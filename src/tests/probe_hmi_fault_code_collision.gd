extends Node
## PROBE (not a suite, not in run.sh) — do two extruders' 6557 alarms reach the
## operator as two alarms? Written 2026-09-24 for the "Open" item in
## docs/audit/hmi_fault_rearm_2026-09-24.md.
##
##   godot --headless --path . res://src/tests/probe_hmi_fault_code_collision.tscn
##
## _compute_faults() emits "EREMA-%04d" once per extruder; before the fix the
## overlay keyed first-seen, occurrence, history and shield by CODE, and read
## the line from `em.line_id`, which a real ExtruderMachine does not have (it
## is on config_resource), so both alarms read "EREMA-6557@extruder". Fixture:
## two real catalog extruders (3A, 3C) 100 m apart, each with a catalog laser
## filter beside it; each brain's SimTick handler is disconnected so it does
## not write 0.0 over the pressure. Pressure is written through each filter's
## own setter. The guard suite built from this is test_hmi_fault_per_line.
##
## Measured 2026-09-24 on main 500af33 and on b8bda8a (before #275), before
## the fix: step 3 bell amber, Actief 0 rows, Historie 1 row — the 3C trip
## never reached the operator.
##
## Sequence: A trips → KWITTEREN → B trips while A is still active → A clears
## while B is active → B clears. After every step it prints what the operator
## sees: the bell, the Actief rows and the Historie rows. Step 1 is the control
## (a lone 6557 must light the bell red).

const TRIP_BAR := 343.0
const CLEAR_BAR := 291.0
const _OV_SCENE := "res://src/scenes/hud/HmiOverlay.tscn"
const _OV_SCRIPT := "res://src/scenes/hud/HmiOverlay.gd"

var _ov : Node = null
var _ovs : Script = null

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = 60.0
	wd.timeout.connect(func():
		print("PROBE: watchdog — did not finish in 60 s")
		get_tree().quit(2))
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _live_buttons(root: Node) -> Array:
	var out : Array = []
	for n in root.find_children("*", "Button", true, false):
		if not n.is_queued_for_deletion():
			out.append(n)
	return out

func _press(text: String) -> void:
	for b in _live_buttons(_ov):
		if String((b as Button).text) == text:
			(b as Button).pressed.emit()
			return
	print("PROBE:   (no live button '%s')" % text)

func _bell_state() -> String:
	var sb := (_ov.get("_alarm_bell_btn") as Button).get_theme_stylebox("normal") as StyleBoxFlat
	var k := _ovs.get_script_constant_map()
	if sb.bg_color.is_equal_approx(k["C_NAV"]):
		return "none"
	if sb.bg_color.is_equal_approx(k["LAMP_IDLE"]):
		return "acked (amber)"
	return "UNACKED (red)"

func _tab_rows(tab_text: String) -> Array:
	_press(tab_text)
	var out : Array = []
	var box = _ov.get("_fault_box")
	if box == null:
		return out
	for row in (box as Node).get_children():
		if row.is_queued_for_deletion() or not (row is PanelContainer):
			continue
		var hb := row.get_child(0) as HBoxContainer
		if hb == null or hb.get_child_count() < 3:
			continue
		out.append("%s %s | %s" % [(hb.get_child(0) as Label).text,
			(hb.get_child(1) as Label).text, (hb.get_child(2) as Label).text])
	return out

func _set_bar(f: Node, bar: float) -> void:
	f.call("set_upstream_pressure_indicator", bar / 0.0689)

func _hold(s: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(s * 1000.0):
		await get_tree().process_frame

func _report(step: String) -> void:
	var faults : Array = []
	for f in _ov.call("_compute_faults"):
		faults.append("%s@%s" % [f["code"], f["scope"]])
	print("PROBE: == %s" % step)
	print("PROBE:    detected : %s" % [faults])
	print("PROBE:    bell     : %s" % _bell_state())
	var act := _tab_rows("Actief")
	print("PROBE:    Actief   : %d row(s)" % act.size())
	for r in act:
		print("PROBE:        %s" % r)
	var hist := _tab_rows("Historie")
	print("PROBE:    Historie : %d row(s)" % hist.size())
	for r in hist:
		print("PROBE:        %s" % r)

func _run() -> void:
	_ovs = load(_OV_SCRIPT)
	var lf := LineFlow.new()
	lf.name = "LineFlow"
	lf.add_to_group("line_flow")
	add_child(lf)
	lf.feed_enabled = false
	# Two REAL catalog extruders (brain attached by MachineBrains, real
	# ExtruderConfig with its line_id), each with its own laser filter. The
	# brain's SimTick handler is disconnected so it does not write 0.0 over the
	# pressure every tick while OFF; nothing else about it is touched.
	var filters : Array = []
	for i in 2:
		var id : String = ["extruder_3a", "extruder_3c"][i]
		var ex : Node3D = PlaceableCatalog.build_node(id, false)
		add_child(ex)
		ex.position = Vector3(100.0 * i, 0, 0)
		var f : Node3D = PlaceableCatalog.build_node("laser_filter", false)
		add_child(f)
		f.position = Vector3(100.0 * i, 0, 9)
		_set_bar(f, CLEAR_BAR)
		filters.append(f)
	await get_tree().process_frame
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var st : Node = get_node("/root/SimTick")
		if st.sim_tick.is_connected(em._on_sim_tick):
			st.sim_tick.disconnect(em._on_sim_tick)
		var cfg = em.get("config_resource")
		print("PROBE: brain %s  'line_id' in node=%s  config_resource.line_id=%s"
			% [em.get_path(), "line_id" in em, cfg.get("line_id") if cfg != null else "<none>"])

	_ov = (load(_OV_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_ov)
	await get_tree().process_frame
	var scope : Dictionary = (load("res://src/build/HmiScopes.gd") as Script).call("get_scope", "hmi_extruder_all")
	_ov.call("open_for", String(scope.get("label", "Extruder")), scope)
	(_ov.get("_alarm_bell_btn") as Button).pressed.emit()
	print("PROBE: overlay sees %d filter(s), %d extruder(s)"
		% [(_ov.get("_laser_filters") as Array).size(), (_ov.get("_extruder_machines") as Array).size()])
	await _hold(0.6)
	_report("0 baseline, both at %.0f bar" % CLEAR_BAR)

	_set_bar(filters[0], TRIP_BAR)
	await _hold(0.6)
	_report("1 CONTROL: 3A trips alone (%.0f bar)" % TRIP_BAR)

	_press("KWITTEREN")
	await _hold(0.6)
	_report("2 KWITTEREN")

	_set_bar(filters[1], TRIP_BAR)
	await _hold(0.6)
	_report("3 3C trips while acked 3A is still active")

	_set_bar(filters[0], CLEAR_BAR)
	await _hold(0.6)
	_report("4 3A clears, 3C still active")

	_set_bar(filters[1], CLEAR_BAR)
	await _hold(0.6)
	_report("5 3C clears")

	print("PROBE: done")
	_ov.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)
