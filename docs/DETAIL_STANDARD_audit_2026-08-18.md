# CeDo_Simulator vs the ConveyorSim Engineering Standard — Full Audit, 2026-08-18

This is not a claim that CeDo_Simulator is broken, nor a claim that it is now fixed. It is a
precise, ranked map of where a 285-file, ~105k-line, actively multi-session-edited codebase
currently stands against a standard extracted from a much smaller, single-purpose reference
project (ConveyorSim), produced by walking 16 independent audit lenses over the machine
catalog, physics layer, HMI mockups, test suite, render tooling, vehicle fleet, and flow
simulation, then adversarially re-checking every finding before it is listed here. Every row
below is either directly actionable today or explicitly marked as needing an operator
photo/spec before it can be. Nothing here should be read as "fix all of this now."

## 1. The standard, as a checklist (self-contained)

**Provenance discipline**
- Q1 — Does every numeric constant carry an explicit tag for how it's known (OPERATOR /
  CATALOGUE / PHOTO / TYPICAL), with no untagged numbers? ("A number with no tag is a bug in
  this project.")
- Q2 — Does an OPERATOR tag cite a specific file+line/document, not just "the operator said so"?
- Q3 — Does the spec warn against stapling one machine's measured dimensions onto a different
  machine, and against re-citing a prior model's own unsourced constants as if grounded?

**Physics-as-the-driver**
- Q4 — Is every part that should physically rotate a real RigidBody3D on a real hinge/joint on
  its true axis — never a script-spun mesh, never a kinematic stand-in?
- Q5 — Where engine mesh/shape axis and joint free-axis conventions disagree, is that mismatch
  documented and corrected with two distinct, named transforms?
- Q6 — Is rotational inertia computed explicitly from real cross-section (e.g. hollow-tube),
  with the size of the engine-default error actually measured?
- Q7 — Is bearing/friction drag modeled as real Coulomb friction (not the engine's viscous
  default), with the discrepancy between the two measured?

**No invisible helpers**
- Q8 — Are physically impossible/cosmetic collision shortcuts explicitly forbidden in comment,
  with the reason stated?
- Q9 — When such a shortcut was introduced anyway, is the resulting failure mode measured and
  stated in real terms, not glossed over?

**Measure, don't assert — twice**
- Q10 — For any claim that could be true "by accident," is there a second, independent
  measurement that could only pass if the first is genuinely true?

**Mutation-provable tests**
- Q11 — For each automated check, is there a concrete code change that would flip it green→red,
  and has that failure mode actually happened once in the project's own history?
- Q12 — Is there a pass whose only job is proving the validators themselves fire, by feeding
  each one a case constructed to be invalid?

**Honest gaps**
- Q13 — Does the project document at least one place where its model and reality disagree,
  rather than silently averaging the discrepancy away?

**Render-and-inspect discipline**
- Q14 — Does the render pipeline detect and refuse a "succeeded but produced nothing visible"
  false pass, by checking actual pixel content?
- Q15 — Does every generated image get a unique, content-derived filename, so a batch cannot
  silently collapse into one overwritten picture?

---

## 2. Ranked, deduplicated findings

Severity is the worst-case read against the checklist above. Where the same defect pattern
recurred across multiple machine families, rows are merged and cite every site found rather
than being repeated.

### CRITICAL

| # | Subsystem | Finding | Sites |
|---|---|---|---|
| C1 | Physics / whole machine catalog | Zero rotating parts anywhere (belts, shredders, wash line, sorting line, pumps, fans) are RigidBody3D+HingeJoint3D. All 35+ "spinning" parts route through `RotatingMechanism.gd`, a plain Node3D that writes `transform.basis` directly each frame — the exact kinematic fake Q4 forbids. A further ~12 parts (extruder screw, PCU cutter disc, melt-pump shafts, sink/float skimmer) are described as rotating in comments but built fully static. Repo-wide `grep HingeJoint3D` returns 0 real hits (1 hit is an unused addon script). | `RotatingMechanism.gd:99-104`; `PlaceableCatalog.gd` (34+ `_spinning_cyl` sites incl. 7889, 7010, 7054, 8412-8623, 9105, 4249-4257); `BeltBuilder.gd:363-417`; `PlaceableCatalog.gd:10546-10572` (PCU disc static), `:2691-2692` (melt-pump shafts static), `:5053-5062` (skimmer static despite motor) |
| C2 | Vehicle fleet | Every vehicle's wheels are deleted from the physics tree on tick 1 (not merely kinematic — actually removed), on a chassis frozen kinematic. 0 of ~12 vehicle types (Forklift, Merlo, MerloP40, BaleClamp, MastLift, 7 Car.gd cars) keep a live wheel joint of any kind. | `BaseVehicle.gd:269-270, 1852-1896, 1317-1328` |
| C3 | Shredder sim | Rotor rpm has zero causal effect on reported throughput — `throughput_kg_h` is pure feed/rated-bucket math, never reads `current_rpm()`; instant on/off flips throughput instantly regardless of rotor spin-up state. | `ShredderMachine.gd:101-133, 95-98` |
| C4 | Extruder HMI numbers | Four sites present "138 rpm / 187 kW / 112°C / 169 kW" as a direct "3C HMI" read-off; cross-checked against ~15 captured HMI photo frames, only 112°C matches, 169kW/187kW appear in none of them, and 138 rpm exceeds the plant's own documented 130 rpm ceiling. | `PlaceableCatalog.gd:7168, 7255`; `Line3CDef.gd:31-33`; `ProcessModel.gd:177` (currently mid-edit by another session — flagged, not attributed) |
| C5 | Wash line | The live wash-line placeable `prewash_drum` ships an 18-line unsourced stub while the operator-reviewed, photo-signed-off trommel geometry (`_m_vw_trommel`) sits under an unused sibling id, with a "2.5x scale" label that matches neither model's real dimension ratios nor rpm values. | `PlaceableCatalog.gd:394, 1682, 8668-8686` vs `:392, 1730, 9931-10081`; `photo_audit.md:68` |
| C6 | Sorting line | TITECH/TOMRA NIR sorter's "modelled from operator photos" claim is directly contradicted by the project's own primary ledger, which marks this exact machine "not modelled (stubs only)" and flags the cited photo as showing a different machine. | `PlaceableCatalog.gd:8349`; `photo_audit.md:50-51`; `titech_tomra.md:80` |
| C7 | Building/structure | MS/LS silo and EOP-endpoint geometry cite `silos_ms_ls.md` and `eop_rafter.md` by name and section/flag number — documents the project's own later audit ("de-fabrication" pass) already found do not exist in the repo. | `PlaceableCatalog.gd:460-462, 2898-2911, 3010`; `fixed_equipment_inventory.md:3` |
| C8 | Building/structure | `door_personnel` / `gate_roller` / `window_frame` dimensions carry zero provenance — only a vague "nominal ... standard industrial opening" adjective, no doc anywhere in `docs/plant/`. | `PlaceableCatalog.gd:94-96` |
| C9 | HMI screens | "Water Circuit Lijn 3C-6" — one of only 5 screens actually wired live into the game — shows a permanent fake "Pomp Indaver niet actief" alarm that can never clear, because its div color doesn't match the shell's alarm-binding regex. | `Water Circuit Lijn 3C-6.dc.html:25-26`; `hmi_shell.html:385-392`; `HmiScopes.gd:236` |
| C10 | Render tooling | All 10 render/screenshot tools (`shot_*.gd`) save a PNG and declare success with zero check of actual pixel content — a headless/empty-scene run would silently "succeed." | `shot_placeable.gd:67-68`, `shot_flakes.gd:71-73`, `shot_bale_clamp.gd:127-128`, `shot_discharge_station.gd:60-62`, `shot_clamp_cab.gd:54-56`, `shot_cart_forkholes.gd:48-50`, `shot_annotate_flotation.gd:125-127`, `shot_annotate_extruder.gd:147-149`, `test_bale_shredder_pipeline_shots.gd:284-290` (×7 shots) |
| C11 | Crew/NPC proof | The single real-MainWorld npc-05 proof (`test_npc05_realworld.gd`) is not wired into `tools/regression/run.sh`'s gating loop (appears only in a comment), and its own last recorded run is a documented FAIL (stalls at DRIVE_TO_INDOOR, 33.9m short). A backlog doc still reads as if it's proven. | `run.sh:270-273` (comment only, real loop at :222); `CLAUDE.md:309-345`; `BACKLOG_ultracode_2026-07-19.md:53-55` |
| C12 | Crew/NPC proof | Nine crew/NPC claim-clusters (S2-S4, S6-S10: cart/filter geometry, lump-chunk physics, role gates, force_task, CrewManager wiring, feeder-shift ghost fix #233, board release/retry, dump-credit) lost their only proof when `NpcTaskBench` was deleted 2026-08-17 per operator ruling; the ruling's own required follow-up ("re-establish the proof in a real MainWorld boot") has not happened for any of the nine. | `operator_rulings_2026-08-17.md:76-93`; `test_npc_task_bench.gd.bak_deleted20260817`; `BACKLOG_ultracode_2026-07-19.md:80` |
| C13 | Flow simulation | Every Line-3C stage conveys mass at MachineFlow's generic default of 6.0 kg/s (21,600 kg/h) — 12.8x the line's own operator/HMI-calibrated design throughput (1687 kg/h) that the parallel amps/energy model already uses correctly. The two models of the same line disagree by an order of magnitude and nothing catches it. | `LineFlow.gd:562-599, 2115`; `ProcessModel.gd:24`; `MachineFlow.gd:34` |

### HIGH

| # | Subsystem | Finding | Sites |
|---|---|---|---|
| H1 | Provenance (systemic) | No ConveyorSim-style tag vocabulary (OPERATOR/CATALOGUE/PHOTO/TYPICAL) exists anywhere in `src/` — 0 repo-wide matches. Confirmed independently in belts, extruder (20/21 `ExtruderConfig.gd` fields), wash line (0/8 builders), sorting line, water/utility (`BezinkTank.gd`, `AirNetwork.gd`), colour (`_STEEL`/`_DARK`), flow-sim (`LineFlow.gd`/`MachineFlow.gd`), and bale-yard (`BaleDefs.gd`) — this is one systemic gap, not eight separate ones. | `ExtruderConfig.gd:16-72`; `BeltBuilder.gd:74-104`; `PlaceableCatalog.gd:1102,1109` (belt), wash builders (no line refs — absence); `BezinkTank.gd:19-27`; `AirNetwork.gd:35-45`; `LineFlow.gd:30-50`; `MachineFlow.gd` (49 rate overrides); `PlaceableCatalog.gd:1590-1597` (_STEEL/_DARK) |
| H2 | Belts | Every CeDo roller (transport/opzetband/switch belt family) is either a kinematic `RotatingMechanism` spin or a fully static `_cyl` mesh — same root cause as C1, called out separately here because it is the project's flagship "physics-driven conveyor" claim and the standard's namesake system. | `BeltBuilder.gd:363-417`; `PlaceableCatalog.gd:2298-2310` |
| H3 | ShredderFeedBelt | Bales never physically contact the belt or its rollers — position is scripted directly from a progress fraction each tick, completely independent of collider/roller state (Q8/Q9 invisible-helper pattern, undocumented). | `ShredderFeedBelt.gd:985-1010, 916` |
| H4 | Extruder | 20 of 21 `ExtruderConfig.gd` numeric fields are untagged; several (`vacuum_alarm_grace_s`, `DIE_PRESSURE_BASE_PSI`) go further and claim "operator-documented"/"per operator" provenance in prose with no file named — the specific failure mode Q2 calls worse than plain-unsourced. | `ExtruderConfig.gd:16-72` |
| H5 | Extruder | The one real per-line operator dataset in this family (FORM-008's 7-zone barrel-temperature chain for line 3A) is never wired into any config — `zone_temp_setpoints` is empty everywhere, so the one grounded number never reaches the running sim. | `extruder_3a_setpoints.json:206-263`; `ExtruderConfig.gd:35`; `ExtruderModel.gd:279-294` |
| H6 | Shredder | Two independent, disagreeing motor-overload/trip models run on the same shredder node simultaneously (ShredderMachine's own 118%/5s vs LineFlow's shared amps-based MotorOverload at ~135%/3s); the shared model's own doc comment uses the shredder as its worked example, so this is a duplication, not a missing feature. | `ShredderMachine.gd:46-48`; `LineFlow.gd:688-692, 775-777`; `test_tag_snapshot.gd:695` |
| H7 | Wash line | 0 of 8 wash-line builders use any provenance tag; only `_m_flotation` cites anything at all, and even that is an informal internal issue number, not a `docs/plant/` file+line. | `PlaceableCatalog.gd:3586, 3673, 4991-4993, 5172, 6997` (untagged); `:4690-4696, 4814-4829` (informal citation) |
| H8 | Sorting line | Bunker's genuinely OPERATOR-sourced speed/fill setpoints (component_flags_review.md rulings B3/B4) carry zero citation at their point of definition, and the doc's own recorded 600-vs-875 rpm discrepancy (flagged as "keep visible") is silently dropped rather than carried into the code as a comment. | `PlaceableCatalog.gd:7714-7721`; `component_flags_review.md:109-120`; `hmi_reference.md:236-252` |
| H9 | HMI screens | BluPort Overzicht/Modulegrid/Storingstabel (3 mockup screens) plus the live in-game `ExtruderBluPortScope.gd` all hardcode a permanent "LDPE 800 kg/h 22.04.2024 IBN" recipe banner that nothing at runtime can ever overwrite — the last of these is not a mockup, it is the actual runtime HMI overlay a player opens. | `BluPort Overzicht Lijn 3C.dc.html:26`; `BluPort Storingstabel Lijn 3C.dc.html:22`; `BluPort Modulegrid Lijn 3C.dc.html:22`; `ExtruderBluPortScope.gd:243` |
| H10 | Test coverage | Washing family (`centrifuge`, `mech_dryer`, `thermal_dryer`) has zero test coverage despite dedicated sim code exists for it, unlike every sibling machine family (extruder screw, cutter-compactor, motor overload all have dedicated tests). | `MechDryerCycle.gd`, `MechDryerModel.gd` (no matching test file) |
| H11 | Water/utility | Water pump 3D models have no rotating impeller/shaft in 0 of 4 placements, versus the one pump that IS spun (`vacuum_pump`) — the builder function to do this correctly already exists in the same file and is simply not applied here. | `PlaceableCatalog.gd:5251-5299, 8238-8242` vs `:9093-9119` |
| H12 | Water/utility | `BezinkTank.gd`'s 5 level-control constants governing a real EOP-feeding settling tank are entirely untagged, unsourced numbers. | `BezinkTank.gd:19, 23, 24, 26, 27` |
| H13 | Water/utility | `AirNetwork.gd`'s 5 header-physics constants are untagged, and the one real OPERATOR-sourced air-pressure figure in the docs (Tomra target 3-5 bar) is never read by or reconciled against the 7.0 bar header the code actually simulates. | `AirNetwork.gd:35, 37, 40, 42, 45`; `shift_checklists.json:37` |
| H14 | Flow simulation | `bunker.md` is cited by name and section for a derived "4.6-18.4 kg/s" rate band; that document does not exist anywhere in the repo and the figure appears nowhere in `docs/plant/`. | `MachineFlow.gd:236-245` |
| H15 | Flow simulation | `prewash_drum`'s flow-topology rate defaults to 21,600 kg/h though the operator gave an explicit measured ceiling of 1450 kg/h for this exact machine (14.9x over, and the doc already flags a prior 3.1x-over guess as wrong). | `MachineFlow.gd:107-110`; `photo_audit.md:72` |
| H16 | Flow simulation | Shredder/mill flow-topology rate (generic 21,600 kg/h default) disagrees with `ShredderMachine.gd`'s own documented 4500/2200 kg/h rated caps for the same physical machines. | `MachineFlow.gd:76-79`; `photo_audit.md:61` |
| H17 | Flow simulation | `FEED_RATE`/extruder sink rate (8.0 kg/s = 28,800 kg/h) is untagged and >6x the entire plant's documented 4500 kg/h total film-intake capacity, and 20-40x a single extruder line's documented 1200-1450 kg/h output. | `LineFlow.gd:30`; `MachineFlow.gd:56, 71`; `misc_sources.md:152, 206`; `hmi_reference.md:111, 125` |
| H18 | Vehicle fleet | Wheel meshes never rotate for forward travel at any speed — only steering yaw is applied; not even the "cosmetic mesh spun by script" minimum-violation fallback exists. | `BaseVehicle.gd:1783-1812` |
| H19 | Vehicle fleet | No BearingDrag-equivalent friction model exists anywhere in the fleet; the only friction/damping code found acts on carried cargo (bales/sheets), never on any wheel or axle. | grep of `src/scenes/vehicles/*` for `BearingDrag|angular_damp|friction` — only `BaleClamp.gd:176-177, 488-490` |
| H20 | Building/structure | `build_door()`/`build_gate()` hand-roll `StandardMaterial3D` and bypass the shared `_mat()` helper — the only two Structure placeables in the catalog that never receive the project's mandatory grime texture (Rule 8). | `PlaceableCatalog.gd:9277-9281, 9310-9313` vs `:1935-1952` |
| H21 | Colour/paint | `_STEEL` and `_DARK` — the two most-reused shared colour constants, feeding the frame/base/trim colour of essentially every `_m_*` builder — carry zero provenance, while the third constant defined alongside them (`_SAFETY`) is fully photo-cited. | `PlaceableCatalog.gd:1590-1597` |

### MEDIUM

| # | Subsystem | Finding | Sites |
|---|---|---|---|
| M1 | Extruder | Only 1 of 5 extruder lines has a per-line `.tres` config, and it is a byte-for-byte copy of the class defaults, not measured 3B data — the exact pattern Q3 warns against. | `Extruder3B.tres:9-26`; `MachineBrains.gd:123-145` |
| M2 | Extruder | 12 of 13 extruder-train catalog footprints (extruder_3a/3b/1/3c/6, plasmaq, laser_filter, melt_pump, extruder_screw, vacuum_degas, kopfilter, heetafslag) carry no dimension citation, against one correctly PHOTO-tagged sibling entry (`extruder_silo`) in the same file. | `PlaceableCatalog.gd:152-161, 445-448` vs `:97-108` |
| M3 | Extruder | Extruder screw auger is never modeled in any of the 3 extruder placeables — defensible (screw is hidden inside a real barrel) but never stated as a deliberate scope decision. | `PlaceableCatalog.gd:2716-2736, 7256-7278, 10468-10586` |
| M4 | Extruder | Compactor and `pcu_cabinet` claim operator/photo provenance in prose with no file+line pointer. | `PlaceableCatalog.gd:363-368, 83-86` |
| M5 | Shredder | Shredder 2's rotor rpm silently defaults to 45 (Shredder 1's value) though the operator's own doc gives Shredder 2 a fixed 55 rpm setpoint — no code path can currently reach the documented number. | `PlaceableCatalog.gd:7963-7970, 7889, 2298`; `misc_sources.md:174, 180` |
| M6 | Shredder | "≤10x10cm output" chunk-size spec, and ~10 internal chamber/rotor/discharge dimensions, carry no citation anywhere in `docs/plant/` despite sitting beside genuinely-sourced numbers in the same function. | `PlaceableCatalog.gd:171, 7811`; `:7828-7945` (leg_top, chamber_h, rotor_r, n_knives, etc.) |
| M7 | Belts | Roller strategy is inconsistent across belt families with no comment explaining why: 4 belt types (scraper/compactor/inclined/metal) render zero rollers, 1 (switch_belt) renders dead static rollers. | `BeltBuilder.gd:363-417`; `PlaceableCatalog.gd:2461, 4381, 7356, 8164, 3955` |
| M8 | Belts | No inertia model and no bearing-drag model exist for any roller — there is no RigidBody3D to give either concept meaning yet. | `RotatingMechanism.gd` (full file) |
| M9 | Belts | Belt test suite (`test_belt_discharge_geometry.gd`, `test_feed_belt_orientation.gd`) is genuinely mutation-provable but 0% of it touches roller/transport physics, because none exists to test. | both files |
| M10 | Wash line | Prewash drum rpm is internally inconsistent between the two builders the catalog's own "2.5x scale" label implies are the same machine: 28 rpm vs 14 rpm, neither cited. | `PlaceableCatalog.gd:8679` vs `:9954` |
| M11 | Wash line | Centrifuge and mechanical dryer carry zero citations despite dedicated reference docs existing in the repo; the project's own photo-audit ledger already marks both rows unreviewed. | `PlaceableCatalog.gd:3580-3660, 3663-3690`; `photo_audit.md:89, 95` |
| M12 | Sorting line | Trilzeef vibration spec (8cm/8Hz) is labeled "operator's trilzeef spec" in two places; no such document exists anywhere in `docs/plant/`. | `VibratingPivot.gd:6`; `PlaceableCatalog.gd:6730-6732` |
| M13 | Sorting line | Trilzeef/ballistic_sep/wind_sifter catalog dimensions are completely uncited, in the same file/block where neighboring entries (rafter, bunker) demonstrably use a citation convention. | `PlaceableCatalog.gd:359, 377, 378` |
| M14 | Sorting line | Ballistic separator and windshifter geometry were built while the project's own photo-identification of "which machine is this" is still an open question mark in the audit ledger. | `photo_audit.md:51` |
| M15 | HMI screens | Waslijn 3A/3C Storingen Lijst screens each hardcode a fully static, 25-30-row fabricated-looking fault history inside DCLogic with zero binding path to any real state. | `Waslijn 3A Storingen Lijst.dc.html:65-95+`; `Waslijn 3C Storingen.dc.html:64-79` |
| M16 | HMI screens | BluPort Storingstabel additionally hardcodes a 5-entry active-fault table gated by a design-time-only `faultsVisible` prop that defaults true and nothing at runtime can ever set false. | `BluPort Storingstabel Lijn 3C.dc.html:127-136` |
| M17 | Test coverage | `test_bale_shredder_pipeline_shots.gd` is the vacuous-bench pattern by name: zero assertions, hand-injected `buffer_kg`/`motor_load_pct` via `.set()`, unconditional `quit(0)`. | `test_bale_shredder_pipeline_shots.gd:84-86, 107-110, 160-162` |
| M18 | Test coverage | 7 of ~22 placeable categories (Pumps, Platforms, Walls, Decals, Size reduction, Sorting/bunker, Tools) have zero test-id references anywhere in `src/tests/`. | grep across `src/tests/*.gd` |
| M19 | Render tooling | No `shot_*.gd` tool has a runtime headless guard — every one relies on a human reading a code comment before invoking Godot with the right flags. | comment-only warnings in `shot_discharge_station.gd:5`, `shot_l3c_unit_screen.gd:9-10`, `tool_render_3c_mimic.gd:17` |
| M20 | Render tooling | Render coverage is thin and recent-session-skewed: 22 PNGs on disk cover ~8 distinct machines/screens out of 180 catalog ids, with no tracking of what's been visually audited. | `docs/plant/renders/` (22 files) vs `PlaceableCatalog.gd` (180 `"id":` entries) |
| M21 | Crew/NPC proof | Break rotation, jam dispatch, and the 2-2-2-4 rota are proven only by a bare-`SceneTree` bench (`test_crew.gd`) that isn't wired into the harness at all. | `test_crew.gd:1-12` |
| M22 | Crew/NPC proof | `CLAUDE.md` still cites `NpcTaskBench.gd:68` for the F8 trap after the file was deleted 2026-08-17 — a citation that didn't survive the deletion sweep that removed its own target. | `CLAUDE.md:201-204`; `NpcTaskBench.gd.bak_deleted20260817` |
| M23 | Vehicle fleet | Fleet drivetrain constants (`speed_limit_kmh`, `engine_power_kw`, `brake_torque_nm`, throttle/brake ramp rates) carry no provenance tag; the one vehicle doc in the repo is a daily-inspection checklist with no performance numbers to cite. | `BaseVehicle.gd:19-24`; `Forklift.gd:128-129` |
| M24 | Vehicle fleet | None of the 4 vehicle test files assert anything about wheel physics, inertia, or joints — deleting the wheel-removal logic entirely would change zero test outcomes. | `test_vehicle_census.gd`, `test_merlo_p40.gd`, `test_nested_vehicle_drift.gd`, `test_vehicle_spawn_frame.gd` |
| M25 | Water/utility | LineFlow's compressor sizing and per-consumer air demand are justified by circular game-balance language ("sized so it holds nominal with headroom") rather than a catalogue/operator number, and are untagged. | `LineFlow.gd:842-845, 853` |
| M26 | Flow simulation | `FEED_DENSITY=320 kg/m³` is a previously-logged, still-unfixed contradiction — flagged by the project's own audit 6 weeks before today (2026-08-18) as matching neither loose-film infeed nor PCU-output density, and unchanged since. | `LineFlow.gd:31`; `densities.md` §4 |
| M27 | Flow simulation | `TRANSPORT_MPS=1.3` (all connector transit timing derives from this) is untagged with no matching belt-speed figure found anywhere in `docs/plant/`. | `LineFlow.gd:50` |
| M28 | Building/structure | `riveted_steel_column` and `concrete_v_beam` dimensions carry zero provenance comment of any kind — not even a placeholder caveat, unlike neighboring silo entries. | `PlaceableCatalog.gd:573-580` |
| M29 | Bale yard | `CloseLODSticker` on the near-LOD bale body is still off-white — the operator-confirmed bright-yellow sticker fix landed in 2 of 3 render paths (`LabelItem.gd`, yard-sticker MultiMesh) but not this one, whose comment still asserts a now-false rationale. | `PlaceableCatalog.gd:5953-5959` vs `LabelItem.gd:33, 163` and `PlaceableCatalog.gd:6196` |
| M30 | Bale yard | `wire_compliance`/`clamp_force_needed` (gate real interactive clamp-grab mechanics) recur untagged across ~10 sites with zero provenance vocabulary anywhere in the codebase. | `PlaceableCatalog.gd:1505, 1510, 6285, 6288`; `BaleClamp.gd:15, 26, 39, 102, 358, 362, 427`; `HUD.gd:1112-1118` |
| M31 | Colour/paint | ~150 per-machine catalog-dict colours are bare literals with zero comment, unlike the one silo pair that explicitly flags its own colour as unsourced ("RAL undocumented, flag 12") — proving the honest-gap pattern is known but not applied. | `PlaceableCatalog.gd:368-479` vs `:460-462` |
| M32 | Colour/paint | Descriptive labels like "RAL-blue" and "TOMRA orange" read as citations but name no real RAL code or photo. | `PlaceableCatalog.gd:3582, 380-383` |

### LOW

| # | Subsystem | Finding | Sites |
|---|---|---|---|
| L1 | Physics (systemic) | `RotatingMechanism`'s spin-up ramp is the same exponential/viscous-style curve ConveyorSim explicitly measured and rejected for bearing behavior (not urgent while every rotor is kinematic). | `RotatingMechanism.gd:78-88` |
| L2 | Shredder | No project-wide numeric-provenance tag convention exists at all — sourcing is expressed ad hoc, so sourced and unsourced constants sit typographically identical in the same function. | systemic (same root as H1) |
| L3 | Sorting line | Bunker's internal placeholder dimensions (wall thickness, roll diameter, door size, mouth height) are acknowledged in docs as unmeasured but a doc's own claim that "each is cited in a code comment" does not hold for these four. | `PlaceableCatalog.gd:7710, 7794, 7779-7781, 7774`; `component_flags_review.md:39-52` |
| L4 | Vehicle fleet | The bale-clamp's real cargo physics (PinJoint3D chains, measured PhysicsMaterial friction) confirms the project can do this correctly — it just was never extended to the wheels every vehicle shares, including the bale clamp's own. | `BaleClamp.gd:176-177, 513-522` vs shared `BaseVehicle` wheel-neutralization |
| L5 | Building/structure | `concrete_v_beam`'s collider is a solid full-footprint box filling the visually-open V-gap between its two legs — an invisible wall inside an opening the player can see through (inverse of the standard's forbidden-shortcut pattern). | `PlaceableCatalog.gd:11387-11398` |
| L6 | Bale yard | Yard bale-gap randomization (1-6cm) cites "(operator spec)" with no file/line — the exact unattributed-parenthetical pattern Q2 exists to catch. | `BaleYardManager.gd:333-340` |
| L7 | Bale yard | `BaleDefs.gd`'s per-origin dirt/moisture/blue/tint numbers carry informal "(operator)" prose, not a real citation, sitting three lines below `BULK_DENSITY`, which IS properly cited. | `BaleDefs.gd:24-53` vs `:15-18` |
| L8 | Colour/paint | `MaterialPalette.gd` is the one disciplined material source (~40% of its 30 functions cite a photo filename) but covers only 33 of hundreds of material-assignment call sites, and even its citations are filename-only with no traceable pixel-derivation step. | `MaterialPalette.gd` (30 functions, 33 call sites in `PlaceableCatalog.gd`) |
| L9 | Crew/NPC proof | `test_gauntlet_operator_context.tscn` survived the 2026-08-17 bench purge with local uncommitted edits from another session; its status (real-MainWorld migration vs half-migrated bench reference) is currently indeterminate and should not be assumed proven either way. | `test_gauntlet_operator_context.gd.bak_deleted20260817`; `test_gauntlet_operator_context.tscn` (modified, other session) |

---

## 3. Scorecard — one line per lens, for tracking over time

1. **Physics-as-the-driver (rotating parts, whole catalog):** 0 of 35+ kinematic "spins" are real RigidBody3D+HingeJoint3D; ~12 more are claimed-rotating in comments but built fully static; 0 of 3 extruder screws modeled at all.
2. **ConveyorSim standard vs CeDo's real belts:** 0% of rollers are RigidBody3D+joint (100% kinematic-spin or fully static); 0 provenance-tag matches repo-wide; 2 real geometry tests exist, 0 touch roller/transport physics.
3. **Extruder family provenance:** 2 of 26 sampled constants carry a genuine citation; 0 of 26 are NAMED-CATALOGUE; 4 sites present fabricated HMI numbers, 3 of 4 unverifiable against ~15 captured photo frames and 1 of 4 physically impossible.
4. **Shredder family provenance:** ~5-6 of 20 constants trace to a real operator/doc source; 0 of 4 rotor shafts are RigidBody3D+joint; rotor rpm has 0% measured causal effect on reported throughput.
5. **Wash line family provenance:** 0 of 8 builders use any tag vocabulary; 1 of 8 (`_m_flotation`) has any citation at all (informal); 0 of 8 rotating parts are RigidBody3D+joint.
6. **Sorting line family provenance:** 8 of 23 constants are OPERATOR-traceable (but 0 of those 8 are cited in-code at their point of definition); 0 of 23 are NAMED-CATALOGUE; 0 of 6 rotating parts are RigidBody3D+joint.
7. **Vehicle fleet physics:** 0 of ~12 vehicle types keep a live wheel joint; 0 wheels rotate for forward travel at any speed; 0 BearingDrag-equivalent models exist; 0 of 4 vehicle test files assert wheel physics.
8. **HMI screen numeric provenance:** 6 of 33 screens (18%) carry a permanent-value-nothing-can-clear defect; 27 of 33 are correctly zeroed; the same defect additionally exists live in 1 in-game runtime scope (`ExtruderBluPortScope.gd`).
9. **Mutation-provable test coverage:** 18 of 19 sampled test files are real, mutation-provable proofs; 1 of 19 is vacuous by design; 7-8 of ~22 placeable categories have zero test-id references anywhere.
10. **Render-and-inspect discipline:** 0 of 10 render tools check pixel content before declaring success; filenames are 100% unique (no overwrite-collapse found); ~8 of 180 catalog machines have ever been rendered for audit.
11. **Water/utility systems:** 0 of 7 water/wash fixtures have any flow simulation (`role='none'`); 0 of 4 water-pump placements have a rotating impeller (vs 1 of 1 on the air side); 10 of 10 sampled BezinkTank+AirNetwork constants are untagged.
12. **Crew/NPC bench-vs-real proof (Rule 3):** 0 of 10 claim-clusters have a passing, harness-gated, real-MainWorld proof; 1 of 10 has a real-world test but it currently FAILs and isn't harness-gated; the other 9 have zero coverage of any kind since the 2026-08-17 bench deletion.
13. **Building/structure geometry provenance:** 0 of 12 sampled constants meet the OPERATOR/CATALOGUE tag bar; 4 of 12 are phantom-cited to documents that don't exist; door/gate hinge-and-carve physics itself is comparatively strong (real pivot, real triangle-vs-OBB wall carve, 2 documented historical bugs it now catches).
14. **Bale-yard subsystem (post C1/C2 fix):** the mass-conservation fix itself has 1 of 1 real behavioral test, wired into CI and passing; the sticker-colour fix landed in 2 of 3 render paths; ~15 untagged constants remain across `BaleDefs.gd`, wire-compliance thresholds, and gap randomization.
15. **Material/paint provenance:** ~16 of ~520 colour decision points (~3%) carry anything citation-shaped; 0% use the standard's 4-tag vocabulary; 1 of 3 shared colour constants (`_SAFETY`) is photo-cited, the other 2 (`_STEEL`, `_DARK`, feeding nearly every builder) are not.
16. **Material-flow simulation layer:** 0 of ~17 named `LineFlow` constants and 0 of ~49 `MachineFlow` rate overrides carry a provenance tag; every Line-3C stage runs at 12.8x its own documented design throughput; the plant's total feed-rate constant is >6x the whole plant's documented intake capacity.

---

## 4. Blocked by Rule 1 — punch list of what to ask the operator for

These cannot be safely fixed by inventing a plausible number — that is the exact failure mode
this whole audit exists to catch. Each needs a real photo, spec sheet, or operator statement
before code should change.

**Dimensions/geometry needing a photo or measurement**
- Door/gate/window nominal sizes — no doc exists at all (C8)
- MS/LS silo + EOP-endpoint real dimensions, now that their cited source docs are confirmed fabricated (C7)
- Shredder internal geometry: chamber, rotor radius, knife count, hopper wall thickness, discharge-conveyor angle (M6)
- Shredder chunk-size spec ("≤10x10cm") — no supporting doc found (M6)
- `riveted_steel_column` / `concrete_v_beam` real dimensions (M28)
- Trilzeef vibration spec (8cm/8Hz) — no such document exists despite being labeled "operator spec" (M12)
- Which machine the disc/ballistic-screen photo in `titech_tomra_1.jpg` actually shows (C6, M14)
- Prewash drum rpm reconciliation (28 vs 14 rpm on the two "same machine" builders) (M10)

**Physics data needing a nameplate/catalogue**
- Roller tube OD/wall-thickness/material for belt rollers, to compute real hollow-tube inertia (H2/M8)
- Shredder rotor/knife mass data, to compute a real inertia tensor (C1/C6 shredder subset)
- Fleet drivetrain constants (engine power, brake torque, ramp rates) — only doc in repo is a cleaning checklist (M23)
- Real RAL code for "RAL-blue" equipment paint; TOMRA's actual brand orange (M32)

**Flow/rate data needing operator sign-off**
- Water/wash circuit real flow rates — `water_circuits.json`'s own 4 source PDFs contain none (C13's root cause)
- `BezinkTank.gd`'s 5 level-control setpoints — no real bezink setpoints documented anywhere (H12)
- Extruder line-specific setpoints for lines 3A/1/3C/6 (only 3B has a `.tres`, and it's a copy of defaults) (M1)
- `TRANSPORT_MPS` real belt speed (M27)
- `mengsilo` real throughput (not in this table above severity-LOW but listed for completeness — MachineFlow.gd:114-117)
- `AirNetwork.gd`/LineFlow compressor sizing — currently justified by circular game-balance logic (M25, H13)
- `FEED_RATE`'s real per-head basis, derived from the plant's 4500 kg/h documented intake (H17)

**Retrofit-only (the number likely already exists in the repo, just needs the tag applied)**
- `BaleDefs.gd` per-origin dirt/moisture/blue/tint values — retag as TYPICAL pending real source (L7)

---

## 5. What NOT to do

Do not attempt to "fix everything on this list" in one pass. This repo is under active
multi-session edit right now — 7+ files (`PlayerController.gd`, `DayNightCycle.gd`,
`InteriorLightingManager.gd`, `BaleBurst.gd`, `ProcessModel.gd`, `test_spawn_clearance.gd`,
`docs/audit/material_trace_2026-08-18.md`) carry local uncommitted changes from another
session as of this audit, and the crew/NPC lens alone found 21 files touched by yet another
in-flight session. A broad, sweeping "clean up the whole catalog" edit is exactly the shape of
change most likely to collide with work that is not visible in a point-in-time read.

This session already produced a concrete near-miss of that exact failure: a stray revert
during cleanup silently discarded live, uncommitted edits to `FeederWorker.gd` and
`BaleClamp.tscn` from another in-progress session, work that had nothing to do with the change
being made. It was caught before it landed, but it is the reason this document ends in a punch
list rather than a diff.

The safe path is the one that already worked earlier this session on the bale-yard
mass-conservation defect (C1/C2 in that session's terms): pick one item from the table above,
make the smallest change that fixes it, prove the fix with a real, mutation-provable test
(not a bench, not a smoke test — something that goes red if the fix is reverted), and commit
it on its own before touching the next item. A few items at a time, each independently
verified and independently committed, is slower than a sweep but is the only version of this
plan that doesn't risk losing someone else's in-flight work the way the FeederWorker/BaleClamp
near-miss almost did.

---

## 6. Recommended next 3 items

Chosen for highest severity, lowest collision risk against the files currently modified by
other sessions, and not blocked by Rule 1 — each is startable today.

1. **C9 — Water Circuit Lijn 3C-6 permanent fake alarm.** Single self-contained `.dc.html`
   file, zero code-side dependency, not touched by any other in-flight session. Recolor the
   alarm div to the shell's bindable-amber convention (`#e6b84a`, matching the sibling Waslijn
   3C Storingen screen that already works) or zero the strip with a provenance comment.

2. **C10 — Render tools have no pixel-content check.** Add one shared luminance/variance
   helper and call it from all 10 `shot_*.gd` files before `save_png()`. These files are
   self-contained test tooling, not touched by any other session's current edits, and this
   closes the Q14 gap in one sitting rather than piecemeal.

3. **C11 — `test_npc05_realworld.gd` not gated, last run FAIL.** Add it to
   `tools/regression/run.sh`'s `for t in ...` loop (it already prints `Result: PASS|FAIL`) and
   correct `BACKLOG_ultracode_2026-07-19.md`'s stale "fixed + re-verified" line so it doesn't
   contradict the file it's citing. Touches only `run.sh` and one doc — neither is on any other
   session's modified-files list — and turns a silently-broken claim into a visibly red one,
   which is the necessary first step before anyone can trust it again.
