extends Node

# Single global world layout, persisted to user://world_layout.json.
# Populated once via the WorldSetup scene (top-down marker placement) and
# consumed by MainWorld whenever a save starts/loads. A missing or empty layout
# falls back to MainWorld's old hardcoded positions.

const LAYOUT_PATH := "user://world_layout.json"

const VEHICLE_IDS := ["forklift", "bale_clamp", "merlo", "merlo_p40", "mast_lift"]
const LINE_IDS    := ["1", "3a", "3b", "3c", "6"]
# Legacy id alias — old layouts wrote "scissor" before we renamed to "mast_lift".
# Read paths normalise it on load; write paths only ever emit "mast_lift".
const LEGACY_VEHICLE_ALIASES := {"scissor": "mast_lift"}

# Markers — all in world-space, Y is floor-relative.
var factory_center : Vector3 = Vector3.ZERO
var player_spawn   : Vector3 = Vector3.ZERO
# Each vehicle id maps to an ARRAY of spawn positions so the user can place
# multiple forklifts / bale clamps / Merlos / mast lifts.
var vehicle_spawns : Dictionary = {}   # id → Array[Vector3]
var line_starts    : Dictionary = {}   # id → Vector3
# Optional marker for the visible compressor pair (compressor_a / compressor_b
# placeables LineFlow spawns alongside the abstract air-network compressors).
# Vector3.ZERO means "no marker placed" — LineFlow then falls back to a default
# offset from player_spawn. TODO: hook WorldSetup UI for placing this marker.
var compressor_spawn : Vector3 = Vector3.ZERO
# Polygonal bale yards — each yard is a closed 4-corner polygon tagged with the
# supplier whose bales stack there (BaleDefs ids: rotterdam / alba_marl / zwolle
# / forstplus). Old single-rectangle format is discarded on load.
var bale_yards     : Array = []        # [{supplier_id:String, corners:Array[Vector3]}]

# ── #221-PC Phase 5 — operator-draggable markers for previously-hardcoded
# placements (parking lot, the player's parked Swift). When unset
# (Vector3.ZERO / Vector2.ZERO), MainWorld and ShiftCarSpawner fall back to
# the Phase 3 / Phase 4 PC constants. When set in WorldSetup, the marker
# wins — drag in WorldSetup, the lot / Swift moves wherever you drop it.
var staff_parking   : Vector3 = Vector3.ZERO
var player_swift    : Vector3 = Vector3.ZERO

# ── #221-PC Phase 2 — Plant Coordinate (PC) parallel fields ──────────────────
# Mirror of the legacy fields above, but as Vector2 in the 1000×1000 PC grid
# centred on the building (Plant.PC_CENTER = (500, 500)). Populated by
# `migrate_to_pc(layout_to_scene_callable)` after Plant.init() has run; loaded
# from disk if a v2+ save wrote them. Spawners continue to read the legacy
# fields until Phase 3 migrates them — having both means the migration can be
# done one subsystem at a time without breaking saves.
var factory_center_pc   : Vector2 = Vector2.ZERO
var player_spawn_pc     : Vector2 = Vector2.ZERO
var vehicle_spawns_pc   : Dictionary = {}   # id → Array[Vector2]
var line_starts_pc      : Dictionary = {}   # id → Vector2
var compressor_spawn_pc : Vector2 = Vector2.ZERO
var bale_yards_pc       : Array = []        # [{supplier_id:String, corners_pc:Array[Vector2]}]
# #221-PC Phase 5 — PC parallels for the new operator markers above.
var staff_parking_pc    : Vector2 = Vector2.ZERO
var player_swift_pc     : Vector2 = Vector2.ZERO
# True after migrate_to_pc has populated the PC fields (in-memory) OR after
# a v2+ save was loaded from disk. Spawners can check this to decide whether
# to read PC or fall back to legacy.
var has_pc_data : bool = false

# WMS satellite reference (so we can re-fetch / re-project later if needed).
var satellite_center_rd : Vector2 = Vector2.ZERO   # EPSG:28992 metres (Rijksdriehoek)
var satellite_extent_m  : float   = 400.0          # bbox edge length in metres
var has_satellite       : bool    = false

# Floor-plan overlay (the CeDo127 floor-plan PNG, calibrated by the user once
# so machine placement can be done with high accuracy against the labelled
# halls / extruders / wash lines in the plan). Persists across sessions so the
# user calibrates exactly once.
var floor_plan_enabled  : bool    = false
var floor_plan_opacity  : float   = 0.6           # 0–1
var floor_plan_offset_x : float   = 0.0           # m, relative to shell centre
var floor_plan_offset_z : float   = 0.0           # m, relative to shell centre
var floor_plan_scale_m  : float   = 100.0         # world height (Z extent) the plan covers
var floor_plan_rot_deg  : float   = 0.0           # rotation around Y axis

# ── Building STRUCTURE (walls + doors + gates + windows) ─────────────────────────
# Shared across ALL saves — once you build the factory's interior structure (walls,
# doors, gates, windows), every save and every NEW save inherits it. Machines
# remain per-save. Entries are the same JSON dicts BuildMode._save_layout produces
# for these placeable ids (wall_low/tall/full + kind=="surface" door/gate/window),
# so we round-trip them as-is without a parallel schema.
var structure_items : Array = []

signal layout_changed

func _ready() -> void:
	_load()

func is_configured() -> bool:
	# Treat the layout as "configured" once the user has saved ANY layout data.
	# (player_spawn can legitimately be exactly Vector3.ZERO after the RD-coord
	# re-centring, so checking it alone falsely re-triggers in-world setup mode.)
	return player_spawn != Vector3.ZERO \
		or factory_center != Vector3.ZERO \
		or not vehicle_spawns.is_empty() \
		or not line_starts.is_empty() \
		or not bale_yards.is_empty()

## Returns the array of spawn positions for vehicles of type `id`. Empty array
## means MainWorld will fall back to its hardcoded anchor + offset.
func get_vehicle_spawns(id: String) -> Array:
	var arr = vehicle_spawns.get(id, [])
	return arr if arr is Array else []

func get_line_start(id: String, fallback: Vector3) -> Vector3:
	return line_starts.get(id, fallback)

func add_vehicle_spawn(id: String, pos: Vector3) -> void:
	var arr : Array = vehicle_spawns.get(id, [])
	if not (arr is Array): arr = []
	arr.append(pos)
	vehicle_spawns[id] = arr

func remove_vehicle_spawn(id: String, index: int) -> void:
	var arr : Array = vehicle_spawns.get(id, [])
	if arr is Array and index >= 0 and index < arr.size():
		arr.remove_at(index)
		vehicle_spawns[id] = arr

func clear_vehicle_spawns(id: String) -> void:
	vehicle_spawns[id] = []

func set_line_start(id: String, pos: Vector3) -> void:
	line_starts[id] = pos

## Append a polygonal bale yard. `supplier_id` is a BaleDefs origin id
## (rotterdam / alba_marl / zwolle / forstplus). `corners` is a 4-element
## Array[Vector3] in placement order (Y is ignored; the polygon lives at
## floor level in MainWorld).
func add_bale_yard(supplier_id: String, corners: Array) -> void:
	bale_yards.append({
		"supplier_id": supplier_id,
		"corners":     corners.duplicate(true),
	})

func clear() -> void:
	factory_center = Vector3.ZERO
	player_spawn = Vector3.ZERO
	vehicle_spawns.clear()
	line_starts.clear()
	compressor_spawn = Vector3.ZERO
	bale_yards.clear()
	# NB: structure_items is intentionally NOT cleared here. The building structure
	# (walls/doors/gates/windows) belongs to the SITE — clearing markers in WorldSetup
	# shouldn't wipe the interior the user has built across many sessions. Use the
	# Build-mode UI to remove individual structure items.

func save() -> void:
	var data := {
		"version": 2 if has_pc_data else 1,
		"factory_center": _v3(factory_center),
		"player_spawn":   _v3(player_spawn),
		"vehicle_spawns": _dict_v3(vehicle_spawns),
		"line_starts":    _dict_v3_single(line_starts),
		"compressor_spawn": _v3(compressor_spawn),
		"bale_yards":     _yards_to_json(),
		# #221-PC Phase 5 — operator-draggable markers (legacy Vector3).
		"staff_parking":  _v3(staff_parking),
		"player_swift":   _v3(player_swift),
		# #221-PC Phase 2 — parallel PC fields. Only written when migrate_to_pc
		# has populated them (has_pc_data == true). Older readers ignore the
		# new keys; newer readers can fall back to legacy if these are absent.
		"factory_center_pc":   _v2(factory_center_pc) if has_pc_data else null,
		"player_spawn_pc":     _v2(player_spawn_pc)   if has_pc_data else null,
		"vehicle_spawns_pc":   _dict_v2(vehicle_spawns_pc) if has_pc_data else null,
		"line_starts_pc":      _dict_v2_single(line_starts_pc) if has_pc_data else null,
		"compressor_spawn_pc": _v2(compressor_spawn_pc) if has_pc_data else null,
		"bale_yards_pc":       _yards_pc_to_json() if has_pc_data else null,
		# #221-PC Phase 5 — PC parallels for the new operator markers.
		"staff_parking_pc":    _v2(staff_parking_pc) if has_pc_data else null,
		"player_swift_pc":     _v2(player_swift_pc) if has_pc_data else null,
		"satellite": {
			"center_rd_x": satellite_center_rd.x,
			"center_rd_y": satellite_center_rd.y,
			"extent_m":    satellite_extent_m,
			"has_image":   has_satellite,
		},
		"floor_plan": {
			"enabled":  floor_plan_enabled,
			"opacity":  floor_plan_opacity,
			"offset_x": floor_plan_offset_x,
			"offset_z": floor_plan_offset_z,
			"scale_m":  floor_plan_scale_m,
			"rot_deg":  floor_plan_rot_deg,
		},
		"structure_items": structure_items,
	}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[WorldLayout] Could not write %s" % LAYOUT_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	# Verbose confirmation so the user can verify which player_spawn / vehicle
	# spawns / yard count actually hit disk. Read this whenever the satellite
	# or in-game spawn seems "off" — the line below is the source of truth.
	print("[WorldLayout] saved → %s" % LAYOUT_PATH)
	print("  player_spawn   = (%.2f, %.2f, %.2f)" % [player_spawn.x, player_spawn.y, player_spawn.z])
	print("  factory_center = (%.2f, %.2f, %.2f)" % [factory_center.x, factory_center.y, factory_center.z])
	print("  vehicle_spawns = %d entries  %s" % [vehicle_spawns.size(), str(vehicle_spawns.keys())])
	print("  line_starts    = %d entries  %s" % [line_starts.size(), str(line_starts.keys())])
	print("  bale_yards     = %d rectangle(s)" % bale_yards.size())
	emit_signal("layout_changed")

## True when a marker's XZ magnitude says "Dutch RD scene-space" (~1e5 m) rather
## than a local offset around the building (~1e2 m).
func _is_rd_scale(p: Vector3) -> bool:
	return abs(p.x) > 10000.0 or abs(p.z) > 10000.0

## Shift a marker into local space ONLY if it is itself RD-scale; markers that
## are already local offsets pass through untouched (mixed-file safety).
func _localized(p: Vector3, shift: Vector3) -> Vector3:
	return p - shift if _is_rd_scale(p) else p

## Any vehicle / line-start / yard-corner marker still in RD space? Used to
## decide whether the satellite-centre fallback anchor is needed at all.
func _has_any_rd_marker() -> bool:
	for k in vehicle_spawns.keys():
		for p in vehicle_spawns[k]:
			if p is Vector3 and _is_rd_scale(p): return true
	for k in line_starts.keys():
		if _is_rd_scale(line_starts[k]): return true
	for y in bale_yards:
		for c in y.get("corners", []):
			if c is Vector3 and _is_rd_scale(c): return true
	return false

func _load() -> void:
	if not FileAccess.file_exists(LAYOUT_PATH):
		return
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.READ)
	if f == null: return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[WorldLayout] %s is not a JSON object — ignoring" % LAYOUT_PATH)
		return
	factory_center = _read_v3(parsed.get("factory_center", {}))
	player_spawn   = _read_v3(parsed.get("player_spawn",   {}))
	vehicle_spawns = _read_dict_v3(parsed.get("vehicle_spawns", {}))
	# Line starts are still SINGLE Vector3 per key (one start per production
	# line); _read_dict_v3 wraps everything as arrays for vehicles, so we use a
	# dedicated reader here.
	line_starts    = _read_dict_v3_single(parsed.get("line_starts", {}))
	# Optional visible-compressor marker (additive to the abstract air bank).
	# Missing → Vector3.ZERO → LineFlow uses its default offset from player_spawn.
	compressor_spawn = _read_v3(parsed.get("compressor_spawn", {}))
	bale_yards     = _read_yards(parsed.get("bale_yards", []))
	# #221-PC Phase 5 — operator-draggable markers (legacy fields).
	staff_parking  = _read_v3(parsed.get("staff_parking", {}))
	player_swift   = _read_v3(parsed.get("player_swift", {}))
	# #221-PC Phase 2 — read PC parallel fields if present (v2+ saves). When
	# absent (v1 / fresh save), the fields stay Vector2.ZERO and has_pc_data
	# stays false; MainWorld will call migrate_to_pc() right after Plant.init.
	factory_center_pc   = _read_v2(parsed.get("factory_center_pc", {}))
	player_spawn_pc     = _read_v2(parsed.get("player_spawn_pc", {}))
	vehicle_spawns_pc   = _read_dict_v2(parsed.get("vehicle_spawns_pc", {}))
	line_starts_pc      = _read_dict_v2_single(parsed.get("line_starts_pc", {}))
	compressor_spawn_pc = _read_v2(parsed.get("compressor_spawn_pc", {}))
	bale_yards_pc       = _read_yards_pc(parsed.get("bale_yards_pc", []))
	# #221-PC Phase 5 — PC parallels for the new operator markers.
	staff_parking_pc    = _read_v2(parsed.get("staff_parking_pc", {}))
	player_swift_pc     = _read_v2(parsed.get("player_swift_pc", {}))
	# has_pc_data: any non-zero PC field signals v2+. factory_center_pc=(500,500)
	# is the canonical "non-zero" marker since migrate_to_pc always sets it.
	has_pc_data = (factory_center_pc != Vector2.ZERO)
	var sat = parsed.get("satellite", {})
	if typeof(sat) == TYPE_DICTIONARY:
		satellite_center_rd = Vector2(sat.get("center_rd_x", 0.0), sat.get("center_rd_y", 0.0))
		satellite_extent_m  = float(sat.get("extent_m", 400.0))
		has_satellite       = bool(sat.get("has_image", false))
	var fp = parsed.get("floor_plan", {})
	if typeof(fp) == TYPE_DICTIONARY:
		floor_plan_enabled  = bool(fp.get("enabled", false))
		floor_plan_opacity  = float(fp.get("opacity", 0.6))
		floor_plan_offset_x = float(fp.get("offset_x", 0.0))
		floor_plan_offset_z = float(fp.get("offset_z", 0.0))
		floor_plan_scale_m  = float(fp.get("scale_m", 100.0))
		floor_plan_rot_deg  = float(fp.get("rot_deg", 0.0))
	# Building STRUCTURE — round-tripped as raw JSON dicts (BuildMode owns the schema).
	var si = parsed.get("structure_items", [])
	structure_items = (si as Array).duplicate(true) if si is Array else []
	# Re-centring: WorldSetup writes positions in Dutch RD coords (magnitudes
	# ~1e5+) because its satellite quad is anchored at RD scene-space. The
	# building shell model has its own internal scene-space, so markers in RD
	# don't line up with the shell. We subtract an RD anchor so all markers
	# become OFFSETS from where the player_spawn marker was placed; MainWorld
	# adds the player's actual scene-space position back in when spawning.
	#
	# CRITICAL (377 km bug): the file can be in a MIXED state — e.g. a previous
	# load converted vehicles/yards to local offsets and a later WorldSetup save
	# re-wrote player_spawn in RD coords. Blanket-subtracting the shift from
	# EVERYTHING then corrupts the already-local markers (18 − 183857 ≈ −183839
	# → equipment spawns 377 km away, NaN transforms, 34k render errors). So:
	#   1. pick the anchor from whichever marker IS RD-scale
	#      (player_spawn → factory_center → satellite centre), and
	#   2. convert PER-MARKER: only markers that are themselves RD-scale get
	#      shifted; already-local offsets pass through untouched.
	var shift := Vector3.ZERO
	if _is_rd_scale(player_spawn):
		shift = Vector3(player_spawn.x, 0.0, player_spawn.z)
	elif _is_rd_scale(factory_center):
		shift = Vector3(factory_center.x, 0.0, factory_center.z)
	elif has_satellite and satellite_center_rd != Vector2.ZERO \
			and _has_any_rd_marker():
		# RD x → world x, RD y → world −z (Godot right-handed).
		shift = Vector3(satellite_center_rd.x, 0.0, -satellite_center_rd.y)
	if shift != Vector3.ZERO:
		print("[WorldLayout] Detected RD-scale coordinates — converting RD markers to local offsets (anchor %.0f, %.0f)" % [shift.x, shift.z])
		player_spawn   = _localized(player_spawn, shift)
		factory_center = _localized(factory_center, shift)
		compressor_spawn = _localized(compressor_spawn, shift)
		# #221-PC Phase 5 — operator-draggable single-point markers ride the same
		# RD→local shift so they end up in the same frame as the rest.
		staff_parking  = _localized(staff_parking, shift)
		player_swift   = _localized(player_swift, shift)
		for k in vehicle_spawns.keys():
			var arr : Array = vehicle_spawns[k]
			var out : Array = []
			for p in arr:
				if p is Vector3: out.append(_localized(p, shift))
			vehicle_spawns[k] = out
		for k in line_starts.keys():
			line_starts[k] = _localized(line_starts[k], shift)
		for y in bale_yards:
			var corners : Array = y.get("corners", [])
			for i in range(corners.size()):
				if corners[i] is Vector3:
					corners[i] = _localized(corners[i], shift)
			y["corners"] = corners
	print("[WorldLayout] loaded from %s" % LAYOUT_PATH)
	print("  player_spawn   = (%.2f, %.2f, %.2f)" % [player_spawn.x, player_spawn.y, player_spawn.z])
	print("  vehicle_spawns = %d entries" % vehicle_spawns.size())
	print("  line_starts    = %d entries" % line_starts.size())
	print("  bale_yards     = %d rectangle(s)" % bale_yards.size())
	# Distances-from-player report so the user can see at a glance whether their
	# markers are realistic plant distances (10–40 m) or accidentally far apart.
	print("  ── offsets from player_spawn (XZ horizontal m) ──")
	for vid in vehicle_spawns.keys():
		var positions : Array = vehicle_spawns[vid]
		for i in range(positions.size()):
			var p : Vector3 = positions[i]
			var d := Vector2(p.x - player_spawn.x, p.z - player_spawn.z).length()
			print("    %s #%d : %.1f m away  (%.1f, %.1f)" % [vid, i + 1, d, p.x - player_spawn.x, p.z - player_spawn.z])
	for y in bale_yards:
		var corners : Array = (y as Dictionary).get("corners", [])
		if corners.is_empty(): continue
		var c := Vector3.ZERO
		for v in corners: c += v
		c /= float(corners.size())
		var d := Vector2(c.x - player_spawn.x, c.z - player_spawn.z).length()
		print("    yard '%s' : %.1f m away (centroid)" % [(y as Dictionary).get("supplier_id", "?"), d])

# ── JSON helpers ─────────────────────────────────────────────────────────────
func _v3(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func _read_v3(d) -> Vector3:
	if typeof(d) != TYPE_DICTIONARY: return Vector3.ZERO
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))

## Serialise a SINGLE-Vector3-per-key dictionary (line_starts). Returns
## Dictionary[String, {x,y,z}].
func _dict_v3_single(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[k] = _v3(src[k])
	return out

## Serialise the vehicle-spawn dictionary: keys are vehicle ids, values are
## arrays of Vector3 positions ({x,y,z} per element).
func _dict_v3(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var arr_out : Array = []
		var v = src[k]
		if v is Array:
			for p in v: arr_out.append(_v3(p))
		elif v is Vector3:
			arr_out.append(_v3(v))   # safety net if caller stuffed a bare Vector3
		out[k] = arr_out
	return out

## Read a dictionary of SINGLE Vector3 values (line_starts). Each key maps to
## one {x,y,z} dict on disk; we return Dictionary[String, Vector3].
func _read_dict_v3_single(src) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY: return out
	for k in src:
		out[k] = _read_v3(src[k])
	return out

## Read the vehicle-spawn dictionary. Accepts both the new format (key → array
## of {x,y,z}) and the legacy single-Vector3 format ({x,y,z}) for back-compat,
## so existing world_layout.json files keep working.
func _read_dict_v3(src) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY: return out
	for k in src:
		var canonical_key : String = k
		# Migrate legacy "scissor" → new "mast_lift".
		if LEGACY_VEHICLE_ALIASES.has(canonical_key):
			canonical_key = LEGACY_VEHICLE_ALIASES[canonical_key]
		var v = src[k]
		var arr : Array = []
		if v is Array:
			for p in v: arr.append(_read_v3(p))
		elif v is Dictionary:
			# Old single-position format — wrap it.
			arr.append(_read_v3(v))
		out[canonical_key] = arr
	return out

## Polygonal-yard serialiser. Each yard has a supplier_id and a list of corner
## Vector3s.
func _yards_to_json() -> Array:
	var out := []
	for y in bale_yards:
		var corners : Array = y.get("corners", [])
		var corners_json : Array = []
		for c in corners: corners_json.append(_v3(c))
		out.append({
			"supplier_id": y.get("supplier_id", ""),
			"corners":     corners_json,
		})
	return out

## Polygonal-yard parser. Old rectangle format (id / origin / size_x/z /
## rotation) is intentionally NOT migrated — the new schema is incompatible
## enough that a fresh layout pass is cleaner than guessing 4 corners from a
## centre+size. Anything that doesn't have a corners[] field is dropped.
func _read_yards(src) -> Array:
	var out := []
	if typeof(src) != TYPE_ARRAY: return out
	for entry in src:
		if typeof(entry) != TYPE_DICTIONARY: continue
		var corners_raw = entry.get("corners", [])
		if typeof(corners_raw) != TYPE_ARRAY or corners_raw.size() < 3: continue
		var corners : Array = []
		for c in corners_raw: corners.append(_read_v3(c))
		out.append({
			"supplier_id": entry.get("supplier_id", entry.get("id", "")),
			"corners":     corners,
		})
	return out

# ─────────────────────────────────────────────────────────────────────────────
# #221-PC Phase 2 — Plant Coordinate helpers + migration
# ─────────────────────────────────────────────────────────────────────────────

## Populate the PC parallel fields from the legacy Vector3 markers.
##
## `layout_to_scene` is the legacy converter from MainWorld (passed as a
## Callable so this autoload doesn't have to reach across the scene tree to
## find MainWorld). Each marker is converted layout-local → scene via the
## caller, then scene → PC via Plant.scene_to_pc. Plant MUST be initialized
## before this is called; we early-out with a warning if not.
##
## Safe to call multiple times: each call overwrites the PC fields with fresh
## conversions of whatever the legacy fields currently hold. The next save()
## will then write the PC fields to disk (version bumps to 2).
func migrate_to_pc(layout_to_scene: Callable) -> void:
	if not has_node("/root/Plant") or not Plant.is_initialized():
		push_warning("[WorldLayout] migrate_to_pc called before Plant.init — skipping")
		return
	# Helper: layout-local Vector3 → PC Vector2
	var to_pc := func(rel: Vector3) -> Vector2:
		var scene : Vector3 = layout_to_scene.call(rel)
		return Plant.scene_to_pc(scene)

	factory_center_pc   = to_pc.call(factory_center)
	player_spawn_pc     = to_pc.call(player_spawn)
	compressor_spawn_pc = to_pc.call(compressor_spawn)
	# #221-PC Phase 5 — operator-draggable markers. Each is Vector3.ZERO when
	# the operator hasn't placed it; to_pc(ZERO) maps to (500, 500), i.e. the
	# building centre, which is not a meaningful "user-set" value. Caller is
	# expected to check the LEGACY Vector3 for non-ZERO before reading the PC
	# field (consumer in MainWorld / ShiftCarSpawner gates on it).
	staff_parking_pc = to_pc.call(staff_parking)
	player_swift_pc  = to_pc.call(player_swift)

	vehicle_spawns_pc.clear()
	var veh_total : int = 0
	for vid in vehicle_spawns.keys():
		var arr : Array = vehicle_spawns[vid]
		var arr_pc : Array = []
		for p in arr:
			if p is Vector3:
				arr_pc.append(to_pc.call(p))
				veh_total += 1
		vehicle_spawns_pc[vid] = arr_pc

	line_starts_pc.clear()
	for lid in line_starts.keys():
		var p = line_starts[lid]
		if p is Vector3:
			line_starts_pc[lid] = to_pc.call(p)

	bale_yards_pc.clear()
	var yard_corners_total : int = 0
	for y in bale_yards:
		var corners_raw : Array = (y as Dictionary).get("corners", [])
		var corners_pc : Array = []
		for c in corners_raw:
			if c is Vector3:
				corners_pc.append(to_pc.call(c))
				yard_corners_total += 1
		bale_yards_pc.append({
			"supplier_id": (y as Dictionary).get("supplier_id", ""),
			"corners_pc":  corners_pc,
		})

	has_pc_data = true
	print("[WorldLayout] migrated to PC — factory_center_pc=(%.2f, %.2f) vehicles=%d yard_corners=%d lines=%d" % [
		factory_center_pc.x, factory_center_pc.y,
		veh_total, yard_corners_total, line_starts_pc.size()])

# ── Vector2 JSON helpers (mirror of the v3 family above) ─────────────────────
func _v2(v: Vector2) -> Dictionary:
	return {"x": v.x, "y": v.y}

func _read_v2(d) -> Vector2:
	if typeof(d) != TYPE_DICTIONARY: return Vector2.ZERO
	return Vector2(d.get("x", 0.0), d.get("y", 0.0))

## Serialise a SINGLE-Vector2-per-key dictionary (line_starts_pc).
func _dict_v2_single(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[k] = _v2(src[k])
	return out

## Serialise the PC vehicle-spawn dictionary (keys → arrays of Vector2).
func _dict_v2(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		var arr_out : Array = []
		var v = src[k]
		if v is Array:
			for p in v: arr_out.append(_v2(p))
		elif v is Vector2:
			arr_out.append(_v2(v))
		out[k] = arr_out
	return out

func _read_dict_v2_single(src) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY: return out
	for k in src:
		out[k] = _read_v2(src[k])
	return out

func _read_dict_v2(src) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY: return out
	for k in src:
		var canonical_key : String = k
		if LEGACY_VEHICLE_ALIASES.has(canonical_key):
			canonical_key = LEGACY_VEHICLE_ALIASES[canonical_key]
		var v = src[k]
		var arr : Array = []
		if v is Array:
			for p in v: arr.append(_read_v2(p))
		elif v is Dictionary:
			arr.append(_read_v2(v))
		out[canonical_key] = arr
	return out

func _yards_pc_to_json() -> Array:
	var out := []
	for y in bale_yards_pc:
		var corners : Array = (y as Dictionary).get("corners_pc", [])
		var corners_json : Array = []
		for c in corners: corners_json.append(_v2(c))
		out.append({
			"supplier_id": (y as Dictionary).get("supplier_id", ""),
			"corners_pc":  corners_json,
		})
	return out

func _read_yards_pc(src) -> Array:
	var out := []
	if typeof(src) != TYPE_ARRAY: return out
	for entry in src:
		if typeof(entry) != TYPE_DICTIONARY: continue
		var corners_raw = entry.get("corners_pc", [])
		if typeof(corners_raw) != TYPE_ARRAY: continue
		var corners : Array = []
		for c in corners_raw: corners.append(_read_v2(c))
		out.append({
			"supplier_id": entry.get("supplier_id", ""),
			"corners_pc":  corners,
		})
	return out
