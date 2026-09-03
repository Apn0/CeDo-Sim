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
## OPERATOR-FORWARD SIGN (operator report 2026-07-20: "reverse alarm when I go
## forwards and vice versa. Forks/clamps and seat position and look direction
## are forwards"). Forklift / BaleClamp / Merlo / MerloP40 are authored with the
## working gear AND the cab camera on +Z, while the canonical drive convention
## is forward = -basis.z. So the seat looks at the forks, but the code called
## fork-first travel "reverse": the throttle key drove AWAY from what the
## operator faces, and the reverse beeper + beam fired during fork-first travel.
## -1.0 flips the OPERATOR boundary only (throttle sign, steering sign, beeper/
## beam gate, beam aim). NPC autopilot paths stay canonical and are untouched.
@export var operator_forward_sign : float = 1.0
var _throttle: float = 0.0    # -1 reverse … +1 forward — SMOOTHED throttle command (post-ramp)
var _throttle_raw : float = 0.0   # -1..+1 raw input axis BEFORE the SmoothedRate input ramp
var _steering: float = 0.0    # +1 left … -1 right (Godot VehicleWheel3D convention: positive steer = wheels rotate CCW from above = LEFT)
var _brake   : float = 0.0    # 0 … 1 — SMOOTHED brake command (post-ramp)
var _brake_raw : float = 0.0      # 0..1 raw brake axis BEFORE the SmoothedRate input ramp

# Throttle / brake ramps — input-side smoothing (#214 follow-up to #184).
# The audit (RotatingMechanism + vehicle tap-snap pass) recommended replacing
# the global DRIVE_ACCEL=8 m/s² + brake×3 hard-coded constants in _drive() with
# per-vehicle @export overrides + an EXTRA input-side SmoothedRate so the very
# THROTTLE COMMAND itself ramps (not just the resulting speed). Two stages:
#
#   1) Input ramp (SmoothedRate, tau seconds) — _throttle_raw → _throttle
#      converts an instantaneous W/S key-press into a smooth pedal-press feel.
#      tau ≈ 0.6 s for cars, 1.2 s for forklift / mast lift, 1.5 s for Merlo.
#
#   2) Speed ramp (move_toward in _drive) — _throttle * max_mps → _current_speed_mps
#      at throttle_accel_mps2 / brake_decel_mps2 / coast_decel_mps2 m/s². This
#      stage was already here as DRIVE_ACCEL * {1,3,3}; now @export so each
#      subclass tunes its own mass + powertrain feel.
#
# Both stages preserve the existing W/A/S/D/Space input mapping verbatim —
# only the engine_force / brake assignment changes downstream.
@export_group("Drive ramps")
# #223 audit: brake was 24 m/s² = 2.4 g — physically impossible for any tyre on
# concrete (best road cars peak ~1.0-1.1 g). Realistic service-brake defaults;
# subclasses override per machine (forklift/car below).
@export var throttle_accel_mps2 : float = 8.0   # legacy DRIVE_ACCEL — accelerate-to-target rate
@export var brake_decel_mps2    : float = 6.0   # was 24 (2.4g!) — strong service brake ~0.6 g
@export var coast_decel_mps2    : float = 1.5   # was 8 — passive roll-down (drivetrain drag)
@export var throttle_ramp_tau_s : float = 0.6   # input-side ramp tau (cars default)
@export var brake_ramp_tau_s    : float = 0.3   # input-side brake ramp tau — fast but not instant
var _throttle_smoother : SmoothedRate = null
var _brake_smoother    : SmoothedRate = null

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
	# Drive-ramp smoothers — input-side SmoothedRate for throttle + brake (#214).
	# Subclasses may override throttle_ramp_tau_s / brake_ramp_tau_s BEFORE
	# super._ready() to get the right tau on first tick; otherwise they tune
	# AFTER super._ready() and the smoothers pick up the new tau on the next
	# approach() call via set_tau (see _retune_drive_smoothers).
	_throttle_smoother = SmoothedRate.new(0.0, throttle_ramp_tau_s)
	_brake_smoother    = SmoothedRate.new(0.0, brake_ramp_tau_s)
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

# ── npc-05 — loose-bulk carry ledger ─────────────────────────────────────────
# OverflowDumpTask scoops a full indoor waste bin into the vehicle and tips it
# into the outdoor skip. It probed for load_bulk()/unload_bulk() with
# has_method() guards, but NOTHING in production implemented them: every real
# session emptied the indoor bin and then added 0.0 kg to the skip, so the mass
# left the world silently ("bin empties, skip stays at 0.00 kg, forever").
#
# This is a BOOKKEEPING ledger, not a modelled bucket: no geometry, no visual,
# no capacity limit invented out of thin air. It records what the machine is
# currently carrying so the mass is conserved across the drive leg, and the
# density travels with it so the receiving container blends correctly instead of
# being handed a hardcoded 200 kg/m3.
var carried_bulk_kg      : float = 0.0
var carried_bulk_density : float = 0.0

## Take `kg` of loose bulk aboard at `density_kg_m3`. Mass-weighted density blend
## so two scoops of different material average out honestly.
func load_bulk(kg: float, density_kg_m3: float = 0.0) -> void:
	if kg <= 0.0:
		return
	var d : float = density_kg_m3 if density_kg_m3 > 0.0 else carried_bulk_density
	if d <= 0.0:
		d = 200.0
	if carried_bulk_kg > 0.0 and carried_bulk_density > 0.0:
		carried_bulk_density = (carried_bulk_density * carried_bulk_kg + d * kg) / (carried_bulk_kg + kg)
	else:
		carried_bulk_density = d
	carried_bulk_kg += kg

## Tip everything off. Returns the kg that left the vehicle so the caller can
## ledger the dump; the density it was carried at stays readable until the next
## load via bulk_density().
func unload_bulk() -> float:
	var out : float = carried_bulk_kg
	carried_bulk_kg = 0.0
	return out

## Density (kg/m3) of what is aboard — or of what just left, until the next load.
func bulk_density() -> float:
	return carried_bulk_density if carried_bulk_density > 0.0 else 200.0

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
	_throttle_raw = 0.0
	if _throttle_smoother:
		_throttle_smoother.snap_to(0.0)
	_steering = 0.0
	_brake    = 0.0
	_brake_raw = 0.0
	if _brake_smoother:
		_brake_smoother.snap_to(0.0)
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
	_throttle_raw = 0.0
	if _throttle_smoother:
		_throttle_smoother.snap_to(0.0)
	_steering = 0.0
	_brake    = 0.0
	_brake_raw = 0.0
	if _brake_smoother:
		_brake_smoother.snap_to(0.0)
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

# #201 Step 5 — auto-snap REMOVED. Vehicles no longer reparent or freeze bales /
# containers. The clamp/forks/grapple are real AnimatableBody3D physics bodies
# (see #201 steps 1–4); a bale sits in a bucket or between plates because of
# gravity + friction + clamp normal force, NOT because the script teleported it
# under the carry point.
#
# What _try_grab() still does: pure SENSOR. It polls bodies in the carry-point
# sphere and sets `_carried_bale` to the closest qualifying body so consumers
# (load-aware speed, HUD, _on_grabbed hooks) keep working. No state mutation
# on the load itself beyond a one-time LOD-detail upgrade.
func _try_grab() -> void:
	var cp := _carry_point()
	var best : Node3D = null
	var best_d := GRAB_RANGE
	var space_state := cp.get_world_3d().direct_space_state
	if space_state:
		var query := PhysicsShapeQueryParameters3D.new()
		var sphere := SphereShape3D.new()
		sphere.radius = GRAB_RANGE
		query.shape = sphere
		query.transform = Transform3D(Basis(), cp.global_position)
		query.collision_mask = 0xFFFFFFFF
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
		# No qualifying body in range. If we were holding a reference, drop it —
		# the operator pressed grab but nothing is there to grab.
		if _carried_bale != null:
			# #9 — clear the carried flag so a let-go bale is feed-eligible again.
			if is_instance_valid(_carried_bale):
				_carried_bale.set_meta("carried", false)
			_carried_bale = null
			_on_released()
		return
	# Subclasses can still veto via the grip-strength gate (bale clamp refuses
	# if clamp_force is too low for this stack height).
	if not _can_grab_stack(best, []):
		_on_grab_refused(best, [])
		return
	# First-time LOD-detail upgrade so cutting/sheet behaviours work the moment
	# a yard bale becomes a carried load. No freeze, no collision toggle, no
	# reparent — pure physics from here on.
	if best.has_meta("simple_bale"):
		PlaceableCatalog.detail_bale(best)
	# #9 — the sensor can latch a DIFFERENT body while we're still flagged on the
	# old one (force-ramp / pinch re-fires _try_grab mid-carry). Un-mark the old
	# load or it stays feed-ineligible forever (LineFlow._bale_at skips it).
	if _carried_bale != null and _carried_bale != best and is_instance_valid(_carried_bale):
		_carried_bale.set_meta("carried", false)
	_carried_bale = best
	# #9 — mark the bale as in-transit so LineFlow._bale_at won't feed from it
	# while it's being carried (a re-grabbed, previously-delivered bale must not
	# keep metering into the line as it's hauled away). Cleared on release.
	best.set_meta("carried", true)
	# MAGIC-BALE FIX (operator 2026-07-16): placed bales spawn freeze=true /
	# FREEZE_MODE_KINEMATIC (PlaceableCatalog ~1329) so untouched yard stacks
	# don't drift. That freeze=false flip on grab was orphaned in #201 Step 5, so
	# a grabbed bale stayed a FROZEN kinematic body — it ignored gravity AND could
	# not be pushed by the AnimatableBody3D plates (kinematic-vs-kinematic doesn't
	# resolve), leaving it hovering detached as the clamp drove off. Unfreeze it
	# the instant it's latched so gravity + the μ=1.6 plate friction do the carry
	# (no joint reintroduced). Left unfrozen on release so it falls + rests. Never
	# re-freeze while carried / on release — that is what made bales hover forever.
	if best is RigidBody3D:
		(best as RigidBody3D).freeze = false
	_bale_orig_parent = null
	_carried_stack.clear()
	_carried_stack_orig_parents.clear()
	_carried_natural_local_y.clear()
	_on_grabbed(best, [])

## #201 Step 5 — clears the carried-bale reference. The load itself stays where
## physics put it (in the bucket / between plates / on the forks). No reparent,
## no settlement ray — gravity + contact already handled that.
func _release() -> void:
	_on_pre_release()
	if _carried_bale == null:
		return
	# #9 — clear the in-transit flag so the released bale can feed again once it's
	# set down.
	if is_instance_valid(_carried_bale):
		_carried_bale.set_meta("carried", false)
		# FEED-ELIGIBILITY (narrow, correct path — #201 removed the blanket
		# _drop_bale delivered flag because it fired at pickup/mid-air). Mark the
		# bale delivered=true ONLY when it is SET DOWN within range of a real line
		# feed point (an intake marker or a feed belt). LineFlow._bale_at then
		# ingests it; a bale released anywhere else stays inert. Bales never fire
		# this at pickup (that path is _try_grab, which sets carried=true, not
		# delivered) nor mid-air (the vehicle drives the load to the feed point and
		# opens the tool AT the belt).
		if _carried_bale.is_in_group("bale") and _carried_bale.has_meta("material_origin"):
			if _is_near_line_feed_point(_carried_bale.global_position):
				_carried_bale.set_meta("delivered", true)
		# #201 Step 5 removed the only _drop_bale caller, orphaning the dump-zone
		# tip check — re-attach it here so a movable skip released over a
		# "dump_zone" marker still empties (LegacyPropsSpawner tip-zone flow).
		if _carried_bale.is_in_group("waste_container") and _carried_bale.has_method("empty"):
			var zone := _dump_zone_at(_carried_bale.global_position)
			if zone != null:
				var dumped: float = _carried_bale.call("empty")
				print("[Dump] Skip emptied %.0f kg at %s" % [dumped, zone.name])
	_carried_bale = null
	_bale_orig_parent = null
	_carried_stack.clear()
	_carried_stack_orig_parents.clear()
	_carried_natural_local_y.clear()
	_on_released()

## True when `pos` is within range of a line feed point (intake marker / feed
## belt). Delegates to MainWorld.is_near_line_feed_point — found by walking up the
## ancestors (the vehicle lives under MainWorld). Returns false (no delivery) when
## the world can't be reached (headless tests, no MainWorld), which is correct: a
## test that wants a delivered bale sets the meta itself (see VehicleBaleTest).
func _is_near_line_feed_point(pos: Vector3) -> bool:
	var n : Node = self
	while n != null:
		if n.has_method("is_near_line_feed_point"):
			return bool(n.call("is_near_line_feed_point", pos))
		n = n.get_parent()
	return false

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
	# #201 Step 5 — DEAD. This was a positional kludge to keep auto-parented
	# bales from clipping into stacks; with the snap gone, gravity + contact
	# solve this for free. Body kept for save-compat and stays a no-op.
	return
	# The legacy positional clamp that used to live here was deleted on
	# 2026-07-20: it sat after the return, so it was unreachable code (a
	# warning, and warnings are errors here). Recover it from git history if
	# the contact solve ever proves insufficient.

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
	# Virtual hook intended to be overridden by subclasses.
	pass
## Called after a successful grab. Default: nothing.
func _on_grabbed(_primary: Node3D, _stack: Array[Node3D]) -> void:
	# Virtual hook intended to be overridden by subclasses.
	pass
## Called at the very start of _release, before the early-out. Default: nothing.
func _on_pre_release() -> void:
	# Virtual hook intended to be overridden by subclasses.
	pass
## Called after everything has been dropped. Default: nothing.
func _on_released() -> void:
	# Virtual hook intended to be overridden by subclasses.
	pass

## Toggle a bale's "grabbed" state. Bales are RigidBody3D — when grabbed they
## freeze (becoming kinematic so the carry-point parent drags them along) and
## drop their collision layer so they don't push the vehicle around. When let
## go, they unfreeze and re-collide with the world. StaticBody3D bales (legacy
## save data) take the old collision-toggle path.
## #201 Step 5 — kept ONLY for the LOD upgrade. The freeze/collision-disable
## branch was the heart of the auto-snap: it took a bale's physics offline so
## the script could move it manually. With the clamp/forks/grapple now being
## real AnimatableBody3D bodies, the bale's own RB stays live and contact
## physics handles the carry. NPC helpers that still call this end up with a
## detail upgrade and nothing else — which is what we want.
func _set_bale_grabbed(b: Node3D, grabbed: bool) -> void:
	if grabbed and b != null and b.has_meta("simple_bale"):
		PlaceableCatalog.detail_bale(b)

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
var _npc_reverse       : bool    = false   # carry-first approach: back the carry gear onto the target
var _pilot             : VehiclePilot = null   # npc-06 local sensing, built on first NPC drive
# npc-06 GLOBAL ROUTE. _npc_goal is what the caller asked for; _npc_target is the
# waypoint currently being driven to. With no route the two are identical, which
# is exactly the old dead-reckoning behaviour — so a world where the grid cannot
# build degrades to what shipped rather than to a vehicle that refuses to move.
var _npc_goal    : Vector3 = Vector3.ZERO
var _npc_route   : PackedVector3Array = PackedVector3Array()
var _npc_route_i : int = 0
## Metres the last ordered goal sat from a standable cell — see
## npc_goal_clearance_m(). PER-VEHICLE deliberately: the route grid is a shared
## static, so this cannot live on the grid without one vehicle reporting
## another's goal.
var _npc_goal_clearance_m : float = 0.0
## Shared across every vehicle: the occupancy grid describes the plant, not the
## driver. Rebuilt when the world changes so a test that boots a second MainWorld
## cannot inherit the first one's obstacles.
static var _route_grid : VehicleRouteGrid = null
static var _route_grid_world : int = 0

## Force the shared route grid to resample on the next NPC drive order. The
## grid samples real colliders ONCE per world and caches from then on, so a
## wall opening carved or removed mid-session (BuildMode door/gate/window
## placement or deletion) is invisible to every vehicle already driving until
## this is called — measured: a forklift ignored a freshly-placed gate for
## the rest of the session. Cheap: this only drops the cache; the rebuild
## itself stays lazy (paid on the next _ensure_route_grid() call).
static func invalidate_route_grid() -> void:
	_route_grid = null

const NPC_ARRIVE_TOL   : float   = 2.2     # m — "close enough" to the waypoint
const NPC_TURN_RATE    : float   = 1.8     # rad/s yaw slew toward the heading
const NPC_CRUISE_FRAC  : float   = 0.55    # fraction of speed_limit the AI cruises at

# NPC_TARGET_MAX_R — the sanity bound npc_set_target rejects beyond. Derived
# from the world extent, not picked:
#   · the drivable exterior apron is a 200 x 200 m slab centred on the plant
#     anchor (MainWorld._spawn_exterior_ground, MainWorld.gd:918 / :933), so no
#     drivable point is more than its half-diagonal, 141 m, from that anchor;
#   · the plant anchor sits ~224 m from the scene origin (player_spawn is scene
#     (-202.66, -8.0, 94.04), |xz| ~ 222 m);
#   · 224 + 141 ~ 366 m bounds every real surface, so 500 m is that figure with
#     ~35 % headroom for yard / macro extensions.
# Re-checked 2026-07-21 against the marker-frame fix (WorldFrame._layout_to_scene
# is now the identity): this derivation was already reading player_spawn as an
# ABSOLUTE scene coordinate, which is the canonical frame, so the bound is
# unchanged. What DID change is the real spread — vehicles no longer spawn ~228 m
# off their markers, so the headroom is now genuine slack rather than the amount
# of misplacement the bound had to tolerate.
# Deliberately NOT derived from the TempFloor slab (FloorDetector's
# FLOOR_BOX_SIZE_XZ = 4000 m, i.e. +/-2000 m): that slab exists so nothing can
# fall out of the world, it is not plant surface. The 2026-07-20 clamp beads at
# x = +/-814 sat on that slab, hundreds of metres past anything drivable — which
# is exactly the class of coordinate this radius rejects.
const NPC_TARGET_MAX_R : float = 500.0   # m from the scene origin, XZ

## Point the vehicle at a world position and start driving there.
## carry_first=true: approach with the carry gear leading. All fork vehicles
## mount forks/plates at local +Z while canonical drive-forward is -Z, so an
## NPC that noses in always parks the carry point on the FAR side of the load —
## permanently outside GRAB_RANGE and the grab can never latch. Real clamp
## drivers reverse onto the load; so does the autopilot in this mode.
##
## SANITY GUARD (2026-07-21). This entry point accepted ANY Vector3 — no finite
## check, no bounds check — so a NaN or a wild coordinate would have been driven
## toward silently. No current caller does that (every FeederWorker target is
## bounded to a few metres by _find_bale / _work_spot, and the 2026-07-20
## relocation was proven NOT to come through here: those clamps held
## rotation.y == 0.0000, which _npc_drive cannot produce because it rewrites
## rotation.y every frame). The guard is defence-in-depth against a future
## caller, and it turns a silent 800 m excursion into a named warning. The bound
## itself (NPC_TARGET_MAX_R) is derived from the world extent just above.
##
## A refusal leaves the previous waypoint state untouched (it was valid) rather
## than stopping the vehicle — the guard rejects the bad order, it does not
## invent a new one.
func npc_set_target(p: Vector3, carry_first: bool = false) -> void:
	if not (is_finite(p.x) and is_finite(p.y) and is_finite(p.z)):
		push_warning("[BaseVehicle] %s (%s): REFUSED non-finite npc target %s" % [name, vehicle_type, str(p)])
		return
	var r := Vector2(p.x, p.z).length()
	if r > NPC_TARGET_MAX_R:
		push_warning("[BaseVehicle] %s (%s): REFUSED npc target %.1f m from the scene origin (max %.0f m) — target %s, vehicle at %s" % [
			name, vehicle_type, r, NPC_TARGET_MAX_R, str(p), str(global_position)])
		return
	# npc-06 — RE-ORDER SUPPRESSION, and it is not an optimisation. Every driving
	# task re-issues its destination EVERY physics tick until it arrives (e.g.
	# OverflowDumpTask._tick_drive_to_indoor:136-138), so without this the route
	# would be re-planned 60x/s AND the vehicle would restart at waypoint 0 every
	# tick — it could never leave the first leg. Same order, same route, keep the
	# progress already made along it.
	#
	# npc-05 REALWORLD — the guard used to require _npc_route.size() > 0, so it
	# only protected a vehicle the grid actually routed. Any vehicle the grid
	# COULDN'T route (VehicleRouteGrid.route() returning empty — measured on the
	# npc-05 forklift, whose parked spot snaps into a fully enclosed 2-cell
	# pocket in the coarse occupancy grid, is_solid on all 4 sides) fell straight
	# through every tick: _plan_route() re-ran a full A* over the whole site grid
	# 60x/s (measured CPU-bound, fps 3-5 for the entire indoor leg), and
	# _pilot.reset_leg() wiped the local-avoidance pilot's stuck timer/evade
	# commit/reverse budget every physics frame, so VehiclePilot could never
	# complete a multi-frame evade manoeuvre and the vehicle crawled at dead-
	# reckoning speed (measured ~0.26 m/s over a 34 m leg, 128 s) instead of
	# using its whiskers properly. The grid is static per world (only
	# invalidate_route_grid() forces a resample), so retrying an unchanged order
	# every tick can never produce a different route() answer — it was pure
	# waste on the happy path and an active foot-shot on the stuck-vehicle path.
	# Same order now suppresses re-planning and re-arms whether or not a route
	# was found.
	if _npc_target_active and p.distance_to(_npc_goal) < 0.5:
		return
	_npc_goal = p
	_npc_target = p
	_npc_target_active = true
	npc_autopilot = true
	_npc_reverse = false
	# npc-06 — a new order is a new leg: the pilot's stuck timer, evade commit and
	# reverse budget must not carry over, or a vehicle re-tasked mid-recovery
	# inherits a manoeuvre aimed at the previous obstacle.
	if _pilot != null:
		_pilot.reset_leg()
	_npc_route = _plan_route(p)
	_npc_route_i = 0
	if _npc_route.size() > 0:
		_npc_target = _npc_route[0]
	if carry_first:
		var cp := _carry_point()
		if cp != null and cp != self:
			_npc_reverse = to_local(cp.global_position).z > 0.0

## Stop driving (hold position).
## DOES NOT CLEAR _npc_route, AND THAT IS LOAD-BEARING — do not "tidy" it.
##
## npc_route_points() reads _npc_route, which survives a stop, so it reports the
## LAST order's route rather than "no order". That looks like an obvious bug and
## has been logged as one (docs/audit/jam_baseline_2026-09-03.md). Clearing it
## here silently breaks test_jam_baseline: _drive_leg calls npc_stop() and THEN
## calls _route_exists() (npc_route_points() > 0) both at test_jam_baseline.gd:474
## and again from _test_jam3 at :338. With the route cleared, _route_exists()
## returns false after every leg, the suite's "no doorway, skip the check" branch
## re-arms, and the three checks that finally went green on 2026-09-03 go back to
## being SILENTLY SKIPPED — an 11 ok / 0 fail / 3 skipped result that reads like a
## pass. The same field is what _npc_goal_clearance_m follows.
##
## So the stale read is a real defect with a real trap around it: fix the READER
## (_route_exists) first, or fix both in one change with the suite re-run to prove
## the skip count stayed at 0.
func npc_stop() -> void:
	_npc_target_active = false

## True once we're within NPC_ARRIVE_TOL of the ORDERED destination (XZ) — not of
## the intermediate waypoint currently being driven to. Reporting arrival at a
## waypoint would let every task advance its phase the moment the route's first
## corner was reached.
func npc_arrived() -> bool:
	if not _npc_target_active:
		return true
	var a := global_position; a.y = 0.0
	var b := _npc_goal;       b.y = 0.0
	return a.distance_to(b) <= NPC_ARRIVE_TOL

## Waypoints remaining on the planned route (0 when dead reckoning). Exposed so a
## test can tell "arrived because it drove the route" from "arrived because the
## route was empty and the straight line happened to be clear".
func npc_route_points() -> int:
	return _npc_route.size()

## Metres the last ORDERED goal sat from standable ground, as measured by the
## route grid when the order was placed. 0.0 means the pose was free. Greater
## than NPC_ARRIVE_TOL means npc_arrived() can never return true for it. -1.0
## means no free cell was found at all. Per-vehicle, so it is safe to read even
## though the grid itself is shared.
func npc_goal_clearance_m() -> float:
	return _npc_goal_clearance_m

## Plan a vehicle-scale route to `p`. An empty result means dead reckoning, which
## is the shipped behaviour and the correct degradation: a world whose grid
## cannot build must still move its vehicles.
func _plan_route(p: Vector3) -> PackedVector3Array:
	var grid := _ensure_route_grid()
	if grid == null:
		_npc_goal_clearance_m = 0.0
		return PackedVector3Array()
	# Ask, before routing, whether the ordered pose is standable at all. route()
	# appends it verbatim as the final waypoint either way (deliberately — see
	# VehicleRouteGrid.goal_clearance), so this is the only thing that can tell a
	# caller apart from a goal it will reach and one it cannot.
	_npc_goal_clearance_m = grid.goal_clearance(p)
	# WARN ONLY WHEN ARRIVAL IS IMPOSSIBLE, and that threshold is derived, not
	# picked: npc_arrived() succeeds within NPC_ARRIVE_TOL of the ordered pose, so
	# a goal snapped LESS than that is still reachable and warning about it would
	# spam every legitimate container-mouth and cart-seat order. Snapped further
	# and npc_arrived() can never return true, which is the undebuggable case.
	if _npc_goal_clearance_m > NPC_ARRIVE_TOL or _npc_goal_clearance_m < 0.0:
		push_warning(("[BaseVehicle] %s (%s): ORDERED GOAL IS NOT STANDABLE — %s is "
			+ "%s from the nearest vehicle-sized free cell, and npc_arrived() only "
			+ "succeeds within %.1f m, so this order can never complete. The route "
			+ "still ends on it. Check whether the pose is inside a machine, a "
			+ "container, or occupied by a body.")
			% [name, vehicle_type, str(p.round()),
				"unreachable at any distance" if _npc_goal_clearance_m < 0.0
					else "%.2f m" % _npc_goal_clearance_m,
				NPC_ARRIVE_TOL])
	var r := grid.route(global_position, p)
	if r.is_empty():
		# NAMED, not silent. An empty route means the grid found no vehicle-sized
		# way through, and the vehicle then dead-reckons — which looks exactly like
		# the bug this work removed. Measured cause on both jam fixtures: the
		# endpoint was on the far side of the building envelope, and the operator's
		# survey has ZERO doorways (world_layout structure_items is empty), so a
		# 2.2 m probe correctly reports the interior as unreachable. Say so, rather
		# than letting the caller infer it from a leg that wanders.
		push_warning(("[BaseVehicle] %s (%s): NO VEHICLE ROUTE from %s to %s — falling back "
			+ "to dead reckoning. Check whether either endpoint is inside the building "
			+ "(no doorways exist in world_layout structure_items).")
			% [name, vehicle_type, str(global_position.round()), str(p.round())])
	return r

## Build (or reuse) the shared site occupancy grid. Built lazily on the first NPC
## drive order rather than at world load: a session where nothing is ever
## NPC-driven never pays for it, and by first-order time the plant is placed.
func _ensure_route_grid() -> VehicleRouteGrid:
	var tree := get_tree()
	if tree == null:
		return null
	var world := tree.current_scene
	if world == null or not (world is Node3D):
		return null
	if _route_grid != null and _route_grid_world == world.get_instance_id():
		return _route_grid
	var bounds := NavSiteBounds.compute(world)
	if bounds.size == Vector3.ZERO:
		push_warning("[BaseVehicle] site bounds unmeasurable — NPC driving falls back to dead reckoning")
		return null
	var grid := VehicleRouteGrid.new()
	if not grid.build(world as Node3D, bounds, global_position.y):
		return null
	_route_grid = grid
	_route_grid_world = world.get_instance_id()
	print("[VehicleRouteGrid] %d x %d cells over %.0f x %.0f m, %d blocked, built in %d ms"
		% [grid.cols, grid.rows, bounds.size.x, bounds.size.z, grid.blocked_cells, grid.build_ms])
	return _route_grid

## Per-frame AI driving: yaw toward the target (rate-limited), set forward speed
## scaled by how well we're facing it + how close we are. _kinematic_move (called
## right after, with _steering = 0) does the actual swept translation + collision.
func _npc_drive(delta: float) -> void:
	_steering = 0.0
	var to := _npc_target - global_position
	to.y = 0.0
	var dist := to.length()
	if dist <= NPC_ARRIVE_TOL:
		# Reached a waypoint: take the next one and keep rolling. Only the FINAL
		# waypoint stops the vehicle, so a route does not brake at every corner.
		if _advance_waypoint():
			return
		# AI hard-stop on arrival — use brake_decel_mps2 so an NPC-driven Forklift /
		# Merlo stops at the same per-vehicle deceleration as a player-driven one.
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, brake_decel_mps2 * delta)
		if _pilot != null:
			_pilot.reset_leg()
		return
	# Canonical CeDo direction: forward = -basis.z. In Godot, -basis.z for a
	# Y-rotation θ is (-sinθ, 0, -cosθ). So the yaw that points -basis.z along
	# `to` is atan2(-to.x, -to.z) (equivalently atan2(to.x, to.z) + PI).
	# Carry-first mode points +basis.z (the carry side) at the target instead
	# and drives in reverse, so the forks/plates arrive ON the load.
	var desired_yaw := atan2(-to.x, -to.z)
	if _npc_reverse:
		desired_yaw = atan2(to.x, to.z)
	var cruise := (speed_limit_kmh / 3.6) * NPC_CRUISE_FRAC * _power_factor()
	# npc-06 — LOCAL SENSING. Everything above is unchanged dead reckoning; the
	# pilot is the only thing between it and the wheels. It reads the world and
	# returns a heading bias + a speed scale, never a transform, so a jam that
	# clears can be attributed to this layer and nothing else. See VehiclePilot.gd
	# for why sensing (not a navmesh) is the missing organ — jam 1 reproduced with
	# all 339 fence colliders stripped.
	_ensure_pilot()
	_pilot.advise(self, delta, cruise, _npc_target)
	# While the pilot is rounding an obstacle the heading comes from the OBSTACLE,
	# not from the target bearing — steering at a target behind a wall is what
	# turned the timed swerve into an oscillation.
	if is_finite(_pilot.heading_override):
		desired_yaw = _pilot.heading_override
	else:
		desired_yaw += _pilot.yaw_bias
	if not _pilot.hold_heading:
		rotation.y = _approach_angle(rotation.y, desired_yaw, NPC_TURN_RATE * delta)
	# Speed scales with alignment (don't barrel forward while still turning).
	var yaw_err := _angle_diff(rotation.y, desired_yaw)
	var align : float = clampf(cos(yaw_err), 0.0, 1.0)
	var tgt_speed : float = cruise * align * _pilot.speed_scale
	if dist < 4.0:
		tgt_speed *= clampf(dist / 4.0, 0.25, 1.0)   # ease in to the waypoint
	if _npc_reverse:
		tgt_speed = -tgt_speed   # reverse along +basis.z (see _kinematic_move)
	if _pilot.recovery_reverse:
		# CRITICAL SEPARATION. The recovery reverse NEGATES the final command; it
		# never touches _npc_reverse. That flag decides which END of the vehicle
		# faces the load (carry-first approach), and overwriting it during a
		# recovery manoeuvre would leave the forks on the far side of every load,
		# permanently outside GRAB_RANGE. "Back away from the contact" composes
		# with either approach mode; "set reverse = true" does not.
		tgt_speed = -absf(cruise) * _pilot.speed_scale if not _npc_reverse \
			else absf(cruise) * _pilot.speed_scale
	_current_speed_mps = move_toward(_current_speed_mps, tgt_speed, throttle_accel_mps2 * delta)

## Step to the next route waypoint. Returns false when the route is exhausted (or
## there never was one), which is the caller's signal to brake. Clears the pilot's
## per-leg state so a recovery aimed at the previous corner does not leak forward.
func _advance_waypoint() -> bool:
	if _npc_route_i + 1 >= _npc_route.size():
		return false
	_npc_route_i += 1
	_npc_target = _npc_route[_npc_route_i]
	if _pilot != null:
		_pilot.reset_leg()
	return true

## The pilot is created on first NPC drive, not in _ready: a player-driven or
## parked vehicle never allocates one, and nothing in the player path can be
## affected by a node that does not exist.
func _ensure_pilot() -> void:
	if _pilot != null and is_instance_valid(_pilot):
		return
	_pilot = VehiclePilot.new()
	_pilot.name = "VehiclePilot"
	add_child(_pilot)

## Recovery manoeuvres this vehicle's pilot has performed. Exposed so a test can
## prove the pilot ENGAGED on a leg it passed — a cleared jam with zero
## engagements is a coincidence, not a fix.
var evade_count : int:
	get: return _pilot.evade_count if _pilot != null else 0
var recovery_reverse_count : int:
	get: return _pilot.recovery_reverse_count if _pilot != null else 0
var wedge_seconds_total : float:
	get: return _pilot.wedge_seconds_total if _pilot != null else 0.0

## Smallest signed difference a→b, wrapped to [-PI, PI].
func _angle_diff(a: float, b: float) -> float:
	return wrapf(b - a, -PI, PI)

## Move `from` toward `to` by at most `step` radians (shortest way around).
func _approach_angle(from: float, to: float, step: float) -> float:
	var d := _angle_diff(from, to)
	if absf(d) <= step:
		return to
	return from + signf(d) * step

## #201 Step 5 — NPC snap path stripped to match the player's pure-physics
## flow. Now only records the reference; the feeder NPC code is responsible
## for actually driving the vehicle into contact with the bale (see #173).
## Previously this froze the bale + zeroed its collision + reparented it
## under the carry point — a textbook auto-snap.
func npc_carry_bale(bale: Node3D) -> void:
	if bale == null:
		return
	if bale.has_meta("simple_bale"):
		PlaceableCatalog.detail_bale(bale)
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
## Legacy reference constant — kept so external callers / tests that compare
## against the historical 8 m/s² value still see it. The live drive loop now
## reads the @export throttle_accel_mps2 / brake_decel_mps2 / coast_decel_mps2
## triple defined above; subclasses tune those in _ready().
const DRIVE_ACCEL : float = 8.0    # m/s² — legacy default, see throttle_accel_mps2
const TURN_RATE   : float = 1.6    # rad/s yaw at full steer

# Steering ramp — single source of truth for every BaseVehicle subclass on the
# live auto-centre path. Spec is exact: ±55° max lock at 18.33°/s ramp.
#
# ARCHITECTURE NOTE: this project does NOT drive VehicleWheel3D.steering — the
# wheels are deliberately neutralised on the first physics tick by
# _neutralize_vehicle_wheels() (task #112 root-cause fix for the NaN-flood that
# corrupted frozen kinematic vehicles). The wheel-friction integrator never
# runs. Instead, _current_steer_rad is the canonical angle and it drives:
#   • body yaw via _kinematic_move (yaw_rate = steer_frac * TURN_RATE * …)
#   • visual wheel angle via _rotate_steered_wheel_meshes (basis rotation on the
#     detached WheelMesh / WheelVisuals nodes)
#   • the in-cabin steering-wheel mirror (Car.gd reads _current_steer_rad * 6.0)
# Writing _current_steer_rad to VehicleWheel3D.steering would be a no-op (the
# wheels are gone), so we don't bother. Future re-enablement of the friction
# model would only need to add that one write here.
const MAX_STEER_RAD          : float = 0.95993108859688   # 55 deg
const STEER_RATE_RAD_PER_SEC : float = 0.479870674298445  # 27.5 deg/s (+50% faster steering rack speed)
var _current_steer_rad : float = 0.0
# Per-subclass steering tuning (operator 2026-07-17). steer_sign = -1 switches
# left/right for a REAR-wheel-steer machine (the bale clamp). steer_rate is the
# angle slew AND the auto-centre rate — subclasses raise it for a quicker rack.
var steer_sign : float = 1.0
var steer_rate_rad_per_sec : float = STEER_RATE_RAD_PER_SEC

# Kinematic-drive runtime state — _current_speed is the body's actual forward
# speed, tracked frame-to-frame because freeze=true means linear_velocity is no
# longer meaningful for movement (only contact response).
var _current_speed_mps : float = 0.0
# #175 — 1-Hz log throttle/steering/speed/handbrake while occupied so the
# operator can confirm the drive loop's response to input.
var _drive_log_t : float = 0.0
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
	# npc-05 — this used to branch on `occupied`, which BOTH on_operator_entered
	# AND on_npc_entered set. So the moment an NPC climbed into a vehicle, the
	# chassis started reading the PLAYER's input actions — which nobody was
	# pressing — and the `elif` autopilot arm became unreachable for exactly the
	# case it exists to serve. Measured in the real world: an NPC boarded a
	# forklift for an OverflowDumpTask and sat there at throttle=0.00,
	# speed=0.00 m/s for the whole watch window while its task waited to arrive.
	# `_operator` is set ONLY by on_operator_entered, so it is the honest test
	# for "a human is holding the controls".
	if _operator != null:
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
		# Use coast_decel_mps2 so a parked car decelerates at the same per-vehicle
		# rate the operator feels when releasing W mid-cruise.
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, coast_decel_mps2 * delta)
	# Single steering ramp — body yaw, visual wheel mesh, and any VehicleWheel3D
	# .steering writes all read _current_steer_rad downstream. Runs every frame
	# (occupied, autopilot, AND parked) so parked vehicles re-centre on their own.
	_update_steer_ramp(delta)
	# Visual steered wheels follow the ramp EVERY frame, not only while occupied —
	# otherwise a parked or NPC-driven vehicle yaws its body while the front wheels
	# stay dead-straight (bughunt 2026-07-17). Idempotent: just copies the ramped
	# _current_steer_rad onto the wheel-mesh basis.
	_rotate_steered_wheel_meshes(delta)
	_kinematic_move(delta)
	# Lights + reverse beeper + horn audio fill. Runs both occupied + parked
	# (a vehicle rolling backward down a slope still needs the beeper).
	_tick_vehicle_aux(delta)

## Direct kinematic drive — sets _current_speed_mps (forward speed along
## -global_transform.basis.z, canonical CeDo -Z forward) and a yaw rate based
## on throttle + steering.
## Body movement happens in _kinematic_move, which both vehicles and parked
## bodies call so the gravity tick stays in one place.
func _drive(delta: float) -> void:
	# Out of energy (flat battery / empty tank) → no drive, just coast to a stop.
	if not _has_power():
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, coast_decel_mps2 * delta)
		# (wheel-mesh steer is applied unconditionally in _physics_process now)
		return
	# Foot brake — when no throttle is held but the brake action is down, the
	# vehicle decelerates faster than coasting. Per-vehicle @export drive ramp
	# constants (throttle_accel_mps2 / brake_decel_mps2 / coast_decel_mps2) let
	# each subclass tune mass + powertrain feel without forking _drive().
	if handbrake_engaged or absf(_throttle) < 0.01:
		# Coast (no brake) vs hard-brake (handbrake engaged OR brake pedal pressed).
		# brake_decel_mps2 defaults to 24 m/s² (3× legacy DRIVE_ACCEL), coast to 8.
		# Subclasses dial these down for industrial-machine inertia / softer cars.
		var decel := brake_decel_mps2 if (handbrake_engaged or _brake > 0.1) else coast_decel_mps2
		_current_speed_mps = move_toward(_current_speed_mps, 0.0, decel * delta)
		# #175 — kill numerical drift below 5 cm/s. Operator reported "shows
		# 0.5 km/h while standing still" — the move_toward residue + the
		# 0.139 m/s first-tick acceleration could leave a flickering nonzero
		# readout. Below the dismount-threshold it should read exactly zero.
		if absf(_current_speed_mps) < 0.05:
			_current_speed_mps = 0.0
	else:
		# Max speed is derated when the DEF tank is dry (diesel SCR limp-home).
		var max_mps := (speed_limit_kmh / 3.6) * _power_factor()
		var target_speed := _throttle * max_mps
		_current_speed_mps = move_toward(_current_speed_mps, target_speed, throttle_accel_mps2 * delta)
	# (wheel-mesh steer is applied unconditionally in _physics_process now)
	# #175 — periodic diagnostic so the operator can confirm the drive loop
	# from the log. Once a second while occupied: input throttle/steering,
	# resulting speed, handbrake state. If "W does nothing" recurs the log will
	# show throttle=1 but speed not climbing (or handbrake=true).
	_drive_log_t += delta
	if _drive_log_t > 1.0:
		_drive_log_t = 0.0
		print("[Vehicle %s] throttle=%+.2f steer=%+.2f speed=%.2fm/s (%.1f km/h) handbrake=%s pos=%s"
			% [str(vehicle_id), _throttle, _steering, _current_speed_mps,
				_current_speed_mps * 3.6, str(handbrake_engaged), str(global_position.round())])

## Apply the frame's translation + yaw + a downward gravity probe. Runs whether
## occupied or not so a parked vehicle still rests on the floor instead of
## floating where it spawned.
func _kinematic_move(delta: float) -> void:
	# Canonical CeDo direction convention: forward = local -Z (Godot's universal
	# convention, matches Camera3D default and the player controller). Throttle
	# pushes the body along -basis.z; reverse along +basis.z. See the convention
	# block at the top of the file / project memory.
	var fwd := -global_transform.basis.z
	# Steering — only effective while rolling (no in-place pivots)
	var max_mps := speed_limit_kmh / 3.6
	var steer_scale := clampf(absf(_current_speed_mps) / maxf(max_mps, 0.01), 0.0, 1.0)
	var dir_sign := 1.0 if _current_speed_mps >= 0.0 else -1.0
	# Canonical -Z forward + Godot VehicleWheel3D convention: positive
	# VehicleWheel3D.steering rotates the front wheels LEFT (CCW from above), so
	# the input sign is now A (left) = +1, D (right) = -1 (see _gather_input).
	# Godot's rotate_y(+θ) rotates -basis.z (forward) from -Z toward -X (world
	# LEFT), so to yaw LEFT on positive _steering the yaw_rate keeps the same
	# sign as _steering — no negation needed once the input sign is flipped.
	#
	# Body yaw scales by the actual ramped angle (_current_steer_rad / 55°),
	# NOT raw input — so pressing D doesn't instantly slam yaw to TURN_RATE.
	# It ramps from 0 to TURN_RATE over ~3 s (55°/18.33°/s) at full lock.
	var steer_frac := _current_steer_rad / MAX_STEER_RAD
	var yaw_rate := steer_frac * TURN_RATE * steer_scale * dir_sign
	# Horizontal motion — SWEPT, not teleported, so the chassis collides with and
	# slides along static geometry (machines, the bunker, walls) instead of driving
	# straight through it. move_and_collide on a frozen-kinematic RigidBody3D is the
	# supported kinematic mover; it does NOT re-engage the wheel friction model that
	# caused the old "vehicles stuck" bug (that was the dynamic integrator, which
	# freeze=true disables). If we hit something head-on, kill forward speed so we
	# don't keep grinding into it.
	var motion := fwd * (_current_speed_mps * delta)
	# HORIZONTAL DISPLACEMENT BUDGET — see _clamp_recovery_overshoot below.
	# Rapier's contact-recovery pass INSIDE move_and_collide translates an
	# overlapping frozen-kinematic hull even when `motion` is exactly zero, and
	# returns null while doing it (recovery is not reported as a collision), so
	# nothing downstream can observe it. `pre` is the reference the achieved
	# travel is measured against after the sweep + slide have run.
	var pre := global_position
	var hit := move_and_collide(motion)
	if hit != null:
		# Slide along the surface with whatever motion remains after the hit.
		var remainder := hit.get_remainder()
		var normal := hit.get_normal()
		move_and_collide(remainder.slide(normal))
		# Bleed speed when we run into something fairly square-on (a wall), but keep
		# it on glancing contact (a kerb, a passing machine corner) so we can scrape by.
		if fwd.dot(normal) < -0.5 or normal.dot(fwd) > 0.5:
			# Hit-wall bleed — same brake-decel rate as a panic stop, so a head-on
			# scrape kills speed quickly without violating the per-vehicle ramp.
			_current_speed_mps = move_toward(_current_speed_mps, 0.0, brake_decel_mps2 * delta * 1.33)
	_clamp_recovery_overshoot(pre, motion.length())
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

## Slack on top of the frame's requested travel before the horizontal
## displacement is treated as engine-injected recovery. RELATIVE (0.1 % of the
## requested travel), never absolute, and that distinction is load-bearing: an
## absolute per-frame slack is a per-frame budget the recovery simply spends.
## Measured 2026-07-21 with a 1e-4 m absolute slack, the nested pairs consumed
## exactly 1e-4 m EVERY frame in a fixed direction — 0.006 m/s, bounded but
## never converging, i.e. the same bug 250× slower. A relative slack gives a
## parked vehicle (requested travel exactly 0) a budget of exactly 0, so the
## drift stops dead, while a driven vehicle keeps float headroom proportional
## to how far it actually asked to move.
const RECOVERY_SLACK_REL : float = 0.001

## Bound the HORIZONTAL travel achieved by the move_and_collide sweep + slide in
## _kinematic_move to what the caller actually asked for — |motion| scaled by
## the relative slack, so a parked vehicle's budget is exactly zero.
##
## WHY (measured 2026-07-21, src/tests/probe_drift_source.gd): two bale clamps
## restored from a pre-clearance-gate save overlap. Rapier 0.8.34's contact
## recovery runs inside move_and_collide and displaces BOTH hulls by the same
## vector each frame, so the overlap never resolves and the pair translates
## forever at constant speed (185 m in 150 s in MainWorld, 23 m in 15 s in the
## probe) with rotation.y exactly 0. move_and_collide returns null on those
## frames — recovery_as_collision defaults to false — so `hit != null` never
## fires and no existing guard can see the motion. Clamping the ACHIEVED
## displacement is the only signal available to the caller.
##
## PRESERVED ON PURPOSE:
##   • The sweep at :1274, the remainder-slide at :1279 and the head-on speed
##     bleed at :1285 all still run UNCHANGED, so a driven vehicle still
##     collides with and slides along walls, machines and other vehicles
##     instead of passing through them. For legitimate driving this clamp is a
##     no-op: sweep displacement + slide displacement can never exceed |motion|
##     (the slide only consumes the remainder), so the limit is never reached.
##   • Y is untouched. Vertical depenetration (a hull spawned inside the floor)
##     is legitimate physics, and ride height is owned by _settle_on_ground().
##
## ACCEPTED BEHAVIOUR CHANGE: a PARKED vehicle has budget 0, so it can no longer
## be shoved sideways by its own recovery pass when another vehicle drives into
## it — parked machines are now immovable obstacles. That is the physically
## honest reading of a braked 8-tonne machine, and the previous "shove" was the
## same unbounded recovery that caused this bug.
##
## This bounds the symptom; overlap itself is prevented at its two sources —
## BuildMode._vehicle_spawn_blocker at placement time and _denest_loaded_vehicles
## on load.
func _clamp_recovery_overshoot(pre: Vector3, budget_m: float) -> void:
	var d := global_position - pre
	var xz := Vector2(d.x, d.z)
	var travel := xz.length()
	var limit := budget_m * (1.0 + RECOVERY_SLACK_REL)
	# Non-finite is left alone: the post-move watchdog restores _last_good_xf.
	if not is_finite(travel) or travel <= limit:
		return
	var k := limit / travel
	global_position = Vector3(pre.x + d.x * k, global_position.y, pre.z + d.z * k)

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
##
## Two constraints, both measured in the 2026-07-20 stacked-clamp session
## (src/tests/repro_clamp_spawn.gd):
##   • ANOTHER VEHICLE is not ground. Overlapping vehicles each treated the
##     other's hull as floor and ratcheted upward ~2.1 m per rung (the save
##     recorded ladders at y -0.65 / 1.54 / 3.57). Vehicle hits are skipped.
##   • The probe reaches 40 m down (was 6 m) so a body boosted high — ladder
##     rungs reached 13 m above the exterior floor in the measured session —
##     still finds a floor below once vehicle hits are skipped, instead of
##     stranding when the short ray comes up empty. (The measured stray was
##     standing on a real shell overhang at y+1.09, a legitimate hit; the
##     empty-ray strand is the adjacent failure this reach closes.)
func _settle_on_ground() -> void:
	var space := get_world_3d().direct_space_state
	if space == null:
		return
	var origin_y := global_position.y + 2.0
	var from := Vector3(global_position.x, origin_y, global_position.z)
	var to := Vector3(global_position.x, origin_y - 40.0, global_position.z)
	var excl : Array = [get_rid()]
	# Don't snap into bales being carried (their RID is already in the carry
	# tree but might still be in the layer mask).
	if _carried_bale and _carried_bale is PhysicsBody3D:
		excl.append((_carried_bale as PhysicsBody3D).get_rid())
	var hit : Dictionary = {}
	# Walk past vehicle hulls (max 4 stacked bodies) to the first REAL surface.
	for _attempt in 4:
		var query := PhysicsRayQueryParameters3D.create(from, to)
		query.exclude = excl
		hit = space.intersect_ray(query)
		if hit.is_empty():
			return
		var col : Object = hit.get("collider")
		if col is Node and _is_vehicle_hull(col as Node):
			excl.append(hit["rid"])
			hit = {}
			continue
		break
	if hit.is_empty():
		return
	var ground_y := (hit["position"] as Vector3).y
	# Lerp toward the subclass-controlled target ride height, gently enough that
	# a boom-lever lift (Merlo) is visible over a few frames instead of being
	# instantly snapped flat.
	var target_y := ground_y + _ride_height_target_m
	global_position.y = lerpf(global_position.y, target_y, 0.25)

## True when `n` or any ancestor is a vehicle body (group set in _ready above).
## Used by the settle probe so one vehicle never treats another as floor.
func _is_vehicle_hull(n: Node) -> bool:
	var cur : Node = n
	while cur != null:
		if cur.is_in_group("vehicle"):
			return true
		cur = cur.get_parent()
	return false

func _gather_input() -> void:
	# Forward / reverse — single rocker pedal convention (electric/LPG forklift).
	# _throttle_raw is the instantaneous keyboard axis; _throttle is the
	# SmoothedRate-ramped command actually consumed by _drive() downstream.
	# tau (throttle_ramp_tau_s) is set per-subclass in _ready(): cars ~0.6 s,
	# forklift / mast lift ~1.2 s, Merlo ~1.5 s.
	var fwd := Input.get_action_strength("vehicle_forward")
	var rev := Input.get_action_strength("vehicle_reverse")
	# operator_forward_sign: on gear-on-+Z vehicles the forward key must drive
	# fork/clamp-first — the direction the seat faces.
	_throttle_raw = (fwd - rev) * operator_forward_sign
	# Re-tune the smoother in case a subclass changed tau AFTER super._ready
	# (Forklift._ready / MastLift._ready / Car subclasses bump tau in this style).
	if _throttle_smoother:
		_throttle_smoother.set_tau(throttle_ramp_tau_s)
		_throttle = _throttle_smoother.approach(_throttle_raw, get_physics_process_delta_time())
	else:
		_throttle = _throttle_raw

	# Steering — two flavours:
	#   live wheel    (default): tracks the keys directly, auto-centres on release.
	#   accumulating  (mast lift): integrates while a key is held, PERSISTS when
	#                              you let go — overshooting is real, you must
	#                              actively counter-steer to get back to straight.
	# Godot VehicleWheel3D convention: positive `steering` rotates wheels LEFT
	# (CCW from above). The spec is A=left=+1, D=right=-1, so left minus right —
	# pressing A produces +1 and the wheel turns LEFT. Pair with the +_steering
	# yaw_rate in _kinematic_move (no extra negation needed).
	if accumulate_steering:
		var ax := Input.get_action_strength("vehicle_steer_left") \
				- Input.get_action_strength("vehicle_steer_right")
		_accum_steer_target = clampf(_accum_steer_target + ax * ACCUM_STEER_RATE * get_physics_process_delta_time(), -1.0, 1.0)
		_steering = _accum_steer_target
	else:
		_steering = Input.get_action_strength("vehicle_steer_left") \
				  - Input.get_action_strength("vehicle_steer_right")

	# operator_forward_sign: the operator's LEFT is mirrored on a +Z-facing cab,
	# and _kinematic_move flips yaw with the sign of the canonical speed — so
	# without this the fixed throttle polarity would mirror the steering.
	_steering *= operator_forward_sign

	# Brake (foot brake — separate from handbrake). Same two-stage shape as
	# throttle: _brake_raw is the instantaneous key axis, _brake is the SmoothedRate
	# ramp of it (brake_ramp_tau_s, default 0.3 s — fast but not instant).
	_brake_raw = Input.get_action_strength("vehicle_brake")
	if _brake_smoother:
		_brake_smoother.set_tau(brake_ramp_tau_s)
		_brake = _brake_smoother.approach(_brake_raw, get_physics_process_delta_time())
	else:
		_brake = _brake_raw

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

## Single source of truth for the body's effective steering angle, in radians.
##   • A held → target_rad = +MAX_STEER_RAD  ( +0.95993 = +55° )
##   • D held → target_rad = -MAX_STEER_RAD  ( -0.95993 = -55° )
##   • neither / parked → target_rad = 0
## _current_steer_rad ramps toward target at STEER_RATE_RAD_PER_SEC (0.31991 rad/s
## = 18.33°/s). Body yaw, wheel-mesh visual, and any (non-neutralised) front
## VehicleWheel3D .steering writes all read _current_steer_rad downstream — never
## raw _steering. accumulate_steering vehicles (JLG mast lift) carry their own
## integrated lock in _steering and bypass the ramp.
func _update_steer_ramp(delta: float) -> void:
	if not occupied and not (npc_autopilot and _npc_target_active):
		# Parked → wheels straighten on their own (operator dismounted mid-turn).
		_current_steer_rad = move_toward(_current_steer_rad, 0.0, steer_rate_rad_per_sec * delta)
		return
	if accumulate_steering:
		# Mast lift / hold-on-release: _steering is the persisted lock from
		# _gather_input (rate-limited there by ACCUM_STEER_RATE). Track instantly
		# so we don't double-rate. -1..1 maps directly to ±MAX_STEER_RAD.
		_current_steer_rad = _steering * MAX_STEER_RAD * steer_sign
		return
	var target_rad := _steering * MAX_STEER_RAD * steer_sign
	_current_steer_rad = move_toward(_current_steer_rad, target_rad, steer_rate_rad_per_sec * delta)

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

func _rotate_steered_wheel_meshes(_delta: float) -> void:
	# Visual wheel mesh follows the SAME ramp as the body yaw — _current_steer_rad
	# is already rate-limited (18.33°/s, capped at ±55°) by _update_steer_ramp,
	# so no separate lerp / cap here. Keeps the rendered wheel angle in lock-step
	# with whatever the body is actually doing.
	_visual_steer_rad = _current_steer_rad
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
			# Canonical -Z forward → rear wheels sit at POSITIVE local Z.
			var is_rear := (child as Node3D).position.z > 0.0
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
		# Canonical -Z forward → rear wheels sit at POSITIVE local Z.
		var is_rear := w.position.z > 0.0
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
		# Canonical -Z forward → rear wheels sit at POSITIVE local Z.
		var is_rear := w_xf.origin.z > 0.0
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
	# Canonical CeDo direction: forward = -Z, rear = +Z. FRONT-mounted features
	# get a NEGATIVE z; REAR-mounted features get a POSITIVE z.
	var d := {
		"work_FL":    Vector3(-0.55, 2.32,-0.85),
		"work_FR":    Vector3( 0.55, 2.32,-0.85),
		"haz_FL":     Vector3(-0.62, 1.50,-0.95),
		"haz_FR":     Vector3( 0.62, 1.50,-0.95),
		"haz_RL":     Vector3(-0.62, 1.50, 1.70),
		"haz_RR":     Vector3( 0.62, 1.50, 1.70),
		"reverse":    Vector3( 0.00, 1.50, 1.85),
		"blue_front": Vector3( 0.00, 1.05,-1.20),
		"blue_rear":  Vector3( 0.00, 1.05, 1.55),
		"beacon":     Vector3( 0.00, 2.40, 0.00),
	}
	# #169 — bale clamp wants the orange beacon further back on the cab roof.
	# Default forklift position (z=0.00, dead-centre) put it visually above the
	# operator's head; the operator wanted it shifted toward the rear of the
	# ROPS so it doesn't overlap the steering-view sightline. Rear = +Z under
	# canonical -Z-forward convention.
	if vehicle_type == "bale_clamp":
		d["beacon"] = Vector3(0.0, 2.50, 0.55)
	if vehicle_type == "merlo" or vehicle_type == "merlo_p40":
		d["work_FL"]    = Vector3(-0.85, 2.30,-1.20)
		d["work_FR"]    = Vector3( 0.85, 2.30,-1.20)
		d["haz_FL"]     = Vector3(-0.95, 1.40,-2.20)
		d["haz_FR"]     = Vector3( 0.95, 1.40,-2.20)
		d["haz_RL"]     = Vector3(-0.95, 1.40, 2.20)
		d["haz_RR"]     = Vector3( 0.95, 1.40, 2.20)
		d["reverse"]    = Vector3( 0.00, 1.40, 2.40)
		d["blue_front"] = Vector3( 0.00, 1.00,-2.40)
		d["blue_rear"]  = Vector3( 0.00, 1.00, 2.40)
		d["beacon"]     = Vector3( 0.30, 1.50, 0.60)
	return d

func _build_lights() -> void:
	var layout := _vehicle_light_layout()
	# Layout is authored canonical (front -Z, rear +Z). On +Z-gear vehicles the
	# OPERATOR front is +Z — mirror every z so work lights land on the fork side
	# and the reverse beam on the counterweight.
	if operator_forward_sign < 0.0:
		for k in layout:
			var v : Vector3 = layout[k]
			layout[k] = Vector3(v.x, v.y, -v.z)
	_build_work_lights(layout)
	_build_hazard_lights(layout)
	_build_reverse_beam(layout)
	_build_blue_spots(layout)
	_build_beacon_rig(layout)

func _build_work_lights(layout: Dictionary) -> void:
	# Work lights — bright white forward spotlights on the ROPS front corners.
	for key in ["work_FL", "work_FR"]:
		var sl := SpotLight3D.new()
		sl.name = "WorkLight_%s" % key
		sl.position = layout[key]
		# Aim slightly down and forward. Canonical -Z forward → a SpotLight3D
		# with rotation.y = 0 already points along -Z (Godot's default
		# Camera3D/SpotLight3D convention), which IS forward. No yaw needed.
		sl.rotation_degrees = Vector3(-18.0, 0.0 if operator_forward_sign > 0.0 else 180.0, 0.0)
		sl.light_color = Color(1.0, 0.96, 0.88)
		sl.light_energy = 4.0
		sl.spot_range = 22.0
		sl.spot_angle = 38.0
		sl.spot_angle_attenuation = 2.5
		sl.visible = false
		add_child(sl)
		_light_work.append(sl)

func _build_hazard_lights(layout: Dictionary) -> void:
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

func _build_reverse_beam(layout: Dictionary) -> void:
	# Reverse beam — white spotlight pointing down-rearward. Canonical -Z
	# forward → SpotLight3D default points along -Z (forward); yaw 180° flips
	# it to +Z (rear) so the beam casts BEHIND the vehicle when reversing.
	_light_rev = SpotLight3D.new()
	_light_rev.name = "ReverseBeam"
	_light_rev.position = layout["reverse"]
	_light_rev.rotation_degrees = Vector3(-22.0, 180.0 if operator_forward_sign > 0.0 else 0.0, 0.0)
	_light_rev.light_color = Color(1.0, 0.97, 0.88)
	_light_rev.light_energy = 3.2
	_light_rev.spot_range = 14.0
	_light_rev.spot_angle = 42.0
	_light_rev.visible = false
	add_child(_light_rev)

func _build_blue_spots(layout: Dictionary) -> void:
	# Linde-style blue safety spots — front and rear. Project a sharply-angled
	# pool of blue light on the floor 2-3 m out so pedestrians see the vehicle
	# approaching even around blind corners.
	# Canonical -Z forward: SpotLight3D's default orientation (yaw=0) already
	# points along -Z = forward. yaw=180 flips to +Z = rear.
	#
	# #— blue-glow-under-the-machine fix. _build_lights() mirrors every layout z
	# for operator_forward_sign < 0, but the AIM YAW used to stay hard-coded at
	# 0/180. On the counterweight-first rigs (BaleClamp, Forklift, Merlo,
	# MerloP40 — all sign = -1) that put the front spot on the operator-forward
	# side of the chassis while still aiming it backwards, so the beam landed
	# 0.54 m INSIDE its own footprint. Flip the yaw with the position, using the
	# same idiom the work lights (line ~2132) and reverse beam (~2174) already
	# use. Node NAMES stay role-keyed (0 = front, 180 = rear) so external
	# readers such as src/tests/shot_bale_clamp.gd:182 keep resolving.
	_light_blue_f = _make_blue_spot(layout["blue_front"],
		  0.0 if operator_forward_sign > 0.0 else 180.0, "BlueSpot_0")
	_light_blue_r = _make_blue_spot(layout["blue_rear"],
		180.0 if operator_forward_sign > 0.0 else   0.0, "BlueSpot_180")
	add_child(_light_blue_f)
	add_child(_light_blue_r)

func _build_beacon_rig(layout: Dictionary) -> void:
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

## A Linde-style blue floor spot — narrow cone raked down at a shallow angle so
## the pool lands 2-3 m clear of the machine. `yaw_deg` is the CANONICAL aim
## (0 = -Z, 180 = +Z); the caller picks it from operator_forward_sign, because
## on counterweight-first rigs the operator's front is +Z. `node_name` is
## role-keyed and stays fixed across both polarities.
func _make_blue_spot(pos: Vector3, yaw_deg: float, node_name: String) -> SpotLight3D:
	var sl := SpotLight3D.new()
	sl.name = node_name
	sl.position = pos
	# Pitch: -65° threw the pool only 0.49 m out from the lamp — with the mount
	# sitting ~0.05 m inside the chassis face that is a puddle at the wheels,
	# not the "2-3 m out" this function's own header promises (see the
	# _build_blue_spots comment above). -22.0° is the pitch the reverse beam in
	# this same file already uses (line ~2174) and it puts every lit vehicle
	# inside that band: floor throw = mount_height / tan(22°) = 2.48 m (Merlo,
	# h=1.00) … 2.60 m (forklift chassis, h=1.05).
	sl.rotation_degrees = Vector3(-22.0, yaw_deg, 0.0)
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
	# Canonical -Z forward → rear = +Z on standard vehicles; -Z on +Z-gear vehicles.
	_beeper.position = Vector3(0.0, 1.0, 1.7 if operator_forward_sign > 0.0 else -1.7)
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
	# Use the SIGNED speed — get_speed_mps() returns absf() for the HUD readout, so
	# comparing it to a negative threshold made `reversing` ALWAYS false and left
	# the reverse beam + reverse beeper permanently dead on every vehicle (bughunt
	# 2026-07-17). _current_speed_mps is signed (negative when reversing / rolling back).
	# Operator-frame signed speed: positive = toward where the seat faces.
	# On +Z-gear vehicles canonical speed is negated, so fork-first travel is
	# operator-forward (silent) and counterweight-first travel beeps — which is
	# also physically right for NPC-driven forklifts on their canonical legs.
	var fwd_spd := _current_speed_mps * operator_forward_sign
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
