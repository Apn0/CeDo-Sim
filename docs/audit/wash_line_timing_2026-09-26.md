# 3B's wash line: the dosing screw meters it, the line holds 3 min, and a stopped screw takes nothing (2026-09-26)

Rulings: `docs/plant/operator_rulings_2026-09-26.md` W1-W7 (recollections,
CLAIMED; every number PLACEHOLDER until the operator corrects it).
Code: `LineFlow.WASH_TIMING`, `_index_wash_timing`, the direct feed
(`SILO_FEED_STOP_ALSO` comment). Guards: `test_wash_line_timing` (new) and
`test_extruder_silo_feed_stop` S3 (re-derived).

## 1. How it started

The task was to re-derive `test_extruder_silo_feed_stop` S3 so it stops
resting on a frame tick (`docs/audit/lineflow_set_process_2026-09-26.md` §6):
S3 allowed < 1.0 kg into the stopped 3B dosing screw M11a and measured
0.96–1.20 kg by tick phase. Asked what S3 should assert, the operator
questioned the model under it: on 3B material takes ~10 min from the VSS
dosing screw to the extruder silo, and a full VSS runs the line ~15 min.

Measured with `src/tests/probe_3b_residence.tscn` (new), before the change
(Godot 4.7.2, 3B alone, LineFlow ticked by hand, isolated `APPDATA` on D:):

| | before | ruled | after |
|---|---|---|---|
| M11a (VSS dosing screw) conveys | 6 kg/s = 21 600 kg/h, the MachineFlow default | 19 kg/h per rpm, HMI setpoint, new line 50 rpm | 950.0 kg/h at 50 rpm, 1520.0 at 80 (master slider) |
| first kg at the extruder silo after the VSS / M11a starts | 38.8 s | ~3 min (W3) | 176.3–176.8 s after M11a first moves |
| kg in the wash line at 950 kg/h | 9.6 kg | ~3 min of feed = 47.5 kg | 56.1 kg with process water (probe, at 400 s) |
| a full VSS, no supply | 150 kg, empty in 15.0 s at 36 000 kg/h | 15 min of M11a at 50 rpm | 237.5 kg, empty in 898.2 s = 14.97 min at 950 kg/h |
| extruder silo 100 % | 150 kg | 17.5 min of M11a at 50 rpm | 277.1 kg |
| M11a's input after the silo stops it | +0.96–1.20 kg, by tick phase | 0 (W2.1) | 0.079 → 0.000 kg (it only drains), at k = 0..3 |

The first answer was "~10 min". It did not fit with his silo answers (a
silo that 15–20 min of feed fills, overshooting to 114–120 % when the
wash line empties onto it with the compactor belt stopped): 10 min of feed
would read ~157 %. Shown that, he chose "the line holds less": 14–20 % of
17.5 min, built as 3 min (rulings W3). The suite now measures the overshoot
at 114.3 %, inside his 114–120 %, from the model and not from a typed
number.

## 2. What was built

All in `src/sim/LineFlow.gd`, for the lines in `WASH_TIMING` (only
`line_3b`; 3A "differs", line 1 and 3C are later, rulings W5):

- **The meter.** The silo's feed stop (`SILO_FEED_STOP`, M11a on 3B) gets
  `rate` = 19 kg/h x 100 rpm and `rpm_pct` = 0.5 when its node is new. The HMI's
  master slider already sets `rpm_pct` (0..`_machine_max_rpm`, now 100 for the
  meter); a survivor and a loaded save keep their own value. M11a has no
  rotor, so its rate is linear in `rpm_pct` (see §5 for the machines that do).
- **The holds.** `_index_wash_timing` (every rebuild, after `_link` and before
  `_init_pipes`) finds the machines between the meter and the silo (reached
  from the meter without passing the silo, and reaching the silo), gives each
  non-tank 5 s and the blowers and cyclones 0 s, takes the fastest way
  (connectors' geometry transit plus those holds, Dijkstra) and gives the
  tanks the rest of 180 s: the flotation tank 2/3, the rafter 1/3. On 3B:
  connectors 38.3 s, 8 x 5 s, flotation tank 71.1 s, rafter 35.6 s.
- **Where a hold lives.** On the machine's out-connectors: `_init_pipes` adds
  the hold to the travel time and cuts the connector into 1 s stages
  (`HOLD_STAGE_S`) instead of 6; every other connector is built as before. A
  hold connector advances with its source's `spin`, so a stopped machine keeps
  what it holds. Because the kg ride the connectors, the ledger
  (`pipe_mass`), `rebuild()`'s `_carry_pipes` and the save's per-edge pipes
  carry them with no new code.
- **The direct feed** (3A and 3B, rulings W5): every edge from a
  `SILO_FEED_STOP_ALSO` body (the VSS) into its feed stop is `direct`. The VSS
  conveys no faster than the screw (`direct_to`), so a surplus waits in the
  VSS, and the connector moves nothing while the screw is not powered, so
  nothing more enters a stopped screw.
- **The sizes.** `full_kg` on 3B's VSS (237.5 kg) and extruder silo
  (277.1 kg): the level sensor's %, the silo's level windows and the "both
  VSS full" check read it. A vessel's overload e-stop keeps today's ratio to
  its size (`_overload_kg`, 250 : 150, PLACEHOLDER): the silo at 114 % holds
  317 kg, past the flat 250 kg.

## 3. Measured

Godot 4.7.2, one Godot per suite, each on a fresh mirror of the operator's
`app_userdata` at `D:\cedo_archive\userdata\session_feed_stop_s3_2026-09-26\`
(his real `world_layout.json` md5 `e046af7d…` checked before and after).

**`test_wash_line_timing`** (new, 13 checks), `PASS (13 ok, 0 fail)`:

| check | measured |
|---|---|
| W3 the holds the rule derives | fastest way 180.0 s: connectors 38.3 s, 8 machines x 5 s, flotation tank 71.1 s = 2 x rafter 35.6 s |
| W6 sizes | VSS 237.5 kg, silo 100 % at 277.1 kg |
| W8 3A unchanged | 0 holds, 0 resized, M11a at 6.0 kg/s; its VSS → M11a edge is a direct feed |
| W1 the meter | HMI 0..100 rpm, starts at 50; 950.0 kg/h at 50 rpm, 1520.0 at 80 |
| W2 the surplus in the VSS | fed 1600 kg/h: the VSS gains 650.0 kg/h; M11a's input at most 0.238 kg (one landed stage), below the 0.976 kg on the connector into it |
| W3 plug flow | M11a first moves at 27.0 s; the first kg reaches the silo 176.3 s later, 0.000 kg before 170 s |
| W4 M11a stops | the silo keeps receiving for 169.7 s (3 min less M11a's own 8.4 s connector, which keeps its 2.0 kg) |
| W5 a stopped tank | the flotation tank's 27.43 kg stays to the gram for 30 s while its input backs up 1.35 → 11.97 kg |
| W7 a rebuild | 80 rpm kept, the same holds, 64.049 kg on the connectors before and after |
| W6 a full VSS | 237.5 kg feeds the line 898.2 s = 14.97 min |
| W9 the ledger | balances to 0.000000000 kg with what the suite put in and took out |

**`test_extruder_silo_feed_stop`**, now with LineFlow's `_process` off,
`PASS (17 ok, 0 fail)` (before, on frame time: 17 ok, S3 at +0.957 kg; with
`_process` off and the old model: S3 red at +1.123 kg):

| | before (old model) | after |
|---|---|---|
| 3B PCU pot full | 309 s | 469 s |
| 3B silo at 100 %, feed stopped | 957 s | 1666 s (27.8 min; 3B now fed 30 min, line 1 still 20) |
| 3B peak after the stop | 106.0 % | 114.3 % (his 114–120 %) |
| the backlog in the VSS | 63.5 kg | 40.5 kg |
| S3, M11a's input after the stop | +0.957 kg (< 1.0 by one frame tick) | 0.079 → 0.000 kg |
| line 1 | 100 % at 872 s, hopper 86.9 kg | 863 s, 89.6 kg |

Feeding line 1 30 min as well piled 248 kg into its paused shredder's hopper
(overload 250 kg) and S5 went red on it; line 1 keeps its 20 min.

**`probe_feed_stop_pre_ticks -- k`** (the frame ticks the suite used to get,
replayed by hand): S3 PASS at every k.

| k | sensor clock after rebuild | stop | M11a input at the stop → end | on the chute, waiting with the VSS |
|---|---|---|---|---|
| 0 | 0.00 s | 1666.0 s | 0.079 → 0.000 kg | 1.135 kg |
| 1 | 0.10 s | 1665.9 s | 0.106 → 0.000 kg | 1.108 kg |
| 2 | 0.20 s | 1665.8 s | 0.132 → 0.000 kg | 1.082 kg |
| 3 | 0.30 s | 1665.7 s | 0.158 → 0.000 kg | 1.056 kg |

**Other suites.** Every `run.sh` suite that builds 3A or 3B, touches a VSS,
boots MainWorld or makes a LineFlow (74 besides the feed-stop suite), one at
a time on this tree: 71 PASS and 3 red. Every one has a log under `logs\after_wash\`; the list is
`affected_list.txt` in the session folder.

- `test_rebuild_pipe_carry`: `FAIL (14 ok, 4 fail)`. Its fixture fed 3B for
  60 s, and with the 3-min hold only 3 connectors were loaded by then (S0 wants
  8), the plasmaq → cyclone edge was empty (F1), and no machine had kg on both
  sides (B0). The model was right and the fixture was too short. It now feeds
  `wash_timing("line_3b").first_kg_s` + 60 s: `PASS (26 ok, 0 fail)`, and the
  rebuild carries 59.4 kg over 18 edges (9.7 kg over 3 before), the tanks'
  holds included.
- `test_machine_sounds`: S8, the panel beep race recorded in
  `docs/audit/lineflow_set_process_2026-09-26.md` §8 (a 0.366 s clip against
  a 0.4 s frame-time timer; no LineFlow in it). Re-run twice: once `PASS
  (80 ok)`, once S8 red again.
- `test_npc05_realworld`: the known expected red (CLAUDE.md), `FAIL (10 ok,
  1 fail)`, unchanged.

Suites that pass through the change with numbers worth naming:
`test_fallback_chains` 110 ok, `test_macro_edges_reload` 62 ok,
`test_plant_resume` 62 ok (on the tree before `main`'s census-fix edit of it; 65 ok
after the rebase, below), `test_extruder_silo_chain` 41 ok (it feeds the blower
before the silo, so the wash line's hold is not on its path),
`test_extruder_start_interlock` 32 ok, `test_jam_baseline` 20 ok / 0 skipped,
`test_nav_connectivity` 13 ok.

**After the rebase.** On `31a9a80` (with `main`'s census fix in
`test_plant_resume`): `test_plant_resume` 65 ok, `test_wash_line_timing` 13 ok,
`test_extruder_silo_feed_stop` 17 ok, `test_rebuild_pipe_carry` 26 ok. Then
onto `5c156d8`, i.e. #332 (the frictiewasser's rate; its `RATE_NOT_BY_RPM`
branch now sits in `_eff_rate`, operand order unchanged) and #333:
`test_frictiewasser_rate` 22 ok, `test_wash_line_timing` 13 ok,
`test_extruder_silo_feed_stop` 17 ok, `test_rebuild_pipe_carry` 26 ok,
`test_plant_resume` 65 ok, `test_extruder_silo_chain` 41 ok,
`test_fallback_chains` 110 ok, all with 0 `SCRIPT ERROR` lines; the four
stdlib gates exit 0, the parse sweep 494 ok / 0 fail, `bash -n run.sh` OK
with one main loop, and the operator's `world_layout.json` md5 is unchanged.

## 4. Mutation matrix

Not run yet when the PR was opened; it follows as a commit on this branch
(`mutate.py` in the session folder: 15 mutations, one at a time, md5 restored
after each).

## 5. Found on the way, not fixed

- **The HMI rpm setpoint squares the rate of a machine with a rotor.**
  `set_machine_rpm_pct` sets `rpm_pct` and every rotor's rpm, and
  `_tick_process_machines` multiplies by both `rpm_pct` and `_mech_fraction`
  (the rotor's commanded / nominal rpm). Measured with
  `src/tests/probe_rpm_pct_rate.tscn` at 0.50: the rafter, flotation tank,
  dewatering screw and blower moved 0.250 of design, the rotor-less
  transport_screw 0.500. M11a has no rotor, so its metering is linear. A
  parallel session took it up the same day, and the operator ruled it KNOWN,
  KEPT ("don't touch the base"; `docs/audit/hmi_rpm_rate_2026-09-26.md`, from
  that session). On the meter (`probe_3b_residence.tscn -- slider`): the
  master rpm slider is linear (50 → 950 kg/h, 80 → 1520 kg/h), but the
  MACHINES screen's "drive" row multiplies on top (drive 50 → 475 kg/h; then
  master 100 → 950 kg/h). Asked, the operator kept that for the meter too
  ("Leave it", rulings W6). `test_wash_line_timing` W1 measures the master
  slider, and turns red if the meter gains a rotor.
- **Every connector moves at 1.3 m/s**, pneumatic runs included: 3B's 15 m
  plasmaq → tussenventilator pipe takes 12.4 s of the 180 s.
- **The first kg arrives a few seconds early** (176.3–176.8 s of 180 s): every
  connector's phase runs from the rebuild on, so a first parcel waits less
  than a whole stage on each of the 13 connectors.

## 6. Files

- `src/sim/LineFlow.gd`: `WASH_TIMING`, `HOLD_STAGE_S`, the node fields
  `hold_s` / `full_kg` / `direct_to` / `meter_rpm_max`, `_index_wash_timing`,
  `_reach`, `_first_kg_s`, `_full_kg`, `_overload_kg`, `wash_timing()`,
  `_edge_geo_transit`, `_eff_rate` (the old inline rate, moved, unchanged);
  `_index_silo_feed_stops` now runs before the pipes.
- `src/tests/test_wash_line_timing.gd` / `.tscn` (new, in `run.sh`).
- `src/tests/test_extruder_silo_feed_stop.gd`: S3 = 0 kg, LineFlow off frame
  time, 3B fed 30 min (line 1 still 20), S1 against the silo's own 100 %.
- `src/tests/probe_3b_residence.gd`, `probe_rpm_pct_rate.gd` (new probes),
  `probe_feed_stop_pre_ticks.gd` (S3 = 0, the suite's feed times).
- `docs/plant/operator_rulings_2026-09-26.md` (new).
- Logs, the runners and `mutate.py`:
  `D:\cedo_archive\userdata\session_feed_stop_s3_2026-09-26\`.
