extends Node

const PlayerScript = preload("res://src/scenes/player/PlayerController.gd")

var _pass := 0
var _fail := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

class MockPlayer extends PlayerScript:
	func _ready() -> void: pass
	func _physics_process(delta: float) -> void: pass

func _ready() -> void:
	print("=== PlayerController Ladder Tests ===")
	var player = MockPlayer.new()
	add_child(player)

	_ok(player._on_ladder_count == 0, "Initial ladder count is 0")

	player.enter_ladder()
	_ok(player._on_ladder_count == 1, "enter_ladder increments count to 1")

	player.enter_ladder()
	_ok(player._on_ladder_count == 2, "enter_ladder increments count to 2")

	player.exit_ladder()
	_ok(player._on_ladder_count == 1, "exit_ladder decrements count to 1")

	player.exit_ladder()
	_ok(player._on_ladder_count == 0, "exit_ladder decrements count to 0")

	player.exit_ladder()
	_ok(player._on_ladder_count == 0, "exit_ladder clamps count to 0, does not go negative")

	print("\nTest Summary: %d passed, %d failed" % [_pass, _fail])
	if _fail > 0:
		get_tree().quit(1)
		return
	get_tree().quit(0)
	return
