extends Node3D
class_name BuildMode
## In-game, Minecraft-style factory builder. You arrange the real CeDo floor;
## the sim provides the objects + placement mechanics.
##
## States:
##   INACTIVE    — normal play.
##   BROWSING    — catalog panel open, mouse free. Click an item → PLACING.
##   PLACING     — translucent ghost follows the crosshair; mouse captured.
##                 [LMB] place   [R] rotate   [RMB] put item away (→ BROWSING)
##                 [X] delete the object under the crosshair   [Tab] open catalog
##   SEQUENTIAL  — guided one-machine-at-a-time line placement (Home key).
##                 [LMB] place & advance   [RMB] skip (furniture only)   [Esc] exit
##
## Toggle build mode with [Tab] (build_mode_toggle).
## Toggle Sequential Line Builder with [Home] — works from any state.
##
## Spawned by MainWorld as a child (needs the world for raycasts and to parent
## placed objects). Placed layout persists to user://factory_layout.json and is
## reloaded on startup, so the factory you build stays built.

enum State { INACTIVE, BROWSING, PLACING, SURFACE, EDIT, SEQUENTIAL }

# ── Jog/Edit mode ─────────────────────────────────────────────────────────────
# Press K (anytime) to enter EDIT: aim the crosshair at a placed machine, [LMB]
# to select it, then jog it for precise alignment:
#   arrows = move X/Z   ·   R/F = up/down   ·   Q/E = rotate   ·   +/- = uniform scale
#   7/4 = X scale   ·   8/5 = Y scale   ·   9/6 = Z scale   ·   Shift = fine
#   Shift = fine step    ·   X = delete      ·   K or RMB = exit
# All continuous (hold the key). Changes persist to factory_layout.json.
const JOG_MOVE_COARSE  : float = 0.6     # m/s while held
const JOG_MOVE_FINE    : float = 0.12
const JOG_ROT_COARSE   : float = 1.2     # rad/s
const JOG_ROT_FINE     : float = 0.3
const JOG_SCALE_COARSE : float = 0.5     # scale units/s
const JOG_SCALE_FINE   : float = 0.12
var _edit_selected  : Node3D = null
var _edit_highlight : MeshInstance3D = null
var _edit_dirty     : bool = false

# #90 — the placed-build layout is now PER-SAVE. `layout_path` is injected by
# MainWorld (user://<save>_factory.json) BEFORE add_child, so a NEW save can never
# inherit a previous run's machines and one save's build never clobbers another's.
# LEGACY_LAYOUT_PATH is the old single global file, read ONCE as a migration source
# for a continued save that has no per-save file yet. Defaults keep tests / direct
# spawns working without injection.
const LEGACY_LAYOUT_PATH := "user://factory_layout.json"
var layout_path : String = "user://factory_layout.json"
var allow_legacy_fallback : bool = true
# Overlay WorldLayout.structure_items (shared site walls/doors/gates) after the
# per-save items. Default on; test benches without a building shell turn it off.
var load_shared_structure : bool = true
const LAYOUT_VERSION := 2   # #29 — bump to force a one-time wipe of pre-patch saved builds
const GRID        := 0.5                  # metres — snap step for placement
const ROT_STEP    := PI / 12.0            # 15° rotation increment per [Q]/[E]
const RAY_LEN     := 80.0                  # placement raycast reach (m)
const HEIGHT_STEP := 0.25                  # metres raised/lowered per [R]/[F]

# Surface-tool type ids, parallel to the popup OptionButton order.
const SURF_TYPES  : Array[String] = ["door", "gate", "window", "sign", "panel"]

# ── Whole-line macro sequences (front → back, in process order) ───────────────
# Transcribed directly from the operator's hand-drawn LIJN 3A / LIJN 3B sheet.
# IMPORTANT: these macros are the WASH + DRY + EXTRUSION train ONLY and START at
# the vuilsnippersilo (wet-film buffer). The shared dry front-end is the common
# intake that feeds BOTH lines — built separately (task #54), NOT here.
# Operator 2026-07-06 (interview, ruling B2): the front-end is a "SNAIL", not a
# straight line — feeder belt → 90° side-feed into shredder-1 funnel → belt 1040
# at 90° → BUNKER top (bunker runs 180° vs the initial feeder) → roll at bunker
# end → next belt at 90° (clockwise from above) → the LONG belt (number
# unconfirmed) at another 90°, parallel to + between the feeder and the bunker →
# SGA → magnet → ballistic → windshifter → TITECH → VSS. Operator explicitly
# requests floor plans for the sorting/washing areas BEFORE any line-layout
# macro encodes this — do not macro-ise the front end from this comment alone.
# Kufferath, MAS bak/drogers and the 3-washer chain are LINE 1 — absent from 3A/3B.
# Name→id: doseerschroef→transport_screw, glijgoot→transfer_chute, pomp→pomp_c1
# (the sheet's "pomp" IS Pomp C1 — water_circuit_3a_la1.md pos 6; generic
# water_pump stays in the catalog for free placement),
# ontwaterschroef→dewater_screw, intrekschroef+schoepen+uitdraairol flotatie→one
# flotation_tank, thermische droger→thermal_dryer, (rondmeng) verdeelwals→verdeelwals,
# ringleiding→ringleiding (verdeelwals/ringleiding/thermal_dryer are new machines).
# Entries are DICTS so a line can branch: {"x": ±m} lays a machine on a side lane
# (does NOT advance the main cursor), {"z": m} offsets it forward along that lane,
# and {"main_advance": m} pushes the main cursor past a recombine. 3A carries the
# mengsilo→ring-main→cyclone drying RECIRC loop (branch); 3B carries the L-R split
# → left+right mech_dryer → recombine at the ventilator. frictiewasser (3A only) is
# the friction_washer id (now a stirring tank, not a separator).
const LINE_3A_SEQ : Array[Dictionary] = [
	# #136 — VSS is the FIRST machine in the wash line, not the intake macro.
	# The switch belt (intake macro) feeds material into here; the wash chain
	# then continues into vuilsnippersilo → transport_screw → ... → extruder.
	{"id": "vss_silo"},
	{"id": "vuilsnippersilo"},
	{"id": "transport_screw"},
	{"id": "friction_washer"},          # frictiewasser — stirring tank, 3A only
	{"id": "transfer_chute"},
	# #81 — pump moved OFF the centreline. It's a utility unit (water loop,
	# not material flow; role="none" in MachineFlow) so placing it in the main
	# chain just pushed every downstream machine further along Z for no reason.
	# Now sits on the -X side lane next to the friction_sep it feeds water to.
	# 2026-07-06: this slot IS Pomp C1 (LA1doc positions 5-6-7: glijgoot →
	# Pomp C1 → frictiescheider M3; water_circuit_3a_la1.md). In-place id swap
	# keeps seq.size() and every macro_index stable, so operator-saved deltas
	# in user://macros/line_3a.json stay valid. Mirror: LineDragger.LINE_3A_SEQ.
	{"id": "pomp_c1", "x": -3.5, "z": 0.0},
	{"id": "friction_sep"},
	{"id": "flotation_tank"},
	{"id": "dewater_screw"},
	{"id": "friction_sep"},
	{"id": "transport_screw"},
	{"id": "mech_dryer", "gap": 1.2},   # wet→dry section break: wider access gap
	# ── RULING 2.1-B, operator 2026-08-28 (SUPERSEDES the same morning's
	# "Diagram is right" ruling — that answer was based on a misread of the
	# question; this is the operator's own account of the machines he ran):
	#   INFEED: "material coming in from the mechanical dryer. Then there is
	#   a blower ... then the material goes to the wind shifter. Then there
	#   is another blower that blows it in the top of the silo in one
	#   cyclone, big cyclone on top."
	#   LOOP:   one screw "goes to the ring and then back up. to dry the
	#   material ... warm it, blow it constantly ... only if the line is
	#   running." On 3A the diagram's "thermische droger" IS this heated
	#   ring circuit — the real thermal-dryer MACHINE is line 3B's (works
	#   differently); 3A's block is "kind of dead" as a separate machine.
	#   MAIN:   the other screw "goes to the extruder silo. That is just
	#   dosing screw, blower, pipeline pipeline pipeline, extruder silo."
	# So vs the diagram: windzifter moves to the INFEED, the ringleiding
	# lives in the LOOP, and no thermal dryer/verdeelwals exists on the 3A
	# main path. The diagram remains the transcription authority for BLOCK
	# NAMES; the operator is the authority for the wiring.
	{"id": "blower"},                   # infeed blower 1 (V4)
	{"id": "wind_sifter"},              # windzifter — operator: on the INFEED
	{"id": "blower"},                   # infeed blower 2 → big top cyclone
	# The BIG SHARED CYCLONE on the mengsilo TOP: both blower lines (from the
	# windzifter and from the ring) enter it at ~180° opposite inlets, and it
	# drops into the silo. gap −2.3 pulls the silo's centre under the cyclone
	# (cyc_half 0.8 + gap + silo_half 1.5 = 0); y 5.9 seats the cone on the
	# 6.5 m silo's dome. Model detail (twin opposed inlets) → detail program.
	{"id": "cyclone", "y": 5.9, "gap": -2.3},
	{"id": "mengsilo"},
	# ── RONDMENG-LUS (branch, +X side) — the ALWAYS-ON (while running)
	# heated drying circulation. Material: silo → doseerschroef M11a₂ →
	# verdeelwals m14 (rotary feeder into the airstream; heaters + V1 blower
	# are the air side, modelled later per the 60×60×200 heater-cabinet spec)
	# → the RING → back into the shared top cyclone → silo. The ring itself:
	# starts at the bottom, 180° turn, up, 180°, other side, 180° — two
	# serpentine loops, then up to the cyclone (operator; detail program).
	# #71 — branch_recirc: the LAST branch entry (the ring) carries the
	# recirc back-edge to the mengsilo; physically that return passes through
	# the shared top cyclone.
	{"id": "transport_screw", "x": 5.0, "z": -3.0, "branch_recirc": true},  # Doseerschroef M11a (onder mengsilo)
	{"id": "verdeelwals",     "x": 5.0, "z":  0.0},                          # Verdeelwals (m14)
	{"id": "blower",          "x": 5.0, "z":  3.0},                          # Ventilator V1 rondmengen
	{"id": "ringleiding",     "x": 5.0, "z":  6.0},                          # de RING (serpentine)
	# ── MAIN PATH out of the mengsilo — operator: "just dosing screw,
	# blower, pipeline pipeline pipeline, extruder silo." ──
	{"id": "transport_screw"},          # Doseerschroef M11b
	{"id": "blower"},
	# #107 — was plain `silo`; the extruder's hot end has to be fed by the
	# elevated extruder_silo (frame + 2 cyclones on top + lump bin + windows),
	# not a generic dosing silo. Same change applied to 3B and Line 1 below.
	{"id": "extruder_silo", "gap": 1.5},  # extruder needs maintenance clearance at both ends
	# ── DOC-WALK GAP FIX 2026-08-28 (gap 1.3) ───────────────────────────────
	# Every line's flow diagram runs extruder_silo → COMPACTOR BAND → compactor
	# → extruder (line_flow_graphs.json edges 32/33/34, identical for 1, 3A and
	# 3B). The band was missing from all three; only line_3c ever placed one,
	# even though `compactorband`'s own builder describes it running "Silo up
	# into the compactor's top funnel" — i.e. exactly this edge.
	# Corroborated beyond the diagrams by the operator checklist FORM-018
	# (swi/FORM-018__064_CeDo120.md:52): "Compactor banden en compactor hoed
	# compleet reinigen" — plural belts, under a section covering "beide
	# compactors", so these are real, separately-maintained machines.
	# The COMPACTOR itself is deliberately NOT added here: _m_extruder_unit
	# builds the EREMA cutter-compactor INTEGRATED on the extruder's -X flank
	# (PlaceableCatalog.gd, "SECTION 1: FEED / CUTTER-COMPACTOR (PCU)"), so a
	# standalone `compactor` placeable would double it. The diagram draws them
	# as separate process BLOCKS, which is not a claim about separate machines.
	# Carries the 1.5 m gap so the extruder keeps its maintenance clearance —
	# that clearance belongs next to the extruder, not next to the silo.
	{"id": "compactorband", "gap": 1.5},
	{"id": "extruder_3a"},
	# #98 — Lump cart parking spot next to the extruder's screen-changer
	# discharge. Operator's responsibility to make sure a lump_cart is parked
	# here BEFORE the extruder starts. Spot is at +X offset, partway along the
	# extruder's length so the laser_filter outlet is above the cart.
	# #225 — the LIVE laserfilter is a standalone machine beside the extruder
	# (ExtruderMachine binds _closest_in_group("laser_filter"); the macros never
	# placed one, so the 318-bar trip / wissel / lump sim were dead in macro
	# worlds). #225.3 — the filter sits 3.5 m out to the side (matches NpcTaskBench
	# FILTER_SIDE_X) with a lump_platform bordes under it, and a cart under EACH of
	# the twin afvoerschroef nozzles (LaserFilter.gd eject_achter_local /
	# eject_voor_local at filter-local ±1.30). Macro coords: ACHTER/bordes cart at
	# 3.5-1.30 = 2.20, VOOR/ground cart at 3.5+1.30 = 4.80 — under the yaw this
	# macro gives the filter, its +X (achter) mouth lands over 2.20 and its -X
	# (voor) mouth over 4.80 (measured 2026-08-03, all four lines; the old comment
	# called 4.80 the "+X AISLE" cart — labels were crossed, geometry always
	# right). 3.5 out keeps the 2.20 cart clear of the extruder edge (±1.30) so
	# nothing overlaps the barrel (the old 2.6 filter put that nozzle onto the
	# extruder).
	{"id": "laser_filter",   "x": 3.5, "z": -5.0},
	# Bordes on the ACHTER side only (macro-x 2.20 — where the filter's +X achter
	# mouth lands) — the achter afvoerschroef discharges HIGHER so its cart sits on
	# the raised platform (y = deck top 0.12); the VOOR cart (macro-x 4.80) sits on
	# the GROUND because the voor discharge is lower. Operator 2026-07-15 (see
	# docs/plant/extruder_line_layout.md).
	{"id": "lump_platform",  "x": 2.2, "z": -5.0},
	{"id": "lump_cart_spot", "x": 2.2, "z": -5.0, "y": 0.12},
	{"id": "lump_cart",      "x": 2.2, "z": -5.0, "y": 0.12},
	{"id": "lump_cart_spot", "x": 4.8, "z": -5.0},
	{"id": "lump_cart",      "x": 4.8, "z": -5.0},
	# #223 docs->code: swi/TRAIN-de-flow-master-diagram__116_CeDo7.md +
	# swi/TRAIN-verdere-verloop-granulaat-silos__125_CeDo40.md — every extruder
	# line runs extruder → heetafslag → ontwaterzeef → centrifuge → weegschaal →
	# voorraad_silo. Back-end chain continues on the centreline past the extruder
	# (lump carts above are branches — they don't advance the main cursor).
	# +14.3 m over 5 main entries at the default 0.5 m gap; stays inside footprint.
	{"id": "heetafslag"},
	{"id": "ontwaterzeef"},
	{"id": "centrifuge"},
	{"id": "weegschaal"},
	# ── DOC-WALK GAP FIX 2026-08-28 (gap 2.2) — lijn_3a_flow.md edge 36:
	# Weegschaal → bigbag station. RULED 3A-ONLY (question_answers.json — 3B's
	# diagram has no bigbag block, so 3B/1/3C get none). Branch on the -X
	# aisle beside the weegschaal (the +X side is the laser-filter lane); the
	# #71 chained-branch logic gives it the weegschaal→bigbag explicit edge,
	# and as a MachineFlow SINK the bag banks granulate (a full bag leaves by
	# forklift, not by line flow). Inserted BEFORE voorraad_silo, shifting
	# only that one index — user://macros still empty (re-checked), so no
	# saved delta breaks.
	{"id": "bigbag_station", "x": -3.0, "z": 0.0},
	{"id": "voorraad_silo"},
]
# #54 — shared dry FRONT-END for Lines 3A and 3B. Lays the Shredder-2 climb,
# the 12 numbered intake belts in series, the switch-belt diverter, and the VSS
# silo + U-bay overflow buffer. After this runs, the user places `line_3a` and
# `line_3b` so their vuilsnippersilo heads sit next to the VSS/U-bay discharge —
# LineFlow's geometry linker will then auto-connect intake → vuilsnippersilo →
# wash trains. Numbers belts 1..12 in their natural placement order (each tilts
# its own deck via _transportband_spec — no extra geometry needed in the macro).
## #136 — operator-spec second pass.
##
## Three structural changes from the original (#54) layout:
##   1. C8.5 is the OVERFLOW belt. It branches off C8 on the -X side, sits
##      slightly LOWER, and points away from the main chain. C8 normally feeds
##      C9 (forward); when both VSS_3A + VSS_3B report FULL, C8 ramps the other
##      way and discharges DOWN onto 8.5, which feeds the U-bay (stortvak).
##      The C8 reversal + ramp logic is task #138; the LAYOUT here just puts
##      the geometry in the right place so LineFlow can wire the edges.
##   2. switch_belt IS conveyor 12 — the duplicate transportband_12 entry is
##      gone. The switch belt jogs along its own conveying axis to feed either
##      VSS_3A, VSS_3B, or both (task #137).
##   3. VSS is REMOVED from this macro. It belongs to the wash macro as its
##      FIRST machine (line_3a / line_3b spawn vss_silo at index 0).
# Sorteerlijn 3A/3B (Full Optical Sorting & Shredding Front-End)
# Complete plant sequence as specified by operator:
#   1. Opzetband 3A/3B (feed intake)
#   2. Shredder 1 (coarse pre-shredder)
#   3. Transport belt (out from under Shredder 1)
#   4. Bunker (large buffer/metering conveyor)
#   5. Transport belt (out of bunker)
#   6. Transport belt (intermediate transfer)
#   7. Split belt (diverter between Titan & Tomra banks)
#   8. Overband magnets (ferrous removal over infeed belts)
#   9. Incline belts (climb to optical sorter decks)
#  10. Titan 1 & Titan 2 (TITECH NIR sorters)
#  11. Tomra 1 & Tomra 2 (TOMRA Autosort NIR sorters)
#  12. Waste/reject collection belts
#  13. Accepted LDPE film collection belts -> long transfer conveyor
#  14. Shredder 2 (fine shredder)
#  15. Inclined belt 8m (climb out of Shredder 2)
# Hand-off at tail goes into Transportband 1 (start of Transportbanden 3A/3B C1-C12).
const LINE_SORT_SEQ : Array[Dictionary] = [
	{"id": "opzetband_3a3b"},                                      # 0: Infeed conveyor
	{"id": "shredder_1"},                                          # 1: Coarse shredder (red)
	{"id": "transport_belt"},                                      # 2: Outfeed belt under Shredder 1
	{"id": "bunker"},                                              # 3: Buffer metering conveyor
	{"id": "transport_belt"},                                      # 4: Outfeed belt from bunker
	{"id": "transport_belt"},                                      # 5: Transfer conveyor
	{"id": "switch_belt"},                                         # 6: Split conveyor (Titan vs Tomra)
	{"id": "overband_magnet", "x": -2.5, "z": 0.0},                # 7: Magnet (Titan side)
	{"id": "overband_magnet", "x":  2.5, "z": 0.0},                # 8: Magnet (Tomra side)
	{"id": "inclined_belt_8m", "x": -2.5, "z": 2.0},               # 9: Incline infeed (Titan)
	{"id": "inclined_belt_8m", "x":  2.5, "z": 2.0},               # 10: Incline infeed (Tomra)
	{"id": "titech_sort",      "x": -3.5, "z": 6.0},               # 11: Titan 1 (TITECH NIR)
	{"id": "titech_sort",      "x": -3.5, "z": 10.0},              # 12: Titan 2 (TITECH NIR)
	{"id": "tomra_sort",       "x":  3.5, "z": 6.0},               # 13: Tomra 1 (TOMRA Autosort)
	{"id": "tomra_sort",       "x":  3.5, "z": 10.0},              # 14: Tomra 2 (TOMRA Autosort)
	{"id": "transport_belt",   "x": -6.0, "z": 8.0, "furniture": true},  # 15: Waste reject belt (Titan)
	{"id": "transport_belt",   "x":  6.0, "z": 8.0, "furniture": true},  # 16: Waste reject belt (Tomra)
	{"id": "transport_belt",   "x":  0.0, "z": 12.0},              # 17: LDPE accept collection conveyor
	{"id": "transport_belt",   "x":  0.0, "z": 18.0},              # 18: Long transfer conveyor to Shredder 2
	{"id": "shredder_2"},                                          # 19: Fine shredder (blue)
	{"id": "inclined_belt_8m"},                                    # 20: Climb conveyor to Transportband 1
]


## D4 — Lines 3C + 6 share a front-end (opzetband_3c6 → shredder → climb belt →
## trilzeef → wash chain). Previously placeable existed in the catalog but no
## macro chained it, so the operator couldn't build the 3C/6 intake from the
## "Lines" group. This is the shared 3C/6 front end; downstream wash diverges
## per line (use LINE_3A/3B-style macros for that, with the wider flotation_tank_wide).
const LINE_3C6_SEQ : Array[Dictionary] = [
	{"id": "opzetband_3c6"},
	{"id": "shredder_1"},                # 3C/6 = the big-RED coarse shredder (operator 2026-07-14; was shredder_2, blue). Same id as Line 1.
	{"id": "inclined_belt_8m"},
	{"id": "trilzeef"},
]

## LINE 3C — the wash/dry/extrude spine, TRANSCRIBED one-for-one from
## Line3CDef.STAGES (src/sim/Line3CDef.gd:53-90, itself transcribed from the plant
## HMI "Techical overview"). Nothing placed this line before: BuildMode dispatched
## six sequences and none of them was Line 3C, so the whole calibrated 3C model
## (ProcessModel coefficients, the HMI currents, the MechDryerCycle pair
## controller, the Line3CDef.LINKS split/merge graph) had no node to run on.
##
## HARD INVARIANT: entry i's id MUST equal Line3CDef.STAGES[i]["id"], and the
## macro_index stamped at placement (:1627-1628) is what Line3CDef
## .code_for_macro_entry turns into the stage's l3c_code. That alignment is
## asserted by src/tests/test_line3c_seq_alignment.gd — an insert or a reorder
## here re-addresses the whole line and MUST go through that test.
## APPEND-ONLY, like every other SEQ (see the standing warning at :100-101).
##
## NO branch_recirc / parallel_branch flags, deliberately: LineFlow skips its
## Line3CDef.LINKS pass for any node carrying an lf_explicit_outs meta
## (LineFlow.gd:1026 runs BEFORE the code branch at :1029-1039), so tagging the
## L/R pairs here would REPLACE the authored split/merge graph with geometry
## guesses. GRAPH_TOPOLOGY_MACROS below suppresses that tagging for this macro.
##
## LAYOUT-APPROXIMATE. Line3CDef supplies order, codes, ids, currents and
## topology — it does NOT supply metres. The x/z offsets are the existing 3B
## side-lane idiom, not an operator measurement; the geometry needs a K-mode jog
## + macro save-back pass before any document calls this the real 3C layout.
const LINE_3C_SEQ : Array[Dictionary] = [
	{"id": "doseersilo"},                                          # 0  L3C.1
	{"id": "sink_float"},                                          # 1  L3C.3
	{"id": "friction_sep",    "x": -3.0, "z": 2.0},                # 2  L3C.4L
	{"id": "friction_sep",    "x":  3.0, "z": 2.0},                # 3  L3C.4R
	{"id": "transport_screw", "x": -3.0, "z": 7.0},                # 4  L3C.5L
	{"id": "transport_screw", "x":  3.0, "z": 7.0,
	 "main_advance": 11.0},                                        # 5  L3C.5R
	{"id": "mill"},                                                # 6  L3C.6  (merge)
	{"id": "friction_sep",    "x": -3.0, "z": 2.0},                # 7  L3C.9L
	{"id": "friction_sep",    "x":  3.0, "z": 2.0},                # 8  L3C.9R
	{"id": "transport_screw", "x": -3.0, "z": 7.0},                # 9  L3C.10L
	{"id": "transport_screw", "x":  3.0, "z": 7.0,
	 "main_advance": 11.0},                                        # 10 L3C.10R
	{"id": "flotation_tank_wide"},                                 # 11 L3C.11 (merge)
	{"id": "transport_screw"},                                     # 12 L3C.12
	{"id": "friction_sep"},                                        # 13 L3C.13
	{"id": "mech_dryer",      "x": -3.0, "z": 3.0},                # 14 L3C.14L
	{"id": "mech_dryer",      "x":  3.0, "z": 3.0,
	 "main_advance": 8.0},                                         # 15 L3C.14R
	{"id": "blower"},                                              # 16 L3C.15 (merge)
	{"id": "plasmaq"},                                             # 17 L3C.16
	{"id": "silo"},                                                # 18 L3C.18
	{"id": "blower"},                                              # 19 L3C.19
	# ── extruder back-end (Line3CDef.gd:77-89, RECONSTRUCTED codes) ──────────
	{"id": "compactorband"},                                       # 20 Cband
	{"id": "compactor"},                                           # 21 PCU
	{"id": "extruder_screw",  "gap": 1.5},                         # 22 Extr
	{"id": "laser_filter"},                                        # 23 Laser
	{"id": "vacuum_degas"},                                        # 24 Degas
	{"id": "melt_pump"},                                           # 25 Melt
	{"id": "kopfilter"},                                           # 26 Kop
	{"id": "heetafslag"},                                          # 27 Heet
	{"id": "ontwaterzeef"},                                        # 28 Ontw
	{"id": "centrifuge"},                                          # 29 Centr
	{"id": "weegschaal"},                                          # 30 Weeg
	{"id": "voorraad_silo"},                                       # 31 Voorraad
	# ── laserfilter afvoer furniture (operator ruling 2026-08-03) ─────────────
	# TWO lump carts per extruder — one VOOR, one ACHTER of the laser filter
	# (docs/plant/extruder_line_layout.md; re-confirmed by the operator
	# 2026-08-03 after 3C shipped with NONE). APPENDED past the Line3CDef.STAGES
	# spine end, honouring the append-only rule (:100-101): every machine keeps
	# its macro_index → l3c_code address, and code_for_macro_entry returns ""
	# for these indices (bounds-safe — test_line3c_seq_alignment checks it).
	# "at_entry": 23 anchors each piece to the laser filter's own z-centre, so
	# there is no hand-baked distance to rot when a machine upstream resizes
	# (stale-constant disease). Geometry mirrors the 3A/3B/1 idiom relative to
	# the filter (here on the centreline at x=0): ACHTER cart on the 0.12 m
	# bordes at macro -1.30, VOOR cart on the GROUND at macro +1.30. Under the
	# macro yaw the filter's +X (eject_achter_local) mouth lands over -1.30 and
	# its -X (eject_voor_local) mouth over +1.30 (measured 2026-08-03).
	{"id": "lump_platform",  "x": -1.3, "z": 0.0, "at_entry": 23,
	 "furniture": true},                                           # 32 bordes
	{"id": "lump_cart_spot", "x": -1.3, "z": 0.0, "y": 0.12, "at_entry": 23,
	 "furniture": true},                                           # 33 achter spot
	{"id": "lump_cart",      "x": -1.3, "z": 0.0, "y": 0.12, "at_entry": 23,
	 "furniture": true},                                           # 34 achter cart
	{"id": "lump_cart_spot", "x":  1.3, "z": 0.0, "at_entry": 23,
	 "furniture": true},                                           # 35 voor spot
	{"id": "lump_cart",      "x":  1.3, "z": 0.0, "at_entry": 23,
	 "furniture": true},                                           # 36 voor cart
]

## Macros whose flow topology comes from an AUTHORED graph rather than from the
## branch/parallel bookkeeping in _build_full_line. For these, no node is stamped
## with lf_explicit_outs, because LineFlow treats that meta as "downstream fully
## specified" and skips its Line3CDef.LINKS pass entirely (LineFlow.gd:1026).
const GRAPH_TOPOLOGY_MACROS : Array[String] = ["line_3c"]

# Transportbanden 3A/3B (operator-correct term — was called "intake"). This is
# STEP 2 in the plant 3A/3B work-flow:
#   step 1: Sort line (LINE_SORT_SEQ — sorteerlijn)
#   step 2: Transportbanden 3A/3B (this macro — the dry conveyor network that
#           lifts trilzeef output through belts C1..C12 + switch belt to VSS)
#   step 3a: Wash + extrude path A (LINE_3A_SEQ)
#   step 3b: Wash + extrude path B (LINE_3B_SEQ)
# Const name kept as INTAKE_3A3B_SEQ + id `line_intake_3a3b` for save-file
# compat — only the operator-facing labels say "Transportbanden 3A/3B" now.
const INTAKE_3A3B_SEQ : Array[Dictionary] = [
	# D4 — opzetband_3a3b at the head feeds the shredder. Was missing; macro
	# previously assumed bales arrived at the shredder by hand.
	{"id": "opzetband_3a3b"},
	{"id": "shredder_2"},
	{"id": "inclined_belt_8m"},      # the climb out of shredder-2's discharge
	{"id": "transportband_1"},
	{"id": "transportband_2"},
	{"id": "transportband_3"},
	{"id": "transportband_4"},
	{"id": "transportband_5"},
	{"id": "transportband_6"},
	{"id": "transportband_7"},
	{"id": "transportband_8"},
	# ── BRANCH (overflow path): C8.5 → U-bay on the -X side lane. The branch
	#    is NOT a parallel sibling — it's the C8-reverse discharge target. C8
	#    sends material here only when both VSSs are FULL (task #138).
	{"id": "transportband_8_5", "x": -3.5, "z": -1.5},
	{"id": "u_bay",           "x": -8.0, "z": -2.0},
	# ── Main forward chain continues. ──
	{"id": "transportband_9"},
	{"id": "transportband_10"},
	{"id": "transportband_11"},
	{"id": "switch_belt"},           # = conveyor 12; jogs ±1.5m to feed VSS_3A / VSS_3B
]
const LINE_3B_SEQ : Array[Dictionary] = [
	# #136 — VSS is the FIRST machine in the wash line (not the intake macro).
	{"id": "vss_silo"},
	{"id": "vuilsnippersilo"},
	{"id": "transport_screw"},
	{"id": "rafter"},
	{"id": "dewater_screw"},
	{"id": "friction_sep"},
	{"id": "flotation_tank"},
	# Kleine LA — open waterbak at the 3B flotation-tank material-EXIT side
	# (checklist row 16 "Nét overlopen kleine LA I" — water_small.md §1). Side
	# lane like 3A's pomp_c1 (#81): role="none" water fixture, no flow edge
	# (placement-only thanks to the I1 guard in _build_full_line).
	# x/z are PLACEHOLDERS — "towards Hal 0" is a world-frame fact the macro
	# local frame cannot express; flag for operator (water_small.md F1/F2).
	# NOTE: this insertion shifts macro_index for entries 7+ — any operator-saved
	# user://macros/line_3b.json chain must be re-saved (verified absent 2026-07-06).
	{"id": "kleine_la", "x": -3.0, "z": -0.5},
	{"id": "dewater_screw"},
	{"id": "friction_sep"},        # frictiescheider L-R — throws material both ways
	# ── L-R SPLIT: a mechanical dryer on each side, then recombine at the ventilator ──
	# #71 — `parallel_branch` flags both dryers as sibling parallel branches.
	# _build_full_line tags friction_sep with TWO explicit downstream edges (one
	# to each dryer) and both dryers with an explicit edge to the next main entry
	# (the recombine blower). Geometry-fallback would only pick the nearest dryer
	# without these tags, so only ONE side would carry material.
	{"id": "mech_dryer", "x": -1.75, "z": 2.0, "parallel_branch": true},
	{"id": "mech_dryer", "x":  1.75, "z": 2.0, "parallel_branch": true, "main_advance": 4.75},
	# ── DOC-WALK GAP FIX 2026-08-28 (gap 3.1) — lijn_3b_flow.md edges 12-19.
	# The doc's dry section is: Ventilator (recombine) → Verdeelwals →
	# THERMISCHE DROGER (+ Heater, hot air) → ventilator → Ringventilator →
	# extruder silo. The sim instead ran cyclone → PLASMAQ → cyclone → blower
	# → cyclone: no verdeelwals, no thermal dryer, and a plasmaq that every
	# document places on LINE 3C only (L3C.16, HMI-photo-verified,
	# Line3CDef.gd:74) — no 3B source for it exists. The operator independently
	# confirmed the same day (ruling 2.1-B): "the thermal dryer is for line
	# 3B, actually" — the REAL machine, unlike 3A where the heated ring does
	# the job. The two unnamed fan blocks keep generic `blower` placeables;
	# the doc's own open question 6 asks the operator for their V-numbers.
	{"id": "blower"},              # "Ventilator" — recombine (edges 12-14)
	{"id": "verdeelwals"},         # Verdeelwals (edge 15)
	{"id": "thermal_dryer"},       # Thermische droger — 3B's REAL machine (edge 15; heater cabinet pending)
	{"id": "blower"},              # "ventilator" (edge 17)
	{"id": "blower"},              # Ringventilator (edges 18-19, pneumatic into the silo)
	{"id": "extruder_silo"},
	# Gap 1.3 — see the matching note in LINE_3A_SEQ. Flow diagram edge 32:
	# extruder_silo → compactor_band. The PCU stays integrated in the extruder.
	{"id": "compactorband"},
	{"id": "extruder_3b"},
	# #98 — Lump cart parking spot at the extruder's filter discharge.
	# #225 — the LIVE laserfilter is a standalone machine beside the extruder
	# (ExtruderMachine binds _closest_in_group("laser_filter"); the macros never
	# placed one, so the 318-bar trip / wissel / lump sim were dead in macro
	# worlds). #225.3 — the filter sits 3.5 m out to the side (matches NpcTaskBench
	# FILTER_SIDE_X) with a lump_platform bordes under it, and a cart under EACH of
	# the twin afvoerschroef nozzles (LaserFilter.gd eject_achter_local /
	# eject_voor_local at filter-local ±1.30). Macro coords: ACHTER/bordes cart at
	# 3.5-1.30 = 2.20, VOOR/ground cart at 3.5+1.30 = 4.80 — under the yaw this
	# macro gives the filter, its +X (achter) mouth lands over 2.20 and its -X
	# (voor) mouth over 4.80 (measured 2026-08-03, all four lines; the old comment
	# called 4.80 the "+X AISLE" cart — labels were crossed, geometry always
	# right). 3.5 out keeps the 2.20 cart clear of the extruder edge (±1.30) so
	# nothing overlaps the barrel (the old 2.6 filter put that nozzle onto the
	# extruder).
	{"id": "laser_filter",   "x": 3.5, "z": -5.0},
	# Bordes on the ACHTER side only (macro-x 2.20 — where the filter's +X achter
	# mouth lands) — the achter afvoerschroef discharges HIGHER so its cart sits on
	# the raised platform (y = deck top 0.12); the VOOR cart (macro-x 4.80) sits on
	# the GROUND because the voor discharge is lower. Operator 2026-07-15 (see
	# docs/plant/extruder_line_layout.md).
	{"id": "lump_platform",  "x": 2.2, "z": -5.0},
	{"id": "lump_cart_spot", "x": 2.2, "z": -5.0, "y": 0.12},
	{"id": "lump_cart",      "x": 2.2, "z": -5.0, "y": 0.12},
	{"id": "lump_cart_spot", "x": 4.8, "z": -5.0},
	{"id": "lump_cart",      "x": 4.8, "z": -5.0},
	# #223 docs->code: swi/TRAIN-de-flow-master-diagram__116_CeDo7.md +
	# swi/TRAIN-verdere-verloop-granulaat-silos__125_CeDo40.md — extruder →
	# heetafslag → ontwaterzeef → centrifuge → weegschaal → voorraad_silo.
	# Main-centreline chain past the extruder (+14.3 m at default 0.5 m gap).
	{"id": "heetafslag"},
	{"id": "ontwaterzeef"},
	{"id": "centrifuge"},
	{"id": "weegschaal"},
	{"id": "voorraad_silo"},
]
# Line 1 = its own intake (opzetband 1 → metal detector → westa band → shredder →
# magnet → VW trommel → band 2 → SGA-trommel → Y-splitgoot) then wash/dry/extrude; transcribed from the
# operator's LIJN 1 sheet; 2x machines laid as side-by-side pairs (jog with K to finalize).
const LINE_1_SEQ : Array[Dictionary] = [
	# #196 — operator rework. Old head (metaaldetector + 45° westa_band) gone:
	# metal-detector head is now built INTO opzetband_1 at 3/4 along; the 45°
	# westa_band_1 moves to the END of the wash-feed group so it dumps into the
	# TOP of the pre-wash drum. New flow:
	#   opzetband_1 (intake + magnet head 3/4 along)
	#   → shredder_1 (no chute between shredder and uitvoerband, sits directly
	#                 above the horizontal collector belt)
	#   → transport_belt (= uitvoerband: horizontal, runs under shredder)
	#   → overband_magnet (near end of uitvoerband — captures ferrous)
	#   → transport_belt (short 1 m horizontal, 30 cm down + 90° L turn — handled
	#                     visually by the K-menu jog after placement)
	#   → westa_band_1 (45° incline up to the top of the pre-wash drum)
	#   → vw_trommel    (the real voorwastrommel, top-fed)
	# ── #fold 2026-08-28 — line 1 SNAKES (operator layout sketch; transcribed
	# in docs/plant/line1_layout_sketch_2026-08-28.md — original image not yet
	# archived, see the warning there). ───────────────────────────────────────
	# Plan-view legs (headings relative to the macro's placement rot):
	#   leg A            opzetband_1 → shredder_1        (intake ramp)
	#   leg B  LEFT +90°  uitvoerband + magnet           (short east run)
	#   leg C  LEFT +90°  short belt → westa → hoekgoot  (climb to drum head)
	#   leg D  RIGHT −90°  drum → Y-goot → wet train     (the long drum axis)
	#   leg E  RIGHT −90°  flotation tank + dewater      (sketch: tank offset
	#                                                     south of the train)
	#   leg F  LEFT +90°  friction → … → extruder tail   (east — CONFIRMED by
	#          the operator 2026-08-28 ("leg F is correct"); matches the floor
	#          plan's east-west extruder-1 block on Hal 2's south wall.)
	{"id": "opzetband_1"},
	{"id": "shredder_1"},
	{"id": "transport_belt", "turn_deg": 90.0},        # uitvoerband — leg B (east)
	{"id": "overband_magnet"},
	{"id": "transport_belt", "turn_deg": 90.0,
	 "main_advance": 1.0},                             # short belt — leg C (north)
	# westa gap 2.14 — DERIVED: the belt's lip sits run+flat = 5.12 m past its
	# origin; the chute's IN port is 0.828 m upstream of the chute centre, so
	# centre-to-centre = 5.12 + 0.828 = 5.94 = westa_half 2.9 + gap + chute_half
	# 0.9 → gap = 2.14. Guarded by test S4b (lip-over-IN measured in-world).
	{"id": "westa_band_1", "gap": 2.14},               # 45° climb to the hoekgoot
	# ── DOC-WALK FIX 2026-08-28 — operator-directed, closes audit finding C5 ──
	# Was `prewash_drum`: an 18-line unsourced stub (a trough, a plain cylinder,
	# a spray pipe). The REAL voorwastrommel geometry — ~150 lines, built from
	# operator photos and signed off by the operator (bolted flange drive ring,
	# axial-thrust bracket, rubber cradle tyres, yellow peeling safety cage,
	# "TANK A-4 / MAX CAP 50,000 L" placard, drain tray) — sat unused under the
	# sibling id `vw_trommel`. Same orphaned-model disease as gap 1.1's sga_drum.
	# See DETAIL_STANDARD_audit_2026-08-18.md finding C5 and photo_audit.md:68.
	# IN-PLACE ID SWAP — seq.size() and every macro_index are unchanged.
	# NOTE the wash physics had to move WITH the model: `vw_trommel` carried no
	# MachineFlow profile at all, so swapping the id alone would have dropped
	# water_add 0.30 / contam_remove 0.40 and turned the pre-wash into an inert
	# conveyor. MachineFlow.gd now matches both ids in the same two arms.
	# SIZE CHANGE: 6.0x6.5x11.25 → 3.6x4.5x8.0, so line 1 gets shorter (helps
	# the overrun). The westa_band_1 discharge was re-aimed the same day: its
	# incline_run is now DERIVED from vw_trommel_funnel_mouth_local() and the
	# lip-over-funnel relationship is measured in the built world by
	# test_line1_flow_conformance S4 (was 3.05 m high / 1.59 m past the mouth).
	# ── OPERATOR RULING 2026-08-28 (layout sketch): ONE drum, not two. ────────
	# "Same machine — one drum does both": the voorwastrommel IS the HPS (SGA)
	# zware-delen scheider. The flow diagram's separate "HPS (SGA)" block is
	# the SAME physical drum this entry places — which also explains why the
	# diagram never draws a voorwas-trommel block of its own (only "Band 2
	# (naar voorwas trommel)" naming it in passing).
	# Earlier the same day, walking the diagram literally, gap-fix 1.1 had
	# inserted band 2 + sga_feed_chute + sga_drum here as a separate stage;
	# the sketch ruling REVERSED that (ledger: DOCS_VS_SIM_GAP_AUDIT, ruling
	# 1.B). The drum therefore carries BOTH behaviours in MachineFlow.gd
	# (wash + heavy-parts screening, its own dedicated arm), and the
	# Y-splitgoot follows it directly.
	# The C5 model-swap note above still applies unchanged.
	# ── #fold — the hoekgoot + the leg-C→D corner. All numbers DERIVED from
	# sga_feed_chute_ports_local(1.8³) + vw_trommel_funnel_mouth_local():
	#   y 3.48   = funnel mouth 4.155 + 0.30 drop − chute OUT height 0.973
	#   gap −1.15 = the corner pivot must sit at the OUT port's along-leg
	#              coordinate (0.245 m upstream of the chute centre), so the
	#              cursor is pulled BACK: 0.9 half-depth + gap = −0.245.
	#   turn_advance 0.49 = OUT hangs 0.750 m to the flow's right; the funnel
	#              sits trommel_half 4.0 − inset 3.74 = 0.26 m down leg D, so
	#              leg D pre-advances 0.75 − 0.26 = 0.49 to line them up.
	# extend_legs — the chute rides 3.48 m up; its own legs stretch to the
	# floor via _finalize_placed → extend_machine_legs (#70).
	# Guarded by test S4 (chute OUT over funnel) + S4b (westa lip over IN).
	{"id": "sga_feed_chute", "y": 3.48, "gap": -1.15, "extend_legs": true},
	{"id": "vw_trommel", "turn_deg": -90.0,
	 "turn_advance": 0.49},                            # leg D (east) — the drum axis
	{"id": "scheidingsgoot"},                          # Y-splitgoot, drum → friction L/R
	# #196 — parallel L/R friction split. parallel_branch tells the macro
	# builder these two siblings BOTH receive from the upstream scheidingsgoot
	# (the "glijgoot" slide-chute connector). Without it, only the first sibling
	# was wired up and the right-side friction ran dry on reload.
	{"id": "friction_sep", "x": -2.5, "z": 1.0, "parallel_branch": true},
	{"id": "friction_sep", "x":  2.5, "z": 1.0, "parallel_branch": true, "main_advance": 5.0},
	{"id": "mech_dryer",  "x": -2.5, "z": 1.0},
	{"id": "mech_dryer",  "x":  2.5, "z": 1.0, "main_advance": 5.0},
	{"id": "blower",      "x": -2.0, "z": 0.5},
	{"id": "blower",      "x":  2.0, "z": 0.5, "main_advance": 2.5},
	{"id": "cyclone",     "x": -2.0, "z": 0.5},
	{"id": "cyclone",     "x":  2.0, "z": 0.5, "main_advance": 3.0},
	# ── DOC-WALK GAP FIX 2026-08-28 (gap 1.2) — lijn_1_flow.md edges 12-19 ──
	# The diagram's post-mill chain is
	#   maalmolen_1 → ventilator_10a/b → intrekschroef_11a/b → flotatie_tank
	# and it has NO screw between the frictiescheiders and the mill
	# (ventilator_8a/b feed the mill directly). This macro had the pair in the
	# wrong stage: two transport_screw entries BEFORE the mill and none after,
	# so the post-mill cyclones dumped straight into the flotation tank.
	# Operator confirmed 2026-08-28: "after the mill, like the doc says".
	# MOVED, not added — the pre-mill pair is deleted and re-placed below, so
	# the line's total length is unchanged and the flotation tank and the whole
	# extruder back-end stay exactly where they were. Only the mill and the
	# post-mill blower/cyclone pairs shift 5 m upstream, into the space the
	# misplaced screws used to occupy.
	{"id": "mill"},
	{"id": "blower",      "x": -2.0, "z": 0.5},
	{"id": "blower",      "x":  2.0, "z": 0.5, "main_advance": 2.5},
	{"id": "cyclone",     "x": -2.0, "z": 0.5},
	{"id": "cyclone",     "x":  2.0, "z": 0.5, "main_advance": 3.0},
	{"id": "transport_screw", "x": -2.0, "z": 0.5},                # intrekschroef 11a
	{"id": "transport_screw", "x":  2.0, "z": 0.5, "main_advance": 5.0},  # intrekschroef 11b
	# #fold — leg E (RIGHT −90): the sketch offsets the flotation tank SOUTH
	# of the wet train's east run.
	{"id": "flotation_tank", "turn_deg": -90.0},
	{"id": "dewater_screw"},
	# #fold — leg F (LEFT +90): the long tail heads east again. ASSUMED (see
	# the leg map at the top of this SEQ) — sketch ends at the flotation tank;
	# east matches the floor plan's east-west extruder-1 block in Hal 2.
	{"id": "friction_sep", "turn_deg": 90.0},
	{"id": "kufferath_sieve", "x": -2.5, "z": 1.0},
	{"id": "kufferath_sieve", "x":  2.5, "z": 1.0, "main_advance": 4.5},
	{"id": "mas_bak",     "x": -2.5, "z": 1.0},
	{"id": "mas_bak",     "x":  2.5, "z": 1.0, "main_advance": 4.0},
	{"id": "mas_droger",  "x": -2.5, "z": 1.0},
	{"id": "mas_droger",  "x":  2.5, "z": 1.0, "main_advance": 5.0},
	{"id": "blower",      "x": -2.0, "z": 0.5},
	{"id": "blower",      "x":  2.0, "z": 0.5, "main_advance": 2.5},
	{"id": "cyclone"},
	{"id": "extruder_silo"},
	# Gap 1.3 — see the matching note in LINE_3A_SEQ. Flow diagram edge 32:
	# extruder_silo → compactor_band. The PCU stays integrated in the extruder.
	{"id": "compactorband"},
	{"id": "extruder_1"},
	# #98 — Lump cart parking spot at the extruder's filter discharge. Same
	# +X / partway-back offset as 3A/3B so the laser_filter outlet sits above
	# the cart (was missing — Line 1's LaserFilter had no cart under it and
	# fell back to the nearest cart anywhere in the hall). APPEND-only: existing
	# macro_index values are unchanged, so saved line_1.json deltas stay valid.
	# #225 — the LIVE laserfilter is a standalone machine beside the extruder
	# (ExtruderMachine binds _closest_in_group("laser_filter"); the macros never
	# placed one, so the 318-bar trip / wissel / lump sim were dead in macro
	# worlds). #225.3 — the filter sits 3.5 m out to the side (matches NpcTaskBench
	# FILTER_SIDE_X) with a lump_platform bordes under it, and a cart under EACH of
	# the twin afvoerschroef nozzles (LaserFilter.gd eject_achter_local /
	# eject_voor_local at filter-local ±1.30). Macro coords: ACHTER/bordes cart at
	# 3.5-1.30 = 2.20, VOOR/ground cart at 3.5+1.30 = 4.80 — under the yaw this
	# macro gives the filter, its +X (achter) mouth lands over 2.20 and its -X
	# (voor) mouth over 4.80 (measured 2026-08-03, all four lines; the old comment
	# called 4.80 the "+X AISLE" cart — labels were crossed, geometry always
	# right). 3.5 out keeps the 2.20 cart clear of the extruder edge (±1.30) so
	# nothing overlaps the barrel (the old 2.6 filter put that nozzle onto the
	# extruder).
	{"id": "laser_filter",   "x": 3.5, "z": -5.0},
	# Bordes on the ACHTER side only (macro-x 2.20 — where the filter's +X achter
	# mouth lands) — the achter afvoerschroef discharges HIGHER so its cart sits on
	# the raised platform (y = deck top 0.12); the VOOR cart (macro-x 4.80) sits on
	# the GROUND because the voor discharge is lower. Operator 2026-07-15 (see
	# docs/plant/extruder_line_layout.md).
	{"id": "lump_platform",  "x": 2.2, "z": -5.0},
	{"id": "lump_cart_spot", "x": 2.2, "z": -5.0, "y": 0.12},
	{"id": "lump_cart",      "x": 2.2, "z": -5.0, "y": 0.12},
	{"id": "lump_cart_spot", "x": 4.8, "z": -5.0},
	{"id": "lump_cart",      "x": 4.8, "z": -5.0},
	# #223 docs->code: swi/TRAIN-de-flow-master-diagram__116_CeDo7.md +
	# swi/TRAIN-verdere-verloop-granulaat-silos__125_CeDo40.md — extruder →
	# heetafslag → ontwaterzeef → centrifuge → weegschaal → voorraad_silo.
	# Main-centreline chain past the extruder (+14.3 m at default 0.5 m gap).
	# APPEND-only after the lump carts, so existing macro_index values are unchanged.
	{"id": "heetafslag"},
	{"id": "ontwaterzeef"},
	{"id": "centrifuge"},
	{"id": "weegschaal"},
	{"id": "voorraad_silo"},
]
const LINE_GAP_M : float = 0.5   # clear space between consecutive machines (process lines are tight)

# Injected by MainWorld so placement rays can ignore the player capsule.
var player_body : CharacterBody3D = null
# Injected by MainWorld — carves doorway/window holes in the building shell.
var wall_openings : WallOpenings = null
# Injected by MainWorld — re-links the material line when machines change.
var line_flow : LineFlow = null

var _state        : int    = State.INACTIVE
var _active_id    : String = ""
var _ghost_rot_y  : float  = 0.0
var _ghost_height : float  = 0.0          # how far above the ground hit to place
var _grid_snap    : bool   = true         # [G] toggles free vs grid-snapped placement
var _placed_root : Node3D
var _ghost       : Node3D

# Two-point placement state (variable_belt etc.) — captured on first LMB; second
# LMB builds the span between (_two_point_start) and the current ghost position.
var _two_point_start : Vector3 = Vector3.ZERO
var _has_two_point   : bool = false
var _two_point_preview : MeshInstance3D = null

# Smart-snap state for support poles. When the crosshair is aimed at a placed
# belt's deck, _pole_snap_height holds the world-Y the pole should reach (so its
# top kisses the deck) and _pole_snap_xz the floor-plane position to plant it at.
var _pole_snap_height : float = 0.0          # 0 = no snap active; use default height
var _pole_snap_xz     : Vector3 = Vector3.ZERO   # world position to plant the base

# ── Machine-to-machine edge snap ──────────────────────────────────────────────
# When the ghost's nearest face center is within SNAP_MAX_DIST_M of an already-
# placed machine's nearest face center, the ghost JUMPS to the alignment
# position so its edge butts up against the placed machine's edge. A green
# vertical marker shows where the join lands; LMB places at that snap.
const SNAP_MAX_DIST_M : float = 2.0
var _snap_marker : Node3D = null
var _snap_active : bool   = false
const POLE_DEFAULT_H : float = 2.0           # matches the catalog size.y for poles
const FLOOR_Y : float = 0.0

# 4-point surface capture
var _surf_points  : Array[Vector3] = []
var _surf_markers : Node3D
var _opening_seq  : int = 0

# UI (built programmatically — no .tscn needed)
var _ui          : CanvasLayer
var _catalog     : PanelContainer
var _status      : Label
# Bottom-right readout shown ONLY in edit (K) mode: live W×H×D in metres for
# the selected machine plus the applied per-axis scale factor. Lets the user
# eyeball how an in-game tweak compares to the catalog's base size while jogging.
var _dim_readout : Label
var _crosshair   : ColorRect
var _popup       : PanelContainer
var _popup_type  : OptionButton
var _popup_name  : LineEdit

# ── Sequential Line Builder ──────────────────────────────────────────────────
# Activated with [Home]. Hands the operator one machine at a time from a chosen
# line sequence; each LMB places it and auto-loads the next machine. All
# machines land as free-standing placed_objects (no macro_id/macro_index metas)
# so they are individually joggable with K-mode and picked up by LineFlow
# geometry linking. No macro save-back is used — precise manual placement IS
# the save-back for this workflow.
var _seq_line_id   : String = ""      # which macro we're walking
var _seq_line_name : String = ""      # human label shown in the status bar
var _seq           : Array  = []      # the SEQ array for the chosen line
var _seq_index     : int    = 0       # current position in _seq
var _seq_picker    : PanelContainer = null   # the line-picker panel

# =============================================================================
## Whether placing/removing/jogging this placeable should rebuild LineFlow.
## HMI panels, signs, lights, doors, decorations are observer/control fixtures
## that don't change the material-flow graph and must NOT trigger a rebuild
## (every rebuild forces a downstream-first staggered PLC restart over ~20 s
## and wipes powered/spin/buffer state — that's #218).
func _is_flow_relevant(id : String) -> bool:
	if id.is_empty():
		return false
	if id.begins_with("hmi_"):
		return false
	# Hard-coded observer-only ids that don't carry a sim role.
	# (`hmi_wall` / `hmi_panel` used to head this list; they are retired
	#  placeables now — PlaceableCatalog.RETIRED_IDS — and the `hmi_` prefix
	#  check above already covers every HMI that can still be placed.)
	const _OBSERVER_IDS : Array[String] = [
		"pcu_cabinet", "e_kast", "door",
		"door_personnel", "gate_roller", "window_frame",
		"hazard_moving", "hazard_overhead", "hazard_hightemp",
		"hazard_hardhat", "hazard_piralchute", "hazard_platformmaxload",
		"fire_riser", "fire_extinguisher", "drainage_grating",
		"riveted_steel_column", "concrete_v_beam", "overhead_crane",
	]
	if id in _OBSERVER_IDS:
		return false
	# Authoritative check: MachineFlow.profile(id).role != 'none' means
	# the id participates in the material-flow graph. If profile() is
	# absent or returns null, default to flow-relevant (rebuild on safety).
	var machine_flow := load("res://src/sim/MachineFlow.gd")
	if machine_flow == null or not machine_flow.has_method("profile"):
		return true
	var pr : Dictionary = machine_flow.profile(id)
	if pr == null or pr.is_empty():
		return true
	var role : String = String(pr.get("role", ""))
	return role != "none"

# =============================================================================
func _ready() -> void:
	_placed_root = Node3D.new()
	_placed_root.name = "PlacedObjects"
	add_child(_placed_root)
	_build_ui()
	load_layout()

# =============================================================================
# UI
# =============================================================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 40
	add_child(_ui)

	# Status line, top-centre
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.offset_top = 14.0
	_status.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.visible = false
	_ui.add_child(_status)

	# Bottom-right dimension + scale readout (edit mode only).
	_dim_readout = Label.new()
	_dim_readout.add_theme_font_size_override("font_size", 14)
	_dim_readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_dim_readout.anchor_left = 1.0
	_dim_readout.anchor_right = 1.0
	_dim_readout.anchor_top = 1.0
	_dim_readout.anchor_bottom = 1.0
	_dim_readout.offset_left = -360.0
	_dim_readout.offset_right = -16.0
	_dim_readout.offset_top = -80.0
	_dim_readout.offset_bottom = -16.0
	_dim_readout.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_dim_readout.add_theme_color_override("font_outline_color", Color.BLACK)
	_dim_readout.add_theme_constant_override("outline_size", 5)
	_dim_readout.visible = false
	_ui.add_child(_dim_readout)

	# Centre crosshair (only while placing)
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.85)
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.offset_left = -3.0
	_crosshair.offset_top = -3.0
	_crosshair.offset_right = 3.0
	_crosshair.offset_bottom = 3.0
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.visible = false
	_ui.add_child(_crosshair)

	# Catalog panel, left side
	_catalog = PanelContainer.new()
	_catalog.anchor_left = 0.0
	_catalog.anchor_top = 0.0
	_catalog.anchor_bottom = 1.0
	_catalog.offset_left = 16.0
	_catalog.offset_right = 290.0     # explicit width — avoids zero-width rect
	_catalog.offset_top = 50.0
	_catalog.offset_bottom = -50.0
	_catalog.visible = false
	_ui.add_child(_catalog)

	var scroll := ScrollContainer.new()
	_catalog.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(250, 0)
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "BUILD CATALOG"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Special tool: the 4-point surface / opening placer.
	var surf_btn := Button.new()
	surf_btn.text = "▣  Surface / opening (4-point)"
	surf_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	surf_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	surf_btn.pressed.connect(_start_surface)
	vbox.add_child(surf_btn)

	var surf_help := Label.new()
	surf_help.text = "  door · window · sign · wall panel"
	surf_help.add_theme_font_size_override("font_size", 11)
	surf_help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	vbox.add_child(surf_help)

	# #MSB — Macro Save-Back panel: after placing a line macro and jogging
	# machines in EDIT mode (K), the operator can save the new layout back
	# so future placements emit it. Reset wipes the override file and
	# restores the const seed.
	_build_macro_saveback_panel(vbox)

	for cat in PlaceableCatalog.categories():
		var header := Label.new()
		header.text = "— %s —" % cat
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
		vbox.add_child(header)
		for it in PlaceableCatalog.items():
			if it["category"] != cat:
				continue
			var btn := Button.new()
			btn.text = String(it["name"])
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_select_item.bind(String(it["id"])))
			vbox.add_child(btn)

	_build_popup()

# The "what did you place?" dialog shown after the 4th surface point.
func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.anchor_left = 0.5
	_popup.anchor_top = 0.5
	_popup.offset_left = -200.0
	_popup.offset_right = 200.0
	_popup.offset_top = -120.0
	_popup.offset_bottom = 120.0
	_popup.visible = false
	_ui.add_child(_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_popup.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var head := Label.new()
	head.text = "What did you place?"
	head.add_theme_font_size_override("font_size", 18)
	vb.add_child(head)

	_popup_type = OptionButton.new()
	_popup_type.add_item("Door  (opens with E, cuts opening)")       # 0
	_popup_type.add_item("Gate  (roller, 3-button UP/STOP/DOWN station)") # 1 — Gate.gd + GateButton.gd, NOT door E-prompt
	_popup_type.add_item("Window  (glass, cuts opening)")            # 2
	_popup_type.add_item("Sign / poster  (flat on wall)")            # 3
	_popup_type.add_item("Plain panel / wall  (solid)")              # 4
	vb.add_child(_popup_type)

	var name_lbl := Label.new()
	name_lbl.text = "Name / description:"
	name_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(name_lbl)

	_popup_name = LineEdit.new()
	_popup_name.placeholder_text = "e.g. 3×3 roller door"
	vb.add_child(_popup_name)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_confirm_surface)
	row.add_child(create_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_cancel_surface)
	row.add_child(cancel_btn)

# #MSB — build a Save-as-spec / Reset-to-default pair of buttons per macro.
# Place once into the catalog; presses route into save_macro_overrides() /
# reset_macro_overrides(). Tracks the user://macros/<macro>.json status so the
# operator can capture the in-world layout as the new spec or roll back to the
# const seed in BuildMode.gd.
func _build_macro_saveback_panel(parent: VBoxContainer) -> void:
	var sep := Label.new()
	sep.text = "— MACRO SAVE-BACK —"
	sep.add_theme_font_size_override("font_size", 13)
	sep.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	parent.add_child(sep)

	var hint := Label.new()
	hint.text = "  Place a line, jog with [K], then Save."
	hint.add_theme_font_size_override("font_size", 11)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	parent.add_child(hint)

	var hint2 := Label.new()
	hint2.text = "  EDIT mode: Shift+S saves selected macro."
	hint2.add_theme_font_size_override("font_size", 11)
	hint2.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	parent.add_child(hint2)

	for mid in LineMacroStore.MACRO_IDS:
		var hrow := HBoxContainer.new()
		hrow.add_theme_constant_override("separation", 6)
		parent.add_child(hrow)
		var lbl := Label.new()
		lbl.text = "  %s" % mid
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lbl.add_theme_font_size_override("font_size", 12)
		hrow.add_child(lbl)
		var save_btn := Button.new()
		save_btn.text = "Save"
		save_btn.tooltip_text = "Save current in-world placement of %s back to user://macros/%s.json" % [mid, mid]
		save_btn.pressed.connect(save_macro_overrides.bind(mid))
		hrow.add_child(save_btn)
		var reset_btn := Button.new()
		reset_btn.text = "Reset"
		reset_btn.tooltip_text = "Reset to default macro — delete user://macros/%s.json" % mid
		reset_btn.pressed.connect(reset_macro_overrides.bind(mid))
		hrow.add_child(reset_btn)

# =============================================================================
# STATE TRANSITIONS
# =============================================================================
func _on_toggle() -> void:
	# Tab is a clean ON/OFF: from any ACTIVE state it fully exits build mode and
	# hands control back (cursor re-captured, walking restored). To go back to the
	# catalog while placing, use [RMB]/build_cancel (PLACING → BROWSING). This avoids
	# the old two-press trap where Tab left you in BROWSING with the cursor up and
	# movement frozen.
	match _state:
		State.INACTIVE: _enter_browsing()
		State.EDIT:     _exit_edit_mode()
		_:              _enter_inactive()

func _enter_inactive() -> void:
	_state = State.INACTIVE
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = false
	_status.visible = false
	_crosshair.visible = false
	if _dim_readout != null:
		_dim_readout.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _enter_browsing() -> void:
	_state = State.BROWSING
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = true
	_status.visible = true
	_crosshair.visible = true   # aim the crosshair at any placed object to delete it
	_status.text = "BUILD MODE   ·   pick an item from the catalog   ·   [K] jog/move placed machines   ·   aim + [X] delete   ·   [Tab] exit build mode"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _enter_placing(id: String) -> void:
	_state = State.PLACING
	_active_id = id
	_ghost_height = 0.0
	# Two-point placement reset: a fresh placeable starts at "click point A".
	_has_two_point = false
	_two_point_start = Vector3.ZERO
	_clear_two_point_preview()
	_catalog.visible = false
	_status.visible = true
	_crosshair.visible = true
	_spawn_ghost(id)
	_update_placing_status()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _update_placing_status() -> void:
	var nm := String(PlaceableCatalog.get_item(_active_id).get("name", _active_id))
	var grid_txt := "ON" if _grid_snap else "OFF (free)"
	if PlaceableCatalog.is_two_point(_active_id):
		# Two-step prompt that swaps after the first click is captured.
		var phase : String = ("② click END point + [R]/[F] end height" if _has_two_point
			else "① click START point + [R]/[F] start height")
		_status.text = "Placing: %s   ·   %s   ·   height %.2fm   [G] grid: %s   [RMB] cancel   [Tab] catalog" \
			% [nm, phase, _ghost_height, grid_txt]
		return
	if PlaceableCatalog.is_pole(_active_id):
		var snap_hint : String = ("SNAP %.2fm" % _pole_snap_height) if _pole_snap_height > 0.0 else "free"
		_status.text = "Placing: %s   ·   aim at a belt to snap, else place freely   ·   %s   ·   [G] grid: %s   [RMB] back   [Tab] catalog" \
			% [nm, snap_hint, grid_txt]
		return
	_status.text = "Placing: %s   ·   [LMB] place   [Q]/[E] rotate   [R]/[F] height %.2fm   [G] grid: %s   [RMB] away   [X] delete   [Tab] catalog" \
		% [nm, _ghost_height, grid_txt]

func _select_item(id: String) -> void:
	_enter_placing(id)

func _start_surface() -> void:
	_enter_surface()

func _enter_surface() -> void:
	_state = State.SURFACE
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = false
	_status.visible = true
	_crosshair.visible = true
	_status.text = "SURFACE  ·  aim & [LMB] the 4 corners:  ① bottom-left  ② top-left  ③ top-right  ④ bottom-right   ·   [RMB] cancel"
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# =============================================================================
# SEQUENTIAL LINE BUILDER
# =============================================================================

## Open the Home-key line-picker panel. If Build Mode is INACTIVE we enter it
## first so the ghost system is live. The picker lists all 7 line macros; each
## button calls _start_sequential with the chosen id.
func _open_sequential_picker() -> void:
	# Auto-enter build mode if needed so the ghost / catalog infrastructure is ready.
	if _state == State.INACTIVE:
		_enter_browsing()
	# Tear down any existing picker (re-open re-creates it fresh).
	if _seq_picker != null and is_instance_valid(_seq_picker):
		_seq_picker.queue_free()
		_seq_picker = null
	# Build the panel.
	_seq_picker = PanelContainer.new()
	_seq_picker.anchor_left   = 0.0
	_seq_picker.anchor_top    = 0.0
	_seq_picker.anchor_right  = 0.0
	_seq_picker.anchor_bottom = 0.0
	_seq_picker.offset_left   = 20.0
	_seq_picker.offset_top    = 60.0
	_seq_picker.offset_right  = 320.0
	_seq_picker.offset_bottom = 420.0
	_ui.add_child(_seq_picker)
	var vbox := VBoxContainer.new()
	_seq_picker.add_child(vbox)
	var title := Label.new()
	title.text = "🔧 LIJN PLAATSER — kies een lijn"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 14)
	vbox.add_child(title)
	vbox.add_child(HSeparator.new())
	# Line entries: [id, display_name, machine_count_hint]
	const LINES : Array = [
		["line_intake_3c6",   "3C/6 Voedingsband",       "4 machines"],
		["line_3c",           "Lijn 3C (wassen/extruderen)", "37 machines"],
		["line_intake_3a3b",  "3A/3B Voedingsband (C1–C12)", "16 machines"],
		["line_sort",         "Sorteerlijn 3A/3B (Shredder/Bunker/NIR)", "21 machines"],
		["line_3a",           "Lijn 3A (wassen/extruderen)", "~35 machines"],
		["line_3b",           "Lijn 3B (wassen/extruderen)", "~25 machines"],
		["line_1",            "Lijn 1 (wassen/extruderen)", "~42 machines"],
	]
	for entry in LINES:
		var row := HBoxContainer.new()
		vbox.add_child(row)
		var btn := Button.new()
		btn.text = entry[1]
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.tooltip_text = entry[2]
		btn.pressed.connect(_start_sequential.bind(entry[0], entry[1]))
		row.add_child(btn)
	vbox.add_child(HSeparator.new())
	var cancel_btn := Button.new()
	cancel_btn.text = "Annuleer  [Home]"
	cancel_btn.pressed.connect(func():
		if _seq_picker != null and is_instance_valid(_seq_picker):
			_seq_picker.queue_free()
			_seq_picker = null
		if _state == State.BROWSING:
			_enter_inactive()
	)
	vbox.add_child(cancel_btn)
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

## Begin sequential placement for a given line id. Closes the picker, loads the
## correct SEQ array, and enters PLACING on the first machine.
func _start_sequential(line_id: String, display_name: String) -> void:
	# Close the picker.
	if _seq_picker != null and is_instance_valid(_seq_picker):
		_seq_picker.queue_free()
		_seq_picker = null
	# Resolve the SEQ.
	var seq := _seq_for_line(line_id)
	if seq.is_empty():
		push_warning("[BuildMode] Sequential: unknown line_id '%s'" % line_id)
		_enter_inactive()
		return
	_seq_line_id   = line_id
	_seq_line_name = display_name
	_seq           = seq
	_seq_index     = 0
	_state         = State.SEQUENTIAL
	_load_seq_step()

## Load the machine at _seq_index into the ghost placement system and update the
## status bar with the sequential-mode prompt.
func _load_seq_step() -> void:
	if _seq_index >= _seq.size():
		_exit_sequential("✅ Lijn klaar! (%s)" % _seq_line_name)
		return
	var entry : Dictionary = _seq[_seq_index]
	var machine_id : String = String(entry.get("id", ""))
	if machine_id.is_empty():
		# Skip empty/malformed entries.
		_seq_index += 1
		_load_seq_step()
		return
	# Reuse the existing PLACING ghost infrastructure — just set state back to
	# SEQUENTIAL after _enter_placing switches it to PLACING.
	_enter_placing(machine_id)
	_state = State.SEQUENTIAL   # restore SEQUENTIAL after _enter_placing overwrote it
	# Override the status bar with the sequential-mode prompt.
	var nm : String = String(PlaceableCatalog.get_item(machine_id).get("name", machine_id))
	var total : int = _seq.size()
	var skip_hint : String = "   [→/RMB] skip" if entry.get("furniture", false) else ""
	_status.text = "🔧 LIJN %s  [%d/%d]  %s   ·   [LMB] plaatsen   [Q/E] draaien   [R/F] hoogte   [K] jog%s   [Home/Esc] stoppen" \
		% [_seq_line_name, _seq_index + 1, total, nm, skip_hint]

## Exit sequential mode. Placed machines stay. Transitions to BROWSING so the
## operator can immediately press K to jog the freshly placed machines.
func _exit_sequential(banner: String) -> void:
	_clear_ghost()
	_seq_line_id   = ""
	_seq_line_name = ""
	_seq           = []
	_seq_index     = 0
	# Tear down picker if it's somehow still open.
	if _seq_picker != null and is_instance_valid(_seq_picker):
		_seq_picker.queue_free()
		_seq_picker = null
	_enter_browsing()   # land in BROWSING so K-jog is immediately available
	if not banner.is_empty():
		_status.text = banner + "   ·   BUILD MODE   ·   [K] jog machines   ·   [Tab] exit build"

## Returns the SEQ array for a line_id, or an empty array if unknown.
## Mirrors the dispatch table in _build_full_line so they stay in sync.
func _seq_for_line(line_id: String) -> Array:
	match line_id:
		"line_3a":           return LINE_3A_SEQ
		"line_3b":           return LINE_3B_SEQ
		"line_1":            return LINE_1_SEQ
		"line_intake_3a3b":  return INTAKE_3A3B_SEQ
		"line_sort":         return LINE_SORT_SEQ
		"line_intake_3c6":   return LINE_3C6_SEQ
		"line_3c":           return LINE_3C_SEQ
		_:                   return []

# =============================================================================
# INPUT  (handled in _input so [Tab] beats UI focus navigation)
# =============================================================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode_toggle"):
		_on_toggle()
		get_viewport().set_input_as_handled()
		return

	# [Home] — Sequential Line Builder toggle. Works from any state:
	# • INACTIVE / BROWSING → open the line-picker panel
	# • SEQUENTIAL          → exit sequential mode (placed machines stay)
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_HOME:
		if _state == State.SEQUENTIAL:
			_exit_sequential("")
		else:
			_open_sequential_picker()
		get_viewport().set_input_as_handled()
		return

	# [Esc] exits sequential mode cleanly (Godot's ui_cancel action).
	if _state == State.SEQUENTIAL and event.is_action_pressed("ui_cancel"):
		_exit_sequential("")
		get_viewport().set_input_as_handled()
		return

	# [→] skips a furniture entry while in sequential mode.
	if _state == State.SEQUENTIAL and event is InputEventKey and event.pressed \
			and not event.echo \
			and (event as InputEventKey).keycode == KEY_RIGHT:
		if _seq_index < _seq.size() and _seq[_seq_index].get("furniture", false):
			_seq_index += 1
			if _seq_index >= _seq.size():
				_exit_sequential("✅ Lijn klaar!")
			else:
				_load_seq_step()
		get_viewport().set_input_as_handled()
		return

	# K toggles the jog/edit mode from anywhere.
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_K:
		if _state == State.EDIT: _exit_edit_mode()
		else: _enter_edit_mode()
		get_viewport().set_input_as_handled()
		return

	if _state == State.EDIT:
		# Discrete edit actions; continuous jog is polled in _process.
		# #MSB — Shift+S saves the SELECTED machine's macro back to disk.
		# (Plain K already toggles edit mode; SHIFT+K would collide with the
		# "fine jog" Shift modifier polled in _edit_process, so we pick S.)
		if event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_S \
				and (event as InputEventKey).shift_pressed:
			_save_macro_for_selected()
			get_viewport().set_input_as_handled()
			return
		# In-sim 3D-model editor: B bakes the SELECTED machine's current scale
		# into the catalog as its new base size. The override is persisted to
		# user://placeable_size_overrides.json so every future placement of
		# this id — in this world AND in any new world — comes out at the
		# baked size. The live instance is reset to scale 1 and its Model
		# subtree rebuilt at the new size, so saves of the current scene
		# don't double-scale on reload.
		if event is InputEventKey and event.pressed and not event.echo \
				and (event as InputEventKey).keycode == KEY_B \
				and _edit_selected != null:
			_bake_selected_size_to_catalog()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("build_place"):
			_edit_select_pointed()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_cancel"):
			if _edit_selected != null: _edit_deselect()
			else: _exit_edit_mode()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_delete"):
			_edit_delete_selected()
			get_viewport().set_input_as_handled()
		return

	if _state == State.SURFACE:
		# While the name popup is open, let clicks reach its buttons.
		if event.is_action_pressed("build_place") and not _popup.visible:
			_add_surface_point()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_cancel"):
			_cancel_surface()
			get_viewport().set_input_as_handled()
		return

	# Delete works in BROWSING too (aim the crosshair at any placed object + [X]),
	# so you don't have to pick a dummy item just to remove something.
	if _state == State.BROWSING and event.is_action_pressed("build_delete"):
		_delete_pointed()
		get_viewport().set_input_as_handled()
		return

	if _state != State.PLACING and _state != State.SEQUENTIAL:
		return

	if event.is_action_pressed("build_place"):
		_place_current()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_cancel"):
		# RMB: first press just cancels an in-progress two-point capture (keep the
		# operator on the same placeable so they can re-pick the start); a second
		# RMB falls through to leaving placing mode altogether.
		# In SEQUENTIAL mode, RMB skips furniture entries; for non-furniture machines
		# it just cancels a two-point capture if one is active, or does nothing
		# (operator must use Home/Esc to fully exit sequential mode).
		if _state == State.SEQUENTIAL:
			if _has_two_point:
				_has_two_point = false
				_two_point_start = Vector3.ZERO
				_clear_two_point_preview()
				_update_placing_status()
			elif _seq_index < _seq.size() and _seq[_seq_index].get("furniture", false):
				# Furniture entry — RMB skips it.
				_seq_index += 1
				if _seq_index >= _seq.size():
					_exit_sequential("✅ Lijn klaar!")
				else:
					_load_seq_step()
			# Non-furniture in sequential mode: RMB is a no-op (force Esc/Home to exit).
			get_viewport().set_input_as_handled()
			return
		if _has_two_point:
			_has_two_point = false
			_two_point_start = Vector3.ZERO
			_clear_two_point_preview()
			_update_placing_status()
		else:
			_enter_browsing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate_cw"):
		_ghost_rot_y = wrapf(_ghost_rot_y + ROT_STEP, 0.0, TAU)
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate_ccw"):
		_ghost_rot_y = wrapf(_ghost_rot_y - ROT_STEP, 0.0, TAU)
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_raise"):
		_ghost_height += HEIGHT_STEP
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_lower"):
		_ghost_height = maxf(0.0, _ghost_height - HEIGHT_STEP)
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_grid_toggle"):
		_grid_snap = not _grid_snap
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_delete"):
		_delete_pointed()
		get_viewport().set_input_as_handled()

# =============================================================================
# GHOST + PLACEMENT
# =============================================================================
func _process(delta: float) -> void:
	if _state == State.EDIT:
		_edit_process(delta)
		return
	if (_state != State.PLACING and _state != State.SEQUENTIAL) or _ghost == null:
		return
	var hit := _raycast()
	if hit.is_empty():
		_ghost.visible = false
		return
	_ghost.visible = true
	var p: Vector3 = hit["position"]
	if _grid_snap:
		p.x = roundf(p.x / GRID) * GRID
		p.z = roundf(p.z / GRID) * GRID
	# Smart snap for poles: when aiming at a placed belt deck, the pole's base
	# stays on the floor and the ghost stretches up to kiss the deck at the hit
	# point. Outside a belt, the pole behaves like any other placeable.
	_pole_snap_height = 0.0
	if PlaceableCatalog.is_pole(_active_id):
		var snap := _try_pole_snap(hit)
		if not snap.is_empty():
			_pole_snap_xz = Vector3(snap["x"], FLOOR_Y, snap["z"])
			_pole_snap_height = float(snap["h"])
			_ghost.global_position = _pole_snap_xz
			_ghost.rotation.y = _ghost_rot_y
			# Stretch the ghost's local Y so its top reaches the hit point.
			_ghost.scale = Vector3(1.0, _pole_snap_height / POLE_DEFAULT_H, 1.0)
			if _has_two_point and _two_point_preview != null:
				_update_two_point_preview(p)
			return
		_ghost.scale = Vector3.ONE   # no snap → restore default
	p.y += _ghost_height
	_ghost.global_position = p
	_ghost.rotation.y = _ghost_rot_y
	# Machine-to-machine edge snap. Skipped for poles (own snap path), line
	# macros, and two-point placeables (they snap by other means).
	_snap_active = false
	if (not _active_id.begins_with("line_")
			and not PlaceableCatalog.is_pole(_active_id)
			and not PlaceableCatalog.is_two_point(_active_id)):
		var snap_info := _find_machine_snap(_ghost.global_position)
		if not snap_info.is_empty():
			var sp : Vector3 = snap_info["snap_pos"]
			sp.y = _ghost.global_position.y
			_ghost.global_position = sp
			_snap_active = true
			if _snap_marker == null:
				_snap_marker = _build_snap_marker()
				add_child(_snap_marker)
			_snap_marker.visible = true
			var mp : Vector3 = snap_info["midpoint"]
			_snap_marker.global_position = Vector3(mp.x, FLOOR_Y, mp.z)
	if not _snap_active and _snap_marker != null:
		_snap_marker.visible = false
	# Preview floor-reaching legs live: a raised machine's ghost shows its legs
	# stretched to the ground (and hidden where they'd punch through a machine),
	# matching what actually gets placed. No-op for ghosts without tagged legs. (#69)
	PlaceableCatalog.extend_machine_legs(_ghost, _ghost_height)
	# While picking the END point of a two-point placement, redraw the preview
	# line from the captured start to the current cursor each frame.
	if _has_two_point and _two_point_preview != null:
		_update_two_point_preview(p)

# ── Standing placed-vehicle sentinel (see _arm_vehicle_watchdog below) ────────
const VEH_SENTINEL_PERIOD_S : float = 30.0   # re-measure every placed vehicle this often
const VEH_SENTINEL_TOL_M    : float = 10.0   # per-leg displacement that counts as "it moved by itself"
const VEH_SENTINEL_NEAR_M   : float = 5.0    # radius of the "who was touching it" dump
# One entry per placed vehicle:
#   {"node": Node3D, "origin": Vector3 (current baseline), "label": String, "legs": int}
var _veh_watch    : Array[Dictionary] = []
var _veh_sentinel : Timer = null

## Tripwire for the unexplained 2026-07-20 relocation: the operator's five
## placed clamps were recorded 220+ m from the click point minutes later —
## not reproducible headlessly at a clean tickrate (src/tests/repro_clamp_spawn.gd:
## clamps stay within 3 m). One second after a vehicle placement, measure how
## far it actually got; a recurrence then logs who/when/where instead of
## leaving another mystery save file.
##
## 2026-07-21 — the one-second shot proved far too short. The transport measured
## in src/tests/repro_feeder_drive.gd is a SMOOTH 0.27-1.56 m/s drift (185 m in
## 150 s, zero per-frame jumps), and the operator's beads only surfaced in a
## quit-save minutes later; a 1 s window can never see either. The watchdog is
## now a STANDING sentinel: the 1 s shot stays (it is the only thing that
## catches an instantaneous teleport) and the vehicle is ALSO registered with a
## repeating VEH_SENTINEL_PERIOD_S check that runs for the rest of its life and
## dumps full driving + neighbourhood state the moment a leg exceeds tolerance.
## Purely diagnostic — nothing here changes vehicle behaviour.
func _arm_vehicle_watchdog(node: Node3D) -> void:
	var placed_at : Vector3 = node.global_position
	_veh_watch.append({
		"node": node,
		"origin": placed_at,
		"label": String(node.name),
		"legs": 0,
	})
	_ensure_vehicle_sentinel()
	get_tree().create_timer(1.0).timeout.connect(func() -> void:
		if node == null or not is_instance_valid(node):
			push_warning("[BuildMode] placed vehicle FREED within 1 s of placement")
			return
		var d := node.global_position.distance_to(placed_at)
		if d > 10.0:
			push_warning("[BuildMode] placed vehicle moved %.1f m within 1 s of placement: (%.1f, %.1f, %.1f) -> (%.1f, %.1f, %.1f)\n%s" % [
				d, placed_at.x, placed_at.y, placed_at.z,
				node.global_position.x, node.global_position.y, node.global_position.z,
				_vehicle_diagnostic_dump(node)]))

## Create the single repeating timer behind the standing sentinel, on first use.
## Lazy (rather than in _ready) so a bench that never places a vehicle never
## pays for it, and so the ordering inside _ready stays untouched.
func _ensure_vehicle_sentinel() -> void:
	if _veh_sentinel != null and is_instance_valid(_veh_sentinel):
		return
	_veh_sentinel = Timer.new()
	_veh_sentinel.name = "VehicleSentinel"
	_veh_sentinel.wait_time = VEH_SENTINEL_PERIOD_S
	_veh_sentinel.one_shot = false
	_veh_sentinel.autostart = true
	_veh_sentinel.timeout.connect(_vehicle_sentinel_tick)
	add_child(_veh_sentinel)

## Re-measure every watched vehicle against its baseline. Freed / detached
## vehicles are pruned. A vehicle that moved further than the tolerance reports
## once and then RE-BASELINES, so a slow continuous drift leaves one warning per
## 30 s leg — a readable trail with speeds — instead of the same line forever.
func _vehicle_sentinel_tick() -> void:
	var keep : Array[Dictionary] = []
	for w in _veh_watch:
		var node := w.get("node") as Node3D
		if node == null or not is_instance_valid(node) or not node.is_inside_tree():
			continue
		keep.append(w)
		var origin : Vector3 = w.get("origin", Vector3.ZERO)
		var now : Vector3 = node.global_position
		var d := origin.distance_to(now)
		if d <= VEH_SENTINEL_TOL_M:
			continue
		var legs : int = int(w.get("legs", 0)) + 1
		w["legs"] = legs
		w["origin"] = now
		push_warning("[BuildMode] SENTINEL leg %d — placed vehicle '%s' moved %.1f m (%.2f m/s avg) in the last %.0f s: (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)\n%s" % [
			legs, String(w.get("label", "?")), d, d / VEH_SENTINEL_PERIOD_S, VEH_SENTINEL_PERIOD_S,
			origin.x, origin.y, origin.z, now.x, now.y, now.z,
			_vehicle_diagnostic_dump(node)])
	_veh_watch = keep

## The state the 2026-07-20/21 investigation had to reconstruct after the fact:
## was the autopilot on, where was it told to go, did an NPC own it, and what
## else was standing in its hull. Built ONLY after the tolerance was already
## exceeded, so the cost never lands on the normal path.
func _vehicle_diagnostic_dump(node: Node3D) -> String:
	var lines : Array[String] = []
	lines.append("    npc_autopilot=%s  _npc_target_active=%s  _npc_target=%s" % [
		str(node.get("npc_autopilot")), str(node.get("_npc_target_active")), str(node.get("_npc_target"))])
	lines.append("    npc_owned=%s  npc_owner_name=%s  occupied=%s" % [
		str(node.get("npc_owned")), str(node.get("npc_owner_name")), str(node.get("occupied"))])
	lines.append("    rotation.y=%.4f  path=%s" % [node.rotation.y, str(node.get_path())])
	lines.append("    bodies within %.0f m:" % VEH_SENTINEL_NEAR_M)
	var space := get_world_3d().direct_space_state
	if space == null:
		lines.append("      (no space state)")
		return "\n".join(lines)
	var sh := SphereShape3D.new()
	sh.radius = VEH_SENTINEL_NEAR_M
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sh
	q.transform = Transform3D(Basis.IDENTITY, node.global_position)
	q.collide_with_areas = false
	q.collide_with_bodies = true
	# EVERY layer, not the vehicle's normal mask: ShiftCarSpawner parks its cars
	# on the query-only layer 1<<19 with mask 0, so a default-mask probe would be
	# blind to exactly the neighbour we most want named if one turns out to push.
	q.collision_mask = 0xFFFFFFFF
	var found := 0
	for r in space.intersect_shape(q, 16):
		var col := r.get("collider") as Node
		if col == null or col == node or node.is_ancestor_of(col):
			continue
		found += 1
		lines.append("      %s  vel=%s  path=%s" % [
			String(col.name), _body_velocity_str(col), str(col.get_path())])
	if found == 0:
		lines.append("      (none)")
	return "\n".join(lines)

## Best-effort velocity readout for an arbitrary neighbouring body: RigidBody3D
## exposes linear_velocity, CharacterBody3D exposes velocity, statics/animatables
## expose neither (an AnimatableBody3D that teleports its transform every frame
## reads "static" here — that absence is itself a useful signal).
func _body_velocity_str(body: Node) -> String:
	var lv : Variant = body.get("linear_velocity")
	if lv is Vector3:
		var a : Vector3 = lv
		return "(%.2f, %.2f, %.2f)" % [a.x, a.y, a.z]
	var v : Variant = body.get("velocity")
	if v is Vector3:
		var b : Vector3 = v
		return "(%.2f, %.2f, %.2f)" % [b.x, b.y, b.z]
	return "static"

## Any OTHER vehicle whose hull overlaps the would-be vehicle footprint at `at`.
## Returns its display name, or "" when the spot is clear. Only vehicles block:
## two nested dynamic hulls shove each other apart (the measured 2026-07-20
## stacked-clamp case); overlap rules for statics are unchanged on purpose.
func _vehicle_spawn_blocker(at: Vector3) -> String:
	var skip : Array[Node] = []
	if _ghost != null:
		skip.append(_ghost)
	return _vehicle_blocker_at(_active_id, at, _ghost_rot_y, skip)

## Shared clearance probe behind _vehicle_spawn_blocker, parameterised so the
## LOAD path can reuse it for a restored pose (which has its own id + rot_y and
## no ghost). Every node in `ignore` is skipped together with its subtree: a
## restored vehicle must not report itself, and the load pass additionally
## ignores every vehicle it restored this pass, because a body added or moved
## this frame has not been synced into the physics space yet and would be
## reported at a stale pose. Those are resolved geometrically instead.
func _vehicle_blocker_at(id: String, at: Vector3, rot_y: float, ignore: Array[Node]) -> String:
	var space := get_world_3d().direct_space_state
	if space == null:
		return ""
	var item : Dictionary = PlaceableCatalog.get_item(id)
	var sz : Vector3 = item.get("size", Vector3(2.0, 2.5, 4.0)) if not item.is_empty() else Vector3(2.0, 2.5, 4.0)
	var shape := BoxShape3D.new()
	# 85 % footprint: brushing past a parked machine stays allowed; hull-on-hull
	# does not.
	shape.size = sz * 0.85
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.transform = Transform3D(Basis(Vector3.UP, rot_y),
		at + Vector3(0.0, sz.y * 0.5 + 0.1, 0.0))
	q.collide_with_areas = false
	for r in space.intersect_shape(q, 8):
		var col : Object = r.get("collider")
		var cur : Node = col as Node
		while cur != null:
			if cur.is_in_group("vehicle"):
				if _is_ignored(cur, ignore):
					break
				return String(cur.name)
			cur = cur.get_parent()
	return ""

## True when `n` is one of `ignore` or sits inside one of their subtrees.
func _is_ignored(n: Node, ignore: Array[Node]) -> bool:
	for ig in ignore:
		if ig == null or not is_instance_valid(ig):
			continue
		if ig == n or ig.is_ancestor_of(n):
			return true
	return false

## A tall thin green vertical cylinder used as the edge-snap indicator.
## Hangs above the snap point so the operator can spot it across the floor.
func _build_snap_marker() -> Node3D:
	var m := MeshInstance3D.new()
	m.name = "SnapMarker"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06
	cm.bottom_radius = 0.06
	cm.height = 4.0
	cm.radial_segments = 8
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.20, 1.0, 0.30)
	mat.emission_enabled = true
	mat.emission = Color(0.20, 1.0, 0.30)
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true              # always visible, never occluded by walls
	m.material_override = mat
	# Centre the cylinder so its base sits at the placement point and it points up.
	m.position = Vector3(0.0, 2.0, 0.0)
	var root := Node3D.new()
	root.name = "SnapMarkerRoot"
	root.add_child(m)
	return root

## Return the 4 face centers of an axis-aligned-then-Y-rotated box, in world XZ.
## Faces are: [+local_z, -local_z, +local_x, -local_x]. Y is the box centre's Y.
func _face_centers_xz(center: Vector3, rot_y: float, sx: float, sz: float) -> Array:
	var c := cos(rot_y); var s := sin(rot_y)
	# Godot Y-up rotation about Y by rot_y. World vectors of local axes:
	var axis_x := Vector3(c, 0.0, -s)
	var axis_z := Vector3(s, 0.0,  c)
	return [
		center + axis_z * sz * 0.5,
		center - axis_z * sz * 0.5,
		center + axis_x * sx * 0.5,
		center - axis_x * sx * 0.5,
	]

## Search for the nearest placed-machine face within SNAP_MAX_DIST_M of any
## ghost face center. Returns a dict with `snap_pos` (where ghost.global_position
## should land so its closest face glues to the placed face), `midpoint` (world
## XZ of the join — where the green marker goes), and `dist`. Empty dict = no
## candidate in range.
func _find_machine_snap(ghost_pos: Vector3) -> Dictionary:
	var item : Dictionary = PlaceableCatalog.get_item(_active_id)
	if item.is_empty():
		return {}
	var gsz : Vector3 = item.get("size", Vector3.ONE)
	var ghost_faces : Array = _face_centers_xz(ghost_pos, _ghost_rot_y, gsz.x, gsz.z)
	var best : Dictionary = {}
	var best_d : float = SNAP_MAX_DIST_M
	# Scan EVERY placed machine in the world, not just children of `_placed_root`.
	# SandboxWorld pre-spawns its 5 macros via `add_child` on the world root,
	# GauntletWorld station #241 spawns silo+cyclone the same way, and MainWorld's
	# Line 3C builder parents L3C nodes under MainWorld itself. All of them get
	# tagged with the `placed_object` group + `placeable_id` meta by
	# PlaceableCatalog.build_node, so the group is the canonical entry point.
	# The ghost is parented under BuildMode and is NOT in this group — build_node(
	# id, true) intentionally skips the group for ghosts — so it can't self-snap.
	for child in get_tree().get_nodes_in_group("placed_object"):
		if not (child is Node3D):
			continue
		if child == _ghost:
			continue   # defensive: never snap to the ghost itself
		var pid : String = String(child.get_meta("placeable_id", ""))
		if pid == "":
			continue
		var pitem : Dictionary = PlaceableCatalog.get_item(pid)
		if pitem.is_empty():
			continue
		var psize : Vector3 = pitem.get("size", Vector3.ONE)
		var n3 : Node3D = child as Node3D
		var pfaces : Array = _face_centers_xz(n3.global_position, n3.rotation.y, psize.x, psize.z)
		for gi in 4:
			for pi in 4:
				var gf : Vector3 = ghost_faces[gi]
				var pf : Vector3 = pfaces[pi]
				var dx : float = gf.x - pf.x
				var dz : float = gf.z - pf.z
				var d : float = sqrt(dx * dx + dz * dz)
				if d < best_d:
					best_d = d
					var gf_off : Vector3 = (ghost_faces[gi] as Vector3) - ghost_pos
					var snap_pos : Vector3 = pf - gf_off
					best = {
						"snap_pos": snap_pos,
						"midpoint": pf,
						"dist": d,
					}
	return best

## Walk the raycast hit collider up to find a placed object; if it's a belt,
## return the snap point + the required pole height. Empty dict = not a belt.
func _try_pole_snap(hit: Dictionary) -> Dictionary:
	if not hit.has("collider"):
		return {}
	var c : Node = hit["collider"]
	while c != null and not c.is_in_group("placed_object"):
		c = c.get_parent()
	if c == null:
		return {}
	var pid := String(c.get_meta("placeable_id", ""))
	# Anything belt-like qualifies — extend this list as new belt placeables land.
	var is_belt : bool = (pid == "variable_belt" or pid == "transport_belt"
		or pid == "inclined_belt_8m" or pid == "compactorband")
	if not is_belt:
		return {}
	var pos : Vector3 = hit["position"]
	var h : float = maxf(0.15, pos.y - FLOOR_Y)
	return {"x": pos.x, "z": pos.z, "h": h}

func _spawn_ghost(id: String) -> void:
	_clear_ghost()
	if id.begins_with("line_"):
		_ghost = _make_line_ghost()   # macro: simple box + forward arrow
	else:
		_ghost = PlaceableCatalog.build_node(id, true)
	if _ghost:
		add_child(_ghost)

## Placeholder ghost for a whole-line macro: a small translucent box with a
## forward-pointing arrow so the operator can see WHERE the line will start and
## which way it will march (the ghost's local -Z).
func _make_line_ghost() -> Node3D:
	var root := Node3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.35, 0.65, 1.0, 0.4)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(2.5, 1.5, 2.5)
	box.mesh = bm; box.material_override = mat; box.position = Vector3(0, 0.75, 0)
	root.add_child(box)
	# Arrow shaft pointing -Z (forward / march direction).
	var arrow := MeshInstance3D.new()
	var am := BoxMesh.new(); am.size = Vector3(0.3, 0.3, 4.0)
	arrow.mesh = am; arrow.material_override = mat; arrow.position = Vector3(0, 0.75, -3.0)
	root.add_child(arrow)
	return root

func _clear_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null
	# Snap marker is shared across ghosts — just hide it.
	_snap_active = false
	if _snap_marker != null and is_instance_valid(_snap_marker):
		_snap_marker.visible = false

func _place_current() -> void:
	if _ghost == null or not _ghost.visible:
		return
	# Whole-line macro: lay the entire train from here and stay in placing mode so
	# the operator could drop a second line if they want.
	if _active_id.begins_with("line_"):
		_build_full_line(_active_id, _ghost.global_position, _ghost_rot_y)
		_save_layout()
		# Whole-line macros ALWAYS touch the material-flow graph (they're literally
		# the line). No gating needed here, but use the helper for symmetry: a
		# macro that somehow expanded to only observers would correctly skip.
		if line_flow and _is_flow_relevant(_active_id):
			line_flow.rebuild()
		return
	# Two-point placeables (variable_belt): first click stashes the START point,
	# second click spans from start → cursor and finalizes.
	if PlaceableCatalog.is_two_point(_active_id):
		if not _has_two_point:
			_two_point_start = _ghost.global_position
			_has_two_point = true
			_ensure_two_point_preview()
			_update_placing_status()
			return
		var end_pos := _ghost.global_position
		if _active_id == "grating_platform":
			# Rectangle from the two opposite corners; the deck sits at the START height
			# and the support posts (tagged machine_leg by the builder) extend down to the
			# floor and auto-hide where they'd punch through a machine (extend_machine_legs).
			var gw : float = absf(end_pos.x - _two_point_start.x)
			var gl : float = absf(end_pos.z - _two_point_start.z)
			var plat := PlaceableCatalog.build_grating_platform(gw, gl, false)
			if plat != null:
				_placed_root.add_child(plat)
				plat.global_position = Vector3(
					(_two_point_start.x + end_pos.x) * 0.5,
					_two_point_start.y,
					(_two_point_start.z + end_pos.z) * 0.5)
				plat.rotation.y = _ghost_rot_y
				_finalize_placed(plat, _active_id, _two_point_start.y - FLOOR_Y)
		elif PlaceableCatalog.is_wall(_active_id):
			# Solid wall along the start→end line. thickness/height from the chosen
			# wall placeable (size.x / size.y); endpoints saved so it reloads exactly.
			var item : Dictionary = PlaceableCatalog.get_item(_active_id)
			var wsz : Vector3 = item.get("size", Vector3(0.2, 3.5, 1.0)) if not item.is_empty() else Vector3(0.2, 3.5, 1.0)
			var wall := PlaceableCatalog.build_wall(_two_point_start, end_pos, wsz.x, wsz.y, false)
			if wall != null:
				_placed_root.add_child(wall)
				wall.global_position = Vector3(
					(_two_point_start.x + end_pos.x) * 0.5,
					_two_point_start.y,
					(_two_point_start.z + end_pos.z) * 0.5)
				# `placeable_id` is the KEY _save_layout() gates on (line ~2996):
				# a child without it is not serialised at all, so before this
				# line every hand-built wall was gone on the next load — the
				# operator drew a partition, saved, reloaded, and the plant was
				# open-plan again. build_wall() cannot set it itself (it is a
				# static helper that never receives the id), and _finalize_placed
				# only writes height_offset, so it has to be set here. The reload
				# path at line ~3369 already stamps the same three metas, which is
				# why loading a wall worked and saving one never did.
				wall.set_meta("placeable_id", _active_id)
				wall.set_meta("wall_start", _two_point_start)
				wall.set_meta("wall_end", end_pos)
				_finalize_placed(wall, _active_id, _two_point_start.y - FLOOR_Y)
		else:
			var belt_node := PlaceableCatalog.build_variable_belt(_two_point_start, end_pos, false)
			if belt_node != null:
				_placed_root.add_child(belt_node)
				# Auto-spawn the leg poles the variable belt recorded in its meta — one
				# pole every ~2.5 m along the span at the correct world-vertical height.
				_spawn_auto_legs(belt_node)
		_has_two_point = false
		_two_point_start = Vector3.ZERO
		_clear_two_point_preview()
		_save_layout()
		# #218 — Walls/gratings are observer-only; only belts (variable_belt) feed
		# the material-flow graph. Gate so dropping a wall doesn't restart the line.
		if line_flow and _is_flow_relevant(_active_id):
			line_flow.rebuild()
		else:
			# Observer-only placement (HMI, decoration). Skip the rebuild that
			# would restart the whole line; let panel binders re-resolve via a
			# signal if LineFlow provides one.
			if line_flow and line_flow.has_signal("observer_placed"):
				line_flow.emit_signal("observer_placed", _active_id)
		_update_placing_status()
		# Sequential mode: advance to next step after a two-point placement completes.
		if _state == State.SEQUENTIAL:
			_seq_index += 1
			if _seq_index >= _seq.size():
				_exit_sequential("✅ Lijn klaar! (%s)" % _seq_line_name)
			else:
				_load_seq_step()
		return
	# Poles use a custom-height build path so the smart snap height (or the
	# default height when no belt is under the crosshair) actually lands as the
	# pole's standing height — not a uniform Y-scaled mesh.
	if PlaceableCatalog.is_pole(_active_id):
		var height : float = _pole_snap_height if _pole_snap_height > 0.0 else POLE_DEFAULT_H
		var base : Vector3 = _pole_snap_xz if _pole_snap_height > 0.0 else _ghost.global_position
		var pole := PlaceableCatalog.build_pole(_active_id, height, false)
		if pole != null:
			_placed_root.add_child(pole)
			pole.global_position = base
			pole.rotation.y = _ghost_rot_y
			_finalize_placed(pole, _active_id, 0.0)
		_save_layout()
		# Sequential mode: advance to next step after a pole placement.
		if _state == State.SEQUENTIAL:
			_seq_index += 1
			if _seq_index >= _seq.size():
				_exit_sequential("✅ Lijn klaar! (%s)" % _seq_line_name)
			else:
				_load_seq_step()
		return
	# Vehicle spawn clearance gate (operator 2026-07-20: five clamp clicks at one
	# aim point nested five VehicleBody3Ds inside each other — the pile shoved
	# itself apart/upward and read as "spawning is unsuccessful"). A vehicle may
	# not materialize inside another vehicle; refuse LOUDLY instead of silently
	# stacking. Statics keep the pre-existing free-placement rules.
	if _active_id.begins_with("vehicle_"):
		var blocker := _vehicle_spawn_blocker(_ghost.global_position)
		if blocker != "":
			_status.text = "SPAWN GEBLOKKEERD — %s staat op deze plek. Kies een vrije plek." % blocker
			return
	var node := PlaceableCatalog.build_node(_active_id, false)
	if node == null:
		return
	_placed_root.add_child(node)
	node.global_position = _ghost.global_position
	# Vehicles get the same +0.5 m drop cushion VehicleSpawner uses — a
	# VehicleBody3D whose wheels materialize exactly flush with the surface
	# starts in contact-manifold ambiguity; a short drop settles it cleanly.
	if _active_id.begins_with("vehicle_"):
		node.global_position.y += 0.5
		_arm_vehicle_watchdog(node)
	node.rotation.y = _ghost_rot_y
	_finalize_placed(node, _active_id, _ghost_height)
	_finalize_bale(node)
	# door_personnel / gate_roller / window_frame are decoration-only geometry
	# from PlaceableCatalog (see build_node's #116 comment) — carve the matching
	# wall opening NOW, live, instead of leaving the operator with a model
	# standing in front of an intact wall until the next save/reload. Same path
	# _load_structure_placeable replays on load, so a fresh placement and a
	# reloaded one look and behave identically from this point on.
	if _active_id == "door_personnel" or _active_id == "gate_roller" or _active_id == "window_frame":
		if not _carve_structure_opening(node, _active_id, node.global_position, _ghost_rot_y):
			# No wall within the carve box — tell the operator directly instead
			# of leaving them to click the same spot again believing it's
			# broken (measured 2026-08-08: 41 repeat clicks, ~5-8 m from the
			# nearest wall, each one a full shell rebuild before this guard).
			var walkie := get_node_or_null("/root/Walkie")
			if walkie and walkie.has_method("receive_call"):
				walkie.call("receive_call", "Bouw",
					"Geen muur gevonden op deze plek — de %s staat er, maar er is niets om een doorgang in te snijden."
						% PlaceableCatalog.get_item(_active_id).get("name", _active_id))
			push_warning("[BuildMode] %s placed at %s but no wall was found to carve — the model stands with no opening"
				% [_active_id, str(node.global_position)])
	_save_layout()
	# #218 — Don't restart the whole line for observer-only fixtures (HMI panels,
	# signs, doors, decorations). Rebuild wipes powered/spin/buffer and forces a
	# ~20 s downstream-first PLC re-stagger; skip it when the placement can't have
	# changed the material-flow graph.
	if line_flow and _is_flow_relevant(_active_id):
		line_flow.rebuild()
	else:
		# Observer-only placement (HMI, decoration). Skip the rebuild that
		# would restart the whole line; let panel binders re-resolve via a
		# signal if LineFlow provides one.
		if line_flow and line_flow.has_signal("observer_placed"):
			line_flow.emit_signal("observer_placed", _active_id)
	# ── Sequential mode advance ───────────────────────────────────────────────
	# After every normal single-machine placement, check if we are in sequential
	# mode and advance to the next entry. This fires AFTER the LineFlow rebuild so
	# the freshly placed machine is already in the graph before the next ghost loads.
	if _state == State.SEQUENTIAL:
		_seq_index += 1
		if _seq_index >= _seq.size():
			_exit_sequential("✅ Lijn klaar! (%s)" % _seq_line_name)
		else:
			_load_seq_step()

## Lay a whole line front-to-back from `start`, marching along the ghost's local
## -Z (forward). Each machine is built, rotated to face the march, spaced by its
## own depth (size.z) + LINE_GAP_M, and added as an individual placed_object so
## it persists and can be jogged (K mode). Material wiring is the LineFlow
## follow-up (#48); this lays the geometry.
##
## MACRO SAVE-BACK (#MSB): every machine spawned here is tagged with
##   macro_id          — e.g. "line_3a", lets save-back find sibling members.
##   macro_index       — its 0-based index in the SEQ; lets save-back compute
##                       the per-index delta and the load path inherit the
##                       upstream chain drift.
##   macro_anchor      — {"start": Vector3, "rot_y": float} stamped at
##                       placement time; the inverse transform uses it to
##                       recover the local-frame offset from world pose.
## On placement, any saved overrides from LineMacroStore are applied as a
## chain-style cumulative delta (machine N's drift is the sum of all earlier
## indices' explicit overrides; an unmoved machine inherits its previous
## machine's accumulated drift).
func _build_full_line(line_id: String, start: Vector3, rot_y: float) -> void:
	var seq : Array[Dictionary] = LINE_3A_SEQ
	if line_id == "line_3b":
		seq = LINE_3B_SEQ
	elif line_id == "line_1":
		seq = LINE_1_SEQ
	elif line_id == "line_intake_3a3b":
		seq = INTAKE_3A3B_SEQ
	elif line_id == "line_sort":
		seq = LINE_SORT_SEQ
	elif line_id == "line_intake_3c6":
		seq = LINE_3C6_SEQ
	elif line_id == "line_3c":
		seq = LINE_3C_SEQ
	# #MSB — pull operator-saved deltas (chain-accumulated) from the store.
	# Each index's delta is added in the macro's LOCAL frame (x/z lateral,
	# y vertical, rot_y around vertical). Empty dict = use const seed verbatim.
	var macro_deltas : Dictionary = LineMacroStore.accumulated_chain(line_id, seq.size())
	# Authored-graph macro: place geometry only, stamp NO lf_explicit_outs. See
	# GRAPH_TOPOLOGY_MACROS — that meta suppresses LineFlow's Line3CDef.LINKS pass.
	var graph_topology : bool = GRAPH_TOPOLOGY_MACROS.has(line_id)
	# ── LEG STATE (#fold 2026-08-28) ─────────────────────────────────────────
	# A line is a chain of straight LEGS. A main entry carrying {"turn_deg": a}
	# rotates the heading by `a` degrees (POSITIVE = LEFT, i.e. CCW seen from
	# above) around the current cursor point BEFORE that entry is placed; the
	# cursor point becomes the new leg's origin and the cursor resets to 0.
	# Optional {"turn_advance": m} pre-advances the new leg's cursor (used to
	# line a corner chute's discharge up with the next machine's inlet).
	# Every placed node's macro_anchor meta records ITS OWN leg's {start,
	# rot_y}, so save_macro_overrides can invert per-leg. Built for the line-1
	# fold (operator layout sketch, 2026-08-28); no other macro turns yet.
	# Forward = the ghost's local -Z; right = local +X (lateral lane for branches).
	var leg_start := start
	var leg_rot := rot_y
	var leg_idx := 0
	var fwd := Vector3(-sin(leg_rot), 0.0, -cos(leg_rot))
	var rgt := Vector3(cos(leg_rot), 0.0, -sin(leg_rot))
	var main_z := 0.0
	var total_run := 0.0                  # summed leg lengths, for the report line
	var leg_by_idx : Dictionary = {}      # entry_idx -> leg_idx (at_entry guard)
	# Saved-delta chain semantics across a turn: accumulated_chain() knows
	# nothing about legs, and an upstream drag must NOT leak its drift into a
	# leg with a different frame. `delta_base` snapshots the accumulated delta
	# at the last pre-turn index; each application subtracts it, so inheritance
	# restarts at every leg. save_macro_overrides mirrors this (acc reset per
	# leg) — keep the two in lockstep.
	var delta_base : Dictionary = {"dx": 0.0, "dy": 0.0, "dz": 0.0, "drot_y": 0.0}
	var built := 0
	# #lump-3c — per-entry place_z snapshots, so a LATER entry can anchor itself
	# to an earlier machine's z-centre via {"at_entry": N}. This is what lets the
	# 3C laserfilter furniture live at the APPEND-ONLY tail of the SEQ (indices
	# past the Line3CDef.STAGES spine, so no macro_index → l3c_code address ever
	# shifts) while still being placed beside entry 23's laser filter.
	var entry_z_by_idx : Dictionary = {}
	# #71 branch tracking — explicit edges for split / recirc topology.
	# Two distinct kinds of branch are supported:
	#   CHAINED  (3A recirc loop): one machine after another along +X side lane,
	#            connected to each other by geometry-fallback; only the FIRST
	#            and LAST entries need explicit edges to/from the main path.
	#   PARALLEL (3B L-R split): two sibling branches at the same Z but opposite
	#            X, each independent. The branch source feeds BOTH; both feed
	#            the recombine target.
	# `last_main_node` tracks the most recent x==0 placement so we know where a
	# starting branch was fed from.
	var last_main_node : Node3D = null
	var branch_chain : Array = []      # consecutive chained branch nodes (3A recirc)
	var branch_source : Node3D = null  # main node feeding the current chain
	var branch_recirc : bool = false
	var parallel_siblings : Array = [] # nodes flagged "parallel_branch"
	var parallel_source : Node3D = null
	# #141 — transportband chain Y-stacking + head-to-tail spacing. Consecutive
	# transportband_* IDs stack vertically (each belt's inlet sits CHUTE_DROP_M
	# below the previous belt's outlet, so the chutes baked into the belt body
	# actually bridge to the next inlet) and sit head-to-tail in Z (no
	# LINE_GAP_M between them). Anything else in the SEQ resets the chain.
	const TB_CHUTE_DROP_M : float = 0.22
	var prev_tb_outlet_y : float = -1.0   # sentinel = first belt sits on floor
	var last_main_was_tb : bool = false
	var prev_main_gap : float = LINE_GAP_M   # gap actually added after the previous main entry
	for entry_idx in range(seq.size()):
		var entry : Dictionary = seq[entry_idx]
		var mid : String = String(entry.get("id", ""))
		if mid == "":
			continue
		var x : float = float(entry.get("x", 0.0))
		var is_branch : bool = not is_equal_approx(x, 0.0)
		var is_parallel : bool = bool(entry.get("parallel_branch", false))
		# ── #fold — turn the line heading before placing this entry ──────────
		if entry.has("turn_deg"):
			if is_branch:
				push_warning("[BuildMode] %s entry %d: turn_deg on a BRANCH entry is unsupported — ignored" % [line_id, entry_idx])
			else:
				leg_start = leg_start + fwd * main_z          # pivot = cursor point
				leg_rot += deg_to_rad(float(entry["turn_deg"]))
				fwd = Vector3(-sin(leg_rot), 0.0, -cos(leg_rot))
				rgt = Vector3(cos(leg_rot), 0.0, -sin(leg_rot))
				total_run += main_z
				main_z = float(entry.get("turn_advance", 0.0))
				leg_idx += 1
				# A turn breaks the transportband head-to-tail chain and the
				# saved-delta inheritance (frame change).
				prev_tb_outlet_y = -1.0
				last_main_was_tb = false
				prev_main_gap = LINE_GAP_M
				if entry_idx > 0:
					delta_base = macro_deltas.get(entry_idx - 1, delta_base)
		leg_by_idx[entry_idx] = leg_idx
		var item := PlaceableCatalog.get_item(mid)
		var depth : float = 2.0
		if not item.is_empty():
			depth = maxf((item["size"] as Vector3).z, 0.5)
		var is_tb : bool = mid.begins_with("transportband_")
		# #141 — Y-stacking for transportbands. Compute this belt's base_y from
		# the previous transportband's outlet height, so the chutes baked into
		# each belt's outlet bridge into the next belt's inlet.
		var tb_y_offset : float = 0.0
		var tb_outlet_y_after : float = -1.0   # -1 = don't update chain state
		if is_tb and not item.is_empty():
			var bsize : Vector3 = item["size"]
			var blen : float = bsize.z
			var spec : Dictionary = PlaceableCatalog._transportband_spec(mid)
			var incline_rad : float = deg_to_rad(float(spec.get("incline", 0.0)))
			var deck_top : float = bsize.y * 0.97
			var lift_at_end : float = (blen * 0.45) * sin(incline_rad)
			var inlet_top_off : float = deck_top - lift_at_end
			var outlet_top_off : float = deck_top + lift_at_end
			var base_y : float = 0.0
			if prev_tb_outlet_y > 0.0:
				base_y = maxf(0.0, prev_tb_outlet_y - TB_CHUTE_DROP_M - inlet_top_off)
			tb_y_offset = base_y
			tb_outlet_y_after = base_y + outlet_top_off
		var place_z : float
		# Per-entry gap override: {"gap": 1.2} replaces LINE_GAP_M after this machine.
		var gap_after : float = float(entry.get("gap", LINE_GAP_M))
		if not is_branch:
			# Main-centreline machine — advances the main cursor.
			# Head-to-tail spacing for consecutive transportbands: undo the gap
			# that the previous main entry actually added (a "gap" override may
			# have replaced LINE_GAP_M), so this belt's inlet butts directly
			# against the prior belt's outlet.
			if last_main_was_tb and is_tb:
				main_z -= prev_main_gap
			main_z += depth * 0.5
			place_z = main_z
			main_z += depth * 0.5 + gap_after
			prev_main_gap = gap_after
			last_main_was_tb = is_tb
		else:
			# Branch machine — sits beside the line at (current cursor + z offset) and
			# does NOT advance the main cursor (the main flow runs past it).
			# {"at_entry": N} re-bases the z offset on entry N's placed z-CENTRE
			# instead of the current cursor (N must be an EARLIER entry — the
			# snapshot only exists once N has been placed). No size coupling: if
			# entry N's machine grows, the anchored furniture moves with it.
			var anchor_idx : int = int(entry.get("at_entry", -1))
			if anchor_idx >= 0:
				# #fold — z snapshots are LEG-relative; anchoring across a turn
				# would re-base on a coordinate from a different frame.
				if int(leg_by_idx.get(anchor_idx, leg_idx)) != leg_idx:
					push_warning("[BuildMode] %s entry %d: at_entry %d is on a different leg — geometry will be wrong" % [line_id, entry_idx, anchor_idx])
				if entry_z_by_idx.has(anchor_idx):
					place_z = float(entry_z_by_idx[anchor_idx]) + float(entry.get("z", 0.0))
				else:
					push_warning("[BuildMode] %s entry %d: at_entry %d not placed yet — falling back to cursor"
						% [line_id, entry_idx, anchor_idx])
					place_z = main_z + float(entry.get("z", 0.0))
			else:
				place_z = main_z + float(entry.get("z", 0.0))
		entry_z_by_idx[entry_idx] = place_z
		# Update transportband chain state AFTER we've used prev_tb_outlet_y for
		# this belt's base. Branches like transportband_8_5 read from the chain
		# (so they stack from belt 8's outlet) but do NOT overwrite it — main
		# transportband_9 still picks up from belt 8, not 8_5.
		if is_tb and not is_branch and tb_outlet_y_after > 0.0:
			prev_tb_outlet_y = tb_outlet_y_after
		elif not is_tb and not is_branch:
			# Leaving the chain — reset.
			prev_tb_outlet_y = -1.0
		var node := PlaceableCatalog.build_node(mid, false)
		if node != null:
			_placed_root.add_child(node)
			# #MSB — apply operator-saved chain delta (in macro local frame).
			# dx → lateral (rgt), dz → forward (fwd), dy → vertical.
			var d : Dictionary = macro_deltas.get(entry_idx, {})
			# #fold — subtract the pre-turn accumulated drift so saved-delta
			# inheritance restarts at each leg (see delta_base above).
			var d_dx : float = float(d.get("dx", 0.0)) - float(delta_base.get("dx", 0.0))
			var d_dy : float = float(d.get("dy", 0.0)) - float(delta_base.get("dy", 0.0))
			var d_dz : float = float(d.get("dz", 0.0)) - float(delta_base.get("dz", 0.0))
			var d_drot : float = float(d.get("drot_y", 0.0)) - float(delta_base.get("drot_y", 0.0))
			if d.is_empty():
				# No stored delta at all for this index — nothing to re-base.
				d_dx = 0.0; d_dy = 0.0; d_dz = 0.0; d_drot = 0.0
			var d_scale : Vector3 = Vector3.ONE
			if d.has("scale") and d["scale"] is Vector3:
				d_scale = d["scale"]
			# #225.3 — optional per-entry "y" lifts a branch item onto a raised
			# surface (e.g. lump carts resting on the lump_platform bordes deck at
			# y=0.12, mirroring NpcTaskBench.PLATFORM_Y). Defaults to 0 so every
			# existing macro entry is unchanged.
			var entry_y : float = float(entry.get("y", 0.0))
			node.global_position = Vector3(leg_start.x, leg_start.y + tb_y_offset, leg_start.z) \
				+ fwd * (place_z + d_dz) + rgt * (x + d_dx) + Vector3.UP * (d_dy + entry_y)
			node.rotation.y = leg_rot + PI + d_drot
			if d_scale != Vector3.ONE:
				node.scale = d_scale
			# #fold — {"extend_legs": true} passes the entry's y lift through to
			# _finalize_placed so the machine's own legs stretch to the floor
			# (e.g. the elevated sga_feed_chute at the drum head). Opt-in:
			# existing lifted entries (lump carts on the 0.12 m bordes) keep
			# their legacy no-frame behaviour.
			_finalize_placed(node, mid, entry_y if bool(entry.get("extend_legs", false)) else 0.0)
			# #MSB — stamp macro-membership metas so save-back can find this
			# node and recover its local-frame pose later.
			node.set_meta("macro_id", line_id)
			node.set_meta("macro_index", entry_idx)
			# #fold — the anchor is THIS NODE'S LEG, not the macro's entry
			# point. save_macro_overrides inverts per node with this.
			node.set_meta("macro_anchor", {"start": leg_start, "rot_y": leg_rot})
			built += 1
			# ── #71 branch state transitions ───────────────────────────────────
			# I1 fix (component_flags_review.md, confirmed 2026-07-06): utilities
			# whose MachineFlow role is "none" (water pumps, kleine LA, lump cart
			# + spot, …) must NOT take part in branch/parallel bookkeeping.
			# LineFlow marks any node with a non-empty lf_explicit_outs meta as
			# explicit_src BEFORE checking that its targets resolve and then skips
			# the geometry fallback for it — but a role-none target is never
			# discovered, so the edge is dropped and the source machine ends the
			# linker with ZERO outgoing edges (fresh line_3a: transfer_chute lost
			# its edge because of the side-lane water_pump). Role-none entries are
			# placement-only: no _add_explicit_out, no chain/sibling membership,
			# and (symmetrically) a role-none MAIN entry never becomes
			# last_main_node or closes an open branch.
			var flow_relevant : bool = _is_flow_relevant(mid) and not graph_topology
			if not flow_relevant:
				pass   # placement only — invisible to the flow topology
			elif is_branch:
				if is_parallel:
					# Parallel sibling — share branch_source with peers, tag now.
					if parallel_source == null:
						parallel_source = last_main_node
					if parallel_source != null:
						_add_explicit_out(parallel_source, node, false)
					parallel_siblings.append(node)
				else:
					# Chained branch entry — first one carries the start link.
					if branch_chain.is_empty():
						branch_source = last_main_node
						branch_recirc = bool(entry.get("branch_recirc", false))
						if branch_source != null:
							_add_explicit_out(branch_source, node, false)
					branch_chain.append(node)
			else:
				# A new main-centreline machine — close any open branches.
				if not branch_chain.is_empty():
					var last_chain : Node3D = branch_chain[branch_chain.size() - 1] as Node3D
					var last_role : String = String(MachineFlow.profile(
						String(last_chain.get_meta("placeable_id"))).get("role", ""))
					if branch_recirc and branch_source != null:
						# Recirc: last branch entry returns to the branch source.
						_add_explicit_out(last_chain, branch_source, true)
						# 2026-08-28 SEVERED-MAIN FIX (found by the 3A doc-walk
						# test): tagging the source with lf_explicit_outs makes
						# LineFlow SKIP its geometry fallback (LineFlow.gd:1142),
						# and nothing ever reconnected it to the next main — so
						# 3A's line was silently DEAD past the mengsilo: the
						# side-loop closed but mengsilo → M11b never existed.
						# A recirc loop is a side-circuit; the main path must
						# continue from its source.
						_add_explicit_out(branch_source, node, false)
					elif last_role == "sink" and branch_source != null:
						# Chain dead-ends in a SINK (e.g. the 3A bigbag
						# station): the sink banks material and LineFlow never
						# emits from sinks (:1137), so an edge out of it would
						# be dead anyway — the MAIN path continues from the
						# branch source instead.
						_add_explicit_out(branch_source, node, false)
					else:
						# Normal chained branch: last entry feeds this new main.
						_add_explicit_out(last_chain, node, false)
					branch_chain.clear()
					branch_source = null
					branch_recirc = false
				if not parallel_siblings.is_empty():
					for sib in parallel_siblings:
						_add_explicit_out(sib as Node3D, node, false)
					parallel_siblings.clear()
					parallel_source = null
				last_main_node = node
		# Explicit cursor push to clear a split/recombine (e.g. past parallel dryers).
		if entry.has("main_advance"):
			main_z += float(entry["main_advance"])
	total_run += main_z
	print("[BuildMode] Built %s — %d machines over %.1f m in %d leg(s)" % [line_id, built, total_run, leg_idx + 1])
	if _status:
		_status.text = "Built %s — %d machines.  Use [K] edit mode to jog each into place." % [
			line_id.to_upper(), built]

## #71 — record an explicit downstream edge from `src` to `tgt` on src's
## `lf_explicit_outs` meta. LineFlow's linker reads this list and adds each
## edge (skipping the geometry-fallback for tagged sources). `recirc=true`
## marks the edge as invisible to cycle-detection so 3A's dry-loop can close.
func _add_explicit_out(src: Node3D, tgt: Node3D, recirc: bool) -> void:
	if src == null or tgt == null or src == tgt:
		return
	var outs : Array = src.get_meta("lf_explicit_outs") if src.has_meta("lf_explicit_outs") else []
	if not (outs is Array):
		outs = []
	outs.append({"path": tgt.get_path(), "recirc": recirc})
	src.set_meta("lf_explicit_outs", outs)

# =============================================================================
# MACRO SAVE-BACK (#MSB) — capture in-world edits to a placed macro back into
# user://macros/<macro_id>.json so future placements emit the corrected layout.
# Triggered by a HUD button (per "Lines" macro) or by SHIFT+K while in EDIT
# mode if a placed_object with `macro_id` meta is selected.
# =============================================================================

## Pull the const seed used by _build_full_line so we can re-run the same
## cursor math and recover each machine's NOMINAL local pose.
func _macro_seed(macro_id: String) -> Array[Dictionary]:
	if macro_id == "line_3a":          return LINE_3A_SEQ
	if macro_id == "line_3b":          return LINE_3B_SEQ
	if macro_id == "line_1":           return LINE_1_SEQ
	if macro_id == "line_intake_3a3b": return INTAKE_3A3B_SEQ
	if macro_id == "line_sort":        return LINE_SORT_SEQ
	if macro_id == "line_intake_3c6":  return LINE_3C6_SEQ
	if macro_id == "line_3c":          return LINE_3C_SEQ
	return [] as Array[Dictionary]

## Re-walk the seed SEQ (no spawning) and emit an Array of {x, z, rot_y_extra}
## NOMINAL local-frame placements per index. Mirrors the cursor advancement
## inside _build_full_line so the per-index nominal pose lines up exactly with
## what the original placement put in world. Branch nodes inherit a y offset
## of 0; transportband Y stacking is captured via tb_y_offset.
func _macro_nominal_poses(p_seed: Array[Dictionary]) -> Array:
	var poses : Array = []
	var main_z := 0.0
	const TB_CHUTE_DROP_M : float = 0.22
	var prev_tb_outlet_y : float = -1.0
	var last_main_was_tb : bool = false
	# 2026-08-28 MIRROR FIX: this walk ignored per-entry {"gap": g} overrides
	# and undid tb head-to-tail spacing with the constant instead of the gap
	# actually added — so every nominal z after a gap override disagreed with
	# _build_full_line, and save-back recorded phantom deltas that the load
	# path then re-applied onto the same wrong nominal (self-consistent, so
	# the round-trip test never went red). Now tracks prev_main_gap exactly
	# like the builder.
	var prev_main_gap : float = LINE_GAP_M
	# #fold — leg tracking mirrors _build_full_line: a main entry with
	# turn_deg resets the leg-relative cursor (and optionally pre-advances by
	# turn_advance). Emitted "leg" lets save_macro_overrides reset its chain
	# accumulator at each leg boundary.
	var leg := 0
	# 2026-08-28 MIRROR FIX 2: {"at_entry": N} anchoring existed only in the
	# builder — nominal fell back to the cursor, so 3C's laserfilter furniture
	# had wrong nominals (masked by the same phantom-delta self-consistency).
	var entry_z_by_idx : Dictionary = {}
	for entry_idx in range(p_seed.size()):
		var entry : Dictionary = p_seed[entry_idx]
		var mid : String = String(entry.get("id", ""))
		if mid == "":
			poses.append({"x": 0.0, "y": 0.0, "z": 0.0, "leg": leg})
			continue
		var x : float = float(entry.get("x", 0.0))
		var is_branch : bool = not is_equal_approx(x, 0.0)
		if entry.has("turn_deg") and not is_branch:
			main_z = float(entry.get("turn_advance", 0.0))
			leg += 1
			prev_tb_outlet_y = -1.0
			last_main_was_tb = false
			prev_main_gap = LINE_GAP_M
		var item := PlaceableCatalog.get_item(mid)
		var depth : float = 2.0
		if not item.is_empty():
			depth = maxf((item["size"] as Vector3).z, 0.5)
		var is_tb : bool = mid.begins_with("transportband_")
		var tb_y_offset : float = 0.0
		var tb_outlet_y_after : float = -1.0
		if is_tb and not item.is_empty():
			var bsize : Vector3 = item["size"]
			var blen : float = bsize.z
			var spec : Dictionary = PlaceableCatalog._transportband_spec(mid)
			var incline_rad : float = deg_to_rad(float(spec.get("incline", 0.0)))
			var deck_top : float = bsize.y * 0.97
			var lift_at_end : float = (blen * 0.45) * sin(incline_rad)
			var inlet_top_off : float = deck_top - lift_at_end
			var outlet_top_off : float = deck_top + lift_at_end
			var base_y : float = 0.0
			if prev_tb_outlet_y > 0.0:
				base_y = maxf(0.0, prev_tb_outlet_y - TB_CHUTE_DROP_M - inlet_top_off)
			tb_y_offset = base_y
			tb_outlet_y_after = base_y + outlet_top_off
		var place_z : float
		var gap_after : float = float(entry.get("gap", LINE_GAP_M))
		if not is_branch:
			if last_main_was_tb and is_tb:
				main_z -= prev_main_gap
			main_z += depth * 0.5
			place_z = main_z
			main_z += depth * 0.5 + gap_after
			prev_main_gap = gap_after
			last_main_was_tb = is_tb
		else:
			var anchor_idx : int = int(entry.get("at_entry", -1))
			if anchor_idx >= 0 and entry_z_by_idx.has(anchor_idx):
				place_z = float(entry_z_by_idx[anchor_idx]) + float(entry.get("z", 0.0))
			else:
				place_z = main_z + float(entry.get("z", 0.0))
		entry_z_by_idx[entry_idx] = place_z
		if is_tb and not is_branch and tb_outlet_y_after > 0.0:
			prev_tb_outlet_y = tb_outlet_y_after
		elif not is_tb and not is_branch:
			prev_tb_outlet_y = -1.0
		# 2026-08-28 MIRROR FIX 3 (found by the fold review): the per-entry
		# {"y": h} lift is part of the NOMINAL pose — the builder adds it at
		# placement, so leaving it out of the nominal made save_macro_overrides
		# record it as a phantom operator dy, which the load path then applied
		# ON TOP of entry_y: every save/rebuild cycle would double the lift
		# (lump carts +0.12, the fold's hoekgoot +3.48 → 6.96 m). delta_sane
		# never catches it (threshold is metres of drag, not stacking).
		poses.append({"x": x, "y": tb_y_offset + float(entry.get("y", 0.0)),
			"z": place_z, "leg": leg})
		if entry.has("main_advance"):
			main_z += float(entry["main_advance"])
	return poses

## Walk placed_object children tagged with `macro_id`, compute the local-frame
## delta for each one vs the const seed's nominal pose, accumulate chain-style
## (so machine N stores ONLY the explicit drift NOT already explained by
## upstream changes), and hand the dict to LineMacroStore. Returns the number
## of overrides written.
func save_macro_overrides(macro_id: String) -> int:
	var p_seed : Array[Dictionary] = _macro_seed(macro_id)
	if p_seed.is_empty():
		push_warning("[BuildMode] Unknown macro id %s" % macro_id)
		return 0
	var nominal : Array = _macro_nominal_poses(p_seed)
	# Gather siblings: every placed_object whose macro_id meta matches.
	var members : Dictionary = {}   # int_index -> Node3D
	var anchor : Dictionary = {}
	for child in _placed_root.get_children():
		if not (child is Node3D): continue
		if not child.has_meta("macro_id"): continue
		if String(child.get_meta("macro_id")) != macro_id: continue
		if not child.has_meta("macro_index"): continue
		var idx : int = int(child.get_meta("macro_index"))
		members[idx] = child
		if anchor.is_empty() and child.has_meta("macro_anchor"):
			anchor = child.get_meta("macro_anchor")
	if members.is_empty() or anchor.is_empty():
		if _status:
			_status.text = "No placed %s macro to save back." % macro_id.to_upper()
		return 0
	var a_start : Vector3 = anchor.get("start", Vector3.ZERO)
	var a_rot   : float   = float(anchor.get("rot_y", 0.0))
	# #fold — anchors are PER LEG since the turn capability: each node's own
	# macro_anchor meta carries its leg's {start, rot_y}, and the inverse
	# transform below re-derives fwd/rgt per node. The a_start/a_rot above
	# remain only as a fallback for nodes missing the meta (pre-fold saves).
	# Build the chain accumulator: for each index the operator MOVED (or any
	# index <= max moved), compute its local delta vs nominal, then subtract
	# the upstream accumulated drift so the on-disk value is the operator's
	# EXPLICIT contribution at that index.
	var deltas : Dictionary = {}
	var acc := Vector3.ZERO
	var acc_rot := 0.0
	var acc_scale := Vector3.ONE
	var cur_leg : int = 0
	for i in range(p_seed.size()):
		if not members.has(i):
			continue
		var node : Node3D = members[i]
		var nom : Dictionary = {"x": 0.0, "y": 0.0, "z": 0.0}
		if i < nominal.size() and nominal[i] is Dictionary:
			nom = nominal[i]
		# #fold — a turn changes the local frame, so upstream drift cannot
		# inherit across it: reset the chain accumulator at each leg boundary
		# (the load side mirrors this via delta_base in _build_full_line).
		var nom_leg : int = int(nom.get("leg", 0))
		if nom_leg != cur_leg:
			cur_leg = nom_leg
			acc = Vector3.ZERO
			acc_rot = 0.0
		# #fold — invert with THIS NODE'S leg anchor.
		var n_anchor : Dictionary = node.get_meta("macro_anchor") if node.has_meta("macro_anchor") else anchor
		var n_start : Vector3 = n_anchor.get("start", a_start)
		var n_rot : float = float(n_anchor.get("rot_y", a_rot))
		var fwd := Vector3(-sin(n_rot), 0.0, -cos(n_rot))
		var rgt := Vector3(cos(n_rot), 0.0, -sin(n_rot))
		# Inverse transform: local = inverse_basis * (world_pos - start).
		# Basis is rotation-only around Y, so dot products recover x_local
		# (along rgt) and z_local (along fwd).
		var rel : Vector3 = node.global_position - n_start
		var x_local : float = rel.dot(rgt)
		var z_local : float = rel.dot(fwd)
		var y_local : float = rel.y
		var dx : float = x_local - float(nom.get("x", 0.0))
		var dy : float = y_local - float(nom.get("y", 0.0))
		var dz : float = z_local - float(nom.get("z", 0.0))
		var drot : float = node.rotation.y - (n_rot + PI)
		# Wrap rotation into (-PI, PI] so saved deltas are minimal.
		drot = wrapf(drot, -PI, PI)
		var sc : Vector3 = node.scale
		# #macro-sink corruption guard: if this machine has fallen through the
		# world (physics sink) its absolute local delta is absurd — this is the
		# line_3a dy≈-40 km bug, which compounded every save. Refuse to record
		# it: skip the machine, do NOT roll the accumulator, leave the clean
		# seed pose for it. Uses the same threshold the load path filters on.
		var LMScript = preload("res://src/autoload/LineMacroStore.gd")
		if not LMScript.delta_sane(dx, dy, dz, drot):
			push_warning("[BuildMode] macro '%s' index %d pose implausible (dx=%.1f dy=%.1f dz=%.1f) — skipped, not saved" % [macro_id, i, dx, dy, dz])
			continue
		# Quick "is this machine actually moved?" check — within 1cm / 1°
		# of the upstream-inherited drift means no explicit override here.
		var explicit_dx : float = dx - acc.x
		var explicit_dy : float = dy - acc.y
		var explicit_dz : float = dz - acc.z
		var explicit_drot : float = wrapf(drot - acc_rot, -PI, PI)
		var pose_moved : bool = absf(explicit_dx) > 0.01 \
			or absf(explicit_dy) > 0.01 \
			or absf(explicit_dz) > 0.01 \
			or absf(explicit_drot) > 0.017
		var scale_changed : bool = not (
			is_equal_approx(sc.x, acc_scale.x)
			and is_equal_approx(sc.y, acc_scale.y)
			and is_equal_approx(sc.z, acc_scale.z))
		if pose_moved or scale_changed:
			deltas[i] = {
				"dx":     explicit_dx,
				"dy":     explicit_dy,
				"dz":     explicit_dz,
				"drot_y": explicit_drot,
				"scale":  [sc.x, sc.y, sc.z],
			}
			# Roll the accumulator forward — downstream-unmoved siblings
			# inherit this new drift implicitly (sparse storage), per the
			# operator's chain-style rule.
			acc.x = dx; acc.y = dy; acc.z = dz
			acc_rot = drot
			acc_scale = sc
	if deltas.is_empty():
		if _status:
			_status.text = "No edits detected for %s — nothing to save." % macro_id.to_upper()
		return 0
	var ok : bool = LineMacroStore.save_overrides(macro_id, deltas, p_seed.size())
	if ok and _status:
		_status.text = "Saved %d overrides for %s → user://macros/%s.json" % [
			deltas.size(), macro_id.to_upper(), macro_id]
	return deltas.size() if ok else 0

## Convenience wrapper called from the HUD "Reset to Default Macro" button.
func reset_macro_overrides(macro_id: String) -> void:
	LineMacroStore.reset(macro_id)
	if _status:
		_status.text = "Reset %s — next placement uses the const seed." % macro_id.to_upper()

## EDIT mode SHIFT+S shortcut: look at the currently selected machine, read
## its `macro_id` meta, and save back the whole macro it belongs to.
## Bake the selected machine's current (size × scale) into the catalog as
## the persistent base size for its placeable_id, then reset the live
## instance's scale to 1 and rebuild its mesh at the new size. Triggered by
## pressing B in edit mode while a machine is selected — the in-sim
## 3D-model editor's "commit" key. The catalog override is written to
## user://placeable_size_overrides.json and applies to every future
## placement of this id (current world + new worlds).
func _bake_selected_size_to_catalog() -> void:
	if _edit_selected == null or not is_instance_valid(_edit_selected):
		if _status:
			_status.text = "Select a machine first, then press B to bake size."
		return
	var pid : String = String(_edit_selected.get_meta("placeable_id", ""))
	if pid == "":
		if _status:
			_status.text = "Selected node has no placeable_id — nothing to bake."
		return
	var item := PlaceableCatalog.get_item(pid)
	if item.is_empty() or not item.has("size"):
		if _status:
			_status.text = "Catalog entry for '%s' has no size — cannot bake." % pid
		return
	# Current effective size = catalog (possibly already overridden) × live scale.
	var base : Vector3 = item["size"]
	var sc : Vector3 = _edit_selected.scale
	var new_size : Vector3 = Vector3(base.x * sc.x, base.y * sc.y, base.z * sc.z)
	# Persist the new base size — survives reload and applies to new worlds.
	var stored : Vector3 = PlaceableCatalog.set_size_override(pid, new_size)
	# Reset the live instance to identity scale + rebuild its procedural Model
	# so the visible mesh swaps to the new base size (and the save's scale
	# round-trips as 1, preventing double-scaling on reload).
	_edit_selected.scale = Vector3.ONE
	var rebuilt : bool = PlaceableCatalog.rebuild_in_place(_edit_selected)
	if _status:
		if rebuilt:
			_status.text = "Baked %s → %.2f × %.2f × %.2f m  (saved to user://placeable_size_overrides.json)" % [
				pid, stored.x, stored.y, stored.z]
		else:
			# Override is still persisted for future placements; live instance
			# couldn't be rebuilt in-place (bespoke construction path). Operator
			# can delete + re-place this instance to see the new size.
			_status.text = "Baked %s → %.2f × %.2f × %.2f m  (re-place this one to refresh — used bespoke build path)" % [
				pid, stored.x, stored.y, stored.z]
	# Refresh the dimension readout to show the new base + identity scale.
	_update_edit_status()

func _save_macro_for_selected() -> void:
	if _edit_selected == null or not is_instance_valid(_edit_selected):
		if _status:
			_status.text = "Select a macro-placed machine first, then Shift+S to save back."
		return
	if not _edit_selected.has_meta("macro_id"):
		if _status:
			_status.text = "Selected machine is not part of a macro — nothing to save."
		return
	# Persist any pending jog changes so the world poses match the save target.
	if _edit_dirty:
		_save_layout()
		_edit_dirty = false
	var mid : String = String(_edit_selected.get_meta("macro_id"))
	save_macro_overrides(mid)

## Read the variable belt's `auto_legs` meta — a list of {pos, h} entries — and
## spawn a pole_single at each one as a regular placed_object. The operator can
## delete individual ones afterward, or replace them with a different pole type.
func _spawn_auto_legs(vb: Node3D) -> void:
	if vb == null or not vb.has_meta("auto_legs"):
		return
	var legs : Array = vb.get_meta("auto_legs")
	for entry in legs:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var pos : Vector3 = entry.get("pos", Vector3.ZERO)
		var h   : float   = float(entry.get("h", POLE_DEFAULT_H))
		var pole := PlaceableCatalog.build_pole("pole_single", h, false)
		if pole != null:
			_placed_root.add_child(pole)
			pole.global_position = pos

## Two-point placement helpers (variable_belt): a thin cyan cylinder drawn from
## the captured start to the current ghost cursor so the operator sees the span
## while picking the end point.
func _ensure_two_point_preview() -> void:
	if _two_point_preview != null and is_instance_valid(_two_point_preview):
		return
	_two_point_preview = MeshInstance3D.new()
	_two_point_preview.name = "TwoPointPreview"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.05
	cm.bottom_radius = 0.05
	cm.height = 1.0
	cm.radial_segments = 8
	_two_point_preview.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.80, 1.00, 0.65)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.emission_enabled = true
	mat.emission = Color(0.20, 0.60, 0.95)
	mat.emission_energy_multiplier = 0.6
	_two_point_preview.material_override = mat
	add_child(_two_point_preview)

func _clear_two_point_preview() -> void:
	if _two_point_preview != null and is_instance_valid(_two_point_preview):
		_two_point_preview.queue_free()
	_two_point_preview = null

func _update_two_point_preview(end_pos: Vector3) -> void:
	if _two_point_preview == null:
		return
	var diff := end_pos - _two_point_start
	var len_ := diff.length()
	if len_ < 0.05:
		_two_point_preview.visible = false
		return
	_two_point_preview.visible = true
	(_two_point_preview.mesh as CylinderMesh).height = len_
	var up : Vector3 = diff / len_
	var ref : Vector3 = Vector3.RIGHT if absf(up.dot(Vector3.RIGHT)) < 0.95 else Vector3.FORWARD
	var x_axis : Vector3 = up.cross(ref).normalized()
	var z_axis : Vector3 = x_axis.cross(up).normalized()
	_two_point_preview.global_transform = Transform3D(Basis(x_axis, up, z_axis),
		(_two_point_start + end_pos) * 0.5)

## Stamps a placed bale with a unique code + prints its label (origin + barcode).
func _finalize_bale(node: Node3D, saved_code: String = "") -> void:
	if not node.has_meta("material_origin"):
		return
	var id := String(node.get_meta("material_origin"))
	var code := saved_code
	if code.is_empty():
		var nm := String(BaleDefs.get_origin(id).get("name", "BALE"))
		code = "%s-%05d" % [nm.substr(0, 3).to_upper(), randi() % 100000]
	node.set_meta("bale_code", code)
	PlaceableCatalog.add_bale_label(node, id, code)

## Records the build height. If the object is raised off the floor, FIRST extend the
## machine's own support legs down to the ground (no separate poles); only if it has
## no taggable legs do we fall back to the old bolt-on support frame.
func _finalize_placed(node: Node3D, id: String, height: float) -> void:
	node.set_meta("height_offset", height)
	if height <= 0.001:
		return
	if PlaceableCatalog.extend_machine_legs(node, height) > 0:
		return   # machine now stands on its own (lengthened) legs — no added poles
	var item := PlaceableCatalog.get_item(id)
	var footprint: Vector3 = item.get("size", Vector3(1.0, 1.0, 1.0))
	var frame := PlaceableCatalog.build_support_frame(footprint, height)
	if frame:
		node.add_child(frame)   # child → rotates, persists and deletes with the object

func _delete_pointed() -> void:
	var hit := _raycast()
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider == null:
		return
	# Walk up to the nearest ancestor flagged "placed_object" — REGARDLESS of which
	# root it hangs under. The old code required a DIRECT child of _placed_root, so
	# anything loaded from disk on reopen, nested (support frames/labels), or spawned
	# by the world (the Line 3C machines) could never be deleted. Matching the group
	# directly fixes "can't delete anything placed after closing/reopening".
	var target: Node = collider
	while target != null and not target.is_in_group("placed_object"):
		target = target.get_parent()
	if target == null:
		return
	# Capture the placeable id BEFORE we free the node — the gate decision below
	# needs to know whether this was a flow-relevant machine or an observer.
	var deleted_id : String = String(target.get_meta("placeable_id", "")) if target.has_meta("placeable_id") else ""
	# If it owns a carved opening, restore that part of the wall first.
	if target.has_meta("opening_id") and wall_openings:
		wall_openings.remove_opening(String(target.get_meta("opening_id")))
		BaseVehicle.invalidate_route_grid()   # the walled-up gap is solid again
	# Drop from the flow group now so the rebuild below doesn't re-include it
	# (queue_free only frees at end of frame).
	target.remove_from_group("placed_object")
	var par := target.get_parent()
	if par != null:
		par.remove_child(target)
	target.queue_free()
	_save_layout()
	# #218 — Only rebuild if the deleted node actually participated in the
	# material-flow graph. Observer fixtures (HMI panels, doors, decorations)
	# don't change topology and must not trigger the costly PLC re-stagger.
	if line_flow and _is_flow_relevant(deleted_id):
		line_flow.rebuild()
	else:
		# Observer-only removal. Skip the rebuild that would restart the whole
		# line; let panel binders re-resolve via a signal if LineFlow provides one.
		if line_flow and line_flow.has_signal("observer_placed"):
			line_flow.emit_signal("observer_placed", deleted_id)

# =============================================================================
# JOG / EDIT MODE — select a placed machine and nudge it into place.
# =============================================================================
func _enter_edit_mode() -> void:
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = false
	_state = State.EDIT
	_status.visible = true
	_crosshair.visible = true
	if _dim_readout != null:
		_dim_readout.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_edit_selected = null
	_clear_edit_highlight()
	_update_edit_status()

func _exit_edit_mode() -> void:
	_edit_deselect()
	# Auto-save every macro the operator touched. Previously the K → exit flow
	# silently discarded jog changes unless the operator remembered to press
	# Shift+S on every machine. That trap cost a whole rework session of the
	# sorting line — operator changed scales + positions, exited, reloaded,
	# everything reverted. Persisting on exit removes the trap.
	_auto_save_all_touched_macros()
	_enter_inactive()

## Walk every placed_object child carrying a `macro_id` meta, collect the
## distinct macro ids, and call save_macro_overrides() on each one. Cheap (a
## handful of macros at most, file I/O only on actual diffs internally).
## Called from _exit_edit_mode so a K-mode session round-trips through disk
## without the operator having to remember Shift+S.
func _auto_save_all_touched_macros() -> void:
	if _placed_root == null or not is_instance_valid(_placed_root):
		return
	var ids : Dictionary = {}
	for child in _placed_root.get_children():
		if child is Node3D and child.has_meta("macro_id"):
			ids[String(child.get_meta("macro_id"))] = true
	if ids.is_empty():
		return
	var total : int = 0
	for mid in ids.keys():
		total += save_macro_overrides(String(mid))
	if _status:
		_status.text = "Auto-saved %d macro override(s) across %d macro(s)." % [total, ids.size()]
	print("[BuildMode] Auto-saved %d macro override(s) across %d macro(s) on K-mode exit" \
		% [total, ids.size()])

## Raycast from the crosshair and climb to the nearest "placed_object" ancestor.
func _pointed_placed_object() -> Node:
	var hit := _raycast()
	if hit.is_empty():
		return null
	var t = hit.get("collider")
	while t != null and not t.is_in_group("placed_object"):
		t = t.get_parent()
	return t

func _edit_select_pointed() -> void:
	var obj := _pointed_placed_object()
	if obj == null:
		return
	# Switching selection saves the previous one's changes.
	_edit_deselect()
	_edit_selected = obj as Node3D
	_add_edit_highlight(_edit_selected)
	_update_edit_status()

func _edit_deselect() -> void:
	if _edit_dirty:
		_save_layout()
		# #218 — Jogging an observer fixture (HMI panel, sign, decoration) only
		# updates its transform; the material-flow graph is unchanged. Gate the
		# rebuild so a tiny nudge to a panel doesn't restart the whole line.
		var jogged_id : String = ""
		if _edit_selected != null and is_instance_valid(_edit_selected) \
				and _edit_selected.has_meta("placeable_id"):
			jogged_id = String(_edit_selected.get_meta("placeable_id"))
		if line_flow and _is_flow_relevant(jogged_id):
			line_flow.rebuild()
		else:
			# Observer-only jog. Skip the rebuild that would restart the whole
			# line; let panel binders re-resolve via a signal if LineFlow provides one.
			if line_flow and line_flow.has_signal("observer_placed"):
				line_flow.emit_signal("observer_placed", jogged_id)
		_edit_dirty = false
	_clear_edit_highlight()
	_edit_selected = null
	_update_edit_status()

func _edit_delete_selected() -> void:
	if _edit_selected == null:
		return
	var target := _edit_selected
	_clear_edit_highlight()
	_edit_selected = null
	# Capture the placeable id BEFORE we free the node — the gate decision below
	# needs to know whether this was a flow-relevant machine or an observer.
	var deleted_id : String = String(target.get_meta("placeable_id", "")) if target.has_meta("placeable_id") else ""
	if target.has_meta("opening_id") and wall_openings:
		wall_openings.remove_opening(String(target.get_meta("opening_id")))
		BaseVehicle.invalidate_route_grid()   # the walled-up gap is solid again
	target.remove_from_group("placed_object")
	var par := target.get_parent()
	if par != null: par.remove_child(target)
	target.queue_free()
	_save_layout()
	# #218 — Only rebuild if the deleted node actually participated in the
	# material-flow graph. Observer fixtures don't change topology and must
	# not trigger the costly PLC re-stagger.
	if line_flow and _is_flow_relevant(deleted_id):
		line_flow.rebuild()
	else:
		# Observer-only K-mode deletion. Skip the rebuild; let panel binders
		# re-resolve via a signal if LineFlow provides one.
		if line_flow and line_flow.has_signal("observer_placed"):
			line_flow.emit_signal("observer_placed", deleted_id)
	_update_edit_status()

func _add_edit_highlight(obj: Node3D) -> void:
	var item := PlaceableCatalog.get_item(String(obj.get_meta("placeable_id", "")))
	var sz : Vector3 = item.get("size", Vector3.ONE) if not item.is_empty() else Vector3.ONE
	var hl := MeshInstance3D.new()
	hl.name = "EditHighlight"
	var bm := BoxMesh.new(); bm.size = sz * 1.06
	hl.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.2, 0.9, 1.0, 0.22)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	hl.material_override = m
	hl.position = Vector3(0.0, sz.y * 0.5, 0.0)
	obj.add_child(hl)
	_edit_highlight = hl

func _clear_edit_highlight() -> void:
	if _edit_highlight != null and is_instance_valid(_edit_highlight):
		_edit_highlight.queue_free()
	_edit_highlight = null

## Continuous jog while a machine is selected (polled, so holding a key keeps
## nudging). Arrows = X/Z, R/F = up/down, Q/E = yaw, +/- = uniform scale,
## Shift = fine step.
func _edit_process(delta: float) -> void:
	if _edit_selected == null or not is_instance_valid(_edit_selected):
		return
	var fine := Input.is_key_pressed(KEY_SHIFT)
	var mv : float = (JOG_MOVE_FINE if fine else JOG_MOVE_COARSE) * delta
	var rv : float = (JOG_ROT_FINE if fine else JOG_ROT_COARSE) * delta
	var sv : float = (JOG_SCALE_FINE if fine else JOG_SCALE_COARSE) * delta
	var moved := false
	var dx := Input.get_action_strength("ui_right") - Input.get_action_strength("ui_left")
	var dz := Input.get_action_strength("ui_down")  - Input.get_action_strength("ui_up")
	if dx != 0.0 or dz != 0.0:
		_edit_selected.global_position += Vector3(dx * mv, 0.0, dz * mv)
		moved = true
	var dy := Input.get_action_strength("build_raise") - Input.get_action_strength("build_lower")
	if dy != 0.0:
		_edit_selected.global_position.y += dy * mv
		moved = true
	var dr := Input.get_action_strength("build_rotate_cw") - Input.get_action_strength("build_rotate_ccw")
	if dr != 0.0:
		_edit_selected.rotation.y += dr * rv
		moved = true
	# UNIFORM scale: +/- (existing behaviour)
	var ds := 0.0
	if Input.is_key_pressed(KEY_EQUAL) or Input.is_key_pressed(KEY_KP_ADD): ds += 1.0
	if Input.is_key_pressed(KEY_MINUS) or Input.is_key_pressed(KEY_KP_SUBTRACT): ds -= 1.0
	if ds != 0.0:
		var u : float = clampf(_edit_selected.scale.x + ds * sv, 0.2, 5.0)
		_edit_selected.scale = Vector3(u, u, u)
		moved = true
	# PER-AXIS scale: numpad-style cluster on the right of the keyboard so it
	# doesn't conflict with movement (WASD/arrows). X uses 7/4, Y uses 8/5, Z uses 9/6
	# (top row of three = grow, bottom row = shrink — same column per axis).
	var dsx := 0.0
	if Input.is_key_pressed(KEY_7) or Input.is_key_pressed(KEY_KP_7): dsx += 1.0
	if Input.is_key_pressed(KEY_4) or Input.is_key_pressed(KEY_KP_4): dsx -= 1.0
	var dsy := 0.0
	if Input.is_key_pressed(KEY_8) or Input.is_key_pressed(KEY_KP_8): dsy += 1.0
	if Input.is_key_pressed(KEY_5) or Input.is_key_pressed(KEY_KP_5): dsy -= 1.0
	var dsz := 0.0
	if Input.is_key_pressed(KEY_9) or Input.is_key_pressed(KEY_KP_9): dsz += 1.0
	if Input.is_key_pressed(KEY_6) or Input.is_key_pressed(KEY_KP_6): dsz -= 1.0
	if dsx != 0.0 or dsy != 0.0 or dsz != 0.0:
		var sx : float = clampf(_edit_selected.scale.x + dsx * sv, 0.2, 5.0)
		var sy : float = clampf(_edit_selected.scale.y + dsy * sv, 0.2, 5.0)
		var sz : float = clampf(_edit_selected.scale.z + dsz * sv, 0.2, 5.0)
		_edit_selected.scale = Vector3(sx, sy, sz)
		moved = true
		ds = 1.0   # signal "scale changed" so legs re-extend below
	# #196 — PER-AXIS TILT: pitch (X-rot) on 1/2, roll (Z-rot) on 3/0. Both
	# top-row digits and numpad equivalents are honoured. Yaw stays on the
	# existing build_rotate_cw/ccw bindings (operator preference: rotation
	# stays mapped to whatever they bound for yaw, only pitch + roll added).
	var dtx := 0.0
	if Input.is_key_pressed(KEY_1) or Input.is_key_pressed(KEY_KP_1): dtx += 1.0
	if Input.is_key_pressed(KEY_2) or Input.is_key_pressed(KEY_KP_2): dtx -= 1.0
	var dtz := 0.0
	if Input.is_key_pressed(KEY_3) or Input.is_key_pressed(KEY_KP_3): dtz += 1.0
	if Input.is_key_pressed(KEY_0) or Input.is_key_pressed(KEY_KP_0): dtz -= 1.0
	if dtx != 0.0 or dtz != 0.0:
		_edit_selected.rotation.x = clampf(_edit_selected.rotation.x + dtx * rv,
			-PI * 0.5, PI * 0.5)
		_edit_selected.rotation.z = clampf(_edit_selected.rotation.z + dtz * rv,
			-PI * 0.5, PI * 0.5)
		moved = true
	if moved:
		if dy != 0.0 or ds != 0.0:
			# Height or scale changed — keep this machine's own legs planted on the floor.
			PlaceableCatalog.extend_machine_legs(_edit_selected, _edit_selected.global_position.y - FLOOR_Y)
		_edit_dirty = true
		_update_edit_status()

func _update_edit_status() -> void:
	if _state != State.EDIT:
		return
	if _edit_selected == null or not is_instance_valid(_edit_selected):
		_status.text = "EDIT MODE   ·   aim at a machine + [LMB] to select   ·   [K]/[RMB] exit"
		if _dim_readout != null:
			_dim_readout.text = ""
		return
	var nm := String(PlaceableCatalog.get_item(String(_edit_selected.get_meta("placeable_id",""))).get("name", _edit_selected.name))
	var p := _edit_selected.global_position
	var sc_v : Vector3 = _edit_selected.scale
	var sc_str : String = ("scale %.2f" % sc_v.x) if (is_equal_approx(sc_v.x, sc_v.y) and is_equal_approx(sc_v.y, sc_v.z)) \
		else ("scale (%.2f, %.2f, %.2f)" % [sc_v.x, sc_v.y, sc_v.z])
	_status.text = "EDIT: %s   pos(%.2f, %.2f, %.2f)  rot %.0f°  %s\narrows=move  R/F=up/down  Q/E=rotate  +/-=uniform scale  7/4=X  8/5=Y  9/6=Z  Shift=fine  [B]bake size→catalog  [X]delete  [K/RMB]exit" % [
		nm, p.x, p.y, p.z, rad_to_deg(_edit_selected.rotation.y), sc_str]
	# Bottom-right readout: catalog base size, current effective WxHxD (size *
	# scale) in metres, and the per-axis scale factor so a jog session has a
	# clear "what am I tweaking, and how far from the original" reference.
	if _dim_readout != null:
		var pid : String = String(_edit_selected.get_meta("placeable_id", ""))
		var item : Dictionary = PlaceableCatalog.get_item(pid)
		if not item.is_empty() and item.has("size"):
			var base : Vector3 = item["size"]
			var cur : Vector3 = Vector3(base.x * sc_v.x, base.y * sc_v.y, base.z * sc_v.z)
			_dim_readout.text = "DIMENSIONS  (W × H × D, m)\n%.2f × %.2f × %.2f\nbase  %.2f × %.2f × %.2f\nscale  X %.2f   Y %.2f   Z %.2f" % [
				cur.x, cur.y, cur.z,
				base.x, base.y, base.z,
				sc_v.x, sc_v.y, sc_v.z]
		else:
			_dim_readout.text = "scale  X %.2f   Y %.2f   Z %.2f" % [sc_v.x, sc_v.y, sc_v.z]

## The camera build mode AIMS with — always the player's, never merely the one
## that happens to be `current`.
##
## Operator report 2026-07-20 (NPC bench): "when I spawn a bale clamp / a film
## pile it always lands in the exact centre of the middle shredder". Root cause:
## _raycast() built its ray from `get_viewport().get_camera_3d()` along that
## camera's FORWARD AXIS — the mouse is never involved. NpcTaskBench's O key
## (_cycle_observer) makes a STATIC ObserverCam current, so with observer mode on
## the ray is one fixed line in space and EVERY placeable of EVERY kind lands on
## the single point that line first hits. Pre-placed bench bales looked fine
## because the rig places them directly, not through build mode.
##
## Ruled out first, by measurement, not by argument: add_child-then-position
## stranding RigidBody3D children at the origin — src/tests/test_spawn_transform.gd
## shows both orderings land within 0.8 m of the aim point.
func _aim_camera() -> Camera3D:
	if player_body != null and is_instance_valid(player_body):
		var pc := player_body.find_child("Camera3D", true, false) as Camera3D
		if pc != null:
			return pc
	return get_viewport().get_camera_3d()

# Camera-forward ray against the world (floor / building / placed objects),
# excluding the player capsule and the (collision-less) ghost.
func _raycast() -> Dictionary:
	var cam := _aim_camera()
	if cam == null:
		return {}
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * RAY_LEN
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	if player_body:
		q.exclude = [player_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

# =============================================================================
# 4-POINT SURFACE TOOL
# =============================================================================
func _add_surface_point() -> void:
	var hit := _raycast()
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	_surf_points.append(pos)
	_update_surface_markers()
	var n := _surf_points.size()
	if n >= 4:
		_show_surface_popup()
	else:
		var nexts := ["② top-left", "③ top-right", "④ bottom-right"]
		_status.text = "SURFACE  ·  point %d/4 set  ·  next: %s   ·   [RMB] cancel" % [n, nexts[n - 1]]

func _update_surface_markers() -> void:
	if _surf_markers == null or not is_instance_valid(_surf_markers):
		_surf_markers = Node3D.new()
		_surf_markers.name = "SurfaceMarkers"
		add_child(_surf_markers)
	for c in _surf_markers.get_children():
		c.queue_free()
	for i in _surf_points.size():
		var m := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.08
		sph.height = 0.16
		m.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.2)
		m.material_override = mat
		_surf_markers.add_child(m)
		m.global_position = _surf_points[i]

func _clear_surface() -> void:
	if _surf_markers and is_instance_valid(_surf_markers):
		_surf_markers.queue_free()
	_surf_markers = null
	_surf_points.clear()

func _show_surface_popup() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_popup_name.text = ""
	_popup_type.selected = 0
	_popup.visible = true
	_status.text = "SURFACE  ·  choose what it is, name it, press Create"

func _confirm_surface() -> void:
	if _surf_points.size() < 4:
		_cancel_surface()
		return
	var type_idx := _popup_type.selected
	var type_str := SURF_TYPES[clampi(type_idx, 0, SURF_TYPES.size() - 1)]
	var label := _popup_name.text.strip_edges()
	var pts := _surf_points.duplicate()
	_popup.visible = false
	_make_surface(pts, type_str, label)
	_save_layout()
	_enter_browsing()

func _cancel_surface() -> void:
	_popup.visible = false
	_enter_browsing()

## Builds a surface object from 4 world-space corner points, positions it flush
## with the clicked plane, and (for doors/windows) carves a matching opening.
func _make_surface(points: Array, type_str: String, label: String) -> Node3D:
	if points.size() < 4:
		return null
	var geo := _surface_geometry(points)
	var center: Vector3 = geo["center"]
	var surf_basis: Basis = geo["basis"]
	var width: float    = geo["width"]
	var height: float   = geo["height"]
	var x_axis: Vector3 = geo["x_axis"]
	var z_axis: Vector3 = geo["z_axis"]

	var node: Node3D = null
	var cuts := false
	match type_str:
		"door":
			node = PlaceableCatalog.build_door(width, height, 0.12, label)
			cuts = true
		"gate":
			# Real industrial sectional/roller gate — dark blue leaf that rolls UP
			# into a drum on top. NOT the hinge mechanism. Driven by a wall-mounted
			# 3-button push-button station (UP / STOP / DOWN) built alongside it.
			node = PlaceableCatalog.build_gate(width, height, label)
			cuts = true
		"window":
			# Aluminium-framed industrial window — frame + central mullion + two
			# blue-tinted glass bays. Reads like real plant glazing, not a floating
			# tinted slab. Carves a matching opening in the wall.
			node = PlaceableCatalog.build_window(width, height, label)
			cuts = true
		"sign":
			node = PlaceableCatalog.build_panel(width, height, 0.03, Color(0.92, 0.92, 0.90), label, false, false)
		_:
			node = PlaceableCatalog.build_panel(width, height, 0.10, Color(0.70, 0.70, 0.72), label, false, true)
	if node == null:
		return null

	_placed_root.add_child(node)
	var place_center := center
	if type_str == "sign":
		place_center = center + z_axis * 0.03   # sit proud of the wall
	node.global_transform = Transform3D(surf_basis, place_center)

	var pdata: Array = []
	for p in points:
		pdata.append([(p as Vector3).x, (p as Vector3).y, (p as Vector3).z])
	node.set_meta("surface_data", {"type": type_str, "label": label, "p": pdata})

	if cuts and wall_openings:
		_opening_seq += 1
		var oid := "op_%d" % _opening_seq
		var rot_y := atan2(x_axis.z, x_axis.x)
		# Carve opening = panel size EXACTLY (no extra) so a closed door fully
		# covers it: no light leak, no gap for the player to walk through. Earlier
		# this added +0.15 m of slack on every dim; that left a 7.5 cm hole all
		# round so daylight bled through and the capsule could slip past the leaf.
		# The clamp still bounds first-person misclicks (4 points far apart =
		# would otherwise produce a 50 m box that the carver chokes on).
		var ow : float = clampf(width,  0.5, 6.0)
		var oh : float = clampf(height, 0.5, 8.0)
		if wall_openings.add_opening(oid, center, Vector3(ow, oh, 2.0), rot_y):
			node.set_meta("opening_id", oid)
		else:
			push_warning("[BuildMode] %s surface carve found no wall at %s — the panel is placed but stands in front of an intact wall"
				% [type_str, str(center)])
		# See _carve_structure_opening's note: the shared vehicle route grid
		# samples colliders once per world and would otherwise ignore this cut
		# for the rest of the session.
		BaseVehicle.invalidate_route_grid()
	return node

## #104 — robust against any click order. The UI asks for BL → TL → TR → BR
## but raycasts on uneven floors or a slightly-misordered click set previously
## made the carve box's y-axis non-vertical AND occasionally swapped the X-Z
## normal direction. With y_axis HARD-LOCKED to world UP (gates / doors /
## windows are always vertical wall surfaces) and the bottom edge picked from
## the two LOWEST points by Y, the carve box always points the right way
## regardless of click order. Side effect: the cutout now succeeds even when
## the user clicks the 4 corners in any order.
func _surface_geometry(points: Array) -> Dictionary:
	# Sort the 4 points by Y so the lowest pair is the bottom edge and the
	# highest pair is the top edge — robust to any click order.
	var sorted_pts := points.duplicate()
	sorted_pts.sort_custom(func(a, b): return (a as Vector3).y < (b as Vector3).y)
	var p_b0 : Vector3 = sorted_pts[0]
	var p_b1 : Vector3 = sorted_pts[1]
	var p_t0 : Vector3 = sorted_pts[2]
	var p_t1 : Vector3 = sorted_pts[3]
	var bottom_mid : Vector3 = (p_b0 + p_b1) * 0.5
	var top_mid    : Vector3 = (p_t0 + p_t1) * 0.5
	var center : Vector3 = (bottom_mid + top_mid) * 0.5
	# #106 — height is the PURELY VERTICAL distance (not 3D length). If the user
	# clicks the 4 corners with even a tiny floor-level mismatch, 3D length adds
	# the X/Z slop on top of the actual vertical height — that made the window's
	# glass pane and frame strips taller than the carved opening, sticking out
	# above and below the wall.
	var height : float = maxf(absf(top_mid.y - bottom_mid.y), 0.1)
	# Horizontal x_axis from the bottom edge, projected onto the XZ plane so
	# even an uneven raycast pair gives a horizontal direction. Direction is
	# whatever sorting put first — doesn't matter for carve symmetry.
	var bottom_dir : Vector3 = p_b1 - p_b0
	bottom_dir.y = 0.0
	if bottom_dir.length() < 0.001:
		bottom_dir = Vector3.RIGHT
	var x_axis : Vector3 = bottom_dir.normalized()
	var y_axis : Vector3 = Vector3.UP                # vertical wall surfaces only
	var z_axis : Vector3 = x_axis.cross(y_axis).normalized()
	# Width is the horizontal extent — use the bottom edge's projected length
	# (height already handled by the vertical span above).
	var width : float = maxf(Vector2(bottom_dir.x, bottom_dir.z).length(), 0.1)
	# Set columns explicitly (Basis.x/.y/.z ARE the columns) to avoid the
	# constructor's column-vs-row ambiguity. local +X→x_axis, +Y→up, +Z→normal.
	var surf_basis := Basis()
	surf_basis.x = x_axis
	surf_basis.y = y_axis
	surf_basis.z = z_axis
	surf_basis = surf_basis.orthonormalized()
	return {
		"center": center, "basis": surf_basis, "width": width, "height": height,
		"x_axis": x_axis, "z_axis": z_axis,
	}

# =============================================================================
# PERSISTENCE
# =============================================================================
func _save_layout() -> void:
	var arr: Array = [{"layout_version": LAYOUT_VERSION}]   # #29 marker — see load_layout
	# STRUCTURE (walls + surface doors/gates/windows) goes to the SHARED layer
	# (WorldLayout) so every save inherits it; MACHINES stay per-save.
	var shared : Array = []
	for child in _placed_root.get_children():
		if child.has_meta("surface_data"):
			# 4-point surfaces persist as their corner points + type + label.
			var sd: Dictionary = child.get_meta("surface_data")
			var t : String = String(sd.get("type", "door"))
			var entry_s := {
				"kind":  "surface",
				"type":  t,
				"label": sd.get("label", ""),
				"p":     sd.get("p", []),
			}
			# Doors / gates / windows belong to the SITE (shared). Signs / plain
			# panels are decorations placed per-save (still flow through `arr`).
			if t == "door" or t == "gate" or t == "window":
				shared.append(entry_s)
			else:
				arr.append(entry_s)
		elif child.has_meta("placeable_id"):
			var h := 0.0
			if child.has_meta("height_offset"):
				h = float(child.get_meta("height_offset"))
			var entry := {
				"id":    child.get_meta("placeable_id"),
				"x":     child.global_position.x,
				"y":     child.global_position.y,
				"z":     child.global_position.z,
				"rot_y": child.rotation.y,
				"h":     h,
			}
			# #196 — round-trip pitch (X) + roll (Z) only when non-zero, so legacy
			# saves stay backward-compatible. Tilt is applied by the K-menu jog
			# (1/2 pitch, 3/0 roll); without these keys the values stay at 0.0.
			if not is_zero_approx(child.rotation.x):
				entry["rot_x"] = child.rotation.x
			if not is_zero_approx(child.rotation.z):
				entry["rot_z"] = child.rotation.z
			# Persist EDIT-mode scale. If uniform → write as a single float (back-compat
			# with older saves). If per-axis (X/Y/Z differ) → write as [sx, sy, sz].
			var sc_v : Vector3 = child.scale
			var uniform_sc : bool = is_equal_approx(sc_v.x, sc_v.y) and is_equal_approx(sc_v.y, sc_v.z)
			if uniform_sc:
				if not is_equal_approx(sc_v.x, 1.0):
					entry["scale"] = sc_v.x
			else:
				entry["scale"] = [sc_v.x, sc_v.y, sc_v.z]
			if child.has_meta("bale_code"):
				entry["code"] = String(child.get_meta("bale_code"))
			# phys-04 — lump_cart fill survives save/load. Persist kg + remaining
			# cool-down seconds so a full 90 kg cart doesn't reload empty (mass
			# conservation) and a hot cart stays hot across the save boundary.
			# Written only when loaded; absence on load means an empty cart.
			if child.is_in_group("lump_cart") and "lumps_kg" in child \
					and float(child.get("lumps_kg")) > 0.001:
				entry["lumps_kg"] = float(child.get("lumps_kg"))
				entry["cool_left_s"] = float(child.call("cool_remaining_s"))
			# #MSB — round-trip macro membership so a reopened save can still
			# invoke save-back on previously placed macro members.
			if child.has_meta("macro_id"):
				entry["macro_id"] = String(child.get_meta("macro_id"))
			if child.has_meta("macro_index"):
				entry["macro_index"] = int(child.get_meta("macro_index"))
			if child.has_meta("macro_anchor"):
				var anc : Dictionary = child.get_meta("macro_anchor")
				var anc_start : Vector3 = anc.get("start", Vector3.ZERO)
				entry["macro_anchor"] = {
					"sx": anc_start.x, "sy": anc_start.y, "sz": anc_start.z,
					"rot_y": float(anc.get("rot_y", 0.0)),
				}
			# Custom-height support poles: stash the pole_height meta so reload
			# rebuilds at the actual standing height (smart-snap or auto-leg).
			if child.has_meta("pole_height"):
				entry["pole_h"] = float(child.get_meta("pole_height"))
			# Variable-length belts persist their two endpoints directly so reload
			# rebuilds them via build_variable_belt(start, end) at the correct
			# length, angle, and start/end height — not a generic placement.
			if String(child.get_meta("placeable_id")) == "variable_belt":
				if child.has_meta("vb_start"):
					var s : Vector3 = child.get_meta("vb_start")
					entry["sx"] = s.x; entry["sy"] = s.y; entry["sz"] = s.z
				if child.has_meta("vb_end"):
					var e : Vector3 = child.get_meta("vb_end")
					entry["ex"] = e.x; entry["ey"] = e.y; entry["ez"] = e.z
			# Walls persist their two endpoints so reload rebuilds the exact span.
			var pid_save := String(child.get_meta("placeable_id"))
			var is_wall := pid_save.begins_with("wall_")
			if child.has_meta("wall_start") and child.has_meta("wall_end"):
				var ws : Vector3 = child.get_meta("wall_start")
				var we : Vector3 = child.get_meta("wall_end")
				entry["sx"] = ws.x; entry["sy"] = ws.y; entry["sz"] = ws.z
				entry["ex"] = we.x; entry["ey"] = we.y; entry["ez"] = we.z
			# #72 — grating platforms persist their rectangle dimensions so reload
			# rebuilds at the exact W×L the operator dragged out, not the catalog
			# default. gp_size is set by build_grating_platform; absence means
			# legacy save → load falls back to build_node's default size.
			if pid_save == "grating_platform" and child.has_meta("gp_size"):
				var gp : Vector2 = child.get_meta("gp_size")
				entry["gw"] = gp.x
				entry["gl"] = gp.y
			# Walls go to the SHARED layer (site structure); other ids stay per-save.
			if is_wall:
				shared.append(entry)
			else:
				arr.append(entry)
	var f := FileAccess.open(layout_path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(arr, "\t"))
		f.close()
	# Push the SHARED structure list to WorldLayout and persist it so EVERY save
	# (including brand-new ones) inherits the building's walls / doors / gates / windows.
	#
	# ONLY when this instance actually loaded that structure. A BuildMode with
	# load_shared_structure = false (test benches, ExtruderGauntlet) never
	# instantiated the site's walls/doors, so `shared` is empty for reasons that
	# have nothing to do with the operator deleting anything — writing it back
	# would erase the real site structure for EVERY save. This is not
	# hypothetical: SaveCoordinator's 60 s autosave routes
	# save_game -> _save_layout -> WorldLayout.save(), so any booted bench would
	# have wiped it on a timer, unattended.
	if load_shared_structure:
		WorldLayout.structure_items = shared
		WorldLayout.save()

# Vehicles restored by the CURRENT load_layout() pass — one entry per vehicle,
# {node, id}. Rebuilt every load, consumed and cleared by
# _denest_loaded_vehicles(). Saves written before the placement clearance gate
# (BuildMode._vehicle_spawn_blocker) contain nested vehicle poses, and applying
# those poses verbatim re-creates the overlap that made hulls translate forever.
var _loaded_vehicles : Array[Dictionary] = []

# Retired placeable ids encountered by the CURRENT load_layout() pass, id -> count.
# Reported once at the end of the load (_report_retired_drops) and cleared.
var _retired_dropped : Dictionary = {}

## De-nest search geometry. Fixed step + fixed angle count = deterministic: the
## same save always yields the same corrected poses, so the regression harness
## and the operator's world stay reproducible. 1.5 m clears a bale-clamp
## footprint (1.6 × 3.6 m) in one or two rings; 8 rings reaches 12 m, past any
## plausible ladder cluster without walking a vehicle across the plant.
const DENEST_STEP_M : float = 1.5
const DENEST_RINGS : int = 8
const DENEST_ANGLES : int = 12

func load_layout() -> void:
	_loaded_vehicles.clear()
	_retired_dropped.clear()
	# Per-save data (machines, signs, plain panels — playthrough-specific items).
	# Falls through with an empty `data` array so a new save (no per-save file) still
	# loads the SHARED structure (walls / doors / gates / windows) below.
	var data : Array = []
	var path := layout_path
	var have_file := FileAccess.file_exists(path)
	if not have_file and allow_legacy_fallback and path != LEGACY_LAYOUT_PATH \
			and FileAccess.file_exists(LEGACY_LAYOUT_PATH):
		path = LEGACY_LAYOUT_PATH
		have_file = true
		print("[BuildMode] Per-save layout missing — migrating legacy %s" % LEGACY_LAYOUT_PATH)
	if have_file:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			var raw := f.get_as_text()
			f.close()
			# Guard against empty / malformed legacy files. The legacy layout file
			# from an early build was sometimes written as an empty placeholder,
			# which raises "Parse JSON failed. Error at line 0" — survivable, just
			# skip the migration and continue with the per-save layout (often the
			# new save is also empty, so this just means starting clean).
			var parsed : Variant = null
			if raw.strip_edges() != "":
				parsed = JSON.parse_string(raw)
				if parsed == null:
					push_warning("[BuildMode] Could not parse %s — skipping migration" % path)
			if parsed is Array:
				# #29 — entries without the current version marker are from before this patch.
				var versioned := false
				for entry in (parsed as Array):
					if entry is Dictionary and int((entry as Dictionary).get("layout_version", 0)) == LAYOUT_VERSION:
						versioned = true
						break
				if versioned:
					data = parsed as Array
				else:
					print("[BuildMode] Ignoring obsolete saved layout (pre-v%d) — clean start (#29)." % LAYOUT_VERSION)
	var count := 0
	for entry in data:
		if _apply_layout_entry(entry):
			count += 1
	# Always overlay the SHARED building structure (walls + doors + gates + windows)
	# on top of per-save items, so a brand-new save still gets the factory's interior.
	# Test benches (ExtruderGauntlet) opt out: they have no building shell, so site
	# doors/gates would float in the void hundreds of metres from the bench floor.
	var shared_count := 0
	if load_shared_structure:
		for s_entry in WorldLayout.structure_items:
			if _apply_layout_entry(s_entry):
				shared_count += 1
	# Restored vehicle poses are NOT clearance-checked on the way in (they were
	# valid when saved, or predate the gate). Resolve any nesting before the
	# first physics frame runs on them.
	_denest_loaded_vehicles()
	print("[BuildMode] Loaded %d placed objects (per-save) + %d shared structure" % [count, shared_count])
	_report_retired_drops()

## One line per retired placeable id that this save still contained, with the
## count and the reason. Saving the world afterwards writes the entry out of
## existence — the objects are gone from the scene tree, so the next save has
## nothing to record.
func _report_retired_drops() -> void:
	for rid in _retired_dropped:
		print("[BuildMode] dropped %d x retired placeable '%s' from this save — %s"
			% [int(_retired_dropped[rid]), rid, PlaceableCatalog.retired_reason(String(rid))])
	_retired_dropped.clear()

## Move restored vehicles off each other so no two hulls start overlapped.
##
## Overlap is the ENTRY condition for the runaway-drift bug: Rapier's contact
## recovery inside BaseVehicle's move_and_collide pushes two nested frozen-
## kinematic hulls by the same vector every frame, so the overlap never resolves.
## BaseVehicle._clamp_recovery_overshoot bounds that motion; this removes its
## cause on the load path, the one path that still applies poses unchecked.
##
## A saved vehicle is NEVER dropped: if no clear spot is found inside the search
## radius the original pose is kept and the conflict is reported.
func _denest_loaded_vehicles() -> void:
	if _loaded_vehicles.is_empty():
		return
	# Every vehicle restored this pass is invisible to the physics probe (not yet
	# synced into the space), so they are resolved against each other with the
	# same 85 % footprint the placement gate uses, and excluded from the probe.
	var skip : Array[Node] = []
	for v in _loaded_vehicles:
		var vn : Node3D = v["node"]
		if is_instance_valid(vn):
			skip.append(vn)
	var settled : Array[Dictionary] = []
	var moved := 0
	for v2 in _loaded_vehicles:
		var node : Node3D = v2["node"]
		if not is_instance_valid(node):
			continue
		var vid : String = v2["id"]
		var size := _vehicle_footprint(vid)
		var rot_y := node.rotation.y
		var pos := node.global_position
		var blocker := _denest_blocker(vid, pos, rot_y, size, settled, skip)
		if blocker == "":
			settled.append({"pos": pos, "rot": rot_y, "size": size})
			continue
		var found := false
		for ring in range(1, DENEST_RINGS + 1):
			var radius := float(ring) * DENEST_STEP_M
			for a in DENEST_ANGLES:
				var ang := TAU * float(a) / float(DENEST_ANGLES)
				var cand := pos + Vector3(cos(ang) * radius, 0.0, sin(ang) * radius)
				if _denest_blocker(vid, cand, rot_y, size, settled, skip) != "":
					continue
				push_warning("[BuildMode] de-nest on load: '%s' (%s) was inside '%s' at %s — offset %.2f m to %s"
					% [String(node.name), vid, blocker, str(pos.round()),
						(cand - pos).length(), str(cand.round())])
				node.global_position = cand
				settled.append({"pos": cand, "rot": rot_y, "size": size})
				moved += 1
				found = true
				break
			if found:
				break
		if not found:
			push_warning("[BuildMode] de-nest on load: '%s' (%s) is inside '%s' at %s and NO clear spot was found within %.1f m — kept at its saved pose"
				% [String(node.name), vid, blocker, str(pos.round()),
					float(DENEST_RINGS) * DENEST_STEP_M])
			settled.append({"pos": pos, "rot": rot_y, "size": size})
	if moved > 0:
		print("[BuildMode] de-nest on load: offset %d of %d restored vehicles" % [moved, _loaded_vehicles.size()])
	_loaded_vehicles.clear()

## Catalog hull size for a vehicle id, with the same fallback the placement gate
## uses so both paths agree on what "overlapping" means.
func _vehicle_footprint(id: String) -> Vector3:
	var item : Dictionary = PlaceableCatalog.get_item(id)
	if item.is_empty():
		return Vector3(2.0, 2.5, 4.0)
	return item.get("size", Vector3(2.0, 2.5, 4.0))

## Name of whatever blocks `at`, or "" when the spot is clear. Two sources:
## the live physics probe (world vehicles that predate this load) and a
## geometric test against the vehicles already settled by this pass.
func _denest_blocker(id: String, at: Vector3, rot_y: float, size: Vector3,
		settled: Array[Dictionary], skip: Array[Node]) -> String:
	var live := _vehicle_blocker_at(id, at, rot_y, skip)
	if live != "":
		return live
	for i in settled.size():
		var s : Dictionary = settled[i]
		var s_pos : Vector3 = s["pos"]
		var s_rot : float = s["rot"]
		var s_size : Vector3 = s["size"]
		if _hulls_overlap(at, rot_y, size, s_pos, s_rot, s_size):
			return "restored vehicle #%d" % i
	return ""

## 85 %-footprint overlap test between two vehicle hulls, mirroring the placement
## gate: box centres sit at pos.y + size.y * 0.5 + 0.1, extents are size * 0.85.
## Separating-axis test on the four footprint axes plus a vertical interval test
## — a nested "ladder" pair overlaps on both, a machine parked alongside on
## neither.
func _hulls_overlap(a_pos: Vector3, a_rot: float, a_size: Vector3,
		b_pos: Vector3, b_rot: float, b_size: Vector3) -> bool:
	var a_cy := a_pos.y + a_size.y * 0.5 + 0.1
	var b_cy := b_pos.y + b_size.y * 0.5 + 0.1
	var a_hy := a_size.y * 0.85 * 0.5
	var b_hy := b_size.y * 0.85 * 0.5
	if absf(a_cy - b_cy) >= a_hy + b_hy:
		return false
	var d := Vector2(b_pos.x - a_pos.x, b_pos.z - a_pos.z)
	var axes : Array[Vector2] = [
		Vector2(cos(a_rot), -sin(a_rot)), Vector2(sin(a_rot), cos(a_rot)),
		Vector2(cos(b_rot), -sin(b_rot)), Vector2(sin(b_rot), cos(b_rot)),
	]
	for ax in axes:
		var reach := _footprint_reach(ax, a_rot, a_size) + _footprint_reach(ax, b_rot, b_size)
		if absf(d.dot(ax)) >= reach:
			return false
	return true

## Half-extent of a Y-rotated 85 % footprint projected onto `axis`.
func _footprint_reach(axis: Vector2, rot_y: float, size: Vector3) -> float:
	var ux := Vector2(cos(rot_y), -sin(rot_y))
	var uz := Vector2(sin(rot_y), cos(rot_y))
	return absf(axis.dot(ux)) * size.x * 0.85 * 0.5 + absf(axis.dot(uz)) * size.z * 0.85 * 0.5

## Apply one persisted layout entry (from per-save or shared structure). Returns
## true when an object was actually placed in the scene.
func _apply_layout_entry(entry: Variant) -> bool:
	if typeof(entry) != TYPE_DICTIONARY:
		return false
	var dict: Dictionary = entry
	if not _is_valid_layout_entry(dict):
		return false

	# New 4-point surfaces (door / gate / window / sign / panel).
	if String(dict.get("kind", "")) == "surface":
		var pts: Array = []
		for pp in dict.get("p", []):
			if typeof(pp) == TYPE_ARRAY and (pp as Array).size() >= 3:
				pts.append(Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
		if pts.size() == 4:
			_make_surface(pts, String(dict.get("type", "door")), String(dict.get("label", "")))
			return true
		return false

	# Legacy plain box "door" → upgrade to an interactive door + hole.
	if String(dict.get("id", "")) == "door":
		_load_legacy_door(dict)
		return true

	# #194 — single-click structure placeables (door_personnel / gate_roller /
	# window_frame) carry both their visual model AND a matching wall carve.
	# Save records only the catalog id + pose; on load we re-instantiate the
	# placeable AND replay the WallOpenings.add_opening call so the hole reappears.
	# Legacy id="surface" (saves written before this fix) is routed as a default
	# personnel door — same dims as the door_personnel catalog entry — so the
	# user's pre-fix doors come back instead of silently dropping.
	var sid := String(dict.get("id", ""))
	if sid == "door_personnel" or sid == "gate_roller" or sid == "window_frame" or sid == "surface":
		var resolved_id := sid if sid != "surface" else "door_personnel"
		_load_structure_placeable(resolved_id, dict)
		return true

	# Variable belts: rebuild via build_variable_belt(start, end) from the
	# persisted endpoints. Transform is derived from the span, not from an anchor.
	if String(dict.get("id", "")) == "variable_belt" \
			and dict.has("sx") and dict.has("ex"):
		var sv := Vector3(float(dict["sx"]), float(dict["sy"]), float(dict["sz"]))
		var ev := Vector3(float(dict["ex"]), float(dict["ey"]), float(dict["ez"]))
		var vb := PlaceableCatalog.build_variable_belt(sv, ev, false)
		if vb != null:
			_placed_root.add_child(vb)
			return true
		return false

	# Walls: rebuild solid span from endpoints; size from catalog.
	if String(dict.get("id", "")).begins_with("wall_") \
			and dict.has("sx") and dict.has("ex"):
		var wsv := Vector3(float(dict["sx"]), float(dict["sy"]), float(dict["sz"]))
		var wev := Vector3(float(dict["ex"]), float(dict["ey"]), float(dict["ez"]))
		var witem : Dictionary = PlaceableCatalog.get_item(String(dict.get("id", "")))
		var wsz : Vector3 = witem.get("size", Vector3(0.2, 3.5, 1.0)) if not witem.is_empty() else Vector3(0.2, 3.5, 1.0)
		var w := PlaceableCatalog.build_wall(wsv, wev, wsz.x, wsz.y, false)
		if w != null:
			_placed_root.add_child(w)
			w.global_position = (wsv + wev) * 0.5
			w.set_meta("placeable_id", String(dict.get("id", "")))
			w.set_meta("wall_start", wsv)
			w.set_meta("wall_end", wev)
			return true
		return false

	# #72 — Grating platforms: custom W×L build path. Older saves without gw/gl
	# fall through to the generic build_node() at the bottom (catalog default size).
	if String(dict.get("id", "")) == "grating_platform" and dict.has("gw") and dict.has("gl"):
		var plat := PlaceableCatalog.build_grating_platform(
			float(dict["gw"]), float(dict["gl"]), false)
		if plat != null:
			_placed_root.add_child(plat)
			plat.global_position = Vector3(
				float(dict.get("x", 0.0)),
				float(dict.get("y", 0.0)),
				float(dict.get("z", 0.0)))
			plat.rotation.y = float(dict.get("rot_y", 0.0))
			_finalize_placed(plat, "grating_platform", float(dict.get("h", 0.0)))
			return true
		return false

	# Support poles: custom-height build path.
	var ld_id := String(dict.get("id", ""))
	if PlaceableCatalog.is_pole(ld_id) and dict.has("pole_h"):
		var pole := PlaceableCatalog.build_pole(ld_id, float(dict["pole_h"]), false)
		if pole != null:
			_placed_root.add_child(pole)
			pole.global_position = Vector3(
				float(dict.get("x", 0.0)),
				float(dict.get("y", 0.0)),
				float(dict.get("z", 0.0)))
			pole.rotation.y = float(dict.get("rot_y", 0.0))
			return true
		return false

	var entry_id := String(dict.get("id", ""))
	if entry_id == "":
		# Legacy / corrupt save entry — skip silently instead of pushing the
		# "Unknown id:" warning from PlaceableCatalog.build_node.
		return false
	# Retired placeables (e.g. the pre-#165 generic HMI props) are dropped on
	# purpose. Counted, not warned per-entry, so a save with a dozen of them
	# produces one honest summary line instead of a wall of warnings — and so
	# "my panel disappeared" always has a printed answer.
	if PlaceableCatalog.is_retired(entry_id):
		_retired_dropped[entry_id] = int(_retired_dropped.get(entry_id, 0)) + 1
		return false
	var node := PlaceableCatalog.build_node(entry_id, false)
	if node == null:
		return false
	_placed_root.add_child(node)
	node.global_position = Vector3(
		float(dict.get("x", 0.0)),
		float(dict.get("y", 0.0)),
		float(dict.get("z", 0.0)))
	node.rotation.y = float(dict.get("rot_y", 0.0))
	# #196 — restore K-menu tilt (pitch/roll). Older saves omit these → 0.
	if dict.has("rot_x"):
		node.rotation.x = float(dict["rot_x"])
	if dict.has("rot_z"):
		node.rotation.z = float(dict["rot_z"])
	if dict.has("scale"):
		var sc_raw : Variant = dict["scale"]
		if sc_raw is Array and (sc_raw as Array).size() >= 3:
			# Per-axis (new format).
			node.scale = Vector3(float(sc_raw[0]), float(sc_raw[1]), float(sc_raw[2]))
		else:
			# Uniform (legacy format).
			var sc := float(sc_raw)
			node.scale = Vector3(sc, sc, sc)
	_finalize_placed(node, String(dict.get("id", "")), float(dict.get("h", 0.0)))
	_finalize_bale(node, String(dict.get("code", "")))
	# A placed vehicle's life spans reloads — the 2026-07-20 clamps were only seen
	# displaced in a LATER save, never at the moment of placement. So a restored
	# vehicle joins the standing sentinel too, baselined on its restored pose.
	if entry_id.begins_with("vehicle_"):
		_arm_vehicle_watchdog(node)
		# Queued for the post-load clearance pass (_denest_loaded_vehicles): a
		# saved pose is applied verbatim here, and pre-gate saves contain nested
		# pairs.
		_loaded_vehicles.append({"node": node, "id": entry_id})
	# phys-04 — restore lump_cart fill (kg + remaining cool-down) persisted by
	# _save_layout; restore_fill re-syncs mass and re-anchors the cool timer.
	if dict.has("lumps_kg") and node.is_in_group("lump_cart") and node.has_method("restore_fill"):
		node.call("restore_fill", float(dict.get("lumps_kg", 0.0)), float(dict.get("cool_left_s", 0.0)))
	# #MSB — restore macro membership metas from disk so save-back still works
	# after a reload of a save that placed a macro previously.
	if dict.has("macro_id"):
		node.set_meta("macro_id", String(dict["macro_id"]))
	if dict.has("macro_index"):
		node.set_meta("macro_index", int(dict["macro_index"]))
	if dict.has("macro_anchor"):
		var anc_raw : Variant = dict["macro_anchor"]
		if anc_raw is Dictionary:
			var d_anc : Dictionary = anc_raw
			node.set_meta("macro_anchor", {
				"start": Vector3(float(d_anc.get("sx", 0.0)), float(d_anc.get("sy", 0.0)), float(d_anc.get("sz", 0.0))),
				"rot_y": float(d_anc.get("rot_y", 0.0)),
			})
	return true

## #194 — Re-instantiate a single-click structure placeable (door_personnel /
## gate_roller / window_frame) AND replay the wall carve so the hole the door
## sits in reappears on reload. Catalog gives us the footprint (W,H,T); the
## save record gives us pose (x,y,z,rot_y). Together they reconstruct the same
## placement + opening the operator made by clicking once in build mode.
##
## Legacy id="surface" entries (saves written before this fix) come in here
## resolved to "door_personnel" — best-effort: we don't have their original
## type recorded, so we treat them as personnel doors at the catalog default
## size. The user can delete + replace if they wanted a roller gate instead.
func _load_structure_placeable(resolved_id: String, dict: Dictionary) -> void:
	var node := PlaceableCatalog.build_node(resolved_id, false)
	if node == null:
		push_warning("[BuildMode] _load_structure_placeable: build_node returned null for %s" % resolved_id)
		return
	_placed_root.add_child(node)
	var pos := Vector3(
		float(dict.get("x", 0.0)),
		float(dict.get("y", 0.0)),
		float(dict.get("z", 0.0)))
	node.global_position = pos
	node.rotation.y = float(dict.get("rot_y", 0.0))
	_finalize_placed(node, resolved_id, float(dict.get("h", 0.0)))
	_carve_structure_opening(node, resolved_id, pos, float(dict.get("rot_y", 0.0)))

## Cut the wall opening a door/gate/window placeable stands in — visual +
## collision, immediately (WallOpenings.add_opening rebuilds synchronously).
## Centre = leaf centre (Y = pos.y + H/2 so the bottom of the cut sits on the
## floor). Rotation = node yaw. Catalog size gives W×H; depth (2.0 m) is
## generous so the cut always punches the wall regardless of its thickness.
##
## SINGLE SOURCE for this carve: previously only the RELOAD path
## (_load_structure_placeable) called this, because catalog id door_personnel /
## gate_roller / window_frame is built as a decoration-only visual (see
## PlaceableCatalog.gd #116 — "operator drops them into a pre-existing hole").
## A freshly single-clicked gate therefore stood in front of an intact wall
## with no way through until the operator saved and reloaded the world
## (operator report 2026-07-22: "no way through was created"). Now the LIVE
## placement path (_place_current) calls this too, so the cut appears the
## instant the gate is dropped, not after a round-trip through disk.
## Returns true if a wall was actually cut. False means the box touched no
## shell geometry — the placeable stands somewhere with no wall nearby
## (measured 2026-08-08: an operator door_personnel click 5-8 m from any
## wall, on the outdoor apron, silently registered as a permanent opening 41
## times over — each one a full shell-mesh rebuild — before this guard).
func _carve_structure_opening(node: Node3D, resolved_id: String, pos: Vector3, rot_y: float) -> bool:
	if wall_openings == null:
		return false
	var item := PlaceableCatalog.get_item(resolved_id)
	var size : Vector3 = item.get("size", Vector3(1.2, 2.4, 0.18)) if not item.is_empty() else Vector3(1.2, 2.4, 0.18)
	var ow := clampf(size.x, 0.5, 6.0)
	var oh := clampf(size.y, 0.5, 8.0)
	var cut_centre := pos + Vector3(0.0, oh * 0.5, 0.0)
	_opening_seq += 1
	var oid := "op_%d" % _opening_seq
	if not wall_openings.add_opening(oid, cut_centre, Vector3(ow, oh, 2.0), rot_y):
		return false
	node.set_meta("opening_id", oid)
	# The shared vehicle route grid samples real colliders ONCE per world and is
	# cached from then on (BaseVehicle._route_grid) — a carve made after that
	# first sample was invisible to every vehicle already driving this session
	# (operator's own forklift, mid-shift, ignored a freshly-placed gate).
	# Force it to resample on the next drive order.
	BaseVehicle.invalidate_route_grid()
	return true

## Converts a legacy box-door entry {id:"door", x,y,z,rot_y} into the new
## interactive roller door with a carved opening, by reconstructing its 4
## corner points from the catalogue door footprint.
func _load_legacy_door(dict: Dictionary) -> void:
	var item := PlaceableCatalog.get_item("door")
	var size: Vector3 = item.get("size", Vector3(1.2, 2.4, 0.18))
	var w := size.x
	var h := size.y
	var rot_y := float(dict.get("rot_y", 0.0))
	# Base position (origin at floor) → centre of the leaf.
	var base := Vector3(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)), float(dict.get("z", 0.0)))
	var center := base + Vector3(0.0, h * 0.5, 0.0)
	var x_axis := Vector3(cos(rot_y), 0.0, sin(rot_y))
	var up := Vector3.UP
	var hx := x_axis * (w * 0.5)
	var hy := up * (h * 0.5)
	var pts := [
		center - hx - hy,   # bottom-left
		center - hx + hy,   # top-left
		center + hx + hy,   # top-right
		center + hx - hy,   # bottom-right
	]
	_make_surface(pts, "door", "Door")

func _is_valid_layout_entry(dict: Dictionary) -> bool:
	if dict.has("layout_version"):
		if typeof(dict["layout_version"]) not in [TYPE_INT, TYPE_FLOAT]:
			return false
		# The layout version object shouldn't be mixed with normal object fields.
		if dict.size() > 1:
			return false
		return true

	if dict.has("kind"):
		if typeof(dict["kind"]) != TYPE_STRING:
			return false
		if dict["kind"] == "surface":
			if not dict.has("p") or typeof(dict["p"]) != TYPE_ARRAY:
				return false
			var p_arr: Array = dict["p"]
			if p_arr.size() != 4:
				return false
			for pp in p_arr:
				if typeof(pp) != TYPE_ARRAY or (pp as Array).size() < 3:
					return false
				if typeof(pp[0]) not in [TYPE_INT, TYPE_FLOAT]: return false
				if typeof(pp[1]) not in [TYPE_INT, TYPE_FLOAT]: return false
				if typeof(pp[2]) not in [TYPE_INT, TYPE_FLOAT]: return false
			if dict.has("type") and typeof(dict["type"]) != TYPE_STRING:
				return false
			if dict.has("label") and typeof(dict["label"]) != TYPE_STRING:
				return false
			return true

	if not dict.has("id") or typeof(dict["id"]) != TYPE_STRING:
		return false
	if dict.has("x") and typeof(dict["x"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if dict.has("y") and typeof(dict["y"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if dict.has("z") and typeof(dict["z"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if dict.has("rot_y") and typeof(dict["rot_y"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if dict.has("h") and typeof(dict["h"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	if dict.has("code") and typeof(dict["code"]) != TYPE_STRING:
		return false

	return true
