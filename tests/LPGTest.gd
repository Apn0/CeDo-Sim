extends Node3D

## Headless test for the LPG cylinder fixes (#167):
##   • a bale clamp spawns TWO mounted cylinders (not one)
##   • the player can only hold ONE cylinder at a time

const LPGTank = preload("res://src/scenes/world/LPGTank.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	_build_floor()
	await _test_clamp_two_tanks()
	await _test_one_held_max()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _build_floor() -> void:
	var f := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(40, 1, 40)
	cs.shape = bs; cs.position = Vector3(0, -0.5, 0)
	f.add_child(cs); add_child(f)

func _test_clamp_two_tanks() -> void:
	print("[1] bale clamp spawns TWO mounted LPG cylinders")
	var scn := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
	var clamp := scn.instantiate() as Node3D
	add_child(clamp)
	clamp.global_position = Vector3(0, 0.5, 0)
	# Let the deferred _spawn_initial_lpg_tanks run.
	for i in range(6):
		await get_tree().physics_frame
	var mounted : Array = clamp.get("_mounted_lpg_tanks")
	_ok(mounted.size() == 2, "clamp has 2 mounted cylinders (got %d)" % mounted.size())
	# Both should be the LPGTank model + MOUNTED.
	var both_mounted := true
	for t in mounted:
		if int(t.get("state")) != LPGTank.State.MOUNTED:
			both_mounted = false
	_ok(both_mounted, "both cylinders report MOUNTED state")
	clamp.queue_free()

func _test_one_held_max() -> void:
	print("[2] player can only carry ONE cylinder at a time")
	var player := CharacterBody3D.new()
	player.name = "Player"
	var head := Node3D.new(); head.name = "Head"
	player.add_child(head)
	add_child(player)
	player.global_position = Vector3(10, 1, 0)
	var t1 = LPGTank.new(); add_child(t1); t1.global_position = Vector3(10, 0.6, 1)
	var t2 = LPGTank.new(); add_child(t2); t2.global_position = Vector3(10, 0.6, 2)
	await get_tree().physics_frame
	t1._pick_up(player)
	_ok(int(t1.get("state")) == LPGTank.State.HELD, "first cylinder picked up")
	_ok(LPGTank.player_holds_tank(player), "player_holds_tank() true after pickup")
	t2._pick_up(player)
	_ok(int(t2.get("state")) != LPGTank.State.HELD, "second cylinder REFUSED (hands full)")
	# Drop the first, then the second should be takeable.
	t1._drop_to_floor()
	_ok(not LPGTank.player_holds_tank(player), "hands free after dropping")
	t2._pick_up(player)
	_ok(int(t2.get("state")) == LPGTank.State.HELD, "second cylinder takeable once hands free")
