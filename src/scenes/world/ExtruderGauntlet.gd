extends "res://src/scenes/world/GauntletWorld.gd"
##
## EXTRUDER TEST GAUNTLET — a minimal live-editing bench.
##
## Flat floor + sun + player + ONE extruder line rig:
##   * detailed extruder unit (catalog "extruder_3a" — EIRENE/Wave-Cut model)
##   * cutter-compactor / PCU (catalog "cutter_compactor") at the intake side
##   * lump cart parked at the laser-filter discharge
##   * Extruder3B.tscn sim brain (ExtruderMachine + ExtruderConfig) placed at
##     the detailed model with its placeholder box hidden — so the HMI scopes,
##     SWI-049 startup flow, SimTick ticking and the FAULT cascade all run
##     against the real sim while the operator looks at the real model.
##
## Purpose: run from the Godot editor (F5 → this scene, or via the main-menu
## button) and use LIVE SCENE EDITING — tweak transforms/params in the editor
## while the debugger session is running, watch them apply in-game, then save
## confirmed values back into the static scripts/catalog.
##
## Inherits GauntletWorld for the floor/sun/player/HUD/BuildMode plumbing but
## replaces the station walk entirely — no signs, no Y/N/R status board.

func _ready() -> void:
	_build_bench_floor()
	_build_sky_light()
	_build_rig()
	_build_player()
	OperatorContext.spawn_under(self, _player)
	_spawn_build_mode()
	_spawn_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[ExtruderGauntlet] bench ready — extruder_3a + cutter_compactor + lump cart; HMI + BuildMode live")

## Override: the parent points BuildMode at user://gauntlet_layout.json, which
## carries whatever was ever built in the WALK gauntlet (compressors, air tank,
## pressure washer, dirt hot-spots…) — all of that spawned into the "empty"
## bench on first boot. The bench gets its OWN layout file so it starts truly
## empty and anything built here stays here.
func _spawn_build_mode() -> void:
	if _player == null:
		push_warning("[ExtruderGauntlet] BuildMode skipped — no player")
		return
	var bm := BM.new()
	bm.name = "BuildMode"
	bm.player_body = _player
	bm.wall_openings = null
	bm.layout_path = "user://extruder_bench_layout.json"
	bm.allow_legacy_fallback = false
	bm.load_shared_structure = false   # no building shell → no site doors/gates
	add_child(bm)
	print("[ExtruderGauntlet] BuildMode ready — bench-local layout, Tab to build")

## Fixed 60×40 slab — the parent's floor sizes itself from STATIONS, which
## this bench doesn't use.
func _build_bench_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "BenchFloor"
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(60.0, FLOOR_THICKNESS_M, 40.0)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.30, 0.32)
	mat.roughness = 0.88
	mesh.material_override = mat
	mesh.position = Vector3(10.0, -FLOOR_THICKNESS_M * 0.5, 8.0)
	floor_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = bm.size
	col.shape = bx
	col.position = mesh.position
	floor_body.add_child(col)

func _build_rig() -> void:
	# Detailed extruder unit — long axis on Z, intake (rear) at -Z.
	var ext : Node3D = PlaceableCatalog.build_node("extruder_3a", false, false)
	if ext != null:
		add_child(ext)
		ext.global_position = Vector3(8.0, 0.0, 10.0)
	# Cutter-compactor (PCU / agglomerator) at the intake side.
	var pcu : Node3D = PlaceableCatalog.build_node("cutter_compactor", false, false)
	if pcu != null:
		add_child(pcu)
		pcu.global_position = Vector3(8.0, 0.0, 0.5)
	# Lump cart near the laser-filter discharge (front half of the unit).
	var cart : Node3D = PlaceableCatalog.build_node("lump_cart", false, false)
	if cart != null:
		add_child(cart)
		cart.global_position = Vector3(5.5, 0.0, 14.0)
	# Sim brain: full ExtruderMachine (model + HMI binding + InteractionArea),
	# co-located with the detailed model. Its placeholder box mesh is hidden so
	# the catalog model is the only visible extruder; collision + interaction
	# area + debug label stay live.
	var brain_scene := load("res://src/scenes/machines/Extruder3B.tscn") as PackedScene
	if brain_scene != null:
		var brain := brain_scene.instantiate() as Node3D
		brain.name = "ExtruderBrain"
		add_child(brain)
		brain.global_position = Vector3(8.0, 0.0, 10.0)
		var body_mesh := brain.get_node_or_null("Body/BodyMesh") as MeshInstance3D
		if body_mesh != null:
			body_mesh.visible = false
		var lbl := brain.get_node_or_null("DebugLabel") as Label3D
		if lbl != null:
			lbl.text = "Extruder bench (live sim)"
	else:
		push_warning("[ExtruderGauntlet] Extruder3B.tscn missing — no live sim brain")
