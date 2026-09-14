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
	var _nodes : Array = [
		{"id": "extruder_3a", "key": "ext_3a", "line": "", "hand_mode": false, "manual_on": false},
		{"id": "shredder_1", "key": "shred_1", "line": "", "hand_mode": false, "manual_on": false}
	]
	func has_machine(_key: String) -> bool: return true
	func get_machine_info(key: String) -> Dictionary:
		for nd in _nodes:
			if nd.get("key") == key or nd.get("id") == key:
				return nd
		return {"id": "extruder_3a", "hand_mode": false, "manual_on": false}
	func get_machines() -> Array: return []
	func get_section_status(_keys: Array) -> int: return 0
	func set_machine_hand_mode(id: String, on: bool) -> void:
		for nd in _nodes:
			if nd.get("key") == id or nd.get("id") == id:
				nd["hand_mode"] = on
				if not on:
					nd["manual_on"] = false
	func set_machine_manual_on(id: String, on: bool) -> void:
		for nd in _nodes:
			if (nd.get("key") == id or nd.get("id") == id) and bool(nd.get("hand_mode", false)):
				nd["manual_on"] = on

# To mock GDScript native methods or complex headless-incompatible UI setup, we
# extend the original class and override `_ready` and `_build_chrome` with `pass`.
class MockHmiOverlay extends "res://src/scenes/hud/HmiOverlay.gd":
	func _ready() -> void:
		pass
	func _build_chrome() -> void:
		pass
	func _show_screen(_s: int) -> void:
		pass
	func _refresh() -> void:
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

	# --- Test HANDBEDIENING manual toggle & auto mode propagation ---
	# Initially AUTOMAAT is true
	if not hmi._automaat:
		_fail("default _automaat should be true"); return

	# In AUTOMAAT, _on_manual_toggle should be rejected
	hmi._on_manual_toggle("EXTRUDER")
	if hmi._manual_run.get("EXTRUDER", false) != false:
		_fail("_on_manual_toggle should be gated when _automaat is true"); return
	print("  ok    : _on_manual_toggle gated when _automaat is true")

	# Toggle auto -> switch to HAND mode
	hmi._on_toggle_auto()
	if hmi._automaat != false:
		_fail("toggle_auto failed to switch to HAND mode"); return
	if not mock_line_flow._nodes[0]["hand_mode"] or not mock_line_flow._nodes[1]["hand_mode"]:
		_fail("switching to HAND mode did not put in-scope nodes in hand_mode"); return
	if mock_line_flow._nodes[0]["manual_on"] or mock_line_flow._nodes[1]["manual_on"]:
		_fail("switching to HAND mode should initialize manual_on to false"); return
	print("  ok    : toggle_auto into HAND mode sets hand_mode=true and manual_on=false on nodes")

	# Now toggle EXTRUDER section ON in HAND mode
	hmi._on_manual_toggle("EXTRUDER")
	if not hmi._manual_run.get("EXTRUDER", false):
		_fail("manual_run['EXTRUDER'] should be true after toggle"); return
	if not mock_line_flow._nodes[0]["manual_on"]:
		_fail("extruder node manual_on should be true after section toggle ON"); return
	if mock_line_flow._nodes[1]["manual_on"]:
		_fail("shredder node manual_on should remain false when EXTRUDER is toggled"); return
	print("  ok    : _on_manual_toggle('EXTRUDER') turns on matching extruder node only")

	# Toggle EXTRUDER section OFF in HAND mode
	hmi._on_manual_toggle("EXTRUDER")
	if hmi._manual_run.get("EXTRUDER", false):
		_fail("manual_run['EXTRUDER'] should be false after second toggle"); return
	if mock_line_flow._nodes[0]["manual_on"]:
		_fail("extruder node manual_on should be false after section toggle OFF"); return
	print("  ok    : _on_manual_toggle('EXTRUDER') turns off matching extruder node")

	# Turn EXTRUDER ON again, then toggle back to AUTOMAAT
	hmi._on_manual_toggle("EXTRUDER")
	hmi._on_toggle_auto()
	if not hmi._automaat:
		_fail("toggle_auto failed to switch back to AUTOMAAT"); return
	if not hmi._manual_run.is_empty():
		_fail("returning to AUTOMAAT should clear _manual_run dict"); return
	if mock_line_flow._nodes[0]["hand_mode"] or mock_line_flow._nodes[1]["hand_mode"]:
		_fail("returning to AUTOMAAT should clear hand_mode on nodes"); return
	if mock_line_flow._nodes[0]["manual_on"] or mock_line_flow._nodes[1]["manual_on"]:
		_fail("returning to AUTOMAAT should clear manual_on on nodes"); return
	print("  ok    : toggle_auto into AUTOMAAT drops hand_mode, manual_on, and clears _manual_run")

	print("Result: PASS")
	print("RESULT: PASS")
	quit(0)
