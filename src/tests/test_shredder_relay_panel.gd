extends SceneTree

var _pass := 0
var _fail := 0

func _init() -> void:
	print("=== SHREDDER RELAY PANEL TESTS ===")

	test_initialization()
	test_public_api()
	test_input_handling()

	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)

func _ok(condition: bool, text: String) -> void:
	if condition:
		_pass += 1
		print("  ok    : " + text)
	else:
		_fail += 1
		print("  FAIL  : " + text)

func _fail_msg(text: String) -> void:
	_fail += 1
	print("  FAIL  : " + text)

func test_initialization():
	var Panel = load("res://src/scenes/hud/panels/ShredderRelayPanel.gd")
	var p = Panel.new()
	_ok(p != null, "ShredderRelayPanel instantiates successfully")

	p._build()
	_ok(p.get_child_count() > 0, "_build() populates the node")
	_ok(p.key_position == 0, "initial key position is AUTO (0)")

	p.free()

func test_public_api():
	var Panel = load("res://src/scenes/hud/panels/ShredderRelayPanel.gd")
	var p = Panel.new()
	p._build()

	_ok(p.running == false, "initial running state is false")
	p.set_running(true)
	_ok(p.running == true, "set_running(true) updates running state")

	_ok(p.e_stop_active == false, "initial e_stop_active state is false")
	p.set_e_stop(true)
	_ok(p.e_stop_active == true, "set_e_stop(true) updates e_stop_active state")

	p.set_key_position(1)
	_ok(p.key_position == 1, "set_key_position(1) updates key position")

	p.free()

func test_input_handling():
	var Panel = load("res://src/scenes/hud/panels/ShredderRelayPanel.gd")
	var p = Panel.new()
	p._build()

	# We need to test the signal emissions
	var _state = {
		"start_pressed": false,
		"stop_pressed": false,
		"request_close": false,
		"key_position": -1,
	}

	p.start_pressed.connect(func(): _state["start_pressed"] = true)
	p.stop_pressed.connect(func(): _state["stop_pressed"] = true)
	p.request_close.connect(func(): _state["request_close"] = true)
	p.key_position_changed.connect(func(pos): _state["key_position"] = pos)

	var mb = InputEventMouseButton.new()
	mb.button_index = MOUSE_BUTTON_LEFT
	mb.pressed = true

	# Test key switch cycle
	p._on_key_widget_input(mb)
	_ok(p.key_position == 1, "key widget input cycles from AUTO (0) to HAND (1)")
	_ok(_state["key_position"] == 1, "key widget input emits key_position_changed signal")

	p._on_key_widget_input(mb)
	_ok(p.key_position == 2, "key widget input cycles from HAND (1) to ONDERHOUD (2)")

	p._on_key_widget_input(mb)
	_ok(p.key_position == 0, "key widget input cycles from ONDERHOUD (2) back to AUTO (0)")

	# Test start button
	p._on_start_widget_input(mb)
	_ok(_state["start_pressed"], "start button input emits start_pressed signal when in AUTO mode")
	_state["start_pressed"] = false

	# Test start button blocked by non-AUTO mode
	p.set_key_position(1)
	p._on_start_widget_input(mb)
	_ok(not _state["start_pressed"], "start button input does not emit start_pressed when in HAND mode")
	_ok(p._flash_active, "start button in wrong mode sets _flash_active to true")

	# Test start button blocked by e-stop
	p.set_key_position(0)
	p.set_e_stop(true)
	p._flash_active = false
	p._on_start_widget_input(mb)
	_ok(not _state["start_pressed"], "start button input does not emit start_pressed when e-stop is active")
	_ok(not p._flash_active, "start button with e-stop active does not trigger flashing")

	# Test stop button
	p._on_stop_widget_input(mb)
	_ok(_state["stop_pressed"], "stop button input always emits stop_pressed signal")

	# Test close button
	p._on_close_pressed()
	_ok(_state["request_close"], "close button pressed emits request_close signal")

	p.free()
