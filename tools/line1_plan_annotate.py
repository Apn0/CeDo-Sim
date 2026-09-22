#!/usr/bin/env python3
"""Annotated plan schematic of line 1, drawn from MEASURED machine positions.

Input is the JSON that src/tests/shot_line1_plan.gd writes beside its PNGs, so
every rectangle here is the machine's real world footprint as the built line
reports it — nothing in this file is hand-placed or remembered.

The orthographic PNG shows what line 1 looks like; this shows what it MEANS:
each leg is coloured and labelled with its heading, and the turn between two
legs is measured from the legs themselves and printed as LEFT/RIGHT + degrees.
That is the claim the 2026-09-16 head correction has to be checked against
("feeder -> 90 right -> Westa -> shredder"), and a photograph cannot settle it.

Scene axes, matching tools/regression/topdown_render.py: X = RD east
(horizontal, +right), Z = -RD north (vertical). The Z axis is flipped so
plant-north points UP, the same way the in-game map overlay draws it.

Usage:
    python line1_plan_annotate.py <plan.json> <out.png>
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Rectangle

# Distinct, colour-blind-safe-ish leg colours. Line 1 builds 8 legs; the list is
# longer so a future leg does not silently wrap onto an existing leg's colour.
LEG_COLOURS = [
    "#4ade80", "#ffd54a", "#63b3ff", "#ff7ac6",
    "#ff9f43", "#9b8cff", "#4fd1c5", "#ff5555",
    "#a0aec0", "#f6e05e",
]


def _heading(dx: float, dz: float) -> str:
    """Quantise a step to a compass label. +X = east, -Z = north (see module doc)."""
    if abs(dx) >= abs(dz):
        return "east (+X)" if dx > 0 else "west (-X)"
    return "south (+Z)" if dz > 0 else "north (-Z)"


def _leg_heading(rot_y_deg: float) -> str:
    """Compass label for a leg whose macro anchor has this rot_y.

    A leg's forward is the macro cursor's local -Z rotated by rot_y
    (BuildMode.gd: `fwd = Vector3(-sin(rot), 0, -cos(rot))`), so rot_y 0 heads
    -Z and a POSITIVE rot_y (a LEFT turn) swings it toward -X.
    """
    r = math.radians(rot_y_deg)
    return _heading(-math.sin(r), -math.cos(r))


def _split_legs(machines: list[dict]):
    """Group machines into legs using the macro's OWN per-leg anchor.

    Each placed node carries macro_anchor {start, rot_y} for the leg it belongs
    to (BuildMode.gd:2429), so a leg break is simply a change of rot_y in build
    order. This is measured, not inferred: differencing consecutive positions
    cannot work here, because line 1 lays several stations as side-by-side PAIRS
    (the walk zigzags) and the laser-filter lump carts are furniture beside leg
    7 rather than a leg of their own.
    """
    legs, start, cur = [], 0, None
    for i, m in enumerate(machines):
        r = m.get("leg_rot_y_deg")
        if r is None:
            continue
        if cur is None:
            cur = r
        elif abs(r - cur) > 1e-3:
            legs.append((start, i - 1, cur))
            start, cur = i, r
    if cur is not None:
        legs.append((start, len(machines) - 1, cur))
    return [(i0, i1, _leg_heading(r), r) for i0, i1, r in legs]


def _turn(prev_rot: float, next_rot: float) -> str:
    """LEFT/RIGHT/STRAIGHT between two legs, from their anchor rot_y.

    turn_deg is POSITIVE = LEFT (CCW seen from above) per LINE_1_SEQ's contract,
    so the signed delta between anchors IS the turn the macro applied.
    """
    d = (next_rot - prev_rot + 180.0) % 360.0 - 180.0
    if abs(d) < 1.0:
        return "straight"
    if abs(abs(d) - 180.0) < 1.0:
        return "REVERSE 180"
    return ("LEFT %.0f" if d > 0 else "RIGHT %.0f") % abs(d)


def render(data: dict, out_path: str) -> None:
    machines = data.get("machines", [])
    if not machines:
        raise SystemExit("no machines in the dump")

    pts = [(float(m["pos"][0]), float(m["pos"][2])) for m in machines]
    legs = _split_legs(machines)

    fig, ax = plt.subplots(figsize=(22, 7), dpi=130)
    fig.patch.set_facecolor("#101418")
    ax.set_facecolor("#101418")

    leg_of = {}
    for li, (i0, i1, _h, _r) in enumerate(legs):
        for i in range(i0, i1 + 1):
            leg_of.setdefault(i, li)

    # --- machine footprints -------------------------------------------------
    for i, m in enumerate(machines):
        col = LEG_COLOURS[leg_of.get(i, 0) % len(LEG_COLOURS)]
        ax_, az_ = float(m["aabb_pos"][0]), float(m["aabb_pos"][2])
        sx, sz = float(m["aabb_size"][0]), float(m["aabb_size"][2])
        ax.add_patch(Rectangle((ax_, az_), sx, sz, facecolor=col, alpha=0.30,
                               edgecolor=col, linewidth=1.0, zorder=3))

    # --- the walk, in build order ------------------------------------------
    xs = [p[0] for p in pts]
    zs = [p[1] for p in pts]
    ax.plot(xs, zs, color="#ffffff", linewidth=1.0, alpha=0.45, zorder=4)
    ax.plot(xs, zs, marker="o", linestyle="none", color="#ffffff",
            markersize=3, zorder=5)

    # --- labels: every machine, alternating above/below so they stay legible -
    for i, m in enumerate(machines):
        x, z = pts[i]
        col = LEG_COLOURS[leg_of.get(i, 0) % len(LEG_COLOURS)]
        ax.annotate(m["id"], (x, z), color=col, fontsize=5.5,
                    rotation=90, ha="center",
                    va="bottom" if i % 2 == 0 else "top",
                    xytext=(0, 7 if i % 2 == 0 else -7),
                    textcoords="offset points", zorder=6)

    # --- leg banners + the measured turn between legs ------------------------
    lines = []
    for li, (i0, i1, h, rot) in enumerate(legs):
        a, b = pts[i0], pts[i1]
        run = math.hypot(b[0] - a[0], b[1] - a[1])
        mx, mz = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
        col = LEG_COLOURS[li % len(LEG_COLOURS)]
        turn = _turn(legs[li - 1][3], rot) if li else "start"
        ax.annotate(f"leg {li + 1}: {h}  {run:.1f} m",
                    (mx, mz), color=col, fontsize=8, fontweight="bold",
                    ha="center", va="center", xytext=(0, -34),
                    textcoords="offset points", zorder=7,
                    bbox=dict(boxstyle="round,pad=0.25", fc="#101418",
                              ec=col, lw=0.8))
        lines.append(f"leg {li + 1}  {turn:<11} {h:<11} {run:6.1f} m  "
                     f"{machines[i0]['id']} -> {machines[i1]['id']}")

    ax.set_aspect("equal", adjustable="datalim")
    ax.invert_yaxis()  # scene Z = -RD north -> flipping puts plant-north UP
    ax.grid(True, color="#2a3340", linewidth=0.4, zorder=0)
    ax.set_xlabel("scene X (east +)  [m]", color="#aab")
    ax.set_ylabel("scene Z  [m]  (north up)", color="#aab")
    ax.tick_params(colors="#889")
    for s in ax.spines.values():
        s.set_color("#2a3340")

    turns = " , ".join(_turn(legs[i - 1][3], legs[i][3]) for i in range(1, len(legs)))
    ax.set_title(f"CeDo line 1 — measured plan  ({len(machines)} machines, "
                 f"{len(legs)} legs)\nturns, head to tail:  {turns}",
                 color="#e2e8f0", fontsize=11, fontweight="bold")

    fig.tight_layout()
    fig.savefig(out_path, facecolor=fig.get_facecolor())
    plt.close(fig)
    print(f"[line1_plan] wrote {out_path}")
    for ln in lines:
        print("  " + ln)


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: line1_plan_annotate.py <plan.json> <out.png>", file=sys.stderr)
        return 2
    render(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sys.argv[2])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
