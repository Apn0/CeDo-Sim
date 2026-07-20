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

## E. Operator photos 2026-07-20 — compactor conveyor before the PCU

Two photos supplied in chat: a side view of the compactor conveyor carrying the
finished shred, and a close-up of the same material. **They are not yet in the
repo** — drop them into `docs/plant/photos/` so this entry can cite files rather
than a chat message.

What they establish:

- **Flakes are NOT flat squares.** They are torn, curled, folded shreds at every
  attitude, with lengths from specks to long ribbons. `FilmFlakeField` used
  `BoxMesh(flake_size, flake_size * 0.15, flake_size)` — a flat square, yaw-only,
  identical for every instance. Rebuilt (2026-07-20) as a folded 3-ribbon tuft
  with per-flake tilt/roll/length/size. Before/after: `src/tests/shot_flakes.tscn`.
- **Colour distribution.** The mass is overwhelmingly translucent white-grey with
  a scatter of bright specks (blue, red/orange, green, black print) — roughly one
  in five. The old code cycled the full PALETTE evenly, which read as confetti.
  `_flake_color()` now does 80% varied grey / 20% speck.
- **Density.** In the photo the shred is a PACKED CARPET with heavy overlap. The
  field is still a scatter; density comes from each machine's `flake_count`/`area`
  and the live LineFlow state, so it needs tuning per machine — NOT done yet.
- **Still to mine from these photos:**
  - brick wall + staircase in the background — relevant to the deferred tex-02
    (building shell walls, previously rendered black and needing operator eyes);
  - the belt itself: tan/khaki rubber with raised cleats and dirty side rails;
  - the black rubber flap at the left of photo 1 is the **chute from the extruder
    silo** (operator). Check what the model currently puts there.
  - the close-up is a good candidate for a tiling albedo texture for bulk shred.

## F. Operator photo set now IN the repo — `docs/plant/photos/extruder_2026-07-20/`

Operator instruction: **"also save images to the project folder always~!!!"** The
photos had been sitting on his Desktop with self-describing filenames the whole
time; nothing was missing, I just never looked there. Eight copied in.

**The filename prefix on the annotated shot IS a colour legend** — he had already
drawn the polygons I asked for:

`gr-HMI_or-laserfilter_bl-vacuumpots_ye-vacuumcatchresiduebin_pu-headfiltercontrol_pi-headfiltercabinetclosed.jpg`

| Colour | Part | What the photo shows |
|---|---|---|
| green  | HMI | separate floor-standing panel, well off to the side |
| orange | laser filter | its own floor unit, NOT on the barrel |
| blue   | vacuum pots | floor-standing pots beside the line |
| yellow | vacuum catch residue bin | small bin under the vacuum pots |
| purple | head-filter control | narrow vertical panel at floor level, beside the cabinet |
| pink   | head-filter cabinet (closed) | LARGE stainless floor-standing cabinet next to the barrel end |

### This contradicts the current model more deeply than the PCU did
- **Vacuum degassing is modelled as two small domes ON the barrel crown**
  (`PlaceableCatalog.gd` SECTION 5b). The photo shows **floor-standing vacuum
  pots with their own residue bin**, off the barrel entirely.
- **The head filter is modelled as a slim housing on the barrel.** The photo
  shows a **large floor-standing stainless cabinet** roughly the height of a
  person, with its **control panel as a separate vertical unit beside it** — so
  the "invented" mini panel is not just unplaced, it is the wrong object at the
  wrong scale.
- **The pelletizer** (`pelletizer_closed_hatch.jpg`) is a **cylindrical housing
  with a clamped round hatch** on an EREMA-blue body — not the rectangular
  louvered cabinet currently modelled. That hatch is the "lid/latch" the operator
  asked to have outlined.
- `head_filter_cabinet_open_top-cylinder_out_breaker-plate-in.jpg`,
  `cylinder_out_no-breaker-plate*.jpg` and `breaker-plate_with-tool-attached.jpg`
  document the **breaker plate + screen cylinder** and the extraction tool —
  parts that do not exist in the model at all.

**None of this is built yet.** It is a bigger rebuild than the PCU and should be
its own pass, machine by machine, with a render approval per step.

## G. Renders now land in the project

`shot_placeable.gd`, `shot_annotate_extruder.gd` and `shot_flakes.gd` write to
`docs/plant/renders/` instead of `user://`. A render in
`%APPDATA%\Godot\app_userdata\` is invisible to the operator and uncitable from
these docs.
