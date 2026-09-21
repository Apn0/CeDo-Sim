# Robustness + coverage pass — 2026-09-21

**Tree measured:** branch `feat/mill-photo-details-2026-09-06` at `58a95ba`, **plus 216 uncommitted entries**
(31 modified tracked files, 185 untracked) left by an earlier session. Godot 4.6.3, Rapier3D 0.8.34.
**Method rule:** every number below was produced this session; anything inferred is labelled **CLAIMED**.
Nothing was reverted, reset or deleted — the uncommitted work was only built on top of.

---

## 0 · Safety net (what makes this pass reversible)

| | |
|---|---|
| Pre-change snapshot | `D:\cedo_archive\snapshots\2026-09-21_pre_directive` (moved from `D:\cedo_snapshots` on 2026-09-21) — `git diff` patch, the 31 modified files, pre-edit copies of the 3 clean files I later edited, and the operator's `user://` JSON (`world_layout.json`, `macros/`, saves) |
| World ground truth | `user://world_layout.json` sha256 `f0aefcac…6ef5b` — **identical before the pass, after the 29-min baseline, after every suite run, and after all mutation runs** (checked with `sha256sum` each time) |
| Isolated lane | `D:\cedo_head_lane` (archived 2026-09-21 to `D:\cedo_archive\git_copies\cedo_head_lane`) — a copy reset to clean `HEAD`, with `config/custom_user_dir_name="CeDoSim_headlane"` (redirect proven: `OS.get_user_data_dir()` → `…/Roaming/CeDoSim_headlane`). Used to ask "is this red from the uncommitted work or from HEAD?" without touching the real tree or the real `user://` |
| Residue I created and removed | `user://feedback/20260921_014033` (written by `test_marker_tool`, which is why that suite is **not** wired) — **moved**, not deleted, to `…\moved_residue\` |
| Unverified side effect | `user://settings.cfg` mtime moved to 01:40 during the suite runs. `SettingsManager` re-saves on quit (`SettingsManager.gd:432`), so **CLAIMED** content-neutral; I had no pre-run copy to prove it. A copy taken afterwards is in the snapshot dir |

## 1 · Baseline (VERIFIED)

`bash tools/regression/run.sh` **can** launch Godot from Git Bash on this machine: `"$GODOT" --version` →
`4.6.3.stable.official`, and the full harness ran end to end in **29 min**, `== done (exit 1)`.
CLAUDE.md's "CANNOT invoke Godot via bash" warning did not reproduce (see §7).

| step | before my changes | note |
|---|---|---|
| full-tree parse sweep | **406 ok, 1 fail** | `test_line1_flow_conformance.gd:569` — `There is already a variable named "nominal"` |
| harness | exit 1, **4 failing steps** | below |

The 4 reds on the dirty tree: `test_nav_connectivity` (2 checks), `test_jam_baseline` (4), `test_gate_carve` (1),
`test_npc05_realworld` (the documented, intentional red).

## 2 · Fix: a test that never compiled

`test_line1_flow_conformance.gd` declared `var nominal` twice in one block (GDScript has no block scope), so it
did not parse. Renamed the second to `nominal_mirror` (3 lines, same pure call, no behaviour change).
Parse sweep → **407 ok, 0 fail**; the suite now runs (**84 ok, 0 fail** in the dirty tree; 70 ok at clean HEAD, whose
version of the file predates the fold rewrite).
The duplicate exists only in the **uncommitted** edit of this file — committed `main` declares `nominal` once — so
the rename stays with that local edit and is **not** part of the PR that carries this pass (2026-09-21 sync).

## 3 · Crash-safe persistence

### The defect (VERIFIED by reading every writer)

Six persistence sites opened the live file with `FileAccess.WRITE` — which **truncates it to 0 bytes immediately** —
and only then streamed the JSON in: `WorldLayout.save`, `BuildMode._save_layout`, `LineMacroStore.save_overrides`,
`GameState.save_game`, `PlaceableCatalog._save_overrides_to_disk` (+ `_append_captured_door`, a dev tool, left alone).
Only `TextureCache` used temp-file-then-rename.

The loaders then made it permanent: `BuildMode.load_layout` treated an empty/unparseable per-save file as "no data"
→ an **empty factory**; `WorldLayout._load` returned early → `is_configured()` false → demo spawns; and the 60 s
autosave overwrote the damaged file with that empty state. The exposure is real: the harness itself segfaults in
teardown ~24 % of runs (CLAUDE.md), and `BuildMode._save_layout`'s open-failure path skipped the save **silently**.

### The fix — `src/util/AtomicFile.gd`

Write: validate → `<file>.tmp` → flush + **byte-length verify** → copy the current file to `<file>.bak` *only if it is
itself good* → swap. Read: primary → `.tmp` → `.bak`; a rejected primary is **copied** (never moved) to
`.corrupt-<hash>` once. Converted: `WorldLayout` (save + load), `BuildMode` (save + load), `LineMacroStore`
(save + load), `GameState` (save + load + appearance recovery), `PlaceableCatalog` size overrides (save + load).

**A design bug I caught before it shipped.** My first draft recovered a *missing* primary from `.bak`. The game deletes
saves/macros by removing only the primary (`MainMenu._delete_save_file`, `SystemsSpawner` "new world can never
inherit a previous factory", `LineMacroStore.reset`, `GameState.clear_save`) — so a leftover `.bak` would have
**resurrected deleted saves**. Rule now: a missing primary recovers from a complete `.tmp` only (what a crash mid-swap
leaves); a `.bak` is used only when the primary exists but is damaged. `AtomicFile.delete()` removes the whole family,
and all four delete sites call it.

**Honest limits.** Godot exposes no `fsync`: this defends against a killed process and a short/failed write, not an OS
crash with the page cache unflushed. On Windows `DirAccess.rename` removes an existing destination first, so the swap
is not one syscall — which is exactly why reads also accept a complete `.tmp`.

### Proof (VERIFIED)

`src/tests/test_atomic_file.tscn` — **50 checks**, wired into `run.sh`. Every recovery check is preceded by an
undamaged-file control. It covers the helper (truncated / empty / crash-before-rename / all-corrupt / wrong root
type / validator rejection / unwritable path / UTF-8 byte length / quarantine idempotence / delete-stays-deleted)
and two end-to-end runs through the real `BuildMode` and `WorldLayout`.

**Mutation-tested five ways**, each restored byte-identical (sha256-checked):

| mutation | result |
|---|---|
| no `.bak` fallback on read | **6 red** |
| always rotate the primary to `.bak` (poisons the backup) | **2 red** |
| a missing primary may fall back to `.bak` (resurrects deletes) | **2 red** |
| the **original** `BuildMode` | **2 red — the factory loads back with 0 objects**: the reported bug, reproduced end to end |
| `WorldLayout` load reverted to a direct parse | **1 red — spawn `(0,0,0)`** |

Also: `test_layout_load` 20/20, `test_new_world_wipe` 8/8 (it was 7/8 on 09-06), `test_world_layout_coords` 11/11,
`test_qa_loop` 15/15 on the changed tree; parse sweep **409 ok, 0 fail**. A later full-harness run is in §9.

## 4 · Test coverage: 34 suites nobody ran

Diffing `src/tests/test_*.tscn` against `run.sh` found **34 runnable suites that nothing invoked** — including
`test_extruder_brain_wired`, which CLAUDE.md names as "the guard" for the extruder brain while `run.sh` never ran it.
All were run (300 s cap each, one at a time; the real world file re-hashed after each).

* **26 wired.** 11 already print `Result: PASS` and joined the main loop. 15 print a different verdict dialect
  (`Result: N ok, 0 fail`, `[TEST] … PASS` — the "verdict-dialect problem" in `test_inventory_2026-09-06.md` §6);
  loosening the shared grep would let one suite's stray "PASS" bless another, so each is gated on **its own exact
  line**, plus at least one `  ok` (a 0-check suite is a vacuous green) and no `  FAIL`. Each pattern was proven
  against its own real log and **rejects the logs of the two red suites**.
* **Not wired, on purpose:** `test_marker_tool` (writes into the operator's real feedback channel), `test_hmi_screen_base`
  (**0 checks**, no verdict), `test_leafblower_refuel` + `test_player_ladder` (checks run, no verdict line), and:
* **Red, left red:** `test_feed_belt_to_shredder_flow` (6 fail in the dirty tree; at clean HEAD it **hangs** — it calls
  `ShredderFeedBelt._find_downstream_shredder`, absent at HEAD, so `_run()` aborts before its `quit()`);
  `test_line1_automated_4bales` (3 fail dirty / 2 fail at HEAD).
* **Hang guard.** The scene loop had no timeout (CLAUDE.md documents the "idles forever" mode). `run.sh` now wraps each
  suite in `timeout --kill-after=15 ${SUITE_TIMEOUT_S:-900}`. Measured before adding it: `timeout 8` killed a hung
  headless Godot on schedule (rc 124, no process left behind). 900 s = 4.4× the slowest scene-loop suite (206 s).

## 5 · Findings that belong to the uncommitted work (NOT fixed — operator's call)

Method: overlay the operator's uncommitted files (from the pre-edit snapshot, so none of my edits can be blamed) onto
the clean-HEAD lane and run the suite.

### 5.1 `test_gate_carve` — VERIFIED cause: two rotation-sign flips in `WallOpenings.gd`

* Clean HEAD: **16 ok, 0 fail**. Dirty tree: 15 ok, **1 fail** (`PASSABILITY: at least 4/5 sample points clear (got 0)`).
* All 23 uncommitted source files on clean HEAD reproduce it. Bisect: `src/build/` (9 files) reproduces, the other 14
  do not → 4 wall/gate files → **`WallOpenings.gd` alone reproduces**.
* Inside that file the WIP makes three edits; applied one at a time to clean HEAD:
  `queue_free()`→`free()` (+ sibling-body cleanup) **passes**; the **two sign flips in `_from_box` / `_to_box`
  fail with the identical 0/5**.
* **CLAIMED** (not verified): the flips swap the rotation direction of an inverse pair while callers still pass the
  "already negated" cos/sin (`_to_box`'s own comment), so carve boxes on rotated walls mirror. Whether the flips
  were an intended fix for a real visual defect is the operator's to say.

### 5.2 `test_jam_baseline` — INTERMITTENT navmesh collapse (10 polygons vs ~275)

> **Update, same day, VERIFIED, and a correction of a correction.** The final full harness on the dirty tree
> baked **273 polygons** (suite `12 ok, 1 fail, 1 skipped`, the only fail being the HEAD-identical fixture check)
> and I first wrote this finding off as a one-off. A later isolated run of the same suite on the same tree baked
> **10 polygons / 8 vertices** again (`10 ok, 3 fail, 1 skipped`), while `test_nav_connectivity` right before it
> baked 275. So it is **intermittent, 2 collapses in 3 dirty-tree runs; 1 good run at clean HEAD**; the
> distribution is not measured (a 3-run repeat was started and killed before finishing). Cause unknown: a
> bake/timing race and the uncommitted files are both unexcluded. Do not treat it as fixed or as harmless.
> A later stray CPU-hogging process makes runs after ~03:43 timing-unreliable (see §9.3).

* Clean HEAD: baked navmesh **276 polygons / 297 vertices** (10 ok, 1 fail — the 38/39 fixture — 3 skipped).
  Dirty tree, one run: **10 polygons / 8 vertices** (9 ok, 4 fail, 1 skipped).
* **The `WallOpenings.gd` sign flips are NOT the cause of this**: clean HEAD + only those two flips bakes **276
  polygons / 297 vertices** and gives the same 10 ok / 1 fail / 3 skipped as HEAD. So `test_gate_carve` (5.1) and the
  navmesh collapse are **two separate effects** of the uncommitted work, and this one is **not yet isolated**.
* It was observed **once** in the dirty tree (the baseline run); the same tree's `test_nav_connectivity` baked 275
  polygons. Not re-run, so a one-off cannot be excluded. To bisect it, use the same overlay method with
  `test_jam_baseline` (~4 min per probe): the candidates not yet ruled out are the other 22 uncommitted source files.

### 5.3 Reds that are NOT from the uncommitted work (identical at clean HEAD)

* `test_nav_connectivity`: 8 ok / 2 fail at HEAD **and** dirty — the fixture check (`38 static placed bodies,
  LINE_3A_SEQ has 39`) and the crew-post navmesh gap. `LINE_3A_SEQ` has two `lump_cart` entries (physics props);
  the missing body is **CLAIMED** to be one of them — not identified at runtime.
* `test_jam_baseline` fixture check: same 38/39, also at HEAD.
* `test_line1_automated_4bales`, `test_npc05_realworld` (expected), `test_feed_belt_to_shredder_flow` (hangs at HEAD).

## 6 · Measured non-findings (things that looked wrong and are not)

* **Bale LOD "91 vs 92 meshes"** (`test_inventory_2026-09-06.md` §8, flagged "live performance regression"): **already
  fixed** by `58a95ba` — the close-LOD parts are statically merged; `test_bale_lod` now reads **SIMPLE 2 vs FULL 92
  (46×), 25 checks pass, 0 fail**. Measured before touching anything; no change made. It is green and `--script`-only
  (no `.tscn`), so it is still un-wired.
* **Physics engine:** boot log `PHYSICS ENGINE 3D: Rapier3D v0.8.34` — the Rapier GDExtension loads under 4.6.3.
* Import-time `WebView` / `Unrecognized UID` errors predate this pass.

## 7 · Stale claims corrected

* CLAUDE.md: "`run.sh` CANNOT invoke Godot via bash" — not reproducible here (§1). Note added there, original kept.
* `test_new_world_wipe` (1 fail on 09-06), `test_vehicle_census` (5 stranded), `test_character_customizer` (2 fail):
  all **green now**, not by my change.

## 8 · Observations, unverified or low priority

* `project.godot` carries `jolt_physics_3d/*` keys, dead under Rapier3D.
* **112 of 115** `collision_layer` / `collision_mask` assignments are bare literals (only `0`, `1`, `2` appear);
  one layer is named in project settings. Filtering is effectively unused; **CLAIMED** low value to change without a profile.
* 17 `~libgodot_rapier…TMP` files (141 MB, git-ignored) sit in `addons/godot-rapier3d/bin/` — editor DLL-reload leftovers.
* 6 headless Godot processes from 2026-09-19 (`--script test_aabb/raycast/raycast2.gd`, no `quit()`) were still running
  when this pass started. Not mine; not touched.
* `ApiKeys.gd` "encrypts" `user://api_keys.cfg` with `OS.get_unique_id()` as the password — obfuscation, not secrecy.
* `test_api_keys` had 5 failures on 09-06; not re-run here.

## 9 · Performance bench and the final harness run

### 9.1 CPU-side bench — `src/tests/bench_mainworld_perf.tscn` (new, informational, not in the harness)

Boots the real `MainWorld` from a **scratch copy** of the newest real save, with `WorldLayout.layout_path_override`
pointing at a scratch file (the bench outlives MainWorld's 60 s autosave, which ends in `WorldLayout.save()`). The real
world file hash was unchanged after every run, and the scratch files are removed.

Headless = dummy renderer, so this is **CPU only** — nothing here says anything about GPU, draw calls or fill rate.

| what | result | trust |
|---|---|---|
| **Boot hitch** | `add_child(world)` blocks **one frame for 4.3 s (run 2) / 5.0 s (run 3)** — the whole world is built synchronously in `_ready`; frame time settles within ~1.4 s after | **VERIFIED**, two runs agree (and the first run's failed 8 s warm-up sampled exactly this frame: 5,557 ms) |
| Steady-state loop | 39–48 process fps across three 240-frame windows (frame ≈ 21 ms) | wall-clock, trustworthy; the ±20 % window spread is real |
| World census (this scratch slot) | 4,426 nodes · 74 `_process` / 33 `_physics_process` · 231 static, 11 rigid, 10 character bodies, 36 areas · 28 MultiMesh nodes / **10,103 instances** · 58 `AudioStreamPlayer3D` · **117 lights** · 3,837 visible · engine object count ≈ 11,800 · ~898 MB static memory | **VERIFIED** (via `HotspotProfiler`) |
| Per-script cost attribution | **failed**: almost every delta is smaller than its own ±range (even "all processing scripts off" read 8.6 ± 15 ms) | **NOT a finding** — the run-to-run noise of the headless loop is larger than the effect |
| `TIME_PHYSICS_PROCESS` | 20–31 ms "per tick" while the loop ticked at ~60 Hz (16.7 ms) — impossible if it were tick duration | **do not quote** |

What this does establish, honestly: the "7–11 FPS / 60–130 ms" floor in `HotspotProfiler`'s header is **not** reproduced
CPU-side (≈ 45 fps headless), so it is not a CPU-script problem in this scene; whatever remains would be GPU/rendering
(117 lights, ~10 k MultiMesh instances, shadows) which this tool cannot see. The **actionable, verified** item is the
4–5 s synchronous world build — a loading-screen or staggered/async build would remove a multi-second freeze.
A useful attribution needs a quieter signal (pause the sim, fixed-step replay, many more windows), not a cleverer
estimator on this one; that limit is written into the bench's header so it is not quoted later.

### 9.2 Final harness run

**VERIFIED** — `bash tools/regression/run.sh` on the dirty tree with all changes above, started 02:20:34,
finished 02:57 (~37 min; 98 `== ` section headers in the log, up from 71). `== done (exit 1)`, and
the four failing steps are exactly the four known reds from §1, nothing new:

| failing step | status vs baseline |
|---|---|
| `test_nav_connectivity` (2 checks: 38 bodies vs 39 `LINE_3A_SEQ` entries; crew-post gap, 14.67 m short here vs 14.32 m earlier) | same, identical at clean HEAD |
| `test_jam_baseline` (1 check: 38/39 fixture; 273 polygons, 12 ok / 1 fail / 1 skipped) | this run only: the intermittent navmesh collapse did not occur (§5.2 — it did in another run); the remaining fail is identical at clean HEAD |
| `test_gate_carve` (PASSABILITY 0/5) | same (uncommitted `WallOpenings.gd` sign flips — §5.1) |
| `test_npc05_realworld` (7 ok, 2 fail) | same, documented expected red |

No `TIMEOUT` line, no `syntax error` / `unbound variable` from the `run.sh` edits.
`test_atomic_file` ends `RESULT: PASS` in the harness (the run.sh log also shows a teardown segfault
after the verdict — the known benign one). All 15 own-dialect suites print their own PASS/`0 fail`
verdict (`test_layout_load` 20 ok, `test_new_world_wipe` 8, `test_world_layout_coords` 11,
`test_extruder_screw` 12, `test_mast_jib` 14, `test_merlo_p40` 17, `test_spawn_transform` 4, the rest
`[TEST] … PASS`), and the 11 suites added to the main loop are not in the fail list.
`user://world_layout.json` sha256 still begins `f0aefcace5a3d8c5` — unchanged across the run.

Residue, **not cleaned**: 21 `__*` scratch files in `user://` (15 touched today), the usual
leftovers of teardown segfaults skipping `_restore_files()` (see CLAUDE.md). `user://feedback`
newest dir is still `20260829_050700` — no new `test_marker_tool` residue.
Not verified: that `settings.cfg` is content-identical after the run (mtime changes only).

## 10 · Not done

The remaining categories of the enhancement directive (rendering, audio, animation, AI depth, UI/UX, multiplayer…)
were **not** audited: this pass went where measurement could be done cheaply and the evidence was strong.
Anything not listed above is unexamined, not "fine".

### 9.3 FPS — measured cause (windowed, GTX 1070; `src/tests/bench_mainworld_fps.gd`)

Operator report: "fps is too low". All numbers below **VERIFIED** by the bench on a scratch copy of the
09-20 save `123123123123123123` (real world_layout hash unchanged), 1920x1080 viewport, Forward+, vsync forced
off, runs 1-3 at ~03:20-03:40 before the stray process below existed.

* **Baseline: 61 ms median frame = 16.4 fps** (4 windows 50-70 ms), 1%-low ~7-11 fps, mean ~15 fps.
* **Not the GPU, not the wrong GPU:** Godot uses the GTX 1070 (not the Intel HD 4000); GPU render time 7.4 ms,
  render CPU 9.6 ms; the same world with all world processing off renders at **14.7 ms = 68 fps**; turning the
  render loop off changed nothing (62 ms). Rendering is hidden behind the simulation.
* **It is script `_process`/`_physics_process`:** switching them off (3 alternating pairs) removes **47.6 ms**
  (pairs 46.5 / 47.6 / 48.3). Physics-server step: ~13 ms (12.2-15.7, overlaps with the scripts). Navigation
  server: not measurable (-9.3..+4.0). Only 167 nodes in 35 scripts are involved.
* **Two groups exceed noise** (solo enable on a quiet 17 ms floor; floor wandered 16-29 ms, so < ~4 ms is noise):
  **`LineFlow.gd` (1 node) +21.9 / +17.7 ms per frame**, **`NPC.gd` (9 nodes) +12.0 / +5.5 ms** (unstable).
  Everything else is within noise.
* **LineFlow breakdown** (its `tick()` steps timed in situ, 300 frames, 137 nodes; run 5, shortly after the stray
  process started, so absolute values may be slightly high): whole tick 16.9 ms/frame — `_tick_feed` 4.7,
  `_tick_route_outputs` 4.6, `_tick_plc_power_downstream` 2.7, `_tick_advanced_systems` 1.6, `_update_label` 1.1,
  `_push_scada` 1.1, rest < 0.5. `LineFlow._process` calls `tick(delta)` **every rendered frame**.
* Render side, for completeness: 1 shadowed light casts 3,062 meshes; shadows account for ~6,400 of ~8,100
  draw calls (1.85 M of 2.1 M primitives); render CPU 9.6 -> 3.9 ms and GPU 7.4 -> 5.9 ms with shadows off. Real
  but **hidden behind the sim**, so not what limits fps today.
* **NOT established:** what fps a fixed-rate LineFlow tick would give. The experiment (`PERF_STAGE=throttle`) ran
  under contention (frames 110-180 ms, throttle no better than baseline) and is **inconclusive**. Also unmeasured:
  why `_tick_feed`/`_tick_route_outputs` cost ~4.6 ms each for 137 nodes; NPC.gd's cost source; anything on a
  different save or view (the plant-centre view stage never ran).
* **Contamination:** a stray `python -` process (PID 37376, started 03:43:28, ~1 core at 100 %) from an earlier
  command of mine was running for hours; a kill was not permitted, so runs 5-6 were taken with it present.
