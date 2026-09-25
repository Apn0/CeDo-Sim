# Extruder melt pressures through STARTING and STOPPING — 2026-09-25

Branch `claude/elegant-liskov-dd1577`, on `main` `64921ff`. Every number below
was produced on that tree with
`C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe`,
`Extruder3B.tres` (die plate nominal 140 bar, MP>MF nominal 25 bar,
`START_RAMP_S` 4 s, `STOP_DECAY_S` 4 s). Guard: `src/tests/test_extruder_ramp_pressures.tscn`
(21 checks, in `tools/regression/run.sh`).

## 1. The defect

`ExtruderModel._scale_melt_pressures(rpm_frac)` did

    mp_after_laserfilter_bar *= rpm_frac
    die_plate_bar *= rpm_frac

and `_tick_starting` / `_tick_stopping` called it every tick. It multiplied the
PREVIOUS tick's already-scaled pressures, so they followed the product of every
rpm fraction so far, not the rpm.

Measured, a stop from a nominal run (die plate 140.00 bar):

| t into STOPPING | rpm / nominal | flow law | die plate, 0.1 s ticks | die plate, 0.05 s ticks |
|---|---|---|---|---|
| 0.5 s | 0.882 | 0.886 | 96.22 bar (0.687) | 70.40 bar (0.503) |
| 1.2 s | 0.741 | 0.747 | 19.92 bar (0.142) | 3.29 bar (0.024) |
| 2.0 s | 0.607 | 0.615 | 0.73 bar (0.005) | 0.00 |
| 4.0 s | 0.368 | 0.379 | 0.00 | 0.00 |

The tick size set the reading. MP>MF fell by the same fractions.

A start (melt at setpoint, from OFF): OFF, PREHEAT and IDLE park the pressures
at 0, and `0 x rpm_frac` is 0. **Both pressures read 0.00 bar on all 39 STARTING
ticks**, while the flow climbed to q 0.968 of nominal. `ExtruderMachine`
forwards MP>MF to the LaserFilter in STARTING and STOPPING
(`_forward_melt_pressures`, the "producing" gate), so the 318-bar trip input
carried the screen's dMP with no melt-set pressure under it.

## 2. The fix

`_scale_melt_pressures` is gone. `_set_melt_pressures_from_flow()` computes both
pressures from the current `throughput_kg_h / nominal_kg_per_h` and
`melt_viscosity_factor`, the law `_step_degassing` already applied in RUNNING and
VACUUM_ALARM. All four states that move melt now call it. The throughput in
STARTING (`lerp(idle, nominal, rpm_frac)`, times the pelletiser multiplier) and in
STOPPING (`lerp(0, nominal, rpm_frac)`) is unchanged.

Measured after the fix, same stop:

| t into STOPPING | die plate, 0.1 s ticks | die plate, 0.05 s ticks | flow law x melt |
|---|---|---|---|
| 0.5 s | 124.00 bar (0.886) | 124.00 bar | 0.886 |
| 1.2 s | 104.63 bar (0.747) | 104.63 bar | 0.747 |
| 4.0 s | 53.01 bar (0.379) | 53.01 bar | 0.379 |
| 12.0 s | 7.58 bar (0.054) | 7.58 bar | 0.054 |

The start: 58.6 bar at t 0.5 s (q 0.419), 135.5 bar on the last STARTING tick
(q 0.968). The wired catalog `extruder_3b` feeds its LaserFilter 24.2 bar MP>MF
on that tick, where it fed 0 before.

**The die law is the one the model carries.** The fix does not choose a law.
When the power-law die lands (`DIE_FLOW_INDEX`, operator ruling 2026-09-25,
uncommitted in worktree `unruffled-keller-219387` when this was written), the
helper's one call becomes `_set_melt_pressures(throughput_norm, melt_viscosity_factor)`.
It must NOT become `_set_melt_pressures(throughput_norm * melt_viscosity_factor)`,
which computes `pow(q * m, n)` instead of `pow(q, n) * m`. That session's first
version gave `melt_factor` a default of 1.0, so a one-argument call parsed and
went quietly wrong. It has since dropped the default (read in its worktree,
2026-09-25: `func _set_melt_pressures(throughput_norm: float, melt_factor: float)`,
the zero calls are `(0.0, 1.0)`). A surviving one-argument call is now a parse
error that the parse sweep gates on. This suite's mutation M3b (below) catches
the default-argument form as well.

## 3. The guard and its mutation matrix

`test_extruder_ramp_pressures` reads `DIE_FLOW_INDEX` from the script's
constants when it exists (1.0 otherwise), so it holds under either die law.
Part A drives a bare model. Part B drives the real catalog `extruder_3b`
(`build_node` → `MachineBrains`) with a real LaserFilter and HeadFilter, as
`test_extruder_melt_pressures` does.

| mutation | result |
|---|---|
| none (this fix) | PASS 21 ok |
| M1 the old `_scale_melt_pressures` restored | 11 red (S1, S2, S5, U1-U6, W1, W2) |
| M2 STARTING and STOPPING hold the last value | 7 red (S1, U1-U5, W1) |
| M3a the power-law die, merged correctly (two-argument call) | PASS 21 ok, the suite reads n 0.350 |
| M3b the power-law die with the melt folded into the flow | 3 red (S1, U1, U5) |

Neighbouring suites on the fixed tree, one at a time: `test_extruder_melt_pressures`
53 ok, `test_die_pressure_bar` 21 ok, `test_screw_die_plate_bar` 36 ok,
`test_hmi_fault_rearm` 32 ok, `test_hmi_fault_per_line` 26 ok,
`test_vacuum_pot_minigame` 35 ok, `test_extruder_screw` 13 ok,
`test_cutter_compactor` PASS. Parse sweep 455 ok / 0 fail. Not run here:
`test_extruder_brain_wired`, which backs up and restores the operator's real
`user://world_layout.json` while other sessions share that `app_userdata`.
The full harness was not run either.

## 4. One number moved: the preheat-ready start's peak

`test_extruder_melt_pressures`' last check starts a FRESH model at the
preheat-ready melt (196.25 °C, 18.75 °C under the 215 °C setpoint) and asserts
no trip. It still passes, but its MP<MF peak went from **267.9 to 283.7 bar**.
That is 34 bar under the 318 trip and 3.7 bar over the operator's 280-bar safe
maximum. Where it happens, measured:

| | tick | q | MP>MF | dMP | MP<MF |
|---|---|---|---|---|---|
| before | first RUNNING tick | 0.053 | 1.9 | 266.0 | 267.9 |
| after | last STARTING tick | 0.968 | 34.6 | 249.1 | 283.7 |

In both cases the peak comes from the STARTING flow. The LaserFilter's dMP
integrates the previous tick's feed, so before the fix it reached 266 bar one
tick after STARTING, while the MP>MF that belongs with that flow read 0.

## 5. Found while measuring, NOT changed here

1. **A warm restart at the preheat-ready melt trips 318, on the old code and
   the new.** A model that has run before (runtime_s 296 s, past
   `startup_ramp_s` 180 s) re-enters RUNNING at nominal flow. With the melt
   17.5 °C cold, MP<MF climbs to 317.1 bar (old) / 317.6 bar (new) within 0.5 s
   of RUNNING, and the line goes EMERGENCY_STOP about a second in. The
   preheat-ready threshold is derived from TORQUE headroom only.
   `test_extruder_melt_pressures` cannot see this, because it only starts a
   fresh model (item 2 hides it). Whether the green button should also wait for
   pressure headroom is an operator call.
   **Resolved the same day by operator rulings** (a start ramps to the setpoint
   the operator left, 60 is the floor and a new extruder's setpoint, the green
   button also waits until the screw passes no lumps, a per-line rpm control):
   `extruder_warm_restart_2026-09-25.md`, guard `test_extruder_start_rpm`.
2. **A model's first start re-ramps from idle in RUNNING.** STARTING ends at
   q 0.968. On the next tick RUNNING's `lerp(idle_kg_per_h, nominal, runtime_s /
   startup_ramp_s)` puts it at q 0.053, and the screw slows from 0.966 toward
   idle rpm. Later starts (runtime_s past 180 s) do not. The suite records this
   as an `info` line and gates the warm-restart handover instead (3.2 % step).
   **Removed the same day** with item 1: every start now ramps to the setpoint
   and RUNNING holds it, so a first start and a warm one run identically.
3. **`motor_torque_pct *= rpm_frac` in `_tick_stopping` compounds the same
   way.** Measured from a 60 % running torque: 0.142 of it 1.2 s into a stop
   with 0.1 s ticks, 0.024 with 0.05 s ticks, 0 by 4 s. It needs a coast-down
   torque law. No document gives one.
   **Fixed the same day, on top of this branch** (`test_extruder_stop_torque`).
   No SWI gives the law, but the plant's own raw 3A/3B archive does: load and
   speed are logged in the same ~5 s cycle, and the 17 samples caught mid-stop
   read load / entry load = 0.969 x rpm / entry rpm.
   `extruder_stop_torque_2026-09-25.md`.
4. **`test_hmi_fault_rearm` and `test_hmi_fault_per_line` are in no `run.sh`
   loop on `main`.** `00646e6` and `04eaa77` wired them; both commits are
   ancestors of `64921ff`, whose `for t in` lines no longer name them. A merge
   dropped them. Both are green when run by hand (above).
