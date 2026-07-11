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

# =============================================================================
# #198 — Fill + cool-down state.
# =============================================================================
# Lumps drop in from the laser-filter discharge hose (operator's spec). Each
# lump is hot (~120-180 °C) when extruded; the cart sits under the discharge
# accumulating lumps until either (a) it's full or (b) the line stops pushing.
# Once a lump is in the cart it cools to ambient over COOL_TIME_S (1-3 hours
# sim time). When ALL contents are cool AND the cart has at least
# EMPTY_THRESHOLD_KG of lumps in it, the NpcAutonomyBoard emits an
# "empty_lump_cart" task — an idle NPC will then grab a forklift, drive over,
# lift the cart, transport it to the indoor lumps_container, and dump.
# Operator-recalculated 2026-07-11: a full Lumpenwagen holds ~90 kg of lumps,
# with a small heap over the rim before the discharge truly can't add more.
const CAPACITY_KG       : float = 100.0   # hard cap — heaped a little over the top
const FULL_THRESHOLD_KG : float = 90.0    # above this → "is_full" → block more lumps
const EMPTY_THRESHOLD_KG: float = 20.0    # above this → worth emptying (don't haul ~empty carts)
const COOL_TIME_S_MIN   : float = 60.0 * 60.0   #  1 sim-hour minimum cool-down
const COOL_TIME_S_MAX   : float = 3.0 * 60.0 * 60.0   # 3 sim-hour worst case

const EMPTY_MASS_KG   : float = 40.0     # bare cart (steel dumpster + wheels)

var lumps_kg          : float = 0.0
var _last_received_at : float = -INF     # sim-time of the most recent lump
var _cool_time_s      : float = COOL_TIME_S_MIN   # randomised per receive

## Physics mass tracks the load: bare cart + whatever lumps are in it. A cart
## with 200 kg of lumps genuinely pushes/steers like 240 kg, not like an empty
## one. Called after every fill/dump so the RigidBody the player shoves and the
## forklift lifts feels the real weight.
func _sync_mass() -> void:
	mass = EMPTY_MASS_KG + lumps_kg

func is_full() -> bool:
	return lumps_kg >= FULL_THRESHOLD_KG

func has_lumps_worth_emptying() -> bool:
	return lumps_kg >= EMPTY_THRESHOLD_KG

## Lumps are cool when at least _cool_time_s has passed since the last lump
## landed. Returns false if there's nothing in the cart (no point emptying).
func is_cool() -> bool:
	if lumps_kg <= 0.001:
		return false
	var now_s : float = _now_sim_s()
	return (now_s - _last_received_at) >= _cool_time_s

## Called by the laser-filter discharge when a lump drops into this cart.
func receive_lump(mass_kg: float) -> void:
	if mass_kg <= 0.0:
		return
	if is_full():
		# Operator spec: when full, the discharge backs up / overflows on the
		# floor — but the simulator doesn't model that yet. For now we hard-cap
		# the cart's mass and the upstream filter will see is_full() and stop
		# pushing.
		return
	lumps_kg = clampf(lumps_kg + mass_kg, 0.0, CAPACITY_KG)
	_sync_mass()
	_last_received_at = _now_sim_s()
	# Each receive resets the cool-down with a fresh random sample in [min,max].
	_cool_time_s = randf_range(COOL_TIME_S_MIN, COOL_TIME_S_MAX)

## Called by the EmptyLumpCartTask after the forklift dumps the cart into the
## lumps_container. Returns how many kg were dumped (so the receiving container
## can grow its own fill level by that amount).
func empty() -> float:
	var dumped : float = lumps_kg
	lumps_kg = 0.0
	_sync_mass()
	_last_received_at = -INF
	return dumped

## Sim time in seconds since the ShiftClock's day-zero epoch. Falls back to the
## wall-clock if the shift clock isn't reachable (test scenes).
func _now_sim_s() -> float:
	var sc := get_tree().get_root().find_child("ShiftClock", true, false)
	if sc and "shift_elapsed_seconds" in sc:
		return float(sc.shift_elapsed_seconds)
	return Time.get_ticks_msec() / 1000.0

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
