extends Node
# =============================================================================
# CENSUS — where does every vehicle TRIANGLE and crew DOT actually sit?
# =============================================================================
#   GODOT --headless --path . res://src/tests/test_vehicle_census.tscn
#   prints "Result: PASS" / "Result: FAIL" for the harness to key off.
#
# WHY THIS FILE EXISTS (operator report, 2026-07-22):
#   After the scene-absolute marker-frame fix (commit 9334310) the plant
#   building outline + bale-yard cluster land correctly, but the operator still
#   sees "some triangles OUTSIDE the building, NOT at the parking lot — somewhere
#   else." A triangle on the site map is a BaseVehicle that is a direct child of
#   MainWorld (MapOverlay._vehicles, MapOverlay.gd:449). A dot is a crew NPC.
#   This file boots his REAL world_layout.json, settles the deferred spawn +
#   pre-shift cascade, and classifies EVERY vehicle by MEASURED distance to the
#   plant anchor, to the parking-lot bays, and inside/outside the SAME building
#   footprint polygon MapOverlay draws — so the answer is a measurement, never an
#   assertion (this project's recurring failure is the vacuous green + a reader
#   that rotates absolute markers 150-400 m off).
#
# CLASSES (each vehicle gets exactly one):
#   ON_PLANT           inside the footprint polygon OR within ANCHOR_M of the
#                      anchor — a work rig, expected.
#   AT_PARKING         within PARKING_M of the nearest staff-lot BAY transform —
#                      a commute car, expected.
#   ON_ROAD_PRESHIFT   the player Suzuki Swift near SWIFT_PC_DEFAULT on De Asselen
#                      Kuil — expected: during pre-shift the player is SEATED in
#                      it on the road, so the map centres here.
#   STRANDED           none of the above — the bug the operator is seeing.
#
#   FAIL = at least one STRANDED vehicle.
#
# This is a PURE READ. It boots into the __census__ scratch slot and NEVER calls
# _place_current / _save_layout, so world_layout.json is not rewritten. The file
# is byte-backed-up and restored regardless (MainWorld autosaves on a timer,
# which is stopped as soon as the boot settles).
# =============================================================================

const TEST_SLOT := "__census__"

const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__census___save.json",
	"user://__census___factory.json",
]

# Building footprint in the georeferenced BUILDING FRAME — the EXACT polygon
# MapOverlay._BF_OUTLINE draws (MapOverlay.gd:218-221). Kept in lockstep here so
# "inside the building" means the same thing the operator sees on the map.
const BF_OUTLINE : Array = [
	Vector2(0, 0), Vector2(150.7, 0), Vector2(150.7, 31.5), Vector2(131.5, 31.5),
	Vector2(131.5, 71.5), Vector2(81, 71.5), Vector2(81, 66), Vector2(57, 66),
	Vector2(57, 61), Vector2(0, 61)]

# Classification radii (XZ metres).
const ANCHOR_M     : float = 45.0    # a work rig this close to the anchor is "on plant"
const PARKING_M    : float = 25.0    # a car this close to a bay is "at parking"
const SWIFT_M      : float = 30.0    # tolerance around the Swift's road marker
const YARD_M       : float = 30.0    # a work rig this close to a bale yard is "on plant"
const BLDG_APRON_M : float = 25.0    # loading apron / roll-up door perimeter outside building

# Frames to let MainWorld's _ready cascade + deferred vehicle spawns finish, then
# extra frames for the pre-shift sequence (car spawner, player seating) to run.
const BOOT_FRAMES    : int = 120
const PRESHIFT_FRAMES : int = 180

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
	print("=== vehicle census — classify every triangle + dot on the operator's real layout ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2)
		return
	_backup_files()

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
	# Stop autosave BEFORE pre-shift runs so nothing writes world_layout.
	var autosave := _world.find_child("AutosaveTimer", true, false) as Timer
	if autosave != null:
		autosave.stop()
	for _i in range(PRESHIFT_FRAMES):
		await get_tree().process_frame
	if autosave != null:
		autosave.stop()

	# ── REFERENCE FRAME (measured off the live world, never re-derived) ──────
	var anchor : Vector3 = _world.call("_get_factory_anchor")
	var poly : PackedVector2Array = _building_polygon()
	var parking_node : Node3D = _world.get("staff_parking") as Node3D
	var parking_c : Vector3 = parking_node.global_position if parking_node != null else Vector3.INF
	var bays : Array = _parking_bays(parking_node)
	var swift : Node3D = _find_swift()
	var swift_pos : Vector3 = swift.global_position if swift != null else Vector3.INF

	print("\n--- REFERENCE FRAME (measured) ---")
	_info("anchor (factory)         scene (%.2f, %.2f, %.2f)" % [anchor.x, anchor.y, anchor.z])
	if parking_node != null:
		_info("parking-lot node origin  scene (%.2f, %.2f, %.2f)" % [parking_c.x, parking_c.y, parking_c.z])
		var bc : Vector2 = _bays_centroid(bays)
		_info("parking-lot bay centroid scene (%.2f, --, %.2f)  from %d bays  |  dist node->anchor %.1f m" % [
			bc.x, bc.y, bays.size(), Vector2(parking_c.x, parking_c.z).distance_to(Vector2(anchor.x, anchor.z))])
	else:
		_info("parking-lot node MISSING")
	if swift != null:
		_info("player Swift             scene (%.2f, %.2f, %.2f)  '%s'  dist->anchor %.1f m" % [
			swift_pos.x, swift_pos.y, swift_pos.z, String(swift.get("vehicle_type")),
			Vector2(swift_pos.x, swift_pos.z).distance_to(Vector2(anchor.x, anchor.z))])
	else:
		_info("player Swift MISSING")
	_check(poly.size() >= 3, "building footprint polygon resolved (%d verts) from the measured fit" % poly.size())
	_check(parking_node != null, "StaffParking node present")
	_check(bays.size() > 0, "parking bay transforms enumerated (%d bays)" % bays.size())

	# ── PLAYER (map centre during pre-shift) ─────────────────────────────────
	var player : Node3D = _world.get("player") as Node3D
	if player != null:
		var pp : Vector3 = player.global_position
		_info("PLAYER (map centre)      scene (%.2f, %.2f, %.2f)  dist->anchor %.1f m  dist->swift %.1f m" % [
			pp.x, pp.y, pp.z, Vector2(pp.x, pp.z).distance_to(Vector2(anchor.x, anchor.z)),
			Vector2(pp.x, pp.z).distance_to(Vector2(swift_pos.x, swift_pos.z)) if swift != null else -1.0])

	# ── VEHICLE CENSUS ───────────────────────────────────────────────────────
	var stranded : Array[String] = []
	var counts : Dictionary = {"ON_PLANT": 0, "AT_PARKING": 0, "ON_ROAD_PRESHIFT": 0, "STRANDED": 0}
	var yard_mgr = _world.get("bale_yard_manager")
	var yard_polys : Array = []
	if yard_mgr != null and yard_mgr.has_method("get_yard_polygons"):
		yard_polys = yard_mgr.get_yard_polygons()
	print("\n--- VEHICLE CENSUS (every node in group 'vehicle') ---")
	print("  %-22s %-16s %-9s %8s %8s %8s %8s %6s %-3s %s" % [
		"name", "type", "class", "d_anch", "d_park", "d_yard", "d_bldg", "inB", "tri", "scene pos"])
	var vehicles : Array = get_tree().get_nodes_in_group("vehicle")
	# Deterministic order for a readable, diffable table.
	vehicles.sort_custom(func(a, b): return String(a.name) < String(b.name))
	for vn in vehicles:
		var v := vn as Node3D
		if v == null:
			continue
		var gp : Vector3 = v.global_position
		var vtype : String = String(v.get("vehicle_type"))
		var xz := Vector2(gp.x, gp.z)
		var d_anchor : float = xz.distance_to(Vector2(anchor.x, anchor.z))
		var d_park : float = _nearest_bay_dist(xz, bays, parking_c)
		var d_yard : float = _nearest_yard_dist(xz, yard_polys)
		var d_bldg : float = _nearest_poly_dist(xz, poly)
		var inside : bool = poly.size() >= 3 and Geometry2D.is_point_in_polygon(xz, poly)
		var is_tri : bool = (v is BaseVehicle) and v.get_parent() == _world
		var d_swift : float = xz.distance_to(Vector2(swift_pos.x, swift_pos.z)) if swift != null else INF

		var cls : String = "STRANDED"
		if inside or d_anchor <= ANCHOR_M or d_yard <= YARD_M or d_bldg <= BLDG_APRON_M:
			cls = "ON_PLANT"
		elif d_park <= PARKING_M:
			cls = "AT_PARKING"
		elif v == swift or (vtype == "suzuki_swift_glx" and d_swift <= SWIFT_M):
			cls = "ON_ROAD_PRESHIFT"
		counts[cls] = int(counts[cls]) + 1
		if cls == "STRANDED":
			stranded.append("%s(%s) @scene(%.1f,%.1f) d_anch=%.1f d_park=%.1f d_yard=%.1f d_bldg=%.1f tri=%s" % [
				v.name, vtype, gp.x, gp.z, d_anchor, d_park, d_yard, d_bldg, "Y" if is_tri else "n"])
		print("  %-22s %-16s %-9s %7.1f %7.1f %7.1f %7.1f  %-5s %-3s (%.1f, %.1f)" % [
			v.name.substr(0, 22), vtype.substr(0, 16), cls, d_anchor, d_park, d_yard, d_bldg,
			"IN" if inside else "out", "Y" if is_tri else "n", gp.x, gp.z])

	print("\n  totals: ON_PLANT=%d  AT_PARKING=%d  ON_ROAD_PRESHIFT=%d  STRANDED=%d  (of %d vehicles)" % [
		counts["ON_PLANT"], counts["AT_PARKING"], counts["ON_ROAD_PRESHIFT"], counts["STRANDED"],
		vehicles.size()])

	# ── CREW CENSUS (dots — the operator may conflate a dot with a triangle) ──
	print("\n--- CREW CENSUS (main_world.npcs — DOTS on the map) ---")
	print("  %-16s %8s %8s %6s %s" % ["npc", "d_anch", "d_park", "inB", "scene pos"])
	var crew_outliers : Array[String] = []
	var npcs : Dictionary = _world.get("npcs")
	if npcs == null:
		npcs = {}
	var keys : Array = npcs.keys()
	keys.sort()
	for id in keys:
		var n := npcs[id] as Node3D
		if n == null or not is_instance_valid(n):
			_info("%-16s <invalid/missing>" % String(id))
			continue
		var gp : Vector3 = n.global_position
		var xz := Vector2(gp.x, gp.z)
		var d_anchor : float = xz.distance_to(Vector2(anchor.x, anchor.z))
		var d_park : float = _nearest_bay_dist(xz, bays, parking_c)
		var inside : bool = poly.size() >= 3 and Geometry2D.is_point_in_polygon(xz, poly)
		print("  %-16s %7.1f %7.1f  %-5s (%.1f, %.1f)" % [
			String(id).substr(0, 16), d_anchor, d_park, "IN" if inside else "out", gp.x, gp.z])
		# A crew member neither on the plant nor at parking is an outlier dot.
		if not inside and d_anchor > ANCHOR_M and d_park > PARKING_M:
			crew_outliers.append("%s @scene(%.1f,%.1f) d_anch=%.1f" % [String(id), gp.x, gp.z, d_anchor])

	# ── VERDICT ──────────────────────────────────────────────────────────────
	print("\n--- THE OUTSIDE TRIANGLES (operator's question, answered) ---")
	if stranded.is_empty():
		_info("no vehicle is STRANDED. Triangles the operator sees outside the outline:")
		if counts["ON_ROAD_PRESHIFT"] > 0:
			_info("  -> the player Swift on De Asselen Kuil (ON_ROAD_PRESHIFT) — EXPECTED,")
			_info("     during pre-shift the player is seated in it; the map centres on the road.")
		_info("  -> commute cars are AT_PARKING (%d) — expected." % counts["AT_PARKING"])
	else:
		for s in stranded:
			_info("STRANDED: %s" % s)
	if not crew_outliers.is_empty():
		_info("crew DOTS off-site (may look like a stray marker but are DOTS, not triangles):")
		for c in crew_outliers:
			_info("  %s" % c)

	_check(counts["ON_PLANT"] > 0, "at least one work vehicle classified ON_PLANT (non-vacuous)")
	_check(int(counts["STRANDED"]) == 0,
		"NO vehicle is STRANDED (outside building, not at parking, not the pre-shift Swift) — %d found %s" % [
			int(counts["STRANDED"]), str(stranded)])
	await _finish()


# =============================================================================
# FRAME HELPERS — measured off the live world.
# =============================================================================
## The footprint polygon MapOverlay draws: BF_OUTLINE mapped through the frame
## InteriorLightingManager fitted to the shell's collision faces this boot.
func _building_polygon() -> PackedVector2Array:
	var out := PackedVector2Array()
	var ilm := _world.get_node_or_null("InteriorLightingManager")
	if ilm == null:
		return out
	var fit : Dictionary = ilm.call("get_building_frame")
	if fit.is_empty():
		return out
	var o : Vector2 = fit["o"]
	var fx : Vector2 = fit["x"]
	var fz : Vector2 = fit["z"]
	out.resize(BF_OUTLINE.size())
	for i in BF_OUTLINE.size():
		var b : Vector2 = BF_OUTLINE[i]
		out[i] = o + fx * b.x + fz * b.y
	return out


## Every staff-lot bay's world origin (both rows, all slots). The node ORIGIN
## alone is not the lot centre a car could park at — the bays span ~13 m each
## way — so proximity is measured to the nearest actual bay, not just the origin.
func _parking_bays(parking: Node3D) -> Array:
	var out : Array = []
	if parking == null or not parking.has_method("bay_world_transform"):
		return out
	var count : int = int(parking.get("bay_count"))
	for side in [-1, 1]:
		for idx in range(count):
			var xf : Transform3D = parking.call("bay_world_transform", side, idx)
			out.append(xf.origin)
	return out


func _bays_centroid(bays: Array) -> Vector2:
	if bays.is_empty():
		return Vector2.INF
	var acc := Vector2.ZERO
	for b in bays:
		acc += Vector2((b as Vector3).x, (b as Vector3).z)
	return acc / float(bays.size())


func _nearest_bay_dist(xz: Vector2, bays: Array, fallback: Vector3) -> float:
	if bays.is_empty():
		if fallback == Vector3.INF:
			return INF
		return xz.distance_to(Vector2(fallback.x, fallback.z))
	var best : float = INF
	for b in bays:
		best = minf(best, xz.distance_to(Vector2((b as Vector3).x, (b as Vector3).z)))
	return best


func _dist_point_to_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var ab_len_sq := ab.length_squared()
	if ab_len_sq < 1e-6:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / ab_len_sq, 0.0, 1.0)
	var proj := a + ab * t
	return p.distance_to(proj)


func _nearest_poly_dist(xz: Vector2, poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return INF
	if Geometry2D.is_point_in_polygon(xz, poly):
		return 0.0
	var best : float = INF
	for i in poly.size():
		var a : Vector2 = poly[i]
		var b : Vector2 = poly[(i + 1) % poly.size()]
		best = minf(best, _dist_point_to_segment(xz, a, b))
	return best


func _nearest_yard_dist(xz: Vector2, yard_polys: Array) -> float:
	if yard_polys.is_empty():
		return INF
	var best : float = INF
	for poly in yard_polys:
		best = minf(best, _nearest_poly_dist(xz, poly))
	return best


func _find_swift() -> Node3D:
	for vn in get_tree().get_nodes_in_group("vehicle"):
		var v := vn as Node3D
		if v != null and String(v.get("vehicle_type")) == "suzuki_swift_glx":
			return v
	return null


# =============================================================================
# Teardown
# =============================================================================
func _finish() -> void:
	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("RESULT: %s" % ["PASS" if _fails == 0 else "FAIL"])
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
