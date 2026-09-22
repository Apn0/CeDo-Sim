extends SceneTree
## Headless test suite for universal HMI setpoints and sensor convergence
## Run: godot --headless --path . --script res://src/tests/test_hmi_universal_interactive.gd --quit-after 300

const OverlayScript := preload("res://src/scenes/hud/HmiWebOverlay.gd")
const ExtruderConfigScript := preload("res://src/sim/ExtruderConfig.gd")
const ExtruderModelScript := preload("res://src/sim/ExtruderModel.gd")
const CutterCompactorScript := preload("res://src/sim/CutterCompactor.gd")

var _pass := 0
var _fail := 0
var _ran := false

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_tests()
	return false

func _run_tests() -> void:
	print("=== Universal Interactive HMI Setpoints & Telemetry Convergence Tests ===")

	var overlay := OverlayScript.new()
	root.add_child(overlay)
	overlay._current_screen = "EREMA Extruder Scherm 3C.dc.html"

	var lf := MockLineFlow.new()
	root.add_child(lf)
	lf.add_to_group("line_flow")

	var cc = CutterCompactorScript.new("test_cc")
	lf.active_cc = cc

	# Create a mock ExtruderMachine in group "extruder_machine"
	var em_node := MockExtruderMachine.new()
	var cfg = ExtruderConfigScript.new()
	var ex_model = ExtruderModelScript.new(cfg)
	ex_model.state = ExtruderModelScript.State.RUNNING
	em_node.model = ex_model
	em_node.add_to_group("extruder_machine")
	root.add_child(em_node)

	# ── 1. Initial gather_vals on Extruder screen ────────────────────────
	print("Test 1: Extruder telemetry structure")
	var v : Dictionary = overlay.gather_vals()
	_ok(not v.is_empty(), "gather_vals returns data")
	_ok(v.has("extruder"), "payload contains 'extruder'")
	var ext : Dictionary = v.get("extruder", {})
	_ok(ext.size() == 13, "all 13 extruder process channels gathered (got %d)" % ext.size())

	var expected_channels := [
		"schuif", "ex_belasting", "extr_rpm", "sv_temperatuur",
		"ez_1", "zz_1", "zz_2", "zz_3", "sv_vulpeil",
		"afzuiging_1", "afzuiging_2", "sv_belasting", "sv_vermogen"
	]
	var all_present := true
	for ch in expected_channels:
		if not ext.has(ch):
			all_present = false
			break
	_ok(all_present, "all 13 expected channels present in extruder dict")

	# Check channel sub-structure {actual, setpoint, unit}
	var rpm_data : Dictionary = ext.get("extr_rpm", {})
	_ok(rpm_data.has("actual") and rpm_data.has("setpoint") and rpm_data.has("unit"),
		"extr_rpm contains actual, setpoint, and unit")
	_ok(String(rpm_data.get("unit", "")) == "rpm", "extr_rpm unit == 'rpm'")

	# ── 2. IPC setpoint update for extruder RPM ───────────────────────────
	print("Test 2: Update screw RPM setpoint via IPC")
	overlay._on_ipc(JSON.stringify({
		"type": "set_setpoint",
		"screen": "EREMA Extruder Scherm 3C.dc.html",
		"channel": "extr_rpm",
		"value": 145.0,
		"unit": "rpm"
	}))
	_ok(float(overlay._setpoints.get("extr_rpm", 0.0)) == 145.0, "overlay setpoint recorded as 145.0")
	_ok(ex_model.screw_rpm_setpoint == 145.0, "ExtruderModel screw_rpm_setpoint updated to 145.0")

	# Simulate model convergence tick
	var old_rpm : float = ex_model.screw_rpm
	for i in range(10):
		ex_model.tick(0.1, {})
	_ok(absf(ex_model.screw_rpm - 145.0) < absf(old_rpm - 145.0),
		"screw_rpm moved toward setpoint (%s -> %s)" % [str(old_rpm), str(ex_model.screw_rpm)])

	# ── 3. IPC setpoint update for compactor temperature ─────────────────
	print("Test 3: Update SV-temperatuur via IPC")
	overlay._on_ipc(JSON.stringify({
		"type": "set_setpoint",
		"screen": "EREMA Extruder Scherm 3C.dc.html",
		"channel": "sv_temperatuur",
		"value": 112.0,
		"unit": "°C"
	}))
	_ok(float(overlay._setpoints.get("sv_temperatuur", 0.0)) == 112.0, "overlay SV-temperatuur setpoint == 112.0")
	_ok(cc.pot_temperature_setpoint == 112.0, "CutterCompactor pot_temperature_setpoint == 112.0")

	# ── 4. IPC setpoint update for zone temperatures ──────────────────────
	print("Test 4: Update zone temperature EZ-1 via IPC")
	overlay._on_ipc(JSON.stringify({
		"type": "set_setpoint",
		"screen": "EREMA Extruder Scherm 3C.dc.html",
		"channel": "ez_1",
		"value": 135.0,
		"unit": "°C"
	}))
	_ok(float(overlay._setpoints.get("ez_1", 0.0)) == 135.0, "overlay ez_1 setpoint == 135.0")
	_ok(ex_model.get_zone_temp(0) == 135.0, "ExtruderModel zone 0 setpoint == 135.0")

	var old_ez1 : float = ex_model.get_actual_zone_temp(0)
	for i in range(10):
		ex_model.tick(0.1, {})
	var new_ez1 : float = ex_model.get_actual_zone_temp(0)
	_ok(absf(new_ez1 - 135.0) < absf(old_ez1 - 135.0),
		"EZ-1 actual zone temp converged toward setpoint (%s -> %s)" % [str(old_ez1), str(new_ez1)])

	# ── 5. IPC setpoint update for power cap ──────────────────────────────
	print("Test 5: Update SV-vermogen via IPC")
	overlay._on_ipc(JSON.stringify({
		"type": "set_setpoint",
		"screen": "EREMA Extruder Scherm 3C.dc.html",
		"channel": "sv_vermogen",
		"value": 205.0,
		"unit": "kW"
	}))
	_ok(float(overlay._setpoints.get("sv_vermogen", 0.0)) == 205.0, "overlay sv_vermogen setpoint == 205.0")
	_ok(cc.power_cap_kw_setpoint == 205.0, "CutterCompactor power_cap_kw_setpoint == 205.0")

	# ── 6. Generic parallel screen values ─────────────────────────────────
	print("Test 6: Generic screen values across other HMI screens")
	overlay._on_ipc(JSON.stringify({
		"type": "set_setpoint",
		"screen": "Waslijn 3C L3C.6 Maalmolen.dc.html",
		"channel": "schroef_1_frequentie",
		"value": 48.5,
		"unit": "Hz"
	}))
	_ok(float(overlay._setpoints.get("schroef_1_frequentie", 0.0)) == 48.5,
		"generic setpoint 'schroef_1_frequentie' stored")

	var v2 : Dictionary = overlay.gather_vals()
	_ok(v2.has("screen_vals"), "payload contains 'screen_vals'")
	var svals : Dictionary = v2.get("screen_vals", {})
	_ok(svals.has("schroef_1_frequentie"), "screen_vals contains 'schroef_1_frequentie'")
	var fq_data : Dictionary = svals.get("schroef_1_frequentie", {})
	_ok(float(fq_data.get("setpoint", 0.0)) == 48.5, "screen_vals setpoint == 48.5")
	# ── 7. Problem / E-Stop state handling ("unless there's a problem, of course") ──
	print("Test 7: Fault / E-Stop decoupling")
	lf.mock_fault_key = "estop_pressed"
	# When estop is active, motion/power channels decay to 0 instead of moving to setpoint
	var val_before : float = float(overlay._actuals.get("schroef_1_frequentie", 2.0))
	for step in range(5):
		overlay.gather_vals()
	var val_after : float = float(overlay._actuals.get("schroef_1_frequentie", 0.0))
	_ok(val_after <= val_before, "frequentie decayed during active estop (%s -> %s)" % [str(val_before), str(val_after)])
	lf.mock_fault_key = "" # clear fault

	# ── 8. Sensor jitter / micro-fluctuations ──
	print("Test 8: Operational micro-fluctuations")
	overlay._actuals["schroef_1_frequentie"] = 40.0
	var jitter_v1 : Dictionary = overlay.gather_vals()
	var act1 : float = float(jitter_v1.get("screen_vals", {}).get("schroef_1_frequentie", {}).get("actual", 0.0))
	_ok(act1 > 0.0, "actual value returned during operational state")

	# Clean up
	root.remove_child(overlay)
	overlay.free()
	root.remove_child(lf)
	lf.free()
	root.remove_child(em_node)
	em_node.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)

class MockExtruderMachine extends Node3D:
	var model = null

class MockLineFlow extends Node:
	var active_cc = null
	var mock_fault_key := ""
	func get_first_cutter_compactor():
		return active_cc
	func machine_list() -> Array: return []
	func get_machine_info(_key: String) -> Dictionary: return {}
	func is_estopped() -> bool: return mock_fault_key != ""
	func is_line_starting() -> bool: return false
	func line_powered_fraction() -> float: return 0.5
	func estop_fault_key() -> String: return mock_fault_key
	func set_machine_setpoint(_ch: String, _val: float) -> void: pass
