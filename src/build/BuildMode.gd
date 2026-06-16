extends Node3D
class_name BuildMode
## In-game, Minecraft-style factory builder. You arrange the real CeDo floor;
## the sim provides the objects + placement mechanics.
##
## States:
##   INACTIVE — normal play.
##   BROWSING — catalog panel open, mouse free. Click an item → PLACING.
##   PLACING  — translucent ghost follows the crosshair; mouse captured.
##              [LMB] place   [R] rotate   [RMB] put item away (→ BROWSING)
##              [X] delete the object under the crosshair   [Tab] open catalog
##
## Toggle the whole mode with [Tab] (build_mode_toggle).
##
## Spawned by MainWorld as a child (needs the world for raycasts and to parent
## placed objects). Placed layout persists to user://factory_layout.json and is
## reloaded on startup, so the factory you build stays built.

enum State { INACTIVE, BROWSING, PLACING, SURFACE, EDIT }

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
# the vuilsnippersilo (wet-film buffer). The shared dry front-end (opzetband →
# shredder → bunker → SGA → magnet → ballistic → windshifter → TITECH → VSS) is
# the common intake that feeds BOTH lines — built separately (task #54), NOT here.
# Kufferath, MAS bak/drogers and the 3-washer chain are LINE 1 — absent from 3A/3B.
# Name→id: doseerschroef→transport_screw, glijgoot→transfer_chute, pomp→water_pump,
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
	# #81 — water_pump moved OFF the centreline. It's a utility unit (water loop,
	# not material flow; role="none" in MachineFlow) so placing it in the main
	# chain just pushed every downstream machine further along Z for no reason.
	# Now sits on the -X side lane next to the friction_sep it feeds water to.
	{"id": "water_pump", "x": -3.5, "z": 0.0},
	{"id": "friction_sep"},
	{"id": "flotation_tank"},
	{"id": "dewater_screw"},
	{"id": "friction_sep"},
	{"id": "transport_screw"},
	{"id": "mech_dryer"},
	{"id": "blower"},
	{"id": "mengsilo"},
	# ── RECIRC DRYING LOOP (branch, +X side, returns to the mengsilo top) ──
	# 2nd dosing screw lifts film into the ring main to DRY it; a cyclone drops the
	# dried film back into the TOP of the mengsilo. Toggleable sub-circuit.
	# #71 — `branch_recirc` on the first branch entry tells _build_full_line to
	# tag the LAST branch entry (cyclone) with a recirc back-edge to the source
	# (mengsilo). LineFlow treats recirc edges as invisible to the cycle check,
	# so the loop can close without blocking the main forward path.
	{"id": "transport_screw", "x": 5.0, "z": -3.0, "branch_recirc": true},
	{"id": "blower",          "x": 5.0, "z":  0.0},
	{"id": "ringleiding",     "x": 5.0, "z":  3.0},
	{"id": "cyclone",         "x": 5.0, "z":  6.0},
	# ── MAIN PATH out of the mengsilo (1st dosing screw) ──
	{"id": "transport_screw"},
	{"id": "verdeelwals"},
	{"id": "blower"},
	{"id": "wind_sifter"},
	{"id": "blower"},
	{"id": "cyclone"},
	{"id": "verdeelwals"},
	{"id": "thermal_dryer"},
	{"id": "cyclone"},
	{"id": "blower"},
	{"id": "cyclone"},
	# #107 — was plain `silo`; the extruder's hot end has to be fed by the
	# elevated extruder_silo (frame + 2 cyclones on top + lump bin + windows),
	# not a generic dosing silo. Same change applied to 3B and Line 1 below.
	{"id": "extruder_silo"},
	{"id": "extruder_3a"},
	# #98 — Lump cart parking spot next to the extruder's screen-changer
	# discharge. Operator's responsibility to make sure a lump_cart is parked
	# here BEFORE the extruder starts. Spot is at +X offset, partway along the
	# extruder's length so the laser_filter outlet is above the cart.
	{"id": "lump_cart_spot", "x": 2.8, "z": -5.0},
	{"id": "lump_cart",      "x": 2.8, "z": -5.0},
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
# Sort line — two trilzeef vibrating sieves running in PARALLEL (operator
# spec: bales feed into the head end, material splits left+right across two
# screens running side-by-side, dual outputs at the tail). x = ±2.5 m puts
# them on either side of the centreline with ~1m clear lane between them
# (each trilzeef is 1.8 m wide). Both at z=0 so they run as siblings, not in
# series. _build_full_line treats x≠0 entries as branches; using a PARALLEL
# split (both at the same z, opposite x) matches the 3B L-R split pattern.
const LINE_SORT_SEQ : Array[Dictionary] = [
	# D4 — operator: real plant feeds the trilzeef pair from an opzetband_3a3b
	# at the head. Without it the macro just drops two parallel screens with no
	# upstream feed surface.
	{"id": "opzetband_3a3b"},
	{"id": "trilzeef", "x": -2.5, "z": 1.0},
	{"id": "trilzeef", "x":  2.5, "z": 1.0},
]

## D4 — Lines 3C + 6 share a front-end (opzetband_3c6 → shredder → climb belt →
## trilzeef → wash chain). Previously placeable existed in the catalog but no
## macro chained it, so the operator couldn't build the 3C/6 intake from the
## "Lines" group. This is the shared 3C/6 front end; downstream wash diverges
## per line (use LINE_3A/3B-style macros for that, with the wider flotation_tank_wide).
const LINE_3C6_SEQ : Array[Dictionary] = [
	{"id": "opzetband_3c6"},
	{"id": "shredder_2"},
	{"id": "inclined_belt_8m"},
	{"id": "trilzeef"},
]

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
	{"id": "blower"},              # recombine
	{"id": "cyclone"},
	{"id": "plasmaq"},
	{"id": "cyclone"},
	{"id": "blower"},
	{"id": "cyclone"},
	{"id": "extruder_silo"},
	{"id": "extruder_3b"},
	# #98 — Lump cart parking spot at the extruder's filter discharge.
	{"id": "lump_cart_spot", "x": 2.8, "z": -5.0},
	{"id": "lump_cart",      "x": 2.8, "z": -5.0},
]
# Line 1 = its own intake (opzetband 1 → metal detector → westa band → shredder →
# magnet → VW trommel → scheidingsgoot) then wash/dry/extrude; transcribed from the
# operator's LIJN 1 sheet; 2x machines laid as side-by-side pairs (jog with K to finalize).
const LINE_1_SEQ : Array[Dictionary] = [
	{"id": "opzetband_1"},
	{"id": "metaaldetector"},
	{"id": "westa_band_1"},
	{"id": "shredder_1"},
	{"id": "transport_belt"},
	{"id": "overband_magnet"},
	{"id": "transport_belt"},
	{"id": "prewash_drum"},
	{"id": "scheidingsgoot"},
	{"id": "friction_sep", "x": -2.5, "z": 1.0},
	{"id": "friction_sep", "x":  2.5, "z": 1.0, "main_advance": 5.0},
	{"id": "mech_dryer",  "x": -2.5, "z": 1.0},
	{"id": "mech_dryer",  "x":  2.5, "z": 1.0, "main_advance": 5.0},
	{"id": "blower",      "x": -2.0, "z": 0.5},
	{"id": "blower",      "x":  2.0, "z": 0.5, "main_advance": 2.5},
	{"id": "cyclone",     "x": -2.0, "z": 0.5},
	{"id": "cyclone",     "x":  2.0, "z": 0.5, "main_advance": 3.0},
	{"id": "transport_screw", "x": -2.0, "z": 0.5},
	{"id": "transport_screw", "x":  2.0, "z": 0.5, "main_advance": 5.0},
	{"id": "mill"},
	{"id": "blower",      "x": -2.0, "z": 0.5},
	{"id": "blower",      "x":  2.0, "z": 0.5, "main_advance": 2.5},
	{"id": "cyclone",     "x": -2.0, "z": 0.5},
	{"id": "cyclone",     "x":  2.0, "z": 0.5, "main_advance": 3.0},
	{"id": "flotation_tank"},
	{"id": "dewater_screw"},
	{"id": "friction_sep"},
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
	{"id": "extruder_1"},
]
const LINE_GAP_M : float = 1.5   # clear space between consecutive machines

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
var _crosshair   : ColorRect
var _popup       : PanelContainer
var _popup_type  : OptionButton
var _popup_name  : LineEdit

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
# INPUT  (handled in _input so [Tab] beats UI focus navigation)
# =============================================================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode_toggle"):
		_on_toggle()
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

	if _state != State.PLACING:
		return

	if event.is_action_pressed("build_place"):
		_place_current()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_cancel"):
		# RMB: first press just cancels an in-progress two-point capture (keep the
		# operator on the same placeable so they can re-pick the start); a second
		# RMB falls through to leaving placing mode altogether.
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
	if _state != State.PLACING or _ghost == null:
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
		if line_flow:
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
		if line_flow:
			line_flow.rebuild()
		_update_placing_status()
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
		return
	var node := PlaceableCatalog.build_node(_active_id, false)
	if node == null:
		return
	_placed_root.add_child(node)
	node.global_position = _ghost.global_position
	node.rotation.y = _ghost_rot_y
	_finalize_placed(node, _active_id, _ghost_height)
	_finalize_bale(node)
	_save_layout()
	if line_flow:
		line_flow.rebuild()

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
	# #MSB — pull operator-saved deltas (chain-accumulated) from the store.
	# Each index's delta is added in the macro's LOCAL frame (x/z lateral,
	# y vertical, rot_y around vertical). Empty dict = use const seed verbatim.
	var macro_deltas : Dictionary = LineMacroStore.accumulated_chain(line_id, seq.size())
	# Forward = the ghost's local -Z; right = local +X (lateral lane for branches).
	var fwd := Vector3(-sin(rot_y), 0.0, -cos(rot_y))
	var rgt := Vector3(cos(rot_y), 0.0, -sin(rot_y))
	var main_z := 0.0
	var built := 0
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
	for entry_idx in range(seq.size()):
		var entry : Dictionary = seq[entry_idx]
		var mid : String = String(entry.get("id", ""))
		if mid == "":
			continue
		var x : float = float(entry.get("x", 0.0))
		var is_branch : bool = not is_equal_approx(x, 0.0)
		var is_parallel : bool = bool(entry.get("parallel_branch", false))
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
		if not is_branch:
			# Main-centreline machine — advances the main cursor.
			# Head-to-tail spacing for consecutive transportbands: undo the
			# LINE_GAP_M that the previous main entry added, so this belt's
			# inlet butts directly against the prior belt's outlet.
			if last_main_was_tb and is_tb:
				main_z -= LINE_GAP_M
			main_z += depth * 0.5
			place_z = main_z
			main_z += depth * 0.5 + LINE_GAP_M
			last_main_was_tb = is_tb
		else:
			# Branch machine — sits beside the line at (current cursor + z offset) and
			# does NOT advance the main cursor (the main flow runs past it).
			place_z = main_z + float(entry.get("z", 0.0))
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
			var d_dx : float = float(d.get("dx", 0.0))
			var d_dy : float = float(d.get("dy", 0.0))
			var d_dz : float = float(d.get("dz", 0.0))
			var d_drot : float = float(d.get("drot_y", 0.0))
			var d_scale : Vector3 = Vector3.ONE
			if d.has("scale") and d["scale"] is Vector3:
				d_scale = d["scale"]
			node.global_position = Vector3(start.x, start.y + tb_y_offset, start.z) \
				+ fwd * (place_z + d_dz) + rgt * (x + d_dx) + Vector3.UP * d_dy
			node.rotation.y = rot_y + PI + d_drot
			if d_scale != Vector3.ONE:
				node.scale = d_scale
			_finalize_placed(node, mid, 0.0)
			# #MSB — stamp macro-membership metas so save-back can find this
			# node and recover its local-frame pose later.
			node.set_meta("macro_id", line_id)
			node.set_meta("macro_index", entry_idx)
			node.set_meta("macro_anchor", {"start": start, "rot_y": rot_y})
			built += 1
			# ── #71 branch state transitions ───────────────────────────────────
			if is_branch:
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
					if branch_recirc and branch_source != null:
						# Recirc: last branch entry returns to the branch source.
						_add_explicit_out(last_chain, branch_source, true)
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
	print("[BuildMode] Built %s — %d machines over %.1f m" % [line_id, built, main_z])
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
	return [] as Array[Dictionary]

## Re-walk the seed SEQ (no spawning) and emit an Array of {x, z, rot_y_extra}
## NOMINAL local-frame placements per index. Mirrors the cursor advancement
## inside _build_full_line so the per-index nominal pose lines up exactly with
## what the original placement put in world. Branch nodes inherit a y offset
## of 0; transportband Y stacking is captured via tb_y_offset.
func _macro_nominal_poses(seed: Array[Dictionary]) -> Array:
	var poses : Array = []
	var main_z := 0.0
	const TB_CHUTE_DROP_M : float = 0.22
	const _LINE_GAP_M : float = LINE_GAP_M
	var prev_tb_outlet_y : float = -1.0
	var last_main_was_tb : bool = false
	for entry in seed:
		var mid : String = String(entry.get("id", ""))
		if mid == "":
			poses.append({"x": 0.0, "y": 0.0, "z": 0.0})
			continue
		var x : float = float(entry.get("x", 0.0))
		var is_branch : bool = not is_equal_approx(x, 0.0)
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
		if not is_branch:
			if last_main_was_tb and is_tb:
				main_z -= _LINE_GAP_M
			main_z += depth * 0.5
			place_z = main_z
			main_z += depth * 0.5 + _LINE_GAP_M
			last_main_was_tb = is_tb
		else:
			place_z = main_z + float(entry.get("z", 0.0))
		if is_tb and not is_branch and tb_outlet_y_after > 0.0:
			prev_tb_outlet_y = tb_outlet_y_after
		elif not is_tb and not is_branch:
			prev_tb_outlet_y = -1.0
		poses.append({"x": x, "y": tb_y_offset, "z": place_z})
		if entry.has("main_advance"):
			main_z += float(entry["main_advance"])
	return poses

## Walk placed_object children tagged with `macro_id`, compute the local-frame
## delta for each one vs the const seed's nominal pose, accumulate chain-style
## (so machine N stores ONLY the explicit drift NOT already explained by
## upstream changes), and hand the dict to LineMacroStore. Returns the number
## of overrides written.
func save_macro_overrides(macro_id: String) -> int:
	var seed : Array[Dictionary] = _macro_seed(macro_id)
	if seed.is_empty():
		push_warning("[BuildMode] Unknown macro id %s" % macro_id)
		return 0
	var nominal : Array = _macro_nominal_poses(seed)
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
	# Inverse-basis vectors (same fwd/rgt as _build_full_line).
	var fwd := Vector3(-sin(a_rot), 0.0, -cos(a_rot))
	var rgt := Vector3(cos(a_rot), 0.0, -sin(a_rot))
	# Build the chain accumulator: for each index the operator MOVED (or any
	# index <= max moved), compute its local delta vs nominal, then subtract
	# the upstream accumulated drift so the on-disk value is the operator's
	# EXPLICIT contribution at that index.
	var deltas : Dictionary = {}
	var acc := Vector3.ZERO
	var acc_rot := 0.0
	var acc_scale := Vector3.ONE
	for i in range(seed.size()):
		if not members.has(i):
			continue
		var node : Node3D = members[i]
		var nom : Dictionary = {"x": 0.0, "y": 0.0, "z": 0.0}
		if i < nominal.size() and nominal[i] is Dictionary:
			nom = nominal[i]
		# Inverse transform: local = inverse_basis * (world_pos - start).
		# Basis is rotation-only around Y, so dot products recover x_local
		# (along rgt) and z_local (along fwd).
		var rel : Vector3 = node.global_position - a_start
		var x_local : float = rel.dot(rgt)
		var z_local : float = rel.dot(fwd)
		var y_local : float = rel.y
		var dx : float = x_local - float(nom.get("x", 0.0))
		var dy : float = y_local - float(nom.get("y", 0.0))
		var dz : float = z_local - float(nom.get("z", 0.0))
		var drot : float = node.rotation.y - (a_rot + PI)
		# Wrap rotation into (-PI, PI] so saved deltas are minimal.
		drot = wrapf(drot, -PI, PI)
		var sc : Vector3 = node.scale
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
	var ok : bool = LineMacroStore.save_overrides(macro_id, deltas, seed.size())
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
	# If it owns a carved opening, restore that part of the wall first.
	if target.has_meta("opening_id") and wall_openings:
		wall_openings.remove_opening(String(target.get_meta("opening_id")))
	# Drop from the flow group now so the rebuild below doesn't re-include it
	# (queue_free only frees at end of frame).
	target.remove_from_group("placed_object")
	var par := target.get_parent()
	if par != null:
		par.remove_child(target)
	target.queue_free()
	_save_layout()
	if line_flow:
		line_flow.rebuild()

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
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	_edit_selected = null
	_clear_edit_highlight()
	_update_edit_status()

func _exit_edit_mode() -> void:
	_edit_deselect()
	_enter_inactive()

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
		if line_flow: line_flow.rebuild()
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
	if target.has_meta("opening_id") and wall_openings:
		wall_openings.remove_opening(String(target.get_meta("opening_id")))
	target.remove_from_group("placed_object")
	var par := target.get_parent()
	if par != null: par.remove_child(target)
	target.queue_free()
	_save_layout()
	if line_flow: line_flow.rebuild()
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
		return
	var nm := String(PlaceableCatalog.get_item(String(_edit_selected.get_meta("placeable_id",""))).get("name", _edit_selected.name))
	var p := _edit_selected.global_position
	var sc_v : Vector3 = _edit_selected.scale
	var sc_str : String = ("scale %.2f" % sc_v.x) if (is_equal_approx(sc_v.x, sc_v.y) and is_equal_approx(sc_v.y, sc_v.z)) \
		else ("scale (%.2f, %.2f, %.2f)" % [sc_v.x, sc_v.y, sc_v.z])
	_status.text = "EDIT: %s   pos(%.2f, %.2f, %.2f)  rot %.0f°  %s\narrows=move  R/F=up/down  Q/E=rotate  +/-=uniform scale  7/4=X  8/5=Y  9/6=Z  Shift=fine  [X]delete  [K/RMB]exit" % [
		nm, p.x, p.y, p.z, rad_to_deg(_edit_selected.rotation.y), sc_str]

# Camera-forward ray against the world (floor / building / placed objects),
# excluding the player capsule and the (collision-less) ghost.
func _raycast() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
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
		wall_openings.add_opening(oid, center, Vector3(ow, oh, 2.0), rot_y)
		node.set_meta("opening_id", oid)
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
	WorldLayout.structure_items = shared
	WorldLayout.save()

func load_layout() -> void:
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
	var shared_count := 0
	for s_entry in WorldLayout.structure_items:
		if _apply_layout_entry(s_entry):
			shared_count += 1
	print("[BuildMode] Loaded %d placed objects (per-save) + %d shared structure" % [count, shared_count])

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
	var node := PlaceableCatalog.build_node(entry_id, false)
	if node == null:
		return false
	_placed_root.add_child(node)
	node.global_position = Vector3(
		float(dict.get("x", 0.0)),
		float(dict.get("y", 0.0)),
		float(dict.get("z", 0.0)))
	node.rotation.y = float(dict.get("rot_y", 0.0))
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
	# Carve the matching wall opening. Centre = leaf centre (Y = pos.y + H/2 so
	# the bottom of the cut sits on the floor). Rotation = node yaw. Catalog
	# size gives W×H; depth (2.0 m) is generous so the cut always punches the
	# wall regardless of its thickness.
	if wall_openings == null:
		return
	var item := PlaceableCatalog.get_item(resolved_id)
	var size : Vector3 = item.get("size", Vector3(1.2, 2.4, 0.18)) if not item.is_empty() else Vector3(1.2, 2.4, 0.18)
	var ow := clampf(size.x, 0.5, 6.0)
	var oh := clampf(size.y, 0.5, 8.0)
	var cut_centre := pos + Vector3(0.0, oh * 0.5, 0.0)
	_opening_seq += 1
	var oid := "op_%d" % _opening_seq
	wall_openings.add_opening(oid, cut_centre, Vector3(ow, oh, 2.0), float(dict.get("rot_y", 0.0)))
	node.set_meta("opening_id", oid)

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
