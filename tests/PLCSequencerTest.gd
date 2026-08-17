extends SceneTree

const PLCSequencer := preload("res://src/sim/PLCSequencer.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

class MockMachine extends Object:
	var is_running: bool = false
	var name: String

	func _init(n: String) -> void:
		name = n

	func set_running(on: bool) -> void:
		is_running = on

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — PLCSequencer headless test")
	print("============================================================")

	_test_initialization()
	_test_startup_sequence()
	_test_shutdown_sequence()
	_test_force_all_powered()
	_test_set_stage_powered()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")

	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

func _test_initialization() -> void:
	print("[1] Initialization")
	var plc := PLCSequencer.new()
	_ok(plc.all_running() == false, "Starts with all_running == false")
	_ok(plc.all_stopped() == true, "Starts with all_stopped == true")
	_ok(plc.powered_count() == 0, "Starts with powered_count == 0")
	_ok(plc.is_busy() == false, "Starts with is_busy == false")
	plc.queue_free()

func _test_startup_sequence() -> void:
	print("[2] Startup Sequence (Downstream-first)")
	var plc := PLCSequencer.new()
	plc.stagger_s = 1.0

	var m1 := MockMachine.new("Head")
	var m2 := MockMachine.new("Middle")
	var m3 := MockMachine.new("Tail")

	plc.add_stage(m1)
	plc.add_stage(m2)
	plc.add_stage(m3)

	plc.start()
	_ok(plc.is_busy() == true, "Sequencer is busy after start()")
	_ok(plc.powered_count() == 0, "Nothing powered instantly on start()")

	# Tick to start the tail (first downstream machine)
	plc.tick(1.0) # stagger is 1.0, wait 1.0s
	_ok(m3.is_running == true, "Tail powered first")
	_ok(m2.is_running == false, "Middle not powered yet")
	_ok(m1.is_running == false, "Head not powered yet")
	_ok(plc.powered_count() == 1, "1 machine powered")

	plc.tick(1.0)
	_ok(m2.is_running == true, "Middle powered second")
	_ok(m1.is_running == false, "Head not powered yet")

	plc.tick(1.0)
	_ok(m1.is_running == true, "Head powered third")
	_ok(plc.is_busy() == false, "Sequencer not busy after all started")
	_ok(plc.all_running() == true, "all_running() returns true")

	m1.free()
	m2.free()
	m3.free()
	plc.queue_free()

func _test_shutdown_sequence() -> void:
	print("[3] Shutdown Sequence (Upstream-first)")
	var plc := PLCSequencer.new()
	plc.stagger_s = 1.0

	var m1 := MockMachine.new("Head")
	var m2 := MockMachine.new("Tail")

	plc.add_stage(m1)
	plc.add_stage(m2)

	plc.force_all_powered()
	_ok(m1.is_running and m2.is_running, "Machines running before stop")

	plc.stop()
	_ok(plc.is_busy() == true, "Sequencer is busy after stop()")

	plc.tick(1.0)
	_ok(m1.is_running == false, "Head (upstream) stopped first")
	_ok(m2.is_running == true, "Tail still running")

	plc.tick(1.0)
	_ok(m2.is_running == false, "Tail stopped second")
	_ok(plc.is_busy() == false, "Sequencer not busy after all stopped")
	_ok(plc.all_stopped() == true, "all_stopped() returns true")

	m1.free()
	m2.free()
	plc.queue_free()

func _test_force_all_powered() -> void:
	print("[4] Force all powered")
	var plc := PLCSequencer.new()

	var m1 := MockMachine.new("M1")
	var m2 := MockMachine.new("M2")

	plc.add_stage(m1)
	plc.add_stage(m2)

	plc.force_all_powered()
	_ok(m1.is_running == true, "M1 running")
	_ok(m2.is_running == true, "M2 running")
	_ok(plc.all_running() == true, "all_running is true")
	_ok(plc.is_busy() == false, "Sequencer not busy")

	m1.free()
	m2.free()
	plc.queue_free()

func _test_set_stage_powered() -> void:
	print("[5] Set stage powered")
	var plc := PLCSequencer.new()
	var m1 := MockMachine.new("M1")
	plc.add_stage(m1)

	plc.set_stage_powered(0, true)
	_ok(m1.is_running == true, "M1 running after set_stage_powered true")
	_ok(plc.is_powered(0) == true, "is_powered(0) returns true")
	_ok(plc.powered_count() == 1, "powered_count is 1")

	plc.set_stage_powered(0, false)
	_ok(m1.is_running == false, "M1 stopped after set_stage_powered false")
	_ok(plc.is_powered(0) == false, "is_powered(0) returns false")

	m1.free()
	plc.queue_free()
