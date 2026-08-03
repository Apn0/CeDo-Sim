# Extruder-line docs→code — status tracker (#223)

Tracker for the "implement the documentation in the code" sweep. Derived from the
5-agent doc↔code audit + operator corrections.

**STATUS: all 22 items done + centrally verified.**
Verification (this pass): class-cache reimport `exit 0, 0 parse errors` · weigh-hopper
unit test `PASS` · world regression `14 ok / 0 fail` incl. **38/38 machines inside
the building footprint** (line 3A grew 33→38 with the back-end chain, all inside).

Legend: ✅ done + verified · 🟡 done, behaviour not unit-tested · ⚠️ note

## Batch 1 (single edits)

| # | Item | Status | Where |
|---|------|--------|-------|
| 1 | Laser filter MOTOR-driven (M1 disc + afvoervijzel motors); ΔMP readout only | ✅ | `LaserFilter.gd` |
| 2 | 318-bar upstream trip — latches + halts filter + fires signal | ✅ | `LaserFilter.gd` |
| 3 | EREMA brand (was EIRENE) | ✅ | `PlaceableCatalog.gd`, `ExtruderGauntlet.gd` |
| 4 | Two screen discs (extruder-unit filter) | ✅ | `PlaceableCatalog.gd` §4 |
| 5 | ΔMP trip constant → 318 | ✅ | `EremaFaultRegistry.gd` |
| 6 | Mesh cage around the 4 PCU support pillars | ✅ | `PlaceableCatalog.gd` §1 |
| 7 | HMI M1-load % + afvoervijzel motor setpoint | ✅ | `LaserFilter.gd` |
| 8 | Gauntlet is NOT a save file (wipes each launch) | ✅ | `ExtruderGauntlet.gd` |

## Batch 2 — the 14 (ultracode pass, 6 parallel agents)

| # | Item | Status | Where |
|---|------|--------|-------|
| 9 | Per-line barrel stencil — LINE ONLY ("3A"/"3B"/"1"/"3C"/"6"), no number | ✅ | `PlaceableCatalog.gd` |
| 10 | HMI pressure scale 0–10 → **0–350 bar** | ✅ | `LaserFilterScope.gd` |
| 11 | HMI colour bands (green ≤250, yellow 250–300, red >300) | ✅ | `LaserFilterScope.gd` |
| 12 | HMI **ΔMP-MF1 setpoint** box (0–300 bar) | ✅ | `LaserFilterScope.gd` |
| 13 | ΔP model → bar-realistic (clean-screen base + cake term; 175–235 bar sawtooth) | ✅ | `LaserFilter.gd` |
| 14 | 318-trip **full cascade** — stops compactor+extruder+pelletiser together | 🟡 | `ExtruderMachine.gd` — wired + parses + boots; trip behaviour not yet unit-tested |
| 15 | Back-end chain (heetafslag→ontwaterzeef→centrifuge→weegschaal→voorraadsilo) on lines 1/3A/3B | ✅ | `BuildMode.gd` — regression: **38/38 inside footprint** |
| 16 | Weegschaal 25-kg batch weigh+dump + production counter | ✅ | new `WeighHopper.gd` + `MachineFlow.gd` — unit test PASS |
| 17 | Pelletiser 160-bar melt-pressure interlock | 🟡 | `EremaFaultRegistry.gd` — detector wired; behaviour not yet unit-tested |
| 18 | Standalone `laser_filter` placeable: 2 discs + downward afvoervijzel discharge | ✅ | `PlaceableCatalog.gd` |
| 19 | Meltpump drive motor on top | ✅ | `PlaceableCatalog.gd` §6 |
| 20 | Ontwaterzeef trilnaald-followup + basin-flush settings | ✅ | `MachineFlow.gd` |
| 21 | Screen-mesh grades L1/L3a/L3b | ✅ | `LaserFilter.gd` |
| 22 | Heetafslag comment: hot die-face (not "underwater pelletizer") | ✅ | `PlaceableCatalog.gd` |

## Operator corrections applied (I had these wrong)

| Thing | Truth | Result |
|-------|-------|--------|
| Trip value | **318 bar** (plant), not 320 (manual) | reverted ✅ |
| Extruder naming | "right after line 3A" — line only, no position number | line-only stencil ✅ |
| PCU location | already correct (feed end) | no change ✅ |
| Extruder per-line | catalog already per-line | no change ✅ |
| Lump carts | **1** correct for the four extruders | kept 1 ✅ |

## Remaining (behaviour verification, not code)

- **14 + 17** — the 318-bar and 160-bar trips are wired and boot clean, but I have not
  yet driven a live over-pressure event to watch all three units stop. Needs a targeted
  headless test (spike the pressure → assert compactor+extruder+pelletiser all halt).
