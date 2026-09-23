# Overnight enhancement run — 2026-09-23

Unattended session on branch `claude/ready-daacfa` (worktree
`V:\_Claude\CeDo_Simulator\ready-daacfa`, real copies of `assets/` and
`.godot/`). Directive: work the existing backlog
(`docs/BACKLOG_ultracode_2026-07-19.md`, `docs/DESIGN_SUGGESTIONS_2026-07-08.md`)
first, then widen. Nobody was watching; every choice below records why the
recommended/safest option was taken. Things that need the operator's eyes
in-game are collected in the last section instead of being guessed.

Every Godot run was wrapped in `timeout --kill-after=10 N`, judged on its
`Result:` line plus zero `SCRIPT ERROR` lines, never on the exit code. All
suites were run with `--path .` from the worktree, never against the
operator's checkout.

## 0. What landed, in order (branch `claude/ready-daacfa`, on top of `a619b1e`)

| commit | what | proof |
|---|---|---|
| `fb065f0` | **P2** — a latched MotorOverload trip now really stops the drive (it kept conveying at full rate) | `test_motor_trip_stops_conveying` 28 ok; pre-fix 20 ok / 8 fail |
| `41ecca4` | **P6** — a full Lumpenwagen overflows onto the floor, visibly; no lump kg vanishes | `test_lump_cart_overflow` 45 ok |
| `ac7f668` | **Q2** Checkpoint save; **Q4** F1 key sheet; six Controls-tab actions bound at boot | `test_save_checkpoint` 22 ok; `test_keybind_sheet` 24 ok |
| `e248861` | **Q5** map wayfinding labels; two per-frame recursive tree searches cached | `test_map_labels` 18 ok; `probe_find_child_cost` |
| `f74b4a9` | **phys-05 interim** — the cart can no longer be flung or spun by a squeeze-eject | `test_lump_cart_speed_clamp` 6 ok; mutation 4 ok / 2 fail |
| `eee57e8` | soak probe (no growth over 16.6 s; 9.4 ms/frame CPU floor) | `probe_world_soak_growth` |
| `577d7d4` | docs for the soak | — |

Seven new suites are wired into `run.sh`'s main loop. The full harness was run
once on the branch at the end of the night — see §7 for the measurement.
Sections 1-6 below are the per-item evidence, in the order the work was done.

## 1. P2 — a MotorOverload trip did not stop the drive (fixed)

**Backlog entry:** DESIGN P2 said a trip "surfaces only as an EventBus alarm +
HMI number; nothing stalls or smokes". The premise was checked, not trusted
(directive: existing code is evidence of state, not of quality).

**Measured before any change** (`src/tests/test_motor_trip_stops_conveying.tscn`
on the real `line_sort` macro, shredder-2 force-tripped via
`MotorOverload.force_trip()`, its documented owner-facing API):

| quantity | pre-fix | after fix |
|---|---|---|
| shredder-2 `_moved_kg`, first tick after trip | 0.0611 kg (= full 0.61 kg/s × 0.1 s) | 0.0000 |
| shredder-2 kg conveyed over 3.1 s "tripped" | 1.894 kg | 0.000 |
| bunker kg conveyed over the same 3.1 s (interlock) | 31.000 kg | 0.000 |
| shredder-2 `spin` after 3.1 s | 1.000 | 0.000 |
| max `commanded_rpm()` over shredder-2 mechanisms | 45.0 | 0.0 |
| shredder-2 input buffer 59.694 kg → | 57.800 kg | 59.694 kg |
| shredder-2 `powered` read at end of tick | false | false |
| shredder-2 `amps` | 0 A | 0 A |

So the trip was cosmetic: the two things a trip is supposed to do (stop the
rotor, stop the material) did not happen, while the two things every existing
check read (`powered` after one tick, amps) looked perfect. The
bunker/shredder-2 interlock (operator instruction 2026-08-26) had the same
hole — `test_bunker_shredder2_interlock` passes because it reads `powered`
after a single tick, which is exactly the end-of-tick value the defect leaves
correct.

**Cause.** `LineFlow.tick()` order is `_tick_plc_power_downstream` →
`_tick_feed` → `_tick_process_machines` → `_tick_advanced_systems` →
`_tick_bunker_shredder2_interlock`. The PLC step wrote `powered = plc_says`
(true once started) on every staged node and immediately ran the `spin`
ramp and every `RotatingMechanism.set_running()` from it; the trip dropped
`powered` in `_tick_advanced_systems`, after conveying; the next tick the PLC
wrote `true` again before anything read it.

**Fix** (`src/sim/LineFlow.gd`): `_apply_trip_latches()` runs inside the PLC
step, after the PLC and HAND-mode writes and before `_estop_step()` and the
ramp. It drops `powered` on every node whose own `mol.is_tripped()`, and
applies the bunker/shredder-2 interlock there too (the 2.55 call after
`_tick_advanced_systems` is kept so a trip that fires mid-tick still shows on
`powered` in the same tick). The machine node's own `set_running(false)` is
called while latched, next to the existing e-stop / PLC-stopping branch. A
latched relay is a dropped-out contactor: HAND mode bypasses the PLC, not the
motor protection, so the latch runs after both. Nothing else changed — the
rotor's coast-down is `RotatingMechanism`'s existing ramp, which had simply
never been told to stop.

**Not built: smoke.** Rule 1. A thermal-overload relay dropping out does not
make a motor smoke, and there is no operator statement or photo of what a
packed-up drive looks like beyond "it stops". Listed for the operator below.

**Verification, all from the worktree:**

| suite | result |
|---|---|
| `test_motor_trip_stops_conveying` (new, 28 checks) | pre-fix `FAIL (20 ok, 8 fail)`; post-fix `PASS (28 ok, 0 fail)` |
| `test_bunker_shredder2_interlock` | PASS |
| `test_bunker_relay_trip` | PASS |
| `test_line1_no_false_overload` | PASS (0 fail) |
| `test_shredder_machine` | PASS |
| `test_feeder_sequence` | PASS (exit 139 = the documented teardown segfault after the verdict) |
| `test_tag_snapshot` | 28 ok, 0 fail, 1 skip — see note |
| `test_line1_throughput` | PASS |
| `test_shredder_rate_reconciliation` | PASS |
| `test_line1_flow_conformance`, `test_line3a_flow_conformance`, `test_line3b_flow_conformance` | PASS |

The suite's anti-vacuity check asserts both machines were moving material
BEFORE the trip; the 8 pre-fix reds are exactly the trip-effect checks, and
the fix turns them green without touching the checks. The suite is wired into
`run.sh`'s main loop.

## 2. P6 — a full Lumpenwagen overflows onto the floor, visibly (done)

**Backlog entry:** DESIGN P6. **Checked first:** `LumpCart.receive_lump()`
returned at `is_full()` and dropped the kg, under a comment saying "the
upstream filter will see is_full() and stop pushing" — a grep shows nothing in
`LaserFilter` ever read `is_full()`. `lumps_kg_this_shift` counted kg that then
existed nowhere. The cart never showed its load either: a chunk that came to
rest inside the bucket was freed on absorption, so a 90 kg cart looked empty.

**What changed** (`src/sim/LumpCart.gd`, `src/sim/LaserFilter.gd`,
`src/sim/FloorPile.gd`):

- `receive_lump()` returns the refused kg. It accepts up to `CAPACITY_KG`
  (100) — the operator's 2026-07-11 figures make 90 kg "full, worth emptying"
  and 100 kg "the discharge truly can't add more", so the last 10 kg heap over
  the rim and are still taken.
- `LaserFilter._disc_advance()` routes refused kg, and the kg of a nozzle with
  no cart under it, into one soft `FloorPile` per nozzle straight under the
  nozzle (around the cart's base). New counters `lumps_kg_on_floor` and
  `lumps_kg_lost` (the latter only moves when the mound itself is at its
  1.0 m radius, ~270 kg).
- A visible heap (`LumpHeap`) inside the bucket, sized from the cart's own
  collision plate and walls — measured, not copied from the catalog — rising
  with `lumps_kg`, tinted hot→cool on the cart's own cool-down clock.
- A full cart no longer absorbs settled chunks (they stay as overflow, still
  litter-capped at 16).
- `FloorPile.solid` (default true): false = no collider.
- `LumpCart._now_sim_s()` caches the ShiftClock instead of a whole-tree
  `find_child` per call (polled per cart by the autonomy board; ~9k nodes in a
  booted world).

**Two things the suite caught in the change itself, in order:**

1. The heap top at 90 kg sat 1.25 cm above the wall top (0.7340 vs 0.7215 m):
   the catalog's wall boxes start at the floor plate's CENTRE, so "wall box
   height" over-reads the rim. `h_max` is now wall-top minus plate-top.
2. The first draft put a SOLID pile beside the cart, outward along the
   filter's X. The suite's shape query at that point hit `Extruder 3B`,
   `Extruder 1` and `Extruder 3A` (all three achter sides; 3C and every voor
   side were free): the achter cart stands on its bordes between the filter
   and the extruder's 14 m collider, so there is no free floor there. A
   candidate search (outward X, then ±Z) fell back every time for the same
   reason. Physically, lumps that overflow heap over the rim and slide down
   the cart's sides, so the mound now sits under the nozzle around the cart's
   footprint and is soft — a StaticBody3D growing inside a RigidBody3D cart's
   footprint ejects the cart. A solid pile beside the cart would also have
   walled off the forklift's approach for the npc-05 chain.

A third red was a fixture artefact: with no floor body under a BuildMode-only
line the voor carts (no bordes) sank 6.7 cm in the frames the suite runs; the
fixture now has a floor.

**Measured** (`src/tests/test_lump_cart_overflow.tscn`, real `line_3b` macro,
production purge path `_disc_advance()` with 2000 g of cake → 1.7 kg per
advance):

| step | result |
|---|---|
| bucket measured from the cart's collision boxes | w 0.688, d 1.084, plate top 0.265, rim 0.4565 m above it |
| heap at 45 / 90 / 100 kg | 0.228 m / on the rim (0.7215 = wall top) / 0.507 m (over the rim) |
| `receive_lump(15)` at 90 kg | 10 accepted, 5.000 refused |
| purge into a full achter cart | achter 100 → 100 kg, voor +0.85, mound +0.85, lost 0 |
| mound position | XZ 0.000 m off the nozzle, y 0.120 on the bordes the cart stands on (cart base 0.119) |
| second purge | same mound reused, 1.700 kg |
| settled chunk in a full cart | kept; absorbed after `empty()` |
| no cart under either nozzle | the whole 1.7 kg lands on the mound |
| conservation | shed 5.100 == voor 1.700 + floor 3.400 + lost 0.000 |
| mound points, all 4 lines × 2 nozzles | under the nozzle, on the cart's surface (0.12 bordes / 0.0 floor) |

`Result: PASS (45 ok, 0 fail)`; wired into `run.sh`.

**Assumptions stated:** lump bulk density 400 kg/m³ (solid LDPE ~920 kg/m³,
~40 % packing of 70 mm rope chunks; FloorPile's 200 default is loose film).
The whole heap takes the colour of the newest lump (the real top layer is
hot, the bottom cooled). The mound is not persisted across save/load — the
same gap LineFlow's chute piles have.

**Not done:** the other half of P6, `LineFlow._dump_waste` losing reject past
a maxed chute pile. The honest model there is that the machine backs up
(cannot discharge) until the pile is shovelled, which changes the throughput
every conformance suite measures — not a change to make unattended.

## 3. Q2 checkpoint save and Q4 F1 key sheet (done)

**Q2 — checkpoint.** `SaveCoordinator.save_checkpoint()`: save the live slot,
then copy `<stem>_save.json` and the `<stem>_factory.json` sidecar to
`<stem>_cp_<YYYYMMDD-HHMMSS>_*` through `AtomicFile`. The main menu's scan
lists every `*_save.json`, so a checkpoint is a normal loadable save with its
own `saved_at`. Same-second stamps get `-2`, `-3` …; any failure returns `""`
and writes nothing. Pause card gets a **Checkpoint** button between Save and
Save & Quit; the HUD banner names the copy. `test_save_checkpoint`: 22 checks
on the REAL `GameState` + `SaveCoordinator` with no world (both are null-safe),
`__cptest__` files only, deleted at the end and proven gone.

**Q4 — key sheet.** `KeybindSheet` (new, under HUD), F1 via the new
`help_overlay` action (project.godot + `_ensure_aux_actions` + HUD's
fallback map, like `map_toggle`). H, the design doc's pick, is taken (vehicle
handbrake, marker-tool clear); F1 was unbound everywhere. `build_rows()` is
static and is exactly what is rendered: 69 actions in 10 groups, live
InputMap bindings, rebuilt on open. `test_keybind_sheet`: 24 checks.

**Found by the sheet suite, fixed:** six Controls-tab actions (`sprint`,
`fast_run`, `feedback_capture`, `opening_capture`, `debug_fill_silo`,
`debug_force_fault`) were registered only by `PlayerController._ready()`, so
before a player existed — the main menu's Settings → Controls — the tab showed
"—" for keys that work. They are now registered at autoload time in
`SettingsManager._ensure_aux_actions` with the same physical keycodes
(`fast_run`'s Alt stays debug-build-only). The suite now asserts every tab
action is bound at boot; `test_f10_reserved` still passes (F10 stays
`feedback_capture`'s alone).

| suite | result |
|---|---|
| `test_save_checkpoint` (new) | PASS (22 ok, 0 fail) |
| `test_keybind_sheet` (new) | first run 22 ok / 1 fail (the six-actions finding); PASS (24 ok, 0 fail) after the registration fix |
| `test_f10_reserved` | PASS |
| `test_scada_dashboard_scene` | 29 ok, 0 fail |
| `test_map_overlay_init` (full MainWorld boot, HUD with the new sheet) | PASS |
| parse sweep | 416 ok, 0 fail |

## 4. Q5 map wayfinding labels, and two per-frame tree searches (done)

**Q5.** `MapOverlay`: machines labelled by catalog display name
(`machine_label_for`), crew dots named (`crew_label_for`), HMI panels drawn as
violet diamonds with their scope label (`hmi_markers()`, new
`Hmi.scope_label()`), legend row added. All sources are live nodes. Guard
`test_map_labels`: pure helpers, a real MainWorld boot for the crew names, two
catalog-built HMI panels, a zoomed redraw. One fixture red on the way: the
dummy display server's window is 64 px, so the closest radius only reaches
`scale_px` 1.05 and no label is drawn — the suite now sizes the overlay to
1152 × 648 itself. Also green after the change: `test_map_overlay_init`,
`test_map_frame`, `test_hmi_retired` (70 ok), `test_vehicle_census`,
`test_nested_vehicle_drift`.

**Per-frame tree searches.** A script listed every recursive `find_child` /
`find_children` in game code by enclosing function (68 sites); three ran
inside per-frame code. `probe_find_child_cost` (kept, not wired) measured
them on this machine, headless:

| search | cost |
|---|---|
| `bale.find_child("Wires", true)` on a real 115-node bale | 4.5 µs per call |
| the cached reference instead | 0.17 µs per call |
| `root.find_child("ShiftClock", true)` MISS on a 3151-node tree | 252.8 µs per call |

- `LumpCart._now_sim_s()` did the whole-tree search on EVERY call (fixed in
  the P6 commit: the ShiftClock is cached once). A booted world is ~9k nodes,
  so each call was in the order of 0.7 ms; the autonomy board polls
  `is_cool()` per cart and the new heap colour would have added one call per
  cart per second.
- `BaleClamp._update_wire_bulge()` ran the bale search every physics tick
  while carrying (4.5 µs × 60 Hz — small, but it is now one lookup per
  carried bale).
- `DayNightCycle._process()` searched the WHOLE tree every frame for as long
  as no ShiftClock existed (bench worlds, forever): now a 2 s retry.

The other 65 sites are one-shot (`_ready`, `setup`, `_bind_nodes`) or
event-driven and were left alone.

## 5. phys-05 interim — the Lumpenwagen can no longer be flung (done)

BACKLOG phys-05: frozen-kinematic vehicles have infinite mass, so a cart
caught between a forklift and a wall left at whatever velocity the solver
needed to resolve the overlap. The backlog's own interim suggestion was a
speed clamp in `LumpCart.gd`; the file already had `MAX_SPEED := 3.5` with no
reader. Now `_integrate_forces` caps linear velocity at 6 m/s (above a hand
push at ~1.8 m/s and a forklift shove at ~4 m/s) and angular velocity at
6 rad/s.

Measured (`test_lump_cart_speed_clamp`, real catalog cart on a floor):

| impulse | integrator disabled (mutation run) | with the clamp |
|---|---|---|
| 50 m/s central impulse, read next tick | 48.09 m/s | 5.76 m/s |
| 500 N·m·s twist | 53.33 rad/s | 5.58 rad/s |
| 1.2 m/s walking shove | 1.04 m/s | 1.04 m/s (untouched) |

`Result: PASS (6 ok, 0 fail)`; the mutation run reads `FAIL (4 ok, 2 fail)`
on exactly the two clamp checks. Wired into `run.sh`. This bounds the symptom
for the cart only — bales and containers can still be ejected, and the
AnimatableBody chassis re-architecture remains the real phys-05 fix.

## 6. Soak: does a running world grow? (measured — no)

`src/tests/probe_world_soak_growth.tscn` (kept, not wired). It replaces a
first "frame cost" probe once `bench_mainworld_perf.gd` (2026-09-21) turned
out to own per-frame cost already; the probe owns growth. It uses the bench's
discipline — a `__soak__` scratch slot and `WorldLayout.layout_path_override`
set BEFORE the boot, so the 60 s autosave can never reach the real
`world_layout.json` (md5 checked identical before and after). This machine has
no real save slot (user:// holds only `__test__` slots), so it boots a fresh
world and places `line_3b` + `line_sort` through BuildMode (52 LineFlow nodes,
line started), then samples two 300-frame windows 1500 frames apart.

| quantity | window 1 (lines just placed) | window 2 (16.6 s later) | growth |
|---|---|---|---|
| nodes | 4533 | 4533 | +0 |
| orphan nodes | 3 | 3 | +0 |
| objects | 15356 | 15362 | +6 (+21.6/min) |
| resources | 524 | 524 | +0 |
| static memory | 896.75 MB | 896.80 MB | +0.05 MB (+0.18 MB/min) |
| TIME_PROCESS mean | 25.4 ms (max 104.9, settling) | 9.42 ms (min 9.25, max 9.64) | −16.0 ms |
| wall ms/frame (headless) | 11.0 | 11.7 | +0.7 |

No leak signature at this timescale: node and resource counts are flat, the
six extra objects over 16.6 s are within what parcels in the flow pipes
account for, and memory moves by 50 KB. What the numbers DO say: a booted
world with two lines costs a steady **9.4 ms of CPU-side process time per
frame headless** — the "proc floor" the bench header records without
attribution. That is the next performance target; the bench's ablation was
measured too noisy to attribute it (its own header), so attribution needs a
different instrument (timing `LineFlow.tick`, `CrewManager.tick` and the NPC
`_physics_process` directly). Not done tonight.

## 7. The full harness on the branch (measured 2026-09-23, 01:57 → 02:32)

`PROJ="V:/_Claude/CeDo_Simulator/ready-daacfa" bash tools/regression/run.sh`
from the worktree, detached from any tool timeout, at commit `577d7d4`
(everything in §0 in place; the nav-bake and sight-glass changes below were
applied AFTER this run). `== done (exit 1)`, **111 steps in 35 minutes, 105
logs written** (counted by mtime, as CLAUDE.md asks), 0 timeouts, and exactly
**three** `FAIL  :` lines:

| red | verdict |
|---|---|
| `test_nav_connectivity` | the known crew-post island: Abdellilah and Mohammed, canteen←post ends **14.67 m short** at (-215.7, 83.2) — byte-for-byte the 2026-09-22 measurement. Operator call, untouched. |
| `test_jam_baseline` | `6 polygons, 7 vertices` — the "intermittent navmesh collapse". **Root-caused tonight, see §8**: the suite read the mesh before the fixture bake finished. |
| `test_npc05_realworld` | expected: the chain holds DRIVE_TO_INDOOR from frame 6583 to the end of the 180 s window. Untouched. |

Everything else green, including the seven suites added tonight, the 15
own-dialect suites, both spawn-clearance configurations and the door carve.
`test_tag_snapshot` still reports its pre-existing `28 ok, 0 fail, 1 skip`.

So against the 2026-09-22 measurement (two reds) the branch shows one more,
and that one is a measurement defect in the suite, not a change in the world.

## 8. The "intermittent navmesh collapse" was the suite reading too early (root-caused, fixed)

`test_jam_baseline` red in the harness with `6 polygons, 7 vertices`. CLAUDE.md
carries this as INTERMITTENT (2 collapses in 3 runs on the 2026-09-21 dirty
tree, one clean pass on 2026-09-22); the operator checkout's own last jam log
reads `10 polygons, 8 vertices` — the same thing.

**What the log shows.** The world bakes three times: at boot (2 source bodies),
once deferred from `_ready` (1 body), and once when the suite calls
`rebake_navigation()` after placing the 39-machine fixture (37 bodies). The
suite then waited for the polygon count to hold still for 60 frames and read
`6 polygons` — and the world's own `bake_finished` handler ("Nav connectivity
verified: plant route open") printed AFTER the suite's FAIL lines. The 37-body
bake was still on its thread; the suite measured the previous, 1-body mesh
(floor + one body = 6 polygons). In the healthy `test_nav_connectivity` run of
the same harness the identical heuristic happened to outlast the bake and read
281 polygons. A threaded bake of ~37 bodies at this cell size takes about one
second, which is exactly the 60-frame window: a coin toss, hence "intermittent".

**Fix.** Both suites now wait on the engine's own flag —
`NavigationRegion3D.is_baking()` — until it clears (plus five quiet frames to
catch a queued re-bake starting), and only then run the old stability loop.
`MainWorld.rebake_navigation()` additionally queues a rebake that lands while
a bake is still running and re-issues it from `bake_finished` (defensive: a
BuildMode commit-time rebake during the boot bake would otherwise be dropped
silently; that is not what happened tonight).

**Measured after the fix** (each run a full MainWorld boot + the 39-machine
fixture):

| run | bake thread finished after | polygons / vertices | verdict |
|---|---|---|---|
| `test_jam_baseline` #1 | 69 frames | 279 / 299 | PASS (11 ok, 0 fail, 3 skipped — the doorway-gated checks) |
| `test_jam_baseline` #2 | 72 frames | 279 / 299 | PASS (11 ok, 0 fail, 3 skipped) |
| `test_jam_baseline` #3 | 71 frames | 279 / 299 | PASS (11 ok, 0 fail, 3 skipped) |
| `test_nav_connectivity` #1 | 29 frames | 281 | FAIL (9 ok, 1 fail — the known crew-post island, 14.67 m, unchanged) |
| `test_nav_connectivity` #2 | 39 frames | 281 | FAIL (9 ok, 1 fail — same) |

Three jam runs, three bakes that took 69-72 frames: every one of them would
have latched onto the stale 6-polygon mesh under the old 60-frame rule. The
"intermittent" red was a measurement of the machine's bake speed, not of the
world. The nav suite's bake is faster (29-39 frames, its LineFlow rebuild runs
first) which is why it read the right mesh in the harness by luck.

The `bake thread finished after N frames` line each run prints is the
evidence the old window was too short whenever N is above 60.

## 9. The compactor's kijkglas now shows the pot's load (done, docs-backed)

DESIGN P5 asked for a visible silo level. The plant docs do not describe a
level indicator on any silo; they do on the compactor: Cedo PROD-SWI-012 p7
step 6, "Vul de compactor op hand tot het kijkglas" (fill the compactor by
hand up to the sight glass). The model already had that glass on the cleanout
door (`_m_compactor`) and the load (`CutterCompactor.charge / POT_CAPACITY_KG`);
nothing connected them, so the glass showed a grimy disc over an empty drum.

**What changed.** `_m_compactor` adds a `PotFill` flake column standing on the
cutter disc, carrying its own geometry as meta (base, range, the glass's centre
and radius) so no reader copies a constant; `PlaceableCatalog.set_pot_fill()`
sizes it; `CutterCompactor.pot_fill_fraction()` exposes the load; LineFlow's
compactor block publishes `nd["cc_fill"]` and drives the column every tick,
caching the PotFill lookup per node. Ghosts get no column. Colour is the
washed-flake base tint `FilmFlakeField` already uses.

**Measured** (`test_compactor_sight_glass`, catalog PCU + a real LineFlow node
with 60 kg injected):

| check | result |
|---|---|
| column geometry read off the mesh's meta | base 1.288 m, range 2.037 m, glass at 1.950 ± 0.12 m (size.y 3.9) |
| the glass lies inside the fill range | level enters the glass at 27 %, leaves it at 38 % of the pot |
| half / full / over-full | height 0.5 × range on the base; top at base + range; 1.7 clamped to the lid |
| at the glass fraction the top is in the window | yes |
| LineFlow drive, 300 ticks | column height == fraction × range every tick, `cc_fill` matches, 0 mismatches; peak fill 100 % |
| the level moved while fed and discharged | yes |

`Result: PASS (21 ok, 0 fail)`; wired into `run.sh`. One fixture
assumption fell on the way: a lone head node is fed by LineFlow's own head
feed during start-up (the pot read 100 % before any injection), so the
pre-injection check is consistency, not emptiness.

**Honest limits.** The column is a plain cylinder of one tint (real flake is
mixed colour, and the operator fills "to the glass", ~30 %, by hand — the model
fills from the belt). Whether the level reads through the grimy glass at all
from where the operator stands is an eye judgement (operator list). Silos stay
without a level indicator — no document describes one (Rule 1).

## 10. Where the CPU frame time goes (measured — LineFlow ticks every frame)

`src/tests/probe_tick_cost.tscn` (kept, not wired) calls each per-frame entry
point itself N times and takes the wall clock — the function's own cost, not a
difference of two noisy windows (the bench's ablation). Fresh world +
`line_3b` + `line_sort` (52 LineFlow nodes), 9 workers, 9 vehicles, headless:

| system | µs per call | calls/s | ms per frame at 60 Hz |
|---|---|---|---|
| `LineFlow.tick(1/60)` — its `_process` calls `tick(delta)` EVERY FRAME | 2845.9 | 60 | **2.846** |
| `NPC._physics_process` × 9 workers (sum) | 1625.0 | 60 | 1.625 |
| `BaseVehicle._physics_process` × 9 vehicles (sum) | 1248.8 | 60 | 1.249 |
| `CrewManager._physics_process` | 30.5 | 60 | 0.031 |
| `SimTick.sim_tick.emit(0.1)` (1 subscriber) | 157.1 | 10 | 0.026 |
| `HUD._process` | 20.9 | 60 | 0.021 |
| `NpcAutonomyBoard._process` | 4.5 | 60 | 0.005 |

Attributed: 5.80 ms of a 16.18 ms `TIME_PROCESS` reference in that run (the
reference was taken 240 frames after placing the lines, still settling; the
soak's steady state was 9.4 ms). The rest is the engine, the physics server
and navigation.

**The finding.** `LineFlow` runs its whole flow step — spatial-query caches,
52 nodes of PLC/feed/split/observer work — at frame rate, while the
project's own sim clock (`SimTick`) is 10 Hz and **every suite drives
`LineFlow.tick(0.1)`**: the tested rate is not the shipped rate. Ticking the
flow at 10 Hz from an accumulator in `_process` would cut 2.85 ms/frame to
~0.47 ms and make the game run the rate the harness proves. Not done tonight:
the EMA smoothing constants in `tick()` are per-tick (the HMI's `thru` would
settle in ~1.3 s instead of ~0.2 s wall time) and the MainWorld-based suites
carry time-based expectations, so it needs its own full harness run and an
operator look at the HMI response — listed as the next performance step.

## Things for the operator to look at in-game (not guessed)

- **P2 smoke / heat-shimmer on a packed-up drive:** does the real one smoke? If
  yes, a short particle burst at the motor housing on the trip edge is ~20
  lines; if no, the rotor stopping plus the alarm is the whole event.
- **P6 heap and mound, on foot:** fill a Lumpenwagen (Numpad 9 fills the
  aimed machine; the cart itself fills through the laser filter) and look at
  the `LumpHeap` box inside the bucket and the grey mound that forms around
  the cart's wheels once it is at 100 kg. Both are sized from measured
  geometry, but nobody has SEEN them. Two questions only the eye answers: does
  a flat box read as lumps, and should the mound's 1.0 m radius be smaller.
- **P6 and the forklift:** lift a cart out of a mound with the forklift — the
  mound is soft (no collider) so the cart comes free, but the visual of the
  cone left behind at the spot has not been looked at.
- **Q2 Checkpoint button:** open the pause card (P) and press Checkpoint —
  the banner should name `<slot>_cp_<stamp>`, and the main menu should list
  it. The button's placement on the card (4th of 5) is unseen.
- **Q4 F1 sheet:** press F1 on foot and in a cab. The panel is 760 × 560 px
  clamped to 90 % × 75 % of the window; whether the 69 rows read well at the
  real window size, and whether the sheet should pause the shift (it does
  not, like the map), are judgement calls.
- **Q5 map:** open the map (M) near a line and zoom in two or three notches:
  machine names in Dutch, crew names beside the dots, violet diamonds on the
  HMI panels. Whether violet reads well on the dark panel, and whether names
  should also show at the default 90 m radius, are eye judgements.
- **Compactor kijkglas:** stand at the PCU's cleanout door on 3C while the
  line runs and look into the glass: a grey flake level should sit behind it
  between ~27 % and ~38 % pot load, and be gone below/above. Whether it reads
  through the grime material at all, and whether the flake tint is right, are
  eye judgements.
- **Watch a real trip once:** stand at shredder-2 (or any friction separator),
  overload it, and confirm the rotor visibly coasts to a stop over ~2.5 s. The
  ramp is measured headless (`commanded_rpm` 45 → 0, `spin` 1 → 0); the frame
  rate of the visual coast-down is not.
