extends Node
## PROBE (measures, gates nothing) — do a macro line's EXPLICIT flow edges
## survive a save → load round trip?
##
##   APPDATA=<scratch dir> godot --headless --path . res://src/tests/probe_explicit_edges_roundtrip.tscn
##
## RUN IT UNDER A SCRATCH APPDATA. It calls BuildMode._save_layout(), which
## writes the factory file AND pushes WorldLayout.save(). Both paths are also
## redirected to probe-only names below, as a second line of defence.
##
## Why: BuildMode stamps `lf_explicit_outs` only inside _build_full_line, and
## _save_layout persists macro_id / macro_index / macro_anchor but not that
## meta. If nothing re-stamps it on load, a reloaded world is wired by the
## geometry fallback alone. This builds lines 1, 3A and 3B, dumps each silo
## tail, saves, rebuilds a fresh BuildMode from the file, and dumps again.
## Measured 2026-09-25 before the fix: 47 tagged nodes → 0. load_layout now
## re-derives them (BuildMode._rederive_macro_flow_edges); the gated proof is
## test_macro_edges_reload, and this probe stays as the quick look.

const FACTORY_PATH : String = "user://__rt_probe_factory.json"
const WORLD_PATH   : String = "user://__rt_probe_world_layout.json"
const LINES : Array = [
	{"line": "line_1",  "origin": Vector3(0.0, 0.0, 0.0)},
	{"line": "line_3a", "origin": Vector3(400.0, 0.0, 0.0)},
	{"line": "line_3b", "origin": Vector3(800.0, 0.0, 0.0)},
]

var _t0 : int = 0
var _done : bool = false

func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	call_deferred("_run")

func _process(_d: float) -> void:
	if not _done and Time.get_ticks_msec() - _t0 > 180000:
		_done = true
		print("Result: FAIL (probe watchdog)")
		get_tree().quit(2)

func _report(tag: String, lf: LineFlow) -> void:
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var tagged := 0
	for nd in nodes:
		var n3 = (nd as Dictionary).get("node")
		if n3 != null and is_instance_valid(n3) and n3.has_meta("lf_explicit_outs") \
				and not (n3.get_meta("lf_explicit_outs") as Array).is_empty():
			tagged += 1
	print("[%s] %d nodes, %d edges, %d nodes carry lf_explicit_outs" % [tag, nodes.size(), edges.size(), tagged])
	for i in nodes.size():
		var id : String = String((nodes[i] as Dictionary).get("id", ""))
		if id != "extruder_silo" and id != "compactorband" and not (id.begins_with("extruder_") and id != "extruder_silo"):
			continue
		var n3 = (nodes[i] as Dictionary).get("node")
		var mid : String = String(n3.get_meta("macro_id", "?")) if n3 != null else "?"
		var ins : Array = []
		var outs : Array = []
		for e in edges:
			if int(e["b"]) == i:
				ins.append("%s#%d" % [(nodes[int(e["a"])] as Dictionary).get("id"), int(e["a"])])
			if int(e["a"]) == i:
				outs.append("%s#%d" % [(nodes[int(e["b"])] as Dictionary).get("id"), int(e["b"])])
		print("    %-8s %-15s #%-3d in %s  out %s" % [mid, id, i, str(ins), str(outs)])

func _run() -> void:
	print("[PROBE] user dir = %s" % OS.get_user_data_dir())
	WorldLayout.layout_path_override = WORLD_PATH
	var bm1 := BuildMode.new()
	bm1.layout_path = FACTORY_PATH
	add_child(bm1)
	await get_tree().process_frame
	for spec in LINES:
		bm1.call("_build_full_line", String(spec["line"]), spec["origin"] as Vector3, 0.0)
	await get_tree().process_frame
	var lf1 := LineFlow.new()
	add_child(lf1)
	await get_tree().process_frame
	lf1.call("rebuild")
	_report("BUILT", lf1)

	bm1.call("_save_layout")
	print("[PROBE] saved %s (exists: %s)" % [FACTORY_PATH, AtomicFile.exists_any(FACTORY_PATH)])
	lf1.queue_free()
	bm1.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame

	var bm2 := BuildMode.new()
	bm2.layout_path = FACTORY_PATH
	add_child(bm2)                      # _ready → load_layout()
	await get_tree().process_frame
	await get_tree().process_frame
	var lf2 := LineFlow.new()
	add_child(lf2)
	await get_tree().process_frame
	lf2.call("rebuild")
	_report("RELOADED", lf2)

	_done = true
	print("Result: PROBE DONE")
	get_tree().quit(0)
