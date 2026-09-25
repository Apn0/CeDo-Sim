# The 3A/3B intake is wired as the plant runs it (2026-09-25)

Follow-up to `flow_node_twins_2026-09-25.md` §6, which found this and left
it: "The opzetband skips its shredder on both 3A3B feed macros … The intake
macro is unchanged: 17 nodes, with `opzetband_3a3b`, `shredder_2` and `u_bay`
as heads. It is still open." The sort-line half was fixed the same day
(`sort_line_topology_2026-09-25.md`, #306), and this change reuses its idioms.
It touches `INTAKE_3A3B_SEQ` only, plus the U-bay's MachineFlow profile.

Branch `claude/focused-jackson-bff053`, worktree `mystifying-franklin-db632a`,
on `origin/main` `a4b2031` (#307, the twin fix). Operator rulings:
`docs/plant/operator_rulings_2026-09-25.md`, fourth part ("Transportbanden
3A/3B").

## 1. The defect, measured

`src/tests/dump_line_graph.tscn -- line_intake_3a3b opzetband_3a3b`, on
`a4b2031`, under a scratch APPDATA: 17 nodes, 16 edges, 0 cycles. `mN` is the
`INTAKE_3A3B_SEQ` index.

```
opzetband_3a3b[m0]    -> inclined_belt_8m[m2]    geometry   skips shredder 2
shredder_2[m1]        -> inclined_belt_8m[m2]    geometry
inclined_belt_8m[m2]  -> transportband_1[m3]     geometry
transportband_1 … 7   -> the next belt           geometry
transportband_8[m10]  -> transportband_8_5[m11]  explicit   C8's ONLY edge
transportband_8_5[m11]-> transportband_9[m13]    geometry   overflow belt feeds C9
u_bay[m12]            -> transportband_9[m13]    explicit   the dump feeds C9
transportband_9 … 11  -> the next belt           geometry
NOIN  (feed heads): opzetband_3a3b[m0], shredder_2[m1], u_bay[m12]
NOOUT (dead ends):  switch_belt[m16]
```

**The head.** The probable cause in the task was right. The opzetband's
discharge, `wout (0.0, 4.9, -27.1)`, is 5.78 m from the climb belt's inlet and
6.44 m from shredder 2's, so the nearest-inlet fallback picks the climb belt.
The 18 m deck ends 6.4 m past shredder 2's throat (z -20.7), which is the same
geometry the sort line's opzetband has against shredder 1. Shredder 2 then has
no in-edge, and LineFlow treats it as a feed head.

**The overflow.** C8.5 and the U-bay sit at `x ≠ 0` with no flag, so BuildMode
put them in one `branch_chain`. Such a chain gets exactly two explicit edges:
the previous main entry feeds its first member (`C8 → C8.5`), and its last
member feeds the next main entry (`U-bay → C9`). The first one makes C8 an
explicit source, and LineFlow skips the geometry fallback for explicit sources,
so C8 lost its forward edge to C9. Three consequences:

- Every kg on C8 went to C8.5, whichever way C8 ran. LineFlow's Conveyor8
  overlay (#138) splits a splitter's output by direction only when it has two
  edges, so it never engaged.
- C8.5 fed C9 by geometry (3.75 m, against 5.72 m to the U-bay).
- The U-bay, with no inlet, was a feed head into C9.

## 2. What settles each link

| link | source |
|---|---|
| the belt into shredder 2 is a plain conveyor, no bale on it | **operator 2026-09-25** (T1): "just a conveyor that feeds it. And there is no [bales] being placed anywhere on that conveyor" |
| that belt → shredder 2 | T1; `LINE_SORT_SEQ` 18 → 19 (the same belt on the sort line, "Long transfer conveyor to Shredder 2") |
| shredder 2 → climb belt → transportband 1 | `LINE_SORT_SEQ` 19 → 20 ("Climb conveyor to Transportband 1"); `misc_sources.md` §1b ("Shredder 2 … small flakes … enter the transportation belts system"); this SEQ's own comment on the climb belt |
| C8 forward → C9; C8 reversed → C8.5 → U-bay; the U feeds nothing | the operator's notes, `misc_sources.md` §1b ("8 can spin in both directions … 'normal' direction is towards 9 … This other direction discharges the material to the slightly lower conveyor 8.5; which feeds the U"); **confirmed 2026-09-25** (T2) |
| C1 … C7, C9 … C11, switch belt | not re-pinned: the fallback's picks are 0.6–1.6 m apart and match the operator's "7 … material from 7 lands on the center of 8" / "switch belt should be below conveyor 11" |

The opzetband at entry 0 came from commit `a3fa4b4` (2026-06-14, "D4 —
opzetband_3a3b at the head feeds the shredder. Was missing; macro previously
assumed bales arrived at the shredder by hand"). No source was recorded; the
sort-line D4 entry in the same commit says "operator:", this one does not.

Not changed, recorded in T1: shredder 2 "is actually more similar like a mill
on the other lines". Its MachineFlow process is still `shred`.

## 3. The fix

**`INTAKE_3A3B_SEQ`** (`src/build/BuildMode.gd`). No entry moved, so every
index after 0 keeps its meaning.

- Entry 0 is `transport_belt` instead of `opzetband_3a3b` (T1).
- `explicit_from_prev` on entries 1, 2 and 3: the belt → shredder 2 → climb
  belt → transportband 1 are declared. Only the first was wrong, but with a
  plain belt at entry 0 the fallback happens to pick shredder 2 (its inlet is
  5.1 m from the belt's outlet, the climb belt's 5.8 m), and a lost pin would
  pass unnoticed until the layout moved (the sort line's M4 lesson).
- `"stream": "overflow"` on C8.5 and the U-bay. A stream chains its members
  explicitly (`C8 → C8.5 → U-bay`), which a `branch_chain` does not.

**A stream can now end** (`BuildMode.macro_flow_edges`). A stream whose last
member feeds nothing (a sink, or MachineFlow `no_outlet`) writes no merge
edge. The main path continues from the stream's split to the next main
entry, as a chained branch that ends in a sink already did. That
continuation, `C8 → C9`, is inserted **before** the split's other edges. The
reason is that LineFlow's Conveyor8 overlay reads C8's edge 0 as forward and
edge 1 as reverse, which is the order the geometry linker emits for a
splitter (`wout`, then `wout2`). Appended after the stream's opening edge, it
would send C8's forward share into the overflow belt (mutation M4). No other
macro has a stream that ends on a machine that feeds nothing, so no other
line's edges change (§6).

**The U-bay feeds nothing** (`MachineFlow.profile("u_bay")`). It gets
`no_outlet = true`, and LineFlow's geometry pass skips such a node the way it
skips a sink. It stays a `buffer`, not a sink: LineFlow counts whatever a sink
takes as granulaat (`gran_mass`), and HmiOverlay reads a sink's inlet as "what
is about to be pelletised". So what reaches the U-bay stays in its out-buffer
until a Merlo scoop is modelled. The old profile comment said the U-bay fed
"the wash-line head too"; the operator's notes and T2 say it does not.

## 4. After

Same dump, fixed tree: 17 nodes, 16 edges, 0 cycles.

```
transport_belt[m0] -> shredder_2[m1] -> inclined_belt_8m[m2] -> transportband_1[m3]   explicit
transportband_1 -> 2 -> … -> 7 -> transportband_8[m10]                                geometry
transportband_8[m10] -> transportband_9[m13] (edge 0), transportband_8_5[m11] (edge 1) explicit
transportband_8_5[m11] -> u_bay[m12]                                                   explicit
transportband_9 -> 10 -> 11 -> switch_belt[m16]                                        geometry
NOIN  (feed heads): transport_belt[m0]
NOOUT (dead ends):  switch_belt[m16] (its VSS silos stand on the 3A/3B macros), u_bay[m12]
```

**Through a save/load** (`dump_line_graph.tscn -- line_intake_3a3b
transport_belt --reload`): the same 16 edges, heads and dead ends, and C8's
out-line reads `transportband_9 (explicit), transportband_8_5 (explicit)`, so
the order survives too. The task brief said pins do not survive a save/load.
That was true until #295/#298 (`macro_edges_reload_2026-09-25.md`) and is not
any more. `test_macro_edges_reload` measures the intake at 6 explicit edges
built and 6 re-derived.

## 5. Guard: `test_fallback_chains` (already in `run.sh`)

83 checks before, **109** after. What was added:

- **H1** the intake's only feed head is `transport_belt` (entry 0).
- **H2** is now per line by id (`DEAD_ENDS`). On the intake the only dead ends
  are the switch belt and the U-bay. The other four lines still have none.
- **Chain "3A/3B intake head"**, anchored on SEQ index 0 (not on an id, so
  that the old SEQ still resolves and its bypass shows up in kg):
  - G1–G3: shredder 2 is fed only by the belt, and each link is exclusive.
  - **G2 (feeder):** the belt feeds only shredder 2.
  - **G6:** all three links are declared (`lf_explicit_outs`), not guessed.
  - F feeds 950 kg/h at the **belt**, not at shredder 2.
    - **F3a:** shredder 2 carries at least half of what was fed.
    - **F3b:** transportband 1 gets no more than went through shredder 2, so
      nothing reached it around the shredder.
- **O — conveyor 8**, by name:
  - O0: the four machines are LineFlow nodes, and C8 has its Conveyor8
    controller.
  - **O1:** C8's out-edges are exactly `[C9, C8.5]`, in that order.
  - O2–O4: C8.5 is fed only by C8 and feeds only the U-bay; the U-bay is fed
    only by C8.5 and feeds nothing; C9 is fed only by C8.
  - O5: all three overflow edges are declared.
- **O — conveyor 8, by kg.** 30 s of warm-up, then 950 kg/h fed at C8 for 30 s
  plus a 30 s drain, once forward and once reversed.
  - **O6/O7:** forward, the kg reach C9 and nothing reaches C8.5 or the U-bay.
  - **O8–O10:** C8 held at full reverse (`direction_x = -1`). The kg reach the
    U-bay through C8.5, nothing reaches C9, and C8 stayed reversed through
    the phase.

The reverse phase **holds** C8 in reverse. `Conveyor8.direction_x` only
moves in `_physics_process`, and the suite ticks LineFlow synchronously, so
no frame passes. O8 checks it held. This proves the wiring and the overlay.
It does not prove the both-VSS-full trigger, which runs into the pack-up
cascade (§7).

Measured on the fixed tree: `PASS (109 ok, 0 fail)`, 0 `^SCRIPT ERROR`, 94 s
of wall time (the O phases add 38 s; the watchdog is 360 s).

| measurement | value |
|---|---|
| fed at the belt, 120 s | 31.7 kg |
| through shredder 2 | 31.7 kg |
| reached transportband 1 | 31.4 kg |
| C8 forward: fed at C8 → C9 / C8.5 / U-bay | 7.9 → 7.9 / 0.0 / 0.0 kg |
| C8 reversed: fed at C8 → C9 / C8.5 / U-bay | 7.9 → 0.0 / 7.9 / 7.9 kg |

### Mutation proofs

Each mutation edits one file, runs the suite under a scratch APPDATA on D:, and
restores the file byte for byte (md5 checked after every run). Script:
`D:\cedo_scratch_mystifying-franklin\mutate.py` (scratch, not committed).
Baseline in the same script: `PASS (109 ok, 0 fail)`.

| # | mutation | result |
|---|---|---|
| M0 | the whole intake SEQ back to the original (opzetband, no pins, old branch) | 93 ok, **16 fail**: H1, H2, G1, G2 (feeder), G3, G6, O1–O5, O7, O9, O10, **F3a, F3b** |
| M1 | the head pins off (entry 0 stays `transport_belt`) | 108 ok, **1 fail**: G6 |
| M2 | entry 0 back to `opzetband_3a3b`, pins kept | 108 ok, **1 fail**: H1 |
| M3 | `macro_flow_edges`: the dead-end stream rule off (merge edge written, no continuation) | 102 ok, **7 fail**: H2, O1, O3, O4, O5, O7, O10 |
| M4 | the continuation APPENDED after the stream's opening edge (C8's edge order swapped) | 104 ok, **5 fail**: O1, **O6, O7, O9, O10** |
| M5 | LineFlow's geometry pass ignores `no_outlet` | 105 ok, **4 fail**: H2, O3, O4, O10 |
| M6 | `u_bay` `no_outlet` false in MachineFlow | 102 ok, **7 fail**: H2, O1, O3, O4, O5, O7, O10 |

Every run: 0 `^SCRIPT ERROR`.

M0 is the measured defect. It fails in kg as well as by name: under it,
shredder 2 moves nothing of what is fed at the head. M1 is why G6 exists. With
a plain belt at entry 0, the fallback happens to pick shredder 2, and only
"declared, not guessed" notices the lost pins. M4 is why O1 asserts ORDER:
with the order swapped, C8 forward sends every kg to C8.5 and C8 reversed
sends every kg to C9, and all four kg checks go red.

## 6. The other suites that build this macro

Each was run alone under a scratch APPDATA on D: (see §8 for why not C:).

| suite | result |
|---|---|
| `test_flow_node_unique` | PASS (34 ok). Its C3 fed the intake at the id `opzetband_3a3b`; it now feeds entry 0, whatever its id. |
| `test_macro_edges_reload` | PASS (60 ok), 0 `^SCRIPT ERROR`; intake 6 explicit edges built, 6 re-derived |
| `test_sort_line_topology` | PASS (97 ok). The sort line's streams close on a belt, so the new stream rule does not apply |
| `test_fallback_chains` | PASS (109 ok) |

**Full harness.** `bash tools/regression/run.sh` on this worktree, `a4b2031` plus
this change (uncommitted). `PROJ=` was set. `APPDATA`, `UD` and `TEMP` pointed
at D:, which held a copy of the operator's `app_userdata` (`world_layout.json`
md5 `e046af7d…`) and of `SharedTextures`. Missing `assets/` files (145: HMI
reference photos and the machine WAVs) were copied in from the operator's
checkout, never linked. The launcher waited until no Godot process had run for
180 s, because another session's harness was running.

Result: `== done (exit 1)`, 141 steps, 55 min (16:01:22 → 16:56:25), 132
logs by mtime, 0 timeouts. The sentinel reported "untouched by every step".
There was **1 red, `test_npc05_realworld`** (expected: the chain does not
complete).

Inside the run:

| suite | result |
|---|---|
| `test_fallback_chains` | 109 ok |
| `test_flow_node_unique` | 34 ok |
| `test_macro_edges_reload` | 60 ok |
| `test_sort_line_topology` | 97 ok |
| `test_extruder_silo_chain` | 41 ok |
| `test_machine_sounds` | 80 ok |
| `test_jam_baseline` | 19 ok, 0 skipped |
| `test_nav_connectivity` | 12 ok |
| parse sweep | 470 ok, 0 fail |

`^SCRIPT ERROR` lines appear in two logs, and neither is a failure:

- `parse_sweep.log`: the non-gated `ERR_COMPILATION_FAILED` noise its header
  describes.
- `route_goal_clearance.log`: `Identifier not found: EventBus` in `--script`
  mode, then `Result: PASS`.

These are the same two that `flow_node_twins_2026-09-25.md` §7 recorded. The
operator's real `world_layout.json` kept md5 `e046af7d…`.

## 7. Found on the way, not fixed here

- **The pack-up cascade (#139) contradicts the operator's notes.** With both
  VSSs FULL, the notes say the conveyors from the bunker back to the
  trilzeef pause one per second, and the flakes still coming through shredder
  2 run C8 (reversed) → C8.5 → U. `LineFlow._PACK_UP_ORDER` pauses C11, C10,
  C9, **C8.5 after 3 s and C8 after 4 s**, then C7 … C1, the trilzeef and the
  bunker. C8's reversal alone takes 2 + 2 s (`Conveyor8.DIR_RAMP_RATE`), so in
  the sim the U-bay can take at most a moment's flow. This comes from reading
  the code; the both-full sequence was not driven here. Fixing it means
  changing which belts pack up, which is an operator call.
- **The layout does not match the flow.** The feed belt discharges at y 0.8
  under shredder 2's hopper inlet at y 5.1. C8.5 stands beside C8's forward
  half, while the operator's notes put it at the other end from C9. The
  intake macro also repeats shredder 2 and the climb belt that the sort line
  already places (`LINE_SORT_SEQ` 19–20), so placing both macros gives two of
  each.
- **Old saves.** A layout saved with the opzetband at entry 0 no longer
  matches the SEQ, so a reload refuses to re-pin that intake line (one
  warning) and it keeps geometry wiring. Two files on this machine hold one:
  `__outdoorroute___factory.json` (a test residue) and `sandbox_layout.json`
  (2026-08-16). Re-placing the macro gives the new head.
- **The switch belt's second outlet.** `MachineFlow.profile("switch_belt")`
  still describes `out2` as "toward U-bay". The operator's notes moved the U
  to C8.5 ("should be after conveyor 8.5 … NOT after 12").

## 8. The C: drive was full

During this work `C:` measured **0.00 GB free**, and AtomicFile's writes
failed with `ERR_FILE_CANT_WRITE` (13). One of the reload suite's runs lost
its phase D this way: the save failed, the read returned null, and the phase
aborted on a `SCRIPT ERROR`, so the suite printed `PASS (51 ok)` with nine
checks never run. On D: the same suite reads `PASS (60 ok)`. The operator's
real `app_userdata` is on C: too. A scratch APPDATA on C: also lets a run
start downloading texture packs (`SharedTextures/polyhaven/*.part`, 114 MB
from one `test_flow_node_unique` run). Those were deleted, and every later
run used `D:\cedo_scratch_mystifying-franklin`.
