extends Node

const CustomizerScript = preload("res://src/scenes/hud/CharacterCustomizer.gd")

var _fails : int = 0
func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

class QuietCustomizer extends CustomizerScript:
	var committed = false

	func _ready() -> void:
		# Override _ready to bypass complex UI/3D setup which times out in headless
		pass

	func _commit_to_gamestate():
		committed = true

func _ready() -> void:
	print("[TEST] CharacterCustomizer open/close API")

	# Test 1: Open sets tree paused and changes mouse mode
	var cust = QuietCustomizer.new()
	add_child(cust) # Add to tree so get_tree() is valid

	var initial_paused = get_tree().paused
	var initial_mouse_mode = Input.mouse_mode

	cust.open()

	_check(get_tree().paused == true, "Open pauses the tree")
	_check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Open sets mouse mode to visible")

	# Test 2: Close(false) cancels and reverts state
	var cancelled_emitted = false
	cust.cancelled.connect(func(): cancelled_emitted = true)

	cust.close(false)

	_check(cancelled_emitted, "Close(false) emits cancelled signal")
	_check(get_tree().paused == initial_paused, "Close(false) reverts tree paused state")
	_check(Input.mouse_mode == initial_mouse_mode, "Close(false) reverts mouse mode")
	_check(not cust.committed, "Close(false) does not commit to gamestate")

	# Wait for queue_free to process
	await get_tree().process_frame
	_check(not is_instance_valid(cust), "Close(false) frees the customizer")

	# Test 3: Close(true) commits and emits saved
	var cust2 = QuietCustomizer.new()
	add_child(cust2)
	cust2.open() # Need to open to set _was_paused and _prev_mouse_mode

	var saved_emitted = false
	cust2.saved.connect(func(app): saved_emitted = true)

	cust2.close(true)

	_check(saved_emitted, "Close(true) emits saved signal")
	_check(cust2.committed, "Close(true) commits to gamestate")

	# Wait for queue_free to process
	await get_tree().process_frame
	_check(not is_instance_valid(cust2), "Close(true) frees the customizer")

	if _fails == 0:
		print("[TEST] CharacterCustomizer PASS")
	else:
		print("[TEST] CharacterCustomizer FAIL (%d)" % _fails)

	get_tree().quit(0 if _fails == 0 else 1)
