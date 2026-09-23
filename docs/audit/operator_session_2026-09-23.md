# Operator session 2026-09-23 — ranked by operator effort against sim impact

Branch `claude/ready-daacfa`, worktree `V:\_Claude\CeDo_Simulator\ready-daacfa`.
The operator asked for a continuous session: rank the open work by "least
effort from me for highest impact on the sim", then take the tasks in order,
asking through AskUserQuestion whenever an answer only he has unblocks the
work. His answers are recorded in `docs/plant/operator_rulings_2026-09-23.md`
(recollections, labelled as such). Every task below was measured before it was
called done, per CLAUDE.md Rule 2.

## The ranking (as presented)

| # | task | what it needs from the operator | why it ranks here |
|---|---|---|---|
| 1 | P1 film on every belt | what the film looks like on the belts | highest visual win in the roadmap; one answer round |
| 2 | Crew posts at the windshifter | where that operator really stands | kills the month-old `test_nav_connectivity` red |
| 3 | Silo level indicator | do the real silos carry a sight strip? | build or close P5's silo half |
| 4 | Choked chute pile | does a full pile stop the line? | the `_dump_waste` half of P6 |
| 5 | Doorway fixture for the three skipped forklift checks | one design choice | makes the pilot checks permanent |
| 6 | Smoke on a packed-up drive | yes or no | P2's second half, ~20 lines |
| 7 | 3C cart count and line 6 carts | two rulings | two lines' correctness |
| 8 | In-game look at the overnight items | one game session | validates seven shipped features |
| 9 | Extruder vacuum pots | a photo or a description | P3 |
| 10 | forklift autopilot, fork pockets, hand-off, pellets, textures | nothing | my work only |

## Task 1 — P1: film on every belt (DONE, belt half; wet side queued)

### What the operator said (three AskUserQuestion rounds)

Round 1: mixed sizes, "from small flake to long strips". Colour: "Mix of
colors, although more white/translucent, then blue (variety of shades), then
all other colors, least black". Bed depth "varies per belt"; the 3A/3B
transportbanden carry "about twice the material, but those transportation
belts also run 50% faster then the other conveyors"; the compactorband is
"heaped, 20 cm or more". After washing the flake is "the same flake, wet and
darker". Wet-side places where flake is visible: Kufferath sieve /
scheidingsgoot, the dewatering screw trough, "open top tanks, transitions
cyclones to blowers". Transport screws: "differs per screw".

Round 2 (after the first renders, which drew the bed as a white slab with
flakes on top): the compactorband moves "more like 4 centimeters per second";
the bed "should be flakes only. But is that too heavy? Then use similar method
that for instance Gold Mining simulator uses for the soil, instead of sand the
texture is film"; the intake belts run "actually closer to 1.5m/s"; the wet
side next: scheidingsgoot, Kufferath sieve, dewatering screw trough, with the
same textured method.

### What was built

- **`FilmFlakeField` belt mode.** A deck instead of a water surface. The bed
  is derived, never drawn from a constant: kg per metre of belt =
  LineFlow's `thru` ÷ the deck's `belt_speed` (the same number BeltSurface
  carries the player with), depth = kg/m ÷ (bulk density × bed width). A
  stopped deck holds its bed; a moving one slews at one belt-full per transit
  time (length ÷ speed) and drains the same way when starved. Colour shares
  68/16/13/3 in his order; the size spread widened to 0.50-3.20 (length) ×
  0.55-1.60 (size).
- **How the bed is drawn (v2, his round-2 answer).** A `BedHeap` mesh —
  rounded across (30 % where the flanks meet the deck, 100 % on the crest,
  feet on the deck), lumpy along and across, unit height scaled in Y to the
  live depth so nothing is rebuilt — wearing a procedural film texture:
  cellular noise (one cell per shred, ~5 cm) coloured through a constant
  gradient in his shares, the same cells as a normal map, tiled every 0.5 m
  and scrolled downstream by `uv1_offset`. On top, a DENSE flake layer
  (~120 per m² of bed, 120..1500 per belt): instance transforms are written
  once, per-instance custom data carries each flake's base z and lift jitter,
  and a vertex shader (`world_vertex_coords`) scrolls it along the field's
  world axis, wraps it at the deck end, lifts it by the live bed depth plus
  its jitter, and tints it wet or dirty. Everything dynamic is a handful of
  uniforms per frame. The textures are built synchronously from an `Image`
  (the first v2 render was black: `NoiseTexture2D` generates on a thread).
- **`BeltBuilder.build_deck`** names every deck skin `DeckSkin` and seats a
  field on its top face (`attach_film_field`, public); a spec that zeroes the
  deck's width or thickness now builds no skin at all (it used to build a
  zero-volume box — which would have carried a second, degenerate field).
  Densities: `SNIPPER_BULK_KGM3` 60 (shredded film: transport_belt, the
  intake transportbanden, switch_belt, inclined_belt_8m) and
  `FLAKE_BULK_KGM3` 90 (washed flake on the compactorband — derived from his
  4 cm/s and "heaped 20 cm+" at 3A/3B's 0.61 kg/s; both visual only).
- **`PlaceableCatalog`**: the compactorband and the inclined belt seat their
  own field from their `extras` (bespoke decks). `COMPACTORBAND_SPEED_MPS` =
  0.04 replaces the generic 0.4 m/s for that belt's carry meta, BeltSurface,
  roller rpm and bed drift.
- **`LineFlow`**: in the PLC step, a belt-mode view gets `set_belt_state(thru,
  belt_speed × spin, spin > 0.05, moist, contam, delta)`; everything else
  keeps `set_live_state`.

### Found on the way: the inclined belt's deck ran the wrong diagonal

`probe_deck_orientation.gd` measured Godot's convention off a bare Node3D:
`rotation.x = +45°` maps local +Z to (0, −0.707, +0.707) — the +Z end goes
DOWN. `_inclined_belt_extras` rotated its 11.31 m deck (and both rails) by
+angle while the rollers sit at (y 0.25, z 0.25) and (7.75, 7.75): the deck ran
from top-left to bottom-right, crossing the frame at mid-height, with the top
roller and motor 8 m off the deck plane. `shot_belt_bed_inclined_belt_8m_before.png`
shows it. Fixed to −angle (BeltBuilder's tilted decks already use −incline),
rails offset along the deck's normal; the suite asserts the deck's +Z climbs
(`+Z.y` 0.707) and the top roller axle lies within 0.30 m of the deck plane.
This belt is placed by the sort line (×4) and the 3B/3C climbs.

### Measured

| what | result |
|---|---|
| `tools/regression/parse_sweep.gd` | `Result: 426 ok, 0 fail` |
| `test_belt_film_field` | `Result: PASS (142 ok, 0 fail)` — S1 geometry on 5 builders unmerged (field on the skin's top face, in its plane, spanning it; heap feet on the deck, unit crest; shader uniforms carry the field's world axes) + 3 through build_node/StaticMerge (field, heap and its one MultiMeshInstance3D survive; LineFlow's finder returns it); S2 bed model (slew 0.820 kg/m after 1 s at a 12 s transit; 2.4 kg/m → 4.88 cm → 65 of 150 flakes; heap scaled to the depth; scroll 0.50 m in 1 s and wrapping at the deck length; hold, no scroll while stopped; drain; over-full; wet roughness 0.18; brown); S3 colours 68.2 % white, blue 932 > other 777 > black 199; S4 line 1 booted, PLC cascade powers the belt after 17.3 s, 3 kg/s at 0.4 m/s → 7.50 kg/m on the fed belt AND the next one, unfed compactorband 0, HAND-off holds the bed exactly |
| `probe_belt_field_cost` (24 intake belts, headless = every field animating, FilmFlakeField's own µs counter) | v1 (CPU-animated flakes): bare 25 µs/frame, thin 590 µs (1602 flakes), full 1020 µs (3567 flakes ≈ 7 ms per 20 Hz tick), stopped 25 µs. **v2 (GPU-scrolled): bare 37 µs, thin 78 µs (6404 flakes), full 75 µs (14 259 flakes), stopped 24 µs** — ~3 µs per field per frame. Wall 6.9 ms/frame throughout |
| renders (`shot_belt_bed.gd`, windowed) | `docs/plant/renders/shot_belt_bed_{transport_belt_thin_2p8cm, transportband_3_even_5cm, transportband_3_wet, transportband_3_close, transportband_3_flakes_only, compactorband_0p61kgps_4cmps, inclined_belt_8m_after, inclined_belt_8m_before}.png` — looked at: the close-up shows a speckled grey-white film bed with crumpled shreds riding it, the compactorband at 0.61 kg/s and 4 cm/s stands 19.7 cm heaped, the old inclined deck crosses its frame |
| suites that touch belts, views or macros, re-run after v1 (detached batch, 17:04-17:08) | 20 of 20 green: `test_line1_throughput`, `test_line1_flow_conformance`, `test_line3a_flow_conformance`, `test_line3b_flow_conformance`, `test_belt_discharge_geometry`, `test_line1_overband_mount`, `test_macro_part_placement`, `test_line_builder_ghost` (29 ok), `test_line1_twin_streams` (exit 139 = the documented teardown segfault after its PASS), `test_line1_no_false_overload`, `test_shredder_rate_reconciliation`, `test_tag_snapshot` (28 ok, 1 skip, unchanged), `test_shredder_feed_belt`, `test_feed_belt_orientation`, `test_lump_cart_coverage`, `test_line3c_identity`, `test_line3a_identity`, `test_line3b_identity`, `test_project_sweep_guards` (19 ok), `test_macro_delta_guard`; 0 SCRIPT ERROR lines. The full harness runs after the commit |

### Honest limits / open

- The heap is uniform along the deck (no leading edge of a batch) and its
  texture is procedural, not a photo of Geleen film; the operator judges it
  in-game.
- His 1.5 m/s for the intake belts contradicts the catalog's note that
  0.4–0.6 m/s was operator-confirmed — NOT applied; one explicit answer
  first, because belt speed drives the player carry, deck physics, roller
  rpm and the discharge arcs.
- No bed yet on: the ShredderFeedBelt-scene belts (`drum_feed_belt` carries
  snippers), `metal_belt`, `scraper_conveyor`, `compactor_belt`; nothing on
  the wet side (his three are the next slice) or the screws (needs his
  per-machine list).
- A 4 cm/s compactorband fills over 96 s; the bed is correct but slow to
  appear after a start — that is the physics, not a bug.

## Task 2 — crew posts at the windzifter (DONE: the month-old red was a crew defect, ruled)

**Asked.** Where does the permanent feeder stand on 3A/3B; does anyone have
a post at a windzifter; may a blocked post slide along the aisle.
**Answered.** "line 1, he drives the Merlo and check containers etc. for
washing line one"; "No, nobody"; and on sliding: "depends on height (use of
mast lift needed) or other accessibility option like the fixed stair/walkway
(flotation tanks) (or ladder, but that is not added yet and low prio)".

**Why it was red.** Abdellilah and Mohammed are both `permanent_feeder`. That
role's `CrewManager.ZONES` list carried `wind_sifter`, and on a world with
only line 3A built (the suite's fixture, and any save without the shredder
hall) the windzifter was the ONLY zone match for both, so `assign_posts()`
parked them 1 m off its edge — inside the neighbouring blower's 1.2 × 1.0 m
collider, on no floor-level navmesh (the `why` line: nearest mesh 1.02 m
away and 1.10 m up, ISLAND, inside `@StaticBody3D@2339`). Every earlier
diagnosis chased the navmesh or the post-placement search; the post itself
was fiction.

**Fix.** `wind_sifter` left the permanent feeder's zone (one line, with the
ruling in the comment). A jam at the windzifter still gets a responder:
`_pick_responder` falls through to the floaters, which is his "crew only come
when it blocks". His sliding answer is recorded as a design item — a post
belongs at the machine's ACCESS point (mast lift for height, the fixed
stair/walkway on the flotation tanks, ladders later) — not built today.

**Measured.** `test_nav_connectivity`: `Result: PASS (10 ok, 0 fail)` on 3 of
3 runs; the seven stationed posts carry the same station ids on every run
(two positions differ by 0.1 m between runs — the aisle side is picked from
where the worker happens to stand, which is the suite's documented
provenance rule, not a flake); the two
feeders now appear as the suite's own `ADVIS: 2 post(s) assigned OUTSIDE the
site` (their spawn spot, since a 3A-only world has no line-1 station for
them) instead of a fake post. Before the fix, in the full harness at
`99b3a35` the same evening: `FAIL (9 ok, 1 fail)`, 14.67 m short.

**Full harness at `99b3a35`** (task 1 committed, before this fix): `== done
(exit 1)`, 113 steps, 33 min (17:44 → 18:17), 106 logs by mtime, 0 timeouts,
0 SCRIPT ERROR lines, exactly two reds — `test_nav_connectivity` (this one)
and `test_npc05_realworld` (expected). So after this commit the branch's
honest red list is `test_npc05_realworld` alone.
