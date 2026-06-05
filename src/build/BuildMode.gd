extends Node3D
class_name BuildMode
## In-game, Minecraft-style factory builder. You arrange the real CeDo floor;
## the sim provides the objects + placement mechanics.
##
## States:
##   INACTIVE — normal play.
##   BROWSING — catalog panel open, mouse free. Click an item → PLACING.
##   PLACING  — translucent ghost follows the crosshair; mouse captured.
##              [LMB] place   [R] rotate   [RMB] put item away (→ BROWSING)
##              [X] delete the object under the crosshair   [Tab] open catalog
##
## Toggle the whole mode with [Tab] (build_mode_toggle).
##
## Spawned by MainWorld as a child (needs the world for raycasts and to parent
## placed objects). Placed layout persists to user://factory_layout.json and is
## reloaded on startup, so the factory you build stays built.

enum State { INACTIVE, BROWSING, PLACING, SURFACE }

const LAYOUT_PATH := "user://factory_layout.json"
const LAYOUT_VERSION := 2   # #29 — bump to force a one-time wipe of pre-patch saved builds
const GRID        := 0.5                  # metres — snap step for placement
const ROT_STEP    := PI / 12.0            # 15° rotation increment per [Q]/[E]
const RAY_LEN     := 80.0                  # placement raycast reach (m)
const HEIGHT_STEP := 0.25                  # metres raised/lowered per [R]/[F]

# Surface-tool type ids, parallel to the popup OptionButton order.
const SURF_TYPES  : Array[String] = ["door", "window", "sign", "panel"]

# Injected by MainWorld so placement rays can ignore the player capsule.
var player_body : CharacterBody3D = null
# Injected by MainWorld — carves doorway/window holes in the building shell.
var wall_openings : WallOpenings = null
# Injected by MainWorld — re-links the material line when machines change.
var line_flow : LineFlow = null

var _state        : int    = State.INACTIVE
var _active_id    : String = ""
var _ghost_rot_y  : float  = 0.0
var _ghost_height : float  = 0.0          # how far above the ground hit to place
var _grid_snap    : bool   = true         # [G] toggles free vs grid-snapped placement
var _placed_root : Node3D
var _ghost       : Node3D

# 4-point surface capture
var _surf_points  : Array[Vector3] = []
var _surf_markers : Node3D
var _opening_seq  : int = 0

# UI (built programmatically — no .tscn needed)
var _ui          : CanvasLayer
var _catalog     : PanelContainer
var _status      : Label
var _crosshair   : ColorRect
var _popup       : PanelContainer
var _popup_type  : OptionButton
var _popup_name  : LineEdit

# =============================================================================
func _ready() -> void:
	_placed_root = Node3D.new()
	_placed_root.name = "PlacedObjects"
	add_child(_placed_root)
	_build_ui()
	load_layout()

# =============================================================================
# UI
# =============================================================================
func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 40
	add_child(_ui)

	# Status line, top-centre
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 16)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.offset_top = 14.0
	_status.add_theme_color_override("font_color", Color(0.85, 0.95, 1.0))
	_status.add_theme_color_override("font_outline_color", Color.BLACK)
	_status.add_theme_constant_override("outline_size", 6)
	_status.visible = false
	_ui.add_child(_status)

	# Centre crosshair (only while placing)
	_crosshair = ColorRect.new()
	_crosshair.color = Color(1, 1, 1, 0.85)
	_crosshair.anchor_left = 0.5
	_crosshair.anchor_top = 0.5
	_crosshair.offset_left = -3.0
	_crosshair.offset_top = -3.0
	_crosshair.offset_right = 3.0
	_crosshair.offset_bottom = 3.0
	_crosshair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crosshair.visible = false
	_ui.add_child(_crosshair)

	# Catalog panel, left side
	_catalog = PanelContainer.new()
	_catalog.anchor_left = 0.0
	_catalog.anchor_top = 0.0
	_catalog.anchor_bottom = 1.0
	_catalog.offset_left = 16.0
	_catalog.offset_right = 290.0     # explicit width — avoids zero-width rect
	_catalog.offset_top = 50.0
	_catalog.offset_bottom = -50.0
	_catalog.visible = false
	_ui.add_child(_catalog)

	var scroll := ScrollContainer.new()
	_catalog.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(250, 0)
	vbox.add_theme_constant_override("separation", 4)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "BUILD CATALOG"
	title.add_theme_font_size_override("font_size", 20)
	vbox.add_child(title)

	# Special tool: the 4-point surface / opening placer.
	var surf_btn := Button.new()
	surf_btn.text = "▣  Surface / opening (4-point)"
	surf_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	surf_btn.add_theme_color_override("font_color", Color(1.0, 0.9, 0.5))
	surf_btn.pressed.connect(_start_surface)
	vbox.add_child(surf_btn)

	var surf_help := Label.new()
	surf_help.text = "  door · window · sign · wall panel"
	surf_help.add_theme_font_size_override("font_size", 11)
	surf_help.add_theme_color_override("font_color", Color(0.6, 0.6, 0.66))
	vbox.add_child(surf_help)

	for cat in PlaceableCatalog.categories():
		var header := Label.new()
		header.text = "— %s —" % cat
		header.add_theme_font_size_override("font_size", 13)
		header.add_theme_color_override("font_color", Color(0.65, 0.78, 1.0))
		vbox.add_child(header)
		for it in PlaceableCatalog.items():
			if it["category"] != cat:
				continue
			var btn := Button.new()
			btn.text = String(it["name"])
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.pressed.connect(_select_item.bind(String(it["id"])))
			vbox.add_child(btn)

	_build_popup()

# The "what did you place?" dialog shown after the 4th surface point.
func _build_popup() -> void:
	_popup = PanelContainer.new()
	_popup.anchor_left = 0.5
	_popup.anchor_top = 0.5
	_popup.offset_left = -200.0
	_popup.offset_right = 200.0
	_popup.offset_top = -120.0
	_popup.offset_bottom = 120.0
	_popup.visible = false
	_ui.add_child(_popup)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_popup.add_child(margin)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	margin.add_child(vb)

	var head := Label.new()
	head.text = "What did you place?"
	head.add_theme_font_size_override("font_size", 18)
	vb.add_child(head)

	_popup_type = OptionButton.new()
	_popup_type.add_item("Door  (opens with E, cuts opening)")       # 0
	_popup_type.add_item("Window  (glass, cuts opening)")            # 1
	_popup_type.add_item("Sign / poster  (flat on wall)")           # 2
	_popup_type.add_item("Plain panel / wall  (solid)")             # 3
	vb.add_child(_popup_type)

	var name_lbl := Label.new()
	name_lbl.text = "Name / description:"
	name_lbl.add_theme_font_size_override("font_size", 12)
	vb.add_child(name_lbl)

	_popup_name = LineEdit.new()
	_popup_name.placeholder_text = "e.g. 3×3 roller door"
	vb.add_child(_popup_name)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)
	var create_btn := Button.new()
	create_btn.text = "Create"
	create_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	create_btn.pressed.connect(_confirm_surface)
	row.add_child(create_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cancel_btn.pressed.connect(_cancel_surface)
	row.add_child(cancel_btn)

# =============================================================================
# STATE TRANSITIONS
# =============================================================================
func _on_toggle() -> void:
	# Tab is a clean ON/OFF: from any ACTIVE state it fully exits build mode and
	# hands control back (cursor re-captured, walking restored). To go back to the
	# catalog while placing, use [RMB]/build_cancel (PLACING → BROWSING). This avoids
	# the old two-press trap where Tab left you in BROWSING with the cursor up and
	# movement frozen.
	match _state:
		State.INACTIVE: _enter_browsing()
		_:              _enter_inactive()

func _enter_inactive() -> void:
	_state = State.INACTIVE
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = false
	_status.visible = false
	_crosshair.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _enter_browsing() -> void:
	_state = State.BROWSING
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = true
	_status.visible = true
	_crosshair.visible = true   # aim the crosshair at any placed object to delete it
	_status.text = "BUILD MODE   ·   pick an item from the catalog   ·   aim + [X] delete   ·   [Tab] exit build mode"
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)

func _enter_placing(id: String) -> void:
	_state = State.PLACING
	_active_id = id
	_ghost_height = 0.0
	_catalog.visible = false
	_status.visible = true
	_crosshair.visible = true
	_spawn_ghost(id)
	_update_placing_status()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _update_placing_status() -> void:
	var nm := String(PlaceableCatalog.get_item(_active_id).get("name", _active_id))
	var grid_txt := "ON" if _grid_snap else "OFF (free)"
	_status.text = "Placing: %s   ·   [LMB] place   [Q]/[E] rotate   [R]/[F] height %.2fm   [G] grid: %s   [RMB] away   [X] delete   [Tab] catalog" \
		% [nm, _ghost_height, grid_txt]

func _select_item(id: String) -> void:
	_enter_placing(id)

func _start_surface() -> void:
	_enter_surface()

func _enter_surface() -> void:
	_state = State.SURFACE
	_clear_ghost()
	_clear_surface()
	_popup.visible = false
	_catalog.visible = false
	_status.visible = true
	_crosshair.visible = true
	_status.text = "SURFACE  ·  aim & [LMB] the 4 corners:  ① bottom-left  ② top-left  ③ top-right  ④ bottom-right   ·   [RMB] cancel"
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# =============================================================================
# INPUT  (handled in _input so [Tab] beats UI focus navigation)
# =============================================================================
func _input(event: InputEvent) -> void:
	if event.is_action_pressed("build_mode_toggle"):
		_on_toggle()
		get_viewport().set_input_as_handled()
		return

	if _state == State.SURFACE:
		# While the name popup is open, let clicks reach its buttons.
		if event.is_action_pressed("build_place") and not _popup.visible:
			_add_surface_point()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("build_cancel"):
			_cancel_surface()
			get_viewport().set_input_as_handled()
		return

	# Delete works in BROWSING too (aim the crosshair at any placed object + [X]),
	# so you don't have to pick a dummy item just to remove something.
	if _state == State.BROWSING and event.is_action_pressed("build_delete"):
		_delete_pointed()
		get_viewport().set_input_as_handled()
		return

	if _state != State.PLACING:
		return

	if event.is_action_pressed("build_place"):
		_place_current()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_cancel"):
		_enter_browsing()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate_cw"):
		_ghost_rot_y = wrapf(_ghost_rot_y + ROT_STEP, 0.0, TAU)
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_rotate_ccw"):
		_ghost_rot_y = wrapf(_ghost_rot_y - ROT_STEP, 0.0, TAU)
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_raise"):
		_ghost_height += HEIGHT_STEP
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_lower"):
		_ghost_height = maxf(0.0, _ghost_height - HEIGHT_STEP)
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_grid_toggle"):
		_grid_snap = not _grid_snap
		_update_placing_status()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("build_delete"):
		_delete_pointed()
		get_viewport().set_input_as_handled()

# =============================================================================
# GHOST + PLACEMENT
# =============================================================================
func _process(_delta: float) -> void:
	if _state != State.PLACING or _ghost == null:
		return
	var hit := _raycast()
	if hit.is_empty():
		_ghost.visible = false
		return
	_ghost.visible = true
	var p: Vector3 = hit["position"]
	if _grid_snap:
		p.x = roundf(p.x / GRID) * GRID
		p.z = roundf(p.z / GRID) * GRID
	p.y += _ghost_height
	_ghost.global_position = p
	_ghost.rotation.y = _ghost_rot_y

func _spawn_ghost(id: String) -> void:
	_clear_ghost()
	_ghost = PlaceableCatalog.build_node(id, true)
	if _ghost:
		add_child(_ghost)

func _clear_ghost() -> void:
	if _ghost and is_instance_valid(_ghost):
		_ghost.queue_free()
	_ghost = null

func _place_current() -> void:
	if _ghost == null or not _ghost.visible:
		return
	var node := PlaceableCatalog.build_node(_active_id, false)
	if node == null:
		return
	_placed_root.add_child(node)
	node.global_position = _ghost.global_position
	node.rotation.y = _ghost_rot_y
	_finalize_placed(node, _active_id, _ghost_height)
	_finalize_bale(node)
	_save_layout()
	if line_flow:
		line_flow.rebuild()

## Stamps a placed bale with a unique code + prints its label (origin + barcode).
func _finalize_bale(node: Node3D, saved_code: String = "") -> void:
	if not node.has_meta("material_origin"):
		return
	var id := String(node.get_meta("material_origin"))
	var code := saved_code
	if code.is_empty():
		var nm := String(BaleDefs.get_origin(id).get("name", "BALE"))
		code = "%s-%05d" % [nm.substr(0, 3).to_upper(), randi() % 100000]
	node.set_meta("bale_code", code)
	PlaceableCatalog.add_bale_label(node, id, code)

## Records the build height and, if the object is raised off the floor, adds a
## metal support frame from its base down to the ground.
func _finalize_placed(node: Node3D, id: String, height: float) -> void:
	node.set_meta("height_offset", height)
	if height <= 0.001:
		return
	var item := PlaceableCatalog.get_item(id)
	var footprint: Vector3 = item.get("size", Vector3(1.0, 1.0, 1.0))
	var frame := PlaceableCatalog.build_support_frame(footprint, height)
	if frame:
		node.add_child(frame)   # child → rotates, persists and deletes with the object

func _delete_pointed() -> void:
	var hit := _raycast()
	if hit.is_empty():
		return
	var collider = hit.get("collider")
	if collider == null:
		return
	# Walk up to the nearest ancestor flagged "placed_object" — REGARDLESS of which
	# root it hangs under. The old code required a DIRECT child of _placed_root, so
	# anything loaded from disk on reopen, nested (support frames/labels), or spawned
	# by the world (the Line 3C machines) could never be deleted. Matching the group
	# directly fixes "can't delete anything placed after closing/reopening".
	var target: Node = collider
	while target != null and not target.is_in_group("placed_object"):
		target = target.get_parent()
	if target == null:
		return
	# If it owns a carved opening, restore that part of the wall first.
	if target.has_meta("opening_id") and wall_openings:
		wall_openings.remove_opening(String(target.get_meta("opening_id")))
	# Drop from the flow group now so the rebuild below doesn't re-include it
	# (queue_free only frees at end of frame).
	target.remove_from_group("placed_object")
	var par := target.get_parent()
	if par != null:
		par.remove_child(target)
	target.queue_free()
	_save_layout()
	if line_flow:
		line_flow.rebuild()

# Camera-forward ray against the world (floor / building / placed objects),
# excluding the player capsule and the (collision-less) ghost.
func _raycast() -> Dictionary:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return {}
	var from := cam.global_position
	var to := from + (-cam.global_transform.basis.z) * RAY_LEN
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collide_with_areas = false
	if player_body:
		q.exclude = [player_body.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

# =============================================================================
# 4-POINT SURFACE TOOL
# =============================================================================
func _add_surface_point() -> void:
	var hit := _raycast()
	if hit.is_empty():
		return
	var pos: Vector3 = hit["position"]
	_surf_points.append(pos)
	_update_surface_markers()
	var n := _surf_points.size()
	if n >= 4:
		_show_surface_popup()
	else:
		var nexts := ["② top-left", "③ top-right", "④ bottom-right"]
		_status.text = "SURFACE  ·  point %d/4 set  ·  next: %s   ·   [RMB] cancel" % [n, nexts[n - 1]]

func _update_surface_markers() -> void:
	if _surf_markers == null or not is_instance_valid(_surf_markers):
		_surf_markers = Node3D.new()
		_surf_markers.name = "SurfaceMarkers"
		add_child(_surf_markers)
	for c in _surf_markers.get_children():
		c.queue_free()
	for i in _surf_points.size():
		var m := MeshInstance3D.new()
		var sph := SphereMesh.new()
		sph.radius = 0.08
		sph.height = 0.16
		m.mesh = sph
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.85, 0.2)
		m.material_override = mat
		_surf_markers.add_child(m)
		m.global_position = _surf_points[i]

func _clear_surface() -> void:
	if _surf_markers and is_instance_valid(_surf_markers):
		_surf_markers.queue_free()
	_surf_markers = null
	_surf_points.clear()

func _show_surface_popup() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	_popup_name.text = ""
	_popup_type.selected = 0
	_popup.visible = true
	_status.text = "SURFACE  ·  choose what it is, name it, press Create"

func _confirm_surface() -> void:
	if _surf_points.size() < 4:
		_cancel_surface()
		return
	var type_idx := _popup_type.selected
	var type_str := SURF_TYPES[clampi(type_idx, 0, SURF_TYPES.size() - 1)]
	var label := _popup_name.text.strip_edges()
	var pts := _surf_points.duplicate()
	_popup.visible = false
	_make_surface(pts, type_str, label)
	_save_layout()
	_enter_browsing()

func _cancel_surface() -> void:
	_popup.visible = false
	_enter_browsing()

## Builds a surface object from 4 world-space corner points, positions it flush
## with the clicked plane, and (for doors/windows) carves a matching opening.
func _make_surface(points: Array, type_str: String, label: String) -> Node3D:
	if points.size() < 4:
		return null
	var geo := _surface_geometry(points)
	var center: Vector3 = geo["center"]
	var surf_basis: Basis = geo["basis"]
	var width: float    = geo["width"]
	var height: float   = geo["height"]
	var x_axis: Vector3 = geo["x_axis"]
	var z_axis: Vector3 = geo["z_axis"]

	var node: Node3D = null
	var cuts := false
	match type_str:
		"door":
			node = PlaceableCatalog.build_door(width, height, 0.12, label)
			cuts = true
		"window":
			node = PlaceableCatalog.build_panel(width, height, 0.08, Color(0.62, 0.76, 0.86, 0.35), label, true, true)
			cuts = true
		"sign":
			node = PlaceableCatalog.build_panel(width, height, 0.03, Color(0.92, 0.92, 0.90), label, false, false)
		_:
			node = PlaceableCatalog.build_panel(width, height, 0.10, Color(0.70, 0.70, 0.72), label, false, true)
	if node == null:
		return null

	_placed_root.add_child(node)
	var place_center := center
	if type_str == "sign":
		place_center = center + z_axis * 0.03   # sit proud of the wall
	node.global_transform = Transform3D(surf_basis, place_center)

	var pdata: Array = []
	for p in points:
		pdata.append([(p as Vector3).x, (p as Vector3).y, (p as Vector3).z])
	node.set_meta("surface_data", {"type": type_str, "label": label, "p": pdata})

	if cuts and wall_openings:
		_opening_seq += 1
		var oid := "op_%d" % _opening_seq
		var rot_y := atan2(x_axis.z, x_axis.x)
		wall_openings.add_opening(oid, center, Vector3(width + 0.15, height + 0.15, 2.0), rot_y)
		node.set_meta("opening_id", oid)
	return node

func _surface_geometry(points: Array) -> Dictionary:
	var p0: Vector3 = points[0]
	var p1: Vector3 = points[1]
	var p2: Vector3 = points[2]
	var p3: Vector3 = points[3]
	var center := (p0 + p1 + p2 + p3) / 4.0
	var right_edge := p3 - p0          # bottom-left → bottom-right
	var up_edge := p1 - p0             # bottom-left → top-left
	var width := maxf(right_edge.length(), 0.1)
	var height := maxf(up_edge.length(), 0.1)
	var x_axis := right_edge.normalized()
	var y_axis := up_edge.normalized()
	var z_axis := x_axis.cross(y_axis)
	if z_axis.length() < 0.001:
		z_axis = Vector3.FORWARD
	z_axis = z_axis.normalized()
	y_axis = z_axis.cross(x_axis).normalized()
	# Set columns explicitly (Basis.x/.y/.z ARE the columns) to avoid the
	# constructor's column-vs-row ambiguity. local +X→x_axis, +Y→up, +Z→normal.
	var surf_basis := Basis()
	surf_basis.x = x_axis
	surf_basis.y = y_axis
	surf_basis.z = z_axis
	surf_basis = surf_basis.orthonormalized()
	return {
		"center": center, "basis": surf_basis, "width": width, "height": height,
		"x_axis": x_axis, "z_axis": z_axis,
	}

# =============================================================================
# PERSISTENCE
# =============================================================================
func _save_layout() -> void:
	var arr: Array = [{"layout_version": LAYOUT_VERSION}]   # #29 marker — see load_layout
	for child in _placed_root.get_children():
		if child.has_meta("surface_data"):
			# 4-point surfaces persist as their corner points + type + label.
			var sd: Dictionary = child.get_meta("surface_data")
			arr.append({
				"kind":  "surface",
				"type":  sd.get("type", "door"),
				"label": sd.get("label", ""),
				"p":     sd.get("p", []),
			})
		elif child.has_meta("placeable_id"):
			var h := 0.0
			if child.has_meta("height_offset"):
				h = float(child.get_meta("height_offset"))
			var entry := {
				"id":    child.get_meta("placeable_id"),
				"x":     child.global_position.x,
				"y":     child.global_position.y,
				"z":     child.global_position.z,
				"rot_y": child.rotation.y,
				"h":     h,
			}
			if child.has_meta("bale_code"):
				entry["code"] = String(child.get_meta("bale_code"))
			arr.append(entry)
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(arr, "\t"))
		f.close()

func load_layout() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_ARRAY:
		return
	# #29 — one-time wipe: a saved layout without the current version marker is from
	# before this patch, so ignore it and start clean. The next _save_layout writes the
	# marker, so anything the player builds from here on persists normally.
	var versioned := false
	for entry in data:
		if typeof(entry) == TYPE_DICTIONARY and int((entry as Dictionary).get("layout_version", 0)) == LAYOUT_VERSION:
			versioned = true
			break
	if not versioned:
		print("[BuildMode] Ignoring obsolete saved layout (pre-v%d) — clean start (#29)." % LAYOUT_VERSION)
		return
	var count := 0
	for entry in data:
		if typeof(entry) != TYPE_DICTIONARY:
			continue
		var dict: Dictionary = entry

		# New 4-point surfaces (door / window / sign / panel).
		if String(dict.get("kind", "")) == "surface":
			var pts: Array = []
			for pp in dict.get("p", []):
				if typeof(pp) == TYPE_ARRAY and (pp as Array).size() >= 3:
					pts.append(Vector3(float(pp[0]), float(pp[1]), float(pp[2])))
			if pts.size() == 4:
				_make_surface(pts, String(dict.get("type", "door")), String(dict.get("label", "")))
				count += 1
			continue

		# Legacy plain box "door" → upgrade to an interactive roller door + hole.
		if String(dict.get("id", "")) == "door":
			_load_legacy_door(dict)
			count += 1
			continue

		var node := PlaceableCatalog.build_node(String(dict.get("id", "")), false)
		if node == null:
			continue
		_placed_root.add_child(node)
		node.global_position = Vector3(
			float(dict.get("x", 0.0)),
			float(dict.get("y", 0.0)),
			float(dict.get("z", 0.0)))
		node.rotation.y = float(dict.get("rot_y", 0.0))
		_finalize_placed(node, String(dict.get("id", "")), float(dict.get("h", 0.0)))
		_finalize_bale(node, String(dict.get("code", "")))
		count += 1
	print("[BuildMode] Loaded %d placed objects" % count)

## Converts a legacy box-door entry {id:"door", x,y,z,rot_y} into the new
## interactive roller door with a carved opening, by reconstructing its 4
## corner points from the catalogue door footprint.
func _load_legacy_door(dict: Dictionary) -> void:
	var item := PlaceableCatalog.get_item("door")
	var size: Vector3 = item.get("size", Vector3(1.2, 2.4, 0.18))
	var w := size.x
	var h := size.y
	var rot_y := float(dict.get("rot_y", 0.0))
	# Base position (origin at floor) → centre of the leaf.
	var base := Vector3(float(dict.get("x", 0.0)), float(dict.get("y", 0.0)), float(dict.get("z", 0.0)))
	var center := base + Vector3(0.0, h * 0.5, 0.0)
	var x_axis := Vector3(cos(rot_y), 0.0, sin(rot_y))
	var up := Vector3.UP
	var hx := x_axis * (w * 0.5)
	var hy := up * (h * 0.5)
	var pts := [
		center - hx - hy,   # bottom-left
		center - hx + hy,   # top-left
		center + hx + hy,   # top-right
		center + hx - hy,   # bottom-right
	]
	_make_surface(pts, "door", "Door")
