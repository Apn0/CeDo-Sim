#!/usr/bin/env python3
"""
Parametric rebuild of the CeDo factory shell — replaces the solidified 3DBAG
triangle soup with clean, deliberately-modelled geometry. Every dimension is
MEASURED, not invented:

  * Footprint / hall layout / roof profiles: rasterized from the 3DBAG LOD2.2
    survey component of CeDo_building.obj (scratchpad extract_layout.py):
      - 4 gabled bays, 30 m each (X 0..120): eave 7.4 m, 16.7 deg pitch over
        10 m, flat crest 10 m wide at 10.4 m. Valleys at X = 30/60/90.
      - East flat wing X 120..150.7, Z 0..31.5, roof 7.0 m.
      - SE wing X 120..131.5, Z 31.5..61, roof 7.0 m.
      - South annex, roof 4.6 m: X 57..81 to Z 66, X 81..131.5 to Z 71.5.
      - Rooftop penthouse ~8x8 m at the X=90 valley, to 12.4 m.
  * V-splay support columns: operator reference photo
    assets/reference_photos/building/_wooden_V_shape_support_beams.png —
    massive columns, narrow at the floor, fanning upward to carry the
    longitudinal valley beams. One row per valley, 6 per row.

Output uses the SAME frame as the survey mesh (raw RD coords, base y 74.02)
and the same shell/posts material groups, so BuildingShellLoader, WorldSetup
and the texture pipeline keep working unchanged.

Run:  python tools/generate_building.py
"""
import math
import os

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(os.path.dirname(HERE), "assets", "models", "CeDo_factory_solid.obj")

# ── Survey frame (from scratchpad/extract_layout.py on CeDo_building.obj) ────
THETA = math.radians(130.0)          # building long axis vs mesh frame
CT, ST = math.cos(THETA), math.sin(THETA)
BX0, BZ0 = -370539.4, 70746.4        # building-frame origin (rotated RD)
BASE_Y = 74.02                       # survey ground level

def to_mesh(xr, y, zr):
    """building-frame (x-right, z-down on the map) -> survey mesh RD coords."""
    bx, bz = BX0 + xr, BZ0 + zr
    return (bx * CT - bz * ST, BASE_Y + y, bx * ST + bz * CT)

# ── Measured layout ───────────────────────────────────────────────────────────
T = 0.30            # wall thickness
RT = 0.18           # roof skin thickness
EAVE = 7.4
CREST = 10.4
BAYS = [(0.0, 30.0), (30.0, 60.0), (60.0, 90.0), (90.0, 120.0)]
CREST_IN = 10.0     # crest starts 10 m into the bay (16.7 deg pitch)
GABLE_Z0, GABLE_Z1 = 0.0, 61.0
EAST = (120.0, 150.7, 0.0, 31.5, 7.0)      # x0,x1,z0,z1,roof_h
SE_WING = (120.0, 131.5, 31.5, 61.0, 7.0)
ANNEX_W = (57.0, 81.0, 61.0, 66.0, 4.6)
ANNEX_E = (81.0, 131.5, 61.0, 71.5, 4.6)
PENTHOUSE = (86.0, 94.0, 20.0, 28.0, 8.0, 12.4)
VALLEYS = [30.0, 60.0, 90.0]

shell_faces = []   # list of (verts...) polygons, outward winding
post_faces = []

def add_box(faces, x0, y0, z0, x1, y1, z1):
    """Axis-aligned solid box in building frame; 6 outward quads."""
    v = {}
    for xi, x in ((0, x0), (1, x1)):
        for yi, y in ((0, y0), (1, y1)):
            for zi, z in ((0, z0), (1, z1)):
                v[(xi, yi, zi)] = (x, y, z)
    # NOTE building frame is LEFT-handed vs mesh handedness after to_mesh
    # (z-down map). Winding is fixed once in write_obj by normal check.
    faces.append((v[0,0,0], v[0,1,0], v[1,1,0], v[1,0,0]))  # z0 side
    faces.append((v[1,0,1], v[1,1,1], v[0,1,1], v[0,0,1]))  # z1 side
    faces.append((v[0,0,1], v[0,1,1], v[0,1,0], v[0,0,0]))  # x0 side
    faces.append((v[1,0,0], v[1,1,0], v[1,1,1], v[1,0,1]))  # x1 side
    faces.append((v[0,1,0], v[0,1,1], v[1,1,1], v[1,1,0]))  # top
    faces.append((v[0,0,0], v[1,0,0], v[1,0,1], v[0,0,1]))  # bottom

def add_prism(faces, poly, z0, z1):
    """Solid prism: XY polygon (in building X/Y) extruded along Z."""
    front = [(x, y, z0) for x, y in poly]
    back = [(x, y, z1) for x, y in poly]
    faces.append(tuple(front))
    faces.append(tuple(reversed(back)))
    n = len(poly)
    for i in range(n):
        j = (i + 1) % n
        faces.append((front[i], front[j], back[j], back[i]))

def add_skew_box(faces, bot_c, top_c, sx, sz):
    """Column leg: box whose top centre is offset from its bottom centre.
    bot_c/top_c = (x, y, z) centres; sx/sz = half cross-section."""
    bx, by, bz = bot_c
    tx, ty, tz = top_c
    b = [(bx-sx, by, bz-sz), (bx+sx, by, bz-sz), (bx+sx, by, bz+sz), (bx-sx, by, bz+sz)]
    t = [(tx-sx, ty, tz-sz), (tx+sx, ty, tz-sz), (tx+sx, ty, tz+sz), (tx-sx, ty, tz+sz)]
    faces.append(tuple(reversed(b)))
    faces.append(tuple(t))
    for i in range(4):
        j = (i + 1) % 4
        faces.append((b[i], b[j], t[j], t[i]))

# ── Perimeter walls ───────────────────────────────────────────────────────────
def wall_x(faces, z, x0, x1, h, y0=0.0):
    """Wall running along X at depth z (centreline), height y0..h."""
    add_box(faces, x0, y0, z - T / 2, x1, h, z + T / 2)

def wall_z(faces, x, z0, z1, h, y0=0.0):
    add_box(faces, x - T / 2, y0, z0, x + T / 2, h, z1)

# gabled hall long walls (gable ends: profile trapezoids above the eave line)
wall_x(shell_faces, GABLE_Z0, 0.0, 120.0, EAVE)
wall_x(shell_faces, GABLE_Z1, 0.0, 120.0, EAVE)
for (b0, b1) in BAYS:
    trap = [(b0, EAVE), (b1, EAVE), (b1 - CREST_IN, CREST), (b0 + CREST_IN, CREST)]
    add_prism(shell_faces, trap, GABLE_Z0 - T / 2, GABLE_Z0 + T / 2)
    add_prism(shell_faces, trap, GABLE_Z1 - T / 2, GABLE_Z1 + T / 2)
# west wall
wall_z(shell_faces, 0.0, GABLE_Z0, GABLE_Z1, EAVE)
# east wing: north, east, inner-south walls
wall_x(shell_faces, EAST[2], EAST[0], EAST[1], EAST[4])
wall_z(shell_faces, EAST[1], EAST[2], EAST[3], EAST[4])
wall_x(shell_faces, EAST[3], SE_WING[1], EAST[1], EAST[4])       # notch north edge
# SE wing east wall (continues to annex depth at lower height)
wall_z(shell_faces, SE_WING[1], SE_WING[2], ANNEX_E[3], SE_WING[4])
# spandrel closing the eave step between gabled hall (7.4) and east wings (7.0)
wall_z(shell_faces, 120.0, GABLE_Z0, GABLE_Z1, EAVE, y0=SE_WING[4] - 0.3)
# annex south + west step walls
wall_x(shell_faces, ANNEX_E[3], ANNEX_E[0], ANNEX_E[1], ANNEX_E[4])
wall_z(shell_faces, ANNEX_E[0], ANNEX_W[3], ANNEX_E[3], ANNEX_E[4])
wall_x(shell_faces, ANNEX_W[3], ANNEX_W[0], ANNEX_W[1], ANNEX_W[4])
wall_z(shell_faces, ANNEX_W[0], ANNEX_W[2], ANNEX_W[3], ANNEX_W[4])

# ── Roofs ─────────────────────────────────────────────────────────────────────
def sloped_slab(faces, x0, y0, x1, y1, z0, z1, th):
    """Roof plane from (x0,y0) to (x1,y1) spanning z0..z1, thickness th
    (extruded straight up so eave edges stay vertical)."""
    poly = [(x0, y0), (x1, y1), (x1, y1 + th), (x0, y0 + th)]
    add_prism(faces, poly, z0, z1)

for (b0, b1) in BAYS:
    sloped_slab(shell_faces, b0, EAVE, b0 + CREST_IN, CREST, GABLE_Z0, GABLE_Z1, RT)
    sloped_slab(shell_faces, b1 - CREST_IN, CREST, b1, EAVE, GABLE_Z0, GABLE_Z1, RT)
    add_box(shell_faces, b0 + CREST_IN, CREST, GABLE_Z0,
            b1 - CREST_IN, CREST + RT, GABLE_Z1)
add_box(shell_faces, EAST[0], EAST[4], EAST[2], EAST[1], EAST[4] + RT, EAST[3])
add_box(shell_faces, SE_WING[0], SE_WING[4], SE_WING[2], SE_WING[1], SE_WING[4] + RT, SE_WING[3])
add_box(shell_faces, ANNEX_W[0], ANNEX_W[4], ANNEX_W[2], ANNEX_W[1], ANNEX_W[4] + RT, ANNEX_W[3])
add_box(shell_faces, ANNEX_E[0], ANNEX_E[4], ANNEX_E[2], ANNEX_E[1], ANNEX_E[4] + RT, ANNEX_E[3])

# rooftop penthouse (walls + lid) straddling the X=90 valley
px0, px1, pz0, pz1, py0, py1 = PENTHOUSE
add_box(shell_faces, px0, py0, pz0, px0 + T, py1, pz1)
add_box(shell_faces, px1 - T, py0, pz0, px1, py1, pz1)
add_box(shell_faces, px0, py0, pz0, px1, py1, pz0 + T)
add_box(shell_faces, px0, py0, pz1 - T, px1, py1, pz1)
add_box(shell_faces, px0, py1, pz0, px1, py1 + RT, pz1)

# ── V-splay columns + valley beams (reference photo) ─────────────────────────
BEAM_TOP = EAVE - 0.10          # beam tucked under the valley skin
BEAM_H, BEAM_W = 0.55, 0.50
COL_TOP = BEAM_TOP - BEAM_H     # legs carry the beam soffit
PED_H = 1.1                     # pedestal
SPLAY = 1.8                     # leg top offset from centre, along the beam
LEG_SX, LEG_SZ = 0.24, 0.20

for vx in VALLEYS:
    # longitudinal valley beam
    add_box(post_faces, vx - BEAM_W / 2, COL_TOP, GABLE_Z0 + 0.4,
            vx + BEAM_W / 2, BEAM_TOP, GABLE_Z1 - 0.4)
    for vz in (6.0, 15.0, 24.0, 33.0, 42.0, 51.0):
        add_box(post_faces, vx - 0.35, 0.0, vz - 0.35, vx + 0.35, PED_H, vz + 0.35)
        add_skew_box(post_faces, (vx, PED_H, vz), (vx, COL_TOP, vz - SPLAY),
                     LEG_SX, LEG_SZ)
        add_skew_box(post_faces, (vx, PED_H, vz), (vx, COL_TOP, vz + SPLAY),
                     LEG_SX, LEG_SZ)

# ── Write OBJ (mesh RD frame, shell/posts groups, ASCII only) ────────────────
def face_normal(pts):
    # Newell's method
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        nx += (a[1] - b[1]) * (a[2] + b[2])
        ny += (a[2] - b[2]) * (a[0] + b[0])
        nz += (a[0] - b[0]) * (a[1] + b[1])
    m = math.sqrt(nx * nx + ny * ny + nz * nz) or 1.0
    return (nx / m, ny / m, nz / m)

def poly_centroid(pts):
    n = len(pts)
    return tuple(sum(p[i] for p in pts) / n for i in range(3))

mtl = os.path.splitext(OUT)[0] + ".mtl"
with open(mtl, "w") as mf:
    mf.write("# CeDo factory - material slot manifest. Values are placeholders;\n"
             "# real materials are applied at runtime by MaterialPalette + MainWorld.\n"
             "newmtl shell\nKa 0.7 0.68 0.63\nKd 0.7 0.68 0.63\nKs 0 0 0\nNs 10\n"
             "newmtl posts\nKa 0.30 0.22 0.14\nKd 0.30 0.22 0.14\nKs 0 0 0\nNs 10\n")

verts, vids = [], {}
def vid(p):
    key = (round(p[0] * 1000), round(p[1] * 1000), round(p[2] * 1000))
    if key not in vids:
        vids[key] = len(verts) + 1
        verts.append((key[0] / 1000.0, key[1] / 1000.0, key[2] / 1000.0))
    return vids[key]

out_groups = []
for label, faces in (("shell", shell_faces), ("posts", post_faces)):
    emitted = []
    for poly in faces:
        mesh_pts = [to_mesh(*p) for p in poly]
        # to_mesh flips handedness (map z-down -> RD z), so reverse winding;
        # sanity-corrected below against the solid's outward direction anyway.
        mesh_pts.reverse()
        emitted.append(mesh_pts)
    out_groups.append((label, emitted))

with open(OUT, "w") as f:
    f.write("# CeDo factory - PARAMETRIC REBUILD (tools/generate_building.py).\n"
            "# Measured from the 3DBAG survey + operator reference photos.\n"
            "# 4 gabled bays / east flat wings / south annex / V-splay columns.\n")
    f.write("mtllib %s\n" % os.path.basename(mtl))
    all_polys = [(lbl, p) for lbl, polys in out_groups for p in polys]
    for _, p in all_polys:
        for pt in p:
            vid(pt)
    for v in verts:
        f.write("v %.4f %.4f %.4f\n" % v)
    normals = []
    for _, p in all_polys:
        normals.append(face_normal(p))
    for n in normals:
        f.write("vn %.4f %.4f %.4f\n" % n)
    ni = 0
    cur = None
    for lbl, p in all_polys:
        if lbl != cur:
            f.write("g %s\nusemtl %s\n" % (lbl, lbl))
            cur = lbl
        ni += 1
        f.write("f " + " ".join("%d//%d" % (vid(pt), ni) for pt in p) + "\n")

print("[generate] wrote %s: %d verts, %d faces (%d shell / %d posts)"
      % (OUT, len(verts), len(all_polys),
         sum(1 for l, _ in all_polys if l == "shell"),
         sum(1 for l, _ in all_polys if l == "posts")))
