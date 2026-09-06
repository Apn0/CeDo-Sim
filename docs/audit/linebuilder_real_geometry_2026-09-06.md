# Real-geometry line ghosts — `#linebuilder-geometry`, 2026-09-06

Operator ruling 2026-09-06: **"real geometry ghosts"** and **"leg F is confirmed"**.

The first reverses the 2026-08-29 compromise (`#linebuilder-ghost`), where every
previewed machine was a flat footprint box because *"the chutes do not have to be
perfect"*. With ~50 boxes the operator could judge that the train **fits**, but not
what it **is**.

## What changed

| File | Change |
|---|---|
| `src/build/BuildMode.gd` | `_make_line_ghost_node()` — new per-slot factory: `PlaceableCatalog.build_node(mid, true)`. The old box survives as the fallback for ids the catalog cannot build |
| `src/build/BuildMode.gd` | `_make_preview_inert()` — new sanitiser, called on the preview root before `_build_full_line` returns it |
| `src/build/BuildMode.gd` | preview parity for `extend_legs` entries, so the 3.48 m `sga_feed_chute` at the leg-C→D corner previews on legs instead of floating |
| `src/build/BuildMode.gd` | leg F comment `ASSUMED` → `CONFIRMED` |
| `src/tests/test_line_builder_ghost.gd` | new section 5 — four checks |

## Real geometry is not a drop-in for boxes

Two defects appeared the moment the preview stopped being boxes. Both were found by
the new checks, not by reading.

### 1. Leaked colliders — 14 of them

`PlaceableCatalog` gates the *generic* machine collider and the `placed_object`
group on `not ghost` (`PlaceableCatalog.gd:1525`), but a few model builders reached
from `_build_model` construct their own `StaticBody3D` + `CollisionShape3D` children
and never saw the flag.

Probed over all 31 distinct `line_1` ids — the two sources sum to exactly the 14
observed:

| id | shapes | bodies | scripts | meshes |
|---|---|---|---|---|
| `vw_trommel` | 6 | 6 | 0 | 119 |
| `mill` | 8 | 8 | 0 | 190 |
| `shredder_1` | 0 | 0 | 1 | 57 |
| `laser_filter` | 0 | 0 | 1 | 36 |
| `lump_cart` | 0 | 0 | 1 | 27 |
| `extruder_1` | 0 | 4 | 0 | 169 |

Every other line-1 id ghosts clean. `extruder_1`'s four bodies carry no shape.

### 2. The ghost was ~50 LIVE machines

`_build_full_line` returns an **unparented** root, so no `_ready` has run when the
count checks look at it. The moment the caller parents the ghost (`_spawn_ghost`'s
`add_child`, and the test's own), every scripted machine wakes up, re-registers its
groups, connects signals and starts timers. That is how one node was still in
`placed_object` after the collider fix was in.

`_make_preview_inert` therefore does all four: frees every shape, zeroes every
body's layer **and** mask, strips the behaviour groups
(`placed_object` / `belt` / `lump_cart` / `bale`), and removes every script.

Mesh count is **identical (1383) before and after the script strip** — measured.
That is what proves nothing visual is built in `_ready`, so nothing was lost.

`machine_leg` / `machine_foot` are deliberately kept: pure visual markers that
`extend_machine_legs` reads.

## Measurements — 2026-09-06, `line_1`, 50 slots

| Configuration | Meshes | Multi-part slots | Colliders | Grouped | Verdict |
|---|---|---|---|---|---|
| Real geometry + inert (shipped) | 1383 | 48 / 50 | 0 | 0 | **PASS 17 ok, 0 fail** |
| Real geometry, no sanitiser | 1383 | 48 / 50 | 14 | 1 | FAIL 15 ok, 2 fail |
| Placeholder boxes (mutant) | 50 | 0 / 50 | 0 | 0 | FAIL 15 ok, 2 fail |

Both directions measured, so neither half of the change is a vacuous green.

Full harness after the change: `== done (exit 1) ==`, **5 failures — the same five
already recorded in `CLAUDE.md` for 2026-09-03, with identical messages.** No new
red. `test_line1_flow_conformance` PASS, `test_tool_placement_mode` PASS 18 ok.

## Why section 5 had to exist

Checks 1–3 of `test_line_builder_ghost` pass **identically** for boxes and for real
machines: they count slots, prove zero side effects on `_placed_root`, and compare
positions. None of them can see *what* was drawn. Without section 5 a revert to
`_make_ghost_placeholder_box` stays green and the ruling is held by nothing.

The discriminator is part count: a placeholder box is exactly one `MeshInstance3D`;
a catalog machine is dozens of parts, and ghosts skip `StaticMerge`
(`PlaceableCatalog.gd:1522`) so those parts stay separate nodes.

## Leg F

`BuildMode.gd` contradicted itself: the leg map at the top of `LINE_1_SEQ` read
**CONFIRMED** (operator, 2026-08-28, *"leg F is correct"*), while the comment on the
leg-F entry itself read **ASSUMED** and pointed the reader back at the leg map.
`docs/plant/line1_layout_sketch_2026-08-28.md:50` already said **BEVESTIGD**, so the
docs were right and only the code comment was stale. Re-confirmed by the operator
2026-09-06 and corrected; the contradiction is recorded in place so it is not
re-litigated.

## Open

- **Single-item placement ghosts have the same collider defect** for `vw_trommel`
  and `mill` — `build_node(id, true)` is the same call, just without the sanitiser.
  Proven by the same probe, pre-existing, deliberately not fixed here: it means
  touching the snap and blocker paths that read the single-item ghost.
- The operator's original line-1 layout sketch image is still not archived
  (`docs/plant/line1_layout_sketch_2026-08-28.md` carries the warning).
- 3A / 3B / 3C carry zero `turn_deg` entries. The turn machinery in
  `_build_full_line` is generic, so folding them is data authoring, not code —
  it needs an operator statement of where each line turns.
