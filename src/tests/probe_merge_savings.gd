extends SceneTree

## #224 — measure the static-merge draw-call reduction on REAL machine models.
## Builds each machine's visual model both ways (raw parts vs merged) and reports
## the MeshInstance3D count (≈ draw calls) + triangle count. Proves detail can go
## up while draw calls go down.
##   godot --headless --path <proj> --script src/tests/probe_merge_savings.gd

const PC = preload("res://src/build/PlaceableCatalog.gd")
const StaticMerge = preload("res://src/build/StaticMerge.gd")

func _meshes(n: Node) -> int:
	var c := 0
	for ch in n.get_children():
		if ch is MeshInstance3D:
			c += 1
		c += _meshes(ch)
	return c

func _tris(n: Node) -> int:
	var t := 0
	for ch in n.get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh != null:
			var m : Mesh = (ch as MeshInstance3D).mesh
			for s in m.get_surface_count():
				var a : Array = m.surface_get_arrays(s)
				var idx = a[Mesh.ARRAY_INDEX]
				if idx != null and idx.size() > 0:
					t += idx.size() / 3
				elif a[Mesh.ARRAY_VERTEX] != null:
					t += (a[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		t += _tris(ch)
	return t

func _initialize() -> void:
	print("[PROBE] static-merge savings on real machines")
	var ids : Array = ["mengsilo", "flotation_tank", "mech_dryer", "shredder_1",
		"frictiewasser", "cyclone", "trilzeef", "rafter", "voorraad_silo", "centrifuge"]
	var tot_b := 0
	var tot_a := 0
	print("  %-18s  meshes b->a     tris b->a" % "id")
	for id in ids:
		var item : Dictionary = PC.get_item(id)
		if item.is_empty():
			continue
		var m := Node3D.new()
		get_root().add_child(m)
		PC._build_model(m, id, String(item.get("category", "")),
			item.get("size", Vector3.ONE), item.get("color", Color.WHITE), false)
		var mb := _meshes(m)
		var tb := _tris(m)
		StaticMerge.merge_static(m)
		var ma := _meshes(m)
		var ta := _tris(m)
		tot_b += mb
		tot_a += ma
		print("  %-18s  %4d -> %-4d    %6d -> %d" % [id, mb, ma, tb, ta])
		m.free()
	var pct : float = 100.0 * float(tot_b - tot_a) / float(max(tot_b, 1))
	print("  TOTAL draw-call meshes: %d -> %d  (%.0f%% fewer)" % [tot_b, tot_a, pct])
	quit(0)
