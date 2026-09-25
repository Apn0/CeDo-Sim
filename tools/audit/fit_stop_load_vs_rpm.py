"""What does the main-motor load do while the extruder screw stops? (2026-09-25)

The downsampled curves in src/data/plant/trends/ are ~6-minute medians and
cannot show a stop. This reads the RAW EREMA Archivspeicher exports the curves
were made from (docs/plant/trends_overview.md §1), where speed_extruder and
load_extruder are logged together every ~5 s, finds every stop of the main
screw, and compares the load to the speed on the samples a stop was caught in
mid-way.

    python tools/audit/fit_stop_load_vs_rpm.py [raw root]

raw root defaults to F:/Citizen/Documents/CeDo (the operator's machine).

A stop is a 0-rpm sample whose predecessor is above MIN_RUN_RPM. Its ENTRY is
the last sample of the steady run before the speed starts falling, and it must
repeat its predecessor within STEADY_TOL_RPM (a start that is aborted is not a
steady run and is skipped). A CAUGHT sample lies strictly between the entry
and the zero. For each one: rpm / entry rpm against load / entry load.

Measured 2026-09-25 (docs/audit/extruder_stop_torque_2026-09-25.md): 83 stops
from a steady run (3A 29, 3B 54), 70 of them with no sample caught mid-stop,
17 caught samples. load / entry load = 0.969 x rpm / entry rpm (least squares
through the origin); mean abs error 0.098 for load = entry x rpm ratio, 0.369
for a held load, 0.237 for the ratio squared. 26 stops started from a load
under 25 % (run empty first).
"""
import bisect
import csv
import glob
import math
import os
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else "F:/Citizen/Documents/CeDo"
LINES = {"3A": "Gegevens extruder 3A", "3B": "Gegevens extruder 3B"}
MIN_RUN_RPM = 20.0
STEADY_TOL_RPM = 2.0
PAIR_TOL_S = 1.0          # a load sample must share the speed sample's cycle
RUN_EMPTY_LOAD_PCT = 25.0  # a stop from below this load was run empty first


def load_signal(line, folder):
    rows = []
    for f in sorted(glob.glob(os.path.join(ROOT, LINES[line], folder, "*.csv"))):
        with open(f, newline="", encoding="latin-1") as fh:
            txt = fh.read()
        delim = ";" if '";"' in txt else ","
        for r in csv.reader(txt.splitlines(), delimiter=delim):
            if len(r) < 5 or r[0] == "VarName" or r[3].strip() != "1":
                continue    # header, or Validity != 1 ($RT_OFF$ markers)
            try:
                v = float(r[2].replace(",", "."))
                t = float(r[4].replace(",", ".")) / 1e6 * 86400.0   # Excel serial -> s
            except ValueError:
                continue
            rows.append((t, v))
    rows.sort()
    out = []
    for t, v in rows:
        if out and abs(out[-1][0] - t) < 1e-3:
            continue
        out.append((t, v))
    return out


def main():
    caught = []          # (line, rpm_frac, load_frac, rpm, load, entry_rpm, entry_load)
    for line in LINES:
        spd = load_signal(line, "Snelheid hoofdmotor")
        ld = load_signal(line, "Vermogen hoofdmotor")
        lt = [t for t, _ in ld]

        def load_at(t):
            i = bisect.bisect_left(lt, t)
            best = None
            for j in (i - 1, i):
                if 0 <= j < len(ld) and (best is None or abs(ld[j][0] - t) < abs(ld[best][0] - t)):
                    best = j
            if best is None or abs(ld[best][0] - t) > PAIR_TOL_S:
                return None
            return ld[best][1]

        stops = 0
        low_entry = 0
        by_caught = {}
        for k in range(1, len(spd)):
            if not (spd[k][1] <= 0.5 < MIN_RUN_RPM < spd[k - 1][1]):
                continue
            if spd[k][0] - spd[k - 1][0] > 30.0:
                continue            # a logger gap, not a stop
            j = k - 1
            while j - 1 >= 0 and spd[j - 1][1] > spd[j][1] and spd[j][0] - spd[j - 1][0] < 30.0:
                j -= 1
            if j < 2 or abs(spd[j - 1][1] - spd[j][1]) > STEADY_TOL_RPM:
                continue            # no steady run before the stop
            e_rpm = spd[j][1]
            e_loads = [load_at(spd[i][0]) for i in (j - 2, j - 1, j)]
            if any(x is None for x in e_loads):
                continue
            e_load = sum(e_loads) / 3.0
            stops += 1
            if e_load < RUN_EMPTY_LOAD_PCT:
                low_entry += 1
            n = k - 1 - j
            by_caught[n] = by_caught.get(n, 0) + 1
            for i in range(j + 1, k):
                lv = load_at(spd[i][0])
                if lv is None or e_load < 1.0:
                    continue
                caught.append((line, spd[i][1] / e_rpm, lv / e_load, spd[i][1], lv, e_rpm, e_load))
        print(f"{line}: {len(spd)} speed / {len(ld)} load samples, {stops} stops from a steady run; "
              f"caught samples per stop {dict(sorted(by_caught.items()))}; "
              f"{low_entry} stopped from a load under {RUN_EMPTY_LOAD_PCT:.0f} % (run empty)")

    print(f"\n{len(caught)} caught samples (rpm / entry rpm, load / entry load):")
    for c in sorted(caught, key=lambda c: c[1]):
        print(f"  {c[0]}  rpm {c[3]:5.1f}/{c[5]:5.1f} = {c[1]:.3f}   load {c[4]:4.1f}/{c[6]:4.1f} = {c[2]:.3f}")
    if not caught:
        return
    # Candidate laws for load / entry load as a function of r = rpm / entry rpm.
    laws = {
        "load = entry load x r        ": lambda r: r,
        "load = entry load (held)     ": lambda r: 1.0,
        "load = entry load x r^2      ": lambda r: r * r,
    }
    print("\nlaw                             mean |err|   rms err   (in fractions of the entry load)")
    for name, f in laws.items():
        errs = [c[2] - f(c[1]) for c in caught]
        mae = sum(abs(e) for e in errs) / len(errs)
        rms = math.sqrt(sum(e * e for e in errs) / len(errs))
        print(f"  {name}    {mae:.3f}      {rms:.3f}")
    sxy = sum(c[1] * c[2] for c in caught)
    sxx = sum(c[1] * c[1] for c in caught)
    print(f"\nleast-squares slope through the origin: load/entry = {sxy / sxx:.3f} x rpm/entry")


if __name__ == "__main__":
    main()
