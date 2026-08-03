extends SceneTree

## #224 — StaticMerge unit test.
## Run headless: godot --headless --path <proj> --script src/tests/test_static_merge.gd
##
## Proves the static-mesh baker:
##   A. collapses static parts into ONE MeshInstance3D ("StaticMerged");
##   B. groups by material LOOK — two red boxes (distinct material objects, same
##      colour) + one blue box -> exactly 2 surfaces;
##   C. preserves triangle geometry (3 boxes = 36 triangles total);
##   D. leaves DYNAMIC parts untouched: a mesh under a "mechanism" node, a mesh
##      tagged set_meta("comp",...), and a GPUParticles3D all survive;
##   E. removes the original static meshes from the tree (draw-call drop).

const StaticMerge = preload("res://src/build/StaticMerge.gd")

var _fails : int = 0
func _ok(c: bool, label: String) -> void:
	if c: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

func _std(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	return m

func _box(parent: Node3D, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1, 1, 1)
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _initialize() -> void:
	print("[TEST] #224 static-merge")
	var root := Node3D.new()
	root.name = "Machine"
	get_root().add_child(root)

	# 3 static boxes: two RED (distinct material objects, same look) + one BLUE.
	_box(root, _std(Color(1, 0, 0)), Vector3(0, 0, 0))
	_box(root, _std(Color(1, 0, 0)), Vector3(2, 0, 0))
	_box(root, _std(Color(0, 0, 1)), Vector3(4, 0, 0))

	# Dynamic: a "mechanism" node with a rotor mesh under it (must survive).
	var mech := Node3D.new()
	mech.add_to_group("mechanism")
	root.add_child(mech)
	var rotor := _box(mech, _std(Color(1, 1, 0)), Vector3(0, 2, 0))
	rotor.name = "Rotor"

	# Dynamic: a mesh tagged as a named component (must survive).
	var comp := _box(root, _std(Color(0, 1, 0)), Vector3(6, 0, 0))
	comp.name = "CompPart"
	comp.set_meta("comp", "scraper")

	# Dynamic: a particle system (must survive).
	var fx := GPUParticles3D.new()
	fx.name = "Steam"
	root.add_child(fx)

	var mesh_children_before := 0
	for c in root.get_children():
		if c is MeshInstance3D: mesh_children_before += 1
	_ok(mesh_children_before == 4, "before: 4 direct MeshInstance3D under root (3 static + comp) — got %d" % mesh_children_before)

	# ── merge ──
	StaticMerge.merge_static(root)

	# A/B: one merged node, exactly 2 surfaces (red look collapsed, blue separate).
	var merged : MeshInstance3D = root.get_node_or_null("StaticMerged") as MeshInstance3D
	_ok(merged != null and merged.mesh != null, "A merged 'StaticMerged' MeshInstance3D exists")
	if merged != null and merged.mesh != null:
		_ok(merged.mesh.get_surface_count() == 2, "B 2 surfaces (red+red collapsed, blue) — got %d" % merged.mesh.get_surface_count())
		var tris := 0
		for s in merged.mesh.get_surface_count():
			var arrs : Array = merged.mesh.surface_get_arrays(s)
			var idx = arrs[Mesh.ARRAY_INDEX]
			if idx != null and idx.size() > 0:
				tris += idx.size() / 3
			else:
				tris += (arrs[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
		_ok(tris == 36, "C triangle geometry preserved (3 boxes = 36 tris) — got %d" % tris)

	# D: dynamics preserved.
	_ok(is_instance_valid(rotor) and rotor.get_parent() == mech, "D1 rotor under 'mechanism' preserved")
	_ok(is_instance_valid(comp) and comp.get_parent() == root, "D2 comp-tagged mesh preserved")
	_ok(is_instance_valid(fx) and fx.get_parent() == root, "D3 particle system preserved")

	# E: the 3 static boxes were removed from the tree (draw-call drop).
	var static_left := 0
	for c in root.get_children():
		if c is MeshInstance3D and c.name != "StaticMerged": static_left += 1
	# only the comp mesh should remain as a direct MeshInstance3D child (dynamic).
	_ok(static_left == 1, "E only the dynamic comp mesh remains direct (statics removed) — got %d" % static_left)

	if _fails == 0:
		print("[TEST] #224 static-merge PASS")
	else:
		print("[TEST] #224 static-merge FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
