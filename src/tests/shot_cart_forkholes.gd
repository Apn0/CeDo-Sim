extends Node3D
# #225.2 / #201 — Visual proof: the lump cart underframe now has TWO genuine
# OPEN fork channels (rectangular holes) a forklift tine slides through, NOT a
# solid slab with painted-on recesses. Low view onto the -Z short end where the
# channels open. Renders one PNG and quits. Run WINDOWED (needs a GPU context).
const OUT_PNG := "user://shot_cart_forkholes.png"

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.67)
	env.ambient_light_energy = 1.15
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(-28.0), 0.0)
	sun.light_energy = 1.3
	add_child(sun)
	var fill := DirectionalLight3D.new()   # gentle fill so the channel bores aren't pitch black
	fill.rotation = Vector3(deg_to_rad(-8.0), deg_to_rad(150.0), 0.0)
	fill.light_energy = 0.5
	add_child(fill)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(8.0, 8.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)
	# the cart — FREEZE it (the ground plane has no collision, so an unfrozen
	# RigidBody would fall straight through before the frame renders).
	var cart := PlaceableCatalog.build_node("lump_cart", false)
	add_child(cart); (cart as Node3D).global_position = Vector3.ZERO
	if cart is RigidBody3D:
		(cart as RigidBody3D).freeze = true
	# camera low + in front of the -Z end, looking slightly up at the underframe
	# so the two open fork channels read as real tunnels through the frame.
	var cam := Camera3D.new(); add_child(cam)
	(cam as Camera3D).global_position = Vector3(0.42, 0.30, -1.75)
	(cam as Camera3D).look_at(Vector3(0.0, 0.15, -0.5), Vector3.UP)
	cam.make_current()
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_PNG)
	preload("res://src/tests/shot_common.gd").check_image_content(img, OUT_PNG)
	print("[SHOT] saved ", ProjectSettings.globalize_path(OUT_PNG))
	get_tree().quit(0)
