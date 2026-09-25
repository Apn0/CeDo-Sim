extends Node

# =============================================================================
# Extruder motor torque through STOPPING follows the screw down from the torque
# the stop was entered at, the same at any tick size.
# =============================================================================
# Regression guard for the defect measured 2026-09-25
# (docs/audit/extruder_ramp_pressures_2026-09-25.md §5 item 3): `_tick_stopping`
# did `motor_torque_pct = motor_torque_pct * rpm_frac` every tick, so the torque
# followed the PRODUCT of every tick's rpm fraction. From a 60 % running torque
# (Extruder3B.tres, melt at setpoint, stop from nominal), 1.2 s into STOPPING
# (rpm 0.741 of nominal) it read 8.54 % = 0.142 of running at 0.1 s ticks and
# 1.41 % = 0.024 at 0.05 s ticks, and 0 by 4 s. That field is the "belasting"
# the BluPort rail, the HMI (ex_belasting) and SCADA show.
#
# The law now: torque = entry torque x rpm / entry rpm, where "entry" is the tick
# the stop was entered on. From the plant's raw EREMA archive (3A + 3B, load and
# speed logged in the same ~5 s cycle): 17 samples caught mid-stop across 83
# stops, load / entry load = 0.969 x rpm / entry rpm
# (tools/audit/fit_stop_load_vs_rpm.py, docs/audit/extruder_stop_torque_2026-09-25.md).
# screw_rpm decays as exp(-t / STOP_DECAY_S), so the reading depends on time only.
#
# The law checks read the entry off the model on the stop tick, so they do not
# hard-code 60 % or the decay constant.
#
#   godot --headless --path . res://src/tests/test_extruder_stop_torque.tscn
#
# Part A drives a bare ExtruderModel from Extruder3B.tres. Part B drives the REAL
# catalog extruder_3b (build_node -> MachineBrains) through its SimTick handler,
# with a real LaserFilter and HeadFilter, and reads the load off a real
# ExtruderBluPortScope bound to its model. No MainWorld boot, no user:// writes.
# Exits 0 on pass, 1 on failure, 2 on the watchdog.
# =============================================================================

const DT : float = 0.1
const WATCHDOG_S : float = 180.0
const CFG_PATH := "res://src/data/machines/Extruder3B.tres"
const LAW_TOL_PCT : float = 0.001      # the law is exact: same inputs, same formula
const TICK_TOL_PCT : float = 0.05      # the same stop at 0.1 s and 0.05 s ticks
const RUN_TO_NOMINAL_S : float = 300.0 # the start + the raise to nominal, then steady
const STOP_PROBE_S : float = 1.2       # where the defect was first measured
const MARKS : Array = [1.2, 4.0, 8.0]
const ZONE_DROP_C : float = 30.0       # 60 % + 30 °C x 2 %/°C = 120 %, over the 110 % trip
const SETPOINT_BELOW_NOMINAL_RPM : float = 80.0

var _oks : int = 0
var _fails : int = 0
var _done : bool = false


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
	print("=== extruder stop torque (STOPPING follows the rpm down) ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	# Watchdog: a runtime SCRIPT ERROR aborts _ready() and the scene would idle
	# forever with no verdict (CLAUDE.md, "a headless run that outlives...").
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame

	var cfg := load(CFG_PATH) as ExtruderConfig
	_check(cfg != null, "Extruder3B.tres loads")
	if cfg == null:
		_finish()
		return

	_check_stopping(cfg)
	_check_tick_size(cfg)
	_check_no_trip_in_stopping(cfg)
	_check_second_stop(cfg)
	await _check_wired_rig()
	_finish()


# ── helpers ───────────────────────────────────────────────────────────────────
func _running_model(cfg: ExtruderConfig, dt: float) -> ExtruderModel:
	var m := ExtruderModel.new(cfg.duplicate())
	m.melt_temp = m.config.melt_temp_setpoint
	m.tick(dt, {"start_production": true})
	# A new extruder's rpm setpoint is 60 (operator 2026-09-25); these stops
	# are from NOMINAL, so raise it as the player does.
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
	for _i in range(int(RUN_TO_NOMINAL_S / dt)):
		m.tick(dt, {})
	return m

## Press stop on `m` and follow it to OFF. The stop tick is the entering state's
## own tick, then the transition; the entry is read off the model right after it.
## Returns {entry_t, entry_rpm, ticks, worst, rising, lumps, trip, fault, off,
## off_t, marks: {t: torque}, rpm_marks: {t: rpm}}.
func _stop_and_follow(m: ExtruderModel, dt: float, marks: Array) -> Dictionary:
	var out := {"entry_t": 0.0, "entry_rpm": 0.0, "ticks": 0, "worst": 0.0, "rising": 0,
		"lumps": 0, "trip": false, "fault": false, "off": false, "off_t": -1.0,
		"marks": {}, "rpm_marks": {}}
	var ev := m.tick(dt, {"stop_production": true})
	if ev.has("motor_torque_trip"):
		out["trip"] = true
	out["entry_t"] = m.motor_torque_pct
	out["entry_rpm"] = m.screw_rpm
	var entry_t : float = m.motor_torque_pct
	var entry_rpm : float = maxf(m.screw_rpm, 0.001)
	var prev : float = entry_t
	var t := 0.0
	var k := 0
	for _i in range(int(60.0 / dt)):
		if m.state != ExtruderModel.State.STOPPING:
			break
		ev = m.tick(dt, {})
		t += dt
		if ev.has("motor_torque_trip"):
			out["trip"] = true
		if m.state == ExtruderModel.State.FAULT:
			out["fault"] = true
		# The tick that ends in the OFF transition still ran _tick_stopping.
		out["ticks"] = int(out["ticks"]) + 1
		var want : float = entry_t * clampf(m.screw_rpm / entry_rpm, 0.0, 1.0)
		out["worst"] = maxf(float(out["worst"]), absf(m.motor_torque_pct - want))
		if m.motor_torque_pct > prev + 1e-6:
			out["rising"] = int(out["rising"]) + 1
		if m.lump_passthrough_rate_g_s > 0.0:
			out["lumps"] = int(out["lumps"]) + 1
		prev = m.motor_torque_pct
		if k < marks.size() and t + dt * 0.5 >= float(marks[k]):
			out["marks"][marks[k]] = m.motor_torque_pct
			out["rpm_marks"][marks[k]] = m.screw_rpm
			k += 1
	if m.state == ExtruderModel.State.OFF:
		out["off"] = true
		m.tick(dt, {})
		out["off_t"] = m.motor_torque_pct
	return out


# ── A. bench model ────────────────────────────────────────────────────────────
func _check_stopping(cfg: ExtruderConfig) -> void:
	var m := _running_model(cfg, DT)
	var run_t : float = m.motor_torque_pct
	_check(m.state == ExtruderModel.State.RUNNING and absf(run_t - cfg.motor_torque_base_pct) < 0.01,
		"T0 a nominal run at setpoint melt reaches RUNNING at the base torque (%s, %.2f %%, base %.0f %%)"
		% [m.get_state_name(), run_t, cfg.motor_torque_base_pct])
	var s := _stop_and_follow(m, DT, [STOP_PROBE_S])
	_check(int(s["ticks"]) >= 100 and float(s["entry_t"]) > 0.0,
		"T1 the stop spent %d ticks in STOPPING from an entry torque of %.2f %% (anti-vacuity: >= 100 ticks, entry > 0)"
		% [int(s["ticks"]), float(s["entry_t"])])
	_check(float(s["worst"]) <= LAW_TOL_PCT,
		"T2 every STOPPING tick reads entry torque x rpm / entry rpm: worst deviation %.5f %% over %d ticks (tolerance %.3f)"
		% [float(s["worst"]), int(s["ticks"]), LAW_TOL_PCT])
	var t12 : float = float(s["marks"].get(STOP_PROBE_S, -1.0))
	var r12 : float = float(s["rpm_marks"].get(STOP_PROBE_S, 0.0)) / maxf(float(s["entry_rpm"]), 0.001)
	_check(t12 >= 0.70 * run_t and absf(t12 / maxf(run_t, 0.001) - r12) <= 0.01,
		"T3 %.1f s into the stop the torque reads %.2f %% = %.3f of running, with the screw at %.3f of its entry rpm (the compounding product read 0.142)"
		% [STOP_PROBE_S, t12, t12 / maxf(run_t, 0.001), r12])
	_check(int(s["rising"]) == 0,
		"T4 the torque never rises while the screw coasts down (%d rising ticks)" % int(s["rising"]))
	_check(int(s["lumps"]) == 0,
		"T5 no STOPPING tick passes lumps to the laserfilter (%d did)" % int(s["lumps"]))
	_check(bool(s["off"]) and float(s["off_t"]) == 0.0,
		"T6 the stop ends OFF with the torque parked at 0 (%s, %.3f %%)"
		% [m.get_state_name(), float(s["off_t"])])


## The compounding product was per TICK, so the tick size set the reading.
func _check_tick_size(cfg: ExtruderConfig) -> void:
	var a := _stop_and_follow(_running_model(cfg, 0.1), 0.1, MARKS)
	var b := _stop_and_follow(_running_model(cfg, 0.05), 0.05, MARKS)
	for t in MARKS:
		var ta : float = float(a["marks"].get(t, -1.0))
		var tb : float = float(b["marks"].get(t, -1.0))
		_check(ta > 0.0 and tb > 0.0 and absf(ta - tb) <= TICK_TOL_PCT,
			"S1 %.1f s into the stop the torque reads the same at 0.1 s and 0.05 s ticks (%.3f vs %.3f %%; the compounding product read 8.54 vs 1.41 at 1.2 s, 0 by 4 s)"
			% [t, ta, tb])


## _update_motor_torque runs the 110 % trip accumulator, and a coasting screw
## must not trip on the torque it was stopped at. Run a cold-zone line at 120 %
## for 1.0 s (half the 2.0 s sustain), then stop it.
func _check_no_trip_in_stopping(cfg: ExtruderConfig) -> void:
	var m := _running_model(cfg, DT)
	for i in range(ExtruderModel.ZONE_COUNT):
		m.set_zone_temp(i, m.get_zone_temp(i) - ZONE_DROP_C)
	var over := 0
	var tripped := false
	for _i in range(int(1.0 / DT)):
		if m.tick(DT, {}).has("motor_torque_trip"):
			tripped = true
		if m.motor_torque_pct >= ExtruderModel.TORQUE_TRIP_PCT:
			over += 1
	_check(not tripped and m.state == ExtruderModel.State.RUNNING and over == int(1.0 / DT),
		"N0 a line with every zone %.0f °C down runs %d ticks at %.1f %% torque, over the %.0f %% trip, without tripping yet (%s)"
		% [ZONE_DROP_C, over, m.motor_torque_pct, ExtruderModel.TORQUE_TRIP_PCT, m.get_state_name()])
	var s := _stop_and_follow(m, DT, [STOP_PROBE_S])
	_check(not bool(s["trip"]) and not bool(s["fault"]) and bool(s["off"]),
		"N1 stopped from %.1f %%, it coasts down to OFF with no motor_torque_trip (trip %s, FAULT %s, OFF %s)"
		% [float(s["entry_t"]), str(s["trip"]), str(s["fault"]), str(s["off"])])
	_check(float(s["worst"]) <= LAW_TOL_PCT and int(s["lumps"]) == 0,
		"N2 that stop reads the rpm law too (worst %.5f %%) and passes no lumps (%d ticks did)"
		% [float(s["worst"]), int(s["lumps"])])


## Every stop takes its own entry: stop, restart 2 s into the coast-down, stop
## again 1 s into STARTING (so the second stop starts from a mid-ramp rpm). And
## a stop from a RUNNING screw below nominal scales from that screw's rpm.
func _check_second_stop(cfg: ExtruderConfig) -> void:
	var m := _running_model(cfg, DT)
	m.tick(DT, {"stop_production": true})
	for _i in range(int(2.0 / DT)):
		m.tick(DT, {})
	var coast_t : float = m.motor_torque_pct
	m.tick(DT, {"start_production": true})       # STOPPING's tick, then -> STARTING
	for _i in range(int(1.0 / DT)):
		m.tick(DT, {})
	var state_before : String = m.get_state_name()
	var s := _stop_and_follow(m, DT, [])
	_check(state_before == "STARTING" and float(s["entry_rpm"]) < m.config.screw_rpm_nominal * 0.95,
		"R0 the second stop is pressed mid-ramp (%s, %.1f rpm, nominal %.0f)"
		% [state_before, float(s["entry_rpm"]), m.config.screw_rpm_nominal])
	_check(float(s["entry_t"]) > coast_t and int(s["ticks"]) >= 5 and float(s["worst"]) <= LAW_TOL_PCT,
		"R1 it follows its OWN entry (%.2f %% at %.1f rpm, not the first coast-down's %.2f %%): worst %.5f %% over %d ticks"
		% [float(s["entry_t"]), float(s["entry_rpm"]), coast_t, float(s["worst"]), int(s["ticks"])])
	# The plant stops from wherever the operator set the screw (60-125 rpm in the
	# 3A/3B archive), so the ratio is to the ENTRY rpm, not to nominal.
	var low := _running_model(cfg, DT)
	low.set_screw_rpm_setpoint(SETPOINT_BELOW_NOMINAL_RPM)
	for _i in range(int(10.0 / DT)):
		low.tick(DT, {})
	var low_run_t : float = low.motor_torque_pct
	var ls := _stop_and_follow(low, DT, [0.1])
	var first : float = float(ls["marks"].get(0.1, -1.0))
	_check(absf(float(ls["entry_rpm"]) - SETPOINT_BELOW_NOMINAL_RPM) < 0.5
			and first >= 0.95 * low_run_t and float(ls["worst"]) <= LAW_TOL_PCT,
		"R2 a stop from the operator's %.0f rpm (nominal %.0f) starts from its running %.2f %% (first STOPPING tick %.2f %%) and follows the entry rpm: worst %.5f %%"
		% [float(ls["entry_rpm"]), cfg.screw_rpm_nominal, low_run_t, first, float(ls["worst"])])


# ── B. the wired brain, read where the operator reads it ─────────────────────
func _check_wired_rig() -> void:
	var body := PlaceableCatalog.build_node("extruder_3b", false)
	if body == null:
		_check(false, "catalog built extruder_3b")
		return
	add_child(body)
	body.global_position = Vector3.ZERO
	var brain := body.get_node_or_null("SimBrain")
	if brain == null or brain.get("model") == null:
		_check(false, "extruder_3b carries a SimBrain with a model")
		return
	# A bench rig has no pellet side, so its hidden "natraject" setting goes
	# OFF and the start button starts the screw alone, as before 2026-09-25
	# (operator rulings, rulings file §I7). The natraject itself is
	# test_extruder_start_interlock's.
	brain.get("model").start_seq.natraject_enabled = false
	var laser : Node3D = load("res://src/sim/LaserFilter.gd").new()
	add_child(laser)
	laser.global_position = Vector3(6.0, 0.0, 0.0)
	var head : Node3D = load("res://src/sim/HeadFilter.gd").new()
	add_child(head)
	head.global_position = Vector3(9.0, 0.0, 0.0)
	var scope := ExtruderBluPortScope.new()
	add_child(scope)
	await get_tree().process_frame
	brain.call("_resolve_downstream_filters")
	var m : ExtruderModel = brain.get("model")
	scope.set_model(m)
	m.melt_temp = m.config.melt_temp_setpoint
	var pend : Dictionary = brain.get("_pending")
	pend["start_production"] = true
	for i in range(int(RUN_TO_NOMINAL_S / DT)):
		_step(brain, laser, head)
		if i == 0:
			m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)   # the player raises it
	var run_t : float = m.motor_torque_pct
	_check(m.state == ExtruderModel.State.RUNNING and run_t > 0.0,
		"W0 the wired extruder_3b runs through its SimTick handler (%s, %.2f %%)" % [m.get_state_name(), run_t])
	pend["stop_production"] = true
	_step(brain, laser, head)
	var entry_t : float = m.motor_torque_pct
	var entry_rpm : float = maxf(m.screw_rpm, 0.001)
	var t := 0.0
	var worst := 0.0
	var ticks := 0
	var at_probe := -1.0
	var rail := ""
	for _i in range(int(60.0 / DT)):
		if m.state != ExtruderModel.State.STOPPING:
			break
		_step(brain, laser, head)
		t += DT
		ticks += 1
		worst = maxf(worst, absf(m.motor_torque_pct - entry_t * clampf(m.screw_rpm / entry_rpm, 0.0, 1.0)))
		if at_probe < 0.0 and t + DT * 0.5 >= STOP_PROBE_S:
			at_probe = m.motor_torque_pct
			scope._process(DT)
			var lbl : Label = scope._rail_values.get("load_pct", null)
			rail = lbl.text if lbl != null else "<no load_pct rail>"
	_check(ticks >= 100 and worst <= LAW_TOL_PCT,
		"W1 through %d wired STOPPING ticks the torque reads the rpm law (worst %.5f %%)" % [ticks, worst])
	_check(at_probe >= 0.70 * run_t and rail == scope._fmt_number(at_probe, "%") and float(rail) >= 0.70 * run_t,
		"W2 %.1f s into the stop the BluPort 'belasting' rail reads %s %% (model %.2f %% = %.3f of running %.1f; the compounding product showed 9)"
		% [STOP_PROBE_S, rail, at_probe, at_probe / maxf(run_t, 0.001), run_t])
	_check(m.state == ExtruderModel.State.OFF and not bool(laser.get("is_tripped"))
			and not bool(brain.get("_pel_trip_latched")) and m.fault_reason == "",
		"W3 the wired stop ends OFF with no trip latched and no fault reason (%s, 318 %s, MP<PEL %s, '%s')"
		% [m.get_state_name(), str(laser.get("is_tripped")), str(brain.get("_pel_trip_latched")), m.fault_reason])


## One 0.1 s step: filters first (they integrate on physics), then the brain's
## SimTick handler — test_extruder_melt_pressures' order.
func _step(brain: Node, laser: Node, head: Node) -> void:
	laser.call("_physics_process", DT)
	head.call("_physics_process", DT)
	brain.call("_on_sim_tick", DT)


# ── verdict ───────────────────────────────────────────────────────────────────
func _finish() -> void:
	if _done:
		return
	_done = true
	var verdict := "PASS" if _fails == 0 and _oks > 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("  FAIL  : watchdog — no verdict after %.0f s (a SCRIPT ERROR above aborted the run)" % WATCHDOG_S)
	print("Result: FAIL (%d ok, %d fail)" % [_oks, _fails + 1])
	get_tree().quit(2)
