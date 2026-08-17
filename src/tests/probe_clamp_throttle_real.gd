extends Node
# =============================================================================
# PROBE (REAL WORLD) — BaleClamp W/S travel direction inside a real MainWorld
# boot, not a bare bench. Operator report 2026-08-17: "W drives BACKWARDS,
# S drives FORWARDS on the bale clamp".
#
# Finds the bale clamp the world itself spawned, seats the world's own
# OperatorContext, presses the REAL input actions, and measures the world-space
# displacement projected onto the vehicle's own axes.
#
#   +local_Z = MastPivot / clamp plates side (and the direction CabCamera faces)
#   -local_Z = Counterweight + LPG bottle side
#
#   GODOT --headless --path . res://src/tests/probe_clamp_throttle_real.tscn
# =============================================================================

const FRAMES := 150

func _ready() -> void:
	print("=== PROBE (REAL MainWorld) — BaleClamp throttle direction ===")
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(120):
		await get_tree().process_frame

	var clamp : Node3D = _find_clamp()
	if clamp == null:
		print("FATAL: no bale_clamp found in the booted world"); get_tree().quit(2); return
	print("[FOUND] %s  vehicle_id=%s  pos=(%.2f, %.2f, %.2f)  yaw=%.1f deg"
		% [clamp.name, str(clamp.get("vehicle_id")),
			clamp.global_position.x, clamp.global_position.y, clamp.global_position.z,
			rad_to_deg(clamp.global_rotation.y)])
	print("[SIGNS] operator_forward_sign=%+.1f  steer_sign=%+.1f  fuel_l=%.1f  npc_autopilot=%s"
		% [float(clamp.get("operator_forward_sign")), float(clamp.get("steer_sign")),
			float(clamp.get("fuel_l")), str(clamp.get("npc_autopilot"))])

	# Local-space landmarks straight off the live node.
	for n in ["MastPivot", "Counterweight", "CabCamera"]:
		var c := clamp.get_node_or_null(n) as Node3D
		if c:
			print("[PART] %-14s local=(%+.2f, %+.2f, %+.2f)" % [n, c.position.x, c.position.y, c.position.z])
	var cam := clamp.get_node_or_null("CabCamera") as Camera3D
	if cam:
		var look : Vector3 = -cam.transform.basis.z
		print("[CAM ] live look dir local = (%+.2f, %+.2f, %+.2f) -> %s"
			% [look.x, look.y, look.z, ("+Z / MAST" if look.z > 0.5 else "-Z / COUNTERWEIGHT")])

	if float(clamp.get("fuel_l")) <= 0.0:
		clamp.set("fuel_l", 40.0)
		print("[SETUP] tank was empty — filled to 40 L so the drive loop runs")

	var ocs := get_tree().get_nodes_in_group("operator_context")
	if ocs.is_empty():
		print("FATAL: no OperatorContext in the world"); get_tree().quit(2); return
	clamp.call("on_operator_entered", ocs[0])
	await get_tree().process_frame
	print("[SETUP] occupied=%s handbrake=%s" % [str(clamp.get("occupied")), str(clamp.get("handbrake_engaged"))])

	await _run(clamp, "vehicle_forward", "W")
	await _run(clamp, "vehicle_reverse", "S")

	print("\n=========================================")
	print("Done.")
	print("=========================================")
	get_tree().quit(0)

func _find_clamp() -> Node3D:
	for n in get_tree().get_nodes_in_group("vehicle"):
		if n is Node3D and String(n.get("vehicle_type")) == "bale_clamp":
			return n as Node3D
	return null

func _run(v: Node3D, action: String, label: String) -> void:
	v.set("_current_speed_mps", 0.0)
	v.set("_throttle", 0.0)
	v.set("_throttle_raw", 0.0)
	var sm = v.get("_throttle_smoother")
	if sm != null:
		sm.set("value", 0.0)
	var p0 : Vector3 = v.global_position
	var b0 : Basis = v.global_transform.basis
	Input.action_press(action, 1.0)
	for i in range(FRAMES):
		await get_tree().physics_frame
	Input.action_release(action)
	var d : Vector3 = v.global_position - p0
	var dz : float = d.dot(b0.z)
	print("[REAL %s] throttle_raw=%+.2f throttle=%+.2f speed=%+.3f m/s" %
		[label, float(v.get("_throttle_raw")), float(v.get("_throttle")), float(v.get("_current_speed_mps"))])
	print("[REAL %s] world delta=(%+.3f, %+.3f, %+.3f)  |xz|=%.3f m" % [label, d.x, d.y, d.z, Vector2(d.x, d.z).length()])
	print("[REAL %s]   along +local_Z (MAST / camera-facing) = %+.3f m" % [label, dz])
	print("[REAL %s]   => %s" % [label,
		("TOWARD THE MAST (what the seat faces)" if dz > 0.05
		else ("TOWARD THE COUNTERWEIGHT (behind the seat)" if dz < -0.05 else "DID NOT MOVE"))])
	for i in range(90):
		await get_tree().physics_frame
