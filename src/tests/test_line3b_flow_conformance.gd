extends Node
## LINE 3B — flow-diagram conformance (docs × sim gap walk, doc 3, 2026-08-28).
##
##   godot --headless --path . res://src/tests/test_line3b_flow_conformance.tscn
##
## Authority: docs/plant/lijn_3b_flow.md (27 material edges), corroborated by
## ruling 2.1-B (operator: the REAL thermal-dryer machine is 3B's; 3A dries
## via its heated ring instead). Gap 3.1 replaced the sim's undocumented
## cyclone → plasmaq → cyclone → blower → cyclone dry section (plasmaq is a
## LINE 3C machine — L3C.16, no 3B source exists) with the doc's
## Ventilator → Verdeelwals → Thermische droger → ventilator →
## Ringventilator → extruder silo.
## Three layers: S1 SEQ, S2 world, S3 LineFlow wiring. Order asserted
## RELATIONALLY — no baked macro indices.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _idx_after(seq: Array, id: String, from_i: int) -> int:
	for i in range(from_i, seq.size()):
		if String((seq[i] as Dictionary).get("id", "")) == id:
			return i
	return -1

func _run() -> void:
	print("[TEST] line 3B — flow-diagram conformance")
	var seq : Array = BuildMode.LINE_3B_SEQ

	# ── S1 — SEQ order matches the doc ──────────────────────────────────────
	print("  -- S1: LINE_3B_SEQ vs lijn_3b_flow.md --")
	# Front wash chain (edges 1-9): vuilsnippersilo → M11a screw → rafter →
	# rafter's dewater screw → frictiescheider 210 → flotation (rollers
	# integrated per ruling Q2.3) → dewater screw → frictie li/re.
	var i_raft := _idx_after(seq, "rafter", 0)
	var i_flot := _idx_after(seq, "flotation_tank", 0)
	_check(i_raft >= 0, "rafter present (edge 2)")
	_check(_idx_after(seq, "vuilsnippersilo", 0) < i_raft, "vuilsnippersilo comes before the rafter")
	_check(_idx_after(seq, "dewater_screw", i_raft) < i_flot,
		"the rafter's ontwaterschroef sits between rafter and flotation tank (edges 3-5)")
	_check(i_flot > i_raft, "flotation tank after the rafter chain")

	# L-R split (edges 10-11): two parallel mech dryers.
	var d1 := _idx_after(seq, "mech_dryer", 0)
	var d2 := _idx_after(seq, "mech_dryer", d1 + 1)
	_check(d1 >= 0 and d2 == d1 + 1, "two adjacent mech_dryer entries (310/311)")
	if d1 >= 0 and d2 == d1 + 1:
		_check(bool((seq[d1] as Dictionary).get("parallel_branch", false)) \
			and bool((seq[d2] as Dictionary).get("parallel_branch", false)),
			"both dryers are parallel_branch siblings (the L-R split)")

	# Dry section (edges 12-19): recombine blower → verdeelwals → THERMISCHE
	# DROGER → ventilator → Ringventilator → extruder silo.
	var mid_ids : Array = []
	for j in range(d2 + 1, seq.size()):
		var mid := String((seq[j] as Dictionary).get("id", ""))
		mid_ids.append(mid)
		if mid == "extruder_silo":
			break
	_check(mid_ids == ["blower", "verdeelwals", "thermal_dryer", "blower", "blower",
			"extruder_silo"],
		"dry section = Ventilator → Verdeelwals → Thermische droger → ventilator → Ringventilator → silo (got %s)" % str(mid_ids))
	_check(_idx_after(seq, "plasmaq", 0) < 0,
		"NO plasmaq on 3B (a line-3C machine — L3C.16; no 3B source exists)")
	_check(_idx_after(seq, "thermal_dryer", 0) >= 0,
		"3B has the REAL thermal-dryer machine (ruling 2.1-B: 3A's is the ring)")
	# 3B's diagram draws no mengsilo/rondmeng and no bigbag (Q&A ruled).
	_check(_idx_after(seq, "mengsilo", 0) < 0, "NO mengsilo on 3B (the diagram has none)")
	_check(_idx_after(seq, "ringleiding", 0) < 0, "NO ringleiding on 3B (3A's loop only)")

	# Tail (edges 20-27): silo → compactorband → extruder → … → voorraad silo.
	var i_es := _idx_after(seq, "extruder_silo", 0)
	_check(_idx_after(seq, "compactorband", i_es) == i_es + 1,
		"compactorband directly after the extruder silo (edge 20, gap 1.3)")
	_check(_idx_after(seq, "extruder_3b", 0) > i_es, "extruder_3b after the compactor band")

	# ── S2 — the built world really contains the recomposition ──────────────
	print("  -- S2: built world --")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var counts : Dictionary = {}
	for m in get_tree().get_nodes_in_group("placed_object"):
		var n3 := m as Node3D
		if n3 == null or not n3.has_meta("placeable_id") or not n3.has_meta("macro_id"):
			continue
		if String(n3.get_meta("macro_id")) != "line_3b":
			continue
		var pid := String(n3.get_meta("placeable_id"))
		counts[pid] = int(counts.get(pid, 0)) + 1
	_check(int(counts.get("thermal_dryer", 0)) == 1, "world contains exactly 1 thermal_dryer")
	_check(int(counts.get("verdeelwals", 0)) == 1, "world contains exactly 1 verdeelwals")
	_check(int(counts.get("plasmaq", 0)) == 0, "world contains NO plasmaq")
	_check(int(counts.get("cyclone", 0)) == 0,
		"world contains NO cyclone on 3B (the doc's dry section has none), got %d" % int(counts.get("cyclone", 0)))
	_check(int(counts.get("mech_dryer", 0)) == 2, "world contains both mech dryers (310/311)")

	# ── S3 — LineFlow wiring ────────────────────────────────────────────────
	print("  -- S3: LineFlow topology --")
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	# Resolve nodes by macro_index so the two dryers/blowers are unambiguous.
	var by_seq : Dictionary = {}
	for k in nodes.size():
		var n3d = (nodes[k] as Dictionary).get("node")
		if n3d != null and is_instance_valid(n3d) and n3d.has_meta("macro_index"):
			by_seq[int(n3d.get_meta("macro_index"))] = k
	var fs_i : int = by_seq.get(d1 - 1, -1)        # friction_sep right before the dryers
	var d1_i : int = by_seq.get(d1, -1)
	var d2_i : int = by_seq.get(d2, -1)
	var rc_i : int = by_seq.get(d2 + 1, -1)        # recombine blower
	var td_i : int = by_seq.get(_idx_after(seq, "thermal_dryer", 0), -1)
	_check(fs_i >= 0 and d1_i >= 0 and d2_i >= 0 and rc_i >= 0 and td_i >= 0,
		"split/recombine/thermal-dryer nodes all resolved")
	var split_l := false
	var split_r := false
	var rec_l := false
	var rec_r := false
	for e in edges:
		var ea := int((e as Dictionary)["a"])
		var eb := int((e as Dictionary)["b"])
		if ea == fs_i and eb == d1_i: split_l = true
		if ea == fs_i and eb == d2_i: split_r = true
		if ea == d1_i and eb == rc_i: rec_l = true
		if ea == d2_i and eb == rc_i: rec_r = true
	_check(split_l and split_r, "frictiescheider li/re feeds BOTH dryers (edges 10-11)")
	_check(rec_l and rec_r, "both dryers recombine at the Ventilator (edges 12-13)")
	# The thermal dryer must be ON the main path: something feeds it and it
	# feeds onward (severed-main guard for this line).
	var td_in := false
	var td_out := false
	for e2 in edges:
		if int((e2 as Dictionary)["b"]) == td_i: td_in = true
		if int((e2 as Dictionary)["a"]) == td_i: td_out = true
	_check(td_in and td_out, "the thermal dryer is fed AND feeds onward (in %s / out %s)" % [td_in, td_out])

	print("[TEST] line 3B conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
