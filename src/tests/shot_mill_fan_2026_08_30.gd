extends Node3D
## Close-up renders of the maalmolen's mobile industrial FAN (the object that was
## wrongly built as a rust flywheel until the operator corrected it on
## 2026-08-30). `shot_placeable.tscn` auto-frames the WHOLE machine, which leaves
## the fan about 70 px across — no use for judging whether it reads as a fan.
##
##   <godot> --path . res://src/tests/shot_mill_fan_2026_08_30.tscn --quit-after 120
##
## Writes docs/plant/renders/shot_mill_fan_angle{1,2}_2026_08_30.png.
## Run WINDOWED (headless has no framebuffer to grab).

const OUT_DIR := "res://docs/plant/renders/"

## Camera stations, chosen to answer two different questions:
##   angle1 — does the guarded outlet face read as a FAN?
##   angle2 — are the trolley, the two wheels and the tilt knob actually there?
## Both stations sit OUTSIDE the -X railing. Anything on the +X or overhead side
## is blocked by the infeed hopper, which is 2.24 m across at the mouth and
## reaches y 4.22 — the first attempt put the camera above the deck and rendered
## the inside of the hopper.
const SHOTS := [
	{"name": "shot_mill_fan_angle1_2026_08_30.png", "from": Vector3(-2.35, 0.55, -2.05)},
	{"name": "shot_mill_fan_angle2_2026_08_30.png", "from": Vector3(-2.05, 0.35, 1.95)},
	# Tight on the guarded outlet: the operator could not make the wire shroud
	# out at all from the two wider stations above.
	{"name": "shot_mill_fan_shroud_2026_08_30.png", "from": Vector3(-0.62, 0.16, 1.02)},
]

func _ready() -> void:
	_environment()
	var item: Dictionary = PlaceableCatalog.get_item("mill")
	var sz: Vector3 = item.get("size", Vector3.ONE)
	var root := Node3D.new()
	add_child(root)
	PlaceableCatalog._build_model(root, "mill", String(item.get("category", "")), sz,
		item.get("color", Color.WHITE), false)

	# The fan's own frame, re-derived from the builder's constants so this scene
	# keeps aiming at the fan if the fan ever moves.
	var deck_top: float = sz.y * 0.40 + 0.01
	var target := Vector3(-1.115, deck_top + 0.55, -0.55)

	var cam := Camera3D.new()
	cam.fov = 42.0
	cam.near = 0.02
	cam.far = 200.0
	add_child(cam)
	cam.current = true

	for shot in SHOTS:
		cam.global_position = target + (shot["from"] as Vector3)
		cam.look_at(target, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.35).timeout
		var img := get_viewport().get_texture().get_image()
		var outp: String = OUT_DIR + String(shot["name"])
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
		img.save_png(outp)
		preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
		print("[FANSHOT] saved ", ProjectSettings.globalize_path(outp))
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
