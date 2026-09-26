extends Node
## Line 3B's wash line: the VSS dosing screw meters it, and the line holds its
## material for 3 min (operator 2026-09-26, docs/plant/operator_rulings_2026-09-26.md
## W2-W5; recollections, every number a PLACEHOLDER; LineFlow.WASH_TIMING).
##
##   godot --headless --path . res://src/tests/test_wash_line_timing.tscn
##
## Before this, measured with probe_3b_residence: every wash machine conveyed
## at 6 kg/s and held nothing, so the first kg reached the extruder silo 38.8 s
## after the VSS, the line held 9.6 kg at 950 kg/h, and a 150 kg VSS emptied in
## 15 s. What the operator ruled, and what each check measures:
##   W1  M11a's setting is screw rpm, 19 kg/h per rpm (100 rpm ~1900 kg/h), the
##       operator's HMI setpoint; a new line starts at 50 rpm = 950 kg/h.
##   W2  the VSS discharges only through M11a: a surplus waits in the VSS.
##   W3  plug flow: the first kg reaches the extruder silo 3 min after M11a
##       starts; the tanks hold most of it, the flotation tank 2/3.
##   W4  after M11a stops, what is past it keeps arriving for that time; what
##       is in the screw stays there.
##   W5  a stopped machine keeps what it holds.
##   W6  a full VSS (15 min of M11a at 50 rpm) runs the line 15 min; the silo
##       reads 100 % at 17.5 min of it.
##   W7  a rebuild keeps the setpoint, the holds and the kg they carry.
##   W8  3A "differs" (not said how): no holds, no meter, no sizes on 3A yet.
##
## 3B and 3A built by BuildMode._build_full_line, LineFlow ticked by hand at
## 0.1 s with its _process OFF (set after add_child), the extruder brains
## unhooked from SimTick. Every time is sim time. A bare BuildMode never saves;
## nothing here writes world_layout.json.

const DT : float = 0.1
const WATCHDOG_S : float = 600.0
const SURPLUS_KG_H : float = 1600.0    # fed into the VSS: more than M11a takes at 50 rpm

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _lf : Node = null
var _t : float = 0.0
var _feed_kg_h : float = 0.0
var _vss : Node3D = null
var _meter : Node3D = null
var _silo : Node3D = null
var _silo_log : Array = []             # [t, kg delivered into the silo this tick]
var _injected : float = 0.0            # kg the suite put into the VSS
var _removed : float = 0.0             # kg the suite took out of the silo


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
	print("=== 3B wash line: the dosing screw meters it, 3 min to the extruder silo ===")
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


func _key(body: Node3D) -> String:
	return String(_nd(body).get("key", ""))


func _in_kg(body: Node3D) -> float:
	return (_nd(body)["in"] as MaterialBatch).mass_kg


## One LineFlow tick with the feed; logs what reached the silo this tick, then
## empties the silo the way a running extruder would. The extruder side is not
## what this suite measures, and a silo left to fill would reach 100 % and stop
## M11a (the feed stop) in the middle of W6.
func _tick() -> void:
	if _feed_kg_h > 0.0:
		var kg : float = _feed_kg_h / 3600.0 * DT
		(_nd(_vss)["in"] as MaterialBatch).add(MaterialBatch.new(kg, kg / LineFlow.FEED_DENSITY,
			LineFlow.DEFAULT_COMP.duplicate(), "wash_timing", 0.0, 0.0))
		_injected += kg
	var before : float = _in_kg(_silo)
	_lf.call("tick", DT)
	_t += DT
	var arrived : float = _in_kg(_silo) - before + float(_nd(_silo).get("_moved_kg", 0.0))
	_silo_log.append([_t, arrived])
	var s_in : MaterialBatch = _nd(_silo)["in"] as MaterialBatch
	_removed += s_in.mass_kg
	s_in.split_mass(s_in.mass_kg)


func _ticks(seconds: float) -> void:
	for _i in int(round(seconds / DT)):
		_tick()


## kg M11a conveys per hour, measured over `seconds`.
func _meter_kg_h(seconds: float) -> float:
	var moved := 0.0
	for _i in int(round(seconds / DT)):
		_tick()
		moved += float(_nd(_meter).get("_moved_kg", 0.0))
	return moved / seconds * 3600.0


## kg on the connectors leaving `body`.
func _out_edge_kg(body: Node3D) -> float:
	var bi : int = int(_lf.call("_nd_for_body", body))
	var kg := 0.0
	for e in _lf.get("_edges"):
		if int(e["a"]) == bi:
			for st in (e["pipe"] as Array):
				kg += (st as MaterialBatch).mass_kg
	return kg


func _body(line: String, id: String, after_id: String = "") -> Node3D:
	var seq : Array = BuildMode.LINE_3B_SEQ if line == "line_3b" else BuildMode.LINE_3A_SEQ
	var from := 0
	if after_id != "":
		for k in seq.size():
			if String((seq[k] as Dictionary).get("id", "")) == after_id:
				from = k + 1
				break
	var idx := -1
	for k in range(from, seq.size()):
		if String((seq[k] as Dictionary).get("id", "")) == id:
			idx = k
			break
	for e in _lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		if String(b.get_meta("macro_id", "")) == line and int(b.get_meta("macro_index", -1)) == idx:
			return b
	return null


func _run() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	bm.call("_build_full_line", "line_3a", Vector3(400.0, 0.0, 0.0), 0.0)
	var st : Node = get_node("/root/SimTick")
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
	_lf = LineFlow.new()
	add_child(_lf)
	_lf.set_process(false)
	await get_tree().process_frame
	_lf.call("rebuild")

	# ── fixture ──────────────────────────────────────────────────────────────
	_vss = _body("line_3b", "vss_silo")
	_meter = _body("line_3b", "transport_screw", "vuilsnippersilo")
	_silo = _body("line_3b", "extruder_silo")
	var flot : Node3D = _body("line_3b", "flotation_tank")
	var rafter : Node3D = _body("line_3b", "rafter")
	var rep : Dictionary = _lf.call("wash_timing", "line_3b")
	var ok_fix : bool = _vss != null and _meter != null and _silo != null and flot != null and rafter != null \
		and not rep.is_empty() and String(rep.get("meter", "")) == _key(_meter) and String(rep.get("silo", "")) == _key(_silo)
	_check(ok_fix, "W0 3B: the VSS, M11a (the transport_screw after the vuilsnippersilo, the silo's feed stop), the flotation tank, the rafter and the extruder silo are flow nodes; M11a is the line's meter (%s -> %s)"
		% [String(rep.get("meter", "?")), String(rep.get("silo", "?"))])
	if not ok_fix:
		return
	var spec : Dictionary = LineFlow.WASH_TIMING["line_3b"]
	var kg_h_start : float = float(spec["meter_kg_h_per_rpm"]) * float(spec["meter_rpm_start"])

	# ── W3 (static) — the holds the rule derives ─────────────────────────────
	var holds : Dictionary = rep["holds"]
	var h_flot : float = float(holds.get(_key(flot), -1.0))
	var h_raft : float = float(holds.get(_key(rafter), -1.0))
	var pass_ok := true
	var air_ok := true
	var pass_n := 0
	for k in holds:
		var id : String = String(k).get_slice("#", 0)
		if id == "flotation_tank" or id == "rafter":
			continue
		if (spec["air"] as Array).has(id):
			air_ok = air_ok and float(holds[k]) == 0.0
		else:
			pass_ok = pass_ok and absf(float(holds[k]) - float(spec["pass_hold_s"])) < 1e-9
			pass_n += 1
	_check(absf(float(rep["first_kg_s"]) - float(spec["transit_s"])) < 1e-6 and absf(h_flot - 2.0 * h_raft) < 1e-6 \
		and h_flot > 0.0 and absf(h_flot + h_raft - float(rep["tanks_s"])) < 1e-6 and pass_ok and air_ok and pass_n >= 7,
		"W3 the fastest way from M11a to the silo takes %.1f s: connectors %.1f s, %d machines x %.0f s, blowers/cyclones 0 s, and the tanks the rest %.1f s: flotation tank %.1f s = 2 x rafter %.1f s"
		% [float(rep["first_kg_s"]), float(rep["geo_s"]), pass_n, float(spec["pass_hold_s"]), float(rep["tanks_s"]), h_flot, h_raft])

	# ── W6 (static) — the sizes ──────────────────────────────────────────────
	var vss_full : float = float(_nd(_vss).get("full_kg", 0.0))
	var silo_full : float = float((_lf.call("silo_level_for", _silo) as Dictionary).get("full_kg", 0.0))
	_check(absf(vss_full - kg_h_start * 15.0 / 60.0) < 1e-6 and absf(silo_full - kg_h_start * 17.5 / 60.0) < 1e-6,
		"W6 the VSS is full at %.1f kg (15 min of M11a at 50 rpm) and the extruder silo reads 100 %% at %.1f kg (17.5 min of it)"
		% [vss_full, silo_full])

	# ── W8 — 3A differs: nothing of this on 3A yet; the zero rule is ─────────
	var a3_holds := 0
	var a3_full := 0
	for e2 in _lf.call("flow_bodies"):
		var b2 : Node3D = e2["body"]
		if String(b2.get_meta("macro_id", "")) != "line_3a":
			continue
		if float(_nd(b2).get("hold_s", 0.0)) > 0.0:
			a3_holds += 1
		if float(_nd(b2).get("full_kg", 0.0)) > 0.0:
			a3_full += 1
	var m3a : Node3D = _body("line_3a", "transport_screw", "vuilsnippersilo")
	var v3a : Node3D = _body("line_3a", "vss_silo")
	var direct3a := false
	for e3 in _lf.get("_edges"):
		if int(e3["a"]) == int(_lf.call("_nd_for_body", v3a)) and int(e3["b"]) == int(_lf.call("_nd_for_body", m3a)):
			direct3a = bool(e3.get("direct", false))
	_check(m3a != null and a3_holds == 0 and a3_full == 0 and absf(float(_nd(m3a)["rate"]) - MachineFlow.profile("transport_screw")["rate"]) < 1e-9 \
		and float(_nd(m3a).get("rpm_pct", 0.0)) == 1.0 and direct3a and _lf.call("wash_timing", "line_3a").is_empty(),
		"W8 3A keeps its old timing: %d machines hold material, %d vessels resized, its M11a at MachineFlow's %.1f kg/s; its VSS -> M11a edge is a direct feed (%s)"
		% [a3_holds, a3_full, float(_nd(m3a)["rate"]) if m3a != null else -1.0, direct3a])

	# ── W1/W2/W3 — run it ────────────────────────────────────────────────────
	var info : Dictionary = _lf.call("get_machine_info", _key(_meter))
	_check(absf(float(info.get("max_rpm", 0.0)) - float(spec["meter_rpm_max"])) < 1e-9 \
		and absf(float(info.get("rpm_pct", 0.0)) * float(info.get("max_rpm", 0.0)) - float(spec["meter_rpm_start"])) < 1e-9,
		"W1 M11a's HMI setpoint runs 0..%.0f rpm and a new line starts it at %.0f rpm"
		% [float(info.get("max_rpm", 0.0)), float(info.get("rpm_pct", 0.0)) * float(info.get("max_rpm", 0.0))])
	_lf.call("start_line")
	_feed_kg_h = SURPLUS_KG_H
	var t_move := -1.0
	for _i in int(120.0 / DT):
		_tick()
		if t_move < 0.0 and float(_nd(_meter).get("_moved_kg", 0.0)) > 0.0:
			t_move = _t
			break
	_ticks(60.0)
	var kh50 : float = _meter_kg_h(60.0)
	var vss_a : float = _in_kg(_vss)
	var meter_in_max := 0.0
	var chute_min := INF
	for _i in int(30.0 / DT):
		_tick()
		meter_in_max = maxf(meter_in_max, _in_kg(_meter))
		chute_min = minf(chute_min, _out_edge_kg(_vss))
	var vss_b : float = _in_kg(_vss)
	_lf.call("set_machine_rpm_pct", _key(_meter), 80.0 / float(spec["meter_rpm_max"]))
	_ticks(10.0)
	var kh80 : float = _meter_kg_h(60.0)
	_lf.call("set_machine_rpm_pct", _key(_meter), float(spec["meter_rpm_start"]) / float(spec["meter_rpm_max"]))
	_check(absf(kh50 - 50.0 * float(spec["meter_kg_h_per_rpm"])) < 0.01 * kh50 \
		and absf(kh80 - 80.0 * float(spec["meter_kg_h_per_rpm"])) < 0.01 * kh80,
		"W1 M11a conveys 19 kg/h per rpm, fed %.0f kg/h: %.1f kg/h at 50 rpm, %.1f kg/h at 80 rpm"
		% [SURPLUS_KG_H, kh50, kh80])
	# M11a's input holds at most the stage of the VSS -> M11a connector that just
	# landed (the connector delivers in stages), never the surplus: it stays
	# below what the connector itself carries.
	_check(absf((vss_b - vss_a) / 30.0 * 3600.0 - (SURPLUS_KG_H - kh50)) < 0.05 * (SURPLUS_KG_H - kh50) and meter_in_max < chute_min,
		"W2 the surplus waits in the VSS (%.1f -> %.1f kg in 30 s = %.1f kg/h, fed %.0f less %.1f), not in M11a's input (at most %.3f kg, less than the %.3f kg on the connector into it)"
		% [vss_a, vss_b, (vss_b - vss_a) / 30.0 * 3600.0, SURPLUS_KG_H, kh50, meter_in_max, chute_min])
	# the first kg at the silo, from the log
	var t_first := -1.0
	_ticks(30.0)
	for rec in _silo_log:
		if float(rec[1]) > 1e-9:
			t_first = float(rec[0])
			break
	var early := 0.0
	for rec2 in _silo_log:
		if float(rec2[0]) < t_move + float(spec["transit_s"]) - 10.0:
			early += float(rec2[1])
	_check(t_move > 0.0 and t_first > 0.0 and absf((t_first - t_move) - float(spec["transit_s"])) < 5.0 and early == 0.0,
		"W3 plug flow: M11a first moves at %.1f s, the first kg reaches the extruder silo %.1f s later (3 min; %.3f kg before %.0f s)"
		% [t_move, t_first - t_move, early, float(spec["transit_s"]) - 10.0])
	_info("wash line at %.0f s: VSS %.1f kg, M11a input %.3f kg, flotation tank's out-connectors %.1f kg"
		% [_t, _in_kg(_vss), _in_kg(_meter), _out_edge_kg(flot)])

	# ── W4 — M11a stops: what is past it keeps coming for its transit ────────
	var key_m : String = _key(_meter)
	var m_edge : float = _out_edge_kg(_meter)
	_lf.call("set_machine_hand_mode", key_m, true)
	_lf.call("set_machine_manual_on", key_m, false)
	var t_stop : float = _t
	_silo_log.clear()
	_ticks(260.0)
	var t_last := -1.0
	for rec3 in _silo_log:
		if float(rec3[1]) > 1e-9:
			t_last = float(rec3[0])
	var m_edge_after : float = _out_edge_kg(_meter)
	var run_on : float = t_last - t_stop
	_check(run_on > float(spec["transit_s"]) - 20.0 and run_on < float(spec["transit_s"]) + 5.0 \
		and m_edge > 0.0 and absf(m_edge_after - m_edge) < 0.5 * m_edge,
		"W4 M11a stopped at %.1f s: the silo keeps receiving for %.1f s (3 min less what is still in the screw), and the screw keeps its content (%.2f -> %.2f kg on its way out)"
		% [t_stop, run_on, m_edge, m_edge_after])
	_lf.call("set_machine_hand_mode", key_m, false)

	# ── W5 — a stopped tank keeps what it holds ──────────────────────────────
	_ticks(150.0)
	var key_f : String = _key(flot)
	var f0 : float = _out_edge_kg(flot)
	_lf.call("set_machine_hand_mode", key_f, true)
	_lf.call("set_machine_manual_on", key_f, false)
	_ticks(3.0)                         # its rotor coasts to a stand (SPIN_UP_S)
	var f1 : float = _out_edge_kg(flot)
	var fin1 : float = _in_kg(flot)
	_ticks(30.0)
	var f2 : float = _out_edge_kg(flot)
	var fin2 : float = _in_kg(flot)
	_lf.call("set_machine_hand_mode", key_f, false)
	_ticks(10.0)
	var f3 : float = _out_edge_kg(flot)
	_check(f1 > 1.0 and absf(f2 - f1) < 1e-9 and fin2 > fin1 and absf(f3 - f2) > 0.0,
		"W5 the flotation tank stopped: what it holds stays (%.2f kg at +3 s, %.2f kg at +33 s) while its input backs up (%.2f -> %.2f kg); started again it moves (%.2f kg)"
		% [f1, f2, fin1, fin2, f3])

	# ── W7 — a rebuild keeps the setpoint, the holds and their kg ────────────
	_lf.call("set_machine_rpm_pct", _key(_meter), 80.0 / float(spec["meter_rpm_max"]))
	_ticks(5.0)
	var pm0 : float = float(_lf.call("pipe_mass"))
	var fe0 : float = _out_edge_kg(flot)
	_lf.call("rebuild")
	var rep2 : Dictionary = _lf.call("wash_timing", "line_3b")
	var pm1 : float = float(_lf.call("pipe_mass"))
	var rpm_after : float = float(_nd(_meter).get("rpm_pct", 0.0)) * float(spec["meter_rpm_max"])
	_check(absf(pm1 - pm0) < 1e-9 and absf(_out_edge_kg(flot) - fe0) < 1e-9 and absf(rpm_after - 80.0) < 1e-9 \
		and str(rep2.get("holds", {})) == str(rep.get("holds", {})),
		"W7 a rebuild keeps M11a at %.0f rpm, the same holds, and the kg on the connectors (%.3f -> %.3f kg; flotation tank %.3f kg)"
		% [rpm_after, pm0, pm1, fe0])
	_lf.call("set_machine_rpm_pct", _key(_meter), float(spec["meter_rpm_start"]) / float(spec["meter_rpm_max"]))

	# ── W6 — a full VSS runs the line 15 min ─────────────────────────────────
	_feed_kg_h = 0.0
	for _i in int(1500.0 / DT):
		_tick()
		if _in_kg(_vss) <= 0.0:
			break
	_ticks(5.0)
	var left : float = _in_kg(_vss)
	(_nd(_vss)["in"] as MaterialBatch).add(MaterialBatch.new(vss_full, vss_full / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "wash_timing", 0.0, 0.0))
	_injected += vss_full
	var t_fill : float = _t
	var t_empty := -1.0
	for _i in int(1200.0 / DT):
		_tick()
		if _in_kg(_vss) < 0.5:
			t_empty = _t
			break
	var lasted : float = t_empty - t_fill
	_check(left <= 1e-9 and t_empty > 0.0 and absf(lasted - 15.0 * 60.0) < 0.01 * 900.0,
		"W6 a full VSS (%.1f kg) with no supply feeds the line %.1f s = %.2f min at 50 rpm (15 min)"
		% [vss_full, lasted, lasted / 60.0])
	var resid : float = float(_lf.call("ledger_residual")) + _injected - _removed
	_check(absf(resid) < 1e-6,
		"W9 no kg made or lost: LineFlow's ledger plus what the suite put in (%.1f kg) and took out (%.1f kg) balances to %.9f kg"
		% [_injected, _removed, resid])


func _finish() -> void:
	if _done:
		return
	_done = true
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 and _oks > 0 else "FAIL", _oks, _fails])
	get_tree().quit(0 if _fails == 0 and _oks > 0 else 1)
