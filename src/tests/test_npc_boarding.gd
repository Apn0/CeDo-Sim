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
	call_deferred("_run")

func _run() -> void:
	print("=== NPC Boarding Logic ===")

	var op_ctx = MockOperatorContext.new()
	op_ctx.name = "OperatorContext"
	root.add_child(op_ctx)

	var npc = load("res://src/scenes/world/NPC.gd").new()
	npc.name = "NPC"
	root.add_child(npc)

	var vehicle = Node.new()

	# 1. Null vehicle check
	var board_null = npc.board_vehicle(null)
	_ok(board_null == false, "board_vehicle returns false when passed null")

	# 2. Successful boarding
	var board_res = npc.board_vehicle(vehicle)
	_ok(board_res == true, "board_vehicle returns true on success")
	_ok(op_ctx.last_boarded_npc == npc, "board_vehicle passes correct NPC to OperatorContext")
	_ok(op_ctx.last_boarded_vehicle == vehicle, "board_vehicle passes correct vehicle to OperatorContext")

	# 3. Disembark
	npc.disembark_vehicle()
	_ok(op_ctx.last_disembarked_npc == npc, "disembark_vehicle passes correct NPC to OperatorContext")

	# 4. Missing OperatorContext
	root.remove_child(op_ctx)
	op_ctx.free()

	var board_res_no_ctx = npc.board_vehicle(vehicle)
	_ok(board_res_no_ctx == false, "board_vehicle returns false if no OperatorContext is found")

	# 5. Missing OperatorContext disembark gracefully
	npc.disembark_vehicle()
	_ok(true, "disembark_vehicle handles missing OperatorContext gracefully")

	npc.free()
	vehicle.free()

	print("\nResult: %d ok, %d fail" % [_pass, _fail])
	quit(0 if _fail == 0 else 1)

class MockOperatorContext extends Node:
	var last_boarded_npc: Node = null
	var last_boarded_vehicle: Node = null
	var last_disembarked_npc: Node = null

	func npc_board_vehicle(npc: Node, vehicle: Node) -> bool:
		last_boarded_npc = npc
		last_boarded_vehicle = vehicle
		return true

	func npc_disembark_vehicle(npc: Node) -> void:
		last_disembarked_npc = npc
