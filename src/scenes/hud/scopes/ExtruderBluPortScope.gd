extends Control
class_name ExtruderBluPortScope

## EREMA BluPort scope screen for LINE 3C / LINE 6 extruders.
##
## Replicates the in-plant SCADA panel pictured in 3C_extruder_hmi.png and
## 6_extruder_HMI.png. This is a fully procedural Control — no .tscn — built
## the same way every other HUD in this project is built (HmiOverlay.gd,
## ExtruderZonePanel.gd). The scope is instantiated by HmiOverlay when the
## player opens an extruder-scoped HMI panel (hmi_extruder_all, lines 3C/6).
##
## Layout:
##
##   ┌──────────────────────────────────────────────────────────────────────┐
##   │ 09:42                Rx LDPE 800 kg/h 22.04.2024 IBN     BluPort/EREMA│
##   ├──────────────────────────────────────────────────────────────────────┤
##   │┌──────┐ ┌──────────────────────────────────────┐  ┌────────────────┐ │
##   ││ rail │ │      4-trace oscilloscope             │  │  AutoPro Aan/Uit│ │
##   ││ 9    │ │      0-600 kW left axis              │  │  PCU-vulpeil   │ │
##   ││ rows │ │      0-250 °C/% right axis           │  │  PES-toerental │ │
##   ││      │ │      rolling ~16 min window          │  │  TEU-toerental │ │
##   ││      │ │                                       │  │  [numpad if L6]│ │
##   │└──────┘ │  red/green/yellow/cyan square wave  │  └────────────────┘ │
##   │         └──────────────────────────────────────┘                     │
##   │         legend strip                                                 │
##   ├──────────────────────────────────────────────────────────────────────┤
##   │   schematic: cone | feed belt | barrel | die  + overlay labels       │
##   ├──────────────────────────────────────────────────────────────────────┤
##   │                          LIJN 3C / LIJN 6                            │
##   └──────────────────────────────────────────────────────────────────────┘
##
## The scope does NOT manage its own visibility — the parent (HmiOverlay or
## the Hmi node) shows/frees it. When the operator presses the ✕ close button
## the scope emits `request_close()` and stops there.

signal request_close()

# =============================================================================
# Public configuration
# =============================================================================
@export var line_id : String = "3C"

# =============================================================================
# Palette (project-internal — falls back to the spec if HmiOverlay isn't
# reachable). HmiOverlay's palette uses dark green/amber dashboards; the
# BluPort scope uses the original SCADA colours per the source images.
# =============================================================================
const COL_BG       : Color = Color(0.06, 0.06, 0.10)
const COL_PANEL    : Color = Color(0.10, 0.10, 0.16)
const COL_GRID     : Color = Color(0.20, 0.22, 0.30)
const COL_TEXT     : Color = Color(0.92, 0.94, 0.97)
const COL_DIM      : Color = Color(0.62, 0.66, 0.72)
const COL_RED      : Color = Color(0.95, 0.30, 0.20)   # PCU-vermogen kW
const COL_GREEN    : Color = Color(0.30, 0.85, 0.30)   # PCU-temperatuur 1 °C
const COL_YELLOW   : Color = Color(0.95, 0.85, 0.20)   # AIS-positie %
const COL_CYAN     : Color = Color(0.20, 0.85, 0.95)   # Toevoer actief (bool)
const COL_ALARM    : Color = Color(0.98, 0.78, 0.12)   # zone-temp alarm text
const COL_BLUE     : Color = Color(0.15, 0.45, 0.85)   # BluPort accent

# =============================================================================
# Strip-chart configuration
# =============================================================================
const CHART_WINDOW_S    : float = 16.0 * 60.0    # 16 minute rolling window
const CHART_RING_SIZE   : int   = 1000           # ~1.04 s resolution at full window
const CHART_LEFT_MAX_KW : float = 600.0          # left Y axis
const CHART_RIGHT_MAX   : float = 250.0          # right Y axis (°C / %)

# Alarm band for the EX1-IZ1 zone temp callout on the schematic
const ZONE_ALARM_LOW_C  : float = 180.0
const ZONE_ALARM_HIGH_C : float = 230.0

# =============================================================================
# Telemetry binding
# =============================================================================
# Duck-typed: we keep it as Object so headless tests can pass a mock.
var _model : Object = null

# =============================================================================
# Internal UI references — populated in _build_ui()
# =============================================================================
var _title_plate         : Label
var _clock_lbl           : Label
var _recipe_lbl          : Label
var _rail_values         : Dictionary = {}   # key (String) → Label
var _chart               : Control          # custom _draw target
var _right_value_lbls    : Dictionary = {}   # AutoPro / PCU-vulpeil / PES / TEU
var _autopro_button      : Button
var _numpad_panel        : PanelContainer    # only visible when line_id == "6"
var _schematic_box       : Control
var _schematic_value_lbls: Dictionary = {}   # overlay labels on the schematic

# Strip-chart ring buffers — index 0..CHART_RING_SIZE-1, rolling
var _samples_kw     : PackedFloat32Array = PackedFloat32Array()
var _samples_temp_c : PackedFloat32Array = PackedFloat32Array()
var _samples_ais    : PackedFloat32Array = PackedFloat32Array()
var _samples_feed   : PackedFloat32Array = PackedFloat32Array()
var _samples_t      : PackedFloat32Array = PackedFloat32Array()   # seconds since scope open
var _ring_head      : int   = 0
var _ring_filled    : int   = 0
var _scope_open_s   : float = 0.0

# Time-of-day for the clock — Time.get_time_dict_from_system() once a second.
var _last_clock_refresh_s : float = -10.0

# =============================================================================
# Layout constants
# =============================================================================
const RAIL_WIDTH       : float = 220.0
const RIGHT_COL_WIDTH  : float = 260.0
const SCHEMATIC_HEIGHT : float = 160.0
const HEADER_HEIGHT    : float = 40.0
const FOOTER_HEIGHT    : float = 36.0

const RAIL_ROWS : Array = [
	{"key": "melt_temp",       "icon": "T", "unit": "°C",   "label": "melt temp"},
	{"key": "total_kw",        "icon": "P", "unit": "kW",   "label": "totaal"},
	{"key": "screw_rpm",       "icon": "n", "unit": "rpm",  "label": "schroef"},
	{"key": "load_pct",        "icon": "L", "unit": "%",    "label": "belasting"},
	{"key": "runtime_h",       "icon": "h", "unit": "h",    "label": "looptijd"},
	{"key": "melt_pressure",   "icon": "p", "unit": "bar",  "label": "smelt-druk"},
	{"key": "screen_changer",  "icon": "p", "unit": "bar",  "label": "zeefwisselaar"},
	{"key": "post_filter",     "icon": "p", "unit": "bar",  "label": "na-filter"},
	{"key": "throughput_kg_h", "icon": "Q", "unit": "kg/h", "label": "doorzet"},
]

const SCHEMATIC_OVERLAYS : Array = [
	{"key": "bc1_rpm_pct",   "label": "BC1-toerental",  "unit": "%",   "px": 0.08, "py": 0.30},
	{"key": "ex1_kw",        "label": "EX1-vermogen",   "unit": "kW",  "px": 0.32, "py": 0.16},
	{"key": "ais_pct",       "label": "AIS-positie",    "unit": "%",   "px": 0.20, "py": 0.62},
	{"key": "pcu_temp1_c",   "label": "PCU-temp.1",     "unit": "°C",  "px": 0.08, "py": 0.66},
	{"key": "ex1_rpm",       "label": "EX1-toerental",  "unit": "rpm", "px": 0.50, "py": 0.30},
	{"key": "ex1_load_pct",  "label": "EX1-belasting",  "unit": "%",   "px": 0.50, "py": 0.66},
	{"key": "pcu_load_pct",  "label": "PCU-belasting",  "unit": "%",   "px": 0.08, "py": 0.16},
	{"key": "pcu_kw",        "label": "PCU-vermogen",   "unit": "kW",  "px": 0.20, "py": 0.16},
	{"key": "ex1_iz1_temp",  "label": "EX1-IZ1 zone",   "unit": "°C",  "px": 0.75, "py": 0.30, "alarm": true},
]

const RIGHT_PANEL_ROWS : Array = [
	{"key": "pcu_vulpeil",   "label": "PCU-vulpeil",   "unit": "cm"},
	{"key": "pes_toerental", "label": "PES-toerental", "unit": "%"},
	{"key": "teu_toerental", "label": "TEU-toerental", "unit": "%"},
]

# =============================================================================
# Lifecycle
# =============================================================================
func _ready() -> void:
	# Fill the parent — HmiOverlay's _content is a MarginContainer that hands
	# us its full client rect.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Pre-allocate ring buffers (one-shot — no realloc thrash inside _process).
	_samples_kw.resize(CHART_RING_SIZE)
	_samples_temp_c.resize(CHART_RING_SIZE)
	_samples_ais.resize(CHART_RING_SIZE)
	_samples_feed.resize(CHART_RING_SIZE)
	_samples_t.resize(CHART_RING_SIZE)
	_build_ui()
	_apply_line_id()

# =============================================================================
# Public API
# =============================================================================

## Bind a live ExtruderModel. The scope reads telemetry from it each tick;
## the binding is duck-typed so headless tests can pass a Dictionary-shaped
## mock with the same property names.
func set_model(m : Object) -> void:
	_model = m
	# Drop any in-flight chart data so the new model starts a clean trace.
	_ring_head = 0
	_ring_filled = 0
	_scope_open_s = 0.0

## Change which line the scope represents. "6" reveals the right-side numpad
## (recipe entry only available on line 6 SCADA stations); any other id hides
## the numpad. Title plate updates either way.
func set_line_id(id : String) -> void:
	line_id = id
	_apply_line_id()

# =============================================================================
# Per-frame
# =============================================================================
func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	_scope_open_s += delta
	_sample_telemetry(delta)
	_update_rail()
	_update_right_panel()
	_update_schematic_overlays()
	_refresh_clock(delta)
	if _chart != null and is_instance_valid(_chart):
		_chart.queue_redraw()

# =============================================================================
# UI construction
# =============================================================================
func _build_ui() -> void:
	# Solid backdrop
	var bg := ColorRect.new()
	bg.color = COL_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	# Root vertical stack — header / main row / schematic / title plate
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 6)
	root.offset_left = 8
	root.offset_top = 8
	root.offset_right = -8
	root.offset_bottom = -8
	add_child(root)

	root.add_child(_build_header())
	root.add_child(_build_main_row())
	root.add_child(_build_schematic())
	root.add_child(_build_title_plate())

func _build_header() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, HEADER_HEIGHT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	sb.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(h)

	_clock_lbl = Label.new()
	_clock_lbl.text = "--:-- ----------"
	_clock_lbl.add_theme_color_override("font_color", COL_TEXT)
	_clock_lbl.custom_minimum_size = Vector2(220, 0)
	_clock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_clock_lbl)

	_recipe_lbl = Label.new()
	_recipe_lbl.text = "Rx LDPE 800 kg/h 22.04.2024 IBN"
	_recipe_lbl.add_theme_color_override("font_color", COL_TEXT)
	_recipe_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_recipe_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_recipe_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_recipe_lbl)

	var logos := HBoxContainer.new()
	logos.add_theme_constant_override("separation", 8)

	var blu := Label.new()
	blu.text = "BluPort"
	blu.add_theme_color_override("font_color", COL_BLUE)
	blu.add_theme_font_size_override("font_size", 16)
	blu.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logos.add_child(blu)

	var ere := Label.new()
	ere.text = "EREMA"
	ere.add_theme_color_override("font_color", COL_TEXT)
	ere.add_theme_font_size_override("font_size", 16)
	ere.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	logos.add_child(ere)

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(36, 28)
	close_btn.pressed.connect(_on_close_pressed)
	logos.add_child(close_btn)

	h.add_child(logos)
	return bar

func _build_main_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_build_rail())
	row.add_child(_build_chart_block())
	row.add_child(_build_right_column())
	return row

func _build_rail() -> Control:
	var rail := PanelContainer.new()
	rail.custom_minimum_size = Vector2(RAIL_WIDTH, 0)
	rail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	rail.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	rail.add_child(v)

	for r in RAIL_ROWS:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		var icon := Label.new()
		icon.text = String(r.icon)
		icon.add_theme_color_override("font_color", COL_DIM)
		icon.custom_minimum_size = Vector2(18, 0)
		row.add_child(icon)

		var lbl := Label.new()
		lbl.text = String(r.label)
		lbl.add_theme_color_override("font_color", COL_DIM)
		lbl.custom_minimum_size = Vector2(108, 0)
		row.add_child(lbl)

		var val := Label.new()
		val.text = "---"
		val.add_theme_color_override("font_color", COL_TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(val)
		_rail_values[String(r.key)] = val

		var unit := Label.new()
		unit.text = String(r.unit)
		unit.add_theme_color_override("font_color", COL_DIM)
		unit.custom_minimum_size = Vector2(40, 0)
		row.add_child(unit)

		v.add_child(row)

	return rail

func _build_chart_block() -> Control:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 2)

	var chart_panel := PanelContainer.new()
	chart_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chart_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	chart_panel.add_theme_stylebox_override("panel", sb)

	_chart = Control.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_chart.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chart.draw.connect(_draw_chart)
	chart_panel.add_child(_chart)

	v.add_child(chart_panel)
	v.add_child(_build_chart_legend())
	return v

func _build_chart_legend() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 24)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	bar.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	bar.add_child(h)

	h.add_child(_legend_chip(COL_RED,    "PCU-vermogen kW"))
	h.add_child(_legend_chip(COL_GREEN,  "PCU-temperatuur 1 °C"))
	h.add_child(_legend_chip(COL_YELLOW, "AIS-positie %"))
	h.add_child(_legend_chip(COL_CYAN,   "Toevoer actief"))
	return bar

func _legend_chip(c: Color, t: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var swatch := ColorRect.new()
	swatch.color = c
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var lbl := Label.new()
	lbl.text = t
	lbl.add_theme_color_override("font_color", COL_DIM)
	row.add_child(lbl)
	return row

func _build_right_column() -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(RIGHT_COL_WIDTH, 0)
	col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)

	# AutoPro toggle box
	var ap := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	ap.add_theme_stylebox_override("panel", sb)
	var apv := VBoxContainer.new()
	apv.add_theme_constant_override("separation", 4)
	ap.add_child(apv)
	var apt := Label.new()
	apt.text = "AutoPro-control"
	apt.add_theme_color_override("font_color", COL_DIM)
	apv.add_child(apt)
	_autopro_button = Button.new()
	_autopro_button.text = "AAN"
	_autopro_button.toggle_mode = true
	_autopro_button.button_pressed = true
	_autopro_button.toggled.connect(_on_autopro_toggled)
	apv.add_child(_autopro_button)
	col.add_child(ap)

	# PCU-vulpeil / PES / TEU rows
	for r in RIGHT_PANEL_ROWS:
		var box := PanelContainer.new()
		var rsb := StyleBoxFlat.new()
		rsb.bg_color = COL_PANEL
		box.add_theme_stylebox_override("panel", rsb)

		var rh := HBoxContainer.new()
		rh.add_theme_constant_override("separation", 6)
		box.add_child(rh)

		var lbl := Label.new()
		lbl.text = String(r.label)
		lbl.add_theme_color_override("font_color", COL_DIM)
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rh.add_child(lbl)

		var val := Label.new()
		val.text = "---"
		val.add_theme_color_override("font_color", COL_TEXT)
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		val.custom_minimum_size = Vector2(60, 0)
		rh.add_child(val)
		_right_value_lbls[String(r.key)] = val

		var unit := Label.new()
		unit.text = String(r.unit)
		unit.add_theme_color_override("font_color", COL_DIM)
		unit.custom_minimum_size = Vector2(36, 0)
		rh.add_child(unit)

		col.add_child(box)

	# 10-key numpad (line 6 only)
	_numpad_panel = _build_numpad()
	col.add_child(_numpad_panel)

	# Spacer so the panels hug the top
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)
	return col

func _build_numpad() -> PanelContainer:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	panel.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	panel.add_child(v)

	var t := Label.new()
	t.text = "RECEPT"
	t.add_theme_color_override("font_color", COL_DIM)
	v.add_child(t)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	v.add_child(grid)

	var keys : Array = ["7","8","9","4","5","6","1","2","3","De","0","Nu"]
	for k in keys:
		var b := Button.new()
		b.text = String(k)
		b.custom_minimum_size = Vector2(46, 32)
		grid.add_child(b)

	var esc := Button.new()
	esc.text = "ESC"
	esc.custom_minimum_size = Vector2(0, 28)
	v.add_child(esc)

	return panel

func _build_schematic() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, SCHEMATIC_HEIGHT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_PANEL
	panel.add_theme_stylebox_override("panel", sb)

	_schematic_box = Control.new()
	_schematic_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_schematic_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_schematic_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_schematic_box.draw.connect(_draw_schematic)
	panel.add_child(_schematic_box)

	# Overlay labels — positioned as children of the schematic_box and
	# anchored via _process to follow the box size. We use the % offsets in
	# SCHEMATIC_OVERLAYS to set anchor + offset.
	for ov in SCHEMATIC_OVERLAYS:
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		v.anchor_left = float(ov.px)
		v.anchor_top = float(ov.py)
		v.anchor_right = float(ov.px)
		v.anchor_bottom = float(ov.py)
		v.offset_left = 0
		v.offset_top = 0
		v.offset_right = 140
		v.offset_bottom = 30
		v.mouse_filter = Control.MOUSE_FILTER_IGNORE

		var lbl := Label.new()
		lbl.text = String(ov.label)
		lbl.add_theme_color_override("font_color", COL_DIM)
		lbl.add_theme_font_size_override("font_size", 10)
		v.add_child(lbl)

		var val := Label.new()
		val.text = "---  %s" % String(ov.unit)
		val.add_theme_color_override("font_color", COL_TEXT)
		val.add_theme_font_size_override("font_size", 12)
		v.add_child(val)

		_schematic_box.add_child(v)
		_schematic_value_lbls[String(ov.key)] = {
			"value": val,
			"unit": String(ov.unit),
			"alarm": bool(ov.get("alarm", false)),
		}

	return panel

func _build_title_plate() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, FOOTER_HEIGHT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_BLUE
	panel.add_theme_stylebox_override("panel", sb)
	_title_plate = Label.new()
	_title_plate.text = "LIJN %s" % line_id
	_title_plate.add_theme_color_override("font_color", COL_TEXT)
	_title_plate.add_theme_font_size_override("font_size", 18)
	_title_plate.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_plate.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(_title_plate)
	return panel

# =============================================================================
# Telemetry sampling
# =============================================================================
func _sample_telemetry(_delta: float) -> void:
	var kw    : float = _read_field("ex1_kw", 0.0)
	var t_c   : float = _read_field("pcu_temp1_c", _read_field("melt_temp", 0.0))
	var ais   : float = _read_field("ais_pct", 0.0)
	var feed  : float = 1.0 if bool(_read_field_bool("toevoer_actief", true)) else 0.0
	_samples_kw[_ring_head]     = kw
	_samples_temp_c[_ring_head] = t_c
	_samples_ais[_ring_head]    = ais
	_samples_feed[_ring_head]   = feed
	_samples_t[_ring_head]      = _scope_open_s
	_ring_head = (_ring_head + 1) % CHART_RING_SIZE
	if _ring_filled < CHART_RING_SIZE:
		_ring_filled += 1

func _read_field(key: String, dflt: float) -> float:
	if _model == null:
		return dflt
	# Direct property names (covers ExtruderModel)
	match key:
		"melt_temp":
			if "melt_temp" in _model:
				return float(_model.melt_temp)
		"screw_rpm":
			if "screw_rpm" in _model:
				return float(_model.screw_rpm)
		"throughput_kg_h":
			if "throughput_kg_h" in _model:
				return float(_model.throughput_kg_h)
		"runtime_h":
			if "runtime_s" in _model:
				return float(_model.runtime_s) / 3600.0
		"load_pct", "ex1_load_pct":
			if "motor_torque_pct" in _model:
				return float(_model.motor_torque_pct)
		"melt_pressure":
			# die_pressure is psi; convert (1 bar = 14.504 psi)
			if "die_pressure_psi" in _model:
				return float(_model.die_pressure_psi) / 14.504
		"screen_changer":
			if "die_pressure_psi" in _model:
				return float(_model.die_pressure_psi) / 14.504 * 0.92
		"post_filter":
			if "die_pressure_psi" in _model:
				return float(_model.die_pressure_psi) / 14.504 * 0.82
		"ex1_kw", "total_kw", "pcu_kw":
			# Coarse proxy: motor_torque_pct × rpm × scalar
			var rpm : float = float(_model.screw_rpm) if "screw_rpm" in _model else 0.0
			var lpct : float = float(_model.motor_torque_pct) if "motor_torque_pct" in _model else 0.0
			return clampf(rpm * lpct * 0.0035, 0.0, CHART_LEFT_MAX_KW)
		"pcu_temp1_c":
			if "melt_temp" in _model:
				return float(_model.melt_temp)
		"ais_pct":
			if "primary_suction_pct" in _model:
				return clampf(float(_model.primary_suction_pct) * 100.0, 0.0, 100.0)
		"pcu_vulpeil":
			if "primary_pot_fill_kg" in _model:
				return float(_model.primary_pot_fill_kg) * 10.0
		"pes_toerental", "teu_toerental":
			if "screw_rpm" in _model and "config" in _model and _model.config != null \
					and "screw_rpm_nominal" in _model.config:
				var nom : float = max(1.0, float(_model.config.screw_rpm_nominal))
				return clampf(float(_model.screw_rpm) / nom * 100.0, 0.0, 100.0)
		"bc1_rpm_pct":
			if "screw_rpm" in _model and "config" in _model and _model.config != null \
					and "screw_rpm_nominal" in _model.config:
				var nom2 : float = max(1.0, float(_model.config.screw_rpm_nominal))
				return clampf(float(_model.screw_rpm) / nom2 * 100.0, 0.0, 100.0)
		"ex1_rpm":
			if "screw_rpm" in _model:
				return float(_model.screw_rpm)
		"pcu_load_pct":
			if "motor_torque_pct" in _model:
				return float(_model.motor_torque_pct) * 0.85
		"ex1_iz1_temp":
			if _model.has_method("get_zone_temp"):
				return float(_model.call("get_zone_temp", 1))
	# Generic dictionary-or-property lookup for mocks
	if key in _model:
		return float(_model.get(key))
	return dflt

func _read_field_bool(key: String, dflt: bool) -> bool:
	if _model == null:
		return dflt
	if key in _model:
		return bool(_model.get(key))
	# Derive feed from state — RUNNING means toevoer actief
	if key == "toevoer_actief" and "state" in _model:
		# State enum 2 = RUNNING in ExtruderModel
		return int(_model.state) == 2
	return dflt

# =============================================================================
# Rail / right-panel / schematic updaters
# =============================================================================
func _update_rail() -> void:
	for r in RAIL_ROWS:
		var k : String = String(r.key)
		var lbl : Label = _rail_values.get(k, null)
		if lbl == null:
			continue
		var v : float = _read_field(k, 0.0)
		lbl.text = _fmt_number(v, String(r.unit))

func _update_right_panel() -> void:
	for r in RIGHT_PANEL_ROWS:
		var k : String = String(r.key)
		var lbl : Label = _right_value_lbls.get(k, null)
		if lbl == null:
			continue
		var v : float = _read_field(k, 0.0)
		lbl.text = _fmt_number(v, String(r.unit))

func _update_schematic_overlays() -> void:
	for ov in SCHEMATIC_OVERLAYS:
		var k : String = String(ov.key)
		var entry : Dictionary = _schematic_value_lbls.get(k, {})
		if entry.is_empty():
			continue
		var val_lbl : Label = entry.get("value", null)
		if val_lbl == null:
			continue
		var unit : String = String(entry.get("unit", ""))
		var v : float = _read_field(k, 0.0)
		val_lbl.text = "%s  %s" % [_fmt_number(v, unit), unit]
		# Alarm-band recolouring for the IZ1 zone callout
		if bool(entry.get("alarm", false)):
			var in_alarm : bool = v < ZONE_ALARM_LOW_C or v > ZONE_ALARM_HIGH_C
			val_lbl.add_theme_color_override(
				"font_color",
				COL_ALARM if in_alarm else COL_TEXT
			)

func _fmt_number(v: float, unit: String) -> String:
	match unit:
		"rpm":
			return "%d" % int(round(v))
		"kg/h":
			return "%d" % int(round(v))
		"h":
			return "%.1f" % v
		"kW":
			return "%.0f" % v
		"bar":
			return "%.1f" % v
		"%":
			return "%.0f" % v
		"°C":
			return "%.0f" % v
		"cm":
			return "%.0f" % v
		_:
			return "%.1f" % v

func _refresh_clock(delta: float) -> void:
	_last_clock_refresh_s += delta
	if _last_clock_refresh_s < 1.0:
		return
	_last_clock_refresh_s = 0.0
	var t : Dictionary = Time.get_datetime_dict_from_system()
	_clock_lbl.text = "%02d:%02d   %02d.%02d.%04d" % [
		int(t.get("hour", 0)),
		int(t.get("minute", 0)),
		int(t.get("day", 0)),
		int(t.get("month", 0)),
		int(t.get("year", 0)),
	]

# =============================================================================
# Custom drawing
# =============================================================================
func _draw_chart() -> void:
	if _chart == null:
		return
	var sz : Vector2 = _chart.size
	if sz.x <= 4.0 or sz.y <= 4.0:
		return
	# Grid: 6 vertical, 5 horizontal
	for i in 7:
		var x : float = sz.x * float(i) / 6.0
		_chart.draw_line(Vector2(x, 0), Vector2(x, sz.y), COL_GRID, 1.0)
	for i in 6:
		var y : float = sz.y * float(i) / 5.0
		_chart.draw_line(Vector2(0, y), Vector2(sz.x, y), COL_GRID, 1.0)

	# Axis labels (left = kW 0..600, right = °C/% 0..250)
	var font : Font = ThemeDB.fallback_font
	var fs : int = 10
	for i in 6:
		var y_lbl : float = sz.y * float(i) / 5.0
		var left_v : float = CHART_LEFT_MAX_KW * (1.0 - float(i) / 5.0)
		var right_v : float = CHART_RIGHT_MAX * (1.0 - float(i) / 5.0)
		_chart.draw_string(font, Vector2(2, y_lbl + 10), "%d" % int(left_v),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_DIM)
		_chart.draw_string(font, Vector2(sz.x - 28, y_lbl + 10), "%d" % int(right_v),
			HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_DIM)

	# Time-axis absolute labels at left/centre/right
	var now : Dictionary = Time.get_datetime_dict_from_system()
	var hh : int = int(now.get("hour", 0))
	var mm : int = int(now.get("minute", 0))
	_chart.draw_string(font, Vector2(2, sz.y - 4),
		"%02d:%02d" % [(hh + 23) % 24, mm],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_DIM)
	_chart.draw_string(font, Vector2(sz.x - 40, sz.y - 4),
		"%02d:%02d" % [hh, mm],
		HORIZONTAL_ALIGNMENT_LEFT, -1, fs, COL_DIM)

	if _ring_filled <= 1:
		return

	# Polyline drawing — walk ring oldest→newest and map to canvas
	var start : int = 0
	var count : int = _ring_filled
	if _ring_filled == CHART_RING_SIZE:
		start = _ring_head
	# Use the oldest sample's t as window start so the trace scrolls left.
	var oldest_t : float = _samples_t[start]
	var newest_t : float = _samples_t[(start + count - 1) % CHART_RING_SIZE]
	var window_span : float = max(0.001, newest_t - oldest_t)

	var pts_kw   : PackedVector2Array = PackedVector2Array()
	var pts_temp : PackedVector2Array = PackedVector2Array()
	var pts_ais  : PackedVector2Array = PackedVector2Array()
	var pts_feed : PackedVector2Array = PackedVector2Array()
	pts_kw.resize(count)
	pts_temp.resize(count)
	pts_ais.resize(count)
	pts_feed.resize(count)

	for j in count:
		var idx : int = (start + j) % CHART_RING_SIZE
		var tt : float = _samples_t[idx]
		var x : float = clampf((tt - oldest_t) / window_span, 0.0, 1.0) * sz.x
		var y_kw : float = sz.y * (1.0 - clampf(_samples_kw[idx] / CHART_LEFT_MAX_KW, 0.0, 1.0))
		var y_t : float  = sz.y * (1.0 - clampf(_samples_temp_c[idx] / CHART_RIGHT_MAX, 0.0, 1.0))
		var y_a : float  = sz.y * (1.0 - clampf(_samples_ais[idx] / 100.0, 0.0, 1.0))
		# Square wave: 0 → bottom band, 1 → upper band (so it reads as boolean)
		var y_f : float  = sz.y * (1.0 - (0.95 if _samples_feed[idx] > 0.5 else 0.05))
		pts_kw[j] = Vector2(x, y_kw)
		pts_temp[j] = Vector2(x, y_t)
		pts_ais[j] = Vector2(x, y_a)
		pts_feed[j] = Vector2(x, y_f)

	# Draw cyan feed first so the analog traces sit on top
	_chart.draw_polyline(pts_feed, COL_CYAN, 1.5)
	_chart.draw_polyline(pts_ais,  COL_YELLOW, 1.5)
	_chart.draw_polyline(pts_temp, COL_GREEN, 1.5)
	_chart.draw_polyline(pts_kw,   COL_RED, 1.5)

func _draw_schematic() -> void:
	if _schematic_box == null:
		return
	var sz : Vector2 = _schematic_box.size
	if sz.x <= 4.0 or sz.y <= 4.0:
		return
	# Cone (cutter-compactor) — left ~25%
	var cone_pts : PackedVector2Array = PackedVector2Array([
		Vector2(sz.x * 0.04, sz.y * 0.20),
		Vector2(sz.x * 0.18, sz.y * 0.20),
		Vector2(sz.x * 0.14, sz.y * 0.80),
		Vector2(sz.x * 0.08, sz.y * 0.80),
	])
	_schematic_box.draw_colored_polygon(cone_pts, COL_GRID)

	# Inclined feed belt
	var belt_pts : PackedVector2Array = PackedVector2Array([
		Vector2(sz.x * 0.18, sz.y * 0.60),
		Vector2(sz.x * 0.40, sz.y * 0.40),
		Vector2(sz.x * 0.40, sz.y * 0.50),
		Vector2(sz.x * 0.18, sz.y * 0.70),
	])
	_schematic_box.draw_colored_polygon(belt_pts, COL_GRID)

	# Extruder barrel
	var barrel_rect : Rect2 = Rect2(
		Vector2(sz.x * 0.40, sz.y * 0.42),
		Vector2(sz.x * 0.45, sz.y * 0.16)
	)
	_schematic_box.draw_rect(barrel_rect, COL_GRID)
	# Barrel zone tick marks
	for i in 6:
		var tx : float = barrel_rect.position.x + barrel_rect.size.x * float(i + 1) / 7.0
		_schematic_box.draw_line(
			Vector2(tx, barrel_rect.position.y),
			Vector2(tx, barrel_rect.end.y),
			COL_PANEL, 1.5
		)

	# Die-head (cylinder + face)
	_schematic_box.draw_rect(
		Rect2(Vector2(sz.x * 0.85, sz.y * 0.38), Vector2(sz.x * 0.06, sz.y * 0.24)),
		COL_BLUE
	)
	_schematic_box.draw_circle(
		Vector2(sz.x * 0.92, sz.y * 0.50),
		min(sz.y, sz.x) * 0.06,
		COL_BLUE
	)

# =============================================================================
# Event handlers
# =============================================================================
func _on_close_pressed() -> void:
	emit_signal("request_close")

func _on_autopro_toggled(p: bool) -> void:
	_autopro_button.text = "AAN" if p else "UIT"
	# Forward to the model if it has an AutoPro setter
	if _model != null and is_instance_valid(_model) \
			and _model.has_method("set_autopro_enabled"):
		_model.call("set_autopro_enabled", p)

# =============================================================================
# Line-id reactive layout
# =============================================================================
func _apply_line_id() -> void:
	if _title_plate != null and is_instance_valid(_title_plate):
		_title_plate.text = "LIJN %s" % line_id
	if _numpad_panel != null and is_instance_valid(_numpad_panel):
		_numpad_panel.visible = (line_id == "6")
