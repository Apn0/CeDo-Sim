extends BaseVehicle

class_name Forklift

const SmoothedRateScript = preload("res://src/sim/SmoothedRate.gd")

## Standard LPG forklift with full fork hydraulics:
##   - Lift up / down
##   - Mast tilt forward / backward
##   - Rotator left / right (the lump-dumping mechanic)
##   - Pinch forks together / widen apart (fork positioner)
##   - Handbrake (inherited from BaseVehicle)
##
## Hydraulics are modelled as kinematic Node3D transforms (not physics joints)
## driven by tunable speeds. Load weight slows lift speed (real behaviour).
##
## Forks themselves are RigidBody3Ds with Joints in the actual scene file;
## this script controls the SETPOINTS, the joints follow.

# ── Fork node references (set in .tscn instance) ──────────────────────────────
@export_group("Fork rig nodes")
@export var lift_carriage_path  : NodePath          # Node3D that moves up/down on mast
@export var mast_pivot_path     : NodePath          # Node3D that tilts fw/bw
@export var rotator_path        : NodePath          # Node3D that rotates forks L/R
@export var left_fork_path      : NodePath          # Node3D — moves outward on widen
@export var right_fork_path     : NodePath          # Node3D — mirror

# ── Hydraulic limits & speeds ─────────────────────────────────────────────────
# #201 — lift_min_m / lift_max_m are the carriage Y offset in the FORKLIFT-LOCAL
# frame. With MastPivot at chassis-local Y = 0.40 m and the fork-tip mesh
# half-thickness = 0.025 m, fork-tip world Y above the floor = lift_height_m + 0.375.
# Real spec for a 2.5 t LPG counterbalance forklift:
#   - Carriage fully DOWN → tine bottoms FLAT on the floor (~no clearance);
#     achieved with lift_min_m = -0.375.
#   - Carriage fully UP   → 3.00 m fork-tip height (standard simplex mast);
#     achieved with lift_max_m = 2.625.
@export_group("Lift (vertical carriage)")
@export var lift_min_m              : float = -0.375   # tine flat on floor
@export var lift_max_m              : float =  2.625   # fork tip 3.00 m above floor
@export var lift_speed_no_load_m_s  : float = 0.60     # spec: 0.55–0.65 m/s unloaded
@export var lift_speed_full_load_m_s: float = 0.40     # spec: 0.40–0.55 m/s at rated load

@export_group("Mast tilt")
@export var tilt_min_deg            : float = -6.0     # forward — industry spec 3–6°; was -10° (unsafe)
@export var tilt_max_deg            : float = 12.0     # backward — standard
@export var tilt_speed_deg_s        : float = 8.0      # spec: 6–10°/s

@export_group("Rotator (lump-dump head)")
@export var rotator_min_deg         : float = -180.0
@export var rotator_max_deg         : float =  180.0
@export var rotator_speed_deg_s     : float = 60.0     # CeDo-spec dumper: ~60°/s (was 30 — too sluggish for a 3 s dump)

@export_group("Fork spread (positioner)")
@export var fork_spread_min_m       : float = 0.20     # = fork centres ±0.10 m → lump_cart pocket centres
@export var fork_spread_max_m       : float = 1.10     # widest pallet
@export var fork_spread_speed_m_s   : float = 0.10     # spec: 0.08–0.12 m/s (was 0.15 — too fast)

@export_group("Load")
@export var max_safe_load_kg        : float = 2500.0   # 2.5 t rated capacity (bale handling needs the headroom)

# ── Hydraulic pump-flow ramp time-constants ──────────────────────────────────
# Real hydraulic cylinders don't step from 0 → nominal velocity instantly; pump
# flow has to spin up against the relief valve. 0.3–0.6 s is the observed range
# on the CeDo Linde/Toyota fleet.
const LIFT_RAMP_TAU_S         : float = 0.45   # 0.3–0.6 s pump-flow ramp
const TILT_RAMP_TAU_S         : float = 0.40
const ROTATOR_RAMP_TAU_S      : float = 0.50
const FORK_SPREAD_RAMP_TAU_S  : float = 0.40

# ── Runtime hydraulic state (setpoints — meshes lerp toward these) ────────────
var lift_height_m  : float = -0.375
var tilt_deg       : float = 0.0
var rotator_deg    : float = 0.0
var fork_spread_m  : float = 0.45    # neutral spread (closer together by default)

# ── Resolved node refs (in _ready) ────────────────────────────────────────────
var _lift_carriage : Node3D
var _mast_pivot    : Node3D
var _rotator       : Node3D
var _left_fork     : Node3D
var _right_fork    : Node3D

# Load currently on the forks (kg) — set by FlatLumpDetector / pallet sensor.
var current_load_kg: float = 0.0

# ── Ramped actuator velocities (pump-flow inertia) ───────────────────────────
# Each axis tracks its CURRENT cylinder velocity; the operator input sets the
# TARGET velocity, and SmoothedRate eases between them with the constants above.
var _lift_velocity         : SmoothedRate = null
var _tilt_velocity         : SmoothedRate = null
var _rotator_velocity      : SmoothedRate = null
var _fork_spread_velocity  : SmoothedRate = null

# ── #211e — Bale alignment ghost ──────────────────────────────────────────────
# A wireframe / low-alpha rectangle projected onto the nearest ShredderFeedBelt
# deck in the lengthwise-aligned bale pose. Visible only when:
#   (a) this forklift is carrying a bale (BaseVehicle._carried_bale != null), AND
#   (b) the forklift is within GHOST_BELT_REACH_M of any ShredderFeedBelt.
# Tints:
#   • green (alpha 0.5)               when |yaw| ≤ GHOST_YAW_TOLERANCE_DEG
#   • red, flashing (alpha 0.5..0.8)  when cross-wise (|yaw| > tolerance)
# The ghost is a visual aid only — it never blocks the drop or modifies the
# belt's accept_bale decision. Wireframe via low-alpha additive + a thin border.
const GHOST_BELT_REACH_M    : float = 5.0
const GHOST_YAW_TOLERANCE_DEG : float = 15.0
const GHOST_BALE_LEN_M      : float = 1.4    # matches ShredderFeedBelt.BALE_LENGTH_M
const GHOST_BALE_WID_M      : float = 1.2
const GHOST_BALE_HGT_M      : float = 0.10   # flat slab — projected onto deck
const GHOST_FLASH_HZ        : float = 2.5
var _bale_alignment_ghost : Node3D = null
var _ghost_mesh           : MeshInstance3D = null
var _ghost_mat            : StandardMaterial3D = null
var _ghost_flash_t        : float = 0.0

# =============================================================================
func _ready() -> void:
	# Drive-ramp tuning per the throttle/brake audit. Real Linde/Toyota counter-
	# balance forklifts feel deliberately sluggish — operators don't want to
	# wheelspin a 4-tonne mast. ~0.95 s 0→12 km/h, ~0.21 s panic-stop from
	# top, brake softer than a car (the load fights you with mast inertia).
	# Set BEFORE super._ready() so the SmoothedRate picks up the tau on its
	# first approach() call.
	throttle_accel_mps2 = 3.5
	brake_decel_mps2    = 3.0   # #223: was 16 (1.6g) — a real forklift brakes ~2-3 m/s² or the load flies off
	coast_decel_mps2    = 2.0   # was 4
	throttle_ramp_tau_s = 1.2
	brake_ramp_tau_s    = 0.3
	super._ready()
	vehicle_type = "forklift"
	if lift_carriage_path: _lift_carriage = get_node_or_null(lift_carriage_path) as Node3D
	if mast_pivot_path:    _mast_pivot    = get_node_or_null(mast_pivot_path)    as Node3D
	if rotator_path:       _rotator       = get_node_or_null(rotator_path)       as Node3D
	if left_fork_path:     _left_fork     = get_node_or_null(left_fork_path)     as Node3D
	if right_fork_path:    _right_fork    = get_node_or_null(right_fork_path)    as Node3D
	_build_bale_alignment_ghost()
	_lift_velocity         = SmoothedRateScript.new(0.0, LIFT_RAMP_TAU_S)
	_tilt_velocity         = SmoothedRateScript.new(0.0, TILT_RAMP_TAU_S)
	_rotator_velocity      = SmoothedRateScript.new(0.0, ROTATOR_RAMP_TAU_S)
	_fork_spread_velocity  = SmoothedRateScript.new(0.0, FORK_SPREAD_RAMP_TAU_S)

func _physics_process(delta: float) -> void:
	super._physics_process(delta)   # base driving / fuel / handbrake
	if occupied:
		_update_hydraulics(delta)
	_apply_hydraulic_transforms()
	_update_bale_alignment_ghost(delta)

# =============================================================================
# #211e — BALE ALIGNMENT GHOST
# =============================================================================
## Spawn the ghost as a translucent slab parented to the world scene root via
## get_tree().current_scene so its world transform tracks the belt independently
## of the forklift's pose. Hidden until the proximity + carry-state check passes.
func _build_bale_alignment_ghost() -> void:
	_bale_alignment_ghost = Node3D.new()
	_bale_alignment_ghost.name = "BaleAlignmentGhost"
	_ghost_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(GHOST_BALE_WID_M, GHOST_BALE_HGT_M, GHOST_BALE_LEN_M)
	_ghost_mesh.mesh = bm
	_ghost_mat = StandardMaterial3D.new()
	_ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ghost_mat.albedo_color = Color(0.2, 0.95, 0.3, 0.5)
	# Unshaded so the rectangle reads as a HUD overlay even in shadow under the
	# deck guards; no_depth_test=false (default) so the deck still occludes it
	# when the camera is below the belt — that matches how a real alignment
	# laser projection would look.
	_ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ghost_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_ghost_mesh.material_override = _ghost_mat
	_bale_alignment_ghost.add_child(_ghost_mesh)
	_bale_alignment_ghost.visible = false
	# Parent to the world scene rather than the forklift — the ghost lives in
	# belt space, not vehicle space.
	call_deferred("_deferred_attach_ghost")

func _deferred_attach_ghost() -> void:
	if _bale_alignment_ghost == null:
		return
	var scene := get_tree().current_scene
	if scene != null:
		scene.add_child(_bale_alignment_ghost)

## Project the lengthwise-aligned bale pose onto the nearest belt deck when the
## forklift is carrying a bale and is within GHOST_BELT_REACH_M of any feed
## belt. Hidden otherwise.
func _update_bale_alignment_ghost(delta: float) -> void:
	if _bale_alignment_ghost == null or not is_instance_valid(_bale_alignment_ghost):
		return
	if _carried_bale == null:
		_bale_alignment_ghost.visible = false
		return
	var belt := _nearest_shredder_feed_belt(GHOST_BELT_REACH_M)
	if belt == null:
		_bale_alignment_ghost.visible = false
		return
	_bale_alignment_ghost.visible = true
	# Place the ghost on the belt deck at the LOAD_ZONE_M centre — that's where
	# accept_bale would drop the bale. Lengthwise = belt's +Z. The ghost is
	# parented in world space, so we set its global_transform.
	var deck_y : float = 0.7   # ShredderFeedBelt.deck_height default
	if "deck_height" in belt:
		deck_y = float(belt.get("deck_height"))
	# Local position: lane 0 (centre) and roughly 1 m into the deck from the
	# loading end. The ghost slab sits 0.15 m above the deck surface (same offset
	# accept_bale uses when it places a rider).
	var local_pos := Vector3(0.0, deck_y + 0.15, 1.0)
	var ghost_xf : Transform3D = (belt as Node3D).global_transform * Transform3D(Basis(), local_pos)
	_bale_alignment_ghost.global_transform = ghost_xf
	# Tint: green when carried-bale yaw matches belt yaw within ±15°, red
	# (flashing) otherwise. The belt provides _bale_yaw_deviation_deg() (#211a)
	# which already does the projection + 180° fold.
	var yaw_dev_deg : float = 0.0
	if belt.has_method("_bale_yaw_deviation_deg"):
		yaw_dev_deg = float(belt.call("_bale_yaw_deviation_deg", _carried_bale))
	if absf(yaw_dev_deg) <= GHOST_YAW_TOLERANCE_DEG:
		_ghost_flash_t = 0.0
		_ghost_mat.albedo_color = Color(0.2, 0.95, 0.3, 0.5)
	else:
		_ghost_flash_t += delta * GHOST_FLASH_HZ * TAU
		# alpha sweeps 0.5..0.8 in a sine; sin in [-1,1] → 0.5 + (sin+1)*0.15
		var a : float = 0.5 + (sin(_ghost_flash_t) + 1.0) * 0.15
		_ghost_mat.albedo_color = Color(0.95, 0.2, 0.2, a)

## Closest ShredderFeedBelt in the "shredder_feed_belt" group within `reach` m
## of the forklift's chassis origin. Returns null when nothing is in range.
func _nearest_shredder_feed_belt(reach: float) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var here : Vector3 = global_transform.origin
	var best : Node3D = null
	var best_d : float = reach
	for b in tree.get_nodes_in_group("shredder_feed_belt"):
		if not (b is Node3D) or not is_instance_valid(b):
			continue
		var d : float = (b as Node3D).global_transform.origin.distance_to(here)
		if d <= best_d:
			best = b as Node3D
			best_d = d
	return best

func _exit_tree() -> void:
	# The ghost is parented to the scene root, so it survives this node leaving.
	# Clean it up so a forklift respawn doesn't leak ghosts.
	if _bale_alignment_ghost != null and is_instance_valid(_bale_alignment_ghost):
		_bale_alignment_ghost.queue_free()
		_bale_alignment_ghost = null

# =============================================================================
# HYDRAULIC INPUT
# =============================================================================
func _update_hydraulics(delta: float) -> void:
	# Mouse-as-joystick (hold a button + drag — see BaseVehicle):
	#   LEFT  drag  Y = lift up/down,  X = mast tilt
	#   RIGHT drag  Y = fork spread,   X = rotator
	var m := _tool_axes()

	# Lift speed depends on load (real forklifts)
	var load_ratio := clampf(current_load_kg / max_safe_load_kg, 0.0, 1.0)
	var lift_speed := lerpf(lift_speed_no_load_m_s, lift_speed_full_load_m_s, load_ratio)

	# Lift up / down — target velocity ramps via SmoothedRate (pump-flow inertia).
	# The mouse-joystick term folds into the TARGET so a flick rides the same
	# 0.3–0.6 s ramp as a key tap.
	var lift_axis := Input.get_action_strength("forklift_lift_up") \
				   - Input.get_action_strength("forklift_lift_down")
	var target_lift_v : float = lift_axis * lift_speed + float(m["b"]) * lift_speed * MOUSE_TOOL_MULT
	var cur_lift_v    : float = _lift_velocity.approach(target_lift_v, delta)
	lift_height_m = clampf(lift_height_m + cur_lift_v * delta, lift_min_m, lift_max_m)

	# Mast tilt
	var tilt_axis := Input.get_action_strength("forklift_tilt_back") \
				   - Input.get_action_strength("forklift_tilt_fwd")
	var target_tilt_v : float = tilt_axis * tilt_speed_deg_s + float(m["a"]) * tilt_speed_deg_s * MOUSE_TOOL_MULT
	var cur_tilt_v    : float = _tilt_velocity.approach(target_tilt_v, delta)
	tilt_deg = clampf(tilt_deg + cur_tilt_v * delta, tilt_min_deg, tilt_max_deg)

	# Rotator (the signature lump-dumping mechanic)
	var rot_axis := Input.get_action_strength("forklift_rotator_right") \
				  - Input.get_action_strength("forklift_rotator_left")
	var target_rot_v : float = rot_axis * rotator_speed_deg_s + float(m["c"]) * rotator_speed_deg_s * MOUSE_TOOL_MULT
	var cur_rot_v    : float = _rotator_velocity.approach(target_rot_v, delta)
	rotator_deg = clampf(rotator_deg + cur_rot_v * delta, rotator_min_deg, rotator_max_deg)

	# Fork spread (pinch/widen)
	var spread_axis := Input.get_action_strength("forklift_forks_widen") \
					 - Input.get_action_strength("forklift_forks_pinch")
	var target_spread_v : float = spread_axis * fork_spread_speed_m_s + float(m["d"]) * fork_spread_speed_m_s * MOUSE_TOOL_MULT
	var cur_spread_v    : float = _fork_spread_velocity.approach(target_spread_v, delta)
	fork_spread_m = clampf(fork_spread_m + cur_spread_v * delta, fork_spread_min_m, fork_spread_max_m)

# =============================================================================
# APPLY TO MESH NODES
# =============================================================================
func _apply_hydraulic_transforms() -> void:
	if _lift_carriage:
		_lift_carriage.position.y = lift_height_m
	if _mast_pivot:
		_mast_pivot.rotation.x = deg_to_rad(tilt_deg)
	if _rotator:
		_rotator.rotation.z = deg_to_rad(rotator_deg)
	if _left_fork:
		_left_fork.position.x  = -fork_spread_m * 0.5
	if _right_fork:
		_right_fork.position.x =  fork_spread_m * 0.5

# =============================================================================
# NPC HYDRAULIC SETPOINTS  (task A)
# =============================================================================
# NPC autonomy tasks (EmptyLumpCartTask etc.) drive the hydraulics through
# these setters. Each clamps to the same physical envelope as the operator's
# keyboard input, and `_apply_hydraulic_transforms()` picks the new value up
# next physics tick. There's no time-ramp here — the autopilot is allowed to
# command a step change because the resulting motion is still bound by the
# kinematic AnimatableBody3D collision (no NPC can teleport a load).
func npc_set_lift(target_m: float) -> void:
	lift_height_m = clampf(target_m, lift_min_m, lift_max_m)

func npc_set_fork_spread(target_m: float) -> void:
	fork_spread_m = clampf(target_m, fork_spread_min_m, fork_spread_max_m)

func npc_set_tilt(target_deg: float) -> void:
	tilt_deg = clampf(target_deg, tilt_min_deg, tilt_max_deg)

## Convenience for the EmptyLumpCartTask: lowest forks + min spread is the
## "ready to insert into lump-cart pockets" pose (forks centred at ±0.10 m
## matching the pocket centres, tine bottoms flat on the floor).
func npc_pose_for_lump_cart() -> void:
	npc_set_lift(lift_min_m)
	npc_set_fork_spread(fork_spread_min_m)
	npc_set_tilt(0.0)

