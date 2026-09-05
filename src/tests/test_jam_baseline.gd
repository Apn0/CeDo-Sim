extends Node
# =============================================================================
# npc-06 / npc-07 — NAVIGATION JAM HARNESS.
# =============================================================================
# The four jams this work exists to clear are COORDINATES, not opinions. This
# file boots the REAL MainWorld and measures each one, so every claim about a
# fix has a number behind it.
#
#   GODOT --headless --path . res://src/tests/test_jam_baseline.tscn
#
# DESIGNED TO FAIL ON UNMODIFIED main. On main the baked navmesh is 2 polygons /
# 4 vertices — one featureless 4000 m continent — so every map_get_path returns a
# 2-point straight line through solid geometry. If the mesh checks below ever go
# green WITHOUT the bake changes, they are measuring the wrong object. That is
# the whole point: this project has shipped greens that validated a stub, a
# stale constant, and a test's own ledger, and the only defence is a check that
# is red before the fix.
#
# WHAT IS DELIBERATELY *NOT* ASSERTED HERE:
#   · "map is valid" and NavigationServer3D.map_get_iteration_id. The iteration
#     id measured 2 against the 2-polygon mesh — it counts map syncs, not mesh
#     quality, so any test built on it is vacuous by construction.
#   · mass moved. That belongs to test_npc05_realworld, read FROM THE CONTAINERS.
#     A motion test must not certify a chain it cannot weigh.
# =============================================================================

const TEST_SLOT : String = "__jambaseline__"

const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__jambaseline___save.json",
	"user://__jambaseline___factory.json",
]

# ── Measured jam coordinates (see docs/BACKLOG_ultracode_2026-07-19.md) ───────
# JAM 1 — the yard forklift drives at the plant and wedges against the perimeter
# fence's east end post. Reproduced to 0.13 m across runs, and a control with all
# 339 fence collisions stripped jammed at (-79.95, 157.25) anyway: the fence is
# incidental, the autopilot dead-reckons into whatever is in front of it.
const JAM1_POS : Vector3 = Vector3(-79.90, -7.93, 157.13)
# Start the leg so the straight line to the plant passes THROUGH the jam point.
# Reproducing the mechanism deterministically beats waiting for the emergent
# chain to wander into it: the defect is "drives into the first solid on the
# bearing", and this puts a solid on the bearing every run.
const JAM1_BACKOFF_M : float = 22.0
## How far short of the factory anchor jam 1 parks. The anchor is player_spawn
## and the player occupies it headless, so the ordered goal has to stand off it.
## 4.0 m, from the measured clearance sweep: the nearest hull-clear pose along
## the approach bearing is 2.0 m out, and NPC_ARRIVE_TOL is 2.2 m.
const JAM1_GOAL_STANDOFF_M : float = 4.0

# JAM 3 — the outdoor-skip A/B recorded in ContainerGuide.gd:103-113. Offset
# (12, 0, 45.5) from the factory anchor is 6.9 m past the facade and
# geometrically ideal; the forklift covered 47 m in 141 s (0.33 m/s) and wedged
# 6.95 m short, moving 0 kg. Offset (12, 0, 28.0) is the shipped interim.
const SKIP_OUTDOOR_OFFSET : Vector3 = Vector3(12.0, 0.0, 45.5)
const SKIP_INDOOR_OFFSET  : Vector3 = Vector3(12.0, 0.0, 28.0)

# ── Acceptance thresholds ────────────────────────────────────────────────────
# Mesh quality. Baseline is 2 / 4. A bounded site bake over ~145 machine bodies,
# ~15 belt decks, 339 fence bodies and the platforms cannot land near those
# numbers, so the gap between baseline and threshold is the assertion's teeth.
const MIN_POLYGONS : int = 200
## NOT polygons x 3. Recast merges the voxelised region into CONVEX polygons that
## share vertices, so the vertex count runs BELOW the polygon count on a real
## mesh — measured 279 polygons / 320 vertices on the line_3a fixture. The 400
## first written here was a guess from triangle intuition and it failed a mesh
## that was working; 200 is set from that measurement, and the baseline it has to
## beat is 4.
const MIN_VERTICES : int = 200
# A routed path has interior waypoints. Two points is the straight line.
const MIN_PATH_POINTS : int = 3
# Godot truncates a path at the mesh edge when the goal is off-mesh and returns
# it as a success. Assert the path actually ENDS at the goal.
const PATH_ENDPOINT_TOL_M : float = 1.0
# A leg counts as jammed at a coordinate if it stalled within this of it.
const JAM_RADIUS_M : float = 3.0
const JAM_STALL_S  : float = 2.0
# Total wedge budget for a clean drive leg.
const WEDGE_BUDGET_S : float = 3.0

const BOOT_FRAMES   : int = 120
const SETTLE_FRAMES : int = 60
## 240 s at 60 Hz. RESIZED FROM MEASUREMENT 2026-09-03, not picked: the old
## 7200 (120 s) was too small for jam 1 now that a route through the gate
## exists. probe_pilot_convergence.gd drove that leg to `arrived` in 158 s over
## 279.6 m of path — the straight line is 156 m but the only doorway forces a
## detour, and NPC_CRUISE_FRAC caps the forklift near 1.8 m/s. jam 3 arrives in
## 85 s. 240 s leaves headroom on the slower leg without doubling suite time,
## because the route-progress abort below catches a genuine stall in 40 s.
const DRIVE_FRAMES  : int = 14400
const BAKE_WAIT_FRAMES : int = 600
## 40 s without either reaching the next waypoint or closing half a metre on it.
## Waypoint-relative on purpose — see the long comment in _drive_leg. A
## goal-relative version of this constant is what made a legitimate 58 m detour
## to the plant's only doorway look like a circling vehicle.
const NO_PROGRESS_FRAMES : int = 2400

var _backups : Dictionary = {}
var _fails : int = 0
var _oks   : int = 0
## Checks DOWNGRADED to a report because the world offered no route.
## Counted and printed, never silent. On 2026-08-30 this suite reported
## "11 ok, 0 fail" while THREE of its fourteen checks never ran: both
## "<leg> completed" assertions and "reached the outdoor skip pose" sit behind
## _route_exists(), which was false while the model carved no doorway. That
## green measured a world with nowhere to drive and read exactly like a green
## that measured a working pilot -- and it was quoted as one for four days. A
## skip missing from the verdict line is a lie the harness tells once and
## everybody repeats.
var _skips : int = 0
var _world : Node3D = null
var _anchor : Vector3 = Vector3.ZERO

func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)

## Record a check that could not be evaluated. Prints like a check, counts like
## a check, and lands in the verdict line -- so "0 fail" can never again be read
## as "everything was measured".
func _skip(label: String, why: String) -> void:
	_skips += 1
	print("  SKIP  : %s" % label)
	print("        : %s" % why)

func _info(label: String) -> void:
	print("  info  : %s" % label)

func _section(title: String) -> void:
	print("[%s]" % title)

func _ready() -> void:
	print("=== npc-06/npc-07 — navigation jam harness ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	_backup_files()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(2); return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	_anchor = _resolve_anchor()
	_info("factory anchor resolved at (%.2f, %.2f, %.2f)" % [_anchor.x, _anchor.y, _anchor.z])

	await _build_line_3a()
	await _test_navmesh()
	await _test_interior_routing()
	await _test_jam1()
	await _test_jam3()

	print("\n=========================================")
	print("Result: %s (%d ok, %d fail, %d skipped)"
		% ["PASS" if _fails == 0 else "FAIL", _oks, _fails, _skips])
	if _skips > 0:
		print("NOTE: %d check(s) were NOT evaluated — this PASS is narrower than it looks."
			% _skips)
	print("=========================================")
	_finish(0 if _fails == 0 else 1)

# ── Fixture: the machine row every interior routing claim is measured against ──
# Without machines the interior is an empty slab and "a path exists" proves
# nothing. line_3a is the operator's real line (39 entries since the 2026-08-28
# rulings; it was 42 when this fixture was written) and the same fixture
# tools/regression/run.sh builds, so the two harnesses talk about one plant.
func _build_line_3a() -> void:
	_section("FIXTURE — build line_3a (clean seed)")
	var bm = _world.get("build_mode")
	if bm == null:
		bm = _world.find_child("BuildMode", true, false)
	if bm == null:
		_check(false, "BuildMode present (the machine fixture cannot be built without it)")
		return
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache["line_3a"] = {}
	var start_bf := Vector2(4.0, 22.0)
	var start : Vector3 = Plant.pc_to_scene(_bf_to_pc(start_bf))
	var fdir : Vector3 = (Plant.pc_to_scene(_bf_to_pc(Vector2(5.0, 22.0)))
		- Plant.pc_to_scene(_bf_to_pc(Vector2(4.0, 22.0)))).normalized()
	bm.call("_build_full_line", "line_3a", start, atan2(-fdir.x, -fdir.z))
	for _i in range(20):
		await get_tree().process_frame
	var machines : int = 0
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is StaticBody3D:
			machines += 1
	# DERIVED, not typed. This was `>= 40`, written 2026-07-22 (94c685b) when
	# LINE_3A_SEQ had 42 entries. Operator rulings 5f4e7c3 (2.1-B) and 5b854d8
	# took the line to 39 on 2026-08-28 and the constant never followed, so from
	# that day the check was unsatisfiable by the very fixture it verifies. It
	# kept passing here only while a stale __jambaseline___factory.json (166
	# leftover machines) sat in user://; test_nav_connectivity, whose slot is
	# clean, was red on this exact line the whole time. Measured at 00cc51c2:
	# BuildMode reports "Built line_3a — 39 machines" and every SEQ entry yields
	# one StaticBody3D in the placed_object group, so the counts are equal, not
	# merely >=. Both numbers print so a future non-static SEQ entry shows up as
	# a visible gap instead of a silent false red.
	var seq_n : int = BuildMode.LINE_3A_SEQ.size()
	_check(machines >= seq_n,
		"machine fixture present (%d static placed bodies, LINE_3A_SEQ has %d)"
			% [machines, seq_n])
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

# ── 1. Mesh quality ───────────────────────────────────────────────────────────
func _test_navmesh() -> void:
	_section("NAVMESH QUALITY — the mesh must describe the plant, not one continent")
	var region := _find_nav_region()
	if region == null:
		_check(false, "a NavigationRegion3D exists in the world")
		return
	# The fixture was built AFTER the world's own bake, so ask for a fresh one.
	# Without this the test measures the boot-time mesh and reports "2 polygons"
	# for a plant whose machines went in thirty frames ago — which is exactly the
	# wrong-object mistake these assertions exist to catch.
	if _world.has_method("rebake_navigation"):
		_world.call("rebake_navigation")
	# The bake is threaded. Wait for the count to STOP CHANGING, and never break on
	# the first sample: an early-exit on two equal reads latches onto the stale
	# pre-bake value (measured — it reported 2 while the routing probe on the same
	# mesh already returned 3 points).
	var polys : int = 0
	var verts : int = 0
	var stable : int = 0
	for _i in range(BAKE_WAIT_FRAMES):
		await get_tree().process_frame
		var nm := region.navigation_mesh
		if nm == null:
			continue
		var p : int = nm.get_polygon_count()
		if p == polys:
			stable += 1
			if stable >= 60 and polys > 0:
				break
		else:
			stable = 0
		polys = p
		verts = nm.get_vertices().size()
	_info("baked navmesh: %d polygons, %d vertices" % [polys, verts])
	_check(polys > MIN_POLYGONS,
		"navmesh has real topology (%d polygons, need >%d — baseline is 2)"
			% [polys, MIN_POLYGONS])
	_check(verts > MIN_VERTICES,
		"navmesh has real vertices (%d, need >%d — baseline is 4)"
			% [verts, MIN_VERTICES])

# ── 2. Interior routing ───────────────────────────────────────────────────────
# Two points on opposite sides of the line_3a machine row. On main this returns
# a 2-point straight line THROUGH the machines and reads as success.
func _test_interior_routing() -> void:
	_section("INTERIOR ROUTING — a path around a machine row, not through it")
	var machines := _line_machines()
	if machines.size() < 4:
		_check(false, "enough machines to have a row to route around (%d)" % machines.size())
		return
	# Straddle the row at its middle machine, along the row's local X.
	var mid : Node3D = machines[machines.size() / 2]
	var side : Vector3 = mid.global_transform.basis.x.normalized()
	var a : Vector3 = mid.global_position + side * 6.0
	var b : Vector3 = mid.global_position - side * 6.0
	a.y = mid.global_position.y
	b.y = mid.global_position.y
	var map : RID = _world.get_world_3d().navigation_map
	var path : PackedVector3Array = NavigationServer3D.map_get_path(map, a, b, true)
	_info("path across the row at (%.1f, %.1f) -> (%.1f, %.1f): %d points"
		% [a.x, a.z, b.x, b.z, path.size()])
	_check(path.size() >= MIN_PATH_POINTS,
		"the route around the machine row has interior waypoints (%d points, need >=%d)"
			% [path.size(), MIN_PATH_POINTS])
	# A path that silently truncates at the mesh edge is Godot's failure mode and
	# otherwise reads as success.
	var endp : float = 1e9 if path.is_empty() else Vector2(path[path.size() - 1].x - b.x,
		path[path.size() - 1].z - b.z).length()
	_check(endp <= PATH_ENDPOINT_TOL_M,
		"the route ENDS at the goal, not at the mesh edge (%.2f m off, limit %.1f)"
			% [endp, PATH_ENDPOINT_TOL_M])

# ── 3. JAM 1 ──────────────────────────────────────────────────────────────────
func _test_jam1() -> void:
	_section("JAM 1 — forklift yard->plant, measured wedge at (-79.90, 157.13)")
	var fl := _grab_forklift()
	if fl == null:
		_check(false, "an unoccupied forklift is available to drive")
		return
	var to_plant : Vector3 = (_anchor - JAM1_POS)
	to_plant.y = 0.0
	to_plant = to_plant.normalized()
	var start : Vector3 = JAM1_POS - to_plant * JAM1_BACKOFF_M
	# NOT `_anchor` itself. The factory anchor IS player_spawn — measured
	# 2026-09-03: a 2.4 x 2.2 x 4.0 m hull at the anchor comes back
	# `BLOCKED by ["Player"]`, because the player body stands on that exact
	# point in every headless boot. The forklift drove 352 m, got to 2.32 m of
	# it (tolerance 2.2 m), refused to run the player over, and orbited in EVADE
	# until the budget ran out. Ordering a vehicle into an occupied pose asserts
	# nothing about navigation. Park 4 m short of the anchor on the approach
	# bearing instead: measured `arrived`, 158 s, 279.6 m travelled, best 2.22 m.
	var goal : Vector3 = _anchor - to_plant * JAM1_GOAL_STANDOFF_M
	var leg := await _drive_leg(fl, "jam1_yard_to_plant", start, goal)
	if leg.is_empty():
		return
	var stall : float = VehicleJamRecorder.wedge_seconds_near(leg, JAM1_POS, JAM_RADIUS_M)
	_check(stall < JAM_STALL_S,
		"the forklift did not wedge at the measured jam point (%.1f s stalled within %.1f m, limit %.1f)"
			% [stall, JAM_RADIUS_M, JAM_STALL_S])
	_check(float(leg.get("wedge_seconds", 0.0)) < WEDGE_BUDGET_S,
		"the leg spent under the wedge budget stationary (%.1f s, limit %.1f)"
			% [float(leg.get("wedge_seconds", 0.0)), WEDGE_BUDGET_S])
	# ANTI-VACUITY. A leg that never met an obstacle proves nothing about the
	# recovery, so the pilot must be observed ENGAGING. Zero means the pass is a
	# coincidence and the coordinates need re-measuring before anything is claimed.
	var engaged : int = _pilot_engagements(fl)
	if engaged >= 0:
		_check(engaged > 0,
			"the pilot actually engaged on this leg (%d evade/reverse events — 0 means the pass is a coincidence)"
				% engaged)
	else:
		_info("no pilot on the vehicle yet — engagement counter not available (pre-Step-1 baseline)")

# ── 4. JAM 3 ──────────────────────────────────────────────────────────────────
func _test_jam3() -> void:
	_section("JAM 3 — indoor skip -> outdoor skip pose, measured 6.95 m short at 0.33 m/s")
	var fl := _grab_forklift()
	if fl == null:
		_check(false, "an unoccupied forklift is available for the outdoor leg")
		return
	var start : Vector3 = _anchor + SKIP_INDOOR_OFFSET
	var goal  : Vector3 = _anchor + SKIP_OUTDOOR_OFFSET
	var leg := await _drive_leg(fl, "jam3_indoor_to_outdoor", start, goal)
	if leg.is_empty():
		return
	# npc-06/07 — same split as _drive_leg: the outdoor skip pose sits on the far
	# side of the facade, and this world models NO doorways (structure_items is
	# empty), so the router returns a 0-point route and no pilot can arrive. That
	# is a missing-door DATA gap, not a driving defect, so it is reported loudly
	# instead of gating. It becomes a hard check the moment a gate is placed.
	if not _route_exists(fl):
		_skip("the forklift reached the outdoor skip pose (%.2f m away)"
				% float(leg.get("final_dist_m", 1e9)),
			"no vehicle route to the target — the model carves no doorway the router "
			+ "accepts. Not a pilot failure. Place a gate/door and this becomes a hard check.")
	else:
		_check(float(leg.get("final_dist_m", 1e9)) <= 3.5,
			"the forklift reached the outdoor skip pose (%.2f m, limit 3.5 — baseline was 6.95 m short)"
				% float(leg.get("final_dist_m", 1e9)))
	_check(float(leg.get("wedge_seconds", 0.0)) < WEDGE_BUDGET_S,
		"the outdoor leg spent under the wedge budget stationary (%.1f s, limit %.1f)"
			% [float(leg.get("wedge_seconds", 0.0)), WEDGE_BUDGET_S])
	# REPORTED, NOT ASSERTED. The 0.33 m/s figure in the ContainerGuide A/B is a
	# 47 m / 141 s AVERAGE, and the measured stall is a dead stop at 0.00 m/s — so
	# a "no creep band" check passes on the broken baseline too. It would have been
	# a green that proved nothing; the wedge budget above is the check with teeth.
	if _creep_stall(leg):
		_info("trace contains a 0.20-0.45 m/s stretch with the distance not closing")

# ── Drive-leg driver ──────────────────────────────────────────────────────────
# Teleports the vehicle to `start` (a test fixture, not a behaviour), orders it
# to `goal` through the REAL npc_set_target entry point — never around it, so
# the NPC_TARGET_MAX_R guard stays on the path — and records the leg.
func _drive_leg(fl: Node3D, leg_name: String, start: Vector3, goal: Vector3) -> Dictionary:
	var ground_y : float = _ground_y_at(start)
	fl.global_position = Vector3(start.x, ground_y + 1.2, start.z)
	fl.rotation = Vector3.ZERO
	for _i in range(20):
		await get_tree().physics_frame
	# ANTI-VACUITY. A leg that starts on the roof drives 20 m unobstructed and
	# passes every check below while proving nothing about the plant floor. The
	# first run of this harness did exactly that, so the elevation is asserted.
	_check(absf(fl.global_position.y - _anchor.y) <= 3.0,
		"%s starts on the operating floor, not a roof (y=%.2f, floor %.2f)"
			% [leg_name, fl.global_position.y, _anchor.y])

	var rec := VehicleJamRecorder.new()
	rec.name = "JamRecorder"
	fl.add_child(rec)
	rec.watch(fl)
	rec.begin_leg(leg_name, goal)
	if not fl.has_method("npc_set_target"):
		_check(false, "the forklift exposes npc_set_target")
		rec.queue_free()
		return {}
	fl.call("npc_set_target", goal)
	# ANTI-VACUITY. Record how many waypoints the router produced. A leg that
	# arrives on a 0-point route arrived by dead reckoning down a lucky straight
	# line, and crediting the router for it would be the same class of claim as
	# "31/31 green while zero kilograms moved".
	if fl.has_method("npc_route_points"):
		rec.note_path_points(int(fl.call("npc_route_points")))
	# Was the ordered pose inside STATIC geometry? Reported, not asserted: the
	# arithmetic is proved deterministically by test_route_goal_clearance.
	#
	# READ THIS NUMBER NARROWLY. VehicleRouteGrid._blocks() only counts
	# StaticBody3D, so 0.00 m means "no machine or wall here", NOT "nobody is
	# standing here". jam1's original goal — the factory anchor, which IS
	# player_spawn — reports 0.00 m while a hull probe there returns
	# BLOCKED by ["Player"]. That is why jam1 parks JAM1_GOAL_STANDOFF_M short
	# instead of relying on this line to catch it.
	if fl.has_method("npc_goal_clearance_m"):
		var gc : float = float(fl.call("npc_goal_clearance_m"))
		if gc < 0.0:
			_info("%s ordered goal: NO standable cell found at all" % leg_name)
		elif gc <= 0.0001:
			_info("%s ordered goal sits on free ground (clearance 0.00 m)" % leg_name)
		else:
			_info("%s ordered goal is %.2f m from standable ground%s"
				% [leg_name, gc,
					" — FURTHER than the 2.2 m arrival tolerance, so this leg cannot complete"
						if gc > 2.2 else ""])

	var outcome := "timeout"
	# Early abort on non-convergence. A vehicle that circles closes no distance,
	# and burning the full budget to learn that costs ~20 minutes of wall clock per
	# leg. "stalled" and "timeout" are BOTH failures — this only makes the failure
	# arrive sooner, it can never turn a red into a green.
	# PROGRESS IS MEASURED ALONG THE ROUTE, NOT AS THE CROW FLIES.
	#
	# This used to watch the straight-line XZ distance to `goal` and abort when
	# it stopped shrinking. That metric cannot work in this plant and it produced
	# two false reds for four days. The building has exactly ONE doorway, the
	# 3A/3B gate. jam3's goal is 17.5 m from its start, but the route out runs
	# 58 m in the OPPOSITE direction to reach that gate, so the straight-line
	# distance is guaranteed to grow for the whole outbound run. Measured
	# 2026-09-03 with src/tests/probe_pilot_convergence.gd: the forklift ticks
	# all six waypoints and ARRIVES in 85 s, 148.4 m travelled, pilot in RUN the
	# whole way. The old abort fired at 40 s and reported "57.34 m from target"
	# — which is exactly where the vehicle was at t=46 s, driving correctly.
	#
	# A vehicle that is genuinely circling advances no waypoint AND closes on
	# none, so this is strictly the more sensitive test of the two, not a
	# loosening.
	var best_idx : int = -1
	var best_wp_d : float = INF
	var since_gain : int = 0
	for _i in range(DRIVE_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(fl):
			outcome = "vehicle_gone"
			break
		if bool(fl.call("npc_arrived")):
			outcome = "arrived"
			break
		# With a 0-point route _npc_target IS the goal, so this degrades to the
		# old straight-line behaviour exactly where that behaviour was correct.
		var idx : int = int(fl.get("_npc_route_i"))
		var wp : Vector3 = fl.get("_npc_target")
		var d_wp : float = Vector2(fl.global_position.x - wp.x, fl.global_position.z - wp.z).length()
		if idx > best_idx:
			best_idx = idx
			best_wp_d = d_wp
			since_gain = 0
		elif d_wp < best_wp_d - 0.5:
			best_wp_d = d_wp
			since_gain = 0
		else:
			since_gain += 1
			if since_gain > NO_PROGRESS_FRAMES:
				outcome = "stalled"
				break
	rec.end_leg(outcome)
	var leg : Dictionary = rec.leg(leg_name)
	print("  trace : %s" % VehicleJamRecorder.describe(leg))
	if fl.has_method("npc_stop"):
		fl.call("npc_stop")
	rec.queue_free()
	# npc-06/07 — separate "the pilot failed" from "the world has nowhere to go".
	# Both jam-1 and jam-3 targets sit on the far side of the building facade, and
	# this world models NO doorways at all (world_layout structure_items is empty),
	# so the router correctly returns a 0-point route. No code change can make a
	# vehicle cross a solid wall, and gating on it would leave a permanently red
	# harness step — which trains everyone to ignore the harness, the same damage
	# a vacuous green does from the other side. The WEDGE assertions stay hard;
	# only unreachability is downgraded, and it is reported loudly every run.
	if outcome != "arrived" and not _route_exists(fl):
		_skip("%s completed (outcome '%s')" % [leg_name, outcome],
			"no vehicle route to the target — the model carves no doorway the router "
			+ "accepts. Not a pilot failure. Place a gate/door and this becomes a hard check.")
		return leg
	_check(outcome == "arrived", "%s completed (outcome '%s')" % [leg_name, outcome])
	return leg

## True when the router can still offer this vehicle a path to its current
## target. False means the destination is unreachable geometry, not a bad driver.
func _route_exists(fl: Node) -> bool:
	if fl == null or not is_instance_valid(fl):
		return false
	if not fl.has_method("npc_route_points"):
		return true   # no router introspection → treat as reachable, keep the check hard
	return int(fl.call("npc_route_points")) > 0

## True when the trace contains the measured ease-in grind: speed parked in the
## 0.20-0.45 m/s band while the distance to target fails to close.
func _creep_stall(leg_dict: Dictionary) -> bool:
	var samples : Array = leg_dict.get("samples", [])
	for i in range(samples.size()):
		var s : Dictionary = samples[i]
		var sp : float = float(s.get("speed", 0.0))
		if sp < 0.20 or sp > 0.45:
			continue
		# Look 3 s ahead: did the distance drop by more than half a metre?
		var j : int = mini(i + 3, samples.size() - 1)
		if j <= i:
			continue
		if float(s.get("dist", 0.0)) - float((samples[j] as Dictionary).get("dist", 0.0)) <= 0.5:
			return true
	return false

# ── Helpers ───────────────────────────────────────────────────────────────────

## Evade + recovery-reverse events the pilot logged, or -1 when the vehicle has
## no pilot (pre-Step-1). Read through get() so this file works on both.
func _pilot_engagements(fl: Node3D) -> int:
	if not ("evade_count" in fl and "recovery_reverse_count" in fl):
		return -1
	return int(fl.get("evade_count")) + int(fl.get("recovery_reverse_count"))

func _find_nav_region() -> NavigationRegion3D:
	return _world.find_child("NavRegion", true, false) as NavigationRegion3D

## Machines belonging to the line_3a fixture, ordered along the row.
func _line_machines() -> Array[Node3D]:
	var out : Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is StaticBody3D and n.has_meta("macro_id") and String(n.get_meta("macro_id")) == "line_3a":
			out.append(n as Node3D)
	if out.is_empty():
		for n in get_tree().get_nodes_in_group("placed_object"):
			if n is StaticBody3D:
				out.append(n as Node3D)
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.x < b.global_position.x)
	return out

## An unoccupied forklift, taken off autopilot so a crew task cannot fight the
## test for the wheel.
func _grab_forklift() -> Node3D:
	for v in get_tree().get_nodes_in_group("forklift"):
		if not (v is Node3D and is_instance_valid(v)):
			continue
		if "occupied" in v and bool(v.occupied):
			continue
		if "npc_owned" in v and bool(v.npc_owned):
			continue
		return v as Node3D
	return null

## Factory anchor, derived from the world's own outdoor skip rather than a
## constant: this project has already been burned by a site map validated
## against a copy of its own stale constant.
func _resolve_anchor() -> Vector3:
	for c in get_tree().get_nodes_in_group("waste_container_outdoor"):
		if c is Node3D:
			return (c as Node3D).global_position - SKIP_INDOOR_OFFSET
	var wl := get_node_or_null("/root/WorldLayout")
	if wl != null:
		var ps = wl.get("player_spawn")
		if ps is Vector3:
			return ps as Vector3
	return Vector3(-202.66, -9.0, 94.04)

## Floor height under `pos`. The probe starts 2 m up, NOT 40 m: an indoor point
## probed from above the building finds the ROOF and the fixture then drives the
## forklift across it — measured, first run of this harness, which produced a
## clean 20.5 m "drive" at 8 m altitude and a green that meant nothing.
func _ground_y_at(pos: Vector3) -> float:
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, pos.y + 2.0, pos.z), Vector3(pos.x, pos.y - 60.0, pos.z))
	var hit := space.intersect_ray(q)
	return float((hit as Dictionary).get("position", Vector3(0.0, -9.0, 0.0)).y) if hit else -9.0

## Building-frame -> plant-coordinate basis. Same triple regression_world_save.gd
## uses (BF_O / BF_XU / BF_ZU, :31-33) so both harnesses build the line_3a
## fixture at the identical anchor and their measurements stay comparable.
const BF_O  : Vector2 = Vector2(573.404, 463.647)
const BF_XU : Vector2 = Vector2(-0.64279, 0.76604)
const BF_ZU : Vector2 = Vector2(-0.76604, -0.64279)

func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU

func _finish(code: int) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
	await get_tree().process_frame
	_restore_files()
	get_tree().quit(code)

func _backup_files() -> void:
	for p in PROTECT:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_buffer(f.get_length())
			f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in PROTECT:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(data)
			f.close()
