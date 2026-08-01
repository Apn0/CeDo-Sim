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
