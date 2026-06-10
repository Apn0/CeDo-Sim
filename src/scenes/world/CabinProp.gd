extends StaticBody3D
class_name CabinProp

## A personal cabin item the operator can carry and set down on real surfaces /
## snap points inside a vehicle — a coffee cup (goes in the cup holder), a
## sandwich (on the seat / dash), etc. Same pickup-and-hold contract as the
## scissors/scanner so it composes with Inventory + the tool-placement mode
## (#122): pick up with E, swap to it on the hotbar, press G to place it into a
## matching cabin slot. The cup holder only accepts a "coffee" (slot `accepts`
## meta filter — see ToolPlacementMode).

@export var prop_kind : String = "coffee"   # "coffee" | "sandwich"
const PICKUP_RANGE : float = 1.2

var tool_id      : String = "coffee"   # set from prop_kind; Inventory reads this
var _held_by     : Node3D = null
var _player_near : bool   = false
var _player_node : Node   = null

# =============================================================================
func _ready() -> void:
	add_to_group("cabin_prop")
	tool_id = prop_kind
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	match prop_kind:
		"sandwich":
			_build_sandwich()
		_:
			_build_coffee()
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.12, 0.14, 0.12)
	col.shape = bx
	col.position = Vector3(0, 0.07, 0)
	add_child(col)

func _build_coffee() -> void:
	var cup_mat := StandardMaterial3D.new()
	cup_mat.albedo_color = Color(0.92, 0.90, 0.86); cup_mat.roughness = 0.7
	var lid_mat := StandardMaterial3D.new()
	lid_mat.albedo_color = Color(0.10, 0.10, 0.12); lid_mat.roughness = 0.6
	var cup := MeshInstance3D.new()
	var cm := CylinderMesh.new(); cm.top_radius = 0.045; cm.bottom_radius = 0.035; cm.height = 0.11
	cup.mesh = cm; cup.material_override = cup_mat
	cup.position = Vector3(0, 0.055, 0)
	add_child(cup)
	var lid := MeshInstance3D.new()
	var lm := CylinderMesh.new(); lm.top_radius = 0.05; lm.bottom_radius = 0.05; lm.height = 0.02
	lid.mesh = lm; lid.material_override = lid_mat
	lid.position = Vector3(0, 0.12, 0)
	add_child(lid)

func _build_sandwich() -> void:
	var bread := StandardMaterial3D.new()
	bread.albedo_color = Color(0.85, 0.72, 0.45); bread.roughness = 0.9
	var filling := StandardMaterial3D.new()
	filling.albedo_color = Color(0.40, 0.62, 0.30); filling.roughness = 0.9
	# Two bread triangles (boxes) with a filling layer between — a cut sandwich.
	var bottom := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.16, 0.025, 0.11)
	bottom.mesh = bm; bottom.material_override = bread
	bottom.position = Vector3(0, 0.02, 0)
	add_child(bottom)
	var fill := MeshInstance3D.new()
	var fm := BoxMesh.new(); fm.size = Vector3(0.165, 0.02, 0.115)
	fill.mesh = fm; fill.material_override = filling
	fill.position = Vector3(0, 0.04, 0)
	add_child(fill)
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new(); tm.size = Vector3(0.16, 0.025, 0.11)
	top.mesh = tm; top.material_override = bread
	top.position = Vector3(0, 0.06, 0)
	add_child(top)

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
# PICKUP / DROP  (mirror of LabelItem — routes through Inventory when present)
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
	_emit_prompt_hide()

func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()

func crosshair_prompt(_player: Node3D) -> String:
	return ("Take %s" % prop_kind) if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	var inv := get_node_or_null("/root/Inventory")
	# Refuse the grab when the hotbar is full — otherwise take() fails and the
	# prop ends up force-parented under Head in no slot, never active, impossible
	# to drop (the stuck state). Leave it on the floor and prompt the player.
	if inv and bool(inv.call("is_full")):
		_emit_prompt("Hands full — drop something first")
		return
	_held_by = player
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		if get_parent():
			get_parent().remove_child(self)
		parent_node.add_child(self)
	transform = Transform3D(Basis(), Vector3(0.18, -0.16, -0.32))
	collision_layer = 0
	collision_mask  = 0
	_emit_prompt_hide()

func _drop() -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	var player := _held_by
	var scene_root := get_tree().current_scene
	var drop_world := player.global_transform * Vector3(0.0, -0.5, -0.7)
	if get_parent():
		get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask  = 1
	_held_by = null

func _emit_prompt(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)
