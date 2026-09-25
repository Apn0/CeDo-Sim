extends Node
## PROBE (measures, gates nothing) — dump every macro's BUILT flow edges by name,
## so two versions of BuildMode can be diffed line for line.
##
##   godot --headless --path . res://src/tests/probe_macro_edges_dump.tscn > a.log
##   (swap BuildMode.gd)  … > b.log;   diff <(grep '^EDGE' a.log) <(grep '^EDGE' b.log)
##
## Written 2026-09-25 to prove that moving _build_full_line's branch / stream /
## recirc / explicit_from_prev bookkeeping out of the placement loop and into
## BuildMode.macro_flow_edges changed no edge: every macro is built once, 400 m
## apart on a floor, and the probe prints
##   EDGE X <src> -> [<targets in stamped order>]   one per lf_explicit_outs source
##   EDGE L <a> -> <b>                             every LineFlow edge
## with <node> = <macro_id>[<macro_index>]<placeable_id>. Writes nothing to
## user:// (a bare BuildMode never saves); run it under a scratch APPDATA anyway.

const LINES : Array = ["line_1", "line_3a", "line_3b", "line_intake_3a3b", "line_sort",
	"line_intake_3c6", "line_3c"]

func _ready() -> void:
	call_deferred("_run")

func _lab(n: Node) -> String:
	if n == null:
		return "<null>"
	return "%s[%d]%s" % [String(n.get_meta("macro_id", "?")), int(n.get_meta("macro_index", -1)),
		String(n.get_meta("placeable_id", n.name))]

func _run() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(8000.0, 1.0, 4000.0)
	cs.shape = box
	floor_body.add_child(cs)
	floor_body.position = Vector3(1200.0, -0.5, 0.0)
	add_child(floor_body)
	var bm := BuildMode.new()
	bm.layout_path = "user://__macroedgesdump___factory.json"   # never written: nothing here saves
	bm.load_shared_structure = false
	bm.allow_legacy_fallback = false
	add_child(bm)
	await get_tree().process_frame
	for k in LINES.size():
		bm.call("_build_full_line", String(LINES[k]), Vector3(400.0 * k, 0.0, 0.0), 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var rows : Array = []
	var root : Node3D = bm.get("_placed_root")
	for c in root.get_children():
		if not c.has_meta("lf_explicit_outs"):
			continue
		var tl : Array = []
		for o in c.get_meta("lf_explicit_outs"):
			var t : Node = get_node_or_null((o as Dictionary)["path"])
			tl.append("%s%s" % [_lab(t), " (recirc)" if bool((o as Dictionary).get("recirc", false)) else ""])
		rows.append("EDGE X %s -> %s" % [_lab(c), str(tl)])
	var nodes : Array = lf.get("_nodes")
	for e in lf.get("_edges"):
		rows.append("EDGE L %s -> %s%s" % [_lab((nodes[int(e["a"])] as Dictionary).get("node")),
			_lab((nodes[int(e["b"])] as Dictionary).get("node")), " (recirc)" if bool(e.get("recirc", false)) else ""])
	rows.sort()
	for r in rows:
		print(r)
	print("PROBE: %d rows (%d explicit sources, %d LineFlow edges, %d nodes)" % [rows.size(),
		rows.filter(func(r): return String(r).begins_with("EDGE X")).size(), (lf.get("_edges") as Array).size(), nodes.size()])
	print("Result: PROBE DONE")
	get_tree().quit(0)
