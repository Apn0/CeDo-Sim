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

## Task 3 — silo level windows (DONE), and the belt speeds he settled on the way

**Asked.** Which silos show a level from outside, and what the indicator is.
**Answered.** Doseersilo, mengsilo, extruder silo (not the VSS): "dosing silo
2 square windows approx 30x30 cm horizontal distance 90cm between them
centered along the tank, on both sides. mixing silo 1 small 15x15cm window
1/3 the way up on 1 side, extruder silo 4 vertical windows on each side" —
and, when the last one collided with the #98/#99 layout: "It's four windows
per side. And the sides I mean are not the short sides where the ladder would
be. But the long sides … every window would be in the … most centre of the
centre, but not actually in the centre overlapping."

**Built.** `PlaceableCatalog._level_window` (a proud sight-glass port: ring,
gauge glass, dark back, `LevelWitness` slab), `_silo_fill_root`,
`set_silo_fill`, `_window_port`; the doseersilo's two 0.30 m squares per long
side at z = ±0.45 on the trough wall 35° below the axis (his numbers give the
spacing, not the height — that is a stated placement), the mengsilo's 0.15 m
window at a third of the height above the legs on +Z (the invented vertical
strip is gone), the extruder silo's eight 0.29 × 0.61 m windows on the ±X
faces at ±bd/8 and ±box_h/8 (ribs 1 and 2 removed, the short-face windows and
the #89 static flake pile removed). LineFlow finds each node's `SiloFill` and
drives it every tick from the input batch's kg against `SILO_FULL_KG` (150,
the VSS convention). **The morning's compactor kijkglas turned out invisible**
— rendered at 33 % pot load: a grey door plate — because the door and drum
are opaque and the PotFill column is inside; it is now the same proud port
under the hatch, driven by `set_pot_fill()`.

**Measured.**

| what | result |
|---|---|
| `test_silo_level_windows` | `Result: PASS (50 ok, 0 fail)` — S1 counts, sizes, faces, spacing, a-third-up, inner sub-quadrants, no-touch gaps, VSS none; S2 witnesses hidden / partial / full, top ON the level line (also on the 35° trough wall), monotonic; S3 build_node keeps `SiloFill` through StaticMerge and a real LineFlow mengsilo reads 0.50 after one tick with 75 kg injected, falling as it discharges; S4 the compactor port at the kijkglas height shows nothing at 20 %, a partial line at 33 %, full at 50 % |
| `test_compactor_sight_glass` | 21 ok (the PotFill column and its meta are unchanged) |
| renders (`shot_silo_level.gd`) | `docs/plant/renders/shot_silo_level_{doseersilo_47pct, mengsilo_10pct, extruder_silo_45pct, compactor_kijkglas_33pct, compactor_kijkglas_33pct_back}.png` — looked at: the doseersilo pair and the mengsilo glass show the film level; the extruder silo's lower pair shows it at 45 % and the upper pair the dark cavity; the compactor render before the fix showed no level at all |
| belt speeds (rulings §8) | `_BELT_CARRY_SPEED` 0.4 → 1.0, `_INTAKE_BELT_SPEED_MPS` 0.5 → 1.5 (both files). `test_belt_film_field` 142 ok after one expectation moved with the physics (a 4 m belt at 1.0 m/s empties in 4 s, so little bed remains after the 2.5 s spin-down; the hold check now asserts the remainder holds exactly, not a size); the belt/line batch below |

Belt/line batch on this code (detached, 21:00-21:05): 23 of 23 green —
`test_belt_film_field` 142, `test_silo_level_windows` 50,
`test_compactor_sight_glass` 21, the four line conformance/throughput suites,
`test_belt_discharge_geometry`, `test_line1_overband_mount`,
`test_macro_part_placement`, `test_line_builder_ghost` 29,
`test_line1_twin_streams`, `test_line1_no_false_overload`,
`test_shredder_rate_reconciliation`, `test_tag_snapshot` 28 (1 skip,
unchanged), `test_shredder_feed_belt`, `test_feed_belt_orientation`,
`test_lump_cart_coverage`, the three line identity suites (3A exit 139 =
the documented teardown segfault after its PASS), `test_project_sweep_guards`
19, `test_macro_delta_guard`; 0 SCRIPT ERROR lines. Parse sweep 428 ok.

**Honest limits.** The doseersilo windows' height on the trough wall and the
mengsilo's side are placements, not his numbers. The kijkglas port is square
(0.24 m) where the real one is round. A port on the cleanout door swings with
the door; the witness under it does too, but the interior column does not
(nobody sees it). `SILO_FULL_KG` = 150 is the sim's kg scale, not a vessel
volume.

## Task 4 — the choked chute (DONE) and Task 6 — smoke on a packed-up drive (DONE)

**Asked / answered.** Task 4: "The machine chokes and stops"; it comes back by
"Shovel, then reset on the HMI". Task 6: "Visible smoke sometimes" — "Heavy
smoke, people react".

**Built (task 4).** `LineFlow._dump_waste` returns what nothing would take;
both dump sites put the refused kg back into the machine and the node chokes
(`nd["choked"]`, `nd["choke_pile"]`), latched through `_is_trip_latched` so
the existing trip path drops power in the PLC step (the 2026-09-23 morning
lesson: stop where `powered` is written). One `CHUTE-BLOCKED` alarm on the
edge. `reset_choke(id)` refuses while the pile is above `CHOKE_CLEAR_FRAC`
(0.5) and takes after; `is_choked(id)`. `CrewManager._relieve` on a choked
node shovels `SHOVEL_KG` off that pile instead of moving buffer kg. The HMI's
RESETTEN calls `reset_choke` for every machine in its scope. Choke state
survives `rebuild()` (survivor copy).

**Built (task 6).** `_motor_unit` leaves a `motor_pos_local` meta on its
parent (the first motor per model);
`PlaceableCatalog.install_smoke_plume(body)` seats a dark, dense variant of
the steam plume there (`_install_steam_plume` grew name/group/dark
parameters and now returns the emitter). `LineFlow._apply_trip_latches`
detects the MotorOverload trip EDGE per node; `_on_trip_edge` rolls
`smoke_chance` (0.35, stated) and, when it hits, emits for `SMOKE_S` = 25 s,
raises `SMOKE` (severity 3) and prints; `_tick_smoke` runs it down;
`is_smoking(id)`. `CrewManager` hooks `machine_alarm_raised` lazily: on
SMOKE it radios ("Rook bij <id>! Iedereen weg daar — ik ga kijken."), logs
the id in `smoke_alarms`, and dispatches the nearest free responder.

**Measured.**

| what | result |
|---|---|
| `test_chute_choke` | `Result: PASS (24 ok, 0 fail)` — a friction separator over a pile pre-filled to 99.5 % of its volume at dirt density chokes on the first refused dump, alarms once, drops power, conveys 0 kg over 2 s with its buffer untouched, ledger closed to 1e-3 (injected + wash water taken on), the pile holds exactly what left, reset refused at 102 % fill, the crew service shovels it to 0 %, the choke survives a rebuild, reset then takes and after `start_line()` the machine conveys again |
| `test_trip_smoke` | `Result: PASS (21 ok, 0 fail)` — no plume before any trip; with chance 1 a forced trip installs and starts a `smoke_plume` on the motor anchor (0.000 m off), 160 puffs, one SMOKE alarm, `is_smoking` true, still emitting at half time, off after 25 s; with chance 0 a second trip neither smokes nor alarms and the node is reused; a third trip with chance 1 smokes again; the crew log SMOKE and ignore BUF-300. The autonomy board also raised the storing (`[NpcAutonomyBoard] storing raised: friction_sep/SMOKE`) |
| parse sweep | `Result: 430 ok, 0 fail` |
| two fixture facts worth keeping | a FloorPile blends density by mass, so "room left" must be stated in VOLUME (a 1.5 kg fines pre-fill grew to a 6.8 kg capacity once dirt landed on it); a washer adds process water, so a machine-level mass ledger must count `water_added` |

Wide batch on this code (detached, 21:25-21:33): 22 suites ran, all green, 0
SCRIPT ERROR lines (`test_hmi_overlay_open_close` and
`test_hmi_web_gather_vals` are `--script` suites without a scene and the batch
runner skipped them) — `test_chute_choke`, `test_trip_smoke`, `test_motor_trip_stops_conveying`, `test_hmi_retired`, `test_hmi_overlay_open_close`, `test_hmi_web_gather_vals`, `test_scada_dashboard_scene`, `test_line1_throughput`, `test_line3a_flow_conformance`, `test_line3b_flow_conformance`, `test_tag_snapshot`, `test_l3c_unit_screens`, `test_extruder_brain_wired`, `test_lump_cart_overflow`, `test_nav_connectivity`, `test_bunker_relay_trip`, `test_bunker_shredder2_interlock`, `test_belt_film_field`, `test_silo_level_windows`, `test_compactor_sight_glass`, `test_project_sweep_guards`, `test_qa_loop`, `test_line1_no_false_overload`, `test_shredder_rate_reconciliation` (`test_bunker_relay_trip` and
`test_bunker_shredder2_interlock` print their own verdict line; 0 FAIL lines
in both). `test_nav_connectivity` stays green (45 ok) with the crew change,
`test_motor_trip_stops_conveying` (28 ok) with the trip-edge hook,
`test_hmi_retired` (70 ok) with the RESETTEN hook.

**Honest limits.** `smoke_chance` 0.35 is a reading of "sometimes". The
plume is the steam plume's construction in dark; its look in-game is for the
operator's eye (a render needs a running trip, so none was taken). The HMI
reset resets the chute, not the overload relay — the operator resets the
drive separately (the choke suite does both). Shovelling is the crew's
service; the player's ShovelTool path was not changed.

## Task 5 — the doorway the forklift checks needed (DONE: the suite owns it)

**Asked / answered.** "Suite builds its own gate (Recommended)".

**What was wrong.** `test_jam_baseline`'s three forklift-pilot checks are
gated on `_route_exists()`: without a doorway the vehicle router accepts,
they SKIP, and the suite has said so in a `NOTE:` line since 2026-09-22. The
doorway used to be the operator's own 3A/3B gate in his `world_layout.json`
`structure_items`; the 2026-09-13 session cleared that entry to turn
`regression verdict` and `test_project_sweep_guards` B1b green, which put
the three checks back on their vacuous skip (11 ok + 3 skipped).

**Built.** The entry is reproduced IN MEMORY by the suite itself, from the
operator's own backups (`user://world_layout.json.bak_prerun_20260902`,
`.bak_tagsnap_20260831`, `.bak_premerge_2026-09-08`,
`.bak_ultracode_20260913_061442` — byte-identical in all four): a four-point
`surface` gate labelled "3A/3B gate" on the facade,
`p = [[-248.650, -8.924, 154.075], [-248.622, -4.091, 154.098],
[-244.101, -4.200, 157.892], [-244.135, -8.842, 157.863]]`. After the line
3A fixture is built, `_build_line_3a` passes it to
`BuildMode._apply_layout_entry` — the same call a save load makes — which
builds the leaf, has `WallOpenings` carve both wall skins and calls
`BaseVehicle.invalidate_route_grid()`. `WorldLayout.structure_items` is not
touched (asserted), so nothing can leak into the operator's file; the
autosave was already redirected by `layout_path_override`. Two new checks
assert the cut happened (`opening_id` on the gate) and the layout list is
still empty.

**Measured.**

| run | result |
|---|---|
| 1 | `Result: PASS (16 ok, 0 fail, 0 skipped)` — `DOORWAY fixture: … carved (op_1)`, jam 1 `arrived after 158.6 s`, 2.19 m from target, 281.4 m covered, wedged 0.0 s; jam 3 `arrived after 94.1 s`, 2.19 m, 158.1 m covered; the route around the machine row 15 points, ends 0.00 m off |
| 2 | `Result: PASS (16 ok, 0 fail, 0 skipped)` — jam 1 arrived after 158.6 s, jam 3 after 94.1 s (both 2.19 m from target; the same order as run 1) |

Before the fixture (this morning's harness): `PASS (11 ok, 0 fail, 3 skipped)`
plus the `NOTE:` line. On 2026-09-03 with the operator's gate in his world:
jam 1 166.3 s, jam 3 100.8 s — the same order as today.

**Honest limits.** The gate is a fixture of this suite alone;
`regression_world_save`'s "doors on walls" and macro checks still skip on
the (empty) operator world, and `test_nav_connectivity`'s pedestrian mesh is
unaffected (vehicles route on their own grid). The building still has no
door survey — this is the one doorway the operator ever placed.

## The operator's in-game look (task 8 — after the full harness, his choice)

Run the branch from the worktree (it has real `assets/` and `.godot/`):
open `V:\_Claude\CeDo_Simulatoready-daacfa` in Godot 4.6.3 and press
Play, or `Godot_v4.6.3-stable_win64_console.exe --path V:/_Claude/CeDo_Simulator/ready-daacfa`.
Nothing below is guessed; each is a thing only the eye settles.

**Today (2026-09-23 evening)**
1. **Belt beds** (P1): stand at any 3A/3B transportband, line 1's belts after
   shredder 1, or the compactorband while the line runs. A textured film heap
   with crumpled shreds riding it, scrolling at the belt's speed; thin on the
   intake belts (they run 1.5 m/s now), heaped on the compactorband (4 cm/s).
   Judge: does the heap read as film; is the intake bed too thin; do the
   shreds look right in size and colour order (white, blue, others, black).
2. **Belt speeds**: 1.5 m/s intake, 1.0 m/s other conveyors — stand on one.
3. **Silo windows** (P5): doseersilo two squares per long side, mengsilo one
   small glass low on the +Z side, extruder silo 2×2 per long face — with the
   line filling them, a film level in the glass. Judge: positions and sizes
   against Geleen; does a level read through the glass at all in real light.
4. **Compactor kijkglas**: now a boxed port on the cleanout door; a level
   between ~27 % and ~38 % pot load.
5. **Choke**: let a reject pile under a washer or screen fill (or block the
   chute deliberately); the machine stops with `CHUTE-BLOCKED`; crew shovel
   it on their service; RESETTEN on that HMI takes only after the shovel;
   then start the line again. Judge: does the flow feel right.
6. **Smoke**: overload a shredder or friction separator until it trips; about
   one trip in three smokes heavily at the motor for 25 s, the radio calls
   it, a responder walks over. Judge: the plume's look and amount.
7. **Crew**: nobody stands at a windzifter any more; the two feeders are
   line-1 men.

**Last night (2026-09-23 morning, still unseen)**
8. The Lumpenwagen heap in the bucket and the grey mound around a full cart
   (Numpad 9 fills the aimed machine); lift a cart out of a mound.
9. Checkpoint button on the pause card (P), 4th of 5.
10. F1 key sheet on foot and in a cab.
11. Map (M): Dutch machine names, crew names, violet HMI diamonds.
12. A real trip: the rotor coasting to a stop over ~2.5 s.
13. HMI readouts settling over ~0.4 s at the 10 Hz flow.

## Full harness after the five task commits (`99fc375`)

`== done (exit 1)`, 116 steps, 36 min (22:06 → 22:42), 109 logs by mtime,
0 timeouts, 0 SCRIPT ERROR lines, one red: `test_npc05_realworld`
(expected, the DRIVE_TO_INDOOR stall). Inside the run: `test_nav_connectivity`
PASS (10 ok), `test_jam_baseline` PASS (16 ok, 0 fail, 0 skipped),
`test_belt_film_field` 142, `test_silo_level_windows` 50, `test_chute_choke`
24, `test_trip_smoke` 21. The morning's harness at `99b3a35` had 113 steps
and two reds; the difference is the crew ruling and three new suites.

## Task 9 — vacuum pots, stage A (DONE); stage B is a mini-game (queued)

**Asked / answered.** How to get the pot geometry: "Use the EREMA diagrams".
Then, on the build: yes, on the photo domes — but not as a hold-E: the
cleaning is an operator mini-game (rulings §14, transcribed in full).

**Built.** Per pot a `VacPot_<name>` root under the catalog body: the dome's
sight glass as a proud witness port, a `Lid` that lifts 12 cm and tilts at
capacity, a `Gunk` sphere at the riser scaled by the gunk fraction.
`PlaceableCatalog.set_vacuum_pot_state(machine, pot, frac, lid_open, gunk)`;
`ExtruderMachine._drive_pot_visual()` every frame from the model's
`primary/secondary_pot_fill_kg` (18 kg each), lid open ⇔ at capacity (the
model's alarm trigger), gunk ⇔ `vacuum_line_gunk_kg / 4 kg`.

**Measured.** `test_vacuum_pot_visual`: `PASS (22 ok, 0 fail)` — roots,
witness inside the pot's range, empty → dark/closed/no gunk, 50 % → the line
in the glass, capacity → glass full, lid lifted 0.12 m and tilted, the other
lid closed, gunk at half threshold scale 0.50, `clean_vacuum_lines()` clears
it, emptied → lid back; a ghost has none. `test_extruder_brain_wired` 24 ok.
Parse sweep 432 ok. Renders `shot_vacuum_pots_{empty, primary_half,
primary_full_lid_gunk}.png` looked at. Extruder-side batch on this code (detached, 23:00-23:06): 15 suites, 0 non-pass, 0 SCRIPT ERROR lines — `test_vacuum_pot_visual`, `test_extruder_brain_wired`, `test_line3a_flow_conformance`, `test_line3b_flow_conformance`, `test_line1_flow_conformance`, `test_line3c_identity`, `test_line3a_identity`, `test_line3b_identity`, `test_macro_part_placement`, `test_hmi_screen_zeroing`, `test_scada_dashboard_scene`, `test_l3c_unit_screens`, `test_line1_throughput`, `test_tag_snapshot`, `test_qa_loop`.

**EREMA facts found (rulings §13 addendum, with sources):** filtration
upstream of degassing; "optimised triple degassing" (preconditioning unit,
reverse degassing in the screw, the degassing zone); the Laserfilter presses
the melt through two laser-bored screen discs with a scraper disc rotating
between them and discharges through screws — the operator's §7 picture. No
pot geometry anywhere public; the photos remain the source.

## Task 10 — the doseersilo as he described it (rulings §17) — DONE 2026-09-24

**Asked / answered.** The top: "Open, no grating." The shape, from the three
renders of the old model: "basically more like a flotation tank … the three
screws going on like the bottom flat of it … tilted up slightly, about 20
degrees or 25 degrees … the bottom is the input side, the top is the output
side … the very bottom point sits at a height of about 1.7 meters … no
semicircular shapes on top of it at all … maybe 10% less wide and 10%
longer."

**Built.** `PlaceableCatalog._m_doseersilo` rebuilt: an open flat-bottomed
trough on a `Trough` frame rotated −22.5° about X (so local +Z rises —
`DOSEERSILO_TILT_DEG`, the middle of his 20-25), vertical side walls, flat
end plates, three augers along the bottom driven from the high end, four
legs cut to the tilted bottom so the body's lowest point is
`DOSEERSILO_LOW_Y` 1.7 m. The width and length come from the model he was
judging: the old half-pipe measured 3.31 m across (size.x 3.6 × 0.92) and
5.06 m long (size.z 5.5 × 0.92), so `DOSEERSILO_WIDTH_M` 2.98 = 0.9× and
`DOSEERSILO_LENGTH_M` 5.57 = 1.1×. Catalog box (3.6, 2.6, 5.5) → (3.3, 5.0,
6.2) to hold the tilt. The two 30 × 30 windows per side (§3) sit on the
trough walls and lean with it; the level range is the wall height in the
trough's frame. `MachineFlow` gives "doseersilo" its own ports instead of
sharing "silo": inlet at the low −Z end (box y 0.50), outlet at the high +Z
end (y 0.95). The grating, the half-discs, the bottom hopper are gone; the
wall depth 1.0 m (`DOSEERSILO_DEPTH_M`) is a placeholder — he gave no depth.

**Measured.** `test_doseersilo_trough`: `PASS (14 ok, 0 fail)` — tilt 22.5°,
flat bottom, 2 walls + 2 flat ends, 0 half-discs, 0 grating, lowest point
1.70 m, 2.98 / 5.57 m, 3 augers on the tilted frame, 4 legs, LineFlow finds
it, inlet at −Z / outlet at +Z, outlet ≥ 1.5 m higher, both ports in the
height band. `test_silo_level_windows`: `PASS (52 ok, 0 fail)` (was 50; the
doseersilo checks now measure the pane pairs 0.90 m apart in 3-D, centred on
the trough's plane, witnesses leaning 22.5°). Line-3C neighbours:
`test_line3c_identity` PASS, `test_line3c_seq_alignment` 11 ok,
`test_waslijn3c_overzicht` PASS (a teardown segfault after the verdict — the
known 24 % mode), `test_l3c_unit_screens` PASS, `test_tag_snapshot`
`28 ok, 0 fail, 1 skip` — identical to the 22:23 harness log, so the skip is
not new. Parse sweep 434 ok. Renders `shot_doseersilo_{topdown,
topfrontright, topfrontleft}_v2.png`, looked at and sent. The shot checker
called the top-down "blank/flat" (variance 0.000179) while it plainly shows
the trough and augers: the floor fills the frame at pitch 89, so that is the
heuristic, not the render.

**Open.** The wall depth; whether the auger motors sit at the high end (taken
from "the top is the output side"); the outlet lip. First-hand corrections
welcome on the `_v2` renders.

## Task 11 — LINE_1_FOLIE and a weight for every bale (rulings §18) — DONE 2026-09-24

**Asked / answered.** Bale type name LINE_1_FOLIE; large bales ~1000 kg,
±15 % one SD; "apply this variance/ratio whatever to all bale types that are
present in the sim thus far (since I noticed while testing that e.g. all
Rotterdam bales are the exact same weight → which is not realistic)".

**Built.** `BaleDefs`: origins `line_1_folie` (2.00 × 1.70 × 1.50 m from
§11's "about 1.70 m high, 2 m wide, 1.5 thick", `weight_kg` 1000, black,
the dirtiest and wettest feed, tagged line "1", `metal_chance` 0.10 as a
PLACEHOLDER for the metal-detect conveyor build — unused today) and
`line_1_folie_small` (each side × 0.7, 343 kg — a stated reading of "a 30
percent smaller version"); `nominal_weight(o)` (the origin's `weight_kg`,
else footprint × bulk density as before); `WEIGHT_SD_FRAC` 0.15;
`weight_factor(seq, origin)` — a Gaussian draw clipped at ±3 σ, seeded by
origin and build sequence so a headless boot reproduces its yard;
`assign_weight(body, size, origin)` sets `weight_kg` / `weight_nominal_kg`
meta and is idempotent (a body that already carries `weight_kg` keeps it).
`PlaceableCatalog`: the three bale-mass sites (`build_node`,
`_build_light_bale`, `build_yard_bale_mm`) draw through it; the yellow label
prints the body's own weight — the old ±50 kg label jitter is gone, it
faked variance on the sticker while every body weighed the same; the light
bale's label info likewise; the supplier sticker texture keeps the nominal
(one texture per supplier). `LineFlow._bale_remaining` starts from
`weight_kg` when the bale carries it. `ShredderFeedBelt` already read that
meta.

**Measured.** `test_bale_weight_variance`: `PASS (17 ok, 0 fail)`. 40
Rotterdam bales: 40 distinct weights (the old yard had 1), mean 415 kg
against a nominal 396 (+4.8 %), SD 14.0 % of the mean, range 299-536 kg
inside the ±3 σ clip (218-574), `detail_bale()` keeps 345.8 kg, LineFlow's
remaining_kg starts at that 345.8, a built LINE_1_FOLIE weighs 1106 kg with
nominal 1000 recorded. First run had one red on correct code: the mass ↔
meta equality at 1e-6, because `RigidBody3D.mass` is single precision
(CLAUDE.md trap). Neighbours: `test_bale_yard_mass_conservation` PASS,
`test_bale_sticker_supplier` PASS, `test_shredder_feed_belt` PASS,
`test_line1_throughput` PASS, `test_lump_cart_coverage` PASS. Parse sweep
434 ok.

**Open.** Metal in line-1 bales and the reversing metal-detect first
conveyor (§11) — queued, `metal_chance` waits for it. Whether the yard
should spawn LINE_1_FOLIE bales by itself (today they come from the catalog /
build menu like every origin).

## Task 12 — flake where he sees it on the wet side (task 1c, rulings §1 / §12) — DONE 2026-09-24

**Asked / answered (rounds 2-4).** Where flake is visible wet: "Kufferath
sieve / scheidingsgoot; dewatering screw trough; open top tanks, transitions
cyclones to blowers"; how it looks: "Same flake, wet and darker"; how to build
it: "Use the textured soil simulation for this". The open-top list (§12): the
doseersilo, the bunker, the bezinkafscheider, the ontwaterschroef ONLY after
the flotation tank, VSS 3A/3B, the prewash drum.

**Built.** `BeltBuilder.attach_film_field` beds — the belts' heap + GPU flake
layer, wet-tinted by LineFlow's moisture — on five machines:
- **Kufferath sieve** (`_m_kufferath`): one bed on the screen deck. The deck
  was tilted −14°, which in Godot tips local −Z DOWN — its feed box (at −Z,
  "the high end" per the builder's own comment) sat at the LOW end and the
  ports (inlet high −Z, outlet low +Z) disagreed with the mesh. Now +14°: the
  deck descends toward the outlet and the bed slides downhill.
- **Scheidingsgoot** (`_m_scheidingsgoot`): a bed in each of its five
  segments (stem, two branches, two run-outs). `_goot_segment` hands its pivot
  back through an optional array; each bed sits on a child turned 180° so it
  scrolls along the goot's −Z, downhill.
- **Dewatering screw** (`_m_dewater`): BOTH looks are built (no_merge): the
  closed tube (default) and an open half-pipe trough climbing +Z with the
  screw visible inside and a bed riding it. `LineFlow.rebuild()` calls
  `PlaceableCatalog.set_dewater_open` per instance from the graph it built:
  open when a flotation tank feeds it, closed otherwise (§12: "ONLY after the
  flotation tank; after e.g. the rafter it is closed"). Line 1's and 3A's
  screws follow a flotation tank; 3B's first follows the rafter.
- **Bunker**: a snipper bed on the travelling deck at the deck's own creep.
- **Doseersilo**: a bed on the flat bottom between the augers.
LineFlow drives EVERY field of a node now (`views`; the old first-match
`view` would have left four of the goot's five dead), reads a bed's transport
speed off the field (`bed_speed_mps` — placeholders: sieve 0.40, goot 0.60,
screw 0.15, augers 0.05 m/s) when the body has no belt_speed, and darkens the
bed with the node's moisture as before. The bed's kg include the wash water
the stream carries (open: the wet bed reads deeper than the dry flake in it).

**Measured.** `test_wet_side_beds`: `PASS (31 ok, 0 fail)`. B: the sieve
deck's +Z axis points DOWN (y −0.24), 1 sieve bed at 0.40 m/s, 5 goot beds
all downhill, both dewater looks with the tube showing and the trough hidden,
`set_dewater_open` flips them, the trough bed climbs, the auger sits inside;
the bunker bed at the deck's 0.0167 m/s; the doseersilo bed on `Trough`. P:
build_node keeps 1/5/1/1/1 beds through StaticMerge and both dewater looks.
G: flotation_tank → dw1 OPEN, rafter → dw2 CLOSED after a real `rebuild()`.
L: line 1 built by `BuildMode._build_full_line`, one Rotterdam bale, 4000
ticks (400 s): three of the four watched beds carried flake — scheidingsgoot
peak 7.8 cm at 27.8 % moisture, tint r 0.64; dewatering screw 13.7 cm at
21.9 %, r 0.74; Kufferath sieve #28 3.9 cm at 32.2 %, r 0.63 (dry = 1.00);
line 1's screw open. The fourth, Kufferath sieve #29, saw 0.0 kg: the graph
dump (`dump_line1_graph`) shows it has NO feed edge — `friction_sep#27 →
kufferath_sieve#28` only, `kufferath_sieve#29 → mas_bak#31` with nothing
into it. Pre-existing wiring on the L/R tail, not touched here; listed for
the operator below. The first two runs of the suite were red on the SUITE:
it keyed a Dictionary by LineFlow's node dicts (whose contents change every
tick, so the hash changes — `Invalid access to property or key`), then read
the tint off `_mat`, which is null in belt mode (the tint lives on the heap
material and the flake shader). Both fixed in the test; nothing in the code
was weakened. Neighbours: `test_belt_film_field` 142 ok,
`test_doseersilo_trough` 14 ok, `test_silo_level_windows` 52 ok,
`test_line1_flow_conformance` / `test_line1_throughput` /
`test_line1_twin_streams` PASS, `test_line3a_identity` / `3b` / `3c` PASS
(two teardown segfaults after the verdict — the known 24 % mode),
`test_line3a_flow_conformance` / `3b` PASS, `test_line3c_seq_alignment`
11 ok, `test_tag_snapshot` 28 ok / 1 skip (unchanged), `test_l3c_unit_screens`
PASS, `test_shredder_rate_reconciliation` PASS. Parse sweep 435 ok, lint 0.
Renders (`shot_belt_bed.gd`, now filterable by label):
`shot_belt_bed_{kufferath_sieve_wet, scheidingsgoot_wet,
dewater_screw_open_wet, bunker_snippers, doseersilo_bed, bunker_snippers_top,
doseersilo_bed_top}.png` — looked at; the walled two only show their bed from
above (the top views: the bunker's deck carpeted, the doseersilo's three
augers standing in theirs).

**Not built, and why (Phase B).** VSS 3A/3B silos and the bezinkafscheider
raft: a round silo needs a circular bed and the bezink tank's water surface
moves (BezinkTank) — both wanted a look at the real thing first. The prewash
drum's "slurry, quite turbulent": no photo of the drum interior. The
cyclone → blower gap: in every SEQ the blower stands 2-3 m BESIDE its cyclone
on the floor, while he describes the blower's suction box 10-15 cm UNDER the
cyclone mouth — a relayout question for him before any stream is drawn.
Also for him: Kufferath sieve #29's missing feed.

## Task 13 — line 1's metal-detecting first conveyor (rulings §11) — DONE 2026-09-24

**Asked / answered (round 4).** Line-1 bales hide "car wheels, plough parts,
very sometimes even an anvil, large nails, balls of wire"; only line 1 has
detection; "the very first conveyor, before the Westa conveyor, has a sensor
at about three quarters of its length: on detection it slows to a stop,
reverses about one full conveyor length to clear the debris, slows to a stop,
and runs forward again until an operator stops it or the next detection."

**Built.** `BaleDefs.roll_metal` (inside `assign_weight`): a LINE_1_FOLIE bale
rolls `metal_chance` 0.10 (placeholder) once, deterministically, and carries
`metal_pieces` / `metal_kind` / `metal_kg` (the kinds and their kg are
stated placeholders; the anvil is 4 % of hits, "very sometimes").
`ShredderFeedBelt` grew the cycle: `metal_detect` + `metal_sensor_frac`
(0.75), switched on for opzetband_1 only in `_build_opzetband`. A rider
crossing the sensor FORWARD with metal trips it → DECEL (setpoint 0) →
REVERSE (−belt_speed for one `_path_total`) → DECEL2 → NONE (forward again).
Riders move with the sign of the live speed and clamp at the load end. Going
back below the sensor re-arms it, so the belt keeps cycling on the same bale;
`request_stop()` ends the cycle where it is. On the first trip a `MetalScrap`
prop (new, `src/scenes/world/MetalScrap.gd`: wheel / plough part / wire ball
/ nails / anvil) is spawned on the bale; E takes it into the hotbar
(`crosshair_interact`), which takes the piece and its kg off the bale and
clears the alarm and the head's METAL lamp (the two dots on the detector
cabinet are now named and no_merge). Dropping it within 3 m of a waste
container puts its kg in as METAL (class 3). One `METAL-DETECT` alarm per
trip on the bus, severity 2, not a latched belt fault.

**Found on the way: the #196 detector head had never once been attached in
a real build.** `_build_opzetband` grafted it onto the belt's `InclinePivot`,
which `ShredderFeedBelt` only builds in `_ready()` — and the belt is not in
the tree when `_build_opzetband` runs (build_node adds the model afterwards),
so the graft found no pivot and returned. Probed 2026-09-24: `build_node(
"opzetband_1")` + two frames → no `MetaalDetectorHead`. The coil tunnel,
cabinet, lamps and REJECT placard existed only in code. Now grafted on the
belt's `ready` (one shot), or at once if it is ready; `test_line1_metal_detect`
asserts the head is on the built belt. First render of the belt WITH its
head: `docs/plant/renders/shot_opzetband_1_head_on.png`.

**Measured.** `test_line1_metal_detect`: `PASS (22 ok, 0 fail)`. M: of 60
LINE_1_FOLIE bales 11 hid metal, all with a kind and kg; Rotterdam 0 of 30.
C (a 10 m @ 25° belt at 0.12 m/s, `_process` driven at 0.1 s): trip 1 at
64.9 s at progress 0.751; min live speed −0.120 m/s (a full reversal); the
rider carried back to progress 0.000; trip 2 167.0 s after the first on the
same bale; 2 alarms on the bus; a wheel `MetalScrap` on the bale; the
operator's stop → speed 0.000 after 15 s, cycle off; scrap taken → bale
clean, alarm cleared, scrap a world prop; restart → no further trip, the
bale fed through in 248 ticks. N: the same bale on a belt without the sensor
fed straight through in 897 ticks, 0 trips. P: opzetband_1 built with the
sensor at 3/4, the head present, lamps named; opzetband_3a3b without. Three
test-side defects on the way, all in the suite: the bale rode CROSS-WISE and
both belts latched BELT-JAM after 5 s (laid lengthwise now, as
`test_shredder_feed_belt` does); the stop check read the speed 6 s into a
2.5 s ramp (0.011); and two "fed through" flags were set from a lambda —
GDScript lambdas capture locals BY VALUE, so the outer flag never moved
(the checks now read `rider_count()`). Neighbours: `test_shredder_feed_belt`
PASS, `test_bale_weight_variance` 17 ok, `test_line1_throughput` PASS,
`test_line1_flow_conformance` PASS, `test_line1_overband_mount` PASS,
`test_bale_yard_mass_conservation` PASS, `test_line1_no_false_overload` PASS, `test_line1_twin_streams` PASS, `test_bale_sticker_supplier` PASS. Parse sweep
437 ok, lint 0.

**Open (for him).** What the scrap looks like and weighs, and how often a
line-1 bale hides one; whether the belt really re-trips on the same bale
until someone intervenes (built that way from his words); where the removed
scrap goes in Geleen (a scrap bin?); whether the #196 head's side-reject
chute exists at all — his §11 describes a reversal, not a side reject.

## Task 14 — the line-1 tail: one separator feeds both sieves, and the extruder end was never fed (round 7) — DONE 2026-09-24

**Asked / answered.** "Line 1's tail: after the dewatering screw there is ONE
friction separator, then TWO Kufferath sieves side by side… the graph shows
only one sieve is fed." → **"One separator feeds both sieves (split)."**

**Built.** The tail pairs in `LINE_1_SEQ` (Kufferath sieves, MAS bakken, MAS
dryers, blowers) carry `"stream": "L"/"R"` tags: the separator becomes the
split (first member of each train), each side chains head-to-tail to its
blower, both blowers merge at the cyclone — the same mechanism as the
scheidingsgoot split. Measured before/after with `dump_line1_graph`: the
tag adds exactly one edge (`friction_sep#27 → kufferath_sieve#29`); both
Kufferath beds now fill in the wet-side suite (2.4 cm each, 32.2 % moisture,
tint r 0.63 — the flow halves, 3.9 cm on one sieve before).

**Found on the way, and fixed: line 1's extruder end had never been fed.**
The same dump showed `cyclone#36 → blower#34` (a blower → cyclone → blower
2-cycle) and `compactorband#38 → blower#34`, with `blower#34` at in-degree 3
and `extruder_1#39` fed by nothing. Cause: consecutive MAIN entries of a SEQ
get no explicit edge; LineFlow's nearest-input-port fallback wires them, and
at the tail the nearest inlet to both the cyclone's bottom mouth and the
compactorband's lip is blower L's. Both edges are pinned with
`explicit_from_prev` (the flag 3B already uses for its 15 m pneumatic legs).
After: `cyclone#36 → extruder_silo#37 → compactorband#38 → extruder_1#39 →
laser_filter#40`, no cycle, no merge at the blower — and
`test_line1_throughput` banks **23.7 kg of granulate after 600 s where it
banked 0.0** (its own ungated info line, unchanged text, first non-zero
reading). Neither the 2-cycle nor the dead extruder had a failing check:
the tests assert the head chain and the twin streams, and the graph trap in
CLAUDE.md said to dump before believing — this is that trap on the other end
of the same line.

**Measured.** `dump_line1_graph` before/after (above). `test_line1_twin_streams`
PASS, `test_line1_flow_conformance` PASS, `test_line1_throughput` PASS
(granulate 23.7 kg), `test_line1_no_false_overload` PASS,
`test_macro_delta_guard` PASS, `test_line1_overband_mount` PASS,
`test_shredder_rate_reconciliation` PASS, `test_wet_side_beds` 31 ok (both
sieve beds filled). Not touched: whether the other lines' tails (3A/3B/3C
extruder ends) lean on the same fallback — worth one dump each.

## Task 15 — the vacuum-pot cleaning mini-game (P3 stage B, rulings §14) — DONE 2026-09-24

**Asked / answered.** Round 5: P3 yes, "but this is operator simulation
stuff" — not a hold-E, a mini-game he narrated end to end (§14, the design in
`docs/DESIGN_vacuum_pot_minigame_2026-09-23.md`). Round 7: build it next.

**Built.** Six pieces, every step of his sequence one call:
- `ExtruderModel`: `vacuum_alarm_pot` names the pot whose lid the melt
  pushed; `vacuum_alarm_elapsed_s` counts the seconds the vacuum has been
  gone — through VACUUM_ALARM and on into the FAULT it cascades to; a new
  input `pot_emptied` zeroes a pot in any state; `vacuum_restored` is REFUSED
  while a pot is at capacity (event `vacuum_restore_refused_pot_full`), so the
  old hold-E on the extruder can no longer wave a pushed-open lid away (it
  still clears the manual `vacuum_lost`).
- `VacuumPotService` (static, `src/scenes/interactions/`): the lid pull —
  required seconds = 2 + 1 per minute the vacuum has been gone (his "harder
  and harder"); letting go springs it back; the parked lid; a `MeltBlock` of
  the pot's kg spawned inside; four planes × four cells; `push()` gains
  1.0 → 0.45 of a cell as the melt stiffens over three minutes, times a
  0.6-1.0 draw (his "might only go halfway … then three quarters or all the
  way"); a push with the tool still in is refused — `pull_out()` first; every
  plane ≥ 0.90 (his testing value) frees the block, which drops 1 cm down and
  forward; `take_block()` hands it out and tells the model; `relid()` seats
  the lid and asks for the vacuum. Every number marked PLACEHOLDER in the
  file is his to set after playing.
- `VacuumPotInteract` (`VacPot_<name>/PotService`, a crosshair body around
  each dome): hold E pulls the lid; E pushes the plamuurmes into the cell the
  crosshair ray hits on the dome (upper = top plane, lower = bottom, else
  left/right; the cell by quadrant), E again pulls it out; E takes the freed
  block into the hotbar; E puts the lid back. Prompts say which.
- `MeltBlock` (carryable): dropped within 3 m of a lump cart with room it
  goes in as lumps (`receive_lump`), else into a waste container, else it
  lands as a prop; mass conserved (`dump_into`).
- `PlamuurmesTool` (catalog `tool_plamuurmes`, Tools): the putty knife, held
  like the wrench; the pot checks it is the active slot.
- `PlayerController._update_generic_hold`: any crosshair interactable with
  `crosshair_hold_tick(delta, player) -> 0..1` gets E held on it; the first
  user is the lid.
- `ExtruderMachine`: the E hint at the extruder now says "pot primary is
  full — pull its lid and clean it (at the pot)"; past the two minutes the
  FAULT broadcast adds `laserfilter_error` (primary pot) / `headfilter_error`
  (secondary) — his "a different HMI alarm reports the shutdown due to laser
  filter error"; both clear when FAULT is left.
- `PlaceableCatalog.set_vacuum_pot_state` leaves a lid alone while the pot's
  root carries `lid_off` (the parked lid used to be driven back every frame).

**Measured.** `test_vacuum_pot_minigame`: `PASS (33 ok, 0 fail)` on a real
`extruder_3a` build with its SimBrain. The full pot → VACUUM_ALARM naming
'primary', one 'vacuum' alarm on the bus; the shortcut refused; only the full
pot's lid pullable; 2.0 s at the alarm, 7.0 s five minutes in; a half pull
springs back; the lid off after 2.1 s, parked 9 cm below its seat and
leaning; an 18 kg block inside; the first push 68 %, the second refused; 31
pushes to free it, top/bottom/left 1.00, right 0.94; the block 1 cm down and
forward; taken → pot 0.0000 kg (the alarm tick's degassing re-condenses
micrograms — the check reads < 0.01); 18 kg into the cart whole; the lid
back at 2.4 s → RUNNING, 'vacuum' cleared; a second full pot untouched for
125 s → FAULT with 'fault' + 'laserfilter_error' and no head-filter alarm;
the lid then needs 4.1 s and can still be cleaned in FAULT; the line stays
FAULT until `operator_clear_fault`. Neighbours: `test_vacuum_pot_visual` 22
ok, `test_extruder_brain_wired` PASS, `test_line3a_flow_conformance` PASS,
`test_tool_placement_mode` PASS, `test_hmi_screen_zeroing` PASS,
`test_scada_dashboard_scene` PASS, `test_keybind_sheet` 24 ok. Parse sweep
442 ok, lint 0. Two suite-side faults on the way, in the audit trail of
CLAUDE.md's traps: a new `class_name` is unknown to a standalone headless run
(the suite idled to its watchdog — the service is now referenced by preload
path), and `call()` into an `Array[String]` parameter needs a typed array.
Renders: `shot_tool_plamuurmes.png`; `shot_vacuum_pots_lid_off_block.png`
and `shot_vacuum_pots_block_free.png` from the stage-A shot tool (the lid
leaning against the dome, the block inside).

**Not proven headless, for him to play.** The feel: every PLACEHOLDER (pull
time, stiffness curve, cells per plane, the push draw); which way "towards
the player" is (the block shifts +X, the sight-glass side); whether the
cell the ray picks on a 25 cm dome reads as his planes; the hotbar carry of
an 18 kg block (no weight penalty yet).
