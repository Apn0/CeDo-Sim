extends Node

# =============================================================================
# PROBE (measures, asserts nothing): a WARM restart of a real catalog extruder
# at the preheat-ready melt, and the 318-bar trip before the laserfilter.
# =============================================================================
# Finding carried in from docs/audit/extruder_ramp_pressures_2026-09-25.md §5
# items 1-2: a model that has run before (runtime_s past startup_ramp_s) re-enters
# RUNNING at nominal flow, so a restart at the coldest melt the green button
# accepts (ExtruderModel._preheat_ready_temp(), derived from TORQUE headroom
# only) drives MP<MF to ~317 bar and trips 318. A FRESH model re-ramps from idle
# in RUNNING and does not. test_extruder_melt_pressures only starts fresh models.
#
# Same rig as test_extruder_melt_pressures (`_build_rig` / `_step`): the catalog
# extruder (build_node -> MachineBrains) with a real LaserFilter and HeadFilter,
# stepped by hand at 0.1 s. No MainWorld boot, nothing under user:// touched.
#
#   godot --headless --path . res://src/tests/probe_warm_restart_pressure.tscn
#
# Sections:
#   A  fresh model at the ready melt (the suite's own case, control)
#   B  warm model at the ready melt, melt set by hand (the finding), traced
#   C  B with the screen's cake wiped before the restart (is it the cake?)
#   D  warm model, gameplay path, nothing set by hand: stop, wait in OFF until
#      the melt is under the ready temperature, start (PREHEAT), green button
#      the tick preheat_ready() goes true
#   E  D after a long stop: the barrel cools to ambient, a full PREHEAT
#   F  deficit scan: warm restart at setpoint minus d, for d 0 .. 18.75 C
#   G  what-if, first-start re-ramp on EVERY start: B with runtime_s = 0
#   H  3A: B and G
# =============================================================================

const DT : float = 0.1
const WATCHDOG_S : float = 900.0
const PSI_PER_BAR : float = 14.5038
const RUN_S : float = 300.0     # the audit's warm-up run (past startup_ramp_s 180)
const WATCH_S : float = 240.0

var _done : bool = false
var _x : float = 0.0


func _ready() -> void:
	print("=== PROBE warm restart at the preheat-ready melt vs the 318-bar trip ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame

	_section_a()
	_section_b("3B", "extruder_3b", false)
	_section_b("3B", "extruder_3b", true)
	_section_d(false)
	_section_d(true)
	_section_f()
	_section_g("3B", "extruder_3b")
	_section_b("3A", "extruder_3a", false)
	_section_g("3A", "extruder_3a")
	_section_i(0.0)
	_section_i(30.0)
	_section_i(70.0)
	_section_j()
	_done = true
	print("PROBE DONE")
	get_tree().quit(0)


# ── rig (as test_extruder_melt_pressures) ─────────────────────────────────────
func _build_rig(lid: String, placeable: String) -> Dictionary:
	_x += 1000.0
	var body := PlaceableCatalog.build_node(placeable, false)
	add_child(body)
	body.global_position = Vector3(_x, 0.0, 0.0)
	var brain := body.get_node_or_null("SimBrain")
	var laser : Node3D = load("res://src/sim/LaserFilter.gd").new()
	add_child(laser)
	laser.global_position = Vector3(_x + 6.0, 0.0, 0.0)
	var head : Node3D = load("res://src/sim/HeadFilter.gd").new()
	add_child(head)
	head.global_position = Vector3(_x + 9.0, 0.0, 0.0)
	brain.call("_resolve_downstream_filters")
	if brain.get("_laser_filter") != laser or brain.get("_head_filter") != head:
		print("FATAL: %s brain did not resolve its own filters" % lid)
	return {"lid": lid, "body": body, "brain": brain, "model": brain.get("model"),
		"laser": laser, "head": head}


func _step(rig: Dictionary) -> void:
	rig["laser"].call("_physics_process", DT)
	rig["head"].call("_physics_process", DT)
	rig["brain"].call("_on_sim_tick", DT)


func _press(rig: Dictionary, key: String) -> void:
	rig["brain"].get("_pending")[key] = true


func _mp_before(rig: Dictionary) -> float:
	return float(rig["laser"].call("mp_before_filter_bar"))


func _dmp(rig: Dictionary) -> float:
	return float(rig["laser"].get("delta_p_psi")) / PSI_PER_BAR


func _q(model) -> float:
	return model.throughput_kg_h / maxf(1.0, model.config.nominal_kg_per_h)


func _estop(model) -> bool:
	return model.state == ExtruderModel.State.EMERGENCY_STOP


## Run a fresh rig RUN_S seconds from a start at the handed-over (setpoint) melt,
## then press stop and step to OFF. Returns the screen state at the stop.
func _warm_up_and_stop(rig: Dictionary) -> Dictionary:
	var model = rig["model"]
	_press(rig, "start_production")
	_step(rig)
	# Since 2026-09-25 every start leaves the screw at screw_rpm_min; the player
	# raises it. On the older model this writes the nominal it already held.
	model.set_screw_rpm_setpoint(model.config.screw_rpm_nominal)
	var peak_run := 0.0
	for _i in range(int(RUN_S / DT) - 1):
		_step(rig)
		peak_run = maxf(peak_run, _mp_before(rig))
	var at_stop := {
		"state": model.get_state_name(), "runtime_s": model.runtime_s,
		"mp_before": _mp_before(rig), "dmp": _dmp(rig), "peak_run": peak_run,
		"front_g": float(rig["laser"].get("front_loading_g")),
		"back_g": float(rig["laser"].get("back_loading_g")),
	}
	_press(rig, "stop_production")
	var t := 0.0
	while model.state != ExtruderModel.State.OFF and t < 120.0:
		_step(rig)
		t += DT
	at_stop["stop_to_off_s"] = t
	at_stop["melt_at_off"] = model.melt_temp
	return at_stop


## From OFF: the melt set by hand, the start pressed; a melt under the ready
## temperature goes to PREHEAT first (OFF cools 0.05 C before routing), so the
## green button is pressed a second time there. True when it reached STARTING.
func _hand_restart(rig: Dictionary, melt: float) -> bool:
	var model = rig["model"]
	model.melt_temp = melt
	_press(rig, "start_production")
	_step(rig)
	if model.state == ExtruderModel.State.PREHEAT:
		model.melt_temp = melt
		_press(rig, "start_production")
		_step(rig)
	return model.state == ExtruderModel.State.STARTING


## Step WATCH_S (or to the trip) after the green button. `trace` prints every
## tick of the first 6 s and every 1 s to 20 s.
func _watch(rig: Dictionary, trace: bool) -> Dictionary:
	var model = rig["model"]
	var r := {"peak": 0.0, "t_peak": -1.0, "trip_t": -1.0, "t_running": -1.0,
		"state_at_peak": "", "q_at_peak": 0.0, "melt_at_peak": 0.0,
		"after_at_peak": 0.0, "dmp_at_peak": 0.0, "visc_at_peak": 0.0,
		"over_280_s": 0.0, "peak_running": 0.0}
	if trace:
		print("      t(s)  state      q      melt   visc   MP>MF    dMP    MP<MF   front_g")
	var n := int(WATCH_S / DT)
	for i in range(n):
		_step(rig)
		var t := (i + 1) * DT
		var mp := _mp_before(rig)
		if r["t_running"] < 0.0 and model.state == ExtruderModel.State.RUNNING:
			r["t_running"] = t
		if model.state == ExtruderModel.State.RUNNING:
			r["peak_running"] = maxf(r["peak_running"], mp)
		if mp > 280.0:
			r["over_280_s"] += DT
		if mp > r["peak"]:
			r["peak"] = mp
			r["t_peak"] = t
			r["state_at_peak"] = model.get_state_name()
			r["q_at_peak"] = _q(model)
			r["melt_at_peak"] = model.melt_temp
			r["after_at_peak"] = model.mp_after_laserfilter_bar
			r["dmp_at_peak"] = _dmp(rig)
			r["visc_at_peak"] = model.melt_viscosity_factor
		if trace and (i < 60 or (i < 200 and (i + 1) % 10 == 0)):
			print("    %6.1f  %-9s  %5.3f  %6.2f  %5.3f  %6.1f  %6.1f  %6.1f   %7.1f" % [
				t, model.get_state_name(), _q(model), model.melt_temp, model.melt_viscosity_factor,
				model.mp_after_laserfilter_bar, _dmp(rig), mp,
				float(rig["laser"].get("front_loading_g"))])
		if _estop(model):
			r["trip_t"] = t
			r["fault"] = String(model.fault_reason)
			r["melt_at_trip"] = model.melt_temp
			break
	r["end_state"] = model.get_state_name()
	r["end_melt"] = model.melt_temp
	r["end_rpm"] = model.screw_rpm
	r["end_q"] = _q(model)
	r["end_mp"] = _mp_before(rig)
	return r


func _say(tag: String, r: Dictionary) -> void:
	var trip := "NO TRIP" if r["trip_t"] < 0.0 else "TRIP at %.1f s after green ('%s', melt %.2f C)" % [
		r["trip_t"], r.get("fault", ""), r.get("melt_at_trip", 0.0)]
	print("  %s: RUNNING from %.1f s; MP<MF peak %.1f bar at %.1f s (%s, q %.3f, melt %.2f, visc %.3f, MP>MF %.1f + dMP %.1f); >280 bar for %.1f s; %s; end %s melt %.2f" % [
		tag, r["t_running"], r["peak"], r["t_peak"], r["state_at_peak"], r["q_at_peak"],
		r["melt_at_peak"], r["visc_at_peak"], r["after_at_peak"], r["dmp_at_peak"],
		r["over_280_s"], trip, r["end_state"], r["end_melt"]])
	print("      end: %.1f rpm, q %.3f, MP<MF %.1f bar" % [r["end_rpm"], r["end_q"], r["end_mp"]])


func _say_stop(s: Dictionary) -> void:
	print("  warm-up %.0f s: %s, runtime_s %.1f, MP<MF %.1f (dMP %.1f, run peak %.1f), cake front %.2f g back %.2f g; stop->OFF %.1f s, melt at OFF %.2f C" % [
		RUN_S, s["state"], s["runtime_s"], s["mp_before"], s["dmp"], s["peak_run"],
		s["front_g"], s["back_g"], s["stop_to_off_s"], s["melt_at_off"]])


# ── A: fresh model at the ready melt (control) ────────────────────────────────
func _section_a() -> void:
	print("\n-- A  3B FRESH model, start at the preheat-ready melt (test_extruder_melt_pressures' case) --")
	var rig := _build_rig("3B", "extruder_3b")
	var model = rig["model"]
	var ready_c : float = float(model.call("_preheat_ready_temp"))
	print("  preheat-ready %.2f C, setpoint %.1f C, runtime_s %.1f, startup_ramp_s %.0f" % [
		ready_c, model.config.melt_temp_setpoint, model.runtime_s, model.config.startup_ramp_s])
	var ok := _hand_restart(rig, ready_c)
	print("  reached STARTING: %s" % str(ok))
	_say("A fresh", _watch(rig, false))


# ── B / C: warm model at the ready melt ───────────────────────────────────────
func _section_b(lid: String, placeable: String, wipe_cake: bool) -> void:
	print("\n-- %s  %s WARM model, restart at the preheat-ready melt%s --" % [
		"C" if wipe_cake else ("B" if lid == "3B" else "H"), lid,
		", screen cake wiped first" if wipe_cake else ""])
	var rig := _build_rig(lid, placeable)
	var model = rig["model"]
	var ready_c : float = float(model.call("_preheat_ready_temp"))
	_say_stop(_warm_up_and_stop(rig))
	if wipe_cake:
		rig["laser"].set("front_loading_g", 0.0)
		rig["laser"].set("back_loading_g", 0.0)
	var ok := _hand_restart(rig, ready_c)
	print("  restart at %.2f C (%.2f C cold), runtime_s %.1f: reached STARTING %s" % [
		ready_c, model.config.melt_temp_setpoint - ready_c, model.runtime_s, str(ok)])
	_say("%s warm%s" % [lid, " clean" if wipe_cake else ""], _watch(rig, not wipe_cake))


# ── D / E: gameplay path, nothing set by hand ─────────────────────────────────
func _section_d(long_stop: bool) -> void:
	print("\n-- %s  3B WARM model, gameplay path%s --" % [
		"E" if long_stop else "D", ": barrel cooled to ambient, full PREHEAT" if long_stop else ""])
	var rig := _build_rig("3B", "extruder_3b")
	var model = rig["model"]
	var ready_c : float = float(model.call("_preheat_ready_temp"))
	_say_stop(_warm_up_and_stop(rig))
	var t_off := 0.0
	var until : float = ExtruderModel.AMBIENT_C + 0.01 if long_stop else ready_c
	while model.melt_temp >= until and t_off < 3600.0:
		_step(rig)
		t_off += DT
	print("  OFF %.1f s until the melt read %.2f C (< %.2f)" % [t_off, model.melt_temp, until])
	_press(rig, "start_production")
	_step(rig)
	print("  start pressed -> %s" % model.get_state_name())
	var t_pre := 0.0
	while model.state == ExtruderModel.State.PREHEAT and not model.preheat_ready() and t_pre < 3600.0:
		_step(rig)
		t_pre += DT
	print("  PREHEAT %.1f s until preheat_ready() at %.2f C" % [t_pre, model.melt_temp])
	_press(rig, "start_production")
	_step(rig)
	print("  green button -> %s (runtime_s %.1f)" % [model.get_state_name(), model.runtime_s])
	_say("%s gameplay" % ("E" if long_stop else "D"), _watch(rig, false))


# ── F: deficit scan ───────────────────────────────────────────────────────────
func _section_f() -> void:
	print("\n-- F  3B WARM restart, melt setpoint - d (each d on its own fresh rig warmed %.0f s) --" % RUN_S)
	for d in [0.0, 4.0, 6.0, 7.0, 8.0, 9.0, 10.0, 12.0, 14.0, 16.0, 18.75]:
		var rig := _build_rig("3B", "extruder_3b")
		var model = rig["model"]
		_warm_up_and_stop(rig)
		var ok := _hand_restart(rig, model.config.melt_temp_setpoint - d)
		var r := _watch(rig, false)
		print("  d %5.2f C: STARTING %s  MP<MF peak %6.1f bar at %5.1f s (%s)  >280 %5.1f s  %s" % [
			d, str(ok), r["peak"], r["t_peak"], r["state_at_peak"], r["over_280_s"],
			"NO TRIP" if r["trip_t"] < 0.0 else "TRIP at %.1f s" % r["trip_t"]])


# ── G: what-if, the first-start re-ramp on every start ────────────────────────
func _section_g(lid: String, placeable: String) -> void:
	print("\n-- G  %s WARM model at the ready melt, runtime_s zeroed before the restart (re-ramp on every start) --" % lid)
	var rig := _build_rig(lid, placeable)
	var model = rig["model"]
	var ready_c : float = float(model.call("_preheat_ready_temp"))
	_warm_up_and_stop(rig)
	model.runtime_s = 0.0
	var ok := _hand_restart(rig, ready_c)
	print("  reached STARTING %s" % str(ok))
	_say("%s re-ramp" % lid, _watch(rig, false))


# ── I: the player raises the rpm to nominal N s after RUNNING ────────────────
## Only meaningful on the 60-rpm-start model: a restart at the preheat-ready
## melt, then the HMI setpoint goes to nominal `after_s` into RUNNING.
func _section_i(after_s: float) -> void:
	print("
-- I  3B WARM restart at the ready melt, the player sets nominal %.0f s into RUNNING --" % after_s)
	var rig := _build_rig("3B", "extruder_3b")
	var model = rig["model"]
	var ready_c : float = float(model.call("_preheat_ready_temp"))
	_warm_up_and_stop(rig)
	_hand_restart(rig, ready_c)
	var t := 0.0
	var t_run := -1.0
	var raised := false
	var peak := 0.0
	var trip_t := -1.0
	var melt_at_raise := 0.0
	for i in range(int(WATCH_S / DT)):
		_step(rig)
		t = (i + 1) * DT
		if t_run < 0.0 and model.state == ExtruderModel.State.RUNNING:
			t_run = t
		if not raised and t_run >= 0.0 and t - t_run >= after_s:
			model.set_screw_rpm_setpoint(model.config.screw_rpm_nominal)
			raised = true
			melt_at_raise = model.melt_temp
		peak = maxf(peak, _mp_before(rig))
		if _estop(model):
			trip_t = t
			break
	print("  RUNNING at %.1f s (%.1f rpm); raised at melt %.2f C; MP<MF peak %.1f bar; %s; end %s %.1f rpm q %.3f MP<MF %.1f" % [
		t_run, model.screw_rpm if trip_t < 0.0 else 0.0, melt_at_raise, peak,
		"NO TRIP" if trip_t < 0.0 else "TRIP at %.1f s ('%s')" % [trip_t, model.fault_reason],
		model.get_state_name(), model.screw_rpm, _q(model), _mp_before(rig)])


# ── J: fine scan near the ready melt, with torque and lumps at RUNNING entry ──
func _section_j() -> void:
	print("
-- J  3B WARM restart, fine scan near the preheat-ready melt (torque / lumps on the first RUNNING tick) --")
	for d in [16.0, 16.5, 17.0, 17.25, 17.5, 17.75, 18.0, 18.25, 18.5, 18.75]:
		var rig := _build_rig("3B", "extruder_3b")
		var model = rig["model"]
		_warm_up_and_stop(rig)
		_hand_restart(rig, model.config.melt_temp_setpoint - d)
		var first := {}
		var peak := 0.0
		var trip_t := -1.0
		var lump_ticks := 0
		var lump_max := 0.0
		for i in range(int(60.0 / DT)):
			_step(rig)
			if first.is_empty() and model.state == ExtruderModel.State.RUNNING:
				first = {"melt": model.melt_temp, "torque": model.motor_torque_pct,
					"lump": model.lump_passthrough_rate_g_s}
			if model.state == ExtruderModel.State.RUNNING and model.lump_passthrough_rate_g_s > 0.0:
				lump_ticks += 1
				lump_max = maxf(lump_max, model.lump_passthrough_rate_g_s)
			peak = maxf(peak, _mp_before(rig))
			if _estop(model):
				trip_t = (i + 1) * DT
				break
		print("  d %5.2f C (green at %.2f): RUNNING entry melt %.2f torque %.2f %% lumps %.2f g/s; RUNNING ticks with lumps %d (max %.2f g/s); MP<MF peak %.1f; %s" % [
			d, model.config.melt_temp_setpoint - d, float(first.get("melt", 0.0)), float(first.get("torque", 0.0)),
			float(first.get("lump", 0.0)), lump_ticks, lump_max, peak,
			"NO TRIP" if trip_t < 0.0 else "TRIP at %.1f s" % trip_t])


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("PROBE WATCHDOG — no end after %.0f s (a SCRIPT ERROR above aborted it)" % WATCHDOG_S)
	get_tree().quit(2)
