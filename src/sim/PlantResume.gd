extends RefCounted

## RESUME ON LOAD — the plant comes back as it was saved.
##
## Operator 2026-09-25 (docs/plant/operator_rulings_2026-09-25.md §R1-§R3,
## CLAIMED): "during normal gameplay or during normal shifts, I would like the
## state to be as it was at the end of the shift before." Asked what comes back,
## he chose all four: the run state, his settings, the material in the line, and
## the faults and alarms (latched, reset as before). This replaces the
## 2026-07-08 "cold start on load" decision (MainWorld._spawn_world_items). A
## machine placed NEW in build mode still starts as it always did (§R3).
##
## WHERE THE STATE GOES. Every placed body's run state rides in its own entry of
## the per-save factory file (BuildMode._save_layout, key "run"), beside its pose,
## the same way the lump cart's kg always did. So a machine's state cannot end up
## on another machine: the identity is the entry itself, not a key that has to
## match after the load. The line-level part (the kg ledger, the PLC, e-stop, the
## loose floor piles) rides in the file's version marker (key "plant_run"). Both
## are written by the same _save_layout call, so they are one snapshot.
##
## WHAT CARRIES STATE, and who owns its field list:
##   * LineFlow's node for the body: LineFlow.node_run_state / restore_node_run_state
##     (powered, spin, material, HAND/rpm settings, choke, the observers: motor
##     overload, the screw model, the compactor, the NIR wrap, the DRD cycle, and
##     the kg in the pipes leaving it).
##   * Any node under the body with save_run_state() / restore_run_state(d): the
##     extruder brain (model, start sequence, pelletiser, trip latches), the
##     laserfilter, the kopfilter, the waste bins, the bezinktank, the shredders,
##     the opzetband, the silo level sensor, the scrap bin, the lump cart.
##     Keyed by its path under the body ("." = the body itself).
##
## LOAD ORDER. BuildMode._apply_layout_entry only stashes the entry's "run" on the
## body (meta META). resume_world() applies it once LineFlow has rebuilt and the
## shift clock is loaded (MainWorld, after ShiftLifecycleManager.setup), because
## LineFlow's nodes only exist after the rebuild and the lump cart's cool timer
## is anchored to sim time. Until then a save of that body writes the stashed
## dict back unchanged, so a save during the load can never replace the saved
## state with the cold one.
##
## No class_name on purpose (CLAUDE.md: a fresh class_name is unknown to a bare
## headless run until the editor rebuilds its cache); preload this file.

const FORMAT : int = 1
## Meta on a loaded body: its saved run state, until resume_world() applies it.
const META : String = "plant_resume"
## A spilled floor pile that belongs to nobody placed (a chute spill, a lump
## spill); DirtHotspot's own pile and the belt heap (a mirror of a buffer) are
## not in the list.
const PILE_SCRIPT := preload("res://src/sim/FloorPile.gd")

# =============================================================================
# Generic helpers
# =============================================================================

## A JSON-safe copy of `v`: MaterialBatch → its dict (tagged), typed arrays →
## plain arrays, Vector3 / Color → tagged arrays. Anything else JSON cannot hold
## (a Node, a RefCounted) is dropped (null).
static func to_json(v: Variant) -> Variant:
	match typeof(v):
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return v
		TYPE_STRING_NAME:
			return String(v)
		TYPE_VECTOR3:
			var v3 : Vector3 = v
			return {"_v3": [v3.x, v3.y, v3.z]}
		TYPE_COLOR:
			var c : Color = v
			return {"_col": [c.r, c.g, c.b, c.a]}
		TYPE_ARRAY:
			var out : Array = []
			for x in (v as Array):
				out.append(to_json(x))
			return out
		TYPE_DICTIONARY:
			var d : Dictionary = {}
			for k in (v as Dictionary):
				d[String(k)] = to_json((v as Dictionary)[k])
			return d
		TYPE_OBJECT:
			if v is MaterialBatch:
				return batch_out(v as MaterialBatch)
			return null
	return null

## The inverse of to_json for the tagged forms. Plain values come back as JSON
## gave them (every number a float); unpack() coerces to the field's own type.
static func from_json(v: Variant) -> Variant:
	if v is Dictionary:
		var d : Dictionary = v
		if d.has("_mb"):
			return batch_in(d)
		if d.has("_v3") and d.size() == 1:
			var a : Array = d["_v3"]
			return Vector3(float(a[0]), float(a[1]), float(a[2]))
		if d.has("_col") and d.size() == 1:
			var c : Array = d["_col"]
			return Color(float(c[0]), float(c[1]), float(c[2]), float(c[3]))
		var out : Dictionary = {}
		for k in d:
			out[k] = from_json(d[k])
		return out
	if v is Array:
		var arr : Array = []
		for x in (v as Array):
			arr.append(from_json(x))
		return arr
	return v

## {} for a null or empty batch: most pipe stages and in/out batches are empty,
## and written out in full they made one line's factory file 4.7x larger
## (measured on 3B, 9.9 KB before the run state, 46.4 KB with). batch_in({})
## gives an empty batch back.
static func batch_out(b: MaterialBatch) -> Dictionary:
	if b == null or (b.mass_kg <= 0.0 and b.volume_m3 <= 0.0):
		return {}
	var d := b.to_dict()
	d["_mb"] = 1
	return d

static func batch_in(d: Dictionary) -> MaterialBatch:
	var comp : Dictionary = {}
	var raw_c : Variant = d.get("composition", {})
	if raw_c is Dictionary:
		for k in (raw_c as Dictionary):
			comp[String(k)] = float((raw_c as Dictionary)[k])
	return MaterialBatch.new(float(d.get("mass_kg", 0.0)), float(d.get("volume_m3", 0.0)),
		comp, String(d.get("origin", "")), float(d.get("water_kg", 0.0)),
		float(d.get("contaminant_kg", 0.0)))

## {field: json value} for each named property `obj` has.
static func pack(obj: Object, fields: Array) -> Dictionary:
	var out : Dictionary = {}
	if obj == null:
		return out
	for f in fields:
		var name : String = String(f)
		if name in obj:
			out[name] = to_json(obj.get(name))
	return out

## Write each saved field back, coerced to the type the field has NOW (JSON
## gives every number as a float; an enum or a count must come back an int, a
## typed Array[float] must be assigned in place). Returns the fields it could not
## apply, for the caller's report.
static func unpack(obj: Object, d: Dictionary) -> Array:
	var missed : Array = []
	if obj == null:
		return d.keys()
	for k in d:
		var name : String = String(k)
		if not (name in obj):
			missed.append(name)
			continue
		var cur : Variant = obj.get(name)
		var val : Variant = coerce(cur, from_json(d[k]))
		if typeof(cur) == TYPE_ARRAY and val is Array:
			(cur as Array).assign(val)
		elif typeof(cur) == TYPE_DICTIONARY and val is Dictionary:
			(cur as Dictionary).clear()
			(cur as Dictionary).merge(val)
		else:
			obj.set(name, val)
	return missed

## `val` in the type of `cur`. Arrays and dictionaries are coerced element by
## element against the current element of the same index / key when there is one.
static func coerce(cur: Variant, val: Variant) -> Variant:
	match typeof(cur):
		TYPE_INT:
			return int(val) if (typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT) else cur
		TYPE_FLOAT:
			return float(val) if (typeof(val) == TYPE_FLOAT or typeof(val) == TYPE_INT) else cur
		TYPE_BOOL:
			return bool(val)
		TYPE_STRING:
			return String(val) if val != null else ""
		TYPE_ARRAY:
			if not (val is Array):
				return cur
			var out : Array = []
			var ca : Array = cur
			for i in (val as Array).size():
				var x : Variant = (val as Array)[i]
				out.append(coerce(ca[i], x) if i < ca.size() else x)
			return out
		TYPE_DICTIONARY:
			if not (val is Dictionary):
				return cur
			var od : Dictionary = {}
			var cd : Dictionary = cur
			for k in (val as Dictionary):
				od[k] = coerce(cd[k], (val as Dictionary)[k]) if cd.has(k) else (val as Dictionary)[k]
			return od
		TYPE_OBJECT:
			# A batch field: an empty batch is saved as {} (batch_out).
			if cur is MaterialBatch:
				if val is MaterialBatch:
					return val
				return batch_in(val if val is Dictionary else {})
			return cur
	return val

# =============================================================================
# Capture (BuildMode._save_layout, once per placed body)
# =============================================================================

## Every node under `body` (and the body) that saves its own run state.
static func _owners(body: Node) -> Array:
	var out : Array = []
	if body.has_method("save_run_state"):
		out.append(body)
	for n in body.find_children("*", "", true, false):
		if n.has_method("save_run_state"):
			out.append(n)
	return out

## The run state of one placed body, or {} when it carries none. A body that
## still holds an unapplied stash (META) saves the stash: the load has not
## reached it yet, and its live state is the cold one it was built with.
static func capture_body(body: Node3D, lf: Node) -> Dictionary:
	if body == null or not is_instance_valid(body):
		return {}
	if body.has_meta(META):
		var st : Variant = body.get_meta(META)
		return (st as Dictionary).duplicate(true) if st is Dictionary else {}
	var out : Dictionary = {}
	if lf != null and is_instance_valid(lf) and lf.has_method("node_run_state"):
		var lfs : Dictionary = lf.call("node_run_state", body)
		if not lfs.is_empty():
			out["lf"] = lfs
	var parts : Dictionary = {}
	for o in _owners(body):
		var st2 : Variant = o.call("save_run_state")
		if st2 is Dictionary and not (st2 as Dictionary).is_empty():
			parts[String(body.get_path_to(o))] = st2
	if not parts.is_empty():
		out["parts"] = parts
	if not out.is_empty():
		out["v"] = FORMAT
	return out

## The line-level part: LineFlow's own (ledger, PLC, e-stop) and the loose
## floor piles, which no placed body owns.
static func capture_line(lf: Node, tree: SceneTree) -> Dictionary:
	var out : Dictionary = {"v": FORMAT}
	if lf != null and is_instance_valid(lf) and lf.has_method("line_run_state"):
		out["lf"] = lf.call("line_run_state")
	if tree != null:
		out["piles"] = capture_piles(tree)
	return out

## True for a FloorPile the resume keeps in the line-level list.
static func _loose_pile(p: Node) -> bool:
	if not (p is Node3D) or p.get_script() != PILE_SCRIPT:
		return false
	if p.has_meta("mirror_kg") or p.has_meta("placeable_id"):
		return false
	var par : Node = p.get_parent()
	if par != null and par.is_in_group("dirt_hotspot"):
		return false
	return float(p.get("mass_kg")) > 0.0

static func capture_piles(tree: SceneTree) -> Array:
	var out : Array = []
	for p in tree.get_nodes_in_group("floor_pile"):
		if not _loose_pile(p):
			continue
		var p3 := p as Node3D
		out.append({
			"name": String(p3.name),
			"pos": to_json(p3.global_position),
			"mass_kg": float(p3.get("mass_kg")),
			"density_kg_m3": float(p3.get("density_kg_m3")),
			"max_radius_m": float(p3.get("max_radius_m")),
			"angle_repose": float(p3.get("angle_repose")),
			"pile_color": to_json(p3.get("pile_color")),
			"solid": bool(p3.get("solid")),
		})
	return out

# =============================================================================
# Resume (MainWorld, once, after LineFlow's rebuild and the shift clock's load)
# =============================================================================

## Apply every stashed body and the line-level state. `bodies` is the placed
## root's children (BuildMode._placed_root); `line_state` what load_layout found
## in the version marker ({} for a save written before this). Returns a report:
## {bodies, lf_nodes, parts, piles, missed: [..]} — printed by the caller.
static func resume_world(bodies: Array, lf: Node, line_state: Dictionary, pile_parent: Node) -> Dictionary:
	var rep : Dictionary = {"bodies": 0, "lf_nodes": 0, "parts": 0, "piles": 0, "missed": []}
	# Piles first: a choked node re-finds the pile that refused it by position.
	var piles : Array = []
	if line_state.has("piles") and pile_parent != null:
		for pd in (line_state["piles"] as Array):
			var pile := restore_pile(pd as Dictionary, pile_parent)
			if pile != null:
				piles.append(pile)
	rep["piles"] = piles.size()
	for b in bodies:
		var body := b as Node3D
		if body == null or not is_instance_valid(body) or not body.has_meta(META):
			continue
		var st : Variant = body.get_meta(META)
		body.remove_meta(META)
		if not (st is Dictionary):
			continue
		rep["bodies"] = int(rep["bodies"]) + 1
		var d : Dictionary = st
		if d.has("lf") and lf != null and is_instance_valid(lf):
			if bool(lf.call("restore_node_run_state", body, d["lf"])):
				rep["lf_nodes"] = int(rep["lf_nodes"]) + 1
			else:
				(rep["missed"] as Array).append("%s: not a LineFlow node" % String(body.get_meta("placeable_id", body.name)))
		var parts : Dictionary = d.get("parts", {})
		for path in parts:
			var o : Node = body.get_node_or_null(NodePath(String(path)))
			if o == null or not o.has_method("restore_run_state"):
				(rep["missed"] as Array).append("%s: no part '%s'" % [String(body.get_meta("placeable_id", body.name)), path])
				continue
			o.call("restore_run_state", parts[path])
			rep["parts"] = int(rep["parts"]) + 1
	# Line-level last: the ledger, the PLC phase and the e-stop read the nodes
	# restored above.
	if line_state.has("lf") and lf != null and is_instance_valid(lf):
		lf.call("restore_line_run_state", line_state["lf"])
	# Owners that hold a claim on LineFlow (the extruders) re-assert it now that
	# their run commands are back.
	if lf != null and is_instance_valid(lf) and lf.is_inside_tree():
		lf.get_tree().call_group("extruder_machine", "on_line_flow_rebuilt", lf)
	return rep

## resume_world() for a BuildMode's loaded world: its placed bodies and the
## line-level state its load_layout read. What MainWorld calls; suites too.
static func resume_build_mode(bm: Node, lf: Node, pile_parent: Node) -> Dictionary:
	if bm == null or not is_instance_valid(bm):
		return {}
	var root : Node = bm.get("_placed_root")
	var bodies : Array = root.get_children() if root != null else []
	var line_state : Dictionary = bm.call("take_pending_plant_run") if bm.has_method("take_pending_plant_run") else {}
	return resume_world(bodies, lf, line_state, pile_parent)

static func restore_pile(pd: Dictionary, parent: Node) -> Node3D:
	var kg : float = float(pd.get("mass_kg", 0.0))
	if kg <= 0.0:
		return null
	var pile = PILE_SCRIPT.new()
	pile.name = String(pd.get("name", "FloorPile"))
	pile.max_radius_m = float(pd.get("max_radius_m", pile.max_radius_m))
	pile.angle_repose = float(pd.get("angle_repose", pile.angle_repose))
	var col : Variant = from_json(pd.get("pile_color", null))
	if col is Color:
		pile.pile_color = col
	pile.solid = bool(pd.get("solid", true))
	parent.add_child(pile)
	var pos : Variant = from_json(pd.get("pos", null))
	if pos is Vector3:
		(pile as Node3D).global_position = pos
	pile.density_kg_m3 = float(pd.get("density_kg_m3", pile.density_kg_m3))
	pile.mass_kg = kg
	pile.call("_update_visual")
	return pile
