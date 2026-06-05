extends Node3D

## #173 — the BAKED process model's ENERGY layer. Proves the amps model is
## calibrated to the real HMI currents (Line3CDef) and scales correctly with load.

const ProcessModel = preload("res://src/sim/ProcessModel.gd")
const Line3CDef    = preload("res://src/sim/Line3CDef.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _approx(a: float, b: float, eps: float = 0.01) -> bool:
	return absf(a - b) <= eps

func _ready() -> void:
	print("=== #173 PROCESS MODEL — energy/amps calibration ===")
	var mill := 186.79   # L3C.6 Maalmolen — the line's biggest motor
	# Full load reproduces the HMI reading exactly.
	_ok(_approx(ProcessModel.stage_amps(mill, 1.0, true), mill),
		"full load → exactly the HMI current (%.2f A)" % mill)
	# Idle (spinning, no material) sits at the motor idle fraction.
	var idle := mill * 0.35
	_ok(_approx(ProcessModel.stage_amps(mill, 0.0, true), idle),
		"unloaded-but-running → motor idle current (%.2f A)" % idle)
	# Half load interpolates between idle and full.
	_ok(_approx(ProcessModel.stage_amps(mill, 0.5, true), idle + (mill - idle) * 0.5),
		"half load interpolates idle→full")
	# Stopped draws nothing; unmetered (0 A on HMI) stays 0.
	_ok(ProcessModel.stage_amps(mill, 1.0, false) == 0.0, "stopped motor draws 0 A")
	_ok(ProcessModel.stage_amps(0.0, 1.0, true) == 0.0, "unmetered stage stays 0 A")
	# Monotonic: more load → more current.
	_ok(ProcessModel.stage_amps(mill, 0.8, true) > ProcessModel.stage_amps(mill, 0.3, true),
		"current rises monotonically with load")

	# Lookup by HMI code matches the table.
	_ok(_approx(ProcessModel.hmi_amps_for_code("L3C.6"), 186.79),
		"hmi_amps_for_code('L3C.6') = Maalmolen 186.79 A")
	_ok(_approx(ProcessModel.live_amps_for_stage("L3C.6", 1.0, true), 186.79),
		"live_amps_for_stage drives the mill to 186.79 A at full load")
	_ok(_approx(ProcessModel.hmi_amps_for_code("L3C.14L"), 70.80),
		"mechanical dryer L reads 70.80 A")

	# Line-level anchors.
	var total := ProcessModel.line_nominal_amps()
	_ok(total > 400.0 and total < 800.0, "whole-line nominal current sums sanely (%.1f A)" % total)
	_ok(_approx(ProcessModel.load_fraction(1687.0), 1.0), "load_fraction at design rate = 1.0")
	_ok(_approx(ProcessModel.load_fraction(843.5), 0.5, 0.01), "load_fraction at half rate = 0.5")

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()
