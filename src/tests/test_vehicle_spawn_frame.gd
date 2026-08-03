extends Node
# =============================================================================
# REGRESSION — a vehicle must spawn ON the marker the operator placed.
# =============================================================================
#   GODOT --headless --path . res://src/tests/test_vehicle_spawn_frame.tscn
#   prints "Result: PASS" / "Result: FAIL" for the harness to key off.
#
# WHAT IT GUARDS (measured 2026-07-21 against the operator's real layout):
#   WorldSetup writes markers SCENE-ABSOLUTE, but WorldFrame._layout_to_scene
#   read them as player_spawn-relative offsets and applied R(world_yaw) + anchor.
#   Every vehicle therefore spawned ~228 m from its own marker — forklift #1 was
#   drawn at (-211.21, 86.05) and materialised at (-0.6, 199.8), out in the field
#   north-east of the plant, on the far side of the perimeter fence.
#
# WHY THE EXISTING CHECKS COULD NOT SEE IT:
#   regression_world_save.gd:455 asserts "all vehicles finite + within 500 m of
#   plant". 228 m passes. That check was green for the entire life of the bug.
#   A radius bound cannot detect a frame error smaller than the radius, so this
#   file asserts marker IDENTITY instead: spawned XZ == stored XZ.
#
# INDEPENDENT DERIVATION (or the check is vacuous):
#   The expected position is parsed from the RAW world_layout.json on disk and,
#   if a marker is RD-scale, shifted by the building TILE mesh's own AABB centre
#   read here from the .obj. Nothing is asked of WorldFrame, VehicleSpawner or
#   Plant — reverting _layout_to_scene to the rotate+anchor form must turn CHECK
#   B red, which is the mutation test this file exists to survive.
#
# world_layout.json is byte-backed-up and restored (MainWorld autosaves).
# =============================================================================

const LAYOUT_PATH := "user://world_layout.json"
const TILE_OBJ    := "res://assets/models/CeDo_building.obj"
const TEST_SLOT   := "__spawnframe__"

# Files MainWorld may write during a boot. All byte-restored in _finish.
const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__spawnframe___save.json",
	"user://__spawnframe___factory.json",
]

# Tolerance between the stored marker and the spawned hull, in XZ metres.
# Justification: VehicleSpawner sets global_position from the marker and only
# overrides Y, so the expected reading is ~0. The budget covers Rapier contact
# recovery during the boot frames — the operator's mast_lift markers are 1.4 m
# apart and their hulls overlap, so the physics engine legitimately pushes them
# apart by ~1 m. 3 m is a detection floor, not a tolerance: it is 76x below the
# 228 m the rotate+anchor reading produced.
const TOL_M : float = 3.0
# Frames to let MainWorld's _ready cascade finish. Kept small on purpose —
# every extra frame is more physics settling between spawn and measurement.
const BOOT_FRAMES : int = 90

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


func _info(label: String) -> void:
	print("  info  : %s" % label)


func _ready() -> void:
	print("=== vehicle spawn frame — spawned position must equal the operator's marker ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2)
		return
	_backup_files()

	# ── EXPECTATION, derived from disk without consulting any game transform ──
	var expected : Dictionary = _expected_from_disk()
	if expected.is_empty():
		_check(false, "world_layout.json holds at least one vehicle marker to verify")
		await _finish()
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

	_check_a_loader_preserved_markers(expected)
	var spawned : Dictionary = _spawned_by_type()
	_check_b_marker_identity(expected, spawned)
	_check_c_header_agrees(expected, spawned)
	_check_d_pc_path(expected)
	await _finish()


# =============================================================================
# EXPECTATION — raw JSON, converted by this file's own arithmetic.
# =============================================================================

## AABB centre of the building tile mesh. This is the RD origin MainWorld.tscn's
## BuildingShell transform is built from, read here from the asset so the test
## cannot inherit a constant from the code under test.
func _tile_shift() -> Vector2:
	var mesh = ResourceLoader.load(TILE_OBJ)
	if mesh is Mesh:
		var c : Vector3 = (mesh as Mesh).get_aabb().get_center()
		return Vector2(c.x, c.z)
	return Vector2.ZERO


## vehicle id → Array[Vector2] of expected SCENE XZ positions, straight from the
## file. RD-scale entries (|xz| > 10 km) are brought into the scene frame by
## subtracting the tile centre — the same rule MainWorld.tscn applies to the
## mesh, derived here independently.
func _expected_from_disk() -> Dictionary:
	if not FileAccess.file_exists(LAYOUT_PATH):
		_info("no %s on disk" % LAYOUT_PATH)
		return {}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var shift := _tile_shift()
	_info("tile-derived RD→scene shift = %s (read from %s)" % [str(shift), TILE_OBJ])
	var raw = (parsed as Dictionary).get("vehicle_spawns", {})
	if typeof(raw) != TYPE_DICTIONARY:
		return {}
	var out : Dictionary = {}
	for vid in (raw as Dictionary).keys():
		var arr = (raw as Dictionary)[vid]
		if not (arr is Array):
			continue
		var pts : Array[Vector2] = []
		for e in (arr as Array):
			if typeof(e) != TYPE_DICTIONARY:
				continue
			pts.append(_to_scene_xz(Vector2(e.get("x", 0.0), e.get("z", 0.0)), shift))
		# Legacy id alias, mirrored from the file format (not imported from code).
		var key : String = "mast_lift" if String(vid) == "scissor" else String(vid)
		out[key] = pts
	var ps = (parsed as Dictionary).get("player_spawn", {})
	out["__player_spawn__"] = [_to_scene_xz(
		Vector2(ps.get("x", 0.0) if typeof(ps) == TYPE_DICTIONARY else 0.0,
				ps.get("z", 0.0) if typeof(ps) == TYPE_DICTIONARY else 0.0), shift)]
	return out


func _to_scene_xz(p: Vector2, shift: Vector2) -> Vector2:
	if absf(p.x) > 10000.0 or absf(p.y) > 10000.0:
		return p - shift
	return p


# =============================================================================
# CHECK A — the loader handed the spawner what the operator drew.
# =============================================================================
func _check_a_loader_preserved_markers(expected: Dictionary) -> void:
	print("\n--- A. WorldLayout kept the authored marker values ---")
	var worst : float = 0.0
	var checked : int = 0
	for vid in expected.keys():
		if String(vid).begins_with("__"):
			continue
		var loaded : Array = WorldLayout.get_vehicle_spawns(String(vid))
		var want : Array = expected[vid]
		if loaded.size() != want.size():
			_check(false, "'%s': loader kept %d marker(s), file holds %d" % [vid, loaded.size(), want.size()])
			continue
		for i in want.size():
			var got : Vector3 = loaded[i]
			worst = maxf(worst, Vector2(got.x, got.z).distance_to(want[i]))
			checked += 1
	_check(checked > 0, "loader exposed %d vehicle marker(s) to compare" % checked)
	_check(worst < 0.01,
		"every loaded marker matches the file verbatim (worst %.4f m)" % worst)


# =============================================================================
# CHECK B — THE ONE THAT MATTERS. Spawned hull XZ == stored marker XZ.
# =============================================================================
func _spawned_by_type() -> Dictionary:
	var out : Dictionary = {}
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not (n is Node3D):
			continue
		var t : String = String((n as Node).get("vehicle_type"))
		if t == "":
			continue
		var arr : Array = out.get(t, [])
		arr.append(n as Node3D)
		out[t] = arr
	return out


func _check_b_marker_identity(expected: Dictionary, spawned: Dictionary) -> void:
	print("\n--- B. every vehicle spawned ON its own marker ---")
	var worst : float = 0.0
	var worst_desc : String = "n/a"
	var matched : int = 0
	for vid in expected.keys():
		if String(vid).begins_with("__"):
			continue
		var want : Array = expected[vid]
		if want.is_empty():
			continue
		var have : Array = spawned.get(String(vid), [])
		_check(have.size() == want.size(),
			"'%s': %d marker(s) in the file → %d vehicle(s) in the world" % [vid, want.size(), have.size()])
		if have.is_empty():
			continue
		# Greedy nearest match. Safe as an identity test: a whole-class frame
		# error moves every candidate together, so no assignment can hide it.
		var pool : Array = have.duplicate()
		for i in want.size():
			var target : Vector2 = want[i]
			var best : Node3D = null
			var best_d : float = INF
			for c in pool:
				var gp : Vector3 = (c as Node3D).global_position
				var d : float = Vector2(gp.x, gp.z).distance_to(target)
				if d < best_d:
					best_d = d
					best = c as Node3D
			if best == null:
				continue
			pool.erase(best)
			matched += 1
			var bp : Vector3 = best.global_position
			_info("%s #%d  marker %s → spawned (%.2f, %.2f)   off by %.2f m" %
				[vid, i + 1, str(target), bp.x, bp.z, best_d])
			if best_d > worst:
				worst = best_d
				worst_desc = "%s #%d" % [vid, i + 1]
	_check(matched > 0, "matched %d spawned vehicle(s) against their markers" % matched)
	_check(worst <= TOL_M,
		"worst marker→spawn displacement %.2f m (%s) is within %.1f m" % [worst, worst_desc, TOL_M])


# =============================================================================
# CHECK C — the boot header and the world tell the same story.
# =============================================================================
## WorldLayout's boot header prints, per vehicle, the XZ distance from
## player_spawn. That report was CORRECT while the spawner was wrong, and the
## two disagreeing by 200+ m is what the operator was never shown. Assert they
## agree: the distance the header reports must be the distance the spawned hull
## actually sits at.
func _check_c_header_agrees(expected: Dictionary, spawned: Dictionary) -> void:
	print("\n--- C. boot-header distance == real spawned distance ---")
	var ps_arr : Array = expected.get("__player_spawn__", [])
	if ps_arr.is_empty():
		_check(false, "player_spawn present in the layout file")
		return
	var ps : Vector2 = ps_arr[0]
	var worst : float = 0.0
	var worst_desc : String = "n/a"
	for vid in expected.keys():
		if String(vid).begins_with("__"):
			continue
		var have : Array = spawned.get(String(vid), [])
		var want : Array = expected[vid]
		if have.size() != want.size():
			continue
		var pool : Array = have.duplicate()
		for i in want.size():
			var reported : float = want[i].distance_to(ps)   # what the header prints
			var best : Node3D = null
			var best_d : float = INF
			for c in pool:
				var gp : Vector3 = (c as Node3D).global_position
				var d : float = Vector2(gp.x, gp.z).distance_to(want[i])
				if d < best_d:
					best_d = d
					best = c as Node3D
			if best == null:
				continue
			pool.erase(best)
			var gp2 : Vector3 = best.global_position
			var actual : float = Vector2(gp2.x, gp2.z).distance_to(ps)
			var gap : float = absf(actual - reported)
			_info("%s #%d  header says %.1f m from player_spawn, world says %.1f m (gap %.2f m)" %
				[vid, i + 1, reported, actual, gap])
			if gap > worst:
				worst = gap
				worst_desc = "%s #%d" % [vid, i + 1]
	_check(worst <= TOL_M,
		"worst header-vs-world disagreement %.2f m (%s) is within %.1f m" % [worst, worst_desc, TOL_M])


# =============================================================================
# CHECK D — the PC path agrees with the legacy path.
# =============================================================================
## migrate_to_pc feeds every marker through the same converter, so a frame error
## is carried faithfully into vehicle_spawns_pc and the two spawn branches agree
## with each other while both being wrong. Pin the PC grid to its own contract
## instead: Plant.gd documents PC(500,500) == the scene_origin handed to init(),
## and MainWorld hands it factory_center. So factory_center must round-trip to
## PC_CENTER, and every PC marker must invert back onto the file's value.
func _check_d_pc_path(expected: Dictionary) -> void:
	print("\n--- D. PC grid honours its own contract ---")
	if not (has_node("/root/Plant") and Plant.is_initialized()):
		_info("Plant not initialized — PC path not exercised this boot")
		return
	if not WorldLayout.has_pc_data:
		_info("no PC data migrated this boot")
		return
	var fc_pc : Vector2 = WorldLayout.factory_center_pc
	_check(fc_pc.distance_to(Plant.PC_CENTER) < 1.0,
		"factory_center_pc %s == PC_CENTER %s (Plant.gd:20-22 contract)" % [str(fc_pc), str(Plant.PC_CENTER)])
	var worst : float = 0.0
	for vid in expected.keys():
		if String(vid).begins_with("__"):
			continue
		if not WorldLayout.vehicle_spawns_pc.has(String(vid)):
			continue
		var pcs : Array = WorldLayout.vehicle_spawns_pc[String(vid)]
		var want : Array = expected[vid]
		if pcs.size() != want.size():
			_check(false, "'%s': %d PC entries vs %d file markers" % [vid, pcs.size(), want.size()])
			continue
		for i in want.size():
			var back : Vector3 = Plant.pc_to_scene(pcs[i])
			worst = maxf(worst, Vector2(back.x, back.z).distance_to(want[i]))
	_check(worst < 0.5,
		"every PC marker inverts back onto the file's scene value (worst %.3f m)" % worst)


# =============================================================================
# Teardown
# =============================================================================
func _finish() -> void:
	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = null
		_world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(0 if _fails == 0 else 1)


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
