#!/usr/bin/env python3
"""Census the colour palette across the exported plant HMI screens.

WHY
---
src/scenes/hud/scopes/HmiScreenBase.gd holds ONE palette and asserts in its
header that the 34 exported screens share it.  That claim has to be checked
rather than believed: if a screen introduces a hex the base does not carry,
porting it would silently render the wrong colour, and nobody would notice
because "it looks about right" is not a test.

SCOPE — READ THIS BEFORE WIDENING IT
------------------------------------
Only the L&P/Siemens WASLIJN 3C family is in scope, because that is the family
HmiScreenBase serves.  The export also contains BRITAS, EREMA, BluPort, MAS DRD,
COAD, WEIMA and Sorteerlijn screens: those are OTHER VENDORS' HMI systems with
their own house styles, and a census over all 34 screens finds 269 distinct
hexes — a number that says nothing about whether the 3C chrome is consistent.
Measured 2026-07-29: across all 34 screens 269 hexes, across the 3C family far
fewer.  Run with --all to see the wide number for yourself.

WHAT IT DOES
------------
Extracts every #rrggbb literal from the in-scope screens, groups by hex, and
reports which hexes the base does NOT declare.  Exit 1 if an in-scope screen
uses a colour the base has no constant for, so tools/regression/run.sh can gate
on it.

Usage:  python tools/hmi/palette_census.py [--verbose] [--all]
"""

from __future__ import annotations

import re
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
SCREEN_DIR = REPO / "docs" / "plant" / "hmi_screens_2026-07-26"
BASE_GD = REPO / "src" / "scenes" / "hud" / "scopes" / "HmiScreenBase.gd"

# Both spellings, because the export mixes them freely: `background:#fff` and
# `border:1px solid #aaa` sit beside `background:#c8cdd6`.  Matching only the
# 6-digit form made the first run of this tool report that #ffffff/#111111/
# #aaaaaa "match no screen" while all three are on every screen in the family.
HEX_RE = re.compile(r"#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})\b")
BASE_COLOR_RE = re.compile(r'Color\("#([0-9a-fA-F]{6})"\)')


def norm(hexval: str) -> str:
    """Expand #rgb shorthand to #rrggbb so the two spellings compare equal."""
    h = hexval.lower()
    return "".join(c * 2 for c in h) if len(h) == 3 else h

# The family HmiScreenBase serves: the L&P/Siemens per-unit and overview screens
# for wash line 3C.  Other vendors' screens are deliberately out of scope.
IN_SCOPE_PREFIX = "Waslijn 3C "

# What separates CHROME from CONTENT: chrome is shared, content is not.  A hex
# on a single screen is that screen's own drawing — the machine SVG hand-drawn
# into L3C.14 Rechts, the trace colours of the Stroom Trend plot — and belongs
# to the screen, not to the base.  A hex on a large minority of the family is
# structural, and the base must declare it or every port renders it wrong.
#
# Set to a THIRD of the family rather than a half: the niveau-panel ground
# #f0f2ee is shared by exactly the two silo screens (L3C.1, L3C.18) out of 16
# and is genuinely content, while every real chrome hex measured here lands on
# 12+ screens.  There is a wide empty gap between those two populations, so the
# exact threshold inside it does not matter — but it must not be so low that
# two-screen content trips it.
CHROME_MIN_SCREENS_FRAC = 1.0 / 3.0

# Hexes that legitimately appear in the export but are NOT screen chrome.
# Every entry needs a reason; an unexplained exemption is how a real gap hides.
IGNORED = {
    "0a0a0a": "the <helmet> page backdrop behind the 1280x800 canvas - the "
              "browser preview's letterbox, not part of the WinCC page",
    "4aa3e0": "<helmet> anchor colour for the export's own index links",
    "7cc0f0": "<helmet> anchor :hover colour, same",
    "178382": "the SIEMENS/SIMATIC HMI strip - physical panel bezel silkscreen, "
              "not part of the WinCC page, deliberately not drawn (see the note "
              "in WashingScope._build_ui)",
    "3a4a6a": "1px border of the nav home key; the base draws every nav key "
              "border with C_NAV_EDGE #9aa0aa. Known 1px infidelity, recorded "
              "rather than hidden",
    "b89a20": "1px border of the nav alarm key; same C_NAV_EDGE simplification",
}

# Base constants that intentionally appear on NO real screen, because they are
# sim-side inventions rather than ports.  Without this the "matches no screen"
# note cries wolf every run, and a note that always fires is a note nobody reads.
SIM_SIDE = {
    "8a929c": "C_UNAVAIL - the grey an UNBOUND field renders in. No real screen "
              "has this state: the panel always has a value from the PLC. It "
              "exists so the sim can say 'I do not know' instead of inventing a "
              "plausible number",
    "20242a": "C_NAV_FG - font colour for the disabled nav keys. The export "
              "leaves nav key text at the browser default, which is not a hex "
              "we can read out of it",
}


def main() -> int:
    verbose = "--verbose" in sys.argv
    wide = "--all" in sys.argv

    if not SCREEN_DIR.is_dir():
        print(f"FAIL  : screen dir missing: {SCREEN_DIR}")
        return 1
    if not BASE_GD.is_file():
        print(f"FAIL  : base script missing: {BASE_GD}")
        return 1

    declared = set(BASE_COLOR_RE.findall(BASE_GD.read_text(encoding="utf-8")))
    declared = {h.lower() for h in declared}

    all_screens = sorted(SCREEN_DIR.glob("*.html"))
    if not all_screens:
        print(f"FAIL  : no screens found in {SCREEN_DIR}")
        return 1
    screens = all_screens if wide else [
        p for p in all_screens if p.name.startswith(IN_SCOPE_PREFIX)]
    if not screens:
        print(f"FAIL  : no screens matched scope {IN_SCOPE_PREFIX!r}")
        return 1

    users: dict[str, set[str]] = defaultdict(set)
    for path in screens:
        text = path.read_text(encoding="utf-8", errors="replace")
        for hexval in HEX_RE.findall(text):
            users[norm(hexval)].add(path.name)

    threshold = max(2, int(round(len(screens) * CHROME_MIN_SCREENS_FRAC)))
    undeclared = {
        h: s for h, s in users.items()
        if h not in declared and h not in IGNORED and len(s) >= threshold
    }
    content = {
        h: s for h, s in users.items()
        if h not in declared and h not in IGNORED and len(s) < threshold
    }

    print(f"scope          : {'ALL vendors' if wide else IN_SCOPE_PREFIX.strip()}")
    print(f"screens        : {len(screens)} of {len(all_screens)}")
    print(f"distinct hexes : {len(users)}")
    print(f"declared in base: {len(declared)}")
    print(f"ignored (cited): {len(IGNORED)}")

    if verbose:
        for hexval in sorted(users, key=lambda h: -len(users[h])):
            mark = "ok " if hexval in declared else ("ign" if hexval in IGNORED else "NEW")
            print(f"  {mark} #{hexval}  used by {len(users[hexval]):2d} screen(s)")

    print(f"chrome threshold: >= {threshold} of {len(screens)} screens")
    print(f"per-screen content (not chrome, not a failure): {len(content)} hex(es)")

    if undeclared:
        print(f"FAIL  : {len(undeclared)} SHARED hex(es) used by >= {threshold} "
              f"screens but not declared in HmiScreenBase.gd —")
        for hexval in sorted(undeclared, key=lambda h: -len(undeclared[h])):
            who = sorted(undeclared[hexval])
            shown = ", ".join(who[:4]) + (f", +{len(who) - 4} more" if len(who) > 4 else "")
            print(f"        #{hexval}  ({len(who)} screen(s)): {shown}")
        return 1

    # Guard against the mirror failure: a base palette full of constants that
    # NO screen actually uses is drift in the other direction.
    unused = sorted(declared - set(users) - set(SIM_SIDE))
    if unused:
        print(f"note  : {len(unused)} base constant(s) match no screen: "
              + ", ".join("#" + h for h in unused))

    shared = sum(1 for h, s in users.items()
                 if len(s) >= threshold and h not in IGNORED)
    print(f"Result: PASS ({shared} shared chrome hexes, all declared)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
