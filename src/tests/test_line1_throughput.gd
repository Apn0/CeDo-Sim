extends Node
## LINE 1 — end-to-end throughput: a bale fed at the head reaches the extruder,
## and it gets there THROUGH shredder_1.
##
##   godot --headless --path . res://src/tests/test_line1_throughput.tscn
##
## WHY THIS FILE EXISTS. Line 1's geometry was well guarded (S1-S6 in
## test_line1_flow_conformance) and its motor loads were guarded
## (test_line1_no_false_overload), but nothing asserted that material actually
## traverses the line. That gap hid a real defect on 2026-09-16: LineFlow reads
## a belt's ports from MachineFlow's generic fractions, which put the inlet high
## at the back and the outlet low at the front — the profile of a machine you
## pour into, not of a belt that climbs. With three inclined belts in a row at
## the new shredder-infeed head, westa_band_1's discharge computed 5.7 m BELOW
## shredder_1's throat, so the nearest-input linker skipped the shredder and
## wired the Westa straight onto the uitvoerband. shredder_1 ended up with NO
## incoming edge at all.
##
## Every geometry check still passed, because the machines were all placed
## correctly — only the FLOW was wrong. The conformance suite's S6/S6b now pin
## the port heights, but a height check cannot see a missing edge, and an edge
## check cannot see material that never moves. This asserts the behaviour:
## feed one real bale through the production path (BuildMode._build_full_line +
## LineFlow.start_line/tick — no mocks) and watch mass come out the far end.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] line 1 — end-to-end throughput")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")

	# ── T1 — the head chain is WIRED, in order, through the shredder ─────────
	# Index the edges by placeable id. Ids are unique here for the three head
	# machines (transport_belt is not, which is exactly why the chain is only
	# asserted as far as the shredder's outlet).
	var idx_of : Dictionary = {}
	for i in nodes.size():
		var nid := String((nodes[i] as Dictionary).get("id", ""))
		if not idx_of.has(nid):
			idx_of[nid] = i
	var linked : Dictionary = {}
	for e in edges:
		linked["%d->%d" % [int((e as Dictionary)["a"]), int((e as Dictionary)["b"])]] = true

	for pair in [["opzetband_1", "westa_band_1"], ["westa_band_1", "shredder_1"]]:
		var a : String = pair[0]
		var b : String = pair[1]
		var ok : bool = idx_of.has(a) and idx_of.has(b) \
			and linked.has("%d->%d" % [int(idx_of[a]), int(idx_of[b])])
		_check(ok, "T1 LineFlow wired %s -> %s" % [a, b])

	# shredder_1 must have an INCOMING edge. This is the check that goes red on
	# the exact bypass described in the header — the shredder stayed in the
	# topology and kept its outgoing edge, so only its in-degree gave it away.
	var shred_i : int = int(idx_of.get("shredder_1", -1))
	var shred_in : int = 0
	for e in edges:
		if int((e as Dictionary)["b"]) == shred_i:
			shred_in += 1
	_check(shred_i >= 0, "T1 shredder_1 is in the LineFlow topology")
	_check(shred_in > 0, "T1 shredder_1 has an incoming edge (in-degree %d)" % shred_in)

	# ── T2 — a real bale, fed at the real head, actually moves ───────────────
	var has_incoming : Dictionary = {}
	for e in edges:
		has_incoming[int((e as Dictionary)["b"])] = true
	var head_node : Node3D = null
	for i2 in nodes.size():
		var nd : Dictionary = nodes[i2]
		if String(nd.get("role", "")) == "sink" or has_incoming.has(i2):
			continue
		var n3d = nd.get("node")
		if n3d != null and is_instance_valid(n3d):
			head_node = n3d as Node3D
			break
	_check(head_node != null, "T2 line 1 has a resolvable source head")
	if head_node == null:
		_finish(); return
	# The source head must BE the intake belt. If the head resolves to something
	# else, the line has a break upstream and everything below would be feeding
	# the wrong end of it.
	var head_id := String(head_node.get_meta("placeable_id", "?"))
	_check(head_id == "opzetband_1",
		"T2 the source head is opzetband_1 (got '%s')" % head_id)

	var bale : Node3D = PlaceableCatalog.build_node("rotterdam", false)
	add_child(bale)
	bale.global_position = lf.call("_head_feed_point", head_node)
	bale.set_meta("delivered", true)

	# Run the line, tracking which landmarks ever HELD mass. "Ever held" rather
	# than "holds now": material moves through, so sampling buffers at the end
	# of the run says almost nothing — the first version of this test sampled
	# once at the end and read zero on machines the bale had already passed.
	var wet_i : int = int(idx_of.get("vw_trommel", -1))
	var shred_saw_mass : bool = false
	var wet_saw_mass : bool = false
	var bale_gone : bool = false
	var t : int = 0
	while t < 6000:                     # 600 s
		lf.call("tick", 0.1)
		t += 1
		if shred_i >= 0 and float((nodes[shred_i] as Dictionary).get("buffer", 0.0)) > 0.0:
			shred_saw_mass = true
		if wet_i >= 0 and float((nodes[wet_i] as Dictionary).get("buffer", 0.0)) > 0.0:
			wet_saw_mass = true
		if not bale_gone and (not is_instance_valid(bale) or bale.is_queued_for_deletion()):
			bale_gone = true
		if bale_gone and float(lf.call("in_transit_mass")) < 0.05:
			break

	_check(bale_gone, "T2 the bale was picked up off the intake belt")
	_check(shred_saw_mass,
		"T2 shredder_1 actually held material during the run (the bypass left it dry)")

	# ── T3 — material got past the head, into the wet front ──────────────────
	# vw_trommel is the first machine on leg D, two turns downstream of the
	# shredder, so mass reaching it proves the whole corrected head (feeder →
	# right turn → Westa → shredder → uitvoerband → left, left → drum) carries
	# material, not just that it is wired.
	#
	# DELIBERATELY NOT asserted here: that granulaat reaches the extruder sink.
	# Measured 2026-09-16 — a single bale banks 0 kg on line 1 after 4000 s of
	# sim, but line 3A does exactly the same (its mass parks in a `blower`), so
	# whatever throttles the tail is sim-wide and predates this test. Asserting
	# it here would produce a permanently-red check about somebody else's bug.
	# It is worth a separate look; it is not line 1's fold.
	print("  info   : granulaat banked %.1f kg after %.0f s (see note above — not gated)"
		% [float(lf.get("gran_mass")), float(t) * 0.1])
	_check(wet_saw_mass,
		"T3 material reached vw_trommel — the head carries mass, not just edges")

	_finish()

func _finish() -> void:
	if _fails == 0:
		print("[TEST] line 1 throughput PASS")
		print("Result: PASS (0 fail)")
		get_tree().quit(0)
	else:
		print("[TEST] line 1 throughput FAIL (%d fail)" % _fails)
		print("Result: FAIL (%d fail)" % _fails)
		get_tree().quit(1)
