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
	# CANONICAL VERDICT LINE. tools/regression/run.sh gates on
	# grep -E "Result: PASS|RESULT: PASS" -- the descriptive line above does
	# NOT match it. Measured 2026-08-28: all four conformance tests passed
	# standalone and reported FAIL in the harness for this reason alone.
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
		get_tree().quit(1); return

	# One-drum ruling: no second drum, no stub. The corner chute is BACK now
	# that the fold exists to make its 90° turn geometrically true.
	_check(_idx(seq, "sga_drum") < 0,
		"NO separate sga_drum — the ruling merged HPS/SGA into vw_trommel")
	_check(_idx(seq, "prewash_drum") < 0,
		"line 1 uses the photo-signed-off vw_trommel, NOT the prewash_drum stub (audit C5)")
	# Chain: westa -> hoekgoot -> drum -> Y-goot -> friction L/R.
	var i_hoek := _idx(seq, "sga_feed_chute")
	var i_westa := _idx(seq, "westa_band_1")
	_check(i_hoek >= 0, "sga_feed_chute (90° hoekgoot) is back in LINE_1_SEQ with the fold")
	_check(i_westa >= 0 and i_westa < i_hoek, "westa band climbs into the hoekgoot")
	_check(i_hoek < i_pre, "hoekgoot comes before the drum it feeds")
	_check(i_pre < i_goot, "drum comes before the Y-splitgoot (goot sits at the drum's END)")
	_check(i_goot < i_fric, "Y-splitgoot comes before the frictiescheiders it splits into")
	# The fold itself: the SEQ carries the sketch's turn pattern L,L,R,R,L.
	var turns : Array = []
	for e in seq:
		if (e as Dictionary).has("turn_deg"):
			turns.append(signf(float((e as Dictionary)["turn_deg"])))
	_check(turns == [1.0, 1.0, -1.0, -1.0, 1.0],
		"turn pattern is LEFT,LEFT,RIGHT,RIGHT,LEFT (sketch legs A→F), got %s" % str(turns))

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
	_check(int(counts.get("transport_screw", 0)) == 2, "world contains 2 transport_screw (intrekschroef 11a/11b)")

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
	#   S4b  the westa band's discharge lip hangs over the hoekgoot's IN port
	print("  -- S4: hoekgoot OUT over funnel · S4b: westa lip over hoekgoot IN --")
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
		if pid == "westa_band_1":
			westa = n3
		elif pid == "vw_trommel":
			trommel = n3
		elif pid == "sga_feed_chute":
			hoek = n3
	_check(westa != null, "westa_band_1 found in the built line")
	_check(trommel != null, "vw_trommel found in the built line")
	_check(hoek != null, "sga_feed_chute found in the built line")
	# Review finding (2026-08-28, CONFIRMED by live mutation): this guard used
	# to skip the whole measured block SILENTLY if _discharge_lip_pos vanished
	# — the suite printed PASS with 4 fewer checks and nothing noticed. The
	# guard's failure is now itself a red check.
	_check(westa == null or westa.has_method("_discharge_lip_pos"),
		"westa exposes _discharge_lip_pos (S4/S4b cannot run without it)")
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
		# S4b — westa lip over the chute IN (channel half-width ≈ 0.38 m; allow
		# a little slack for the lip's own overhang).
		var h2 : float = Vector2(lip.x - in_w.x, lip.z - in_w.z).length()
		var d2 : float = lip.y - in_w.y
		print("  info   : westa lip (%.2f, %.2f, %.2f)  chute IN (%.2f, %.2f, %.2f)  horiz %.2f  drop %.2f"
			% [lip.x, lip.y, lip.z, in_w.x, in_w.y, in_w.z, h2, d2])
		_check(h2 <= 0.35,
			"S4b westa lip lands on the hoekgoot infeed (horiz %.2f m, gate 0.35)" % h2)
		_check(d2 >= 0.05 and d2 <= 0.6,
			"S4b westa lip is a sane drop above the infeed (%.2f m, want 0.05–0.6)" % d2)

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
	var n_magnet : Node3D = by_idx.get(_idx(seq, "overband_magnet"))
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
		var d_de : float = wrapf(n_flot.rotation.y - n_mill.rotation.y, -PI, PI)
		var d_ef : float = wrapf(n_ext.rotation.y - n_flot.rotation.y, -PI, PI)
		_check(absf(d_ab - PI / 2.0) < 0.01, "leg A→B turns LEFT 90° (got %.1f°)" % rad_to_deg(d_ab))
		_check(absf(d_bc - PI / 2.0) < 0.01, "leg B→C turns LEFT 90° (got %.1f°)" % rad_to_deg(d_bc))
		_check(absf(d_cd + PI / 2.0) < 0.01, "leg C→D turns RIGHT 90° (got %.1f°)" % rad_to_deg(d_cd))
		_check(absf(d_de + PI / 2.0) < 0.01, "leg D→E turns RIGHT 90° (got %.1f°)" % rad_to_deg(d_de))
		_check(absf(d_ef - PI / 2.0) < 0.01, "leg E→F turns LEFT 90° (got %.1f°)" % rad_to_deg(d_ef))
		# Plan relationships at build rot 0 (leg A = -Z, legs B/D/F = -X,
		# leg C = +Z, leg E = -Z): the sketch's shape, not just the turns.
		_check(n_shred.global_position.z < n_opzet.global_position.z,
			"shredder sits downstream (leg A) of the opzetband")
		_check(westa.global_position.z > n_magnet.global_position.z,
			"westa climbs BACK up leg C, north of the magnet run")
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
		var nominal : Array = bm.call("_macro_nominal_poses", seq)
		var worst := 0.0
		var checked := 0
		for i3 in by_idx:
			var node3 : Node3D = by_idx[i3]
			if i3 >= nominal.size() or not node3.has_meta("macro_anchor"):
				continue
			# lump_cart is a live physics prop — it settles/rolls after spawn
			# (measured −0.29 m of y-settle), so it can't witness PLACEMENT
			# fidelity. Everything bolted down stays in the check.
			if String(node3.get_meta("placeable_id")) == "lump_cart":
				continue
			var nomp : Dictionary = nominal[i3]
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
	get_tree().quit(1 if _fails > 0 else 0)
