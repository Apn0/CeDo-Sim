extends Node
## Guard against the F10 key-collision bug: pressing F10 must ONLY capture
## feedback, never also cycle the camera. The operator's saved settings had
## `camera_toggle` bound to F10 in addition to `feedback_capture`, so one press
## did both (screenshot + flip to third-person). SettingsManager._reserve_feedback_key
## strips F10 from every non-feedback action after keybinds apply.
##
##   godot --headless --main-scene res://src/tests/test_f10_reserved.tscn

func _ready() -> void:
	print("=== F10 reserved-for-feedback guard ===")
	var fails := 0

	# Simulate the exact corruption: bind F10 to camera_toggle, then re-apply.
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		print("FAIL: SettingsManager autoload missing (boot via --main-scene)")
		get_tree().quit(1); return

	if InputMap.has_action("camera_toggle"):
		var bad1 := InputEventKey.new()
		bad1.keycode = KEY_F10
		var bad2 := InputEventKey.new()
		bad2.physical_keycode = KEY_F10
		InputMap.action_add_event("camera_toggle", bad1)
		InputMap.action_add_event("camera_toggle", bad2)

		# Also inject directly into SettingsManager's working model, because _apply_keybinds
		# overwrites the InputMap with _current_keybinds, which would wipe our test data
		# before _reserve_feedback_key even gets a chance to see it.
		var cur_binds = sm.get("_current_keybinds")
		if typeof(cur_binds) == TYPE_DICTIONARY and cur_binds.has("camera_toggle"):
			cur_binds["camera_toggle"].append(bad1)
			cur_binds["camera_toggle"].append(bad2)

		if sm.has_method("_apply_keybinds"):
			sm.call("_apply_keybinds")   # runs _reserve_feedback_key()
		elif sm.has_method("_reserve_feedback_key"):
			sm.call("_reserve_feedback_key")

	# After the reserve pass, NO non-feedback action may hold F10.
	for action in InputMap.get_actions():
		if String(action) == "feedback_capture":
			continue
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey:
				var evk := ev as InputEventKey
				if evk.keycode == KEY_F10 or evk.physical_keycode == KEY_F10:
					print("  FAIL  : action '%s' still bound to F10" % action)
					fails += 1

	if fails == 0:
		print("  ok    : no non-feedback action is bound to F10 (camera_toggle clean)")
	print("Result: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
