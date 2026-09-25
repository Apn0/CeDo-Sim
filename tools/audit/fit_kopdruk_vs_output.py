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

2026-09-25 (docs/plant/operator_rulings_2026-09-25.md): the operator called
the flatness operator-specific, perhaps an office test run without head
filters, and chose a power-law die, P ~ Q^0.35, for both extruder models. The
second half of this script prints what that ruling was measured against:
the melt temperature against output, the plant's median rpm at the edges of
the output band (the rpm test_screw_die_plate_bar section D drives), and the
per-shift kopdruk slopes and step drops a head-filter sawtooth would show.
Measured 2026-09-25: melt +10.4 / +22.4 degC per ln-unit of output (3A / 3B,
R2 0.445 / 0.541); plant rpm 60 / 88 / 110 at 595 / 908 / 1082 kg/h (3A) and
60 / 80 / 120 at 534 / 799 / 1263 kg/h (3B); 161 / 129 drops of >= 8 bar
within 15 min over nine days, no per-shift sawtooth.
"""
import bisect
import datetime
import json
import math
import os
import statistics

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


# -- 2026-09-25: what the power-law die ruling was measured against ----------

SUMMARY = os.path.join(TRENDS, "extruder_trends_summary.json")
MELT = "smelt_temperatuur_voor_meltfilter"


def band(line, signal):
    with open(SUMMARY, encoding="utf-8") as f:
        for s in json.load(f)["signals"]:
            if s["line"] == line and s["signal"] == signal:
                return s["operating_band"], s["stats"]["p50"]
    raise KeyError((line, signal))


def fit2(x1, x2, y):
    """Least squares y = b0 + b1 x1 + b2 x2. Returns (b1, b2, R2)."""
    n = len(y)
    m1, m2, my = sum(x1) / n, sum(x2) / n, sum(y) / n
    a = [v - m1 for v in x1]
    b = [v - m2 for v in x2]
    c = [v - my for v in y]
    s11 = sum(v * v for v in a)
    s22 = sum(v * v for v in b)
    s12 = sum(u * v for u, v in zip(a, b))
    s1y = sum(u * v for u, v in zip(a, c))
    s2y = sum(u * v for u, v in zip(b, c))
    det = s11 * s22 - s12 * s12
    b1 = (s22 * s1y - s12 * s2y) / det
    b2 = (s11 * s2y - s12 * s1y) / det
    ssr = sum((cv - b1 * av - b2 * bv) ** 2 for av, bv, cv in zip(a, b, c))
    return b1, b2, 1.0 - ssr / sum(v * v for v in c)


print()
print("-- 2026-09-25: melt temperature, plant rpm per output, head-filter sawtooth --")
for line, kfile in KOPDRUK.items():
    to, vo = load(f"{line}_output.json")
    tk, vk = load(kfile)
    tr, vr = load(f"{line}_snelheid_hoofdmotor.json")
    tm, vm = load(f"{line}_{MELT}.json")
    trip = []
    for t, k in zip(tk, vk):
        jo = nearest(to, t, PAIR_WINDOW_S)
        jr = nearest(tr, t, RPM_WINDOW_S)
        jm = nearest(tm, t, RPM_WINDOW_S)
        if None not in (jo, jr, jm) and vo[jo] > 300 and k > 50 and vr[jr] > 40:
            trip.append((vo[jo], k, vm[jm]))
    lq = [math.log(p[0]) for p in trip]
    lk = [math.log(p[1]) for p in trip]
    mt = [p[2] for p in trip]
    print(f"{line}: {len(trip)} kopdruk/output/melt triples")
    print("  melt T ~ log output: %.1f degC per ln-unit  R2 %.3f" % fit(lq, mt))
    b1, b2, r2 = fit2(lq, mt, lk)
    print("  log kopdruk ~ log output + melt T: output exp %.3f, melt %.4f /degC, R2 %.3f" % (b1, b2, r2))
    # The plant's rpm at an output: each output sample paired with the nearest
    # rpm sample, running pairs only, median within +-10 % of the output.
    # test_screw_die_plate_bar._plant_rpm_at() is the same computation.
    pairs = []
    for t, q in zip(to, vo):
        j = nearest(tr, t, RPM_WINDOW_S)
        if j is not None and q > 300 and vr[j] > 40:
            pairs.append((q, vr[j]))
    ob, op50 = band(line, "Output")
    for q in (ob["low"], op50, ob["high"]):
        near = [p[1] for p in pairs if abs(p[0] - q) <= 0.1 * q]
        print("    plant rpm at %4.0f kg/h: median %.0f (n=%d)" % (q, statistics.median(near), len(near)))
    # A loading pack changed once a shift would rise through the shift and drop
    # at the change. The curves are ~6-min bucket medians.
    run = [(datetime.datetime.fromtimestamp(t), v) for t, v in zip(tk, vk) if v > 50]
    drops = sum(1 for (a, va), (b, vb) in zip(run, run[1:])
                if (b - a).total_seconds() <= 900 and va - vb >= 8)
    shifts = {}
    for ti, v in run:
        h = ti.hour
        code = "D" if 6 <= h < 14 else ("L" if 14 <= h < 22 else "N")
        day = (ti - datetime.timedelta(hours=6)).date() if code == "N" else ti.date()
        shifts.setdefault((day, code), []).append((ti, v))
    slopes = []
    for rows in shifts.values():
        if len(rows) > 3:
            t0 = rows[0][0]
            slopes.append(fit([(x[0] - t0).total_seconds() / 3600 for x in rows], [x[1] for x in rows])[0])
    slopes.sort()
    print("    %d drops >= 8 bar within 15 min; %d shift slopes, median %+.2f bar/h (p10 %+.2f, p90 %+.2f)"
          % (drops, len(slopes), statistics.median(slopes), slopes[len(slopes) // 10], slopes[len(slopes) * 9 // 10]))
