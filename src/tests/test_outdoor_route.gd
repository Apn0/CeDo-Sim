extends Node
# =============================================================================
# npc-06 — CAN A VEHICLE BE ROUTED TO AN OUTDOOR POSITION AND ACTUALLY GET THERE?
# =============================================================================
#   GODOT --headless --path . res://src/tests/test_outdoor_route.tscn
#
# THIS IS AN OPERATOR DECISION TEST, not a unit test. The outdoor skip was moved
# from offset (12, 0, 45.5) to (12, 0, 28.0) because a forklift sent to the far
# position covered 47 m in 141 s and wedged 6.95 m short, moving zero kilograms.
# If a vehicle can now be ROUTED to an exterior position and arrive, that
# interim retreat can be reconsidered — so this file answers the question with a
# number instead of an impression.
#
# THE DISTINCTION THAT MATTERS, AND WHY THE ROUTE-POINT ASSERTION IS HERE.
# A forklift can arrive at an outdoor point by dead reckoning whenever the
# straight line happens to be clear. That is luck, not routing, and crediting it
# would be the same class of claim as "31/31 green while zero kilograms moved".
# So arrival ALONE is not accepted: the leg must also show the router produced
# real waypoints (BaseVehicle.npc_route_points). Both, or it does not count.
#
# WHAT THIS FILE DELIBERATELY DOES NOT TEST: crossing the building facade. The
# operator's survey has ZERO doorways (world_layout structure_items is empty), so
# VehicleRouteGrid correctly reports the interior unreachable for a 2.2 m probe
# and BaseVehicle._plan_route (BaseVehicle.gd:1045) warns and dead-reckons. That
# is a survey gap, not a routing defect, and it is measured in the companion
# EXTERIOR->INTERIOR probe below rather than hidden.
# =============================================================================

const TEST_SLOT : String = "__outdoorroute__"

const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__outdoorroute___save.json",
	"user://__outdoorroute___factory.json",
]

## Clearance beyond the shell footprint for a probe that must be unambiguously
## outdoors. Derived from the MEASURED shell AABB, never a constant.
const OUTDOOR_MARGIN_M : float = 25.0
## Arrival gate. Matches OverflowDumpTask.APPROACH_DIST_VEH so a pass here means
## the real task's gate would also be satisfied.
const ARRIVE_TOL_M : float = 3.5
const WEDGE_BUDGET_S : float = 3.0

const BOOT_FRAMES   : int = 120
const SETTLE_FRAMES : int = 60
## 300 s at 60 Hz. SIZED FROM A MEASUREMENT, NOT PICKED. The first run of this
## file used 120 s and reported a FAIL that was entirely my own budget: the trace
## read "timeout, 109.19 m from target (best 109.19 m), covered 212.6 m" — final
## distance EQUAL to best distance, i.e. the forklift was still closing when the
## clock ran out, at an average 1.77 m/s. Rounding a 155 m building needs ~205 m
## of travel and that is ~120 s of driving before any detour. Calling that a
## routing defect would have been a manufactured red, which is the same sin as a
## vacuous green with the sign flipped.
const DRIVE_FRAMES  : int = 18000
## The genuine non-convergence guard stays: 40 s without closing half a metre.
## A vehicle that circles is caught by this, not by the total budget.
const NO_PROGRESS_FRAMES : int = 2400

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
	print("=== npc-06 — outdoor vehicle routing ===")
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
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	await _test_outdoor_leg()
	_probe_interior_reachability()

	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)"
		% ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	_finish(0 if _fails == 0 else 1)

# ── The leg ───────────────────────────────────────────────────────────────────
func _test_outdoor_leg() -> void:
	_section("OUTDOOR LEG — apron to apron, both endpoints verified outside the shell")
	var shell := _shell()
	if shell == null:
		_check(false, "the building shell is findable (its footprint defines 'outdoors')")
		return
	var box := NavSiteBounds.body_aabb(shell)
	if box.size == Vector3.ZERO:
		_check(false, "the shell has a measurable footprint")
		return
	var c : Vector3 = box.get_center()
	var floor_y : float = box.position.y
	# Two apron points on opposite ends of the building's long axis. The straight
	# line between them runs THROUGH the shell, so a vehicle that arrives had to
	# route around it — which is precisely the capability under test.
	var start := Vector3(c.x, floor_y, box.position.z - OUTDOOR_MARGIN_M)
	var goal  := Vector3(c.x, floor_y, box.position.z + box.size.z + OUTDOOR_MARGIN_M)
	_info("shell %.0f x %.0f m; start (%.1f, %.1f) goal (%.1f, %.1f)"
		% [box.size.x, box.size.z, start.x, start.z, goal.x, goal.z])

	# ANTI-VACUITY. If either probe were inside the shell this becomes the
	# facade-crossing test, which is known-unroutable, and the failure would be
	# blamed on routing instead of on the missing doorways.
	var s_out : bool = not box.has_point(Vector3(start.x, c.y, start.z))
	var g_out : bool = not box.has_point(Vector3(goal.x, c.y, goal.z))
	_check(s_out and g_out,
		"both endpoints are genuinely outdoors (start outside=%s, goal outside=%s)"
			% [str(s_out), str(g_out)])
	# And the straight line must be obstructed, or the leg proves nothing about
	# routing: a clear bearing is cleared by dead reckoning alone.
	_check(box.has_point(Vector3(c.x, c.y, c.z)),
		"the shell sits between the two endpoints (the straight line is blocked)")

	var fl := _grab_forklift()
	if fl == null:
		_check(false, "an unoccupied forklift is available")
		return

	var ground_y : float = _ground_y_at(start)
	fl.global_position = Vector3(start.x, ground_y + 1.2, start.z)
	fl.rotation = Vector3.ZERO
	for _i in range(20):
		await get_tree().physics_frame
	# A leg that starts on the roof drives unobstructed and passes everything
	# below while proving nothing. Measured failure, first run of the sibling
	# harness — hence the assertion.
	_check(absf(fl.global_position.y - floor_y) <= 3.0,
		"the leg starts on the apron, not a roof (y=%.2f, floor %.2f)"
			% [fl.global_position.y, floor_y])

	var rec := VehicleJamRecorder.new()
	rec.name = "JamRecorder"
	fl.add_child(rec)
	rec.watch(fl)
	rec.begin_leg("outdoor_apron_to_apron", goal)
	# Ordered through the REAL entry point so npc_set_target's NPC_TARGET_MAX_R
	# guard stays on the path.
	fl.call("npc_set_target", goal)
	var route_pts : int = 0
	if fl.has_method("npc_route_points"):
		route_pts = int(fl.call("npc_route_points"))
		rec.note_path_points(route_pts)

	var outcome := "timeout"
	var best : float = INF
	var since_gain : int = 0
	for _i in range(DRIVE_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(fl):
			outcome = "vehicle_gone"
			break
		if bool(fl.call("npc_arrived")):
			outcome = "arrived"
			break
		var d : float = Vector2(fl.global_position.x - goal.x,
			fl.global_position.z - goal.z).length()
		if d < best - 0.5:
			best = d
			since_gain = 0
		else:
			since_gain += 1
			if since_gain > NO_PROGRESS_FRAMES:
				outcome = "stalled"
				break
	rec.end_leg(outcome)
	var leg : Dictionary = rec.leg("outdoor_apron_to_apron")
	print("  trace : %s" % VehicleJamRecorder.describe(leg))
	if fl.has_method("npc_stop"):
		fl.call("npc_stop")
	rec.queue_free()

	# THE ROUTER MUST HAVE PRODUCED A ROUTE. Without this the next two checks can
	# be satisfied by a lucky straight line and the operator would be told
	# "outdoor routing works" on the strength of dead reckoning.
	_check(route_pts > 0,
		"the router produced a real route for this leg (%d waypoints — 0 means it dead-reckoned and the arrival below is luck)"
			% route_pts)
	_check(outcome == "arrived", "the outdoor leg completed (outcome '%s')" % outcome)
	_check(float(leg.get("final_dist_m", 1e9)) <= ARRIVE_TOL_M,
		"the forklift reached the outdoor position (%.2f m, gate %.1f)"
			% [float(leg.get("final_dist_m", 1e9)), ARRIVE_TOL_M])
	_check(float(leg.get("wedge_seconds", 0.0)) < WEDGE_BUDGET_S,
		"the outdoor leg stayed under the wedge budget (%.1f s, limit %.1f)"
			% [float(leg.get("wedge_seconds", 0.0)), WEDGE_BUDGET_S])

# ── Companion probe: is the interior reachable for a VEHICLE at all? ──────────
# Reported, never asserted. This is the doorway survey gap, and turning it into a
# red would be gating this work on an operator task no engineering can close.
func _probe_interior_reachability() -> void:
	_section("FACADE — reported, not asserted (doorway survey gap)")
	var shell := _shell()
	if shell == null:
		return
	var box := NavSiteBounds.body_aabb(shell)
	if box.size == Vector3.ZERO:
		return
	var wl := get_node_or_null("/root/WorldLayout")
	var doors : int = 0
	if wl != null:
		var si = wl.get("structure_items")
		if si is Array:
			doors = (si as Array).size()
	_info("world_layout structure_items (doorways): %d" % doors)
	var interior := Vector3(box.get_center().x, box.position.y, box.get_center().z)
	var outside := Vector3(box.position.x + box.size.x + OUTDOOR_MARGIN_M,
		box.position.y, box.get_center().z)
	var bounds := NavSiteBounds.compute(_world)
	var grid := VehicleRouteGrid.new()
	if bounds.size != Vector3.ZERO and grid.build(_world, bounds, box.position.y):
		var r : PackedVector3Array = grid.route(outside, interior)
		_info("VEHICLE route outside -> interior: %d waypoints%s"
			% [r.size(), "" if r.size() > 0 else "  (expected: no doorways exist to drive through)"])

# ── Helpers ───────────────────────────────────────────────────────────────────
func _shell() -> Node3D:
	for nm in ["ShellCollision", "BuildingShell", "ShellMesh"]:
		var n := _world.find_child(nm, true, false)
		if n is Node3D:
			return n as Node3D
	return null

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

## Probe from 2 m up, never from altitude: an indoor probe started high finds the
## ROOF and the fixture then drives across it.
func _ground_y_at(pos: Vector3) -> float:
	var space := _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(
		Vector3(pos.x, pos.y + 2.0, pos.z), Vector3(pos.x, pos.y - 60.0, pos.z))
	var hit := space.intersect_ray(q)
	return float((hit as Dictionary).get("position", Vector3(0.0, -9.0, 0.0)).y) if hit else -9.0

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
