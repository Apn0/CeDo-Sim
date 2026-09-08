extends Node

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	if c:
		print("  ok    : " + msg)
	else:
		print("  FAIL  : " + msg)
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] leafblower refuel")

	# The instantiate() on LeafBlower.tscn failed to be a LeafBlower object probably because we need PlaceableCatalog or something?
	# Wait, test_walkie.gd did `var w = preload("...Walkie.gd").new()`. Let's do that!
	var blower = preload("res://src/operator/LeafBlower.gd").new()
	add_child(blower)
	await get_tree().process_frame

	_check(blower != null, "S0 blower instantiated")

	# Scenario A: Negative value behaves as full top-off
	blower.fuel_l = 0.1
	blower.refuel(-1.0)
	_check(is_equal_approx(blower.fuel_l, blower.fuel_capacity_l), "S1 refuel(-1.0) tops off the tank completely (fuel_l is %.2f)" % blower.fuel_l)
	_check(is_equal_approx(blower.fuel_pct(), 1.0), "S1 fuel_pct() is 1.0 after full top off")

	# Scenario B: Partial fill
	blower.set("fuel_capacity_l", 1.0)
	blower.fuel_l = 0.1
	blower.refuel(0.2)
	_check(is_equal_approx(blower.fuel_l, 0.3), "S2 partial refuel(0.2) from 0.1 results in 0.3 (fuel_l is %.2f)" % blower.fuel_l)

	# Scenario C: Overfill clamping
	blower.set("fuel_capacity_l", 0.5)
	blower.fuel_l = 0.4
	blower.refuel(999.0)
	_check(is_equal_approx(blower.fuel_l, blower.fuel_capacity_l), "S3 overfill refuel(999.0) from 0.4 clamps to capacity (fuel_l is %.2f)" % blower.fuel_l)

	# Scenario D: refuel() with default argument
	blower.fuel_l = 0.0
	blower.refuel()
	_check(is_equal_approx(blower.fuel_l, blower.fuel_capacity_l), "S4 refuel() with default argument tops off completely (fuel_l is %.2f)" % blower.fuel_l)

	# Empty capacity scenario
	var old_cap = blower.fuel_capacity_l
	blower.fuel_capacity_l = 0.0
	_check(is_equal_approx(blower.fuel_pct(), 0.0), "S5 fuel_pct() returns 0.0 when capacity is 0.0")
	blower.fuel_capacity_l = old_cap

	if _fails > 0:
		print("TEST FAILED WITH %d ERRORS" % _fails)
		get_tree().quit(1)
	else:
		print("TEST PASSED")
		get_tree().quit(0)
	return
