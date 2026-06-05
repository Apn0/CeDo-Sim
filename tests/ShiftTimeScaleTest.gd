extends Node3D

## #166 — the shift time-compression rate is an operator-set, persisted setting
## (gameplay.shift_time_scale) that ShiftClock reads, instead of a hardcoded 24×.
## The operator picks the pace; the value is clamped to a sane band.

const ShiftClockScript = preload("res://src/scenes/world/ShiftClock.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _approx(a: float, b: float) -> bool:
	return absf(a - b) < 0.001

func _ready() -> void:
	print("=== #166 SHIFT TIME-SCALE SETTING ===")
	var sm := get_node_or_null("/root/SettingsManager")
	_ok(sm != null, "SettingsManager autoload present")
	_ok(sm.gameplay().has("shift_time_scale"), "shift_time_scale is a known gameplay setting")

	var saved : float = float(sm.gameplay().get("shift_time_scale", 24.0))

	var clock = ShiftClockScript.new()
	add_child(clock)                                  # _ready reads the setting
	_ok(_approx(clock.time_scale, saved), "clock takes the setting's value on ready (%.0f×)" % clock.time_scale)

	# Operator dials it slower (8×) — clock picks it up.
	sm.gameplay()["shift_time_scale"] = 8.0
	clock._apply_time_scale_setting()
	_ok(_approx(clock.time_scale, 8.0), "operator-set 8× is applied")

	# Out-of-range is clamped to the sane band (1–240).
	sm.gameplay()["shift_time_scale"] = 5000.0
	clock._apply_time_scale_setting()
	_ok(_approx(clock.time_scale, 240.0), "absurd rate clamps to 240×")
	sm.gameplay()["shift_time_scale"] = 0.0
	clock._apply_time_scale_setting()
	_ok(_approx(clock.time_scale, 1.0), "below-real-time clamps to 1× (true real-time floor)")

	# Restore the in-memory setting (no disk write happened — we never apply()'d).
	sm.gameplay()["shift_time_scale"] = saved
	clock.queue_free()

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()
