extends Node3D

class_name MainWorld

# ── Cross-module forwarders (#195) ───────────────────────────────────────────
# Some extracted modules read these off _world (the MainWorld instance) by name.
# Keep thin aliases here so the dynamic lookups in ShiftCarSpawner /
# ShiftLifecycleManager / etc. resolve without coupling to the new module names
# at every call site.
const NPC_DATA           : Dictionary = NPCSpawner.NPC_DATA
const _CAR_SLOTS         : Dictionary = ShiftCarSpawner.CAR_SLOTS

# ── Export ────────────────────────────────────────────────────────────────────
@export var building_shell_path: String = "res://assets/models/CeDo_building.obj"

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
var bale_yard_manager : BaleYardManager   # #195 — yards/spawn-queue/proximity-sweep/reset/restock
var npcs            : Dictionary = {}

# ── Cached scene-tree lookups ────────────────────────────────────────────────
# find_child(..., true, false) walks the whole subtree; calling it dozens of
# times per spawn is a measurable cost on a 1400+ child scene. Cache the two
# nodes every helper needed and re-resolve only if the cached one was freed.
var _shell_mesh_cache    : MeshInstance3D = null
var _player_spawn_cache  : Node3D         = null

# #195 — Canonical world-yaw math + layout transforms extracted to WorldFrame.
# Created at the very start of `_ready()` (before any helper that may need
# `_world_yaw()` / `_bo()` / `_layout_to_scene()` fires). MainWorld keeps thin
# forwarders below that delegate into this child node so the scene tree shape
# and call signatures are preserved.
var _world_frame : WorldFrame = null

func _shell() -> MeshInstance3D:
	if _shell_mesh_cache != null and is_instance_valid(_shell_mesh_cache):
		return _shell_mesh_cache
	# Prefer the direct path first (cheapest), fall back to subtree search.
	var sh := get_node_or_null("BuildingShell/ShellMesh") as MeshInstance3D
	if sh == null:
		sh = find_child("ShellMesh", true, false) as MeshInstance3D
	_shell_mesh_cache = sh
	return sh

func _player_spawn_node() -> Node3D:
	if _player_spawn_cache != null and is_instance_valid(_player_spawn_cache):
		return _player_spawn_cache
	_player_spawn_cache = find_child("PlayerSpawn", false, false) as Node3D
	return _player_spawn_cache

# Where the player actually spawned this run (marker OR resumed save position).
# The forklift parks 3 m from here so it's always within reach on spawn.
var _player_spawn_pos : Vector3 = Vector3.ZERO

# Setup mode state
var is_setup_mode : bool = false
var setup_overlay : CanvasLayer = null

# ── NPC catalogue ─────────────────────────────────────────────────────────────
# #195 — NPC_DATA + the _spawn_npcs / _register_lifts_for_booking / get_npc /
# get_all_npcs implementations live on NPCSpawner (src/scenes/world/NPCSpawner.gd).
# Other call sites here read the roster via `NPCSpawner.NPC_DATA`.

# Per-NPC schedule + dressing-room / canteen / smoke-spot offsets are now
# owned by PreShiftSpawner.gd (#195 extraction). Forwarder kept so the
# _position_cars_for_elapsed() call site downstream still resolves.
const PRE_SHIFT_SCHEDULE : Dictionary = PreShiftSpawner.PRE_SHIFT_SCHEDULE

# =============================================================================
## When true, the scattered test/demo props are NOT spawned — a clean canvas of just
## the rebuilt Line 3C + vehicles + utilities. Set false to restore the test props.
const CLEAN_CANVAS : bool = true

func _ready() -> void:
	# Children's _ready() has already run — GameState has loaded its save file.
	# #195 — Spawn the WorldFrame BEFORE anything else so the earliest helpers
	# that look up `_world_yaw()` / `_bo()` / `_layout_to_scene()` (overhead bay
	# lights, vehicles, NPCs) see a live child manager.
	if _world_frame == null:
		_world_frame = WorldFrame.new()
		_world_frame.name = "WorldFrame"
		_world_frame.setup(self)
		add_child(_world_frame)
	shift_clock = find_child("ShiftClock", false, false) as ShiftClock
	game_state  = find_child("GameState",  false, false) as GameState

	if not shift_clock: push_error("[MainWorld] ShiftClock node missing")
	if not game_state:  push_error("[MainWorld] GameState node missing")

	var shell_loader := BuildingShellLoader.new(); add_child(shell_loader); shell_loader.setup(self, building_shell_path); shell_loader.load_shell_and_openings()
	var player_spawner := PlayerSpawner.new(); add_child(player_spawner); player_spawner.setup(self); player = player_spawner.spawn()
	# Road + parking must come AFTER the player spawn so we anchor them relative
	# to `_player_spawn_pos` instead of world origin. The building shell is
	# re-anchored from RD coords at runtime — world origin is meaningless;
	# only the player spawn is a known fixed point in the operating frame.
	_spawn_road_and_parking()
	# Phase 1 of #145 — bake a NavigationRegion3D from the interior floor +
	# exterior ground so NPCs (NavigationAgent3D) can route around obstacles
	# instead of walking in straight lines through machines and walls.
	_spawn_navigation_region()
	var sys_spawner := SystemsSpawner.new(); add_child(sys_spawner); sys_spawner.setup(self)
	_spawn_container_guides()
	var npc_spawner := NPCSpawner.new(); add_child(npc_spawner); npc_spawner.setup(self, _player_spawn_pos); npcs = npc_spawner.spawn_all()
	# #166 Phase B — if we're in pre-shift, intercept the freshly-spawned NPCs
	# and run them through the arrival → dress → canteen loop. Resumed saves
	# (where the shift bell already rang) skip this entirely. (#195 extraction)
	var pre_shift := PreShiftSpawner.new()
	add_child(pre_shift)
	pre_shift.setup(self, npcs, shift_clock, staff_parking, _player_spawn_pos)
	# #155 — spawn the shift's cars + put the player in their Swift + seat Yasin.
	# MUST come after _spawn_npcs (needs npcs["yassine"] to exist to seat as
	# passenger) AND _spawn_operator_context (needs operator_context to board the
	# player into the Swift). Was previously called at line ~105 BEFORE both —
	# Yasin silently never got seated. Audit-caught (#157 follow-up).
	var car_spawner := ShiftCarSpawner.new(); add_child(car_spawner); car_spawner.setup(self, staff_parking, npcs, operator_context, player, _player_spawn_pos)
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
	var veh_spawner := VehicleSpawner.new(); add_child(veh_spawner); veh_spawner.setup(self, _player_spawn_pos)
	_spawn_merlo()

	# When the user has configured a world via WorldSetup, treat it as
	# authoritative: skip ALL legacy hardcoded clutter (utility props, feeder
	# line, demo pipeline, default crew posts). Otherwise spawn the legacy
	# layout for backward-compat / first-run experience.
	var layout_authoritative := WorldLayout.is_configured()

	if not layout_authoritative:
		LegacyPropsSpawner.spawn_all(self, _get_factory_anchor(), _vehicle_anchor(), _floor_top_y())
		if not CLEAN_CANVAS:
			_spawn_bale_yard()   # stays on MainWorld (not in LegacyPropsSpawner spec)
	else:
		print("[MainWorld] WorldLayout is authoritative — skipping legacy utility/demo spawns")
		bale_yard_manager = BaleYardManager.new()
		add_child(bale_yard_manager)
		bale_yard_manager.setup(self, shift_clock)

	# Final LineFlow discovery pass — AFTER every machine exists.
	if line_flow:
		line_flow.rebuild()
	# Crew manager ALWAYS spawns (even with an authoritative layout). It posts
	# the 9 workers to whatever LineFlow machines exist (free-wander if none),
	# and — critically — the HUD crew-assignment panel (C / Numpad-.) bails out
	# when crew_manager is null, so skipping it broke that menu entirely.
	_spawn_crew_manager()
	var shift_lc := ShiftLifecycleManager.new(); add_child(shift_lc); shift_lc.setup(self, shift_clock, staff_parking, _player_spawn_pos)
	var save_coord := SaveCoordinator.new(); add_child(save_coord); save_coord.setup(self, player, game_state, shift_clock, crew_manager)

	# WorldEnvironment + sun are now in the tree — push saved graphics prefs
	# (SSAO / SDFGI / fog / brightness / shadow distance) onto them.
	SettingsManager.refresh_environment()
	TextureKit.apply_textures(self, _shell())
	# #195 — overhead lights now built by InteriorLightingManager via build_all()
	# inside the road-and-parking spawn block (mounts under ShellMesh once it exists).
	_spawn_plant_audio()

	print("[MainWorld] Ready — %d NPCs, shift running: %s" \
		% [npcs.size(), str(shift_clock.shift_active) if shift_clock else "?"])



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

## Look up the building shell via its known scene path AND compute both its
## XZ centre and a footprint polygon (AABB rectangle) in one pass. Used by
## other helpers — find_child("ShellMesh", true, false) returned empty in
## the last test, so we use the explicit path BuildingShell/ShellMesh which
## we know exists in MainWorld.tscn.
func _building_center_and_footprint() -> Dictionary:
	var shell := _shell()
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

const _PLAYER_BODY_LAYER : int = 1 << 1
const _PLAYER_HEAD_LAYER : int = 1 << 2
const _HEAD_Y_THRESHOLD  : float = 0.55

func _set_body_render_layer_split(root: Node) -> void:
	if root is MeshInstance3D:
		var mi := root as MeshInstance3D
		# Local position relative to the Humanoid rig root tells us if this is a
		# head-region box. Walk up from the mesh summing Node3D y positions until
		# we hit the PlayerBody root (orientations are identity inside Humanoid,
		# so summing y is correct).
		var y_local : float = mi.position.y
		var p : Node = mi.get_parent()
		while p != null and (not (p is Node3D) or p.name != "PlayerBody"):
			if p is Node3D:
				y_local += (p as Node3D).position.y
			p = p.get_parent()
		mi.layers = _PLAYER_HEAD_LAYER if y_local >= _HEAD_Y_THRESHOLD else _PLAYER_BODY_LAYER
	for c in root.get_children():
		_set_body_render_layer_split(c)

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
	var marker := _player_spawn_node()
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
# WORLD YAW + LAYOUT TRANSFORMS — moved to WorldFrame.gd (#195).
# =============================================================================
# These thin forwarders preserve every existing call site in MainWorld and its
# children (ExteriorManager calls `_world.call("_bo", ...)` etc.) while the
# canonical yaw math + layout-frame translation now live in the child manager
# spawned at the top of `_ready()` (see `_world_frame`).

func _world_yaw() -> float:
	return _world_frame._world_yaw()

func _building_yaw() -> float:
	return _world_frame._building_yaw()

func _bo(ga: Vector3, offset: Vector3) -> Vector3:
	return _world_frame._bo(ga, offset)

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

## Sanity guard for layout-relative markers (377 km bug): a marker more than
## ~5 km from the anchor is corrupt RD-space leakage, not a real placement.
## Spawning physics bodies that far out breaks float precision → NaN transforms
## → tens of thousands of "!v.is_finite()" render errors that also tank the
## framerate via log I/O. Skip the marker instead.
func _layout_rel_sane(rel: Vector3) -> bool:
	return Vector2(rel.x, rel.z).length() < 5000.0

# Surfaced on the PerfHud overlay so the layout mapping can be sanity-checked.
# Updated by `_layout_to_scene()` on its first call so the string always reflects
# the actual yaw+anchor that ran (not stale boilerplate). PerfHud.gd:88 reads this
# verbatim, so we keep the variable NAME stable and only change its contents.
var layout_conv_summary : String = "Layout: no layout file — vanilla spawn"
var _layout_summary_logged : bool = false

# Layout transforms now live in WorldFrame. Thin forwarders preserve callers.
# `_layout_rel_sane`, `layout_conv_summary` and `_layout_summary_logged` stay
# in MainWorld (PerfHud reads the summary directly; the sanity check is also
# used in _spawn_bale_yards_from_layout()).
func _layout_anchor_xz() -> Vector3:
	return _world_frame._layout_anchor_xz()

func _layout_rotated_offset(rel: Vector3) -> Vector3:
	return _world_frame._layout_rotated_offset(rel)

func _layout_to_scene(rel: Vector3) -> Vector3:
	return _world_frame._layout_to_scene(rel)

## #195 — _vehicle_anchor moved to VehicleSpawner.vehicle_anchor. Forwarder
## kept here so _spawn_lpg_rack (which stays in MainWorld) still gets the same
## anchor it always used.
func _vehicle_anchor() -> Vector3:
	return _get_factory_anchor()

## World Y of the floor's TOP surface — placing a machine so its AABB bottom sits
## at this Y seats it flush on the floor.
func _floor_top_y() -> float:
	return _floor_min_y_cache

func _spawn_merlo() -> void:
	# #195 — _spawn_vehicle_instances moved to VehicleSpawner. _spawn_merlo stays
	# in MainWorld (not in source_functions list), so dispatch through the spawner
	# instance the integration call added under MainWorld.
	var vs : Node = find_child("VehicleSpawner", false, false)
	if vs == null:
		push_warning("[MainWorld] VehicleSpawner not present — _spawn_merlo skipped")
		return
	vs.call("spawn_vehicle_instances", "merlo", "res://src/scenes/vehicles/Merlo.tscn",
		Vector3(15.0, 0.0, 0.0), "Merlo")
	vs.call("spawn_vehicle_instances", "merlo_p40", "res://src/scenes/vehicles/MerloP40.tscn",
		Vector3(22.0, 0.0, 0.0), "Merlo P40")

## Walk the scene tree, build a LiftBooking, register every mast lift instance.
## Called after _spawn_mast_lift; the booking is then handed to every NPC during
## _spawn_crew_manager so the planner can claim lifts at runtime.
var lift_booking : LiftBooking = null







func _process(delta: float) -> void:
	# #195 — the only per-frame work MainWorld owned was the bale-yard drain
	# queue + proximity sweep; both moved to BaleYardManager.tick(). Forward
	# every tick so the spawn queue keeps draining and far yards stay culled.
	if bale_yard_manager != null:
		bale_yard_manager.tick(delta)

# =============================================================================
# SHIFT-LEADER PC — bale yard maintenance buttons (#73, #74)
# =============================================================================
## #195 — Forwarder to BaleYardManager.reset_yard_bales. Kept on MainWorld
## because ShiftLeaderTerminal.gd calls mw.call("reset_yard_bales") on the
## current scene root, so the public name stays here.
func reset_yard_bales() -> int:
	if bale_yard_manager != null:
		return bale_yard_manager.reset_yard_bales()
	return 0

## #195 — Forwarder to BaleYardManager.restock_yard_bales. Kept on MainWorld
## because ShiftLeaderTerminal.gd calls mw.call("restock_yard_bales") on the
## current scene root, so the public name stays here.
func restock_yard_bales() -> int:
	if bale_yard_manager != null:
		return bale_yard_manager.restock_yard_bales()
	return 0

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
# DEMO PIPELINE — a full feeding-belt → extruder line, 300 m down the road
# =============================================================================
## A single-file straight-line layout of every catalog machine in process order
## so the player can see the entire LineFlow in action without having to build
## the line themselves. Sits ~300 m west of the player spawn (out of the way of
## the factory's build zone).
##







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
	# Anchor everything to the captured player spawn. Every local-frame offset
	# below is rotated by the building's principal yaw before being added to
	# the anchor — that's what makes fence/parking/roads wrap a rotated shell
	# correctly instead of running parallel to world X/Z. (Adopts the bale-
	# yard rotation convention; see `_building_yaw`.)
	var anchor : Vector3 = _player_spawn_pos
	var ground_y : float = anchor.y - 1.0      # capsule centre - half-height
	# Canonical yaw — adopts the bale-yard convention so road + parking +
	# fence + props + ceiling lights ALL agree with the operator-drawn yards.
	var by : float = _world_yaw()
	var basis_y := Basis(Vector3.UP, by)
	# Wide exterior ground plane around the anchor so the player can walk
	# outside the building without falling into void.
	_spawn_exterior_ground(anchor, ground_y)
	# Parking lot — 25 m local-west, 8 m local-north of the spawn. The local
	# offset is rotated through `by` so the lot lands beside the building's
	# south face regardless of shell yaw; the parking node's own yaw is set
	# to `by` so its internal local-X (bay rows) × local-Z (length) align
	# with the building wall.
	const PARKING_OFFSET := Vector3(-25.0, 0.0, 8.0)
	var parking_world : Vector3 = basis_y * PARKING_OFFSET
	staff_parking = preload("res://src/scenes/world/StaffParking.gd").new()
	staff_parking.name = "StaffParking"
	add_child(staff_parking)
	staff_parking.global_position = Vector3(
		anchor.x + parking_world.x,
		ground_y + 0.02,
		anchor.z + parking_world.z)
	staff_parking.rotation.y = by
	_spawn_parking_lamps(staff_parking, ground_y)
	# Road — De Asselen Kuil — runs along the building's local west edge
	# (negative local-X), then turns east into the parking aisle. Waypoints
	# are expressed in BUILDING-local coords and rotated by `by`.
	var ga := Vector3(anchor.x, ground_y, anchor.z)
	var road : Road = preload("res://src/scenes/world/Road.gd").new()
	road.name = "DeAsselenKuil"
	road.surface_y = ground_y
	road.setup([
		# Far south end of De Asselen Kuil — extended ~400 m local-south so the
		# player Swift sits at a real "FAR end of the road" approach instead of
		# right next to the parking entry. Long northbound straight gives a
		# clear drive-in cinematic before the east turn into the lot.
		_bo(ga, Vector3(-42.0, 0.0, -440.0)),  # FAR south spawn end
		_bo(ga, Vector3(-42.0, 0.0, -40.0)),   # original south end (now mid-road)
		_bo(ga, Vector3(-42.0, 0.0,   0.0)),   # straight north along west edge
		_bo(ga, Vector3(-42.0, 0.0,  20.0)),   # past parking entry, continues north
		_bo(ga, Vector3(-25.0, 0.0,  30.0)),   # turn east toward plant entry pad
		_bo(ga, Vector3(  0.0, 0.0,  30.0)),   # plant entry pad
	])
	add_child(road)
	_spawn_street_sign(_bo(ga, Vector3(-43.5, 0.0, 0.0)), "De Asselen Kuil")
	# #192 follow-up — road extensions / perimeter fence / exterior props are
	# now owned by ExteriorManager (a child node); it parents its spawned items
	# back under MainWorld so the runtime scene shape is unchanged. Interior
	# TL bars (misnamed "_spawn_floodlights" — actually inside the shell) stay
	# in MainWorld because they belong to the building's interior lighting kit.
	var exterior_mgr := preload("res://src/scenes/world/ExteriorManager.gd").new()
	exterior_mgr.name = "ExteriorManager"
	add_child(exterior_mgr)
	exterior_mgr.build_exterior(anchor, ground_y)
	# #195 — interior lighting (overhead grid + wall-line TL bars) extracted to
	# InteriorLightingManager. Spawns its children under MainWorld so the scene
	# shape is unchanged (OverheadLights node under ShellMesh; InteriorTLBars
	# node under ShellMesh). build_all() runs _spawn_overhead_lights() first
	# then _spawn_floodlights(anchor) to preserve the original side-effect order.
	var lighting := InteriorLightingManager.new()
	lighting.name = "InteriorLightingManager"
	add_child(lighting)
	lighting.setup(self)
	lighting.build_all(anchor)
	print("[MainWorld] Road + parking anchored to player spawn %s (yaw %.1f deg)" \
		% [anchor, rad_to_deg(by)])

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
	# Path routing climb cap — matches NPC.CLIMB_MAX_DY (1.4 m, same as the player
	# vault). Below 0.30 the navmesh bake produced flat-only paths and NPCs got
	# stuck on every bale-yard kerb; above 1.4 they'd try to scale obstacles the
	# vault can't actually complete. Keeps NPCs in lock-step with the vault verb.
	nm.agent_max_climb = 1.40
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
## #5xx — the post is now a StaticBody3D so the player can't phase through
## it. Previously plain MeshInstance3D (collision audit caught).
func _spawn_street_sign(at: Vector3, text: String) -> void:
	var holder := Node3D.new()
	holder.name = "StreetSign_" + text.replace(" ", "_")
	holder.position = at
	add_child(holder)
	# Post body — StaticBody3D + cylinder collider matching the visible mesh
	# so the player bumps the pole instead of phasing through.
	var post_body := StaticBody3D.new()
	post_body.name = "Post"
	post_body.position = Vector3(0.0, 1.3, 0.0)
	holder.add_child(post_body)
	var post := MeshInstance3D.new()
	post.name = "PostMesh"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.035
	cm.height = 2.6
	post.mesh = cm
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.78, 0.78, 0.80)
	post_mat.metallic = 0.6
	post_mat.roughness = 0.4
	post.material_override = post_mat
	post_body.add_child(post)
	var post_col := CollisionShape3D.new()
	post_col.name = "PostCollision"
	var pcy := CylinderShape3D.new()
	pcy.radius = 0.05    # slightly larger than visible so player doesn't squeeze past
	pcy.height = 2.6
	post_col.shape = pcy
	post_body.add_child(post_col)
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

# =============================================================================
# FLOOR GENERATION
# =============================================================================
# World-Y of the floor's top surface. Set by _generate_floor_from_shell from
# the largest-area horizontal slab in the building shell mesh (the operating
# floor — NOT the absolute lowest vertex, which would be foundations/below-grade).
var _floor_min_y_cache: float = -9.0



# =============================================================================
# Helpers
# =============================================================================

func get_npc(npc_id: String) -> Node:
	return npcs.get(npc_id, null)   # forwarded — implementation lives on NPCSpawner (#195)

func get_all_npcs() -> Array:
	return npcs.values()            # forwarded — implementation lives on NPCSpawner (#195)

# ── Save forwarders (#195) — SaveCoordinator owns the real impl. ────────────
func save_game() -> void:
	var sc := find_child("SaveCoordinator", false, false)
	if sc and sc.has_method("save_game"):
		sc.save_game()

func save_and_quit() -> void:
	var sc := find_child("SaveCoordinator", false, false)
	if sc and sc.has_method("save_and_quit"):
		sc.save_and_quit()
	else:
		get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")
