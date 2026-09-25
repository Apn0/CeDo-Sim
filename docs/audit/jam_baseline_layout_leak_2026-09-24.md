# test_jam_baseline leaked its fixture gate into the operator's world_layout.json (2026-09-24)

## What was found

The operator's real `%APPDATA%/Godot/app_userdata/CeDo Simulator/world_layout.json`
(md5 `e046af7dbae5017380c1bbd36dfc7f65`, 10 554 bytes) holds one
`structure_items` entry: `{"kind": "surface", "type": "gate", "label": "3A/3B gate
(jam-baseline fixture)", "p": [...]}`. **VERIFIED** by `diff` against
`world_layout.json.bak_preharness_20260923` (md5 `741014d8…`, 9 998 bytes). That
entry is the **only** difference: `structure_items: []` became this one gate.
Its crash-recovery generation `world_layout.json.bak` has the same md5, `e046af7d…`.

On his machine that produces two red checks, and neither one is a code regression:
- `regression verdict`: "all 1 door(s)/gate(s) sit on a wall (on-wall 0)"
- `test_jam_baseline`: "DOORWAY fixture: WorldLayout.structure_items untouched (1 entries)"

## How it got there

The suite has carved the 3A/3B gate in memory since 2026-09-23 (operator
ruling: "suite builds its own gate"). A comment said the 60 s autosave was
"redirected by layout_path_override as well". **The suite never set
`layout_path_override`.** It only guarded the file with an in-memory copy that
`_finish()` wrote back.

The leak path, all read from code and confirmed by the runs below:
1. `SaveCoordinator`'s autosave runs `save_game()`, which calls `BuildMode._save_layout()`.
2. `_save_layout` puts every `surface_data` node under `_placed_root` of type
   door/gate/window into `shared`. That includes the fixture gate, which
   `_apply_layout_entry` placed there. It then sets
   `WorldLayout.structure_items = shared` and calls `WorldLayout.save()`.
3. `WorldLayout.save()` writes to `get_layout_path()`. With no override, that is
   the real `user://world_layout.json`.
4. The only thing that undid it was `_restore_files()` in `_finish()`, which runs
   after `queue_free()` and one frame of teardown.

So the fixture stays in the file whenever the process dies before `_finish()`
completes. That covers a kill, a timeout, and the documented headless teardown
segfault (CLAUDE.md, 15 of 62 boots), which lands before the restore.

### The run that did it

**VERIFIED** from `V:\_Claude\CeDo_Simulator\ready-daacfa\tools\regression\out\`:
- `test_jam_baseline.log` (mtime 17:15:10) has two `[WorldLayout] saved →
  user://world_layout.json` + `[SaveCoordinator] Autosave` pairs. It ends in
  the middle of the jam1 drive leg, with no `Result:` line and no crash banner.
- `test_gate_carve.log` (17:15:31) boots with `[BuildMode] Loaded 0 placed
  objects (per-save) + 1 shared structure`. The gate was already on disk when
  the next suite started.
- `test_line3c_seq_alignment.log` (17:15:38) is the last log of that run.
- The leftover primaries `__jambaseline___save.json` / `_factory.json` (17:14:10)
  are what a skipped `_restore_files()` leaves behind. A completed run deletes them.
- The 15:40 full harness had ONE red, `test_npc05_realworld`, so the file was
  clean at 15:40.

**INFERENCE, not recorded anywhere:** the jam suite's Godot process was stopped
3.5 min into a suite that has a 900 s timeout. The bash loop then ran two more
suites before it stopped too. That fits someone killing the harness by hand
(CLAUDE.md: "the child survives the shell"). What stopped it is not known.

`test_gate_carve` is a bystander. It snapshots `world_layout.json` at start and
writes the snapshot back at the end, so it kept the leaked bytes as they were.

### A second path: green runs left the gate in `.bak`

`AtomicFile.write_json` copies the current primary to `<path>.bak` before each
swap. A normal run did 4 autosaves. The primary was restored by hand, but the
`.bak` was not, so it still held the last leaked generation. A later read that
finds the primary damaged recovers from `.bak`, and the gate would come back.
Measured below: this happened on every green run since 2026-09-23 evening.

## Reproduction — isolated APPDATA, never the real folder

Each run got its own copy of the operator's `app_userdata` (clean layout
`741014d8…`, `settings.cfg` with `autosave_interval_s=60`, `macros/`):
`APPDATA=<scratch>/iso_X` + `godot --headless --path <worktree> res://src/tests/test_jam_baseline.tscn`.
"Killed" means `kill -9` two seconds after the log's first line matching
`^[SaveCoordinator] Autosave$`. The boot line `Autosave interval set to 60s`
does not count. A first attempt matched it and killed too early.

| run | code | outcome | `world_layout.json` after | `.bak` after |
|---|---|---|---|---|
| head_kill | HEAD `fcb53e1` | killed 76 s in | **`e046af7d…` (1 entry)**, byte-identical to the operator's file | — |
| head_full | HEAD | `PASS (16 ok, 0 fail, 0 skipped)`, 4 saves to the real path | `741014d8…` (restored) | **`e046af7d…` (1 entry)** |
| fix_kill | fixed | killed 72 s in | `741014d8…` | `741014d8…` |
| fix_full | fixed | `PASS (19 ok, 0 fail, 0 skipped)`, 0 `SCRIPT ERROR`, 5 saves all to scratch, mtime never changed | `741014d8…` | `741014d8…` |
| mutation | fixed, override cleared after the guard | `FAIL (16 ok, 3 fail)`, rc 1, all three LEAK GUARD checks red | `741014d8…` (restored) | `e046af7d…` |

Parse sweep on the fixed tree: `Result: 448 ok, 0 fail`. `test_jam_baseline`
is among the files that report `ERR_COMPILATION_FAILED` there, which the sweep
does not gate. It was on that list at HEAD too: autoload names do not exist in
`--script` mode.

## The fix (`src/tests/test_jam_baseline.gd`)

- **Redirect before boot.** `WorldLayout.layout_path_override =
  user://__jambaseline___world_layout.json` is set before MainWorld boots. If it
  does not take, the suite refuses to run (`quit(2)`). WorldLayout has already
  loaded the operator's markers, so only the writes move.
- **LEAK GUARD, three checks.**
  1. Right after the gate is built, force `bm._save_layout()` (the autosave's
     own call). The real file's md5 must be unchanged.
  2. After that same save, the scratch file must hold the fixture gate. This
     proves the write happened and was redirected, not skipped.
  3. After both drive legs, which outlast several autosaves, the real md5 must
     still be unchanged. Checked before `_finish` restores anything.
- **Restore before teardown, then again after.** A teardown segfault can no
  longer skip it.
- **Never rewrite an untouched file.** `_restore_files` skips any file whose
  bytes match the backup. With the redirect in place, the real layout is never
  opened for writing. `FileAccess.WRITE` truncates first, so the old
  unconditional restore was itself a chance to damage the file.
- The scratch layout, with its `.tmp`/`.bak`, is removed at the start and end of each run.

## Operator decision

Asked 2026-09-24 whether to remove the leaked entry from `world_layout.json`
(and `.bak`). **He chose to leave it.** On his machine `regression verdict` and
`test_jam_baseline`'s "structure_items untouched" check therefore stay red for
this environmental reason. Do not edit his `world_layout.json` to turn them
green without asking him.

## Operator ruling 2026-09-25: it is the real gate, keep it

He was shown where the entry stands in the game: renders from above and from
both sides at eye level, made on an isolated copy of his userdata. It sits on
the south-west outer wall of the southern hall, 5.9 m wide and 4.8 m tall, an
open roller door with the hall behind it. Its history, read from his backups:

| When | Gate in `world_layout.json` |
|---|---|
| 10 Jun | "3A/3B" at nearly this spot (0.6 m off), plus a second gate labelled "sad" |
| 23 Jun – 17 Aug | none |
| 31 Aug – 12 Sep | "3A/3B gate", exactly this spot |
| 13 Sep | cleared by a session, to turn two suites green |
| since 24 Sep ~17:15 | back, as this suite's leaked fixture |

Who first placed it is not recorded. His answer: **"that gate looks correct.
That is indeed the line 3A, line 3B gate through which the feeder can drive
outside to the bale lot, which is close by there."**

So the entry stays, and the four suites that went red on it now expect shared
site structure:

- **`regression verdict`** (`regression_world_save.gd`): each gate must stand
  in a wall opening that the carve cut in the REAL shell (`opening_id` on its
  placed node). The old test compared the centre with six typed wall lines of
  a building frame. Drawn through `Plant`, that frame comes out square to the
  scene axes, while the 3D shell stands diagonal, so his gate read "on-wall 0".
- **`test_jam_baseline`**: uses his gate when the loaded world already stands
  one there in a carved opening, and builds the in-memory fixture only on a
  world without it, so there are never two leaves in one opening. It checks
  that `structure_items` is unchanged from the start of the run, not that it
  is empty, and the leak guard finds the gate by position, not by label.
- **`test_project_sweep_guards` B1b**: requires no WALL entry before its wall
  placement. A gate cannot make B3 pass.
- **`test_new_world_wipe`**: a new save must have no per-save objects. Shared
  site structure (doors, gates, windows, walls) is overlaid on every save by
  design, so it is counted apart, and a second check asserts it is there.

Measured on isolated APPDATA copies (2026-09-25 02:07–02:39):

| World | regression | sweep guards | new-world wipe | jam baseline |
|---|---|---|---|---|
| his, with the gate | 18 ok, 1 skip | 19 ok | 9 ok | 19 ok, 0 skipped (his gate) |
| without the gate (23 Sep backup) | 17 ok, 2 skip | 19 ok | 9 ok | 19 ok, 0 skipped (fixture) |
| mutation: gate moved 8 m into the yard | **1 fail**: "carved 0" | — | 9 ok | — |

Parse sweep 454 ok, 0 fail; 0 `^SCRIPT ERROR` lines in every suite log; his
real `world_layout.json` unchanged (md5 `e046af7d…`).

## Still exposed (not changed here)

The other MainWorld suites that boot on the real layout without
`layout_path_override`, `test_gate_carve` among them, still write the real
`world_layout.json` during the run: `_save_layout` runs on placement and on
autosave. They restore it from an in-memory copy afterwards. Killing one mid-run
leaves the file as the world last saved it. That was harmless as long as no
fixture door existed, and it is the same mechanism as this leak.
