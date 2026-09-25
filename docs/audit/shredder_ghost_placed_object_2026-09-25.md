# A shredder placement ghost was a placed_object (2026-09-25)

Follow-up to `flow_node_twins_2026-09-25.md` §6, which found it and left it
unfixed. `PlaceableCatalog.build_node("shredder_1" / "shredder_2", true)`,
the placement ghost, is in group `placed_object` once it has been in the tree
for a frame.

## 1. The mechanism

- `build_node` picks the body by id before it looks at the ghost flag. For
  both shredder ids the body is `src/sim/ShredderMachine.gd`, even for a ghost.
- It sets meta `placeable_id` on that body unconditionally
  (`body.set_meta("placeable_id", id)`, right after the body switch).
- It adds `placed_object` only in its `if not ghost:` block. That is the
  catalog's ghost contract, and BuildMode's snap scan relies on it in a
  comment ("The ghost … is NOT in this group — build_node(id, true)
  intentionally skips the group for ghosts").
- `ShredderMachine._ready` ran `add_to_group("placed_object")`. A script on
  the body cannot tell a ghost from a machine, so every shredder ghost joined
  the group the moment it entered the tree.

`LineFlow._discover`, K-mode (`_delete_pointed`, `_pointed_placed_object`,
`_try_pole_snap`), `InspectMode`, `NpcAutonomyBoard` and `ContainerGuide` all
iterate that group.

## 2. Did it reach LineFlow? Measured

`src/tests/probe_shredder_ghost_flow.tscn`, under a scratch APPDATA, before
the fix.

**P1, BuildMode's own continuous placement.** `_enter_placing(id)` spawned
the ghost. Then `_place_current()` ran twice per id: it builds the machine,
saves and calls `line_flow.rebuild()`, and the ghost stays at the cursor.

| | shredder_1 | shredder_2 |
|---|---|---|
| ghost script / `placed_object` | none / false | none / false |
| rebuilds with the ghost alive | 2 of 2 | 2 of 2 |
| LineFlow nodes after each rebuild | 1, 2 | 3, 4 (one per placed machine) |
| LineFlow nodes that are the ghost or lie under it | 0, 0 | 0, 0 |

So BuildMode does rebuild LineFlow while a shredder ghost exists, on every
placement. The ghost is still never a flow node, because `_spawn_ghost` runs
`_make_preview_inert(_ghost)` **before** `add_child` (added 2026-09-06). That
strips the script, so `ShredderMachine._ready` never runs on this ghost. The
only groups left on it are the four `machine_leg` markers.
`test_line_builder_ghost` §6 already asserted that for `shredder_1`.

**P2, the raw catalog ghost.** `build_node(id, true)`, parented, two frames,
one LineFlow rebuild:

| | shredder_1 | shredder_2 |
|---|---|---|
| before `add_child` | script ShredderMachine.gd, `placed_object` false, `placeable_id` set | same |
| after two frames | `placed_object` **true**, also in `shredder` | same |
| LineFlow | **1 node**, the ghost, `in=[] out=[]` | same |

A node with no in-edge is a feed **head** to LineFlow, which draws a bale at
its feed point when feed is on.

**Who builds a raw ghost.** `grep -rnE 'build_node\([^)]*,\s*true'` outside
`src/tests/` finds three sites:

- `BuildMode._spawn_ghost` (single item): sanitised, P1 above.
- `BuildMode._make_line_ghost_node` (whole-line preview):
  `_build_full_line(…, preview = true)` runs `_make_preview_inert` on the
  unparented root before `_spawn_ghost` parents it.
- `ContainerGuide._build` (`src/scenes/world/ContainerGuide.gd`): parents the
  ghost, then strips `placed_object`, `waste_container` and four more groups.
  It only builds container ids, never a shredder.

So no production path put a shredder ghost into LineFlow. The break was in
the catalog's contract, and a new caller of `build_node(id, true)` without
the sanitiser would have got a flow node at the cursor.

## 3. The fix

`ShredderMachine._ready` no longer adds itself to `placed_object`. It keeps
`add_to_group("shredder")` (build_node does not add that one, and three
readers need it, §5). A comment at the removed line says why.

Why this is not a change for real shredders:

- `build_node(id, false)` adds `placed_object` in its `if not ghost:` block,
  at construction, before the body ever enters the tree. For a real shredder
  the `_ready` self-add was a no-op.
- `grep -rnE 'ShredderMachine\.gd|ShredderMachine\.new'` finds one site that
  instantiates the script: `PlaceableCatalog.gd`, the body switch. No bench or
  spawner builds it directly. `LegacyPropsSpawner` builds its own shredder
  node and tags it `shredder` itself.
- `_ready` runs once per node. The two delete paths that remove the group
  (`BuildMode._delete_pointed` and the K-mode delete) free the node, so no
  node leaves the group and relies on `_ready` to put it back.

Measured after, in `test_ghost_census` R: a real `shredder_1` / `shredder_2`
is `placed_object` and `shredder`, reads rated 4500 / 2200 kg/h from its
`_ready`, and is a LineFlow node. The suites that drive the real machine are
green on a scratch copy of the operator's `app_userdata` (0 `SCRIPT ERROR`):

| suite | result |
|---|---|
| `test_shredder_machine` | PASS |
| `test_shredder_rate_reconciliation` | PASS |
| `test_bunker_shredder2_interlock` | PASS |
| `test_bunker_relay_trip` | PASS |
| `test_feeder_sequence` | PASS |
| `test_line_builder_ghost` | 31 ok |
| `test_flow_node_unique` | 34 ok |

Comments updated to match: BuildMode's snap scan and `_spawn_ghost`, and the
header of `test_flow_node_unique`, which said ghosts were left out because of
this defect.

Not chosen: giving a ghost no ShredderMachine body at all
(`elif (id == "shredder_1" or …) and not ghost`). That also ends the `shredder`
membership (§5), but leaves a second place that tags `placed_object`. The
census now guards the contract for every id, whichever way a later change
breaks it.

## 4. Guard: `test_ghost_census`, wired into `run.sh`

11 checks, a sibling of `test_flow_node_unique`:

- **G0**: the census builds 200 ghosts. Among them are the nine scripted
  bodies (the two shredders, `laser_filter`, `kopfilter`, `lump_cart`,
  `waste_container`, `scrap_bin`, `wardrobe_locker`, `silo_level_sensor`) and
  the 12 HMI panels (Hmi.gd bodies). Every root `is_node_ready()`.
- **G1**: no node inside any ghost is `placed_object`.
- **G2**: one LineFlow over all of them has 0 nodes.
- **R1 / R2**: two real shredders in the same scene keep `placed_object`,
  `shredder` and their rated capacity. The same LineFlow then has exactly 2
  nodes, both of them real (the positive control for G2).
- **P1 ×4**: BuildMode's continuous placement, as in §2 P1. The ghost is alive
  across each rebuild, there is one node per placed machine, and none is the
  ghost.
- **Z**: the slot file is gone.

The BuildMode writes only `user://__ghostcensus_factory.json`
(`load_shared_structure = false`), so never `world_layout.json`.

Before the fix: `8 ok, 3 fail`. G1 lists `shredder_1: .` and `shredder_2: .`,
G2 finds 2 nodes, and R2 sees 4 nodes for 2 real shredders. After: `11 ok,
0 fail`, 0 `SCRIPT ERROR`.

Mutations, each on its own, under a scratch APPDATA. After each run the three
source files were restored and md5-checked against the fixed copies.

| mutation | result |
|---|---|
| M1 `ShredderMachine._ready` adds `placed_object` again (the old code) | 8 ok, **3 fail**: G1, G2, R2 |
| M2 `build_node` tags the generic body `placed_object` regardless of ghost | 8 ok, **3 fail**: G1 (167 of 200 ghosts), G2 (127 nodes), R2 |
| M3 `zone_collection`'s early return finalizes its ghost (`and not ghost` dropped) | 8 ok, **3 fail**: G1, G2, R2 (one id) |
| M4 `_spawn_ghost` without `_make_preview_inert`, fix in place | 11 ok, green |
| M5 M4 **and** M1: no sanitiser, old self-add | 4 ok, **7 fail**: G1, G2, R2, all four P1 |

M4 stays green on purpose. With the fix, the placement ghost is not a flow
node even unsanitised, so each layer holds on its own. M5 is the scenario
§6 of the twins doc asked about: had BuildMode not stripped the script, every
placement rebuild would have added the ghost as a flow node (2 nodes for 1
placed, then 3 for 2, …).

`test_flow_node_unique`'s census was not extended. It builds real placeables
and takes minutes (seven macros, a 90 s feed). The ghost census takes seconds
and fails on its own.

## 5. Found, not fixed: raw ghosts join their OWN behaviour groups

`test_ghost_census` prints, without gating, every group a raw ghost joins
apart from the markers `machine_leg` / `machine_foot` / `steam_plume`.
Measured after the fix:

| ghost | group | production readers (`grep` for the group name) |
|---|---|---|
| `shredder_1`, `shredder_2` | `shredder` | `Hmi._find_scoped_shredder` (binds the relay panel), `CrewManager` (line start calls `start()`), `ShredderFeedBelt` (nearest shredder in reach) |
| `lump_cart` | `lump_cart` | `LaserFilter`, `MeltBlock`, `NpcAutonomyBoard`, `BuildMode` |
| `waste_container`, `skip_steel`, `fines_bin`, `cyclone_bin`, `ibc_tote` | `waste_container` | `LineFlow`, `NpcAutonomyBoard`, `BaseVehicle`, `ShredderFeedBelt`, `MetalScrap`, `MeltBlock`, `ShovelFloorPileTask` |
| `laser_filter` | `laser_filter` | `ExtruderMachine`, `HmiOverlay`, `BuildMode` |
| `kopfilter` | `kopfilter`, `head_filter` | `ExtruderMachine` (`head_filter`) |
| `silo_level_sensor` | `silo_level_sensor` | `LineFlow`, `PlaceableCatalog` |
| `scrap_bin` | `scrap_bin` | `MetalScrap` |
| `wardrobe_locker` | `wardrobe_locker` | none |
| 12 `hmi_*` panels | `hmi` | `StaticMerge`, `MapOverlay`, `LineCouplerTool` |

This does not reach a running game today, by the same reasoning as §2:
BuildMode strips the scripts before `_ready`, and ContainerGuide strips
`waste_container` and five more groups after it. It is the same latent hazard
for the next caller of `build_node(id, true)`. For example, a shredder ghost
within `ShredderFeedBelt`'s reach would be taken as that opzetband's shredder.

Two ways to close it, not done here because neither was asked for:

- Give a ghost no scripted body in `build_node`: a ghost is a picture.
- Move `_make_preview_inert` into the catalog, so every ghost comes back
  sanitised.

Either one needs its own census check (G1 widened to these groups), with this
table as its "before".

## 6. Full harness

`bash tools/regression/run.sh` ran on this worktree at `fa4d99a`: `origin/main`
`a4b2031` (#307) plus this change, committed. `PROJ=` was set, and
`APPDATA` / `UD` pointed at a scratch copy of the operator's `app_userdata`.
The copy left out `EBWebView/` and `api_keys.cfg`, and its `world_layout.json`
had md5 `e046af7d…`, the same as his. No other harness was running.

Result: `== done (exit 1)`, 142 steps, 31 min (13:07:35 → 13:38:20), 133 logs
by mtime, 0 timeouts. The sentinel reported "untouched by every step". There
was **1 red, `test_npc05_realworld`** (expected: "the chain completed" fails,
10 ok / 1 fail).

Inside the run:

| suite | result |
|---|---|
| `test_ghost_census` | 11 ok |
| `test_flow_node_unique` | 34 ok |
| `test_line_builder_ghost` | 31 ok |
| `test_sort_line_topology` | 97 ok |
| `test_fallback_chains` | 83 ok |
| `test_jam_baseline` | 19 ok, 0 skipped |
| `test_nav_connectivity` | 12 ok |
| `test_shredder_machine` | PASS |
| `test_shredder_rate_reconciliation` | PASS |
| parse sweep | 472 ok, 0 fail |
| `regression verdict` (`last_run.log`) | 20 ok, 0 fail, 1 skip |

`^SCRIPT ERROR` lines appear in two logs, and neither is a failure. They are
the same two as in `flow_node_twins_2026-09-25.md` §7:

- `parse_sweep.log`: the non-gated `ERR_COMPILATION_FAILED` noise its header
  describes.
- `route_goal_clearance.log`: `Identifier not found: EventBus` in `--script`
  mode, then `Result: PASS`.

The operator's real `world_layout.json` kept md5 `e046af7d…`, and its mtime
(06:24) is older than the run.
