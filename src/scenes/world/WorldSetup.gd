extends Node3D
##
## Top-down RTS marker-placement scene. Loads the empty building shell, paints a
## satellite-image floor (via PDOK Luchtfoto WMS), and lets the user click to drop
## markers for: player spawn, vehicle spawns (per type), line starts (per line),
## and bale-yard rectangles. Saves to WorldLayout (user://world_layout.json).
##
## v1 scope: this scene does NOT run gameplay — it's purely a layout authoring
## tool. After Save the user returns to the main menu.
##

const BUILDING_OBJ        := "res://assets/models/CeDo_building.obj"
const SATELLITE_CACHE     := "user://satellite.png"
# PDOK Luchtfoto WMS — open Dutch aerial. EPSG:4326 keeps the bbox input simple
# (paste lat/lon corners straight from Google Maps).
const PDOK_WMS            := "https://service.pdok.nl/hwh/luchtfotorgb/wms/v1_0"
const PDOK_LAYER          := "Actueel_orthoHR"
const WMS_IMG_SIZE        := 1024

# Default lat/lon center of the CeDo plant in Sittard-Geleen (Krijtstraat area).
# User can change this in-scene; the field is just a starting hint.
const DEFAULT_LAT         := 50.9695
const DEFAULT_LON         := 5.8194
const DEFAULT_EXTENT_M    := 400.0

# Camera defaults
const CAM_HEIGHT_DEFAULT  := 120.0
const CAM_HEIGHT_MIN      := 25.0
const CAM_HEIGHT_MAX      := 400.0
const CAM_PAN_SPEED       := 1.0   # world m per pixel of mouse drag

# Marker visual sizes
const MARKER_DOT_RADIUS   := 0.6
const MARKER_DOT_HEIGHT   := 1.2
const YARD_PREVIEW_ALPHA  := 0.35

# Tool IDs (drive UI + click handler)
enum Tool {
	NONE,
	PLAYER_SPAWN,
	VEHICLE_FORKLIFT,
	VEHICLE_BALE_CLAMP,
	VEHICLE_MERLO,
	VEHICLE_MERLO_P40,
	VEHICLE_SCISSOR,
	LINE_1, LINE_3A, LINE_3B, LINE_3C, LINE_6,
	BALE_YARD,
}

# Tool metadata
const TOOL_DEFS := {
	Tool.PLAYER_SPAWN:      {"label": "Player spawn",   "color": Color.WHITE,         "kind": "point"},
	Tool.VEHICLE_FORKLIFT:  {"label": "Forklift",       "color": Color.ORANGE,        "kind": "point"},
	Tool.VEHICLE_BALE_CLAMP:{"label": "Bale clamp",     "color": Color.GOLD,          "kind": "point"},
	Tool.VEHICLE_MERLO:     {"label": "Merlo",          "color": Color.CRIMSON,       "kind": "point"},
	Tool.VEHICLE_MERLO_P40: {"label": "Merlo P40",      "color": Color.ORANGE_RED,    "kind": "point"},
	Tool.VEHICLE_SCISSOR:   {"label": "Scissor lift",   "color": Color.LIGHT_BLUE,    "kind": "point"},
	Tool.LINE_1:            {"label": "Line 1 start",   "color": Color.LIME_GREEN,    "kind": "point"},
	Tool.LINE_3A:           {"label": "Line 3A start",  "color": Color.SPRING_GREEN,  "kind": "point"},
	Tool.LINE_3B:           {"label": "Line 3B start",  "color": Color.TURQUOISE,     "kind": "point"},
	Tool.LINE_3C:           {"label": "Line 3C start",  "color": Color.AQUAMARINE,    "kind": "point"},
	Tool.LINE_6:            {"label": "Line 6 start",   "color": Color.SEA_GREEN,     "kind": "point"},
	Tool.BALE_YARD:         {"label": "Bale yard (drag)", "color": Color.YELLOW,      "kind": "rect"},
}

# Tool → WorldLayout key. For points each tool maps to a setter; for the yard
# we accumulate in a list.
const VEHICLE_TOOL_TO_ID := {
	Tool.VEHICLE_FORKLIFT:   "forklift",
	Tool.VEHICLE_BALE_CLAMP: "bale_clamp",
	Tool.VEHICLE_MERLO:      "merlo",
	Tool.VEHICLE_MERLO_P40:  "merlo_p40",
	Tool.VEHICLE_SCISSOR:    "scissor",
}
const LINE_TOOL_TO_ID := {
	Tool.LINE_1:  "1",
	Tool.LINE_3A: "3a",
	Tool.LINE_3B: "3b",
	Tool.LINE_3C: "3c",
	Tool.LINE_6:  "6",
}

# ── Runtime ──────────────────────────────────────────────────────────────────
var camera          : Camera3D
var ground_quad     : MeshInstance3D
var ground_material : StandardMaterial3D
var markers_root    : Node3D
var rect_preview    : MeshInstance3D
var cam_target      : Vector3 = Vector3.ZERO   # camera pans by moving its XZ target
var cam_height      : float   = CAM_HEIGHT_DEFAULT
var current_tool    : int     = Tool.NONE
var yard_drag_start : Vector3 = Vector3.ZERO
var yard_dragging   : bool    = false

# UI refs (built in _build_ui)
var status_label    : Label
var lat_input       : LineEdit
var lon_input       : LineEdit
var extent_input    : LineEdit
var tool_buttons    : Dictionary = {}

# Markers indexed for visual update / clear-on-replace
var point_markers   : Dictionary = {}   # tool_id → MeshInstance3D
var yard_markers    : Array      = []   # MeshInstance3D nodes

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ground()
	_build_building_shell()
	markers_root = Node3D.new()
	markers_root.name = "Markers"
	add_child(markers_root)
	_build_ui()
	_apply_loaded_layout()        # show any existing markers
	_try_load_cached_satellite()

# ── Scene construction ───────────────────────────────────────────────────────
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -35, 0)
	sun.light_energy = 0.8
	add_child(sun)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 50.0
	camera.current = true
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	camera.global_position = Vector3(cam_target.x, cam_height, cam_target.z)
	camera.look_at(cam_target, Vector3.FORWARD)   # look straight down

func _build_ground() -> void:
	ground_quad = MeshInstance3D.new()
	ground_quad.name = "GroundQuad"
	var pm := PlaneMesh.new()
	pm.size = Vector2(DEFAULT_EXTENT_M, DEFAULT_EXTENT_M)
	pm.subdivide_depth = 1
	pm.subdivide_width = 1
	ground_quad.mesh = pm
	ground_material = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.30, 0.32, 0.30)
	ground_material.roughness = 1.0
	ground_quad.material_override = ground_material
	ground_quad.position = Vector3(0, -0.05, 0)   # just below floor
	add_child(ground_quad)

func _build_building_shell() -> void:
	var mesh = ResourceLoader.load(BUILDING_OBJ)
	if mesh == null:
		push_warning("[WorldSetup] %s could not load" % BUILDING_OBJ)
		return
	var mi := MeshInstance3D.new()
	mi.name = "ShellMesh"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	# Center camera over the shell's footprint.
	var aabb := mi.get_aabb()
	cam_target = Vector3(aabb.position.x + aabb.size.x * 0.5, 0, aabb.position.z + aabb.size.z * 0.5)
	cam_height = clampf(maxf(aabb.size.x, aabb.size.z) * 0.9, CAM_HEIGHT_MIN, CAM_HEIGHT_MAX)
	_update_camera()

# ── UI ───────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Top bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 0
	top.offset_left = 0
	top.offset_right = 0
	top.custom_minimum_size.y = 44
	layer.add_child(top)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.text = "World Setup — pick a tool on the left, then click on the floor."
	top.add_child(status_label)

	# Left: marker tools
	var left := PanelContainer.new()
	left.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	left.offset_top = 50
	left.offset_left = 8
	left.offset_bottom = -8
	left.custom_minimum_size.x = 230
	layer.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)

	var hdr := Label.new()
	hdr.text = "Markers"
	hdr.add_theme_font_size_override("font_size", 18)
	lv.add_child(hdr)

	for tool_id in TOOL_DEFS.keys():
		var def : Dictionary = TOOL_DEFS[tool_id]
		var b := Button.new()
		b.text = def["label"]
		var col : Color = def["color"]
		b.add_theme_color_override("font_color", col)
		b.pressed.connect(_on_tool_pressed.bind(tool_id))
		lv.add_child(b)
		tool_buttons[tool_id] = b

	lv.add_child(HSeparator.new())
	var clear_btn := Button.new()
	clear_btn.text = "Clear all markers"
	clear_btn.pressed.connect(_on_clear_pressed)
	lv.add_child(clear_btn)

	# Right: WMS satellite + save
	var right := PanelContainer.new()
	right.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	right.offset_top = 50
	right.offset_right = -8
	right.offset_bottom = -8
	right.custom_minimum_size.x = 260
	layer.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)

	var sat_hdr := Label.new()
	sat_hdr.text = "PDOK Luchtfoto"
	sat_hdr.add_theme_font_size_override("font_size", 18)
	rv.add_child(sat_hdr)

	var lat_box := _field("Lat (center)", str(DEFAULT_LAT))
	lat_input = lat_box.get_child(1) as LineEdit
	rv.add_child(lat_box)
	var lon_box := _field("Lon (center)", str(DEFAULT_LON))
	lon_input = lon_box.get_child(1) as LineEdit
	rv.add_child(lon_box)
	var ext_box := _field("Extent (m)", str(DEFAULT_EXTENT_M))
	extent_input = ext_box.get_child(1) as LineEdit
	rv.add_child(ext_box)

	var fetch_btn := Button.new()
	fetch_btn.text = "Fetch satellite"
	fetch_btn.pressed.connect(_on_fetch_satellite)
	rv.add_child(fetch_btn)
	rv.add_child(HSeparator.new())

	var info := Label.new()
	info.text = "Controls:\nLMB — place (or drag for yard)\nRMB drag — pan camera\nWheel — zoom"
	info.add_theme_font_size_override("font_size", 13)
	rv.add_child(info)

	rv.add_child(HSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "Save & return to menu"
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.pressed.connect(_on_save_pressed)
	rv.add_child(save_btn)

	var back_btn := Button.new()
	back_btn.text = "Cancel (no save)"
	back_btn.pressed.connect(_on_back_pressed)
	rv.add_child(back_btn)

func _field(label_text: String, default_val: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	box.add_child(l)
	var le := LineEdit.new()
	le.text = default_val
	box.add_child(le)
	return box

# ── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_height = clampf(cam_height * 0.9, CAM_HEIGHT_MIN, CAM_HEIGHT_MAX)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_height = clampf(cam_height * 1.1, CAM_HEIGHT_MIN, CAM_HEIGHT_MAX)
			_update_camera()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_click_down(mb.position)
			else:
				_on_left_click_up(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			# Pan: drag scales with camera height so it feels consistent at any zoom.
			var px_to_m := cam_height / 600.0
			cam_target.x -= mm.relative.x * px_to_m
			cam_target.z -= mm.relative.y * px_to_m
			_update_camera()
		elif yard_dragging:
			_update_yard_preview(_screen_to_floor(mm.position))

func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	# Cast a ray from camera through cursor down to the y=0 plane.
	if camera == null: return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_pos)
	var dir    := camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 1e-4: return cam_target
	var t := -origin.y / dir.y
	if t < 0.0: return cam_target
	return origin + dir * t

func _on_left_click_down(screen_pos: Vector2) -> void:
	if current_tool == Tool.NONE: return
	var def : Dictionary = TOOL_DEFS[current_tool]
	if def["kind"] == "rect":
		yard_drag_start = _screen_to_floor(screen_pos)
		yard_dragging = true
		_update_yard_preview(yard_drag_start)

func _on_left_click_up(screen_pos: Vector2) -> void:
	if current_tool == Tool.NONE: return
	var hit := _screen_to_floor(screen_pos)
	var def : Dictionary = TOOL_DEFS[current_tool]
	if def["kind"] == "point":
		_place_point(current_tool, hit)
	elif def["kind"] == "rect":
		if yard_dragging:
			_finalize_yard(yard_drag_start, hit)
			yard_dragging = false
			if rect_preview:
				rect_preview.queue_free()
				rect_preview = null

# ── Tool buttons ─────────────────────────────────────────────────────────────
func _on_tool_pressed(tool_id: int) -> void:
	current_tool = tool_id
	status_label.text = "Tool: %s — click on the floor" % str(TOOL_DEFS[tool_id]["label"])
	for k in tool_buttons:
		var btn : Button = tool_buttons[k]
		btn.flat = (k != tool_id)

func _on_clear_pressed() -> void:
	for m in point_markers.values():
		m.queue_free()
	point_markers.clear()
	for y in yard_markers:
		y.queue_free()
	yard_markers.clear()
	WorldLayout.clear()
	status_label.text = "All markers cleared (not yet saved)."

# ── Marker placement / visuals ───────────────────────────────────────────────
func _place_point(tool_id: int, world_pos: Vector3) -> void:
	# Replace any existing marker for this tool.
	if point_markers.has(tool_id):
		point_markers[tool_id].queue_free()
	var def : Dictionary = TOOL_DEFS[tool_id]
	var node := _make_dot(def["color"])
	node.position = Vector3(world_pos.x, 0.0, world_pos.z)
	markers_root.add_child(node)
	point_markers[tool_id] = node

	# Persist to WorldLayout in-memory (saved on Save & Return).
	var p := Vector3(world_pos.x, 0.0, world_pos.z)
	if tool_id == Tool.PLAYER_SPAWN:
		WorldLayout.player_spawn = p
		WorldLayout.factory_center = p   # keep legacy field aligned
	elif VEHICLE_TOOL_TO_ID.has(tool_id):
		WorldLayout.set_vehicle_spawn(VEHICLE_TOOL_TO_ID[tool_id], p)
	elif LINE_TOOL_TO_ID.has(tool_id):
		WorldLayout.set_line_start(LINE_TOOL_TO_ID[tool_id], p)
	status_label.text = "Placed %s at (%.1f, %.1f)" % [def["label"], p.x, p.z]

func _make_dot(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius    = MARKER_DOT_RADIUS
	cyl.bottom_radius = MARKER_DOT_RADIUS
	cyl.height        = MARKER_DOT_HEIGHT
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	mi.material_override = m
	mi.position.y = MARKER_DOT_HEIGHT * 0.5
	return mi

func _update_yard_preview(world_pos: Vector3) -> void:
	if rect_preview == null:
		rect_preview = MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(1, 1)
		rect_preview.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(Color.YELLOW, YARD_PREVIEW_ALPHA)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rect_preview.material_override = m
		markers_root.add_child(rect_preview)
	var sx := absf(world_pos.x - yard_drag_start.x)
	var sz := absf(world_pos.z - yard_drag_start.z)
	(rect_preview.mesh as PlaneMesh).size = Vector2(maxf(sx, 0.1), maxf(sz, 0.1))
	rect_preview.position = Vector3((world_pos.x + yard_drag_start.x) * 0.5, 0.02, (world_pos.z + yard_drag_start.z) * 0.5)

func _finalize_yard(a: Vector3, b: Vector3) -> void:
	var sx := absf(b.x - a.x)
	var sz := absf(b.z - a.z)
	if sx < 1.0 or sz < 1.0:
		status_label.text = "Yard too small — drag a bigger rectangle."
		return
	var center := Vector3((a.x + b.x) * 0.5, 0.0, (a.z + b.z) * 0.5)
	var size := Vector2(sx, sz)
	var visual := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	visual.mesh = pm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(Color.YELLOW, YARD_PREVIEW_ALPHA + 0.15)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	visual.material_override = m
	visual.position = Vector3(center.x, 0.02, center.z)
	markers_root.add_child(visual)
	yard_markers.append(visual)
	WorldLayout.add_bale_yard("yard_%d" % yard_markers.size(), center, size, 0.0)
	status_label.text = "Bale yard %d × %d m placed." % [int(sx), int(sz)]

func _apply_loaded_layout() -> void:
	# If WorldLayout already has data (re-edit), re-render its markers visually.
	if WorldLayout.player_spawn != Vector3.ZERO:
		var node := _make_dot(TOOL_DEFS[Tool.PLAYER_SPAWN]["color"])
		node.position = WorldLayout.player_spawn
		markers_root.add_child(node)
		point_markers[Tool.PLAYER_SPAWN] = node
	for k in VEHICLE_TOOL_TO_ID:
		var vid : String = VEHICLE_TOOL_TO_ID[k]
		if WorldLayout.vehicle_spawns.has(vid):
			var node2 := _make_dot(TOOL_DEFS[k]["color"])
			node2.position = WorldLayout.vehicle_spawns[vid]
			markers_root.add_child(node2)
			point_markers[k] = node2
	for k in LINE_TOOL_TO_ID:
		var lid : String = LINE_TOOL_TO_ID[k]
		if WorldLayout.line_starts.has(lid):
			var node3 := _make_dot(TOOL_DEFS[k]["color"])
			node3.position = WorldLayout.line_starts[lid]
			markers_root.add_child(node3)
			point_markers[k] = node3
	for y in WorldLayout.bale_yards:
		var pm := PlaneMesh.new()
		pm.size = y["size"]
		var visual := MeshInstance3D.new()
		visual.mesh = pm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(Color.YELLOW, YARD_PREVIEW_ALPHA + 0.15)
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		visual.material_override = m
		visual.position = (y["origin"] as Vector3) + Vector3(0, 0.02, 0)
		markers_root.add_child(visual)
		yard_markers.append(visual)

# ── Save / cancel ────────────────────────────────────────────────────────────
func _on_save_pressed() -> void:
	WorldLayout.save()
	status_label.text = "Saved — returning to main menu"
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

func _on_back_pressed() -> void:
	# Reload so unsaved edits are discarded (re-read from disk).
	WorldLayout._load()
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

# ── PDOK Luchtfoto WMS fetch ─────────────────────────────────────────────────
func _on_fetch_satellite() -> void:
	var lat : float = float(lat_input.text) if lat_input else float(DEFAULT_LAT)
	var lon : float = float(lon_input.text) if lon_input else float(DEFAULT_LON)
	var extent_m : float = float(extent_input.text) if extent_input else float(DEFAULT_EXTENT_M)
	if extent_m <= 0.0: extent_m = DEFAULT_EXTENT_M
	# Approximate degrees-per-metre at our latitude. PDOK accepts EPSG:4326
	# bbox as minLat,minLon,maxLat,maxLon (yes, lat first — WMS 1.3.0 quirk).
	var dlat := extent_m / 111_320.0
	var dlon := extent_m / (111_320.0 * cos(deg_to_rad(lat)))
	var bbox := "%f,%f,%f,%f" % [lat - dlat * 0.5, lon - dlon * 0.5, lat + dlat * 0.5, lon + dlon * 0.5]
	var url := "%s?service=WMS&version=1.3.0&request=GetMap&layers=%s&crs=EPSG:4326&bbox=%s&width=%d&height=%d&format=image/png" % [
		PDOK_WMS, PDOK_LAYER, bbox, WMS_IMG_SIZE, WMS_IMG_SIZE
	]
	status_label.text = "Fetching satellite tile…"
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(_on_satellite_fetched.bind(req, extent_m, lat, lon))
	var err := req.request(url)
	if err != OK:
		status_label.text = "HTTP error: %s" % str(err)

func _on_satellite_fetched(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest, extent_m: float, lat: float, lon: float) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_label.text = "Satellite fetch failed (code %d)" % code
		return
	var img := Image.new()
	var err := img.load_png_from_buffer(body)
	if err != OK:
		status_label.text = "Could not decode satellite PNG"
		return
	# Cache so we don't re-fetch on next entry.
	img.save_png(SATELLITE_CACHE)
	_apply_satellite_image(img, extent_m)
	WorldLayout.satellite_center_rd = Vector2(lon, lat)   # store lon/lat in WGS84 (field name is legacy)
	WorldLayout.satellite_extent_m  = extent_m
	WorldLayout.has_satellite       = true
	status_label.text = "Satellite loaded (%.0f m extent)" % extent_m

func _try_load_cached_satellite() -> void:
	if not FileAccess.file_exists(SATELLITE_CACHE):
		return
	var img := Image.new()
	if img.load(SATELLITE_CACHE) != OK: return
	var ext : float = WorldLayout.satellite_extent_m if WorldLayout.has_satellite else float(DEFAULT_EXTENT_M)
	_apply_satellite_image(img, ext)

func _apply_satellite_image(img: Image, extent_m: float) -> void:
	var tex := ImageTexture.create_from_image(img)
	ground_material.albedo_texture = tex
	ground_material.albedo_color   = Color(1, 1, 1)
	(ground_quad.mesh as PlaneMesh).size = Vector2(extent_m, extent_m)
