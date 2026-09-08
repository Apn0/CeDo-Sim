extends SceneTree

var _ok := 0
var _fail := 0
const CR = preload("res://src/scenes/player/CameraRig.gd")

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	var rig = CR.new()
	root.add_child(rig)

	var cam = Camera3D.new()
	var t = Transform3D()
	t.origin = Vector3(1, 2, 3)
	cam.transform = t
	cam.current = false

	rig.set_first_person_camera(cam)
	_check(rig._first_person_camera == cam, "Stores the camera reference")
	_check(rig._cab_initial_xf == t, "Snapshots initial transform")
	_check(cam.current == false, "Inactive rig makes the camera not current")

	rig.activate()
	var cam2 = Camera3D.new()
	var t2 = Transform3D()
	t2.origin = Vector3(4, 5, 6)
	cam2.transform = t2
	rig.set_first_person_camera(cam2)
	_check(rig._first_person_camera == cam2, "Stores the new camera reference")
	_check(cam2.current == true, "Active rig makes the new camera current")

	root.remove_child(rig)
	rig.free()
	cam.free()
	cam2.free()

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_ok, _fail])
	print("=========================================")
	quit(1 if _fail > 0 else 0)
	return

func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  ok   : %s" % msg)
	else:
		_fail += 1
		print("  FAIL : %s" % msg)
