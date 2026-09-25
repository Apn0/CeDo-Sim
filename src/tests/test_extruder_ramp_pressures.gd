extends Node

# =============================================================================
# Extruder melt pressures through STARTING and STOPPING follow the flow the
# ramp moves, not the previous tick's pressure.
# =============================================================================
# Regression guard for the defect measured 2026-09-25 on `main` 64921ff:
# `ExtruderModel._scale_melt_pressures(rpm_frac)` ran every tick of
# `_tick_starting` and `_tick_stopping` and did
#   mp_after_laserfilter_bar *= rpm_frac;  die_plate_bar *= rpm_frac
# so it multiplied the LAST tick's already-scaled pressures:
#   * STOPPING — the pressures fell as the product of every rpm fraction so far,
#     and the tick size set how fast. 1.2 s into a stop from nominal (rpm 0.741
#     of nominal) the die plate read 19.92 bar = 0.142 of the running 140 bar at
#     0.1 s ticks and 3.29 bar = 0.024 at 0.05 s ticks; the flow gives 0.747.
#     At 2 s it read 0.73 bar, at 4 s 0.00, with the screw still at 0.37.
#   * STARTING — OFF / PREHEAT / IDLE park the pressures at 0, and 0 x rpm_frac
#     is 0, so a start read 0 bar for the whole ramp. The laserfilter's 318-bar
#     trip input (ExtruderMachine forwards MP>MF in STARTING and STOPPING) saw
#     no melt-set pressure while the screw pushed up to 0.97 of nominal flow.
# Now both states call `_set_melt_pressures_from_flow()`, the same law
# `_step_degassing` applies in RUNNING and VACUUM_ALARM.
#
# The expected values are computed from the model's own throughput and
# melt_viscosity_factor at that tick, with the die law read off the script:
#   MP>MF      = mp_after_laserfilter_nominal_bar x q x melt
#   die plate  = die_plate_nominal_bar x q^n x melt
# where q = throughput / nominal and n = ExtruderModel.DIE_FLOW_INDEX when that
# constant exists (the power-law die, operator ruling 2026-09-25), else 1.0
# (the linear law it replaces). So this suite holds under either die law, and a
# merge that feeds the power law q x melt through one argument (pow(q*m, n)
# instead of pow(q, n) * m) turns the law checks red whenever the melt is off
# setpoint, as it is during every stop (the heaters drift toward 0.85 x setpoint).
#
#   godot --headless --path . res://src/tests/test_extruder_ramp_pressures.tscn
#
# Part A drives a bare ExtruderModel from Extruder3B.tres. Part B drives the REAL
# catalog extruder_3b (build_node -> MachineBrains) with a real LaserFilter and
# HeadFilter, ticked by hand at the 0.1 s SimTick rate, as
# test_extruder_melt_pressures does. No MainWorld boot, no user:// writes.
# Exits 0 on pass, 1 on failure, 2 on the watchdog.
# =============================================================================

const DT : float = 0.1
const WATCHDOG_S : float = 180.0
const CFG_PATH := "res://src/data/machines/Extruder3B.tres"
const LAW_TOL_BAR : float = 0.01      # the law is exact: same inputs, same formula
const RUN_TO_NOMINAL_S : float = 300.0 # the start + the raise to nominal, then steady
const STOP_PROBE_S : float = 1.2       # where the defect was first measured

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _n : float = 1.0


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
	print("=== extruder ramp pressures (STARTING / STOPPING follow the flow) ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	# Watchdog: a runtime SCRIPT ERROR aborts _ready() and the scene would idle
	# forever with no verdict (CLAUDE.md, "a headless run that outlives...").
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame

	var consts : Dictionary = (ExtruderModel as Script).get_script_constant_map()
	_n = float(consts.get("DIE_FLOW_INDEX", 1.0))
	_info("die law: die plate ∝ q^%.3f x melt (%s)" % [_n,
		"ExtruderModel.DIE_FLOW_INDEX" if consts.has("DIE_FLOW_INDEX") else "no DIE_FLOW_INDEX: linear"])
	var cfg := load(CFG_PATH) as ExtruderConfig
	_check(cfg != null, "Extruder3B.tres loads")
	if cfg == null:
		_finish()
		return

	_check_stopping(cfg)
	_check_stopping_tick_size(cfg)
	_check_starting(cfg)
	_check_warm_restart(cfg)
	_check_restart_during_coast(cfg)
	await _check_wired_rig()
	_finish()


# ── helpers ───────────────────────────────────────────────────────────────────
func _q(m: ExtruderModel) -> float:
	return m.throughput_kg_h / maxf(m.config.nominal_kg_per_h, 0.001)

func _law_die(m: ExtruderModel) -> float:
	return m.config.die_plate_nominal_bar * pow(maxf(_q(m), 0.0), _n) * m.melt_viscosity_factor

func _law_mp(m: ExtruderModel) -> float:
	return m.config.mp_after_laserfilter_nominal_bar * maxf(_q(m), 0.0) * m.melt_viscosity_factor

## Worst deviation of the model's two melt-set pressures from the flow law.
func _law_err(m: ExtruderModel) -> float:
	return maxf(absf(m.die_plate_bar - _law_die(m)), absf(m.mp_after_laserfilter_bar - _law_mp(m)))

## Flow fraction at the model's rpm setpoint (a start ends STARTING there).
func _q_setpoint(m: ExtruderModel) -> float:
	return m.screw_rpm_setpoint / maxf(m.config.screw_rpm_nominal, 1.0)

func _running_model(cfg: ExtruderConfig, dt: float) -> ExtruderModel:
	var m := ExtruderModel.new(cfg.duplicate())
	m.melt_temp = m.config.melt_temp_setpoint
	m.tick(dt, {"start_production": true})
	# A new extruder's setpoint is 60 rpm (operator 2026-09-25); the player
	# raises it on the HMI.
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
	for _i in range(int(RUN_TO_NOMINAL_S / dt)):
		m.tick(dt, {})
	return m

## Stop a running model and sample the die plate at `marks` seconds into
## STOPPING. Returns {marks: {t: die}, ticks, worst, rising, off, off_die, off_mp}.
func _stop_and_sample(m: ExtruderModel, dt: float, marks: Array) -> Dictionary:
	var out := {"marks": {}, "ticks": 0, "worst": 0.0, "rising": 0, "off": false,
		"off_die": -1.0, "off_mp": -1.0}
	m.tick(dt, {"stop_production": true})       # RUNNING's tick, then -> STOPPING
	var t := 0.0
	var k := 0
	var prev_die : float = m.die_plate_bar
	for _i in range(int(60.0 / dt)):
		m.tick(dt, {})
		t += dt
		if m.state != ExtruderModel.State.STOPPING:
			# The tick that ends in the OFF transition still ran _tick_stopping
			# (the flow law at rpm < STOPPING_RPM_FLOOR, ~0.7 bar); OFF's own
			# tick is the one that parks the pressures.
			out["off"] = m.state == ExtruderModel.State.OFF
			m.tick(dt, {})
			out["off_die"] = m.die_plate_bar
			out["off_mp"] = m.mp_after_laserfilter_bar
			break
		out["ticks"] = int(out["ticks"]) + 1
		out["worst"] = maxf(float(out["worst"]), _law_err(m))
		if m.die_plate_bar > prev_die + 1e-6:
			out["rising"] = int(out["rising"]) + 1
		prev_die = m.die_plate_bar
		if k < marks.size() and t + dt * 0.5 >= float(marks[k]):
			out["marks"][marks[k]] = m.die_plate_bar
			k += 1
	return out


# ── A. bench model ────────────────────────────────────────────────────────────
func _check_stopping(cfg: ExtruderConfig) -> void:
	var m := _running_model(cfg, DT)
	_check(m.state == ExtruderModel.State.RUNNING and absf(m.die_plate_bar - cfg.die_plate_nominal_bar) < 1.0,
		"a nominal run reaches RUNNING at the die plate's nominal (%s, %.1f bar, nominal %.0f)"
		% [m.get_state_name(), m.die_plate_bar, cfg.die_plate_nominal_bar])
	var run_die : float = m.die_plate_bar
	var s := _stop_and_sample(m, DT, [STOP_PROBE_S, 4.0])
	_check(int(s["ticks"]) >= 100,
		"S0 the stop spent %d ticks in STOPPING (anti-vacuity: >= 100)" % int(s["ticks"]))
	_check(float(s["worst"]) <= LAW_TOL_BAR,
		"S1 every STOPPING tick reads the flow law: worst deviation %.4f bar over %d ticks (tolerance %.2f)"
		% [float(s["worst"]), int(s["ticks"]), LAW_TOL_BAR])
	var d12 : float = float(s["marks"].get(STOP_PROBE_S, -1.0))
	_check(d12 >= 0.70 * run_die,
		"S2 %.1f s into the stop the die plate reads %.1f bar = %.3f of running (the flow gives ~0.747; the compounding scale read 0.142)"
		% [STOP_PROBE_S, d12, d12 / maxf(run_die, 0.001)])
	_check(int(s["rising"]) == 0,
		"S3 the die plate never rises while the screw coasts down (%d rising ticks)" % int(s["rising"]))
	_check(bool(s["off"]) and float(s["off_die"]) == 0.0 and float(s["off_mp"]) == 0.0,
		"S4 the stop ends OFF with both melt-set pressures parked at 0 (die %.2f, MP>MF %.2f bar)"
		% [float(s["off_die"]), float(s["off_mp"])])


## The compounding scale was a per-TICK product, so the tick size set the
## reading. The flow law is a function of time (rpm decays as exp(-t/tau)).
func _check_stopping_tick_size(cfg: ExtruderConfig) -> void:
	var a := _stop_and_sample(_running_model(cfg, 0.1), 0.1, [STOP_PROBE_S, 4.0])
	var b := _stop_and_sample(_running_model(cfg, 0.05), 0.05, [STOP_PROBE_S, 4.0])
	for t in [STOP_PROBE_S, 4.0]:
		var da : float = float(a["marks"].get(t, -1.0))
		var db : float = float(b["marks"].get(t, -1.0))
		_check(da > 0.0 and absf(da - db) <= 0.1,
			"S5 %.1f s into the stop the die plate reads the same at 0.1 s and 0.05 s ticks (%.2f vs %.2f bar; the compounding scale read 19.92 vs 3.29 at 1.2 s, 0.00 at 4 s)"
			% [t, da, db])


func _check_starting(cfg: ExtruderConfig) -> void:
	var ref := _running_model(cfg, DT)
	var run_die : float = ref.die_plate_bar
	var m := ExtruderModel.new(cfg.duplicate())
	m.melt_temp = m.config.melt_temp_setpoint
	m.tick(DT, {"start_production": true})       # OFF routes a hot barrel to STARTING
	_check(m.state == ExtruderModel.State.STARTING,
		"a hot barrel's start goes straight to STARTING (%s)" % m.get_state_name())
	var ticks := 0
	var zero_ticks := 0
	var worst := 0.0
	var last_die := 0.0
	for _i in range(int(20.0 / DT)):
		if m.state != ExtruderModel.State.STARTING:
			break
		m.tick(DT, {})
		# The tick ran _tick_starting even when it ended in the RUNNING
		# transition, so every one of these readings is a STARTING reading.
		ticks += 1
		worst = maxf(worst, _law_err(m))
		if m.throughput_kg_h > 0.0 and m.die_plate_bar <= 0.0:
			zero_ticks += 1
		last_die = m.die_plate_bar
	_check(ticks >= 20 and m.state == ExtruderModel.State.RUNNING,
		"U0 the ramp spent %d ticks in STARTING and reached RUNNING (%s)" % [ticks, m.get_state_name()])
	_check(worst <= LAW_TOL_BAR,
		"U1 every STARTING tick reads the flow law: worst deviation %.4f bar over %d ticks" % [worst, ticks])
	_check(zero_ticks == 0,
		"U2 no STARTING tick with melt flowing reads 0 bar at the die plate (%d did; the compounding scale read 0 on all of them)"
		% zero_ticks)
	# STARTING ends at the rpm setpoint (a new extruder's is 60 of 110, operator
	# 2026-09-25), so the last STARTING tick carries the die plate of that flow.
	var start_die : float = cfg.die_plate_nominal_bar * pow(_q_setpoint(m), _n)
	_check(last_die >= 0.9 * start_die,
		"U3 the last STARTING tick reads %.1f bar = %.3f of the die plate at the setpoint's flow (%.1f bar at q %.3f; running at nominal %.1f)"
		% [last_die, last_die / maxf(start_die, 0.001), start_die, _q_setpoint(m), run_die])


## A start after the line has run at nominal before: STARTING ramps to the
## setpoint the operator left and hands over to RUNNING there, so the gauge must
## not jump. (Until 2026-09-25 a FIRST start re-ramped from idle in RUNNING
## whatever the setpoint; test_extruder_start_rpm holds both to one start.)
func _check_warm_restart(cfg: ExtruderConfig) -> void:
	var m := _running_model(cfg, DT)
	var run_die : float = m.die_plate_bar
	m.tick(DT, {"stop_production": true})
	for _i in range(int(60.0 / DT)):
		m.tick(DT, {})
		if m.state == ExtruderModel.State.OFF:
			break
	m.melt_temp = m.config.melt_temp_setpoint    # this check is about pressure, not preheat
	m.tick(DT, {"start_production": true})
	var last_start := -1.0
	var first_run := -1.0
	for _i in range(int(20.0 / DT)):
		var was_starting : bool = m.state == ExtruderModel.State.STARTING
		m.tick(DT, {})
		if was_starting:
			last_start = m.die_plate_bar
		elif m.state == ExtruderModel.State.RUNNING:
			first_run = m.die_plate_bar
			break
	var jump : float = absf(first_run - last_start) / maxf(run_die, 0.001)
	_check(last_start > 0.0 and first_run > 0.0 and jump <= 0.05,
		"U4 a warm restart hands STARTING (%.1f bar) to RUNNING (%.1f bar) with a %.1f %% step (the compounding scale stepped 0 -> %.0f)"
		% [last_start, first_run, jump * 100.0, run_die])
	# Measured, not gated: a model's FIRST start. It used to re-ramp from idle in
	# RUNNING (a lifetime-runtime ramp); since 2026-09-25 every start ramps to
	# the setpoint and RUNNING holds it, so first and warm starts hand over alike.
	var f := ExtruderModel.new(cfg.duplicate())
	f.melt_temp = f.config.melt_temp_setpoint
	f.tick(DT, {"start_production": true})
	var f_last := 0.0
	for _i in range(int(20.0 / DT)):
		var was : bool = f.state == ExtruderModel.State.STARTING
		f.tick(DT, {})
		if was:
			f_last = f.die_plate_bar
		elif f.state == ExtruderModel.State.RUNNING:
			break
	_info("a FIRST start (runtime_s 0) hands STARTING %.1f bar to RUNNING %.1f bar at q %.3f (it dropped to q 0.053 while RUNNING re-ramped from idle; see test_extruder_start_rpm A8)"
		% [f_last, f.die_plate_bar, _q(f)])


## STOPPING -> STARTING (the operator restarts during the coast-down). The
## compounding scale kept multiplying the coast-down's residue.
func _check_restart_during_coast(cfg: ExtruderConfig) -> void:
	var m := _running_model(cfg, DT)
	m.tick(DT, {"stop_production": true})
	for _i in range(int(2.0 / DT)):
		m.tick(DT, {})
	var coast_die : float = m.die_plate_bar
	var coast_state : String = m.get_state_name()
	m.tick(DT, {"start_production": true})       # STOPPING's tick, then -> STARTING
	var ticks := 0
	var worst := 0.0
	var first := -1.0
	for _i in range(int(20.0 / DT)):
		if m.state != ExtruderModel.State.STARTING:
			break
		m.tick(DT, {})
		ticks += 1
		worst = maxf(worst, _law_err(m))
		if first < 0.0:
			first = m.die_plate_bar
	_check(coast_state == "STOPPING" and ticks >= 5 and worst <= LAW_TOL_BAR,
		"U5 a restart 2 s into the coast-down (%s, %.1f bar) ramps on the flow law: %d STARTING ticks, worst %.4f bar"
		% [coast_state, coast_die, ticks, worst])
	_check(first >= 0.9 * coast_die,
		"U6 its first STARTING tick reads %.1f bar, not the coast-down's residue x rpm (coast-down %.1f bar)"
		% [first, coast_die])


# ── B. the wired brain: what the laserfilter's 318-bar trip reads ─────────────
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
	var laser : Node3D = load("res://src/sim/LaserFilter.gd").new()
	add_child(laser)
	laser.global_position = Vector3(6.0, 0.0, 0.0)
	var head : Node3D = load("res://src/sim/HeadFilter.gd").new()
	add_child(head)
	head.global_position = Vector3(9.0, 0.0, 0.0)
	await get_tree().process_frame
	brain.call("_resolve_downstream_filters")
	_check(brain.get("_laser_filter") == laser and brain.get("_head_filter") == head,
		"W0 the wired extruder_3b resolved its own laserfilter and kopfilter")
	var m : ExtruderModel = brain.get("model")
	m.melt_temp = m.config.melt_temp_setpoint
	var pend : Dictionary = brain.get("_pending")
	pend["start_production"] = true
	var start_ticks := 0
	var start_mismatch := 0
	var start_last := 0.0
	var run_steps := 0
	for _i in range(int(RUN_TO_NOMINAL_S / DT)):
		var was_starting : bool = m.state == ExtruderModel.State.STARTING
		_step(brain, laser, head)
		run_steps += 1
		if run_steps == 1:
			# A new extruder's setpoint is 60 rpm; the player raises it.
			m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
		if was_starting:
			start_ticks += 1
			var fed : float = float(laser.get("mp_after_filter_bar"))
			if absf(fed - m.mp_after_laserfilter_bar) > LAW_TOL_BAR:
				start_mismatch += 1
			start_last = fed
	var start_mp : float = m.config.mp_after_laserfilter_nominal_bar * _q_setpoint(m)
	_check(start_ticks >= 20 and start_mismatch == 0
			and start_last >= 0.9 * start_mp,
		"W1 through %d STARTING ticks the laserfilter's MP>MF is the model's (%d mismatches), %.1f bar on the last one (%.1f at the setpoint's flow; the compounding scale fed 0)"
		% [start_ticks, start_mismatch, start_last, start_mp])
	var run_mp : float = m.mp_after_laserfilter_bar
	pend["stop_production"] = true
	_step(brain, laser, head)
	var t := 0.0
	var at_probe := -1.0
	var stop_mismatch := 0
	for _i in range(int(60.0 / DT)):
		_step(brain, laser, head)
		t += DT
		if m.state != ExtruderModel.State.STOPPING:
			break
		if absf(float(laser.get("mp_after_filter_bar")) - m.mp_after_laserfilter_bar) > LAW_TOL_BAR:
			stop_mismatch += 1
		if at_probe < 0.0 and t + DT * 0.5 >= STOP_PROBE_S:
			at_probe = float(laser.get("mp_after_filter_bar"))
	_check(stop_mismatch == 0 and at_probe >= 0.70 * run_mp,
		"W2 %.1f s into the stop the laserfilter's MP>MF reads %.1f bar = %.3f of running %.1f (%d mismatches with the model)"
		% [STOP_PROBE_S, at_probe, at_probe / maxf(run_mp, 0.001), run_mp, stop_mismatch])
	_check(m.state == ExtruderModel.State.OFF and not bool(laser.get("is_tripped"))
			and not bool(brain.get("_pel_trip_latched")),
		"W3 a start, %.0f s of running and a stop at setpoint melt end OFF with neither trip latched (%s, 318 %s, MP<PEL %s)"
		% [RUN_TO_NOMINAL_S, m.get_state_name(), str(laser.get("is_tripped")), str(brain.get("_pel_trip_latched"))])


## One 0.1 s step: filters first (they integrate on physics), then the brain's
## SimTick handler (model tick, forwarding, trip checks) — test_extruder_melt_pressures' order.
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
