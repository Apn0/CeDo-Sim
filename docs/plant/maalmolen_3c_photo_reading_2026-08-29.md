# Maalmolen 3C (NEUE HERBOLD granulator) — operator photo reading, 2026-08-29

Source photograph: `docs/plant/photos/maalmolen_3c_construction_2026-08-29.jpg`
(operator's own camera; camera filename `IMG-20250912-WA0008.jpg`, camera date
**2025-09-12**). Supplied in session **2026-08-29**, filed **2026-08-30**. Shows the
REAL machine — **line 3C's mill** (`L3C.6 Maalmolen`, catalog id `mill`).

> **PHOTO IS NOW IN THE REPO (filed 2026-08-30).** The operator supplied the
> original camera file (`IMG-20250912-WA0008.jpg`, 1536 x 2040, 412 KB). Filed as:
>
> - `docs/plant/photos/maalmolen_3c_construction_2026-08-29.jpg` — **tracked in git**
> - `assets/reference_photos/machines/maalmolen_3c_construction_2026-08-29.jpg` —
>   the conventional library home, but `assets/` is gitignored (`.gitignore:2`),
>   so that copy is local-only. The `docs/` copy is the durable one.
>
> The filename keeps the 2026-08-29 session date (when the reading was made), not
> the camera's own 2025-09-12 stamp — the camera date is recorded here instead.

**CRITICAL CONTEXT — the photo was taken DURING CONSTRUCTION.** Several things
visible in it are NOT how the machine looks in normal operation. They are called
out explicitly below; do not model them as permanent.

Provenance vocabulary follows the detail standard's Q1
(`docs/DETAIL_STANDARD_audit_2026-08-18.md`): **OPERATOR** = stated by the
operator; **PHOTO** = visible in the photograph; **DOC** = a plant document;
**TYPICAL** = invented/assumed, flagged as such.

---

## 1. Provenance correction — the docstring was RIGHT

`PlaceableCatalog.gd:4601-4605` says the mill was *"modelled from the operator
photo"* and names it **NEUE HERBOLD**, cream/white.

A 2026-08-29 investigation could not find any machine photo in the repo and
found only the HMI screen mimic (`assets/reference_photos/hmi/IMG-20240811-WA0007.jpg`,
screen `L3C.6 Maalmolen`), whose vendor illustration is **cyan/blue**. That
prompted a proposal to repaint the model cyan to match its only findable source.

**That proposal was WRONG and must not be actioned.** The operator then supplied
the real photograph:

- **OPERATOR + PHOTO — the machine really is cream/white** with **"NEUE HERBOLD"**
  in blue lettering on the angled infeed hopper. The name is legible in the photo.
- The HMI mimic is the vendor's schematic in HMI house colours, **not** the
  machine's real livery.

**Lesson for the ledger:** absence of an in-repo photo is not evidence the
docstring was fabricated. The operator holds photographs that were never filed.
Ask before "correcting" a sourced-looking claim. (Contrast the NIR sorter at
`PlaceableCatalog.gd:8604`, where the claim *was* genuinely wrong —
`photo_audit.md:50-51`.)

---

## 2. The mill itself — confirmed features

| # | Feature | Tag |
|---|---|---|
| 1 | **NEUE HERBOLD** granulator; brand in blue lettering on the hopper | OPERATOR + PHOTO |
| 2 | Body + infeed hopper are **cream/white** | OPERATOR + PHOTO |
| 3 | Large **angled infeed hopper/chute** on top, feeding down into the cutting chamber | PHOTO |
| 4 | Sits on an **elevated grating platform** — galvanised/grey deck | PHOTO |
| 5 | **YELLOW railings** around the platform (current model already yellow — correct) | PHOTO |
| 6 | **Caged vertical ladder** down from the platform | PHOTO |
| 7 | Rust-coloured **flywheel/pulley** at one end | PHOTO |
| 8 | **Drive-belt guard = fine YELLOW MESH** over the belts driving the main shaft (safety guard) | OPERATOR + PHOTO |
| 9 | Yellow **chute/hopper** on the platform's near side | PHOTO |

### 2a. ⚠ MOTOR COLOUR — a documented EXCEPTION to global rule 8b

`CLAUDE.md` rule 8b states all factory motors are CeDo dark blue `#191E6C` and
*"never paint a motor another colour"* (global in `PlaceableCatalog._motor_unit`).

**The mill's own shaft motor is an EXCEPTION:**

> **OPERATOR (2026-08-29):** *"The motor of the shaft of the mill is in the same
> colour as the rest of the mill (exception to the blue motors)."*

So: mill shaft motor = **cream/white, same as the mill body**. The blue motors in
the photo are a *different* machine's drives — see §3.

This is the first recorded exception to rule 8b and should be carried into
`CLAUDE.md` when the model is updated, or a future pass will "fix" it back to blue.

---

## 3. Surrounding machines visible in the same photo

| Feature | Detail | Tag |
|---|---|---|
| **Two long transport screws feeding the mill** | Enter from the upper-left; their discharge ends feed the mill's hopper | OPERATOR + PHOTO |
| **Two friction separators** | Directly **BELOW** the mill, under the platform | OPERATOR + PHOTO |
| **Blue motors** | Below deck — these drive the **friction separators**, not the mill. Standard CeDo blue, rule 8b applies to these | OPERATOR + PHOTO |
| **Two transport screws out** | Bottom-right of frame: run **from the friction separators → the flotation tank** ("if I'm correct" — operator hedged) | OPERATOR |
| Screw continuity | The screw bottom visible bottom-right is the *start*; the screw tops visible upper-left are the ones feeding the mill | OPERATOR |

**Yellow equipment stickers:** machines carry yellow labels with the Dutch machine
name — e.g. **`MAALMOLEN`** — plus the line/tag. Also present on the friction
washer and the transport screws. The exact tag number was not readable; the
operator recalled "8-point-something" from memory but was unsure.
`Line3CDef.gd:66` records this unit as **`L3C.6`** — resolve before stencilling
a number. *(OPERATOR, uncertain — do NOT stencil a guessed number.)*

---

## 4. CONSTRUCTION-ONLY — do NOT model as permanent

| Item | Reality in normal operation | Tag |
|---|---|---|
| **Stairs lying flat on the floor** | They belong **upright**: they rise to a small **square landing platform** which connects to the **gap in the railing** at upper-left of the platform. Model them installed, not lying down. | OPERATOR |
| **Red/white barrier tape** at the ladder base | Present only because the railing gap was an open fall hazard during construction. **Removed in normal operation.** | OPERATOR |
| **Blue forklift** | Belongs to the **contractor** that built the line, NOT to CeDo. **DO NOT MODEL IT.** | OPERATOR (explicit) |

---

## 5. Building / environment details — operator says model these

Stated as wanted, but lower priority than the machines themselves.

| Item | Detail | Tag |
|---|---|---|
| **Rusty brown pipes** | Horizontal runs left→right AND front→back behind the mill. Carry: process water supply + return, **extruder cooling water** supply + return, and water for the mill. Both process water and extruder cooling water. Operator: *"we will do that later… so you can model the rusty pipes. Later."* | OPERATOR |
| **Roof trusses** | Supporting the roof; operator believes not yet modelled | OPERATOR |
| **Spider webs** | Hanging near the light fittings | OPERATOR |
| **Dirty windows** | The building's side walls have windows; they are grimy | OPERATOR |
| **Props** | A black bucket on the floor; tools (probably for opening the mill); a **blower fan** at the top of the bordes/catwalk | OPERATOR |

The water piping is explicitly deferred — it belongs with the wider water-circuit
work the operator has parked (blauwe tank / blauwe vat / koeltoren, see
`DOCS_VS_SIM_GAP_AUDIT_2026-08-28.md` W.1-W.3). Machines first, water later.

---

## 6. Measured state of the current model (2026-08-29, before any fix)

Census via `src/tests/mesh_census_2026_08_29.gd` (bypasses `StaticMerge` so loop
bodies count as real parts). Two agents measured independently and agreed.

| Metric | `mill` | `vw_trommel` (exemplar) | population |
|---|---|---|---|
| Authored mesh parts | **70** (rank 29/193) | 124 (rank 12/193) | median 14 |
| Non-comment code lines | **50** (rank 23/114) | 125 (rank 6/114) | median 24 |
| `MaterialPalette` calls | **2** | 13 | 87 of 114 use ZERO |
| Feature classes | **9/11 — rank 1/114** | 8/11 | median 2 |

**Shape of the gap:** the mill is **broad but thin** — it touches more feature
classes than any other builder in the file, but executes each shallowly. The drum
is **narrow but deep**. Closing the gap on the mill is mostly a *materials and
finish* job (2 → ~12 palette calls, weathering, stencils, indicators), not a
"add more subassemblies" job.

### 6a. Geometry defects measured from the source constants

Computed from `size 3.6 × 4.8 × 4.6` → `deck_y 1.92`, `hw 1.44`, `hd 1.564`,
`base_y 1.98`, `ch_h 1.248`. Not eyeballed.

1. **Access stair tunnels into the platform.** Base `z = -2.564`, rise 1.92 → 8
   steps, tread 0.27, run 2.16. Top tread lands at `z = -0.539`, i.e. **1.03 m
   inside** the deck footprint (edge `-1.564`). Treads 4-6 sit *under* the deck
   slab; tread 7 is co-planar with it → buried steps + z-fighting.
   **Also wrong per §4:** the real stair rises to a square landing at the railing gap.
2. **Flywheel cantilevered off the deck.** `_cyl` at `x = -1.699` spans
   `-1.799…-1.599`; deck edge is `-1.44`. Entirely beyond the platform,
   unsupported, crossing the -X railing plane.
3. **Drive motor floats.** Centre `x = 1.757` (edge 1.44), length 1.008 → spans
   ≈ `1.25…2.26`; most of it hangs off the deck.
4. **Discharge hopper floats.** Top at `y = 1.488`; deck underside `1.89` → a
   **0.40 m air gap** between the chute and the machine it drains.
5. **Two bare blue cubes** (0.5 × 0.6 × 0.5) on the ground — untextured
   primitives, no base plate/bolts/conduit. Per §3 the real blue motors drive the
   **friction separators**; these cubes are a stand-in that should become real
   motor units on real machines.
6. **Hopper is a box rotated 20°**, not a converging flare — reads as a tilted
   crate rather than the wide-mouth funnel actually fitted.

---

## 7. Catalog / macro naming inconsistency (three-way)

- `PlaceableCatalog.gd:321` display name: **"Mill (fine; 3C, 6)"**
- Actually placed by **`LINE_3C_SEQ`** (`BuildMode.gd:345`, `# 6 L3C.6 (merge)`)
  and **`LINE_1_SEQ`** (`BuildMode.gd:659`)
- **There is no `LINE_6_SEQ` in the file at all** (grep count 0), and
  `LINE_3C6_SEQ` does not place the mill
- `photo_audit.md:83` lists it as "Maalmolen 1 / Line 1" only — missing 3C

So the display name advertises a line that has no macro and omits a line that
does place it. `photo_audit.md:83` also records Photo `—` (none) and Status `☐`
(never operator-reviewed) — **both now superseded by this document.**

The operator confirmed the mills on **3C and 6 are the same machine**, so the
"3C, 6" name reflects the real plant even though no line-6 macro exists yet.

---

## 8. Open questions for the operator

1. **The yellow equipment sticker's tag number — STILL OPEN.** Now that the photo
   is on disk it was re-read at full resolution and zoomed: the stickers are a
   three-line layout (small top line / bold machine name / smaller tag line) but
   the text is **below the resolution of the image** — illegible even zoomed.
   `Line3CDef.gd:66` says `L3C.6`; the operator recalled "8-point-something" and
   was unsure. **Do not stencil a number until this is settled.** The model
   currently stencils the word `MAALMOLEN` only, which is correct.
2. **The friction separators' brand.** A blue-on-white maker's plate with a swoosh
   logo is fixed to the machine at bottom-right of frame. The legible fragment is
   **"...antec"** — the first letters are hidden behind the caged ladder's upright.
   Recorded as a fragment, deliberately NOT guessed into a full brand name.

---

## 9. Second reading, 2026-08-30 — from the filed full-resolution file

Everything in sections 2-5 above was written from the operator's narration while
the photo was only in the chat. With the file on disk it was re-read directly and
zoomed. **Nothing in sections 2-5 is contradicted.** The following are additions.

### 9a. Confirmed visually (previously OPERATOR-only, now OPERATOR + PHOTO)

| Item | What the file shows | Tag |
|---|---|---|
| **Cream shaft motor** | Large white/cream finned motor with a fan cowl, on a cream I-beam skid, standing on the deck to the right of the drive drum. Unambiguous — this is the rule-8b exception, now photographically confirmed, not just stated. | OPERATOR + PHOTO |
| **Brand text** | Reads **`NEUE HERBOLD`** with a stylised blue globe for the O, followed by **`.com`** — the full mark is `NEUE HERBOLD.com`. The model stencils `NEUE HERBOLD`; adding `.com` would be more faithful. | PHOTO |
| **Fine yellow mesh guard** | Confirmed as an open mesh/crosshatch panel around the belt run behind the rust-brown drive drum — not a solid plate. The rebuilt model already uses a mesh grid. | OPERATOR + PHOTO |
| **Blue motors below deck** | Three blue motors with fan cowls, below and right of the bordes, on the friction separators. Standard CeDo blue; rule 8b applies normally to these. | OPERATOR + PHOTO |
| **Railing gap / ladder** | The caged galvanised ladder lands exactly at the gap in the yellow railing on the right-hand side, with the red/white construction tape wrapped around its base. | OPERATOR + PHOTO |

### 9b. NEW — visible in the file, not previously recorded, not yet modelled

| Item | Detail | Tag |
|---|---|---|
| **`+BP2` control cabinet** | A grey/galvanised electrical cabinet stands on the deck between the drive drum and the motor, stencilled **`+BP2`**, with green and red pushbutton/indicator lamps on its face. | PHOTO |
| **Instrument panel** | A small dark vertical panel (gauge or local HMI) mounted on a post immediately left of the `+BP2` cabinet. | PHOTO |
| **Tool board** | A yellow board on the deck's far-left railing carrying a large open-ended **spanner** — a shadow-board for the mill's own tools. This is very likely the "tools (probably for opening the mill)" the operator mentioned in section 5. | PHOTO |
| **Motor sticker** | A small yellow sticker on the motor's fan cowl. | PHOTO |
| **Yellow GRP grating** | Yellow perforated/GRP grating panels below deck around the friction separators — distinct from the yellow *mesh belt guard* and from the galvanised steel grating of the mill's own bordes. Three different yellow surfaces, do not conflate them. | PHOTO |
| **Infeed screw livery** | The transport screw discharging into the mill's hopper is **galvanised grey**, not cream, and carries its own yellow name sticker. | PHOTO |
| **Hopper lid clamps** | A row of white clamp cylinders / hinged-lid hardware along the top-right edge of the infeed hopper. | PHOTO |
| **Under-deck discharge** | The mill's discharge below deck is a large cream/grey hopper box with a steeply angled bottom, ending in pointed outlets. | PHOTO |

### 9c. Construction-only in the file — re-confirmed, do NOT model

Stairs lying flat on the floor at bottom-left, with a green and a purple lifting
sling and an orange-capped bottle on them; wooden pallets and loose square steel
ducts under the deck; the red/white barrier tape; and the **blue forklift** at
bottom-left, which is the contractor's and was explicitly excluded by the operator.

### 9d. Provenance status

The section 1 lesson stands and is now closed: the docstring's *"modelled from the
operator photo"* claim was **correct**, and the photograph it referred to is this
file, which simply had never been filed into the repo. `photo_audit.md`'s Maalmolen
row is updated from "no photo / never reviewed" to reference this file.
