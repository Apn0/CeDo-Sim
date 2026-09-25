# The sort line is wired as the plant runs it (2026-09-25)

Follow-up to `cycle_guard_swap_2026-09-25.md` §6, which found this and left
it: "The sort line's topology. The sorters feed the final climb belt directly
… `shredder_2` has no in-edge."

Branch `claude/unruffled-vaughan-c64987`, worktree `wonderful-euclid-80a5da`.
Operator rulings: `docs/plant/operator_rulings_2026-09-25.md`, second part
("Sorteerlijn 3A/3B").

## 1. The defect, measured

`src/tests/dump_line_graph.tscn -- line_sort`, at `dd5c4af` (main with the
cycle-guard fix, before #295), under a scratch APPDATA: 20 nodes, 20 edges,
0 cycles. `mN` is the `LINE_SORT_SEQ` index.

```
opzetband_3a3b[m0]   -> bunker[m3]               geometry   skips shredder 1
shredder_1[m1]       -> transport_belt[m2]       geometry
transport_belt[m2]   -> bunker[m3]               geometry
bunker[m3]           -> transport_belt[m4]       geometry
transport_belt[m4]   -> transport_belt[m5]       geometry
transport_belt[m5]   -> switch_belt[m6]          geometry
switch_belt[m6]      -> inclined_belt_8m[m9]     explicit   Titan lane only
inclined_belt_8m[m9] -> titech_sort[m12]         geometry   skips Titan 1
inclined_belt_8m[m10]-> tomra_sort[m14]          geometry   skips Tomra 1
titech_sort[m11]     -> titech_sort[m12]         geometry
tomra_sort[m13]      -> tomra_sort[m14]          geometry
titech_sort[m12]     -> inclined_belt_8m[m20]    geometry   skips m17, m18, shredder 2
tomra_sort[m14]      -> inclined_belt_8m[m20]    geometry   skips m17, m18, shredder 2
transport_belt[m15]  -> titech_sort[m12]         geometry   reject belt feeds a sorter
transport_belt[m16]  -> transport_belt[m17]      explicit   reject belt feeds the accept conveyor
transport_belt[m17]  -> transport_belt[m18]      geometry
transport_belt[m18]  -> titech_sort[m12]         geometry   transfer feeds a sorter BACK
shredder_2[m19]      -> inclined_belt_8m[m20]    geometry
switch_belt[m-1]     -> inclined_belt_8m[m9], transport_belt[m17]   (the twin, §7)
NO IN-EDGE (feed heads): opzetband[m0], shredder_1[m1], inclined_belt_8m[m10],
  titech_sort[m11], tomra_sort[m13], transport_belt[m15], transport_belt[m16],
  shredder_2[m19], switch_belt[m-1]
```

**Cause.** The side-lane entries 9 to 16 all sit at `x ≠ 0` with no flag, so
BuildMode put them in ONE `branch_chain`. Such a chain gets two explicit
edges: the split feeds its first member (`switch_belt → m9`), and its last
member feeds the next main entry (`m16 → m17`). LineFlow's nearest-inlet
fallback wired everything else. That covers the chain's other members, and
every pair of consecutive main entries, which have no edge of their own
(CLAUDE.md trap).

**Why the fallback cannot be trusted on this line.** Its placement does not
match its flow:

- The opzetband's 18.06 m deck discharges at z −27.1, 6 m past shredder 1's
  throat at −21.1 and 2.8 m below it. The bunker inlet was the nearest one.
- The incline tops sit at y 8.0, and the sorter inlets at y 1.9.
- m17 and m18 are MAIN entries (`x: 0.0`), so their `"z": 12.0 / 18.0` is
  never read. They stand right after the split, under the sorter lanes.
  Titan 2's inlet (z −60.3) was 3.7 m from the long transfer's discharge,
  and shredder 2's (−63.7) was 5.1 m.

## 2. What settles each link

| link | source |
|---|---|
| opzetband → shredder 1 → belt 1012 → bunker → belt 1040 | `question_answers.json` Q16, operator interview 2026-07-05: "shredder 1 -> belt 1012 -> bunker -> belt 1040"; SWI-048 p1 step 1 (shredder 1 and the bunkerrol at the head) |
| belt 1040 → transfer belt → split | `LINE_SORT_SEQ` header ("as specified by operator"), items 5–7 |
| split → two lanes (Titech / Tomra) | `hmi_reference.md` §21: the SOP routes film to "beide sorteerlijnen" with button 2040/2035; SWI-015: Titech 1 and 2, Tomra 1 and 2 |
| per lane: incline → sorter 1 → sorter 2, **series** | **operator ruling 2026-09-25** (S1), matching CEDO.xlsx's two ×0.7 stages (`misc_sources.md` §2e) |
| both lanes → accept conveyor → long transfer → shredder 2 → climb belt | SEQ header items 13–15; CEDO.xlsx (Titech/Tomra → Shredder 2); the operator's notes (`misc_sources.md` §1b); the 2026-08-26 bunker/shredder-2 interlock (TITECH/TOMRA sit between the bunker and shredder 2) |
| reject belts: not flow | **operator ruling 2026-09-25** (S2): on the plant they run to the balenpers; in the sim a reject is `LineFlow.poly_rejected`, a counted loss |

Not settled, and deferred by the operator ("lets discuss the sorting line
tomorrow"): the trilzeef his notes put before Titech/Tomra, and the Tomra
sorting model (§8).

## 3. The fix: flags only, no index moves

The SEQ's indices are keyed on elsewhere: `LineFlow._SORT_BUNKER_IDX` (3),
`_SORT_BUNKER_OUT_IDX` (4) and `_SORT_SHREDDER2_IDX` (19), which
`test_motor_trip_stops_conveying` also reads. So no entry was inserted or
reordered. Checked before editing:

- no `mount_over` or `at_entry` in `LINE_SORT_SEQ`;
- the operator's `user://macros/` holds no `line_sort.json` (only four
  `*.probe-bak-*` files for other lines).

`LINE_SORT_SEQ` (`src/build/BuildMode.gd`):

- `explicit_from_prev` on entries 1–6 and 18–20. Every main link is declared
  now, including the ones the fallback happened to get right, because on this
  line the fallback's inputs are wrong (§1).
- `"stream": "titech"` on 9, 11, 12 and `"stream": "tomra"` on 10, 13, 14.
  Each lane opens at the split (6), chains head to tail, and closes on the
  next main entry, the accept conveyor (17), which is the merge. 17 has no pin,
  because a pin would add `split → 17`.
- `"flow": false` on the reject belts 15 and 16. This flag is new:
  - `BuildMode._macro_entry_in_flow(entry)` reads it;
  - `macro_flow_edges` skips the entry, as it skips role-none ids;
  - `_stamp_macro_flow_edges` stamps the meta `lf_placement_only`
    (`BuildMode.LF_PLACEMENT_ONLY_META`). The build and the reload (#295's
    `_rederive_macro_flow_edges`) both pass through this function, so the meta
    is derived from the SEQ every time and never saved;
  - `LineFlow._process_discovered_node` skips a node carrying the meta.

  MachineFlow's role `none` could not express this, because `transport_belt`
  is a flow machine everywhere else.

## 4. After

Same dump, same tree plus the fix: 18 nodes, 19 edges, 0 cycles.

```
opzetband[m0] -> shredder_1[m1] -> belt[m2] -> bunker[m3] -> belt[m4] -> belt[m5] -> switch_belt[m6]
switch_belt[m6] -> incline[m9]  -> titech_sort[m11] -> titech_sort[m12] -> belt[m17]
switch_belt[m6] -> incline[m10] -> tomra_sort[m13]  -> tomra_sort[m14]  -> belt[m17]
belt[m17] -> belt[m18] -> shredder_2[m19] -> inclined_belt_8m[m20]
every edge explicit; switch_belt[m-1] -> incline[m9], belt[m17] geometry (the twin, §7)
NO IN-EDGE: opzetband[m0], switch_belt[m-1]     NO OUT-EDGE: inclined_belt_8m[m20]
```

The climb belt is the line's end. It hands off to transportband 1 of
`line_intake_3a3b`, which is a separate macro.

## 5. Guard: `test_sort_line_topology` (in `run.sh`)

It builds one bare BuildMode and one LineFlow, with no MainWorld and no bales.
The BuildMode's layout slot is never written: only in-game placement calls
`_save_layout`, and shared structure is off.

- **T:** each of the 17 flow entries is exactly one LineFlow node with the
  SEQ's id. The SEQ must still have 21 entries with the ids the suite names.
  The magnets (7, 8) and reject belts (15, 16) are placed, and are not nodes.
  The reject belts carry the meta. Any other node on the line is a named
  BeltBuilder twin, and only while it has no in-edge (§7).
- **E:** each node's in-set and out-set are exact, by SEQ index. Every edge
  out of a SEQ node is explicit (declared, not guessed).
- **C:** no cycle of any length, and an explicit 2-cycle search.
- **H:** the only feed head is the opzetband, and the only dead end is the
  climb belt.
- **K:** 950 kg/h is fed at the opzetband for 120 s, then the line drains for
  120 s. Checked:
  - the kg reach shredder 2 and the climb belt by name;
  - both lanes carry kg;
  - each lane's sorter 1 takes the whole lane, and sorter 2 takes sorter 1's
    output;
  - **every kg through the split passes both sorter stages (K7)**;
  - no machine processes more than was fed.

Measured: `PASS (97 ok, 0 fail)`, 0 `^SCRIPT ERROR`, 20.5 s of wall time
for 2400 ticks. Of 31.7 kg fed:

| node | kg processed | first kg |
|---|---|---|
| split belt [m6] | 31.3 | 31.7 s |
| incline (Titan) [m9] / (Tomra) [m10] | 15.7 / 15.7 | 33.7 s |
| Titan 1 → Titan 2 | 15.7 → 14.1 | 38.3 / 38.9 s |
| Tomra 1 → Tomra 2 | 15.7 → 15.7 | 38.5 / 39.4 s |
| accept conveyor [m17] | 29.0 | 48.3 s |
| shredder 2 [m19] | 29.0 | 53.0 s |
| climb belt [m20] | 28.7 | 55.2 s |

The Titan lane loses 1.6 kg in Titan 2 and 2.3 kg in all (`poly_rejected`).
The Tomra lane loses nothing, because Tomra has no sorting model (§8). The
first kg reaches the opzetband at 18.8 s: that is `start_line`'s
downstream-first PLC start, not transit.

**Why K7 exists.** The first draft asserted series only per lane (K3, K4).
The parallel mutation (M3 below) passed every kg check, because a split
feeding each sorter 2 directly still lets each sorter "pass its kg on". K7
asserts what the ruling says: the whole split goes through a sorter 1 AND a
sorter 2. Parallel wiring puts each stage at half (15.7 of 31.3 kg).

### Mutation proofs

Each mutation edits one file, runs the suite, and restores the file
byte-for-byte (md5 checked). Measured against the final 97-check suite:

| # | mutation | result |
|---|---|---|
| M0 | whole SEQ fix off (all pins, streams and `flow` flags) | 45 fail |
| M1 | `{"flow": false}` off (reject belts back in the flow) | 10 fail |
| M2 | shredder 1's pin off | 5 fail |
| M3 | sorters in PARALLEL per lane (sorter 2s on their own streams) | 7 fail, K7 among them |
| M4 | tail pins 18/19/20 off | 3 fail (E3 only, see below) |
| M5 | LineFlow ignores `lf_placement_only` | 5 fail |
| M6 | `_stamp_macro_flow_edges` stamps no meta | 7 fail |

M4 shows what E3 is for. Once the lanes merge on m17, the fixed cycle guard
refuses `m18 → Titan 2` (that edge would close a cycle), and the fallback
then happens to wire the tail right. Only "declared, not guessed" catches
the lost pins. Without that check, the tail would depend on the fallback
choosing correctly.

## 6. The other suites that build `line_sort`

Measured one at a time under a scratch APPDATA, before the merge with main:

- `test_fallback_chains`: PASS (83 ok). `line_sort` has no cycle.
- `test_macro_edges_reload`: PASS (60 ok). A10 (the same machines are
  discovered after a reload) and A11 (the whole LineFlow edge set is the same
  by name after a reload) cover this line's pins, and the reject belts
  staying out after a reload.
- `test_motor_trip_stops_conveying`: PASS (28 ok).
- `test_bunker_relay_trip`: PASS.
- `test_bunker_shredder2_interlock`: 1 red. That was a count: "≥ 5 OTHER
  transport_belt instances" was typed when the reject belts were flow nodes.
  4 remain (m2, m5, m17, m18). The check now derives the number from the SEQ
  (flow entries with id `transport_belt`, minus index 4) and asserts equality.
  After the change: PASS.

`test_fallback_chains` was missing from `run.sh` on the base. Merge `7cd9474`
(#296) dropped it. Main put it back in parallel (#299, `1c4977c`), so the
merge took main's line and added `test_sort_line_topology` after it.

## 7. Known, owned elsewhere: the BeltBuilder twin

`BeltBuilder.build()` tags the `Model` child it builds under a placeable's
body with `placeable_id` and the `placed_object` group. So a BeltBuilder belt
is discovered twice. On this line that is `switch_belt[m-1]`, which has no
`macro_index` and no in-edge, and gets two geometry out-edges. It cannot carry
kg: a head only draws from a bale on its feed point, and K runs with none. The
session "Fix intake belts discovered twice as flow nodes" owns the fix. It was
messaged about this change. The suite names the twin on a `NOTE` line and
leaves it out of the exact sets, but only while T7 holds (the twin has no
in-edge). After that fix lands, the NOTE reads 0 and nothing in the suite
changes.

## 8. Found, not fixed

All of these are for the operator's sort-line discussion (2026-09-26):

- **The trilzeef.** His notes put it before Titech/Tomra. This SEQ has had
  none since `9d16514`. The SEQ before that commit had two, one per lane.
  `LineFlow._PACK_UP_ORDER` names one.
- **`tomra_sort` has no MachineFlow profile.** It defaults to role `process`
  and process `convey`, so the Tomra lane sorts nothing (above: 15.7 → 15.7
  kg). It is still a NIR sorter for `_is_nir_sorter`, the air network and the
  shaft wrap.
- **The geometry (§1).** The opzetband overlaps shredder 1. The incline tops
  sit 6 m above the sorter inlets. m17 and m18 stand under the lanes. The flow
  no longer depends on any of this, but a render of the line shows it.
- **The split belt is the intake's `switch_belt`.** LineFlow drives its
  `SwitchBelt` jog controller from downstream headroom. In the measurement both
  lanes got 15.7 kg. The 2040/2035 button (both lanes, or one) is not modelled.
- **The reject leg to the balenpers** (ruling S2) is not modelled. It needs a
  reject output on the sorter node.
