#!/usr/bin/env python3
"""Labelled schematic of line 1's head, drawn from MEASURED geometry.

Input is the JSON dumped out of a real `_build_full_line("line_1", ...)` run
(docs/plant/line1_head_geometry_2026_09_17.json), so every number here is what
the sim actually builds - nothing is hand-placed or remembered.

WHY IT EXISTS. The operator read an orthographic render of the head as showing
the feeder pointing the wrong way. It was not: what looked like the Westa band
was `shredder_1`'s own 11.4 m built-in discharge conveyor, which overhangs its
5.0 m catalog footprint and dominates the frame. A photograph of that head is
genuinely ambiguous; a labelled drawing is not.

Two panels, because neither alone answers the question that was asked:
  PLAN      - which way the feeder's funnel tapers, and where the 90 deg right
              turn onto the Westa is.
  ELEVATION - the climb, UNFOLDED along the material path. The path turns a
              corner, so plotting against world X or Z would fold one leg on top
              of the other and hide exactly the stretch being checked.

Usage:  python line1_head_schematic.py <head_geometry.json> <out.png>
"""
from __future__ import annotations

import json
import math
import re
import sys
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon as MplPolygon, Rectangle

BG = "#101418"
FG = "#e2e8f0"
C_OPZ = "#ffd54a"
C_WES = "#4ade80"
C_SHR = "#ff7a7a"
C_BELT = "#63b3ff"
C_MAG = "#c08cff"

NUM = re.compile(r"-?\d+\.?\d*(?:e-?\d+)?")


def vec(s: str):
    """Parse Godot's `Vector3(x, y, z)` string form.

    Only the text INSIDE the parentheses is scanned. Matching the whole string
    picks up the `3` in `Vector3` as the first number and silently shifts every
    coordinate by one - which it did, and the drawing came out with the lip at
    "y -156.76".
    """
    inner = s[s.index("(") + 1:s.rindex(")")]
    return [float(v) for v in NUM.findall(inner)]


def draw(d: dict, out: str) -> None:
    opz, wes, shr = d["opz"], d["wes"], d["shr"]
    belt, mag = d["belt"], d["mag"]
    o_tail, o_lip = vec(opz["tail"]), vec(opz["lip"])
    w_tail, w_lip = vec(wes["tail"]), vec(wes["lip"])
    s_pos, s_throat = vec(shr["pos"]), vec(shr["throat"])
    b_pos, m_pos = vec(belt["pos"]), vec(mag["pos"])
    b_size, s_size = vec(belt["size"]), vec(shr["size"])

    fig, (axp, axe) = plt.subplots(
        2, 1, figsize=(15, 11), dpi=125, gridspec_kw={"height_ratios": [1.15, 1]}
    )
    fig.patch.set_facecolor(BG)

    # --- PLAN --------------------------------------------------------------
    axp.set_facecolor(BG)
    half_w = opz["deck_width"] / 2.0
    half_n = opz["funnel_min_width"] / 2.0
    # Funnel walls, stepped along the belt's OWN run direction (tail -> lip).
    sgn = math.copysign(1.0, o_lip[0] - o_tail[0])
    s0 = o_tail[0] + sgn * opz["funnel_start_m"]
    s1 = s0 + sgn * opz["funnel_narrow_m"]
    z0 = o_tail[2]
    for side in (+1, -1):
        axp.plot(
            [o_tail[0], s0, s1, o_lip[0]],
            [z0 + side * half_w, z0 + side * half_w,
             z0 + side * half_n, z0 + side * half_n],
            color=C_OPZ, lw=2.6, solid_capstyle="round", zorder=4,
        )
    axp.add_patch(MplPolygon(
        [(o_tail[0], z0 - half_w), (s0, z0 - half_w), (s1, z0 - half_n),
         (o_lip[0], z0 - half_n), (o_lip[0], z0 + half_n), (s1, z0 + half_n),
         (s0, z0 + half_w), (o_tail[0], z0 + half_w)],
        closed=True, facecolor=C_OPZ, alpha=0.14, edgecolor="none", zorder=3))
    axp.annotate("opzetband_1\nfunnel mouth %.1f m\n(bales in here)" % opz["deck_width"],
                 (o_tail[0], z0), color=C_OPZ, fontsize=9, ha="right", va="center",
                 xytext=(-14, 0), textcoords="offset points")
    axp.annotate("taper %.1f -> %.1f m" % (opz["deck_width"], opz["funnel_min_width"]),
                 ((s0 + s1) / 2.0, z0 - half_w), color=C_OPZ, fontsize=8,
                 ha="center", va="top", xytext=(0, -6), textcoords="offset points")

    axp.plot([w_tail[0], w_lip[0]], [w_tail[2], w_lip[2]],
             color=C_WES, lw=7, solid_capstyle="butt", zorder=5)
    axp.annotate("westa_band_1  (%.2f m)" % abs(w_lip[2] - w_tail[2]),
                 (w_lip[0], (w_tail[2] + w_lip[2]) / 2.0), color=C_WES, fontsize=9,
                 ha="left", va="center", xytext=(12, 0), textcoords="offset points")

    axp.add_patch(Rectangle((s_pos[0] - s_size[0] / 2.0, s_pos[2] - s_size[2] / 2.0),
                            s_size[0], s_size[2], facecolor=C_SHR, alpha=0.22,
                            edgecolor=C_SHR, lw=1.8, zorder=2))
    axp.annotate("shredder_1\nhopper", (s_pos[0], s_pos[2]), color=C_SHR,
                 fontsize=9, ha="center", va="center")

    axp.add_patch(Rectangle((b_pos[0] - b_size[2] / 2.0, b_pos[2] - b_size[0] / 2.0),
                            b_size[2], b_size[0], facecolor=C_BELT, alpha=0.22,
                            edgecolor=C_BELT, lw=1.6, zorder=2))
    axp.annotate("uitvoerband", (b_pos[0], b_pos[2] + b_size[0] / 2.0), color=C_BELT,
                 fontsize=8, ha="center", va="top", xytext=(0, -6),
                 textcoords="offset points")
    axp.plot(m_pos[0], m_pos[2], marker="s", color=C_MAG, ms=9, zorder=6)
    axp.annotate("overband magnet", (m_pos[0], m_pos[2]), color=C_MAG, fontsize=8,
                 ha="left", va="bottom", xytext=(10, 8), textcoords="offset points")

    axp.annotate("", xy=(o_lip[0], z0), xytext=(o_tail[0], z0),
                 arrowprops=dict(arrowstyle="-|>", color=FG, lw=2.2, alpha=0.9))
    axp.annotate("", xy=(w_lip[0], w_lip[2]), xytext=(w_tail[0], w_tail[2]),
                 arrowprops=dict(arrowstyle="-|>", color=FG, lw=2.2, alpha=0.9))
    axp.annotate("90 deg RIGHT", (w_tail[0], w_tail[2]), color=FG, fontsize=9,
                 fontweight="bold", ha="left", va="bottom",
                 xytext=(10, 10), textcoords="offset points")

    axp.set_aspect("equal", adjustable="datalim")
    axp.invert_yaxis()
    axp.set_title("PLAN - feeder funnels TOWARD the Westa, then 90 deg right into the shredder",
                  color=FG, fontsize=11, fontweight="bold")
    axp.set_xlabel("scene X  [m]", color="#aab")
    axp.set_ylabel("scene Z  [m]  (north up)", color="#aab")

    # --- ELEVATION, unfolded along the path --------------------------------
    axe.set_facecolor(BG)
    L1 = abs(o_lip[0] - o_tail[0])
    L2 = math.hypot(w_lip[0] - w_tail[0], w_lip[2] - w_tail[2])
    axe.plot([0, L1], [opz["deck_h"], o_lip[1]], color=C_OPZ, lw=5,
             solid_capstyle="round",
             label="opzetband_1   %.1f m @ %.0f deg" % (L1, opz["incline_deg"]))
    axe.plot([L1, L1 + L2], [w_tail[1], w_lip[1]], color=C_WES, lw=5,
             solid_capstyle="round",
             label="westa_band_1   %.1f m @ %.0f deg" % (L2, wes["incline_deg"]))
    axe.plot([L1 + L2], [s_throat[1]], marker="v", color=C_SHR, ms=15,
             linestyle="none", label="shredder_1 hopper   y %.2f m" % s_throat[1])
    axe.annotate("transfer drop %.2f m" % (o_lip[1] - w_tail[1]),
                 (L1, (o_lip[1] + w_tail[1]) / 2.0), color=FG, fontsize=8,
                 ha="left", va="center", xytext=(10, 0), textcoords="offset points")
    axe.annotate("into the hopper\n(%.2f -> %.2f m)" % (w_lip[1], s_throat[1]),
                 (L1 + L2, w_lip[1]), color=FG, fontsize=8, ha="right", va="bottom",
                 xytext=(-12, 12), textcoords="offset points")
    axe.axhline(0, color="#2a3340", lw=1)
    axe.set_aspect("equal", adjustable="datalim")
    axe.set_title("ELEVATION - unfolded along the material path (the 90 deg corner is at %.1f m)" % L1,
                  color=FG, fontsize=11, fontweight="bold")
    axe.set_xlabel("distance along the path  [m]", color="#aab")
    axe.set_ylabel("height  [m]", color="#aab")
    leg = axe.legend(facecolor=BG, edgecolor="#2a3340", labelcolor=FG, fontsize=9)
    leg.get_frame().set_alpha(0.9)

    for ax in (axp, axe):
        ax.grid(True, color="#2a3340", lw=0.4)
        ax.tick_params(colors="#889")
        for sp in ax.spines.values():
            sp.set_color("#2a3340")

    fig.tight_layout()
    fig.savefig(out, facecolor=BG)
    plt.close(fig)
    print("[head] wrote %s" % out)
    print("  opzetband  %.2f m run, lip at y %.2f" % (L1, o_lip[1]))
    print("  westa      %.2f m run, %.0f deg, lip at y %.2f"
          % (L2, wes["incline_deg"], w_lip[1]))
    print("  hopper     y %.2f" % s_throat[1])


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("usage: line1_head_schematic.py <head_geometry.json> <out.png>",
              file=sys.stderr)
        raise SystemExit(2)
    draw(json.loads(Path(sys.argv[1]).read_text(encoding="utf-8")), sys.argv[2])
