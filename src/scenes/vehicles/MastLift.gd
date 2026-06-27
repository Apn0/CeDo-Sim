extends BaseVehicle

# The plant ran three JLG-style vertical-mast personnel lifts. "Mast lift" is
# the correct industry term — the script was originally called ScissorLift
# (and the vehicle_type string was "scissor_lift") in error. The class +
# vehicle_type are now "MastLift" / "mast_lift" everywhere; legacy save data
# carrying the old strings is migrated on load by WorldLayout, MapOverlay,
# VehicleEnterArea, and BaseVehicle.
class_name MastLift

const SmoothedRateScript = preload("res://src/sim/SmoothedRate.gd")

## Ground rescue panel — a proximity Area3D around the GroundPanel mesh. While
## the player is on foot inside the zone, holding the interact key (E) LOWERS the
## platform. This is the safety feature the operator asked for: if someone gets
## a heart attack up top, anyone on the ground can bring them down.
var _ground_panel_player_near : bool = false
const GROUND_LOWER_RATE_M_S : float = 0.55

func _setup_ground_panel_trigger() -> void:
	# Offset by the GroundPanel mesh on the chassis side.
	InteractionTriggers.make_pickup_trigger(
		self, 1.4,
		_on_ground_panel_body_entered,
		_on_ground_panel_body_exited,
		"GroundPanelTrigger", 1, Vector3(0.86, 0.7, 0))

func _on_ground_panel_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_ground_panel_player_near = true
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, "Hold to LOWER platform (ground rescue)")

func _on_ground_panel_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_ground_panel_player_near = false
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

## Build the procedural double-hinged jib at the mast top. The lower segment
## pivots forward from vertical, the upper segment counter-rotates so at fold=0
## (stowed) the tip folds back DOWN to the mast-top point — the platform sits
## directly above the mast — and at fold=1 the linkage extends ~2 × segment
## length forward at mast-top height. The platform's WORLD position follows the
## tip each frame but its ORIENTATION stays level so the operator doesn't tilt.
func _build_jib() -> void:
	_jib_root = Node3D.new()
	_jib_root.name = "JibRoot"
	add_child(_jib_root)
	# Sits at the mast-top X/Z, Y is set per-frame in _apply_platform_transforms.
	if _platform_node:
		_jib_root.position.x = _platform_node.position.x
		_jib_root.position.z = _platform_node.position.z

	# Operator: orange segment belongs on the BASKET side, steel on the MAST side.
	var mat_mast := StandardMaterial3D.new()
	mat_mast.albedo_color = Color(0.78, 0.80, 0.74)    # bare steel — mast-side (lower) segment
	mat_mast.metallic = 0.5
	mat_mast.roughness = 0.4
	var mat_basket := StandardMaterial3D.new()
	mat_basket.albedo_color = Color(0.85, 0.33, 0.06)  # JLG orange — basket-side (upper) segment
	mat_basket.roughness = 0.55

	_jib_lower = MeshInstance3D.new()
	_jib_lower.name = "JibLower"
	var lower_mesh := BoxMesh.new()
	lower_mesh.size = Vector3(0.18, jib_segment_m, 0.18)
	_jib_lower.mesh = lower_mesh
	_jib_lower.material_override = mat_mast
	# Mesh is centred at the segment midpoint; shift it +Y so the PIVOT is at the
	# segment's BASE (where JibRoot sits) and the FAR end is at (0, segment, 0).
	_jib_lower.position.y = jib_segment_m * 0.5
	_jib_root.add_child(_jib_lower)

	# Pivot at the LOWER segment's tip for the upper. We add an intermediate
	# Node3D at that local point so we can rotate the upper segment around the
	# correct hinge, independent of the lower's mesh-centring offset.
	var upper_pivot := Node3D.new()
	upper_pivot.name = "UpperPivot"
	upper_pivot.position = Vector3(0.0, jib_segment_m * 0.5, 0.0)   # at the lower's tip in lower's local frame
	_jib_lower.add_child(upper_pivot)

	_jib_upper = MeshInstance3D.new()
	_jib_upper.name = "JibUpper"
	var upper_mesh := BoxMesh.new()
	upper_mesh.size = Vector3(0.16, jib_segment_m, 0.16)
	_jib_upper.mesh = upper_mesh
	_jib_upper.material_override = mat_basket
	_jib_upper.position.y = jib_segment_m * 0.5
	upper_pivot.add_child(_jib_upper)

	# Tip marker at the upper segment's far end (local +Y by half-length).
	_jib_tip = Node3D.new()
	_jib_tip.name = "JibTip"
	_jib_tip.position = Vector3(0.0, jib_segment_m * 0.5, 0.0)
	_jib_upper.add_child(_jib_tip)

## Per-frame: rotate the two hinges and reposition the platform to track the tip.
## upper_pivot is the FIRST child of _jib_lower — we get it by name to keep the
## node-graph clean.
# Orange-beam swing geometry (operator spec, second pass): the GRAY (steel,
# mast-side) beam stays perfectly VERTICAL. The ORANGE (basket-side) beam swings
# through a 25°-from-DOWN (stow) → 135°-from-DOWN (full reach) arc — i.e. starts
# at 25° forward of straight-down (basket folded against the mast on the +Z side)
# and ends at 45° ABOVE horizontal (basket high + forward). Previous values had
# the upper rotating through -Z (backward) instead of +Z (forward); the sign of
# the swing is reversed below so it now reaches OUT-AND-UP as the operator asked.
const JIB_ORANGE_STOW_RAD  : float = PI - deg_to_rad(25.0)      # 25° fwd of straight-down
const JIB_ORANGE_REACH_RAD : float = -deg_to_rad(135.0 - 25.0)  # swing toward up by 110°

func _apply_jib_transforms() -> void:
	if _jib_lower == null or _jib_upper == null or _jib_tip == null:
		return
	# GRAY (lower) beam: perfectly vertical, always. No tilt.
	_jib_lower.rotation.x = 0.0
	# ORANGE (upper) beam: carries the whole jib motion. swing_t maps the usable
	# fold band [MIN,MAX] to 0..1; rotation goes stow → reach.
	var swing_t : float = clampf(
		(jib_fold - JIB_FOLD_MIN) / maxf(JIB_FOLD_MAX - JIB_FOLD_MIN, 0.0001), 0.0, 1.0)
	var upper_pivot := _jib_lower.get_node_or_null("UpperPivot") as Node3D
	if upper_pivot != null:
		upper_pivot.rotation.x = JIB_ORANGE_STOW_RAD + swing_t * JIB_ORANGE_REACH_RAD
	# Platform follows the tip in WORLD position, but keeps its orientation level
	# with the chassis — the operator on the deck doesn't get tilted.
	if _platform_node:
		var tip_world := _jib_tip.global_position
		_platform_node.global_position = tip_world
		_platform_node.global_transform.basis = global_transform.basis

## REVERTED to fixed-cab boarding (operator feedback: free movement on the deck
## "fucked it up very bad"). The problem with the platform ride was that the
## player capsule stayed ALIVE on the deck, so on-foot keys (WASD walk, Z prone,
## crouch, etc.) fired AT THE SAME TIME as the lift's drive + raise controls —
## you'd walk and drive simultaneously, go prone while operating, etc.
##
## Returning false makes OperatorContext take the normal cab path: hide + freeze
## the player capsule and hand the viewport to Platform/CabCamera. That camera is
## parented to the Platform node, so the view STILL rises with the operator as
## the mast extends — you get the elevation experience without the dual-input
## mess. R/F raise/lower, WASD drive, ground-rescue panel all still work.
func is_platform_ride() -> bool:
	return false

func platform_node() -> Node3D:
	return _platform_node

## Refuse to be boarded while the platform is raised — otherwise the boarding
## code teleports the player up onto the deck (the operator-reported bug). They
## must lower it from the ground control panel first.
func can_enter() -> bool:
	return _platform_height < elevated_threshold_m

func enter_refusal_reason() -> String:
	if _platform_height >= elevated_threshold_m:
		return "Lower the platform from the ground panel first"
	return ""

## Electric vertical-MAST lift — a JLG Toucan-style "hoogwerker", as used on the
## CeDo sorting floor (the plant ran three of them). Despite the legacy class name
## (kept so saves / HUD / map keep working), this is NOT a scissor lift: it's a
## compact self-propelled VERTICAL MAST lift — a nested telescoping mast at the
## front raises a small work platform; a small CounterBlock represents the
## battery / drive enclosure at the rear (the earlier 2 m³ red capsule "cowl"
## was operator-rejected as not matching any real machine and was removed).
##
## The platform rises from chassis-top (0 m) to PLATFORM_MAX_M with R / F (or the
## mouse joystick — hold LMB, drag up/down). A safety interlock drops the travel
## speed to 1.5 km/h while the platform is above ELEVATED_THRESHOLD_M, matching the
## real machine — the "snail mode up high" the operator liked.
##
## The mast is animated by sliding each nested stage up a fraction of the platform
## height, so the sections telescope out proportionally. No physics joints needed;
## the CabCamera is parented to the Platform so the view rises with the operator.

@export var platform_max_m      : float = 7.0
@export var platform_speed_m_s  : float = 0.55   # m/s lift rate
@export var normal_speed_kmh    : float = 6.0
@export var elevated_speed_kmh  : float = 1.5
@export var elevated_threshold_m: float = 0.5

# Jib at the top of the mast — a double-hinged folding arm that swings the
# platform out horizontally up to ~3 m of reach. JibLower pivots from vertical
# (0°) to ~90° forward; JibUpper counter-rotates so the platform stays roughly
# level. Driven by jib_fold ∈ [0, 1] (0 = stowed, 1 = full reach). T = extend
# (forklift_tilt_back), G = retract (forklift_tilt_fwd) — keys the mast lift
# wasn't using otherwise.
@export var jib_reach_m        : float = 3.0    # max horizontal arc reach
@export var jib_segment_m      : float = 1.7    # length of each of the two segments
@export var jib_fold_speed_1_s : float = 0.2    # slow hydraulic creep (operator: was way too fast)

# Slewing rotation around the mast's vertical axis (operator request). Rotates
# the entire jib + platform assembly about the mast top so the basket can swing
# left/right without driving the chassis. Z = rotate left, C = right (mapped
# via the existing forklift_rotator_left/right input actions — those keys are
# free on the mast lift's cab control set).
const SLEW_SPEED_RAD_S : float = 0.6              # ~35°/s, comfortable hydraulic feel
const SLEW_LIMIT_RAD   : float = PI               # ±180° travel (full swing)
var   _slew_angle      : float = 0.0              # current slew (radians)

# The jib's USABLE travel is a narrow band, not the full 0→1 swing. The full
# range threw the platform "up and over and back down the other side" — way too
# far. Rest at 10 % fold, and allow only ~1/3 of the total motion from there.
const JIB_FOLD_MIN : float = 0.10
const JIB_FOLD_MAX : float = 0.43   # ≈ 10 % + 1/3 of the range

## Hydraulic ramp time constants. Telescopic mast + counterweight: 0.4–0.8 s.
## Jib fold: slow hydraulic creep already by spec; small additional ramp keeps
## input flicks from snapping the cylinder. Slew: similar feel to jib fold.
const PLATFORM_RAMP_TAU_S : float = 0.60
const JIB_FOLD_RAMP_TAU_S : float = 0.50
const SLEW_RAMP_TAU_S     : float = 0.50

var _platform_height : float = 0.0
var _platform_base_y : float = 0.5   # saved from the .tscn on _ready
var _platform_velocity : SmoothedRate = null
var _jib_fold_velocity : SmoothedRate = null
var _slew_velocity     : SmoothedRate = null

# #147 Phase 3 — Autonomous control. When an NPC commands the lift, these are
# set; _physics_process drives _platform_height toward the target each tick at
# `platform_speed_m_s`. is_at_autonomous_target() returns true once we're inside
# AUTONOMOUS_TOL of the goal so the NPC planner can advance to the next step.
const AUTONOMOUS_TOL : float = 0.05
var _autonomous_target_active : bool = false
var _autonomous_target_local  : float = 0.0   # platform height in lift-local meters (0 = stowed)
var jib_fold         : float = JIB_FOLD_MIN   # rest at 10 %

# Node refs (resolved in _ready)
var _platform_node : Node3D = null
var _mast_stages   : Array[Node3D] = []   # moving telescoping sections, bottom→top
var _jib_root      : Node3D = null   # sits at mast top, rotates with JibLower
var _jib_lower     : Node3D = null   # first segment (visual)
var _jib_upper     : Node3D = null   # second segment, counter-rotates
var _jib_tip       : Node3D = null   # where the platform hangs from

# =============================================================================
func _ready() -> void:
	# Mast lift has NO running lights / hazards / reverse beam / blue spots —
	# real JLG mast lifts skip those because the body is short, the operator
	# is up on the platform, and the chassis can't reverse fast enough to
	# need a beeper. It DOES get a horn on the platform panel (N key) for
	# alerting ground crew that someone's working overhead.
	has_lights = false
	has_horn   = true
	# Drive-ramp tuning per the throttle/brake audit. JLG-style mast lifts are
	# deliberately the slowest movers — full throttle from the platform should
	# feel like a labored crawl. ~1.6 s to top speed (capped 12 km/h anyway),
	# 12 m/s² brake is softer than the rest of the fleet because the operator
	# stands on the platform and a jolt would be unpleasant.
	throttle_accel_mps2 = 2.0
	brake_decel_mps2    = 12.0
	coast_decel_mps2    = 3.0
	throttle_ramp_tau_s = 1.2
	brake_ramp_tau_s    = 0.3
	super._ready()
	vehicle_type = "mast_lift"   # JLG vertical-mast personnel lift
	fuel_type    = "electric"
	speed_limit_kmh = normal_speed_kmh
	accumulate_steering = true      # JLG manual steer: angle persists when keys released
	_setup_ground_panel_trigger()   # ground-rescue lower button on the chassis side

	_platform_node = get_node_or_null("Platform") as Node3D
	if _platform_node:
		_platform_base_y = _platform_node.position.y

	# Gather the moving mast stages in order: Mast/Stage1, Stage2, … (until missing).
	var mast := get_node_or_null("Mast")
	if mast:
		var i := 1
		while true:
			var s := mast.get_node_or_null("Stage%d" % i) as Node3D
			if s == null:
				break
			_mast_stages.append(s)
			i += 1

	# Build the folding jib at the top of the mast (procedurally — not in the
	# .tscn, so the geometry follows jib_segment_m even if the export changes).
	_build_jib()

	# Hydraulic ramp smoothers — telescopic mast + jib fold + slew. Keeps key
	# taps from snapping the cylinder from 0 to nominal velocity.
	_platform_velocity = SmoothedRateScript.new(0.0, PLATFORM_RAMP_TAU_S)
	_jib_fold_velocity = SmoothedRateScript.new(0.0, JIB_FOLD_RAMP_TAU_S)
	_slew_velocity     = SmoothedRateScript.new(0.0, SLEW_RAMP_TAU_S)

# =============================================================================
func _physics_process(delta: float) -> void:
	# Safety interlock: restrict travel speed while the platform is elevated.
	speed_limit_kmh = elevated_speed_kmh if _platform_height > elevated_threshold_m \
					else normal_speed_kmh
	super._physics_process(delta)
	if occupied:
		_update_platform(delta)
	# Ground rescue: while a player on foot is at the GroundPanel and holding E,
	# the platform lowers regardless of who's on it (the operator's R/F keyboard
	# only fires when occupied, so this can't fight that path).
	if _ground_panel_player_near and Input.is_action_pressed("interact"):
		_platform_height = maxf(0.0, _platform_height - GROUND_LOWER_RATE_M_S * delta)
	# #147 Phase 3 — autonomous lift target. When an NPC has commanded the lift
	# to a specific world-Y, drive _platform_height toward the equivalent local
	# height. Active regardless of `occupied` so an unoccupied lift can finish
	# returning to ground after its NPC operator dismounts.
	if _autonomous_target_active:
		_drive_autonomous_height(delta)
	_apply_platform_transforms()

# How hard the mast was working this frame (0..1), for the battery drain model.
var _lift_load : float = 0.0

func _update_platform(delta: float) -> void:
	# A flat battery can't raise the platform (it can still settle DOWN under its
	# own weight if it were modelled, but here it simply holds).
	if not _has_power():
		_lift_load = 0.0
		return
	# Mouse-as-joystick: hold LEFT and drag up/down to raise/lower the platform.
	var m := _tool_axes()
	var axis := Input.get_action_strength("forklift_lift_up") \
			  - Input.get_action_strength("forklift_lift_down")
	var target_plat_v : float = axis * platform_speed_m_s + float(m["b"]) * platform_speed_m_s * MOUSE_TOOL_MULT
	var cur_plat_v    : float = _platform_velocity.approach(target_plat_v, delta)
	_lift_load = clampf(absf(cur_plat_v) / maxf(platform_speed_m_s, 0.0001), 0.0, 1.0)
	_platform_height = clampf(_platform_height + cur_plat_v * delta, 0.0, platform_max_m)
	# JIB FOLD — extend/retract the basket out over the edge. T = out
	# (forklift_tilt_back), G = in (forklift_tilt_fwd); RIGHT-mouse drag up/down
	# also folds it. This was the missing control: jib_fold was never driven by
	# input, so T and RMB did nothing in-game (#12).
	var jaxis := Input.get_action_strength("forklift_tilt_back") \
			   - Input.get_action_strength("forklift_tilt_fwd")
	var target_jib_v : float = jaxis * jib_fold_speed_1_s + float(m["d"]) * jib_fold_speed_1_s * MOUSE_TOOL_MULT
	var cur_jib_v    : float = _jib_fold_velocity.approach(target_jib_v, delta)
	if absf(cur_jib_v) > 0.0001:
		jib_fold = clampf(jib_fold + cur_jib_v * delta, JIB_FOLD_MIN, JIB_FOLD_MAX)
		_lift_load = maxf(_lift_load, clampf(absf(cur_jib_v) / maxf(jib_fold_speed_1_s, 0.0001), 0.0, 1.0))
	# SLEW — Z rotates the jib LEFT, C rotates RIGHT. Clamped to ±π so the
	# basket can't wind around the mast endlessly.
	var slew_axis : float = Input.get_action_strength("forklift_rotator_left") \
						   - Input.get_action_strength("forklift_rotator_right")
	var target_slew_v : float = slew_axis * SLEW_SPEED_RAD_S
	var cur_slew_v    : float = _slew_velocity.approach(target_slew_v, delta)
	if absf(cur_slew_v) > 0.0001:
		_slew_angle = clampf(_slew_angle + cur_slew_v * delta,
			-SLEW_LIMIT_RAD, SLEW_LIMIT_RAD)
		_lift_load = maxf(_lift_load, clampf(absf(cur_slew_v) / SLEW_SPEED_RAD_S, 0.0, 1.0) * 0.4)
	# Apply slew rotation to the jib root every frame (platform follows via the
	# tip in _apply_jib_transforms; only the orientation has to be set here).
	if _jib_root:
		_jib_root.rotation.y = _slew_angle

## Raising the mast is the lift's heaviest electrical draw — report it so the
## drive battery drains faster while working up high.
func _extra_power_draw() -> float:
	return _lift_load

# =============================================================================
# MAST ANIMATION
# =============================================================================
## Move the platform to its height, then telescope each nested mast stage up a
## proportional fraction of that height. Stage k (1-indexed of n) slides to
## (k/n) × height, so the topmost stage tracks the platform and the lower stages
## nest progressively — the classic vertical-mast extension.
func _apply_platform_transforms() -> void:
	# 1) Telescoping mast: each stage slides up a proportional fraction of the
	#    platform height (top stage tracks the platform; lower stages nest below).
	var n := _mast_stages.size()
	if n > 0:
		for k in n:
			_mast_stages[k].position.y = _platform_height * float(k + 1) / float(n)
	# 2) Jib root sits at the mast TOP — its Y tracks the platform height plus
	#    the natural base offset (which is where the platform used to sit in the
	#    pre-jib model, so jib_fold=0 puts the platform at the same place it
	#    always was — visual continuity).
	if _jib_root:
		_jib_root.position.y = _platform_base_y + _platform_height
	# 3) Jib pivots + platform follows tip (see _apply_jib_transforms).
	_apply_jib_transforms()

# =============================================================================
# DISMOUNT — exit at platform height so the player lands on the deck, not the
# ground far below.
# =============================================================================
func get_dismount_position() -> Vector3:
	var base := global_position + global_transform.basis * dismount_offset
	base.y = global_position.y + _platform_base_y + _platform_height + 0.1
	return base

# =============================================================================
# #147 PHASE 3 — Autonomous height control (NPC mast-lift use)
# =============================================================================
## Where the platform's WALKING SURFACE sits in world Y right now. NPC planner
## uses this to decide if its operator can reach the target after the lift has
## raised the platform.
func current_platform_top_y() -> float:
	return global_position.y + _platform_base_y + _platform_height

## Maximum world Y a worker standing on this lift's platform can reach with
## arms extended (platform_top + standing reach). Used by the NPC planner to
## confirm the chosen lift can actually get the worker high enough; if not,
## the planner looks for a taller lift or aborts the task.
func max_reach_top_y(reach_height: float = 2.2) -> float:
	return global_position.y + _platform_base_y + platform_max_m + reach_height

## Command the lift to raise / lower until the platform top sits at
## `target_world_y`. The autonomous tick in _physics_process drives the
## existing `_platform_height` toward the equivalent local target at
## `platform_speed_m_s`, so all the existing visuals (telescoping stages,
## jib, ground panel) continue to work without a parallel code path.
func set_autonomous_target_top_world_y(target_world_y: float) -> void:
	var target_local : float = target_world_y - global_position.y - _platform_base_y
	_autonomous_target_local = clampf(target_local, 0.0, platform_max_m)
	_autonomous_target_active = true

## True once the platform has reached the autonomous target within tolerance.
## NPC planner advances to the next step on this returning true.
func is_at_autonomous_target() -> bool:
	if not _autonomous_target_active:
		return false
	return absf(_platform_height - _autonomous_target_local) <= AUTONOMOUS_TOL

## Release the autonomous lock — the lift becomes operator-driven again (or
## just holds height if unoccupied).
func release_autonomous_target() -> void:
	_autonomous_target_active = false

## Internal: per-tick drive toward _autonomous_target_local. Same speed as
## the operator's R/F keys.
func _drive_autonomous_height(delta: float) -> void:
	if not _has_power():
		return
	var diff : float = _autonomous_target_local - _platform_height
	if absf(diff) <= AUTONOMOUS_TOL:
		_platform_height = _autonomous_target_local
		return
	var step : float = platform_speed_m_s * delta
	if absf(diff) < step:
		_platform_height = _autonomous_target_local
	else:
		_platform_height += sign(diff) * step
