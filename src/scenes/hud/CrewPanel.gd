extends CanvasLayer

## Crew assignment panel — open with the crew hotkey (Numpad ".") or from the HUD.
## Lists every worker (name · role · live task) and lets the operator hand-assign
## each one to a post: a specific station, "Auto" (role-based), or "Off duty".
## Drives CrewManager.manual_assign(). One shared instance reused each open.

var _cm : Node = null            # CrewManager
var _built : bool = false
var _rows : Array = []           # [{worker, task_lbl, opt}]
var _post_ids : Array = []       # post ids, index-aligned to OptionButton items 2..n
var _post_labels : Array = []    # human labels paired with _post_ids

const C_PANEL := Color(0.11, 0.13, 0.16, 1.0)
const C_TEXT  := Color(0.88, 0.92, 0.92, 1.0)
const C_SUB   := Color(0.62, 0.68, 0.70, 1.0)
const C_BTN   := Color(0.20, 0.32, 0.40, 1.0)

func _ready() -> void:
	layer = 60
	visible = false
	set_process(true)

func toggle_for(cm: Node) -> void:
	if visible:
		close_panel()
	else:
		open_for(cm)

func open_for(cm: Node) -> void:
	_cm = cm
	if not _built:
		_build()
		_built = true
	_populate()
	visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func close_panel() -> void:
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# ── UI scaffold (built once) ──────────────────────────────────────────────────
var _list_vb : VBoxContainer

func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 520)
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_PANEL
	psb.set_corner_radius_all(8)
	psb.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", psb)
	center.add_child(panel)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	panel.add_child(vb)

	var title := Label.new()
	title.text = "PLOEG — CREW ASSIGNMENT"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", C_TEXT)
	vb.add_child(title)

	var hint := Label.new()
	hint.text = "Assign each worker to a post. 'Auto' = role-based; 'Off duty' = stand down."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", C_SUB)
	vb.add_child(hint)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 410)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(scroll)
	_list_vb = VBoxContainer.new()
	_list_vb.add_theme_constant_override("separation", 4)
	_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list_vb)

	var closeb := _flat_button("SLUITEN  (Esc)", Color(0.40, 0.22, 0.20, 1.0))
	closeb.pressed.connect(close_panel)
	vb.add_child(closeb)

## Rebuild the worker rows + post dropdowns from the current crew + stations.
func _populate() -> void:
	for c in _list_vb.get_children():
		c.queue_free()
	_rows.clear()
	_post_ids.clear()
	_post_labels.clear()
	if _cm == null:
		return
	# Role-based posts FIRST (the proper plant rota slots: shiftleader, extruder op,
	# feeder, …) — assigning these switches the worker's npc_role and posts them by
	# zone. #36 — this is what the operator actually thinks in.
	var roles : Array = _cm.role_posts() if _cm.has_method("role_posts") else []
	for rp in roles:
		_post_ids.append(String(rp.get("id", "")))
		_post_labels.append(String(rp.get("label", "")))
	# Then specific machine stations (the deduped legacy list) for fine-grained pinning.
	var seen := {}
	for s in _cm.station_list():
		var sid := String(s.get("id", ""))
		if sid == "" or seen.has(sid):
			continue
		seen[sid] = true
		_post_ids.append(sid)
		_post_labels.append(sid.replace("_", " "))
	for w in _cm.workers:
		_add_worker_row(w)

func _add_worker_row(worker) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_list_vb.add_child(row)

	var name_lbl := _cell(String(worker.npc_name), 150, C_TEXT, 16)
	row.add_child(name_lbl)
	var role_lbl := _cell(String(worker.npc_role).replace("_", " "), 130, C_SUB, 13)
	row.add_child(role_lbl)
	var task_lbl := _cell(worker.current_task(), 150, C_SUB, 13)
	row.add_child(task_lbl)

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(190, 0)
	opt.add_item("— Auto (rol) —")        # index 0 → "__auto__"
	opt.add_item("Van dienst af (off)")    # index 1 → "__off__"
	for i in _post_ids.size():
		opt.add_item(String(_post_labels[i]))
	# Reflect the current pin in the dropdown selection.
	var pinned := String(_cm.pinned_station(worker)) if _cm.has_method("pinned_station") else ""
	if pinned != "" and _post_ids.has(pinned):
		opt.select(2 + _post_ids.find(pinned))
	else:
		opt.select(0)
	opt.item_selected.connect(_on_post_selected.bind(worker))
	row.add_child(opt)

	_rows.append({"worker": worker, "task_lbl": task_lbl})

func _on_post_selected(idx: int, worker) -> void:
	if _cm == null:
		return
	var sid := "__auto__"
	if idx == 1:
		sid = "__off__"
	elif idx >= 2 and (idx - 2) < _post_ids.size():
		sid = String(_post_ids[idx - 2])
	_cm.manual_assign(worker, sid)

func _process(_dt: float) -> void:
	if not visible:
		return
	for r in _rows:
		var w = r["worker"]
		if is_instance_valid(w):
			(r["task_lbl"] as Label).text = w.current_task()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close_panel()
		get_viewport().set_input_as_handled()

# ── small UI helpers ──────────────────────────────────────────────────────────
func _cell(text: String, w: float, col: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = text
	l.custom_minimum_size = Vector2(w, 0)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.clip_text = true
	return l

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
