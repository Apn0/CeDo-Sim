extends Node3D
## P5 (2026-09-23) — render the silo level windows and the compactor kijkglas
## with a level behind them, for the operator's eye. Run WINDOWED:
##   Godot --path . res://src/tests/shot_silo_level.tscn
## Writes docs/plant/renders/shot_silo_level_<case>.png (unique names).

const OUT_DIR := "res://docs/plant/renders/"

# id, label, fill fraction, yaw, pitch, distance multiplier, focus height frac
const CASES : Array = [
	{"id": "doseersilo",    "label": "doseersilo_47pct",    "frac": 0.47, "yaw": 75.0,  "pitch": 8.0,  "k": 0.75, "fy": 0.45},
	{"id": "mengsilo",      "label": "mengsilo_10pct",      "frac": 0.10, "yaw": 15.0,  "pitch": 6.0,  "k": 0.55, "fy": 0.32},
	{"id": "extruder_silo", "label": "extruder_silo_45pct", "frac": 0.45, "yaw": 80.0,  "pitch": 8.0,  "k": 0.60, "fy": 0.66},
	{"id": "compactor",     "label": "compactor_kijkglas_33pct", "frac": 0.33, "yaw": 35.0, "pitch": 12.0, "k": 0.60, "fy": 0.45},
	{"id": "compactor",     "label": "compactor_kijkglas_33pct_back", "frac": 0.33, "yaw": 215.0, "pitch": 12.0, "k": 0.60, "fy": 0.45},
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
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	for c in CASES:
		await _shoot(c, cam)
	get_tree().quit(0)

func _shoot(c: Dictionary, cam: Camera3D) -> void:
	var pid : String = c["id"]
	var item : Dictionary = PlaceableCatalog.get_item(pid)
	var sz : Vector3 = item.get("size", Vector3.ONE)
	var node : Node3D = PlaceableCatalog.build_node(pid, false)
	add_child(node)
	if node is RigidBody3D:
		(node as RigidBody3D).freeze = true
	node.global_position = Vector3.ZERO
	await get_tree().process_frame
	if pid == "compactor":
		PlaceableCatalog.set_pot_fill(node, float(c["frac"]))
	else:
		PlaceableCatalog.set_silo_fill(node, float(c["frac"]))
	print("[SHOT] %s at %.0f %%" % [c["label"], float(c["frac"]) * 100.0])
	var reach : float = maxf(sz.x, maxf(sz.y, sz.z))
	var dist : float = reach * float(c["k"]) + 1.5
	var yr : float = deg_to_rad(float(c["yaw"]))
	var pr : float = deg_to_rad(float(c["pitch"]))
	var focus := Vector3(0.0, sz.y * float(c["fy"]), 0.0)
	cam.global_position = focus + Vector3(sin(yr) * cos(pr) * dist, sin(pr) * dist, cos(yr) * cos(pr) * dist)
	cam.look_at(focus, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.8).timeout
	var img := get_viewport().get_texture().get_image()
	var outp : String = OUT_DIR + "shot_silo_level_%s.png" % String(c["label"])
	img.save_png(outp)
	preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[SHOT] saved ", ProjectSettings.globalize_path(outp))
	node.queue_free()
	await get_tree().process_frame
