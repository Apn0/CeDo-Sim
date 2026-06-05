extends Node3D

## Headless test for ShiftClock (#158): time actually advances under
## compression, the display reads correctly, and the shift auto-rolls to the
## next working day at 15:00 instead of freezing.

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	_test_start_and_display()
	_test_time_advances()
	_test_rollover_at_end()
	_test_hold_when_no_autoadvance()
	_test_load_guard_against_frozen_end()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _make_clock() -> ShiftClock:
	# NOT added to the tree, so _physics_process only runs when we call it —
	# fully deterministic, no reliance on real frame timing.
	var c := preload("res://src/scenes/world/ShiftClock.gd").new()
	return c

# ── 1. Start + display ───────────────────────────────────────────────────────
func _test_start_and_display() -> void:
	print("[1] start_shift resets to 07:00 and is active")
	var c := _make_clock()
	c.start_shift()
	_ok(c.shift_active, "shift is active after start")
	_ok(c.get_time_string() == "07:00", "starts at 07:00 (got %s)" % c.get_time_string())
	c.shift_elapsed_seconds = 3600.0
	_ok(c.get_time_string() == "08:00", "1 h elapsed → 08:00 (got %s)" % c.get_time_string())
	c.shift_elapsed_seconds = 3600.0 * 4 + 1800.0
	_ok(c.get_time_string() == "11:30", "4.5 h elapsed → 11:30 (got %s)" % c.get_time_string())

# ── 2. Time advances under compression ───────────────────────────────────────
func _test_time_advances() -> void:
	print("[2] time advances when ticked (compression applied)")
	var c := _make_clock()
	c.time_scale = 60.0
	c.start_shift()
	var before := c.shift_elapsed_seconds
	# One simulated second of real time → 60 game-seconds.
	c._physics_process(1.0)
	_ok(c.shift_elapsed_seconds > before, "elapsed grew after a tick")
	_ok(is_equal_approx(c.shift_elapsed_seconds, 60.0), "60x scale → 60 game-s per real-s (got %.1f)" % c.shift_elapsed_seconds)

# ── 3. Rollover at 15:00 → next working day, fresh 07:00 ──────────────────────
func _test_rollover_at_end() -> void:
	print("[3] shift auto-rolls to the next working day at 15:00")
	var c := _make_clock()
	c.auto_advance = true
	c.day_index = 0
	c.start_shift()
	var ended := [false]
	var rolled := [false]
	c.shift_ended.connect(func(): ended[0] = true)
	c.shift_rolled_over.connect(func(_d): rolled[0] = true)
	# Jump to one tick short of the end, then overshoot.
	c.shift_elapsed_seconds = c.shift_total_seconds - 1.0
	c.time_scale = 100.0
	c._physics_process(1.0)   # +100 game-s → past the end
	_ok(ended[0], "shift_ended fired at the boundary")
	_ok(rolled[0], "shift_rolled_over fired")
	_ok(c.day_index >= 1, "calendar advanced to a new day (day_index=%d)" % c.day_index)
	_ok(c.shift_active, "next shift is active (didn't freeze)")
	_ok(c.shift_elapsed_seconds < 60.0, "elapsed reset toward 07:00 (got %.1f)" % c.shift_elapsed_seconds)
	_ok(not c.is_resting_today(), "rolled onto a WORKING day, not a rest day")

# ── 4. auto_advance = false holds at the end ──────────────────────────────────
func _test_hold_when_no_autoadvance() -> void:
	print("[4] auto_advance=false holds at 15:00")
	var c := _make_clock()
	c.auto_advance = false
	c.start_shift()
	c.shift_elapsed_seconds = c.shift_total_seconds - 1.0
	c.time_scale = 100.0
	c._physics_process(1.0)
	_ok(not c.shift_active, "clock paused at the end")
	_ok(c.get_time_string() == "15:00", "held at 15:00 (got %s)" % c.get_time_string())

# ── 5. Load guard — a save left at the end must not reload frozen ─────────────
func _test_load_guard_against_frozen_end() -> void:
	print("[5] _roll_to_next_shift from a maxed clock starts fresh")
	var c := _make_clock()
	c.day_index = 0
	c.shift_elapsed_seconds = c.shift_total_seconds   # simulate a save at 15:00
	c._roll_to_next_shift()
	_ok(c.day_index >= 1, "day advanced past the frozen one")
	_ok(c.shift_elapsed_seconds < 60.0, "elapsed reset (got %.1f)" % c.shift_elapsed_seconds)
	_ok(c.get_time_string().begins_with("07"), "back to the 07:00 window (got %s)" % c.get_time_string())
