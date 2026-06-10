extends BaseVehicle

# The plant ran three JLG-style vertical-mast personnel lifts. "Mast lift" is
# the correct industry term — the script was originally called ScissorLift
# (and the vehicle_type string was "scissor_lift") in error. The class +
# vehicle_type are now "MastLift" / "mast_lift" everywhere; legacy save data
# carrying the old strings is migrated on load by WorldLayout, MapOverlay,
# VehicleEnterArea, and BaseVehicle.
class_name MastLift

## Ground rescue panel — a proximity Area3D around the GroundPanel mesh. While
## the player is on foot inside the zone, holding the interact key (E) LOWERS the
## platform. This is the safety feature the operator asked for: if someone gets
## a heart attack up top, anyone on the ground can bring them down.
var _ground_panel_player_near : bool = false
const GROUND_LOWER_RATE_M_S : float = 0.55

func _setup_ground_panel_trigger() -> void:
	var area := Area3D.new()
	area.name = "GroundPanelTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = 1.4
	cs.shape = sp
	cs.position = Vector3(0.86, 0.7, 0)   # by the GroundPanel mesh
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_ground_panel_body_entered)
	area.body_exited.connect(_on_ground_panel_body_exited)

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
# Orange-beam swing geometry (operator spec): the GRAY (steel, mast-side) beam
# stays perfectly VERTICAL — it's a plumb riser. The ORANGE (basket-side) beam
# carries ALL the rotation, swinging from straight-down (stowed → platform sits
# at the mast top) out toward horizontal-forward (extended → platform reaches
# out). Tunable so the swing can be dialled in after a visual check.
const JIB_ORANGE_STOW_RAD  : float = -PI        # straight down (tip meets the riser base)
const JIB_ORANGE_REACH_RAD : float = PI * 0.5   # how far it swings toward forward (90°)

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
## front raises a small work platform, with a rounded red battery/drive cowl at
## the rear.
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

# The jib's USABLE travel is a narrow band, not the full 0→1 swing. The full
# range threw the platform "up and over and back down the other side" — way too
# far. Rest at 10 % fold, and allow only ~1/3 of the total motion from there.
const JIB_FOLD_MIN : float = 0.10
const JIB_FOLD_MAX : float = 0.43   # ≈ 10 % + 1/3 of the range

var _platform_height : float = 0.0
var _platform_base_y : float = 0.5   # saved from the .tscn on _ready
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
	var move: float = axis * platform_speed_m_s * delta \
		+ float(m["b"]) * platform_speed_m_s * delta * MOUSE_TOOL_MULT
	_lift_load = clampf(absf(move) / maxf(platform_speed_m_s * delta, 0.0001), 0.0, 1.0)
	_platform_height = clampf(_platform_height + move, 0.0, platform_max_m)
	# JIB FOLD — extend/retract the basket out over the edge. T = out
	# (forklift_tilt_back), G = in (forklift_tilt_fwd); RIGHT-mouse drag up/down
	# also folds it. This was the missing control: jib_fold was never driven by
	# input, so T and RMB did nothing in-game (#12).
	var jaxis := Input.get_action_strength("forklift_tilt_back") \
			   - Input.get_action_strength("forklift_tilt_fwd")
	var jmove : float = jaxis * jib_fold_speed_1_s * delta \
		+ float(m["d"]) * jib_fold_speed_1_s * delta * MOUSE_TOOL_MULT
	if absf(jmove) > 0.0:
		jib_fold = clampf(jib_fold + jmove, JIB_FOLD_MIN, JIB_FOLD_MAX)
		_lift_load = maxf(_lift_load, clampf(absf(jmove) / maxf(jib_fold_speed_1_s * delta, 0.0001), 0.0, 1.0))

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
