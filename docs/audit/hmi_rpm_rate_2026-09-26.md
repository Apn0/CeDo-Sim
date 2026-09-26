# An HMI rpm setting counts 2-3 times in LineFlow's rate: measured, kept by ruling (2026-09-26)

Branch `claude/awesome-bhabha-e2390e`, on `main` `cae760b`. Godot 4.7.2 console,
every run headless under an isolated `APPDATA` on D:
(`D:\cedo_archive\userdata\session_rpm_pct_2026-09-26\`), LineFlow ticked by
hand at 0.1 s with `set_process(false)` after `add_child`.

In short:

- **Found and measured:** LineFlow's rate law counts one HMI speed setting two
  or three times. At 50 % on the MACHINES screen, a transport belt conveys
  12.5 % of its rate, a blower 12.5 %, a shredder 25 %. At 100 % nothing is
  off. §1.
- **Ruled: keep it.** The operator's words: "don't touch the base". This rate
  model is phase 1, and a physical material model replaces it (§2 R1). The law
  now carries a comment saying so, and `test_frictiewasser_rate` pins it on
  three machines.
- **Ruled and built: the frictiewasser.** Its two stirrers are in series, and
  the water inflow moves the film through it, not the stirrers (§2 R2). Its
  rate no longer follows any rpm setting, and switching it off still stops it
  at once (§3).
- **Ruled, not built:** averages for parallel augers are rejected. The 3C
  doseersilo belongs to the physical model (§2 R3), a separate task.

## 1. The mechanism, and what it does (MEASURED)

`LineFlow._tick_process_machines`:

    eff_rate = rate × spin × _mech_fraction(nd) × rpm_pct × _component_pct_multiplier(nd)

The same setting reaches it through up to three of those factors:

1. **`set_machine_rpm_pct(key, p)`** stores `rpm_pct = p` and calls
   `_apply_rotor_rpm`, which sets every top-level rotor's `rpm` to
   `p × nominal_rpm`. `_mech_fraction` returns the primary rotor's
   `commanded_rpm() / nominal_rpm`, which is `p` again. So a machine with a
   rotor conveys `p²`.
2. **`set_machine_component_pct(key, comp, p)`**, the MACHINES screen's
   per-motor slider (`HmiOverlay._md_build_rpm_sliders`; the `__master__` row
   that would call `set_machine_rpm_pct` is never built), sets
   `components[comp] = p`. On a machine whose component has no tagged rotor of
   its own, `_apply_component_rotor`'s single-drive path ALSO writes
   `rpm_pct = p` and drives every rotor from it. So `rpm_pct ×
   components` is `p²`, and `p³` with a rotor.
3. A component with its own tagged rotor does not touch `rpm_pct`. But when
   that rotor is the one `_mech_fraction` reads (the flotation tank's inlet,
   the frictiewasser's stirrer 1, the doseersilo's auger 1), that one slider
   counts twice and its siblings once.

No production code writes a rotor's `rpm` at runtime except those two setters
(`grep` for `.rpm =`, `set_target_rpm(`, `snap_to_rpm(` outside `src/tests/`:
only construction in `PlaceableCatalog`, where `rpm = nominal_rpm`). So the
speed `_mech_fraction` reads is always a copy of an HMI setting. It also carries
the rotor's on/off (`commanded_rpm()` is 0 once `set_running(false)`), which
makes a rotor machine stop on the tick the PLC switches it off, while a
rotor-less one coasts down with `spin`.

Measured with `src/tests/probe_hmi_speed_rate.tscn -- <line>` on all seven
macros. It builds the line alone, starts it, and runs it 60 s empty. Then, per
node (the first instance of each id), it resets every setting to 1.0, parks
50 kg in the input and sums `_moved_kg` over 10 ticks. Each figure is the ratio
against the same node's 1.0 run. Logs: `logs\before_<line>.log`.

| machine class | examples | rpm_pct 0.50 | rpm_pct 0.25 | MACHINES slider 0.50 |
|---|---|---|---|---|
| single drive, no rotor | transport_screw, cyclone, friction_sep, opzetband_*, voorraad_silo, switch_belt, u_bay, trilzeef, 3C Kop/Melt/Degas | 0.500 | 0.250 | **0.250** |
| single drive, untagged rotor(s) | blower, transport_belt, transportband_1-11, inclined_belt_8m, compactorband, mech_dryer, dewater_screw, rafter, vuilsnippersilo, mengsilo, verdeelwals, mill, vw_trommel, 3C Centr/Laser/Heet/PCU/Cband | **0.250** | **0.063** | **0.125** |
| one tagged rotor that is the drive | shredder_1, shredder_2 (`rotor`), bunker (`uittrekrol`), titech_sort, tomra_sort (`belt`) | **0.250** | **0.063** | **0.250** |
| flotation tank, 4 tagged rotors in series, `mech` = inlet | flotation_tank (1, 3A, 3B), L3C.11 | **0.250** | **0.063** | inlet **0.250**; transport_1, transport_2, outlet 0.500 |
| 3C flotation L3C.3: 4 components, no rotors | L3C.3 | 0.500 | 0.250 | each **0.250** |
| frictiewasser, 2 tagged stirrers, `mech` = stirrer_1 | friction_washer (3A) | **0.250** | **0.063** | stirrer_1 **0.375**, stirrer_2 0.750 |
| 3C doseersilo, 3 tagged augers "parallel", `mech` = auger_1 | L3C.1 | **0.250** | **0.063** | auger_1 **0.417**, auger_2 and auger_3 0.833 |

Every machine reads 1.000 with every setting at 1.0.

Not measured:
- The line's own start does not run the extruder and its natraject (extruder,
  laser_filter, heetafslag, ontwaterzeef, centrifuge, weegschaal on 1/3A/3B;
  extruder_silo and compactorband on line 1), so they moved nothing at 1.0
  (`NOFLOW`).
- 3A's `transfer_chute` (0.542 / 0.271 / 0.271) is not a clean reading. Its
  rate is above the 50 kg parked, so kg arriving from the machines measured
  before it add to its count.

The first measurement was `probe_rpm_pct_rate` (3B, five machines, branch
`claude/sweet-mcnulty-6890da`, not on `main`). It read the same 0.250 / 0.500.

## 2. The operator's rulings (CLAIMED: his answers in this session)

Arno, answering AskUserQuestion on 2026-09-26. These are choices and
recollections, not documents. They belong in
`docs/plant/operator_rulings_2026-09-26.md`, which another session's PR brings
to `main` (the wash-line timing, section W). Append them there as a lettered
section once it has landed.

**R1: the rpm law stays as it is.** Asked whether throughput should follow the
rpm linearly on every machine, he first asked back whether this was a base to
start from or end-game work, because his answer depended on it. He was told it
is phase 1: a base, on the rate model that runs today. The physical model is
the end game. He chose "Don't touch the base", whose option read: "Leave the
rate model as it is (squared/cubed) and put the effort into the physical
material model instead." So:
- the double count is KNOWN and KEPT;
- the law carries a comment pointing here;
- `test_frictiewasser_rate` C1-C4 pin today's values on three neighbours of
  the one machine that changed.

Do not linearise it without asking him.

**R2: the frictiewasser.** "They are not in parallel. They are in series." The
two stirrers stand one per chamber, and the film passes under the baffle from
the first to the second; `_m_friction_washer` builds it that way. What moves
the film is the wash water: it flows in on the input side, the level rises,
and the film overflows into the chute and is pumped on. The stirrers "certainly
have an effect, but not necessarily on throughput speed". Asked whether to take
the stirrer rpm out of its rate now (its throughput no longer drops when a
stirrer is turned down, and it still stops when switched off), he chose "Yes,
stirrers out of the rate". What the stirrers' speed does to the WASH (dirt off,
water on) was not asked, and nothing models it.

**R3: no averages; model the material.** He rejected combining parallel augers
as an average ("that does not hold up to me"). He wants the 3C doseersilo, and
the belt that feeds it, simulated physically, and asked for research into how
games do it (he named a gold-mining game where a shovel deforms the ground).
In his words, paraphrased:
- the film moves as volume blobs of about a litre;
- the belt is a moving surface, so what lies on it moves with it;
- at the belt's end nothing holds the blobs up: they fall, keeping some
  horizontal momentum;
- they stop on the silo's steel and pile up;
- an auger is a warped plane moving one way, and pushes blobs out of the pile.

Throughput then follows from the physics, with no per-screw rule: with one
screw off, the pile feeds the other. That is a separate project, offered as its
own task (research and a design doc first). Nothing here builds it.

## 3. What changed

`src/sim/LineFlow.gd`:
- `RATE_NOT_BY_RPM : Array[String] = ["friction_washer"]`, exact ids. For a
  listed machine the rate law uses `rate_mul = 1.0` (neither `rpm_pct` nor its
  components) and `_mech_run_gate(nd)` in place of `_mech_fraction(nd)`.
- `_mech_run_gate` returns 1.0 while the primary rotor's `running` is on and
  0.0 once the PLC has switched it off. That is the on/off half of
  `_mech_fraction`, without the speed. A machine with no rotor gets 1.0.
- Every other machine runs the same expression in the same operand order
  (`rate × spin × mech × rate_mul`).
- `_component_topology("friction_washer")` is now `"series"`, with a comment.
  Its rate no longer reads the multiplier, so this only keeps the table true.
- A comment on the rate law: KNOWN, KEPT, with a pointer to this doc.

The stirrers still follow their sliders (the MACHINES screen's rpm readout),
and the machine's sound still follows `spin × _mech_fraction`, which is the
stirrer's speed (`test_frictiewasser_rate` R1, R2).

## 4. After: the guard and its mutations

`src/tests/test_frictiewasser_rate.tscn`, built on `line_3a` as the probe is:

| group | checks |
|---|---|
| F0 | the tank exists; both stirrers are tagged rotors; the rotor `_mech_fraction` reads IS a stirrer (without that the old double read could not show); the id is listed; the topology is series |
| F1 | anti-vacuity: 6.000 kg in 1 s at 1.0 |
| S1-S6 | stirrer_1 0.50, stirrer_2 0.50, both 0.25, both 0, rpm_pct 0.50, rpm_pct 0.25: each 1.000 of the 1.0 rate |
| R1-R2 | stirrer_1's rotor commanded at 0.500 of nominal, stirrer_2's at 1.000; `_mech_fraction` still reads 0.500 |
| G1-G4 | HAND with AAN/UIT off: powered false; the FIRST tick moves 0.0000 kg while the spin is still 0.60; 1 s off moves 0 kg and the 50 kg stay; back in AUTO it conveys again (22.9 kg in 4 s) |
| C1-C4 | base law kept: blower rpm_pct 0.50 → 0.250, blower drive slider 0.50 → 0.125, transport_screw 0.50 → 0.500, friction_sep 0.50 → 0.500 |

`Result: PASS (22 ok, 0 fail)`, 0 `SCRIPT ERROR` lines.

Each mutation was applied to the changed `LineFlow.gd` and the suite re-run;
the file was restored after the last one (md5 `11bab217…`, the same as before
the loop):

| mutation | result | red checks |
|---|---|---|
| M1 the `RATE_NOT_BY_RPM` branch removed (old law, new `series` topology) | FAIL 16 / 6 | S1-S6 (0.250, 0.500, 0.063, 0.000, 0.250, 0.063; with `series` the stirrers combine as a minimum, so not the §1 0.375 / 0.750, which the original file reproduces in §5) |
| M2 rpm settings out, but the rotor's SPEED still read | FAIL 17 / 5 | S1, S3-S6 (S2 passes: stirrer_2 is not `mech`) |
| M3 `_mech_run_gate` always 1.0 | FAIL 20 / 2 | G2 (0.576 kg on the first tick off), G3 (4.68 kg in 1 s) |
| M4 the branch applied to every machine | FAIL 18 / 4 | C1-C4 (all 1.000) |
| M5 matched by prefix `friction` | FAIL 21 / 1 | C4 (friction_sep 1.000) |
| M6 topology back to `parallel` | FAIL 21 / 1 | F0 series |
| M7 `RATE_NOT_BY_RPM` emptied | FAIL 15 / 7 | F0 listed, S1-S6 |

## 5. Suites that set an rpm below 1.0, and suites re-run

`grep -n -E "set_machine_rpm_pct|set_machine_component_pct|\"rpm_pct\"\] *="
src/tests/*.gd` finds four files that set a value below 1.0:

- `test_belt_speed_mismatch`: a belt at rpm_pct 0.25;
- `test_bunker_relay_trip`: the bunker's `rpm_pct` = 0.1, written directly;
- `test_plant_resume`: a 3B compactorband at 0.7 and a flotation component at
  0.6;
- `probe_resume_baseline`: a probe.

None of them touches the frictiewasser. The line-3A suites run its flow at 1.0,
where the law is the same as before. Each was run once, one at a time, under
the isolated copy of the operator's `app_userdata`
(`logs\after_<suite>.log`):

| suite | why | original `LineFlow.gd` | this branch |
|---|---|---|---|
| `test_frictiewasser_rate` | new | FAIL (14 ok, 8 fail): F0 list, F0 series, S1 0.375, S2 0.750, S3 0.063, S4 0.000, S5 0.250, S6 0.063 | PASS (22 ok, 0 fail) |
| `test_belt_speed_mismatch` | rpm_pct 0.25 | PASS (24 ok, 0 fail) | PASS (24 ok, 0 fail) |
| `test_bunker_relay_trip` | rpm_pct 0.1 | `[TEST] bunker relay trip PASS`, 17 ok | same, 17 ok |
| `test_plant_resume` | 0.7 and 0.6 on 3B | PASS (64 ok, 0 fail) | PASS (64 ok, 0 fail) |
| `test_line3a_flow_conformance` | 3A flow | PASS (0 fail), 31 ok | same, 31 ok |
| `test_extruder_silo_chain` | 3A/3B kg | PASS (41 ok, 0 fail) | PASS (41 ok, 0 fail) |
| `test_fallback_chains` | 3A infeed by kg | PASS (110 ok, 0 fail) | PASS (110 ok, 0 fail) |
| `test_macro_edges_reload` | kg to each extruder | PASS (62 ok, 0 fail) | PASS (62 ok, 0 fail) |
| `test_flow_node_unique` | all macros | PASS (34 ok, 0 fail) | PASS (34 ok, 0 fail) |
| `test_machine_sounds` | sound reads `_mech_fraction` | PASS (80 ok, 0 fail) | PASS (80 ok, 0 fail) |
| `test_tag_snapshot` | `_mech_fraction`'s history | `32 ok, 0 fail, 1 skip`, `RESULT: PASS` | same |

0 `^SCRIPT ERROR` lines in all of them. `test_tag_snapshot` segfaulted in
teardown (exit 139) on both runs, AFTER its verdict line. That is the known
headless teardown crash, which is why `run.sh` gates on the verdict line.

The first run of `test_frictiewasser_rate` on the original file did not fail:
it hung. The suite named `LineFlow.RATE_NOT_BY_RPM` directly, which is a parse
error where the constant does not exist, so the scene booted with no script
and idled into the 900 s timeout. It now reads the list at runtime
(`get_script_constant_map()`), fails cleanly (the row above), and measured
the same on this branch after the change (22 ok; M7 still red).

The probe on `line_3a` after the change (`logsfter_line_3a.log`) differs from
the one before in two rows:
- `friction_washer` reads 1.000 on every setting;
- `transfer_chute`, the not-clean reading (§1), moved from 0.542 to 0.522,
  because the tank upstream of it now passes more kg while it is measured.

Every other row is identical.

The full-tree parse sweep (`tools/regression/parse_sweep.gd`) on this branch:
`Result: 491 ok, 0 fail`. It also reported 65 files as `ERR_COMPILATION_FAILED`,
a class the sweep does not gate on; none of them is a file this branch touches.

## 6. Found, not fixed

- **The bunker's MACHINES-screen slider cannot arm its relay trip.** The relay
  trip reads `rpm_pct × bunker_speed_max` (`_tick_advanced_systems`). The
  in-game slider is the `uittrekrol` component, a tagged rotor, so it never
  writes `rpm_pct`. Measured: after `uittrekrol` 0.50, `rpm_pct` still reads
  1.00 (`before_line_sort.log`). That the trip therefore never fires from the
  slider is read from the code, not measured. `test_bunker_relay_trip` writes
  `rpm_pct` directly.
- **Two settings for one motor.** On machines whose only component has its own
  tagged rotor (the shredders' `rotor`, the bunker's `uittrekrol`, the NIR
  sorters' `belt`), `rpm_pct` and that component both drive the same rotors
  (the last one written wins) and both multiply the rate. Read from the code.
- **`set_machine_rpm_pct` leaves the MACHINES slider behind.** On a
  single-drive machine it does not update `components`, so the screen's slider
  keeps its old position after a web-strip or resume write. Read from the code.
- **The `__master__` row in `HmiOverlay._md_make_rpm_row` is dead code.**
  `_md_build_rpm_sliders` only builds component rows. Read from the code.
- **The other session's 3B meter** (`WASH_TIMING`, branch
  `claude/sweet-mcnulty-6890da`) is `transport_screw`, which is linear on
  `rpm_pct`, but its MACHINES-screen `drive` slider gives `p²`. That session
  was told, and asks the operator itself.

## 7. Reproduce

    APPDATA=<scratch> godot --headless --path . res://src/tests/probe_hmi_speed_rate.tscn -- line_3a
    APPDATA=<scratch> godot --headless --path . res://src/tests/test_frictiewasser_rate.tscn
