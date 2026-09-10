#!/usr/bin/env python3
"""
generate_rooftop_props.py

Headless Blender script that procedurally models 5 stylized low-poly NYC
rooftop & street props for a Spider-Man traversal/combat game in Roblox.

Usage:
    blender --background --python generate_rooftop_props.py -- --output-dir ./rooftop_props

Outputs:
    rooftop_water_tower.fbx
    hvac_air_conditioner.fbx
    fire_escape_balcony.fbx
    nyc_fire_hydrant.fbx
    industrial_dumpster.fbx
    export_report.json

Scale: 1 unit in Blender = 1 Roblox Stud. Exported with 1:1 scale for Roblox Studio.
"""

import argparse
import bmesh
import bpy
import json
import math
import os
import sys
from mathutils import Matrix, Vector

# ---------------------------------------------------------------------------
# Constants (1:1 Roblox Studs - No 0.28 shrinkage!)
# ---------------------------------------------------------------------------
STUD_TO_M = 1.0
MIN_TRIS = 400
MAX_TRIS = 2000

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
def parse_args():
    argv = sys.argv
    argv = argv[argv.index("--") + 1:] if "--" in argv else []
    p = argparse.ArgumentParser(description="Generate NYC rooftop props.")
    p.add_argument("--output-dir", default="./rooftop_props")
    return p.parse_args(argv)

# ---------------------------------------------------------------------------
# Scene helpers
# ---------------------------------------------------------------------------
def clear_scene():
    bpy.ops.object.select_all(action="DESELECT")
    for obj in list(bpy.data.objects):
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in list(bpy.data.meshes):
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)

# ---------------------------------------------------------------------------
# Material creation
# ---------------------------------------------------------------------------
def make_mat(name, color, metallic=0.0, roughness=0.5):
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    bsdf = nt.nodes.new("ShaderNodeBsdfPrincipled")
    bsdf.inputs["Base Color"].default_value = (*color, 1.0)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(bsdf.outputs["BSDF"], out.inputs["Surface"])
    mat.diffuse_color = (*color, 1.0)
    return mat

# ---------------------------------------------------------------------------
# BMesh geometry helpers
# ---------------------------------------------------------------------------
def bm_box(bm, cx, cy, cz, sx, sy, sz, mi):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    vs = geom["verts"]
    for v in vs:
        v.co.x = v.co.x * sx + cx
        v.co.y = v.co.y * sy + cy
        v.co.z = v.co.z * sz + cz
    vset = set(vs)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mi

def bm_cyl(bm, cx, cy, cz, r, depth, seg, mi, cap=True, r2=None):
    if r2 is None:
        r2 = r
    mat = Matrix.Translation((cx, cy, cz))
    geom = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False,
        segments=seg, radius1=r, radius2=r2, depth=depth, matrix=mat
    )
    vset = set(geom["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mi

def bm_box_rot(bm, cx, cy, cz, sx, sy, sz, mi, rot_euler):
    geom = bmesh.ops.create_cube(bm, size=1.0)
    vs = geom["verts"]
    rot = Matrix.Rotation(rot_euler[2], 4, "Z") @ \
          Matrix.Rotation(rot_euler[1], 4, "Y") @ \
          Matrix.Rotation(rot_euler[0], 4, "X")
    trans = Matrix.Translation((cx, cy, cz))
    scale = Matrix.Diagonal((sx, sy, sz, 1.0))
    m = trans @ rot @ scale
    for v in vs:
        v.co = m @ v.co
    vset = set(vs)
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mi

def bm_cyl_rot(bm, cx, cy, cz, r, depth, seg, mi, rot_euler, cap=True, r2=None):
    if r2 is None:
        r2 = r
    rot = Matrix.Rotation(rot_euler[2], 4, "Z") @ \
          Matrix.Rotation(rot_euler[1], 4, "Y") @ \
          Matrix.Rotation(rot_euler[0], 4, "X")
    trans = Matrix.Translation((cx, cy, cz))
    m = trans @ rot
    geom = bmesh.ops.create_cone(
        bm, cap_ends=cap, cap_tris=False,
        segments=seg, radius1=r, radius2=r2, depth=depth, matrix=m
    )
    vset = set(geom["verts"])
    for f in bm.faces:
        if all(v in vset for v in f.verts):
            f.material_index = mi

# ---------------------------------------------------------------------------
# Prop 1: Rooftop Water Tower (Proportioned for rooftop skyline: ~15 studs tall)
# ---------------------------------------------------------------------------
def build_water_tower():
    mats = [
        make_mat("WT_Wood", (0.42, 0.26, 0.12), 0.0, 0.82),
        make_mat("WT_Wood_Dark", (0.30, 0.18, 0.08), 0.0, 0.85),
        make_mat("WT_Iron_Hoop", (0.12, 0.12, 0.14), 0.85, 0.45),
        make_mat("WT_Roof", (0.22, 0.14, 0.08), 0.0, 0.78),
        make_mat("WT_Steel", (0.18, 0.19, 0.21), 0.80, 0.50),
        make_mat("WT_Finial", (0.75, 0.55, 0.20), 0.90, 0.30),
    ]
    M_WOOD = 0
    M_WOOD_D = 1
    M_HOOP = 2
    M_ROOF = 3
    M_STEEL = 4
    M_FIN = 5

    bm = bmesh.new()

    # Scale factor for heroic rooftop presence (2.2x base coordinates)
    S = 2.2

    barrel_r = 1.2 * S
    barrel_h = 2.8 * S
    leg_h = 3.2 * S
    barrel_cz = leg_h + barrel_h / 2

    # --- Barrel body (20-sided cylinder) ---
    bm_cyl(bm, 0, 0, barrel_cz, barrel_r, barrel_h, 20, M_WOOD)

    # --- Vertical planks (8 thin boxes on barrel surface) ---
    for i in range(8):
        ang = 2.0 * math.pi * i / 8.0
        px = (barrel_r + 0.04) * math.cos(ang)
        py = (barrel_r + 0.04) * math.sin(ang)
        bm_box_rot(bm, px, py, barrel_cz, 0.20, 0.12, barrel_h, M_WOOD_D, (0, 0, ang))

    # --- Metal tension hoops (5 rings) ---
    for i in range(5):
        hz = leg_h + 0.6 + i * (barrel_h - 1.2) / 4.0
        bm_cyl(bm, 0, 0, hz, barrel_r + 0.08, 0.16, 20, M_HOOP)

    # --- Conical roof (20-sided) ---
    roof_r = barrel_r + 0.30
    roof_h = 1.0 * S
    roof_cz = leg_h + barrel_h + roof_h / 2
    bm_cyl(bm, 0, 0, roof_cz, roof_r, roof_h, 20, M_ROOF, r2=0.10)

    # --- Finial (small 8-sided cylinder + cone tip) ---
    fin_cz = roof_cz + roof_h / 2 + 0.30
    bm_cyl(bm, 0, 0, fin_cz, 0.25, 0.60, 8, M_FIN)
    bm_cyl(bm, 0, 0, fin_cz + 0.50, 0.20, 0.40, 8, M_FIN, r2=0.0)

    # --- 4-legged angled steel truss ---
    leg_top_r = 1.0 * S
    leg_bot_r = 1.45 * S
    for i in range(4):
        ang = 2.0 * math.pi * i / 4.0 + math.pi / 4.0
        tx = leg_top_r * math.cos(ang)
        ty = leg_top_r * math.sin(ang)
        bx = leg_bot_r * math.cos(ang)
        by = leg_bot_r * math.sin(ang)
        mid_x = (tx + bx) / 2.0
        mid_y = (ty + by) / 2.0
        mid_z = leg_h / 2.0
        dx = bx - tx
        dy = by - ty
        dz = leg_h
        length = math.sqrt(dx*dx + dy*dy + dz*dz)
        tilt = math.atan2(math.sqrt(dx*dx + dy*dy), dz)
        yaw = math.atan2(dy, dx)
        bm_box_rot(bm, mid_x, mid_y, mid_z, 0.25, 0.25, length, M_STEEL, (tilt, 0, yaw))

    # --- Horizontal cross-bracing (4 bars at mid-height) ---
    cross_h = leg_h * 0.5
    cross_r = leg_top_r + (leg_bot_r - leg_top_r) * 0.5
    for i in range(4):
        ang = 2.0 * math.pi * i / 4.0
        nx = cross_r * math.cos(ang)
        ny = cross_r * math.sin(ang)
        ang2 = ang + math.pi / 2.0
        ex = cross_r * math.cos(ang2)
        ey = cross_r * math.sin(ang2)
        bm_box_rot(bm, (nx+ex)/2, (ny+ey)/2, cross_h,
                   math.sqrt((ex-nx)**2 + (ey-ny)**2) + 0.2, 0.16, 0.16, M_STEEL,
                   (0, 0, math.atan2(ey-ny, ex-nx)))

    # --- Diagonal braces (8) ---
    for i in range(4):
        ang1 = 2.0 * math.pi * i / 4.0 + math.pi / 4.0
        ang2 = 2.0 * math.pi * (i + 1) / 4.0 + math.pi / 4.0
        r1 = leg_top_r + (leg_bot_r - leg_top_r) * 0.25
        r2 = leg_top_r + (leg_bot_r - leg_top_r) * 0.75
        x1 = r1 * math.cos(ang1)
        y1 = r1 * math.sin(ang1)
        x2 = r2 * math.cos(ang2)
        y2 = r2 * math.sin(ang2)
        z1 = leg_h * 0.25
        z2 = leg_h * 0.75
        mid = ((x1+x2)/2, (y1+y2)/2, (z1+z2)/2)
        dx, dy, dz = x2-x1, y2-y1, z2-z1
        length = math.sqrt(dx*dx + dy*dy + dz*dz)
        tilt = math.atan2(math.sqrt(dx*dx + dy*dy), dz)
        yaw = math.atan2(dy, dx)
        bm_box_rot(bm, mid[0], mid[1], mid[2], 0.14, 0.14, length, M_STEEL, (tilt, 0, yaw))

    # --- Base platform ---
    bm_cyl(bm, 0, 0, 0.12, leg_bot_r + 0.4, 0.24, 20, M_STEEL)

    # --- Side ladder ---
    lad_x = leg_bot_r + 0.50
    for side in (-1, 1):
        bm_box(bm, lad_x, side * 0.50, leg_h / 2, 0.12, 0.12, leg_h, M_STEEL)
    for i in range(8):
        rz = 0.6 + i * (leg_h - 1.2) / 7.0
        bm_box(bm, lad_x, 0, rz, 0.12, 1.00, 0.12, M_STEEL)

    # --- Top rim ring ---
    rim_cz = leg_h + barrel_h
    bm_cyl(bm, 0, 0, rim_cz, barrel_r + 0.10, 0.20, 20, M_HOOP)

    return bm, mats

# ---------------------------------------------------------------------------
# Prop 2: HVAC Air Conditioner (Heroic scale: ~5.0 x 4.0 x 3.6 studs)
# ---------------------------------------------------------------------------
def build_hvac():
    mats = [
        make_mat("HVAC_SheetMetal", (0.55, 0.58, 0.60), 0.70, 0.45),
        make_mat("HVAC_Louver", (0.38, 0.40, 0.42), 0.60, 0.55),
        make_mat("HVAC_FanGrill", (0.20, 0.22, 0.24), 0.80, 0.40),
        make_mat("HVAC_Pipe", (0.65, 0.45, 0.20), 0.85, 0.35),
        make_mat("HVAC_Base", (0.25, 0.26, 0.28), 0.75, 0.50),
        make_mat("HVAC_Panel", (0.48, 0.50, 0.52), 0.65, 0.50),
    ]
    M_METAL = 0
    M_LOUVER = 1
    M_GRILL = 2
    M_PIPE = 3
    M_BASE = 4
    M_PANEL = 5

    bm = bmesh.new()

    hw, hd, hh = 4.8, 3.8, 3.0
    bm_box(bm, 0, 0, hh/2 + 0.4, hw, hd, hh, M_METAL)
    bm_box(bm, 0, 0, hh + 0.4 + 0.08, hw - 0.2, hd - 0.2, 0.16, M_PANEL)

    # Front intake ventilation louvers
    louver_x = hw / 2 + 0.02
    for i in range(14):
        lz = 0.8 + i * 0.16
        bm_box(bm, louver_x, 0, lz, 0.08, hd * 0.75, 0.08, M_LOUVER)

    # Side louvers
    for i in range(10):
        ly = -hd/2 * 0.6 + i * (hd * 0.6) / 9.0
        bm_box(bm, -hw/2 - 0.02, ly, 1.5, 0.08, 0.08, hh * 0.5, M_LOUVER)

    # Circular top recessed exhaust fan housing
    fan_cz = hh + 0.4 + 0.30
    bm_cyl(bm, 0.6, 0, fan_cz, 1.0, 0.50, 16, M_METAL)

    # Fan blades
    for i in range(6):
        ang = 2.0 * math.pi * i / 6.0
        fx = 0.6 + 0.45 * math.cos(ang)
        fy = 0.45 * math.sin(ang)
        bm_box_rot(bm, fx, fy, fan_cz + 0.10, 0.45, 0.08, 0.06, M_GRILL, (0.3, 0, ang))

    # Protective safety grill
    for i in range(16):
        ang = 2.0 * math.pi * i / 16.0
        gx = 0.6 + 0.65 * math.cos(ang)
        gy = 0.65 * math.sin(ang)
        bm_box_rot(bm, gx, gy, fan_cz + 0.35, 0.40, 0.06, 0.06, M_GRILL, (0, 0, ang))

    # Grill ring
    bm_cyl(bm, 0.6, 0, fan_cz + 0.35, 1.0, 0.08, 16, M_GRILL)

    # External compressor pipe
    bm_cyl(bm, -hw/2 - 0.30, 0.6, 1.5, 0.16, 2.0, 8, M_PIPE)
    bm_cyl_rot(bm, -hw/2 - 0.70, 0.6, 0.5, 0.16, 0.8, 8, M_PIPE, (0, math.pi/2, 0))
    bm_box(bm, -hw/2 - 0.30, 0.6, 2.5, 0.28, 0.28, 0.20, M_PIPE)
    bm_cyl(bm, hw/2 + 0.25, -0.8, 1.1, 0.12, 1.4, 8, M_PIPE)

    # Base frame
    for sx in (-1, 1):
        for sy in (-1, 1):
            bm_box(bm, sx * (hw/2 - 0.2), sy * (hd/2 - 0.2), 0.2, 0.25, 0.25, 0.4, M_BASE)
    bm_box(bm, 0, hd/2 - 0.2, 0.2, hw - 0.4, 0.16, 0.16, M_BASE)
    bm_box(bm, 0, -hd/2 + 0.2, 0.2, hw - 0.4, 0.16, 0.16, M_BASE)

    # Side access panels
    bm_box(bm, 0, hd/2 + 0.02, 1.5, hw * 0.45, 0.06, hh * 0.55, M_PANEL)
    bm_box(bm, 1.2, hd/2 + 0.04, 2.2, 0.65, 0.08, 0.45, M_PANEL)

    return bm, mats

# ---------------------------------------------------------------------------
# Prop 3: Fire Escape Balcony (Heroic scale: ~6.0 x 3.6 x 3.5 studs)
# ---------------------------------------------------------------------------
def build_fire_escape():
    mats = [
        make_mat("FE_Iron", (0.10, 0.10, 0.12), 0.80, 0.55),
        make_mat("FE_Iron_Dark", (0.06, 0.06, 0.08), 0.75, 0.60),
        make_mat("FE_Grill", (0.14, 0.14, 0.16), 0.70, 0.50),
        make_mat("FE_Bracket", (0.08, 0.08, 0.10), 0.85, 0.45),
    ]
    M_IRON = 0
    M_IRON_D = 1
    M_GRILL = 2
    M_BRACKET = 3

    bm = bmesh.new()

    pw, pd, ph = 5.8, 3.4, 0.16
    plat_cz = 0.0

    # Platform floor
    bm_box(bm, 0, pd/2, plat_cz, pw, pd, ph, M_IRON)

    # Grate slats (raised diamond grid)
    grate_rows = 4
    grate_cols = 6
    for r in range(grate_rows):
        for c in range(grate_cols):
            gx = -pw/2 + 0.6 + c * (pw - 1.2) / (grate_cols - 1)
            gy = 0.4 + r * (pd - 0.8) / (grate_rows - 1)
            bm_box_rot(bm, gx, gy, plat_cz + ph/2 + 0.02, 0.45, 0.12, 0.04, M_GRILL, (0, 0, math.pi/4))
            bm_box_rot(bm, gx, gy, plat_cz + ph/2 + 0.02, 0.45, 0.12, 0.04, M_GRILL, (0, 0, -math.pi/4))

    # Handrails (3-sided)
    rail_h = 2.4
    rail_t = 0.10
    rail_y_front = pd + 0.08

    # Front rail
    bm_box(bm, 0, rail_y_front, rail_h, pw + 0.2, rail_t, rail_t, M_IRON)
    bm_box(bm, 0, rail_y_front, rail_h * 0.5, pw + 0.2, rail_t, rail_t, M_IRON)
    bm_box(bm, 0, rail_y_front, 0.10, pw + 0.2, rail_t, rail_t, M_IRON)
    for i in range(12):
        px = -pw/2 + 0.25 + i * (pw - 0.5) / 11.0
        bm_box(bm, px, rail_y_front, rail_h/2, rail_t, rail_t, rail_h, M_IRON)

    # Left rail
    bm_box(bm, -pw/2 - rail_t/2, pd/2, rail_h, rail_t, pd + 0.2, rail_t, M_IRON)
    bm_box(bm, -pw/2 - rail_t/2, pd/2, rail_h * 0.5, rail_t, pd + 0.2, rail_t, M_IRON)
    bm_box(bm, -pw/2 - rail_t/2, pd/2, 0.10, rail_t, pd + 0.2, rail_t, M_IRON)
    for i in range(8):
        py = 0.2 + i * (pd - 0.4) / 7.0
        bm_box(bm, -pw/2 - rail_t/2, py, rail_h/2, rail_t, rail_t, rail_h, M_IRON)

    # Right rail
    bm_box(bm, pw/2 + rail_t/2, pd/2, rail_h, rail_t, pd + 0.2, rail_t, M_IRON)
    bm_box(bm, pw/2 + rail_t/2, pd/2, rail_h * 0.5, rail_t, pd + 0.2, rail_t, M_IRON)
    bm_box(bm, pw/2 + rail_t/2, pd/2, 0.10, rail_t, pd + 0.2, rail_t, M_IRON)
    for i in range(8):
        py = 0.2 + i * (pd - 0.4) / 7.0
        bm_box(bm, pw/2 + rail_t/2, py, rail_h/2, rail_t, rail_t, rail_h, M_IRON)

    # Corner posts
    for sx in (-1, 1):
        bm_box(bm, sx * (pw/2 + rail_t/2), rail_y_front, rail_h/2, rail_t*2, rail_t*2, rail_h, M_IRON)

    # Wall mounting brackets
    for i in range(4):
        bx = -pw/2 + 0.7 + i * (pw - 1.4) / 3.0
        bm_box(bm, bx, 0.04, 0.8, 0.12, 0.08, 1.6, M_BRACKET)
        bm_box(bm, bx, 0.4, 0.10, 0.12, 0.8, 0.12, M_BRACKET)
        bm_box_rot(bm, bx, 0.30, 0.70, 0.10, 0.10, 1.10, M_BRACKET, (math.pi/5, 0, 0))

    # Drop ladder rails
    for sx in (-1, 1):
        lx = sx * (pw/2 - 0.8)
        bm_box(bm, lx, rail_y_front + 0.10, -1.5, 0.12, 0.12, 3.2, M_IRON_D)
    for i in range(7):
        rz = -0.5 - i * 0.45
        bm_box(bm, 0, rail_y_front + 0.10, rz, pw - 1.6, 0.10, 0.10, M_IRON_D)

    return bm, mats

# ---------------------------------------------------------------------------
# Prop 4: NYC Fire Hydrant (~1.5 x 1.5 x 2.4 studs)
# ---------------------------------------------------------------------------
def build_fire_hydrant():
    mats = [
        make_mat("FH_Red", (0.85, 0.08, 0.05), 0.10, 0.40),
        make_mat("FH_Silver", (0.75, 0.78, 0.80), 0.90, 0.25),
        make_mat("FH_Dark", (0.15, 0.15, 0.17), 0.70, 0.50),
        make_mat("FH_Chain", (0.25, 0.25, 0.28), 0.85, 0.35),
        make_mat("FH_Cap", (0.80, 0.10, 0.08), 0.15, 0.35),
    ]
    M_RED = 0
    M_SILVER = 1
    M_DARK = 2
    M_CHAIN = 3
    M_CAP = 4

    bm = bmesh.new()

    # Base flange
    bm_cyl(bm, 0, 0, 0.10, 0.56, 0.20, 12, M_DARK)

    # Main body
    bm_cyl(bm, 0, 0, 0.85, 0.38, 1.35, 12, M_RED)

    # Upper shoulder
    bm_cyl(bm, 0, 0, 1.65, 0.44, 0.38, 12, M_RED)

    # Top dome
    bm_cyl(bm, 0, 0, 1.95, 0.40, 0.30, 12, M_RED, r2=0.18)

    # Hexagonal bonnet nut
    bm_cyl(bm, 0, 0, 2.18, 0.22, 0.18, 6, M_SILVER)
    bm_cyl(bm, 0, 0, 2.30, 0.14, 0.10, 6, M_SILVER)

    # 2 Side hose nozzles
    for sx in (-1, 1):
        bm_cyl_rot(bm, sx * 0.52, 0, 1.05, 0.18, 0.25, 12, M_CAP, (0, math.pi/2, 0))
        bm_cyl_rot(bm, sx * 0.67, 0, 1.05, 0.15, 0.05, 12, M_SILVER, (0, math.pi/2, 0))
        for ci in range(3):
            cz = 0.92 - ci * 0.15
            bm_box(bm, sx * 0.52, 0.10 + ci * 0.05, cz, 0.04, 0.04, 0.12, M_CHAIN)

    # Front steamer nozzle
    bm_cyl_rot(bm, 0, 0.50, 0.95, 0.15, 0.30, 10, M_RED, (math.pi/2, 0, 0))
    bm_cyl_rot(bm, 0, 0.68, 0.95, 0.20, 0.12, 10, M_SILVER, (math.pi/2, 0, 0))
    bm_cyl_rot(bm, 0, 0.77, 0.95, 0.18, 0.06, 10, M_CAP, (math.pi/2, 0, 0))

    # Rear outlet
    bm_cyl_rot(bm, 0, -0.48, 0.95, 0.13, 0.22, 10, M_RED, (math.pi/2, 0, 0))
    bm_cyl_rot(bm, 0, -0.60, 0.95, 0.11, 0.05, 10, M_SILVER, (math.pi/2, 0, 0))

    # Base bolts (6)
    for i in range(6):
        ang = 2.0 * math.pi * i / 6.0
        bx = 0.48 * math.cos(ang)
        by = 0.48 * math.sin(ang)
        bm_cyl(bm, bx, by, 0.20, 0.05, 0.10, 6, M_SILVER)

    # Mid-body band
    bm_cyl(bm, 0, 0, 0.68, 0.40, 0.08, 12, M_SILVER)

    return bm, mats

# ---------------------------------------------------------------------------
# Prop 5: Industrial Dumpster (Heroic scale: ~6.0 x 3.6 x 3.6 studs)
# ---------------------------------------------------------------------------
def build_dumpster():
    mats = [
        make_mat("DMP_Steel", (0.18, 0.22, 0.18), 0.60, 0.55),
        make_mat("DMP_Corrugated", (0.14, 0.18, 0.14), 0.55, 0.60),
        make_mat("DMP_Lid", (0.20, 0.25, 0.20), 0.60, 0.50),
        make_mat("DMP_Fork", (0.10, 0.12, 0.10), 0.70, 0.45),
        make_mat("DMP_Rubber", (0.05, 0.05, 0.06), 0.0, 0.90),
        make_mat("DMP_Hinge", (0.30, 0.30, 0.32), 0.80, 0.40),
    ]
    M_STEEL = 0
    M_CORR = 1
    M_LID = 2
    M_FORK = 3
    M_RUBBER = 4
    M_HINGE = 5

    bm = bmesh.new()

    dw, dd, dh = 5.8, 3.2, 3.2
    wall_t = 0.12
    base_h = 0.4
    taper = 0.30

    # Bin walls
    bm_box(bm, 0, dd/2, base_h + dh/2, dw, wall_t, dh, M_STEEL)
    bm_box(bm, 0, -dd/2, base_h + dh/2, dw, wall_t, dh, M_STEEL)
    bm_box(bm, -dw/2 + taper/2, 0, base_h + dh/2, wall_t, dd - taper, dh, M_STEEL)
    bm_box(bm, dw/2 - taper/2, 0, base_h + dh/2, wall_t, dd - taper, dh, M_STEEL)
    bm_box(bm, 0, 0, base_h, dw, dd, wall_t, M_STEEL)

    # Vertical corrugation channels
    for side in (-1, 1):
        for i in range(6):
            cx = -dw/2 + 0.6 + i * (dw - 1.2) / 5.0
            bm_box(bm, cx, dd/2 + 0.04, base_h + dh/2, 0.15, 0.08, dh - 0.4, M_CORR)
            bm_box(bm, cx, -dd/2 - 0.04, base_h + dh/2, 0.15, 0.08, dh - 0.4, M_CORR)

    # Horizontal reinforcement bands
    for i in range(3):
        bz = base_h + 0.6 + i * (dh - 1.2) / 2.0
        bm_box(bm, 0, dd/2 + 0.02, bz, dw + 0.08, 0.08, 0.16, M_CORR)
        bm_box(bm, 0, -dd/2 - 0.02, bz, dw + 0.08, 0.08, 0.16, M_CORR)

    # Fork-lift pockets
    for sx in (-1, 1):
        for i in range(2):
            fy = -dd/2 * 0.3 + i * dd * 0.3
            bm_box(bm, sx * (dw/2 + 0.04), fy, base_h + 0.6, 0.16, 0.6, 0.50, M_FORK)
            bm_box(bm, sx * (dw/2 + 0.12), fy, base_h + 0.36, 0.08, 0.7, 0.08, M_FORK)

    # Dual split lids
    lid1_w = dw / 2 - 0.10
    bm_box(bm, -dw/4, 0, base_h + dh + 0.08, lid1_w, dd + 0.2, 0.16, M_LID)
    bm_box(bm, -dw/4, 0, base_h + dh + 0.20, lid1_w - 0.2, 0.2, 0.08, M_LID)

    lid2_w = dw / 2 - 0.10
    lid2_cx = dw/4
    lid2_cy = -dd/2 + 0.10
    lid2_cz = base_h + dh + 0.08
    bm_box_rot(bm, lid2_cx, lid2_cy + 0.6, lid2_cz + 0.30,
               lid2_w, dd + 0.2, 0.16, M_LID, (math.radians(20), 0, 0))
    bm_box_rot(bm, lid2_cx, lid2_cy + 0.6, lid2_cz + 0.44,
               lid2_w - 0.2, 0.2, 0.08, M_LID, (math.radians(20), 0, 0))

    # Hinges
    for i in range(4):
        hx = -dw/2 + 0.6 + i * (dw - 1.2) / 3.0
        bm_box(bm, hx, -dd/2 - 0.04, base_h + dh, 0.24, 0.16, 0.24, M_HINGE)

    # Front latch
    bm_box(bm, 0, dd/2 + 0.08, base_h + dh - 0.4, 0.30, 0.16, 0.30, M_HINGE)

    # Caster wheels
    for sx in (-1, 1):
        for sy in (-1, 1):
            wx = sx * (dw/2 - 0.6)
            wy = sy * (dd/2 - 0.4)
            bm_cyl_rot(bm, wx, wy, 0.2, 0.20, 0.16, 8, M_RUBBER, (0, math.pi/2, 0))

    # Base rails
    bm_box(bm, 0, dd/2 - 0.3, base_h/2, dw - 0.8, 0.16, base_h, M_FORK)
    bm_box(bm, 0, -dd/2 + 0.3, base_h/2, dw - 0.8, 0.16, base_h, M_FORK)

    return bm, mats

# ---------------------------------------------------------------------------
# Mesh processing
# ---------------------------------------------------------------------------
def process_and_create(name, bm, materials):
    bmesh.ops.triangulate(bm, faces=list(bm.faces), quad_method="BEAUTY", ngon_method="EAR_CLIP")
    bmesh.ops.dissolve_degenerate(bm, dist=1e-5, edges=list(bm.edges))

    zero_faces = [f for f in bm.faces if f.calc_area() < 1e-8]
    if zero_faces:
        bmesh.ops.delete(bm, geom=zero_faces, context="FACES")

    tri_count = len(bm.faces)

    if tri_count < MIN_TRIS or tri_count > MAX_TRIS:
        raise RuntimeError(
            f"{name}: {tri_count} triangles outside budget [{MIN_TRIS}, {MAX_TRIS}]"
        )

    for v in bm.verts:
        v.co *= STUD_TO_M

    mesh = bpy.data.meshes.new(name + "_Mesh")
    bm.to_mesh(mesh)
    bm.free()

    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)

    for mat in materials:
        mesh.materials.append(mat)

    for poly in mesh.polygons:
        if poly.material_index >= len(materials):
            poly.material_index = 0
        poly.use_smooth = False

    obj.location = (0, 0, 0)
    obj.rotation_euler = (0, 0, 0)
    obj.scale = (1, 1, 1)
    obj.data.update()

    return obj, tri_count

# ---------------------------------------------------------------------------
# FBX Export (1:1 Roblox Stud scale)
# ---------------------------------------------------------------------------
def export_fbx(obj, filepath):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj

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
        add_leaf_bones=False,
        bake_anim=False,
        path_mode="AUTO",
        embed_textures=False,
    )
    if "FINISHED" not in result:
        raise RuntimeError(f"FBX export failed for {filepath}")

def compute_bounds_studs(bm):
    if not bm.verts:
        return (0, 0, 0), (0, 0, 0)
    coords = [v.co.copy() for v in bm.verts]
    mn = Vector((min(c.x for c in coords), min(c.y for c in coords), min(c.z for c in coords)))
    mx = Vector((max(c.x for c in coords), max(c.y for c in coords), max(c.z for c in coords)))
    return tuple(mn), tuple(mx)

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
def main():
    args = parse_args()
    out_dir = os.path.abspath(args.output_dir)
    os.makedirs(out_dir, exist_ok=True)

    try:
        bpy.ops.preferences.addon_enable(module="io_scene_fbx")
    except Exception:
        pass

    clear_scene()

    bpy.context.scene.unit_settings.system = "METRIC"
    bpy.context.scene.unit_settings.length_unit = "METERS"
    bpy.context.scene.unit_settings.scale_length = 1.0

    props = [
        ("rooftop_water_tower", build_water_tower),
        ("hvac_air_conditioner", build_hvac),
        ("fire_escape_balcony", build_fire_escape),
        ("nyc_fire_hydrant", build_fire_hydrant),
        ("industrial_dumpster", build_dumpster),
    ]

    report = {
        "script": "generate_rooftop_props.py",
        "blender_version": bpy.app.version_string,
        "units": "Roblox Studs (1 unit = 1 stud, player height = 5 studs)",
        "export_settings": {
            "axis_forward": "-Z",
            "axis_up": "Y",
            "mesh_smooth_type": "FACE",
        },
        "assets": [],
    }

    for name, builder in props:
        print(f"\n[Building] {name} ...")
        bm, mats = builder()

        bmin, bmax = compute_bounds_studs(bm)
        dims_studs = (round(bmax[0]-bmin[0], 3), round(bmax[1]-bmin[1], 3), round(bmax[2]-bmin[2], 3))

        obj, tri_count = process_and_create(name, bm, mats)

        fbx_path = os.path.join(out_dir, name + ".fbx")
        export_fbx(obj, fbx_path)
        print(f"  -> {fbx_path} ({tri_count} tris, {dims_studs} studs)")

        mat_slots = [
            {
                "slot_index": i,
                "name": m.name,
                "base_color": list(m.diffuse_color[:3]),
                "metallic": m.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value,
                "roughness": m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value,
            }
            for i, m in enumerate(obj.data.materials)
        ]

        report["assets"].append({
            "name": name,
            "file": name + ".fbx",
            "triangle_count": tri_count,
            "bounding_box_studs": {
                "min": [round(v, 3) for v in bmin],
                "max": [round(v, 3) for v in bmax],
                "dimensions": list(dims_studs),
            },
            "material_slots": mat_slots,
            "pivot": "bottom/ground contact at (0,0,0)",
        })

        mesh_data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if mesh_data.users == 0:
            bpy.data.meshes.remove(mesh_data)

    report_path = os.path.join(out_dir, "export_report.json")
    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, indent=2)
    print(f"\n[Report] {report_path}")
    print("[Done] All 5 rooftop props exported successfully at 1:1 Roblox Stud scale.")


if __name__ == "__main__":
    main()
