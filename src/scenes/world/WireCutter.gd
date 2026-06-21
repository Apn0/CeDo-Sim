extends StaticBody3D
class_name WireCutter

## The "concrete scissors" / wire cutter — a holdable tool for cutting the iron
## wires on bales. Real flow: the operator parks a clamped bale, EXITS the cab,
## walks over to the scissors, picks them up (E), walks to a bale, LEFT-CLICKS
## once per wire (3 wires per bale), then walks back to re-enter the clamp and
## place + open the bale.

## tool_id — used by Inventory.slot_label() to label the hotbar slot.
const tool_id : String = "scissors"
##
## On the ground the tool is a StaticBody3D with a proximity Area3D + interact
## prompt. On pickup it reparents under the player's head as a held visual (so
## it bobs around with the player's view). E again drops it back on the floor.
## While held, "tool_use" (left mouse button on foot) cuts ONE wire on the
## nearest bale within reach.
##
## When all 3 wires are cut the bale's "wires_cut" meta flips to true, and the
## BaleClamp's existing _on_released hook fans the sheets into the open arc on
## the next release. Per-wire cutting means each bale needs 3 separate clicks —
## the wires fall away one by one as you cut them.

const PICKUP_RANGE   : float = 1.6
const CUT_RANGE      : float = 1.8     # how close to the bale you must stand
const CUT_COOLDOWN_S : float = 0.35    # one cut per ~third of a second

# Held state — null when on the floor, otherwise the player node it's parented under.
var _held_by   : Node3D = null
var _last_cut  : float  = 0.0

# Player-proximity prompt (only while on the floor).
var _player_near : bool = false
var _player_node : Node = null

# =============================================================================
func _ready() -> void:
	add_to_group("wire_cutter")
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	# Concrete-scissors silhouette: a long red handle pair + chrome jaws.
	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.78, 0.14, 0.10)
	red.roughness = 0.6
	var chrome := StandardMaterial3D.new()
	chrome.albedo_color = Color(0.78, 0.80, 0.82)
	chrome.metallic = 0.85
	chrome.roughness = 0.18
	# Two handles (slightly diverging)
	for sx in [-0.04, 0.04]:
		var handle := MeshInstance3D.new()
		var hm := BoxMesh.new(); hm.size = Vector3(0.05, 0.05, 0.7)
		handle.mesh = hm; handle.material_override = red
		handle.position = Vector3(sx, 0.0, -0.32)
		add_child(handle)
	# Hinge bolt
	var hinge := MeshInstance3D.new()
	var hc := CylinderMesh.new(); hc.top_radius = 0.04; hc.bottom_radius = 0.04
	hc.height = 0.12; hc.radial_segments = 10
	hinge.mesh = hc; hinge.material_override = chrome
	add_child(hinge)
	# Two jaws (the cutting heads) — flared blocks
	for sx in [-0.05, 0.05]:
		var jaw := MeshInstance3D.new()
		var jm := BoxMesh.new(); jm.size = Vector3(0.06, 0.06, 0.34)
		jaw.mesh = jm; jaw.material_override = chrome
		jaw.position = Vector3(sx, 0.0, 0.20)
		add_child(jaw)
	# A small base collision so the prop doesn't fall through the floor.
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.16, 0.1, 0.85)
	col.shape = bx
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
	# Pickup branch (on the floor) is handled by the player's crosshair ray.
	if _held_by == null:
		return
	# Held branch — E drops, tool_use cuts. BUT we only react when this tool is
	# the ACTIVE one in inventory; otherwise the player is holding (e.g.) the
	# scanner and pressing E should not drop the holstered scissors.
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("tool_use"):
		_try_cut_nearest()
		get_viewport().set_input_as_handled()
		return

func crosshair_prompt(_player: Node3D) -> String:
	return "Take wire-cutter" if _held_by == null and _player_near else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and _player_near:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	# Refuse the grab when the hotbar is full — otherwise take() fails and the
	# tool ends up force-parented under Head in no slot, never active, impossible
	# to drop (the stuck state). Leave it on the floor and prompt the player.
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		var busf := get_node_or_null("/root/EventBus")
		if busf and busf.has_signal("interaction_prompt_show"):
			busf.emit_signal("interaction_prompt_show", self, "Hands full — drop something first")
		return
	_held_by = player
	# Inventory takes care of reparenting under Head + show/hide bookkeeping;
	# if for whatever reason Inventory isn't available (e.g. headless test
	# without the autoload), fall back to the old hard-parent behaviour so the
	# tool still works.
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		get_parent().remove_child(self)
		parent_node.add_child(self)
	# Position it slightly forward + down-right of the camera as a held silhouette.
	# Rotated 180° around UP so the JAWS point AWAY from the player (the local
	# +Z of the scissor mesh is the cutting end — without the 180° flip it would
	# end up in the player's face, with the handles sticking out the front).
	transform = Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(165.0)),
		Vector3(0.22, -0.18, -0.4))
	# Tool is non-colliding while held (it rides with the player). Inventory
	# may further toggle this when the slot becomes inactive.
	collision_layer = 0
	collision_mask  = 0
	# Drop the prompt — held state no longer has a "Take" hint.
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

func _drop() -> void:
	if _held_by == null:
		return
	# Inventory needs to release its slot before we reparent — otherwise its
	# show/hide pass would keep flipping us invisible after we land on the floor.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	# Re-parent back to the scene root at the player's current position, dropped
	# slightly in front and at floor level. Collision re-enabled.
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
# USE — cut one wire on the nearest bale
# =============================================================================
func _try_cut_nearest() -> void:
	# Throttle so a held key/click doesn't shred all 3 wires instantly.
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_cut < CUT_COOLDOWN_S:
		return
	# PRECISE cut (#6): raycast from the operator's view and cut ONLY the wire BAND the
	# crosshair is actually on. Pointing between bands cuts nothing, and re-clicking the
	# same spot can't shred the others — you must aim at each wire separately.
	var cam : Camera3D = null
	if _held_by:
		cam = _held_by.get_node_or_null("Head/Camera3D") as Camera3D
	if cam == null:
		return
	var from := cam.global_position
	var to := from - cam.global_transform.basis.z * CUT_RANGE
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.exclude = [get_rid()]
	if _held_by is PhysicsBody3D:
		q.exclude = [get_rid(), (_held_by as PhysicsBody3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return
	# Climb to the bale the ray struck.
	var bale : Node3D = null
	var n : Node = hit.get("collider")
	while n != null:
		if n is Node3D and (n as Node).is_in_group("bale"):
			bale = n as Node3D
			break
		n = n.get_parent()
	if bale == null or bool(bale.get_meta("wires_cut", false)):
		return
	var wires := bale.find_child("Wires", true, false)
	if wires == null:
		return
	# Pick the wire whose band (its local Z position) the hit point is closest to —
	# you have to put the crosshair ON that wire. Within ~18 cm counts as on it.
	var hit_local : Vector3 = (bale as Node3D).to_local(hit.get("position"))
	var best_wire : Node = null
	var best_dz := 0.18
	for wire in wires.get_children():
		if not (wire is Node3D):
			continue
		var dz : float = absf((wire as Node3D).position.z - hit_local.z)
		if dz < best_dz:
			best_dz = dz
			best_wire = wire
	if best_wire == null:
		return   # aimed between wires — nothing cut
	best_wire.queue_free()
	_last_cut = now
	# If that was the last wire, flip wires_cut (deferred, after the free settles).
	call_deferred("_recheck_all_cut", bale)

func _recheck_all_cut(bale: Node3D) -> void:
	if bale == null or not is_instance_valid(bale):
		return
	var wires := bale.find_child("Wires", true, false)
	if wires == null or wires.get_child_count() == 0:
		bale.set_meta("wires_cut", true)
