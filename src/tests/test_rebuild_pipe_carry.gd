extends Node
## LineFlow.rebuild() keeps the kg riding the connectors (2026-09-25).
##
##   godot --headless --path . res://src/tests/test_rebuild_pipe_carry.tscn
##
## Every connector is a delay line (`_edges[i]["pipe"]`, PIPE_STAGES
## MaterialBatch). rebuild() carried each surviving NODE's state over by
## `id @ scene path`, but _link() cleared _edges and _init_pipes() built fresh
## empty pipes, so every rebuild deleted the kg in transit. BuildMode rebuilds
## on each flow-relevant placement, deletion and jog, a line macro placed beside
## a running line, and the line coupler on every link. Measured before the fix
## (probe_rebuild_pipes): a 3B line fed 60 s at 950 kg/h held 13.35 kg in its
## connectors, a rebuild with nothing changed left 0, and the ledger stayed
## 13.35 kg off for good.
##
## The rule now: a loaded edge whose two ends both survive keeps its stages and
## its phase (stage_t), and an empty edge restarts at phase 0 like a new one;
## an edge that is gone puts its kg into the source's out
## batch, or into the target's in batch when only the target is left; only an
## edge with neither end left loses its kg, with the two machines' own buffers.
##
## A real 3B line (BuildMode._build_full_line -> LineFlow.rebuild -> start_line),
## 950 kg/h fed at the VSS and 20 kg put into the extruder silo. LineFlow's own
## _process is off, so only tick(0.1) moves material; the extruder brains are
## unhooked from SimTick. A bare BuildMode never saves; nothing here writes
## world_layout.json. docs/audit/rebuild_pipe_carry_2026-09-25.md.

const DT : float = 0.1
const WATCHDOG_S : float = 300.0
const FEED_KG_H : float = 950.0
const RUN_S : float = 60.0
const SILO_KG : float = 20.0
## The ledger is a sum of a few hundred float adds; the carried batches are the
## same objects, so the pipes themselves are compared exactly.
const LEDGER_EPS : float = 1e-6
const PHASES : Array[String] = ["S0", "A", "E", "F", "B", "C"]

## Engine errors during the run: LineFlow's survivor key used to call
## get_path() on a machine BuildMode had already taken out of the tree.
class ErrLog extends Logger:
	var mutex := Mutex.new()
	var no_path : int = 0
	var script_errors : int = 0
	func _log_error(_function: String, _file: String, _line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		mutex.lock()
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			script_errors += 1
		if code.contains("Cannot get path") or rationale.contains("Cannot get path"):
			no_path += 1
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _lf : Node = null
var _bm : Node = null
var _log := ErrLog.new()
var _injected : float = 0.0
var _reached : Dictionary = {}
var _vss : Node3D = null


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
	print("=== LineFlow.rebuild() keeps the kg in the connectors ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	OS.add_logger(_log)
	await get_tree().process_frame
	await _run()
	_log.mutex.lock()
	var se : int = _log.script_errors
	_log.mutex.unlock()
	var missing : Array = []
	for p in PHASES:
		if not _reached.has(p):
			missing.append(p)
	_check(missing.is_empty(), "Z every phase ran to its last line (missing: %s)" % str(missing))
	_check(se == 0, "Z no SCRIPT ERROR during the run (%d)" % se)
	_finish()


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("Result: FAIL (watchdog — no verdict after %.0f s; %d ok, %d fail so far)" % [WATCHDOG_S, _oks, _fails])
	get_tree().quit(2)


func _finish() -> void:
	if _done:
		return
	_done = true
	OS.remove_logger(_log)
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 and _oks > 0 else "FAIL", _oks, _fails])
	get_tree().quit(0 if _fails == 0 and _oks > 0 else 1)


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


func _nd(body: Node3D) -> Dictionary:
	return _lf.call("node_for_body", body)


func _held(body: Node3D) -> float:
	var nd := _nd(body)
	return (nd["in"] as MaterialBatch).mass_kg + (nd["out"] as MaterialBatch).mass_kg


func _unhook_brains() -> void:
	var st : Node = get_node("/root/SimTick")
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)


func _feed(seconds: float) -> void:
	var kg : float = FEED_KG_H / 3600.0 * DT
	for i in int(round(seconds / DT)):
		(_nd(_vss)["in"] as MaterialBatch).add(MaterialBatch.new(kg, kg / LineFlow.FEED_DENSITY,
			LineFlow.DEFAULT_COMP.duplicate(), "rebuild_pipes", 0.0, 0.0))
		_injected += kg
		_lf.call("tick", DT)


## ledger_residual() does not count what a test injects (fed_mass is the bale
## feed's counter), so the quantity that balances is residual + injected.
func _residual() -> float:
	return float(_lf.call("ledger_residual")) + _injected


## Every edge by its two BODIES: kg, each stage's batch, the phase.
func _edges() -> Dictionary:
	var out : Dictionary = {}
	var nodes : Array = _lf.get("_nodes")
	for e in _lf.get("_edges"):
		var a : Node3D = nodes[int(e["a"])]["node"]
		var b : Node3D = nodes[int(e["b"])]["node"]
		var kg := 0.0
		var stages : Array = []
		for s in (e["pipe"] as Array):
			var mb := s as MaterialBatch
			kg += mb.mass_kg
			stages.append([mb.mass_kg, mb.volume_m3, mb.water_kg, mb.contaminant_kg, mb.composition.duplicate()])
		out["%d>%d" % [a.get_instance_id(), b.get_instance_id()]] = {
			"kg": kg, "stages": stages, "stage_t": float(e["stage_t"]), "stage_dt": float(e["stage_dt"]),
			"label": "%s#%d -> %s#%d" % [String(a.get_meta("placeable_id", "?")), int(a.get_meta("macro_index", -1)),
				String(b.get_meta("placeable_id", "?")), int(b.get_meta("macro_index", -1))],
		}
	return out


func _edge_kg(a: Node3D, b: Node3D) -> float:
	var r : Dictionary = _edges().get("%d>%d" % [a.get_instance_id(), b.get_instance_id()], {})
	return float(r.get("kg", -1.0))


## Edges of `before` that differ in `after` (a missing edge counts). The phase
## is compared on loaded edges only: an empty edge restarts at 0 (A6).
func _changed(before: Dictionary, after: Dictionary, with_dt: bool) -> Array:
	var bad : Array = []
	for k in before:
		var x : Dictionary = before[k]
		if not after.has(k):
			bad.append(String(x["label"]) + " (gone)")
			continue
		var y : Dictionary = after[k]
		if str(x["stages"]) != str(y["stages"]) \
				or (float(x["kg"]) > 0.0 and float(x["stage_t"]) != float(y["stage_t"])) \
				or (with_dt and float(x["stage_dt"]) != float(y["stage_dt"])):
			bad.append("%s %.3f kg t %.3f -> %.3f kg t %.3f" % [x["label"], x["kg"], x["stage_t"], y["kg"], y["stage_t"]])
	return bad


## The first 3B machine in SEQ order with exactly one edge in and one out, both
## carrying kg, none of the three in `skip`: [source, machine, target].
func _pass_through(skip: Array) -> Array:
	var nodes : Array = _lf.get("_nodes")
	var ins : Dictionary = {}
	var outs : Dictionary = {}
	for e in _lf.get("_edges"):
		var a : Node3D = nodes[int(e["a"])]["node"]
		var b : Node3D = nodes[int(e["b"])]["node"]
		var kg := 0.0
		for s in (e["pipe"] as Array):
			kg += (s as MaterialBatch).mass_kg
		(outs.get_or_add(a, []) as Array).append([b, kg])
		(ins.get_or_add(b, []) as Array).append([a, kg])
	for k in BuildMode.LINE_3B_SEQ.size():
		var m : Node3D = _at("line_3b", k)
		if m == null or m in skip or (ins.get(m, []) as Array).size() != 1 or (outs.get(m, []) as Array).size() != 1:
			continue
		var i0 : Array = ins[m][0]
		var o0 : Array = outs[m][0]
		if i0[0] in skip or o0[0] in skip or float(i0[1]) < 0.05 or float(o0[1]) < 0.05:
			continue
		return [i0[0], m, o0[0]]
	return []


## BuildMode._delete_pointed's order: out of placed_object, out of the tree,
## queue_free, then the rebuild.
func _delete(body: Node3D) -> void:
	body.remove_from_group("placed_object")
	body.get_parent().remove_child(body)
	body.queue_free()


func _no_path_errors() -> int:
	_log.mutex.lock()
	var n : int = _log.no_path
	_log.mutex.unlock()
	return n


func _run() -> void:
	_bm = BuildMode.new()
	add_child(_bm)
	await get_tree().process_frame
	_bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	_unhook_brains()
	_lf = LineFlow.new()
	add_child(_lf)
	# AFTER add_child: Godot 4 turns processing back on at READY for a script
	# that overrides _process, and LineFlow's _process ticks on frame time.
	# Set before, it ticked in the awaited frame, and S0 read 13.35 / 13.40 /
	# 12.85 kg across runs (measured).
	_lf.set_process(false)
	await get_tree().process_frame
	_lf.call("rebuild")
	var seq : Array = BuildMode.LINE_3B_SEQ
	_vss = _at("line_3b", _seq_idx(seq, "vss_silo"))
	var silo : Node3D = _at("line_3b", _seq_idx(seq, "extruder_silo"))
	var plasmaq : Node3D = _at("line_3b", _seq_idx(seq, "plasmaq"))
	var cyc2 : Node3D = _at("line_3b", _seq_idx(seq, "cyclone", _seq_idx(seq, "plasmaq")))
	var screw : Node3D = _at("line_3b", _seq_idx(seq, "transport_screw"))
	var rafter : Node3D = _at("line_3b", _seq_idx(seq, "rafter"))
	var dw1 : Node3D = _at("line_3b", _seq_idx(seq, "dewater_screw"))
	var fs1 : Node3D = _at("line_3b", _seq_idx(seq, "friction_sep"))
	var all_found := _vss != null and silo != null and plasmaq != null \
		and cyc2 != null and screw != null and rafter != null and dw1 != null and fs1 != null
	_check(all_found, "S0 the 3B VSS, extruder silo, plasmaq, the cyclone after it, M11a, rafter, first dewater screw and friction separator are flow nodes")
	if not all_found:
		return

	# ── S0 — a running line with kg in its connectors ─────────────────────────
	_lf.call("start_line")
	(_nd(silo)["in"] as MaterialBatch).add(MaterialBatch.new(SILO_KG, SILO_KG / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "rebuild_pipes", 0.0, 0.0))
	_injected += SILO_KG
	_feed(RUN_S)
	var e0 := _edges()
	var loaded := 0
	for k in e0:
		if float(e0[k]["kg"]) > 0.0:
			loaded += 1
	var p0 : float = float(_lf.call("pipe_mass"))
	var r0 : float = _residual()
	_info("after %.0f s: %d edges, %d carry kg, pipe_mass %.4f kg, in_transit %.4f kg, residual+injected %.9f kg" % [
		RUN_S, e0.size(), loaded, p0, float(_lf.call("in_transit_mass")), r0])
	_check(p0 > 5.0 and loaded >= 8,
		"S0 the connectors carry kg before any rebuild (%.3f kg over %d edges; not a vacuous 0)" % [p0, loaded])
	_check(absf(r0) < LEDGER_EPS, "S0 the ledger balances before any rebuild (%.9f kg)" % r0)
	_reached["S0"] = true

	# ── A — a rebuild that changes nothing (the line coupler, a re-scan) ──────
	_lf.call("rebuild")
	var e1 := _edges()
	var p1 : float = float(_lf.call("pipe_mass"))
	var r1 : float = _residual()
	var carry : Dictionary = _lf.get("last_pipe_carry")
	_info("A: pipe_mass %.4f -> %.4f kg, residual %.9f -> %.9f kg, carry %s" % [p0, p1, r0, r1, str(carry)])
	_check(absf(p1 - p0) < 1e-9, "A1 pipe_mass is the same across the rebuild (%.4f -> %.4f kg)" % [p0, p1])
	_check(absf(r1 - r0) < LEDGER_EPS, "A2 the ledger is the same across the rebuild (moved %.9f kg)" % (r1 - r0))
	var a3 := _changed(e0, e1, true)
	_check(a3.is_empty() and e1.size() == e0.size(),
		"A3 every edge keeps every stage's batch (kg, volume, water, dirt, composition), and every loaded edge its phase stage_t (%d of %d changed: %s)" % [a3.size(), e0.size(), str(a3.slice(0, 4))])
	# An empty edge's phase describes no material. It restarts at 0 like a new
	# edge, so a rebuild of an idle line is what it was before the carry, and a
	# suite that lets LineFlow tick on frame time before its own rebuild() does
	# not start from that frame's phase (measured: test_extruder_silo_feed_stop).
	var empty_phased := 0
	var empty_kept : Array = []
	for k in e0:
		if float(e0[k]["kg"]) > 0.0:
			continue
		if float(e0[k]["stage_t"]) > 0.0:
			empty_phased += 1
		if e1.has(k) and float(e1[k]["stage_t"]) != 0.0:
			empty_kept.append(String(e0[k]["label"]))
	_check(empty_phased > 0 and empty_kept.is_empty(),
		"A6 an empty edge restarts at phase 0 (%d empty edges had a phase before; kept: %s)" % [empty_phased, str(empty_kept)])
	_check(absf(float(carry.get("carried", -1.0)) - p0) < 1e-9 and float(carry.get("to_source", -1.0)) == 0.0
		and float(carry.get("to_target", -1.0)) == 0.0 and float(carry.get("lost", -1.0)) == 0.0,
		"A4 LineFlow reports all of it carried in place, none re-homed or lost (%s)" % str(carry))
	_feed(30.0)
	var r1b : float = _residual()
	_check(absf(r1b) < 1e-4, "A5 30 s on, fed, the carried kg have moved on and the ledger still balances (%.9f kg)" % r1b)
	_reached["A"] = true

	# ── E — a second line placed beside the running one (a line macro) ────────
	var e2 := _edges()
	var p2 : float = float(_lf.call("pipe_mass"))
	var r2 : float = _residual()
	var n_before : int = (_lf.get("_nodes") as Array).size()
	_bm.call("_build_full_line", "line_3a", Vector3(400.0, 0.0, 0.0), 0.0)
	_unhook_brains()
	_lf.call("rebuild")
	var e3 := _edges()
	var n_after : int = (_lf.get("_nodes") as Array).size()
	var r3 : float = _residual()
	var e_bad := _changed(e2, e3, true)
	_info("E: %d -> %d nodes, %d -> %d edges, pipe_mass %.4f -> %.4f kg" % [
		n_before, n_after, e2.size(), e3.size(), p2, float(_lf.call("pipe_mass"))])
	_check(n_after > n_before + 20, "E1 line 3A joined the graph (%d -> %d nodes)" % [n_before, n_after])
	_check(e_bad.is_empty(), "E2 every 3B edge keeps its stages and phase across the 3A placement (%d changed: %s)" % [e_bad.size(), str(e_bad.slice(0, 4))])
	_check(absf(r3 - r2) < LEDGER_EPS and absf(float(_lf.call("pipe_mass")) - p2) < 1e-9,
		"E3 the ledger and pipe_mass are the same across it (moved %.9f kg)" % (r3 - r2))
	_reached["E"] = true

	# ── F — a machine jogged: the edge stays, its transit time changes ────────
	_feed(20.0)
	var f_key := "%d>%d" % [plasmaq.get_instance_id(), cyc2.get_instance_id()]
	var e4 := _edges()
	var r4 : float = _residual()
	var f0 : Dictionary = e4.get(f_key, {})
	plasmaq.global_position += Vector3(1.5, 0.0, 0.0)
	_lf.call("rebuild")
	var e5 := _edges()
	var f1 : Dictionary = e5.get(f_key, {})
	var r5 : float = _residual()
	_info("F: plasmaq -> cyclone %.4f kg, stage_dt %.3f -> %.3f s" % [
		float(f0.get("kg", -1.0)), float(f0.get("stage_dt", -1.0)), float(f1.get("stage_dt", -1.0))])
	_check(not f0.is_empty() and not f1.is_empty() and float(f0["kg"]) > 0.01
		and float(f0["stage_dt"]) != float(f1["stage_dt"]),
		"F1 the plasmaq -> cyclone edge carries kg and survives the jog with a new transit time")
	var f_bad := _changed(e4, e5, false)
	_check(f_bad.is_empty(), "F2 every edge keeps its stages and phase across the jog (%d changed: %s)" % [f_bad.size(), str(f_bad.slice(0, 4))])
	_check(absf(r5 - r4) < LEDGER_EPS, "F3 the ledger is the same across the jog (moved %.9f kg)" % (r5 - r4))
	_reached["F"] = true

	# ── B — one machine deleted: its in-edge's kg back to the source, its
	#        out-edge's kg on to the target. Which edges hold kg at a given
	#        instant depends on each pipe's phase, so the machine is the first
	#        3B pass-through (one edge in, one out) with kg on both, away from
	#        the machines C deletes. ───────────────────────────────────────────
	_feed(20.0)
	var pt : Array = _pass_through([screw, rafter, dw1, fs1])
	_check(not pt.is_empty(),
		"B0 a 3B machine with one edge in and one out, both carrying kg, exists before the delete (not a vacuous 0)")
	if pt.is_empty():
		return
	var src : Node3D = pt[0]
	var mid : Node3D = pt[1]
	var dst : Node3D = pt[2]
	var into_m : float = _edge_kg(src, mid)
	var out_m : float = _edge_kg(mid, dst)
	var mid_held : float = _held(mid)
	var src_out0 : float = (_nd(src)["out"] as MaterialBatch).mass_kg
	var dst_in0 : float = (_nd(dst)["in"] as MaterialBatch).mass_kg
	var r6 : float = _residual()
	var np0 : int = _no_path_errors()
	_info("B: deleting %s#%d; %s#%d -> it %.4f kg, it -> %s#%d %.4f kg, it holds %.4f kg" % [
		String(mid.get_meta("placeable_id")), int(mid.get_meta("macro_index")),
		String(src.get_meta("placeable_id")), int(src.get_meta("macro_index")), into_m,
		String(dst.get_meta("placeable_id")), int(dst.get_meta("macro_index")), out_m, mid_held])
	_delete(mid)
	_lf.call("rebuild")
	var carry_b : Dictionary = _lf.get("last_pipe_carry")
	var src_out1 : float = (_nd(src)["out"] as MaterialBatch).mass_kg
	var dst_in1 : float = (_nd(dst)["in"] as MaterialBatch).mass_kg
	var r7 : float = _residual()
	_check(absf((src_out1 - src_out0) - into_m) < 1e-9,
		"B1 the kg on its in-edge are back in the source's out batch (+%.4f kg, the edge held %.4f)" % [src_out1 - src_out0, into_m])
	_check(absf((dst_in1 - dst_in0) - out_m) < 1e-9,
		"B2 the kg on its out-edge went on into the target (+%.4f kg, the edge held %.4f)" % [dst_in1 - dst_in0, out_m])
	_check(absf((r7 - r6) - mid_held) < LEDGER_EPS,
		"B3 the ledger moved by exactly what the deleted machine itself held (%.9f kg, it held %.9f)" % [r7 - r6, mid_held])
	_check(absf(float(carry_b.get("to_source", -1.0)) - into_m) < 1e-9
		and absf(float(carry_b.get("to_target", -1.0)) - out_m) < 1e-9 and float(carry_b.get("lost", -1.0)) == 0.0,
		"B4 LineFlow reports it (%s)" % str(carry_b))
	_check(_no_path_errors() == np0,
		"B5 no engine 'Cannot get path' error from rebuild() after a BuildMode-style delete (%d new)" % (_no_path_errors() - np0))
	_reached["B"] = true

	# ── C — two adjacent machines deleted in one rebuild: only the connector
	#        between them has no end left ─────────────────────────────────────
	_feed(20.0)
	var sc_ra : float = _edge_kg(screw, rafter)
	var ra_dw : float = _edge_kg(rafter, dw1)
	var dw_fs : float = _edge_kg(dw1, fs1)
	var held2 : float = _held(rafter) + _held(dw1)
	var screw_out0 : float = (_nd(screw)["out"] as MaterialBatch).mass_kg
	var fs_in0 : float = (_nd(fs1)["in"] as MaterialBatch).mass_kg
	var r8 : float = _residual()
	_info("C: M11a -> rafter %.4f, rafter -> dewater %.4f, dewater -> friction %.4f kg; rafter + dewater hold %.4f kg" % [
		sc_ra, ra_dw, dw_fs, held2])
	_check(sc_ra > 0.01 and ra_dw > 0.01 and dw_fs > 0.01,
		"C0 the three edges around the rafter and the dewater screw carry kg (not a vacuous 0)")
	_delete(rafter)
	_delete(dw1)
	_lf.call("rebuild")
	var carry_c : Dictionary = _lf.get("last_pipe_carry")
	var r9 : float = _residual()
	_check(absf(float(carry_c.get("lost", -1.0)) - ra_dw) < 1e-9
		and absf((_nd(screw)["out"] as MaterialBatch).mass_kg - screw_out0 - sc_ra) < 1e-9
		and absf((_nd(fs1)["in"] as MaterialBatch).mass_kg - fs_in0 - dw_fs) < 1e-9,
		"C1 only the rafter -> dewater kg are lost (%.4f); M11a got its out-edge's kg back and the friction separator its in-edge's (%s)" % [ra_dw, str(carry_c)])
	_check(absf((r9 - r8) - (held2 + ra_dw)) < LEDGER_EPS,
		"C2 the ledger moved by exactly the two machines' own kg plus the connector between them (%.6f kg, expected %.6f)" % [r9 - r8, held2 + ra_dw])
	_reached["C"] = true
