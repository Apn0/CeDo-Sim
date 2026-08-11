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

`tools/regression/run.sh` runs **22 suites**. Since the perimeter-fence
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
9. Audit renders get a **per-line unique filename** (`shot_flotation_tank_3A.png`),
   never a shared name that overwrites the previous line's shot. Renders come from
   `src/tests/shot_placeable.tscn`:
   `<godot> --path . res://src/tests/shot_placeable.tscn -- <placeable_id> [yaw] [pitch]`

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

## Where things are

285 GDScript files, 105,241 lines under `src/`:

| dir | files | what |
|---|---|---|
| `src/scenes/` | 133 | world, player, NPC, vehicles, HUD/HMI |
| `src/tests/` | 72 | every proof; also the render + shot tools |
| `src/sim/` | 42 | LineFlow, TagMap, MachineFlow, machine models |
| `src/autoload/` | 19 | singletons (WorldLayout, SettingsManager, AudioManager…) |
| `src/build/` | 14 | `PlaceableCatalog` + `BuildMode` — the two biggest files |
| `src/data/`, `src/operator/`, `src/util/` | 5 | plant data, operator context |

## Doc index — `docs/`

| Doc | What it holds |
|---|---|
| `docs/plant/` | **Primary source of truth for the plant — start at `docs/plant/README.md`, the corpus index.** 414 `.md`: SWI procedures, HMI screens, trends, photo-audit ledger |
| `docs/plant/hmi_screen_inventory_2026-07-28.md` | Ground truth for the 34 HMI mockups — the **photos are authoritative**, the mockups are layout only |
| `docs/AUDIO_sound_engine_state_2026-08-03.md` | Both audio systems, the verified RD frame for the 43 positional clips, loop-crossfade + IMA_ADPCM trap, 3 open findings |
| `docs/BACKLOG_ultracode_2026-07-19.md` | Deferred queue — 16 of 40 findings landed; also records the npc-05 vacuous-green correction |
| `docs/DESIGN_SUGGESTIONS_2026-07-08.md` | Ranked roadmap, P1-P8 physicalization + Q1-Q8 QoL, every item file-cited |
| `docs/FULL_LOGIC_AUDIT_2026-07-08.md` | Runtime-behaviour audit, 25 findings. **Snapshot, no per-finding status.** Bug 0 / HIGH #1 / #2 are DONE; #7 `build_wall` meta, #12 Walkie→VoiceService and 5 dead files still open. Re-measure before acting |
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

## Branch state

`main` is the integration branch. Work happens on feature branches and lands via
PR. Check where you are before trusting anything — this repo has had a local
`main` sit 118 commits behind `origin/main` while a daily sync script reported
"in sync" (that script only syncs the *checked-out* branch).

## Where session memory lives

The operator's cross-project memory is scoped to `V---Claude`
(`C:/Users/arnod/.claude/projects/V---Claude/memory/`) and is **not loaded by
sessions opened inside this repo**. That is why durable CeDo knowledge belongs in
`docs/` and in this file — committed, and therefore findable by everyone.
