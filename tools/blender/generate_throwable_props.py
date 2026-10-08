#!/usr/bin/env python3
"""
generate_throwable_props.py

Standalone Blender 3.6+ / 5.x script for generating correctly-scaled Roblox props.

Usage:
    blender --background --python generate_throwable_props.py -- --output-dir ./throwable_props

Produces:
    manhole_cover.fbx           (3.6 x 3.6 x 0.35 studs)
    trash_can.fbx               (2.8 x 2.8 x 4.2 studs, separate lid)
    wooden_crate.fbx            (4.8 x 4.8 x 4.8 studs)
    construction_barrel.fbx     (2.6 x 2.6 x 4.8 studs)
    mailbox_classic_usps.fbx    (2.6 x 2.4 x 5.0 studs)
    mailbox_double_chute.fbx    (4.6 x 2.4 x 5.0 studs)
    mailbox_combat_dented.fbx   (2.6 x 2.5 x 4.8 studs)
    mailbox_relay_green.fbx     (2.8 x 2.5 x 4.5 studs)
    mailbox_vintage_pillar.fbx  (2.4 x 2.4 x 5.2 studs)
    export_report.json

Scale:
    1 unit in Blender = 1 Roblox Stud (Heroic Character Scale, Player = 5 studs tall).
    Exported with FBX_SCALE_NONE and apply_unit_scale=False so vertex coordinates
    directly correspond to Roblox Stud dimensions.
"""

import argparse
import bpy
import bmesh
import json
import math
import os
import sys

from mathutils import Matrix, Vector

MIN_TRIANGLES = 400
MAX_TRIANGLES = 2200

MATERIALS = {}


# ---------------------------------------------------------------------------
# Scene and material utilities
# ---------------------------------------------------------------------------

def parse_arguments():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []

    script_path = globals().get("__file__")
    base_dir = (
        os.path.dirname(os.path.abspath(script_path))
        if script_path else os.getcwd()
    )

    parser = argparse.ArgumentParser(
        description="Generate stylized Roblox throwable and street props."
    )
    parser.add_argument(
        "--output-dir",
        default=os.path.join(base_dir, "throwable_props"),
        help="Destination folder for FBX files and export_report.json.",
    )
    return parser.parse_args(argv)


def clear_scene():
    if bpy.context.object and bpy.context.object.mode != "OBJECT":
        bpy.ops.object.mode_set(mode="OBJECT")

    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)

    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

    for collection in list(bpy.data.collections):
        if collection.name.startswith("__COM_"):
            bpy.data.collections.remove(collection)

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)


def configure_scene():
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.unit_settings.length_unit = "METERS"
    scene.unit_settings.scale_length = 1.0


def activate_only(objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def create_material(name, color, metallic=0.0, roughness=0.5):
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


def create_materials():
    create_material("Iron_Dark",       (0.055, 0.068, 0.080), 0.78, 0.64)
    create_material("Iron_Scraped",    (0.230, 0.255, 0.280), 0.85, 0.34)
    create_material("Iron_Grooves",    (0.025, 0.032, 0.039), 0.55, 0.78)

    create_material("Zinc_Matte",      (0.370, 0.425, 0.450), 0.70, 0.61)
    create_material("Zinc_Worn",       (0.590, 0.640, 0.655), 0.82, 0.36)
    create_material("Zinc_Interior",   (0.220, 0.265, 0.285), 0.62, 0.73)

    create_material("Wood_Pine",       (0.560, 0.300, 0.115), 0.00, 0.79)
    create_material("Wood_Oak",        (0.660, 0.390, 0.160), 0.00, 0.76)
    create_material("Wood_Pale",       (0.730, 0.460, 0.205), 0.00, 0.77)
    create_material("Wood_Frame",      (0.255, 0.115, 0.038), 0.00, 0.83)
    create_material("Wood_Frame_Edge", (0.380, 0.195, 0.068), 0.00, 0.75)

    create_material("Safety_Orange",   (1.000, 0.190, 0.012), 0.00, 0.43)
    create_material("Reflective_White",(0.920, 0.945, 0.920), 0.18, 0.23)
    create_material("Recycled_Rubber", (0.022, 0.027, 0.032), 0.00, 0.91)
    create_material("Rubber_Edge",     (0.055, 0.064, 0.070), 0.00, 0.84)

    create_material("Postal_Blue",     (0.018, 0.070, 0.260), 0.36, 0.48)
    create_material("Postal_Edge",     (0.055, 0.145, 0.390), 0.42, 0.38)
    create_material("Postal_Panel",    (0.013, 0.045, 0.165), 0.32, 0.56)
    create_material("Postal_Green",    (0.035, 0.125, 0.065), 0.30, 0.52)
    create_material("Postal_Green_Edge",(0.070, 0.210, 0.110), 0.38, 0.42)
    create_material("Brass_Accent",    (0.780, 0.620, 0.220), 0.88, 0.24)
    create_material("Chrome",          (0.720, 0.790, 0.840), 0.94, 0.19)
    create_material("Dark_Steel",      (0.040, 0.052, 0.066), 0.76, 0.55)
    create_material("Steel_Edge",      (0.125, 0.150, 0.175), 0.78, 0.42)
    create_material("Slot_Shadow",     (0.008, 0.012, 0.020), 0.10, 0.86)
    create_material("Label_Enamel",    (0.800, 0.850, 0.875), 0.12, 0.40)


# ---------------------------------------------------------------------------
# Geometry primitives
# ---------------------------------------------------------------------------

def mesh_object(name, vertices, faces, material_names, face_materials=None):
    mesh = bpy.data.meshes.new(name + "_Mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    for material_name in material_names:
        mesh.materials.append(MATERIALS[material_name])

    if face_materials is not None:
        if len(face_materials) != len(mesh.polygons):
            raise RuntimeError("Face material count mismatch: " + name)
        for polygon, index in zip(mesh.polygons, face_materials):
            polygon.material_index = index

    for polygon in mesh.polygons:
        polygon.use_smooth = False

    return obj


def apply_bevel(obj, width, edge_material_index=-1):
    if width <= 0.0:
        return

    activate_only([obj])

    modifier = obj.modifiers.new("Single_Segment_Faceted_Chamfer", "BEVEL")
    modifier.width = width
    modifier.segments = 1
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = math.radians(35.0)
    modifier.use_clamp_overlap = True
    modifier.material = edge_material_index

    bpy.ops.object.modifier_apply(modifier=modifier.name)


def box(name, center, dimensions, material, bevel=0.0,
        edge_material=None, rotation=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions

    if rotation is not None:
        obj.rotation_euler = rotation.to_euler()

    bpy.ops.object.transform_apply(
        location=False, rotation=False, scale=True
    )

    obj.data.materials.append(MATERIALS[material])
    edge_index = -1

    if edge_material is not None:
        obj.data.materials.append(MATERIALS[edge_material])
        edge_index = 1

    apply_bevel(obj, bevel, edge_index)
    return obj


def beam(name, start, end, width, material, bevel=0.012,
         edge_material=None):
    start = Vector(start)
    end = Vector(end)
    direction = end - start

    if direction.length <= 1.0e-8:
        raise ValueError("Zero-length beam: " + name)

    rotation = direction.to_track_quat("Z", "Y").to_matrix()

    return box(
        name,
        (start + end) * 0.5,
        (width, width, direction.length),
        material,
        bevel,
        edge_material,
        rotation,
    )


def flat_brace(name, start, end, face_normal, width, thickness,
               material, edge_material):
    start = Vector(start)
    end = Vector(end)

    x_axis = (end - start).normalized()
    z_axis = Vector(face_normal).normalized()
    y_axis = z_axis.cross(x_axis).normalized()
    rotation = Matrix((x_axis, y_axis, z_axis)).transposed()

    return box(
        name,
        (start + end) * 0.5,
        ((end - start).length, width, thickness),
        material,
        bevel=0.015,
        edge_material=edge_material,
        rotation=rotation,
    )


def lathe(name, profile, segments, material_names,
          segment_materials=None, phase=0.0, deform=None):
    vertices = []
    rings = []

    for profile_index, (radius, height) in enumerate(profile):
        if abs(radius) < 1.0e-10:
            rings.append([len(vertices)])
            vertices.append((0.0, 0.0, height))
            continue

        ring = []
        for i in range(segments):
            angle = phase + (2.0 * math.pi * i / segments)
            r, z = radius, height

            if deform is not None:
                r, z = deform(profile_index, i, angle, r, z)

            ring.append(len(vertices))
            vertices.append((r * math.cos(angle), r * math.sin(angle), z))
        rings.append(ring)

    faces = []
    face_materials = []

    for profile_index in range(len(profile)):
        a = rings[profile_index]
        b = rings[(profile_index + 1) % len(profile)]

        material_index = (
            segment_materials[profile_index]
            if segment_materials is not None else 0
        )

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
            face_materials.append(material_index)

    return mesh_object(
        name, vertices, faces, material_names, face_materials
    )


def extrude_xz_polygon(name, polygon_xz, y_front, y_back,
                       material, bevel=0.0, edge_material=None):
    count = len(polygon_xz)

    vertices = [(x, y_front, z) for x, z in polygon_xz]
    vertices += [(x, y_back, z) for x, z in polygon_xz]

    faces = [
        tuple(range(count)),
        tuple(reversed(range(count, 2 * count))),
    ]

    for i in range(count):
        j = (i + 1) % count
        faces.append((i, count + i, count + j, j))

    material_names = [material]
    if edge_material is not None:
        material_names.append(edge_material)

    obj = mesh_object(name, vertices, faces, material_names)
    apply_bevel(obj, bevel, 1 if edge_material else -1)
    return obj


# ---------------------------------------------------------------------------
# Prop 1: NYC manhole cover (3.6 x 3.6 x 0.35 studs)
# ---------------------------------------------------------------------------

def build_manhole():
    profile = [
        (0.110, -0.060),
        (0.760, -0.060),
        (0.800, -0.030),
        (0.800,  0.030),
        (0.770,  0.060),
        (0.690,  0.060),
        (0.675,  0.041),
        (0.520,  0.041),
        (0.505,  0.024),
        (0.490,  0.041),
        (0.145,  0.041),
        (0.110,  0.022),
    ]

    def traction_deformation(profile_index, i, angle, radius, height):
        if profile_index in (6, 7, 9, 10):
            if i % 4 in (0, 1):
                height -= 0.012
        return radius, height

    obj = lathe(
        "ManholeCover",
        profile,
        segments=48,
        material_names=["Iron_Dark", "Iron_Scraped", "Iron_Grooves"],
        segment_materials=[0, 1, 0, 1, 1, 0, 0, 2, 2, 0, 1, 2],
        deform=traction_deformation,
    )

    return {"ManholeCover": [obj]}


# ---------------------------------------------------------------------------
# Prop 2: Corrugated trash can (2.8 x 2.8 x 4.2 studs)
# ---------------------------------------------------------------------------

def build_trash_can():
    body_profile = [
        (0.000, 0.000),
        (0.570, 0.000),
        (0.620, 0.045),
        (0.650, 0.120),
        (0.730, 1.700),
        (0.740, 1.770),
        (0.730, 1.810),
        (0.685, 1.810),
        (0.675, 1.710),
        (0.595, 0.140),
        (0.000, 0.140),
    ]

    def corrugation(profile_index, i, angle, radius, height):
        if profile_index in (3, 4, 8, 9):
            radius += 0.018 if i % 2 == 0 else -0.018
        return radius, height

    body = lathe(
        "TrashCan_CorrugatedBody",
        body_profile,
        segments=32,
        material_names=["Zinc_Matte", "Zinc_Worn", "Zinc_Interior"],
        segment_materials=[0, 1, 1, 0, 1, 1, 1, 2, 2, 2, 2],
        deform=corrugation,
    )

    body_parts = [body]

    for side in (-1, 1):
        x_inner = side * 0.690
        x_outer = side * 0.910

        for y, suffix in ((-0.170, "Front"), (0.170, "Back")):
            body_parts.append(beam(
                f"TrashCan_Side{side}_{suffix}HandleArm",
                (x_inner, y, 1.300),
                (x_outer, y, 1.300),
                0.075,
                "Zinc_Matte",
                bevel=0.012,
                edge_material="Zinc_Worn",
            ))

        body_parts.append(beam(
            f"TrashCan_Side{side}_HandleGrip",
            (x_outer, -0.170, 1.300),
            (x_outer,  0.170, 1.300),
            0.085,
            "Zinc_Matte",
            bevel=0.014,
            edge_material="Zinc_Worn",
        ))

    lid_profile = [
        (0.000, 1.795),
        (0.680, 1.795),
        (0.780, 1.795),
        (0.810, 1.830),
        (0.810, 1.880),
        (0.750, 1.920),
        (0.500, 1.950),
        (0.000, 1.965),
    ]

    def dent(profile_index, i, angle, radius, height):
        influence = max(0.0, math.cos(angle - 0.65)) ** 10
        if profile_index == 5:
            height -= 0.018 * influence
        elif profile_index == 6:
            height -= 0.045 * influence
        return radius, height

    lid = lathe(
        "TrashCan_DentedLid",
        lid_profile,
        segments=24,
        material_names=["Zinc_Matte", "Zinc_Worn", "Zinc_Interior"],
        segment_materials=[2, 2, 1, 1, 1, 0, 0, 2],
        deform=dent,
    )

    lid_parts = [lid]

    for x in (-0.200, 0.200):
        lid_parts.append(beam(
            f"TrashCan_LidHandlePost_{x:+.2f}",
            (x, 0.0, 1.940),
            (x, 0.0, 2.100),
            0.065,
            "Zinc_Matte",
            bevel=0.010,
            edge_material="Zinc_Worn",
        ))

    lid_parts.append(beam(
        "TrashCan_LidHandleGrip",
        (-0.200, 0.0, 2.100),
        ( 0.200, 0.0, 2.100),
        0.075,
        "Zinc_Matte",
        bevel=0.012,
        edge_material="Zinc_Worn",
    ))

    return {
        "TrashCan_Body": body_parts,
        "TrashCan_Lid": lid_parts,
    }


# ---------------------------------------------------------------------------
# Prop 3: Industrial shipping crate (4.8 x 4.8 x 4.8 studs)
# ---------------------------------------------------------------------------

def build_crate():
    parts = []

    for long_axis in range(3):
        other_axes = [axis for axis in range(3) if axis != long_axis]

        for sign_a in (-1, 1):
            for sign_b in (-1, 1):
                center = [0.0, 0.0, 0.0]
                center[other_axes[0]] = sign_a * 1.015
                center[other_axes[1]] = sign_b * 1.015

                dimensions = [0.170, 0.170, 0.170]
                dimensions[long_axis] = 2.200

                parts.append(box(
                    f"Crate_Frame_{long_axis}_{sign_a}_{sign_b}",
                    center,
                    dimensions,
                    "Wood_Frame",
                    bevel=0.024,
                    edge_material="Wood_Frame_Edge",
                ))

    plank_materials = ["Wood_Pine", "Wood_Oak", "Wood_Pale"]

    for normal_axis in range(3):
        tangent_axes = [
            axis for axis in range(3) if axis != normal_axis
        ]
        u_axis, v_axis = tangent_axes

        for sign in (-1, 1):
            for plank_index in range(3):
                center = [0.0, 0.0, 0.0]
                center[normal_axis] = sign * 0.985
                center[u_axis] = (plank_index - 1) * 0.600

                dimensions = [0.0, 0.0, 0.0]
                dimensions[normal_axis] = 0.100
                dimensions[u_axis] = 0.588
                dimensions[v_axis] = 1.800

                parts.append(box(
                    f"Crate_Face_{normal_axis}_{sign}_Plank{plank_index}",
                    center,
                    dimensions,
                    plank_materials[
                        (plank_index + normal_axis) % len(plank_materials)
                    ],
                ))

            normal = Vector((0.0, 0.0, 0.0))
            normal[normal_axis] = sign

            face_center = normal * 1.055
            diagonal_sign = 1 if (normal_axis + (sign > 0)) % 2 else -1

            offset = Vector((0.0, 0.0, 0.0))
            offset[u_axis] = 0.800
            offset[v_axis] = 0.800 * diagonal_sign

            parts.append(flat_brace(
                f"Crate_Face_{normal_axis}_{sign}_DiagonalBrace",
                face_center - offset,
                face_center + offset,
                normal,
                width=0.170,
                thickness=0.090,
                material="Wood_Frame",
                edge_material="Wood_Frame_Edge",
            ))

    return {"WoodenCrate": parts}


# ---------------------------------------------------------------------------
# Prop 4: Stepped safety barrel (2.6 x 2.6 x 4.8 studs)
# ---------------------------------------------------------------------------

def build_barrel():
    base = lathe(
        "ConstructionBarrel_HexRubberBase",
        [
            (0.000, 0.000),
            (0.880, 0.000),
            (0.920, 0.040),
            (0.920, 0.180),
            (0.870, 0.230),
            (0.000, 0.230),
        ],
        segments=6,
        phase=math.pi / 6.0,
        material_names=["Recycled_Rubber", "Rubber_Edge"],
        segment_materials=[0, 1, 0, 1, 0, 0],
    )

    profile = [
        (0.000, 0.180),
        (0.670, 0.180),
        (0.730, 0.240),
        (0.730, 0.400),
        (0.690, 0.440),
        (0.680, 0.700),
        (0.655, 0.740),
        (0.630, 1.000),
        (0.615, 1.040),
        (0.590, 1.300),
        (0.575, 1.340),
        (0.550, 1.560),
        (0.510, 1.610),
        (0.510, 1.750),
        (0.470, 1.800),
        (0.000, 1.800),
    ]

    bands = [0] * len(profile)
    for band_index in (5, 6, 9, 10):
        bands[band_index] = 1

    body = lathe(
        "ConstructionBarrel_SteppedHazardBody",
        profile,
        segments=32,
        material_names=["Safety_Orange", "Reflective_White"],
        segment_materials=bands,
    )

    return {"ConstructionBarrel": [base, body]}


# ---------------------------------------------------------------------------
# Mailbox Variant 1: Classic Blue USPS Drop Box (2.6 x 2.4 x 5.0 studs)
# ---------------------------------------------------------------------------

def build_mailbox_classic():
    parts = []
    arch_radius = 0.700
    spring_height = 1.900

    polygon = [(-0.700, 0.580), (0.700, 0.580)]
    for i in range(13):
        angle = math.pi * i / 12.0
        polygon.append((
            arch_radius * math.cos(angle),
            spring_height + arch_radius * math.sin(angle),
        ))

    parts.append(extrude_xz_polygon(
        "Mailbox_ArchedBody",
        polygon,
        y_front=-0.530,
        y_back=0.700,
        material="Postal_Blue",
        bevel=0.025,
        edge_material="Postal_Edge",
    ))

    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(beam(
                f"Mailbox_Leg_{sx}_{sy}",
                (sx * 0.550, sy * 0.470, 0.080),
                (sx * 0.470, sy * 0.400, 0.660),
                width=0.120,
                material="Dark_Steel",
                bevel=0.015,
                edge_material="Steel_Edge",
            ))
            parts.append(box(
                f"Mailbox_Foot_{sx}_{sy}",
                (sx * 0.550, sy * 0.470, 0.055),
                (0.220, 0.240, 0.110),
                "Dark_Steel",
                bevel=0.018,
                edge_material="Steel_Edge",
            ))

    parts.append(box(
        "Mailbox_MailSlotReveal",
        (0.0, -0.540, 1.905),
        (0.980, 0.025, 0.130),
        "Slot_Shadow",
    ))

    flap_rotation = Matrix.Rotation(math.radians(8.0), 3, "X")
    parts.append(box(
        "Mailbox_DropFlap",
        (0.0, -0.560, 1.675),
        (1.035, 0.065, 0.315),
        "Postal_Blue",
        bevel=0.020,
        edge_material="Postal_Edge",
        rotation=flap_rotation,
    ))

    for x in (-0.220, 0.220):
        parts.append(beam(
            f"Mailbox_ChromeHandleArm_{x:+.2f}",
            (x, -0.590, 1.665),
            (x, -0.715, 1.665),
            width=0.060,
            material="Chrome",
            bevel=0.010,
        ))

    parts.append(beam(
        "Mailbox_ChromePullGrip",
        (-0.220, -0.715, 1.665),
        ( 0.220, -0.715, 1.665),
        width=0.070,
        material="Chrome",
        bevel=0.012,
    ))

    parts.append(box(
        "Mailbox_RearServicePanel",
        (0.0, 0.704, 1.145),
        (1.055, 0.030, 0.925),
        "Postal_Panel",
        bevel=0.025,
        edge_material="Postal_Edge",
    ))

    for sx in (-1, 1):
        parts.append(box(
            f"Mailbox_SideEmbossedPanel_{sx}",
            (sx * 0.695, 0.065, 1.210),
            (0.035, 0.875, 0.835),
            "Postal_Blue",
            bevel=0.020,
            edge_material="Postal_Edge",
        ))

    parts.append(box(
        "Mailbox_EnamelCollectionPlate",
        (0.0, -0.549, 1.075),
        (0.405, 0.030, 0.245),
        "Label_Enamel",
        bevel=0.012,
    ))

    return {"Mailbox_Classic": parts}


# ---------------------------------------------------------------------------
# Mailbox Variant 2: Double-Chute Twin Drop Box (4.6 x 2.4 x 5.0 studs)
# ---------------------------------------------------------------------------

def build_mailbox_double():
    parts = []
    width_half = 1.350
    spring_height = 1.900

    polygon = [(-width_half, 0.580), (width_half, 0.580)]
    for i in range(13):
        angle = math.pi * i / 12.0
        polygon.append((
            width_half * math.cos(angle),
            spring_height + 0.650 * math.sin(angle),
        ))

    parts.append(extrude_xz_polygon(
        "DoubleMailbox_ArchedBody",
        polygon,
        y_front=-0.530,
        y_back=0.700,
        material="Postal_Blue",
        bevel=0.025,
        edge_material="Postal_Edge",
    ))

    # Center vertical dividing rib
    parts.append(box(
        "DoubleMailbox_CenterDivider",
        (0.0, -0.550, 1.550),
        (0.090, 0.050, 1.900),
        "Dark_Steel",
        bevel=0.015,
        edge_material="Steel_Edge",
    ))

    # 4 Corner legs
    for sx in (-1, 1):
        for sy in (-1, 1):
            parts.append(beam(
                f"DoubleMailbox_Leg_{sx}_{sy}",
                (sx * 1.150, sy * 0.470, 0.080),
                (sx * 1.050, sy * 0.400, 0.660),
                width=0.140,
                material="Dark_Steel",
                bevel=0.015,
                edge_material="Steel_Edge",
            ))
            parts.append(box(
                f"DoubleMailbox_Foot_{sx}_{sy}",
                (sx * 1.150, sy * 0.470, 0.055),
                (0.240, 0.240, 0.110),
                "Dark_Steel",
                bevel=0.018,
                edge_material="Steel_Edge",
            ))

    # Dual drop flaps (Left = Metered, Right = Stamped)
    flap_rotation = Matrix.Rotation(math.radians(8.0), 3, "X")
    for chute_idx, chute_x in enumerate((-0.680, 0.680)):
        suffix = "Left" if chute_idx == 0 else "Right"

        parts.append(box(
            f"DoubleMailbox_MailSlotReveal_{suffix}",
            (chute_x, -0.540, 1.905),
            (0.920, 0.025, 0.130),
            "Slot_Shadow",
        ))

        parts.append(box(
            f"DoubleMailbox_DropFlap_{suffix}",
            (chute_x, -0.560, 1.675),
            (0.960, 0.065, 0.315),
            "Postal_Blue",
            bevel=0.020,
            edge_material="Postal_Edge",
            rotation=flap_rotation,
        ))

        for arm_x in (chute_x - 0.200, chute_x + 0.200):
            parts.append(beam(
                f"DoubleMailbox_HandleArm_{suffix}_{arm_x:+.2f}",
                (arm_x, -0.590, 1.665),
                (arm_x, -0.715, 1.665),
                width=0.055,
                material="Chrome",
                bevel=0.010,
            ))

        parts.append(beam(
            f"DoubleMailbox_PullGrip_{suffix}",
            (chute_x - 0.200, -0.715, 1.665),
            (chute_x + 0.200, -0.715, 1.665),
            width=0.065,
            material="Chrome",
            bevel=0.012,
        ))

        parts.append(box(
            f"DoubleMailbox_Plate_{suffix}",
            (chute_x, -0.549, 1.075),
            (0.480, 0.030, 0.245),
            "Label_Enamel",
            bevel=0.012,
        ))

    # Rear service panel
    parts.append(box(
        "DoubleMailbox_RearServicePanel",
        (0.0, 0.704, 1.145),
        (2.050, 0.030, 0.925),
        "Postal_Panel",
        bevel=0.025,
        edge_material="Postal_Edge",
    ))

    return {"Mailbox_Double": parts}


# ---------------------------------------------------------------------------
# Mailbox Variant 3: Combat-Dented Superhero Battle Mailbox (2.6 x 2.5 x 4.8 studs)
# ---------------------------------------------------------------------------

def build_mailbox_damaged():
    parts = []
    arch_radius = 0.700
    spring_height = 1.900

    # Slightly warped roof arch profile
    polygon = [(-0.700, 0.580), (0.700, 0.580)]
    for i in range(13):
        angle = math.pi * i / 12.0
        r = arch_radius
        # Dent on top right
        if 2 <= i <= 5:
            r -= 0.120
        polygon.append((
            r * math.cos(angle),
            spring_height + r * math.sin(angle),
        ))

    parts.append(extrude_xz_polygon(
        "DentedMailbox_ArchedBody",
        polygon,
        y_front=-0.530,
        y_back=0.700,
        material="Postal_Blue",
        bevel=0.025,
        edge_material="Iron_Scraped",
    ))

    # Legs: front right leg is bent inward
    for sx in (-1, 1):
        for sy in (-1, 1):
            if sx == 1 and sy == -1:
                # Bent damaged leg
                parts.append(beam(
                    "DentedMailbox_Leg_Bent",
                    (sx * 0.550 - 0.180, sy * 0.470 + 0.120, 0.080),
                    (sx * 0.470, sy * 0.400, 0.660),
                    width=0.120,
                    material="Dark_Steel",
                    bevel=0.015,
                    edge_material="Iron_Scraped",
                ))
                parts.append(box(
                    "DentedMailbox_Foot_Bent",
                    (sx * 0.550 - 0.180, sy * 0.470 + 0.120, 0.055),
                    (0.220, 0.240, 0.110),
                    "Dark_Steel",
                    bevel=0.018,
                    edge_material="Iron_Scraped",
                ))
            else:
                parts.append(beam(
                    f"DentedMailbox_Leg_{sx}_{sy}",
                    (sx * 0.550, sy * 0.470, 0.080),
                    (sx * 0.470, sy * 0.400, 0.660),
                    width=0.120,
                    material="Dark_Steel",
                    bevel=0.015,
                    edge_material="Steel_Edge",
                ))
                parts.append(box(
                    f"DentedMailbox_Foot_{sx}_{sy}",
                    (sx * 0.550, sy * 0.470, 0.055),
                    (0.220, 0.240, 0.110),
                    "Dark_Steel",
                    bevel=0.018,
                    edge_material="Steel_Edge",
                ))

    # Exposed mail slot reveal
    parts.append(box(
        "DentedMailbox_MailSlotReveal",
        (0.0, -0.540, 1.905),
        (0.980, 0.025, 0.130),
        "Slot_Shadow",
    ))

    # Jammed ajar drop flap (tilted heavily forward and skewed)
    jammed_rot = (
        Matrix.Rotation(math.radians(28.0), 3, "X") @
        Matrix.Rotation(math.radians(-7.0), 3, "Z")
    )
    parts.append(box(
        "DentedMailbox_DropFlap",
        (0.020, -0.620, 1.640),
        (1.035, 0.065, 0.315),
        "Postal_Blue",
        bevel=0.020,
        edge_material="Iron_Scraped",
        rotation=jammed_rot,
    ))

    # Crooked chrome handle
    for x in (-0.220, 0.220):
        parts.append(beam(
            f"DentedMailbox_HandleArm_{x:+.2f}",
            (x + 0.020, -0.650, 1.630),
            (x + 0.030, -0.780, 1.610),
            width=0.060,
            material="Chrome",
            bevel=0.010,
        ))

    parts.append(beam(
        "DentedMailbox_PullGrip",
        (-0.200, -0.780, 1.610),
        ( 0.240, -0.770, 1.600),
        width=0.070,
        material="Chrome",
        bevel=0.012,
    ))

    # Scratched schedule plate
    parts.append(box(
        "DentedMailbox_Plate",
        (0.0, -0.549, 1.075),
        (0.405, 0.030, 0.245),
        "Label_Enamel",
        bevel=0.012,
        edge_material="Iron_Scraped",
    ))

    return {"Mailbox_Damaged": parts}


# ---------------------------------------------------------------------------
# Mailbox Variant 4: NYC Forest Green Relay / Storage Box (2.8 x 2.5 x 4.5 studs)
# ---------------------------------------------------------------------------

def build_mailbox_relay():
    parts = []

    # Heavy rectangular welded steel cabinet
    parts.append(box(
        "Relay_Cabinet",
        (0.0, 0.0, 1.450),
        (1.350, 1.150, 1.550),
        "Postal_Green",
        bevel=0.025,
        edge_material="Postal_Green_Edge",
    ))

    # Sloped weather-shedding roof lid
    roof_rot = Matrix.Rotation(math.radians(-4.0), 3, "X")
    parts.append(box(
        "Relay_SlopedRoof",
        (0.0, 0.020, 2.260),
        (1.420, 1.220, 0.160),
        "Postal_Green",
        bevel=0.020,
        edge_material="Postal_Green_Edge",
        rotation=roof_rot,
    ))

    # Heavy welded kick plinth / skirt base (no legs)
    parts.append(box(
        "Relay_BasePlinth",
        (0.0, 0.0, 0.350),
        (1.390, 1.180, 0.700),
        "Dark_Steel",
        bevel=0.022,
        edge_material="Steel_Edge",
    ))

    # Recessed door seam on front
    parts.append(box(
        "Relay_DoorSeam",
        (0.0, -0.578, 1.450),
        (1.180, 0.015, 1.350),
        "Slot_Shadow",
    ))

    # Heavy front lock hasp and padlock
    parts.append(box(
        "Relay_LockHaspPlate",
        (0.0, -0.588, 1.650),
        (0.180, 0.045, 0.320),
        "Dark_Steel",
        bevel=0.012,
        edge_material="Steel_Edge",
    ))

    parts.append(box(
        "Relay_PadlockBody",
        (0.0, -0.612, 1.520),
        (0.120, 0.035, 0.160),
        "Chrome",
        bevel=0.010,
    ))

    # Side lifting / transit handles
    for sx in (-1, 1):
        x = sx * 0.680
        parts.append(beam(
            f"Relay_SideHandle_PostA_{sx}",
            (x, -0.150, 1.450),
            (x + sx * 0.110, -0.150, 1.450),
            width=0.045,
            material="Dark_Steel",
            bevel=0.008,
        ))
        parts.append(beam(
            f"Relay_SideHandle_PostB_{sx}",
            (x,  0.150, 1.450),
            (x + sx * 0.110,  0.150, 1.450),
            width=0.045,
            material="Dark_Steel",
            bevel=0.008,
        ))
        parts.append(beam(
            f"Relay_SideHandle_Grip_{sx}",
            (x + sx * 0.110, -0.150, 1.450),
            (x + sx * 0.110,  0.150, 1.450),
            width=0.055,
            material="Dark_Steel",
            bevel=0.010,
        ))

    return {"Mailbox_RelayGreen": parts}


# ---------------------------------------------------------------------------
# Mailbox Variant 5: NYC Cast-Iron Pillar Box (2.4 x 2.4 x 5.2 studs)
# ---------------------------------------------------------------------------

def build_mailbox_vintage():
    # Fluted cylindrical column with flared weighted base and decorative domed cap
    pillar_profile = [
        (0.000, 0.000),
        (0.600, 0.000),
        (0.620, 0.080),
        (0.560, 0.180),
        (0.530, 0.350),
        (0.480, 0.450),
        (0.470, 1.750),
        (0.510, 1.820),
        (0.510, 1.950),
        (0.470, 2.020),
        (0.440, 2.220),
        (0.350, 2.380),
        (0.200, 2.460),
        (0.080, 2.500),
        (0.080, 2.580),
        (0.000, 2.600),
    ]

    pillar_body = lathe(
        "Pillar_ColumnBody",
        pillar_profile,
        segments=28,
        material_names=["Postal_Green", "Postal_Green_Edge"],
        segment_materials=[0, 1, 0, 1, 0, 1, 0, 1, 1, 0, 0, 0, 1, 1, 1, 1],
    )

    parts = [pillar_body]

    # Brass horizontal mail flap facing front (-Y)
    parts.append(box(
        "Pillar_BrassMailSlot",
        (0.0, -0.475, 1.880),
        (0.460, 0.045, 0.110),
        "Brass_Accent",
        bevel=0.012,
    ))

    parts.append(box(
        "Pillar_MailSlotAperture",
        (0.0, -0.480, 1.880),
        (0.380, 0.020, 0.050),
        "Slot_Shadow",
    ))

    # Brass collection schedule plate
    parts.append(box(
        "Pillar_BrassPlateFrame",
        (0.0, -0.472, 1.300),
        (0.320, 0.035, 0.440),
        "Brass_Accent",
        bevel=0.010,
    ))

    parts.append(box(
        "Pillar_PlateEnamel",
        (0.0, -0.482, 1.300),
        (0.260, 0.015, 0.380),
        "Label_Enamel",
    ))

    return {"Mailbox_VintagePillar": parts}


# ---------------------------------------------------------------------------
# Transform baking, dimensions, and true assembly volume centroid
# ---------------------------------------------------------------------------

def flatten_groups(groups):
    return [obj for members in groups.values() for obj in members]


def bake_world_transforms(objects):
    bpy.context.view_layer.update()

    for obj in objects:
        obj.data.transform(obj.matrix_world.copy())
        obj.matrix_world = Matrix.Identity(4)
        obj.data.update()


def bounds_of(objects):
    minimum = Vector((math.inf, math.inf, math.inf))
    maximum = Vector((-math.inf, -math.inf, -math.inf))

    for obj in objects:
        for vertex in obj.data.vertices:
            co = obj.matrix_world @ vertex.co
            for axis in range(3):
                minimum[axis] = min(minimum[axis], co[axis])
                maximum[axis] = max(maximum[axis], co[axis])

    if not all(math.isfinite(value) for value in (*minimum, *maximum)):
        raise RuntimeError("Cannot measure an empty or invalid mesh assembly.")

    return minimum, maximum


def enforce_dimensions(objects, target_dimensions):
    if target_dimensions is None:
        return

    minimum, maximum = bounds_of(objects)
    current = maximum - minimum
    midpoint = (minimum + maximum) * 0.5

    if min(current) <= 1.0e-8:
        raise RuntimeError("Degenerate assembly dimensions.")

    scale = Vector(tuple(
        target_dimensions[axis] / current[axis] for axis in range(3)
    ))

    for obj in objects:
        for vertex in obj.data.vertices:
            relative = vertex.co - midpoint
            vertex.co = Vector(tuple(
                relative[axis] * scale[axis] for axis in range(3)
            ))
        obj.data.update()


def mesh_volume_centroid(mesh):
    if not mesh.vertices:
        raise RuntimeError("Mass proxy contains no vertices.")

    reference = Vector((0.0, 0.0, 0.0))
    for vertex in mesh.vertices:
        reference += vertex.co
    reference /= len(mesh.vertices)

    mesh.calc_loop_triangles()

    volume = 0.0
    first_moment = Vector((0.0, 0.0, 0.0))

    for triangle in mesh.loop_triangles:
        a, b, c = (
            mesh.vertices[index].co - reference
            for index in triangle.vertices
        )
        signed_volume = a.dot(b.cross(c)) / 6.0
        volume += signed_volume
        first_moment += ((a + b + c) * 0.25) * signed_volume

    if not math.isfinite(volume) or volume <= 1.0e-9:
        raise RuntimeError("Mass proxy has invalid volume.")

    centroid = reference + first_moment / volume
    return volume, centroid


def exact_assembly_center_of_mass(objects):
    if len(objects) == 1:
        return mesh_volume_centroid(objects[0].data)

    operand_collection = bpy.data.collections.new("__COM_Operands")
    bpy.context.scene.collection.children.link(operand_collection)

    temporary_objects = []
    proxy = None
    proxy_mesh = None
    evaluated_proxy = None

    try:
        proxy = objects[0].copy()
        proxy.data = objects[0].data.copy()
        proxy.name = "__COM_UnionProxy"
        proxy_mesh = proxy.data
        bpy.context.scene.collection.objects.link(proxy)

        for original in objects[1:]:
            duplicate = original.copy()
            duplicate.data = original.data
            duplicate.name = "__COM_Operand"
            operand_collection.objects.link(duplicate)
            temporary_objects.append(duplicate)

        modifier = proxy.modifiers.new("__COM_ExactUnion", "BOOLEAN")
        modifier.operation = "UNION"
        modifier.solver = "EXACT"
        modifier.operand_type = "COLLECTION"
        modifier.collection = operand_collection

        if hasattr(modifier, "use_self"):
            modifier.use_self = True
        if hasattr(modifier, "use_hole_tolerant"):
            modifier.use_hole_tolerant = True

        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()
        depsgraph.update()

        evaluated_proxy = proxy.evaluated_get(depsgraph)
        evaluated_mesh = evaluated_proxy.to_mesh(
            preserve_all_data_layers=False,
            depsgraph=depsgraph,
        )

        volume, centroid = mesh_volume_centroid(evaluated_mesh)
        return volume, centroid

    finally:
        if evaluated_proxy is not None:
            evaluated_proxy.to_mesh_clear()

        if proxy is not None:
            bpy.data.objects.remove(proxy, do_unlink=True)

        for obj in temporary_objects:
            bpy.data.objects.remove(obj, do_unlink=True)

        bpy.data.collections.remove(operand_collection)

        if proxy_mesh is not None and proxy_mesh.users == 0:
            bpy.data.meshes.remove(proxy_mesh)


def center_to_origin_studs(objects, center_studs):
    for obj in objects:
        for vertex in obj.data.vertices:
            vertex.co = vertex.co - center_studs

        obj.matrix_world = Matrix.Identity(4)
        obj.data.update()

    bpy.context.scene.cursor.location = (0.0, 0.0, 0.0)


def consolidate_groups(groups):
    result = []

    for final_name, members in groups.items():
        activate_only(members)

        if len(members) > 1:
            bpy.ops.object.join()

        obj = bpy.context.view_layer.objects.active
        obj.name = final_name
        obj.data.name = final_name + "_TriMesh"
        obj.matrix_world = Matrix.Identity(4)
        result.append(obj)

    return result


def triangulate_and_validate(objects, asset_name):
    total = 0

    for obj in objects:
        bm = bmesh.new()
        try:
            bm.from_mesh(obj.data)
            bmesh.ops.triangulate(
                bm,
                faces=list(bm.faces),
                quad_method="BEAUTY",
                ngon_method="EAR_CLIP",
            )
            bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=bm.edges)
            bm.to_mesh(obj.data)
        finally:
            bm.free()

        obj.data.update()

        for polygon in obj.data.polygons:
            polygon.use_smooth = False

        triangle_count = len(obj.data.polygons)
        obj["triangle_count"] = triangle_count
        total += triangle_count

        if obj.location.length > 1.0e-8:
            raise RuntimeError("Object location is not zero: " + obj.name)

    if not MIN_TRIANGLES <= total <= MAX_TRIANGLES:
        raise RuntimeError(
            f"{asset_name}: {total} triangles; required "
            f"{MIN_TRIANGLES}–{MAX_TRIANGLES}. Export aborted."
        )

    return total


# ---------------------------------------------------------------------------
# FBX export
# ---------------------------------------------------------------------------

def ensure_fbx_exporter():
    if hasattr(bpy.ops.export_scene, "fbx"):
        return

    try:
        bpy.ops.preferences.addon_enable(module="io_scene_fbx")
    except Exception as exc:
        raise RuntimeError(
            "Blender's FBX exporter is unavailable."
        ) from exc


def export_fbx(objects, filepath):
    activate_only(objects)
    bpy.context.view_layer.update()

    result = bpy.ops.export_scene.fbx(
        filepath=filepath,
        check_existing=False,
        use_selection=True,
        object_types={"MESH"},
        global_scale=1.0,
        apply_unit_scale=False,
        apply_scale_options="FBX_SCALE_NONE",
        use_space_transform=True,
        bake_space_transform=True,
        axis_forward="-Z",
        axis_up="Y",
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
# Driver & Asset Specs (Proper Roblox Stud Scale)
# ---------------------------------------------------------------------------

ASSET_SPECS = [
    # Core Throwable Props
    {
        "name": "manhole_cover",
        "builder": build_manhole,
        "target_dimensions": (3.600, 3.600, 0.350),
    },
    {
        "name": "trash_can",
        "builder": build_trash_can,
        "target_dimensions": (2.800, 2.800, 4.200),
    },
    {
        "name": "wooden_crate",
        "builder": build_crate,
        "target_dimensions": (4.800, 4.800, 4.800),
    },
    {
        "name": "construction_barrel",
        "builder": build_barrel,
        "target_dimensions": (2.600, 2.600, 4.800),
    },
    # Mailbox Variants
    {
        "name": "mailbox_classic_usps",
        "builder": build_mailbox_classic,
        "target_dimensions": (2.600, 2.400, 5.000),
    },
    {
        "name": "mailbox_double_chute",
        "builder": build_mailbox_double,
        "target_dimensions": (4.600, 2.400, 5.000),
    },
    {
        "name": "mailbox_combat_dented",
        "builder": build_mailbox_damaged,
        "target_dimensions": (2.600, 2.500, 4.800),
    },
    {
        "name": "mailbox_relay_green",
        "builder": build_mailbox_relay,
        "target_dimensions": (2.800, 2.500, 4.500),
    },
    {
        "name": "mailbox_vintage_pillar",
        "builder": build_mailbox_vintage,
        "target_dimensions": (2.400, 2.400, 5.200),
    },
]


def vector_list(vector, digits=4):
    return [round(float(value), digits) for value in vector]


def generate_asset(spec, output_dir):
    clear_scene()
    configure_scene()

    groups = spec["builder"]()
    parts = flatten_groups(groups)

    if not parts:
        raise RuntimeError("Builder returned no geometry: " + spec["name"])

    bake_world_transforms(parts)
    enforce_dimensions(parts, spec["target_dimensions"])

    minimum_studs, maximum_studs = bounds_of(parts)
    dimensions_studs = maximum_studs - minimum_studs

    print(f"\n[{spec['name']}] Computing center of mass...")
    volume_studs3, center_studs = exact_assembly_center_of_mass(parts)

    center_to_origin_studs(parts, center_studs)
    export_objects = consolidate_groups(groups)

    triangle_count = triangulate_and_validate(
        export_objects, spec["name"]
    )

    filepath = os.path.join(output_dir, spec["name"] + ".fbx")
    export_fbx(export_objects, filepath)

    print(
        f"[{spec['name']}] {triangle_count} triangles | "
        f"{len(export_objects)} mesh(es) | "
        f"{vector_list(dimensions_studs)} studs"
    )
    print(f"  Exported: {filepath}")

    return {
        "asset": spec["name"],
        "file": os.path.basename(filepath),
        "mesh_objects": [obj.name for obj in export_objects],
        "triangles": triangle_count,
        "dimensions_studs_xyz": vector_list(dimensions_studs),
        "pivot": [0.0, 0.0, 0.0],
    }


def main():
    args = parse_arguments()
    output_dir = os.path.abspath(os.path.expanduser(args.output_dir))
    os.makedirs(output_dir, exist_ok=True)

    clear_scene()
    configure_scene()
    ensure_fbx_exporter()
    create_materials()

    reports = []
    for spec in ASSET_SPECS:
        reports.append(generate_asset(spec, output_dir))

    report = {
        "generator": "generate_throwable_props.py",
        "blender_version": bpy.app.version_string,
        "units": "Roblox Studs (1 unit = 1 stud)",
        "scale_notes": "Heroic character scale proportioned to Roblox R15/R6 characters (5 studs tall)",
        "assets": reports,
    }

    report_path = os.path.join(output_dir, "export_report.json")
    with open(report_path, "w", encoding="utf-8") as handle:
        json.dump(report, handle, indent=2)

    print(f"\nExported {len(reports)} props successfully at 1:1 Roblox Stud scale.")
    print(f"Report: {report_path}")


if __name__ == "__main__":
    main()
