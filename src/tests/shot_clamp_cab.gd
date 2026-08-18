extends Node3D
## RENDER PROBE — what the BaleClamp operator actually SEES from the cab seat.
## Not a test: a camera. Writes a PNG so a geometry claim ("the lever shafts are
## invisible, only the knobs read") can be LOOKED AT instead of asserted.
##
##   Godot --path <proj> --rendering-driver ... res://src/tests/shot_clamp_cab.tscn -- <outname>
##
## Output: docs/plant/renders/<outname>.png  (project rule: renders live in the repo)

const OUT_DIR := "res://docs/plant/renders"

func _ready() -> void:
	var tag := "clamp_cab"
	for a in OS.get_cmdline_user_args():
		tag = String(a)
	var scn := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
	var v : Node3D = scn.instantiate()
	# Strip the script so BaseVehicle._ready() does not build the camera rig /
	# beeper / lights — we want the AUTHORED pose exactly as saved in the .tscn.
	v.set_script(null)
	add_child(v)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.45, 0.52, 0.60)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.75, 0.78, 0.82)
	e.ambient_light_energy = 1.0
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.4
	add_child(sun)

	var src : Camera3D = v.get_node("CabCamera")
	var cam := Camera3D.new()
	add_child(cam)
	cam.global_transform = src.global_transform
	cam.fov = 70.0
	cam.near = 0.03
	cam.current = true
	src.queue_free()

	print("[shot] cab eye = %s  fov=%.0f" % [str(cam.global_transform.origin), cam.fov])
	for i in range(6):
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))
	var path := "%s/%s.png" % [OUT_DIR, tag]
	var err := img.save_png(path)
	print("[shot] wrote %s (err=%d)  %dx%d" % [ProjectSettings.globalize_path(path), err, img.get_width(), img.get_height()])
	get_tree().quit(0)
