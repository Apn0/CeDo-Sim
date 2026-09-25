# Suites dropped from run.sh's main loop by merges, 2026-09-25

> **STATUS — fixed in the same commit that adds this file.** That commit puts
> the four suites still missing on `main` `f30fbea` back into the main
> `for t in` loop: `test_hmi_fault_rearm`, `test_hmi_fault_per_line`,
> `test_machine_sounds` and `test_macro_edges_reload`. Their comment blocks
> never left the file. Each suite was measured green on its own. **A full harness
> was not run** (see "Not done").
> Why this keeps happening, and the one-line check that catches it, are
> below. **Read "How to check a merge" before merging anything that touches
> `run.sh`.**

## What was wrong

The main scene loop in `tools/regression/run.sh` is ONE line:
`for t in test_a test_b … ; do`, now about 75 names. Every session that wires
a new suite edits that line, so almost every pair of branches conflicts on
it. The resolutions kept one side's whole line, and each time the other
side's suites left the harness. Their test files stay in the tree, and their
comment blocks usually stay too, so nothing looks missing. This is the
CLAUDE.md trap "A bot PR's conflict resolution can delete a suite without
touching its test file".

Measured on `main`'s first-parent history, each PR merge that changed the
loop's suite list (`-` = left the loop, `+` = joined it):

| main commit | PR | left the loop | joined the loop |
|---|---|---|---|
| `a58a6a5` 01:08 | #278 | `test_hmi_fault_per_line`, `test_hmi_fault_rearm` | `test_extruder_melt_pressures` |
| `79c03f0` 01:41 | #285 | | `test_screw_die_plate_bar` |
| `798ce2b` 03:47 | #289 | `test_screw_die_plate_bar` | `test_extruder_silo_chain` |
| `7d19d2f` 03:54 | #287 | `test_extruder_silo_chain` | `test_machine_sounds`, `test_screw_die_plate_bar` |
| `2962f7c` 04:00 | #288 | `test_extruder_melt_pressures`, `test_screw_die_plate_bar` | `test_hmi_fault_rearm` |
| `5afb880` 04:12 | #290 | `test_hmi_fault_rearm`, `test_machine_sounds` | `test_extruder_melt_pressures`, `test_extruder_ramp_pressures`, `test_screw_die_plate_bar` |
| `22c9fd6` 04:48 | #292 | `test_extruder_ramp_pressures`, `test_screw_die_plate_bar` | `test_extruder_silo_chain`, `test_hmi_fault_rearm`, `test_machine_sounds` |
| `dd5c4af` | #294 | `test_hmi_fault_rearm`, `test_machine_sounds` | `test_fallback_chains` (new), `test_screw_die_plate_bar` |
| `8e6c93f` | #296 | `test_extruder_silo_chain`, `test_fallback_chains` | `test_extruder_ramp_pressures`, `test_extruder_stop_torque` (new) |
| `e81be45` | #295 | `test_extruder_ramp_pressures`, `test_extruder_stop_torque` | `test_extruder_silo_chain`, `test_hmi_fault_rearm`, `test_machine_sounds`, `test_macro_edges_reload` (new) |
| `828dbc1` | #298 | | `test_fallback_chains` |
| `f30fbea` | #299 | `test_hmi_fault_rearm`, `test_machine_sounds`, `test_macro_edges_reload` | `test_extruder_ramp_pressures`, `test_extruder_stop_torque` |

Ten of those twelve merges dropped at least one suite. This fix was rebased
five times while it was being written, because `main` moved under it each
time. None of the drops was intended: every suite that left still has its
`.tscn` and `.gd` on `main`, and no commit message in the range says a suite
was removed on purpose.
Re-derive the table with:

```bash
fl(){ git show $1:tools/regression/run.sh | grep -E '^for t in' | tr -d ';' | tr ' ' '\n' | grep '^test_' | sort; }
for c in $(git rev-list --first-parent --reverse 8440f63..origin/main); do
  r=$(comm -23 <(fl $c^1) <(fl $c) | tr '\n' ' '); a=$(comm -13 <(fl $c^1) <(fl $c) | tr '\n' ' ')
  [ -n "$r$a" ] && echo "$(git log -1 --format='%h %s' $c) :: -[$r] +[$a]"
done
```

### Where each drop happened: the branch-side merges

Three-way check for each merge. A suite counts as dropped if one side added
it relative to the merge base (or both sides and the base all had it), and
the merge result does not have it:

| merge | dropped | reached `main` in |
|---|---|---|
| `e8b3a0c` Merge branch 'main' into claude/clever-hypatia-945f15 | `test_hmi_fault_per_line`, `test_hmi_fault_rearm` | #278 (`a58a6a5`) |
| `a317056` Merge branch 'main' into claude/machine-sounds-2026-09-25 | `test_extruder_silo_chain` | #287 (`7d19d2f`) |
| `cc2f41b` Merge branch 'main' into claude/elegant-liskov-dd1577 | `test_machine_sounds` | #290 (`5afb880`) |
| `175e409` Merge branch 'main' into claude/elegant-liskov-dd1577 | `test_hmi_fault_rearm` (back on `main` since #288) | #290 (`5afb880`) |
| `993b30b` Merge branch 'main' into claude/kind-brattain-fcbe16 | `test_extruder_ramp_pressures`, `test_screw_die_plate_bar`, and their comment blocks | #292 (`22c9fd6`) |
| `1d1cb01` Merge branch 'main' into claude/cool-wing-61fec6 | `test_hmi_fault_rearm`, `test_machine_sounds`, and the latter's comment block | #294 (`dd5c4af`) |
| `7cd9474` Merge branch 'main' into claude/clever-taussig-f94c91 | `test_extruder_silo_chain`, `test_fallback_chains` | #296 (`8e6c93f`) |
| `f90d69d` Merge branch 'main' into claude/gracious-jackson-0c7549 | `test_extruder_ramp_pressures`, `test_extruder_stop_torque` | #295 (`e81be45`) |
| `082c302` Merge branch 'main' into claude/clever-taussig-f94c91 | `test_hmi_fault_rearm`, `test_machine_sounds`, `test_macro_edges_reload` | #299 (`f30fbea`) |
| `d90a943`, `468b3f9`, `e6d9bdc` (side branches) | `test_extruder_melt_pressures`, `test_extruder_silo_chain`, `test_screw_die_plate_bar` | healed or re-dropped by later merges, see the table above |

`e8b3a0c` is the first one, and the easiest to see. Both of its sides had
edited the loop line: the #278 branch added `test_extruder_melt_pressures`,
and `main` (#282) had the two HMI suites. The resolution kept the branch's
line. `git diff 8440f63 e8b3a0c -- tools/regression/run.sh` shows it. When a
branch like that is later merged into `main`, the merge base already contains
the drop, only one side changed the line, and git takes it without a
conflict. The drop never shows up as a conflict on `main`.

#292 (`c40b000`) put `test_extruder_melt_pressures` and
`test_extruder_silo_chain` back, and its line also brought back
`test_hmi_fault_rearm` and `test_machine_sounds`. The merge that took it to
`main` (`993b30b`) then dropped two others.

## How to check a merge

`git diff <old> <new> -- tools/regression/run.sh | grep '^-echo "=='` (the
check in CLAUDE.md) printed **nothing** on every drop above. The main loop
prints its `== $t ==` header from a line inside the loop, so removing a suite
from the list removes no `echo` line. (The operator chose not to change
CLAUDE.md for this; the gap is recorded here.) What does catch it is the list
diff. Run it after any merge that touches `run.sh`; its output must be empty:

```bash
fl(){ git show $1:tools/regression/run.sh | grep -E '^for t in' | tr -d ';' | tr ' ' '\n' | grep '^test_' | sort; }
comm -23 <(fl <before>) <(fl <after>)     # suites that LEFT a loop
```

For a conflict on the loop line: take the other side's line exactly as it
is, add your names with a script, then run the list diff against BOTH
parents. Never pick one side's line.

## The fix in this commit

- Base: `origin/main` `f30fbea`. Before the first edit, `run.sh` (at
  `64921ff`) was copied to `tools/regression/run.sh.bak` (gitignored). Every
  rebase conflict was resolved the same way: start from the new `main`'s file
  exactly as committed, then add names (and comment blocks, if gone) with a
  script. The set of missing suites changed with every rebase: two on
  `64921ff`, three on `22c9fd6`, four on `dd5c4af`, three on `828dbc1`, four
  on `f30fbea`.
- The script: for every suite that was in a `for t in` loop of any commit
  since `8440f63` and is missing now, it inserts the name after the nearest
  earlier neighbour it had in the newest commit that still had it (the HMI
  suites go after `test_hmi_ack_rearm`, the operator's choice). If the
  suite's comment block is gone too, it copies the block from that commit to
  just before the loop. Before it was used, the script was checked on
  `dd5c4af`: it rebuilt the hand-made loop line of the previous version byte
  for byte.
- Loop on `f30fbea`:
  - `test_machine_sounds` at the head, where `d2a1db2` wired it;
  - `test_hmi_fault_rearm test_hmi_fault_per_line` after `test_hmi_ack_rearm`;
  - `test_macro_edges_reload` after `test_extruder_silo_chain`, as in `828dbc1`.
- Comments: all four blocks are still in `f30fbea`'s file; none was re-added.
- Checked:
  - the loop is `f30fbea`'s list plus exactly those four, with no duplicates;
  - every suite in any `for t in` loop of any commit in `8440f63..f30fbea` is
    in the new file;
  - every name in the loop has a `.tscn`;
  - `bash -n` passes.

## Proof: each suite run alone

`assets/`, `.godot/` and `addons/waterbox/assets` were COPIED from the
operator's checkout, then `--import` was run on each new base. Engine
`4.6.3.stable.official.7d41c59c4`. `f30fbea` differs from `828dbc1` only in
`run.sh` and `CLAUDE.md`, so a run on either one tests the same code.

| suite | tree | verdict | exit | `^SCRIPT ERROR` |
|---|---|---|---|---|
| `test_macro_edges_reload` | `f30fbea` + fix | `Result: PASS (60 ok, 0 fail)` | 139 | 0 |
| `test_hmi_fault_rearm` | `f30fbea` + fix | `Result: PASS (32 ok, 0 fail)` | 0 | 0 |
| `test_machine_sounds` | `f30fbea` + fix | `Result: PASS (80 ok, 0 fail)` | 0 | 0 |
| `test_hmi_fault_per_line` | `828dbc1` + fix (same code) | `Result: PASS (26 ok, 0 fail)` | 0 | 0 |

The `ok` line counts equal the verdicts, and no log has a skip or `NOTE`
line. The exit-139 run is the known segfault while Godot shuts down. Its log
ends exactly at the `Result:` line, and the main loop gates on that line, not
on the exit code.

`test_macro_edges_reload` is the only one of the four that writes `user://`,
and only its own slot files (`user://__macroedgesrt___*`). No other copy of it
was running at the time. Its own leak guard passed: `Z2 LEAK GUARD: 17
operator files md5-identical before and after`. The HMI suites and
`test_machine_sounds` have no file access at all.

Earlier runs, same method, on the earlier bases of this fix:
- `828dbc1`: `test_extruder_stop_torque` 21, `test_extruder_ramp_pressures` 21;
- `dd5c4af`: `test_machine_sounds` 80, `test_extruder_ramp_pressures` 21,
  `test_hmi_fault_rearm` 32, `test_hmi_fault_per_line` 26;
- `22c9fd6`: the HMI suites 32 and 26, `test_extruder_ramp_pressures` 21,
  `test_screw_die_plate_bar` 36;
- `64921ff`: the HMI suites 32 and 26.

Every count matched across runs.

## Not done

- **A full `run.sh` with the four suites back.** Several other CeDo sessions
  were running harnesses on this machine at the time, and CLAUDE.md says never
  to run two at once.
- **Nothing structural was changed.** While the loop is one line, every two
  branches that wire a suite conflict on it, and the drop will happen again. An
  idea, not built: a bash array with one name per line. Additions from two
  branches would then usually merge without a conflict, and a dropped name
  would show as a `-` line in the diff. That is a change to `run.sh`'s layout,
  so it needs the operator's call.
- When this has landed on `main`, delete the memory pointer
  `hmi-fault-suites-uncommitted-fix.md` and its line in `MEMORY.md` in
  `C:\Users\arnod\.claude\projects\C--Users-arnod-Documents-CeDo-Simulator\memory\`.
