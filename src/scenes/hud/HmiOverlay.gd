extends CanvasLayer
class_name HmiOverlay

## Reconstruction of the real CeDo line PLC touchscreen.
##
## Modelled on the actual operator panels documented in the Cedo-PROD-SWI work
## instructions (e.g. "Lijn 1 Opstart" step 7 "Was 1 hoofd plc scherm": press
## [storingen] on the touchscreen, return via [hoofdmenu], press [start]). The
## SWIs don't contain clean screen exports — only blurry panel photos plus the
## exact button/menu flow — so this is a faithful *reconstruction* of that flow,
## not a pixel copy.
##
## Four screens, every button touch-clickable (mouse is freed to VISIBLE while
## open), wired to the live LineFlow sim:
##   HOOFDMENU      — section dashboard with live status lamps
##   OVERZICHT      — line mimic (Bunker→…→Extruder→Granulaat) + START/STOP/
##                    LEEGDRAAIEN + AUTOMAAT/HAND
##   STORINGEN      — active alarm list, KWITTEREN / RESETTEN
##   HANDBEDIENING  — per-section manual run/stop (gated by AUTOMAAT)
##
## Owned globally — Hmi.gd lazy-loads one instance and reuses it. open_for(label)
## sets the station title and shows it; close returns the cursor to captured.

enum Screen { HOOFDMENU, OVERZICHT, STORINGEN, HANDBEDIENING, MACHINES }

# --- Plant colour scheme (Siemens-ish steel + signal lamps) -------------------
const C_DIM        := Color(0.0, 0.0, 0.0, 0.62)
const C_BEZEL      := Color(0.10, 0.11, 0.13, 1.0)
const C_HEADER     := Color(0.12, 0.19, 0.25, 1.0)
const C_SCREEN     := Color(0.74, 0.78, 0.76, 1.0)   # the greenish-grey HMI glass
const C_TILE       := Color(0.86, 0.88, 0.86, 1.0)
const C_TILE_EDGE  := Color(0.38, 0.42, 0.40, 1.0)
const C_TEXT_DARK  := Color(0.10, 0.12, 0.11, 1.0)
const C_AMBER      := Color(1.0, 0.86, 0.45, 1.0)
const C_NAV        := Color(0.18, 0.27, 0.34, 1.0)
const C_NAV_SEL    := Color(0.20, 0.46, 0.62, 1.0)
# Signal lamps
const LAMP_OFF     := Color(0.42, 0.45, 0.43, 1.0)   # grey  — not installed
const LAMP_IDLE    := Color(0.90, 0.66, 0.18, 1.0)   # amber — present, idle
const LAMP_RUN     := Color(0.27, 0.78, 0.32, 1.0)   # green — running
const LAMP_FAULT   := Color(0.86, 0.22, 0.18, 1.0)   # red   — fault

# Status codes returned by _group_status / _stage_status
const ST_OFF   := 0
const ST_IDLE  := 1
const ST_RUN   := 2
const ST_FAULT := 3

# Live process-fault thresholds, read off the LineFlow per-machine telemetry.
const BUFFER_JAM_KG := 120.0   # input backlog (kg) that trips an "ophoping" alarm
const DRYER_WET_PCT := 8.0     # pre-extruder moisture % that's too wet to pellet cleanly
const MELT_DIRT_PCT := 1.0     # contamination % carried into the melt = wash underperforming
const QUALITY_MIN   := 70.0    # granulaat grade below this is off-spec

# Line mimic: the conceptual Line-1 process order. Each stage matches LineFlow
# nodes whose placeable id contains any of the listed tokens.
const STAGES := [
	{"name": "BUNKER",      "tokens": ["bunker"]},
	{"name": "SORTEREN",    "tokens": ["sga", "metal_belt", "ballistic", "wind_sifter", "titech", "tomra", "sorteer"]},
	{"name": "SHREDDERS",   "tokens": ["shredder"]},
	{"name": "OPVOER",      "tokens": ["inclined_belt", "feed_hopper", "transport_belt", "transport_screw", "conveyor", "blower"]},
	{"name": "WASSEN",      "tokens": ["prewash", "friction", "intensive", "wash", "was"]},
	{"name": "FLOTATIE",    "tokens": ["flotation", "rotation", "sink_float"]},
	{"name": "ZEVEN",       "tokens": ["kufferath", "rafter", "sieve", "zeef"]},
	{"name": "ONTWATEREN",  "tokens": ["dewater"]},
	{"name": "DROGEN",      "tokens": ["mech_dryer", "dryer", "droger", "centrifuge"]},
	{"name": "MENGSILO",    "tokens": ["mengsilo", "mas_bak", "compactor", "silo"]},
	{"name": "EXTRUDER",    "tokens": ["extruder", "intarema", "erema"]},
	{"name": "GRANULAAT",   "tokens": ["__sink__"]},
]

# Main-menu section dashboard groups.
const SECTIONS := [
	{"name": "SORTEERLIJN",  "tokens": ["bunker", "sga", "metal_belt", "ballistic", "wind_sifter", "titech", "tomra", "sorteer"]},
	{"name": "SHREDDERS",    "tokens": ["shredder"]},
	{"name": "WASLIJN",      "tokens": ["prewash", "friction", "intensive", "wash", "was", "flotation", "rotation", "kufferath", "rafter", "dewater", "sieve"]},
	{"name": "MAS DROGERS",  "tokens": ["mech_dryer", "dryer", "droger", "centrifuge", "mas"]},
	{"name": "EXTRUDER",     "tokens": ["extruder", "intarema", "erema", "mengsilo", "compactor", "silo"]},
	{"name": "WATER / ZSS",  "tokens": ["zss", "eop", "water", "tank", "pomp", "pump"]},
]

# =============================================================================
var _line_flow : Node = null
var _station   : String = "LIJN 1"
var _screen    : int = Screen.HOOFDMENU
var _refresh_acc : float = 0.0

# Operating state (local to the panel; START/STOP/AUTOMAAT drive the sim)
var _automaat       : bool = true
var _leegdraaien    : bool = false       # empty-run flag (display only)
var _manual_run     : Dictionary = {}    # section name -> bool (HANDBEDIENING)
var _acked_faults   : Dictionary = {}    # fault code -> true
var _last_fed_mass  : float = 0.0
var _no_feed_secs   : float = 0.0

# --- Persistent chrome widgets ---
var _dim          : ColorRect
var _bezel        : PanelContainer
var _header_title : Label
var _clock_lbl    : Label
var _alarm_chip   : Label
var _content      : MarginContainer
var _nav_btns     : Dictionary = {}      # screen -> Button

# --- Per-screen dynamic widgets (rebuilt on screen change) ---
var _stage_tiles  : Array = []           # [{def, lamp:ColorRect, val:Label}]
var _section_tiles: Array = []           # [{def, lamp:ColorRect}]
var _ov_status    : Label = null
var _ov_totals    : Label = null
var _start_btn    : Button = null
var _stop_btn     : Button = null
var _auto_btn     : Button = null
var _fault_box    : VBoxContainer = null
var _manual_rows  : Array = []           # [{section, lamp:ColorRect, btn:Button}]

# --- MACHINES screen state ---------------------------------------------------
var _selected_machine_id : String = ""
var _machines_list_vb    : VBoxContainer = null   # left column: scrollable list
var _machines_detail_vb  : VBoxContainer = null   # right column: live detail
var _machines_list_rows  : Array = []             # [{id, btn, lamp}]
# Rebuilt every time the selection changes; refresh() updates only the live widgets.
var _md_title_lbl    : Label = null
var _md_powered_lamp : ColorRect = null
var _md_status_lbl   : Label = null
var _md_buffer_bar   : ProgressBar = null
var _md_thru_lbl     : Label = null
var _md_hand_btn     : Button = null
var _md_run_btn      : Button = null
var _md_safeguard_lbl: Label = null
var _md_rpm_slider   : HSlider = null
var _md_rpm_pct_lbl  : Label = null
var _md_comp_rows    : Array = []   # [{name, slider:HSlider, pct_lbl:Label, rpm_lbl:Label, nom_rpm}]
var _md_amps_lbl     : Label = null

## Per-component design RPMs the operator's slider scales. RPM is the rotor's
## actual SPEED (independent of material) — what the operator commands. Throughput
## (kg/s) is the consequence, gated by material availability. A paddle spinning
## empty still has its full RPM here (and still draws the motor idle current).
const _NOMINAL_RPM := {
	# Tank stirrer / paddle stages — slow scrapers.
	"inlet":       30.0,
	"transport_1": 45.0,
	"transport_2": 45.0,
	"outlet":      30.0,
	# Dosing-silo augers — motor RPMs, before the gearbox. Operator usually thinks
	# in Hz (10 Hz ≈ 300 RPM on a 4-pole motor; 50 Hz ≈ 1500 RPM = full speed).
	"auger_1":     1500.0,
	"auger_2":     1500.0,
	"auger_3":     1500.0,
	# Conveyors / belts / screws (motor side, before any gearbox).
	"drive":       1450.0,
	# Shredder / mill rotors run far slower than the drive motor (post-gearbox).
	"rotor":        800.0,
}
static func _nominal_rpm_for(comp_name: String) -> float:
	return float(_NOMINAL_RPM.get(comp_name, 100.0))

# =============================================================================
func _ready() -> void:
	add_to_group("esc_modal_overlay")
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SECTIONS:
		_manual_run[String(s["name"])] = false
	_build_chrome()
	visible = false
	call_deferred("_find_line_flow")

func _find_line_flow() -> void:
	# Don't overwrite an already-resolved reference (the test harness assigns
	# directly, and we shouldn't drop a live ref because of a transient tree state).
	if _line_flow != null and is_instance_valid(_line_flow):
		return
	var root := get_tree().current_scene
	if root:
		_line_flow = root.find_child("LineFlow", true, false)

# =============================================================================
# OPEN / CLOSE
# =============================================================================
func open_for(label: String) -> void:
	_station = label.to_upper()
	_find_line_flow()
	if _line_flow and "fed_mass" in _line_flow:
		_last_fed_mass = float(_line_flow.fed_mass)
	_show_screen(Screen.HOOFDMENU)
	visible = true

func is_open() -> bool:
	return visible

func close_overlay() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		close_overlay()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	# Track feed-starvation for the synthetic "no material" alarm.
	if _line_flow and "feed_enabled" in _line_flow and bool(_line_flow.feed_enabled):
		var fed := float(_line_flow.fed_mass) if "fed_mass" in _line_flow else 0.0
		if fed <= _last_fed_mass + 0.001:
			_no_feed_secs += delta
		else:
			_no_feed_secs = 0.0
		_last_fed_mass = fed
	else:
		_no_feed_secs = 0.0
	# Clear the empty-run flag once the line has drained.
	if _leegdraaien and _in_transit() < 0.5:
		_leegdraaien = false
	_refresh_acc += delta
	if _refresh_acc >= 0.25:
		_refresh_acc = 0.0
		_refresh()

# =============================================================================
# CHROME (persistent: bezel + header + content slot + footer nav)
# =============================================================================
const PANEL_W := 900.0
const PANEL_H := 624.0

func _build_chrome() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = C_DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_bezel = PanelContainer.new()
	_bezel.set_anchors_preset(Control.PRESET_CENTER)
	_bezel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_bezel.offset_left   = -PANEL_W * 0.5
	_bezel.offset_top    = -PANEL_H * 0.5
	_bezel.offset_right  =  PANEL_W * 0.5
	_bezel.offset_bottom =  PANEL_H * 0.5
	_bezel.add_theme_stylebox_override("panel", _sb(C_BEZEL, 12, 14))
	add_child(_bezel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_bezel.add_child(outer)

	# ---- Header bar -------------------------------------------------------
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _sb(C_HEADER, 6, 10))
	outer.add_child(header)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	header.add_child(hrow)

	var logo := Label.new()
	logo.text = "cedo"
	logo.add_theme_font_size_override("font_size", 24)
	logo.add_theme_color_override("font_color", Color(0.35, 0.72, 0.92, 1))
	hrow.add_child(logo)

	_header_title = Label.new()
	_header_title.text = "LIJN 1  ·  HOOFDMENU"
	_header_title.add_theme_font_size_override("font_size", 19)
	_header_title.add_theme_color_override("font_color", C_AMBER)
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_header_title)

	_alarm_chip = Label.new()
	_alarm_chip.text = "● GEEN STORING"
	_alarm_chip.add_theme_font_size_override("font_size", 14)
	_alarm_chip.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6, 1))
	_alarm_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_alarm_chip)

	_clock_lbl = Label.new()
	_clock_lbl.text = "--:--:--"
	_clock_lbl.add_theme_font_size_override("font_size", 16)
	_clock_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.92, 1))
	_clock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_clock_lbl)

	# ---- Content slot (the glass) ----------------------------------------
	var glass := PanelContainer.new()
	glass.add_theme_stylebox_override("panel", _sb(C_SCREEN, 0, 0))
	glass.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(glass)
	_content = MarginContainer.new()
	_content.add_theme_constant_override("margin_left", 16)
	_content.add_theme_constant_override("margin_right", 16)
	_content.add_theme_constant_override("margin_top", 14)
	_content.add_theme_constant_override("margin_bottom", 14)
	glass.add_child(_content)

	# ---- Footer nav -------------------------------------------------------
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _sb(C_HEADER, 6, 8))
	outer.add_child(footer)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	footer.add_child(frow)
	_nav_btns.clear()
	frow.add_child(_nav_button("HOOFDMENU", Screen.HOOFDMENU))
	frow.add_child(_nav_button("OVERZICHT", Screen.OVERZICHT))
	frow.add_child(_nav_button("STORINGEN", Screen.STORINGEN))
	frow.add_child(_nav_button("HANDBEDIENING", Screen.HANDBEDIENING))
	frow.add_child(_nav_button("MACHINES", Screen.MACHINES))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	frow.add_child(spacer)
	var close_b := _flat_button("AFSLUITEN  ✕", Vector2(120, 42), Color(0.55, 0.20, 0.18, 1), Color.WHITE)
	close_b.pressed.connect(close_overlay)
	frow.add_child(close_b)

func _nav_button(text: String, screen: int) -> Button:
	var b := _flat_button(text, Vector2(150, 42), C_NAV, Color(0.92, 0.95, 0.97, 1))
	b.pressed.connect(_show_screen.bind(screen))
	_nav_btns[screen] = b
	return b

# =============================================================================
# SCREEN ROUTER
# =============================================================================
func _show_screen(screen: int) -> void:
	# If we're invoked before _ready had a chance to build the chrome (headless
	# test harnesses can do this when there's no main scene), build it now so the
	# call doesn't blow up. Production hits this via Hmi.gd well after _ready.
	if _content == null:
		_build_chrome()
	_screen = screen
	# Clear dynamic refs + content
	_stage_tiles.clear()
	_section_tiles.clear()
	_manual_rows.clear()
	_machines_list_rows.clear()
	_md_comp_rows.clear()
	_ov_status = null
	_ov_totals = null
	_start_btn = null
	_stop_btn = null
	_auto_btn = null
	_fault_box = null
	_machines_list_vb = null
	_machines_detail_vb = null
	_md_title_lbl = null
	_md_powered_lamp = null
	_md_status_lbl = null
	_md_buffer_bar = null
	_md_thru_lbl = null
	_md_hand_btn = null
	_md_run_btn = null
	_md_safeguard_lbl = null
	_md_rpm_slider = null
	_md_rpm_pct_lbl = null
	_md_amps_lbl = null
	for c in _content.get_children():
		c.queue_free()
	match screen:
		Screen.HOOFDMENU:     _build_hoofdmenu()
		Screen.OVERZICHT:     _build_overzicht()
		Screen.STORINGEN:     _build_storingen()
		Screen.HANDBEDIENING: _build_handbediening()
		Screen.MACHINES:      _build_machines()
	# Highlight active nav tab
	for s in _nav_btns:
		var btn: Button = _nav_btns[s]
		btn.add_theme_stylebox_override("normal", _sb(C_NAV_SEL if s == screen else C_NAV, 4, 6))
	_refresh()

# =============================================================================
# SCREEN: HOOFDMENU — section dashboard
# =============================================================================
func _build_hoofdmenu() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_content.add_child(v)

	var h := Label.new()
	h.text = "HOOFDMENU — kies een sectie"
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(h)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)

	for s in SECTIONS:
		var tile := _section_tile(String(s["name"]))
		tile["btn"].pressed.connect(_show_screen.bind(Screen.OVERZICHT))
		grid.add_child(tile["btn"])
		_section_tiles.append({"def": s, "lamp": tile["lamp"]})

func _section_tile(tile_name: String) -> Dictionary:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(250, 96)
	btn.add_theme_stylebox_override("normal", _sb(C_TILE, 8, 0, C_TILE_EDGE, 2))
	btn.add_theme_stylebox_override("hover", _sb(Color(0.92, 0.94, 0.92), 8, 0, C_NAV_SEL, 2))
	btn.add_theme_stylebox_override("pressed", _sb(Color(0.80, 0.86, 0.90), 8, 0, C_NAV_SEL, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var lamp := ColorRect.new()
	lamp.custom_minimum_size = Vector2(22, 22)
	lamp.color = LAMP_OFF
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lamp)
	var lbl := Label.new()
	lbl.text = tile_name
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return {"btn": btn, "lamp": lamp}

# =============================================================================
# SCREEN: OVERZICHT — line mimic + master controls
# =============================================================================
func _build_overzicht() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_content.add_child(v)

	_ov_status = Label.new()
	_ov_status.add_theme_font_size_override("font_size", 17)
	_ov_status.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(_ov_status)

	# Mimic: 5 columns x 2 rows of stage tiles
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for st in STAGES:
		var tile := _stage_tile(String(st["name"]))
		grid.add_child(tile["box"])
		_stage_tiles.append({"def": st, "lamp": tile["lamp"], "val": tile["val"]})

	_ov_totals = Label.new()
	_ov_totals.add_theme_font_size_override("font_size", 14)
	_ov_totals.add_theme_color_override("font_color", Color(0.18, 0.22, 0.20, 1))
	v.add_child(_ov_totals)

	# Master control bar
	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 10)
	v.add_child(ctrl)
	_start_btn = _flat_button("▶  START", Vector2(150, 56), LAMP_RUN, Color.WHITE)
	_start_btn.add_theme_font_size_override("font_size", 18)
	_start_btn.pressed.connect(_on_start)
	ctrl.add_child(_start_btn)
	_stop_btn = _flat_button("■  STOP", Vector2(150, 56), LAMP_FAULT, Color.WHITE)
	_stop_btn.add_theme_font_size_override("font_size", 18)
	_stop_btn.pressed.connect(_on_stop)
	ctrl.add_child(_stop_btn)
	var leeg := _flat_button("⧗  LEEGDRAAIEN", Vector2(190, 56), Color(0.72, 0.52, 0.16, 1), Color.WHITE)
	leeg.add_theme_font_size_override("font_size", 16)
	leeg.pressed.connect(_on_leegdraaien)
	ctrl.add_child(leeg)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.add_child(sp)
	_auto_btn = _flat_button("AUTOMAAT", Vector2(170, 56), C_NAV_SEL, Color.WHITE)
	_auto_btn.add_theme_font_size_override("font_size", 16)
	_auto_btn.pressed.connect(_on_toggle_auto)
	ctrl.add_child(_auto_btn)

func _stage_tile(tile_name: String) -> Dictionary:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(150, 84)
	box.add_theme_stylebox_override("panel", _sb(C_TILE, 6, 0, C_TILE_EDGE, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)
	var lamp := ColorRect.new()
	lamp.custom_minimum_size = Vector2(16, 16)
	lamp.color = LAMP_OFF
	top.add_child(lamp)
	var nl := Label.new()
	nl.text = tile_name
	nl.add_theme_font_size_override("font_size", 13)
	nl.add_theme_color_override("font_color", C_TEXT_DARK)
	top.add_child(nl)
	var val := Label.new()
	val.text = "—"
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", Color(0.25, 0.30, 0.27, 1))
	col.add_child(val)
	return {"box": box, "lamp": lamp, "val": val}

# =============================================================================
# SCREEN: STORINGEN — active alarm list
# =============================================================================
func _build_storingen() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_content.add_child(v)

	var h := Label.new()
	h.text = "ACTIEVE STORINGEN"
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(h)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_fault_box = VBoxContainer.new()
	_fault_box.add_theme_constant_override("separation", 6)
	_fault_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fault_box)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 10)
	v.add_child(ctrl)
	var ack := _flat_button("KWITTEREN", Vector2(180, 50), Color(0.20, 0.40, 0.55, 1), Color.WHITE)
	ack.pressed.connect(_on_kwitteren)
	ctrl.add_child(ack)
	var reset := _flat_button("RESETTEN", Vector2(180, 50), Color(0.40, 0.42, 0.45, 1), Color.WHITE)
	reset.pressed.connect(_on_reset_faults)
	ctrl.add_child(reset)

# =============================================================================
# SCREEN: HANDBEDIENING — per-section manual run/stop
# =============================================================================
func _build_handbediening() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_content.add_child(v)

	var h := Label.new()
	h.text = "HANDBEDIENING — alleen actief in HAND-modus"
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(h)

	for s in SECTIONS:
		var sec_name := String(s["name"])
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _sb(C_TILE, 6, 0, C_TILE_EDGE, 1))
		v.add_child(row)
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 12)
		row.add_child(hr)
		var lamp := ColorRect.new()
		lamp.custom_minimum_size = Vector2(18, 18)
		lamp.color = LAMP_OFF
		hr.add_child(lamp)
		var nl := Label.new()
		nl.text = sec_name
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color", C_TEXT_DARK)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(nl)
		var btn := _flat_button("START", Vector2(130, 40), LAMP_RUN, Color.WHITE)
		btn.pressed.connect(_on_manual_toggle.bind(sec_name))
		hr.add_child(btn)
		_manual_rows.append({"section": sec_name, "lamp": lamp, "btn": btn})

# =============================================================================
# CONTROL ACTIONS
# =============================================================================
func _on_start() -> void:
	_leegdraaien = false
	if _line_flow and "feed_enabled" in _line_flow:
		_line_flow.feed_enabled = true
	_refresh()

func _on_stop() -> void:
	_leegdraaien = false
	if _line_flow and "feed_enabled" in _line_flow:
		_line_flow.feed_enabled = false
	_refresh()

func _on_leegdraaien() -> void:
	# Empty-run: stop feeding new material, let what's in the line drain out.
	if _line_flow and "feed_enabled" in _line_flow:
		_line_flow.feed_enabled = false
	_leegdraaien = _in_transit() >= 0.5
	_refresh()

func _on_toggle_auto() -> void:
	_automaat = not _automaat
	_refresh()

func _on_manual_toggle(section: String) -> void:
	if _automaat:
		return                                  # HAND-modus required
	_manual_run[section] = not bool(_manual_run.get(section, false))
	_refresh()

func _on_kwitteren() -> void:
	for f in _compute_faults():
		_acked_faults[String(f["code"])] = true
	_refresh()

func _on_reset_faults() -> void:
	_acked_faults.clear()
	_refresh()

# =============================================================================
# REFRESH (4 Hz) — only the active screen's dynamic widgets
# =============================================================================
func _refresh() -> void:
	# Header clock + title + alarm chip (always)
	var t := Time.get_time_dict_from_system()
	_clock_lbl.text = "%02d:%02d:%02d" % [t["hour"], t["minute"], t["second"]]
	var screen_name : String = ["HOOFDMENU", "OVERZICHT", "STORINGEN", "HANDBEDIENING", "MACHINES"][_screen]
	_header_title.text = "%s  ·  %s" % [_station, screen_name]
	var faults := _compute_faults()
	var unacked := 0
	for f in faults:
		if not _acked_faults.has(String(f["code"])):
			unacked += 1
	if faults.is_empty():
		_alarm_chip.text = "● GEEN STORING"
		_alarm_chip.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6, 1))
	else:
		_alarm_chip.text = "▲ %d STORING%s" % [faults.size(), "EN" if faults.size() != 1 else ""]
		_alarm_chip.add_theme_color_override("font_color", Color(1.0, 0.55, 0.45, 1) if unacked > 0 else C_AMBER)

	match _screen:
		Screen.HOOFDMENU:     _refresh_hoofdmenu(faults)
		Screen.OVERZICHT:     _refresh_overzicht(faults)
		Screen.STORINGEN:     _refresh_storingen(faults)
		Screen.HANDBEDIENING: _refresh_handbediening()
		Screen.MACHINES:      _refresh_machines()

func _refresh_hoofdmenu(faults: Array) -> void:
	for t in _section_tiles:
		(t["lamp"] as ColorRect).color = _lamp_color(_group_status(t["def"]["tokens"], faults))

func _refresh_overzicht(faults: Array) -> void:
	var feed_on := _feed_on()
	if _leegdraaien:
		_ov_status.text = "STATUS:  LEEGDRAAIEN ACTIEF — lijn loopt leeg (%.0f kg in lijn)" % _in_transit()
		_ov_status.add_theme_color_override("font_color", Color(0.62, 0.42, 0.10, 1))
	elif feed_on:
		_ov_status.text = "STATUS:  LOPEND" + ("" if faults.is_empty() else "  ▲ met storing")
		_ov_status.add_theme_color_override("font_color", Color(0.13, 0.42, 0.16, 1))
	else:
		_ov_status.text = "STATUS:  GESTOPT"
		_ov_status.add_theme_color_override("font_color", Color(0.55, 0.20, 0.16, 1))
	for t in _stage_tiles:
		var sc := _stage_status(t["def"]["tokens"], faults)
		(t["lamp"] as ColorRect).color = _lamp_color(sc)
		(t["val"] as Label).text = _stage_value(t["def"]["tokens"])
	_ov_totals.text = "Doorvoer:  gevoed %.0f kg   ·   granulaat %.0f kg   ·   afval %.0f kg   ·   in lijn %.0f kg" \
		% [_fed(), _gran(), _waste(), _in_transit()]
	# Button enable states reflect feed
	_start_btn.disabled = feed_on
	_stop_btn.disabled = not feed_on
	_auto_btn.text = "AUTOMAAT" if _automaat else "HANDBEDIENING"
	_auto_btn.add_theme_stylebox_override("normal", _sb(C_NAV_SEL if _automaat else Color(0.62, 0.45, 0.14, 1), 4, 6))

func _refresh_storingen(faults: Array) -> void:
	if _fault_box == null:
		return
	for c in _fault_box.get_children():
		c.queue_free()
	if faults.is_empty():
		var ok := Label.new()
		ok.text = "Geen actieve storingen."
		ok.add_theme_font_size_override("font_size", 15)
		ok.add_theme_color_override("font_color", Color(0.13, 0.42, 0.16, 1))
		_fault_box.add_child(ok)
		return
	for f in faults:
		var acked := _acked_faults.has(String(f["code"]))
		var line := PanelContainer.new()
		var bg := Color(0.93, 0.86, 0.62, 1) if acked else Color(0.95, 0.74, 0.70, 1)
		line.add_theme_stylebox_override("panel", _sb(bg, 4, 0, Color(0.5, 0.3, 0.25, 1), 1))
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 10)
		line.add_child(hr)
		var dot := Label.new()
		dot.text = "✓" if acked else "▲"
		dot.add_theme_color_override("font_color", Color(0.3, 0.5, 0.2, 1) if acked else Color(0.7, 0.15, 0.1, 1))
		dot.add_theme_font_size_override("font_size", 16)
		hr.add_child(dot)
		var code := Label.new()
		code.text = String(f["code"])
		code.add_theme_font_size_override("font_size", 13)
		code.add_theme_color_override("font_color", Color(0.3, 0.25, 0.2, 1))
		code.custom_minimum_size = Vector2(70, 0)
		hr.add_child(code)
		var txt := Label.new()
		txt.text = String(f["text"]) + ("   (gekwiteerd)" if acked else "")
		txt.add_theme_font_size_override("font_size", 14)
		txt.add_theme_color_override("font_color", C_TEXT_DARK)
		hr.add_child(txt)
		_fault_box.add_child(line)

func _refresh_handbediening() -> void:
	for r in _manual_rows:
		var sec_name := String(r["section"])
		var present := _group_status(_section_def(sec_name)["tokens"]) != ST_OFF
		var on := bool(_manual_run.get(sec_name, false)) and not _automaat
		(r["lamp"] as ColorRect).color = LAMP_RUN if on else (LAMP_IDLE if present else LAMP_OFF)
		var btn: Button = r["btn"]
		btn.disabled = _automaat
		btn.text = "STOP" if on else "START"
		btn.add_theme_stylebox_override("normal", _sb(LAMP_FAULT if on else LAMP_RUN, 4, 6))

# =============================================================================
# SIM QUERIES
# =============================================================================
func _feed_on() -> bool:
	return _line_flow != null and "feed_enabled" in _line_flow and bool(_line_flow.feed_enabled)

func _fed() -> float:
	return float(_line_flow.fed_mass) if (_line_flow and "fed_mass" in _line_flow) else 0.0

func _gran() -> float:
	return float(_line_flow.gran_mass) if (_line_flow and "gran_mass" in _line_flow) else 0.0

func _waste() -> float:
	return float(_line_flow.waste_mass) if (_line_flow and "waste_mass" in _line_flow) else 0.0

func _in_transit() -> float:
	var m := 0.0
	if _line_flow and "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			if nd.has("in"):  m += float(nd["in"].mass_kg)
			if nd.has("out"): m += float(nd["out"].mass_kg)
	return m

## Status for a mimic stage: ST_OFF (no such node), ST_IDLE (present, no
## material), ST_RUN (material flowing), ST_FAULT (matched + active alarm).
func _stage_status(tokens: Array, faults: Array = []) -> int:
	# An active fault scoped to this stage overrides everything → red lamp.
	for f in faults:
		var scope := String(f.get("scope", ""))
		if scope != "" and _id_matches(scope, tokens):
			return ST_FAULT
	if tokens.size() == 1 and String(tokens[0]) == "__sink__":
		return ST_RUN if _gran() > 0.0 else (ST_IDLE if _feed_on() else ST_OFF)
	var present := false
	var active := false
	if _line_flow and "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			if not _id_matches(String(nd.get("id", "")), tokens):
				continue
			present = true
			var m := 0.0
			if nd.has("in"):  m += float(nd["in"].mass_kg)
			if nd.has("out"): m += float(nd["out"].mass_kg)
			if m > 0.01:
				active = true
	if not present:
		return ST_OFF
	if active:
		return ST_RUN
	return ST_IDLE if _feed_on() else ST_IDLE

func _stage_value(tokens: Array) -> String:
	# The line end shows banked granulaat + its run-average melt grade.
	if tokens.size() == 1 and String(tokens[0]) == "__sink__":
		return "%.0f kg\nQ %.0f/100" % [_gran(), _granulaat_quality()]
	var m := _stage_metrics(tokens)
	if not bool(m["found"]):
		return "n.v.t."
	# Line 1: backlog in the buffer + the smoothed throughput leaving the stage.
	var line1 := "%.0f kg  %.1f kg/s" % [float(m["kg"]), float(m["thru"])]
	# Line 2: the extruder reports melt grade; every wet/dry stage reports the two
	# enemies an operator chases — moisture and contamination.
	var line2 := ""
	if "extruder" in tokens:
		line2 = "Q %.0f/100" % float(m["quality"])
	else:
		line2 = "H2O %.0f%%  vuil %.1f%%" % [float(m["moist"]), float(m["contam"])]
	return line1 + "\n" + line2

## Aggregate the live LineFlow telemetry across every node matching `tokens`.
## Moisture/dirt/quality are averaged mass-weighted by throughput (the stream
## that's actually moving), falling back to a plain average when the stage idles.
func _stage_metrics(tokens: Array) -> Dictionary:
	var m := {"found": false, "kg": 0.0, "thru": 0.0, "moist": 0.0, "contam": 0.0, "quality": 0.0}
	if _line_flow == null or not ("_nodes" in _line_flow):
		return m
	var wsum := 0.0
	var moist_w := 0.0
	var contam_w := 0.0
	var qual_w := 0.0
	var n := 0
	var moist_p := 0.0
	var contam_p := 0.0
	var qual_p := 0.0
	for nd in _line_flow._nodes:
		if not _id_matches(String(nd.get("id", "")), tokens):
			continue
		m["found"] = true
		m["kg"]   = float(m["kg"]) + float(nd.get("buffer", 0.0))
		var th := float(nd.get("thru", 0.0))
		m["thru"] = float(m["thru"]) + th
		var mo := float(nd.get("moist", 0.0))
		var co := float(nd.get("contam", 0.0))
		var qu := float(nd.get("quality", 0.0))
		wsum += th
		moist_w += mo * th
		contam_w += co * th
		qual_w += qu * th
		n += 1
		moist_p += mo
		contam_p += co
		qual_p += qu
	if wsum > 0.001:
		m["moist"]   = moist_w / wsum
		m["contam"]  = contam_w / wsum
		m["quality"] = qual_w / wsum
	elif n > 0:
		m["moist"]   = moist_p / n
		m["contam"]  = contam_p / n
		m["quality"] = qual_p / n
	return m

## The material currently queued at the extruder INPUT — i.e. exactly what is
## about to be pelletised. This is the honest "is the melt wet/dirty?" reading.
func _sink_feed() -> Dictionary:
	var r := {"found": false, "moist": 0.0, "contam": 0.0, "kg": 0.0}
	if _line_flow == null or not ("_nodes" in _line_flow):
		return r
	for nd in _line_flow._nodes:
		if String(nd.get("role", "")) != "sink":
			continue
		var b = nd.get("in", null)
		if b != null and b.mass_kg > 0.05:
			r["found"]  = true
			r["moist"]  = b.moisture_pct()
			r["contam"] = b.contam_pct()
			r["kg"]     = b.mass_kg
	return r

func _granulaat_quality() -> float:
	if _line_flow and _line_flow.has_method("granulaat_quality"):
		return float(_line_flow.granulaat_quality())
	return 0.0

func _stage_tokens(stage_name: String) -> Array:
	for st in STAGES:
		if String(st["name"]) == stage_name:
			return st["tokens"]
	return []

func _node_name(id: String) -> String:
	var item := PlaceableCatalog.get_item(id)
	return String(item.get("name", id)) if not item.is_empty() else id

## Section status for dashboards = best status across its matching stages.
func _group_status(tokens: Array, faults: Array = []) -> int:
	for f in faults:
		var scope := String(f.get("scope", ""))
		if scope != "" and _id_matches(scope, tokens):
			return ST_FAULT
	var best := ST_OFF
	if _line_flow and "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			if not _id_matches(String(nd.get("id", "")), tokens):
				continue
			var m := 0.0
			if nd.has("in"):  m += float(nd["in"].mass_kg)
			if nd.has("out"): m += float(nd["out"].mass_kg)
			var sc := ST_RUN if m > 0.01 else ST_IDLE
			if sc > best:
				best = sc
	return best

func _id_matches(id: String, tokens: Array) -> bool:
	for tk in tokens:
		if id.find(String(tk)) != -1:
			return true
	return false

func _section_def(section_name: String) -> Dictionary:
	for s in SECTIONS:
		if String(s["name"]) == section_name:
			return s
	return {"name": section_name, "tokens": []}

## Synthetic-but-honest alarms derived from live sim state. Real plants list
## PLC faults here; the sim doesn't raise them yet, so these reflect operating
## conditions an operator would actually see on this screen.
## Live alarms derived from the running sim. Operating-state alarms (no PLC, no
## feed, empty-run) are line-wide (scope ""); process alarms carry a `scope` token
## naming the machine/stage at fault, so the matching mimic tile lights red.
func _compute_faults() -> Array:
	var out : Array = []
	if _line_flow == null:
		out.append({"code": "PLC-000", "text": "Geen lijn-PLC gekoppeld in deze scene", "scope": ""})
		return out
	# --- operating state ---------------------------------------------------
	if _feed_on() and _no_feed_secs > 3.0:
		out.append({"code": "INV-101", "text": "Geen baal op invoerpunt — lijn vraagt materiaal", "scope": ""})
	if _leegdraaien:
		out.append({"code": "RUN-200", "text": "Leegdraaien actief — geen nieuwe invoer", "scope": ""})

	# --- live process faults from per-machine telemetry --------------------
	# 1) Backlog: material piling up faster than the slowest machine can take it.
	var worst_kg := 0.0
	var worst_id := ""
	if "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			var buf := float(nd.get("buffer", 0.0))
			if buf > worst_kg:
				worst_kg = buf
				worst_id = String(nd.get("id", ""))
	if worst_kg > BUFFER_JAM_KG:
		out.append({"code": "BUF-300",
			"text": "Ophoping bij %s — %.0f kg in buffer, doorvoer geblokkeerd" % [_node_name(worst_id), worst_kg],
			"scope": worst_id})

	# 2) Wet melt: what's queued at the extruder is too wet → drying underperforms.
	var feed := _sink_feed()
	if bool(feed["found"]) and float(feed["moist"]) > DRYER_WET_PCT:
		out.append({"code": "DRG-310",
			"text": "Droger: restvocht %.0f%% — extruder krijgt nat materiaal" % float(feed["moist"]),
			"scope": "dryer"})
	# 3) Dirty melt: contamination carried into the extruder → wash underperforms.
	if bool(feed["found"]) and float(feed["contam"]) > MELT_DIRT_PCT:
		out.append({"code": "VUIL-420",
			"text": "Smelt te vuil (%.1f%%) — controleer wasrendement" % float(feed["contam"]),
			"scope": "extruder"})

	# 4) Off-spec granulaat: the run-average melt grade has dropped below norm.
	var q := _granulaat_quality()
	if _gran() > 0.0 and q < QUALITY_MIN:
		out.append({"code": "QUA-400",
			"text": "Granulaatkwaliteit %.0f/100 onder norm (min %d)" % [q, int(QUALITY_MIN)],
			"scope": "__sink__"})
	return out

# =============================================================================
# HELPERS
# =============================================================================
func _lamp_color(status: int) -> Color:
	match status:
		ST_RUN:   return LAMP_RUN
		ST_IDLE:  return LAMP_IDLE
		ST_FAULT: return LAMP_FAULT
		_:        return LAMP_OFF

func _flat_button(text: String, min_size: Vector2, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.45))
	b.add_theme_stylebox_override("normal", _sb(bg, 4, 6))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.10), 4, 6))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.15), 4, 6))
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.35), 4, 6))
	return b

func _sb(bg: Color, radius: int, margin: int, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if margin > 0:
		s.content_margin_left = margin
		s.content_margin_right = margin
		s.content_margin_top = margin * 0.6
		s.content_margin_bottom = margin * 0.6
	if border_w > 0:
		s.border_width_left = border_w
		s.border_width_right = border_w
		s.border_width_top = border_w
		s.border_width_bottom = border_w
		s.border_color = border
	return s

# =============================================================================
# SCREEN: MACHINES — per-machine HMI (overview + click-drill detail)
# =============================================================================
## Two-column screen: scrollable list of every LineFlow machine on the left,
## the selected machine's live detail panel on the right (HAND/AUTO toggle, ON/
## OFF, fill bar, master RPM%, per-component RPM sliders + live RPM readouts).
## HAND mode bypasses the PLC + safeguards so the operator can start any
## component (or a whole tank) directly — at their own responsibility.
func _build_machines() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(h)

	# Left: machine list
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(280, 0)
	h.add_child(left)
	var lh := Label.new()
	lh.text = "MACHINES"
	lh.add_theme_font_size_override("font_size", 15)
	lh.add_theme_color_override("font_color", C_TEXT_DARK)
	left.add_child(lh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_machines_list_vb = VBoxContainer.new()
	_machines_list_vb.add_theme_constant_override("separation", 4)
	_machines_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_machines_list_vb)
	_populate_machine_list()

	# Right: detail panel for the selected machine
	_machines_detail_vb = VBoxContainer.new()
	_machines_detail_vb.add_theme_constant_override("separation", 8)
	_machines_detail_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_machines_detail_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_machines_detail_vb)
	# Pick an initial selection if none yet (and the line has machines).
	if _selected_machine_id == "" and _line_flow != null and _line_flow.has_method("machine_list"):
		var ml: Array = _line_flow.call("machine_list")
		if not ml.is_empty():
			_selected_machine_id = String(ml[0]["id"])
	_build_machine_detail()

func _populate_machine_list() -> void:
	for c in _machines_list_vb.get_children():
		c.queue_free()
	_machines_list_rows.clear()
	if _line_flow == null or not _line_flow.has_method("machine_list"):
		var empty := Label.new()
		empty.text = "(geen machines)"
		empty.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_list_vb.add_child(empty)
		return
	for m in _line_flow.call("machine_list"):
		var mid := String(m["id"])
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 32)
		btn.text = ""    # filled by children
		btn.add_theme_stylebox_override("normal",
			_sb(C_TILE if mid != _selected_machine_id else C_NAV_SEL, 4, 0, C_TILE_EDGE, 1))
		btn.add_theme_stylebox_override("hover",
			_sb(C_NAV_SEL.lightened(0.08), 4, 0, C_NAV_SEL, 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(row)
		var lamp := ColorRect.new()
		lamp.custom_minimum_size = Vector2(14, 14)
		lamp.color = LAMP_OFF
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lamp)
		var lbl := Label.new()
		lbl.text = mid.replace("_", " ")
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color",
			C_TEXT_DARK if mid != _selected_machine_id else Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		btn.pressed.connect(_on_machine_picked.bind(mid))
		_machines_list_vb.add_child(btn)
		_machines_list_rows.append({"id": mid, "btn": btn, "lamp": lamp, "lbl": lbl})

func _on_machine_picked(id: String) -> void:
	_selected_machine_id = id
	# Rebuild the list (so the selection highlight is correct) and the right pane.
	if _machines_list_vb != null:
		_populate_machine_list()
	_build_machine_detail()

## (Re)build the right-hand detail pane for `_selected_machine_id`. Called on
## selection change. Live values are refreshed by _refresh_machines().
func _build_machine_detail() -> void:
	if _machines_detail_vb == null:
		return
	for c in _machines_detail_vb.get_children():
		c.queue_free()
	_md_comp_rows.clear()
	_md_title_lbl = null
	_md_powered_lamp = null
	_md_status_lbl = null
	_md_buffer_bar = null
	_md_thru_lbl = null
	_md_hand_btn = null
	_md_run_btn = null
	_md_safeguard_lbl = null
	_md_rpm_slider = null
	_md_rpm_pct_lbl = null
	_md_amps_lbl = null

	if _selected_machine_id == "":
		var hint := Label.new()
		hint.text = "Selecteer een machine links."
		hint.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_detail_vb.add_child(hint)
		return
	if _line_flow == null or not _line_flow.has_method("get_machine_info"):
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_id)
	if info.is_empty():
		var miss := Label.new()
		miss.text = "Machine '%s' niet gevonden (niet meer op de lijn?)" % _selected_machine_id
		miss.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_detail_vb.add_child(miss)
		return

	# Title row: name + powered lamp + status
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	_machines_detail_vb.add_child(trow)
	_md_powered_lamp = ColorRect.new()
	_md_powered_lamp.custom_minimum_size = Vector2(18, 18)
	_md_powered_lamp.color = LAMP_OFF
	trow.add_child(_md_powered_lamp)
	_md_title_lbl = Label.new()
	_md_title_lbl.text = String(info["id"]).replace("_", " ").to_upper()
	_md_title_lbl.add_theme_font_size_override("font_size", 18)
	_md_title_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	trow.add_child(_md_title_lbl)
	_md_status_lbl = Label.new()
	_md_status_lbl.add_theme_font_size_override("font_size", 13)
	_md_status_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.27, 1))
	trow.add_child(_md_status_lbl)
	# Live current draw — a paddle spinning empty still pulls ~35% nominal (motor
	# idle floor), which is the energy cost the operator was asking to see.
	_md_amps_lbl = Label.new()
	_md_amps_lbl.text = "0 A"
	_md_amps_lbl.add_theme_font_size_override("font_size", 13)
	_md_amps_lbl.add_theme_color_override("font_color", C_AMBER)
	trow.add_child(_md_amps_lbl)

	# HAND / AUTO + RUN row
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	_machines_detail_vb.add_child(crow)
	_md_hand_btn = _flat_button("AUTOMAAT", Vector2(150, 38), C_NAV_SEL, Color.WHITE)
	_md_hand_btn.pressed.connect(_on_machine_toggle_hand)
	crow.add_child(_md_hand_btn)
	_md_run_btn = _flat_button("AAN/UIT", Vector2(120, 38), Color(0.40, 0.42, 0.45, 1), Color.WHITE)
	_md_run_btn.pressed.connect(_on_machine_toggle_run)
	crow.add_child(_md_run_btn)
	_md_safeguard_lbl = Label.new()
	_md_safeguard_lbl.text = ""
	_md_safeguard_lbl.add_theme_font_size_override("font_size", 13)
	_md_safeguard_lbl.add_theme_color_override("font_color", LAMP_FAULT)
	crow.add_child(_md_safeguard_lbl)

	# Buffer / fill bar + throughput
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	_machines_detail_vb.add_child(brow)
	var blbl := Label.new()
	blbl.text = "Vul / buffer"
	blbl.custom_minimum_size = Vector2(110, 0)
	blbl.add_theme_color_override("font_color", C_TEXT_DARK)
	brow.add_child(blbl)
	_md_buffer_bar = ProgressBar.new()
	_md_buffer_bar.min_value = 0.0
	_md_buffer_bar.max_value = 250.0    # OVERLOAD_KG; visually saturates near e-stop
	_md_buffer_bar.value = 0.0
	_md_buffer_bar.custom_minimum_size = Vector2(0, 22)
	_md_buffer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(_md_buffer_bar)
	_md_thru_lbl = Label.new()
	_md_thru_lbl.text = "—"
	_md_thru_lbl.add_theme_font_size_override("font_size", 13)
	_md_thru_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	_md_thru_lbl.custom_minimum_size = Vector2(150, 0)
	brow.add_child(_md_thru_lbl)

	# Master RPM% slider
	_machines_detail_vb.add_child(_md_make_rpm_row("RPM (master)", "__master__", float(info.get("rpm_pct", 1.0)),
		float(info.get("rate", 0.0)), float(info.get("spin", 0.0))))

	# Per-component RPM sliders (inlet / transport / outlet for tanks; drive
	# for conveyors + ventilators; rotor for shredders/mills)
	var comps : Dictionary = info.get("components", {})
	for cname in comps.keys():
		var row := _md_make_rpm_row(String(cname).replace("_", " "), String(cname),
			float(comps[cname]), float(info.get("rate", 0.0)), float(info.get("spin", 0.0)))
		_machines_detail_vb.add_child(row)

	# Spacer at the bottom so the panel reads cleanly.
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_machines_detail_vb.add_child(sp)

func _md_make_rpm_row(label_text: String, comp_key: String, pct: float, design_rate: float, spin: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = pct
	slider.custom_minimum_size = Vector2(0, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var pct_lbl := Label.new()
	pct_lbl.text = "%d %%" % int(round(pct * 100.0))
	pct_lbl.custom_minimum_size = Vector2(60, 0)
	pct_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	pct_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(pct_lbl)
	var rpm_lbl := Label.new()
	# Live RPM readout — the ROTOR speed the operator's setting commands,
	# INDEPENDENT of material. A paddle spinning at full RPM with no inflow still
	# reads its full RPM here (and still draws idle current, shown up top).
	rpm_lbl.text = "— RPM"
	rpm_lbl.custom_minimum_size = Vector2(100, 0)
	rpm_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.27, 1))
	rpm_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(rpm_lbl)
	# Wire the slider write-back. __master__ goes to set_machine_rpm_pct; component
	# keys go to set_machine_component_pct.
	if comp_key == "__master__":
		slider.value_changed.connect(_on_master_rpm_changed)
		_md_rpm_slider = slider
		_md_rpm_pct_lbl = pct_lbl
	else:
		slider.value_changed.connect(_on_component_rpm_changed.bind(comp_key))
		_md_comp_rows.append({
			"name": comp_key, "slider": slider, "pct_lbl": pct_lbl, "rpm_lbl": rpm_lbl,
			"nom_rpm": _nominal_rpm_for(comp_key),
		})
	return row

func _on_machine_toggle_hand() -> void:
	if _line_flow == null or _selected_machine_id == "":
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_id)
	var was_hand := bool(info.get("hand_mode", false))
	_line_flow.call("set_machine_hand_mode", _selected_machine_id, not was_hand)

func _on_machine_toggle_run() -> void:
	if _line_flow == null or _selected_machine_id == "":
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_id)
	if not bool(info.get("hand_mode", false)):
		return   # AAN/UIT only works in HAND mode (PLC owns it in AUTO)
	var was_on := bool(info.get("manual_on", false))
	_line_flow.call("set_machine_manual_on", _selected_machine_id, not was_on)

func _on_master_rpm_changed(value: float) -> void:
	if _line_flow == null or _selected_machine_id == "":
		return
	_line_flow.call("set_machine_rpm_pct", _selected_machine_id, value)

func _on_component_rpm_changed(value: float, comp_key: String) -> void:
	if _line_flow == null or _selected_machine_id == "":
		return
	_line_flow.call("set_machine_component_pct", _selected_machine_id, comp_key, value)

## 4 Hz live refresh of the MACHINES screen (list lamps + detail panel readouts).
func _refresh_machines() -> void:
	if _line_flow == null or not _line_flow.has_method("get_machine_info"):
		return
	# Update the list-row lamps (live powered state).
	for r in _machines_list_rows:
		var li : Dictionary = _line_flow.call("get_machine_info", String(r["id"]))
		if li.is_empty():
			continue
		var c : Color = LAMP_OFF
		if bool(li.get("powered", false)) and float(li.get("spin", 0.0)) > 0.05:
			c = LAMP_RUN
		elif float(li.get("buffer", 0.0)) > 1.0:
			c = LAMP_IDLE
		(r["lamp"] as ColorRect).color = c
	# Update the detail panel.
	if _md_title_lbl == null or _selected_machine_id == "":
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_id)
	if info.is_empty():
		return
	var hand := bool(info.get("hand_mode", false))
	var powered := bool(info.get("powered", false))
	var manual_on := bool(info.get("manual_on", false))
	var spin := float(info.get("spin", 0.0))
	var buffer := float(info.get("buffer", 0.0))
	var thru := float(info.get("thru", 0.0))
	var rate := float(info.get("rate", 0.0))
	_md_powered_lamp.color = LAMP_RUN if (powered and spin > 0.05) else (LAMP_IDLE if buffer > 1.0 else LAMP_OFF)
	_md_status_lbl.text = "%.1f%% spin · %.1f kg buffer · %.2f kg/s" % [spin * 100.0, buffer, thru]
	_md_hand_btn.text = ("HAND  ●" if hand else "AUTOMAAT")
	_md_hand_btn.add_theme_stylebox_override("normal",
		_sb(Color(0.72, 0.52, 0.16, 1) if hand else C_NAV_SEL, 4, 6))
	_md_run_btn.text = ("AAN" if manual_on else "UIT")
	_md_run_btn.add_theme_stylebox_override("normal",
		_sb(LAMP_RUN if (hand and manual_on) else Color(0.40, 0.42, 0.45, 1), 4, 6))
	_md_run_btn.disabled = not hand
	_md_safeguard_lbl.text = "⚠ Beveiligingen overruled (HAND)" if hand else ""
	_md_buffer_bar.value = clampf(buffer, 0.0, _md_buffer_bar.max_value)
	# Throughput / rate
	_md_thru_lbl.text = "%.2f / %.2f kg/s" % [thru, rate]
	# Master RPM label
	var mpct := float(info.get("rpm_pct", 1.0))
	if _md_rpm_pct_lbl != null:
		_md_rpm_pct_lbl.text = "%d %%" % int(round(mpct * 100.0))
	# Live current — non-zero whenever the rotor is spinning (even starved), which is
	# the energy cost the operator was asking to see for "spinning empty."
	if _md_amps_lbl != null:
		var amps := float(info.get("amps", 0.0))
		_md_amps_lbl.text = "Stroom: %.1f A" % amps
	# Per-component readouts: RPM is the rotor's ACTUAL speed (independent of
	# material) — nominal × spin × master_pct × this_component_pct.
	var comps : Dictionary = info.get("components", {})
	for r in _md_comp_rows:
		var cname := String(r["name"])
		if not comps.has(cname):
			continue
		var cpct := float(comps[cname])
		var nom_rpm := float(r.get("nom_rpm", 100.0))
		var actual_rpm : float = nom_rpm * spin * cpct * mpct
		(r["pct_lbl"] as Label).text = "%d %%" % int(round(cpct * 100.0))
		(r["rpm_lbl"] as Label).text = "%.0f RPM" % actual_rpm
