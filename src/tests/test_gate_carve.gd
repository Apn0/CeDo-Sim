extends Node
# =============================================================================
# #GATECARVE — LIVE gate/door placement must invoke the SAME carve reload did.
# =============================================================================
# Operator report 2026-07-22: "i tried placing an industrial gate (roller
# gate), but no way through was created."
#
# ROOT CAUSE #1 (measured, fixed): PlaceableCatalog.build_node's door_
# personnel / gate_roller / window_frame branch builds DECORATION ONLY —
# comment #116 there says outright "operator drops them into a pre-existing
# hole". The only code that ever carved the matching WallOpenings hole was
# BuildMode._load_structure_placeable — which runs ONLY on SAVE→RELOAD, never
# on the live single-click placement path (_place_current). So a freshly
# clicked gate stood in front of an intact wall until the operator saved and
# reloaded the whole world.
#
# FIX: _place_current now calls the same carve (_carve_structure_opening,
# factored out of the reload path) immediately. This test proves the carve
# mechanism runs THE SAME FRAME the gate is placed — no save, no reload — and
# that the vehicle route grid, which samples colliders once and caches, is
# invalidated so a vehicle already driving this session sees the new gap on
# its next order. ALSO proves the mirror: deleting the gate re-triggers the
# carve removal and invalidates the grid again.
#
# ROOT CAUSE #2 (measured, FIXED 2026-08-29): on the operator's OWN building,
# WallOpenings' triangle carve did not actually open a passable hole at the
# wall location this test picks, even though _carve_structure_opening ran
# correctly (has_opening() true, "[WallOpenings] Rebuilt — 1 openings"
# logged). A same-day attempt to widen the coplanarity test (angle-based
# instead of per-vertex-absolute, tolerance widened to the box's own
# half-depth) fixed passability on THIS building but REGRESSED the existing
# src/tests/test_door_carve.gd (0 -> 13 visible teeth). Reverted; the real
# cause was measured properly afterward with a throwaway diagnostic booting
# this same MainWorld and dumping every WallOpenings._orig_surfaces /
# _visual_surfaces triangle's box-local Z near this exact wall
# (-254.77,-8.00,95.84): the wall is a real closed box (built by
# tools/generate_building.py, T=0.30 wall thickness) — outer skin at
# box-local z=0.0046, inner skin at z=-0.2954, i.e. ~0.30 m apart along the
# opening's depth axis. WallOpenings._COPLANAR_TOL (5 cm) was 5.9x too small
# to ever reach that inner skin, so it silently stayed un-carved — solid from
# the inside, exactly matching the operator's report.
#
# FIX (src/build/WallOpenings.gd): the coplanarity tolerance now tracks the
# existing `solidify_enabled` switch instead of being one fixed global
# constant — solidify_enabled=true (thin mesh + runtime solidify, e.g.
# test_door_carve.gd's synthetic wall) keeps tol = WALL_THICK (0.05 m,
# BIT-FOR-BIT unchanged — a bare global widen was tried first and regressed
# test_door_carve.gd 0 -> 13 teeth the same way the angle-based attempt did);
# solidify_enabled=false (the live parametric shell) uses tol = 0.35 m (the
# measured 0.2954 m gap + margin). Same per-vertex-absolute-distance algorithm
# throughout — only which constant applies changed, keyed off geometry the
# caller already declares. Passability on this exact wall: 0/5 -> 5/5. The
# passability check below is now a GATING assertion, not diagnostic.
#
#   GODOT --headless --path . res://src/tests/test_gate_carve.tscn
# =============================================================================

const TEST_SLOT : String = "__gatecarve__"
const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__gatecarve___save.json",
	"user://__gatecarve___factory.json",
]

## How far past the shell AABB the outside probe sits. Same order of magnitude
## as test_nav_connectivity's EXTERIOR_MARGIN_M, proven to land outside the
## fixture's shell.
const PROBE_MARGIN_M : float = 18.0
## Span of the "is this segment solid" sanity ray, centred on the hit point,
## along the MEASURED surface normal (not an assumed wall thickness).
const WALL_PROBE_HALF_M : float = 1.5

const BOOT_FRAMES : int = 120

var _backups : Dictionary = {}
var _oks   : int = 0
var _fails : int = 0
var _world : Node3D = null

func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)

func _info(msg: String) -> void:
	print("  info  : %s" % msg)

func _ready() -> void:
	print("=== #GATECARVE — live gate placement must invoke the real carve ===")
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
	for i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var bm : Node = _world.get("build_mode")
	if bm == null:
		_check(false, "world.build_mode is present"); _finish(1); return
	var wall_openings = bm.get("wall_openings")
	if wall_openings == null:
		_check(false, "BuildMode.wall_openings is present (shell must exist)"); _finish(1); return

	# ── Find a REAL, currently-solid wall face, and its true surface normal ──
	var shell := _shell()
	if shell == null:
		_check(false, "the building shell is findable"); _finish(1); return
	var box : AABB = NavSiteBounds.body_aabb(shell)
	if box.size == Vector3.ZERO:
		_check(false, "the shell has a measurable footprint"); _finish(1); return
	var centre : Vector3 = box.get_center()
	var floor_y : float = box.position.y + 1.0   # clear of low kerbs, well under any wall's height
	var outside : Vector3 = Vector3(box.position.x - PROBE_MARGIN_M, floor_y, centre.z)
	var inside  : Vector3 = Vector3(centre.x, floor_y, centre.z)
	_info("shell AABB %.0f x %.0f m centred (%.1f, %.1f); probing outside(%.1f,%.1f) -> inside(%.1f,%.1f)"
		% [box.size.x, box.size.z, centre.x, centre.z, outside.x, outside.z, inside.x, inside.z])

	var space : PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(outside, inside)
	q.collide_with_areas = false
	var hit := space.intersect_ray(q)
	if hit.is_empty() or not _is_shell_hit(hit.get("collider")):
		_check(false, "the outside->inside probe actually hits the shell (got %s)"
			% (String((hit.get("collider") as Node).name) if not hit.is_empty() and hit.get("collider") != null else "nothing"))
		_finish(1); return
	var hit_pos : Vector3 = hit["position"]
	var normal  : Vector3 = hit["normal"]
	normal.y = 0.0
	normal = normal.normalized()
	_info("wall hit at (%.2f, %.2f, %.2f), surface normal (%.3f, %.3f)"
		% [hit_pos.x, hit_pos.y, hit_pos.z, normal.x, normal.z])

	# Carve-box local +Z (the depth axis add_opening punches along) maps to the
	# world direction (-sin(rot_y), 0, cos(rot_y)) — see WallOpenings._to_box.
	# Solve for rot_y so that direction equals the MEASURED normal.
	var rot_y : float = atan2(-normal.x, normal.z)

	# _carve_structure_opening cuts centred at pos + (0, catalog_height*0.5, 0) —
	# pos being the PLACED node's floor-level Y (hit_pos.y here). Probe at that
	# SAME height: the real cut sits at floor+1.8 m (half of gate_roller's
	# 3.6 m catalog height), not at the raycast height (~floor+1 m).
	var gate_h : float = float(PlaceableCatalog.get_item("gate_roller").get("size", Vector3(3.5, 3.6, 0.2)).y)
	var probe_centre : Vector3 = hit_pos + Vector3(0.0, gate_h * 0.5, 0.0)
	var parallel : Vector3 = Vector3(-normal.z, 0.0, normal.x).normalized()
	var sample_offsets := [-1.2, -0.6, 0.0, 0.6, 1.2]   # within the 3.5 m width (half 1.75)

	# ── BEFORE: this exact spot is solid ────────────────────────────────────
	_check(_wall_blocks(space, probe_centre, normal),
		"BEFORE: the wall is solid at the chosen point (sanity check on our own probe)")

	# ── PLACE the gate live, through the real BuildMode path ───────────────
	bm.call("_enter_placing", "gate_roller")
	await get_tree().process_frame
	var ghost : Node3D = bm.get("_ghost")
	if ghost == null:
		_check(false, "ghost built by _enter_placing"); _finish(1); return
	ghost.visible = true
	ghost.global_position = hit_pos
	bm.set("_ghost_rot_y", rot_y)

	# Snapshot the shared vehicle route grid with a NON-NULL sentinel so we can
	# prove invalidation actually fired, not just that it was null already.
	BaseVehicle._route_grid = VehicleRouteGrid.new()
	BaseVehicle._route_grid_world = _world.get_instance_id()
	_check(BaseVehicle._route_grid != null, "route-grid sentinel armed before placement")

	var placed_root : Node = bm.get("_placed_root")
	var before_children := placed_root.get_child_count()
	bm.call("_place_current")
	await get_tree().process_frame

	_check(placed_root.get_child_count() == before_children + 1,
		"exactly one new node was placed (got %d new)" % (placed_root.get_child_count() - before_children))
	var gate_node : Node3D = placed_root.get_child(placed_root.get_child_count() - 1) as Node3D
	_check(gate_node != null and String(gate_node.get_meta("placeable_id", "")) == "gate_roller",
		"the new node is the gate_roller we placed")
	_check(gate_node != null and gate_node.has_meta("opening_id"),
		"the placed gate carries opening_id meta (so delete can restore the wall)")

	# ── THE FIX (asserted): the carve mechanism fires THIS FRAME, not on reload.
	var oid : String = String(gate_node.get_meta("opening_id", "")) if gate_node != null else ""
	_check(gate_node != null and bool(wall_openings.call("has_opening", oid)),
		"WallOpenings registered the opening immediately (has_opening true, no save/reload)")

	# ── ROOT CAUSE #2 (GATING, fixed 2026-08-29 — see file header for the
	# measured gap and the WallOpenings.gd fix). Require at least 4/5 sample
	# points clear (ideally 5/5); a regression here means the coplanarity
	# tolerance stopped reaching the live building's real double-skin gap.
	var open_count := 0
	for off in sample_offsets:
		if not _wall_blocks(space, probe_centre + parallel * off, normal):
			open_count += 1
	_info("PASSABILITY: open across %d/%d sample points" % [open_count, sample_offsets.size()])
	_check(open_count >= sample_offsets.size() - 1,
		"PASSABILITY: at least %d/%d sample points clear (got %d)"
			% [sample_offsets.size() - 1, sample_offsets.size(), open_count])

	_check(BaseVehicle._route_grid == null,
		"placing the gate invalidated the shared vehicle route grid")

	# ── THE MIRROR: deleting the gate removes the opening registration ─────
	BaseVehicle._route_grid = VehicleRouteGrid.new()
	_check(BaseVehicle._route_grid != null, "route-grid sentinel re-armed before deletion")
	bm.set("_edit_selected", gate_node)
	bm.call("_edit_delete_selected")
	await get_tree().process_frame

	_check(not bool(wall_openings.call("has_opening", oid)),
		"deleting the gate removed the WallOpenings registration")
	_check(BaseVehicle._route_grid == null,
		"deleting the gate invalidated the shared vehicle route grid again")

	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	_finish(0 if _fails == 0 else 1)

## True when the SHELL SPECIFICALLY blocks a short ray centred on `centre`,
## spanning WALL_PROBE_HALF_M either side along `normal`. Deliberately NOT "is
## anything hit": a placed gate/door carries its OWN closed-leaf collision
## (build_gate: a 0.10 m-thick BoxShape3D on the leaf, PlaceableCatalog.gd
## ~8945) which legitimately still blocks the spot — that is a real, separate
## object standing in an open gap, not the wall.
func _wall_blocks(space: PhysicsDirectSpaceState3D, centre: Vector3, normal: Vector3) -> bool:
	var a := centre + normal * WALL_PROBE_HALF_M
	var b := centre - normal * WALL_PROBE_HALF_M
	var excl : Array[RID] = []
	for _attempt in 6:   # walk past the gate leaf (and anything else non-shell)
		var q := PhysicsRayQueryParameters3D.create(a, b)
		q.collide_with_areas = false
		q.exclude = excl
		var hit := space.intersect_ray(q)
		if hit.is_empty():
			return false
		if _is_shell_hit(hit.get("collider")):
			return true
		excl.append(hit["rid"])
	return false

func _is_shell_hit(collider: Object) -> bool:
	var n := collider as Node
	while n != null:
		if n.name in ["ShellCollision", "BuildingShell", "ShellMesh"]:
			return true
		n = n.get_parent()
	return false

func _shell() -> Node3D:
	for nm in ["ShellCollision", "BuildingShell", "ShellMesh"]:
		var n := _world.find_child(nm, true, false)
		if n is Node3D:
			return n as Node3D
	return null

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

func _finish(code: int) -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(code)
