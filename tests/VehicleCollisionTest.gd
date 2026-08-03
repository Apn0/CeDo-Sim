extends Node3D
## Proves the kinematic vehicles now COLLIDE with static world geometry instead of
## teleporting through it (the "I can drive through the test bunker" bug).
##
## Before the fix, _kinematic_move did `global_position += fwd * v*dt` — a raw
## teleport with no sweep, so the chassis passed through everything. Now it uses
## move_and_collide, so a forklift driven straight at a static wall must STOP at
## the wall instead of ending up behind it.
##
## Run headless:
##   "<godot>" --headless --path . res://tests/VehicleCollisionTest.tscn --quit-after 240
##
## Exit code: 0 = all pass, 1 = a failure.

const FORKLIFT_SCENE := "res://src/scenes/vehicles/Forklift.tscn"

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array[String] = []

var _fork : Node3D = null
var _wall_z : float = -6.0   # canonical CeDo vehicle forward is local -Z (BaseVehicle._kinematic_move)
var _frames : int = 0
var _done : bool = false

func _ready() -> void:
	print("============================================================")
	print("  CeDo Simulator — Vehicle vs world collision test")
	print("============================================================")

	# A static wall 6 m ahead (-Z, the direction the forklift actually drives),
	# spanning the drive path.
	var wall := StaticBody3D.new()
	wall.name = "Wall"
	add_child(wall)
	wall.global_position = Vector3(0, 0, _wall_z)
	var wcol := CollisionShape3D.new()
	var wbox := BoxShape3D.new()
	wbox.size = Vector3(8.0, 4.0, 0.5)
	wcol.shape = wbox
	wall.add_child(wcol)
	# A floor so the gravity-settle has something to rest on.
	var floor_body := StaticBody3D.new()
	add_child(floor_body)
	floor_body.global_position = Vector3(0, -0.25, 0)
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(60, 0.5, 60)
	fcol.shape = fbox
	floor_body.add_child(fcol)

	# Forklift at origin. Canonical forward = local -Z, so it drives toward the wall at -Z.
	var scene := load(FORKLIFT_SCENE) as PackedScene
	_fork = scene.instantiate() as Node3D
	add_child(_fork)
	_fork.global_position = Vector3(0, 0.5, 0)
	# Pretend an operator is aboard and flooring it forward, brake released.
	_fork.set("occupied", true)
	_fork.set("handbrake_engaged", false)
	_fork.set("_throttle", 1.0)
	_fork.set("_current_speed_mps", 3.0)

func _physics_process(_delta: float) -> void:
	if _done or _fork == null:
		return
	# The vehicle's own _physics_process calls _gather_input() every frame, which
	# reads real Input actions (all zero in headless) and would zero our throttle.
	# So we drive it by forcing the runtime forward speed directly each frame —
	# that's the value _kinematic_move actually integrates (and now sweeps with
	# move_and_collide). The wall must arrest it regardless.
	_fork.set("occupied", false)              # stop _gather_input from fighting us
	_fork.set("_current_speed_mps", 3.0)
	_frames += 1
	# Give it ~2.5 s of sim to cover the 8 m and pile into the wall.
	if _frames < 150:
		return
	_done = true
	_evaluate()

func _evaluate() -> void:
	var z: float = (_fork as Node3D).global_position.z
	# Driving toward -Z: the wall face nearest the spawn is at _wall_z + 0.25.
	# The forklift must be stopped on the NEAR side of the wall, not past it.
	var wall_front := _wall_z + 0.25
	_ok(z > wall_front - 0.1,
		"forklift stopped at/near the wall front (z=%.2f, wall front=%.2f)" % [z, wall_front])
	_ok(z > _wall_z - 1.0,
		"forklift did NOT pass through the wall (z=%.2f, wall=%.2f)" % [z, _wall_z])
	# And it actually moved toward the wall (didn't just sit at spawn).
	_ok(z < -1.0, "forklift drove forward before being stopped (z=%.2f)" % z)

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")
	get_tree().quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)
