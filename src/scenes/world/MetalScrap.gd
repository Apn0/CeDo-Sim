extends StaticBody3D
class_name MetalScrap
## Rulings §11 (2026-09-23) — the scrap a line-1 agricultural-film bale can
## hide: "car wheels, plough parts, very sometimes even an anvil, large nails,
## balls of wire, farm scrap". ShredderFeedBelt spawns one on the bale the
## moment its sensor fires (the bale carried `metal_pieces` from BaleDefs), so
## the operator can see what the belt is reversing for. Walk up and press E:
## it goes into the hotbar like any tool, the bale is clean, the belt's alarm
## clears. Drop it (hotbar drop) anywhere — within DUMP_RANGE of a waste
## container it goes INTO the container as METAL (LineFlow's class 3, kg
## conserved), otherwise it lands on the floor as a prop.
##
## Sizes and weights per kind are STATED PLACEHOLDERS (no operator figures).

const tool_id : String = "metal_scrap"
const DUMP_RANGE : float = 3.0
const METAL_DENSITY_KGM3 : float = 4500.0   # LineFlow's METAL class density
const METAL_CLASS : int = 3                  # WasteContainer/LineFlow class id for metal

var kind : String = "wheel"
var kg : float = 10.0
var source_bale : Node3D = null
var belt : Node = null
var _held_by : Node3D = null

func _ready() -> void:
	add_to_group("metal_scrap")
	name = "MetalScrap"
	_build_visual()
	_build_collision()

func _m(c: Color, rough: float, metal: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m

func _mesh(mesh: Mesh, pos: Vector3, mat: StandardMaterial3D, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	add_child(mi)
	return mi

func _build_visual() -> void:
	var rust := _m(Color(0.42, 0.26, 0.16), 0.85, 0.35)
	var steel := _m(Color(0.55, 0.56, 0.58), 0.45, 0.8)
	var rubber := _m(Color(0.10, 0.10, 0.11), 0.9, 0.0)
	match kind:
		"wheel":
			var tyre := CylinderMesh.new()
			tyre.top_radius = 0.28; tyre.bottom_radius = 0.28; tyre.height = 0.18
			_mesh(tyre, Vector3.ZERO, rubber, Vector3(0.0, 0.0, PI * 0.5))
			var rim := CylinderMesh.new()
			rim.top_radius = 0.17; rim.bottom_radius = 0.17; rim.height = 0.20
			_mesh(rim, Vector3.ZERO, steel, Vector3(0.0, 0.0, PI * 0.5))
		"plough_part":
			var blade := BoxMesh.new(); blade.size = Vector3(0.55, 0.06, 0.30)
			_mesh(blade, Vector3.ZERO, rust, Vector3(0.0, 0.0, deg_to_rad(18.0)))
			var shank := BoxMesh.new(); shank.size = Vector3(0.08, 0.30, 0.08)
			_mesh(shank, Vector3(-0.18, 0.15, 0.0), rust)
		"wire_ball":
			var ball := SphereMesh.new(); ball.radius = 0.22; ball.height = 0.44
			_mesh(ball, Vector3.ZERO, _m(Color(0.50, 0.48, 0.42), 0.7, 0.6))
		"nails":
			for i in 6:
				var nail := CylinderMesh.new()
				nail.top_radius = 0.008; nail.bottom_radius = 0.008; nail.height = 0.22
				_mesh(nail, Vector3(-0.08 + 0.032 * i, 0.0, 0.02 * (i % 3)), steel,
					Vector3(0.0, 0.0, deg_to_rad(80.0 + 4.0 * i)))
		_:   # "anvil"
			var base := BoxMesh.new(); base.size = Vector3(0.40, 0.14, 0.22)
			_mesh(base, Vector3(0.0, 0.07, 0.0), steel)
			var top := BoxMesh.new(); top.size = Vector3(0.50, 0.10, 0.14)
			_mesh(top, Vector3(0.0, 0.26, 0.0), steel)
			var horn := CylinderMesh.new()
			horn.top_radius = 0.02; horn.bottom_radius = 0.06; horn.height = 0.22
			_mesh(horn, Vector3(0.34, 0.27, 0.0), steel, Vector3(0.0, 0.0, -PI * 0.5))

func _build_collision() -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.5, 0.3, 0.4)
	cs.shape = bs
	add_child(cs)

## ── crosshair interaction (PlayerController._interactable_from_hit) ─────────
func crosshair_prompt(_player: Node3D) -> String:
	if _held_by != null:
		return ""
	return "Pick up scrap metal (%s, %.0f kg)" % [kind.replace("_", " "), kg]

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
	remove_from_bale()
	if inv and bool(inv.call("take", self)):
		_held_by = player
		collision_layer = 0
		collision_mask = 0

## The bookkeeping of taking the piece OFF its bale, shared by the pick-up and
## by tests (which have no player): the bale loses the piece and its kg, and
## the belt is told so its alarm and lamp clear.
func remove_from_bale() -> void:
	var b := source_bale
	source_bale = null
	if b == null or not is_instance_valid(b):
		return
	var n : int = maxi(int(b.get_meta("metal_pieces", 0)) - 1, 0)
	b.set_meta("metal_pieces", n)
	if b.has_meta("remaining_kg"):
		b.set_meta("remaining_kg", maxf(float(b.get_meta("remaining_kg")) - kg, 0.0))
	if b is RigidBody3D:
		(b as RigidBody3D).mass = maxf((b as RigidBody3D).mass - kg, 1.0)
	if get_parent() == b:
		var world := get_tree().current_scene
		var gp : Vector3 = global_position
		b.remove_child(self)
		if world != null:
			world.add_child(self)
			global_position = gp
	if n <= 0 and belt != null and is_instance_valid(belt) and belt.has_method("metal_cleared"):
		belt.call("metal_cleared", b, kg)

## Hand the piece to a scrap bin (add_scrap) or a waste container (add, as
## METAL). Returns the kg accepted; frees itself when it went in.
func dump_into(target: Node) -> float:
	if target == null or not is_instance_valid(target) or kg <= 0.0:
		return 0.0
	var accepted := 0.0
	if target.has_method("add_scrap"):
		accepted = float(target.call("add_scrap", kg, kind))
	elif target.has_method("add"):
		target.call("add", kg, METAL_DENSITY_KGM3, METAL_CLASS)
		accepted = kg
	if accepted > 0.0:
		var inv := get_node_or_null("/root/Inventory")
		if inv and _held_by != null:
			inv.call("remove", self)
		queue_free()
	return accepted

## Hotbar drop (PlayerController calls _drop on the active tool).
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
	# Rulings §20: the scrap bin by the belt first…
	var best : Node = null
	var best_d : float = DUMP_RANGE
	for c in get_tree().get_nodes_in_group("scrap_bin"):
		if c is Node3D and c.has_method("add_scrap"):
			var d0 : float = (c as Node3D).global_position.distance_to(drop_world)
			if d0 < best_d:
				best_d = d0
				best = c
	if best != null:
		var got0 : float = dump_into(best)
		print("[MetalScrap] %s (%.0f kg) into the scrap bin %s" % [kind, got0, best.name])
		return
	# …else a waste container when one is close: the metal is conserved there.
	best_d = DUMP_RANGE
	for c in get_tree().get_nodes_in_group("waste_container"):
		if c is Node3D and c.has_method("add"):
			var d : float = (c as Node3D).global_position.distance_to(drop_world)
			if d < best_d:
				best_d = d
				best = c
	if best != null:
		best.call("add", kg, METAL_DENSITY_KGM3, METAL_CLASS)
		print("[MetalScrap] %s (%.0f kg) dumped into %s" % [kind, kg, best.name])
		queue_free()
		return
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask = 1
