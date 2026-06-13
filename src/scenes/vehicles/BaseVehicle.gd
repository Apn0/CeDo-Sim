extends VehicleBody3D

class_name BaseVehicle

## Common behaviour for every drivable vehicle: enter/exit lifecycle, fuel,
## handbrake, speed limiter, cab camera activation. Subclasses (Forklift,
## BaleClamp, Merlo) add their specific hydraulics on top.
##
## Configuration is exposed as @export so individual instances can be tuned
## in the inspector AND template values come from a VehicleConfig resource.

# ── Identity ──────────────────────────────────────────────────────────────────
@export var vehicle_type   : String = "base"   # overridden per subclass
@export var vehicle_id     : String = "vehicle_unset"  # unique scene-instance id

# ── Powertrain & limits ───────────────────────────────────────────────────────
@export_group("Powertrain")
@export_enum("lpg", "diesel", "electric") var fuel_type: String = "lpg"
@export var fuel_capacity_l    : float = 18.0       # LPG tank ~18 kg / forklift
@export var fuel_consumption_l_per_h : float = 2.0
@export var speed_limit_kmh    : float = 12.0
@export var engine_power_kw    : float = 25.0
@export var brake_torque_nm    : float = 2500.0
@export var handbrake_torque_nm: float = 5000.0

# ── Cab & camera ──────────────────────────────────────────────────────────────
@export_group("Cab")
@export var cab_camera_path    : NodePath
@export var dismount_offset    : Vector3 = Vector3(1.2, 0.0, 0.0)

@export_group("Load handling")
## Node3D at the business end of the tool (forks / between clamp plates / in the
## bucket). A grabbed bale is parented here and rides along.
@export var carry_point_path   : NodePath
## Position relative to vehicle origin where the operator capsule appears
## on dismount. Default = step off the right side.

# ── Runtime state ─────────────────────────────────────────────────────────────
var fuel_l            : float = 0.0

# LPG mount integration — physical cylinder swap (see LPGTank.gd). For
# forklifts there is ONE mount node ("LPG_Mount") and one tank. For bale
# clamps there are two ("LPG_Mount_0" + "LPG_Mount_1") and the operator
# picks the active feed with H. _active_lpg_tank is the one currently
# pushing gas into the engine.
var _active_lpg_tank   : Node3D = null
var _mounted_lpg_tanks : Array  = []   # Array[Node3D] — every mounted tank, in order
var _active_lpg_idx    : int    = 0

# ── Lights + audio aux (see _install_vehicle_aux below) ───────────────────────
# Subclasses override has_lights / has_horn before super._ready() runs:
#   MastLift  : has_lights = false, has_horn = true
#   everything else: defaults
@export var has_lights : bool = true
@export var has_horn   : bool = false

var work_lights_on    : bool = false       # L key — forward work lamps
var hazards_on        : bool = false       # K key — 4-way blinkers
var blinker_left_on   : bool = false
var blinker_right_on  : bool = false
var _light_work       : Array = []
var _light_haz        : Array = []         # OmniLight3D corners
var _light_rev        : SpotLight3D = null # reverse beam (auto)
var _light_blue_f     : SpotLight3D = null # Linde-style blue spot front
var _light_blue_r     : SpotLight3D = null # …and rear
var _beacons          : Array = []         # Rotating mini-lighthouse elements
var _haz_blink_t      : float = 0.0
var _haz_blink_on     : bool  = false

var _beeper         : AudioStreamPlayer3D = null
var _beeper_pb      : AudioStreamGeneratorPlayback = null
var _beeper_phase   : float = 0.0
var _beeper_time    : float = 0.0
# Per-vehicle reverse beep parameters (set in _install_vehicle_aux).
var _beep_tone_hz   : float = 880.0
var _beep_period_s  : float = 0.40
var _beep_on_ratio  : float = 0.5
# Bale-clamp double-beep pattern: second pulse offset within the period.
var _beep_double    : bool  = false

var _horn           : AudioStreamPlayer3D = null
var _horn_pb        : AudioStreamGeneratorPlayback = null
var _horn_active_t  : float = 0.0
var _horn_phase     : float = 0.0
const HORN_TONE_HZ  : float = 220.0
const HORN_DURATION : float = 0.45

# ── Electric drive battery (only meaningful when fuel_type == "electric") ──────
# A normalised 0..1 charge that depletes while the lift drives / raises, and is
# refilled by plugging into a wall power outlet (ServiceStation in "outlet" mode).
# A full pack lasts ~6 h of ACTIVE use; idling barely sips, so a parked machine
# holds charge for days. When flat, the machine won't drive or lift until charged.
const DRIVE_BATTERY_LIFE_S : float = 21600.0   # full→empty under continuous load
const DRIVE_CHARGE_S       : float = 10800.0   # empty→full on the outlet (~3 h)
var drive_charge      : float = 1.0
var _drive_low_emitted: bool  = false

# ── AdBlue / DEF (only for fuel_type == "diesel" — SCR exhaust treatment) ─────
# Diesel machines sip DEF at a few % of the diesel rate. Run dry and the engine
# DERATES (real SCR behaviour): power + speed are cut until it's topped up.
@export var adblue_capacity_l : float = 9.0
var adblue_l : float = 0.0

var handbrake_engaged : bool  = true   # safer default — must release to drive
var occupied          : bool  = false
var _operator         : OperatorContext = null
var _cab_camera       : Camera3D = null
# Multi-mode camera rig — 1st person (cab) / 3rd-person follow / world-orbit.
# F4 cycles modes, hold-F4 + arrows pans orbit, hold-F4 + scroll zooms.
# See CameraRig.gd. Replaces the old _chase_camera + _third_person bool.
var _camera_rig       : CameraRig = null

const CAB_CAMERA_DEBUG_STEP_M : float = 0.05
const CAB_CAMERA_OFFSETS_PATH : String = "user://vehicle_cab_camera_offsets.cfg"
var _cab_camera_debug_offset : Vector3 = Vector3.ZERO

const GRAB_RANGE      : float = 2.5       # m from the carry point to grab a bale
var _carried_bale     : Node3D = null
var _bale_orig_parent : Node = null

# Bales stacked ON TOP of the grabbed bale ride along too (pick up the bottom of a
# yard stack and the whole column comes with it). Parallel arrays: the carried
# stack and each bale's original parent so they can be put back on release.
var _carried_stack              : Array[Node3D] = []
var _carried_stack_orig_parents : Array[Node]   = []

## A bale counts as "stacked on" the grabbed one when it sits roughly in the same
## vertical column (within STACK_COLUMN_RADIUS laterally) and clearly above it.
const STACK_COLUMN_RADIUS : float = 0.75
const STACK_VERTICAL_GAP  : float = 0.30

## On-grab local Y per carried bale — the "natural" position the carry-point's
## transform would place it at. Each frame the load-collision clamp resets every
## carried bale to this before computing the upward push, so when an obstacle
## below is removed the bale drops back to its natural carry position.
var _carried_natural_local_y : Dictionary = {}

# Input axes (set each frame by _gather_input when occupied)
var _throttle: float = 0.0    # -1 reverse … +1 forward
var _steering: float = 0.0    # -1 left … +1 right
var _brake   : float = 0.0    # 0 … 1

# ── Mouse-as-joystick tool control ────────────────────────────────────────────
# While the operator is seated, holding a mouse button turns the mouse into a tool
# joystick instead of moving the camera:
#   • LEFT  held  → mouse X / Y drive tool functions A / B
#   • RIGHT held  → mouse X / Y drive tool functions C / D
#   • BOTH  held  → all four move together (one drag works the whole tool)
# Each subclass maps its hydraulics onto these four virtual axes. The relative
# mouse motion is accumulated here and CONSUMED once per physics frame by the
# subclass (consume = read-and-clear, so motion never double-applies or leaks).
var _lmb_held   : bool    = false
var _rmb_held   : bool    = false
var _mouse_left : Vector2 = Vector2.ZERO   # accumulated drag while LEFT is held
var _mouse_right: Vector2 = Vector2.ZERO   # accumulated drag while RIGHT is held

## Absolute throttle 0–1, updated every physics frame while occupied.
## Read by AudioManager to drive engine-pitch synthesis.
var engine_throttle: float = 0.0

# =============================================================================
func _ready() -> void:
	# Group membership: lets other systems (ChargingPlug, CrewManager, save
	# code) find every vehicle in one query instead of walking the scene tree.
	add_to_group("vehicle")
	# Any direct child Node3D whose name starts with "ToolSlot_" is a stowing
	# spot for inventory tools — register it in the "tool_slot" group so
	# ToolPlacementMode (G key) can snap to it.
	for c in get_children():
		if c is Node3D and c.name.begins_with("ToolSlot_"):
			c.add_to_group("tool_slot")
			# A cup-holder slot only accepts a coffee (the #162 accept filter).
			if "CupHolder" in c.name:
				c.set_meta("accepts", ["coffee"])
	# Spawn the initial LPG cylinder(s) at each LPG_Mount anchor — vehicles
	# spawn with a fresh tank attached so the operator doesn't start the shift
	# with an empty bracket. Deferred so the tree is ready before we mount.
	if fuel_type == "lpg":
		call_deferred("_spawn_initial_lpg_tanks")
	# Procedurally install work lights / hazards / reverse beam / blue safety
	# spots, plus the reverse beeper + (if has_horn) a panel horn. Per-vehicle
	# light positions + beep cadence keyed off `vehicle_type` so each rig
	# sounds and looks correct. Skipped entirely on no-lights machines (mast
	# lift), but the horn path still installs for those.
	call_deferred("_install_vehicle_aux")
	fuel_l = fuel_capacity_l
	drive_charge = 1.0                 # electric machines spawn fully charged
	adblue_l = adblue_capacity_l       # diesel machines spawn with a full DEF tank
	_ensure_cab_camera_debug_actions()
	if cab_camera_path:
		_cab_camera = get_node_or_null(cab_camera_path) as Camera3D
		if _cab_camera:
			_apply_saved_cab_camera_offset()
			_cab_camera.current = false
	# Camera rig — own camera is used by 3rd-person follow + orbit modes; the
	# cab camera (handed in via set_first_person_camera) is the 1st-person.
	_camera_rig = CameraRig.new()
	_camera_rig.name = "CameraRig"
	# Vehicles are bigger than the player capsule so push the follow camera
	# further back and higher.
	_camera_rig.orbit_default_dist  = 9.0
	_camera_rig.orbit_min_dist      = 3.0
	_camera_rig.orbit_max_dist      = 40.0
	add_child(_camera_rig)
	# Just store the cab-camera reference; do NOT activate. Unattended vehicles
	# must NOT grab the viewport on spawn — that was the bug that made every
	# spawned vehicle fight for the camera and left the player looking at the
	# Merlo's empty cab on game start.
	_camera_rig.set_first_person_camera(_cab_camera)

	# DRIVE FIX (the "vehicles stuck" bug): switch the vehicle to kinematic
	# freeze mode. VehicleBody3D inherits from RigidBody3D — the dynamic
	# wheel + suspension + friction integration was overriding the direct
	# linear_velocity assignment each physics step (no matter what we set
	# wheel_friction_slip to). FREEZE_MODE_KINEMATIC turns the body into a
	# kinematic mover: position/rotation can be set directly each frame and
	# the body still collides with the world (and pushes other RigidBody3Ds
	# like bales), but nothing in Godot's rigid-body integrator touches it.
	# Wheels stay attached for the visual roll + suspension-mesh dangle, they
	# just don't drive anything physically.
	freeze = true
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	can_sleep = false
	sleeping  = false

	# #22 — on vehicles flagged for it (the forklift), pull the wheel meshes out of the
	# NaN-prone VehicleWheel3D nodes so the renderer stops getting non-finite transforms.
	if detach_wheel_visuals:
		_detach_wheel_visuals()

# =============================================================================
# LIFECYCLE — called by OperatorContext
# =============================================================================
func on_operator_entered(operator: OperatorContext) -> void:
	_operator = operator
	occupied  = true
	handbrake_engaged = false   # operator releases the brake to pull away (else throttle is cut)
	# Platform rides (mast lift) let the player keep their own camera — they're
	# standing on the platform, not sitting in a cab. Cab vehicles take the
	# viewport so the player sees through the cab camera.
	if not is_platform_ride() and _camera_rig:
		_camera_rig.reset()
		_camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
		_camera_rig.activate()           # take the viewport from the player

# =============================================================================
# #148 PHASE 4 — NPC vehicle entry/exit parity with the player
# =============================================================================
# Vehicles already expose occupied / dismount_offset / cab_camera_path. For
# NPC parity we add a boarding-position getter (where they stop walking before
# they "sit down"), and on_npc_entered / on_npc_exited so the NPC parents under
# a SeatMarker (if present) and the vehicle's occupied flag flips like it does
# for the player. Doors that animate (MerloP40, the cars) expose
# request_door_open / close hooks; the NPC planner calls those when they exist
# so the boarding sequence reads as "walk up → door swings → climb in".

var _seated_npc : Node3D = null

## World position the NPC should walk to BEFORE the sit-down animation runs.
## Default: the dismount_offset point (driver-side step) — for most cars +
## forklift that's a metre to the LEFT of the cab. Vehicles can override.
func get_boarding_position() -> Vector3:
	var base : Vector3 = global_position + global_transform.basis * dismount_offset
	base.y = global_position.y
	return base

## NPC boarding — parents the NPC under a SeatMarker node if the vehicle has
## one, otherwise pins to the chassis origin. Flips occupied=true so passersby
## (and other NPC planners) see the vehicle as taken. Mirrors on_operator_entered
## minus the camera takeover (NPC drives blind for now; the operator can still
## board to override the camera).
func on_npc_entered(npc: Node3D) -> void:
	if npc == null:
		return
	_seated_npc = npc
	occupied = true
	handbrake_engaged = false
	# Reparent NPC under the seat marker (if any) so it rides with the chassis.
	var seat := get_node_or_null("SeatMarker") as Node3D
	var parent_node : Node3D = seat if seat != null else self
	if npc.get_parent():
		npc.get_parent().remove_child(npc)
	parent_node.add_child(npc)
	npc.transform = Transform3D.IDENTITY    # snap to seat origin

## NPC dismount — reverse of on_npc_entered. Reparents the NPC back to the
## scene root and drops them at dismount_offset (world space). Flips occupied=false.
func on_npc_exited(npc: Node3D) -> void:
	if npc == null:
		return
	if _seated_npc == npc:
		_seated_npc = null
	occupied = false
	_throttle = 0.0
	_steering = 0.0
	_brake    = 0.0
	handbrake_engaged = true
	# Reparent back to the world (scene root) at the dismount point.
	var root := get_tree().current_scene
	var dismount_pos : Vector3 = global_position + global_transform.basis * dismount_offset
	if npc.get_parent():
		npc.get_parent().remove_child(npc)
	if root != null:
		root.add_child(npc)
		npc.global_position = Vector3(dismount_pos.x,
			global_position.y, dismount_pos.z)

func on_operator_exited() -> void:
	_operator = null
	occupied  = false
	_throttle = 0.0
	_steering = 0.0
	_brake    = 0.0
	# Drop any held tool-joystick state so we don't resume mid-drag next time.
	_lmb_held = false
	_rmb_held = false
	_mouse_left = Vector2.ZERO
	_mouse_right = Vector2.ZERO
	handbrake_engaged = true   # always re-engage on exit
	# Release the viewport. OperatorContext.activate_camera() then re-arms the
	# player's rig in first-person, so the player sees their head camera again.
	# Platform rides never took the viewport, so there's nothing to release —
	# avoid calling deactivate (which would needlessly toggle the player's cam).
	if _camera_rig and not is_platform_ride():
		_camera_rig.deactivate()

func _unhandled_input(event: InputEvent) -> void:
	if not occupied:
		return
	# Tool-joystick: track LMB/RMB and, while held, route mouse drag to the tool
	# accumulators instead of the camera (handled in _track_tool_mouse).
	if _track_tool_mouse(event):
		return
	# Mouse look — only when NOT working the tool.
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if _camera_rig:
			_camera_rig.handle_mouse_look((event as InputEventMouseMotion).relative)
		return
	# Cab-camera seat debugger: nudge the first-person cab viewpoint with numpad
	# keys and persist the offset to user:// so the tested correction can be baked
	# into the scene later.
	if _handle_cab_camera_debug_input(event):
		get_viewport().set_input_as_handled()
		return
	# Camera rig (F4 cycle / hold-F4 + arrows / hold-F4 + scroll).
	if _camera_rig and _camera_rig.handle_input(event):
		get_viewport().set_input_as_handled()
		return
	# Legacy [P] toggle — keeps cycling the same modes.
	if event.is_action_pressed("camera_toggle"):
		_camera_rig.cycle_mode()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("forklift_forks_pinch"):   # close the tool → grab
		_try_grab()
	elif event.is_action_pressed("forklift_forks_widen"):   # open the tool → release
		_release()
	# L = work lights, K = 4-way hazards. Cheap toggles — every vehicle that
	# has lights honours them; mast lift just doesn't build the lights array
	# so the flag flips but nothing visible changes.
	elif event.is_action_pressed("vehicle_lights"):
		work_lights_on = not work_lights_on
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vehicle_hazards"):
		hazards_on = not hazards_on
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vehicle_blinker_left"):
		blinker_left_on = not blinker_left_on
		if blinker_left_on:
			blinker_right_on = false
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("vehicle_blinker_right"):
		blinker_right_on = not blinker_right_on
		if blinker_right_on:
			blinker_left_on = false
		get_viewport().set_input_as_handled()
	# N = horn. Only vehicles with has_horn=true (mast lift) actually
	# synthesise sound; everywhere else this is a no-op.
	elif event.is_action_pressed("vehicle_horn"):
		if has_horn:
			honk()
			get_viewport().set_input_as_handled()

# =============================================================================
# CAB CAMERA DEBUG POSITIONING
# =============================================================================
## Numpad 8/2/4/6/9/3 nudges the occupied cab camera in the driver's local
## forward/back/left/right/up/down axes. The accumulated per-vehicle-type offset
## is saved to user://vehicle_cab_camera_offsets.cfg and printed after each nudge
## so a manually tested correction can be baked into the .tscn later.
func _ensure_cab_camera_debug_actions() -> void:
	var binds := {
		"cab_cam_forward":  KEY_KP_8,
		"cab_cam_back":     KEY_KP_2,
		"cab_cam_left":     KEY_KP_4,
		"cab_cam_right":    KEY_KP_6,
		"cab_cam_up":       KEY_KP_9,
		"cab_cam_down":     KEY_KP_3,
	}
	for action_name in binds:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var key_code: int = binds[action_name]
		var has_key := false
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey and (ev as InputEventKey).keycode == key_code:
				has_key = true
				break
		if not has_key:
			var k := InputEventKey.new()
			k.keycode = key_code as Key
			InputMap.action_add_event(action_name, k)

func _handle_cab_camera_debug_input(event: InputEvent) -> bool:
	if not occupied or _cab_camera == null or is_platform_ride():
		return false
	var cam_basis := _cab_camera_debug_basis()
	var dir := Vector3.ZERO
	if event.is_action_pressed("cab_cam_forward"):
		dir += -cam_basis.z
	elif event.is_action_pressed("cab_cam_back"):
		dir += cam_basis.z
	elif event.is_action_pressed("cab_cam_left"):
		dir += -cam_basis.x
	elif event.is_action_pressed("cab_cam_right"):
		dir += cam_basis.x
	elif event.is_action_pressed("cab_cam_up"):
		dir += cam_basis.y
	elif event.is_action_pressed("cab_cam_down"):
		dir += -cam_basis.y
	else:
		return false
	_nudge_cab_camera_debug(dir.normalized() * CAB_CAMERA_DEBUG_STEP_M)
	return true

func _cab_camera_debug_basis() -> Basis:
	if _camera_rig and _camera_rig.has_method("first_person_base_basis"):
		return _camera_rig.call("first_person_base_basis") as Basis
	return _cab_camera.transform.basis

func _nudge_cab_camera_debug(delta_local: Vector3) -> void:
	_cab_camera_debug_offset += delta_local
	if _camera_rig and _camera_rig.has_method("nudge_first_person_base"):
		_camera_rig.call("nudge_first_person_base", delta_local)
	else:
		_cab_camera.position += delta_local
	_save_cab_camera_offset()
	print("[CabCameraDebug] %s offset=%s position=%s saved=%s" % [
		_cab_camera_offset_key(),
		_vec3_str(_cab_camera_debug_offset),
		_vec3_str(_cab_camera.position),
		CAB_CAMERA_OFFSETS_PATH,
	])

func _apply_saved_cab_camera_offset() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CAB_CAMERA_OFFSETS_PATH) != OK:
		return
	var value = cfg.get_value("cab_camera_offsets", _cab_camera_offset_key(), Vector3.ZERO)
	if value is Vector3:
		_cab_camera_debug_offset = value
		_cab_camera.position += _cab_camera_debug_offset
		print("[CabCameraDebug] loaded %s offset=%s from %s" % [
			_cab_camera_offset_key(),
			_vec3_str(_cab_camera_debug_offset),
			CAB_CAMERA_OFFSETS_PATH,
		])

func _save_cab_camera_offset() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CAB_CAMERA_OFFSETS_PATH)
	cfg.set_value("cab_camera_offsets", _cab_camera_offset_key(), _cab_camera_debug_offset)
	var err := cfg.save(CAB_CAMERA_OFFSETS_PATH)
	if err != OK:
		push_warning("[CabCameraDebug] Could not save %s (error %d)" % [CAB_CAMERA_OFFSETS_PATH, err])

func _cab_camera_offset_key() -> String:
	return vehicle_type if vehicle_type != "" else String(name)

func _vec3_str(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]

# =============================================================================
# BALE PICKUP / CARRY / DROP
# =============================================================================
func _carry_point() -> Node3D:
	if carry_point_path:
		var n := get_node_or_null(carry_point_path) as Node3D
		if n:
			return n
	return self

func _try_grab() -> void:
	if _carried_bale != null:
		return
	var cp := _carry_point()
	# Closest bale or skip to the carry point, within reach. Skips (movable waste
	# containers with forklift pockets) use the same grab/carry/drop plumbing as
	# bales — the forklift just lifts whatever heavy thing is in its forks.
	var best : Node3D = null
	var best_d := GRAB_RANGE

	# Use a physics shape query to find nearby items instead of iterating the entire scene
	var space_state := cp.get_world_3d().direct_space_state
	if space_state:
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = GRAB_RANGE
		query.shape = sphere
		query.transform = Transform3D(Basis(), cp.global_position)
		query.collision_mask = 0xFFFFFFFF # Match all collision layers

		var results := space_state.intersect_shape(query)
		for res in results:
			var collider := res.collider as Node3D
			if collider == null:
				continue

			var is_bale := collider.is_in_group("bale")
			var is_movable_container := collider.is_in_group("waste_container") and bool(collider.get("movable"))

			if is_bale or is_movable_container:
				var d := collider.global_position.distance_to(cp.global_position)
				if d < best_d:
					best_d = d
					best = collider
	if best == null:
		return
	# Pick up the bottom of a yard stack: collect every bale resting above it in
	# the same column. Subclasses can VETO the whole grab (e.g. the bale clamp
	# refuses if the operator isn't squeezing hard enough for this stack height).
	var stack := _find_stack_above(best)
	if not _can_grab_stack(best, stack):
		_on_grab_refused(best, stack)
		return
	# Latch the primary bale onto the tool.
	_carried_bale = best
	_bale_orig_parent = best.get_parent()
	best.set_meta("delivered", false)        # carried bales don't feed the line
	_set_bale_grabbed(best, true)
	_reparent_keep_world(best, cp)
	# Capture the on-grab LOCAL Y so the positional collision-clamp can reset to
	# this every frame before computing the upward push (so the bale drops back to
	# its natural carry-point position when an obstacle is removed).
	_carried_natural_local_y[best.get_instance_id()] = best.position.y
	# Latch each stacked bale, PRESERVING its offset above the primary bale so the
	# column rides intact instead of collapsing onto the carry point.
	_carried_stack.clear()
	_carried_stack_orig_parents.clear()
	for sb in stack:
		_carried_stack.append(sb)
		_carried_stack_orig_parents.append(sb.get_parent())
		sb.set_meta("delivered", false)
		_set_bale_grabbed(sb, true)
		_reparent_keep_world(sb, cp)
		_carried_natural_local_y[sb.get_instance_id()] = sb.position.y
	_on_grabbed(best, stack)

func _release() -> void:
	_on_pre_release()
	if _carried_bale == null:
		return
	# Drop the stacked bales first (top of the pile), then the primary, each back
	# at its current world position and settled onto whatever is below.
	for i in _carried_stack.size():
		var sb := _carried_stack[i] as Node3D
		if sb == null or not is_instance_valid(sb):
			continue
		var dest_s : Node = _carried_stack_orig_parents[i] \
			if (i < _carried_stack_orig_parents.size() and _carried_stack_orig_parents[i] \
				and is_instance_valid(_carried_stack_orig_parents[i])) \
			else get_tree().current_scene
		_drop_bale(sb, dest_s)
	_carried_stack.clear()
	_carried_stack_orig_parents.clear()

	var b := _carried_bale
	var dest : Node = _bale_orig_parent if (_bale_orig_parent and is_instance_valid(_bale_orig_parent)) else get_tree().current_scene
	_drop_bale(b, dest)
	_carried_bale = null
	_bale_orig_parent = null
	_carried_natural_local_y.clear()
	_on_released()

## Reparent a bale under `dest` keeping its world transform, mark it delivered,
## un-grab it, and settle it onto the floor below.
func _drop_bale(b: Node3D, dest: Node) -> void:
	_reparent_keep_world(b, dest)
	_set_bale_grabbed(b, false)
	b.set_meta("delivered", true)            # a dropped bale will feed a feed machine it's near
	# Skip dump check — if this is a movable WasteContainer dropped inside a
	# "dump_zone" marker, empty it (the forklift tipped it out at the tip zone).
	if b.is_in_group("waste_container") and b.has_method("empty"):
		var zone := _dump_zone_at(b.global_position)
		if zone != null:
			var dumped: float = b.call("empty")
			print("[Dump] Skip emptied %.0f kg at %s" % [dumped, zone.name])
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var from := b.global_position + Vector3.UP * 0.3
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3.DOWN * 25.0)
	var excl: Array = [get_rid()]
	if b is PhysicsBody3D:
		excl.append((b as PhysicsBody3D).get_rid())
	q.exclude = excl
	var hit := space.intersect_ray(q)
	if hit:
		b.global_position.y = (hit["position"] as Vector3).y

## Reparent `bale` under `new_parent` while preserving its global transform — so
## stacked bales keep their height offset above the one in the tool.
func _reparent_keep_world(bale: Node3D, new_parent: Node) -> void:
	var world_xf := bale.global_transform
	if bale.get_parent():
		bale.get_parent().remove_child(bale)
	new_parent.add_child(bale)
	bale.global_transform = world_xf

## Every bale resting in the same vertical column as `base` and clearly above it,
## sorted bottom-up. This is what lets a vehicle lift the bottom bale of a stack
## and bring the 2-3 above it along.
func _find_stack_above(base: Node3D) -> Array[Node3D]:
	var result : Array[Node3D] = []
	var bp := base.global_position
	for b in get_tree().get_nodes_in_group("bale"):
		var bn := b as Node3D
		if bn == null or bn == base:
			continue
		var dp := bn.global_position - bp
		if Vector2(dp.x, dp.z).length() > STACK_COLUMN_RADIUS:
			continue                    # different column
		if dp.y <= STACK_VERTICAL_GAP:
			continue                    # not above
		result.append(bn)
	result.sort_custom(func(a: Node3D, c: Node3D) -> bool:
		return a.global_position.y < c.global_position.y)
	return result

# =============================================================================
# CARRIED-LOAD COLLISION CLAMP
# =============================================================================
## Each frame, push any carried bale UP relative to the carry point if it would
## clip into something below. Kinematic-vs-kinematic collision in Godot doesn't
## stop the moving body, so we do it positionally — that's what makes a lowered
## bale visually REST ON a stacked bale instead of sinking straight through it.
##
## How: 1) reset every carried bale to its on-grab natural local Y (so the clamp
## re-solves fresh each frame), 2) raycast straight down from the LOWEST carried
## bale's centre, 3) if the bale's bottom would be below the obstacle's top, push
## the entire stack up by that penetration depth.
func _clamp_carried_against_obstacles() -> void:
	if _carried_bale == null:
		return
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	# Build the full list of carried bodies (primary + stack).
	var all_carried : Array[Node3D] = [_carried_bale]
	for sb in _carried_stack:
		if sb != null and is_instance_valid(sb):
			all_carried.append(sb)
	# 1) Reset to natural local Y so the clamp is recomputed cleanly every frame.
	for b in all_carried:
		var key := b.get_instance_id()
		if _carried_natural_local_y.has(key):
			b.position.y = _carried_natural_local_y[key]
	# 2) Find the LOWEST carried bale — that's the one whose bottom hits an
	#    obstacle first when the carrier lowers the load.
	var lowest := all_carried[0]
	for b in all_carried:
		if b.global_position.y < lowest.global_position.y:
			lowest = b
	# 3) Probe straight down from a hair above the bale's TOP, deep enough to
	#    catch obstacles within reach. Exclude the vehicle + every carried body
	#    (we don't want to "hit ourselves" with the carried stack).
	var sz := _carry_size(lowest)
	var bottom_y := lowest.global_position.y - sz.y * 0.5
	var start := lowest.global_position + Vector3.UP * (sz.y * 0.5 + 0.05)
	var probe := PhysicsRayQueryParameters3D.create(start, start + Vector3.DOWN * 6.0)
	var excl : Array = [get_rid()]
	for b in all_carried:
		if b is PhysicsBody3D:
			excl.append((b as PhysicsBody3D).get_rid())
	probe.exclude = excl
	var hit := space.intersect_ray(probe)
	if hit.is_empty():
		return
	var obstacle_top_y : float = (hit["position"] as Vector3).y
	var lift_needed := obstacle_top_y - bottom_y
	if lift_needed <= 0.0:
		return   # already above the obstacle — nothing to push
	# 4) Push every carried bale up by the same amount so the stack stays intact.
	#    (Local Y, since carried bales are parented under the carry point and we
	#    care about the vertical world axis — small mast tilts are negligible.)
	for b in all_carried:
		b.position.y += lift_needed

## A box collision shape's size (m), or Vector3.ONE if the body has no BoxShape.
## Local helper so BaseVehicle doesn't depend on BaleClamp's identical _bale_size.
func _carry_size(b: Node3D) -> Vector3:
	for c in b.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	return Vector3.ONE

## A dump zone is any Node3D in the "dump_zone" group within DUMP_RADIUS of `pos`.
## When a skip is dropped inside one it empties — the operator tipped its load out.
const DUMP_RADIUS : float = 4.0
func _dump_zone_at(pos: Vector3) -> Node3D:
	for z in get_tree().get_nodes_in_group("dump_zone"):
		var zn := z as Node3D
		if zn == null:
			continue
		if zn.global_position.distance_to(pos) <= DUMP_RADIUS:
			return zn
	return null

# ── Overridable grab hooks (BaleClamp uses these for the force gate + sheets) ──
## Return false to refuse the grab. Default: always allow.
func _can_grab_stack(_primary: Node3D, _stack: Array[Node3D]) -> bool:
	return true
## Called when a grab is refused (e.g. give the bale a nudge). Default: nothing.
func _on_grab_refused(_primary: Node3D, _stack: Array[Node3D]) -> void:
	pass
## Called after a successful grab. Default: nothing.
func _on_grabbed(_primary: Node3D, _stack: Array[Node3D]) -> void:
	pass
## Called at the very start of _release, before the early-out. Default: nothing.
func _on_pre_release() -> void:
	pass
## Called after everything has been dropped. Default: nothing.
func _on_released() -> void:
	pass

## Toggle a bale's "grabbed" state. Bales are RigidBody3D — when grabbed they
## freeze (becoming kinematic so the carry-point parent drags them along) and
## drop their collision layer so they don't push the vehicle around. When let
## go, they unfreeze and re-collide with the world. StaticBody3D bales (legacy
## save data) take the old collision-toggle path.
func _set_bale_grabbed(b: Node3D, grabbed: bool) -> void:
	# LOD upgrade: yard bales spawn as a cheap single-box model; the moment one is
	# grabbed, build its full sheet/wire detail so cutting + the film-pile work.
	if grabbed and b != null and b.has_meta("simple_bale"):
		PlaceableCatalog.detail_bale(b)
	if b is RigidBody3D:
		var rb := b as RigidBody3D
		rb.freeze = grabbed
		rb.sleeping = grabbed
		rb.linear_velocity = Vector3.ZERO
		rb.angular_velocity = Vector3.ZERO
		rb.collision_layer = 0 if grabbed else 1
		rb.collision_mask  = 0 if grabbed else 1
	elif b is StaticBody3D:
		var sb := b as StaticBody3D
		sb.collision_layer = 1 if not grabbed else 0
		sb.collision_mask  = 1 if not grabbed else 0

## Crosshair interaction protocol used by PlayerController. VehicleEnterArea still
## decides whether the cab is reachable; the player must also look at the vehicle.
func crosshair_prompt(_player: Node3D) -> String:
	var op_ctx := _operator_context()
	if op_ctx == null or op_ctx.get("current_mode") != "on_foot" or op_ctx.get("interactable_vehicle") != self:
		return ""
	if has_method("can_enter") and not can_enter():
		var reason := enter_refusal_reason() if has_method("enter_refusal_reason") else "Cannot enter right now"
		return reason if reason != "" else "Cannot enter right now"
	return "Enter %s" % _pretty_vehicle_type()

func crosshair_interact(_player: Node3D) -> void:
	var op_ctx := _operator_context()
	if op_ctx != null and op_ctx.has_method("enter_interactable_vehicle"):
		op_ctx.call("enter_interactable_vehicle", self)

func _operator_context() -> Node:
	var nodes := get_tree().get_nodes_in_group("operator_context")
	return nodes[0] if not nodes.is_empty() else null

func _pretty_vehicle_type() -> String:
	match vehicle_type:
		"forklift": return "forklift"
		"bale_clamp": return "bale clamp"
		"merlo", "merlo_p40": return "Merlo"
		"mast_lift", "scissor_lift": return "mast lift"   # legacy alias preserved
		_: return vehicle_type.capitalize().replace("_", " ")

func can_exit() -> bool:
	# In kinematic-drive mode linear_velocity isn't a meaningful speed signal;
	# use the runtime forward-speed value instead.
	return absf(_current_speed_mps) < 0.3   # ~stationary to dismount

## Can the player BOARD this vehicle right now? Default: always. The mast lift
## overrides this to refuse boarding while the platform is raised — without it
## the boarding code teleports the player up onto the deck (the bug the operator
## reported). The mast lift must be lowered from the GROUND control panel first.
## Ownership is a PRIORITY TAG, not a lock. A feeder's clamp/Merlo is "theirs"
## by default, but anyone (player or another NPC) may still board it — locking a
## vehicle would be catastrophic: if its owner is on a 30-min break and no other
## machine is free, the belt starves → shredder starves → wash line → extruder
## stalls → money burned. So can_enter() stays TRUE; the tag only drives "prefer
## your own vehicle, fall back to any free one" logic in the feeder AI.
var npc_owned      : bool   = false
var npc_owner_name : String = ""

func can_enter() -> bool:
	return true

# =============================================================================
# NPC AUTOPILOT — a FeederWorker drives its vehicle here (kinematic, waypoint).
# =============================================================================
var npc_autopilot      : bool    = false
var _npc_target        : Vector3 = Vector3.ZERO
var _npc_target_active : bool    = false
const NPC_ARRIVE_TOL   : float   = 2.2     # m — "close enough" to the waypoint
const NPC_TURN_RATE    : float   = 1.8     # rad/s yaw slew toward the heading
const NPC_CRUISE_FRAC  : float   = 0.55    # fraction of speed_limit the AI cruises at

## Point the vehicle at a world position and start driving there.
func npc_set_target(p: Vector3) -> void:
	_npc_target = p
	_npc_target_active = true
	npc_autopilot = true

## Stop driving (hold position).
func npc_stop() -> void:
	_npc_target_active = false

## True once we're within NPC_ARRIVE_TOL of the active waypoint (XZ).
func npc_arrived() -> bool:
	if not _npc_target_active:
		return true
	var a := global_position; a.y = 0.0
	var b := _npc_target;     b.y = 0.0
	return a.distance_to(b) <= NPC_ARRIVE_TOL

## Per-frame AI driving: yaw toward the target (rate-limited), set forward speed
## scaled by how well we're facing it + how close we are. _kinematic_move (called
## right after, with _steering = 0) does the actual swept translation + collision.
func _npc_drive(delta: float) -> void:
	_steering = 0.0
	var to := _npc_target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= NPC_ARRIVE_TOL:
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, DRIVE_ACCEL * 4.0 * delta)
		return
	# Forward is +basis.z; in Godot basis.z = (sinθ, 0, cosθ) for a Y-rotation θ.
	# So the yaw that points basis.z along `to` is atan2(to.x, to.z).
	var desired_yaw := atan2(to.x, to.z)
	rotation.y = _approach_angle(rotation.y, desired_yaw, NPC_TURN_RATE * delta)
	# Speed scales with alignment (don't barrel forward while still turning).
	var yaw_err := _angle_diff(rotation.y, desired_yaw)
	var align : float = clampf(cos(yaw_err), 0.0, 1.0)
	var cruise := (speed_limit_kmh / 3.6) * NPC_CRUISE_FRAC * _power_factor()
	var tgt_speed := cruise * align
	if dist < 4.0:
		tgt_speed *= clampf(dist / 4.0, 0.25, 1.0)   # ease in to the waypoint
	_current_speed_mps = move_toward(_current_speed_mps, tgt_speed, DRIVE_ACCEL * delta)

## Smallest signed difference a→b, wrapped to [-PI, PI].
func _angle_diff(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)

## Move `from` toward `to` by at most `step` radians (shortest way around).
func _approach_angle(from: float, to: float, step: float) -> float:
	var d := _angle_diff(from, to)
	if absf(d) <= step:
		return to
	return from + signf(d) * step

## NPC clamps a bale onto its carry point (bypasses the player grab minigame).
func npc_carry_bale(bale: Node3D) -> void:
	if bale == null:
		return
	if bale is RigidBody3D:
		(bale as RigidBody3D).freeze = true
	if bale is CollisionObject3D:
		(bale as CollisionObject3D).collision_layer = 0
		(bale as CollisionObject3D).collision_mask  = 0
	var cp := _carry_point()
	if bale.get_parent():
		bale.get_parent().remove_child(bale)
	cp.add_child(bale)
	bale.transform = Transform3D.IDENTITY
	_carried_bale = bale

## Hand the carried bale back to the world at a target transform (for the belt).
func npc_release_bale() -> Node3D:
	var b := _carried_bale
	_carried_bale = null
	return b

## True when "boarding" means the operator STANDS on a moving platform rather
## than sits in a cab — for these vehicles OperatorContext keeps the player
## capsule visible + active and parents it to a ride node (see `platform_node()`),
## so WASD / jump / crouch / mouse-look all keep working while the platform moves.
## Default false (every cab vehicle). The JLG mast lift overrides to true.
func is_platform_ride() -> bool:
	return false

## For platform-ride vehicles, the Node3D the player should be parented to (so the
## player rides with it). Default null. Mast lift returns its Platform node.
func platform_node() -> Node3D:
	return null

## Short human reason for refusal — shown as the interaction prompt while the
## player is in range and the vehicle is refusing entry. Default: empty.
func enter_refusal_reason() -> String:
	return ""

## Public speed accessor — m/s. HUD reads this for the km/h readout.
func get_speed_mps() -> float:
	return absf(_current_speed_mps)

func get_dismount_position() -> Vector3:
	return global_position + global_transform.basis * dismount_offset

# =============================================================================
# MOUSE-AS-JOYSTICK — shared tool control plumbing
# =============================================================================
## Subclasses that OVERRIDE _unhandled_input (Forklift, BaleClamp) call this first
## so the tool-joystick buttons + drag are tracked uniformly. Returns true if the
## event was a tool-mouse motion that should NOT fall through to the camera.
func _track_tool_mouse(event: InputEvent) -> bool:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_lmb_held = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			_rmb_held = mb.pressed
		return false
	if event is InputEventMouseMotion and (_lmb_held or _rmb_held) \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel := (event as InputEventMouseMotion).relative
		if _lmb_held:
			_mouse_left += rel
		if _rmb_held:
			_mouse_right += rel
		return true
	return false

## Read-and-clear the accumulated LEFT-drag (pixels) since the last call.
func _consume_left_drag() -> Vector2:
	var v := _mouse_left
	_mouse_left = Vector2.ZERO
	return v

## Read-and-clear the accumulated RIGHT-drag (pixels) since the last call.
func _consume_right_drag() -> Vector2:
	var v := _mouse_right
	_mouse_right = Vector2.ZERO
	return v

## True while either tool-joystick button is held (so subclasses can suppress the
## keyboard hydraulics conflicting, if they want, and the HUD can show a hint).
func tool_mouse_active() -> bool:
	return occupied and (_lmb_held or _rmb_held)

## Pixels of mouse drag → joystick axis units, PER PHYSICS FRAME. Tuned for the
## rate model below: ~22 px of drag in a frame = full deflection (a brisk drag),
## so a steady drag holds the stick near full while a gentle drag is proportional.
const TOOL_MOUSE_SENS : float = 1.0 / 22.0

## How much faster than the keyboard a fully-deflected mouse drag drives a tool.
## The mouse term is applied as a RATE (× delta), exactly like holding the key —
## NOT as an instant position jump — so a fast flick can't teleport the tool.
const MOUSE_TOOL_MULT : float = 3.0

## Consume this frame's drags and return the four virtual tool axes, each clamped
## to roughly [-1, 1] per frame's worth of motion:
##   a = LEFT-drag X      b = LEFT-drag Y (screen-up = +, so we invert)
##   c = RIGHT-drag X     d = RIGHT-drag Y (inverted)
## Subclasses map these onto their hydraulics. Both buttons held → all four are
## live at once (one combined drag works the whole tool), exactly as requested.
func _tool_axes() -> Dictionary:
	var l := _consume_left_drag()  * TOOL_MOUSE_SENS
	var r := _consume_right_drag() * TOOL_MOUSE_SENS
	return {
		"a": clampf( l.x, -1.0, 1.0),
		"b": clampf(-l.y, -1.0, 1.0),   # screen-up is negative Y → push-up = positive
		"c": clampf( r.x, -1.0, 1.0),
		"d": clampf(-r.y, -1.0, 1.0),
	}

# =============================================================================
# DRIVING (run only when occupied)
# =============================================================================
const DRIVE_ACCEL : float = 8.0    # m/s² toward target speed
const TURN_RATE   : float = 1.6    # rad/s yaw at full steer

# Kinematic-drive runtime state — _current_speed is the body's actual forward
# speed, tracked frame-to-frame because freeze=true means linear_velocity is no
# longer meaningful for movement (only contact response).
var _current_speed_mps : float = 0.0
var _last_good_xf : Transform3D = Transform3D.IDENTITY   # NaN-transform watchdog
var _xf_warned : bool = false

func _physics_process(delta: float) -> void:
	# ROOT FIX (NaN flood): kill the unused VehicleWheel3D sim on the first tick,
	# after every subclass _ready has finished arranging wheel children.
	if not _wheels_neutralized:
		_wheels_neutralized = true
		_neutralize_vehicle_wheels()
	# NaN-transform watchdog: if the physics ever drives this body to a non-finite
	# transform — the renderer's `instance_set_transform "!is_finite"` spam, which also
	# corrupts a feeder riding in the cab — snap back to the last good pose, kill the
	# velocities, and report it ONCE so the real source can be traced.
	if global_transform.is_finite():
		_last_good_xf = global_transform
	else:
		if not _xf_warned:
			_xf_warned = true
			push_warning("[Vehicle %s] caught + reset a NON-FINITE transform" % str(vehicle_id))
		global_transform = _last_good_xf
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_current_speed_mps = 0.0
		return
	if occupied:
		_gather_input()
		_drive(delta)
		_consume_fuel(delta)
	elif npc_autopilot and _npc_target_active:
		# Driven by a FeederWorker (or any NPC) toward a waypoint — same kinematic
		# mover the player uses, just with an AI setting speed + heading.
		_npc_drive(delta)
		_consume_fuel(delta)
	else:
		# Parked — coast to a stop on the horizontal axis, gravity still applies
		# via the kinematic move below (we always test a small downward step).
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, DRIVE_ACCEL * delta)
	_kinematic_move(delta)
	# Lights + reverse beeper + horn audio fill. Runs both occupied + parked
	# (a vehicle rolling backward down a slope still needs the beeper).
	_tick_vehicle_aux(delta)

## Direct kinematic drive — sets _current_speed_mps (forward speed along
## global_transform.basis.z) and a yaw rate based on throttle + steering.
## Body movement happens in _kinematic_move, which both vehicles and parked
## bodies call so the gravity tick stays in one place.
func _drive(delta: float) -> void:
	# Out of energy (flat battery / empty tank) → no drive, just coast to a stop.
	if not _has_power():
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, DRIVE_ACCEL * delta)
		_rotate_steered_wheel_meshes(delta)
		return
	# Foot brake — when no throttle is held but the brake action is down, the
	# vehicle decelerates faster than coasting.
	var accel := DRIVE_ACCEL
	if handbrake_engaged or absf(_throttle) < 0.01:
		# Coast / brake to 0
		var decel := DRIVE_ACCEL * (3.0 if handbrake_engaged or _brake > 0.1 else 1.0)
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, decel * delta)
	else:
		# Max speed is derated when the DEF tank is dry (diesel SCR limp-home).
		var max_mps := (speed_limit_kmh / 3.6) * _power_factor()
		var target_speed := _throttle * max_mps
		_current_speed_mps = move_toward(_current_speed_mps, target_speed, accel * delta)
	_rotate_steered_wheel_meshes(delta)

## Apply the frame's translation + yaw + a downward gravity probe. Runs whether
## occupied or not so a parked vehicle still rests on the floor instead of
## floating where it spawned.
func _kinematic_move(delta: float) -> void:
	var fwd := global_transform.basis.z
	# Steering — only effective while rolling (no in-place pivots)
	var max_mps := speed_limit_kmh / 3.6
	var steer_scale := clampf(absf(_current_speed_mps) / maxf(max_mps, 0.01), 0.0, 1.0)
	var dir_sign := 1.0 if _current_speed_mps >= 0.0 else -1.0
	var yaw_rate := -_steering * TURN_RATE * steer_scale * dir_sign
	# Horizontal motion — SWEPT, not teleported, so the chassis collides with and
	# slides along static geometry (machines, the bunker, walls) instead of driving
	# straight through it. move_and_collide on a frozen-kinematic RigidBody3D is the
	# supported kinematic mover; it does NOT re-engage the wheel friction model that
	# caused the old "vehicles stuck" bug (that was the dynamic integrator, which
	# freeze=true disables). If we hit something head-on, kill forward speed so we
	# don't keep grinding into it.
	var motion := fwd * (_current_speed_mps * delta)
	var hit := move_and_collide(motion)
	if hit != null:
		# Slide along the surface with whatever motion remains after the hit.
		var remainder := hit.get_remainder()
		var normal := hit.get_normal()
		move_and_collide(remainder.slide(normal))
		# Bleed speed when we run into something fairly square-on (a wall), but keep
		# it on glancing contact (a kerb, a passing machine corner) so we can scrape by.
		if fwd.dot(normal) < -0.5 or normal.dot(fwd) > 0.5:
			_current_speed_mps = move_toward(_current_speed_mps, 0.0, DRIVE_ACCEL * delta * 4.0)
	# Yaw
	rotate_y(yaw_rate * delta)
	# Gravity probe — drop the body until its underside touches the floor.
	# A short ray from above each wheel keeps the chassis at "wheels touching
	# ground" height (works for slopes too — the lowest hit wins).
	_settle_on_ground()
	# Carried-load collision clamp — the carried bale (+ stack) can't sink through
	# anything below it. Kinematic-vs-kinematic in Godot doesn't auto-stop, so we
	# positionally clamp here. Runs in _kinematic_move (one frame after the carry-
	# point's hydraulic update, but at 60Hz the lag is invisible).
	_clamp_carried_against_obstacles()
	# Catch a non-finite transform produced THIS frame (a degenerate collision sweep /
	# slide / ground probe) BEFORE it reaches the renderer — restore the last good pose
	# and kill velocity so the body recovers instead of emitting instance_set_transform.
	if not global_transform.is_finite():
		if not _xf_warned:
			_xf_warned = true
			push_warning("[Vehicle %s] non-finite transform after move — restored" % str(vehicle_id))
		global_transform = _last_good_xf
		linear_velocity = Vector3.ZERO
		angular_velocity = Vector3.ZERO
		_current_speed_mps = 0.0

## Ride-height target above the floor. Subclasses can change this to lift the
## chassis (e.g. Merlo's stabiliser-boom effect when the bucket presses ground).
## Reset toward DEFAULT_RIDE_HEIGHT every frame so the chassis settles back down
## once the subclass stops overriding.
const DEFAULT_RIDE_HEIGHT : float = 0.4
var _ride_height_target_m : float = DEFAULT_RIDE_HEIGHT

## Find the lowest hit beneath the chassis and snap the body to it. Cheap
## stand-in for full wheel suspension — keeps the vehicle resting on whatever
## surface is below (floor, ramp, kerb). Subclasses can bias the ride height by
## writing to _ride_height_target_m before super._physics_process runs.
func _settle_on_ground() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var origin_y := global_position.y + 2.0
	var query := PhysicsRayQueryParameters3D.create(
		Vector3(global_position.x, origin_y, global_position.z),
		Vector3(global_position.x, origin_y - 6.0, global_position.z))
	query.exclude = [get_rid()]
	# Don't snap into bales being carried (their RID is already in the carry
	# tree but might still be in the layer mask).
	if _carried_bale and _carried_bale is PhysicsBody3D:
		query.exclude.append((_carried_bale as PhysicsBody3D).get_rid())
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return
	var ground_y := (hit["position"] as Vector3).y
	# Lerp toward the subclass-controlled target ride height, gently enough that
	# a boom-lever lift (Merlo) is visible over a few frames instead of being
	# instantly snapped flat.
	var target_y := ground_y + _ride_height_target_m
	global_position.y = lerpf(global_position.y, target_y, 0.25)

func _gather_input() -> void:
	# Forward / reverse — single rocker pedal convention (electric/LPG forklift)
	var fwd := Input.get_action_strength("vehicle_forward")
	var rev := Input.get_action_strength("vehicle_reverse")
	_throttle = fwd - rev

	# Steering — two flavours:
	#   live wheel    (default): tracks the keys directly, auto-centres on release.
	#   accumulating  (mast lift): integrates while a key is held, PERSISTS when
	#                              you let go — overshooting is real, you must
	#                              actively counter-steer to get back to straight.
	if accumulate_steering:
		var ax := Input.get_action_strength("vehicle_steer_right") \
				- Input.get_action_strength("vehicle_steer_left")
		_accum_steer_target = clampf(_accum_steer_target + ax * ACCUM_STEER_RATE * get_physics_process_delta_time(), -1.0, 1.0)
		_steering = _accum_steer_target
	else:
		_steering = Input.get_action_strength("vehicle_steer_right") \
				  - Input.get_action_strength("vehicle_steer_left")

	# Brake (foot brake — separate from handbrake)
	_brake = Input.get_action_strength("vehicle_brake")

	# Expose absolute throttle for AudioManager engine-pitch synthesis
	engine_throttle = absf(_throttle)

	# Handbrake toggle (one-shot, on press)
	if Input.is_action_just_pressed("vehicle_handbrake"):
		handbrake_engaged = not handbrake_engaged

func _apply_throttle(_delta: float) -> void:
	if fuel_l <= 0.0:
		engine_force = 0.0
		return
	if handbrake_engaged and absf(_throttle) > 0.01:
		# Releasing the throttle against a handbrake — small lurch only
		engine_force = _throttle * engine_power_kw * 300.0 * 0.05
	else:
		engine_force = _throttle * engine_power_kw * 300.0
		# Note: engine_force is N (multiplied by wheel friction internally).
		# 50.0 is an empirical scaling factor — tuned per vehicle in tuning pass.

func _apply_steering() -> void:
	# Rear-wheel steering on real forklifts — subclass overrides this for Merlos
	# (which have different geometry). Default = front-wheel for now.
	steering = lerpf(steering, _steering * 0.6, 0.15)

# Cached visual steering angle (smoothed) so we don't snap the wheel meshes.
var _visual_steer_rad : float = 0.0

## Visual-only wheel steering: walk every VehicleWheel3D child with
## use_as_steering=true and rotate its WheelMesh child around local Y to match
## the player's steering input. The wheel's PHYSICS direction is untouched
## (that would activate the friction model and stall direct-velocity drive).
# Each steered WheelMesh's base orientation (from the .tscn) — captured once so
# the steering yaw COMPOSES with it instead of overwriting it. Cylinder wheels
# carry a 90°-about-Z base (axle along X); a plain rotation.y= would wipe that and
# stand the cylinder up like a drum. Keyed by the mesh instance id.
var _wheel_base_basis : Dictionary = {}

## When true, REAR steered wheels turn opposite the fronts — the all-wheel /
## "crab-into-corner" steer a Merlo telehandler does (front & rear at different
## angles, exactly as in the user's reference photo). Subclasses set this in _ready.
var all_wheel_steer : bool = false

## When true, the wheel angle PERSISTS when the steering keys are released —
## holding A turns them progressively, letting go LEAVES them at that angle, and
## you only re-centre by holding the opposite key. Real on the JLG mast lift
## (a manual hydraulic steer that doesn't auto-centre). Set in subclass _ready.
var accumulate_steering : bool = false
const ACCUM_STEER_RATE  : float = 0.9    # rad/s while a steering key is held
var _accum_steer_target : float = 0.0    # persistent target angle (-1..1 = -lock..+lock)

## #22 — set true on a vehicle whose VehicleWheel3D sim spams non-finite wheel
## transforms (the forklift). When true, _detach_wheel_visuals() lifts the WheelMeshes
## out of the wheel nodes so a NaN wheel transform can never reach a VisualInstance3D.
@export var detach_wheel_visuals : bool = false
var _detached_wheels : Array = []   # [{mesh, base_basis, is_rear, steering}] — see _detach_wheel_visuals
var _wheels_neutralized : bool = false   # one-shot, set on the first physics tick

func _rotate_steered_wheel_meshes(delta: float) -> void:
	var target := _steering * 0.55     # max ~31° lock
	_visual_steer_rad = lerpf(_visual_steer_rad, target, clampf(8.0 * delta, 0.0, 1.0))
	var yaw_front := Basis(Vector3.UP, _visual_steer_rad)
	var yaw_rear  := Basis(Vector3.UP, -_visual_steer_rad if all_wheel_steer else _visual_steer_rad)
	# Detached path (#22): the meshes now live under WheelVisuals, not the wheel nodes.
	if detach_wheel_visuals:
		for d in _detached_wheels:
			if not bool(d["steering"]):
				continue
			var yawd : Basis = yaw_rear if bool(d["is_rear"]) else yaw_front
			(d["mesh"] as MeshInstance3D).transform.basis = yawd * (d["base_basis"] as Basis)
		return
	for child in get_children():
		if child is VehicleWheel3D and (child as VehicleWheel3D).use_as_steering:
			# Rear wheels sit at negative local Z (behind the centre).
			var is_rear := (child as Node3D).position.z < 0.0
			var yaw := yaw_rear if is_rear else yaw_front
			for sub in child.get_children():
				if sub is MeshInstance3D:
					var mi := sub as MeshInstance3D
					var key := mi.get_instance_id()
					if not _wheel_base_basis.has(key):
						_wheel_base_basis[key] = mi.transform.basis
					# Yaw about world-up, then apply the wheel's base orientation,
					# so the cylinder keeps its axle-along-X roll shape while steering.
					mi.transform.basis = yaw * (_wheel_base_basis[key] as Basis)

## #22 — lift every WheelMesh out of its VehicleWheel3D into a plain holder under the
## body, preserving the rest pose. The wheel node keeps NaN-ing its OWN (non-visual)
## transform harmlessly; no VisualInstance3D inherits it, so the renderer stops getting
## non-finite transforms. The wheels become static visuals (they were already stuck on
## the rejected NaN transform), steered via the detached path in the function above.
func _detach_wheel_visuals() -> void:
	var holder := Node3D.new()
	holder.name = "WheelVisuals"
	add_child(holder)
	for child in get_children():
		if not (child is VehicleWheel3D):
			continue
		var w := child as VehicleWheel3D
		var is_rear := w.position.z < 0.0
		for sub in w.get_children():
			if sub is MeshInstance3D:
				var mi := sub as MeshInstance3D
				mi.reparent(holder, true)   # keep world transform → correct rest pose under the body
				_detached_wheels.append({
					"mesh": mi,
					"base_basis": mi.transform.basis,
					"is_rear": is_rear,
					"steering": w.use_as_steering,
				})

## ROOT FIX for the renderer "instance_set_transform !v.is_finite()" flood.
## VehicleWheel3D nodes on this frozen kinematic body are still stepped by the
## physics server every tick and their transforms go non-finite (#22 observed
## it on the forklift and detached only ITS visuals — every other vehicle's
## wheel meshes kept inheriting the NaN, ~26 renderer errors per tick across
## the parked fleet). The wheel sim is entirely unused — drive is
## move_and_collide + rotate_y + _settle_on_ground — so each VehicleWheel3D is
## replaced by an inert Node3D anchor carrying the same children, and the
## wheel node (the NaN factory) is removed from the tree. Runs on the FIRST
## physics tick, after every subclass _ready has arranged its wheel children
## (MerloP40._articulate_wheels reparents FBX wheels INTO the wheel nodes at
## _ready, so doing this in BaseVehicle._ready would be too early).
func _neutralize_vehicle_wheels() -> void:
	var holder := get_node_or_null("WheelVisuals") as Node3D
	for child in get_children().duplicate():
		if not (child is VehicleWheel3D):
			continue
		var w := child as VehicleWheel3D
		if holder == null:
			holder = Node3D.new()
			holder.name = "WheelVisuals"
			add_child(holder)
		# At the first physics tick the wheel still carries its scene-file
		# transform (the server hasn't stepped it yet) — but guard anyway.
		var w_xf := w.transform
		if not w_xf.is_finite():
			push_warning("[Vehicle %s] wheel %s already non-finite at neutralize — identity fallback" \
				% [str(vehicle_id), String(w.name)])
			w_xf = Transform3D()
		var anchor := Node3D.new()
		anchor.name = "WheelAnchor_" + String(w.name)
		holder.add_child(anchor)
		anchor.transform = w_xf
		var is_rear := w_xf.origin.z < 0.0
		for sub in w.get_children().duplicate():
			if not (sub is Node3D):
				continue
			var n := sub as Node3D
			var local := n.transform
			n.reparent(anchor, false)   # anchor sits at the wheel's pose → keep LOCAL
			n.transform = local if local.is_finite() else Transform3D()
			if n is MeshInstance3D:
				_detached_wheels.append({
					"mesh": n,
					"base_basis": n.transform.basis,
					"is_rear": is_rear,
					"steering": w.use_as_steering,
				})
		# Out of the tree immediately so the server never steps it again this
		# tick; queue_free alone would leave it live for the current step.
		remove_child(w)
		w.queue_free()
	# Visual steering now always uses the detached path (see
	# _rotate_steered_wheel_meshes) — the VehicleWheel3D iteration path has no
	# nodes left to find.
	detach_wheel_visuals = true

func _apply_brakes() -> void:
	var b := _brake * brake_torque_nm
	if handbrake_engaged:
		b = maxf(b, handbrake_torque_nm)
	brake = b

func _consume_fuel(delta: float) -> void:
	if fuel_type == "electric":
		_consume_battery(delta)
		return
	# Diesel / LPG burn — proportional to throttle effort + idle burn.
	var idle_burn  := fuel_consumption_l_per_h / 3600.0 * 0.2
	var work_burn  := fuel_consumption_l_per_h / 3600.0 * absf(_throttle)
	fuel_l = maxf(0.0, fuel_l - (idle_burn + work_burn) * delta)

	# AdBlue (diesel SCR only) — sips DEF at ~5 % of the diesel rate.
	if fuel_type == "diesel" and adblue_capacity_l > 0.0:
		adblue_l = maxf(0.0, adblue_l - (idle_burn + work_burn) * 0.05 * delta)

	# LPG vehicles back their fuel_l with a PHYSICAL tank node — mirror the
	# burn back into the active tank's `level` so when the operator pulls it
	# off the rack it shows the right remaining charge.
	if fuel_type == "lpg" and _active_lpg_tank != null and fuel_capacity_l > 0.0:
		_active_lpg_tank.set_level(fuel_l / fuel_capacity_l)

	if fuel_l <= 0.0:
		EventBus.vehicle_fuel_empty.emit(vehicle_id)
	elif fuel_l / fuel_capacity_l <= 0.15:
		EventBus.vehicle_fuel_low.emit(vehicle_id, fuel_l / fuel_capacity_l)

## Electric drive-battery drain. Idle sips a little; driving + working tool draw
## the most. Subclasses add tool load via _extra_power_draw() (the lift overrides
## it while raising). Fires fuel_empty/low on the EventBus so the HUD + audio react
## the same way they do for a combustion machine running dry.
func _consume_battery(delta: float) -> void:
	var work := clampf(absf(_throttle) + _extra_power_draw(), 0.0, 1.0)
	var draw := (0.12 + 0.88 * work) / DRIVE_BATTERY_LIFE_S
	drive_charge = maxf(0.0, drive_charge - draw * delta)
	if drive_charge <= 0.0:
		EventBus.vehicle_fuel_empty.emit(vehicle_id)
	elif drive_charge <= 0.15 and not _drive_low_emitted:
		_drive_low_emitted = true
		EventBus.vehicle_fuel_low.emit(vehicle_id, drive_charge)
	elif drive_charge > 0.2:
		_drive_low_emitted = false

## Extra battery load 0..1 from a subclass's tool work this frame (e.g. the lift
## raising). Default: none.
func _extra_power_draw() -> float:
	return 0.0

## True while the machine has energy to move/work. Drive + tool code gate on this.
func _has_power() -> bool:
	if fuel_type == "electric":
		return drive_charge > 0.0
	return fuel_l > 0.0

## Power/speed multiplier. Diesel with an empty DEF tank derates to 40 % (SCR
## limp-home); everything else runs at full.
func _power_factor() -> float:
	if fuel_type == "diesel" and adblue_capacity_l > 0.0 and adblue_l <= 0.0:
		return 0.4
	return 1.0

func _enforce_speed_limit() -> void:
	var speed_mps := linear_velocity.length()
	var limit_mps := speed_limit_kmh / 3.6
	if speed_mps > limit_mps:
		engine_force = 0.0   # hard cut — real vehicles have governor

# =============================================================================
# REFUEL / RECHARGE  (called by ServiceStation when the player services it)
# =============================================================================
## Top up combustion fuel (litres). Returns true while there's still room.
func refuel(amount_l: float) -> bool:
	fuel_l = minf(fuel_capacity_l, fuel_l + amount_l)
	EventBus.vehicle_refueled.emit(vehicle_id)
	return fuel_l < fuel_capacity_l

## Top up the DEF/AdBlue tank (litres). Returns true while there's still room.
func refill_adblue(amount_l: float) -> bool:
	adblue_l = minf(adblue_capacity_l, adblue_l + amount_l)
	return adblue_l < adblue_capacity_l

## Charge the drive battery (normalised fraction this tick). Returns true while
## not yet full. ServiceStation in "outlet" mode calls this each frame.
func recharge(frac: float) -> bool:
	drive_charge = minf(1.0, drive_charge + frac)
	if drive_charge > 0.2:
		_drive_low_emitted = false
	EventBus.vehicle_refueled.emit(vehicle_id)
	return drive_charge < 1.0

## Charge/fuel level as a 0..1 fraction, whichever applies — for the HUD bar.
func energy_fraction() -> float:
	if fuel_type == "electric":
		return drive_charge
	return fuel_l / fuel_capacity_l if fuel_capacity_l > 0.0 else 0.0

func adblue_fraction() -> float:
	return adblue_l / adblue_capacity_l if adblue_capacity_l > 0.0 else 0.0

# =============================================================================
# LPG MOUNT API (called by LPGTank when the operator clicks one onto / off the
# vehicle's bracket). Multi-mount vehicles override _on_lpg_active_changed() to
# update any cab indicators ("Tank 1 / Tank 2" lamp etc.).
# =============================================================================
func on_lpg_tank_mounted(tank: Node3D, _anchor: Node3D) -> void:
	if fuel_type != "lpg":
		return
	if tank in _mounted_lpg_tanks:
		return
	_mounted_lpg_tanks.append(tank)
	# If we had no active tank yet, this one takes over and its level pushes
	# straight into fuel_l so the engine can start. Otherwise it sits idle
	# until the operator switches with the active-tank key.
	if _active_lpg_tank == null:
		_active_lpg_tank = tank
		_active_lpg_idx = _mounted_lpg_tanks.find(tank)
		fuel_l = tank.level * fuel_capacity_l
		_on_lpg_active_changed()

func on_lpg_tank_removed(tank: Node3D, _anchor: Node3D) -> void:
	if fuel_type != "lpg":
		return
	_mounted_lpg_tanks.erase(tank)
	if _active_lpg_tank == tank:
		# Save the consumed level back to the tank we're losing.
		if fuel_capacity_l > 0.0:
			tank.set_level(fuel_l / fuel_capacity_l)
		_active_lpg_tank = null
		fuel_l = 0.0
		# If another tank is still on the vehicle, auto-switch to it (it'd
		# be cruel to make the operator press the switch key every single time
		# they reseat the spent tank).
		if not _mounted_lpg_tanks.is_empty():
			_active_lpg_tank = _mounted_lpg_tanks[0]
			_active_lpg_idx  = 0
			fuel_l = _active_lpg_tank.level * fuel_capacity_l
		_on_lpg_active_changed()

## Cycle to the next mounted tank (bale-clamp dual-tank switch). Saves the
## current active tank's burned-down level back to it, then loads from the
## newly-active one. No-op if only one tank is on the rig.
func switch_active_lpg_tank() -> void:
	if _mounted_lpg_tanks.size() < 2:
		return
	if _active_lpg_tank != null and fuel_capacity_l > 0.0:
		_active_lpg_tank.set_level(fuel_l / fuel_capacity_l)
	_active_lpg_idx = (_active_lpg_idx + 1) % _mounted_lpg_tanks.size()
	_active_lpg_tank = _mounted_lpg_tanks[_active_lpg_idx]
	fuel_l = _active_lpg_tank.level * fuel_capacity_l
	_on_lpg_active_changed()

## Subclasses override to update cab indicators.
func _on_lpg_active_changed() -> void:
	pass

# =============================================================================
# VEHICLE LIGHTS + AUDIO AUX  (lights, hazards, reverse beam + beeper, horn)
# =============================================================================
## Build the procedural lights + audio rig on this vehicle. Called via
## call_deferred from _ready so subclass-overridden flags (MastLift sets
## has_lights = false + has_horn = true) take effect before we build.
func _install_vehicle_aux() -> void:
	if has_lights:
		_build_lights()
	_build_reverse_beeper()
	if has_horn:
		_build_horn()

## Light positions are keyed by vehicle_type. forklift + bale_clamp share the
## Mitsubishi chassis so they use the same layout. merlo + merlo_p40 sit on a
## taller, longer rig — different mounts. MastLift / mast lift gets none.
func _vehicle_light_layout() -> Dictionary:
	# Defaults aimed at a forklift-sized chassis (X≈1.2 W, Z≈2.5 L, top≈2.4 H).
	var d := {
		"work_FL":    Vector3(-0.55, 2.32, 0.85),
		"work_FR":    Vector3( 0.55, 2.32, 0.85),
		"haz_FL":     Vector3(-0.62, 1.50, 0.95),
		"haz_FR":     Vector3( 0.62, 1.50, 0.95),
		"haz_RL":     Vector3(-0.62, 1.50,-1.70),
		"haz_RR":     Vector3( 0.62, 1.50,-1.70),
		"reverse":    Vector3( 0.00, 1.50,-1.85),
		"blue_front": Vector3( 0.00, 1.05, 1.20),
		"blue_rear":  Vector3( 0.00, 1.05,-1.55),
		"beacon":     Vector3( 0.00, 2.40, 0.00),
	}
	if vehicle_type == "merlo" or vehicle_type == "merlo_p40":
		d["work_FL"]    = Vector3(-0.85, 2.30, 1.20)
		d["work_FR"]    = Vector3( 0.85, 2.30, 1.20)
		d["haz_FL"]     = Vector3(-0.95, 1.40, 2.20)
		d["haz_FR"]     = Vector3( 0.95, 1.40, 2.20)
		d["haz_RL"]     = Vector3(-0.95, 1.40,-2.20)
		d["haz_RR"]     = Vector3( 0.95, 1.40,-2.20)
		d["reverse"]    = Vector3( 0.00, 1.40,-2.40)
		d["blue_front"] = Vector3( 0.00, 1.00, 2.40)
		d["blue_rear"]  = Vector3( 0.00, 1.00,-2.40)
		d["beacon"]     = Vector3( 0.30, 1.50,-0.60)
	return d

func _build_lights() -> void:
	var layout := _vehicle_light_layout()
	# Work lights — bright white forward spotlights on the ROPS front corners.
	for key in ["work_FL", "work_FR"]:
		var sl := SpotLight3D.new()
		sl.name = "WorkLight_%s" % key
		sl.position = layout[key]
		# Aim slightly down and forward (-Z is forward in vehicle local frame).
		sl.rotation_degrees = Vector3(-18.0, 180.0, 0.0)
		sl.light_color = Color(1.0, 0.96, 0.88)
		sl.light_energy = 4.0
		sl.spot_range = 22.0
		sl.spot_angle = 38.0
		sl.spot_angle_attenuation = 2.5
		sl.visible = false
		add_child(sl)
		_light_work.append(sl)
	# Hazard corner lamps — amber omnis (one in each corner). Blinking is
	# applied per-frame in _tick_vehicle_aux.
	for key in ["haz_FL", "haz_FR", "haz_RL", "haz_RR"]:
		var hl := OmniLight3D.new()
		hl.name = "HazardLight_%s" % key
		hl.position = layout[key]
		hl.light_color = Color(1.0, 0.62, 0.05)
		hl.light_energy = 1.6
		hl.omni_range = 4.0
		hl.visible = false
		# Add a small amber glob mesh so the lamp is visible in daylight too.
		var bulb := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 0.05; sm.height = 0.10
		bulb.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.albedo_color = Color(1.0, 0.62, 0.05)
		bm.emission_enabled = true
		bm.emission = Color(1.0, 0.62, 0.05)
		bm.emission_energy_multiplier = 1.2
		bulb.material_override = bm
		hl.add_child(bulb)
		add_child(hl)
		_light_haz.append(hl)
	# Reverse beam — white spotlight pointing down-rearward.
	_light_rev = SpotLight3D.new()
	_light_rev.name = "ReverseBeam"
	_light_rev.position = layout["reverse"]
	_light_rev.rotation_degrees = Vector3(-22.0, 0.0, 0.0)
	_light_rev.light_color = Color(1.0, 0.97, 0.88)
	_light_rev.light_energy = 3.2
	_light_rev.spot_range = 14.0
	_light_rev.spot_angle = 42.0
	_light_rev.visible = false
	add_child(_light_rev)
	# Linde-style blue safety spots — front and rear. Project a sharply-angled
	# pool of blue light on the floor 2-3 m out so pedestrians see the vehicle
	# approaching even around blind corners.
	_light_blue_f = _make_blue_spot(layout["blue_front"], 180.0)
	_light_blue_r = _make_blue_spot(layout["blue_rear"],  0.0)
	add_child(_light_blue_f)
	add_child(_light_blue_r)

	# Mini-lighthouse beacon rig.
	# The mast lift gets no lights (has_lights is false), so it skips this.
	# The Merlo variants specify a beacon position explicitly.
	var beacon_rig := Node3D.new()
	beacon_rig.name = "BeaconRig"
	
	if vehicle_type == "merlo":
		# Base Merlo has a beacon node explicitly in the cab at local 0,0,0
		var existing_beacon = get_node_or_null("Cab/Beacon")
		if existing_beacon:
			existing_beacon.queue_free()
	
	# The parent Cab node on Merlo
	var target_parent: Node = self
	if (vehicle_type == "merlo" or vehicle_type == "merlo_p40") and has_node("Cab"):
		target_parent = get_node("Cab")

	beacon_rig.position = layout["beacon"]
	target_parent.add_child(beacon_rig)

	# Add the sweeping beams
	var b_spot1 := SpotLight3D.new()
	b_spot1.name = "BeaconBeam1"
	b_spot1.rotation_degrees = Vector3(0.0, 0.0, 0.0)
	b_spot1.light_color = Color(1.0, 0.55, 0.05)
	b_spot1.light_energy = 5.0
	b_spot1.spot_range = 10.0
	b_spot1.spot_angle = 35.0
	b_spot1.spot_angle_attenuation = 2.0
	b_spot1.visible = false
	beacon_rig.add_child(b_spot1)

	var b_spot2 := SpotLight3D.new()
	b_spot2.name = "BeaconBeam2"
	b_spot2.rotation_degrees = Vector3(0.0, 180.0, 0.0)
	b_spot2.light_color = Color(1.0, 0.55, 0.05)
	b_spot2.light_energy = 5.0
	b_spot2.spot_range = 10.0
	b_spot2.spot_angle = 35.0
	b_spot2.spot_angle_attenuation = 2.0
	b_spot2.visible = false
	beacon_rig.add_child(b_spot2)

	# Add localized glow
	var b_glow := OmniLight3D.new()
	b_glow.name = "BeaconGlow"
	b_glow.light_color = Color(1.0, 0.55, 0.05)
	b_glow.light_energy = 2.0
	b_glow.omni_range = 3.0
	b_glow.visible = false
	beacon_rig.add_child(b_glow)

	# Only add the cylindrical body if it's not the Merlo P40 (which has its own).
	if vehicle_type != "merlo_p40":
		var b_mesh := MeshInstance3D.new()
		b_mesh.name = "BeaconMesh"
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.07
		cyl.height = 0.12
		cyl.radial_segments = 10
		b_mesh.mesh = cyl
		var b_mat := StandardMaterial3D.new()
		b_mat.albedo_color = Color(0.95, 0.62, 0.10)
		b_mat.emission_enabled = true
		b_mat.emission = Color(0.95, 0.55, 0.05)
		b_mat.emission_energy_multiplier = 1.6
		b_mesh.material_override = b_mat
		beacon_rig.add_child(b_mesh)

	_beacons.append(beacon_rig)

## A Linde-style blue floor spot — aimed steeply down, narrow cone. `yaw_deg`
## chooses which side: 180 = forward (the FRONT of the vehicle, since -Z = fwd)
## / 0 = rear.
func _make_blue_spot(pos: Vector3, yaw_deg: float) -> SpotLight3D:
	var sl := SpotLight3D.new()
	sl.name = "BlueSpot_%d" % int(yaw_deg)
	sl.position = pos
	sl.rotation_degrees = Vector3(-65.0, yaw_deg, 0.0)
	sl.light_color = Color(0.20, 0.55, 1.00)
	sl.light_energy = 5.0
	sl.spot_range = 6.0
	sl.spot_angle = 14.0
	sl.spot_angle_attenuation = 4.0
	sl.visible = false        # turns on while occupied (see _tick_vehicle_aux)
	return sl

# ── Reverse beeper ────────────────────────────────────────────────────────────
const _BEEPER_SAMPLE_RATE : float = 24000.0
func _build_reverse_beeper() -> void:
	# Per-vehicle cadence (matches real-world reverse alarms — operators learn
	# to identify the rig by its beep pattern).
	match vehicle_type:
		"forklift":
			_beep_tone_hz = 920.0; _beep_period_s = 0.30; _beep_on_ratio = 0.45
		"bale_clamp":
			_beep_tone_hz = 720.0; _beep_period_s = 0.60; _beep_on_ratio = 0.40
			_beep_double = true
		"merlo", "merlo_p40":
			_beep_tone_hz = 440.0; _beep_period_s = 0.55; _beep_on_ratio = 0.50
		"mast_lift", "scissor_lift":
			_beep_tone_hz = 800.0; _beep_period_s = 0.45; _beep_on_ratio = 0.50
		_:
			_beep_tone_hz = 880.0; _beep_period_s = 0.40; _beep_on_ratio = 0.50
	_beeper = AudioStreamPlayer3D.new()
	_beeper.name = "ReverseBeeper"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _BEEPER_SAMPLE_RATE
	gen.buffer_length = 0.10
	_beeper.stream = gen
	_beeper.max_db = 6.0
	_beeper.unit_size = 8.0
	# Mount at the rear of the vehicle so distance attenuation reads right.
	_beeper.position = Vector3(0.0, 1.0, -1.7)
	add_child(_beeper)
	_beeper.play()
	_beeper_pb = _beeper.get_stream_playback() as AudioStreamGeneratorPlayback

# ── Horn (mast lift, eventually others) ──────────────────────────────────────
func _build_horn() -> void:
	_horn = AudioStreamPlayer3D.new()
	_horn.name = "Horn"
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = _BEEPER_SAMPLE_RATE
	gen.buffer_length = 0.10
	_horn.stream = gen
	_horn.max_db = 8.0
	_horn.unit_size = 10.0
	# Mount up on the platform if we have one (mast lift); otherwise just on
	# the chassis. Subclasses can move this later.
	if has_method("platform_node"):
		var pnode = call("platform_node")
		if pnode is Node3D:
			pnode.add_child(_horn)
			_horn.position = Vector3(0.0, 0.5, 0.5)
		else:
			add_child(_horn)
			_horn.position = Vector3(0.0, 1.6, 0.5)
	else:
		add_child(_horn)
		_horn.position = Vector3(0.0, 1.6, 0.5)
	_horn.play()
	_horn_pb = _horn.get_stream_playback() as AudioStreamGeneratorPlayback

## Called from _physics_process — drives blink, blue-spot toggles, reverse
## beam, beeper fill, horn fill. Subclass _physics_process implementations call
## super._physics_process(delta) before their own work so this runs.
func _tick_vehicle_aux(delta: float) -> void:
	# Hazards / Blinkers: 1.5 Hz blink. Lamps follow `hazards_on AND blink-phase` or individual blinker state.
	_haz_blink_t += delta
	if _haz_blink_t >= 0.33:
		_haz_blink_t = 0.0
		_haz_blink_on = not _haz_blink_on
	for hl in _light_haz:
		var n: String = (hl as OmniLight3D).name
		var on := false
		if hazards_on:
			on = true
		elif blinker_left_on and (n == "HazardLight_haz_FL" or n == "HazardLight_haz_RL"):
			on = true
		elif blinker_right_on and (n == "HazardLight_haz_FR" or n == "HazardLight_haz_RR"):
			on = true
		(hl as OmniLight3D).visible = on and _haz_blink_on

	# Mini-lighthouse beacons — guarded against a degenerate or non-finite parent
	# basis (an FBX-imported beacon node can ship a zero-scale or NaN-rotation
	# transform; once that gets read into `rotation.y` and += an offset, every
	# subsequent frame writes NaN back, which the renderer reports as
	# "instance_set_transform !v.is_finite()" forever). Reset to identity on
	# bad input so the spin can recover; skip null entries entirely.
	var beacons_active = hazards_on or blinker_left_on or blinker_right_on or occupied
	for beacon in _beacons:
		var br := beacon as Node3D
		if br == null or not br.is_inside_tree():
			continue
		var b := br.transform.basis
		if not (b.x.is_finite() and b.y.is_finite() and b.z.is_finite()) \
				or b.determinant() < 1e-6:
			br.transform.basis = Basis()
		# Use a wrapped assignment instead of `+=` so a sustained accumulator
		# can't drift past Godot's float range or pick up rounding into NaN.
		br.rotation.y = wrapf(br.rotation.y + delta * TAU / 0.7, -TAU, TAU)
		for c in br.get_children():
			if c is Light3D:
				c.visible = beacons_active

	# Work lights: simple on/off.
	for wl in _light_work:
		(wl as SpotLight3D).visible = work_lights_on
	# Blue safety spots: on while occupied.
	if _light_blue_f:
		_light_blue_f.visible = occupied
	if _light_blue_r:
		_light_blue_r.visible = occupied
	# Reverse beam + beeper — driven off ACTUAL forward speed, not throttle
	# intent. Operator on a slope rolling backward still triggers the alarm.
	var fwd_spd := 0.0
	if has_method("get_speed_mps"):
		fwd_spd = get_speed_mps()
	var reversing := occupied and fwd_spd < -0.20
	if _light_rev:
		_light_rev.visible = reversing
	_fill_beeper(delta, reversing)
	# Horn — counts down to silence after the player presses the button.
	if _horn_active_t > 0.0:
		_horn_active_t = maxf(0.0, _horn_active_t - delta)
	_fill_horn(delta)

func _fill_beeper(_delta: float, active: bool) -> void:
	if _beeper_pb == null:
		return
	var n := _beeper_pb.get_frames_available()
	if n == 0:
		return
	if not active:
		for _i in n:
			_beeper_pb.push_frame(Vector2.ZERO)
		_beeper_time = 0.0
		return
	var dt := 1.0 / _BEEPER_SAMPLE_RATE
	for _i in n:
		# Beep gating — `pos` is position within the period.
		var pos := fmod(_beeper_time, _beep_period_s) / _beep_period_s
		var on := pos < _beep_on_ratio
		if _beep_double:
			# Double-beep pattern (used by the BaleClamp). The first pulse
			# spans 0…on_ratio/2, the second spans 0.5…0.5+on_ratio/2.
			on = (pos < _beep_on_ratio * 0.5) \
					or (pos >= 0.5 and pos < 0.5 + _beep_on_ratio * 0.5)
		var s := 0.0
		if on:
			# Slight square-wave bias for the "beep" timbre.
			var v := sin(_beeper_phase * TAU)
			s = (1.0 if v >= 0.0 else -1.0) * 0.40 + v * 0.30
		_beeper_phase = fmod(_beeper_phase + _beep_tone_hz * dt, 1.0)
		_beeper_pb.push_frame(Vector2(s, s))
		_beeper_time += dt

func _fill_horn(_delta: float) -> void:
	if _horn_pb == null:
		return
	var n := _horn_pb.get_frames_available()
	if n == 0:
		return
	var dt := 1.0 / _BEEPER_SAMPLE_RATE
	for _i in n:
		var s := 0.0
		if _horn_active_t > 0.0:
			var v := sin(_horn_phase * TAU)
			s = (1.0 if v >= 0.0 else -1.0) * 0.55 + v * 0.25
		_horn_phase = fmod(_horn_phase + HORN_TONE_HZ * dt, 1.0)
		_horn_pb.push_frame(Vector2(s, s))

## Trigger the horn (mast lift "platform is operating overhead" alert).
## Called from input when N is pressed while occupied.
func honk() -> void:
	_horn_active_t = HORN_DURATION

# =============================================================================

## Walk children for nodes named LPG_Mount* and drop a fresh full tank into
## each. The tank's `_mount_to()` path runs the same code as a player-driven
## click-on so the bookkeeping (active tank index, fuel_l sync) goes through
## the same on_lpg_tank_mounted callback.
func _spawn_initial_lpg_tanks() -> void:
	var tank_script := preload("res://src/scenes/world/LPGTank.gd")
	for c in get_children():
		if not (c is Node3D):
			continue
		var n := c as Node3D
		if not n.name.begins_with("LPG_Mount"):
			continue
		if n.has_meta("mounted_tank") and n.get_meta("mounted_tank") != null:
			continue
		var t = tank_script.new()
		t.level = 1.0
		# Add to scene root first, then route through the same mount logic the
		# player would trigger — keeps the bookkeeping in one place.
		get_tree().current_scene.add_child(t)
		t.global_transform = n.global_transform
		t.call("_mount_to", n, self)
