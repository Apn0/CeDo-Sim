extends Node
## DIE PRESSURE IS BAR (2026-09-24, C1) — the extruder's melt pressures read the
## plant's bar, follow melt temperature, and every consumer agrees on them.
##
##   godot --headless --path . res://src/tests/test_die_pressure_bar.tscn
##
## Before: ExtruderModel.DIE_PRESSURE_BASE_PSI was 280.0 PSI, so a nominal run
## showed 280 / 14.504 = 19.3 bar on the BluPort chart, against SWI-054 p1's
## "280 / 300 bar", the 3C BluPort screen's 280-287 bar and the 3A WinCC trend
## "Smeltdruk voor meltfilter" p50 271 / p95 280 bar. Operator ruling
## 2026-09-24: 280 is bar, pre-meltfilter. Fixing the unit exposed consumers
## that only worked because the number was 14.5x too small:
##   * the laser filter's inlet was fed the KOPFILTER's ΔP — a filter
##     downstream of it, and on 3A/3B the nearest one belongs to line 3C;
##   * the pressure rode the TORQUE proxy, which carries the zone-setpoint
##     shortfall — at bar scale one zone 30 °C down (the paper practice) read
##     320 bar and tripped the line. Operator ruling 2026-09-24: pressure
##     follows melt temperature (ExtruderModel.DIE_PRESSURE_BAR_PER_C, the 3A
##     trend fit), so a zone drop raises torque but not the gauge.
##
## MERGED 2026-09-24 with #278 (the same finding, fixed in parallel). The
## operator's rulings of that evening (docs/plant/operator_rulings_2026-09-24.md)
## make it TWO pressures: before the laserfilter = the melt-set pressure after it
## (25 bar nominal) + the screen's own dMP, and MP<PEL, the 160-bar interlock,
## is the dP ACROSS the kopfilter, not a 140-bar copy of the pre-filter pressure.
## This suite's checks that asserted the single-pressure model (a bare model
## reading 280 bar, MP<PEL 120-150 bar, a 12 °C cold melt crossing 318 on a
## model with no screen) are rewritten against that; the reachability of both
## trips is test_extruder_melt_pressures' job (caked screen, cold zones, a cold
## melt through the screen, a loaded pack). The melt-temperature sensitivity
## stays: the melt-set pressures scale by DIE_PRESSURE_BAR_PER_C as a fraction
## of MELT_FIT_LEVEL_BAR (2.44 %/°C), and so does the laserfilter's dMP
## (operator 2026-09-25: "dMP rises too").
##
## Mutation-proven after the merge (2026-09-24): torque proxy restored -> A7c
## red (3.23 %/°C); laser filter fed the kopfilter's ΔP -> B1/B2 red. C2 alone
## does not catch the torque proxy: in the two-pressure model torque only
## scales the 25-bar melt-set part, so neither factor lets one zone reach 318.
## (The single-pressure version's four mutations: this file at 1588462.)

const WATCHDOG_S := 180.0
const TREND_JSON := "res://src/data/plant/trends/extruder_trends_summary.json"
const PSI_PER_BAR := 14.5038
const DT := 0.1

var _fails := 0
var _oks := 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

## p50/p95 of a WinCC trend signal, read from the data file rather than typed.
func _trend(line: String, sig_name: String) -> Dictionary:
	var f := FileAccess.open(TREND_JSON, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	for s in d.get("signals", []):
		if String(s.get("line", "")) == line and String(s.get("signal", "")) == sig_name:
			return s.get("stats", {})
	return {}

func _run_to_nominal(m: ExtruderModel) -> void:
	m.melt_temp = m.config.melt_temp_setpoint
	m.tick(0.1, {"start_production": true})
	# A new extruder's rpm setpoint is 60 (operator 2026-09-25) and the operator
	# raises it on the HMI; this suite is about a line AT nominal.
	m.set_screw_rpm_setpoint(m.config.screw_rpm_nominal)
	for _i in range(3000):   # 300 s — steady long before that
		m.tick(0.1, {})

func _has_nr(rows: Array, nr: int) -> bool:
	for r in rows:
		if typeof(r) == TYPE_DICTIONARY and int(r.get("nr", -1)) == nr:
			return true
	return false

func _run() -> void:
	print("[TEST] die pressure is bar")
	var cfg := load("res://src/data/machines/Extruder3B.tres") as ExtruderConfig
	_check(cfg != null, "Extruder3B.tres loads")
	if cfg == null:
		_finish(); return

	# ── A. the model (no filters attached: both filter dPs are 0) ─────────────
	_check(is_equal_approx(ExtruderModel.DIE_PRESSURE_BAR_PER_C, 6.83)
			and is_equal_approx(ExtruderModel.MELT_FIT_LEVEL_BAR, 280.0),
		"A0 melt sensitivity is the 3A trend fit, 6.83 bar/°C at the operator's 280 bar")
	var m := ExtruderModel.new(cfg.duplicate())
	_run_to_nominal(m)
	_check(m.state == ExtruderModel.State.RUNNING, "nominal run reached RUNNING (state %s)" % m.get_state_name())
	_check(absf(m.mp_after_laserfilter_bar - cfg.mp_after_laserfilter_nominal_bar) < 1.0,
		"A1 a nominal run reads %.1f bar after the laserfilter (the 3A screen's MP>MF %.0f bar; the psi base read 19.3 bar TOTAL)"
			% [m.mp_after_laserfilter_bar, cfg.mp_after_laserfilter_nominal_bar])
	var win : Vector2 = cfg.kopdruk_window_bar
	_check(m.kopdruk_bar >= win.x and m.kopdruk_bar <= win.y,
		"A2 kopdruk %.1f bar sits in 3B's FORM-008 window %.0f-%.0f bar" % [m.kopdruk_bar, win.x, win.y])
	var tk := _trend("3b", "Smeltdruk voor kopfilter")
	_check(not tk.is_empty(), "3B trend 'Smeltdruk voor kopfilter' found in %s" % TREND_JSON)
	if not tk.is_empty():
		_check(absf(m.kopdruk_bar - float(tk["p50"])) <= 15.0,
			"A3 kopdruk %.1f bar within 15 bar of the 3B kopfilter trend p50 %.0f bar" % [m.kopdruk_bar, float(tk["p50"])])
	var rows := EremaFaultRegistry.detect_active(m, null)
	_check(m.mp_pel_bar < 1.0 and not _has_nr(rows, int(EremaFaultRegistry.F_PEL_MELT_PRESSURE_HI["nr"])),
		"A6 a nominal run raises NO 160-bar MP<PEL row: MP<PEL is the kopfilter's dP (%.1f bar, no pack)" % m.mp_pel_bar)
	# Sensitivity: one °C of cold melt scales the melt-set pressures by
	# DIE_PRESSURE_BAR_PER_C / MELT_FIT_LEVEL_BAR (2.44 %). The torque proxy
	# this replaced moved them 3.2 %/°C (9.05 bar/°C at 280, #275's mutation).
	var after0 : float = m.mp_after_laserfilter_bar
	var plate0 : float = m.die_plate_bar
	m.melt_temp = cfg.melt_temp_setpoint - 1.0
	m.tick(0.1, {})
	var frac : float = (m.mp_after_laserfilter_bar - after0) / maxf(after0, 0.001)
	var want : float = ExtruderModel.DIE_PRESSURE_BAR_PER_C / ExtruderModel.MELT_FIT_LEVEL_BAR
	_check(absf(frac - want) < 0.003,
		"A7c 1 °C of cold melt raises the melt-set pressures %.2f %% (fit %.2f %%): MP>MF +%.2f bar, die plate +%.2f bar"
			% [frac * 100.0, want * 100.0, m.mp_after_laserfilter_bar - after0, m.die_plate_bar - plate0])
	_check(absf(m.melt_viscosity_factor - (1.0 + want)) < 0.003,
		"A7d the model exposes that factor for the laserfilter (x%.4f at 1 °C cold): the screen's dMP scales too, so MP<MF moves at the fit's %.2f bar/°C (test_extruder_melt_pressures measures it end to end)"
			% [m.melt_viscosity_factor, ExtruderModel.DIE_PRESSURE_BAR_PER_C])

	# ── B. the wired brain feeds the laser filter's inlet ────────────────────
	var root := Node3D.new()
	add_child(root)
	var ex := PlaceableCatalog.build_node("extruder_3b", false) as Node3D
	var lf := PlaceableCatalog.build_node("laser_filter", false) as Node3D
	var kf := PlaceableCatalog.build_node("kopfilter", false) as Node3D
	_check(ex != null and lf != null and kf != null, "catalog built extruder_3b + laser_filter + kopfilter")
	if ex == null or lf == null or kf == null:
		_finish(); return
	root.add_child(ex)
	root.add_child(lf)
	root.add_child(kf)
	ex.global_position = Vector3.ZERO
	lf.global_position = Vector3(3.5, 0.0, -5.0)
	kf.global_position = Vector3(0.0, 0.0, -9.0)
	for _i in range(3):
		await get_tree().process_frame
	var brain := ex.get_node_or_null("SimBrain")
	_check(brain != null and brain.get("model") != null, "the extruder carries a live SimBrain")
	if brain == null:
		_finish(); return
	var bm : ExtruderModel = brain.get("model")
	# A bench rig has no pellet side, so its hidden "natraject" setting goes
	# OFF and the start button starts the screw alone, as before 2026-09-25
	# (operator rulings, rulings file §I7). The natraject itself is
	# test_extruder_start_interlock's.
	bm.start_seq.natraject_enabled = false
	bm.melt_temp = bm.config.melt_temp_setpoint
	# A loaded kopfilter: 300 psi of ΔP on its online cavity. The old wiring
	# forwarded exactly this number as the laser filter's inlet pressure.
	var kop_cav = kf.get("cavities")[kf.get("_active_idx")]
	brain.get("_pending")["start_production"] = true
	for _i in range(3000):
		kop_cav.loading_g = 300.0 / 0.22
		kop_cav.delta_p_psi = 300.0
		brain.call("_on_sim_tick", 0.1)
		if _i == 0:
			bm.set_screw_rpm_setpoint(bm.config.screw_rpm_nominal)   # the player raises it
	_check(bm.state == ExtruderModel.State.RUNNING, "brain model RUNNING (state %s)" % bm.get_state_name())
	var kop_bar : float = 300.0 / PSI_PER_BAR
	var inlet_bar : float = float(lf.get("mp_after_filter_bar"))
	_check(absf(inlet_bar - bm.mp_after_laserfilter_bar) < 0.01 and absf(inlet_bar - kop_bar) > 1.0,
		"B1 laser filter is fed the model's melt-set pressure (%.2f bar vs model %.2f; kopfilter ΔP %.1f bar must NOT be used)"
			% [inlet_bar, bm.mp_after_laserfilter_bar, kop_bar])
	var screen_bar : float = float(lf.call("mp_before_filter_bar"))
	_check(absf(screen_bar - bm.mp_before_laserfilter_bar) < 0.5
			and absf(screen_bar - (inlet_bar + float(lf.get("delta_p_psi")) * LaserFilterScope.PSI_TO_BAR)) < 0.01,
		"B2 the LaserFilter screen's MP<MF (%.1f bar) = MP>MF + its own dMP, and the model agrees (%.1f bar)"
			% [screen_bar, bm.mp_before_laserfilter_bar])
	_check(absf(bm.mp_pel_bar - kop_bar) < 0.5,
		"B2b MP<PEL reads the kopfilter's own ΔP (%.1f bar vs pack %.1f bar)" % [bm.mp_pel_bar, kop_bar])
	for _i in range(60):
		await get_tree().physics_frame
		brain.call("_on_sim_tick", 0.1)
	_check(not bool(lf.get("is_tripped")), "B3 a nominal run does not latch the 318-bar upstream trip")
	_check(not bool(brain.get("_pel_trip_latched")), "B4 a nominal run does not latch the 160-bar MP<PEL interlock")
	_check(bm.state == ExtruderModel.State.RUNNING, "B5 still RUNNING after 60 physics frames (state %s)" % bm.get_state_name())

	# ── C. one zone 30 °C down on the wired rig trips nothing ─────────────────
	# Operator ruling 2026-09-24 (#275): lowering a zone setpoint raises torque,
	# but pressure follows the MELT — one zone 30 °C down (the paper practice)
	# must not trip the line. It read 320 bar on the torque proxy. On the rig the
	# other way to 318 is through the laserfilter (torque over the lump
	# threshold → lumps → a caked screen), so the filters are stepped too.
	var torque0 : float = bm.motor_torque_pct
	bm.set_zone_temp(0, bm.get_zone_temp(0) - 30.0)
	var tpk := 0.0
	var ppk := 0.0
	for _i in range(int(600.0 / DT)):
		lf.call("_physics_process", DT)
		kf.call("_physics_process", DT)
		brain.call("_on_sim_tick", DT)
		tpk = maxf(tpk, bm.motor_torque_pct)
		ppk = maxf(ppk, float(lf.call("mp_before_filter_bar")))
		if bm.state != ExtruderModel.State.RUNNING:
			break
	_check(tpk > torque0 + 1.0,
		"C1 a one-zone 30 °C drop still raises torque (%.1f %% -> peak %.1f %%)" % [torque0, tpk])
	_check(bm.state == ExtruderModel.State.RUNNING and not bool(lf.get("is_tripped"))
			and not bool(brain.get("_pel_trip_latched")) and ppk < LaserFilter.UPSTREAM_TRIP_BAR,
		"C2 ...but trips nothing over 600 s: MP<MF peak %.1f bar, state %s, fault '%s'"
			% [ppk, bm.get_state_name(), bm.fault_reason])
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] die pressure is bar %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
