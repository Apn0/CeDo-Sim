# Resume on load: a saved plant comes back as it was (2026-09-25)

Operator request and rulings: `docs/plant/operator_rulings_2026-09-25.md` §R1-§R4.
A loaded save used to start cold (the 2026-07-08 decision in
`MainWorld._spawn_world_items`). He wants *"the state to be as it was at the end of
the shift before"*. Asked what comes back, he chose all four categories: the run
state, his settings, the material in the line, and the faults and alarms. How a
NEW save starts is deferred (§R2), and a machine placed new stays cold (§R3).

## 1. Before (measured)

`src/tests/probe_resume_baseline.tscn` (a probe, gates nothing) built line 3B and
started it through its own controls: line START, the extruder's start button, rpm
setpoint 80, zone 3 at 205 °C, the compactorband in HAND at 70 %. It fed the line
for 60 s, then saved and loaded into a fresh BuildMode + LineFlow.

| | before the save | after the load |
|---|---|---|
| LineFlow nodes powered | 25 of 25 | 0 |
| extruder_3b | RUNNING, 80.0 rpm, melt 215.0 °C | OFF, 0 rpm, melt 214.9 °C, cooling (212.4 °C 5 s later) |
| rpm setpoint / zone 3 | 80 / 205 °C | 60 / 215 °C |
| start sequence | SCREW, natraject commanded on | IDLE, all off |
| HAND / rpm % | 1 node / 1 node | 0 / 0 |
| kg in pipes | 7.0 | 0.0 |
| granulaat ledger | 8.9 kg | 0.0 kg |

The factory file held `id`, pose and macro metas per machine (`keys written:
layout_version, h, id, macro_anchor, macro_id, macro_index, macro_instance, rot_y,
x, y, z, rot_x`) and nothing of the run. The only runtime state any save carried
was a lump cart's `lumps_kg` / `cool_left_s`.

## 2. The design

**Where the state lives.** `src/sim/PlantResume.gd` holds the scheme. Every placed
body's run state rides in **its own factory entry** (`"run"`), beside its pose,
the way the lump cart's kg always did. So there is no key to match after a load:
LineFlow's keys (`compactorband#2`) are ordinals of discovery order, documented
as not stable across a load (`LineFlow.gd`, PER-INSTANCE ADDRESSING), and the
first suite run showed exactly that (§4.4). The line's own state (the kg ledger,
the PLC, the e-stop, the loose floor piles) rides in one `{"plant_run": …}` entry
after the version marker. Both are written by the same `_save_layout` call, so the
factory file is one snapshot. `GameState`'s `machines` slot stays unused: the
save file and the factory file are written by separate calls (the factory file
also on every placement), so splitting one snapshot across them could pair a
newer machine state with an older ledger.

**Who owns each field list.**

| state | where | fields |
|---|---|---|
| a machine's LineFlow node | `LineFlow.RESUME_NODE_FIELDS` + `node_run_state` / `restore_node_run_state` | powered, spin, buffer, in/out batches, hand_mode, manual_on, rpm_pct, per-component rpm, choked (+ the pile's position), thru / moist / contam / quality, `_was_tripped`, e-stop fault flag, the kg in each out-pipe (per edge, with the target's id and the stage timer), and for an extruder silo its level sensor and feed-stop latch (`_silo_state`, #322) |
| its observers | `RESUME_MOL_FIELDS`, `RESUME_SCREW_FIELDS`, `RESUME_CC_FIELDS`, `RESUME_DRD_*` | motor overload (trip latch, load, timer); LineFlow's own screw model; the cutter-compactor (setpoints, pot, charge, knives, trips); the DRD cycle and dryer; the NIR wrap |
| the line | `LineFlow.RESUME_LINE_FIELDS` + `line_run_state` | the shift's kg ledger, `_gran_q_accum`, feed on/off, the PLC phase/index/timer, e-stop active |
| the extruder | `ExtruderModel.RESUME_FIELDS`, `ExtruderStartSequence.RESUME_FIELDS`, `ExtruderMachine.save_run_state` | state and time in it, melt, screw rpm and **setpoint**, **zone setpoints**, actual zones, torque and trip accumulators, suction, bypass, pots, vacuum gunk, all melt pressures, die face, fault reason, natraject trip text; the start sequence (phase, step, timers, **alarm**, **natraject setting**, run commands); the pelletiser's knives; the brain's two pressure-trip latches |
| machine-owned sims | each script's `save_run_state` / `restore_run_state` | LaserFilter (screen grade + µm, loading, dP, setpoints, 318-bar latch, halt, change procedure step, spill counters), HeadFilter (both packs, online cavity, procedure), WasteContainer (kg, overflow), BezinkTank (level, valve, AUTOMAAT, setpoints), ShredderMachine (relay panel, latches, throat, spin), ShredderFeedBelt (throat, start, metal cycle, counters, fault latches), SiloLevelSensor (bridged), ScrapBin (pieces, kg), LumpCart (kg, cool left) |
| loose floor piles | `PlantResume.capture_piles` | every `floor_pile` that no placed body owns (chute spills, lump spills), by position, kg, density, size, colour, solid. Not the belt heap (a mirror of a buffer) or a DirtHotspot's own pile |

**Load order.** `BuildMode._apply_layout_entry` only stashes an entry's `run` on
the body (meta `plant_resume`); `load_layout` keeps the `plant_run` entry.
`MainWorld._resume_plant()` applies both AFTER LineFlow's rebuild (LineFlow has
no node for a body before it) and after `ShiftLifecycleManager.setup` loaded the
shift clock (the lump cart's cool timer is anchored to sim time, §4.3), and
before the SaveCoordinator exists. A save that runs while a body still holds its
stash writes the stash back (`capture_body`), so a save during the load can never
replace the saved state with the cold one it was built with.

**Power through the PLC.** A resumed powered node is pre-powered the way a
rebuild's survivor is (`_survivor_powered` + `_plc.set_stage_powered`).
Otherwise the PLC's per-tick override drops it on the first tick (mutation M3).
An extruder's own node and natraject are driven by the extruder, not the PLC.
They come back through its start sequence's restored run commands, which
`resume_world` pushes into LineFlow with `on_line_flow_rebuilt`.

**Latches announce themselves again.** A latch restored silently is one nobody in
this session can see. LineFlow re-raises OVERLOAD-ESTOP, CHUTE-BLOCKED and
MOTOR-OVERLOAD. The extruder broadcasts its state as a transition from OFF, which
raises vacuum / fault the way a live transition does, plus "overpressure" for a
latched 318-bar or MP<PEL trip. The opzetband's fault latches come back through
its own `_raise_fault`.

**What did NOT change.** The 2026-07-08 decision was right about its trigger: the
old warm boot called `force_all_powered()` on every load and started lines that
were never commissioned. That path stays unused. A stopped line comes back
stopped, because each node comes back as saved. A save written before this change
has no `run` keys, so it loads exactly as before (cold). A machine placed new is
unchanged (§R3).

## 3. The guard: `test_plant_resume` (in `run.sh`'s main loop)

`godot --headless --path . res://src/tests/test_plant_resume.tscn`: 62 checks,
three phases plus Z. It has a watchdog, a `Result:` line and a per-phase
last-line assertion (Z2). It writes only its own slot files and arms the
world_layout guard for the whole run.

- **A, running lines.** Lines 1 and 3B (70 LineFlow nodes). The setup:
  - the line is started and 3B's extruder is started through its button, at rpm
    80 and zone 3 at 205 °C;
  - the 3B compactorband is put in HAND at 70 % and the flotation tank's
    transport_1 at 60 %;
  - line 1's extruder stays OFF with its natraject setting OFF, and a lump cart
    holds 30 kg, hot;
  - the line is fed for 60 s, then saved, loaded into a fresh BuildMode and
    LineFlow, and resumed.

  The checks:
  - A2: the save wrote 71 run entries and the plant_run entry.
  - A3: before the resume, the load is the old cold world.
  - A4: a save before the resume writes the file back identical.
  - A5: all 71 bodies were applied.
  - A6: every body's run state and the line's are identical by name.
  - A7: the named settings.
  - A8: 10 s after the resume no machine dropped out, 3B's screw never left
    80 rpm, and granulate kept coming.
  - A9: the ledger residual is unchanged.
  - A10: a rebuild afterwards keeps the settings.
- **B, latched faults.** Line 3A, line 3C (for its DRD pair's cycles; its extruder
  is `extruder_screw`, which has no brain), a compactor, a TITECH sorter, a
  kopfilter, a sink_float (bezinktank), a waste bin (120 kg) and a bridged level
  sensor. Each
  fault comes from its own code path: 230 kg into 3A's extruder silo until
  its level sensor holds the feed (§I11, #322); a friction washer's `force_trip`; the
  flotation tank's reject refused by a full chute pile (`_dump_waste`, choke); 400
  kg into the VSS (e-stop); the laserfilter caked until its own physics tick trips
  318 bar, which puts the extruder in EMERGENCY_STOP; a start pressed with failing
  checks (the start alarm). After the reload:
  - B2: both DRD cycles are in the save, and every run state and the pile are
    identical by name.
  - B3: every latch is back on the same machine, and the silo's feed stop holds
    at the saved level before its first new report.
  - B4: MOTOR-OVERLOAD, CHUTE-BLOCKED, OVERLOAD-ESTOP and overpressure are raised
    again.
  - B5: a second later the tripped and choked machines are still stopped, and the
    e-stop and EMERGENCY_STOP hold.
  - B6: RESETTEN clears the restored trip. A choke reset is refused while the pile
    is full and succeeds once it is shovelled.
- **C, a real MainWorld boot** on phase A's save with the shift clock 4 h in:
  - C2: MainWorld's own load path resumed 3B's extruder (RUNNING, 80 rpm, 205 °C)
    with its node powered, and line 1's extruder is OFF with natraject OFF.
  - C3: no body is left with an unapplied stash.
  - C4: the lump cart is still hot, 7296 s to cool against 7392 saved.
  - Two LEAK GUARD checks.

Measured: `Result: PASS (62 ok, 0 fail)` on the tree merged with `origin/main`
(#322), and `PASS (60 ok, 0 fail)` before the merge (without the silo checks).
0 `^SCRIPT ERROR` lines. It ran on two worlds:
- a bare scratch APPDATA (no world_layout.json, so C boots the unconfigured world
  with the legacy props);
- a copy of the operator's `app_userdata` on D:, where C boots his authoritative
  world (`WorldLayout is authoritative`, `Resumed the plant as saved: 71 machines
  (70 LineFlow nodes, 9 machine parts)`) and the copy's world_layout.json kept
  its md5.

A run takes 60-130 s. M1-M13 of §5 ran before line 3C, B2's DRD check and the
silo checks were added (59 checks then); M14 ran on the merged tree (62).

## 4. Found while building (measured)

1. **A rebuild reset every per-component rpm.** `rebuild()`'s survivor list had
   `rpm_pct` but not `components`, so an HMI placed mid-shift put every component
   slider back to 100 %. Added to the list. A10, mutation M11.
2. **On a single-drive machine the component setter writes `rpm_pct`.**
   `_apply_component_rotor` falls back to "this component governs all rotors" and
   sets `nd["rpm_pct"] = pct`. A restore that re-applied every component brought a
   belt saved at 70 % back at 100 % (its `drive` component's default). Found by A6
   on the first green-able run. Only components with rotors of their own are
   re-applied. M10.
3. **A lump cart restored during BuildMode's load was anchored to the shift clock's
   PRE-load time.** `LumpCart.restore_fill` sets `_last_received_at` from
   `ShiftClock.shift_elapsed_seconds`, which the clock only loads later
   (`ShiftLifecycleManager.setup`). A cart saved hot therefore read as cool once
   the loaded shift time passed its cool-down. The kg stayed right, the heat did
   not. Measured with M6 (the cart's resume re-anchor removed), 4 h into the shift:
   C4 red. The resume now re-anchors it after the clock has loaded: 7296 s left,
   against 7392 s saved.
4. **LineFlow's keys moved across a reload.** The first run looked the HAND belt
   up by its key `compactorband#2` in the reloaded world and read another belt.
   The suite now names bodies by `macro_id#instance[index]id`. This is a test
   defect, recorded because the key is tempting.
5. **Two sims re-rolled their fitted parts on every boot.** The laserfilter
   re-rolled its screen grade and µm (`_pick_screen_grade`), and the kopfilter
   re-rolled both packs' mesh. Both are now saved.
6. **`_was_tripped` exists only after the first tick.** A restore that skipped
   fields the fresh node lacks would make a latched trip look like a NEW trip edge
   on the first tick: smoke roll and a SMOKE alarm. It is now set as saved. M12.

## 5. Mutation proofs

Each mutation was applied to the source alone, the suite was run under a scratch
APPDATA, and the file was restored and md5-checked. The runner is a session
scratch script, not committed. M1-M13 were made before the empty-batch
compaction in `PlantResume.batch_out` (§7) and before the merge with #322. None
of the mutated lines changed with either, and the suite is green after both. M14
was made on the merged tree. Every run printed 0 `^SCRIPT ERROR` lines.

| # | mutation | file | verdict | red checks |
|---|---|---|---|---|
| M1 | the save writes no per-body `run` | BuildMode | FAIL (27 ok, 32 fail) | A2 A5 A6 A7 A8 A9 A10 B2 B3 B4 B5 B6 C0 C2 |
| M2 | MainWorld never calls `_resume_plant()` | MainWorld | FAIL (54 ok, 5 fail) | C2 C3 C4 |
| M3 | no PLC pre-power for a resumed node | LineFlow | FAIL (58 ok, 1 fail) | A8 (the line drops on the first tick) |
| M4 | a save before the resume ignores the stash | PlantResume | FAIL (55 ok, 4 fail) | A4 C2. The early save wrote the cold state, and the MainWorld boot then had nothing to resume |
| M5 | pipes not restored (their kg folded into the machine) | LineFlow | FAIL (57 ok, 2 fail) | A6 B2. The kg total still balances, so only the by-name compare sees it |
| M6 | the lump cart is not re-anchored after the shift load | LumpCart | FAIL (58 ok, 1 fail) | C4. This is the pre-existing timing defect of §4.3 |
| M7 | the e-stop is not restored | LineFlow | FAIL (55 ok, 4 fail) | B2 B3 B4 |
| M8 | LineFlow's latches are not announced again | LineFlow | FAIL (56 ok, 3 fail) | B4 |
| M9 | the extruder model is not restored | ExtruderMachine | FAIL (45 ok, 14 fail) | A6 A7 A8 B2 B3 B4 B5 C2 |
| M10 | every component re-applied (single-drive overwrite, §4.2) | LineFlow | FAIL (56 ok, 3 fail) | A6 A7 A10 |
| M11 | rebuild's survivor list without `components` (§4.1) | LineFlow | FAIL (58 ok, 1 fail) | A10 |
| M12 | a field the fresh node lacks is skipped (`_was_tripped`, §4.6) | LineFlow | FAIL (57 ok, 2 fail) | A6 B2 |
| M13 | the laserfilter's state is not restored | LaserFilter | FAIL (56 ok, 3 fail) | A6 B2 B3 |
| M14 | the extruder silo's feed-stop state (#322) is not restored | LineFlow | FAIL (59 ok, 3 fail) | A6 B2 B3 |

## 6. Not done, and open

- **How a NEW save starts** (template vs photo-seeded, cold first shift vs a
  hand-over): deferred by the operator (§R2). Nothing built.
- **Not in any save, then or now:**
  - bales on the feed points and riding the opzetband: bales are yard or vehicle
    objects, not placed ones;
  - vehicles' loads and batteries;
  - crew activity;
  - gate leaf positions: gates come back open, the ruled default;
  - the vacuum-pot mini-game mid-way (the pot fill IS saved, in the model);
  - DirtHotspot piles;
  - the HMI screens' session state: the page shown, KWITTEREN acknowledgements,
    HmiOverlay's automaat/manual tables;
  - QaLab.
- **LineFlow drops the kg in its pipes on every rebuild**, which is not a save
  question: `_link` clears `_edges` and `_init_pipes` makes empty batches, so any
  placement mid-shift loses what was in transit. Found by the survey. Not fixed
  here, because it changes every placement. The per-edge capture written here
  (`node_run_state`'s `pipes`) is the piece a fix would reuse.
- **A BuildMode whose world never calls the resume** (SandboxWorld, the
  Line1FlowTestWorld bench) keeps its stash and writes it back on every save. That
  is harmless there (nothing applies it), but the file then carries a state the
  bench no longer has.
- **`_save_layout` now walks each body's subtree** (`find_children`) on every
  placement and autosave. Measured cost: see §7.

## 7. Verification

All numbers below were measured on 2026-09-25 at `256d1fb` plus this change,
with Godot 4.6.3 headless. Each suite ran on its own, one at a time, under a
scratch APPDATA. The full harness was not run, per the one-runner ruling.

- **Parse sweep:** `Result: 483 ok, 0 fail`. `BuildMode`, `ExtruderMachine` and
  `MainWorld` are in the not-gated compile note only for autoload names
  (`LineMacroStore`, `SimTick`), which is the sweep's known noise.
- **`test_plant_resume`:** PASS (60 ok, 0 fail) on both worlds before the merge, PASS (62 ok, 0 fail) after it (§3).
- **The suites this change touches, bare scratch APPDATA:**

  | result | suites |
  |---|---|
  | PASS | test_macro_edges_reload (62), test_save_checkpoint (22), test_atomic_file, test_lump_cart_overflow (45), test_lump_cart_coverage, test_lump_cart_speed_clamp (6), test_extruder_start_interlock (32), test_extruder_start_rpm (27), test_chute_choke (24), test_motor_trip_stops_conveying (28), test_trip_smoke (21), test_flow_node_unique (34), test_fallback_chains (110), test_hmi_fault_rearm (32), test_line1_metal_detect (27), test_vacuum_pot_minigame (35), test_extruder_melt_pressures (55), test_legacy_props_unconfigured_boot (35), test_ghost_census (11), test_belt_speed_mismatch (24), test_project_sweep_guards, test_hmi_retired, test_extruder_silo_chain (41), test_cutter_compactor |
  | own verdicts | test_layout_load 22 ok / 0 fail / 0 skip, test_new_world_wipe 11 ok / 0 fail, test_shredder_machine, test_feeder_sequence and test_bunker_shredder2_interlock PASS |
  | regression_world_save | 21 ok / 0 fail / 3 skip |
  | test_extruder_brain_wired | FAIL on 4 checks, all environmental: "the world under test is CONFIGURED" is false on a bare APPDATA |

  0 `^SCRIPT ERROR` in all of them. Exit code 139 in five is the known teardown
  segfault after the verdict.
- **On the D: copy of the operator's userdata:** test_extruder_brain_wired PASS,
  regression_world_save 23 ok / 0 fail / 1 skip.
- **`run.sh`:** `bash -n` clean; `grep -c '^for t in test_machine_sounds'` = 1;
  the diff touches only the main loop's line (`test_plant_resume` after
  `test_macro_edges_reload`) and adds a comment block.
- **Save cost** (`probe_resume_baseline`, line 3B, 32 bodies, median of 5 saves,
  two runs each, old BuildMode swapped in from its `.bak` and put back
  md5-checked). Old: 50.4 / 38.6 ms, 9.9 KB file. New: 84.8 / 43.0 ms, 34.0 KB
  (46.4 KB before empty batches were written as `{}`). The V: drive makes these
  noisy: single saves ranged 26-125 ms. In the suite, capturing 71 bodies costs
  18-32 ms of a 75-83 ms `_save_layout` (84 bodies, 81.6 KB). The file is written
  tab-indented, as it always was, which about triples its size. By key (compact
  JSON), the pipes' kg in transit are the biggest part: 5.7 of about 11 KB.

### 7.1 After the merge with `origin/main` (#322, the extruder silo's feed stop)

#322 landed while this was built, and it added LineFlow state (`_silo_state`: the
silo sensor's level and its feed-stop latch). The resume now carries it per silo
body (§2 table), guarded by B1/B3's silo checks and M14. The merge conflicted only
in `run.sh`'s main `for` line. It was resolved to ONE line with both suite lists:
`bash -n` clean, one `for t in test_machine_sounds`, no step dropped against
`origin/main`.

On the merged tree:

- **Parse sweep:** 484 ok, 0 fail.
- **`test_plant_resume`:** PASS (62 ok, 0 fail) on the bare APPDATA and on the D:
  copy of the operator's userdata. On the copy, MainWorld reported *"Resumed the
  plant as saved: 71 machines (70 LineFlow nodes, 9 machine parts)"* and the
  copy's world_layout.json md5 was unchanged.
- **Re-run, all PASS:** test_extruder_start_interlock (32), test_extruder_start_rpm
  (27), test_extruder_silo_chain (41), test_macro_edges_reload (62),
  test_chute_choke (24), test_motor_trip_stops_conveying (28),
  test_flow_node_unique (34), test_save_checkpoint (22), test_lump_cart_overflow
  (45), test_hmi_fault_rearm (32).
- **#322's own `test_extruder_silo_feed_stop`:**
  - On the D: copy of the operator's userdata: PASS (17 ok, 0 fail).
  - On the bare APPDATA: FAIL (16 ok, 1 fail), and **identically with
    `origin/main`'s own code** (my files swapped back to main's in this worktree,
    same assets). So the red is #322's, not this change's.
  - The failing check is S3, "the stopped screw's input rises less than 1.0 kg".
    It measured 0.0 → 1.1 kg on the bare world and 0.2 → 1.2 kg on the copy, so
    it sits on its own threshold. Worth widening, or measuring over more runs,
    in #322's suite. Not changed here.
