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

	# ── S1 — the macro SEQ matches the flow diagram's chain, AS RULED ────────
	# Doc edges 4,5,6,7: band_2_voorwas -> band_2_hps -> hps_sga -> 2x
	# frictiescheider. OPERATOR RULING 2026-08-28 (layout sketch): the
	# voorwastrommel IS the HPS (SGA) — ONE drum does both, so the diagram's
	# hps_sga block maps onto vw_trommel, not onto a second machine. The
	# earlier same-day literal reading (separate band 2 + corner chute +
	# sga_drum) was reversed by that ruling; sga_feed_chute returns with the
	# line-1 fold (a 90° turn cannot sit on a straight macro axis).
	print("  -- S1: LINE_1_SEQ order vs the flow diagram (one-drum ruling) --")

	var i_goot  := _idx(seq, "scheidingsgoot")
	# The voorwastrommel is `vw_trommel`, NOT the `prewash_drum` stub — see the
	# 2026-08-28 swap in LINE_1_SEQ closing audit finding C5.
	var i_pre   := _idx(seq, "vw_trommel")
	var i_fric  := _idx(seq, "friction_sep")
	var i_mill  := _idx(seq, "mill")

	_check(i_pre >= 0, "vw_trommel (voorwas + HPS/SGA, one drum) is in LINE_1_SEQ")
	_check(_all_idx(seq, "vw_trommel").size() == 1, "exactly one drum on line 1")
	_check(i_goot >= 0, "scheidingsgoot (Y-splitgoot) is in LINE_1_SEQ")
	_check(i_mill >= 0, "mill (Maalmolen 1) is in LINE_1_SEQ")

	if i_goot < 0 or i_pre < 0 or i_fric < 0 or i_mill < 0:
		print("[TEST] line 1 conformance FAIL (setup incomplete)")
		print("Result: FAIL (1 fail)")
		get_tree().quit(1); return

	# One-drum ruling: no second drum, no stub. The corner chute is BACK now
	# that the fold exists to make its 90° turn geometrically true.
	_check(_idx(seq, "sga_drum") < 0,
		"NO separate sga_drum — the ruling merged HPS/SGA into vw_trommel")
	_check(_idx(seq, "prewash_drum") < 0,
		"line 1 uses the photo-signed-off vw_trommel, NOT the prewash_drum stub (audit C5)")
	# Chain: drum_feed_belt -> hoekgoot -> drum -> Y-goot -> friction L/R.
	# (drum_feed_belt was named "westa_band_1" before #fold 2026-09-16 moved the
	# real Westa Band to the shredder infeed — see LINE_1_SEQ.)
	var i_hoek := _idx(seq, "sga_feed_chute")
	var i_westa := _idx(seq, "drum_feed_belt")
	_check(i_hoek >= 0, "sga_feed_chute (90° hoekgoot) is back in LINE_1_SEQ with the fold")
	_check(i_westa >= 0 and i_westa < i_hoek, "drum_feed_belt climbs into the hoekgoot")
	# The real Westa Band (shredder infeed, #fold 2026-09-16) sits right after
	# opzetband_1 and before shredder_1.
	var i_opzet := _idx(seq, "opzetband_1")
	var i_westa_feed := _idx(seq, "westa_band_1")
	var i_shred1 := _idx(seq, "shredder_1")
	_check(i_westa_feed >= 0 and i_opzet >= 0 and i_shred1 >= 0
			and i_opzet < i_westa_feed and i_westa_feed < i_shred1,
		"westa_band_1 sits between opzetband_1 and shredder_1 (shredder-infeed Westa)")
	_check(i_hoek < i_pre, "hoekgoot comes before the drum it feeds")
	_check(i_pre < i_goot, "drum comes before the Y-splitgoot (goot sits at the drum's END)")
	_check(i_goot < i_fric, "Y-splitgoot comes before the frictiescheiders it splits into")
	# The fold itself, as ANGLES rather than signs. It used to assert signf()
	# only, which cannot tell a 90° corner from the 180° U-turn that the
	# flotation tank now makes — the whole point of the 2026-09-17 correction —
	# so the sign list would have gone on passing while the tank pointed the
	# wrong way. Assert the real numbers.
	#
	#   +90  entry 0   compensating LEFT: gives the through-the-wall feeder its
	#                  own leg (without it the next RIGHT rotates legs B-G)
	#   -90  leg A     opzetband_1 -> westa_band_1, the south afslag
	#   +90  leg B     uitvoerband + overband magnet
	#   +90  leg C     short belt -> drum_feed_belt climb
	#   -90  leg D     the drum axis -> Y-splitgoot -> wet street -> mill
	#  +180  leg E     THE U-TURN — flotation tank runs back against the drum.
	#                  OPERATOR 2026-09-17: "the direction of travel through the
	#                  drum is 180 deg opposite of the direction of travel in the
	#                  flotation tank, top-down." Measured end-to-end in S5.
	#   +90  leg F     friction -> Kuferath -> MAS, running off the tank's
	#                  discharge end (the sketch draws this train below the tank)
	#   +90  leg G     back to east for the extruder group, so extruder 1 stays
	#                  the long east-west block the floor plan puts on Hal 2's
	#                  south wall. Added with leg E's U-turn, which rotated every
	#                  leg behind it.
	var turns : Array = []
	for e in seq:
		if (e as Dictionary).has("turn_deg"):
			turns.append(float((e as Dictionary)["turn_deg"]))
	_check(turns == [90.0, -90.0, 90.0, 90.0, -90.0, 180.0, 90.0, 90.0],
		"turn pattern is +90,-90,+90,+90,-90,+180 (tank U-turn),+90,+90 (legs A->G), got %s" % str(turns))

	# ── S1b — gap 1.2: the intake screws belong AFTER the mill ───────────────
	# Doc edges 14-19: maalmolen_1 -> ventilator_10a/b -> intrekschroef_11a/b ->
	# flotatie_tank. There is NO screw between the frictiescheiders and the
	# mill in the diagram. Operator confirmed 2026-08-28: "after the mill, like
	# the doc says".
	print("  -- S1b: intrekschroef 11a/11b sit after the mill (doc edges 16-19) --")
	# 2026-09-25: line 1's intake screws are `intrekschroef` (1.75 m, 30° down
	# from each cyclone into the tank, operator), no longer transport_screws.
	var screws := _all_idx(seq, "intrekschroef")
	var i_flot := _idx(seq, "flotation_tank")
	_check(screws.size() == 2, "line 1 has exactly 2 intrekschroef entries (11a/11b), got %d" % screws.size())
	var pre_mill_screws : Array = []
	for s in screws:
		if int(s) < i_mill:
			pre_mill_screws.append(s)
	_check(pre_mill_screws.is_empty(),
		"NO intake screw before the mill (doc has none there; found %d)" % pre_mill_screws.size())
	for s in screws:
		_check(int(s) > i_mill, "intrekschroef at SEQ %d is after the mill (%d)" % [int(s), i_mill])
		_check(int(s) < i_flot, "intrekschroef at SEQ %d feeds the flotation tank (%d)" % [int(s), i_flot])

	# ── S1c — gap 1.3: the compactor band, on ALL THREE documented lines ────
	# line_flow_graphs.json edges 32/33/34 are identical for lines 1, 3A and 3B:
	#   extruder_silo -> compactor_band -> compactor -> extruder
	# Corroborated by operator checklist FORM-018:52 ("Compactor banden en
	# compactor hoed compleet reinigen" — plural, "beide compactors").
	# The COMPACTOR must stay absent: _m_extruder_unit builds the EREMA PCU
	# integrated on the extruder's -X flank, so a standalone one would double it.
	print("  -- S1c: compactor band on lines 1 / 3A / 3B (doc edge 32) --")
	var lines := {
		"line_1":  {"seq": BuildMode.LINE_1_SEQ,  "extruder": "extruder_1"},
		"line_3a": {"seq": BuildMode.LINE_3A_SEQ, "extruder": "extruder_3a"},
		"line_3b": {"seq": BuildMode.LINE_3B_SEQ, "extruder": "extruder_3b"},
	}
	for lname in lines:
		var lseq : Array = lines[lname]["seq"]
		var ex_id : String = String(lines[lname]["extruder"])
		var i_silo := _idx(lseq, "extruder_silo")
		var i_band := _idx(lseq, "compactorband")
		var i_ex   := _idx(lseq, ex_id)
		_check(i_band >= 0, "%s: compactorband is present (doc node compactor_band)" % lname)
		_check(i_silo >= 0 and i_band > i_silo,
			"%s: compactorband comes after the extruder_silo it is fed from" % lname)
		_check(i_ex >= 0 and i_band < i_ex,
			"%s: compactorband comes before the extruder it feeds" % lname)
		_check(_idx(lseq, "compactor") < 0,
			"%s: NO standalone compactor — the PCU is integrated in the extruder unit" % lname)

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

	_check(int(counts.get("vw_trommel", 0)) == 1,
		"world contains the photo-signed-off vw_trommel (audit C5)")
	_check(int(counts.get("sga_drum", 0)) == 0,
		"world contains NO separate sga_drum (one-drum ruling 2026-08-28)")
	_check(int(counts.get("sga_feed_chute", 0)) == 1,
		"world contains exactly 1 sga_feed_chute (the leg-C→D corner)")
	_check(int(counts.get("prewash_drum", 0)) == 0,
		"world contains NO prewash_drum stub on line 1")
	_check(int(counts.get("compactorband", 0)) == 1,
		"world contains exactly 1 compactorband (doc edge 32, was missing)")
	_check(int(counts.get("scheidingsgoot", 0)) == 1, "world contains exactly 1 scheidingsgoot")
	_check(int(counts.get("intrekschroef", 0)) == 2, "world contains 2 intrekschroef (11a/11b)")

	# With the fold the line is 2-D in plan — S5 reports the full bounding box
	# and gates it against the building shell; this line is just the raw Z.
	print("  info   : line_1 raw Z extent %.1f m (folded — see S5 for the plan box)" % (max_z - min_z))

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
	var goot_i := -1
	var vw_i := -1
	var sga_in_topo := false
	for i in nodes.size():
		var nid := String((nodes[i] as Dictionary).get("id", ""))
		if nid == "scheidingsgoot" and goot_i < 0:
			goot_i = i
		elif nid == "vw_trommel" and vw_i < 0:
			vw_i = i
		elif nid == "sga_drum":
			sga_in_topo = true

	# ONE drum, carrying BOTH merged behaviours (operator ruling 2026-08-28):
	# the wash half (water_add 0.30) and the heavy-parts half folded into
	# contam_remove 0.52 = 1 − (1−0.40)·(1−0.20) and waste 0.05 = 0.03 + 0.02.
	# vw_trommel had NO MachineFlow profile before the C5 swap, so any profile
	# regression here silently deletes the entire wet front — keep these tight.
	_check(vw_i >= 0, "vw_trommel is a node in the LineFlow topology")
	_check(not sga_in_topo, "NO sga_drum node in the topology (one-drum ruling)")
	if vw_i >= 0:
		var vw_cr : float = float((nodes[vw_i] as Dictionary).get("contam_remove", 0.0))
		var vw_wa : float = float((nodes[vw_i] as Dictionary).get("water_add", 0.0))
		var vw_ws : float = float((nodes[vw_i] as Dictionary).get("waste", 0.0))
		_check(is_equal_approx(vw_cr, 0.52),
			"the drum SCREENS as well as washes: contam_remove == 0.52 (merged), got %.3f" % vw_cr)
		_check(is_equal_approx(vw_wa, 0.30),
			"the drum still adds wash water: water_add == 0.30, got %.3f" % vw_wa)
		_check(is_equal_approx(vw_ws, 0.05),
			"the drum rejects heavies: waste == 0.05 (0.03 wash + 0.02 heavies), got %.3f" % vw_ws)
		_check(String((nodes[vw_i] as Dictionary).get("process", "")) == "wash",
			"the drum's process is 'wash', not an inert 'convey' fallback")

	_check(goot_i >= 0, "scheidingsgoot is a node in the LineFlow topology")

	if goot_i >= 0:
		var goot_cr : float = float((nodes[goot_i] as Dictionary).get("contam_remove", 0.0))
		_check(is_equal_approx(goot_cr, 0.0),
			"scheidingsgoot itself removes nothing (it is a chute) — so the drum is what does the work")

	# The drum must actually feed the Y-splitgoot.
	if vw_i >= 0 and goot_i >= 0:
		var drum_to_goot := false
		for e in edges:
			if int((e as Dictionary)["a"]) == vw_i and int((e as Dictionary)["b"]) == goot_i:
				drum_to_goot = true
		_check(drum_to_goot, "LineFlow wired an edge vw_trommel -> scheidingsgoot")

		# ...and the goot must fan out to BOTH frictiescheiders (doc edges 6,7).
		var fanout := 0
		for e in edges:
			if int((e as Dictionary)["a"]) != goot_i:
				continue
			if String((nodes[int((e as Dictionary)["b"])] as Dictionary).get("id", "")) == "friction_sep":
				fanout += 1
		_check(fanout == 2,
			"the Y-splitgoot fans out to BOTH frictiescheiders (doc edges 6,7), got %d" % fanout)

	# ── S4/S4b — the fold's corner really carries material (measured) ────────
	# Two hand-offs at the leg-C→D corner, both measured in WORLD space via the
	# shared port helpers, so a resize of the belt, the chute or the drum (or a
	# broken turn transform) goes red here instead of silently misfeeding:
	#   S4   the hoekgoot's OUT port hangs over the vw_trommel feed funnel
	#   S4b  drum_feed_belt's discharge lip hangs over the hoekgoot's IN port
	# (drum_feed_belt was named "westa_band_1" before #fold 2026-09-16 moved
	# the real Westa Band to the shredder infeed — see LINE_1_SEQ. Local var
	# kept as `westa` below to minimize churn; it now points at drum_feed_belt.)
	print("  -- S4: hoekgoot OUT over funnel · S4b: drum_feed_belt lip over hoekgoot IN --")
	var westa : Node3D = null
	var trommel : Node3D = null
	var hoek : Node3D = null
	for m in get_tree().get_nodes_in_group("placed_object"):
		var n3 := m as Node3D
		if n3 == null or not n3.has_meta("placeable_id") or not n3.has_meta("macro_id"):
			continue
		if String(n3.get_meta("macro_id")) != "line_1":
			continue
		var pid := String(n3.get_meta("placeable_id"))
		if pid == "drum_feed_belt":
			westa = n3
		elif pid == "vw_trommel":
			trommel = n3
		elif pid == "sga_feed_chute":
			hoek = n3
	_check(westa != null, "drum_feed_belt found in the built line")
	_check(trommel != null, "vw_trommel found in the built line")
	_check(hoek != null, "sga_feed_chute found in the built line")
	# Review finding (2026-08-28, CONFIRMED by live mutation): this guard used
	# to skip the whole measured block SILENTLY if _discharge_lip_pos vanished
	# — the suite printed PASS with 4 fewer checks and nothing noticed. The
	# guard's failure is now itself a red check.
	_check(westa == null or westa.has_method("_discharge_lip_pos"),
		"drum_feed_belt exposes _discharge_lip_pos (S4/S4b cannot run without it)")
	if westa != null and trommel != null and hoek != null \
			and westa.has_method("_discharge_lip_pos"):
		var t_size : Vector3 = PlaceableCatalog.get_item("vw_trommel")["size"]
		var c_size : Vector3 = PlaceableCatalog.get_item("sga_feed_chute")["size"]
		var ports : Dictionary = PlaceableCatalog.sga_feed_chute_ports_local(c_size)
		var mouth : Vector3 = trommel.to_global(
			PlaceableCatalog.vw_trommel_funnel_mouth_local(t_size))
		var out_w : Vector3 = hoek.to_global(ports["out"])
		var in_w : Vector3 = hoek.to_global(ports["in"])
		var lip : Vector3 = westa.call("_discharge_lip_pos")
		# S4 — chute OUT over the funnel (mouth radius drum_r*0.55 ≈ 0.85 m).
		var h1 : float = Vector2(out_w.x - mouth.x, out_w.z - mouth.z).length()
		var d1 : float = out_w.y - mouth.y
		print("  info   : chute OUT (%.2f, %.2f, %.2f)  funnel (%.2f, %.2f, %.2f)  horiz %.2f  drop %.2f"
			% [out_w.x, out_w.y, out_w.z, mouth.x, mouth.y, mouth.z, h1, d1])
		# Gate 0.35, NOT the 0.85 funnel radius: losing turn_advance (0.49)
		# misaligns by exactly 0.49 m, which the radius-sized window would
		# wave through (review finding). Measured build lands at 0.00-0.01.
		_check(h1 <= 0.35,
			"S4 chute OUT centred over the funnel (horiz %.2f m, gate 0.35)" % h1)
		_check(d1 >= 0.05 and d1 <= 0.9,
			"S4 chute OUT is a sane drop above the mouth (%.2f m, want 0.05–0.9)" % d1)
		# S4b — drum_feed_belt lip over the chute IN (channel half-width ≈ 0.38 m;
		# allow a little slack for the lip's own overhang).
		var h2 : float = Vector2(lip.x - in_w.x, lip.z - in_w.z).length()
		var d2 : float = lip.y - in_w.y
		print("  info   : drum_feed_belt lip (%.2f, %.2f, %.2f)  chute IN (%.2f, %.2f, %.2f)  horiz %.2f  drop %.2f"
			% [lip.x, lip.y, lip.z, in_w.x, in_w.y, in_w.z, h2, d2])
		_check(h2 <= 0.35,
			"S4b drum_feed_belt lip lands on the hoekgoot infeed (horiz %.2f m, gate 0.35)" % h2)
		_check(d2 >= 0.05 and d2 <= 0.6,
			"S4b drum_feed_belt lip is a sane drop above the infeed (%.2f m, want 0.05–0.6)" % d2)

	# ── S6 — the shredder-infeed head, measured end to end ─────────────
	# opzetband_1 lip → westa_band_1 deck tail → shredder_1 throat. This is the
	# #fold 2026-09-16 corner, and it is the one place on line 1 where a silent
	# miss does not just look wrong but STOPS THE LINE: LineFlow links by
	# nearest-input, so a Westa whose discharge falls short of the throat gets
	# skipped and the material routes straight onto the uitvoerband, leaving
	# shredder_1 with no infeed edge at all. That is exactly what the catalog-box
	# placeholder did before the geometry was derived. Both legs of the transfer
	# are measured in the built world, not recomputed from the builder's own
	# expressions.
	print("  -- S6: opzetband lip → westa deck · S6b: westa lip → shredder hopper --")
	var opz : Node3D = null
	var wsta : Node3D = null
	var shr : Node3D = null
	for m6 in get_tree().get_nodes_in_group("placed_object"):
		var n6 := m6 as Node3D
		if n6 == null or not n6.has_meta("placeable_id") 				or not n6.has_meta("macro_id") 				or String(n6.get_meta("macro_id")) != "line_1":
			continue
		match String(n6.get_meta("placeable_id")):
			"opzetband_1":  opz = n6
			"westa_band_1": wsta = n6
			"shredder_1":   shr = n6
	_check(opz != null, "opzetband_1 found in the built line")
	_check(wsta != null, "westa_band_1 found in the built line")
	_check(shr != null, "shredder_1 found in the built line")
	# Same self-guard as S4's: a vanished method must go RED, not skip silently.
	_check(opz == null or opz.has_method("_discharge_lip_pos"),
		"opzetband_1 exposes _discharge_lip_pos (S6 cannot run without it)")
	_check(wsta == null or wsta.has_method("_discharge_lip_pos"),
		"westa_band_1 exposes _discharge_lip_pos (S6b cannot run without it)")
	if opz != null and wsta != null and shr != null 			and opz.has_method("_discharge_lip_pos") 			and wsta.has_method("_discharge_lip_pos"):
		# S6 — opzetband_1's lip over the Westa's deck tail (its inlet, which sits
		# at the belt's own origin because deck_length is 0).
		var o_lip : Vector3 = opz.call("_discharge_lip_pos")
		var w_deck : Vector3 = wsta.to_global(Vector3(0.0, float(wsta.get("deck_height")), 0.0))
		var h3 : float = Vector2(o_lip.x - w_deck.x, o_lip.z - w_deck.z).length()
		var d3 : float = o_lip.y - w_deck.y
		print("  info   : opzetband lip (%.2f, %.2f, %.2f)  westa deck (%.2f, %.2f, %.2f)  horiz %.2f  drop %.2f"
			% [o_lip.x, o_lip.y, o_lip.z, w_deck.x, w_deck.y, w_deck.z, h3, d3])
		_check(h3 <= 0.35,
			"S6 opzetband_1 lip lands on the Westa deck (horiz %.2f m, gate 0.35)" % h3)
		_check(d3 >= 0.05 and d3 <= 0.9,
			"S6 opzetband_1 lip is a sane drop above the Westa deck (%.2f m, want 0.05–0.9)" % d3)
		# S6b — the Westa's lip INTO shredder_1's hopper. Until 2026-09-25 this
		# asserted the lip over the throat (the shredder's centre); the operator
		# then ruled it ends "about 30 centimeters" into the hopper and clears its
		# rim ("Westa should climb steeper"). The throat is still printed, so
		# shredder_infeed_local and MachineFlow's `in` can be compared.
		var w_lip : Vector3 = wsta.call("_discharge_lip_pos")
		var throat : Vector3 = shr.to_global(PlaceableCatalog.shredder_infeed_local(
			Vector3(PlaceableCatalog.get_item("shredder_1")["size"])))
		var h4 : float = Vector2(w_lip.x - throat.x, w_lip.z - throat.z).length()
		var d4 : float = w_lip.y - throat.y
		print("  info   : westa lip (%.2f, %.2f, %.2f)  shredder throat (%.2f, %.2f, %.2f)  horiz %.2f  drop %.2f"
			% [w_lip.x, w_lip.y, w_lip.z, throat.x, throat.y, throat.z, h4, d4])
		var ssz6 : Vector3 = PlaceableCatalog.get_item("shredder_1")["size"]
		var w_anc : Dictionary = wsta.get_meta("macro_anchor", {}) as Dictionary
		var w_rot : float = float(w_anc.get("rot_y", 0.0))
		var w_fwd := Vector3(-sin(w_rot), 0.0, -cos(w_rot))
		var into : float = (w_lip - shr.global_position).dot(w_fwd) + ssz6.z * 1.04 * 0.5
		var over_rim : float = w_lip.y - (shr.global_position.y + ssz6.y)
		print("  info   : westa lip %.2f m into the hopper, %.2f m over its rim" % [into, over_rim])
		_check(absf(into - PlaceableCatalog.SHREDDER_1_HOPPER_OVERLAP_M) <= 0.05,
			"S6b westa_band_1 lip is ~0.30 m into the shredder hopper (%.2f m)" % into)
		_check(over_rim >= 0.05 and over_rim <= 0.6,
			"S6b westa_band_1 lip clears the hopper rim (%.2f m, want 0.05–0.6)" % over_rim)

	# ── S5 — the fold itself: legs, headings, plan box, and mirror parity ────
	print("  -- S5: fold geometry (operator sketch) --")
	# Node-by-macro-index lookup (relational — no baked indices).
	var by_idx : Dictionary = {}
	for m in get_tree().get_nodes_in_group("placed_object"):
		var n3 := m as Node3D
		if n3 == null or not n3.has_meta("macro_id") or not n3.has_meta("macro_index"):
			continue
		if String(n3.get_meta("macro_id")) != "line_1":
			continue
		by_idx[int(n3.get_meta("macro_index"))] = n3
	var n_shred : Node3D = by_idx.get(_idx(seq, "shredder_1"))
	var n_opzet : Node3D = by_idx.get(_idx(seq, "opzetband_1"))
	var n_magnet : Node3D = by_idx.get(_idx(seq, "overband_magnet_l1"))
	var n_mill : Node3D = by_idx.get(_idx(seq, "mill"))
	var n_flot : Node3D = by_idx.get(_idx(seq, "flotation_tank"))
	var n_ext : Node3D = by_idx.get(_idx(seq, "extruder_1"))
	var n_silo : Node3D = by_idx.get(_idx(seq, "voorraad_silo"))
	var all_named : bool = n_shred != null and n_opzet != null and n_magnet != null \
		and n_mill != null and n_flot != null and n_ext != null and n_silo != null \
		and hoek != null and trommel != null and westa != null
	_check(all_named, "all fold landmark machines resolved by macro_index")
	if all_named:
		# Headings: consecutive legs differ by exactly ±90° (built at rot 0,
		# but asserted RELATIVELY so any placement rotation passes too).
		var d_ab : float = wrapf(n_magnet.rotation.y - n_shred.rotation.y, -PI, PI)
		var d_bc : float = wrapf(westa.rotation.y - n_magnet.rotation.y, -PI, PI)
		var d_cd : float = wrapf(trommel.rotation.y - hoek.rotation.y, -PI, PI)
		_check(absf(d_ab - PI / 2.0) < 0.01, "leg A→B turns LEFT 90° (got %.1f°)" % rad_to_deg(d_ab))
		_check(absf(d_bc - PI / 2.0) < 0.01, "leg B→C turns LEFT 90° (got %.1f°)" % rad_to_deg(d_bc))
		_check(absf(d_cd + PI / 2.0) < 0.01, "leg C→D turns RIGHT 90° (got %.1f°)" % rad_to_deg(d_cd))
		# ── THE OPERATOR'S OWN SENTENCE, 2026-09-17, measured on the built world:
		# "the direction of travel through the drum is 180 deg opposite of the
		# direction of travel in the flotation tank, when looking from top-down."
		# Read off the DRUM itself rather than the mill (same leg, but the drum is
		# what he named), and compared as an ABSOLUTE separation so it passes at
		# any macro placement rotation. absf(±PI) is the only accepted answer —
		# 90° in either direction is the bug this replaced.
		var d_drum_tank : float = wrapf(n_flot.rotation.y - trommel.rotation.y, -PI, PI)
		_check(absf(absf(d_drum_tank) - PI) < 0.01,
			"drum and flotation tank are ANTI-PARALLEL in plan — 180°, operator 2026-09-17 (got %.1f°)"
				% rad_to_deg(d_drum_tank))
		# ...and the tank is offset SIDEWAYS from the drum's street, not on it:
		# anti-parallel alone would also be satisfied by the tank sitting in the
		# middle of the wet train, running back through it.
		var lateral : float = (n_flot.global_position - trommel.global_position) \
			.rotated(Vector3.UP, -trommel.rotation.y).x
		_check(absf(lateral) > 3.0,
			"the tank is laid BESIDE the drum street, not on it (lateral offset %.2f m)" % lateral)
		# Legs F and G — the rest of the serpentine the U-turn produced.
		var n_kuf : Node3D = by_idx.get(_idx(seq, "kufferath_sieve"))
		if n_kuf != null:
			var d_ef : float = wrapf(n_kuf.rotation.y - n_flot.rotation.y, -PI, PI)
			_check(absf(d_ef - PI / 2.0) < 0.01,
				"leg E→F turns LEFT 90° off the tank's discharge end (got %.1f°)" % rad_to_deg(d_ef))
			var d_fg : float = wrapf(n_ext.rotation.y - n_kuf.rotation.y, -PI, PI)
			_check(absf(d_fg - PI / 2.0) < 0.01,
				"leg F→G turns LEFT 90° back to east for the extruder (got %.1f°)" % rad_to_deg(d_fg))
		# The extruder must still run EAST-WEST along the hall (floor plan, Hal 2
		# south wall) — that is what the operator's "leg F is correct" ruling
		# protects, and the U-turn rotated every leg behind it.
		var d_drum_ext : float = wrapf(n_ext.rotation.y - trommel.rotation.y, -PI, PI)
		_check(absf(absf(d_drum_ext) - PI) < 0.01 or absf(d_drum_ext) < 0.01,
			"extruder 1 stays on the drum's east-west axis (got %.1f° off it)" % rad_to_deg(d_drum_ext))
		# ── SAVE-BACK PARITY (#serpentine 2026-09-17) ───────────────────────
		# save_macro_overrides walks its OWN copy of the cursor and must stay in
		# lockstep with the builder, or every machine downstream of a mismatch is
		# inverted against the wrong origin and drifts on each save/reload.
		# `leg_offset` is deliberately NOT mirrored there: it shifts leg_start
		# only, and the save side recovers each leg's origin from the per-node
		# `macro_anchor` meta, which is stamped AFTER the shift. This asserts
		# that reasoning rather than trusting it — run the same inversion the
		# save path runs and demand it lands back on the nominal pose.
		#
		# Done INLINE rather than by calling save_macro_overrides, because that
		# function WRITES user://macros/line_1.json as a side effect; a test must
		# not leave real macro overrides behind for the game to load.
		#
		# lump_cart is excluded: it is a physics prop that settles in Y after
		# placement, so it carries a small dy on EVERY macro (measured 2026-09-17
		# at -0.35 on line 1 and -0.07 on 3A/3B/3C alike — pre-existing and
		# unrelated to the fold). X/Z parity is what this check is for.
		var nominal : Array = bm.call("_macro_nominal_poses", seq)
		var drifted : Array = []
		for idx in by_idx.keys():
			var nn : Node3D = by_idx[idx]
			var pid : String = String(nn.get_meta("placeable_id", ""))
			if pid == "lump_cart" or int(idx) >= nominal.size():
				continue
			var nom2 : Dictionary = nominal[int(idx)]
			var anc : Dictionary = nn.get_meta("macro_anchor")
			var a_rot2 : float = float(anc.get("rot_y", 0.0))
			var rel : Vector3 = nn.global_position - (anc.get("start", Vector3.ZERO) as Vector3)
			var ddx : float = rel.dot(Vector3(cos(a_rot2), 0.0, -sin(a_rot2))) - float(nom2.get("x", 0.0))
			var ddz : float = rel.dot(Vector3(-sin(a_rot2), 0.0, -cos(a_rot2))) - float(nom2.get("z", 0.0))
			if absf(ddx) > 0.01 or absf(ddz) > 0.01:
				drifted.append("%d:%s(%+.2f,%+.2f)" % [int(idx), pid, ddx, ddz])
		_check(drifted.is_empty(),
			"save-back inverts every machine back onto its nominal pose — builder walk and save mirror agree (drifted: %s)"
				% ("none" if drifted.is_empty() else ", ".join(drifted)))
		# Plan relationships at build rot 0 (leg A = -Z, legs B/D/F = -X,
		# leg C = +Z, leg E = -Z): the sketch's shape, not just the turns.
		# NOTE (#fold 2026-09-16): leg A now has an internal 90° turn
		# (opzetband_1 -> westa_band_1 -> shredder_1) that this specific
		# same-axis position check predates. It's LEFT AS-IS pending a real
		# in-game measurement pass (see the geometry-placeholder note on
		# westa_band_1 in PlaceableCatalog._build_opzetband) — it may need
		# rewriting from a Z-comparison to something turn-aware once the new
		# leg's real geometry is measured instead of guessed.
		_check(n_shred.global_position.z < n_opzet.global_position.z,
			"shredder sits downstream (leg A) of the opzetband")
		_check(westa.global_position.z > n_magnet.global_position.z,
			"drum_feed_belt climbs BACK up leg C, north of the magnet run")
		_check(trommel.global_position.x < hoek.global_position.x,
			"drum runs leg D away from the corner chute")
		_check(n_flot.global_position.z < trommel.global_position.z,
			"flotation tank is offset to the SOUTH of the drum axis (sketch)")
		_check(n_ext.global_position.x < n_flot.global_position.x,
			"extruder tail runs leg F (assumed east — Hal 2 floor plan)")
		_check(n_silo.global_position.x < n_ext.global_position.x,
			"voorraad silo is at the very end of leg F")
		# Plan bounding box vs the building shell (140 × 155 aabb). Each
		# machine contributes its own catalog half-extent (max of x/z halves —
		# a rotation-agnostic upper bound), not a flat margin: a flat +3 m
		# understated a 14 m extruder's 7 m half-length at the box edge
		# (review finding).
		var mn := Vector3(INF, 0, INF)
		var mx := Vector3(-INF, 0, -INF)
		for i2 in by_idx:
			var nd2 := by_idx[i2] as Node3D
			var p3 : Vector3 = nd2.global_position
			var it2 : Dictionary = PlaceableCatalog.get_item(String(nd2.get_meta("placeable_id")))
			var half : float = 1.0
			if not it2.is_empty():
				var s2 : Vector3 = it2["size"]
				half = maxf(s2.x, s2.z) * 0.5
			mn.x = minf(mn.x, p3.x - half); mn.z = minf(mn.z, p3.z - half)
			mx.x = maxf(mx.x, p3.x + half); mx.z = maxf(mx.z, p3.z + half)
		var ext_x : float = mx.x - mn.x
		var ext_z : float = mx.z - mn.z
		print("  info   : folded plan box %.1f × %.1f m (shell aabb 140 × 155)" % [ext_x, ext_z])
		_check((ext_x <= 155.0 and ext_z <= 140.0) or (ext_x <= 140.0 and ext_z <= 155.0),
			"folded line 1 FITS the building shell in some orientation (%.1f × %.1f)" % [ext_x, ext_z])
		# Mirror parity: _macro_nominal_poses + each node's own leg anchor must
		# reproduce the builder's world positions exactly. This is the check
		# that makes save-back trustworthy — and would have caught the old
		# gap-override drift between the two walks.
		var nominal_mirror : Array = bm.call("_macro_nominal_poses", seq)
		var worst := 0.0
		var checked := 0
		for i3 in by_idx:
			var node3 : Node3D = by_idx[i3]
			if i3 >= nominal_mirror.size() or not node3.has_meta("macro_anchor"):
				continue
			# lump_cart is a live physics prop — it settles/rolls after spawn
			# (measured −0.29 m of y-settle), so it can't witness PLACEMENT
			# fidelity. Everything bolted down stays in the check.
			if String(node3.get_meta("placeable_id")) == "lump_cart":
				continue
			var nomp : Dictionary = nominal_mirror[i3]
			var anc : Dictionary = node3.get_meta("macro_anchor")
			var a_s : Vector3 = anc.get("start", Vector3.ZERO)
			var a_r : float = float(anc.get("rot_y", 0.0))
			var f3 := Vector3(-sin(a_r), 0.0, -cos(a_r))
			var g3 := Vector3(cos(a_r), 0.0, -sin(a_r))
			# nominal.y now INCLUDES the per-entry {"y": h} lift (mirror fix 3)
			# — re-adding it here would mask the exact phantom-dy save-back bug
			# the fix closed.
			var expect : Vector3 = a_s + f3 * float(nomp.get("z", 0.0)) \
				+ g3 * float(nomp.get("x", 0.0)) \
				+ Vector3.UP * float(nomp.get("y", 0.0))
			var err : float = (node3.global_position - expect).length()
			if err > 0.01:
				print("  debug : idx %d %s err %.4f (world %s vs expect %s)" % [i3,
					String(node3.get_meta("placeable_id")), err,
					str(node3.global_position), str(expect)])
			worst = maxf(worst, err)
			checked += 1
		_check(checked >= 40, "mirror parity covered the whole line (%d nodes)" % checked)
		_check(worst < 0.01,
			"nominal-pose mirror reproduces every world position (worst %.4f m)" % worst)

	print("[TEST] line 1 conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	# CANONICAL VERDICT LINE. tools/regression/run.sh gates on
	# grep -E "Result: PASS|RESULT: PASS" -- the descriptive line above does
	# NOT match it. Measured 2026-08-28: all four conformance tests passed
	# standalone and reported FAIL in the harness for this reason alone.
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
