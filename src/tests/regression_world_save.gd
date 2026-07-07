extends Node3D
## AUTOMATED REGRESSION — world creation + save creation, with a top-down
## verification dump so correctness is PROVEN, not assumed.
##
##   godot --headless --main-scene res://src/tests/regression_world_save.tscn
##
## What it proves
## --------------
## Boots the REAL MainWorld against the REAL world_layout.json, then:
##
##  WORLD CREATION
##   - Plant initialised; building shell present with a real mesh;
##   - operating-floor grade at ~-9.0 (the site datum, not a wing roof);
##   - every door in WorldLayout.structure_items sits ON a wall line.
##
##  SAVE CREATION (the "machines outside the building" class of bug)
##   - every id in LINE_3A_SEQ resolves in the catalog (no silent drops);
##   - a line built from the macro places the expected machine count;
##   - EVERY placed machine lands INSIDE the true building footprint —
##     tested by converting each machine's scene position back to the
##     building frame (Plant.scene_to_pc -> bf) and checking the real wall
##     rectangles, NOT the rotated AABB (which is the trap that hid this);
##   - save -> clear -> reload reproduces every machine position to <1 cm
##     (round-trip fidelity — the loader is not silently shifting anything).
##
## Emits user://regression_positions.json for tools/regression/topdown_render.py.
## Backs up and restores every user:// file it touches, so the operator's real
## world_layout.json and saves are never harmed.

# ── Building frame (bf) -> Plant Coordinates affine (operator-verified) ────────
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)

# True outer wall outline in bf (the 10-corner union, NOT an AABB).
const BF_OUTLINE := [
	Vector2(0.0, 0.0), Vector2(150.7, 0.0), Vector2(150.7, 31.5),
	Vector2(131.5, 31.5), Vector2(131.5, 71.5), Vector2(81.0, 71.5),
	Vector2(81.0, 66.0), Vector2(57.0, 66.0), Vector2(57.0, 61.0),
	Vector2(0.0, 61.0),
]
# Interior as axis-aligned bf rectangles [xmin, xmax, zmin, zmax] — exact
# containment test after mapping a machine back into the building frame.
const BF_RECTS := [
	[0.0, 120.0, 0.0, 61.0],       # arched halls
	[120.0, 150.7, 0.0, 31.5],     # SW flat wing
	[120.0, 131.5, 31.5, 61.0],    # SE wing
	[57.0, 81.0, 61.0, 66.0],      # annex west (shallow)
	[81.0, 131.5, 61.0, 71.5],     # annex east
]
# Wall lines a door/gate is allowed to sit on (bf coordinate + which axis).
const INSIDE_MARGIN := 0.6          # m of slack for a machine centre near a wall
const DOOR_WALL_TOL := 1.6          # m a door centre may be off a wall line
const GRADE_Y := -9.0
const GRADE_TOL := 0.25
const ROUNDTRIP_TOL := 0.01         # 1 cm

const TEST_SLOT := "__regression__"
const TOUCHED := [
	"user://world_layout.json", "user://world_layout_consumed.flag",
	"user://__regression___save.json", "user://__regression___factory.json",
]
const DUMP_PATH := "user://regression_positions.json"

var _pass := 0
var _fail := 0
var _skip := 0
var _backups : Dictionary = {}
var _dump : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _section(t: String) -> void:
	print("\n[%s]" % t)


# ── bf helpers ────────────────────────────────────────────────────────────────
func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU

func _pc_to_bf(pc: Vector2) -> Vector2:
	var d := pc - BF_O
	return Vector2(d.dot(BF_XU), d.dot(BF_ZU))

func _scene_to_bf(pos: Vector3) -> Vector2:
	return _pc_to_bf(Plant.scene_to_pc(pos))

func _bf_inside(bf: Vector2, margin: float) -> bool:
	for r in BF_RECTS:
		if bf.x >= r[0] - margin and bf.x <= r[1] + margin \
				and bf.y >= r[2] - margin and bf.y <= r[3] + margin:
			return true
	return false

func _on_a_wall(bf: Vector2) -> bool:
	return absf(bf.y - 71.5) < DOOR_WALL_TOL or absf(bf.y - 61.0) < DOOR_WALL_TOL \
		or absf(bf.y - 0.0) < DOOR_WALL_TOL or absf(bf.x - 150.7) < DOOR_WALL_TOL \
		or absf(bf.x - 0.0) < DOOR_WALL_TOL or absf(bf.y - 66.0) < DOOR_WALL_TOL


func _ready() -> void:
	print("=== REGRESSION — world creation + save creation ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via --main-scene, not --script)")
		get_tree().quit(2); return

	_backup_files()

	# Load-existing (not new-save) so MainWorld builds the configured world
	# without entering the interactive setup flow (which would hang headless).
	# The per-save factory file was wiped, so machines start empty.
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _restore_files(); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	# Let _ready cascade + deferred spawns settle.
	for i in range(80):
		await get_tree().process_frame

	_dump["meta"] = {
		"world_yaw_deg": rad_to_deg(Plant.world_yaw_rad()) if Plant.is_initialized() else null,
		"floor_grade_y": Plant.floor_top_y() if Plant.is_initialized() else null,
	}

	_test_world_creation(world, wl)
	_test_macros()   # BEFORE save-creation, which clears the in-memory macro cache
	await _test_save_creation(world)
	_collect_footprint_and_doors(wl)
	_test_exterior(world)

	# Verdict list for the render.
	_dump["checks"] = [
		{"name": "world_creation+save_creation", "pass": _fail == 0},
	]
	_write_dump()

	world.queue_free()
	_restore_files()
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Dump: %s" % ProjectSettings.globalize_path(DUMP_PATH))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
func _test_world_creation(world: Node, wl: Node) -> void:
	_section("WORLD CREATION")
	_ok(Plant.is_initialized(), "Plant initialised")
	var grade : float = Plant.floor_top_y() if Plant.is_initialized() else 999.0
	_ok(absf(grade - GRADE_Y) < GRADE_TOL,
		"operating-floor grade ~= %.2f (got %.2f)" % [GRADE_Y, grade])

	var shell := world.find_child("ShellMesh", true, false) as MeshInstance3D
	_ok(shell != null and shell.mesh != null, "building shell mesh present")
	if shell != null and shell.mesh != null:
		var ab : AABB = shell.mesh.get_aabb()
		_ok(ab.size.x > 50.0 and ab.size.z > 30.0,
			"shell footprint non-trivial (aabb %.0f x %.0f)" % [ab.size.x, ab.size.z])

	# Doors: each structure_item center must sit on a wall line.
	var items : Array = []
	if wl.has_method("get") and wl.get("structure_items") != null:
		items = wl.get("structure_items")
	var door_dump : Array = []
	var doors_on_wall := 0
	var doors_total := 0
	for it in items:
		if typeof(it) != TYPE_DICTIONARY:
			continue
		var pts : Array = it.get("p", [])
		if pts.size() < 4:
			continue
		doors_total += 1
		var c := Vector3.ZERO
		for pp in pts:
			c += Vector3(float(pp[0]), float(pp[1]), float(pp[2]))
		c /= float(pts.size())
		var bf := _scene_to_bf(c)
		var on_wall := _on_a_wall(bf)
		if on_wall:
			doors_on_wall += 1
		door_dump.append({
			"label": String(it.get("label", "")), "type": String(it.get("type", "door")),
			"center": [c.x, c.y, c.z], "bf": [bf.x, bf.y], "on_wall": on_wall})
	_dump["doors"] = door_dump
	if doors_total == 0:
		print("  note  : no structure_items (doors) in world_layout — skipped"); _skip += 1
	else:
		_ok(doors_on_wall == doors_total,
			"all %d door(s)/gate(s) sit on a wall (on-wall %d)" % [doors_total, doors_on_wall])


# =============================================================================
func _test_save_creation(world: Node) -> void:
	_section("SAVE CREATION — build line_3a (clean seed), verify inside + round-trip")

	# (a) static id resolution over the sequence — catches silently-dropped ids.
	var seq : Array = BuildMode.LINE_3A_SEQ
	var unresolved : Array = []
	var expected := 0
	for e in seq:
		var mid := String(e.get("id", ""))
		if mid == "":
			continue
		expected += 1
		if PlaceableCatalog.get_item(mid).is_empty():
			unresolved.append(mid)
	_ok(unresolved.is_empty(),
		"every LINE_3A_SEQ id resolves in catalog (%d unresolved: %s)"
			% [unresolved.size(), str(unresolved)])

	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if bm == null:
		print("  skip  : BuildMode not found — save-creation tier skipped"); _skip += 1
		_dump["machines"] = []
		return

	# Test the CLEAN const seed (the shipped layout), NOT operator jog-deltas:
	# clear the in-memory macro cache so accumulated_chain returns zeros. This is
	# in-memory only (disk macro untouched — it is separately validated by
	# _test_macros, which is what catches the corrupt line_3a deltas).
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache["line_3a"] = {}

	# (b) build the line at an anchor inside the halls, running down the long
	# (bf +X) axis so it fits. bf(4,22): near the NE gable, mid-depth, with room
	# for the +X advance and lateral branch lanes.
	var start_bf := Vector2(4.0, 22.0)
	var start : Vector3 = Plant.pc_to_scene(_bf_to_pc(start_bf))
	var fdir : Vector3 = Plant.pc_to_scene(_bf_to_pc(Vector2(5.0, 22.0))) \
		- Plant.pc_to_scene(_bf_to_pc(Vector2(4.0, 22.0)))
	fdir = fdir.normalized()
	var rot_y : float = atan2(-fdir.x, -fdir.z)   # so _build_full_line fwd == +bf X
	bm.call("_build_full_line", "line_3a", start, rot_y)
	for i in range(10):
		await get_tree().process_frame

	# Collect ONLY this line's machines (macro_id meta), so world doors/props
	# never pollute the machine set.
	var placed := _collect_line(bm, "line_3a")
	_ok(placed.size() == expected,
		"line built: %d machines placed (expected %d)" % [placed.size(), expected])

	# (c) inside-building check for every placed machine.
	var machine_dump : Array = []
	var inside := 0
	for n in placed:
		var pos : Vector3 = (n as Node3D).global_position
		var bf := _scene_to_bf(pos)
		var is_in := _bf_inside(bf, INSIDE_MARGIN)
		if is_in:
			inside += 1
		machine_dump.append({
			"id": _placed_id(n), "pos": [pos.x, pos.y, pos.z],
			"rot_y": (n as Node3D).rotation.y, "bf": [bf.x, bf.y],
			"inside": is_in, "resolved": true})
	_dump["machines"] = machine_dump
	_ok(inside == placed.size(),
		"ALL placed machines inside building footprint (%d/%d)" % [inside, placed.size()])

	# (d) round-trip: snapshot -> save -> clear -> reload -> compare.
	var before : Array = []
	for n in placed:
		before.append({"id": _placed_id(n), "p": (n as Node3D).global_position})
	var before_all := _collect_placed(bm)   # doors + machines, for a like-for-like count
	if not bm.has_method("_save_layout"):
		print("  skip  : BuildMode._save_layout missing — round-trip skipped"); _skip += 1
		return
	bm.call("_save_layout")
	_clear_placed(bm)
	for i in range(6):
		await get_tree().process_frame
	if not bm.has_method("load_layout"):
		print("  skip  : BuildMode.load_layout missing — round-trip skipped"); _skip += 1
		return
	bm.call("load_layout")
	for i in range(10):
		await get_tree().process_frame
	var after := _collect_placed(bm)
	_ok(after.size() == before_all.size(),
		"round-trip node count stable (%d -> %d)" % [before_all.size(), after.size()])
	# Match by nearest position; assert every 'before' has an 'after' within tol.
	var worst := 0.0
	var matched := 0
	for b in before:
		var bp : Vector3 = b["p"]
		var best := 1e9
		for n in after:
			var d : float = (n as Node3D).global_position.distance_to(bp)
			best = minf(best, d)
		worst = maxf(worst, best)
		if best <= ROUNDTRIP_TOL:
			matched += 1
	_ok(matched == before.size(),
		"round-trip positions reproduced within %.0f cm (worst %.3f m, %d/%d)"
			% [ROUNDTRIP_TOL * 100.0, worst, matched, before.size()])


# =============================================================================
func _collect_footprint_and_doors(wl: Node) -> void:
	# True footprint polygon in scene coords for the top-down render.
	var poly : Array = []
	if Plant.is_initialized():
		for bf in BF_OUTLINE:
			var s : Vector3 = Plant.pc_to_scene(_bf_to_pc(bf))
			poly.append([s.x, s.y, s.z])
	_dump["building_footprint"] = poly
	# line starts (scene) for context.
	var ls : Dictionary = {}
	var raw = wl.get("line_starts")
	if typeof(raw) == TYPE_DICTIONARY:
		for k in raw.keys():
			var v = raw[k]
			if v is Vector3:
				ls[k] = {"x": v.x, "z": v.z}
	_dump["line_starts"] = ls


# =============================================================================
# EXTERIOR & FIXTURES — the things the operator keeps seeing wrong:
# fence through the building, TL bars floating outside, spawns in the void.
# All MEASURED off the real spawned nodes, not asserted.
# =============================================================================
func _test_exterior(world: Node) -> void:
	_section("EXTERIOR & FIXTURES — fence, TL bars, spawns (measured)")

	# True building footprint polygon in scene XZ.
	var poly := PackedVector2Array()
	if Plant.is_initialized():
		for bf in BF_OUTLINE:
			var s : Vector3 = Plant.pc_to_scene(_bf_to_pc(bf))
			poly.append(Vector2(s.x, s.z))

	# ── FENCE: no perimeter-fence segment may cross the building interior ──────
	var fences : Array = world.find_children("PerimeterFence*", "", true, false)
	var fence_dump : Array = []
	var fence_cross := 0
	for f in fences:
		var wps = f.get("_waypoints")   # ChainLinkFence stores world-space corners here
		if not (wps is Array) or (wps as Array).size() < 2:
			continue
		var arr : Array = wps
		for i in range(arr.size() - 1):
			var a : Vector3 = arr[i]
			var b : Vector3 = arr[i + 1]
			var a2 := Vector2(a.x, a.z)
			var b2 := Vector2(b.x, b.z)
			var hits := _seg_hits_polygon(a2, b2, poly)
			if hits:
				fence_cross += 1
			fence_dump.append({"a": [a.x, a.z], "b": [b.x, b.z], "crosses": hits})
	_dump["fence"] = fence_dump
	if fences.is_empty():
		print("  note  : no PerimeterFence nodes found"); _skip += 1
	else:
		_ok(fence_cross == 0,
			"NO fence segment crosses the building (%d crossing / %d segments)"
				% [fence_cross, fence_dump.size()])

	# ── TL BARS: all inside + rod-mounted; legacy floating path gone ──────────
	_ok(world.find_child("InteriorTLBars", true, false) == null,
		"legacy floating TL-bar path (InteriorTLBars) is deleted")
	var oh := world.find_child("OverheadLights", true, false)
	var tl_dump : Array = []
	if oh == null:
		print("  note  : OverheadLights node not found"); _skip += 1
	else:
		var tl_out := 0
		var tl_float := 0
		var tl_n := 0
		for fx in (oh as Node).get_children():
			if not (fx is Node3D):
				continue
			tl_n += 1
			var pos : Vector3 = (fx as Node3D).global_position
			var bf := _scene_to_bf(pos)
			var inside := _bf_inside(bf, 1.0)
			var has_rod := false
			for ch in (fx as Node).get_children():
				if ch is MeshInstance3D:
					has_rod = true
					break
			if not inside:
				tl_out += 1
			if not has_rod:
				tl_float += 1
			tl_dump.append({"pos": [pos.x, pos.y, pos.z], "inside": inside})
		_ok(tl_out == 0, "all %d TL bars inside the building (%d OUTSIDE)" % [tl_n, tl_out])
		_ok(tl_float == 0, "all %d TL bars rod-mounted (%d floating)" % [tl_n, tl_float])
	_dump["tl_bars"] = tl_dump

	# ── SPAWNS: finite + within a sane radius of the plant centre ─────────────
	var center := Plant.factory_center_scene()
	var veh : Array = []
	for c in world.get_children():
		if c is VehicleBody3D:
			veh.append(c)
	if veh.is_empty():
		print("  note  : no vehicles spawned to check"); _skip += 1
	else:
		var vbad := 0
		var vworst := 0.0
		for v in veh:
			var gp : Vector3 = (v as Node3D).global_position
			var d := Vector2(gp.x - center.x, gp.z - center.z).length()
			vworst = maxf(vworst, d)
			if not _v3_finite(gp) or d > 500.0:
				vbad += 1
		_ok(vbad == 0, "all %d vehicles finite + within 500 m of plant (worst %.0f m)"
			% [veh.size(), vworst])

	var npcs := get_tree().get_nodes_in_group("npc")
	if npcs.is_empty():
		npcs = get_tree().get_nodes_in_group("colleague")
	if not npcs.is_empty():
		var nbad := 0
		for n in npcs:
			if n is Node3D:
				var gp : Vector3 = (n as Node3D).global_position
				var d := Vector2(gp.x - center.x, gp.z - center.z).length()
				if not _v3_finite(gp) or d > 500.0:
					nbad += 1
		_ok(nbad == 0, "all %d NPC spawns finite + within 500 m of plant (%d bad)"
			% [npcs.size(), nbad])


func _seg_hits_polygon(a: Vector2, b: Vector2, poly: PackedVector2Array) -> bool:
	if poly.size() < 3:
		return false
	if Geometry2D.is_point_in_polygon(a, poly) or Geometry2D.is_point_in_polygon(b, poly):
		return true
	for i in range(poly.size()):
		var c := poly[i]
		var d := poly[(i + 1) % poly.size()]
		if Geometry2D.segment_intersects_segment(a, b, c, d) != null:
			return true
	return false


func _v3_finite(v: Vector3) -> bool:
	return is_finite(v.x) and is_finite(v.y) and is_finite(v.z)


# ── placed-node helpers ───────────────────────────────────────────────────────
func _collect_placed(bm) -> Array:
	var root = bm.get("_placed_root")
	if root != null and is_instance_valid(root):
		var out : Array = []
		for c in (root as Node).get_children():
			if c is Node3D:
				out.append(c)
		if not out.is_empty():
			return out
	# Fallback: LineFlow-registered placed machines.
	return get_tree().get_nodes_in_group("placed_object")

func _clear_placed(bm) -> void:
	var root = bm.get("_placed_root")
	if root != null and is_instance_valid(root):
		for c in (root as Node).get_children():
			c.queue_free()
	else:
		for c in get_tree().get_nodes_in_group("placed_object"):
			c.queue_free()

func _placed_id(n) -> String:
	if (n as Node).has_meta("placeable_id"):
		return String((n as Node).get_meta("placeable_id"))
	return String((n as Node).name)

func _collect_line(bm, macro_id: String) -> Array:
	# Only this macro's machines (excludes doors/props). macro_id meta is stamped
	# by BuildMode._build_full_line at placement time.
	var pool : Array = []
	var root = bm.get("_placed_root")
	if root != null and is_instance_valid(root):
		pool = (root as Node).get_children()
	else:
		pool = get_tree().get_nodes_in_group("placed_object")
	var out : Array = []
	for c in pool:
		if c is Node3D and (c as Node).has_meta("macro_id") \
				and String((c as Node).get_meta("macro_id")) == macro_id:
			out.append(c)
	return out


# ── macro corruption guard ────────────────────────────────────────────────────
const MACRO_MAX_XZ := 25.0   # m — accumulated lateral/forward drift ceiling
const MACRO_MAX_Y  := 10.0   # m — accumulated vertical drift ceiling

func _test_macros() -> void:
	_section("MACRO SANITY — operator line macros must not encode insane deltas")
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms == null:
		print("  skip  : LineMacroStore autoload missing"); _skip += 1; return
	var any := false
	for mid in (lms.MACRO_IDS as Array):
		if not bool(lms.call("has_overrides", mid)):
			continue
		any = true
		var chain : Dictionary = lms.call("accumulated_chain", mid, 64)
		var mx := 0.0; var my := 0.0; var mz := 0.0
		for i in chain.keys():
			var d : Dictionary = chain[i]
			mx = maxf(mx, absf(float(d.get("dx", 0.0))))
			my = maxf(my, absf(float(d.get("dy", 0.0))))
			mz = maxf(mz, absf(float(d.get("dz", 0.0))))
		_ok(mx < MACRO_MAX_XZ and mz < MACRO_MAX_XZ and my < MACRO_MAX_Y,
			"macro '%s' deltas sane (max|dx|=%.1f |dy|=%.1f |dz|=%.1f)" % [mid, mx, my, mz])
	if not any:
		print("  note  : no operator macros present"); _skip += 1


# ── user:// file safety ───────────────────────────────────────────────────────
func _backup_files() -> void:
	for p in TOUCHED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f: f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in _backups.keys():
		var orig = _backups[p]
		if orig is String:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f: f.store_string(orig); f.close()
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("  (restored touched user:// files)")

func _write_dump() -> void:
	var f := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_dump, "  "))
		f.close()
