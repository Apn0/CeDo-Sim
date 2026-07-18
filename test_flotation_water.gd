extends SceneTree
## Proof the flotation-tank water is REAL (operator 2026-07-16 "THIS IS NOT WATER
## → FAUX"). Builds the actual flotation_tank placeable, asserts a WaterBox +
## Area3D volume exists, then drops one RigidBody INSIDE the water and an
## identical one in open AIR and shows the water body is held up by buoyancy
## (falls far less) — i.e. the Waterbox plugin is actually simulating water.
## Run: Godot_v4.6.3_console --headless --path <proj> --script res://test_flotation_water.gd

var _ran := false
var _f := 0
var _water_body : RigidBody3D
var _air_body : RigidBody3D
var _y0 := 3.0

func _physics_process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_setup()
		return false
	_f += 1
	if _f < 60:
		return false
	var fell_water := _y0 - _water_body.global_position.y
	var fell_air := _y0 - _air_body.global_position.y
	var fails := 0
	print("  body in AIR   fell %.2f m" % fell_air)
	print("  body in WATER fell %.2f m" % fell_water)
	if fell_air > 1.0:
		print("  OK  : air body free-falls (%.2f m) — baseline" % fell_air)
	else:
		print("  FAIL: air baseline didn't fall"); fails += 1
	if fell_water < fell_air * 0.5:
		print("  OK  : water body is HELD by buoyancy (%.2f m vs %.2f m free-fall) — real water" % [fell_water, fell_air])
	else:
		print("  FAIL: water body fell like it's in air (%.2f m) — still faux" % fell_water); fails += 1
	print("=== FLOTATION WATER TEST: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true

func _setup() -> void:
	var root := get_root()
	var tank : Node3D = PlaceableCatalog.build_node("flotation_tank", false, false)
	root.add_child(tank)
	tank.global_position = Vector3.ZERO
	# Integration assert: a WaterBox with an Area3D+shape must exist.
	var wbox := tank.find_children("*", "WaterBox", true, false)
	if wbox.is_empty():
		print("  FAIL: no WaterBox in the flotation tank (faux water)")
		print("=== FLOTATION WATER TEST: FAIL ==="); quit(1); return
	print("  OK  : WaterBox present in flotation_tank (real water volume)")
	_water_body = _drop(Vector3(0.0, _y0, 0.0))     # inside the tank water volume
	_air_body = _drop(Vector3(40.0, _y0, 0.0))      # far away, open air

func _drop(pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = 2.0
	var col := CollisionShape3D.new()
	var s := SphereShape3D.new(); s.radius = 0.25
	col.shape = s
	b.add_child(col)
	get_root().add_child(b)
	b.global_position = pos
	return b
