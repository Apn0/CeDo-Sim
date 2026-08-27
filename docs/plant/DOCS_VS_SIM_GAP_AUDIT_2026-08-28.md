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
| 1 | `lijn_1_flow.md` + `line_flow_graphs.json` (line "1") | ⚙ 1 of 3 gaps fixed |
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

### GAP 1.2 — `intrekschroef_11a` / `_11b` missing · ☐ OPEN

**Doc:** `maalmolen_1` → `ventilator_10a/b` → `intrekschroef_11a/b` →
`flotatie_tank` (edges 14-19).

**Sim:** post-mill chain is `mill` → 2× `blower` → 2× `cyclone` →
`flotation_tank`. No screws. A `transport_screw` pair does exist on line 1 but
sits **pre**-mill, where the doc has no screw at all.

Reads like the discharge screws were placed one stage too early. Needs an
operator check before moving them — and per standing rule 1, whether a chute
sits between the cyclones and the tank.

### GAP 1.3 — `compactor_band` missing on lines 1, 3A and 3B · ☐ OPEN

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

> Follow-on to check when the walk reaches 3C: `LINE_3C_SEQ` places a standalone
> `compactor` (index 21) **and** `extruder_screw` (index 22), which also routes
> to `_m_extruder_unit` and therefore also builds an integrated PCU. That looks
> like a double compactor on 3C. Unverified — do not act on it from here.
