extends Node
## LINE 1 — flow-diagram conformance (docs × sim gap walk, 2026-08-28).
##
##   godot --headless --path . res://src/tests/test_line1_flow_conformance.tscn
##
## The authority here is the plant's own line-1 flow diagram:
##   docs/plant/lijn_1_flow.md  +  src/data/plant/line_flow_graphs.json["1"]
## and the operator's 2026-08-28 chute spec recorded in
##   docs/plant/DOCS_VS_SIM_GAP_AUDIT_2026-08-28.md
##
## WHY THIS FILE EXISTS. The regression harness's world test builds `line_3a`
## and ONLY line_3a (regression_world_save.gd hardcodes it), so line 1 had no
## coverage whatsoever. The doc walk then found that line 1 shipped without the
## HPS (SGA) heavy-parts separator: `sga_drum` was in the catalog, had a
## builder, and had full MachineFlow behaviour — and was placed by NO macro, so
## line 1 performed no heavy-parts separation at all. A green harness said
## nothing about it. This test is the missing gate.
##
## It asserts THREE independent layers, because any one alone is a mock:
##   S1  the SEQ data says the right thing,
##   S2  BuildMode actually PLACES those machines in the world,
##   S3  LineFlow actually WIRES them and the drum's screening is live.
## S1 alone would just re-read the constant I wrote; S2/S3 are what prove it.
##
## Order is asserted RELATIONALLY (index_of(a) < index_of(b)), never against
## hand-baked macro indices — inserting one machine must not force a rewrite of
## this file (see [[cedo-stale-constant-disease]]).

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

## First index of `id` in the SEQ, or -1.
func _idx(seq: Array, id: String) -> int:
	for i in seq.size():
		if String((seq[i] as Dictionary).get("id", "")) == id:
			return i
	return -1

## Every index of `id` in the SEQ.
func _all_idx(seq: Array, id: String) -> Array:
	var out : Array = []
	for i in seq.size():
		if String((seq[i] as Dictionary).get("id", "")) == id:
			out.append(i)
	return out

func _run() -> void:
	print("[TEST] line 1 — flow-diagram conformance")

	var seq : Array = BuildMode.LINE_1_SEQ

	# ── S1 — the macro SEQ matches the flow diagram's chain ──────────────────
	# Doc edges 4,5,6,7: band_2_voorwas -> band_2_hps -> hps_sga -> 2x
	# frictiescheider. The chutes between them are operator-described
	# (2026-08-28); the diagrams draw blocks only and never show chutes.
	print("  -- S1: LINE_1_SEQ order vs the flow diagram --")

	var i_drum  := _idx(seq, "sga_drum")
	var i_chute := _idx(seq, "sga_feed_chute")
	var i_goot  := _idx(seq, "scheidingsgoot")
	var i_pre   := _idx(seq, "prewash_drum")
	var i_fric  := _idx(seq, "friction_sep")
	var i_mill  := _idx(seq, "mill")

	_check(i_drum >= 0, "sga_drum (HPS/SGA zware-delen scheider) is in LINE_1_SEQ")
	_check(_all_idx(seq, "sga_drum").size() == 1, "exactly one sga_drum on line 1")
	_check(i_chute >= 0, "sga_feed_chute (90 deg hoekgoot, operator 2026-08-28) is in LINE_1_SEQ")
	_check(i_goot >= 0, "scheidingsgoot (Y-splitgoot) is in LINE_1_SEQ")
	_check(i_mill >= 0, "mill (Maalmolen 1) is in LINE_1_SEQ")

	if i_drum < 0 or i_chute < 0 or i_goot < 0 or i_pre < 0 or i_fric < 0 or i_mill < 0:
		print("[TEST] line 1 conformance FAIL (setup incomplete)")
		get_tree().quit(1); return

	# Chain: prewash_drum -> (band 2) -> chute -> drum -> Y-goot -> friction L/R
	_check(i_pre < i_chute, "prewash_drum comes before the SGA feed chute")
	_check(i_chute < i_drum, "feed chute comes before the drum (chute feeds the drum's TOP side)")
	_check(i_drum < i_goot, "drum comes before the Y-splitgoot (goot sits at the drum's END)")
	_check(i_goot < i_fric, "Y-splitgoot comes before the frictiescheiders it splits into")
	# A belt must sit between the prewash drum and the feed chute — doc node
	# band_2_hps, "Band 2 (naar HPS/SGA)".
	var belt_between := false
	for i in range(i_pre + 1, i_chute):
		if String((seq[i] as Dictionary).get("id", "")) == "transport_belt":
			belt_between = true
	_check(belt_between, "a transport_belt (doc node band_2_hps) runs prewash_drum -> feed chute")

	# ── S1b — gap 1.2: the intake screws belong AFTER the mill ───────────────
	# Doc edges 14-19: maalmolen_1 -> ventilator_10a/b -> intrekschroef_11a/b ->
	# flotatie_tank. There is NO screw between the frictiescheiders and the
	# mill in the diagram. Operator confirmed 2026-08-28: "after the mill, like
	# the doc says".
	print("  -- S1b: intrekschroef 11a/11b sit after the mill (doc edges 16-19) --")
	var screws := _all_idx(seq, "transport_screw")
	var i_flot := _idx(seq, "flotation_tank")
	_check(screws.size() == 2, "line 1 has exactly 2 transport_screw entries (intrekschroef 11a/11b), got %d" % screws.size())
	var pre_mill_screws : Array = []
	for s in screws:
		if int(s) < i_mill:
			pre_mill_screws.append(s)
	_check(pre_mill_screws.is_empty(),
		"NO transport_screw before the mill (doc has none there; found %d)" % pre_mill_screws.size())
	for s in screws:
		_check(int(s) > i_mill, "intrekschroef at SEQ %d is after the mill (%d)" % [int(s), i_mill])
		_check(int(s) < i_flot, "intrekschroef at SEQ %d feeds the flotation tank (%d)" % [int(s), i_flot])

	# ── S2 — BuildMode actually PLACES them ─────────────────────────────────
	# S1 only proves the constant reads correctly. This proves the builder
	# turns it into real nodes in the world.
	print("  -- S2: the built world really contains them --")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame

	var counts : Dictionary = {}
	var min_z : float = INF
	var max_z : float = -INF
	for m in get_tree().get_nodes_in_group("placed_object"):
		var n3 := m as Node3D
		if n3 == null or not n3.has_meta("placeable_id"):
			continue
		if not n3.has_meta("macro_id") or String(n3.get_meta("macro_id")) != "line_1":
			continue
		var pid := String(n3.get_meta("placeable_id"))
		counts[pid] = int(counts.get(pid, 0)) + 1
		min_z = minf(min_z, n3.global_position.z)
		max_z = maxf(max_z, n3.global_position.z)

	_check(int(counts.get("sga_drum", 0)) == 1,
		"world contains exactly 1 sga_drum (was 0 before this fix — placed by no macro at all)")
	_check(int(counts.get("sga_feed_chute", 0)) == 1, "world contains exactly 1 sga_feed_chute")
	_check(int(counts.get("scheidingsgoot", 0)) == 1, "world contains exactly 1 scheidingsgoot")
	_check(int(counts.get("transport_screw", 0)) == 2, "world contains 2 transport_screw (intrekschroef 11a/11b)")

	# Line length is reported, not gated: the harness's footprint check only
	# ever builds line_3a (117.2 m, 42 machines, fits), so this number is the
	# only signal that inserting machines has not run line 1 out of the hall.
	print("  info   : line_1 spans %.1f m along Z (line_3a, which fits, is 117.2 m)" % (max_z - min_z))

	# ── S3 — LineFlow wires it, and the drum's screening is LIVE ────────────
	# The drum being placed is not enough: LineFlow drops any machine whose
	# MachineFlow role is "none" (LineFlow.gd:521), and a stand-in with no
	# profile removes no contaminant. This asserts the drum is in the topology
	# AND carries its screening coefficient.
	print("  -- S3: LineFlow topology + live screening --")
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var drum_i := -1
	var goot_i := -1
	for i in nodes.size():
		var nid := String((nodes[i] as Dictionary).get("id", ""))
		if nid == "sga_drum" and drum_i < 0:
			drum_i = i
		elif nid == "scheidingsgoot" and goot_i < 0:
			goot_i = i

	_check(drum_i >= 0, "sga_drum is a node in the LineFlow topology (not dropped as role 'none')")
	_check(goot_i >= 0, "scheidingsgoot is a node in the LineFlow topology")

	if drum_i >= 0:
		var cr : float = float((nodes[drum_i] as Dictionary).get("contam_remove", 0.0))
		_check(is_equal_approx(cr, 0.20),
			"the drum's screening is LIVE in the sim: contam_remove == 0.20 (MachineFlow), got %.3f" % cr)
		_check(String((nodes[drum_i] as Dictionary).get("process", "")) == "screen",
			"the drum's process is 'screen', not an inert 'convey' pass-through")

	if goot_i >= 0:
		var goot_cr : float = float((nodes[goot_i] as Dictionary).get("contam_remove", 0.0))
		_check(is_equal_approx(goot_cr, 0.0),
			"scheidingsgoot itself removes nothing (it is a chute) — so the drum is what does the work")

	# The drum must actually feed the Y-splitgoot.
	if drum_i >= 0 and goot_i >= 0:
		var drum_to_goot := false
		for e in edges:
			if int((e as Dictionary)["a"]) == drum_i and int((e as Dictionary)["b"]) == goot_i:
				drum_to_goot = true
		_check(drum_to_goot, "LineFlow wired an edge sga_drum -> scheidingsgoot")

		# ...and the goot must fan out to BOTH frictiescheiders (doc edges 6,7).
		var fanout := 0
		for e in edges:
			if int((e as Dictionary)["a"]) != goot_i:
				continue
			if String((nodes[int((e as Dictionary)["b"])] as Dictionary).get("id", "")) == "friction_sep":
				fanout += 1
		_check(fanout == 2,
			"the Y-splitgoot fans out to BOTH frictiescheiders (doc edges 6,7), got %d" % fanout)

	print("[TEST] line 1 conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
