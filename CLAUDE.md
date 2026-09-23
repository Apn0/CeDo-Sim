# CeDo Simulator

Godot **4.6** simulation of a real LDPE plastic-film recycling plant (CeDo, Geleen
NL) that the operator actually worked at. Not a generic factory game — the plant
is a real place and the sim is judged against it.

**This file is the entry point. If you are a fresh session, read this before
searching — and treat every number here as re-checkable, not as gospel.**

> Sessions opened inside this repo load NO cross-project memory. That is why
> durable knowledge belongs here and in `docs/`, committed. See the last section.

## Engine

```bash
bash tools/regression/run.sh          # the one command that proves things
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
| ~~`regression verdict`~~ | ~~door/gate check~~ — **FIXED 2026-09-13**: `structure_items` cleared from `world_layout.json` (was 1 entry from prior session work) |
| `test_nav_connectivity` | `every on-site post routes to the canteen and back (2 broken: Abdellilah canteen←post (ends 14.32 m short; post at (-215.6, 82.7)), Mohammed …)` — 9 ok, 1 fail since #216. **Requires operator to move crew posts off ISLAND** (inside wind_sifter collider). Do NOT auto-fix. |
| `test_npc05_realworld` | EXPECTED red — the DRIVE_TO_INDOOR stall, see below. Do not silence it |
| ~~`test_line3b_flow_conformance`~~ | ~~missing input edge in LineFlow topology~~ — **FIXED 2026-09-13**: added `explicit_from_prev: true` to plasmaq entry in `LINE_3B_SEQ` (gap 15 m > MAX_LINK_DIST 14 m) |
| ~~`test_project_sweep_guards`~~ | ~~B1b WorldLayout.structure_items starts empty (1 entries)~~ — **FIXED 2026-09-13**: cleared local world state |

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

Killing a mid-run suite leaves residue: `test_l3c_unit_screens` backs up its
`TOUCHED` `user://` files **in memory only** and restores them in `_finish()`, so
a kill loses the backups. Verified 2026-08-03 that `world_layout.json` survived
intact; `world_layout_consumed.flag` was left behind but no production code reads
it — only tests do.

### Within the suites that do run

`run.sh` gates on the fail count only, so **skips pass silently**. Two of the
things this file used to claim were "proven" are among the skips:

| claimed proof | reality |
|---|---|
| machines inside the building, TL bars, round-trip | genuinely checked (the fence 0-crossing check died with the fence — deleted per operator order 2026-08-03) |
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

313 GDScript files, 109,663 lines under `src/` (measured 2026-08-23; the
previous "285 / 105,241 / 72 tests" in this table was ~6 months stale, so treat
this one as re-checkable too — `find src -name '*.gd' | wc -l`):

| dir | tracked `.gd` (2026-09-05) | what |
|---|---|---|
| `src/scenes/` | 135 | world, player, NPC, vehicles, HUD/HMI |
| `src/tests/` | 151 | every proof; also the render + shot tools (109 are `test_*.gd`) |
| `src/sim/` | 47 | LineFlow, TagMap, MachineFlow, machine models |
| `src/autoload/` | 19 | singletons (WorldLayout, SettingsManager, AudioManager…) |
| `src/build/` | 16 | `PlaceableCatalog` + `BuildMode` — the two biggest files |
| `src/data/`, `src/operator/`, `src/util/` | 5 | plant data, operator context |

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
| `docs/audit/assets_loss_and_restore_2026-09-21.md` | **`assets/` was wiped and restored.** Godot's `.md5` fingerprints identify originals byte for byte: 159 of 273 are back exact and 101 are cache-only (listed; do not re-import them). Also the `Merlo.fbx` re-import trap, what `winfr` did and did not recover (nothing exact), and the method to reuse |
| `docs/BACKLOG_ultracode_2026-07-19.md` | Deferred queue — 16 of 40 findings landed; also records the npc-05 vacuous-green correction |
| `docs/DESIGN_SUGGESTIONS_2026-07-08.md` | Ranked roadmap, P1-P8 physicalization + Q1-Q8 QoL, every item file-cited |
| `docs/FULL_LOGIC_AUDIT_2026-07-08.md` | Runtime-behaviour audit, 25 findings. **Snapshot, no per-finding status.** Bug 0 / HIGH #1 / #2 / #7 are DONE (#7 fixed 2026-08-23, guarded by `test_project_sweep_guards`); **#12 Walkie→VoiceService is REFUTED — measured, the connect works**; 5 dead files still unverified. Two findings re-measured, one was wrong: re-measure before acting |
| `docs/DESIGN_hmi_tag_bridge_2026-07-22.md` | **Verdict: do NOT build the WebSocket HMI bridge.** Plus the slice that WAS built: `src/sim/TagMap.gd` |
| `docs/DESIGN_npc05_container_chain_2026-07-20.md` | Container-chain design (Dutch). ⚠️ Its "GEBOUWD" status was corrected 2026-07-21 — that proof was a vacuous green |
| `docs/research_film_physics_feasibility.md` | Film-physics R&D — GO on Jolt + GPUParticles3D + custom buoyancy; NO-GO on a Rapier backend swap. Correctly targets 4.6.3 |
| `docs/MESHROOM_BUILDING_HANDOFF.md` | Building photogrammetry handoff. Its `scratchpad/production_run.py` re-run path is **lost**; the 17 GB Meshroom cache now lives at `D:\cedo_archive\meshroom\CeDo_meshroom_cache` (moved from `D:\CeDo_meshroom_cache` 2026-09-21) |

## Traps that have bitten before

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
- **F8 is a trap.** The project binds F8 to Inspect Mode (`SettingsManager.gd:660`),
  but when the game runs embedded in the editor F8 is the editor's **Stop**
  shortcut — `NpcTaskBench.gd:68`: "it killed the session." Use the observer key
  `O` in benches instead.
- **Stale-constant disease.** Geometry/UI built from hand-baked constants instead
  of measured runtime values. The harness once validated a stale constant against
  its own copy. Measure from the mesh, not from a saved number.
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
a short write, not an OS crash with the page cache unflushed. Tests that keep a
world booted past the 60 s autosave must set `WorldLayout.layout_path_override`
first, or that autosave rewrites the real `world_layout.json`.

## Operator feedback channel

**F10 is a multi-point marker tool** (`src/scenes/player/MarkerTool.gd`): LMB
places an orb, G snaps to grid/edge, H clears, RMB/F10 exits and writes
`user://feedback/<stamp>/markers.json` + `context.json` + a screenshot. When the
operator says "check feedback", read the newest directory under
`%APPDATA%/Godot/app_userdata/CeDo Simulator/feedback/`.

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
threshold is *derived* from the trip rather than picked: it is the melt
temperature at which cold-melt torque still leaves 25 % headroom under
`TORQUE_TRIP_PCT`.

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

  A post-placement fix was tried 2026-08-28 and **measured as not working** —
  kept at `scratchpad/CrewManager.gd.attempt_navpost.bak`. It searched the
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
