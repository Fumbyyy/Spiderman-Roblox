#!/usr/bin/env python3
"""
generate_thug_wearables.py

Standalone Blender 3.6+/4.x script.

Usage:
    blender --background --python generate_thug_wearables.py -- \
        --output-dir ./thug_wearables

Outputs:
    ballistic_hockey_mask.fbx
    thug_ski_mask.fbx
    tactical_plate_carrier.fbx
    street_gang_beanie.fbx
    spiked_arm_bracers.fbx
    export_report.json

SCALE:
    1 Blender unit = 1 Roblox stud.
    No physical-unit/meter conversion is performed.
    FBX apply_unit_scale=False, apply_scale_options='FBX_SCALE_NONE'.

AUTHORING AXES:
    Z up; front of wearer faces negative Y.

PIVOTS:
    Hockey mask: rear-center face cavity / attachment frame.
    Ski mask: head cavity center.
    Vest: torso center.
    Beanie: lower cuff opening center.
    Bracers: forearm center, longitudinal axis Z.

BRACER PAIR:
    Two logically grouped attachment-local meshes are exported together.
    Both have identity transforms and individual forearm-centered geometry.
    They intentionally overlap in the FBX preview. Assign them separately
    to the left/right forearms rather than importing as one fused accessory.
    Dimensions are approximately 1.4 x 1.4 x 1.6 studs PER cuff.
    Triangle validation applies to the combined pair.

RIG FIT:
    These are nominal R6/R15-sized rigid accessory shells, not skinned
    clothing or Roblox layered-clothing cages. Set Roblox attachment
    orientations/offsets for the target rig. Avatar body packages and
    non-default body scaling may require fit adjustments.

GEOMETRY:
    Eye/mouth openings and mask cavities are actual modeled openings.
    Construction components can intersect intentionally.
    No external images, procedural textures, fonts, or dependencies.
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
DEGENERATE_DISTANCE = 1.0e-5

MATERIALS = {}


# ---------------------------------------------------------------------------
# Arguments, scene, and materials
# ---------------------------------------------------------------------------

def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    parser = argparse.ArgumentParser(
        description="Generate five stylized Roblox thug wearable assets."
    )
    parser.add_argument("--output-dir", default="./thug_wearables")
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
            "the FBX import-export add-on."
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
    shader.inputs["Base Color"].default_value = (*color, 1.0)
    shader.inputs["Metallic"].default_value = metallic
    shader.inputs["Roughness"].default_value = roughness

    output = nodes.new("ShaderNodeOutputMaterial")
    mat.node_tree.links.new(shader.outputs["BSDF"], output.inputs["Surface"])

    MATERIALS[name] = mat
    return mat


def create_palette():
    make_material("Tactical_Matte_Black", (0.018, 0.024, 0.031), 0.05, 0.91)
    make_material("Slate_Gray",           (0.135, 0.168, 0.205), 0.12, 0.78)
    make_material("Worn_White",           (0.72, 0.69, 0.59),    0.12, 0.67)
    make_material("White_Edge",           (0.43, 0.43, 0.39),    0.22, 0.72)
    make_material("Dark_Leather",         (0.105, 0.047, 0.027), 0.00, 0.84)
    make_material("Leather_Edge",         (0.235, 0.115, 0.052), 0.00, 0.76)
    make_material("Gunmetal_Steel",        (0.205, 0.245, 0.285), 0.82, 0.42)
    make_material("Steel_Highlight",       (0.46, 0.50, 0.54),    0.86, 0.32)
    make_material("Elastic_Black",         (0.027, 0.030, 0.037), 0.00, 0.96)
    make_material("Knit_Charcoal",         (0.065, 0.071, 0.085), 0.00, 0.97)
    make_material("Knit_Rib",              (0.105, 0.116, 0.137), 0.00, 0.94)
    make_material("Muted_Red_Label",       (0.28, 0.031, 0.036),  0.00, 0.88)


# ---------------------------------------------------------------------------
# Construction helpers
# ---------------------------------------------------------------------------

class Builder:
    """Accumulates closed construction components into one BMesh."""

    def __init__(self, name):
        self.name = name
        self.bm = bmesh.new()
        self.material_names = []
        self.material_lookup = {}

    def material_index(self, name):
        if name not in MATERIALS:
            raise KeyError("Unknown material: " + name)

        if name not in self.material_lookup:
            self.material_lookup[name] = len(self.material_names)
            self.material_names.append(name)

        return self.material_lookup[name]

    def add(self, vertices, faces, material, transform=None):
        index = self.material_index(material)

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

            vertices = [vertex.co.copy() for vertex in temporary.verts]
            faces = [
                tuple(vertex.index for vertex in face.verts)
                for face in temporary.faces
            ]

            rotation = (
                Matrix.Identity(3) if rotation is None else rotation
            )
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

    def lathe(self, profile, segments, material, center=(0, 0, 0),
              axis=(0, 0, 1), phase=0.0):
        """
        Revolve a closed radial/Z cross-section.

        Profile runs from bottom inside/axis outward, upward, then inward.
        All-positive radii produce true annular geometry.
        Zero radii create one pole vertex instead of degenerate quads.
        """
        vertices = []
        rings = []

        for radius, z in profile:
            if abs(radius) < 1.0e-10:
                rings.append([len(vertices)])
                vertices.append((0.0, 0.0, z))
            else:
                ring = []
                for i in range(segments):
                    angle = phase + math.tau * i / segments
                    ring.append(len(vertices))
                    vertices.append((
                        radius * math.cos(angle),
                        radius * math.sin(angle),
                        z,
                    ))
                rings.append(ring)

        faces = []

        for row in range(len(rings)):
            a = rings[row]
            b = rings[(row + 1) % len(rings)]

            if len(a) == 1 and len(b) == 1:
                continue

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

    def ring(self, center, outer, inner, depth, segments, material,
             axis=(0, 0, 1)):
        half = depth * 0.5
        return self.lathe(
            [
                (inner, -half),
                (outer, -half),
                (outer, half),
                (inner, half),
            ],
            segments,
            material,
            center=center,
            axis=axis,
        )

    def cylinder(self, center, radius, depth, segments, material,
                 axis=(0, 0, 1)):
        half = depth * 0.5
        return self.lathe(
            [(0, -half), (radius, -half), (radius, half), (0, half)],
            segments, material, center=center, axis=axis,
        )

    def rectangular_ring(self, center, width, height, border, depth,
                         material, axis=(0, 0, 1)):
        """Closed rectangular buckle frame with a real through-opening."""
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

    def thick_surface(self, vertices, faces, thickness, material,
                      inner_material=None):
        """
        Thicken an oriented open surface inward along averaged normals.

        Boundary walls are generated around every opening. This produces
        real cavities and perforations without Boolean artifacts.
        """
        used = sorted({index for face in faces for index in face})
        remap = {old: new for new, old in enumerate(used)}

        source = [Vector(vertices[index]) for index in used]
        faces = [
            tuple(remap[index] for index in face)
            for face in faces
        ]

        normals = [Vector((0, 0, 0)) for _ in source]
        edge_uses = {}

        for face in faces:
            origin = source[face[0]]
            normal = Vector((0, 0, 0))

            for i in range(1, len(face) - 1):
                normal += (
                    source[face[i]] - origin
                ).cross(source[face[i + 1]] - origin)

            if normal.length <= 1.0e-10:
                raise RuntimeError("Degenerate source surface.")

            for index in face:
                normals[index] += normal

            for i, a in enumerate(face):
                c = face[(i + 1) % len(face)]
                key = tuple(sorted((a, c)))
                edge_uses.setdefault(key, []).append((a, c))

        for normal in normals:
            if normal.length <= 1.0e-10:
                raise RuntimeError("Undefined shell vertex normal.")
            normal.normalize()

        count = len(source)
        all_vertices = source + [
            point - normal * thickness
            for point, normal in zip(source, normals)
        ]

        all_faces = list(faces)
        all_faces.extend(
            tuple(index + count for index in reversed(face))
            for face in faces
        )

        for uses in edge_uses.values():
            if len(uses) == 1:
                a, c = uses[0]
                all_faces.append((a, a + count, c + count, c))
            elif len(uses) != 2:
                raise RuntimeError("Non-manifold source shell surface.")

        new_vertices = self.add(all_vertices, all_faces, material)

        if inner_material is not None:
            inner_index = self.material_index(inner_material)
            inner_set = set(new_vertices[count:])

            for face in self.bm.faces:
                if all(vertex in inner_set for vertex in face.verts):
                    face.material_index = inner_index

    def blunt_stud(self, center, base_width, top_width, height, material,
                   axis=(0, -1, 0)):
        """Truncated square pyramid: intentionally blunt, not needle sharp."""
        vertices = []
        for width, z in ((base_width, 0.0), (top_width, height)):
            half = width * 0.5
            vertices.extend([
                (-half, -half, z),
                ( half, -half, z),
                ( half,  half, z),
                (-half,  half, z),
            ])

        faces = [
            (3, 2, 1, 0), (4, 5, 6, 7),
            (0, 1, 5, 4), (1, 2, 6, 5),
            (2, 3, 7, 6), (3, 0, 4, 7),
        ]

        rotation = Vector(axis).to_track_quat("Z", "Y").to_matrix()
        transform = (
            Matrix.Translation(Vector(center)) @ rotation.to_4x4()
        )
        self.add(vertices, faces, material, transform)


# ---------------------------------------------------------------------------
# 1. Ballistic hockey mask
# ---------------------------------------------------------------------------

def build_hockey_mask():
    b = Builder("BallisticHockeyMask")
    nx = 10
    nz = 10

    vertices = []
    for row in range(nz + 1):
        v = row / nz
        z = -0.67 + 1.34 * v

        # Narrow jaw and gently pinched crown.
        taper = 0.79 + 0.21 * math.sin(math.pi * v) ** 0.65

        for column in range(nx + 1):
            u = -1.0 + 2.0 * column / nx
            x = 0.62 * u * taper
            y = -0.20 - 0.31 * (1.0 - u * u)
            y -= 0.045 * math.cos(z * 2.0)

            # Gives the eye openings an aggressive angular slant.
            angled_z = z + 0.08 * abs(u) * math.exp(
                -((z - 0.20) / 0.24) ** 2
            )
            vertices.append((x, y, angled_z))

    holes = {
        (1, 6), (2, 6),             # Left eye slit.
        (7, 6), (8, 6),             # Right eye slit.
        (4, 3), (5, 3),             # Nose/breathing opening.
        (4, 4), (5, 4),
    }

    faces = []
    for row in range(nz):
        for column in range(nx):
            if (column, row) in holes:
                continue

            a = row * (nx + 1) + column
            faces.append((
                a, a + 1, a + nx + 2, a + nx + 1
            ))

    b.thick_surface(
        vertices, faces, 0.055,
        "Worn_White", inner_material="Tactical_Matte_Black",
    )

    # Two angled, chamfered brow plates.
    for side in (-1, 1):
        rotation = Matrix.Rotation(
            side * math.radians(-10), 3, "Y"
        )
        b.box(
            (side * 0.29, -0.49, 0.37),
            (0.49, 0.11, 0.14),
            "White_Edge",
            bevel=0.021,
            rotation=rotation,
        )

    # Three rear elastic bands wrap around the head cavity.
    for z in (-0.38, 0.03, 0.43):
        points = [
            (-0.56, -0.24, z),
            (-0.61,  0.00, z),
            (-0.46,  0.28, z),
            ( 0.00,  0.43, z),
            ( 0.46,  0.28, z),
            ( 0.61,  0.00, z),
            ( 0.56, -0.24, z),
        ]
        b.tube(points, 0.052, 4, "Elastic_Black")

    for x, z in ((-0.49, 0.49), (0.49, 0.49), (0, -0.52)):
        b.cylinder(
            (x, -0.36 if x else -0.55, z),
            0.045, 0.035, 6, "Gunmetal_Steel",
            axis=(0, -1, 0),
        )

    return [b]


# ---------------------------------------------------------------------------
# Shared faceted head/cap surface
# ---------------------------------------------------------------------------

def head_surface(profile, segments, holes=None):
    """
    profile entries: (radius, height, center_x, center_y)
    Front corresponds to angular index 0, facing negative Y.
    """
    holes = set() if holes is None else holes
    vertices = []

    for radius, z, offset_x, offset_y in profile:
        for i in range(segments):
            angle = math.tau * i / segments
            vertices.append((
                offset_x + radius * math.sin(angle),
                offset_y - radius * math.cos(angle),
                z,
            ))

    faces = []

    for row in range(len(profile) - 1):
        for column in range(segments):
            if (column, row) in holes:
                continue

            j = (column + 1) % segments
            faces.append((
                row * segments + column,
                row * segments + j,
                (row + 1) * segments + j,
                (row + 1) * segments + column,
            ))

    top = (len(profile) - 1) * segments
    faces.append(tuple(top + i for i in range(segments)))

    return vertices, faces


# ---------------------------------------------------------------------------
# 2. Ski mask / balaclava
# ---------------------------------------------------------------------------

def build_ski_mask():
    b = Builder("ThugSkiMask")

    profile = [
        (0.49, -0.72, 0.0, 0.0),
        (0.56, -0.48, 0.0, 0.0),
        (0.60, -0.28, 0.0, 0.0),
        (0.62, -0.10, 0.0, 0.0),
        (0.63,  0.16, 0.0, 0.0),
        (0.50,  0.42, 0.0, 0.0),
        (0.16,  0.72, 0.0, 0.0),
    ]

    holes = {
        (18, 4), (1, 4),        # Separate eye cutouts.
        (19, 2), (0, 2),        # Connected open mouth slit.
    }

    vertices, faces = head_surface(profile, 20, holes)
    b.thick_surface(
        vertices, faces, 0.045,
        "Knit_Charcoal", inner_material="Tactical_Matte_Black",
    )

    b.ring(
        (0, 0, -0.65),
        0.575, 0.44, 0.22, 16, "Knit_Rib",
    )

    # Rolled collar ribbing is actual geometry.
    for i in range(16):
        angle = math.tau * i / 16.0
        rotation = Matrix.Rotation(angle, 3, "Z")
        b.box(
            (0.567 * math.cos(angle), 0.567 * math.sin(angle), -0.65),
            (0.035, 0.068, 0.205),
            "Knit_Charcoal",
            rotation=rotation,
        )

    return [b]


# ---------------------------------------------------------------------------
# 3. Tactical plate carrier
# ---------------------------------------------------------------------------

def build_plate_carrier():
    b = Builder("TacticalPlateCarrier")

    # Eight independent ceramic plate pockets leave a torso cavity.
    for y in (-0.53, 0.53):
        for x in (-0.46, 0.46):
            for z in (-0.40, 0.40):
                b.box(
                    (x, y, z), (0.87, 0.23, 0.72),
                    "Tactical_Matte_Black",
                    bevel=0.045,
                )

    # Shoulder bridges leave the neck and arm openings unobstructed.
    for x in (-0.73, 0.73):
        b.box(
            (x, 0, 0.91), (0.36, 1.18, 0.24),
            "Slate_Gray", bevel=0.038,
        )

    # Upper and lower side fastening straps.
    for x in (-0.97, 0.97):
        for z in (-0.47, 0.47):
            b.box(
                (x, 0, z), (0.13, 1.08, 0.18),
                "Elastic_Black",
            )

            b.rectangular_ring(
                (x * 1.025, 0.08, z),
                0.30, 0.22, 0.040, 0.055,
                "Gunmetal_Steel",
                axis=(1, 0, 0),
            )

    # Eight raised MOLLE loops, each with a real open center.
    for z in (-0.43, 0.35):
        for x in (-0.63, -0.21, 0.21, 0.63):
            y = -0.685

            b.box(
                (x, y, z - 0.065),
                (0.30, 0.05, 0.035), "Slate_Gray",
            )
            b.box(
                (x, y, z + 0.065),
                (0.30, 0.05, 0.035), "Slate_Gray",
            )

            for dx in (-0.1325, 0.1325):
                b.box(
                    (x + dx, y, z),
                    (0.035, 0.05, 0.13), "Slate_Gray",
                )

    # Two lower overlapping utility pockets.
    for x in (-0.47, 0.47):
        b.box(
            (x, -0.68, -0.84), (0.68, 0.18, 0.31),
            "Slate_Gray", bevel=0.032,
        )

    return [b]


# ---------------------------------------------------------------------------
# 4. Slouchy beanie
# ---------------------------------------------------------------------------

def build_beanie():
    b = Builder("StreetGangBeanie")

    profile = [
        (0.53, 0.06, 0.00, 0.00),
        (0.61, 0.24, 0.00, 0.00),
        (0.59, 0.47, 0.01, 0.01),
        (0.48, 0.66, 0.06, 0.04),
        (0.32, 0.78, 0.11, 0.08),
        (0.10, 0.82, 0.17, 0.10),
    ]

    vertices, faces = head_surface(profile, 16)
    b.thick_surface(
        vertices, faces, 0.043,
        "Knit_Charcoal", inner_material="Tactical_Matte_Black",
    )

    # Six-point cuff cross-section gives a chunky folded, faceted roll.
    b.lathe(
        [
            (0.47, 0.00),
            (0.59, 0.00),
            (0.65, 0.05),
            (0.65, 0.20),
            (0.60, 0.25),
            (0.47, 0.25),
        ],
        16, "Knit_Rib",
    )

    for i in range(12):
        angle = math.tau * i / 12.0
        b.box(
            (0.65 * math.cos(angle), 0.65 * math.sin(angle), 0.125),
            (0.032, 0.052, 0.17),
            "Knit_Charcoal",
            rotation=Matrix.Rotation(angle, 3, "Z"),
        )

    b.box(
        (0.13, -0.657, 0.13),
        (0.22, 0.025, 0.14),
        "Muted_Red_Label",
    )

    return [b]


# ---------------------------------------------------------------------------
# 5. Bracer pair
# ---------------------------------------------------------------------------

def build_one_bracer(name, side):
    b = Builder(name)

    # Open-ended leather cuff.
    b.ring(
        (0, 0, 0), 0.50, 0.405, 1.36, 12, "Dark_Leather"
    )

    # Faceted metal end trims.
    for z in (-0.65, 0.65):
        b.ring(
            (0, 0, z), 0.535, 0.395, 0.12, 8,
            "Gunmetal_Steel",
        )

    # Dual leather buckle straps around the forearm.
    for z in (-0.40, 0.40):
        b.ring(
            (0, 0, z), 0.55, 0.49, 0.13, 8, "Leather_Edge"
        )

        b.rectangular_ring(
            (side * 0.54, 0.02, z),
            0.25, 0.22, 0.042, 0.065,
            "Steel_Highlight",
            axis=(side, 0, 0),
        )

    b.box(
        (side * 0.04, -0.48, 0),
        (0.61, 0.13, 1.12),
        "Gunmetal_Steel",
        bevel=0.034,
    )

    # Six blunt pyramid studs per cuff.
    for x in (-0.19, 0.19):
        for z in (-0.37, 0.0, 0.37):
            b.blunt_stud(
                (x, -0.54, z),
                base_width=0.19,
                top_width=0.075,
                height=0.18,
                material="Steel_Highlight",
                axis=(0, -1, 0),
            )

    return b


def build_bracer_pair():
    return [
        build_one_bracer("SpikedArmBracer_Left", -1),
        build_one_bracer("SpikedArmBracer_Right", 1),
    ]


# ---------------------------------------------------------------------------
# Dimension fitting and mesh validation
# ---------------------------------------------------------------------------

def bounds_from_coordinates(coordinates):
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


def fit_builder(builder, target_dimensions, pivot_mode):
    """
    Direct asset dimension fitting in studs, not unit conversion.
    The authored anatomical origin is preserved, except the beanie's
    lower opening is explicitly placed at Z=0.
    """
    minimum, maximum = bounds_from_coordinates(
        vertex.co for vertex in builder.bm.verts
    )
    dimensions = maximum - minimum

    if min(dimensions) <= 1.0e-7:
        raise RuntimeError("Degenerate asset bounds: " + builder.name)

    factors = Vector(tuple(
        target_dimensions[axis] / dimensions[axis]
        for axis in range(3)
    ))

    for vertex in builder.bm.verts:
        for axis in range(3):
            vertex.co[axis] *= factors[axis]

    if pivot_mode == "CUFF_OPENING":
        minimum, _ = bounds_from_coordinates(
            vertex.co for vertex in builder.bm.verts
        )
        for vertex in builder.bm.verts:
            vertex.co.z -= minimum.z


def cleanup_and_validate(builder):
    bm = builder.bm

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))

    # Required order: triangulate, followed by dissolve_degenerate.
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

    # Cleanup can theoretically change polygons; repeat the ordered
    # operation pair if any resulting face is not triangular.
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
        raise RuntimeError(builder.name + ": non-triangle face remains.")

    minimum_area = math.inf
    minimum_altitude = math.inf

    for face in bm.faces:
        area = face.calc_area()
        if not math.isfinite(area) or area <= 1.0e-12:
            raise RuntimeError(builder.name + ": degenerate face remains.")

        longest = max(edge.calc_length() for edge in face.edges)
        altitude = 2.0 * area / longest

        if altitude <= DEGENERATE_DISTANCE:
            raise RuntimeError(
                builder.name + ": triangle below sliver tolerance remains."
            )

        minimum_area = min(minimum_area, area)
        minimum_altitude = min(minimum_altitude, altitude)

    if any(
        edge.calc_length() <= DEGENERATE_DISTANCE
        for edge in bm.edges
    ):
        raise RuntimeError(builder.name + ": near-zero edge remains.")

    if any(not edge.is_manifold for edge in bm.edges):
        raise RuntimeError(
            builder.name + ": open/non-manifold construction component."
        )

    if any(not vertex.link_faces for vertex in bm.verts):
        raise RuntimeError(builder.name + ": loose vertices remain.")

    if any(
        not math.isfinite(component)
        for vertex in bm.verts
        for component in vertex.co
    ):
        raise RuntimeError(builder.name + ": invalid vertex coordinate.")

    return {
        "triangle_count": len(bm.faces),
        "degenerate_faces": 0,
        "minimum_triangle_area_studs_squared": minimum_area,
        "minimum_triangle_altitude_studs": minimum_altitude,
    }


def create_mesh_object(builder):
    mesh = bpy.data.meshes.new(builder.name + "_Mesh")
    builder.bm.to_mesh(mesh)
    mesh.update()

    for material_name in builder.material_names:
        mesh.materials.append(MATERIALS[material_name])

    # Compact material slots to those actually used by this mesh.
    used = sorted({polygon.material_index for polygon in mesh.polygons})
    remap = {old: new for new, old in enumerate(used)}
    used_materials = [mesh.materials[index] for index in used]
    polygon_indices = [
        remap[polygon.material_index] for polygon in mesh.polygons
    ]

    mesh.materials.clear()
    for mat in used_materials:
        mesh.materials.append(mat)

    for polygon, material_index in zip(mesh.polygons, polygon_indices):
        polygon.material_index = material_index
        polygon.use_smooth = False

    obj = bpy.data.objects.new(builder.name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    obj.matrix_world = Matrix.Identity(4)
    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)

    if any(len(polygon.vertices) != 3 for polygon in mesh.polygons):
        raise RuntimeError(builder.name + ": non-triangulated output.")

    return obj


def rounded_vector(vector):
    return [round(float(value), 7) for value in vector]


def bounds_report(objects):
    minimum, maximum = bounds_from_coordinates(
        vertex.co
        for obj in objects
        for vertex in obj.data.vertices
    )
    return {
        "minimum_xyz": rounded_vector(minimum),
        "maximum_xyz": rounded_vector(maximum),
        "dimensions_xyz": rounded_vector(maximum - minimum),
    }


def report_material_slots(obj):
    result = []

    for slot, mat in enumerate(obj.data.materials):
        shader = mat.node_tree.nodes["Principled BSDF"]

        result.append({
            "slot": slot,
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
            "triangles": sum(
                polygon.material_index == slot
                for polygon in obj.data.polygons
            ),
        })

    return result


# ---------------------------------------------------------------------------
# Export
# ---------------------------------------------------------------------------

def export_fbx(objects, filepath):
    bpy.ops.object.select_all(action="DESELECT")

    for obj in objects:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = objects[0]
    bpy.context.view_layer.update()

    for obj in objects:
        if obj.location.length > 1.0e-8:
            raise RuntimeError("Nonzero object location: " + obj.name)

        if any(abs(value) > 1.0e-8 for value in obj.rotation_euler):
            raise RuntimeError("Nonzero object rotation: " + obj.name)

        if any(abs(value - 1.0) > 1.0e-8 for value in obj.scale):
            raise RuntimeError("Unapplied object scale: " + obj.name)

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
# Asset definitions and driver
# ---------------------------------------------------------------------------

ASSETS = [
    {
        "name": "ballistic_hockey_mask",
        "builder": build_hockey_mask,
        "dimensions": (1.3, 1.1, 1.4),
        "pivot_mode": "FACE_CONTACT",
        "pivot_description": (
            "Center-back face cavity attachment frame; front faces -Y."
        ),
        "rig_target": "Head",
    },
    {
        "name": "thug_ski_mask",
        "builder": build_ski_mask,
        "dimensions": (1.3, 1.3, 1.6),
        "pivot_mode": "HEAD_CENTER",
        "pivot_description": "Head cavity center; front faces -Y.",
        "rig_target": "Head",
    },
    {
        "name": "tactical_plate_carrier",
        "builder": build_plate_carrier,
        "dimensions": (2.2, 1.3, 2.2),
        "pivot_mode": "TORSO_CENTER",
        "pivot_description": "Torso center; front plates face -Y.",
        "rig_target": "R15 UpperTorso / R6 Torso",
    },
    {
        "name": "street_gang_beanie",
        "builder": build_beanie,
        "dimensions": (1.3, 1.3, 0.9),
        "pivot_mode": "CUFF_OPENING",
        "pivot_description": "Lower cuff opening center, Z=0.",
        "rig_target": "Head top",
    },
    {
        "name": "spiked_arm_bracers",
        "builder": build_bracer_pair,
        "dimensions": (1.4, 1.4, 1.6),
        "pivot_mode": "FOREARM_CENTER",
        "pivot_description": (
            "Each mesh uses its own forearm-centered attachment-local "
            "frame. Both origins are zero; longitudinal axis is Z."
        ),
        "rig_target": (
            "R15 LeftLowerArm / RightLowerArm; R6 Left Arm / Right Arm"
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
        "generator": "generate_thug_wearables.py",
        "blender_version": bpy.app.version_string,
        "scale_standard": {
            "blender_units_per_roblox_stud": 1.0,
            "meter_conversion_applied": False,
        },
        "coordinate_convention": {
            "report_axes": "Blender XYZ; Z up; wearer front is -Y",
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
        "fit_note": (
            "Nominal rigid R6/R15 wearables. Attachment orientation and "
            "offset must be assigned for the target avatar. No skinning "
            "or layered-clothing cages are generated."
        ),
        "assets": [],
    }

    for spec in ASSETS:
        print(f"\n[Build] {spec['name']}")

        builders = spec["builder"]()
        objects = []
        validations = []

        try:
            for builder in builders:
                fit_builder(
                    builder,
                    spec["dimensions"],
                    spec["pivot_mode"],
                )

                validation = cleanup_and_validate(builder)
                validations.append(validation)

                obj = create_mesh_object(builder)
                objects.append(obj)

                obj["asset_name"] = spec["name"]
                obj["units"] = "1 Blender unit = 1 Roblox stud"
                obj["pivot_description"] = spec["pivot_description"]
                obj["rig_target"] = spec["rig_target"]
                obj["triangle_count"] = validation["triangle_count"]

                if spec["name"] == "spiked_arm_bracers":
                    obj["attachment_side"] = (
                        "Left" if obj.name.endswith("_Left") else "Right"
                    )
                    obj["layout"] = "Independent attachment-local geometry"

                actual_bounds = bounds_report([obj])
                actual_dimensions = actual_bounds["dimensions_xyz"]

                if any(
                    abs(actual_dimensions[i] - spec["dimensions"][i])
                    > 1.0e-5
                    for i in range(3)
                ):
                    raise RuntimeError(
                        obj.name + ": dimension validation failed."
                    )

            total_triangles = sum(
                validation["triangle_count"] for validation in validations
            )

            if not MIN_TRIANGLES < total_triangles < MAX_TRIANGLES:
                raise RuntimeError(
                    f"{spec['name']}: {total_triangles} triangles; "
                    f"expected strictly between {MIN_TRIANGLES} "
                    f"and {MAX_TRIANGLES}."
                )

            filepath = os.path.join(
                output_dir, spec["name"] + ".fbx"
            )
            export_fbx(objects, filepath)

            asset_record = {
                "name": spec["name"],
                "file": os.path.basename(filepath),
                "triangle_count": total_triangles,
                "mesh_object_count": len(objects),
                "bounding_box_studs": bounds_report(objects),
                "pivot": {
                    "position": [0.0, 0.0, 0.0],
                    "description": spec["pivot_description"],
                },
                "rig_target": spec["rig_target"],
                "objects": [],
            }

            if spec["name"] == "spiked_arm_bracers":
                asset_record["layout_note"] = (
                    "The two cuff meshes overlap intentionally in "
                    "attachment-local coordinates. Dimensions are per "
                    "cuff; attach them separately to opposite forearms."
                )

            for obj, validation in zip(objects, validations):
                asset_record["objects"].append({
                    "name": obj.name,
                    "bounding_box_studs": bounds_report([obj]),
                    "transform": {
                        "location": [0.0, 0.0, 0.0],
                        "rotation_euler": [0.0, 0.0, 0.0],
                        "scale": [1.0, 1.0, 1.0],
                    },
                    "validation": validation,
                    "material_slots": report_material_slots(obj),
                })

            report["assets"].append(asset_record)

            print(
                f"  {total_triangles} triangles | "
                f"{len(objects)} mesh object(s)"
            )
            print(f"  Exported: {filepath}")

        finally:
            for builder in builders:
                builder.bm.free()

            for obj in objects:
                # Required safe cleanup: cache data BEFORE removing obj.
                mesh_data = obj.data
                bpy.data.objects.remove(obj, do_unlink=True)

                if mesh_data.users == 0:
                    bpy.data.meshes.remove(mesh_data)

    report_path = os.path.join(output_dir, "export_report.json")
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print("\n[Done] All five wearable assets exported.")
    print(f"[Report] {report_path}")
    print("[Scale] 1 Blender unit = 1 Roblox stud; no meter conversion.")


if __name__ == "__main__":
    main()
