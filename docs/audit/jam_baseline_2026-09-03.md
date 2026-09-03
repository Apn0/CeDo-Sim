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

## Follow-up, 2026-09-03 — the gate opens now, and the pilot still fails

Two of the four open defects below are resolved, one is REFUTED by a better
measurement of my own, and what is left is a single clean defect.

**RESOLVED — NPCs cannot operate gates.** Operator ruling: the real 3A/3B gate
"is usually open", and its station is press-once, not a held deadman — top
button up arrow runs it open, centre stops it mid-travel, bottom button, red,
down arrow, runs it shut. Gates therefore now SPAWN OPEN (`Gate._ready`), the
station carries those arrows and colours, and finishing a travel calls
`BaseVehicle.invalidate_route_grid()` so the router stops seeing the old leaf
state. A second unswept centre-anchor constant surfaced and is fixed: the
station sat at `-height * 0.5 + 1.30`, which on a base-anchored catalog gate put
the buttons at y −8.500 — **half a metre under the floor**, unreachable even for
the player. It is now derived from `leaf_top_y` like the leaf.

**REFUTED — "a route exists that no vehicle can physically follow."** That was
my own inference from a bad probe. The box cast that reported the shell
overlapping a hull at every width from 2.4 m down to 0.8 m used a **4.0 m deep**
box centred on the wall plane; at that depth the box clips the jambs no matter
how narrow it is. Re-measured with a 0.6 m deep, correctly oriented
2.4 × 2.2 m hull at the open gate: **clear at every centre height from −7.60 m
upward**, hitting only `ExteriorGroundBody` at −8.60 and −8.10 where the box
dips below the floor. The opening admits a forklift. The wall is not the
problem.

**WHAT IS LEFT — the pilot cannot thread an open doorway it has a route
through.** With gates open, `_route_exists()` is true, the three gated checks go
hard, and they fail:

```
jam1_yard_to_plant: stalled after 116.4 s — final (-244.71, -8.60, 161.36),
  79.37 m from target (best 67.25 m), covered 203.7 m, path 7 pts, wedged 0.0 s
jam3_indoor_to_outdoor: stalled after 45.7 s — final (-244.98, -8.60, 157.91),
  57.34 m from target (best 16.94 m), covered 77.9 m, path 6 pts, wedged 0.0 s
Result: FAIL (11 ok, 3 fail, 0 skipped)
```

Both legs end within 6 m of the gate centre (−246.38, 155.98) having driven
203.7 m and 77.9 m respectively, never stationary, never wedged. jam3 closed to
**16.94 m of its goal and then went back out to 57.34 m** — it approaches,
turns away, and returns to the gate. That is a route-following defect in the
NPC pilot, not geometry and not the gate. It is now the only thing between the
plant and a working indoor→outdoor haul, and it is a real red rather than a
skipped check for the first time.

## Second follow-up, 2026-09-03 — the pilot was never broken

🤮 The claim above — "the pilot cannot thread an open doorway it has a route
through" — is **REFUTED**, by me, with the instrument I should have built first
(`src/tests/probe_pilot_convergence.gd`). Driving the identical leg through the
identical `npc_set_target` entry point with a larger budget and progress
measured ALONG THE ROUTE:

```
LEG: jam3   route points = 6
t=  0.0s  wp=1/6  d_goal= 17.50  pilot=RUN
t= 40.0s  wp=2/6  d_goal= 56.57  pilot=RUN     <- the old metric aborted here
t= 74.0s  wp=5/6  d_goal= 21.81  pilot=RUN
t= 84.0s  wp=5/6  d_goal=  3.51  pilot=RUN
outcome: arrived   waypoints 5 of 6   path 148.4 m   evades 0 during the leg
```

The forklift ticks every waypoint off, stays in `RUN` the whole way at a steady
1.83 m/s, and **arrives**. Three test-side defects were producing the red:

1. **The no-progress abort measured the wrong thing.** It watched the
   straight-line XZ distance to the goal and aborted after 40 s without gain
   (`test_jam_baseline.gd`). The plant has exactly ONE doorway, so jam3's route
   runs 58 m in the opposite direction to reach it: that distance is
   *guaranteed* to grow for the whole outbound run. The "57.34 m from target"
   the suite reported is exactly where the vehicle was at t=46 s, driving
   correctly. Now measured per waypoint — index advanced, or the current
   waypoint closed by 0.5 m — which is strictly MORE sensitive to real circling
   and immune to a legal detour.
2. **`DRIVE_FRAMES` was too small.** 7200 frames = 120 s; jam1 needs 158 s to
   cover 279.6 m of path at the ~1.8 m/s `NPC_CRUISE_FRAC` allows. Raised to
   14400 (240 s), sized from that measurement.
3. **jam1's goal was the player's spawn point.** `_anchor` IS `player_spawn`, and
   a hull probe at it returns `BLOCKED by ["Player"]` — the player body stands
   there in every headless boot. The forklift drove 352 m, closed to 2.32 m
   against a 2.2 m tolerance, correctly refused to drive through the player, and
   orbited in EVADE until the budget expired. Ordering a vehicle into an
   occupied pose asserts nothing about navigation, so jam1 now parks
   `JAM1_GOAL_STANDOFF_M` = 4.0 m short of the anchor on the approach bearing.

Result, on the operator checkout:

```
jam1_yard_to_plant:      arrived after 166.3 s, 2.20 m from target, covered 289.5 m, path 7 pts
jam3_indoor_to_outdoor:  arrived after 100.8 s, 2.20 m from target, covered 166.9 m, path 6 pts
Result: PASS (14 ok, 0 fail, 0 skipped)
```

**All fourteen checks evaluated and green — the first time this suite has ever
done that.** It has previously been 11 ok + 3 silently skipped, or 11 ok + 3
failing. Nothing was loosened to get here: the three formerly-skipped checks are
hard, `0 skipped` is printed, and the wedge and anti-vacuity assertions are
untouched.

## Open defects, measured, not fixed here

1. ~~**`VehicleRouteGrid.route()` appends the ordered goal verbatim**~~ —
   **FIXED 2026-09-03**, see the section below.
2. **`goal_clearance` is blind to dynamic bodies** — see above. A pose occupied
   by the player, a crew NPC or a settling bale reports 0.00 m. Closing it needs a
   live shape query beside the grid answer, not a change to the grid.
3. **`_route_exists()` reads a stale snapshot, and the staleness is currently
   LOAD-BEARING.** `npc_route_points()` returns `_npc_route.size()`, assigned once
   per order, and `npc_stop()` does not clear it. 🔑 Do not "fix" that by clearing
   the route in `npc_stop()`: `_drive_leg` calls `npc_stop()` and *then* calls
   `_route_exists()` (`test_jam_baseline.gd:474`, and again from `_test_jam3` at
   `:338`). Clearing it makes `_route_exists()` false after every leg, which
   re-arms the "no doorway, skip the check" branch and silently returns this suite
   to `11 ok, 0 fail, 3 skipped` — a result that reads like a pass. Fix the reader
   first, or fix both together and re-run the suite to prove the skip count stayed
   at 0. A warning now sits on `npc_stop()` itself.

   Also corrected while verifying this: `route()`'s docstring names
   EmptyLumpCartTask's seat pose as the caller that needs an unreachable goal, but
   `LumpCart extends RigidBody3D` and `_blocks()` admits only `StaticBody3D`, so
   nothing snaps there at all — the raw-append is a no-op for it. The callers that
   really snap are the `WasteContainer` legs (`extends StaticBody3D`).
4. **`regression_world_save`'s on-wall check uses a stale frame** — see the
   earlier section; `all 1 door(s)/gate(s) sit on a wall (on-wall 0)` is
   evidence about the check, not the gate.
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

## Third follow-up, 2026-09-03 — the router now says when a goal is not standable

`route()` still appends the raw ordered pose as its final waypoint, and it still
should: its docstring is right that a goal is routinely inside a container or a
cart pocket, and a router that refused those would break working tasks. What was
missing was any way for a caller to tell that apart from a goal it can actually
reach. jam1 ordering a forklift onto `player_spawn` is what that costs — 352 m
driven, 2.32 m short of a 2.2 m tolerance, an EVADE orbit until the budget
expired, and nothing anywhere explaining it.

**`VehicleRouteGrid.goal_clearance(to) -> float`** — metres the ordered pose sits
from a vehicle-sized free cell. `0.0` when it is already free, `-1.0` when no
free cell exists within `_nearest_free`'s ring bound.

Two things about it are deliberate and were both forced by measurement:

* **Stateless.** `BaseVehicle` caches ONE grid in a `static`
  (`BaseVehicle.gd:924`) that every vehicle shares, so a "last `route()` result"
  field on the grid would be overwritten by whichever vehicle ordered most
  recently and would report another vehicle's goal. Recomputed on demand: two
  cell lookups plus a bounded ring walk, no A*, no physics.
* **It reports the cell `_nearest_free` actually picks, not the geometrically
  nearest one.** That scan returns the first free cell in ring order, so from a
  lone solid cell's centre it answers 2.83 m (the diagonal) where an orthogonal
  neighbour sits at 2.00 m. `route()` snaps through the same function, so this
  has to agree with where the vehicle will really be taken. `_nearest_free` is
  left alone — its own comment records a measured-and-reverted attempt to make it
  cleverer, and "a wrong route is worse than no route" applies to its callers too.

`BaseVehicle` records it per-vehicle at order time and exposes
`npc_goal_clearance_m()`. It warns on exactly one condition, and the threshold is
derived rather than picked: `npc_arrived()` succeeds within `NPC_ARRIVE_TOL`, so a
goal snapped **further than that** can never complete, while a container-mouth
goal snapped less than that still arrives and must not produce a warning on every
legitimate order.

### What it cannot see, and why that matters here

🤮 The first version of this function's docstring cited jam1's
`BLOCKED by ["Player"]` trace as its motivation. **That is the one case it
misses.** `VehicleRouteGrid._blocks()` returns false for anything that is not a
`StaticBody3D`, and `Player.tscn`'s root is a `CharacterBody3D` — so the grid is
blind to the player, to crew NPCs, and to `RigidBody3D` yard bales.
`goal_clearance` reports jam1's original goal as **0.00 m, free**, while a hull
probe at the same point returns `BLOCKED by ["Player"]`. Both verified by reading
`_blocks()` and `Player.tscn` directly, after an adversarial review caught the
over-claim.

What the function actually answers is "is this pose inside the plant's **static**
geometry" — machines, walls, `WasteContainer`s — which is the common case and the
only thing a once-sampled occupancy grid can know. Catching an *occupied* pose
needs a live shape query against the physics space, which this deliberately does
not do. That is the named follow-up, not a silent gap: every place that claims
otherwise has been corrected, and `test_jam_baseline`'s info line says so inline,
which is also why jam1 parks `JAM1_GOAL_STANDOFF_M` short rather than trusting
this number to catch it.

### A refinement to the jam1 orbit story

The adversarial pass also corrected the mechanism I had written for jam1's EVADE
orbit. Because `route()` appends the raw goal, `_npc_drive`'s last-leg waypoint
test (`dist <= NPC_ARRIVE_TOL`) and `npc_arrived()` are the **same XZ
predicate** — so "the final waypoint is consumed but `npc_arrived()` is still
false" is unreachable. What actually happens is the inverse: the final waypoint is
**never** consumed, the vehicle lives in the last leg forever, and the pilot cycles
EVADE ↔ REVERSE against the body standing on the goal.

Proved by `src/tests/test_route_goal_clearance.gd` — **15 ok, 0 fail** — a unit
suite on a synthetic occupancy grid, wired into `run.sh` beside the other
`--script` suites. No world boot, no A*, no physics: milliseconds, not the ~90 s
a `MainWorld` boot costs. It earned its keep immediately by **failing on a real
bug in the first implementation**: clamping the cell before testing it for
freeness made a pose 120 m off the survey clamp onto a free edge cell and report
`0.00 m` — the exact opposite of the truth. It now tests the raw cell for bounds
and reports 142.84 m. Two further checks in it were my own wrong expectations
about the diagonal, corrected in the test with the reasoning recorded rather than
quietly relaxed.

`test_jam_baseline` prints the clearance for each leg every run. Reported, not
asserted: crew NPCs and the player move between boots, so a hard check there
would be flaky, and the arithmetic is proved deterministically in the unit suite.
