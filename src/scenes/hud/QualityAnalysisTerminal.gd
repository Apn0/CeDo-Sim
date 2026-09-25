extends CanvasLayer
## Quality-analysis terminal (v1). Walk up to a QualityAnalysisBench and press E
## to open this overlay. Reads live extruder telemetry from MainWorld's LineFlow
## (MFI proxy, melt-temp, die-pressure, line throughput) and shows the most
## recent QA samples — what the operator at the bench would actually see.
##
## v2: backed by the real QaLab (src/sim/QaLab.gd) held on LineFlow, not by a
## per-terminal stub log. The panel's job is to make ONE thing legible:
##
##   the live readout is instant, and the lab result is not.
##
## So the sample grid shows pending samples counting down on the bench next to
## resolved ones carrying a verdict. That gap is what the trainee is being
## taught to reason about — the proxy reads fine, the bench lands ten minutes
## later, and the line kept running in between.
##
## The lab is resolved off LineFlow rather than injected, so two placed benches
## share ONE lab and one sample log. (Each bench builds its own terminal
## instance parented to the tree root — QualityAnalysisBench.gd:150 — so an
## injected lab would give each bench a private history of the same line.)

const C_PANEL : Color = Color(0.09, 0.11, 0.13, 1.0)
const C_HEAD  : Color = Color(0.34, 0.78, 0.92, 1.0)
const C_TEXT  : Color = Color(0.88, 0.92, 0.96, 1.0)
const C_DIM   : Color = Color(0.58, 0.62, 0.66, 1.0)
const C_OK    : Color = Color(0.30, 0.92, 0.42, 1.0)
const C_WARN  : Color = Color(0.94, 0.74, 0.20, 1.0)
## Three verdicts need three colours; the file previously had only two.
const C_BAD   : Color = Color(0.95, 0.34, 0.32, 1.0)

var _built : bool = false
var _bus : Node = null
var _readout_grid : GridContainer = null
var _sample_grid  : GridContainer = null
var _foot : Label = null
var _lab_connected : bool = false
var _repaint_accum : float = 0.0

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
	# Connect only AFTER _build(), never in setup(): _refresh() early-returns
	# while _built is false, so a callback wired before the panel exists is a
	# silent no-op. There is no _process and no timer in this file — every
	# number is a snapshot, so without this the countdown would never move.
	_connect_lab()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_refresh()


func _connect_lab() -> void:
	if _lab_connected:
		return
	var lab : Object = _find_lab(_find_lineflow())
	if lab == null or not lab.has_signal("sample_ready"):
		return
	lab.connect("sample_ready", Callable(self, "_on_sample_ready"))
	_lab_connected = true


func _on_sample_ready(_result: Dictionary) -> void:
	if visible:
		_refresh()


## Throttled repaint so the bench countdown visibly ticks. Only runs while the
## panel is open, and only rebuilds the sample grid — the telemetry rows are
## rebuilt on the same beat because they are the "instant" half of the contrast
## the panel exists to show. 2 Hz is enough for an mm:ss readout and keeps this
## off HotspotProfiler.
func _process(delta: float) -> void:
	if not visible or not _built:
		return
	_repaint_accum += delta
	if _repaint_accum < 0.5:
		return
	_repaint_accum = 0.0
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
	_sample_grid.columns = 6
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
	_foot.text = "De MFI-proxy is direct; de bank duurt 10 minuten. De lijn draait door."
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
	# The die plate, after the kopfilter (operator ruling 2026-09-24). This row
	# used to say "Spuitkop-druk", a word that appears in no plant document.
	rows.append(["Matrijsdruk (na kopfilter)", _fmt_metric(lf, "die_pressure", " bar")])
	rows.append(["Doorzet (kg/s)",       _fmt_metric(lf, "thru", " kg/s")])
	rows.append(["Vochtigheid",          _fmt_metric(lf, "moist", " %")])
	rows.append(["Verontreiniging",      _fmt_metric(lf, "contam", " %")])
	for r in rows:
		_readout_grid.add_child(_cell(String(r[0]), C_TEXT))
		_readout_grid.add_child(_cell(String(r[1]), C_OK))

## Pending samples FIRST, counting down, then resolved ones with their verdict.
## Showing both together is the whole teaching point: the bench is slow and the
## line is not.
func _refresh_samples() -> void:
	for ch in _sample_grid.get_children():
		_sample_grid.remove_child(ch)
		ch.queue_free()
	for h in ["MONSTER", "MFI", "VOCHT", "VUIL", "OORDEEL", "STATUS"]:
		var hl := _cell(h, C_HEAD)
		hl.add_theme_font_size_override("font_size", 13)
		_sample_grid.add_child(hl)

	var lab : Object = _find_lab(_find_lineflow())
	if lab == null:
		_sample_grid.add_child(_cell("— geen lab actief —", C_DIM))
		for _i in 5:
			_sample_grid.add_child(_cell("", C_DIM))
		return

	var pending : Array = lab.pending()
	var rows : Array = lab.log_rows(10)
	if pending.is_empty() and rows.is_empty():
		_sample_grid.add_child(_cell("— nog geen monsters —", C_DIM))
		for _i in 5:
			_sample_grid.add_child(_cell("", C_DIM))
		return

	for p in pending:
		_sample_grid.add_child(_cell("#%d" % int(p["sample_id"]), C_TEXT))
		for _i in 4:
			_sample_grid.add_child(_cell("op de bank", C_DIM))
		_sample_grid.add_child(_cell("nog %s" % _mmss(float(p["remaining_s"])), C_WARN))

	for r in rows:
		_sample_grid.add_child(_cell("#%d" % int(r["sample_id"]), C_TEXT))
		_sample_grid.add_child(_cell(_num(float(r.get("mfi", NAN)), 2), C_TEXT))
		_sample_grid.add_child(_cell("%.2f%%" % float(r.get("moisture_pct", 0.0)), C_TEXT))
		_sample_grid.add_child(_cell("%.2f%%" % float(r.get("contam_pct", 0.0)), C_TEXT))
		var verdict := String(r.get("verdict", "—"))
		_sample_grid.add_child(_cell(verdict, _verdict_colour(verdict)))
		var reasons : Array = r.get("reasons", [])
		_sample_grid.add_child(_cell("—" if reasons.is_empty() else ", ".join(reasons), C_DIM))


func _verdict_colour(verdict: String) -> Color:
	match verdict:
		"ACCEPT":  return C_OK
		"REGRADE": return C_WARN
		"REJECT":  return C_BAD
	return C_DIM


## NAN prints as an em dash rather than "nan" or a misleading 0.00.
func _num(v: float, places: int) -> String:
	if is_nan(v):
		return "—"
	return String.num(v, places)


func _mmss(seconds: float) -> String:
	var s := int(maxf(0.0, seconds))
	return "%d:%02d" % [s / 60, s % 60]

## Draw real granulaat off the line and put it on the bench. The verdict exists
## immediately but is not revealed until the bench delay elapses — that is the
## point of the exercise, so nothing here shows a result.
func _on_submit_sample() -> void:
	var lf : Node = _find_lineflow()
	var lab : Object = _find_lab(lf)
	if lab == null:
		_foot.text = "Geen lab actief op deze lijn — training staat uit."
		_foot.add_theme_color_override("font_color", C_WARN)
		return
	var batch : Object = lf.call("take_product_sample", QaLab.SAMPLE_KG)
	if batch == null:
		_foot.text = "Nog geen granulaat gestort — de lijn heeft niets geproduceerd."
		_foot.add_theme_color_override("font_color", C_WARN)
		return
	var sid : int = lab.submit_sample(batch, _build_source(lf))
	if sid < 0:
		_foot.text = "Monster te klein om te analyseren."
		_foot.add_theme_color_override("font_color", C_WARN)
		return
	_foot.add_theme_color_override("font_color", C_DIM)
	_refresh()


## Melt telemetry, which is NOT on MaterialBatch. Anything unavailable must be
## NAN and never 0.0: LineFlow only writes nd["mfi_value"] inside `if ex != null`
## (LineFlow.gd:2360 guarding :2372), so an extruder node with no ExtruderScrew
## would otherwise report a plausible 0.00 forever and grade as a stalled line.
func _build_source(lf: Node) -> Dictionary:
	var nd : Dictionary = _first_extruder_node(lf)
	var has_ex : bool = not nd.is_empty() and nd.get("ex") != null
	return {
		"source_key": String(nd.get("key", "")),
		"source_id": String(nd.get("id", "")),
		"mfi": float(nd.get("mfi_value", 0.0)) if has_ex else NAN,
		"melt_temp_c": float(nd.get("melt_temp", 0.0)) if has_ex else NAN,
		"die_bar": float(nd.get("die_pressure", 0.0)) if has_ex else NAN,
		"thru_kg_s": float(nd.get("thru", 0.0)) if not nd.is_empty() else NAN,
		"operator": "",
	}

## Three-step resolve. The old name search was the LAST resort, not the first:
## HmiOverlay.gd:319-329 records that find_child("LineFlow") measurably missed a
## live LineFlow. Every other function here takes `lf` as a parameter, so this
## one function re-points the whole terminal.
func _find_lineflow() -> Node:
	var world : Node = get_tree().current_scene
	if world != null and "line_flow" in world:
		var lf : Node = world.get("line_flow")
		if lf != null:
			return lf
	var grouped : Node = get_tree().get_first_node_in_group("line_flow")
	if grouped != null:
		return grouped
	if world == null:
		return null
	return world.find_child("LineFlow", true, false)


## The shared lab for this line, or null when the line is not in training mode.
func _find_lab(lf: Node) -> Object:
	if lf == null or not lf.has_method("qa_lab"):
		return null
	return lf.call("qa_lab")

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

## The first node carrying LineFlow's ExtruderScrew, the same pick as
## LineFlow._first_extruder_node() for the SCADA panel. It used to match
## `id.begins_with("extruder_")`, which returned the extruder_silo on lines 1,
## 3A and 3B: the silo comes first in _nodes, so every row here showed the
## silo (measured 2026-09-24, probe_screw_die_pressure).
func _first_extruder_node(lf: Node) -> Dictionary:
	if lf == null or not "_nodes" in lf:
		return {}
	for nd in lf.get("_nodes"):
		if nd is Dictionary and nd.get("ex") != null:
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
