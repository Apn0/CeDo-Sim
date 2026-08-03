extends SceneTree
## Proof of the two MAJOR bughunt fixes on the elevated extruder_silo (2026-07-17):
##  1. StaticMerge no longer eats the support legs — machine_leg MeshInstances
##     must SURVIVE the static merge so extend_machine_legs can floor them.
##  2. Collision leaves the ~2.6 m walk-under clearance OPEN — the low bay between
##     the legs must NOT be filled by a solid AABB (was one big box 0..6.5 m).
## Run: Godot_v4.6.3_console --headless --path <proj> --script res://test_silo_legs_clearance.gd

var _ran := false

func _count_group_meshes(n: Node, grp: String) -> int:
	var c := 0
	if n is MeshInstance3D and n.is_in_group(grp):
		c += 1
	for ch in n.get_children():
		c += _count_group_meshes(ch, grp)
	return c

func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	var root := get_root()
	var body := PlaceableCatalog.build_node("extruder_silo", false, false)
	root.add_child(body)

	var fails := 0

	# (1) Legs survive the merge.
	var legs := _count_group_meshes(body, "machine_leg")
	if legs > 0:
		print("  OK  : %d machine_leg meshes survived StaticMerge (extend_machine_legs can floor them)" % legs)
	else:
		print("  FAIL: 0 machine_leg meshes survived — merge ate them, raised silo floats"); fails += 1

	# (2) Clearance open. Gather the body's own CollisionShape3D boxes and check
	#     that NONE of them occupies the walk-under bay: a box counts as blocking
	#     if it is wide (footprint > 1 m in both X and Z) AND its bottom reaches
	#     below 1.5 m. The legitimate silo BODY box sits up high (bottom ~2.6 m).
	var blockers := 0
	var box_count := 0
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			box_count += 1
			var sz : Vector3 = ((c as CollisionShape3D).shape as BoxShape3D).size
			var cy : float = (c as CollisionShape3D).position.y
			var bottom : float = cy - sz.y * 0.5
			var wide : bool = sz.x > 1.0 and sz.z > 1.0
			if wide and bottom < 1.5:
				blockers += 1
	if box_count >= 5 and blockers == 0:
		print("  OK  : %d collision boxes, none fills the low clearance (walk-under open)" % box_count)
	else:
		print("  FAIL: %d boxes, %d block the clearance (solid AABB under the silo)" % [box_count, blockers]); fails += 1

	print("=== SILO LEGS + CLEARANCE TEST: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true
