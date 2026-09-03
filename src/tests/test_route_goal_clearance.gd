extends SceneTree
# =============================================================================
# VehicleRouteGrid.goal_clearance() — the signal route() never gave its callers.
# =============================================================================
# route() deliberately replaces its final grid waypoint with the RAW ordered
# pose, because a goal is routinely inside a container or a cart pocket and a
# router that refused those would break working tasks. The cost was that a caller
# could not tell "your goal is free" from "your goal is inside a machine and you
# will never arrive".
#
# WHAT goal_clearance DOES NOT COVER, said here so this suite is not mistaken for
# broader proof than it is: VehicleRouteGrid._blocks() rejects anything that is not
# a StaticBody3D, so the grid is blind to the player (CharacterBody3D), crew NPCs
# and RigidBody3D bales. The 2026-09-03 test_jam_baseline failure that prompted
# this work was a forklift ordered onto player_spawn — BLOCKED by ["Player"] to a
# hull probe, but 0.00 m to goal_clearance, because the player is not static. What
# is proved below is the STATIC-geometry answer: machines, walls, containers.
# Dynamic occupancy needs a live shape query and is a named follow-up.
# docs/audit/jam_baseline_2026-09-03.md has the trace.
#
# WHY THIS SUITE IS A UNIT TEST AND NOT A WORLD BOOT. goal_clearance() reads only
# region_min / cols / rows / _solid and uses no A* and no
# PhysicsDirectSpaceState3D, so a synthetic occupancy grid exercises every branch
# in milliseconds instead of the ~90 s a MainWorld boot costs. The world-level
# behaviour it protects is already covered by test_jam_baseline; what needs
# proving here is the arithmetic, at every boundary.
#
#   GODOT --headless --path . --script res://src/tests/test_route_goal_clearance.gd
#
# RED BEFORE THE FIX: goal_clearance() did not exist, so every check below
# errors out on a missing method rather than passing vacuously.
# =============================================================================

var _pass := 0
var _fail := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		print("  ok    : %s" % msg)
	else:
		_fail += 1
		print("  FAIL  : %s" % msg)

func _initialize() -> void:
	call_deferred("_run")

## A grid with a known solid patch and nothing else. CELL_M is 2.0 m, so cell
## (c, r) covers world x in [c*2, c*2+2) and z in [r*2, r*2+2), and cell_to_world
## returns its CENTRE.
func _make_grid(cols: int, rows: int, solid_cells: Array) -> VehicleRouteGrid:
	var g := VehicleRouteGrid.new()
	g.region_min = Vector2.ZERO
	g.cols = cols
	g.rows = rows
	g.floor_y = 0.0
	var arr := PackedByteArray()
	arr.resize(cols * rows)
	arr.fill(0)
	for c in solid_cells:
		var cc : Vector2i = c
		arr[cc.y * cols + cc.x] = 1
	g._solid = arr
	g.blocked_cells = solid_cells.size()
	return g

func _run() -> void:
	print("=== VehicleRouteGrid.goal_clearance ===")

	# Not counted as a check: if this were false the script would not have
	# compiled, so scoring it would inflate the ok-count without proving anything.
	var script_ok : bool = VehicleRouteGrid != null
	print("  info  : VehicleRouteGrid resolves as a class_name: %s" % str(script_ok))
	if not script_ok:
		_finish()
		return

	# A 10 x 10 grid (20 x 20 m) with one solid cell at (5,5) — world x 10..12,
	# z 10..12, centre (11, 11).
	var g := _make_grid(10, 10, [Vector2i(5, 5)])
	# Also not counted — this only asserts that _make_grid did what _make_grid says.
	print("  info  : synthetic grid is %d x %d cells (%.0f x %.0f m at CELL_M %.1f)"
		% [g.cols, g.rows, g.cols * VehicleRouteGrid.CELL_M, g.rows * VehicleRouteGrid.CELL_M,
			VehicleRouteGrid.CELL_M])
	_ok(g.is_solid(Vector2i(5, 5)), "the planted solid cell reads solid")
	_ok(not g.is_solid(Vector2i(4, 5)), "its neighbour reads free")

	# ---- 1. A FREE pose reports exactly zero ------------------------------
	# Anywhere in a free cell, not just its centre: the caller's pose is arbitrary.
	for p in [Vector3(1.0, 0.0, 1.0), Vector3(3.0, 0.0, 7.0), Vector3(0.05, 0.0, 0.05), Vector3(19.9, 0.0, 19.9)]:
		var pv : Vector3 = p
		_ok(absf(g.goal_clearance(pv)) < 0.0001,
			"a pose on free ground %s reports 0.00 m clearance" % str(pv))

	# ---- 2. A pose INSIDE the solid cell reports a real, positive distance --
	# Centre of the solid cell is (11, 11); the nearest free cell centre is one
	# cell away, i.e. 2.0 m, in whichever direction _nearest_free's ring finds.
	var d_centre : float = g.goal_clearance(Vector3(11.0, 0.0, 11.0))
	_ok(d_centre > 0.0, "a pose inside a solid cell reports a POSITIVE clearance (%.2f m), not 0" % d_centre)
	# THE DIAGONAL IS CORRECT, and this expectation was wrong first time round.
	# _nearest_free scans each ring in iteration order and returns the FIRST free
	# cell, which for r = 1 is the (-1,-1) corner — so the answer is CELL_M * sqrt2
	# = 2.83 m, not the 2.00 m an orthogonal neighbour would give. goal_clearance
	# must report where route() will ACTUALLY snap the vehicle, and route() snaps
	# through the same function, so agreeing with it beats being geometrically
	# prettier.
	_ok(absf(d_centre - VehicleRouteGrid.CELL_M * sqrt(2.0)) < 0.0001,
		"from the solid cell's centre it is one DIAGONAL cell to the free cell _nearest_free picks (%.2f m = CELL_M * sqrt2)"
			% d_centre)

	# A pose in the same solid cell but nearer its edge is CLOSER to free ground.
	# This is the check that a constant would fail: the answer tracks the pose.
	var d_edge : float = g.goal_clearance(Vector3(10.1, 0.0, 11.0))
	_ok(d_edge < d_centre,
		"a pose near the solid cell's edge is closer to free ground than its centre (%.2f m < %.2f m)"
			% [d_edge, d_centre])

	# ---- 3. The threshold that actually matters ----------------------------
	# BaseVehicle.npc_arrived() succeeds within NPC_ARRIVE_TOL of the ORDERED
	# pose. A 3 x 3 solid block makes its centre unreachable by more than that,
	# which is the case where an order can never complete.
	var block : Array = []
	for dx in range(4, 7):
		for dz in range(4, 7):
			block.append(Vector2i(dx, dz))
	var g2 := _make_grid(12, 12, block)
	var d_block : float = g2.goal_clearance(Vector3(11.0, 0.0, 11.0))   # centre of the 3x3
	_ok(d_block > BaseVehicle.NPC_ARRIVE_TOL,
		"the centre of a 3 x 3 solid block is further than NPC_ARRIVE_TOL from free ground (%.2f m > %.2f m) — an order there can never complete"
			% [d_block, BaseVehicle.NPC_ARRIVE_TOL])
	_ok(absf(d_block - (VehicleRouteGrid.CELL_M * 2.0 * sqrt(2.0))) < 0.0001,
		"and it is two DIAGONAL cells out (%.2f m), consistent with the same ring scan" % d_block)

	# ---- 4. A fully solid grid reports the miss, it does not lie -----------
	var all_solid : Array = []
	for cx in range(6):
		for cz in range(6):
			all_solid.append(Vector2i(cx, cz))
	var g3 := _make_grid(6, 6, all_solid)
	_ok(g3.goal_clearance(Vector3(5.0, 0.0, 5.0)) < 0.0,
		"a grid with no free cell at all reports -1.0, the same miss route() reports as an empty route")

	# ---- 5. It needs no A* and no physics ---------------------------------
	# The whole point of the unit form: none of the above built an AStarGrid2D.
	_ok(g._astar == null,
		"every check above ran with _astar still null — goal_clearance needs no A* and no world")
	# And route() on that same grid correctly refuses, so the two are independent.
	_ok(g.route(Vector3(1.0, 0.0, 1.0), Vector3(3.0, 0.0, 3.0)).is_empty(),
		"route() on an unbuilt grid still returns empty (the two entry points do not interfere)")

	# ---- 6. Off-map poses are clamped, not called free --------------------
	# route() clamps out-of-region endpoints, so this must agree with it rather
	# than reporting a pose 100 m off the survey as standable.
	# This check FOUND A BUG in goal_clearance before it shipped: clamping the cell
	# before testing it for freeness made a pose 100 m off the survey clamp onto a
	# free edge cell and report 0.00 m. It now tests the RAW cell for bounds.
	var d_off : float = g.goal_clearance(Vector3(120.0, 0.0, 120.0))
	_ok(d_off > 100.0,
		"a pose 120 m outside a 20 m survey reports the real distance to the nearest surveyed free cell (%.2f m), not 0 — clamping must not read as 'free'"
			% d_off)

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
