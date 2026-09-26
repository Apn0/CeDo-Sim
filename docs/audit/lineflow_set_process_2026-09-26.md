# LineFlow off frame time in the suites that tick it (2026-09-26)

Follow-up to `docs/audit/rebuild_pipe_carry_2026-09-25.md` §5 and §5.1.

LineFlow's `_process` adds up frame time and calls `tick(0.1)` once for every
0.1 s it has gathered, at most 10 times a frame (`FLOW_CATCHUP_MAX_S`, 1 s).
Godot 4 turns processing on at READY for a script that overrides `_process`,
so a `set_process(false)` made before `add_child` is ignored.

The suites below make their own LineFlow, call `rebuild()` and drive
`tick(0.1)` themselves. None of them switched `_process` off, so LineFlow also
ticked on frame time in every frame they awaited. Their results could depend on
frame pacing and on how loaded the machine was.

**Result:**
- 21 suites now call `set_process(false)` right after `add_child`.
- `test_extruder_silo_feed_stop` keeps frame time, by operator choice: its S3
  check passes only on the one frame tick it gets today (§6).
- On 4.6.3, check values moved in 5 suites and info lines in 4 more. The
  plain baseline was identical across its two runs. But in one suite it gave a
  different value from the instrumented run and the `--fixed-fps 10` run, with
  the code under test unchanged.
- After the change, two runs and a `--fixed-fps 10` run of each suite agree,
  apart from sources that are not LineFlow (§4).

## 1. Which suites

Listed with the grep from the task (`run.sh`'s `for t in` lists, a
`LineFlow.new()`, a `rebuild()` call, no `set_process(false)`). It finds
**28** suites, not the 27 of 2026-09-25: `test_plant_resume` was wired into
`run.sh` after that count (the grep re-run on `d5ed137`, the commit that wrote
it, gives exactly the 27).

**Changed (21):** `set_process(false)` right after `add_child`, on every
LineFlow the suite ticks itself.

| suite | LineFlows switched off |
|---|---|
| `test_belt_film_field` | the S4 `lf` (S1's `lf_probe` is never added to the tree) |
| `test_belt_speed_mismatch`, `test_bunker_relay_trip`, `test_bunker_shredder2_interlock`, `test_chute_choke`, `test_compactor_sight_glass`, `test_extruder_silo_chain`, `test_extruder_start_interlock`, `test_fallback_chains`, `test_line1_no_false_overload`, `test_line1_throughput`, `test_machine_sounds`, `test_motor_trip_stops_conveying`, `test_screw_die_plate_bar`, `test_silo_level_windows`, `test_sort_line_topology`, `test_trip_smoke` | the suite's one LineFlow |
| `test_flow_node_unique` | B's `lf` (the one `_behaviour` ticks); the census and reloaded LineFlows only read the graph and are left |
| `test_macro_edges_reload` | in `_boot_lineflow()`, the one place it adds a LineFlow: lf2 is ticked, lf1/lf3/lf4 only read the graph |
| `test_plant_resume` | all four (phases A and B, built and reloaded). Phase C boots MainWorld, whose LineFlow runs on frame time as in the game, and is left |
| `test_wet_side_beds` | L's `lf1`; G's `lf` only reads edges and metas |

**Not changed (7):**
- `test_extruder_silo_feed_stop`: left on frame time until its S3 check is
  re-derived (operator choice 2026-09-26, §6). A comment at its `add_child` says why.
- `test_doseersilo_trough`, `test_ghost_census`,
  `test_line1_flow_conformance`, `test_line1_twin_streams`,
  `test_line3a_flow_conformance`, `test_line3b_flow_conformance`: they never
  call `tick()`. They read the graph, port positions and metas, which no tick
  changes. Measured: their output was identical before and after
  (they served as the controls below).

## 2. How it was measured

- **Tree and engine:** `276f3d7` (= `origin/main` at the start) on
  Godot 4.6.3. `main` moved to 4.7.2 (#327) during the work; the changed
  suites were re-run on 4.7.2 after merging it (§7).
- **Isolation:** one Godot at a time. Each run started from a fresh
  `robocopy /MIR` of the operator's `app_userdata`
  (`D:\cedo_archive\userdata\session_lf_set_process_2026-09-26\`), with
  `APPDATA` pointing there. The operator's real `world_layout.json` kept its md5
  (`e046af7d…`) throughout.
- **Import first.** `.godot/` was copied from the operator's checkout, and its
  class cache did not know `KeybindSheet`. The first partial baseline pass
  therefore printed 2 `SCRIPT ERROR` lines in `test_plant_resume` phase C
  (HUD.gd did not parse), still with `PASS`. That pass was discarded. Every
  run below comes after `--import`, as `run.sh` does.
- **Runs:** baseline ×2 and a baseline with `--fixed-fps 10`. Then the change,
  and the same three again. `--fixed-fps 10` gives every frame exactly 0.1 s,
  one LineFlow tick, whatever the frame really took: a different pacing.
- **Compared:** every `ok` / `FAIL` / `info` / `note` / `skip` / `Result` line,
  with only wall-clock figures masked.
- **Instrumented baseline:** a throwaway detached worktree of `276f3d7`, with
  LineFlow printing every frame tick (count, delta, powered nodes) and every
  `rebuild()`, to see when the ticks landed (§3). Its output matched the plain
  baseline's, apart from the two sources that are not LineFlow (§4) and
  `test_sort_line_topology` (§5.3).
- **Probe:** `src/tests/probe_feed_stop_pre_ticks.tscn -- <k>` switches
  `_process` off and runs k ticks by hand where the frame ticks used to land
  (§6).

## 3. Where the frame ticks landed (instrumented baseline, 4.6.3)

Every heavy frame reported a delta of 0.117–0.150 s, even a frame that built
three lines and took seconds. So each awaited frame gave LineFlow one tick,
two when the remainder carried over. That is likely why two plain runs on
this machine agreed with each other.

Not verified: that cap is close to Godot's default
`max_physics_steps_per_frame` / `physics_ticks_per_second` = 8/60 s, which is
the likely cause. A light frame (under 0.1 s) gives no tick.

Ticks that landed before a check, per suite:

| suite | before its own `rebuild()` | idle, between `rebuild()` and `start_line()` | on a running line, mid-run |
|---|---|---|---|
| `test_belt_film_field`, `test_belt_speed_mismatch`, `test_extruder_silo_chain`, `test_fallback_chains`, `test_line1_no_false_overload`, `test_line1_throughput`, `test_screw_die_plate_bar`, `test_sort_line_topology`, `test_silo_level_windows`, `test_trip_smoke` | 1 | 1 | 0 |
| `test_bunker_relay_trip`, `test_bunker_shredder2_interlock`, `test_compactor_sight_glass`, `test_motor_trip_stops_conveying`, `test_extruder_silo_feed_stop` | 1 | 0 | 0 |
| `test_chute_choke` | 1 | 2 (one after its mid-test `rebuild()`) | 0 |
| `test_extruder_start_interlock` | 1 | 0 | 1 (part C's first await, 50 machines powered) |
| `test_flow_node_unique` | 3 | 4 | 1 |
| `test_macro_edges_reload` | 4 | 8 | 2 |
| `test_plant_resume` | 4 | 0 | 4 (one in phase B's four `physics_frame` awaits, 65 powered) |
| `test_machine_sounds` | 0 | 0 | 6 (S4's `_wait(0.5)` with the trilzeef in HAND) |
| `test_wet_side_beds` | 2 | 2 | **433**: one per `await` in its 4000-tick loop (it awaits every 10 ticks) |

How a tick before the suite's own `rebuild()` survives it:
- `rebuild()` keeps each machine's state (#218).
- It keeps the extruder silo sensor's `_silo_state`, keyed by the silo body, so
  its 1 s report clock starts 0.1 s ahead.
- It keeps the models hung on a node, such as the CutterCompactor.

A tick after `rebuild()` on an idle line advances every empty connector's
`stage_t`. The suite's first kg then arrives one tick earlier.

Most suites also got 1–3 more ticks after their last check. Those change no
result.

## 4. Before and after, 4.6.3

`=` means the check (ok/FAIL) lines are identical; the info column counts info
lines that differ.

| suite | before r1 = r2 | before ff10 = r1 | after r1 = r2 = ff10 | before → after: checks | before → after: info |
|---|---|---|---|---|---|
| `test_belt_film_field` | = | = | = | **1 moved** (§5.1) | 4 |
| `test_belt_speed_mismatch` | = | = | = | **4 moved** (§5.1) | 16 |
| `test_bunker_relay_trip` | = | = | = | = | = |
| `test_bunker_shredder2_interlock` | = | = | = | = | = |
| `test_chute_choke` | = | = | = | = | = |
| `test_compactor_sight_glass` | = | 1 differs | = | **1 moved** (§5.1) | = |
| `test_extruder_silo_chain` | = | = | = | = | 6 (§5.2) |
| `test_extruder_silo_feed_stop` (with the change, then reverted) | = | = | = | **S3 red** (§6) | = |
| `test_extruder_start_interlock` | = | = | = | = | = |
| `test_fallback_chains` | = | = | = | = | 17 (§5.2) |
| `test_flow_node_unique` | = | = | = | = | 11 (§5.2) |
| `test_line1_no_false_overload` | = | = | = | = | = |
| `test_line1_throughput` | = | = | = | = | = |
| `test_machine_sounds` | S3/S4 drift, S8 red once | cannot run | S3 drift; ff10 cannot run | S3 drift only | = |
| `test_macro_edges_reload` | = | = | = | = | = |
| `test_motor_trip_stops_conveying` | = | = | = | = | = |
| `test_plant_resume` | cart RNG | cart RNG | cart RNG | **B1 122 → 137 %** (§5.1) + cart RNG | 1 (RNG) |
| `test_screw_die_plate_bar` | = | = | = | = | = |
| `test_silo_level_windows` | = | = | = | = | = |
| `test_sort_line_topology` | = | 16 info differ | = | = | = (§5.3) |
| `test_trip_smoke` | = | = | = | = | = |
| `test_wet_side_beds` | = | 2 info differ | = | = | 2 (§5.2) |
| the 6 that never tick | = | = | = | = | = |

Verdicts: every suite PASS before. After, every changed suite PASSes, and
`test_extruder_silo_feed_stop` is FAIL (16 ok, 1 fail) with the change, which
is why it was reverted.

**Two sources that are not LineFlow, seen in every column:**
- `test_plant_resume`: the lump cart's time to cool (4132, 6768, 6837, 6920,
  8521 s, …) comes from `randf_range(COOL_TIME_S_MIN, COOL_TIME_S_MAX)`,
  unseeded (`src/sim/LumpCart.gd:107`). The file-size line follows it, by its
  digits.
- `test_machine_sounds`:
  - S3 is a MachineSound with no LineFlow, coasting on frame time: drive
    0.107–0.161 across runs, both before and after.
  - Under `--fixed-fps` it cannot run at all: S3 holds on the wall clock but
    waits on frame timers, and the watchdog fires. That is the same before and
    after.
  - S8 was red once (§8).

## 5. The values that moved, read

Every one of them differs between runs whose only difference is LineFlow's
`_process`, so every old value came from frame ticks. §3 says which ticks.

### 5.1 Check values

| suite | check | before | after | which ticks | margin to the threshold |
|---|---|---|---|---|---|
| `test_belt_film_field` | S4 "the next belt downstream carries a bed too" | 3.35 kg/m (belt#4 thru 3.38 kg/s) | 3.10 kg/m (thru 3.51) | 1 before `rebuild()`, 1 idle after it: the connectors' phases | the check wants > 0 |
| `test_belt_speed_mismatch` | H1 chute packs first, drive trips after | trip 18.9 s, excess 25 kg | 18.8 s, 24 kg | the same two | packs at 9.5 s, both runs |
| | H1 no spill yet | excess 25 kg (chute 15) | 24 kg | | |
| | H2 heap after the reset | 0.1 s | 0.2 s | | |
| | R2 backlog drained | 9.8 s | 9.7 s | | |
| `test_compactor_sight_glass` | S3 the level moved | 2.0326 → 2.0207 m | 2.0327 → 2.0208 m | 1 before `rebuild()`, idle (the compactor model) | it wants any movement |
| `test_plant_resume` | B1 3A's silo holds its feed | 122 % | 137 % | 1 before each `rebuild()`, and 1 on the running line in phase B's `physics_frame` awaits | it wants `held` |
| `test_extruder_silo_feed_stop` | S2 3B stop time; S6 silo % | 957 s = 15.9 min; 63.0 % | 957 s = 16.0 min; 62.6 % | 1 before `rebuild()` (`_silo_state`) | S3: §6 |

### 5.2 Info lines only

- `test_extruder_silo_chain`: the silo's and the compactorband's "first kg"
  arrive 0.1 s later on all three lines (for example 9.2 → 9.3 s). That is
  exactly the one idle tick after `rebuild()`. Upstream machines unchanged.
- `test_fallback_chains`: "first kg" times move by 0.1–0.2 s on most lines and
  by 0.6 s at the 3A/3B intake's shredder 2 (4.1 → 3.5 s). Every kg total
  unchanged.
- `test_flow_node_unique`: the intake belts' mean thru and bed move in the
  third decimal (for example 0.467 → 0.469 kg/s).
- `test_wet_side_beds`: max bed depth 12.9 → 13.0 cm (dewatering screw) and
  2.2 → 2.3 cm (one Kufferath sieve). In the instrumented run, 433 extra ticks
  landed during its loop, so the old "L ran 4000 ticks (400 s sim)" was about
  443 s of sim time.

### 5.3 The one that moved with the pacing, not with the change

`test_sort_line_topology` read "first kg at 22.2 s" in both plain baseline
runs and in all three after-runs. Two baseline runs with unchanged code under
test read 22.1 s for every machine, all 16 lines one tick earlier:
- the instrumented run, where one frame after `rebuild()` had a delta of
  exactly 0.100 s;
- the `--fixed-fps 10` run.

The plain runs evidently did not tick in that frame: their values equal the
after-runs. Whether a frame near 0.1 s ticks depends on the remainder carried
from earlier frames. This is the load dependence the task describes, caught in
one suite. With `_process` off it is gone.

## 6. `test_extruder_silo_feed_stop` S3, and why it keeps frame time

S3 reads: "3B's backlog waits in the VSS (63.5 kg) … not in the stopped screw
(its input X kg at the stop, Y kg now)". It asserts
`screw_in_end - screw_in_at_stop < 1.0`. With the change it was red, the same
in all three after-runs: 0.0 → 1.1 kg.

The probe replays the frame ticks by hand, `_process` off, 4.6.3:

| k ticks before `rebuild()` | sensor clock after `rebuild()` | stop | screw input at the stop | grew after the stop | S3 | on the VSS→screw connector at the stop |
|---|---|---|---|---|---|---|
| 0 (the suite with the change) | 0.00 s | 957.0 s | 0.000 kg | 1.123 kg | FAIL | 1.056 kg |
| **1 (what this machine gives today)** | 0.10 s | 956.9 s | 0.211 kg | **0.957 kg** | **PASS** | 1.029 kg |
| 2 | 0.20 s | 957.8 s | 0.000 kg | 1.149 kg | FAIL | 1.082 kg |
| 3 | 0.30 s | 957.7 s | 0.000 kg | 1.195 kg | FAIL | 1.056 kg |

k = 0 and k = 1 reproduce the after-run and the baseline to the printed digit.
So the green holds only while exactly one frame tick lands before the
`rebuild()`. A faster machine (no tick) or a slower frame (two) would turn it
red with no code change.

**What the growth is (probe, k = 0, printed each tick after the stop):**
- The VSS and the dosing screw coast down together: spin 0.96 → 0 over about
  2.4 s, `SPIN_UP_S`.
- While the VSS coasts, it passes the feed on into the connector, 0.026 kg a
  tick (950 kg/h). Its own buffer stays at 0.03 kg.
- While the screw coasts, it passes a 0.185 kg parcel on to the rafter.
- Once both stand, the ~1.08 kg left on the connector drains into the stopped
  screw's input.

So S3 measures about one connector's worth at the fed rate, 0.96–1.20 kg by
where the parcels sit when the stop lands. The typed 1.0 kg allowance cuts
through that band. The check's intent still holds by far (VSS 63.5 kg against
~1.1 kg in the screw), but the number does not say so.

**Operator choice (2026-09-26):** of four options (ship it red; hold this
suite; re-derive the allowance from the model; restate S3 as a ratio), the
operator chose to leave this suite on frame time until S3 is re-derived. No threshold
was changed. A follow-up task carries the probe numbers and the options.

**Update, later on 2026-09-26.** Relayed by the follow-up session (branch
`claude/sweet-mcnulty-6890da`), where the rulings are recorded. They are
recollections, not documents, and not verified here:
- **S3 is PARKED.** The operator says a stopped dosing screw M11a takes nothing
  more, so the ~1 kg measured here is a sim artifact: the 5.9 m connector
  between `vss_silo` and M11a, which `lijn_3b_flow.md` does not have. S3
  should end up asserting 0.
- **The 3B wash-line timing comes first.** That session measured the sim at 39 s
  from VSS to extruder silo and 9.6 kg in the line at 950 kg/h. The operator
  recalls ~10 min and ~160–200 kg.

This suite stays on frame time until that model work is done.

## 7. On Godot 4.7.2

`main` moved to 4.7.2 (#327) while this ran. After merging it:
- this tree was imported with `V:/Godot/Godot_v4.7.2-stable_win64_console.exe`;
- all 28 suites ran twice;
- the parse sweep and the probe (k = 0, 1) ran once.

| run | result |
|---|---|
| `--import` | rc 0 |
| 28 suites, run 1 and run 2 | all PASS, 0 `^SCRIPT ERROR`. The two runs agree except `test_machine_sounds` S3 and `test_plant_resume`'s cart (§4) |
| against 4.6.3 after-run 1 | 27 suites identical line for line (same exceptions). `test_extruder_silo_feed_stop`, which now keeps frame time, is identical to the 4.6.3 baseline: PASS, 0.2 → 1.2 kg |
| parse sweep | 489 ok, 0 fail, `RESULT: PASS` (4.6.3: the same) |
| probe k = 0 / k = 1 | +1.123 kg FAIL / +0.957 kg PASS, the 4.6.3 numbers to the printed digit |

Not investigated: `test_plant_resume`'s save file is about 1 KB smaller on
4.7.2 (81516 bytes against 82553–82638 on 4.6.3). It is an info line, and
every check reads the same.

## 8. Found on the way, not fixed

- **`test_machine_sounds` S8 is a timing race, unrelated to LineFlow.**
  - The check: "OVERLOAD-ESTOP on a friction washer → the panel beeps" asks for
    `ap.playing` 0.4 s after the alarm is raised, a frame-time timer.
  - The beep (`washing_alarm_beep.wav`) is 0.366 s long and starts on the next
    frame. So the check only passes when that frame is ≥ 0.034 s late.
  - Red in 1 of the 8 default runs of this session (baseline run 2), on the
    unchanged tree.
- **The material census is red on `main`**, so `run.sh` stops before any suite
  runs.
  - `tools/audit/material_census.py` flags `src/sim/PlantResume.gd`: MINTS at
    :127, DROPS_SUB.
  - It is red on `276f3d7`, since `cbd95ec`. Filed as a separate task.
- **`_silo_state` outlives `rebuild()`.** That is right for a sensor on a real
  silo. It is also why a tick before a suite's `rebuild()` shifts every report.

## 9. Files

- 21 suites in `src/tests/`: one line each after `add_child`, four in
  `test_plant_resume`.
- `src/tests/test_extruder_silo_feed_stop.gd`: a comment only.
- `src/tests/probe_feed_stop_pre_ticks.gd` / `.tscn`: the probe in §6.
- Logs, the runner, the comparison script and the instrumented LineFlow's diff:
  `D:\cedo_archive\userdata\session_lf_set_process_2026-09-26\`.
