extends Node3D

# 🧪 [testing improvement description]
# 🎯 What: Missing test for HmiScreenBase
# 📊 Coverage: wire_nav and delayed _apply_nav_wiring
# ✨ Result: The test suite now asserts the correct behavior of the base screen component

class CallableBox extends RefCounted:
	var count: int = 0
	func call_me():
		count += 1

func _ready():
	print("TEST_START: test_hmi_screen_base.gd")
	var fails = 0

	# Instantiate the screen base
	var screen_base = preload("res://src/scenes/hud/scopes/HmiScreenBase.gd").new()
	add_child(screen_base)

	# Test 1: Immediate wire_nav when buttons are already available
	print("  Running Test 1: wire_nav with available buttons...")

	var box1 = CallableBox.new()
	var box2 = CallableBox.new()

	var cb1 = Callable(box1, "call_me")
	var cb2 = Callable(box2, "call_me")

	var btn_prev = Button.new()
	var btn_next = Button.new()
	btn_prev.disabled = true
	btn_next.disabled = true

	screen_base._nav_prev_btn = btn_prev
	screen_base._nav_next_btn = btn_next

	screen_base.wire_nav(cb1, cb2)

	if btn_prev.disabled != false:
		print("  FAIL: btn_prev is still disabled")
		fails += 1

	if btn_next.disabled != false:
		print("  FAIL: btn_next is still disabled")
		fails += 1

	if btn_prev.tooltip_text != "vorige unit":
		print("  FAIL: btn_prev tooltip is incorrect")
		fails += 1

	if btn_next.tooltip_text != "volgende unit":
		print("  FAIL: btn_next tooltip is incorrect")
		fails += 1

	if not btn_prev.pressed.is_connected(cb1):
		print("  FAIL: btn_prev pressed is not connected to cb1")
		fails += 1

	if not btn_next.pressed.is_connected(cb2):
		print("  FAIL: btn_next pressed is not connected to cb2")
		fails += 1

	btn_prev.pressed.emit()
	if box1.count != 1:
		print("  FAIL: btn_prev press did not trigger callback")
		fails += 1

	btn_next.pressed.emit()
	if box2.count != 1:
		print("  FAIL: btn_next press did not trigger callback")
		fails += 1

	# Clean up previous buttons
	btn_prev.queue_free()
	btn_next.queue_free()


	# Test 2: Delayed wire_nav when buttons are not yet built
	print("  Running Test 2: delayed wire_nav...")

	var screen_base2 = preload("res://src/scenes/hud/scopes/HmiScreenBase.gd").new()
	add_child(screen_base2)

	var box3 = CallableBox.new()
	var box4 = CallableBox.new()

	var cb3 = Callable(box3, "call_me")
	var cb4 = Callable(box4, "call_me")

	# Wire nav before buttons exist
	screen_base2.wire_nav(cb3, cb4)

	# Now create buttons and call _apply_nav_wiring (simulate what _build_nav_bar does)
	var btn_prev2 = Button.new()
	var btn_next2 = Button.new()
	btn_prev2.disabled = true
	btn_next2.disabled = true

	screen_base2._nav_prev_btn = btn_prev2
	screen_base2._nav_next_btn = btn_next2

	screen_base2._apply_nav_wiring()

	if btn_prev2.disabled != false:
		print("  FAIL: btn_prev2 is still disabled after delayed wiring")
		fails += 1

	if btn_next2.disabled != false:
		print("  FAIL: btn_next2 is still disabled after delayed wiring")
		fails += 1

	if not btn_prev2.pressed.is_connected(cb3):
		print("  FAIL: btn_prev2 pressed is not connected to cb3")
		fails += 1

	if not btn_next2.pressed.is_connected(cb4):
		print("  FAIL: btn_next2 pressed is not connected to cb4")
		fails += 1

	# Test repeated _apply_nav_wiring doesn't reconnect
	screen_base2._apply_nav_wiring()
	var conns = btn_prev2.pressed.get_connections()
	if conns.size() != 1:
		print("  FAIL: Repeated _apply_nav_wiring connected multiple times")
		fails += 1

	btn_prev2.queue_free()
	btn_next2.queue_free()

	screen_base.queue_free()
	screen_base2.queue_free()

	if fails == 0:
		print("TEST_END: PASS")
		get_tree().quit(0)
	else:
		print("TEST_END: FAIL (%d failures)" % fails)
		get_tree().quit(1)
