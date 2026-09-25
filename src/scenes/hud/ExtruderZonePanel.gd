extends PanelContainer
class_name ExtruderZonePanel

## Interactive HMI panel for the extruder's 7 temperature zone setpoints.
## Each row carries:
##   - Zone label (TRANSPORT / HEAT_1 / HEAT_2 / MELT_COMPACT / PRIMARY_DEGAS /
##     HOMOGENISE / SECONDARY_DEGAS)
##   - HSlider clamped to [TEMP_MIN_C, TEMP_MAX_C]
##   - Live numeric readout (the current setpoint °C, updates as the slider moves)
##
## Usage:
##   var panel := ExtruderZonePanel.new()
##   panel.bind(extruder_model)            # ExtruderModel — calls set_zone_temp on it
##   add_child(panel)
##
## The panel reads ZONE_NAMES + ZONE_COUNT from the model so adding/removing
## zones doesn't need a separate UI update. Sliders auto-populate from the
## model's current zone_temp_setpoints on bind().
##
## Operator semantics:
##   - The 100..240 °C range covers the operator-realistic envelope. Below 100 °C
##     the melt freezes; above 240 °C the polymer cracks. The HSlider's "tick"
##     is 1 °C; the operator drags + reads the live value.
##   - Pushing a zone setpoint LOWER avoids burning paper/cellulose contamination.
##     The model's motor_torque_pct climbs in response (cold melt loads the screw)
##     and operator's torque trip mechanic becomes part of the cascade — exactly
##     the Drop-Zone-Temps lever from the operator matrix.

const TEMP_MIN_C : float = 100.0
const TEMP_MAX_C : float = 240.0

# Die-face chip palette (#209b — pelletizer quality state visible to the operator
# right above the temperature sliders, so they connect the dots between zone
# setpoints and the strand quality at the cutter face).
const DIE_FACE_COLD_ON  : Color = Color(0.60, 0.60, 0.60)   # TE KOUD — pale grey
const DIE_FACE_GOOD_ON  : Color = Color(0.55, 0.45, 0.85)   # GOED GEHARD — lavender per pelletizer.png
const DIE_FACE_HOT_ON   : Color = Color(0.85, 0.30, 0.20)   # TE HEET — burnt red
const DIE_FACE_OFF      : Color = Color(0.18, 0.18, 0.22)   # inactive (any non-glowing chip)

var _model : Object = null
var _sliders : Array[HSlider] = []
var _readouts : Array[Label] = []
# Die-face chips (one PanelContainer each, recoloured per _process from the
# model's get_die_face_state() readout).
var _die_chip_cold : PanelContainer = null
var _die_chip_good : PanelContainer = null
var _die_chip_hot  : PanelContainer = null
# Screw speed setpoint (2026-09-25). A start ramps the screw to this setpoint,
# and after a 318-bar trip the operator lowers it to 60 to get the line going
# again (operator ruling). The touchscreen had zone sliders but no rpm control,
# so this row is that control on the MACHINES -> extruder_<line> detail, bound
# to that line's own model. Slider range = what the model accepts
# (screw_rpm_min..max).
var _rpm_slider : HSlider = null
var _rpm_readout : Label = null
# The start button (operator rulings 2026-09-25, §I1-§I7): ring lamp, what the
# start sequence does or why it is blocked, the alarm reset (on the HMI, never
# at the machine) and the hidden "natraject" setting.
var _start_lamp : Label = null
var _start_text : Label = null
var _start_reset : Button = null
var _natraject_toggle : CheckButton = null

func _ready() -> void:
	custom_minimum_size = Vector2(320, 0)

## Bind to an ExtruderModel. Populates the slider initial values from the
## model's existing zone_temp_setpoints array.
func bind(model: Object) -> void:
	_model = model
	if _model == null:
		return
	# Re-build the UI to match the model's ZONE_COUNT (handles a possible
	# future revision where the zone count varies per machine).
	for c in get_children():
		c.queue_free()
	_sliders.clear()
	_readouts.clear()
	var zone_count : int = 7
	var zone_names : Array = []
	if "ZONE_COUNT" in _model:
		zone_count = int(_model.ZONE_COUNT)
	if "ZONE_NAMES" in _model:
		zone_names = _model.ZONE_NAMES
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	add_child(box)
	_add_start_row(box)
	_add_rpm_row(box)
	box.add_child(HSeparator.new())
	var header := Label.new()
	header.text = "EXTRUDER ZONE SETPOINTS  (°C)"
	header.add_theme_font_size_override("font_size", 13)
	box.add_child(header)
	box.add_child(HSeparator.new())
	for i in zone_count:
		_add_zone_row(box, i, zone_names)
	# ── Die-face quality chips (#209b) ──────────────────────────────────────
	# Three side-by-side status chips showing the live pelletizer die-face
	# quality state from the model. Only one chip glows at a time; the others
	# render dark so the operator's eye snaps to the active one.
	_die_chip_cold = null
	_die_chip_good = null
	_die_chip_hot  = null
	box.add_child(HSeparator.new())
	var die_header := Label.new()
	die_header.text = "DIE-FACE KWALITEIT"
	die_header.add_theme_font_size_override("font_size", 12)
	box.add_child(die_header)
	var die_row := HBoxContainer.new()
	die_row.name = "DieFaceRow"
	die_row.add_theme_constant_override("separation", 6)
	box.add_child(die_row)
	_die_chip_cold = _make_die_chip("TE KOUD", DIE_FACE_OFF)
	_die_chip_good = _make_die_chip("GOED GEHARD", DIE_FACE_OFF)
	_die_chip_hot  = _make_die_chip("TE HEET", DIE_FACE_OFF)
	die_row.add_child(_die_chip_cold)
	die_row.add_child(_die_chip_good)
	die_row.add_child(_die_chip_hot)
	# Initial paint so the panel doesn't flash all-dark for one frame.
	_refresh_die_face_chips()

## "STARTKNOP": the right white ring as a lamp, the sequence / alarm line, the
## alarm reset and the natraject setting. Only for a model with a start_seq.
func _add_start_row(box: VBoxContainer) -> void:
	_start_lamp = null
	_start_text = null
	_start_reset = null
	_natraject_toggle = null
	if _model.get("start_seq") == null:
		return
	var header := Label.new()
	header.text = "STARTKNOP  (rechts, witte ring)"
	header.add_theme_font_size_override("font_size", 13)
	box.add_child(header)
	var row := HBoxContainer.new()
	row.name = "StartRow"
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_start_lamp = Label.new()
	_start_lamp.name = "StartRingLamp"
	_start_lamp.add_theme_font_size_override("font_size", 18)
	row.add_child(_start_lamp)
	_start_text = Label.new()
	_start_text.name = "StartStatus"
	_start_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_start_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_start_text.add_theme_font_size_override("font_size", 12)
	row.add_child(_start_text)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 8)
	box.add_child(row2)
	_start_reset = Button.new()
	_start_reset.name = "StartAlarmReset"
	_start_reset.text = "ALARM RESET"
	_start_reset.pressed.connect(func():
		var seq = _model.get("start_seq") if _model != null else null
		if seq != null:
			seq.reset_alarm()
		_refresh_start_row()
	)
	row2.add_child(_start_reset)
	_natraject_toggle = CheckButton.new()
	_natraject_toggle.name = "NatrajectToggle"
	_natraject_toggle.text = "Natraject"
	_natraject_toggle.tooltip_text = "Diepe instelling: UIT = geen controle en geen start van het natraject, alleen de schroef. Niet voor normaal bedrijf."
	_natraject_toggle.toggled.connect(func(on: bool):
		var seq = _model.get("start_seq") if _model != null else null
		if seq != null:
			seq.natraject_enabled = on
		_refresh_start_row()
	)
	row2.add_child(_natraject_toggle)
	box.add_child(HSeparator.new())
	_refresh_start_row()

func _refresh_start_row() -> void:
	if _start_lamp == null or _model == null or not is_instance_valid(_model):
		return
	var seq = _model.get("start_seq")
	if seq == null:
		return
	var lit : bool = bool(seq.led_lit())
	_start_lamp.text = "●" if lit else "◯"
	_start_lamp.add_theme_color_override("font_color",
		Color(0.97, 0.97, 1.0) if lit else Color(0.30, 0.31, 0.34))
	_start_text.text = String(seq.status_text())
	_start_text.add_theme_color_override("font_color",
		Color(1.0, 0.45, 0.35) if String(seq.alarm) != "" else Color(0.85, 0.88, 0.92))
	_start_reset.disabled = String(seq.alarm) == ""
	_natraject_toggle.set_pressed_no_signal(bool(seq.natraject_enabled))

## "SCHROEFTOERENTAL": the rpm setpoint slider plus a setpoint / actual readout.
## Only built for a model that has the setpoint API and a config.
func _add_rpm_row(box: VBoxContainer) -> void:
	_rpm_slider = null
	_rpm_readout = null
	if not _model.has_method("set_screw_rpm_setpoint") or not ("config" in _model) \
			or _model.config == null:
		return
	var header := Label.new()
	header.text = "SCHROEFTOERENTAL  (rpm)"
	header.add_theme_font_size_override("font_size", 13)
	box.add_child(header)
	var row := HBoxContainer.new()
	row.name = "ScrewRpmRow"
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	var sl := HSlider.new()
	sl.name = "ScrewRpmSlider"
	sl.min_value = float(_model.config.screw_rpm_min)
	sl.max_value = maxf(sl.min_value, float(_model.config.screw_rpm_max))
	sl.step = 1.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.set_value_no_signal(float(_model.screw_rpm_setpoint))
	row.add_child(sl)
	var read := Label.new()
	read.name = "ScrewRpmReadout"
	read.custom_minimum_size = Vector2(150, 0)
	read.add_theme_font_size_override("font_size", 12)
	read.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(read)
	sl.value_changed.connect(func(v: float):
		if _model != null and is_instance_valid(_model):
			_model.call("set_screw_rpm_setpoint", v)
		_refresh_rpm_row()
	)
	_rpm_slider = sl
	_rpm_readout = read
	_refresh_rpm_row()

## Mirror the model into the rpm row. The web HMI's line strip writes the same
## setpoint, so the slider must follow the model, not the other way round.
func _refresh_rpm_row() -> void:
	if _rpm_slider == null or _model == null or not is_instance_valid(_model):
		return
	var sp : float = float(_model.screw_rpm_setpoint)
	if not is_equal_approx(_rpm_slider.value, sp):
		_rpm_slider.set_value_no_signal(sp)
	if _rpm_readout != null:
		_rpm_readout.text = "sp %.0f  |  act %.0f rpm" % [sp, float(_model.screw_rpm)]

func _add_zone_row(box: VBoxContainer, i: int, zone_names: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	# Zone-name label
	var lbl := Label.new()
	var nm : String = String(zone_names[i]) if i < zone_names.size() else "zone_%d" % (i + 1)
	lbl.text = "  %d. %s" % [i + 1, nm.to_upper()]
	lbl.custom_minimum_size = Vector2(150, 0)
	lbl.add_theme_font_size_override("font_size", 12)
	row.add_child(lbl)
	# Slider
	var sl := HSlider.new()
	sl.min_value = TEMP_MIN_C
	sl.max_value = TEMP_MAX_C
	sl.step = 1.0
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var current : float = TEMP_MIN_C
	if _model.has_method("get_zone_temp"):
		current = float(_model.call("get_zone_temp", i))
	current = clampf(current, TEMP_MIN_C, TEMP_MAX_C)
	sl.value = current
	row.add_child(sl)
	# Numeric readout
	var read := Label.new()
	read.text = "%.0f °C" % current
	read.custom_minimum_size = Vector2(60, 0)
	read.add_theme_font_size_override("font_size", 12)
	read.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(read)
	# Wire the slider change → model + readout. Bind the zone index so the
	# lambda knows which slider fired.
	var idx := i
	sl.value_changed.connect(func(v: float):
		read.text = "%.0f °C" % v
		if _model != null and is_instance_valid(_model) \
				and _model.has_method("set_zone_temp"):
			_model.call("set_zone_temp", idx, v)
	)
	_sliders.append(sl)
	_readouts.append(read)

## Build a single die-face chip. PanelContainer with a coloured StyleBoxFlat
## so we can recolour it live; Label child carries the text. Returned by ref
## so the caller can stash it for per-frame recolour.
func _make_die_chip(text: String, fill: Color) -> PanelContainer:
	var chip := PanelContainer.new()
	chip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.corner_radius_top_left = 3
	sb.corner_radius_top_right = 3
	sb.corner_radius_bottom_left = 3
	sb.corner_radius_bottom_right = 3
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 3
	sb.content_margin_bottom = 3
	chip.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.96, 0.96, 0.96))
	chip.add_child(lbl)
	return chip

## Recolour the three chips so only the active state glows. The model's
## get_die_face_state() is duck-typed to return an int:
##   0 = TE KOUD, 1 = GOED GEHARD, 2 = TE HEET. Anything else → all dark.
func _refresh_die_face_chips() -> void:
	if _die_chip_cold == null or _die_chip_good == null or _die_chip_hot == null:
		return
	var state : int = 1   # default to GOED so a model that doesn't expose
	                       # the method still looks normal rather than alarming
	if _model != null and is_instance_valid(_model) \
			and _model.has_method("get_die_face_state"):
		state = int(_model.call("get_die_face_state"))
	_set_chip_fill(_die_chip_cold, DIE_FACE_COLD_ON if state == 0 else DIE_FACE_OFF)
	_set_chip_fill(_die_chip_good, DIE_FACE_GOOD_ON if state == 1 else DIE_FACE_OFF)
	_set_chip_fill(_die_chip_hot,  DIE_FACE_HOT_ON  if state == 2 else DIE_FACE_OFF)

## Update the panel stylebox's bg_color in place (mutates the existing flat
## stylebox so the chip's geometry/margin don't get rebuilt every frame).
func _set_chip_fill(chip: PanelContainer, c: Color) -> void:
	if chip == null:
		return
	var sb := chip.get_theme_stylebox("panel")
	if sb is StyleBoxFlat:
		(sb as StyleBoxFlat).bg_color = c

func _process(_dt: float) -> void:
	# Live die-face state — cheap (just three colour writes when the state
	# changes) so per-frame polling is fine. The model owns the state machine;
	# the panel only mirrors it.
	if _die_chip_cold != null:
		_refresh_die_face_chips()
	_refresh_rpm_row()
	_refresh_start_row()

## Refresh the displayed values from the model (e.g. after another caller
## changed a setpoint via the API). Doesn't fire value_changed.
func refresh_from_model() -> void:
	if _model == null:
		return
	for i in _sliders.size():
		if not _model.has_method("get_zone_temp"):
			break
		var v : float = float(_model.call("get_zone_temp", i))
		_sliders[i].set_value_no_signal(v)
		_readouts[i].text = "%.0f °C" % v
	_refresh_die_face_chips()
	_refresh_rpm_row()
	_refresh_start_row()
