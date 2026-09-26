extends Node
## PROBE (not a suite): how many LineFlow ticks run BEFORE the suite's own
## rebuild() decides test_extruder_silo_feed_stop's S3 check.
##
##   godot --headless --path . res://src/tests/probe_feed_stop_pre_ticks.tscn -- <k>
##
## test_extruder_silo_feed_stop adds its LineFlow in the frame that builds three
## lines, awaits one frame, then calls rebuild(). With LineFlow's _process on,
## that awaited frame ticks it on frame time: floor(delta / 0.1) ticks, where
## delta is how long the frame before it took (capped at 1 s, 10 ticks). The
## level sensor's clock lives in `_silo_state`, keyed by the silo body, and
## rebuild() does not reset it, so those ticks shift every sensor report, the
## 100 % stop included, against the suite's own ticks.
##
## This probe switches _process off after add_child and runs exactly <k> ticks
## by hand where the frame ticks used to land, then the S1/S2 feed of the suite
## (950 kg/h at 3B's VSS and line 1's opzetband, extruders off, 20 + 5 min), and
## prints the S3 numbers plus what was on its way into the stopped screw.
## docs/audit/lineflow_set_process_2026-09-26.md.

const DT : float = 0.1
const FEED_KG_H : float = 950.0
const FEED_S : float = 1200.0
const SETTLE_S : float = 300.0
const WATCHDOG_S : float = 420.0

var _lf : Node = null
var _done : bool = false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame
	var k := 0
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		k = int(args[0])
	await _run(k)
	_done = true
	get_tree().quit(0)


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("PROBE: watchdog — no result after %.0f s" % WATCHDOG_S)
	get_tree().quit(2)


func _at(macro: String, idx: int) -> Node3D:
	for e in _lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		if String(b.get_meta("macro_id", "")) == macro and int(b.get_meta("macro_index", -1)) == idx:
			return b
	return null


func _seq_idx(seq: Array, id: String, from: int = 0) -> int:
	for i in range(from, seq.size()):
		if String((seq[i] as Dictionary).get("id", "")) == id:
			return i
	return -1


## kg riding the connectors whose target is `body`.
func _inflight_into(body: Node3D) -> float:
	var bi : int = int(_lf.call("_nd_for_body", body))
	var kg := 0.0
	for e in _lf.get("_edges"):
		if int(e["b"]) == bi:
			for st in (e["pipe"] as Array):
				kg += (st as MaterialBatch).mass_kg
	return kg


## Where the kg sit around the stop: the VSS's in/out batches and power, the
## connector into the screw, the screw's in/out batches and power.
func _where(k: int, tag: String, vss: Node3D, screw: Node3D) -> void:
	var v : Dictionary = _lf.call("node_for_body", vss)
	var s : Dictionary = _lf.call("node_for_body", screw)
	print("PROBE k=%d: %s: VSS buffer %.2f in %.3f out %.3f powered %s spin %.2f moved %.3f | connector %.3f | screw in %.3f out %.3f buffer %.3f powered %s spin %.2f moved %.3f"
		% [k, tag, float(v.get("buffer", 0.0)), (v["in"] as MaterialBatch).mass_kg, (v["out"] as MaterialBatch).mass_kg,
			str(v.get("powered")), float(v.get("spin", -1.0)), float(v.get("_moved_kg", 0.0)),
			_inflight_into(screw), (s["in"] as MaterialBatch).mass_kg, (s["out"] as MaterialBatch).mass_kg,
			float(s.get("buffer", 0.0)), str(s.get("powered")), float(s.get("spin", -1.0)), float(s.get("_moved_kg", 0.0))])
	var nodes : Array = _lf.get("_nodes")
	var si : int = int(_lf.call("_nd_for_body", screw))
	for e in _lf.get("_edges"):
		if int(e["b"]) == si or int(e["a"]) == si:
			var kg := 0.0
			for st in (e["pipe"] as Array):
				kg += (st as MaterialBatch).mass_kg
			print("PROBE k=%d:     edge %s#%d -> %s#%d: %.3f kg in %d stages" % [k,
				String((nodes[int(e["a"])] as Dictionary).get("id", "?")), int(e["a"]),
				String((nodes[int(e["b"])] as Dictionary).get("id", "?")), int(e["b"]), kg, (e["pipe"] as Array).size()])


func _run(k: int) -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	bm.call("_build_full_line", "line_1", Vector3(400.0, 0.0, 0.0), 0.0)
	bm.call("_build_full_line", "line_3a", Vector3(800.0, 0.0, 0.0), 0.0)
	var st : Node = get_node("/root/SimTick")
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
	_lf = LineFlow.new()
	add_child(_lf)
	_lf.set_process(false)
	for _i in k:                       # the frame ticks, by hand
		_lf.call("tick", DT)
	await get_tree().process_frame
	_lf.call("rebuild")
	var silo3b : Node3D = _at("line_3b", _seq_idx(BuildMode.LINE_3B_SEQ, "extruder_silo"))
	var screw3b : Node3D = _at("line_3b", _seq_idx(BuildMode.LINE_3B_SEQ, "transport_screw",
		_seq_idx(BuildMode.LINE_3B_SEQ, "vuilsnippersilo")))
	var vss3b : Node3D = _at("line_3b", _seq_idx(BuildMode.LINE_3B_SEQ, "vss_silo"))
	var head1 : Node3D = _at("line_1", _seq_idx(BuildMode.LINE_1_SEQ, "opzetband_1"))
	if silo3b == null or screw3b == null or vss3b == null or head1 == null:
		print("PROBE: fixture incomplete")
		return
	var ss : Dictionary = (_lf.get("_silo_state") as Dictionary).get(silo3b.get_instance_id(), {})
	print("PROBE k=%d: after rebuild the 3B sensor clock reads t=%.2f s, %d samples, %d reports"
		% [k, float(ss.get("t", 0.0)), int(ss.get("n", 0)), int(ss.get("reports", 0))])
	_lf.call("start_line")
	var feed_tick : float = FEED_KG_H / 3600.0 * DT
	var t := 0.0
	var full_t := -1.0
	var in_at_stop := -1.0
	var fly_at_stop := -1.0
	var in_prev := 0.0
	for i in int((FEED_S + SETTLE_S) / DT):
		if float(i) * DT < FEED_S:
			for head in [vss3b, head1]:
				((_lf.call("node_for_body", head) as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(
					feed_tick, feed_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		in_prev = float((_lf.call("node_for_body", screw3b) as Dictionary).get("buffer", 0.0))
		_lf.call("tick", DT)
		t += DT
		if full_t < 0.0 and float((_lf.call("silo_level_for", silo3b) as Dictionary)["pct"]) >= 100.0:
			full_t = t
			in_at_stop = float((_lf.call("node_for_body", screw3b) as Dictionary).get("buffer", 0.0))
			fly_at_stop = _inflight_into(screw3b)
			print("PROBE k=%d: stop at %.1f s; screw input %.3f kg (%.3f kg the tick before), %.3f kg in flight into it"
				% [k, full_t, in_at_stop, in_prev, fly_at_stop])
			_where(k, "at the stop", vss3b, screw3b)
		if full_t > 0.0 and t > full_t + 0.05 and t < full_t + 3.05:
			_where(k, "stop +%.1f s" % (t - full_t), vss3b, screw3b)
	var in_end : float = float((_lf.call("node_for_body", screw3b) as Dictionary).get("buffer", 0.0))
	var vss_kg : float = float((_lf.call("node_for_body", vss3b) as Dictionary).get("buffer", 0.0))
	print("PROBE k=%d: end: screw input %.3f kg, grew %.3f kg after the stop (S3 allows < 1.0: %s); in flight at the stop %.3f; VSS %.1f kg"
		% [k, in_end, in_end - in_at_stop, "PASS" if in_end - in_at_stop < 1.0 else "FAIL", fly_at_stop, vss_kg])
