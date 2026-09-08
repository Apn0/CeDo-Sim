# Test inventory — can every test actually run?

**Date:** 2026-09-06 · **Commit measured:** `5a02158` ("Make single-item placement ghosts inert too")
**Question asked:** run every test in the repo; where a test cannot *execute*, fix the code so it can.
Actual assertion failures were explicitly out of scope for this pass and were left untouched.

The rule this pass was held to: **a fix must make a test RUN, never make it PASS.** No assertion was
weakened, no threshold moved, no check deleted. Where an unlocked test came back red, red is reported.

---

## 1 · Method — why this ran on D:, not in the repo

A second Claude session was live in `C:\Users\arnod\Documents\CeDo_Simulator` throughout
(`src/build/PlaceableCatalog.gd` modified 17 s before the first measurement; `src/tests/shot_line1_ghost.gd`
and three `shot_line1_ghost_*.png` renders being written). Godot 4.6.3 has **no `--user-data-dir` flag**
(verified against `--help`), so both sessions would have shared
`%APPDATA%\Godot\app_userdata\CeDo Simulator\` and corrupted each other's `user://`.

Isolation used instead:

| | |
|---|---|
| Lane | `D:\cedo_testrun` — robocopy of the full tree, 12 694 files / 5.546 GB, 0 failures |
| Pinned to | `git reset --hard 5a02158`; the dirty diff present at copy time saved to `D:\cedo_testrun_dirty_at_copy.diff.bak` |
| Private `user://` | `project.godot` → `config/use_custom_user_dir=true`, `config/custom_user_dir_name="CeDoSim_testrun"` |
| Redirect proven | `OS.get_user_data_dir()` → `C:/Users/arnod/AppData/Roaming/CeDoSim_testrun` |
| Seeded from | the real `user://`, 467 files / 74.6 MB (`EBWebView` excluded — no suite touches it) |

`tools/regression/run.sh` already parameterises `GODOT` / `PROJ` / `UD`, so **no harness edit was needed**
to run it against the lane.

**Lane fidelity, measured:** the lane's harness run reproduced `harness_fixture_branch.log`
(real lane, 2026-09-05) **failure-for-failure** — same 5 suites, nothing invented, nothing hidden.

---

## 2 · Headline

Across **62 harness steps** and **41 dead suites** — 2 062 assertions executed — exactly **one test in the
repository could not be run**, and exactly **one production-code path was failing at runtime inside a
green suite**. Both are fixed and proven. Everything else that looked broken was a reporting artefact.

---

## 3 · Fix 1 — `test_scada_dashboard_scene` could not be run at all

`src/tests/test_scada_dashboard_scene.gd` — created **2026-08-26**, `extends Node3D`, **no `.tscn`**.

* `--script` refuses it: that path requires a `SceneTree`-derived script.
* With no scene file, the scene loop has no door either.
* It is invoked by nothing — 0 hits in `run.sh`, 0 in any `.sh` / `.yml` / `.bat` / `.ps1` in the tree.

**Measured before:** `rc=124`, hung the full **301 s timeout, 0 checks executed**.

The suite itself was never the problem — `_ready()` does the work, it calls `get_tree().quit()`, and it
already prints `RESULT: PASS`, the exact literal `run.sh:306` greps. It was missing a three-line file.

**Fix:** added `src/tests/test_scada_dashboard_scene.tscn`, matching the house pattern used by
`test_qa_loop.tscn` / `test_world_layout_coords.tscn`. (112 `.tscn` files in this repo carry 0 `.uid`
sidecars, so none was added.)

**Measured after:** `rc=0`, **22 s, 29 ok / 0 fail, `RESULT: PASS`.**
Twenty-nine real assertions about `ScadaDashboard` init, parameters, state and micro-stop logic that
had never executed once in eleven days.

---

## 4 · Fix 2 — `LineFlow.gd:1033` threw 7x per boot inside a passing suite

`LineFlow._tick_dryer_pairs` cast before it validated:

```gdscript
var n3d : Node3D = nd.get("node", null) as Node3D   # 1033 — cast runs first
if n3d != null and is_instance_valid(n3d):          # 1034 — guard runs too late
```

`as Node3D` on a freed object throws `Trying to cast a freed object` and returns **before** line 1034,
so the freed-object guard the author wrote was unreachable for exactly the case it was written for.

**Measured before (solo boot):** 7 throws, 14 `LineFlow.gd:1033` frames, verdict `Result: 25 ok, 0 fail`.
The suite reported green while the code under it was failing every boot — the vacuous-green shape this
repo has been bitten by before.

**Fix:** validate, then cast.

```gdscript
var raw : Variant = nd.get("node", null)
var n3d : Node3D = (raw as Node3D) if is_instance_valid(raw) else null
if n3d != null:
```

**Measured after:** **0 throws, 0 script errors of any kind**, verdict unchanged `25 ok, 0 fail`.
Behaviour is unchanged — a freed node was never usable; it is now skipped quietly instead of throwing.

One check line differs between boots (`live_line_amps 268.68 / 269.09 / 268.85 A`). Three boots gave
three values and two *patched* boots differ from each other as much as patched-vs-unpatched, so this is
sim noise, not the patch. Every other check line is byte-identical.

---

## 5 · What looked broken but is not

| Symptom | Verdict |
|---|---|
| `Compile Error: Identifier not found: SettingsManager` / `EventBus` | Godot compiles the target script before autoloads register as global identifiers, then retries and succeeds. Appears in `--script` suites that transitively reach `PlayerController.gd:254` or `BaseVehicle.gd:1905`. The suite runs and reaches its verdict. Noise. |
| `52 file(s) parsed but reported ERR_COMPILATION_FAILED` | Documented, mutation-tested artefact of `CACHE_MODE_IGNORE` re-resolving dependencies — engine error 36, not 43. See the header of `tools/regression/parse_sweep.gd`. *(The comment there says 47; the tree now yields 52 — stale constant, cosmetic.)* |
| Exit code 139 on 4 dead suites | Teardown segfault **after** a clean verdict, with `fail=0`. `run.sh` already keys off the printed verdict for exactly this reason (`run.sh:131-142`). |
| 8 dead suites reporting "no verdict" | Reporting artefact, not a run failure — see section 6. |

---

## 6 · The verdict-dialect problem (structural, not yet acted on)

`run.sh` carries **two mutually incompatible verdict grammars**:

* scene loop, `run.sh:306` — accepts only literal `Result: PASS` / `RESULT: PASS`
* world-save block, `run.sh:142` — accepts only `^Result: [0-9]+ ok, 0 fail`

Neither accepts the other's form, and neither accepts `ALL OK` or `[TEST] … PASS`.

Every one of the 31 currently-wired scene suites emits `Result: PASS` (via format string), so **no wired
suite is affected**. The mismatch only bites on wiring, and these dead suites would report a **false red**
if wired as-is:

| Suite | Prints | Would fail scene-loop grep |
|---|---|---|
| `test_air_network` | `ALL OK` | yes |
| `test_bunker_shredder2_interlock` | `[TEST] bunker/shredder-2 MOL interlock PASS` | yes |
| `test_bunker_relay_trip` | `[TEST] bunker relay trip PASS` | yes |
| `test_shredder_machine` | `[TEST] shredder machine PASS` | yes |
| `test_shredder_feed_belt_faults` | `[TEST] ShredderFeedBelt fault handling PASS` | yes |
| `test_static_merge` | `[TEST] #224 static-merge PASS` | yes |
| `test_forced_task` | `[TEST] forced-task PASS` | yes |
| `test_feeder_sequence` | `[TEST] feeder sequence PASS` | yes |
| `test_npc_appearance_apply` | `[TEST] npc appearance apply PASS` | yes |
| `test_appearance_persistence` | `[TEST] appearance persistence PASS` | yes |
| `test_customizer_resolves_gamestate` | `[TEST] customizer resolve PASS` | yes |
| `test_production_first_gate` | `[TEST] #223 PASS` | yes |
| `test_cutter_compactor` | `Result: 53 ok, 0 fail` | yes |
| `test_layout_load` | `Result: 20 ok, 0 fail, 0 skip` | yes |

Each needs one added `print("Result: %s" % ...)` line beside the existing dialect print. **Not done** —
it only matters as part of wiring, and wiring changes the gate.

Related, unaddressed: the scene loop at `run.sh:301` passes **no `--quit-after`**, unlike every
`--script` block. `run.sh:293-296` already names the hazard in its own comment: "a green log and a hung
harness at once."

---

## 7 · Dead-suite census — 41 suites, 601 assertions, 10 failures

Every `src/tests/*.gd` carrying at least 5 assertions and invoked by nothing. Run in the isolated lane,
`CEDO_OFFLINE=1`, 300 s timeout each.

**Never run before this pass (12 suites), 11 of them green:**

| Suite | Result |
|---|---|
| `verify_mill_addons_2026_08_30` | 29 ok / 0 fail |
| `test_qa_spec` | 24 ok / 0 fail |
| `test_marker_tool` | 21 ok / 0 fail |
| `test_map_overlay_init` | 20 ok / 0 fail *(rc 139 teardown)* |
| `test_mfi_proxy` | 20 ok / 0 fail |
| `test_shredder_machine` | 18 ok / 0 fail |
| `test_bunker_relay_trip` | 17 ok / 0 fail |
| `test_appearance_persistence` | 6 ok / 0 fail |
| `test_customizer_resolves_gamestate` | 4 ok / 0 fail |
| `test_spawn_transform` | 4 ok / 0 fail *(rc 139 teardown)* |
| `test_scada_dashboard_scene` | **could not run** → fixed, now 29 ok / 0 fail |
| `test_new_world_wipe` | **7 ok / 1 fail** |

**Tallies across all 41:** 35 with `fail=0` · 5 with real failures · 4 teardown segfaults (all `fail=0`)
· 1 timeout (now fixed).

---

## 8 · The "later" pile — genuine assertion failures, untouched

**Harness (5, unchanged from the 2026-09-05 real-lane run):**

| Step | Failing check |
|---|---|
| `running regression` | `all 1 door(s)/gate(s) sit on a wall (on-wall 0)` |
| `test_nav_connectivity` | `every on-site post routes to the canteen and back` — 2 broken, both end 14.32 m short from post `(-215.6, 82.7)` |
| `test_npc05_realworld` | `the chain completed (reached DUMP and released the task)` — seated frames observed: 0 |
| `test_line3b_flow_conformance` | `the plasmaq is fed AND feeds onward across the 15 m run (in false / out true)` |
| `test_project_sweep_guards` | `B1b WorldLayout.structure_items starts empty (1 entries)` |

None is caused by a code error: **0 runtime script errors** in all five logs.

**Dead set (5):**

| Suite | Failing check |
|---|---|
| `test_api_keys` (5 fails) | encryption-key round-trip — file will not load with the generated key; saved google/openai keys do not match |
| `test_character_customizer` (2) | `Close(false) emits cancelled signal`, `Close(true) emits saved signal` |
| `test_bale_lod` (1) | `SIMPLE bale model has FAR fewer meshes than FULL (91 vs 92, >2x reduction)` — **the LOD saving is 1 mesh where Task #43 designed a >2x reduction.** Worth looking at first; it is a live performance regression, not a threshold quibble. |
| `test_new_world_wipe` (1) | `NEW world via real MainWorld → PlacedObjects EMPTY (child_count=1)` |
| `test_vehicle_census` (1) | 5 stranded vehicles: `ford_ka_2003`, `bale_clamp`, `bmw_x1_placeholder`, `merlo`, `merlo_p40` |

---

## 9 · Open, not done

1. Wire `test_scada_dashboard_scene` into `run.sh`'s scene loop — it is green and costs 22 s. One line.
2. Fix the 14 dialect verdicts (section 6) if those suites are to be wired.
3. Give the scene loop a `--quit-after`, as its own comment recommends.
4. Refresh the stale `47` to `52` in `parse_sweep.gd`'s header.
