extends Node
## PROBE (not a suite, not in run.sh): how long can a line feed an extruder
## that is OFF before LineFlow's overload e-stop fires?
##
##   godot --headless --path . res://src/tests/probe_extruder_off_backlog.tscn
##
## Since 2026-09-25 the extruder runs its own LineFlow node and natraject
## (operator rulings, docs/plant/operator_rulings_2026-09-25.md §I4): the
## line's start no longer makes an extruder that was never started convey. The
## material then waits at the extruder, and LineFlow e-stops the line upstream
## of the first machine whose input buffer passes OVERLOAD_KG (250 kg). The
## plant's silos hold far more than 250 kg; the sim's cap is its own.
##
## A real 3B line (BuildMode._build_full_line -> LineFlow.rebuild ->
## start_line), 950 kg/h fed at the blower before the extruder silo (as
## test_extruder_silo_chain), 60 min of sim time, the brain stepped by hand:
##   case OFF — the extruder is never started;
##   case ON  — the start button is pressed at t = 0 (control).

const DT : float = 0.1
const FEED_KG_H : float = 950.0
const RUN_S : float = 3600.0

var _t0 : int = 0


func _ready() -> void:
	_t0 = Time.get_ticks_msec()
	await get_tree().process_frame
	for case_on in [false, true]:
		await _case(case_on)
	print("PROBE DONE")
	get_tree().quit(0)


func _case(start_it: bool) -> void:
	print("== case %s ==" % ("ON (started at t=0)" if start_it else "OFF (never started)"))
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	var st : Node = get_node("/root/SimTick")
	var brain : Node = null
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
		brain = em
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	lf.call("start_line")
	var feed_body : Node3D = null
	var silo : Node3D = null
	var ex : Node3D = brain.get_parent()
	var seq : Array = BuildMode.LINE_3B_SEQ
	var mi_silo := -1
	for k in seq.size():
		if String((seq[k] as Dictionary).get("id", "")) == "extruder_silo":
			mi_silo = k
			break
	for e in lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		var mi : int = int(b.get_meta("macro_index", -1))
		if mi == mi_silo - 1:
			feed_body = b
		elif mi == mi_silo:
			silo = b
	var m : ExtruderModel = brain.get("model")
	if start_it:
		m.melt_temp = m.config.melt_temp_setpoint
		(brain.get("_pending") as Dictionary)["start_production"] = true
	var feed_tick : float = FEED_KG_H / 3600.0 * DT
	var fed := 0.0
	var estop_t := -1.0
	var estop_at := ""
	var next_report := 0.0
	for i in range(int(RUN_S / DT)):
		var t : float = i * DT
		var fnd : Dictionary = lf.call("node_for_body", feed_body)
		# Fed straight into the blower's input, as test_extruder_silo_chain does;
		# an e-stop powers the blower off and the kg then wait in front of it.
		(fnd["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick, feed_tick / LineFlow.FEED_DENSITY,
			LineFlow.DEFAULT_COMP.duplicate(), "probe", 0.0, 0.0))
		fed += feed_tick
		brain.call("_on_sim_tick", DT)
		lf.call("tick", DT)
		if bool(lf.get("_estop_active")) and estop_t < 0.0:
			estop_t = t + DT
			var fi : int = int(lf.get("_estop_fault_node"))
			estop_at = String(((lf.get("_nodes") as Array)[fi] as Dictionary).get("id", "?"))
			print("  E-STOP at %.0f s (%.1f min): overload at '%s', fed %.0f kg" % [estop_t, estop_t / 60.0, estop_at, fed])
		if t >= next_report:
			next_report += 300.0
			var exn : Dictionary = lf.call("node_for_body", ex)
			var sn : Dictionary = lf.call("node_for_body", silo)
			print("  t %5.0f s  fed %6.1f kg  extruder %-9s buffer %6.1f kg  silo buffer %6.1f kg  estop %s"
				% [t, fed, m.get_state_name(), float(exn.get("buffer", 0.0)), float(sn.get("buffer", 0.0)),
				str(lf.get("_estop_active"))])
		if estop_t > 0.0 and t > estop_t + 60.0:
			break
	print("  RESULT case %s: e-stop %s" % ["ON" if start_it else "OFF",
		("at %.0f s (%.1f min) on '%s'" % [estop_t, estop_t / 60.0, estop_at]) if estop_t > 0.0 else "none in %.0f min" % (RUN_S / 60.0)])
	lf.call("release_nodes", brain)
	lf.queue_free()
	bm.queue_free()
	for c in get_children():
		c.queue_free()
	await get_tree().process_frame
	await get_tree().process_frame
