extends SceneTree

const BezinkHmi = preload("res://src/scenes/hud/BezinkHmi.gd")

class MockTank extends Node:
	var water_level : float = 0.45
	var valve_auto : bool = true
	var valve_open : bool = false
	var sp_low : float = 0.20
	var sp_high : float = 0.80
	var pump_on : bool = false

	var method_calls := []

	func set_valve_manual(open: bool) -> void:
		method_calls.append({"method": "set_valve_manual", "open": open})
		valve_open = open

	func toggle_auto() -> void:
		method_calls.append({"method": "toggle_auto"})
		valve_auto = not valve_auto

	func adjust_sp_low(d: float) -> void:
		method_calls.append({"method": "adjust_sp_low", "d": d})
		sp_low += d

	func adjust_sp_high(d: float) -> void:
		method_calls.append({"method": "adjust_sp_high", "d": d})
		sp_high += d

var _fails : int = 0

func _check(cond: bool, msg: String) -> void:
	print(("  ok    : " if cond else "  FAIL  : ") + msg)
	if not cond:
		_fails += 1

func _init() -> void:
	print("=== BezinkHmi UI unit tests ===")

	var hmi = BezinkHmi.new()
	hmi._ready()

	_check(not hmi.visible, "HMI initially hidden")
	_check(not hmi._built, "HMI initially not built")

	var tank = MockTank.new()

	# Test open_for
	hmi.open_for(tank)

	_check(hmi.visible, "HMI visible after open_for")
	_check(hmi._built, "HMI built after open_for")
	_check(hmi._tank == tank, "HMI linked to tank")

	# Verify UI elements exist
	_check(hmi._level_bar != null, "Level bar created")
	_check(hmi._mode_btn != null, "Mode button created")
	_check(hmi._open_btn != null, "Open button created")
	_check(hmi._close_btn != null, "Close button created")

	# Test refresh values
	_check(hmi._level_bar.value == 45.0, "Level bar value set from tank")
	_check(hmi._mode_btn.text == "KLEP: AUTOMAAT", "Mode button text set to AUTO")
	_check(hmi._open_btn.disabled == true, "Open button disabled in auto mode")
	_check(hmi._valve_lbl.text == "Klep: DICHT", "Valve label set to DICHT")
	_check(hmi._pump_lamp.color == hmi.LAMP_OFF, "Pump lamp set to OFF")

	# Test interactions
	hmi._on_toggle_mode()
	_check(tank.method_calls.size() > 0 and tank.method_calls[-1].method == "toggle_auto", "toggle_auto called on tank")

	# Simulate the button being pressed
	hmi._mode_btn.pressed.emit()
	_check(tank.method_calls.size() > 1 and tank.method_calls[-1].method == "toggle_auto", "toggle_auto called on tank via button")

	hmi._open_btn.pressed.emit()
	_check(tank.method_calls.size() > 2 and tank.method_calls[-1].method == "set_valve_manual", "set_valve_manual called via button")

	hmi._close_btn.pressed.emit()
	_check(tank.method_calls.size() > 3 and tank.method_calls[-1].method == "set_valve_manual", "set_valve_manual called via button (close)")

	tank.toggle_auto()
	hmi._refresh()
	_check(hmi._mode_btn.text == "KLEP: HAND", "Mode button text changed to HAND")
	_check(hmi._open_btn.disabled == false, "Open button enabled in HAND mode")

	var old_sp_low = tank.sp_low
	hmi._adjust(tank, "adjust_sp_low", 0.05)
	_check(tank.sp_low == old_sp_low + 0.05, "adjust_sp_low called via _adjust")

	hmi.close_panel()
	_check(not hmi.visible, "HMI hidden after close_panel")

	print("Result: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	quit(0 if _fails == 0 else 1)
