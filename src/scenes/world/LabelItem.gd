extends StaticBody3D
class_name LabelItem

## A detached label — what you get after RMB-peeling one off a bale or
## container with the barcode scanner. Pick-up with E goes through the same
## Inventory path as scissors/scanner. The held visual is a paper card with a
## printed barcode + text on it. Useful for re-labelling a stripped bale or
## moving a tag from one buffer to another.
##
## DATA: `label_info` is a Dictionary the scanner peeled off the original
## host's "Label" child. We keep the host's name for context. Nothing else
## modifies these — they're a snapshot of what was on the source object at
## the moment of peel.

const tool_id : String = "label"
const PICKUP_RANGE : float = 1.4

var label_info       : Dictionary = {}
var origin_host_name : String = ""

var _held_by     : Node3D = null
var _player_near : bool   = false
var _player_node : Node   = null

# =============================================================================
func _ready() -> void:
	add_to_group("label_item")
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	var card := StandardMaterial3D.new()
	card.albedo_color = Color(0.93, 0.82, 0.15)   # yellow shipping label
	card.roughness = 0.85
	# The visible card
	var quad := MeshInstance3D.new()
	var qm := BoxMesh.new(); qm.size = Vector3(0.16, 0.10, 0.005)
	quad.mesh = qm
	quad.material_override = card
	add_child(quad)
	# Barcode stripes — six thin black bars on the card face
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.05, 0.05, 0.05)
	for i in range(6):
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new(); sm.size = Vector3(0.008, 0.05, 0.006)
		stripe.mesh = sm
		stripe.material_override = ink
		stripe.position = Vector3(-0.05 + i * 0.02, 0.005, 0.0)
		add_child(stripe)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.18, 0.12, 0.02)
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

func _on_body_entered(body: Node3D) -> void:
	if _held_by != null:
		return
	if body.name != "Player":
		return
	_player_near = true
	_player_node = body
	_emit_prompt("Take label — %s" % origin_host_name)

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	_emit_prompt_hide()

func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		if _player_near and event.is_action_pressed("interact"):
			_pick_up(_player_node)
			get_viewport().set_input_as_handled()
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return

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
	# Held: forward-facing card just below the camera.
	transform = Transform3D(Basis(), Vector3(0.16, -0.16, -0.32))
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

# =============================================================================
# STATIC HELPER — build a stuck-on label visual for a host node. Used by
# PlaceableCatalog for bales/containers; the scanner reads its `label_info`
# meta. Re-usable for any other entity that wants a peelable tag later.
# =============================================================================
static func attach_to(host: Node3D, info: Dictionary, local_position: Vector3, local_basis: Basis = Basis(), card_color: Color = Color(0.93, 0.82, 0.15)) -> Node3D:
	if host == null:
		return null
	if host.get_node_or_null("Label") != null:
		return host.get_node_or_null("Label")
	var label := MeshInstance3D.new()
	label.name = "Label"
	var card := StandardMaterial3D.new()
	# Default is the YELLOW shipping label (real bales carry a yellow sticker
	# with the barcode — the operator asked us to use THAT rather than an extra
	# white card). Caller can override card_color for other label kinds.
	card.albedo_color = card_color
	card.roughness = 0.85
	# Slightly larger than the held LabelItem so it's readable from a step or two away.
	var qm := BoxMesh.new(); qm.size = Vector3(0.22, 0.14, 0.005)
	label.mesh = qm
	label.material_override = card
	label.transform = Transform3D(local_basis, local_position)
	# Barcode stripes as child quads — same look as LabelItem.
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.05, 0.05, 0.05)
	for i in range(7):
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new(); sm.size = Vector3(0.010, 0.07, 0.006)
		stripe.mesh = sm
		stripe.material_override = ink
		stripe.position = Vector3(-0.07 + i * 0.022, 0.005, 0.0)
		label.add_child(stripe)
	label.set_meta("label_info", info)
	host.add_child(label)
	return label
