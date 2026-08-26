extends SceneTree
## Headless test for CrewPanel (Crew assignment panel).
##
## CrewPanel has NO associated `.tscn` file; it dynamically builds its own UI
## via code in `_build()` when instantiated via `load("res://src/scenes/hud/CrewPanel.gd").new()`.
## This test ensures that the panel correctly initializes, builds its UI, and populates
## workers without crashing.
##
## Run (ALWAYS with --quit-after to dodge the autoload-hang issue):
##   godot --headless --path . --script res://src/tests/test_crew_panel.gd --quit-after 5

const CrewPanelScript = preload("res://src/scenes/hud/CrewPanel.gd")

## Stand-in for CrewManager
class MockCrewManager extends Node:
	var workers = []
	func role_posts() -> Array:
		return [{"id": "post1", "label": "Post 1"}]
	func pinned_station(_worker) -> String:
		return ""
	func position_pin_for(_worker) -> Dictionary:
		return {}

## Stand-in for Worker/NPC
class MockWorker extends Node:
	var npc_name = "Test Worker"
	var npc_role = "tester"
	func current_task() -> String:
		return "idle"

func _init():
	print("Running CrewPanel tests...")

	# We need a root node to act as the scene tree root to attach UI components,
	# otherwise they will encounter null references during dynamic UI builds.
	var root_node = Node.new()
	root_node.name = "root"
	self.root.add_child(root_node)

	# Test initialization and default state
	var panel = CrewPanelScript.new()
	root_node.add_child(panel)

	# Trigger ready manually if it hasn't processed
	if panel.layer != 60:
		panel._ready()

	assert(panel.layer == 60)
	assert(panel.visible == false)
	assert(panel.is_processing() == true)
	print("Test 1 OK: initialization")

	# Mock CrewManager
	var cm = MockCrewManager.new()
	root_node.add_child(cm)

	# Add a worker to test population
	var worker = MockWorker.new()
	cm.workers.append(worker)
	root_node.add_child(worker)

	# Test open_for builds UI and populates list without crashing
	panel.open_for(cm)
	assert(panel._built == true)
	assert(panel.visible == true)
	print("Test 2 OK: open_for builds and populates")

	# Test close
	panel.close_panel()
	assert(panel.visible == false)
	print("Test 3 OK: close_panel hides panel")

	# Test toggle_for toggles correctly
	panel.toggle_for(cm)
	assert(panel.visible == true)
	panel.toggle_for(cm)
	assert(panel.visible == false)
	print("Test 4 OK: toggle_for switches visibility")

	# Check if rows array populated correctly (i.e. the mock worker was successfully parsed)
	assert(panel._rows.size() == 1)
	assert(panel._rows[0].worker.npc_name == "Test Worker")
	print("Test 5 OK: Worker row populated correctly")

	print("All tests passed!")
	quit()
