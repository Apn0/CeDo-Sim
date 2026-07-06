extends SceneTree
## TEMP smoke test (2026-07-06 new-components batch) — builds every new/rebuilt
## catalog id in both ghost and solid form and reports failures. Run:
##   godot --headless --path . -s res://tests/tmp_build_new_components.gd
## Delete after the batch lands (or keep as a quick regression probe).

func _init() -> void:
	var ids := [
		"bunker", "ms_silo_buiten", "ls_silo_buiten", "kleine_la",
		"tankje_tussen_extruders", "pomp_c1", "pomp_zeefbocht",
		"eop_endpoint", "rafter", "compactor", "cutter_compactor",
	]
	var fails := 0
	for id in ids:
		var item : Dictionary = PlaceableCatalog.get_item(String(id))
		if item.is_empty():
			print("FAIL get_item: ", id)
			fails += 1
			continue
		for ghost in [true, false]:
			var n : Node3D = PlaceableCatalog.build_node(String(id), bool(ghost))
			if n == null:
				print("FAIL build_node(ghost=%s): %s" % [str(ghost), id])
				fails += 1
				continue
			# Ghost-safety probe: no live Area3D, and no collision shapes anywhere
			# (the root is a bare StaticBody3D by convention; ghosts skip its
			# CollisionShape3D — see build_node's `if not ghost:` collision block).
			if bool(ghost):
				var bad := _find_hazards(n)
				if bad > 0:
					print("FAIL ghost has %d live area/collision nodes: %s" % [bad, id])
					fails += 1
			n.free()
		# MachineFlow role sanity.
		var pr : Dictionary = MachineFlow.profile(String(id))
		print("ok %-24s role=%-8s process=%s" % [id, String(pr.get("role","")), String(pr.get("process",""))])
	print("---- smoke done, %d failures ----" % fails)
	quit(1 if fails > 0 else 0)

func _find_hazards(n: Node) -> int:
	var c := 0
	if n is Area3D or n is CollisionShape3D:
		c += 1
	for ch in n.get_children():
		c += _find_hazards(ch)
	return c
