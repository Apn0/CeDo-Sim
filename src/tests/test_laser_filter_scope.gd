extends SceneTree

const ScopeScript = preload("res://src/scenes/hud/scopes/LaserFilterScope.gd")
const LaserFilter = preload("res://src/sim/LaserFilter.gd")

var _ran := false
var _fail := 0

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false

func _run() -> void:
	print("==== LASER FILTER SCOPE TEST ====")
	var scope: Control = ScopeScript.new()
	get_root().add_child(scope)

	if scope.get("_title_lbl") == null:
		print("FAIL: Title label not built")
		_fail += 1
		quit(1)
		return
	print("  ok    : Title label built")

	var filter: Node3D = LaserFilter.new()
	get_root().add_child(filter)

	filter.set("delta_p_psi", 100.0)
	# 2026-09-24: the filter is told the melt-set pressure AFTER it (bar); the
	# inlet (MP < MF) is that plus its own dMP. Was a psi "upstream indicator".
	filter.set("mp_after_filter_bar", 25.0)
	filter.set("scraper_rpm", 30.0)
	filter.set("front_loading_g", 10.0)
	filter.set("is_halted", false)

	scope.set("filter_id", "TEST_ID")
	scope.call("set_filter", filter)

	print("  ok    : Bound mock filter")

	scope.call("_process", 0.1)

	var delta_bar = scope.get("_cur_delta_bar")
	var inlet_bar = scope.get("_cur_inlet_bar")

	if abs(delta_bar - 100.0 / 14.5038) > 0.01:
		print("FAIL: Expected delta bar ~6.89, got ", delta_bar)
		_fail += 1
	else:
		print("  ok    : delta bar converted correctly")

	if abs(inlet_bar - (25.0 + 100.0 / 14.5038)) > 0.01:
		print("FAIL: Expected inlet bar ~31.89 (25 after + 6.89 dMP), got ", inlet_bar)
		_fail += 1
	else:
		print("  ok    : inlet bar converted correctly")

	var press_delta = scope.get("_press_delta")
	if press_delta == null:
		print("FAIL: _press_delta not built")
		_fail += 1
	elif abs(press_delta.get("_value_bar") - delta_bar) > 0.01:
		print("FAIL: _press_delta readout not updated")
		_fail += 1
	else:
		print("  ok    : _press_delta readout updated")

	var press_inlet = scope.get("_press_inlet")
	if press_inlet == null:
		print("FAIL: _press_inlet not built")
		_fail += 1
	elif press_inlet.get("_label").text != "MP < MF":
		print("FAIL: _press_inlet setup label mismatch, got ", press_inlet.get("_label").text)
		_fail += 1
	elif abs(press_inlet.get("_value_bar") - inlet_bar) > 0.01:
		print("FAIL: _press_inlet readout not updated")
		_fail += 1
	else:
		print("  ok    : _press_inlet setup and update verified")

	var press_outlet = scope.get("_press_outlet")
	if press_outlet == null:
		print("FAIL: _press_outlet not built")
		_fail += 1
	elif press_outlet.get("_label").text != "MP > MF":
		print("FAIL: _press_outlet setup label mismatch, got ", press_outlet.get("_label").text)
		_fail += 1
	elif abs(press_outlet.get("_value_bar") - maxf(0.0, inlet_bar - delta_bar)) > 0.01:
		print("FAIL: _press_outlet readout not updated")
		_fail += 1
	else:
		print("  ok    : _press_outlet setup and update verified")

	scope.call("set_filter", null)
	scope.call("_process", 0.1)
	print("  ok    : Process tick with null filter")

	if _fail == 0:
		print("PASS — LaserFilterScope logic verified")
		quit(0)
	else:
		print("FAIL — ", _fail, " tests failed")
		quit(1)
