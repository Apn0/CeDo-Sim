# HMI fault re-arm — a re-trip is a new occurrence (2026-09-24)

`src/scenes/hud/HmiOverlay.gd`, guarded by `src/tests/test_hmi_fault_rearm.tscn`
(in `tools/regression/run.sh`'s main scene loop).

## The defect, as measured

Code read on `main` `b8bda8a`: `_acked_faults` was a per-CODE set. KWITTEREN
(`_on_kwitteren`) added every active code to it, only RESETTEN
(`_on_reset_faults`) cleared it, and the clear-transition loop in
`_record_fault_transitions` erased `_fault_first_seen[code]` and logged
"Hersteld" but never touched the ack.

Trigger → wrong outcome, measured by the new suite on the unmodified overlay:

| path | trigger | wrong outcome |
|---|---|---|
| panel open | 6557 trips (343 bar) → KWITTEREN → pressure drops to 291 bar, the fault clears by itself → 343 bar again | the re-trip shows up already "(gekwiteerd)", is missing from the Actief tab, and the bell stays amber-steady. Historie marks all three rows gekwiteerd |
| panel **closed** | same, but KWITTEREN → close the panel → clear + re-trip while it is shut → reopen | same, plus the overlay never saw the clear at all. Historie has 3 rows where 5 happened |

The second path is a separate cause: `_process` returned on `not visible`, so
the overlay only observed the plant while someone had it open. It is the more
likely real case, because the operator acknowledges and walks away.

Result on `main` as it was (`b8bda8a`): `Result: FAIL (25 ok, 7 fail)`, 0
`SCRIPT ERROR`.

**#275 (`1588462`) landed a partial fix in parallel**, the minimal option:
`_acked_faults.erase(code)` when a fault clears, guarded by
`test_hmi_ack_rearm` (7 checks, RUN-200 driven through the overlay's own
methods). That re-arms the code on a re-trip **while the panel is open**.
Measured on the rebased branch with #275's overlay swapped in:
`test_hmi_fault_rearm` is `27 ok / 5 fail`. What this change adds over #275:
- **the closed-panel path** (B1 ×2, B2, D1): #275's overlay still observes
  only while open;
- **the ack per occurrence in the history** (A4-history): with the per-code
  erase, the first trip's Historie rows lose "(gekwiteerd)" the moment it
  clears.

#275's erase line is superseded by the occurrence model (the variable is now
`_acked_occurrences`), and `test_hmi_ack_rearm`'s two direct reads of
`_acked_faults` are ported to `_is_acked()` / `_acked_occurrences`.

## The fix

- Every fault code that goes active gets an **occurrence id** (`_fault_occ`,
  from a monotonic counter). The id is dropped when the code clears, so a
  re-trip gets a new one.
- KWITTEREN acknowledges **occurrences** (`_acked_occurrences`), not codes.
  `_is_acked(code)` is true only for the code's *current* occurrence.
- History entries carry their `occ`. Historie and Gekwitteerd therefore show the
  ack per occurrence: an earlier trip stays gekwiteerd while its re-trip is not.
- An occurrence's ack is dropped when its last history entry (the "cleared"
  one) leaves the 256-entry ring, so the set stays bounded.
- A closed panel still observes at the same 4 Hz; only drawing waits for an
  open panel. With no LineFlow (main menu, a world being torn down) it observes
  nothing, so it does not log a PLC-000 for a plant that is not there.
- RESETTEN is **unchanged**: it still clears every ack, which re-arms faults
  that are still active. That behaviour predates this change and has not been
  ruled on.

Reference model: Apn0/TVE-micro `backend/logic.py` `_latch_alarm` (lines
202-266 at the time of reading). It dedupes only against an **uncleared** alarm
of the same type, so a re-latch is a new, unacknowledged alarm object. This is
the ISA-18.2 convention.

## What is ruled and what is assumed

- **ASSUMPTION, not a ruling:** that the real EREMA BluPort re-arms on a
  re-trip. `docs/plant/hmi_screen_inventory_2026-07-28.md` (BluPort
  Storingstabel) marks the blue-row meaning as unknown, and the EREMA manual
  extracts in `docs/plant/swi/` have no section on acknowledging alarms. Asked
  on 2026-09-24, the operator explained the word rather than the machine:
  *kwitteren* comes from German *quittieren*, "to sign for receipt". A receipt
  is signed once per delivery, which fits one acknowledgement per trip, but it
  is not a memory of how the BluPort behaves. **What would settle it:** watch
  the 3C BluPort Storingstabel when an acknowledged alarm clears and trips again
  (does its row come back red or blue?), or find EREMA's alarm-acknowledgement
  ("Störmeldungen quittieren") section.
- **RULED (operator, 2026-09-24, AskUserQuestion):** a closed panel keeps
  watching ("Yes, keep watching").

Cost of watching while closed: `_compute_faults()` measured at 29–49 µs per
call on the suite's fixture (1 filter, 0 LineFlow machines). That is **not** a
full-line measurement. There is ONE shared overlay (`Hmi.gd`,
`static var _overlay`), so the cost is one call every 0.25 s.

## The guard suite

Real parts: `HmiOverlay.tscn` opened with the real `hmi_extruder_all` scope, a
real LineFlow, a catalog `laser_filter`, and the real `EremaFaultRegistry`. The
suite operates the panel only through its own buttons (BELL, sub-tabs,
KWITTEREN, the X), and it checks what the operator sees: the rows and the bell
colour. **Stand-ins:** the upstream pressure is written through LaserFilter's
own `set_upstream_pressure_indicator()`, the setter ExtruderMachine calls while
RUNNING. A real brain cannot hold that pressure: when OFF it writes 0.0 every
tick, and RUNNING needs the 30-minute preheat plus a clogged head filter. Phase
D also writes `fed_mass` directly.

Phases: A (open panel: trip, KWITTEREN, hold 1 s, self-clear, re-trip), C
(control: acked, closed, the fault never clears, reopen → still acked), B
(acked, closed, clear + re-trip while closed, reopen → red), D (the world is
swapped under a closed panel → no PLC-000, no false INV-101).

Fixed: `Result: PASS (32 ok, 0 fail)`, 3 of 3 runs before the rebase and
again after it, 0 `SCRIPT ERROR`. After the rebase onto `fcb53e1`: parse sweep
449 ok / 0 fail, `test_hmi_ack_rearm` 7 ok, `test_die_pressure_bar` 23 ok
(#275 rescaled the laser filter's pressure anchors; the 6557 detector still
reads psi × 0.0689, so this suite's trigger is unchanged), open/close 28 ok.

Mutation matrix on the rebased tree, both suites:

| mutation | `test_hmi_fault_rearm` | `test_hmi_ack_rearm` |
|---|---|---|
| `b8bda8a` (before #275) | 25 / **7 fail**: A4 ×3, B1 ×2, B2, D1 | n/a |
| #275's overlay | 27 / **5 fail**: A4-history, B1 ×2, B2, D1 | cannot run (the port calls `_is_acked`) |
| M2 closed panel does not observe | 28 / **4**: B1 ×2, B2, D1 | 7 ok |
| M3 over-fix: every observation re-arms everything | 25 / **7**: A2 ×3, A2b, A4-history, C0, C1 | 6 / **1**: 3 |
| M4 naive: closing the panel re-arms every fault | 30 / **2**: C1, B2 | 7 ok |
| M5 a closed panel with no world logs PLC-000 | 31 / **1**: D2 | 7 ok |
| M8 the closed panel stops following `fed_mass` | 31 / **1**: D3 | 7 ok |
| M9 a re-trip reuses the old occurrence (the original bug) | 28 / **4**: A4 ×2, B1 ×2 | 5 / **2**: 4, 5 |

## Full harness — partial, and on the pre-rebase tree

Run isolated: `APPDATA` pointed at a scratch copy of the operator's userdata,
so the harness never touched the real `app_userdata` (measured: Godot 4.6.3
takes its user dir from `APPDATA`; `XDG_DATA_HOME` is ignored). Tree:
`b8bda8a` plus this change. It was **stopped after 88 steps** (in the
own-dialect loop at `test_bunker_relay_trip`) because the branch was then
rebased onto `fcb53e1`. **No full harness has run on the rebased tree.**

- `test_hmi_fault_rearm` inside the harness: `PASS (32 ok, 0 fail)`.
- `test_npc05_realworld`: red, the known expected one.
- Four reds, **all four reproduced identically with `main`'s overlay swapped
  in**, so none come from this change. The operator's live `world_layout.json`
  (modified 2026-09-24 17:15, after the 15:40 full harness) again holds one
  `structure_items` entry, a `gate`:
  - `regression verdict`: `all 1 door(s)/gate(s) sit on a wall (on-wall 0)`
  - `test_jam_baseline`: `DOORWAY fixture: WorldLayout.structure_items
    untouched (1 entries)`
  - `test_project_sweep_guards`: `B1b WorldLayout.structure_items starts
    empty (1 entries)`
  - `test_new_world_wipe`: `NEW world … PlacedObjects EMPTY (child_count=1)`
- `test_appearance_persistence` red: killed mid-run while the harness was
  being stopped (its log is the engine banner only). Re-run on the rebased
  tree: PASS, and so are the two suites after it.

## Measured and thrown away on the way

- **Two of my own additions were disproven by mutation and removed.** (1) A
  feed-baseline reset when a new LineFlow binds. Without it the suite stays
  green, because `_process` already re-baselines `_last_fed_mass` every frame,
  so a stale baseline lasts one frame. (2) Dropping a freed LineFlow at the top
  of `_process`. Without it the suite stays green with 0 `SCRIPT ERROR`: a freed
  reference reads false and `_find_line_flow()` re-binds.
- **A mutation that does not apply passes.** The first M5–M7 runs were green
  because my patch to the mutation script had silently failed, so those "PASS"
  lines were the fixed code re-tested. The mutation script now exits on an
  unknown mutation, and each run prints how many lines changed. Diff the
  mutated file before believing a mutation's green.
- **D3 was vacuous at first.** The overlay's feed baseline was 0 from the last
  reopen, so any feeding in the new world read as "fed" whether or not the
  closed panel tracked it. It only bites when the panel was last opened while
  the old world showed 5125 kg fed, which is what phase D now does.
- `NpcAutonomyBoard`'s npc-ack (`_npc_acked`) is also per code, but it is
  erased on `machine_alarm_cleared`, so it already re-arms. Nothing changed
  there.

## Open

- **Same code from two extruders is one fault.** `_compute_faults` emits
  `EREMA-6557` for every extruder whose filter trips, with only `scope`
  telling them apart. Occurrence identity (and `_fault_first_seen`, history
  and shield) is keyed by code, so a 3C 6557 that trips while an acknowledged
  3A 6557 is still active joins the acknowledged occurrence. This predates the
  change. **Found by code reading only, NOT yet measured.** A probe waits for
  the full harness run to finish, so it does not compete for CPU with its
  wall-clock suites.
- RESETTEN clearing every ack (above) is unruled.
