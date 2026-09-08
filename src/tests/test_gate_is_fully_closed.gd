extends SceneTree

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
	print("=== Gate is_fully_closed Tests ===")

	var GateScript = load("res://src/build/Gate.gd")
	if GateScript == null:
		_ok(false, "Gate.gd script loaded")
		_finish()
		return

	# We mock the necessary functions to bypass _ready() dependencies on the tree
	# and autoloads that fail compilation in headless mode, as we just want to test
	# the snippet logic for is_fully_closed().
	var gate = GateScript.new()
	if gate == null:
		_ok(false, "Gate.gd script instantiable")
		_finish()
		return

	# Test 1: Exactly on the boundary (<= 0.001)
	gate._open_t = 0.001
	_ok(gate.is_fully_closed() == true, "is_fully_closed() true for _open_t = 0.001")

	# Test 2: Below boundary
	gate._open_t = 0.0005
	_ok(gate.is_fully_closed() == true, "is_fully_closed() true for _open_t = 0.0005")

	gate._open_t = 0.0
	_ok(gate.is_fully_closed() == true, "is_fully_closed() true for _open_t = 0.0")

	gate._open_t = -1.0
	_ok(gate.is_fully_closed() == true, "is_fully_closed() true for negative _open_t = -1.0")

	# Test 3: Above boundary
	gate._open_t = 0.002
	_ok(gate.is_fully_closed() == false, "is_fully_closed() false for _open_t = 0.002")

	gate._open_t = 0.5
	_ok(gate.is_fully_closed() == false, "is_fully_closed() false for _open_t = 0.5")

	gate._open_t = 1.0
	_ok(gate.is_fully_closed() == false, "is_fully_closed() false for _open_t = 1.0")

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
