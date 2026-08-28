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
| 1 | `lijn_1_flow.md` + `line_flow_graphs.json` (line "1") | ⚙ gaps 1.1, 1.2, 1.3 + fix 1.4 all fixed; consequence 1.A (line-1 fold) open |
| 2 | `lijn_3a_flow.md` | ☐ |
| 3 | `lijn_3b_flow.md` | ☐ |
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

**Watch item:** the swap changes the machine's size from 6.0 × 6.5 × 11.25 to
3.6 × 4.5 × 8.0. Line 1 gets 3.25 m shorter (helps consequence 1.A) but the
drum top drops ~2 m, and `westa_band_1` immediately upstream is described as a
45° incline feeding "the TOP of the pre-wash drum". That alignment wants an
eyeball once the fold lands — flagged, not yet checked.
