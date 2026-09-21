extends SceneTree

# OperatorContext.gd is LOADED in _initialize(), never preloaded. It references the
# EventBus autoload, and a preload compiles it while this script is still compiling —
# before autoload names exist — so it failed "Identifier not found: EventBus", .new()
# errored, no check ran and no Result line was printed: this suite was red in run.sh
# from the day it was wired (measured 2026-09-21). test_operator_context_board_vehicle.gd
# uses the same runtime load.
const OPERATOR_CONTEXT_PATH := "res://src/operator/OperatorContext.gd"

var _pass := 0
var _fail := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _initialize() -> void:
	print("=== OperatorContext interactable verification ===")

	var oc = load(OPERATOR_CONTEXT_PATH).new()
	root.add_child(oc)

	_ok(oc.interactable_vehicle == null, "interactable_vehicle starts as null")

	var vehicle1 = Node3D.new()
	var vehicle2 = Node3D.new()

	oc.register_interactable(vehicle1)
	_ok(oc.interactable_vehicle == vehicle1, "register_interactable sets the vehicle")

	oc.register_interactable(vehicle2)
	_ok(oc.interactable_vehicle == vehicle2, "register_interactable overrides the vehicle")

	oc.unregister_interactable(vehicle1)
	_ok(oc.interactable_vehicle == vehicle2, "unregister_interactable ignores mismatching vehicle")

	oc.unregister_interactable(vehicle2)
	_ok(oc.interactable_vehicle == null, "unregister_interactable clears matching vehicle")

	vehicle1.free()
	vehicle2.free()
	oc.free()

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	quit(0 if _fail == 0 else 1)
