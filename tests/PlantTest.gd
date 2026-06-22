extends SceneTree
## Headless tests for Plant.gd — the PC coordinate system foundation (#221-PC Phase 1).
##
## Each test creates a fresh Plant instance via PlantScript.new(); we don't poke
## the live autoload singleton. This matches the convention used by the other
## SceneTree-extended tests in this directory (see WireFixAndCameraTest.gd) —
## autoloads aren't reachable by identifier name when Godot is invoked with -s,
## so we preload the script directly.
##
## Verifies:
##   • Pre-init guard (no NaN/INF; safe defaults)
##   • Centre invariant (pc=(500,500) → scene_origin XZ, Y=floor_top_y)
##   • Y handling (pc_to_scene bakes floor_top_y; _with_y respects override)
##   • Yaw=0 east/south displacement (PC X+/Y+ → scene X+/Z+)
##   • Yaw=+90° rotation direction (PC +X → scene −Z per right-hand rule)
##   • Round-trip identity (pc → scene → pc within 1e-3 m)
##   • Initialise-once contract (second init() warns and is no-op)
##   • plant_initialized signal fires exactly once
##
## Run: godot --headless -s res://tests/PlantTest.gd

const PlantScript := preload("res://src/autoload/Plant.gd")

const TOL_M   : float = 1.0e-3
const TOL_RAD : float = 1.0e-6

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Plant.gd (PC coord system) Phase 1 tests")
	print("============================================================")

	_test_pre_init_guard()
	_test_centre_invariant()
	_test_y_handling()
	_test_yaw_zero_displacement()
	_test_yaw_90_rotation()
	_test_round_trip_identity()
	_test_initialise_once_contract()
	_test_initialised_signal()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")
	quit(0 if _fail == 0 else 1)

# ── Helpers ──────────────────────────────────────────────────────────────────
func _mk() -> Node:
	# Returns a fresh, uninitialised Plant instance. Caller owns disposal but
	# since the tests are short-lived and the script frees on quit, we don't
	# bother freeing manually.
	return PlantScript.new()

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

func _ok_v3(actual: Vector3, expected: Vector3, label: String) -> void:
	var d : float = (actual - expected).length()
	if d > TOL_M:
		label = "%s  (expected %s, got %s, |Δ|=%.6f)" % [
			label, str(expected), str(actual), d]
	_ok(d <= TOL_M, label)

func _ok_v2(actual: Vector2, expected: Vector2, label: String) -> void:
	var d : float = (actual - expected).length()
	if d > TOL_M:
		label = "%s  (expected %s, got %s, |Δ|=%.6f)" % [
			label, str(expected), str(actual), d]
	_ok(d <= TOL_M, label)

func _ok_f(actual: float, expected: float, tol: float, label: String) -> void:
	var d : float = absf(actual - expected)
	if d > tol:
		label = "%s  (expected %.6f ±%.6f, got %.6f)" % [label, expected, tol, actual]
	_ok(d <= tol, label)

# =============================================================================
# (1) Pre-init guard — never NaN, never INF, never crashes
# =============================================================================
func _test_pre_init_guard() -> void:
	print("[1] Pre-init guard")
	var p : Node = _mk()
	_ok(not p.is_initialized(), "is_initialized() == false before init")
	_ok_v3(p.pc_to_scene(Vector2(500, 500)), Vector3.ZERO,
		"pc_to_scene pre-init returns Vector3.ZERO")
	_ok_v2(p.scene_to_pc(Vector3.ZERO), Vector2.ZERO,
		"scene_to_pc pre-init returns Vector2.ZERO")
	_ok_v3(p.factory_center_scene(), Vector3.ZERO,
		"factory_center_scene pre-init returns Vector3.ZERO")

# =============================================================================
# (2) Centre invariant — pc=(500,500) maps exactly to scene_origin XZ
# =============================================================================
func _test_centre_invariant() -> void:
	print("[2] Centre invariant")
	var p : Node = _mk()
	p.init(Vector3(100.0, 0.0, 200.0), 0.0, 1.5)
	_ok(p.is_initialized(), "is_initialized() == true after init")
	_ok_v3(p.pc_to_scene(Vector2(500, 500)), Vector3(100.0, 1.5, 200.0),
		"pc(500,500) yaw=0 → (100, 1.5, 200)")
	_ok_v3(p.factory_center_scene(), Vector3(100.0, 1.5, 200.0),
		"factory_center_scene() agrees with pc_to_scene(PC_CENTER)")

# =============================================================================
# (3) Y handling — default bakes floor_top_y; _with_y respects override
# =============================================================================
func _test_y_handling() -> void:
	print("[3] Y handling")
	var p : Node = _mk()
	p.init(Vector3(0.0, 0.0, 0.0), 0.0, 5.25)
	var v : Vector3 = p.pc_to_scene(Vector2(700.0, 300.0))
	_ok_f(v.y, 5.25, TOL_M, "pc_to_scene bakes floor_top_y=5.25")
	var v2 : Vector3 = p.pc_to_scene_with_y(Vector2(700.0, 300.0), 42.0)
	_ok_f(v2.y, 42.0, TOL_M, "pc_to_scene_with_y honours override Y=42")
	_ok_f(v2.x, v.x, TOL_M, "pc_to_scene_with_y preserves X")
	_ok_f(v2.z, v.z, TOL_M, "pc_to_scene_with_y preserves Z")

# =============================================================================
# (4) Yaw=0 displacement — PC +X → scene +X, PC +Y → scene +Z
# =============================================================================
func _test_yaw_zero_displacement() -> void:
	print("[4] Yaw=0 displacement")
	var p : Node = _mk()
	p.init(Vector3.ZERO, 0.0, 0.0)
	_ok_v3(p.pc_to_scene(Vector2(600.0, 500.0)),
		Vector3(100.0, 0.0, 0.0),
		"pc(600,500) yaw=0 → (+100, 0, 0)")
	_ok_v3(p.pc_to_scene(Vector2(500.0, 600.0)),
		Vector3(0.0, 0.0, 100.0),
		"pc(500,600) yaw=0 → (0, 0, +100)")
	_ok_v3(p.pc_to_scene(Vector2(0.0, 0.0)),
		Vector3(-500.0, 0.0, -500.0),
		"pc(0,0) yaw=0 → (−500, 0, −500)")
	_ok_v3(p.pc_to_scene(Vector2(1000.0, 1000.0)),
		Vector3(500.0, 0.0, 500.0),
		"pc(1000,1000) yaw=0 → (+500, 0, +500)")

# =============================================================================
# (5) Yaw=+90° rotation — Godot right-handed Y-up convention
#
#  Basis(Vector3.UP, +π/2) rotates +X toward -Z (right-hand rule).
#  So PC (+100m east of centre) lands at scene (0, 0, −100).
# =============================================================================
func _test_yaw_90_rotation() -> void:
	print("[5] Yaw=+90° rotation direction")
	var p : Node = _mk()
	p.init(Vector3.ZERO, PI * 0.5, 0.0)
	var expected_east : Vector3 = Basis(Vector3.UP, PI * 0.5) * Vector3(100.0, 0.0, 0.0)
	_ok_v3(p.pc_to_scene(Vector2(600.0, 500.0)),
		expected_east,
		"pc(600,500) yaw=+90° matches raw Basis(UP, π/2) * (100, 0, 0)")
	var expected_south : Vector3 = Basis(Vector3.UP, PI * 0.5) * Vector3(0.0, 0.0, 100.0)
	_ok_v3(p.pc_to_scene(Vector2(500.0, 600.0)),
		expected_south,
		"pc(500,600) yaw=+90° matches raw Basis(UP, π/2) * (0, 0, 100)")

# =============================================================================
# (6) Round-trip identity — pc → scene → pc must reproduce input
# =============================================================================
func _test_round_trip_identity() -> void:
	print("[6] Round-trip identity (sweep, yaw=37°)")
	var p : Node = _mk()
	p.init(Vector3(-123.4, 0.0, 567.8), deg_to_rad(37.0), 2.0)
	var max_err : float = 0.0
	var samples : int = 0
	for ix in range(11):
		for iy in range(11):
			var pc : Vector2 = Vector2(float(ix) * 100.0, float(iy) * 100.0)
			var scene : Vector3 = p.pc_to_scene(pc)
			var pc_back : Vector2 = p.scene_to_pc(scene)
			var err : float = (pc_back - pc).length()
			if err > max_err:
				max_err = err
			samples += 1
	_ok(max_err <= TOL_M,
		"round-trip identity over %d samples (max |Δ|=%.6f m)" % [samples, max_err])
	var pc_fine : Vector2 = Vector2(345.6789, 712.3456)
	var rt : Vector2 = p.scene_to_pc(p.pc_to_scene(pc_fine))
	_ok_v2(rt, pc_fine, "round-trip pc=(345.6789, 712.3456) yaw=37°")

# =============================================================================
# (7) Initialise-once contract — second init() warns AND is no-op
# =============================================================================
func _test_initialise_once_contract() -> void:
	print("[7] Initialise-once contract")
	var p : Node = _mk()
	p.init(Vector3(100.0, 0.0, 200.0), 0.0, 1.5)
	p.init(Vector3(999.0, 99.0, 999.0), deg_to_rad(123.0), 50.0)
	_ok_v3(p.factory_center_scene(), Vector3(100.0, 1.5, 200.0),
		"second init() ignored — factory_center_scene unchanged")
	_ok_f(p.world_yaw_rad(), 0.0, TOL_RAD,
		"second init() ignored — world_yaw_rad unchanged")
	_ok_f(p.floor_top_y(), 1.5, TOL_M,
		"second init() ignored — floor_top_y unchanged")

# =============================================================================
# (8) plant_initialized signal fires exactly once
# =============================================================================
func _test_initialised_signal() -> void:
	print("[8] plant_initialized signal")
	var p : Node = _mk()
	var counter : Array = [0]   # mutable counter usable by inline lambda
	p.plant_initialized.connect(func(): counter[0] += 1)
	p.init(Vector3.ZERO, 0.0, 0.0)
	_ok(counter[0] == 1, "plant_initialized fired once on first init (got %d)" % counter[0])
	p.init(Vector3(1.0, 0.0, 1.0), 0.5, 1.0)
	_ok(counter[0] == 1, "plant_initialized did NOT fire on second init (got %d)" % counter[0])
