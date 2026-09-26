# Godot 4.6.3 → 4.7.2: migration trial (2026-09-26)

Plan and feature list: `docs/PLAN_godot_4.7_migration_2026-09-25.md`.
This file records what was **measured**. Steps 0-7 of the plan ran; step 8 (the
full harness on 4.7.2, and the operator's play-test) and step 9 (merge) have not.

**Verdict: nothing in this trial blocks the switch.** Every measured suite gives
the same verdict on 4.7.2 as on 4.6.3. Its checks are identical, and so are its
vehicle numbers, to the centimetre.

## Setup

| what | value |
|---|---|
| tree | worktree `V:/_Claude/CeDo_Simulator/cedo-simulator-godot-migration-7de0ab`, `c1dabb7` (= `origin/main`) |
| engines | `V:/Godot/Godot_v4.6.3-stable_win64_console.exe` (`4.6.3.stable.official.7d41c59c4`), `V:/Godot/Godot_v4.7.2-stable_win64_console.exe` (`4.7.2.stable.official.ed1daf0bf`), both put there by the operator |
| `assets/`, `.godot/`, `addons/waterbox/assets/`, `src/assets/` | robocopied (never linked) from `C:/Users/arnod/Documents/CeDo_Simulator`. 1793 files, md5 + size + mtime identical to the source |
| `APPDATA` | `D:/cedo_archive/userdata/godot47_trial/base463` (4.6.3) and `…/v472` (4.7.2): copies of the operator's `app_userdata` (766 files, 129 MB); `…/pristine` is the untouched copy |
| harness | **not run.** Suites ran one at a time (the one-runner rule) |

His real `world_layout.json` was `e046af7d…` before and after the trial, and
nothing under his real `app_userdata` was written while it ran.

## 1. The import: 4.7.2 re-imports NOTHING

Every file under `.godot/`, `assets/`, `addons/waterbox/assets/` and
`src/assets/` was fingerprinted (path, size, mtime, md5) between steps.

| step | engine | rc | time | files changed in `.godot/imported/` + `assets/` |
|---|---|---|---|---|
| F0 → F1: first `--import` of the copy | 4.6.3 | 139 (crashed on exit) | 271 s | **+88 `.import`, +280 imported files.** None of this is 4.7's doing (see below) |
| F1 → F1b: second `--import` | 4.6.3 | 0 | 57 s | **0**: the fixed point |
| F1b → F2: the 4.6.3 baseline suites | 4.6.3 | — | — | 0 |
| **F2 → F3: `--import`** | **4.7.2** | **0** | **86 s** | **0**. Only `.godot/editor/filesystem_cache10` and `project_metadata.cfg` change |

- **The 101 cache-only assets and `Merlo.fbx`**
  (`docs/audit/assets_loss_and_restore_2026-09-21.md`) are byte-identical across
  the 4.7.2 import: 102 assets, their `.import` files and 204 cache files.
  - The checker reads the restore manifest's `import-only (cache)` rows and each
    asset's `.godot/imported/<name>-<md5("res://"+path)>.*`.
  - Proven both ways: it reports UNCHANGED over the 4.6.3 import, and CHANGED
    when one cache md5 is planted.
- **The import logs carry the same three ERROR lines on both engines** (empty
  save path, WRY `WebView` not reloadable, `Unrecognized UID uid://ufjffcjjbpd5`
  = `audio/buses/default_bus_layout`), plus one godot-rust WARNING. None is new.
- **The only tracked change:** `project.godot` `config/features` `"4.6"` →
  `"4.7"`, written by the 4.7.2 import itself.

**What the first 4.6.3 import found (not a 4.7 matter).** The operator
checkout's `.godot/` has never imported `assets/reference_photos/` (74 hmi, 9
machines, 4 instructions, 1 building; no `.gdignore`), nor the cache of 18
machine WAVs (their `.import` files exist, the cache does not). A fresh copy of
his `.godot/` is therefore not at a fixed point until one import has run. Any
"the import changed nothing" gate needs that pass first. The same first import
crashed on exit (rc 139) after finishing its work, and the second one was clean.

## 2. The suites: 20 of 20 give the same verdict

Same tree and the same order on both engines. `SCRIPT ERROR` counts lines
starting `^SCRIPT ERROR`.

| run | 4.6.3 | 4.7.2 |
|---|---|---|
| parse sweep | 481 ok, 0 fail (139 = the known autoload compile noise) | **481 ok, 0 fail** (139) |
| `regression_world_save` | 23 ok, 0 fail, 1 skip | 23 ok, 0 fail, 1 skip |
| `test_extruder_brain_wired` | PASS (26 ok) | PASS (26 ok) |
| `test_legacy_props_unconfigured_boot` | 35 ok | 35 ok |
| `test_bale_yard_mass_conservation` | PASS (34 ok) | PASS (34 ok) |
| `test_humanoid_rig_conformance` | PASS (26 ok) | PASS (26 ok) |
| `test_map_labels` | 20 ok | 20 ok |
| `test_keybind_sheet` | 24 ok | 24 ok |
| `test_machine_sounds` | 80 ok | 80 ok |
| `test_atomic_file` | PASS (50 ok) | PASS (50 ok) |
| `test_jam_baseline` | 20 ok, 0 skipped | 20 ok, 0 skipped |
| `test_spawn_clearance` NOLINE / LINE | 14 ok / 16 ok | 14 ok / 16 ok |
| `test_lump_chunk_ccd` | 5 ok | 5 ok |
| `test_hmi_web` (WRY) | `PASS —` (10 ok) | `PASS —` (10 ok) |
| `test_hmi_web_gather_vals` | PASS (42 ok) | PASS (42 ok) |
| `test_map_overlay_zoom` | PASS (28 ok) | PASS (28 ok) |
| 3 `Input.parse_input_event` probes | ran | ran, same tables (below) |

- **Every suite's set of ok/FAIL/skip lines is identical** once the decimals in
  them are masked.
- **Exit 139 after the verdict:** 2 runs on 4.6.3 and 3 on 4.7.2, never the
  same suite twice. This is the known headless teardown segfault (~24 %), and
  it is why `run.sh` reads the verdict line, not the exit code.

### Numbers, not only verdicts

| measurement | 4.6.3 | 4.7.2 |
|---|---|---|
| jam baseline navmesh | 543 polygons, 610 vertices | 543, 610 |
| jam1 yard → plant | arrived 159.0 s, 281.4 m, 2.19 m from target | identical |
| jam3 indoor → outdoor | arrived 96.0 s, 160.2 m, 2.20 m | identical |
| W key through `Input.parse_input_event` (clamp truck) | fires `vehicle_forward`, +4.856 m | fires `vehicle_forward`, +4.856 m |
| W key, five vehicle types (`probe_fleet_wkey`) | −3.40 / −3.40 / +1.70 / −6.98 / −6.98 m | identical |
| signs matrix, yaw on A (3 runs each) | 76.9–83.0° | 74.5–83.0° |

**Keyboard and mouse device ids (4.7 change).** The 65 key and 5 mouse bindings
in `project.godot` are stored with `"device":0`, and 4.7 gives keyboard and
mouse events device 16/32. 4.7 converts old bindings as they load (PR #116526),
and the probes confirm it: a real `InputEventKey` still fires its action and
drives every vehicle the same way. The signs-matrix spread is run-to-run noise
on both engines, not an engine change: 4.6.3 alone spans 6° over three runs.
All signs and directions agree in all six runs.

**Both GDExtensions load on 4.7.2:** `PHYSICS ENGINE 3D: Rapier3D v0.8.34`, and
WRY's `WebView` class registers (same log lines as 4.6.3). `test_hmi_web` runs
headless, so no WebView **window** was opened. That is the play-test's job.

## 3. The one new message, deliberately NOT fixed yet

Every 4.7.2 run that builds a humanoid (11 logs) prints:

    WARNING: AnimationNodeBlendSpace2D::add_blend_point: No name provided, using safe
    index as reference. In the future, empty names will be deprecated …

It comes from `src/scenes/world/Humanoid.gd`, which calls `add_blend_point`
without a name. The `name` argument only exists in 4.7, so the fix would stop
the file compiling on 4.6.3. It stays until the switch has held, so a revert to
4.6.3 remains a plain revert. Everything else that differs between the logs is
the leak message's reworded text (`ObjectDB instances leaked at exit`).

## 4. Not measured: the rest of step 8, for the operator

- **The full harness on 4.7.2**, about 120 steps, by the harness runner or by
  hand. It needs `GODOT=V:/Godot/Godot_v4.7.2-stable_win64_console.exe` and
  `PROJ=` set to a tree with this branch and a 4.7-imported `.godot/`. This
  trial covered about 20 of those steps.
- **A windowed play-test**: WRY web HMI panels as real windows, sounds, the
  map's anti-aliased lines (4.7 draws them thinner: `MapOverlay.gd`'s three
  `draw_line/draw_arc(…, true)`), and the feel of driving.
- **The editor GUI**: nothing here opened it.
- **An export build**: whether cache-only files are included was not measured
  on 4.6.3 either.
