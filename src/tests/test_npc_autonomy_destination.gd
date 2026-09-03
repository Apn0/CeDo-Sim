extends SceneTree

var _pass = 0
var _fail = 0

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
	print("=== NPC Autonomy Destination Tests ===")

	var NPCClass = load("res://src/scenes/world/NPC.gd")
	var npc = QuietNPC.new()
	npc.name = "TestNPC"
	root.add_child(npc)

	# Test baseline
	_ok(npc.target_position == Vector3.ZERO, "target_position is initially zero")

	# Test setting destination (walking branch)
	var dest = Vector3(10.0, 0.0, 5.0)
	npc.set_autonomy_destination(dest)
	_ok(npc.target_position.is_equal_approx(dest), "destination vector is stored correctly natively")

	# Test boarded in vehicle - fallback logic (vehicle lacks npc_set_target)
	var op_ctx = MockOperatorContext.new()
	op_ctx.name = "OperatorContext"
	var fallback_vehicle = MockVehicleMissingMethod.new()
	op_ctx._veh = fallback_vehicle
	root.add_child(op_ctx)

	var dest2 = Vector3(20.0, 0.0, 10.0)
	npc.set_autonomy_destination(dest2)
	_ok(npc.target_position.is_equal_approx(dest2), "fallback stores vector if vehicle lacks npc_set_target")

	# Test boarded in vehicle - primary logic (vehicle HAS npc_set_target)
	var primary_vehicle = MockVehicleWithMethod.new()
	op_ctx._veh = primary_vehicle

	var dest3 = Vector3(30.0, 0.0, 15.0)
	npc.set_autonomy_destination(dest3)
	_ok(primary_vehicle.called_with_pos != null and primary_vehicle.called_with_pos.is_equal_approx(dest3), "routes to vehicle's npc_set_target if available")
	_ok(npc.target_position.is_equal_approx(dest2), "does not overwrite native target_position when routed to vehicle")

	root.remove_child(op_ctx)
	op_ctx.free()
	fallback_vehicle.free()
	primary_vehicle.free()

	root.remove_child(npc)
	npc.free()

	print("\nResult: %d ok, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

class QuietNPC extends "res://src/scenes/world/NPC.gd":
	func _ready() -> void:
		pass

class MockOperatorContext extends Node:
	var _veh: Node
	func npc_vehicle_of(npc: Node) -> Node:
		return _veh

class MockVehicleMissingMethod extends Node:
	pass

class MockVehicleWithMethod extends Node:
	var called_with_pos = null
	func npc_set_target(pos: Vector3) -> void:
		called_with_pos = pos
