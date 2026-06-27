extends Control

## KufferathsDryerScope — German-language Kufferath DRD dryer-pair controller HUD.
##
## Models the real "PARAMETER" screen seen at CeDo on the Kufferath line: two
## DRD drums (DRD1 + DRD2) shown side-by-side, each driven by a MechDryerCycle.
## The antiphase visualization is the headline feature — when DRD1 is BEFÜLLEN,
## DRD2 should be ENTLEEREN and vice versa, so the operator instantly sees the
## 180° phase offset working.
##
## This is the first per-scope panel under src/scenes/hud/scopes/. HmiOverlay
## will instantiate it inside a new screen branch when the active scope token
## set includes a kufferath / drd hint. Until that branch is wired, the panel
## is also usable as a standalone CanvasItem (e.g. inside a debug viewer).

class_name KufferathsDryerScope

signal request_close()
## #218 — Trocknungs-Automatik EIN/AUS click → external listeners.
## dryer_index is 0 (DRD1) or 1 (DRD2); on=true means EIN was pressed.
## The scope ALSO calls enable_cycle()/disable_cycle() directly on the
## bound MechDryerCycle (when present), so a model is updated synchronously
## even without an external listener.
signal dryer_automatik_toggled(dryer_index : int, on : bool)

@export var line_id : String = "3C"

# ---------------------------------------------------------------------------- colours
const C_BG          := Color(0.20, 0.20, 0.22, 1.0)
const C_PANEL       := Color(0.13, 0.13, 0.15, 1.0)
const C_HEADER      := Color(0.07, 0.45, 0.15, 1.0)   # DRD1/DRD2 green title bar
const C_TITLE_BAR   := Color(0.10, 0.10, 0.12, 1.0)   # "PARAMETER" top strip
const C_ROW_A       := Color(0.16, 0.16, 0.18, 1.0)
const C_ROW_B       := Color(0.19, 0.19, 0.21, 1.0)
const C_VALUE_BOX   := Color(0.08, 0.08, 0.10, 1.0)
const C_TEXT        := Color(0.95, 0.95, 0.95, 1.0)
const C_TEXT_DIM    := Color(0.70, 0.70, 0.72, 1.0)
const C_GREEN_ON    := Color(0.20, 0.78, 0.27, 1.0)
const C_RED_OFF     := Color(0.85, 0.18, 0.18, 1.0)
const C_TAB         := Color(0.12, 0.12, 0.14, 1.0)
const C_TAB_ACTIVE  := Color(0.07, 0.45, 0.15, 1.0)

# ---------------------------------------------------------------------------- runtime refs
var _dryer_cycles : Array = []           # exactly 2 MechDryerCycle entries

# Title bar
var _title_lbl  : Label
var _clock_lbl  : Label

# Per-column value labels [0] = DRD1, [1] = DRD2
var _motorlast       : Array = [null, null]
var _schritt         : Array = [null, null]
var _schritt_runtime : Array = [null, null]
var _trockenzeit     : Array = [null, null]
var _befulstop       : Array = [null, null]
var _entleerstop     : Array = [null, null]
var _temp_sollwert   : Array = [null, null]
var _korr_temp_drd   : Array = [null, null]
var _korr_temp_ent   : Array = [null, null]
var _silo_voll       : Array = [null, null]
var _standby         : Array = [null, null]

# Toggle (EIN / AUS) pair: [drd_idx][0] = EIN ColorRect, [drd_idx][1] = AUS ColorRect
var _automatik_ein : Array = [null, null]
var _automatik_aus : Array = [null, null]
var _heizung_ein   : Array = [null, null]
var _heizung_aus   : Array = [null, null]

# Schieber timing (constants displayed; no editing wired yet)
var _entleer_takt  : Array = [null, null]
var _entleer_pause : Array = [null, null]
var _besch_offen   : Array = [null, null]
var _besch_zu      : Array = [null, null]
var _entleer_lauf  : Array = [null, null]

var _built : bool = false

# ---------------------------------------------------------------------------- public API

func set_dryer_pair(cycles : Array) -> void:
	## Accept exactly 2 MechDryerCycle references. Order = [DRD1, DRD2].
	_dryer_cycles = []
	for c in cycles:
		if c != null:
			_dryer_cycles.append(c)
	while _dryer_cycles.size() < 2:
		_dryer_cycles.append(null)
	if _built:
		_refresh()

# ---------------------------------------------------------------------------- lifecycle

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(960, 600)
	if not _built:
		_build()
		_built = true
	set_process(true)

func _process(_delta : float) -> void:
	if visible and _built:
		_refresh()

# ---------------------------------------------------------------------------- build

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = C_BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	root.add_child(_build_title_bar())

	var cols := HBoxContainer.new()
	cols.add_theme_constant_override("separation", 8)
	cols.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	cols.add_child(_build_drd_column(0, "DRD 1"))
	cols.add_child(_build_drd_column(1, "DRD 2"))

	root.add_child(_build_tab_bar())

func _build_title_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TITLE_BAR
	bar.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	bar.add_child(h)

	_title_lbl = Label.new()
	_title_lbl.text = "PARAMETER"
	_title_lbl.add_theme_color_override("font_color", C_TEXT)
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(_title_lbl)

	_clock_lbl = Label.new()
	_clock_lbl.text = "Samstag, 29. Juni 2024  13:41:38"
	_clock_lbl.add_theme_color_override("font_color", C_TEXT)
	_clock_lbl.add_theme_font_size_override("font_size", 16)
	h.add_child(_clock_lbl)

	return bar

func _build_drd_column(idx : int, header_text : String) -> Control:
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_PANEL
	panel.add_theme_stylebox_override("panel", sb)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	panel.add_child(col)

	# Header
	var header := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = C_HEADER
	header.add_theme_stylebox_override("panel", hsb)
	var hlbl := Label.new()
	hlbl.text = header_text
	hlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hlbl.add_theme_color_override("font_color", C_TEXT)
	hlbl.add_theme_font_size_override("font_size", 18)
	header.add_child(hlbl)
	col.add_child(header)

	# Parameter rows
	_motorlast[idx]       = _add_value_row(col, "Motorlast",                    "0 %",      true)
	_schritt[idx]         = _add_value_row(col, "Schritt",                      "0: Idle",  false)
	_schritt_runtime[idx] = _add_value_row(col, "Schrittlaufzeit",              "0 s",      true)
	_trockenzeit[idx]     = _add_value_row(col, "Trockenzeit",                  "30 s",     false)
	_befulstop[idx]       = _add_value_row(col, "Befüllstop DRD",               "90 %",     true)
	_entleerstop[idx]     = _add_value_row(col, "Entleerstop DRD",              "60 %",     false)
	_temp_sollwert[idx]   = _add_value_row(col, "Temperatur Sollwert DRD",      "40 °C",    true)

	# EIN/AUS toggles
	_add_toggle_row(col, idx, "Trocknungs-Automatik", "auto", false)
	_add_toggle_row(col, idx, "Heizregister",         "heiz", true)

	# Entleerschieber pulse pair
	_add_pulse_row(col, idx, "Entleerschieber",
		"Taktzeit",  "2 s",
		"Pausezeit", "4 s",
		false, "entleer")

	# Beschickungsschieber pulse pair (Offen / Geschlossen)
	_add_pulse_row(col, idx, "Laufzeit Beschickungsschieber",
		"Offen",       "12 s",
		"Geschlossen", "120 s",
		true, "besch")

	_entleer_lauf[idx] = _add_value_row(col, "Laufzeit Entleerschieber", "12 s", false)

	_korr_temp_drd[idx] = _add_value_row(col, "Korrekturwert Temperatur DRD",
		("+13 °C" if idx == 0 else "+15 °C"), true)
	_korr_temp_ent[idx] = _add_value_row(col, "Korrekturwert Temperatur Entstaubung",
		("+83 °C" if idx == 0 else "+98 °C"), false)

	# Final dual-value row (Silo voll | Standby)
	_add_pulse_row(col, idx, "",
		"Silo voll", "3 s",
		"Standby",   "3 s",
		true, "siloStandby")

	# Spacer pushes content to the top
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(spacer)

	return panel

func _add_value_row(parent : Control, label_text : String, initial_value : String, zebra_a : bool) -> Label:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ROW_A if zebra_a else C_ROW_B
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)

	var val_panel := PanelContainer.new()
	var vsb := StyleBoxFlat.new()
	vsb.bg_color = C_VALUE_BOX
	val_panel.add_theme_stylebox_override("panel", vsb)
	val_panel.custom_minimum_size = Vector2(110, 0)
	h.add_child(val_panel)

	var val_lbl := Label.new()
	val_lbl.text = initial_value
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_color_override("font_color", C_TEXT)
	val_lbl.add_theme_font_size_override("font_size", 14)
	val_panel.add_child(val_lbl)

	parent.add_child(row)
	return val_lbl

func _add_toggle_row(parent : Control, idx : int, label_text : String, slot : String, zebra_a : bool) -> void:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ROW_A if zebra_a else C_ROW_B
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)

	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.add_theme_color_override("font_color", C_TEXT)
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(name_lbl)

	var ein := _make_toggle_pill("EIN", C_GREEN_ON)
	var aus := _make_toggle_pill("AUS", C_RED_OFF)
	h.add_child(ein)
	h.add_child(aus)

	if slot == "auto":
		_automatik_ein[idx] = ein
		_automatik_aus[idx] = aus
		# #218 — make Trocknungs-Automatik EIN/AUS clickable so the operator
		# can actually arm / park the dryer cycle from the panel. Pills are
		# PanelContainers (no `pressed` signal), so we listen on gui_input
		# for a left-click release and route through _on_automatik_pressed.
		ein.mouse_filter = Control.MOUSE_FILTER_STOP
		aus.mouse_filter = Control.MOUSE_FILTER_STOP
		ein.gui_input.connect(_on_automatik_pill_gui_input.bind(idx, true))
		aus.gui_input.connect(_on_automatik_pill_gui_input.bind(idx, false))
	elif slot == "heiz":
		_heizung_ein[idx] = ein
		_heizung_aus[idx] = aus

	parent.add_child(row)

## #218 — Trocknungs-Automatik pill click handler. Bound per pill so the same
## function services all four (DRD1/DRD2 × EIN/AUS). Fires the public
## dryer_automatik_toggled signal AND calls enable_cycle / disable_cycle on
## the matching MechDryerCycle when one is bound — so a scope with no
## external listener still does the right thing locally.
func _on_automatik_pill_gui_input(event : InputEvent, dryer_index : int, on : bool) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb : InputEventMouseButton = event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or mb.pressed:
		return   # fire on release, not press, to match Button semantics
	emit_signal("dryer_automatik_toggled", dryer_index, on)
	if dryer_index >= 0 and dryer_index < _dryer_cycles.size():
		var cycle = _dryer_cycles[dryer_index]
		if cycle != null:
			if on and cycle.has_method("enable_cycle"):
				cycle.call("enable_cycle")
			elif (not on) and cycle.has_method("disable_cycle"):
				cycle.call("disable_cycle")
	# Optimistic visual update — _refresh() will re-derive from cycle.step on
	# the next tick, but flipping the pills now removes the click-feel lag.
	_set_pill_on(_automatik_ein[dryer_index], on)
	_set_pill_on(_automatik_aus[dryer_index], not on)

func _make_toggle_pill(text : String, active_color : Color) -> Control:
	var pill := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	sb.corner_radius_top_left = 4
	sb.corner_radius_top_right = 4
	sb.corner_radius_bottom_left = 4
	sb.corner_radius_bottom_right = 4
	pill.add_theme_stylebox_override("panel", sb)
	pill.custom_minimum_size = Vector2(48, 0)
	pill.set_meta("active_color", active_color)
	pill.set_meta("on", false)

	var lbl := Label.new()
	lbl.text = text
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", C_TEXT)
	lbl.add_theme_font_size_override("font_size", 13)
	pill.add_child(lbl)

	return pill

func _set_pill_on(pill : Control, on : bool) -> void:
	if pill == null:
		return
	var sb := pill.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	if on:
		sb.bg_color = pill.get_meta("active_color", C_GREEN_ON)
	else:
		sb.bg_color = Color(0.18, 0.18, 0.20, 1.0)
	pill.set_meta("on", on)

func _add_pulse_row(parent : Control, idx : int, label_text : String,
		left_name : String, left_init : String,
		right_name : String, right_init : String,
		zebra_a : bool, slot : String) -> void:
	var row := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_ROW_A if zebra_a else C_ROW_B
	row.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 8)
	row.add_child(h)

	if label_text != "":
		var name_lbl := Label.new()
		name_lbl.text = label_text
		name_lbl.add_theme_color_override("font_color", C_TEXT)
		name_lbl.add_theme_font_size_override("font_size", 14)
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(name_lbl)
	else:
		var spc := Control.new()
		spc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(spc)

	var left_lbl := Label.new()
	left_lbl.text = left_name
	left_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	left_lbl.add_theme_font_size_override("font_size", 13)
	h.add_child(left_lbl)

	var left_val_panel := PanelContainer.new()
	var lvsb := StyleBoxFlat.new()
	lvsb.bg_color = C_VALUE_BOX
	left_val_panel.add_theme_stylebox_override("panel", lvsb)
	left_val_panel.custom_minimum_size = Vector2(70, 0)
	h.add_child(left_val_panel)

	var left_val_lbl := Label.new()
	left_val_lbl.text = left_init
	left_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	left_val_lbl.add_theme_color_override("font_color", C_TEXT)
	left_val_lbl.add_theme_font_size_override("font_size", 13)
	left_val_panel.add_child(left_val_lbl)

	var right_lbl := Label.new()
	right_lbl.text = right_name
	right_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	right_lbl.add_theme_font_size_override("font_size", 13)
	h.add_child(right_lbl)

	var right_val_panel := PanelContainer.new()
	var rvsb := StyleBoxFlat.new()
	rvsb.bg_color = C_VALUE_BOX
	right_val_panel.add_theme_stylebox_override("panel", rvsb)
	right_val_panel.custom_minimum_size = Vector2(70, 0)
	h.add_child(right_val_panel)

	var right_val_lbl := Label.new()
	right_val_lbl.text = right_init
	right_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	right_val_lbl.add_theme_color_override("font_color", C_TEXT)
	right_val_lbl.add_theme_font_size_override("font_size", 13)
	right_val_panel.add_child(right_val_lbl)

	if slot == "entleer":
		_entleer_takt[idx]  = left_val_lbl
		_entleer_pause[idx] = right_val_lbl
	elif slot == "besch":
		_besch_offen[idx] = left_val_lbl
		_besch_zu[idx]    = right_val_lbl
	elif slot == "siloStandby":
		_silo_voll[idx] = left_val_lbl
		_standby[idx]   = right_val_lbl

	parent.add_child(row)

func _build_tab_bar() -> Control:
	var bar := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TITLE_BAR
	bar.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	bar.add_child(h)

	var tabs : Array = ["MAIN", "PARAMETER", "HANDBETRIEB", "ZYKLUSDATEN", "SYSTEM", "ALARME"]
	for i in tabs.size():
		var t : String = tabs[i]
		var active : bool = (t == "PARAMETER")
		var btn := Button.new()
		btn.text = t
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.custom_minimum_size = Vector2(0, 32)
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = C_TAB_ACTIVE if active else C_TAB
		btn.add_theme_stylebox_override("normal", bsb)
		btn.add_theme_stylebox_override("hover", bsb)
		btn.add_theme_stylebox_override("pressed", bsb)
		btn.add_theme_color_override("font_color", C_TEXT)
		btn.add_theme_font_size_override("font_size", 14)
		btn.disabled = not active   # only PARAMETER is implemented (spec stub)
		h.add_child(btn)

	return bar

# ---------------------------------------------------------------------------- refresh

func _refresh() -> void:
	# Clock — leave the prop-style German date string in place, only update the
	# H:MM:SS tail with the live wall clock so the panel feels alive.
	var t := Time.get_time_dict_from_system()
	_clock_lbl.text = "Samstag, 29. Juni 2024  %02d:%02d:%02d" % [t.hour, t.minute, t.second]

	for i in 2:
		var cycle = _dryer_cycles[i] if i < _dryer_cycles.size() else null
		_refresh_column(i, cycle)

func _refresh_column(idx : int, cycle) -> void:
	if cycle == null:
		_set_lbl(_motorlast[idx], "-- %")
		_set_lbl(_schritt[idx], "-- offline")
		_set_lbl(_schritt_runtime[idx], "-- s")
		_set_pill_on(_automatik_ein[idx], false)
		_set_pill_on(_automatik_aus[idx], true)
		_set_pill_on(_heizung_ein[idx], false)
		_set_pill_on(_heizung_aus[idx], true)
		return

	# Motorlast — proxy from heater-on + step; the model doesn't expose load
	# directly, so we approximate from fill_pct since drum load scales with mass.
	var fill : float = 0.0
	if cycle.dryer != null:
		fill = float(cycle.dryer.fill_pct)
	var motorlast_pct : int = int(round(clamp(fill, 0.0, 100.0)))
	_set_lbl(_motorlast[idx], "%d %%" % motorlast_pct)

	_set_lbl(_schritt[idx], _step_label(cycle.step))
	_set_lbl(_schritt_runtime[idx], "%d s" % int(round(float(cycle.step_elapsed_s))))

	_set_lbl(_trockenzeit[idx],   "%d s"  % int(round(float(cycle.trockenzeit_s))))
	_set_lbl(_befulstop[idx],     "%d %%" % int(round(float(cycle.befuelstop_pct))))
	_set_lbl(_entleerstop[idx],   "%d %%" % int(round(float(cycle.entleerstop_pct))))
	_set_lbl(_temp_sollwert[idx], "%d °C" % int(round(float(cycle.temp_sollwert_c))))

	# EIN/AUS pills: any non-IDLE step counts as automatic cycle running.
	var auto_on : bool = (int(cycle.step) != 0)   # 0 == MechDryerCycle.Step.IDLE
	_set_pill_on(_automatik_ein[idx], auto_on)
	_set_pill_on(_automatik_aus[idx], not auto_on)

	var heater_on : bool = false
	if cycle.dryer != null and "heater_on" in cycle.dryer:
		heater_on = bool(cycle.dryer.heater_on)
	_set_pill_on(_heizung_ein[idx], heater_on)
	_set_pill_on(_heizung_aus[idx], not heater_on)

	# Schieber timings come from MechDryerCycle constants.
	_set_lbl(_entleer_takt[idx],  "%d s" % int(round(float(cycle.ENTLEER_OPEN_S))))
	_set_lbl(_entleer_pause[idx], "%d s" % int(round(float(cycle.ENTLEER_CLOSE_S))))
	_set_lbl(_besch_offen[idx],   "%d s" % int(round(float(cycle.BESCH_OPEN_S))))
	_set_lbl(_besch_zu[idx],      "%d s" % int(round(float(cycle.BESCH_CLOSE_S))))

func _step_label(step_int : int) -> String:
	# Mirror MechDryerCycle.Step enum order (IDLE=0, BEFULLEN=1, TROCKNEN=2, ENTLEEREN=3).
	# Step numbers shown match the operator-photo "Schritt" column (3 / 5 / 6).
	match step_int:
		0: return "0: Idle"
		1: return "3: Befüllen"
		2: return "5: Trocknen"
		3: return "6: Entleeren"
		_: return "?: --"

func _set_lbl(lbl : Label, txt : String) -> void:
	if lbl != null:
		lbl.text = txt

# ---------------------------------------------------------------------------- close

func _unhandled_input(event : InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		emit_signal("request_close")
		accept_event()
