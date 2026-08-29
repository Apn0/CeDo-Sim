extends SceneTree

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var Door = load("res://src/build/Door.gd")
	var root = get_root()
	var door = Door.new()
	root.add_child(door)

	print("Test 1: Guard clause - pivot is null")
	var door_no_pivot = Door.new()
	door_no_pivot._is_open = false
	door_no_pivot._moving = false
	door_no_pivot.toggle()
	if door_no_pivot._moving or door_no_pivot._is_open:
		print("FAIL: Door moved or opened despite null pivot")
		quit(1)
		return
	door_no_pivot.free()

	print("Test 2: Guard clause - already moving")
	door._is_open = false
	door._moving = true
	door.toggle()
	if door._is_open:
		print("FAIL: Door opened despite already moving")
		quit(1)
		return

	print("Test 3: Standard toggle (Open)")
	door._moving = false
	door._is_open = false
	door.toggle()
	if not door._is_open or not door._moving:
		print("FAIL: Door failed to open")
		quit(1)
		return

	print("Test 4: Standard toggle (Close)")
	door._moving = false
	door._is_open = true
	door.toggle()
	if door._is_open or not door._moving:
		print("FAIL: Door failed to close")
		quit(1)
		return

	print("PASS: All tests completed successfully")
	quit(0)
