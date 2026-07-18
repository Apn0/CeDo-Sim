extends "res://src/scenes/world/GauntletWorld.gd"
##
## #225 — NPC TASK BENCH: a clean flat world for testing the whole crew stack.
##
## Operator spec (2026-07-12): three production lines, each
##   feeder belt (opzetband) → shredder → wash (frictiewasser + flotation) →
##   extruder → standalone laserfilter → TWO lump carts at the discharge.
## So: 3 extruder-operator positions + 3 feeder positions + the general
## housekeeping bait (waste containers, film pile under a conveyor, leaf
## blower + jerrycan) — everything the NpcAutonomyBoard scans for.
##
## Unlike GauntletWorld (visual-only), this bench runs the REAL behaviour
## systems: hand-spawned NPC.gd workers, CrewManager (production-first gate +
## role/section posting), the NpcAutonomyBoard autoload (auto task assignment),
## and the CrewPanel (C / Numpad-.) for manual role + task assignment.
##
## The lump discharge is LIVE: each standalone laser_filter runs LaserFilter.gd
## — TWO vertical afvoervijzel nozzles (aisle +X / wall -X) drop rope chunks
## into the cart parked under each, on the bordes. Proven headless by
## src/tests/test_npc_task_bench.gd (chunks land in carts, never on extruder).

const NPCScript      = preload("res://src/scenes/world/NPC.gd")
const HumanoidScript = preload("res://src/scenes/world/Humanoid.gd")
const FloorPileScript = preload("res://src/sim/FloorPile.gd")
const LineFlowScript = preload("res://src/sim/LineFlow.gd")
const CrewManagerScript = preload("res://src/scenes/world/CrewManager.gd")
const ShiftClockScript  = preload("res://src/scenes/world/ShiftClock.gd")

# ── MainWorld stand-in (#225) ────────────────────────────────────────────────
# NpcAutonomyBoard._find_main_world duck-types on `_player_spawn_pos in node`;
# once matched it also calls _bo() and reads shift_clock — implement all three
# or trade benign degradation for crashes.
var _player_spawn_pos : Vector3 = Vector3(-16.0, 1.0, 8.0)
var shift_clock : Node = null
func _bo(anchor: Vector3, offset: Vector3) -> Vector3:
	return anchor + offset   # flat bench: no building rotation to apply

# ── Layout ───────────────────────────────────────────────────────────────────
const LINE_X : Array = [-12.0, 0.0, 12.0]
const EXTRUDER_IDS : Array = ["extruder_3a", "extruder_3b", "extruder_1"]
const CHAIN_IDS : Array = ["opzetband_3a3b", "shredder_1", "friction_washer", "flotation_tank"]
const CHAIN_GAP_M : float = 1.0
# Extra post-placement clearance (m) for machines whose baked model overhangs
# their catalog size.z. shredder_1's discharge conveyor head reaches ~+8.86 m
# from center vs the +2.5 m footprint edge → +3.9 m puts the washer under it.
const CHAIN_POST_CLEAR : Dictionary = {"shredder_1": 3.9}
const CHAIN_Z_START : float = -22.0
# Twin discharge: vertical nozzles at filter-local ±1.30 (aisle +X / wall -X),
# a cart under each (LaserFilter.eject_local_offset / eject_wall_local).
# The extruder is 2.6 m wide (±1.3) × 14 m long — so the filter sits 3.5 m out
# to the side, which puts the WALL nozzle at 3.5-1.30 = 2.2 (clear of the
# extruder edge at 1.3) and the AISLE nozzle at 4.8. Both clear.
const NOZZLE_DX     : float = 1.30   # eject offset from filter centre (both sides)
const FILTER_SIDE_X : float = 3.5
const CART_AISLE_X  : float = FILTER_SIDE_X + NOZZLE_DX   # 4.8 — aisle (+X) cart
const CART_WALL_X   : float = FILTER_SIDE_X - NOZZLE_DX   # 2.2 — wall  (-X) cart
const PLATFORM_Y    : float = 0.12   # bordes deck top — filter + carts stand on it

var _rig_root : Node3D = null
var crew_manager : Node = null
var line_flow : Node = null
var npcs : Dictionary = {}
var _hud : Node = null
var _npc_variant : int = 0

# ── Observer camera (#225) — O cycles player → plant overview → line-B
# discharge close-up. Purely for WATCHING the crew/discharge work; the player
# body keeps simulating. (NOT an F-key: F8 = editor stop shortcut when the
# game runs embedded — it killed the session.)
var _obs_cam : Camera3D = null
var _obs_mode : int = 0
const _OBS_VIEWS : Array = [
	# [position, look_at] — view 1: whole bench from the south-east, high
	[Vector3(26.0, 24.0, -10.0), Vector3(0.0, 0.0, 12.0)],
	# view 2: line-B laserfilter twin discharge — both nozzles + both carts
	[Vector3(11.5, 3.4, 12.5), Vector3(3.5, 0.9, 17.5)],
]

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_O:
		_cycle_observer()
		get_viewport().set_input_as_handled()
		return
	super._input(event)

func _cycle_observer() -> void:
	_obs_mode = (_obs_mode + 1) % (_OBS_VIEWS.size() + 1)
	if _obs_mode == 0:
		if _obs_cam != null:
			_obs_cam.current = false
		var pc : Camera3D = _player.find_child("Camera3D", true, false) if _player != null else null
		if pc != null:
			pc.current = true
		print("[NpcTaskBench] observer OFF (player cam)")
		return
	if _obs_cam == null:
		_obs_cam = Camera3D.new()
		_obs_cam.name = "ObserverCam"
		add_child(_obs_cam)
	var v : Array = _OBS_VIEWS[_obs_mode - 1]
	_obs_cam.global_position = v[0]
	_obs_cam.look_at(v[1] as Vector3, Vector3.UP)
	_obs_cam.current = true
	print("[NpcTaskBench] observer view %d" % _obs_mode)

func _ready() -> void:
	_build_bench_floor()
	_build_sky_light()
	_build_rig()
	_build_navmesh()
	_build_player()
	if _player != null:
		_player.global_position = _player_spawn_pos
	OperatorContext.spawn_under(self, _player)
	_spawn_systems()
	_spawn_crew()
	_spawn_build_mode()
	_spawn_hud()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[NpcTaskBench] bench ready — 3 lines, %d NPCs, CrewPanel on C / Numpad-." % npcs.size())

## Fixed slab spanning X -22..+22, Z -27..+41 — covers the machine field AND
## the NpcAutonomyBoard's mw_ref-null cleaning-circuit waypoint span.
func _build_bench_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "BenchFloor"
	floor_body.add_to_group("navmesh_source")
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(44.0, FLOOR_THICKNESS_M, 68.0)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.30, 0.32)
	mat.roughness = 0.88
	mesh.material_override = mat
	mesh.position = Vector3(0.0, -FLOOR_THICKNESS_M * 0.5, 7.0)
	floor_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = bm.size
	col.shape = bx
	col.position = mesh.position
	floor_body.add_child(col)

## Bake a navmesh over the floor so NPC NavigationAgent3D pathing works.
## Machines are NOT parsed as obstacles (v1 — task logic is under test here,
## not local avoidance); agents may clip machine footprints while walking.
func _build_navmesh() -> void:
	var region := NavigationRegion3D.new()
	region.name = "NavRegion"
	add_child(region)
	var nm := NavigationMesh.new()
	nm.cell_size = 0.25
	nm.cell_height = 0.25
	nm.agent_radius = 0.4
	nm.agent_height = 1.8
	nm.agent_max_climb = 0.5
	nm.agent_max_slope = 45.0
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "navmesh_source"
	region.navigation_mesh = nm
	region.bake_navigation_mesh(false)   # blocking bake at boot — flat slab, cheap

## The 3 production lines + discharge carts + housekeeping bait + forklift.
func _build_rig() -> void:
	var prev_labels : bool = PlaceableCatalog.emit_name_labels
	PlaceableCatalog.emit_name_labels = false
	_rig_root = Node3D.new()
	_rig_root.name = "RigRoot"
	add_child(_rig_root)

	for li in LINE_X.size():
		var lx : float = float(LINE_X[li])
		var zc : float = CHAIN_Z_START
		# feeder belt → shredder → wash chain, centres advanced by footprint+gap
		for id in CHAIN_IDS:
			var item : Dictionary = PlaceableCatalog.get_item(String(id))
			var depth : float = (item.get("size", Vector3.ONE) as Vector3).z
			zc += depth * 0.5
			_place(String(id), Vector3(lx, 0.0, zc))
			# _m_shredder_1 bakes a 35° discharge conveyor whose head pulley reaches
			# ~6.4 m past its +Z footprint edge, which size.z (5.0) does NOT advertise
			# — so the next machine landed UNDER the belt and got skewered (operator
			# 2026-07-16: exit belt runs through the friction washer). Add the belt's
			# forward overhang as extra clearance so the washer sits under the
			# discharge head and receives material instead of being impaled.
			zc += depth * 0.5 + CHAIN_GAP_M + CHAIN_POST_CLEAR.get(String(id), 0.0)
		# extruder
		var ex_item : Dictionary = PlaceableCatalog.get_item(String(EXTRUDER_IDS[li]))
		var ex_depth : float = (ex_item.get("size", Vector3.ONE) as Vector3).z
		zc += ex_depth * 0.5
		var ex_z : float = zc
		_place(String(EXTRUDER_IDS[li]), Vector3(lx, 0.0, ex_z))
		# standalone LIVE laserfilter on its afvoer-bordes, twin nozzles ±X
		var lf_z : float = ex_z + 3.5
		var lf_x : float = lx + FILTER_SIDE_X
		# the bordes (platform + oprit) the filter + BOTH carts stand on
		_place("lump_platform", Vector3(lf_x, 0.0, lf_z))
		var lf : Node3D = _place("laser_filter", Vector3(lf_x, PLATFORM_Y, lf_z))
		# BENCH DEMO FEED — no ExtruderMachine sim brains in bench v1, so nothing
		# would drive feed_throughput and the discharge would sit dead. Feed the
		# filter a realistic line rate so lumps visibly purge into the carts.
		if lf != null and lf.has_method("set_feed_throughput"):
			lf.call("set_feed_throughput", 450.0)
		# TWO lump carts per extruder (operator spec 2026-07-14): one under EACH
		# vertical nozzle — aisle (+X, in front of the disc face) and wall (-X,
		# behind it) — on the bordes, with a yellow spot under each.
		_place("lump_cart_spot", Vector3(lx + CART_AISLE_X, PLATFORM_Y, lf_z))
		_place("lump_cart",      Vector3(lx + CART_AISLE_X, PLATFORM_Y, lf_z))
		_place("lump_cart_spot", Vector3(lx + CART_WALL_X,  PLATFORM_Y, lf_z))
		_place("lump_cart",      Vector3(lx + CART_WALL_X,  PLATFORM_Y, lf_z))

	# ── housekeeping bait (the NpcAutonomyBoard group scan finds these) ──
	_place("waste_container", Vector3(-18.0, 0.0, 30.0))
	_place("waste_container", Vector3( 18.0, 0.0, 30.0))
	_place("tool_leafblower", Vector3(-19.0, 0.0, 4.0))
	_place("tool_jerrycan",   Vector3(-19.0, 0.0, 5.0))
	# film pile ON THE FLOOR UNDER the line-B feeder belt (operator: "film
	# which is falling on the floor underneath conveyors")
	var pile := FloorPileScript.new()
	pile.name = "FilmPile"
	_rig_root.add_child(pile)
	pile.global_position = Vector3(1.6, 0.0, -14.0)
	if pile.has_method("add"):
		pile.call("add", 80.0, 40.0)   # 80 kg loose film — above the 60 kg shovel threshold
	# forklift for the empty-lump-cart haul; nothing tags the group globally
	# yet (#201/#202 pending) so the bench tags it for the task's availability
	# check.
	var fork : Node3D = _place("vehicle_forklift", Vector3(18.0, 0.0, -8.0))
	if fork != null:
		fork.add_to_group("forklift")

	PlaceableCatalog.emit_name_labels = prev_labels

func _place(id: String, pos: Vector3) -> Node3D:
	var n : Node3D = PlaceableCatalog.build_node(id, false, false)
	if n == null:
		push_warning("[NpcTaskBench] catalog id missing: %s" % id)
		return null
	_rig_root.add_child(n)
	n.global_position = pos
	return n

## Live systems: ShiftClock + LineFlow (auto-discovery best-effort) +
## CrewManager wired exactly like MainWorld does.
func _spawn_systems() -> void:
	shift_clock = ShiftClockScript.new()
	shift_clock.name = "ShiftClock"
	add_child(shift_clock)
	line_flow = LineFlowScript.new()
	line_flow.name = "LineFlow"
	add_child(line_flow)
	if line_flow.has_method("rebuild"):
		line_flow.call("rebuild")

func _spawn_crew() -> void:
	# 8 workers: 3 extruder ops + 3 feeders (operator spec), 1 all-rounder for
	# housekeeping, 1 shift leader (receives NO automatic tasks — the role-gate
	# negative control). npc_role here is the BENCH assignment; the CrewPanel
	# can re-assign live.
	var roster : Array = [
		{"nm": "Pascal",     "role": "extruder_op",      "pos": Vector3(LINE_X[0] - 2.5, 1.0, 22.0), "col": Color.YELLOW},
		{"nm": "Kevin",      "role": "extruder_op",      "pos": Vector3(LINE_X[1] - 2.5, 1.0, 22.0), "col": Color.GREEN},
		{"nm": "Emrah",      "role": "extruder_op",      "pos": Vector3(LINE_X[2] - 2.5, 1.0, 22.0), "col": Color.WHITE},
		{"nm": "Abdellilah", "role": "permanent_feeder", "pos": Vector3(LINE_X[0] - 2.5, 1.0, -18.0), "col": Color.ORANGE},
		{"nm": "Mohammed",   "role": "permanent_feeder", "pos": Vector3(LINE_X[1] - 2.5, 1.0, -18.0), "col": Color.TOMATO},
		{"nm": "Yassine",    "role": "permanent_feeder", "pos": Vector3(LINE_X[2] - 2.5, 1.0, -18.0), "col": Color.LIGHT_GRAY},
		{"nm": "Vincent",    "role": "all_rounder",      "pos": Vector3(-6.0, 1.0, 8.0),  "col": Color.CORNFLOWER_BLUE},
		{"nm": "Romain",     "role": "shift_leader",     "pos": Vector3(6.0, 1.0, 8.0),   "col": Color.CYAN},
	]
	for r in roster:
		var npc := _spawn_npc(String(r["nm"]), String(r["role"]), r["col"] as Color, r["pos"] as Vector3)
		npcs[String(r["nm"]).to_lower()] = npc
	crew_manager = CrewManagerScript.new()
	crew_manager.name = "CrewManager"
	add_child(crew_manager)
	var break_pos := Vector3(0.0, 0.0, 38.0)   # "canteen" corner of the slab
	crew_manager.call("setup", npcs, line_flow, shift_clock, break_pos)

func _spawn_npc(nm: String, role: String, color: Color, pos: Vector3) -> CharacterBody3D:
	var npc : CharacterBody3D = CharacterBody3D.new()
	npc.set_script(NPCScript)
	npc.name = nm
	npc.set("npc_name", nm)
	npc.set("npc_role", role)
	add_child(npc)
	npc.global_position = pos
	var body : Node3D = HumanoidScript.build(color, _npc_variant, {})
	body.name = "HumanoidBody"     # NPC._physics_process scales it for crouch/prone
	_npc_variant += 1
	npc.add_child(body)
	var col := CollisionShape3D.new()
	col.name = "BodyCollision"     # NPC resizes the capsule for crouch/prone
	var cap := CapsuleShape3D.new()
	cap.radius = 0.3
	cap.height = 1.8
	col.shape = cap
	npc.add_child(col)
	npc.set("managed", true)
	npc.set("on_duty", true)
	npc.set("task_state", NPCScript.Task.AT_POST)
	return npc

## Own layout file + wipe on boot — the bench is a TEST RIG, not a save file
## (same #223 rule as the extruder gauntlet).
func _spawn_build_mode() -> void:
	if _player == null:
		push_warning("[NpcTaskBench] BuildMode skipped — no player")
		return
	var bm := BM.new()
	bm.name = "BuildMode"
	bm.player_body = _player
	bm.wall_openings = null
	bm.layout_path = "user://npc_task_bench_layout.json"
	bm.allow_legacy_fallback = false
	bm.load_shared_structure = false
	DirAccess.remove_absolute("user://npc_task_bench_layout.json")
	add_child(bm)

## Override: HUD only auto-wires crew_manager from a MainWorld current_scene
## (HUD._connect_signals) — hand it ours so the CrewPanel key works here.
func _spawn_hud() -> void:
	var hud_scene := load("res://src/scenes/hud/HUD.tscn") as PackedScene
	if hud_scene == null:
		push_error("[NpcTaskBench] HUD.tscn not found")
		return
	_hud = hud_scene.instantiate()
	add_child(_hud)
	if crew_manager != null and "crew_manager" in _hud:
		_hud.set("crew_manager", crew_manager)
