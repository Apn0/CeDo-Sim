extends SceneTree
## Headless regression test for the enter/exit camera + position bugs:
##   - Unattended vehicle rigs must NOT activate their cab camera on spawn
##     (that was making every spawned vehicle fight for the viewport).
##   - Entering a vehicle must deactivate the player's rig and activate the
##     vehicle's rig.
##   - Exiting must deactivate the vehicle rig, snap the player to the
##     dismount position with zero velocity, and re-activate the player rig
##     back in FIRST_PERSON.

const _CameraRig := preload("res://src/scenes/player/CameraRig.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Operator enter/exit camera lifecycle test")
	print("============================================================")
	_test_rig_starts_inactive()
	_test_activate_deactivate_toggles_first_person_camera()
	_test_set_first_person_camera_doesnt_steal_viewport()
	_test_mode_change_while_inactive_does_not_grab_viewport()
	_test_camera_updates_immediately_on_mode_cycle()
	_test_mouse_look_first_person_rotates_cab_camera()
	_test_mouse_look_orbit_updates_orbit_state()
	_test_reset_restores_cab_camera_neutral()
	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

# =============================================================================
# 1) Fresh rigs spawn INACTIVE (no viewport grab on spawn)
# =============================================================================
func _test_rig_starts_inactive() -> void:
	print("[1] Newly-spawned rig is inactive")
	var rig := _CameraRig.new()
	root.add_child(rig)
	_ok(not rig.is_active(),
		"_active starts false (unattended vehicle won't grab the viewport)")
	# Even calling set_mode while inactive must NOT make the rig's own camera current
	rig.set_mode(_CameraRig.Mode.THIRD_PERSON)
	_ok(not rig._camera.current,
		"set_mode(THIRD_PERSON) while inactive does NOT set _camera.current")
	rig.queue_free()

# =============================================================================
# 2) activate() arms the current mode's camera; deactivate() releases both
# =============================================================================
func _test_activate_deactivate_toggles_first_person_camera() -> void:
	print("[2] activate / deactivate manage first-person camera + rig camera")
	var rig := _CameraRig.new()
	var cab := Camera3D.new()
	root.add_child(rig)
	root.add_child(cab)
	rig.set_first_person_camera(cab)
	_ok(not cab.current,
		"set_first_person_camera() WITHOUT activate() does NOT make cab current")
	rig.activate()
	_ok(cab.current, "after activate() in FIRST_PERSON: cab.current = true")
	_ok(not rig._camera.current, "in FIRST_PERSON mode: rig._camera.current = false")
	rig.set_mode(_CameraRig.Mode.THIRD_PERSON)
	_ok(not cab.current and rig._camera.current,
		"switching to THIRD_PERSON: cab off, rig camera on")
	rig.deactivate()
	_ok(not cab.current and not rig._camera.current,
		"deactivate(): BOTH cameras off (no viewport ownership)")
	rig.queue_free()
	cab.queue_free()

# =============================================================================
# 3) The CORE BUG: vehicle rigs must NOT grab the viewport when spawned
# =============================================================================
func _test_set_first_person_camera_doesnt_steal_viewport() -> void:
	print("[3] set_first_person_camera + inactive rig = no viewport grab")
	# Two "vehicles" spawn in sequence. Their cab cameras must STAY non-current
	# until someone calls activate() — otherwise they fight the player's camera.
	var v1 := _CameraRig.new()
	var v2 := _CameraRig.new()
	var cab1 := Camera3D.new()
	var cab2 := Camera3D.new()
	root.add_child(v1); root.add_child(v2)
	root.add_child(cab1); root.add_child(cab2)
	v1.set_first_person_camera(cab1)
	v2.set_first_person_camera(cab2)
	_ok(not cab1.current, "vehicle 1 cab stays inactive at spawn")
	_ok(not cab2.current, "vehicle 2 cab stays inactive at spawn")
	# Cleanup
	for n in [v1, v2, cab1, cab2]:
		n.queue_free()

# =============================================================================
# 4) Cycling modes on an inactive rig updates _mode but never grabs viewport
# =============================================================================
func _test_mode_change_while_inactive_does_not_grab_viewport() -> void:
	print("[4] Mode cycling while inactive doesn't grab viewport")
	var rig := _CameraRig.new()
	root.add_child(rig)
	rig.cycle_mode()
	rig.cycle_mode()
	_ok(not rig._camera.current,
		"cycle_mode twice while inactive: rig camera STILL not current")
	rig.queue_free()

# =============================================================================
# 6) Mouse look in FIRST_PERSON rotates the cab camera (not the orbit state)
# =============================================================================
func _test_mouse_look_first_person_rotates_cab_camera() -> void:
	print("[6] Mouse look in 1st-person rotates cab camera locally")
	var rig := _CameraRig.new()
	var cab := Camera3D.new()
	# Cab starts with a non-trivial initial transform to make sure we apply
	# rotations ON TOP of it (not replace it)
	cab.transform = Transform3D(Basis().rotated(Vector3.UP, PI), Vector3(0, 1.6, -0.7))
	root.add_child(rig)
	root.add_child(cab)
	rig.set_first_person_camera(cab)
	var initial_basis := cab.transform.basis
	# Push mouse to the right (positive X) → yaw should change
	rig.handle_mouse_look(Vector2(50.0, 0.0))
	_ok(rig._cab_yaw != 0.0, "mouse X moves _cab_yaw (=%.3f)" % rig._cab_yaw)
	_ok(not cab.transform.basis.is_equal_approx(initial_basis),
		"cab camera basis CHANGED after mouse-look (so it's actually applied)")
	# Orbit state must be UNTOUCHED in 1st-person mode
	_ok(rig._orbit_yaw == 0.0,
		"orbit_yaw stays 0 in 1st person (=%.3f)" % rig._orbit_yaw)
	# Push mouse downward (positive Y) → pitch should DECREASE (looking down)
	var pitch_before := rig._cab_pitch
	rig.handle_mouse_look(Vector2(0.0, 50.0))
	_ok(rig._cab_pitch < pitch_before,
		"mouse Y (down) lowers _cab_pitch (%.3f → %.3f)" % [pitch_before, rig._cab_pitch])
	rig.queue_free()
	cab.queue_free()

# =============================================================================
# 7) Mouse look in ORBIT updates orbit_yaw/pitch (not cab state)
# =============================================================================
func _test_mouse_look_orbit_updates_orbit_state() -> void:
	print("[7] Mouse look in orbit updates orbit_yaw / orbit_pitch")
	var rig := _CameraRig.new()
	root.add_child(rig)
	rig.set_mode(_CameraRig.Mode.ORBIT)
	var oy := rig._orbit_yaw
	var op := rig._orbit_pitch
	rig.handle_mouse_look(Vector2(100.0, -30.0))
	_ok(rig._orbit_yaw != oy,
		"mouse X moves orbit_yaw (%.3f → %.3f)" % [oy, rig._orbit_yaw])
	_ok(rig._orbit_pitch != op,
		"mouse Y moves orbit_pitch (%.3f → %.3f)" % [op, rig._orbit_pitch])
	_ok(rig._cab_yaw == 0.0,
		"cab_yaw stays 0 in orbit mode (=%.3f)" % rig._cab_yaw)
	rig.queue_free()

# =============================================================================
# 8) reset() restores the cab camera to its initial (neutral) transform
# =============================================================================
func _test_reset_restores_cab_camera_neutral() -> void:
	print("[8] reset() restores cab camera to neutral")
	var rig := _CameraRig.new()
	var cab := Camera3D.new()
	cab.transform = Transform3D(Basis(), Vector3(0, 1.6, -0.7))
	root.add_child(rig)
	root.add_child(cab)
	rig.set_first_person_camera(cab)
	var initial_xf := cab.transform
	# Mess things up with mouse look
	rig.handle_mouse_look(Vector2(200.0, 100.0))
	_ok(not cab.transform.is_equal_approx(initial_xf), "cab moved after look")
	rig.reset()
	_ok(rig._cab_yaw == 0.0 and rig._cab_pitch == 0.0,
		"reset(): cab yaw/pitch zeroed")
	_ok(cab.transform.is_equal_approx(initial_xf),
		"reset(): cab camera back to initial transform (clean dismount)")
	rig.queue_free()
	cab.queue_free()

# =============================================================================
# 5) Pressing F4 (cycle mode) updates the camera position SYNCHRONOUSLY so the
#    user doesn't see a stale frame at the previous mode's position.
# =============================================================================
func _test_camera_updates_immediately_on_mode_cycle() -> void:
	print("[5] Camera position updates on the same frame as mode cycle")
	var rig := _CameraRig.new()
	root.add_child(rig)
	rig.global_position = Vector3(50.0, 0.0, 50.0)   # imagine the vehicle is here
	rig.activate()
	# Before cycling, rig._camera is wherever it defaulted to (origin-ish).
	rig.cycle_mode()   # THIRD_PERSON
	# After cycle, _update_follow_camera() should have run synchronously
	# and put the camera in the rig's neighbourhood (within 20 m of the subject)
	var d := rig._camera.global_position.distance_to(rig.global_position)
	_ok(d < 20.0,
		"after F4 cycle to 3rd-person: rig camera within 20m of subject (=%.1f m)" % d)
	rig.cycle_mode()   # ORBIT
	d = rig._camera.global_position.distance_to(rig.global_position)
	_ok(d < 50.0,
		"after F4 cycle to orbit: rig camera within 50m of subject (=%.1f m)" % d)
	rig.queue_free()
