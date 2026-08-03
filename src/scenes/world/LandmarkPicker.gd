extends Node3D
## Free-fly landmark picker for georeferencing the AliceVision scan against the
## North-up satellite tile. Two instances are launched (LandmarkBuilding.tscn and
## LandmarkSat.tscn); in each you fly around, press F10 to ARM, then LMB to drop a
## numbered dot on a feature. Drop 2-4 dots per window on the SAME real-world
## features in the SAME order. Each window writes its dots' world X/Z to a JSON
## file; a separate solver reads both and computes heading + scale + offset.
##
## Controls:
##   RMB drag ....... look around
##   W/A/S/D ........ move (relative to look)
##   Q / E .......... down / up
##   Shift .......... move 4x faster
##   F10 ............ toggle ARM (must be armed to place dots)
##   LMB ............ (armed) drop a numbered dot at the surface under the cursor
##   Z .............. undo last dot
##   H .............. clear all dots
##   Enter / F9 ..... save JSON now (also auto-saves on window close)
##
## Args (after --):  <mode>  where mode is "building" or "sat".

const OUT_DIR := "C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/"
const SAT := "C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/sat_overlay.png"

var _mode : String = "building"
var _out_path : String = ""
var _cam : Camera3D
var _armed : bool = false
var _looking : bool = false
var _dots : Array = []          # Array[Vector3] world hit points
var _marker_r : float = 0.4
var _move_speed : float = 8.0
var _hud : Label
var _space : PhysicsDirectSpaceState3D
var _home_pos : Vector3 = Vector3(0, 20, 20)
var _home_target : Vector3 = Vector3.ZERO
var _home_size : float = 30.0

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() >= 1:
		_mode = a[0]
	_out_path = OUT_DIR + ("landmarks_%s.json" % _mode)
	_cam = $Camera3D as Camera3D

	# Marker size + speed scale to the world (sat plane = metres, scan = ~15 units).
	if _mode == "sat":
		_marker_r = 2.5
		_move_speed = 45.0
	else:
		_marker_r = 0.30
		_move_speed = 2.2

	# Satellite tile texture onto the ground plane (North-up, 1 unit = 1 m).
	if _mode == "sat":
		var g := get_node_or_null("Ground") as MeshInstance3D
		if g != null:
			var img := Image.new()
			if img.load(SAT) == OK:
				var m2 := StandardMaterial3D.new()
				m2.albedo_texture = ImageTexture.create_from_image(img)
				m2.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
				g.material_override = m2
			else:
				push_error("[picker] could not load satellite " + SAT)

	# Scan mode: flat STRAIGHT-DOWN ORTHOGRAPHIC view, exactly like the satellite
	# window (which worked). No flying — pan + click. Vertical ortho rays => a click
	# lands at the exact X/Z under the cursor via the y=0 plane, holes irrelevant,
	# and no 30s collider build. North (-Z) is up on screen.
	if _mode == "building":
		# Force a dark background so the light-gray roof reads with clear edges.
		var we := get_node_or_null("WorldEnvironment") as WorldEnvironment
		if we != null and we.environment != null:
			we.environment.background_mode = Environment.BG_COLOR
			we.environment.background_color = Color(0.06, 0.06, 0.09)
		var mi := _find_mesh_instance(self)
		if mi != null and mi.mesh != null:
			# Show the drape's texture at native (photographic) brightness, ignoring
			# scene lighting/exposure — it's Google-Earth aerial imagery of the roof.
			var am := mi.mesh as ArrayMesh
			if am != null:
				for i in am.get_surface_count():
					var sm := am.surface_get_material(i)
					if sm is BaseMaterial3D:
						var d := (sm as BaseMaterial3D).duplicate() as BaseMaterial3D
						d.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						mi.set_surface_override_material(i, d)
			var aabb := mi.get_aabb()
			var center : Vector3 = mi.global_transform * aabb.get_center()
			var radius : float = maxf(aabb.size.x, aabb.size.z) * 0.5
			_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
			_cam.size = radius * 2.4
			_cam.position = Vector3(center.x, center.y + 150.0, center.z)
			_cam.look_at(center, Vector3(0, 0, -1))
			_home_pos = _cam.position
			_home_target = center
			_home_size = _cam.size
			print("[picker] top-down ortho: center=(%.2f,%.2f,%.2f) size=%.2f" % [center.x, center.y, center.z, _cam.size])
	_make_hud()
	_refresh_hud()
	print("[picker] mode=%s  out=%s" % [_mode, _out_path])
	get_tree().set_auto_accept_quit(false)

func _find_mesh_instance(n: Node) -> MeshInstance3D:
	if n is MeshInstance3D:
		return n as MeshInstance3D
	for c in n.get_children():
		var r := _find_mesh_instance(c)
		if r != null:
			return r
	return null

func _make_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	_hud = Label.new()
	_hud.position = Vector2(16, 12)
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 6)
	cl.add_child(_hud)

func _refresh_hud() -> void:
	var arm := "ARMED (LMB drops dot)" if _armed else "not armed (press F10)"
	_hud.text = "%s  |  %s  |  dots: %d\nRMB look  WASD move  Q/E down/up  wheel zoom  R reset-view  Shift fast  Z undo  H clear  Enter save" % [_mode.to_upper(), arm, _dots.size()]

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save()
		get_tree().quit()

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_RIGHT:
			_looking = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed and _armed:
			_place_dot(mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(0.9)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.111)
	elif e is InputEventMouseMotion and _looking:
		var mm := e as InputEventMouseMotion
		_cam.rotation.y -= mm.relative.x * 0.003
		_cam.rotation.x = clampf(_cam.rotation.x - mm.relative.y * 0.003, -1.5, 1.5)
	elif e is InputEventKey and e.pressed and not e.echo:
		var k := e as InputEventKey
		match k.keycode:
			KEY_F10:
				_armed = not _armed
				_refresh_hud()
			KEY_R:
				_cam.position = _home_pos
				if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
					_cam.size = _home_size
					_cam.look_at(_home_target, Vector3(0, 0, -1))
				else:
					_cam.look_at(_home_target, Vector3.UP)
			KEY_Z:
				if not _dots.is_empty():
					_dots.pop_back()
					var last := get_child(get_child_count() - 1)
					if last is MeshInstance3D and (last as Node).name.begins_with("dot_"):
						last.queue_free()
					_renumber()
					_refresh_hud()
			KEY_H:
				for c in get_children():
					if c.name.begins_with("dot_"):
						c.queue_free()
				_dots.clear()
				_refresh_hud()
			KEY_ENTER, KEY_KP_ENTER, KEY_F9:
				_save()

func _zoom(f: float) -> void:
	if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		_cam.size = clampf(_cam.size * f, 4.0, 400.0)
	else:
		# Dolly along the view direction: wheel-up (f<1) moves forward, wheel-down back.
		var fwd := -_cam.global_transform.basis.z.normalized()
		var step := (1.0 - f) * 6.0
		_cam.position += fwd * step

func _place_dot(screen_pos: Vector2) -> void:
	var from := _cam.project_ray_origin(screen_pos)
	var dir := _cam.project_ray_normal(screen_pos)
	# Straight-down ortho => vertical ray => the y=0 plane hit is the exact X/Z under
	# the cursor, independent of surface height or holes in the scan mesh.
	if absf(dir.y) < 1e-6:
		print("[picker] miss (looking along horizon)")
		return
	var t := -from.y / dir.y
	if t <= 0.0:
		print("[picker] miss (plane behind camera)")
		return
	var p := from + dir * t
	_dots.append(p)
	_spawn_marker(p, _dots.size())
	_refresh_hud()
	print("[picker] dot %d  world=(%.3f, %.3f, %.3f)" % [_dots.size(), p.x, p.y, p.z])

func _spawn_marker(p: Vector3, num: int) -> void:
	var col := Color.from_hsv(fmod(0.15 + 0.27 * num, 1.0), 0.9, 1.0)
	var mi := MeshInstance3D.new()
	mi.name = "dot_%d" % num
	var sph := SphereMesh.new()
	sph.radius = _marker_r
	sph.height = _marker_r * 2.0
	mi.mesh = sph
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 4.0
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mi.material_override = m
	mi.position = p
	add_child(mi)
	var l := Label3D.new()
	l.text = str(num)
	l.font_size = 200
	l.pixel_size = _marker_r * 0.02
	l.modulate = Color(1, 1, 1)
	l.outline_size = 40
	l.no_depth_test = true
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.position = p + Vector3(0, _marker_r * 3.0, 0)
	mi.add_child(l)

func _renumber() -> void:
	# Rebuild markers so numbering stays 1..N after an undo.
	for c in get_children():
		if c.name.begins_with("dot_"):
			c.queue_free()
	var pts := _dots.duplicate()
	_dots.clear()
	for p in pts:
		_dots.append(p)
		_spawn_marker(p, _dots.size())

func _save() -> void:
	var out := {"mode": _mode, "count": _dots.size(), "points": []}
	for i in _dots.size():
		var p : Vector3 = _dots[i]
		out["points"].append({"i": i + 1, "x": p.x, "y": p.y, "z": p.z})
	var f := FileAccess.open(_out_path, FileAccess.WRITE)
	if f == null:
		push_error("[picker] cannot write " + _out_path)
		return
	f.store_string(JSON.stringify(out, "  "))
	f.close()
	print("[picker] SAVED %d dots -> %s" % [_dots.size(), _out_path])

func _process(delta: float) -> void:
	var v := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): v.z -= 1.0
	if Input.is_key_pressed(KEY_S): v.z += 1.0
	if Input.is_key_pressed(KEY_A): v.x -= 1.0
	if Input.is_key_pressed(KEY_D): v.x += 1.0
	if Input.is_key_pressed(KEY_E): v.y += 1.0
	if Input.is_key_pressed(KEY_Q): v.y -= 1.0
	if v == Vector3.ZERO:
		return
	var fast := 3.0 if Input.is_key_pressed(KEY_SHIFT) else 1.0
	if _cam.projection == Camera3D.PROJECTION_ORTHOGONAL:
		# Top-down: W/S/A/D pan in world X/Z; pan rate scales with zoom.
		var pan := _cam.size * 0.5 * fast * delta
		_cam.position += Vector3(v.x, 0.0, v.z).normalized() * pan
	else:
		# Fly: horizontal relative to yaw, vertical world Y.
		var basis := Basis(Vector3.UP, _cam.rotation.y)
		var world_v := basis * Vector3(v.x, 0, v.z) + Vector3(0, v.y, 0)
		_cam.position += world_v.normalized() * _move_speed * fast * delta
