extends Node

# Single global world layout, persisted to user://world_layout.json.
# Populated once via the WorldSetup scene (top-down marker placement) and
# consumed by MainWorld whenever a save starts/loads. A missing or empty layout
# falls back to MainWorld's old hardcoded positions.

const LAYOUT_PATH := "user://world_layout.json"

## Redirects save()/_load() to another file. Empty (always, in the shipped game)
## means the real LAYOUT_PATH. A suite or bench that keeps a world booted past
## MainWorld's 60 s autosave sets this FIRST — that autosave ends in save(), i.e.
## a rewrite of the operator's world ground truth, which lives in git nowhere.
var layout_path_override : String = ""

func get_layout_path() -> String:
	return layout_path_override if layout_path_override != "" else LAYOUT_PATH

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
# offset from player_spawn.
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
		# Frame stamp — lets a future build DETECT a convention change instead of
		# silently reinterpreting coordinates. See _check_marker_frame.
		"marker_frame": MARKER_FRAME,
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
		"factory_center_pc":   _v2(factory_center_pc) if has_pc_data else {},
		"player_spawn_pc":     _v2(player_spawn_pc)   if has_pc_data else {},
		"vehicle_spawns_pc":   _dict_v2(vehicle_spawns_pc) if has_pc_data else {},
		"line_starts_pc":      _dict_v2_single(line_starts_pc) if has_pc_data else {},
		"compressor_spawn_pc": _v2(compressor_spawn_pc) if has_pc_data else {},
		"bale_yards_pc":       _yards_pc_to_json() if has_pc_data else [],
		# #221-PC Phase 5 — PC parallels for the new operator markers.
		"staff_parking_pc":    _v2(staff_parking_pc) if has_pc_data else {},
		"player_swift_pc":     _v2(player_swift_pc) if has_pc_data else {},
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
	# Crash-safe: .tmp + last-good .bak + swap (see AtomicFile). The old direct
	# FileAccess.WRITE truncated the world file to 0 bytes before writing a byte
	# of it, so a kill mid-save left the demo-spawn fallback in place of the world.
	var path := get_layout_path()
	var err := AtomicFile.write_json(path, data, "  ")
	if err != OK:
		push_error("[WorldLayout] Could not write %s (error %d) — the previous file is untouched" % [path, err])
		return
	# Verbose confirmation so the user can verify which player_spawn / vehicle
	# spawns / yard count actually hit disk. Read this whenever the satellite
	# or in-game spawn seems "off" — the line below is the source of truth.
	print("[WorldLayout] saved → %s" % path)
	print("  player_spawn   = (%.2f, %.2f, %.2f)" % [player_spawn.x, player_spawn.y, player_spawn.z])
	print("  factory_center = (%.2f, %.2f, %.2f)" % [factory_center.x, factory_center.y, factory_center.z])
	print("  vehicle_spawns = %d entries  %s" % [vehicle_spawns.size(), str(vehicle_spawns.keys())])
	print("  line_starts    = %d entries  %s" % [line_starts.size(), str(line_starts.keys())])
	print("  bale_yards     = %d rectangle(s)" % bale_yards.size())
	emit_signal("layout_changed")

## True when a marker's XZ magnitude says "Dutch RD scene-space" (~1e5 m) rather
## than a scene-absolute position around the building (~1e2 m).
func _is_rd_scale(p: Vector3) -> bool:
	return abs(p.x) > 10000.0 or abs(p.z) > 10000.0

# CANONICAL frame tag written into every save. A file carrying a DIFFERENT tag
# was authored by a build whose marker convention we cannot reconstruct, so it
# is reported loudly rather than reinterpreted (see _check_marker_frame).
const MARKER_FRAME := "scene_absolute"
# Source of the RD→scene shift. This is the TILE mesh MainWorld.tscn's
# BuildingShell transform is derived from — not the factory-solid mesh the
# scene actually displays. The two centres are 220.8 m apart, so measuring the
# shift from the wrong one authors markers 220.8 m from the ones on disk.
const BUILDING_TILE_OBJ := "res://assets/models/CeDo_building.obj"
# True when the loaded file's frame tag disagrees with MARKER_FRAME. Consumers
# can gate on it; the load itself does not silently rewrite the markers.
var marker_frame_trusted : bool = true
# True when the loaded file actually CARRIED a marker_frame key. Absent means the
# file predates the stamp: its scene-absolute markers are still trustworthy (the
# writer never changed), but its derived PC block is not — see _load.
var _file_has_frame_stamp : bool = false

## RD → scene-absolute shift, MEASURED from the building tile mesh's AABB centre
## so it cannot drift from MainWorld.tscn's BuildingShell transform. Falls back
## to the saved satellite centre (RD x → scene x, RD y → scene −z) when the mesh
## is unavailable; returns ZERO if neither source exists, which leaves RD
## markers untouched rather than shifting them by a guess.
func _rd_to_scene_shift() -> Vector3:
	var mesh = ResourceLoader.load(BUILDING_TILE_OBJ)
	if mesh is Mesh:
		var c : Vector3 = (mesh as Mesh).get_aabb().get_center()
		return Vector3(c.x, 0.0, c.z)
	if has_satellite and satellite_center_rd != Vector2.ZERO:
		push_warning("[WorldLayout] %s unavailable — falling back to the saved satellite centre for the RD shift" % BUILDING_TILE_OBJ)
		return Vector3(satellite_center_rd.x, 0.0, -satellite_center_rd.y)
	push_error("[WorldLayout] RD-scale markers present but no tile mesh and no satellite centre — leaving them unconverted (they will be rejected by _layout_rel_sane)")
	return Vector3.ZERO

## Loud, explicit report when the file mixes RD-scale and scene-absolute markers.
## The per-marker conversion below handles it correctly, but a mixed file means
## some earlier session wrote through a different frame — the operator should
## know, because the un-mixed half may be positioned by an old convention.
func _warn_if_mixed_frame() -> void:
	var rd : Array[String] = []
	var local : Array[String] = []
	var bucket := func(p_name: String, p: Vector3) -> void:
		if p == Vector3.ZERO:
			return
		if _is_rd_scale(p): rd.append(p_name)
		else: local.append(p_name)
	bucket.call("player_spawn", player_spawn)
	bucket.call("factory_center", factory_center)
	for k in vehicle_spawns.keys():
		var arr : Array = vehicle_spawns[k]
		for i in arr.size():
			if arr[i] is Vector3: bucket.call("%s#%d" % [k, i + 1], arr[i])
	for k in line_starts.keys():
		bucket.call("line_%s" % k, line_starts[k])
	for y in bale_yards:
		for c in (y as Dictionary).get("corners", []):
			if c is Vector3: bucket.call("yard_%s" % (y as Dictionary).get("supplier_id", "?"), c)
	if rd.is_empty() or local.is_empty():
		return
	push_warning("[WorldLayout] MIXED COORDINATE FRAMES in %s — %d RD-scale marker(s) %s alongside %d scene-absolute marker(s) %s. Only the RD ones are converted; re-place the others by editing world_layout.json (WorldSetup was deleted 2026-08-17; seed copy at src/data/world/world_layout_seed.json)." % [
		get_layout_path(), rd.size(), str(rd.slice(0, 6)), local.size(), str(local.slice(0, 6))])

## Compare the file's frame tag against MARKER_FRAME. An untagged file predates
## the tag and is scene-absolute by construction (WorldSetup has only ever
## written `_screen_to_floor` output), so it is trusted. A file tagged with
## anything else was authored by a convention this build cannot reconstruct:
## report it loudly and leave the values alone — silently reinterpreting them is
## how markers end up hundreds of metres from where they were drawn.
func _check_marker_frame(parsed: Dictionary) -> void:
	_file_has_frame_stamp = parsed.has("marker_frame")
	var tag : String = String(parsed.get("marker_frame", MARKER_FRAME))
	marker_frame_trusted = (tag == MARKER_FRAME)
	if not marker_frame_trusted:
		push_error("[WorldLayout] %s declares marker_frame='%s' but this build only understands '%s' — markers are being loaded VERBATIM and may be misplaced. Re-save the layout by hand (WorldSetup was deleted 2026-08-17; seed copy at src/data/world/world_layout_seed.json)." % [
			get_layout_path(), tag, MARKER_FRAME])

## Bring a marker into the scene-absolute frame ONLY if it is itself RD-scale.
## Markers already in that frame pass through untouched — that per-marker rule is
## the mixed-file safety net (see the 377 km note in _load).
func _to_scene_frame(p: Vector3, shift: Vector3) -> Vector3:
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

## The world layout an exported build carries (the Steam build). The build
## script copies the operator's world_layout.json here at export time
## (tools/steam/build_windows.sh); steam_seed/ is gitignored.
const SEED_PATH := "res://steam_seed/world_layout.json"

## Exported builds only. A player's first launch has no world_layout.json, and
## without one the world has no building, gate or spawns (measured 2026-09-26,
## docs/steam/README.md). Writes the layout the build carries to user:// once;
## after that the player's own file rules. The editor and every suite never
## take this path, so a missing layout there still means "not configured".
func _seed_from_build(path: String) -> bool:
	if OS.has_feature("editor") or path != LAYOUT_PATH:
		return false
	var text := FileAccess.get_file_as_string(SEED_PATH)
	if text.is_empty() or AtomicFile.write_text(path, text) != OK:
		return false
	print("[WorldLayout] first launch: seeded %s from the layout this build carries" % path)
	return true

func _load() -> void:
	var path := get_layout_path()
	if not AtomicFile.exists_any(path) and not _seed_from_build(path):
		return
	# Recovering read. A truncated or empty primary (what a kill mid-save used to
	# leave behind) falls back to the .tmp / .bak generation instead of being
	# treated as "no layout" — which reverted the world to the demo spawns and
	# let the next save overwrite the damage. A wrong root type counts as damage.
	var parsed = AtomicFile.read_json(path, TYPE_DICTIONARY)
	if parsed == null:
		push_warning("[WorldLayout] %s is unreadable and has no valid .tmp/.bak — ignoring" % path)
		return

	if _get_max_depth(parsed) > 64:
		push_warning("[WorldLayout] %s is too deeply nested — ignoring to prevent stack overflow" % path)
		return

	# Frame check FIRST — everything below decides what to trust based on it.
	_check_marker_frame(parsed)
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
	# DISCARD PC data written before the frame stamp existed. Those values were
	# produced by migrate_to_pc composing scene_to_pc with the old rotate+anchor
	# `_layout_to_scene`, so they encode the 228 m misplacement — the operator's
	# own file carries player_spawn_pc = (297.34, 594.04) where the Plant
	# contract (Plant.gd:20-22) requires PC_CENTER (500, 500).
	#
	# MainWorld normally re-migrates right after Plant.init and overwrites them,
	# but that only happens when Plant was not already initialised. Any boot that
	# skips the re-migration would spawn straight off these stale numbers. Zero
	# them so the PC path CANNOT run until it has been recomputed — a missing
	# migration then falls back to the legacy (correct) reader instead of
	# silently reinstating the old frame.
	if has_pc_data and not _file_has_frame_stamp:
		print("[WorldLayout] PC block predates the marker_frame stamp — discarding it; it will be recomputed from the scene-absolute markers")
		factory_center_pc = Vector2.ZERO
		player_spawn_pc = Vector2.ZERO
		vehicle_spawns_pc.clear()
		line_starts_pc.clear()
		compressor_spawn_pc = Vector2.ZERO
		bale_yards_pc.clear()
		staff_parking_pc = Vector2.ZERO
		player_swift_pc = Vector2.ZERO
		has_pc_data = false
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
	# Legacy RD conversion. Ancient WorldSetup saves wrote positions in Dutch RD
	# coords (magnitudes ~1e5+) because the satellite quad was anchored at RD
	# scene-space. Everything since stores markers SCENE-ABSOLUTE — the frame
	# MainWorld.tscn's BuildingShell transform defines — so this block's only job
	# is to bring an RD marker into THAT frame.
	#
	# The shift is the building TILE's own centre (measured from the mesh, see
	# _rd_to_scene_shift), which is exactly what MainWorld.tscn:76 subtracts.
	# It is NOT taken from player_spawn any more: doing that zeroed player_spawn
	# and turned the file into player-relative OFFSETS, a frame no reader uses
	# (PlayerSpawner, the boot header, _get_factory_anchor and Plant all read
	# markers absolutely). That mismatch is the 228 m vehicle-misplacement bug.
	#
	# CRITICAL (377 km bug): the file can be MIXED — a previous load converted
	# vehicles/yards while a later WorldSetup save re-wrote player_spawn in RD.
	# Blanket-subtracting corrupts the already-converted markers (18 − 183857 ≈
	# −183839 → spawns 377 km away, NaN transforms, 34k render errors). So the
	# conversion stays PER-MARKER: only RD-scale markers are shifted.
	var shift := Vector3.ZERO
	if _has_any_rd_marker() or _is_rd_scale(player_spawn) or _is_rd_scale(factory_center):
		shift = _rd_to_scene_shift()
	if shift != Vector3.ZERO:
		_warn_if_mixed_frame()
		print("[WorldLayout] Detected RD-scale coordinates — converting RD markers to the scene-absolute frame (tile anchor %.1f, %.1f)" % [shift.x, shift.z])
		player_spawn   = _to_scene_frame(player_spawn, shift)
		factory_center = _to_scene_frame(factory_center, shift)
		compressor_spawn = _to_scene_frame(compressor_spawn, shift)
		# #221-PC Phase 5 — operator-draggable single-point markers ride the same
		# RD→scene shift so they end up in the same frame as the rest.
		staff_parking  = _to_scene_frame(staff_parking, shift)
		player_swift   = _to_scene_frame(player_swift, shift)
		for k in vehicle_spawns.keys():
			var arr : Array = vehicle_spawns[k]
			var out : Array = []
			for p in arr:
				if p is Vector3: out.append(_to_scene_frame(p, shift))
			vehicle_spawns[k] = out
		for k in line_starts.keys():
			line_starts[k] = _to_scene_frame(line_starts[k], shift)
		for y in bale_yards:
			var corners : Array = y.get("corners", [])
			for i in range(corners.size()):
				if corners[i] is Vector3:
					corners[i] = _to_scene_frame(corners[i], shift)
			y["corners"] = corners
	print("[WorldLayout] loaded from %s" % get_layout_path())
	print("  player_spawn   = (%.2f, %.2f, %.2f)" % [player_spawn.x, player_spawn.y, player_spawn.z])
	print("  vehicle_spawns = %d entries" % vehicle_spawns.size())
	print("  line_starts    = %d entries" % line_starts.size())
	print("  bale_yards     = %d rectangle(s)" % bale_yards.size())
	# Distances-from-player report so the user can see at a glance whether their
	# markers are realistic plant distances (10–40 m) or accidentally far apart.
	# Markers are scene-absolute, so this is a plain subtraction — and it is the
	# SAME number the spawner must land on. When the two disagreed, the spawner
	# was wrong (see WorldFrame._layout_to_scene); src/tests/test_vehicle_spawn_frame.gd
	# now asserts they agree.
	print("  ── distance from player_spawn (XZ horizontal m) ──")
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

func _get_max_depth(val: Variant, current_depth: int = 1, limit: int = 64) -> int:
	if current_depth > limit:
		return current_depth
	var max_d = current_depth
	if typeof(val) == TYPE_DICTIONARY:
		for key in val:
			var d = _get_max_depth(val[key], current_depth + 1, limit)
			if d > limit: return d
			if d > max_d: max_d = d
	elif typeof(val) == TYPE_ARRAY:
		for item in val:
			var d = _get_max_depth(item, current_depth + 1, limit)
			if d > limit: return d
			if d > max_d: max_d = d
	return max_d

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
