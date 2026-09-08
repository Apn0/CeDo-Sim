extends SceneTree

const OperatorContext = preload("res://src/operator/OperatorContext.gd")

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

	var oc = OperatorContext.new()
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
