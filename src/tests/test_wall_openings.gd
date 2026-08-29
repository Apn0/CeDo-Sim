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

	# Test 4: _would_cut_anything
	# We mock a shell and its original surfaces.
	var shell = MeshInstance3D.new()
	# The method uses _shell.global_transform if inside tree, otherwise IDENTITY.
	# We will not put it in the tree, so it uses Transform3D.IDENTITY
	openings._shell = shell

	# Create a simple triangle: a wall section standing on the X-axis from x=-5 to x=5, height 5 (at Z=0).
	var wall_tri = {
		"v": PackedVector3Array([
			Vector3(-5, 0, 0),
			Vector3(5, 0, 0),
			Vector3(0, 5, 0)
		]),
		"n": PackedVector3Array([Vector3.BACK, Vector3.BACK, Vector3.BACK])
	}
	openings._orig_surfaces = [wall_tri]

	# Box intersecting the triangle
	assert(openings._would_cut_anything(Vector3(0, 2, 0), Vector3(2, 2, 2), 0.0), "Expected true for intersecting box")

	# Box far away
	assert(not openings._would_cut_anything(Vector3(10, 10, 10), Vector3(1, 1, 1), 0.0), "Expected false for distant box")

	# Box offset in Z so it doesn't touch the wall at Z=0
	assert(not openings._would_cut_anything(Vector3(0, 2, 5), Vector3(2, 2, 2), 0.0), "Expected false for Z-offset box")

	# Rotated box check (if we rotate the box, it might or might not intersect).
	# A box that would intersect the edge if placed straight, let's see.
	# The wall triangle is at Z=0.
	assert(openings._would_cut_anything(Vector3(4, 0, 0), Vector3(2, 2, 2), 0.0), "Expected true for edge intersection")

	shell.free()
	openings.free()

	print("[Test] All WallOpenings tests passed!\n")
	quit(0)
