extends BaseVehicle

class_name Forklift

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

var _bulk_load_kg: float = 0.0

func load_bulk(kg: float) -> void:
	_bulk_load_kg += kg

func unload_bulk() -> float:
	var amt = _bulk_load_kg
	_bulk_load_kg = 0.0
	return amt

# =============================================================================
func _ready() -> void:
	super._ready()
	vehicle_type = "forklift"
	if lift_carriage_path: _lift_carriage = get_node_or_null(lift_carriage_path) as Node3D
	if mast_pivot_path:    _mast_pivot    = get_node_or_null(mast_pivot_path)    as Node3D
	if rotator_path:       _rotator       = get_node_or_null(rotator_path)       as Node3D
	if left_fork_path:     _left_fork     = get_node_or_null(left_fork_path)     as Node3D
	if right_fork_path:    _right_fork    = get_node_or_null(right_fork_path)    as Node3D

func _physics_process(delta: float) -> void:
	super._physics_process(delta)   # base driving / fuel / handbrake
	if occupied:
		_update_hydraulics(delta)
	_apply_hydraulic_transforms()

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

	# Lift up / down
	var lift_axis := Input.get_action_strength("forklift_lift_up") \
				   - Input.get_action_strength("forklift_lift_down")
	lift_height_m = clampf(lift_height_m + lift_axis * lift_speed * delta
						   + float(m["b"]) * lift_speed * delta * MOUSE_TOOL_MULT, lift_min_m, lift_max_m)

	# Mast tilt
	var tilt_axis := Input.get_action_strength("forklift_tilt_back") \
				   - Input.get_action_strength("forklift_tilt_fwd")
	tilt_deg = clampf(tilt_deg + tilt_axis * tilt_speed_deg_s * delta
					   + float(m["a"]) * tilt_speed_deg_s * delta * MOUSE_TOOL_MULT, tilt_min_deg, tilt_max_deg)

	# Rotator (the signature lump-dumping mechanic)
	var rot_axis := Input.get_action_strength("forklift_rotator_right") \
				  - Input.get_action_strength("forklift_rotator_left")
	rotator_deg = clampf(rotator_deg + rot_axis * rotator_speed_deg_s * delta
						  + float(m["c"]) * rotator_speed_deg_s * delta * MOUSE_TOOL_MULT, rotator_min_deg, rotator_max_deg)

	# Fork spread (pinch/widen)
	var spread_axis := Input.get_action_strength("forklift_forks_widen") \
					 - Input.get_action_strength("forklift_forks_pinch")
	fork_spread_m = clampf(fork_spread_m + spread_axis * fork_spread_speed_m_s * delta
						   + float(m["d"]) * fork_spread_speed_m_s * delta * MOUSE_TOOL_MULT, fork_spread_min_m, fork_spread_max_m)

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

