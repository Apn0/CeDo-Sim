# Docs × sim gap walk — running ledger (started 2026-08-28)

Operator-directed sweep: **walk the plant documentation in order; every time the
written record of the real factory and the simulator disagree, STOP reading, fix
the gap, then resume.** One halt per gap. This file is the resume point.

This is not the same sweep as [`photo_audit.md`](photo_audit.md) (model-vs-photo,
per machine) or [`extruder_docs_into_code_status.md`](extruder_docs_into_code_status.md)
(one closed batch). This one walks the **flow topology and process facts** and
asks a single question of each documented block: *is it in the sim, and does it
do what the docs say it does?*

## Standing rules for this walk

1. **The docs draw blocks, never chutes — but the real floor has a chute between
   most machines.** Operator, 2026-08-28: *"chutes are indeed not mentioned
   (mostly) in the docs, but there is a chute between most machines, best ask me
   to make sure."* So an A→B edge in a flow diagram is NOT evidence that A
   discharges straight into B. **Ask the operator per machine pair.** Never
   invent a chute, and never assume its absence either.
2. **A block that exists in the catalog is not a block that exists in the plant.**
   Check that the macro actually PLACES it. Two of the three line-1 gaps below
   were machines that were fully modelled, fully wired for behaviour, and placed
   by no macro at all — dead content that reads as "done" from every angle
   except the one that matters.
3. **A placeable standing in the right slot is not the right machine.** Check
   `MachineFlow.gd` for a role. A stand-in with no role removes no contaminant,
   screens nothing, and silently makes the process a pass-through.
4. **Check `user://macros/` before shifting any `macro_index`.** The SEQ arrays
   are documented APPEND-ONLY (`BuildMode.gd:100-101`) because saved deltas
   address machines by index. As of 2026-08-28 that directory is empty and no
   `line_*.json` ships in the repo, so insertion is currently safe — but
   re-check, don't assume.

## Progress

| # | Document | Status |
|---|---|---|
| 1 | `lijn_1_flow.md` + `line_flow_graphs.json` (line "1") | ✅ COMPLETE — gaps 1.1–1.3, fix 1.4, ruling 1.B, fold 1.A; leg F confirmed by operator 2026-08-28. Open: archive the sketch image |
| 2 | `lijn_3a_flow.md` | ✅ 2.1-B re-wired per operator, 2.2 fixed, Q2.3/Q2.4 closed; open: heater cabinets build, bigbag render sign-off |
| 3 | `lijn_3b_flow.md` | ⚙ gap 3.1 fixed; open: doc's operator questions (rafter type, fan V-numbers, zeefbocht) |
| … | remaining 426 docs | ☐ |

---

## Doc 1 — `lijn_1_flow.md` (43 nodes, 53 edges)

Machine-readable twin: `src/data/plant/line_flow_graphs.json` → `lines["1"]`.

> **Side finding, not yet acted on:** `line_flow_graphs.json` is a 36 KB
> authoritative topology file with **zero references anywhere in the repo** —
> no script, test, or tool reads it. `docs/plant/README.md` explicitly calls for
> "a sim-side test [to] assert the in-game line topology matches these graphs".
> That test does not exist. Building it would turn this entire manual walk into
> a mechanical check for lines 1/3A/3B. Strong candidate for the next halt.

### GAP 1.1 — HPS (SGA) heavy-parts separator absent from line 1 · ✅ FIXED

**Doc:** nodes `band_2_hps` → `hps_sga` → `frictiescheider_6a` + `_6b`
(edges 5, 6, 7). `photo_audit.md:49` already assigns it the placeable `sga_drum`
and marks the model ✓.

**Sim, before:** `prewash_drum` → `scheidingsgoot` → 2× `friction_sep`. The belt
and the drum were both missing.

**Why it mattered — measured, not assumed:**
- `sga_drum` was in the catalog, had a builder (`_m_sga_drum`), and had full
  behaviour in `MachineFlow.gd` (`process "screen"`, `contam_remove 0.20`,
  `waste 0.02`, `rate 8.0`) — and was **placed by no macro at all**.
- `scheidingsgoot`, standing in its slot, has **no `MachineFlow` entry**. So
  line 1 performed **no heavy-parts separation whatsoever**.

**Operator spec, 2026-08-28** (asked because of standing rule 1 — the chutes are
not in any document):

> "there is actually a chute after the belt that feeds material into the drum on
> the top side (and it makes a 90 deg right turn from the conveyor to the drum),
> and then at the end of the drum there is a Y-shaped shute also, which splits
> the material+water stream left and right (about 1m long 30 deg down angle, the
> the split, then a steeper 60 deg down angle, where left is about 35 deg to the
> left and the right side about 35 deg to the right, both for about 1m, then both
> sides turn straight (in line with the drum orientation) while still feeding
> material+water into the next machine)"

**Fix:**
- `BuildMode.gd` `LINE_1_SEQ` — inserted `transport_belt` (band 2), the new
  `sga_feed_chute`, and `sga_drum` ahead of `scheidingsgoot`.
- `PlaceableCatalog.gd` — new placeable `sga_feed_chute`: 90°-right corner chute,
  infeed leg → corner pan + deflector plate → outfeed leg over the drum's top.
- `PlaceableCatalog.gd` — `_m_scheidingsgoot` **rebuilt** from a straight
  U-trough into the operator's Y-splitgoot: 1 m @ 30°, splitter nose, 2× 1 m @
  60° yawed ±35°, then both legs straighten in line with the drum axis. Height
  1.4 → 2.0 m to fit the real 1.37 m of drop; X/Z footprint unchanged. The id
  is deliberately unchanged — `LineFlow.gd:3104` keys the left/right connector
  split off `scheidingsgoot`.
- New shared helper `_goot_segment()` chains pitched/yawed open-U segments and
  returns its own end point, so no segment coordinate is hand-baked (see
  [[cedo-stale-constant-disease]]).

The Y-splitgoot geometry is worth calling out: the machine whose entire job is
splitting the stream left/right previously had **no splitting geometry**. The
split existed only as a LineFlow connector rule spawning two chutes out of a
straight gutter.

### ⚖ RULING 1.B — ONE drum: the voorwastrommel IS the HPS (SGA) · ✅ APPLIED

Operator ruling 2026-08-28, from the line-1 layout sketch ("Same machine — one
drum does both"): the voorwastrommel and the HPS (SGA) zware-delen scheider are
the SAME physical drum. The sketch shows shredder → conveyor → chute → ONE drum
→ Y-split → the two parallel machines. This also explains why the flow diagram
never draws a voorwas-trommel block of its own — its "HPS (SGA)" block IS this
drum, and "Band 2 (naar voorwas trommel)" names it only in passing.

**This partially reverses gap-fix 1.1**, which had read the diagram literally
and inserted a separate band 2 + corner chute + `sga_drum` stage. Applied:

- `LINE_1_SEQ`: the three inserted entries removed again; chain is now
  `westa_band_1 → vw_trommel → scheidingsgoot → 2× friction_sep`.
- `MachineFlow.gd`: `vw_trommel` gets its OWN arm merging both stages'
  existing constants — `contam_remove 0.52` (= 1 − (1−0.40)·(1−0.20), the
  wash and the screen composed), `waste 0.05` (0.03 wash + 0.02 heavies),
  `rate 8.0`, `water_add 0.30` kept. Composition arithmetic on constants the
  sim already carried — no new invented physics. `prewash_drum` keeps its old
  arm untouched.
- Catalog name now carries both: "VW trommel / HPS (SGA) — voorwas + zware
  delen (50,000L)".
- `sga_feed_chute` (the 90°-turn corner chute — real, operator-described, in
  the sketch at the drum's head) is REMOVED from the straight macro: a 90°
  turn on a straight axis would be geometrically false. It returns WITH the
  fold. The placeable stays in the catalog.
- `sga_drum` returns to being unplaced — this time DELIBERATELY, with this
  ruling as the reason (it is a modelled spare, not a forgotten machine).
- `test_line1_flow_conformance` rewritten to assert the ruling (one drum, no
  second drum anywhere in SEQ/world/topology, merged coefficients live).
  53 ok / 0 fail.

Span effect: line 1 drops to **146.8 m** — now under the 155 m shell axis,
still over the 140 m one. The fold (consequence 1.A) remains open but smaller.

### GAP 1.2 — `intrekschroef_11a` / `_11b` in the wrong stage · ✅ FIXED

**Doc:** `maalmolen_1` → `ventilator_10a/b` → `intrekschroef_11a/b` →
`flotatie_tank` (edges 14-19), and **no** screw between the frictiescheiders
and the mill — `ventilator_8a/b` feed the mill directly.

**Sim, before:** the `transport_screw` pair sat **pre**-mill, and the post-mill
cyclones dumped straight into the flotation tank.

**Operator, 2026-08-28:** *"after the mill, like the doc says"*.

**Fix:** the pair is **moved, not added** — deleted from the pre-mill stage and
re-placed between the post-mill cyclones and the flotation tank. Length-neutral
by construction, so the flotation tank and the whole extruder back-end stay
exactly where they were; only the mill and the post-mill blower/cyclone pairs
shift 5 m upstream into the space the misplaced screws had occupied.

### ⚠ CONSEQUENCE 1.A — line 1 is now longer than the building · ☐ OPEN

Measured with a throwaway probe, building `line_1` at the origin before and
after the two fixes above:

| | machines | Z span |
|---|---|---|
| `origin/main` (before) | 48 | **147.9 m** |
| with gaps 1.1 + 1.2 fixed | 51 | **160.2 m** |
| after gap 1.3 + fix 1.4 | 52 | **161.4 m** |
| after westa re-aim | 52 | **159.1 m** |
| after ruling 1.B (one drum) | 49 | **146.8 m** |

The building shell's aabb is **140 × 155 m** (`regression_world_save.gd`,
"shell footprint non-trivial"). Gap 1.2 was length-neutral; the whole +12.3 m
is gap 1.1's three doc-required machines (`transport_belt` 4.0 + `sga_feed_chute`
1.8 + `sga_drum` 5.0, plus 3 × `LINE_GAP_M` 0.5).

So line 1 was **already** over the 140 m axis at 147.9 m and cleared the 155 m
axis by only ~7 m; adding the machines the plant's own flow diagram requires
takes it past both. For comparison `line_3a` is 117.2 m and passes the
footprint check comfortably.

**This is not merely a side effect of the fix — it is evidence the sim's line-1
layout was already dimensionally unfaithful.** The real hall holds this line
with the SGA drum in it, so either the sim's inter-machine spacing is too
generous, or line 1 does not run as one straight axis in reality.
`floor_plan_edits.md:41` hints at the latter: lines run *"doorlopend van Hal 4
(shredders) naar Hal 5"* — through more than one hall.

**Do not "fix" this by shrinking `main_advance`/`LINE_GAP_M` until the operator
says how line 1 is really laid out** — that would be inventing floor plan, which
this project forbids. Open question for the operator:

> Does line 1 run as one straight run down the hall, or does it fold / change
> direction (e.g. Hal 4 → Hal 5)? And roughly how long is the real run?

Note also that **nothing in the regression harness would have caught this**:
`regression_world_save.gd` hardcodes `line_3a` for its footprint check, so line
1 has never been footprint-tested at any length. `test_line1_flow_conformance`
(added this pass) reports the span but deliberately does **not** gate on it,
because the correct limit is unknown until the operator answers.

### ✅ RESOLVED — the fold is laid out (turn capability, 2026-08-28)

Operator sketch received + "build the turn capability and lay out the fold".

**New macro-builder capability** (`BuildMode.gd`): a line is now a chain of
straight LEGS. A main SEQ entry with `{"turn_deg": a}` rotates the heading `a`
degrees (positive = LEFT/CCW from above) around the cursor point, which
becomes the new leg's origin; `{"turn_advance": m}` pre-advances the new leg;
`{"extend_legs": true}` stretches an elevated entry's legs to the floor.
Per-node `macro_anchor` now records each node's OWN leg, `_macro_nominal_poses`
mirrors the walk (emitting a `leg` per pose), and `save_macro_overrides`
inverts per-leg with chain inheritance reset at each turn (mirrored on the
load side via `delta_base`). Two pre-existing mirror bugs fixed on the way:
nominal ignored per-entry `gap` overrides and lacked `at_entry` anchoring —
both previously masked by phantom-delta self-consistency in the round-trip
test.

**Line 1's fold** (sketch legs, turns L,L,R,R,L):

| Leg | Heading | Contents |
|---|---|---|
| A | (placement rot) | opzetband → shredder |
| B | LEFT | uitvoerband + magnet |
| C | LEFT | short belt → westa climb → **hoekgoot** (back, elevated 3.48 m) |
| D | RIGHT | vw_trommel → Y-goot → wet train → intake screws |
| E | RIGHT | flotation tank + dewater (sketch: offset south of the train) |
| F | LEFT | friction → Kufferath/MAS → silo → compactorband → extruder tail |

**Leg F's east heading: CONFIRMED** by the operator 2026-08-28 ("leg F is
correct") after being flagged as an assumption. The fold is fully
operator-sourced end to end; only archiving the sketch image remains open.

**Provenance:** the sketch is transcribed verbatim in
[`line1_layout_sketch_2026-08-28.md`](line1_layout_sketch_2026-08-28.md); the
**original image is not yet archived** (operator to save it into
`docs/plant/photos/`). Until then legs A–E rest on that transcription — one
level less sure than an archived original (review finding, 2026-08-28).

**Adversarial review (17-agent workflow, 2026-08-28):** 3 findings CONFIRMED
and fixed — (1) S4/S4b could skip silently if `_discharge_lip_pos` vanished
(proven by live mutation: PASS with 4 fewer checks) → the guard is now its own
red check; (2) the sketch provenance gap above; (3) a stale "8 m at 35°"
westa docstring bullet that outlived two rewrites. Self-adjudicated from the
unverified remainder: (4) REAL save-back bug — nominal poses omitted per-entry
`y` lifts, so saving macro overrides recorded a phantom dy that the loader
stacked ON TOP of the lift, doubling it each save/rebuild cycle (hoekgoot
3.48 → 6.96 m; latent for the 0.12 m lump carts since #225.3) → nominal now
includes the lift; (5) S4's 0.85 m gate was wider than a lost turn_advance
(0.49 m) → tightened to 0.35; (6) the plan-box +3 m flat margin understated a
14 m extruder's half-length → per-machine catalog half-extents.

**Measured, first build:** every derived corner number landed exact — hoekgoot
OUT over the funnel horiz 0.00 m / drop 0.30 m; westa lip over hoekgoot IN
0.00 / 0.15; all five leg headings ±90.0°; nominal-mirror parity worst
0.0000 m over 48 nodes (lump_cart excluded — live physics prop, settles
−0.29 m). **Folded plan box: 111.6 × 24.8 m — fits the 140 × 155 shell with
room to spare.** Mutation: flipping one turn sign produces 7 independent
FAILs (pattern, alignment, heading, plan shape). Consequence 1.A is CLOSED
pending the leg-F confirmation.

### GAP 1.3 — `compactor_band` missing on lines 1, 3A and 3B · ✅ FIXED

**Doc:** `extruder_silo` → `compactor_band` → `compactor` → `extruder`
(edges 32, 33, 34). Present in the flow graphs for **all three** lines.

**Sim:** all three go `extruder_silo` → `extruder` directly. The catalog has
`compactorband`, whose builder comment describes it running "Silo up into the
compactor's top funnel" — exactly this edge. It is placed **only** on line 3C.

**Not a gap — checked:** the `compactor`/PCU itself is correctly absent as a
standalone placeable on 1/3A/3B, because `_m_extruder_unit` builds the EREMA
cutter-compactor **integrated** into the extruder (`PlaceableCatalog.gd:10544`,
"SECTION 1: FEED / CUTTER-COMPACTOR (PCU) — SIDE-MOUNTED TANGENTIAL INFEED").
Adding a standalone `compactor` to those lines would double it.

**Extra corroboration beyond the diagrams**, found while fixing: operator
checklist **FORM-018** (`swi/FORM-018__064_CeDo120.md:52`) —
*"Compactor **banden** en compactor hoed compleet reinigen"* — plural belts,
in a section covering *"beide compactors"*. So these are real, separately
maintained machines, not a diagram abstraction.

**Fix:** `compactorband` inserted between `extruder_silo` and the extruder on
all three lines. On 3A it carries the `gap: 1.5` maintenance clearance, which
belongs next to the extruder rather than next to the silo.

**Proven:** the world regression builds line_3a and footprint-checks it —
42 → **43 machines, all 43 still inside the building footprint**, round-trip
stable, 17 ok / 0 fail. (Its `expected` count is computed from the SEQ, so it
self-adjusted.) Lines 1 and 3B are not footprint-tested by anything.

> Follow-on to check when the walk reaches 3C: `LINE_3C_SEQ` places a standalone
> `compactor` (index 21) **and** `extruder_screw` (index 22), which also routes
> to `_m_extruder_unit` and therefore also builds an integrated PCU. That looks
> like a double compactor on 3C. Unverified — do not act on it from here.

### FIX 1.4 — line 1 was running the `prewash_drum` STUB · ✅ FIXED

Operator-directed, 2026-08-28, mid-walk. Not a flow-diagram gap — a
**model-quality** gap, and the exact same disease as 1.1: an operator-approved
model orphaned while a stub gets placed.

`LINE_1_SEQ` placed `prewash_drum` — an 18-line unsourced stub (a trough, a
plain cylinder, a spray pipe, a motor). The real voorwastrommel geometry,
~150 lines built from operator photos and signed off by the operator (bolted
flange drive ring, axial-thrust bracket, rubber cradle tyres, yellow peeling
safety cage, "TANK A-4 / MAX CAP 50,000 L" placard, drain tray), sat unused
under the sibling id `vw_trommel`. Already recorded as finding **C5** in
`DETAIL_STANDARD_audit_2026-08-18.md`, and in `photo_audit.md:68` as
IMAGE OK / operator-reviewed.

**Fix:** in-place id swap in `LINE_1_SEQ` (index-stable, `seq.size()`
unchanged) **plus** a matching `MachineFlow.gd` change.

**The MachineFlow half is the important half.** `prewash_drum` carries a real
profile — `process "wash"`, `water_add 0.30`, `contam_remove 0.40`,
`waste 0.03`. `vw_trommel` had **no profile at all**, so swapping the id alone
would have silently dropped the machine to the inert `"convey"` default and
**deleted line 1's entire pre-wash stage** while looking like a pure visual
upgrade. Both ids now match in the same two arms. This is standing rule 3
biting for the second time in one document.

**Watch item → FIXED same day (operator: "fix the westa band alignment").**
The swap shrank the drum from 6.0 × 6.5 × 11.25 to 3.6 × 4.5 × 8.0, and
`westa_band_1` was still hand-aimed at the old stub's 6.5 m top. **Measured
first** (test S4, in the BUILT line, before any fix): discharge lip at
y = 7.20 m vs funnel mouth at y = 4.15 m — a 3.05 m free fall — and the lip
overshot the mouth horizontally by 1.59 m. The placement model predicted both
numbers exactly, so the fix was derived, not tuned:

- New shared helper `PlaceableCatalog.vw_trommel_funnel_mouth_local(size)` —
  single source of truth used by BOTH `_m_vw_trommel` (to place the feed cone)
  and the `westa_band_1` spec (to aim the belt), so they cannot drift apart.
- `belt.incline_run` is now DERIVED at build time: `(mouth_y + 0.30 −
  deck_height) / tan(45°)` — no baked height constant remains.
- Catalog size re-derived 1.6×7.0×9.5 → 1.6×4.8×7.2 (z chosen so the funnel
  lands dead-centre under the lip; full derivation in the catalog comment).
- `test_line1_flow_conformance` S4 measures the lip→mouth relationship in the
  built world: **horiz 0.01 m, drop 0.30 m** after the fix. Mutation-tested:
  mis-aiming the belt +2 m turns both S4 checks red (drop 2.30 / overshoot
  1.99), then restored clean. 51 ok / 0 fail.
- Side effect: line 1 shortens 161.4 → **159.1 m** (consequence 1.A still
  open — the fold).

---

## Doc 2 — `lijn_3a_flow.md` (36 material edges + water)

Walked 2026-08-28 against `LINE_3A_SEQ` + `MachineFlow` + the Q&A rulings.
**Cleared, not gaps:** C1 = Pomp C1 (placed, #81); kopfilter (built INTO
`_m_extruder_unit` SECTION 5, doc-cited); M11a appearing twice (ruled real);
compactorband (fixed by gap 1.3); VSS before vuilsnippersilo (#136 ruling);
transfer_chute glijgoot (LA1-doc-sourced).

### GAP 2.1 — mengsilo loop miscomposed · ⚠ SUPERSEDED BY RULING 2.1-B (below)

**Doc** (edges 13-28, backed by `photo_audit.md:34`'s spine and
`fixed_equipment_inventory.md:29`): main path = M11b → V2 → **ringleiding →
cycloon & windzifter** → V2a → verdeelwals → thermische droger → cycloon→V3 →
extruder silo; rondmeng-lus = M11a₂ → **verdeelwals m14** → V1 → silo top.

**Sim, before:** the recirc loop held the ringleiding + a cyclone (its comment
claimed an operator description no ruling records), the loop lacked its
verdeelwals, and the main path had an extra early verdeelwals + extra trailing
cyclone found in no document.

**Operator 2026-08-28:** "Diagram is right — fix the sim."

**Fix:** both paths recomposed to the diagram in `LINE_3A_SEQ` (3A drops
43 → 41 machines). "Cycloon & windzifter" and "Cycloon → ventilator V3" are
each ONE doc station rendered as two adjacent placeables; intra-station order
is undocumented and kept from the old SEQ. Proven by the NEW
`test_line3a_flow_conformance` (12 checks: SEQ order, world counts, and the
LineFlow RECIRC edge from V1's blower back into the silo — doc edge 22);
mutation (ringleiding back into the loop) goes red 4 ways. World regression
17/0, all 41 machines inside the footprint.

### ⚖ RULING 2.1-B — the operator's own wiring of the mengsilo area · ✅ APPLIED

Same day, hours after "Diagram is right": the operator explained that answer
came from misreading the question, and gave his own account of the machines
he ran. **Operator supersedes diagram** (the diagram stays the authority for
block NAMES only):

- **INFEED:** mech. dryer → blower → **windzifter** → blower → **one BIG
  cyclone on the mengsilo TOP** → silo. (Diagram had the windzifter after
  the silo.) Both blower lines — windzifter's and the ring's — enter that
  same top cyclone at ~180° opposite inlets.
- **LOOP:** doseerschroef M11a₂ → verdeelwals m14 → V1 → **the RING** → the
  shared top cyclone → silo. Always on while the line runs; heated (the
  60×60×200 heater cabinets feed the air side). **On 3A, the diagram's
  "thermische droger" IS this heated ring circuit** — "kind of dead" as a
  separate machine; the real thermal-dryer machine belongs to **line 3B**
  and works differently.
- **MAIN:** doseerschroef M11b → blower → "pipeline pipeline pipeline" →
  extruder silo. No windzifter, no verdeelwals, no thermal dryer here.
- **Ring geometry** (detail program): starts at the bottom, 180° turn, up a
  bit, 180°, other side, 180° — two serpentine loops, then up to the cyclone.

Applied in `LINE_3A_SEQ` (3A now 38 machines): windzifter + second blower +
the lifted shared cyclone (y 5.9, negative gap pulls the silo under it) on
the infeed; the ring moved into the lus as its LAST stage (recirc edge ring →
silo, physically via the top cyclone); main path reduced to screw → blower →
extruder silo; `thermal_dryer` removed from 3A entirely.

**Pre-measured gap for doc 3:** `LINE_3B_SEQ` has NO `thermal_dryer` — and
per this ruling the real machine is 3B's. Expect that gap when the walk
reaches `lijn_3b_flow.md`.

Proven: test_line3a_flow_conformance rewritten to 2.1-B — 30/30 (infeed
composition, lifted cyclone, lus incl. ring, bare main path, no thermal
dryer anywhere, recirc edge from the RING, top-cyclone → silo drop edge,
severed-main guards, bigbag block). World regression 17/0, 38/38 inside;
3A identity ledger 4/0.

### GAP 2.2 — bigbag station missing · ✅ FIXED

Doc edge 36: Weegschaal → **bigbag station**. RULED a 3A-only feature, with a
behaviour fact (extruder runs out to bigbag after a knife/screen change until
quality is OK — future gameplay hook, not built). The sim had no bigbag
placeable of any kind.

**Fixed 2026-08-28** from the operator's composite spec (two chat reference
images, to be archived like the fold sketch): bottom per image 1 — open
square-tube frame, bag on its 4 loops on corner hangers, wooden EURO pallet
underneath; top per image 2 — metal fill cylinder with the bag's "trunk"
sleeve bound by a BLUE strap, small cyclone on the frame top. New placeable
`bigbag_station` (1.7 × 3.6 × 1.7, Logistics), MachineFlow SINK (the bag
banks granulate; a full bag leaves by forklift), placed as a -X branch off
the 3A weegschaal. Render: `renders/shot_bigbag_station.png`, sent for
sign-off.

**MAJOR side catch — the severed-main bug.** The test's guard check
"weegschaal STILL feeds the voorraad silo" went red: a source tagged with
`lf_explicit_outs` skips LineFlow's geometry fallback (`LineFlow.gd:1142`)
and the #71 branch-close never reconnected it to the next main. Adding the
same check at the mengsilo proved the pre-existing case: **3A's main line has
been topologically SEVERED at the mengsilo since #71** — the side-loop closed
but mengsilo → M11b never existed, and the mass-ledger tests stayed green
because a stalled line also conserves mass. Fixed in BuildMode's branch-close:
a RECIRC chain now re-links source → next main (a side-loop is a
side-circuit), and a chain ending in a SINK (bigbag) links source → next main
instead of the dead sink → main edge. Proven: 25/25 on the 3A conformance
test (both "STILL feeds" checks red before the fix, green after), 3A/3B
identity ledgers 4/0, line-1 conformance PASS, world regression 17/0.

### Q 2.3 — Intrekrol / Uittrek rol flotatie tank · ✅ ANSWERED (operator 2026-08-28)

All part of the flotation tank — no separate machines, the sim topology was
already right. Operator description, recorded for the model-detail program:
- The tank is a POOL on metal legs, a few metres up.
- **Intrek** = the FIRST paddle, LARGER than the rest.
- Middle: ~5-10 (model-dependent) smaller TRANSPORT paddles pushing the film
  along the surface repeatedly — washing it while the heavies sink.
- A **bottom scraper** runs along the tank's bottom centre, then UP a ~45°
  incline; the scraped heavies fall into a CONTAINER below.
- **Uittrek** = the LAST paddle, larger like the first, at the far edge, so
  it pushes material up OVER THE LATCH (overflow lip) — usually into a
  dewatering screw.
`_m_flotation` today: uniform paddle shafts, no first/last size distinction,
no bottom scraper / 45° incline / container. → model-detail backlog item,
not a topology gap.

### Q 2.4 — Heaters (3× hot-air blocks) · ⚙ SPEC RECEIVED (operator 2026-08-28)

Heater elements heat air, which the blower sucks in; the material joins from
the doseer screw and warm air + material are blown onward. Model spec: a
**60 × 60 cm cabinet, ~2 m high** housing the filter stacks; pipes run from
the BOTTOM of the filter stacks to the blower. Build as role-none side units
(pomp_c1 pattern) beside V2/M11b, V1 and the thermische droger.

The ring question this answer raised is CLOSED by ruling 2.1-B: the ring
lives in the rondmeng loop. Remaining build item: the three heater cabinets
(60×60×200, filter stacks, pipes from the stack bottoms to the blowers) as
role-none side units — needs a small model pass.

---

## Doc 3 — `lijn_3b_flow.md` (27 material edges + water)

Walked 2026-08-28 against `LINE_3B_SEQ`. **Cleared, not gaps:** the front wash
chain matches the doc end-to-end (vuilsnippersilo → M11a screw → rafter →
rafter-ontwaterschroef → frictiescheider 210 → flotation tank (intrek/uittrek
rollers integrated per ruling Q2.3) → ontwaterschroef → frictie li/re →
parallel dryers 310/311); VSS-first is the #136 ruling; kleine_la is the
checklist-sourced water fixture; compactorband was gap 1.3; kopfilter is
integrated in the extruder unit; no bigbag (doc draws none + Q&A ruling —
guarded by the 3A test); no mengsilo/rondmeng on 3B ✓.

### GAP 3.1 — the 3B dry section ran through an undocumented plasmaq · ✅ FIXED

**Doc** (edges 12-19): Ventilator (recombine) → **Verdeelwals** →
**THERMISCHE DROGER** (+ Heater, hot air) → ventilator → **Ringventilator** →
extruder silo.

**Sim, before:** blower → cyclone → **plasmaq** → cyclone → blower → cyclone →
extruder silo. No verdeelwals, no thermal dryer — and the plasmaq is a
**line-3C machine** (L3C.16, HMI-photo-verified, `Line3CDef.gd:74`); no 3B
source for one exists anywhere in the corpus.

**Corroboration:** ruling 2.1-B the same day — operator, unprompted: *"the
thermal dryer I think is for line three b, actually"* — the REAL machine,
working differently from 3A's heated ring. Doc and operator agree; fixed
without a further halt (flagged for operator review in-session).

**Fix:** dry section recomposed to the doc. The two unnamed fan blocks stay
generic `blower` placeables — the doc's own open question 6 asks the operator
for their V-numbers. Proven by NEW `test_line3b_flow_conformance` (22 checks,
3 layers: SEQ incl. front-chain order and no-plasmaq/no-mengsilo/no-bigbag
guards; world counts; LineFlow wiring incl. the li/re split feeding BOTH
dryers, both recombining at the Ventilator, and the thermal dryer fed AND
feeding onward). Mutation (plasmaq chain restored) goes red 10 ways. 3B
identity ledger 4/0; world regression 17/0.

**Open (from the doc's own operator-question list):** rafter brand/type (Q1 —
model itself operator-approved 2026-07-15), the two fan V-numbers (Q6), the
zeefbocht fed by "Pomp zeefbocht" (Q3), LA1/P1 water routing (Q4). The heater
cabinet beside the thermal dryer joins doc 2's pending heater-cabinet build.
