extends Node
# =============================================================================
# REGRESSION — relocated spawns must not materialise INSIDE solid geometry.
# =============================================================================
#   GODOT --headless --path . res://src/tests/test_spawn_clearance.tscn
#   prints "Result: PASS" / "Result: FAIL" for the harness to key off.
#
#   SPAWNCLEAR_NOLINE=1 ... → shipped save ONLY, no synthetic line. THIS is the
#   authoritative read of the operator's next boot: the synthetic line below
#   perturbs the very hulls under test (measured — it lifts MastLift onto a
#   machine and thereby HIDES the real mast-lift nesting). Run both.
#
#   SPAWNCLEAR_PLANT=1 ...  → deliberately teleports vehicle #0 into the
#   volumetric centre of the biggest STATIC shipped machine before measuring.
#   That run MUST go red. It is the mutation test that proves this file is not
#   another vacuous green. Measured: reads 100 % penetration, reproducibly, and
#   turns 3 checks red. Three earlier versions of this plant did NOT go red —
#   it landed on top of the machine (node origin is at the base, not the
#   centre), it picked a bale (bales carry placeable_id too), and it picked a
#   RigidBody3D the solver simply shoved aside. Each is documented at its fix.
#
# VERDICT SCOPE:
#   "FAIL" covers the operator's next boot on his real save. "ADVIS" lines are
#   measured defects this file is deliberately not the gate for — see _advise.
#   Advisories are printed with their full measurement and counted in the
#   verdict line; they are never suppressed.
#
# WHY THIS FILE EXISTS (commit 9334310, measured 2026-07-21):
#   WorldFrame._layout_to_scene used to rotate the operator's SCENE-ABSOLUTE
#   markers by world yaw and re-add the anchor. Every vehicle therefore spawned
#   150-400 m away, in an empty field. The frame fix moved 9 vehicles 120-270 m,
#   7 bale yards 290-355 m and 3 line starts 145-175 m — all ONTO the plant.
#   Landing on the marker is now PROVEN (test_vehicle_spawn_frame). Landing in
#   FREE SPACE was not. A hull that materialises inside a machine, a wall or
#   another hull is the failure mode the operator would meet on his next boot.
#
# WHY THE EXISTING CHECKS CANNOT SEE IT:
#   regression_world_save.gd:457 asserts "vehicles finite + within 500 m of the
#   plant" — a radius bound is blind to what is at the radius. Its companion at
#   :486 asserts marker identity — which is exactly what a vehicle buried in a
#   machine WOULD satisfy, because the machine is standing on the marker. Both
#   stay green for every bug this file hunts. So this file measures REAL SHAPE
#   OVERLAP: the vehicle's OWN collision shapes, at its OWN spawned transform,
#   against everything else in the space.
#
# POPULATION UNDER TEST (stated because an empty shell would make it vacuous):
#   the shipped save carries almost no machines, so this test ALSO builds
#   line_3a from the CLEAN const seed the same way regression_world_save.gd
#   does (in-memory macro cache cleared, anchored at bf(4,22), running down the
#   long hall axis). Vehicles are therefore tested against a REAL machine line,
#   not an empty building. The machine count actually placed is printed.
#
# World saves go to a scratch file; world_layout.json is only compared, never
# written (src/tests/world_layout_guard.gd).
# =============================================================================

const TEST_SLOT := "__spawnclear__"

## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const PROTECT : Array[String] = [
	"user://__spawnclear___save.json",
	"user://__spawnclear___factory.json",
]

# ── Building frame (bf), only used to ANCHOR the test line (never to judge a
# result). The same fitted frame regression_world_save.gd uses.
# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")
const LINE_START_BF := Vector2(4.0, 22.0)

# Frames to let MainWorld's _ready cascade + deferred spawns finish.
const BOOT_FRAMES : int = 90
# Extra frames after the line is built, so Rapier has settled every hull and the
# bale-collider drain queue (2 ms/frame) has produced a real RB population.
const SETTLE_FRAMES : int = 240

# ── PENETRATION METRIC ──────────────────────────────────────────────────────
# NOT PhysicsDirectSpaceState3D.collide_shape. Measured 2026-07-21 on this
# project's Rapier3D backend (project.godot:392), collide_shape's contact array
# is NOT the (point-on-A, point-on-B) pairing the Godot docs describe: pairing
# consecutive entries reports a car resting on ExteriorGroundBody as 15.32 m
# deep and two cars 11 m apart as 12.39 m deep. Those numbers are the distance
# between two points on the SAME surface, so any threshold built on them is
# noise dressed as a measurement — precisely the vacuous-green shape this
# project keeps getting bitten by.
#
# Instead: PENETRATION FRACTION by shrink-search, built only on intersect_shape
# (independently verified honest — it correctly reported the 28x33x44 m
# ParkedCollider boxes as real). Rebuild the hull as a box from its own local
# AABB, shrink it uniformly about its own centre, and bisect for the largest
# scale at which it STILL touches the body in question. A hull merely resting on
# a surface separates after ~1 % of shrink; a hull with its centre inside a
# machine never separates at all. penetration = 1.0 - free_scale, so 0.0 = just
# touching and 1.0 = the body engulfs the hull.
const SHRINK_ITERS : int = 10
const SHRINK_FLOOR : float = 0.02   # below this, call it fully engulfed

# Vehicle-on-vehicle: nested hulls are the exact defect fixed in 276d142/5a56d68
# (5 clamp clicks nested into a sky-ladder). Two hulls sharing a tenth of their
# own scale are nested, not parked side by side.
const PEN_VEHICLE : float = 0.10
# Machine / belt / wall / shell. The plant mutation below reads ~1.0, so this
# floor sits 5x below the signal it exists to catch.
const PEN_SOLID : float = 0.20
# Frames given to BaleYardManager's drain queue once the probes are parked. The
# queue is time-sliced at 2 ms/frame, so a yard materialises over many frames.
# Bale streaming is waited for in WALL time and on the condition, never a frame
# count: BaleYardManager.tick() refreshes its "vehicle" cache every 2.0 s of
# wall time, and the probes below are only seen at that refresh. Measured
# 2026-09-23: a fixed 180-frame window streamed bales at 55 fps (3.3 s) and
# streamed NONE at 140 fps (1.3 s — the frame rate after LineFlow moved to
# 10 Hz), turning the vacuity guard red on a healthy world. MIN keeps the old
# window's wall-clock worth of drain after the first body; MAX bounds a world
# that never streams (which then fails the guard, as it should).
const BALE_DRAIN_MIN_S : float = 3.0
const BALE_DRAIN_MAX_S : float = 12.0

# Bodies parked on layer 20 with mask 0 are QUERY-ONLY proxies (ShiftCarSpawner
# .gd:177-178). They are reported but never scored: nothing can physically
# collide with them, so a hull sharing space with one is not embedded in
# anything. See the ParkedCollider finding printed by _check_d.
const QUERY_ONLY_LAYER : int = 1 << 19

# Down-ray: a vehicle must be STANDING on something, not floating or buried.
const RAY_UP_M      : float = 1.5    # start above the body origin
const RAY_DOWN_M    : float = 8.0    # look this far below the start
const STAND_MAX_M   : float = 2.5    # surface may be at most this far below origin
const STAND_MIN_M   : float = 0.02   # ... and must be BELOW it (not buried)

const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)
var _oks   : int = 0
var _fails : int = 0
var _advisories : int = 0
var _world : Node3D = null
var _plant_mutation : bool = false
var _no_line : bool = false
## instance ids of every machine THIS TEST built. Provenance matters: a hull
## overlapping a machine from the operator's SHIPPED SAVE is what he meets on
## his next boot; a hull overlapping the synthetic line_3a is a statement about
## where this test chose to anchor its line. Both are scored, separately, and
## conflating them would make the verdict unreadable.
var _synthetic : Dictionary = {}


func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)


## A measured defect that this test is NOT the gate for, because acting on it is
## outside the change this file guards:
##   • the SYNTHETIC line_3a arm — the line anchor bf(4,22) is chosen by this
##     file (copied from regression_world_save.gd), so a hull overlapping it is a
##     statement about a line the operator has not built, not about his save;
##   • ShiftCarSpawner's oversized proxy boxes — src/scenes/world/ShiftCarSpawner
##     .gd is outside this task's file scope.
## Printed with its full measurement and counted in the verdict line, but does
## not turn the harness red. The number is never suppressed — hiding it is how
## this project got its vacuous greens.
func _advise(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_advisories += 1
		print("  ADVIS : %s" % label)


func _info(label: String) -> void:
	print("  info  : %s" % label)


func _ready() -> void:
	_plant_mutation = OS.get_environment("SPAWNCLEAR_PLANT") != ""
	_no_line = OS.get_environment("SPAWNCLEAR_NOLINE") != ""
	print("=== spawn clearance — relocated vehicles/yards must land in free space ===")
	if _plant_mutation:
		print("*** SPAWNCLEAR_PLANT=1 — MUTATION RUN, a hull is planted inside a machine ON PURPOSE ***")
	if _no_line:
		print("*** SPAWNCLEAR_NOLINE=1 — SHIPPED-SAVE BASELINE, no synthetic line_3a is built ***")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2)
		return
	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2)
		return

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		_check(false, "MainWorld.tscn loaded")
		await _finish()
		return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	var autosave := _world.find_child("AutosaveTimer", true, false) as Timer
	if autosave != null:
		autosave.stop()

	var machines : Array = await _populate_line_3a()
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame
	# Settle the space FIRST, then plant, then measure with no frames in between.
	# freeze=true is not enough to hold a VehicleBody3D still: with 4 physics
	# frames after the plant the hull drifted out of the machine and the mutation
	# read "perched on" instead of "embedded in" on some runs but not others.
	# Every query below reads the shape's own node transform, so no frame is
	# needed for the measurement to be valid — only for the world to be settled.
	await get_tree().physics_frame
	if _plant_mutation:
		_plant_a_hull_inside_a_machine(machines)

	_check_a_vehicle_overlap()
	_check_b_vehicles_are_standing()
	await _check_c_bale_yards(machines)
	_check_d_query_proxy_sanity()
	for c in _wlg.final_checks(_world):
		_check(c[0], c[1])
	await _finish()


# =============================================================================
# POPULATION — build the real machine line, so the overlap test has something
# to be wrong about. An empty shell would make every green below meaningless.
# =============================================================================


func _populate_line_3a() -> Array:
	print("\n--- POPULATION — building line_3a from the clean seed ---")
	if _no_line:
		var shipped : Array = get_tree().get_nodes_in_group("placed_object")
		_info("SKIPPED by SPAWNCLEAR_NOLINE — testing against the shipped save alone (%d placed object(s))"
			% shipped.size())
		return []
	if not Plant.is_initialized():
		_check(false, "Plant initialised (cannot anchor the test line without it)")
		return []
	var bm = _world.get("build_mode")
	if bm == null:
		bm = _world.find_child("BuildMode", true, false)
	if bm == null:
		_check(false, "BuildMode reachable — WITHOUT IT THE WORLD IS EMPTY AND THIS TEST IS VACUOUS")
		return []
	# Clean const seed, not the operator's jog-deltas (in-memory only; the disk
	# macro is untouched and is separately validated by regression_world_save).
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache["line_3a"] = {}
	var fr : Dictionary = await BFrame.wait_fitted(_world)
	_check(not fr.is_empty(), "building frame FITTED from the shell (InteriorLightingManager)")
	if fr.is_empty():
		return []
	var start : Vector3 = BFrame.to_scene(fr, LINE_START_BF, Plant.floor_top_y())
	bm.call("_build_full_line", "line_3a", start, BFrame.forward_rot_y(fr))
	for _i in range(20):
		await get_tree().process_frame

	var placed : Array = []
	var root = bm.get("_placed_root")
	var pool : Array = (root as Node).get_children() if (root != null and is_instance_valid(root)) \
		else get_tree().get_nodes_in_group("placed_object")
	for c in pool:
		if c is Node3D and (c as Node).has_meta("macro_id") \
				and String((c as Node).get_meta("macro_id")) == "line_3a":
			placed.append(c)
	for n in placed:
		_synthetic[(n as Node).get_instance_id()] = true
	_check(placed.size() > 0,
		"POPULATED: %d line_3a machine(s) standing in the building (anchor bf%s)"
			% [placed.size(), str(LINE_START_BF)])
	if not placed.is_empty():
		var c0 : Vector3 = (placed[0] as Node3D).global_position
		var cn : Vector3 = (placed[placed.size() - 1] as Node3D).global_position
		_info("line spans scene (%.1f, %.1f) → (%.1f, %.1f)" % [c0.x, c0.z, cn.x, cn.z])
	return placed


## MUTATION — drop vehicle #0 into the middle of a machine and freeze it there.
## If the checks below stay green with this active, they prove nothing.
func _plant_a_hull_inside_a_machine(machines: Array) -> void:
	var vehicles : Array = get_tree().get_nodes_in_group("vehicle")
	if vehicles.is_empty() or machines.is_empty():
		_info("MUTATION could not run (no vehicle or no machine)")
		return
	var v := vehicles[0] as Node3D
	# Prefer the BIGGEST SHIPPED-SAVE machine, so the mutation exercises the gate
	# the operator's next boot depends on, and so the hull is genuinely engulfed
	# rather than perched. Fall back to the synthetic line.
	var m : Node3D = null
	var m_aabb := AABB()
	var best_vol : float = 0.0
	for n in get_tree().get_nodes_in_group("placed_object"):
		if not (n is Node3D) or _is_synthetic(n as Node):
			continue
		# Yard bales also carry the placed_object group; the first attempt picked
		# one and the mutation only exercised check C. Must be a MACHINE.
		if _classify(n as Node) != "machine":
			continue
		# Must be STATIC. The second attempt planted the hull inside a "Steel skip"
		# RigidBody3D; Rapier simply shoved the skip out of the way and by
		# measurement time there was no overlap left to find. A mutation that the
		# engine can resolve does not hold the invalid state it exists to create.
		if not _is_all_static(n as Node3D):
			continue
		var ab : AABB = _body_world_aabb(n as Node3D)
		var vol : float = ab.size.x * ab.size.y * ab.size.z
		if vol > best_vol:
			best_vol = vol
			m = n as Node3D
			m_aabb = ab
	if m == null:
		m = machines[int(machines.size() / 2)] as Node3D
		m_aabb = _body_world_aabb(m)
	if v is RigidBody3D:
		(v as RigidBody3D).freeze = true
		(v as RigidBody3D).linear_velocity = Vector3.ZERO
		(v as RigidBody3D).angular_velocity = Vector3.ZERO
	# The COLLIDER's volumetric centre, not the node origin: a machine's origin
	# sits at its base, so origin+offset parks the hull ON TOP and the mutation
	# proves nothing (measured — the first attempt did exactly that).
	v.global_position = m_aabb.get_center()
	print("  PLANT : %s teleported into the centre of %s — collider AABB centre %s, size %s" % [
		v.name, m.name, str(m_aabb.get_center().snappedf(0.01)), str(m_aabb.size.snappedf(0.01))])


# =============================================================================
# CHECK A — REAL SHAPE OVERLAP, not proximity.
# =============================================================================
## Every CollisionObject3D in a subtree — the vehicle body PLUS its animatable
## fork/plate children, which are separate bodies and can embed independently.
func _collision_objects(root: Node) -> Array:
	var out : Array = []
	var stack : Array = [root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		if n is CollisionObject3D:
			out.append(n)
		for c in n.get_children():
			stack.append(c)
	return out


## True when nothing in this subtree can be pushed around by the solver.
func _is_all_static(root: Node3D) -> bool:
	var cos : Array = _collision_objects(root)
	if cos.is_empty():
		return false
	for co in cos:
		if not (co is StaticBody3D):
			return false
	return true


## Union of every collision shape's world AABB under a node. Used to find a
## machine's true volumetric centre (its node origin is at its base).
func _body_world_aabb(root: Node3D) -> AABB:
	var out := AABB()
	var seen := false
	for co in _collision_objects(root):
		for cs in (co as Node).get_children():
			if not (cs is CollisionShape3D):
				continue
			var shp : Shape3D = (cs as CollisionShape3D).shape
			if shp == null:
				continue
			var wa : AABB = (cs as CollisionShape3D).global_transform * _shape_local_aabb(shp)
			out = wa if not seen else out.merge(wa)
			seen = true
	return out


func _own_rids(root: Node) -> Array[RID]:
	var out : Array[RID] = []
	for co in _collision_objects(root):
		out.append((co as CollisionObject3D).get_rid())
	return out


## A body nothing can physically collide with (layer 20 / mask 0) — a query
## proxy, not geometry. Reported, never scored.
func _is_query_only(n: Node) -> bool:
	var co := n as CollisionObject3D
	if co == null:
		return false
	return co.collision_mask == 0 and (co.collision_layer & ~QUERY_ONLY_LAYER) == 0 \
		and (co.collision_layer & QUERY_ONLY_LAYER) != 0


## Classify what a hull is touching. Ancestor-walk, so a collider buried three
## nodes deep inside a machine still reads as "machine". People are tested
## BEFORE vehicles: Yassine rides in SuzukiSwiftGLX/PassengerSeat, and the
## naive walk scored him as a nested vehicle.
func _classify(n: Node) -> String:
	if _is_query_only(n):
		return "query-proxy"
	var cur : Node = n
	while cur != null:
		if cur.is_in_group("npc") or cur.is_in_group("colleague") \
				or String(cur.name).begins_with("Humanoid") or cur is CharacterBody3D:
			return "npc"
		if cur.is_in_group("vehicle"):
			return "vehicle"
		# BEFORE the machine test: yard bales carry BOTH the bale groups and a
		# placeable_id, so the machine test would swallow them and every bale a
		# hull touched would be reported as an embedded machine.
		if cur.is_in_group("yard_bale_rb") or cur.is_in_group("bale"):
			return "bale"
		if cur.has_meta("placeable_id") or cur.is_in_group("placed_object"):
			return "machine"
		var nm : String = String(cur.name)
		if nm == "TempFloor" or nm.begins_with("ExteriorGround") or nm.begins_with("GroundQuad") \
				or nm.begins_with("YardPad"):
			return "ground"
		if nm == "ShellMesh" or nm == "WallOpenings" or nm.begins_with("Wall"):
			return "shell"
		cur = cur.get_parent()
	return "other"


## Does a box of `local_aabb` scaled by `s`, sitting at `base_xf`, touch anything
## not in `ex`? The one primitive both the penetration search and this file's
## honesty rest on — and the one this project's Rapier build gets right.
func _touches(space: PhysicsDirectSpaceState3D, base_xf: Transform3D, local_aabb: AABB,
		s: float, ex: Array[RID]) -> bool:
	var box := BoxShape3D.new()
	box.size = local_aabb.size * s
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = box
	q.transform = base_xf * Transform3D(Basis.IDENTITY, local_aabb.get_center())
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_bodies = true
	q.collide_with_areas = false
	q.exclude = ex
	return space.intersect_shape(q, 1).size() > 0


## PENETRATION FRACTION of one hull into ONE body: 0.0 = grazing contact only,
## 1.0 = the body engulfs the hull. Every other body found at this hull is
## excluded, so the number belongs to `target` alone.
##
## Contact is monotone in the shrink factor (a bigger box can only touch more),
## so bisection is sound.
func _penetration(space: PhysicsDirectSpaceState3D, base_xf: Transform3D, local_aabb: AABB,
		own: Array[RID], target: RID, others: Array[RID]) -> float:
	var ex : Array[RID] = own.duplicate()
	for r in others:
		if r != target:
			ex.append(r)
	if _touches(space, base_xf, local_aabb, SHRINK_FLOOR, ex):
		return 1.0
	var lo : float = SHRINK_FLOOR   # known free
	var hi : float = 1.0            # known contact
	for _i in range(SHRINK_ITERS):
		var mid : float = (lo + hi) * 0.5
		if _touches(space, base_xf, local_aabb, mid, ex):
			hi = mid
		else:
			lo = mid
	return 1.0 - lo


## Local AABB of a shape, in its CollisionShape3D's own frame.
func _shape_local_aabb(shp: Shape3D) -> AABB:
	return shp.get_debug_mesh().get_aabb()


## Was this collider built by THIS TEST's line_3a, or was it already in the
## operator's save? Ancestor-walk, because a machine's collider is nested.
func _is_synthetic(n: Node) -> bool:
	var cur : Node = n
	while cur != null:
		if _synthetic.has(cur.get_instance_id()):
			return true
		cur = cur.get_parent()
	return false


func _check_a_vehicle_overlap() -> void:
	print("\n--- A. every spawned vehicle occupies FREE SPACE (real shape query) ---")
	var space : PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	if space == null:
		_check(false, "physics space reachable")
		return
	var vehicles : Array = get_tree().get_nodes_in_group("vehicle")
	_check(vehicles.size() > 0, "found %d vehicle(s) in group 'vehicle' to test" % vehicles.size())
	if vehicles.is_empty():
		return

	var bad_vehicle : int = 0
	var bad_shipped : int = 0
	var bad_synth   : int = 0
	var probed      : int = 0
	var proxies     : int = 0
	var worst_solid : float = 0.0
	var worst_desc  : String = "n/a"
	var synth_desc  : Array[String] = []

	for vn in vehicles:
		var v := vn as Node3D
		if v == null:
			continue
		var own : Array[RID] = _own_rids(v)
		var gp : Vector3 = v.global_position
		var lines : Array[String] = []
		for co in _collision_objects(v):
			if co is Area3D:
				continue          # EnterArea is a trigger volume, not a hull
			if _is_query_only(co):
				continue          # ParkedCollider proxy is not a hull either
			for cs in (co as Node).get_children():
				if not (cs is CollisionShape3D):
					continue
				var shp : Shape3D = (cs as CollisionShape3D).shape
				if shp == null:
					continue
				probed += 1
				var base_xf : Transform3D = (cs as CollisionShape3D).global_transform
				var laabb : AABB = _shape_local_aabb(shp)
				var q := PhysicsShapeQueryParameters3D.new()
				q.shape = shp
				q.transform = base_xf
				q.collision_mask = 0xFFFFFFFF
				q.collide_with_bodies = true
				q.collide_with_areas = false
				q.exclude = own
				var hits : Array[Dictionary] = space.intersect_shape(q, 32)
				var rids : Array[RID] = []
				for h in hits:
					var r : RID = h.get("rid", RID())
					if not rids.has(r):
						rids.append(r)
				for h in hits:
					var col = h.get("collider")
					if col == null or not (col is Node):
						continue
					var kind : String = _classify(col as Node)
					if kind == "query-proxy":
						proxies += 1
						lines.append("      %-11s %-12s pen  n/a          %s" % [
							kind, "not-scored", (col as Node).get_path()])
						continue
					var pen : float = _penetration(space, base_xf, laabb, own,
						h.get("rid", RID()), rids)
					var synth : bool = _is_synthetic(col as Node)
					var verdict : String = "ok"
					if kind == "vehicle" and pen > PEN_VEHICLE:
						verdict = "BAD-NESTED"; bad_vehicle += 1
					elif (kind == "machine" or kind == "shell") and pen > PEN_SOLID:
						if synth:
							verdict = "BAD-TESTLINE"; bad_synth += 1
							synth_desc.append("%s in %s (%.0f %%)" % [
								v.name, (col as Node).name, pen * 100.0])
						else:
							verdict = "BAD-EMBEDDED"; bad_shipped += 1
							if pen > worst_solid:
								worst_solid = pen
								worst_desc = "%s in %s" % [v.name, (col as Node).name]
					lines.append("      %-11s %-12s pen %5.1f %%   %-9s %s" % [
						kind, verdict, pen * 100.0, "TESTLINE" if synth else "shipped",
						(col as Node).get_path()])
		if lines.is_empty():
			_info("%-20s (%.1f, %.1f, %.1f) — no overlap at all" % [v.name, gp.x, gp.y, gp.z])
		else:
			_info("%-20s (%.1f, %.1f, %.1f) — %d overlapping body/bodies:" % [
				v.name, gp.x, gp.y, gp.z, lines.size()])
			for l in lines:
				print(l)

	_check(probed > 0, "probed %d real collision shape(s) — a zero here means the test read nothing" % probed)
	_check(bad_vehicle == 0, "NO vehicle hull is nested in another vehicle (%d nesting overlap(s))" % bad_vehicle)
	# THE OPERATOR'S NEXT BOOT. Only shipped-save geometry can be waiting for him.
	_check(bad_shipped == 0,
		"NO vehicle hull is embedded in SHIPPED-SAVE machine/belt/wall/shell (%d, worst %.0f %%: %s)"
			% [bad_shipped, worst_solid * 100.0, worst_desc])
	# (fence overlap check removed 2026-08-03 — the perimeter fence was deleted.)
	# Separate gate, separate meaning: the synthetic line_3a is anchored at
	# bf(4,22) by THIS FILE. A hit here says the operator's vehicle markers sit
	# on top of where line_3a gets built — a real collision the moment he builds
	# that line there, but not something already in his save.
	_advise(bad_synth == 0,
		"NO vehicle hull is embedded in the SYNTHETIC test line_3a (%d overlap(s)) %s"
			% [bad_synth, str(synth_desc)])
	if proxies > 0:
		_info("%d overlap(s) with query-only proxy bodies were reported but not scored" % proxies)


# =============================================================================
# CHECK B — the hulls are STANDING on something real.
# =============================================================================
func _check_b_vehicles_are_standing() -> void:
	print("\n--- B. every vehicle rests on a real surface (not floating, not buried) ---")
	var space : PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	if space == null:
		_check(false, "physics space reachable for the down-ray")
		return
	var vehicles : Array = get_tree().get_nodes_in_group("vehicle")
	var floating : int = 0
	var checked  : int = 0
	var perched  : int = 0
	var perched_desc : Array[String] = []
	var perched_synth : int = 0
	var perched_synth_desc : Array[String] = []
	for vn in vehicles:
		var v := vn as Node3D
		if v == null:
			continue
		checked += 1
		var gp : Vector3 = v.global_position
		var q := PhysicsRayQueryParameters3D.create(gp + Vector3.UP * RAY_UP_M,
			gp + Vector3.UP * RAY_UP_M + Vector3.DOWN * RAY_DOWN_M)
		q.collision_mask = 0xFFFFFFFF
		q.exclude = _own_rids(v)
		var hit : Dictionary = space.intersect_ray(q)
		if hit.is_empty():
			floating += 1
			_check(false, "%-14s (%.1f, %.1f) — NOTHING under it within %.0f m" % [
				v.name, gp.x, gp.z, RAY_DOWN_M])
			continue
		var hy : float = (hit["position"] as Vector3).y
		var drop : float = gp.y - hy
		var surface : String = String((hit["collider"] as Node).name)
		var kind : String = _classify(hit["collider"] as Node)
		var okstand : bool = drop >= STAND_MIN_M and drop <= STAND_MAX_M
		if not okstand:
			floating += 1
		# Standing ON a machine is not "floating", but it is not the floor either
		# — a hull parked on a machine roof is the sky-ladder failure mode wearing
		# a different hat, so it is counted and named.
		var on_ground : bool = kind == "ground"
		if not on_ground:
			if _is_synthetic(hit["collider"] as Node):
				perched_synth += 1
				perched_synth_desc.append("%s on %s (%s)" % [v.name, surface, kind])
			else:
				perched += 1
				perched_desc.append("%s on %s (%s)" % [v.name, surface, kind])
		_info("%-20s stands on %-22s (%s) at y=%.2f — body origin %.2f m above it%s" % [
			v.name, surface, kind, hy, drop, "" if okstand else "   <<< OUT OF RANGE"])
	_check(checked > 0, "down-ray ran on %d vehicle(s)" % checked)
	_check(floating == 0, "all %d vehicle(s) rest %.2f-%.2f m above a real surface (%d do not)"
		% [checked, STAND_MIN_M, STAND_MAX_M, floating])
	_check(perched == 0,
		"every vehicle stands on GROUND, not on top of SHIPPED-SAVE geometry (%d perched) %s"
			% [perched, str(perched_desc)])
	_advise(perched_synth == 0,
		"no vehicle is perched on the SYNTHETIC test line_3a (%d perched) %s"
			% [perched_synth, str(perched_synth_desc)])


# =============================================================================
# CHECK C — the 7 relocated bale yards.
# =============================================================================
func _check_c_bale_yards(machines: Array) -> void:
	print("\n--- C. bale yards are on real ground and their bales are not in solid geometry ---")
	var mgr = _world.get("bale_yard_manager")
	if mgr == null:
		_check(false, "BaleYardManager reachable")
		return
	var polys : Array = mgr.call("get_yard_polygons")
	_check(polys.size() > 0, "manager reports %d yard polygon(s) actually built" % polys.size())
	var space : PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	if space == null:
		_check(false, "physics space reachable for yard probes")
		return

	var no_ground : int = 0
	var idx : int = 0
	for p in polys:
		var poly : PackedVector2Array = p
		idx += 1
		if poly.size() < 3:
			continue
		var c := Vector2.ZERO
		for pt in poly:
			c += pt
		c /= float(poly.size())
		# What is UNDER the yard centroid?
		var top := Vector3(c.x, Plant.floor_top_y() + 6.0, c.y)
		var dq := PhysicsRayQueryParameters3D.create(top, top + Vector3.DOWN * 20.0)
		dq.collision_mask = 0xFFFFFFFF
		var dh : Dictionary = space.intersect_ray(dq)
		var under : String = "NOTHING"
		var under_kind : String = "none"
		var under_y : float = NAN
		if dh.is_empty():
			no_ground += 1
		else:
			under = String((dh["collider"] as Node).name)
			under_kind = _classify(dh["collider"] as Node)
			under_y = (dh["position"] as Vector3).y
		# Is the yard under the building roof? (informational — indoor storage
		# is legitimate; a yard that MOVED under a roof is not, so it is shown.)
		var uq := PhysicsRayQueryParameters3D.create(
			Vector3(c.x, Plant.floor_top_y() + 1.0, c.y),
			Vector3(c.x, Plant.floor_top_y() + 45.0, c.y))
		uq.collision_mask = 0xFFFFFFFF
		var roofed : bool = not space.intersect_ray(uq).is_empty()
		_info("yard #%d centroid (%.1f, %.1f) — under it: %s (%s) at y=%.2f | roof above: %s | %d corners"
			% [idx, c.x, c.y, under, under_kind, under_y, "YES" if roofed else "no", poly.size()])
	_check(no_ground == 0, "every yard centroid has real ground under it (%d with nothing)" % no_ground)

	# Yard bales are STREAMED, not built at boot: BaleYardManager.tick() only
	# materialises a slot's RigidBody while a player or a "vehicle"-group node is
	# inside the 24 m NEAR radius (BaleYardManager.gd:112). This test parks its
	# vehicles on their save markers, and those sit far from the yards — measured
	# 2026-08-18 from this test's own log, the nearest vehicle (BaleClamp) is
	# 58.7 m from the nearest yard centroid, a 34.7 m shortfall. So the drain
	# queue never ran, `yard_bale_rb` was always empty, and the vacuity guard
	# below failed on EVERY run since it was added (94c685b, 2026-07-22).
	#
	# Park one probe per yard so every yard streams in together, then give the
	# time-sliced queue frames to drain. Probes are freed at both exits so they
	# can never show up in check D's sweep of group "vehicle".
	var probes : Array[Node3D] = []
	for pp in polys:
		var ppoly : PackedVector2Array = pp
		if ppoly.size() < 3:
			continue
		var pc := Vector2.ZERO
		for pt in ppoly:
			pc += pt
		pc /= float(ppoly.size())
		var probe := Node3D.new()
		probe.name = "BaleStreamProbe"
		probe.add_to_group("vehicle")
		add_child(probe)
		probe.global_position = Vector3(pc.x, Plant.floor_top_y(), pc.y)
		probes.append(probe)
	var t_drain0 := Time.get_ticks_msec()
	var drain_frames := 0
	var drain_s := 0.0
	while true:
		await get_tree().process_frame
		drain_frames += 1
		drain_s = float(Time.get_ticks_msec() - t_drain0) / 1000.0
		var so_far : int = get_tree().get_nodes_in_group("yard_bale_rb").size()
		if (so_far > 0 and drain_s >= BALE_DRAIN_MIN_S) or drain_s >= BALE_DRAIN_MAX_S:
			break

	# Bale bodies vs solid geometry. Only the RBs the time-sliced drain queue has
	# actually produced exist yet; the count is printed so a small population can
	# never be mistaken for a clean result.
	var rbs : Array = get_tree().get_nodes_in_group("yard_bale_rb")
	_info("bale RBs materialised so far: %d (%d probe(s), %d frames / %.1f s of drain)"
		% [rbs.size(), probes.size(), drain_frames, drain_s])
	if rbs.is_empty():
		_check(false, "at least one bale body exists to test — 0 would make this check vacuous")
		_free_probes(probes)
		return
	var machine_rids : Array[RID] = []
	for m in machines:
		for co in _collision_objects(m as Node):
			machine_rids.append((co as CollisionObject3D).get_rid())
	var bad : int = 0
	var worst : float = 0.0
	var worst_desc : String = "n/a"
	for rn in rbs:
		var rb := rn as Node3D
		if rb == null:
			continue
		var own : Array[RID] = _own_rids(rb)
		for cs in (rb as Node).get_children():
			if not (cs is CollisionShape3D):
				continue
			var shp : Shape3D = (cs as CollisionShape3D).shape
			if shp == null:
				continue
			var base_xf : Transform3D = (cs as CollisionShape3D).global_transform
			var laabb : AABB = _shape_local_aabb(shp)
			var q := PhysicsShapeQueryParameters3D.new()
			q.shape = shp
			q.transform = base_xf
			q.collision_mask = 0xFFFFFFFF
			q.collide_with_bodies = true
			q.collide_with_areas = false
			q.exclude = own
			var hits : Array[Dictionary] = space.intersect_shape(q, 16)
			var rids : Array[RID] = []
			for h in hits:
				var r : RID = h.get("rid", RID())
				if not rids.has(r):
					rids.append(r)
			for h in hits:
				var col = h.get("collider")
				if col == null or not (col is Node):
					continue
				var kind : String = _classify(col as Node)
				if kind != "machine" and kind != "shell" and kind != "vehicle":
					continue
				var pen : float = _penetration(space, base_xf, laabb, own,
					h.get("rid", RID()), rids)
				if pen > PEN_SOLID:
					bad += 1
					if pen > worst:
						worst = pen
						worst_desc = "%s in %s (%s)" % [rb.name, (col as Node).name, kind]
	_check(bad == 0, "NO yard bale is embedded in the shell/a machine/a vehicle (%d of %d bales, worst %.0f %%: %s)"
		% [bad, rbs.size(), worst * 100.0, worst_desc])
	if machine_rids.is_empty():
		_info("note: no machine colliders collected — bale-vs-machine arm had nothing to hit")
	_free_probes(probes)


## Drop the streaming probes. Their bales despawn on the next tick, which is fine:
## every measurement above is already taken.
func _free_probes(probes: Array[Node3D]) -> void:
	for pr in probes:
		if is_instance_valid(pr):
			pr.queue_free()


# =============================================================================
# CHECK D — query-only proxy bodies must still be the size of the thing they
# proxy. Found while building this file: ShiftCarSpawner._add_parked_collider
# sizes its box from _visual_aabb(car), and that union comes back 28 x 33 x 44 m
# for every parked car — a 50 m phantom, centred ~17 m under grade. It is on
# layer 20 / mask 0 so nothing collides with it, but EVERY query that sweeps all
# layers hits it: the F10 feedback ray, and BuildMode's own vehicle-clearance
# sentinel (src/build/BuildMode.gd:1100-1106 deliberately probes every layer to
# find exactly these bodies). A clearance gate that trips on a phantom 25 m away
# is a clearance gate that cannot be trusted. Reported here rather than fixed —
# ShiftCarSpawner.gd is outside this task's file scope.
# =============================================================================
const PROXY_SANE_M : float = 8.0   # a parked car is < 6 m in every dimension

func _check_d_query_proxy_sanity() -> void:
	print("\n--- D. query-only proxy bodies are the size of what they proxy ---")
	var oversized : int = 0
	var total : int = 0
	var worst : float = 0.0
	for co in _collision_objects(_world):
		if not _is_query_only(co as Node):
			continue
		total += 1
		for cs in (co as Node).get_children():
			if not (cs is CollisionShape3D):
				continue
			var shp : Shape3D = (cs as CollisionShape3D).shape
			if shp == null:
				continue
			var sz : Vector3 = _shape_local_aabb(shp).size
			var biggest : float = maxf(sz.x, maxf(sz.y, sz.z))
			worst = maxf(worst, biggest)
			if biggest > PROXY_SANE_M:
				oversized += 1
				_info("OVERSIZED %s  box %.1f x %.1f x %.1f m" % [
					(co as Node).get_path(), sz.x, sz.y, sz.z])
	if total == 0:
		_info("no query-only proxy bodies in this world")
		return
	_advise(oversized == 0,
		"all %d query-only proxy box(es) are under %.0f m (%d oversized, worst %.1f m)"
			% [total, PROXY_SANE_M, oversized, worst])


# =============================================================================
# Teardown
# =============================================================================
## The verdict is printed and user:// restored BEFORE the world is freed, then
## restored again after: the headless teardown segfault lands inside world
## teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
func _finish() -> void:
	_wlg.restore()
	print("\n=========================================")
	print("Result: %s (%d ok, %d fail, %d advisory)" % [
		"PASS" if _fails == 0 else "FAIL", _oks, _fails, _advisories])
	if _advisories > 0:
		print("  (advisories are MEASURED DEFECTS this file is not the gate for — see _advise)")
	print("=========================================")
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = null
		_world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fails == 0 else 1)


