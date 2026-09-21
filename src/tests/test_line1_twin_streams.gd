extends Node
## LINE 1 — the wet section is TWO INDEPENDENT STREAMS (operator, 2026-09-17).
##
##   godot --headless --path . res://src/tests/test_line1_twin_streams.tscn
##
## The operator's spec, verbatim from the live chat:
##
##   "from the first scheidingsgoot: one half of the material goes to the left,
##    other half of the material goes to the right. both streams then continue —
##    by themselves independently — to: friction, glijgoot, mechanical, pipe,
##    blower, pipe, cyclone. then the 2 cyclones feed the top of the mill by
##    gravity. the mill is a single machine, but it splits the material left and
##    right, so each side, after reaching the bottom of the mill: blower, pipe,
##    cyclone, transportation screw — and then the material converges again in
##    the flotation tank."
##
## WHY THIS FILE EXISTS. Nothing tested the wet section's TOPOLOGY. The macro
## SEQ is a placement list — it says where machines stand, never which one feeds
## which — and test_line1_flow_conformance's S3 only checks that the
## scheidingsgoot fans out to two frictiescheiders. Everything downstream of
## that fan-out was unverified, and measurement (dump_line1_graph.gd) showed it
## was wrong in four separate ways at once:
##
##   * the scheidingsgoot had THREE outputs, the third going straight to a
##     mech_dryer and skipping its friction separator entirely;
##   * BOTH frictiescheiders discharged directly into the mill, so the dryer /
##     blower / cyclone train hung off nothing;
##   * the two pre-mill blowers fed EACH OTHER — blower L -> blower R -> blower L,
##     a closed two-node loop with no cyclone in it;
##   * both pre-mill cyclones had no inlet at all.
##
## None of that is visible in the SEQ, and a green harness said nothing about it.
## This is the missing gate: it asserts the wiring, not the wording.
##
## Everything is asserted RELATIONALLY — by walking the graph from the
## scheidingsgoot — so inserting a machine cannot force a rewrite here
## (see the repo's stale-constant note).

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

## Every node index whose catalog id is `id`.
func _find_all(nodes: Array, id: String) -> Array:
	var out : Array = []
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) == id:
			out.append(i)
	return out

## The single node index whose id is `id`, or -1 when it is not unique.
func _find_one(nodes: Array, id: String) -> int:
	var all := _find_all(nodes, id)
	return int(all[0]) if all.size() == 1 else -1

func _outs(edges: Array, i: int) -> Array:
	var out : Array = []
	for e in edges:
		if int((e as Dictionary)["a"]) == i:
			out.append(int((e as Dictionary)["b"]))
	return out

func _ins(edges: Array, i: int) -> Array:
	var out : Array = []
	for e in edges:
		if int((e as Dictionary)["b"]) == i:
			out.append(int((e as Dictionary)["a"]))
	return out

func _id_of(nodes: Array, i: int) -> String:
	return String((nodes[i] as Dictionary).get("id", "?"))

## Walk forward from `start` while each step has exactly ONE outgoing edge,
## collecting the ids passed through. Stops when it reaches `stop_id` or runs
## out of single-successor steps. Returns [ids, reached_stop, visited_indices].
## The indices are what bounds the "wet section" for T9 — the tail of line 1 has
## its own blower→cyclone pair, so a whole-line count of those edges would be
## measuring the MAS dryers as much as this section.
func _walk(nodes: Array, edges: Array, start: int, stop_id: String, limit: int = 12) -> Array:
	var ids : Array = []
	var seen : Array = [start]
	var cur : int = start
	for _step in limit:
		var o := _outs(edges, cur)
		if o.size() != 1:
			return [ids, false, seen]
		cur = int(o[0])
		seen.append(cur)
		var nid := _id_of(nodes, cur)
		if nid == stop_id:
			return [ids, true, seen]
		ids.append(nid)
	return [ids, false, seen]

func _run() -> void:
	print("[TEST] line 1 — twin independent streams (operator 2026-09-17)")

	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	# Built away from the world origin on purpose: a topology bug that collapses
	# to (0,0,0) hides completely when the line starts there.
	bm.call("_build_full_line", "line_1", Vector3(-142.7, 0.0, 42.9), 0.0)
	await get_tree().process_frame

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")

	var goot := _find_one(nodes, "scheidingsgoot")
	var mill := _find_one(nodes, "mill")
	var tank := _find_one(nodes, "flotation_tank")
	_check(goot >= 0, "exactly one scheidingsgoot in the topology")
	_check(mill >= 0, "exactly one mill in the topology (it is a single machine)")
	_check(tank >= 0, "exactly one flotation_tank in the topology")
	if goot < 0 or mill < 0 or tank < 0:
		print("Result: FAIL (%d fail)" % maxi(_fails, 1))
		get_tree().quit(1)
		return

	# ── T1 — the split: exactly two ways out, both frictiescheiders ───────────
	var g_out := _outs(edges, goot)
	_check(g_out.size() == 2,
		"scheidingsgoot has EXACTLY 2 outputs — one half left, one half right (got %d)" % g_out.size())
	var g_ids : Array = []
	for o in g_out:
		g_ids.append(_id_of(nodes, int(o)))
	g_ids.sort()
	_check(g_ids == ["friction_sep", "friction_sep"],
		"both halves leave the scheidingsgoot into a friction separator, nothing else (got %s)" % str(g_ids))

	# ── T2 — 50/50. The operator said HALF each; LineFlow's default share for a
	# non-splitter source is 1/n, so two out-edges IS the even split. Assert the
	# count that produces it rather than a coefficient copied from LineFlow.
	_check(String((nodes[goot] as Dictionary).get("role", "")) != "splitter",
		"the scheidingsgoot is a passive Y, not a biased splitter — so its two edges carry 1/2 each")

	# ── T3 — each stream runs friction → mechanical → blower → cyclone → mill,
	# ALONE. A single-successor walk is the test: if any stage fans out or joins,
	# the walk stops and reports it.
	var wet : Array = [goot, mill, tank]   # node indices T9 confines itself to
	var reached : int = 0
	var expect : Array = ["mech_dryer", "blower", "cyclone"]
	for side in g_out:
		var r := _walk(nodes, edges, int(side), "mill")
		var path : Array = r[0]
		var hit : bool = bool(r[1])
		for v in (r[2] as Array):
			if not wet.has(int(v)):
				wet.append(int(v))
		_check(path == expect,
			"stream from friction_sep#%d runs %s then the mill — no branching, no crossing (got %s)"
				% [int(side), str(expect), str(path)])
		_check(hit, "stream from friction_sep#%d reaches the mill" % int(side))
		if hit:
			reached += 1
	_check(reached == 2, "BOTH streams reach the mill independently (got %d of 2)" % reached)

	# ── T4 — the two cyclones feed the mill, and they are the ONLY things that do
	var mill_in := _ins(edges, mill)
	var mill_in_ids : Array = []
	for i in mill_in:
		mill_in_ids.append(_id_of(nodes, int(i)))
	mill_in_ids.sort()
	_check(mill_in_ids == ["cyclone", "cyclone"],
		"the 2 cyclones feed the top of the mill, and nothing else does (got %s)" % str(mill_in_ids))

	# ── T5 — the cyclones really sit ABOVE the mill, so "by gravity" is true of
	# the geometry and not just of the graph. Measured, not assumed.
	var mill_n : Node3D = (nodes[mill] as Dictionary)["node"] as Node3D
	for i in mill_in:
		var cy : Node3D = (nodes[int(i)] as Dictionary)["node"] as Node3D
		if cy == null or mill_n == null:
			continue
		var dy : float = cy.global_position.y - mill_n.global_position.y
		_check(dy > 1.0,
			"cyclone at x%+.1f sits above the mill so it can feed it by gravity (+%.2f m)"
				% [cy.global_position.x, dy])

	# ── T6 — the mill splits again: two ways out, one per side ───────────────
	var m_out := _outs(edges, mill)
	_check(m_out.size() == 2,
		"the mill splits the material left and right — EXACTLY 2 outputs (got %d)" % m_out.size())

	# ── T7 — each post-mill side runs blower → cyclone → screw → tank, alone ──
	var re_conv : int = 0
	var expect2 : Array = ["cyclone", "transport_screw"]
	for side in m_out:
		_check(_id_of(nodes, int(side)) == "blower",
			"each side leaves the bottom of the mill into a blower (got %s)" % _id_of(nodes, int(side)))
		var r2 := _walk(nodes, edges, int(side), "flotation_tank")
		var path2 : Array = r2[0]
		for v2 in (r2[2] as Array):
			if not wet.has(int(v2)):
				wet.append(int(v2))
		_check(path2 == expect2,
			"post-mill side runs blower then %s then the tank (got %s)" % [str(expect2), str(path2)])
		if bool(r2[1]):
			re_conv += 1
	_check(re_conv == 2,
		"the material converges again in the flotation tank — both sides arrive (got %d of 2)" % re_conv)

	# ── T8 — NOTHING in the wet section is wired to its own sibling. This is the
	# specific failure the geometry fallback produced (blower L <-> blower R) and
	# it is invisible to every check above: a 2-cycle between siblings still
	# leaves each node with one in and one out.
	for pair_id in ["friction_sep", "mech_dryer", "blower", "cyclone", "transport_screw"]:
		var idxs := _find_all(nodes, pair_id)
		var sib_edges : int = 0
		for e in edges:
			var a := int((e as Dictionary)["a"])
			var b := int((e as Dictionary)["b"])
			if idxs.has(a) and idxs.has(b):
				sib_edges += 1
		_check(sib_edges == 0,
			"no %s feeds another %s — the two streams never touch (found %d such edge(s))"
				% [pair_id, pair_id, sib_edges])

	# ── T9 — the glijgoot and the pipes. The operator listed them between the
	# machines; they are not machines, LineFlow fits them per EDGE. Assert the
	# edges that CAUSE them exist, since that is what puts them on screen.
	var fric_to_dryer : int = 0
	var dryer_to_blower : int = 0
	var blower_to_cyclone : int = 0
	for e in edges:
		var ea := int((e as Dictionary)["a"])
		var eb := int((e as Dictionary)["b"])
		# Confined to the nodes the two streams actually walk through. Line 1's
		# MAS tail has its own blower→cyclone pair further downstream, so a
		# whole-line count would be 6 and would move every time the tail changes.
		if not (wet.has(ea) and wet.has(eb)):
			continue
		var sa := _id_of(nodes, ea)
		var sb := _id_of(nodes, eb)
		if sa == "friction_sep" and sb == "mech_dryer":
			fric_to_dryer += 1
		elif sa == "mech_dryer" and sb == "blower":
			dryer_to_blower += 1
		elif sa == "blower" and sb == "cyclone":
			blower_to_cyclone += 1
	_check(fric_to_dryer == 2,
		"2 friction→dryer edges — the glijgoot the operator named, one per stream (got %d)" % fric_to_dryer)
	_check(dryer_to_blower == 2,
		"2 dryer→blower edges — the first pipe, one per stream (got %d)" % dryer_to_blower)
	_check(blower_to_cyclone == 4,
		"4 blower→cyclone edges — the second pipe, 2 pre-mill + 2 post-mill (got %d)" % blower_to_cyclone)

	print("[TEST] line 1 twin streams %s (%d fail)"
		% ["PASS" if _fails == 0 else "FAIL", _fails])
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
