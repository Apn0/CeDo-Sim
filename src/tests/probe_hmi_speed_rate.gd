extends Node
## PROBE (not a suite): what each HMI speed setting does to a machine's
## conveying rate, for every machine on one macro line.
##
##   godot --headless --path . res://src/tests/probe_hmi_speed_rate.tscn -- line_3b
##
## Written 2026-09-26 for docs/audit/hmi_rpm_rate_2026-09-26.md. The first
## measurement (probe_rpm_pct_rate, 3B, five machines) found that a rotor
## machine at rpm_pct 0.50 conveyed 0.250 of design; this one covers every node
## of a line and BOTH HMI setters:
##   - set_machine_rpm_pct(key, p) (the master setting; the web strip, tests);
##   - set_machine_component_pct(key, comp, p) for each of the node's
##     components (the MACHINES screen's per-motor sliders).
##
## The line is built alone, LineFlow is ticked by hand (set_process(false)
## AFTER add_child), started and run 60 s empty. Then, per node (first instance
## of each id): every setting back to 1.0, 50 kg parked in the input, the kg
## moved over 10 ticks of 0.1 s summed from `_moved_kg`. Each row prints the
## ratio against the same node's 1.0 run, so air, NIR wrap and the spin ramp
## cancel out. A node that moves nothing at 1.0 (an extruder the line does not
## start, a claimed node) is listed as NOFLOW.
##
## Also printed per node: its top-level rotors, whether `mech` (the rotor
## _mech_fraction reads) is a component-tagged rotor, and which components have
## tagged rotors of their own. Headless-safe; writes nothing but BuildMode's
## own layout under user:// (run it under a scratch APPDATA).

const DT : float = 0.1
const PARK_KG : float = 50.0

var _lf : Node = null


func _ready() -> void:
	get_tree().create_timer(300.0).timeout.connect(func():
		print("PROBE: watchdog")
		get_tree().quit(2))
	call_deferred("_run")


func _node_by_key(key: String) -> Dictionary:
	for n in (_lf.get("_nodes") as Array):
		if String(n.get("key", "")) == key:
			return n
	return {}


func _reset(nd: Dictionary) -> void:
	var key := String(nd["key"])
	for c in (nd.get("components", {}) as Dictionary).keys():
		_lf.call("set_machine_component_pct", key, String(c), 1.0)
	_lf.call("set_machine_rpm_pct", key, 1.0)


func _measure(nd: Dictionary) -> float:
	var bin : MaterialBatch = nd["in"] as MaterialBatch
	bin.split_mass(bin.mass_kg)
	bin.add(MaterialBatch.new(PARK_KG, PARK_KG / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
	var moved := 0.0
	for _i in 10:
		_lf.call("tick", DT)
		moved += float(nd.get("_moved_kg", 0.0))
	bin.split_mass(bin.mass_kg)
	return moved


func _run() -> void:
	var args := Array(OS.get_cmdline_user_args())
	var line_id : String = args[0] if args.size() > 0 else "line_3b"
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", line_id, Vector3.ZERO, 0.0)
	var st : Node = get_node_or_null("/root/SimTick")
	if st != null:
		for em in get_tree().get_nodes_in_group("extruder_machine"):
			var cb := Callable(em, "_on_sim_tick")
			if st.sim_tick.is_connected(cb):
				st.sim_tick.disconnect(cb)
	_lf = LineFlow.new()
	add_child(_lf)
	_lf.set_process(false)
	await get_tree().process_frame
	_lf.call("rebuild")
	_lf.call("start_line")
	for _i in int(60.0 / DT):
		_lf.call("tick", DT)

	var seen : Dictionary = {}
	var keys : Array = []
	for n in (_lf.get("_nodes") as Array):
		var id := String(n.get("id", ""))
		if seen.has(id):
			continue
		seen[id] = true
		keys.append(String(n["key"]))
	print("PROBE line %s: %d nodes, %d distinct ids" % [line_id, (_lf.get("_nodes") as Array).size(), keys.size()])
	for key in keys:
		var nd := _node_by_key(key)
		_lf.call("_cache_rotors", nd)
		_lf.call("_cache_component_rotors", nd)
		var rotors : Array = nd.get("rotors", [])
		var mech = nd.get("mech")
		var mech_comp := "-"
		if mech != null and is_instance_valid(mech):
			mech_comp = String(mech.get_meta("comp")) if mech.has_meta("comp") else "untagged"
		else:
			mech_comp = "none"
		var comps : Dictionary = nd.get("components", {})
		var tagged : Array = []
		for c in comps.keys():
			if (nd.get("component_rotors", {}) as Dictionary).has(c):
				tagged.append(String(c))
		var topo := String(LineFlow._component_topology(String(nd["id"])))
		_reset(nd)
		var base := _measure(nd)
		if base <= 0.0001:
			print("PROBE %-24s NOFLOW (rotors %d, mech %s, comps %s)" % [key, rotors.size(), mech_comp, str(comps.keys())])
			continue
		var cells : Array = []
		for p in [0.5, 0.25]:
			_reset(nd)
			_lf.call("set_machine_rpm_pct", key, p)
			cells.append("rpm_pct %.2f -> %.3f" % [p, _measure(nd) / base])
		for c in comps.keys():
			_reset(nd)
			_lf.call("set_machine_component_pct", key, String(c), 0.5)
			cells.append("%s 0.50 -> %.3f (rpm_pct now %.2f)" % [c, _measure(nd) / base, float(nd.get("rpm_pct", 1.0))])
		_reset(nd)
		print("PROBE %-24s rotors %d, mech %s, %s comps %s tagged %s, spin %.2f, base %.2f kg/s | %s"
			% [key, rotors.size(), mech_comp, topo, str(comps.keys()), str(tagged),
				float(nd["spin"]), base, " | ".join(cells)])
	print("PROBE done")
	get_tree().quit(0)
