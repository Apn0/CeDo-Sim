extends Node
## PROBE (not a suite): what an HMI rpm setpoint does to a machine's conveying
## rate. LineFlow's effective rate is rate x spin x _mech_fraction x rpm_pct x
## components, and set_machine_rpm_pct also sets every rotor's rpm to
## rpm_pct x nominal, which _mech_fraction reads back. So a machine with a rotor
## may convey at rpm_pct^2 of its design rate.
##
##   godot --headless --path . res://src/tests/probe_rpm_pct_rate.tscn
##
## 3B built alone, LineFlow ticked by hand. For each machine id below: set its
## rpm_pct, park 50 kg in its input, and measure what it moves in 1 s.

const DT : float = 0.1
const IDS : Array[String] = ["transport_screw", "rafter", "flotation_tank", "dewater_screw", "blower"]

var _lf : Node = null


func _ready() -> void:
	get_tree().create_timer(120.0).timeout.connect(func(): print("PROBE: watchdog"); get_tree().quit(2))
	await get_tree().process_frame
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
	_lf.call("start_line")
	for _i in int(30.0 / DT):
		_lf.call("tick", DT)
	var nodes : Array = _lf.get("_nodes")
	for id in IDS:
		var nd : Dictionary = {}
		for n in nodes:
			if String(n.get("id", "")) == id:
				nd = n
				break
		if nd.is_empty():
			print("PROBE: no %s" % id)
			continue
		for pct in [1.0, 0.5]:
			_lf.call("set_machine_rpm_pct", String(nd["key"]), pct)
			(nd["in"] as MaterialBatch).add(MaterialBatch.new(50.0, 50.0 / LineFlow.FEED_DENSITY,
				LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
			var moved := 0.0
			for _i in 10:
				_lf.call("tick", DT)
				moved += float(nd.get("_moved_kg", 0.0))
			print("PROBE %-16s rpm_pct %.2f: design rate %.2f kg/s, spin %.2f, mech_fraction %.3f, rotors %d, moved %.3f kg in 1 s = %.3f of design"
				% [id, pct, float(nd["rate"]), float(nd["spin"]), float(_lf.call("_mech_fraction", nd)),
					(nd.get("rotors", []) as Array).size(), moved, moved / float(nd["rate"])])
			(nd["in"] as MaterialBatch).split_mass((nd["in"] as MaterialBatch).mass_kg)
		_lf.call("set_machine_rpm_pct", String(nd["key"]), 1.0)
	get_tree().quit(0)
