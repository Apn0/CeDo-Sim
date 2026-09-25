# Every intake belt was two machines: the Model was a placeable too (2026-09-25)

Follow-up to `cycle_guard_swap_2026-09-25.md` §6, which found it with
`dump_line_graph` and left it unfixed: every BeltBuilder belt on
`line_intake_3a3b`, and the sort line's `switch_belt`, was a LineFlow node
twice. The intake graph had 30 nodes for 17 machines.

## 1. The mechanism

`PlaceableCatalog.build_node` makes the placeable: a body (usually a
`StaticBody3D`) that carries `placeable_id` and the group `placed_object`. It
then adds a plain `Node3D` named `Model` under the body and hands that Model
to `_build_model(model, …)`, which dispatches to one `_m_<id>` builder per
placeable. Everything an `_m_*` builder receives as `p` is that Model.

Four belt builders passed `p` to `BeltBuilder.build(p, …)` instead of
`BeltBuilder.build_internal(p, …)`:

| builder | ids |
|---|---|
| `_m_intake_belt` | `transportband_1` … `transportband_12`, `transportband_8_5` |
| `_m_switch_belt` | `switch_belt` |
| `_m_scraper_conveyor` | `scraper_conveyor` |
| `_m_compactor_belt` | `compactor_belt` |

`build()` runs `build_internal()` and then tags `p`: `apply_tagging` and
`placeable_id` + `placed_object` (`BeltBuilder.gd`, the block after step 4).
So the Model became a second placeable inside the first. The other four
migrated belts (`transport_belt`, `compactorband`, `inclined_belt_8m`,
`metal_belt`) call `build_internal()` and never had a twin, which is why
`inclined_belt_8m` was single on the same line.

The census (§4, check A2) found ten more builders doing the same thing by hand,
with `_finalize_placeable(p, id)` at their end: `_m_vacuum_unit`,
`_m_vacuum_pump`, `_m_hazard_decal` (six ids), `_m_overhead_crane`,
`_m_fire_riser`, `_m_fire_extinguisher`, `_m_drainage_grating`,
`_m_scissor_lift`, `_m_riveted_steel_column` and `_m_concrete_v_beam`. That
makes **31 catalog ids** whose Model was `placed_object`. None of the ten is
on a macro, so no dump showed them. `_m_vacuum_unit` and `_m_vacuum_pump`
did it without an `if not ghost` guard, so their placement ghosts were
`placed_object` as well.

A save never held a twin: `BuildMode._save_layout` walks the direct children
of `_placed_root`, and the Model is a grandchild. But `build_node` made the
twin again on every load (check B, "reloaded").

## 2. What the twin did

Measured unless marked.

- **LineFlow.** `_discover` takes every `placed_object` with a
  `placeable_id` and a flow role. The twin sat at the body's own win / wout
  and had no `macro_index`. It had no in-edge, so LineFlow treated it as a
  feed **head** (it draws a bale at its feed point when feed is on), and its
  out-edge fed the next belt a second time. On the intake line the body of
  `switch_belt[m16]` had one out-edge, to its own twin, and the twin had
  none: in the standalone macro, every kg reaching the switch belt went into
  a node with no way out.
- **The film bed.** Both nodes found the same `FilmFlakeField` under the
  Model, and LineFlow drives each node's fields once per tick. The twin came
  after the body in discovery order and drove the bed toward 0 kg/s every
  tick. With 950 kg/h fed at the intake head for 90 s, **all 12 carrying
  intake belts read a bed of 0.000 kg/m** (mean of the last 30 s), against
  0.216–0.420 kg/m from their own flow.
- **Two controllers on one deck.** `SwitchBelt.attach_to` and
  `Conveyor8.attach_to` are called per LineFlow node. The twin added a second
  `_SwitchBeltCtrl` (under the Model, finding the same `Deck` by search) and a
  second `_Conveyor8Ctrl`. Counted: 2 on both switch belts and on C8.
- **K-mode.** `BuildMode._delete_pointed`, `_pointed_placed_object` and
  `_try_pole_snap` walk up from the hit collider to the **first**
  `placed_object`. On six ids a collider sits under the Model: the vacuum
  unit's two cabinet doors plus one `StaticBody3D`, the vacuum pump's drain
  cock, the crane's pendant, the fire riser's test valve, the extinguisher's
  lever and the scissor lift's control. Measured: those 8 colliders resolved
  to the Model.
  By reading `_delete_pointed` (not driven): a K-delete aimed at one of them
  frees the Model, leaves the body and its box collider standing, and
  `_save_layout` then saves the body, so the machine comes back on reload. No
  belt has a collider under its Model, so on the belts K-mode was not
  affected.
- **Not measured, by reading only:** `BuildMode`'s snap scan computes faces
  from `n3.rotation.y`, which on a Model is its local 0, so every twin added
  four snap faces at the wrong yaw; `InspectMode` counted each twin as an
  object; `NpcAutonomyBoard._station_pos` can return either node (same
  position).
- **Seen, cause not measured:** with the twins, the mean `thru` over the same
  window on `transportband_9/10/11` read 0.51 / 0.58 / 0.63 kg/s. Without them
  it reads 0.33 / 0.34 / 0.45.

## 3. The fix

- The four belt builders call `BeltBuilder.build_internal(p, …)`. Their body
  is already tagged by `build_node`: the 'belt' group, `belt_speed`,
  `belt_ramp_tau_s` and `BeltSurface` for the intake belts, the switch belt
  and `scraper_conveyor` (`_BELT_IDS`). `compactor_belt` has never been a
  carrying belt. Carry physics lives on the body. The Model is a plain
  `Node3D`, so `apply_tagging` never attached `BeltSurface` to it. What
  `build()` added to the Model and is now gone:
  - `scraper_conveyor`'s Model in 'belt' with `belt_speed` / `safe_zone_m` /
    `spread_zone_m` metas. `BeltSurface` reads those metas from its own body.
    `PlayerController` checks the hit collider's group. `BezinkTank` calls
    `current_belt_speed_mps`, which a Model does not have. Nothing read them.
  - `scraper_conveyor`'s `spec.tag_as_belt = true` only fed `build()`'s
    tagging, so it was removed.
- The ten inner `_finalize_placeable(p, …)` calls are removed. Every
  function still uses its `ghost` / `id` parameters (lint: 0 unused).
- Doc comments on `_finalize_placeable` and `BeltBuilder.build` say which
  node they may tag.

`LineFlow` is **not** changed. A dedupe in `_discover` would have hidden the
twins from LineFlow alone and left the snap scan, K-mode and the controllers
as they were. It would also have made the LineFlow-level guard pass on a
catalog that still tags its Models.

## 4. Measurements

`dump_line_graph.tscn -- <line>`, before (`dd5c4af`) and after, under a
scratch APPDATA:

| line | nodes | edges | NOIN (heads) | `[m-1]` nodes |
|---|---|---|---|---|
| `line_intake_3a3b` before | 30 | 30 | 15 | 13 |
| `line_intake_3a3b` after | **17** | 16 | **3** — `opzetband_3a3b`, `shredder_2`, `u_bay` | 0 |
| `line_sort` before | 20 | 20 | 9 | 1 |
| `line_sort` after | **19** | 18 | 8 | 0 |

Every edge the diff removes has a twin at one end, and it adds none. On the
intake line `switch_belt[m16]` is now NOOUT: its targets are the VSS silos,
which are on the 3A / 3B macros, not in this one. On the sort line the twin's
two edges (to `inclined_belt_8m[m9]` and `transport_belt[m17]`) are gone.
The real switch belt keeps its one explicit edge to `[m9]`. The twin never
carried a kg along its edges, because it had no in-edge.

`test_flow_node_unique`, before → after:

| check | before | after |
|---|---|---|
| A2 catalog ids with a second `placed_object` | 31 of 200 | 0 of 200 |
| A3 colliders resolving to a non-root in K-mode's walk | 8 (6 ids) of 842 | 0 of 842 |
| A4 LineFlow nodes over the whole catalog | 176 for 145 flow roots | 145 for 145 |
| B seven macros, fresh and reloaded | 188 nodes, 14 twins | 174, 0 |
| C1/C2 controllers per switch belt / C8 | 2 / 2 / 2 | 1 / 1 / 1 |
| C3c intake beds carrying their own flow | 0 of 12 (0.000 kg/m) | 12 of 12 (86–98 %) |

B4 (per line, flow nodes = discoverable macro roots, one per slot) was
already green before the fix. The twin carries no `macro_id`, so B3 is what
sees it. B4 is there for the other kind of duplicate (mutation M4 below).

## 5. Guard: `test_flow_node_unique`, wired into `run.sh`

34 checks. Parts:

- **A:** every catalog placeable is built through `build_node` and kept in
  the tree together, with one LineFlow over all of them.
- **B:** the seven macros in one world, freshly built and again after a
  `_save_layout` / load round trip.
- **C:** the controllers and the fed intake beds.

The BuildMode writes only its own slot file. `load_shared_structure` is false,
so it never writes `world_layout.json`.

| mutation | result |
|---|---|
| M1 `_m_intake_belt` back to `BeltBuilder.build` | 24 ok, **10 fail**: A2, A4, B1–B3 fresh and reloaded, C2, C3c |
| M2 `_m_switch_belt` back to `build` | 24 ok, **10 fail**: A2, A4, B1–B3 ×2, C1 on both lines |
| M3 `_m_vacuum_pump` finalizing its Model again | 31 ok, **3 fail**: A2, A3, A4 |
| M4 `LineFlow._discover` visiting `transportband_5` twice | 26 ok, **8 fail**: A4, B1 (same Node3D), B2, B4 ×2, C3c |

Each run was under a scratch APPDATA with 0 `SCRIPT ERROR` lines, and each
source file was restored and md5-checked against the fixed copy afterwards.

Parse sweep after the fix: `Result: 465 ok, 0 fail`. Unused-parameter lint:
0.

## 6. Found on the way, not fixed here

- **A shredder ghost is `placed_object`.** `ShredderMachine._ready` adds
  itself to the group unconditionally, and `build_node` sets `placeable_id`
  on the body before it knows about ghosts. Measured: `build_node("shredder_1"
  / "shredder_2", true)` in the tree is `placed_object`. Not measured: whether
  BuildMode rebuilds LineFlow while a shredder ghost exists. If it does, the
  placement preview becomes a flow node at the cursor. The suite leaves
  ghosts out for this reason.
- **The opzetband skips its shredder on both 3A3B feed macros.** After the
  fix, on `line_intake_3a3b` the geometry fallback wires `opzetband_3a3b →
  inclined_belt_8m`, and `shredder_2` has no in-edge. On `line_sort` it wires
  `opzetband_3a3b → bunker`, and `shredder_1` has no in-edge. So fed film
  bypasses shredding. That is why `test_fallback_chains` H still leaves those
  two macros out: their remaining heads are not the plant's heads either.
  The sort line was re-wired the same day in a parallel session (#306,
  `test_sort_line_topology`, `sort_line_topology_2026-09-25.md`). With both
  fixes merged, `line_sort` dumps as 17 nodes and 17 edges, and its only head
  is `opzetband_3a3b[m0]`. The intake macro is unchanged: 17 nodes, with
  `opzetband_3a3b`, `shredder_2` and `u_bay` as heads. It is still open.
  **Fixed the same day** in `intake_3a3b_topology_2026-09-25.md`: entry 0 is a
  plain belt pinned into shredder 2, and C8 / C8.5 / U-bay run on an
  `overflow` stream. The only head is entry 0.
- **The intake switch belt in a real world.** Before the fix, the switch belt
  fed its twin: that inlet was the belt's own, 3.6 m from its outlet. In a
  world that also holds the VSS silos, the linker would have picked whichever
  inlet was nearer. That was not measured: the operator's `app_userdata`
  holds no save with an intake line (the only one is a test residue,
  `__outdoorroute___factory.json`).

## 7. Full harness

`bash tools/regression/run.sh` ran on this worktree: `dd5c4af` plus this
change, uncommitted. `PROJ=` was set, and `APPDATA` / `UD` pointed at a scratch
copy of the operator's `app_userdata` (`world_layout.json` md5 `e046af7d…`,
the same as his). No other harness was running.

Result: `== done (exit 1)`, 134 steps, 31 min (06:45:31 → 07:16:08), 125 logs
by mtime, 0 timeouts. The sentinel reported "untouched by every step". There
were **5 reds, all known before this change**:

- **Four from the leaked jam-baseline gate in his `world_layout.json`**
  (CLAUDE.md, the 2026-09-24/25 notes):
  - `regression verdict`: "all 1 door(s)/gate(s) sit on a wall"
  - `test_jam_baseline`: "structure_items untouched (1 entries)", 18 ok / 1
    fail / 0 skipped
  - `test_project_sweep_guards` B1b
  - `test_new_world_wipe`: PlacedObjects child_count=1
- **`test_npc05_realworld`**: expected; the chain does not complete.

Inside the run:

| suite | result |
|---|---|
| `test_flow_node_unique` | 34 ok |
| `test_fallback_chains` | 83 ok |
| `test_belt_film_field` | 142 ok (it builds `_m_intake_belt` / `_m_switch_belt` on a bare node) |

`^SCRIPT ERROR` lines appear in two logs, and neither is a failure:

- `parse_sweep.log`: the non-gated `ERR_COMPILATION_FAILED` noise its header
  describes.
- `route_goal_clearance.log`: `Identifier not found: EventBus` in `--script`
  mode, then `Result: PASS`. The operator checkout's log of 2026-09-22 has
  the same two lines.

The operator's real `world_layout.json` kept md5 `e046af7d…`.

**Again on the merged tree** (this branch + `origin/main` `6692816`, with
#306's sort-line re-wire), `62a455a`: `== done (exit 1)`, 141 steps, 33 min
(12:13:23 → 12:46:42), 132 logs by mtime, 0 timeouts, and the sentinel
reported "untouched by every step". There was **1 red,
`test_npc05_realworld`** (expected). The four gate reds are green on this tree
because main reworded those checks: `test_jam_baseline` now reads "leaves
structure_items as it was", and B1b reads "holds no wall". This change did
not do that. Inside the run:

| suite | result |
|---|---|
| `test_flow_node_unique` | 34 ok |
| `test_sort_line_topology` | 97 ok (twin NOTE 0) |
| `test_fallback_chains` | 83 ok |

The same two logs carry the pre-existing `^SCRIPT ERROR` noise as above.
