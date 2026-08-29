extends SceneTree

func _initialize() -> void:
	var PushGate = load("res://src/build/PushGate.gd")
	var gate = PushGate.new()
	var root = get_root()
	root.add_child(gate)

	# Delay execution to allow Node3D tree setup.
	call_deferred("_test_logic", gate, root)

func _test_logic(gate: Node3D, root: Window) -> void:
	var player = Node3D.new()
	player.name = "Player"
	root.add_child(player)

	gate.global_position = Vector3(10.0, 0.0, 10.0)
	# Rotate gate 90 degrees around Y just to make sure local space math works correctly
	gate.rotation_degrees = Vector3(0, 90, 0)

	print("[TEST] PushGate._player_is_on_free_side")

	# Test free_side_idx = 0 (+X)
	gate.free_side_idx = 0
	# Local +X should be True. Since rotation is +90 (yaw left), local +X is world -Z
	player.global_position = gate.global_transform * Vector3(1.0, 0.0, 0.0)
	assert(gate._player_is_on_free_side(player) == true, "free_side_idx 0 (+X) should be true on local +X")
	# Local -X should be False
	player.global_position = gate.global_transform * Vector3(-1.0, 0.0, 0.0)
	assert(gate._player_is_on_free_side(player) == false, "free_side_idx 0 (+X) should be false on local -X")
	print("  ok: free_side_idx 0 (+X)")

	# Test free_side_idx = 1 (-X)
	gate.free_side_idx = 1
	player.global_position = gate.global_transform * Vector3(-1.0, 0.0, 0.0)
	assert(gate._player_is_on_free_side(player) == true, "free_side_idx 1 (-X) should be true on local -X")
	player.global_position = gate.global_transform * Vector3(1.0, 0.0, 0.0)
	assert(gate._player_is_on_free_side(player) == false, "free_side_idx 1 (-X) should be false on local +X")
	print("  ok: free_side_idx 1 (-X)")

	# Test free_side_idx = 2 (+Z)
	gate.free_side_idx = 2
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, 1.0)
	assert(gate._player_is_on_free_side(player) == true, "free_side_idx 2 (+Z) should be true on local +Z")
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, -1.0)
	assert(gate._player_is_on_free_side(player) == false, "free_side_idx 2 (+Z) should be false on local -Z")
	print("  ok: free_side_idx 2 (+Z)")

	# Test free_side_idx = 3 (-Z)
	gate.free_side_idx = 3
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, -1.0)
	assert(gate._player_is_on_free_side(player) == true, "free_side_idx 3 (-Z) should be true on local -Z")
	player.global_position = gate.global_transform * Vector3(0.0, 0.0, 1.0)
	assert(gate._player_is_on_free_side(player) == false, "free_side_idx 3 (-Z) should be false on local +Z")
	print("  ok: free_side_idx 3 (-Z)")

	print("[TEST] PASS")
	quit(0)
