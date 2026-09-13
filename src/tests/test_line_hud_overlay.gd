extends SceneTree

## Unit test verifying LineFlow bottom-right overlay positioning, F6 toggle,
## active line name detection, ScadaDashboard dynamic set_title, and F2 toggle.

const LineFlowScript = preload("res://src/sim/LineFlow.gd")
const ScadaDashboardScript = preload("res://src/scenes/hud/ScadaDashboard.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== Running test_line_hud_overlay ===")
	var root_node := Node.new()
	root_node.name = "TestRoot"
	self.root.add_child(root_node)

	# 1. Verify InputMap actions
	print("Test 1: InputMap actions")
	assert(InputMap.has_action("toggle_line_flow_hud"), "InputMap must have toggle_line_flow_hud action")
	assert(InputMap.has_action("toggle_scada_dashboard"), "InputMap must have toggle_scada_dashboard action")

	var f6_found := false
	for ev in InputMap.action_get_events("toggle_line_flow_hud"):
		if ev is InputEventKey and ((ev as InputEventKey).keycode == KEY_F6 or (ev as InputEventKey).physical_keycode == KEY_F6):
			f6_found = true
	assert(f6_found, "toggle_line_flow_hud must map to KEY_F6")

	var f2_found := false
	for ev in InputMap.action_get_events("toggle_scada_dashboard"):
		if ev is InputEventKey and ((ev as InputEventKey).keycode == KEY_F2 or (ev as InputEventKey).physical_keycode == KEY_F2):
			f2_found = true
	assert(f2_found, "toggle_scada_dashboard must map to KEY_F2")
	print("  [1] OK: InputMap actions toggle_line_flow_hud (F6) and toggle_scada_dashboard (F2) configured")

	# 2. LineFlow UI placement & toggle
	print("Test 2: LineFlow overlay placement & toggle")
	var lf = LineFlowScript.new()
	lf.set_process(false)
	root_node.add_child(lf)

	assert(lf._label != null, "_label must be created in LineFlow")
	assert(lf._label.anchor_left == 1.0, "anchor_left should be 1.0")
	assert(lf._label.anchor_right == 1.0, "anchor_right should be 1.0")
	assert(lf._label.anchor_top == 1.0, "anchor_top should be 1.0 (bottom anchored)")
	assert(lf._label.anchor_bottom == 1.0, "anchor_bottom should be 1.0 (bottom anchored)")
	assert(lf._label.offset_top == -140.0, "offset_top should be -140.0")
	assert(lf._label.offset_bottom == -12.0, "offset_bottom should be -12.0")

	var initial_vis : bool = lf._label.visible
	lf.toggle_hud_overlay()
	assert(lf._label.visible == (not initial_vis), "toggle_hud_overlay should invert _label visibility")
	lf.toggle_hud_overlay()
	assert(lf._label.visible == initial_vis, "second toggle should restore _label visibility")
	print("  [2] OK: LineFlow overlay anchored to bottom right and toggles cleanly")

	# 3. Active Line Detection
	print("Test 3: Active line detection")
	assert(lf.active_line_name() == "", "Empty line should return empty string")

	# Mock Line 1 nodes
	var m1 := Node3D.new()
	m1.name = "opzetband_1"
	m1.set_meta("macro_id", "line_1")
	root_node.add_child(m1)

	var m2 := Node3D.new()
	m2.name = "extruder_1"
	m2.set_meta("macro_id", "line_1")
	root_node.add_child(m2)

	lf._nodes = [
		{"id": "opzetband_1", "node": m1},
		{"id": "extruder_1", "node": m2}
	]
	assert(lf.active_line_name() == "LIJN 1", "Line 1 nodes should report 'LIJN 1', got: %s" % lf.active_line_name())
	print("  [3] OK: LineFlow correctly detects 'LIJN 1' for Line 1 nodes")

	# Mock Line 3C nodes
	var m3 := Node3D.new()
	m3.name = "extruder_3c"
	m3.set_meta("macro_id", "line_3c")
	root_node.add_child(m3)

	lf._nodes = [
		{"id": "extruder_3c", "node": m3}
	]
	assert(lf.active_line_name() == "LIJN 3C", "Line 3C nodes should report 'LIJN 3C', got: %s" % lf.active_line_name())
	print("  [4] OK: LineFlow correctly detects 'LIJN 3C' for Line 3C nodes")
	lf._nodes.clear()

	# 4. ScadaDashboard dynamic title & toggle
	print("Test 4: ScadaDashboard dynamic title & toggle")
	var scada = ScadaDashboardScript.new()
	scada.set_process(false)
	root_node.add_child(scada)

	assert(scada._title_label != null, "_title_label should be created")
	assert(scada.get_title() == "LINE 3C", "Default title should be LINE 3C")

	scada.set_title("LIJN 1")
	assert(scada.get_title() == "LIJN 1", "get_title should return LIJN 1")
	assert(scada._title_label.text == "LIJN 1", "_title_label.text should be updated to LIJN 1")

	var scada_vis : bool = scada._root_panel.visible
	scada.toggle_visibility()
	assert(scada._root_panel.visible == (not scada_vis), "toggle_visibility should invert _root_panel visibility")
	scada.toggle_visibility()
	assert(scada._root_panel.visible == scada_vis, "second toggle should restore _root_panel visibility")
	print("  [5] OK: ScadaDashboard set_title and toggle_visibility work properly")

	print("\nResult: 5 ok, 0 fail")
	print("RESULT: PASS")
	quit(0)
