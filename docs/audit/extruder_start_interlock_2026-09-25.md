# The extruder's start button and its natraject — 2026-09-25

Branch `claude/extruder-start-interlocks`, off `main` `147cff1` (#308 merged),
with `main` merged in again at `1b3c4e0` (#310, #311, #312).
Engine `C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe`.
The operator's answers are in `docs/plant/operator_rulings_2026-09-25.md`,
fourth session (§I1-§I10). Every number below was produced by
`src/tests/test_extruder_start_interlock.tscn`,
`src/tests/probe_extruder_off_backlog.tscn` or the suites named.

## 1. What was there before

Found by reading the code (two search passes over `src/` and `docs/`):

- **Only the barrel temperature could refuse a start.** `ExtruderModel`
  routes a cold-barrel start to PREHEAT and ignores green until
  `preheat_ready()`. Nothing else was checked, and a refused start raised no
  alarm.
- **LineFlow and ExtruderModel never read each other.** The line's start
  (`LineFlow.start_line()`, one PLC for the whole plant) powered the
  extruder's own flow node and every machine after it, whether or not the
  extruder had been started.
- **The pellet side existed only as flow nodes.** The heetafslag, ontwaterzeef,
  centrifuge and weegschaal on lines 1, 3A and 3B had `powered`/`spin`, a
  HAND/AUTO switch and trip latches in LineFlow, but no link to the extruder.
  `PelletizerModel` (the knife wear inside the extruder model) has no run state.
- **No plant document lists the start conditions.** SWI-042 p4 rows 19-20 say
  "Nog SWI maken opstarten extruders". The raw WinCC archive logs none of these
  machines: 3A/3B hold screw speed and load, pressures, temperatures, output and
  the compactor, and the 3C tag list covers the wash side only.

## 2. What was built

From the operator's rulings (§I1-§I7):

- **`src/sim/ExtruderStartSequence.gd`** (new, plain logic, `preload`ed; no
  `class_name`). This is the right white ring button:
  - `press()` runs the checks. A failed check latches an alarm, and while an
    alarm stands the button does nothing.
  - `tick()` switches on blower + weegschaal, centrifuge, ontwaterzeef,
    heetafslag and laserfilter in that order. Each goes on once the one before
    reaches spin 0.99 (LineFlow ramps spin over 2.5 s). Then it asks for the
    screw once.
  - A natraject machine that loses power under the screw trips it.
  - A stop runs them down in reverse, starting only once the screw stands.
  - `led()`/`led_lit()` give the ring: 0.5 s off / 0.5 s on while the
    natraject comes up or runs down, solid with the screw, off at rest.
  - Two sim limits, with no plant number behind them: a step whose machine is
    not up within 10 s aborts the start, and so does a screw that does not
    start within 1 s of being asked.
- **`ExtruderModel`**:
  - `start_seq` holds the sequence, so every HMI that reaches the model can show
    it and reset it.
  - The input `natraject_trip` in STARTING, RUNNING or VACUUM_ALARM goes to
    FAULT (`fault_reason = "natraject_stopped"`, `natraject_trip_text`).
  - A bare model has no interlock: its `start_production` starts the screw as
    before.
- **`ExtruderConfig.natraject_enabled`** (default true) is the hidden setting's
  starting value.
- **`LineFlow`** gets extruder-owned machines:
  - `claim_node`, `command_node`, `release_nodes`, `node_owner`,
    `natraject_status`, `node_for_body` and `flow_bodies`.
  - `_tick_plc_power_downstream` writes an owned node's `powered` from its
    owner's command after the PLC. HAND, the trip latches and the e-stop still
    override it.
  - `rebuild()` calls every extruder's `on_line_flow_rebuilt`, so the claims
    are in place before the next tick.
- **`ExtruderMachine`**:
  - Finds its natraject: the machines of its own macro build
    (`macro_instance`), or for a free-built extruder the nearest of each kind
    within 30 m that no macro line holds.
  - Claims those machines and its own flow node.
  - Every start press (the E key, or `_pending["start_production"]` from tests
    and HMIs) goes through `_route_start_button`:
    - a cold barrel goes to its warm-up as before;
    - a barrel at temperature, or a coasting screw, runs the sequence;
    - with the natraject off, the press goes straight to the screw;
    - with an alarm standing, nothing happens.
  - While the natraject comes up the model holds the barrel in PREHEAT, because
    OFF cools 0.5 °C/s and green is 13 °C under the setpoint.
  - The extruder's own flow node runs while the screw turns.
  - The prompt and the status text show the sequence and the alarm.
- **HMI**:
  - `EremaFaultRegistry` lists a standing start alarm as **4401**, a SIM code in
    the emulator tier: no photo shows the plant's number. The text is live.
  - `HmiOverlay` RESETTEN resets the start alarm of the extruders on its lines,
    on a panel whose tokens name the extruder (the washing panel's does not).
  - `ExtruderZonePanel` (touchscreen) and the `HmiWebOverlay` line strip both
    get the ring lamp, the status or alarm text, ALARM RESET and the
    **Natraject** switch.
  - The reset is on the HMI only (§I6). E at the machine still clears the
    model's FAULT as before, but not the start alarm.

## 3. Measured (test_extruder_start_interlock, 32 checks)

Part A, the sequence alone on a fake plant: order, waits, ring, refusal, latch,
trip, run-down, the natraject switch, the timeout and the mid-start abort (12
checks, A1-A12).

Part B, a real 3B line (`BuildMode._build_full_line` → `LineFlow.rebuild` →
`start_line`), with a 3C line and a free-built extruder_3a beside it, the brains
stepped by hand:

| what | measured |
|---|---|
| claims right after `rebuild()`, before any brain tick | 3B brain holds its node + weegschaal, centrifuge, ontwaterzeef, heetafslag, laser_filter, all of `line_3b`; the 3C heetafslag has no owner |
| 30 s after the line's start | 3B extruder node and natraject all OFF; its compactorband and 3C's heetafslag run |
| 5 kg put in the stopped extruder | 0.000 kg reach the laserfilter |
| the press, by LineFlow's own power and spin | weegschaal on 0.1 / up 2.5 s, centrifuge 2.7 / 5.1, ontwaterzeef 5.3 / 7.7, heetafslag 7.9 / 10.3, laserfilter 10.5 / 12.9 |
| the screw | STARTING at 13.0 s, RUNNING at 60 rpm at 16.0 s; model in PREHEAT until then, melt min 214.95 °C (green 201.875) |
| the ring | off at 0.3 s, on at 0.7 s, solid from the screw start |
| kg through the running natraject (60 s at 950 kg/h + 60 s drain) | 20.6 of 20.6 kg in the voorraad_silo |
| centrifuge switched off (HAND) under the running screw | FAULT in 0.2 s, `natraject_stopped`, "Natraject gestopt — Centrifuge: staat in HAND", alarm 4401 listed |
| the run-down | screw at 0.00 rpm at the first switch-off; laserfilter 0.2 s, heetafslag 2.7, ontwaterzeef 5.2, centrifuge 7.7, weegschaal 7.7; ring off after |
| fixed, FAULT cleared with E, pressed | nothing starts (OFF, no natraject powered); a cold-barrel press does not start the warm-up either |

Part C, the HMI:
- RESETTEN on the washing panel leaves the alarm; RESETTEN on the extruder panel
  clears it and 4401 leaves the list.
- The same press then runs everything again: RUNNING 16.0 s after it.
- The extruder panel shows a refusal ("Start geweigerd — Heetafslag: staat in
  HAND") and its ALARM RESET clears it.
- The web strip shows the free-built 3A's refusal ("... Blower + weegschaal niet
  gevonden") and resets it.
- With the Natraject switch OFF there, the same press starts 3A's screw at
  once. The panel's switch turns it back ON.

## 4. A consequence to rule on: an extruder left off backs the line up

`src/tests/probe_extruder_off_backlog.tscn` ran a real 3B line fed at 950 kg/h
at the blower before the extruder silo, for 60 min of sim time:

| case | result |
|---|---|
| extruder never started | the material waits at the extruder: 75 kg at 5 min, 154 kg at 10 min, 234 kg at 15 min; **LineFlow's overload e-stop fires at 16.0 min** (`extruder_3b`, 250 kg, `OVERLOAD_KG`) and stops the line upstream |
| extruder started at t = 0 | no e-stop in 60 min; the extruder's buffer stays at 0 kg |

The operator ruled that the silos fill while the extruder is off (§I4). The sim
caps any machine's input at 250 kg and has no silo capacity. So a cold barrel,
whose warm-up takes at least 30 min (SWI-042 p4 §19), could not be warmed up
with its line feeding at nominal: the line e-stopped at 16 min. Before this
change the extruder node swallowed the material whether or not it ran, so the
question never came up. **He was asked; the answer is built in §8.**

## 5. Mutation matrix

Each mutation was applied to the source, the suite run, and the file restored;
the md5 was identical after every one. Runner:
`python mutate.py <out> [M..]`, kept in the session scratchpad, calling the
engine directly.

| mutation | red | which |
|---|---|---|
| M1 the line's PLC still runs extruder-owned machines | 4 | B1, B8, B9 |
| M2 a step does not wait for its machine to spin up | 7 | A2, A3, A4, A11, A12, B2, B3 |
| M3 the button ignores a latched alarm (in the sequence) | 1 | A7 |
| M4 no trip when a natraject machine stops under the screw | 9 | A5, A7, B7, B8, B9, C1, C3, C4 |
| M5 the run-down does not wait for the screw to stand | 1 | A6 |
| M6 natraject OFF does not hand the press to the screw | 1 | C6 |
| M7 RESETTEN on the extruder panel does not reset the start alarm | 3 | C2, C3, C4 |
| M8 the extruders claim only on their next SimTick, not at rebuild | 1 | B0 (part B stops there) |
| M9 the ring blinks on-first | 2 | A4, B4 |
| M10 the start alarm is not in the Storingstabel | 2 | B7, C1 |
| M11 the heaters do not hold the barrel while the natraject comes up | 1 | B3 |
| M12 a cold-barrel press gets through a latched alarm (the warm-up starts) | 1 | B9 |
| M13 the natraject trip does not fault the model | 6 | B7, B8, B9, C3, C4 |
| M14 a macro extruder takes the nearest machines, not its own build's | 1 | B0 (part B stops there) |

The first draft of the suite had no check that M12 could turn red; that was
found by reading the draft before the mutation run. The B9 cold-barrel check
was added for it. Parse sweep on the final tree: 477 ok, 0 fail.

## 6. Other suites

Six suites start an extruder on a bench with no pellet side. They now switch its
hidden natraject setting off, so the button starts the screw alone, exactly as
before:
- `test_extruder_start_rpm`
- `test_extruder_melt_pressures`
- `test_extruder_ramp_pressures`
- `test_extruder_stop_torque`
- `test_die_pressure_bar`
- `test_extruder_brain_wired` (which proves the brain ticks)

The probe `probe_warm_restart_pressure` got the same change.

Two flow suites fed kg through an extruder that was never started. Under the
ruling (§I4) that material now waits, so each suite starts every extruder brain
the way a player does (hot barrel, the start button, natraject first), steps
the brains with LineFlow, and checks they reach RUNNING before it feeds:

- **`test_fallback_chains`** fed the line-1 and 3B granulate chains at the
  laserfilter. Before the change to the suite, 0.0 of 31.7 kg reached the
  voorraad_silo on both. New check F-.
- **`test_screw_die_plate_bar`** fed the extruder nodes. Before, 3A and 3B read
  0 kg/h and 0.0 bar (9 red). New check B2b. After, the started 3B extruder
  reads what 3C's unowned `extruder_screw` reads on the same profile: 799 kg/h,
  143.7 bar, MFI 0.93.

Run one at a time on this branch, not the full harness (the operator runs
that). Suites marked * were changed here:

| suite | result |
|---|---|
| test_extruder_start_interlock * | 32 ok |
| test_extruder_start_rpm * | 27 ok |
| test_extruder_melt_pressures * | 55 ok |
| test_extruder_ramp_pressures * | 21 ok |
| test_extruder_stop_torque * | 21 ok |
| test_die_pressure_bar * | 21 ok |
| test_extruder_brain_wired * | PASS |
| test_fallback_chains * | 84 ok (red 81/2 before the suite change) |
| test_screw_die_plate_bar * | 56 ok (red 46/9 before the suite change) |
| test_extruder_silo_chain | 41 ok |
| test_macro_edges_reload | 60 ok |
| test_flow_node_unique | 34 ok |
| test_line1_throughput | PASS (its ungated "granulaat banked" line reads 0.0 kg, as it did before) |
| test_qa_loop | PASS |
| test_line1/3a/3b_flow_conformance | PASS |
| test_motor_trip_stops_conveying | 28 ok |
| test_hmi_fault_per_line | 26 ok |
| test_hmi_fault_rearm | 32 ok |
| test_hmi_web_gather_vals, test_hmi_universal_interactive (--script) | PASS |
| test_vacuum_pot_minigame | 35 ok |
| test_vacuum_pot_visual | 22 ok |
| test_line1_twin_streams, test_line1_no_false_overload | PASS |
| test_lump_cart_overflow | 45 ok |
| test_lump_cart_coverage, test_tag_snapshot, test_macro_part_placement | PASS |
| test_wet_side_beds | 31 ok |
| test_line1_metal_detect | 27 ok |
| test_sort_line_topology | 97 ok |
| test_ghost_census | 11 ok |

0 `SCRIPT ERROR` lines in any of them.

**After merging `main` at `1b3c4e0`** (#312 moved the world suites into the
building frame), these were run again on the merged tree, all green with 0
`SCRIPT ERROR` lines:
- test_extruder_start_interlock 32 ok, test_fallback_chains 84 ok,
  test_screw_die_plate_bar 56 ok, test_extruder_start_rpm 27 ok,
  test_extruder_silo_chain 41 ok, test_macro_edges_reload 60 ok.
- test_nav_connectivity 13 ok, test_jam_baseline 20 ok / 0 skipped.
- test_extruder_brain_wired, test_qa_loop, test_tag_snapshot,
  test_lump_cart_coverage, test_line3a/3b/3c_identity, test_l3c_unit_screens and
  test_waslijn3c_overzicht all PASS.

Parse sweep on the merged tree: 479 ok, 0 fail.

## 7. run.sh on main did not parse

`main` as merged at `147cff1` (the #308/#309 merge, `59acf8f`) kept two
`for t in ...` headers for the main suite loop. One lacked `test_ghost_census`,
the other `test_extruder_start_rpm`. `bash -n` said
`line 1204: syntax error: unexpected end of file`, so the harness would stop
before its first suite. This branch repaired it (`86cc7c5`), and #310 repaired
it on `main` the same day. The merge of `main` into this branch kept #310's
line and added only `test_extruder_start_interlock`, after
`test_extruder_start_rpm`. The `for t in` lists were diffed against `main`:
none missing, one added.

## 8. The extruder silo's level sensor and its feed stop

Asked after §4 (rulings §I11, §I13). Built:

- **The PCU belt stops at a full pot.** On lines 1/3A/3B the extruder's flow
  node is the PCU and the screw in one, so its input buffer is the pot. At
  `CutterCompactor.POT_CAPACITY_KG` (60 kg, the sim's own number; his rough
  guess for a full PCU was about 100 kg) the compactorband and the extruder
  silo's discharge are held. The silo then fills, which is what he described:
  *"if the compactor belt is not running ..."*.
- **The level sensor** (`LineFlow._tick_silo_feed_stops`) averages the silo's
  content over each second and reports once per second, as % of `SILO_FULL_KG`
  (150 kg, the silo-full the level windows already show; no plant capacity is
  documented) and as mm on his example scale (1780 mm = 100 %, 4950 mm = 0 %).
- **The feed stop.** At >= 100 % the silo's feed is held at once. On 3A/3B that
  is the VSS dosing screw M11a (the `transport_screw` after the
  `vuilsnippersilo`) and the VSS's own discharge (`vss_silo`; in the sim graph
  it feeds the screw directly, so without it the VSS empties into the stopped
  screw). On line 1 it is the shredder (§I13: its hopper is line 1's VSS). The
  feed runs again after 10 reports in a row under 100 %.
- **HAND bypasses it**, as HAND bypasses every PLC safeguard. It is applied
  where the PLC writes, before HAND.
- The extruder model carries the reading (`silo_level_pct`, `silo_level_mm`,
  `silo_feed_stopped`), and both extruder HMIs show "Extrudersilo NN %
  (NNNN mm)" and "vol: toevoer gestopt".

Measured with `test_extruder_silo_feed_stop` (17 checks) on a real 3B line and
line 1 (plus 3A for the pairing), fed 950 kg/h at the head for 20 min with the
extruders off:

| what | 3B | line 1 |
|---|---|---|
| pairs with | extruder_silo #18 → transport_screw #2 (+ vss_silo) | extruder_silo #38 → shredder_1 #3 |
| PCU pot full, belt + silo discharge stop | 309 s | 298 s |
| silo at 100 %, feed stopped at once | 957 s (15.9 min) | 872 s |
| the wash line runs empty on top | peak 106.0 % | peak 109.8 % |
| overload e-stop in 25 min | none | none |
| where the backlog waits | the VSS, 63.5 kg; the stopped screw's input stays at 1.2 kg | the shredder hopper, 86.9 kg |
| extruder started: feed runs again | 10 reports under 100 %, 9.0 s after the first | the same |

Other checks:
- The reports come once per second (60 in the first 60 s).
- Each is the average of the second before it, checked against the suite's own
  record of the silo over 60 reports.
- The dosing screw in HAND + AAN runs despite a full silo; back in AUTO it is
  held again.

`probe_extruder_off_backlog` (3B fed at its VSS, extruder never started):

| | before §8 | after |
|---|---|---|
| PCU pot full | — | 5.1 min |
| silo at 100 % | — | 15.9 min |
| silo peak | — | 106.0 % |
| e-stop | 16.0 min at `extruder_3b` | 31.8 min at `vss_silo` (250 kg) |

The probe feeds the VSS directly, past the intake. In the plant the intake has
its own "VSS full" logic (`VSS_FULL_KG` 150 kg: the C8 reverse and the pack-up
pause, when both VSSes are full), which this probe does not exercise. Whether
the whole intake keeps a cold extruder's line off the e-stop through a full
30-min warm-up was not measured.

**Mutation matrix (`mutate_silo.py` in the session scratchpad, run on the
final tree, md5 restored after each):**

| mutation | red | which |
|---|---|---|
| MS1 a full silo does not stop its feed | 8 | S2, S3, S4, S5 |
| MS2 the feed runs again at the first report under 100 % | 2 | S5 |
| MS3 the sensor reports the instant content, not the 1 s average | 1 | S1 |
| MS4 the sensor reports every tick | 4 | S1, S3, S5 |
| MS5 a full PCU pot does not stop the belt and the silo's discharge | 10 | S2, S3, S4, S5 |
| MS6 the stop applied after HAND (HAND cannot bypass it) | 1 | S4 |
| MS7 3B's silo stops the vss_silo instead of the dosing screw | 1 | S0 (the suite stops there) |
| MS8 the extruder model does not carry the reading | 2 | S6, S7 |
| MS9 3B's VSS keeps emptying into the stopped dosing screw | 1 | S3 |

**Open, from his answers:**
- The PCU pot's real size (60 kg is the sim's; his guess was about 100 kg), and
  the PCU belt's other modes (continuous, off, manual).
- The silo's real capacity (the mm scale is his "for instance").
- 3C/6's stop/start band ("stop vullen" 225 cm, and a maximum above it): his
  "later".
- The VSS's own fill in bar (3B: start 2, stop 8).
- Line 1's shredder pause is a flow hold: the ram and the motor that keeps its
  rpm are not modelled.
- The sim's `vss_silo` and `vuilsnippersilo` are two nodes for what is probably
  one silo (found by the code search, not changed).

## 9. Open

- **§4/§8:** the backlog is now held in the VSS; whether the intake's own
  VSS-full logic keeps a cold extruder's line running through a full warm-up
  was not measured.
- **Checks the sim cannot make yet:**
  - the pelletizer lid and lever (no lid in the sim);
  - zone and pressure limits (in the deep EREMA settings; no numbers).
- **Steps the sim does not have:**
  - the blower (the weegschaal stands for it);
  - water and knives as two steps (one heetafslag node);
  - the vacuum pump, the PCU belt and the dosing screw.
- **Not built:**
  - running with the head open into lump carts (§I5);
  - the left PCU button (§I8);
  - a physical ring button (its place on 3A/3B is not documented).
- **Lines 3C and 6.** The 3C macro's `extruder_screw` has no brain, so its
  pellet side still runs on the line's PLC. Line 6 has no macro.
- **After a save load, every extruder is OFF**, like the rest of the line: a
  load starts cold (his 2026-07-08 ruling). He now wants the plant as the last
  shift left it, and a realistic running state for a new save (rulings §I12).
  That is a separate task. **Done the same day for loads** (rulings §R1-§R4,
  `docs/audit/plant_resume_2026-09-25.md`); a new save's starting state is
  deferred.
- **The E key still clears an extruder FAULT and an e-stop at the machine.**
  §I6's principle says the HMI. Not changed here.
