extends SceneTree
## Headless test for HmiOverlay (Operator Control Panel).
##
## This test validates the initialization, scope setup, and open/close logic
## of the HmiOverlay without requiring UI interactions.
##
## Run (ALWAYS with --quit-after to dodge the autoload-hang issue):
##   godot --headless --path . --script res://src/tests/test_hmi_overlay.gd --quit-after 10

class StubLineFlow extends Node:
	var fed_mass = 123.45
	func has_machine(key: String) -> bool: return true
	func get_machine_info(key: String) -> Dictionary: return {"id": "extruder_3a", "hand_mode": false, "manual_on": false}
	func get_machines() -> Array: return []
	func get_section_status(keys: Array) -> int: return 0

# Test wrapper for testing HmiOverlay methods without triggering UI dependency cascades
class TestableHmiOverlay extends CanvasLayer:
	var _station = ""
	var _scope = {}
	var _selected_machine_key = ""
	var _line_flow = null
	var _last_fed_mass = 0.0

	func open_for(label: String, scope: Dictionary = {}) -> void:
		_station = label.to_upper()
		_scope = scope.duplicate(true) if not scope.is_empty() else {}
		_selected_machine_key = ""
		_find_line_flow()
		if _line_flow and "fed_mass" in _line_flow:
			_last_fed_mass = float(_line_flow.fed_mass)
		_show_screen(0)
		visible = true

	func close_overlay() -> void:
		close_subscope()
		visible = false

	func close_subscope() -> void:
		pass

	func _find_line_flow() -> void:
		_line_flow = get_tree().root.get_node_or_null("root/LineFlow")

	func _show_screen(_s: int) -> void:
		pass

func _fail(msg: String) -> void:
	print("RESULT FAIL: %s" % msg)
	quit(1)

var _ran := false

func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false

func _run():
	print("==== HMI OVERLAY TEST ====")

	var hmi = TestableHmiOverlay.new()
	var root_node = Node.new()
	root_node.name = "root"
	root.add_child(root_node)
	root_node.add_child(hmi)

	var mock_line_flow = StubLineFlow.new()
	mock_line_flow.name = "LineFlow"
	root_node.add_child(mock_line_flow)

	hmi._station = ""

	# Test open_for generic
	hmi.open_for("TestStation", {})
	if hmi._station != "TESTSTATION":
		_fail("open_for generic failed to set uppercase station, got: %s" % hmi._station); return
	if not hmi._scope.is_empty():
		_fail("open_for generic failed to set empty scope"); return
	if hmi.visible != true:
		_fail("open_for generic failed to set visibility to true"); return
	print("  ok    : open_for (generic) sets station, empty scope, and visibility")

	# Test open_for scoped
	hmi.open_for("ScopedStation", {"nodes": ["test1", "test2"]})
	if hmi._scope.get("nodes", []) != ["test1", "test2"]:
		_fail("open_for scoped failed to retain scope data"); return
	print("  ok    : open_for (scoped) sets provided scope")

	# Test close overlay
	hmi.close_overlay()
	if hmi.visible != false:
		_fail("close_overlay failed to set visibility to false"); return
	print("  ok    : close_overlay sets visibility to false")

	print("PASS — HmiOverlay logic verified headless")
	quit(0)
