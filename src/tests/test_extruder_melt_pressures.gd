extends Node

# =============================================================================
# Melt pressures of the 3A / 3B extruders: bar, at the right points, and both
# documented over-pressure trips reachable.
# =============================================================================
# Regression guard for the unit defect measured 2026-09-24 on `main` b8bda8a:
# ExtruderModel carried ONE pressure, `die_pressure_psi`, based on 280 "psi"
# ("operator-documented", no source named). Every plant source gives 280 in BAR.
# A nominal 3B run held 280.0 psi, the BluPort showed 19.3 bar, and the 160-bar
# MP<PEL interlock sat 8.3x above nominal. Neither documented trip could ever
# fire: the model topped out near 46 bar before the 110 % torque trip, and on
# 3A the laserfilter's 318-bar check read the KOPFILTER's dP (<= 41 bar).
#
# The operator's rulings (2026-09-24, docs/plant/operator_rulings_2026-09-24.md):
#   * 280 is bar: a safe maximum before the laserfilter, kept under the
#     318-bar emergency shutdown. He would rather run ~220 bar.
#   * TWO pressures. Line order: screw -> laserfilter (MF1) -> degassing ->
#     melt pump -> kopfilter (MF2) -> heetafslag.
#   * Before the laserfilter = the melt-set pressure AFTER it + the screen's own
#     dMP ("both": melt and screen cake). A caking screen climbs to 318.
#   * The 160-bar MP<PEL trip reads the dP ACROSS the kopfilter.
#   * The die-side (kopdruk) nominal is per line, from FORM-008.
#
# Every number asserted below is typed from a document, not read back from the
# config under test (a check that reads the config would bless any value):
#   MP>MF 25 bar ................ docs/plant/hmi_reference.md sec 1 (3A laserfilter
#                                 screen: MP<MF 207, dMP 182, MP>MF 25); line 6
#                                 22 bar, 3C 24/26 bar (PHOTO-erema-bluport-*)
#   MP<MF <= 280 bar ............ operator ruling (safe max; 318 = shutdown)
#   MP<MF >= 177 bar ............ lowest documented steady reading before the
#                                 meltfilter: 3B trend p50 (trends_overview.md sec 2)
#   kopdruk 3A 120-150 bar ...... FORM-008 row 25 (checklist_3a_3b.md:60)
#   kopdruk 3B 140-155 bar ...... FORM-008 row 26 (checklist_3a_3b.md:61)
#   kopdruk trend 3A 103-173,
#                 3B 106-166 .... trends_overview.md sec 2 (p5-p95)
#   kopfilter >= 1x per dienst .. FORM-008 row 27 -> one 8 h shift of pack loading
#   318 bar ..................... LaserFilter.UPSTREAM_TRIP_BAR (062_CeDo72; plant 318)
#   160 bar ..................... EREMA manual 4.3.7 (169_CeDo84)
#   6.83 bar/C at 280 bar ....... 3A trend fit of MP<MF against melt temperature
#                                 (#275; ExtruderModel.DIE_PRESSURE_BAR_PER_C doc).
#                                 The operator (2026-09-25): a colder melt raises
#                                 the laserfilter's own dMP too.
#
#   godot --headless --path . res://src/tests/test_extruder_melt_pressures.tscn
#
# Drives the REAL catalog extruders (build_node -> MachineBrains -> per-line
# ExtruderConfig) with a real LaserFilter and HeadFilter each, ticked by hand
# at the 0.1 s SimTick rate. No MainWorld boot. Exits 0 on pass, 1 on failure,
# 2 on the watchdog.
# =============================================================================

const DT : float = 0.1
const RUN_S : float = 600.0          # same span as the 2026-09-24 probe
const SAMPLE_FROM_S : float = 300.0  # sample the steady tail (was startup_ramp_s 180 s + margin)
const SHIFT_H : float = 8.0          # FORM-008 row 27: kopfilters >= 1x per dienst
const PSI_PER_BAR : float = 14.5038
const WATCHDOG_S : float = 240.0

# Documented values (see header). Deliberately NOT read from ExtruderConfig.
const MP_AFTER_DOC_BAR   := Vector2(18.0, 26.0)     # 3A 25, line 6 18-22, 3C 24-26
const MP_BEFORE_OK_BAR   := Vector2(177.0, 280.0)   # 3B trend p50 .. operator safe max
const KOPDRUK_FORM008 := {"3A": Vector2(120.0, 150.0), "3B": Vector2(140.0, 155.0)}
const KOPDRUK_TREND   := {"3A": Vector2(103.0, 173.0), "3B": Vector2(106.0, 166.0)}
const MP_BEFORE_TREND := {"3A": Vector2(6.0, 280.0),   "3B": Vector2(7.0, 190.0)}

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


## A property that may not exist (the pre-fix tree has none of the bar fields):
## NAN instead of a SCRIPT ERROR, so the old tree reports clean FAILs.
func _num(obj: Object, prop: String) -> float:
	if obj == null or not (prop in obj):
		return NAN
	return float(obj.get(prop))


func _call_num(obj: Object, method: String) -> float:
	if obj == null or not obj.has_method(method):
		return NAN
	return float(obj.call(method))


func _in(v: float, band: Vector2) -> bool:
	return not is_nan(v) and v >= band.x and v <= band.y


func _ready() -> void:
	print("=== extruder melt pressures (bar, two points, both trips) ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	# Watchdog: a runtime SCRIPT ERROR aborts _ready() and the scene would idle
	# forever with no verdict (CLAUDE.md, "a headless run that outlives...").
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame

	var lines := {}
	var x := 0.0
	for pair in [["3A", "extruder_3a"], ["3B", "extruder_3b"]]:
		var rig := _build_rig(String(pair[0]), String(pair[1]), x)
		if rig.is_empty():
			_finish()
			return
		lines[pair[0]] = rig
		x += 1000.0   # far apart: each brain's nearest-filter lookup finds its own
	await get_tree().process_frame

	for lid in ["3A", "3B"]:
		_check_per_line_config(lid, lines[lid])
	for lid in ["3A", "3B"]:
		_run_nominal(lid, lines[lid])
	_check_readouts(lines["3A"])
	_check_pel_trip(lines["3A"])
	_check_upstream_trip_caked_screen(lines["3B"])
	_check_upstream_trip_cold_melt()
	_check_upstream_trip_melt_viscosity()
	_finish()


# ── rig ───────────────────────────────────────────────────────────────────────
func _build_rig(lid: String, placeable: String, x: float) -> Dictionary:
	var body := PlaceableCatalog.build_node(placeable, false)
	if body == null:
		_check(false, "catalog built %s" % placeable)
		return {}
	add_child(body)
	body.global_position = Vector3(x, 0.0, 0.0)
	var brain := body.get_node_or_null("SimBrain")
	if brain == null or brain.get("model") == null:
		_check(false, "%s carries a SimBrain with a model" % placeable)
		return {}
	# A bench rig has no pellet side, so its hidden "natraject" setting goes
	# OFF and the start button starts the screw alone, as before 2026-09-25
	# (operator rulings, rulings file §I7). The natraject itself is
	# test_extruder_start_interlock's.
	brain.get("model").start_seq.natraject_enabled = false
	var laser : Node3D = load("res://src/sim/LaserFilter.gd").new()
	add_child(laser)
	laser.global_position = Vector3(x + 6.0, 0.0, 0.0)
	var head : Node3D = load("res://src/sim/HeadFilter.gd").new()
	add_child(head)
	head.global_position = Vector3(x + 9.0, 0.0, 0.0)
	brain.call("_resolve_downstream_filters")
	_check(brain.get("_laser_filter") == laser and brain.get("_head_filter") == head,
		"%s: the brain resolved its OWN laserfilter and kopfilter" % lid)
	return {"lid": lid, "body": body, "brain": brain, "model": brain.get("model"),
		"laser": laser, "head": head}


## One 0.1 s step of one line: filters first (they integrate on physics), then
## the brain's SimTick handler (model tick, forwarding, trip checks).
func _step(rig: Dictionary) -> void:
	rig["laser"].call("_physics_process", DT)
	rig["head"].call("_physics_process", DT)
	rig["brain"].call("_on_sim_tick", DT)


func _start(rig: Dictionary) -> void:
	var pend = rig["brain"].get("_pending")
	pend["start_production"] = true


## A new extruder's rpm setpoint is 60 (operator 2026-09-25) and the operator
## raises it on the HMI. The nominal-run checks here are about a line AT
## nominal, so they raise it on the tick after the start, as a player would.
func _raise_to_nominal(rig: Dictionary) -> void:
	var m = rig["model"]
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)


# ── per-line configuration ────────────────────────────────────────────────────
func _check_per_line_config(lid: String, rig: Dictionary) -> void:
	var path := "res://src/data/machines/Extruder%s.tres" % lid
	_check(ResourceLoader.exists(path),
		"%s has its own config %s (operator 2026-09-24: die-side nominal per line)" % [lid, path])
	var cfg = rig["brain"].get("config_resource")
	_check(cfg != null and String(cfg.get("line_id")) == lid,
		"%s: MachineBrains handed the brain the %s config" % [lid, lid])


# ── nominal run ───────────────────────────────────────────────────────────────
func _run_nominal(lid: String, rig: Dictionary) -> void:
	print("  -- %s nominal: %.0f s at %.1f s, sampled from %.0f s --" % [lid, RUN_S, DT, SAMPLE_FROM_S])
	var model = rig["model"]
	var head = rig["head"]
	_start(rig)
	var n := int(RUN_S / DT)
	var lo := {"after": INF, "before": INF, "kop": INF, "pel": INF}
	var hi := {"after": -INF, "before": -INF, "kop": -INF, "pel": -INF}
	var tripped_at := -1.0
	for i in range(n):
		_step(rig)
		if i == 0:
			_raise_to_nominal(rig)
		var t := (i + 1) * DT
		if tripped_at < 0.0 and model.state == ExtruderModel.State.EMERGENCY_STOP:
			tripped_at = t
		if t < SAMPLE_FROM_S:
			continue
		var vals := {
			"after": _num(model, "mp_after_laserfilter_bar"),
			"before": _num(model, "mp_before_laserfilter_bar"),
			"kop": _num(model, "kopdruk_bar"),
			"pel": _num(model, "mp_pel_bar"),
		}
		for k in vals.keys():
			var v : float = vals[k]
			if is_nan(v):
				lo[k] = NAN
				hi[k] = NAN
			elif not is_nan(lo[k]):
				lo[k] = minf(lo[k], v)
				hi[k] = maxf(hi[k], v)

	_info("%s state %s, %.0f rpm, %.0f kg/h, torque %.0f %%, legacy die_pressure_psi=%s" % [
		lid, model.get_state_name(), model.screw_rpm, model.throughput_kg_h,
		model.motor_torque_pct, str(_num(model, "die_pressure_psi"))])
	_info("%s MP>MF %.1f..%.1f  MP<MF %.1f..%.1f  kopdruk %.1f..%.1f  MP<PEL %.1f..%.1f bar" % [
		lid, lo["after"], hi["after"], lo["before"], hi["before"],
		lo["kop"], hi["kop"], lo["pel"], hi["pel"]])

	_check(model.state == ExtruderModel.State.RUNNING and tripped_at < 0.0,
		"%s runs %.0f s at nominal without an over-pressure trip (state %s)" % [lid, RUN_S, model.get_state_name()])
	_check(_in(lo["after"], MP_AFTER_DOC_BAR) and _in(hi["after"], MP_AFTER_DOC_BAR),
		"%s pressure AFTER the laserfilter %.1f..%.1f bar is inside the documented %.0f-%.0f bar"
		% [lid, lo["after"], hi["after"], MP_AFTER_DOC_BAR.x, MP_AFTER_DOC_BAR.y])
	_check(_in(lo["before"], MP_BEFORE_OK_BAR) and _in(hi["before"], MP_BEFORE_OK_BAR),
		"%s pressure BEFORE the laserfilter %.1f..%.1f bar is inside %.0f-%.0f bar (3B trend p50 .. operator's 280 safe max)"
		% [lid, lo["before"], hi["before"], MP_BEFORE_OK_BAR.x, MP_BEFORE_OK_BAR.y])
	var tb : Vector2 = MP_BEFORE_TREND[lid]
	if lid == "3A":
		_check(_in(lo["before"], tb) and _in(hi["before"], tb),
			"3A pressure BEFORE the laserfilter %.1f..%.1f bar is inside the 3A trend p5-p95 %.0f-%.0f bar"
			% [lo["before"], hi["before"], tb.x, tb.y])
	else:
		# Not gated, and said so: the 3B trend band comes from ONE 72-minute
		# session (trends_overview.md note ‡) at an output the sim does not run
		# (3B p50 799 kg/h vs nominal 950), and the laserfilter's dMP is one
		# calibration for both lines (hmi_reference.md sec 1, a 3A screen).
		_info("3B BEFORE-laserfilter vs its one-session trend p5-p95 %.0f-%.0f bar: %s (max %.1f)"
			% [tb.x, tb.y, "inside" if _in(hi["before"], tb) else "ABOVE", hi["before"]])
	var fb : Vector2 = KOPDRUK_FORM008[lid]
	_check(_in(lo["kop"], fb) and _in(hi["kop"], fb),
		"%s kopdruk %.1f..%.1f bar with a fresh kopfilter pack is inside FORM-008's %.0f-%.0f bar"
		% [lid, lo["kop"], hi["kop"], fb.x, fb.y])
	var kt : Vector2 = KOPDRUK_TREND[lid]
	_check(_in(lo["kop"], kt) and _in(hi["kop"], kt),
		"%s kopdruk is inside the %s trend p5-p95 %.0f-%.0f bar" % [lid, lid, kt.x, kt.y])
	_check(not is_nan(hi["pel"]) and hi["pel"] < 160.0,
		"%s MP<PEL (dP across the kopfilter) %.1f bar at nominal, under the 160-bar interlock" % [lid, hi["pel"]])

	# One shift of kopfilter loading at the HeadFilter's OWN rate, then re-read.
	var feed : float = float(head.get("feed_throughput_kg_h"))
	var shift_g : float = HeadFilter.LOADING_PER_KG_THROUGHPUT * feed * SHIFT_H
	var on = head.call("_online")
	on.loading_g = shift_g
	for _i in range(20):
		_step(rig)
	var kop_eos := _num(model, "kopdruk_bar")
	var pel_eos := _num(model, "mp_pel_bar")
	_info("%s after one shift of pack loading (%.0f g at %.0f kg/h): kopfilter dP %.1f bar"
		% [lid, shift_g, feed, pel_eos])
	_check(_in(kop_eos, fb),
		"%s kopdruk %.1f bar after an 8 h shift on one pack is still inside FORM-008's %.0f-%.0f bar"
		% [lid, kop_eos, fb.x, fb.y])
	_check(model.state == ExtruderModel.State.RUNNING,
		"%s still RUNNING after a shift on one kopfilter pack" % lid)
	on.loading_g = 0.0
	for _i in range(5):
		_step(rig)


# ── readouts ──────────────────────────────────────────────────────────────────
func _check_readouts(rig: Dictionary) -> void:
	print("  -- readouts (3A, running) --")
	var model = rig["model"]
	var laser = rig["laser"]
	var before := _num(model, "mp_before_laserfilter_bar")
	var after := _num(model, "mp_after_laserfilter_bar")
	var kop := _num(model, "kopdruk_bar")
	var lf_before := _call_num(laser, "mp_before_filter_bar")
	_check(not is_nan(lf_before) and absf(lf_before - before) < 0.5,
		"LaserFilter's own MP<MF %.1f bar (its trip input) matches the model's %.1f bar" % [lf_before, before])

	var bp = load("res://src/scenes/hud/scopes/ExtruderBluPortScope.gd").new()
	add_child(bp)
	bp.call("set_model", model)
	var r_melt : float = bp.call("_read_field", "melt_pressure", -1.0)
	var r_kop : float = bp.call("_read_field", "screen_changer", -1.0)
	var r_post : float = bp.call("_read_field", "post_filter", -1.0)
	_check(absf(r_melt - before) < 0.5,
		"BluPort 'smelt-druk' %.1f bar = the pressure before the laserfilter (%.1f)" % [r_melt, before])
	_check(absf(r_kop - kop) < 0.5,
		"BluPort 'zeefwisselaar' %.1f bar = kopdruk into the kopfilter (%.1f)" % [r_kop, kop])
	_check(absf(r_post - after) < 0.5,
		"BluPort 'na-filter' %.1f bar = the pressure after the laserfilter (%.1f)" % [r_post, after])
	bp.queue_free()

	var sc = load("res://src/scenes/hud/scopes/LaserFilterScope.gd").new()
	add_child(sc)
	sc.call("set_filter", laser)
	sc.call("_pull_telemetry")
	var inlet : float = float(sc.get("_cur_inlet_bar"))
	var dmp : float = float(sc.get("_cur_delta_bar"))
	_check(absf(inlet - lf_before) < 0.5,
		"LaserFilterScope MP < MF %.1f bar = the filter's own pressure before it" % inlet)
	_check(absf((inlet - dmp) - after) < 0.5,
		"LaserFilterScope MP > MF (inlet - dMP) %.1f bar = the pressure after it (%.1f)" % [inlet - dmp, after])
	sc.queue_free()


# ── 160-bar MP<PEL: dP across the kopfilter ───────────────────────────────────
func _check_pel_trip(rig: Dictionary) -> void:
	print("  -- 160-bar MP<PEL (dP across the kopfilter) --")
	var model = rig["model"]
	var head = rig["head"]
	var on = head.call("_online")
	var k : float = HeadFilter.DELTA_P_PER_LOADING_G
	var feed : float = float(head.get("feed_throughput_kg_h"))
	var h_to_trip : float = 160.0 * PSI_PER_BAR / k / (HeadFilter.LOADING_PER_KG_THROUGHPUT * maxf(feed, 1.0))
	_info("at %.0f kg/h an un-swapped kopfilter pack reaches 160 bar dP after %.0f h" % [feed, h_to_trip])

	# Negative control first: 155 bar dP. Kopdruk there is die-plate + 155, far
	# above 160 — a trip that read kopdruk instead of the dP would fire here.
	on.loading_g = 155.0 * PSI_PER_BAR / k
	for _i in range(5):
		_step(rig)
	_check(_in(_num(model, "mp_pel_bar"), Vector2(150.0, 160.0)),
		"MP<PEL reads the kopfilter dP: %.1f bar at a 155-bar pack" % _num(model, "mp_pel_bar"))
	_check(_num(model, "kopdruk_bar") > 160.0 and model.state == ExtruderModel.State.RUNNING,
		"155 bar dP: NO trip although kopdruk is %.1f bar (the trip reads the dP, not kopdruk)"
		% _num(model, "kopdruk_bar"))

	on.loading_g = 165.0 * PSI_PER_BAR / k
	var t := -1.0
	for i in range(30):
		_step(rig)
		if model.state == ExtruderModel.State.EMERGENCY_STOP:
			t = (i + 1) * DT
			break
	_check(t > 0.0, "165 bar dP across the kopfilter trips the line (after %.1f s)" % t)
	_check(String(model.fault_reason) == "pelletiser_meltdruk_160bar",
		"fault_reason '%s' names the 160-bar pelletiser interlock" % model.fault_reason)
	var rows : Array = EremaFaultRegistry.detect_active(model, rig["laser"])
	var nrs : Array = rows.map(func(r): return int(r["nr"]))
	_check(nrs.has(5516), "Storingstabel shows 5516 (MP<PEL te hoog) — rows %s" % str(nrs))


# ── 318 bar before the laserfilter: a caked screen ────────────────────────────
func _check_upstream_trip_caked_screen(rig: Dictionary) -> void:
	print("  -- 318 bar before the laserfilter: caked screen (3B, running) --")
	var model = rig["model"]
	var laser = rig["laser"]
	var after := _num(model, "mp_after_laserfilter_bar")
	# Front-face cake that puts dMP at `dp_bar`, no disc advance in between. The
	# clean-screen base is read from the LIVE feed on every call: the restart
	# below runs at 60 rpm (every start does, operator 2026-09-25), and a base
	# frozen at the nominal 950 kg/h left the cake ~73 bar short of the trip.
	var set_dp := func(dp_bar: float) -> void:
		var base_psi : float = float(laser.get("feed_throughput_kg_h")) * LaserFilter.CLEAN_BASE_PSI_PER_KG_H
		laser.set("front_loading_g", maxf(0.0, (dp_bar * PSI_PER_BAR - base_psi) / LaserFilter.CAKE_PSI_PER_G))
		laser.set("_rotation_timer", 0.0)

	# Negative control: dMP that leaves MP<MF 10 bar under the trip.
	set_dp.call(318.0 - after - 10.0)
	_step(rig)
	var below := _call_num(laser, "mp_before_filter_bar")
	_check(_in(below, Vector2(300.0, 318.0)) and not bool(laser.get("is_tripped"))
			and model.state == ExtruderModel.State.RUNNING,
		"MP<MF %.1f bar (after-filter %.1f + dMP) does NOT trip" % [below, after])

	set_dp.call(318.0 - after + 12.0)
	var t := -1.0
	for i in range(10):
		_step(rig)
		if model.state == ExtruderModel.State.EMERGENCY_STOP:
			t = (i + 1) * DT
			set_dp.call(0.0)
			break
		set_dp.call(318.0 - after + 12.0)
	_check(bool(laser.get("is_tripped")) and t > 0.0,
		"a caked screen pushing MP<MF past 318 bar trips the line (after %.1f s)" % t)
	_check(String(model.fault_reason) == "laserfilter_upstream_overpressure_318bar",
		"fault_reason '%s' names the 318-bar laserfilter trip" % model.fault_reason)
	var rows : Array = EremaFaultRegistry.detect_active(model, laser)
	var nrs : Array = rows.map(func(r): return int(r["nr"]))
	_check(nrs.has(5518), "Storingstabel shows 5518 (laserfilter 318 bar) — rows %s" % str(nrs))

	# The trip must be armed again after the operator resets the E-stop. The
	# filter's own latch used to clear only on a screen change, and it signals
	# on the edge — so the second over-pressure of a session never tripped.
	# (The screen was cleaned above: set_dp(0) right after the trip.)
	var pend = rig["brain"].get("_pending")
	pend["reset_after_estop"] = true
	for _i in range(10):
		_step(rig)
		if model.state != ExtruderModel.State.EMERGENCY_STOP:
			break
	_check(model.state == ExtruderModel.State.OFF and not bool(laser.get("is_tripped")),
		"E-stop reset: line OFF (%s), laserfilter trip re-armed (is_tripped %s)"
		% [model.get_state_name(), str(laser.get("is_tripped"))])
	_start(rig)
	for _i in range(int(20.0 / DT)):
		_step(rig)
	_check(model.state == ExtruderModel.State.RUNNING,
		"restarted onto a clean screen, 20 s later: %s, MP<MF %.1f bar" % [model.get_state_name(), _call_num(laser, "mp_before_filter_bar")])
	var after2 := _num(model, "mp_after_laserfilter_bar")
	var t2 := -1.0
	for i in range(10):
		set_dp.call(318.0 - after2 + 12.0)
		_step(rig)
		if model.state == ExtruderModel.State.EMERGENCY_STOP:
			t2 = (i + 1) * DT
			break
	_check(t2 > 0.0 and String(model.fault_reason) == "laserfilter_upstream_overpressure_318bar",
		"a SECOND caked screen in the same session trips again (after %.1f s, '%s')" % [t2, model.fault_reason])


# ── 318 bar before the laserfilter: the melt path (operator lever) ────────────
## Nothing injected into the filter: the operator drops all seven zone
## setpoints 20 C. Torque climbs to ~100 % (under the 110 % torque trip), cold
## lumps pass the screw and cake the screen's front face, dMP saturates, and
## the pressure before the filter crosses 318.
func _check_upstream_trip_cold_melt() -> void:
	print("  -- 318 bar before the laserfilter: cold zones (fresh 3B) --")
	var rig := _build_rig("3B", "extruder_3b", 3000.0)
	if rig.is_empty():
		return
	var model = rig["model"]
	_start(rig)
	for i in range(int(300.0 / DT)):
		_step(rig)
		if i == 0:
			_raise_to_nominal(rig)
	var sp : float = model.config.melt_temp_setpoint
	for z in range(ExtruderModel.ZONE_COUNT):
		model.set_zone_temp(z, sp - 20.0)
	var t := -1.0
	var peak := 0.0
	var torque_peak := 0.0
	for i in range(int(120.0 / DT)):
		_step(rig)
		peak = maxf(peak, _call_num(rig["laser"], "mp_before_filter_bar"))
		torque_peak = maxf(torque_peak, model.motor_torque_pct)
		if model.state == ExtruderModel.State.EMERGENCY_STOP:
			t = (i + 1) * DT
			break
	_info("zones -20 C: torque peak %.0f %%, MP<MF peak %.1f bar, fault '%s'"
		% [torque_peak, peak, model.fault_reason])
	_check(t > 0.0 and String(model.fault_reason) == "laserfilter_upstream_overpressure_318bar",
		"cold zones -> lumps -> caked screen -> 318-bar trip, %.1f s after the setpoints dropped" % t)
	_check(torque_peak < ExtruderModel.TORQUE_TRIP_PCT,
		"it is the PRESSURE trip, not the 110 %% torque trip, that stops it (torque peak %.0f %%)" % torque_peak)


# ── 318 bar before the laserfilter: a cold melt through the screen ────────────
## Operator 2026-09-25: when the melt runs colder, the laserfilter's own dMP
## rises too, not only the melt-set pressure after it. The 3A trend fit (#275)
## puts 6.83 bar/C on MP<MF, typed below rather than read from the model: a
## melt 9 C under setpoint (+61 bar on the 260-bar sawtooth top) must reach
## 318, and 5 C (+34) must not. The melt is HELD below setpoint, because the
## model's melt drifts back to setpoint while running and nothing in gameplay
## holds it colder yet. Torque stays under the lump threshold, so the trip
## comes through the screen and not through lumps. The gameplay negative
## controls are a start at the preheat-ready melt, the coldest melt the green
## button accepts, on a fresh model AND on a warm one (2026-09-25).
func _check_upstream_trip_melt_viscosity() -> void:
	print("  -- 318 bar before the laserfilter: a cold melt through the screen (fresh 3B) --")
	var fit_bar_per_c := 6.83   # 3A trend fit, #275
	var fit_level_bar := 280.0
	for c in [[5.0, false], [9.0, true]]:
		var cold : float = c[0]
		var rig := _build_rig("3B", "extruder_3b", 5000.0 + cold * 100.0)
		if rig.is_empty():
			return
		var model = rig["model"]
		var laser = rig["laser"]
		var sp : float = model.config.melt_temp_setpoint
		_start(rig)
		for i in range(int(300.0 / DT)):
			_step(rig)
			if i == 0:
				_raise_to_nominal(rig)
		var peak := 0.0
		var torque_peak := 0.0
		var lump_peak := 0.0
		var t := -1.0
		for i in range(int(60.0 / DT)):
			model.melt_temp = sp - cold
			_step(rig)
			peak = maxf(peak, _call_num(laser, "mp_before_filter_bar"))
			torque_peak = maxf(torque_peak, model.motor_torque_pct)
			lump_peak = maxf(lump_peak, model.lump_passthrough_rate_g_s)
			if model.state == ExtruderModel.State.EMERGENCY_STOP:
				t = (i + 1) * DT
				break
		var want_f : float = 1.0 + cold * fit_bar_per_c / fit_level_bar
		_check(absf(_num(laser, "melt_viscosity_factor") - want_f) < 0.01,
			"melt %.0f C cold: the laserfilter's dMP is scaled x%.3f (fit x%.3f)"
			% [cold, _num(laser, "melt_viscosity_factor"), want_f])
		if bool(c[1]):
			_check(t > 0.0 and String(model.fault_reason) == "laserfilter_upstream_overpressure_318bar",
				"melt %.0f C cold -> the screen's dMP climbs -> 318-bar trip after %.1f s ('%s')"
				% [cold, t, model.fault_reason])
			_check(lump_peak == 0.0 and torque_peak < ExtruderModel.LUMP_PASSTHROUGH_TORQUE_PCT,
				"...through the screen, not lumps: torque peak %.0f %% (lump threshold %.0f %%), lumps %.1f g/s"
				% [torque_peak, ExtruderModel.LUMP_PASSTHROUGH_TORQUE_PCT, lump_peak])
		else:
			_check(t < 0.0 and model.state == ExtruderModel.State.RUNNING and peak < LaserFilter.UPSTREAM_TRIP_BAR,
				"melt %.0f C cold for 60 s: MP<MF peak %.1f bar, no trip (%s)" % [cold, peak, model.get_state_name()])

	var rs := _build_rig("3B", "extruder_3b", 6500.0)
	if rs.is_empty():
		return
	var ms = rs["model"]
	var ready_c : float = float(ms.call("_preheat_ready_temp"))
	ms.melt_temp = ready_c
	_start(rs)
	_step(rs)                  # a cold barrel goes to PREHEAT first
	ms.melt_temp = ready_c
	_start(rs)                 # the green button, at the coldest melt it accepts
	_step(rs)
	var started : bool = ms.state == ExtruderModel.State.STARTING
	var speak := 0.0
	for _i in range(int(400.0 / DT)):
		_step(rs)
		speak = maxf(speak, _call_num(rs["laser"], "mp_before_filter_bar"))
		if ms.state == ExtruderModel.State.EMERGENCY_STOP:
			break
	_check(started and ms.state == ExtruderModel.State.RUNNING and not bool(rs["laser"].get("is_tripped"))
			and speak < LaserFilter.UPSTREAM_TRIP_BAR,
		"a start at the preheat-ready melt (%.2f C, %.2f C cold) runs up without a trip: MP<MF peak %.1f bar"
		% [ready_c, ms.config.melt_temp_setpoint - ready_c, speak])

	# The same start on a WARM model: one that ran at nominal before and was
	# stopped. The check above only ever started FRESH models, and a fresh model
	# used to re-ramp from idle in RUNNING (a lifetime-runtime ramp) while a warm
	# one went straight to nominal flow — measured 2026-09-25: MP<MF 317.6 bar
	# and a 318 trip 4.3 s after the green button (probe_warm_restart_pressure).
	# Now a start ramps to the setpoint the operator left, and on a barrel that is
	# only just warm the operator puts it at 60 first (operator rulings
	# 2026-09-25; test_extruder_start_rpm has the rest, including the same
	# restart left at 110, which trips).
	var rw := _build_rig("3B", "extruder_3b", 7000.0)
	if rw.is_empty():
		return
	var mw = rw["model"]
	_start(rw)
	for i in range(int(300.0 / DT)):
		_step(rw)
		if i == 0:
			_raise_to_nominal(rw)
	var warm_rt : float = mw.runtime_s
	rw["brain"].get("_pending")["stop_production"] = true
	for _i in range(int(60.0 / DT)):
		_step(rw)
		if mw.state == ExtruderModel.State.OFF:
			break
	var ready_w : float = float(mw.call("_preheat_ready_temp"))
	mw.set_screw_rpm_setpoint(60.0)   # the operator's 60 on a just-warm barrel (typed: a config read blesses any value)
	mw.melt_temp = ready_w
	_start(rw)
	_step(rw)                  # OFF cools 0.05 C first: PREHEAT
	mw.melt_temp = ready_w
	_start(rw)                 # the green button
	_step(rw)
	var wstarted : bool = mw.state == ExtruderModel.State.STARTING
	var wpeak := 0.0
	for _i in range(int(400.0 / DT)):
		_step(rw)
		wpeak = maxf(wpeak, _call_num(rw["laser"], "mp_before_filter_bar"))
		if mw.state == ExtruderModel.State.EMERGENCY_STOP:
			break
	_check(warm_rt > 180.0 and wstarted and mw.state == ExtruderModel.State.RUNNING
			and not bool(rw["laser"].get("is_tripped")) and wpeak < LaserFilter.UPSTREAM_TRIP_BAR,
		"a WARM restart (ran %.0f s at nominal, stopped, set back to %.0f rpm) at the preheat-ready melt %.2f C runs up without a trip: MP<MF peak %.1f bar"
		% [warm_rt, mw.screw_rpm_setpoint, ready_w, wpeak])


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
