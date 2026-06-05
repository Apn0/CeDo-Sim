extends StaticBody3D
class_name ChargingPlug

## Physical plug on a heavy-duty industrial cable. Lives on a ServiceStation
## (mode = "outlet"). Three meaningful states:
##
##   SOCKETED        — parked in the station's wall socket (default)
##   HELD            — carried by the player (under Head, like a tool)
##   PLUGGED_IN      — clipped to an electric vehicle's ChargePort, current flows
##
## The cable is a per-frame procedural line of cylinder segments drawn from the
## station's socket anchor to the plug's CURRENT world position. There's a max
## reach (CABLE_MAX_M); pulling further than that yanks the plug out of the
## player's hand and dumps it on the floor — same as real life.
##
## Interaction (E key, on foot only):
##   • not held + within PICKUP_RANGE         → pick up (from socket OR floor)
##   • held + within PLUG_RANGE of a vehicle  → plug INTO that vehicle (charge begins)
##   • held + no vehicle nearby               → drop on floor
##   • PLUGGED_IN + walk away too far OR E    → unplug (returns to HELD-on-ground)
##
## CHARGING: ServiceStation owns the per-frame `recharge()` call on the
## connected vehicle. The plug just BIDS a vehicle to the station via
## `station.attach_plug_to_vehicle()` when plugged in; the station's existing
## _tick_service() handles the rest.

const PICKUP_RANGE : float = 1.4
const PLUG_RANGE   : float = 1.5    # how close to a vehicle's port you must stand
const CABLE_MAX_M  : float = 9.0    # auto-yank distance from socket

enum State { SOCKETED, HELD, PLUGGED_IN, DROPPED }
var state : int = State.SOCKETED

# References
var station          : Node3D = null    # owning ServiceStation (set on _ready)
var socket_anchor    : Node3D = null    # Node3D under station where cable starts
var _held_by         : Node3D = null
var _plugged_vehicle : Node3D = null
var _player_near     : bool   = false
var _player_node     : Node   = null

# Cable visual
var _cable_root : Node3D = null
const CABLE_SEGMENTS : int   = 14
const CABLE_RADIUS   : float = 0.018
var _cable_segs : Array = []   # Array[MeshInstance3D]

# =============================================================================
func _ready() -> void:
	add_to_group("charging_plug")
	_build_visual()
	_build_pickup_trigger()
	_build_cable_root()
	# We need per-frame updates so the cable can chase the plug.
	set_process(true)

func _process(_delta: float) -> void:
	_update_cable()
	# Auto-yank if the player wanders too far while holding the plug.
	if state == State.HELD and socket_anchor:
		var d := global_position.distance_to(socket_anchor.global_position)
		if d > CABLE_MAX_M:
			_drop_to_floor_at(global_position - global_transform.basis.z * 0.3)
			_emit_banner("[plug]  Cable yanked you back — dropped!")

# =============================================================================
# VISUAL
# =============================================================================
func _build_visual() -> void:
	var black := StandardMaterial3D.new()
	black.albedo_color = Color(0.10, 0.10, 0.12); black.roughness = 0.85
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.92, 0.45, 0.10); orange.roughness = 0.55
	var brass := StandardMaterial3D.new()
	brass.albedo_color = Color(0.78, 0.62, 0.18); brass.metallic = 0.85; brass.roughness = 0.25
	# Boot / strain relief (orange rubber sleeve at cable end)
	var boot := MeshInstance3D.new()
	var bm := CylinderMesh.new(); bm.top_radius = 0.038; bm.bottom_radius = 0.042
	bm.height = 0.08; bm.radial_segments = 14
	boot.mesh = bm; boot.material_override = orange
	boot.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)), Vector3(0, 0, -0.13))
	add_child(boot)
	# Plug body (black square block — the part you grip)
	var body := MeshInstance3D.new()
	var bdm := BoxMesh.new(); bdm.size = Vector3(0.10, 0.10, 0.14)
	body.mesh = bdm; body.material_override = black
	body.position = Vector3(0, 0, -0.02)
	add_child(body)
	# Three brass prongs sticking out the +Z face (that's the bit you push in)
	for i in range(3):
		var prong := MeshInstance3D.new()
		var pm := CylinderMesh.new(); pm.top_radius = 0.008; pm.bottom_radius = 0.008
		pm.height = 0.07; pm.radial_segments = 8
		prong.mesh = pm; prong.material_override = brass
		var x_off := -0.025 + i * 0.025
		prong.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90)),
			Vector3(x_off, 0, 0.085))
		add_child(prong)
	# Collision so the dropped plug doesn't fall through the floor
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.12, 0.12, 0.30)
	col.shape = bx
	add_child(col)

func _build_pickup_trigger() -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = PICKUP_RANGE
	cs.shape = sp
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _build_cable_root() -> void:
	# Cable lives in WORLD SPACE (parented to scene root) so it doesn't inherit
	# the plug's transform — it has its own start/end points.
	_cable_root = Node3D.new()
	_cable_root.name = "PlugCable"
	# Defer: scene root may not exist yet during _ready().
	call_deferred("_install_cable_root")

func _install_cable_root() -> void:
	if _cable_root == null or _cable_root.is_inside_tree():
		return
	var root := get_tree().current_scene
	if root == null:
		return
	root.add_child(_cable_root)
	# Make N cylinder segments up-front; we re-pose them every frame.
	var rubber := StandardMaterial3D.new()
	rubber.albedo_color = Color(0.08, 0.08, 0.10)
	rubber.roughness = 0.95
	for i in CABLE_SEGMENTS:
		var seg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = CABLE_RADIUS
		cm.bottom_radius = CABLE_RADIUS
		cm.height = 1.0   # will be scaled per-frame
		cm.radial_segments = 8
		seg.mesh = cm
		seg.material_override = rubber
		_cable_root.add_child(seg)
		_cable_segs.append(seg)

## Re-pose the cable as a slack catenary-ish arc between the socket anchor and
## the plug. Not physically simulated — just sags below the straight-line
## midpoint by an amount proportional to slack length.
func _update_cable() -> void:
	if socket_anchor == null or _cable_segs.is_empty():
		return
	var a := socket_anchor.global_position
	var b := global_position
	var straight := a.distance_to(b)
	# Slack = how much CABLE there is vs straight-line distance. Saggy if < max.
	var slack := maxf(0.0, CABLE_MAX_M - straight)
	var sag := minf(slack * 0.12, 0.7)   # cap sag so it doesn't hit the floor
	var n := _cable_segs.size()
	# Sample n+1 points along the arc, then place a cylinder between each pair.
	var pts : Array = []
	for i in range(n + 1):
		var t := float(i) / float(n)
		var mid := a.lerp(b, t)
		# Sag is a downward bow centred at t=0.5.
		mid.y -= sag * (1.0 - pow(2.0 * t - 1.0, 2))
		pts.append(mid)
	for i in n:
		var p0 : Vector3 = pts[i]
		var p1 : Vector3 = pts[i + 1]
		var seg : MeshInstance3D = _cable_segs[i]
		_pose_seg(seg, p0, p1)

func _pose_seg(seg: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var seg_len := dir.length()
	if seg_len < 0.0001:
		seg.visible = false
		return
	seg.visible = true
	var mid := (a + b) * 0.5
	# Cylinder's default axis is Y. Align Y to (b - a).
	var up := dir.normalized()
	var seg_basis := _basis_from_up(up)
	seg_basis = seg_basis.scaled(Vector3(1.0, seg_len, 1.0))
	seg.global_transform = Transform3D(seg_basis, mid)

func _basis_from_up(up: Vector3) -> Basis:
	# Build an orthonormal basis whose Y axis is `up`.
	var x := Vector3.RIGHT
	if absf(up.dot(x)) > 0.95:
		x = Vector3.FORWARD
	var z := up.cross(x).normalized()
	x = z.cross(up).normalized()
	return Basis(x, up, z)

# =============================================================================
# INTERACTIONS
# =============================================================================
func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	_player_node = body
	_refresh_prompt()

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	_emit_prompt_hide()

func _refresh_prompt() -> void:
	if not _player_near:
		_emit_prompt_hide(); return
	match state:
		State.SOCKETED, State.DROPPED:
			_emit_prompt("Pick up plug")
		State.HELD:
			_emit_prompt("Drop plug   (walk near a vehicle to plug in)")
		State.PLUGGED_IN:
			_emit_prompt("Unplug")

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near and state != State.HELD:
		return
	if not event.is_action_pressed("interact"):
		return
	match state:
		State.SOCKETED, State.DROPPED:
			if _player_near:
				_pick_up(_player_node)
				get_viewport().set_input_as_handled()
		State.HELD:
			# Try to plug into a nearby vehicle first; failing that, drop.
			var v := _find_electric_vehicle_in_range()
			if v != null:
				_plug_into(v)
			else:
				_drop_to_floor()
			get_viewport().set_input_as_handled()
		State.PLUGGED_IN:
			_unplug()
			get_viewport().set_input_as_handled()

func _pick_up(player: Node3D) -> void:
	_held_by = player
	# Tools-pattern: reparent under Head so it follows the camera. Plug is NOT
	# routed through Inventory because the cable would visually disconnect when
	# the player swaps to scissors mid-grip. Held plug is its own pose.
	var head := player.get_node_or_null("Head") as Node3D
	var parent_node : Node = head if head != null else player
	if get_parent():
		get_parent().remove_child(self)
	parent_node.add_child(self)
	transform = Transform3D(Basis(), Vector3(0.20, -0.20, -0.45))
	collision_layer = 0
	collision_mask  = 0
	state = State.HELD
	_refresh_prompt()

func _drop_to_floor() -> void:
	var player := _held_by
	if player == null:
		return
	var drop_world := player.global_transform * Vector3(0.0, -0.6, -0.7)
	_drop_to_floor_at(drop_world)

func _drop_to_floor_at(world_pos: Vector3) -> void:
	var scene_root := get_tree().current_scene
	if get_parent():
		get_parent().remove_child(self)
	scene_root.add_child(self)
	# Drop with prongs facing up so the visual reads "plug lying on the floor"
	global_transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(-90)), world_pos)
	visible = true
	collision_layer = 1
	collision_mask  = 1
	state = State.DROPPED
	_held_by = null
	_refresh_prompt()

func _plug_into(vehicle: Node3D) -> void:
	# Find the vehicle's charging port anchor (a Node3D named ChargePort, or
	# default to the chassis centre + a bit forward).
	var port := vehicle.get_node_or_null("ChargePort") as Node3D
	var anchor_xf := port.global_transform if port else vehicle.global_transform.translated(Vector3(0, 1.1, 0))
	# Reparent under the vehicle so the plug rides with it.
	if get_parent():
		get_parent().remove_child(self)
	vehicle.add_child(self)
	global_transform = anchor_xf
	collision_layer = 0
	collision_mask  = 0
	state = State.PLUGGED_IN
	_plugged_vehicle = vehicle
	_held_by = null
	# Tell the station to start serving this vehicle.
	if station and station.has_method("attach_plug_to_vehicle"):
		station.call("attach_plug_to_vehicle", vehicle)
	_emit_banner("[plug]  Connected to %s" % vehicle.name)
	_refresh_prompt()

func _unplug() -> void:
	if station and station.has_method("disconnect_vehicle"):
		station.call("disconnect_vehicle")
	# Drop in front of the vehicle's port at floor level.
	var here := global_position
	_plugged_vehicle = null
	_drop_to_floor_at(here + Vector3(0, -0.4, 0))
	_emit_banner("[plug]  Unplugged")

func _find_electric_vehicle_in_range() -> Node3D:
	var best : Node3D = null
	var best_d := PLUG_RANGE
	for v in get_tree().get_nodes_in_group("vehicle"):
		var vn := v as Node3D
		if vn == null or String(vn.get("fuel_type")) != "electric":
			continue
		# Prefer ChargePort distance, fall back to chassis distance.
		var port := vn.get_node_or_null("ChargePort") as Node3D
		var ref_pos := port.global_position if port else vn.global_position
		var d := ref_pos.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = vn
	return best

# =============================================================================
# UI helpers
# =============================================================================
func _emit_prompt(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _emit_banner(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", text)
	print(text)
