extends Node
# =============================================================================
# PROBE — does the physical W key drive gear-first on EVERY operator_forward_sign
# = -1 machine, or only the bale clamp?
#
# The InputMap is global, so a swapped vehicle_forward/vehicle_reverse binding in
# user://settings.cfg hits the whole fleet, not just the clamp. This measures it
# per vehicle in one real MainWorld boot.
#
#   GODOT --headless --path . res://src/tests/probe_fleet_wkey.tscn
# =============================================================================

const FRAMES := 120

func _ready() -> void:
	print("=== PROBE — physical W key, whole fleet ===")
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(120):
		await get_tree().process_frame

	var oc = get_tree().get_nodes_in_group("operator_context")[0]
	for swapped in [true, false]:
		_bind("vehicle_forward", KEY_S if swapped else KEY_W)
		_bind("vehicle_reverse", KEY_W if swapped else KEY_S)
		print("\n### InputMap = %s" % ("SWAPPED (user://settings.cfg as it is on disk)" if swapped else "FIXED (W=vehicle_forward, project.godot default)"))
		await _pass(oc)
	print("\nDone.")
	get_tree().quit(0)

func _bind(action: String, key: Key) -> void:
	InputMap.action_erase_events(action)
	var e := InputEventKey.new()
	e.keycode = key
	e.physical_keycode = key
	InputMap.action_add_event(action, e)

func _pass(oc) -> void:
	var seen : Dictionary = {}
	print("%-16s | %-6s | %-38s | %s" % ["vehicle_type", "ofs", "W key travels", "cab cam looks"])
	print("-".repeat(16) + "-+-" + "-".repeat(6) + "-+-" + "-".repeat(38) + "-+-" + "-".repeat(16))
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not (n is Node3D):
			continue
		var vt := String(n.get("vehicle_type"))
		if vt == "" or seen.has(vt):
			continue
		seen[vt] = true
		var v := n as Node3D
		var ofs := float(v.get("operator_forward_sign"))
		if float(v.get("fuel_l")) <= 0.0:
			v.set("fuel_l", 60.0)
		v.set("drive_charge", 100.0)
		v.call("on_operator_entered", oc)
		await get_tree().process_frame
		var res := await _cell(v)
		var cam_dir := "n/a"
		var cam := v.get_node_or_null(String(v.get("cab_camera_path"))) as Camera3D
		if cam:
			var lz : float = (-cam.transform.basis.z).z
			cam_dir = "+Z (gear)" if lz > 0.5 else ("-Z" if lz < -0.5 else "sideways")
		print("%-16s | %+5.0f | %-38s | %s" % [vt, ofs, res, cam_dir])
		v.call("on_operator_exited") if v.has_method("on_operator_exited") else v.set("_operator", null)
		v.set("occupied", false)
		await get_tree().process_frame

func _cell(v: Node3D) -> String:
	v.set("_current_speed_mps", 0.0)
	v.set("_throttle", 0.0); v.set("_throttle_raw", 0.0)
	var sm = v.get("_throttle_smoother")
	if sm != null: sm.set("value", 0.0)
	var p0 : Vector3 = v.global_position
	var b0 : Basis = v.global_transform.basis
	_key(KEY_W, true)
	for i in range(FRAMES):
		await get_tree().physics_frame
	_key(KEY_W, false)
	var dz : float = (v.global_position - p0).dot(b0.z)
	for i in range(60):
		await get_tree().physics_frame
	if absf(dz) < 0.05:
		return "did not move (%.3f m)" % dz
	return ("%+.2f m toward +Z (gear/cam side)" % dz) if dz > 0.0 \
		else ("%+.2f m toward -Z (counterweight side)" % dz)

func _key(k: Key, down: bool) -> void:
	var e := InputEventKey.new()
	e.keycode = k
	e.physical_keycode = k
	e.pressed = down
	Input.parse_input_event(e)
