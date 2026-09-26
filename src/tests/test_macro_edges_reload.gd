extends Node
## A macro line's EXPLICIT flow edges survive a save → load round trip — by
## name, and by kg at every extruder.
##
##   godot --headless --path . res://src/tests/test_macro_edges_reload.tscn
##
## WHY THIS FILE EXISTS. BuildMode stamped `lf_explicit_outs` (NodePaths) only
## inside _build_full_line, and _save_layout never wrote it, so a world loaded
## from a save was wired by LineFlow's nearest-input-port fallback alone.
## Measured 2026-09-25 (probe_explicit_edges_roundtrip): lines 1/3A/3B built →
## 121 edges, 47 tagged nodes; saved and reloaded → 113 edges, 0 tagged. 3A's
## silo <-> band 2-cycle came back, 3B's silo lost its in-edge, extruder_1 its
## feed. Every macro lost its pins, streams, split and recirc on reload. Now
## load_layout re-derives them from the SEQ with the SAME function the build
## uses (BuildMode.macro_flow_edges); this suite proves the round trip.
##
##   A  every macro the build menu offers, plus a SECOND line_3a, in one world:
##      build → _save_layout → a fresh BuildMode loads the file → LineFlow.
##      The explicit edges (per source, in order) and LineFlow's whole edge set
##      must be identical by name before and after; no edge may cross from one
##      3A build to the other; line_3c (authored graph) must stay unstamped.
##   B  in the RELOADED world, the silo chain of lines 1, 3A (both) and 3B is
##      wired by name, and 950 kg/h fed at the silo's feeder reaches the NAMED
##      extruder without circulating (test_extruder_silo_chain's F checks).
##   C  a PARTIAL line and an operator delta. line_3b's extruder is jogged
##      3 m through LineMacroStore (in memory only), then three machines are
##      deleted through BuildMode's own delete path: 3B's extruder_silo (a
##      pinned main), line 1's L-stream blower (mid-train), 3A's rondmeng ring
##      (the recirc chain's last member). After a reload the explicit edges
##      must be the full line's edges MINUS those that touch a deleted machine
##      — nothing rewired around a hole — and the jogged extruder keeps its pin.
##      And the reload must give the world the LIVE session had after the same
##      deletes: explicit state per source and LineFlow's whole edge set equal,
##      and a machine whose only pinned target was deleted stays a dead end
##      (explicit, no edge), not a job for the geometry fallback.
##   D  saves the load must REFUSE rather than guess: two 3A builds without
##      macro_instance (a pre-2026-09-25 save), a 3B entry whose id no longer
##      matches the SEQ, a macro_index past the SEQ's end. A refused line gets
##      no edge at all; a single legacy copy (line 1 without macro_instance)
##      is still re-derived.
##   Z  the slot files are gone, the override is restored, the leak guard,
##      and every phase ran to its LAST line (Z3). Added 2026-09-25: a failed
##      save made phase D die on a runtime error, and the suite still printed
##      PASS with 51 of its 60 checks (docs/audit/aborted_phase_guard_2026-09-25.md).
##
## ISOLATION. Everything goes to this suite's OWN slot (FACTORY_PATH); both
## WorldLayout.layout_path_override and every BuildMode.layout_path are set
## before any BuildMode boots; load_shared_structure and allow_legacy_fallback
## are off, so WorldLayout is never saved and the operator's legacy factory is
## never read. LEAK GUARD checks md5 every operator file this could reach, before
## and after. The LineMacroStore delta is written into its in-memory cache and
## put back; user://macros is never written.

const FACTORY_PATH : String = "user://__macroedgesrt___factory.json"
const WORLD_PATH   : String = "user://__macroedgesrt___world_layout.json"

const FEED_KG_H  : float = 950.0
# Measured 2026-09-25 (test_extruder_silo_chain): the first kg reaches the
# extruder 19.6-27.4 s after feeding starts, ~15 s of it pipe transit.
const FEED_S     : float = 90.0
const DRAIN_S    : float = 45.0
const REACH_FRAC : float = 0.5
const CIRC_FRAC  : float = 1.05
const WATCHDOG_MS : int = 600000

const JOG_DZ_M : float = 3.0          # phase C: line_3b's extruder, along the line

# Far apart (MAX_LINK_DIST is 14 m) so no two lines can cross-wire.
const WORLD_A : Array = [
	{"line": "line_1",           "origin": Vector3(0.0, 0.0, 0.0)},
	{"line": "line_3a",          "origin": Vector3(400.0, 0.0, 0.0)},
	{"line": "line_3b",          "origin": Vector3(800.0, 0.0, 0.0)},
	{"line": "line_intake_3a3b", "origin": Vector3(1200.0, 0.0, 0.0)},
	{"line": "line_sort",        "origin": Vector3(1600.0, 0.0, 0.0)},
	{"line": "line_intake_3c6",  "origin": Vector3(2000.0, 0.0, 0.0)},
	{"line": "line_3c",          "origin": Vector3(2400.0, 0.0, 0.0)},
	{"line": "line_3a",          "origin": Vector3(2800.0, 0.0, 0.0)},
]
const WORLD_C : Array = [
	{"line": "line_1",  "origin": Vector3(0.0, 0.0, 0.0)},
	{"line": "line_3a", "origin": Vector3(400.0, 0.0, 0.0)},
	{"line": "line_3b", "origin": Vector3(800.0, 0.0, 0.0)},
]
# The silo chains measured in B: [macro_id, instance ordinal, feeder id, extruder id].
const CHAINS : Array = [
	["line_1",  0, "cyclone", "extruder_1"],
	["line_3a", 0, "blower",  "extruder_3a"],
	["line_3a", 1, "blower",  "extruder_3a"],
	["line_3b", 0, "blower",  "extruder_3b"],
]

var _ok : int = 0
var _fails : int = 0
var _t0 : int = 0
var _done : bool = false
var _prev_override : String = ""
var _guard_before : Dictionary = {}
var _macro_store_prev : Dictionary = {}   # LineMacroStore._cache as it was, restored in _cleanup
var _diag_built : Dictionary = {}         # source label → its fallback candidates in the BUILT world
var _gap_const_3b : float = 0.0           # 3B band → extruder along the line, const SEQ (phase A)
# Phases that ran to their LAST line. A runtime error aborts only the function it
# hits: `await _phase_d()` then returns as if D were done, _run goes on to
# _finish, and the suite used to print PASS without D's checks (2026-09-25, a
# full C: drive: `PASS (51 ok)` instead of 60). _finish asserts every phase here.
const PHASES : Array = ["A", "B", "C", "D"]
var _phases_done : Dictionary = {}

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_ok += 1
	else:
		_fails += 1

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

## Hang guard: `_run` awaits, so a SCRIPT ERROR after an await would otherwise
## leave headless Godot idling with no verdict (CLAUDE.md, 2026-09-22 trap).
func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > WATCHDOG_MS:
		_done = true
		_cleanup()
		print("Result: FAIL (watchdog — no verdict after %d s)" % (WATCHDOG_MS / 1000))
		get_tree().quit(2)

# ── isolation ────────────────────────────────────────────────────────────────

## Every operator file this suite could conceivably reach. A path that does not
## exist hashes as "absent", so a file that APPEARS is caught too.
func _guard_paths() -> Array:
	var out : Array = []
	for base in ["user://world_layout.json", "user://factory_layout.json",
			"user://sandbox_layout.json", "user://gauntlet_layout.json"]:
		for suf in ["", ".bak", ".tmp"]:
			out.append(String(base) + String(suf))
	for dir_path in ["user://macros", "user://saves"]:
		var d := DirAccess.open(dir_path)
		if d == null:
			out.append(dir_path + "/<dir>")
			continue
		for f in d.get_files():
			out.append("%s/%s" % [dir_path, f])
	return out

func _guard_snapshot() -> Dictionary:
	var snap : Dictionary = {}
	for p in _guard_paths():
		var ps : String = p
		if ps.ends_with("/<dir>"):
			snap[ps] = "absent-dir" if DirAccess.open(ps.trim_suffix("/<dir>")) == null else "dir"
		elif FileAccess.file_exists(ps):
			snap[ps] = FileAccess.get_md5(ps)
		else:
			snap[ps] = "absent"
	return snap

func _new_build_mode() -> BuildMode:
	var bm := BuildMode.new()
	bm.layout_path = FACTORY_PATH          # BEFORE add_child: _ready → load_layout()
	bm.load_shared_structure = false       # never WorldLayout.save(), never the site doors
	bm.allow_legacy_fallback = false       # never read the operator's factory_layout.json
	add_child(bm)
	return bm

func _placed_root(bm: BuildMode) -> Node3D:
	return bm.get("_placed_root") as Node3D

## BuildMode's per-load report; [] when this BuildMode has none (a reverted
## tree, as in the mutation runs), so the checks go red instead of the suite
## dying on a null.
func _rederive_report(bm: BuildMode) -> Array:
	var v : Variant = bm.get("last_macro_rederive")
	return v if v is Array else []

func _cleanup() -> void:
	AtomicFile.delete(FACTORY_PATH)
	AtomicFile.delete(WORLD_PATH)
	var ms : Node = get_node_or_null("/root/LineMacroStore")
	if ms != null:
		var cache : Dictionary = ms.get("_cache")
		cache.clear()
		cache.merge(_macro_store_prev)
	WorldLayout.layout_path_override = _prev_override

# ── naming ───────────────────────────────────────────────────────────────────

## macro_instance → ordinal, per macro_id, in scene order: "the first 3A built"
## is #0 in the built world and in the reloaded one (save and load keep order).
func _instance_ordinals(bm: BuildMode) -> Dictionary:
	var out : Dictionary = {}
	var per_mid : Dictionary = {}
	for c in _placed_root(bm).get_children():
		if not c.has_meta("macro_id"):
			continue
		var key : String = "%s|%s" % [String(c.get_meta("macro_id")), String(c.get_meta("macro_instance", ""))]
		if out.has(key):
			continue
		var mid : String = String(c.get_meta("macro_id"))
		out[key] = int(per_mid.get(mid, 0))
		per_mid[mid] = int(per_mid.get(mid, 0)) + 1
	return out

func _label(n: Node, ords: Dictionary) -> String:
	if n == null:
		return "<null>"
	if not n.has_meta("macro_id"):
		return String(n.name)
	var mid : String = String(n.get_meta("macro_id"))
	var key : String = "%s|%s" % [mid, String(n.get_meta("macro_instance", ""))]
	return "%s#%d[%d]%s" % [mid, int(ords.get(key, -1)), int(n.get_meta("macro_index", -1)),
		String(n.get_meta("placeable_id", "?"))]

## Every explicit edge in the world, one string per SOURCE with its targets in
## stamped order, sorted by source. Targets whose path no longer resolves (a
## live delete leaves those behind) are dropped and counted.
func _explicit_by_name(bm: BuildMode) -> Dictionary:
	var ords := _instance_ordinals(bm)
	var rows : Array = []
	var edges : Array = []
	var tagged : int = 0
	var dangling : int = 0
	var cross : Array = []
	for c in _placed_root(bm).get_children():
		if not c.has_meta("lf_explicit_outs"):
			continue
		var outs : Array = c.get_meta("lf_explicit_outs")
		if outs.is_empty():
			continue
		tagged += 1
		var tl : Array = []
		for o in outs:
			var t : Node = get_node_or_null((o as Dictionary).get("path", NodePath("")))
			if t == null:
				dangling += 1
				continue
			var s : String = "%s%s" % [_label(t, ords), " (recirc)" if bool((o as Dictionary).get("recirc", false)) else ""]
			tl.append(s)
			edges.append("%s -> %s" % [_label(c, ords), s])
			if String(t.get_meta("macro_instance", "")) != String(c.get_meta("macro_instance", "")) \
					or String(t.get_meta("macro_id", "")) != String(c.get_meta("macro_id", "")):
				cross.append("%s -> %s" % [_label(c, ords), _label(t, ords)])
		rows.append("%s -> %s" % [_label(c, ords), str(tl)])
	rows.sort()
	edges.sort()
	return {"rows": rows, "edges": edges, "tagged": tagged, "dangling": dangling, "cross": cross}

## LineFlow's whole edge set by name (explicit AND geometry), sorted.
func _lineflow_by_name(bm: BuildMode, lf: LineFlow) -> Array:
	var ords := _instance_ordinals(bm)
	var nodes : Array = lf.get("_nodes")
	var out : Array = []
	for e in lf.get("_edges"):
		var a : Node = (nodes[int((e as Dictionary)["a"])] as Dictionary).get("node") as Node
		var b : Node = (nodes[int((e as Dictionary)["b"])] as Dictionary).get("node") as Node
		out.append("%s -> %s%s" % [_label(a, ords), _label(b, ords),
			" (recirc)" if bool((e as Dictionary).get("recirc", false)) else ""])
	out.sort()
	return out

func _diff(a: Array, b: Array, cap: int = 12) -> String:
	var only_a : Array = []
	var only_b : Array = []
	for x in a:
		if not b.has(x):
			only_a.append(x)
	for y in b:
		if not a.has(y):
			only_b.append(y)
	return "only before %s%s | only after %s%s" % [str(only_a.slice(0, cap)),
		" …" if only_a.size() > cap else "", str(only_b.slice(0, cap)), " …" if only_b.size() > cap else ""]

func _count_prefix(arr: Array, prefix: String) -> int:
	var n : int = 0
	for s in arr:
		if String(s).begins_with(prefix):
			n += 1
	return n

func _seq_of(line_id: String) -> Array:
	match line_id:
		"line_1":  return BuildMode.LINE_1_SEQ
		"line_3a": return BuildMode.LINE_3A_SEQ
		"line_3b": return BuildMode.LINE_3B_SEQ
	return []

func _seq_index(seq: Array, id: String, from: int = 0) -> int:
	for k in range(from, seq.size()):
		if String((seq[k] as Dictionary).get("id", "")) == id:
			return k
	return -1

func _find(bm: BuildMode, mid: String, ordinal: int, idx: int) -> Node3D:
	var ords := _instance_ordinals(bm)
	for c in _placed_root(bm).get_children():
		if not c.has_meta("macro_id") or String(c.get_meta("macro_id")) != mid:
			continue
		if int(c.get_meta("macro_index", -1)) != idx:
			continue
		var key : String = "%s|%s" % [mid, String(c.get_meta("macro_instance", ""))]
		if int(ords.get(key, -1)) == ordinal:
			return c as Node3D
	return null

func _members(bm: BuildMode) -> Dictionary:
	var ords := _instance_ordinals(bm)
	var out : Dictionary = {}
	for c in _placed_root(bm).get_children():
		if not c.has_meta("macro_id"):
			continue
		var key : String = "%s|%s" % [String(c.get_meta("macro_id")), String(c.get_meta("macro_instance", ""))]
		var lab : String = "%s#%d" % [String(c.get_meta("macro_id")), int(ords.get(key, -1))]
		out[lab] = int(out.get(lab, 0)) + 1
	return out

func _boot_lineflow() -> LineFlow:
	var lf := LineFlow.new()
	add_child(lf)
	lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	return lf

## queue_free only. remove_child first would take the extruder brains out of
## the tree while SimTick still ticks them for the rest of the frame, and
## ExtruderMachine._resolve_lazy_dependencies then calls get_tree() on null
## (measured: 60 SCRIPT ERROR lines in the first run of this suite).
func _free(n: Node) -> void:
	if n != null and is_instance_valid(n):
		n.queue_free()

## Every phase starts from an empty slot, so no phase boots on another's world.
func _fresh_slot() -> void:
	AtomicFile.delete(FACTORY_PATH)
	AtomicFile.delete(WORLD_PATH)

## The geometry fallback's view of one source, for a failing A11: its nearest
## inlets by distance, as LineFlow._link_best_target sorts them.
func _candidates(bm: BuildMode, lf: LineFlow, src_label: String, k: int = 3) -> String:
	var ords := _instance_ordinals(bm)
	var nodes : Array = lf.get("_nodes")
	var src : int = -1
	for i in nodes.size():
		if _label((nodes[i] as Dictionary).get("node") as Node, ords) == src_label:
			src = i
	if src < 0:
		return "%s: not a LineFlow node" % src_label
	var wout : Vector3 = (nodes[src] as Dictionary)["wout"]
	var c : Array = []
	for j in nodes.size():
		if j != src:
			c.append([wout.distance_to((nodes[j] as Dictionary)["win"] as Vector3), j])
	c.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
	var parts : Array = []
	for q in mini(k, c.size()):
		var n3 : Node3D = (nodes[int(c[q][1])] as Dictionary).get("node") as Node3D
		parts.append("%s %.9f m @%s" % [_label(n3, ords), float(c[q][0]),
			str(n3.global_position) if n3 != null else "?"])
	return "%s wout %s → %s" % [src_label, str(wout), ", ".join(parts)]

# ── the run ──────────────────────────────────────────────────────────────────

func _run() -> void:
	print("[TEST] macro edges reload — explicit flow edges survive save → load, by name and by kg")
	_guard_before = _guard_snapshot()
	_prev_override = WorldLayout.layout_path_override
	WorldLayout.layout_path_override = WORLD_PATH
	AtomicFile.delete(FACTORY_PATH)       # residue of a killed run
	AtomicFile.delete(WORLD_PATH)
	# Build every line from the const SEQ: the operator's own user://macros jogs
	# live in LineMacroStore's in-memory cache, which is blanked here (and put
	# back in _cleanup) — never written to disk.
	var ms : Node = get_node_or_null("/root/LineMacroStore")
	var cache : Dictionary = ms.get("_cache") if ms != null else {}
	_macro_store_prev = cache.duplicate(true)
	for mid in LineMacroStore.MACRO_IDS:
		cache[mid] = {}
	_check(ms != null, "S0 LineMacroStore autoload present (phase C jogs through it)")
	# A floor under every line. Measured without one (first run, 2026-09-25):
	# each line's "achter" lump_cart has nothing under it and FALLS — y -0.65 m
	# at the built world's LineFlow rebuild, -1.29 m at the reloaded one — so
	# the laser filter's geometry fallback picked the other cart after the
	# reload (1.974 m vs 2.007 m before, 2.089 m vs 2.007 m after). That is a
	# void, not a save → load defect; the plant has a floor, and so does this.
	var floor_body := StaticBody3D.new()
	floor_body.name = "TestFloor"
	var floor_cs := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(8000.0, 1.0, 4000.0)
	floor_cs.shape = floor_box
	floor_body.add_child(floor_cs)
	floor_body.position = Vector3(1400.0, -0.5, 0.0)
	add_child(floor_body)

	await _phase_a_b()
	await _phase_c()
	await _phase_d()
	_finish()

# ── A + B ────────────────────────────────────────────────────────────────────

func _phase_a_b() -> void:
	print("  -- A: every macro (+ a second line_3a) — build, save, reload --")
	_fresh_slot()
	var bm1 := _new_build_mode()
	await get_tree().process_frame
	_check(_placed_root(bm1).get_child_count() == 0, "A0 the suite's slot starts empty (%d placed)" % _placed_root(bm1).get_child_count())
	for spec in WORLD_A:
		bm1.call("_build_full_line", String(spec["line"]), spec["origin"] as Vector3, 0.0)
	await get_tree().process_frame
	var lf1 : LineFlow = await _boot_lineflow()
	var ex1 := _explicit_by_name(bm1)
	var lfe1 := _lineflow_by_name(bm1, lf1)
	var mem1 := _members(bm1)
	var n_nodes1 : int = (lf1.get("_nodes") as Array).size()
	_diag_built.clear()
	for s in lfe1:
		var src_lab : String = String(s).split(" -> ")[0]
		if not _diag_built.has(src_lab):
			_diag_built[src_lab] = _candidates(bm1, lf1, src_lab)
	# The const-SEQ spacing of 3B's band → extruder, for phase C's jog check.
	var s3 : Array = BuildMode.LINE_3B_SEQ
	var b0 := _find(bm1, "line_3b", 0, _seq_index(s3, "compactorband", _seq_index(s3, "extruder_silo")))
	var e0 := _find(bm1, "line_3b", 0, _seq_index(s3, "extruder_3b"))
	_gap_const_3b = (b0.global_position - e0.global_position).z if b0 != null and e0 != null else 0.0
	print("  info  : BUILT    %d LineFlow nodes, %d edges, %d explicit edges from %d tagged nodes, members %s"
		% [n_nodes1, lfe1.size(), ex1["edges"].size(), int(ex1["tagged"]), str(mem1)])
	bm1.call("_save_layout")
	var saved : Variant = AtomicFile.read_json(FACTORY_PATH, TYPE_ARRAY)
	var saved_macro : int = 0
	var saved_inst : int = 0
	if saved is Array:
		for e in saved:
			if e is Dictionary and (e as Dictionary).has("macro_id"):
				saved_macro += 1
				if (e as Dictionary).has("macro_instance"):
					saved_inst += 1
	var built_macro : int = 0
	for v in mem1.values():
		built_macro += int(v)
	_check(saved_macro == built_macro and built_macro > 0,
		"A1 the save holds every macro machine (%d of %d) in the suite's own slot" % [saved_macro, built_macro])
	_check(saved_inst == saved_macro, "A2 every saved macro machine carries macro_instance (%d of %d)" % [saved_inst, saved_macro])
	_free(lf1)
	_free(bm1)
	await get_tree().process_frame
	await get_tree().process_frame

	var bm2 := _new_build_mode()          # _ready → load_layout → re-derive
	await get_tree().process_frame
	var rep : Array = _rederive_report(bm2)
	var lf2 : LineFlow = await _boot_lineflow()
	var ex2 := _explicit_by_name(bm2)
	var lfe2 := _lineflow_by_name(bm2, lf2)
	var mem2 := _members(bm2)
	print("  info  : RELOADED %d LineFlow nodes, %d edges, %d explicit edges from %d tagged nodes, members %s"
		% [(lf2.get("_nodes") as Array).size(), lfe2.size(), ex2["edges"].size(), int(ex2["tagged"]), str(mem2)])
	_check(mem2 == mem1, "A3 every macro instance reloads whole — %s" % str(mem2))
	var statuses : Array = []
	var all_ok : bool = rep.size() == WORLD_A.size()
	for r in rep:
		var rd : Dictionary = r
		statuses.append("%s %s %d/%d" % [rd["macro_id"], rd["status"], int(rd["members"]), int(rd["seq_size"])])
		var want : String = "authored" if String(rd["macro_id"]) == "line_3c" else "stamped"
		if String(rd["status"]) != want:
			all_ok = false
	_check(all_ok, "A4 load re-derived every group (3C authored, the rest stamped): %s" % str(statuses))
	_check(ex1["edges"].size() > 0 and _count_prefix(ex1["edges"], "line_3a#1") > 0,
		"A5 anti-vacuity: the built world HAS explicit edges (%d, of which the second 3A %d)"
		% [ex1["edges"].size(), _count_prefix(ex1["edges"], "line_3a#1")])
	_check(ex2["rows"] == ex1["rows"],
		"A6 explicit edges per source, in stamped order, identical after reload (%d sources) — %s"
		% [ex1["rows"].size(), "same" if ex2["rows"] == ex1["rows"] else _diff(ex1["rows"], ex2["rows"])])
	for mid in ["line_1", "line_3a#0", "line_3a#1", "line_3b", "line_intake_3a3b", "line_sort", "line_intake_3c6"]:
		print("  info  : %-18s %3d explicit edges built, %3d reloaded" % [mid,
			_count_prefix(ex1["edges"], mid), _count_prefix(ex2["edges"], mid)])
	_check(_count_prefix(ex1["edges"], "line_3c") == 0 and _count_prefix(ex2["edges"], "line_3c") == 0,
		"A7 line_3c (GRAPH_TOPOLOGY_MACROS) carries no explicit edge, built or reloaded")
	_check((ex1["cross"] as Array).is_empty() and (ex2["cross"] as Array).is_empty(),
		"A8 no explicit edge crosses from one build to another — built %s, reloaded %s"
		% [str(ex1["cross"]), str(ex2["cross"])])
	_check(int(ex2["dangling"]) == 0, "A9 every re-derived path resolves (%d dangling)" % int(ex2["dangling"]))
	_check((lf2.get("_nodes") as Array).size() == n_nodes1,
		"A10 LineFlow discovers the same machines (%d built, %d reloaded)" % [n_nodes1, (lf2.get("_nodes") as Array).size()])
	_check(lfe2 == lfe1, "A11 LineFlow's WHOLE edge set is identical by name after reload (%d edges) — %s"
		% [lfe1.size(), "same" if lfe2 == lfe1 else _diff(lfe1, lfe2)])
	if lfe2 != lfe1:
		for s in lfe1:
			if not lfe2.has(s):
				var src_lab : String = String(s).split(" -> ")[0]
				print("  why   : BUILT    %s" % String(_diag_built.get(src_lab, "?")))
				print("  why   : RELOADED %s" % _candidates(bm2, lf2, src_lab))

	await _phase_b(bm2, lf2)
	_free(lf2)
	_free(bm2)
	await get_tree().process_frame
	await get_tree().process_frame
	_phases_done["A"] = true

func _phase_b(bm: BuildMode, lf: LineFlow) -> void:
	print("  -- B: the reloaded world's silo chains, by name and by kg --")
	var ords := _instance_ordinals(bm)
	var nodes : Array = lf.get("_nodes")
	var idx_of : Dictionary = {}          # Node → LineFlow index
	for i in nodes.size():
		var n3 = (nodes[i] as Dictionary).get("node")
		if n3 != null and is_instance_valid(n3):
			idx_of[n3] = i
	var outs : Dictionary = {}
	var ins : Dictionary = {}
	for e in lf.get("_edges"):
		var a : int = int((e as Dictionary)["a"])
		var b : int = int((e as Dictionary)["b"])
		outs[a] = (outs.get(a, []) as Array) + [b]
		ins[b] = (ins.get(b, []) as Array) + [a]
	var lab := func(i: int) -> String:
		return _label((nodes[i] as Dictionary).get("node") as Node, ords) if i >= 0 else "<none>"
	var chains : Array = []
	for spec in CHAINS:
		var mid : String = spec[0]
		var ordn : int = spec[1]
		var seq : Array = _seq_of(mid)
		var mi_silo : int = _seq_index(seq, "extruder_silo")
		var mi_band : int = _seq_index(seq, "compactorband", maxi(mi_silo, 0))
		var mi_ex : int = _seq_index(seq, String(spec[3]))
		var tag : String = "%s#%d" % [mid, ordn]
		var ns : Array = []
		for mi in [mi_silo - 1, mi_silo, mi_band, mi_ex]:
			var n3 := _find(bm, mid, ordn, mi)
			ns.append(int(idx_of.get(n3, -1)) if n3 != null else -1)
		var resolved : bool = not ns.has(-1) and mi_silo > 0 \
			and String((seq[mi_silo - 1] as Dictionary).get("id", "")) == String(spec[2])
		_check(resolved, "B0 %s: feeder '%s', silo, band and %s are LineFlow nodes" % [tag, spec[2], spec[3]])
		if not resolved:
			continue
		var up : int = ns[0]
		var silo : int = ns[1]
		var band : int = ns[2]
		var ex : int = ns[3]
		_check(outs.get(up, []) == [silo] and ins.get(silo, []) == [up],
			"B1 %s: %s feeds ONLY the silo, and nothing else feeds it — out %s, silo in %s"
			% [tag, lab.call(up), str((outs.get(up, []) as Array).map(lab)), str((ins.get(silo, []) as Array).map(lab))])
		_check(outs.get(silo, []) == [band] and outs.get(band, []) == [ex] and ins.get(ex, []) == [band],
			"B2 %s: silo → band → %s, exactly — silo out %s, band out %s, extruder in %s"
			% [tag, spec[3], str((outs.get(silo, []) as Array).map(lab)), str((outs.get(band, []) as Array).map(lab)),
				str((ins.get(ex, []) as Array).map(lab))])
		chains.append({"tag": tag, "up": up, "silo": silo, "band": band, "ex": ex})
	_check(chains.size() == CHAINS.size(), "B3 all %d chains resolved (anti-vacuity)" % CHAINS.size())

	lf.call("start_line")
	var feed_kg_tick : float = FEED_KG_H / 3600.0 * 0.1
	var moved : Dictionary = {}
	for ch in chains:
		for key in ["up", "silo", "band", "ex"]:
			moved[int(ch[key])] = 0.0
	var fed : float = 0.0
	var feed_ticks : int = int(FEED_S / 0.1)
	var total_ticks : int = int((FEED_S + DRAIN_S) / 0.1)
	var t_wall : int = Time.get_ticks_msec()
	for t in total_ticks:
		if t < feed_ticks:
			for ch in chains:
				(((nodes[int(ch["up"])] as Dictionary)["in"]) as MaterialBatch).add(MaterialBatch.new(
					feed_kg_tick, feed_kg_tick / LineFlow.FEED_DENSITY,
					LineFlow.DEFAULT_COMP.duplicate(), "macro_edges_reload", 0.0, 0.0))
			fed += feed_kg_tick
		lf.call("tick", 0.1)
		for i in moved.keys():
			moved[i] = float(moved[i]) + float((nodes[int(i)] as Dictionary).get("_moved_kg", 0.0))
	print("  info  : %d ticks (%.0f s sim) in %.1f s wall; fed %.1f kg into each chain's feeder"
		% [total_ticks, FEED_S + DRAIN_S, (Time.get_ticks_msec() - t_wall) / 1000.0, fed])
	for ch in chains:
		var got : Dictionary = {}
		var worst : float = 0.0
		for key in ["up", "silo", "band", "ex"]:
			var i : int = int(ch[key])
			var bin : MaterialBatch = (nodes[i] as Dictionary).get("in", null) as MaterialBatch
			got[key] = float(moved[i]) + (bin.mass_kg if bin != null else 0.0)
			worst = maxf(worst, float(moved[i]))
		_check(float(got["ex"]) >= REACH_FRAC * fed,
			"B4 %s: the fed kg reach the extruder by name after a reload (silo %.1f, band %.1f, extruder %.1f of %.1f kg)"
			% [ch["tag"], float(got["silo"]), float(got["band"]), float(got["ex"]), fed])
		_check(worst <= CIRC_FRAC * fed,
			"B5 %s: nothing circulates — no chain machine processed more than was fed (max %.1f of %.1f kg)"
			% [ch["tag"], worst, fed])
	_phases_done["B"] = true

# ── C: a partial line, and an operator jog ───────────────────────────────────

func _phase_c() -> void:
	print("  -- C: deleted machines and a LineMacroStore jog survive a reload as holes --")
	var seq3b : Array = BuildMode.LINE_3B_SEQ
	var seq1 : Array = BuildMode.LINE_1_SEQ
	var seq3a : Array = BuildMode.LINE_3A_SEQ
	var i3b_silo : int = _seq_index(seq3b, "extruder_silo")
	var i3b_band : int = _seq_index(seq3b, "compactorband", i3b_silo)
	var i3b_ex : int = _seq_index(seq3b, "extruder_3b")
	# line 1: the first L-stream blower — mid-train, fed by the L dryer and
	# feeding the L cyclone.
	var i1_blower : int = -1
	for k in seq1.size():
		var e : Dictionary = seq1[k]
		if String(e.get("id", "")) == "blower" and String(e.get("stream", "")) == "L":
			i1_blower = k
			break
	# 3A: the rondmeng chain, from its branch_recirc entry to its last
	# flow-relevant member (the ring); a role-none cabinet in it is not a member.
	var i3a_src : int = -1
	var i3a_chain : Array = []
	var probe_bm := BuildMode.new()       # _is_flow_relevant only; never entered into the tree
	for k in seq3a.size():
		var e : Dictionary = seq3a[k]
		if i3a_chain.is_empty():
			if bool(e.get("branch_recirc", false)):
				i3a_chain.append(k)
				for j in range(k - 1, -1, -1):
					if is_equal_approx(float((seq3a[j] as Dictionary).get("x", 0.0)), 0.0) \
							and probe_bm._is_flow_relevant(String((seq3a[j] as Dictionary).get("id", ""))):
						i3a_src = j
						break
		elif not is_equal_approx(float(e.get("x", 0.0)), 0.0):
			if probe_bm._is_flow_relevant(String(e.get("id", ""))):
				i3a_chain.append(k)
		else:
			break
	probe_bm.free()
	var i3a_ring : int = int(i3a_chain[i3a_chain.size() - 1]) if i3a_chain.size() >= 2 else -1
	var i3a_before_ring : int = int(i3a_chain[i3a_chain.size() - 2]) if i3a_chain.size() >= 2 else -1
	_check(i3b_silo > 0 and i1_blower > 0 and i3a_ring > 0 and i3a_src >= 0,
		"C0 targets found in the SEQs: 3B silo %d, line 1 L blower %d, 3A recirc %d → chain %s (ring %d)"
		% [i3b_silo, i1_blower, i3a_src, str(i3a_chain), i3a_ring])

	# The jog: exactly what save_macro_overrides would have written for
	# "extruder_3b moved JOG_DZ_M further down the line", kept in memory.
	var ms : Node = get_node_or_null("/root/LineMacroStore")
	var cache : Dictionary = ms.get("_cache") if ms != null else {}
	cache["line_3b"] = {"version": 1, "macro_id": "line_3b", "deltas": {
		str(i3b_ex): {"dx": 0.0, "dy": 0.0, "dz": JOG_DZ_M, "drot_y": 0.0, "scale": [1.0, 1.0, 1.0]}}}
	_fresh_slot()
	var bm3 := _new_build_mode()
	await get_tree().process_frame
	_check(_placed_root(bm3).get_child_count() == 0, "C-1 phase C starts on an empty slot (%d placed)" % _placed_root(bm3).get_child_count())
	for spec in WORLD_C:
		bm3.call("_build_full_line", String(spec["line"]), spec["origin"] as Vector3, 0.0)
	cache["line_3b"] = {}                 # the jog is baked into the placed poses now
	await get_tree().process_frame
	var band3 := _find(bm3, "line_3b", 0, i3b_band)
	var ex3 := _find(bm3, "line_3b", 0, i3b_ex)
	var gap_jogged : float = (band3.global_position - ex3.global_position).z if band3 != null and ex3 != null else 0.0
	var full := _explicit_by_name(bm3)
	var ords := _instance_ordinals(bm3)
	var silo_lab : String = _label(_find(bm3, "line_3b", 0, i3b_silo), ords)
	var blower_lab : String = _label(_find(bm3, "line_1", 0, i1_blower), ords)
	var ring_lab : String = _label(_find(bm3, "line_3a", 0, i3a_ring), ords)
	var deleted : Array = [silo_lab, blower_lab, ring_lab]
	for trio in [["line_3b", i3b_silo], ["line_1", i1_blower], ["line_3a", i3a_ring]]:
		var n3 := _find(bm3, String(trio[0]), 0, int(trio[1]))
		if n3 != null:
			bm3.set("_edit_selected", n3)
			bm3.call("_edit_delete_selected")   # production path; it saves to our slot
	await get_tree().process_frame
	var live := _explicit_by_name(bm3)
	var expected : Array = []
	for s in full["edges"]:
		var touches : bool = false
		for d in deleted:
			if String(s).begins_with(String(d) + " ") or String(s).contains("-> " + String(d)):
				touches = true
		if not touches:
			expected.append(s)
	_check(expected.size() < (full["edges"] as Array).size() and expected.size() > 0,
		"C1 anti-vacuity: the three deletions touch %d of %d explicit edges"
		% [(full["edges"] as Array).size() - expected.size(), (full["edges"] as Array).size()])
	_check(live["edges"] == expected,
		"C2 in the live session the deletions left exactly the other edges — %s"
		% ("same" if live["edges"] == expected else _diff(expected, live["edges"])))
	var lf3 : LineFlow = await _boot_lineflow()
	var lfe3 := _lineflow_by_name(bm3, lf3)
	_free(lf3)
	_free(bm3)
	await get_tree().process_frame
	await get_tree().process_frame

	var bm4 := _new_build_mode()
	await get_tree().process_frame
	var rep : Array = _rederive_report(bm4)
	var stat : Array = []
	var stamped3 : int = 0
	for r in rep:
		var rd : Dictionary = r
		stat.append("%s %s %d/%d" % [rd["macro_id"], rd["status"], int(rd["members"]), int(rd["seq_size"])])
		if String(rd["status"]) == "stamped":
			stamped3 += 1
	_check(stamped3 == 3, "C3 a partial line is re-derived, not refused: %s" % str(stat))
	var back := _explicit_by_name(bm4)
	var lf4 : LineFlow = await _boot_lineflow()
	var lfe4 := _lineflow_by_name(bm4, lf4)
	_free(lf4)
	_check(back["edges"] == expected,
		"C4 after the reload: the full line's edges minus those touching a deleted machine (%d) — %s"
		% [expected.size(), "same" if back["edges"] == expected else _diff(expected, back["edges"])])
	# The reload must give the world the live session had after the same
	# deletes — dead ends included (a source whose pinned target was deleted
	# keeps its explicit status and gets NO edge, not the geometry fallback).
	_check(back["rows"] == live["rows"],
		"C4b explicit state per source, dead ends included, equals the live session's (%d sources) — %s"
		% [(live["rows"] as Array).size(), "same" if back["rows"] == live["rows"] else _diff(live["rows"], back["rows"])])
	_check(lfe4 == lfe3 and not lfe3.is_empty(),
		"C4c LineFlow's whole edge set equals the live session's after the deletes (%d edges) — %s"
		% [lfe3.size(), "same" if lfe4 == lfe3 else _diff(lfe3, lfe4)])
	var ords4 := _instance_ordinals(bm4)
	# The holes, named: nothing may be rewired AROUND them.
	var l_dryer : String = ""
	var l_cyclone : String = ""
	for k in range(i1_blower - 1, -1, -1):
		if String((seq1[k] as Dictionary).get("stream", "")) == "L":
			l_dryer = _label(_find(bm4, "line_1", 0, k), ords4)
			break
	for k in range(i1_blower + 1, seq1.size()):
		if String((seq1[k] as Dictionary).get("stream", "")) == "L":
			l_cyclone = _label(_find(bm4, "line_1", 0, k), ords4)
			break
	var heal : Array = []
	for s in back["edges"]:
		var st : String = s
		if st.begins_with(l_dryer + " ") and st.contains("-> " + l_cyclone):
			heal.append(st)
		if st.begins_with(_label(_find(bm4, "line_3b", 0, i3b_silo - 1), ords4) + " ") \
				and st.contains("-> " + _label(_find(bm4, "line_3b", 0, i3b_band), ords4)):
			heal.append(st)
		if st.begins_with(_label(_find(bm4, "line_3a", 0, i3a_before_ring), ords4) + " ") and st.contains("(recirc)"):
			heal.append(st)
	_check(heal.is_empty() and l_dryer != "" and l_cyclone != "",
		"C5 no edge rewired around a hole (L dryer → L cyclone, 3B feeder → band, recirc from the member before the ring): %s"
		% str(heal))
	# The two machines whose ONLY pinned target was deleted are dead ends, by
	# name: explicit, with no target left.
	var feeder3b : String = _label(_find(bm4, "line_3b", 0, i3b_silo - 1), ords4)
	var dead : Array = []
	for want in [l_dryer, feeder3b]:
		if (back["rows"] as Array).has("%s -> []" % want):
			dead.append(want)
	_check(dead.size() == 2, "C5b the L dryer and 3B's silo feeder stay explicit dead ends after the reload: %s" % str(dead))
	var src_lab : String = _label(_find(bm4, "line_3a", 0, i3a_src), ords4)
	var src_keeps_main : bool = false
	for s in back["edges"]:
		if String(s).begins_with(src_lab + " ") and not String(s).contains("(recirc)") \
				and not String(s).contains("[%d]" % int(i3a_chain[0])):
			src_keeps_main = true
	_check(src_keeps_main, "C6 3A: the recirc source (%s) still feeds the next main with its ring gone" % src_lab)
	var band4 := _find(bm4, "line_3b", 0, i3b_band)
	var ex4 := _find(bm4, "line_3b", 0, i3b_ex)
	var pin : String = "%s -> %s" % [_label(band4, ords4), _label(ex4, ords4)]
	_check((back["edges"] as Array).has(pin),
		"C7 the jogged extruder keeps its pin through a reload: %s" % pin)
	var gap_reloaded : float = (band4.global_position - ex4.global_position).z if band4 != null and ex4 != null else 0.0
	_check(absf(gap_reloaded - gap_jogged) < 0.01,
		"C8 the jog round-trips with the pose (band→extruder %.2f m built, %.2f m reloaded)" % [gap_jogged, gap_reloaded])
	# Anti-vacuity for the jog: against the same line built from the const SEQ
	# in phase A, the extruder really moved JOG_DZ_M further down the line.
	_check(absf((gap_jogged - _gap_const_3b) - JOG_DZ_M) < 0.01,
		"C9 anti-vacuity: the jog really moved the extruder %.2f m down the line (%.2f jogged vs %.2f const)"
		% [gap_jogged - _gap_const_3b, gap_jogged, _gap_const_3b])
	_free(bm4)
	await get_tree().process_frame
	await get_tree().process_frame
	_phases_done["C"] = true

# ── D: saves the load must refuse ────────────────────────────────────────────

func _phase_d() -> void:
	print("  -- D: legacy and stale saves are refused, not guessed --")
	# A fresh world to craft from: lines 1, 3B, sort and two 3A builds.
	_fresh_slot()
	var bm6 := _new_build_mode()
	await get_tree().process_frame
	for spec in [["line_1", 0.0], ["line_3a", 400.0], ["line_3b", 800.0], ["line_sort", 1200.0], ["line_3a", 1600.0]]:
		bm6.call("_build_full_line", String(spec[0]), Vector3(float(spec[1]), 0.0, 0.0), 0.0)
	await get_tree().process_frame
	var ref := _explicit_by_name(bm6)
	bm6.call("_save_layout")
	_free(bm6)
	await get_tree().process_frame
	# The save must LAND before anything is crafted from it. _save_layout
	# returns nothing; a failed write (a full disk: AtomicFile "short write",
	# error 13) leaves no file, read_json returns null, and assigning that to a
	# typed Array was a runtime error that silently ended this phase.
	var raw : Variant = AtomicFile.read_json(FACTORY_PATH, TYPE_ARRAY)
	var n_raw : int = (raw as Array).size() if raw is Array else -1
	_check(n_raw > 1, "D-1 the build was saved to the suite's slot and reads back (%d entries)" % n_raw)
	if n_raw <= 1:
		return                             # nothing to craft from; Z3 names the unfinished phase
	var arr : Array = raw
	var i3b_silo : int = _seq_index(BuildMode.LINE_3B_SEQ, "extruder_silo")
	var sort_mid : int = -1
	for e in arr:
		if not (e is Dictionary):
			continue
		var d : Dictionary = e
		var mid : String = String(d.get("macro_id", ""))
		if mid == "line_3a" or mid == "line_1":
			d.erase("macro_instance")          # pre-2026-09-25 save: no instance key
		if mid == "line_3b" and int(d.get("macro_index", -1)) == i3b_silo:
			d["id"] = "mengsilo"               # the SEQ changed since the save
		if mid == "line_sort" and sort_mid < 0:
			sort_mid = int(d.get("macro_index", -1))
			d["macro_index"] = 999             # past the SEQ's end
	_check(AtomicFile.write_json(FACTORY_PATH, arr, "\t") == OK, "D0 crafted legacy/stale save written to the suite's slot")
	var bm7 := _new_build_mode()
	await get_tree().process_frame
	var rep : Array = _rederive_report(bm7)
	var by_mid : Dictionary = {}
	for r in rep:
		by_mid[String((r as Dictionary)["macro_id"])] = r
	var got := _explicit_by_name(bm7)
	for trio in [["line_3a", "two machines at index"], ["line_3b", "in the save and 'extruder_silo' in the SEQ"],
			["line_sort", "outside the"]]:
		var mid : String = trio[0]
		var rd : Dictionary = by_mid.get(mid, {})
		_check(String(rd.get("status", "")) == "refused" and String(rd.get("reason", "")).contains(String(trio[1])),
			"D1 %s refused: %s" % [mid, str(rd.get("reason", "<no report>"))])
		_check(_count_prefix(got["edges"], mid) == 0,
			"D2 %s: a refused line carries no explicit edge (%d)" % [mid, _count_prefix(got["edges"], mid)])
	var l1 : Dictionary = by_mid.get("line_1", {})
	_check(String(l1.get("status", "")) == "stamped", "D3 line 1 without macro_instance (one copy) is still re-derived: %s"
		% str(l1.get("status", "<no report>")))
	var l1_ref : Array = []
	var l1_got : Array = []
	for s in ref["edges"]:
		if String(s).begins_with("line_1"):
			l1_ref.append(s)
	for s in got["edges"]:
		if String(s).begins_with("line_1"):
			l1_got.append(s)
	_check(l1_got == l1_ref and not l1_ref.is_empty(),
		"D4 … with the same %d edges as when it was built — %s" % [l1_ref.size(), "same" if l1_got == l1_ref else _diff(l1_ref, l1_got)])
	_free(bm7)
	await get_tree().process_frame
	_phases_done["D"] = true

func _finish() -> void:
	_done = true
	_cleanup()
	_check(not AtomicFile.exists_any(FACTORY_PATH) and not AtomicFile.exists_any(WORLD_PATH),
		"Z0 the suite's slot files are removed")
	_check(WorldLayout.layout_path_override == _prev_override, "Z1 WorldLayout.layout_path_override restored")
	var after := _guard_snapshot()
	var changed : Array = []
	for k in after.keys():
		if String(_guard_before.get(k, "absent")) != String(after[k]):
			changed.append("%s %s→%s" % [k, _guard_before.get(k, "absent"), after[k]])
	for k in _guard_before.keys():
		if not after.has(k):
			changed.append("%s vanished" % k)
	_check(changed.is_empty(), "Z2 LEAK GUARD: %d operator files md5-identical before and after %s"
		% [after.size(), str(changed) if not changed.is_empty() else ""])
	var unfinished : Array = []
	for ph in PHASES:
		if not _phases_done.has(ph):
			unfinished.append(ph)
	_check(unfinished.is_empty(), "Z3 every phase ran to its end %s — a phase cut short by a runtime error is not a pass%s"
		% [str(PHASES), "" if unfinished.is_empty() else "; did not finish: %s (read the SCRIPT ERROR above)" % str(unfinished)])
	var verdict : String = "PASS" if _fails == 0 and _ok > 0 else "FAIL"
	print("[TEST] macro edges reload %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _ok, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
