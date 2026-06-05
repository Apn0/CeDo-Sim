extends CanvasLayer
## #3 — the shift-leader's computer screen: the day's BALE SCAN LOG. Opened by
## walking up to the office desk (ShiftLeaderDesk) and pressing E. It's a pure
## read-out of ScanLog — which is fed ONLY by real barcode scans — refreshed live
## as new bales are scanned.

var _built : bool = false
var _grid  : GridContainer
var _foot  : Label
var _bus   : Node = null   # EventBus — handed in by the desk (see setup)
var _slog  : Node = null   # ScanLog  — handed in by the desk

const COLS := ["TIJD", "BATCH", "BAAL", "KG", "LIJN", "OPERATOR"]
const C_PANEL := Color(0.09, 0.11, 0.13, 1.0)
const C_HEAD  := Color(0.32, 0.78, 0.52, 1.0)
const C_TEXT  := Color(0.86, 0.92, 0.88, 1.0)
const C_DIM   := Color(0.60, 0.66, 0.62, 1.0)

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

## The desk (which IS inside the active scene) resolves the autoloads and hands
## them in here. This CanvasLayer lives under the SceneTree root — outside the
## active scene — where absolute get_node("/root/X") lookups are rejected, so it
## must NOT resolve them itself.
func setup(bus: Node, slog: Node) -> void:
	_bus = bus
	_slog = slog
	if _bus and _bus.has_signal("scanlog_changed") and not _bus.scanlog_changed.is_connected(_refresh):
		_bus.scanlog_changed.connect(_refresh)
	if visible:
		_refresh()

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
	panel.custom_minimum_size = Vector2(720, 540)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_PANEL
	psb.set_corner_radius_all(8)
	psb.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "SHIFT-LEADER  ·  BALEN-SCANLOG"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_TEXT)
	vb.add_child(title)

	var head := GridContainer.new()
	head.columns = COLS.size()
	head.add_theme_constant_override("h_separation", 22)
	vb.add_child(head)
	for c in COLS:
		var h := Label.new()
		h.text = c
		h.add_theme_font_size_override("font_size", 14)
		h.add_theme_color_override("font_color", C_HEAD)
		head.add_child(h)

	vb.add_child(HSeparator.new())

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(684, 410)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_grid = GridContainer.new()
	_grid.columns = COLS.size()
	_grid.add_theme_constant_override("h_separation", 22)
	_grid.add_theme_constant_override("v_separation", 5)
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_grid)

	_foot = Label.new()
	_foot.add_theme_font_size_override("font_size", 13)
	_foot.add_theme_color_override("font_color", C_DIM)
	vb.add_child(_foot)

	var closeb := Button.new()
	closeb.text = "SLUITEN  (Esc)"
	closeb.pressed.connect(close)
	vb.add_child(closeb)

func _cell(text: String, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 14)
	l.add_theme_color_override("font_color", col)
	return l

func _refresh() -> void:
	if not _built or _grid == null:
		return
	for ch in _grid.get_children():
		_grid.remove_child(ch)   # detach now (queue_free is deferred) so no 1-frame doubling
		ch.queue_free()
	var rows : Array = _slog.entries() if _slog else []
	if rows.is_empty():
		_grid.add_child(_cell("— nog geen balen gescand —", C_DIM))
		for _i in COLS.size() - 1:
			_grid.add_child(_cell("", C_DIM))
	else:
		for e in rows:
			_grid.add_child(_cell(String(e.get("time", "--")), C_TEXT))
			_grid.add_child(_cell(String(e.get("batch", "—")), C_TEXT))
			_grid.add_child(_cell(String(e.get("item", "—")), C_TEXT))
			_grid.add_child(_cell(str(int(e.get("weight_kg", 0))), C_TEXT))
			_grid.add_child(_cell(String(e.get("line", "—")), C_TEXT))
			_grid.add_child(_cell(String(e.get("by", "—")), C_TEXT))
	if _slog:
		_foot.text = "%d scans  ·  %d kg totaal deze dienst   (E of Esc om te sluiten)" % [
			_slog.count(), int(round(_slog.total_kg()))]
	else:
		_foot.text = "ScanLog niet beschikbaar"

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
