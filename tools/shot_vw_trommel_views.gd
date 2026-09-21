extends Node3D

const OUT_DIR := "res://docs/plant/renders/"

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.67, 0.70)
	env.ambient_light_energy = 1.2
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(-35.0), 0.0)
	sun.light_energy = 1.3
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-10.0), deg_to_rad(170.0), 0.0)
	fill.light_energy = 0.8
	add_child(fill)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)

	var node : Node = PlaceableCatalog.build_node("vw_trommel", false)
	add_child(node)
	(node as Node3D).global_position = Vector3.ZERO

	var cam := Camera3D.new()
	add_child(cam)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	# 1. Close-up into discharge opening (matching real photos 2 & 3)
	cam.global_position = Vector3(0.0, 2.15, 5.2)
	cam.look_at(Vector3(0.0, 2.15, 0.0), Vector3.UP)
	cam.make_current()
	await _snap("shot_vw_trommel_interior_closeup.png")

	# 2. View from inspection walkway looking at discharge (matching real photos 4 & 5)
	# Standing on the walkway at eye height (y ≈ 3.0), looking toward discharge mouth + hood
	cam.global_position = Vector3(-2.1, 2.9, 2.2)
	cam.look_at(Vector3(0.0, 1.8, 3.4), Vector3.UP)
	cam.make_current()
	await _snap("shot_vw_trommel_walkway_view.png")

	# 3. View from outside walkway looking at end railing + discharge structure
	cam.global_position = Vector3(-4.5, 3.2, 4.8)
	cam.look_at(Vector3(-1.0, 2.0, 3.0), Vector3.UP)
	cam.make_current()
	await _snap("shot_vw_trommel_walkway_railing.png")

	print("[SHOT] all views captured!")
	get_tree().quit(0)

func _snap(filename: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	var img := get_viewport().get_texture().get_image()
	var outp : String = OUT_DIR + filename
	img.save_png(outp)
	print("[SHOT] saved ", ProjectSettings.globalize_path(outp))
