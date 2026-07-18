extends Node3D
# #225.2 — Visual proof shot: the twin-nozzle laserfilter discharge station on
# its bordes (platform + ramp), with two fork-pocketed lump carts, one under
# each vertical nozzle. Renders ONE PNG and quits. Run WINDOWED (rendering needs
# a real GPU context — do NOT pass --headless):
#   Godot --path . res://src/tests/shot_discharge_station.tscn
const OUT_PNG := "user://shot_discharge_station.png"

func _ready() -> void:
	# ── lighting + environment (else the frame renders black) ────────────────
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.60, 0.63)
	env.ambient_light_energy = 1.1
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.25
	add_child(sun)
	# ── concrete ground ──────────────────────────────────────────────────────
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24.0, 24.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)
	# ── build the station from the catalog (same ids the bench uses) ─────────
	var plat := PlaceableCatalog.build_node("lump_platform", false)
	add_child(plat); (plat as Node3D).global_position = Vector3.ZERO
	var lf := PlaceableCatalog.build_node("laser_filter", false)
	add_child(lf);   (lf as Node3D).global_position = Vector3(0.0, 0.12, 0.0)
	var aisle := PlaceableCatalog.build_node("lump_cart", false)
	add_child(aisle); (aisle as Node3D).global_position = Vector3(1.30, 0.12, 0.0)
	var wall := PlaceableCatalog.build_node("lump_cart", false)
	add_child(wall);  (wall as Node3D).global_position = Vector3(-1.30, 0.12, 0.0)
	# bind both carts directly + grow a visible rope hanging from each nozzle
	lf.set("lump_cart", aisle)
	lf.set("lump_cart_wall", wall)
	for _i in 11:
		lf.call("_grow_sausage", 0.1, 200.0)
	# ── camera: 3/4 view framing filter + both nozzles + both carts ──────────
	var cam := Camera3D.new()
	add_child(cam)
	(cam as Camera3D).global_position = Vector3(5.4, 3.0, 5.0)
	(cam as Camera3D).look_at(Vector3(0.0, 0.75, 0.0), Vector3.UP)
	cam.make_current()
	# let a couple of frames render, then grab the framebuffer
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png(OUT_PNG)
	print("[SHOT] saved ", ProjectSettings.globalize_path(OUT_PNG))
	get_tree().quit(0)
