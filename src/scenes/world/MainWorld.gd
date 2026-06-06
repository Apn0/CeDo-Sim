extends Node3D

class_name MainWorld

# ── Export ────────────────────────────────────────────────────────────────────
@export var building_shell_path: String = "res://assets/models/CeDo_building.obj"

# #171 — show a small driven rotor on each Line 3C machine (its spin is the one
# that gates flow). Flip to false if the rotors read too busy with the flakes.
const SHOW_LINE_ROTORS := true

# ── Fallback spawn positions (used only if NPCSpawnPoints markers are missing)
var npc_spawn_fallback: Dictionary = {
	"romain":     Vector3(0,   0,  5),
	"vincent":    Vector3(5,   0,  5),
	"pascal":     Vector3(-5,  0,  0),
	"kevin":      Vector3(-5,  0, -5),
	"emrah":      Vector3(0,   0,-10),
	"yassine":    Vector3(5,   0, -5),
	"abdellilah": Vector3(10,  0,  0),
	"mohammed":   Vector3(10,  0, -5),
	"peter":      Vector3(15,  0, 10),
}

# ── Runtime references ────────────────────────────────────────────────────────
var player          : CharacterBody3D
var shift_clock     : ShiftClock
var game_state      : GameState
var hud             : CanvasLayer
var operator_context: OperatorContext
var build_mode      : BuildMode
var wall_openings   : WallOpenings
var line_flow       : LineFlow
var crew_manager    : CrewManager
var npcs            : Dictionary = {}

# Where the player actually spawned this run (marker OR resumed save position).
# The forklift parks 3 m from here so it's always within reach on spawn.
var _player_spawn_pos : Vector3 = Vector3.ZERO

# Setup mode state
var is_setup_mode : bool = false
var setup_overlay : CanvasLayer = null

# ── NPC catalogue ─────────────────────────────────────────────────────────────
const NPC_DATA: Dictionary = {
	"romain":     {"name": "Romain",     "role": "shift_leader",       "color": Color.CYAN},
	"vincent":    {"name": "Vincent",    "role": "asst_shift_leader",  "color": Color.CORNFLOWER_BLUE},
	"pascal":     {"name": "Pascal",     "role": "extruder_op",        "color": Color.YELLOW},
	"kevin":      {"name": "Kevin",      "role": "extruder_op",        "color": Color.GREEN},
	"emrah":      {"name": "Emrah",      "role": "all_rounder",        "color": Color.WHITE},
	"yassine":    {"name": "Yassine",    "role": "transitional",       "color": Color.LIGHT_GRAY},
	"abdellilah": {"name": "Abdellilah", "role": "permanent_feeder",   "color": Color.ORANGE},
	"mohammed":   {"name": "Mohammed",   "role": "permanent_feeder",   "color": Color.TOMATO},
	"peter":      {"name": "Peter",      "role": "production_manager", "color": Color.MEDIUM_ORCHID},
}

# =============================================================================
## When true, the scattered test/demo props are NOT spawned — a clean canvas of just
## the rebuilt Line 3C + vehicles + utilities. Set false to restore the test props.
const CLEAN_CANVAS : bool = true

func _ready() -> void:
	# Children's _ready() has already run — GameState has loaded its save file.
	shift_clock = find_child("ShiftClock", false, false) as ShiftClock
	game_state  = find_child("GameState",  false, false) as GameState

	if not shift_clock: push_error("[MainWorld] ShiftClock node missing")
	if not game_state:  push_error("[MainWorld] GameState node missing")

	_load_building_shell()
	_spawn_wall_openings()
	_spawn_player()
	_spawn_operator_context()
	_spawn_build_mode()
	_spawn_line_flow()
	_spawn_npcs()
	_spawn_hud()
	
	if game_state and game_state.is_new_save:
		_start_setup_mode()
	else:
		_spawn_world_items()

func _start_setup_mode() -> void:
	is_setup_mode = true
	setup_overlay = CanvasLayer.new()
	var center = CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	var label = Label.new()
	label.text = "Walk to the desired Factory Center and press ENTER"
	label.add_theme_font_size_override("font_size", 32)
	var panel = PanelContainer.new()
	panel.add_child(label)
	center.add_child(panel)
	setup_overlay.add_child(center)
	add_child(setup_overlay)

func _input(event: InputEvent) -> void:
	if is_setup_mode and event.is_action_pressed("ui_accept"):
		if player and game_state:
			game_state.factory_center = player.global_position
			game_state.is_new_save = false
			is_setup_mode = false
			if setup_overlay:
				setup_overlay.queue_free()
			save_game()
			_spawn_world_items()

func _spawn_world_items() -> void:
	_spawn_forklift()
	_spawn_bale_clamp()
	_spawn_merlo()
	_spawn_scissor_lift()
	# Line 3C is no longer auto-built — the scene starts clean (#29). Only the 3C/6
	# opzetband + shredder are spawned (in _spawn_feeder_line); build the rest from the
	# menu. To bring the full demo line back, call _spawn_line_3c() here again.
	# Utilities kept (charger / outlet+pump / scissors tool / LPG rack).
	_spawn_battery_station()   # walkie-battery charger in the shift-leader office
	_spawn_shift_leader_desk() # shift-leader PC: the bale scan log (#3)
	_spawn_service_stations()  # wall outlet (electric lift) + diesel pump
	_spawn_wire_cutter()       # concrete-scissors tool the player picks up on foot
	_spawn_lpg_rack()          # outdoor LPG cylinder rack — full below, empty above
	# CLEAN CANVAS (#2): the scattered TEST/DEMO props (standalone extruder 3B, the
	# feedstock bale yard, the test intake bunker, the steel skip, the Wave-5 waste
	# zones) are skipped so the scene is just the rebuilt Line 3C + vehicles + tools.
	# Flip to false to bring the test props back.
	if not CLEAN_CANVAS:
		_spawn_extruder_3b()
		_spawn_bale_yard()
		_spawn_test_bunker()
		_spawn_test_skip()
		_spawn_test_waste_zones()
	_spawn_feeder_line()       # (currently disabled — see FEEDERS_ENABLED)
	# Final LineFlow discovery pass — AFTER every machine exists (demo pipeline +
	# the test bunker). _spawn_demo_pipeline's own rebuild ran before the test
	# bunker spawned, so this is the one that actually registers it as a feed point.
	if line_flow:
		line_flow.rebuild()
	_spawn_crew_manager()      # after NPCs + LineFlow (incl. demo pipeline) exist
	_start_or_resume_shift()
	_setup_autosave()

	# WorldEnvironment + sun are now in the tree — push saved graphics prefs
	# (SSAO / SDFGI / fog / brightness / shadow distance) onto them.
	SettingsManager.refresh_environment()
	_apply_textures()

	print("[MainWorld] Ready — %d NPCs, shift running: %s" \
		% [npcs.size(), str(shift_clock.shift_active) if shift_clock else "?"])

# =============================================================================
# BUILDING SHELL
# =============================================================================
func _load_building_shell() -> void:
	var mesh_instance := find_child("ShellMesh", true, false) as MeshInstance3D
	if not mesh_instance:
		push_error("[MainWorld] ShellMesh not found")
		return
	mesh_instance.create_trimesh_collision()
	print("[MainWorld] Building collision generated")
	_generate_floor_from_shell(mesh_instance)
	print("[MainWorld] Dynamic floor generated from building corners")

# Caches the building mesh so doors/windows can carve real, walkable openings
# at runtime (never touches the source .obj). Must exist BEFORE BuildMode loads
# its layout, since saved doors/windows re-cut their holes on load.
# =============================================================================
# PROCEDURAL TEXTURES  (no image assets exist — surface detail is generated)
# =============================================================================
func _apply_textures() -> void:
	# Floor — worn concrete
	var floor_node := find_child("TempFloor", true, false)
	if floor_node:
		var fm := floor_node.find_child("MeshInstance3D", false, false) as MeshInstance3D
		if fm:
			fm.material_override = _industrial_mat(Color(0.42, 0.41, 0.39), 0.35, 0.95, false)
	# Building shell — painted concrete/steel. Use a SIMPLE flat material rather
	# than the triplanar-noise one: the noise normal-map combined with the .obj's
	# mixed winding was making some wall/roof faces render black on one side.
	# WallOpenings now regenerates normals from winding AND flips inward-facing
	# tris (see WallOpenings._fix_winding_outward), so the shell can use a clean
	# matte pass without the noise normal-map trickery.
	var shell := find_child("ShellMesh", true, false) as MeshInstance3D
	if shell:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.78, 0.76, 0.72)
		sm.roughness    = 0.95          # matte — kills bright specular hot-spots
		sm.metallic     = 0.0
		# CULL_DISABLED so back faces still render (single-sided walls would
		# disappear from one side otherwise). Godot auto-flips the normal on
		# the back face, so both sides light correctly.
		sm.cull_mode    = BaseMaterial3D.CULL_DISABLED
		shell.material_override = sm
	print("[MainWorld] Procedural textures applied (floor + building)")

## Procedural surface material: world-triplanar bump + roughness noise so the
## surface has real texture under light, without needing any image files.
func _industrial_mat(base: Color, tex_scale: float, rough: float, cull_off: bool) -> StandardMaterial3D:
	var rn := FastNoiseLite.new()
	rn.frequency = 0.5
	var rough_tex := NoiseTexture2D.new()
	rough_tex.width = 256
	rough_tex.height = 256
	rough_tex.seamless = true
	rough_tex.noise = rn

	var nn := FastNoiseLite.new()
	nn.frequency = 0.9
	var normal_tex := NoiseTexture2D.new()
	normal_tex.width = 256
	normal_tex.height = 256
	normal_tex.seamless = true
	normal_tex.as_normal_map = true
	normal_tex.bump_strength = 1.5
	normal_tex.noise = nn

	var m := StandardMaterial3D.new()
	m.albedo_color = base
	m.roughness = rough
	m.roughness_texture = rough_tex
	m.normal_enabled = true
	m.normal_texture = normal_tex
	m.normal_scale = 0.7
	m.uv1_triplanar = true            # works without mesh UVs (the carved shell has none)
	m.uv1_world_triplanar = true      # consistent real-world tiling
	m.uv1_scale = Vector3(tex_scale, tex_scale, tex_scale)
	if cull_off:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m

func _spawn_wall_openings() -> void:
	var shell := find_child("ShellMesh", true, false) as MeshInstance3D
	if not shell:
		push_error("[MainWorld] ShellMesh not found — wall openings disabled")
		return
	wall_openings = WallOpenings.new()
	wall_openings.name = "WallOpenings"
	add_child(wall_openings)
	wall_openings.setup(shell)
	print("[MainWorld] WallOpenings ready")

# =============================================================================
# PLAYER
# =============================================================================
func _spawn_player() -> void:
	## Tries saved position first; falls back to the PlayerSpawn marker.
	## Saved position is the actual capsule centre (no +1.0 lift needed on load).

	var spawn_pos  : Vector3 = Vector3.ZERO
	var spawn_rot_y: float   = 0.0
	var from_save  : bool    = false

	if game_state:
		var saved := game_state.load_player_state()
		if saved.has("x"):
			spawn_pos   = Vector3(saved["x"], saved["y"], saved["z"])
			spawn_rot_y = saved.get("rot_y", 0.0)
			from_save   = true

	if not from_save:
		var marker := find_child("PlayerSpawn", false, false) as Node3D
		spawn_pos = marker.global_position if marker else Vector3(0.0, 1.0, 0.0)
		spawn_pos.y += 1.0   # lift above marker so capsule doesn't clip floor

	var script := load("res://src/scenes/player/PlayerController.gd")
	if not script:
		push_error("[MainWorld] PlayerController.gd not found")
		return

	player = CharacterBody3D.new()
	player.name = "Player"
	player.set_script(script)

	var head := Node3D.new()
	head.name     = "Head"
	head.position = Vector3(0.0, 0.7, 0.0)   # eye level above capsule centre
	player.add_child(head)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true   # explicitly own the viewport so vehicle CabCameras
							# added later don't accidentally win the fallback.
	head.add_child(camera)

	var col := CollisionShape3D.new()
	col.name = "Collision"          # PlayerController resizes this for crouch/prone
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape  = cap
	player.add_child(col)

	add_child(player)
	player.global_position = spawn_pos
	if from_save:
		player.rotation.y = spawn_rot_y

	# Remember where the player actually ended up so the forklift can park right
	# beside them — whether they spawned at the marker or resumed a save 500 m away.
	_player_spawn_pos = player.global_position

	print("[MainWorld] Player spawned at %s%s" \
		% [player.global_position, " (resumed)" if from_save else ""])

func _get_factory_anchor() -> Vector3:
	if game_state and game_state.factory_center != Vector3.ZERO:
		return game_state.factory_center
	if _player_spawn_pos != Vector3.ZERO:
		return _player_spawn_pos
	var marker := find_child("PlayerSpawn", false, false) as Node3D
	if marker:
		return marker.global_position
	return Vector3.ZERO

# =============================================================================
# NPCs
# =============================================================================
func _spawn_npcs() -> void:
	var spawn_root := find_child("NPCSpawnPoints", false, false) as Node3D
	var marker_map : Dictionary = {}

	if spawn_root:
		for child in spawn_root.get_children():
			marker_map[child.name.to_lower()] = (child as Node3D).global_position
	else:
		push_warning("[MainWorld] NPCSpawnPoints not found — using fallback positions")

	var npc_script := load("res://src/scenes/world/NPC.gd")

	for npc_id in NPC_DATA.keys():
		var data : Dictionary = NPC_DATA[npc_id]
		var pos  : Vector3   = marker_map.get(npc_id, npc_spawn_fallback.get(npc_id, Vector3.ZERO))
		pos.y += 1.0

		var npc := CharacterBody3D.new()
		npc.name = data["name"]

		var mi    := MeshInstance3D.new()
		var cmesh := CapsuleMesh.new()
		cmesh.radius = 0.3
		cmesh.height = 1.8
		mi.mesh = cmesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = data["color"]
		mi.material_override = mat
		npc.add_child(mi)

		var col := CollisionShape3D.new()
		var cap := CapsuleShape3D.new()
		cap.radius = 0.3
		cap.height = 1.8
		col.shape  = cap
		npc.add_child(col)

		if npc_script:
			npc.set_script(npc_script)

		npc.set_meta("map_color", data["color"])   # MapOverlay draws crew in this colour

		add_child(npc)
		npc.global_position = pos
		npcs[npc_id] = npc

# =============================================================================
# CREW MANAGER — posts the shift crew, dispatches them to jams, rotates breaks
# =============================================================================
## Turns the spawned NPCs into a working shift team. Each on-duty worker is posted
## at the machine its role covers; the manager then watches LineFlow's buffer
## telemetry and walks the right free worker over to clear jams, while rotating one
## worker at a time off to the canteen. Must run AFTER _spawn_npcs() and after the
## full machine line (incl. the demo pipeline) exists, since posting reads the live
## LineFlow node list and each worker's spawn position.
func _spawn_crew_manager() -> void:
	if npcs.is_empty() or line_flow == null:
		push_warning("[MainWorld] CrewManager skipped — no NPCs or LineFlow")
		return
	crew_manager = CrewManager.new()
	crew_manager.name = "CrewManager"

	# Break room: use a BreakRoom/Canteen marker if the level has one, else a fixed
	# spot near the factory entrance.
	var break_pos := Vector3(0.0, 0.0, 25.0)
	var canteen := find_child("BreakRoom", false, false) as Node3D
	if canteen == null:
		canteen = find_child("Canteen", false, false) as Node3D
	if canteen:
		break_pos = canteen.global_position

	add_child(crew_manager)
	crew_manager.setup(npcs, line_flow, shift_clock, break_pos)
	print("[MainWorld] CrewManager ready — %d workers posted, canteen @ %s"
		% [crew_manager.workers.size(), str(break_pos)])

# =============================================================================
# OPERATOR CONTEXT (embodiment switcher: on_foot ↔ forklift ↔ ...)
# =============================================================================
func _spawn_operator_context() -> void:
	operator_context = OperatorContext.new()
	operator_context.name = "OperatorContext"
	operator_context.on_foot_body = player
	operator_context.foot_camera  = player.find_child("Camera3D", true, false) as Camera3D
	add_child(operator_context)
	print("[MainWorld] OperatorContext ready")

# =============================================================================
# BUILD MODE (in-game factory builder — press Tab)
# =============================================================================
func _spawn_build_mode() -> void:
	build_mode = BuildMode.new()
	build_mode.name = "BuildMode"
	build_mode.player_body = player        # so placement rays ignore the capsule
	build_mode.wall_openings = wall_openings   # set BEFORE add_child → load_layout
	add_child(build_mode)
	print("[MainWorld] BuildMode ready — press Tab to build")
	# Tool-placement mode (the build-mode sibling for hand-held items). Same
	# UX as BuildMode (ghost preview + rotate + confirm) but operates on the
	# active Inventory tool — never spawns from catalog, so accidental tap
	# can't drop a machine into the world.
	var tool_place := preload("res://src/build/ToolPlacementMode.gd").new()
	tool_place.name = "ToolPlacementMode"
	tool_place.main_world = self
	add_child(tool_place)
	print("[MainWorld] ToolPlacementMode ready — press G to place held tool")

# =============================================================================
# LINE FLOW (auto-links placed machines + simulates material through them)
# =============================================================================
func _spawn_line_flow() -> void:
	line_flow = LineFlow.new()
	line_flow.name = "LineFlow"
	add_child(line_flow)                   # _ready() discovers machines already placed
	if build_mode:
		build_mode.line_flow = line_flow   # so placing/deleting re-links the line
	print("[MainWorld] LineFlow ready")

# =============================================================================
# VEHICLES — placeholder forklift parked near the entrance
# =============================================================================
func _spawn_forklift() -> void:
	var fork_scene := load("res://src/scenes/vehicles/Forklift.tscn") as PackedScene
	if not fork_scene:
		push_warning("[MainWorld] Forklift.tscn missing — skipping")
		return
	var fork := fork_scene.instantiate()
	add_child(fork)
	# Park 3 m to the player's side so it's the first thing they see on spawn. We
	# anchor to where the PLAYER actually ended up (which may be a resumed save
	# 500 m from the marker), NOT the marker — otherwise a saved game leaves the
	# forklift stranded back at origin while the player is out by the pipeline.
	var anchor := _get_factory_anchor()
	anchor.x += 3.0      # 3 m to the side — close enough to reach immediately
	anchor.y += 0.5      # small clearance so wheels settle without a hard bounce
	fork.global_position = anchor
	print("[MainWorld] Forklift A spawned 3 m from anchor at %s" % str(anchor))

## Anchor for the vehicle row — the player's actual spawn (marker OR resumed save),
## so every vehicle parks beside the player wherever they end up.
func _vehicle_anchor() -> Vector3:
	return _get_factory_anchor()

## World Y of the floor's TOP surface — placing a machine so its AABB bottom sits
## at this Y seats it flush on the floor.
func _floor_top_y() -> float:
	return _floor_min_y_cache

## Combined AABB of all of `node`'s mesh descendants, expressed in `node`'s OWN
## local space (accounts for nested child transforms). Used to seat a machine's
## bottom on the floor regardless of where its origin sits in the geometry.
func _local_aabb(node: Node3D) -> AABB:
	var bb := AABB()
	var started := false
	var inv := node.global_transform.affine_inverse()
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var a : AABB = mi.get_aabb()
		var xf : Transform3D = inv * mi.global_transform
		for ix in [0.0, 1.0]:
			for iy in [0.0, 1.0]:
				for iz in [0.0, 1.0]:
					var corner : Vector3 = a.position + Vector3(a.size.x * ix, a.size.y * iy, a.size.z * iz)
					var p : Vector3 = xf * corner
					if not started:
						bb = AABB(p, Vector3.ZERO); started = true
					else:
						bb = bb.expand(p)
	return bb

## #10 collision audit — give a procedurally-modelled body a SOLID collider sized
## to its visible meshes, so the player & vehicles can't walk through it. The body
## is already a StaticBody3D (BatteryStation / ServiceStation); it only ever had an
## Area3D proximity trigger, so we add the missing solid shape here.
func _fit_box_collider(body: Node3D) -> void:
	if body == null or body.has_node("SolidCollision"):
		return
	var bb := _local_aabb(body)
	if bb.size.x < 0.02 or bb.size.y < 0.02 or bb.size.z < 0.02:
		return
	var cs := CollisionShape3D.new()
	cs.name = "SolidCollision"
	var box := BoxShape3D.new()
	box.size = bb.size
	cs.shape = box
	cs.position = bb.position + bb.size * 0.5
	body.add_child(cs)

func _spawn_bale_clamp() -> void:
	var scene := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
	if not scene:
		push_warning("[MainWorld] BaleClamp.tscn missing — skipping")
		return
	var v := scene.instantiate()
	add_child(v)
	var pos := _vehicle_anchor()
	pos.x += 10.0     # next to the forklift, same reachable floor
	pos.y += 0.5
	v.global_position = pos
	print("[MainWorld] Bale clamp spawned")

func _spawn_merlo() -> void:
	var scene := load("res://src/scenes/vehicles/Merlo.tscn") as PackedScene
	if not scene:
		push_warning("[MainWorld] Merlo.tscn missing — skipping")
		return
	var v := scene.instantiate()
	add_child(v)
	var pos := _vehicle_anchor()
	pos.x += 15.0     # next in the row beside the bale clamp
	pos.y += 0.5
	v.global_position = pos
	print("[MainWorld] Merlo spawned")
	# High-detail Merlo P40 variant from the imported FBX — parked alongside.
	# The original procedural Merlo stays; this is a separate vehicle the
	# operator can choose to drive.
	var scene2 := load("res://src/scenes/vehicles/MerloP40.tscn") as PackedScene
	if scene2:
		var v2 := scene2.instantiate()
		add_child(v2)
		var pos2 := _vehicle_anchor()
		pos2.x += 22.0    # 7 m further along the vehicle row
		pos2.y += 0.5
		v2.global_position = pos2
		print("[MainWorld] Merlo P40 spawned")

func _spawn_scissor_lift() -> void:
	var scene := load("res://src/scenes/vehicles/ScissorLift.tscn") as PackedScene
	if not scene:
		push_warning("[MainWorld] ScissorLift.tscn missing — skipping")
		return
	var v := scene.instantiate()
	add_child(v)
	var pos := _vehicle_anchor()
	pos.x += 20.0     # next in the vehicle row after the Merlo at +15
	pos.y += 0.5      # clearance so wheels settle without bouncing
	v.global_position = pos
	print("[MainWorld] Scissor lift spawned")

# =============================================================================
# BALE YARD — feedstock stacks (2-3 high) the vehicles pick up bottom-first
# =============================================================================
## Lays out one stack per feedstock origin in a row beside the vehicle line. Each
## stack is `origin.stack` bales tall (Rotterdam/Forst+ = 3, Alba/Zwolle = 2) so the
## operator can drive a forklift / bale-clamp / Merlo in, grip the BOTTOM bale, and
## lift the whole column at once — exactly how it's done on the lot. Each bale is a
## frozen RigidBody3D in group "bale" with a unique printed label, identical to a
## build-placed bale, so grab / carry / drop and LineFlow feeding all just work.
func _spawn_bale_yard() -> void:
	# Anchor the yard to where the PLAYER actually spawned (which may be a resumed
	# save far from the marker), so the stacks are always a few steps away to test
	# with — not stranded back at the factory marker.
	var base : Vector3 = _get_factory_anchor()
	# A tidy yard 6 m to the player's side and a few metres ahead — next to the
	# forklift (which parks at +3 on X), clear of the player capsule. Drop the
	# FULL capsule half-height (0.9 m): the spawn anchor is the player capsule's
	# CENTRE, which sits ~0.9 m above the floor, so subtracting it puts each bale
	# base ON the floor instead of hovering.
	base += Vector3(6.0, -0.9, 6.0)

	var yard := Node3D.new()
	yard.name = "BaleYard"
	add_child(yard)
	yard.global_position = Vector3.ZERO

	var origins := BaleDefs.origins()
	var col_x : float = base.x
	var total := 0
	for o in origins:
		var id   : String  = String(o["id"])
		var size : Vector3 = o["size"]
		var high : int     = int(o.get("stack", 2))
		# Vertical column: each bale's base sits on the one below (origin = base).
		var y : float = base.y
		for level in high:
			var bale := PlaceableCatalog.build_node(id, false) as Node3D
			if bale == null:
				continue
			yard.add_child(bale)
			bale.global_position = Vector3(col_x, y, base.z)
			# Stamp a unique code + print the yellow label, same as a placed bale.
			var nm := String(BaleDefs.get_origin(id).get("name", "BALE"))
			var code := "%s-%05d" % [nm.substr(0, 3).to_upper(), (randi() % 100000)]
			bale.set_meta("bale_code", code)
			PlaceableCatalog.add_bale_label(bale, id, code)
			y += size.y          # next bale rests on this one's top
			total += 1
		# Space columns by the widest footprint plus a gangway.
		col_x += maxf(size.x, size.z) + 2.0
	print("[MainWorld] Bale yard: %d bales in %d stacks" % [total, origins.size()])

# =============================================================================
# TEST BUNKER — an intake pit beside the player to dump carried bales into
# =============================================================================
## Drops a single intake bunker a short distance from the player's spawn so the
## full loop is testable on the spot: grab a stack from the yard → carry it over →
## release it at the bunker → LineFlow picks up the delivered bale and meters it in.
## Tagged "placed_object" + "feed_machine" like a build-placed one so LineFlow's
## scan treats it as a real feed point.
func _spawn_test_bunker() -> void:
	var base : Vector3 = _get_factory_anchor()
	# In front of the player, past the bale yard, clear of the vehicle row.
	# -0.9 grounds the base (anchor is the player capsule centre, ~0.9 m up).
	base += Vector3(2.0, -0.9, 14.0)
	var bunker := PlaceableCatalog.build_node("bunker", false) as Node3D
	if bunker == null:
		push_warning("[MainWorld] test bunker build failed")
		return
	add_child(bunker)
	bunker.global_position = base
	print("[MainWorld] Test bunker spawned at %s" % str(base))

# =============================================================================
# DEMO PIPELINE — a full feeding-belt → extruder line, 300 m down the road
# =============================================================================
## A single-file straight-line layout of every catalog machine in process order
## so the player can see the entire LineFlow in action without having to build
## the line themselves. Sits ~300 m west of the player spawn (out of the way of
## the factory's build zone).
##
## Order mirrors the real plant flow described in project_plastic_film_recycling_sim.md:
##   bunker → SGA opener → overband magnet → ballistic sep → windshifter →
##   TITECH NIR sort → shredders → feed hopper → wash (pre / friction /
##   intensive) → flotation → rotation → Kufferath sieve → rafter → dewater
##   screw → dryers → mengsilo → MAS trough → compactor → extruder (sink).
## A waste bin sits at the wash section; the ZSS water plant anchors the tail.
# =============================================================================
# LINE 3C — built in the EXACT machine order from the plant HMI (Line3CDef).
# =============================================================================
## Replaces the old generic demo pipeline. Lays L3C.1 → … → Meltpump head-to-
## tail along +Z within reach of the player. Each machine carries a billboard
## "L3C.x  Name" label + meta (l3c_code / l3c_order) and joins placed_object so
## LineFlow discovers the real flow nodes and feeds ONLY the head (Doseer Silo) —
## you can never feed straight into the extruder (#144). Waste baskets omitted
## (per the operator) — they're placed separately off the separators/dryers.
func _spawn_line_3c() -> void:
	var marker := find_child("PlayerSpawn", false, false) as Node3D
	var base : Vector3 = (marker.global_position if marker else Vector3.ZERO) \
		+ Vector3(-20.0, 0.0, -8.0)
	# Sit the machines ON the floor. The old code used marker.y - 0.9 which landed
	# ~1 m UNDER the floor (the floor top is ~marker.y + 0.15, not 0.9 below it).
	base.y = _floor_top_y()
	var z : float = 0.0
	const GAP : float = 1.4
	const ROW_OFFSET : float = 3.5     # X spacing of the L/R parallel trains
	var built := 0
	var intake_node : Node3D = null
	for i in Line3CDef.STAGES.size():
		var st : Dictionary = Line3CDef.STAGES[i]
		var id : String = st["id"]
		var item := PlaceableCatalog.get_item(id)
		if item.is_empty():
			push_warning("[Line3C] missing catalog item '%s' for %s" % [id, st["code"]])
			continue
		var size : Vector3 = item["size"]
		var node := PlaceableCatalog.build_node(id, false) as Node3D
		if node == null:
			continue
		add_child(node)
		# L/R stages stand side by side as two PARALLEL trains (the real splits); single
		# stages run down the centre. The R partner reuses its L partner's Z slot so the
		# pair is abreast; Z advances once the pair (or a single stage) is placed.
		var code : String = String(st["code"])
		var lane := 0
		# R = RIGHT looking from the line START → END; L = LEFT. (Sides swapped
		# from the original mapping per operator: R sits on -X, L on +X.)
		if code.ends_with("L"):   lane = 1
		elif code.ends_with("R"): lane = -1
		# Seat the machine's BOTTOM on the floor. These machines are CENTRE-origin
		# (geometry spans -h/2..+h/2 around the node), and the catalog size.y does
		# NOT match the built height, so measure the real AABB and offset by it.
		var local_bb : AABB = _local_aabb(node)
		node.global_position = Vector3(
			base.x + float(lane) * ROW_OFFSET,
			base.y - local_bb.position.y,
			base.z + z + size.z * 0.5)
		if not code.ends_with("L"):
			z += size.z + GAP
		# Tag for flow + identification.
		node.set_meta("placeable_id", id)        # so LineFlow.discover() sees it
		node.set_meta("l3c_code", st["code"])
		node.set_meta("l3c_order", i)
		node.set_meta("l3c_amps", st["amps"])
		if not node.is_in_group("placed_object"):
			node.add_to_group("placed_object")
		if Line3CDef.is_intake(st["code"]):
			node.set_meta("is_line_intake", true)
			intake_node = node
		# Billboard "L3C.x  Name" label above the machine.
		var lbl := Label3D.new()
		lbl.text = "%s  %s" % [st["code"], st["name"]]
		lbl.position = Vector3(0.0, size.y + 0.5, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.font_size = 40
		lbl.outline_size = 8
		lbl.modulate = Color(0.92, 0.95, 1.0)
		node.add_child(lbl)
		# #173 — a live flake layer riding this machine's deck. LineFlow finds it by
		# the "film_field" group each tick and drives its density (material present),
		# drift speed (throughput) and wet/dirty tint from the baked process state,
		# so the flakes you SEE reflect the kg/moisture/contam the model COMPUTES.
		var field = preload("res://src/sim/FilmFlakeField.gd").new()
		field.flake_count = 60
		field.area = Vector2(maxf(size.x * 0.7, 0.6), maxf(size.z * 0.7, 0.6))
		field.surface_y = size.y * 0.72
		field.flake_size = 0.06
		field.flow_speed = 0.4
		node.add_child(field)
		# #171 — a small visible drive rotor whose spin IS the one that gates flow:
		# LineFlow drives its set_running() from the PLC power-up, and reads its rpm
		# back into the throughput (_mech_fraction), so a turning rotor literally
		# means material is moving. SHOW_LINE_ROTORS flips them all off if it reads
		# too busy alongside the flake fields.
		if SHOW_LINE_ROTORS:
			_attach_drive_rotor(node, size)
		built += 1
	print("[MainWorld] Line 3C built: %d machines, head=%s" % \
		[built, str(intake_node.name) if intake_node else "?"])

## #171 — attach a small visible DRIVE ROTOR to a Line 3C machine. It's a real
## RotatingMechanism (joins group "mechanism"), so LineFlow already drives it: the
## PLC powers it (set_running) and its live rpm feeds back into the flow rate. A
## dark drum with safety-yellow flight fins makes the rotation read at a glance,
## so a turning rotor literally means material is moving through that machine.
func _attach_drive_rotor(machine: Node3D, size: Vector3) -> void:
	var rm = preload("res://src/sim/RotatingMechanism.gd").new()
	rm.axis = Vector3.RIGHT
	rm.rpm = 42.0
	rm.nominal_rpm = 42.0
	rm.running = false          # starts stopped; the line PLC spins it up
	rm.spin_up_s = 2.5
	rm.position = Vector3(0.0, size.y * 0.6, size.z * 0.42)
	machine.add_child(rm)
	var span : float = clampf(size.x * 0.5, 0.25, 1.0)
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.16, 0.18); dark.metallic = 0.6; dark.roughness = 0.4
	var stripe := StandardMaterial3D.new()
	stripe.albedo_color = Color(0.95, 0.78, 0.20); stripe.roughness = 0.6
	# Drum — a cylinder laid along local X (the spin axis).
	var drum := MeshInstance3D.new()
	var dcm := CylinderMesh.new()
	dcm.top_radius = 0.12; dcm.bottom_radius = 0.12; dcm.height = span; dcm.radial_segments = 14
	drum.mesh = dcm
	drum.rotation.z = deg_to_rad(90.0)
	drum.material_override = dark
	rm.add_child(drum)
	# Three flight fins around the drum so the rotation is unmistakable.
	for a in [0.0, TAU / 3.0, TAU * 2.0 / 3.0]:
		var fin := MeshInstance3D.new()
		var fbm := BoxMesh.new(); fbm.size = Vector3(span * 0.92, 0.03, 0.07)
		fin.mesh = fbm
		fin.material_override = stripe
		fin.position = Vector3(0.0, sin(a) * 0.12, cos(a) * 0.12)
		rm.add_child(fin)

func _spawn_demo_pipeline() -> void:
	var marker := find_child("PlayerSpawn", false, false) as Node3D
	if marker == null:
		push_warning("[MainWorld] PlayerSpawn marker missing — demo pipeline anchored at origin")
	# RELOCATED from 300 m west (far too far to walk to for testing) to ~18 m
	# west of the player spawn, running along +Z. Close enough to reach on foot
	# in a few seconds. The documented machine ORDER in `sequence` below doubles
	# as the line's design doc. (The full physicalised rebuild — real transport
	# rates + the photo-accurate sink separator — is tracked as #145/#147; this
	# is the existing layout, just brought into reach.)
	var origin: Vector3 = (marker.global_position if marker else Vector3.ZERO) \
		+ Vector3(-18.0, 0.0, -6.0)

	var sequence: Array[String] = [
		# ── intake + dry sorting line (TITECH/TOMRA front end) ───────────────
		"bunker",               # bale bunker: forklift dumps, meters onto line
		"sga_drum",             # SGA opener drum: tears bales open, screens fines
		"metal_belt",           # overband magnet: pulls ferrous metal
		"ballistic_sep",        # ballistic separator: 2D film vs 3D rigids
		"wind_sifter",          # zig-zag windshifter: blows off light film
		"titech_sort",          # TITECH NIR sorter: ejects off-spec polymers
		# ── size reduction ──────────────────────────────────────────────────
		"shredder_1",           # coarse pre-shred
		"shredder_2",           # fine shred to flake
		"inclined_belt_8m",     # climb to the washing deck
		"feed_hopper",          # meter flake into the wash
		# ── wet washing + separation ────────────────────────────────────────
		"prewash_drum",         # pre-wash drum: knock off bulk dirt
		"friction_washer",      # friction scrubber
		"intensive_washer",     # hot caustic intensive wash
		"flotation_tank",       # sink/float: drop PET/PVC/sand
		"rotation_tank",        # rotation wash + tumble
		"waste_container",      # heavies/reject bin for the wash section
		"kufferath_sieve",      # Kufferath wedge-wire sieve: drain + screen
		"rafter",               # sieve deck: drain water, screen fines
		# ── dewater + dry ───────────────────────────────────────────────────
		"dewater_screw",        # squeeze out free water
		"mech_dryer",           # thermal dryer: drive off the bulk moisture
		"centrifuge",           # spin dryer: final moisture
		# ── extrusion prep + pelletise ──────────────────────────────────────
		"mengsilo",             # mixing silo: homogenise dry flake
		"mas_bak",              # MAS trough (pre-extruder agglomeration)
		"compactor",            # EREMA compactor
		"extruder_1",           # extruder = the line sink → granulaat
		"zss_water",            # ZSS water plant (services the wash loop)
	]

	const GAP : float = 1.6     # metres between adjacent machine ENDS
	var z: float = 0.0          # cursor along +Z (process direction)
	var count: int = 0
	for id in sequence:
		var item := PlaceableCatalog.get_item(id)
		if item.is_empty():
			push_warning("[MainWorld] Demo pipeline: missing catalog item '%s'" % id)
			continue
		var size: Vector3 = item["size"]
		var node := PlaceableCatalog.build_node(id, false) as Node3D
		if node == null:
			continue
		add_child(node)
		# Centre each machine at z + half its length so it sits flush against
		# the previous one's tail.
		node.global_position = origin + Vector3(0.0, 0.0, z + size.z * 0.5)
		z += size.z + GAP
		count += 1
	# Tall sky-blue beacon at the start of the pipeline so the player can spot
	# it from inside the factory — 60 m tall, visible from anywhere on the lot.
	_spawn_pipeline_beacon(origin, z)

	var bearing := "300 m WEST"
	if marker:
		bearing = "%.0f m WEST of PlayerSpawn (world XYZ = %.0f, %.0f, %.0f → %.0f)" % \
			[300.0, origin.x, origin.y, origin.z, origin.z + z]
	print("[MainWorld] Demo pipeline spawned: %d machines, total length %.0f m, %s"
		% [count, z, bearing])

	# LineFlow's discovery only runs in rebuild() — push it to register the
	# new machines + draw their auto-link connectors.
	if line_flow:
		line_flow.rebuild()

## Big bright pole at the start AND end of the pipeline so the player can find
## the demo line from anywhere on the lot. Sky-blue base + safety-orange top so
## it reads against both ground and sky.
func _spawn_pipeline_beacon(origin: Vector3, length: float) -> void:
	var beacon_root := Node3D.new()
	beacon_root.name = "DemoPipelineBeacons"
	add_child(beacon_root)
	for end_z in [-2.0, length + 2.0]:    # one at the head, one at the tail
		var pole := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.4
		pm.bottom_radius = 0.4
		pm.height = 60.0
		pole.mesh = pm
		var blue_mat := StandardMaterial3D.new()
		blue_mat.albedo_color = Color(0.20, 0.55, 0.95)
		blue_mat.emission_enabled = true
		blue_mat.emission = Color(0.20, 0.55, 0.95)
		blue_mat.emission_energy_multiplier = 0.6
		pole.material_override = blue_mat
		pole.position = origin + Vector3(0.0, 30.0, end_z)
		beacon_root.add_child(pole)
		# Orange flag on top
		var flag := MeshInstance3D.new()
		var fm := BoxMesh.new()
		fm.size = Vector3(4.0, 1.5, 0.1)
		flag.mesh = fm
		var orange_mat := StandardMaterial3D.new()
		orange_mat.albedo_color = Color(1.0, 0.55, 0.05)
		orange_mat.emission_enabled = true
		orange_mat.emission = Color(1.0, 0.55, 0.05)
		orange_mat.emission_energy_multiplier = 0.8
		flag.material_override = orange_mat
		flag.position = origin + Vector3(2.0, 58.0, end_z)
		beacon_root.add_child(flag)

# =============================================================================
# MACHINES — Extruder 3B (first machine sim, drives the 120s cascade test)
# =============================================================================
func _spawn_extruder_3b() -> void:
	var ext_scene := load("res://src/scenes/machines/Extruder3B.tscn") as PackedScene
	if not ext_scene:
		push_warning("[MainWorld] Extruder3B.tscn missing — skipping")
		return
	var ext := ext_scene.instantiate()
	add_child(ext)
	# Park 15 m forward of player spawn so they can walk to it
	var marker := find_child("PlayerSpawn", false, false) as Node3D
	if marker:
		var pos := marker.global_position
		pos.z -= 15.0
		pos.y += 0.0
		ext.global_position = pos
	print("[MainWorld] Extruder 3B placed")

# =============================================================================
# BATTERY STATION — walkie-battery charger bench in the shift-leader office
# =============================================================================
## A small bench (charger + drawer + shelf) near the extruders, where the player
## swaps walkie packs. The single charger is the social bottleneck (see
## BatteryStation.gd). Modeled procedurally so no .tscn is needed.
func _spawn_battery_station() -> void:
	var station := BatteryStation.new()
	station.name = "BatteryStation"
	# Near the extruder (which sits ~15 m -Z of spawn), offset to the side so it
	# reads as a corner office bench rather than blocking the machine.
	var anchor : Vector3 = _get_factory_anchor()
	anchor += Vector3(-6.0, 0.0, -15.0)
	add_child(station)
	station.global_position = anchor
	_build_battery_station_model(station)
	_fit_box_collider(station)   # #10 — solid bench, not just a proximity trigger
	print("[MainWorld] Battery station (walkie charger) @ %s" % str(anchor))

## #3 — the shift-leader's desk + computer in the office, beside the walkie-battery
## bench. Walk up + E opens the bale scan-log terminal (ScanLog → ShiftLeaderTerminal).
func _spawn_shift_leader_desk() -> void:
	var desk : Node3D = load("res://src/scenes/world/ShiftLeaderDesk.gd").new()
	desk.name = "ShiftLeaderDesk"
	var anchor : Vector3 = _get_factory_anchor()
	add_child(desk)
	desk.global_position = anchor + Vector3(-9.0, 0.0, -14.0)
	print("[MainWorld] Shift-leader desk (scan log) @ %s" % str(desk.global_position))

## A procedural bench: worktop, a charger block with a status LED, a drawer, and a
## shelf — just enough to read as "the charging corner". Cosmetic; the logic lives
## in BatteryStation.gd.
func _build_battery_station_model(station: Node3D) -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.42, 0.44, 0.48)
	steel.metallic = 0.5
	steel.roughness = 0.4
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.16, 0.16, 0.18)
	var led := StandardMaterial3D.new()
	led.albedo_color = Color(0.2, 0.9, 0.3)
	led.emission_enabled = true
	led.emission = Color(0.2, 0.9, 0.3)
	led.emission_energy_multiplier = 2.0

	# Worktop
	var top := MeshInstance3D.new()
	var topm := BoxMesh.new(); topm.size = Vector3(1.8, 0.08, 0.7)
	top.mesh = topm; top.material_override = steel
	top.position = Vector3(0, 0.9, 0)
	station.add_child(top)
	# Legs
	for sx in [-0.8, 0.8]:
		for sz in [-0.28, 0.28]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new(); lm.size = Vector3(0.07, 0.9, 0.07)
			leg.mesh = lm; leg.material_override = dark
			leg.position = Vector3(sx, 0.45, sz)
			station.add_child(leg)
	# Charger block (left) with status LED
	var charger := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.34, 0.22, 0.34)
	charger.mesh = cm; charger.material_override = dark
	charger.position = Vector3(-0.55, 1.05, 0)
	station.add_child(charger)
	var lamp := MeshInstance3D.new()
	var lampm := SphereMesh.new(); lampm.radius = 0.03; lampm.height = 0.06
	lamp.mesh = lampm; lamp.material_override = led
	lamp.position = Vector3(-0.55, 1.19, 0.14)
	station.add_child(lamp)
	# Fresh drawer (centre) + empty shelf (right) as labelled trays
	for data in [{"x": 0.05, "c": Color(0.2, 0.5, 0.25)}, {"x": 0.6, "c": Color(0.5, 0.35, 0.2)}]:
		var tray := MeshInstance3D.new()
		var tm := BoxMesh.new(); tm.size = Vector3(0.4, 0.06, 0.46)
		var trm := StandardMaterial3D.new(); trm.albedo_color = data["c"]
		tray.mesh = tm; tray.material_override = trm
		tray.position = Vector3(data["x"], 0.97, 0)
		station.add_child(tray)

# =============================================================================
# SERVICE STATIONS — wall outlet (electric lift) + diesel pump
# =============================================================================
## A power outlet beside the lift's parking spot, and a diesel bowser by the
## vehicle row. Both anchor to the player's actual spawn so they're reachable.
func _spawn_service_stations() -> void:
	var anchor : Vector3 = _get_factory_anchor()

	# Wall outlet — near the lift (which parks at +20 on X).
	var outlet := ServiceStation.new()
	outlet.name = "PowerOutlet"
	outlet.mode = "outlet"
	add_child(outlet)
	outlet.global_position = anchor + Vector3(22.5, 0.0, 0.0)
	_build_outlet_model(outlet)
	_fit_box_collider(outlet)   # #10 — solid post

	# Diesel pump — near the Merlo (which parks at +15 on X).
	var pump := ServiceStation.new()
	pump.name = "FuelPump"
	pump.mode = "pump"
	add_child(pump)
	pump.global_position = anchor + Vector3(13.0, 0.0, -3.0)
	_build_pump_model(pump)
	_fit_box_collider(pump)   # #10 — solid bowser
	print("[MainWorld] Service stations: outlet @ %s · pump @ %s"
		% [str(outlet.global_position), str(pump.global_position)])

func _build_outlet_model(st: Node3D) -> void:
	var box := StandardMaterial3D.new(); box.albedo_color = Color(0.85, 0.82, 0.2)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.12, 0.12, 0.13)
	# Yellow industrial outlet box on a short post.
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.12, 1.1, 0.12)
	post.mesh = pm; post.material_override = dark; post.position = Vector3(0, 0.55, 0)
	st.add_child(post)
	var bx := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.34, 0.4, 0.22)
	bx.mesh = bm; bx.material_override = box; bx.position = Vector3(0, 1.15, 0)
	st.add_child(bx)
	# Two socket dots.
	for sx in [-0.07, 0.07]:
		var s := MeshInstance3D.new()
		var sm := CylinderMesh.new(); sm.top_radius = 0.04; sm.bottom_radius = 0.04
		sm.height = 0.04; sm.radial_segments = 10
		s.mesh = sm; s.material_override = dark
		s.transform = Transform3D(Basis(Vector3(1,0,0), PI/2.0), Vector3(sx, 1.15, 0.12))
		st.add_child(s)

func _build_pump_model(st: Node3D) -> void:
	var red := StandardMaterial3D.new(); red.albedo_color = Color(0.6, 0.13, 0.1)
	var dark := StandardMaterial3D.new(); dark.albedo_color = Color(0.14, 0.14, 0.15)
	var blue := StandardMaterial3D.new(); blue.albedo_color = Color(0.2, 0.4, 0.7)
	# Diesel bowser body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.8, 1.5, 0.6)
	body.mesh = bm; body.material_override = red; body.position = Vector3(0, 0.75, 0)
	st.add_child(body)
	# A small blue AdBlue can beside it.
	var can := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.35, 0.5, 0.35)
	can.mesh = cm; can.material_override = blue; can.position = Vector3(0.6, 0.25, 0)
	st.add_child(can)
	# Hose reel.
	var reel := MeshInstance3D.new()
	var rm := CylinderMesh.new(); rm.top_radius = 0.18; rm.bottom_radius = 0.18
	rm.height = 0.12; rm.radial_segments = 14
	reel.mesh = rm; reel.material_override = dark
	reel.transform = Transform3D(Basis(Vector3(0,0,1), PI/2.0), Vector3(-0.46, 1.0, 0))
	st.add_child(reel)

# =============================================================================
# WIRE-CUTTER TOOL — the "concrete scissors" the operator carries on foot
# =============================================================================
## Drop a single WireCutter near the bale clamp's parking spot. The operator
## walks up, presses E to pick it up, then can left-click on bales to cut wires
## one at a time. The in-cab Shift+B cut was removed — this is the real flow.
# =============================================================================
# LPG CYLINDER RACK — outside near the vehicle row
# =============================================================================
func _spawn_lpg_rack() -> void:
	var rack_script := preload("res://src/scenes/world/LPGRack.gd")
	var rack := rack_script.new()
	rack.name = "LPGRack"
	add_child(rack)
	var anchor : Vector3 = _vehicle_anchor()
	# A few metres in front of the vehicle row, broadside on so the operator
	# can walk a tank straight from the rack to the forklift cab.
	rack.global_position = anchor + Vector3(-6.0, 0.0, 4.0)
	print("[MainWorld] LPGRack @ %s" % str(rack.global_position))

# =============================================================================
# FEEDER LINE — wide shredder feed belt + a bale lot + autonomous NPC feeders
# =============================================================================
## Two crewed feed stations, one per worker, each with its OWN belt + bale lot +
## personal vehicle + personal scissors & scanner:
##   • Abdullah — Line 1      — drives a Merlo
##   • Mohammed — Line 3A/3B  — drives a bale clamp
## The vehicles are fresh NPC-owned instances (tagged so the player can't board
## them). Tools ride on each worker's holster and aren't player-grabbable.
## Feeders are DISABLED until rebuilt with REAL clamp physics. The current NPCs use
## npc_carry_bale, which teleport-reparents the bale onto the clamp instead of driving
## the mast/clamp controls + force-grabbing it — exactly the "from a distance /
## pre-programmed" the operator forbids — and that childed-bale machinery is the prime
## suspect for the non-finite-transform spam. Disabling them gives a clean, stable scene
## to verify the canvas + rebuilt Line 3C, and stops the "both feeders feeding" bug.
## Rebuild plan: Mohammed feeds Line 3C via the real clamp (lower mast → close plates →
## force-grip → lift → drive → place); Abdullah only stages bales for him. (#6 + rework)
const FEEDERS_ENABLED : bool = true   # #11 — rebuilt to drive the REAL clamp controls (no teleport-grab)

func _spawn_feeder_line() -> void:
	if not FEEDERS_ENABLED:
		print("[MainWorld] Feeders DISABLED (rebuilding with real clamp physics) — clean scene.")
		return
	var base : Vector3 = _get_factory_anchor()
	# ONE intake for line 3C/6 (#30): the opzetband (feed belt) + its shredder, fed by
	# Mohammed. No bale lot or prepped bales (#32) — feedstock is built from the menu.
	_spawn_feeder_station(base + Vector3(-12.0, -0.9, 24.0), "Mohammed",
			"Line 3C/6", "res://src/scenes/vehicles/BaleClamp.tscn")

## Build one station: belt + lot + worker + the worker's personal vehicle +
## personal scissors & scanner.
func _spawn_feeder_station(station: Vector3, worker_name: String,
		line_name: String, vehicle_scene_path: String) -> FeederWorker:
	# 1) Wide feed belt.
	var belt = preload("res://src/scenes/world/ShredderFeedBelt.gd").new()
	belt.name = "ShredderFeedBelt_%s" % worker_name
	add_child(belt)
	belt.global_position = station

	# 2) The SHREDDER at the belt's discharge (3C/6). Tagged "shredder" so the belt's
	#    PLC interlock is satisfied and the opzetband runs (#30/#31). Seated on the floor.
	var shredder := PlaceableCatalog.build_node("shredder_1_3c6", false) as Node3D
	if shredder != null:
		add_child(shredder)
		shredder.add_to_group("shredder")
		var disc := (belt as Node3D).to_global(Vector3(0.0, 0.0, belt.deck_length + belt.incline_run + 2.0))
		disc.y = _floor_top_y()
		var sbb := _local_aabb(shredder)
		shredder.global_position = Vector3(disc.x, disc.y - sbb.position.y, disc.z)

	# (No bale lot / prepped bales — feedstock is built from the build menu now. #32)
	var lot_center := station + Vector3(7.0, 0.0, 0.0)

	# 3) The worker.
	var worker = preload("res://src/scenes/world/FeederWorker.gd").new()
	worker.worker_name = worker_name
	worker.assigned_line = line_name
	worker.lot_center = lot_center
	worker.lot_radius = 16.0
	add_child(worker)
	worker.global_position = station + Vector3(3.0, 1.0, 2.0)

	# 4) Their personal vehicle (NPC-owned), parked behind the worker.
	var vscene := load(vehicle_scene_path) as PackedScene
	if vscene:
		var v := vscene.instantiate() as Node3D
		add_child(v)
		v.global_position = station + Vector3(2.0, 0.5, -3.0)
		worker.assign_vehicle(v)

	# 5) Personal scissors + scanner on the holster (not player-grabbable).
	var scissors := WireCutter.new()
	add_child(scissors)
	scissors.global_position = worker.global_position
	worker.stow_personal_tool(scissors, -1.0)
	var scanner := preload("res://src/scenes/world/BarcodeScanner.gd").new()
	add_child(scanner)
	scanner.global_position = worker.global_position
	worker.stow_personal_tool(scanner, 1.0)
	worker.personal_scissors = scissors
	worker.personal_scanner = scanner

	print("[MainWorld] Feeder station: %s on %s (vehicle %s)" % \
			[worker_name, line_name, vehicle_scene_path.get_file()])
	return worker

func _spawn_wire_cutter() -> void:
	var anchor : Vector3 = _get_factory_anchor()
	# Sit it on the floor between the bale clamp (+10 X) and the bale yard (+6 X,
	# +6 Z), so it's right where the wire-cutting action happens.
	var cutter_pos := anchor + Vector3(8.0, -0.85, 3.0)
	var cutter := WireCutter.new()
	cutter.name = "WireCutter"
	add_child(cutter)
	cutter.global_position = cutter_pos
	print("[MainWorld] WireCutter (concrete scissors) @ %s" % str(cutter_pos))

	# Personal cabin props (#162): a coffee + a sandwich on the floor near the
	# scissors. Pick up with E, hotbar-swap to them, then G to place into a cab
	# slot — the coffee snaps into the cup holder, the sandwich onto a surface.
	var prop_script := preload("res://src/scenes/world/CabinProp.gd")
	var coffee : Node3D = prop_script.new()
	coffee.prop_kind = "coffee"
	add_child(coffee)
	coffee.global_position = anchor + Vector3(8.6, -0.85, 3.4)
	var sandwich : Node3D = prop_script.new()
	sandwich.prop_kind = "sandwich"
	add_child(sandwich)
	sandwich.global_position = anchor + Vector3(8.9, -0.85, 3.4)
	print("[MainWorld] Cabin props (coffee + sandwich) spawned")

	# Drop a barcode scanner half a metre to the right of the scissors. The
	# operator picks it up the same way (E), swaps to it with hotbar 1-4, and
	# left-clicks to scan a bale / container label. Right-click peels the
	# label off into a held LabelItem.
	var scanner_pos := anchor + Vector3(8.6, -0.85, 3.0)
	var scanner := BarcodeScanner.new()
	scanner.name = "BarcodeScanner"
	add_child(scanner)
	scanner.global_position = scanner_pos
	print("[MainWorld] BarcodeScanner @ %s" % str(scanner_pos))

	# Shovel (#154) — for cleaning up chute-spill floor piles into a container.
	var shovel := preload("res://src/scenes/world/ShovelTool.gd").new()
	shovel.name = "ShovelTool"
	add_child(shovel)
	shovel.global_position = anchor + Vector3(9.2, -0.85, 3.0)
	print("[MainWorld] ShovelTool @ %s" % str(shovel.global_position))

# =============================================================================
# TEST SKIP + DUMP ZONE — Wave 5 MVP
# =============================================================================
## A single PLASTIC steel skip near the test bunker so the operator can:
##   1. Forklift up to it (skip has forklift pockets at base)
##   2. Press B to grab it onto the forks
##   3. Drive to the orange-striped dump zone
##   4. Press V to release — the skip's contents are emptied at the tip area
## Skip is configured for the COARSE_FILM stream so LineFlow routes plastic
## rejects into it automatically.
func _spawn_test_skip() -> void:
	var anchor : Vector3 = _get_factory_anchor()

	# Steel skip — drop it 4 m to the +X side of the test bunker so the forklift
	# can swing around to pick it up. Anchor.y - 0.9 grounds the skip base.
	var skip := PlaceableCatalog.build_node("skip_steel", false) as Node3D
	if skip != null:
		add_child(skip)
		skip.global_position = anchor + Vector3(6.0, -0.9, 18.0)
		# Configure as a COARSE_FILM-only catcher (Stream.COARSE_FILM = 0).
		skip.set("accepted_streams", [0])
		skip.set("capacity_m3", 2.4)
		skip.set("safe_fill", 0.8)
		# Seed with some material so the operator can see the dump-empty cycle work.
		if skip.has_method("add"):
			skip.call("add", 80.0, 90.0, 0)
		print("[MainWorld] Steel skip (PLASTIC, COARSE_FILM) @ %s, fill=%.0f%%"
			% [str(skip.global_position), float(skip.call("fill_fraction")) * 100.0])

	# Dump zone — a flat orange-striped pad ~10 m further out. Tag with the
	# dump_zone group so BaseVehicle._drop_bale empties any skip released over it.
	var zone := Node3D.new()
	zone.name = "DumpZone_PLASTIC"
	zone.add_to_group("dump_zone")
	add_child(zone)
	zone.global_position = anchor + Vector3(20.0, -0.9, 18.0)
	var pad := MeshInstance3D.new()
	var pad_mat := StandardMaterial3D.new()
	pad_mat.albedo_color = Color(0.88, 0.55, 0.10)
	pad_mat.roughness = 0.85
	var pad_mesh := BoxMesh.new()
	pad_mesh.size = Vector3(6.0, 0.04, 6.0)
	pad.mesh = pad_mesh
	pad.material_override = pad_mat
	pad.position = Vector3(0.0, 0.05, 0.0)
	zone.add_child(pad)
	# A label so the operator can see it from afar.
	var lbl := Label3D.new()
	lbl.text = "DUMP — PLASTIC"
	lbl.font_size = 64
	lbl.pixel_size = 0.012
	lbl.modulate = Color(0.10, 0.10, 0.10)
	lbl.position = Vector3(0.0, 0.2, 0.0)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	zone.add_child(lbl)
	print("[MainWorld] Dump zone (PLASTIC) @ %s" % str(zone.global_position))

# =============================================================================
# TEST WASTE ZONES — Wave 5: bay + cyclone bin + IBC + floor pile
# =============================================================================
## Spawn one of each remaining waste-buffer type beside the test skip so the
## complete Wave 5 model is visible on first launch:
##   • Fines bay     — 3 black bins on castors under a fake conveyor (FINES stream)
##   • Cyclone bin   — grey steel bin sat under a virtual cyclone chute (SLUDGE)
##   • IBC tote      — caged 1 m³ for process water (EFFLUENT) with valve drain
##   • Floor pile    — bounded zone for spillover when bins overflow + no skip nearby
## Each is pre-seeded so the operator can see fills, mounds, valves immediately.
func _spawn_test_waste_zones() -> void:
	var anchor : Vector3 = _get_factory_anchor()
	var floor_y := anchor.y - 0.9

	# ── Fines bay: 3 fines_bin in a row, +Z further out from the skip ──────────
	for i in 3:
		var bin := PlaceableCatalog.build_node("fines_bin", false) as Node3D
		if bin == null:
			continue
		add_child(bin)
		bin.global_position = Vector3(anchor.x + 9.0 + float(i) * 1.1, floor_y, anchor.z + 22.0)
		bin.set("accepted_streams", [1])   # Stream.FINES
		bin.set("capacity_m3", 0.7)
		bin.set("safe_fill", 0.8)
		# Seed the LAST bin past its safe-fill so the mound visualisation is live.
		if i == 2 and bin.has_method("add"):
			bin.call("add", 180.0, 180.0, 1)   # 1 m³ of fines @180 kg/m³ → bin is full + spilling
	print("[MainWorld] Fines bay (3× FINES bins) seeded — last one over safe-fill")

	# ── Cyclone bin: grey steel cube under a virtual cyclone discharge (SLUDGE) ─
	var cb := PlaceableCatalog.build_node("cyclone_bin", false) as Node3D
	if cb != null:
		add_child(cb)
		cb.global_position = Vector3(anchor.x + 13.0, floor_y, anchor.z + 25.0)
		cb.set("accepted_streams", [4])    # Stream.SLUDGE
		cb.set("capacity_m3", 1.3)
		cb.set("safe_fill", 0.85)
		cb.set("mound_color", Color(0.32, 0.30, 0.26))
		# Pre-seed so a small visible mound appears on top of the bin.
		if cb.has_method("add"):
			cb.call("add", 1200.0, 800.0, 4)
		print("[MainWorld] Cyclone bin (SLUDGE) @ %s, fill=%.0f%%"
			% [str(cb.global_position), float(cb.call("fill_fraction")) * 100.0])

	# ── IBC tote: caged 1 m³ for process water (EFFLUENT) with on-foot valve ───
	var ibc := PlaceableCatalog.build_node("ibc_tote", false) as Node3D
	if ibc != null:
		add_child(ibc)
		ibc.global_position = Vector3(anchor.x + 17.0, floor_y, anchor.z + 25.0)
		ibc.set("accepted_streams", [5])   # Stream.EFFLUENT
		ibc.set("capacity_m3", 1.0)
		ibc.set("safe_fill", 0.9)
		ibc.set("movable", false)
		ibc.set("fluid_valve", true)        # operator opens on foot with E
		if ibc.has_method("add"):
			ibc.call("add", 720.0, 1000.0, 5)
		print("[MainWorld] IBC tote (EFFLUENT, valve-drain) @ %s, fill=%.0f%%"
			% [str(ibc.global_position), float(ibc.call("fill_fraction")) * 100.0])

	# ── Floor pile: a bounded zone for bin-overflow spillover. Sits beside the
	#    skip's dump zone so it's where excess material would actually end up. ──
	var pile_script := load("res://src/sim/FloorPile.gd")
	if pile_script != null:
		var pile = pile_script.new()
		pile.name = "FloorPile_PLASTIC"
		add_child(pile)
		pile.global_position = Vector3(anchor.x + 12.0, floor_y, anchor.z + 14.0)
		pile.max_radius_m = 3.0
		pile.pile_color = Color(0.48, 0.45, 0.38)
		# Seed a visible mound so the operator can see what it looks like.
		pile.add(220.0, 90.0)
		print("[MainWorld] Floor pile @ %s seeded — visible cone overflow"
			% str(pile.global_position))

# =============================================================================
# HUD
# =============================================================================
func _spawn_hud() -> void:
	var hud_scene := load("res://src/scenes/hud/HUD.tscn") as PackedScene
	if not hud_scene:
		push_error("[MainWorld] HUD.tscn not found")
		return
	hud = hud_scene.instantiate() as CanvasLayer
	add_child(hud)
	print("[MainWorld] HUD instantiated")

# =============================================================================
# SHIFT START / RESUME
# =============================================================================
func _start_or_resume_shift() -> void:
	## MainWorld is the single authority for starting or resuming the shift.
	## ShiftClock._ready() deliberately does NOT self-load to avoid the sibling
	## ordering race (ShiftClock is child[0]; GameState is child[1]).
	if not shift_clock:
		return
	if game_state and game_state.has_shift_data():
		shift_clock.load_shift_state()
		shift_clock.resume_shift()
		print("[MainWorld] Shift resumed at %s" % shift_clock.get_time_string())
	else:
		shift_clock.start_shift()
		print("[MainWorld] New shift started")

# =============================================================================
# SAVE / QUIT
# =============================================================================
func save_game() -> void:
	if player and game_state:
		game_state.save_player_state({
			"x":     player.global_position.x,
			"y":     player.global_position.y,
			"z":     player.global_position.z,
			"rot_y": player.rotation.y,
		})
	if shift_clock:
		shift_clock.save_shift_state()
	if game_state:
		game_state.save_game()
	print("[MainWorld] Game saved")

func save_and_quit() -> void:
	save_game()
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

# =============================================================================
# AUTOSAVE (every 60 s of real play time)
# =============================================================================
func _setup_autosave() -> void:
	var timer := Timer.new()
	timer.name       = "AutosaveTimer"
	timer.wait_time  = 60.0
	timer.autostart  = true
	timer.one_shot   = false
	timer.timeout.connect(_on_autosave)
	add_child(timer)

func _on_autosave() -> void:
	save_game()
	print("[MainWorld] Autosave")

# =============================================================================

# =============================================================================
# FLOOR GENERATION
# =============================================================================
var _floor_min_y_cache: float = -9.0

func _generate_floor_from_shell(shell_mesh: MeshInstance3D) -> void:
	var mesh = shell_mesh.mesh as ArrayMesh
	if not mesh:
		return

	var shell_xf = shell_mesh.global_transform
	var xz_to_y = {}
	var min_y = 1000000.0

	# Extract vertices
	for s in range(mesh.get_surface_count()):
		var arr = mesh.surface_get_arrays(s)
		var verts = arr[Mesh.ARRAY_VERTEX] as PackedVector3Array
		for v in verts:
			var world_v = shell_xf * v
			var xz = Vector2(round(world_v.x * 10.0) / 10.0, round(world_v.z * 10.0) / 10.0)
			if not xz_to_y.has(xz) or world_v.y < xz_to_y[xz]:
				xz_to_y[xz] = world_v.y
			if world_v.y < min_y:
				min_y = world_v.y

	# Filter for bottom corners
	var bottom_pts = PackedVector2Array()
	var bottom_ys = PackedFloat32Array()
	for xz in xz_to_y.keys():
		var y = xz_to_y[xz]
		if y <= min_y + 10.0:
			bottom_pts.push_back(xz)
			bottom_ys.push_back(y)

	# Add 4 large bounding corners to extend the floor
	var extents = [
		Vector2(-2000, -2000), Vector2(2000, -2000),
		Vector2(2000, 2000), Vector2(-2000, 2000)
	]
	for ext in extents:
		bottom_pts.push_back(ext)
		bottom_ys.push_back(min_y)

	var floor_node = find_child("TempFloor", true, false) as StaticBody3D
	if not floor_node:
		return

	var floor_inv = floor_node.global_transform.affine_inverse()
	var local_pts = PackedVector2Array()
	var local_ys = PackedFloat32Array()
	for i in range(bottom_pts.size()):
		var xz = bottom_pts[i]
		var y = bottom_ys[i]
		var local_v = floor_inv * Vector3(xz.x, y, xz.y)
		local_pts.push_back(Vector2(local_v.x, local_v.z))
		local_ys.push_back(local_v.y)

	var delaunay = Geometry2D.triangulate_delaunay(local_pts)

	var st = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for i in range(0, delaunay.size(), 3):
		var i1 = delaunay[i]
		var i2 = delaunay[i+1]
		var i3 = delaunay[i+2]

		var p1 = Vector3(local_pts[i1].x, local_ys[i1], local_pts[i1].y)
		var p2 = Vector3(local_pts[i2].x, local_ys[i2], local_pts[i2].y)
		var p3 = Vector3(local_pts[i3].x, local_ys[i3], local_pts[i3].y)

		var normal = (p2 - p1).cross(p3 - p1)
		if normal.y < 0:
			st.add_vertex(p1)
			st.add_vertex(p3)
			st.add_vertex(p2)
		else:
			st.add_vertex(p1)
			st.add_vertex(p2)
			st.add_vertex(p3)

	st.generate_normals()
	var new_mesh = st.commit()

	var mi = floor_node.find_child("MeshInstance3D", false, false) as MeshInstance3D
	if mi:
		mi.mesh = new_mesh

	var cs = floor_node.find_child("CollisionShape3D", false, false) as CollisionShape3D
	if cs:
		var shape = ConcavePolygonShape3D.new()
		shape.set_faces(new_mesh.get_faces())
		cs.shape = shape

	_floor_min_y_cache = min_y

# =============================================================================
# Helpers
# =============================================================================

func get_npc(npc_id: String) -> Node:
	return npcs.get(npc_id, null)

func get_all_npcs() -> Array:
	return npcs.values()
