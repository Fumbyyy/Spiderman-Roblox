#!/usr/bin/env python3
"""
generate_spidey_gadgets.py

Blender 3.6+/4.x/5.x script for generating Spider-Man gadgets and pickups.

Usage:
    blender --background --python generate_spidey_gadgets.py -- \
        --output-dir ./spidey_gadgets

Outputs:
    web_shooter_bracer.fbx
    web_bomb_canister.fbx
    spider_tracer_dart.fbx
    classic_pizza_box.fbx
    webbed_backpack.fbx
    export_report.json

Coordinate / scale convention:
    - 1 Blender unit = 1 Roblox stud.
    - No meter conversion is applied.
    - Blender authoring coordinates: Z up.
    - FBX: -Z forward, Y up.
    - Every exported asset is a single mesh with identity transforms.
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

PALETTE = {}


# ---------------------------------------------------------------------------
# Arguments / scene
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    parser = argparse.ArgumentParser(
        description="Generate five stylized Spider-Man gadgets and pickups."
    )
    parser.add_argument("--output-dir", default="./spidey_gadgets")
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
    units = bpy.context.scene.unit_settings
    units.system = "NONE"
    units.scale_length = 1.0

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)


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
            "Blender's FBX exporter is unavailable. Enable/install "
            "the FBX import-export add-on before running this script."
        ) from exc


# ---------------------------------------------------------------------------
# Constant-color materials
# ---------------------------------------------------------------------------

def material(name, color, metallic=0.0, roughness=0.5, emission=0.0):
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

    emission_input = shader.inputs.get("Emission Color")
    if emission_input is None:
        emission_input = shader.inputs.get("Emission")

    if emission_input is not None:
        emission_input.default_value = (*color, 1.0)

    strength_input = shader.inputs.get("Emission Strength")
    if strength_input is not None:
        strength_input.default_value = emission

    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    PALETTE[name] = mat
    return mat


def create_palette():
    material("Hero_Red",       (0.72, 0.025, 0.040), 0.42, 0.36)
    material("Red_Shadow",     (0.26, 0.012, 0.022), 0.36, 0.53)
    material("Gunmetal",       (0.055, 0.075, 0.105), 0.82, 0.43)
    material("Steel",          (0.40, 0.49, 0.59), 0.88, 0.30)
    material("Brass",          (0.76, 0.44, 0.10), 0.78, 0.36)
    material("Rubber",         (0.016, 0.024, 0.038), 0.00, 0.88)
    material("Electric_Blue",  (0.015, 0.43, 1.00), 0.25, 0.23, 2.5)
    material("Scanner_Cyan",   (0.06, 0.85, 1.00), 0.18, 0.19, 3.0)
    material("Canvas_Blue",    (0.035, 0.095, 0.22), 0.00, 0.92)
    material("Canvas_Red",     (0.42, 0.045, 0.045), 0.00, 0.88)
    material("Canvas_Seam",    (0.14, 0.23, 0.36), 0.00, 0.86)
    material("Web_White",      (0.89, 0.95, 1.00), 0.05, 0.47)
    material("Cardboard",      (0.62, 0.39, 0.18), 0.00, 0.92)
    material("Cardboard_Edge", (0.34, 0.18, 0.066), 0.00, 0.96)
    material("Pizza_Cream",    (0.94, 0.79, 0.46), 0.00, 0.86)
    material("Print_Red",      (0.78, 0.035, 0.020), 0.00, 0.83)
    material("Print_Green",    (0.035, 0.33, 0.11), 0.00, 0.86)


# ---------------------------------------------------------------------------
# Mesh construction
# ---------------------------------------------------------------------------

class Builder:
    """Accumulates disconnected, closed construction components in a BMesh."""

    def __init__(self):
        self.bm = bmesh.new()
        self.material_names = []
        self.material_indices = {}

    def mat_index(self, name):
        if name not in PALETTE:
            raise KeyError("Unknown material: " + name)

        if name not in self.material_indices:
            self.material_indices[name] = len(self.material_names)
            self.material_names.append(name)

        return self.material_indices[name]

    def add(self, vertices, faces, mat, transform=None):
        index = self.mat_index(mat)

        if transform is None:
            new_vertices = [
                self.bm.verts.new(Vector(co)) for co in vertices
            ]
        else:
            new_vertices = [
                self.bm.verts.new(transform @ Vector(co))
                for co in vertices
            ]

        for face in faces:
            polygon = self.bm.faces.new([new_vertices[i] for i in face])
            polygon.material_index = index

        return new_vertices

    def box(self, center, size, mat, bevel=0.0, rotation=None):
        temporary = bmesh.new()
        try:
            result = bmesh.ops.create_cube(temporary, size=1.0)

            for vertex in result["verts"]:
                vertex.co.x *= size[0]
                vertex.co.y *= size[1]
                vertex.co.z *= size[2]

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

            rot = rotation if rotation is not None else Matrix.Identity(3)
            transform = Matrix.Translation(Vector(center)) @ rot.to_4x4()

            return self.add(vertices, faces, mat, transform)
        finally:
            temporary.free()

    def beam(self, start, end, width, mat, thickness=None, bevel=0.0):
        start = Vector(start)
        end = Vector(end)
        delta = end - start

        if delta.length < 1.0e-7:
            raise ValueError("Attempted to construct a zero-length beam.")

        rotation = delta.to_track_quat("Z", "Y").to_matrix()
        return self.box(
            (start + end) * 0.5,
            (width, width if thickness is None else thickness, delta.length),
            mat,
            bevel=bevel,
            rotation=rotation,
        )

    def lathe(self, profile, segments, mat, center=(0, 0, 0),
              axis=(0, 0, 1), scale=(1, 1, 1), phase=0.0):
        vertices = []
        rings = []

        for radius, height in profile:
            if abs(radius) < 1.0e-10:
                rings.append([len(vertices)])
                vertices.append((0.0, 0.0, height))
            else:
                ring = []
                for i in range(segments):
                    angle = phase + math.tau * i / segments
                    ring.append(len(vertices))
                    vertices.append((
                        radius * math.cos(angle),
                        radius * math.sin(angle),
                        height,
                    ))
                rings.append(ring)

        faces = []

        for ring_index in range(len(rings)):
            a = rings[ring_index]
            b = rings[(ring_index + 1) % len(rings)]

            if len(a) == 1 and len(b) == 1:
                continue

            for i in range(segments):
                j = (i + 1) % segments

                if len(a) == 1:
                    face = (a[0], b[j], b[i])
                elif len(b) == 1:
                    face = (a[i], a[j], b[0])
                else:
                    face = (a[i], a[j], b[j], b[i])

                faces.append(face)

        rotation = Vector(axis).to_track_quat("Z", "Y").to_matrix()
        scale_matrix = Matrix.Diagonal((*scale, 1.0))
        transform = (
            Matrix.Translation(Vector(center))
            @ rotation.to_4x4()
            @ scale_matrix
        )
        return self.add(vertices, faces, mat, transform)

    def cylinder(self, center, radius, depth, segments, mat,
                 axis=(0, 0, 1)):
        half = depth * 0.5
        return self.lathe(
            [(0, -half), (radius, -half), (radius, half), (0, half)],
            segments, mat, center=center, axis=axis,
        )

    def chamfer_cylinder(self, center, radius, depth, segments, mat,
                         axis=(0, 0, 1)):
        half = depth * 0.5
        chamfer = min(radius * 0.15, depth * 0.18)
        return self.lathe(
            [
                (0, -half),
                (radius - chamfer, -half),
                (radius, -half + chamfer),
                (radius, half - chamfer),
                (radius - chamfer, half),
                (0, half),
            ],
            segments, mat, center=center, axis=axis,
        )

    def ring(self, center, outer, inner, depth, segments, mat,
             axis=(0, 0, 1)):
        half = depth * 0.5
        return self.lathe(
            [
                (inner, -half),
                (outer, -half),
                (outer, half),
                (inner, half),
            ],
            segments, mat, center=center, axis=axis,
        )

    def sphere(self, center, radius, segments, latitude_steps, mat):
        profile = [(0.0, -radius)]

        for j in range(1, latitude_steps):
            latitude = -math.pi / 2 + math.pi * j / latitude_steps
            profile.append((
                radius * math.cos(latitude),
                radius * math.sin(latitude),
            ))

        profile.append((0.0, radius))
        return self.lathe(profile, segments, mat, center=center)

    def tube(self, points, radius, sides, mat):
        points = [Vector(point) for point in points]
        if len(points) < 2:
            raise ValueError("A tube needs at least two points.")

        vertices = []

        for i, point in enumerate(points):
            if i == 0:
                tangent = points[1] - point
            elif i == len(points) - 1:
                tangent = point - points[i - 1]
            else:
                tangent = points[i + 1] - points[i - 1]

            if tangent.length < 1.0e-7:
                raise ValueError("Invalid tube tangent.")

            tangent.normalize()
            reference = Vector((0, 0, 1))
            if abs(tangent.dot(reference)) > 0.92:
                reference = Vector((0, 1, 0))

            u = tangent.cross(reference).normalized()
            v = tangent.cross(u).normalized()

            for j in range(sides):
                angle = math.tau * j / sides
                co = point + radius * (
                    math.cos(angle) * u + math.sin(angle) * v
                )
                vertices.append(co)

        faces = [tuple(reversed(range(sides)))]

        for i in range(len(points) - 1):
            for j in range(sides):
                k = (j + 1) % sides
                faces.append((
                    i * sides + j,
                    i * sides + k,
                    (i + 1) * sides + k,
                    (i + 1) * sides + j,
                ))

        last = (len(points) - 1) * sides
        faces.append(tuple(last + j for j in range(sides)))

        return self.add(vertices, faces, mat)

    def octahedron(self, center, radius, mat):
        vertices = [
            (radius, 0, 0), (-radius, 0, 0),
            (0, radius, 0), (0, -radius, 0),
            (0, 0, radius), (0, 0, -radius),
        ]
        faces = [
            (4, 0, 2), (4, 2, 1), (4, 1, 3), (4, 3, 0),
            (5, 2, 0), (5, 1, 2), (5, 3, 1), (5, 0, 3),
        ]
        return self.add(
            vertices, faces, mat, Matrix.Translation(Vector(center))
        )


# ---------------------------------------------------------------------------
# 1. Web shooter bracer
# ---------------------------------------------------------------------------

def build_web_shooter():
    b = Builder()

    for z in (-0.49, 0.49):
        b.ring(
            (0, 0, z), 0.57, 0.47, 0.19, 20,
            "Red_Shadow",
        )

    for x in (-0.39, 0.39):
        for y in (-0.34, 0.34):
            b.box((x, y, 0), (0.10, 0.10, 1.15), "Gunmetal")

    b.box(
        (0, -0.49, 0.06), (0.58, 0.25, 1.16),
        "Hero_Red", bevel=0.045,
    )

    b.chamfer_cylinder(
        (0, -0.64, 0.03), 0.19, 0.93, 16, "Steel"
    )
    b.ring(
        (0, -0.64, -0.32), 0.205, 0.18, 0.09, 12, "Brass"
    )

    b.lathe(
        [
            (0.052, -0.12),
            (0.115, -0.12),
            (0.145, -0.075),
            (0.145, 0.085),
            (0.115, 0.12),
            (0.052, 0.12),
        ],
        10, "Gunmetal", center=(0, -0.64, 0.67),
    )

    trigger_path = [
        (0.20, -0.50, 0.41),
        (0.30, -0.26, 0.53),
        (0.23, 0.05, 0.68),
        (0.00, 0.18, 0.73),
    ]
    for start, end in zip(trigger_path, trigger_path[1:]):
        b.beam(start, end, 0.035, "Brass")

    for x in (-0.52, 0.52):
        for z in (-0.49, 0.49):
            b.box(
                (x, 0.0, z), (0.15, 0.27, 0.23),
                "Hero_Red", bevel=0.022,
            )

    return b


# ---------------------------------------------------------------------------
# 2. Impact-web bomb
# ---------------------------------------------------------------------------

def spherical_point(radius, longitude, latitude):
    return (
        radius * math.cos(latitude) * math.cos(longitude),
        radius * math.cos(latitude) * math.sin(longitude),
        radius * math.sin(latitude),
    )


def build_web_bomb():
    b = Builder()

    b.sphere((0, 0, 0), 0.355, 12, 6, "Electric_Blue")

    longitude_count = 12
    latitude_edges = [-65, -32.5, 0, 32.5, 65]

    for row in range(4):
        low = math.radians(latitude_edges[row] + 2.6)
        high = math.radians(latitude_edges[row + 1] - 2.6)

        for column in range(longitude_count):
            a = math.tau * column / longitude_count + 0.037
            c = math.tau * (column + 1) / longitude_count - 0.037

            vertices = []
            for radius in (0.395, 0.455):
                vertices.extend([
                    spherical_point(radius, a, low),
                    spherical_point(radius, c, low),
                    spherical_point(radius, c, high),
                    spherical_point(radius, a, high),
                ])

            faces = [
                (0, 3, 2, 1), (4, 5, 6, 7),
                (0, 1, 5, 4), (1, 2, 6, 5),
                (2, 3, 7, 6), (3, 0, 4, 7),
            ]

            tile_mat = "Hero_Red" if column % 4 == 0 else "Steel"
            b.add(vertices, faces, tile_mat)

    for i in range(3):
        angle = math.tau * i / 3.0 + math.pi / 6.0
        x = 0.425 * math.cos(angle)
        y = 0.425 * math.sin(angle)

        b.chamfer_cylinder(
            (x, y, 0), 0.060, 0.37, 8, "Scanner_Cyan"
        )
        for z in (-0.195, 0.195):
            b.cylinder((x, y, z), 0.075, 0.065, 8, "Brass")

    b.chamfer_cylinder(
        (0, 0, 0.445), 0.17, 0.16, 10, "Gunmetal"
    )
    b.cylinder((0, 0, 0.54), 0.090, 0.045, 8, "Scanner_Cyan")

    return b


# ---------------------------------------------------------------------------
# 3. Spider tracer
# ---------------------------------------------------------------------------

def build_spider_tracer():
    b = Builder()

    b.chamfer_cylinder(
        (0, 0, 0.075), 0.205, 0.12, 16, "Hero_Red"
    )
    b.cylinder((0, 0, 0.013), 0.174, 0.026, 12, "Rubber")

    b.chamfer_cylinder(
        (0, 0, 0.149), 0.105, 0.058, 16, "Scanner_Cyan"
    )
    b.ring(
        (0, 0, 0.137), 0.137, 0.107, 0.043, 16, "Brass"
    )

    for side in (-1, 1):
        for i, y in enumerate((-0.15, -0.05, 0.05, 0.15)):
            spread = (-0.18, -0.09, 0.09, 0.18)[i]

            root = (side * 0.14, y * 0.65, 0.078)
            elbow = (side * 0.27, y + spread * 0.30, 0.079)
            tip = (side * (0.35 if i in (0, 3) else 0.39),
                   y + spread, 0.045)

            b.beam(root, elbow, 0.026, "Steel", thickness=0.018)
            b.beam(elbow, tip, 0.020, "Gunmetal", thickness=0.016)
            b.octahedron(tip, 0.024, "Electric_Blue")

    return b


# ---------------------------------------------------------------------------
# 4. Classic pizza box
# ---------------------------------------------------------------------------

def build_pizza_box():
    b = Builder()

    b.box(
        (0, 0, 0.035), (2.34, 2.34, 0.07),
        "Cardboard", bevel=0.014,
    )
    b.box(
        (0, 0, 0.445), (2.40, 2.40, 0.09),
        "Cardboard", bevel=0.017,
    )

    for x in (-1.13, 1.13):
        b.box((x, 0, 0.235), (0.08, 2.23, 0.33), "Cardboard")

    for y in (-1.13, 1.13):
        b.box(
            (0, y, 0.20), (2.20, 0.08, 0.27), "Cardboard"
        )

        for i in range(5):
            x = (i - 2) * 0.445
            b.box(
                (x, y, 0.367), (0.365, 0.08, 0.066),
                "Cardboard_Edge",
            )

    for x in (-1.045, 1.045):
        for y in (-1.045, 1.045):
            rotation = Matrix.Rotation(
                math.radians(45 if x * y > 0 else -45), 3, "Z"
            )
            b.box(
                (x, y, 0.415), (0.235, 0.135, 0.08),
                "Cardboard_Edge", bevel=0.012, rotation=rotation,
            )

    for y, mat in ((-0.88, "Print_Red"), (0.88, "Print_Green")):
        b.box((0, y, 0.494), (1.68, 0.095, 0.008), mat)

    for x, mat in ((-0.88, "Print_Green"), (0.88, "Print_Red")):
        b.box((x, 0, 0.494), (0.095, 1.48, 0.008), mat)

    b.cylinder((0, 0, 0.495), 0.65, 0.010, 12, "Print_Red")
    b.cylinder((0, 0, 0.503), 0.56, 0.010, 12, "Pizza_Cream")

    for i in range(5):
        angle = math.tau * i / 5.0 + 0.3
        b.cylinder(
            (0.32 * math.cos(angle),
             0.32 * math.sin(angle), 0.511),
            0.083, 0.008, 6, "Print_Red",
        )

    return b


# ---------------------------------------------------------------------------
# 5. Webbed backpack
# ---------------------------------------------------------------------------

def build_backpack():
    b = Builder()

    b.lathe(
        [
            (0.0, 0.08),
            (0.47, 0.08),
            (0.62, 0.20),
            (0.67, 0.70),
            (0.63, 1.48),
            (0.50, 1.84),
            (0.34, 1.97),
            (0.0, 1.97),
        ],
        12, "Canvas_Blue",
        center=(0, -0.05, 0),
        scale=(1.0, 0.65, 1.0),
        phase=math.pi / 12,
    )

    b.box(
        (0, -0.50, 0.68), (0.97, 0.29, 0.65),
        "Canvas_Red", bevel=0.085,
    )
    b.box(
        (0.0, -0.405, 1.37), (0.72, 0.15, 0.34),
        "Canvas_Blue", bevel=0.045,
    )

    for side in (-1, 1):
        b.tube(
            [
                (side * 0.32, 0.23, 1.72),
                (side * 0.45, 0.49, 1.48),
                (side * 0.47, 0.52, 0.89),
                (side * 0.35, 0.40, 0.40),
                (side * 0.27, 0.20, 0.25),
            ],
            0.065, 6, "Canvas_Seam",
        )
        b.box(
            (side * 0.35, 0.405, 0.48),
            (0.15, 0.10, 0.20), "Brass", bevel=0.017,
        )

    b.tube(
        [
            (-0.49, -0.535, 0.36),
            (-0.50, -0.555, 0.86),
            (-0.40, -0.555, 0.99),
            (0.40, -0.555, 0.99),
            (0.49, -0.535, 0.36),
        ],
        0.017, 4, "Canvas_Seam",
    )
    b.tube(
        [
            (-0.48, -0.30, 1.30),
            (-0.46, -0.34, 1.70),
            (0.00, -0.37, 1.85),
            (0.46, -0.34, 1.70),
            (0.48, -0.30, 1.30),
        ],
        0.017, 4, "Gunmetal",
    )

    for i in range(10):
        b.box(
            ((i - 4.5) * 0.078, -0.660, 0.87),
            (0.045, 0.016, 0.027), "Brass",
        )

    b.tube(
        [
            (-0.20, 0.03, 1.85),
            (-0.19, 0.035, 2.10),
            (0.19, 0.035, 2.10),
            (0.20, 0.03, 1.85),
        ],
        0.046, 6, "Canvas_Seam",
    )

    center = Vector((0.0, 0.38, 1.02))
    anchors = []
    middle_points = []

    for i in range(8):
        angle = math.tau * i / 8.0
        anchor = Vector((
            0.90 * math.cos(angle),
            0.72,
            1.08 + 1.08 * math.sin(angle),
        ))
        middle = center.lerp(anchor, 0.59)
        middle.y = 0.56

        anchors.append(anchor)
        middle_points.append(middle)

        b.tube(
            [center, middle, anchor],
            0.029, 5, "Web_White",
        )

    for i in range(8):
        b.tube(
            [middle_points[i], middle_points[(i + 1) % 8]],
            0.023, 5, "Web_White",
        )

    return b


# ---------------------------------------------------------------------------
# Dimensions, pivot placement, cleanup, and validation
# ---------------------------------------------------------------------------

def bm_bounds(bm):
    if not bm.verts:
        raise RuntimeError("Cannot measure an empty mesh.")

    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))

    for vertex in bm.verts:
        for axis in range(3):
            minimum[axis] = min(minimum[axis], vertex.co[axis])
            maximum[axis] = max(maximum[axis], vertex.co[axis])

    return minimum, maximum


def fit_dimensions_and_pivot(bm, dimensions, pivot_mode):
    minimum, maximum = bm_bounds(bm)
    current = maximum - minimum

    if min(current) <= 1.0e-7:
        raise RuntimeError("Degenerate asset bounding box.")

    scale = Vector(tuple(dimensions[i] / current[i] for i in range(3)))

    for vertex in bm.verts:
        for axis in range(3):
            vertex.co[axis] *= scale[axis]

    minimum, maximum = bm_bounds(bm)

    if pivot_mode == "WRIST":
        offset = Vector((0.0, 0.0, 0.0))

    elif pivot_mode in {"GROUND", "MAGNET"}:
        offset = Vector((
            (minimum.x + maximum.x) * 0.5,
            (minimum.y + maximum.y) * 0.5,
            minimum.z,
        ))

    elif pivot_mode == "WALL":
        offset = Vector((
            (minimum.x + maximum.x) * 0.5,
            maximum.y,
            (minimum.z + maximum.z) * 0.5,
        ))

    else:
        raise ValueError("Unknown pivot mode: " + pivot_mode)

    for vertex in bm.verts:
        vertex.co -= offset


def triangulate_cleanup_validate(bm, name):
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    bmesh.ops.triangulate(
        bm,
        faces=list(bm.faces),
        quad_method="BEAUTY",
        ngon_method="EAR_CLIP",
    )
    bmesh.ops.dissolve_degenerate(
        bm,
        dist=CLEANUP_DISTANCE,
        edges=list(bm.edges),
    )

    if any(len(face.verts) != 3 for face in bm.faces):
        bmesh.ops.triangulate(
            bm,
            faces=list(bm.faces),
            quad_method="BEAUTY",
            ngon_method="EAR_CLIP",
        )
        bmesh.ops.dissolve_degenerate(
            bm,
            dist=CLEANUP_DISTANCE,
            edges=list(bm.edges),
        )

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    if any(len(face.verts) != 3 for face in bm.faces):
        raise RuntimeError(name + ": non-triangle faces after cleanup.")

    degenerate_faces = [
        face for face in bm.faces
        if not math.isfinite(face.calc_area()) or face.calc_area() <= 1.0e-12
    ]
    if degenerate_faces:
        raise RuntimeError(
            f"{name}: {len(degenerate_faces)} degenerate faces remain."
        )

    if any(edge.calc_length() < CLEANUP_DISTANCE for edge in bm.edges):
        raise RuntimeError(name + ": an edge below cleanup tolerance remains.")

    if any(not vertex.link_faces for vertex in bm.verts):
        raise RuntimeError(name + ": loose vertices remain.")

    if any(not edge.is_manifold for edge in bm.edges):
        raise RuntimeError(
            name + ": an open/non-manifold construction component remains."
        )

    if any(
        not math.isfinite(component)
        for vertex in bm.verts for component in vertex.co
    ):
        raise RuntimeError(name + ": invalid vertex coordinates.")

    triangles = len(bm.faces)

    if not MIN_TRIANGLES < triangles < MAX_TRIANGLES:
        raise RuntimeError(
            f"{name}: {triangles} triangles; expected strictly between "
            f"{MIN_TRIANGLES} and {MAX_TRIANGLES}."
        )

    return triangles


def create_object(name, builder):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    builder.bm.to_mesh(mesh)
    mesh.update()

    for name_in_palette in builder.material_names:
        mesh.materials.append(PALETTE[name_in_palette])

    for polygon in mesh.polygons:
        polygon.use_smooth = False

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    obj.matrix_world = Matrix.Identity(4)
    obj.location = (0.0, 0.0, 0.0)
    obj.rotation_euler = (0.0, 0.0, 0.0)
    obj.scale = (1.0, 1.0, 1.0)

    if any(len(p.vertices) != 3 for p in mesh.polygons):
        raise RuntimeError(name + ": output mesh is not fully triangulated.")

    return obj


def object_bounds(obj):
    vertices = [vertex.co for vertex in obj.data.vertices]
    minimum = Vector(tuple(
        min(vertex[axis] for vertex in vertices) for axis in range(3)
    ))
    maximum = Vector(tuple(
        max(vertex[axis] for vertex in vertices) for axis in range(3)
    ))
    return minimum, maximum


def rounded_vector(value):
    return [round(float(component), 7) for component in value]


def material_report(obj):
    result = []

    for index, mat in enumerate(obj.data.materials):
        shader = mat.node_tree.nodes.get("Principled BSDF")
        strength = shader.inputs.get("Emission Strength")

        result.append({
            "slot": index,
            "name": mat.name,
            "base_color_rgba": [
                round(float(v), 6)
                for v in shader.inputs["Base Color"].default_value
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
            "triangles_using_slot": sum(
                polygon.material_index == index
                for polygon in obj.data.polygons
            ),
        })

    return result


# ---------------------------------------------------------------------------
# FBX export
# ---------------------------------------------------------------------------

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
# Main
# ---------------------------------------------------------------------------

ASSETS = [
    {
        "name": "web_shooter_bracer",
        "builder": build_web_shooter,
        "dimensions": (1.4, 1.4, 1.6),
        "pivot_mode": "WRIST",
        "pivot_description": "Wrist attachment center; wrist axis is Z.",
    },
    {
        "name": "web_bomb_canister",
        "builder": build_web_bomb,
        "dimensions": (1.0, 1.0, 1.2),
        "pivot_mode": "GROUND",
        "pivot_description": "Bottom bounding-box center / ground contact.",
    },
    {
        "name": "spider_tracer_dart",
        "builder": build_spider_tracer,
        "dimensions": (0.8, 0.8, 0.2),
        "pivot_mode": "MAGNET",
        "pivot_description": "Magnetic underside mounting center.",
    },
    {
        "name": "classic_pizza_box",
        "builder": build_pizza_box,
        "dimensions": (2.4, 2.4, 0.5),
        "pivot_mode": "GROUND",
        "pivot_description": "Bottom bounding-box center / ground contact.",
    },
    {
        "name": "webbed_backpack",
        "builder": build_backpack,
        "dimensions": (1.8, 1.4, 2.2),
        "pivot_mode": "WALL",
        "pivot_description": (
            "Rear wall contact plane center at Y=0; "
            "asset projects toward negative Y."
        ),
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
        "generator": "generate_spidey_gadgets.py",
        "blender_version": bpy.app.version_string,
        "scale_standard": {
            "blender_units_per_stud": 1.0,
            "meter_conversion_applied": False,
        },
        "coordinate_convention": {
            "report_axes": "Blender authoring XYZ; Z up",
            "fbx_axis_forward": "-Z",
            "fbx_axis_up": "Y",
        },
        "triangle_budget_exclusive": [MIN_TRIANGLES, MAX_TRIANGLES],
        "export_settings": {
            "global_scale": 1.0,
            "apply_unit_scale": False,
            "apply_scale_options": "FBX_SCALE_NONE",
            "mesh_smooth_type": "FACE",
        },
        "assets": [],
    }

    for spec in ASSETS:
        name = spec["name"]
        print(f"\n[Build] {name}")

        builder = spec["builder"]()
        obj = None

        try:
            fit_dimensions_and_pivot(
                builder.bm,
                spec["dimensions"],
                spec["pivot_mode"],
            )

            triangles = triangulate_cleanup_validate(builder.bm, name)
            obj = create_object(name, builder)

            minimum, maximum = object_bounds(obj)
            dimensions = maximum - minimum

            if any(
                abs(dimensions[i] - spec["dimensions"][i]) > 1.0e-5
                for i in range(3)
            ):
                raise RuntimeError(name + ": dimension validation failed.")

            obj["asset_name"] = name
            obj["units"] = "1 Blender unit = 1 Roblox stud"
            obj["triangle_count"] = triangles
            obj["pivot_description"] = spec["pivot_description"]

            filepath = os.path.join(output_dir, name + ".fbx")
            export_fbx(obj, filepath)

            report["assets"].append({
                "name": name,
                "file": os.path.basename(filepath),
                "mesh_objects": 1,
                "triangle_count": triangles,
                "degenerate_faces": 0,
                "all_faces_triangulated": True,
                "bounding_box_studs": {
                    "minimum_xyz": rounded_vector(minimum),
                    "maximum_xyz": rounded_vector(maximum),
                    "dimensions_xyz": rounded_vector(dimensions),
                },
                "transform": {
                    "location": [0.0, 0.0, 0.0],
                    "rotation_euler": [0.0, 0.0, 0.0],
                    "scale": [1.0, 1.0, 1.0],
                },
                "pivot": {
                    "position": [0.0, 0.0, 0.0],
                    "description": spec["pivot_description"],
                },
                "material_slots": material_report(obj),
            })

            print(
                f"  {triangles} triangles | "
                f"{rounded_vector(dimensions)} studs | "
                f"{len(obj.data.materials)} material slots"
            )
            print(f"  Exported: {filepath}")

        finally:
            builder.bm.free()

            if obj is not None:
                mesh_data = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)

                if mesh_data.users == 0:
                    bpy.data.meshes.remove(mesh_data)

    report_path = os.path.join(output_dir, "export_report.json")
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print("\n[Done] All five gadgets exported.")
    print(f"[Report] {report_path}")
    print("[Scale] 1 Blender unit = 1 stud; no meter conversion applied.")


if __name__ == "__main__":
    main()
