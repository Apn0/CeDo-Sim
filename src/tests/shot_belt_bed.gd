extends Node3D
## P1 (2026-09-23) — render the film BED on the belts for the operator's eye.
## Run WINDOWED (the dummy renderer captures nothing):
##   Godot --path . res://src/tests/shot_belt_bed.tscn
## Writes docs/plant/renders/shot_belt_bed_<case>.png, one file per case
## (operator rule 2026-07-15: unique names, never a shared one).
##
## The fields are driven directly with set_belt_state — the same call LineFlow
## makes — to the bed each case names, then the drift runs for a moment so the
## flakes are seated and spinning before the capture. The inclined belt is
## rendered twice: UNMERGED with its deck rotated back the old way ("before":
## the deck ran the opposite diagonal to its rollers, measured 2026-09-23) and
## as built now ("after").

const OUT_DIR := "res://docs/plant/renders/"

# case: id, label, thru kg/s, deck m/s, wet01, dirt01, yaw, pitch, dist mult
const CASES : Array = [
	{"id": "transport_belt",   "label": "transport_belt_thin_2p8cm",    "thru": 0.5,  "v": 0.4, "wet": 0.0, "yaw": 38.0, "pitch": 22.0, "k": 1.05},
	{"id": "transportband_3",  "label": "transportband_3_even_5cm",     "thru": 1.2,  "v": 0.5, "wet": 0.0, "yaw": 32.0, "pitch": 18.0, "k": 0.80},
	{"id": "transportband_3",  "label": "transportband_3_wet",          "thru": 1.2,  "v": 0.5, "wet": 1.0, "yaw": 32.0, "pitch": 18.0, "k": 0.80},
	{"id": "transportband_3",  "label": "transportband_3_close",        "thru": 1.2,  "v": 0.5, "wet": 0.0, "yaw": 20.0, "pitch": 24.0, "k": 0.35},
	{"id": "transportband_3",  "label": "transportband_3_flakes_only",  "thru": 1.2,  "v": 0.5, "wet": 0.0, "yaw": 20.0, "pitch": 24.0, "k": 0.35, "no_heap": true},
	{"id": "compactorband",    "label": "compactorband_0p61kgps_4cmps", "thru": 0.61, "v": 0.04, "wet": 0.0, "yaw": 40.0, "pitch": 20.0, "k": 1.10},
	{"id": "inclined_belt_8m", "label": "inclined_belt_8m_after",       "thru": 1.5,  "v": 0.4, "wet": 0.0, "yaw": 55.0, "pitch": 12.0, "k": 1.05},
	{"id": "inclined_belt_8m", "label": "inclined_belt_8m_before",      "thru": 0.0,  "v": 0.4, "wet": 0.0, "yaw": 55.0, "pitch": 12.0, "k": 1.05, "before": true},
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
	var node : Node3D = null
	if bool(c.get("before", false)):
		# The pre-fix geometry: unmerged extras, deck + rails rotated +angle.
		node = Node3D.new()
		add_child(node)
		PlaceableCatalog._inclined_belt_extras(node, node, sz, {}, false)
		for ch in node.get_children():
			var mi := ch as MeshInstance3D
			if mi != null and mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.z > 10.0:
				mi.rotation = Vector3(-mi.rotation.x, 0.0, 0.0)
		var fr := node.get_node_or_null("DeckFrame")
		if fr != null:
			fr.queue_free()
	else:
		node = PlaceableCatalog.build_node(pid, false)
		add_child(node)
		if node is RigidBody3D:
			(node as RigidBody3D).freeze = true
	node.global_position = Vector3.ZERO
	await get_tree().process_frame
	# drive every field on it to the case's bed (1200 ticks = 120 s: past the
	# 96 s transit time of the 4 cm/s compactorband)
	for f in node.find_children("*", "", true, false):
		if f.is_in_group("film_field") and bool(f.get("belt_mode")):
			for _i in 1200:
				f.call("set_belt_state", float(c["thru"]), float(c["v"]), true, float(c["wet"]), 0.0, 0.1)
			print("[SHOT] %s: bed %.2f kg/m, depth %.1f cm, %d flakes" % [c["label"], float(f.call("bed_kg_per_m")), float(f.call("bed_depth_m")) * 100.0, int(f.call("visible_count"))])
			var fm : ShaderMaterial = f.get("_flake_shader_mat")
			if fm != null:
				print("[SHOT]   shader axis %s up %s len %s depth %s scroll %s" % [str(fm.get_shader_parameter("belt_axis")), str(fm.get_shader_parameter("belt_up")), str(fm.get_shader_parameter("belt_len")), str(fm.get_shader_parameter("bed_depth")), str(fm.get_shader_parameter("scroll"))])
			if bool(c.get("no_heap", false)):
				var hp := f.get_node_or_null("BedHeap") as Node3D
				if hp != null:
					hp.visible = false
	var reach : float = maxf(sz.x, maxf(sz.y, sz.z))
	var dist : float = reach * float(c["k"]) + 1.5
	var yr : float = deg_to_rad(float(c["yaw"]))
	var pr : float = deg_to_rad(float(c["pitch"]))
	var focus := Vector3(0.0, sz.y * 0.5, 0.0)
	if pid == "inclined_belt_8m":
		focus = Vector3(0.0, 4.0, 4.0)
	elif float(c["k"]) < 0.5:
		focus = Vector3(0.0, sz.y * 0.95, sz.z * 0.15)   # close-ups look at the deck top
	cam.global_position = focus + Vector3(sin(yr) * cos(pr) * dist, sin(pr) * dist, cos(yr) * cos(pr) * dist)
	cam.look_at(focus, Vector3.UP)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(1.2).timeout
	var img := get_viewport().get_texture().get_image()
	var outp : String = OUT_DIR + "shot_belt_bed_%s.png" % String(c["label"])
	img.save_png(outp)
	preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[SHOT] saved ", ProjectSettings.globalize_path(outp))
	node.queue_free()
	await get_tree().process_frame
