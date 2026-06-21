extends StaticBody3D
class_name SocketWrench7

## Maat-7 dopsleutel — a 7 mm socket wrench (ratchet + socket) used by the
## operator for pelletizer knife maintenance (#210). On the ground it's a
## StaticBody3D with a proximity prompt; on E it's picked up into the player's
## Inventory hotbar and reparented under Head as a held visual.
##
## This file ONLY implements the item-existence + pickup/drop + held-visual
## contract. The downstream interaction (using the wrench to swap pelletizer
## knives) is a separate UI task tracked under #210; do NOT add it here.
##
## Mirrors the WireCutter / BarcodeScanner pattern exactly:
##   - `tool_id` constant labels the hotbar slot via Inventory.slot_label()
##   - `_pick_up()` checks Inventory.is_full + calls Inventory.take(self)
##   - `_drop()` calls Inventory.remove(self), reparents to scene root, re-
##     enables collision
##   - crosshair_prompt / crosshair_interact wire the F-key prompt + E pickup
##     through PlayerController._update_crosshair_interaction()

## tool_id — used by Inventory.slot_label() to label the hotbar slot.
const tool_id : String = "socket_wrench_7"

const PICKUP_RANGE : float = 1.6

# Held state — null when on the floor, otherwise the player node it's parented under.
var _held_by : Node3D = null

# Player-proximity prompt (only while on the floor).
var _player_near : bool = false
var _player_node : Node = null

# =============================================================================
func _ready() -> void:
	add_to_group("socket_wrench_7")
	_build_visual()
	_build_pickup_trigger()

## Steel handle + chrome ratchet head + short socket at one end. Dimensions
## come from #210b spec: 15 cm handle, 4×2.5×3 cm ratchet head, ø3 cm socket
## 2 cm tall. Sized to look right held in the hand and to fit in a tool
## pouch on the ground.
func _build_visual() -> void:
	# Steel-grey handle material
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.55, 0.57, 0.60)
	steel.metallic = 0.9
	steel.roughness = 0.5
	# Polished chrome for the ratchet head + socket
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.85, 0.86, 0.88)
	chrome.metallic = 1.0
	chrome.roughness = 0.2

	# Handle — 0.02 × 0.02 × 0.15 box, lying along +Z so the head sits at +Z end.
	var handle := MeshInstance3D.new()
	var hm := BoxMesh.new(); hm.size = Vector3(0.02, 0.02, 0.15)
	handle.mesh = hm
	handle.material_override = steel
	handle.position = Vector3(0.0, 0.0, 0.0)
	add_child(handle)

	# Ratchet head — 0.04 × 0.025 × 0.03 box at the +Z end of the handle.
	# Centred on z = +0.075 (handle half-length) + half head depth = +0.090.
	var head := MeshInstance3D.new()
	var headm := BoxMesh.new(); headm.size = Vector3(0.04, 0.025, 0.03)
	head.mesh = headm
	head.material_override = chrome
	head.position = Vector3(0.0, 0.0, 0.090)
	add_child(head)

	# Socket — short cylinder, r=0.015, h=0.02, hanging off the BOTTOM of the
	# ratchet head (visible end where the bolt goes). Cylinder mesh is axis-Y
	# by default, so we leave it upright and drop it half its height below
	# the head's bottom face.
	var socket := MeshInstance3D.new()
	var sm := CylinderMesh.new()
	sm.top_radius = 0.015
	sm.bottom_radius = 0.015
	sm.height = 0.02
	sm.radial_segments = 14
	socket.mesh = sm
	socket.material_override = chrome
	# Head centre y=0 + half head height (-0.0125) - half socket height (-0.01)
	# = -0.0225 puts the socket flush under the head with its tip at y=-0.0325.
	socket.position = Vector3(0.0, -0.0225, 0.090)
	add_child(socket)

	# Small collision so the prop doesn't sink through floors when dropped.
	# Wraps the whole assembly — handle is the longest axis.
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.05, 0.06, 0.20)
	col.shape = bx
	col.position = Vector3(0.0, -0.005, 0.045)
	add_child(col)

func _build_pickup_trigger() -> void:
	InteractionTriggers.make_pickup_trigger(
		self, PICKUP_RANGE, _on_body_entered, _on_body_exited)

# =============================================================================
# PICKUP / DROP (E)
# =============================================================================
func _on_body_entered(body: Node3D) -> void:
	if _held_by != null:
		return
	if body.name != "Player":
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
	# Only react while held AND active in the hotbar. Pickup branch is owned
	# by the crosshair ray (crosshair_interact below).
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return

func crosshair_prompt(_player: Node3D) -> String:
	return "Take Maat-7 dopsleutel" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	# #76 — refuse the grab when the hotbar is full so we don't strand the tool
	# (force-parented under Head in no slot, never active, impossible to drop).
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		var busf := get_node_or_null("/root/EventBus")
		if busf and busf.has_signal("interaction_prompt_show"):
			busf.emit_signal("interaction_prompt_show", self, "Hands full — drop something first")
		return
	_held_by = player
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		# Headless / Inventory-absent fallback — hard-parent under Head.
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		get_parent().remove_child(self)
		parent_node.add_child(self)
	# Position it as a held silhouette — slightly forward + down-right of the
	# camera, head end pointed away from the player (local +Z = ratchet head).
	transform = Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(180.0)),
		Vector3(0.20, -0.18, -0.35))
	# Tool is non-colliding while held (it rides with the player).
	collision_layer = 0
	collision_mask  = 0
	# Drop the prompt — held state no longer has a "Take" hint.
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _drop() -> void:
	if _held_by == null:
		return
	# Inventory releases its slot BEFORE we reparent — otherwise its show/hide
	# pass would keep flipping us invisible after we land on the floor.
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
