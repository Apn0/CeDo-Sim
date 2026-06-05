extends SceneTree
## Regression tests for the drive-feel fixes:
##   - No in-place rotation: angular_velocity must be ~0 when speed is ~0
##   - Steering scales with speed (full effect at top speed)
##   - Reverse driving flips the steer direction (like a real car)
##
## We don't load the full BaseVehicle scene (4.6 .tscn) — we copy the relevant
## tiny piece of _drive() logic here and exercise it directly. If you change
## the formula in BaseVehicle._drive, mirror it in _drive_test_step().

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

const TURN_RATE   : float = 1.6
const DRIVE_ACCEL : float = 8.0

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Vehicle drive feel test")
	print("============================================================")
	_test_no_in_place_rotation()
	_test_steering_scales_with_speed()
	_test_reverse_flips_steering_direction()
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

# =============================================================================
# Mirrors BaseVehicle._drive — keep in sync (kept tiny so the test stays a
# proper isolation of the steering rule)
# =============================================================================
func _drive_test_step(throttle: float, steering: float, current_speed: float, max_mps: float) -> Dictionary:
	var steer_scale := clampf(current_speed / maxf(max_mps, 0.01), 0.0, 1.0)
	var dir_sign := 1.0 if throttle >= 0.0 else -1.0
	var turn := -steering * TURN_RATE * steer_scale * dir_sign
	return {"turn": turn, "steer_scale": steer_scale}

# =============================================================================
func _test_no_in_place_rotation() -> void:
	print("[1] No in-place rotation: at speed=0, steering has zero yaw effect")
	# Throttle 0, full steer left, speed 0 → turn must be 0 (no axis pivot)
	var r := _drive_test_step(0.0, -1.0, 0.0, 3.33)
	_ok(absf(r["turn"]) < 0.001,
		"throttle=0, steer=-1, speed=0 → turn=%.3f (should be 0)" % r["turn"])
	# Same for hard-right with no throttle
	r = _drive_test_step(0.0, 1.0, 0.0, 3.33)
	_ok(absf(r["turn"]) < 0.001,
		"throttle=0, steer=+1, speed=0 → turn=%.3f (should be 0)" % r["turn"])
	# Tiny crawl-speed → small but nonzero turn
	r = _drive_test_step(0.0, 1.0, 0.5, 3.33)
	_ok(absf(r["turn"]) > 0.0 and absf(r["turn"]) < TURN_RATE * 0.2,
		"throttle=0, steer=+1, speed=0.5 → small turn=%.3f" % r["turn"])

func _test_steering_scales_with_speed() -> void:
	print("[2] Steering scales linearly with speed up to max")
	# At full speed, steering reaches full TURN_RATE
	var r := _drive_test_step(1.0, -1.0, 3.33, 3.33)
	_ok(absf(r["turn"] - TURN_RATE) < 0.01,
		"throttle=1, steer=-1, speed=max → turn=%.3f ≈ TURN_RATE" % r["turn"])
	# At half speed, steer scale is 0.5
	r = _drive_test_step(1.0, -1.0, 1.66, 3.33)
	_ok(absf(r["turn"] - TURN_RATE * 0.5) < 0.05,
		"throttle=1, steer=-1, half speed → turn ≈ 0.5 × TURN_RATE (=%.3f)" % r["turn"])
	# Above max speed (e.g., downhill) we still clamp at TURN_RATE
	r = _drive_test_step(1.0, -1.0, 10.0, 3.33)
	_ok(absf(r["turn"] - TURN_RATE) < 0.01,
		"speed > max → steer_scale clamps; turn=%.3f ≈ TURN_RATE" % r["turn"])

func _test_reverse_flips_steering_direction() -> void:
	print("[3] Reverse driving flips steer direction (like a real car backing up)")
	# Forward + steer right → yaw negative (turning right in our coordinates)
	var fwd := _drive_test_step(1.0, 1.0, 3.33, 3.33)
	# Reverse + same steer should yaw positively
	var rev := _drive_test_step(-1.0, 1.0, 3.33, 3.33)
	_ok(signf(fwd["turn"]) != signf(rev["turn"]) and absf(fwd["turn"]) > 0.1,
		"forward turn=%.3f, reverse turn=%.3f (opposite sign)"
			% [fwd["turn"], rev["turn"]])
