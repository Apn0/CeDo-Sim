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
| 7 | ~~Rust-coloured flywheel/pulley at one end~~ — **WRONG, RETRACTED 2026-08-30.** It is a **MOBILE INDUSTRIAL FAN** parked on the deck. See §9e. | ~~PHOTO~~ → corrected |
| 8 | **Drive-belt guard = fine YELLOW MESH** over the belts driving the main shaft. **SETTLED 2026-08-30.** The 2026-08-30 "it is not a mesh, it is a plate" ruling was about the loose yellow plate on the deck, NOT this guard — operator: *"i believe we are talking about a separate part there"*. Two different yellow objects. The guard stays MESH. | OPERATOR + PHOTO |
| 9 | ~~Yellow chute/hopper on the platform's near side~~ — **WRONG, RETRACTED 2026-08-30.** It is a flat yellow **PLATE** standing on the deck. Operator: "a yellow shoot like thing [...] is not anywhere on the image and also doesn't make sense". See §9e. | ~~PHOTO~~ → corrected |

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
| **Stairs lying flat on the floor** | They belong **upright**. **LOCATION SETTLED 2026-08-30** — operator: *"note stairs location, starts pretty much next to the ladder"*. The flight is on the **same face as the caged ladder**, its foot immediately beside the ladder's foot, climbing onto the deck's open +X edge. The earlier "square landing at a gap in the railing" reading put it on the opposite side of the machine and is superseded; the landing and the hand-built railing gap are both gone and the -Z railing is continuous again. See §9f. | OPERATOR |
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

### 9b. NEW — visible in the file, not previously recorded

| Item | Detail | Tag |
|---|---|---|
| **`+BP2` control cabinet** — **MODELLED 2026-08-30** | A light-grey painted electrical enclosure stands on the deck between the drive drum and the cream motor, stencilled **`+BP2`**. Across the door: a row of three devices (grey button / **GREEN** lamp / grey button) plus a fourth lower down, and a bundle of black cable leaving the bottom and running off toward the motor. The face is **smooth light grey with no galvanising spangle** — a painted RAL 7035 enclosure, not raw galvanised steel; the first attempt used the galvanised material and rendered far too dark. | PHOTO |
| **Instrument panel** | A small dark vertical panel (gauge or local HMI) mounted on a post immediately left of the `+BP2` cabinet. | PHOTO |
| **Tool shadow board** — **MODELLED 2026-08-30** | A yellow board hangs on the inside of the railing carrying **two numbered tool silhouettes**. Position **1** still has its large single open-ended **spanner** on the board; position **2**'s silhouette (a combination spanner — ring one end, open jaw the other) is **empty, the tool is missing**. The missing tool is modelled deliberately: it is what the photograph shows, and a shadow board with a gap in it is what a working shadow board looks like. Very likely the "tools (probably for opening the mill)" of section 5. | PHOTO |
| **Motor sticker** — **MODELLED 2026-09-06** | A small yellow sticker on the motor's fan cowl. Building it exposed that the model had **no cowl at all**; the cowl, its chord-fitted crosshatch grille, the square hub, a lifting eye and the fin-block nameplate were all built with it. See §9h. | PHOTO |
| **Yellow GRP grating** | Yellow perforated/GRP grating panels below deck around the friction separators — distinct from the yellow *mesh belt guard* and from the galvanised steel grating of the mill's own bordes. Three different yellow surfaces, do not conflate them. | PHOTO |
| **Infeed screw livery** | The transport screw discharging into the mill's hopper is **galvanised grey**, not cream, and carries its own yellow name sticker. | PHOTO |
| **Hopper lid clamps** — **MODELLED 2026-09-06** | A row of white clamp cylinders / hinged-lid hardware along the top-right edge of the infeed hopper. Zoomed: **three** bracket + dark-pad assemblies and **two** spindle clamps with barrel nuts, one trailing a hose, on the **+X** wall. See §9h. | PHOTO |
| **Under-deck discharge** — **MODELLED 2026-09-06** | An upside-down **Y SPLITTER** (operator, §9i): trunk off the chamber, a divider ridge, two legs to outlets 1.29 m apart feeding the L/R friction separators. Finish fixed (was near-black `aged`, now `galv`); bolted access plate and yellow sticker built. The “pointed outlets” in this line are **correct** — a same-day retraction of them in §9h was itself wrong and is withdrawn. | PHOTO |

### 9b-i. What was modelled on 2026-08-30, and what is still open

`PlaceableCatalog._m_mill` gained the `+BP2` cabinet and the tool shadow board.
The cabinet **replaces** an invented `TYPICAL` 0.30 x 0.42 x 0.22 control box that
used to stand on the +Z edge with nothing behind it — a sourced object displacing
an imagined one, which is the direction this file should always move in.

Model count 207 -> **231** parts. Verified by
`src/tests/verify_mill_addons_2026_08_30.gd` (13 checks, all green, and
mutation-tested: displacing either item, or nudging the cabinet 0.15 m so it
fouls the motor skid, turns the suite red).

Measured clearances, not eyeballed — cabinet union `X[-0.256, 0.356]`,
`Y[1.930, 2.730]`, `Z[-1.227, -0.897]`: it stands exactly on the grating
(base 1.9300 = deck top), stops 0.043 m short of the motor skid at X 0.3995,
0.115 m short of the cutting chamber at Z -0.782, and 0.337 m inside the -Z
railing. Board union `X[-1.453, -1.365]`, `Y[2.056, 2.836]`, `Z[0.351, 1.151]`:
below the 2.95 top rail, above the toe board, inside the railing line, and
intersecting neither the chamber nor the yellow near-side chute.

Still NOT modelled from section 9b: the framed document/drawing holder beside the
cabinet, the yellow sticker on the motor fan cowl, the yellow GRP grating below
deck, the galvanised-grey livery and sticker of the infeed screw, the hopper lid
clamps, and the under-deck discharge hopper's pointed outlets.

**Flagged for the operator, NOT acted on:** at full resolution the big rust-brown
object on the deck reads less like a bare flywheel and more like a **curved
rust-coloured sheet-metal hood over the belt drive**, with the fine yellow mesh
closing its open end/underside. The model currently builds a flywheel disc plus a
separate flat mesh guard. Changing that is a geometry ruling, not a detail tweak,
so it is left alone pending an answer.

### 9e. Operator corrections, 2026-08-30 — two readings were WRONG

Shown the rebuilt model, the operator corrected two things that had been carried
as PHOTO facts since the first reading. Both are now fixed in
`PlaceableCatalog._m_mill`, and both are recorded here so nobody "restores" them.

**1. The rust-coloured drum is a MOBILE INDUSTRIAL FAN, not a flywheel.**

> **OPERATOR:** *"the rusty thing is a industrial fan. You can see the two wheels
> in its bottom right. And you can see the pivot point [...] in the center above
> the wheels."*

Re-zooming the filed photograph confirms it in full: a rusty barrel shroud, a
wire finger-guard over the impeller, two rubber wheels under a tubular trolley,
and a black spoked hand-knob on the side trunnion that locks the tilt. It is a
loose object parked on the platform — almost certainly the **"blower fan at the
top of the bordes/catwalk"** already listed among the props in §5, which means
that prop was in the photo all along and was simply mis-identified.

It was previously built as a 1.25 m rust flywheel disc with spokes, a hub, a
shaft stub and a bearing pedestal, keyed to the rotor axis. **None of that was
real.** The mill's actual drive — cream motor, twin pulleys, three V-belts on
the +X side — was never touched and is unaffected.

**2. The yellow object is a flat PLATE, not a chute and not a mesh.**

> **OPERATOR:** *"that yellow [...] is not a mesh. It is a plate."* and
> *"you also drew like a yellow shoot like thing? which is not anywhere on the
> image and also doesn't make sense."*

It was built as a converging `_flare4` hopper hanging 0.78 m through the deck.
It is now one flat sheet standing on the grating inside the near railing, with a
folded lip along its top edge. What the plate is FOR is unknown and is not
guessed at; a loose guard panel parked on a deck mid-construction is plausible
but unconfirmed.

*Deviation, flagged:* at the photo's apparent size the plate spanned the whole
deck front, which turned it into an opaque billboard hiding the machine and stood
it directly in front of the granulator's interactive screen-cradle door. It was
cut to 0.95 x 0.95 m and moved to the -X end so a player can still reach that
door. Faithfulness lost on purpose, for playability.

**3. The second wrench is modelled, and it is PRESENT.**

> **OPERATOR:** *"please model the second [wrench] [...] it's not on the photo,
> but you can see that it's just the same one, but [...] smaller."*

Position 2 on the shadow board previously carried paint only, because the tool is
not legible in the photograph. The operator has settled it from his own knowledge
of the machine: it is the same single open-ended spanner as position 1, smaller.
Built at 0.72 scale, and the painted silhouette was changed to match — the
ring-ended combination spanner the low-resolution outline had suggested was an
artefact of the image, not the tool.

**Still open after this pass:** the operator also said *"the stairs should come up
next to it"*, which the model does not do — the flight currently runs parallel to
the -Z deck edge and turns onto a landing at the railing gap, a bearing that was
always tagged TYPICAL because the photo shows the stair lying down. Exactly which
feature it should come up next to has been asked and is not yet answered. **Do
not re-route the stair until it is.**

Model count after this pass: **250 parts.** Verified by
`src/tests/verify_mill_addons_2026_08_30.gd` — 23 checks, all green, each
mutation-tested.

### 9f. Stair relocated to the ladder side, 2026-08-30

> **OPERATOR:** *"I think the model is a bit weird. because the stairs should come
> up next to it. Right?"* — and, when asked which feature: *"note stairs location,
> starts pretty much next to the ladder"*.

The stair bearing had been tagged TYPICAL from the start, because the photo shows
the flight lying flat on the floor and its installed direction was unknown. The
guess was wrong: it ran along the **-Z** deck edge and turned onto a square
landing at a hand-built gap in the -Z railing — the far side of the machine from
the caged ladder.

It is now on the **+X face, immediately -Z of the ladder**, climbing in -X
straight onto the deck. Because the +X edge already carries no railing (it is the
ladder's climb-out) the flight tops out flush with the deck edge and the player
walks straight on: the landing, its four legs and pads, its own railing and the
hand-built railing gap are all deleted, and the **-Z railing is a continuous run
again**. Model count 250 → 225 parts — the stair rework removed more geometry
than the fan and plate added.

Measured clearances, not eyeballed. `_caged_ladder` at (1.54, 0, 0.547) occupies
X [1.056, 2.024] (0.484 m hoop radius) and Z [0.394, 1.362] (hoops offset +0.33,
outer cage bar at +0.792). The flight is 0.90 m wide on centreline z = -0.30, so
Z [-0.75, 0.15] — **0.244 m clear of the ladder's -Z face**. Stair foot at world
(3.60, 0, -0.30) against the ladder's foot at (1.54, 0, 0.547): **2.23 m apart on
the same side**, where before they were 2.69 m apart around a corner.

*Still TYPICAL:* the 0.30 m -Z offset (picked purely for ladder clearance) and the
0.90 m flight width.

### 9g. The yellow mesh belt guard is a SEPARATE part — settled

The 2026-08-30 correction *"that yellow [...] is not a mesh. It is a plate"* raised
a real ambiguity, because the operator had earlier described the mill's drive belts
as *"covered in yellow tiny mesh"*. Asked directly which object the ruling covered:

> **OPERATOR:** *"i believe we are talking about a separate part there"*

So there are **two different yellow objects** and both readings stand: the loose
**plate** on the deck (§9e), and the fine yellow **mesh** guard over the belt
drive. The belt guard was left as mesh throughout and needs no change. §2 item 8
is restored to OPERATOR + PHOTO.

### 9h. Third reading, 2026-09-06 — four §9b items built, one §9b item RETRACTED

Four of the items §9b listed as seen-but-not-modelled are now in
`PlaceableCatalog._m_mill`. All four are PHOTO-tagged and were re-zoomed on the
filed file before anything was written; nothing here is TYPICAL.

**1. Hopper-lid CLAMP BANK (built).** §9b called it "a row of white clamp
cylinders / hinged-lid hardware". Zoomed it resolves fully: **three** cream
clamp brackets, each a gusset rib + a top plate + a **dark contact pad** at the
outer tip, with **two** spindles between them — a galvanised stem through a cast
barrel nut, hex head on top — and a hose trailing off the -Z spindle. On a Neue
Herbold granulator this is the hardware that locks the hinged hopper section
down for knife changes.

*Which wall:* the **+X** one. The brand is stencilled on +Z, and in the
photograph the clamp wall is the face clockwise from the brand wall, toward the
ladder — which the model puts at +X. The bank is built under a pivot that reuses
`_flare4`'s own +X panel transform, so it stays welded to the wall if the hopper
is ever re-proportioned.

**2. Motor FAN COWL, grille and yellow sticker (built).** §9b recorded only "a
small yellow sticker on the motor's fan cowl" — but the model had **no cowl at
all**, just the body and its fin rings, so the sticker had nothing to sit on.
Zoomed, the photograph gives the whole non-drive end: a smooth cream cowl, a
fine crosshatch grille with a **square hub**, the sticker high on the cowl's
shoulder, a lifting eye on the body and a dark nameplate on the fin block. All
of it is built. The grille bars are chord-fitted to the disc so they stop at the
rim instead of overhanging as a square patch.

**3. `NEUE HERBOLD.com` (built).** §9a noted the model stencilled only
`NEUE HERBOLD` and that the suffix would be more faithful. The suffix is a much
smaller lockup low and right of the wordmark, so it is a **second label** — one
`Label3D` can carry only one glyph size. **Still not modelled:** the stylised
blue globe standing in for the O. A `Label3D` cannot express it and faking it
with an emissive disc would be a guess at the artwork. Ask before adding one.

**4. Under-deck discharge — finish FIXED. ⚠ The "pointed outlets" retraction below is ITSELF WITHDRAWN — see §9i.** Kept here only so the mistake is legible.

> §9b said: *"a large cream/grey hopper box with a steeply angled bottom, ending
> in **pointed outlets**."*

The finish half of that is right and is now fixed: the chute was built with
`aged` (`mat_steel_dark_aged`, 0.22/0.22/0.24), which renders near-black; the
photograph shows a **mid-grey** box, the same family as the galvanised frame it
hangs in, so it is `galv` now. The bolted **access plate** (ten bolt heads) and
the **yellow name sticker** on its +Z face are built, both unmistakable in the
file.

**The "pointed outlets" are RETRACTED — they are not outlets.** Re-zoomed, the
pointed shapes in that part of the frame are the **gusset tops of two
floor-standing support posts**: each post has a base plate bolted to the floor,
a square-section column, a round pivot boss, and a triangular gusset plate above
it, with a cross-beam and a turnbuckle running between the two posts under the
chute. They point **upward**, which an outlet would not. Nothing was invented to
match the old reading. This is the third §9b/§2 reading to be overturned by
zooming the file — after the flywheel→fan and the chute→plate corrections of
§9e — so treat every remaining un-modelled §9b line as provisional until it has
been re-zoomed.

*Open, and the one question worth his time:* what that two-post frame under the
mill actually is — a support stand for the discharge, or the mounting for
something else that had not been installed when the photo was taken. It is not
modelled until he says.

**Still NOT modelled from §9b**, unchanged by this pass: the instrument panel on
its post; the yellow GRP grating below deck (unowned — the mill's own bordes is
galvanised and must not be recoloured); the infeed screw's galvanised livery and
sticker (they live in the shared `_m_transport_screw`, so a mill-only variant is
a design call, not a photo reading); the blue globe in the wordmark; and the two
questions of §8 — the sticker's tag number and the "…antec" maker's plate.

**A collision the first green run did not catch.** The cowl pushes the motor's
non-drive end 166 mm further -X, and that put the grille plane 10 mm *inside* the
`+BP2` cabinet — the cabinet's +X face was at x 0.350, the grille at x 0.333. All
of the new geometry checks still passed, because none of them looked at the
neighbouring part; it showed up in the render, where the camera saw the cabinet
where the grille should have been. The cabinet moved 130 mm -X and the cowl 20 mm
toward the motor body, restoring the gap the photograph shows. There is now an
explicit AABB check for it, and the cabinet's box is *found in the model* rather
than written into the test — the first version hardcoded it and stayed green when
the cabinet was moved back into the cowl.

Model count **250 → 275 parts.** Verified by
`src/tests/verify_mill_photo_details_2026_09_06.gd` — 29 checks, all green, each
one mutation-tested (24 mutations, every assertion proven to fire).
`verify_mill_addons_2026_08_30.gd` still passes 29/29 after the cabinet move.
Renders: `docs/plant/renders/shot_mill_3c_{clamps,cowl,underdeck}_2026_09_06.png`.

### 9i. The under-deck chute is a Y SPLITTER — operator, 2026-09-06

> **OPERATOR:** *"the frame under the mill is the chute that is an upside down Y
> splitter, dividing material from the mill left and right again to the friction
> separators > transportation screws towards the flotation tank inlet paddle"*

**This overturns §9h's retraction, not §9b.** §9b's original *"ending in pointed
outlets"* was RIGHT. The 2026-09-06 re-reading that called the pointed shapes
"gusset tops of two floor-standing support posts" and retracted the outlets was
the error — the second wrong reading of this same object, and this time the
wrong reading was mine correcting a right one. §9b item **Under-deck discharge**
is restored to plain **PHOTO**.

*Lesson, and it is the opposite of §9e's.* §9e taught that a confident reading of
a photograph can be wrong and the operator's correction wins. §9h then applied
that lesson too eagerly: re-zooming produced a new confident reading and
retracted a claim that was actually correct. **A retraction needs the same
standard of evidence as the claim it retracts.** At this resolution the
structure is genuinely ambiguous — a chute with two outlets, hanging in a frame
of two posts, photographed at a steep angle. Do not re-derive either reading
from the photograph alone.

**What is now modelled.** The trunk still converges off the chamber underside and
through the deck. Below the deck it now carries a **divider ridge** — two plates
meeting in an apex on the centreline, pointing up into the falling stream, which
is the pointed element in the photograph — and **two legs** leaning out at 42.8°
from vertical to outlets 1.29 m apart, against a 0.44 m throat. This replaces a
single straight duct on the centreline that split nothing.

**The split axis is +/-X, and that is measured, not chosen.**
`BuildMode.LINE_3C_SEQ` places `L3C.9L` at **x -3.0** and `L3C.9R` at **x +3.0**
relative to the mill, and `Line3CDef.LINKS` already carries
`["L3C.6","L3C.9L"]` and `["L3C.6","L3C.9R"]`, then `L3C.9L/R -> L3C.10L/R ->
L3C.11 Flotatietank`.

**The sim topology already matched the operator's description exactly** — mill
-> two friction separators -> two transport screws -> flotation tank. Only the
geometry was missing. No flow defect to fix.

*Still not modelled from this answer:* the **flotation tank inlet paddle** named
at the end of the operator's chain. It is a separate machine
(`flotation_tank_wide`, `L3C.11`) and was not inspected in this pass.

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
