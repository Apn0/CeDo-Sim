extends Node
## Macro save-back store (cluster: MACRO SAVE-BACK).
##
## Captures operator-jogged whole-line macro placements (LINE_3A / LINE_3B /
## LINE_1 / INTAKE_3A3B / LINE_SORT / LINE_3C6) back into a writable spec so
## subsequent placements emit the corrected layout instead of the original
## hard-coded const sequence in BuildMode.gd.
##
## STORAGE PATH (per operator spec — written to user://, NOT into the source tree):
##   user://macros/<macro_id>.json
## with <macro_id> in {line_3a, line_3b, line_1, line_intake_3a3b, line_sort,
## line_intake_3c6}. The directory user://macros is created on first save.
##
## LOAD PATH (consumed by BuildMode._build_full_line, replacing the const
## lookup): get_overrides(macro_id) returns the saved DELTAS dictionary
## { entry_index : { "dx":..., "dy":..., "dz":..., "drot_y":...,
##                   "scale":[sx,sy,sz] } } where each delta is RELATIVE TO THE
## PREVIOUS-IN-CHAIN machine's drift (per operator's chain-style rule:
## machine 3's delta is relative to machine 2's NEW position; machine 4 with
## no override inherits machine 3's accumulated drift unless an explicit
## override resets it).
##
## SCHEMA (on disk per macro file):
## {
##   "version": 1,
##   "macro_id": "line_3a",
##   "saved_at": "<ISO 8601 string>",
##   "machine_count": 23,                   # operator-observed count at save
##   "deltas": {
##     "0":  {"dx": 0.0, "dy": 0.0, "dz": 0.0, "drot_y": 0.0,
##            "scale": [1.0, 1.0, 1.0]},
##     "2":  {"dx": 0.5, "dy": 0.0, "dz": -0.25, "drot_y": 0.0,
##            "scale": [1.0, 1.0, 1.0]},
##     ...
##   }
## }
## Indices not present in `deltas` mean "no operator override — inherit the
## upstream-chain drift". An entry with all zero deltas + identity scale is
## technically a no-op but is kept if the operator explicitly captured it.
##
## Source of truth ordering: the operator JOGS machines in EDIT mode (K). The
## save-back routine walks placed_object children tagged with the same
## macro_id + macro_index meta, computes each one's CURRENT pose in the
## macro's local frame (using the macro_anchor meta = {start, rot_y} stamped
## at placement time by BuildMode._build_full_line), subtracts the
## const-baked nominal pose for that index, then stores the delta against the
## PREVIOUS-IN-CHAIN delta so re-applying at a fresh anchor cascades.

const MACRO_DIR : String = "user://macros"
const STORE_VERSION : int = 1
## Corruption guard (#macro-sink). A per-machine macro delta beyond this many
## metres — or non-finite — means the machine fell through the world (a physics
## sink) and its pose must NOT be recorded or re-applied. This is the line_3a
## dy≈-40 km bug: machine 32 sank, the save recorded its plummeting Y, and the
## delta compounded every save→load→fall cycle. Both the save-back
## (BuildMode.save_macro_overrides) and the load (get_overrides) reject such
## values so one glitched machine can never poison a whole macro. The whole
## plant footprint is ~150 m, so no legitimate single-machine jog approaches
## this cap.
const MAX_ABS_DELTA_M : float = 100.0

## True when a per-machine pose delta is finite and within the sane range.
## Shared by the save-back guard and the load-time filter.
static func delta_sane(dx: float, dy: float, dz: float, drot_y: float) -> bool:
	if not (is_finite(dx) and is_finite(dy) and is_finite(dz) and is_finite(drot_y)):
		return false
	return absf(dx) <= MAX_ABS_DELTA_M and absf(dy) <= MAX_ABS_DELTA_M and absf(dz) <= MAX_ABS_DELTA_M

## APPEND-ONLY. Each id maps to a SEQ in BuildMode; macro_index is the position
## in that SEQ, so an id removed here orphans every user://macros/<id>.json delta.
const MACRO_IDS : Array[String] = [
	"line_3a", "line_3b", "line_1",
	"line_intake_3a3b", "line_sort", "line_intake_3c6",
	"line_3c",
]

## In-memory cache: macro_id -> Dictionary (full file contents).
var _cache : Dictionary = {}

signal macro_saved(macro_id: String)
signal macro_reset(macro_id: String)

func _ready() -> void:
	_ensure_dir()
	for mid in MACRO_IDS:
		_load_one(mid)

func _ensure_dir() -> void:
	var d := DirAccess.open("user://")
	if d == null:
		push_warning("[LineMacroStore] Could not open user:// to make %s" % MACRO_DIR)
		return
	if not d.dir_exists("macros"):
		var err := d.make_dir("macros")
		if err != OK:
			push_warning("[LineMacroStore] make_dir failed (%d)" % err)

func _file_for(macro_id: String) -> String:
	return "%s/%s.json" % [MACRO_DIR, macro_id]

func _load_one(macro_id: String) -> void:
	var path := _file_for(macro_id)
	if not FileAccess.file_exists(path):
		_cache[macro_id] = {}
		return
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_cache[macro_id] = {}
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw) if raw.strip_edges() != "" else null
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("[LineMacroStore] Corrupt %s — ignoring" % path)
		_cache[macro_id] = {}
		return
	_cache[macro_id] = parsed

## True when the operator has saved any overrides for this macro.
func has_overrides(macro_id: String) -> bool:
	var d : Dictionary = _cache.get(macro_id, {})
	var deltas = d.get("deltas", {})
	return deltas is Dictionary and (deltas as Dictionary).size() > 0

## Return the deltas dictionary {int_index: {dx,dy,dz,drot_y,scale}} for a
## macro. Integer keys (JSON loads them as strings; we normalize). Caller is
## responsible for chain-style accumulation: when an index is missing, inherit
## the previous index's accumulated drift.
func get_overrides(macro_id: String) -> Dictionary:
	var d : Dictionary = _cache.get(macro_id, {})
	var raw = d.get("deltas", {})
	if not (raw is Dictionary):
		return {}
	var out : Dictionary = {}
	for k in (raw as Dictionary).keys():
		var idx : int = int(k)
		var v = (raw as Dictionary)[k]
		if not (v is Dictionary):
			continue
		var _dx := float((v as Dictionary).get("dx", 0.0))
		var _dy := float((v as Dictionary).get("dy", 0.0))
		var _dz := float((v as Dictionary).get("dz", 0.0))
		var _dr := float((v as Dictionary).get("drot_y", 0.0))
		# #macro-sink guard: drop a poisoned delta (e.g. a machine that sank to
		# y=-27 km) rather than teleporting the machine into the void on load.
		if not delta_sane(_dx, _dy, _dz, _dr):
			push_warning("[LineMacroStore] %s index %s delta implausible (dx=%.1f dy=%.1f dz=%.1f) — dropped" % [macro_id, k, _dx, _dy, _dz])
			continue
		out[idx] = {
			"dx":     _dx,
			"dy":     _dy,
			"dz":     _dz,
			"drot_y": _dr,
			"scale":  _read_scale((v as Dictionary).get("scale", [1.0, 1.0, 1.0])),
		}
	return out

## Persist a deltas dict to disk. `deltas` keys are int indices; values are
## {dx,dy,dz,drot_y,scale} (scale = [sx,sy,sz]).
func save_overrides(macro_id: String, deltas: Dictionary, machine_count: int) -> bool:
	if not (macro_id in MACRO_IDS):
		push_warning("[LineMacroStore] Unknown macro id %s" % macro_id)
		return false
	_ensure_dir()
	var on_disk : Dictionary = {}
	for k in deltas.keys():
		var v : Dictionary = deltas[k]
		var sc = v.get("scale", [1.0, 1.0, 1.0])
		if sc is Vector3:
			sc = [(sc as Vector3).x, (sc as Vector3).y, (sc as Vector3).z]
		on_disk[str(int(k))] = {
			"dx":     float(v.get("dx", 0.0)),
			"dy":     float(v.get("dy", 0.0)),
			"dz":     float(v.get("dz", 0.0)),
			"drot_y": float(v.get("drot_y", 0.0)),
			"scale":  sc,
		}
	var payload := {
		"version":       STORE_VERSION,
		"macro_id":      macro_id,
		"saved_at":      Time.get_datetime_string_from_system(true),
		"machine_count": machine_count,
		"deltas":        on_disk,
	}
	var path := _file_for(macro_id)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[LineMacroStore] Could not write %s" % path)
		return false
	f.store_string(JSON.stringify(payload, "\t"))
	f.close()
	_cache[macro_id] = payload
	print("[LineMacroStore] saved %d overrides → %s" % [on_disk.size(), path])
	emit_signal("macro_saved", macro_id)
	return true

## Drop the user's override file so subsequent placements use the hard-coded
## const SEQ again.
func reset(macro_id: String) -> bool:
	var path := _file_for(macro_id)
	if FileAccess.file_exists(path):
		var d := DirAccess.open(MACRO_DIR)
		if d != null:
			var fname := "%s.json" % macro_id
			var err := d.remove(fname)
			if err != OK:
				push_warning("[LineMacroStore] remove %s failed (%d)" % [path, err])
				return false
	_cache[macro_id] = {}
	emit_signal("macro_reset", macro_id)
	print("[LineMacroStore] reset %s — next placement uses const seed" % macro_id)
	return true

## Returns when this macro was last saved (ISO 8601) or empty string.
func saved_at(macro_id: String) -> String:
	var d : Dictionary = _cache.get(macro_id, {})
	return String(d.get("saved_at", ""))

## Apply chain-style accumulation across the macro's index range.
## Given saved (sparse) overrides {idx: delta}, returns a DENSE
## {0..count-1: cumulative_delta} where each missing index inherits the most
## recent prior index's cumulative delta. This is the per-operator rule:
## machine 4 (unmoved) follows machine 3's new transform.
func accumulated_chain(macro_id: String, count: int) -> Dictionary:
	var overrides := get_overrides(macro_id)
	var out : Dictionary = {}
	var acc := {"dx": 0.0, "dy": 0.0, "dz": 0.0, "drot_y": 0.0,
				"scale": Vector3.ONE}
	for i in range(count):
		if overrides.has(i):
			var ov : Dictionary = overrides[i]
			# Chained add: this index's stored delta is RELATIVE to the
			# accumulated drift from prior indices. The capture routine
			# subtracts the upstream accumulator before storing, so on load
			# we add it back here.
			acc = {
				"dx":     acc["dx"]     + float(ov.get("dx", 0.0)),
				"dy":     acc["dy"]     + float(ov.get("dy", 0.0)),
				"dz":     acc["dz"]     + float(ov.get("dz", 0.0)),
				"drot_y": acc["drot_y"] + float(ov.get("drot_y", 0.0)),
				"scale":  ov.get("scale", Vector3.ONE),
			}
		out[i] = {
			"dx":     acc["dx"],
			"dy":     acc["dy"],
			"dz":     acc["dz"],
			"drot_y": acc["drot_y"],
			"scale":  acc["scale"],
		}
	return out

func _read_scale(v) -> Vector3:
	if v is Vector3: return v
	if v is Array and (v as Array).size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	if v is float or v is int:
		return Vector3(float(v), float(v), float(v))
	return Vector3.ONE
