extends BaseVehicle
class_name Merlo

const SmoothedRateScript = preload("res://src/sim/SmoothedRate.gd")

## Diesel telehandler ("far reacher") with an MX-style grapple bucket: a wide
## scoop with a top grapple of tines that clamp down onto the bucket.
##
## Controls (reuses the forklift action set):
##   R / F  boom raise / lower
##   T / G  telescope extend / retract
##   Z / C  bucket curl (tilt the whole scoop)
##   V / B  grapple open / close (top tines up / down)

@export_group("Boom rig nodes")
@export var boom_pivot_path  : NodePath
@export var boom_extend_path : NodePath
@export var bucket_tilt_path : NodePath   # the whole bucket assembly (curl)
@export var grapple_arm_path : NodePath   # the tine grapple (opens/closes)

# #201 — Spec calibration against real Merlo telehandlers (TF42.7 / P40.17 class
# — what CeDo actually runs). Telehandlers are big diesel hydraulic machines:
# boom cylinders are slow and powerful, telescope reaches 6+ m, the grapple
# bucket curls past 90° for clean rollback dumping.
@export_group("Boom")
@export var boom_min_deg            : float = -5.0    # slight crouch for digging at ground
@export var boom_max_deg            : float = 70.0    # P40.17 reaches ~72°; was 55° (couldn't tip top of stack)
@export var boom_speed_deg_s        : float = 10.0    # spec: 8–12°/s — these cylinders are slow

@export_group("Telescope")
@export var extend_min_m            : float = 0.0
@export var extend_max_m            : float = 6.0     # P40.17 telescopes ~7 m worth at ground reach; was 3 m
@export var extend_speed_m_s        : float = 0.50    # spec: 0.40–0.60 m/s under load (was 0.6 — a touch optimistic)

@export_group("Bucket curl")
# Bucket needs ~110° rollback for clean dumping; -45° to +40° couldn't tip a load.
@export var curl_min_deg            : float = -45.0   # forks-down / digging crowd
@export var curl_max_deg            : float = 110.0   # full rollback dump (was 40°)
@export var curl_speed_deg_s        : float =  35.0   # spec: 30–45°/s (was 25 — sluggish)

@export_group("Grapple")
@export var grapple_closed_deg      : float =  0.0    # tines flush against bucket
@export var grapple_open_deg        : float = 90.0    # tines straight up (was 75° — didn't fully clear)
@export var grapple_speed_deg_s     : float = 70.0    # spec: 60–80°/s (was 45)

@export_group("Load")
@export var max_safe_load_kg        : float = 4000.0  # P40.17 rated at ground; derate applies past 50 % reach

## Hydraulic ramp time constants. Telehandler boom cylinders are slow + powerful.
## Spec: 0.5–1.0 s. Boom + telescope get the longer tau (more mass swung);
## bucket curl + grapple ramp faster (smaller cylinders).
const BOOM_RAMP_TAU_S    : float = 0.80
const EXTEND_RAMP_TAU_S  : float = 0.70
const CURL_RAMP_TAU_S    : float = 0.50
const GRAPPLE_RAMP_TAU_S : float = 0.40

var boom_deg    : float = 0.0
var extend_m    : float = 0.0
var curl_deg    : float = 0.0
var grapple_deg : float = 60.0   # start open so the grapple reads as raised tines

var _boom_velocity    : SmoothedRate = null
var _extend_velocity  : SmoothedRate = null
var _curl_velocity    : SmoothedRate = null
var _grapple_velocity : SmoothedRate = null

var _boom_pivot  : Node3D
var _boom_extend : Node3D
var _boom_ext_rest : Vector3 = Vector3.ZERO   # extension's local rest position; extend slides RELATIVE to this
var _bucket_tilt : Node3D
var _grapple_arm : Node3D

func _ready() -> void:
	# Drive-ramp tuning per the throttle/brake audit. Telehandler diesel pulls
	# harder than an electric forklift but the chassis is heavier and the
	# operator carries the full mass with a long boom — longest input tau (1.5 s)
	# so a full-load Merlo doesn't jerk the load on tap. 16 m/s² brake matches
	# the rest of the lift fleet.
	throttle_accel_mps2 = 4.0
	brake_decel_mps2    = 16.0
	coast_decel_mps2    = 4.0
	throttle_ramp_tau_s = 1.5
	brake_ramp_tau_s    = 0.3
	super._ready()
	vehicle_type = "merlo"
	all_wheel_steer = true   # rear wheels counter-steer — the all-wheel look in the photo
	if boom_pivot_path:  _boom_pivot  = get_node_or_null(boom_pivot_path)  as Node3D
	if boom_extend_path:
		_boom_extend = get_node_or_null(boom_extend_path) as Node3D
		if _boom_extend: _boom_ext_rest = _boom_extend.position
	if bucket_tilt_path: _bucket_tilt = get_node_or_null(bucket_tilt_path) as Node3D
	if grapple_arm_path: _grapple_arm = get_node_or_null(grapple_arm_path) as Node3D
	# #201 — physical bucket + grapple. The .tscn switched both nodes to
	# AnimatableBody3D with sync_to_physics + collision shapes mirroring the
	# visible meshes. PhysicsMaterial gives the bucket an honest contact feel
	# (painted-steel bowl μ ≈ 0.9, rubber-faced tines μ ≈ 1.6 so a clamp grip
	# really holds). Loads sit in the bowl and stay there via friction × gravity;
	# the grapple presses DOWN to add a normal force on top.
	var bucket_pm := PhysicsMaterial.new()
	bucket_pm.friction = 0.9
	bucket_pm.bounce   = 0.05
	if _bucket_tilt is PhysicsBody3D:
		(_bucket_tilt as PhysicsBody3D).physics_material_override = bucket_pm
	var grapple_pm := PhysicsMaterial.new()
	grapple_pm.friction = 1.6
	grapple_pm.bounce   = 0.02
	if _grapple_arm is PhysicsBody3D:
		(_grapple_arm as PhysicsBody3D).physics_material_override = grapple_pm
	_boom_velocity    = SmoothedRateScript.new(0.0, BOOM_RAMP_TAU_S)
	_extend_velocity  = SmoothedRateScript.new(0.0, EXTEND_RAMP_TAU_S)
	_curl_velocity    = SmoothedRateScript.new(0.0, CURL_RAMP_TAU_S)
	_grapple_velocity = SmoothedRateScript.new(0.0, GRAPPLE_RAMP_TAU_S)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if occupied:
		_update_boom(delta)
	_apply_boom()
	if occupied:
		_apply_boom_chassis_lever(delta)

## Telehandler stabiliser effect — when the bucket is touching the ground AND
## the operator is still holding F (boom_lower), the boom can't push further
## down, so instead the leverage LIFTS the chassis. Real Merlos use this to
## level themselves on uneven ground or push the front wheels off the floor.
##
## We detect "grounded" via a short ray DOWNWARD from the bucket tilt origin.
## If the operator is pressing the lower-boom action AND there's ground within
## ~15 cm of the bucket, we raise the chassis at `BOOM_LEVER_LIFT_S` m/s. The
## kinematic settle that runs next frame will gently pull the chassis back
## down once the operator releases F.
const BOOM_LEVER_LIFT_S      : float = 0.9   # m/s the chassis can rise when leveraging
const BOOM_LEVER_PROBE_DIST  : float = 0.25  # ground considered "in contact" within this
const BOOM_LEVER_MAX_HEIGHT  : float = 2.2   # safety cap above settled ride height

func _apply_boom_chassis_lever(delta: float) -> void:
	# Default state: ride height drifts back to normal so the chassis settles
	# down when the operator stops leveraging.
	var leveraging := false
	if _bucket_tilt and Input.get_action_strength("forklift_lift_down") > 0.5:
		# Cast a short ray under the bucket. If the bucket is within contact
		# distance of the ground AND the operator is still asking the boom to
		# go DOWN, the boom can't, so the leverage lifts the chassis instead.
		var bucket_world := _bucket_tilt.global_position
		var space := get_world_3d().direct_space_state
		if space != null:
			var from := bucket_world + Vector3.UP * 0.5
			var to   := bucket_world + Vector3.DOWN * (BOOM_LEVER_PROBE_DIST + 0.6)
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = [get_rid()]
			if _carried_bale and _carried_bale is PhysicsBody3D:
				q.exclude.append((_carried_bale as PhysicsBody3D).get_rid())
			var hit := space.intersect_ray(q)
			if not hit.is_empty():
				var ground_y: float = (hit["position"] as Vector3).y
				if bucket_world.y - ground_y <= BOOM_LEVER_PROBE_DIST:
					leveraging = true
	# Move the ride-height target instead of the chassis directly — the base
	# settle code lerps the chassis toward that target every frame, so we get
	# a smooth lift/lower without fighting the settle code.
	if leveraging:
		_ride_height_target_m = minf(
			_ride_height_target_m + BOOM_LEVER_LIFT_S * delta,
			DEFAULT_RIDE_HEIGHT + BOOM_LEVER_MAX_HEIGHT)
	else:
		# Drop back to default ride height when we let off
		_ride_height_target_m = move_toward(
			_ride_height_target_m, DEFAULT_RIDE_HEIGHT, BOOM_LEVER_LIFT_S * delta)

func _update_boom(delta: float) -> void:
	# Mouse-as-joystick (hold a button + drag — see BaseVehicle):
	#   LEFT  drag  Y = boom elevation,  X = grapple clamp (open/close)
	#   RIGHT drag  Y = bucket curl,     X = telescope extend/retract
	# One full drag ≈ a couple of seconds of the keyboard hydraulics.
	var m := _tool_axes()

	# #201 — load-aware boom + telescope: a carried load slows the hydraulics.
	# Telehandlers feel this strongly on extension (long cylinder, low pressure
	# margin) and a bit on raise. Multiplier from 1.0 unloaded down to 0.55 at
	# rated load, applied to both speeds.
	var load_ratio : float = 0.0
	if _carried_bale != null and is_instance_valid(_carried_bale) and "mass" in _carried_bale:
		load_ratio = clampf(float(_carried_bale.mass) / max_safe_load_kg, 0.0, 1.0)
	var load_mult : float = lerpf(1.0, 0.55, load_ratio)
	var bsp : float = boom_speed_deg_s * load_mult
	var esp : float = extend_speed_m_s * load_mult

	var b := Input.get_action_strength("forklift_lift_up") \
		   - Input.get_action_strength("forklift_lift_down")
	var target_boom_v : float = b * bsp + float(m["b"]) * bsp * MOUSE_TOOL_MULT
	var cur_boom_v    : float = _boom_velocity.approach(target_boom_v, delta)
	boom_deg = clampf(boom_deg + cur_boom_v * delta, boom_min_deg, boom_max_deg)

	var e := Input.get_action_strength("forklift_tilt_back") \
		   - Input.get_action_strength("forklift_tilt_fwd")
	var target_extend_v : float = e * esp + float(m["c"]) * esp * MOUSE_TOOL_MULT
	var cur_extend_v    : float = _extend_velocity.approach(target_extend_v, delta)
	extend_m = clampf(extend_m + cur_extend_v * delta, extend_min_m, extend_max_m)

	var c := Input.get_action_strength("forklift_rotator_right") \
		   - Input.get_action_strength("forklift_rotator_left")
	var target_curl_v : float = c * curl_speed_deg_s + float(m["d"]) * curl_speed_deg_s * MOUSE_TOOL_MULT
	var cur_curl_v    : float = _curl_velocity.approach(target_curl_v, delta)
	curl_deg = clampf(curl_deg + cur_curl_v * delta, curl_min_deg, curl_max_deg)

	# widen = open (lift tines), pinch = close (clamp onto the bucket)
	var g := Input.get_action_strength("forklift_forks_widen") \
		   - Input.get_action_strength("forklift_forks_pinch")
	var target_grapple_v : float = g * grapple_speed_deg_s + float(m["a"]) * grapple_speed_deg_s * MOUSE_TOOL_MULT
	var cur_grapple_v    : float = _grapple_velocity.approach(target_grapple_v, delta)
	grapple_deg = clampf(grapple_deg + cur_grapple_v * delta, grapple_closed_deg, grapple_open_deg)

func _apply_boom() -> void:
	if _boom_pivot:
		_boom_pivot.rotation.x = -deg_to_rad(boom_deg)   # +boom_deg raises the tip
	if _boom_extend:
		# Slide forward from the captured rest position (not an absolute z=extend_m,
		# which teleported FBX meshes whose rest origin wasn't at 0).
		_boom_extend.position = _boom_ext_rest + Vector3(0.0, 0.0, extend_m)
	if _bucket_tilt:
		_bucket_tilt.rotation.x = deg_to_rad(curl_deg)
	if _grapple_arm:
		_grapple_arm.rotation.x = -deg_to_rad(grapple_deg)   # +grapple_deg lifts tines (open)
