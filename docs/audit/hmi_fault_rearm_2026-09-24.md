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

## Follow-up — the same code on two lines is two alarms (2026-09-25)

`src/scenes/hud/HmiOverlay.gd`, guarded by
`src/tests/test_hmi_fault_per_line.tscn` (in `run.sh`'s main scene loop).

### The defect, as measured

`_compute_faults` emits `EREMA-6557` once per extruder whose filter trips, and
the overlay keyed first-seen, occurrence, history and shield by CODE. Under it
sat a second cause: `_compute_faults` read the line from `em.line_id`, and a
real `ExtruderMachine` has no such property. Its line lives on
`config_resource.line_id` (MachineBrains sets it per placeable), which is what
`_find_extruder_machine_for_scope` in the same file already read. Measured:
two real catalog brains print `'line_id' in node=false`,
`config_resource.line_id=3A` / `3C`, and both alarms came out as
`EREMA-6557@extruder`. So the two lines were identical all the way down.

Probe: `src/tests/probe_hmi_fault_code_collision.tscn`. It uses two real
catalog extruders (3A, 3C) 100 m apart, each with a catalog laser filter
beside it, and the panel operated through its own buttons, with an isolated
`APPDATA`. Each brain's SimTick handler is disconnected so it does not write
0.0 over the pressure. Measured on `main` `500af33`, and identically (with
`line_id` stand-ins) on `b8bda8a` before #275, so it predates both fixes:

| step | detected | bell | Actief | Historie |
|---|---|---|---|---|
| 1 control: 3A trips alone | 6557@extruder | **red** | 1 | 1 |
| 2 KWITTEREN | 6557@extruder | amber | 0 | 1 (gekwiteerd) |
| 3 **3C trips**, 3A still active | 6557@extruder ×2 | **amber** | **0** | **1** |
| 4 3A clears, 3C still active | 6557@extruder | amber | 0 | **1** (no Hersteld) |
| 5 3C clears | — | none | 0 | 2 (one Hersteld, "gekwiteerd") |

So the 3C trip never reached the operator. It lit no bell and got no row in
Actief or Historie, and its clear was logged "Hersteld (gekwiteerd)" although
nobody acknowledged it. 3A's own clear was never logged.

### Ruled (operator, 2026-09-24, AskUserQuestion)

- **One alarm per line**, and each row shows its line (`EREMA-6557 3C`).
- **A shield covers its own line only.** Caveat, found only after asking:
  nothing in the sim writes `_shielded_faults`. There is no Afschermen
  action; the Onderdrukt tab only lists the table. It is now keyed per line,
  so it follows the ruling if shielding is ever built. No test can exercise
  it today.

### The fix

- Every fault has a **key** (`_fault_key`): `code@line` for an EREMA alarm,
  or `code@#<instance id>` for an extruder with no line id, so two unlabelled
  extruders still raise two alarms. Plant-wide faults (INV-101, RUN-200, …)
  keep the bare code. First-seen, occurrence, the new `_fault_meta` (code +
  line of an active key), history, shield and `_is_acked` are all keyed by
  it. The KWITTEREN was already per occurrence and did not change.
- The line comes from `_extruder_line_id(em)`: `config_resource.line_id`,
  then a `line_id` on the node, then "".
- Rows carry the line, and the code column shows it (min width 90 → 120 px).
  Historie keeps it on "Hersteld" rows too. Gekwitteerd de-duplicates per
  key, so both lines' acks are listed.
- The scope of a real extruder's alarm is now `extruder_3A` where it was
  `extruder`. Measured, the tile lamps did not move: with 3A tripped, exactly
  the two EXTRUDER tiles (HOOFDMENU and OVERZICHT) show fault, the same set as
  `main`'s overlay (suite check A1).
- NpcAutonomyBoard's npc-ack is keyed by its own alarm names (`overpressure`,
  `vacuum`, …), never by overlay codes, so the change cannot reach it.

### The guard suite

`test_hmi_fault_per_line`: 26 checks, `PASS (26 ok, 0 fail)` 3 of 3 runs,
0 `SCRIPT ERROR`. Phase A: 3A trips, KWITTEREN, then 3C trips while 3A is
still active (bell red, Actief shows 3C only, Historie separate), and both
acks listed. Then 3A clears (Hersteld 3A, none for 3C), 3A re-trips while 3C
is acked (red: 3C's ack does not cover it), and Historie holds exactly the 6
transitions. Phase B blanks both configs' line id: the fallback still raises
two alarms.

| mutation | `test_hmi_fault_per_line` |
|---|---|
| K0 `main`'s overlay (`500af33`) | 15 / **11 fail** |
| K1 key = code (the defect) | 16 / **10**: A3 ×2, A4, A5, A6, A7 ×2, A8, B3 ×2 |
| K2 line read from the node only (the old read) | 19 / **7**: every line label. The alarms still separate via the fallback |
| K3 no-line fallback collapses | 24 / **2**: B3 ×2 |
| K4 Gekwitteerd de-duplicated by code | 25 / **1**: A5 |
| K5 "Hersteld" row loses its line | 24 / **2**: A6, A8 |
| K6 row label without the line | 19 / **7**: every line label |

(K1–K6 were measured before the A1 lamp check was added, at 25 checks. The
lamp check passes on the fixed and on `main`'s overlay alike, so their ok
counts would each be one higher now. K0 was measured at 26.)

Neighbours on this tree: parse sweep 451 ok / 0 fail;
`test_hmi_fault_rearm` 32 ok, `test_hmi_ack_rearm` 7 ok,
`test_die_pressure_bar` 23 ok, `test_hmi_screen_zeroing`,
`test_hmi_retired`, `test_scada_dashboard_scene`,
`test_hmi_overlay_open_close`, `test_hmi_web_gather_vals`,
`test_hmi_universal_interactive` and `test_hmi_web` PASS, all 0 `SCRIPT
ERROR`. `test_extruder_brain_wired` failed 4 checks in the empty isolated
user dir ("the world under test is CONFIGURED"). It passed 24 ok / 0 fail
against a scratch copy of the operator's userdata, so the failures were only
the missing world.

## Open

- **Every panel lists every line's EREMA faults.** Found by code reading
  only: `_compute_faults` walks all `_extruder_machines` whatever `_scope`
  the panel was opened with, so a shredder or washing panel would list an
  extruder's 6557 too. Not measured.
- **Afschermen does not exist** (above): the Onderdrukt tab reads a table
  nothing writes.
- RESETTEN clearing every ack (above) is unruled.
