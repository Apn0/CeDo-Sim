# Extruder motor torque through STOPPING — 2026-09-25

Branch `claude/clever-taussig-f94c91`, on `be319d6` (PR #290, the ramp melt
pressures, which found this defect: `extruder_ramp_pressures_2026-09-25.md` §5
item 3). Every number below was produced on that tree with
`C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe` and
`Extruder3B.tres` (base torque 60 %, `screw_rpm_nominal` 110, `STOP_DECAY_S`
4 s). Guard: `src/tests/test_extruder_stop_torque.tscn` (21 checks, in
`tools/regression/run.sh`).

## 1. The defect

`_tick_stopping` did

    motor_torque_pct = motor_torque_pct * rpm_frac

every tick, with `rpm_frac = screw_rpm / nominal`. It multiplied the previous
tick's already-scaled torque, so the torque followed the product of every rpm
fraction so far. Measured with the old line put back (mutation M1 below), a
stop from a nominal run at 60 %:

| t into STOPPING | rpm / entry rpm | torque, 0.1 s ticks | torque, 0.05 s ticks |
|---|---|---|---|
| 1.2 s | 0.741 | 8.536 % (0.142 of running) | 1.411 % (0.024) |
| 4.0 s | 0.368 | ~0 | ~0 |

`motor_torque_pct` is the number every screen shows as the extruder's load: the
BluPort rail `load_pct` ("belasting") and its `ex1_kw` power proxy, the HMI's
`ex_belasting`, and SCADA. 1.2 s into a stop the BluPort read **9 %**.

## 2. What the plant documents

There is no SWI or screen that gives a coast-down torque. The downsampled
WinCC curves in `src/data/plant/trends/` are medians over ~6-minute buckets
and cannot show a stop. The RAW EREMA Archivspeicher exports they were made from
(`F:/Citizen/Documents/CeDo/Gegevens extruder 3A|3B/`, `docs/plant/trends_overview.md`
§1) can. There, `speed_extruder` (Snelheid hoofdmotor) and `load_extruder`
(Vermogen hoofdmotor, %) are logged in the same cycle, every ~5.03 s.

`tools/audit/fit_stop_load_vs_rpm.py` finds every stop from a steady run (a
0-rpm sample after a run that held its speed for at least two samples) and keeps
the samples caught between the last steady sample and the zero:

| | stops from a steady run | caught nothing | caught 1 | caught 2 | caught 3 |
|---|---|---|---|---|---|
| 3A | 29 | 27 | 1 | 1 | 0 |
| 3B | 54 | 43 | 9 | 1 | 1 |

That gives 17 caught samples. **VERIFIED** (primary record, raw archive):

| line | rpm / entry rpm | load / entry load |
|---|---|---|
| 3B | 22 / 110 = 0.200 | 3.0 / 15.7 = 0.191 |
| 3B | 39 / 120 = 0.325 | 28.0 / 80.0 = 0.350 |
| 3B | 27 / 80 = 0.338 | 28.0 / 73.7 = 0.380 |
| 3B | 40 / 113 = 0.354 | 28.0 / 74.7 = 0.375 |
| 3B | 60 / 122 = 0.492 | 48.0 / 79.3 = 0.605 |
| 3B | 62 / 122 = 0.508 | 46.0 / 79.3 = 0.580 |
| 3A | 60 / 110 = 0.545 | 6.0 / 8.7 = 0.692 |
| 3B | 62 / 100 = 0.620 | 4.0 / 8.0 = 0.500 |
| 3B | 82 / 120 = 0.683 | 7.0 / 10.0 = 0.700 |
| 3A | 87 / 110 = 0.791 | 0.0 / 8.7 = 0.000 |
| 3A | 60 / 75 = 0.800 | 51.0 / 57.3 = 0.890 |
| 3B | 98 / 120 = 0.817 | 9.0 / 10.0 = 0.900 |
| 3B | 74 / 88 = 0.841 | 62.0 / 74.3 = 0.834 |
| 3B | 85 / 100 = 0.850 | 7.0 / 8.0 = 0.875 |
| 3B | 83 / 95 = 0.874 | 10.0 / 11.0 = 0.909 |
| 3B | 108 / 120 = 0.900 | 71.0 / 73.3 = 0.968 |
| 3B | 121 / 122 = 0.992 | 78.0 / 79.3 = 0.983 |

Candidate laws, error in fractions of the entry load:

| law | mean abs error | rms error |
|---|---|---|
| load = entry load x rpm / entry rpm | 0.098 | 0.204 |
| load = entry load (held) | 0.369 | 0.466 |
| load = entry load x (rpm / entry rpm)^2 | 0.237 | 0.273 |

The least-squares slope through the origin is **0.969**. The linear law's rms is
driven by one sample: 3A, 87 rpm at 0 % from an 8.7 % run-empty load. That is
the logger's integer rounding at the bottom of the scale.

What this does NOT settle:
- Whether `load_extruder` is torque or power in the drive. The archive folder
  says "Vermogen" (power) and the tag says load; `trends_overview.md` lists the
  unit as a guess. It does not matter here: the sim field is DISPLAYED as that
  load, and the display now follows the plant's reading.
- Whether the melt cooling during a stop adds load. The heaters drift the model
  0.3 °C/s toward 0.85 x setpoint, and a 5 s cycle cannot resolve that. The law
  above holds the entry load, as the data does.

## 3. The fix

`_transition` records `_stop_entry_torque_pct` and `_stop_entry_rpm` when it
enters STOPPING. That is the entering state's torque and rpm on the stop tick
(RUNNING's or STARTING's own tick runs first). Each STOPPING tick then sets

    motor_torque_pct = _stop_entry_torque_pct x clamp(screw_rpm / _stop_entry_rpm, 0, 1)

The ratio is to the ENTRY rpm, not to nominal. The plant stops from wherever the
operator set the screw (60-125 rpm in the archive). `screw_rpm` decays as
`exp(-t / STOP_DECAY_S)`, so the torque at a given time is the same at any tick
size. `_update_motor_torque` is not called in STOPPING, because it runs the
110 % trip accumulator (mutation M2 shows why). Lumps stay forced to 0 there, as
before.

Measured after the fix, from a nominal run at 60 %:

| t into STOPPING | 0.1 s ticks | 0.05 s ticks |
|---|---|---|
| 1.2 s | 44.449 % (0.741) | 44.449 % |
| 4.0 s | 22.073 % | 22.073 % |
| 8.0 s | 8.120 % | 8.120 % |

1.2 s into the wired `extruder_3b`'s stop, the BluPort rail reads **44 %**.

## 4. The guard and its mutation matrix

`test_extruder_stop_torque`, in three parts:
- Part A drives a bare model: the law on every STOPPING tick, the same stop at
  0.1 s and 0.05 s ticks, and a stop from a 120 % run that must not trip. It
  also covers a second stop pressed mid-ramp, and a stop from an operator
  setpoint of 80 rpm.
- Part B drives the real catalog `extruder_3b` through its SimTick handler,
  with a real LaserFilter and HeadFilter.
- Part B also reads the load off a real `ExtruderBluPortScope` bound to that
  model.

The law checks read the entry off the model on the stop tick, so they do not
hard-code 60 % or the decay constant.

| mutation | result |
|---|---|
| none (this fix) | PASS 21 ok |
| M1 the old `motor_torque_pct * rpm_frac` | 8 red (T2, T3, S1, N2, R1, R2, W1, W2) |
| M2 `_update_motor_torque(delta, _events)` then `*= rpm_frac` | 5 red (T2, N1 trips to FAULT, R1, R2, W1) |
| M3 entry captured only on the first stop | 1 red (R1) |
| M4 ratio to nominal rpm instead of entry rpm | 2 red (R1, R2) |
| M5 entry torque held, no decay | 6 red (T2, T3, N2, R1, R2, W1) |

M5 passes the tick-size check S1. A reading that is the same at both tick sizes
is not yet a correct reading.

Neighbours on the fixed tree, one at a time:
- `test_extruder_ramp_pressures` 21 ok
- `test_extruder_melt_pressures` 53 ok
- `test_die_pressure_bar` 21 ok
- parse sweep 456 ok / 0 fail
- unused-parameter lint: 451 files, 0 unused

`test_extruder_melt_pressures` segfaulted AFTER its PASS line in 2 of 7 runs on
the fix. The pre-fix model, run alternately, also segfaulted in 2 of 7. All 14
runs printed `PASS (53 ok, 0 fail)`. This is the known headless teardown crash
(CLAUDE.md), not this change. `run.sh` keys off the verdict. The full harness
was not run here; the operator runs it after the parallel sessions finish.

## 5. Found while measuring, NOT changed here

1. **The plant's screw stops much faster than the model's.** 70 of 83 stops
   (84 %) went from a steady speed to 0 rpm inside ONE ~5 s logging cycle, and
   none caught more than three samples. The model's STOPPING runs 216 ticks
   (21.6 s, `4 x ln(110 / 0.5)`) from nominal to the 0.5 rpm floor.
   `STOP_DECAY_S` = 4 s is cited to the operator emulator's `*= 0.9` step, not
   to the plant. A faster decay would shorten every coast-down: the torque, the
   melt pressures and the tail-end throughput. That is an operator call. The
   script above prints the counts to rule it on.
2. **26 of the 83 stops started from a load under 25 %** (3A 14 of 29, 3B 12
   of 54). The screw ran empty at its normal or a raised speed before the stop,
   at a load of 7-24 % (leegdraaien, SWI-035). The model has no such phase:
   STOPPING starts from whatever load RUNNING had.
