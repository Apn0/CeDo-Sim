extends Node3D
## Headless proof for ToolPlacementMode _nearest_slot
##
##   godot --headless --path . --main-scene res://src/tests/test_tool_placement_mode.tscn

const ToolPlacementMode = preload("res://src/build/ToolPlacementMode.gd")
const MockTool = preload("res://src/tests/test_tool_placement_mode_mock_tool.gd")

var _fails := 0

func _check(cond: bool, msg: String) -> void:
    if cond:
        print("  ok    : %s" % msg)
    else:
        print("  FAIL  : %s" % msg)
        _fails += 1

func _ready() -> void:
    print("=== ToolPlacementMode headless proof ===")

    var tpm = ToolPlacementMode.new()
    add_child(tpm)

    var nearest = tpm._nearest_slot(Vector3.ZERO)
    _check(nearest == null, "_nearest_slot returns null gracefully when no slots exist")

    var slot = Node3D.new()
    slot.add_to_group("tool_slot")
    add_child(slot)

    slot.global_position = Vector3(1, 0, 0)

    var nearest2 = tpm._nearest_slot(Vector3.ZERO)
    _check(nearest2 == slot, "_nearest_slot returns the slot when it exists and is within SNAP_RANGE_M")

    var nearest3 = tpm._nearest_slot(Vector3(10, 0, 0))
    _check(nearest3 == null, "_nearest_slot returns null when slot is outside SNAP_RANGE_M")

    var slot2 = Node3D.new()
    slot2.add_to_group("tool_slot")
    add_child(slot2)
    slot2.global_position = Vector3(0.5, 0, 0)

    var nearest4 = tpm._nearest_slot(Vector3.ZERO)
    _check(nearest4 == slot2, "_nearest_slot returns the closest slot")

    # Test `accepts` functionality
    slot2.set_meta("accepts", ["coffee"])
    var tool_coffee = MockTool.new()
    tpm.set("_tool", tool_coffee)

    var nearest5 = tpm._nearest_slot(Vector3.ZERO)
    _check(nearest5 == slot2, "_nearest_slot accepts matching tool based on tool_id")

    var tool_sandwich = MockTool.new()
    tool_sandwich.tool_id = "sandwich"
    tpm.set("_tool", tool_sandwich)

    var nearest6 = tpm._nearest_slot(Vector3.ZERO)
    _check(nearest6 == slot, "_nearest_slot ignores non-matching tool slot and finds next best")

    # Test _make_ghost
    var empty_node = Node3D.new()
    var ghost1 = tpm._make_ghost(empty_node)
    _check(ghost1 == null, "_make_ghost should return null for empty node tree")

    var mesh_node_no_mesh = MeshInstance3D.new()
    empty_node.add_child(mesh_node_no_mesh)
    var ghost2 = tpm._make_ghost(empty_node)
    _check(ghost2 == null, "_make_ghost should return null for MeshInstance3D with no mesh")

    var valid_mesh_node = MeshInstance3D.new()
    var box_mesh = BoxMesh.new()
    valid_mesh_node.mesh = box_mesh
    empty_node.add_child(valid_mesh_node)
    var ghost3 = tpm._make_ghost(empty_node)
    _check(ghost3 != null, "_make_ghost should return a valid MeshInstance3D when a mesh is present")
    _check(ghost3 is MeshInstance3D, "Returned ghost should be a MeshInstance3D")
    _check(ghost3.mesh == box_mesh, "Returned ghost should have the same mesh")

    if ghost3:
        ghost3.queue_free()
    empty_node.queue_free()

    print("Result: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))

    tpm.queue_free()
    slot.queue_free()
    slot2.queue_free()
    tool_coffee.queue_free()
    tool_sandwich.queue_free()

    get_tree().quit(0 if _fails == 0 else 1)
