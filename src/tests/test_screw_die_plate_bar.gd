extends Node
## DIE-PLATE PRESSURE ON LINEFLOW'S SCREW (2026-09-24) — the Quality terminal's
## pressure row, and the MFI estimate built on it, read the plant's numbers.
##
##   godot --headless --path . res://src/tests/test_screw_die_plate_bar.tscn
##
## Before: LineFlow's ExtruderScrew (a model separate from ExtruderModel)
## computed die_pressure = 6.5e-4 · eta · flow and labelled it bar. Measured on
## all four macro lines at 950 kg/h: 0.1056 bar, on a screw turning a flat
## 200 rpm with the melt held at 195 °C. The plant runs 95–110 rpm with the melt
## at 246–257 °C before the meltfilter, and its die-side pressures sit around
## 120–155 bar. MfiProxy's output is ABSOLUTE (MFI_GAIN · Q / (P · η)), so the
## 0.1-bar input put the MFI at 1491 g/10min, and QaSpec REJECTed every sample.
## On lines 1, 3A and 3B the terminal and the SCADA panel did not even read the
## extruder. `_is_extruder()` matched the id prefix, so the extruder_silo got a
## screw model too, and it comes first in _nodes.
##
## Operator rulings 2026-09-24 (AskUserQuestion, this change):
##   * the pressure is the DIE PLATE, after the kopfilter. No gauge reads it, so
##     it is derived: the bottom of FORM-008's kopdruk window per line;
##   * rpm and melt temperature go to the trend bands, and the pressure is
##     calibrated at that point;
##   * the silo stops carrying a screw model.
##
## Checks. A: the profile table and the MFI anchor agree with the data files
## (the trend numbers are read from the JSON, not typed). B: a real LineFlow
## over the four macro-built lines, fed at each line's trend p50 output for
## 300 s. It checks rpm, melt, die plate and MFI against documented bands, and
## that the terminal and SCADA read the extruder. Anti-vacuity: the fed
## extruders must actually carry the fed rate, and the silos must exist.
##
## Measured, NOT gated (printed as info): the plant's kopdruk does not follow
## output (trend fit exponent -0.13 on 3A, 0.007 on 3B, R² ≤ 0.04), while this
## model's die plate is proportional to it. That is an open model-form question.
## docs/audit/extruder_screw_die_plate_2026-09-24.md.

## Measured 68 s idle and 156 s beside another session's suites (2026-09-25);
## run.sh's own per-suite timeout is 900 s.
const WATCHDOG_S := 600.0
const TREND_JSON := "res://src/data/plant/trends/extruder_trends_summary.json"
const ExtruderScrewScript := preload("res://src/sim/ExtruderScrew.gd")
const MfiProxyScript := preload("res://src/sim/MfiProxy.gd")
const QaSpecScript := preload("res://src/sim/QaSpec.gd")
const TerminalScript := preload("res://src/scenes/hud/QualityAnalysisTerminal.gd")

## FORM-008 rows 25/26, "Kopdruk kopfilter 3a/3b extruder" (docs/plant/
## checklist_3a_3b.md). Not in any data file, so typed here with its row.
const FORM008_KOPDRUK := {"3a": [120.0, 150.0], "3b": [140.0, 155.0]}
## The kopdruk trend signal is named differently on the two archives.
const KOPDRUK_SIGNAL := {"3a": "Druk voor kopfilter", "3b": "Smeltdruk voor kopfilter"}
const SETTLE_S := 300.0
## One LineFlow over four lines, 400 m apart so no nearest-port fallback can
## bridge two of them, the way a world holds several lines at once.
const LINES := [["line_1", Vector3(0, 0, 0)], ["line_3a", Vector3(0, 0, 400)],
	["line_3b", Vector3(0, 0, 800)], ["line_3c", Vector3(0, 0, 1200)]]
## The extruders the four macros place. Gated: 3a / 3b (own profiles).
const EXTRUDER_LINE := {"extruder_1": "", "extruder_3a": "3a", "extruder_3b": "3b",
	"extruder_screw": ""}

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
	print("Result: FAIL (%d ok, %d fail — watchdog: verdict never completed; see SCRIPT ERROR above)" % [_oks, _fails + 1])
	get_tree().quit(2)

## A trend signal's record (stats + operating_band), read from the data file.
func _trend(line: String, sig_name: String) -> Dictionary:
	var f := FileAccess.open(TREND_JSON, FileAccess.READ)
	if f == null:
		return {}
	var d = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return {}
	for s in d.get("signals", []):
		if String(s.get("line", "")) == line and String(s.get("signal", "")) == sig_name:
			return s
	return {}

func _p50(line: String, sig_name: String) -> float:
	var s := _trend(line, sig_name)
	return float(s["stats"]["p50"]) if not s.is_empty() else NAN

func _run() -> void:
	print("[TEST] LineFlow screw — die plate in bar, rpm + melt from the trends")

	# ── A. the numbers in code agree with the data files ─────────────────────
	for line in ["3a", "3b"]:
		var prof : Dictionary = ExtruderScrewScript.PROFILES[line.to_upper()]
		var rpm := _trend(line, "Snelheid hoofdmotor")
		var outp := _trend(line, "Output")
		var melt := _trend(line, "Smelt temperatuur voor meltfilter")
		_check(not rpm.is_empty() and not outp.is_empty() and not melt.is_empty(),
			"A0 %s trend signals found in %s" % [line, TREND_JSON])
		if rpm.is_empty() or outp.is_empty() or melt.is_empty():
			continue
		_check(is_equal_approx(float(prof["rpm_nominal"]), float(rpm["stats"]["p50"])),
			"A1 %s rpm_nominal %.0f == 'Snelheid hoofdmotor' p50 %.0f" % [line, prof["rpm_nominal"], rpm["stats"]["p50"]])
		_check(is_equal_approx(float(prof["kg_h_nominal"]), float(outp["stats"]["p50"])),
			"A2 %s kg_h_nominal %.0f == 'Output' p50 %.0f" % [line, prof["kg_h_nominal"], outp["stats"]["p50"]])
		_check(is_equal_approx(float(prof["melt_lo"]), float(melt["operating_band"]["low"]))
			and is_equal_approx(float(prof["melt_hi"]), float(melt["operating_band"]["high"]))
			and is_equal_approx(float(prof["melt_mid"]), float(melt["stats"]["p50"])),
			"A3 %s melt window %.0f / %.0f / %.0f == meltfilter trend band %.0f–%.0f, p50 %.0f"
			% [line, prof["melt_lo"], prof["melt_mid"], prof["melt_hi"], melt["operating_band"]["low"],
			melt["operating_band"]["high"], melt["stats"]["p50"]])
		_check(is_equal_approx(float(prof["die_plate_bar"]), float(FORM008_KOPDRUK[line][0])),
			"A4 %s die_plate_bar %.0f == bottom of FORM-008's kopdruk window %.0f–%.0f"
			% [line, prof["die_plate_bar"], FORM008_KOPDRUK[line][0], FORM008_KOPDRUK[line][1]])
		# ExtruderModel (#278) derives its die plate the same way. Two models, one
		# number: a drift between them is a red check here, not a silent split.
		var cfg := load("res://src/data/machines/Extruder%s.tres" % line.to_upper()) as ExtruderConfig
		_check(cfg != null and is_equal_approx(float(prof["die_plate_bar"]), cfg.die_plate_nominal_bar),
			"A4b %s screw die plate %.0f == ExtruderModel's Extruder%s.tres die_plate_nominal_bar %s"
			% [line, prof["die_plate_bar"], line.to_upper(), str(cfg.die_plate_nominal_bar) if cfg != null else "<missing>"])
	# The MFI anchor is 3B's nominal point, and it reads CAL_MFI.
	_check(is_equal_approx(MfiProxyScript.CAL_Q_KG_H, _p50("3b", "Output"))
		and is_equal_approx(MfiProxyScript.CAL_T_C, _p50("3b", "Smelt temperatuur voor meltfilter"))
		and is_equal_approx(MfiProxyScript.CAL_P_BAR, float(ExtruderScrewScript.PROFILES["3B"]["die_plate_bar"])),
		"A5 MfiProxy anchor %.0f kg/h / %.0f bar / %.0f °C is 3B's output p50, die plate, melt p50"
		% [MfiProxyScript.CAL_Q_KG_H, MfiProxyScript.CAL_P_BAR, MfiProxyScript.CAL_T_C])
	var anchor = MfiProxyScript.new()
	var a_mfi : float = anchor.update(MfiProxyScript.CAL_Q_KG_H, MfiProxyScript.CAL_P_BAR, MfiProxyScript.CAL_T_C)
	_check(absf(a_mfi - MfiProxyScript.CAL_MFI) < 1e-3,
		"A6 the anchor reads MFI %.4f (CAL_MFI %.1f; MFI_GAIN %.6f is solved from it)" % [a_mfi, MfiProxyScript.CAL_MFI, MfiProxyScript.MFI_GAIN])

	# ── B. a real LineFlow over the four macro-built lines ───────────────────
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	for l in LINES:
		bm.call("_build_full_line", String(l[0]), l[1] as Vector3, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")

	var nodes : Array = lf.get("_nodes")
	var screw_ids : Array = []
	var silos := 0
	var silo_with_screw := 0
	var ex_by_id : Dictionary = {}
	for nd in nodes:
		var id := String((nd as Dictionary).get("id", ""))
		if id == "extruder_silo":
			silos += 1
			if nd.get("ex") != null:
				silo_with_screw += 1
		if nd.get("ex") != null:
			screw_ids.append(id)
			ex_by_id[id] = nd
	screw_ids.sort()
	var want : Array = EXTRUDER_LINE.keys()
	want.sort()
	_check(silos >= 3, "B0 anti-vacuity: the lines placed %d extruder_silo nodes (lines 1, 3A, 3B)" % silos)
	_check(silo_with_screw == 0, "B1 no extruder_silo carries a screw model (%d of %d do)" % [silo_with_screw, silos])
	_check(screw_ids == want, "B1b screw models sit on exactly the extruders %s (got %s)" % [str(want), str(screw_ids)])
	if screw_ids != want:
		_finish(); return

	for id in ex_by_id:
		var ex = (ex_by_id[id] as Dictionary)["ex"]
		var own : String = String(EXTRUDER_LINE[id])
		if own != "":
			_check(String(ex.profile_id) == own.to_upper() and not bool(ex.profile_carried),
				"B2 %s runs its own profile %s (got %s, carried %s)" % [id, own.to_upper(), ex.profile_id, ex.profile_carried])
		else:
			_check(String(ex.profile_id) == ExtruderScrewScript.DEFAULT_PROFILE and bool(ex.profile_carried),
				"B2 %s has no profile of its own and says so (%s, carried %s)" % [id, ex.profile_id, ex.profile_carried])

	# Feed every extruder straight into its input buffer at its profile's
	# nominal output (3A 908, 3B 799 kg/h; the carried lines 3B's), 300 s.
	var feed : Dictionary = {}
	for id in ex_by_id:
		feed[id] = float(((ex_by_id[id] as Dictionary)["ex"]).nominal_throughput_kg_s)
	var steps : int = int(SETTLE_S / 0.1)
	for _s in steps:
		for id in ex_by_id:
			var m : float = float(feed[id]) * 0.1
			((ex_by_id[id] as Dictionary)["in"] as MaterialBatch).add(MaterialBatch.new(m,
				m / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test", 0.0, 0.0))
		lf.call("tick", 0.1)

	var spec := QaSpecScript.default_ldpe()
	for id in ex_by_id:
		var nd : Dictionary = ex_by_id[id]
		var ex = nd["ex"]
		var line : String = String(EXTRUDER_LINE[id])
		var thru_kg_h : float = float(nd.get("thru", 0.0)) * 3600.0
		var die : float = float(nd.get("die_pressure", 0.0))
		var melt : float = float(nd.get("melt_temp", 0.0))
		var mfi_v : float = float(nd.get("mfi_value", 0.0))
		print("  %-14s %s  %.0f rpm  %.0f kg/h  melt %.1f °C  die plate %.1f bar  MFI %.2f g/10min"
			% [id, ex.profile_id, float(ex.screw_rpm), thru_kg_h, melt, die, mfi_v])
		if line == "":
			print("  info  : %s carries 3B's profile — no trend or FORM-008 row for this line; not gated" % id)
			continue
		var want_kg_h : float = float(feed[id]) * 3600.0
		_check(absf(thru_kg_h - want_kg_h) <= want_kg_h * 0.02,
			"B3 anti-vacuity: %s carries the fed %.0f kg/h (reads %.0f)" % [id, want_kg_h, thru_kg_h])
		var rpm_p50 := _p50(line, "Snelheid hoofdmotor")
		_check(absf(float(ex.screw_rpm) - rpm_p50) <= 0.5,
			"B4 %s screw at %.1f rpm == trend p50 %.0f (was a flat 200)" % [id, float(ex.screw_rpm), rpm_p50])
		var mb : Dictionary = _trend(line, "Smelt temperatuur voor meltfilter").get("operating_band", {})
		_check(not mb.is_empty() and melt >= float(mb["low"]) and melt <= float(mb["high"]),
			"B5 %s melt %.1f °C inside the meltfilter trend band %s (was 195)" % [id, melt, str(mb)])
		var fw : Array = FORM008_KOPDRUK[line]
		_check(die >= float(fw[0]) and die <= float(fw[1]),
			"B6 %s die plate %.1f bar inside FORM-008's kopdruk window %.0f–%.0f (was 0.11)" % [id, die, fw[0], fw[1]])
		var kb : Dictionary = _trend(line, String(KOPDRUK_SIGNAL[line])).get("operating_band", {})
		_check(not kb.is_empty() and die >= float(kb["low"]) and die <= float(kb["high"]),
			"B7 %s die plate %.1f bar inside the kopdruk trend band %s" % [id, die, str(kb)])
		_check(spec.check_mfi(mfi_v) == QaSpecScript.Grade.ACCEPT,
			"B8 %s MFI %.2f g/10min grades ACCEPT (%.1f–%.1f; was 1491 → REJECT)" % [id, mfi_v, spec.mfi_min, spec.mfi_max])

	# ── C. the terminal and the SCADA panel read an extruder ─────────────────
	var term = TerminalScript.new()
	var t_nd : Dictionary = term.call("_first_extruder_node", lf)
	var t_id := String(t_nd.get("id", "<none>"))
	_check(EXTRUDER_LINE.has(t_id), "C1 the Quality terminal reads an extruder (%s), not the extruder_silo" % t_id)
	var row := String(term.call("_fmt_metric", lf, "die_pressure", " bar"))
	var want_row := "%.2f bar" % float(t_nd.get("die_pressure", NAN))
	_check(row == want_row and float(t_nd.get("die_pressure", 0.0)) >= 100.0,
		"C2 its die-plate row shows '%s' — that extruder's pressure, in the hundreds of bar" % row)
	term.free()
	var s_nd : Dictionary = lf.call("_first_extruder_node")
	_check(String(s_nd.get("id", "")) == t_id,
		"C3 the SCADA panel reads the same extruder (%s)" % s_nd.get("id", "<none>"))

	# ── D. measured, not gated: die plate across the trend's output band ─────
	# The model is proportional to output; the plant's kopdruk is flat with it.
	var probe = ExtruderScrewScript.new()
	probe.configure_for_extruder("extruder_3b")
	var ob : Dictionary = _trend("3b", "Output").get("operating_band", {})
	var kb3 : Dictionary = _trend("3b", "Smeltdruk voor kopfilter").get("operating_band", {})
	if not ob.is_empty():
		for q in [float(ob["low"]), float(probe.nominal_throughput_kg_s) * 3600.0, float(ob["high"])]:
			var e = ExtruderScrewScript.new(NAN, probe.melt_target_mid)
			e.configure_for_extruder("extruder_3b")
			e.melt_temp = e.melt_target_mid
			e.set_rpm(e.rpm_nominal)
			e.set_throughput(q / 3600.0)
			for _i in 1800:
				e.tick(0.1)
			print("  info  : 3B at %.0f kg/h → die plate %.1f bar (plant kopdruk band %s, flat with output)"
				% [q, e.die_pressure, str(kb3)])
	_finish()

func _finish() -> void:
	if _fails == 0:
		print("Result: PASS (%d ok, 0 fail)" % _oks)
		get_tree().quit(0)
	else:
		print("Result: FAIL (%d ok, %d fail)" % [_oks, _fails])
		get_tree().quit(1)
