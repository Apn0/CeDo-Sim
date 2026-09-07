extends SceneTree

var _ok := 0
var _fail := 0
const CR = preload("res://src/scenes/player/CameraRig.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var rig = CR.new()

	_check(rig.is_active() == false, "Initial state should be inactive")

	rig.deactivate()
	_check(rig.is_active() == false, "Should be inactive after deactivate()")

	rig.free()

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_ok, _fail])
	print("=========================================")
	quit(1 if _fail > 0 else 0)
	return

func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  ok   : %s" % msg)
	else:
		_fail += 1
		print("  FAIL : %s" % msg)
