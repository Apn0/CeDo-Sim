# LineFlow's cycle guard never fired: swapped, measured on every macro (2026-09-25)

Follow-up to `extruder_silo_tail_2026-09-25.md` §5 (PR #289), which found the
defect and pinned the 3A/3B silo tails around it. This change fixes the guard
itself. It is built on top of #289: this branch merges `4a8174f`, because the
swap alone sends 3A's compactorband to the laser filter, past the extruder
(§3).

## 1. The defect

`LineFlow._link_best_target(src_idx, …)` proposes the edge `src_idx → best`
and then called `_creates_cycle(best, src_idx)`. `_creates_cycle(from, to)` is
documented and implemented as "would adding edge from → to close a cycle": it
walks forward from `to` looking for `from`. The call therefore asked whether
the **source** already reached the **target**. In the geometry pass a source
has no out-edges of its own yet, so the answer was always no. #78's "full DAG
cycle prevention" has never refused an edge.

The fix is the argument order: `_creates_cycle(src_idx, best)`.

## 2. How it was measured

`src/tests/dump_line_graph.tscn` (from #289) builds one macro alone and dumps
the wired graph. This change adds three things at its end:

- an `EDGE a -> b kind` list, sorted, so two runs diff edge by edge;
- `NOIN` for every non-sink node with no in-edge. LineFlow treats such a node
  as a feed **head** and draws a bale at its feed point.
- `NOOUT` for every non-sink node with no out-edge.

It also adds `--reload`: build the line, save it with `BuildMode._save_layout`
to files with probe-only names, load it into a fresh BuildMode, and dump that.

All seven macros were dumped, each process under a scratch `APPDATA`. These
tree states were measured:

| state | cycle edges per line: 1 / 3A / 3B / 3C / intake 3A3B / sort / intake 3C6 | total |
|---|---|---|
| `main` 64921ff | 6 / 8 / 8 / 6 / 6 / 4 / 2 | 40 |
| `main` + #289 (the base of this change) | 6 / 6 / 6 / 6 / 6 / 4 / 2 | 36 |
| + swap only | 0 / 0 / 0 / 0 / 0 / 0 / 0 | 0 |
| + full fix (§4) | 0 / 0 / 0 / 0 / 0 / 0 / 0 | 0 |
| `main` + #289, **reloaded** | 14 / 14 / 12 / 6 / 8 / 4 / 2 | 60 |
| full fix, **reloaded** | 0 / 0 / 0 / 0 / 0 / 0 / 0 | 0 |

"Cycle edges" counts non-recirc edges whose target already reaches their
source. A 2-cycle counts 2. `user://macros/` holds no line overrides (only
`*.probe-bak-20260917` copies), so every macro was built from its constant
SEQ.

## 3. What the swap alone changes (main + #289 → + swap)

A refused back-edge falls through to the source's **next** candidate. That
candidate is not automatically right. Every changed edge, keyed
`id[macro_index]`:

| line | before | swap only | verdict |
|---|---|---|---|
| 1, 3B | `weegschaal → centrifuge` (2-cycle; `voorraad_silo` had no in-edge) | `weegschaal → voorraad_silo` | **right**: lijn_1 edge 39, lijn_3b edge 27 |
| 3A | `blower[m14] → wind_sifter` (2-cycle; the top cyclone had no in-edge) | `blower[m14] → transport_screw[m22]`, which is doseerschroef M11b | **wrong**: the infeed skips the mengsilo. Ruling 2.1-B says blower 2 blows into the big top cyclone. Needs a pin. |
| 1, 3A, 3B | `lump_cart ↔ lump_cart_spot` | `lump_cart → laser_filter` | **wrong**: furniture feeding a machine |
| 3C | two `lump_cart ↔ lump_cart_spot` | both `lump_cart → vacuum_degas` | **wrong**, same |
| 1, 3A, 3B, 3C, sort | `compressor_a ↔ compressor_b` | `compressor_a → compressor_b` only; `compressor_a` becomes a head | **wrong**: neither is a flow machine |
| intake 3A3B | `switch_belt[m16] → transportband_11[m15]`, plus the twin's two back-edges | removed | right to remove (see §6 for the twins) |
| sort | `inclined_belt_8m[m20] → shredder_2[m19]` | removed; `shredder_2` becomes a head | the back-edge is right to remove. The line around it is wrong, and was before (§6). |
| intake 3C6 | `trilzeef → inclined_belt_8m` | removed; `trilzeef` is the last machine | right |

On `main` without #289, the swap also sent 3A's compactorband to
`lump_platform` and 3B's booster blower to the compactorband. #289's pins
settle both. Measured, then superseded by basing this change on #289.

## 4. The fix, per edge

1. **The swap** (`LineFlow.gd`, one line plus its comment).
2. **3A: blower 2 → the big top cyclone is pinned.** `"explicit_from_prev":
   true` on `LINE_3A_SEQ`'s cyclone entry, per ruling 2.1-B. The lifted
   cyclone's inlet is 7.6 m from blower 2's discharge and M11b's is 4.1 m, so
   the geometry fallback never picks the cyclone. No entry was inserted, so no
   `macro_index` moves.
3. **The fixtures leave the flow graph.** `lump_platform`, `lump_cart_spot`,
   `lump_cart`, `compressor_a` and `compressor_b` join MachineFlow's role
   `"none"` list, as `overband_magnet` did on 2026-09-24 for the same kind of
   defect. Three places in the code already said these were not flow nodes:
   - BuildMode's I1 guard comment: "lump cart + spot" are role-none utilities;
   - `test_line3a_identity` / `test_line3b_identity`: "furniture … that
     LineFlow does not track";
   - `LineFlow._spawn_visible_compressors`: "they don't enter LineFlow's
     material graph".

   None of the five was on the list, so each defaulted to role `process`.
   Nothing needed the edges:
   - the laser filter drops lumps into a cart by physics, through
     `LaserFilter._closest_lump_cart` and the `lump_cart` group;
   - the air bank is AirNetwork's;
   - the lump-cart suites find carts by group.

   With the carts out of the graph, BuildMode's I1 guard also drops them from
   the post-extruder branch chain. On lines 1, 3A and 3B the chain becomes
   `extruder → laser_filter → heetafslag`, both edges explicit. Before, the
   pelletising melt ran `laser_filter → lump_cart → heetafslag`, through a
   cart.

Every changed edge, main + #289 → full fix (keyed `id[macro_index]`):

- **line 1:** 6 lump-furniture edges and the compressor pair removed;
  `laser_filter → heetafslag` (explicit); `weegschaal → voorraad_silo`.
- **3A:** `blower[m14] → cyclone[m15]` (explicit); 6 lump-furniture edges and
  the compressor pair removed; `laser_filter → heetafslag` (explicit).
- **3B:** 6 lump-furniture edges and the compressor pair removed;
  `laser_filter → heetafslag` (explicit); `weegschaal → voorraad_silo`.
- **3C:** 5 lump-furniture edges and the compressor pair removed.
- **intake 3A3B, sort, intake 3C6:** only the back-edges in §3 removed, plus
  the compressor pair on the sort line.

No other edge moved. After the fix, the only non-sink nodes with no in-edge
are the plant's own feed heads:

| line | feed heads |
|---|---|
| 1 | `opzetband_1` |
| 3A / 3B | `vss_silo`, `vuilsnippersilo` |
| 3C | `doseersilo` |

No non-sink node dead-ends on those four lines.

## 5. A reloaded world: fewer cycles, but pins are still lost

BuildMode does not persist `lf_explicit_outs` (#289 §7). A reloaded line is
therefore wired by the geometry fallback alone, and that includes this
change's 3A cyclone pin.

- **Before this change:** 60 cycle edges across the seven reloaded lines.
- **After it:** 0.
- **Still wrong after a reload:** the edges that rest on a pin. All of these
  were measured with `--reload`:
  - **3A:** `blower[m14] → M11b` (the pin is lost), `mengsilo → blower[m14]`,
    `ringleiding_3a → compactorband`, and `compactorband → laser_filter`.
    The mengsilo's two explicit outs and the ring's recirc are lost.
  - **3B:** `blower[m17] → compactorband`, `compactorband → laser_filter`,
    `extruder_3b → heetafslag`. Heads appear at the silo, the extruder,
    `mech_dryer` and the post-plasmaq cyclone.
  - **line 1:** the wet-side streams and the tail pins are lost (7 new heads).
  - **3C:** unchanged, because it runs on `Line3CDef.LINKS`, not on tags.

So the swap makes a reloaded world cycle-free. It does not make it right.
Re-deriving the tags on load is #289 §7's fix, and it is not part of this
change.

## 6. Found on the way, not fixed here (filed as separate tasks)

- **Intake belts are discovered twice.** Every BeltBuilder belt on
  `line_intake_3a3b`, and the sort line's `switch_belt`, has an `[m-1]` twin
  at the identical inlet and outlet. Each twin has no in-edge, so it is a
  feed head. This is unchanged by this fix. The swap only removed the twin's
  back-edges; the intake's `switch_belt[m16]` now feeds its own twin.
- **The sort line's topology.** The sorters feed the final climb belt
  (`inclined_belt_8m[m20]`) directly, which skips the collection conveyors
  (m17, m18) and shredder 2. Titan 1 → Titan 2 and Tomra 1 → Tomra 2 run in
  series. `shredder_2` has no in-edge. Before the swap, its only in-edge was
  its own downstream belt. The cause is the one CLAUDE.md records for line 1:
  every side-lane entry falls into one branch chain.
- **Not measured: the guard is greedy in discovery order.** It refuses an
  edge whose target already reaches the source, at the moment the source is
  linked. Macro nodes are discovered in SEQ order, so the upstream links
  first and a back-edge is what gets refused. For hand-placed machines
  discovered downstream-first, the first-linked edge would win instead, and
  the forward edge would be refused. The operator's world holds no placed
  machines today (no `factory_layout.json`), so nothing on his machine hits
  this yet.

## 7. Guard: `test_fallback_chains`, wired into `run.sh`

All seven macros stand in one world, 400 m apart, with one LineFlow.

- **C:** no non-recirc edge sits on a cycle, on each line.
- **X:** each of the five fixture ids is placed in the world, is not a
  LineFlow node, and has role `none`.
- **H:** lines 1, 3A, 3B and 3C have only their own feed heads and no
  non-sink dead ends.
- **G:** each chain is checked edge by edge by name, plus an explicit 2-cycle
  search. The chains are the 3A infeed (V4 → windzifter → blower 2 → top
  cyclone → mengsilo) and the granulate tail on lines 1 and 3B (laser filter
  → heetafslag → ontwaterzeef → centrifuge → weegschaal → voorraad silo).
- **F:** 950 kg/h is fed at each chain's first machine for 120 s, then the
  line drains for 60 s. The fed kg must reach the chain's last machine by
  name, and no chain machine may process more than 1.25 × the kg fed.

  The bound is 1.25 and not 1.05 because the heetafslag adds process water.
  For 31.7 kg fed, the ontwaterzeef processed 33.3 kg and the centrifuge
  32.0 kg (+5.0 % and +1.0 %). The mengsilo is left out of the circulation
  bound, because its own rondmeng loop re-processes what it holds.

Measured on the fixed tree: `PASS (83 ok, 0 fail)`, 0 SCRIPT ERROR lines.
188 LineFlow nodes and 191 edges. 1800 ticks took about 116 s of wall time.
First kg at the mengsilo came at 26.8 s, and at the voorraad silo at 15.3 s
(line 1) and 20.7 s (3B).

### Mutation proofs

MUTATIONS_PLACEHOLDER

## 8. Verification

VERIFICATION_PLACEHOLDER
