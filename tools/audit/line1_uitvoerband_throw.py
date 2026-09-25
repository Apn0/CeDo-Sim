#!/usr/bin/env python3
"""Where the material from line 1's uitvoerband lands on the belt below it.

Operator, 2026-09-25: the receiving belt's centre, along the uitvoerband's
direction, is "the center of the spread" of the material leaving the
uitvoerband: "what is the speed of the conveyor, what is the drop it will be
making … using standard deviation, what is the minimum distance and the maximum
distance". This is that calculation, kept as a tool so the number in LINE_1_SEQ
can be re-derived when any input changes.

Model: every particle leaves the discharge end at the belt speed along the
belt's last direction, and falls freely onto the receiving deck. Without air
drag the particle's MASS cancels out of the throw, so it does not appear. Light
film flakes would in reality be slowed by the air and land a little SHORTER;
the sim models no drag, so the mean below is the drag-free throw.

The spread comes from the particles not all moving at the belt speed (slip on
the belt, tumbling at the drum). SIGMA_V_FRAC, the standard deviation of that
speed as a fraction of the belt speed, is an ASSUMPTION, not a plant figure:
change it and re-run. The belt centre only depends on the mean.

Usage:  python line1_uitvoerband_throw.py [belt_speed_mps] [drop_m] [angle_deg] [sigma_v_frac]
"""
from __future__ import annotations
import math
import sys

G = 9.81


def throw(v: float, drop: float, angle_deg: float) -> float:
    """Horizontal distance past the discharge point at which a particle leaving
    at speed v, angle_deg above horizontal, has fallen `drop` metres."""
    a = math.radians(angle_deg)
    vx, vy = v * math.cos(a), v * math.sin(a)
    t = (vy + math.sqrt(vy * vy + 2.0 * G * drop)) / G
    return vx * t


def main() -> None:
    v = float(sys.argv[1]) if len(sys.argv) > 1 else 1.0        # PlaceableCatalog._BELT_CARRY_SPEED
    drop = float(sys.argv[2]) if len(sys.argv) > 2 else 0.962    # uitvoerband lip - receiving deck
    ang = float(sys.argv[3]) if len(sys.argv) > 3 else 20.0      # the climb it leaves
    sig = float(sys.argv[4]) if len(sys.argv) > 4 else 0.20      # ASSUMED speed spread
    mean = throw(v, drop, ang)
    lo2, lo1 = throw(v * (1 - 2 * sig), drop, ang), throw(v * (1 - sig), drop, ang)
    hi1, hi2 = throw(v * (1 + sig), drop, ang), throw(v * (1 + 2 * sig), drop, ang)
    print("belt %.2f m/s, drop %.3f m, leaving at %.0f deg, speed sigma %.0f%%" % (v, drop, ang, sig * 100))
    print("  mean throw           %.3f m past the discharge end" % mean)
    print("  +-1 sigma            %.3f .. %.3f m" % (lo1, hi1))
    print("  +-2 sigma (min..max) %.3f .. %.3f m  (spread %.3f m)" % (lo2, hi2, hi2 - lo2))


if __name__ == "__main__":
    main()
