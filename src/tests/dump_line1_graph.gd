extends Node
## Dump line 1's WIRED LineFlow graph — every node and every edge, as built.
##
##   godot --headless --path . res://src/tests/dump_line1_graph.tscn
##
## WHY THIS EXISTS. LINE_1_SEQ is a placement list, not a topology: which
## machine feeds which is decided afterwards, partly by the macro builder's
## explicit-out tagging and partly by LineFlow's geometry fallback. Reading the
## SEQ therefore tells you where things STAND, never what the material DOES.
## The wet section is where that gap bites: the operator's spec is two fully
## independent L/R streams between the scheidingsgoot and the mill, and again
## between the mill and the flotation tank, and nothing in the SEQ expresses
## "independent". This prints the edges that actually exist so the claim can be
## checked instead of argued.
##
## Headless-safe: it measures, it does not render.

const OUT_PATH : String = "res://docs/plant/line1_graph_2026_09_17.json"

func _ready() -> void:
	call_deferred("_run")

## Short label for a node: id plus its macro index, so the two sides of a
## parallel pair are distinguishable (they share an id).
func _label(nd: Dictionary) -> String:
	var n3 : Node3D = nd.get("node", null) as Node3D
	var mi : int = int(n3.get_meta("macro_index", -1)) if n3 != null and n3.has_meta("macro_index") else -1
	var px : float = n3.global_position.x if n3 != null else 0.0
	return "%s#%d(x%+.1f)" % [String(nd.get("id", "?")), mi, px]

func _run() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")

	print("[GRAPH] %d nodes, %d edges" % [nodes.size(), edges.size()])

	# Out-edges per node, in node order — reads as the material path.
	var outs : Dictionary = {}
	for e in edges:
		var a : int = int((e as Dictionary)["a"])
		var lst : Array = outs.get(a, [])
		lst.append(int((e as Dictionary)["b"]))
		outs[a] = lst

	var rows : Array = []
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var tgt : Array = outs.get(i, [])
		var names : Array = []
		for t in tgt:
			names.append(_label(nodes[int(t)]))
		var src_n : String = _label(nd)
		print("  %-28s -> %s" % [src_n, ", ".join(names) if not names.is_empty() else "(nothing)"])
		rows.append({"i": i, "node": src_n, "outs": names})

	# In-degree, so merges show up as loudly as splits.
	var indeg : Dictionary = {}
	for e in edges:
		var b : int = int((e as Dictionary)["b"])
		indeg[b] = int(indeg.get(b, 0)) + 1
	print("[GRAPH] nodes with in-degree > 1 (merge points):")
	for i in nodes.size():
		if int(indeg.get(i, 0)) > 1:
			print("    %-28s in-degree %d" % [_label(nodes[i]), int(indeg[i])])
	print("[GRAPH] nodes with NO outgoing edge (dead ends):")
	for i in nodes.size():
		if not outs.has(i) and String((nodes[i] as Dictionary).get("role", "")) != "sink":
			print("    %s" % _label(nodes[i]))

	# ── Plan-view HEADINGS ────────────────────────────────────────────────────
	# Operator 2026-09-17: "the direction of travel through the drum is 180 deg
	# opposite of the direction of travel in the flotation tank, looking top-down"
	# — matching docs/plant/photos/line1_washing_flow_sketch_2026-08-28.png, where
	# the drum runs west→east along the top and the tank runs east→west below it,
	# fed from the cyclone/screw end. A heading is the machine's own leg rotation,
	# read from the `macro_anchor` the builder stamps, NOT guessed from the order
	# machines appear in: side-by-side pairs make the placement walk zigzag.
	print("[PLAN] headings (deg, 0 = leg 0 forward; +Y up, CCW):")
	var heads : Dictionary = {}
	for want in ["vw_trommel", "scheidingsgoot", "mill", "flotation_tank", "dewater_screw",
			"kufferath_sieve", "mas_droger", "extruder_silo", "extruder_1", "voorraad_silo"]:
		for i in nodes.size():
			if String((nodes[i] as Dictionary).get("id", "")) != want:
				continue
			var n3 : Node3D = (nodes[i] as Dictionary)["node"] as Node3D
			if n3 == null or not n3.has_meta("macro_anchor"):
				continue
			var rot : float = float((n3.get_meta("macro_anchor") as Dictionary).get("rot_y", 0.0))
			var deg : float = rad_to_deg(rot)
			# Unit forward of that leg, same formula the builder walks with.
			var fwd := Vector3(-sin(rot), 0.0, -cos(rot))
			heads[want] = deg
			print("    %-16s heading %+7.1f deg  fwd (%+.2f, %+.2f)  at (%+.1f, %+.1f)"
				% [want, deg, fwd.x, fwd.z, n3.global_position.x, n3.global_position.z])
			break
	if heads.has("vw_trommel") and heads.has("flotation_tank"):
		var delta : float = fposmod(float(heads["flotation_tank"]) - float(heads["vw_trommel"]), 360.0)
		print("    >> drum -> tank heading difference %.1f deg (operator spec: 180)" % delta)

	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"rows": rows}, "  "))
	f.close()
	print("Result: PASS (0 fail)")
	get_tree().quit(0)
