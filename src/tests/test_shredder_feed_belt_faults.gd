extends SceneTree

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("[TEST] ShredderFeedBelt fault handling")

	var belt = load("res://src/scenes/world/ShredderFeedBelt.gd").new()
	belt.require_shredder = false
	root.add_child(belt)

	if not belt.is_node_ready():
		belt._ready()
	belt.set_process(false)

	# Initial state
	_check(not belt.is_faulted(), "Initial state: is_faulted() == false")
	_check(not belt.belt_jam_active(), "Initial state: belt_jam_active() == false")
	_check(not belt.intake_overfill_active(), "Initial state: intake_overfill_active() == false")
	_check(not belt.thermal_shutdown_active(), "Initial state: thermal_shutdown_active() == false")

	# Trigger belt_jam
	belt._raise_fault("belt_jam", "BELT-JAM")
	_check(belt.is_faulted(), "After belt_jam: is_faulted() == true")
	_check(belt.belt_jam_active(), "After belt_jam: belt_jam_active() == true")
	_check(not belt.intake_overfill_active(), "After belt_jam: intake_overfill_active() == false")
	_check(not belt.thermal_shutdown_active(), "After belt_jam: thermal_shutdown_active() == false")

	# Trigger intake_overfill
	belt._raise_fault("intake_overfill", "INTAKE-OVERFILL")
	_check(belt.is_faulted(), "After intake_overfill: is_faulted() == true")
	_check(belt.belt_jam_active(), "After intake_overfill: belt_jam_active() == true")
	_check(belt.intake_overfill_active(), "After intake_overfill: intake_overfill_active() == true")
	_check(not belt.thermal_shutdown_active(), "After intake_overfill: thermal_shutdown_active() == false")

	# Trigger thermal_shutdown
	belt._raise_fault("thermal_shutdown", "THERMAL-SHUTDOWN")
	_check(belt.is_faulted(), "After thermal_shutdown: is_faulted() == true")
	_check(belt.belt_jam_active(), "After thermal_shutdown: belt_jam_active() == true")
	_check(belt.intake_overfill_active(), "After thermal_shutdown: intake_overfill_active() == true")
	_check(belt.thermal_shutdown_active(), "After thermal_shutdown: thermal_shutdown_active() == true")

	# Reset faults
	belt.reset_faults()
	_check(not belt.is_faulted(), "After reset: is_faulted() == false")
	_check(not belt.belt_jam_active(), "After reset: belt_jam_active() == false")
	_check(not belt.intake_overfill_active(), "After reset: intake_overfill_active() == false")
	_check(not belt.thermal_shutdown_active(), "After reset: thermal_shutdown_active() == false")

	if _fails == 0:
		print("[TEST] ShredderFeedBelt fault handling PASS")
	else:
		print("[TEST] ShredderFeedBelt fault handling FAIL (%d)" % _fails)

	quit(0 if _fails == 0 else 1)
