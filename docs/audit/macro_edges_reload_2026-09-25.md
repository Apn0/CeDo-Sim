# Macro flow edges survive a save → load (2026-09-25)

Follow-up to `extruder_silo_tail_2026-09-25.md` §7. That section measured the
defect and did not fix it. This change fixes it, and `test_macro_edges_reload`
guards it.

## 1. The defect (measured before the fix)

BuildMode stamps a macro line's explicit flow edges as the `lf_explicit_outs`
meta, which is a list of NodePaths. It did that in one place only: inside
`_build_full_line`'s placement loop. `_save_layout` writes `macro_id`,
`macro_index` and `macro_anchor`, and nothing else about the line. So a world
loaded from a save had no explicit edges, and LineFlow wired every macro line
with its nearest-input-port fallback alone.

`probe_explicit_edges_roundtrip` measured this with lines 1, 3A and 3B:

- **Built:** 119 nodes, 121 edges, 47 tagged nodes.
- **Reloaded:** 119 nodes, 113 edges, 0 tagged nodes.

All three extruder-silo tails went back to broken wiring, and every other macro
lost its explicit edges too: line 1's twin streams, the 3B split, the 3A
recirc, the bigbag branch, and every `explicit_from_prev` pin. That includes
3B's two 15 m plasmaq legs.

## 2. The fix

### One implementation, used by the build and by the load

- **`macro_flow_edges(line_id, seq)`** returns the edges a SEQ declares, as
  `[src_index, tgt_index, recirc]` triples in stamping order. It holds all of
  the bookkeeping that used to run inside the build loop: CHAINED branches
  with recirc and sink close, PARALLEL siblings, `stream` trains,
  `explicit_from_prev`, the I1 role-none guard, and `GRAPH_TOPOLOGY_MACROS`.
  It reads the SEQ and nothing else, so a saved pose, an operator jog or a
  reload cannot change a line's topology.
- **`_stamp_macro_flow_edges(line_id, seq, nodes_by_idx)`** writes those
  triples onto nodes.
- **The build:** `_build_full_line` now only records which node landed at
  which SEQ index, then stamps once after the loop.
- **The load:** `_rederive_macro_flow_edges()` runs at the end of
  `load_layout`. It groups the loaded machines by `(macro_id,
  macro_instance)`, orders each group by `macro_index`, and stamps it with the
  same two functions. `last_macro_rederive` records what it did, one entry
  per group.

### `macro_instance`

This is a new meta: one id per `_build_full_line` call. It is saved and
restored with the other macro metas.

Two builds of the same line share every `(macro_id, macro_index)` pair. Before
this meta existed, a reload had no way to tell which silo belonged to which
band.

This is not hypothetical. On this machine, `__extruderwired__`, `__npc05real__`
and `__eventbus_tap__` each hold `line_3a` two or three times, and
`gauntlet_layout.json` holds 65 `line_3a` entries for 39 indices. The survey
in §6 shows what happens to them.

### Holes: a deleted machine

A machine that is missing from a loaded line is a **hole**, not an absent SEQ
entry. The rules:

- **Edges from a hole are dropped.**
- **Nothing is rewired around a hole.** For example, no `feeder → band` pin
  appears when the silo between them is deleted.
- **An edge to a hole is kept as a hole entry.** `_add_explicit_hole` writes
  `{"path": NodePath(), "missing_index": N}`. LineFlow never resolves an empty
  path, so the source stays an explicit source with no edge. It is a dead end.

The dead end is what a live delete already leaves. The pin still names the
freed machine, LineFlow cannot resolve it, and the source gets no edge at all:
no geometry fallback either.

The first version of this fix did something else. It dropped edges to holes,
so their sources went to the geometry fallback instead. That was changed after
measuring: on 3B the fallback hands the silo's booster blower its own
tussenventilator cyclone, which is the 2-cycle the pins exist to stop. It
would also have made a reload change the world. The suite now compares a
reloaded partial line against the live session after the same deletes (C4b,
C4c), and M7 in §5 shows that the first design fails that comparison.

"Absent" still means what the build loop always meant: an entry the catalog
cannot build (empty, retired or unknown id), decided by
`_macro_entry_absent`. For every catalog id in a SEQ, that equals
`build_node() == null`.

### Refusal: when the save cannot be matched to the SEQ

A group is **refused** when the save can't be matched to the SEQ with
certainty. A refused group gets nothing stamped, `push_warning` prints one
line, and the line keeps the geometry-only wiring it had before this fix. The
rule is that stamping a wrong pin is worse than stamping none: a wrong pin
defeats the fallback and the pin both. The load refuses in these cases:

- **Unknown `macro_id`.**
- **`macro_index` outside the SEQ.** The SEQ has shrunk since the save.
- **A machine whose id is not the SEQ's id at its index.** The SEQ changed
  since the save: an insertion shifts every later index, and an in-place id
  swap changes one. If a future SEQ edit swaps an id in place and the old id
  still builds, older saves of that line fall back to geometry. If the old id
  is retired, the load drops it and it becomes a hole instead.
- **Two machines at one index.** The save is from before `macro_instance`
  existed and holds two builds of the line.

A single legacy copy of a line, one with no `macro_instance`, is re-derived
normally (D3/D4).

## 3. The build path is unchanged (measured)

`src/tests/probe_macro_edges_dump.tscn` builds every macro once, on a floor,
and prints each `lf_explicit_outs` source with its targets in stamped order,
followed by every LineFlow edge. I ran it on the pre-fix `BuildMode.gd.bak`
and on the new code, and diffed the two outputs:

| | pre-fix | new |
|---|---|---|
| rows | 269 | 269 |
| explicit sources | 51 | 51 |
| LineFlow edges | 218 | 218 |
| nodes | 210 | 210 |
| `diff` | | **identical** |

## 4. The guard: `test_macro_edges_reload`, wired into `run.sh`

The suite is 60 checks in four phases. It writes only its own slot
(`user://__macroedgesrt___factory.json`). It sets
`WorldLayout.layout_path_override` and every `BuildMode.layout_path` before
the first boot, turns `load_shared_structure` and `allow_legacy_fallback` off,
and md5-checks 13 operator files before and after (LEAK GUARD, Z2). Operator
jogs in LineMacroStore's in-memory cache are blanked for the run and restored
afterwards; `user://macros` is never written.

- **A — round trip.** Every macro plus a second `line_3a`, built, saved and
  reloaded by a fresh BuildMode:
  - 241 of 241 machines saved, all with `macro_instance`.
  - Every group re-derived: `line_3c` "authored", the rest "stamped".
  - The explicit edges per source, in stamped order, are identical by name: 67
    edges from 59 sources.
  - LineFlow's whole edge set is identical by name: 255 edges over 247 nodes.
  - No edge crosses from one 3A build to the other.
  - `line_3c` carries no explicit edge before or after.
- **B — kg after the reload.** The silo chains of line 1, both 3A copies and
  3B are wired exactly by name. 23.7 kg fed at each feeder (950 kg/h for
  90 s, then 45 s to drain) arrives as 23.7-23.8 kg at the named extruder,
  and no chain machine processes more than was fed.
- **C — a partial line and an operator jog.** 3B's extruder is jogged 3 m down
  the line through LineMacroStore's cache. The C9 anti-vacuity check confirms
  the move: 12.50 m against 9.50 m from the const SEQ. Then BuildMode's own
  delete path removes three machines: 3B's `extruder_silo`, line 1's first
  L-stream blower, and 3A's rondmeng ring. After a reload:
  - The explicit edges are the full lines' 53 minus the 5 that touched a
    deleted machine: 48, exact.
  - The explicit state per source, dead ends included (44 sources), and
    LineFlow's whole edge set (116 edges) equal the live session's after the
    same deletes.
  - Nothing is rewired around a hole.
  - The L dryer and 3B's silo feeder stay dead ends.
  - The 3A recirc source still feeds the next main line.
  - The jogged extruder keeps its pin.
- **D — refusals.** One crafted save, three refusals, one acceptance:
  - Two 3A builds with no `macro_instance`: refused, "two machines at index 0".
  - A 3B entry whose id was changed to `mengsilo`: refused, "saved with an
    older SEQ".
  - A `line_sort` `macro_index` of 999: refused, "outside the 21-entry SEQ".
  - A refused line carries 0 edges.
  - Line 1 with no `macro_instance`, one copy, is re-derived with its 32
    edges.

Measured on the fixed tree: `Result: PASS (60 ok, 0 fail)`, 0 `^SCRIPT ERROR`
lines, 179 s wall.

### Two things the suite's first runs caught in the suite itself

- **The test world needs a floor.** Without one, each line's "achter"
  `lump_cart` (an unfrozen RigidBody3D) falls: y -0.65 m at the built world's
  LineFlow rebuild, -1.29 m at the reloaded one. The laser filter's geometry
  fallback then picks the other cart: 1.974 m against 2.007 m before the save,
  2.089 m against 2.007 m after. That is a void, not a save/load defect. The
  cart would not be a flow node at all if it were role-none, which a parallel
  session is changing.
- **`remove_child()` before `queue_free()` on a world** takes the extruder
  brains out of the tree while SimTick still ticks them for the rest of the
  frame. `ExtruderMachine._resolve_lazy_dependencies` then calls
  `get_tree()` on null: 60 SCRIPT ERROR lines. The suite now only calls
  `queue_free()`. Production's delete path does not trip this. That was
  checked with a throwaway probe: a built `line_3a`, then its `extruder_3a`
  deleted through `_edit_delete_selected`, printed 0 SCRIPT ERROR lines in
  the 30 frames after. Only a whole world taken out of the tree triggered it.

## 5. Mutation proofs

Each mutation was applied alone to the fixed `BuildMode.gd` (md5
`3282ad63…`). After every run the file was restored and md5-checked (all 9
restores OK). No run printed a `^SCRIPT ERROR` line. rc 139 is the documented
teardown segfault, which comes after the verdict.

| # | mutation | result | what goes red |
|---|---|---|---|
| BASE | the fixed tree | **PASS (60 ok, 0 fail)** | nothing |
| M0 | whole fix reverted (`BuildMode.gd.bak`) | 25 ok, **31 fail** | A2 A4 A5 A6 A11, B1-B5 on every chain, C3-C7, D1-D4 |
| M1 | the load never calls `_rederive_macro_flow_edges` | 29 ok, **31 fail** | A4 A6 A11, all of B's wiring and kg, C3-C7, D1-D4 |
| M2 | `_save_layout` drops `macro_instance` | 45 ok, **11 fail** | A2 A3 A4 A6 A11, B on 3A; the two 3A builds merge into one group of 78 and are refused |
| M3 | SKIP semantics: rewire around a hole | 55 ok, **5 fail** | C4 C4b C4c C5 C5b; the reload invents `mech_dryer L → cyclone L` |
| M4 | no id-vs-SEQ check | 58 ok, **2 fail** | D1 D2 3B; the stale 3B gets 11 pins |
| M5 | no duplicate-index check | 58 ok, **2 fail** | D1 D2 3A; the two legacy 3As get 10 pins |
| M6 | the build never stamps `macro_instance` | 45 ok, **11 fail** | same as M2 |
| M7 | an edge TO a hole is dropped (sources go to the geometry fallback, this fix's first design) | 57 ok, **3 fail** | C4b C4c C5b; the L dryer gets a geometry edge that the live session does not have |

M0 is also the before-picture, in kg. On the pre-fix tree, after a reload:

- `extruder_1`, `extruder_3a` and `extruder_3b` each receive **0.0 kg** of the
  23.7 kg fed.
- 3A's silo processes 243.5 kg: its 2-cycle with the band circulates the
  mass.
- The blowers on line 1 and 3B process 572.9 and 591.5 kg.

## 6. What the load does with the layouts on this machine today

`src/tests/probe_macro_rederive_survey.tscn` loaded **copies** of every
macro-bearing layout in the operator's `app_userdata`. The copies sat in a
scratch APPDATA, and nothing in the real folder was opened for writing.

| file | macro | result |
|---|---|---|
| `__jambaseline___factory.json` | line_3a 39/39 | **stamped**, 10 edges |
| `__outdoorroute___factory.json` | line_intake_3a3b 17/17 | **stamped**, 2 edges |
| | line_3a 42 | refused: index 13 is `mengsilo` in the save, `wind_sifter` in the SEQ |
| | line_sort 3 | refused: index 1 is `trilzeef` in the save, `shredder_1` in the SEQ |
| `sandbox_layout.json` | line_intake_3a3b 17/17 | **stamped**, 2 edges |
| | line_3a 33, line_sort 3, line_1 48 | refused: older SEQs (line 1: index 1 `shredder_1` vs `scrap_bin`) |
| `gauntlet_layout.json` | line_3a 65, line_sort 3, line_intake_3c6 4 | refused: older SEQs (3A index 5 `water_pump` vs `pomp_c1`) |
| `__extruderwired__`, `__npc05real__` (126), `__eventbus_tap__` (84) | line_3a | refused: index 13 `mengsilo` vs `wind_sifter` |

So most of these files were written with an older SEQ than today's, and the
load refuses them loudly. Each keeps exactly the geometry-only wiring it had
before this fix. The three duplicate-3A files would also fail the duplicate
check, but the id check fires first. The lines that do match their SEQ get
their pins back.

None of the operator's own saves holds a macro line (as §7 of the silo-tail
doc found), so his world does not change today.

## 7. Verification

All numbers below are from the fixed tree (`BuildMode.gd` md5 `3282ad63…`).

| step | result |
|---|---|
| parse sweep (scratch APPDATA) | `Result: 460 ok, 0 fail`, `RESULT: PASS` |
| `test_macro_edges_reload`, alone | `PASS (60 ok, 0 fail)`, 0 `^SCRIPT ERROR` |
| build path, pre-fix vs new (§3) | 269 rows, `diff` identical |
| `probe_explicit_edges_roundtrip` (the finding's own probe) | built 119 nodes / 121 edges / 47 tagged; **reloaded 119 / 121 / 47** (was 113 / 0). Every silo tail is wired by name after the reload |
| mutation matrix (§5) | BASE green, all 8 mutations red |

### Full harness

The harness ran 04:38 → 05:08 with `PROJ` set to this worktree. It used a
fresh copy of the operator's `app_userdata` as `APPDATA` (and as `UD`), so it
could not touch his files, and his `world_layout.json` was read from a copy
(md5 `e046af7d…`, identical to the real one). No other harness or game was
running when it started.

`== done (exit 1)`: **131 steps, 30 min, 124 logs by mtime, 0 timeouts.**
`^SCRIPT ERROR` lines: 131 in `parse_sweep.log`, which is its documented
compile-invocation noise (it gates on parse errors only), and 2 in
`route_goal_clearance.log`, the `--script` compile-before-autoload noise.
The same 2 are in every other worktree's run since 2026-09-24, and that suite
passes (15 ok). There are none anywhere else.

Inside the run:

- `test_macro_edges_reload`: PASS (60 ok).
- `test_extruder_silo_chain`: PASS (41 ok).
- `test_line_builder_ghost`: PASS (29 ok). This is the preview path, which
  still stamps nothing.
- `test_line1/3a/3b_flow_conformance`, `test_line1_twin_streams`,
  `test_macro_part_placement` and `test_macro_delta_guard`: all PASS.

**Reds: 5 steps.**

- `test_npc05_realworld`: expected.
- Four come from ONE cause, the jam-baseline fixture gate that leaked into
  the operator's `world_layout.json` on 2026-09-24. He chose to keep it
  (CLAUDE.md), so these are environmental:
  - `regression verdict`: 1 door off a wall.
  - `test_jam_baseline`: "structure_items untouched (1 entries)", 18 ok /
    1 fail.
  - `test_project_sweep_guards`: "B1b structure_items starts empty (1
    entries)".
  - `test_new_world_wipe`: "PlacedObjects EMPTY (child_count=1)". The boot log
    reads `Loaded 0 placed objects (per-save) + 1 shared structure`, and that
    one child is the gate.

**Why the four are not this change's.** CLAUDE.md names only the first two
as environmental. The other two have the same cause, and that was measured,
not reasoned. Three other worktrees WITHOUT this change show the identical
B1b and `child_count=1` reds on the same file:

- `mystifying-franklin` at 00:48,
- `cedo-sim-sound-processing` at 03:12,
- `wizardly-euclid` at 04:31.

The last runs where both passed (`ready-daacfa`, 16:13/16:19 on 2026-09-24)
came before the 17:15 leak.

### After merging `origin/main` (#289-#292)

`main` had moved on: #289 itself had been merged, plus the machine sounds
work. The only conflict was the scene loop in `run.sh`. It was resolved as
the union of both lists, and `main`'s list lost nothing. One suite came back:
`test_screw_die_plate_bar` was on this branch's loop but not on `main`'s. The
machine-sounds loop replacement dropped it, the same way it dropped the two
suites `c40b000` re-wired. It passed in the 04:38 harness above (36 ok).

On the merged tree, after an `--import` for `main`'s three new `class_name`s:

- parse sweep: `Result: 466 ok, 0 fail`;
- `test_macro_edges_reload`: `PASS (60 ok)`;
- `test_extruder_silo_chain`: `PASS (41 ok)`;
- both suites with 0 `^SCRIPT ERROR` lines.

### And again, on top of #293/#294 (the cycle-guard fix)

#294 landed on `main` while this was being pushed. It swaps LineFlow's
fallback cycle guard, pins 3A's infeed blower 2 to the big top cyclone, and
makes the lump furniture and the visible compressors role `none`. Its merge
into `main` had also dropped `test_machine_sounds` and `test_hmi_fault_rearm`
from the scene loop, the same loop-line drop as above. The loop was resolved
as the union again:

- nothing from `main`'s list is missing;
- `test_machine_sounds` and `test_hmi_fault_rearm` are restored;
- `test_macro_edges_reload` is added.

`test_hmi_fault_per_line` is not added: that re-wiring is another session's
held commit. CLAUDE.md's reload paragraph replaces the old "no pin survives a
reload" one, and #294's cycle-guard entry keeps its reload measurement, now
dated as before this fix.

Measured on that merged tree:

- The build path is still unchanged. `probe_macro_edges_dump` on `main`'s
  `BuildMode.gd` (which has #294's pins and the old in-loop bookkeeping) and
  on the merged one gives 243 rows each (52 explicit sources, 191 LineFlow
  edges, 188 nodes), and `diff` finds them **identical**.
- parse sweep: `Result: 467 ok, 0 fail`.
- `test_macro_edges_reload`: `PASS (60 ok)`. The round trip now carries 69
  explicit edges from 61 sources and 223 LineFlow edges, identical before and
  after the reload (#294's cyclone pin included).
- `test_extruder_silo_chain`: `PASS (41 ok)`.
- `test_fallback_chains`: `PASS (83 ok)`.
- All three suites: 0 `^SCRIPT ERROR` lines.

The full harness was NOT re-run on the merged tree; the operator runs it.

## 8. Not changed here

- **The live delete path.** It still leaves the dangling pin, and with it the
  dead end described in §2. The reload now reproduces that state; neither
  path rewires anything.
- **LineFlow's swapped cycle guard, and role-none furniture** (§5 of the
  silo-tail doc). Fixed in parallel by #294 and merged under this change (§7).
  `macro_flow_edges` reads `_is_flow_relevant` at run time, so a role-none
  `lump_cart` drops out of the build and the reload alike.
- **`save_macro_overrides`** still gathers siblings by `macro_id` alone. With
  two builds of one line in a world, it mixes them. That was true before this
  change and is not touched by it.
