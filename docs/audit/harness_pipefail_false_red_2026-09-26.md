# Two false reds in the first full harness on Godot 4.7.2 (2026-09-26)

The harness runner (the session the operator named on 2026-09-26 18:00) ran
the first full harness on 4.7.2, on `origin/main` `5c156d8`:

| | |
|---|---|
| result | `== done (exit 1)`, 151 sections, 59 min (18:22:34 → 19:21:11) |
| logs | 140 by mtime, 0 `^SCRIPT ERROR` (census), 0 timeouts |
| world_layout sentinel | untouched by every step |
| real red | `test_npc05_realworld` (expected, the DRIVE_TO_INDOOR stall) |
| **false reds** | `test_layout_load`, `test_new_world_wipe`: `FAIL : … verdict printed but ZERO checks ran (vacuous)` |

The runner's record: `D:\cedo_archive\userdata\harness_runner\runs.tsv` and
`run_5c156d8_20260926-182234.log`.

## 1. The two suites did run their checks

Their own logs say `Result: 22 ok, 0 fail, 0 skip` and `Result: 11 ok, 0 fail`,
with 22 and 11 `  ok` lines. `run.sh`'s own-dialect loop said the opposite.

## 2. Cause: `tr | grep -q` under `pipefail`

`run.sh` runs under `set -uo pipefail` (line 16). The loop checked each log
with

    tr -d '\r' < "$OUT/$t.log" | grep -aqE '^  ok'

`grep -q` exits at its first match. `tr` still has output to write, dies of
SIGPIPE, and pipefail makes the pipeline's status 141, which `!` reads as "no
`  ok` line". This needs two things at once:
- a log bigger than the 64 KB pipe buffer, so `tr` is still writing;
- a match early in the log, so grep quits before `tr` is done.

A verdict check is safe by luck: its line is at the END, so grep reads
everything before it matches.

Measured on the run's own logs, the loop's decision (verdict → `  FAIL` →
`  ok`) repeated 10 times with the old checks and with the new `log_has`.
M1-M3 are mutants of `test_layout_load.log`: an early planted `  FAIL` line,
every `  ok` line removed, and the `Result:` line removed.

| log | bytes | expected | old, 10 runs | new, 10 runs |
|---|---|---|---|---|
| test_layout_load.log | 169 942 | GREEN | 3 GREEN, **7 zero-checks** | 10 GREEN |
| test_new_world_wipe.log | 168 386 | GREEN | 1 GREEN, **9 zero-checks** | 10 GREEN |
| test_world_layout_coords.log | 4 818 | GREEN | 10 GREEN | 10 GREEN |
| M1 early `  FAIL` | 167 805 | FAIL line | **10 zero-checks** (the FAIL check missed it) | 10 FAIL line |
| M2 no `  ok` | 166 001 | zero checks | 10 zero-checks | 10 zero-checks |
| M3 no verdict | 167 745 | verdict missing | 10 verdict missing | 10 verdict missing |

The same pipe sat at two more sites, both verdict checks that found their line
10 of 10 times both ways: the parse sweep (53 510 B) and spawn clearance
(NOLINE 169 222 B, LINE 169 151 B).

The loop's three pipes date from `c02e943` (2026-09-21), the two verdict pipes
from `d93681d` (2026-09-13). The logs they check were small until now: 28 KB on
4.6.3 (2026-09-25).

## 3. Why the logs grew: the 4.7.2 blend-point warning

4.7 prints a WARNING, with a GDScript backtrace, for every
`AnimationNodeBlendSpace2D.add_blend_point()` call without a name.
`Humanoid.gd` adds five unnamed points per humanoid rig, so every world boot
printed it 140 times. The 4.6.3 log of the same suite has 0.
`test_layout_load.log` went from 409 lines / 28 028 B to 2 169 lines /
169 942 B. The migration left this warning on purpose, because the `name`
argument does not exist in 4.6.3
(`docs/audit/godot_4.7_migration_trial_2026-09-26.md` §3).

## 4. The fix (operator ruling 2026-09-26: the runner fixes both)

- **`run.sh`**: a `log_has <file> <ERE>` helper, `tr -d '\r' < f | grep -aE
  -- re > /dev/null`. grep without `-q` reads to the end, so `tr` always
  finishes. It replaces all five `tr | grep -q` pipes: the parse sweep verdict,
  the own-dialect loop's three checks, and spawn clearance. No `tr … | grep -q`
  is left (`grep -cE "tr -d '.r' <.*\| *grep -[a-zA-Z]*q"` prints 0). Every
  other `grep -q` in the script reads a file directly, with no pipe.
- **`Humanoid.gd`**: the five points are named `idle`, `walk`, `run`,
  `strafe_l`, `strafe_r` (`add_blend_point(node, pos, -1, &"name")`; the
  4.7.2 signature read from `ClassDB`). No code in `src/` addresses a blend
  point by index or name. The controllers write only
  `parameters/locomotion/blend_position`.

## 5. Measured after the fix (4.7.2, scratch `APPDATA` on D:)

| | before | after |
|---|---|---|
| parse sweep | 481 ok (the migration trial, older tree) | 494 ok, 0 fail, `RESULT: PASS` |
| `add_blend_point` warnings, `test_layout_load` | 140 | 0 |
| `test_layout_load` log / verdict | 169 942 B / 22 ok | 28 025 B / 22 ok, 0 fail, 0 skip |
| `test_new_world_wipe` log / verdict | 168 386 B / 11 ok | 27 475 B / 11 ok, 0 fail |
| `test_humanoid_rig_conformance` | PASS (0 fail), 80 warnings | PASS (0 fail), 0 warnings, the same 28 check lines |
| walk-cycle LUpperLeg peak, 3 runs each | 24.8° / 24.9° / 25.0° | 24.8° / 25.0° / 24.8° |
| `probe_stance_extents`, 5 stances | as below | identical, line for line |

    [EXTENT] locomotion  low=-0.90 high=+0.88  height=1.78 m
    [EXTENT] crouch      low=-0.90 high=+0.51  height=1.41 m
    [EXTENT] prone       low=-0.90 high=-0.51  height=0.39 m
    [EXTENT] seated      low=-0.76 high=+0.83  height=1.59 m
    [EXTENT] jump        low=-0.88 high=+0.89  height=1.77 m

The first baseline run's walk peak read 23.8°. The suite samples the leg once
per frame over 90 frames, and that first run followed a fresh import. The six
runs above, three each way, overlap.

Also:
- `bash -n tools/regression/run.sh` passes, and `grep -c '^for t in
  test_machine_sounds'` prints 1.
- The four stdlib gates pass: 0 unused, palette PASS, 0 parse-breaking, 0
  flagged.
- The operator's real `world_layout.json` kept its md5 (`e046af7d`).

Not run by this change: the full harness. The runner runs it on `main` after
the merge.

## 6. Consequence: `Humanoid.gd` is 4.7-only now

The 4-argument `add_blend_point` does not exist in 4.6.3, so a revert to 4.6.3
must revert this change too. The migration's rollback note
(`docs/PLAN_godot_4.7_migration_2026-09-25.md` §5) predates it.

## 7. Found, not changed

- `CLAUDE.md` still says `project.godot` declares `config/features=…("4.6")`.
  It declares `"4.7"` since #327.
- `run.sh:59`, `tasklist … | grep -qw`, is the same shape. tasklist prints a
  few hundred bytes, far under the pipe buffer.

## Reproduce

Point the script at any harness `out/` directory and at the edited `run.sh`.
It `eval`s `log_has` from the script itself, not from a copy:

    eval "$(awk '/^log_has\(\) \{/{p=1} p{print} p&&/^\}/{exit}' tools/regression/run.sh)"
    old_has() { tr -d '\r' < "$1" | grep -aqE "$2"; }
    for i in $(seq 10); do old_has out/test_layout_load.log '^  ok'; echo -n "$? "; done   # 141s
    for i in $(seq 10); do log_has out/test_layout_load.log '^  ok'; echo -n "$? "; done   # 0s

Only a log over 64 KB with an early match shows the 141. Since the warning fix,
the world logs are 28 KB again. A mutant needs padding: append 100 KB of
filler after the first `  ok` line.
