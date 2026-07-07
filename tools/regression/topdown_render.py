#!/usr/bin/env python3
"""Top-down regression renderer for the CeDo Simulator world/save harness.

Consumes a positions dump written by the in-engine harness
(src/tests/regression_world_save.gd) and draws a top-down schematic PNG so a
human (or a diff) can VERIFY that:
  - machines land INSIDE the building footprint (not floating in the yard),
  - doors/gates sit ON a wall line,
  - TL bars are inside,
  - a saved layout reloads to the same coordinates (round-trip).

This is deliberately a data-driven schematic, not a photoreal 3D grab: it is
deterministic, headless-safe, and every dot is colour-coded by its pass/fail
verdict, which is what makes it useful as a regression artifact. A real Godot
orthographic capture (if the box can render offscreen) is produced separately
by the harness; this view is the source of truth for correctness.

Scene axes: X = RD east (horizontal, +right), Z = -RD north (vertical). We flip
the Z axis so plant-north points UP, matching the in-game map overlay.

Usage:
    python topdown_render.py <positions.json> <out.png>
"""
from __future__ import annotations
import json
import sys
from pathlib import Path

import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MplPolygon


def _poly_xz(pts):
    """Accept [[x,z],...] or [[x,y,z],...] and return (xs, zs)."""
    xs, zs = [], []
    for p in pts:
        if len(p) >= 3:
            xs.append(float(p[0]))
            zs.append(float(p[2]))
        elif len(p) == 2:
            xs.append(float(p[0]))
            zs.append(float(p[1]))
    return xs, zs


def render(data: dict, out_path: str) -> None:
    fig, ax = plt.subplots(figsize=(14, 12), dpi=110)
    ax.set_facecolor("#101418")

    meta = data.get("meta", {})
    footprint = data.get("building_footprint", [])
    doors = data.get("doors", [])
    tl_bars = data.get("tl_bars", [])
    machines = data.get("machines", [])
    line_starts = data.get("line_starts", {})
    checks = data.get("checks", [])

    # --- building footprint -------------------------------------------------
    if footprint:
        xs, zs = _poly_xz(footprint)
        if xs:
            ax.add_patch(MplPolygon(
                list(zip(xs, zs)), closed=True,
                facecolor="#1d2733", edgecolor="#5b7fa6", linewidth=2.0,
                zorder=1, label="building footprint"))

    # --- perimeter fence ----------------------------------------------------
    fence = data.get("fence", [])
    fence_cross = 0
    for seg in fence:
        a = seg.get("a"); b = seg.get("b")
        if not a or not b:
            continue
        crosses = seg.get("crosses", False)
        if crosses:
            fence_cross += 1
        color = "#ff3b3b" if crosses else "#8a8f98"
        lw = 3.0 if crosses else 1.6
        ax.plot([a[0], b[0]], [a[-1], b[-1]], color=color, linewidth=lw,
                zorder=2, solid_capstyle="round")

    # --- line-start markers -------------------------------------------------
    for name, p in (line_starts or {}).items():
        if isinstance(p, dict):
            x, z = float(p.get("x", 0)), float(p.get("z", 0))
        else:
            x, z = float(p[0]), float(p[-1])
        ax.plot(x, z, marker="*", color="#ffd54a", markersize=18, zorder=5)
        ax.annotate(f"start {name}", (x, z), color="#ffd54a",
                    fontsize=8, xytext=(6, 6), textcoords="offset points")

    # --- machines -----------------------------------------------------------
    n_in = n_out = n_unresolved = 0
    for m in machines:
        p = m.get("pos", [0, 0, 0])
        x, z = float(p[0]), float(p[-1])
        resolved = m.get("resolved", True)
        inside = m.get("inside", None)
        if not resolved:
            color, n_unresolved = "#c0392b", n_unresolved + 1  # dark red
            marker = "x"
        elif inside is False:
            color, n_out = "#ff5555", n_out + 1
            marker = "o"
        else:
            color, n_in = "#4ade80", n_in + 1
            marker = "o"
        ax.plot(x, z, marker=marker, color=color, markersize=6,
                markeredgecolor="black", markeredgewidth=0.4, zorder=4)

    # --- TL bars ------------------------------------------------------------
    tl_out = 0
    for b in tl_bars:
        p = b.get("pos", [0, 0, 0])
        x, z = float(p[0]), float(p[-1])
        inside = b.get("inside", True)
        color = "#63b3ff" if inside else "#ff8c00"
        if not inside:
            tl_out += 1
        ax.plot(x, z, marker="s", color=color, markersize=4, alpha=0.8, zorder=3)

    # --- doors / gates ------------------------------------------------------
    door_off = 0
    for d in doors:
        c = d.get("center", [0, 0, 0])
        x, z = float(c[0]), float(c[-1])
        on_wall = d.get("on_wall", True)
        is_gate = d.get("type", "door") == "gate"
        color = "#9b59b6" if on_wall else "#ff2d2d"
        if not on_wall:
            door_off += 1
        ax.plot(x, z, marker="D" if is_gate else "P", color=color,
                markersize=12, markeredgecolor="white", markeredgewidth=0.6,
                zorder=6)
        ax.annotate(d.get("label", ""), (x, z), color=color, fontsize=7,
                    xytext=(6, -10), textcoords="offset points")

    # --- cosmetics ----------------------------------------------------------
    ax.set_aspect("equal", adjustable="datalim")
    ax.invert_yaxis()  # scene Z = -RD north -> flipping puts plant-north UP
    ax.grid(True, color="#2a3340", linewidth=0.5, zorder=0)
    ax.set_xlabel("scene X (east +)  [m]", color="#aab")
    ax.set_ylabel("scene Z  [m]  (north up)", color="#aab")
    ax.tick_params(colors="#889")

    passed = sum(1 for c in checks if c.get("pass"))
    total = len(checks)
    verdict = "PASS" if total and passed == total else "FAIL"
    vcolor = "#4ade80" if verdict == "PASS" else "#ff5555"
    title = (f"CeDo world/save regression  —  {verdict}  ({passed}/{total} checks)\n"
             f"machines: {n_in} inside / {n_out} OUTSIDE / {n_unresolved} unresolved   "
             f"TL bars outside: {tl_out}   fence crossings: {fence_cross}   doors off-wall: {door_off}   "
             f"yaw={meta.get('world_yaw_deg','?')}deg  grade_y={meta.get('floor_grade_y','?')}")
    ax.set_title(title, color=vcolor, fontsize=11, fontweight="bold")

    fig.tight_layout()
    fig.savefig(out_path, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"[topdown_render] wrote {out_path}  ({verdict}: {passed}/{total} checks, "
          f"{n_out} machines outside, {n_unresolved} unresolved)")


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: topdown_render.py <positions.json> <out.png>", file=sys.stderr)
        return 2
    src, out = sys.argv[1], sys.argv[2]
    data = json.loads(Path(src).read_text(encoding="utf-8"))
    render(data, out)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
