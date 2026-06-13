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
var container_guides: ContainerGuideManager   # holographic catch-container placement guides (#85)
var crew_manager    : CrewManager
var scada           : Node          # ScadaDashboard (ISA-101 overlay)
var npcs            : Dictionary = {}

# Where the player actually spawned this run (marker OR resumed save position).
# The forklift parks 3 m from here so it's always within reach on spawn.
var _player_spawn_pos : Vector3 = Vector3.ZERO

# Setup mode state
var is_setup_mode : bool = false
var setup_overlay : CanvasLayer = null

# ── NPC catalogue ─────────────────────────────────────────────────────────────
## #133 — operator spec. Per-NPC appearance overrides:
##   hair  : "short" (default), "mid", "bald"
##   cap   : if true, a dark-blue work cap replaces the hair on top of the head
##   beard : "none" (default), "thin", "thick"
##   hair_color: optional Color override (defaults to a variant-driven choice)
const NPC_DATA: Dictionary = {
	"romain":     {"name": "Romain",     "role": "shift_leader",       "color": Color.CYAN,             "appearance": {},
		"car": "res://src/scenes/vehicles/cars/HyundaiI20_2010.tscn"},
	"vincent":    {"name": "Vincent",    "role": "asst_shift_leader",  "color": Color.CORNFLOWER_BLUE,  "appearance": {},
		"car": "res://src/scenes/vehicles/cars/VolvoV40Placeholder.tscn"},   # PLACEHOLDER: black Astra-as-Volvo until real GLB lands
	"pascal":     {"name": "Pascal",     "role": "extruder_op",        "color": Color.YELLOW,           "appearance": {"hair": "bald"},
		"car": "res://src/scenes/vehicles/cars/FordStreetka.tscn"},   # black Streetka — Ford Ka GLB Y-squished + repainted
	"kevin":      {"name": "Kevin",      "role": "extruder_op",        "color": Color.GREEN,            "appearance": {"cap": true},
		"car": ""},   # not assigned a car yet
	"emrah":      {"name": "Emrah",      "role": "all_rounder",        "color": Color.WHITE,            "appearance": {"beard": "thin"},
		"car": "res://src/scenes/vehicles/cars/AudiA3Sportback.tscn"},
	"yassine":    {"name": "Yassine",    "role": "transitional",       "color": Color.LIGHT_GRAY,       "appearance": {},
		"car": "passenger:player"},   # rides shotgun in the player's Swift
	"abdellilah": {"name": "Abdellilah", "role": "permanent_feeder",   "color": Color.ORANGE,           "appearance": {"cap": true},
		"car": "res://src/scenes/vehicles/cars/FordKa2003.tscn"},
	"mohammed":   {"name": "Mohammed",   "role": "permanent_feeder",   "color": Color.TOMATO,           "appearance": {"beard": "thick", "hair": "mid", "hair_color": Color(0.10, 0.07, 0.05)},
		"car": "res://src/scenes/vehicles/cars/VWGolfMk6.tscn"},
	"peter":      {"name": "Peter",      "role": "production_manager", "color": Color.MEDIUM_ORCHID,    "appearance": {},
		"car": "res://src/scenes/vehicles/cars/BMWX1Placeholder.tscn"},   # PLACEHOLDER: white AClass-as-BMW until real GLB lands
}
# #155 — Player's car. Swift goes to the player; Yasin (yassine) rides shotgun.
const PLAYER_CAR_SCENE : String = "res://src/scenes/vehicles/cars/SuzukiSwiftGLX.tscn"

# ── #166 Pre-shift arrival sequence ──────────────────────────────────────────
# A fresh game starts PRE_SHIFT_WINDOW_S game-seconds before the bell so the
# arrival sequence has room to play out. ShiftClock seeds to -1800 and ticks
# up to 0; the bell fires shift_started again at that moment.
const PRE_SHIFT_WINDOW_S : float = 30.0 * 60.0   # 30 minutes

# Per-NPC schedule, expressed in seconds RELATIVE to the bell (negative = before).
# `pre_changed` = arrives already in PPE/boots (skips dressing-room loop).
# `dress_time_s` = how long they spend in the locker room (-1 → use random
#                  uniform 2..6 min default).
# `smokes_at_s`  = if set, NPC stands at SMOKE_SPOT smoking from that time until
#                  3 min later. Only Pascal has this.
# Order corresponds to NPC_DATA keys above. Unlisted NPCs default to T-15 +
# random-dressing (so Mohammed / Peter / Vincent fallback work cleanly).
const PRE_SHIFT_SCHEDULE : Dictionary = {
	"emrah":      {"arrives_at_s": -35.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
	"pascal":     {"arrives_at_s": -40.0 * 60.0, "pre_changed": true,  "dress_time_s": 0.0, "smokes_at_s": -33.0 * 60.0},
	"vincent":    {"arrives_at_s": -40.0 * 60.0, "pre_changed": true,  "dress_time_s": 0.0},
	"romain":     {"arrives_at_s": -25.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
	"yassine":    {"arrives_at_s": -20.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0, "rides_with": "player"},
	"abdellilah": {"arrives_at_s": -17.0 * 60.0, "pre_changed": false, "dress_time_s":  8.0 * 60.0},
	"kevin":      {"arrives_at_s": -10.0 * 60.0, "pre_changed": false, "dress_time_s": -1.0},
}

# Placeholder dressing room + smoke spot — operator can refine via WorldSetup
# markers later. For now we anchor relative to the player spawn so the loop
# works against the same building shell as everything else (#34 lesson).
const DRESSING_ROOM_OFFSET : Vector3 = Vector3(-8.0, 0.0,  6.0)   # inside, near canteen
const CANTEEN_OFFSET       : Vector3 = Vector3( 0.0, 0.0, 25.0)   # matches MainWorld:771 fallback
const SMOKE_SPOT_OFFSET    : Vector3 = Vector3( 4.0, 0.0,-12.0)   # outside, near parking

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
	# Road + parking must come AFTER the player spawn so we anchor them relative
	# to `_player_spawn_pos` instead of world origin. The building shell is
	# re-anchored from RD coords at runtime — world origin is meaningless;
	# only the player spawn is a known fixed point in the operating frame.
	_spawn_road_and_parking()
	# Phase 1 of #145 — bake a NavigationRegion3D from the interior floor +
	# exterior ground so NPCs (NavigationAgent3D) can route around obstacles
	# instead of walking in straight lines through machines and walls.
	_spawn_navigation_region()
	_spawn_operator_context()
	_spawn_build_mode()
	_spawn_line_flow()
	_spawn_container_guides()
	_spawn_npcs()
	# #155 — spawn the shift's cars + put the player in their Swift + seat Yasin.
	# MUST come after _spawn_npcs (needs npcs["yassine"] to exist to seat as
	# passenger) AND _spawn_operator_context (needs operator_context to board the
	# player into the Swift). Was previously called at line ~105 BEFORE both —
	# Yasin silently never got seated. Audit-caught (#157 follow-up).
	_spawn_shift_cars_and_player_drive_in()
	_spawn_hud()
	# Performance overlay + auto-logger (F3 toggles; logs a [PERF] snapshot every
	# 5 s so the lag can be diagnosed straight from the console).
	var perf: Node = load("res://src/scenes/hud/PerfHud.gd").new()
	perf.name = "PerfHud"
	add_child(perf)
	# ISA-101 SCADA dashboard (muted-grey nominal, colour only on alarm; logs
	# micro-stops). Machines push set_state/set_param to it.
	scada = load("res://src/scenes/hud/ScadaDashboard.gd").new()
	scada.name = "ScadaDashboard"
	add_child(scada)
	# #52 — hand the dashboard to LineFlow so its tick pushes live line state +
	# process params (amps / quality / melt temp / MFI / air pressure). LineFlow was
	# spawned above by _spawn_line_flow(); guarded so it's a no-op if absent.
	if line_flow and line_flow.has_method("set_scada"):
		line_flow.set_scada(scada)

	if game_state and game_state.is_new_save:
		# If the user has already run "Setup World Layout" from the main menu,
		# skip the in-world walk-and-press-ENTER ritual and use those markers.
		if WorldLayout.is_configured():
			if game_state.factory_center == Vector3.ZERO:
				game_state.factory_center = WorldLayout.factory_center
			game_state.is_new_save = false
			save_game()
			_spawn_world_items()
		else:
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
	# Vehicles ALWAYS come from WorldLayout (or fall back to defaults if empty).
	_spawn_forklift()
	_spawn_bale_clamp()
	_spawn_merlo()
	_spawn_mast_lift()

	# When the user has configured a world via WorldSetup, treat it as
	# authoritative: skip ALL legacy hardcoded clutter (utility props, feeder
	# line, demo pipeline, default crew posts). Otherwise spawn the legacy
	# layout for backward-compat / first-run experience.
	var layout_authoritative := WorldLayout.is_configured()

	if not layout_authoritative:
		_spawn_battery_station()   # walkie-battery charger in the shift-leader office
		_spawn_shift_leader_desk() # shift-leader PC: the bale scan log (#3)
		_spawn_service_stations()  # wall outlet (electric lift) + diesel pump
		_spawn_wire_cutter()       # concrete-scissors tool the player picks up on foot
		_spawn_lpg_rack()          # outdoor LPG cylinder rack — full below, empty above
		if not CLEAN_CANVAS:
			_spawn_extruder_3b()
			_spawn_bale_yard()
			_spawn_test_bunker()
			_spawn_test_skip()
			_spawn_test_waste_zones()
		_spawn_feeder_line()
	else:
		print("[MainWorld] WorldLayout is authoritative — skipping legacy utility/demo spawns")
		_spawn_bale_yards_from_layout()

	# Final LineFlow discovery pass — AFTER every machine exists.
	if line_flow:
		line_flow.rebuild()
	# Crew manager ALWAYS spawns (even with an authoritative layout). It posts
	# the 9 workers to whatever LineFlow machines exist (free-wander if none),
	# and — critically — the HUD crew-assignment panel (C / Numpad-.) bails out
	# when crew_manager is null, so skipping it broke that menu entirely.
	_spawn_crew_manager()
	_start_or_resume_shift()
	_setup_autosave()

	# WorldEnvironment + sun are now in the tree — push saved graphics prefs
	# (SSAO / SDFGI / fog / brightness / shadow distance) onto them.
	SettingsManager.refresh_environment()
	_apply_textures()
	_spawn_overhead_lights()
	_spawn_plant_audio()

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
	# Use the SOLIDIFIED shell (real wall thickness, welded, closed seams) when it
	# exists — kills the zero-thickness light leaks. Built by tools/solidify_building.gd;
	# falls back to the raw thin shell if absent.
	# #105 — collision must come from the THIN mesh, NOT the solid. The solid has
	# 0.30 m wall thickness baked in (inner + outer surfaces), which traps the
	# player capsule between the two faces ("stuck in wall on un-modified walls").
	# WallOpenings does its own collision regen, sourced from a separate thin
	# mesh below; we DON'T call create_trimesh_collision() here anymore so we
	# don't add a thick collider that WallOpenings then has to fight.
	if ResourceLoader.exists("res://assets/models/CeDo_building_solid.res"):
		var solid = load("res://assets/models/CeDo_building_solid.res")
		if solid is Mesh:
			mesh_instance.mesh = solid
			print("[MainWorld] Using solidified building shell (visual)")
	print("[MainWorld] Building collision will be generated by WallOpenings (thin mesh)")
	_generate_floor_from_shell(mesh_instance)
	print("[MainWorld] Dynamic floor generated from building corners")

# Caches the building mesh so doors/windows can carve real, walkable openings
# at runtime (never touches the source .obj). Must exist BEFORE BuildMode loads
# its layout, since saved doors/windows re-cut their holes on load.
# =============================================================================
# PROCEDURAL TEXTURES  (no image assets exist — surface detail is generated)
# =============================================================================
func _apply_textures() -> void:
	# Floor — worn concrete. Photo-calibrated from assets/reference_photos/
	# building/hal_0_*.png + yellow_ladders_railings_lines.png. The real CeDo
	# floor is a warm-grey-brown worn polished concrete, NOT a neutral mid-grey;
	# the previous (0.42, 0.41, 0.39) was too lifted and too neutral.
	var floor_node := find_child("TempFloor", true, false)
	if floor_node:
		var fm := floor_node.find_child("MeshInstance3D", false, false) as MeshInstance3D
		if fm:
			# Photo-extracted hall-floor texture (assets/textures/floor/) when
			# local assets are present; procedural noise otherwise.
			var floor_mat := MaterialPalette.mat_concrete_worn()
			if floor_mat.albedo_texture == null:
				floor_mat = _industrial_mat(Color(0.34, 0.32, 0.30), 0.55, 0.92, false)
			fm.material_override = floor_mat
	# Building shell — painted concrete/steel. Use a SIMPLE flat material rather
	# than the triplanar-noise one: the noise normal-map combined with the .obj's
	# mixed winding was making some wall/roof faces render black on one side.
	# WallOpenings now regenerates normals from winding AND flips inward-facing
	# tris (see WallOpenings._fix_winding_outward), so the shell can use a clean
	# matte pass without the noise normal-map trickery.
	# Calibrated cream-grey from _e_kast.png (background wall) — the real walls
	# are not pure-white painted, they're a dusty cream from years of service.
	var shell := find_child("ShellMesh", true, false) as MeshInstance3D
	if shell:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.70, 0.68, 0.63)
		sm.roughness    = 0.94          # matte — kills bright specular hot-spots
		sm.metallic     = 0.0
		# CULL_DISABLED so back faces still render (single-sided walls would
		# disappear from one side otherwise). Godot auto-flips the normal on
		# the back face, so both sides light correctly.
		sm.cull_mode    = BaseMaterial3D.CULL_DISABLED
		# #111 — the solidified .obj now emits `usemtl shell` and `usemtl posts`
		# as separate surfaces (surface 0 = walls/roof, surface 1 = wooden
		# V-beams). If the imported mesh has multiple surfaces, override per
		# surface so the V-beams pick up the photo-calibrated timber material
		# instead of inheriting the cream shell paint. Falls back to
		# material_override on a single-surface mesh (old .obj).
		var surface_count : int = 0
		if shell.mesh != null:
			surface_count = shell.mesh.get_surface_count()
		if surface_count >= 2:
			shell.material_override = null
			shell.set_surface_override_material(0, sm)
			var timber := MaterialPalette.mat_timber_dark()
			# Apply CULL_DISABLED to timber too — posts are baked as proper
			# 6-sided boxes by solidify_building.py, but the photo material is
			# triplanar with a normal map, and CULL_DISABLED matches the shell
			# behaviour so lighting reads identically across both surfaces.
			timber.cull_mode = BaseMaterial3D.CULL_DISABLED
			shell.set_surface_override_material(1, timber)
		else:
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
	# #105 — when the visible shell is the pre-solid .res, load the THIN .obj
	# separately and hand it to WallOpenings as the COLLISION source. The thin
	# mesh has single-face walls so the player capsule can't wedge between an
	# inner and outer surface, and the WallOpenings carve still drops walkable
	# holes through the thin collision when gates / doors / windows are placed.
	# Visual stays solid for no-light-leak.
	var thin_source : Mesh = null
	if ResourceLoader.exists("res://assets/models/CeDo_building_solid.res"):
		# Disable WallOpenings's own solidify — the visible shell is already thick.
		wall_openings.solidify_enabled = false
		thin_source = load(building_shell_path) as Mesh
		if thin_source != null:
			print("[MainWorld] Pre-solid shell active; using thin .obj for collision")
		else:
			push_warning("[MainWorld] Thin .obj source not loaded; collision will be from solid mesh")
	add_child(wall_openings)
	wall_openings.setup(shell, thin_source)
	print("[MainWorld] WallOpenings ready")

# =============================================================================
# PLANT AUDIO — #60
# =============================================================================
## Spawn the PlantAudio system that streams each tagged clip from
## assets/audio/audio_layout.json into a 3D AudioStreamPlayer at its recorded
## position. See src/scenes/world/PlantAudio.gd for the full design.
func _spawn_plant_audio() -> void:
	var pa : PlantAudio = preload("res://src/scenes/world/PlantAudio.gd").new()
	pa.name = "PlantAudio"
	add_child(pa)

# =============================================================================
# OVERHEAD LIGHTS — #107
# =============================================================================
## Hang industrial-style bay lights from the ceiling in a 5×5 grid centred on
## the player spawn so the production floor is no longer pitch-dark. Each
## fixture has a visible white bar mesh (emissive so you can see it), a small
## dark housing above, and an OmniLight3D with warm-white tint and 25 m range.
## The flashlight is still available for inspecting machinery up close, but
## you can now actually see the room without it.
func _spawn_overhead_lights() -> void:
	var root := Node3D.new()
	root.name = "OverheadLights"
	add_child(root)
	var floor_y : float = _floor_top_y()
	var ceil_y : float = floor_y + 8.0           # ~8 m bay-light height
	# Anchor on the BUILDING's centre, not the player's spawn — the PlayerSpawn
	# marker in MainWorld.tscn is hardcoded at (-263, 133), but the building
	# shell is at scene origin (its tscn translation shifts the RD-coord mesh
	# down). With the lights anchored on the player they ended up over the bale
	# yard / parking lot 250 m away from the actual factory. Now they grid out
	# from the SHELL's XZ AABB centre and clip to that AABB so every kept
	# fixture lands inside the building.
	var info := _building_center_and_footprint()
	var bcenter : Vector3 = info["center"]
	var footprint : PackedVector2Array = info["footprint"]
	var origin : Vector3 = bcenter
	# Fall back to player spawn if the shell isn't resolvable (test scene,
	# missing model) so a dev still sees lights.
	if footprint.size() < 3:
		push_warning("[MainWorld] No building footprint — bay lights anchored on player")
		origin = _player_spawn_pos
	var spacing : float = 18.0                    # tighter grid → more lights INSIDE the building
	var n : int = 7                                # 7×7 = 49 candidates, clipped to footprint
	var n_kept : int = 0
	var n_culled : int = 0
	for ix in range(n):
		for iz in range(n):
			var fx : float = (float(ix) - float(n - 1) * 0.5) * spacing
			var fz : float = (float(iz) - float(n - 1) * 0.5) * spacing
			var px : float = origin.x + fx
			var pz : float = origin.z + fz
			if footprint.size() >= 3:
				if not Geometry2D.is_point_in_polygon(Vector2(px, pz), footprint):
					n_culled += 1
					continue
			_build_overhead_fixture(root, Vector3(px, ceil_y, pz))
			n_kept += 1
	print("[MainWorld] Overhead bay lights: %d kept at (%.1f,%.1f), %d culled (outside building AABB)" \
		% [n_kept, origin.x, origin.z, n_culled])

## Look up the building shell via its known scene path AND compute both its
## XZ centre and a footprint polygon (AABB rectangle) in one pass. Used by
## _spawn_overhead_lights — find_child("ShellMesh", true, false) returned
## empty in the last test, so we use the explicit path BuildingShell/ShellMesh
## which we know exists in MainWorld.tscn.
func _building_center_and_footprint() -> Dictionary:
	var shell := get_node_or_null("BuildingShell/ShellMesh") as MeshInstance3D
	if shell == null:
		shell = find_child("ShellMesh", true, false) as MeshInstance3D
	if shell == null or shell.mesh == null:
		return {"center": Vector3.ZERO, "footprint": PackedVector2Array()}
	var aabb : AABB = shell.global_transform * shell.mesh.get_aabb()
	var centre := aabb.position + aabb.size * 0.5
	var x0 := aabb.position.x; var x1 := x0 + aabb.size.x
	var z0 := aabb.position.z; var z1 := z0 + aabb.size.z
	return {
		"center": centre,
		"footprint": PackedVector2Array([
			Vector2(x0, z0), Vector2(x1, z0),
			Vector2(x1, z1), Vector2(x0, z1)])
	}

func _build_overhead_fixture(parent: Node3D, pos: Vector3) -> void:
	var fixture := Node3D.new()
	fixture.position = pos
	parent.add_child(fixture)
	# Visible white emissive tube (the bay-light bar itself).
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(1.6, 0.10, 0.32)
	bar.mesh = bb
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.96, 0.97, 0.92)
	bar_mat.emission_enabled = true
	bar_mat.emission = Color(1.0, 0.95, 0.84)
	bar_mat.emission_energy_multiplier = 2.5
	bar.material_override = bar_mat
	fixture.add_child(bar)
	# Dark steel housing above the bar so you see it as a fixture, not a floating tube.
	var hous := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(1.8, 0.16, 0.46)
	hous.mesh = hb
	hous.position = Vector3(0.0, 0.13, 0.0)
	var hous_mat := StandardMaterial3D.new()
	hous_mat.albedo_color = Color(0.22, 0.22, 0.24)
	hous_mat.metallic = 0.4
	hous_mat.roughness = 0.6
	hous.material_override = hous_mat
	fixture.add_child(hous)
	# The actual omnidirectional light.
	var light := OmniLight3D.new()
	light.light_energy = 2.2
	light.omni_range = 25.0
	light.light_color = Color(1.0, 0.96, 0.86)
	light.position = Vector3(0.0, -0.05, 0.0)
	fixture.add_child(light)

# =============================================================================
# PLAYER
# =============================================================================
## Recursively set `layers` on every MeshInstance3D under `root`. Used to put
## the player's own Humanoid body on render layer 2 so the first-person camera
## (mask drops layer 2) hides it, while wardrobe-mirror cameras see it.
func _set_body_render_layer(root: Node, layer_mask: int) -> void:
	if root is MeshInstance3D:
		(root as MeshInstance3D).layers = layer_mask
	for c in root.get_children():
		_set_body_render_layer(c, layer_mask)

func _spawn_player() -> void:
	## Tries saved position first; falls back to the PlayerSpawn marker.
	## Saved position is the actual capsule centre (no +1.0 lift needed on load).

	var spawn_pos  : Vector3 = Vector3.ZERO
	var spawn_rot_y: float   = 0.0
	var from_save  : bool    = false

	if game_state:
		var saved := game_state.load_player_state()
		if saved.has("x"):
			var sp := Vector3(saved["x"], saved["y"], saved["z"])
			# Stale-save guard: if the saved capsule sits more than 100 m from
			# the current world layout's spawn marker AND from world origin
			# (where the building is shifted to), the save was taken in a
			# previous, differently-anchored world (e.g. building was at RD
			# coords). Ignore it so we land on the actual floor near the
			# building instead of in an empty field next to lights and crew
			# anchored at origin.
			var dist_to_marker : float = Vector2(sp.x - WorldLayout.player_spawn.x,
				sp.z - WorldLayout.player_spawn.z).length()
			var dist_to_origin : float = Vector2(sp.x, sp.z).length()
			if dist_to_marker > 100.0 and dist_to_origin > 100.0:
				print("[MainWorld] Stale saved player pos (%.0f,%.0f) — using marker instead"
					% [sp.x, sp.z])
			else:
				spawn_pos   = sp
				spawn_rot_y = saved.get("rot_y", 0.0)
				from_save   = true

	if not from_save:
		# Marker XZ is meaningful (where the operator's feet should land);
		# marker Y is NOT — WorldSetup places markers on a y=0 click plane
		# regardless of where the actual floor is. Override Y with the detected
		# floor + capsule half-height so the player lands ON the floor.
		var floor_top := _floor_top_y()
		if WorldLayout.player_spawn != Vector3.ZERO:
			var ps := WorldLayout.player_spawn
			spawn_pos = Vector3(ps.x, floor_top + 1.0, ps.z)
		else:
			var marker := find_child("PlayerSpawn", false, false) as Node3D
			if marker:
				spawn_pos = Vector3(marker.global_position.x, floor_top + 1.0, marker.global_position.z)
			else:
				spawn_pos = Vector3(0.0, floor_top + 1.0, 0.0)

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
	# #152 — Render layer 1 = world (default for everything), layer 2 = "self"
	# (the player's own visible body). The first-person camera ignores layer 2
	# so the operator doesn't see their own torso poking up into the FOV; the
	# wardrobe mirror (#153) and any third-person camera include layer 2 to
	# see the body.
	camera.cull_mask &= ~(1 << 1)   # drop layer 2
	head.add_child(camera)

	var col := CollisionShape3D.new()
	col.name = "Collision"          # PlayerController resizes this for crouch/prone
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape  = cap
	player.add_child(col)

	# #152 — Visible Humanoid body so other cameras (wardrobe mirror, future
	# third-person) see the operator wearing what they picked in #153. Loaded
	# from GameState.player_appearance (defaults = orange hi-vis + dark blue
	# pants, short hair, no beard, no cap — fresh-hire look).
	var appearance : Dictionary = game_state.player_appearance if game_state else {}
	var shirt : Color = Color(0.96, 0.45, 0.12)   # hi-vis orange default
	if appearance.has("shirt_color"):
		var sc = appearance["shirt_color"]
		if sc is Color: shirt = sc
		elif sc is Dictionary and sc.has("r"):
			shirt = Color(float(sc["r"]), float(sc["g"]), float(sc["b"]))
	var humanoid_script = load("res://src/scenes/world/Humanoid.gd")
	if humanoid_script:
		var body : Node3D = humanoid_script.build(shirt, 0, appearance)
		body.name = "PlayerBody"
		# Tag every MeshInstance3D in the body subtree onto render layer 2
		# (LAYER 1 = world, LAYER 2 = self) so the first-person camera ignores
		# it but the wardrobe mirror sees it.
		_set_body_render_layer(body, 1 << 1)
		player.add_child(body)

	add_child(player)
	player.global_position = spawn_pos
	if from_save:
		player.rotation.y = spawn_rot_y

	# Remember where the player actually ended up so the forklift can park right
	# beside them — whether they spawned at the marker or resumed a save 500 m away.
	_player_spawn_pos = player.global_position

	print("[MainWorld] Player spawned at %s%s" \
		% [player.global_position, " (resumed)" if from_save else ""])
	# Restore the saved free-cam pose if there is one. Defer one frame so PlayerController._ready
	# has built its CameraRig before we hand it the saved state. (#freecam)
	if from_save and game_state:
		var saved_player := game_state.load_player_state()
		var fc = saved_player.get("freecam", null)
		if fc != null:
			call_deferred("_restore_freecam_state", fc)

## Walk to the player's CameraRig (built lazily by PlayerController._ready).
func _freecam_rig() -> Node:
	if player == null:
		return null
	return player.find_child("CameraRig", true, false)

func _restore_freecam_state(d: Dictionary) -> void:
	var rig := _freecam_rig()
	if rig != null and rig.has_method("load_freecam_state"):
		rig.call("load_freecam_state", d)

func freecam_save_now() -> void:
	# Trigger an immediate save when the operator presses F5 — the rig's current pose
	# goes in alongside the player position. Also prints a small notice on the banner.
	save_game()
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", "[F5] Free-cam position saved")

func _get_factory_anchor() -> Vector3:
	# Take XZ from whichever source we have (factory_center / player spawn /
	# scene marker), but ALWAYS pin Y to the detected operating floor — the
	# Y component of those sources is set by WorldSetup's y=0 click plane,
	# not the actual building floor, so trusting it leaves vehicles in the air
	# (or buried). _on_floor() does the override.
	if game_state and game_state.factory_center != Vector3.ZERO:
		return _on_floor(game_state.factory_center)
	if _player_spawn_pos != Vector3.ZERO:
		return _on_floor(_player_spawn_pos)
	var marker := find_child("PlayerSpawn", false, false) as Node3D
	if marker:
		return _on_floor(marker.global_position)
	return _on_floor(Vector3.ZERO)

## Force a position onto the detected operating-floor Y plane (with an optional
## lift so wheels / capsule bases / machine bottoms can settle without clipping).
## Use everywhere a saved layout (WorldLayout / GameState) supplies an XZ but a
## meaningless Y.
func _on_floor(pos: Vector3, lift: float = 0.0) -> Vector3:
	return Vector3(pos.x, _floor_top_y() + lift, pos.z)

# =============================================================================
# NPCs
# =============================================================================
func _spawn_npcs() -> void:
	# Crew now spawns in a 2–20 m random ring around the PLAYER SPAWN marker, on
	# the OUTSIDE of the building (rejected if the candidate point lands inside
	# the shell's XZ AABB). The old NPCSpawnPoints markers / fallback dictionary
	# placed workers at hardcoded coordinates that didn't follow the player_spawn
	# the user calibrated in WorldSetup; in practice they appeared in the wrong
	# spot (often inside the building). Now they cluster naturally near where the
	# player starts the shift.
	var npc_script := load("res://src/scenes/world/NPC.gd")
	var humanoid_script := load("res://src/scenes/world/Humanoid.gd")
	var npc_variant := 0

	# Random-ring anchor — the PLAYER's actual spawn this run (set in
	# _spawn_player). Was WorldLayout.player_spawn, but that's the WorldSetup
	# marker, not where the player actually lands; a stale save or building
	# shift can put the actual player metres away from the marker.
	var anchor : Vector3 = _player_spawn_pos
	# Building's XZ AABB so we can reject candidates that land INSIDE the shell.
	var shell := find_child("ShellMesh", true, false) as MeshInstance3D
	var bb_min := Vector2(INF, INF); var bb_max := Vector2(-INF, -INF)
	if shell and shell.mesh:
		var aabb := shell.global_transform * shell.mesh.get_aabb()
		bb_min = Vector2(aabb.position.x, aabb.position.z)
		bb_max = Vector2(aabb.position.x + aabb.size.x, aabb.position.z + aabb.size.z)

	for npc_id in NPC_DATA.keys():
		var data : Dictionary = NPC_DATA[npc_id]
		# #128 — the production manager works INSIDE the office on the operating
		# floor; field crew spawn OUTSIDE the building AABB. The role-flag below
		# inverts the containment check for `production_manager` so Peter ends
		# up at the indoor desk by design, not as a fall-through retry.
		var indoor_role : bool = String(data.get("role", "")) == "production_manager"
		var pos : Vector3 = anchor
		for attempt in 30:
			var ang : float = randf() * TAU
			var r   : float = randf_range(2.0, 20.0)
			var cand := anchor + Vector3(cos(ang) * r, 0.0, sin(ang) * r)
			pos = cand
			var outside : bool = cand.x < bb_min.x or cand.x > bb_max.x \
				or cand.z < bb_min.y or cand.z > bb_max.y
			# Accept candidate when its INSIDE/OUTSIDE matches the role's
			# preference. Field crew want outside; the manager wants inside.
			if outside != indoor_role:
				break
		# Y from floor detection + 1 m for capsule centre.
		pos = _on_floor(pos, 1.0)

		var npc := CharacterBody3D.new()
		npc.name = data["name"]

		# Blocky humanoid body (feet/legs/torso/arms/hands/head/face/hair) instead
		# of the old capsule pill. Its vertical centre sits at the node origin so
		# it lines up with the CapsuleShape3D collider below.
		var npc_ap : Dictionary = data.get("appearance", {}).duplicate()
		if game_state and "npc_appearances" in game_state:
			var custom_npc_ap = game_state.get("npc_appearances")
			if custom_npc_ap is Dictionary and custom_npc_ap.has(npc_id):
				var saved_ap = custom_npc_ap[npc_id]
				if saved_ap is Dictionary:
					for k in saved_ap:
						npc_ap[k] = saved_ap[k]
		var body : Node3D = humanoid_script.build(data["color"], npc_variant, npc_ap)
		body.name = "HumanoidBody"           # tagged so NPC._physics_process can scale it for crouch / prone (#146)
		npc_variant += 1
		npc.add_child(body)

		var col := CollisionShape3D.new()
		col.name = "BodyCollision"           # tagged so NPC can resize the capsule for crouch / prone (#146)
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
		# #147 / #148 — hand the lift booking to every NPC so the operate planner
		# can claim a mast lift when its target is too high to reach from the
		# floor. Null until _register_lifts_for_booking has run; the planner
		# guards against that case.
		if lift_booking != null:
			npc.set("lift_booking", lift_booking)
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
	# #124 — restore operator pins from the save file (HIER coord pins + role/
	# station pins). Must run AFTER setup so workers + their roles exist.
	if game_state and not game_state.crew_pins_data.is_empty() \
			and crew_manager.has_method("restore_pins_dict"):
		crew_manager.restore_pins_dict(game_state.crew_pins_data)
		print("[MainWorld] Restored %d crew pin(s) from save"
			% game_state.crew_pins_data.size())

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
## #90 — per-save placed-build layout path. Derived from the active save name (the
## same stem GameState uses), so every save has its own factory file and a brand-new
## save starts empty. Falls back to the legacy stem when no save name was provided
## (e.g. MainWorld launched directly without going through the menu).
func _factory_layout_path() -> String:
	var stem := "cedo_simulator"
	if EventBus.has_meta("pending_save_name"):
		var n := String(EventBus.get_meta("pending_save_name")).strip_edges()
		if n != "":
			stem = n
	return "user://%s_factory.json" % stem

func _spawn_build_mode() -> void:
	# #90 — PER-SAVE placed-build layout. Each save gets its OWN factory file
	# (user://<save>_factory.json), so a NEW world can NEVER inherit a previous run's
	# machines, and one save's build never clobbers another's. BuildMode reads/writes
	# this injected path; a CONTINUED save with no per-save file yet falls back ONCE to
	# the legacy global user://factory_layout.json (migration), a NEW save never does —
	# its per-save file simply doesn't exist, so it comes up empty. (The old approach
	# wiped a shared global file on a runtime flag, which was fragile; this can't fail.)
	var fpath := _factory_layout_path()
	var is_new : bool = game_state != null and game_state.is_new_save
	if is_new and FileAccess.file_exists(fpath):
		# Same-named save reused after a delete: force it to truly start fresh.
		DirAccess.remove_absolute(ProjectSettings.globalize_path(fpath))
		print("[MainWorld] New save — wiped stale %s" % fpath)
	print("[MainWorld] Save factory layout: %s (new_save=%s)" % [fpath, str(is_new)])
	build_mode = BuildMode.new()
	build_mode.name = "BuildMode"
	build_mode.player_body = player              # so placement rays ignore the capsule
	build_mode.wall_openings = wall_openings     # set BEFORE add_child → load_layout
	build_mode.layout_path = fpath               # per-save layout file (#90)
	build_mode.allow_legacy_fallback = not is_new  # continue may migrate; new never inherits
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
# CONTAINER GUIDES (#85) — holographic catch-container placement guides
# =============================================================================
## Spawns the ContainerGuideManager as a world child. It scans placed_object
## machines on a ~1 s timer and paints a translucent cyan hologram of the
## correct catch container at each machine's eject/reject point (overband magnet
## → steel skip, flotation/sink-float → waste container, compactor → fines bin).
## A hologram hides when a real container is parked within 0.5 m of its slot.
## Spawned AFTER LineFlow so the machine line already exists for the first scan;
## later-spawned machines (Line 3C macro, demo pipeline, build-placed) are picked
## up by the periodic rescan.
func _spawn_container_guides() -> void:
	container_guides = ContainerGuideManager.new()
	container_guides.name = "ContainerGuideManager"
	add_child(container_guides)
	print("[MainWorld] ContainerGuideManager ready — eject-point holograms active")

# =============================================================================
# VEHICLES — the user can place N of each in WorldSetup; we instantiate one
# scene per saved position, falling back to a single hardcoded "next to player"
# slot if WorldLayout has no spawns for that vehicle id.
# =============================================================================

## Common helper: spawn instances of `scene_path` at every WorldLayout position
## under `layout_id`. If the user hasn't placed any, fall back to a single
## instance at `fallback_offset` from the factory anchor.
func _spawn_vehicle_instances(layout_id: String, scene_path: String, fallback_offset: Vector3, label: String) -> void:
	var scn := load(scene_path) as PackedScene
	if scn == null:
		push_warning("[MainWorld] %s missing — skipping" % scene_path); return
	var positions : Array = WorldLayout.get_vehicle_spawns(layout_id)
	if positions.is_empty():
		# Fallback: spawn one next to the factory anchor.
		var anchor := _get_factory_anchor()
		var pos : Vector3 = _on_floor(anchor + fallback_offset, 0.5)
		var v := scn.instantiate()
		add_child(v); v.global_position = pos
		print("[MainWorld] %s (fallback) spawned at %s" % [label, str(pos)])
		return
	# Markers are stored as player_spawn-relative offsets in north-up RD space.
	# _layout_to_scene() rotates them by the floor-plan calibration angle (the
	# RD→building rotation) and anchors them at the player's scene position.
	for i in positions.size():
		var rel : Vector3 = positions[i]
		if not _layout_rel_sane(rel):
			push_warning("[MainWorld] %s #%d marker is %.0f m from the anchor — corrupt layout data, skipping (re-place it in WorldSetup)" \
				% [label, i + 1, Vector2(rel.x, rel.z).length()])
			continue
		var p : Vector3 = _on_floor(_layout_to_scene(rel), 0.5)
		var v := scn.instantiate()
		add_child(v); v.global_position = p
		print("[MainWorld] %s #%d  placed at scene(%.1f,%.1f)" % [
			label, i + 1, p.x, p.z])

## Sanity guard for layout-relative markers (377 km bug): a marker more than
## ~5 km from the anchor is corrupt RD-space leakage, not a real placement.
## Spawning physics bodies that far out breaks float precision → NaN transforms
## → tens of thousands of "!v.is_finite()" render errors that also tank the
## framerate via log I/O. Skip the marker instead.
func _layout_rel_sane(rel: Vector3) -> bool:
	return Vector2(rel.x, rel.z).length() < 5000.0

# Surfaced on the PerfHud overlay so the layout mapping can be sanity-checked.
var layout_conv_summary : String = "Layout: markers placed at literal WorldSetup coordinates (no rotation, no anchor)"

## Map a saved marker to its scene position. Markers are the EXACT Godot world
## coordinates the user picked in WorldSetup, on the SAME building shell MainWorld
## loads — so they are used DIRECTLY. floor_plan_rot_deg is ONLY a display rotation
## for the satellite/PNG overlay in the editor; it must NOT transform picked
## coordinates. (Earlier builds rotated by it and anchored to the live player,
## which scrambled the layout and made it drift to the last save spot.) RD-scale
## player_spawn is already localized to ~0 on load; the small building-frame
## markers pass through untouched, so this passthrough is correct for both.
func _layout_to_scene(rel: Vector3) -> Vector3:
	return Vector3(rel.x, 0.0, rel.z)

func _spawn_forklift() -> void:
	_spawn_vehicle_instances("forklift", "res://src/scenes/vehicles/Forklift.tscn",
		Vector3(3.0, 0.0, 0.0), "Forklift")

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
	_spawn_vehicle_instances("bale_clamp", "res://src/scenes/vehicles/BaleClamp.tscn",
		Vector3(10.0, 0.0, 0.0), "Bale clamp")

func _spawn_merlo() -> void:
	_spawn_vehicle_instances("merlo", "res://src/scenes/vehicles/Merlo.tscn",
		Vector3(15.0, 0.0, 0.0), "Merlo")
	_spawn_vehicle_instances("merlo_p40", "res://src/scenes/vehicles/MerloP40.tscn",
		Vector3(22.0, 0.0, 0.0), "Merlo P40")

func _spawn_mast_lift() -> void:
	_spawn_vehicle_instances("mast_lift", "res://src/scenes/vehicles/MastLift.tscn",
		Vector3(20.0, 0.0, 0.0), "Mast lift")
	# #147 Phase 3 / #148 Phase 4 — register every mast lift with the booking
	# registry so NPC operate planners can claim one when a target is too high
	# to reach from the floor. Created lazily so non-mast-lift worlds skip it.
	_register_lifts_for_booking()

## Walk the scene tree, build a LiftBooking, register every mast lift instance.
## Called after _spawn_mast_lift; the booking is then handed to every NPC during
## _spawn_crew_manager so the planner can claim lifts at runtime.
var lift_booking : LiftBooking = null

func _register_lifts_for_booking() -> void:
	if lift_booking == null:
		lift_booking = LiftBooking.new()
		lift_booking.name = "LiftBooking"
		add_child(lift_booking)
	var count : int = 0
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v != null and String(v.get("vehicle_type")) == "mast_lift":
			lift_booking.register_lift(v)
			count += 1
	# Some MastLift instances may not be in the "vehicle" group (depends on the
	# .tscn). Fallback: find by class.
	if count == 0:
		for v in find_children("", "VehicleBody3D", true, false):
			if v != null and String(v.get("vehicle_type")) == "mast_lift":
				lift_booking.register_lift(v)
				count += 1
	print("[MainWorld] LiftBooking: registered %d mast lift(s)" % count)
	# NPCs spawn BEFORE mast lifts in _ready order, so the booking ref they got
	# was null. Backfill it now so the operate planner can claim a lift on its
	# next tick.
	for npc_id in npcs.keys():
		var npc = npcs[npc_id]
		if npc != null and is_instance_valid(npc):
			npc.set("lift_booking", lift_booking)

# =============================================================================
# BALE YARD — feedstock stacks (2-3 high) the vehicles pick up bottom-first
# =============================================================================
## Lays out one stack per feedstock origin in a row beside the vehicle line. Each
## stack is `origin.stack` bales tall (Rotterdam/Forst+ = 3, Alba/Zwolle = 2) so the
## operator can drive a forklift / bale-clamp / Merlo in, grip the BOTTOM bale, and
## lift the whole column at once — exactly how it's done on the lot. Each bale is a
## frozen RigidBody3D in group "bale" with a unique printed label, identical to a
## build-placed bale, so grab / carry / drop and LineFlow feeding all just work.
## Per-yard cap is effectively OFF — each yard now fills its FULL polygon so the
## footprint reads as the drawn shape (the old 60 cap truncated the grid mid-fill
## and left odd partial/triangular strips). A GLOBAL ceiling (MAX_BALES_TOTAL)
## still guards against a runaway 200×200 m polygon re-triggering the RID-limit
## freeze — realistic yards fill completely well under it; only a pathological
## layout would ever hit it, and a truncated last yard beats a frozen game.
const MAX_BALES_PER_YARD : int = 100000
# Global ceiling on spawned yard bales. Each simple yard bale is now ~4 meshes
# (down from ~10) and culls its body at 18 m, so the per-frame cost is bounded by
# the cull radius, not the total — but the total still bounds physics RIDs, so we
# keep a sane ceiling. 600 reads as a full pile without the RID-limit freeze.
# Want denser yards? raise this AND/OR raise the body _lod_cull in _m_bale_simple.
const MAX_BALES_TOTAL    : int = 600

## Spawn bales inside each polygonal yard saved in WorldLayout, picking the
## supplier_id from the yard. Bales are tiled across the polygon footprint in a
## simple axis-aligned grid (rows × cols) clipped against the polygon — quick
## first pass; the full grid-rotated fill is task #25.
func _spawn_bale_yards_from_layout() -> void:
	if WorldLayout.bale_yards.is_empty():
		print("[MainWorld] No bale yards in layout"); return
	var yards_root := Node3D.new()
	yards_root.name = "BaleYards"
	add_child(yards_root)
	var total_bales := 0
	var total_yards := 0
	for y in WorldLayout.bale_yards:
		var data : Dictionary = y
		var corners : Array = data.get("corners", [])
		if corners.size() < 3: continue
		var supplier_id : String = data.get("supplier_id", "")
		if supplier_id == "":
			push_warning("[MainWorld] Bale yard has no supplier_id — skipping")
			continue
		var origin_def : Dictionary = BaleDefs.get_origin(supplier_id)
		if origin_def.is_empty():
			push_warning("[MainWorld] Unknown supplier_id '%s' — skipping yard" % supplier_id)
			continue
		var size : Vector3 = origin_def.get("size", Vector3(1.1, 0.7, 1.1))
		var stack_high : int = int(origin_def.get("stack", 2))
		# Convert the polygon corners from layout-space (player-relative, north-up
		# RD) into scene-space via the same rotation-aware mapping the vehicles
		# use, so the yard sits in the right place + orientation on the building.
		var translated_corners : Array = []
		var yard_corrupt := false
		for c in corners:
			if not _layout_rel_sane(c):
				yard_corrupt = true
				break
			translated_corners.append(_layout_to_scene(c))
		if yard_corrupt:
			push_warning("[MainWorld] Yard '%s' has a corner km away from the anchor — corrupt layout data, skipping yard (redraw it in WorldSetup)" % supplier_id)
			continue
		corners = translated_corners
		# FIX (footprint shows as a triangle): if the user clicked corners in
		# Z-order (TL, TR, BL, BR) the polygon self-intersects into a bowtie and
		# point-in-polygon only fills a triangle. Re-sort the corners by angle
		# around their centroid so any 4 points form a proper convex quad.
		corners = _sort_corners_ccw(corners)
		# Fill the polygon along ITS OWN LONGEST EDGE direction, not world X/Z. This
		# is what the user was missing: their rectangles are typically NOT axis-
		# aligned, so an axis-aligned grid only filled the diamond inscribed in the
		# polygon's AABB (the visible "diamond inside the rectangle" pattern). Now
		# bales are laid out along the polygon's actual edges, rotated to match,
		# filling the rectangle properly.
		var le_a : Vector3 = corners[0]; var le_b : Vector3 = corners[0]
		var le_len_sq : float = 0.0
		for i in corners.size():
			var ca : Vector3 = corners[i]
			var cb : Vector3 = corners[(i + 1) % corners.size()]
			var dd : float = (cb - ca).length_squared()
			if dd > le_len_sq:
				le_len_sq = dd; le_a = ca; le_b = cb
		var u_axis : Vector3 = (le_b - le_a)
		u_axis.y = 0.0
		u_axis = u_axis.normalized() if u_axis.length() > 0.001 else Vector3.RIGHT
		# #102 — final NaN guard: if the polygon is degenerate (collinear corners,
		# zero-area, or any NaN-tainted coordinate that slipped past the sanity
		# check), the normalize path can still produce a non-finite u_axis. Drop
		# the yard rather than spawn bales with NaN transforms — those hit the
		# renderer every frame and saturate the error log (~46k errors).
		if not u_axis.is_finite() or u_axis.length_squared() < 0.5:
			push_warning("[MainWorld] Yard '%s' has degenerate polygon — skipping (redraw it)" % supplier_id)
			continue
		var v_axis : Vector3 = Vector3(-u_axis.z, 0.0, u_axis.x)   # 90° CCW in XZ
		# Polygon centroid (the grid pivot in WORLD space).
		var centroid := Vector3.ZERO
		for c in corners: centroid += c
		centroid /= float(corners.size())
		# Polygon UV extents in the (u,v) local basis (so the grid steps span the
		# real polygon extent — no diamond clipping).
		var min_u :=  INF; var max_u := -INF
		var min_v :=  INF; var max_v := -INF
		for c in corners:
			var cv : Vector3 = c
			var dv : Vector3 = cv - centroid
			# Renamed from u/v — same names are reused as the row-walking cursors
			# later in this function and the inner shadowing tripped
			# CONFUSABLE_LOCAL_DECLARATION.
			var pu : float = dv.dot(u_axis)
			var pv : float = dv.dot(v_axis)
			if pu < min_u: min_u = pu
			if pu > max_u: max_u = pu
			if pv < min_v: min_v = pv
			if pv > max_v: max_v = pv
		var poly2 : PackedVector2Array = _polygon_xz(corners)   # for point-in-poly check (world XZ)
		var yard_w : float = max_u - min_u
		var yard_d : float = max_v - min_v
		print("[MainWorld]  Yard '%s'  polygon-aligned %.1f × %.1f m  (stack %d)" \
			% [supplier_id, yard_w, yard_d, stack_high])
		# #61 follow-up — slightly wider step so adjacent bales read as
		# individual blocks rather than one continuous wall (operator: "Rotterdam
		# stack looks like a continuous super-long bale"). The MM body box is
		# size×0.98, so 0.25 m extra leaves a visible ~20 cm air-gap between
		# bales while keeping pack-density realistic.
		var step_x : float = size.x + 0.25
		var step_z : float = size.z + 0.25
		var floor_y : float = _floor_top_y()
		var yard_node := Node3D.new()
		yard_node.name = "Yard_%s" % supplier_id
		yards_root.add_child(yard_node)
		var nm : String = String(origin_def.get("name", supplier_id))
		var prefix : String = nm.substr(0, 3).to_upper()
		var bale_yaw : float = atan2(u_axis.x, u_axis.z)    # rotate each bale so its size.x aligns with the polygon edge
		# #61 — collect every (world_xy, level) the polygon would fill, FIRST,
		# so we can size the per-yard MultiMesh once before spawning bales. The
		# old per-bale build_node() + 13 MeshInstance3D children gave us ~30k
		# draw calls and 50-100k objs when yards were in view; the new path is
		# one MultiMesh per yard (= 1 draw call) plus colliders.
		var slots : Array = []   # each entry = [Vector3 pos, int level]
		var u := min_u + step_x * 0.5
		while u <= max_u:
			var v := min_v + step_z * 0.5
			while v <= max_v:
				var world_xy : Vector3 = centroid + u_axis * u + v_axis * v
				# #102 — last-line NaN gate. The renderer hits is_finite() once
				# per frame on every transform; a single bad bale would saturate
				# the error log. Drop the cell silently if the math went bad.
				if not world_xy.is_finite():
					v += step_z
					continue
				if Geometry2D.is_point_in_polygon(Vector2(world_xy.x, world_xy.z), poly2):
					for level in stack_high:
						slots.append([world_xy, level])
				v += step_z
			u += step_x
		var bales_this_yard : int = slots.size()
		if bales_this_yard > 0:
			# One MultiMesh sized to the whole yard.
			var mmi := PlaceableCatalog.build_yard_multimesh(supplier_id, bales_this_yard)
			# #117 — Close-LOD MM with groove-shaded bale material; visibility-
			# range swap with the far MM hides it past ~35 m so far-distance
			# draw count stays at 1 per yard. Close-range yards now show wire
			# shadow grooves on every bale face.
			var mmi_close := PlaceableCatalog.build_yard_multimesh_close(supplier_id, bales_this_yard)
			# #125 — Proximity-loaded paper sticker MM per yard. Stickers vanish
			# beyond STICKER_LOD_M (12 m) so far yards pay zero sticker cost; close
			# yards get the one-draw-call label pass.
			var mmi_sticker := PlaceableCatalog.build_yard_sticker_multimesh(supplier_id, bales_this_yard)
			if mmi != null:
				yard_node.add_child(mmi)
				# Far MM kicks in past CLOSE_LOD_M; close MM fades out at the
				# same threshold. 4 m margin = soft swap with no visible pop.
				const CLOSE_LOD_M : float = 35.0
				const STICKER_LOD_M : float = 12.0
				mmi.visibility_range_begin        = CLOSE_LOD_M
				mmi.visibility_range_begin_margin = 4.0
				mmi.visibility_range_fade_mode    = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if mmi_close != null:
					yard_node.add_child(mmi_close)
					mmi_close.visibility_range_end        = CLOSE_LOD_M
					mmi_close.visibility_range_end_margin = 4.0
					mmi_close.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				if mmi_sticker != null:
					yard_node.add_child(mmi_sticker)
					mmi_sticker.visibility_range_end        = STICKER_LOD_M
					mmi_sticker.visibility_range_end_margin = 2.0
					mmi_sticker.visibility_range_fade_mode  = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
				var safe_yaw : float = bale_yaw if is_finite(bale_yaw) else 0.0
				var bale_basis := Basis(Vector3.UP, safe_yaw)
				var size_y_half : float = size.y * 0.5
				# Pass 1 — populate the MultiMesh transforms IMMEDIATELY. These are
				# just integer transform writes to the shared buffer and finish in
				# a fraction of a second even for 2940 instances. Bales render at
				# correct positions the moment the yard appears. Same transforms
				# go into BOTH MMs so far / close stay perfectly aligned during
				# the fade swap.
				for i in bales_this_yard:
					var entry : Array = slots[i]
					var pos : Vector3 = entry[0]
					var level : int = int(entry[1])
					var inst_origin := Vector3(
						pos.x,
						floor_y + size.y * float(level) + size_y_half,
						pos.z)
					var xf := Transform3D(bale_basis, inst_origin)
					mmi.multimesh.set_instance_transform(i, xf)
					if mmi_close != null:
						mmi_close.multimesh.set_instance_transform(i, xf)
					if mmi_sticker != null:
						# Sticker rides the +Z face at mid-height, 4 mm proud of the
						# bale skin so it doesn't z-fight. QuadMesh faces +Z by
						# default, which lines up with the bale's +Z face.
						var sticker_local := Vector3(0.0, 0.0, size.z * 0.49 + 0.004)
						var sticker_xf := Transform3D(bale_basis,
							inst_origin + bale_basis * sticker_local)
						mmi_sticker.multimesh.set_instance_transform(i, sticker_xf)
				# #127 — Pass 2: per-bale collider creation is the actual cost
				# (2940 RigidBody3D + CollisionShape3D + meta + group joins). The
				# old loop blocked >60 s. Defer the RBs into call_deferred batches
				# so the main thread can return to the shift right away, and the
				# yards finish stocking themselves over the next ~1 s of frames.
				total_bales += bales_this_yard
				call_deferred("_defer_yard_rb_batch",
					yard_node, mmi, supplier_id, prefix, slots, floor_y, size, safe_yaw, 0)
		print("[MainWorld]  Yard '%s' filled with %d bales  (1 multimesh draw call)" % [supplier_id, bales_this_yard])
		total_yards += 1
	print("[MainWorld] Bale yards from layout: %d bales across %d yards (RBs deferred)" % [total_bales, total_yards])

# #127 — yard collider batch worker. Creates BALE_RB_BATCH RigidBody3Ds per
# call, then re-queues itself via call_deferred until the slot list is drained.
# A single 2940-slot yard finishes in ~12 batches over the first ~1 s of frames
# — invisible under a steady 60 fps and the player gets control instantly
# instead of after a one-minute freeze.
const BALE_RB_BATCH : int = 250

func _defer_yard_rb_batch(yard_node: Node3D, mmi: MultiMeshInstance3D,
		supplier_id: String, prefix: String, slots: Array,
		floor_y: float, size: Vector3, yaw: float, start_idx: int) -> void:
	if yard_node == null or not is_instance_valid(yard_node):
		return
	var end_idx : int = mini(start_idx + BALE_RB_BATCH, slots.size())
	for i in range(start_idx, end_idx):
		var entry : Array = slots[i]
		var pos : Vector3 = entry[0]
		var level : int = int(entry[1])
		var rb := PlaceableCatalog.build_yard_bale_mm(supplier_id, mmi, i)
		if rb == null:
			continue
		yard_node.add_child(rb)
		var spawn_pos := Vector3(pos.x, floor_y + size.y * float(level), pos.z)
		rb.global_position = spawn_pos
		rb.rotation.y = yaw
		var code := "%s-%05d" % [prefix, (randi() % 100000)]
		rb.set_meta("bale_code", code)
		# #73 — origin pose so Reset Bales can snap moved bales back.
		rb.set_meta("yard_origin", spawn_pos)
		rb.set_meta("yard_origin_yaw", yaw)
	if end_idx < slots.size():
		call_deferred("_defer_yard_rb_batch",
			yard_node, mmi, supplier_id, prefix, slots, floor_y, size, yaw, end_idx)

# =============================================================================
# SHIFT-LEADER PC — bale yard maintenance buttons (#73, #74)
# =============================================================================
## Snap every yard bale back to its spawn pose. Called from the shift-leader's
## "Reset bales" button. Cleans up: bales pushed off stacks by physics, bales
## still in their grabbed (detailed) form, bales that drifted >0.5 m from their
## original yard slot. Restores the multimesh slot for detailed bales so the
## yard renders normally again.
func reset_yard_bales() -> int:
	var n_reset : int = 0
	for b in get_tree().get_nodes_in_group("bale"):
		var rb := b as Node3D
		if rb == null or not is_instance_valid(rb):
			continue
		if not rb.has_meta("yard_origin"):
			continue   # not a yard-MM bale (forklift-placed elsewhere)
		var origin : Vector3 = rb.get_meta("yard_origin")
		var yaw    : float   = float(rb.get_meta("yard_origin_yaw", 0.0))
		var drift  : float   = rb.global_position.distance_to(origin)
		var was_detailed : bool = not bool(rb.get_meta("simple_bale", true))
		if drift < 0.05 and not was_detailed:
			continue   # already at rest
		# Snap pose.
		if rb is RigidBody3D:
			var rbody := rb as RigidBody3D
			rbody.linear_velocity = Vector3.ZERO
			rbody.angular_velocity = Vector3.ZERO
			rbody.freeze = true
			rbody.sleeping = true
			rbody.collision_layer = 1
			rbody.collision_mask = 1
		rb.global_position = origin
		rb.rotation.y = yaw
		# If the bale was promoted to a detailed visual (Model children), strip it
		# and reveal the multimesh slot again — back to the cheap representation.
		if rb.has_meta("yard_mm_inst") and rb.has_meta("yard_mm_idx"):
			var mmi := rb.get_meta("yard_mm_inst") as MultiMeshInstance3D
			var idx := int(rb.get_meta("yard_mm_idx"))
			if mmi != null and mmi.multimesh != null \
					and idx >= 0 and idx < mmi.multimesh.instance_count:
				var bale_basis := Basis(Vector3.UP, yaw)
				# MM instances are CENTRE-positioned, body is BASE-positioned; the
				# half-height offset matches what _spawn_yards does at spawn.
				var size : Vector3 = BaleDefs.get_origin(
					String(rb.get_meta("material_origin", ""))).get("size", Vector3(1.1, 0.7, 1.1))
				var inst_origin := origin + Vector3(0.0, size.y * 0.5, 0.0)
				mmi.multimesh.set_instance_transform(idx,
					Transform3D(bale_basis, inst_origin))
		var model := rb.get_node_or_null("Model")
		if model != null:
			for ch in model.get_children():
				ch.queue_free()
			model.queue_free()   # detail_bale recreates it next time
		# Reset gameplay meta to "fresh bale" state.
		rb.set_meta("simple_bale", true)
		rb.set_meta("scanned", false)
		rb.set_meta("wires_cut", false)
		n_reset += 1
	print("[MainWorld] Reset %d yard bales" % n_reset)
	return n_reset

## Order a fresh yard restock from the shift-leader PC. v1 implementation: emit
## a walkie "logistiek" call NOW confirming the order, set a pending flag, and
## subscribe to ShiftClock.shift_started. On the next shift start the delivery
## confirmation fires and reset_yard_bales() runs to clear any drift / grabs
## that happened during the shift — net effect, the next shift opens with a
## "freshly stocked" yard.
##
## Persistence: _restock_pending is in-memory only; closing the game cancels a
## pending order. Wire to GameState in a v2 if persistence matters.
func restock_yard_bales() -> int:
	if _restock_pending:
		var walkie_dup := get_node_or_null("/root/Walkie")
		if walkie_dup and walkie_dup.has_method("receive_call"):
			walkie_dup.call("receive_call", "Logistiek",
				"Bestelling al ingepland voor de volgende dienst — geen dubbele levering.")
		return 0
	var walkie := get_node_or_null("/root/Walkie")
	if walkie and walkie.has_method("receive_call"):
		walkie.call("receive_call", "Logistiek",
			"Bestelling ontvangen — nieuwe balen worden geleverd bij de start van de volgende dienst.")
	if shift_clock and shift_clock.has_signal("shift_started"):
		var c := Callable(self, "_on_shift_started_restock")
		if not shift_clock.shift_started.is_connected(c):
			shift_clock.shift_started.connect(c)
	_restock_pending = true
	print("[MainWorld] Restock ordered — delivery on next shift_started")
	return 1

var _restock_pending : bool = false

func _on_shift_started_restock() -> void:
	if not _restock_pending:
		return
	_restock_pending = false
	var n := reset_yard_bales()
	var walkie := get_node_or_null("/root/Walkie")
	if walkie and walkie.has_method("receive_call"):
		walkie.call("receive_call", "Logistiek",
			"Levering aangekomen — %d balen aangevuld voor de nieuwe dienst." % n)
	print("[MainWorld] Restock delivered — %d bales refreshed" % n)

func _polygon_xz(corners: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for c in corners:
		out.append(Vector2(c.x, c.z))
	return out

## Re-orders polygon corners counter-clockwise around their centroid (in the XZ
## plane) so a quad drawn in any click order becomes a simple, non-self-
## intersecting polygon. Without this, corners clicked in Z-order produce a
## bowtie and the yard fills as a triangle.
func _sort_corners_ccw(corners: Array) -> Array:
	if corners.size() < 3:
		return corners
	var cx := 0.0
	var cz := 0.0
	for c in corners:
		cx += c.x; cz += c.z
	cx /= float(corners.size()); cz /= float(corners.size())
	var sorted := corners.duplicate()
	sorted.sort_custom(func(a, b):
		var aa := atan2(a.z - cz, a.x - cx)
		var ab := atan2(b.z - cz, b.x - cx)
		return aa < ab)
	return sorted

func _spawn_bale_yard() -> void:
	# Anchor: each bale yard in WorldLayout is now a 4-corner polygon with an
	# associated supplier_id. For this initial pass we still spawn a single
	# stack-column per supplier, anchored at the polygon centroid of the
	# matching yard. Yards whose supplier doesn't match any BaleDefs origin
	# get the default offset behaviour as a fallback.
	# TODO follow-up: pack rows × columns into the polygon footprint so the
	# user's drawn shape actually fills with bales (the original to-do #38).
	var supplier_to_centroid : Dictionary = {}
	for y in WorldLayout.bale_yards:
		var corners : Array = (y as Dictionary).get("corners", [])
		if corners.size() < 3: continue
		var c := Vector3.ZERO
		for v in corners: c += v
		c /= float(corners.size())
		supplier_to_centroid[(y as Dictionary).get("supplier_id", "")] = _on_floor(c)
	var base : Vector3
	if not supplier_to_centroid.is_empty():
		# Use the first polygon's centroid as the legacy "yard origin" so the
		# existing per-supplier column lay-out below still works for now.
		base = supplier_to_centroid.values()[0]
	else:
		var anchor := _get_factory_anchor()
		# A tidy yard 6 m to the player's side and a few metres ahead. _on_floor
		# already pins Y to the detected floor.
		base = _on_floor(anchor + Vector3(6.0, 0.0, 6.0))

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
# =============================================================================
# Road + Staff Parking (#134 / #135)
# Procedural asphalt + parking bay grid + signs, positioned to match the
# operator's Google Maps satellite of De Asselen Kuil + CeDo staff lot.
# Hardcoded defaults until the WorldSetup parking tool exists; operator can
# tune via the StaffParking export vars on the spawned node.
# =============================================================================
var staff_parking : StaffParking = null

func _spawn_road_and_parking() -> void:
	# Anchor everything to the captured player spawn. Operator tunes
	# PARKING_OFFSET / ROAD_OFFSET below if the satellite-aligned layout
	# wants different relative positions.
	var anchor : Vector3 = _player_spawn_pos
	var ground_y : float = anchor.y - 1.0      # capsule centre - half-height
	# Wide exterior ground plane around the anchor so the player can walk
	# outside the building without falling into void.
	_spawn_exterior_ground(anchor, ground_y)
	# Parking lot — 25 m west, 8 m north of the spawn (roughly behind the
	# building's south face, where the operator's satellite shows it).
	const PARKING_OFFSET := Vector3(-25.0, 0.0, 8.0)
	staff_parking = preload("res://src/scenes/world/StaffParking.gd").new()
	staff_parking.name = "StaffParking"
	add_child(staff_parking)
	staff_parking.global_position = Vector3(
		anchor.x + PARKING_OFFSET.x,
		ground_y + 0.02,
		anchor.z + PARKING_OFFSET.z)
	_spawn_parking_lamps(staff_parking, ground_y)
	# Road — De Asselen Kuil — runs north-south ~15 m west of the parking
	# lot, then turns east into the parking aisle. All waypoints anchored
	# to the player spawn so the layout survives any shell re-anchoring.
	var road : Road = preload("res://src/scenes/world/Road.gd").new()
	road.name = "DeAsselenKuil"
	road.surface_y = ground_y
	road.setup([
		anchor + Vector3(-42.0, 0.0, -40.0),   # south end on De Asselen Kuil
		anchor + Vector3(-42.0, 0.0,   0.0),   # straight north along west edge
		anchor + Vector3(-42.0, 0.0,  20.0),   # past parking entry, continues north
		anchor + Vector3(-25.0, 0.0,  30.0),   # turn east toward plant entry pad
		anchor + Vector3(  0.0, 0.0,  30.0),   # plant entry pad
	])
	add_child(road)
	_spawn_street_sign(anchor + Vector3(-43.5, 0.0, 0.0), "De Asselen Kuil")
	# Extended road network + perimeter + exterior props. Each helper is a
	# self-contained orchestrator that prints its own one-line tally so we can
	# tell at a glance which exterior layer actually landed.
	_spawn_road_extensions(anchor, ground_y)
	_spawn_perimeter_fence(anchor, ground_y)
	_spawn_exterior_props(anchor, ground_y)
	_spawn_floodlights(anchor)
	print("[MainWorld] Road + parking anchored to player spawn %s" % anchor)

## Extra road polylines branching off De Asselen Kuil:
##   1. South E-W extension along the south boundary
##   2. East-side service road parallel to the production hall's east face
##   3. North bale-yard access driveway
##   4. Internal plant aisle between the parking lot and the building's west face
## Each segment instantiates its own Road via the same preload pattern as the
## main De Asselen Kuil road so they all share the surface_y / paint pipeline.
func _spawn_road_extensions(anchor: Vector3, ground_y: float) -> void:
	var road_script := preload("res://src/scenes/world/Road.gd")
	var segments : Array = [
		{
			"name": "DeAsselenKuil_SouthExt",
			"waypoints": [
				anchor + Vector3(-42.0, 0.0, -40.0),
				anchor + Vector3(  5.0, 0.0, -40.0),
			],
		},
		{
			"name": "EastServiceRoad",
			"waypoints": [
				anchor + Vector3( 35.0, 0.0, -30.0),
				anchor + Vector3( 35.0, 0.0,  20.0),
			],
		},
		{
			"name": "NorthBaleYardAccess",
			"waypoints": [
				anchor + Vector3(  5.0, 0.0,  35.0),
				anchor + Vector3( 40.0, 0.0,  35.0),
			],
		},
		{
			"name": "InternalPlantAisle",
			"waypoints": [
				anchor + Vector3(-15.0, 0.0,  -5.0),
				anchor + Vector3( -5.0, 0.0,  -5.0),
			],
		},
	]
	for seg in segments:
		var r : Road = road_script.new()
		r.name = seg["name"]
		r.surface_y = ground_y
		r.setup(seg["waypoints"])
		add_child(r)
	print("[MainWorld] Road extensions: %d extra segments (south ext / east service / north access / plant aisle)" \
		% segments.size())

## Chain-link fence around the plant perimeter + the south entry gate barrier.
## Fence runs the north edge, the east edge, and the eastern half of the south
## edge so the south-west driveway / parking lot stays open to the road.
func _spawn_perimeter_fence(anchor: Vector3, ground_y: float) -> void:
	# `anchor` is the spawn capsule centre (Y ≈ floor + 1.0). Build a
	# ground-level base so XZ comes from the anchor but Y comes from ground_y —
	# avoids the double-Y bug the audit caught (anchor.y + ground_y ≈ 6m up).
	var ga := Vector3(anchor.x, ground_y, anchor.z)
	var fence_script := preload("res://src/scenes/world/exterior/ChainLinkFence.gd")
	var perimeters : Array = [
		{"name": "PerimeterFence_North",     "waypoints": [ga + Vector3(-30.0, 0.0,  38.0), ga + Vector3( 40.0, 0.0,  38.0)]},
		{"name": "PerimeterFence_East",      "waypoints": [ga + Vector3( 40.0, 0.0,  38.0), ga + Vector3( 40.0, 0.0, -35.0)]},
		{"name": "PerimeterFence_SouthEast", "waypoints": [ga + Vector3( 40.0, 0.0, -35.0), ga + Vector3(  8.0, 0.0, -35.0)]},
	]
	for p in perimeters:
		var f = fence_script.new()
		f.name = p["name"]
		# setup() must come BEFORE add_child so _ready() sees populated waypoints.
		# Audit caught: order was reversed → _ready ran empty → fences invisible.
		f.setup(p["waypoints"])
		add_child(f)
	# Gate barrier at the south plant entry — closed by default; opens via
	# set_open(true) when the gate logic eventually wires up.
	var gate = preload("res://src/scenes/world/exterior/GateBarrier.gd").new()
	gate.name = "PlantEntryGate"
	gate.setup(0.0)
	add_child(gate)
	gate.global_position = ga + Vector3(0.0, 0.0, 25.0)
	print("[MainWorld] Perimeter fence: %d runs + 1 gate barrier (south entry)" % perimeters.size())

## Sidewalk + crosswalk + road markings + trees + power line + transformer +
## neighbour buildings. All ground-level Y comes from `ground_y` so everything
## sits flush on the exterior ground plane.
func _spawn_exterior_props(anchor: Vector3, ground_y: float) -> void:
	# Ground-level base anchor (XZ from spawn, Y from ground). Avoids the
	# anchor.y + ground_y double-count the audit caught.
	var ga := Vector3(anchor.x, ground_y, anchor.z)
	# Sidewalk hugs the west side of De Asselen Kuil, parallel to the main road.
	var sidewalk = preload("res://src/scenes/world/exterior/Sidewalk.gd").new()
	sidewalk.name = "Sidewalk_DeAsselenKuil"
	sidewalk.surface_y = ground_y
	# setup() BEFORE add_child so _ready() sees populated waypoints.
	sidewalk.setup([
		ga + Vector3(-45.0, 0.0, -40.0),
		ga + Vector3(-45.0, 0.0,  20.0),
	])
	add_child(sidewalk)
	# Crosswalk at the bend where De Asselen Kuil turns east. Y comes from
	# global_position; surface_y=0 keeps the stripes flush (was double-anchored).
	var crosswalk = preload("res://src/scenes/world/exterior/Crosswalk.gd").new()
	crosswalk.name = "Crosswalk_DeAsselenKuil"
	crosswalk.surface_y = 0.0
	crosswalk.setup(6)
	add_child(crosswalk)
	crosswalk.global_position = ga + Vector3(-42.0, 0.0, 0.0)
	# Road markings — STOP bar at the gate, give-way triangles approaching it,
	# directional arrows in the parking aisles. Kind strings MUST match
	# RoadMarking.gd's match arms exactly (audit caught: was "stop"/"give_way"/"arrow",
	# silently queue_free'd as unknown).
	var marking_script := preload("res://src/scenes/world/exterior/RoadMarking.gd")
	var markings = marking_script.new()
	markings.name = "RoadMarkings"
	markings.surface_y = ground_y
	add_child(markings)
	markings.build_at("stop_text",          ga + Vector3(0.0, 0.0, 22.0), 0.0, "white")
	markings.build_at("give_way_triangle",  ga + Vector3(0.0, 0.0, 19.0), 0.0, "white")
	markings.build_at("give_way_triangle",  ga + Vector3(2.0, 0.0, 19.0), 0.0, "white")
	markings.build_at("arrow_straight",     ga + Vector3(-25.0, 0.0, 5.0),  0.0, "white")
	markings.build_at("arrow_straight",     ga + Vector3(-25.0, 0.0, 11.0), 0.0, "white")
	# Tree clusters spaced along the west side of De Asselen Kuil.
	var tree_script := preload("res://src/scenes/world/exterior/TreeCluster.gd")
	var tree_offsets : Array = [
		Vector3(-50.0, 0.0, -30.0),
		Vector3(-50.0, 0.0, -10.0),
		Vector3(-50.0, 0.0,  10.0),
		Vector3(-50.0, 0.0,  28.0),
	]
	for i in tree_offsets.size():
		var tc = tree_script.new()
		tc.name = "TreeCluster_%d" % i
		add_child(tc)
		tc.cluster_at(ga + tree_offsets[i], 3.5, 5, i * 17 + 3)
	# Power poles every ~30 m along De Asselen Kuil, with wires strung between
	# consecutive poles.
	var pole_script := preload("res://src/scenes/world/exterior/PowerPole.gd")
	var pole_positions : Array = [
		ga + Vector3(-46.0, 0.0, -38.0),
		ga + Vector3(-46.0, 0.0, -10.0),
		ga + Vector3(-46.0, 0.0,  18.0),
		ga + Vector3(-30.0, 0.0,  33.0),
		ga + Vector3(  0.0, 0.0,  33.0),
	]
	var poles : Array = []
	for i in pole_positions.size():
		var pp = pole_script.new()
		pp.name = "PowerPole_%d" % i
		add_child(pp)
		pp.global_position = pole_positions[i]
		pp.build_pole()
		poles.append(pp)
	for i in poles.size() - 1:
		poles[i].build_to(pole_positions[i + 1])
	# Transformer cabinet in the south yard.
	var transformer = preload("res://src/scenes/world/exterior/TransformerCabinet.gd").new()
	transformer.name = "TransformerCabinet"
	add_child(transformer)
	transformer.global_position = ga + Vector3(10.0, 0.0, -10.0)
	transformer.setup()
	# Neighbour buildings — SW solar-roof neighbour + NW smaller workshop.
	var nb_script := preload("res://src/scenes/world/exterior/NeighborBuilding.gd")
	var nb_sw = nb_script.new()
	nb_sw.name = "NeighborBuilding_SW"
	add_child(nb_sw)
	nb_sw.build_at(
		ga + Vector3(-60.0, 0.0, -55.0),
		Vector3(18.0, 6.0, 14.0),
		Color(0.82, 0.78, 0.70),
		"Recyclepartner BV",
		Color(0.18, 0.22, 0.36),
		0.0,
		11)
	var nb_nw = nb_script.new()
	nb_nw.name = "NeighborBuilding_NW"
	add_child(nb_nw)
	nb_nw.build_at(
		ga + Vector3(-55.0, 0.0, 25.0),
		Vector3(12.0, 4.5, 10.0),
		Color(0.74, 0.70, 0.62),
		"Werkplaats",
		Color(0.20, 0.18, 0.18),
		0.0,
		23)
	print("[MainWorld] Exterior props: sidewalk + crosswalk + %d markings + %d tree clusters + %d power poles + transformer + 2 neighbour buildings" \
		% [5, tree_offsets.size(), pole_positions.size()])

## Wall-mounted floodlights aimed outward from the south + west faces of the
## production hall so the exterior yard reads at dusk/night. Each Floodlight
## tilts down by `tilt_down_deg`; we set yaw so the cone points away from the
## wall it hangs on.
func _spawn_floodlights(anchor: Vector3) -> void:
	var fl_script := preload("res://src/scenes/world/exterior/Floodlight.gd")
	# (local_offset_from_anchor, yaw_deg_pointing_outward)
	var mounts : Array = [
		{"pos": Vector3(-5.0, 5.0,  5.0), "yaw": 180.0},  # south face, west side
		{"pos": Vector3( 5.0, 5.0,  5.0), "yaw": 180.0},  # south face, east side
		{"pos": Vector3(15.0, 5.0,  5.0), "yaw": 180.0},  # south face, far east
		{"pos": Vector3(-8.0, 5.0, 15.0), "yaw":  90.0},  # west face, mid
	]
	for i in mounts.size():
		var m : Dictionary = mounts[i]
		var fl = fl_script.new()
		fl.name = "Floodlight_%d" % i
		# setup() BEFORE add_child so _ready uses the requested tilt (audit caught:
		# setup() only mutates tilt_down_deg; _ready had already built with the
		# default by the time setup() ran post-add_child).
		fl.setup(25.0)
		add_child(fl)
		fl.global_position = anchor + (m["pos"] as Vector3)
		fl.rotation.y = deg_to_rad(float(m["yaw"]))
	print("[MainWorld] Floodlights: %d wall-mounted (south + west building faces)" % mounts.size())

## #145 Phase 1 — Bake a NavigationRegion3D from the interior floor + the
## exterior ground plane. NPCs route through this region instead of walking
## straight-line through walls and machines.
##
## Source geometry: every MeshInstance3D in the "navmesh_source" group. The
## bake is async (worker thread); NPCs fall back to straight-line until it
## completes, so there's no startup stall.
const NAVMESH_GROUP : String = "navmesh_source"

func _spawn_navigation_region() -> void:
	# Find the interior floor mesh + exterior ground and tag them as nav sources.
	var floor_mi := find_child("TempFloor", true, false)
	if floor_mi:
		var fm := floor_mi.find_child("MeshInstance3D", false, false) as MeshInstance3D
		if fm:
			fm.add_to_group(NAVMESH_GROUP)
	var ext_ground := find_child("ExteriorGround", false, false) as MeshInstance3D
	if ext_ground:
		ext_ground.add_to_group(NAVMESH_GROUP)
	# Build the region.
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	add_child(region)
	var nm := NavigationMesh.new()
	nm.cell_size = 1.00
	nm.cell_height = 0.60
	nm.agent_radius = 0.40
	nm.agent_height = 1.80
	nm.agent_max_climb = 0.30                   # step over short curbs
	nm.agent_max_slope = 45.0
	# Pull source geometry from MeshInstance3Ds in the NAVMESH_GROUP group, scene-wide.
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_MESH_INSTANCES
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_EXPLICIT
	nm.geometry_source_group_name = NAVMESH_GROUP
	region.navigation_mesh = nm
	# Bake on a worker thread so we don't stall the shift boot. NavigationAgent3D
	# in each NPC reads the live navmap as soon as bake completes.
	region.bake_navigation_mesh(true)
	print("[MainWorld] NavRegion baking (group '%s', %d source meshes)" % \
		[NAVMESH_GROUP, get_tree().get_nodes_in_group(NAVMESH_GROUP).size()])

# =============================================================================
# #155 — Shift-start: spawn cars in lot + player in Swift on road + Yasin shotgun
# =============================================================================
## Slot assignment matching the operator's Google Maps satellite of the lot.
## side: -1 = left row, +1 = right row. idx: 0 = north end, 9 = south end.
## Player Swift sits in right-row slot 2 (operator-identified in the photo).
const _CAR_SLOTS : Dictionary = {
	"abdellilah": {"side": -1, "idx": 0},   # left row, slot 1 (Ka sunset orange)
	"emrah":      {"side": -1, "idx": 1},   # left row, slot 2 (Audi A3 sunroof)
	"mohammed":   {"side": -1, "idx": 2},   # left row, slot 3 (VW Golf)
	"vincent":    {"side": -1, "idx": 3},   # left row, slot 4 (Volvo V40 placeholder)
	"pascal":     {"side":  1, "idx": 0},   # right row, slot 1 (black Streetka)
	"romain":     {"side":  1, "idx": 1},   # right row, slot 2 (Hyundai i20 — Roman)
	"peter":      {"side":  1, "idx": 3},   # right row, slot 4 (BMW X1 placeholder)
	# Player Swift: right row, slot 3 (operator's car)
	# Vincent / Pascal / Peter: GLB assets pending — slots reserved when those land.
}
const _PLAYER_SWIFT_SLOT : Dictionary = {"side": 1, "idx": 2}

func _spawn_shift_cars_and_player_drive_in() -> void:
	if staff_parking == null:
		push_warning("[MainWorld] #155: staff_parking missing — cars not spawned")
		return
	# (B) NPC cars — one per NPC that has an asset, parked in their satellite slot.
	var spawned_cars : int = 0
	var missing_assets : Array = []
	for npc_id in NPC_DATA.keys():
		var data : Dictionary = NPC_DATA[npc_id]
		var car_path : String = String(data.get("car", ""))
		if car_path == "" or car_path == "passenger:player":
			# All 7 NPC cars have asset paths now (real GLB or placeholder).
			# Missing-asset tracking kept for any future additions.
			continue
		if not _CAR_SLOTS.has(npc_id):
			continue
		var slot : Dictionary = _CAR_SLOTS[npc_id]
		_spawn_car_in_bay(car_path, int(slot["side"]), int(slot["idx"]),
			"%s's car" % String(data["name"]))
		spawned_cars += 1
	# (D) Player's Swift on the south end of De Asselen Kuil, facing north
	# (so the operator drives forward into the lot). Parked alongside the
	# road's south waypoint anchor + spawn_pos offset.
	var swift : Node3D = _spawn_player_swift_on_road()
	# (C) Yasin in the Swift's passenger seat.
	if swift != null and npcs.has("yassine"):
		var yasin : Node3D = npcs["yassine"] as Node3D
		if yasin != null and swift.has_method("seat_passenger"):
			swift.call("seat_passenger", yasin)
	# Programmatic boarding — put the player in the driver seat so they
	# start the shift sitting in the car (per #155 spec). Uses
	# OperatorContext.enter_interactable_vehicle so the camera takes the
	# CabCamera and the player gets the throttle/steer inputs straight away.
	if swift != null and player != null:
		if operator_context and operator_context.has_method("enter_interactable_vehicle"):
			operator_context.call("enter_interactable_vehicle", swift)
		elif swift.has_method("get_boarding_position"):
			# Fallback: teleport the player next to the driver door so they
			# can board with E themselves. Not autopilot, just positioning.
			player.global_position = swift.call("get_boarding_position")
	print("[MainWorld] #155 shift-start: %d NPC cars in lot, player in Swift on road, %d assets missing (%s)" \
		% [spawned_cars, missing_assets.size(), str(missing_assets)])

func _spawn_car_in_bay(scene_path: String, side: int, idx: int, label: String) -> Node3D:
	var ps := load(scene_path) as PackedScene
	if ps == null:
		push_warning("[MainWorld] #155: car scene missing: %s" % scene_path)
		return null
	var car : Node3D = ps.instantiate() as Node3D
	if car == null:
		return null
	add_child(car)
	car.transform = staff_parking.bay_world_transform(side, idx)
	car.set_meta("display_label", label)
	return car

## Player's red Suzuki Swift parked on De Asselen Kuil at the south end,
## facing NORTH so a forward drive brings the operator straight into the lot.
func _spawn_player_swift_on_road() -> Node3D:
	var ps := load(PLAYER_CAR_SCENE) as PackedScene
	if ps == null:
		push_warning("[MainWorld] #155: SuzukiSwiftGLX.tscn missing")
		return null
	var swift : Node3D = ps.instantiate() as Node3D
	if swift == null:
		return null
	add_child(swift)
	# Park on the road. Road south waypoint is (anchor + (-42, _, -40));
	# put the Swift a bit north of that with a heading of +Z (north).
	var anchor : Vector3 = _player_spawn_pos
	var pos := Vector3(anchor.x - 42.0, anchor.y - 1.0 + 0.3, anchor.z - 35.0)
	swift.global_position = pos
	# Face north (+Z) — driver looks UP De Asselen Kuil toward the parking turn.
	swift.rotation.y = 0.0
	return swift

## Wide grass plane around the spawn anchor so the parking + road don't float
## in void. 200x200m centred at the anchor XZ, sits at the same Y as the
## interior floor so there's no visible step at the wall.
func _spawn_exterior_ground(anchor: Vector3, ground_y: float) -> void:
	var ground := MeshInstance3D.new()
	ground.name = "ExteriorGround"
	var pm := PlaneMesh.new()
	pm.size = Vector2(200.0, 200.0)
	ground.mesh = pm
	ground.position = Vector3(anchor.x, ground_y - 0.05, anchor.z)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.46, 0.22)
	mat.roughness = 0.96
	ground.material_override = mat
	ground.add_to_group(NAVMESH_GROUP)         # source for the NavRegion bake
	add_child(ground)
	# Static collision so the player can walk on it.
	var body := StaticBody3D.new()
	body.name = "ExteriorGroundBody"
	body.position = Vector3(anchor.x, ground_y - 0.05, anchor.z)
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(200.0, 0.1, 200.0)
	col.shape = sh
	body.add_child(col)
	add_child(body)

## Four lamp posts at the parking lot corners — tall steel poles with an
## OmniLight3D at the head. Light reads even in dusk/night world lighting,
## and during the day the lamp posts themselves give the lot a real "this
## is a parking lot, not a slab of asphalt" feel.
func _spawn_parking_lamps(parking_node: Node3D, _ground_y: float) -> void:
	var fp : Vector2 = parking_node.call("footprint") as Vector2
	var post_h : float = 4.5
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var corner_local := Vector3(
				sx * (fp.x * 0.5 + 0.8),
				0.0,
				sz * (fp.y * 0.5 + 0.8))
			var lamp := Node3D.new()
			lamp.name = "ParkingLamp"
			parking_node.add_child(lamp)
			lamp.position = corner_local
			# Steel post
			var post := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.06
			cm.bottom_radius = 0.06
			cm.height = post_h
			post.mesh = cm
			post.position = Vector3(0.0, post_h * 0.5, 0.0)
			var post_mat := StandardMaterial3D.new()
			post_mat.albedo_color = Color(0.30, 0.30, 0.32)
			post_mat.metallic = 0.7
			post_mat.roughness = 0.45
			post.material_override = post_mat
			lamp.add_child(post)
			# Lamp head box (small white luminaire)
			var head := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.45, 0.18, 0.30)
			head.mesh = bm
			head.position = Vector3(0.0, post_h - 0.05, 0.0)
			var head_mat := StandardMaterial3D.new()
			head_mat.albedo_color = Color(0.92, 0.92, 0.90)
			head_mat.emission_enabled = true
			head_mat.emission = Color(1.0, 0.95, 0.78)
			head_mat.emission_energy_multiplier = 1.5
			head.material_override = head_mat
			lamp.add_child(head)
			# Actual light source
			var light := OmniLight3D.new()
			light.name = "Light"
			light.light_color = Color(1.0, 0.93, 0.75)   # sodium-vapor warm
			light.light_energy = 6.0
			light.omni_range = 18.0
			light.position = Vector3(0.0, post_h - 0.15, 0.0)
			lamp.add_child(light)

## Small white street-name sign on a metal pole — placed at the south corner
## where De Asselen Kuil intersects with the parking entry.
func _spawn_street_sign(at: Vector3, text: String) -> void:
	var holder := Node3D.new()
	holder.name = "StreetSign_" + text.replace(" ", "_")
	holder.position = at
	add_child(holder)
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 2.6
	post.mesh = cm
	post.position = Vector3(0.0, 1.3, 0.0)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.78, 0.78, 0.80)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.4
	post.material_override = post_mat
	holder.add_child(post)
	var label := Label3D.new()
	label.text = text
	label.font_size = 56
	label.outline_size = 6
	label.modulate = Color(0.10, 0.10, 0.20)
	label.position = Vector3(0.0, 2.45, 0.0)
	label.pixel_size = 0.005
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	holder.add_child(label)
	# Backing plate (white)
	var plate := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(1.40, 0.32)
	plate.mesh = qm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.96, 0.96, 0.92)
	pm.roughness = 0.6
	plate.material_override = pm
	plate.position = Vector3(0.0, 2.45, -0.01)
	holder.add_child(plate)

const FEEDERS_ENABLED : bool = true   # #11 — rebuilt to drive the REAL clamp controls (no teleport-grab)

func _spawn_feeder_line() -> void:
	if not FEEDERS_ENABLED:
		print("[MainWorld] Feeders DISABLED (rebuilding with real clamp physics) — clean scene.")
		return
	var base : Vector3 = _get_factory_anchor()
	# Two autonomous feed stations — one per shred line. Each has its own
	# opzetband (feed belt) + shredder + bale-clamp vehicle + worker with
	# scissors & scanner. Stations are placed on opposite sides of the base
	# anchor so the approach lanes don't overlap.
	# ONE feeder station: Mohammed on Line 3A/3B (operator-confirmed, twice).
	# Abdullah is Line 1 — that line doesn't exist yet, so he has NO station
	# and stays with the regular crew (idle/chill). Do NOT give him a station
	# until Line 1 is actually built.
	_spawn_feeder_station(base + Vector3( 12.0, -0.9, 24.0), "Mohammed",
			"Line 3A/3B", "res://src/scenes/vehicles/BaleClamp.tscn",
			"shredder_3a3b")

## Build one station: belt + lot + worker + the worker's personal vehicle +
## personal scissors & scanner. `shredder_id` picks which catalog shredder
## sits at the belt's discharge — different per line so the right LineFlow
## machine receives the shredded film.
func _spawn_feeder_station(station: Vector3, worker_name: String,
		line_name: String, vehicle_scene_path: String,
		shredder_id: String) -> FeederWorker:
	# 1) Wide feed belt.
	var belt = preload("res://src/scenes/world/ShredderFeedBelt.gd").new()
	belt.name = "ShredderFeedBelt_%s" % worker_name
	add_child(belt)
	belt.global_position = station

	# 2) The SHREDDER at the belt's discharge. Tagged "shredder" so the belt's
	#    PLC interlock is satisfied and the opzetband runs (#30/#31). Seated on
	#    the floor. `shredder_id` is per-station so Line 3A/3B vs Line 3C/6 each
	#    get their own machine.
	var shredder := PlaceableCatalog.build_node(shredder_id, false) as Node3D
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
	# anchor.Y is now the floor surface (was the capsule centre); no Y fudge needed.
	var cutter_pos := anchor + Vector3(8.0, 0.0, 3.0)
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
	coffee.global_position = anchor + Vector3(8.6, 0.0, 3.4)
	var sandwich : Node3D = prop_script.new()
	sandwich.prop_kind = "sandwich"
	add_child(sandwich)
	sandwich.global_position = anchor + Vector3(8.9, 0.0, 3.4)
	print("[MainWorld] Cabin props (coffee + sandwich) spawned")

	# Drop a barcode scanner half a metre to the right of the scissors. The
	# operator picks it up the same way (E), swaps to it with hotbar 1-4, and
	# left-clicks to scan a bale / container label. Right-click peels the
	# label off into a held LabelItem.
	var scanner_pos := anchor + Vector3(8.6, 0.0, 3.0)
	var scanner := BarcodeScanner.new()
	scanner.name = "BarcodeScanner"
	add_child(scanner)
	scanner.global_position = scanner_pos
	print("[MainWorld] BarcodeScanner @ %s" % str(scanner_pos))

	# Shovel (#154) — for cleaning up chute-spill floor piles into a container.
	var shovel := preload("res://src/scenes/world/ShovelTool.gd").new()
	shovel.name = "ShovelTool"
	add_child(shovel)
	shovel.global_position = anchor + Vector3(9.2, 0.0, 3.0)
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
	# can swing around to pick it up. anchor.Y is the floor surface now.
	var skip := PlaceableCatalog.build_node("skip_steel", false) as Node3D
	if skip != null:
		add_child(skip)
		skip.global_position = anchor + Vector3(6.0, 0.0, 18.0)
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
	zone.global_position = anchor + Vector3(20.0, 0.0, 18.0)
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
	# anchor.y is the floor top now (was the capsule centre, hence the legacy −0.9).
	var floor_y := anchor.y

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
		# #166 — Fresh game starts 30 min BEFORE the bell so the pre-shift arrival
		# sequence (Emrah at T-35, Pascal smoking at T-33, …, Kevin at T-10) has
		# room to play out. The bell still emits shift_started at T=0.
		shift_clock.start_pre_shift(PRE_SHIFT_WINDOW_S)
		print("[MainWorld] Pre-shift started (%.0f min until bell)" % (PRE_SHIFT_WINDOW_S / 60.0))

# =============================================================================
# SAVE / QUIT
# =============================================================================
func save_game() -> void:
	if player and game_state:
		var ps := {
			"x":     player.global_position.x,
			"y":     player.global_position.y,
			"z":     player.global_position.z,
			"rot_y": player.rotation.y,
		}
		# Persist the 3rd-person free-cam pose alongside the player position so the
		# operator's preferred external viewpoint survives a save/load (#freecam).
		var rig := _freecam_rig()
		if rig != null and rig.has_method("serialize_freecam"):
			ps["freecam"] = rig.call("serialize_freecam")
		game_state.save_player_state(ps)
	if shift_clock:
		shift_clock.save_shift_state()
	# #124 — flush crew pins (HIER + station/role) so they survive save/load.
	if crew_manager and game_state and crew_manager.has_method("save_pins_dict"):
		game_state.crew_pins_data = crew_manager.save_pins_dict()
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
	timer.one_shot   = false
	timer.timeout.connect(_on_autosave)
	add_child(timer)
	_apply_autosave_interval()   # set wait_time / start / stop based on setting
	# React to live edits in the Settings menu.
	if has_node("/root/SettingsManager"):
		var sm := get_node("/root/SettingsManager")
		if sm.has_signal("settings_applied"):
			sm.settings_applied.connect(_apply_autosave_interval)

## Reads Settings → Gameplay → "Auto-save interval". 0 disables autosave.
func _apply_autosave_interval() -> void:
	var t := get_node_or_null("AutosaveTimer") as Timer
	if t == null: return
	var iv : float = 60.0
	if has_node("/root/SettingsManager"):
		iv = float(SettingsManager.gameplay().get("autosave_interval_s", 60))
	if iv <= 0.0:
		t.stop()
		print("[MainWorld] Autosave disabled (interval 0)")
		return
	t.wait_time = iv
	if t.is_stopped(): t.start()
	print("[MainWorld] Autosave interval set to %.0fs" % iv)

func _on_autosave() -> void:
	save_game()
	print("[MainWorld] Autosave")

# =============================================================================

# =============================================================================
# FLOOR GENERATION
# =============================================================================
# World-Y of the floor's top surface. Set by _generate_floor_from_shell from
# the largest-area horizontal slab in the building shell mesh (the operating
# floor — NOT the absolute lowest vertex, which would be foundations/below-grade).
var _floor_min_y_cache: float = -9.0

# Floor-detection tunables.
const FLOOR_HORIZONTAL_DOT  := 0.9    # cos(~25°) — face counts as horizontal if up-normal ≥ this
const FLOOR_Y_BUCKET_M      := 0.5    # 0.5 m bins for the area histogram
const FLOOR_AREA_THRESHOLD  := 0.5    # candidate bucket must have ≥ 50% of the max bucket's area
const FLOOR_BOX_SIZE_XZ     := 4000.0 # the collision floor is a huge flat slab; players can't walk off
const FLOOR_BOX_THICKNESS   := 1.0
# Quicksand fix (B): the shell mesh has its own horizontal floor triangles at the
# operating-floor Y (that's how _detect_operating_floor_y finds it). If TempFloor's
# top is at the SAME Y, the player's capsule sits on two coincident colliders, the
# solver oscillates contacts, and the capsule slowly sinks ("quicksand"). Lifting
# the TempFloor's top by 5 cm makes the shell's interior floor sit 5 cm BELOW the
# walkable surface and never contact the capsule. Machines still seat correctly
# because _floor_top_y() returns the LIFTED value.
const FLOOR_LIFT_OFFSET     := 0.05

# =============================================================================
# Floor generation — replace TempFloor's mesh + collision with a simple flat
# box positioned at the building's operating-floor Y.
#
# Why this is necessary: the building shell .obj is BLOSM-derived in real RD
# coordinates (Y range 67.83 – 112.14 m above sea level). After BuildingShell's
# parent transform shifts it down to world space, the operating floor sits at
# world Y ≈ −9.33 and the roof at ≈ −0.83. The OLD code keyed off `min_y` of
# ALL vertices, which picked the lowest mesh point (foundation level, world
# Y ≈ −15) and built a 10-m-thick Delaunay surface above it. Players spawned
# at the marker fell straight through the building, NPCs floated mid-air, and
# every machine placement was off. This rewrite asks the .obj an empirical
# question instead: "where is your biggest flat horizontal up-facing surface?"
# — the answer is the operating floor.
func _generate_floor_from_shell(shell_mesh: MeshInstance3D) -> void:
	var floor_y := _detect_operating_floor_y(shell_mesh)
	if is_nan(floor_y) or is_inf(floor_y):
		push_warning("[MainWorld] Could not detect operating floor; defaulting to world Y=0")
		floor_y = 0.0
	print("[MainWorld] Operating floor detected at world Y = %.3f" % floor_y)

	var floor_node := find_child("TempFloor", true, false) as StaticBody3D
	if floor_node == null:
		push_error("[MainWorld] TempFloor node missing — cannot install floor"); return

	# Position the box so its TOP surface is at floor_y + FLOOR_LIFT_OFFSET — the
	# 5 cm gap lifts the walkable surface clear of the shell's coincident interior
	# floor triangles (quicksand fix B; see FLOOR_LIFT_OFFSET comment).
	var top_y : float = floor_y + FLOOR_LIFT_OFFSET
	floor_node.global_position = Vector3(0.0, top_y - FLOOR_BOX_THICKNESS * 0.5, 0.0)
	floor_node.global_rotation = Vector3.ZERO

	# Replace any prior mesh / collision (from the old Delaunay code or scene
	# defaults) with a simple flat 4000×1×4000 box.
	var mi := floor_node.find_child("MeshInstance3D", false, false) as MeshInstance3D
	if mi:
		var bm := BoxMesh.new()
		bm.size = Vector3(FLOOR_BOX_SIZE_XZ, FLOOR_BOX_THICKNESS, FLOOR_BOX_SIZE_XZ)
		mi.mesh = bm
		mi.transform = Transform3D()
	var cs := floor_node.find_child("CollisionShape3D", false, false) as CollisionShape3D
	if cs:
		var bx := BoxShape3D.new()
		bx.size = Vector3(FLOOR_BOX_SIZE_XZ, FLOOR_BOX_THICKNESS, FLOOR_BOX_SIZE_XZ)
		cs.shape = bx
		cs.transform = Transform3D()

	_floor_min_y_cache = top_y    # the TempFloor's TOP — what _floor_top_y() must return

## Detect the operating floor's world-Y by histogramming up-facing horizontal
## triangle area in 0.5 m Y buckets, then picking the LOWEST bucket whose
## area is at least 50 % of the maximum. The "≥ 50% of max" gate keeps small
## terraces/mezzanines out; the "lowest among candidates" picks the ground
## floor over a same-area roof. Returns +INF if no horizontal faces exist.
func _detect_operating_floor_y(shell_mesh: MeshInstance3D) -> float:
	var mesh := shell_mesh.mesh as ArrayMesh
	if mesh == null: return INF
	var xf := shell_mesh.global_transform
	var area_by_y : Dictionary = {}

	for s in range(mesh.get_surface_count()):
		var arr : Array = mesh.surface_get_arrays(s)
		# Variant-first: a null vertex buffer assigned straight to a typed
		# PackedVector3Array THROWS before the null check below can run (the
		# 'verts == null' line was dead — a typed var can't hold null). Guard
		# with `is` so floor detection survives a degenerate surface instead of
		# crashing and leaving the floor cache at its -9 m sentinel (whole scene
		# spawns underground).
		var verts_raw : Variant = arr[Mesh.ARRAY_VERTEX]
		var verts : PackedVector3Array = verts_raw if verts_raw is PackedVector3Array else PackedVector3Array()
		if verts.is_empty(): continue
		var idx_raw : Variant = arr[Mesh.ARRAY_INDEX]
		var idx : PackedInt32Array = idx_raw if idx_raw is PackedInt32Array else PackedInt32Array()
		if idx.is_empty():
			# Non-indexed mesh: triangles are sequential triples of vertices.
			for i in range(0, verts.size() - 2, 3):
				_floor_add_face(verts[i], verts[i + 1], verts[i + 2], xf, area_by_y)
		else:
			for i in range(0, idx.size() - 2, 3):
				_floor_add_face(verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]], xf, area_by_y)

	if area_by_y.is_empty():
		# No horizontal faces — degenerate mesh. Caller falls back to Y=0.
		return INF

	var max_area := 0.0
	for b in area_by_y:
		if float(area_by_y[b]) > max_area: max_area = float(area_by_y[b])
	var threshold := max_area * FLOOR_AREA_THRESHOLD
	var candidates : Array = []
	for b in area_by_y:
		if float(area_by_y[b]) >= threshold:
			candidates.append(float(b))
	candidates.sort()
	return float(candidates[0])

func _floor_add_face(v1: Vector3, v2: Vector3, v3: Vector3, xf: Transform3D, dict: Dictionary) -> void:
	var p1 := xf * v1
	var p2 := xf * v2
	var p3 := xf * v3
	var cross := (p2 - p1).cross(p3 - p1)
	var len_cross := cross.length()
	if len_cross < 1e-3: return
	# Skip downward-facing triangles (ceilings, undersides) — we only want the
	# floor's top surface. cross.y / len_cross is the up-component of the normal.
	if cross.y / len_cross < FLOOR_HORIZONTAL_DOT: return
	var area := len_cross * 0.5
	var avg_y := (p1.y + p2.y + p3.y) / 3.0
	var bucket := snappedf(avg_y, FLOOR_Y_BUCKET_M)
	dict[bucket] = float(dict.get(bucket, 0.0)) + area

# =============================================================================
# Helpers
# =============================================================================

func get_npc(npc_id: String) -> Node:
	return npcs.get(npc_id, null)

func get_all_npcs() -> Array:
	return npcs.values()
