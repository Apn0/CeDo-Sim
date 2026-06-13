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
	hint.text = "Assign each worker to a post. 'Auto' = role-based; 'Off duty' = stand down.\n'HIER' = post the worker at YOUR current position (#124)."
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
	# #173 — Section posts AFTER roles: "Line 3A · Feed area", etc. The operator
	# wanted to assign by a meaningful chunk of the plant rather than by raw
	# coords or by one specific machine id — pinning to a section auto-posts to
	# the nearest matching machine and covers any incident inside the section.
	var sections : Array = _cm.section_posts() if _cm.has_method("section_posts") else []
	for sp in sections:
		_post_ids.append(String(sp.get("id", "")))
		_post_labels.append(String(sp.get("label", "")))
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

	# Pull pin state once: a `pos:` pin is shown as a synthetic "📍 PIN" option
	# at the TOP of the dropdown so the UI tells the truth about it (#124).
	var pinned := String(_cm.pinned_station(worker)) if _cm.has_method("pinned_station") else ""
	var has_pos_pin : bool = pinned.begins_with("pos:")

	var opt := OptionButton.new()
	opt.custom_minimum_size = Vector2(220, 0)
	var pin_label := ""
	if has_pos_pin and _cm.has_method("position_pin_for"):
		var meta : Dictionary = _cm.position_pin_for(worker)
		var p : Vector3 = meta.get("pos", Vector3.ZERO)
		pin_label = "📍 HIER (%.1f, %.1f, %.1f)" % [p.x, p.y, p.z]
		opt.add_item(pin_label)               # index 0 → keep this synthetic option
	opt.add_item("— Auto (rol) —")            # index ? → "__auto__"
	opt.add_item("Van dienst af (off)")       # index ? → "__off__"
	for i in _post_ids.size():
		opt.add_item(String(_post_labels[i]))
	# Dropdown selection: pos-pin → synthetic entry at 0; station/role pin → its
	# offset (post indices live after Auto + Off); nothing → Auto. With a pos
	# pin shown, Auto is now at index 1 (not 0) — but that case is already
	# handled because has_pos_pin selects the pin row directly.
	if has_pos_pin:
		opt.select(0)
	elif pinned != "" and _post_ids.has(pinned):
		opt.select(2 + _post_ids.find(pinned))
	else:
		opt.select(0)
	# Bind row data so the handler knows whether the dropdown carries a pos-pin
	# entry at index 0 (offsets every subsequent index by +1).
	opt.item_selected.connect(_on_post_selected.bind(worker, has_pos_pin))
	row.add_child(opt)

	# #124 — "HIER": pin to operator's current world position + facing.
	var here_btn := _flat_button("HIER", Color(0.18, 0.36, 0.24, 1.0))
	here_btn.add_theme_font_size_override("font_size", 13)
	here_btn.pressed.connect(_on_post_here.bind(worker))
	row.add_child(here_btn)

	# #124 — "LOS" (release / unpin): explicit clear of any pin (station, role,
	# or pos). Reverts the worker to auto-posting. Only enabled when pinned.
	var unpin_btn := _flat_button("LOS", Color(0.40, 0.32, 0.20, 1.0))
	unpin_btn.add_theme_font_size_override("font_size", 13)
	unpin_btn.disabled = (pinned == "")
	unpin_btn.pressed.connect(_on_unpin.bind(worker))
	row.add_child(unpin_btn)

	_rows.append({"worker": worker, "task_lbl": task_lbl})

## #124 — Resolve a sane world spot for the operator and pin the worker there.
## Falls back through three sources in order:
##   1. If the player is in a vehicle, use the vehicle's ground footprint so
##      pressing HIER from the cab doesn't pin the worker mid-air at seat level.
##   2. Else the player's own global_position + yaw.
##   3. If a downward raycast finds no floor, refuse and warn instead of
##      silently pinning the worker into a wall or void.
func _on_post_here(worker) -> void:
	if _cm == null or not _cm.has_method("assign_to_position"):
		return
	var src := _pin_source()
	if src.is_empty():
		push_warning("[CrewPanel] no player/vehicle found — cannot HIER")
		return
	var anchor : Vector3 = src["pos"]
	var facing : float = float(src["yaw"])
	# Floor validation: cast straight down 30 m and snap the pin Y to the hit.
	# No hit → refuse (no walkable surface beneath the operator).
	var ground = _drop_to_floor(anchor + Vector3(0.0, 1.5, 0.0))
	if ground == null:
		push_warning("[CrewPanel] no floor beneath operator — cannot HIER here")
		return
	_cm.assign_to_position(worker, ground, facing)
	_refresh_row(worker)

## #124 — explicit unpin button (LOS). Clears whatever pin the worker has.
func _on_unpin(worker) -> void:
	if _cm == null or not _cm.has_method("unpin"):
		return
	_cm.unpin(worker)
	_refresh_row(worker)

## Rebuild the whole panel after a pin change so the dropdown + LOS button
## state actually reflect the new reality. Cheap — ~10 rows.
func _refresh_row(_worker) -> void:
	_populate()

## Where the operator IS in the world, and which way they're facing. Returns
## `{pos: Vector3, yaw: float}` or {} on failure.
func _pin_source() -> Dictionary:
	# Vehicle takes priority — operator sitting in the forklift cab presses HIER:
	# pin to where the vehicle is, not where the camera is.
	var op := _operator_context()
	if op != null:
		var vehicle = op.get("current_vehicle")
		if vehicle is Node3D and is_instance_valid(vehicle):
			return {"pos": (vehicle as Node3D).global_position,
					"yaw": (vehicle as Node3D).rotation.y}
	# Else use the player.
	var pl := _player_node()
	if pl is Node3D:
		return {"pos": (pl as Node3D).global_position,
				"yaw": (pl as Node3D).rotation.y}
	return {}

func _operator_context() -> Node:
	var found := get_tree().get_first_node_in_group("operator_context")
	return found if found is Node else null

func _player_node() -> Node:
	if _cm != null:
		var mw := _cm.get_parent()
		if mw != null:
			var pl = mw.get("player")
			if pl is Node3D and is_instance_valid(pl):
				return pl
	return get_tree().current_scene.find_child("Player", true, false)

## Cast a 30 m ray straight down through the physics world from `from` and
## return the hit position, or null if nothing's there. Used to snap the HIER
## pin to actual ground so mezzanine pins land on the deck, not the floor below.
func _drop_to_floor(from: Vector3):
	var world := get_tree().current_scene
	if world == null:
		return null
	var space := (world as Node3D).get_world_3d().direct_space_state \
		if world is Node3D else null
	if space == null:
		return null
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -30.0, 0.0))
	q.collide_with_areas = false
	q.collide_with_bodies = true
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return null
	return hit.get("position", null)

func _on_post_selected(idx: int, worker, has_pos_pin: bool) -> void:
	if _cm == null:
		return
	# When a pos-pin is showing, the synthetic "📍 HIER" entry is index 0 — every
	# other index shifts +1. The pos entry is read-only (re-selecting it is a
	# no-op; the operator must press LOS or pick a different post to leave it).
	var sid := "__auto__"
	if has_pos_pin:
		if idx == 0:
			return                                  # re-select pin: no-op
		idx -= 1                                    # drop the pos entry offset
	if idx == 1:
		sid = "__off__"
	elif idx >= 2 and (idx - 2) < _post_ids.size():
		sid = String(_post_ids[idx - 2])
	_cm.manual_assign(worker, sid)
	_refresh_row(worker)

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
