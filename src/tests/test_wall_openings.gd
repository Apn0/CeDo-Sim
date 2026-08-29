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

	print("[Test] All WallOpenings tests passed!\n")
	quit(0)
