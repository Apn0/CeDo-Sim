extends SceneTree
## Headless verification for ExtruderBluPortScope.

const ExtruderBluPortScope = preload("res://src/scenes/hud/scopes/ExtruderBluPortScope.gd")

var _pass := 0
var _fail := 0

class MockExtruderModel extends Object:
	var melt_temp := 195.0
	var screw_rpm := 120.0
	var throughput_kg_h := 800.0
	var runtime_s := 3600.0 * 2.5 # 2.5 h
	var motor_torque_pct := 75.0
	var die_pressure_psi := 1450.4 # 100 bar
	var primary_suction_pct := 0.45
	var primary_pot_fill_kg := 25.0
	var config: Dictionary = {"screw_rpm_nominal": 150.0}
	var state := 2 # RUNNING

	func get_zone_temp(_z: int) -> float:
		return 200.0

class MockExtruderModelAlarm extends Object:
	var melt_temp := 195.0
	var screw_rpm := 120.0
	var throughput_kg_h := 800.0
	var runtime_s := 3600.0 * 2.5
	var motor_torque_pct := 75.0
	var die_pressure_psi := 1450.4
	var primary_suction_pct := 0.45
	var primary_pot_fill_kg := 25.0
	var config: Dictionary = {"screw_rpm_nominal": 150.0}
	var state := 2

	# ZONE_ALARM_LOW_C = 180, ZONE_ALARM_HIGH_C = 230
	func get_zone_temp(_z: int) -> float:
		return 240.0 # Alarm!

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _init() -> void:
	print("=== ExtruderBluPortScope initialization verification ===")

	var scope = ExtruderBluPortScope.new()
	# Manually call ready for headless mode
	scope._ready()

	_ok(scope._title_plate != null, "Title plate is initialized")
	_ok(scope._title_plate.text == "LIJN 3C", "Default line_id is 3C")
	_ok(scope._numpad_panel != null, "Numpad panel is initialized")
	_ok(scope._numpad_panel.visible == false, "Numpad is hidden for line 3C")

	# Test line ID change
	scope.set_line_id("6")
	_ok(scope.line_id == "6", "Line ID changed to 6")
	_ok(scope._title_plate.text == "LIJN 6", "Title plate updated for line 6")
	_ok(scope._numpad_panel.visible == true, "Numpad is visible for line 6")

	# Mock data binding
	var model = MockExtruderModel.new()
	scope.set_model(model)

	# Simulate processing to sample telemetry and update rails
	scope._process(0.1)

	_ok(scope._rail_values.size() > 0, "Rail values populated")
	_ok(scope._rail_values["melt_temp"].text == "195", "Melt temp formatting correct")
	_ok(scope._rail_values["screw_rpm"].text == "120", "Screw rpm formatting correct")
	_ok(scope._rail_values["load_pct"].text == "75", "Load pct formatting correct")
	_ok(scope._rail_values["runtime_h"].text == "2.5", "Runtime formatting correct")
	_ok(scope._rail_values["melt_pressure"].text == "100.0", "Melt pressure conversion and formatting correct")
	_ok(scope._rail_values["throughput_kg_h"].text == "800", "Throughput formatting correct")

	_ok(scope._right_value_lbls["pcu_vulpeil"].text == "250", "PCU vulpeil correctly multiplied by 10")
	_ok(scope._right_value_lbls["pes_toerental"].text == "80", "PES toerental correctly calculated (120/150 * 100)")

	# Check schematic labels
	var iz1_label: Label = scope._schematic_value_lbls["ex1_iz1_temp"]["value"]
	_ok(iz1_label.text == "200  °C", "IZ1 temp label value correct")
	_ok(iz1_label.get_theme_color("font_color") == scope.COL_TEXT, "IZ1 temp label in normal range uses COL_TEXT")

	# Check alarm state
	var model_alarm = MockExtruderModelAlarm.new()
	scope.set_model(model_alarm)
	scope._process(0.1)
	_ok(iz1_label.text == "240  °C", "IZ1 temp label value updated to alarm state")
	_ok(iz1_label.get_theme_color("font_color") == scope.COL_ALARM, "IZ1 temp label in alarm range uses COL_ALARM")

	scope.free()
	model.free()
	model_alarm.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	quit(0 if _fail == 0 else 1)
