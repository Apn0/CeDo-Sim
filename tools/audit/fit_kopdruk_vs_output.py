"""Does the plant's die-side pressure follow output? (2026-09-24)

Pairs each kopdruk sample (melt pressure before the kopfilter, MD_vor_SF2)
with the nearest output and main-motor-speed samples from the downsampled
WinCC curves in src/data/plant/trends/, keeps running samples only, and fits
log(kopdruk) against log(output) and log(rpm).

    python tools/audit/fit_kopdruk_vs_output.py

Measured 2026-09-24 (docs/audit/extruder_screw_die_plate_2026-09-24.md §5):
3A 648 pairs, exponent -0.129, R2 0.037; 3B 719 pairs, exponent 0.007,
R2 0.000. Output follows rpm (exponent 0.85 / 1.01, R2 0.78 / 0.92), but
kopdruk does not follow output. Why it is flat (melt-pump pressure control?)
is an open question for the operator.
"""
import bisect
import datetime
import json
import math
import os

TRENDS = os.path.join(os.path.dirname(__file__), "..", "..", "src", "data", "plant", "trends")
KOPDRUK = {"3a": "3a_druk_voor_kopfilter.json", "3b": "3b_smeltdruk_voor_kopfilter.json"}
PAIR_WINDOW_S = 300.0     # output sample must lie within 5 min of the kopdruk sample
RPM_WINDOW_S = 400.0      # rpm curve is sparser (~6 s raw, downsampled)


def load(name):
    with open(os.path.join(TRENDS, name), encoding="utf-8") as f:
        d = json.load(f)
    t = [datetime.datetime.fromisoformat(x).timestamp() for x in d["t_iso"]]
    return t, d["v"]


def nearest(ts, t, window):
    i = bisect.bisect_left(ts, t)
    best = None
    for j in (i - 1, i):
        if 0 <= j < len(ts) and abs(ts[j] - t) <= window:
            if best is None or abs(ts[j] - t) < abs(ts[best] - t):
                best = j
    return best


def fit(x, y):
    mx = sum(x) / len(x)
    my = sum(y) / len(y)
    sxx = sum((a - mx) ** 2 for a in x)
    syy = sum((b - my) ** 2 for b in y)
    sxy = sum((a - mx) * (b - my) for a, b in zip(x, y))
    return sxy / sxx, (sxy * sxy) / (sxx * syy)


for line, kfile in KOPDRUK.items():
    to, vo = load(f"{line}_output.json")
    tk, vk = load(kfile)
    tr, vr = load(f"{line}_snelheid_hoofdmotor.json")
    pairs = []
    for t, k in zip(tk, vk):
        jo = nearest(to, t, PAIR_WINDOW_S)
        jr = nearest(tr, t, RPM_WINDOW_S)
        # running samples only: output > 300 kg/h, kopdruk > 50 bar, rpm > 40
        if jo is not None and jr is not None and vo[jo] > 300 and k > 50 and vr[jr] > 40:
            pairs.append((vo[jo], k, vr[jr]))
    lo = [math.log(p[0]) for p in pairs]
    lk = [math.log(p[1]) for p in pairs]
    lr = [math.log(p[2]) for p in pairs]
    print(f"{line}: {len(pairs)} paired running samples")
    print("  log kopdruk ~ log output: exponent %.3f  R2 %.3f" % fit(lo, lk))
    print("  log kopdruk ~ log rpm:    exponent %.3f  R2 %.3f" % fit(lr, lk))
    print("  log output  ~ log rpm:    exponent %.3f  R2 %.3f" % fit(lr, lo))
    for a, b in ((300, 600), (600, 800), (800, 1000), (1000, 1400)):
        ks = sorted(p[1] for p in pairs if a <= p[0] < b)
        if ks:
            print("    output %4d-%4d kg/h: n=%3d  kopdruk median %.0f bar" % (a, b, len(ks), ks[len(ks) // 2]))
