extends StaticBody3D
class_name PlamuurmesTool
## Plamuurmes (putty knife) — the tool the operator clears a vacuum pot's four
## inner planes with (rulings 2026-09-23 §14, P3 stage B). Same item contract
## as SocketWrench7: a StaticBody3D prop on the floor with a crosshair prompt,
## E takes it into the Inventory hotbar (tool_id labels the slot), hotbar drop
## returns it to the floor. The pushing itself lives in VacuumPotInteract,
## which only checks that this tool is the ACTIVE slot.

const tool_id : String = "tool_plamuurmes"

var _held_by : Node3D = null

func _ready() -> void:
	add_to_group("tool_plamuurmes")
	_build_visual()

func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.72, 0.74, 0.76)
	steel.metallic = 0.9
	steel.roughness = 0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.45, 0.30, 0.16)
	wood.roughness = 0.8
	# flat flexible blade, 10 cm wide, along +Z
	var blade := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.10, 0.0025, 0.13)
	blade.mesh = bm
	blade.material_override = steel
	blade.position = Vector3(0.0, 0.0, 0.085)
	add_child(blade)
	# ferrule + handle behind it
	var ferrule := MeshInstance3D.new()
	var fm := CylinderMesh.new()
	fm.top_radius = 0.014
	fm.bottom_radius = 0.016
	fm.height = 0.03
	ferrule.mesh = fm
	ferrule.material_override = steel
	ferrule.position = Vector3(0.0, 0.0, 0.005)
	ferrule.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	add_child(ferrule)
	var handle := MeshInstance3D.new()
	var hm := CylinderMesh.new()
	hm.top_radius = 0.016
	hm.bottom_radius = 0.019
	hm.height = 0.12
	handle.mesh = hm
	handle.material_override = wood
	handle.position = Vector3(0.0, 0.0, -0.07)
	handle.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	add_child(handle)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.10, 0.04, 0.28)
	col.shape = bx
	col.position = Vector3(0.0, 0.0, 0.01)
	add_child(col)

func crosshair_prompt(_player: Node3D) -> String:
	return "Take the plamuurmes (putty knife)" if _held_by == null else ""

func crosshair_interact(player: Node3D) -> void:
	if _held_by == null:
		_pick_up(player)

func _pick_up(player: Node3D) -> void:
	var inv := get_node_or_null("/root/Inventory")
	if inv and bool(inv.call("is_full")):
		var busf := get_node_or_null("/root/EventBus")
		if busf and busf.has_signal("interaction_prompt_show"):
			busf.emit_signal("interaction_prompt_show", self, "Hands full — drop something first")
		return
	if inv and bool(inv.call("take", self)):
		_held_by = player
		transform = Transform3D(Basis().rotated(Vector3.UP, deg_to_rad(180.0)), Vector3(0.20, -0.18, -0.35))
		collision_layer = 0
		collision_mask = 0
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
	_held_by = null
	var scene_root := get_tree().current_scene
	var drop_world : Vector3 = player.global_transform * Vector3(0.0, -0.6, -0.8)
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	rotation = Vector3.ZERO
	visible = true
	collision_layer = 1
	collision_mask = 1
