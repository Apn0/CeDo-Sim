extends Node3D
## Close-up renders of the four photo details added to the maalmolen on
## 2026-09-06. `shot_placeable.tscn` auto-frames the WHOLE machine, which leaves
## a 0.05 m clamp pad about 4 px across — no use for judging fidelity.
##
##   <godot> --path . res://src/tests/shot_mill_3c_details_2026_09_06.tscn --quit-after 150
##
## Writes docs/plant/renders/shot_mill_3c_{clamps,cowl,underdeck}_2026_09_06.png.
## Run WINDOWED (headless has no framebuffer to grab).

const OUT_DIR := "res://docs/plant/renders/"

## Each station is (camera position, look-at target) in world metres. Sight lines
## were picked against the model's own obstacles, not by eye:
##   clamps  — the bank is at y 4.04, far above the caged ladder (tops out at
##             y 1.92), so the +X approach is clear.
##   cowl    — the -Z railing stands between camera and motor. Top rail y 2.95,
##             mid rail y 2.425; this line crosses the rail plane at y 2.554,
##             in the gap between them.
##   deck    — passes the deck edge at x 0.53, clear of the leg at x 1.44.
const SHOTS := [
	{"name": "shot_mill_3c_clamps_2026_09_06.png",
	 "from": Vector3(2.73, 4.60, 1.10), "at": Vector3(1.13, 4.05, -0.10)},
	# The grille FACES -X. A station on the -Z side alone looks at the motor's
	# flank and the cowl end is hidden behind the fin rings, so this one sits
	# off the -X corner. It crosses the -Z rail plane at y 2.53, between the
	# mid rail (2.405-2.445) and the top rail (2.93-2.97).
	# and it must also miss the +BP2 cabinet, which stands at x -0.38..0.22,
	# z -1.20..-0.90. This line reaches the cabinet's -Z face at x 0.275, just
	# outside it, and crosses the -Z railing at y 2.28 — between the toe board
	# (1.98) and the mid rail (2.405).
	{"name": "shot_mill_3c_cowl_2026_09_06.png",
	 "from": Vector3(-0.60, 2.30, -1.85), "at": Vector3(0.3535, 2.25, -1.142)},
	{"name": "shot_mill_3c_underdeck_2026_09_06.png",
	 "from": Vector3(0.90, 1.35, 2.40), "at": Vector3(0.00, 1.60, 0.35)},
]

func _ready() -> void:
	_environment()
	var item: Dictionary = PlaceableCatalog.get_item("mill")
	var sz: Vector3 = item.get("size", Vector3.ONE)
	var root := Node3D.new()
	add_child(root)
	PlaceableCatalog._build_model(root, "mill", String(item.get("category", "")), sz,
		item.get("color", Color.WHITE), false)

	var cam := Camera3D.new()
	cam.fov = 40.0
	cam.near = 0.02
	cam.far = 200.0
	add_child(cam)
	cam.current = true

	for shot in SHOTS:
		cam.global_position = shot["from"] as Vector3
		cam.look_at(shot["at"] as Vector3, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		var img := get_viewport().get_texture().get_image()
		var outp: String = OUT_DIR + String(shot["name"])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		img.save_png(outp)
		preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
		print("[MILLSHOT] saved ", ProjectSettings.globalize_path(outp))
	get_tree().quit(0)

func _environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.58, 0.63, 0.69)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.67)
	env.ambient_light_energy = 1.15
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-46.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 1.30
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation = Vector3(deg_to_rad(-18.0), deg_to_rad(140.0), 0.0)
	fill.light_energy = 0.55
	add_child(fill)
