extends SceneTree
## Parse-and-load-only check for the settings-menu changes.
## Just preloads the scripts and inspects the constants we changed.

const _SM := preload("res://src/autoload/SettingsManager.gd")

# Note on SettingsMenu.gd: it references the autoload `SettingsManager`, which
# only exists at runtime when the full project boots. So in script-mode we don't
# preload it — its parse + behaviour are covered by actually opening the menu
# in-game (or by the scene-mode VehicleBaleTest harness, when Godot 4.6 is used).

var _pass : int = 0
var _fail : int = 0

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Settings menu parse + coverage test")
	print("============================================================")

	# SettingsManager parsed (we're here, so the preload succeeded)
	_ok(true, "SettingsManager.gd parses")

	# 2. Coverage: every action defined in project.godot inputs (minus ui_*) has
	#    a friendly label in ACTION_LABELS — otherwise the rebind/overview rows
	#    would fall back to the raw action_name.
	var labels: Dictionary = _SM.ACTION_LABELS
	var groups: Array      = _SM.ACTION_GROUPS

	var expected_actions := [
		"move_forward", "move_backward", "move_left", "move_right", "jump",
		"interact", "ui_cancel", "camera_toggle",
		"vehicle_forward", "vehicle_reverse",
		"vehicle_steer_left", "vehicle_steer_right",
		"vehicle_brake", "vehicle_handbrake",
		"forklift_lift_up", "forklift_lift_down",
		"forklift_tilt_back", "forklift_tilt_fwd",
		"forklift_rotator_left", "forklift_rotator_right",
		"forklift_forks_widen", "forklift_forks_pinch",
		"build_mode_toggle", "build_place", "build_cancel",
		"build_rotate_ccw", "build_rotate_cw",
		"build_raise", "build_lower",
		"build_grid_toggle", "build_delete",
	]
	for a in expected_actions:
		_ok(labels.has(a), "ACTION_LABELS covers '%s'" % a)

	# 3. Every action listed in ACTION_GROUPS must also have a label, otherwise
	#    the rebind row will say "build_xxxxx" instead of a friendly description.
	for g in groups:
		var ga: Array = g["actions"]
		for a in ga:
			_ok(labels.has(a), "Action '%s' (group '%s') has a label" % [a, g["label"]])

	# 4. Coverage check: every expected action appears in some group, so it's
	#    visible in the Controls tab. If not, the user can't rebind it.
	var in_some_group := {}
	for g in groups:
		for a in g["actions"]:
			in_some_group[a] = true
	for a in expected_actions:
		_ok(in_some_group.has(a), "Action '%s' belongs to a group" % a)

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	print("============================================================")
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		print("  FAIL  %s" % label)
