extends Node
## LINES 1 AND 3A — the granulate leaves the extruder and reaches the weegschaal.
##
##   godot --headless --path . res://src/tests/test_line1_pellet_side.tscn
##
## WHY THIS FILE EXISTS. extruder_1 and extruder_3a are MachineFlow `sink`s with
## an explicit edge to their laser filter. Until #338 (2026-09-26) LineFlow
## banked everything a sink took as granulaat, so on lines 1 and 3A the whole
## pellet side (laser filter, heetafslag, centrifuge, weegschaal, voorraad_silo)
## carried 0 kg, and nothing noticed: test_line1_throughput prints its granulate
## as an ungated info line, and its bench never starts the extruder (since
## 2026-09-25 the extruder owns its flow node and natraject; the line's start no
## longer runs them). #338 made a sink with a downstream edge pass its output on,
## so only a line's LAST node banks. This suite gates that, by name and by kg.
##
## The bench: BuildMode._build_full_line("line_1") and ("line_3a"), LineFlow
## driven by hand at 0.1 s (set_process(false) after add_child), each extruder
## brain unhooked from SimTick and stepped with it, started the HMI way
## (`_pending["start_production"]`), the melt held at its setpoint so the start
## sequence does not wait out a 30-min preheat. kg are put straight into the
## extruder node's input: the shredder, the wash line and the silo feed stops are
## other suites' business (test_line1_throughput, test_extruder_silo_feed_stop).
## A bare BuildMode never saves; nothing here writes world_layout.json.
##
## Checks, per line:
##   P0 the fixture: the brain, the extruder a `sink` WITH an out-edge (the
##      branch #338 changed), the pellet chain in order down to a terminal
##      voorraad_silo;
##   P1 the extruder RUNNING at its setpoint when the feed starts, and still
##      RUNNING at the end (anti-vacuity: a stopped screw moves nothing);
##   P2 the kg fed really entered the extruder;
##   P3 the extruder banks nothing itself: what it moved reached the laser
##      filter's input;
##   P4 kg pass laser_filter, heetafslag, centrifuge and weegschaal;
##   P5 granulaat grows only at the line ends: every tick's gran_mass step
##      equals what the terminal sinks moved that tick, the ends together banked
##      the kg, and voorraad_silo got its share (3A splits with its bigbag
##      station; the split is printed, not gated).

const DT : float = 0.1
const WATCHDOG_S : float = 600.0
const FEED_KG_S : float = 0.26        # ~950 kg/h, as test_extruder_start_interlock
const START_S : float = 60.0          # the natraject + screw start took 20-30 s on 3B
const FEED_S : float = 60.0
const DRAIN_S : float = 120.0
const PASS_FRAC : float = 0.90        # of the kg the extruder moved, measured, see the log
const LINES := {"line_1": "extruder_1", "line_3a": "extruder_3a"}
const CHAIN : Array[String] = ["laser_filter", "heetafslag", "centrifuge", "weegschaal"]
## The line ENDS, by name. 3A's weegschaal also feeds a bigbag station (doc edge
## 36, lijn_3a_flow.md; gap 2.2 ruled it 3A only), a sink like the silo.
const ENDS := {"line_1": ["voorraad_silo"], "line_3a": ["bigbag_station", "voorraad_silo"]}

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _lf : Node = null
var _brains : Array = []
var _moved : Dictionary = {}          # flow body instance id -> Σ _moved_kg
var _t : float = 0.0
var _gran_steps : float = 0.0         # Σ gran_mass increments
var _silo_moved : float = 0.0         # Σ _moved_kg of the line ends
var _worst_tick_err : float = 0.0     # max |gran step − line ends' moved| over ticks
var _silos : Array = []


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
	print("=== lines 1 and 3A: the granulate passes the pellet side, only voorraad_silo banks ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	# Watchdog: a runtime SCRIPT ERROR aborts the coroutine and the scene would
	# idle forever with no verdict (CLAUDE.md, "a headless run that outlives...").
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


func _step_world() -> void:
	for b in _brains:
		for key in ["_laser_filter", "_head_filter"]:
			var f = b.get(key)
			if f != null and is_instance_valid(f) and f.has_method("_physics_process"):
				f.call("_physics_process", DT)
		b.call("_on_sim_tick", DT)
	var g0 : float = float(_lf.get("gran_mass"))
	_lf.call("tick", DT)
	_t += DT
	for nd in (_lf.get("_nodes") as Array):
		var body = (nd as Dictionary).get("node", null)
		if body == null or not is_instance_valid(body):
			continue
		var bid : int = (body as Object).get_instance_id()
		_moved[bid] = float(_moved.get(bid, 0.0)) + float((nd as Dictionary).get("_moved_kg", 0.0))
	var dg : float = float(_lf.get("gran_mass")) - g0
	var ds : float = 0.0
	for s in _silos:
		ds += float(_nd(s).get("_moved_kg", 0.0))
	_gran_steps += dg
	_silo_moved += ds
	_worst_tick_err = maxf(_worst_tick_err, absf(dg - ds))


func _nd(body: Node3D) -> Dictionary:
	return _lf.call("node_for_body", body)


## kg a flow node has taken: processed + still in its input buffer.
func _received(body: Node3D) -> float:
	var nd := _nd(body)
	var bin = nd.get("in", null)
	return float(_moved.get(body.get_instance_id(), 0.0)) + (float(bin.mass_kg) if bin != null else 0.0)


func _flow_body(id: String, macro: String) -> Node3D:
	for e in _lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		if String(e["id"]) == id and String(b.get_meta("macro_id", "")) == macro:
			return b
	return null


## The flow path from `body` along out-edges, as placeable ids, until a node
## with no out-edge (or a branch: then the first edge, printed as such).
func _path_from(body: Node3D) -> Array:
	var nodes : Array = _lf.get("_nodes")
	var outs : Dictionary = {}
	for e in (_lf.get("_edges") as Array):
		var a : int = int((e as Dictionary)["a"])
		if not outs.has(a):
			outs[a] = []
		(outs[a] as Array).append(int((e as Dictionary)["b"]))
	var i : int = -1
	for j in nodes.size():
		if (nodes[j] as Dictionary).get("node", null) == body:
			i = j
			break
	var path : Array = []
	var seen : Dictionary = {}
	while i >= 0 and not seen.has(i):
		seen[i] = true
		var nd : Dictionary = nodes[i]
		path.append({"id": String(nd.get("id", "?")), "role": String(nd.get("role", "")),
			"outs": (outs.get(i, []) as Array).size(), "node": nd.get("node", null)})
		i = int((outs[i] as Array)[0]) if outs.has(i) else -1
	return path


## Every node reachable from `body` along out-edges that has no out-edge.
func _ends_from(body: Node3D) -> Array:
	var nodes : Array = _lf.get("_nodes")
	var outs : Dictionary = {}
	for e in (_lf.get("_edges") as Array):
		var a : int = int((e as Dictionary)["a"])
		if not outs.has(a):
			outs[a] = []
		(outs[a] as Array).append(int((e as Dictionary)["b"]))
	var todo : Array = []
	for j in nodes.size():
		if (nodes[j] as Dictionary).get("node", null) == body:
			todo.append(j)
	var seen : Dictionary = {}
	var ends : Array = []
	while not todo.is_empty():
		var i : int = todo.pop_back()
		if seen.has(i):
			continue
		seen[i] = true
		if not outs.has(i):
			ends.append(nodes[i])
		else:
			todo.append_array(outs[i])
	return ends


func _run() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	bm.call("_build_full_line", "line_3a", Vector3(1000.0, 0.0, 0.0), 0.0)
	# Unhook every brain from SimTick before a frame passes: they are stepped
	# by hand below, together with LineFlow.
	var st : Node = get_node("/root/SimTick")
	var brain_of : Dictionary = {}
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
		var par : Node = em.get_parent()
		if par != null:
			brain_of[String(par.get_meta("macro_id", ""))] = em
	_lf = LineFlow.new()
	add_child(_lf)
	_lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	await get_tree().process_frame
	_lf.call("rebuild")
	_lf.call("start_line")

	# ── P0 the fixture ───────────────────────────────────────────────────────
	var ex : Dictionary = {}
	var parts : Dictionary = {}          # line -> {id: body}
	for line in LINES:
		var brain : Node = brain_of.get(line, null)
		var body : Node3D = _flow_body(String(LINES[line]), line)
		_check(brain != null and body != null and brain.get_parent() == body,
			"P0 %s: %s is a flow node with its own extruder brain" % [line, LINES[line]])
		if brain == null or body == null:
			return
		_brains.append(brain)
		ex[line] = body
		var path : Array = _path_from(body)
		var ids : Array = path.map(func(p): return String(p["id"]))
		_info("%s flow path from the extruder: %s" % [line, " -> ".join(ids)])
		_check(String(path[0]["role"]) == "sink" and int(path[0]["outs"]) > 0,
			"P0 %s: %s is a `sink` WITH an out-edge (role '%s', %d out) — the branch #338 changed"
			% [line, LINES[line], path[0]["role"], int(path[0]["outs"])])
		var at : int = 0
		var order_ok : bool = true
		for id in CHAIN:
			var k : int = ids.find(id, at)
			order_ok = order_ok and k >= 0
			at = maxi(k + 1, at)
		_check(order_ok, "P0 %s: the path runs %s in that order" % [line, " > ".join(CHAIN)])
		var ends : Array = _ends_from(body)
		var end_ids : Array = ends.map(func(nd): return String(nd.get("id", "?")))
		end_ids.sort()
		var sinks_ok : bool = true
		for nd in ends:
			sinks_ok = sinks_ok and String(nd.get("role", "")) == "sink"
		_check(end_ids == ENDS[line] and sinks_ok,
			"P0 %s: everything the extruder feeds ends at %s, all `sink`s (got %s)" % [line, str(ENDS[line]), str(end_ids)])
		var bodies : Dictionary = {}
		for id in CHAIN:
			bodies[id] = _flow_body(id, line)
		for id in ENDS[line]:
			bodies[id] = _flow_body(id, line)
		parts[line] = bodies
		if bodies["voorraad_silo"] == null or end_ids != ENDS[line]:
			return
		for id in ENDS[line]:
			_silos.append(bodies[id])

	# ── P1 the HMI press, both lines at once ─────────────────────────────────
	for b in _brains:
		var m : ExtruderModel = b.get("model")
		m.melt_temp = m.config.melt_temp_setpoint
		(b.get("_pending") as Dictionary)["start_production"] = true
	var run_t : Dictionary = {}
	for _i in range(int(START_S / DT)):
		for b in _brains:   # probe-only shortcut: the melt held above green, no 30-min preheat
			var m : ExtruderModel = b.get("model")
			m.melt_temp = maxf(m.melt_temp, float(m.call("_preheat_ready_temp")) + 1.0)
		_step_world()
		for line in LINES:
			var mm : ExtruderModel = brain_of[line].get("model")
			if mm.state == ExtruderModel.State.RUNNING and not run_t.has(line):
				run_t[line] = _t
		if run_t.size() == LINES.size():
			break
	for line in LINES:
		var m : ExtruderModel = brain_of[line].get("model")
		_check(m.state == ExtruderModel.State.RUNNING and bool(_nd(ex[line]).get("powered", false))
				and m.screw_rpm > 0.0,
			"P1 %s: the extruder is RUNNING %.1f s after the press at %.0f rpm, its flow node powered (state %s, alarm '%s')"
			% [line, float(run_t.get(line, -1.0)), m.screw_rpm,
				ExtruderModel.State.keys()[m.state], String(m.start_seq.alarm)])
	if run_t.size() != LINES.size():
		return

	# ── feed, then drain ─────────────────────────────────────────────────────
	# Only what the feed moves counts: reset the tallies the start left behind.
	_moved.clear()
	_gran_steps = 0.0
	_silo_moved = 0.0
	_worst_tick_err = 0.0
	var g_start : float = float(_lf.get("gran_mass"))
	var fed : float = 0.0
	var feed_tick : float = FEED_KG_S * DT
	for _i in range(int(FEED_S / DT)):
		for line in LINES:
			(_nd(ex[line])["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick,
				feed_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "pellet_side", 0.0, 0.0))
		fed += feed_tick
		_step_world()
	for _i in range(int(DRAIN_S / DT)):
		_step_world()

	# ── P1-P4 per line ───────────────────────────────────────────────────────
	for line in LINES:
		var m : ExtruderModel = brain_of[line].get("model")
		_check(m.state == ExtruderModel.State.RUNNING,
			"P1 %s: still RUNNING after %.0f s feed + %.0f s drain (state %s, fault '%s')"
			% [line, FEED_S, DRAIN_S, ExtruderModel.State.keys()[m.state], String(m.fault_reason)])
		var ex_moved : float = float(_moved.get((ex[line] as Node3D).get_instance_id(), 0.0))
		_check(fed > 1.0 and ex_moved >= PASS_FRAC * fed,
			"P2 %s: the kg fed entered and left the extruder (fed %.2f kg, it moved %.2f)" % [line, fed, ex_moved])
		var bodies : Dictionary = parts[line]
		var got : Array = (CHAIN + ENDS[line]).map(func(id): return "%s %.2f" % [id, _received(bodies[id]) if bodies[id] != null else -1.0])
		_info("%s kg received after %.0f s feed + %.0f s drain (fed %.2f, extruder moved %.2f): %s"
			% [line, FEED_S, DRAIN_S, fed, ex_moved, ", ".join(got)])
		var lf_got : float = _received(bodies["laser_filter"]) if bodies["laser_filter"] != null else 0.0
		_check(ex_moved > 1.0 and absf(lf_got - ex_moved) <= 0.01 * ex_moved,
			"P3 %s: %s banks nothing itself — the laser filter received what it moved (%.2f of %.2f kg)"
			% [line, LINES[line], lf_got, ex_moved])
		for id in ["laser_filter", "heetafslag", "centrifuge", "weegschaal"]:
			var r : float = _received(bodies[id]) if bodies[id] != null else 0.0
			_check(ex_moved > 1.0 and r >= PASS_FRAC * ex_moved,
				"P4 %s: kg pass the %s (%.2f of %.2f kg, >= %.0f %%)" % [line, id, r, ex_moved, PASS_FRAC * 100.0])
		var banked : float = 0.0
		for id in ENDS[line]:
			banked += float(_moved.get((bodies[id] as Node3D).get_instance_id(), 0.0))
		var silo_banked : float = float(_moved.get((bodies["voorraad_silo"] as Node3D).get_instance_id(), 0.0))
		_check(banked >= PASS_FRAC * ex_moved and silo_banked >= 0.25 * ex_moved,
			"P5 %s: the line ends banked %.2f kg as granulaat (>= %.0f %% of %.2f), voorraad_silo %.2f of it (>= 25 %%)"
			% [line, banked, PASS_FRAC * 100.0, ex_moved, silo_banked])

	# ── P5 the bank, both lines ──────────────────────────────────────────────
	var g_total : float = float(_lf.get("gran_mass")) - g_start
	_check(g_total > 1.0 and absf(_gran_steps - _silo_moved) <= 1e-3 and _worst_tick_err <= 1e-4,
		"P5 granulaat grows only at the line ends: +%.3f kg banked, the ends moved %.3f kg, worst tick %.6f kg"
		% [g_total, _silo_moved, _worst_tick_err])


func _finish() -> void:
	if _done:
		return
	_done = true
	if _lf != null and is_instance_valid(_lf):
		for b in _brains:
			if b != null and is_instance_valid(b):
				_lf.call("release_nodes", b)
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 and _oks > 0 else "FAIL", _oks, _fails])
	get_tree().quit(0 if _fails == 0 and _oks > 0 else 1)
