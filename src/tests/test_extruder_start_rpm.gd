extends Node

# =============================================================================
# An extruder start ramps the screw to the operator's rpm setpoint, 60 rpm is
# the floor and a new extruder's setpoint, the player sets the rpm per line on
# the HMI, and a WARM restart at the green button's temperature neither trips
# 318 bar nor passes lumps when the operator starts it at 60.
# =============================================================================
# The finding (docs/audit/extruder_ramp_pressures_2026-09-25.md §5 items 1-2,
# re-measured with src/tests/probe_warm_restart_pressure.tscn on main 64921ff
# and on #290): a model that had run before (runtime_s past startup_ramp_s)
# re-entered RUNNING at NOMINAL flow, so a restart at the coldest melt the green
# button accepted (196.25 C) drove MP<MF to 317 bar and tripped 318 about 4.5 s
# after the green button, on 3A and 3B, through the plain gameplay path (stop,
# wait, PREHEAT, green) too. A FRESH model re-ramped from idle in RUNNING (a
# lifetime-runtime ramp) whatever the setpoint, so test_extruder_melt_pressures,
# which only starts fresh models, never saw it, and nothing the operator set
# could change either.
#
# Operator rulings 2026-09-25 (docs/plant/operator_rulings_2026-09-25.md):
#   * 60 rpm is "the minimum value possible to set"; a start "will ramp up to
#     that 80 [the setpoint]. It will not be 80 instantly"; ~3 s to 60, so the
#     ramp runs at 20 rpm/s. After a 318 trip, restarting at 100 rpm trips again
#     as it ramps up: "So you can put it at 60 RPM. And then hope that it is
#     able to start." A start does NOT always go to 60 ("that's not how
#     operating works").
#   * a new extruder's setpoint is 60; every extruder; the player sets the rpm
#     on the HMI, with a line choice on the one all-lines extruder HMI.
#   * the green button also waits until the screw passes no lumps (95 % torque),
#     with the same 25 % margin as the torque trip: green = 201.875 C on 3A/3B.
#     At 60 rpm, green at the old 196.25 C still tripped, through lumps
#     (RUNNING entry at 95.7 % torque, 3.4 g/s, 318 in 0.3 s).
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
const MIN_RPM_DOC : float = 60.0        # the floor, and a new extruder's setpoint
const RAMP_RPM_PER_S : float = 20.0     # 60 rpm in ~3 s
const GREEN_3AB_C : float = 201.875     # 215 - (95 - 60) % / (20 %/10 C) x 0.75
const OLD_GREEN_C : float = 196.25      # the torque-trip-only green it replaced
const SAFE_MAX_BAR : float = 280.0      # operator 2026-09-24: safe max before the laserfilter
const TRIP_BAR : float = 318.0          # the laserfilter's emergency shutdown
const MP_BEFORE_OK_BAR := Vector2(177.0, 280.0)   # test_extruder_melt_pressures' nominal band
const WARM_RUN_S : float = 300.0        # past the old startup_ramp_s (180 s)
const WATCH_S : float = 240.0
# A screen still caked from a 318 trip: 151.5 bar of cake at setpoint melt puts
# MP<MF at 25 + 161.5 + 151.5 = 338 bar at nominal flow, 253 bar at 60 rpm.
const CAKE_BAR : float = 151.5

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
	print("=== extruder start: ramp to the setpoint, 60 floor, warm restart at green ===")
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


## Step STARTING to its end. Returns {first_rpm, t, law_err}.
func _ramp(m: ExtruderModel) -> Dictionary:
	var r := {"first_rpm": -1.0, "t": 0.0, "law_err": 0.0}
	var ticks := 0
	while m.state == ExtruderModel.State.STARTING and ticks < 200:
		m.tick(DT, {})
		ticks += 1
		if float(r["first_rpm"]) < 0.0:
			r["first_rpm"] = m.screw_rpm
		r["law_err"] = maxf(float(r["law_err"]), absf(m.throughput_kg_h - _flow_law(m, m.screw_rpm)))
	r["t"] = ticks * DT
	return r


# ── A. the start rule on a bare model ─────────────────────────────────────────
func _part_a_model(cfg: ExtruderConfig) -> void:
	print("  -- A. the start rule (bare Extruder3B model) --")
	var m := ExtruderModel.new(cfg.duplicate())
	_check(absf(m.screw_rpm_setpoint - MIN_RPM_DOC) < 1e-6,
		"A0 a new extruder's rpm setpoint is %.0f (ruling; it was nominal): %.0f" % [MIN_RPM_DOC, m.screw_rpm_setpoint])
	var started := _bare_start(m, m.config.melt_temp_setpoint)
	var r := _ramp(m)
	_check(started and float(r["first_rpm"]) > 0.0
			and absf(float(r["first_rpm"]) - RAMP_RPM_PER_S * DT) < 1e-4,
		"A1 the first STARTING tick runs the screw from standstill at 20 rpm/s: %.2f rpm after 0.1 s (not an idle rpm)"
		% float(r["first_rpm"]))
	_check(m.state == ExtruderModel.State.RUNNING and absf(float(r["t"]) - MIN_RPM_DOC / RAMP_RPM_PER_S) < DT + 1e-4
			and absf(m.screw_rpm - MIN_RPM_DOC) < 1e-3,
		"A2 at the new setpoint the screw reaches %.0f rpm and the model is RUNNING %.1f s after the start (operator: ~3 s) at %.2f rpm"
		% [MIN_RPM_DOC, float(r["t"]), m.screw_rpm])
	_check(float(r["law_err"]) < 1e-3,
		"A3 on every STARTING tick the flow follows the screw (nominal x rpm / nominal rpm): worst %.5f kg/h off"
		% float(r["law_err"]))
	var thru10 := 0.0
	for i in range(int(600.0 / DT)):
		m.tick(DT, {})
		if i == int(10.0 / DT):
			thru10 = m.throughput_kg_h
	var want60 : float = m.config.nominal_kg_per_h * MIN_RPM_DOC / m.config.screw_rpm_nominal
	_check(m.state == ExtruderModel.State.RUNNING and absf(m.screw_rpm - MIN_RPM_DOC) < 1e-3
			and absf(m.throughput_kg_h - want60) < 0.01 and absf(thru10 - m.throughput_kg_h) < 1e-6,
		"A4 RUNNING holds the setpoint: 600 s later still %.2f rpm and %.1f kg/h (= %.1f at 60 rpm; %.1f at 10 s), no hidden ramp to nominal"
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
	_check(absf(lo - MIN_RPM_DOC) < 1e-6 and absf(hi - m.config.screw_rpm_max) < 1e-6,
		"A6 the setpoint cannot go under %.0f rpm (40 reads %.0f) nor past the line's max (400 reads %.0f)"
		% [MIN_RPM_DOC, lo, hi])

	# A stop leaves the setpoint where the operator had it, and the restart ramps
	# back up to it (operator: "it will ramp up to that 80").
	var w := ExtruderModel.new(cfg.duplicate())
	_bare_start(w, w.config.melt_temp_setpoint)
	w.set_screw_rpm_setpoint(80.0)
	for _i in range(int(WARM_RUN_S / DT)):
		w.tick(DT, {})
	var warm_rt : float = w.runtime_s
	_bare_stop(w)
	var ws := _bare_start(w, w.config.melt_temp_setpoint)
	var sp_kept : float = w.screw_rpm_setpoint
	var f := ExtruderModel.new(cfg.duplicate())
	f.set_screw_rpm_setpoint(80.0)
	var fs := _bare_start(f, f.config.melt_temp_setpoint)
	var worst_dq := 0.0
	var t80 := -1.0
	for i in range(100):
		w.tick(DT, {})
		f.tick(DT, {})
		worst_dq = maxf(worst_dq, absf(_q(w) - _q(f)))
		if t80 < 0.0 and w.state == ExtruderModel.State.RUNNING:
			t80 = (i + 1) * DT
	_check(ws and absf(sp_kept - 80.0) < 1e-6 and absf(t80 - 80.0 / RAMP_RPM_PER_S) < DT + 1e-4
			and absf(w.screw_rpm - 80.0) < 1e-3,
		"A7 a stop keeps the operator's 80 rpm setpoint (%.0f after the restart) and the restart ramps back to it, RUNNING at %.1f s (20 rpm/s gives 4.0)"
		% [sp_kept, t80])
	_check(fs and warm_rt > 180.0 and worst_dq < 1e-6,
		"A8 a warm restart (runtime %.0f s) and a model's first start at the same setpoint run the same 10 s: worst flow difference q %.7f"
		% [warm_rt, worst_dq])

	# A restart during the coast-down, the setpoint lowered to 60 meanwhile: the
	# screw slows to 60 rather than climbing on.
	var c := ExtruderModel.new(cfg.duplicate())
	_bare_start(c, c.config.melt_temp_setpoint)
	c.set_screw_rpm_setpoint(c.config.screw_rpm_nominal)
	for _i in range(int(30.0 / DT)):
		c.tick(DT, {})
	c.tick(DT, {"stop_production": true})
	c.tick(DT, {})
	var coast_rpm : float = c.screw_rpm
	c.set_screw_rpm_setpoint(MIN_RPM_DOC)
	c.tick(DT, {"start_production": true})
	var cr := _ramp(c)
	_check(coast_rpm > MIN_RPM_DOC and c.state == ExtruderModel.State.RUNNING
			and absf(c.screw_rpm - MIN_RPM_DOC) < 1e-3,
		"A9 a restart during the coast-down (screw at %.1f rpm) with the setpoint put at 60 runs the screw down to %.1f rpm and RUNNING after %.1f s"
		% [coast_rpm, c.screw_rpm, float(cr["t"])])

	# A vacuum alarm keeps the screw where the operator has it.
	var v := ExtruderModel.new(cfg.duplicate())
	v.set_screw_rpm_setpoint(80.0)
	_bare_start(v, v.config.melt_temp_setpoint)
	for _i in range(int(10.0 / DT)):
		v.tick(DT, {})
	var thru_run : float = v.throughput_kg_h
	v.tick(DT, {"vacuum_lost": true})
	var in_alarm : bool = v.state == ExtruderModel.State.VACUUM_ALARM
	for _i in range(int(5.0 / DT)):
		v.tick(DT, {})
	_check(in_alarm and absf(v.screw_rpm - 80.0) < 1e-3 and absf(v.throughput_kg_h - thru_run) < 1e-3,
		"A10 a vacuum alarm at 80 rpm keeps 80 rpm and %.1f kg/h (%s, %.1f rpm, %.1f kg/h; it used to force nominal)"
		% [thru_run, v.get_state_name(), v.screw_rpm, v.throughput_kg_h])

	# The green button waits until the screw passes no lumps (ruling).
	var g := ExtruderModel.new(cfg.duplicate())
	var green : float = float(g.call("_preheat_ready_temp"))
	g.melt_temp = GREEN_3AB_C - 0.01
	var below : bool = g.preheat_ready()
	g.melt_temp = GREEN_3AB_C
	var at : bool = g.preheat_ready()
	_check(absf(green - GREEN_3AB_C) < 1e-6 and not below and at,
		"A11 the green button unlocks at %.3f C (ruling: %.3f, from the 95 %% lump point with the 25 %% margin; it was %.2f)"
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


## A warm rig (ran at nominal, stopped), restarted at the green temperature with
## the setpoint at `sp` (the operator's choice before pressing green).
func _warm_restart(lid: String, placeable: String, sp: float) -> Dictionary:
	var rig := _build_rig(lid, placeable)
	if rig.is_empty():
		return {}
	var m : ExtruderModel = rig["model"]
	var warm := _warm_up_and_stop(rig)
	m.set_screw_rpm_setpoint(sp)
	var green : float = float(m.call("_preheat_ready_temp"))
	var started := _hand_restart(rig, green)
	var r := _watch(rig, WATCH_S)
	r["rig"] = rig
	r["ok_setup"] = warm and started
	r["green"] = green
	return r


func _clean(r: Dictionary) -> bool:
	return bool(r.get("ok_setup", false)) and float(r["t_run"]) > 0.0 and float(r["trip_t"]) < 0.0 \
		and int(r["lump_ticks"]) == 0 and float(r["peak"]) < SAFE_MAX_BAR


func _part_b_rigs() -> void:
	print("  -- B. the wired rigs: a warm restart at the green button --")
	# B0 — a NEW extruder's first start at the green temperature: its setpoint
	# is 60 (ruling), so the start the player gets without touching the HMI.
	var n0 := _build_rig("3B", "extruder_3b")
	if not n0.is_empty():
		var nm : ExtruderModel = n0["model"]
		var started := _hand_restart(n0, float(nm.call("_preheat_ready_temp")))
		var r := _watch(n0, WATCH_S)
		r["ok_setup"] = started
		_check(_clean(r) and absf(nm.screw_rpm - MIN_RPM_DOC) < 1e-3,
			"B0 a new 3B's first start at the green %.3f C: RUNNING at %.1f s at %.0f rpm, no lumps, MP<MF peak %.1f bar < %.0f, no trip over %.0f s"
			% [float(nm.call("_preheat_ready_temp")), float(r["t_run"]), nm.screw_rpm, float(r["peak"]), SAFE_MAX_BAR, WATCH_S])

	for pair in [["B1", "3B", "extruder_3b"], ["B2", "3A", "extruder_3a"]]:
		var r := _warm_restart(String(pair[1]), String(pair[2]), MIN_RPM_DOC)
		if r.is_empty():
			continue
		var m : ExtruderModel = r["rig"]["model"]
		_check(_clean(r) and absf(m.screw_rpm - MIN_RPM_DOC) < 1e-3,
			"%s %s WARM restart (ran %.0f s at nominal, stopped, set to 60) at the green %.3f C: RUNNING at %.1f s, torque %.1f %%, no lumps (%d ticks), MP<MF peak %.1f bar < %.0f, no trip over %.0f s"
			% [pair[0], pair[1], WARM_RUN_S, float(r["green"]), float(r["t_run"]), float(r["torque_run"]),
				int(r["lump_ticks"]), float(r["peak"]), SAFE_MAX_BAR, WATCH_S])
		if pair[0] == "B1":
			# B4 — the player waits for the melt, then raises to nominal: the line
			# reaches its nominal pressures (the pressure path is live).
			var rig : Dictionary = r["rig"]
			var melt_at_raise : float = m.melt_temp
			m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
			var lo := INF
			var hi := -INF
			var trip := false
			for i in range(int(300.0 / DT)):
				_step(rig)
				if m.state == ExtruderModel.State.EMERGENCY_STOP:
					trip = true
					break
				if i * DT >= 120.0:
					var p := _mp_before(rig)
					lo = minf(lo, p)
					hi = maxf(hi, p)
			_check(not trip and m.state == ExtruderModel.State.RUNNING
					and absf(m.screw_rpm - m.config.screw_rpm_nominal) < 1e-3
					and lo >= MP_BEFORE_OK_BAR.x and hi <= MP_BEFORE_OK_BAR.y,
				"B4 raised to %.0f rpm at melt %.2f C: RUNNING at nominal, MP<MF %.1f..%.1f bar inside %.0f-%.0f (the nominal band), no trip"
				% [m.config.screw_rpm_nominal, melt_at_raise, lo, hi, MP_BEFORE_OK_BAR.x, MP_BEFORE_OK_BAR.y])

	# B3 — the gameplay path, nothing set by hand but the setpoint: stop, wait in
	# OFF until the melt is under the green temperature, start (PREHEAT), set 60,
	# green the tick the block turns green.
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
		gm.set_screw_rpm_setpoint(MIN_RPM_DOC)
		_press(g, "start_production")
		_step(g)
		var r := _watch(g, WATCH_S)
		r["ok_setup"] = warm and to_preheat
		_check(_clean(r),
			"B3 gameplay path: stop, %.1f s in OFF, start -> PREHEAT %.1f s, set 60, green at %.2f C: no trip over %.0f s, no lumps, MP<MF peak %.1f bar"
			% [t_off, t_pre, melt_green, WATCH_S, float(r["peak"])])

	# B5 — negative control: a 60-rpm warm restart with the melt at the OLD
	# green temperature trips, through lumps. The trip is armed at 60 rpm, and
	# the new green is what keeps B0-B3 clear of it.
	var n := _build_rig("3B", "extruder_3b")
	if not n.is_empty():
		var nm : ExtruderModel = n["model"]
		var warm := _warm_up_and_stop(n)
		nm.set_screw_rpm_setpoint(MIN_RPM_DOC)
		var started := _hand_restart(n, float(nm.call("_preheat_ready_temp")))
		nm.melt_temp = OLD_GREEN_C        # the green button no longer accepts it
		var r := _watch(n, 30.0)
		_check(warm and started and float(r["trip_t"]) > 0.0 and int(r["lump_ticks"]) > 0
				and String(r.get("fault", "")) == "laserfilter_upstream_overpressure_318bar",
			"B5 negative control: a warm 60-rpm start at the old green %.2f C passes lumps (%d ticks, torque %.1f %%) and trips 318 after %.1f s ('%s')"
			% [OLD_GREEN_C, int(r["lump_ticks"]), float(r["torque_run"]), float(r["trip_t"]), String(r.get("fault", ""))])

	# B6 — the operator's own account: a line that tripped 318 on a caked screen
	# trips again when restarted at its old 110 rpm, as it ramps up; put at 60,
	# the same screen lets it start.
	var k110 := _caked_restart(-1.0)
	var k60 := _caked_restart(MIN_RPM_DOC)
	if not k110.is_empty() and not k60.is_empty():
		_check(bool(k110["first_trip"]) and float(k110["trip_t"]) > 0.0
				and float(k110["rpm_at_trip"]) < 110.0 - 1e-3,
			"B6 a line that tripped 318 on a caked screen, reset and restarted at its old 110 rpm, trips again %.1f s in, while still ramping (%.1f rpm)"
			% [float(k110["trip_t"]), float(k110["rpm_at_trip"])])
		_check(bool(k60["first_trip"]) and float(k60["trip_t"]) < 0.0 and float(k60["peak"]) < TRIP_BAR,
			"B7 ...the same screen, restarted at 60 rpm, runs: MP<MF peak %.1f bar, no trip over 30 s" % float(k60["peak"]))

	# Measured, not gated (the operator accepted that it CAN trip; the margin is
	# thin): a warm restart at the green temperature with the setpoint left at 110.
	var e := _warm_restart("3B", "extruder_3b", 110.0)
	if not e.is_empty():
		_info("a warm restart at the green %.3f C with the setpoint left at 110 rpm: MP<MF peak %.1f bar, %s"
			% [float(e["green"]), float(e["peak"]),
				"no trip" if float(e["trip_t"]) < 0.0 else "trips 318 at %.1f s" % float(e["trip_t"])])


## A 3B run at nominal, tripped 318 by a caked screen, E-stop reset, and
## restarted onto the same cake at `sp` (< 0: the old nominal setpoint).
func _caked_restart(sp: float) -> Dictionary:
	var rig := _build_rig("3B", "extruder_3b")
	if rig.is_empty():
		return {}
	var m : ExtruderModel = rig["model"]
	var laser = rig["laser"]
	_press(rig, "start_production")
	_step(rig)
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
	for _i in range(int(WARM_RUN_S / DT)):
		_step(rig)
	var cake_g : float = CAKE_BAR * 14.5038 / LaserFilter.CAKE_PSI_PER_G
	var first_trip := false
	for _i in range(50):
		laser.set("front_loading_g", cake_g)
		laser.set("_rotation_timer", 0.0)
		_step(rig)
		if m.state == ExtruderModel.State.EMERGENCY_STOP:
			first_trip = true
			break
	_press(rig, "reset_after_estop")
	for _i in range(10):
		_step(rig)
		if m.state == ExtruderModel.State.OFF:
			break
	laser.set("front_loading_g", cake_g)       # the cake stays on the screen
	laser.set("_rotation_timer", 0.0)
	if sp > 0.0:
		m.set_screw_rpm_setpoint(sp)
	_hand_restart(rig, m.config.melt_temp_setpoint)
	var r := {"first_trip": first_trip, "trip_t": -1.0, "peak": 0.0, "rpm_at_trip": -1.0}
	for i in range(int(30.0 / DT)):
		var rpm_before : float = m.screw_rpm
		_step(rig)
		r["peak"] = maxf(float(r["peak"]), _mp_before(rig))
		if m.state == ExtruderModel.State.EMERGENCY_STOP:
			r["trip_t"] = (i + 1) * DT
			r["rpm_at_trip"] = rpm_before
			break
	return r


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
	_check(absf(mb.screw_rpm_setpoint - MIN_RPM_DOC) < 1e-6 and not no6
			and String(ov.call("selected_extruder_line")) == "3b",
		"C4 extr rpm 30 through the HMI reads %.0f (the drive's minimum); choosing line 6 with no extruder there is refused"
		% mb.screw_rpm_setpoint)

	# The touchscreen: MACHINES -> extruder_3b -> the zone panel's rpm row.
	var zp = load("res://src/scenes/hud/ExtruderZonePanel.gd").new()
	add_child(zp)
	zp.call("bind", mb)
	var sl : HSlider = zp.find_child("ScrewRpmSlider", true, false) as HSlider
	var ok_range : bool = sl != null and absf(sl.min_value - MIN_RPM_DOC) < 1e-6 \
		and absf(sl.max_value - mb.config.screw_rpm_max) < 1e-6
	if sl != null:
		sl.value = 95.0
	_check(ok_range and absf(mb.screw_rpm_setpoint - 95.0) < 1e-6,
		"C5 the touchscreen's extruder panel has an rpm slider %s-%s rpm, and moving it to 95 sets 3B's setpoint (%.0f)"
		% [str(sl.min_value) if sl != null else "?", str(sl.max_value) if sl != null else "?", mb.screw_rpm_setpoint])

	# The web HMI writes the same setpoint; the slider must follow the model,
	# and a start keeps it (it is where the start ramps to).
	ov.call("_apply_setpoint", "EREMA Extruder Scherm 3C.dc.html", "extr_rpm", 75.0, "rpm")
	_hand_restart(b, float(mb.call("_preheat_ready_temp")) + 5.0)
	zp.call("_process", 0.0)
	var rd : Label = zp.find_child("ScrewRpmReadout", true, false) as Label
	_check(mb.state == ExtruderModel.State.STARTING and absf(mb.screw_rpm_setpoint - 75.0) < 1e-6
			and sl != null and absf(sl.value - 75.0) < 1e-6 and rd != null and rd.text.begins_with("sp 75"),
		"C6 the web HMI puts 3B at 75, a start keeps 75, and the touchscreen slider follows (%s, slider %s, '%s')"
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
