extends Node3D
## P3 stage A (2026-09-23) — render the extruder's vacuum pots in three states
## for the operator's eye. Run WINDOWED:
##   Godot --path . res://src/tests/shot_vacuum_pots.tscn
## Writes docs/plant/renders/shot_vacuum_pots_<state>.png.

const OUT_DIR := "res://docs/plant/renders/"
const CASES : Array = [
	{"label": "empty",                 "p": 0.0,  "s": 0.0,  "gunk": 0.0},
	{"label": "primary_half",          "p": 0.5,  "s": 0.2,  "gunk": 0.0},
	{"label": "primary_full_lid_gunk", "p": 1.0,  "s": 0.6,  "gunk": 0.7},
]

func _ready() -> void:
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
	var body : Node3D = PlaceableCatalog.build_node("extruder_3a", false)
	add_child(body)
	body.global_position = Vector3.ZERO
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	await get_tree().process_frame
	var brain : Node = null
	for m in get_tree().get_nodes_in_group("extruder_machine"):
		if m.get_parent() == body:
			brain = m
	var model = brain.get("model") if brain != null else null
	var lid := body.find_child("VacPot_primary", true, false).get_node("Lid") as Node3D
	var focus : Vector3 = lid.global_position
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for c in CASES:
		if model != null:
			model.primary_pot_fill_kg = float(c["p"]) * ExtruderModel.VACUUM_POT_CAPACITY_KG
			model.secondary_pot_fill_kg = float(c["s"]) * ExtruderModel.VACUUM_POT_CAPACITY_KG
			model.vacuum_line_gunk_kg = float(c["gunk"]) * ExtruderModel.VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG
		var yr := deg_to_rad(62.0)
		var pr := deg_to_rad(22.0)
		var dist := 2.6
		cam.global_position = focus + Vector3(sin(yr) * cos(pr) * dist, sin(pr) * dist, cos(yr) * cos(pr) * dist)
		cam.look_at(focus, Vector3.UP)
		await get_tree().process_frame
		await get_tree().process_frame
		await get_tree().create_timer(0.8).timeout
		var img := get_viewport().get_texture().get_image()
		var outp : String = OUT_DIR + "shot_vacuum_pots_%s.png" % String(c["label"])
		img.save_png(outp)
		preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
		print("[SHOT] saved ", ProjectSettings.globalize_path(outp))
	get_tree().quit(0)
