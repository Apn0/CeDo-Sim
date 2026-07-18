extends Node3D
## Fly-through viewer for the RAW building scan (assets/building_3d_raw/
## texturedMesh.obj — the AliceVision photogrammetry mesh). Same content as
## RawMeshTest.tscn but with a WASD + mouse-look free camera so you can move
## around and inside the building.
##
## Opens in its own window:
##   Godot_v4.6.3 --path <CeDo_Simulator> res://src/scenes/world/RawMeshFly.tscn

const FLY_SPEED  : float = 7.0
const FLY_BOOST  : float = 5.0
const MOUSE_SENS : float = 0.0025

var _cam : Camera3D
var _yaw : float = 0.0
var _pitch : float = -0.12
var _mouse_captured : bool = true

func _ready() -> void:
	_cam = $Camera3D
	_apply_look()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _apply_look() -> void:
	_pitch = clampf(_pitch, deg_to_rad(-89.0), deg_to_rad(89.0))
	_cam.transform.basis = Basis(Vector3.UP, _yaw) * Basis(Vector3.RIGHT, _pitch)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _mouse_captured:
		_yaw -= event.relative.x * MOUSE_SENS
		_pitch -= event.relative.y * MOUSE_SENS
		_apply_look()
	elif event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			_mouse_captured = not _mouse_captured
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if _mouse_captured else Input.MOUSE_MODE_VISIBLE
		elif event.keycode == KEY_F12:
			_save_shot()

var _frames : int = 0

func _process(delta: float) -> void:
	_frames += 1
	if _frames == 150:
		var p := "C:/Users/arnod/AppData/Local/Temp/claude/V---Claude/370e0175-2243-4ddb-b7bf-1a7a58a5f0d3/scratchpad/raw_building_fly.png"
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		get_viewport().get_texture().get_image().save_png(p)
		print("[shot] ", p)
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

func _save_shot() -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://raw_building.png")
	print("[shot] user://raw_building.png")
