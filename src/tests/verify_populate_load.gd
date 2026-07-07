extends Node3D
## Minimal: boot new_building_test and let BuildMode print its per-save loaded
## count. Success = the log line "[BuildMode] Loaded 56 placed objects (per-save)".
##
##   godot --headless --main-scene res://src/tests/verify_populate_load.tscn
const TEST_SLOT := "new_building_test"

func _ready() -> void:
	print("=== VERIFY POPULATE LOAD (watch for BuildMode Loaded line) ===")
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(60):
		await get_tree().process_frame
	print("=== boot settled, quitting ===")
	get_tree().quit(0)
