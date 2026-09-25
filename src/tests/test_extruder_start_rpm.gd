extends Node

# =============================================================================
# Every extruder start runs the screw 0 -> 60 rpm in ~3 s and stays there; the
# player raises the rpm on the HMI, per line; and a WARM restart at the green
# button's temperature neither trips 318 bar nor passes lumps.
# =============================================================================
# The finding (docs/audit/extruder_ramp_pressures_2026-09-25.md §5 items 1-2,
# re-measured here with src/tests/probe_warm_restart_pressure.tscn on main
# 64921ff and on #290): a model that had run before (runtime_s past
# startup_ramp_s) re-entered RUNNING at NOMINAL flow, so a restart at the
# coldest melt the green button accepted (196.25 C) drove MP<MF to 317 bar and
# tripped 318 about 4.5 s after the green button, on 3A and 3B, through the
# plain gameplay path (stop, wait, PREHEAT, green) too. A FRESH model re-ramped
# from idle in RUNNING (a lifetime-runtime ramp), so test_extruder_melt_pressures,
# which only starts fresh models, never saw it.
#
# Operator rulings 2026-09-25 (docs/plant/operator_rulings_2026-09-25.md):
#   * "the minimum value possible to set 60 rpm and it will ramp up in about two
#     and a half to three seconds ... to that 60 rpm and then that's it". The
#     EREMA WinCC archive agrees: 3A/3B speed_extruder has no 6-min bucket
#     between 0 and 60 rpm (2023-06-19..28), and most starts read 60 first.
#   * the player raises the rpm on the HMI; every extruder; a line choice on the
#     one all-lines extruder HMI so every line can be raised.
#   * the green button also waits until the screw passes no lumps (95 % torque),
#     with the same 25 % margin as the torque trip: green = 201.875 C on 3A/3B.
#     With the 60-rpm start alone, green at the old 196.25 C still tripped, now
#     through lumps (RUNNING entry at 95.7 % torque, 3.4 g/s, 318 in 0.3 s).
#
# Every number asserted below is typed from those rulings, not read from the
# config under test (a check that reads the config blesses any value).
#
#   godot --headless --path . res://src/tests/test_extruder_start_rpm.tscn
#
# Part A: a bare ExtruderModel from Extruder3B.tres. Part B: the REAL catalog
# extruders (build_node -> MachineBrains) with a real LaserFilter and HeadFilter,
# ticked by hand at 0.1 s as test_extruder_melt_pressures does. Part C: the web
# HMI's line choice and the touchscreen's rpm row, on two live catalog rigs.
# No MainWorld boot, no user:// writes. Exits 0 on pass, 1 on failure, 2 on
# the watchdog.
# =============================================================================

const DT : float = 0.1
const WATCHDOG_S : float = 300.0
const CFG_PATH := "res://src/data/machines/Extruder3B.tres"

# Documented (see header). Deliberately NOT read from ExtruderConfig.
const START_RPM_DOC : float = 60.0
const START_S_DOC := Vector2(2.5, 3.0)
const GREEN_3AB_C : float = 201.875     # 215 - (95 - 60) % / (20 %/10 C) x 0.75
const OLD_GREEN_C : float = 196.25      # the torque-trip-only green it replaced
const SAFE_MAX_BAR : float = 280.0      # operator 2026-09-24: safe max before the laserfilter
const MP_BEFORE_OK_BAR := Vector2(177.0, 280.0)   # test_extruder_melt_pressures' nominal band
const WARM_RUN_S : float = 300.0        # past the old startup_ramp_s (180 s)
const WATCH_S : float = 240.0

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _x : float = 0.0


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
	print("=== extruder start: 0 -> 60 rpm, the player raises it, warm restart at green ===")
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
	await _part_c_hmi()
	_part_a_model(cfg)
	_part_b_rigs()
	_finish()


# ── helpers ───────────────────────────────────────────────────────────────────
func _q(m: ExtruderModel) -> float:
	return m.throughput_kg_h / maxf(m.config.nominal_kg_per_h, 0.001)


## Flow the documented law gives at a screw speed: nominal x rpm / nominal rpm,
## times the pelletiser's knife-wear multiplier.
func _flow_law(m: ExtruderModel, rpm: float) -> float:
	var mult : float = m.pelletizer.get_throughput_multiplier() if m.pelletizer != null else 1.0
	return m.config.nominal_kg_per_h * rpm / m.config.screw_rpm_nominal * mult


## Start a bare model from OFF at `melt`. OFF cools the melt 0.05 C before it
## routes the request, so a melt AT the green temperature lands in PREHEAT and
## the green button is pressed a second time there. True when it is STARTING.
func _bare_start(m: ExtruderModel, melt: float) -> bool:
	m.melt_temp = melt
	m.tick(DT, {"start_production": true})
	if m.state == ExtruderModel.State.PREHEAT:
		m.melt_temp = melt
		m.tick(DT, {"start_production": true})
	return m.state == ExtruderModel.State.STARTING


func _bare_stop(m: ExtruderModel) -> void:
	m.tick(DT, {"stop_production": true})
	for _i in range(int(60.0 / DT)):
		if m.state == ExtruderModel.State.OFF:
			return
		m.tick(DT, {})


# ── A. the start rule on a bare model ─────────────────────────────────────────
func _part_a_model(cfg: ExtruderConfig) -> void:
	print("  -- A. the start rule (bare Extruder3B model) --")
	var m := ExtruderModel.new(cfg.duplicate())
	var started := _bare_start(m, m.config.melt_temp_setpoint)
	_check(started and m.screw_rpm == 0.0,
		"A0 a hot barrel's start enters STARTING with the screw standing still (%s, %.1f rpm)"
		% [m.get_state_name(), m.screw_rpm])
	var first_rpm := -1.0
	var ticks := 0
	var law_err := 0.0
	while m.state == ExtruderModel.State.STARTING and ticks < 100:
		m.tick(DT, {})
		ticks += 1
		if first_rpm < 0.0:
			first_rpm = m.screw_rpm
		law_err = maxf(law_err, absf(m.throughput_kg_h - _flow_law(m, m.screw_rpm)))
	var t_run : float = ticks * DT
	_check(first_rpm > 0.0 and first_rpm <= START_RPM_DOC * DT / START_S_DOC.x + 1e-4,
		"A1 the first STARTING tick runs the screw from 0, not from an idle rpm: %.2f rpm after 0.1 s (a 2.5-3 s ramp to 60 gives 2.0-2.4)"
		% first_rpm)
	_check(m.state == ExtruderModel.State.RUNNING and t_run >= START_S_DOC.x - 1e-4
			and t_run <= START_S_DOC.y + DT + 1e-4 and absf(m.screw_rpm - START_RPM_DOC) < 1e-3,
		"A2 the screw reaches %.0f rpm and the model is RUNNING %.1f s after the start (operator: 2.5-3 s) at %.2f rpm"
		% [START_RPM_DOC, t_run, m.screw_rpm])
	_check(law_err < 1e-3,
		"A3 on every STARTING tick the flow follows the screw (nominal x rpm / nominal rpm): worst %.5f kg/h off"
		% law_err)
	var thru10 := 0.0
	for i in range(int(600.0 / DT)):
		m.tick(DT, {})
		if i == int(10.0 / DT):
			thru10 = m.throughput_kg_h
	var want60 : float = m.config.nominal_kg_per_h * START_RPM_DOC / m.config.screw_rpm_nominal
	_check(m.state == ExtruderModel.State.RUNNING and absf(m.screw_rpm - START_RPM_DOC) < 1e-3
			and absf(m.throughput_kg_h - want60) < 0.01 and absf(thru10 - m.throughput_kg_h) < 1e-6,
		"A4 nobody raises it: 600 s later still %.2f rpm and %.1f kg/h (= %.1f at 60 rpm; %.1f at 10 s), no hidden ramp to nominal"
		% [m.screw_rpm, m.throughput_kg_h, want60, thru10])

	# The player raises it on the HMI; the screw follows.
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
	var t_up := 0.0
	while absf(m.screw_rpm - m.config.screw_rpm_nominal) > 1e-3 and t_up < 30.0:
		m.tick(DT, {})
		t_up += DT
	for _i in range(5):
		m.tick(DT, {})
	_check(absf(m.screw_rpm - m.config.screw_rpm_nominal) < 1e-3 and t_up <= 3.0
			and absf(m.throughput_kg_h - _flow_law(m, m.config.screw_rpm_nominal)) < 0.01,
		"A5 raising the setpoint to %.0f rpm takes the screw there in %.1f s and the flow to %.1f kg/h"
		% [m.config.screw_rpm_nominal, t_up, m.throughput_kg_h])

	m.set_screw_rpm_setpoint(40.0)
	var lo := m.screw_rpm_setpoint
	m.set_screw_rpm_setpoint(400.0)
	var hi := m.screw_rpm_setpoint
	_check(absf(lo - START_RPM_DOC) < 1e-6 and absf(hi - m.config.screw_rpm_max) < 1e-6,
		"A6 the setpoint cannot go under %.0f rpm (40 reads %.0f) nor past the line's max (400 reads %.0f)"
		% [START_RPM_DOC, lo, hi])

	# A warm model (ran at nominal past the old 180 s ramp) and a fresh one
	# start identically: the old lifetime-runtime ramp made them differ.
	var w := ExtruderModel.new(cfg.duplicate())
	_bare_start(w, w.config.melt_temp_setpoint)
	w.tick(DT, {})
	w.set_screw_rpm_setpoint(w.config.screw_rpm_nominal)
	for _i in range(int(WARM_RUN_S / DT)):
		w.tick(DT, {})
	var warm_sp_before : float = w.screw_rpm_setpoint
	var warm_rt : float = w.runtime_s
	_bare_stop(w)
	var f := ExtruderModel.new(cfg.duplicate())
	var ws := _bare_start(w, w.config.melt_temp_setpoint)
	var fs := _bare_start(f, f.config.melt_temp_setpoint)
	_check(ws and absf(warm_sp_before - w.config.screw_rpm_nominal) < 1e-6
			and absf(w.screw_rpm_setpoint - START_RPM_DOC) < 1e-6,
		"A7 a restart puts the rpm setpoint back to %.0f (it was %.0f before the stop): %.0f"
		% [START_RPM_DOC, warm_sp_before, w.screw_rpm_setpoint])
	var worst_dq := 0.0
	for _i in range(100):
		w.tick(DT, {})
		f.tick(DT, {})
		worst_dq = maxf(worst_dq, absf(_q(w) - _q(f)))
	_check(fs and warm_rt > 180.0 and worst_dq < 1e-6,
		"A8 a warm restart (runtime %.0f s) and a model's first start run the same 10 s: worst flow difference q %.7f"
		% [warm_rt, worst_dq])

	# A vacuum alarm keeps the screw where the operator has it.
	var v := ExtruderModel.new(cfg.duplicate())
	_bare_start(v, v.config.melt_temp_setpoint)
	for _i in range(int(10.0 / DT)):
		v.tick(DT, {})
	var thru_run : float = v.throughput_kg_h
	v.tick(DT, {"vacuum_lost": true})
	var in_alarm : bool = v.state == ExtruderModel.State.VACUUM_ALARM
	for _i in range(int(5.0 / DT)):
		v.tick(DT, {})
	_check(in_alarm and absf(v.screw_rpm - START_RPM_DOC) < 1e-3 and absf(v.throughput_kg_h - thru_run) < 1e-3,
		"A9 a vacuum alarm at 60 rpm keeps 60 rpm and %.1f kg/h (%s, %.1f rpm, %.1f kg/h; it used to force nominal)"
		% [thru_run, v.get_state_name(), v.screw_rpm, v.throughput_kg_h])

	# The green button waits until the screw passes no lumps (ruling).
	var g := ExtruderModel.new(cfg.duplicate())
	var green : float = float(g.call("_preheat_ready_temp"))
	g.melt_temp = GREEN_3AB_C - 0.01
	var below : bool = g.preheat_ready()
	g.melt_temp = GREEN_3AB_C
	var at : bool = g.preheat_ready()
	_check(absf(green - GREEN_3AB_C) < 1e-6 and not below and at,
		"A10 the green button unlocks at %.3f C (ruling: %.3f, from the 95 %% lump point with the 25 %% margin; it was %.2f)"
		% [green, GREEN_3AB_C, OLD_GREEN_C])


# ── B. the wired rigs: the warm restart the finding is about ──────────────────
func _build_rig(lid: String, placeable: String) -> Dictionary:
	_x += 1000.0
	var body := PlaceableCatalog.build_node(placeable, false)
	if body == null:
		_check(false, "catalog built %s" % placeable)
		return {}
	add_child(body)
	body.global_position = Vector3(_x, 0.0, 0.0)
	var brain := body.get_node_or_null("SimBrain")
	if brain == null or brain.get("model") == null:
		_check(false, "%s carries a SimBrain with a model" % placeable)
		return {}
	var laser : Node3D = load("res://src/sim/LaserFilter.gd").new()
	add_child(laser)
	laser.global_position = Vector3(_x + 6.0, 0.0, 0.0)
	var head : Node3D = load("res://src/sim/HeadFilter.gd").new()
	add_child(head)
	head.global_position = Vector3(_x + 9.0, 0.0, 0.0)
	brain.call("_resolve_downstream_filters")
	if brain.get("_laser_filter") != laser or brain.get("_head_filter") != head:
		_check(false, "%s: the brain resolved its OWN laserfilter and kopfilter" % lid)
		return {}
	return {"lid": lid, "body": body, "brain": brain, "model": brain.get("model"),
		"laser": laser, "head": head}


## One 0.1 s step: filters first (they integrate on physics), then the brain's
## SimTick handler — test_extruder_melt_pressures' order.
func _step(rig: Dictionary) -> void:
	rig["laser"].call("_physics_process", DT)
	rig["head"].call("_physics_process", DT)
	rig["brain"].call("_on_sim_tick", DT)


func _press(rig: Dictionary, key: String) -> void:
	rig["brain"].get("_pending")[key] = true


func _mp_before(rig: Dictionary) -> float:
	return float(rig["laser"].call("mp_before_filter_bar"))


## Start at the handed-over (setpoint) melt, raise to nominal as the player
## does, run WARM_RUN_S, stop to OFF. Returns false if any step went wrong.
func _warm_up_and_stop(rig: Dictionary) -> bool:
	var m : ExtruderModel = rig["model"]
	_press(rig, "start_production")
	_step(rig)
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
	for _i in range(int(WARM_RUN_S / DT)):
		_step(rig)
	var warm : bool = m.state == ExtruderModel.State.RUNNING and m.runtime_s > 180.0 \
		and absf(m.screw_rpm - m.config.screw_rpm_nominal) < 1e-3
	_press(rig, "stop_production")
	for _i in range(int(60.0 / DT)):
		_step(rig)
		if m.state == ExtruderModel.State.OFF:
			break
	return warm and m.state == ExtruderModel.State.OFF


## From OFF, the melt set by hand, the start (and the green button) pressed.
func _hand_restart(rig: Dictionary, melt: float) -> bool:
	var m : ExtruderModel = rig["model"]
	m.melt_temp = melt
	_press(rig, "start_production")
	_step(rig)
	if m.state == ExtruderModel.State.PREHEAT:
		m.melt_temp = melt
		_press(rig, "start_production")
		_step(rig)
	return m.state == ExtruderModel.State.STARTING


## Step up to `secs` after the green button; stop early on a trip.
func _watch(rig: Dictionary, secs: float) -> Dictionary:
	var m : ExtruderModel = rig["model"]
	var r := {"peak": 0.0, "trip_t": -1.0, "t_run": -1.0, "lump_ticks": 0, "torque_run": -1.0}
	for i in range(int(secs / DT)):
		_step(rig)
		var t := (i + 1) * DT
		if r["t_run"] < 0.0 and m.state == ExtruderModel.State.RUNNING:
			r["t_run"] = t
			r["torque_run"] = m.motor_torque_pct
		if m.state == ExtruderModel.State.RUNNING and m.lump_passthrough_rate_g_s > 0.0:
			r["lump_ticks"] = int(r["lump_ticks"]) + 1
		r["peak"] = maxf(float(r["peak"]), _mp_before(rig))
		if m.state == ExtruderModel.State.EMERGENCY_STOP:
			r["trip_t"] = t
			r["fault"] = String(m.fault_reason)
			break
	return r


func _warm_restart_check(tag: String, lid: String, placeable: String) -> Dictionary:
	var rig := _build_rig(lid, placeable)
	if rig.is_empty():
		return {}
	var m : ExtruderModel = rig["model"]
	var warm := _warm_up_and_stop(rig)
	var green : float = float(m.call("_preheat_ready_temp"))
	var started := _hand_restart(rig, green)
	var r := _watch(rig, WATCH_S)
	_check(warm and started and float(r["t_run"]) > 0.0 and float(r["trip_t"]) < 0.0
			and int(r["lump_ticks"]) == 0 and float(r["peak"]) < SAFE_MAX_BAR
			and absf(m.screw_rpm - START_RPM_DOC) < 1e-3,
		"%s %s WARM restart (ran %.0f s at nominal, stopped) at the green %.3f C: RUNNING at %.1f s, torque %.1f %%, no lumps (%d ticks), MP<MF peak %.1f bar < %.0f, no trip over %.0f s, still %.1f rpm"
		% [tag, lid, WARM_RUN_S, green, float(r["t_run"]), float(r["torque_run"]), int(r["lump_ticks"]),
			float(r["peak"]), SAFE_MAX_BAR, WATCH_S, m.screw_rpm])
	return rig


func _part_b_rigs() -> void:
	print("  -- B. the wired rigs: a warm restart at the green button --")
	var r3b := _warm_restart_check("B1", "3B", "extruder_3b")
	_warm_restart_check("B2", "3A", "extruder_3a")

	# B3 — the gameplay path, nothing set by hand: stop, wait in OFF until the
	# melt is under the green temperature, start (PREHEAT), green the tick the
	# block turns green.
	var g := _build_rig("3B", "extruder_3b")
	if not g.is_empty():
		var gm : ExtruderModel = g["model"]
		var warm := _warm_up_and_stop(g)
		var green : float = float(gm.call("_preheat_ready_temp"))
		var t_off := 0.0
		while gm.melt_temp >= green and t_off < 600.0:
			_step(g)
			t_off += DT
		_press(g, "start_production")
		_step(g)
		var to_preheat : bool = gm.state == ExtruderModel.State.PREHEAT
		var t_pre := 0.0
		while gm.state == ExtruderModel.State.PREHEAT and not gm.preheat_ready() and t_pre < 3600.0:
			_step(g)
			t_pre += DT
		var melt_green : float = gm.melt_temp
		_press(g, "start_production")
		_step(g)
		var started : bool = gm.state == ExtruderModel.State.STARTING
		var r := _watch(g, WATCH_S)
		_check(warm and to_preheat and started and float(r["trip_t"]) < 0.0
				and int(r["lump_ticks"]) == 0 and float(r["peak"]) < SAFE_MAX_BAR,
			"B3 gameplay path: stop, %.1f s in OFF, start -> PREHEAT %.1f s, green at %.2f C: no trip over %.0f s, no lumps, MP<MF peak %.1f bar"
			% [t_off, t_pre, melt_green, WATCH_S, float(r["peak"])])

	# B4 — the player waits for the melt, then raises to nominal: the line
	# reaches its nominal pressures (the pressure path is live, not vacuous).
	if not r3b.is_empty():
		var m : ExtruderModel = r3b["model"]
		var melt_at_raise : float = m.melt_temp
		m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
		var lo := INF
		var hi := -INF
		var trip := false
		for i in range(int(300.0 / DT)):
			_step(r3b)
			if m.state == ExtruderModel.State.EMERGENCY_STOP:
				trip = true
				break
			if i * DT >= 120.0:
				var p := _mp_before(r3b)
				lo = minf(lo, p)
				hi = maxf(hi, p)
		_check(not trip and m.state == ExtruderModel.State.RUNNING
				and absf(m.screw_rpm - m.config.screw_rpm_nominal) < 1e-3
				and lo >= MP_BEFORE_OK_BAR.x and hi <= MP_BEFORE_OK_BAR.y,
			"B4 raised to %.0f rpm at melt %.2f C: RUNNING at nominal, MP<MF %.1f..%.1f bar inside %.0f-%.0f (the nominal band), no trip"
			% [m.config.screw_rpm_nominal, melt_at_raise, lo, hi, MP_BEFORE_OK_BAR.x, MP_BEFORE_OK_BAR.y])

	# B5 — negative control: the same warm restart with the melt at the OLD
	# green temperature trips, through lumps. The trip is armed at 60 rpm, and
	# the new green is what keeps B1-B3 clear of it.
	var n := _build_rig("3B", "extruder_3b")
	if not n.is_empty():
		var nm : ExtruderModel = n["model"]
		var warm := _warm_up_and_stop(n)
		var started := _hand_restart(n, float(nm.call("_preheat_ready_temp")))
		nm.melt_temp = OLD_GREEN_C        # the green button no longer accepts it
		var r := _watch(n, 30.0)
		_check(warm and started and float(r["trip_t"]) > 0.0 and int(r["lump_ticks"]) > 0
				and String(r.get("fault", "")) == "laserfilter_upstream_overpressure_318bar",
			"B5 negative control: a warm 60-rpm start at the old green %.2f C passes lumps (%d ticks, torque %.1f %%) and trips 318 after %.1f s ('%s')"
			% [OLD_GREEN_C, int(r["lump_ticks"]), float(r["torque_run"]), float(r["trip_t"]), String(r.get("fault", ""))])

	# Measured, not gated (not ruled): raising to nominal the moment RUNNING
	# begins, on a melt still at the green temperature.
	var e := _build_rig("3B", "extruder_3b")
	if not e.is_empty():
		var em : ExtruderModel = e["model"]
		_warm_up_and_stop(e)
		_hand_restart(e, float(em.call("_preheat_ready_temp")))
		var t_run := -1.0
		var peak := 0.0
		var trip_t := -1.0
		for i in range(int(WATCH_S / DT)):
			_step(e)
			if t_run < 0.0 and em.state == ExtruderModel.State.RUNNING:
				t_run = (i + 1) * DT
				em.set_screw_rpm_setpoint(em.config.screw_rpm_nominal)
			peak = maxf(peak, _mp_before(e))
			if em.state == ExtruderModel.State.EMERGENCY_STOP:
				trip_t = (i + 1) * DT
				break
		_info("raising to nominal at once (RUNNING at %.1f s, melt ~%.1f C): MP<MF peak %.1f bar, %s"
			% [t_run, float(em.call("_preheat_ready_temp")) + 0.9, peak,
				"no trip" if trip_t < 0.0 else "trips 318 at %.1f s" % trip_t])


# ── C. the HMI: a line choice on the web screen, an rpm row on the touchscreen ─
func _part_c_hmi() -> void:
	print("  -- C. the HMI rpm control, per line --")
	var a := _build_rig("3A", "extruder_3a")
	var b := _build_rig("3B", "extruder_3b")
	if a.is_empty() or b.is_empty():
		return
	await get_tree().process_frame
	var ma : ExtruderModel = a["model"]
	var mb : ExtruderModel = b["model"]
	var ov = load("res://src/scenes/hud/HmiWebOverlay.gd").new()
	add_child(ov)
	ov.call("open_for", "Extruder (alle lijnen)", HmiScopes.get_scope("hmi_extruder_all"))
	var lines : Array = ov.call("extruder_lines")
	var bar : Node = ov.get_node_or_null("ExtruderLineBar")
	var btn_a : Button = bar.find_child("Line_3a", true, false) as Button if bar != null else null
	var btn_b : Button = bar.find_child("Line_3b", true, false) as Button if bar != null else null
	_check(lines.size() == 2 and String(lines[0]) == "3a" and String(lines[1]) == "3b"
			and String(ov.call("selected_extruder_line")) == "3a"
			and bar != null and bar.visible and btn_a != null and btn_b != null
			and btn_a.button_pressed and not btn_b.button_pressed,
		"C1 the all-lines extruder HMI offers one button per extruder in the world %s, opens on 3A (its scope's first line with an extruder)"
		% str(lines))

	var a_sp0 : float = ma.screw_rpm_setpoint
	if btn_b != null:
		btn_b.pressed.emit()
	ov.call("_apply_setpoint", "EREMA Extruder Scherm 3C.dc.html", "extr_rpm", 100.0, "rpm")
	_check(String(ov.call("selected_extruder_line")) == "3b" and btn_b != null and btn_b.button_pressed
			and absf(mb.screw_rpm_setpoint - 100.0) < 1e-6 and absf(ma.screw_rpm_setpoint - a_sp0) < 1e-6,
		"C2 pressing 'Lijn 3B' then setting extr rpm 100 moves 3B's setpoint (%.0f), not 3A's (%.0f, was %.0f)"
		% [mb.screw_rpm_setpoint, ma.screw_rpm_setpoint, a_sp0])

	var vals_b : Dictionary = ov.call("_gather_extruder_vals")
	ov.call("select_extruder_line", "3A")
	var vals_a : Dictionary = ov.call("_gather_extruder_vals")
	_check(absf(float(vals_b["extr_rpm"]["setpoint"]) - 100.0) < 1e-6
			and absf(float(vals_a["extr_rpm"]["setpoint"]) - a_sp0) < 1e-6,
		"C3 the screen shows the selected line's rpm setpoint: 3B %.0f, 3A %.0f"
		% [float(vals_b["extr_rpm"]["setpoint"]), float(vals_a["extr_rpm"]["setpoint"])])

	ov.call("select_extruder_line", "3b")
	ov.call("_apply_setpoint", "EREMA Extruder Scherm 3C.dc.html", "extr_rpm", 30.0, "rpm")
	var no6 : bool = bool(ov.call("select_extruder_line", "6"))
	_check(absf(mb.screw_rpm_setpoint - START_RPM_DOC) < 1e-6 and not no6
			and String(ov.call("selected_extruder_line")) == "3b",
		"C4 extr rpm 30 through the HMI reads %.0f (the drive's minimum); choosing line 6 with no extruder there is refused"
		% mb.screw_rpm_setpoint)

	# The touchscreen: MACHINES -> extruder_3b -> the zone panel's rpm row.
	var zp = load("res://src/scenes/hud/ExtruderZonePanel.gd").new()
	add_child(zp)
	zp.call("bind", mb)
	var sl : HSlider = zp.find_child("ScrewRpmSlider", true, false) as HSlider
	var ok_range : bool = sl != null and absf(sl.min_value - START_RPM_DOC) < 1e-6 \
		and absf(sl.max_value - mb.config.screw_rpm_max) < 1e-6
	if sl != null:
		sl.value = 95.0
	_check(ok_range and absf(mb.screw_rpm_setpoint - 95.0) < 1e-6,
		"C5 the touchscreen's extruder panel has an rpm slider %s-%s rpm, and moving it to 95 sets 3B's setpoint (%.0f)"
		% [str(sl.min_value) if sl != null else "?", str(sl.max_value) if sl != null else "?", mb.screw_rpm_setpoint])

	# A start resets the model to 60; the slider must follow the model.
	_hand_restart(b, float(mb.call("_preheat_ready_temp")) + 5.0)
	zp.call("_process", 0.0)
	var rd : Label = zp.find_child("ScrewRpmReadout", true, false) as Label
	_check(mb.state == ExtruderModel.State.STARTING and sl != null and absf(sl.value - START_RPM_DOC) < 1e-6
			and rd != null and rd.text.begins_with("sp 60"),
		"C6 a start puts 3B back to 60 and the slider follows (%s, slider %s, '%s')"
		% [mb.get_state_name(), str(sl.value) if sl != null else "?", rd.text if rd != null else "?"])

	zp.queue_free()
	ov.queue_free()
	for rig in [a, b]:
		rig["body"].queue_free()
		rig["laser"].queue_free()
		rig["head"].queue_free()
	await get_tree().process_frame


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
