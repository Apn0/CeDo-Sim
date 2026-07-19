# Operator issues — 2026-07-20

Captured verbatim-in-substance from the operator's report so none of it gets lost
again. Status is honest: BLOCKED means I must not guess, not that it's hard.

## A. Placement — BLOCKED ON OPERATOR (do NOT guess again)

### A1. HMI placement per line/section or per machine
**Operator: "I asked like 5 times to fix it already."** He is right to be angry,
and the reason it never moved is worse than a bad fix:

- There is **no HMI placement code at all**. `src/build/HmiScopes.gd` calls itself
  the single source of truth but contains zero position data — it maps panels to
  the machines they *control*, never to where they *stand*. `src/build/Hmi.gd`
  `_ready()` never sets a transform; a panel sits wherever it was dropped.
- The 13 scoped HMI placeables (`PlaceableCatalog.gd:483-498`) carry `size`,
  `color`, `hmi_id`, `mesh` — **no position, no anchor, no parent machine**.
- No line macro places any of them (`LineMacroStore.gd`: zero `hmi` hits).
- All 8 previous HMI commits (`dfbd218`, `6e7b91e`, `0e970f3`, `3eb0b14`,
  `bb88087`, `445fed3`, `f42b0d1`, `4968185`) changed screen CONTENT, wiring or
  scoping. **Not one of them could have moved a panel in space.** That is why
  five rounds of "fixed" changed nothing he could see.
- `docs/plant/photo_audit.md:149` still carries the open box:
  `☐ operator flagged HMI stand placement`. It was flagged and never closed.
- `f42b0d1`'s own commit body says: *HMI overhaul deferred ("ask me once we get
  there")*.

**What I need, per panel (13 of them):** which machine or wall it mounts to, and
on which face. Fastest path is F10 markers in-game — one orb where each panel
belongs — rather than describing 13 positions in text.

### A2. Cutter-compactor / PCU location vs the extruder + intake slit
There IS a spec and the code contradicts it:
- `docs/plant/extruder_line_layout.md:10-12` (operator spec, 2026-07-15):
  *"PCU — large unit sitting ABOVE the barrel near the motor end. Feeds material
  DOWN into the barrel through an intake slider (intrek/opzetschuif)."*
- The code puts it on the floor BESIDE the barrel: `PlaceableCatalog.gd:10128`
  `tw_z = -size.z * 0.42`, standing on four `machine_leg` posts with a base
  plate (`:10131-10137`), discharging through a tangential outlet + throat
  (`:10199-10201`).
- **The intake slider does not exist as geometry at all.** It exists only as an
  HMI readout: `ExtruderBluPortScope.gd:129` `ais_pct` / "AIS-positie".
- Same doc, line 60-61, lists `PCU-above-barrel + intake slider` as **DEFERRED
  pending operator photos/decisions** — which is why it was never built.

**Blocked on:** whether "above the barrel" means the drum itself sits on top of
the barrel, or the drum stands on the floor and only its OUTLET/slider is above
the barrel. Those are very different models and the one-line spec doesn't settle
it. A photo or a marked-up render closes it.

### A3. Head-filter mini control panel
No spec anywhere. Grep for `mini panel` / `bedieningspaneel` / kopfilter+panel
across all 417 docs returns only sorteerlijn and shredder hits, never the
kopfilter. The current geometry (`PlaceableCatalog.gd:10285-10288`) was invented
to hang the SWAP/REPACK E-interaction on — note the surrounding kopfilter housing
IS doc-cited (`:10231-10241`) and this one is not. **Blocked on operator.**

## B. Gauntlet bench — reported behaviour

- **B1. Most spawns land at the centre of the middle shredder.** Bale clamp,
  film-piece piles and others all appear at one fixed point; bales spawn
  correctly. Because the clamp lands inside the shredder, NPCs cannot board it.
- **B2. Phantom housekeeping tasks.** NPCs get auto-assigned a leaf-blower task
  with nothing to blow, and an exclamation mark shows for it.
- **B3. Wrong verb/tool: "sweep with the shovel".** A shovel SCOOPS; a broom
  SWEEPS. The task name and the tool are mismatched.
- **B4. Assigned NPCs stand still** instead of executing the task.
- **B5. Shift leader stuck on "making rounds"** — task shown, no movement.
  (Related to the boarding-walk freeze fixed in `1cf15bf`? Not proven — the
  gauntlet has no vehicles for that path. Needs its own measurement.)

## C. Feed belt → shredder (mass appearing from nothing)

- **C1.** Bales ride the opzetband THROUGH the shredder and dump on the far side
  instead of dropping into the shredder's top intake.
- **C2.** Nothing visible is riding the belt (the invisible mass rider carries it
  — see `ShredderFeedBelt._tick_film_pieces`), so the operator cannot see what is
  happening.
- **C3.** A pile of fines forms at floor level — either from nothing, or from
  UNSHREDDED bales. Both are impossible. This is a ledger bug, not a cosmetic
  one, and it is the most serious item in this list: mass is being created.

## D. Editor warnings — DONE (`de7c9d1`, `1cf15bf`)

Seven sites fixed. Note for future batches: GDScript warnings are **invisible
headlessly** on 4.6.3 (verified: `--check-only`, runtime `load()`, and
`--headless --editor --quit` all print nothing for a planted unused parameter).
They only surface in the editor, which is why they reach the operator and not
CI. `tools/regression/lint_unused_params.py` now gates the unused-parameter
class in `run.sh`; the other classes still need an editor session.
