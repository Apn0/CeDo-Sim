extends SceneTree

var _pass := 0
var _fail := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _init() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== OperatorContext.npc_board_vehicle Tests ===")

	var script = load("res://src/operator/OperatorContext.gd")
	var op_ctx = script.new()
	op_ctx.name = "OperatorContext"
	root.add_child(op_ctx)

	# Test 1: Null inputs
	_ok(op_ctx.npc_board_vehicle(null, null) == false, "board_vehicle with null npc and vehicle returns false")

	var npc = Node.new()
	root.add_child(npc)
	_ok(op_ctx.npc_board_vehicle(npc, null) == false, "board_vehicle with null vehicle returns false")

	var vehicle = Node.new()
	root.add_child(vehicle)
	_ok(op_ctx.npc_board_vehicle(null, vehicle) == false, "board_vehicle with null npc returns false")

	# Test 2: Vehicle without on_npc_entered
	_ok(op_ctx.npc_board_vehicle(npc, vehicle) == false, "board_vehicle returns false if vehicle lacks on_npc_entered")

	# Test 3: Vehicle with can_enter() returning false
	var refuse_vehicle = MockRefuseVehicle.new()
	root.add_child(refuse_vehicle)
	_ok(op_ctx.npc_board_vehicle(npc, refuse_vehicle) == false, "board_vehicle returns false if vehicle can_enter() returns false")

	# Test 4: Successful boarding with _seated_in_vehicle
	var valid_vehicle = MockValidVehicle.new()
	root.add_child(valid_vehicle)

	var seated_npc = MockSeatedNPC.new()
	root.add_child(seated_npc)

	_ok(op_ctx.npc_board_vehicle(seated_npc, valid_vehicle) == true, "board_vehicle returns true on successful boarding")
	_ok(seated_npc.visible == false, "board_vehicle hides the NPC")
	_ok(seated_npc.get("_seated_in_vehicle") == true, "board_vehicle sets _seated_in_vehicle to true")
	_ok(valid_vehicle.last_npc == seated_npc, "board_vehicle calls on_npc_entered on vehicle")
	_ok(op_ctx._npc_vehicles.has(seated_npc.get_instance_id()) and op_ctx._npc_vehicles[seated_npc.get_instance_id()] == valid_vehicle, "board_vehicle registers link in _npc_vehicles")
	_ok(op_ctx.npc_vehicle_of(seated_npc) == valid_vehicle, "npc_vehicle_of returns correct vehicle")

	# Test 5: Successful boarding with legacy NPC (uses set_physics_process)
	var legacy_npc = MockLegacyNPC.new()
	root.add_child(legacy_npc)
	var valid_vehicle2 = MockValidVehicle.new()
	root.add_child(valid_vehicle2)

	_ok(op_ctx.npc_board_vehicle(legacy_npc, valid_vehicle2) == true, "board_vehicle returns true for legacy NPC")
	_ok(legacy_npc.visible == false, "board_vehicle hides the legacy NPC")
	_ok(legacy_npc.is_physics_processing() == false, "board_vehicle calls set_physics_process(false) on legacy NPC")
	_ok(valid_vehicle2.last_npc == legacy_npc, "board_vehicle calls on_npc_entered on vehicle for legacy NPC")
	_ok(op_ctx._npc_vehicles.has(legacy_npc.get_instance_id()) and op_ctx._npc_vehicles[legacy_npc.get_instance_id()] == valid_vehicle2, "board_vehicle registers link for legacy NPC")

	# Clean up
	root.remove_child(op_ctx)
	op_ctx.free()
	root.remove_child(npc)
	npc.free()
	root.remove_child(vehicle)
	vehicle.free()
	root.remove_child(refuse_vehicle)
	refuse_vehicle.free()
	root.remove_child(valid_vehicle)
	valid_vehicle.free()
	root.remove_child(seated_npc)
	seated_npc.free()
	root.remove_child(legacy_npc)
	legacy_npc.free()
	root.remove_child(valid_vehicle2)
	valid_vehicle2.free()

	print("\nResult: %d ok, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)
	return

class MockRefuseVehicle extends Node3D:
	func on_npc_entered(_npc: Node) -> void:
		pass
	func can_enter() -> bool:
		return false

class MockValidVehicle extends Node3D:
	var last_npc: Node = null
	func on_npc_entered(npc_node: Node) -> void:
		last_npc = npc_node
	func can_enter() -> bool:
		return true

class MockSeatedNPC extends Node3D:
	var _seated_in_vehicle: bool = false

class MockLegacyNPC extends Node3D:
	pass
