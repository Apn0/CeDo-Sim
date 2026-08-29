extends SceneTree

func _initialize() -> void:
	var Door = load("res://src/build/Door.gd")
	var root = get_root()
	var door = Door.new()
	root.add_child(door)

	# Test 1: Null player, but not near, expect ""
	door._player_near = false
	door._moving = false
	door._is_open = false

	var prompt_null = door.crosshair_prompt(null)
	if prompt_null != "":
		print("FAIL: Expected empty prompt for null player when not near, got '%s'" % prompt_null)
		quit(1)
		return

	print("PASS: crosshair_prompt handles null player correctly")

	# Test 2: Null player, but near, expect prompt
	door._player_near = true
	door._moving = false
	door._is_open = false

	var prompt_null_near = door.crosshair_prompt(null)
	if prompt_null_near != "Open door   ·   [Tab] then [X] to remove":
		print("FAIL: Expected 'Open door...', got '%s'" % prompt_null_near)
		quit(1)
		return

	print("PASS: crosshair_prompt handles null player correctly when near")

	quit(0)
