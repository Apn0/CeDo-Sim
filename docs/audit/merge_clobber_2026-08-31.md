# The 2026-08-31 batch merge silently reverted five hardened test suites

**Status:** fixed on `fix/wall-openings-merge-clobber-2026-08-31`.
**Severity:** `main` could not run its own regression harness. One parse error, four silent reversions.

This is the **third** occurrence of the batch-merge hazard first written up in
`docs/audit/pr_merge_2026-08-29.md`, and the first with this shape: **duplicate PRs, re-merged
from stale branches, overwriting the fixes that were applied to their own earlier copies.**

---

## What happened

Ten PRs merged between 00:36 and 00:40 on 2026-08-31. Four of them were **duplicates of PRs
already merged two days earlier** — same bot, same title, a fresh branch cut from the *old*
`main`:

| re-merged | duplicate of | title |
|---|---|---|
| #183 | #158 | Add proper headless test for WallOpenings remove_opening() |
| #185 | #156 | Add test cases for WallOpenings.setup() |
| #186 | #172 | Add headless tests for ToolPlacementMode _slot_accepts |
| #173 / #174 | #155 / #162 | WallOpenings `_would_cut_anything` / `_solidify_surfaces` |

Each stale branch still carried the **pre-hardening** copy of its test file. Merging it wrote
that copy back over the hardened one. Git reported **no conflict** in any case — the hardened
version and the stale version differ in ways that 3-way merge resolves silently.

## Measured damage

| file | asserts | counted checks | `Result:` verdict lines |
|---|---|---|---|
| `test_wall_openings.gd` | 2 → **13** | 23 → **2** | 2 → **0** |
| `test_push_gate.gd` | 0 → **8** | 11 → **0** | 2 → **0** |
| `test_walkie.gd` | 3 → **38** | 36 → **1** | 2 → **0** |
| `test_tool_placement_mode.gd` | 0 → 0 | 19 → **14** | — |
| `test_texture_cache.gd` | 0 → 0 | 18 → 18 | hermeticity fix removed |

Four distinct regressions, in descending order of how loudly they fail:

1. **`test_wall_openings.gd` did not parse.** #183 and #185 each contributed the same
   "create a dummy shell mesh" block, so `st`, `dummy_mesh` and `shell` are each declared
   **twice in one `_init()` scope**. GDScript has no block scoping — hard parse error. `run.sh`
   exits at its parse gate, so **no suite in the harness ran at all**.
2. **Five tests were deleted.** `_would_cut_anything` (×4) and `_solidify_surfaces` (×4) — the
   entire contribution of PRs #155 and #162 — are gone from the file. 11 tests → 6.
3. **The hang-proofing was reverted in three suites.** `assert()` aborts the script before
   `quit()`, and is compiled out of release builds. Both properties are why those 22/8/35 checks
   were counted rather than asserted in the first place.
4. **`test_texture_cache.gd` stopped being hermetic.** The `tc2._offline = true` line before the
   `bad_asset` request was dropped, so a harness run reopens a live HTTPRequest to the Polyhaven
   API (`TextureCache.gd:96-101`).

Separately, **`test_tool_placement_mode` was dropped from the `for t in ...` loop in
`run.sh`**: PR #168's branch rewrote that same single line to add `test_line_builder_ghost`, and
git merged one line over the other. Both suites now run.

## Why the harness did not catch it

It did — it just could not report it. The parse gate is the *first* step in `run.sh`, so the
duplicate-`var` error stopped the run before any suite executed. That is the gate working as
designed. What is missing is anything that runs it **on `main` after a merge**: every check in
this repo is invoked by hand.

The three suites whose verdict lines vanished would have gone **red**, not silent — the
`grep -qaE "^Result: [1-9][0-9]* ok, 0 fail"` gate added on 2026-08-30 fails a suite that prints
no verdict. That design held. The reversion of `assert()` did **not** re-introduce a hang for the
same reason: those blocks pass `--quit-after 300`.

## Fix

All five files restored from `d7b5c1f` (verified a strict superset of `main`'s copies — the only
strings unique to `main` were four `print` labels for checks the hardened version already makes,
and one vacuous `"All tests passed."`). `test_tool_placement_mode` re-added to the loop.

### Verification (worktree at `origin/main` + this fix, `CEDO_OFFLINE=1`)

```
parse sweep                    363 ok, 0 fail   RESULT: PASS   (was 362 ok, 1 fail)
boot parse gate                GREEN — main scene compiles
test_wall_openings             exit 0   22 ok, 0 fail
test_push_gate                 exit 0    8 ok, 0 fail
test_texture_cache             exit 0   19 ok, 0 fail
test_walkie                    exit 0   35 ok, 0 fail
test_silo_level_sensor_wired   exit 0    7 ok, 0 fail
test_tool_placement_mode       exit 0   18 ok, 0 fail   (no --quit-after; 124 would mean hung)
```

109 checks restored. Both directions measured: the parse sweep was **red before** the restore
and **green after**, in the same worktree, same engine, same command.

## What would prevent the next one

Nothing here is a code fix — all four regressions are *merge* failures.

1. **Run `tools/regression/run.sh` on `main` after any batch merge.** The parse gate alone would
   have caught #1 in seconds. Everything below depends on this repo not having CI.
2. **Before merging a PR whose branch is older than the file it touches, rebase it.** All four
   duplicates were cut from a `main` that predated the hardening.
3. **Close duplicate PRs rather than merging them.** #183/#185/#186 added nothing that #158/#156/#172
   had not already added; merging them could only ever move the file backwards.
4. **Treat a shrinking check count as a defect.** Every one of these reversions shows up as a
   drop in counted checks or a lost `Result:` line — cheap to diff, and the table above is the
   whole detector.
