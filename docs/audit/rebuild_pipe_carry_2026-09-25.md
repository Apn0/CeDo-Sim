# LineFlow.rebuild() kept the machines and dropped the belts (2026-09-25)

Found by reading the code on 2026-09-25, then measured, fixed and guarded the
same night. Branch `claude/inspiring-agnesi-adf606`, worktree
`wonderful-euclid-80a5da`, on `origin/main` `c1dabb7` (#322).

## 1. The defect

Every LineFlow connector is a delay line: `_edges[i]["pipe"]` is an Array of
`PIPE_STAGES` (6) `MaterialBatch` slots that shift forward one slot every
`stage_dt`, with the phase in `stage_t` (#145). The kg on those slots are part
of the ledger: `in_transit_mass()` adds `pipe_mass()`, and
`ledger_residual()` subtracts it.

`rebuild()` (#218) snapshots every node's `powered`, `spin`, `buffer`, `in`,
`out`, HMI settings and observer modules by `id @ scene path`, and puts them
back on the re-discovered node. The edges got nothing: `_link()` starts with
`_edges.clear()` and `_init_pipes()` gives every new edge fresh, empty
batches. So every rebuild deleted whatever was riding the connectors, and the
ledger was off by that much for the rest of the shift.

### When rebuild() runs (read from the code)

| caller | when |
|---|---|
| `BuildMode._place_current` | a whole-line macro placed; a flow-relevant placeable placed (both the single and the two-point path) |
| `BuildMode._delete_pointed`, `_edit_delete_selected` | a flow-relevant machine deleted |
| `BuildMode._edit_deselect` | a flow-relevant machine jogged in edit mode |
| `LineCouplerTool` | linking two machines, coupling machines to an HMI, auto-wiring (four call sites) |
| `MainWorld` | the first rebuild at boot (no edges yet) |

An HMI panel placed mid-shift does **not** rebuild any more:
`BuildMode._is_flow_relevant` returns false for every `hmi_` id and for the
observer fixtures (#218). The original report of this defect named that case;
the line coupler and the placements above are the real triggers.

## 2. Measured before the fix

`src/tests/probe_rebuild_pipes.tscn`, on `main` `c1dabb7`'s LineFlow: a bare
BuildMode builds line 3B, LineFlow rebuilds and starts the line, 20 kg go
into the extruder silo's `in` batch and 950 kg/h into the VSS for 60 s of
`tick(0.1)`. The extruders are unhooked from SimTick and stay off.

```
[A] rebuild with nothing changed
  before rebuild   nodes 25  edges 25  pipe_mass 13.3497 kg  in_transit 35.3997 kg  ledger_residual -35.8333 kg  (+injected 35.8333 = -0.000000)
  after rebuild    nodes 25  edges 25  pipe_mass 0.0000 kg  in_transit 22.0501 kg  ledger_residual -22.4836 kg  (+injected 35.8333 = 13.349692)
  LOST across the rebuild: pipe 13.3497 kg, ledger moved 13.3497 kg
  30 s later (no feed)   ...  (+injected 35.8333 = 13.349692)
```

16 of 25 edges carried kg (0.19 to 2.86 kg each; the longest, plasmaq →
cyclone, 2.65 kg on a 2.06 s stage). `ledger_residual()` does not count what a
test injects (`fed_mass` is the bale feed's counter), so the quantity that
balances is residual + injected: 0 before, 13.35 kg after, and still 13.35 kg
30 s later. The kg were gone, not late.

Deleting the compactorband the way BuildMode deletes (out of `placed_object`,
`remove_child`, `queue_free`, rebuild) dropped all 12.55 kg in the line's
connectors, not only the band's own two edges.

The same delete printed an engine error from `rebuild()`:

```
ERROR: Cannot get path of node as it is not in a scene tree.
       [0] rebuild (res://src/sim/LineFlow.gd:413)
```

BuildMode takes a deleted machine out of the tree before it rebuilds, and the
survivor key called `get_path()` on it. The call returns an empty path, so the
key became `id@` and matched nothing, and rebuild went on. It is an `ERROR:`
line, not a `SCRIPT ERROR`, so `script_error_census.sh` does not see it. With
the fix reverted to that key (mutation M5 below) the suite counts 3 of them.

## 3. The fix (`src/sim/LineFlow.gd`)

- `_survivor_key(nd)` is the one place the `id @ scene path` key is built.
  Both loops in `rebuild()` used to carry their own copy. A body that is freed
  **or out of the tree** gets `id # index`, so a deleted machine no longer
  calls `get_path()`.
- `_snapshot_pipes()` runs before `_discover()` replaces `_nodes` (the edges
  hold node indices): every LOADED edge's `pipe` Array and `stage_t`, keyed by
  both ends' survivor keys. An empty edge is not taken: it has no kg, and its
  phase describes no material, so it restarts at 0 like a new edge, and a
  rebuild of an idle line is exactly what it was before this fix. The first
  version carried empty phases too and turned `test_extruder_silo_feed_stop`
  red (§5.1).
- `_carry_pipes(old_pipes)` runs right after `_init_pipes()`:
  - **Both ends survived and the edge still exists**: the edge gets its old
    stages (the same `MaterialBatch` objects) and its `stage_t` back. The new
    `stage_dt` is kept, so a jogged machine's edge rides on at its new transit
    time. The tick's `while stage_t >= stage_dt` loop already handles a phase
    that exceeds a shorter new stage.
  - **The edge is gone, the source survived** (its target was deleted, or the
    linker picked another target): the kg go into the source's `out` batch.
    The next tick routes them down the source's edges as they are now.
  - **Only the target survived** (the source was deleted): the kg go into the
    target's `in` batch. They were already past the source's discharge.
  - **Neither end survived**: the kg are lost, together with the two machines'
    own `in`/`out` batches (see §6).
- `last_pipe_carry` reports `carried` / `to_source` / `to_target` / `lost` for
  the last rebuild, and rebuild prints one line when anything was re-homed or
  lost.

Measured after, same probe on the final code (the probe now switches LineFlow's
`_process` off after `add_child`, §5; its first "after" run did not, and read
13.3950 kg because the first version carried the phase of those frame ticks):

```
[A] rebuild with nothing changed
  before rebuild   ... pipe_mass 13.3497 kg  in_transit 35.3997 kg  ... (+injected 35.8333 = -0.000000)
  after rebuild    ... pipe_mass 13.3497 kg  in_transit 35.3997 kg  ... (+injected 35.8333 = -0.000000)
  LOST across the rebuild: pipe 0.0000 kg, ledger moved 0.0000 kg
  30 s later (no feed)  ... pipe_mass 4.5715 kg ... (+injected 35.8333 = -0.000000)
[B] delete the compactorband, then rebuild
  band holds 0.0000 kg (in+out), 1.8585 kg in the pipes leaving it, 0.3485 kg in the pipes into it
[LineFlow] rebuild: 0.348 kg from connectors that are gone went back into their source, 1.859 kg into their target, 0.000 kg left with both machines
  silo out 0.3485 kg after (was 0.0000); ledger moved -0.0000 kg; pipe fell 2.2070 kg
```

## 4. The guard: `test_rebuild_pipe_carry` (26 checks, in `run.sh`)

The same 3B line, with LineFlow's `_process` switched off after `add_child`
so only `tick(0.1)` moves material. A bare BuildMode never saves; nothing
writes `world_layout.json`.

| phase | what | checks |
|---|---|---|
| S0 | 60 s fed: kg in the connectors, the ledger balances | 13.35 kg over 16 edges; residual + injected 0 |
| A | a rebuild with nothing changed | A1 pipe_mass, A2 the ledger, A3 every edge's every stage (kg, volume, water, dirt, composition) identical and every loaded edge's `stage_t`, A4 `last_pipe_carry` all carried, A5 30 s on the ledger still balances, A6 every empty edge restarts at phase 0 (9 empty edges had a phase before) |
| E | line 3A placed 400 m away, rebuild (25 → 57 nodes) | E2 every 3B edge identical, E3 ledger and pipe_mass unchanged |
| F | the plasmaq moved 1.5 m, rebuild | F1 plasmaq → cyclone carries 2.65 kg and survives with a new `stage_dt` (2.059 → 2.076 s), F2 every edge's stages and phase identical, F3 ledger unchanged |
| B | one machine deleted BuildMode's way | the first 3B machine with one edge in and one out, both carrying kg (dewater_screw #8 every time; its edges carried 1.16 / 0.21 kg in / out in the first version's runs on an empty user://, 0.85 / 0.24 kg in the final run on the operator's copy). B1 the in-edge's kg are in the source's `out`, B2 the out-edge's kg in the target's `in`, B3 the ledger moved by exactly what the machine itself held, B4 reported, B5 no `Cannot get path` engine error (an engine `Logger`) |
| C | the rafter and the dewater screw after it deleted in one rebuild | C1 only the rafter → dewater kg (0.768) are lost; M11a and the friction separator get their edges' kg; C2 the ledger moved by exactly the two machines' kg plus that connector |
| Z | every phase reached its last line; 0 `SCRIPT ERROR` (engine `Logger`) | |

B picks its machine at run time because which edges hold kg at an instant
depends on each pipe's phase: the booster blower's in-edge was empty at that
instant in one run, and the compactorband's edges are empty once the PCU pot
is full (the extruder is off, so §I13's pot stop halts the silo's discharge).

### Mutation matrix

Each mutation applied to the final `LineFlow.gd` (md5 `f01b9082…`), the suite
run under the copy of the operator's `app_userdata`, and the file restored and
md5-checked after every run.

| # | mutation | result | red |
|---|---|---|---|
| M0 | `main`'s LineFlow.gd (`c1dabb7`) | FAIL 3 ok, 2 fail | Z phases A–C missing, Z 1 SCRIPT ERROR (`last_pipe_carry` does not exist, so A aborts) |
| M1 | no `_carry_pipes` call (main's behaviour, with the new report field) | FAIL 9 ok, 17 fail | A1–A5 (13.26 kg lost), E2 E3, F1–F3, B1–B4, C0–C2 |
| M2 | stages carried, `stage_t` not | FAIL 22 ok, 4 fail | A3, E2, F2, C0 |
| M3 | a gone edge's kg not put anywhere | FAIL 21 ok, 5 fail | B1 B2 B3, C1 C2 |
| M4 | only-the-target-survived counted as lost | FAIL 21 ok, 5 fail | B2 B3 B4, C1 C2 |
| M5 | survivor key without `is_inside_tree()` | FAIL 25 ok, 1 fail | B5 (3 `Cannot get path` errors) |
| M6 | edges matched by source only | FAIL 16 ok, 10 fail | A1 A2 A3 A5 (the 3B splitter friction_sep #9 → mech_dryer #10 / #11 loses one pipe), E2 E3, F2 F3, B3, C2 |
| M7 | empty edges carried too (this fix's first version) | FAIL 25 ok, 1 fail | A6 (the empty edges kept their phase) |

C0 is the anti-vacuity check before the double delete. It goes red under M1
and M2 because their runs diverge, and one of the three edges around the
rafter happens to be empty at that instant.

The final tree: `PASS (26 ok, 0 fail)`. The first version, with an empty
user://, passed its 25 checks twice with byte-identical check and info lines.
The absolute kg depend on the userdata and on nothing under test: S0 reads
13.3497 kg on an empty user:// and 13.2630 kg on the copy of the operator's,
for the fix, M1 and M7 alike. No line macro override is saved there; the
cause, probably a value in `settings.cfg`, was not traced.

## 5. A suite trap met on the way: `set_process(false)` before `add_child`

The first version of the suite called `_lf.set_process(false)` before
`add_child(_lf)`. S0 then read 13.3950 kg with the fix, 13.3497 kg under M1 and
12.8505 kg under M6: the phase before any rebuild depended on the code under
test. Godot 4 switches processing on at READY for a script that overrides
`_process` (the `set_process` docs: calls before `_ready()` are ignored), and
LineFlow's `_process` ticks on frame time. So LineFlow ticked in the awaited
frame between its own first rebuild and the suite's, and the fix carried that
frame's `stage_t` where M1 reset it. With the call after `add_child`, S0 reads
13.3497 kg under every variant. The probe in §2 was first run without any
`set_process(false)`, so it ticked in the same frame, and the fix carried that
frame's phase: that is why its first "after" run read 13.3950. It now switches
`_process` off after `add_child` too.

`src/tests/test_line_hud_overlay.gd:39` has the same order (not changed,
not measured; it tests the HUD label, not flow).

### 5.1 The same frame, in another suite: why an empty connector is not carried

Most suites that drive `tick()` themselves never switch LineFlow's `_process`
off at all. Counted by grep: 27 suites in `run.sh`'s loops make their own
LineFlow, call `rebuild()` and never call `set_process(false)`; besides this
suite's own, only `test_line1_metal_detect` switches it off. They add LineFlow (its
`_ready` rebuilds), await frames, then call `rebuild()` themselves. LineFlow
ticks on frame time in those frames with the line idle and the connectors
empty, so on `main` nothing of those ticks survived the explicit rebuild,
because every phase restarted at 0. The first version of this fix carried
every edge's `stage_t`, the phases of empty edges included, so those suites
began from whatever phase the awaited frames left.

`test_extruder_silo_feed_stop` went red on it. Measured, two runs each, on a
copy of the operator's `app_userdata`:

| LineFlow.gd | result | S3 "backlog waits in the VSS" |
|---|---|---|
| `main` (`c1dabb7`), run 1 | PASS 17 ok | VSS 63.5 kg; the stopped 3B screw's input 0.2 kg at the stop, 1.2 kg at the end |
| `main`, run 2 | PASS 17 ok | identical |
| fix, first version, run 1 | FAIL 16 ok, 1 fail | VSS 63.0 kg; 0.0 kg at the stop, 1.2 kg at the end (+1.2 against the check's < 1.0) |
| fix, first version, run 2 | FAIL 16 ok, 1 fail | identical |

Deterministic both ways: the shifted phases change when the kg already in
flight reach the stopped screw. On `main` the check passes by a hair
(0.2 → 1.2 kg against < 1.0 kg).

What should a rebuild do with the phase of an empty delay line? The phase only
decides when a parcel moves up one stage, so an empty line's phase says
nothing about material. Restarting it at 0 is exactly what a new edge does.
So `_snapshot_pipes()` now leaves empty edges out. A loaded edge still keeps
its phase, and that is what keeps its kg arriving on time. The guard pins
this down with A6: every edge that was empty restarts at 0, and at least one
of them had a phase before. Mutation M7 carries empty phases again.

The general cure is for those suites to drive LineFlow alone, calling
`set_process(false)` after `add_child`. That is a change to 27 suites, each
one to re-measure, so it is not done here (§6).

## 6. Not fixed, for the operator or a later session

- **Most suites that drive `tick()` still let LineFlow tick on frame time
  during their awaits** (§5.1). A suite that awaits between ticks mid-run is
  frame-rate dependent whatever this fix does. Found by reading, not measured
  per suite.

- **A deleted machine's own `in`/`out` kg leave the ledger** (measured in B
  and C: 0 kg for the pass-through machines deleted there, because they pass
  their input on within the tick; a VSS, a silo or a PCU pot holds kg between
  ticks). So does an edge whose two ends are both deleted in one rebuild
  (C: 0.768 kg). Deleting is a build-mode tool of the development phase, and
  whether a deletion should bank its contents somewhere (a floor pile, a
  "removed with machines" ledger term) is an operator call.
- **Read, not measured:** rebuild() does not carry a node's `thru`, `moist`,
  `contam` or `quality`. The resume-on-load work in progress in another
  worktree lists them in `RESUME_NODE_FIELDS`. `_estop_fault_node` is a node
  index and survives a rebuild that may renumber the nodes.
- The resume-on-load work (`src/sim/PlantResume.gd`,
  `LineFlow.node_run_state` / `restore_node_run_state`, uncommitted in
  worktree `unruffled-keller-219387` at the time of writing) saves each
  node's out-edges' pipes with the target's id. It works on a load, after the
  load's rebuild, and does not depend on this fix; the two touch different
  hunks of `rebuild()`.

## 7. Neighbouring suites, measured with the fix

One at a time, each under a scratch APPDATA on D: holding a copy of the
operator's `app_userdata` (not the harness; one runner runs that).

| suite | result |
|---|---|
| `test_rebuild_pipe_carry` | PASS 25 ok |
| `test_ghost_census` | PASS 11 ok |
| `test_macro_edges_reload` | PASS 62 ok |
| `test_fallback_chains` | PASS 110 ok |
| `test_flow_node_unique` | PASS 34 ok |
| `test_extruder_silo_chain` | PASS 41 ok |

All with 0 `SCRIPT ERROR` lines. The full-tree parse sweep's first run was
killed by this session's own 300 s timeout while other sessions' Godot runs
loaded the machine (it reached `test_qa_loop`). The two new scripts and
LineFlow.gd were then compiled alone, the way the sweep does
(`ResourceLoader.load(..., CACHE_MODE_IGNORE)` + `reload(true)`): err 0 each.

## 8. Files

- `src/sim/LineFlow.gd` — `_survivor_key`, `_snapshot_pipes`, `_carry_pipes`,
  `last_pipe_carry`; `rebuild()` calls them.
- `src/tests/test_rebuild_pipe_carry.{gd,tscn}` — the guard, wired into
  `run.sh`'s main loop.
- `src/tests/probe_rebuild_pipes.{gd,tscn}` — the before/after probe (prints
  only).
