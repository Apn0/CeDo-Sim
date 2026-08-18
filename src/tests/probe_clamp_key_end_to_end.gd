extends Node
# =============================================================================
# PROBE — END TO END: PHYSICAL KEY -> travel direction, real MainWorld boot.
#
# probe_clamp_throttle_real.gd pressed the ACTIONS and proved the throttle chain
# is correct (action vehicle_forward -> mast-first). This probe closes the last
# gap: it feeds a real InputEventKey (W / S) through Input.parse_input_event, so
# the runtime InputMap — including whatever SettingsManager loaded out of
# user://settings.cfg — is part of the measurement.
#
#   GODOT --headless --path . res://src/tests/probe_clamp_key_end_to_end.tscn
# =============================================================================

const FRAMES := 150

func _ready() -> void:
	print("=== PROBE — physical key -> BaleClamp travel direction ===")
	_dump_map()
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(120):
		await get_tree().process_frame

	print("--- InputMap AFTER autoloads + MainWorld boot ---")
	_dump_map()

	var clamp : Node3D = null
	for n in get_tree().get_nodes_in_group("vehicle"):
		if n is Node3D and String(n.get("vehicle_type")) == "bale_clamp":
			clamp = n as Node3D
			break
	if clamp == null:
		print("FATAL: no bale clamp"); get_tree().quit(2); return
	if float(clamp.get("fuel_l")) <= 0.0:
		clamp.set("fuel_l", 40.0)
	var ocs := get_tree().get_nodes_in_group("operator_context")
	clamp.call("on_operator_entered", ocs[0])
	await get_tree().process_frame

	await _run(clamp, KEY_W, "W")
	await _run(clamp, KEY_S, "S")
	print("\nDone.")
	get_tree().quit(0)

func _dump_map() -> void:
	for a in ["vehicle_forward", "vehicle_reverse", "vehicle_steer_left", "vehicle_steer_right"]:
		var parts : Array[String] = []
		for e in InputMap.action_get_events(a):
			if e is InputEventKey:
				var k := e as InputEventKey
				var kc : int = k.keycode if k.keycode != 0 else k.physical_keycode
				parts.append("%s(keycode=%d physical=%d)" % [OS.get_keycode_string(kc), k.keycode, k.physical_keycode])
		print("  InputMap %-20s <- %s" % [a, ", ".join(parts)])

func _run(v: Node3D, key: Key, label: String) -> void:
	v.set("_current_speed_mps", 0.0)
	v.set("_throttle", 0.0)
	v.set("_throttle_raw", 0.0)
	var sm = v.get("_throttle_smoother")
	if sm != null:
		sm.set("value", 0.0)
	var p0 : Vector3 = v.global_position
	var b0 : Basis = v.global_transform.basis

	var down := InputEventKey.new()
	down.keycode = key
	down.physical_keycode = key
	down.pressed = true
	Input.parse_input_event(down)
	await get_tree().physics_frame
	print("[KEY %s] fires action: vehicle_forward=%s vehicle_reverse=%s"
		% [label, str(Input.is_action_pressed("vehicle_forward")), str(Input.is_action_pressed("vehicle_reverse"))])

	for i in range(FRAMES):
		await get_tree().physics_frame
	var up := InputEventKey.new()
	up.keycode = key
	up.physical_keycode = key
	up.pressed = false
	Input.parse_input_event(up)

	var d : Vector3 = v.global_position - p0
	var dz : float = d.dot(b0.z)
	print("[KEY %s] throttle_raw=%+.2f speed=%+.3f m/s  delta_along_+localZ(MAST)=%+.3f m  => %s"
		% [label, float(v.get("_throttle_raw")), float(v.get("_current_speed_mps")), dz,
			("FORWARD - toward the mast/seat facing" if dz > 0.05
			else ("BACKWARD - toward the counterweight" if dz < -0.05 else "no movement"))])
	for i in range(90):
		await get_tree().physics_frame
