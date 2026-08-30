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
— this is what `tools/regression/run.sh:17` defaults to, override with `GODOT=`.

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

`tools/regression/run.sh` runs **23 suites**. Since the perimeter-fence
deletion (operator order 2026-08-07) it ends `== done (exit 1) ==`:
`test_jam_baseline`'s jam1 leg now wedges **10.0 s (budget 3.0) on the parked
`VolvoV40Placeholder` in the staff parking lot** — the fence used to wall that
lot off the yard→plant bearing, and the pilot dead-reckons (route planning
already returns NO ROUTE because the target is inside the building — a
pre-existing gap). Measured with an intersect_shape probe at the recorded wedge
point (-115.26, -8.60, 138.19). The fix direction (pilot evade vs outdoor road
routing vs re-baselining the leg) is an operator decision — do not silently
re-tune the budget. Every other suite is green.
Last full run 2026-08-07, after the fix below; `test_l3c_unit_screens` alone is
`Result: 120 ok, 0 fail, 0 skip` and takes minutes, not hours.

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

| dir | files | what |
|---|---|---|
| `src/scenes/` | 133 | world, player, NPC, vehicles, HUD/HMI |
| `src/tests/` | 93 | every proof; also the render + shot tools |
| `src/sim/` | 47 | LineFlow, TagMap, MachineFlow, machine models |
| `src/autoload/` | 19 | singletons (WorldLayout, SettingsManager, AudioManager…) |
| `src/build/` | 16 | `PlaceableCatalog` + `BuildMode` — the two biggest files |
| `src/data/`, `src/operator/`, `src/util/` | 5 | plant data, operator context |

## Doc index — `docs/`

| Doc | What it holds |
|---|---|
| `docs/plant/` | **Primary source of truth for the plant — start at `docs/plant/README.md`, the corpus index.** 419 `.md` (counted 2026-08-28): SWI procedures, HMI screens, trends, photo-audit ledger |
| `docs/plant/hmi_screen_inventory_2026-07-28.md` | Ground truth for the 34 HMI mockups — the **photos are authoritative**, the mockups are layout only |
| `docs/AUDIO_sound_engine_state_2026-08-03.md` | Both audio systems, the verified RD frame for the 43 positional clips, loop-crossfade + IMA_ADPCM trap, 3 open findings |
| `docs/anim_rig_unification_2026-08-28.md` | **Why the humanoid never animated:** limb meshes sat on dead pivot nodes while the AnimationTree drove boneless bones. Also the face-up prone, the 4 %-deep crouch found by MEASURING, the poses that sank through the floor, the double-player-body (`rebuild_appearance` didn't know the name `PlayerBody`), and the NPC jump latch that cleared on the impulse tick. 12 review findings, mutation-verified |
| `docs/AUDIT_handoffs_2026-08-16.md` | **Read before trusting any handoff doc.** Two 2026-08-16 handoffs claimed "Stable / Verified"; three of five claims described code not in the repo. Records 12 unmentioned defects (4 critical, now fixed + tested), the Rule 1 blocks, and the 3 findings that were refuted |
| `docs/AUDIT_project_sweep_2026-08-23.md` | **The sweep that found `main` did not compile.** Why both harness compile checks missed it, the BaleYardManager merge repair, FULL_LOGIC_AUDIT #7 confirmed + fixed and #12 REFUTED, the headless MultiMesh limit, and what a fresh clone can/cannot prove |
| `docs/BACKLOG_ultracode_2026-07-19.md` | Deferred queue — 16 of 40 findings landed; also records the npc-05 vacuous-green correction |
| `docs/DESIGN_SUGGESTIONS_2026-07-08.md` | Ranked roadmap, P1-P8 physicalization + Q1-Q8 QoL, every item file-cited |
| `docs/FULL_LOGIC_AUDIT_2026-07-08.md` | Runtime-behaviour audit, 25 findings. **Snapshot, no per-finding status.** Bug 0 / HIGH #1 / #2 / #7 are DONE (#7 fixed 2026-08-23, guarded by `test_project_sweep_guards`); **#12 Walkie→VoiceService is REFUTED — measured, the connect works**; 5 dead files still unverified. Two findings re-measured, one was wrong: re-measure before acting |
| `docs/DESIGN_hmi_tag_bridge_2026-07-22.md` | **Verdict: do NOT build the WebSocket HMI bridge.** Plus the slice that WAS built: `src/sim/TagMap.gd` |
| `docs/DESIGN_npc05_container_chain_2026-07-20.md` | Container-chain design (Dutch). ⚠️ Its "GEBOUWD" status was corrected 2026-07-21 — that proof was a vacuous green |
| `docs/research_film_physics_feasibility.md` | Film-physics R&D — GO on Jolt + GPUParticles3D + custom buoyancy; NO-GO on a Rapier backend swap. Correctly targets 4.6.3 |
| `docs/MESHROOM_BUILDING_HANDOFF.md` | Building photogrammetry handoff. Its `scratchpad/production_run.py` re-run path is **lost**; the 17 GB Meshroom cache now lives at `D:\CeDo_meshroom_cache` |

## Traps that have bitten before

- **`assets/` is gitignored** (`.gitignore:2`). 2.9 GB, `git ls-files assets` → 0.
  Every WAV, model and `.import` setting is local-only and does **not** survive a
  fresh clone. On a clean clone `PlantAudio` fails at its first check
  (`PlantAudio.gd:50`, missing `assets/audio/audio_layout.json`) — it does not
  merely lose the crossfade.
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
