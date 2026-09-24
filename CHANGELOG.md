# Changelog

Started by the sync sweep on 2026-09-24. Earlier history is in `git log main`
and in `docs/`.

## [2026-09-24] - Weekly Sync Sweep
- Merged branches: none. `main` is at 0996804 (PR #272). In the primary checkout
  `C:\Users\arnod\Documents\CeDo_Simulator` the local `main` ref was
  fast-forwarded 2dae7ab -> 0996804 without touching its worktree (it stays on
  `feat/backlog-qol-cleanup-2026-09-22`).
- Branches ahead of `main` in that checkout, none merged:
  - `claude/ready-daacfa` (27 commits, 161 files, +10,149/-363) would merge
    cleanly, but it is checked out in `V:\_Claude\CeDo_Simulator\ready-daacfa`
    with 11 uncommitted files and a commit from 2026-09-24 01:23 - work in
    progress, frozen.
  - `integrate/merge-open-prs-2026-08-29` (17 conflicts) and `wip/gate-carve`
    (3 conflicts: `src/build/Gate.gd`, `src/build/PlaceableCatalog.gd`,
    `src/tests/test_gate_carve.gd`) conflict with `main`.
  - `fix/navmesh-post-island-2026-08-26` (PR #109) and
    `trial/merge-all-2026-09-08` are already contained in `main`.
- Window: 15 commits since the previous sweep (2026-09-16), 11 non-merge, PRs
  #269-#272:
  - Line 1 re-layout, stranded hinge bodies, interactive HMI setpoints (af333dc).
  - Crash-safe saves via `AtomicFile`; 26 previously unrun suites wired into the
    harness; 3 harness losses from bot-PR merges restored (c02e943).
  - `BaleYardManager` scale optimization and slot-index bounds checking (1b7613d,
    1fb9eb8).
  - Five backlog QoL items (qol-06/07/08, phys-09, keybind comment) (3eeb7eb);
    `LumpChunk` continuous CD with a mutation-proven guard (a619b1e).
  - `assets/` loss and restore documented, now in the Drive backup (053840b,
    2dae7ab). Godot 4.6.3 import metadata and `project.godot` key order (683c41a,
    4b93f86). `test_bale_yard_mass_conservation` fix (09a42aa).
  - `src/scenes/player/Player.tscn` deleted; no doc references it.
- Docs: this file created. Relative links that do not resolve, not changed:
  `addons/godot_aerodynamic_physics/README.md` points at the upstream addon's
  `docs/`, which is not vendored; `docs/research_film_physics_feasibility.md`
  links `../../.claude/...`, a placeholder outside the repo.
- Hygiene: no `.env`; the code reads no app environment keys. The regression
  harness was not run by this sweep.
