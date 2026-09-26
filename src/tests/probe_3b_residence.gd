extends Node
## PROBE (not a suite): how long material takes through line 3B's wash line in
## the sim, how much the wash line holds while it runs, and how long a full VSS
## feeds the line with no supply. Asked by the operator's reading of
## test_extruder_silo_feed_stop S3 (2026-09-26): "~10 min from the VSS dosing
## screw to the extruder silo" and "a full VSS runs the line ~15 min" (his
## recollection, not a document).
##
##   godot --headless --path . res://src/tests/probe_3b_residence.tscn -- feed [kg_h]
##   godot --headless --path . res://src/tests/probe_3b_residence.tscn -- drain [kg]
##
## feed : kg_h (default 950, the suite's rate) into the VSS for FEED_RUN_S,
##        extruder off. Prints each machine's design rate, hold and connector
##        transit, the time the first kg reaches each one after the dosing screw
##        M11a (the line's meter) first moves, and at FEED_RUN_S the kg in the wash line
##        (dosing screw .. the last machine before the extruder silo, their
##        connectors, and the connector into the silo).
## drain: kg (default: the VSS's full level) put in the VSS, no feed; the time
##        until the VSS is empty, and its peak discharge.

const DT : float = 0.1
const WATCHDOG_S : float = 600.0
const FEED_RUN_S : float = 400.0

var _lf : Node = null
var _done : bool = false


func _ready() -> void:
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	var mode : String = args[0] if args.size() > 0 else "feed"
	var amount : float = float(args[1]) if args.size() > 1 else (950.0 if mode == "feed" else -1.0)
	await _run(mode, amount)
	_done = true
	get_tree().quit(0)


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("PROBE: watchdog — no result after %.0f s" % WATCHDOG_S)
	get_tree().quit(2)


func _nodes() -> Array:
	return _lf.get("_nodes")


func _edges() -> Array:
	return _lf.get("_edges")


func _name(i: int) -> String:
	var nd : Dictionary = _nodes()[i]
	var b = nd.get("node")
	var mi := -1
	if b != null and is_instance_valid(b):
		mi = int((b as Node3D).get_meta("macro_index", -1))
	return "%s[%d]" % [String(nd.get("id", "?")), mi]


func _pipe_kg(e: Dictionary) -> float:
	var kg := 0.0
	for st in (e["pipe"] as Array):
		kg += (st as MaterialBatch).mass_kg
	return kg


func _node_kg(i: int) -> float:
	var nd : Dictionary = _nodes()[i]
	return (nd["in"] as MaterialBatch).mass_kg + (nd["out"] as MaterialBatch).mass_kg


## Flow order from `from` along the out-edges (BFS), stopping at `stop_id`.
func _walk(from: int, stop_id: String) -> Array:
	var order : Array = [from]
	var seen := {from: true}
	var q : Array = [from]
	while not q.is_empty():
		var a : int = q.pop_front()
		if String((_nodes()[a] as Dictionary).get("id", "")) == stop_id:
			continue
		for e in _edges():
			if int(e["a"]) == a and not seen.has(int(e["b"])):
				seen[int(e["b"])] = true
				order.append(int(e["b"]))
				q.append(int(e["b"]))
	return order


func _run(mode: String, amount: float) -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
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
	var vss := -1
	var silo := -1
	for i in _nodes().size():
		var id : String = String((_nodes()[i] as Dictionary).get("id", ""))
		if id == "vss_silo":
			vss = i
		elif id == "extruder_silo":
			silo = i
	if vss < 0 or silo < 0:
		print("PROBE: fixture incomplete (vss %d, silo %d)" % [vss, silo])
		return
	var order : Array = _walk(vss, "extruder_silo")
	var wash : Array = []          # the dosing screw .. the machine before the silo
	for i in order:
		var id : String = String((_nodes()[i] as Dictionary).get("id", ""))
		if i != vss and i != silo and id != "vuilsnippersilo":
			wash.append(i)
	print("PROBE %s: VSS_FULL_KG %.0f kg, SILO_FULL_KG %.0f kg, TRANSPORT_MPS %.1f m/s, MIN_TRANSIT_S %.1f s"
		% [mode, LineFlow.VSS_FULL_KG, LineFlow.SILO_FULL_KG, LineFlow.TRANSPORT_MPS, LineFlow.MIN_TRANSIT_S])
	var sum_transit := 0.0
	for i in order:
		var nd : Dictionary = _nodes()[i]
		var outs : Array = []
		for e in _edges():
			if int(e["a"]) == i and order.has(int(e["b"])):
				var tr : float = float(e["stage_dt"]) * float((e["pipe"] as Array).size())
				outs.append("-> %s %.1f m %.1f s%s" % [_name(int(e["b"])), float(e["len"]), tr, " (direct)" if bool(e.get("direct", false)) else ""])
		print("PROBE %s:   %-24s rate %6.2f kg/s (%5.0f kg/h) rpm_pct %.2f hold %5.1f s full %5.1f kg  %s"
			% [mode, _name(i), float(nd["rate"]), float(nd["rate"]) * 3600.0, float(nd.get("rpm_pct", 1.0)),
				float(nd.get("hold_s", 0.0)), float(nd.get("full_kg", 0.0)), ", ".join(outs)])
	print("PROBE %s: wash_timing(line_3b) = %s" % [mode, str(_lf.call("wash_timing", "line_3b"))])
	_lf.call("start_line")
	var t := 0.0
	if mode == "feed":
		var feed_tick : float = amount / 3600.0 * DT
		var t0 := -1.0
		var first := {}
		var meter := -1
		for i in order:
			if String((_nodes()[i] as Dictionary).get("id", "")) == "transport_screw":
				meter = i
				break
		for _i in int(FEED_RUN_S / DT):
			((_nodes()[vss] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick,
				feed_tick / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
			_lf.call("tick", DT)
			t += DT
			if t0 < 0.0 and meter >= 0 and float((_nodes()[meter] as Dictionary).get("_moved_kg", 0.0)) > 0.0:
				t0 = t
			for i in order:
				if not first.has(i) and float((_nodes()[i] as Dictionary).get("buffer", 0.0)) > 0.0:
					first[i] = t
		for i in order:
			print("PROBE feed: first kg at %-24s %6.1f s after the dosing screw first moved (t %.1f)"
				% [_name(i), float(first.get(i, -1.0)) - t0, float(first.get(i, -1.0))])
		var in_nodes := 0.0
		var in_pipes := 0.0
		var poly := 0.0
		for i in wash:
			in_nodes += _node_kg(i)
			poly += ((_nodes()[i] as Dictionary)["in"] as MaterialBatch).polymer_kg() 				+ ((_nodes()[i] as Dictionary)["out"] as MaterialBatch).polymer_kg()
			for e in _edges():
				if int(e["a"]) == i:
					in_pipes += _pipe_kg(e)
					for st2 in (e["pipe"] as Array):
						poly += (st2 as MaterialBatch).polymer_kg()
		var vss_to_screw := 0.0
		for e in _edges():
			if int(e["a"]) == vss:
				vss_to_screw += _pipe_kg(e)
		print("PROBE feed: at t %.0f s, fed %.0f kg/h: wash line holds %.1f kg (%.1f in %d machines, %.1f on their connectors); VSS %.1f kg + %.2f kg on its connector; extruder silo %.1f kg"
			% [t, amount, in_nodes + in_pipes, in_nodes, wash.size(), in_pipes, _node_kg(vss), vss_to_screw, _node_kg(silo)])
		print("PROBE feed: polymer in the wash line %.1f kg (the rest is process water) = %.1f s of feed at %.0f kg/h (operator, rulings W3: ~3 min = %.1f kg)"
			% [poly, poly / (amount / 3600.0), amount, amount / 20.0])
	elif mode == "slider":
		# The meter's two HMI sliders (MACHINES screen): the master rpm
		# (set_machine_rpm_pct) and its "drive" component
		# (set_machine_component_pct). kg/h over 60 s, fed a surplus.
		var meter := -1
		for i in order:
			if String((_nodes()[i] as Dictionary).get("id", "")) == "transport_screw":
				meter = i
				break
		var key : String = String((_nodes()[meter] as Dictionary)["key"])
		var steps : Array = [["start", "", 0.0], ["master", "", 0.5], ["drive", "drive", 0.5],
			["master", "", 1.0], ["drive", "drive", 1.0], ["master", "", 0.8]]
		for stp in steps:
			if String(stp[0]) == "master":
				_lf.call("set_machine_rpm_pct", key, float(stp[2]))
			elif String(stp[0]) == "drive":
				_lf.call("set_machine_component_pct", key, String(stp[1]), float(stp[2]))
			var moved := 0.0
			for i2 in int(90.0 / DT):
				((_nodes()[vss] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(0.08,
					0.08 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
				_lf.call("tick", DT)
				if i2 >= int(30.0 / DT):
					moved += float((_nodes()[meter] as Dictionary).get("_moved_kg", 0.0))
			var nd_m : Dictionary = _nodes()[meter]
			print("PROBE slider: after %-6s %s -> %.2f: rpm_pct %.2f, components %s, HMI shows %.0f rpm (master); M11a conveys %.1f kg/h"
				% [String(stp[0]), String(stp[1]), float(stp[2]), float(nd_m.get("rpm_pct", 0.0)),
					str(nd_m.get("components", {})), float(nd_m.get("rpm_pct", 0.0)) * 100.0, moved / 60.0 * 3600.0])
	else:
		# let the PLC power the whole line first, then fill the VSS and time it
		if amount < 0.0:
			amount = float((_nodes()[vss] as Dictionary).get("full_kg", 0.0))
			if amount <= 0.0:
				amount = LineFlow.VSS_FULL_KG
		for _i in int(30.0 / DT):
			_lf.call("tick", DT)
		((_nodes()[vss] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(amount,
			amount / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		var peak := 0.0
		var empty_t := -1.0
		for _i in int(1500.0 / DT):
			_lf.call("tick", DT)
			t += DT
			peak = maxf(peak, float((_nodes()[vss] as Dictionary).get("_moved_kg", 0.0)) / DT)
			if empty_t < 0.0 and (_nodes()[vss]["in"] as MaterialBatch).mass_kg < 0.5:
				empty_t = t
				break
		print("PROBE drain: %.1f kg in the powered VSS, no feed: empty (< 0.5 kg) after %.1f s = %.1f min; peak discharge %.3f kg/s (%.0f kg/h) (operator, rulings W2.8: a full VSS runs the line ~15 min)"
			% [amount, empty_t, empty_t / 60.0, peak, peak * 3600.0])
