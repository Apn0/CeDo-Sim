extends Node3D
const ScadaDashboard := preload("res://src/scenes/hud/ScadaDashboard.gd")

var _pass := 0
var _fail := 0

# Mock time tracker
var _mock_time := 0.0

func _ok(condition: bool, msg: String) -> void:
	if condition:
		_pass += 1
		print("  [OK] %s" % msg)
	else:
		_fail += 1
		printerr("  [FAIL] %s" % msg)

func _mock_time_s() -> float:
	return _mock_time

func _ready() -> void:
	print("--- test_scada_dashboard ---")

	_check_initialization()
	_check_parameters()
	_check_state_and_microstop()

	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)


func _check_initialization() -> void:
	print("\n-- A. Initialization --")
	var dash = ScadaDashboard.new()
	# Inject mock time
	dash.set_time_source(Callable(self, "_mock_time_s"))

	add_child(dash) # This triggers _ready() which triggers _build_ui()

	# Verify root panel is created and visible
	_ok(dash._root_panel != null, "Root panel is created programmatically")
	_ok(dash.is_shutdown_visible() == false, "Dashboard is visible (is_shutdown_visible is false)")

	# State label should be populated and state should be "Idle" by default
	_ok(dash.get_state() == "Idle", "Default state is Idle")
	_ok(dash._state_label != null and dash._state_label.text == "IDLE", "State label correctly displays IDLE")

	# Initial micro-stop count is 0
	_ok(dash.micro_stop_count() == 0, "Initial micro-stop count is 0")

	dash.queue_free()

func _check_parameters() -> void:
	print("\n-- B. Parameters --")
	var dash = ScadaDashboard.new()
	dash.set_time_source(Callable(self, "_mock_time_s"))
	add_child(dash)

	# Test set_param normal value
	dash.set_param("pressure", 5.0, 0.0, 10.0, "Pressure")
	_ok(dash.is_param_alarming("pressure") == false, "Pressure 5.0 in [0, 10] is not alarming")
	var p_row = dash._param_rows["pressure"]
	_ok(p_row["name_lbl"].text == "Pressure", "Label correctly set to Pressure")
	_ok(p_row["value_lbl"].text == "5", "Value label correctly formats 5")
	_ok(p_row["value_lbl"].get_theme_color("font_color") == ScadaDashboard.COL_GREY_TEXT, "Nominal value is grey")

	# Test set_param high alarm
	dash.set_param("pressure", 12.0, 0.0, 10.0, "Pressure")
	_ok(dash.is_param_alarming("pressure") == true, "Pressure 12.0 in [0, 10] IS alarming")
	_ok(p_row["value_lbl"].text == "12", "Value label updates to 12")
	_ok(p_row["value_lbl"].get_theme_color("font_color") == ScadaDashboard.COL_ALARM_HI, "High alarm is red (COL_ALARM_HI)")

	# Test set_param low alarm
	dash.set_param("temp", -5.0, 0.0, 100.0, "Temperature")
	_ok(dash.is_param_alarming("temp") == true, "Temperature -5.0 in [0, 100] IS alarming")
	var t_row = dash._param_rows["temp"]
	_ok(t_row["value_lbl"].get_theme_color("font_color") == ScadaDashboard.COL_ALARM_LO, "Low alarm is amber (COL_ALARM_LO)")

	# Test set_text_param normal
	dash.set_text_param("status", "OK", false, "System Status")
	_ok(dash.is_param_alarming("status") == false, "Text param not alarming")
	var s_row = dash._param_rows["status"]
	_ok(s_row["value_lbl"].text == "OK", "Text param displays text correctly")
	_ok(s_row["value_lbl"].get_theme_color("font_color") == ScadaDashboard.COL_GREY_TEXT, "Nominal text is grey")

	# Test set_text_param alarm
	dash.set_text_param("status", "FAULT", true, "System Status")
	_ok(dash.is_param_alarming("status") == true, "Text param IS alarming")
	_ok(s_row["value_lbl"].text == "FAULT", "Text param updates text correctly")
	_ok(s_row["value_lbl"].get_theme_color("font_color") == ScadaDashboard.COL_ALARM_HI, "Alarm text is red (COL_ALARM_HI)")

	dash.queue_free()

func _check_state_and_microstop() -> void:
	print("\n-- C. State & Micro-stops --")
	var dash = ScadaDashboard.new()
	dash.set_time_source(Callable(self, "_mock_time_s"))
	add_child(dash)

	# Time 0
	_mock_time = 0.0

	# Set to running
	var logged = dash.set_state("Running")
	_ok(logged == false, "Initial transition to Running doesn't log a micro-stop")
	_ok(dash.get_state() == "Running", "State is Running")
	_ok(dash._state_label.get_theme_color("font_color") == ScadaDashboard.COL_GREY_TEXT, "Running state label is grey")

	# Time 10.0: Transition to Idle
	_mock_time = 10.0
	logged = dash.set_state("Idle")
	_ok(logged == false, "Transition to Idle doesn't immediately log a micro-stop")
	_ok(dash._state_label.get_theme_color("font_color") == ScadaDashboard.COL_STATE_BAD, "Idle state label is amber (COL_STATE_BAD)")

	# Time 40.0: Transition to Running (Idle duration: 30s)
	# 30s < MICRO_STOP_WINDOW_S (60s) -> Should log a micro-stop
	_mock_time = 40.0
	logged = dash.set_state("Running")
	_ok(logged == true, "Transition back to Running < 60s logs a micro-stop")
	_ok(dash.micro_stop_count() == 1, "Micro-stop count is 1")

	# Time 100.0: Transition to Idle
	_mock_time = 100.0
	dash.set_state("Idle")

	# Time 200.0: Transition to Running (Idle duration: 100s)
	# 100s > MICRO_STOP_WINDOW_S (60s) -> Should NOT log a micro-stop
	_mock_time = 200.0
	logged = dash.set_state("Running")
	_ok(logged == false, "Transition back to Running > 60s DOES NOT log a micro-stop")
	_ok(dash.micro_stop_count() == 1, "Micro-stop count is still 1")

	dash.queue_free()
