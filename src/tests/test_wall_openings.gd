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

	# Test 4: _solidify_surfaces with empty array
	var res1 = openings._solidify_surfaces([])
	assert(res1.size() == 0, "Expected empty array for empty input")

	# Test 5: _solidify_surfaces with empty surface
	var res2 = openings._solidify_surfaces([{"v": PackedVector3Array()}])
	assert(res2.size() == 1 and res2[0]["v"].size() == 0, "Expected empty surface for empty input surface")

	# Test 6: _solidify_surfaces with degenerate triangle (area ~ 0)
	var res3 = openings._solidify_surfaces([{"v": PackedVector3Array([Vector3.ZERO, Vector3.ZERO, Vector3.ZERO])}])
	assert(res3.size() == 1 and res3[0]["v"].size() == 0, "Expected empty surface for degenerate triangle")

	# Test 7: _solidify_surfaces with valid triangle
	var res4 = openings._solidify_surfaces([{"v": PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)])}])
	assert(res4.size() == 1 and res4[0]["v"].size() == 24, "Expected 24 vertices for a single valid triangle (front, back, and 3 rim quads)")

	openings.free()

	print("[Test] All WallOpenings tests passed!\n")
	quit(0)
