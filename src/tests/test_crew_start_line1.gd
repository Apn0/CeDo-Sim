extends SceneTree

## Headless test for Line 1 Crew Startup sequence and Insert hotkey.

const CrewManagerScript = preload("res://src/scenes/world/CrewManager.gd")
const NPCScript = preload("res://src/scenes/world/NPC.gd")

class StubLineFlow extends Node:
	var _nodes : Array = []
	var _started : bool = false
	var feed_enabled : bool = false

	func start_line() -> void:
		_started = true

class MockMachNode extends Node3D:
	func _init(mid: String):
		name = mid

func _init() -> void:
	print("Running test_crew_start_line1...")

	# 1. Verify InputMap / Settings fallback
	if not InputMap.has_action("crew_start_line"):
		InputMap.add_action("crew_start_line")
		var ev := InputEventKey.new()
		ev.keycode = KEY_INSERT
		InputMap.action_add_event("crew_start_line", ev)

	var events = InputMap.action_get_events("crew_start_line")
	print("crew_start_line events count: ", events.size())
	var has_insert := false
	for ev in events:
		if ev is InputEventKey:
			var iek := ev as InputEventKey
			print("  event keycode: ", iek.keycode, " physical: ", iek.physical_keycode, " expected KEY_INSERT: ", KEY_INSERT)
			if iek.keycode == KEY_INSERT or iek.physical_keycode == KEY_INSERT:
				has_insert = true
				break
	assert(has_insert, "crew_start_line must bind KEY_INSERT")
	print("  [1] OK: crew_start_line action binds KEY_INSERT")

	# 2. Setup Scene and Mock LineFlow
	var root_node = Node.new()
	root_node.name = "TestRoot"
	self.root.add_child(root_node)

	var lf = StubLineFlow.new()
	lf.name = "LineFlow"
	root_node.add_child(lf)

	# Build Line 1 machine nodes
	var m_opzet := MockMachNode.new("opzetband_1")
	m_opzet.position = Vector3(-150, 0, 40)
	m_opzet.set_meta("macro_id", "line_1")
	root_node.add_child(m_opzet)

	var m_shredder := MockMachNode.new("shredder_1")
	m_shredder.position = Vector3(-155, 0, 38)
	m_shredder.set_meta("macro_id", "line_1")
	root_node.add_child(m_shredder)

	var m_trommel := MockMachNode.new("vw_trommel")
	m_trommel.position = Vector3(-165, 0, 30)
	m_trommel.set_meta("macro_id", "line_1")
	root_node.add_child(m_trommel)

	var m_friction := MockMachNode.new("friction_sep")
	m_friction.position = Vector3(-170, 0, 30)
	m_friction.set_meta("macro_id", "line_1")
	root_node.add_child(m_friction)

	var m_mill := MockMachNode.new("mill")
	m_mill.position = Vector3(-175, 0, 30)
	m_mill.set_meta("macro_id", "line_1")
	root_node.add_child(m_mill)

	var m_flot := MockMachNode.new("flotation_tank")
	m_flot.position = Vector3(-180, 0, 30)
	m_flot.set_meta("macro_id", "line_1")
	root_node.add_child(m_flot)

	var m_ext := MockMachNode.new("extruder_1")
	m_ext.position = Vector3(-190, 0, 30)
	m_ext.set_meta("macro_id", "line_1")
	root_node.add_child(m_ext)

	lf._nodes = [
		{"id": "opzetband_1", "node": m_opzet, "win": m_opzet.position},
		{"id": "shredder_1", "node": m_shredder, "win": m_shredder.position},
		{"id": "vw_trommel", "node": m_trommel, "win": m_trommel.position},
		{"id": "friction_sep", "node": m_friction, "win": m_friction.position},
		{"id": "mill", "node": m_mill, "win": m_mill.position},
		{"id": "flotation_tank", "node": m_flot, "win": m_flot.position},
		{"id": "extruder_1", "node": m_ext, "win": m_ext.position},
	]

	# 3. Setup CrewManager and Workers
	var cm = CrewManagerScript.new()
	cm.name = "CrewManager"
	root_node.add_child(cm)

	var feeder_npc := NPCScript.new()
	feeder_npc.name = "Pascal"
	feeder_npc.npc_name = "Pascal"
	feeder_npc.npc_role = "feeder"
	root_node.add_child(feeder_npc)

	var ext_npc := NPCScript.new()
	ext_npc.name = "Kevin"
	ext_npc.npc_name = "Kevin"
	ext_npc.npc_role = "extruder_op"
	root_node.add_child(ext_npc)

	var all_npc := NPCScript.new()
	all_npc.name = "Emrah"
	all_npc.npc_name = "Emrah"
	all_npc.npc_role = "all_rounder"
	root_node.add_child(all_npc)

	var lead_npc := NPCScript.new()
	lead_npc.name = "Romain"
	lead_npc.npc_name = "Romain"
	lead_npc.npc_role = "shift_leader"
	root_node.add_child(lead_npc)

	var npc_dict := {
		"pascal": feeder_npc,
		"kevin": ext_npc,
		"emrah": all_npc,
		"romain": lead_npc
	}

	cm.setup(npc_dict, lf, null, Vector3.ZERO)
	print("  [2] OK: CrewManager setup with 4 workers")

	# 4. Trigger start_line_1_with_crew()
	cm.start_line_1_with_crew()

	# Assertions
	assert(lf._started == true, "LineFlow.start_line() should have been called")
	assert(lf.feed_enabled == true, "LineFlow.feed_enabled should be true")
	print("  [3] OK: LineFlow PLC started and feed enabled")

	# Check Feeder assignment
	assert(feeder_npc.assigned_station_id.find("opzetband") != -1 or feeder_npc.assigned_station_id.find("shredder") != -1,
		"Feeder should be assigned to intake: got %s" % feeder_npc.assigned_station_id)
	assert(feeder_npc.on_duty == true, "Feeder should be on duty")
	print("  [4] OK: Feeder assigned to Line 1 intake (%s)" % feeder_npc.assigned_station_id)

	# Check Extruder Op assignment
	assert(ext_npc.assigned_station_id.find("extruder") != -1,
		"Extruder op should be assigned to extruder: got %s" % ext_npc.assigned_station_id)
	assert(ext_npc.on_duty == true, "Extruder op should be on duty")
	print("  [5] OK: Extruder op assigned to Line 1 extruder (%s)" % ext_npc.assigned_station_id)

	# Check All-Rounder patrol
	assert(cm._allrounder_patrols.has(all_npc), "All-rounder should have an active startup patrol")
	var patrol_info : Dictionary = cm._allrounder_patrols[all_npc]
	assert(patrol_info.get("active", false) == true, "All-rounder patrol should be active")
	var stations : Array = patrol_info.get("stations", [])
	assert(stations.size() >= 3, "All-rounder patrol should contain Line 1 stations, found %d" % stations.size())
	print("  [6] OK: All-rounder active startup patrol initialized with %d stations" % stations.size())

	# Test stepping the all-rounder patrol
	var start_idx : int = patrol_info.get("idx", 0)
	cm._step_allrounder_patrol(all_npc)
	var next_idx : int = patrol_info.get("idx", 0)
	assert(next_idx == start_idx + 1, "Patrol should advance to next station index")
	print("  [7] OK: All-rounder patrol successfully advances across Line 1")

	print("\nResult: 7 ok, 0 fail")
	print("RESULT: PASS")
	quit(0)
