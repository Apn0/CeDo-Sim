extends StaticBody3D
class_name MeltBlock
## P3 stage B (2026-09-24) — the block of melt the operator scrapes free inside
## a vacuum pot and lifts out by hand (rulings §14): "take the block out … and
## place or throw it anywhere: the ground, a container, the lump pile under a
## filling cart, into the lump cart if there is room". Spawned by
## VacuumPotService.complete_lid_pull inside the pot (hidden until the lid is
## off); freed by the plamuurmes work; taken through the pot's crosshair body
## into the hotbar like any tool. Dropped (hotbar drop) within DUMP_RANGE of a
## lump cart with room it goes in as lumps, else into a waste container as
## lumps, else it lands on the floor as a prop. Mass conserved: kg = the pot's
## fill at the moment the lid came off.

const tool_id : String = "melt_block"
const DUMP_RANGE : float = 3.0

var kg : float = 0.0
var pot_name : String = ""
var size_m : float = 0.14
var free : bool = false          # released by the plamuurmes work
var _held_by : Node3D = null

func _ready() -> void:
	add_to_group("melt_block")
	name = "MeltBlock"
	_build_visual()

func _build_visual() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.13, 0.12, 0.11)
	m.roughness = 0.35
	m.metallic = 0.05
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size_m, size_m * 0.9, size_m)
	mi.mesh = bm
	mi.material_override = m
	add_child(mi)
	var crust := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(size_m * 0.7, size_m * 0.12, size_m * 0.7)
	crust.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.32, 0.27, 0.20)
	cmat.roughness = 0.9
	crust.material_override = cmat
	crust.position = Vector3(0.0, size_m * 0.5, 0.0)
	add_child(crust)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size_m, size_m * 0.9, size_m)
	cs.shape = bs
	add_child(cs)

## ── on the floor: crosshair pickup like any tool ─────────────────────────────
func crosshair_prompt(_player: Node3D) -> String:
	if _held_by != null or not free:
		return ""
	return "Pick up the melt block (%.1f kg)" % kg

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null and free:
		pick_up(player)

func pick_up(player: Node3D) -> bool:
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		var busf := get_node_or_null("/root/EventBus")
		if busf and busf.has_signal("interaction_prompt_show"):
			busf.emit_signal("interaction_prompt_show", self, "Hands full — drop something first")
		return false
	if inv and bool(inv.call("take", self)):
		_held_by = player
		collision_layer = 0
		collision_mask = 0
		return true
	return false

## Hand the block's mass to a lump cart (receive_lump) or a waste container
## (receive_lumps). Returns the kg accepted; frees itself when everything went.
func dump_into(target: Node) -> float:
	if target == null or not is_instance_valid(target) or kg <= 0.0:
		return 0.0
	var accepted := 0.0
	if target.has_method("receive_lump"):
		var left : float = float(target.call("receive_lump", kg))
		accepted = kg - left
	elif target.has_method("receive_lumps"):
		var left2 : float = float(target.call("receive_lumps", kg))
		accepted = kg - left2
	kg -= accepted
	if kg <= 0.01:
		var inv := get_node_or_null("/root/Inventory")
		if inv and _held_by != null:
			inv.call("remove", self)
		queue_free()
	return accepted

## Hotbar drop (PlayerController calls _drop on the active tool).
func _drop() -> void:
	if _held_by == null:
		return
	var player := _held_by
	var drop_world : Vector3 = player.global_transform * Vector3(0.0, -0.6, -0.8)
	# a lump cart with room first (his "into the lump cart if there is room")
	var best : Node = null
	var best_d : float = DUMP_RANGE
	for c in get_tree().get_nodes_in_group("lump_cart"):
		if c is Node3D and c.has_method("receive_lump") and not (c.has_method("is_full") and bool(c.call("is_full"))):
			var d : float = (c as Node3D).global_position.distance_to(drop_world)
			if d < best_d:
				best_d = d
				best = c
	if best == null:
		best_d = DUMP_RANGE
		for c in get_tree().get_nodes_in_group("waste_container"):
			if c is Node3D and c.has_method("receive_lumps"):
				var d2 : float = (c as Node3D).global_position.distance_to(drop_world)
				if d2 < best_d:
					best_d = d2
					best = c
	if best != null:
		var got : float = dump_into(best)
		print("[MeltBlock] %.1f kg of pot melt into %s" % [got, best.name])
		if kg <= 0.01:
			return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	_held_by = null
	var scene_root := get_tree().current_scene
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask = 1
