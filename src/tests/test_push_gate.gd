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
	print("=== PUSH GATE TEST ===")
	var PushGate = load("res://src/build/PushGate.gd")
	# Guard, not a counted check: a null script makes the .new() below abort this
	# function with a runtime error BEFORE any quit(), which idles the harness
	# forever instead of failing it. Only reports when it trips.
	if PushGate == null:
		_ok(false, "res://src/build/PushGate.gd loaded")
		_finish()
		return
	var gate = PushGate.new()
	var root = get_root()
	root.add_child(gate)

	# Delay execution to allow Node3D tree setup.
	call_deferred("_test_logic", gate, root)

func _test_logic(gate: Node3D, root: Window) -> void:
	var player = Node3D.new()
	player.name = "Player"
	root.add_child(player)

	gate.global_position = Vector3(10.0, 0.0, 10.0)
	# Rotate gate 90 degrees around Y just to make sure local space math works correctly
	gate.rotation_degrees = Vector3(0, 90, 0)

	print("[TEST] PushGate._player_is_on_free_side")

	# Guard, not a counted check: every check below calls this method. If it were
	# ever renamed in PushGate.gd the call would abort _test_logic before the
	# verdict block and the harness would HANG rather than go red. Probe once.
	if not gate.has_method("_player_is_on_free_side"):
		_ok(false, "PushGate exposes _player_is_on_free_side")
		_finish()
		return

	# Test free_side_idx = 0 (+X)
	gate.free_side_idx = 0
	# Local +X should be True. Since rotation is +90 (yaw left), local +X is world -Z
	player.global_position = gate.global_transform * Vector3(1.0, 0.0, 0.0)
	_ok(gate._player_is_on_free_side(player) == true, "free_side_idx 0 (+X) should be true on local +X")
	# Local -X should be False
	player.global_position = gate.global_transform * Vector3(-1.0, 0.0, 0.0)
	_ok(gate._player_is_on_free_side(player) == false, "free_side_idx 0 (+X) should be false on local -X")

	# Test free_side_idx = 1 (-X)
	gate.free_side_idx = 1
	player.global_position = gate.global_transform * Vector3(-1.0, 0.0, 0.0)
	_ok(gate._player_is_on_free_side(player) == true, "free_side_idx 1 (-X) should be true on local -X")
	player.global_position = gate.global_transform * Vector3(1.0, 0.0, 0.0)
	_ok(gate._player_is_on_free_side(player) == false, "free_side_idx 1 (-X) should be false on local +X")

	# Test free_side_idx = 2 (+Z)
	gate.free_side_idx = 2
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, 1.0)
	_ok(gate._player_is_on_free_side(player) == true, "free_side_idx 2 (+Z) should be true on local +Z")
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, -1.0)
	_ok(gate._player_is_on_free_side(player) == false, "free_side_idx 2 (+Z) should be false on local -Z")

	# Test free_side_idx = 3 (-Z)
	gate.free_side_idx = 3
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, -1.0)
	_ok(gate._player_is_on_free_side(player) == true, "free_side_idx 3 (-Z) should be true on local -Z")
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, 1.0)
	_ok(gate._player_is_on_free_side(player) == false, "free_side_idx 3 (-Z) should be false on local +Z")

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
