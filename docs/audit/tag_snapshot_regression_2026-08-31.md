# 2026-08-31 — test_tag_snapshot doseersilo red: bisect, mechanism, fix

**TL;DR.** The 2026-08-31 wave turned `test_tag_snapshot` red (27 ok, 2 fail:
`scada/3c/info/1/em/status` false, `em/snelheid` 0 — the 3C doseersilo, no
MotorOverload trip). Bisect (good `d459ad0`, bad `32a35ce`) lands on
**`5382cca`** — "Fix LineFlow rotor/film-field discovery". That commit made
`_find_mechanisms` actually find rotors for the first time, which **activated a
gate that had been dead since birth**: `_mech_fraction()` scales conveying by
`RotatingMechanism.current_rpm()`, a value that only advances in `_process` —
**frame time** — while the test drives `LineFlow.tick(0.1)` 400× in a tight
loop with **zero frames**. Every rotor-bearing stage conveyed 0.000×, the
force-fed doseersilo crossed `OVERLOAD_KG` (250) at ~31 s, and the
buffer-overload e-stop (not a MOL trip) cut its power. Fixed by reading the
rotor's **commanded** rpm (new `RotatingMechanism.commanded_rpm()`, pure sim
state) in `_mech_fraction`. Proven red→green both directions, commit-level and
line-level, and confirmed 2026-09-02 in the full harness on the operator
checkout at `dc017bb` + fix: `test_tag_snapshot` 29 ok / 0 fail, six reds
where the pre-fix canonical run had seven, no new ones.

## The signature

```
FAIL : (a2) every em/status row reads TRUE after start_line + 40 s, except 0 explained
       by a MotorOverload trip (19 true / 20 rows; unexplained false:
       ["scada/3c/info/1/em/status (doseersilo)"])
FAIL : (a2) every em/snelheid row reads > 0 (19 of 20)
```

Plus, higher in the log (the tell): `[LineFlow] E-STOP: overload at
'doseersilo' — upstream stopped, downstream emptying.` and in the dump
`estop_fault_key: "L3C.1"`, `line_status: "Fault"`, unit-1 `niveau: 320.0` —
i.e. **every gram fed in 40 s (8 kg/s × 40 s) still sitting in the silo;
nothing moved.**

## Bisect — measured, every step

Environment: detached worktree `D:/cedo_bisect_tagsnap` (assets junctioned),
**isolated `APPDATA` seeded with a copy of the operator's
`app_userdata/CeDo Simulator`** (caches excluded), probe keyed off the printed
verdict (never the exit code — the ~24 % teardown segfault exits 139, which
`git bisect run` would treat as abort).

| rev | verdict |
|---|---|
| `d459ad0` (good anchor) | PASS — 20/20 em/status true |
| `f8396cc` | FAIL, doseersilo signature |
| `9f714aa` | FAIL, doseersilo signature |
| `c020cf2` | FAIL, doseersilo signature |
| `d059007` | FAIL, doseersilo signature |
| `822c9a5` (= `5382cca^`) | **PASS — 20/20** |
| `5382cca` | **FAIL — first bad commit** |
| `32a35ce` (bad anchor) | FAIL, doseersilo signature |

Also relevant: the net `src/sim/LineFlow.gd` diff over the whole
`d459ad0..32a35ce` range is **exactly `5382cca`'s two-function change**
(`_find_mechanisms` + `_find_film_field` going recursive) — the PR #179 tick
refactor and the #182 `_discover` helper netted out to zero in that file.

### TRAP — the bisect baseline depends on user://

With an **empty** isolated `user://`, `d459ad0` shows the **same doseersilo
signature** (a look-alike red from the legacy-spawn world, measured, separate
cause) — a naive clean-environment bisect would have classified every commit
bad and converged on garbage. The good anchor is only green against the
operator's world data. Any future bisect of a world-booting suite must seed the
isolated `APPDATA` from the operator's `app_userdata` first.

## Mechanism — measured with `src/tests/probe_tagsnap_mech.tscn`

The probe boots MainWorld, builds `line_3c`, feeds the heads at the test's
8 kg/s, and drives 400 ticks in three modes
(`-- [frames|nomech|census|census_frames]`), all at `5382cca`:

| mode | cadence | mech gate | result |
|---|---|---|---|
| A | tight loop (as the test) | live | auger `current_rpm` **0.00 all run**, frac 0.000, buffer 8 kg/s → **e-stop 'doseersilo' t≈31 s** |
| B | 1 frame per tick | live | augers ramp to 60 rpm, frac 1.000, doseersilo **drains** (buffer 0.2 by t=25) |
| C | tight loop | `nd["mech"]` nulled | **no e-stop**, powered, buffer 217 (= fed 8 vs rate 6 after PLC power-up ~21 s) |

Census (mode `census_frames`): every rotor `5382cca` discovers is a genuine
conveying rotor with `rpm_setpoint == nominal_rpm` (doseersilo 3× auger 60/60,
mill 120/120, flotation tank 12 rotors 9/5/4, blowers 220/220, …) — so the
commanded fraction is 1.0 everywhere, i.e. the pre-`5382cca` flow numbers are
restored exactly by the fix below.

Why only the doseersilo trips: every stage stalls (frac 0), but only *fed*
heads accumulate, the e-stop detector walks PLC stages in order and trips on
the **first** buffer > 250, and L3C.1 is stage 0. The e-stop then forces
`powered = false` on the fault + upstream — one machine, hence 19/20.

Why the game never shows this: production drive is `LineFlow._process(delta) →
tick(delta)`, one tick per frame — the rotor ramp and the sim always advance in
lockstep in-game. Only frame-less tick-driving (headless suites, any
fast-forward) diverges.

## The fix

`src/sim/RotatingMechanism.gd` — new `commanded_rpm()` (capped setpoint, 0
while not running; pure sim state), `_process` and `snap_to_rpm` refactored
onto it (identical behaviour, one source of truth).
`src/sim/LineFlow.gd:_mech_fraction` — reads `commanded_rpm()` instead of
`current_rpm()`.

Semantics kept: a stopped/tripped rotor still gates to 0 (`set_running(false)`
→ commanded 0); a per-rotor HMI setpoint still bites (`set_target_rpm` writes
the commanded rpm); spin-up lag is still modelled — in **sim** time — by
`nd["spin"]` (SPIN_UP_S). What changes in-game: material flow no longer lags
the ~1.2 s *visual* ramp on top of the spin gate. The visual ramp itself is
untouched.

## Proof, both directions

* Commit-level: `822c9a5` PASS → `5382cca` FAIL (table above).
* Operator checkout, real `user://`, `32a35ce` + fix: **29 ok, 0 fail, PASS**
  (was 27 ok, 2 fail).
* Mutation: with everything else in place, reverting the ONE call in
  `_mech_fraction` back to `current_rpm()` → **27 ok, 2 fail**, identical
  doseersilo signature; restoring → green again.
* **Authoritative full harness, 2026-09-02: the operator checkout at `dc017bb`
  (main after #189) + this fix.** `== done (exit 1) ==`, 54 suite logs,
  **`test_tag_snapshot` 29 ok / 0 fail / PASS in-harness**, and **six** reds —
  exactly the seven that PR #190 measured pre-fix at `32a35ce`, minus this one.
  🔑 **The fix removes one red and introduces none**, across a main that had
  since gained #189's nine new suites (all nine PASS).

  | red | attribution |
  |---|---|
  | `regression verdict` ("all 1 door(s)/gate(s) sit on a wall (on-wall 0)", 17 ok 1 fail 1 skip) | pre-existing; identical with the fix reverted, and identical on a clean D: worktree — so NOT local tree state, contra PR #190's note |
  | `test_nav_connectivity` | known red (CLAUDE.md 08-30) |
  | `test_jam_baseline` (jam1/jam3 `stalled`, forklift 57.34 m off, limit 3.5) | **a real 2026-08-31 wave regression** — red on the operator checkout in PR #190's canonical pre-fix run, green 08-30. Byte-identical with this fix reverted, so this fix is cleared of causing it; the cause is elsewhere in the wave (suspects `d059007` / `1ece58a`, the maalmolen rebuild and stair move). A concurrent session's unfinished fix attempt sits, unpushed, on `wip/gate-carve` |
  | `test_npc05_realworld` | known red, do not silence |
  | `test_line3b_flow_conformance` | known red |
  | `test_project_sweep_guards` (`B1b WorldLayout.structure_items starts empty (1 entries)`) | known red; local `user://` world state |

  🤮 Correction to this document's first version: the harness proof cited
  above used to read "`32a35ce` + only this fix" and was run in
  `D:/cedo_bisect_tagsnap`. That worktree never left `5382cca` — a
  `git checkout --detach 32a35ce` had failed with its output suppressed — so
  the 08-31 harness evidence was gathered at **`5382cca` + fix**, one commit
  after the first bad commit, not at main. The 2026-09-02 operator run above
  replaces it. The same slip is why the `test_jam_baseline` row previously
  called that suite "sandbox-environmental": at `5382cca` the operator's
  08-31 red was invisible.

  Free intel on the other two 08-31 wave candidates from
  `review_findings_2026-08-31.md`: in this same run **`test_feeder_fetch`
  PASSes** and **no spawn-clearance/MastLift red appears** — both look
  user://-/tree-state-dependent, not code regressions.

  The operator-checkout harness could NOT be used as the proof on 2026-08-31:
  it aborted in the parse sweep on `src/tests/test_gate_carve.gd` ("already a
  variable named \"oid\"" — the in-flight, uncommitted gate-work edit of a
  concurrently active session, the same no-block-scoping collision class as the
  08-29 `var shell` merge). That file was deliberately left untouched for 54 h.
  On 2026-09-02, on Arie's instruction, those three files were committed
  verbatim to the unpushed branch `wip/gate-carve` (`0063f6c`) so the operator
  tree became runnable again; the parse sweep then passed and `test_gate_carve`
  itself returned 11 ok / 0 fail. Recovering that work means switching to
  `wip/gate-carve` and renaming the second `oid`.

### TRAP — `run.sh` ignores your worktree unless you say otherwise

`tools/regression/run.sh` defaults `PROJ` and `UD` to the operator's absolute
paths (`run.sh:22-23`). Run from a worktree with no overrides, it imports,
parse-gates and sweeps **the operator checkout**, not the tree you are standing
in — measured 2026-08-31: a D:-worktree invocation failed on the operator
tree's dirty `test_gate_carve.gd`. A worktree harness needs all three:

    APPDATA='D:\<isolated>' PROJ='D:/<worktree>' UD='D:/<isolated>/Godot/app_userdata/CeDo Simulator' bash tools/regression/run.sh

## Observed while measuring, NOT fixed here

1. **`lump_cart_spot` overload under frames+force-feed** — in probe mode B the
   e-stop still fires, from `lump_cart_spot` (the yellow floor paint is a
   LineFlow *process* node in the PLC chain, rate 6). Measured at **`822c9a5`
   too** — pre-existing, unrelated to `5382cca`, and unreachable by the real
   suite (which never pumps frames mid-drive) or by in-game feeding (only real
   heads get bales). Worth a look the day the lump chain becomes load-bearing:
   why is floor paint a powered process stage?
2. **The test's "MATERIAL MOVED" check passes on a pile-up.** In the red run,
   `flow_positive` was satisfied by unit 1's `niveau` = 320 — material that
   *sat* there. A stalled line with a fed head still clears `flow_positive >
   0`. If that check is ever revisited, count only rows that require material
   to *leave* a machine (throughputactual / waterflow), not level gauges.
3. **Operator checkout carried unrelated uncommitted edits from a LIVE
   session** during this work (`src/build/Gate.gd`, `src/build/PlaceableCatalog.gd`,
   `src/tests/test_gate_carve.gd`, mtimes 06:00 on 2026-08-31 — in-progress
   gate-carve work). Left untouched for 54 h, then parked verbatim on
   `wip/gate-carve` (`0063f6c`, unpushed) on 2026-09-02 so the harness could
   run. Their `test_gate_carve.gd` hunk re-declares `oid` inside `_ready`
   (existing `var oid` at :197 vs new `for oid in` at :226) and therefore does
   not parse, which **blocked the whole harness at the parse gate** for those
   54 h. That work is unfinished and its own comment says it is the
   `test_jam_baseline` fix; it needs the rename plus a measurement before it is
   worth anything. It cites `docs/audit/jam_baseline_bisect_2026-08-31.md`,
   which exists in no worktree.
4. **`.uid` sidecars for tracked scripts were untracked locally** and would
   have blocked the checkout onto `dc017bb` (which tracks five of them). All
   five were byte-identical to the tracked versions; they were moved aside, not
   deleted, and git then materialised the tracked copies.

## Files

* Fix: `src/sim/RotatingMechanism.gd`, `src/sim/LineFlow.gd`
  (`.bak_tagsnap_20260831` copies beside both, outside git).
* Probe: `src/tests/probe_tagsnap_mech.tscn` (+ `.gd`), committed with the fix
  so this document keeps pointing at a file that exists — modes:
  `<godot> --headless --path . res://src/tests/probe_tagsnap_mech.tscn -- [frames|nomech|census|census_frames]`
  It is not in `run.sh`'s allow-list and is never run by the harness.
* Branch: `fix/tag-snapshot-commanded-rpm`, based on `dc017bb`.
* Full harness log for the 2026-09-02 proof run lives outside the repo, in the
  session scratchpad; `tools/regression/out/*.log` holds the per-suite logs it
  produced.
* Bisect worktree (removable, still detached at `5382cca`):
  `D:/cedo_bisect_tagsnap`, isolated user data at `D:/cedo_bisect_userdata`.
