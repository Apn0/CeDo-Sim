# 2026-08-31 external review — disposition of all 21 findings

Every finding was re-measured against `main` (32a35ce) before any fix — four turned out
stale, misread, or false. 11 agents fixed the rest in parallel on this branch; every new
suite was mutation-tested (one deliberate break in the code under test → suite red → restore)
before being wired. Full evidence per fix in the PR body.

## Fixed — production code (3)

| # | finding | file | fix |
|---|---|---|---|
| 1 | Synchronous `load()` inside loop | `src/autoload/NpcAutonomyBoard.gd:538` | Hoisted to a typed const preload (`: Variant` keeps the null-guard meaningful; cycle-checked: ShovelFloorPileTask + base have zero back-references). Other `load()` sites in the file are NOT in per-item loops and were left alone. |
| 2 | Synchronous `load()` on demand | `src/autoload/Inventory.gd:124` | `STARTER_TOOL_SCRIPTS` paths → const preloaded scripts, resolved once at parse. Per-entry null-skip and tool_id dedup unchanged. |
| 3 | Recursive `find_child` per NPC in loop | `src/scenes/hud/CharacterCustomizer.gd:748` | One preorder traversal builds a name→node map, lazily, first-match-in-tree-order preserved; wildcard names fall through to real `find_child`. NPCs are in no group (checked MainWorld.gd), so a group lookup was not available. |

## Fixed — removal (1)

| # | finding | disposition |
|---|---|---|
| 4 | Command injection in `test_os_execute.gd:7` | The file was a leftover one-off probe (commit 7d9b55f) whose only content IS the unsafe call — `cmd.exe` with `"hello & whoami"` plus writing and executing a `user://test.bat`. Referenced nowhere (run.sh, src/, tools/ greps all empty). Sanitizing dead code preserves dead code: removed (`git rm`), `.bak` kept per house rule. No `test.bat` residue found in either user:// tree. |

## Fixed — new test suites (9 wired, +379 checks)

| suite | checks | covers | mutation proof (red) |
|---|---|---|---|
| `test_gate_state.gd` | 33 | is_fully_open/closed 0.999/0.001 boundaries, set_drive clamp, deterministic `_physics_process` travel | inverted `is_fully_open` → 6 fail |
| `test_scada_dashboard.gd` | 75 | set_state (incl. 60 s micro-stop boundary), set_param bands grey/red/amber, set_text_param | flipped micro-stop compare → 10 fail |
| `test_shredder_feed_belt_api.gd` | 47 | request_start/stop idempotence, fault latches + reset, can_accept/accept_bale gates | `is_faulted() -> false` → 3 fail |
| `test_npc_state_api.gd` | 74 | autonomy destination, forced-task lifecycle, post assign/return/clear, board/disembark with real OperatorContext | dropped destination-active write → 2 fail |
| `test_hmi_overlay_open_close.gd` | 28 | open_for/is_open/close_overlay on the REAL class (no mock bench) | inverted `is_open` → 7 fail |
| `test_laserscope_pressure_box.gd` | 48 | PressureBox.setup/update — the finding's ":558" is the INNER class | skipped `_value_bar` write → 9 fail |
| `test_map_overlay_zoom.gd` | 28 | zoom direction, exact clamp at both bounds ×50, downstream `view_params().scale_px`/`_to_px` | inverted direction → 13 fail |
| `test_hmi_web_gather_vals.gd` | 42 | gather_vals payload: pills, alarms, exclusions, every degrade path (pure GDScript — no WebView involved) | inverted powered bool → 7 fail |
| `test_customizer_world_bodies.gd` | 4 | `_rebuild_world_bodies` NPC loop — promoted from the finding-3 mutation probe; nothing else observed that loop | cache-returns-null mutation → 2 fail |

Plus: **`test_inventory.gd` (24 checks) existed but was wired nowhere** — found during finding 2;
now gated (it proved mutable to red: inverted `is_full()` → 3 fail).

## Not fixed — measured stale / false (4)

| finding | verdict |
|---|---|
| `find_child` fallback, `HmiOverlay.gd:348` | **Stale.** Current main already does `get_first_node_in_group("line_flow")` first; `find_child` is only the documented, measured fallback for a miss. |
| Empty `_ready`, `test_customizer_resolves_gamestate.gd:26` | **False positive.** It is the house quiet-subclass pattern — a deliberate override that skips the heavy UI boot, commented as such at the site. |
| `get_nodes_in_group` "repeated in loop", `NavSiteBounds.gd:62` | **Misread.** The enclosing loop iterates a ONE-element group list — the call runs once per `_sources()` invocation, which is not per-frame. |
| `Expression.execute`, aero addon `:63` | **Won't fix, documented.** Vendored third-party addon; the expression strings are operator-authored `@export` config, not user input; and the path is UNREACHABLE — zero references to any aero class or `expression_*` config exist outside the addon. Forking vendored code for an unreachable path buys drift, not safety. Open operator question: the plugin is enabled yet unused — disable it? (May still be wanted for the film-physics evaluation.) |

## Full-harness measurement on this branch (D: worktree, clean tree, isolated user://, 2026-08-31)

Exit 1 — every red is measured UNTOUCHED by this branch:

- **All 10 newly wired suites green inside the harness** (403 checks) alongside every
  previously-green gate.
- Known-red trio still red, unchanged: `test_nav_connectivity`, `test_npc05_realworld`,
  `test_line3b_flow_conformance` (see CLAUDE.md).
- **Two known-reds went GREEN on the clean tree**: `regression_world_save` (371 ok, 0 fail) and
  `test_project_sweep_guards` (19 ok) — their redness on the operator checkout is tree-state
  (stray files / local layout), not code.
- Environment reds from the empty isolated `user://` (no operator world):
  `test_vehicle_spawn_frame` ("world_layout.json holds at least one vehicle marker"),
  `test_jam_baseline` + part of `test_nav_connectivity` ("machine fixture present (39 static
  placed bodies)").
- **Candidate NEW main regressions from the 2026-08-31 61-commit wave** (green in the
  2026-08-30 red-list era, red now, and this branch touches none of the involved systems):
  `spawn clearance NOLINE/LINE` (MastLift 95 % embedded in the building shell — suspicious of
  the #168 gate/shell work), `test_tag_snapshot` (doseersilo `em/status` false),
  `test_feeder_fetch` (8 fail, feeder never reaches the kit; HEAD-baseline rerun during the
  preload work showed the identical red BEFORE any of this branch's edits). The canonical
  pristine-main harness run on the operator machine settles all three.

## Follow-ups surfaced while fixing (not in scope here)
- `test_hmi_overlay.gd` (the older suite) tests a hand-copied `TestableHmiOverlay`
  reimplementation, not the real class — the exact mock-bench gap this repo has been bitten by.
  The new `test_hmi_overlay_open_close.gd` covers the real class; the old suite should be
  retired or rebased onto it.
- `test_scada_dashboard.tscn` + `test_scada_dashboard_scene.gd` are an older unwired suite pair
  (its 8-line launcher was replaced by the new suite; launcher preserved in git history + .bak).
  Candidate for retirement.
- `MapOverlay.handle_zoom(0)` zooms OUT (falls into the else branch) — documented code-as-written
  in the new suite; flag if an operator ever binds a neutral-scroll event.
