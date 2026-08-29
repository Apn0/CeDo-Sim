extends SceneTree

var _pass := 0
var _fail := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ok    : " + msg)
	else:
		_fail += 1
		print("  FAIL  : " + msg)

func _initialize() -> void:
	print("=== Inventory Autoload Tests ===")

	var inv = load("res://src/autoload/Inventory.gd").new()
	var root_node = Node3D.new()
	root.add_child(root_node)
	root_node.add_child(inv)

	# Simulate Player
	var player = Node3D.new()
	var head = Node3D.new()
	head.name = "Head"
	player.add_child(head)
	root_node.add_child(player)

	inv.player_ref = player

	# 1. Initial State
	_ok(inv.is_full() == false, "Initial inventory is not full")
	_ok(inv.total_carried_kg() == 0.0, "Initial mass is 0.0")
	_ok(inv.active() == null, "Initial active is null")

	# 2. Test take() and mass
	var t1 = _mock_tool("leaf_blower")
	_ok(inv.take(t1), "take() returns true when adding tool 1")
	_ok(inv.active() == t1, "take() sets active tool if active was null")
	_ok(t1.get_parent() == head, "Tool was re-parented to Head")
	_ok(t1.visible == true, "Active tool is visible")

	var t2 = _mock_tool("wire_cutter")
	_ok(inv.take(t2), "take() returns true when adding tool 2")
	_ok(inv.active() == t1, "take() does not change active if already set")
	_ok(t2.visible == false, "Inactive tool is hidden")

	# leaf_blower = 9.0 kg, wire_cutter = 0.6 kg -> Total 9.6 kg
	var kg = inv.total_carried_kg()
	_ok(abs(kg - 9.6) < 0.01, "total_carried_kg is 9.6 (got %f)" % kg)

	# 3. Test Fill up
	var t3 = _mock_tool("unknown_tool") # default mass 1.0
	var t4 = _mock_tool("scissors")
	var t5 = _mock_tool("barcode_scanner")
	inv.take(t3)
	inv.take(t4)
	inv.take(t5)

	_ok(inv.is_full() == true, "Inventory is full after 5 items")
	var t6 = _mock_tool("spade")
	_ok(inv.take(t6) == false, "take() returns false when full")

	# 4. Test set_active()
	inv.set_active(1)
	_ok(inv.active() == t2, "set_active(1) switched active tool to wire_cutter")
	_ok(t2.visible == true, "wire_cutter is now visible")
	_ok(t1.visible == false, "leaf_blower is now hidden")

	# 5. Test drop_active()
	var dropped = inv.drop_active()
	_ok(dropped == t2, "drop_active() returned the active tool")
	_ok(inv.active() == null, "Active slot is now empty")
	_ok(inv.is_full() == false, "Inventory is no longer full")

	# 6. Test remove()
	inv.remove(t3)
	_ok(inv.slots[2] == null, "remove() clears the tool's slot")

	# 7. Test slot_label()
	_ok(inv.slot_label(0) == "leaf_blower", "slot_label(0) returns tool_id")
	_ok(inv.slot_label(1) == "—", "slot_label(1) for empty slot returns '—'")

	# 8. Test Freed Node Handling
	inv.slots[3] = t4
	t4.free()
	_ok(inv.slot_label(3) == "—", "slot_label() self-heals freed node")
	_ok(inv.slots[3] == null, "slot_label() cleared freed node from slots")

	print("\nResult: %d ok, %d fail" % [_pass, _fail])

	t6.free()

	# We must manually free mock tools to avoid "ObjectDB instances leaked at exit"
	for t in [t1, t2, t3, t5]:
		if is_instance_valid(t):
			if t.get_parent():
				t.get_parent().remove_child(t)
			t.free()

	# Remove the autoload to prevent crash/leak logic for normal autoloads
	root_node.remove_child(inv)
	inv.free()
	root_node.free()

	quit(0 if _fail == 0 else 1)

func _mock_tool(tid: String) -> Node3D:
	var node = MockTool.new()
	node.tool_id = tid
	node.name = tid
	return node

class MockTool extends Node3D:
	var tool_id : String = ""
	func on_draw():
		pass
	func on_holster():
		pass
