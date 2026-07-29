extends Node
# =============================================================================
# npc-07 — THE NAVMESH MUST NOT HAVE SEALED THE PLANT.
# =============================================================================
# Carving machines into the navmesh is the fix. Sealing the crew inside (or
# outside) the building is the way that fix goes wrong, and it goes wrong
# QUIETLY: a sealed plant produces tasks that never start, not errors.
#
#   GODOT --headless --path . res://src/tests/test_nav_connectivity.tscn
#
# WHY THIS FILE EXISTS RATHER THAN TRUSTING MainWorld._verify_nav_connectivity.
# That guard is VACUOUS as shipped and this test is the thing that proves it:
#   · its "exterior" endpoint is `_player_spawn_pos` (MainWorld.gd:1017), which is
#     the LAYOUT ANCHOR — a point INSIDE the plant. It never tested an
#     inside->outside route at all, only inside->inside.
#   · because that anchor sits within 5 m of the shell's own centre, the guard
#     takes its `endpoints coincide — check skipped` branch (MainWorld.gd:1018)
#     on every single boot. Measured: 1 skip, 0 checks, across a full harness run.
# A guard that has never once executed is not a safety net, so the endpoints here
# are derived from the shell's MEASURED footprint and asserted to be genuinely on
# opposite sides of the facade before any path is requested.
#
# MUTATION-TESTABLE ON DEMAND: flip MainWorld.NAV_BAKE_SHELL (MainWorld.gd:906)
# to true and INSIDE_OUTSIDE must go red. That flag is the only thing standing
# between this world and a sealed one, so a test that cannot detect the flip is
# not testing connectivity.
# =============================================================================

const TEST_SLOT : String = "__navconn__"

const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__navconn___save.json",
	"user://__navconn___factory.json",
]

## How far beyond the shell footprint the exterior probe sits. Far enough to be
## unambiguously outside, close enough to still be on the baked apron.
const EXTERIOR_MARGIN_M : float = 18.0
## A path must end this close to the goal. Godot truncates a path at the mesh
## edge and returns it as a success, so the endpoint is the real assertion.
const PATH_ENDPOINT_TOL_M : float = 1.5
## Crew posts get more slack: a post can legitimately sit inside a machine's
## eroded footprint, and the nearest mesh point is then a metre or two away.
const POST_ENDPOINT_TOL_M : float = 3.0

const BOOT_FRAMES   : int = 120
const SETTLE_FRAMES : int = 60
const BAKE_WAIT_FRAMES : int = 600

var _backups : Dictionary = {}
var _fails : int = 0
var _oks   : int = 0
var _world : Node3D = null

func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)

func _info(label: String) -> void:
	print("  info  : %s" % label)

func _section(title: String) -> void:
	print("[%s]" % title)

func _ready() -> void:
	print("=== npc-07 — navmesh connectivity (plant not sealed) ===")
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

	await _build_line_3a()
	await _wait_for_bake()
	_test_machine_carve()
	_test_inside_outside()
	_test_crew_posts()

	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)"
		% ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	_finish(0 if _fails == 0 else 1)

# ── Fixture ───────────────────────────────────────────────────────────────────
# The same line_3a the other two harnesses build. Connectivity measured on an
# EMPTY shell is meaningless: with nothing carved, everything is trivially
# reachable and the test would pass on the broken 2-polygon baseline too.
func _build_line_3a() -> void:
	_section("FIXTURE — build line_3a (clean seed)")
	var bm = _world.get("build_mode")
	if bm == null:
		bm = _world.find_child("BuildMode", true, false)
	if bm == null:
		_check(false, "BuildMode present (connectivity on an empty shell proves nothing)")
		return
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache["line_3a"] = {}
	var start : Vector3 = Plant.pc_to_scene(_bf_to_pc(Vector2(4.0, 22.0)))
	var fdir : Vector3 = (Plant.pc_to_scene(_bf_to_pc(Vector2(5.0, 22.0)))
		- Plant.pc_to_scene(_bf_to_pc(Vector2(4.0, 22.0)))).normalized()
	bm.call("_build_full_line", "line_3a", start, atan2(-fdir.x, -fdir.z))
	for _i in range(20):
		await get_tree().process_frame
	var machines : int = 0
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is StaticBody3D:
			machines += 1
	_check(machines >= 40, "machine fixture present (%d static placed bodies)" % machines)
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

## Re-bake with the fixture in, then wait for the polygon count to STOP moving.
## Never break on the first pair of equal reads — that latches the stale pre-bake
## value (measured in the sibling harness: it reported 2 polygons while a routing
## probe on the same mesh already returned 3 points).
func _wait_for_bake() -> void:
	_section("BAKE")
	if _world.has_method("rebake_navigation"):
		_world.call("rebake_navigation")
	var polys : int = 0
	var stable : int = 0
	var region := _world.find_child("NavRegion", true, false) as NavigationRegion3D
	if region == null:
		_check(false, "a NavigationRegion3D exists in the world")
		return
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
	# A stable POLYGON COUNT is only a proxy: the mesh resource can be fully baked
	# while NavigationServer3D has not yet synced the map on its own step, and a
	# query against an unsynced map returns a TRUNCATED path rather than an error.
	# So gate on the server's own iteration id, which only advances when the map
	# has actually been rebuilt. Cheap, and correct regardless.
	#
	# CORRECTION, 2026-07-29 — TWO WRONG DIAGNOSES, RECORDED SO NOBODY REPEATS THEM.
	# This wait was added believing it explained the intermittent crew-post failure
	# below. It did not. Measured, paired A/B runs of the crew-post check:
	#
	#   bake-race theory   the wait landed, the next harness run failed the same
	#                      check for a DIFFERENT worker (Peter, 17.00 m short).
	#   off-mesh theory    CrewManager takes each post from its machine's own
	#                      position and the bake erodes machine footprints, so
	#                      posts looked off-mesh by construction. Snapping posts to
	#                      the nearest navmesh point was tried and MEASURED:
	#                        no-snap: PASS, PASS      snap: PASS, FAIL
	#                      It fixes nothing, and the "is the post on the mesh"
	#                      invariant written to prove it passed in BOTH conditions
	#                      (worst 0.28 m) while routing failed — a vacuous check.
	#                      Both were reverted rather than shipped.
	#
	# WHAT IS ACTUALLY KNOWN: the failure is genuinely nondeterministic run to run,
	# always in the one-way `canteen<-post` direction, and the affected worker AND
	# post position differ every time (Pascal (-218.9, 83.3); Peter; Abdellilah
	# (-197.9, 83.7) and (-216.0, ...)). Being within 0.28 m of the mesh is not
	# enough — the nearest polygon can be a sliver that is not CONNECTED to the
	# canteen. The open question is therefore which machine positions are
	# unroutable-from-canteen and why post assignment lands on them at random;
	# that is a CrewManager/navmesh-topology question, not a bake-timing one.
	#
	# This wait stays because gating on the server's iteration id is correct on its
	# own merits, not because it fixed anything.
	var map : RID = region.get_navigation_map()
	var iter : int = -1
	var iter_stable : int = 0
	for _i in range(BAKE_WAIT_FRAMES):
		var cur : int = NavigationServer3D.map_get_iteration_id(map)
		if cur == iter and cur > 0:
			iter_stable += 1
			if iter_stable >= 30:
				break
		else:
			iter_stable = 0
		iter = cur
		await get_tree().physics_frame
	_info("baked navmesh: %d polygons (server map iteration %d)" % [polys, iter])
	# Guard against measuring connectivity on the empty-continent mesh, where
	# every route trivially succeeds. Without this the whole file is vacuous.
	_check(polys > 200,
		"the mesh under test has real topology (%d polygons — on the 2-polygon baseline every route below passes for free)"
			% polys)

# ── 1. Are the machines actually IN the mesh? ────────────────────────────────
# THE POLYGON COUNT ABOVE CANNOT ANSWER THIS, and finding that out the hard way is
# why this check exists. Mutating the bake back to SOURCE_GEOMETRY_GROUPS_EXPLICIT
# — the pre-fix mode, under which a machine's child CollisionShape3D is never
# parsed and NOT ONE machine enters the mesh — still produced 272 polygons and
# sailed through the ">200" assertion, because the bounded floor slab alone is
# worth that many. A count proves the bake ran over a sensible area; only routing
# AROUND an obstacle proves the obstacle is in there.
func _test_machine_carve() -> void:
	_section("MACHINE CARVE — the row is an obstacle, not decoration")
	var machines : Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is StaticBody3D:
			machines.append(n as Node3D)
	if machines.size() < 4:
		_check(false, "enough machines to have a row to route around (%d)" % machines.size())
		return
	machines.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		return a.global_position.x < b.global_position.x)
	# Straddle the row at its middle machine, along that machine's own local X, so
	# the two probes sit on opposite faces of a real body.
	var mid : Node3D = machines[machines.size() / 2]
	var side : Vector3 = mid.global_transform.basis.x.normalized()
	var a : Vector3 = mid.global_position + side * 6.0
	var b : Vector3 = mid.global_position - side * 6.0
	a.y = mid.global_position.y
	b.y = mid.global_position.y
	var map : RID = _world.get_world_3d().navigation_map
	var path : PackedVector3Array = NavigationServer3D.map_get_path(map, a, b, true)
	_info("path across the row (%.1f, %.1f) -> (%.1f, %.1f): %d points"
		% [a.x, a.z, b.x, b.z, path.size()])
	# Two points IS the straight line through solid steel — the exact signature of
	# the 2-polygon baseline and of the EXPLICIT parse mode.
	_check(path.size() >= 3,
		"the route goes AROUND the machine row (%d points — 2 is a straight line through it)"
			% path.size())

# ── 2. Inside <-> outside ─────────────────────────────────────────────────────
func _test_inside_outside() -> void:
	_section("INSIDE <-> OUTSIDE — the crew can still get out of the building")
	var shell := _shell()
	if shell == null:
		_check(false, "the building shell is findable (its footprint defines both endpoints)")
		return
	var box := NavSiteBounds.body_aabb(shell)
	if box.size == Vector3.ZERO:
		_check(false, "the shell has a measurable footprint")
		return
	var centre : Vector3 = box.get_center()
	var floor_y : float = box.position.y
	var interior := Vector3(centre.x, floor_y, centre.z)
	# Straight out along +X past the facade. Derived from the MEASURED half-extent,
	# never from a constant: a site map validated against its own stale constant is
	# already one of this project's shipped bugs.
	var exterior := Vector3(
		box.position.x + box.size.x + EXTERIOR_MARGIN_M, floor_y, centre.z)
	_info("shell footprint %.0f x %.0f m centred (%.1f, %.1f)"
		% [box.size.x, box.size.z, centre.x, centre.z])
	_info("interior probe (%.1f, %.1f)  exterior probe (%.1f, %.1f)"
		% [interior.x, interior.z, exterior.x, exterior.z])

	# ANTI-VACUITY. MainWorld's own guard compared two INTERIOR points and then
	# skipped itself for having picked them 5 m apart. Assert the geometry of the
	# question before trusting the answer to it.
	var inside_ok : bool = box.has_point(Vector3(interior.x, centre.y, interior.z))
	var outside_ok : bool = not box.has_point(Vector3(exterior.x, centre.y, exterior.z))
	_check(inside_ok and outside_ok,
		"the probes really are on opposite sides of the facade (interior inside=%s, exterior outside=%s)"
			% [str(inside_ok), str(outside_ok)])
	_check(interior.distance_to(exterior) > 20.0,
		"the probes are far enough apart to constitute a crossing (%.1f m)"
			% interior.distance_to(exterior))

	_route("inside -> outside", interior, exterior, PATH_ENDPOINT_TOL_M)
	_route("outside -> inside", exterior, interior, PATH_ENDPOINT_TOL_M)

# ── 2. Crew posts and the canteen ─────────────────────────────────────────────
func _test_crew_posts() -> void:
	_section("CREW — every post still reaches the canteen and back")
	var cm = _world.get("crew_manager")
	if cm == null:
		_check(false, "CrewManager present")
		return
	var workers : Array = cm.get("workers")
	var canteen : Vector3 = cm.get("break_room_pos")
	if workers == null or workers.is_empty():
		_check(false, "the shift crew is posted (0 workers)")
		return
	_info("%d workers, canteen at (%.1f, %.1f, %.1f)"
		% [workers.size(), canteen.x, canteen.y, canteen.z])
	# Posts outside the site are a CREW defect, not a navmesh one, and conflating
	# them buries a real bug under a wrong headline. MEASURED: on this fixture
	# Yassine's post is (-508.0, 406.5) — roughly 340 m outside the fence, with the
	# canteen route ending 267.91 m short. No navmesh can route to a post that is
	# not on the site; CrewManager.assign_posts (CrewManager.gd:266-277) falls back
	# to `pos = w.global_position` when no machine sits in the worker's zone, and
	# during the pre-shift window that position is wherever the worker still is —
	# on the approach road. So these are counted, named and reported SEPARATELY,
	# and the navmesh assertion is made over the posts that are actually on site.
	var site := NavSiteBounds.compute(_world)
	var unreachable : Array[String] = []
	var offsite : Array[String] = []
	var checked : int = 0
	for w in workers:
		if not (w is Node3D):
			continue
		var post : Vector3 = w.get("home_position")
		if post == Vector3.ZERO:
			continue
		if site.size != Vector3.ZERO \
				and not site.has_point(Vector3(post.x, site.get_center().y, post.z)):
			offsite.append("%s at (%.1f, %.1f)" % [String(w.get("npc_name")), post.x, post.z])
			continue
		checked += 1
		# Both directions: a one-way route is a crew that can go on break and
		# never come back, which is the same bug wearing a different hat.
		#
		# The ASYMMETRY is diagnostic, so both gaps are reported. map_get_path snaps
		# each endpoint to the nearest polygon, so a post buried inside a machine's
		# eroded footprint still routes post->canteen (its START snaps out to the
		# aisle and the path lands exactly on the canteen) while canteen->post ends
		# short. A one-way failure therefore means "the post is off-mesh", not "the
		# aisle is blocked" — and printing only "unreachable" would hide that.
		var gap_to : float = _endpoint_gap(canteen, post)
		var gap_from : float = _endpoint_gap(post, canteen)
		if gap_to > POST_ENDPOINT_TOL_M:
			unreachable.append("%s post<-canteen (ends %.2f m short; post at (%.1f, %.1f))"
				% [String(w.get("npc_name")), gap_to, post.x, post.z])
		if gap_from > POST_ENDPOINT_TOL_M:
			unreachable.append("%s canteen<-post (ends %.2f m short; post at (%.1f, %.1f))"
				% [String(w.get("npc_name")), gap_from, post.x, post.z])
	# ANTI-VACUITY. 0 of 0 posts reachable is the shape of every vacuous green
	# this project has shipped. Assert the sample size before the result.
	_check(checked >= 5,
		"enough ON-SITE posts were actually measured to mean anything (%d of %d workers)"
			% [checked, workers.size()])
	_check(unreachable.is_empty(),
		"every on-site post routes to the canteen and back (%d broken: %s)"
			% [unreachable.size(), ", ".join(unreachable) if not unreachable.is_empty() else "none"])

	# REPORTED, NOT ASSERTED — and deliberately so. This is a real defect, but it
	# belongs to CrewManager, and gating navigation work on it would be blaming the
	# navmesh for a post that was never on the plant. It must still be LOUD: an
	# off-site post is a worker who can never reach their station.
	if offsite.is_empty():
		_info("all posts are on site")
	else:
		print("  ADVIS : %d post(s) assigned OUTSIDE the site — a CrewManager defect, not a navmesh one: %s"
			% [offsite.size(), ", ".join(offsite)])

# ── Helpers ───────────────────────────────────────────────────────────────────

## Assert a route exists AND lands on its goal. Reports both numbers on failure —
## an unreachable endpoint is useless to debug without knowing which one it was.
func _route(label: String, from: Vector3, to: Vector3, tol: float) -> void:
	var map : RID = _world.get_world_3d().navigation_map
	var path : PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	var endp : float = 1e9
	if not path.is_empty():
		endp = Vector2(path[path.size() - 1].x - to.x,
			path[path.size() - 1].z - to.z).length()
	_check(path.size() >= 2 and endp <= tol,
		"%s: routed (%d points, ends %.2f m from the goal, limit %.1f)"
			% [label, path.size(), endp, tol])

## XZ distance between where a route ENDS and where it was asked to end. INF when
## no route came back at all. Returned as a number rather than a bool so the
## failure message can say how badly it missed — "unreachable" and "ends 0.3 m
## short of a post buried in a machine" are different bugs with different owners.
func _endpoint_gap(from: Vector3, to: Vector3) -> float:
	var map : RID = _world.get_world_3d().navigation_map
	var path : PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	if path.size() < 2:
		return INF
	return Vector2(path[path.size() - 1].x - to.x,
		path[path.size() - 1].z - to.z).length()

func _shell() -> Node3D:
	for nm in ["ShellCollision", "BuildingShell", "ShellMesh"]:
		var n := _world.find_child(nm, true, false)
		if n is Node3D:
			return n as Node3D
	return null

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
