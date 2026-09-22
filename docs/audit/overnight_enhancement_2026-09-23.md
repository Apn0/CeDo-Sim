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
- **Watch a real trip once:** stand at shredder-2 (or any friction separator),
  overload it, and confirm the rotor visibly coasts to a stop over ~2.5 s. The
  ramp is measured headless (`commanded_rpm` 45 → 0, `spin` 1 → 0); the frame
  rate of the visual coast-down is not.
