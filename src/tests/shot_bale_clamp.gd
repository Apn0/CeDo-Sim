extends Node3D
# EXTERIOR AUDIT HELPER (2026-08-17) — renders the BaleClamp vehicle scene from
# several exterior angles AFTER the runtime has had its say (BaleClamp.gd's
# _physics_process overwrites the authored LiftCarriage / plate transforms on
# the first tick), and dumps the resulting world coordinates of every clamp part.
#
# Sibling of src/tests/shot_placeable.gd — that tool only handles PlaceableCatalog
# ids, and "bale_clamp" is a vehicle .tscn, not a placeable, so it cannot be
# driven through shot_placeable.
#
# Run WINDOWED (needs a real swapchain for get_texture()):
#   Godot_v4.6.3-stable_win64_console.exe --path . res://src/tests/shot_bale_clamp.tscn
#
# Writes res://docs/plant/renders/shot_baleclamp_<angle>.png — one unique
# filename per shot (project rule 9).

const VEH_PATH := "res://src/scenes/vehicles/BaleClamp.tscn"
const OUT_DIR  := "res://docs/plant/renders/"

var _veh : Node3D = null
var _cam : Camera3D = null

# name, yaw_deg (0 = looking from +Z toward -Z), pitch_deg, distance, look-at height
const SHOTS := [
	# yaw 0 = camera on +Z = the MAST / clamp side = the machine's working front.
	["front_threequarter",  35.0, 12.0, 8.5, 1.2],
	["side_left",          -90.0,  4.0, 8.5, 1.2],
	["front_direct",         0.0,  6.0, 7.5, 1.2],
	["mast_carriage_close", 30.0, 10.0, 4.2, 1.0],
	["mast_carriage_side", -90.0,  8.0, 4.2, 1.0],
	["rear_threequarter",  200.0, 14.0, 8.5, 1.2],
	["top_down",             0.0, 62.0, 9.0, 0.6],
]

func _ready() -> void:
	var env_root := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.67)
	env.ambient_light_energy = 1.15
	env_root.environment = env
	add_child(env_root)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-48.0), deg_to_rad(-140.0), 0.0)
	sun.light_energy = 1.30
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80.0, 80.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)

	# 1 m reference stakes at x = 0, z = +3 (in front of the machine) so the
	# renders carry a scale bar instead of a vibe.
	for i in 3:
		var stake := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.03; cm.bottom_radius = 0.03; cm.height = 1.0
		stake.mesh = cm
		var smat := StandardMaterial3D.new()
		smat.albedo_color = Color(0.95, 0.85, 0.10) if i % 2 == 0 else Color(0.15, 0.15, 0.15)
		stake.material_override = smat
		stake.position = Vector3(2.4, 0.5 + float(i), 3.2)
		add_child(stake)

	var ps := load(VEH_PATH) as PackedScene
	if ps == null:
		print("[CLAMPSHOT] ERROR: cannot load ", VEH_PATH)
		get_tree().quit(1); return
	_veh = ps.instantiate() as Node3D
	add_child(_veh)
	if _veh is RigidBody3D:
		(_veh as RigidBody3D).freeze = true
	_veh.global_position = Vector3.ZERO

	_cam = Camera3D.new()
	add_child(_cam)
	_cam.make_current()

	# Let _ready + several physics ticks run so BaleClamp._physics_process has
	# overwritten LiftCarriage.position.y and the plate X positions, and the
	# clamp_gap_m lerp has converged.
	for _i in 200:
		await get_tree().physics_frame
	await get_tree().process_frame

	_dump_pose()

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for s in SHOTS:
		await _shoot(String(s[0]), float(s[1]), float(s[2]), float(s[3]), float(s[4]))

	# ── Second pass: drive the carriage to FULL LIFT and re-measure/re-shoot, so
	#    the top end of the travel is documented too (lift_max_m = 2.57).
	_veh.set("lift_height_m", _veh.get("lift_max_m"))
	for _i in 30:
		await get_tree().physics_frame
	print("[CLAMPSHOT] ===== FULL-LIFT POSE (lift_height_m = ", _veh.get("lift_height_m"), ") =====")
	for p in ["MastPivot/LiftCarriage", "MastPivot/LiftCarriage/LeftPlate/LeftPlateMesh",
			"MastPivot/MastPostL"]:
		var n2 := _veh.get_node_or_null(NodePath(p)) as Node3D
		if n2 == null: continue
		var o2 := n2.global_transform.origin
		print("[CLAMPSHOT] %-46s world=(%.3f, %.3f, %.3f)  %s" % [p, o2.x, o2.y, o2.z, _aabb_world(n2)])
	await _shoot("full_lift_side", -90.0, 6.0, 9.5, 2.0)
	await _shoot("full_lift_threequarter", 35.0, 10.0, 9.5, 2.0)
	get_tree().quit(0)

func _shoot(nm: String, yaw: float, pitch: float, dist: float, look_y: float) -> void:
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	_cam.global_position = Vector3(
		sin(yr) * cos(pr) * dist,
		look_y + sin(pr) * dist,
		cos(yr) * cos(pr) * dist)
	_cam.look_at(Vector3(0.0, look_y, 0.35), Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.35).timeout
	var img := get_viewport().get_texture().get_image()
	var outp := OUT_DIR + "shot_baleclamp_%s.png" % nm
	img.save_png(outp)
	preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[CLAMPSHOT] saved ", ProjectSettings.globalize_path(outp))

func _aabb_world(n: Node) -> String:
	var mi := n as MeshInstance3D
	if mi == null or mi.mesh == null:
		return "(no mesh)"
	var ab := mi.mesh.get_aabb()
	var xf := mi.global_transform
	var lo := Vector3(INF, INF, INF)
	var hi := Vector3(-INF, -INF, -INF)
	for i in 8:
		var p : Vector3 = xf * ab.get_endpoint(i)
		lo = Vector3(minf(lo.x, p.x), minf(lo.y, p.y), minf(lo.z, p.z))
		hi = Vector3(maxf(hi.x, p.x), maxf(hi.y, p.y), maxf(hi.z, p.z))
	return "AABB x[%.3f..%.3f] y[%.3f..%.3f] z[%.3f..%.3f]" % [lo.x, hi.x, lo.y, hi.y, lo.z, hi.z]

func _dump_pose() -> void:
	print("[CLAMPSHOT] ===== RUNTIME REST POSE (vehicle at world origin) =====")
	var bc := _veh
	print("[CLAMPSHOT] lift_height_m = ", bc.get("lift_height_m"),
		"  tilt_deg = ", bc.get("tilt_deg"),
		"  clamp_gap_m = ", bc.get("clamp_gap_m"),
		"  clamp_force = ", bc.get("clamp_force"))
	var paths := [
		"MastPivot", "MastPivot/MastPostL", "MastPivot/MastPostR",
		"MastPivot/LiftCarriage", "MastPivot/LiftCarriage/CarryPoint",
		"MastPivot/LiftCarriage/LeftPlate", "MastPivot/LiftCarriage/LeftPlate/LeftPlateMesh",
		"MastPivot/LiftCarriage/LeftPlate/LeftPlateFrontBevel",
		"MastPivot/LiftCarriage/LeftPlate/LeftPlateTopSlant",
		"MastPivot/LiftCarriage/RightPlate", "MastPivot/LiftCarriage/RightPlate/RightPlateMesh",
		"BodyMesh", "Counterweight", "HoodPanel", "RoofPanel",
		"Wheel_FL", "Wheel_RL", "CabCamera", "SteeringWheel", "Dashboard", "SeatBase",
	]
	for p in paths:
		var n := _veh.get_node_or_null(NodePath(p)) as Node3D
		if n == null:
			print("[CLAMPSHOT] %-46s MISSING" % p)
			continue
		var o := n.global_transform.origin
		print("[CLAMPSHOT] %-46s world=(%.3f, %.3f, %.3f)  %s" % [p, o.x, o.y, o.z, _aabb_world(n)])
	print("[CLAMPSHOT] ----- root children at runtime -----")
	var names : Array[String] = []
	for c in _veh.get_children():
		names.append("%s(%s)" % [c.name, c.get_class()])
	print("[CLAMPSHOT] ", ", ".join(names))
	# Every light the runtime built
	print("[CLAMPSHOT] ----- lights -----")
	for c in _veh.get_children():
		if c is Light3D:
			var l := c as Light3D
			print("[CLAMPSHOT] %-22s type=%s pos=%s rot_deg=%s visible=%s color=%s" % [
				l.name, l.get_class(), str(l.position), str(l.rotation_degrees),
				str(l.visible), str(l.light_color)])
	# Where does each blue spot actually hit the floor?
	for nm in ["BlueSpot_0", "BlueSpot_180"]:
		var sl := _veh.get_node_or_null(NodePath(nm)) as SpotLight3D
		if sl == null:
			continue
		var dir : Vector3 = -sl.global_transform.basis.z
		var org : Vector3 = sl.global_transform.origin
		if absf(dir.y) > 0.001:
			var t : float = -org.y / dir.y
			var hit : Vector3 = org + dir * t
			print("[CLAMPSHOT] %s aim_dir=(%.3f,%.3f,%.3f) floor_hit=(%.3f, 0, %.3f)" % [
				nm, dir.x, dir.y, dir.z, hit.x, hit.z])
	print("[CLAMPSHOT] ===== END POSE =====")
