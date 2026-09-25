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

## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const PROTECT : Array[String] = [
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
## Diagnostics only. "Did the path land ON this polygon" needs a far tighter gate
## than "did the crew get near enough": A* handed an unreachable target returns
## the closest reachable point, so any tolerance wide enough to forgive a post
## inside a machine is also wide enough to call an island reachable.
const ON_POLYGON_TOL_M : float = 0.5

const BOOT_FRAMES   : int = 120
const SETTLE_FRAMES : int = 60
const BAKE_WAIT_FRAMES : int = 600

const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)
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
	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return

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
	# BuildMode calls line_flow.rebuild() after every placement; this harness
	# builds its fixture straight from the catalog and so never did, leaving
	# LineFlow with 0 nodes. CrewManager._machine_list() reads line_flow._nodes,
	# so with none the post assignment below has nothing to assign from.
	var lf0 = _world.get("line_flow")
	if lf0 != null and lf0.has_method("rebuild"):
		lf0.call("rebuild")
		await get_tree().process_frame
	await _wait_for_bake()
	_test_machine_carve()
	_test_inside_outside()
	await _test_crew_posts()

	for c in _wlg.final_checks(_world):
		_check(c[0], c[1])

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
	var fr : Dictionary = await BFrame.wait_fitted(_world)
	_check(not fr.is_empty(), "building frame FITTED from the shell (InteriorLightingManager)")
	if fr.is_empty():
		return
	var start : Vector3 = BFrame.to_scene(fr, Vector2(4.0, 22.0), Plant.floor_top_y())
	bm.call("_build_full_line", "line_3a", start, BFrame.forward_rot_y(fr))
	for _i in range(20):
		await get_tree().process_frame
	var machines : int = 0
	# lump_cart is built as a RigidBody3D (PlaceableCatalog, bespoke compound
	# collision) and there are two per extruder since the 2026-08-03 ruling, so a
	# StaticBody3D-only count sits below LINE_3A_SEQ.size() by exactly the carts
	# (measured 2026-09-21: 40 placed = 38 static + 2 lump_cart rigid, SEQ 39).
	# Count them as fixture, and ONLY them, so any other non-static entry still
	# shows up as a gap.
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is StaticBody3D \
				or (n is RigidBody3D and String(n.get_meta("placeable_id", "")) == "lump_cart"):
			machines += 1
	# DERIVED, not typed. This was `>= 40`, written 2026-07-22 (94c685b) when
	# LINE_3A_SEQ had 42 entries. Operator rulings 5f4e7c3 (2.1-B) and 5b854d8
	# took the line to 39 on 2026-08-28 and the constant never followed, so from
	# that day the check was unsatisfiable by the very fixture it verifies, and
	# this suite — whose scratch slot is clean — was red on this exact line the
	# whole time while test_jam_baseline hid the same 39 behind a stale
	# __jambaseline___factory.json (166 leftover machines). Measured at 00cc51c2:
	# BuildMode reports "Built line_3a — 39 machines" and every SEQ entry yields
	# one StaticBody3D in the placed_object group, so the counts are equal, not
	# merely >=. Both numbers print so a future non-static SEQ entry shows up as
	# a visible gap instead of a silent false red.
	var seq_n : int = BuildMode.LINE_3A_SEQ.size()
	_check(machines >= seq_n,
		"machine fixture present (%d placed bodies [static + lump_cart], LINE_3A_SEQ has %d)"
			% [machines, seq_n])
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
	# 2026-09-23 — WAIT FOR THE BAKE ITSELF, not for a still count. The stability
	# loop below latched onto the PREVIOUS bake's mesh whenever the fixture bake
	# took longer than its 60-frame window: measured in the 2026-09-23 harness as
	# "6 polygons, 7 vertices" with the world's own bake_finished handler ("Nav
	# connectivity verified") printing AFTER the FAIL lines; the operator
	# checkout's last log shows the same latch at 10 polygons, and the 2026-09-21
	# audit's "2 collapses in 3 runs" was this too. The bake is threaded and
	# is_baking() is the engine's own flag; a few quiet frames after it clears
	# catch a queued re-bake (MainWorld.rebake_navigation) starting up.
	var baking_frames : int = 0
	var quiet_frames : int = 0
	while baking_frames + quiet_frames < BAKE_WAIT_FRAMES:
		await get_tree().process_frame
		if region.is_baking():
			baking_frames += 1
			quiet_frames = 0
		else:
			quiet_frames += 1
			if quiet_frames >= 5:
				break
	_info("bake thread finished after %d frames (is_baking false)" % baking_frames)
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
	#
	# RESOLVED 2026-08-12 — THIRD DIAGNOSIS, AND THIS ONE HELD.
	# The nondeterminism was never in the navmesh. It was in the INPUT. This
	# harness builds its line-3A fixture straight from the catalog and never
	# called line_flow.rebuild() (BuildMode does, after every placement), so
	# CrewManager._machine_list() — which reads line_flow._nodes — saw ZERO
	# machines. assign_posts() therefore took the `no machine in zone` branch for
	# every worker and set pos = w.global_position: the spot each worker happened
	# to be standing on mid-walk. Measured, 3 consecutive runs, all 9 workers:
	#   station='' every time, and every post moved between runs
	#   (Romain (-208.8,83.4) / (-196.6,98.0) / (-188.6,85.6))
	# So the check was routing eight wandering floor positions, and failed
	# whenever one landed off-mesh — about one run in three, always on a
	# different worker. That is exactly the signature recorded above.
	#
	# With rebuild() called before assignment, posts are real stations
	# (extruder_3a, centrifuge, mengsilo, wind_sifter, plus floaters on
	# "(rondgang)") and the result is byte-identical run to run: 9 runs, same 6
	# broken legs, same distances to 0.01 m. The check now names a stable
	# navmesh/topology defect instead of tossing a coin.
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
	# never from a constant, to ensure the site map is always validated against
	# actual geometry rather than a stale assumption.
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
	# Yassine's post is (-508.0, 406.5) — roughly 340 m off-site, with the
	# canteen route ending 267.91 m short. No navmesh can route to a post that is
	# not on the site; CrewManager.assign_posts (CrewManager.gd:266-277) falls back
	# to `pos = w.global_position` when no machine sits in the worker's zone, and
	# during the pre-shift window that position is wherever the worker still is —
	# on the approach road. So these are counted, named and reported SEPARATELY,
	# and the navmesh assertion is made over the posts that are actually on site.
	# assign_posts() reads line_flow._nodes (CrewManager._machine_list), and it
	# runs at CrewManager setup — BEFORE this harness builds its line-3A fixture.
	# So every post was assigned against an empty machine list and fell back to
	# `pos = w.global_position`, i.e. wherever the worker was standing mid-walk.
	# MEASURED before this call was added: all 8 workers had station='' and every
	# post moved between runs (Romain (-208.8,83.4) / (-196.6,98.0) / (-188.6,85.6)),
	# so the check was routing eight random floor positions and failed whenever one
	# of them landed off-mesh — about one run in three. Re-assign now that the
	# machines exist, so the posts under test are actual stations.
	var lf = _world.get("line_flow")
	var n_nodes : int = 0
	if lf != null and "_nodes" in lf:
		n_nodes = (lf.get("_nodes") as Array).size()
	_info("LineFlow nodes available for post assignment: %d" % n_nodes)
	if cm.has_method("assign_posts"):
		cm.call("assign_posts")
		for _i in range(10):
			await get_tree().process_frame

	var site := NavSiteBounds.compute(_world)
	var unreachable : Array[String] = []
	var offsite : Array[String] = []
	var checked : int = 0
	var stationed : int = 0
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
		# Provenance, not just position. assign_posts() takes the post from the
		# nearest machine IN ZONE measured from the worker's CURRENT position,
		# and falls back to that position outright when the zone has no machine
		# (CrewManager.gd:266-277). A post with no station id is therefore
		# "wherever this worker happened to be standing", which is why the
		# failing worker and post differ every run.
		var sid := String(w.get("assigned_station_id"))
		if sid != "":
			stationed += 1
		_info("post %-12s station='%s' at (%.1f, %.1f)"
			% [String(w.get("npc_name")), sid, post.x, post.z])
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
		# A distance alone does not say WHOSE bug it is, and this file has already
		# cost two wrong diagnoses that a number here would have cut short. So when
		# a leg breaks, name the mechanism as well: how far the post is from any
		# mesh at all, whether the nearest mesh point is reachable from the canteen,
		# and — the decisive one — which body the post is standing inside.
		if gap_to > POST_ENDPOINT_TOL_M or gap_from > POST_ENDPOINT_TOL_M:
			_info("  why %-12s %s" % [String(w.get("npc_name")), _diagnose(post, canteen)])
	# ANTI-VACUITY. 0 of 0 posts reachable is the shape of every vacuous green
	# this project has shipped. Assert the sample size before the result.
	_check(checked >= 5,
		"enough ON-SITE posts were actually measured to mean anything (%d of %d workers)"
			% [checked, workers.size()])
	# ANTI-VACUITY #2. `checked > 0` is not enough: a post with no station id is
	# just "wherever this worker was standing", and routing eight of those is a
	# coin flip, not a test. MEASURED before the LineFlow rebuild above: all 8
	# workers had station='' and every post moved between runs, which is the
	# whole reason this file failed about one run in three.
	_check(stationed > 0,
		"posts come from real stations, not from wherever a worker stood "
		+ "(%d of %d checked posts carry a station id)" % [stationed, checked])
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

## WHY a post's route breaks, in the three terms that separate the candidate
## owners. Measurement only — this adds no assertion and cannot change a verdict.
##
##   nearest mesh  where the navmesh actually is relative to the post, SPLIT into
##                 a horizontal offset and a height above the operating floor.
##                 The split is the whole point. MEASURED here: dXZ 0.00 m, and
##                 0.2-0.4 m of floor clearance. There IS mesh directly at the
##                 post's own XZ — a sliver Recast left inside the machine's
##                 footprint, lifted by cell_height 0.60 voxel quantisation. So
##                 "the post is off-mesh" is the wrong headline; the post is ON a
##                 scrap of mesh that goes nowhere.
##   reach         whether the canteen can route to that nearest point and LAND
##                 on it, judged at 0.50 m rather than POST_ENDPOINT_TOL_M. The
##                 loose gate is what makes this reading useless: A* asked for an
##                 unreachable island returns the closest reachable point instead,
##                 which is the aisle ~1.8 m away — inside a 3 m tolerance, and
##                 therefore indistinguishable from success. Only a gate tight
##                 enough to demand "the path actually ended ON the polygon"
##                 separates an island from a neighbour.
##   inside        the body whose collider contains the post, WITH its footprint.
##                 This one names an owner outright: CrewManager.assign_posts
##                 takes the post from the machine's OWN global_position
##                 (CrewManager.gd:276), and MainWorld bakes that machine's
##                 collider as navmesh source, so a stationed post sits inside
##                 its own machine.
##
## A FOURTH THEORY, DISPROVEN 2026-08-12 — RECORDED SO NOBODY CHASES IT.
## extruder_3a is the only station that fails in BOTH directions, and the obvious
## reading is that a two-way failure must have a different cause than the four
## one-way ones. It does not. All five `why` lines are the same shape — dXZ
## 0.00 m, ISLAND, post inside its own machine — and the whole difference is how
## far the reachable aisle sits from the machine's ORIGIN, which is a function of
## how big the machine is:
##
##     extruder_3a   canteen->post ends 3.68 m short   > POST_ENDPOINT_TOL_M 3.0
##     centrifuge                    1.78 m
##     mengsilo                      2.17 m
##     wind_sifter                   1.97 m
##
## Only the first crosses the 3.0 m line, so only the first is also counted in
## the post<-canteen direction. One mechanism, five instances, one of them on the
## far side of a tolerance. Treating the asymmetry as a separate defect would be
## the fourth wrong diagnosis this check has produced; the footprint printed in
## `inside [...]` is there to cut that short.
func _diagnose(post: Vector3, canteen: Vector3) -> String:
	var map : RID = _world.get_world_3d().navigation_map
	var cp : Vector3 = NavigationServer3D.map_get_closest_point(map, post)
	var off : float = Vector2(cp.x - post.x, cp.z - post.z).length()
	# HEIGHT ABOVE THE OPERATING FLOOR, NOT ABOVE THE POST. Measured 2026-08-12:
	# against the post this read +0.26 to +0.42 m over 10 runs and was the ONLY
	# unstable field in the whole log. Not the navmesh — cp.y is deterministic —
	# but post.y, which assign_posts copies from w.global_position, i.e. the
	# worker's SETTLED standing height, a few cm of physics noise every boot.
	# Which is this file's own lesson arriving by the back door: a nondeterministic
	# input had leaked into a diagnostic, and a diagnostic that moves run to run is
	# one nobody can diff. Plant.floor_top_y() is a constant of the world.
	var dy : float = cp.y - Plant.floor_top_y()
	var to_cp : PackedVector3Array = NavigationServer3D.map_get_path(map, canteen, cp, true)
	var cp_gap : float = INF
	if to_cp.size() >= 2:
		cp_gap = to_cp[to_cp.size() - 1].distance_to(cp)
	# CONTAINMENT FROM GEOMETRY, NOT FROM A PHYSICS QUERY. This began as
	# intersect_point at post.y + 1.0 and was the last unstable field in the log:
	# 1 run in 10 reported `inside [nothing]` for three of the five posts. The
	# probe height rode on post.y — the worker's settled standing height again —
	# and a point query is knife-edge by nature. Measured AABB overlap depends on
	# nothing but the placement, which the identical routing distances already
	# prove is deterministic.
	#
	# The body's OWN footprint is reported with it, because the one number that
	# looks like a second mechanism is explained by it — see the note below.
	# Axis-aligned, so a rotated machine reads slightly larger than its true
	# footprint; that is fine for naming an owner and would not be for gating.
	var inside : Array[String] = []
	for n in get_tree().get_nodes_in_group("placed_object"):
		if not (n is Node3D):
			continue
		var box := NavSiteBounds.body_aabb(n as Node3D)
		if box.size == Vector3.ZERO:
			continue
		if post.x < box.position.x or post.x > box.position.x + box.size.x:
			continue
		if post.z < box.position.z or post.z > box.position.z + box.size.z:
			continue
		inside.append("%s %.1fx%.1f m" % [(n as Node).name, box.size.x, box.size.z])
	return ("nearest mesh dXZ %.2f m, %+.2f m above floor; canteen->it ends %.2f m short (%s); inside [%s]"
		% [off, dy, cp_gap,
			"reachable" if cp_gap <= ON_POLYGON_TOL_M else "ISLAND",
			", ".join(inside) if not inside.is_empty() else "nothing"])

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

# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")


## Restore BEFORE the world is freed, then again after: the headless teardown
## segfault lands inside world teardown (CLAUDE.md, 15 of 62 boots) and never
## reaches code after it.
func _finish(code: int) -> void:
	_wlg.restore()
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(code)

