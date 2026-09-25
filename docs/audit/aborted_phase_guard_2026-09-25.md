# A suite that loses a phase must not pass (2026-09-25)

Found while fixing the 3A/3B intake (`intake_3a3b_topology_2026-09-25.md` §8).
Branch `claude/aborted-phase-guard`, worktree `mystifying-franklin-db632a`, on
`origin/main` `77f075f` (#318).

## 1. What happened

With C: at **0.00 GB free**, `test_macro_edges_reload` was run twice. The log
of the second run, alone, under a scratch APPDATA on C::

```
[BuildMode] Built line_3a — 39 machines over 106.3 m in 1 leg(s)
ERROR: [AtomicFile] short write to user://__macroedgesrt___factory.json.tmp (error 13) — existing file untouched
ERROR: [BuildMode] layout NOT saved to user://__macroedgesrt___factory.json (error 13) — the previous file is untouched
SCRIPT ERROR: Trying to assign value of type 'Nil' to a variable of type 'Array'.
   at: _phase_d (res://src/tests/test_macro_edges_reload.gd:773)
  ok    : Z0 the suite's slot files are removed
  ok    : Z1 WorldLayout.layout_path_override restored
  ok    : Z2 LEAK GUARD: 13 operator files md5-identical before and after
Result: PASS (51 ok, 0 fail)
```

The same suite with its scratch APPDATA on D: prints `PASS (60 ok, 0 fail)`.
Phase D's nine checks (D0–D4, three of them per refused line) never ran, and
nothing said so.

**The mechanism.** Phase D saves a freshly built world, then crafts stale
saves out of that file. `_save_layout` returns nothing. The failed write left
no file, `AtomicFile.read_json` returned null, and
`var arr : Array = AtomicFile.read_json(...)` is a runtime error on null. A
GDScript runtime error aborts only the function it hits. `_run` does
`await _phase_d()`, which then returns as if D had finished, and goes on to
`_finish()`. `_finish` counts `_ok` and `_fails`; nobody counted phases.

**Why the harness would have passed it.** Every step of `run.sh` decides on
its log's verdict line (`Result: PASS`, `Result: N ok, 0 fail`, or a suite's
own dialect). None of them reads the `SCRIPT ERROR` line above it. CLAUDE.md
has told people since 2026-09-22 to "gate on the `Result:` line plus zero
`SCRIPT ERROR` lines", but no step did.

## 2. The fix

### 2.1 `test_macro_edges_reload`

- **D-1.** Phase D reads the save into an untyped `Variant`. It checks that the
  save landed and reads back as an Array with more than the version marker.
  If it did not, the phase returns and names the reason. Phase A already
  worked this way (A1 reads `saved` as a `Variant`).
- **Z3.** Each phase records that it reached its LAST line (`_phases_done`),
  and `_finish` asserts all of `["A", "B", "C", "D"]`. A phase cut short by
  anything, the next runtime error included, now turns the verdict red and is
  named.

### 2.2 `run.sh`: the SCRIPT ERROR census

`tools/regression/script_error_census.sh <out_dir> <marker>` runs as the last
step. `run.sh` touches `out/.run_start` right after creating the out dir.
The census reads every `*.log` newer than that marker, because the out dir is
never cleared: an mtime filter keeps stale logs out, where a name list would
not. Any log with a `^SCRIPT ERROR` line fails. The census names the log and
quotes its first error. Lines end in `\r\n` on Windows, so they are stripped
before anchoring.

- **One log is excused, by name:** `parse_sweep.log`. The sweep compiles
  every file in one boot, so autoload identifiers fail there by construction.
  It has its own detector (`^RESULT: PASS`), gated earlier.
- **Nothing else is excused.** A log with noise gets its suite fixed (§2.3),
  not a place on a list.
- A census that read no log at all fails.

### 2.3 `test_route_goal_clearance`: the one other log with SCRIPT ERROR lines

The census, run over the 132 logs of the full harness of 16:01 today, named
exactly one log besides the excused sweep:

```
FAIL  : route_goal_clearance.log carries 2 SCRIPT ERROR line(s) … First: SCRIPT ERROR:
  Compile Error: Identifier not found: EventBus    at: GDScript::reload (res://src/scenes/vehicles/BaseVehicle.gd:1998)
script error census: 132 log(s) of this run read, 1 with SCRIPT ERROR lines, 1 excused (parse_sweep.log)
```

That log also says `ERROR: Failed to load script
"res://src/tests/test_route_goal_clearance.gd" with error "Compilation
failed"`. The suite named `BaseVehicle.NPC_ARRIVE_TOL`, a class whose script
uses the `EventBus` autoload. A `--script` suite is compiled once before the
autoloads exist, and that compile fails. The 15 checks still ran afterwards,
so here the lines were noise, but they are the same lines a real abort
prints. Now the constant is read at runtime through
`load(...).get_script_constant_map()`, with a check that it resolved (16
checks). Run as `run.sh` runs it: `Result: 16 ok, 0 fail, 0 skip`, 0
`SCRIPT ERROR` lines, `NPC_ARRIVE_TOL` 2.20 m as before.

## 3. Proofs

### 3.1 The census, on fabricated logs and on real ones

| case | result |
|---|---|
| T1 the 132 real logs of today's 16:01 full harness | exit 1, names `route_goal_clearance.log` (2) only; `parse_sweep.log` excused |
| T2 clean logs, `no SCRIPT ERROR above` mid-line (as `test_map_labels` prints), a SCRIPT ERROR in `parse_sweep.log`, one in a log OLDER than the marker | exit 0, 3 read, 0 bad, 1 excused |
| T3 a CRLF log with the exact phase-D abort and `Result: PASS (51 ok, 0 fail)` | exit 1, named, first line quoted |
| T4 no log newer than the marker | exit 1, "the census read nothing" |
| T5 a missing out dir | exit 2, usage |

### 3.2 The suite

Each variant writes a mutated suite over the file (from the fixed suite or the
original `.bak`), runs it under a scratch APPDATA on D:, runs the census over
that run's log the way `run.sh` does, and restores the fixed file (md5 checked
after every run). "Save missing" makes phase D read `FACTORY_PATH + ".missing"`:
exactly what the failed write left, no file.

| # | variant | suite verdict | `^SCRIPT ERROR` | census |
|---|---|---|---|---|
| BASE | fixed suite, unmutated | **PASS (62 ok, 0 fail)**: 60 + D-1 + Z3 | 0 | exit 0 |
| R0 | ORIGINAL suite, phase-D save missing (the measured failure) | **PASS (51 ok, 0 fail)**, reproduced | 1 | **exit 1** |
| R1 | fixed suite, phase-D save missing | **FAIL (51 ok, 2 fail)**: D-1 (`-1 entries`), Z3 names D | 0 | exit 0 |
| R2o | ORIGINAL suite, a runtime error at the top of phase C | **PASS (46 ok, 0 fail)**, a second vacuous green | 1 | **exit 1** |
| R2 | fixed suite, the same error in phase C | **FAIL (47 ok, 1 fail)**: Z3 names C | 1 | **exit 1** |
| R3 | fixed suite, phase D's completion mark removed | **FAIL (61 ok, 1 fail)**: Z3 | 0 | exit 0 |

The two layers cover each other:

- R0 and R2o: the census alone catches an abort in a suite that counts no
  phases, which is every other suite.
- R1: the suite alone turns a failed save red without any runtime error.
- R2: both fire.
- R3: Z3 is not satisfied by default.

## 4. Full harness

**Not run by this session, per the operator ruling of 2026-09-25 ("One
harness runner", CLAUDE.md, landed in #317 while this was being written).** The
designated runner session tests `main` after the merge. What this session ran
instead, one at a time under a scratch APPDATA on D::

- `test_macro_edges_reload`: 62 ok (BASE above);
- `test_route_goal_clearance`, exactly as `run.sh` runs it: 16 ok, 0
  `SCRIPT ERROR`;
- the parse sweep;
- `bash -n tools/regression/run.sh`.

The census itself was measured on two real sets of full-harness logs, read
only:

| logs | census |
|---|---|
| this worktree's full harness of 16:01 (`a4b2031` + the intake fix), 132 logs | 1 bad: `route_goal_clearance.log` (fixed here); `parse_sweep.log` excused |
| the harness runner's full run of `main` `3a00ddb` (18:24 → 19:02, #317), 134 logs, read after it released its lock | 1 bad: `route_goal_clearance.log` (the same 2 lines; fixed here); `parse_sweep.log` excused |
| `test_extruder_start_interlock`, the one suite `main` wired after `3a00ddb` (#313), run alone | `PASS (32 ok, 0 fail)`, 0 lines |

So once this lands, the runner's next run should show the census step green,
with `route_goal_clearance.log` clean. Any other log that turns up with a
`SCRIPT ERROR` line is a real finding for the operator.
