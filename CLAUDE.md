# CeDo Simulator

Godot **4.6** simulation of a real LDPE plastic-film recycling plant (CeDo, Geleen
NL) that the operator actually worked at. Not a generic factory game — the plant
is a real place and the sim is judged against it.

**This file is the entry point. If you are a fresh session, read this before
searching — and treat every number here as re-checkable, not as gospel.**

> Sessions opened inside this repo load NO cross-project memory. That is why
> durable knowledge belongs here and in `docs/`, committed. See the last section.

## Engine

> **ONE HARNESS RUNNER (operator ruling 2026-09-25): do not run the full
> harness from a working session.** Sessions each ran `run.sh` on their own
> branch, up to four at once. That meant four slightly different trees, a full
> C: drive, and eight healthy suites red on AtomicFile short writes. Now one
> designated Claude session, the harness runner, runs the full harness on
> `origin/main` after merges, isolated on D:, and reports reds to the operator.
> Every other session:
> - runs the suites its change touches, one at a time, under a scratch `APPDATA`:
>   `APPDATA=<scratch> "$GODOT" --headless --path <tree> res://src/tests/<suite>.tscn`;
> - runs the parse sweep, plus `bash -n tools/regression/run.sh` if it touched run.sh;
> - opens and merges its PR as before. The runner tests `main` after the merge.
>
> It is enforced twice:
> - **A user-level Claude Code hook**, `~/.claude/hooks/cedo_harness_guard.py`,
>   refuses any command that EXECUTES `…/regression/run.sh` without
>   `CEDO_HARNESS_RUNNER=1`. Its 42 test cases are in
>   `cedo_harness_guard_test.py` beside it. Measured: it also reached a session
>   that was already running, without a restart.
> - **`run.sh` itself** exits 3 without that flag. It exits 4 while another full
>   harness runs, detected two ways: its lock directory `~/.cedo_harness.lock`,
>   which it takes over once the owning process is gone; and a scan of `/proc`
>   for any other `bash …/regression/run.sh`, which also catches older copies
>   of the script.
>
> **Never set the flag yourself.** If you think a full run is needed now, ask
> the operator. He runs it by hand the same way.
>
> **The runner's cycle**, for the runner session or whoever takes it over:
> 1. Fetch. If `origin/main` has not moved since the last run, check again in
>    about 20 min.
> 2. Check it out detached in the runner's worktree (it needs real copies of
>    `assets/` and `.godot/`).
> 3. Copy the operator's `app_userdata` to `D:\cedo_archive\userdata\harness_runner\`
>    and run with `APPDATA`, `UD` and `PROJ` pointing there and at the worktree.
> 4. Take the verdict from each suite's own log in `tools/regression/out/`, not
>    from the redirected stdout. `test_npc05_realworld` is the known red; any
>    other red goes to the operator.

```bash
CEDO_HARNESS_RUNNER=1 bash tools/regression/run.sh   # the harness runner only, see above
```

Engine: **`C:/Users/arnod/AppData/Local/Godot/Godot_v4.6.3-stable_win64_console.exe`**
— this is what `tools/regression/run.sh:21` defaults to, override with `GODOT=`.

**`run.sh` tests `PROJ`, and `PROJ` defaults to the operator's checkout**
(`run.sh:22`, `C:/Users/arnod/Documents/CeDo_Simulator`), not to the tree the
script lives in. From a worktree or clone you must run
`PROJ=<that tree> bash tools/regression/run.sh`, or you silently re-test the
main checkout and read its result as yours. A worktree also needs real copies
of `assets/` and `.godot/` (gitignored) to run the world suites — **copy them,
never link them**: a linked `assets/` is how the 2026-09-21 cleanup of old
worktrees emptied the real one (`docs/audit/assets_loss_and_restore_2026-09-21.md`).

**The directory you start `run.sh` from no longer matters (fixed 2026-09-25).**
`tools/audit/symbol_flow.py` resolved `extends "res://…"` against the CURRENT
directory (`--project` defaulted to `.`). Started from another tree with `PROJ=`
set, `== symbol flow audit ==` reported 38 "parse-breaking" symbols, all
members that `L3CUnitScreen.gd` and `WashingScope.gd` inherit from
`HmiScreenBase.gd`, and the harness stopped before any world suite. Started
from another drive, it crashed in `os.path.relpath`. `res://` now means the
`project.godot` directory at or above `--root`, and a missing one is an error.
Measured the same from four directories (0 parse-breaking, byte-identical
output). A planted undeclared symbol, one inheriting by `res://` path and one by
`class_name`, is reported from all of them.

For an isolated run (never the operator's `app_userdata`), redirect `APPDATA`
and pass the matching `UD`, or the world_layout sentinel watches his real
folder while Godot writes the copy:
`CEDO_HARNESS_RUNNER=1 APPDATA="$(cygpath -w <scratch>)" PROJ=<tree> UD=<scratch>/Godot/app_userdata/"CeDo Simulator" bash tools/regression/run.sh`

`project.godot` declares `config/features=PackedStringArray("4.6")`.
**Do not use `C:/Users/arnod/AppData/Local/Godot/godot.exe`** — that file is
byte-identical to `Godot_v4.2-stable_win64.exe` (`--version` → `4.2.stable`) and
cannot open a 4.6 project. An earlier version of this file recommended it; that
was wrong and would fail on the first command.

## What the harness actually proves

> **2026-08-23 — `main` as merged (`e48479b`) DID NOT COMPILE.** Merge `7b72ecf`
> reverted a one-line fix, leaving `grp_hot` (a local of a different function) in
> `PlaceableCatalog.gd:11071`; LineFlow, BuildMode and 27 test scripts were down,
> and every world suite HUNG rather than failing. The parse gate reported exit 0
> throughout, because it boots `MainMenu.tscn`. `BaleYardManager.gd` was mangled
> by the same merge. Both are repaired, the gate is replaced by a full-tree
> sweep, and the whole story — including the two vacuous detectors that were
> tried and rejected — is in `docs/AUDIT_project_sweep_2026-08-23.md`. **When a
> merge touches this repo, run the sweep before trusting anything else.**

`tools/regression/run.sh` ends `== done (exit 1) ==`. Measured **2026-09-05**
on this machine's real checkout, at `main` `00cc51c2` plus #216's derived
fixture threshold — **5 failures**. (`00cc51c2` alone, 2026-09-04, measured
**6**: the sixth was `test_jam_baseline`'s stale-40 fixture check — see the
2026-09-05 note below.)

> **2026-09-13 ultracode session fixed 3 of those 5 failures.** Remaining
> known red: `test_nav_connectivity` (crew-post ISLAND, operator call required)
> and `test_npc05_realworld` (EXPECTED, documents npc-06/07 vehicle autopilot
> defect). Both are intentionally kept red. Harness re-run is pending.

> **2026-09-21 — the warning below did NOT reproduce.** In a Git Bash session
> `"$GODOT" --version` printed `4.6.3.stable.official` and the **full**
> `bash tools/regression/run.sh` ran end to end (29 min, 71 sections,
> `== done (exit 1)`) with every Godot process launched by the script. The
> failure it describes may be specific to whichever shell or launcher produced
> it; if `No such file or directory` recurs, fall back to PowerShell as it says.
> Measured, not assumed — details in `docs/audit/robustness_and_coverage_2026-09-21.md`.

> **⚠️ (older, 2026-09-13 — see the note above) CRITICAL: `bash tools/regression/run.sh` CANNOT invoke Godot on this
> machine via bash.** When bash invokes `C:/Users/arnod/.../Godot.exe`, bash
> reports `/bin/bash: No such file or directory`. Godot only runs through
> PowerShell (`& "C:\...\Godot.exe" ...`). The harness log shows
> `== full-tree parse sweep ==` followed by `FAIL` because parse_sweep.gd
> never runs — the Godot process is silently skipped. The 9/8/2026 logs in
> `tools/regression/out/` are from an operator-run harness. Until this is
> resolved, verify tests via PowerShell directly.

Count convention, because neither the old "41 gated suites" nor "51 gated
suites" could be re-derived: the run wrote **54** logs into
`tools/regression/out/`, of which two (`parse_gate`, `parse_sweep`) are gates
rather than suites, and `last_run.log` — excluded from the 54 — carries the
`regression verdict` check. Re-derive right after a run — by mtime, not `ls | wc -l`: `out/` is never
cleared, and on 2026-09-05 the run wrote **57** logs while **73** were present
(16 strays from July–August). Do not quote this paragraph without a fresh
count.

| failing check | note |
|---|---|
| ~~`regression verdict`~~ | ~~door/gate check~~ — cleared 2026-09-13 by emptying `structure_items`. **Superseded 2026-09-25: the one entry is the operator's real 3A/3B gate and he ruled KEEP it** ("the gate through which the feeder can drive outside to the bale lot"). The check now asks whether the gate's carve cut the real shell (`opening_id`), not whether it lies on six typed wall lines: those lines sit in a typed building frame that does not line up with the 3D shell (measured 2026-09-25; the suites moved to the frame fitted from the shell the same day, see the building-frame trap) |
| ~~`test_nav_connectivity`~~ | ~~9 ok, 1 fail since #216, "requires operator to move crew posts off ISLAND"~~ — **FIXED 2026-09-23 by an operator RULING, not a navmesh change**: nobody has a post at any windzifter, and the permanent feeder is a line-1 role (Merlo + containers). `wind_sifter` left `CrewManager.ZONES["permanent_feeder"]`; on a 3A-only world the two feeders now hold their spawn spot (the suite's own `ADVIS`) instead of a post inside the blower next to the windzifter. `PASS (10 ok)` 3 of 3. `docs/audit/operator_session_2026-09-23.md` task 2 |
| `test_npc05_realworld` | EXPECTED red — the DRIVE_TO_INDOOR stall, see below. Do not silence it |
| ~~`test_line3b_flow_conformance`~~ | ~~missing input edge in LineFlow topology~~ — **FIXED 2026-09-13**: added `explicit_from_prev: true` to plasmaq entry in `LINE_3B_SEQ` (gap 15 m > MAX_LINK_DIST 14 m) |
| ~~`test_project_sweep_guards`~~ | ~~B1b WorldLayout.structure_items starts empty (1 entries)~~ — cleared 2026-09-13 by emptying the world state. **Superseded 2026-09-25**: B1b now requires no WALL entries before its wall placement, so the operator's gate no longer trips it (same for `test_new_world_wipe`, which counts shared site structure apart from per-save objects, and `test_jam_baseline`, which uses his gate when the world has it) |

> **2026-09-21 — full harness on the DIRTY tree (`58a95ba` + 216 uncommitted
> entries), before the persistence/coverage changes: `== done (exit 1)`, four
> failing steps.** `test_nav_connectivity` (2 checks — the `38 static bodies vs
> 39 LINE_3A_SEQ entries` fixture, **identical at clean HEAD**, plus the
> crew-post gap), `test_jam_baseline` (4), `test_gate_carve` (1) and
> `test_npc05_realworld` (expected). **`test_gate_carve` is red ONLY because of
> the uncommitted `src/build/WallOpenings.gd`** — bisected on a clean-HEAD copy:
> HEAD = 16 ok; the two rotation-sign flips in `_from_box` / `_to_box` alone
> reproduce `PASSABILITY 0/5`, the `queue_free()`→`free()` edit alone passes. The
> navmesh collapse in `test_jam_baseline` (10 polygons vs 276 at HEAD) is
> **INTERMITTENT** on the dirty tree — 2 collapses in 3 runs; one full harness
> baked 273 polygons and passed that part. An earlier revision of this note said
> it "did not recur"; that was one lucky run, not a measurement of the rate. Full
> evidence: `docs/audit/robustness_and_coverage_2026-09-21.md` §5.2.

> **2026-09-22 — the newest measurement; it supersedes the reds above.** The full
> harness ran on branch `feat/line1-relayout-hmi-part-fixes-2026-09-22`:
> `9b7bbd4` plus the reviewed part of that dirty tree, in a clean worktree with
> the restored `assets/`. Result: `== done (exit 1)`, 104 steps, 55 min, and
> exactly the **two known reds**:
> - `test_nav_connectivity`: the crew-post island, 14.67 m short.
> - `test_npc05_realworld`: expected, the chain does not complete.
>
> The other three reds from the dirty tree are all gone:
> - `test_gate_carve`: 16 ok, because the sign flips were left out.
> - `test_jam_baseline`: no navmesh collapse in this run (279 polygons).
> - `test_bale_yard_mass_conservation`: 34 ok. It had been broken on `main` by
>   #269, which turned `_yard_slots` into `SlotRecord` objects the test still
>   cast to `Dictionary`.
>
> The same night, the dirty tree measured **5** reds. The 3 extra were the
> WallOpenings flips, the intermittent navmesh collapse, and the #269 test break.

> **2026-09-23 — the newest measurement; it supersedes the 2026-09-22 one
> above.** Full harness on branch `claude/ready-daacfa` at `577d7d4` (seven
> commits on top of `a619b1e`: P2 trip stop, P6 cart overflow, Q2/Q4/Q5,
> phys-05 clamp, soak probe), run detached from the worktree with `PROJ=`
> set: `== done (exit 1)`, **111 steps, 35 min, 105 logs by mtime, 0
> timeouts, 3 reds** — the two known ones (`test_nav_connectivity` 14.67 m
> short, identical; `test_npc05_realworld` expected) plus `test_jam_baseline`
> at `6 polygons, 7 vertices`. That third one is the "intermittent navmesh
> collapse" and it is now root-caused: the suite waited for the polygon count
> to hold still for 60 frames, which latched onto the PREVIOUS bake's mesh
> whenever the 37-body fixture bake took longer than that on its thread (the
> world's own `bake_finished` handler printed AFTER the FAIL lines in the log;
> the operator checkout's last jam log shows the same latch at 10 polygons).
> Both suites now wait on `NavigationRegion3D.is_baking()` first, and
> `MainWorld.rebake_navigation()` queues a rebake that lands during a running
> bake; measured after the fix, jam-baseline 3 of 3 green at 69/72/71 bake
> frames (§8 of the audit doc). A **second full harness** the same night, with
> that fix, the compactor kijkglas and LineFlow at 10 Hz in place: 112 steps,
> 32 min, again 3 reds — the two operator-owned ones plus `spawn clearance
> NOLINE`, which was the SAME class of defect: the suite waited 180 frames for
> bale bodies while `BaleYardManager` refreshes its vehicle cache every 2.0 s
> of wall time, and the faster frame rate (55 → 140 fps headless) turned 180
> frames into 1.3 s. Fixed to wait on wall time; NOLINE 12 ok / LINE 11 ok
> after. So the honest red list on the branch is the two operator-owned reds.
> Eight new suites are wired into `run.sh`: `test_motor_trip_stops_conveying`,
> `test_lump_cart_overflow`, `test_lump_cart_speed_clamp`,
> `test_save_checkpoint`, `test_keybind_sheet`, `test_map_labels`,
> `test_compactor_sight_glass`, plus `test_lump_chunk_ccd` from the previous
> session. Full story: `docs/audit/overnight_enhancement_2026-09-23.md`.

> **2026-09-23 evening — the newest measurement; it supersedes the morning
> one above.** Full harness on `claude/ready-daacfa` at `99b3a35` (the P1
> belt beds committed, 15 commits on top of `a619b1e`): `== done (exit 1)`,
> **113 steps, 33 min, 106 logs by mtime, 0 timeouts, 0 SCRIPT ERROR lines,
> 2 reds** — `test_nav_connectivity` (14.67 m short, identical) and
> `test_npc05_realworld` (expected). The next commit turned the first one
> green by an operator ruling (see the table above), measured 3 of 3, so the
> branch's honest red list is **`test_npc05_realworld` alone**.
> `docs/audit/operator_session_2026-09-23.md`.

> **2026-09-23 night — the newest measurement; it supersedes the evening one
> above.** Full harness on `claude/ready-daacfa` at `99fc375` (the interactive
> session's five task commits on top: P1 belt beds, the crew ruling, P5 silo
> windows + belt speeds, P6/P2 choke + smoke, the jam-baseline doorway):
> `== done (exit 1)`, **116 steps, 36 min (22:06 → 22:42), 109 logs by mtime,
> 0 timeouts, 0 SCRIPT ERROR lines, ONE red — `test_npc05_realworld`
> (expected).** `test_nav_connectivity` PASS (10 ok) and `test_jam_baseline`
> PASS (16 ok, 0 fail, **0 skipped**) inside the run. Five suites are new
> since the morning: `test_belt_film_field`, `test_silo_level_windows`,
> `test_chute_choke`, `test_trip_smoke` in the main loop, and the jam
> baseline's own doorway. `docs/audit/operator_session_2026-09-23.md`.

> **2026-09-24 16:57 — harness run 5 at `adb6cbd` was STOPPED at 6 min by
> hand.** The operator chose to play-test next; the harness writes its test
> saves into the same `app_userdata` he plays in, so it must not run beside
> a game. The round-9 changes on top (`test_belt_speed_mismatch` reordered
> to his "chute packs first", `metal_chance` 0.25) were measured suite by
> suite (audit doc task 19); the last FULL harness is the 15:40 one below.
> Killing a detached harness needs its bash AND its Godot child — the child
> survives the shell — and only the CONSOLE binary is ever the harness's.

> **2026-09-24 15:40 — the newest measurement; it supersedes the 01:23 one
> above.** Full harness on `claude/ready-daacfa` at `8b52fc5` (the vacuum-pot
> mini-game on top of the line-1 tail fix): `== done (exit 1)`, **122 steps,
> 47 min (15:40:10 → 16:27:13), 115 logs by mtime, 0 timeouts, 0 `^SCRIPT
> ERROR` lines, ONE red — `test_npc05_realworld` (expected).** Inside:
> `test_vacuum_pot_minigame` 33 ok, `test_line1_metal_detect` 22 ok,
> `test_wet_side_beds` 31 ok, `test_nav_connectivity` 10 ok,
> `test_jam_baseline` 16 ok / 0 skipped.

> **2026-09-24 01:23 — the newest measurement; it supersedes the 00:09 one
> above.** Full harness on `claude/ready-daacfa` at `9471d84` (the wet-side
> beds and the metal-detecting first conveyor on top of `9cc6ea4`): `== done
> (exit 1)`, **121 steps, 36 min (01:23:34 → 01:59:22), 114 logs by mtime, 0
> timeouts, 0 `^SCRIPT ERROR` lines, ONE red — `test_npc05_realworld`
> (expected).** Inside: `test_wet_side_beds` 31 ok, `test_line1_metal_detect`
> 22 ok, `test_nav_connectivity` 10 ok, `test_jam_baseline` 16 ok / 0 skipped.
> Not in this run (committed after it): the line-1 tail fix, which the line-1
> suites measured green individually (task 14 in the audit doc).

> **2026-09-24 00:09 — the newest measurement; it supersedes the night one
> above.** Full harness on `claude/ready-daacfa` at `9cc6ea4` (on top of
> `99fc375`: P3 stage A vacuum pots, the doseersilo as an open tilted trough,
> per-bale weight variance + LINE_1_FOLIE, and the lint fix): `== done (exit
> 1)`, **119 steps, 41 min (00:09:29 → 00:50:49), 112 logs by mtime, 0
> timeouts, 0 SCRIPT ERROR lines, ONE red — `test_npc05_realworld`
> (expected).** Inside the run: `test_nav_connectivity` PASS (10 ok),
> `test_jam_baseline` PASS (16 ok, 0 fail, 0 skipped), the two new suites
> `test_doseersilo_trough` 14 ok and `test_bale_weight_variance` 17 ok. Two
> things worth knowing about reading that log: `grep -c 'SCRIPT ERROR'` says 1,
> and it is `test_map_labels`' own check text ("no SCRIPT ERROR above = the
> draw ran"), not an error — grep `^SCRIPT ERROR` instead; and the first
> attempt at `8d43c87` stopped at step 4, the unused-parameter lint, because
> the rebuilt doseersilo no longer reads its `size` parameter (renamed
> `_size`, the lint's own suggestion). `docs/audit/operator_session_2026-09-23.md`.

> **2026-09-21 — everything CeDo that is not this repo lives in ONE folder:
> `D:\cedo_archive`.** Old bisect/merge/verify worktrees and clones were removed
> after their uncommitted edits, untracked files and (for standalone clones) a
> verified `repo.bundle` incl. stashes were saved to `git_copies\<name>\`. Also
> there: `snapshots\` (was `D:\cedo_snapshots`), `userdata\` test copies,
> `backups\`, `CeDo_Simulator_data\`, `CeDo_assets\` (was `V:\_Claude`),
> `projects\ExtruderSim` + `projects\cedo-audio-placer`, `drive_download\`.
> Doc citations to the old paths (`CeDo_Simulator_data`, `ExtruderSim`, …) are
> provenance, not live paths — look under `D:\cedo_archive`.

> **2026-09-22 — that "14 ok, 0 skipped" is no longer true. Measured today:
> `PASS (11 ok, 0 fail, 3 skipped)`, and the suite prints
> `NOTE: 3 check(s) were NOT evaluated`.** The three route checks are gated on
> a doorway the vehicle router accepts. The doorway lived in the operator's
> `user://world_layout.json` as its one `structure_items` entry. The 2026-09-13
> session cleared that entry to turn `regression verdict` and
> `test_project_sweep_guards` B1b green (see the table above), which quietly put
> this suite back on its old vacuous green. `structure_items` is 0 today. The
> log says it plainly: `NO VEHICLE ROUTE … (no doorways exist in world_layout
> structure_items)`. Placing a gate re-arms the checks. Which of the two suites
> should own the door is an operator call. Until then, read this suite's
> `NOTE:` line, not its PASS.
>
> **2026-09-23 evening — ruled and fixed: the SUITE owns the door.** The
> operator chose "suite builds its own gate", so `test_jam_baseline` now
> carves his 3A/3B gate itself, in memory, from the entry his own
> `world_layout.json` backups still hold (`_build_line_3a`, through
> `BuildMode._apply_layout_entry`), and asserts `WorldLayout.structure_items`
> stays empty. Measured: `PASS (16 ok, 0 fail, 0 skipped)`, jam 1 arrived
> after 158.6 s, jam 3 after 94.1 s. `regression verdict` and B1b are
> untouched. `docs/audit/operator_session_2026-09-23.md` task 5.
>
> **2026-09-24 — that door LEAKED into the operator's real world_layout.json.**
> The suite's comment said the autosave was redirected by
> `layout_path_override`, but the suite never set it. Every 60 s autosave
> runs `BuildMode._save_layout`, which moves every door/gate under
> `_placed_root` into `WorldLayout.structure_items` and writes the real
> file. The fixture gate went with them. `_finish` put the bytes back, so
> the gate only stayed when a run died before `_finish`. One did: a harness
> stopped at 17:15, with its log ending mid-jam1. His file now holds
> `"3A/3B gate (jam-baseline fixture)"` (md5 `e046af7d…`). That turns
> `regression verdict` and this suite's "structure_items untouched" check
> red **on his machine only**. Even green runs left the gate in
> `world_layout.json.bak`. Reproduced byte for byte in an isolated APPDATA.
> Fixed with three changes:
> - the override is set before boot;
> - three LEAK GUARD checks on the real file's md5, mutation-proven (3 red);
> - the restore runs before teardown.
>
> Measured after: `PASS (19 ok, 0 fail, 0 skipped)`. **He chose to KEEP the
> leaked entry (asked 2026-09-24), so those two reds are environmental. Do
> not edit his world_layout.json without asking him.**
> **It is FOUR reds, not two** (full harness 2026-09-25 at `2c217c0` on a copy
> of his `app_userdata`). The same one entry also fails two more checks:
> - `test_project_sweep_guards` B1b (`structure_items starts empty (1 entries)`);
> - `test_new_world_wipe`: a new world boots with `Loaded 0 placed objects
>   (per-save) + 1 shared structure`, so `PlacedObjects` holds 1 child.
>
> `docs/audit/cycle_guard_swap_2026-09-25.md` §8.
> `docs/audit/jam_baseline_layout_leak_2026-09-24.md`.
>
> **2026-09-25 — ruled: it is his real gate, keep it.** Shown renders of where
> the entry stands (the south-west wall of the southern hall, an open roller
> door), he answered: "that is indeed the line 3A, line 3B gate through which
> the feeder can drive outside to the bale lot". So the four suites that were
> red on it now expect shared site structure instead of an empty list:
> `regression verdict` (the gate must stand in a wall opening carved in the
> real shell), `test_jam_baseline` (uses his gate when the world has one,
> builds its fixture otherwise; "structure_items as it was"),
> `test_project_sweep_guards` B1b (no WALL before its wall placement) and
> `test_new_world_wipe` (per-save objects counted apart from shared
> structure). Measured on isolated copies: his world 18 / 19 / 19 / 9 ok, a
> world without the gate 17 / 19 / 19 / 9 ok, 0 `SCRIPT ERROR`; the gate
> moved 8 m into the yard turns the carve check red.

**`test_jam_baseline` was `14 ok, 0 fail, 0 skipped` (2026-09-03) — the first time this suite
had ever evaluated all fourteen of its checks.** It was 11 ok + 3 silently
skipped for as long as the plant had no doorway, then 11 ok + 3 failing once one
existed. The pilot was never the problem: three test-side defects were, and all
three were measured with `src/tests/probe_pilot_convergence.gd` before anything
was changed. (1) The no-progress abort watched the STRAIGHT-LINE distance to the
goal, which is guaranteed to grow while a vehicle drives the 58 m detour to the
plant's only doorway — it now measures progress per waypoint, which is strictly
more sensitive to real circling. (2) `DRIVE_FRAMES` was 120 s; jam1 needs 158 s
for its 279.6 m of path. (3) jam1's goal was `_anchor`, which IS `player_spawn`
— a hull probe there returns `BLOCKED by ["Player"]`, so the forklift correctly
refused to drive through the player and orbited. It now parks 4 m short.
Measured after: `jam1 arrived after 166.3 s`, `jam3 arrived after 100.8 s`, both
2.20 m from target. Nothing was loosened — the wedge and anti-vacuity checks are
untouched and `0 skipped` is printed every run.

> **2026-09-05 — `test_jam_baseline`'s green was vacuous a SECOND time, and it
> was a stale constant.** Its fixture check `machines >= 40` was typed on
> 2026-07-22 when `LINE_3A_SEQ` had 42 entries; the 2026-08-28 rulings
> (`5f4e7c3`, `5b854d8`) took the line to 39 and the 40 never moved.
> `test_nav_connectivity` — identical check, clean scratch slot — was red on it
> the whole time and got filed as a known red. This suite kept reporting 198
> because `user://__jambaseline___factory.json` held 166 leftover machines from
> a run whose teardown segfaulted before `_restore_files()`. Sweeping that file
> out on 2026-09-03 made the suite honest and red (39). #216 derives the
> threshold from `BuildMode.LINE_3A_SEQ.size()` in both suites: harness 6 → 5.
> Full story: `docs/audit/jam_baseline_2026-09-03.md`, fourth follow-up.

Everything else is green, including `test_tag_snapshot` (29 ok — red in the
wave, fixed, see below), `test_map_frame`, `test_outdoor_route`,
`test_gate_carve`, and all nine suites #189 wired
(`test_gate_state`, `test_scada_dashboard`, `test_npc_state_api`,
`test_map_overlay_zoom`, `test_laserscope_pressure_box`,
`test_hmi_overlay_open_close`, `test_hmi_web_gather_vals`,
`test_customizer_world_bodies`, `test_shredder_feed_belt_api`).

> **2026-09-03 — gates are OPEN by default, and that is an operator ruling.**
> The real 3A/3B gate "is usually open"; the station is press-once, not a held
> deadman — top button up arrow runs it open, centre stops it mid-travel, bottom
> button (red, down arrow) runs it shut. So `Gate._ready` spawns the leaf rolled
> up, and finishing a travel calls `BaseVehicle.invalidate_route_grid()`,
> because that grid samples colliders once and caches — without it every vehicle
> already in the world keeps routing against the old leaf for the rest of the
> session. A second unswept centre-anchor constant died here too: the button
> station sat at `-height * 0.5 + 1.30`, which on a base-anchored catalog gate
> put the buttons **half a metre under the floor**, unreachable even for the
> player. Both the leaf and the station now derive from `leaf_top_y`.
> Consequence: a routable doorway un-skips three `test_jam_baseline` checks.
> They failed at first, on a bad metric — see the next paragraph.

> **2026-08-31 — `test_tag_snapshot` went red in the 61-commit wave and is
> fixed.** Bisected to `5382cca` (rotor discovery going recursive activated the
> never-before-live `_mech_fraction` gate, which read FRAME-time rotor rpm
> inside SIM-time `tick()` — a frame-less test drive stalled every rotor stage
> and e-stopped the fed doseersilo). Fix: `_mech_fraction` reads the new
> `RotatingMechanism.commanded_rpm()`. Confirmed 2026-09-02 in the full
> harness at `dc017bb` + fix: `test_tag_snapshot` 29 ok / 0 fail, and the six
> reds above are the seven measured pre-fix minus this one — the fix removes
> exactly one red and adds none. Full story, probe, and the
> user://-dependent bisect trap: `docs/audit/tag_snapshot_regression_2026-08-31.md`.

> **2026-09-03 — `test_jam_baseline` was never a regression; its GREEN was
> vacuous.** Three of its fourteen checks sit behind `_route_exists()`, and
> while the model carved no doorway the router accepted, those three were
> skipped — with nothing in `Result: PASS (11 ok, 0 fail)` to say so. The
> 2026-08-30 green measured a forklift that stalled 101 m from its target.
> `10d9ed4` (dual-skin wall carve, on `main` via `98d2cf4` at 2026-08-31 02:34)
> finally punched the operator's gate through both wall skins, the router
> started returning routes, and the three checks ran for the first time. The
> named suspects `d059007` / `1ece58a` are **cleared**. The suite now prints
> `(N ok, M fail, K skipped)` plus a `NOTE:` line, the gate leaf is a real
> collider at last (it registered **zero** shapes before), and its anchor bug —
> leaf hanging a half-height below its own opening — is fixed.
> `docs/audit/jam_baseline_2026-09-03.md`.

> **2026-09-03 — this section was mangled by a "keep both sides" merge and is
> the repair.** #190 (red-list as measured pre-fix at `32a35ce`) and #191 (the
> `commanded_rpm` fix, carrying a newer red-list measured at `dc017bb` + fix)
> both edited this exact block. The conflict was resolved by keeping both
> sides, which left `main` with two intro paragraphs, two table headers, three
> orphaned table rows stranded below a blockquote, and four direct
> contradictions — including a table row calling `test_tag_snapshot` red
> directly above a blockquote saying it was fixed. Nothing was lost, only
> duplicated. **When two PRs touch this table, take the NEWER measurement
> whole and delete the older one; never union the rows.** A merged red-list is
> not a red list, it is two of them.

> **This paragraph used to say "23 suites" and blame `test_jam_baseline`'s
> 10.0 s wedge on the parked `VolvoV40Placeholder` for the exit 1.** That is the
> stale-constant disease this file warns about, in this file. It then said
> "`test_jam_baseline` passes now", which stopped being true on 2026-08-31 and
> stayed in the file anyway — the same disease, one paragraph later. If you are
> about to quote a count or a red list from any doc here, re-run first —
> `grep -c '^FAIL  :'` on a fresh log costs seconds.

Beware of two numbers that look like the harness total and are not:
`test_l3c_unit_screens` alone reports `Result: 120 ok, 0 fail, 0 skip`, and
`regression_world_save` alone reports `16 ok, 0 fail, 2 skip`. Quoting either as
the harness result is how a multi-day hang once stayed invisible.

**History — the `1b29087` "hang" (red 2026-08-02 → fixed 2026-08-07).** The
suite never looped: `src/data/plant/l3c_unit_screens.gd` was committed with raw
newlines where `\n` escapes were intended (the L3C.6
`"ontgrendel\ndeurmaalmolen"` card title, plus a doc comment broken across
column 0), so the file **never parsed**. `test_l3c_unit_screens.gd:77`'s
`preload` of it failed, the whole test script failed to compile, the scene
booted **with no script attached**, and headless Godot idled forever with
nothing to ever call `get_tree().quit()`. The tell was at the TOP of the log —
`SCRIPT ERROR: Parse Error: Could not preload resource script` — printed before
the autoload chatter everyone stared at the tail of. The same parse failure
also silently broke every in-game L3C unit-screen tile (`L3CUnitScreen.gd:80`
preloads the same spec). Lesson: a headless suite that "hangs" right after boot
prints but before its own header has usually **failed to attach its script** —
read the head of the log for parse errors before profiling the tail.

Two consequences you must not repeat:

- **Never pipe `run.sh` into `head`/`tail`.** You get the pipe's exit status, not
  the harness's, and a truncated tail looks like a clean finish. Redirect to a
  file and read `== done (exit N) ==`.
- **`16 ok, 0 fail, 2 skip` is ONE suite** (`regression_world_save`), not the
  harness total. Quoting it as the harness result is how this hang stayed
  invisible. Both mistakes were made in this repo on 2026-08-03.

Killing a mid-run suite leaves residue: the suites back up their own slot files
(`__<slot>___save.json`, `_factory.json`, `world_layout_consumed.flag`) **in
memory only**, so a kill loses those backups. It no longer reaches
`world_layout.json`. Since 2026-09-25 every world-booting suite sends its world
saves to `user://<slot>_world_layout.json` (`src/tests/world_layout_guard.gd`)
and never writes the real file. See "Save files go through `AtomicFile`" below.

### Within the suites that do run

`run.sh` gates on the fail count only, so **skips pass silently**. Two of the
things this file used to claim were "proven" are among the skips:

| claimed proof | reality |
|---|---|
| machines inside the building, TL bars, round-trip | TL bars and round-trip genuinely checked (the fence 0-crossing check died with the fence — deleted per operator order 2026-08-03). **"Machines inside" was a false green until 2026-09-25**: it mapped each machine back through the same double-rotated frame that placed it, and printed 39/39 while 8 stood outside the shell. It now uses the frame fitted from the shell and also asks for a measured roof face above every machine (see the building-frame trap below) |
| **doors on walls** | **SKIPPED** — `no structure_items (doors) in world_layout` (`src/tests/regression_world_save.gd:204`) |
| **macro-corruption guard** | **SKIPPED** — `no operator macros present` (`regression_world_save.gd:575`) |
| top-down PNG | emitted to `tools/regression/out/topdown.png`, but the step is **non-gating** (`\|\| true`) |

Both skips are data-gated, not flaky: the regression world boots with
`[BuildMode] Loaded 0 placed objects` and `[LineFlow] 0 machines, 0 links`. So a
green run does not mean the placed-content paths were exercised. This is the
project's own Rule 3 biting the harness that Rule 3 tells you to trust — always
read `Result:` AND the `note  :` lines in `tools/regression/out/last_run.log`.

## Project rules (operator-stated, enforced in review)

1. **No build without docs.** Do not model plant components, vehicles, or how a
   machine sounds/behaves from imagination. Only from operator photos, specs, or
   explicit approval. `docs/plant/` is primary; photos illustrate.
2. **Measure, don't assert.** Every claim needs a number you actually produced.
   Prove fixes with the harness or a measured capture — never by reasoning about
   what the code should do.
3. **Bench greens prove the mock, not the feature.** `npc-05` passed 31/31 while
   moving 0.00 kg. Prove it in a real MainWorld boot, and check greens are not
   vacuous (a 0/0 suite, or a skip, is not a pass).
4. **A review must check behaviour.** Files-present + compiles + green harness is
   not a review. That combo once passed while every save force-started the whole
   line. Always add a runtime-logic pass with a concrete trigger → wrong-outcome.
5. **Never delete — always `.bak`.** Copy to `<file>.bak` before removing or
   replacing any project file. Cleanup must be reversible.
6. **Implement docs into code the first time you read them.** Do not re-read and
   re-ask. Locked facts: EREMA LF 2/406 is MOTOR-driven (not ΔMP-driven); one
   extruder per line.
7. **Dutch operator vocabulary matters** — trilzeef, maalmolen, flotatietank,
   waslijn, doseersilo. These are `PlaceableCatalog` ids and display names.
8. Every machine gets a light grime patina by default. Nothing is brand-new
   painted (global in `PlaceableCatalog._mat`).
8b. **All factory motors are CeDo-logo dark blue** (#191E6C — operator
   2026-08-28: "All motors in the factory are blue … the blue from that
   logo"). Global in `PlaceableCatalog._motor_unit`; never paint a motor
   another colour — EXCEPT where an operator ruling records one, below.
   * **KNOWN EXCEPTION — the maalmolen's own shaft motor** is cream/white,
     the same colour as the mill body (operator 2026-08-29, from the real
     3C photo: "the motor of the shaft of the mill is in the same colour as
     the rest of the mill (exception to the blue motors)"). The blue motors
     under that platform drive the FRICTION SEPARATORS, not the mill, and
     those do follow 8b. See `docs/plant/maalmolen_3c_photo_reading_2026-08-29.md`.
     Do not "fix" the mill's motor back to blue.
9. Audit renders get a **per-line unique filename** (`shot_flotation_tank_3A.png`),
   never a shared name that overwrites the previous line's shot. Renders come from
   `src/tests/shot_placeable.tscn`:
   `<godot> --path . res://src/tests/shot_placeable.tscn -- <placeable_id> [yaw] [pitch]`
10. **The Skeleton3D is the ONE animation system, and poses are MEASURED.**
   Every humanoid mesh — limbs included — must sit under a `BA_<bone>`
   BoneAttachment3D; the `HipPivot_*`/`ShoulderPivot_*` nodes are empty
   name-compat shells (`MainWorld._set_body_render_layer_split` still reads
   them). Never judge a pose from a render: a still of a 4 %-deep crouch looks
   perfectly fine. Run `res://src/tests/probe_stance_extents.tscn`, which
   prints each stance's low/high/height, and check two things — the pose
   actually changes the height, and its lowest point is **≥ −0.90** (the
   standing sole plane) so the body does not sink through the floor. Guarded by
   `test_humanoid_rig_conformance`; the full story is in
   `docs/anim_rig_unification_2026-08-28.md`.

### RESOLVED 2026-08-03 — two lump carts per extruder

The operator ruled: **"two carts per extruder — one at the voor side, one at the
achter side of the laser filter."** The old "one cart serves four extruders"
locked fact was the stale 2026-07-12 statement, superseded on 07-14/07-15; the
"open contradiction" this section used to flag was built on it. Lines 1/3A/3B
already complied; **line 3C had zero carts and now has both** via an append-only
furniture tail on `LINE_3C_SEQ` (`BuildMode.gd`, `{"at_entry": 23}` anchoring).
Proof: `src/tests/test_lump_cart_coverage.tscn` (39 checks, mutation-proven, in
the harness). Full story + the still-open questions (3C MF1/MF2 cart count,
line 6 Britas, nozzle visual asymmetry, LaserFilter's crossed aisle/wall labels):
`docs/plant/extruder_line_layout.md`, 2026-08-03 section.

### There are exactly 12 HMI panels — the generic ones are RETIRED (2026-08-15)

Operator order: *"remove unused/old HMI displays — from build menu and from
logic"*. The two pre-#165 cosmetic props `hmi_panel` and `hmi_wall` are gone.
They sat in the build menu beside the 12 real panels and opened a **"generic"
scope that saw and controlled EVERY machine in the plant** — a master panel
that exists nowhere in Geleen. `HmiScopes.SCOPES` is the whole list; every
entry in it is a first-class catalog placeable.

What that removal actually required, beyond deleting two catalog lines:

- `PlaceableCatalog.RETIRED_IDS` — a retired id is **not an alias**. There is no
  honest replacement to map it to, so `build_node()` returns `null` with the
  *reason*, and `BuildMode` counts the drops and prints one line per id per
  load. A panel that silently vanishes from a save now always has a printed
  answer. Re-saving writes the id out of existence.
- `HmiScopes.get_scope()` returns an **empty Dictionary** on a miss instead of
  the old see-all fallback, and `has_scope()` is the new gate. The fallback was
  the dangerous kind of default: an unknown id became a plant-wide master panel.
- `Hmi.gd` leaves an unscoped panel **inert** — no proximity trigger, no
  crosshair prompt, no overlay — and warns once.

Guard: `src/tests/test_hmi_retired.tscn`, in `run.sh`. 70 checks across menu,
`build_node`, scope table, runtime behaviour, an old save containing both
retired ids, and MachineFlow roles. Mutation-proven twice — re-adding the
catalog entry turns 8 red, restoring the generic fallback turns 7 red.

Do not re-add a generic panel. `mesh: "hmi_panel"` / `"hmi_wall"` in the catalog
are **geometry keys**, not placeable ids, and stay.

## Where things are

417 tracked GDScript files, 132,980 lines under `src/` (measured 2026-09-23
with `git ls-files 'src/*.gd'`; the 2026-08-23 figure was 313 / 109,663 and
the one before that ~6 months stale — treat this one as re-checkable too):

| dir | tracked `.gd` (2026-09-23) | what |
|---|---|---|
| `src/scenes/` | 136 | world, player, NPC, vehicles, HUD/HMI |
| `src/tests/` | 193 | every proof; also the render + shot tools and probes (138 are `test_*.gd`) |
| `src/sim/` | 47 | LineFlow, TagMap, MachineFlow, machine models |
| `src/autoload/` | 19 | singletons (WorldLayout, SettingsManager, AudioManager…) |
| `src/build/` | 16 | `PlaceableCatalog` + `BuildMode` — the two biggest files |
| `src/data/`, `src/operator/`, `src/util/` | 6 | plant data, operator context |

## Doc index — `docs/`

| Doc | What it holds |
|---|---|
| `docs/plant/` | **Primary source of truth for the plant — start at `docs/plant/README.md`, the corpus index.** 422 `.md` (counted 2026-09-05): SWI procedures, HMI screens, trends, photo-audit ledger |
| `docs/plant/hmi_screen_inventory_2026-07-28.md` | Ground truth for the 34 HMI mockups — the **photos are authoritative**, the mockups are layout only |
| `docs/AUDIO_sound_engine_state_2026-08-03.md` | Both audio systems, the verified RD frame for the 43 positional clips, loop-crossfade + IMA_ADPCM trap, 3 open findings |
| `docs/anim_rig_unification_2026-08-28.md` | **Why the humanoid never animated:** limb meshes sat on dead pivot nodes while the AnimationTree drove boneless bones. Also the face-up prone, the 4 %-deep crouch found by MEASURING, the poses that sank through the floor, the double-player-body (`rebuild_appearance` didn't know the name `PlayerBody`), and the NPC jump latch that cleared on the impulse tick. 12 review findings, mutation-verified |
| `docs/AUDIT_handoffs_2026-08-16.md` | **Read before trusting any handoff doc.** Two 2026-08-16 handoffs claimed "Stable / Verified"; three of five claims described code not in the repo. Records 12 unmentioned defects (4 critical, now fixed + tested), the Rule 1 blocks, and the 3 findings that were refuted |
| `docs/AUDIT_project_sweep_2026-08-23.md` | **The sweep that found `main` did not compile.** Why both harness compile checks missed it, the BaleYardManager merge repair, FULL_LOGIC_AUDIT #7 confirmed + fixed and #12 REFUTED, the headless MultiMesh limit, and what a fresh clone can/cannot prove |
| `docs/audit/pr_merge_2026-08-29.md` | **Ten bot PRs, all reported "mergeable ✅", two of which merge cleanly into a file that does not parse.** Records the `shell` collision that would have taken the harness down, why GitHub structurally cannot see it, the pre-merge `uniq -d` check, and the LineFlow correlation that looked damning and was measured wrong |
| `docs/audit/material_trace_2026-08-18.md` | Follow one bale end-to-end: the symbol-flow + material-census tools, mass-minting proven structurally closed, and the spawn-clearance check that was unsatisfiable for 4 weeks |
| `docs/audit/robustness_and_coverage_2026-09-21.md` | **Crash-safe persistence (`AtomicFile`) and 26 formerly-unrun suites now gated.** Why a save killed mid-write used to load back as an empty factory and get autosaved over; the delete-resurrection bug caught in the first draft; 5 mutation proofs. Plus the bisect that pins the `test_gate_carve` red on two rotation-sign flips in the uncommitted `WallOpenings.gd`, which reds are identical at clean HEAD, and what was measured but not touched |
| `docs/audit/overnight_enhancement_2026-09-23.md` | **The unattended 2026-09-23 run: 12 commits, every one measured first.** A MotorOverload trip that never stopped conveying, a Lumpenwagen that lost kg when full, checkpoint saves, the F1 key sheet, map labels, the cart speed clamp, the compactor kijkglas, LineFlow moved to 10 Hz (2.85 → 0.54 ms/frame), and two harness reds root-caused as frame-count races (navmesh bake, bale streaming). Two full harness runs, the operator list at the end |
| `docs/audit/cycle_guard_swap_2026-09-25.md` | **LineFlow's fallback cycle guard was called with swapped arguments and never refused an edge.** Every rerouted edge, on all seven macros, before and after the swap. The per-edge rulings: swap alone, a 3A pin, or fixtures moved to role `none`. The reload measurement (0 cycles, still wrong without pins). `test_fallback_chains` and its mutation table. Found, not fixed at the time: the sort line's topology and the intake belts discovered twice, both fixed the same day (next two rows) |
| `docs/audit/sort_line_topology_2026-09-25.md` | **The sort line (`LINE_SORT_SEQ`) was wired by guesses: its side lanes sat in one branch chain.** The opzetband fed the bunker past shredder 1, the sorters fed the final climb belt past shredder 2, and shredder 2 had no in-edge. Every link is now declared: main-chain pins, `titech`/`tomra` streams with the sorters in SERIES per lane (operator ruling 2026-09-25), and the new `{"flow": false}` SEQ flag for the reject belts (placed, not flow nodes). Before/after graphs, what settles each link, `test_sort_line_topology` (by name and by kg, incl. "every kg passes both sorter stages") and its mutation table. Open for the operator: the trilzeef, Tomra's missing sort model, the line's geometry |
| `docs/audit/intake_3a3b_topology_2026-09-25.md` | **The 3A/3B intake (`INTAKE_3A3B_SEQ`): the opzetband fed the climb belt past shredder 2, and conveyor 8 only ever fed the overflow.** Entry 0 is now a plain `transport_belt` (operator 2026-09-25: no bale is ever put on the belt into shredder 2), the head is pinned to shredder 2 → climb belt → transportband 1, and C8 → C9 (forward, edge 0) / C8 → C8.5 → U-bay (reverse) runs on an `overflow` stream that ends at the U-bay (MachineFlow `no_outlet`). Before/after dumps, `test_fallback_chains` H/G/F3/O and its mutation table. Found, not fixed: the #139 pack-up cascade stops C8.5 and C8 within 4 s of both VSSs full, against the operator's notes; the layout; old saves with the opzetband refuse to re-pin; C: measured 0 GB free |
| `docs/audit/flow_node_twins_2026-09-25.md` | **Every intake belt was two LineFlow nodes: the body's `Model` child was a placeable too.** The mechanism (`BeltBuilder.build()` in 4 belt builders, an inner `_finalize_placeable` in 10 more, 31 catalog ids), what the twin did (feed heads, a double-fed next belt, every intake film bed at 0.000 kg/m, two controllers per deck, K-mode resolving hatch colliders to the Model), the dumps before/after, `test_flow_node_unique` and its mutation table. Both things it found and left are fixed since: the shredder ghosts (next row) and the opzetband bypassing its shredder (the sort line in `sort_line_topology_2026-09-25.md`, the 3A/3B intake in `intake_3a3b_topology_2026-09-25.md`) |
| `docs/audit/shredder_ghost_placed_object_2026-09-25.md` | **A shredder placement ghost was a `placed_object`:** `ShredderMachine._ready` added the group without knowing it was a ghost, so a raw `build_node(id, true)` became a LineFlow feed head. Measured: BuildMode rebuilds LineFlow with the ghost alive on every placement, but its own ghost was never a flow node (`_make_preview_inert` strips the script first). The fix, why real shredders are unchanged, `test_ghost_census` (all 200 catalog ghosts) and its mutation table. Found, not fixed: raw ghosts still join their own behaviour groups (`shredder`, `lump_cart`, `waste_container`, `hmi`, …) |
| `docs/audit/aborted_phase_guard_2026-09-25.md` | **A suite lost a whole phase and still printed PASS, and `run.sh` would have passed it.** With C: full, `test_macro_edges_reload`'s phase-D save failed and the typed read after it was a runtime error: `PASS (51 ok)` instead of 60. The fix: the suite checks its save (D-1) and asserts every phase reached its last line (Z3); `run.sh` ends with `script_error_census.sh`, which fails any log of the run with a `^SCRIPT ERROR` line (only `parse_sweep.log` excused); `test_route_goal_clearance`'s pre-autoload compile noise removed. Census tests on real and fabricated logs, the suite's mutation table, the full harness |
| `docs/audit/macro_edges_reload_2026-09-25.md` | **A macro line's explicit flow edges (pins, streams, split, recirc) now survive a save → load.** Before, a reloaded world had 0 of them (47 tagged nodes → 0). One function, `BuildMode.macro_flow_edges`, serves the build and the load, and the refactored build is diffed identical to the old one (269 rows). Covers `macro_instance`, the hole and dead-end rules for deleted machines, when a save is refused, the guard `test_macro_edges_reload` and its mutation matrix, and what the load does with every macro-bearing layout on this machine |
| `docs/audit/hmi_fault_rearm_2026-09-24.md` | **HMI alarms: KWITTEREN acknowledges one occurrence of an alarm (#279), and the same EREMA code on two lines is two alarms (#282).** Probes, the guard suites `test_hmi_fault_rearm` and `test_hmi_fault_per_line` with their mutation matrices, and the full harness on `04eaa77`. **Open:** every panel lists every line's EREMA alarms (found by reading the code, not measured); Afschermen does not exist (the Onderdrukt tab reads a table nothing writes); RESETTEN clearing every acknowledgement has not been ruled on |
| `docs/audit/operator_session_2026-09-23.md` | **The interactive 2026-09-23 session: tasks ranked by operator effort against sim impact, each answered by AskUserQuestion then built and measured.** Task 1: film beds on every belt (P1), the inclined belt's deck running the wrong diagonal, the cost probe, the renders; per-task evidence and the open questions each one left |
| `docs/DESIGN_inworld_hmi_2026-09-25.md` | **HMI screens IN the world + hold-F interact mode — SURVEY and operator decisions, nothing built.** Why the 7 web panels cannot go on a mesh (godot_wry is a native window), the pixel budget of a 0.49 m screen at 3–5 m, every key E/F/Q is bound to today, which suites assume a pop-up or the one shared overlay, and the cost probe. The operator's answers (F = interact, E = pick up, F-mode camera/zoom/gold dot) are in `docs/plant/operator_rulings_2026-09-25.md` §H5 |
| `docs/DESIGN_vacuum_pot_minigame_2026-09-23.md` | **P3 stage B as the operator described it: not a hold-E but a mini-game** — lid pull that stiffens with time, plamuurmes planes at 90 %, the block by hand, re-lid, the two-minute race. Systems, parameters (his vs placeholder), test strategy. **Built 2026-09-24** (`test_vacuum_pot_minigame`, 33 ok); the feel is his to play |
| `docs/audit/extruder_stop_torque_2026-09-25.md` | **The extruder's load through a stop, from the plant's raw WinCC archive.** The model compounded the torque every STOPPING tick (0.142 of running 1.2 s in at 0.1 s ticks, 0.024 at 0.05 s). Now it is entry torque x rpm / entry rpm, the law the 17 samples caught mid-stop show (slope 0.969). Open, for the operator: the plant's screw stops within one ~5 s log cycle in 70 of 83 stops, while the model coasts for 21.6 s; 26 of 83 stops were run empty first |
| `docs/audit/extruder_screw_die_plate_2026-09-24.md` | **LineFlow's OWN screw model (not ExtruderModel) read 0.11 "bar" at the die, at 200 rpm and a 195 °C melt.** The MFI estimate was 1491 g/10min, so every QA sample graded REJECT, and on lines 1/3A/3B the terminal and SCADA read the `extruder_silo`. Now: die plate after the kopfilter (operator ruling), per-line rpm, melt and output from the WinCC trends, MFI anchor re-solved. §10 (2026-09-25): the "flat kopdruk vs proportional model" gap was a probe holding rpm fixed; both models now carry a power-law die, P ∝ Q^0.35, gated across the trend's output band |
| `docs/audit/extruder_warm_restart_2026-09-25.md` | **A warm extruder restart at the green button tripped 318 bar** (4.3-4.8 s after green, 3A and 3B, through the plain stop / PREHEAT / green path too): a model that had run before went on at nominal flow, and only a first start re-ramped. Also found: only the FIRST extruder in the group could have its rpm set, and the green button accepted a melt that passes lumps. Built from operator rulings: start ramps to the persisted setpoint, 60 floor and new-extruder setpoint, green from the lump point too (201.875 °C), a per-line rpm control. Probe, 27-check suite, 11 mutations; open items (interlocks, ~5 s ramp in the archive, OFF cooling rate, the lump law's knife edge) |
| `docs/audit/extruder_start_interlock_2026-09-25.md` | **The extruder's start button and its natraject, from operator rulings.** Checks first (a failed one latches alarm 4401 until the HMI resets it), then blower + weegschaal, centrifuge, ontwaterzeef, heetafslag and laserfilter in order, then the screw; the ring; a trip when one stops; the run-down; the hidden natraject switch. The extruder owns its LineFlow node and natraject, so the line's start no longer runs them. Measured on a real 3B line, the mutation matrix, the six bench suites switched to natraject OFF, `test_fallback_chains` starting its extruders. §8: the extruder silo's laser level sensor stops the VSS dosing screw at 100 % (line 1: the shredder) and a full PCU pot stops the PCU belt, so an extruder left off fills its silo instead of e-stopping its line at 16 min |
| `docs/plant/operator_rulings_2026-09-25.md` | **The die plate against output, 2026-09-25**: the flat kopdruk in the June-2023 trends is "operator-specific", perhaps an office test without head filters (CLAIMED; the downsampled curves cannot tell). Power-law die P ∝ Q^0.35 in ExtruderScrew AND ExtruderModel, MfiProxy only the matching exponent (MFI itself deferred to the beta). Open: melt pump on 3A/3B (08-31 says none, 09-24 names one), the profiles' rpm is not the rpm at the nominal output **Third session, §E1-§E7: extruder start, rpm setpoint, green button** — a start ramps to the setpoint the operator left (not always to 60); 60 is the floor, the remedy after a 318 trip and a new extruder's setpoint; green waits out the lumps (201.875 °C); 3 s to 60 kept against the raw archive's ~5 s; a line choice on the HMI. Recollections beside the raw WinCC archive's 126 starts. **Fourth session, §I1-§I10: the start button and its natraject** — checks, an alarm reset only on the HMI, the start order, the ring, the extruder (not the line) runs its natraject, a stop under the screw trips it, the hidden natraject setting; the left button starts the PCU |
| `docs/plant/operator_rulings_2026-09-24.md` | **Extruder melt pressures, 2026-09-24**: the "280 psi" die pressure was 280 BAR, a safe maximum before the laserfilter under the 318-bar shutdown (he runs ~220). Two pressures: before the laserfilter = melt-set after + dMP; MP<PEL (160 bar) = dP across the kopfilter; per-line FORM-008 kopdruk. Recollections; what was measured before/after, and what is still open (3B above its one-session trend). §6: merged with #275, which fixed the same finding in parallel. The melt-set pressures follow MELT temperature (3A fit 6.83 bar/°C, weak). §7: the screen's dMP follows it too (operator 2026-09-25), measured before/after |
| `docs/AUDIO_machine_sounds_2026-09-25.md` | **The operator's 11 plant-floor recordings, on their machines, driven by the sim.** File-name cutting grammar (`5s+_`, `25s-35s_`, `loop_3x_`, `_in_operation`, `_loop_4x`) and the rulings behind each bake; `MachineSoundSpec` `.tres` per placeable with the `gain_db` slider (every level a PLACEHOLDER until play-tested); loop seams measured against each loop's own fluctuation; ramps generated from the run loop; the 60 line-macro machines still without a recording. `test_machine_sounds` 80 ok |
| `docs/plant/operator_rulings_2026-09-23.md` | **Operator answers from memory, 2026-09-23** — film look, colour order, bed depth per belt, where wet flake is visible, screws "differ". Recollections, not documents: cite them as such |
| `docs/audit/assets_loss_and_restore_2026-09-21.md` | **`assets/` was wiped and restored.** Godot's `.md5` fingerprints identify originals byte for byte: 159 of 273 are back exact and 101 are cache-only (listed; do not re-import them). Also the `Merlo.fbx` re-import trap, what `winfr` did and did not recover (nothing exact), and the method to reuse |
| `docs/steam/README.md` | **The Steam build (Windows 64-bit), 2026-09-26: built and measured, not uploaded** (no Steamworks account yet). Why "Export all resources" would ship without the building (101 cache-only assets), the explicit file list (`tools/steam/gen_export_preset.py`), the operator's world bundled as a player's first-launch layout (exported builds only), no Desktop `.env` read in an export, the probe runs, and the Steamworks steps. `store_page.md` beside it: the draft text and image sizes |
| `docs/BACKLOG_ultracode_2026-07-19.md` | Deferred queue — 16 of 40 findings landed; also records the npc-05 vacuous-green correction |
| `docs/DESIGN_SUGGESTIONS_2026-07-08.md` | Ranked roadmap, P1-P8 physicalization + Q1-Q8 QoL, every item file-cited |
| `docs/FULL_LOGIC_AUDIT_2026-07-08.md` | Runtime-behaviour audit, 25 findings. **Snapshot, no per-finding status.** Bug 0 / HIGH #1 / #2 / #7 are DONE (#7 fixed 2026-08-23, guarded by `test_project_sweep_guards`); **#12 Walkie→VoiceService is REFUTED — measured, the connect works**; 5 dead files still unverified. Two findings re-measured, one was wrong: re-measure before acting |
| `docs/DESIGN_hmi_tag_bridge_2026-07-22.md` | **Verdict: do NOT build the WebSocket HMI bridge.** Plus the slice that WAS built: `src/sim/TagMap.gd` |
| `docs/DESIGN_npc05_container_chain_2026-07-20.md` | Container-chain design (Dutch). ⚠️ Its "GEBOUWD" status was corrected 2026-07-21 — that proof was a vacuous green |
| `docs/research_film_physics_feasibility.md` | Film-physics R&D — GO on Jolt + GPUParticles3D + custom buoyancy; NO-GO on a Rapier backend swap. Correctly targets 4.6.3 |
| `docs/MESHROOM_BUILDING_HANDOFF.md` | Building photogrammetry handoff. Its `scratchpad/production_run.py` re-run path is **lost**; the 17 GB Meshroom cache now lives at `D:\cedo_archive\meshroom\CeDo_meshroom_cache` (moved from `D:\CeDo_meshroom_cache` 2026-09-21) |

## Traps that have bitten before

- **A unit error can hold up every consumer built on top of it — fix the unit
  and they all fall over.** Measured 2026-09-24: `ExtruderModel` carried the
  plant's 280 as PSI (`DIE_PRESSURE_BASE_PSI = 280.0`, 19.3 bar on the BluPort
  chart); every plant source gives 280 BAR before the meltfilter (SWI-054 p1,
  the 3C BluPort screen, the 3A trend p50 271 / p95 280 bar), and the operator
  confirmed it. At bar scale three consumers broke at once, each only working
  because the number was 14.5x too small: the 160-bar MP<PEL interlock read the
  PRE-filter pressure (would E-STOP every nominal run), the laser filter's
  inlet was fed the kopfilter's ΔP (downstream of it, and on 3A/3B line 3C's),
  and the pressure rode a torque proxy that made one zone 30 °C down read 320
  bar and trip the line (the melt-set pressures AND the laserfilter's dMP now
  follow melt temperature at the 3A trend fit, 6.83 bar/°C as 2.44 % of 280
  bar — a weak fit, refit when a longer export exists; a melt held 9 °C under
  setpoint trips 318 through the screen). Two sessions fixed this the same evening (#275 and
  #278); the merged model is the operator's TWO pressures — MP<PEL is the dP
  across the kopfilter, not a 140-bar copy of the pre-filter pressure — see the
  "Operator-documented" entry below. Guarded by `test_die_pressure_bar` and
  `test_extruder_melt_pressures`. Before changing a unit, list every reader
  (`grep -rn <var>`), and measure each one at the new scale.
  **The same disease, a second model, the same day:** LineFlow's
  `ExtruderScrew` is not `ExtruderModel`, and its `die_pressure` read 0.11 bar
  (1/1300 of the plant). It fed an ABSOLUTE soft sensor (`MfiProxy`:
  MFI = gain·Q/(P·η)), which read 1491 g/10min, and `QaSpec` REJECTed every
  sample. Both unit suites stayed green: `test_extruder_screw` asserted `> 0`
  and an ordering, and `test_mfi_proxy` asserts only ratios. **A suite that
  checks only proportions cannot see a scale error, so guard any number a
  grader or a gauge reads against a documented band** (`test_screw_die_plate_bar`).
  Next door: `_is_extruder()` was `id.begins_with("extruder")`, which also
  matched `extruder_silo`, so the terminal showed a silo's "melt 195 °C". A
  prefix dispatch needs a check on what the thing DOES (process `meltfilter`).
- **A helper moved to a utility class leaves `world.call("_name")` callers
  silently broken.** `call()` by string is not checked at parse time: when
  MainWorld's `_local_aabb` / `_fit_box_collider` moved to `GeometryUtils`,
  `LegacyPropsSpawner` kept calling them on MainWorld for months — 3 SCRIPT
  ERRORs per unconfigured boot, no colliders on the legacy props, feeder
  station aborted. Nobody saw it: that path only runs on a world with no
  `world_layout.json`. Guarded by `test_legacy_props_spawner`. To audit:
  `grep -rhoE 'world\.call\("[A-Za-z_]+"' src | sort -u` and check each name
  exists as a `func` on MainWorld.
  The same trap caught a merge on 2026-09-25. #278 removed
  `LaserFilter.set_upstream_pressure_indicator()`. #279 and #282, merged the
  same night, called it by string from their suites. `main` then had
  `test_hmi_fault_rearm` at 15 fail and `test_hmi_fault_per_line` at 19 fail,
  and the parse sweep stayed green. Before merging a PR that removes or renames
  a method, grep the target branch for the name in quotes:
  `grep -rn '"<name>"' src tools`.
  The damage was bigger than the error lines, because a failed `call()` ABORTS
  the calling function: the diesel pump was never spawned at all (the outlet's
  call came one line before it), the feeder shredder stood at the world origin
  303 m from its belt, and the feeder worker, his bale clamp and tools never
  existed. Second guard, written in parallel the same evening:
  `test_legacy_props_unconfigured_boot` (35 checks) counts the boot's
  "Nonexistent function" errors with an engine `Logger` (Godot 4.6 has
  `OS.add_logger`), runs the audit above as a check (`has_method` on the booted
  world), and proves each collider live in the physics space. Open, measured,
  not changed: on that world the Merlo P40 parks 0.50 m from the power outlet,
  hull through the post (since `2d4c8da`, 2026-06-10); frozen kinematic, it
  drives off the same with or without the outlet's collider. Both suites were
  written by two sessions sharing one `app_userdata`, first under the SAME test
  name and slot: never run two harnesses at once, give every suite its own slot,
  and never let a suite restore `world_layout.json` over bytes it did not write.

- **`Node3D.rotation.x = +θ` sends the local +Z end DOWN, and a symmetric deck
  box hides a wrong sign for months.** Measured 2026-09-23
  (`src/tests/probe_deck_orientation.gd`): Rx(+45°) maps +Z to
  (0, −0.707, +0.707). `inclined_belt_8m`'s 11 m deck was rotated +angle while
  its rollers and A-frames climbed the other way, so the deck crossed its own
  frame at mid-height with the motor floating in the air
  (`docs/plant/renders/shot_belt_bed_inclined_belt_8m_before.png`); every
  render "looked like a belt" because a box has no front. BeltBuilder's
  tilted decks use −incline for exactly this reason. When you seat anything on
  a deck, read the built skin's `global_transform.basis.z` and check it climbs
  toward the top roller; never derive the sign from the builder's comment.
  Since P1 every BeltBuilder deck also carries a `FilmFlakeField` in belt mode
  (a belt that builds its own deck in `extras` seats one with
  `BeltBuilder.attach_film_field`), and a spec that zeroes the deck's width or
  thickness now gets NO skin instead of a zero-volume one. Two more measured
  facts from the same day: `NoiseTexture2D` generates on a thread and renders
  blank until it is done (the first heap render was black — build a texture
  from an `Image` when a capture or a first frame must show it), and a
  MultiMesh driven from a vertex shader (`world_vertex_coords`, per-instance
  `INSTANCE_CUSTOM`) costs the CPU ~3 µs per field per frame for 14 000
  flakes where CPU-animated instances cost 1 ms for 3 500 — animate with
  uniforms, write transforms once.
- **A fixture that reaches the flow graph with no wired input gets whatever
  inlet is nearest — and that can be the machine beside it, both ways.**
  Measured 2026-09-24: the overband magnet (mounted OVER the uitvoerband,
  MachineFlow process "sort") had no in-edge, so the fallback wired
  `transport_belt#5 → magnet → transport_belt#5`; belt 2 received 8.6 kg/s
  with 3 kg/s injected and the magnet "moved" 6 kg/s — the sibling 2-cycle of
  the graph trap above, at the head of line 1, unnoticed because every suite
  asserted the head chain and the twin streams and none the kg into belt 2.
  Anything the material does not pass THROUGH is role none. And a belt's
  `_backlog_kg` is not a heap: it is whatever the buffer holds after the tick's
  move — a model sized to a fallback capacity tripped the field-less 10 m feed
  belts on their ordinary transit load and the e-stop cut line 1's feed
  (`test_line1_throughput` red for two runs). Size a motor model to the deck it
  drives, or do not attach one.
- **Inserting an entry into a line SEQ shifts every index after it, and
  `mount_over` / `at_entry` are indices.** 2026-09-24: a `scrap_bin` entry after
  opzetband 1 put the overband magnet 2.73 m off its belt until its
  `mount_over: 3` became 4 (`test_line1_overband_mount`). Before inserting,
  grep the SEQ for `mount_over|at_entry` and check `user://macros/` for a saved
  override of that line (its chain is indexed the same way).
- **A fresh `class_name` is unknown to a standalone headless run.** Godot
  resolves class names through `.godot/global_script_class_cache.cfg`, which
  the editor (or the harness's `== importing ==` step) rebuilds — a bare
  `godot --headless --path . res://…tscn` after adding a script with
  `class_name X` sees `Identifier "X" not declared`, the suite fails to parse,
  its scene boots with no script and idles to the watchdog. Measured
  2026-09-24 with `VacuumPotService` (254 s lost). Reference NEW scripts by
  `preload("res://…")` from the code and suites written the same day; leave
  the `class_name` for the editor. Same day, next door: `call()` into a
  method whose parameter is `Array[String]` needs a typed array
  (`var evs : Array[String] = […]`), or it is an `Invalid type` SCRIPT ERROR.
- **Two consecutive MAIN entries of a line SEQ have NO edge of their own —
  LineFlow's nearest-input-port fallback wires them, and it picks whatever
  inlet is closest.** Measured 2026-09-24 with `dump_line1_graph`: at line 1's
  tail the nearest inlet to the cyclone's bottom mouth AND to the
  compactorband's lip was blower L's, so the graph held a blower → cyclone →
  blower 2-cycle, blower L at in-degree 3, and an extruder that nothing fed —
  for as long as that tail existed. No suite failed: they assert the head
  chain and the twin streams. `test_line1_throughput`'s ungated info line
  read `granulaat banked 0.0 kg after 600 s` the whole time and 23.7 kg the
  moment the two edges were pinned with `"explicit_from_prev": true`. When a
  SEQ's next main machine is not the geometrically nearest inlet of the
  previous one — a silo fed from above, a compactor beyond a blower — pin the
  edge; and read the info lines a suite prints without gating, they are
  measurements too.
  **2026-09-25 — the same on 3A and 3B, and WHY the fallback makes 2-cycles
  at all.** The extruder's inlet sits 15.22 m (3A) / 14.24 m (3B, and line 1)
  from its compactorband's discharge, past `MAX_LINK_DIST` (14, exclusive),
  so the band never sees the extruder and falls back to the nearest inlet
  BEHIND it: on 3A a silo ↔ band 2-cycle, on 3B a band → booster blower
  edge, with the booster blower ↔ tussenventilator-cyclone 2-cycle beside it
  and no in-edge on the silo. `extruder_3a` and `extruder_3b` received 0 kg
  from 63 kg fed. A 2-cycle survives at all because `_link_best_target`
  calls `_creates_cycle(best, src_idx)` against a `(from, to)` contract. That
  asks whether the source already reaches the target, and never refuses a
  back-edge. The same swapped guard leaves further 2-cycles on these lines
  (3A's infeed wind_sifter ↔ blower 2, which starves the big top cyclone;
  centrifuge ↔ weegschaal on 1 and 3B, which starves voorraad_silo). They
  were fixed the same night by swapping the arguments (the next entry). The
  3A/3B tails are pinned in the SEQs, guarded
  by `test_extruder_silo_chain` (by name and by kg: no node of the chain may
  process more than was fed, which is how a 2-cycle shows up in flow).
  `src/tests/dump_line_graph.tscn -- <line_id>` dumps any macro line, marks
  every edge explicit or geometry, and lists every cycle.
  **And no pin survived a reload — fixed the same day.** `lf_explicit_outs`
  holds NodePaths, so it is never saved. Until then it was stamped only
  inside `_build_full_line`'s loop, so a reloaded world had 0 explicit
  edges. Measured with `probe_explicit_edges_roundtrip`: 47 tagged nodes
  before a save/load and 0 after, with all three silo tails, line 1's
  streams, the 3B split and the 3A recirc gone. Now the SEQ bookkeeping
  lives in ONE function, `BuildMode.macro_flow_edges` (SEQ indices in, edge
  triples out). The build stamps from it after placing, and `load_layout`
  re-stamps every saved line from it (`_rederive_macro_flow_edges`),
  grouped by the new `macro_instance` meta. Three rules:
  - A deleted machine is a HOLE. Nothing is rewired around it, and its
    upstream stays an explicit dead end, as after a live delete.
  - A save whose ids or indices do not match the SEQ is REFUSED, loudly, and
    that line falls back to geometry.
  - Never add topology logic to the build loop. Put it in
    `macro_flow_edges`, or a reload will not have it.

  Guarded by `test_macro_edges_reload` (60 checks): every macro round-trips
  by name, kg reach each named extruder after a reload, and a partial line
  reloads into exactly the live session's graph.
  `docs/audit/macro_edges_reload_2026-09-25.md`.
- **A guard called with its arguments swapped never fires, and fixing it
  REROUTES edges rather than repairing them.** Measured 2026-09-25 with
  `dump_line_graph` on all seven macros: `_link_best_target` now calls
  `_creates_cycle(src_idx, best)`, and the 36 edges that sat on cycles are 0.
  But a refused back-edge falls to the source's NEXT candidate. Three of those
  were wrong too:
  - 3A's infeed blower 2 went to doseerschroef M11b, skipping the mengsilo.
    It is now pinned to the big top cyclone (ruling 2.1-B).
  - Every lump cart fed the laser filter (vacuum_degas on 3C).
  - One compressor of the pair became a feed head.

  The carts, their spots, the lump platform and both visible compressors now
  have MachineFlow role `none`. Three code comments already claimed that, and
  the code never did it. Two consequences:
  - The post-extruder chain on 1/3A/3B is `extruder → laser_filter →
    heetafslag`, no longer THROUGH a cart.
  - `weegschaal → voorraad_silo` on 1 and 3B came from the swap alone.

  When you fix a guard, dump every graph it touches before and after, and
  read each rerouted edge against the docs. A fixed guard proves only that
  there are no cycles, not that the wiring is right. Measured on a world
  reloaded from a save, BEFORE the reload fix in the entry above: every pin
  lost, and 0 cycles there too (60 before), but not right. Since that fix a
  reload re-stamps the pins (`test_macro_edges_reload`).
  Guarded by `test_fallback_chains`: no cycle on any line, fixtures out of
  the graph, only the plant's own feed heads, and the 3A infeed and the 1/3B
  granulate tails by name and by kg.
  `docs/audit/cycle_guard_swap_2026-09-25.md`.
- **A visual grafted onto a node before that node's `_ready()` is a visual
  that does not exist.** `_build_opzetband` attached the #196 metal-detector
  head to the belt's `InclinePivot`, which `ShredderFeedBelt` builds in
  `_ready()` — after `build_node` returns and the caller adds the model to
  the tree. So the graft looked for a pivot that was not there yet, returned,
  and for the whole life of #196 no real build ever carried the head; the
  coil tunnel and its REJECT placard were code only. Measured 2026-09-24
  (`build_node("opzetband_1")` + 2 frames → no `MetaalDetectorHead`). Fixed
  by grafting on `ready`; guarded by `test_line1_metal_detect`. When a builder
  decorates a SCRIPTED node, check whether that node builds itself in
  `_ready()` — if it does, decorate on its `ready` signal, and assert the
  decoration on a node that has been in the tree for a frame.
- **GDScript lambdas capture locals BY VALUE.** `var done := false;
  x.connect(func(): done = true)` never changes the outer `done` — the lambda
  writes its own copy. Measured 2026-09-24 in `test_line1_metal_detect`: two
  "fed through" checks waited their full 240 s on such a flag. Read the state
  from the object (`rider_count()`), or capture a Dictionary/Array (reference
  types) and write into it.
- **A Dictionary whose contents change cannot be a Dictionary KEY.** Measured
  2026-09-24, `test_wet_side_beds` first run: the suite keyed a Dictionary by
  LineFlow's node dicts, the lookups worked before the first `tick()` and threw
  `Invalid access to property or key '{ "node": … }' on a base object of type
  'Dictionary'` after it — a Dictionary key is hashed by CONTENT, and `thru`,
  `moist`, `spin` change every tick. Key by the node's instance id, or keep an
  Array of records that hold the dict by reference. Same run, same lesson in
  another coat: a belt-mode `FilmFlakeField` has NO `_mat` (its flakes wear a
  ShaderMaterial); the wet tint lives on `_heap_mat` and the shader's `tint`
  uniform, so a test that reads `_mat.albedo_color` reads a null.
- **Check a deck's tilt sign against the machine's PORTS, not its comment.**
  The Kufferath sieve's screen deck was built at −14° with the comment "feed
  box at the high (-Z) end" — but −14° tips local −Z DOWN (the goot builder's
  own note, and `probe_deck_orientation`), so the feed box had stood at the
  LOW end since the day it was built while MachineFlow's ports (inlet high at
  −Z, outlet low at +Z) said otherwise. Nothing caught it because no material
  was ever drawn on the deck. Found 2026-09-24 the moment a bed had to slide
  DOWN it; fixed to +14° and guarded by `test_wet_side_beds` (the deck's
  `basis.z.y` must be negative). When a builder tilts a surface, assert which
  end is low against `MachineFlow` — the two agree nowhere by construction.
- **An opaque shell hides whatever you put inside it — a "sight glass" over a
  closed drum shows the drum, not the level.** Measured 2026-09-23 by
  rendering: the compactor kijkglas built that morning (a flat glass disc on
  the cleanout door, a PotFill column inside the drum, 21 green checks on the
  geometry) showed a grey door plate at 33 % pot load, and the mengsilo's
  vertical "sight strip" had never shown anything either. A level you can see
  needs the film OUTSIDE the shell: `PlaceableCatalog._level_window` builds a
  proud port (ring, gauge glass, dark back, a `LevelWitness` slab that
  `set_silo_fill()` sizes to the live level). Any new sight glass goes through
  it, and any claim that a level "reads through the glass" is a render, not a
  geometry check (`src/tests/shot_silo_level.gd`).
- **"Operator-documented" with no file named is unsourced, and a pressure
  with the wrong unit hides for months because nothing reads it against a
  trip.** Measured 2026-09-24: `ExtruderModel.die_pressure_psi` sat on a
  280 "psi" base ("operator-documented", no source) while every HMI photo,
  SWI and trend gives 280 BAR. The BluPort showed 19.3 bar, and the one number
  fed two trips at two different points of the line (318 bar before the
  laserfilter, 160 bar MP<PEL at the kopfilter), so neither could ever fire.
  The model topped out near 46 bar. On 3A the laserfilter read the KOPFILTER's
  dP as its upstream, although the kopfilter sits after it. Now two pressures
  in bar, per the operator (`docs/plant/operator_rulings_2026-09-24.md`),
  guarded by `test_extruder_melt_pressures`, which REACHES both trips from
  gameplay causes. LaserFilter and HeadFilter keep psi internally; convert at
  their boundary with 14.5038 (the old `0.0689` factors were 0.07 % off). A
  new trip is not done until a suite reaches it TWICE. The first reachable
  318 trip exposed a latch (`LaserFilter.is_tripped`) that only a screen
  change cleared, so after one E-stop reset it could never fire again.
- **Judging a model against a trend one input at a time can invent a
  model-form question.** Measured 2026-09-25: `test_screw_die_plate_bar`
  printed the screw's die plate at 3B 534 / 799 / 1263 kg/h as 96 / 144 /
  227 bar against a flat plant kopdruk, and it was filed as an open
  model-form question. The probe held the screw at 110 rpm. The plant turns
  60 / 80 / 120 rpm at those outputs (output follows rpm, 3B exponent 1.01,
  R² 0.92), and along that path the same law read 120 / 144 / 170. When a
  model's inputs are coupled in the plant, drive it along the plant's own
  joint path (pair the curves, as `tools/audit/fit_kopdruk_vs_output.py`
  does) before calling its form wrong.
- **A frame-counted wait against a wall-clock cadence is a frame-rate
  lottery.** Two suites went red on healthy worlds this way on 2026-09-23:
  `test_jam_baseline` waited 60 stable frames for a threaded navmesh bake that
  takes ~70 frames, and `test_spawn_clearance` waited 180 frames for bale
  bodies that only stream after `BaleYardManager`'s 2.0 s wall-clock cache
  refresh — the second one only surfaced when a perf change raised the
  headless frame rate from 55 to 140 fps. Wait on the thing you mean
  (`is_baking()`, the body count, wall time), never on a frame count, and
  print how long it actually took so the next reader can see the margin.
- **`RigidBody3D.mass` reads back single-precision.** Write 415.7 kg from a
  double and `mass` returns it ±3e-5. An equality against the meta the value
  came from, at 1e-6, failed on CORRECT code (2026-09-24,
  `test_bale_weight_variance`, first run). Compare masses at 1e-3, and treat
  any 1e-6 float assertion against an engine property as suspect.
- **LineFlow ticks at 10 Hz, not per frame (since 2026-09-23).** Its
  `_process` accumulates frame time and calls `tick(FLOW_TICK_DT)` at 0.1 s —
  the rate `SimTick` runs and the rate EVERY suite has always driven
  (`lf.tick(0.1)`). Before, `_process` called `tick(delta)` every frame:
  measured with `probe_tick_cost` at 2.85 ms of every 60 Hz frame for 52
  nodes, the largest single item of the CPU floor, and a rate nothing tested.
  Per-tick EMAs in `tick()` (`thru` etc.) therefore settle in ~0.4 s of wall
  time. If you add flow logic, make it delta-correct at 0.1 s and prove it with
  `tick(0.1)` — do not reintroduce per-frame calls, and do not subscribe
  LineFlow to `SimTick` (that autoload is PROCESS_MODE_ALWAYS and would run the
  flow behind the pause menu — the QaLab header explains).
- **A stop that is written AFTER the conveying split is not a stop.** LineFlow's
  tick is `_tick_plc_power_downstream` (PLC writes `powered`, runs the spin and
  mechanism ramp) → `_tick_feed` → `_tick_process_machines` (conveys on `spin`)
  → `_tick_advanced_systems` (MotorOverload trips here). Measured 2026-09-23
  with `test_motor_trip_stops_conveying`: a tripped shredder-2 kept conveying
  at its full 0.61 kg/s and its rotors stayed at 45 rpm, because the trip only
  dropped `powered` after the split and the PLC re-wrote `true` at the top of
  the next tick; the bunker/shredder-2 interlock moved 31 kg in 3.1 s the same
  way. Every end-of-tick reader (HMI amps, the interlock test's one-tick check)
  saw a perfect trip. Latched trips are now applied inside the PLC step
  (`_apply_trip_latches`). When you add any "stop this machine" rule, put it
  where `powered` is WRITTEN, not where it is read, and prove it with
  `_moved_kg` over several ticks, never with `powered` after one.
- **A builder that tags the node it is HANDED makes the Model a second
  machine.** `build_node` tags the body; every `_m_*` builder is handed the
  body's `Model` child. Four belt builders passed it to `BeltBuilder.build()`,
  which tags whatever it gets `placeable_id` + `placed_object`, and ten more
  ended with `_finalize_placeable(p, id)`. So 31 catalog ids carried a second
  placeable inside the first. Measured 2026-09-25: LineFlow found every intake
  transportband and both switch belts twice (30 intake nodes for 17 machines).
  The twin sat at the body's own ports with no in-edge, so it was a feed head,
  and it double-fed the next belt. It also drove the same film bed with 0 kg/s
  after the body, so every intake bed read 0.000 kg/m, and it hung a second
  SwitchBelt / Conveyor8 controller on the deck. K-mode's walk to the first
  `placed_object` stopped at the Model for hatch colliders under it. No save
  held it, and every load rebuilt it. In an `_m_*` builder call
  `BeltBuilder.build_internal`, never `build()` or `_finalize_placeable`. This
  must print nothing:
  `grep -nE "_finalize_placeable\(p[,)]|BeltBuilder\.build\(p" src/build/PlaceableCatalog.gd`.
  Guarded by `test_flow_node_unique`: every catalog id, seven macros fresh and
  reloaded, 4 mutations red. `docs/audit/flow_node_twins_2026-09-25.md`.
  **The same rule for a script on the body:** its `_ready` must not add
  `placed_object`, because it cannot tell a ghost from a machine.
  `ShredderMachine._ready` did, and every raw `build_node("shredder_*", true)`
  became a LineFlow feed head (fixed 2026-09-25). `build_node` tags the real
  body in its `if not ghost:` block. Guarded by `test_ghost_census`: every
  catalog id built as a ghost, none `placed_object`, 0 LineFlow nodes.
  `docs/audit/shredder_ghost_placed_object_2026-09-25.md`.
- **A macro SEQ is a PLACEMENT list, not a topology — reading it tells you
  nothing about what the material does.** Which machine feeds which is decided
  afterwards, partly by the builder's `lf_explicit_outs` tagging and partly by
  LineFlow's nearest-input-port geometry fallback. Line 1's whole wet section
  looked right in the SEQ and was wired four different kinds of wrong at once: a
  chute with three outputs instead of two, both frictiescheiders discharging
  straight into the mill past their own dryer/blower/cyclone train, two blowers
  feeding EACH OTHER in a closed loop, and two cyclones with no inlet at all. A
  side-by-side L/R pair is where this bites hardest, because the fallback picks
  by distance and the sibling is always the nearest port. **Dump the graph
  (`src/tests/dump_line1_graph.tscn`) before believing any claim about flow**,
  and tag real parallel trains with `{"stream": "L"/"R"}` instead of letting
  geometry guess. A sibling 2-cycle passes every naive check — both nodes have
  exactly one in-edge and one out-edge — so test for it by name.
  **2026-09-25, the sort line:** all eight side-lane entries fell into one
  `branch_chain`, and shredder 2 ended up with no in-edge. Measured with
  `dump_line_graph.tscn -- line_sort`. Two tools came out of the fix:
  - `{"flow": false}` places an entry but keeps it out of the flow graph.
    Use it when the id is a flow machine elsewhere (the reject belts are
    plain `transport_belt`s), so MachineFlow role `none` cannot do it.
  - A per-branch kg check cannot tell SERIES from PARALLEL. Each branch
    "passes its kg on" either way. Assert that the whole split passes BOTH
    stages. `docs/audit/sort_line_topology_2026-09-25.md`.
  **2026-09-25, the 3A/3B intake, same disease:** the opzetband fed the climb
  belt past shredder 2 (5.78 m against 6.44 m). The C8.5 / U-bay
  `branch_chain` pinned `C8 → C8.5` as C8's ONLY edge, so C8 never ran
  forward, and it pinned `U-bay → C9`. Two more things came out of that fix:
  - **A splitter's edge ORDER is topology.** LineFlow's Conveyor8 overlay
    reads C8's edge 0 as forward and edge 1 as reverse (the order the geometry
    linker emits `wout` / `wout2`). With pins, the order is the order in
    `lf_explicit_outs`, i.e. the order `macro_flow_edges` writes them.
    Appending the forward edge after the overflow's opening edge sent C8's
    forward share into the overflow (mutation M4).
  - A stream whose last member feeds nothing (a sink, or MachineFlow
    `no_outlet`, the U-bay) ends there. No merge edge is written, and the main
    path continues from the split, inserted as the split's FIRST edge. Do not
    make a dump a `sink` to get this: LineFlow counts everything a sink takes
    as granulaat.
  `docs/audit/intake_3a3b_topology_2026-09-25.md`.
- **Lifting a gravity-fed machine without lifting what feeds it silently
  disconnects the line.** The feed chain's heights are DERIVED from the target's
  local port helpers, which know nothing about the `y` a macro entry applies. Put
  the lift in one constant every dependent number reads
  (`PlaceableCatalog.VW_TROMMEL_LIFT_M`), and remember a derived `gap` moves too:
  at 45° a belt's horizontal run grows by exactly the lift, at any other angle it
  does not.
- **A turn-pattern test that asserts `signf(turn_deg)` cannot tell a 90° corner
  from a 180° U-turn.** Line 1's fold test passed unchanged while the flotation
  tank sat 90° out from where the operator's drawing puts it. Assert the angles.
- **`AnimatableBody3D.sync_to_physics` defaults to TRUE, and that strands any
  sub-assembly a macro moves later.** With it on, Godot drives the body FROM the
  physics server every tick (`global_transform = state.transform`), and the
  server only learns a new transform when the body's OWN transform is written —
  moving an ANCESTOR never notifies it. Machines are built at the catalog's local
  origin and moved into place afterwards by the line macro, so these bodies stay
  pinned to the global transform they held at build time, which was their
  intended LOCAL offset. Measured 2026-09-16: 47 visible parts on line 1 (plus 14
  on line 3A) were floating in a cluster at the world origin — `shredder_1`'s
  inspection hatch sat at global `(1.76, 3.19, 0.00)` while the shredder stood at
  `(-156.76, 0, 38.98)`. It survived 30 physics frames, so it is not a sync-timing
  artefact, and turning the flag off afterwards does NOT recover the overwritten
  local — it has to be cleared at construction. All three sites now do
  (`PlaceableCatalog._interactive_hatch`, `PushGate._build_hinge_pivot`,
  `Door._build_hinge_pivot`); the flag is only wanted for engine-animated
  platforms that must shove rigid bodies, never for a tween-driven door.
  Guarded by `test_macro_part_placement`. Nothing caught it for months because
  the geometry suites check where MACHINES land, not where a machine's own parts
  land relative to it.
- **`assets/` is gitignored** (`.gitignore:2`). 2.9 GB, `git ls-files assets` → 0.
  Every WAV, model and `.import` setting is local-only and does **not** survive a
  fresh clone. On a clean clone `PlantAudio` fails at its first check
  (`PlantAudio.gd:50`, missing `assets/audio/audio_layout.json`) — it does not
  merely lose the crossfade.
  **2026-09-21 it was wiped (deleting an old test copy followed a link) and
  restored.** Of the 273 imported sources in it, 159 came back byte-exact and 101
  are **cache-only**: the game runs, the editor has nothing to re-import them
  from. Do not re-import them or change their import settings, and do not
  force-reimport `Merlo.fbx` (measured: 0 texture links instead of 21). To check
  any restored file, compare its MD5 with `source_md5` in
  `.godot/imported/<name>-<md5 of res path>.md5`. The list and method are in
  `docs/audit/assets_loss_and_restore_2026-09-21.md`. `.godot/imported/` is what
  made the restore possible: never delete it while assets are missing.
- **`user://world_layout.json` is the world's ground truth and is in git nowhere.**
  `WorldLayout.gd`'s `LAYOUT_PATH` has no `res://` fallback. Losing your
  `app_userdata` loses the world.
- **A green harness on a FRESH CLONE is a narrower claim than a green harness on
  the operator's machine**, and the difference is measured. Without `assets/` and
  without a `world_layout.json`, 15 of 22 suites pass and the other 7 fail for
  purely environmental reasons — four on "the shell has a measurable footprint"
  (no `CeDo_factory_solid.obj`), one on a missing vehicle marker, and both spawn
  clearance runs on "BaleYardManager reachable", because `MainWorld.gd:286` only
  builds that manager when the layout is authoritative. Do not chase those as
  regressions, and do not quote a cloud-session green as if it covered the world
  suites. Full table in `docs/AUDIT_project_sweep_2026-08-23.md` §3.2.
- **A headless suite cannot assert MultiMesh CONTENT.** Measured on 4.6.3
  immediately after a successful `set_instance_transform`: `buffer` reads back
  EMPTY and `get_instance_transform()` returns IDENTITY for every index. The
  dummy renderer keeps no CPU-side copy. A check written against those readings
  fails on CORRECT code, and the instinct is then to weaken it. Assert a
  MultiMesh's shape and node graph; never its contents.
- **F8 is a trap.** The project binds F8 to Inspect Mode (`SettingsManager.gd:788`
  since at least 2026-09-25; an older revision of this line said `:660`),
  but when the game runs embedded in the editor F8 is the editor's **Stop**
  shortcut — the now-deleted `NpcTaskBench.gd:68` recorded "it killed the
  session." Use the observer key `O` in benches instead.
- **Stale-constant disease.** Geometry/UI built from hand-baked constants instead
  of measured runtime values. The harness once validated a stale constant against
  its own copy. Measure from the mesh, not from a saved number.
- **A check that maps a result back through the frame that placed it cannot
  fail — and the world suites' building frame was rotated twice.** Measured
  2026-09-25: 17 files under `src/tests/` (12 suites, 3 probes, 2 tools) used
  typed constants (`BF_O/BF_XU/BF_ZU`) mapped through `Plant.pc_to_scene`, which now
  applies the world yaw a second time. The shell's walls run at 40.00° (mod
  90); that frame ran at −0.2°, six of its ten outline corners stood
  3.6–39.8 m from any wall, and line 3A had 8 of 39 machines outside the
  building, while `regression_world_save` said "39/39 inside" (it mapped each
  machine back through the same frame). Every suite now uses the frame the
  game fits from the shell at runtime (`src/tests/building_frame.gd` over
  `InteriorLightingManager.get_building_frame()`), and refuses to run without
  one. `regression_world_save` adds two checks that measure the frame instead
  of trusting it: the outline corners on the shell's walls (worst 0.03 m) and
  a roof face above every machine (39/39). Mutation-proven: the old frame
  turns both red (39.75 m, 31/39) while "inside footprint" stays 39/39 green.
  Line 3C moved to bf(4,44) in three suites, the QA loop's 3C to bf(4,22),
  and the lump-cart suite's four lines to 3A/3B/3C at bf y 10/31/52 with line
  1 at bf(175,92), outside: it fits nowhere in this shell.
  `docs/audit/building_frame_2026-09-25.md`.
- **GauntletWorld is a visual bench only.** It omits LineFlow/crew/SCADA.
  Trustworthy for "does it spawn/render", never for behaviour.
- **Two PRs can each be "mergeable ✅" and still produce a file that does not
  parse.** MEASURED 2026-08-29 on real branches, not hypothesised. PRs #155 and
  #158 each added `var shell` to `test_wall_openings.gd`'s `_init()`. Different
  hunks, so git merged them with **zero conflict** and GitHub reported both as
  cleanly mergeable — GDScript has no block scoping, so the merged result is
  `Parse Error: There is already a variable named "shell" declared in this scope`,
  which stops the WHOLE harness at its parse gate (`run.sh:40`). GitHub computes
  each PR's mergeability against `main` *independently*, so it structurally cannot
  see this, and **this repo has no CI** — nothing but an actual parse run catches
  it. Before merging any batch that touches one file more than once:
  ```bash
  sed -n 's/^[[:space:]]*var \([A-Za-z_][A-Za-z0-9_]*\).*/\1/p' <file> | sort | uniq -d
  ```
  Non-empty output = the merge will not parse. Then confirm with
  `godot --headless --path . --check-only --script res://<file>`.
- **A bot PR's conflict resolution can delete a suite without touching its test
  file.** MEASURED 2026-09-21 on `origin/main` `34bd56c`, three ways at once:
  merge #258 (`6338e79`) resolved a `run.sh` conflict by *replacing* the
  `SettingsManager apply` block, so that suite stopped running while
  `test_settings_manager_apply.gd` stayed in the tree; two bot PRs created two
  *different* tests both named `test_operator_context.gd`, and merge #268
  (`30cc5f4`) kept one and dropped 16 `npc_board_vehicle` checks; and the
  survivor never ran a check — it `preload`ed `OperatorContext.gd`, which uses
  the `EventBus` autoload, and in a `--script` suite a preload compiles before
  autoload names exist (`Identifier not found: EventBus`), so it printed no
  `Result:` line and was red from the day it was wired. All three restored
  locally and measured green (5 / 16 / 5 ok). Lessons: an **add/add conflict on
  a test file means two tests — rename one, never pick a side**; after pulling
  bot merges, `git diff <old> <new> -- tools/regression/run.sh | grep '^-echo "=='`
  lists every dropped step (it named exactly `SettingsManager apply` on the
  real range, and nothing on a tree that only adds); and in `--script` suites,
  `load()` anything that touches an autoload at runtime — never `preload()` it.
  **2026-09-25, the other way round: a merge KEPT both sides of the main
  `for t in …; do` line** (`59acf8f`, #308 merging `main` with #309). #308
  had added `test_extruder_start_rpm` to that line and #309 `test_ghost_census`.
  Two headers with one body and one `done` leave the first loop unclosed, and
  `main`'s `run.sh` stopped parsing: `syntax error: unexpected end of file`.
  bash runs every step before that line, then exits without
  `== done (exit N) ==`. After any merge that touches `run.sh`, run
  `bash -n tools/regression/run.sh` and check
  `grep -c '^for t in test_machine_sounds' tools/regression/run.sh` is 1.
  Resolve such a conflict by merging the two suite lists into one line.
- **A headless run that outlives its expected time is HUNG, and exit 0 is not a
  pass.** Measured 2026-09-22 on a throwaway `--script` probe that idled until
  the session was killed. Three silent modes: (1) a runtime `SCRIPT ERROR` in
  `_physics_process` aborts only that call, so a one-shot
  `if _pf == END_TICK: … quit()` never fires again → hangs forever; (2) the same
  error inside a helper that `_physics_process` calls before `return true` ends
  the loop with **exit 0 and no verdict**; (3) `--quit-after 300` — used by every
  `--script` block in `run.sh` — ends a 150-physics-tick run early, again exit 0,
  no verdict (it counts frames, not physics ticks). For any probe or suite:
  wrap it in `timeout --kill-after=10 <s>`; put a tick watchdog at the TOP of
  `_physics_process` that prints a failing `Result:` and `quit(2)`; let the
  verdict function call `quit()` itself and never `return true` after it; gate
  on the `Result:` line plus zero `SCRIPT ERROR` lines, never on the exit code.
  Worked example: `src/tests/test_lump_chunk_ccd.gd` (watchdog proven by
  injecting that exact error: exit 2 with a failing verdict in 11 s).
  **A fourth mode, measured 2026-09-25: a suite that PASSES without a phase.**
  `await _phase_d()` returns as if D were done when D dies on a runtime error,
  so `_run` reaches the verdict. With C: full, `test_macro_edges_reload`'s D
  save failed, and the typed read after it aborted the phase. The suite printed
  `PASS (51 ok)` instead of 60, and every `run.sh` step reads only its verdict
  line. Since then:
  - `run.sh` ends with `tools/regression/script_error_census.sh`, which fails
    every log of the run that carries a `^SCRIPT ERROR` line. Only
    `parse_sweep.log` is excused.
  - A suite that awaits phases should record each one's LAST line and assert
    all of them (`test_macro_edges_reload` Z3).
  - A `--script` suite must not name a class whose script uses an autoload.
    `BaseVehicle.NPC_ARRIVE_TOL` in `test_route_goal_clearance` made the
    pre-autoload compile fail on `EventBus`. It ran anyway, but its log carried
    2 `SCRIPT ERROR` lines until the constant was read through `load()`.
  `docs/audit/aborted_phase_guard_2026-09-25.md`.
- **Most `src/tests/*.gd` files are never executed by the harness.** `run.sh:261`
  runs an explicit allow-list of `.tscn` suites; anything not on it is only seen by
  the full-tree parse sweep, which proves the file PARSES and nothing more. As of
  2026-08-29 that includes `test_push_gate.gd`, `test_walkie.gd` and the
  `test_wall_openings.gd` / `test_tool_placement_mode.gd` additions. Adding a test
  file therefore buys **no** regression protection until it is wired into that
  loop. When wiring one in, give it a `--quit-after` guard and an explicit
  `quit(1)` on every failure path — a GDScript `assert()` failure aborts before the
  final `quit()`, so an unguarded suite **hangs** the harness instead of failing
  it (the "idles forever" mode documented at `run.sh:48-54`).
  **2026-09-21:** diffing `src/tests/test_*.tscn` against `run.sh` found 34 such
  suites; 26 measured green and are now wired (11 in the main loop, 15 in a
  second loop that gates each on its OWN verdict line — see `run.sh`). The scene
  loops also now have a per-suite `timeout` (`SUITE_TIMEOUT_S`, default 900).
  Still unwired on purpose: `test_marker_tool` (leaves a directory in the real
  `user://feedback`), `test_hmi_screen_base` (0 checks), `test_leafblower_refuel`
  and `test_player_ladder` (no verdict line), plus two that are red
  (`test_feed_belt_to_shredder_flow`, `test_line1_automated_4bales` — both
  untracked files on the operator's machine, not in git). To re-derive:
  `w=$(grep -E '^for t in' tools/regression/run.sh | tr -d ';' | tr ' ' '\n' | grep '^test_'); for f in src/tests/test_*.tscn; do b=$(basename $f .tscn); echo "$w" | grep -qx "$b" || echo $b; done`
  (read only the `for t in` lists — a plain `grep` of `run.sh` also matches the
  comments that NAME the unwired suites; it also lists suites that have their own
  dedicated block, such as `test_spawn_clearance`).
- **`x *= f` inside a per-tick function compounds.** It follows the product of
  every tick's `f`, not `f`, and the tick size sets how fast it falls. Measured
  2026-09-25: `ExtruderModel._scale_melt_pressures(rpm_frac)` did that in
  STARTING and STOPPING. 1.2 s into a stop the die plate read 0.142 of running
  at 0.1 s ticks and 0.024 at 0.05 s ticks, against 0.747 for the flow. A start
  read 0 bar all the way up, because OFF parks the pressures at 0. The fix
  recomputes the pressures from the current flow every tick
  (`_set_melt_pressures_from_flow`), guarded by `test_extruder_ramp_pressures`.
  `motor_torque_pct *= rpm_frac` in `_tick_stopping` had the same shape and
  measured the same fractions (the BluPort's "belasting" read 9 % 1.2 s into a
  stop from 60 %). It is fixed too: the torque is now entry torque x rpm /
  entry rpm, guarded by `test_extruder_stop_torque`. No SWI documents a
  coast-down torque, but the plant's RAW WinCC archive does
  (`F:/Citizen/Documents/CeDo/Gegevens extruder 3A|3B`, load and speed logged
  in the same ~5 s cycle; `tools/audit/fit_stop_load_vs_rpm.py`). The
  downsampled curves in `src/data/plant/trends/` are 6-minute medians and
  cannot show any transient, so go to the raw files for one.
  `docs/audit/extruder_stop_torque_2026-09-25.md`. To find more:
  `grep -rnE '^\s+(\w+) = \1 \*|^\s+\w+ \*= ' src/sim --include=*.gd`
  (7 hits on 2026-09-25, 6 after the torque fix) — then read each: a value
  assigned fresh earlier in the same tick is fine, and so is
  `x * exp(-delta / tau)`, a decay that is tick-size independent by design (the
  screw's own coast-down). To prove a fix: run the same stop at two tick sizes,
  and the reading at the same time must agree — and check the law as well,
  because a value that is simply HELD agrees at every tick size (the torque
  suite's mutation M5). `docs/audit/extruder_ramp_pressures_2026-09-25.md`,
  which also records that a WARM restart at the preheat-ready melt trips 318 bar
  (old code and new) — resolved the same day by operator rulings, see "The
  extruder warm-up" below and `docs/audit/extruder_warm_restart_2026-09-25.md`.

## Save files go through `AtomicFile` (2026-09-21)

Do not open a save, layout, macro or override file with `FileAccess.WRITE`
directly. That truncates it to 0 bytes *before* the first byte is written, and
the loaders used to read the result as "no data": `BuildMode` loaded an empty
factory, `WorldLayout` fell back to the demo spawns, and the 60 s autosave then
overwrote the damage. Use `src/util/AtomicFile.gd` — `write_json` / `write_text`
(`.tmp`, byte-length verify, last good generation kept as `.bak`),
`read_json` / `read_text` (primary → `.tmp` → `.bak`), `exists_any`, and
**`delete`**.

Two rules that were wrong in the first draft and are now guarded by
`test_atomic_file` (50 checks, mutation-proven):

- **A missing primary recovers from `.tmp` only, never from `.bak`.** The game
  deletes saves by removing the primary file; a leftover `.bak` must not bring
  them back. Anything that deliberately deletes one of these files calls
  `AtomicFile.delete()` so the `.bak`/`.tmp` go with it (`MainMenu`,
  `SystemsSpawner`, `GameState.clear_save`, `LineMacroStore.reset` do).
- **A corrupt primary must never be copied over the last good `.bak`.**

Limits, stated once: Godot has no `fsync`, so this survives a killed process and
a short write, not an OS crash with the page cache unflushed.

**A test that boots a world must never write `world_layout.json` (2026-09-25).**
The 60 s autosave is only one of the writers. `BuildMode._save_layout` also runs
on every placement and deletion, and it calls `WorldLayout.save()` whenever
`load_shared_structure` is true. The world's own BuildMode has it true. The old
guard was an in-memory copy written back after `queue_free()`, which a kill, a
`SUITE_TIMEOUT` or the teardown segfault skipped. Every save also rotated
AtomicFile's `.bak`, which the write-back never repaired. Any suite that boots
`MainWorld.tscn` or builds a BuildMode with shared structure uses
`src/tests/world_layout_guard.gd`, preloaded:
- `arm()` before boot: it redirects `layout_path_override` to
  `user://<slot>_world_layout.json`, and the suite refuses to run if the
  redirect does not take.
- `final_checks(world)` before the verdict: it forces one `_save_layout` and
  proves the save landed in scratch. It also proves the real file and its
  `.bak`/`.tmp` kept their md5 AND mtime.
- `restore()` before and after the world is freed. It skips unchanged bytes and
  never writes the real file.

`tools/regression/run.sh` fingerprints the real file the same way and fails
any step that changes it, naming the step, without restoring. The measurements,
including which suites wrote the file before, are in
`docs/audit/world_layout_guard_2026-09-25.md`.

## Operator feedback channel

**F10 is a multi-point marker tool** (`src/scenes/player/MarkerTool.gd`): LMB
places an orb, G snaps to grid/edge, H clears, RMB/F10 exits and writes
`user://feedback/<stamp>/markers.json` + `context.json` + a screenshot. When the
operator says "check feedback", read the newest directory under
`%APPDATA%/Godot/app_userdata/CeDo Simulator/feedback/`.

## Placed machines get their sound the same way (2026-09-25)

A placeable has a sound iff `src/audio/machine_sounds/<placeable_id>.tres`
exists (a `MachineSoundSpec`). `MachineSoundBank.attach(body, id)` runs at the
tail of `build_node` beside `MachineBrains.attach`, and `LineFlow` drives the
resulting `MachineSound` every tick with `spin × rotor fraction` — so a machine
that is not powered is *stopped*, not quiet, and a machine that leaves the flow
graph winds down on the component's own 1 s watchdog. Ramp-up and ramp-down
are generated from the run loop (pitch + level, over the spec's ramp times or
the sim's `SPIN_UP_S`); a real start/stop recording goes in `start_clip` /
`stop_clip`. The WAVs live in `assets/audio/machines/` (gitignored, plus the
`.gdignore`d `_source/` recordings) and are rebuilt from the committed recipe
`tools/audio/machine_sounds.json` by `tools/audio/machine_clips.py`; every
loop is RMS-normalised to −20 dBFS so the `.tres` `gain_db` slider is the only
place relative loudness lives. **Every level in those `.tres` is a placeholder
until the operator has played** — the notes say so. Guard:
`test_machine_sounds` (80 checks, in `run.sh`). Three rulings this hangs on:
the compactor's 1:11–1:14 ×3 sequence is a LOOP (not an event), the two dryer
windows await an L/R assignment, and which valve the crank was recorded on is
an assumption (hose-reel base valve + IBC drain). `docs/AUDIO_machine_sounds_2026-09-25.md`.

## Placed machines must be given a sim brain

A catalog placeable is geometry. Some machines also own a *simulation*, and that
is attached by `MachineBrains.attach()` from the tail of
`PlaceableCatalog.build_node()`.

This is not decorative plumbing. Measured on 2026-08-11, a booted MainWorld on a
real 84-placeable save contained **8872 nodes across 67 scripts and zero
`ExtruderMachine.gd`**, and a 90-second recording of every EventBus signal
produced **0 events**. `ExtruderModel` is constructed in exactly one place
(`ExtruderMachine.gd:54`), on exactly one scene (`Extruder3B.tscn`), which was
instantiated by exactly two scripts: `ExtruderGauntlet.gd` (a bench) and
`LegacyPropsSpawner.gd` — and the latter is gated behind
`not WorldLayout.is_configured()` (`MainWorld.gd:244`). So every real save
printed *"WorldLayout is authoritative — skipping legacy utility/demo spawns"*
and no extruder ever simulated. What was dark: the vacuum cascade and its 120 s
grace, `machine_state_changed` / `machine_alarm_raised` / `scada_event`
entirely, the HMI MACHINES screen and 7-zone panel (`HmiOverlay` enumerates
`get_nodes_in_group("extruder_machine")` in five places), and the SWI-049
startup flow `SorteerlijnScope` drives against that same group.

If you add a machine that owns a model, add it to `MachineBrains.EXTRUDERS` (or
a sibling table) rather than instantiating it from a world script. Rules the
hook already honours: config is assigned **before** `add_child` (`_ready()`
builds the model from it), the brain's placeholder mesh and collider are
switched off because the catalog model is the visible machine, each brain gets
its **own duplicated** `ExtruderConfig` (a shared one means editing a zone
setpoint on the HMI retunes the other line), and `attach()` is idempotent so
`rebuild_in_place()` cannot stack two.

`tools/regression/run.sh` does **not** cover this — its world places no extruder
at all, so it stayed green for the entire period the brain was missing. The
guard is `src/tests/test_extruder_brain_wired.gd`:

    godot --headless --path . res://src/tests/test_extruder_brain_wired.tscn

13 checks, including negative controls (a non-extruder placeable and a build
mode ghost must NOT get a brain) and a behavioural check that driving
`_pending["start_production"]` really produces `machine_state_changed`. It has
been mutation-tested: reverting the `build_node` hook turns 4 of the 13 red.

## The extruder warm-up, and a citation that was wrong

A cold barrel used to be a dead end. `#218` spawns the model `OFF`, `_ready`
hands the barrel over hot, and `_tick_off` cools it 0.5 °C/s — so after ~50 s
the melt is below ~190 °C, cold-melt torque (+2 %/°C on top of a 110 % trip that
fires after 2 s sustained) trips every start, and **no operator input anywhere
turned the heaters back on.** Measured over a recorded shift: **81 % of starts on
3A and 98 % on L1 went STARTING → FAULT.**

`State.PREHEAT` fixes that. Pressing start on a cold barrel routes to PREHEAT
(`ExtruderModel._route_start_request`), the heaters warm the melt toward
setpoint, and the green button is not live until `preheat_ready()`. The ready
threshold is *derived* rather than picked: the melt temperature at which
cold-melt torque still leaves 25 % headroom under `TORQUE_TRIP_PCT` (110 %)
AND under `LUMP_PASSTHROUGH_TORQUE_PCT` (95 %, where un-melted lumps start
reaching the laserfilter), whichever is warmer: **201.875 °C** on 3A/3B.
Until 2026-09-25 only the torque trip counted (196.25 °C, i.e. 97.5 % torque),
so the green button accepted a melt that passes lumps; a restart pressed the
moment it went green caked the screen and tripped 318 bar in 3.3 s. Operator
ruling, `docs/plant/operator_rulings_2026-09-25.md` §E3.

**How a start runs (operator rulings 2026-09-25, same file §E1-§E5).** A start
ramps the screw from standstill to the operator's rpm SETPOINT at 20 rpm/s
(60 rpm in ~3 s), and a stop does not change the setpoint. 60 rpm is the floor
(`ExtruderConfig.screw_rpm_min`) and a new extruder's setpoint; after a 318 trip
the operator drops a line to 60 to get it going again, because at 100+ rpm it
re-trips while ramping (measured: a caked screen re-trips at 110 at 4.7 s, and
runs at 60). He rejected "every start goes to 60" in so many words: *"That's not
how operating works."* The setpoint is set per line: the all-lines web HMI has a
line strip above the WebView (it used to drive only the FIRST extruder in the
group), and the touchscreen's extruder zone panel has an rpm row. A model's
first start no longer re-ramps from idle over `startup_ramp_s` (a
LIFETIME-runtime ramp that made first and later starts differ; the field is no
longer read). Guard: `test_extruder_start_rpm` (27 checks, 11 mutations red).
The raw WinCC archive agrees on the floor and on starts returning to the old rpm
after short stops, and points at a ~5 s ramp where he says 3 s; he kept 3 s.

**The start button and its natraject (operator rulings 2026-09-25, same file
§I1-§I10).** The press (E at the machine, or `_pending["start_production"]`)
is the RIGHT white LED ring button, and it no longer starts the screw by
itself. `ExtruderStartSequence` (held as `model.start_seq`, ticked by
`ExtruderMachine`):
- runs the checks the sim can make (each natraject machine found, not tripped,
  choked, in HAND or held by the line's e-stop);
- then switches on blower + weegschaal, centrifuge, ontwaterzeef, heetafslag and
  laserfilter, each once the one before is up, then the screw;
- blinks the ring 0.5 s off / 0.5 s on meanwhile, solid with the screw.

A failed check latches alarm 4401 (a SIM code) and the button is dead until the
HMI resets it: RESETTEN on the extruder panel, or ALARM RESET on the extruder
panel or the web strip. Never E at the machine: *"I can't press E in real life
by looking at the extruder"*. A natraject machine that stops under the screw
trips it (FAULT `natraject_stopped`), and a stop runs the natraject down in
reverse after the screw stands. The extruder, not the line, runs its own
LineFlow node and natraject (`LineFlow.claim_node`; the line's start no longer
powers them). The hidden "natraject" setting (default ON, a switch on both
extruder HMIs) turns all of it off: the screw alone. A bench rig with no pellet
side switches it off. Guard: `test_extruder_start_interlock` (32 checks, 14 mutations red).
That left an extruder that is off backing its line up to LineFlow's 250 kg
e-stop in 16 min at 950 kg/h, inside a cold barrel's 30-min warm-up. So, from
his next answers (same file §I11, §I13):
- the PCU belt (compactorband) feeds only while the PCU pot (the extruder
  node's input) is under `CutterCompactor.POT_CAPACITY_KG`, 60 kg; a full pot
  stops the belt and the silo's discharge, so the silo fills;
- each extruder silo has a laser level sensor (`LineFlow._tick_silo_feed_stops`)
  reporting a 1 s running average once per second, as % of `SILO_FULL_KG`;
- at >= 100 % the silo's feed stops at once: on 3A/3B the VSS dosing screw
  M11a and the VSS's own discharge, on line 1 the shredder. It runs again after
  10 reports in a row under 100 %. HAND bypasses it, as HAND bypasses every PLC
  safeguard.
Guard: `test_extruder_silo_feed_stop` (17 checks, 9 mutations red). A load still
starts cold with every extruder OFF (§I12, a separate task).

**Duration comes from the docs, not from feel.** `ExtruderConfig.preheat_min_s`
= 1800 s, from Cedo-PROD-SWI-042 p4 step 19: starting the 3a/3b extruder
compactors *"duurt altijd minimaal 30 minuten, in deze opwarm tijd, kunnen de
silo's verder vullen"*. That same step records *"Nog SWI maken opstarten
extruders"* — there is no dedicated extruder start-up SWI — which is why step 19
is the authority.

**Citation fix.** `ExtruderMachine._ready()` used to point at SWI-049
"Automaatknop → Voorverwarmen (15 s preheat) → Groene drukknop". SWI-048 and
SWI-049 are both *Opstarten sorteerlijn* — the **sorting line**, a different
machine. Anyone reading that comment would have modelled a 15-second extruder
preheat off a sort-line document. The comment now cites SWI-042 p4 §19.

**Check every SWI id against `docs/plant/swi/INDEX.md` before implementing from
a code comment.** A full audit of all 54 citation sites in `src/` and `tools/`
(`docs/plant/swi_citation_audit_2026-08-11.md`) found every cited id real, but
**two pointed at a document about a different machine** — the failure mode is not
a dangling reference, it is a plausible, authoritative-looking citation that
survives review. `ExtruderGauntlet.gd` also blamed SWI-049 for the extruder, and
`ShredderMachine.gd` cited SWI-042 for cleaning shredder 2 (which has no SWI at
all). Note that SWI-042's *title* is about a knife change while its *page 4* is
the shift start-up schedule, so always cite page and step, not just the id.

`State.PREHEAT` is **appended as 8**, never inserted: the first eight values are
carried in saves, `machine_state_changed` payloads and recorded event streams,
so renumbering them would silently rewrite history. The guard test asserts the
numbering.

## A test file can rot without anyone noticing

`tools/regression/run.sh`'s parse gate is `--headless --path . --quit`, which
boots the main scene. Nothing under `src/tests/` is on that path, so a test
script can stop compiling and stay broken indefinitely while the harness reports
green. Measured 2026-08-11: `test_npc05_realworld.gd` — the REAL MainWorld proof
for the npc-05 container chain, written precisely because the bench stubs the
execution half — referenced `_backup_files()`, `_run()` and `_finish()`, none of
which existed. It had never once run.

The harness sweeps the tree for files that do not parse. **As of 2026-08-23 it
sweeps ALL of `src/` and `tools/`, not just `src/tests/`** — the old test-only
version was measured missing the `PlaceableCatalog` breakage above, because all
27 red files reported the same *inherited* error and none named the culprit.

`tools/regression/parse_sweep.gd` does it in ONE boot (~15 s) instead of one
`--check-only` engine start per file (~6 min for 312). It gates on
`ERR_PARSE_ERROR` (43) only, for the same reason as before — 47 files report
`ERR_COMPILATION_FAILED` (36) purely from how the sweep invokes the compiler, and
a permanently red step is one everyone learns to skip. Mutation-tested both ways:
the repaired tree is 316 ok / 0 fail; restoring either broken file turns it red
and NAMES it.

Read `parse_sweep.gd`'s header before changing its detector. Two obvious ones are
already disproven there: `ResourceLoader.load() == null` (a file with a hard
parse error still loads NON-null — that version reported 316 ok on a broken
tree), and recompiling a file's source text into a fresh `GDScript` (no `res://`
identity, so 200+ healthy files report 43).

## The npc-05 container chain stalls at DRIVE_TO_INDOOR

What the restored harness reports (`NPC05_WATCH_S=180`):

* a stock world has **zero indoor WasteContainers**. `ContainerGuideManager`'s
  per-machine pass builds *hologram guides* marking where a bin belongs; the
  only real container it spawns is the outdoor skip in `WORLD_CONTAINER_SPAWNS`.
  The source bin is the operator's to place, so the board correctly emits
  nothing and the chain cannot start at all. The harness now places one on a
  real guide slot through the catalog and fills it via `WasteContainer.add()`.
* with a full bin the board dispatches immediately: WALK_TO_FORKLIFT at t=4.5 s,
  DRIVE_TO_INDOOR at t=6.2 s.
* it then **stalls in DRIVE_TO_INDOOR for the rest of the window**. The worker
  boards (`task._boarded = true`) and sits on the forklift (0.1 m away), the
  target bin is **33.9 m** off, and the forklift does not cover it. The phase
  budget (123.5 s) expires, the task is re-emitted, another worker takes it, same
  result. This is the same dead-reckoning vehicle autopilot weakness that
  `ContainerGuide.gd` already records for the yard leg — it fails on a 34 m
  indoor leg too.
* the **boarding-deadlock guard never fires**, because its premise no longer
  holds: it watches for `set_physics_process(false)` on a seated worker, and
  `physics_process` stayed true on every observed frame even with
  `_boarded = true`.

## A flaky test usually means a nondeterministic INPUT

`test_nav_connectivity` failed about one run in three, always on a different
worker, for long enough that two diagnoses were tried and reverted (a navmesh
bake race, and snapping posts to the nearest mesh point — both measured, both
disproven, both recorded in the file). Neither was the cause.

The cause was that the harness builds its line-3A fixture straight from the
catalog and never called `line_flow.rebuild()` — `BuildMode` does that after
every placement. `CrewManager._machine_list()` reads `line_flow._nodes`, so it
saw zero machines, so `assign_posts()` took its `no machine in zone` fallback
for all nine workers and set the post to `w.global_position` — wherever that
worker was standing mid-walk. The test was routing eight wandering floor
positions and failing whenever one landed off-mesh.

Fixed by rebuilding LineFlow before assignment. Posts are now real stations and
the result is byte-identical across 9 runs. Two anti-vacuity guards keep it that
way: `checked > 0` (already there) and a new one asserting posts actually carry
a station id, because eight random floor points will always route *sometimes*.

**It is deterministically RED**, reporting 6 unroutable legs at 4 named stations
(`extruder_3a`, `centrifuge`, `mengsilo`, `wind_sifter`). Do not silence it by
widening `POST_ENDPOINT_TOL_M` or dropping workers from the fixture.

#### 2026-08-28 — it went GREEN, then PR #118 turned it red again at one station

The "deterministically RED" line above is no longer the whole truth, and the
sequence matters more than either endpoint:

* `CrewManager._post_pos_on_aisle` (the AISLE-BESIDE-THE-MACHINE fix this
  section calls for) landed and **worked**: measured on `9981a6b`, the
  pre-merge main, `Result: PASS (10 ok, 0 fail)` with 41 static bodies.
* Merging **PR #118** (the 3A recomposition to ruling 2.1-B) put it back to
  `Result: FAIL (8 ok, 2 fail)`, measured identically on 3 of 3 runs — so this
  is NOT the old one-in-three flake. Two failures:
  1. `machine fixture present` — the fixture asserts `machines >= 40` and 3A
     now builds **38** static bodies. That threshold is a stale magic number,
     but do not just lower it: check the count against the 2.1-B composition
     that `test_line3a_flow_conformance` asserts before touching it.
  2. Abdellilah and Mohammed both post at `wind_sifter` (-215.6, 82.8) and
     cannot route back from the canteen (14.32 m short).

  **The stable fact is a NAVMESH GAP, not a post inside a collider.** Across
  runs the post position, the 14.32 m shortfall and `nearest mesh dXZ 0.92 m,
  +1.10 m above floor (ISLAND)` never move, but the overlap term is NOT stable
  — the same code reported `inside [@StaticBody3D@2425 1.2x1.0 m]` on three
  runs and `inside [nothing]` on the next. Do not chase the collider: the post
  stands in open space that simply has no floor-level navmesh, and the only
  mesh within reach is a sliver ~1.1 m up (`cell_height` 0.60 quantisation) on
  top of the neighbouring kit.

  A post-placement fix was tried 2026-08-28 and **measured as not working**. This
  paragraph used to say it was "kept at
  `scratchpad/CrewManager.gd.attempt_navpost.bak`" — that file is GONE. There is no
  `scratchpad/` in the repo, and an all-drive name search on 2026-09-24 found no copy
  anywhere. The description that follows is all that is left of it. It searched the
  worker's side plus four cardinals, accepting only spots that were physically
  clear AND had floor-level navmesh within 0.75 m. Every direction was rejected
  out to `STAND_MAX_PUSH_M` (4.0 m), i.e. **there is no floor-level navmesh
  anywhere within 4 m of that post**. That points at navmesh coverage around
  3A's repacked infeed (or the spacing of the machines there), not at
  `_post_pos_on_aisle`. Reverted rather than shipped: it changes where ALL crew
  stand, and per this section's own rule that is an operator call.

### The red is a CREW defect, not a navmesh one (measured 2026-08-12)

The paragraph above used to call it "a real navmesh/topology defect". It is not,
and the correction matters because it points the next person at the wrong file.
The test now prints a `why` line for every broken leg, and all five failing posts
read the same:

    why Kevin   nearest mesh dXZ 0.00 m, +1.10 m above floor; canteen->it ends
                3.68 m short (ISLAND); inside [Extruder 3A 14.0x2.6 m]

Every failing post is **inside a named machine's own collider** — `Extruder 3A`,
`Centrifuge`, `Mixing silo (mengsilo)`, `Windshifter (zigzag)` (x2). By
construction: `assign_posts` sets the post to the machine's own
`global_position` (`CrewManager.gd:276`), and MainWorld bakes that same collider
as navmesh source geometry, so a stationed post always lands inside the hole its
own machine carved. `post->canteen` then goes nowhere (10.8-40.5 m short) while
`canteen->post` lands in the aisle 1.6-3.7 m away and mostly passes — exactly the
asymmetry the file predicts.

Two consequences worth having in writing:

- **Snapping posts to the nearest navmesh point cannot fix this.** The nearest
  point is dXZ **0.00 m** away (1.10 m above the operating floor): a sliver
  Recast left inside the machine footprint, lifted by `cell_height` 0.60
  quantisation, enclosed and unroutable. The snap is a no-op in plan, which is
  the whole reason the 2026-07-29 attempt
  measured as "fixes nothing", and it is why repeating it will fail again. A real
  fix places the post in the AISLE BESIDE the machine — a change to where crew
  stand, so an operator call, not a test tweak.
- The check's own convention already says posts that are CrewManager's fault are
  reported (`ADVIS`) rather than asserted — that is how off-site posts are
  handled. Whether this one moves to `ADVIS` is the same operator call. Until it
  does, the harness stays red for a reason that is real but is not navigation's.

### The bake race was re-tested 2026-08-12 and is dead

Worth stating flatly, because it is the hypothesis everyone reaches for first and
this is now the third time it has been chased. Across **20 runs** (10 pre-fix at
`ea54e19^`, 10 post-fix at `ea54e19`) every navmesh-only measurement was
identical, in the failing runs as well as the passing ones:

    baked navmesh: 279 polygons (server map iteration 3)      20/20
    route AROUND the machine row: 13 points                   20/20
    inside -> outside: 12 points, ends 0.00 m from goal       20/20

A race would move those numbers. Only the POSTS moved. The synchronisation point
people propose adding — waiting on `NavigationServer3D.map_get_iteration_id()`
rather than a frame count — has been in `_wait_for_bake()` since 2026-07-29;
`test_nav_connectivity.gd` records that it was added for this flake and did not
fix it. Measured failure rate of the pre-fix version in this batch: **1 of 10**
(the earlier estimate was ~1 in 3; either way it is a coin toss, and the post-fix
version is 10 of 10 byte-identical, not merely 10 of 10 same-verdict).

## The headless teardown segfault is real, and it skips `_restore_files()`

`run.sh` keys off the printed verdict rather than the exit code, with the comment
"Godot can segfault in teardown after a clean PASS". Measured 2026-08-12 over
**62 batched headless MainWorld boots**: it segfaults **24 %** of the time
(15 of 62 — 2 of 10 `test_outdoor_route`, 13 of 52 `test_nav_connectivity`).
Keying off the
verdict is CORRECT and load-bearing: in every segfaulting run the log ends
exactly at the verdict banner, after every check has executed, while a clean run
continues on to the `ObjectDB instances leaked at exit` warnings. No verdict was
ever wrong.

**But it is not harmless, and this is the part nobody had measured.** `_finish()`
runs `_world.queue_free()` → `await process_frame` → `_restore_files()` →
`quit()`. The crash lands in world teardown — i.e. BEFORE the restore. Proof:
after the batch, `__outdoorroute___save.json` and `__outdoorroute___factory.json`
were still sitting in `user://`, which only happens when `_restore_files()` never
ran. Both tests list **`user://world_layout.json` in `PROTECT`**, so roughly one
run in four the safety net over the world's ground truth — the file this document
already flags as being in git nowhere — is simply skipped. It came through every
boot byte-identical against a `.bak`, so nothing is lost today; the exposure is
the finding, and it is the same failure mode already recorded for killed runs.
Take a `.bak` of `world_layout.json` before batch-running any MainWorld suite.
(2026-09-25: the suites no longer write it at all, and the restore of their own
slot files now runs BEFORE the world is freed as well as after; see "Save files
go through `AtomicFile`".)

## `test_outdoor_route` does not share the navmesh race — it has no navmesh

Worth writing down because the two files sit next to each other in `run.sh` and
the assumption is natural. `test_outdoor_route` has NO bake wait at all, only a
fixed `BOOT_FRAMES + SETTLE_FRAMES` — which looks exactly like the thing that
races. It cannot: vehicles route through `VehicleRouteGrid`
(`BaseVehicle._plan_route`, `BaseVehicle.gd:1043`), a synchronous occupancy grid
built from physics shape queries, with no `NavigationServer3D` involvement
anywhere in the path. Measured 10 runs: **10/10 PASS, all four gated checks one
hash** — 4 waypoints and 2.19 m arrival, identical every run.

## Branch state

`main` is the integration branch. Work happens on feature branches and lands via
PR. Check where you are before trusting anything — this repo has had a local
`main` sit 118 commits behind `origin/main` while a daily sync script reported
"in sync" (that script only syncs the *checked-out* branch).

**Merges into this repo have now silently reverted a fix three times**, always in
the same two files, always leaving the project unable to compile: `4ce7627` and
then `7b72ecf` mangled `BaleYardManager.gd` (its own header documents the first),
and `7b72ecf` also took the older side of `PlaceableCatalog.gd`'s
`_build_heetafslag_strand_switcher` and undid `ed9198b`. These two are the
biggest, most-edited files in the tree and they conflict on almost every merge.
**After ANY merge, run the full-tree parse sweep before anything else** — it is
15 seconds and it is the only step that would have caught all three:

    godot --headless --path . --script res://tools/regression/parse_sweep.gd

## Where session memory lives

The operator's cross-project memory is scoped to `V---Claude`
(`C:/Users/arnod/.claude/projects/V---Claude/memory/`) and is **not loaded by
sessions opened inside this repo**. That is why durable CeDo knowledge belongs in
`docs/` and in this file — committed, and therefore findable by everyone.
