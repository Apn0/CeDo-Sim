# Extruder line — component layout (operator spec 2026-07-15)

Source: two operator hand-annotated diagrams (side view = extruder 3C; top view, labelled).
This is the **source of truth** for the extruder-area model + per-line macros. It supersedes
any earlier guesswork about the laser-filter discharge / head-filter arrangement.

## Order along the barrel (left → right)

1. **Extruder motor** — far LEFT end of the barrel (drives the screw).
2. **PCU** — large unit sitting ABOVE the barrel near the motor end. Feeds material DOWN into
   the barrel through an **intake slider** (intrek/opzetschuif — the red dashed feeder in the
   top view).
3. **Extruder barrel / housing** — the long horizontal screw housing (the black rectangle).
4. **Laser filter housing** — straddles the barrel (centre). Comprises:
   - a **platform** (bordes) with a **ramp** (oprit) on the access/top side;
   - a **rear-side (achterzijde) afvoerschroef** — discharge screw exiting the REAR;
   - a **front-side (voorzijde) afvoerschroef** — discharge screw exiting the FRONT.
   - The two afvoerschroeven run PERPENDICULAR to the barrel (front + rear in top view) and drop
     lumps to a cart on each side. (In the side view the filter is the big concentric DISC.)
5. **Vacuum 1 + 2** — TWO vacuum degassing units, on/below the barrel just after the laser filter
   (the twin `||` box in the side view).
6. **Melt pump** — a GEAR pump (⚙), between the vacuum units and the head filter.
   **ONLY on extruder 3C.**
7. **Head filter unit** — RIGHT end, on the barrel (side view shows TWO circles = two filter
   chambers), with a **head-filter safety hood / cabinet doors** below/around it.
8. Angled discharge off the right end.

## Per-line variants

| Line | Melt pump (step 6) | Final filter (step 7) |
|------|--------------------|-----------------------|
| **3C** | **YES** (gear pump) | Head filter unit + safety hood |
| **1, 3A, 3B** | **NO** (omit — vacuum feeds straight to head filter) | Head filter unit + safety hood |
| **6** | (per 1/3A/3B unless told otherwise) | **Britas** instead of head filters |

## Discharge / cart / platform (operator 2026-07-15, refined)
- The laser filter has TWO afvoerschroeven (front = voorzijde, rear = achterzijde), each with its **own cart** (one cart per side).
- **REAR (achterzijde) cart → sits on the RAISED PLATFORM** (`lump_platform`: bordes + ramp).
- **FRONT (voorzijde) cart → sits on the GROUND** (NO platform on the front side).
  → So only ONE `lump_platform`, on the REAR side; the front discharge drops to a floor-level cart.
### Laser-filter working principle (3A poster "De Laserfilter", 2026-07-15; YouTube rTRxburRXTc)
- Molten material from the extruder cylinder is directed INTO the filter. Inside are **2 screen discs
  (zeefschijven / "laserfilters")** with very small holes. Contaminated melt is pushed **between** the
  2 discs and, by pressure, **through** both — so the dirt stays on the **inside** surface.
- A **ronddraaiende schraper (rotating scraper)** wipes the dirt off the screen discs; it is discharged
  via the afvoerschroef. Cleaned plastic returns to the screw/cylinder and continues through the extruder.
- The poster cross-section shows discharge **UP (rear/achterzijde) and DOWN (front/voorzijde)** — this
  is WHY the **rear cart sits on the raised platform** (higher discharge) and the **front cart on the
  ground** (lower discharge). Model the afvoerschroef accordingly: rear = higher → platform cart; front
  = lower → floor cart. Replace the current symmetric vertical lift-towers; add the rotating scraper.
  (Confirm exact external auger shape with a render before finalising.)

## Root causes found (gap map 2026-07-15) — see `docs/plant/extruder_line_layout.md` history
- "2 laser filters" = `_m_extruder_unit` draws a built-in Section-4 disc AND a standalone `laser_filter`
  placeable is placed beside it (standalone is the functional one the sim binds). Fix = delete the
  built-in Section-4 disc. Same class as the compactor de-dup (ExtruderGauntlet.gd:115-118).
- "broken platform" = `lump_platform` placed by NO line macro (bench-only) + thin sliver + the built-in
  disc discharge missed it. Fix = fix platform geom + place it (REAR side) in the LINE_1/3A/3B macros.
- Melt pump drawn on every line → gate to 3C only (`_m_extruder_unit` Section 6).
- Britas (line 6), PCU-above-barrel + intake slider, head-filter safety hood, afvoerschroef mechanism
  = DEFERRED pending operator photos/decisions.

## 2026-08-03 — operator ruling: two carts per extruder, IMPLEMENTED on all four lines

Operator (verbatim intent): **"There have to be two carts per extruder, one at the
voor side, one at the achter side of the laser filter."** This re-confirms the
07-15 asymmetric layout above and closes the false "one cart serves four
extruders" contradiction that was flagged in CLAUDE.md — that line was the stale
2026-07-12 statement, superseded two days later by this document.

State as of this ruling, measured in a real MainWorld boot
(`src/tests/test_lump_cart_coverage.tscn`, 39 checks):

- **Lines 1 / 3A / 3B** already placed both carts (macro entries at ±1.30 around
  the filter, bordes cart at deck height 0.12, ground cart at 0) — unchanged.
- **Line 3C had ZERO carts.** Fixed: `BuildMode.LINE_3C_SEQ` now carries an
  APPEND-ONLY furniture tail (indices 32-36: bordes + 2 spots + 2 carts) anchored
  to the laser filter's own z via the new `{"at_entry": N}` key, so no
  macro_index → l3c_code address shifted and saved macros stay valid.
  `test_line3c_seq_alignment` guards the tail (mutation-proven: untagging,
  re-anchoring, or deleting a cart each turn a named check red).
- Every laser filter now binds BOTH nozzle carts through its own runtime catch
  windows, the bordes cart rides 0.120 m above the ground cart on all four
  lines, and each cart spawn volume is probed clear of the building shell.

### Naming cross (cleanup item, does not affect behaviour)
Measured 2026-08-03: under the macro rotation, the nozzle `LaserFilter.gd` NAMES
"aisle / +X / front-of-disc" (`lump_cart`, `eject_local_offset`) physically lands
on the **bordes side** on all four lines — which this document calls the
**achterzijde**. The refs work (each window binds its own cart; discharge splits
per active nozzle) but the local labels are crossed relative to plant vocabulary.
Renaming touches external readers of `eject_local_offset` — do it as its own
sweep, not in passing.

### Still open (ask the operator / needs photos — do NOT build)
1. **3C MF1/MF2**: the LIJN 3C alarm list names Smeltfilter 1 AND Smeltfilter 2.
   If 3C physically carries two filter heads, is the ruling 2 carts total or 2
   per head (= 4)? Built as 2 total for now.
2. **Line 6 (Britas/ABMF band filter)**: it has uittrekschroeven (3-8 rpm sticky
   note) so a discharge exists, but no doc places its cart(s).
3. The **asymmetric nozzle VISUAL** (rear exits UP, front exits DOWN — poster
   cross-section above) is still not modelled; both downspouts remain symmetric
   at local ±1.30/1.13. Model work pending a render + operator confirm.
4. The 07-20 photo doc (`operator_issues_2026-07-20.md`) shows the filter as a
   floor-standing unit OFF the barrel ("not built yet, axis mapping needs
   confirming"). If that rebuild happens, which world side "voor" faces must be
   re-confirmed, and NpcTaskBench + the macros move together.
