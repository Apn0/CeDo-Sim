extends SceneTree

# Minimal headless test runner.
# The scene root script handles actual test logic.

func _init() -> void:
	var scene = load("res://src/tests/test_scada_dashboard.tscn").instantiate()
	root.add_child(scene)
