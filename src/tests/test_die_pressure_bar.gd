extends Node
## DIE PRESSURE IS BAR (2026-09-24, C1) — the extruder's melt pressure before the
## meltfilter reads the plant's 280 BAR, and every consumer agrees on it.
##
##   godot --headless --path . res://src/tests/test_die_pressure_bar.tscn
##
## Before: ExtruderModel.DIE_PRESSURE_BASE_PSI was 280.0 PSI, so a nominal run
## showed 280 / 14.504 = 19.3 bar on the BluPort chart, against SWI-054 p1's
## "280 / 300 bar", the 3C BluPort screen's 280-287 bar and the 3A WinCC trend
## "Smeltdruk voor meltfilter" p50 271 / p95 280 bar. Operator ruling
## 2026-09-24: 280 is bar, pre-meltfilter. Fixing the unit exposed three
## consumers that only worked because the number was 14.5x too small:
##   * the 160-bar MP<PEL interlock read the PRE-meltfilter pressure — at 280 bar
##     it would trip on every nominal run. It now reads ExtruderModel.mp_pel_bar
##     (nominal 140 bar: FORM-008 kopdruk 120-150 bar, trend p50 140/143 bar);
##   * the laser filter's inlet (MP<MF) was fed the KOPFILTER's ΔP — a filter
##     downstream of it, and on 3A/3B the nearest one belongs to line 3C;
##   * LaserFilter's front-face amplification anchors were psi tuned against
##     the 280-psi signal; they are now the same numbers in bar;
##   * the pressure rode the TORQUE proxy, which carries the zone-setpoint
##     shortfall — at bar scale one zone 30 °C down (the paper practice) read
##     320 bar and tripped the line. Operator ruling 2026-09-24: pressure
##     follows melt temperature (ExtruderModel.DIE_PRESSURE_BAR_PER_C, the 3A
##     trend fit), so a zone drop raises torque but not the gauge.
##
## Mutation-proven four ways (2026-09-24): psi base restored -> 7 red (19.3 bar);
## head-filter preference restored -> B1/B2 red (inlet 300 psi = kopfilter ΔP);
## interlock + row reading the pre-meltfilter pressure -> 5 red (E-STOP on a
## nominal run); torque proxy restored -> A7b/A7c red (320 bar, 9.05 bar/°C).

const WATCHDOG_S := 120.0
const TREND_JSON := "res://src/data/plant/trends/extruder_trends_summary.json"
const PSI_PER_BAR := 14.5038

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
	for _i in range(3000):   # 300 s — the probe measured nominal by 240 s
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

	# ── A. the model ──────────────────────────────────────────────────────────
	_check(is_equal_approx(ExtruderModel.DIE_PRESSURE_BASE_BAR, 280.0),
		"nominal pre-meltfilter pressure is the operator's 280 BAR (%.1f)" % ExtruderModel.DIE_PRESSURE_BASE_BAR)
	var m := ExtruderModel.new(cfg.duplicate())
	_run_to_nominal(m)
	_check(m.state == ExtruderModel.State.RUNNING, "nominal run reached RUNNING (state %s)" % m.get_state_name())
	var bar : float = m.die_pressure_psi / PSI_PER_BAR
	_check(absf(bar - 280.0) < 1.0,
		"A1 a nominal run reads %.1f bar before the meltfilter (was 19.3 with the psi base)" % bar)
	var tr := _trend("3a", "Smeltdruk voor meltfilter")
	_check(not tr.is_empty(), "3A trend 'Smeltdruk voor meltfilter' found in %s" % TREND_JSON)
	if not tr.is_empty():
		var lo : float = float(tr["p50"]) * 0.95
		var hi : float = float(tr["p95"]) * 1.05
		_check(bar >= lo and bar <= hi,
			"A2 nominal %.1f bar sits in the 3A trend band [p50x0.95 %.0f, p95x1.05 %.0f]" % [bar, lo, hi])
	_check(m.mp_pel_bar >= 120.0 and m.mp_pel_bar <= 150.0,
		"A3 MP<PEL %.1f bar sits in FORM-008's kopdruk band 120-150 bar" % m.mp_pel_bar)
	var tk := _trend("3a", "Druk voor kopfilter")
	if not tk.is_empty():
		_check(absf(m.mp_pel_bar - float(tk["p50"])) <= 15.0,
			"A4 MP<PEL %.1f bar within 15 bar of the 3A kopfilter trend p50 %.0f bar" % [m.mp_pel_bar, float(tk["p50"])])
	_check(bar < LaserFilter.UPSTREAM_TRIP_BAR and bar < EremaFaultRegistry.MPF1_PRESSURE_TRIP_BAR,
		"A5 nominal is below the 318-bar upstream trip and the 6557 row (335 bar)")
	var rows := EremaFaultRegistry.detect_active(m, null)
	_check(not _has_nr(rows, int(EremaFaultRegistry.F_PEL_MELT_PRESSURE_HI["nr"])),
		"A6 a nominal run raises NO 160-bar MP<PEL row (MP<PEL %.1f bar)" % m.mp_pel_bar)
	# Zone drop (operator ruling 2026-09-24): lowering a zone setpoint raises
	# torque, but pressure follows the MELT — one zone 30 °C down (the paper
	# practice) must not trip the line. It read 320 bar on the torque proxy.
	var zm := ExtruderModel.new(cfg.duplicate())
	_run_to_nominal(zm)
	zm.set_zone_temp(0, zm.get_zone_temp(0) - 30.0)
	for _i in range(600):
		zm.tick(0.1, {})
	var zbar : float = zm.die_pressure_psi / PSI_PER_BAR
	_check(zm.motor_torque_pct > cfg.motor_torque_base_pct + 1.0,
		"A7a a one-zone 30 °C drop still raises torque (%.1f %%)" % zm.motor_torque_pct)
	_check(zbar < LaserFilter.UPSTREAM_TRIP_BAR and zm.mp_pel_bar < EremaFaultRegistry.PEL_MELT_PRESSURE_TRIP_BAR,
		"A7b ...but does not trip: %.0f bar pre-meltfilter, %.0f bar MP<PEL" % [zbar, zm.mp_pel_bar])
	# Sensitivity: one °C of cold melt adds DIE_PRESSURE_BAR_PER_C (the 3A fit).
	m.melt_temp = cfg.melt_temp_setpoint - 1.0
	m.tick(0.1, {})
	var d1 : float = m.die_pressure_psi / PSI_PER_BAR - bar
	_check(absf(d1 - ExtruderModel.DIE_PRESSURE_BAR_PER_C) < 0.5,
		"A7c 1 °C of cold melt adds %.2f bar (3A trend fit %.2f bar/°C)" % [d1, ExtruderModel.DIE_PRESSURE_BAR_PER_C])
	# Reachability: a 12 °C cold melt — the documented trips must be reachable,
	# not dead code behind a tiny number.
	m.melt_temp = cfg.melt_temp_setpoint - 12.0
	m.tick(0.1, {})
	var cold_bar : float = m.die_pressure_psi / PSI_PER_BAR
	rows = EremaFaultRegistry.detect_active(m, null)
	_check(cold_bar > LaserFilter.UPSTREAM_TRIP_BAR,
		"A7d a 12 °C cold melt pushes pre-meltfilter pressure over the 318-bar trip (%.0f bar)" % cold_bar)
	_check(_has_nr(rows, int(EremaFaultRegistry.F_PEL_MELT_PRESSURE_HI["nr"])),
		"A8 ...and MP<PEL over 160 bar raises the 5516 row (%.0f bar)" % m.mp_pel_bar)

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
	bm.melt_temp = bm.config.melt_temp_setpoint
	# A loaded kopfilter: 300 psi of ΔP on its online cavity. The old wiring
	# forwarded exactly this number as the laser filter's inlet pressure.
	var kop_cav = kf.get("cavities")[kf.get("_active_idx")]
	brain.get("_pending")["start_production"] = true
	for _i in range(3000):
		kop_cav.loading_g = 300.0 / 0.22
		kop_cav.delta_p_psi = 300.0
		brain.call("_on_sim_tick", 0.1)
	_check(bm.state == ExtruderModel.State.RUNNING, "brain model RUNNING (state %s)" % bm.get_state_name())
	var inlet_psi : float = float(lf.get("upstream_pressure_psi_indicator"))
	_check(absf(inlet_psi - bm.die_pressure_psi) < 0.01,
		"B1 laser filter inlet = the model's pre-meltfilter pressure (%.0f psi vs model %.0f; kopfilter ΔP 300 psi must NOT be used)" % [inlet_psi, bm.die_pressure_psi])
	var inlet_bar : float = inlet_psi * LaserFilterScope.PSI_TO_BAR
	_check(inlet_bar > 250.0 and inlet_bar < 300.0,
		"B2 the LaserFilter screen's inlet reading is %.0f bar" % inlet_bar)
	for _i in range(60):
		await get_tree().physics_frame
		brain.call("_on_sim_tick", 0.1)
	_check(not bool(lf.get("is_tripped")), "B3 a nominal run does not latch the 318-bar upstream trip")
	_check(not bool(brain.get("_pel_trip_latched")), "B4 a nominal run does not latch the 160-bar MP<PEL interlock")
	_check(bm.state == ExtruderModel.State.RUNNING, "B5 still RUNNING after 60 physics frames (state %s)" % bm.get_state_name())
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] die pressure is bar %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
