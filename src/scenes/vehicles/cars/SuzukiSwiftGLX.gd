extends Car
class_name SuzukiSwiftGLX

## Red 1998 Suzuki Swift GLX — the player's personal car (#134 / #135).
## High-detail variant built from the imported FBX in
## res://assets/models/suzuki_swift_glx/. The FBX ships as a single mesh
## scene; Car.load_model() walks the imported tree at runtime and wires the
## doors / wheels / glass / steering wheel / dashboard / passenger seat,
## via the SHARED loader path (no per-subclass duplicate walker).
##
## RUNTIME WIRING (delegated to Car.gd):
##  • Wheels: 4 sub-meshes (FL/FR/RL/RR) reparented under the matching
##    VehicleWheel3D anchors AND local transform zeroed.
##  • Doors: front L/R hinged at front-edge so they swing open like real
##    car doors (open AWAY from the cabin). E toggles the driver-side
##    door on foot; passenger door from passenger-side proximity.
##  • Glass: alpha-blended translucent material so the windscreen reads
##    as see-through from the driver's seat.
##  • Steering wheel: mirrors chassis steer (chassis.steering * GAIN).
##  • Yasin passenger seat: marker placed on the right-side seat after
##    classify; CrewManager parents Yasin under it at shift start.
##
## SWIFT-SPECIFIC additions (installed via Car._post_load_hook):
##  • Driver / passenger door proximity Area3Ds, enabling E-to-toggle
##    door behaviour from outside the car.
##
## EDITOR-IMPORT REQUIREMENT — same as MerloP40: the editor has to ingest
## the FBX once. Until then the script logs a warning and the car still
## functions as a driveable box (proxy collision in the .tscn).
##
## ORIENTATION: the canonical CeDo direction is forward = local -Z. The
## inherited _model_front_axis_correction_deg = 180.0 wraps the imported
## FBX in a Node3D with rotation.y = π so the asset's visible front lands
## on -Z (matches BaseVehicle._kinematic_move which reads
## `fwd := -global_transform.basis.z`). All car FBXes/GLBs in the project
## are authored facing +Z, so the default 180° correction is right.

const FBX_PATH := "res://assets/models/suzuki_swift_glx/suzuki_swift_glx.fbx"

# Substring-based mesh classifier — Swift FBX exports typically label parts
# in English (Body, Door_FL, Wheel_FL, Glass, Headlight, Steering_Wheel,
# Seat, Dashboard, Mirror, Bumper, Hood, Trunk, Taillight). Order matters:
# `_classify` returns on first match so put SPECIFIC tokens before generic
# ones (e.g. "door_fl" before "door").
const PART_NAMES := {
	"door_fl":   ["door_fl", "door_lf", "door_front_l", "door_frontl", "frontleftdoor", "leftfrontdoor"],
	"door_fr":   ["door_fr", "door_rf", "door_front_r", "door_frontr", "frontrightdoor", "rightfrontdoor"],
	"door_rl":   ["door_rl", "door_lr", "door_rear_l", "door_rearl", "rearleftdoor", "leftreardoor"],
	"door_rr":   ["door_rr", "door_rear_r", "door_rearr", "rearrightdoor", "rightreardoor"],
	"door":      ["door", "porte", "tuer"],   # generic fallback
	"wheel_fl":  ["wheel_fl", "wheel_lf", "wheel_front_l", "front_left_wheel", "wheelfl"],
	"wheel_fr":  ["wheel_fr", "wheel_rf", "wheel_front_r", "front_right_wheel", "wheelfr"],
	"wheel_rl":  ["wheel_rl", "wheel_lr", "wheel_rear_l", "rear_left_wheel", "wheelrl"],
	"wheel_rr":  ["wheel_rr", "wheel_rear_r", "rear_right_wheel", "wheelrr"],
	"wheel":     ["wheel", "tire", "tyre", "roue", "rad"],   # generic fallback
	"glass":     ["glass", "window", "windshield", "windscreen", "vitre"],
	"steering":  ["steering", "wheel_steer", "volant", "lenkrad"],
	"seat":      ["seat", "siege", "siège"],
	"dash":      ["dash", "dashboard", "tableau"],
	"hood":      ["hood", "bonnet", "capot"],
	"trunk":     ["trunk", "boot", "kofferraum"],
	"headlight": ["headlight", "front_light", "phare"],
	"taillight": ["taillight", "tail_light", "rear_light", "feu"],
	"mirror":    ["mirror", "retroviseur", "spiegel"],
	"bumper":    ["bumper", "parechoc", "stoss"],
	"body":      ["body", "chassis", "carrosserie", "shell"],
}

var _driver_door_trigger   : Area3D = null
var _passenger_door_trigger: Area3D = null
var _player_near_driver_door    : bool = false
var _player_near_passenger_door : bool = false
var _player_node                : Node = null

# =============================================================================
func _ready() -> void:
	super._ready()
	vehicle_type = "suzuki_swift_glx"
	# Default tuning for a small 90s hatch.
	if speed_limit_kmh < 40.0:
		speed_limit_kmh = 60.0
	if engine_power_kw < 30.0:
		engine_power_kw = 50.0
	if fuel_type == "lpg":
		fuel_type = "diesel"  # Swift is gasoline, no LPG bottle here — use diesel slot for now
	# #157 — Swift FBX has no carpaint-named material; opt into the
	# largest-mesh fallback so red paint actually applies.
	_paint_color = Color(0.78, 0.10, 0.10)              # red Swift GLX 1998
	_paint_fallback_largest_mesh = true
	_real_world_length_m = 3.85   # real Swift = 3.85 m bumper-to-bumper
	# Funnel through the canonical Car.load_model() path: wraps in
	# FrontAxisCorrection (180° yaw -> visible front lands on -Z), auto-rulers
	# to _real_world_length_m on the LONGEST HORIZONTAL axis only (Y excluded
	# so a Z-up authored FBX gets rescaled to its true length not its height),
	# walks + classifies, articulates wheels/doors/glass/steering, paints, and
	# finally calls _post_load_hook() below for Swift-specific extras.
	_model_path = FBX_PATH
	_part_names = PART_NAMES
	load_model()

# ── Swift-specific extras (door proximity triggers) ─────────────────────────
## Called by Car.load_model() after the shared articulation path has wired
## wheels / doors / glass / steering / seat. The Swift needs two extra Area3D
## proximity triggers on the front-left and front-right door pivots so that
## pressing E from outside the car toggles the nearest door.
func _post_load_hook() -> void:
	var wrapped : Array = get_door_pivots()
	if wrapped.is_empty():
		return
	var driver_door : Node3D = null
	var pax_door    : Node3D = null
	for p in wrapped:
		var pn := p as Node3D
		if pn == null:
			continue
		# Canonical convention: car-local +X is right, -X is left. Driver
		# door = leftmost (smallest world X); passenger door = rightmost.
		if driver_door == null or pn.global_position.x < driver_door.global_position.x:
			driver_door = pn
		if pax_door == null or pn.global_position.x > pax_door.global_position.x:
			pax_door = pn
	if driver_door != null:
		_driver_door_trigger = _install_door_trigger(
			driver_door, "_on_driver_door_enter", "_on_driver_door_exit")
	if pax_door != null and pax_door != driver_door:
		_passenger_door_trigger = _install_door_trigger(
			pax_door, "_on_pax_door_enter", "_on_pax_door_exit")

func _install_door_trigger(at: Node3D, enter_cb: String, exit_cb: String) -> Area3D:
	if at == null:
		return null
	var area := Area3D.new()
	area.name = "DoorTrigger"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = 1.4
	cs.shape = sp
	area.add_child(cs)
	at.add_child(area)
	area.body_entered.connect(Callable(self, enter_cb))
	area.body_exited.connect(Callable(self, exit_cb))
	return area

# ── Door interaction callbacks ────────────────────────────────────────────────
func _on_driver_door_enter(body: Node) -> void:
	if body is BaseVehicle:
		return
	_player_near_driver_door = true
	_player_node = body

func _on_driver_door_exit(body: Node) -> void:
	if body == _player_node:
		_player_near_driver_door = false

func _on_pax_door_enter(body: Node) -> void:
	if body is BaseVehicle:
		return
	_player_near_passenger_door = true

func _on_pax_door_exit(_body: Node) -> void:
	_player_near_passenger_door = false

func _unhandled_input(event: InputEvent) -> void:
	super._unhandled_input(event)
	# Door toggle on foot — driver side opens index 0, passenger side opens index 1.
	if event.is_action_pressed("interact") and not occupied:
		if _player_near_driver_door and _car_doors.size() >= 1:
			toggle_door(0)
		elif _player_near_passenger_door and _car_doors.size() >= 2:
			toggle_door(1)
