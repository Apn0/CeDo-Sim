extends StaticBody3D
class_name ShovelTool

## A holdable SHOVEL for housekeeping the floor piles that build up under chutes
## (#154). Real flow: a chute reject heaps up on the floor → the operator parks a
## container nearby, picks up the shovel (E), walks to the heap, and LEFT-CLICKS
## to scoop it a shovelful at a time into the container (or just clears it if no
## bin is in reach). Same pickup/hold/drop UX as the WireCutter.

## tool_id — used by Inventory.slot_label() to label the hotbar slot.
const tool_id : String = "shovel"

const PICKUP_RANGE   : float = 1.6
const SCOOP_RANGE    : float = 2.2     # how close to the heap you must stand
const DEPOSIT_RANGE  : float = 3.0     # a bin this close catches the scoop
const SCOOP_KG       : float = 25.0    # mass lifted per scoop
const SCOOP_COOLDOWN : float = 0.4

var _held_by   : Node3D = null
var _last_scoop: float  = 0.0
var _player_near : bool = false
var _player_node : Node = null

# =============================================================================
func _ready() -> void:
	add_to_group("shovel_tool")
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.55, 0.40, 0.22); wood.roughness = 0.8
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.78); steel.metallic = 0.8; steel.roughness = 0.3
	# Shaft
	var shaft := MeshInstance3D.new()
	var sm := CylinderMesh.new(); sm.top_radius = 0.025; sm.bottom_radius = 0.025
	sm.height = 0.95; sm.radial_segments = 10
	shaft.mesh = sm; shaft.material_override = wood
	shaft.position = Vector3(0, 0, 0.1)
	shaft.rotation.x = deg_to_rad(90.0)
	add_child(shaft)
	# Blade (a slightly dished box at the front)
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.26, 0.04, 0.30)
	blade.mesh = bm; blade.material_override = steel
	blade.position = Vector3(0, 0, -0.5)
	add_child(blade)
	# Base collision so it rests on the floor.
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.28, 0.1, 1.1)
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

# =============================================================================
# PICKUP / DROP (E)
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
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tool_use"):
		scoop_once()
		get_viewport().set_input_as_handled()
		return

func crosshair_prompt(player: Node3D) -> String:
	return "Take shovel" if _held_by == null and _player_near else ""

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
	transform = Transform3D(Basis(), Vector3(0.24, -0.20, -0.45))
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

# =============================================================================
# USE — scoop one shovelful from the nearest heap into a nearby container
# =============================================================================
## Lift up to SCOOP_KG from the nearest floor pile in reach and tip it into the
## nearest waste container in reach (or discard it if none). Returns kg moved.
## Public + side-effect-only so a headless test can call it directly.
func scoop_once() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_scoop < SCOOP_COOLDOWN:
		return 0.0
	var pile := _nearest_in_group("floor_pile", SCOOP_RANGE, true)
	if pile == null:
		return 0.0
	var got : float = pile.call("scoop", SCOOP_KG)
	if got <= 0.0:
		return 0.0
	_last_scoop = now
	# Deposit into a bin if one is parked in reach; else it's tossed clear.
	var bin := _nearest_in_group("waste_container", DEPOSIT_RANGE, false)
	if bin != null and bin.has_method("add"):
		bin.call("add", got, 200.0, -1)
	return got

## Nearest node of `group` within `range_m`. When `need_mass`, only piles that
## actually hold material qualify (skip empty zones).
func _nearest_in_group(group: String, range_m: float, need_mass: bool) -> Node:
	var origin := global_position
	var best : Node = null
	var best_d := range_m
	for n in get_tree().get_nodes_in_group(group):
		var nn := n as Node3D
		if nn == null:
			continue
		if need_mass and float(nn.get("mass_kg")) <= 0.0:
			continue
		var d := nn.global_position.distance_to(origin)
		if d < best_d:
			best_d = d
			best = n
	return best
