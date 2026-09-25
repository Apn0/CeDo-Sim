extends Node
## Dump ANY macro line's WIRED LineFlow graph, and say where each edge came from.
##
##   godot --headless --path . res://src/tests/dump_line_graph.tscn -- line_3a [tail_from_id]
##
## The generic sibling of dump_line1_graph (which is line 1 only and writes a
## JSON). A SEQ is a placement list, not a topology — this prints what LineFlow
## actually wired: every node, every edge, and whether the edge is EXPLICIT (the
## source carries BuildMode's `lf_explicit_outs` tag) or a GEOMETRY guess (the
## nearest-input-port fallback in LineFlow._link_best_target). For every node
## whose downstream was guessed at or after `tail_from_id` (default
## "extruder_silo"'s upstream blower region — pass any id), it also prints the
## fallback's candidate list in the order the linker walks it, so a wrong pick
## can be read off rather than argued about.
##
## Headless-safe, writes nothing. Measures only; gates nothing.
##
## Written 2026-09-25 on branch claude/laughing-booth-e208e8 (the extruder-silo
## tail pins); the EDGE / NOIN / NOOUT lines at the end were added the same day
## for the cycle-guard swap in LineFlow._link_best_target, so every macro line
## can be dumped before and after a linker change and diffed.

func _ready() -> void:
	call_deferred("_run")

func _label(nodes: Array, i: int) -> String:
	var nd : Dictionary = nodes[i]
	var n3 : Node3D = nd.get("node", null) as Node3D
	var mi : int = int(n3.get_meta("macro_index", -1)) if n3 != null and n3.has_meta("macro_index") else -1
	return "%s#%d[m%d]" % [String(nd.get("id", "?")), i, mi]

func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	# `--reload` (2026-09-25): build, save through BuildMode._save_layout, load
	# the file into a FRESH BuildMode and dump THAT world. BuildMode does not
	# persist lf_explicit_outs (docs/audit/extruder_silo_tail_2026-09-25.md §7),
	# so a reloaded line is wired by the geometry fallback alone — this shows
	# what that fallback makes of it. Both files go to probe-only names; run it
	# under a scratch APPDATA anyway.
	var reload : bool = args.has("--reload")
	args.erase("--reload")
	var line_id : String = args[0] if args.size() > 0 else "line_3a"
	var tail_from : String = args[1] if args.size() > 1 else "mengsilo"

	var bm := BuildMode.new()
	if reload:
		WorldLayout.layout_path_override = "user://__dumpgraph_world_layout.json"
		bm.layout_path = "user://__dumpgraph_factory.json"
		# BuildMode._ready loads layout_path, so a previous run's probe file
		# would be built into this world first (measured: node counts grew
		# 45 → 77 → 102 … across the seven lines until this delete).
		AtomicFile.delete(bm.layout_path)
		AtomicFile.delete(WorldLayout.layout_path_override)
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", line_id, Vector3.ZERO, 0.0)
	await get_tree().process_frame
	if reload:
		print("[RELOAD] user dir %s — saving to %s" % [OS.get_user_data_dir(), bm.layout_path])
		bm.call("_save_layout")
		var path : String = bm.layout_path
		bm.queue_free()
		await get_tree().process_frame
		await get_tree().process_frame
		bm = BuildMode.new()
		bm.layout_path = path
		add_child(bm)                  # _ready → load_layout()
		await get_tree().process_frame
		await get_tree().process_frame
		print("[RELOAD] reloaded from %s" % path)
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	print("[GRAPH] %s: %d nodes, %d edges" % [line_id, nodes.size(), edges.size()])

	# Which sources carry an explicit tag, and which targets they name.
	var tagged : Dictionary = {}
	for i in nodes.size():
		var n3 : Node3D = (nodes[i] as Dictionary).get("node", null) as Node3D
		if n3 != null and n3.has_meta("lf_explicit_outs"):
			var outs : Array = n3.get_meta("lf_explicit_outs")
			if not outs.is_empty():
				tagged[i] = outs

	var tail_i : int = -1
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) == tail_from:
			tail_i = i
			break

	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var outs_s : Array = []
		for e in edges:
			if int(e["a"]) != i:
				continue
			var kind : String = "explicit" if tagged.has(i) else "geometry"
			if bool(e.get("recirc", false)):
				kind = "recirc"
			outs_s.append("%s (%s)" % [_label(nodes, int(e["b"])), kind])
		var ins_s : Array = []
		for e in edges:
			if int(e["b"]) == i:
				ins_s.append(_label(nodes, int(e["a"])))
		var win : Vector3 = nd.get("win", Vector3.ZERO)
		var wout : Vector3 = nd.get("wout", Vector3.ZERO)
		print("  %-32s role=%-8s proc=%-9s win(%+.1f,%+.1f,%+.1f) wout(%+.1f,%+.1f,%+.1f)"
			% [_label(nodes, i), String(nd.get("role", "")), String(nd.get("process", "")),
			win.x, win.y, win.z, wout.x, wout.y, wout.z])
		print("      in  <- %s" % (", ".join(ins_s) if not ins_s.is_empty() else "(none)"))
		print("      out -> %s" % (", ".join(outs_s) if not outs_s.is_empty() else "(none)"))
		# Candidate walk for geometry-linked sources in the tail.
		if tail_i >= 0 and i >= tail_i and not tagged.has(i) and String(nd.get("role", "")) != "sink":
			var cands : Array = []
			for j in nodes.size():
				if j == i:
					continue
				var d : float = wout.distance_to((nodes[j] as Dictionary)["win"] as Vector3)
				if d < LineFlow.MAX_LINK_DIST:
					cands.append([d, j])
			cands.sort_custom(func(x, y): return float(x[0]) < float(y[0]))
			var shown := 0
			for c in cands:
				if shown >= 5:
					break
				print("        cand %-30s %.2f m" % [_label(nodes, int(c[1])), float(c[0])])
				shown += 1

	# Silo/extruder summary — the thing this tool exists for.
	print("[TAIL] extruder_silo / compactorband / extruder edges:")
	for i in nodes.size():
		var fid : String = String((nodes[i] as Dictionary).get("id", ""))
		if fid == "extruder_silo" or fid == "compactorband" or fid.begins_with("extruder_"):
			var ins : Array = []
			var outs : Array = []
			for e in edges:
				if int(e["b"]) == i:
					ins.append(_label(nodes, int(e["a"])))
				if int(e["a"]) == i:
					outs.append(_label(nodes, int(e["b"])))
			print("    %-32s in %s  out %s" % [_label(nodes, i), str(ins), str(outs)])
	# The gap the fallback has to bridge: band discharge → extruder inlet, in
	# 3-D (MAX_LINK_DIST is exclusive: d >= 14.0 is never a candidate).
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) != "compactorband":
			continue
		for j in nodes.size():
			var jid : String = String((nodes[j] as Dictionary).get("id", ""))
			if jid.begins_with("extruder_") and jid != "extruder_silo":
				var d : float = ((nodes[i] as Dictionary)["wout"] as Vector3).distance_to((nodes[j] as Dictionary)["win"] as Vector3)
				print("    gap %s.wout -> %s.win = %.2f m (MAX_LINK_DIST %.1f)"
					% [_label(nodes, i), _label(nodes, j), d, LineFlow.MAX_LINK_DIST])

	# Every cycle the non-recirc edges close. LineFlow's fallback is meant to
	# refuse any edge whose target already reaches its source; each line here
	# is an edge it let through anyway, and which pass produced it.
	var fwd : Dictionary = {}
	for e in edges:
		if bool(e.get("recirc", false)):
			continue
		fwd[int(e["a"])] = (fwd.get(int(e["a"]), []) as Array) + [int(e["b"])]
	var n_cyc := 0
	for e in edges:
		if bool(e.get("recirc", false)):
			continue
		var a : int = int(e["a"])
		var b : int = int(e["b"])
		# does b reach a?
		var seen : Dictionary = {}
		var stack : Array = [b]
		var hit := false
		while not stack.is_empty():
			var cur : int = int(stack.pop_back())
			if cur == a:
				hit = true
				break
			if seen.has(cur):
				continue
			seen[cur] = true
			for nx in fwd.get(cur, []):
				stack.append(int(nx))
		if hit:
			n_cyc += 1
			print("  [CYCLE] %s -> %s (%s) closes a cycle"
				% [_label(nodes, a), _label(nodes, b), "explicit" if tagged.has(a) else "geometry"])
	print("[CYCLES] %d non-recirc edges sit on a cycle" % n_cyc)

	# 2026-09-25 (cycle-guard swap) — a DIFFABLE edge list. One line per edge,
	# `id[m<macro_index>]#<node index>`, sorted, so two runs of the same line
	# (before / after a linker change) diff edge by edge. Node indices are the
	# discovery order, which a linker change does not move. Then every
	# non-sink node with no in-edge (LineFlow treats those as HEADS and draws
	# from a bale at their feed point) and every non-sink with no out-edge.
	var edge_lines : Array = []
	for e in edges:
		var a : int = int(e["a"])
		var kind : String = "explicit" if tagged.has(a) else "geometry"
		if bool(e.get("recirc", false)):
			kind = "recirc"
		edge_lines.append("EDGE %s -> %s %s" % [_label(nodes, a), _label(nodes, int(e["b"])), kind])
	edge_lines.sort()
	for s in edge_lines:
		print(s)
	var heads : Array = []
	var ends : Array = []
	for i in nodes.size():
		var role : String = String((nodes[i] as Dictionary).get("role", ""))
		if role == "sink":
			continue
		var has_in := false
		var has_out := false
		for e in edges:
			if int(e["b"]) == i:
				has_in = true
			if int(e["a"]) == i:
				has_out = true
		if not has_in:
			heads.append("NOIN  %s role=%s" % [_label(nodes, i), role])
		if not has_out:
			ends.append("NOOUT %s role=%s" % [_label(nodes, i), role])
	heads.sort()
	ends.sort()
	for s in heads:
		print(s)
	for s in ends:
		print(s)
	print("Result: DUMP DONE")
	get_tree().quit(0)
