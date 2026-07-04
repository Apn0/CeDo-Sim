extends Node3D

## Headless test for the reusable mechanism framework (#146): RotatingMechanism
## spins + reports throughput, and PLCSequencer powers stages downstream-first
## with a stagger and reverses on stop.

const RotMech = preload("res://src/sim/RotatingMechanism.gd")
const PLC     = preload("res://src/sim/PLCSequencer.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	await _test_rotation()
	_test_plc_order()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _test_rotation() -> void:
	print("[1] RotatingMechanism spins + scales throughput with rpm")
	var m = RotMech.new()
	m.rpm = 60.0
	m.nominal_rpm = 60.0
	m.capacity_kg_s = 10.0
	m.spin_up_s = 0.001          # effectively instant for the test
	m.axis = Vector3.UP
	add_child(m)
	await get_tree().process_frame   # _ready captures base basis
	m.set_process(false)             # manual ticking
	m.set_running(true)              # rotors now default to STOPPED (LineFlow drives them per-tick in-game); snap_to_rpm zeroes the target while not running
	m.snap_to_rpm(60.0)              # explicit bypass for deterministic per-tick assertions
	var a0 : float = m.angle
	m._process(0.5)                  # 60 rpm = 1 rev/s → 0.5 s = π rad
	_ok(absf(m.angle - (a0 + PI)) < 0.05, "spun ~π rad in 0.5 s at 60 rpm (Δ=%.2f)" % (m.angle - a0))
	_ok(absf(m.throughput() - 10.0) < 0.1, "throughput = capacity at nominal rpm (%.1f)" % m.throughput())
	m.snap_to_rpm(30.0)
	_ok(absf(m.throughput() - 5.0) < 0.1, "half rpm → half throughput (%.1f)" % m.throughput())
	m.set_running(false); m.snap_to_rpm(0.0)
	_ok(m.throughput() == 0.0, "stopped → zero throughput")
	m.queue_free()

func _test_plc_order() -> void:
	print("[2] PLCSequencer powers tail→head on start, head→tail on stop")
	var plc = PLC.new()
	plc.stagger_s = 1.0
	add_child(plc)
	for i in range(3):
		plc.add_stage(null)          # head=0, mid=1, tail=2
	plc.start()
	plc.tick(0.0)                    # first tick powers the TAIL (idx 2)
	_ok(plc.is_powered(2) and not plc.is_powered(0), "tail powers up first")
	plc.tick(1.0)
	_ok(plc.is_powered(1), "mid powers next")
	plc.tick(1.0)
	_ok(plc.is_powered(0), "head powers last")
	_ok(plc.all_running(), "all three running after spin-up")
	# Stop: head (idx0) powers down first.
	plc.stop()
	plc.tick(0.0)
	_ok(not plc.is_powered(0) and plc.is_powered(2), "head powers DOWN first on stop")
	plc.tick(1.0); plc.tick(1.0)
	_ok(plc.all_stopped(), "all stopped after the down-sequence")
	plc.queue_free()
