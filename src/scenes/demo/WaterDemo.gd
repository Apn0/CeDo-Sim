extends Node3D
## Standalone water-on-click demo (operator request 2026-07-15).
##
## Fly camera (WASD + mouse-look, Q/E down/up, Shift = boost), a 15 x 15 m floor
## 10 cm thick, the real CeDo flotation tank (id "flotation_tank", built through
## PlaceableCatalog so it is the exact plant model) fitted with TRUE trimesh
## collision so water pours INTO the bath instead of resting on a box lid, and a
## left-mouse water jet rated at 2000 L/min made of recycled RigidBody3D droplets
## that genuinely collide with the tank, the curbs and each other.
##
## Launch:  Godot --path <project> res://src/scenes/demo/water_demo.tscn

# ── Tunables ────────────────────────────────────────────────────────────────
const FLOOR_SIZE      : float = 15.0     # m (X and Z)
const FLOOR_THICK     : float = 0.10     # m (10 cm)
const CURB_H          : float = 0.25     # m — low retaining wall so water pools
const FLY_SPEED       : float = 6.0      # m/s
const FLY_BOOST       : float = 4.0      # x multiplier while Shift held
const MOUSE_SENS      : float = 0.0025   # rad / pixel

# Water jet: 2000 L/min = 33.33 L/s. Each droplet is one ~0.5 L parcel, so the
# emitter must launch ~66 parcels/s to hit the rated flow. Live droplets are
# capped and recycled (oldest freed first) so the sim stays real-time.
const LITRES_PER_MIN  : float = 2000.0
const LITRE_PER_DROP   : float = 0.5
const DROP_RADIUS     : float = 0.049    # m — sphere of 0.5 L
const JET_SPEED       : float = 9.0      # m/s out of the nozzle
const MAX_DROPS       : int   = 600

var _cam : Camera3D
var _yaw : float = 0.0
var _pitch : float = -0.15
var _mouse_captured : bool = true
var _drops : Array[RigidBody3D] = []
var _emit_accum : float = 0.0
var _water_mat : StandardMaterial3D
var _water_pm : PhysicsMaterial
var _rng := RandomNumberGenerator.new()

func _ready() -> void:
	_rng.randomize()
	_build_environment()
	_build_floor()
	_build_tank()
	_build_camera()
	_build_hud()
	_water_mat = StandardMaterial3D.new()
	_water_mat.albedo_color = Color(0.18, 0.48, 0.85, 0.72)
	_water_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_water_mat.roughness = 0.08
	_water_mat.metallic = 0.0
	_water_mat.rim_enabled = true
	_water_pm = PhysicsMaterial.new()
	_water_pm.friction = 0.02
	_water_pm.bounce = 0.03
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# ── World ─────────────────────────────────────────────────────────────────
func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var mat := ProceduralSkyMaterial.new()
	mat.sky_top_color = Color(0.35, 0.55, 0.80)
	mat.sky_horizon_color = Color(0.75, 0.80, 0.85)
	mat.ground_horizon_color = Color(0.55, 0.55, 0.55)
	mat.ground_bottom_color = Color(0.30, 0.30, 0.32)
	sky.sky_material = mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-40.0), 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)

func _build_floor() -> void:
	var body := StaticBody3D.new()
	body.name = "Floor"
	add_child(body)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(FLOOR_SIZE, FLOOR_THICK, FLOOR_SIZE)
	mi.mesh = bm
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.42, 0.43, 0.45)
	fmat.roughness = 0.9
	mi.material_override = fmat
	# Top face sits exactly at y = 0.
	mi.position = Vector3(0.0, -FLOOR_THICK * 0.5, 0.0)
	body.add_child(mi)
	var col := CollisionShape3D.new()
	var shp := BoxShape3D.new()
	shp.size = Vector3(FLOOR_SIZE, FLOOR_THICK, FLOOR_SIZE)
	col.shape = shp
	col.position = Vector3(0.0, -FLOOR_THICK * 0.5, 0.0)
	body.add_child(col)
	# Low retaining curbs so poured water pools on the slab (interacts with walls).
	var half := FLOOR_SIZE * 0.5
	var t := 0.15
	for spec in [
		[Vector3(0, CURB_H * 0.5, -half), Vector3(FLOOR_SIZE, CURB_H, t)],
		[Vector3(0, CURB_H * 0.5,  half), Vector3(FLOOR_SIZE, CURB_H, t)],
		[Vector3(-half, CURB_H * 0.5, 0), Vector3(t, CURB_H, FLOOR_SIZE)],
		[Vector3( half, CURB_H * 0.5, 0), Vector3(t, CURB_H, FLOOR_SIZE)],
	]:
		var cb := StaticBody3D.new()
		body.add_child(cb)
		var cmi := MeshInstance3D.new()
		var cbm := BoxMesh.new()
		cbm.size = spec[1]
		cmi.mesh = cbm
		cmi.material_override = fmat
		cmi.position = spec[0]
		cb.add_child(cmi)
		var ccol := CollisionShape3D.new()
		var cshp := BoxShape3D.new()
		cshp.size = spec[1]
		ccol.shape = cshp
		ccol.position = spec[0]
		cb.add_child(ccol)

func _build_tank() -> void:
	var tank : Node3D = PlaceableCatalog.build_node("flotation_tank", false, false)
	if tank == null:
		push_error("[WaterDemo] flotation_tank build failed")
		return
	add_child(tank)
	tank.position = Vector3.ZERO   # base sits at y = 0 (on the slab)
	_fit_trimesh_collision(tank)

# Strip the single box lid collision the catalog adds, then bake concave trimesh
# collision from every mesh so droplets fall into the actual tank cavity and hit
# the real walls / rolls / weir instead of a solid AABB.
func _fit_trimesh_collision(tank: Node3D) -> void:
	if tank is StaticBody3D:
		for c in tank.get_children():
			if c is CollisionShape3D:
				c.queue_free()
	var meshes : Array[MeshInstance3D] = []
	_gather_meshes(tank, meshes)
	for mi in meshes:
		if mi.mesh == null:
			continue
		mi.create_trimesh_collision()

func _gather_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_gather_meshes(c, out)

# ── Camera / controls ───────────────────────────────────────────────────────
func _build_camera() -> void:
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.far = 400.0
	_cam.position = Vector3(0.0, 4.0, 12.0)
	add_child(_cam)
	_apply_look()

func _apply_look() -> void:
	_pitch = clampf(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_cam.transform.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch -= event.relative.y * MOUSE_SENS
		_apply_look()
	elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		_mouse_captured = not _mouse_captured
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE

func _process(delta: float) -> void:
	_fly(delta)
	if _mouse_captured and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_spray(delta)

func _fly(delta: float) -> void:
	var dir := Vector3.ZERO
	var b := _cam.transform.basis
	if Input.is_key_pressed(KEY_W): dir -= b.z
	if Input.is_key_pressed(KEY_S): dir += b.z
	if Input.is_key_pressed(KEY_A): dir -= b.x
	if Input.is_key_pressed(KEY_D): dir += b.x
	if Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE): dir += Vector3.UP
	if Input.is_key_pressed(KEY_Q) or Input.is_key_pressed(KEY_CTRL): dir -= Vector3.UP
	if dir == Vector3.ZERO:
		return
	var speed := FLY_SPEED
	if Input.is_key_pressed(KEY_SHIFT):
		speed *= FLY_BOOST
	_cam.position += dir.normalized() * speed * delta

# ── Water jet ────────────────────────────────────────────────────────────────
func _spray(delta: float) -> void:
	var per_sec := (LITRES_PER_MIN / 60.0) / LITRE_PER_DROP
	_emit_accum += per_sec * delta
	var n := int(_emit_accum)
	_emit_accum -= float(n)
	var b := _cam.transform.basis
	var fwd := -b.z
	# Nozzle just below the eye, like holding a hose.
	var nozzle := _cam.global_position + fwd * 0.4 - b.y * 0.25
	for i in n:
		_spawn_drop(nozzle, fwd)

func _spawn_drop(pos: Vector3, fwd: Vector3) -> void:
	var d := RigidBody3D.new()
	d.mass = LITRE_PER_DROP
	d.linear_damp = 0.12
	d.continuous_cd = true
	d.physics_material_override = _water_pm
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = DROP_RADIUS
	col.shape = sph
	d.add_child(col)
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = DROP_RADIUS
	sm.height = DROP_RADIUS * 2.0
	sm.radial_segments = 6
	sm.rings = 4
	mi.mesh = sm
	mi.material_override = _water_mat
	d.add_child(mi)
	add_child(d)
	d.global_position = pos
	var spread := Vector3(
		_rng.randf_range(-0.6, 0.6),
		_rng.randf_range(-0.6, 0.6),
		_rng.randf_range(-0.6, 0.6))
	d.linear_velocity = fwd * JET_SPEED + spread
	_drops.append(d)
	while _drops.size() > MAX_DROPS:
		var old : RigidBody3D = _drops.pop_front()
		if is_instance_valid(old):
			old.queue_free()

# ── HUD ──────────────────────────────────────────────────────────────────────
func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var lbl := Label.new()
	lbl.text = "WASD move  ·  mouse look  ·  Q/E (or Ctrl/Space) down/up  ·  Shift boost\nLEFT MOUSE = 2000 L/min water jet  ·  ESC toggle mouse"
	lbl.position = Vector2(16, 12)
	lbl.add_theme_color_override("font_color", Color.WHITE)
	lbl.add_theme_color_override("font_outline_color", Color.BLACK)
	lbl.add_theme_constant_override("outline_size", 6)
	layer.add_child(lbl)
