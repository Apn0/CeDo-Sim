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
##   - every door in WorldLayout.structure_items stands in a wall opening the
##     carve cut in the real shell (opening_id on its placed node).
##
##  SAVE CREATION (the "machines outside the building" class of bug)
##   - every id in LINE_3A_SEQ resolves in the catalog (no silent drops);
##   - a line built from the macro places the expected machine count;
##   - EVERY placed machine lands INSIDE the true building footprint —
##     tested twice: its scene position mapped back into the building frame
##     the game FITS from the shell (building_frame.gd) against the wall
##     rectangles, and a measured roof face of the shell straight above it;
##   - the building frame itself sits on the shell: every outline corner is
##     within 1 m of a real wall (2026-09-25: the typed frame, mapped through
##     Plant.pc_to_scene, was rotated twice and 8 of line 3A's 39 machines
##     stood outside the building while this suite said 39/39 inside);
##   - save -> clear -> reload reproduces every machine position to <1 cm
##     (round-trip fidelity — the loader is not silently shifting anything).
##
## Emits user://regression_positions.json for tools/regression/topdown_render.py.
## Backs up and restores every user:// file it touches, so the operator's saves
## are never harmed. His world_layout.json is READ (the world boots on it) but
## never written: every world save, the round-trip's own _save_layout included,
## goes to a scratch file (src/tests/world_layout_guard.gd).

# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")
# Interior as axis-aligned bf rectangles [xmin, xmax, zmin, zmax] — exact
# containment test after mapping a machine back into the building frame.
const BF_RECTS := [
	[0.0, 120.0, 0.0, 61.0],       # arched halls
	[120.0, 150.7, 0.0, 31.5],     # SW flat wing
	[120.0, 131.5, 31.5, 61.0],    # SE wing
	[57.0, 81.0, 61.0, 66.0],      # annex west (shallow)
	[81.0, 131.5, 61.0, 71.5],     # annex east
]
const INSIDE_MARGIN := 0.6          # m of slack for a machine centre near a wall
const GRADE_Y := -9.0
const GRADE_TOL := 0.25
const ROUNDTRIP_TOL := 0.01         # 1 cm

const TEST_SLOT := "__regression__"
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const TOUCHED := [
	"user://world_layout_consumed.flag",
	"user://__regression___save.json", "user://__regression___factory.json",
]
const DUMP_PATH := "user://regression_positions.json"

var _pass := 0
var _fail := 0
var _skip := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, TOUCHED)
var _dump : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _section(t: String) -> void:
	print("\n[%s]" % t)


# ── bf helpers: the shell-fitted frame (building_frame.gd) ──────────────────
var _fr : Dictionary = {}      # set after boot; {} when the world has no fit
var _tris : Dictionary = {}    # the shell's wall / roof triangles, scene space

func _scene_to_bf(pos: Vector3) -> Vector2:
	return BFrame.from_scene(_fr, pos) if not _fr.is_empty() else Vector2(INF, INF)

func _bf_inside(bf: Vector2, margin: float) -> bool:
	for r in BF_RECTS:
		if bf.x >= r[0] - margin and bf.x <= r[1] + margin \
				and bf.y >= r[2] - margin and bf.y <= r[3] + margin:
			return true
	return false

## The placed node BuildMode built for one structure_items entry: the surface
## node whose stored corner points match the entry's (same list, same order —
## _save_layout writes surface_data["p"] back verbatim).
func _surface_node_for(nodes: Array, pts: Array) -> Node:
	for n in nodes:
		var sp : Array = (n.get_meta("surface_data") as Dictionary).get("p", [])
		if sp.size() != pts.size():
			continue
		var same := true
		for i in range(sp.size()):
			if Vector3(float(sp[i][0]), float(sp[i][1]), float(sp[i][2])).distance_to(
					Vector3(float(pts[i][0]), float(pts[i][1]), float(pts[i][2]))) > 0.01:
				same = false
				break
		if same:
			return n
	return null


func _ready() -> void:
	print("=== REGRESSION — world creation + save creation ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via --main-scene, not --script)")
		get_tree().quit(2); return

	# Before boot. The save->reload round-trip below runs _save_layout, which
	# would otherwise write the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return

	# Load-existing (not new-save) so MainWorld builds the configured world
	# without entering the interactive setup flow (which would hang headless).
	# The per-save factory file was wiped, so machines start empty.
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _wlg.restore(); _wlg.disarm(); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	# Let _ready cascade + deferred spawns settle.
	for i in range(80):
		await get_tree().process_frame
	_fr = await BFrame.wait_fitted(world)
	_tris = BFrame.shell_triangles(world)

	_dump["meta"] = {
		"world_yaw_deg": rad_to_deg(Plant.world_yaw_rad()) if Plant.is_initialized() else null,
		"floor_grade_y": Plant.floor_top_y() if Plant.is_initialized() else null,
	}

	_test_world_creation(world, wl)
	_test_macros()   # BEFORE save-creation, which clears the in-memory macro cache
	await _test_save_creation(world)
	_collect_footprint_and_doors(wl)
	# _test_exterior awaits a physics frame (the TL rod-gap raycast needs the
	# shell colliders queryable) — MUST be awaited, or the verdict + quit below
	# run first and the exterior checks silently never count.
	await _test_exterior(world)
	_section("LEAK GUARD")
	for c in _wlg.final_checks(world):
		_ok(c[0], c[1])

	# Verdict list for the render.
	_dump["checks"] = [
		{"name": "world_creation+save_creation", "pass": _fail == 0},
	]
	_write_dump()

	# The verdict is printed and user:// restored BEFORE the world is freed,
	# then restored again after: the headless teardown segfault lands inside
	# world teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
	_wlg.restore()
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Dump: %s" % ProjectSettings.globalize_path(DUMP_PATH))
	print("=========================================")
	world.queue_free()
	await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
func _test_world_creation(world: Node, wl: Node) -> void:
	_section("WORLD CREATION")
	_ok(Plant.is_initialized(), "Plant initialised")
	var grade : float = Plant.floor_top_y() if Plant.is_initialized() else 999.0
	_ok(absf(grade - GRADE_Y) < GRADE_TOL,
		"operating-floor grade ~= %.2f (got %.2f)" % [GRADE_Y, grade])

	# LineFlow's per-tick bale caches MUST be Array[Node]-typed: _bale_at(pos,
	# bales: Array[Node]) hard-rejects a plain Array AT RUNTIME (the call
	# throws, returns null, and the feed loop silently starves every line).
	# Shipped exactly like that on 2026-08-08 (perf commit 9367239) and stayed
	# green here because the harness never fails on SCRIPT ERROR spam —
	# caught by the windowed HMI proof run 2026-08-09.
	var lflow := world.find_child("LineFlow", true, false)
	if lflow == null:
		lflow = get_tree().get_first_node_in_group("line_flow")
	_ok(lflow != null, "LineFlow node present in MainWorld")
	if lflow != null:
		var cache : Variant = lflow.get("_deliverable_bales_cache")
		_ok(typeof(cache) == TYPE_ARRAY and (cache as Array).get_typed_class_name() == &"Node",
			"_deliverable_bales_cache is Array[Node]-typed (matches _bale_at's parameter)")

	var shell := world.find_child("ShellMesh", true, false) as MeshInstance3D
	_ok(shell != null and shell.mesh != null, "building shell mesh present")
	if shell != null and shell.mesh != null:
		var ab : AABB = shell.mesh.get_aabb()
		_ok(ab.size.x > 50.0 and ab.size.z > 30.0,
			"shell footprint non-trivial (aabb %.0f x %.0f)" % [ab.size.x, ab.size.z])

	# The building frame every check below reads: FITTED from the shell at
	# runtime, then measured against it. Its outline corners must sit on the
	# shell's real walls — the typed frame this replaced missed six of ten by
	# 3.6-39.8 m, and nothing here noticed.
	_ok(not _fr.is_empty(), "building frame FITTED from the shell (InteriorLightingManager; mean roof err %.2f m)"
		% float(_fr.get("err", NAN)))
	if not _fr.is_empty():
		var offs : Array = BFrame.outline_off_wall_m(_fr, _tris, Plant.floor_top_y())
		var worst := 0.0
		for d in offs:
			worst = maxf(worst, float(d))
		_ok(worst <= 1.0, "the bf outline sits on the shell's walls: all %d corners within 1.0 m (worst %.2f m)"
			% [offs.size(), worst])

	# Doors: each structure_item must stand in a wall opening that WallOpenings
	# cut in the REAL shell. BuildMode stamps opening_id on the placed node only
	# when the carve found shell wall triangles inside the opening box.
	# Until 2026-09-25 this tested the centre against six typed wall lines of
	# the building frame (BF_*). That frame does not line up with the 3D shell:
	# drawn through Plant it comes out axis-aligned in scene space, while the
	# shell stands rotated (measured with a top-down render). So the operator's
	# own 3A/3B gate, carved through the south-west wall, read "on-wall 0"
	# (operator 2026-09-25: the gate is right, keep it).
	var bm_d = world.get("build_mode")
	var surf_nodes : Array = []
	if bm_d != null and bm_d.get("_placed_root") != null:
		for ch in (bm_d.get("_placed_root") as Node).get_children():
			if ch.has_meta("surface_data"):
				surf_nodes.append(ch)
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
		var node : Node = _surface_node_for(surf_nodes, pts)
		var on_wall : bool = node != null and node.has_meta("opening_id")
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
			"all %d door(s)/gate(s) stand in a wall opening carved in the real shell (carved %d)" % [doors_total, doors_on_wall])


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
	if _fr.is_empty():
		_ok(false, "line_3a placed in the fitted building frame (no frame: cannot anchor the line)")
		return
	var start : Vector3 = BFrame.to_scene(_fr, start_bf, Plant.floor_top_y())
	var rot_y : float = BFrame.forward_rot_y(_fr)   # so _build_full_line fwd == +bf X
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
	var roofed := 0
	for n in placed:
		var pos : Vector3 = (n as Node3D).global_position
		var bf := _scene_to_bf(pos)
		var is_in := _bf_inside(bf, INSIDE_MARGIN)
		if is_in:
			inside += 1
		# MEASURED, frame-free: a roof face of the shell straight above it.
		var under := BFrame.under_roof(_tris, Vector3(pos.x, Plant.floor_top_y(), pos.z))
		if under:
			roofed += 1
		machine_dump.append({
			"id": _placed_id(n), "pos": [pos.x, pos.y, pos.z],
			"rot_y": (n as Node3D).rotation.y, "bf": [bf.x, bf.y],
			"inside": is_in, "under_roof": under, "resolved": true})
	_dump["machines"] = machine_dump
	_ok(inside == placed.size(),
		"ALL placed machines inside building footprint (%d/%d)" % [inside, placed.size()])
	_ok(roofed == placed.size() and placed.size() > 0,
		"ALL placed machines stand under the shell's roof, measured (%d/%d)" % [roofed, placed.size()])

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
	if Plant.is_initialized() and not _fr.is_empty():
		for bf in BFrame.OUTLINE:
			var s : Vector3 = BFrame.to_scene(_fr, bf, Plant.floor_top_y())
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
# TL bars floating outside, spawns in the void.
# All MEASURED off the real spawned nodes, not asserted.
# =============================================================================
func _test_exterior(world: Node) -> void:
	_section("EXTERIOR & FIXTURES — TL bars, spawns (measured)")

	# True building footprint polygon in scene XZ.
	var poly := PackedVector2Array()
	if Plant.is_initialized() and not _fr.is_empty():
		for bf in BFrame.OUTLINE:
			var s : Vector3 = BFrame.to_scene(_fr, bf, Plant.floor_top_y())
			poly.append(Vector2(s.x, s.z))

	# (FENCE check removed 2026-08-03 — the perimeter fence itself was deleted
	# per operator order; there is nothing to cross-check any more.)

	# ── TL BARS: all inside + rod-mounted; legacy floating path gone ──────────
	_ok(world.find_child("InteriorTLBars", true, false) == null,
		"legacy floating TL-bar path (InteriorTLBars) is deleted")
	var oh := world.find_child("OverheadLights", true, false)
	var tl_dump : Array = []
	if oh == null:
		print("  note  : OverheadLights node not found"); _skip += 1
	else:
		# One physics frame so the shell's static colliders are queryable.
		await world.get_tree().physics_frame
		var space := (world as Node3D).get_world_3d().direct_space_state
		var tl_out := 0
		var tl_float := 0
		var tl_gap_fail := 0
		var tl_worst_gap := 0.0
		var tl_n := 0
		for fx in (oh as Node).get_children():
			if not (fx is Node3D):
				continue
			tl_n += 1
			var pos : Vector3 = (fx as Node3D).global_position
			# PHYSICAL inside-test: a bar is inside iff the measured shell has a
			# roof face above it. The old test mapped through the baked BF_O
			# affine — the same stale constants that put the bars in the wrong
			# place to begin with (fitted frame vs baked origin differ by
			# metres; see InteriorLightingManager._fit_building_frame).
			var inside := false
			if space != null:
				var qi := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.UP * 45.0)
				inside = not space.intersect_ray(qi).is_empty()
			# VACUOUS-CHECK FIX (operator 2026-07-20, "mounted to the air"): the
			# old has_rod test accepted ANY MeshInstance3D child — and the TL BAR
			# ITSELF is one, so "0 floating" was true even with no rod at all.
			# Now: the rod must exist by name, AND its top must MEASURABLY reach
			# the roof — raycast straight up and compare against the rod top.
			var rod := (fx as Node).get_node_or_null("MountRod") as MeshInstance3D
			if rod == null:
				tl_float += 1
			elif space != null:
				var rod_len : float = (rod.mesh as BoxMesh).size.y if rod.mesh is BoxMesh else 0.0
				var rod_top_y : float = (fx as Node3D).global_position.y + 0.12 + rod_len
				var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.3, pos + Vector3.UP * 45.0)
				var hit := space.intersect_ray(q)
				if hit.is_empty():
					tl_gap_fail += 1     # nothing above the bar to mount to at all
				else:
					var gap : float = absf(float((hit["position"] as Vector3).y) - rod_top_y)
					tl_worst_gap = maxf(tl_worst_gap, gap)
					if gap > 0.15:
						tl_gap_fail += 1
			if not inside:
				tl_out += 1
			tl_dump.append({"pos": [pos.x, pos.y, pos.z], "inside": inside})
		_ok(tl_out == 0, "all %d TL bars under a MEASURED roof face (%d not)" % [tl_n, tl_out])
		_ok(tl_float == 0, "all %d TL bars have a MountRod (%d without)" % [tl_n, tl_float])
		_ok(tl_gap_fail == 0, "all %d TL rods REACH the measured roof (%d in mid-air, worst gap %.2f m)"
			% [tl_n, tl_gap_fail, tl_worst_gap])
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
		# The radius check above CANNOT see a frame error smaller than its own
		# bound: it was green for the whole life of the 228 m marker-frame bug.
		# Assert marker IDENTITY too — every operator-placed vehicle marker must
		# have a hull standing on it. Full independent-derivation version (raw
		# JSON + tile-mesh shift + PC round-trip + mutation test) lives in
		# src/tests/test_vehicle_spawn_frame.gd; this is the in-harness tripwire.
		var markers : Array[Vector2] = []
		for vid in WorldLayout.vehicle_spawns.keys():
			for p in (WorldLayout.vehicle_spawns[vid] as Array):
				if p is Vector3:
					markers.append(Vector2((p as Vector3).x, (p as Vector3).z))
		if markers.is_empty():
			print("  note  : layout holds no vehicle markers to match"); _skip += 1
		else:
			var unmatched := 0
			var mworst := 0.0
			for m in markers:
				var best := INF
				for v in veh:
					var gp2 : Vector3 = (v as Node3D).global_position
					best = minf(best, Vector2(gp2.x, gp2.z).distance_to(m))
				mworst = maxf(mworst, best)
				# 3 m: the spawner copies the marker XZ verbatim, so the expected
				# reading is ~0; the budget only covers Rapier pushing apart the
				# hulls of markers placed within a vehicle-width of each other.
				if best > 3.0:
					unmatched += 1
			_ok(unmatched == 0,
				"every one of %d vehicle markers has a hull on it (worst gap %.2f m)"
					% [markers.size(), mworst])

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


func _write_dump() -> void:
	var f := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_dump, "  "))
		f.close()
