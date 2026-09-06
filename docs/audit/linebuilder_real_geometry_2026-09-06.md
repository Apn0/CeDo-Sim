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

## Single-item ghosts had it too (fixed in the same PR)

The whole-line preview was never the only ghost. `_spawn_ghost`'s `else` arm builds
ONE machine via the same `PlaceableCatalog.build_node(id, true)` and parents it at
the cursor — with no sanitiser. So **aiming a `mill` or a `vw_trommel` put a solid
object under the cursor**, and had done since long before this change.

`_make_preview_inert` now runs on every placement preview, single-item included, and
**before** `add_child` — the scripts have to come off while `_ready` still hasn't run,
or they get one tick to register themselves first.

Two latent bugs fall out with it:

- `_find_machine_snap`'s comment asserts *"the ghost is NOT in this group —
  `build_node(id, true)` intentionally skips the group for ghosts"*. True at
  construction; **false one frame later** for ids carrying a live script. Measured:
  a `shredder_1` ghost re-adds itself to `placed_object` in `_ready`, making the
  preview a snap target for itself.
- `extend_machine_legs` raycasts each leg downward and excludes only the **root's**
  own RID. A `mill` ghost's 8 nested bodies are not excluded, so its own legs read
  themselves as an obstacle and get hidden.

Mutation proof (sanitiser call removed from `_spawn_ghost`), which also re-measures
the defect through the real path rather than a probe:

| id | shapes | scripts | grouped | meshes |
|---|---|---|---|---|
| `mill` | 8 | 0 | 0 | 190 |
| `vw_trommel` | 6 | 0 | 0 | 119 |
| `shredder_1` | 0 | 1 | 1 | 57 |

→ `FAIL 25 ok, 4 fail`. With the fix: `PASS 29 ok, 0 fail`, all counts zero and mesh
counts **unchanged** (190 / 119 / 57), so no geometry was lost here either.

Covered by `test_line_builder_ghost` section 6, which drives `_spawn_ghost` and then
awaits a frame — testing `build_node` in isolation would miss the group leak entirely,
since it only appears after parenting.

## Looking at it — `shot_line1_ghost`

Every check above is geometric: part counts, collider counts, positions. None of
them can see how the ~50-machine preview **reads on screen**. `src/tests/shot_line1_ghost.gd`
closes that: it boots MainWorld, calls the real `_spawn_ghost("line_1")`, drops the
result at `world_layout` `line_starts["1"]`, hides `BuildingShell` and the six
`CanvasLayer`s, and saves three content-checked renders. Run it **windowed** —
`--headless` has no rendering device and every frame would be blank:

```
Godot --path . res://src/tests/shot_line1_ghost.tscn
```

| Render | mean_lum |
|---|---|
| `docs/plant/renders/shot_line1_ghost_overview_2026_09_06.png` | 0.6787 |
| `docs/plant/renders/shot_line1_ghost_plan_2026_09_06.png` | 0.6851 |
| `docs/plant/renders/shot_line1_ghost_drumhead_2026_09_06.png` | 0.6923 |

Measured on the built ghost: **51 slots, 1433 `MeshInstance3D`, 0 `CollisionShape3D`**,
visual AABB `size=(114.01, 10.64, 23.81)`. The 23.8 m lateral spread is itself the
fold — a straight line would be about 4 m wide.

### The fold, measured

The tool walks the slots in build order and prints the legs. The step from one slot
to the next is *not* the leg heading — line 1 lays 7 stations as side-by-side PAIRS,
so the raw walk zigzags ±135°. Differencing over a **two-slot window** cancels that
jog; the result is then quantised to the nearest axis.

| Leg | Axis | Run | From → to |
|---|---|---|---|
| A | −Z | 11.2 m | `opzetband_1` → `transport_belt` |
| B | −X | 6.3 m | `transport_belt` → `transport_belt2` |
| C | +Z | 12.9 m | `transport_belt2` → `vw_trommel` |
| D | −X | 34.7 m | `vw_trommel` → `transport_screw2` |
| E | −Z | 14.2 m | `transport_screw2` → `friction_sep3` |
| F | −X | 37.5 m | `friction_sep3` → `lump_platform` |

−Z, −X, +Z, −X, −Z, −X is **L, L, R, R, L** — exactly the five `turn_deg` entries in
`LINE_1_SEQ`'s `#fold 2026-08-28` leg map, now measured in the built ghost rather
than read off the source. The tool also prints legs G–I; those are the lump-cart
branch furniture and leg F's own tail continuing to `voorraad_silo`, which jog
laterally off the main axis by design.

### Defect found by looking: 17 of 51 slots had no name

`_make_line_ghost_node` names every slot `ghost_<id>` and its comment promises the
preview tree "stays greppable in a remote debugger". It did not. Line 1 contains
duplicate ids (the pairs), and `add_child()` with the default `force_readable_name`
resolves a sibling name clash by assigning Godot's fast internal form —
`@StaticBody3D@2425`. Measured: **17 of 51** preview slots.

Fixed with `ghost_root.add_child(node, true)` (preview arm only — real placement is
untouched), which uniquifies readably to `ghost_mech_dryer2`. After the fix the child
table has **zero** anonymous names, and `test_line_builder_ghost` still reports
`PASS 29 ok, 0 fail` — its name-prefix fallback (`:138`) keeps working because the
prefix survives.

One earlier suspicion did **not** survive measurement: a 109 m step in the first leg
walk looked like a stray node far from the train. The child table showed it is the
march-direction arrow `_make_line_ghost` adds at the origin (`BuildMode.gd:1912`) —
last in build order, first in space. The walk now drops it.

## Perf: the ghost is free — `perf_line1_ghost`

With the ghost up the PERF overlay read `FPS 2, avg 7, Draw calls 3462`. That was
**observed, never measured against a baseline**, so the ghost was never actually
shown to be the cause. `src/tests/perf_line1_ghost.gd` settles the plant, then runs
six interleaved A/B pairs (ghost down / ghost up) and differences them **pairwise**.

```
Godot --path . res://src/tests/perf_line1_ghost.tscn
```

| | ghost down | ghost up | delta |
|---|---|---|---|
| frame time | 132.51 ms | 132.81 ms | **median −0.06 ms** (mean +0.29 ± 2.00) |
| draw calls | 1042 | 1802 | **+760** |
| primitives | — | — | **+182 239** |

Per-pair B−A: `+2.7 +0.1 −0.2 −0.5 −2.7 +2.3` ms.

**The ghost adds 1433 meshes and 760 draw calls at no measurable frame cost.** The
plant sits at 7.5 fps / 133 ms *with the ghost down too*, and the overlay reports it
CPU-bound on scripts and physics. The `FPS 2` observation is not attributable to this
change — the baseline is the problem, ghost or no ghost. Flag retracted.

Two method notes, both learned by getting them wrong first:

- **Settle before measuring.** A single quiet window is not settled — the plant hit
  3.9 % drift at window 1 and then still fell from 133 ms to 60 ms afterwards. The
  probe now requires 3 consecutive windows under 4 % (took 18 windows).
- **Median, not mean.** On a run where the baseline was still moving, two of six
  pairs read +55.1 and +46.2 ms while the other four read ≈0. Those two measure the
  baseline moving, not the ghost, and they drag the mean to +16 ms — inventing a cost
  that is not there.

**Do not `StaticMerge` the ghost to "fix" the draw calls.** It would buy nothing
measurable, and it would break `test_line_builder_ghost` section 5: the box-vs-real
discriminator *is* the unmerged part count (`PlaceableCatalog.gd:1522`).

## Open

- The operator's original line-1 layout sketch image is still not archived
  (`docs/plant/line1_layout_sketch_2026-08-28.md` carries the warning).
- 3A / 3B / 3C carry zero `turn_deg` entries. The turn machinery in
  `_build_full_line` is generic, so folding them is data authoring, not code —
  it needs an operator statement of where each line turns.
