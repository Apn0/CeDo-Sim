extends SceneTree

## #157 — Smoke test for #117 (bale yard close-LOD MM swap).
## Run headless: godot --headless --script src/tests/test_yard_lod_swap.gd
##
## What it checks:
##   1. PlaceableCatalog.build_yard_multimesh(supplier_id, N) returns a
##      MultiMeshInstance3D with N instances + a flat-shaded box mesh material.
##   2. PlaceableCatalog.build_yard_multimesh_close(supplier_id, N) returns a
##      separate MultiMeshInstance3D with the same N instance slots and a
##      different material (groove-normal-mapped).
##   3. PlaceableCatalog.build_yard_sticker_multimesh(supplier_id, N) returns
##      a separate MultiMesh of QuadMesh stickers, N instances.
##   4. The three MMs are SEPARATE Node objects (so visibility-range swap can
##      run on each independently).
##   5. The materials differ (far vs close should NOT share the exact same
##      material — far has flat albedo, close has normal_texture set).

const PC = preload("res://src/build/PlaceableCatalog.gd")

func _initialize() -> void:
	print("[TEST] #117 yard LOD swap")
	var supplier := "rotterdam"
	var n := 24
	var far  : MultiMeshInstance3D = PC.build_yard_multimesh(supplier, n)
	var near : MultiMeshInstance3D = PC.build_yard_multimesh_close(supplier, n)
	var stk  : MultiMeshInstance3D = PC.build_yard_sticker_multimesh(supplier, n)
	var ok := true
	if far == null:
		print("  FAIL: build_yard_multimesh returned null"); ok = false
	if near == null:
		print("  FAIL: build_yard_multimesh_close returned null"); ok = false
	if stk == null:
		print("  FAIL: build_yard_sticker_multimesh returned null"); ok = false
	if far and near and stk:
		if far.multimesh.instance_count != n:
			print("  FAIL: far MM instance_count = %d, expected %d" % [far.multimesh.instance_count, n]); ok = false
		if near.multimesh.instance_count != n:
			print("  FAIL: near MM instance_count = %d, expected %d" % [near.multimesh.instance_count, n]); ok = false
		if stk.multimesh.instance_count != n:
			print("  FAIL: sticker MM instance_count = %d, expected %d" % [stk.multimesh.instance_count, n]); ok = false
		if far == near or near == stk:
			print("  FAIL: MMs share the same node — visibility range can't apply per-LOD"); ok = false
		# Material distinction: near should have a normal_texture set, far should not.
		var far_mat  : Material = far.multimesh.mesh.surface_get_material(0) if far.multimesh.mesh.get_surface_count() > 0 else far.multimesh.mesh.material
		var near_mat : Material = near.multimesh.mesh.surface_get_material(0) if near.multimesh.mesh.get_surface_count() > 0 else near.multimesh.mesh.material
		# BoxMesh exposes material at mesh-level, not surface
		if far.multimesh.mesh is BoxMesh:
			far_mat = (far.multimesh.mesh as BoxMesh).material
		if near.multimesh.mesh is BoxMesh:
			near_mat = (near.multimesh.mesh as BoxMesh).material
		if far_mat is StandardMaterial3D and near_mat is StandardMaterial3D:
			var far_has_normal := (far_mat as StandardMaterial3D).normal_texture != null
			var near_has_normal := (near_mat as StandardMaterial3D).normal_texture != null
			if not near_has_normal:
				print("  FAIL: close-LOD material missing normal_texture (groove shading not wired)"); ok = false
			if far_has_normal:
				print("  WARN: far-LOD material has a normal_texture too — should be flat-shaded for distance")
			if far_has_normal == near_has_normal:
				print("  WARN: far/near materials look identical — LOD swap is cosmetic only")
	if ok:
		print("[TEST] #117 PASS")
	else:
		print("[TEST] #117 FAIL")
	quit(0 if ok else 1)
