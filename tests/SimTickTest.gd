extends SceneTree

const _SimTick := preload("res://src/autoload/SimTick.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — SimTick headless test")
	print("============================================================")

	_test_initialization()
	_test_ticking_and_accumulation()
	_test_accumulator_capping()
	_test_pausing()

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
	print("[1] Initialization state")
	var st = _SimTick.new()
	_ok(st._accumulator == 0.0, "Accumulator starts at 0.0")
	_ok(st.is_paused() == false, "Starts unpaused")
	_ok(st.get_tick_count() == 0, "Tick count starts at 0")
	st.free()

func _test_ticking_and_accumulation() -> void:
	print("[2] Ticking and Accumulation")
	var st = _SimTick.new()

	var emitted_count = [0]
	st.sim_tick.connect(func(_delta): emitted_count[0] += 1)

	# Process with exactly one tick dt
	st._process(st.TICK_DT)
	_ok(emitted_count[0] == 1, "Emits exactly once for TICK_DT")
	_ok(st.get_tick_count() == 1, "Tick count increments")
	_ok(st._accumulator < 0.0001, "Accumulator empties")

	# Process with enough for 3 ticks
	st._process(st.TICK_DT * 3.5)
	_ok(emitted_count[0] == 4, "Emits 3 more times for 3.5 * TICK_DT")
	_ok(st.get_tick_count() == 4, "Tick count is now 4")
	_ok(st._accumulator >= st.TICK_DT * 0.49 && st._accumulator <= st.TICK_DT * 0.51, "Accumulator holds remaining delta")

	st.free()

func _test_accumulator_capping() -> void:
	print("[3] Accumulator capping")
	var st = _SimTick.new()

	var emitted_count = [0]
	st.sim_tick.connect(func(_delta): emitted_count[0] += 1)

	# Massive delta that should be capped at 1.0
	st._process(5.0)

	# 1.0 / TICK_DT (0.1) = 10 ticks
	var expected_ticks = floori(1.0 / st.TICK_DT)
	_ok(emitted_count[0] == expected_ticks, "Ticks are capped corresponding to 1.0 accumulator cap (got %d, expected %d)" % [emitted_count[0], expected_ticks])
	_ok(st.get_tick_count() == expected_ticks, "Tick count matches capped ticks")

	st.free()

func _test_pausing() -> void:
	print("[4] Pausing")
	var st = _SimTick.new()

	var emitted_count = [0]
	st.sim_tick.connect(func(_delta): emitted_count[0] += 1)

	st.pause()
	_ok(st.is_paused() == true, "pause() sets state to true")

	st._process(st.TICK_DT * 2.0)
	_ok(emitted_count[0] == 0, "No ticks emitted while paused")
	_ok(st.get_tick_count() == 0, "Tick count remains 0 while paused")
	_ok(st._accumulator == 0.0, "Accumulator does not grow while paused")

	st.resume()
	_ok(st.is_paused() == false, "resume() sets state to false")

	st._process(st.TICK_DT)
	_ok(emitted_count[0] == 1, "Ticks emitted after resume")

	st.free()
