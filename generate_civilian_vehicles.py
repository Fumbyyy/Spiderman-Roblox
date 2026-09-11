#!/usr/bin/env python3
"""
generate_civilian_vehicles.py

Standalone Blender 3.6+/4.x script.

Usage:
    blender --background --python generate_civilian_vehicles.py -- \
        --output-dir ./civilian_vehicles

Outputs:
    nyc_yellow_taxi.fbx
    civilian_family_sedan.fbx
    civilian_pickup_truck.fbx
    city_box_delivery_truck.fbx
    urban_compact_hatchback.fbx
    export_report.json

Scale:
    1 Blender unit = 1 Roblox stud.
    No physical-unit/meter conversion is applied.
    FBX apply_unit_scale=False, apply_scale_options='FBX_SCALE_NONE'.

Coordinates:
    Blender authoring coordinates: Z up, front toward positive Y.
    FBX export: -Z forward, Y up.

Pivots:
    Ground center of each vehicle (Z=0), wheels resting exactly on the floor.

Geometry:
    Each vehicle is exported as one combined cohesive mesh.
    All windows are closed, solid, tinted glass surfaces. No interiors.
    All faces are explicitly triangulated and checked after cleanup.
"""

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector


MIN_TRIANGLES = 700
MAX_TRIANGLES = 1400
CLEANUP_DISTANCE = 1.0e-5

MATERIALS = {}


# ---------------------------------------------------------------------------
# Arguments / Scene / Materials
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    parser = argparse.ArgumentParser(
        description="Generate five low-poly NYC civilian vehicles for Roblox."
    )
    parser.add_argument("--output-dir", default="./civilian_vehicles")
    return parser.parse_args(argv)


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)


def configure_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.unit_settings.scale_length = 1.0
    scene.cursor.location = (0.0, 0.0, 0.0)


def ensure_fbx_exporter():
    try:
        bpy.ops.export_scene.fbx.get_rna_type()
        return
    except Exception:
        pass

    try:
        bpy.ops.preferences.addon_enable(module="io_scene_fbx")
        bpy.ops.export_scene.fbx.get_rna_type()
    except Exception as exc:
        raise RuntimeError(
            "The Blender FBX exporter is unavailable. Enable/install "
            "the FBX import-export add-on before running this script."
        ) from exc


def make_material(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)

    mat.use_nodes = True
    mat.diffuse_color = (*color, 1.0)

    nodes = mat.node_tree.nodes
    nodes.clear()

    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.name = "Principled BSDF"
    
    # Robust multi-version support for base shader inputs
    inputs = shader.inputs
    if "Base Color" in inputs:
        inputs["Base Color"].default_value = (*color, 1.0)
    if "Metallic" in inputs:
        inputs["Metallic"].default_value = metallic
    if "Roughness" in inputs:
        inputs["Roughness"].default_value = roughness

    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    MATERIALS[name] = mat


def create_palette():
    make_material("Taxi_Yellow",     (0.90, 0.62, 0.02),  0.15, 0.40)
    make_material("Slate_Blue",       (0.12, 0.22, 0.38),  0.72, 0.36)  # Metallic
    make_material("Crimson_Red",      (0.72, 0.03, 0.08),  0.22, 0.38)
    make_material("Forest_Green",     (0.08, 0.24, 0.12),  0.18, 0.45)
    make_material("Cargo_White",      (0.88, 0.88, 0.88),  0.05, 0.48)
    make_material("Steel_Chrome",     (0.78, 0.78, 0.80),  0.92, 0.18)  # Polished
    make_material("Tire_Rubber",      (0.02, 0.02, 0.03),  0.00, 0.94)
    make_material("Cast_Iron",        (0.06, 0.07, 0.08),  0.42, 0.68)
    make_material("Tinted_Glass",     (0.01, 0.02, 0.04),  0.36, 0.15)
    make_material("Warm_Glow",        (0.98, 0.88, 0.32),  0.00, 0.12)
    make_material("Red_Taillight",    (0.85, 0.02, 0.02),  0.00, 0.22)
    make_material("Slot_Shadow",      (0.005, 0.008, 0.01), 0.00, 0.95)


# ---------------------------------------------------------------------------
# Procedural Mesh Construction (Builder)
# ---------------------------------------------------------------------------

class Builder:
    def __init__(self):
        self.bm = bmesh.new()
        self.material_names = []
        self.material_lookup = {}

    def mat_index(self, name):
        if name not in self.material_lookup:
            self.material_lookup[name] = len(self.material_names)
            self.material_names.append(name)
        return self.material_lookup[name]

    def add(self, vertices, faces, material, transform=None):
        index = self.mat_index(material)

        if transform is None:
            new_vertices = [
                self.bm.verts.new(Vector(co)) for co in vertices
            ]
        else:
            new_vertices = [
                self.bm.verts.new(transform @ Vector(co))
                for co in vertices
            ]

        for indices in faces:
            face = self.bm.faces.new([new_vertices[i] for i in indices])
            face.material_index = index

        return new_vertices

    def box(self, center, size, material, bevel=0.0, rotation=None):
        temporary = bmesh.new()
        try:
            result = bmesh.ops.create_cube(temporary, size=1.0)
            for vertex in result["verts"]:
                for axis in range(3):
                    vertex.co[axis] *= size[axis]

            if bevel > 0.0:
                bmesh.ops.bevel(
                    temporary,
                    geom=list(temporary.edges),
                    offset=min(bevel, min(size) * 0.24),
                    segments=1,
                    affect="EDGES",
                    clamp_overlap=True,
                )

            temporary.verts.ensure_lookup_table()
            temporary.verts.index_update()

            vertices = [v.co.copy() for v in temporary.verts]
            faces = [
                tuple(v.index for v in face.verts)
                for face in temporary.faces
            ]

            rotation = rotation if rotation is not None else Matrix.Identity(3)
            transform = (
                Matrix.Translation(Vector(center)) @ rotation.to_4x4()
            )

            return self.add(vertices, faces, material, transform)
        finally:
            temporary.free()

    def add_sloped_box(self, center, size, material, slope_front_y=0.0, slope_rear_y=0.0, slope_side_x=0.0):
        """
        Creates a custom low-poly box with slopes, perfect for hoods,
        cabins, windshields, and trunks.
        +Y = Front, -Y = Rear, +X = Right, -X = Left, +Z = Up.
        """
        dx, dy, dz = size[0] * 0.5, size[1] * 0.5, size[2] * 0.5
        
        # 8 box corners:
        # Bottom corners
        v0 = Vector((-dx, -dy, -dz))
        v1 = Vector(( dx, -dy, -dz))
        v2 = Vector(( dx,  dy, -dz))
        v3 = Vector((-dx,  dy, -dz))
        
        # Top corners (with slope deflections applied)
        v4 = Vector((-dx + slope_side_x, -dy + slope_rear_y,  dz)) # Top back-left
        v5 = Vector(( dx - slope_side_x, -dy + slope_rear_y,  dz)) # Top back-right
        v6 = Vector(( dx - slope_side_x,  dy - slope_front_y, dz)) # Top front-right
        v7 = Vector((-dx + slope_side_x,  dy - slope_front_y, dz)) # Top front-left

        vertices = [v0, v1, v2, v3, v4, v5, v6, v7]
        faces = [
            (0, 1, 2, 3), # Bottom
            (4, 7, 6, 5), # Top
            (0, 3, 7, 4), # Left
            (1, 5, 6, 2), # Right
            (2, 6, 7, 3), # Front
            (0, 4, 5, 1), # Rear
        ]
        
        return self.add(vertices, faces, material, Matrix.Translation(Vector(center)))

    def beam(self, start, end, width, material, depth=None, bevel=0.0):
        start = Vector(start)
        end = Vector(end)
        delta = end - start

        if delta.length <= 1.0e-7:
            raise ValueError("Zero-length beam.")

        rotation = delta.to_track_quat("Z", "Y").to_matrix()

        return self.box(
            (start + end) * 0.5,
            (width, width if depth is None else depth, delta.length),
            material,
            bevel=bevel,
            rotation=rotation,
        )

    def lathe(self, profile, segments, material, center=(0, 0, 0), axis=(0, 0, 1)):
        """Revolve a closed radial/Z cross-section to build cylinders/wheels."""
        vertices = []
        rings = []

        for radius, height in profile:
            if abs(radius) < 1.0e-10:
                rings.append([len(vertices)])
                vertices.append((0.0, 0.0, height))
            else:
                ring = []
                for i in range(segments):
                    angle = math.tau * i / segments
                    ring.append(len(vertices))
                    vertices.append((
                        radius * math.cos(angle),
                        radius * math.sin(angle),
                        height,
                    ))
                rings.append(ring)

        faces = []
        for row in range(len(rings) - 1):
            a = rings[row]
            b = rings[row + 1]

            for i in range(segments):
                j = (i + 1) % segments
                if len(a) == 1:
                    faces.append((a[0], b[j], b[i]))
                elif len(b) == 1:
                    faces.append((a[i], a[j], b[0]))
                else:
                    faces.append((a[i], a[j], b[j], b[i]))

        rotation = Vector(axis).to_track_quat("Z", "Y").to_matrix()
        transform = (
            Matrix.Translation(Vector(center)) @ rotation.to_4x4()
        )

        return self.add(vertices, faces, material, transform)

    def add_cylinder(self, center, radius, depth, segments, material, axis=(0, 0, 1)):
        half = depth * 0.5
        profile = [
            (0, -half),
            (radius, -half),
            (radius, half),
            (0, half)
        ]
        return self.lathe(profile, segments, material, center=center, axis=axis)

    def add_wheel_assembly(self, x, y, radius, width, rim_mat, tire_mat, spoke_mat, z=None, flare_width=0.35, flare_mat=None):
        """Builds a highly detailed stylized wheel with hubcap spokes and optional fender flares."""
        if z is None:
            z = radius
        # Tire (12 segments for smooth curvature)
        self.add_cylinder((x, y, z), radius, width, 12, tire_mat, axis=(1, 0, 0))
        # Recessed Rim
        rim_offset = 0.08 if x < 0 else -0.08
        self.add_cylinder((x + rim_offset, y, z), radius * 0.65, width * 0.5, 12, rim_mat, axis=(1, 0, 0))
        # Center Spokes (Cross detail)
        spoke_offset = 0.12 if x < 0 else -0.12
        self.box((x + spoke_offset, y, z), (0.05, radius * 0.45, radius * 0.15), spoke_mat)
        self.box((x + spoke_offset, y, z), (0.05, radius * 0.15, radius * 0.45), spoke_mat)
        # Fender Flare
        if flare_mat:
            self.box((x - (0.08 if x < 0 else -0.08), y, z + radius * 0.45), (flare_width, radius * 2.3, radius * 0.8), flare_mat, bevel=0.1)

    def add_side_mirrors(self, cab_y, cab_z, cab_width, material):
        """Adds stylized side mirrors to the cabin flanks."""
        for side in (-1, 1):
            # Mount Arm
            self.beam((side * (cab_width * 0.5), cab_y, cab_z), (side * (cab_width * 0.5 + 0.35), cab_y + 0.1, cab_z), 0.08, material)
            # Mirror Box
            self.box((side * (cab_width * 0.5 + 0.35), cab_y + 0.15, cab_z), (0.12, 0.25, 0.38), material, bevel=0.03)
            # Glass Reflection (offset slightly back for visibility)
            self.box((side * (cab_width * 0.5 + 0.35), cab_y + 0.04, cab_z), (0.02, 0.22, 0.34), "Tinted_Glass")

    def add_license_plate(self, y, z, width, height, is_front, frame_mat, text_mat):
        """Mounts a license plate block."""
        # Frame
        self.box((0, y, z), (width, 0.04, height), frame_mat)
        # Inner Plate
        y_offset = -0.015 if is_front else 0.015
        self.box((0, y + y_offset, z), (width - 0.1, 0.04, height - 0.06), text_mat)

    def add_exhaust_pipe(self, x, y, z, radius, depth, material):
        """Adds a realistic dual-recessed tailpipe."""
        self.add_cylinder((x, y, z), radius, depth, 8, material, axis=(0, 1, 0))
        self.add_cylinder((x, y - 0.02, z), radius * 0.72, depth + 0.01, 8, "Slot_Shadow", axis=(0, 1, 0))


# ---------------------------------------------------------------------------
# Individual Vehicle Builders
# ---------------------------------------------------------------------------

def build_taxi():
    b = Builder()
    # Body
    b.add_sloped_box((0, 0, 1.4), (5.8, 14.2, 1.6), "Taxi_Yellow", slope_front_y=0.4, slope_rear_y=0.4)
    b.add_sloped_box((0, 4.4, 2.5), (5.6, 5.0, 0.8), "Taxi_Yellow", slope_front_y=1.2)
    b.add_sloped_box((0, -4.4, 2.4), (5.6, 5.0, 0.6), "Taxi_Yellow", slope_rear_y=0.8)
    b.add_sloped_box((0, -0.2, 3.4), (5.4, 6.0, 1.4), "Taxi_Yellow", slope_front_y=1.8, slope_rear_y=1.2, slope_side_x=0.4)
    
    # Windows
    b.add_sloped_box((0, 1.4, 3.4), (4.8, 2.2, 1.25), "Tinted_Glass", slope_front_y=1.8, slope_side_x=0.35)
    b.add_sloped_box((0, -2.1, 3.3), (4.8, 2.0, 1.15), "Tinted_Glass", slope_rear_y=1.1, slope_side_x=0.35)
    b.box((2.72, -0.2, 3.4), (0.04, 5.2, 1.0), "Tinted_Glass")
    b.box((-2.72, -0.2, 3.4), (0.04, 5.2, 1.0), "Tinted_Glass")
    
    # Roof fare ad-box
    b.add_sloped_box((0, -0.1, 4.2), (1.6, 2.2, 0.6), "Cargo_White", slope_front_y=0.3, slope_rear_y=0.3)
    b.box((0, -0.1, 4.2), (1.68, 1.8, 0.4), "Taxi_Yellow")
    
    # Chrome bumpers
    b.box((0, 7.2, 1.1), (6.0, 0.4, 0.5), "Steel_Chrome", bevel=0.05)
    b.box((0, -7.2, 1.1), (6.0, 0.4, 0.5), "Steel_Chrome", bevel=0.05)
    
    # Lights
    b.add_cylinder((-2.0, 7.25, 2.5), 0.25, 0.1, 8, "Warm_Glow", axis=(0, 1, 0))
    b.add_cylinder((2.0, 7.25, 2.5), 0.25, 0.1, 8, "Warm_Glow", axis=(0, 1, 0))
    b.box((-2.2, -7.22, 2.4), (0.6, 0.15, 0.3), "Red_Taillight")
    b.box((2.2, -7.22, 2.4), (0.6, 0.15, 0.3), "Red_Taillight")
    
    # Wheels & Flares
    b.add_wheel_assembly(-2.8, 4.2, 0.9, 0.6, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Taxi_Yellow")
    b.add_wheel_assembly(2.8, 4.2, 0.9, 0.6, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Taxi_Yellow")
    b.add_wheel_assembly(-2.8, -4.2, 0.9, 0.6, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Taxi_Yellow")
    b.add_wheel_assembly(2.8, -4.2, 0.9, 0.6, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Taxi_Yellow")
    
    # Details
    b.add_side_mirrors(2.2, 3.2, 5.4, "Taxi_Yellow")
    b.add_license_plate(-7.25, 1.1, 1.2, 0.6, is_front=False, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_license_plate(7.25, 1.1, 1.2, 0.6, is_front=True, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_exhaust_pipe(1.8, -7.2, 0.7, 0.12, 0.5, "Steel_Chrome")
    return b


def build_sedan():
    b = Builder()
    # Body
    b.add_sloped_box((0, 0, 1.3), (5.7, 13.8, 1.5), "Slate_Blue", slope_front_y=0.6, slope_rear_y=0.6)
    b.add_sloped_box((0, 4.2, 2.35), (5.5, 4.8, 0.7), "Slate_Blue", slope_front_y=1.4)
    b.add_sloped_box((0, -4.2, 2.25), (5.5, 4.8, 0.55), "Slate_Blue", slope_rear_y=1.0)
    b.add_sloped_box((0, -0.2, 3.25), (5.3, 5.8, 1.35), "Slate_Blue", slope_front_y=2.1, slope_rear_y=1.6, slope_side_x=0.45)
    
    # Windows
    b.add_sloped_box((0, 1.3, 3.25), (4.7, 2.0, 1.2), "Tinted_Glass", slope_front_y=2.1, slope_side_x=0.4)
    b.add_sloped_box((0, -2.0, 3.2), (4.7, 1.8, 1.1), "Tinted_Glass", slope_rear_y=1.5, slope_side_x=0.4)
    b.box((2.67, -0.2, 3.25), (0.04, 5.0, 0.95), "Tinted_Glass")
    b.box((-2.67, -0.2, 3.25), (0.04, 5.0, 0.95), "Tinted_Glass")
    
    # Chrome bumpers
    b.box((0, 7.0, 1.0), (5.8, 0.4, 0.45), "Steel_Chrome", bevel=0.04)
    b.box((0, -7.0, 1.0), (5.8, 0.4, 0.45), "Steel_Chrome", bevel=0.04)
    
    # Lights
    b.box((-2.1, 6.95, 2.35), (0.6, 0.15, 0.25), "Warm_Glow")
    b.box((2.1, 6.95, 2.35), (0.6, 0.15, 0.25), "Warm_Glow")
    
    # Stylized Taillight Bar
    b.box((0, -7.02, 2.25), (5.2, 0.1, 0.25), "Red_Taillight")
    
    # Wheels & Flares
    b.add_wheel_assembly(-2.75, 4.0, 0.85, 0.55, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Slate_Blue")
    b.add_wheel_assembly(2.75, 4.0, 0.85, 0.55, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Slate_Blue")
    b.add_wheel_assembly(-2.75, -4.0, 0.85, 0.55, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Slate_Blue")
    b.add_wheel_assembly(2.75, -4.0, 0.85, 0.55, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Slate_Blue")
    
    # Details
    b.add_side_mirrors(2.0, 3.1, 5.3, "Slate_Blue")
    b.add_license_plate(-7.05, 1.0, 1.2, 0.6, is_front=False, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_license_plate(7.05, 1.0, 1.2, 0.6, is_front=True, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_exhaust_pipe(1.7, -7.0, 0.65, 0.11, 0.5, "Steel_Chrome")
    return b


def build_pickup():
    b = Builder()
    # Body
    b.add_sloped_box((0, 0, 1.6), (6.2, 15.2, 1.6), "Forest_Green", slope_front_y=0.4, slope_rear_y=0.2)
    b.add_sloped_box((0, 4.8, 2.8), (6.0, 5.2, 0.8), "Forest_Green", slope_front_y=0.8)
    b.add_sloped_box((0, 0.6, 4.1), (5.8, 6.4, 1.8), "Forest_Green", slope_front_y=1.6, slope_rear_y=0.4, slope_side_x=0.35)
    
    # Windows
    b.add_sloped_box((0, 2.0, 4.1), (5.2, 1.8, 1.6), "Tinted_Glass", slope_front_y=1.6, slope_side_x=0.35)
    b.add_sloped_box((0, -1.8, 4.1), (5.2, 1.4, 1.6), "Tinted_Glass", slope_rear_y=0.4, slope_side_x=0.35)
    b.box((2.92, 0.6, 4.1), (0.04, 5.6, 1.3), "Tinted_Glass")
    b.box((-2.92, 0.6, 4.1), (0.04, 5.6, 1.3), "Tinted_Glass")
    
    # Hollow Cargo Bed
    b.box((0, -5.1, 2.1), (5.8, 5.0, 0.4), "Cast_Iron") # Bed Floor
    b.box((-2.9, -5.1, 3.2), (0.4, 5.0, 1.8), "Forest_Green") # Left Wall
    b.box((2.9, -5.1, 3.2), (0.4, 5.0, 1.8), "Forest_Green") # Right Wall
    b.box((0, -2.4, 3.2), (5.4, 0.4, 1.8), "Forest_Green") # Front Bed Wall
    b.box((0, -7.5, 3.2), (5.4, 0.4, 1.8), "Forest_Green") # Tailgate
    
    # Bed floor structural ribbing
    for rx in (-1.8, -0.9, 0.0, 0.9, 1.8):
        b.box((rx, -5.1, 2.35), (0.15, 4.6, 0.1), "Cast_Iron")
        
    # Rugged bumpers
    b.box((0, 7.7, 1.2), (6.4, 0.6, 0.6), "Cast_Iron", bevel=0.06)
    b.box((0, -7.8, 1.2), (6.4, 0.6, 0.6), "Cast_Iron", bevel=0.06)
    
    # Lights
    b.add_cylinder((-2.1, 7.75, 2.8), 0.28, 0.1, 8, "Warm_Glow", axis=(0, 1, 0))
    b.add_cylinder((2.1, 7.75, 2.8), 0.28, 0.1, 8, "Warm_Glow", axis=(0, 1, 0))
    b.box((-2.3, -7.82, 3.0), (0.5, 0.15, 0.35), "Red_Taillight")
    b.box((2.3, -7.82, 3.0), (0.5, 0.15, 0.35), "Red_Taillight")
    
    # High clearance off-road wheels
    b.add_wheel_assembly(-3.1, 4.8, 1.15, 0.7, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Forest_Green")
    b.add_wheel_assembly(3.1, 4.8, 1.15, 0.7, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Forest_Green")
    b.add_wheel_assembly(-3.1, -4.8, 1.15, 0.7, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Forest_Green")
    b.add_wheel_assembly(3.1, -4.8, 1.15, 0.7, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Forest_Green")
    
    # Details
    b.add_side_mirrors(1.2, 4.0, 5.8, "Forest_Green")
    b.add_license_plate(-7.85, 1.2, 1.2, 0.6, is_front=False, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_license_plate(7.85, 1.2, 1.2, 0.6, is_front=True, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_exhaust_pipe(2.0, -7.8, 0.8, 0.15, 0.6, "Steel_Chrome")
    return b


def build_delivery_truck():
    b = Builder()
    # Flat nose cab
    b.add_sloped_box((0, 5.5, 2.4), (6.4, 6.0, 2.0), "Cargo_White", slope_front_y=0.2)
    b.add_sloped_box((0, 5.5, 4.7), (6.2, 5.8, 2.6), "Cargo_White", slope_front_y=0.3, slope_side_x=0.2)
    b.add_sloped_box((0, 7.0, 4.7), (5.8, 1.5, 2.2), "Tinted_Glass", slope_front_y=0.3, slope_side_x=0.15)
    b.box((3.12, 5.5, 4.7), (0.04, 4.2, 1.8), "Tinted_Glass")
    b.box((-3.12, 5.5, 4.7), (0.04, 4.2, 1.8), "Tinted_Glass")
    
    # Roof Fairing
    b.add_sloped_box((0, 5.0, 6.6), (6.0, 4.8, 1.2), "Cargo_White", slope_front_y=3.6)
    
    # Undercarriage rails
    b.box((-1.5, -1.0, 1.4), (0.4, 16.0, 0.8), "Cast_Iron")
    b.box((1.5, -1.0, 1.4), (0.4, 16.0, 0.8), "Cast_Iron")
    
    # Cargo container
    b.box((0, -2.2, 4.8), (6.8, 11.2, 5.8), "Cargo_White")
    b.box((0, -7.85, 4.8), (6.2, 0.1, 5.2), "Steel_Chrome") # Rear frame
    
    # Corrugation ribs
    for y in (-7.2, -5.2, -3.2, -1.2, 0.8, 2.8):
        for side in (-1, 1):
            b.box((side * 3.42, y, 4.8), (0.12, 0.25, 5.6), "Steel_Chrome")
            
    # Bumpers
    b.box((0, 8.6, 1.3), (6.6, 0.6, 0.6), "Steel_Chrome", bevel=0.06)
    b.box((0, -7.9, 1.3), (6.8, 0.6, 0.6), "Steel_Chrome", bevel=0.06)
    
    # Lights
    b.add_cylinder((-2.2, 8.65, 2.4), 0.3, 0.1, 8, "Warm_Glow", axis=(0, 1, 0))
    b.add_cylinder((2.2, 8.65, 2.4), 0.3, 0.1, 8, "Warm_Glow", axis=(0, 1, 0))
    b.box((-2.5, -7.92, 1.8), (0.6, 0.15, 0.4), "Red_Taillight")
    b.box((2.5, -7.92, 1.8), (0.6, 0.15, 0.4), "Red_Taillight")
    
    # Dual axle-size wheels
    b.add_wheel_assembly(-3.2, 5.2, 1.3, 0.8, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Cargo_White")
    b.add_wheel_assembly(3.2, 5.2, 1.3, 0.8, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Cargo_White")
    b.add_wheel_assembly(-3.2, -5.2, 1.3, 0.8, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Cargo_White")
    b.add_wheel_assembly(3.2, -5.2, 1.3, 0.8, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Cargo_White")
    
    # Details
    b.add_side_mirrors(5.5, 4.5, 6.2, "Cargo_White")
    b.add_license_plate(-7.95, 1.3, 1.2, 0.6, is_front=False, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_license_plate(8.65, 1.3, 1.2, 0.6, is_front=True, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_exhaust_pipe(2.0, -7.9, 0.9, 0.18, 0.7, "Steel_Chrome")
    return b


def build_hatchback():
    b = Builder()
    # Body
    b.add_sloped_box((0, 0, 1.2), (5.4, 12.0, 1.4), "Crimson_Red", slope_front_y=0.5, slope_rear_y=0.4)
    b.add_sloped_box((0, 3.6, 2.1), (5.2, 4.4, 0.6), "Crimson_Red", slope_front_y=1.2)
    b.add_sloped_box((0, -0.6, 3.0), (5.0, 5.0, 1.25), "Crimson_Red", slope_front_y=1.8, slope_rear_y=1.6, slope_side_x=0.4)
    
    # Windows
    b.add_sloped_box((0, 0.8, 3.0), (4.4, 1.8, 1.1), "Tinted_Glass", slope_front_y=1.8, slope_side_x=0.35)
    b.add_sloped_box((0, -2.1, 3.0), (4.4, 1.6, 1.1), "Tinted_Glass", slope_rear_y=1.5, slope_side_x=0.35)
    b.box((2.52, -0.6, 3.0), (0.04, 4.2, 0.85), "Tinted_Glass")
    b.box((-2.52, -0.6, 3.0), (0.04, 4.2, 0.85), "Tinted_Glass")
    
    # Compact Bumpers & Foglights
    b.box((0, 6.1, 0.9), (5.4, 0.35, 0.4), "Cast_Iron", bevel=0.03)
    b.box((0, -6.1, 0.9), (5.4, 0.35, 0.4), "Cast_Iron", bevel=0.03)
    b.add_cylinder((-1.8, 6.2, 0.9), 0.15, 0.08, 8, "Warm_Glow", axis=(0, 1, 0))
    b.add_cylinder((1.8, 6.2, 0.9), 0.15, 0.08, 8, "Warm_Glow", axis=(0, 1, 0))
    
    # Lights
    b.box((-1.9, 6.05, 2.1), (0.5, 0.1, 0.2), "Warm_Glow")
    b.box((1.9, 6.05, 2.1), (0.5, 0.1, 0.2), "Warm_Glow")
    b.box((-1.9, -6.12, 2.1), (0.4, 0.1, 0.2), "Red_Taillight")
    b.box((1.9, -6.12, 2.1), (0.4, 0.1, 0.2), "Red_Taillight")
    
    # Wheels & Flares
    b.add_wheel_assembly(-2.55, 3.4, 0.75, 0.5, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Crimson_Red")
    b.add_wheel_assembly(2.55, 3.4, 0.75, 0.5, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Crimson_Red")
    b.add_wheel_assembly(-2.55, -3.4, 0.75, 0.5, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Crimson_Red")
    b.add_wheel_assembly(2.55, -3.4, 0.75, 0.5, "Steel_Chrome", "Tire_Rubber", "Steel_Chrome", flare_mat="Crimson_Red")
    
    # Details
    b.add_side_mirrors(1.2, 2.8, 5.0, "Crimson_Red")
    b.add_license_plate(-6.15, 0.9, 1.2, 0.6, is_front=False, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_license_plate(6.15, 0.9, 1.2, 0.6, is_front=True, frame_mat="Cast_Iron", text_mat="Warm_Glow")
    b.add_exhaust_pipe(1.5, -6.1, 0.6, 0.1, 0.4, "Steel_Chrome")
    return b


# ---------------------------------------------------------------------------
# Dimension Fitting, Pivots, Cleanup, and Validation
# ---------------------------------------------------------------------------

def bounds(coordinates):
    coordinates = list(coordinates)
    if not coordinates:
        raise RuntimeError("No geometry found to measure.")

    minimum = Vector(tuple(
        min(co[axis] for co in coordinates) for axis in range(3)
    ))
    maximum = Vector(tuple(
        max(co[axis] for co in coordinates) for axis in range(3)
    ))
    return minimum, maximum


def fit_dimensions_and_pivot(builder, target_dimensions):
    """
    Fits construction geometry to exact target dimensions in studs
    and places the pivot at bottom ground center (Z=0).
    """
    minimum, maximum = bounds(v.co for v in builder.bm.verts)
    dimensions = maximum - minimum

    if min(dimensions) <= 1.0e-7:
        raise RuntimeError("Degenerate construction bounds.")

    factors = Vector(tuple(
        target_dimensions[i] / dimensions[i] for i in range(3)
    ))

    # Apply precise scaling
    for vertex in builder.bm.verts:
        for axis in range(3):
            vertex.co[axis] *= factors[axis]

    # Re-evaluate scaled bounds
    minimum, maximum = bounds(v.co for v in builder.bm.verts)

    # Offset to center X, Y, and set bottom wheels exactly at Z=0
    offset = Vector((
        (minimum.x + maximum.x) * 0.5,
        (minimum.y + maximum.y) * 0.5,
        minimum.z,
    ))

    for vertex in builder.bm.verts:
        vertex.co -= offset


def cleanup_and_validate(builder, asset_name):
    bm = builder.bm

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # Explicit triangulation and degenerate face dissolution
    bmesh.ops.triangulate(
        bm,
        faces=list(bm.faces),
        quad_method="BEAUTY",
        ngon_method="EAR_CLIP",
    )
    bmesh.ops.dissolve_degenerate(
        bm,
        dist=1e-5,
        edges=list(bm.edges),
    )

    # Repeat triangulation step if cleanup altered polygon topology
    if any(len(face.verts) != 3 for face in bm.faces):
        bmesh.ops.triangulate(
            bm,
            faces=list(bm.faces),
            quad_method="BEAUTY",
            ngon_method="EAR_CLIP",
        )
        bmesh.ops.dissolve_degenerate(
            bm,
            dist=1e-5,
            edges=list(bm.edges),
        )

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    if any(len(face.verts) != 3 for face in bm.faces):
        raise RuntimeError(asset_name + ": non-triangle faces remain.")

    minimum_area = math.inf
    minimum_altitude = math.inf

    for face in bm.faces:
        area = face.calc_area()
        if not math.isfinite(area) or area <= 1.0e-12:
            raise RuntimeError(asset_name + ": degenerate face remains.")

        longest_edge = max(edge.calc_length() for edge in face.edges)
        altitude = 2.0 * area / longest_edge

        if altitude <= CLEANUP_DISTANCE:
            raise RuntimeError(
                asset_name + ": triangle below sliver tolerance remains."
            )

        minimum_area = min(minimum_area, area)
        minimum_altitude = min(minimum_altitude, altitude)

    if any(edge.calc_length() <= CLEANUP_DISTANCE for edge in bm.edges):
        raise RuntimeError(asset_name + ": near-zero edge remains.")

    triangles = len(bm.faces)
    if not MIN_TRIANGLES <= triangles <= MAX_TRIANGLES:
        raise RuntimeError(
            f"{asset_name}: {triangles} triangles; must fall within "
            f"[{MIN_TRIANGLES}, {MAX_TRIANGLES}]."
        )

    return {
        "triangle_count": triangles,
        "degenerate_faces": 0,
        "minimum_triangle_area_studs_squared": minimum_area,
        "minimum_triangle_altitude_studs": minimum_altitude,
    }


def create_mesh_object(name, builder):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    builder.bm.to_mesh(mesh)
    mesh.update()

    for material_name in builder.material_names:
        mesh.materials.append(MATERIALS[material_name])

    # Clean up and consolidate material slots
    used = sorted({polygon.material_index for polygon in mesh.polygons})
    remap = {old: new for new, old in enumerate(used)}
    used_materials = [mesh.materials[index] for index in used]
    final_indices = [
        remap[polygon.material_index] for polygon in mesh.polygons
    ]

    mesh.materials.clear()
    for mat in used_materials:
        mesh.materials.append(mat)

    for polygon, index in zip(mesh.polygons, final_indices):
        polygon.material_index = index
        polygon.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    obj.matrix_world = Matrix.Identity(4)
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)

    return obj


# ---------------------------------------------------------------------------
# Reporting / FBX Export
# ---------------------------------------------------------------------------

def rounded_vector(vector):
    return [round(float(component), 7) for component in vector]


def material_report(obj):
    slots = []
    for index, mat in enumerate(obj.data.materials):
        shader = mat.node_tree.nodes["Principled BSDF"]
        
        # Safe extraction for multi-version base values
        base_color = shader.inputs["Base Color"].default_value
        metallic = shader.inputs["Metallic"].default_value
        roughness = shader.inputs["Roughness"].default_value

        slots.append({
            "slot": index,
            "name": mat.name,
            "base_color_rgba": [round(float(value), 6) for value in base_color],
            "metallic": round(float(metallic), 6),
            "roughness": round(float(roughness), 6),
            "triangle_count": sum(
                polygon.material_index == index
                for polygon in obj.data.polygons
            ),
        })
    return slots


def export_fbx(obj, filepath):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.context.view_layer.update()

    result = bpy.ops.export_scene.fbx(
        filepath=filepath,
        check_existing=False,
        use_selection=True,
        object_types={"MESH"},

        global_scale=1.0,
        apply_unit_scale=False,
        apply_scale_options="FBX_SCALE_NONE",

        axis_forward="-Z",
        axis_up="Y",
        use_space_transform=True,
        bake_space_transform=True,

        use_mesh_modifiers=True,
        mesh_smooth_type="FACE",
        use_tspace=False,
        use_custom_props=True,

        add_leaf_bones=False,
        bake_anim=False,
        path_mode="AUTO",
        embed_textures=False,
    )

    if "FINISHED" not in result or not os.path.isfile(filepath):
        raise RuntimeError("FBX export failed: " + filepath)


# ---------------------------------------------------------------------------
# Main Driver
# ---------------------------------------------------------------------------

VEHICLES = [
    {
        "name": "nyc_yellow_taxi",
        "builder": build_taxi,
        "dimensions": (6.6, 15.0, 5.0), # Width, Length, Height
    },
    {
        "name": "civilian_family_sedan",
        "builder": build_sedan,
        "dimensions": (6.5, 14.5, 4.8),
    },
    {
        "name": "civilian_pickup_truck",
        "builder": build_pickup,
        "dimensions": (7.0, 16.0, 5.6),
    },
    {
        "name": "city_box_delivery_truck",
        "builder": build_delivery_truck,
        "dimensions": (7.2, 18.5, 7.8),
    },
    {
        "name": "urban_compact_hatchback",
        "builder": build_hatchback,
        "dimensions": (6.2, 12.8, 4.6),
    },
]


def main():
    args = parse_args()
    output_dir = os.path.abspath(os.path.expanduser(args.output_dir))
    os.makedirs(output_dir, exist_ok=True)

    clear_scene()
    configure_scene()
    ensure_fbx_exporter()
    create_palette()

    report = {
        "generator": "generate_civilian_vehicles.py",
        "blender_version": bpy.app.version_string,
        "scale_standard": {
            "blender_units_per_roblox_stud": 1.0,
            "meter_conversion_applied": False,
        },
        "coordinate_convention": {
            "report_axes": "Blender XYZ; Z up; front toward positive Y",
            "fbx_axis_forward": "-Z",
            "fbx_axis_up": "Y",
        },
        "triangle_budget": [MIN_TRIANGLES, MAX_TRIANGLES],
        "export_settings": {
            "apply_unit_scale": False,
            "apply_scale_options": "FBX_SCALE_NONE",
            "global_scale": 1.0,
            "mesh_smooth_type": "FACE",
        },
        "assets": [],
    }

    for spec in VEHICLES:
        print(f"\n[Build] {spec['name']}")
        builder = spec["builder"]()
        obj = None

        try:
            fit_dimensions_and_pivot(builder, spec["dimensions"])
            validation = cleanup_and_validate(builder, spec["name"])
            obj = create_mesh_object(spec["name"], builder)

            minimum, maximum = bounds(v.co for v in obj.data.vertices)
            dimensions = maximum - minimum

            # Strict dimension verification
            if any(
                abs(dimensions[i] - spec["dimensions"][i]) > 1.0e-5
                for i in range(3)
            ):
                raise RuntimeError(spec["name"] + ": dimension fitting verification failed.")

            # Ground pivot verification
            if abs(minimum.z) > 1.0e-6:
                raise RuntimeError(spec["name"] + ": ground pivot alignment verification failed.")

            obj["asset_name"] = spec["name"]
            obj["units"] = "1 Blender unit = 1 Roblox stud"
            obj["triangle_count"] = validation["triangle_count"]
            obj["pivot"] = "Bottom-center ground contact at (0, 0, 0)"

            filepath = os.path.join(output_dir, spec["name"] + ".fbx")
            export_fbx(obj, filepath)

            report["assets"].append({
                "name": spec["name"],
                "file": os.path.basename(filepath),
                "mesh_objects": 1,
                "triangle_count": validation["triangle_count"],
                "bounding_box_studs": {
                    "minimum_xyz": rounded_vector(minimum),
                    "maximum_xyz": rounded_vector(maximum),
                    "dimensions_xyz": rounded_vector(dimensions),
                },
                "pivot": {
                    "position": [0.0, 0.0, 0.0],
                    "description": "Ground center, wheels resting on floor Z=0.",
                },
                "transform": {
                    "location": [0.0, 0.0, 0.0],
                    "rotation_euler": [0.0, 0.0, 0.0],
                    "scale": [1.0, 1.0, 1.0],
                },
                "validation": validation,
                "material_slots": material_report(obj),
            })

            print(
                f"  {validation['triangle_count']} triangles | "
                f"{rounded_vector(dimensions)} studs"
            )
            print(f"  Exported: {filepath}")

        finally:
            builder.bm.free()

            if obj is not None:
                # Caching reference BEFORE removing the object to avoid StructRNA ReferenceError
                mesh_data = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)

                if mesh_data.users == 0:
                    bpy.data.meshes.remove(mesh_data)

    report_path = os.path.join(output_dir, "export_report.json")
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print("\n[Done] All five civilian vehicles exported successfully.")
    print(f"[Report] {report_path}")
    print("[Scale] 1 Blender unit = 1 Roblox stud; no unit conversion factor.")


if __name__ == "__main__":
    main()
