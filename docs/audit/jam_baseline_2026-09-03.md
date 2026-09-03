# 2026-09-03 — test_jam_baseline: the green was vacuous, the red is real

**TL;DR.** `test_jam_baseline` did not regress. Three of its fourteen checks sit
behind `_route_exists()`, and while the model carved no doorway the router would
accept, those three were **skipped** — silently, because the suite printed
`Result: PASS (11 ok, 0 fail)` and counted no skips. The 2026-08-30 green
measured a world with nowhere to drive. `10d9ed4` ("Fix dual-skin wall carve")
reached `main` on 2026-08-31 02:34 inside the 61-commit wave, finally punched
the operator's one gate through both wall skins, the router started returning
6–7 point routes, the escape hatch closed, and three checks ran for the first
time — and failed. **Nothing about the driving got worse on 2026-08-31. The
harness stopped hiding what it had never measured.**

The previously named suspects — `d059007` (maalmolen 70 → 207 parts) and
`1ece58a` (stair move) — are **cleared**.

## The three failures, and why exactly three

```
FAIL : jam1_yard_to_plant completed (outcome 'stalled')
FAIL : jam3_indoor_to_outdoor completed (outcome 'stalled')
FAIL : the forklift reached the outdoor skip pose (57.34 m, limit 3.5)
Result: FAIL (11 ok, 3 fail)
```

Those are **exactly** the three checks the suite gates behind a route existing:
`_route_exists()` at `test_jam_baseline.gd:398` (`npc_route_points() > 0`),
guarding the sites at `:320` and `:411`. 11 ok + 3 = the fourteen checks that
the 2026-08-30 "11 ok, 0 fail" green also had. That green was this same suite
with three checks missing and no arithmetic anywhere to notice.

## Proof: one variable, two runs

Identical code (`main` `d0f7e32`, clean worktree), identical isolated `user://`
clone, the only difference being `world_layout.json`:

| run | `structure_items` | verdict | the legs |
|---|---|---|---|
| A | the one `"3A/3B gate"` | **FAIL (11 ok, 3 fail)** | `path 7 pts` / `path 6 pts` → checks run |
| B | `[]` | **PASS (11 ok, 0 fail)** | `path 0 pts` → `BLOCKED … no doorways in the model` → checks skipped |

Run B's own log is the confession:

```
trace : jam1_yard_to_plant: stalled after 76.5 s — 101.05 m from target, path 0 pts
BLOCKED: jam1_yard_to_plant — no vehicle route to the target (no doorways in the model);
```

The forklift stalled **101 m from its target and the suite passed.**

## The trigger, attributed first-hand

* `10d9ed4` (2026-08-29 07:53) — "Fix dual-skin wall carve". It splits the
  coplanarity tolerance: `WallOpenings.gd` gains
  `_coplanar_tol = WALL_THICK if solidify_enabled else _CLOSED_SHELL_COPLANAR_TOL`
  (0.05 m → 0.35 m on the live solid shell), the `#GATECARVE` fix. Its own
  commit message records the measurement behind it — skin z-offsets `+0.0046`
  and `-0.2954`, taken "near the operator's 3A_3B gate".
* It reached `main` **only** via merge `98d2cf4` (PR #168) at
  **2026-08-31 02:34:01**, inside the wave.
* `main`'s tip at the 2026-08-30 green measurement was `d459ad0`
  (2026-08-30 15:48:43), and
  `git merge-base --is-ancestor 10d9ed4 d459ad0` → **NO**. The green was
  measured before the carve fix was on `main`.
* Across the whole wave, `git log --no-merges d459ad0..d0f7e32 --` over
  `WallOpenings.gd`, `BuildMode.gd`, `BuildingShellLoader.gd`,
  `src/scenes/vehicles/` and `MainWorld.gd` returns **exactly one commit**:
  `10d9ed4`. No other production commit in the wave touched the shell, the
  carve, or vehicle routing — which is why the maalmolen commits are cleared:
  they add colliders *inside* the plant, not on the facade.

The gate is a **precondition, not the trigger**. It is operator in-game data
(`git log --all -S"3A/3B gate"` returns no commits), absent from the
2026-08-17 `world_layout.json` backup, present in the 2026-08-31 05:30 one, and
already being measured against by `10d9ed4` on 2026-08-29 — so it existed
during the green run.

## The gate leaf is a ghost — the parked WIP's premise was right

Measured at `main` `d0f7e32` with `probe_gate_navsource.gd`:

```
gate  : '3A_3B gate' pos=(-246.377, -6.514, 155.982)
        groups=["placed_object", "gate", "navmesh_source"]  is StaticBody3D=true
        SHAPE OWNERS=0  TOTAL SHAPES=0
        ray along (1,0,0)  hit 'NOTHING'
        ray along (0,0,-1) hit 'NOTHING'
```

A **closed** gate registered no collision at all. `build_gate` parents the
leaf's `CollisionShape3D` to `LeafScaler`, a plain `Node3D`
(`PlaceableCatalog.gd:10106` on `main`) — the only one of **17**
`add_child(col)` sites in that file that does not parent to a
`CollisionObject3D`. `build_door` does it correctly 52 lines earlier at
`:10054`. Godot registers a `CollisionShape3D` with its **parent**, not with its
nearest ancestor body, so the leaf was never a collider.

`wip/gate-carve` was right about that and wrong about its consequence: it
claimed the ghost leaf "is how test_jam_baseline went red". A ghost cannot stop
a forklift. Its cited evidence,
`docs/audit/jam_baseline_bisect_2026-08-31.md`, exists in no ref — it was never
written. This document is the measurement that was missing.

## A second bug, found because the first one was fixed

Giving the leaf collision immediately failed the WIP's own new check, "the
CLOSED leaf physically blocks the opening centre". The WIP had written that
check and never run it. Measured (`test_gate_carve` prints these every run now):

```
carved opening              y -8.000 .. -4.400
leaf, visual AND collision  y -9.800 .. -6.200     <- a full half-height low
probing at                  y -6.200               <- exactly the leaf's top edge
```

The leaf hung **1.8 m underground and left the top half of its own doorway
open**. Collision was tracking the visual faithfully; the *visual* was
misplaced. The cause is that the two placement paths disagree about where a
gate's origin sits, and always have:

| path | places the gate origin at | measured |
|---|---|---|
| 4-point Surface tool | the opening's **centre** | world gate origin y = -6.514, quad spans -8.92 .. -4.09, centre -6.5 |
| catalog `gate_roller` | the opening's **base** (the wall hit point) | gate origin y = -8.000, opening -8.000 .. -4.400 |

`build_gate` assumed the first and was called by both. Nobody noticed because a
ghost leaf covering the wrong half is indistinguishable from a ghost leaf
covering the right one — the bug was only observable once the leaf could be
hit.

Fixed by making the anchor explicit: `build_gate(..., anchor_base := false)`,
with the catalog branch passing `true`. The gate stamps `leaf_top_y` (the
opening's top edge, the one edge a roller leaf never moves) and
`Gate._apply_open_t` hangs the box from it — `position.y = _leaf_top -
_leaf_h * s * 0.5`. One formula, both conventions, and the physics box is now
derived from the same number as the visual instead of from the origin. After
the fix all three spans coincide at `-8.000 .. -4.400` and `test_gate_carve`
reads **14 ok, 0 fail**.

## What this change does

1. **The leaf becomes a real collider** — `wip/gate-carve`'s fix, plus one
   rename and the anchor correction above. The shape is parented to the gate
   body and `_apply_open_t` sizes it from the fixed top edge, so a closed gate
   is solid across its whole opening and an open one clears.
2. **`oid` → `shape_owner_id`** in `test_gate_carve.gd`. GDScript has no block
   scoping and `oid` was already the opening-id `String` at `:197`; the
   re-declaration was a hard parse error that took the **entire harness** down at
   the parse sweep from 2026-08-31 06:00 until 2026-09-03.
3. **Skips are counted and printed.** `Result:` now reads
   `(N ok, M fail, K skipped)`, plus a `NOTE:` line whenever `K > 0`. The
   `BLOCKED:` prints become `SKIP :` entries through a `_skip()` helper that
   increments a counter. This is the fix that matters most: it is what makes a
   vacuous green impossible to quote as a real one.

## Deliberately NOT changed

* **The operator's `user://world_layout.json`.** The `"3A/3B gate"` is his
  in-game data. Deleting it would turn the suite green by removing the doorway —
  restoring exactly the vacuity this document exists to end.
* **The pilot.** With the leaf solid, the route through the closed gate
  disappears and the three checks legitimately skip again — but now visibly, in
  the verdict line.

## Open defects, measured, not fixed here

1. **A route exists that no vehicle can physically follow.** With the leaf still
   a ghost, an oriented box cast at the gate centre (`probe_gate_passable.gd`)
   reports the shell collision body
   `BuildingShell/ShellMesh/@StaticBody3D@385` overlapping a hull at **every**
   width tried — 2.4 m down to 0.8 m — while horizontal rays through the same
   opening at five heights all read `clear`. The route grid's cell probe accepts
   those cells; a vehicle-sized volume does not fit. That is the most likely
   reason both legs approach the gate and never converge (jam1 ends 5.63 m from
   the gate centre, jam3 2.38 m, both `wedged 0.0 s in 0 stall(s)` — never
   stopped, never arrived). **Inference from two measurements, not yet proven.**
2. **NPCs cannot operate gates.** A closed gate is now a real obstacle, and
   `GateButtonStation` needs a human. Any indoor→outdoor haul is blocked
   whenever the only doorway is a closed gate.
3. **`regression_world_save`'s on-wall check uses a stale frame.** `BF_O` /
   `BF_XU` / `BF_OUTLINE` (`regression_world_save.gd:30-32`, `:101-104`) describe
   a footprint spanning world Z 60.9–132.7, against a runtime-measured shell AABB
   of 140 × 155 m centred (-198.9, 95.8). `all 1 door(s)/gate(s) sit on a wall
   (on-wall 0)` is therefore evidence about the **check**, not about the gate.
4. **`_route_exists()` reads a stale snapshot.** `npc_route_points()` returns
   `_npc_route.size()` (`BaseVehicle.gd:1055`), assigned once per order at
   `:1028`, and `npc_stop()` does not clear it.

## Files

* Probes, written for this investigation and kept in the isolated worktree
  rather than committed: `probe_gate_navsource.gd`, `probe_gate_passable.gd`.
* Parked source branch: `wip/gate-carve` (`0063f6c`, unpushed) — the other
  session's original work, preserved verbatim.
* A/B proof logs live in this session's scratchpad; per-suite logs are in
  `tools/regression/out/`.
