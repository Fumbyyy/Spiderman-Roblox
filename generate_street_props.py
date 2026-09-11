#!/usr/bin/env python3
"""
generate_street_props.py

Standalone Blender 3.6+/4.x script.

Usage:
    blender --background --python generate_street_props.py -- \
        --output-dir ./street_props

Outputs:
    nypd_sawhorse_barricade.fbx
    nyc_street_lamp.fbx
    vintage_payphone_kiosk.fbx
    traffic_hazard_cones.fbx
    electrical_hazard_box.fbx
    export_report.json

Scale:
    1 Blender unit = 1 Roblox stud.
    No meter conversion is applied.
    FBX apply_unit_scale=False, apply_scale_options='FBX_SCALE_NONE'.

Coordinates:
    Blender authoring coordinates: Z up, front toward negative Y.
    FBX export: -Z forward, Y up.

Pivots:
    Ground props: horizontal bounding-box center, bottom at Z=0.
    Electrical box: rear mounting plane at Y=0, centered in X/Z.

Geometry:
    Each exported asset is one combined mesh.
    Construction components intentionally intersect where assembled.
    All faces are explicitly triangulated and checked after cleanup.
    No external images, textures, fonts, or Python dependencies.

Roblox:
    Import with a unit scale of one stud per source unit.
    Principled material slots/base colors are exported. Roblox may require
    separate Material/SurfaceAppearance settings, and lamp lighting should
    be implemented with Roblox lights rather than relying on FBX emission.
"""

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Matrix, Vector


MIN_TRIANGLES = 500
MAX_TRIANGLES = 1400
CLEANUP_DISTANCE = 1.0e-5

MATERIALS = {}


# ---------------------------------------------------------------------------
# Arguments / scene / materials
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    parser = argparse.ArgumentParser(
        description="Generate five stylized Roblox street props."
    )
    parser.add_argument("--output-dir", default="./street_props")
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


def make_material(name, color, metallic=0.0, roughness=0.5, emission=0.0):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)

    mat.use_nodes = True
    mat.diffuse_color = (*color, 1.0)

    nodes = mat.node_tree.nodes
    nodes.clear()

    shader = nodes.new("ShaderNodeBsdfPrincipled")
    shader.name = "Principled BSDF"
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness

    emission_color = shader.inputs.get("Emission Color")
    if emission_color is None:
        emission_color = shader.inputs.get("Emission")
    if emission_color is not None:
        emission_color.default_value = (*color, 1.0)

    emission_strength = shader.inputs.get("Emission Strength")
    if emission_strength is not None:
        emission_strength.default_value = emission

    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    MATERIALS[name] = mat


def create_palette():
    make_material("Police_Blue",      (0.020, 0.095, 0.36), 0.25, 0.47)
    make_material("Reflective_White", (0.91, 0.94, 0.92),   0.15, 0.28)
    make_material("Safety_Orange",    (1.00, 0.19, 0.012), 0.00, 0.48)
    make_material("Cast_Iron",        (0.035, 0.045, 0.055), 0.72, 0.66)
    make_material("Iron_Edge",        (0.12, 0.15, 0.18),   0.78, 0.43)
    make_material("Steel",            (0.43, 0.50, 0.56),   0.83, 0.38)
    make_material("Steel_Dark",       (0.14, 0.19, 0.23),   0.74, 0.55)
    make_material("Brass",            (0.66, 0.42, 0.12),   0.80, 0.36)
    make_material("Industrial_Olive", (0.28, 0.33, 0.24),   0.48, 0.65)
    make_material("Olive_Shadow",     (0.13, 0.17, 0.13),   0.40, 0.74)
    make_material("Rubber",           (0.018, 0.023, 0.029), 0.00, 0.94)
    make_material("Slot_Shadow",      (0.006, 0.012, 0.018), 0.00, 0.89)
    make_material("Warning_Yellow",   (1.00, 0.69, 0.025),  0.10, 0.48)
    make_material("Switch_Red",       (0.65, 0.025, 0.020), 0.12, 0.47)
    make_material("Luminary_Glass",   (0.50, 0.84, 1.00),   0.05, 0.22, 3.0)


# ---------------------------------------------------------------------------
# Mesh construction
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

    def prism(self, polygon, center, depth, material, axis=(0, -1, 0)):
        """Extruded 2D polygon with its thickness along the requested axis."""
        count = len(polygon)
        vertices = [
            (x, y, z)
            for z in (-depth / 2, depth / 2)
            for x, y in polygon
        ]

        faces = [
            tuple(reversed(range(count))),
            tuple(range(count, count * 2)),
        ]

        for i in range(count):
            j = (i + 1) % count
            faces.append((i, j, count + j, count + i))

        rotation = Vector(axis).to_track_quat("Z", "Y").to_matrix()
        transform = (
            Matrix.Translation(Vector(center)) @ rotation.to_4x4()
        )

        return self.add(vertices, faces, material, transform)

    def rectangular_ring(self, center, width, height, border, depth,
                         material, axis=(0, -1, 0)):
        """Rectangular frame with an actual through-opening."""
        outer = [
            (-width / 2, -height / 2),
            ( width / 2, -height / 2),
            ( width / 2,  height / 2),
            (-width / 2,  height / 2),
        ]
        inner = [
            (-width / 2 + border, -height / 2 + border),
            ( width / 2 - border, -height / 2 + border),
            ( width / 2 - border,  height / 2 - border),
            (-width / 2 + border,  height / 2 - border),
        ]

        vertices = []
        for z in (-depth / 2, depth / 2):
            vertices.extend((x, y, z) for x, y in outer)
            vertices.extend((x, y, z) for x, y in inner)

        faces = []
        for i in range(4):
            j = (i + 1) % 4
            faces.extend([
                (i, 4 + i, 4 + j, j),
                (8 + i, 8 + j, 12 + j, 12 + i),
                (i, j, 8 + j, 8 + i),
                (4 + j, 4 + i, 12 + i, 12 + j),
            ])

        rotation = Vector(axis).to_track_quat("Z", "Y").to_matrix()
        transform = (
            Matrix.Translation(Vector(center)) @ rotation.to_4x4()
        )
        return self.add(vertices, faces, material, transform)

    def lathe(self, profile, segments, material, center=(0, 0, 0),
              axis=(0, 0, 1), band_materials=None, deform=None, phase=0.0):
        """
        Revolve a closed radial/Z profile.

        Profile runs from bottom inside/axis outward, upward, then inward.
        Radius-zero entries create single poles, avoiding degenerate quads.
        band_materials maps profile segment indices to material names.
        """
        vertices = []
        rings = []

        for row, (radius, height) in enumerate(profile):
            if abs(radius) < 1.0e-10:
                rings.append([len(vertices)])
                vertices.append((0.0, 0.0, height))
            else:
                ring = []
                for i in range(segments):
                    angle = phase + math.tau * i / segments
                    r, z = radius, height
                    if deform is not None:
                        r, z = deform(row, i, r, z)

                    ring.append(len(vertices))
                    vertices.append((
                        r * math.cos(angle),
                        r * math.sin(angle),
                        z,
                    ))
                rings.append(ring)

        faces = []
        face_materials = []

        for row in range(len(rings)):
            a = rings[row]
            c = rings[(row + 1) % len(rings)]

            if len(a) == 1 and len(c) == 1:
                continue

            mat = (
                band_materials.get(row, material)
                if band_materials else material
            )

            for i in range(segments):
                j = (i + 1) % segments
                if len(a) == 1:
                    face = (a[0], c[j], c[i])
                elif len(c) == 1:
                    face = (a[i], a[j], c[0])
                else:
                    face = (a[i], a[j], c[j], c[i])

                faces.append(face)
                face_materials.append(mat)

        rotation = Vector(axis).to_track_quat("Z", "Y").to_matrix()
        transform = (
            Matrix.Translation(Vector(center)) @ rotation.to_4x4()
        )

        new_vertices = [
            self.bm.verts.new(transform @ Vector(co)) for co in vertices
        ]
        for indices, mat in zip(faces, face_materials):
            face = self.bm.faces.new([new_vertices[i] for i in indices])
            face.material_index = self.mat_index(mat)

        return new_vertices

    def cylinder(self, center, radius, depth, segments, material,
                 axis=(0, 0, 1)):
        half = depth * 0.5
        return self.lathe(
            [(0, -half), (radius, -half), (radius, half), (0, half)],
            segments, material, center=center, axis=axis,
        )

    def ring(self, center, outer, inner, depth, segments, material,
             axis=(0, 0, 1)):
        half = depth * 0.5
        return self.lathe(
            [(inner, -half), (outer, -half),
             (outer, half), (inner, half)],
            segments, material, center=center, axis=axis,
        )

    def tube(self, points, radius, sides, material):
        """Closed polygonal tube following a polyline."""
        points = [Vector(point) for point in points]
        if len(points) < 2:
            raise ValueError("Tube requires at least two points.")

        vertices = []

        for i, point in enumerate(points):
            if i == 0:
                tangent = points[1] - point
            elif i == len(points) - 1:
                tangent = point - points[i - 1]
            else:
                tangent = points[i + 1] - points[i - 1]

            if tangent.length <= 1.0e-7:
                raise ValueError("Invalid tube tangent.")

            tangent.normalize()
            reference = Vector((0, 0, 1))
            if abs(tangent.dot(reference)) > 0.92:
                reference = Vector((0, 1, 0))

            u = tangent.cross(reference).normalized()
            v = tangent.cross(u).normalized()

            for j in range(sides):
                angle = math.tau * j / sides
                vertices.append(
                    point + radius * (
                        math.cos(angle) * u + math.sin(angle) * v
                    )
                )

        faces = [tuple(reversed(range(sides)))]

        for row in range(len(points) - 1):
            for i in range(sides):
                j = (i + 1) % sides
                faces.append((
                    row * sides + i,
                    row * sides + j,
                    (row + 1) * sides + j,
                    (row + 1) * sides + i,
                ))

        last = (len(points) - 1) * sides
        faces.append(tuple(last + i for i in range(sides)))

        return self.add(vertices, faces, material)


# ---------------------------------------------------------------------------
# 1. NYPD sawhorse barricade
# ---------------------------------------------------------------------------

def build_barricade():
    b = Builder()

    # Two A-frame trestles.
    for x in (-1.52, 1.52):
        for side in (-1, 1):
            b.beam(
                (x, side * 0.56, 0.10),
                (x, side * 0.04, 2.35),
                0.19, "Steel_Dark", bevel=0.026,
            )
            b.box(
                (x, side * 0.56, 0.07),
                (0.40, 0.30, 0.14), "Rubber",
            )

        b.beam(
            (x, -0.43, 0.69), (x, 0.43, 0.69),
            0.12, "Steel", bevel=0.018,
        )
        b.beam(
            (x, -0.25, 1.45), (x, 0.25, 1.45),
            0.11, "Steel", bevel=0.016,
        )

    b.box(
        (0, 0, 2.37), (4.6, 0.26, 0.60),
        "Police_Blue", bevel=0.036,
    )
    b.box(
        (0, 0.01, 0.95), (3.20, 0.16, 0.24),
        "Police_Blue", bevel=0.027,
    )

    # Shallow solid diagonal reflective inlays, not coplanar decals.
    stripe = [
        (-0.19, -0.265),
        ( 0.03, -0.265),
        ( 0.25,  0.265),
        ( 0.03,  0.265),
    ]
    for side in (-1, 1):
        for x in (-1.86, -1.20, -0.54, 0.54, 1.20, 1.86):
            b.prism(
                stripe, (x, side * 0.139, 2.37),
                0.018, "Reflective_White",
                axis=(0, side, 0),
            )

    # Stylized police shield plates on both sides.
    shield = [
        (-0.27, 0.24), (-0.29, -0.07),
        (0.0, -0.31), (0.29, -0.07), (0.27, 0.24),
    ]
    for side in (-1, 1):
        b.prism(
            shield, (0, side * 0.17, 2.39),
            0.055, "Steel", axis=(0, side, 0),
        )
        b.prism(
            [(x * 0.70, y * 0.70) for x, y in shield],
            (0, side * 0.204, 2.39),
            0.016, "Police_Blue", axis=(0, side, 0),
        )

    for x in (-1.52, 1.52):
        for z in (0.96, 2.37):
            for side in (-1, 1):
                b.cylinder(
                    (x, side * 0.16, z), 0.052, 0.035, 6,
                    "Steel", axis=(0, side, 0),
                )

    return b


# ---------------------------------------------------------------------------
# 2. Cast-iron NYC street lamp
# ---------------------------------------------------------------------------

def build_street_lamp():
    b = Builder()

    # Alternating radii create eight flutes around an octagonal base.
    def base_fluting(row, i, radius, height):
        if row in (4, 5):
            radius *= 1.0 if i % 2 == 0 else 0.88
        return radius, height

    b.lathe(
        [
            (0, 0), (0.64, 0), (0.68, 0.09), (0.68, 0.25),
            (0.44, 0.36), (0.39, 1.03), (0.28, 1.24), (0, 1.24),
        ],
        16, "Cast_Iron", deform=base_fluting,
        band_materials={1: "Iron_Edge", 2: "Iron_Edge", 5: "Iron_Edge"},
    )

    # Integrated stepped collars around a long tapered shaft.
    b.lathe(
        [
            (0, 1.10), (0.24, 1.10),
            (0.24, 1.38), (0.155, 1.45),
            (0.13, 8.76), (0.21, 8.82),
            (0.21, 9.02), (0.145, 9.08),
            (0.145, 10.62), (0, 10.62),
        ],
        12, "Cast_Iron",
        band_materials={1: "Iron_Edge", 4: "Iron_Edge", 5: "Brass"},
    )

    # Arched gooseneck, terminating over the hanging acorn lantern.
    b.tube(
        [
            (0.0, 0, 10.45),
            (0.02, 0, 11.00),
            (0.30, 0, 11.38),
            (0.79, 0, 11.55),
            (1.27, 0, 11.36),
            (1.52, 0, 10.98),
            (1.52, 0, 10.65),
        ],
        0.12, 8, "Cast_Iron",
    )

    lantern_x = 1.52

    b.lathe(
        [
            (0, 9.00), (0.10, 9.00), (0.23, 9.18),
            (0.33, 9.32), (0.29, 9.40), (0, 9.40),
        ],
        8, "Iron_Edge", center=(lantern_x, 0, 0),
    )

    b.lathe(
        [
            (0, 9.24), (0.22, 9.24), (0.38, 9.55),
            (0.41, 10.08), (0.31, 10.30), (0, 10.30),
        ],
        12, "Luminary_Glass", center=(lantern_x, 0, 0),
    )

    # Four structural lantern cage ribs.
    for angle in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
        b.beam(
            (lantern_x + 0.26 * math.cos(angle),
             0.26 * math.sin(angle), 9.31),
            (lantern_x + 0.39 * math.cos(angle),
             0.39 * math.sin(angle), 10.28),
            0.048, "Cast_Iron",
        )

    b.lathe(
        [
            (0, 10.25), (0.47, 10.25), (0.47, 10.34),
            (0.29, 10.53), (0.10, 10.68), (0, 10.68),
        ],
        12, "Cast_Iron", center=(lantern_x, 0, 0),
        band_materials={1: "Iron_Edge"},
    )

    # Top perch finial over the shaft.
    b.lathe(
        [
            (0, 11.10), (0.15, 11.10), (0.21, 11.38),
            (0.11, 11.74), (0.055, 11.88), (0, 11.88),
        ],
        8, "Brass",
    )

    for x in (-0.39, 0.39):
        for y in (-0.39, 0.39):
            b.cylinder((x, y, 0.265), 0.065, 0.07, 6, "Steel")

    return b


# ---------------------------------------------------------------------------
# 3. Vintage payphone
# ---------------------------------------------------------------------------

def build_payphone():
    b = Builder()

    b.box((0, 0, 0.13), (1.46, 1.12, 0.26), "Steel_Dark", bevel=0.045)
    b.box((0, 0.10, 1.91), (0.46, 0.47, 3.50), "Steel_Dark", bevel=0.035)

    b.box(
        (0, 0.07, 4.27), (1.30, 0.65, 2.33),
        "Steel", bevel=0.055,
    )
    b.box(
        (0.21, -0.279, 4.42), (0.74, 0.07, 1.31),
        "Steel_Dark", bevel=0.017,
    )

    # Twelve proud push-buttons.
    for row in range(4):
        for column in range(3):
            b.box(
                (0.21 + (column - 1) * 0.17,
                 -0.338, 4.59 - row * 0.18),
                (0.125, 0.065, 0.125), "Steel",
            )

    # Coin drop and return frames with recessed dark inserts.
    b.rectangular_ring(
        (0.23, -0.31, 5.04),
        0.39, 0.14, 0.028, 0.09, "Brass",
    )
    b.box(
        (0.23, -0.295, 5.04), (0.34, 0.03, 0.095), "Slot_Shadow"
    )

    b.rectangular_ring(
        (0.23, -0.315, 3.62),
        0.41, 0.25, 0.043, 0.10, "Steel_Dark",
    )
    b.box(
        (0.23, -0.292, 3.62), (0.33, 0.035, 0.17), "Slot_Shadow"
    )

    # Receiver handset with separate chunky earpiece/mouthpiece.
    b.tube(
        [
            (-0.43, -0.47, 4.95),
            (-0.55, -0.53, 4.79),
            (-0.57, -0.56, 4.49),
            (-0.53, -0.53, 4.18),
            (-0.42, -0.47, 4.02),
        ],
        0.095, 6, "Rubber",
    )

    for z in (4.98, 3.99):
        b.box(
            (-0.43, -0.46, z), (0.31, 0.24, 0.25),
            "Rubber", bevel=0.040,
        )
        b.box(
            (-0.44, -0.325, z), (0.29, 0.12, 0.08),
            "Steel_Dark",
        )

    # Actual three-turn polygonal coiled cord.
    cord_points = []
    for i in range(25):
        angle = math.tau * 3.0 * i / 24.0
        cord_points.append((
            -0.40 + 0.060 * math.cos(angle),
            -0.42 + 0.060 * math.sin(angle),
            3.99 - 0.68 * i / 24.0,
        ))
    b.tube(cord_points, 0.019, 4, "Rubber")

    # Side shielding and curved overhead acoustic hood.
    for x in (-0.86, 0.86):
        b.box(
            (x, -0.05, 4.57), (0.10, 1.24, 2.05),
            "Police_Blue",
        )

    # An arch-shaped solid profile extruded along Y.
    arch_polygon = []
    steps = 8
    for i in range(steps + 1):
        angle = math.pi * i / steps
        arch_polygon.append((
            0.91 * math.cos(angle),
            5.48 + 0.59 * math.sin(angle),
        ))
    for i in range(steps, -1, -1):
        angle = math.pi * i / steps
        arch_polygon.append((
            0.80 * math.cos(angle),
            5.48 + 0.48 * math.sin(angle),
        ))

    b.prism(
        arch_polygon, (0, -0.05, 0), 1.24,
        "Police_Blue", axis=(0, -1, 0),
    )

    b.box(
        (0, -0.715, 5.45), (1.56, 0.08, 0.28),
        "Reflective_White", bevel=0.017,
    )

    # Four visible service fasteners.
    for x in (-0.54, 0.54):
        for z in (3.25, 5.25):
            b.cylinder(
                (x, -0.28, z), 0.035, 0.035, 6,
                "Steel_Dark", axis=(0, -1, 0),
            )

    return b


# ---------------------------------------------------------------------------
# 4. Upright and knocked traffic cones
# ---------------------------------------------------------------------------

def add_cone(b, tilt, horizontal_offset):
    before = set(b.bm.verts)

    b.box(
        (0, 0, 0.105), (1.13, 1.13, 0.21),
        "Rubber", bevel=0.045,
    )

    # Hollow mouth with a short inner bore; integral alternating bands.
    profile = [
        (0, 0.15),
        (0.53, 0.15),
        (0.53, 0.22),
        (0.46, 0.29),
        (0.39, 0.60),
        (0.34, 0.83),
        (0.27, 1.10),
        (0.22, 1.33),
        (0.14, 1.72),
        (0.09, 1.75),
        (0.055, 1.75),
        (0.055, 1.58),
        (0, 1.58),
    ]

    b.lathe(
        profile, 12, "Safety_Orange",
        band_materials={
            4: "Reflective_White",
            6: "Reflective_White",
            10: "Slot_Shadow",
            11: "Slot_Shadow",
        },
    )

    new_vertices = [vertex for vertex in b.bm.verts if vertex not in before]
    rotation = (
        Matrix.Rotation(math.radians(-18), 3, "Z")
        @ Matrix.Rotation(tilt, 3, "Y")
    )

    for vertex in new_vertices:
        vertex.co = rotation @ vertex.co

    minimum_z = min(vertex.co.z for vertex in new_vertices)
    for vertex in new_vertices:
        vertex.co.x += horizontal_offset[0]
        vertex.co.y += horizontal_offset[1]
        vertex.co.z -= minimum_z


def build_cones():
    b = Builder()
    add_cone(b, 0.0, (-0.63, -0.20))
    add_cone(b, math.radians(72), (0.46, 0.43))
    return b


# ---------------------------------------------------------------------------
# 5. Wall-mounted electrical hazard cabinet
# ---------------------------------------------------------------------------

def build_electrical_box():
    b = Builder()

    b.box(
        (0, -0.33, 0), (1.67, 0.66, 1.89),
        "Industrial_Olive", bevel=0.065,
    )
    b.box(
        (0, -0.70, 0), (1.51, 0.13, 1.71),
        "Olive_Shadow", bevel=0.045,
    )

    # Four rear mounting ears. Their backs define the mounting plane.
    for x in (-0.83, 0.83):
        for z in (-0.71, 0.71):
            b.box(
                (x, -0.045, z), (0.28, 0.09, 0.27),
                "Steel_Dark",
            )

    # Top and bottom conduit runs.
    for sign in (-1, 1):
        points = [
            (sign * 0.43, -0.20, sign * 0.84),
            (sign * 0.43, -0.20, sign * 1.16),
            (sign * 0.62, -0.16, sign * 1.43),
        ]
        b.tube(points, 0.080, 8, "Steel_Dark")

        for z in (sign * 0.94, sign * 1.10):
            b.ring(
                (sign * 0.43, -0.20, z),
                0.12, 0.078, 0.105, 8, "Steel",
            )

    # Heavy door latch handle.
    for z in (-0.16, 0.16):
        b.beam(
            (0.57, -0.76, z), (0.57, -0.94, z),
            0.085, "Steel", bevel=0.012,
        )
    b.beam(
        (0.57, -0.94, -0.16), (0.57, -0.94, 0.16),
        0.095, "Steel", bevel=0.014,
    )

    # Recessed master switch backing, lever, and safety-red grip.
    b.box(
        (-0.48, -0.81, -0.33), (0.35, 0.12, 0.49),
        "Steel_Dark", bevel=0.025,
    )
    b.beam(
        (-0.48, -0.87, -0.40),
        (-0.48, -1.10, -0.13),
        0.077, "Steel", bevel=0.010,
    )
    b.box(
        (-0.48, -1.10, -0.13), (0.25, 0.12, 0.105),
        "Switch_Red", bevel=0.018,
    )

    # Six stamped front ventilation louvers.
    for i in range(6):
        b.box(
            (0.06, -0.782, -0.56 + i * 0.083),
            (0.43, 0.045, 0.035), "Steel_Dark",
        )

    b.box(
        (-0.06, -0.784, 0.43), (0.79, 0.035, 0.56),
        "Warning_Yellow", bevel=0.014,
    )

    # Solid black lightning/chevron warning graphic.
    lightning = [
        (-0.03, 0.23),
        (-0.22, -0.03),
        (-0.05, -0.03),
        (-0.12, -0.24),
        (0.21, 0.07),
        (0.04, 0.07),
        (0.13, 0.23),
    ]
    b.prism(
        lightning, (-0.06, -0.81, 0.43),
        0.016, "Slot_Shadow",
    )

    # Exposed door hinges.
    for z in (-0.58, 0.58):
        b.cylinder(
            (-0.75, -0.73, z), 0.060, 0.29, 8, "Steel"
        )

    return b


# ---------------------------------------------------------------------------
# Dimension fitting, pivots, cleanup, and validation
# ---------------------------------------------------------------------------

def bounds(coordinates):
    coordinates = list(coordinates)
    if not coordinates:
        raise RuntimeError("Cannot measure empty geometry.")

    minimum = Vector(tuple(
        min(co[axis] for co in coordinates) for axis in range(3)
    ))
    maximum = Vector(tuple(
        max(co[axis] for co in coordinates) for axis in range(3)
    ))
    return minimum, maximum


def fit_dimensions_and_pivot(builder, target_dimensions, pivot):
    minimum, maximum = bounds(v.co for v in builder.bm.verts)
    dimensions = maximum - minimum

    if min(dimensions) <= 1.0e-7:
        raise RuntimeError("Degenerate asset dimensions.")

    # Shape fitting in stud units, NOT a physical-unit conversion.
    factors = Vector(tuple(
        target_dimensions[i] / dimensions[i] for i in range(3)
    ))

    for vertex in builder.bm.verts:
        for axis in range(3):
            vertex.co[axis] *= factors[axis]

    minimum, maximum = bounds(v.co for v in builder.bm.verts)

    if pivot == "GROUND":
        offset = Vector((
            (minimum.x + maximum.x) * 0.5,
            (minimum.y + maximum.y) * 0.5,
            minimum.z,
        ))
    elif pivot == "WALL":
        offset = Vector((
            (minimum.x + maximum.x) * 0.5,
            maximum.y,
            (minimum.z + maximum.z) * 0.5,
        ))
    else:
        raise ValueError("Unknown pivot mode: " + pivot)

    for vertex in builder.bm.verts:
        vertex.co -= offset


def cleanup_and_validate(builder, asset_name):
    bm = builder.bm

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # Required ordered operations.
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

    # If cleanup changed polygon topology, repeat the same ordered pair.
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

    if any(not edge.is_manifold for edge in bm.edges):
        raise RuntimeError(
            asset_name + ": open/non-manifold construction component."
        )

    if any(not vertex.link_faces for vertex in bm.verts):
        raise RuntimeError(asset_name + ": loose vertices remain.")

    if any(
        not math.isfinite(component)
        for vertex in bm.verts
        for component in vertex.co
    ):
        raise RuntimeError(asset_name + ": invalid vertex coordinates.")

    triangles = len(bm.faces)
    if not MIN_TRIANGLES < triangles < MAX_TRIANGLES:
        raise RuntimeError(
            f"{asset_name}: {triangles} triangles; required strictly "
            f"between {MIN_TRIANGLES} and {MAX_TRIANGLES}."
        )

    return {
        "triangle_count": triangles,
        "degenerate_faces": 0,
        "minimum_triangle_area_studs_squared": minimum_area,
        "minimum_triangle_altitude_studs": minimum_altitude,
        "closed_construction_components": True,
    }


def create_mesh_object(name, builder):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    builder.bm.to_mesh(mesh)
    mesh.update()

    for material_name in builder.material_names:
        mesh.materials.append(MATERIALS[material_name])

    # Compact slots to the materials actually used by the final mesh.
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

    if any(len(poly.vertices) != 3 for poly in mesh.polygons):
        raise RuntimeError(name + ": output mesh is not triangulated.")

    return obj


# ---------------------------------------------------------------------------
# Reporting / FBX export
# ---------------------------------------------------------------------------

def rounded_vector(vector):
    return [round(float(component), 7) for component in vector]


def material_report(obj):
    slots = []
    for index, mat in enumerate(obj.data.materials):
        shader = mat.node_tree.nodes["Principled BSDF"]
        strength = shader.inputs.get("Emission Strength")

        slots.append({
            "slot": index,
            "name": mat.name,
            "base_color_rgba": [
                round(float(value), 6)
                for value in shader.inputs["Base Color"].default_value
            ],
            "metallic": round(
                float(shader.inputs["Metallic"].default_value), 6
            ),
            "roughness": round(
                float(shader.inputs["Roughness"].default_value), 6
            ),
            "emission_strength": (
                round(float(strength.default_value), 6)
                if strength is not None else 0.0
            ),
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

    if obj.location.length > 1.0e-8:
        raise RuntimeError("Object location is not zero.")
    if any(abs(value) > 1.0e-8 for value in obj.rotation_euler):
        raise RuntimeError("Object rotation is not zero.")
    if any(abs(value - 1.0) > 1.0e-8 for value in obj.scale):
        raise RuntimeError("Object scale is not identity.")

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


ASSETS = [
    {
        "name": "nypd_sawhorse_barricade",
        "builder": build_barricade,
        "dimensions": (4.6, 1.4, 2.8),
        "pivot": "GROUND",
        "pivot_description": "Ground center, bottom at Z=0.",
    },
    {
        "name": "nyc_street_lamp",
        "builder": build_street_lamp,
        "dimensions": (2.8, 1.6, 12.5),
        "pivot": "GROUND",
        "pivot_description": "Ground center, bottom base plate at Z=0.",
    },
    {
        "name": "vintage_payphone_kiosk",
        "builder": build_payphone,
        "dimensions": (2.2, 2.0, 6.4),
        "pivot": "GROUND",
        "pivot_description": "Ground center, pedestal foot at Z=0.",
    },
    {
        "name": "traffic_hazard_cones",
        "builder": build_cones,
        "dimensions": (2.4, 1.8, 2.2),
        "pivot": "GROUND",
        "pivot_description": "Combined assembly ground center, Z=0.",
    },
    {
        "name": "electrical_hazard_box",
        "builder": build_electrical_box,
        "dimensions": (2.2, 1.2, 3.0),
        "pivot": "WALL",
        "pivot_description": (
            "Rear mounting plane at Y=0, centered in X/Z; "
            "cabinet projects toward negative Y."
        ),
    },
]


# ---------------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------------

def main():
    args = parse_args()
    output_dir = os.path.abspath(os.path.expanduser(args.output_dir))
    os.makedirs(output_dir, exist_ok=True)

    clear_scene()
    configure_scene()
    ensure_fbx_exporter()
    create_palette()

    report = {
        "generator": "generate_street_props.py",
        "blender_version": bpy.app.version_string,
        "scale_standard": {
            "blender_units_per_roblox_stud": 1.0,
            "meter_conversion_applied": False,
        },
        "coordinate_convention": {
            "report_axes": "Blender XYZ; Z up; front toward -Y",
            "fbx_axis_forward": "-Z",
            "fbx_axis_up": "Y",
        },
        "triangle_budget_exclusive": [MIN_TRIANGLES, MAX_TRIANGLES],
        "export_settings": {
            "apply_unit_scale": False,
            "apply_scale_options": "FBX_SCALE_NONE",
            "global_scale": 1.0,
            "mesh_smooth_type": "FACE",
        },
        "assets": [],
    }

    for spec in ASSETS:
        print(f"\n[Build] {spec['name']}")
        builder = spec["builder"]()
        obj = None

        try:
            fit_dimensions_and_pivot(
                builder, spec["dimensions"], spec["pivot"]
            )
            validation = cleanup_and_validate(builder, spec["name"])
            obj = create_mesh_object(spec["name"], builder)

            minimum, maximum = bounds(v.co for v in obj.data.vertices)
            dimensions = maximum - minimum

            if any(
                abs(dimensions[i] - spec["dimensions"][i]) > 1.0e-5
                for i in range(3)
            ):
                raise RuntimeError(spec["name"] + ": dimension check failed.")

            if spec["pivot"] == "GROUND" and abs(minimum.z) > 1.0e-6:
                raise RuntimeError(spec["name"] + ": incorrect ground pivot.")
            if spec["pivot"] == "WALL" and abs(maximum.y) > 1.0e-6:
                raise RuntimeError(spec["name"] + ": incorrect wall pivot.")

            obj["asset_name"] = spec["name"]
            obj["units"] = "1 Blender unit = 1 Roblox stud"
            obj["triangle_count"] = validation["triangle_count"]
            obj["pivot_description"] = spec["pivot_description"]

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
                    "description": spec["pivot_description"],
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
                # Cache mesh BEFORE removing the Object.
                # Never access obj.data after bpy.data.objects.remove().
                mesh_data = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)

                if mesh_data.users == 0:
                    bpy.data.meshes.remove(mesh_data)

    report_path = os.path.join(output_dir, "export_report.json")
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print("\n[Done] All five street props exported.")
    print(f"[Report] {report_path}")
    print("[Scale] 1 Blender unit = 1 Roblox stud; no meter conversion.")


if __name__ == "__main__":
    main()
