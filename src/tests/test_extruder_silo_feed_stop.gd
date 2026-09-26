extends Node
## The extruder silo's level sensor and its feed stop — operator 2026-09-25,
## docs/plant/operator_rulings_2026-09-25.md §I11, §I13.
##
##   godot --headless --path . res://src/tests/test_extruder_silo_feed_stop.tscn
##
## WHAT HE SAID (recollection, no document): a laser at the top of each
## extruder silo measures the distance to the material; the HMI shows it as a
## %; it reports a running average (the sim: once per second). At 100 % or more
## the silo's feed stops at once — on 3A/3B the VSS dosing screw, on line 1 the
## shredder — everything else keeps running, so the silo reads over 100 % as
## the wash line empties into it; the feed runs again after a continuous 10 s
## under 100 %.
##
## WHY NOW: since the extruder runs its own flow node (§I4), a line feeding an
## extruder that is off backs up. Measured before this (probe_extruder_off_
## backlog): LineFlow's 250 kg overload e-stop at the extruder after 16.0 min at
## 950 kg/h, inside a cold barrel's 30-min warm-up.
##
## A real 3B line and line 1 (BuildMode._build_full_line -> LineFlow.rebuild ->
## start_line -> tick), and 3A for its pairing, 950 kg/h fed at each line's
## head with the extruders OFF, then started. The brains are unhooked from
## SimTick and stepped by hand; every time is sim time. A bare BuildMode never
## saves; nothing here writes world_layout.json.

const DT : float = 0.1
const WATCHDOG_S : float = 420.0
const FEED_KG_H : float = 950.0
const FEED_S : float = 1200.0          # 20 min: ~317 kg a line, past the silo's 100 %
const SETTLE_S : float = 300.0         # then let the lines run empty into the silos

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _lf : Node = null
var _t : float = 0.0


func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)


func _info(label: String) -> void:
	print("  info  : %s" % label)


func _ready() -> void:
	print("=== extruder silo level sensor: 1 s average, feed stop at 100 %, 10 s to resume ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame
	await _run()
	_finish()


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("Result: FAIL (watchdog — no verdict after %.0f s; %d ok, %d fail so far)" % [WATCHDOG_S, _oks, _fails])
	get_tree().quit(2)


func _nd(body: Node3D) -> Dictionary:
	return _lf.call("node_for_body", body)


func _at(macro: String, idx: int) -> Node3D:
	for e in _lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		if String(b.get_meta("macro_id", "")) == macro and int(b.get_meta("macro_index", -1)) == idx:
			return b
	return null


func _seq_idx(seq: Array, id: String, from: int = 0) -> int:
	for k in range(from, seq.size()):
		if String((seq[k] as Dictionary).get("id", "")) == id:
			return k
	return -1


func _run() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	bm.call("_build_full_line", "line_1", Vector3(400.0, 0.0, 0.0), 0.0)
	bm.call("_build_full_line", "line_3a", Vector3(800.0, 0.0, 0.0), 0.0)
	var st : Node = get_node("/root/SimTick")
	var brains : Dictionary = {}
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
		brains[String(em.get_parent().get_meta("macro_id", ""))] = em
	_lf = LineFlow.new()
	add_child(_lf)
	# LineFlow's _process is left ON here, on purpose, until S3 is re-derived
	# (operator 2026-09-26). The frame awaited below ticks it once on frame time
	# on this machine, and that tick is what S3 passes on: the level sensor's
	# clock (_silo_state, kept through rebuild) starts 0.1 s ahead, and the stop
	# lands on a tick phase where the screw's input grows 0.96 kg (< 1.0). With
	# _process off it grows 1.12 kg and S3 is red; 2 or 3 such ticks give 1.15 /
	# 1.20 kg. probe_feed_stop_pre_ticks, docs/audit/lineflow_set_process_2026-09-26.md.
	await get_tree().process_frame
	_lf.call("rebuild")

	# ── S0 — each silo paired with its feed stop, by name ────────────────────
	var s3b := _seq_idx(BuildMode.LINE_3B_SEQ, "extruder_silo")
	var m11a_3b := _seq_idx(BuildMode.LINE_3B_SEQ, "transport_screw", _seq_idx(BuildMode.LINE_3B_SEQ, "vuilsnippersilo"))
	var s3a := _seq_idx(BuildMode.LINE_3A_SEQ, "extruder_silo")
	var m11a_3a := _seq_idx(BuildMode.LINE_3A_SEQ, "transport_screw", _seq_idx(BuildMode.LINE_3A_SEQ, "vuilsnippersilo"))
	var s1 := _seq_idx(BuildMode.LINE_1_SEQ, "extruder_silo")
	var shr1 := _seq_idx(BuildMode.LINE_1_SEQ, "shredder_1")
	var want := {
		"line_3b": [_at("line_3b", s3b), _at("line_3b", m11a_3b)],
		"line_3a": [_at("line_3a", s3a), _at("line_3a", m11a_3a)],
		"line_1":  [_at("line_1", s1), _at("line_1", shr1)],
	}
	var stops : Array = _lf.call("silo_feed_stops")
	var pair_ok := stops.size() == 3
	var got : Array = []
	for stp in stops:
		var line : String = String(stp["line"])
		var w : Array = want.get(line, [null, null])
		pair_ok = pair_ok and w[0] != null and w[1] != null and stp["silo"] == w[0] and stp["target"] == w[1]
		got.append("%s: %s#%d -> %s#%d" % [line, String((stp["silo"] as Node3D).get_meta("placeable_id", "?")),
			int((stp["silo"] as Node3D).get_meta("macro_index", -1)),
			String((stp["target"] as Node3D).get_meta("placeable_id", "?")),
			int((stp["target"] as Node3D).get_meta("macro_index", -1))])
	_check(pair_ok,
		"S0 each extruder silo stops its own feed: 3A/3B the VSS dosing screw M11a (the transport_screw after the vuilsnippersilo), line 1 its shredder %s"
		% str(got))
	if not pair_ok:
		return
	var silo3b : Node3D = want["line_3b"][0]
	var screw3b : Node3D = want["line_3b"][1]
	var silo1 : Node3D = want["line_1"][0]
	var shred1 : Node3D = want["line_1"][1]
	var vss3b : Node3D = _at("line_3b", _seq_idx(BuildMode.LINE_3B_SEQ, "vss_silo"))
	var flot3b : Node3D = _at("line_3b", _seq_idx(BuildMode.LINE_3B_SEQ, "flotation_tank"))
	var head1 : Node3D = _at("line_1", _seq_idx(BuildMode.LINE_1_SEQ, "opzetband_1"))
	# The first flow machine after the shredder (the overband magnet right after
	# it is a fixture, not a flow node).
	var after1 : Node3D = null
	for k in range(shr1 + 1, BuildMode.LINE_1_SEQ.size()):
		after1 = _at("line_1", k)
		if after1 != null:
			break
	_check(vss3b != null and flot3b != null and head1 != null and after1 != null,
		"S0 the 3B VSS, flotation tank, line 1's opzetband_1 and the machine after its shredder are flow nodes")

	# ── S1 — the sensor; S2 — the stop; run with the extruders OFF ───────────
	_lf.call("start_line")
	var feed_tick : float = FEED_KG_H / 3600.0 * DT
	var fed := 0.0
	var buf_hist : Array = []          # the 3B silo's buffer after each tick
	var rep_prev := 0
	var reports_60 := -1
	var avg_ok := true
	var avg_checked := 0
	var mm_ok := true
	var full_t := {"line_3b": -1.0, "line_1": -1.0}
	var pcu_t := {"line_3b": -1.0, "line_1": -1.0}
	var screw_in_at_stop := -1.0
	var pcu_stop_ok := {"line_3b": false, "line_1": false}
	var off_at_full := {"line_3b": false, "line_1": false}
	var peak := {"line_3b": 0.0, "line_1": 0.0}
	var estop := false
	var flot_on_after := true
	var after1_on_after := true
	var screw_off_after := true
	var shred_off_after := true
	var ticks : int = int((FEED_S + SETTLE_S) / DT)
	for i in ticks:
		if float(i) * DT < FEED_S:
			for head in [vss3b, head1]:
				(_nd(head)["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick, feed_tick / LineFlow.FEED_DENSITY,
					LineFlow.DEFAULT_COMP.duplicate(), "silo_stop", 0.0, 0.0))
			fed += feed_tick
		_lf.call("tick", DT)
		_t += DT
		buf_hist.append(float(_nd(silo3b).get("buffer", 0.0)))
		estop = estop or bool(_lf.get("_estop_active"))
		var lv3 : Dictionary = _lf.call("silo_level_for", silo3b)
		var lv1 : Dictionary = _lf.call("silo_level_for", silo1)
		var rep : int = int(lv3["reports"])
		if _t >= 60.0 - 1e-6 and reports_60 < 0:
			reports_60 = rep
		if rep != rep_prev:
			rep_prev = rep
			# LineFlow samples at the start of its tick, i.e. the buffer after
			# each of the previous 10 ticks.
			if buf_hist.size() >= 11 and avg_checked < 60:
				var sum := 0.0
				for k in range(buf_hist.size() - 11, buf_hist.size() - 1):
					sum += float(buf_hist[k])
				var mine : float = sum / 10.0 / LineFlow.SILO_FULL_KG * 100.0
				avg_ok = avg_ok and absf(mine - float(lv3["pct"])) < 1e-6
				avg_checked += 1
			mm_ok = mm_ok and absf(float(lv3["mm"]) - (4950.0 - float(lv3["pct"]) / 100.0 * 3170.0)) < 1e-6
		for line in ["line_3b", "line_1"]:
			var lv : Dictionary = lv3 if line == "line_3b" else lv1
			peak[line] = maxf(float(peak[line]), float(lv["pct"]))
			if float(pcu_t[line]) < 0.0 and bool(lv["pcu_full"]):
				pcu_t[line] = _t
				pcu_stop_ok[line] = lv["belt"] != null and not bool(_nd(lv["belt"]).get("powered", true)) 					and not bool(_nd(lv["silo"]).get("powered", true)) 					and float(_nd(lv["pcu"]).get("buffer", 0.0)) >= LineFlow.PCU_POT_FULL_KG
			if float(full_t[line]) < 0.0 and float(lv["pct"]) >= 100.0:
				full_t[line] = _t
				if line == "line_3b":
					screw_in_at_stop = float(_nd(screw3b).get("buffer", 0.0))
				var tgt : Node3D = screw3b if line == "line_3b" else shred1
				off_at_full[line] = bool(lv["held"]) and not bool(_nd(tgt).get("powered", true))
		if float(full_t["line_3b"]) > 0.0 and _t > float(full_t["line_3b"]) + 60.0 and _t < float(full_t["line_3b"]) + 61.0:
			flot_on_after = bool(_nd(flot3b).get("powered", false))
			screw_off_after = not bool(_nd(screw3b).get("powered", true))
		if float(full_t["line_1"]) > 0.0 and _t > float(full_t["line_1"]) + 60.0 and _t < float(full_t["line_1"]) + 61.0:
			after1_on_after = bool(_nd(after1).get("powered", false))
			shred_off_after = not bool(_nd(shred1).get("powered", true)) and float(_nd(shred1).get("spin", 1.0)) < 0.01
	for line in ["line_3b", "line_1"]:
		_check(float(pcu_t[line]) > 0.0 and bool(pcu_stop_ok[line]) and float(pcu_t[line]) < float(full_t[line]),
			"S2 %s: with the extruder off its PCU pot fills to %.0f kg at %.0f s, and the PCU belt and the silo's discharge stop, so the silo fills after it (100 %% at %.0f s)"
			% [line, LineFlow.PCU_POT_FULL_KG, float(pcu_t[line]), float(full_t[line])])
	_check(reports_60 == 60,
		"S1 the sensor reports once per second: %d reports in the first 60 s" % reports_60)
	_check(avg_ok and avg_checked >= 30 and mm_ok,
		"S1 each report is the average of the silo's content over the second before it (%d reports checked), as %% of SILO_FULL_KG %.0f kg, and mm = 4950 - %% x 31.7"
		% [avg_checked, LineFlow.SILO_FULL_KG])
	_check(float(full_t["line_3b"]) > 0.0 and bool(off_at_full["line_3b"]) and screw_off_after and flot_on_after,
		"S2 3B: the first report at >= 100 %% (%.0f s, %.1f min) holds the VSS dosing screw off at once; 60 s later it is still off and the flotation tank still runs"
		% [float(full_t["line_3b"]), float(full_t["line_3b"]) / 60.0])
	_check(float(full_t["line_1"]) > 0.0 and bool(off_at_full["line_1"]) and shred_off_after and after1_on_after,
		"S2 line 1: the full silo (%.0f s) pauses the shredder (rotor stopped), and the machine after it still runs"
		% float(full_t["line_1"]))
	var vss_kg : float = float(_nd(vss3b).get("buffer", 0.0))
	var vsn : Node3D = _at("line_3b", _seq_idx(BuildMode.LINE_3B_SEQ, "vuilsnippersilo"))
	var vsn_kg : float = float(_nd(vsn).get("buffer", 0.0)) if vsn != null else -1.0
	var hop_kg : float = float(_nd(shred1).get("buffer", 0.0))
	_check(float(peak["line_3b"]) > 100.0 and float(peak["line_1"]) > 100.0 and not estop,
		"S3 the wash line runs empty on top of the full silo: peaks 3B %.1f %%, line 1 %.1f %%; no overload e-stop anywhere in %.0f min (fed %.0f kg a line)"
		% [float(peak["line_3b"]), float(peak["line_1"]), (FEED_S + SETTLE_S) / 60.0, fed])
	var screw_in_end : float = float(_nd(screw3b).get("buffer", 0.0))
	_check(vss_kg > 10.0 and screw_in_end - screw_in_at_stop < 1.0,
		"S3 3B's backlog waits in the VSS (%.1f kg), where the intake's own VSS-full logic sees it, not in the stopped screw (its input %.1f kg at the stop, %.1f kg now)"
		% [vss_kg, screw_in_at_stop, screw_in_end])
	_info("vuilsnippersilo %.1f kg; line 1's backlog in the shredder hopper %.1f kg" % [vsn_kg, hop_kg])

	# ── S4 — HAND bypasses the stop, as it bypasses every PLC safeguard ──────
	var key3b : String = String(_lf.call("natraject_status", screw3b).get("key", ""))
	_lf.call("set_machine_hand_mode", key3b, true)
	_lf.call("set_machine_manual_on", key3b, true)
	_lf.call("tick", DT)
	var hand_on : bool = bool(_nd(screw3b).get("powered", false))
	_lf.call("set_machine_hand_mode", key3b, false)
	_lf.call("tick", DT)
	var auto_off : bool = not bool(_nd(screw3b).get("powered", true))
	_check(hand_on and auto_off,
		"S4 the dosing screw in HAND + AAN runs despite the full silo (%s); back in AUTO the stop holds it again (%s)" % [hand_on, auto_off])

	# ── S5 — the extruders start, the silos drain, the feed resumes after 10 s ─
	var starters : Array = [brains.get("line_3b"), brains.get("line_1")]
	for b in starters:
		var m : ExtruderModel = b.get("model")
		m.melt_temp = m.config.melt_temp_setpoint
		(b.get("_pending") as Dictionary)["start_production"] = true
	var below_t := {"line_3b": -1.0, "line_1": -1.0}
	var rel_t := {"line_3b": -1.0, "line_1": -1.0}
	var below_reports := {"line_3b": 0, "line_1": 0}
	var rep_seen := {"line_3b": 0, "line_1": 0}
	var model_ok := true
	for _i in range(int(600.0 / DT)):
		for b in starters:
			b.call("_on_sim_tick", DT)
		# The brain copies LineFlow's latest report during its own tick, which
		# comes before LineFlow's: compare them before LineFlow moves on.
		var bm3 : ExtruderModel = brains["line_3b"].get("model")
		var lv3b : Dictionary = _lf.call("silo_level_for", silo3b)
		model_ok = model_ok and bm3.silo_level_known and absf(bm3.silo_level_pct - float(lv3b["pct"])) < 1e-6 \
			and bm3.silo_feed_stopped == bool(lv3b["held"])
		_lf.call("tick", DT)
		_t += DT
		for line in ["line_3b", "line_1"]:
			var silo : Node3D = silo3b if line == "line_3b" else silo1
			var lv : Dictionary = _lf.call("silo_level_for", silo)
			if int(lv["reports"]) != int(rep_seen[line]):
				rep_seen[line] = int(lv["reports"])
				if float(lv["pct"]) < 100.0 and float(rel_t[line]) < 0.0:
					if float(below_t[line]) < 0.0:
						below_t[line] = _t
					below_reports[line] = int(below_reports[line]) + 1
				elif float(rel_t[line]) < 0.0:
					below_t[line] = -1.0
					below_reports[line] = 0
			if float(rel_t[line]) < 0.0 and float(below_t[line]) > 0.0 and not bool(lv["held"]):
				rel_t[line] = _t
		if float(rel_t["line_3b"]) > 0.0 and float(rel_t["line_1"]) > 0.0:
			break
	for line in ["line_3b", "line_1"]:
		var dt : float = float(rel_t[line]) - float(below_t[line])
		_check(float(rel_t[line]) > 0.0 and int(below_reports[line]) == 10 and absf(dt - 9.0) < 0.05,
			"S5 %s: once the running extruder drains the silo under 100 %%, the feed stays stopped until 10 reports in a row read under 100 %% (%d; released %.1f s after the first)"
			% [line, int(below_reports[line]), dt])
	_check(bool(_nd(screw3b).get("powered", false)) and bool(_nd(shred1).get("powered", false)),
		"S5 the 3B dosing screw and line 1's shredder run again")
	_check(model_ok,
		"S6 the 3B extruder model carries its silo's reading every tick (%.1f %%, feed stopped %s)"
		% [(brains["line_3b"].get("model") as ExtruderModel).silo_level_pct,
		   (brains["line_3b"].get("model") as ExtruderModel).silo_feed_stopped])

	# ── S7 — the HMI shows it ────────────────────────────────────────────────
	var m3b : ExtruderModel = brains["line_3b"].get("model")
	m3b.silo_level_pct = 104.2
	m3b.silo_level_mm = 1646.9
	m3b.silo_feed_stopped = true
	var zp = load("res://src/scenes/hud/ExtruderZonePanel.gd").new()
	add_child(zp)
	zp.call("bind", m3b)
	zp.call("_process", 0.0)
	var lbl : Label = zp.find_child("SiloLevel", true, false) as Label
	_check(lbl != null and lbl.visible and lbl.text == "Extrudersilo 104 %  (1647 mm)  —  vol: toevoer gestopt",
		"S7 the extruder panel reads '%s'" % (lbl.text if lbl != null else "<no label>"))
	var m3a : ExtruderModel = brains["line_3a"].get("model")
	m3a.silo_level_known = false
	zp.call("bind", m3a)
	zp.call("_process", 0.0)
	var lbl2 : Label = null
	for c in zp.find_children("SiloLevel", "Label", true, false):
		if not (c as Node).is_queued_for_deletion():
			lbl2 = c as Label
	_check(lbl2 != null and not lbl2.visible,
		"S7 an extruder whose silo is unknown shows no silo line")
	zp.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	if _done:
		return
	_done = true
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 and _oks > 0 else "FAIL", _oks, _fails])
	get_tree().quit(0 if _fails == 0 and _oks > 0 else 1)
