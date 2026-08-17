extends Node
# =============================================================================
# PROBE — BaleClamp W/S + steering + reverse-alarm truth table.
#
# Two independent switches decide what the operator feels:
#   1. the runtime InputMap  (user://settings.cfg currently binds
#      vehicle_forward -> S and vehicle_reverse -> W: SWAPPED)
#   2. BaseVehicle.operator_forward_sign (BaleClamp.gd:147 sets -1.0)
#
# This runs all four combinations in one real MainWorld boot and reports, per
# cell, what the PHYSICAL W key does:
#   travel   : + = toward the mast/clamp (the way the cab camera looks)
#   steering : yaw sign while A is held (+ = turns LEFT, Godot rotate_y CCW)
#   alarm    : does the reverse beam / beeper fire while W is held
#
# NOTHING IS WRITTEN TO DISK — the InputMap is patched in memory only.
#
#   GODOT --headless --path . res://src/tests/probe_clamp_signs_matrix.tscn
# =============================================================================

const FRAMES := 120

var _clamp : Node3D = null

func _ready() -> void:
	print("=== PROBE — BaleClamp sign truth table ===")
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(120):
		await get_tree().process_frame

	for n in get_tree().get_nodes_in_group("vehicle"):
		if n is Node3D and String(n.get("vehicle_type")) == "bale_clamp":
			_clamp = n as Node3D
			break
	if _clamp == null:
		print("FATAL: no bale clamp"); get_tree().quit(2); return
	if float(_clamp.get("fuel_l")) <= 0.0:
		_clamp.set("fuel_l", 60.0)
	_clamp.call("on_operator_entered", get_tree().get_nodes_in_group("operator_context")[0])
	await get_tree().process_frame

	print("\n%-34s | %-30s | %-24s | %s" % ["CONFIG", "W key travels", "A key yaws", "reverse alarm on W"])
	print("-".repeat(34) + "-+-" + "-".repeat(30) + "-+-" + "-".repeat(24) + "-+-" + "-".repeat(20))
	for swapped in [true, false]:
		_set_map(swapped)
		for ofs in [-1.0, 1.0]:
			_clamp.set("operator_forward_sign", ofs)
			var r := await _cell()
			print("%-34s | %-30s | %-24s | %s" % [
				"map=%s  ofs=%+.0f" % [("SWAPPED (on disk now)" if swapped else "FIXED (W=fwd)"), ofs],
				r["travel"], r["steer"], r["alarm"]])
	print("\nDone.")
	get_tree().quit(0)

func _set_map(swapped: bool) -> void:
	var fwd_key : Key = KEY_S if swapped else KEY_W
	var rev_key : Key = KEY_W if swapped else KEY_S
	_bind("vehicle_forward", fwd_key)
	_bind("vehicle_reverse", rev_key)

func _bind(action: String, key: Key) -> void:
	InputMap.action_erase_events(action)
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	InputMap.action_add_event(action, e)

func _cell() -> Dictionary:
	var v := _clamp
	v.set("_current_speed_mps", 0.0)
	v.set("_throttle", 0.0); v.set("_throttle_raw", 0.0)
	v.set("_steering", 0.0); v.set("_current_steer_rad", 0.0)
	var sm = v.get("_throttle_smoother")
	if sm != null: sm.set("value", 0.0)
	var p0 : Vector3 = v.global_position
	var b0 : Basis   = v.global_transform.basis
	var yaw0 : float = v.global_rotation.y

	_key(KEY_W, true)
	_key(KEY_A, true)
	var alarm := false
	for i in range(FRAMES):
		await get_tree().physics_frame
		var rev_light = v.get_node_or_null("ReverseBeam")
		if rev_light != null and (rev_light as Node3D).visible:
			alarm = true
	_key(KEY_W, false)
	_key(KEY_A, false)

	var dz : float = (v.global_position - p0).dot(b0.z)
	var dyaw : float = wrapf(v.global_rotation.y - yaw0, -PI, PI)
	# let it stop + straighten before the next cell
	for i in range(120):
		await get_tree().physics_frame

	return {
		"travel": ("%+.2f m -> MAST (fwd)" % dz) if dz > 0.05
			else (("%+.2f m -> C'WEIGHT (back)" % dz) if dz < -0.05 else "no movement"),
		"steer": ("%+.1f deg LEFT" % rad_to_deg(dyaw)) if dyaw > 0.01
			else (("%+.1f deg RIGHT" % rad_to_deg(dyaw)) if dyaw < -0.01 else "straight"),
		"alarm": "BEEPING" if alarm else "silent",
	}

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
