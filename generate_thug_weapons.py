#!/usr/bin/env python3
"""
generate_thug_weapons.py

Run:
    blender --background --python generate_thug_weapons.py -- --out ./thug_weapons

Requires Blender 3.6+ with the standard FBX exporter available.

Design:
    Bat:      Ash wood, iron barrel reinforcement, ivory grip bands.
    Crowbar:  Safety-yellow octagonal steel, exaggerated hook, forked tips.
    Knife:    Crimson grip scales, serrated tanto, open lanyard ring.
    Handgun:  Carbon frame, crimson slide, open compensator and trigger guard.
    Shield:   Curved shell, actual viewport opening, white hazard slashes.

Coordinate conventions before FBX axis conversion:
    +Z = up / long-weapon direction
    +X = handgun muzzle direction
    -Y = shield front
    Origin = intended hand-grip center

Every exported asset:
    - Is one mesh object with multiple material slots.
    - Has location/rotation zero and scale one.
    - Has its object origin at world (0, 0, 0).
    - Is explicitly triangulated.
    - Contains 600–1400 triangles.
    - Is normalized to its requested primary dimension.

Materials use constant colors, not procedural textures.
Roblox may require material/SurfaceAppearance adjustments to reproduce
Blender metallic and roughness settings exactly.
"""

import argparse
import json
import math
import os
import sys

import bpy
import bmesh
from mathutils import Vector


MIN_TRIS = 600
MAX_TRIS = 1400
STUD_METERS = 0.28

PARTS = []
MAT = {}


# ---------------------------------------------------------------------------
# Scene and materials
# ---------------------------------------------------------------------------

def clear_scene():
    """Remove scene objects and unused meshes between individual assets."""
    global PARTS
    PARTS = []

    if bpy.context.object and bpy.context.object.mode != 'OBJECT':
        bpy.ops.object.mode_set(mode='OBJECT')

    bpy.ops.object.select_all(action='SELECT')
    bpy.ops.object.delete(use_global=False)

    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    bpy.context.scene.cursor.location = (0, 0, 0)


def material(name, rgb, roughness=0.6, metallic=0.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    rgba = (*rgb, 1.0)
    mat.diffuse_color = rgba

    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = rgba
    bsdf.inputs["Roughness"].default_value = roughness
    bsdf.inputs["Metallic"].default_value = metallic

    mat.roughness = roughness
    mat.metallic = metallic
    return mat


def create_materials():
    global MAT
    MAT = {
        "wood": material("Warm Ash Wood", (0.49, 0.235, 0.075), 0.78),
        "wood_light": material("Ash Cut End", (0.72, 0.43, 0.16), 0.80),
        "wood_dark": material("Dark Wood Accent", (0.24, 0.085, 0.025), 0.86),
        "ivory": material("Worn Ivory Tape", (0.88, 0.84, 0.67), 0.90),
        "steel": material("Matte Steel", (0.24, 0.31, 0.37), 0.47, 0.65),
        "edge": material("Exposed Steel Chamfer", (0.56, 0.65, 0.70), 0.35, 0.72),
        "iron": material("Dark Reinforcing Iron", (0.07, 0.095, 0.12), 0.64, 0.55),
        "rust": material("Rust Orange", (0.40, 0.105, 0.025), 0.91, 0.15),
        "yellow": material("Industrial Safety Yellow", (0.98, 0.57, 0.018), 0.66),
        "red": material("Deep Crimson", (0.48, 0.018, 0.035), 0.59, 0.15),
        "red_light": material("Crimson Edge Accent", (0.76, 0.035, 0.055), 0.51),
        "black": material("Tactical Carbon", (0.018, 0.025, 0.035), 0.82),
        "gunmetal": material("Blade Gunmetal", (0.085, 0.13, 0.18), 0.43, 0.70),
        "white": material("Hazard Stencil White", (0.94, 0.95, 0.87), 0.77),
        "void": material("Recess Black", (0.005, 0.008, 0.012), 0.96),
    }


# ---------------------------------------------------------------------------
# Mesh helpers
# ---------------------------------------------------------------------------

def deselect():
    bpy.ops.object.select_all(action='DESELECT')


def activate(obj):
    deselect()
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj


def make_mesh(name, verts, faces, materials, indices=None):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)

    for mat in materials:
        mesh.materials.append(mat)

    if indices is not None:
        for polygon, index in zip(mesh.polygons, indices):
            polygon.material_index = index

    # All closed components receive consistently oriented normals.
    bm = bmesh.new()
    bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()

    PARTS.append(obj)
    return obj


def apply_bevel(obj, width, bevel_material=None):
    if width <= 0:
        return obj

    activate(obj)
    modifier = obj.modifiers.new("Single Segment Chamfers", 'BEVEL')
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = 'ANGLE'
    modifier.angle_limit = math.radians(18)
    modifier.use_clamp_overlap = True

    if bevel_material is not None:
        obj.data.materials.append(bevel_material)
        modifier.material = len(obj.data.materials) - 1

    bpy.ops.object.modifier_apply(modifier=modifier.name)
    return obj


def box(name, center, dimensions, mat, bevel=0.0, edge_mat=None,
        rotation=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    obj.rotation_euler = rotation
    obj.data.materials.append(mat)

    # Bevel widths remain independent of object dimensions.
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    PARTS.append(obj)
    apply_bevel(obj, bevel, edge_mat)
    return obj


def extrude_polygon(name, polygon_xz, depth, mat, center_y=0,
                    bevel=0, edge_mat=None):
    """Extrude an arbitrary simple XZ polygon along Y."""
    n = len(polygon_xz)
    verts = (
        [(x, center_y - depth / 2, z) for x, z in polygon_xz] +
        [(x, center_y + depth / 2, z) for x, z in polygon_xz]
    )

    faces = [
        tuple(reversed(range(n))),
        tuple(range(n, 2 * n)),
    ]
    faces += [
        (i, (i + 1) % n, (i + 1) % n + n, i + n)
        for i in range(n)
    ]

    obj = make_mesh(name, verts, faces, [mat])
    apply_bevel(obj, bevel, edge_mat)
    return obj


def lathe(name, profile, sides, mat, center=(0, 0, 0),
          phase=0.0, stripe_mat=None):
    """Capped faceted Z-axis solid. Profile entries are (z, radius)."""
    cx, cy, cz = center
    verts = []

    for z, radius in profile:
        for j in range(sides):
            angle = phase + math.tau * j / sides
            verts.append((
                cx + radius * math.cos(angle),
                cy + radius * math.sin(angle),
                cz + z
            ))

    faces = []
    indices = []
    for ring in range(len(profile) - 1):
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((
                ring * sides + j,
                ring * sides + k,
                (ring + 1) * sides + k,
                (ring + 1) * sides + j
            ))
            indices.append(1 if stripe_mat and j in (1, 6) else 0)

    faces.append(tuple(reversed(range(sides))))
    faces.append(tuple(
        (len(profile) - 1) * sides + j for j in range(sides)
    ))
    indices.extend([0, 0])

    mats = [mat] + ([stripe_mat] if stripe_mat else [])
    return make_mesh(name, verts, faces, mats, indices)


def band(name, z, radius, height, mat, sides=10):
    chamfer = min(height * 0.24, radius * 0.09)
    return lathe(
        name,
        [
            (z - height / 2, radius - chamfer),
            (z - height / 2 + chamfer, radius),
            (z + height / 2 - chamfer, radius),
            (z + height / 2, radius - chamfer),
        ],
        sides, mat
    )


def tube(name, points, radius, sides, mats, segment_materials=None,
         closed=False, reference=(0, 1, 0)):
    """
    Faceted swept tube with shared rings.
    Paths in this script are planar; reference is normal to their plane.
    """
    p = [Vector(point) for point in points]
    ref = Vector(reference).normalized()
    verts = []
    count = len(p)

    for i, point in enumerate(p):
        if closed:
            tangent = (p[(i + 1) % count] - p[(i - 1) % count]).normalized()
        elif i == 0:
            tangent = (p[1] - p[0]).normalized()
        elif i == count - 1:
            tangent = (p[-1] - p[-2]).normalized()
        else:
            tangent = (p[i + 1] - p[i - 1]).normalized()

        u = tangent.cross(ref).normalized()
        v = tangent.cross(u).normalized()

        for j in range(sides):
            a = math.tau * j / sides
            verts.append(tuple(
                point + radius * (math.cos(a) * u + math.sin(a) * v)
            ))

    faces = []
    indices = []
    segments = count if closed else count - 1

    for i in range(segments):
        following = (i + 1) % count
        for j in range(sides):
            k = (j + 1) % sides
            faces.append((
                i * sides + j,
                i * sides + k,
                following * sides + k,
                following * sides + j
            ))
            indices.append(
                segment_materials[i] if segment_materials else 0
            )

    if not closed:
        faces.append(tuple(reversed(range(sides))))
        faces.append(tuple((count - 1) * sides + j for j in range(sides)))
        indices.extend([
            segment_materials[0] if segment_materials else 0,
            segment_materials[-1] if segment_materials else 0
        ])

    return make_mesh(name, verts, faces, mats, indices)


def cylinder_between(name, a, b, radius, mat, sides=8):
    """Low-poly fastener or short cylindrical detail."""
    a, b = Vector(a), Vector(b)
    direction = b - a

    bpy.ops.mesh.primitive_cylinder_add(
        vertices=sides,
        radius=radius,
        depth=direction.length,
        end_fill_type='NGON',
        location=(a + b) / 2
    )
    obj = bpy.context.object
    obj.name = name
    obj.rotation_euler = direction.to_track_quat('Z', 'Y').to_euler()
    obj.data.materials.append(mat)
    PARTS.append(obj)
    return obj


def ring_prism(name, outer, inner, depth, mat, axis='Y', center=(0, 0, 0)):
    """
    Extruded polygonal ring with an actual hole.
    Outer and inner loops must have matching vertex counts and ordering.
    axis Y: loop coordinates are X,Z.
    axis X: loop coordinates are Y,Z.
    """
    if len(outer) != len(inner):
        raise ValueError("Ring loops must have matching vertex counts.")

    n = len(outer)
    c = Vector(center)
    verts = []

    for distance in (-depth / 2, depth / 2):
        for loop in (outer, inner):
            for u, v in loop:
                local = (
                    Vector((u, distance, v))
                    if axis == 'Y'
                    else Vector((distance, u, v))
                )
                verts.append(tuple(c + local))

    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces.extend([
            (i, j, n + j, n + i),
            (2*n + i, 3*n + i, 3*n + j, 2*n + j),
            (i, 2*n + i, 2*n + j, j),
            (n + i, n + j, 3*n + j, 3*n + i),
        ])

    return make_mesh(name, verts, faces, [mat])


def chamfer_rectangle(half_u, half_v, chamfer):
    return [
        (-half_u + chamfer, -half_v),
        ( half_u - chamfer, -half_v),
        ( half_u, -half_v + chamfer),
        ( half_u,  half_v - chamfer),
        ( half_u - chamfer,  half_v),
        (-half_u + chamfer,  half_v),
        (-half_u,  half_v - chamfer),
        (-half_u, -half_v + chamfer),
    ]


# ---------------------------------------------------------------------------
# 1. Street Bruiser Bat
# ---------------------------------------------------------------------------

def build_bat():
    lathe(
        "Ash Bat Body",
        [
            (-0.38, 0.115),
            (-0.35, 0.145),
            (-0.28, 0.145),
            (-0.24, 0.091),
            ( 0.28, 0.091),
            ( 0.49, 0.110),
            ( 0.95, 0.150),
            ( 1.43, 0.202),
            ( 1.75, 0.230),
            ( 2.54, 0.230),
            ( 2.73, 0.205),
            ( 2.82, 0.145),
        ],
        12, MAT["wood"], stripe_mat=MAT["wood_dark"]
    )

    # The grasp region is centered on the world origin.
    for i, z in enumerate((-0.20, -0.09, 0.02, 0.13, 0.24)):
        band("Ivory Grip Band %02d" % i, z, 0.102, 0.075,
             MAT["ivory"], sides=8)

    band("Pommel Iron", -0.305, 0.151, 0.052, MAT["iron"], sides=10)

    for i, z in enumerate((1.69, 2.09, 2.49)):
        band("Barrel Reinforcement %02d" % i, z, 0.247, 0.13,
             MAT["iron"], sides=12)

        # Rust-colored bolt heads face the presentation side.
        cylinder_between(
            "Rust Ring Rivet %02d" % i,
            (0, -0.239, z), (0, -0.266, z),
            0.032, MAT["rust"], sides=6
        )

    lathe(
        "Cut Wood Crown",
        [(2.811, 0.135), (2.824, 0.135)],
        12, MAT["wood_light"]
    )


# ---------------------------------------------------------------------------
# 2. Industrial Heavy Crowbar
# ---------------------------------------------------------------------------

def build_crowbar():
    path = [
        (0.00, 0, -0.44),
        (0.00, 0, -0.28),
        (0.00, 0,  0.35),
        (0.00, 0,  1.52),
        (0.03, 0,  1.83),
        (0.16, 0,  2.04),
        (0.37, 0,  2.13),
        (0.57, 0,  2.07),
        (0.72, 0,  1.91),
        (0.75, 0,  1.73),
        (0.66, 0,  1.60),
    ]

    tube(
        "Forged Octagonal Crowbar",
        path, 0.105, 8,
        [MAT["yellow"], MAT["steel"], MAT["edge"]],
        segment_materials=[1, 0, 0, 0, 0, 0, 0, 0, 1, 2]
    )

    # Broken-looking black paint bands around the gripping area.
    for i, z in enumerate((-0.25, -0.13, -0.01, 0.11, 0.23, 0.35)):
        band("Black Grip Band %02d" % i, z, 0.112, 0.068,
             MAT["black"], sides=8)

    band("Upper Warning Collar", 1.46, 0.120, 0.085,
         MAT["red"], sides=8)

    # Two separately modeled tines leave a visible central split.
    for side in (-1, 1):
        extrude_polygon(
            "Split Bottom Chisel %s" % side,
            [
                (-0.082, -0.39),
                ( 0.080, -0.39),
                ( 0.105, -0.58),
                (-0.065, -0.65),
                (-0.115, -0.57),
            ],
            0.067, MAT["steel"],
            center_y=side * 0.057,
            bevel=0.012, edge_mat=MAT["edge"]
        )

        extrude_polygon(
            "Split Hook Claw %s" % side,
            [
                (0.59, 1.65),
                (0.70, 1.56),
                (0.55, 1.43),
                (0.39, 1.40),
                (0.44, 1.48),
            ],
            0.067, MAT["steel"],
            center_y=side * 0.057,
            bevel=0.010, edge_mat=MAT["edge"]
        )

    # Actual small paint-loss shapes rather than procedural shaders.
    for i, z in enumerate((0.70, 1.04, 1.28)):
        extrude_polygon(
            "Exposed Paint Chip %02d" % i,
            [(-0.036, z), (0.025, z + 0.026),
             (0.043, z + 0.093), (-0.022, z + 0.071)],
            0.006, MAT["edge"], center_y=-0.104
        )


# ---------------------------------------------------------------------------
# 3. Tactical Street Tanto
# ---------------------------------------------------------------------------

def build_knife():
    # Serrations are cut into the blade silhouette, not floating decals.
    blade = [
        (-0.095, 0.22),
        ( 0.104, 0.22),
        ( 0.133, 0.70),
        ( 0.070, 0.84),
        (-0.052, 0.975),
        (-0.102, 0.69),
        (-0.102, 0.58),
    ]

    for top in (0.56, 0.50, 0.44, 0.38):
        blade.extend([
            (-0.102, top),
            (-0.073, top - 0.014),
            (-0.073, top - 0.029),
            (-0.102, top - 0.041),
        ])

    extrude_polygon(
        "Serrated Tanto Blade", blade, 0.072,
        MAT["gunmetal"], bevel=0.017, edge_mat=MAT["edge"]
    )

    box("Full Tang Handle", (0, 0, -0.006),
        (0.165, 0.110, 0.432), MAT["iron"],
        bevel=0.024, edge_mat=MAT["steel"])

    for side in (-1, 1):
        box("Crimson Grip Scale %s" % side,
            (0, side * 0.070, -0.005),
            (0.156, 0.047, 0.373),
            MAT["red"], bevel=0.021, edge_mat=MAT["red_light"])

        for i, z in enumerate((-0.15, -0.055, 0.04, 0.135)):
            box("Scale Traction Bar %s %s" % (side, i),
                (0, side * 0.097, z),
                (0.114, 0.009, 0.019), MAT["black"])

        for z in (-0.12, 0.115):
            cylinder_between(
                "Handle Pin",
                (0, side * 0.090, z),
                (0, side * 0.105, z),
                0.023, MAT["edge"], sides=8
            )

    box("Asymmetric Finger Guard", (0.022, 0, 0.213),
        (0.325, 0.153, 0.066), MAT["iron"],
        bevel=0.020, edge_mat=MAT["edge"])

    box("Pommel Connection", (0, 0, -0.231),
        (0.119, 0.115, 0.063), MAT["iron"],
        bevel=0.016, edge_mat=MAT["edge"])

    ring_points = [
        (0.056 * math.cos(math.tau * i / 10),
         0,
         -0.272 + 0.056 * math.sin(math.tau * i / 10))
        for i in range(10)
    ]
    tube("Open Lanyard Ring", ring_points, 0.014, 4,
         [MAT["edge"]], closed=True)


# ---------------------------------------------------------------------------
# 4. Underground Street Pistol
# ---------------------------------------------------------------------------

def build_pistol():
    box(
        "Heavy Crimson Slide",
        (0.155, 0, 0.365),
        (0.83, 0.255, 0.225),
        MAT["red"],
        bevel=0.035,
        edge_mat=MAT["red_light"]
    )

    box(
        "Carbon Lower Receiver",
        (0.100, 0, 0.231),
        (0.70, 0.221, 0.095),
        MAT["black"],
        bevel=0.022,
        edge_mat=MAT["iron"]
    )

    # A raked grip whose grasp center is exactly (0, 0, 0).
    grip_outline = [
        (-0.154, -0.237),
        ( 0.043, -0.237),
        ( 0.132,  0.237),
        (-0.065,  0.237),
    ]

    extrude_polygon(
        "Raked Pistol Grip",
        grip_outline,
        0.198,
        MAT["black"],
        bevel=0.020,
        edge_mat=MAT["iron"]
    )

    scale_outline = [
        (-0.127, -0.185),
        ( 0.030, -0.185),
        ( 0.093,  0.158),
        (-0.064,  0.158),
    ]

    for side in (-1, 1):
        extrude_polygon(
            "Faceted Grip Scale %s" % side,
            scale_outline,
            0.022,
            MAT["iron"],
            center_y=side * 0.108,
            bevel=0.008,
            edge_mat=MAT["steel"]
        )

        for i, z in enumerate((-0.125, -0.050, 0.025, 0.100)):
            x = -0.012 + 0.188 * z
            box(
                "Grip Traction %s %s" % (side, i),
                (x, side * 0.122, z),
                (0.105, 0.009, 0.021),
                MAT["black"]
            )

    box(
        "Extended Magazine Base",
        (-0.056, 0, -0.243),
        (0.240, 0.232, 0.068),
        MAT["red"],
        bevel=0.015,
        edge_mat=MAT["red_light"]
    )

    # An actual open trigger guard, not a solid rectangular block.
    guard_outer = [
        (0.075,  0.209),
        (0.329,  0.209),
        (0.373,  0.150),
        (0.347, -0.057),
        (0.111, -0.057),
        (0.071, -0.008),
    ]

    guard_inner = [
        (0.117,  0.166),
        (0.301,  0.166),
        (0.326,  0.137),
        (0.306, -0.014),
        (0.142, -0.014),
        (0.114,  0.013),
    ]

    ring_prism(
        "Oversized Open Trigger Guard",
        guard_outer,
        guard_inner,
        0.139,
        MAT["iron"]
    )

    extrude_polygon(
        "Curved Trigger",
        [
            (0.192, 0.184),
            (0.225, 0.180),
            (0.204, 0.106),
            (0.217, 0.059),
            (0.189, 0.047),
            (0.168, 0.108),
        ],
        0.048,
        MAT["steel"]
    )

    # Raised, angled ribs produce a chunky serration silhouette.
    for side in (-1, 1):
        for region, positions in (
            ("Rear", (-0.193, -0.146, -0.099)),
            ("Front", (0.359, 0.406, 0.453)),
        ):
            for i, x in enumerate(positions):
                box(
                    "%s Slide Serration %s %s" % (region, side, i),
                    (x, side * 0.131, 0.362),
                    (0.019, 0.015, 0.137),
                    MAT["iron"],
                    rotation=(0, math.radians(-12), 0)
                )

    # Recessed-looking ejection port on one side.
    box(
        "Ejection Port Recess",
        (0.115, -0.129, 0.392),
        (0.154, 0.009, 0.072),
        MAT["void"]
    )

    box(
        "Ejection Port Steel Lip",
        (0.115, -0.136, 0.362),
        (0.154, 0.012, 0.012),
        MAT["edge"]
    )

    # Polygonal compensator with an actual open muzzle.
    ring_prism(
        "Open Mini Compensator",
        chamfer_rectangle(0.149, 0.129, 0.032),
        chamfer_rectangle(0.081, 0.068, 0.015),
        0.142,
        MAT["iron"],
        axis='X',
        center=(0.620, 0, 0.365)
    )

    # A recessed dark back wall gives the muzzle cavity visible depth.
    box(
        "Muzzle Cavity Back",
        (0.576, 0, 0.365),
        (0.008, 0.150, 0.124),
        MAT["void"]
    )

    for side in (-1, 1):
        for i, x in enumerate((0.594, 0.643)):
            box(
                "Compensator Vent Inlay %s %s" % (side, i),
                (x, side * 0.150, 0.366),
                (0.025, 0.007, 0.086),
                MAT["void"]
            )

    box(
        "Rear Sight",
        (-0.175, 0, 0.496),
        (0.092, 0.168, 0.054),
        MAT["black"],
        bevel=0.009
    )

    box(
        "Front Sight",
        (0.472, 0, 0.496),
        (0.053, 0.055, 0.051),
        MAT["black"],
        bevel=0.008
    )

    box(
        "Front Sight Yellow Insert",
        (0.447, 0, 0.501),
        (0.006, 0.027, 0.022),
        MAT["yellow"]
    )

    for i, x in enumerate((0.391, 0.452)):
        box(
            "Underbarrel Rail Lug %s" % i,
            (x, 0, 0.177),
            (0.039, 0.246, 0.025),
            MAT["steel"]
        )


# ---------------------------------------------------------------------------
# 5. Riot Breaker Shield
# ---------------------------------------------------------------------------

def shield_surface_y(x):
    """Concave toward the user (+Y), convex toward the street (-Y)."""
    return -0.305 + 0.185 * (x / 1.10) ** 2


def shield_patch(name, polygon_xz, mat):
    """Thin, closed graphic geometry following the curved shield front."""
    n = len(polygon_xz)
    verts = []

    for offset in (-0.080, -0.067):
        for x, z in polygon_xz:
            verts.append((x, shield_surface_y(x) + offset, z))

    faces = [
        tuple(reversed(range(n))),
        tuple(range(n, 2 * n)),
    ]

    for i in range(n):
        j = (i + 1) % n
        faces.append((i, j, n + j, n + i))

    return make_mesh(name, verts, faces, [mat])


def build_shield():
    xs = [-1.10, -0.82, -0.55, 0.0, 0.55, 0.82, 1.10]
    zs = [-2.00, -1.78, -0.75, 0.66, 1.06, 1.78, 2.00]

    nx = len(xs)
    nz = len(zs)
    layer_size = nx * nz
    thickness = 0.130

    verts = []

    for layer in range(2):
        offset = -thickness / 2 if layer == 0 else thickness / 2

        for row, z in enumerate(zs):
            # Taper only the extreme rows for chamfered shield corners.
            width_factor = 0.80 if row in (0, nz - 1) else 1.0

            for x in xs:
                px = x * width_factor
                verts.append((px, shield_surface_y(px) + offset, z))

    faces = []
    indices = []
    edge_uses = {}

    for row in range(nz - 1):
        for col in range(nx - 1):
            # Leave a real viewport opening across the two center columns.
            if row == 3 and col in (2, 3):
                continue

            a = row * nx + col
            b = a + 1
            c = b + nx
            d = a + nx

            face = (a, b, c, d)
            faces.append(face)
            faces.append(tuple(v + layer_size for v in reversed(face)))

            border = (
                col in (0, nx - 2) or
                row in (0, nz - 2)
            )
            indices.extend([1 if border else 0, 2])

            for u, v in zip(face, face[1:] + face[:1]):
                key = tuple(sorted((u, v)))
                edge_uses.setdefault(key, []).append((u, v))

    # Close the perimeter and the viewport reveals.
    boundary_edges = []
    for uses in edge_uses.values():
        if len(uses) == 1:
            a, b = uses[0]
            faces.append((a, a + layer_size, b + layer_size, b))
            indices.append(1)
            boundary_edges.append((a, b))

    shell = make_mesh(
        "Curved Ballistic Shield Shell",
        verts,
        faces,
        [MAT["black"], MAT["iron"], MAT["steel"]],
        indices
    )

    apply_bevel(shell, 0.023, MAT["edge"])

    # Follow the exterior grid perimeter with a chunky faceted bumper.
    perimeter_ids = (
        [col for col in range(nx)] +
        [row * nx + nx - 1 for row in range(1, nz)] +
        [(nz - 1) * nx + col for col in range(nx - 2, -1, -1)] +
        [row * nx for row in range(nz - 2, 0, -1)]
    )

    perimeter = [
        (verts[index][0], verts[index][1] - 0.012, verts[index][2])
        for index in perimeter_ids
    ]

    # The outline is nearly planar; a fixed Y reference preserves its
    # deliberately angular, low-poly cross-section.
    tube(
        "Reinforced Outer Shield Bumper",
        perimeter,
        0.057,
        4,
        [MAT["iron"]],
        closed=True
    )

    # Viewport trim follows the shell curvature.
    viewport_points = [
        (-0.55, shield_surface_y(-0.55) - 0.075, 0.66),
        ( 0.00, shield_surface_y( 0.00) - 0.075, 0.66),
        ( 0.55, shield_surface_y( 0.55) - 0.075, 0.66),
        ( 0.55, shield_surface_y( 0.55) - 0.075, 1.06),
        ( 0.00, shield_surface_y( 0.00) - 0.075, 1.06),
        (-0.55, shield_surface_y(-0.55) - 0.075, 1.06),
    ]

    tube(
        "Armored Open Viewport Frame",
        viewport_points,
        0.047,
        4,
        [MAT["steel"]],
        closed=True
    )

    # Two white diagonal hazard slashes, split at the curvature centerline.
    for i, base_z in enumerate((-1.29, -0.72)):
        for side in (-1, 1):
            x0, x1 = (-0.81, 0.0) if side == -1 else (0.0, 0.81)
            slope = 0.31

            shield_patch(
                "White Hazard Slash %s %s" % (i, side),
                [
                    (x0, base_z + slope * x0),
                    (x1, base_z + slope * x1),
                    (x1, base_z + 0.22 + slope * x1),
                    (x0, base_z + 0.22 + slope * x0),
                ],
                MAT["white"]
            )

    shield_patch(
        "Upper Crimson Identification Block",
        [(-0.42, 1.37), (0.42, 1.37),
         (0.42, 1.60), (-0.42, 1.60)],
        MAT["red"]
    )

    # Primary grip runs through the origin, behind the shield.
    # Secondary grip provides an obvious two-point bracing silhouette.
    for label, x in (("Primary", 0.0), ("Secondary", 0.62)):
        rear_y = shield_surface_y(x) + thickness / 2

        points = [
            (x, rear_y, -0.40),
            (x, -0.020, -0.40),
            (x,  0.000, -0.29),
            (x,  0.000,  0.29),
            (x, -0.020,  0.40),
            (x, rear_y,  0.40),
        ]

        tube(
            label + " Heavy Inner Handle",
            points,
            0.073,
            6,
            [MAT["iron"], MAT["ivory"]],
            segment_materials=[0, 0, 1, 0, 0],
            reference=(1, 0, 0)
        )

        for z in (-0.40, 0.40):
            box(
                label + " Handle Mount",
                (x, rear_y + 0.012, z),
                (0.205, 0.063, 0.170),
                MAT["iron"],
                bevel=0.018,
                edge_mat=MAT["steel"]
            )

    for x in (-0.93, 0.93):
        for z in (-1.61, -0.38, 1.48):
            y = shield_surface_y(x) - thickness / 2
            cylinder_between(
                "Shield Perimeter Fastener",
                (x, y - 0.005, z),
                (x, y - 0.032, z),
                0.041,
                MAT["edge"],
                sides=6
            )


# ---------------------------------------------------------------------------
# Finalization, triangle validation, and FBX export
# ---------------------------------------------------------------------------

def triangle_count(obj):
    obj.data.calc_loop_triangles()
    return len(obj.data.loop_triangles)


def triangulate_object(obj):
    mesh = obj.data
    bm = bmesh.new()
    bm.from_mesh(mesh)

    bmesh.ops.triangulate(
        bm,
        faces=list(bm.faces),
        quad_method='BEAUTY',
        ngon_method='BEAUTY'
    )

    bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
    bm.to_mesh(mesh)
    bm.free()
    mesh.update()


def enforce_triangle_budget(obj):
    """
    Reduce only if needed, then triangulate explicitly.

    If below the requested minimum, split the largest triangles at their
    centers. This does not change the silhouette or material assignments.
    """
    triangulate_object(obj)
    count = triangle_count(obj)

    if count > MAX_TRIS:
        activate(obj)

        decimate = obj.modifiers.new("Triangle Budget Optimization", 'DECIMATE')
        decimate.decimate_type = 'COLLAPSE'
        decimate.ratio = 1320.0 / count
        decimate.use_collapse_triangulate = True
        decimate.delimit = {'MATERIAL'}

        bpy.ops.object.modifier_apply(modifier=decimate.name)
        triangulate_object(obj)
        count = triangle_count(obj)

        if count > MAX_TRIS:
            raise RuntimeError(
                "%s remains over budget: %s triangles." % (obj.name, count)
            )

    if count < MIN_TRIS:
        bm = bmesh.new()
        bm.from_mesh(obj.data)

        while len(bm.faces) < MIN_TRIS:
            largest = max(bm.faces, key=lambda face: face.calc_area())
            bmesh.ops.poke(
                bm,
                faces=[largest],
                offset=0.0,
                center_mode='MEAN_WEIGHTED',
                use_relative_offset=False
            )

        bmesh.ops.recalc_face_normals(bm, faces=list(bm.faces))
        bm.to_mesh(obj.data)
        bm.free()
        obj.data.update()

    triangulate_object(obj)
    count = triangle_count(obj)

    if not MIN_TRIS <= count <= MAX_TRIS:
        raise RuntimeError(
            "%s failed triangle validation: %s" % (obj.name, count)
        )

    return count


def finalize_asset(name, target_axis, target_size):
    if not PARTS:
        raise RuntimeError("Builder created no geometry for " + name)

    deselect()

    for obj in PARTS:
        obj.select_set(True)

    bpy.context.view_layer.objects.active = PARTS[0]
    bpy.ops.object.join()

    obj = bpy.context.object
    obj.name = name
    obj.data.name = name + "_Mesh"

    # Bake every component's position into the joined mesh.
    bpy.ops.object.transform_apply(
        location=True,
        rotation=True,
        scale=True
    )

    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR', center='MEDIAN')

    axis = {'X': 0, 'Y': 1, 'Z': 2}[target_axis]
    coordinates = [vertex.co[axis] for vertex in obj.data.vertices]
    extent = max(coordinates) - min(coordinates)

    if extent <= 0:
        raise RuntimeError("Invalid primary dimension for " + name)

    # Scale about the grip pivot, not the bounding-box center.
    scale_factor = target_size / extent
    for vertex in obj.data.vertices:
        vertex.co *= scale_factor

    obj.data.update()
    count = enforce_triangle_budget(obj)

    # Flat shading intentionally preserves the faceted style.
    for polygon in obj.data.polygons:
        polygon.use_smooth = False

    activate(obj)
    bpy.ops.object.transform_apply(
        location=True,
        rotation=True,
        scale=True
    )

    bpy.context.view_layer.update()

    obj["asset_type"] = "Stylized game weapon prop"
    obj["grip_pivot"] = "World origin; no bounding-box recentering"
    obj["stud_meters"] = STUD_METERS
    obj["triangle_count"] = count
    obj["primary_axis"] = target_axis
    obj["requested_size_studs"] = target_size

    if obj.location.length > 1e-6:
        raise RuntimeError("Nonzero pivot location on " + name)

    return obj


def ensure_fbx_exporter():
    if hasattr(bpy.ops.export_scene, "fbx"):
        return

    try:
        bpy.ops.preferences.addon_enable(module="io_scene_fbx")
    except Exception as exc:
        raise RuntimeError(
            "Blender's FBX exporter is unavailable. Enable/install the "
            "standard FBX import/export add-on and run again."
        ) from exc

    if not hasattr(bpy.ops.export_scene, "fbx"):
        raise RuntimeError("FBX export operator could not be registered.")


def export_asset(obj, filepath):
    activate(obj)

    bpy.ops.export_scene.fbx(
        filepath=filepath,
        check_existing=False,
        use_selection=True,
        object_types={'MESH'},
        global_scale=1.0,
        apply_unit_scale=True,
        apply_scale_options='FBX_SCALE_UNITS',
        use_space_transform=True,
        bake_space_transform=False,
        axis_forward='-Z',
        axis_up='Y',
        mesh_smooth_type='FACE',
        use_mesh_modifiers=True,
        use_triangles=True,
        use_custom_props=True,
        add_leaf_bones=False,
        bake_anim=False,
        path_mode='AUTO'
    )

    if not os.path.isfile(filepath):
        raise RuntimeError("FBX was not written: " + filepath)


def parse_args():
    args = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

    parser = argparse.ArgumentParser(
        description="Generate five chunky low-poly weapon props for Roblox."
    )
    parser.add_argument(
        "--out",
        default=os.path.join(os.getcwd(), "thug_weapons"),
        help="Output directory for individual FBX files and the manifest."
    )
    parser.add_argument(
        "--save-blend",
        action="store_true",
        help="Also save one editable .blend file per weapon."
    )

    return parser.parse_args(args)


def main():
    args = parse_args()
    output_dir = os.path.abspath(os.path.expanduser(args.out))
    os.makedirs(output_dir, exist_ok=True)

    ensure_fbx_exporter()
    clear_scene()

    scene = bpy.context.scene
    scene.unit_settings.system = 'METRIC'
    scene.unit_settings.scale_length = STUD_METERS
    scene.unit_settings.length_unit = 'METERS'

    create_materials()

    roster = [
        ("baseball_bat", build_bat,    'Z', 3.2),
        ("crowbar",      build_crowbar, 'Z', 2.8),
        ("combat_knife", build_knife,   'Z', 1.3),
        ("handgun",      build_pistol,  'X', 1.0),
        ("riot_shield",  build_shield,  'Z', 4.0),
    ]

    manifest = {
        "generator": "generate_thug_weapons.py",
        "blender_version": bpy.app.version_string,
        "meters_per_stud": STUD_METERS,
        "authoring_axes": {
            "up": "+Z",
            "pistol_muzzle": "+X",
            "shield_front": "-Y",
        },
        "fbx_axes": {
            "forward": "-Z",
            "up": "Y",
        },
        "notes": [
            "All mesh origins are the intended hand-grip center.",
            "Roblox Tool.Grip rotation still depends on the character rig.",
            "Do not recenter imported mesh pivots to geometry bounds.",
            "FBX stores constant material colors; Roblox may not reproduce "
            "every Principled BSDF metallic/roughness parameter.",
            "Disconnected intersecting mesh components are intentional "
            "game-prop construction, not a watertight manufacturing mesh.",
        ],
        "assets": [],
    }

    for name, builder, axis, target in roster:
        clear_scene()
        builder()

        obj = finalize_asset(name, axis, target)
        filepath = os.path.join(output_dir, name + ".fbx")
        export_asset(obj, filepath)

        dimensions = [float(value) for value in obj.dimensions]

        material_records = []
        for slot in obj.material_slots:
            mat = slot.material
            if mat is None:
                continue

            material_records.append({
                "name": mat.name,
                "base_color_rgba": list(mat.diffuse_color),
                "roughness": float(mat.roughness),
                "metallic": float(mat.metallic),
            })

        record = {
            "name": name,
            "file": name + ".fbx",
            "triangles": triangle_count(obj),
            "vertices": len(obj.data.vertices),
            "dimensions_studs_xyz": dimensions,
            "dimensions_meters_xyz": [
                value * STUD_METERS for value in dimensions
            ],
            "grip_pivot_xyz": list(obj.location),
            "rotation_euler_xyz": list(obj.rotation_euler),
            "scale_xyz": list(obj.scale),
            "primary_dimension_axis": axis,
            "primary_dimension_studs": target,
            "materials": material_records,
        }
        manifest["assets"].append(record)

        if args.save_blend:
            bpy.ops.wm.save_as_mainfile(
                filepath=os.path.join(output_dir, name + ".blend")
            )

        print(
            "[EXPORTED] %-14s %4d triangles | "
            "%.3f x %.3f x %.3f studs | %s"
            % (
                name,
                record["triangles"],
                dimensions[0],
                dimensions[1],
                dimensions[2],
                filepath,
            )
        )

    manifest_path = os.path.join(output_dir, "weapon_manifest.json")
    with open(manifest_path, "w", encoding="utf-8") as handle:
        json.dump(manifest, handle, indent=2)

    print("\nFinished. Five individual FBX assets written to:")
    print(output_dir)
    print("Manifest:", manifest_path)


if __name__ == "__main__":
    main()
