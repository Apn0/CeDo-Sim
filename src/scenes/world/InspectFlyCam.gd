extends Camera3D

class_name InspectFlyCam

## #inspect — Free-fly Camera3D for InspectMode.
##
## Driven entirely from this script while it owns the viewport. Detaches from
## the player completely (no parent-relative motion) so the operator can drift
## anywhere in the scene to verify gizmo placement vs world objects.
##
## Controls (only when this camera is .current):
##   W/S      forward / backward in cam-LOCAL XZ (Y is preserved — strafing
##            forward at 45° pitch still walks the ground plane instead of
##            burrowing into the floor)
##   A/D      strafe left / right in cam-LOCAL XZ
##   Space    up (world +Y)
##   Ctrl     down (world -Y)
##   Mouse    look (yaw + clamped pitch)
##   Shift    4× speed boost
##   F8       toggled OFF externally by PlayerController (see InspectMode.toggle())
##   Esc      handled by InspectMode (deactivates whole mode)
##
## Mouse capture: the cam captures the cursor when its _ready / activation
## fires so the operator can mouse-look immediately. It does NOT release the
## cursor on free — InspectMode's deactivate() restores whatever mouse mode
## the previous owner (HUD / vehicle) had.

const SPEED_DEFAULT : float = 10.0     # m/s baseline (task spec)
const SPEED_SPRINT  : float = 40.0     # m/s with Shift (4×)
const PITCH_MIN     : float = -PI * 0.49
const PITCH_MAX     : float =  PI * 0.49

var _yaw : float = 0.0
var _pitch : float = 0.0
var _mouse_sens : float = 0.003

func _ready() -> void:
	# Pull sensitivity from the player's gameplay slider so the fly cam feels
	# the same as walking around. Falls back to 0.003 if SettingsManager is
	# unavailable (tests / sandbox scenes).
	if has_node("/root/SettingsManager"):
		var g : Dictionary = SettingsManager.gameplay()
		_mouse_sens = float(g.get("mouse_sensitivity_x", 0.003))
	# Capture the mouse so look works the moment Inspect Mode is on. If a HUD
	# pause was open it has already released the cursor; we override here.
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	# Idle process + unhandled input only — physics_process is fine to skip,
	# we don't collide with anything.
	set_process(true)
	set_process_unhandled_input(true)

## Called by InspectMode.activate() right after the camera is added to the
## tree. Seeds position + yaw + pitch so the operator's facing is preserved.
func init_pose(pos: Vector3, yaw: float, pitch: float) -> void:
	global_position = pos
	_yaw = yaw
	_pitch = clampf(pitch, PITCH_MIN, PITCH_MAX)
	_apply_rotation()

func _process(delta: float) -> void:
	# Movement only when this camera owns the viewport — keeps the cam frozen
	# while Inspect Mode is being torn down (InspectMode flips .current away
	# before queue_free fires).
	if not current:
		return
	var basis := global_transform.basis
	# Horizontal-axis (cam-local) WASD: project forward / right onto the XZ
	# plane so the operator walks the ground when looking up/down rather than
	# diving toward the look axis.
	var fwd : Vector3 = -basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.0001:
		# Looking straight up/down — pick world -Z as the forward fallback so
		# WASD still does something instead of stalling.
		fwd = Vector3(0.0, 0.0, -1.0)
	fwd = fwd.normalized()
	var right := basis.x
	right.y = 0.0
	if right.length_squared() < 0.0001:
		right = Vector3(1.0, 0.0, 0.0)
	right = right.normalized()
	var move := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		move += fwd
	if Input.is_action_pressed("move_backward"):
		move -= fwd
	if Input.is_action_pressed("move_right"):
		move += right
	if Input.is_action_pressed("move_left"):
		move -= right
	# Vertical: Space up, Ctrl down (in world Y). Use raw key checks so we
	# don't conflict with the player's crouch_toggle action (Ctrl) which is
	# disabled while Inspect Mode is on anyway, but a duplicate binding can
	# confuse the input system if both poll the same key.
	if Input.is_key_pressed(KEY_SPACE):
		move += Vector3.UP
	if Input.is_key_pressed(KEY_CTRL):
		move += Vector3.DOWN
	if move != Vector3.ZERO:
		var speed : float = SPEED_SPRINT if Input.is_key_pressed(KEY_SHIFT) else SPEED_DEFAULT
		global_position += move.normalized() * speed * delta

func _unhandled_input(event: InputEvent) -> void:
	if not current:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel : Vector2 = (event as InputEventMouseMotion).relative
		_yaw   -= rel.x * _mouse_sens
		_pitch -= rel.y * _mouse_sens
		_pitch = clampf(_pitch, PITCH_MIN, PITCH_MAX)
		_apply_rotation()

## Apply yaw (around world +Y) THEN pitch (around the now-yawed +X) — standard
## FPS-camera composition that prevents roll from creeping in when the operator
## sweeps the mouse diagonally.
func _apply_rotation() -> void:
	var b := Basis.IDENTITY
	b = b.rotated(Vector3.UP, _yaw)
	b = b.rotated(b.x, _pitch)
	global_transform.basis = b
