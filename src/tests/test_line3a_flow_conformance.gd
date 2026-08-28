extends Node
## LINE 3A — flow-diagram conformance (docs × sim gap walk, doc 2, 2026-08-28).
##
##   godot --headless --path . res://src/tests/test_line3a_flow_conformance.tscn
##
## Authority: docs/plant/lijn_3a_flow.md (36 material edges) — operator ruling
## 2026-08-28 on gap 2.1: "Diagram is right — fix the sim".
##
## Focus: the MENGSILO AREA the gap fix recomposed. Before the fix the
## ringleiding + a cyclone sat inside the recirc loop and the loop lacked its
## verdeelwals m14 — every written source disagreed. Three layers, like the
## line-1 test: S1 the SEQ says the right thing, S2 the world contains it,
## S3 LineFlow wires it (loop closes as a RECIRC edge back into the silo).
## Order asserted RELATIONALLY — no baked macro indices.

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
	print("[TEST] line 3A — flow-diagram conformance (mengsilo area)")
	var seq : Array = BuildMode.LINE_3A_SEQ

	# ── S1 — SEQ order matches doc edges 13-28 ──────────────────────────────
	print("  -- S1: LINE_3A_SEQ vs lijn_3a_flow.md --")
	var i_silo := _idx_after(seq, "mengsilo", 0)
	_check(i_silo >= 0, "mengsilo present")
	if i_silo < 0:
		print("[TEST] line 3A conformance FAIL (setup)")
		get_tree().quit(1); return

	# Rondmeng-lus (doc edges 19-22): the +X branch right after the silo must
	# be doseerschroef → verdeelwals m14 → ventilator V1 — and NOTHING else.
	var loop_ids : Array = []
	var i := i_silo + 1
	while i < seq.size() and not is_equal_approx(float((seq[i] as Dictionary).get("x", 0.0)), 0.0):
		loop_ids.append(String((seq[i] as Dictionary).get("id", "")))
		i += 1
	_check(loop_ids == ["transport_screw", "verdeelwals", "blower"],
		"rondmeng-lus = doseerschroef M11a → verdeelwals m14 → ventilator V1 (got %s)" % str(loop_ids))
	_check(bool((seq[i_silo + 1] as Dictionary).get("branch_recirc", false)),
		"the lus is tagged branch_recirc (closes back into the silo)")
	_check(not loop_ids.has("ringleiding") and not loop_ids.has("cyclone"),
		"NO ringleiding and NO cyclone inside the lus (the pre-fix miscomposition)")

	# Main path (doc edges 13-17, 24-28): M11b → V2 → ringleiding →
	# cycloon & windzifter → V2a → verdeelwals → therm. droger → cycloon → V3
	# → extruder silo. `i` now points at the first MAIN entry after the lus.
	var main_ids : Array = []
	for j in range(i, seq.size()):
		var mid := String((seq[j] as Dictionary).get("id", ""))
		main_ids.append(mid)
		if mid == "extruder_silo":
			break
	_check(main_ids == ["transport_screw", "blower", "ringleiding", "wind_sifter",
			"cyclone", "blower", "verdeelwals", "thermal_dryer", "cyclone", "blower",
			"extruder_silo"],
		"main path M11b→V2→ringleiding→(cycloon&windzifter)→V2a→verdeelwals→droger→cycloon→V3→silo (got %s)" % str(main_ids))

	# ── S2 — the built world really contains the recomposition ──────────────
	print("  -- S2: built world --")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3a", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var counts : Dictionary = {}
	for m in get_tree().get_nodes_in_group("placed_object"):
		var n3 := m as Node3D
		if n3 == null or not n3.has_meta("placeable_id") or not n3.has_meta("macro_id"):
			continue
		if String(n3.get_meta("macro_id")) != "line_3a":
			continue
		var pid := String(n3.get_meta("placeable_id"))
		counts[pid] = int(counts.get(pid, 0)) + 1
	_check(int(counts.get("ringleiding", 0)) == 1, "world contains exactly 1 ringleiding")
	_check(int(counts.get("wind_sifter", 0)) == 1, "world contains exactly 1 wind_sifter")
	_check(int(counts.get("verdeelwals", 0)) == 2,
		"world contains exactly 2 verdeelwals (m14 in the lus + thermische droger), got %d" % int(counts.get("verdeelwals", 0)))
	_check(int(counts.get("cyclone", 0)) == 2,
		"world contains exactly 2 cyclones (windzifter station + V3 station), got %d" % int(counts.get("cyclone", 0)))

	# ── S3 — LineFlow wires the lus as a closed RECIRC loop ─────────────────
	print("  -- S3: LineFlow topology --")
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var silo_i := -1
	for k in nodes.size():
		if String((nodes[k] as Dictionary).get("id", "")) == "mengsilo":
			silo_i = k
			break
	_check(silo_i >= 0, "mengsilo is a LineFlow node")
	# The lus's LAST machine (V1's blower) must carry a RECIRC edge back into
	# the mengsilo — doc edge 22, the pneumatic rondmeng-retour.
	var recirc_in := false
	var recirc_src_id := ""
	for e in edges:
		if int((e as Dictionary)["b"]) == silo_i and bool((e as Dictionary).get("recirc", false)):
			recirc_in = true
			recirc_src_id = String((nodes[int((e as Dictionary)["a"])] as Dictionary).get("id", ""))
	_check(recirc_in, "a RECIRC edge returns into the mengsilo (doc edge 22)")
	_check(recirc_src_id == "blower",
		"the recirc edge comes from the lus's ventilator V1 (got '%s')" % recirc_src_id)
	# Doc edge 13: Mengsilo → Doseerschroef M11b — the MAIN path must continue
	# past the side-loop. Guards the explicit-out suppression hole: a source
	# with lf_explicit_outs skips the geometry fallback (LineFlow.gd:1142),
	# and the #71 branch-close never reconnected the source to the next main,
	# silently severing the line at the mengsilo.
	var m11b_seq : int = i          # first MAIN entry after the lus (computed in S1)
	var m11b_i := -1
	for k3 in nodes.size():
		var n3d3 = (nodes[k3] as Dictionary).get("node")
		if n3d3 != null and is_instance_valid(n3d3) and n3d3.has_meta("macro_index") \
				and int(n3d3.get_meta("macro_index")) == m11b_seq:
			m11b_i = k3
			break
	_check(m11b_i >= 0, "doseerschroef M11b resolved as a LineFlow node")
	var silo_to_m11b := false
	for e3 in edges:
		if int((e3 as Dictionary)["a"]) == silo_i and int((e3 as Dictionary)["b"]) == m11b_i:
			silo_to_m11b = true
	_check(silo_to_m11b, "mengsilo STILL feeds doseerschroef M11b (doc edge 13 — main path past the lus)")

	# ── S4 — gap 2.2: the bigbag station (doc edge 36, ruled 3A-ONLY) ───────
	print("  -- S4: bigbag station --")
	var i_weeg := _idx_after(seq, "weegschaal", 0)
	var i_bb := _idx_after(seq, "bigbag_station", 0)
	var i_voorraad := _idx_after(seq, "voorraad_silo", 0)
	_check(i_bb >= 0, "bigbag_station is in LINE_3A_SEQ (doc edge 36)")
	_check(i_weeg >= 0 and i_bb > i_weeg and i_voorraad > i_bb,
		"bigbag sits between weegschaal and voorraad_silo in the SEQ")
	if i_bb >= 0:
		_check(not is_equal_approx(float((seq[i_bb] as Dictionary).get("x", 0.0)), 0.0),
			"bigbag is a BRANCH beside the line (the main path runs weegschaal → voorraad)")
	# Ruled 3A-only — no other line may grow one.
	for other in [["line_3b", BuildMode.LINE_3B_SEQ], ["line_1", BuildMode.LINE_1_SEQ],
			["line_3c", BuildMode.LINE_3C_SEQ]]:
		_check(_idx_after(other[1], "bigbag_station", 0) < 0,
			"%s has NO bigbag station (ruled 3A-only)" % other[0])
	_check(int(counts.get("bigbag_station", 0)) == 1, "world contains exactly 1 bigbag_station")
	# LineFlow: weegschaal must feed BOTH the bigbag branch AND the main-path
	# voorraad silo. The second check guards the #71/I1 explicit-out trap —
	# an explicit branch edge on the weegschaal suppresses its geometry
	# fallback, which could silently sever the main path to the silo.
	var weeg_i := -1
	var bb_i := -1
	var vs_i := -1
	for k2 in nodes.size():
		match String((nodes[k2] as Dictionary).get("id", "")):
			"weegschaal": weeg_i = k2
			"bigbag_station": bb_i = k2
			"voorraad_silo": vs_i = k2
	_check(bb_i >= 0, "bigbag_station is a LineFlow node (not dropped as role 'none')")
	if bb_i >= 0:
		_check(String((nodes[bb_i] as Dictionary).get("role", "")) == "sink",
			"bigbag BANKS granulate (MachineFlow role 'sink')")
	var weeg_to_bb := false
	var weeg_to_vs := false
	for e2 in edges:
		if int((e2 as Dictionary)["a"]) == weeg_i:
			if int((e2 as Dictionary)["b"]) == bb_i:
				weeg_to_bb = true
			elif int((e2 as Dictionary)["b"]) == vs_i:
				weeg_to_vs = true
	_check(weeg_to_bb, "LineFlow wired weegschaal → bigbag (doc edge 36)")
	_check(weeg_to_vs, "weegschaal STILL feeds the voorraad silo (doc edge 35 — main path intact)")

	print("[TEST] line 3A conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
