extends SceneTree
## Headless test for WallOpenings
##
## Run: godot --headless --path . --script res://src/tests/test_wall_openings.gd --quit-after 10

const WallOpenings = preload("res://src/build/WallOpenings.gd")

func _init() -> void:
	print("\n[Test] Starting WallOpenings tests...")

	var openings = WallOpenings.new()

	# Test 1: has_opening on an empty collection
	assert(not openings.has_opening("test_id"), "Expected false for missing ID")

	# Test 2: Add an opening and check if it has it
	# We modify the private `_openings` dictionary directly for this test
	openings._openings["test_id"] = {"center": Vector3.ZERO, "size": Vector3.ONE, "rot_y": 0.0}
	assert(openings.has_opening("test_id"), "Expected true for existing ID")

	# Test 3: Remove opening and check again
	# We manually erase it rather than calling remove_opening which requires a cached shell
	openings._openings.erase("test_id")
	assert(not openings.has_opening("test_id"), "Expected false after manually erasing ID")

	openings.free()


	# Test 4: setup() with empty mesh
	var empty_mesh = MeshInstance3D.new()
	var openings2 = WallOpenings.new()
	openings2.setup(empty_mesh)
	assert(openings2._ready_ok == false, "Expected setup to fail with no mesh")

	# Test 5: setup() with valid mesh
	var valid_mesh = MeshInstance3D.new()
	var array_mesh = ArrayMesh.new()
	var arrays = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(0, 1, 0)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	valid_mesh.mesh = array_mesh

	var openings3 = WallOpenings.new()
	# Without adding to tree, rebuild() will fall back to identity transform
	openings3.setup(valid_mesh)
	assert(openings3._ready_ok == true, "Expected setup to succeed with valid mesh")
	assert(openings3._orig_surfaces.size() == 1, "Expected 1 original surface")

	# Test 6: setup() with thin_collision_source
	var thin_mesh = ArrayMesh.new()
	var thin_arrays = []
	thin_arrays.resize(Mesh.ARRAY_MAX)
	thin_arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array([Vector3(0, 0, 0), Vector3(2, 0, 0), Vector3(0, 2, 0)])
	thin_arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2])
	thin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, thin_arrays)

	var openings4 = WallOpenings.new()
	openings4.solidify_enabled = false
	openings4.setup(valid_mesh, thin_mesh)
	assert(openings4._ready_ok == true, "Expected setup to succeed with thin collision source")

	# Verify that the collision surfaces are from the thin mesh
	assert(openings4._orig_surfaces.size() == 1, "Expected 1 original surface from thin mesh")
	var thin_verts = openings4._orig_surfaces[0]["v"]
	assert(thin_verts[1] == Vector3(2, 0, 0), "Expected vertex from thin mesh")

	# Verify that the visual surfaces are from the shell mesh
	assert(openings4._visual_surfaces.size() == 1, "Expected 1 visual surface from shell mesh")
	var vis_verts = openings4._visual_surfaces[0]["v"]
	assert(vis_verts[1] == Vector3(1, 0, 0), "Expected vertex from shell mesh")

	empty_mesh.free()
	valid_mesh.free()
	openings2.free()
	openings3.free()
	openings4.free()

	print("[Test] All WallOpenings tests passed!\n")
	quit(0)
