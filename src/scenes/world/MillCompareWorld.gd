extends Node3D
## Side-by-side A/B compare world for the 2026-08-29 maalmolen (mill) rebuild.
##
##   <godot> --path . res://src/scenes/world/MillCompareWorld.tscn
##
## LEFT  (-X) = the OLD mill, built from `src/tests/_catalog_pre_mill_20260829.gd`
##              — a verbatim snapshot of PlaceableCatalog.gd as it stood BEFORE
##              the rebuild (copied from PlaceableCatalog.gd.bak, which the
##              verifier confirmed byte-identical to HEAD; only the
##              `class_name PlaceableCatalog` line is stripped so both scripts
##              can coexist in one process).
## RIGHT (+X) = the CURRENT mill from the live PlaceableCatalog.
##
## Both go through `_build_model()` — same entry point, same size, same colour,
## same ghost flag — so the ONLY variable is the builder itself. StaticMerge is
## bypassed exactly as src/tests/mesh_census_2026_08_29.gd does it, so what you
## see is the authored geometry, not the baked merge.
##
## Camera: ORBIT. Left-drag rotate, wheel zoom, right-drag or WASD pan,
## Q/E height, F frame both, 1 frame BEFORE, 2 frame AFTER, ESC quit.
##
## Deliberately NOT wired into tools/regression/run.sh — interactive viewer,
## it would hang the harness.
##
## THE SNAPSHOT IS GITIGNORED ON PURPOSE. It is a verbatim 685 KB copy of the
## whole catalog; committing it would mean every future `grep` of src/ returns
## two hits for every builder in the file, forever. It is also a frozen copy
## that silently rots as the real catalog moves on. Regenerate it on demand —
## one command, exact, from whatever commit you actually want to compare
## against (SNAPSHOT_SRC_COMMIT below is the mill rebuild's parent):
##
##   git show <commit>:src/build/PlaceableCatalog.gd \
##     | sed '2{/^class_name PlaceableCatalog$/d}' \
##     > src/tests/_catalog_pre_mill_20260829.gd
##
## Loaded with load() rather than preload() so a fresh clone without the
## snapshot still parses and boots — it just shows the AFTER model plus an
## on-screen note telling you how to regenerate.

const SNAPSHOT_PATH : String = "res://src/tests/_catalog_pre_mill_20260829.gd"
## The commit whose PlaceableCatalog.gd the snapshot must be cut from for the
## BEFORE side to mean "immediately before the 2026-08-29 mill rebuild".
const SNAPSHOT_SRC_COMMIT : String = "822c9a5"

const MILL_ID    : String = "mill"
const SEPARATION : float  = 7.0     # metres between the two models' centres

var _pivot    : Vector3 = Vector3(0.0, 2.2, 0.0)
var _yaw      : float = deg_to_rad(35.0)
var _pitch    : float = deg_to_rad(-16.0)
var _dist     : float = 17.0
var _cam      : Camera3D = null
var _dragging : bool = false
var _panning  : bool = false

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_camera()
	_build_hud()
	_spawn_pair()
	_apply_camera()

# ── the two mills ────────────────────────────────────────────────────────────
func _spawn_pair() -> void:
	var item : Dictionary = PlaceableCatalog.get_item(MILL_ID)
	if item.is_empty():
		push_error("[MillCompare] catalog has no '%s'" % MILL_ID)
		return
	var sz  : Vector3 = item.get("size", Vector3.ONE)
	var col : Color   = item.get("color", Color.WHITE)
	var cat : String  = String(item.get("category", ""))
	print("[MillCompare] mill size=%s colour=%s category=%s" % [str(sz), str(col), cat])

	# BEFORE side — only if the gitignored snapshot is present (see header).
	var old_cat : GDScript = null
	if ResourceLoader.exists(SNAPSHOT_PATH):
		old_cat = load(SNAPSHOT_PATH) as GDScript
	var n_old : int = 0
	if old_cat != null:
		var old_root := Node3D.new()
		old_root.name = "MILL_OLD"
		add_child(old_root)
		old_root.global_position = Vector3(-SEPARATION * 0.5, 0.0, 0.0)
		old_cat._build_model(old_root, MILL_ID, cat, sz, col, false)
		n_old = _count_meshes(old_root)
	else:
		var msg := "snapshot missing — BEFORE side not shown.\nRegenerate:  git show %s:src/build/PlaceableCatalog.gd | sed '2{/^class_name PlaceableCatalog$/d}' > src/tests/_catalog_pre_mill_20260829.gd" % SNAPSHOT_SRC_COMMIT
		push_warning("[MillCompare] " + msg)
		print("[MillCompare] " + msg)
		_sign(Vector3(-SEPARATION * 0.5, 4.0, 0.0),
			"BEFORE unavailable\n(see console)", Color(1.0, 0.75, 0.45))

	var new_root := Node3D.new()
	new_root.name = "MILL_NEW"
	add_child(new_root)
	new_root.global_position = Vector3(SEPARATION * 0.5, 0.0, 0.0)
	PlaceableCatalog._build_model(new_root, MILL_ID, cat, sz, col, false)

	var n_new := _count_meshes(new_root)
	print("[MillCompare] OLD parts=%d   NEW parts=%d" % [n_old, n_new])

	if n_old > 0:
		_sign(Vector3(-SEPARATION * 0.5, 5.8, 0.0),
			"BEFORE  —  %d parts" % n_old, Color(1.0, 0.55, 0.55))
	_sign(Vector3(SEPARATION * 0.5, 5.8, 0.0),
		"AFTER  —  %d parts" % n_new, Color(0.55, 1.0, 0.65))

func _count_meshes(n: Node) -> int:
	var c : int = 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count_meshes(ch)
	return c

func _sign(at: Vector3, text: String, tint: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.outline_size = 18
	lbl.modulate = tint
	lbl.pixel_size = 0.006
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.position = at
	add_child(lbl)

# ── orbit camera ─────────────────────────────────────────────────────────────
func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.name = "OrbitCam"
	_cam.current = true
	_cam.fov = 60.0
	_cam.near = 0.05
	_cam.far = 900.0
	add_child(_cam)

func _apply_camera() -> void:
	if _cam == null:
		return
	var dir := Vector3(
		cos(_pitch) * sin(_yaw),
		sin(_pitch),
		cos(_pitch) * cos(_yaw))
	_cam.global_position = _pivot - dir * _dist
	_cam.look_at(_pivot, Vector3.UP)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		match mb.button_index:
			MOUSE_BUTTON_LEFT:
				_dragging = mb.pressed
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_panning = mb.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if mb.pressed:
					_dist = maxf(2.0, _dist * 0.90)
					_apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if mb.pressed:
					_dist = minf(160.0, _dist * 1.10)
					_apply_camera()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _dragging:
			_yaw -= mm.relative.x * 0.006
			_pitch = clampf(_pitch - mm.relative.y * 0.006,
				deg_to_rad(-88.0), deg_to_rad(88.0))
			_apply_camera()
		elif _panning:
			var right := _cam.global_transform.basis.x
			var up := _cam.global_transform.basis.y
			_pivot -= (right * mm.relative.x + up * -mm.relative.y) * (_dist * 0.0016)
			_apply_camera()
	elif event is InputEventKey:
		var k := event as InputEventKey
		if not k.pressed or k.echo:
			return
		match k.keycode:
			KEY_ESCAPE:
				get_tree().quit(0)
			KEY_F:
				_pivot = Vector3(0.0, 2.2, 0.0)
				_dist = 17.0
				_apply_camera()
			KEY_1:
				_pivot = Vector3(-SEPARATION * 0.5, 2.2, 0.0)
				_dist = 9.0
				_apply_camera()
			KEY_2:
				_pivot = Vector3(SEPARATION * 0.5, 2.2, 0.0)
				_dist = 9.0
				_apply_camera()

func _process(delta: float) -> void:
	# WASD/QE move the pivot, for anyone who would rather not drag.
	if _cam == null:
		return
	var mv := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): mv -= _cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_S): mv += _cam.global_transform.basis.z
	if Input.is_key_pressed(KEY_A): mv -= _cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_D): mv += _cam.global_transform.basis.x
	if Input.is_key_pressed(KEY_E): mv += Vector3.UP
	if Input.is_key_pressed(KEY_Q): mv -= Vector3.UP
	if mv != Vector3.ZERO:
		_pivot += mv.normalized() * delta * maxf(3.0, _dist * 0.45)
		_apply_camera()

# ── scenery ──────────────────────────────────────────────────────────────────
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(38.0), 0.0)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	add_child(sun)
	# Soft back-fill so the shaded sides still read while orbiting.
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-24.0), deg_to_rad(-140.0), 0.0)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	add_child(fill)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.40, 0.56, 0.78)
	sky_mat.sky_horizon_color = Color(0.76, 0.83, 0.90)
	sky_mat.ground_horizon_color = Color(0.52, 0.54, 0.56)
	sky_mat.ground_bottom_color = Color(0.28, 0.30, 0.32)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.85
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)

func _build_ground() -> void:
	var mi := MeshInstance3D.new()
	mi.name = "Floor"
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.42, 0.44)
	mat.roughness = 0.95
	mi.material_override = mat
	add_child(mi)

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	add_child(cl)
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left = 14
	panel.offset_top = 12
	panel.offset_right = 720
	panel.offset_bottom = 80
	cl.add_child(panel)
	var hud := Label.new()
	hud.add_theme_font_size_override("font_size", 17)
	hud.text = "MAALMOLEN A/B    left-drag orbit  ·  wheel zoom  ·  right-drag or WASD pan  ·  Q/E height\n" \
		+ "F = frame both    ·    1 = BEFORE (left)    ·    2 = AFTER (right)    ·    ESC = quit"
	panel.add_child(hud)
