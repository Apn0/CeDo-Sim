# Wiring the 2026-08-29 batch suites into the harness — 2026-08-30

The 2026-08-29 PR batch merged five test files that **nothing executed**.
`run.sh`'s scene loop iterates an explicit allow-list and none of them was on
it, so the only thing that had ever looked at them was the full-tree parse
sweep — which proves a file *parses* and makes no claim about what it does.

All five now run. None of them could be wired safely as merged.

| suite | how it runs now | checks |
|---|---|---|
| `test_tool_placement_mode` | scene allow-list (`run.sh:271`) | 18 |
| `test_wall_openings` | `--script` block | 22 |
| `test_push_gate` | `--script` block | 8 |
| `test_texture_cache` | `--script` block | 19 |
| `test_walkie` | `--script` block | 35 |

## The defect that made wiring unsafe, measured both ways

`test_wall_openings.gd`, `test_push_gate.gd` and `test_walkie.gd` all asserted
with bare `assert()`. A failing `assert()` aborts the enclosing function
**before** its `quit()`, so the `SceneTree` keeps iterating and the process
idles. Wiring them as-is would have converted a future regression from a red
line into a **hung harness** — the "idles forever" mode at `run.sh:48-54` that
this repo has already chased twice.

Not inferred. Same file, same broken claim (`24` vertices → `25`), same command,
no `--quit-after`:

```
OLD (bare assert)   exit 124  <- timeout(90 s) killed it; never exited
                    SCRIPT ERROR: Assertion failed: Expected 24 vertices ...
NEW (counted check) exit 1
                    Result: 21 ok, 1 fail, 0 skip
                    Result: FAIL
```

`assert()` has a second failure mode the conversion also closes: it is compiled
out of release builds, and `$GODOT` is overridable **by design** (`run.sh:17-21`)
so the harness can run off a template on Linux/CI. Under that binary the assert
form would have executed top to bottom checking nothing at all and printed a
pass. The counted form is immune to both.

## Mutation proof — every wired suite, one broken claim each

A wiring nobody has watched fail is unproven. Each suite had one expected value
flipped in the **test**, was run through the exact command `run.sh` uses, and was
required to both go red **and exit**:

| suite | mutation | gate | process |
|---|---|---|---|
| `wall_openings` | `24` → `25` vertices | red, `21 ok, 1 fail` | exit 1 |
| `push_gate` | `== true` → `== false` on `+X` | red, `7 ok, 1 fail` | exit 1 |
| `texture_cache` | `_offline == false` → `== true` | red, `18 ok, 1 fail` | exit 1 |
| `walkie` | `battery_percent() == 100` → `99` | red, `34 ok, 1 fail` | exit 1 |
| `tool_placement_mode` | `nearest == null` → `!= null` | red, `17 ok, 1 fail` | exit 1 |

## The gate is `Result: <n> ok, 0 fail`, not `Result: PASS`

A suite that executed **zero** checks prints `PASS` perfectly honestly. Requiring
a non-zero count is what makes "it ran but did nothing" red. Same reasoning as
the motor-overload gate that already existed.

## Three defects found and fixed on the way in

**1. `test_tool_placement_mode.gd` printed its verdict before its teardown.**
`Result: PASS` was printed, then eleven `queue_free()` calls, then `quit()`. The
scene loop has no `--quit-after`, so a runtime error anywhere in that tail would
have left a green verdict in the log *with the process still alive* — a passing
log and a hung harness simultaneously. The verdict now prints last, immediately
before `quit()`.

**2. `test_texture_cache.gd` opened a live socket to a third-party API.** It
builds `tc2` with `CEDO_OFFLINE=0` on purpose (to prove the flag parses), then
requests `bad_asset`, which can never satisfy all three maps — so
`request_pbr_set` fell past its offline gate into
`http.request(POLYHAVEN_FILES + …)` (`TextureCache.gd:96-101`). That instance is
now forced offline for that one request. The claim under test is untouched: the
corrupt-entry `DirAccess.remove_absolute` sits in the validation loop at
`TextureCache.gd:79`, which runs **before** `if _offline: return` at `:92`.
Deletion still happens; only the fetch stops.

**3. Four checks in `test_walkie.gd` were vacuous.** Two blocks sat behind
`if vs.calls.size() > 0:`, which deleted them precisely when `VoiceService`
stopped being asked to speak — blind to the one regression that section exists
to catch, which is the npc-05 vacuous-green shape. De-guarded; they pass hard.

## `test_walkie` was NOT excluded — the record was wrong

`docs/audit/pr_merge_2026-08-29.md` holds #161 back as measured-broken. Two of
its three findings described the PR **as reviewed**; the author reworked it
before it was squash-merged as `863f644`. Re-measured on the merged file:
**35 ok, 0 fail, exit 0, no hang.** That section is now marked superseded.

A finding about a PR expires the moment its author pushes. Only a finding about
a merge commit keeps.

## Baseline

Both runs are full-harness runs on this machine's real checkout.

| | before | after |
|---|---|---|
| full-tree parse sweep | 357 ok, 0 fail | 357 ok, 0 fail |
| failing checks | 5 | **5 — same list** |
| suites executed | 35 | **40** |

Unchanged failures: `regression verdict`, `test_nav_connectivity`,
`test_npc05_realworld`, `test_line3b_flow_conformance`,
`test_project_sweep_guards`.

**Correction to an earlier figure.** `pr_merge_2026-08-29.md` reports a
9-failure baseline. That was captured in a temporary **worktree**, and `assets/`
is gitignored (2.9 GB, `git ls-files assets` → 0), which CLAUDE.md already
documents as failing several suites for purely environmental reasons. The real
checkout's baseline is **5**. `test_map_frame`, `test_outdoor_route`,
`test_jam_baseline` and `test_gate_carve` are green here and were red there.
That the difference is the `assets/` class is INFERRED from the documented
behaviour — the worktree is gone and was not re-measured.

Use a worktree to isolate *edits*, never to establish a *baseline*.

## Still open

- **98 of 133 files in `src/tests/` are executed by nothing.** This batch closed
  five. `test_crew_panel.gd` is the remaining bare-`assert()` file and carries
  the same hang risk the moment anyone wires it.
- ~~The harness is not hermetic.~~ **FIXED in this same change** — see below.
  This was found while wiring `test_texture_cache` and turned out to be
  harness-wide rather than specific to the new suite.

## The harness talked to the internet (fixed)

Found while closing `test_texture_cache`'s own outbound call, and much bigger
than that one call: `PolyhavenMaterials._ready()` requests its PBR sets at
autoload boot (`PolyhavenMaterials.gd:84`), `TextureCache` opens an
`HTTPRequest` to the Polyhaven API for anything not already on disk
(`TextureCache.gd:96-101`), and `run.sh` never set `CEDO_OFFLINE`.

So **every** suite in the harness reached the public internet on every run. A
regression harness was quietly dependent on a third party being up, on the
machine having a network, and on nobody rate-limiting us — none of which any
suite asserts anything about. That is a flaky-red generator pointed at code that
did not change, which is how a harness teaches you to ignore it.

`run.sh` now exports `CEDO_OFFLINE=1`.

Safe by construction rather than by hope:

- No wired suite references `PolyhavenMaterials`, `TextureCache` or
  `pbr_set_ready` at all — grepped across the whole allow-list.
- The offline path is a documented **degrade**, not a failure: `_build(kind)`
  still produces the flat-colour `StandardMaterial3D` and only the HD upgrade
  never arrives (`PolyhavenMaterials.gd:70`).
- `test_texture_cache` is immune: it sets `CEDO_OFFLINE` to both values itself
  and restores whatever it found.

Validated on three representative suites with the flag exported — a world boot,
a pure-data suite, and the one suite that actually asserts on the flag:

```
test_map_frame             Result: PASS (0 fail)      [rc 139 = the documented
                                                       teardown segfault, not a
                                                       failure; verdict printed]
test_line3c_seq_alignment  Result: 11 ok, 0 fail
test_texture_cache         Result: 19 ok, 0 fail, 0 skip
```

The flag is confirmed to have reached the child process, not just the shell —
`[TextureCache] CEDO_OFFLINE=1 — disk cache only, no network fetches` appears in
the world suite's own log.

NOT YET DONE: a full 41-suite run with the flag exported. Deferred deliberately
— the operator was using the machine, and the harness and a live game session
both write `user://`. Run it before this is relied on as a whole-harness claim.
