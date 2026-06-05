extends CanvasLayer

## Local control panel for a bezinkafscheider tank (BezinkTank). Opened by the
## tank's proximity HMI (walk up + E). Shows the live water level and lets the
## operator switch the discharge valve AUTOMAAT/HAND, open/close it by hand, move
## the level setpoints, and read the pump state. One shared instance, reused for
## whichever tank was last opened (see BezinkTank._open_hmi).

var _tank : Node = null
var _built : bool = false

var _level_bar  : ProgressBar
var _level_lbl  : Label
var _mode_btn   : Button
var _valve_lbl  : Label
var _valve_lamp : ColorRect
var _open_btn   : Button
var _close_btn  : Button
var _splow_lbl  : Label
var _sphigh_lbl : Label
var _pump_lbl   : Label
var _pump_lamp  : ColorRect

const C_PANEL  := Color(0.12, 0.14, 0.16, 1.0)
const C_HEAD   := Color(0.12, 0.19, 0.25, 1.0)
const C_BTN    := Color(0.20, 0.32, 0.40, 1.0)
const C_TEXT   := Color(0.88, 0.92, 0.92, 1.0)
const LAMP_ON  := Color(0.27, 0.78, 0.32, 1.0)
const LAMP_OFF := Color(0.42, 0.45, 0.43, 1.0)

func _ready() -> void:
	layer = 60
	visible = false
	set_process(true)

func open_for(tank: Node) -> void:
	if not _built:
		_build()
		_built = true
	_tank = tank
	visible = true
	_refresh()

func close_panel() -> void:
	visible = false
	_tank = null
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(440, 0)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_PANEL
	psb.set_corner_radius_all(8)
	psb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "BEZINKAFSCHEIDER  ·  L3C.3"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_TEXT)
	vb.add_child(title)

	# ── Water level ────────────────────────────────────────────────────────────
	_level_lbl = _row_label(vb, "Niveau (tankhoogte)")
	_level_bar = ProgressBar.new()
	_level_bar.min_value = 0.0
	_level_bar.max_value = 100.0
	_level_bar.custom_minimum_size = Vector2(0, 26)
	vb.add_child(_level_bar)

	# ── Valve mode + state ───────────────────────────────────────────────────────
	_mode_btn = _flat_button("KLEP: AUTOMAAT", C_BTN)
	_mode_btn.pressed.connect(_on_toggle_mode)
	vb.add_child(_mode_btn)

	var vrow := HBoxContainer.new()
	vrow.add_theme_constant_override("separation", 8)
	vb.add_child(vrow)
	_valve_lamp = _lamp()
	vrow.add_child(_valve_lamp)
	_valve_lbl = _row_label(vrow, "Klep: —")
	_open_btn = _flat_button("OPEN", C_BTN)
	_open_btn.pressed.connect(func(): if _tank: _tank.set_valve_manual(true))
	vrow.add_child(_open_btn)
	_close_btn = _flat_button("DICHT", C_BTN)
	_close_btn.pressed.connect(func(): if _tank: _tank.set_valve_manual(false))
	vrow.add_child(_close_btn)

	# ── Setpoints ────────────────────────────────────────────────────────────────
	_splow_lbl = _setpoint_row(vb, "Setpoint LAAG",
		func(): _adjust(_tank, "adjust_sp_low", -0.05),
		func(): _adjust(_tank, "adjust_sp_low",  0.05))
	_sphigh_lbl = _setpoint_row(vb, "Setpoint HOOG",
		func(): _adjust(_tank, "adjust_sp_high", -0.05),
		func(): _adjust(_tank, "adjust_sp_high",  0.05))

	# ── Pump ──────────────────────────────────────────────────────────────────────
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 8)
	vb.add_child(prow)
	_pump_lamp = _lamp()
	prow.add_child(_pump_lamp)
	_pump_lbl = _row_label(prow, "Proces­pomp: —")

	# ── Close ───────────────────────────────────────────────────────────────────
	var closeb := _flat_button("SLUITEN  (Esc)", Color(0.40, 0.22, 0.20, 1.0))
	closeb.pressed.connect(close_panel)
	vb.add_child(closeb)

func _setpoint_row(parent: Node, text: String, on_minus: Callable, on_plus: Callable) -> Label:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var name_lbl := _row_label(row, text)
	name_lbl.custom_minimum_size = Vector2(180, 0)
	var minus := _flat_button("  –  ", C_BTN)
	minus.pressed.connect(on_minus)
	row.add_child(minus)
	var val := Label.new()
	val.add_theme_font_size_override("font_size", 18)
	val.add_theme_color_override("font_color", C_TEXT)
	val.custom_minimum_size = Vector2(60, 0)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(val)
	var plus := _flat_button("  +  ", C_BTN)
	plus.pressed.connect(on_plus)
	row.add_child(plus)
	return val

func _row_label(parent: Node, text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 16)
	l.add_theme_color_override("font_color", C_TEXT)
	parent.add_child(l)
	return l

func _lamp() -> ColorRect:
	var r := ColorRect.new()
	r.color = LAMP_OFF
	r.custom_minimum_size = Vector2(20, 20)
	return r

func _flat_button(text: String, bg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_color_override("font_color", C_TEXT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.set_corner_radius_all(4)
	sb.set_content_margin_all(8)
	b.add_theme_stylebox_override("normal", sb)
	var hb := sb.duplicate() as StyleBoxFlat
	hb.bg_color = bg.lightened(0.12)
	b.add_theme_stylebox_override("hover", hb)
	return b

func _adjust(tank: Node, method: String, d: float) -> void:
	if tank and tank.has_method(method):
		tank.call(method, d)

func _on_toggle_mode() -> void:
	if _tank:
		_tank.toggle_auto()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if not visible or _tank == null or not _built:
		return
	_refresh()

func _refresh() -> void:
	if _tank == null or _level_bar == null:
		return
	var lvl : float = _tank.water_level * 100.0
	_level_bar.value = lvl
	_level_lbl.text = "Niveau: %d %%" % int(round(lvl))
	var auto : bool = _tank.valve_auto
	_mode_btn.text = "KLEP: AUTOMAAT" if auto else "KLEP: HAND"
	var open : bool = _tank.valve_open
	_valve_lbl.text = "Klep: %s" % ("OPEN" if open else "DICHT")
	_valve_lamp.color = LAMP_ON if open else LAMP_OFF
	_open_btn.disabled = auto
	_close_btn.disabled = auto
	_splow_lbl.text = "%d %%" % int(round(_tank.sp_low * 100.0))
	_sphigh_lbl.text = "%d %%" % int(round(_tank.sp_high * 100.0))
	var pump : bool = _tank.pump_on
	_pump_lbl.text = "Procespomp: %s" % ("AAN" if pump else "UIT")
	_pump_lamp.color = LAMP_ON if pump else LAMP_OFF
