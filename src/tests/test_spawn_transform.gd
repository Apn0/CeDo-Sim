extends Node3D

# =============================================================================
# RULED-OUT HYPOTHESIS — kept as a guard, not as a fix.
#
# Operator report 2026-07-20 (NPC bench): a spawned film-scrap pile / bale clamp
# lands in the exact centre of the middle shredder whatever he aims at.
#
# The first hypothesis was that every spawn path does
#     parent.add_child(node); node.global_position = target
# and that a placeable whose ROOT is a plain Node3D with RigidBody3D CHILDREN
# would strand those children at the world origin, because they register with
# the physics server on tree-entry and a later root move wouldn't carry them.
# The bench's world origin is 0.44 m from the middle shredder's centre, which
# fitted the report exactly.
#
# THIS TEST DISPROVED THAT. On Godot 4.6.3 both orderings land the bodies within
# ~0.8 m of the aim point (pile radius ~1 m). The ordering is NOT the bug, so the
# ordering was left alone.
#
# The real cause was found by reading BuildMode._raycast(): it aimed along
# whatever camera was `current`, and NpcTaskBench's O key makes a STATIC
# ObserverCam current — one fixed ray, so every kind lands on one fixed point.
# Fixed in BuildMode._aim_camera(), which always aims with the player's camera.
#
# This test stays so the ordering hypothesis is not re-litigated, and so we find
# out if a future engine version DOES start stranding physics children.
#
#   Godot --headless --path . src/tests/test_spawn_transform.tscn
# =============================================================================

const TARGET := Vector3(17.0, 0.0, -23.0)
const PILE_ID := "film_scrap_pile"
const TOL_M := 3.0          # pile scatter radius is ~1 m

var _ok := 0
var _fail := 0

func _ready() -> void:
	await get_tree().process_frame
	await get_tree().physics_frame

	var root_a := Node3D.new()
	var root_b := Node3D.new()
	add_child(root_a)
	add_child(root_b)

	# Ordering A — add first, then move (what the shipping code does).
	var node_a : Node3D = PlaceableCatalog.build_node(PILE_ID, false, false)
	root_a.add_child(node_a)
	node_a.global_position = TARGET

	# Ordering B — transform first, then add.
	var node_b : Node3D = PlaceableCatalog.build_node(PILE_ID, false, false)
	node_b.position = root_b.to_local(TARGET)
	root_b.add_child(node_b)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var bodies_a := _bodies(node_a)
	var bodies_b := _bodies(node_b)

	print("\n[spawn transform] pile '%s' — %d RigidBody3D children per pile"
		% [PILE_ID, bodies_b.size()])
	# Non-vacuous guard: with zero bodies both orderings would trivially "pass".
	_check(bodies_b.size() > 0,
		"the pile really does have RigidBody3D children (%d)" % bodies_b.size())

	var da := _mean_dist_to(bodies_a, TARGET)
	var db := _mean_dist_to(bodies_b, TARGET)
	var oa := _mean_dist_to(bodies_a, Vector3.ZERO)
	print("  add-then-move : mean %.2f m from aim point, %.2f m from origin" % [da, oa])
	print("  move-then-add : mean %.2f m from aim point" % db)

	_check(da < TOL_M,
		"add-then-move carries its physics children (%.2f m) — ordering is NOT the bug" % da)
	_check(db < TOL_M,
		"move-then-add carries its physics children (%.2f m)" % db)
	_check(oa > 5.0,
		"CONTROL: the bodies are genuinely away from the origin (%.2f m), so the check can fail" % oa)

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_ok, _fail])
	print("=========================================")
	get_tree().quit(1 if _fail > 0 else 0)

func _bodies(root: Node) -> Array[Node3D]:
	var out : Array[Node3D] = []
	var stack : Array[Node] = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		if n is RigidBody3D:
			out.append(n as Node3D)
		for c in n.get_children():
			stack.append(c)
	return out

func _mean_dist_to(bodies: Array[Node3D], p: Vector3) -> float:
	if bodies.is_empty():
		return -1.0
	var total := 0.0
	for b in bodies:
		total += b.global_position.distance_to(p)
	return total / float(bodies.size())

func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  ok   : %s" % msg)
	else:
		_fail += 1
		print("  FAIL : %s" % msg)
