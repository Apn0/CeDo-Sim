extends Control
class_name WashingScope

## SOAO "Colm-Recycling Process Overview" — Washing line operator panel.
##
## Reference photo: washing_3A.png (SOAO vendor screen, brand-yellow on dark blue).
##
## Scope: hmi_washing_all (see src/build/HmiScopes.gd:121).  This Control is
## a self-contained scope-specific screen module — the first one in
## src/scenes/hud/scopes/.  Instantiate it inside HmiOverlay's _build_<screen>()
## branch and call bind(scope, line_flow) once the LineFlow handle is known.
##
## Layout (top → bottom):
##   - Title bar       "Colm-Recycling Process Overview" + AUTO / HAND toggle
##                     + small "SOAO" vendor mark in the corner
##   - Red banner      "Tijdens starten hoort de doseerschroef M1A op 0% te staan."
##   - Main P&ID strip Input → Dosing → Flotation → Centrifuge → Dryers → Output
##                     (flat rectangles, green when running, grey when stopped)
##   - Left M1A panel  Big % SpinBox/Slider + START button, START disabled until
##                     the slider reads 0.0 %.  Emits m1a_start_pressed() then.
##   - Right stats     Vertical column of 6 numeric readouts (TODO bind to model)
##   - Bottom tabs     Trends / Alarma / Prc... / Settings / Operator
##
## Wiring contract (kept loose so HmiOverlay doesn't need to know about the
## internals):
##   var w := WashingScope.new()
##   w.bind(scope_dict, line_flow_node)   # both optional, see bind() doc
##   w.request_close.connect(_on_close)
##   w.m1a_start_pressed.connect(_on_m1a_start)
##   _content.add_child(w)
##
## No real model binding yet — the right-column stats are seeded with example
## values from the photo and tagged TODO for the eventual washing-model hookup.
## The M1A slider IS live (player drags it, START enables at 0 %).

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal request_close()
signal m1a_start_pressed()

# ---------------------------------------------------------------------------
# Exports
# ---------------------------------------------------------------------------

## Which physical washing line this panel is showing.  Stamped on the title
## bar and forwarded to the model layer when the binding lands.
@export var line_id : String = "3A"

# ---------------------------------------------------------------------------
# SOAO palette (sampled from washing_3A.png)
# ---------------------------------------------------------------------------

const C_BG        : Color = Color(0.10, 0.22, 0.45, 1.0)   # process-screen blue
const C_BG_DARK   : Color = Color(0.06, 0.14, 0.30, 1.0)   # banner / panel sink
const C_PANEL     : Color = Color(0.14, 0.28, 0.52, 1.0)   # raised panel tile
const C_PANEL_EDGE: Color = Color(0.05, 0.10, 0.22, 1.0)
const C_GREY_OFF  : Color = Color(0.65, 0.65, 0.65, 1.0)   # stopped P&ID block
const C_GREEN_RUN : Color = Color(0.30, 0.85, 0.30, 1.0)   # running P&ID block
const C_RED_WARN  : Color = Color(0.92, 0.20, 0.20, 1.0)   # startup-rule banner
const C_AMBER     : Color = Color(1.00, 0.78, 0.10, 1.0)   # SOAO brand mark
const C_TEXT      : Color = Color(0.95, 0.96, 0.98, 1.0)
const C_TEXT_DIM  : Color = Color(0.70, 0.78, 0.90, 1.0)
const C_TAB_BG    : Color = Color(0.08, 0.18, 0.36, 1.0)
const C_TAB_SEL   : Color = Color(0.20, 0.40, 0.70, 1.0)

# ---------------------------------------------------------------------------
# P&ID stages — left → right, exactly as drawn on the SOAO photo
# ---------------------------------------------------------------------------

const STAGES : Array = [
	{"name": "INPUT",      "running": true},
	{"name": "DOSING",     "running": true},
	{"name": "FLOTATION",  "running": true},
	{"name": "CENTRIFUGE", "running": false},
	{"name": "DRYERS",     "running": false},
	{"name": "OUTPUT",     "running": false},
]

# ---------------------------------------------------------------------------
# Stats column rows — label, example value, unit.  TODO replace with live
# values pulled from the washing model once that exists.
# ---------------------------------------------------------------------------

const STAT_ROWS : Array = [
	{"key": "dosing_pct",   "label": "Dosing schroef", "value": 19.4,  "unit": "%",   "fmt": "%.1f"},
	{"key": "poeder_rpm",   "label": "Poeder M2",      "value": 32.2,  "unit": "RPM", "fmt": "%.1f"},
	{"key": "sd_ratio",     "label": "S/D ratio",      "value": 13.0,  "unit": "ppm", "fmt": "%.0f"},
	{"key": "proces",       "label": "Proces",         "value": 0.0,   "unit": "",    "fmt": "%.1f"},
	{"key": "temp_water",   "label": "Temp water",     "value": -17.3, "unit": "%",   "fmt": "%.1f"},
	{"key": "comp_a",       "label": "Composite A",    "value": 6.0,   "unit": "",    "fmt": "%.1f"},
	{"key": "comp_b",       "label": "Composite B",    "value": 18.0,  "unit": "%",   "fmt": "%.1f"},
]

# ---------------------------------------------------------------------------
# Operator mode
# ---------------------------------------------------------------------------

enum Mode { AUTO, HAND }

# ---------------------------------------------------------------------------
# Mutable state (everything below is bind()/UI-callback driven)
# ---------------------------------------------------------------------------

var _scope     : Dictionary = {}
var _line_flow : Node       = null

var _mode : int   = Mode.AUTO
var _m1a_value : float = 19.4   # seeded from photo; player can drag to 0.0
var _stats : Dictionary = {}    # key → current numeric value

# Cached node refs (populated in _build_*)
var _mode_auto_btn  : Button       = null
var _mode_hand_btn  : Button       = null
var _m1a_slider     : HSlider      = null
var _m1a_spinbox    : SpinBox      = null
var _m1a_start_btn  : Button       = null
var _stat_labels    : Dictionary   = {}   # key → Label (right column readout)
var _stage_blocks   : Array        = []   # ColorRect per STAGES entry
var _tabs           : TabContainer = null

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	# Fill whatever container drops us in (typically HmiOverlay._content,
	# a MarginContainer).
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(960, 540)
	mouse_filter = Control.MOUSE_FILTER_STOP
	# Seed stat dict from STAT_ROWS defaults
	for row in STAT_ROWS:
		_stats[row["key"]] = float(row["value"])
	_build_ui()
	_refresh()

## Wire the scope-dict + LineFlow node.  Both are optional — the panel renders
## with example values when called with empty args, which is the current state
## (no washing model wired yet).
func bind(scope: Dictionary = {}, line_flow: Node = null) -> void:
	_scope = scope.duplicate(true) if not scope.is_empty() else {}
	_line_flow = line_flow
	# Future: pull live values out of _line_flow / a washing model here and
	# write them into _stats, then call _refresh().
	_refresh()

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	# Background
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 8)
	# Outer breathing room
	root.offset_left = 12
	root.offset_top = 10
	root.offset_right = -12
	root.offset_bottom = -10
	add_child(root)

	_build_title_bar(root)
	_build_startup_banner(root)
	_build_main_split(root)
	_build_bottom_tabs(root)

# --- Title bar ---------------------------------------------------------------

func _build_title_bar(parent: Container) -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	bar.custom_minimum_size = Vector2(0, 36)
	parent.add_child(bar)

	# Vendor stamp (top-left small)
	var vendor := Label.new()
	vendor.text = "SOAO"
	vendor.add_theme_color_override("font_color", C_AMBER)
	vendor.add_theme_font_size_override("font_size", 14)
	bar.add_child(vendor)

	var title := Label.new()
	title.text = "Colm-Recycling Process Overview"
	title.add_theme_color_override("font_color", C_TEXT)
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bar.add_child(title)

	# Line tag (e.g. "LIJN 3A")
	var line_lbl := Label.new()
	line_lbl.text = "LIJN %s" % line_id
	line_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	line_lbl.add_theme_font_size_override("font_size", 14)
	bar.add_child(line_lbl)

	# AUTO / HAND toggle
	_mode_auto_btn = Button.new()
	_mode_auto_btn.text = "AUTO"
	_mode_auto_btn.toggle_mode = true
	_mode_auto_btn.button_pressed = (_mode == Mode.AUTO)
	_mode_auto_btn.custom_minimum_size = Vector2(72, 32)
	_mode_auto_btn.pressed.connect(func(): _set_mode(Mode.AUTO))
	bar.add_child(_mode_auto_btn)

	_mode_hand_btn = Button.new()
	_mode_hand_btn.text = "HAND"
	_mode_hand_btn.toggle_mode = true
	_mode_hand_btn.button_pressed = (_mode == Mode.HAND)
	_mode_hand_btn.custom_minimum_size = Vector2(72, 32)
	_mode_hand_btn.pressed.connect(func(): _set_mode(Mode.HAND))
	bar.add_child(_mode_hand_btn)

	# Close (X) — fires request_close so HmiOverlay can route it
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 32)
	close_btn.pressed.connect(func(): request_close.emit())
	bar.add_child(close_btn)

# --- Red startup banner ------------------------------------------------------

func _build_startup_banner(parent: Container) -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 28)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BG_DARK
	sb.border_color = C_RED_WARN
	sb.border_width_left = 4
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)

	var lbl := Label.new()
	lbl.text = "Tijdens starten hoort de doseerschroef M1A op 0% te staan."
	lbl.add_theme_color_override("font_color", C_RED_WARN)
	lbl.add_theme_font_size_override("font_size", 13)
	pc.add_child(lbl)

# --- Main split (P&ID + M1A widget + stats) ----------------------------------

func _build_main_split(parent: Container) -> void:
	var middle := HBoxContainer.new()
	middle.add_theme_constant_override("separation", 10)
	middle.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(middle)

	# Left column = P&ID strip on top + M1A widget below
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	middle.add_child(left)

	_build_pid_strip(left)
	_build_m1a_widget(left)

	# Right column = stats panel
	_build_stats_column(middle)

# --- P&ID stage strip --------------------------------------------------------

func _build_pid_strip(parent: Container) -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 110)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_PANEL_EDGE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	pc.add_child(row)

	_stage_blocks.clear()
	for i in STAGES.size():
		var stage : Dictionary = STAGES[i]
		# Block tile
		var tile := PanelContainer.new()
		tile.custom_minimum_size = Vector2(110, 70)
		var tsb := StyleBoxFlat.new()
		tsb.bg_color = C_GREEN_RUN if bool(stage["running"]) else C_GREY_OFF
		tsb.border_color = C_PANEL_EDGE
		tsb.border_width_left = 1
		tsb.border_width_top = 1
		tsb.border_width_right = 1
		tsb.border_width_bottom = 1
		tile.add_theme_stylebox_override("panel", tsb)
		var name_lbl := Label.new()
		name_lbl.text = String(stage["name"])
		name_lbl.add_theme_color_override("font_color", Color.BLACK)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tile.add_child(name_lbl)
		row.add_child(tile)
		# Store the StyleBoxFlat so we can recolour in _refresh()
		_stage_blocks.append({"tile": tile, "style": tsb})

		# Arrow connector (skip after the last stage)
		if i < STAGES.size() - 1:
			var arrow := Label.new()
			arrow.text = ">"
			arrow.add_theme_color_override("font_color", C_TEXT)
			arrow.add_theme_font_size_override("font_size", 22)
			row.add_child(arrow)

# --- M1A doseerschroef widget ------------------------------------------------

func _build_m1a_widget(parent: Container) -> void:
	var pc := PanelContainer.new()
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_PANEL_EDGE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	pc.add_child(col)

	var head := Label.new()
	head.text = "M1A  DOSEERSCHROEF"
	head.add_theme_color_override("font_color", C_TEXT)
	head.add_theme_font_size_override("font_size", 15)
	col.add_child(head)

	# Slider + SpinBox on one row so a precise value is reachable.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)

	_m1a_slider = HSlider.new()
	_m1a_slider.min_value = 0.0
	_m1a_slider.max_value = 100.0
	_m1a_slider.step = 0.1
	_m1a_slider.value = _m1a_value
	_m1a_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_m1a_slider.custom_minimum_size = Vector2(0, 28)
	_m1a_slider.value_changed.connect(_on_m1a_slider_changed)
	row.add_child(_m1a_slider)

	_m1a_spinbox = SpinBox.new()
	_m1a_spinbox.min_value = 0.0
	_m1a_spinbox.max_value = 100.0
	_m1a_spinbox.step = 0.1
	_m1a_spinbox.value = _m1a_value
	_m1a_spinbox.suffix = "%"
	_m1a_spinbox.custom_minimum_size = Vector2(96, 28)
	_m1a_spinbox.value_changed.connect(_on_m1a_spinbox_changed)
	row.add_child(_m1a_spinbox)

	# START button — disabled until the slider value reads 0.0 %.
	_m1a_start_btn = Button.new()
	_m1a_start_btn.text = "START"
	_m1a_start_btn.custom_minimum_size = Vector2(0, 36)
	_m1a_start_btn.pressed.connect(_on_m1a_start_pressed)
	col.add_child(_m1a_start_btn)

	var hint := Label.new()
	hint.text = "(START werkt alleen wanneer M1A op 0,0 % staat)"
	hint.add_theme_color_override("font_color", C_TEXT_DIM)
	hint.add_theme_font_size_override("font_size", 11)
	col.add_child(hint)

# --- Right stats column ------------------------------------------------------

func _build_stats_column(parent: Container) -> void:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(260, 0)
	pc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	sb.border_color = C_PANEL_EDGE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	pc.add_theme_stylebox_override("panel", sb)
	parent.add_child(pc)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	pc.add_child(col)

	var head := Label.new()
	head.text = "PROCESS VALUES"
	head.add_theme_color_override("font_color", C_TEXT)
	head.add_theme_font_size_override("font_size", 14)
	col.add_child(head)
	col.add_child(HSeparator.new())

	_stat_labels.clear()
	for row_def in STAT_ROWS:
		var key : String = String(row_def["key"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		var name_lbl := Label.new()
		name_lbl.text = String(row_def["label"])
		name_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		name_lbl.add_theme_font_size_override("font_size", 13)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(name_lbl)
		var val_lbl := Label.new()
		val_lbl.add_theme_color_override("font_color", C_AMBER)
		val_lbl.add_theme_font_size_override("font_size", 14)
		val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val_lbl.custom_minimum_size = Vector2(80, 0)
		row.add_child(val_lbl)
		var unit_lbl := Label.new()
		unit_lbl.text = String(row_def["unit"])
		unit_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
		unit_lbl.add_theme_font_size_override("font_size", 12)
		unit_lbl.custom_minimum_size = Vector2(36, 0)
		row.add_child(unit_lbl)
		_stat_labels[key] = {"value": val_lbl, "fmt": String(row_def["fmt"])}

# --- Bottom tabs -------------------------------------------------------------

func _build_bottom_tabs(parent: Container) -> void:
	_tabs = TabContainer.new()
	_tabs.custom_minimum_size = Vector2(0, 130)
	_tabs.tabs_visible = true
	_tabs.tab_alignment = TabBar.ALIGNMENT_LEFT
	parent.add_child(_tabs)

	_add_tab("Trends",    "Live trends niet beschikbaar (waslijn model ontbreekt).")
	_add_tab("Alarma",    "Geen actieve storingen op de waslijn.")
	_add_tab("Prc...",    "Procedures: opstart, doseren, reinigen — placeholder.")
	_add_tab("Settings",  "Setpoints + grenswaarden — placeholder.")
	_add_tab("Operator",  "Operator notities en log — placeholder.")

func _add_tab(title: String, body: String) -> void:
	var page := MarginContainer.new()
	page.add_theme_constant_override("margin_left", 12)
	page.add_theme_constant_override("margin_right", 12)
	page.add_theme_constant_override("margin_top", 8)
	page.add_theme_constant_override("margin_bottom", 8)
	page.name = title
	var lbl := Label.new()
	lbl.text = body
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 12)
	lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	page.add_child(lbl)
	_tabs.add_child(page)

# ---------------------------------------------------------------------------
# Refresh — repaints colour state + label text from internal vars.
# Cheap; safe to call from bind() or signal handlers.
# ---------------------------------------------------------------------------

func _refresh() -> void:
	# Stat readouts
	for key in _stat_labels.keys():
		var entry : Dictionary = _stat_labels[key]
		var v : float = float(_stats.get(key, 0.0))
		var lbl : Label = entry["value"]
		var fmt : String = String(entry["fmt"])
		lbl.text = fmt % v
	# AUTO / HAND mirror
	if _mode_auto_btn != null:
		_mode_auto_btn.button_pressed = (_mode == Mode.AUTO)
	if _mode_hand_btn != null:
		_mode_hand_btn.button_pressed = (_mode == Mode.HAND)
	# M1A widgets
	if _m1a_slider != null and not is_equal_approx(_m1a_slider.value, _m1a_value):
		_m1a_slider.set_value_no_signal(_m1a_value)
	if _m1a_spinbox != null and not is_equal_approx(_m1a_spinbox.value, _m1a_value):
		_m1a_spinbox.set_value_no_signal(_m1a_value)
	if _m1a_start_btn != null:
		_m1a_start_btn.disabled = not _m1a_can_start()
	# Stage colours (in case some external caller flips a stage running flag
	# in the future — currently the STAGES constant is the source of truth).
	for i in _stage_blocks.size():
		var stage : Dictionary = STAGES[i]
		var entry : Dictionary = _stage_blocks[i]
		var style : StyleBoxFlat = entry["style"]
		style.bg_color = C_GREEN_RUN if bool(stage["running"]) else C_GREY_OFF

# ---------------------------------------------------------------------------
# Callbacks
# ---------------------------------------------------------------------------

func _set_mode(m: int) -> void:
	_mode = m
	_refresh()

func _on_m1a_slider_changed(v: float) -> void:
	_m1a_value = v
	if _m1a_spinbox != null:
		_m1a_spinbox.set_value_no_signal(v)
	if _m1a_start_btn != null:
		_m1a_start_btn.disabled = not _m1a_can_start()
	# Mirror onto the stats panel — the "Dosing schroef" row tracks M1A.
	_stats["dosing_pct"] = v
	if _stat_labels.has("dosing_pct"):
		var entry : Dictionary = _stat_labels["dosing_pct"]
		(entry["value"] as Label).text = String(entry["fmt"]) % v

func _on_m1a_spinbox_changed(v: float) -> void:
	_m1a_value = v
	if _m1a_slider != null:
		_m1a_slider.set_value_no_signal(v)
	if _m1a_start_btn != null:
		_m1a_start_btn.disabled = not _m1a_can_start()
	_stats["dosing_pct"] = v
	if _stat_labels.has("dosing_pct"):
		var entry : Dictionary = _stat_labels["dosing_pct"]
		(entry["value"] as Label).text = String(entry["fmt"]) % v

func _on_m1a_start_pressed() -> void:
	if not _m1a_can_start():
		return
	m1a_start_pressed.emit()

func _m1a_can_start() -> bool:
	return absf(_m1a_value) < 0.05   # treat sub-0.05 % as "0 %"

# ---------------------------------------------------------------------------
# Input — Esc / ui_cancel closes (HmiOverlay also catches this, but having a
# local handler means this Control works in isolation too).
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		request_close.emit()
		accept_event()
