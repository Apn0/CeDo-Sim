extends CanvasLayer
## Quality-analysis terminal (v1). Walk up to a QualityAnalysisBench and press E
## to open this overlay. Reads live extruder telemetry from MainWorld's LineFlow
## (MFI proxy, melt-temp, die-pressure, line throughput) and shows the most
## recent QA samples — what the operator at the bench would actually see.
##
## v1 scope: display-only. A "Submit sample" button enters a stub entry on a
## local sample log so the workflow is testable; full lab integration (rejection
## flagging into MotorOverload / SCADA, batch-grade certificate output) sits
## alongside #46 (MFI proxy) for a later pass — flagged in the panel footer.

const C_PANEL : Color = Color(0.09, 0.11, 0.13, 1.0)
const C_HEAD  : Color = Color(0.34, 0.78, 0.92, 1.0)
const C_TEXT  : Color = Color(0.88, 0.92, 0.96, 1.0)
const C_DIM   : Color = Color(0.58, 0.62, 0.66, 1.0)
const C_OK    : Color = Color(0.30, 0.92, 0.42, 1.0)
const C_WARN  : Color = Color(0.94, 0.74, 0.20, 1.0)

var _built : bool = false
var _bus : Node = null
var _readout_grid : GridContainer = null
var _sample_grid  : GridContainer = null
var _foot : Label = null
var _samples : Array = []   # local log of submitted samples this session

func _ready() -> void:
	layer = 60
	visible = false

func toggle() -> void:
	if visible:
		close()
	else:
		open()

func open() -> void:
	if not _built:
		_build()
		_built = true
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()

func close() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func setup(bus: Node) -> void:
	_bus = bus

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(centre)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 500)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_PANEL
	psb.set_corner_radius_all(8)
	psb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", psb)
	centre.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "KWALITEITSCONTROLE  ·  QA-WERKBANK"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_TEXT)
	vb.add_child(title)

	# Live extruder telemetry grid.
	var sub_live := Label.new()
	sub_live.text = "Live extruder-telemetrie"
	sub_live.add_theme_font_size_override("font_size", 15)
	sub_live.add_theme_color_override("font_color", C_HEAD)
	vb.add_child(sub_live)
	_readout_grid = GridContainer.new()
	_readout_grid.columns = 2
	_readout_grid.add_theme_constant_override("h_separation", 24)
	_readout_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_readout_grid)

	vb.add_child(HSeparator.new())

	# Sample log grid.
	var sub_samples := Label.new()
	sub_samples.text = "Monsters deze dienst"
	sub_samples.add_theme_font_size_override("font_size", 15)
	sub_samples.add_theme_color_override("font_color", C_HEAD)
	vb.add_child(sub_samples)
	_sample_grid = GridContainer.new()
	_sample_grid.columns = 4
	_sample_grid.add_theme_constant_override("h_separation", 22)
	_sample_grid.add_theme_constant_override("v_separation", 4)
	vb.add_child(_sample_grid)

	vb.add_child(HSeparator.new())

	# Action row.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 12)
	vb.add_child(actions)
	var submit := Button.new()
	submit.text = "MONSTER INDIENEN"
	submit.tooltip_text = "Voeg een nieuw monster toe op basis van de huidige live-meting."
	submit.pressed.connect(_on_submit_sample)
	actions.add_child(submit)
	var refresh := Button.new()
	refresh.text = "VERVERSEN"
	refresh.pressed.connect(_refresh)
	actions.add_child(refresh)

	_foot = Label.new()
	_foot.add_theme_font_size_override("font_size", 12)
	_foot.add_theme_color_override("font_color", C_DIM)
	_foot.text = "v1 read-out — volledige lab-integratie (MFI-koppeling, certificering) volgt."
	vb.add_child(_foot)

	var closeb := Button.new()
	closeb.text = "SLUITEN  (Esc)"
	closeb.pressed.connect(close)
	vb.add_child(closeb)

func _refresh() -> void:
	if not _built:
		return
	_refresh_telemetry()
	_refresh_samples()

func _refresh_telemetry() -> void:
	for ch in _readout_grid.get_children():
		_readout_grid.remove_child(ch)
		ch.queue_free()
	var lf : Node = _find_lineflow()
	if lf == null:
		_readout_grid.add_child(_cell("Status:", C_DIM))
		_readout_grid.add_child(_cell("LineFlow niet gevonden", C_WARN))
		return
	# Pull whatever telemetry is exposed; absent fields fall back to "—".
	var rows : Array = []
	rows.append(["MFI-proxy (g/10min)", _fmt_metric(lf, "mfi_value", " g/10min")])
	rows.append(["Smelttemperatuur",     _fmt_metric(lf, "melt_temp",  " °C")])
	rows.append(["Spuitkop-druk",        _fmt_metric(lf, "die_pressure", " bar")])
	rows.append(["Doorzet (kg/s)",       _fmt_metric(lf, "thru", " kg/s")])
	rows.append(["Vochtigheid",          _fmt_metric(lf, "moist", " %")])
	rows.append(["Verontreiniging",      _fmt_metric(lf, "contam", " %")])
	for r in rows:
		_readout_grid.add_child(_cell(String(r[0]), C_TEXT))
		_readout_grid.add_child(_cell(String(r[1]), C_OK))

func _refresh_samples() -> void:
	for ch in _sample_grid.get_children():
		_sample_grid.remove_child(ch)
		ch.queue_free()
	for h in ["TIJD", "MFI", "SMELT-T", "OORDEEL"]:
		var hl := _cell(h, C_HEAD)
		hl.add_theme_font_size_override("font_size", 13)
		_sample_grid.add_child(hl)
	if _samples.is_empty():
		_sample_grid.add_child(_cell("— nog geen monsters —", C_DIM))
		for _i in 3:
			_sample_grid.add_child(_cell("", C_DIM))
		return
	for s in _samples:
		_sample_grid.add_child(_cell(String(s.get("time", "--:--")), C_TEXT))
		_sample_grid.add_child(_cell(String(s.get("mfi",  "—")), C_TEXT))
		_sample_grid.add_child(_cell(String(s.get("melt", "—")), C_TEXT))
		var verdict := String(s.get("verdict", "—"))
		_sample_grid.add_child(_cell(verdict, C_OK if verdict == "OK" else C_WARN))

func _on_submit_sample() -> void:
	var lf : Node = _find_lineflow()
	var entry := {
		"time":    Time.get_time_string_from_system().substr(0, 5),
		"mfi":     _fmt_metric(lf, "mfi_value", ""),
		"melt":    _fmt_metric(lf, "melt_temp", "°C"),
		# v1 verdict: OK if MFI is in a reasonable LDPE band (0.5..3.0), else CHECK.
		"verdict": "OK",
	}
	# Simple grading: parse the raw mfi number out of the formatted string.
	var raw := String(entry["mfi"]).get_slice(" ", 0)
	if raw != "—":
		var v := raw.to_float()
		if v < 0.4 or v > 3.5:
			entry["verdict"] = "CHECK"
	_samples.push_front(entry)
	if _samples.size() > 12:
		_samples.resize(12)
	_refresh_samples()

func _find_lineflow() -> Node:
	var world : Node = get_tree().current_scene
	if world == null:
		return null
	return world.find_child("LineFlow", true, false)

func _fmt_metric(lf: Node, field: String, suffix: String) -> String:
	if lf == null:
		return "—"
	# LineFlow tracks per-node telemetry in its _nodes array; we surface a
	# summary by picking the first extruder-class node we find. For "thru" /
	# "moist" / "contam" we use the SAME extruder so the numbers correlate.
	var sample : Dictionary = _first_extruder_node(lf)
	if sample.is_empty() or not sample.has(field):
		return "—"
	var v : float = float(sample[field])
	return "%.2f%s" % [v, suffix]

func _first_extruder_node(lf: Node) -> Dictionary:
	if lf == null or not "_nodes" in lf:
		return {}
	for nd in lf.get("_nodes"):
		if not (nd is Dictionary):
			continue
		var id := String(nd.get("id", ""))
		if id.begins_with("extruder_") or id == "extruder_3a" or id == "extruder_3b":
			return nd
	return {}

func _cell(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	return l

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
