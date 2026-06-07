extends StaticBody3D
class_name LeafBlower

## A holdable LEAF BLOWER for housekeeping loose film scraps that drift around
## the wash line / shredder discharge / extruder shed. Same pickup-and-hold UX
## as the ShovelTool: walk up, E to pick up, LMB-HOLD to blow.
##
## While held, the blower projects a cone of wind from the operator's camera
## forward — every RigidBody3D in the group "film_scrap" inside the cone receives
## a force directed AWAY from the muzzle, attenuated by inverse-square distance
## and gated by a single-ray occlusion check (so walls/machines block the wind).
##
## The motor SPOOLS UP over `spool_time_seconds` while LMB is held, and spools
## DOWN once released — so it doesn't snap from 0 to full throttle (and bodies
## don't get teleport-flung).
##
## Originally a Jules-PR Node3D with turn_on()/turn_off() but never wired up;
## refitted into the same held-tool pattern as ShovelTool / WireCutter so it
## composes with the Inventory + crosshair-prompt + build-menu flow.

## tool_id — used by Inventory.slot_label() to label the hotbar slot.
const tool_id : String = "leafblower"

const PICKUP_RANGE   : float = 1.6
@export var max_force          : float = 50.0    # N at the muzzle (before attenuation)
@export var max_range          : float = 10.0    # m — bodies past this are ignored
@export var spool_time_seconds : float = 1.0     # full-throttle ramp time
@export var cone_radius        : float = 2.0     # half-radius of the wind cone at its tip

enum State { OFF, SPOOLING_UP, FULL_THROTTLE, SPOOLING_DOWN }
var _state : int = State.OFF
var _spool : float = 0.0

var _held_by     : Node3D = null
var _player_near : bool   = false
var _player_node : Node   = null

# Wind sensor + occlusion ray (built procedurally in _build_wind_volume).
var _wind_area : Area3D = null
var _wind_cs   : CollisionShape3D = null
var _ray       : RayCast3D = null
var _active_bodies : Array[RigidBody3D] = []

# =============================================================================
func _ready() -> void:
	add_to_group("leaf_blower")
	_build_visual()
	_build_pickup_trigger()
	_build_wind_volume()

## Orange housing + dark grip + dark nozzle. Sized so a held pose reads cleanly.
func _build_visual() -> void:
	var orange := StandardMaterial3D.new()
	orange.albedo_color = Color(0.96, 0.42, 0.10); orange.roughness = 0.55
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.10, 0.10, 0.12); dark.roughness = 0.85
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.65, 0.65, 0.68); steel.metallic = 0.7; steel.roughness = 0.35
	# Main motor housing
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.22, 0.22, 0.34)
	body.mesh = bm; body.material_override = orange
	body.position = Vector3(0, 0.06, 0.0)
	add_child(body)
	# Nozzle tube extending forward (-Z = blow direction)
	var nozzle := MeshInstance3D.new()
	var nm := CylinderMesh.new(); nm.top_radius = 0.06; nm.bottom_radius = 0.08
	nm.height = 0.55; nm.radial_segments = 16
	nozzle.mesh = nm
	nozzle.material_override = dark
	nozzle.position = Vector3(0, 0.06, -0.42)
	nozzle.rotation.x = deg_to_rad(90.0)
	add_child(nozzle)
	# Nozzle cone tip
	var tip := MeshInstance3D.new()
	var tm := CylinderMesh.new(); tm.top_radius = 0.05; tm.bottom_radius = 0.075
	tm.height = 0.08; tm.radial_segments = 16
	tip.mesh = tm
	tip.material_override = steel
	tip.position = Vector3(0, 0.06, -0.72)
	tip.rotation.x = deg_to_rad(90.0)
	add_child(tip)
	# Grip handle on top
	var grip := MeshInstance3D.new()
	var gm := BoxMesh.new(); gm.size = Vector3(0.06, 0.14, 0.10)
	grip.mesh = gm; grip.material_override = dark
	grip.position = Vector3(0, 0.24, 0.0)
	add_child(grip)
	# Intake vent on the back (cosmetic dark cap)
	var vent := MeshInstance3D.new()
	var vm := BoxMesh.new(); vm.size = Vector3(0.18, 0.18, 0.04)
	vent.mesh = vm; vent.material_override = dark
	vent.position = Vector3(0, 0.06, 0.19)
	add_child(vent)
	# Bounding collision so it rests on the floor when dropped.
	var col := CollisionShape3D.new()
	var cb := BoxShape3D.new(); cb.size = Vector3(0.24, 0.30, 0.85)
	col.shape = cb
	col.position = Vector3(0, 0.12, -0.20)
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

## A cylindrical sensor in front of the nozzle that tracks every film_scrap in
## reach. The cylinder's local +Z (its length axis after the 90° tilt) points
## along the blow direction — _physics_process repositions it each frame to sit
## in front of the camera when held.
func _build_wind_volume() -> void:
	_wind_area = Area3D.new()
	_wind_area.name = "WindArea"
	_wind_area.monitorable = false   # we only sense, we don't trigger others
	_wind_area.collision_layer = 0
	_wind_area.collision_mask = 1
	_wind_cs = CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = max_range
	cyl.radius = cone_radius
	_wind_cs.shape = cyl
	# Tilt the cylinder so its length axis is local +Z (the muzzle direction).
	_wind_cs.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(90.0)), Vector3.ZERO)
	_wind_area.add_child(_wind_cs)
	add_child(_wind_area)
	_wind_area.body_entered.connect(_on_wind_body_entered)
	_wind_area.body_exited.connect(_on_wind_body_exited)
	_ray = RayCast3D.new()
	_ray.enabled = true
	_ray.collide_with_bodies = true
	_ray.collision_mask = 1
	add_child(_ray)

# =============================================================================
# PICKUP / DROP (E)  — same contract as ShovelTool / WireCutter
# =============================================================================
func _on_body_entered(body: Node3D) -> void:
	if _held_by != null or body.name != "Player":
		return
	_player_near = true
	_player_node = body

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		if _player_near and event.is_action_pressed("interact"):
			_pick_up(_player_node)
			get_viewport().set_input_as_handled()
		return
	# Only react when WE are the active inventory slot.
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return
	# Continuous fire — _physics_process reads Input.is_action_pressed("tool_use")
	# directly so a HELD LMB ramps up the spool; release ramps it back down.

func crosshair_prompt(_player: Node3D) -> String:
	return "Take leaf blower" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	_held_by = player
	var inv := get_node_or_null("/root/Inventory")
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		get_parent().remove_child(self)
		parent_node.add_child(self)
	# Held pose: clipped under the camera, nozzle pointed forward (-Z).
	transform = Transform3D(Basis(), Vector3(0.22, -0.22, -0.55))
	collision_layer = 0
	collision_mask  = 0
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _drop() -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	var player := _held_by
	var scene_root := get_tree().current_scene
	var drop_world := player.global_transform * Vector3(0.0, -0.6, -0.8)
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask  = 1
	_held_by = null
	_state = State.OFF
	_spool = 0.0
	_active_bodies.clear()

# =============================================================================
# WIND SIM — runs every physics step while held
# =============================================================================
func _on_wind_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("film_scrap"):
		if not _active_bodies.has(body):
			_active_bodies.append(body as RigidBody3D)

func _on_wind_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		_active_bodies.erase(body as RigidBody3D)

## Direction the operator is aiming (camera forward when held, else our own -Z).
func _aim_direction() -> Vector3:
	if _held_by != null:
		var cam := _held_by.get_node_or_null("Head/Camera3D") as Camera3D
		if cam != null:
			return -cam.global_transform.basis.z.normalized()
	return -global_transform.basis.z.normalized()

func _muzzle_origin() -> Vector3:
	# Tip of the nozzle (the 'tip' mesh sits ~0.72 m forward of our origin).
	return global_transform * Vector3(0.0, 0.06, -0.72)

func _physics_process(delta: float) -> void:
	# Pose the WindArea every frame: in front of the muzzle, aligned with aim.
	# (Always — including when stowed in the inventory but inactive — so a held
	# tool that becomes active mid-frame already has its sensor in the right spot.)
	if _wind_area != null and is_inside_tree():
		var aim := _aim_direction()
		var origin := _muzzle_origin() + aim * (max_range * 0.5)
		# Build a basis whose local +Z (length axis) points along aim.
		var up := Vector3.UP
		if absf(aim.dot(up)) > 0.95:
			up = Vector3.RIGHT
		var right := up.cross(aim).normalized()
		var nu := aim.cross(right).normalized()
		_wind_area.global_transform = Transform3D(Basis(right, nu, aim), origin)

	# Drive the spool state.
	if _held_by == null:
		_state = State.OFF
		_spool = 0.0
		return
	var inv := get_node_or_null("/root/Inventory")
	var is_active := (inv == null) or bool(inv.call("is_active", self))
	var pressed := is_active and Input.is_action_pressed("tool_use")
	match _state:
		State.OFF:
			if pressed: _state = State.SPOOLING_UP
		State.SPOOLING_UP:
			_spool = minf(1.0, _spool + delta / maxf(spool_time_seconds, 0.001))
			if _spool >= 1.0: _state = State.FULL_THROTTLE
			if not pressed:   _state = State.SPOOLING_DOWN
		State.FULL_THROTTLE:
			if not pressed:   _state = State.SPOOLING_DOWN
		State.SPOOLING_DOWN:
			_spool = maxf(0.0, _spool - delta / maxf(spool_time_seconds, 0.001))
			if _spool <= 0.0: _state = State.OFF
			if pressed:       _state = State.SPOOLING_UP
	if _spool <= 0.0:
		return

	# Push every tracked scrap forward, with inverse-square attenuation and a
	# single occlusion ray (so a machine/wall blocks the wind).
	var force_mag := max_force * _spool
	var aim := _aim_direction()
	var muzzle := _muzzle_origin()
	for body in _active_bodies:
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue
		var to_body := (body.global_position - muzzle)
		var dist := to_body.length()
		if dist > max_range:
			continue
		# Occlusion check: ray from muzzle to body. If something other than the
		# body itself sits between, the wind is blocked.
		if _ray != null:
			_ray.global_position = muzzle
			_ray.target_position = _ray.to_local(body.global_position)
			_ray.force_raycast_update()
			if _ray.is_colliding() and _ray.get_collider() != body:
				continue
		# Force direction = the operator's aim, NOT straight at the scrap — so the
		# scrap is pushed FORWARD (in the blow direction), the way a real blower works.
		var atten := 1.0 / (1.0 + dist * dist)
		body.apply_central_force(aim * force_mag * atten)
