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

Last measured run: **`16 ok, 0 fail, 2 skip`**.

`run.sh` gates on the fail count only, so **skips pass silently**. Two of the
things this file used to claim were "proven" are among the skips:

| claimed proof | reality |
|---|---|
| machines inside the building, fence 0-crossing, TL bars, round-trip | genuinely checked |
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

### OPEN CONTRADICTION — do not silently resolve

The operator's locked fact is **"one lump cart serves four extruders — do not
'improve' to two."** The code disagrees: `src/build/BuildMode.gd` places **six**
lump carts, two per line (`:159/:161`, `:379/:381`, `:471/:473`), and line 3C's
laser filter gets none. `BuildMode.gd:147-151` justifies it ("a cart under EACH
of the twin afvoerschroef nozzles"). One of these is wrong. **Ask the operator —
do not change either side on your own initiative.**

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
