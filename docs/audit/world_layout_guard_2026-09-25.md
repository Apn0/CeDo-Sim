# Every world-booting suite wrote the operator's world_layout.json — closed (2026-09-25)

Follow-up to `docs/audit/jam_baseline_layout_leak_2026-09-24.md`, whose last
section left this open: the jam suite was fixed, the others still wrote the real
file.

Everything below was measured in an **isolated APPDATA**: a copy of the operator's
`app_userdata` (129 MB, `world_layout.json` md5 `e046af7d…`, the leaked-gate
version he chose to keep) under `V:\_Claude\CeDo_Simulator\_iso_kind-brattain\`.
Godot resolves `user://` from `%APPDATA%`, so setting it per run sends every
write to the copy. The worktree had real copies of `assets/` and `.godot/`,
not links. His real folder was only read, once, to make the copy.

## 1. Which suites wrote it — found by grepping, then measured

**The grep.** It covered every suite `run.sh` names in a `for t in` loop or a
`res://src/tests/…` invocation (118 names), keeping those whose script mentions
`MainWorld.tscn` or `world_layout.json`, then read each one.
- **Converted, 28 suites.** 25 boot `MainWorld.tscn`, each without
  `layout_path_override`. 24 of them had `world_layout.json` on an in-memory
  `PROTECT`/`TOUCHED` list; `test_new_world_wipe` did not have it on any list.
  Two, `test_layout_load` and `test_world_layout_coords`, wrote fixtures over
  it. The 28th, `test_nested_vehicle_drift`, is a BuildMode bench whose restore
  rewrote it.
- **Already redirected, left alone.** `test_jam_baseline`,
  `test_legacy_props_spawner`, `test_legacy_props_unconfigured_boot` and
  `test_atomic_file`.
- **Only mention the file, never write it.** `test_hmi_retired`
  (`load_shared_structure = false`), `test_bale_yard_mass_conservation`,
  `test_hmi_screen_zeroing` and `test_customizer_resolves_gamestate`.

**The measurement.** The full harness ran on the HEAD suites (`a58a6a5`), with
only run.sh's new sentinel added (§3). It used an isolated APPDATA and started
from inside the tree. Result: `== done (exit 1)`, 130 steps, 95 min (01:39 →
03:15; the CPU was shared). The sentinel named **27 steps** that changed
`world_layout.json`, and every one is on the grep list. No step outside the
list changed it. Two converted suites were not named, `test_map_labels` and
`test_new_world_wipe`: at HEAD neither saved nor rewrote it (0 `saved →
user://world_layout.json` lines), and they are converted so a future change
cannot start doing so unseen.

| what happened at HEAD | steps |
|---|---|
| **a world save reached the real file.** `.bak` rotated; `[WorldLayout] saved → user://world_layout.json` in the log | running regression (`regression_world_save`, 1), `test_gate_carve` (2), `test_outdoor_route` (2), `test_line3c_identity` (1), `test_project_sweep_guards` (1) |
| **the suite's own restore rewrote it.** A truncating `FileAccess.WRITE` of the same bytes after `queue_free()`; mtime only | `repro_clamp_spawn`, `test_map_frame`, `test_nested_vehicle_drift`, `test_feeder_fetch`, `test_vehicle_spawn_frame`, `test_nav_connectivity`, `test_line3a_identity`, `test_line3b_identity`, `test_tag_snapshot`, `test_waslijn3c_overzicht`, `test_lump_cart_coverage`, `test_l3c_unit_screens`, `test_npc05_realworld`, `test_line_builder_ghost`, `test_extruder_brain_wired`, `test_vehicle_census`, `test_map_overlay_init`, `test_qa_loop`, `spawn clearance (NOLINE)`, `spawn clearance (LINE)` |
| **fixtures written over it, then the bytes put back.** mtime only | `test_layout_load`, `test_world_layout_coords` |

**In all 27, the file's md5 afterwards was `e046af7d…`, its md5 before.** A
sentinel or check on md5 alone would have reported none of them. That is why
both check mtime too, and the `.bak`. The operator's own file shows the same
signature: md5 unchanged since 2026-09-24, mtime 2026-09-25 01:10. What
rewrote it then is not known.

The 22 raw rewrites are not harmless because the bytes came back. Each is a
truncate-then-write of his world on every run, after the world teardown that
segfaults in about one boot in four. A kill between the truncate and the write
leaves 0 bytes. AtomicFile's reader then falls back to `.bak`, which the 5
saves above had rotated to whatever the test last saved.

## 2. The fix — one helper, used by every suite

`src/tests/world_layout_guard.gd` (preloaded; a fresh `class_name` is unknown to
a standalone headless run). It follows `test_jam_baseline`'s pattern and the
newer rule from #281 (`test_legacy_props_*`): the real file is never written.

- **`arm(tree)`, before `MainWorld.tscn` is instantiated.** It snapshots the
  slot's own files and the real file's md5 + mtime, together with its `.bak` and
  `.tmp`. It then sets `WorldLayout.layout_path_override =
  user://<slot>_world_layout.json`. If `get_layout_path()` does not return that
  path, it prints `FATAL` and returns false, and the suite quits 2 without
  booting a world. WorldLayout has already loaded the operator's file in its own
  `_ready`, so the world still boots on his real markers. Only the writes move.
- **`final_checks(world)`, before the verdict.** Two checks, the jam suite's
  LEAK GUARD pair:
  1. The guard deletes the scratch file and forces `BuildMode._save_layout()` on
     the world's `BuildMode` child, the autosave's own call. The scratch file
     must then exist, and `layout_changed` must have fired. Without this, "the
     real file did not change" cannot tell a redirected save from a run that
     never saved.
  2. `world_layout.json`, `.bak` and `.tmp` have the same md5 AND mtime as
     before boot. md5 alone cannot see a save that wrote identical bytes, and
     §4.1 measured exactly that on most HEAD suites.
- **`restore()`, before the world is freed and again after.** It restores the
  slot files. Unchanged bytes are not rewritten. A file the run created is
  removed, with only the `.tmp`/`.bak` the run created. Changed ones go back
  through `AtomicFile.write_text`. It never writes the real file. If that file
  changed anyway, it leaves it as is and keeps the start-of-run copy beside it,
  as `world_layout.json.<slot>-<unix>.bak`, with a `WARN` line.
- **`disarm()`** deletes the scratch file. The override stays set, because the
  process quits next and lifting it would only open a path for a late save.

**The verdict prints before the world is freed** in every suite. The headless
teardown segfault lands in world teardown (CLAUDE.md, 15 of 62 boots), so
anything printed after `queue_free()` + one frame is lost in about one run in
four.

Per suite, the only changes are these:
- `world_layout.json` is removed from `PROTECT`/`TOUCHED`.
- The suite's own `_backup_files`/`_restore_files` pair is replaced by the
  guard.
- The `arm()` call goes before boot.
- The two checks go before the verdict.
- `_finish` becomes restore → verdict → free → frame → restore → disarm → quit.

Special cases:
- **`test_layout_load`, `test_world_layout_coords`.** These did not just save
  over the file. They wrote synthetic fixtures over it on purpose, with a
  truncating `FileAccess.WRITE`, and put his bytes back at the end. A kill in
  between left a fixture as his world. The fixtures now go to the scratch path.
  For the autoload that is `get_layout_path()`. For the fresh `WorldLayout.gd`
  instances in coords, each one gets `layout_path_override`. So `_load()` reads
  the fixture and the real file is never opened for writing.
- **`test_new_world_wipe`.** `world_layout.json` was never on its backup list.
- **`test_nested_vehicle_drift`.** It boots no world. Its own restore rewrote the
  real file unconditionally, and its comment had recorded the mtime bump without
  naming the cause. That comment now names the cause. It now uses
  `real_layout_check()` only.

## 3. The sentinel in run.sh

`wl_state` prints `md5 + mtime` (or `absent`) for `$UD/world_layout.json`,
`.bak` and `.tmp`. The fingerprint is taken once at the top, and `wl_sentinel
"<step>"` runs after every step from `running regression` on: both scene loops
per suite, both spawn-clearance configs, and each of the 30 `--script` blocks.
That makes 35 call sites. A change prints `FAIL  : <step> changed the
operator's world_layout.json — left as is, NOT restored`, with the before/after
lines, and sets exit 1. The fingerprint is then re-taken, so later steps are
blamed only for their own change. The last line before `== done` names every
step that changed it. The file is never restored, because the script cannot
tell a leak from the game's own save. It watches `$UD`, so an isolated run must
pass `UD` along with `APPDATA`.

## 4. Measurements (isolated APPDATA, fresh copy of `ud_pristine` per run)

### 4.1 The converted suites, one at a time

Each converted suite ran alone on the worktree through a script that
fingerprints the copy's `world_layout.json`, `.bak` and `.tmp` before and after.
In all 28, the real family was **UNCHANGED**. Both LEAK GUARD checks passed
(one in the two suites that boot no world), and the log holds **0** `saved →
user://world_layout.json` lines. Each suite has exactly two checks more than
HEAD. Its other reds and skips are HEAD's own, for example
`test_project_sweep_guards` 18 ok / 1 fail at HEAD and 20 ok / 1 fail here.

Four reds, all present at HEAD with the same text:
- `regression_world_save`: "all 1 door(s)/gate(s) sit on a wall (on-wall 0)".
- `test_project_sweep_guards`: "B1b structure_items starts empty (1 entries)".
- `test_new_world_wipe`: "PlacedObjects EMPTY (child_count=1)".
- `test_npc05_realworld`: expected, see CLAUDE.md.

The first three read the one `structure_items` entry this copy of his file
holds. That is the leaked "3A/3B gate (jam-baseline fixture)", which he chose
to keep on 2026-09-24. `test_jam_baseline`'s "structure_items untouched" check
is red at HEAD for the same reason.

Most suites saved exactly once while armed, and that one was the forced save
in `final_checks`. Without that save, their "real file untouched" check would
have passed on a run that never exercised the redirect.

### 4.2 Mutations — every check can go red

- **M1**, in the helper: `layout_path_override` is cleared on the line after
  `arm()` verified it. That is `test_jam_baseline`'s own mutation, moved to
  where all the suites share it.
- **M2**, in `test_world_layout_coords`: the fixtures are written to
  `user://world_layout.json` again.
- **M3**, in `test_nested_vehicle_drift`: the old unconditional rewrite of the
  real file comes back.

Each suite got a fresh copy of the pristine userdata.

**All 28 suites went red on the guard's own checks, and the copy's real
family was CHANGED after each one.**
- **26 world-booting suites, M1:** both checks red. "a forced world save … went
  to user://<slot>_world_layout.json (1 save signalled, scratch NOT written)"
  and "… untouched … — CHANGED". Every suite's other checks kept their HEAD
  result, so the verdict moved by exactly 2 fails. Examples:
  - `test_gate_carve` 16 ok / 2 fail;
  - `test_l3c_unit_screens` 119 ok / 2 fail;
  - `regression_world_save` 17 ok / 3 fail (2 + the leaked-gate red);
  - `test_new_world_wipe` 7 ok / 3 fail.
- **`test_nested_vehicle_drift`, M3:** its one check red, `RESULT: FAIL (1)`.
- **`test_world_layout_coords`, M2.** The first attempt only moved the fixture
  writes back to the real path. The fresh instances still read the scratch
  file, so `_ready` died on a `SCRIPT ERROR` before any check ran. That is a
  broken mutation, not a proof. The corrected one, M2b, is the full pre-fix
  behaviour: fixtures written to and read from the real path, with no restore.
  Result: `11 ok, 1 fail`. The one red is the LEAK GUARD, "CHANGED:
  world_layout.json e046af7d…@… -> 9d973f9f…@…". All 11 coordinate checks stay
  green, so nothing but the guard would have seen it.

**md5 alone would have missed M1.** In every M1 run the rewritten file's md5
stayed `e046af7d…`: the forced save wrote the same bytes. Only its mtime and
the `.bak`'s changed. A byte-identical world save is the normal case, not a
corner case.

### 4.3 Static gates on the changed tree

- Full-tree parse sweep: `Result: 453 ok, 0 fail`.
- `lint_unused_params`: 0.
- `symbol_flow`: 0 parse-breaking, the same 44 dead as HEAD.
