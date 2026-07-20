extends Node3D
# =============================================================================
# Flake-model reference shot (operator photos 2026-07-20 — compactor conveyor
# before the PCU, plus the close-up of the finished material).
#
# The operator's note: "currently flakes are modeled as squares, flat squares —
# well obviously you can see in this image they are not flat squares".
#
# Renders BOTH so the change is checkable, not just claimed:
#   LEFT  = the OLD mesh, rebuilt here verbatim from the previous code
#           (BoxMesh flake_size x flake_size*0.15 x flake_size, uniform pose,
#           PALETTE cycled evenly)
#   RIGHT = the CURRENT FilmFlakeField
#
#   Godot --path . res://src/tests/shot_flakes.tscn
# =============================================================================

const FLAKE_SIZE := 0.07
const COUNT := 220

func _ready() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.34, 0.36, 0.40)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.70, 0.72, 0.75)
	env.ambient_light_energy = 1.35
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-55.0), deg_to_rad(-30.0), 0.0)
	sun.light_energy = 1.5
	add_child(sun)

	# Belt-ish deck under each sample.
	for x in [-1.15, 1.15]:
		var deck := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1.9, 0.05, 1.9)
		deck.mesh = bm
		var dm := StandardMaterial3D.new()
		dm.albedo_color = Color(0.42, 0.34, 0.24)      # conveyor belt tan
		deck.mesh.surface_set_material(0, dm)
		deck.position = Vector3(x, -0.03, 0.0)
		add_child(deck)

	_build_old_sample(Vector3(-1.15, 0.0, 0.0))
	_build_new_sample(Vector3(1.15, 0.0, 0.0))

	var lbl := Label.new()
	lbl.text = "  OLD: flat square chips              NEW: crumpled shreds (operator photos 2026-07-20)"
	lbl.position = Vector2(20, 18)
	lbl.add_theme_font_size_override("font_size", 22)
	add_child(lbl)

	var cam := Camera3D.new(); add_child(cam)
	cam.global_position = Vector3(0.0, 1.15, 1.75)
	cam.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)
	cam.make_current()

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.6).timeout
	var img := get_viewport().get_texture().get_image()
	img.save_png("user://shot_flakes.png")
	print("[FLAKES] saved ", ProjectSettings.globalize_path("user://shot_flakes.png"))
	get_tree().quit(0)

## The previous model, reproduced exactly: one flat box, yaw only, palette cycled.
func _build_old_sample(at: Vector3) -> void:
	var chip := BoxMesh.new()
	chip.size = Vector3(FLAKE_SIZE, FLAKE_SIZE * 0.15, FLAKE_SIZE)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.7
	chip.surface_set_material(0, mat)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = chip
	mm.instance_count = COUNT
	mm.visible_instance_count = COUNT
	var rng := RandomNumberGenerator.new(); rng.seed = 4242
	for i in COUNT:
		var b := Basis(Vector3.UP, rng.randf() * TAU)
		mm.set_instance_transform(i, Transform3D(b, at + Vector3(
			rng.randf_range(-0.8, 0.8), rng.randf_range(0.0, 0.10), rng.randf_range(-0.8, 0.8))))
		mm.set_instance_color(i, FilmFlakeField.PALETTE[i % FilmFlakeField.PALETTE.size()])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)

## The live FilmFlakeField, driven to full visibility.
func _build_new_sample(at: Vector3) -> void:
	var field := FilmFlakeField.new()
	field.flake_count = COUNT
	field.area = Vector2(1.6, 1.6)
	field.surface_y = 0.04
	field.flake_size = FLAKE_SIZE
	field.flow_speed = 0.0
	field.position = at
	add_child(field)
	field.set_live_state(0.9, 0.2, 0.15, 1.0)
