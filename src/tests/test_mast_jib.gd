extends Node
## Headless test for the MastLift folding jib (task #21).
##
## Run via the project boot path so the engine registers project.godot autoloads
## (EventBus, etc.) as /root globals — MastLift -> BaseVehicle._ready touches a
## few of them:
##
##   godot --headless --main-scene res://src/tests/test_mast_jib.tscn
##
## The recent jib rework (operator spec): the GRAY steel beam (_jib_lower /
## "JibLower") must stay PERFECTLY VERTICAL through the entire jib motion — it's a
## plumb riser. The ORANGE beam (_jib_upper / "JibUpper", driven via the
## "UpperPivot" hinge) carries ALL of the swing. This test instances a MastLift,
## drives jib_fold across [JIB_FOLD_MIN, JIB_FOLD_MAX] and asserts:
##   (1) JibLower stays vertical at every step (world up-vector ~ world-up,
##       local rotation.x ~ 0),
##   (2) the UpperPivot hinge angle changes MONOTONICALLY with jib_fold (the
##       orange actually swings),
##   (3) the platform tip moves as the jib folds.
##
## Prints a pass/fail summary and quits with code 0 (all pass) or 1 (any fail /
## could-not-run). Touches ONLY this test + its .tscn; no shared files edited.

const MAST_LIFT_SCENE := "res://src/scenes/vehicles/MastLift.tscn"
const EPS_VERTICAL    := 0.001    # rad / dot tolerance for "perfectly vertical"
const STEPS           := 12       # samples across the fold band

var _fail := 0
var _pass := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _section(title: String) -> void:
	print("\n[%s]" % title)

func _ready() -> void:
	print("=== MastLift jib headless test ===")
	await _run()
	_finish()

func _run() -> void:
	# ── Instance the lift via its real scene so _ready -> _build_jib runs the
	#    production path (procedural jib geometry follows jib_segment_m). ────────
	var packed := load(MAST_LIFT_SCENE) as PackedScene
	if packed == null:
		_ok(false, "could not load %s" % MAST_LIFT_SCENE)
		return
	var lift := packed.instantiate()
	if lift == null:
		_ok(false, "could not instantiate MastLift")
		return
	# Identity transform → world-up == the lift's local up, so a "vertical" check
	# in world space is unambiguous. Wait one frame first so the root has finished
	# setting up children (else add_child fails with "parent is busy").
	await get_tree().process_frame
	get_tree().root.add_child(lift)
	if lift is Node3D:
		(lift as Node3D).global_transform = Transform3D.IDENTITY
	# Let the deferred _ready cascade (BaseVehicle._install_vehicle_aux etc.) run.
	for _i in range(4):
		await get_tree().process_frame

	# ── Resolve the jib nodes. Prefer the script's own refs; fall back to the
	#    documented node paths so the test still works if the vars are renamed. ──
	_section("jib construction")
	var jib_lower : Node3D = lift.get("_jib_lower") as Node3D
	if jib_lower == null:
		jib_lower = lift.get_node_or_null("JibRoot/JibLower") as Node3D
	var jib_upper : Node3D = lift.get("_jib_upper") as Node3D
	if jib_upper == null:
		jib_upper = lift.get_node_or_null("JibRoot/JibLower/UpperPivot/JibUpper") as Node3D
	var jib_tip : Node3D = lift.get("_jib_tip") as Node3D
	if jib_tip == null:
		jib_tip = lift.get_node_or_null("JibRoot/JibLower/UpperPivot/JibUpper/JibTip") as Node3D
	var upper_pivot : Node3D = null
	if jib_lower != null:
		upper_pivot = jib_lower.get_node_or_null("UpperPivot") as Node3D
	var platform : Node3D = lift.get("_platform_node") as Node3D
	if platform == null:
		platform = lift.get_node_or_null("Platform") as Node3D

	_ok(jib_lower != null,   "JibLower (gray steel beam) built")
	_ok(jib_upper != null,   "JibUpper (orange beam) built")
	_ok(jib_tip != null,     "JibTip marker built")
	_ok(upper_pivot != null, "UpperPivot hinge built")
	_ok(platform != null,    "Platform node resolved")
	if jib_lower == null or jib_upper == null or jib_tip == null or upper_pivot == null:
		return   # nothing more we can assert without the nodes

	# ── Read the fold band + the lift's own apply method. ──────────────────────
	# NOTE: Object.get() does NOT resolve script CONSTANTS in Godot 4 — read the
	# constant map off the script instead (fall back to the documented values).
	var consts := {}
	if lift.get_script() != null:
		consts = (lift.get_script() as GDScript).get_script_constant_map()
	var fold_min : float = float(consts.get("JIB_FOLD_MIN", 0.10))
	var fold_max : float = float(consts.get("JIB_FOLD_MAX", 0.43))
	_ok(fold_max > fold_min, "fold band valid: [%.3f, %.3f]" % [fold_min, fold_max])
	var has_apply := lift.has_method("_apply_platform_transforms")
	_ok(has_apply, "MastLift has _apply_platform_transforms()")

	# Lift the mast a touch so the jib root is at a realistic working height (also
	# exercises _apply_platform_transforms' mast/jib-root Y tracking). Not required
	# for the geometry asserts, but makes the world positions non-degenerate.
	lift.set("_platform_height", 3.0)

	# ── Sweep jib_fold across the usable band and capture per-step samples. ─────
	_section("sweep jib_fold across [JIB_FOLD_MIN, JIB_FOLD_MAX]")
	var pivot_angles  : Array[float]   = []
	var tip_positions : Array[Vector3] = []
	var lower_vertical_worst_dot := 1.0     # min dot(up, world_up) over the sweep
	var lower_rotx_worst         := 0.0     # max |rotation.x| over the sweep

	for s in range(STEPS):
		var t := float(s) / float(STEPS - 1)
		var fold : float = lerpf(fold_min, fold_max, t)
		lift.set("jib_fold", fold)
		# Drive the production transform path (telescopes mast, positions jib root,
		# rotates hinges, re-parents the platform onto the tip).
		if has_apply:
			lift.call("_apply_platform_transforms")
		else:
			lift.call("_apply_jib_transforms")

		# (1) GRAY beam vertical — check in WORLD space + the local rotation.x.
		var up_world := (jib_lower.global_transform.basis.y).normalized()
		var dot_up := up_world.dot(Vector3.UP)
		lower_vertical_worst_dot = minf(lower_vertical_worst_dot, dot_up)
		lower_rotx_worst = maxf(lower_rotx_worst, absf(jib_lower.rotation.x))

		# (2) ORANGE swing — record the hinge angle.
		pivot_angles.append(upper_pivot.rotation.x)
		# (3) platform tip world position.
		tip_positions.append(jib_tip.global_position)

	# ── Assertion (1): GRAY beam perfectly vertical at EVERY step. ─────────────
	_section("(1) GRAY beam (JibLower) stays vertical")
	_ok(lower_vertical_worst_dot > 1.0 - EPS_VERTICAL,
		"JibLower up-vector stays ~world-up (worst dot = %.6f, want > %.6f)"
			% [lower_vertical_worst_dot, 1.0 - EPS_VERTICAL])
	_ok(lower_rotx_worst < EPS_VERTICAL,
		"JibLower local rotation.x stays ~0 (worst |rot.x| = %.6f rad)" % lower_rotx_worst)

	# ── Assertion (2): UpperPivot angle changes MONOTONICALLY with jib_fold. ───
	_section("(2) ORANGE beam (UpperPivot) swings monotonically")
	var total_swing := absf(pivot_angles[STEPS - 1] - pivot_angles[0])
	_ok(total_swing > 0.01,
		"UpperPivot.rotation.x changed over the sweep (Δ = %.4f rad, %.1f°)"
			% [total_swing, rad_to_deg(total_swing)])
	# Direction of the first non-zero delta defines monotonic direction; every
	# subsequent delta must share the sign (no reversal / no plateau-then-flip).
	var monotonic := true
	var dir := 0.0
	var smallest_step := INF
	for i in range(1, pivot_angles.size()):
		var d := pivot_angles[i] - pivot_angles[i - 1]
		if absf(d) > 0.0:
			smallest_step = minf(smallest_step, absf(d))
		if dir == 0.0:
			if absf(d) > 1e-9:
				dir = signf(d)
		elif absf(d) > 1e-9 and signf(d) != dir:
			monotonic = false
			break
	_ok(monotonic,
		"UpperPivot.rotation.x is monotonic across the sweep (dir = %s)"
			% ("up" if dir > 0.0 else ("down" if dir < 0.0 else "flat")))
	_ok(smallest_step > 0.0 and smallest_step != INF,
		"every fold step actually moves the hinge (smallest step = %.5f rad)"
			% (smallest_step if smallest_step != INF else 0.0))

	# ── Assertion (3): platform tip position changes with fold. ────────────────
	_section("(3) platform tip tracks the fold")
	var tip_span := tip_positions[0].distance_to(tip_positions[STEPS - 1])
	_ok(tip_span > 0.01,
		"JibTip world position moved over the sweep (Δ = %.4f m)" % tip_span)
	# And it should move at (essentially) every step, not jump once.
	var min_tip_step := INF
	var moved_each := true
	for i in range(1, tip_positions.size()):
		var step_d := tip_positions[i].distance_to(tip_positions[i - 1])
		min_tip_step = minf(min_tip_step, step_d)
		if step_d <= 1e-6:
			moved_each = false
	_ok(moved_each,
		"JibTip moves at every fold step (smallest step = %.6f m)"
			% (min_tip_step if min_tip_step != INF else 0.0))

	# Sanity echo of the captured extremes (handy when reading the log).
	print("    fold[min] pivot=%.4f rad  tip=%s" % [pivot_angles[0], tip_positions[0]])
	print("    fold[max] pivot=%.4f rad  tip=%s" % [pivot_angles[STEPS - 1], tip_positions[STEPS - 1]])

	lift.queue_free()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
