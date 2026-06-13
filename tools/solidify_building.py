#!/usr/bin/env python3
"""
Solidify the CeDo factory building — STANDALONE, no Godot required.

Reads the thin 3DBAG LOD2.2 shell (CeDo_building.obj, an unwelded triangle soup of
zero-thickness surfaces) and writes a SOLID model: welded vertices, real wall
thickness, closed open seams, recomputed normals. The output .obj opens in any 3D
viewer (Windows 3D Viewer, Blender, online viewers) — no Godot, no engine.

Run locally:
    python tools/solidify_building.py
    python tools/solidify_building.py --thickness 0.5   # tune wall thickness (m)

Pure standard-library Python 3 (no numpy / no pip installs).
"""
import os
import sys
import math
import json
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SRC = os.path.join(PROJECT, "assets", "models", "CeDo_building.obj")
OUT = os.path.join(PROJECT, "assets", "models", "CeDo_factory_solid.obj")
WELD_Q = 1000.0  # weld tolerance: round positions to 1 mm

# The source tile holds ~124 separate buildings. We solidify ONLY the factory —
# the one the user marked by setting factory_center in WorldSetup. We locate it by
# reading that marker, mapping it from the game's local frame back to the model's
# RD coordinates, and picking the connected component it falls inside.


def find_factory_center_rd(obj_aabb_center):
    """Return (rd_x, rd_z) of the factory_center marker, or None if unavailable."""
    appdata = os.environ.get("APPDATA", "")
    candidates = [
        os.path.join(appdata, "Godot", "app_userdata", "CeDo Simulator", "world_layout.json"),
    ]
    for path in candidates:
        if os.path.isfile(path):
            try:
                d = json.load(open(path))
                fc = d.get("factory_center")
                if fc and (fc.get("x") or fc.get("z")):
                    # local -> RD: WorldSetup shifts the model by -aabb_center, so
                    # RD = local + aabb_center.
                    return (fc["x"] + obj_aabb_center[0], fc["z"] + obj_aabb_center[2])
            except Exception as e:
                print("[solidify] could not read %s: %s" % (path, e))
    return None


def connected_components(uniq, wt):
    par = list(range(len(uniq)))
    def find(x):
        while par[x] != x:
            par[x] = par[par[x]]; x = par[x]
        return x
    for a, b, c in wt:
        par[find(a)] = find(b); par[find(find(b))] = find(c)
    comp = {}
    for ti, (a, b, c) in enumerate(wt):
        comp.setdefault(find(a), []).append(ti)
    return comp


def parse_obj(path):
    raw, tris = [], []
    with open(path, "r", errors="replace") as f:
        for line in f:
            if line.startswith("v "):
                p = line.split()
                raw.append((float(p[1]), float(p[2]), float(p[3])))
            elif line.startswith("f "):
                p = line.split()[1:]
                idx = []
                for tok in p:
                    vi = int(tok.split("/")[0])
                    if vi < 0:
                        vi = len(raw) + vi + 1
                    idx.append(vi - 1)
                for k in range(1, len(idx) - 1):  # fan-triangulate n-gons
                    tris.append((idx[0], idx[k], idx[k + 1]))
    return raw, tris


def weld(raw, tris):
    table, uniq, remap = {}, [], [0] * len(raw)
    for i, p in enumerate(raw):
        key = (round(p[0] * WELD_Q), round(p[1] * WELD_Q), round(p[2] * WELD_Q))
        j = table.get(key)
        if j is None:
            j = len(uniq)
            table[key] = j
            uniq.append(p)
        remap[i] = j
    wt = []
    for a, b, c in tris:
        a, b, c = remap[a], remap[b], remap[c]
        if a != b and b != c and a != c:
            wt.append((a, b, c))
    return uniq, wt


def sub(a, b): return (a[0] - b[0], a[1] - b[1], a[2] - b[2])
def cross(u, v): return (u[1]*v[2]-u[2]*v[1], u[2]*v[0]-u[0]*v[2], u[0]*v[1]-u[1]*v[0])


def vertex_normals(uniq, wt):
    vn = [[0.0, 0.0, 0.0] for _ in uniq]
    for a, b, c in wt:
        n = cross(sub(uniq[b], uniq[a]), sub(uniq[c], uniq[a]))  # area-weighted
        for vi in (a, b, c):
            vn[vi][0] += n[0]; vn[vi][1] += n[1]; vn[vi][2] += n[2]
    out = []
    for n in vn:
        m = math.sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2])
        out.append((n[0]/m, n[1]/m, n[2]/m) if m > 1e-9 else (0.0, 1.0, 0.0))
    return out


def merge_coplanar(tri_verts, angle_deg=1.0, max_iterations=10):
    """Collapse coplanar adjacent triangles into N-gon face groups.

    `tri_verts` is a flat list of 3-tuples (already-resolved Vector3 coords); each
    consecutive 3 entries form one triangle. We treat each triangle as a node in a
    union-find graph, build edge→triangle adjacency on the SHARED POSITIONS (we
    re-key by rounded XYZ so duplicate-but-equal verts count as the same point),
    then for every shared edge check whether the two triangles' normals are within
    `angle_deg` of each other. If yes → union them. Re-iterate using AREA-WEIGHTED
    GROUP normals so groups that became coplanar after the first merge also catch.
    Returns (groups, group_normal): groups[gid] = list of triangle indices,
    group_normal[gid] = the unified (nx, ny, nz) for that group.
    """
    n_tri = len(tri_verts) // 3
    # Key each unique position to a small int.
    q = 1000.0  # 1 mm weld
    pos_id = {}
    tri_ids = []  # 3 ids per triangle, flat
    for v in tri_verts:
        key = (round(v[0] * q), round(v[1] * q), round(v[2] * q))
        if key not in pos_id:
            pos_id[key] = len(pos_id)
        tri_ids.append(pos_id[key])

    # Triangle area-weighted normal (non-unit).
    def tri_area_normal(ti):
        a = tri_verts[ti * 3]
        b = tri_verts[ti * 3 + 1]
        c = tri_verts[ti * 3 + 2]
        return cross(sub(b, a), sub(c, a))

    # Build edge → triangles map (undirected, on position ids).
    edge_tris = {}
    for ti in range(n_tri):
        a_id = tri_ids[ti * 3]
        b_id = tri_ids[ti * 3 + 1]
        c_id = tri_ids[ti * 3 + 2]
        if a_id == b_id or b_id == c_id or a_id == c_id:
            continue  # degenerate
        for u, v in ((a_id, b_id), (b_id, c_id), (c_id, a_id)):
            k = (u, v) if u < v else (v, u)
            edge_tris.setdefault(k, []).append(ti)

    # Union-find over triangles.
    parent = list(range(n_tri))
    def find(x):
        while parent[x] != x:
            parent[x] = parent[parent[x]]
            x = parent[x]
        return x
    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb
            return True
        return False

    threshold_cos = math.cos(math.radians(angle_deg))

    for it in range(max_iterations):
        # Group normals (area-weighted).
        roots = {}
        for ti in range(n_tri):
            roots.setdefault(find(ti), []).append(ti)
        gn = {}
        for gid, members in roots.items():
            sx = sy = sz = 0.0
            for ti in members:
                n = tri_area_normal(ti)
                sx += n[0]; sy += n[1]; sz += n[2]
            m = math.sqrt(sx * sx + sy * sy + sz * sz) or 1.0
            gn[gid] = (sx / m, sy / m, sz / m)

        merged_count = 0
        for k, tlist in edge_tris.items():
            if len(tlist) != 2:
                continue
            t1, t2 = tlist
            g1, g2 = find(t1), find(t2)
            if g1 == g2:
                continue
            n1 = gn[g1]; n2 = gn[g2]
            dot = n1[0] * n2[0] + n1[1] * n2[1] + n1[2] * n2[2]
            if dot >= threshold_cos:
                if union(t1, t2):
                    merged_count += 1

        print("[merge] iter %d: %d new merges (groups so far: %d)" % (it + 1, merged_count, len(roots)))
        if merged_count == 0:
            break

    # Final groups + group normals.
    final_groups = {}
    for ti in range(n_tri):
        final_groups.setdefault(find(ti), []).append(ti)
    final_normals = {}
    for gid, members in final_groups.items():
        sx = sy = sz = 0.0
        for ti in members:
            n = tri_area_normal(ti)
            sx += n[0]; sy += n[1]; sz += n[2]
        m = math.sqrt(sx * sx + sy * sy + sz * sz) or 1.0
        final_normals[gid] = (sx / m, sy / m, sz / m)
    return final_groups, final_normals, tri_ids, pos_id


def boundary_polygons_of_group(member_tris, tri_ids):
    """Trace the closed boundary loops of a merged-triangle group.

    For each triangle, walk its 3 directed edges. An edge is INTERIOR to the
    group iff its REVERSE also appears among the group's directed edges. The
    remaining edges form the group's boundary (potentially multiple disjoint
    loops if the group has holes). Returns a list of polygons (each a list of
    position-id vertices, ordered).
    """
    directed = set()
    for ti in member_tris:
        a = tri_ids[ti * 3]
        b = tri_ids[ti * 3 + 1]
        c = tri_ids[ti * 3 + 2]
        directed.add((a, b)); directed.add((b, c)); directed.add((c, a))
    next_v = {}
    for u, v in directed:
        if (v, u) not in directed:
            next_v[u] = v
    polys = []
    visited = set()
    for start in list(next_v.keys()):
        if start in visited:
            continue
        poly = [start]; visited.add(start)
        cur = next_v.get(start)
        safety = 0
        while cur is not None and cur != start and safety < 100000:
            poly.append(cur); visited.add(cur)
            cur = next_v.get(cur)
            safety += 1
        if cur == start and len(poly) >= 3:
            polys.append(poly)
    return polys


# ── DOOR CARVING ──────────────────────────────────────────────────────────────
# Bake permanent factory entrances directly into the .obj instead of relying on
# the brittle runtime WallOpenings polygon-clip. Each --door snaps to the
# closest exterior wall (factory is axis-aligned, so we just take the smaller
# of X-axis-distance vs Z-axis-distance), subdivides nearby shell triangles to
# fine resolution so the centroid-drop produces a clean ~door-sized hole, and
# adds the inner walls of the door tunnel as new triangles. No runtime carve =
# the door cannot fail to appear.

def _vec_sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def _vec_len(v): return math.sqrt(v[0]*v[0] + v[1]*v[1] + v[2]*v[2])
def _vec_mid(a, b): return ((a[0]+b[0])/2, (a[1]+b[1])/2, (a[2]+b[2])/2)

def subdivide_to_max_edge(tri, max_edge):
    """Recursively split the longest edge until all edges <= max_edge.
    Splitting the LONGEST edge (not a fixed midpoint scheme) means adjacent
    triangles that share an edge produce the same midpoint, so the merge step
    re-glues them into one wall n-gon — minus the dropped sub-triangles."""
    stack = [tri]; out = []
    while stack:
        a, b, c = stack.pop()
        el = (_vec_len(_vec_sub(b, a)), _vec_len(_vec_sub(c, b)), _vec_len(_vec_sub(a, c)))
        me = max(el)
        if me <= max_edge:
            out.append((a, b, c)); continue
        if el[0] == me:
            m = _vec_mid(a, b); stack.append((a, m, c)); stack.append((m, b, c))
        elif el[1] == me:
            m = _vec_mid(b, c); stack.append((a, b, m)); stack.append((a, m, c))
        else:
            m = _vec_mid(c, a); stack.append((a, b, m)); stack.append((m, b, c))
    return out

def _tri_centroid(t):
    return ((t[0][0]+t[1][0]+t[2][0])/3, (t[0][1]+t[1][1]+t[2][1])/3, (t[0][2]+t[1][2]+t[2][2])/3)

def _tri_aabb_overlaps(t, box):
    bx0, by0, bz0, bx1, by1, bz1 = box
    tx_min = min(t[0][0], t[1][0], t[2][0]); tx_max = max(t[0][0], t[1][0], t[2][0])
    ty_min = min(t[0][1], t[1][1], t[2][1]); ty_max = max(t[0][1], t[1][1], t[2][1])
    tz_min = min(t[0][2], t[1][2], t[2][2]); tz_max = max(t[0][2], t[1][2], t[2][2])
    return not (tx_max < bx0 or tx_min > bx1 or ty_max < by0 or ty_min > by1
                or tz_max < bz0 or tz_min > bz1)

def _point_in_box(p, box):
    return (box[0] <= p[0] <= box[3] and box[1] <= p[1] <= box[4] and box[2] <= p[2] <= box[5])

def door_kill_box(door, t_wall, slack=1.5):
    """Build the 3D AABB whose interior every shell sub-triangle gets dropped.
    Thicker than the wall (slack * t_wall) on the wall-normal axis so the
    outer shell, inner shell, and bridge triangles all get cleared together.
    `door` carries its own width / height / bottom_y so windows (lifted off
    the floor) and any odd-sized opening work without globals."""
    cx, cz, facing, width, height, bottom_y = door
    if facing == 'x':
        return (cx - t_wall * slack, bottom_y - 0.05, cz - width / 2,
                cx + t_wall * slack, bottom_y + height, cz + width / 2)
    return (cx - width / 2, bottom_y - 0.05, cz - t_wall * slack,
            cx + width / 2, bottom_y + height, cz + t_wall * slack)

def door_tunnel_tris(door, t_wall):
    """Top header + two side jambs through the wall thickness. NO floor — the
    door reaches the operating slab. Six triangles per door (3 quads × 2).
    For a WINDOW (bottom_y > floor) a sill quad is added too."""
    cx, cz, facing, width, height, bottom_y = door
    floor_y = bottom_y
    hw = width / 2
    top_y = floor_y + height
    tris = []
    if facing == 'x':
        outer_x = cx + 0.02
        inner_x = cx - t_wall - 0.02
        # Header (top of door, normal points DOWN into the tunnel).
        v1 = (outer_x, top_y, cz - hw); v2 = (outer_x, top_y, cz + hw)
        v3 = (inner_x, top_y, cz + hw); v4 = (inner_x, top_y, cz - hw)
        tris += [(v1, v2, v3), (v1, v3, v4)]
        # Left jamb (low-Z side, normal points +Z).
        l1 = (outer_x, floor_y, cz - hw); l2 = (inner_x, floor_y, cz - hw)
        l3 = (inner_x, top_y, cz - hw);   l4 = (outer_x, top_y, cz - hw)
        tris += [(l1, l2, l3), (l1, l3, l4)]
        # Right jamb (high-Z side, normal points -Z).
        r1 = (outer_x, floor_y, cz + hw); r2 = (outer_x, top_y, cz + hw)
        r3 = (inner_x, top_y, cz + hw);   r4 = (inner_x, floor_y, cz + hw)
        tris += [(r1, r2, r3), (r1, r3, r4)]
    else:
        outer_z = cz + 0.02
        inner_z = cz - t_wall - 0.02
        v1 = (cx - hw, top_y, outer_z); v2 = (cx + hw, top_y, outer_z)
        v3 = (cx + hw, top_y, inner_z); v4 = (cx - hw, top_y, inner_z)
        tris += [(v1, v2, v3), (v1, v3, v4)]
        l1 = (cx - hw, floor_y, outer_z); l2 = (cx - hw, top_y, outer_z)
        l3 = (cx - hw, top_y, inner_z);   l4 = (cx - hw, floor_y, inner_z)
        tris += [(l1, l2, l3), (l1, l3, l4)]
        r1 = (cx + hw, floor_y, outer_z); r2 = (cx + hw, floor_y, inner_z)
        r3 = (cx + hw, top_y, inner_z);   r4 = (cx + hw, top_y, outer_z)
        tris += [(r1, r2, r3), (r1, r3, r4)]
    return tris

def snap_door_to_wall(cx, cz, bbx0, bbx1, bbz0, bbz1):
    """Pick the nearest of the 4 perimeter walls and snap onto it.
    Returns (cx, cz, facing) where facing is 'x' or 'z'."""
    dW = abs(cx - bbx0); dE = abs(cx - bbx1)
    dS = abs(cz - bbz0); dN = abs(cz - bbz1)
    nearest = min(dW, dE, dS, dN)
    if nearest == dW: return (bbx0, cz, 'x')
    if nearest == dE: return (bbx1, cz, 'x')
    if nearest == dS: return (cx, bbz0, 'z')
    return (cx, bbz1, 'z')

def boundary_edges(wt):
    present = set()
    for a, b, c in wt:
        present.add((a, b)); present.add((b, c)); present.add((c, a))
    out = []
    for a, b, c in wt:
        for e in ((a, b), (b, c), (c, a)):
            if (e[1], e[0]) not in present:
                out.append(e)
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--thickness", type=float, default=0.30, help="wall thickness in metres")
    ap.add_argument("--src", default=SRC)
    ap.add_argument("--out", default=OUT)
    ap.add_argument("--all", action="store_true", help="solidify ALL ~124 buildings, not just the factory")
    ap.add_argument("--center-x", type=float, default=None, help="RD X of the building to keep (overrides factory_center)")
    ap.add_argument("--center-z", type=float, default=None, help="RD Z of the building to keep")
    ap.add_argument("--posts", type=int, default=4, help="rows of wooden structural posts across the building width (4 or 5)")
    ap.add_argument("--post-spacing", type=float, default=10.0, help="metres between posts along the depth axis")
    ap.add_argument("--post-section", type=float, default=0.40, help="square cross-section of each post (m)")
    ap.add_argument("--no-posts", action="store_true", help="skip the wooden structural posts entirely")
    ap.add_argument("--merge-deg", type=float, default=1.0, help="coplanar-merge angle threshold (degrees); 0 = disable merging")
    ap.add_argument("--merge-iter", type=int, default=10, help="max iterations for the coplanar merge")
    ap.add_argument("--door", action="append", default=[],
        help='Bake an entrance into the shell at "cx,cz" (RD coords). Snaps to the '
             'nearest exterior wall. Repeatable: pass --door once per door.')
    ap.add_argument("--scene-door", action="append", default=[],
        help='Same as --door but coordinates are SCENE-LOCAL (what the player sees '
             'in-game after the building is shifted to origin). The script converts '
             'to RD internally using the source-tile AABB. Easier to use: stand at '
             'the door spot in-game, note your X/Z, pass them here.')
    ap.add_argument("--door-width", type=float, default=4.0, help="door width in metres (default 4 m)")
    ap.add_argument("--door-height", type=float, default=3.0, help="door height in metres (default 3 m)")
    ap.add_argument("--door-subdivide", type=float, default=0.4,
        help="max edge length for subdividing wall triangles near a door (m). "
             "Smaller = cleaner carve edge but more triangles.")
    args = ap.parse_args()
    t = args.thickness

    print("[solidify] reading %s" % args.src)
    raw, tris = parse_obj(args.src)
    print("[solidify] raw: %d verts, %d tris" % (len(raw), len(tris)))
    uniq, wt = weld(raw, tris)
    print("[solidify] welded: %d verts, %d tris" % (len(uniq), len(wt)))

    # ── Isolate ONLY the factory building (the tile holds ~124 separate buildings) ──
    if not args.all:
        xs = [p[0] for p in uniq]; ys = [p[1] for p in uniq]; zs = [p[2] for p in uniq]
        aabb_c = ((min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2, (min(zs) + max(zs)) / 2)
        if args.center_x is not None and args.center_z is not None:
            target = (args.center_x, args.center_z)
            print("[solidify] using --center RD (%.0f, %.0f)" % target)
        else:
            target = find_factory_center_rd(aabb_c)
            if target:
                print("[solidify] factory_center marker -> RD (%.0f, %.0f)" % target)
        if target is None:
            print("[solidify] WARNING: no factory_center found; solidifying ALL buildings. Use --center-x/--center-z or --all.")
        else:
            comp = connected_components(uniq, wt)
            best = None
            for tl in comp.values():
                cxs = [uniq[vi][0] for ti in tl for vi in wt[ti]]
                czs = [uniq[vi][2] for ti in tl for vi in wt[ti]]
                bx0, bx1, bz0, bz1 = min(cxs), max(cxs), min(czs), max(czs)
                ccx, ccz = (bx0 + bx1) / 2, (bz0 + bz1) / 2
                inside = bx0 <= target[0] <= bx1 and bz0 <= target[1] <= bz1
                score = (0 if inside else 1, math.hypot(ccx - target[0], ccz - target[1]))
                if best is None or score < best[0]:
                    best = (score, tl, ccx, ccz, bx1 - bx0, bz1 - bz0)
            wt = [wt[ti] for ti in best[1]]
            print("[solidify] FACTORY isolated: %d tris, centroid RD (%.0f, %.0f), %.0f x %.0f m" % (
                len(wt), best[2], best[3], best[4], best[5]))

    vn = vertex_normals(uniq, wt)
    bnd = boundary_edges(wt)
    print("[solidify] open boundary edges: %d" % len(bnd))

    def inner(i):
        p, n = uniq[i], vn[i]
        return (p[0] - n[0]*t, p[1] - n[1]*t, p[2] - n[2]*t)

    # Build output triangles: outer shell + inner shell (reversed) + bridged seams.
    out_tris = []
    for a, b, c in wt:
        out_tris.append((uniq[a], uniq[b], uniq[c]))
    for a, b, c in wt:
        out_tris.append((inner(a), inner(c), inner(b)))   # reversed winding
    for a, b in bnd:
        oa, ob, ib, ia = uniq[a], uniq[b], inner(b), inner(a)
        out_tris.append((oa, ob, ib))
        out_tris.append((oa, ib, ia))
    shell_tri_count = len(out_tris)   # everything beyond this index is "posts"

    # ── Factory bounding box (used by both doors AND posts) ───────────────────
    # Computed FROM FACTORY TRIANGLES ONLY so it doesn't span the whole 1.1km
    # source tile.
    f_idx_all = set()
    for tri in wt:
        f_idx_all.add(tri[0]); f_idx_all.add(tri[1]); f_idx_all.add(tri[2])
    f_verts_all = [uniq[i] for i in f_idx_all]
    fxs = [p[0] for p in f_verts_all]
    fys = [p[1] for p in f_verts_all]
    fzs = [p[2] for p in f_verts_all]
    fac_x0, fac_x1 = min(fxs), max(fxs)
    fac_y0, fac_y1 = min(fys), max(fys)
    fac_z0, fac_z1 = min(fzs), max(fzs)

    # ── Bake doors into the shell ─────────────────────────────────────────────
    door_specs = list(args.door)
    # Convert scene-local entries to RD by adding the source tile's AABB centre
    # (the inverse of WorldSetup's local-origin shift).
    if args.scene_door:
        for s in args.scene_door:
            sx, sz = (float(p) for p in s.split(","))
            door_specs.append("%.4f,%.4f" % (sx + aabb_c[0], sz + aabb_c[2]))
    if door_specs:
        doors = []
        for s in door_specs:
            parts = s.split(",")
            cx, cz = float(parts[0]), float(parts[1])
            # Optional per-door overrides: "cx,cz" → defaults; "cx,cz,W,H[,BY]"
            # → explicit dimensions. Bottom_y defaults to the factory floor.
            w  = float(parts[2]) if len(parts) > 2 else args.door_width
            h  = float(parts[3]) if len(parts) > 3 else args.door_height
            by = float(parts[4]) if len(parts) > 4 else fac_y0
            snap_x, snap_z, facing = snap_door_to_wall(cx, cz, fac_x0, fac_x1, fac_z0, fac_z1)
            doors.append((snap_x, snap_z, facing, w, h, by))
        kill_boxes = [door_kill_box(d, t) for d in doors]
        shell_in = out_tris[:shell_tri_count]
        carved = []
        n_drop = 0
        for tri in shell_in:
            if not any(_tri_aabb_overlaps(tri, b) for b in kill_boxes):
                carved.append(tri); continue
            for sub in subdivide_to_max_edge(tri, args.door_subdivide):
                if any(_point_in_box(_tri_centroid(sub), b) for b in kill_boxes):
                    n_drop += 1
                else:
                    carved.append(sub)
        # Add door-tunnel inner walls (header + 2 jambs per door; sill for windows).
        tunnel = []
        for d in doors:
            tunnel += door_tunnel_tris(d, t)
        out_tris = carved + tunnel
        shell_tri_count = len(out_tris)
        print("[solidify] doors: %d baked  (dropped %d sub-tris, added %d tunnel tris)"
              % (len(doors), n_drop, len(tunnel)))
        for d in doors:
            print("           - %s wall  cx=%.0f cz=%.0f  %.1fw × %.1fh  bottom_y=%.2f" % (
                {'x': 'east/west', 'z': 'north/south'}[d[2]], d[0], d[1], d[3], d[4], d[5]))

    # ── Wooden structural posts ────────────────────────────────────────────────
    # Stand vertical posts inside the factory: `args.posts` rows ACROSS the
    # building width (so we cover the 4 or 5 lowest roof points), each row spaced
    # `args.post-spacing` metres apart ALONG the depth axis. Each post is a square
    # timber from the floor up to the LOCAL roof height directly above it
    # (sampled from the welded shell). Output as a separate "g posts" group so
    # any external viewer can colour them as wood.
    post_tris = []
    if not args.no_posts:
        # Reuse the factory AABB we already computed for the door pass.
        f_verts = f_verts_all
        bbx0, bbx1 = fac_x0, fac_x1
        bby0, bby1 = fac_y0, fac_y1
        bbz0, bbz1 = fac_z0, fac_z1
        # Pick depth axis = whichever is longer (so spacing follows the long side).
        width_x = bbx1 - bbx0
        depth_z = bbz1 - bbz0
        depth_is_z = depth_z >= width_x
        if depth_is_z:
            depth_min, depth_max = bbz0, bbz1
            width_min, width_max = bbx0, bbx1
        else:
            depth_min, depth_max = bbx0, bbx1
            width_min, width_max = bbz0, bbz1

        # Inset a little from the walls so posts sit INSIDE the building.
        inset = max(args.post_section * 1.2, 1.0)
        rows = max(2, int(args.posts))
        # Evenly distribute the rows across the width (interior, not on the walls).
        if rows == 1:
            row_pos = [(width_min + width_max) * 0.5]
        else:
            usable = (width_max - width_min) - 2 * inset
            row_pos = [width_min + inset + usable * (i / float(rows - 1)) for i in range(rows)]
        # Posts every `post-spacing` metres along depth.
        spacing = max(args.post_spacing, 1.0)
        n_along = max(2, int((depth_max - depth_min - 2 * inset) / spacing) + 1)
        depth_pos = [depth_min + inset + spacing * i for i in range(n_along)]

        # Sample the local roof height above each (X,Z) within the factory verts
        # only (not the whole tile). Find the highest factory vert in a small XZ
        # window — good enough for a flat-roof factory where ys cluster at eaves.
        def roof_y_at(cx, cz, win=4.0):
            best = bby1
            for pv in f_verts:
                if abs(pv[0] - cx) <= win and abs(pv[2] - cz) <= win:
                    if pv[1] > best:
                        best = pv[1]
            return best

        sec = args.post_section
        floor_y = bby0
        n_posts = 0
        for rx_or_z in row_pos:
            for dz_or_x in depth_pos:
                cx = rx_or_z if not depth_is_z else rx_or_z
                cz = dz_or_x if depth_is_z else None
                # Resolve the actual XZ depending on which axis is depth.
                if depth_is_z:
                    px, pz = rx_or_z, dz_or_x
                else:
                    pz, px = rx_or_z, dz_or_x
                # Skip posts that fall outside the building footprint (we use a
                # crude AABB-only filter; the building's polygonal footprint isn't
                # convex but most factory cells are roughly rectangular).
                if not (bbx0 + 0.1 <= px <= bbx1 - 0.1 and bbz0 + 0.1 <= pz <= bbz1 - 0.1):
                    continue
                top_y = roof_y_at(px, pz) - 0.05   # tuck under the roof skin
                if top_y - floor_y < 2.0:
                    continue   # not tall enough to be a real column
                # Build a square box (cross-section sec×sec) from floor to roof.
                hx = sec * 0.5
                v000 = (px - hx, floor_y, pz - hx); v100 = (px + hx, floor_y, pz - hx)
                v110 = (px + hx, floor_y, pz + hx); v010 = (px - hx, floor_y, pz + hx)
                v001 = (px - hx, top_y,  pz - hx); v101 = (px + hx, top_y,  pz - hx)
                v111 = (px + hx, top_y,  pz + hx); v011 = (px - hx, top_y,  pz + hx)
                # 12 triangles (6 faces).
                faces = [
                    (v000, v100, v101), (v000, v101, v001),  # -Z
                    (v110, v010, v011), (v110, v011, v111),  # +Z
                    (v100, v110, v111), (v100, v111, v101),  # +X
                    (v010, v000, v001), (v010, v001, v011),  # -X
                    (v001, v101, v111), (v001, v111, v011),  # +Y (top)
                    (v010, v110, v100), (v010, v100, v000),  # -Y (bottom)
                ]
                post_tris.extend(faces)
                n_posts += 1
        print("[solidify] wooden posts: %d posts (%d rows × ~%d along depth), section %.2f m" % (
            n_posts, rows, n_along, sec))
    all_tris = out_tris + post_tris

    # ── Coplanar-merge pass: collapse the 14,673-tri soup into N-gon walls ────
    # Each `out_tris[ti] = (v0,v1,v2)` is flattened so we get 3*N triangle verts,
    # the merge function builds groups whose internal triangles share normals
    # within `merge_deg`, then we trace each group's boundary polygon and emit it
    # as ONE `f`-line in the .obj. Without merge: 8,192 triangles (visible teeth).
    # With 1° merge: each wall + each roof slab collapses to a single n-gon.
    tri_verts_flat = []
    for tri in all_tris:
        tri_verts_flat.append(tri[0]); tri_verts_flat.append(tri[1]); tri_verts_flat.append(tri[2])

    if args.merge_deg > 0.0:
        print("[solidify] starting coplanar merge (threshold=%.2f°, max %d iter)" % (
            args.merge_deg, args.merge_iter))
        groups, group_normals, tri_ids, pos_id = merge_coplanar(
            tri_verts_flat, angle_deg=args.merge_deg, max_iterations=args.merge_iter)
    else:
        groups, group_normals, tri_ids, pos_id = {}, {}, [], {}
        # No-merge mode: each triangle is its own group (writer falls back to triangles).

    # Position-id → coordinates lookup (inverse of pos_id).
    id_to_pos = [None] * len(pos_id)
    for key, idx in pos_id.items():
        id_to_pos[idx] = (key[0] / 1000.0, key[1] / 1000.0, key[2] / 1000.0)

    # Which triangle index range belongs to the SHELL vs the POSTS group.
    def is_post_tri(ti): return ti >= shell_tri_count
    def is_shell_tri(ti): return ti < shell_tri_count

    # ── Write the sidecar .mtl ────────────────────────────────────────────────
    # Two named materials — Godot's OBJ importer reads `usemtl` declarations and
    # creates ONE SURFACE PER MATERIAL on the imported mesh, which lets
    # MainWorld._apply_textures land the calibrated mat_timber_dark on the
    # `posts` surface and the cream shell paint on `shell`. Without these, the
    # importer collapses everything to a single surface and the timber material
    # has nowhere to go (the V-beams render as shell paint).
    mtl_out = os.path.splitext(args.out)[0] + ".mtl"
    with open(mtl_out, "w") as mf:
        mf.write("# CeDo factory — material slot manifest. Values are placeholders;\n"
                 "# real materials are applied at runtime by MaterialPalette + MainWorld.\n"
                 "newmtl shell\nKa 0.7 0.68 0.63\nKd 0.7 0.68 0.63\nKs 0 0 0\nNs 10\n"
                 "newmtl posts\nKa 0.30 0.22 0.14\nKd 0.30 0.22 0.14\nKs 0 0 0\nNs 10\n")
    print("[solidify] wrote %s (mtllib for shell/posts slots)" % mtl_out)

    # ── Write the .obj ────────────────────────────────────────────────────────
    with open(args.out, "w") as f:
        f.write("# CeDo factory — solidified + coplanar-merged (thickness=%.2fm, merge=%.2f°).\n"
                "# Standalone OBJ — no Godot required. Walls collapsed from triangle soup\n"
                "# into clean N-gons by iterative coplanar merge.\n" % (t, args.merge_deg))
        f.write("mtllib %s\n" % os.path.basename(mtl_out))
        # Vertices: one per unique position.
        for p in id_to_pos:
            f.write("v %.4f %.4f %.4f\n" % p)
        # Normals: one per merged group (each group has its own averaged normal).
        gid_to_normal_idx = {}
        if args.merge_deg > 0.0:
            ni = 1
            for gid, nrm in group_normals.items():
                f.write("vn %.4f %.4f %.4f\n" % nrm)
                gid_to_normal_idx[gid] = ni
                ni += 1
        else:
            # Fallback: per-triangle normals.
            for tri in all_tris:
                u = sub(tri[1], tri[0]); w = sub(tri[2], tri[0])
                n = cross(u, w)
                m = math.sqrt(n[0]*n[0] + n[1]*n[1] + n[2]*n[2]) or 1.0
                f.write("vn %.4f %.4f %.4f\n" % (n[0]/m, n[1]/m, n[2]/m))

        # Emit faces, splitting into "shell" and "posts" groups.
        if args.merge_deg > 0.0:
            shell_polys = 0; post_polys = 0
            # Two passes so the .obj has a clean `g shell` then `g posts` ordering.
            # `usemtl` per group makes Godot's importer create ONE SURFACE PER
            # MATERIAL — surface 0 = shell, surface 1 = posts. MainWorld then
            # overrides them independently.
            for label, predicate in (("shell", is_shell_tri), ("posts", is_post_tri)):
                f.write("g %s\nusemtl %s\n" % (label, label))
                for gid, members in groups.items():
                    members_in_group = [ti for ti in members if predicate(ti)]
                    if not members_in_group:
                        continue
                    polys = boundary_polygons_of_group(members_in_group, tri_ids)
                    ni = gid_to_normal_idx[gid]
                    for poly in polys:
                        parts = ["%d//%d" % (pi + 1, ni) for pi in poly]
                        f.write("f " + " ".join(parts) + "\n")
                        if label == "shell":
                            shell_polys += 1
                        else:
                            post_polys += 1
            faces_out = shell_polys + post_polys
            print("[solidify] merged into %d shell n-gons + %d post n-gons (was %d triangles)" % (
                shell_polys, post_polys, len(all_tris)))
        else:
            # No-merge: fall back to triangle list (old behaviour).
            vi = 1
            for label, sl in (("shell", out_tris), ("posts", post_tris)):
                if not sl: continue
                f.write("g %s\nusemtl %s\n" % (label, label))
                for _ in sl:
                    f.write("f %d//%d %d//%d %d//%d\n" % (vi, vi, vi+1, vi+1, vi+2, vi+2))
                    vi += 3
            faces_out = len(all_tris)

    print("[solidify] wrote %s" % args.out)
    print("[solidify] %d face(s) total. Open in any 3D viewer (no Godot)." % faces_out)


if __name__ == "__main__":
    main()
