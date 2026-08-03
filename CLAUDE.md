# CeDo Simulator

Godot 4.2 simulation of a real LDPE plastic-film recycling plant (CeDo, Geleen
NL) that the operator actually worked at. Not a generic factory game — the plant
is a real place and the sim is judged against it.

**This file is the entry point. If you are a fresh session, read the doc index
below before searching — the answer is probably already written down.**

## Doc index — `docs/`

| Doc | What it holds |
|---|---|
| `docs/AUDIO_sound_engine_state_2026-08-03.md` | Both audio systems, the verified RD coordinate frame for the 43 positional clips, the loop-crossfade + IMA_ADPCM trap, and 3 open findings |
| `docs/BACKLOG_ultracode_2026-07-19.md` | Deferred findings from the 2026-07-19 ultracode session |
| `docs/FULL_LOGIC_AUDIT_2026-07-08.md` | Whole-project logic audit |
| `docs/DESIGN_hmi_tag_bridge_2026-07-22.md` | HMI ↔ tag bridge design |
| `docs/DESIGN_npc05_container_chain_2026-07-20.md` | NPC container-chain design |
| `docs/MESHROOM_BUILDING_HANDOFF.md` | Building photogrammetry handoff |
| `docs/research_film_physics_feasibility.md` | Film-physics R&D feasibility |
| `docs/plant/` | **Primary source of truth for the plant itself** — 400+ operator docs, SWI procedures, HMI screens, trends, photo audit ledger |

## Project rules (operator-stated, enforced in review)

1. **No build without docs.** Do not model plant components, vehicles, or how a
   machine sounds/behaves from imagination. Only from operator photos, specs, or
   explicit approval. `docs/plant/` is primary; photos illustrate.
2. **Measure, don't assert.** Every claim needs a number you actually produced.
   Prove fixes with the regression harness or a measured capture — never by
   reasoning about what the code should do.
3. **Bench greens prove the mock, not the feature.** A passing bench is not
   proof. `npc-05` passed 31/31 while destroying mass. Prove it in a real
   MainWorld boot, and check greens are not vacuous (a 0/0 suite is a failure).
4. **A review must check behaviour.** Files-present + compiles + green harness is
   not a review. That combo once passed while every save force-started the whole
   line. Always add a runtime-logic pass with a concrete trigger → wrong-outcome.
5. **Never delete — always `.bak`.** Copy to `<file>.bak` before removing or
   replacing any project file. Cleanup must be reversible.
6. **Implement docs into code the first time you read them.** Do not re-read and
   re-ask. Locked facts: EREMA LF 2/406 is MOTOR-driven (not ΔMP-driven); one
   extruder per line; one lump cart serves four extruders.
7. **Dutch operator vocabulary matters** — trilzeef, maalmolen, flotatietank,
   waslijn, doseersilo. `PhysicalSurface` has an `nl_name` field for this.
8. Every machine gets a light grime patina by default. Nothing is brand-new
   painted (global in `PlaceableCatalog._mat`).
9. Audit renders get a **per-line unique filename** (`shot_flotation_tank_3A.png`),
   never a shared name that overwrites the previous line's shot.

## Commands

```bash
bash tools/regression/run.sh
```
16 checks — proves world/save/exterior creation is correct (machines inside the
building, doors on walls, fence 0-crossing, TL bars inside + mounted,
round-trip, macro-corruption guard) and emits a top-down PNG.

Godot: `C:/Users/arnod/AppData/Local/Godot/godot.exe` (4.2 stable)

## Traps that have bitten before

- **`assets/` is gitignored.** Anything under it — every WAV, every `.import`
  setting, the models — is local-only and does **not** survive a fresh clone.
  Generator scripts under `tools/` are the committed source of truth; baked
  assets are derived artifacts.
- **Stale-constant disease.** Recurring bug class: geometry/UI built from
  hand-baked constants instead of measured runtime values. The harness once
  validated a stale constant against its own copy. Measure from the mesh, not
  from a saved number.
- **F8 stops the editor**, it does not stop the game. See the in-game driving
  notes before driving anything.
- **GauntletWorld is a visual bench only.** It omits the real shift systems
  (LineFlow/crew/SCADA). Trustworthy for "does it spawn/render", never for
  behaviour.

## Where session memory lives

The operator's cross-project memory is scoped to `V---Claude`
(`C:/Users/arnod/.claude/projects/V---Claude/memory/`) and is **not loaded by
sessions opened inside this repo**. That is why durable CeDo knowledge belongs
in `docs/` and in this file — committed, and therefore findable by everyone.
