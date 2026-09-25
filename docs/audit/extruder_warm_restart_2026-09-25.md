# A warm extruder restart tripped 318 bar — 2026-09-25

Branch `claude/brave-turing-7b2143`. It started on `be319d6` (#290) and merged
`origin/main` `d44f06f`. Engine
`C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe`.
Every number below was produced with `src/tests/probe_warm_restart_pressure.tscn`
or the suites named. The operator's answers are in
`docs/plant/operator_rulings_2026-09-25.md`.

## 1. The finding, reproduced

It was carried in from `extruder_ramp_pressures_2026-09-25.md` §5 items 1-2.
Measured on `main` `64921ff` and on #290. The rig is a real catalog
`extruder_3b` (`build_node` → `MachineBrains`) with a real LaserFilter and
HeadFilter, stepped at 0.1 s. "Warm" means 300 s at nominal first, then a stop
to OFF (runtime_s 296, past `startup_ramp_s` 180). The restart is at the green
button's temperature, 196.25 °C (18.75 °C cold).

| case | main 64921ff | + #290 |
|---|---|---|
| A. FRESH model (the only case the suite ran) | peak 267.9 bar, no trip | 283.7, no trip |
| B. WARM model | **trip 4.6 s** after green, 317.1 | **trip 4.3 s**, 317.6 |
| C. B with the screen's cake wiped | trip, 316.7 | trip, 317.2 |
| D. gameplay: stop, OFF until under green (24.6 s), start → PREHEAT, green | trip 4.8 s | trip 4.5 s |
| E. D after a full cool-down and 27 min of PREHEAT | trip 4.8 s | trip 4.4 s |
| F. warm, melt 7 / 10 / 12 °C cold | 278 / 301 / 317, no trip | 279 / 303 / **trip** |
| G. warm, with `runtime_s` zeroed (first-start re-ramp) | 260, no trip | 272, no trip |
| H. 3A, as B | identical to 3B | identical to 3B |

The mechanism has two parts:

- **The warm restart ran on at nominal flow.** RUNNING's throughput was
  `lerp(idle, nominal, runtime_s / startup_ramp_s)` on the model's LIFETIME
  runtime, so only a model's first start re-ramped.
- **At full flow the cold melt did the rest.** The flow went through the
  screen's clean resistance at viscosity ×1.43 (MP>MF 35.7 + dMP ~282 bar).

The cake is not the cause: wiping it (C) changes nothing.

## 2. Two more defects the operator's answers exposed

- **No line could have its rpm set except one.** The only rpm control in the
  game was the web HMI's `extr_rpm` field. `HmiWebOverlay._find_extruder_model()`
  returned the FIRST member of the `extruder_machine` group, on the one
  all-lines extruder panel. The touchscreen fallback had zone sliders and no
  rpm field. Found by reading the code; `test_extruder_start_rpm` C2/C3 now
  measure the fix. So the operator's remedy after a 318 trip (drop to 60,
  restart) was impossible on every line but one.
- **The green button accepted a melt that passes lumps.** `_preheat_ready_temp()`
  was derived from the 110 % torque trip only (25 % margin, 97.5 % torque).
  Lumps pass above 95 % torque. With the start at 60 rpm, a warm restart at the
  old green still tripped, this time through lumps (probe section J):

| green at | torque at RUNNING | lumps | MP<MF peak | result |
|---|---|---|---|---|
| 199.0 °C | 90.3 % | 0 | 175 bar | ok |
| 196.75 °C | 94.8 % | 0 | 182 bar | ok |
| 196.5 °C | 95.3 % | 1.5 g/s | 289 bar | over 280, no trip |
| 196.25 °C (old green) | 95.7 % | 3.4 g/s | 350 | **trip 3.3 s** |

## 3. What was built (operator rulings, rulings file §1-§5)

- **A start ramps to the operator's setpoint, and a stop does not change it.**
  `_tick_starting` moves the screw toward `_setpoint_rpm()` at
  `screw_rpm_min / START_RAMP_S` = 20 rpm/s. The screw starts from standstill,
  not from an idle 35 rpm. It becomes RUNNING at the setpoint. Flow follows the
  screw (`nominal × rpm / nominal rpm`), in STARTING and RUNNING alike.
  `START_RAMP_S` is now 3 s (to 60 rpm); it was 4 s, idle to NOMINAL.
- **The lifetime-runtime ramp in RUNNING is gone.** A first start and a warm
  restart at the same setpoint now run identically (A8: q difference 0.0000000
  over 10 s). `ExtruderConfig.startup_ramp_s` is no longer read. It is kept so
  the `.tres` files still load clean.
- **VACUUM_ALARM follows the same law.** It used to force the screw to nominal,
  against its own comment ("unchanged during alarm"). A line at 80 rpm jumped to
  110 when a pot lid popped.
- **`ExtruderConfig.screw_rpm_min` = 60**, the floor. `set_screw_rpm_setpoint`
  clamps to 60..`screw_rpm_max`; it was 0..250. The web shell's `extr_rpm`
  range is now 60..145.
- **A new extruder's setpoint is 60** (it was nominal).
- **Green = 201.875 °C** on 3A/3B: the warmer of the torque-trip and
  lump-point derivations, each with the 25 % margin.
- **A per-line rpm control.** `HmiWebOverlay` has a strip of "Lijn 1/3A/3B/3C/6"
  buttons above the native WebView; the WebView is inset by the strip's height
  so the native window cannot cover it. Every extruder channel (rpm, zones,
  suction) goes to the selected line. A panel opens on its scope's first line
  that has an extruder. `ExtruderZonePanel` (touchscreen, MACHINES →
  extruder_<line>) gains a SCHROEFTOERENTAL row that follows the model.
- `ExtruderMachine`'s status and start messages name the setpoint.

## 4. Measured after (final tree)

From `test_extruder_start_rpm` (27 ok) and the probe:

| case (3B unless named) | result |
|---|---|
| a NEW extruder's first start at green (setpoint 60) | 60 rpm, no lumps, peak 163.3 bar, no trip |
| warm restart at green, set to 60 (3B and 3A) | torque 84.4 %, no lumps, peak 165.1 bar, no trip |
| the gameplay path, set to 60 | peak 165.1 bar, no trip |
| then raised to 110 once the melt is at setpoint | MP<MF 197.6..260.0 bar (the nominal band), no trip |
| a warm restart set to 60 with the melt at the OLD green 196.25 °C | lumps, **trip 3.3 s** (negative control) |
| tripped 318 on a caked screen, restarted at the old 110 rpm | **trips again** 4.7 s in, at 92 rpm, still ramping |
| the same screen, restarted at 60 rpm | peak 278.1 bar, no trip |
| warm restart at green, setpoint left at 60 / 70 / 80 / 90 / 100 | 165 / 192 / 220 / 252 / 285 bar, no trip |
| warm restart at green, setpoint left at 110 (not gated) | peak 317.2 bar, **trips at 18.1 s** |

The caked-screen rows are the operator's own account (rulings file §1). The last
row is the consequence he accepted with the "new extruder starts at 60" ruling:
a player who leaves a line at 110 and restarts it on a just-warm barrel trips
it, and 60 gets it going. It is an `info` line, not a check. The margin is 0.8
bar, and a later change to the die law (e.g. the power-law die) can move it
either way.

## 5. Guard and mutation matrix

`src/tests/test_extruder_start_rpm.tscn` (wired in `run.sh`'s main loop after
`test_extruder_ramp_pressures`) has 27 checks in three parts: A on a bare
model, B on the wired rigs, C on the HMI. Every mutation below was applied to
the source, run, and restored; md5 was identical after each.

| mutation | start_rpm red | melt_pressures red |
|---|---|---|
| M0 `main`'s ExtruderModel + ExtruderConfig whole | 19 | 0 (see below) |
| M1 the old STARTING (idle → nominal in 4 s, RUNNING at 0.95 nominal) | 6 | — |
| M2 the lifetime-runtime re-ramp in RUNNING | 4 | — |
| M3 every start resets the setpoint to 60 (this branch's first, wrong reading) | 4 | 0 |
| M4 green from the torque trip only | 6 | 2 |
| M5 VACUUM_ALARM forces nominal | 1 | — |
| M6 the 0..250 setpoint clamp | 2 | — |
| M7 the web HMI back on the first extruder | 3 | — |
| M8 the touchscreen slider does not follow the model | 1 | — |
| M9 a new extruder seeded at nominal | 4 | 1 |
| M10 `START_RAMP_S` 4 s | 4 | — |

`test_extruder_melt_pressures` gains the WARM restart beside its fresh one, set
to 60 as the operator does. That check is NOT a guard for M0: on `main`'s model
a warm restart set to 60 also runs (279.1 bar), because RUNNING already honoured
the setpoint. The guard for the fix is `test_extruder_start_rpm`.

## 6. Other suites

Five suites assumed a start runs to nominal. Each now raises the setpoint to
nominal right after the start, as a player would:
`test_extruder_melt_pressures`, `test_extruder_ramp_pressures` (U3 and W1 now
compare the last STARTING tick against the flow at the model's setpoint),
`test_die_pressure_bar` and `test_extruder_stop_torque` (#296; without the
raise its "nominal" stop ran from 60 rpm and still passed). The melt suite's
caked-screen helper now reads the LIVE feed. Its restart used to run at a
different flow from the one the helper had captured, and fell 73 bar short of
the trip.

Run one at a time on the final merged tree:

- start_rpm 27 ok, melt_pressures 55, ramp_pressures 21, stop_torque 21,
  die_pressure_bar 21, brain_wired 26.
- cutter_compactor 57, bluport_scope 20, hmi_fault_per_line 26,
  hmi_fault_rearm 32, hmi_screen_zeroing 29, screw_die_plate_bar 36.
- vacuum_pot_minigame 35, vacuum_pot_visual 22, hmi_universal_interactive 22,
  hmi_web PASS, hmi_web_gather_vals 42.
- Parse sweep 470 ok / 0 fail.

**The full harness was NOT run.** The operator runs it once all sessions are
done. `test_machine_sounds` (new on `main`) fails in this worktree only: its WAVs
are on disk, but this worktree's `.godot` import was cut off at a 600 s timeout
and never imported them ("not an AudioStreamWAV"). The branch touches no audio.

## 7. Open

- Start interlocks (heetafslag water, centrifuge, trilzeef running), rulings
  file §6. Not built.
- The raw archive points at a ~5 s ramp to 60 rpm; the model keeps his 3 s
  (rulings file §4). The rate above 60 is a modelling choice.
- OFF cools the melt 0.5 °C/s with no source (rulings file §7). It sends every
  restart more than ~35 s after a stop through PREHEAT, where the plant restarts
  short stops hot.
- The lump law and the cake's 2500 psi/g have no source, and they make the
  green threshold a knife edge (§2).
- `IDLE` still spins at `screw_rpm_idle` 35, under the new 60 floor. No
  transition into IDLE was found, and it was not changed.
