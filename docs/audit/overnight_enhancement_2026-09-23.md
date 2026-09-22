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

## Things for the operator to look at in-game (not guessed)

- **P2 smoke / heat-shimmer on a packed-up drive:** does the real one smoke? If
  yes, a short particle burst at the motor housing on the trip edge is ~20
  lines; if no, the rotor stopping plus the alarm is the whole event.
- **Watch a real trip once:** stand at shredder-2 (or any friction separator),
  overload it, and confirm the rotor visibly coasts to a stop over ~2.5 s. The
  ramp is measured headless (`commanded_rpm` 45 → 0, `spin` 1 → 0); the frame
  rate of the visual coast-down is not.
