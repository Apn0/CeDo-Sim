extends Car
class_name SuzukiSwiftGLX

## Red 1998 Suzuki Swift GLX — the player's personal car (#134 / #135).
## High-detail variant built from the imported FBX in
## res://assets/models/suzuki_swift_glx/. The FBX ships as a single mesh
## scene; this script walks the imported tree at runtime and wires the
## doors / wheels / glass / steering wheel / dashboard / passenger seat,
## mirroring the MerloP40.gd pattern.
##
## RUNTIME WIRING:
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
## EDITOR-IMPORT REQUIREMENT — same as MerloP40: the editor has to ingest
## the FBX once. Until then the script logs a warning and the car still
## functions as a driveable box (proxy collision in the .tscn).

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
	"door_rr":   ["door_rr", "door_rr", "door_rear_r", "door_rearr", "rearrightdoor", "rightreardoor"],
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

var _door_pivots  : Array  = []     # ordered: FL, FR, RL, RR (whichever exist)
var _driver_door_trigger   : Area3D = null
var _passenger_door_trigger: Area3D = null
var _player_near_driver_door    : bool = false
var _player_near_passenger_door : bool = false
var _player_node                : Node = null

const STEERING_GAIN := 6.0      # chassis steering → wheel rotation multiplier

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
	_load_and_classify()

func _load_and_classify() -> void:
	if not ResourceLoader.exists(FBX_PATH):
		push_warning("[SuzukiSwiftGLX] FBX not imported yet at %s — using proxy box." % FBX_PATH)
		return
	var packed := load(FBX_PATH)
	if packed == null or not (packed is PackedScene):
		push_warning("[SuzukiSwiftGLX] FBX resource not a PackedScene; reopen editor to re-import.")
		return
	var fbx_root : Node = (packed as PackedScene).instantiate()
	if fbx_root == null:
		return
	add_child(fbx_root)
	# Walk + classify every Node3D under the FBX root.
	_walk(fbx_root)
	_wire_articulation()
	# #157 — apply paint AFTER articulation so the glass alpha-blend doesn't get
	# tinted (glass is handled by _articulate_glass first; the fallback picks
	# the largest mesh which is the body, not the windows).
	if _paint_color.a > 0.001:
		_paint_hit_any = false
		_paint_body(self)
		_paint_fallback_apply(fbx_root)

func _walk(n: Node) -> void:
	if n is Node3D:
		_classify(n as Node3D)
	for c in n.get_children():
		_walk(c)

func _classify(n: Node3D) -> void:
	var nm := n.name.to_lower()
	for category in PART_NAMES:
		for needle in PART_NAMES[category]:
			if nm.contains(needle):
				var arr : Array = _parts.get(category, [])
				arr.append(n)
				_parts[category] = arr
				return

# ── Articulation orchestration ────────────────────────────────────────────────
func _wire_articulation() -> void:
	_articulate_wheels()
	_articulate_doors()
	_articulate_glass()
	_articulate_steering()
	_place_passenger_seat()

func _articulate_wheels() -> void:
	# Prefer specific FL/FR/RL/RR; fall back to generic "wheel" matched by
	# nearest-VW3D when the FBX uses plain "Wheel001..." names.
	var vwheels : Array = []
	for c in get_children():
		if c is VehicleWheel3D:
			vwheels.append(c)
	if vwheels.is_empty():
		return
	# Build a flat list of all wheel meshes the classifier found.
	var found : Array = []
	for key in ["wheel_fl", "wheel_fr", "wheel_rl", "wheel_rr", "wheel"]:
		if _parts.has(key):
			for w in _parts[key]:
				if not found.has(w):
					found.append(w)
	# Nearest-VW3D match in world XZ.
	for w in found:
		var wn := w as Node3D
		if wn == null:
			continue
		var best : VehicleWheel3D = null
		var best_d := 1e9
		for vw in vwheels:
			var d : float = (vw as Node3D).global_position.distance_to(wn.global_position)
			if d < best_d:
				best_d = d
				best = vw
		if best == null:
			continue
		if wn.get_parent():
			wn.get_parent().remove_child(wn)
		best.add_child(wn)
		wn.transform = Transform3D.IDENTITY
		var proc_mesh := best.get_node_or_null("WheelMesh")
		if proc_mesh:
			(proc_mesh as Node3D).visible = false

func _articulate_doors() -> void:
	# Collect door pivots from specific keys first.
	var doors : Array = []
	for key in ["door_fl", "door_fr", "door_rl", "door_rr"]:
		if _parts.has(key):
			for d in _parts[key]:
				doors.append(d)
	# Generic "door" fallback ONLY if we found nothing specific — avoids
	# double-counting a Door_FL that also matched "door".
	if doors.is_empty() and _parts.has("door"):
		for d in _parts["door"]:
			doors.append(d)
	# Wrap each in a hinge pivot at the FRONT EDGE of the door panel so it
	# swings open like a real car door (open AWAY from the cabin centre).
	var wrapped : Array = []
	for d in doors:
		var p := _wrap_door_pivot(d as Node3D)
		if p != null:
			wrapped.append(p)
	_door_pivots = wrapped
	articulate_doors(wrapped, 65.0)
	# Driver-side proximity trigger (left front door). Find by world X < self.
	if wrapped.size() > 0:
		var driver_door : Node3D = null
		var pax_door    : Node3D = null
		for p in wrapped:
			var pn := p as Node3D
			if driver_door == null or pn.global_position.x < driver_door.global_position.x:
				driver_door = pn
			if pax_door == null or pn.global_position.x > pax_door.global_position.x:
				pax_door = pn
		_driver_door_trigger    = _install_door_trigger(driver_door, "_on_driver_door_enter", "_on_driver_door_exit")
		if pax_door != driver_door:
			_passenger_door_trigger = _install_door_trigger(pax_door,    "_on_pax_door_enter",    "_on_pax_door_exit")

## Reparent `panel` under a fresh Node3D pivot placed at the FORWARD edge of
## the panel (its +Z side in panel-local space — front of the car). Swinging
## the pivot's Y rotation now hinges the door at that edge.
func _wrap_door_pivot(panel: Node3D) -> Node3D:
	if panel == null or panel.get_parent() == null:
		return null
	var parent := panel.get_parent()
	var pivot := Node3D.new()
	pivot.name = "%s_Pivot" % panel.name
	# Pivot sits at the panel's world transform, then we shift the panel
	# inside the pivot so its FRONT edge is at pivot origin.
	var panel_w : Transform3D = panel.global_transform
	parent.add_child(pivot)
	pivot.global_transform = panel_w
	parent.remove_child(panel)
	pivot.add_child(panel)
	panel.transform = Transform3D.IDENTITY
	# Approximate offset: car doors are ~0.8m long fore-aft, hinge at the
	# front edge. Shift the panel BACK by half its length so the FRONT edge
	# sits at the pivot origin. If a given FBX is rotated 90° the swing
	# will look wrong — operator can tune per car later.
	panel.position.z = -0.40
	return pivot

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

func _articulate_glass() -> void:
	if not _parts.has("glass"):
		return
	for g in _parts["glass"]:
		var gm := g as MeshInstance3D
		if gm == null or gm.mesh == null:
			continue
		for i in gm.mesh.get_surface_count():
			var base_mat := gm.mesh.surface_get_material(i)
			var mat : StandardMaterial3D
			if base_mat is StandardMaterial3D:
				mat = (base_mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			else:
				mat = StandardMaterial3D.new()
				mat.albedo_color = Color(0.80, 0.86, 0.90)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			var c := mat.albedo_color
			c.a = 0.28
			mat.albedo_color = c
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.metallic = 0.10
			mat.roughness = 0.06
			gm.set_surface_override_material(i, mat)

func _articulate_steering() -> void:
	if _parts.has("steering") and not (_parts["steering"] as Array).is_empty():
		_steering_node = (_parts["steering"] as Array)[0]
		# Reset basis if FBX delivered a degenerate transform.
		if _steering_node != null:
			var b := _steering_node.transform.basis
			if not (b.x.is_finite() and b.y.is_finite() and b.z.is_finite()) \
					or b.determinant() < 1e-6:
				_steering_node.transform.basis = Basis()

## Snap the passenger seat marker to the right-side seat the FBX provides.
## If no "seat" is found, the default (0.40, 0.65, 0.10) from Car._install_passenger_seat
## stays in place.
func _place_passenger_seat() -> void:
	if _passenger_seat == null or not _parts.has("seat"):
		return
	var right_seat : Node3D = null
	for s in _parts["seat"]:
		var sn := s as Node3D
		if sn == null:
			continue
		if right_seat == null or sn.global_position.x > right_seat.global_position.x:
			right_seat = sn
	if right_seat != null:
		_passenger_seat.global_position = right_seat.global_position + Vector3(0.0, 0.45, 0.0)

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

func _process(delta: float) -> void:
	super._process(delta)
	# Steering-wheel mirror.
	if _steering_node != null and is_inside_tree():
		_steering_node.rotation.z = -steering * STEERING_GAIN
