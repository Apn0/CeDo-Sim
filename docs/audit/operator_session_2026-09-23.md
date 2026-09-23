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
