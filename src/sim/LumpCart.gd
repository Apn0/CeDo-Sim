class_name LumpCart
extends RigidBody3D

# #98 — Operator grabs the lump_cart by its push-handle (crosshair + E). While
# grabbed, the cart's handle position tracks ~0.9m in front of the player at
# handle height, and yaws to face away from the player. Real-life mass is ~40 kg
# (bumped from 12 once handle-grab steering existed — walking-into-it shove had
# to stay possible at 12 kg, but with active grab the operator can drag and steer
# the full real weight).
#
# Release: press E again, OR walk further than RELEASE_DIST from the cart.

const HANDLE_LOCAL := Vector3(0.0, 0.78, 0.62)   # ~ handle grip in cart-local space
const HOLD_DIST    : float = 0.95                 # cart sits this far in front of player
const STIFF        : float = 14.0                 # how hard the cart chases the target
const YAW_STIFF    : float = 6.0
const RELEASE_DIST : float = 2.6
const MAX_SPEED    : float = 3.5

var _grabbed_by : Node3D = null

func crosshair_prompt(_p: Node3D) -> String:
	if _grabbed_by != null:
		return "Lumpenwagen loslaten [E]"
	return "Lumpenwagen pakken aan handvat [E]"

func crosshair_interact(player: Node3D) -> void:
	if _grabbed_by == null:
		_grabbed_by = player
		sleeping = false
	else:
		_grabbed_by = null

func _physics_process(_delta: float) -> void:
	if _grabbed_by == null or not is_instance_valid(_grabbed_by):
		return
	var fwd : Vector3 = -_grabbed_by.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length() < 0.001:
		return
	fwd = fwd.normalized()
	var target : Vector3 = _grabbed_by.global_position + fwd * HOLD_DIST
	var handle_world : Vector3 = global_transform * HANDLE_LOCAL
	var to_target : Vector3 = target - handle_world
	to_target.y = 0.0
	var v : Vector3 = to_target * STIFF
	if v.length() > MAX_SPEED:
		v = v.normalized() * MAX_SPEED
	linear_velocity = Vector3(v.x, linear_velocity.y, v.z)
	# Yaw the cart so its front (-Z handle is on +Z) faces away from the player.
	var desired_yaw : float = atan2(fwd.x, fwd.z) + PI
	var cur_yaw     : float = rotation.y
	var yaw_err     : float = wrapf(desired_yaw - cur_yaw, -PI, PI)
	angular_velocity = Vector3(0.0, yaw_err * YAW_STIFF, 0.0)
	if global_position.distance_to(_grabbed_by.global_position) > RELEASE_DIST:
		_grabbed_by = null
