extends Node3D
# Photo-audit helper: render the CURRENT in-game model of ANY placeable id to
# user://shot_<id>.png, auto-framed from its catalog size. Run WINDOWED:
#   Godot --path . res://src/tests/shot_placeable.tscn -- <placeable_id> [yaw_deg] [pitch_deg]
# e.g.  ... -- shredder_1 35 18
func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var pid : String = String(args[0]) if args.size() >= 1 else "laser_filter"
	var yaw : float = float(args[1]) if args.size() >= 2 else 35.0
	var pitch : float = float(args[2]) if args.size() >= 3 else 20.0
	# Optional 4th arg = a line-code suffix so each render gets a unique filename
	# (operator rule 2026-07-15), e.g. "_3A" -> user://shot_flotation_tank_3A.png
	var suffix : String = String(args[3]) if args.size() >= 4 else ""
	# ── environment + lighting ───────────────────────────────────────────────
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.65)
	env.ambient_light_energy = 1.1
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.25
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)
	# ── build the placeable ──────────────────────────────────────────────────
	var node : Node = PlaceableCatalog.build_node(pid, false)
	if node == null:
		print("[SHOT] ERROR: no placeable '", pid, "'")
		get_tree().quit(1); return
	add_child(node)
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	(node as Node3D).global_position = Vector3.ZERO
	# ── frame the camera from the catalog footprint ──────────────────────────
	var item : Dictionary = PlaceableCatalog.get_item(pid)
	var sz : Vector3 = item.get("size", Vector3.ONE)
	var reach : float = maxf(sz.x, maxf(sz.y, sz.z))
	var dist : float = reach * 1.9 + 1.5
	var yr : float = deg_to_rad(yaw)
	var pr : float = deg_to_rad(pitch)
	var cam := Camera3D.new(); add_child(cam)
	(cam as Camera3D).global_position = Vector3(
		sin(yr) * cos(pr) * dist,
		sz.y * 0.5 + sin(pr) * dist,
		cos(yr) * cos(pr) * dist)
	(cam as Camera3D).look_at(Vector3(0.0, sz.y * 0.45, 0.0), Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	var img := get_viewport().get_texture().get_image()
	# Operator rule 2026-07-20: renders ALWAYS land in the project folder,
	# never only in user:// or a temp dir — a render nobody can find is a
	# render that gets re-made from scratch next session.
	var out_dir := "res://docs/plant/renders/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var outp : String = out_dir + "shot_%s%s.png" % [pid, suffix]
	img.save_png(outp)
	preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[SHOT] saved ", ProjectSettings.globalize_path(outp), " (size ", sz, ")")
	get_tree().quit(0)
