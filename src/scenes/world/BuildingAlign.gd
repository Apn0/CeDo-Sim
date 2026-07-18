extends Node3D
## Holographic ALIGNMENT gizmo for the AliceVision building scan
## (assets/building_3d_raw/texturedMesh.obj).
##
## The scan comes out of photogrammetry with NO known real-world heading, scale
## or ground position. This tool drops it into the world as a translucent cyan
## HOLOGRAM sitting on a ground grid, with:
##   • a N/E/S/W compass + North arrow (North = -Z, the Godot/forward convention)
##   • a holographic RADIUS RING on the floor whose metres you tweak to calibrate
##     scale against a known real dimension (e.g. the plant is ~180 m across)
##   • live yaw / scale / position you jog by hand until it matches reality
## Press P to dump the resulting transform (heading°, scale×, offset) so it can be
## baked into the real integration.
##
## Launch (managed by the assistant, windowed):
##   Godot_v4.6.3 --path <proj> res://src/scenes/world/BuildingAlign.tscn

const FLY_SPEED   : float = 18.0
const FLY_BOOST   : float = 6.0
const MOUSE_SENS  : float = 0.0025
const YAW_RATE    : float = 35.0     # deg/s while Q/E held
const SCALE_RATE  : float = 1.6      # ×/s while Z/X held (multiplicative)
const RADIUS_RATE : float = 30.0     # m/s while R/F held
const MOVE_RATE   : float = 25.0     # m/s hologram nudge on arrows
const LIFT_RATE   : float = 15.0     # m/s hologram up/down on T/G

var _cam : Camera3D
var _holo : MeshInstance3D
var _ring : MeshInstance3D
var _hud : Label
var _labels : Dictionary = {}        # "N"/"E"/"S"/"W" -> Label3D

var _yaw : float = 0.0
var _pitch : float = -0.28
var _mouse_captured : bool = true

# Hologram alignment state (what this tool exists to set).
var heading_deg : float = 0.0
var scale_factor : float = 8.4       # doc's rough metres-per-unit estimate
var holo_pos : Vector3 = Vector3(0.0, 30.0, 0.0)
var ring_radius_m : float = 90.0     # half of the ~180 m plant span

func _ready() -> void:
	_cam = $Camera3D
	_holo = $Hologram
	_ring = $RadiusRing
	_hud = $HUD/Label
	_build_compass()
	_apply_look()
	_apply_hologram()
	_rebuild_ring()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_look() -> void:
	_pitch = clampf(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_cam.transform.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)

## Compose: world-yaw (heading) × 180° X-flip (AliceVision Y-down → Godot Y-up),
## uniformly scaled, translated to the ground offset. Heading composes cleanly on
## top of the flip because the flip is baked into the local basis.
func _apply_hologram() -> void:
	var b := Basis(Vector3.UP, deg_to_rad(heading_deg)) * Basis(Vector3.RIGHT, PI)
	b = b.scaled(Vector3.ONE * scale_factor)
	_holo.transform = Transform3D(b, holo_pos)

func _rebuild_ring() -> void:
	var tm := TorusMesh.new()
	tm.inner_radius = maxf(ring_radius_m - 1.2, 0.2)
	tm.outer_radius = ring_radius_m + 1.2
	tm.rings = 96
	tm.ring_segments = 12
	_ring.mesh = tm
	_ring.rotation = Vector3(deg_to_rad(90.0), 0.0, 0.0)   # lie flat in the XZ plane
	_ring.position = Vector3(0.0, 0.1, 0.0)
	# Reposition the compass labels onto the ring edge.
	if _labels.has("N"): (_labels["N"] as Label3D).position = Vector3(0.0, 3.0, -ring_radius_m)
	if _labels.has("S"): (_labels["S"] as Label3D).position = Vector3(0.0, 3.0,  ring_radius_m)
	if _labels.has("E"): (_labels["E"] as Label3D).position = Vector3( ring_radius_m, 3.0, 0.0)
	if _labels.has("W"): (_labels["W"] as Label3D).position = Vector3(-ring_radius_m, 3.0, 0.0)

func _build_compass() -> void:
	for key in ["N", "E", "S", "W"]:
		var l := Label3D.new()
		l.text = key
		l.font_size = 200
		l.pixel_size = 0.05
		l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		l.no_depth_test = true
		l.modulate = Color(1.0, 0.85, 0.2) if key == "N" else Color(0.6, 0.9, 1.0)
		add_child(l)
		_labels[key] = l
	# North arrow on the ground (a shaft + head), pointing -Z.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.2)
	mat.emission_energy_multiplier = 2.0
	var shaft := MeshInstance3D.new()
	var sm := BoxMesh.new(); sm.size = Vector3(1.5, 0.3, 40.0)
	shaft.mesh = sm; shaft.material_override = mat
	shaft.position = Vector3(0.0, 0.2, -20.0)
	add_child(shaft)
	var head := MeshInstance3D.new()
	var hm := CylinderMesh.new(); hm.top_radius = 0.0; hm.bottom_radius = 4.0; hm.height = 10.0
	head.mesh = hm; head.material_override = mat
	head.position = Vector3(0.0, 0.2, -44.0)
	head.rotation = Vector3(deg_to_rad(-90.0), 0.0, 0.0)
	add_child(head)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch -= event.relative.y * MOUSE_SENS
		_apply_look()
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_ESCAPE:
				_mouse_captured = not _mouse_captured
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
			KEY_P:
				print("[align] heading=%.1f deg  scale=%.3f x  pos=(%.1f, %.1f, %.1f)  ring=%.1f m"
					% [heading_deg, scale_factor, holo_pos.x, holo_pos.y, holo_pos.z, ring_radius_m])
			KEY_F12:
				_save_shot()
			KEY_END:
				get_tree().quit()

var _frames : int = 0

func _process(delta: float) -> void:
	_frames += 1
	if _frames == 180:
		_save_shot("C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/building_align.png")

	# ── Fly camera ──────────────────────────────────────────────────────────
	var b := _cam.transform.basis
	var dir := Vector3.ZERO
	if Input.is_key_pressed(KEY_W): dir -= b.z
	if Input.is_key_pressed(KEY_S): dir += b.z
	if Input.is_key_pressed(KEY_A): dir -= b.x
	if Input.is_key_pressed(KEY_SPACE): dir += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL): dir -= Vector3.UP
	if Input.is_key_pressed(KEY_D): dir += b.x
	if dir != Vector3.ZERO:
		var spd := FLY_SPEED * (FLY_BOOST if Input.is_key_pressed(KEY_SHIFT) else 1.0)
		_cam.position += dir.normalized() * spd * delta

	# ── Jog the hologram alignment ──────────────────────────────────────────
	var changed := false
	if Input.is_key_pressed(KEY_Q): heading_deg = fmod(heading_deg - YAW_RATE * delta + 360.0, 360.0); changed = true
	if Input.is_key_pressed(KEY_E): heading_deg = fmod(heading_deg + YAW_RATE * delta, 360.0); changed = true
	if Input.is_key_pressed(KEY_Z): scale_factor = maxf(scale_factor / (1.0 + SCALE_RATE * delta * 0.1), 0.1); changed = true
	if Input.is_key_pressed(KEY_X): scale_factor = scale_factor * (1.0 + SCALE_RATE * delta * 0.1); changed = true
	if Input.is_key_pressed(KEY_UP):    holo_pos.z -= MOVE_RATE * delta; changed = true
	if Input.is_key_pressed(KEY_DOWN):  holo_pos.z += MOVE_RATE * delta; changed = true
	if Input.is_key_pressed(KEY_LEFT):  holo_pos.x -= MOVE_RATE * delta; changed = true
	if Input.is_key_pressed(KEY_RIGHT): holo_pos.x += MOVE_RATE * delta; changed = true
	if Input.is_key_pressed(KEY_T): holo_pos.y += LIFT_RATE * delta; changed = true
	if Input.is_key_pressed(KEY_G): holo_pos.y -= LIFT_RATE * delta; changed = true
	if changed:
		_apply_hologram()

	# ── Ring radius (scale calibration) ─────────────────────────────────────
	var ring_changed := false
	if Input.is_key_pressed(KEY_R): ring_radius_m += RADIUS_RATE * delta; ring_changed = true
	if Input.is_key_pressed(KEY_F): ring_radius_m = maxf(ring_radius_m - RADIUS_RATE * delta, 2.0); ring_changed = true
	if ring_changed:
		_rebuild_ring()

	_update_hud()

func _update_hud() -> void:
	_hud.text = "BUILDING ALIGN — heading %.0f°   scale %.2f× (%.1f m/unit)   ring Ø %.0f m   holo y %.0f m\n" \
		% [heading_deg, scale_factor, scale_factor, ring_radius_m * 2.0, holo_pos.y] \
		+ "Q/E spin heading · Z/X scale · R/F ring radius · arrows move · T/G raise/lower · WASD+mouse fly · Shift boost · P dump · F12 shot · End quit\n" \
		+ "North = -Z (red arrow).  N/E/S/W on the ring."

func _save_shot(path: String = "") -> void:
	if path == "":
		path = "user://building_align.png"
	if path.begins_with("C:/") or path.begins_with("/"):
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	get_viewport().get_texture().get_image().save_png(path)
	print("[shot] ", path)
