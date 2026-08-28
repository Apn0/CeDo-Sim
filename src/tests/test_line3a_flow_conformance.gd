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

	print("[TEST] line 3A conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
