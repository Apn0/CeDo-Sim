extends Node

# Single global world layout, persisted to user://world_layout.json.
# Populated once via the WorldSetup scene (top-down marker placement) and
# consumed by MainWorld whenever a save starts/loads. A missing or empty layout
# falls back to MainWorld's old hardcoded positions.

const LAYOUT_PATH := "user://world_layout.json"

const VEHICLE_IDS := ["forklift", "bale_clamp", "merlo", "merlo_p40", "scissor"]
const LINE_IDS    := ["1", "3a", "3b", "3c", "6"]

# Markers — all in world-space, Y is floor-relative.
var factory_center : Vector3 = Vector3.ZERO
var player_spawn   : Vector3 = Vector3.ZERO
var vehicle_spawns : Dictionary = {}   # id → Vector3
var line_starts    : Dictionary = {}   # id → Vector3
var bale_yards     : Array = []        # [{id:String, origin:Vector3, size:Vector2, rotation:float}]

# WMS satellite reference (so we can re-fetch / re-project later if needed).
var satellite_center_rd : Vector2 = Vector2.ZERO   # EPSG:28992 metres (Rijksdriehoek)
var satellite_extent_m  : float   = 400.0          # bbox edge length in metres
var has_satellite       : bool    = false

signal layout_changed

func _ready() -> void:
	_load()

func is_configured() -> bool:
	# Treat the layout as "configured" once the user has saved at least the player spawn.
	return player_spawn != Vector3.ZERO or factory_center != Vector3.ZERO

func get_vehicle_spawn(id: String, fallback: Vector3) -> Vector3:
	return vehicle_spawns.get(id, fallback)

func get_line_start(id: String, fallback: Vector3) -> Vector3:
	return line_starts.get(id, fallback)

func set_vehicle_spawn(id: String, pos: Vector3) -> void:
	vehicle_spawns[id] = pos

func set_line_start(id: String, pos: Vector3) -> void:
	line_starts[id] = pos

func add_bale_yard(id: String, origin: Vector3, size: Vector2, rotation: float = 0.0) -> void:
	bale_yards.append({
		"id":       id,
		"origin":   origin,
		"size":     size,
		"rotation": rotation,
	})

func clear() -> void:
	factory_center = Vector3.ZERO
	player_spawn = Vector3.ZERO
	vehicle_spawns.clear()
	line_starts.clear()
	bale_yards.clear()

func save() -> void:
	var data := {
		"version": 1,
		"factory_center": _v3(factory_center),
		"player_spawn":   _v3(player_spawn),
		"vehicle_spawns": _dict_v3(vehicle_spawns),
		"line_starts":    _dict_v3(line_starts),
		"bale_yards":     _yards_to_json(),
		"satellite": {
			"center_rd_x": satellite_center_rd.x,
			"center_rd_y": satellite_center_rd.y,
			"extent_m":    satellite_extent_m,
			"has_image":   has_satellite,
		},
	}
	var f := FileAccess.open(LAYOUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[WorldLayout] Could not write %s" % LAYOUT_PATH)
		return
	f.store_string(JSON.stringify(data, "  "))
	print("[WorldLayout] saved → %s" % LAYOUT_PATH)
	emit_signal("layout_changed")

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
	line_starts    = _read_dict_v3(parsed.get("line_starts",    {}))
	bale_yards     = _read_yards(parsed.get("bale_yards", []))
	var sat = parsed.get("satellite", {})
	if typeof(sat) == TYPE_DICTIONARY:
		satellite_center_rd = Vector2(sat.get("center_rd_x", 0.0), sat.get("center_rd_y", 0.0))
		satellite_extent_m  = float(sat.get("extent_m", 400.0))
		has_satellite       = bool(sat.get("has_image", false))
	print("[WorldLayout] loaded from %s" % LAYOUT_PATH)

# ── JSON helpers ─────────────────────────────────────────────────────────────
func _v3(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}

func _read_v3(d) -> Vector3:
	if typeof(d) != TYPE_DICTIONARY: return Vector3.ZERO
	return Vector3(d.get("x", 0.0), d.get("y", 0.0), d.get("z", 0.0))

func _dict_v3(src: Dictionary) -> Dictionary:
	var out := {}
	for k in src:
		out[k] = _v3(src[k])
	return out

func _read_dict_v3(src) -> Dictionary:
	var out := {}
	if typeof(src) != TYPE_DICTIONARY: return out
	for k in src:
		out[k] = _read_v3(src[k])
	return out

func _yards_to_json() -> Array:
	var out := []
	for y in bale_yards:
		out.append({
			"id":       y.get("id", ""),
			"origin":   _v3(y.get("origin", Vector3.ZERO)),
			"size_x":   (y.get("size", Vector2.ZERO) as Vector2).x,
			"size_z":   (y.get("size", Vector2.ZERO) as Vector2).y,
			"rotation": y.get("rotation", 0.0),
		})
	return out

func _read_yards(src) -> Array:
	var out := []
	if typeof(src) != TYPE_ARRAY: return out
	for entry in src:
		if typeof(entry) != TYPE_DICTIONARY: continue
		out.append({
			"id":       entry.get("id", ""),
			"origin":   _read_v3(entry.get("origin", {})),
			"size":     Vector2(entry.get("size_x", 0.0), entry.get("size_z", 0.0)),
			"rotation": float(entry.get("rotation", 0.0)),
		})
	return out
