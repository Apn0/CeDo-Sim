extends Node
# =============================================================================
# PROBE — BaleClamp W/S travel direction (operator report 2026-08-17:
# "pressing W drives BACKWARDS, S drives FORWARDS").
#
# Boots BaleClamp.tscn on a bare floor, seats a real OperatorContext, presses
# the REAL input actions (Input.action_press), runs physics, and measures the
# world-space displacement projected onto the vehicle's own axes.
#
# Reference frame of the .tscn:
#   MastPivot / plates / clamp  -> +Z   (the working end)
#   Counterweight + LPG bottle  -> -Z
#   CabCamera basis = 180 deg yaw, so the seat LOOKS toward +Z (at the mast).
#
# Reported per key:
#   d_local_z  > 0  => moved toward the MAST (what the camera faces)
#   d_local_z  < 0  => moved toward the COUNTERWEIGHT (behind the seat)
#
#   GODOT --headless --path . res://src/tests/probe_clamp_throttle_dir.tscn
# =============================================================================

const FRAMES := 180   # 3 s at 60 Hz

func _ready() -> void:
	print("=== PROBE — BaleClamp throttle direction ===")
	var scn := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
	if scn == null:
		print("FATAL: BaleClamp.tscn failed to load"); get_tree().quit(2); return

	var world := Node3D.new()
	world.name = "ProbeWorld"
	add_child(world)

	# Floor so _settle_on_ground has something to rest on.
	var floor_body := StaticBody3D.new()
	var fcol := CollisionShape3D.new()
	var fbox := BoxShape3D.new()
	fbox.size = Vector3(400.0, 1.0, 400.0)
	fcol.shape = fbox
	floor_body.add_child(fcol)
	world.add_child(floor_body)
	floor_body.global_position = Vector3(0.0, -0.5, 0.0)

	var v : Node3D = scn.instantiate()
	world.add_child(v)
	v.global_position = Vector3(0.0, 0.5, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame

	# Fuel so _has_power() is true.
	v.set("fuel_l", 50.0)
	print("[SETUP] fuel_type=%s fuel_l=%.1f speed_limit_kmh=%.1f operator_forward_sign=%+.1f steer_sign=%+.1f"
		% [str(v.get("fuel_type")), float(v.get("fuel_l")), float(v.get("speed_limit_kmh")),
			float(v.get("operator_forward_sign")), float(v.get("steer_sign"))])

	# Seat a real operator so `_operator != null` and _gather_input runs.
	var oc := OperatorContext.new()
	oc.name = "ProbeOperator"
	add_child(oc)
	v.call("on_operator_entered", oc)
	await get_tree().process_frame
	print("[SETUP] occupied=%s handbrake=%s" % [str(v.get("occupied")), str(v.get("handbrake_engaged"))])

	# Where do the authored parts sit? (proves which local Z is the working end)
	_dump_part(v, "MastPivot")
	_dump_part(v, "Counterweight")
	_dump_part(v, "CabCamera")
	var cam := v.get_node_or_null("CabCamera") as Camera3D
	if cam:
		var look : Vector3 = -cam.transform.basis.z
		print("[CAM] CabCamera local look dir (-basis.z) = (%+.2f, %+.2f, %+.2f)  -> %s"
			% [look.x, look.y, look.z, ("+Z / MAST side" if look.z > 0.5 else ("-Z / COUNTERWEIGHT side" if look.z < -0.5 else "sideways"))])

	await _run_key(v, "vehicle_forward", "W")
	await _run_key(v, "vehicle_reverse", "S")

	print("\n=========================================")
	print("Done.")
	print("=========================================")
	get_tree().quit(0)

func _dump_part(v: Node3D, n: String) -> void:
	var c := v.get_node_or_null(n) as Node3D
	if c == null:
		print("[PART] %s : MISSING" % n)
		return
	print("[PART] %-14s local pos = (%+.2f, %+.2f, %+.2f)" % [n, c.position.x, c.position.y, c.position.z])

func _run_key(v: Node3D, action: String, label: String) -> void:
	# reset motion state
	v.set("_current_speed_mps", 0.0)
	v.set("_throttle", 0.0)
	v.set("_throttle_raw", 0.0)
	var sm = v.get("_throttle_smoother")
	if sm != null:
		sm.set("value", 0.0)
	var start_pos : Vector3 = v.global_position
	var start_basis : Basis = v.global_transform.basis

	Input.action_press(action, 1.0)
	for i in range(FRAMES):
		await get_tree().physics_frame
		if i == 29 or i == 89 or i == FRAMES - 1:
			print("   [%s] f=%3d throttle_raw=%+.2f throttle=%+.2f speed=%+.3f m/s pos=(%+.2f,%+.2f,%+.2f)"
				% [label, i + 1, float(v.get("_throttle_raw")), float(v.get("_throttle")),
					float(v.get("_current_speed_mps")),
					v.global_position.x, v.global_position.y, v.global_position.z])
	Input.action_release(action)

	var d : Vector3 = v.global_position - start_pos
	var d_local_z : float = d.dot(start_basis.z)      # +Z = mast side
	var d_local_x : float = d.dot(start_basis.x)
	var canonical_fwd : float = d.dot(-start_basis.z) # canonical -Z forward
	print("[RESULT %s] world delta = (%+.3f, %+.3f, %+.3f)  |xz|=%.3f m" % [label, d.x, d.y, d.z, Vector2(d.x, d.z).length()])
	print("[RESULT %s]   along +local_Z (MAST/clamp side)      = %+.3f m" % [label, d_local_z])
	print("[RESULT %s]   along -local_Z (canonical 'forward')  = %+.3f m" % [label, canonical_fwd])
	print("[RESULT %s]   along +local_X                        = %+.3f m" % [label, d_local_x])
	var verdict := "TOWARD THE MAST (camera-facing)" if d_local_z > 0.05 \
		else ("TOWARD THE COUNTERWEIGHT (behind the seat)" if d_local_z < -0.05 else "DID NOT MOVE")
	print("[RESULT %s]   => %s" % [label, verdict])

	# let it stop before the next run
	for i in range(60):
		await get_tree().physics_frame
