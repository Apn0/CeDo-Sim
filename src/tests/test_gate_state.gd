extends SceneTree
## Headless test for Gate.gd state semantics (src/build/Gate.gd).
##
## Finding (2026-08-31 review): is_fully_open()/is_fully_closed() (Gate.gd:101,104)
## were untested — the 0.999 / 0.001 thresholds, the set_drive clamp, and the
## _physics_process travel/limit-switch behavior had no coverage at all.
##
## Run: godot --headless --path . --script res://src/tests/test_gate_state.gd --quit-after 300
##
## Counted checks, not assert() — a failing assert aborts before quit() so the
## harness HANGS instead of failing, and assert compiles out of release builds
## (see src/tests/test_walkie.gd for the full rationale).
##
## Motion is exercised by calling _physics_process(dt) DIRECTLY with a fixed dt.
## That is deterministic: the method is pure float stepping
## (step = dt / travel_time * drive, clampf to [0,1]) — no physics engine state
## is consulted, so no real physics ticks are needed.
##
## The gate IS added to root: its _ready only joins the "gate" group, resolves
## LeafScaler via get_node_or_null (we provide a real Node3D one so the
## _apply_open_t scale path runs for real), and builds its InteractTrigger
## Area3D in code — no .tscn structure required.

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== Gate State Tests ===")

	var GateScript = load("res://src/build/Gate.gd")
	var script_ok: bool = GateScript != null
	_ok(script_ok, "Gate.gd script loads")
	if not script_ok:
		_finish()
		return

	var gate = GateScript.new()
	gate.name = "TestGate"
	# Real LeafScaler child so _ready's get_node_or_null resolves and
	# _apply_open_t exercises its real scale-writing branch (not the null bail).
	var scaler := Node3D.new()
	scaler.name = "LeafScaler"
	gate.add_child(scaler)
	root.add_child(gate)  # runs the real _ready

	# ---- 1. Fresh gate: default state is fully OPEN -------------------------
	# Changed 2026-09-03 on the operator's ruling that the real 3A/3B gate "is
	# usually open". These three checks used to assert the opposite; they are
	# not flipped to make anything pass. A gate that spawns CLOSED is a sealed
	# doorway, because a closed leaf is a real collider, VehicleRouteGrid
	# shape-casts real colliders, and nothing in this codebase lets an NPC press
	# a button. The old default made every indoor->outdoor haul unroutable.
	print("Test: Fresh gate defaults (OPEN — operator ruling 2026-09-03)")
	_ok(gate.is_fully_open() == true, "Fresh gate is_fully_open() true (usually-open ruling)")
	_ok(gate.is_fully_closed() == false, "Fresh gate is_fully_closed() false")
	_ok(gate._drive == 0, "Fresh gate drive is 0 (stopped, not still travelling)")
	var scaler_ok: bool = gate._scaler != null
	_ok(scaler_ok, "_ready resolved LeafScaler")
	_ok(scaler_ok and absf(gate._scaler.scale.y - 0.04) < 0.0001,
		"Fresh leaf rolled up to _opened_min scale (y=0.04), so the doorway is clear")

	# The gate must still be closable — a default is not a lock.
	gate.travel_time = 4.0
	gate.set_drive(-1)
	for _i in 4:
		gate._physics_process(1.0)
	_ok(gate.is_fully_closed() == true, "A fresh gate still drives fully shut on DOWN")
	_ok(gate._drive == 0, "Closing trips the limit switch and stops the drive")
	gate.set_drive(1)
	for _j in 4:
		gate._physics_process(1.0)
	_ok(gate.is_fully_open() == true, "...and drives fully open again on UP")

	# ---- 2. Threshold semantics of is_fully_open / is_fully_closed ----------
	print("Test: Threshold boundaries")
	gate._open_t = 1.0
	_ok(gate.is_fully_open() == true, "_open_t=1.0 -> is_fully_open true")
	_ok(gate.is_fully_closed() == false, "_open_t=1.0 -> is_fully_closed false")

	gate._open_t = 0.9995  # just above the 0.999 threshold
	_ok(gate.is_fully_open() == true, "_open_t=0.9995 (>0.999) -> fully open")
	gate._open_t = 0.998   # just below the 0.999 threshold
	_ok(gate.is_fully_open() == false, "_open_t=0.998 (<0.999) -> NOT fully open")

	gate._open_t = 0.0005  # just below the 0.001 threshold
	_ok(gate.is_fully_closed() == true, "_open_t=0.0005 (<0.001) -> fully closed")
	gate._open_t = 0.002   # just above the 0.001 threshold
	_ok(gate.is_fully_closed() == false, "_open_t=0.002 (>0.001) -> NOT fully closed")

	gate._open_t = 0.5
	_ok(gate.is_fully_open() == false, "Mid-travel 0.5: not fully open")
	_ok(gate.is_fully_closed() == false, "Mid-travel 0.5: not fully closed")

	# ---- 3. set_drive clamps to [-1, 1] -------------------------------------
	print("Test: set_drive clamp")
	gate.set_drive(5)
	_ok(gate._drive == 1, "set_drive(5) clamps to +1")
	gate.set_drive(-5)
	_ok(gate._drive == -1, "set_drive(-5) clamps to -1")
	gate.set_drive(0)
	_ok(gate._drive == 0, "set_drive(0) stops")

	# ---- 4. Motion via direct _physics_process(dt) --------------------------
	print("Test: Drive motion")
	gate.travel_time = 4.0  # 1s tick = 0.25 travel
	gate._open_t = 0.0
	gate.set_drive(1)
	gate._physics_process(1.0)
	_ok(absf(gate._open_t - 0.25) < 0.0001, "Drive +1, 1s tick raises _open_t to 0.25")
	_ok(gate._drive == 1, "Mid-travel: drive keeps running (no premature limit stop)")
	gate._physics_process(1.0)
	gate._physics_process(1.0)
	gate._physics_process(1.0)
	_ok(absf(gate._open_t - 1.0) < 0.0001, "Four 1s ticks reach _open_t=1.0")
	_ok(gate._drive == 0, "Limit switch: drive auto-stops at fully open")
	_ok(gate.is_fully_open() == true, "Driven gate reports fully open")
	_ok(scaler_ok and absf(gate._scaler.scale.y - 0.04) < 0.0001, "Open leaf rolled up to _opened_min scale")

	gate.set_drive(-1)
	gate._physics_process(1.0)
	_ok(absf(gate._open_t - 0.75) < 0.0001, "Drive -1, 1s tick lowers _open_t to 0.75")
	gate._physics_process(1.0)
	gate._physics_process(1.0)
	gate._physics_process(1.0)
	_ok(absf(gate._open_t - 0.0) < 0.0001, "Four 1s ticks return to _open_t=0.0")
	_ok(gate._drive == 0, "Limit switch: drive auto-stops at fully closed")
	_ok(gate.is_fully_closed() == true, "Driven gate reports fully closed")
	_ok(scaler_ok and absf(gate._scaler.scale.y - 1.0) < 0.0001, "Closed leaf back at full scale")

	# Clamp at the ends: an oversized step must not overshoot [0,1].
	print("Test: Travel clamp")
	gate._open_t = 0.9
	gate.set_drive(1)
	gate._physics_process(1.0)  # raw step 0.25 would give 1.15
	_ok(absf(gate._open_t - 1.0) < 0.0001, "Upward step clamps at 1.0 (no overshoot)")
	_ok(gate._drive == 0, "Clamped upward arrival trips the limit switch")
	gate._open_t = 0.1
	gate.set_drive(-1)
	gate._physics_process(1.0)  # raw step -0.25 would give -0.15
	_ok(absf(gate._open_t - 0.0) < 0.0001, "Downward step clamps at 0.0 (no undershoot)")
	_ok(gate._drive == 0, "Clamped downward arrival trips the limit switch")

	# Drive 0 = deadman released: _physics_process must be a no-op.
	gate._open_t = 0.5
	gate.set_drive(0)
	gate._physics_process(1.0)
	_ok(absf(gate._open_t - 0.5) < 0.0001, "Drive 0: _physics_process leaves _open_t untouched")

	# Cleanup
	root.remove_child(gate)
	gate.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
