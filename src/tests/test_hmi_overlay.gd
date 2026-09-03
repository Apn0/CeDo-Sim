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

# To mock GDScript native methods or complex headless-incompatible UI setup, we
# extend the original class and override `_ready` and `_build_chrome` with `pass`.
class MockHmiOverlay extends "res://src/scenes/hud/HmiOverlay.gd":
	func _ready() -> void:
		pass
	func _build_chrome() -> void:
		pass
	func _show_screen(_s: int) -> void:
		pass

func _fail(msg: String) -> void:
	print("RESULT FAIL: %s" % msg)
	quit(1)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	print("==== HMI OVERLAY TEST ====")

	var hmi = MockHmiOverlay.new()
	var root_node = Node.new()
	root_node.name = "root"
	root.add_child(root_node)
	root_node.add_child(hmi)

	var mock_line_flow = StubLineFlow.new()
	mock_line_flow.name = "LineFlow"
	mock_line_flow.add_to_group("line_flow")
	root_node.add_child(mock_line_flow)

	# Setup required references manually since we skipped _ready
	hmi._line_flow = mock_line_flow

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

	print("Result: PASS")
	quit(0)
