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
## D (2026-09-25): the die plate across the trend's OUTPUT band. A standalone
## screw per line at the band's low edge, p50 and high edge, turning the plant's
## own rpm for that output (read from the paired per-sample curves). The die
## plate must sit inside the kopdruk trend band at all three. At an unchanged
## melt the die plate follows Q^n and the MFI does not follow Q at all. E: the
## ExtruderModel (the BluPort's model) carries the same die law.
##
## Why D changed (operator rulings 2026-09-25, docs/plant/operator_rulings_2026-09-25.md):
## this suite used to print, ungated, "3B at 534 / 799 / 1263 kg/h → 96 / 144 /
## 227 bar" and call the plant's flat kopdruk an open model-form question. That
## probe held the screw at 110 rpm while the output more than doubled; the plant
## turns 60 / 80 / 120 rpm at those outputs. The operator called the flatness
## operator-specific, perhaps even an office test run without head filters,
## so the trend is a band to stay inside, not a law to fit. He chose the
## textbook power-law die, P ∝ Q^0.35, for both models, with MfiProxy taking
## only the matching exponent (the MFI itself is low priority until the beta).
## docs/audit/extruder_screw_die_plate_2026-09-24.md §10.

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

## An rpm sample pairs with an output sample within this window (s): the rpm
## curve is downsampled to ~6 min buckets (fit_kopdruk_vs_output.py's window).
const RPM_PAIR_S := 400.0

var _fails := 0
var _oks := 0
var _pairs_cache : Dictionary = {}   # line → Array[Vector2(output kg/h, rpm)]

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

	# ── D. the die plate across the trend's output band ──────────────────────
	# rpm per output is the plant's own: the "Snelheid hoofdmotor" sample paired
	# with each "Output" sample, median at that output, scaled onto the profile's
	# rpm_nominal by the plant's rpm at the output p50. The scaling is needed
	# because rpm_nominal is the rpm curve's OWN p50 (3B 110), while the plant
	# turns 80 rpm at its output p50: two independent p50s, recorded in §10.
	var n_die : float = ExtruderScrewScript.POWER_LAW_N
	for line in ["3a", "3b"]:
		var id : String = "extruder_" + line
		var ob : Dictionary = _trend(line, "Output").get("operating_band", {})
		var kb : Dictionary = _trend(line, String(KOPDRUK_SIGNAL[line])).get("operating_band", {})
		var q50 := _p50(line, "Output")
		var rpm50 := _plant_rpm_at(line, q50)
		_check(not ob.is_empty() and not kb.is_empty() and rpm50 > 0.0,
			"D0 %s output band %s, kopdruk band %s, plant rpm %.0f at the output p50 %.0f (paired curves)"
			% [line, str(ob), str(kb), rpm50, q50])
		if ob.is_empty() or kb.is_empty() or rpm50 <= 0.0:
			continue
		var rpm_nom : float = float(ExtruderScrewScript.PROFILES[line.to_upper()]["rpm_nominal"])
		for q in [float(ob["low"]), q50, float(ob["high"])]:
			var plant_rpm := _plant_rpm_at(line, q)
			var rpm : float = rpm_nom * plant_rpm / rpm50
			var e = _settled_screw(id, q, rpm)
			_check(plant_rpm > 0.0 and e.die_pressure >= float(kb["low"]) and e.die_pressure <= float(kb["high"]),
				"D1 %s at %.0f kg/h, %.1f rpm (the plant's %.0f rpm there, onto rpm_nominal %.0f): die plate %.1f bar inside the kopdruk trend band %.0f–%.0f (melt %.1f °C)"
				% [id, q, rpm, plant_rpm, rpm_nom, e.die_pressure, kb["low"], kb["high"], e.melt_temp])
			var capped = _settled_screw(id, q, rpm_nom)
			print("  info  : %s at %.0f kg/h on the nominal %.0f rpm (rpm_pct 1.0, LineFlow's cap): die plate %.1f bar, MFI %.3f"
				% [id, q, rpm_nom, capped.die_pressure, _mfi_of(capped, q)])
		# The law, at an unchanged melt: throughput does not enter the screw's
		# heat balance, so two screws at one rpm carry the same melt and differ
		# only in the flow through the die.
		var lo = _settled_screw(id, float(ob["low"]), rpm_nom)
		var hi = _settled_screw(id, float(ob["high"]), rpm_nom)
		var want_ratio : float = pow(float(ob["high"]) / float(ob["low"]), n_die)
		var got_ratio : float = hi.die_pressure / maxf(lo.die_pressure, 0.001)
		_check(is_equal_approx(lo.melt_temp, hi.melt_temp) and absf(got_ratio - want_ratio) < 1e-4,
			"D2 %s die plate at %.0f / %.0f kg/h, one melt (%.2f °C): ratio %.4f == (Q ratio)^%.2f %.4f (a linear die reads %.4f)"
			% [id, ob["high"], ob["low"], hi.melt_temp, got_ratio, n_die, want_ratio, float(ob["high"]) / float(ob["low"])])
		var mfi_lo := _mfi_of(lo, float(ob["low"]))
		var mfi_hi := _mfi_of(hi, float(ob["high"]))
		_check(absf(mfi_hi - mfi_lo) < 1e-6 * maxf(mfi_lo, 1.0) and mfi_lo > 0.0,
			"D3 %s at an unchanged melt the MFI does not follow output: %.4f at %.0f kg/h == %.4f at %.0f kg/h"
			% [id, mfi_lo, ob["low"], mfi_hi, ob["high"]])

	# ── E. ExtruderModel (the BluPort's model) carries the same die law ──────
	_check(is_equal_approx(ExtruderModel.DIE_FLOW_INDEX, n_die),
		"E0 ExtruderModel.DIE_FLOW_INDEX %.2f == ExtruderScrew.POWER_LAW_N %.2f" % [ExtruderModel.DIE_FLOW_INDEX, n_die])
	var cfg_3b := load("res://src/data/machines/Extruder3B.tres") as ExtruderConfig
	var ob3 : Dictionary = _trend("3b", "Output").get("operating_band", {})
	var q50b := _p50("3b", "Output")
	if cfg_3b == null or ob3.is_empty():
		_check(false, "E1 Extruder3B.tres and the 3B output band load")
		_finish(); return
	for r in [float(ob3["low"]) / q50b, 1.0, float(ob3["high"]) / q50b]:
		var m := ExtruderModel.new(cfg_3b.duplicate())
		m.melt_temp = cfg_3b.melt_temp_setpoint
		m.set_screw_rpm_setpoint(cfg_3b.screw_rpm_nominal * r)
		m.tick(0.1, {"start_production": true})
		for _i in 3000:   # 300 s, test_die_pressure_bar's own run to nominal
			m.tick(0.1, {})
		var qn : float = m.throughput_kg_h / cfg_3b.nominal_kg_per_h
		var melt_factor : float = 1.0 + (cfg_3b.melt_temp_setpoint - m.melt_temp) \
			* ExtruderModel.DIE_PRESSURE_BAR_PER_C / ExtruderModel.MELT_FIT_LEVEL_BAR
		var got_die : float = m.die_plate_bar / cfg_3b.die_plate_nominal_bar
		var want_die : float = pow(qn, n_die) * melt_factor
		_check(m.state == ExtruderModel.State.RUNNING and absf(qn - r) < 0.02,
			"E1 anti-vacuity: ExtruderModel 3B RUNNING at %.1f rpm carries %.3f × nominal (asked %.3f; state %s)"
			% [m.screw_rpm, qn, r, m.get_state_name()])
		_check(absf(got_die - want_die) < 1e-3,
			"E2 ExtruderModel 3B die plate %.1f bar = %.0f × (Q %.3f)^%.2f × melt %.4f (%.4f vs %.4f); MP>MF stays linear, %.1f bar"
			% [m.die_plate_bar, cfg_3b.die_plate_nominal_bar, qn, n_die, melt_factor, got_die, want_die, m.mp_after_laserfilter_bar])
	_finish()

## A standalone screw on `id`'s profile, fed `q_kg_h` at `rpm`, started at the
## profile's melt midpoint and run 300 s (the section-B settle).
func _settled_screw(id: String, q_kg_h: float, rpm: float):
	var e = ExtruderScrewScript.new(NAN, 0.0)
	e.configure_for_extruder(id)
	e.melt_temp = e.melt_target_mid
	e.set_rpm(rpm)
	e.set_throughput(q_kg_h / 3600.0)
	for _i in int(SETTLE_S / 0.1):
		e.tick(0.1)
	return e

## The MFI LineFlow would publish for a settled screw at `q_kg_h`.
func _mfi_of(e, q_kg_h: float) -> float:
	var mfi = MfiProxyScript.new()
	return float(mfi.update(q_kg_h, e.die_pressure, e.melt_temp))

## One per-sample trend curve as [unix times, values] (src/data/plant/trends/).
func _curve(file: String) -> Array:
	var f := FileAccess.open("res://src/data/plant/trends/" + file, FileAccess.READ)
	if f == null:
		return [PackedFloat64Array(), PackedFloat64Array()]
	var d = JSON.parse_string(f.get_as_text())
	var ts := PackedFloat64Array()
	var vs := PackedFloat64Array()
	if typeof(d) == TYPE_DICTIONARY:
		for i in (d["t_iso"] as Array).size():
			ts.append(float(Time.get_unix_time_from_datetime_string(String(d["t_iso"][i]))))
			vs.append(float(d["v"][i]))
	return [ts, vs]

## The plant's median main-motor speed at an output: each "Output" sample
## paired with the nearest "Snelheid hoofdmotor" sample within RPM_PAIR_S,
## running pairs only (output > 300 kg/h, rpm > 40: the fit script's cut), the
## median over pairs within ±10 % of `q`. 0.0 when nothing pairs.
## tools/audit/fit_kopdruk_vs_output.py prints the same medians.
func _plant_rpm_at(line: String, q: float) -> float:
	if not _pairs_cache.has(line):
		var out := _curve("%s_output.json" % line)
		var rpm := _curve("%s_snelheid_hoofdmotor.json" % line)
		var pairs : Array = []
		var tr : PackedFloat64Array = rpm[0]
		for i in (out[0] as PackedFloat64Array).size():
			var t : float = out[0][i]
			var j : int = tr.bsearch(t)
			var best := -1
			for k in [j - 1, j]:
				if k >= 0 and k < tr.size() and absf(tr[k] - t) <= RPM_PAIR_S \
						and (best < 0 or absf(tr[k] - t) < absf(tr[best] - t)):
					best = k
			if best >= 0 and float(out[1][i]) > 300.0 and float(rpm[1][best]) > 40.0:
				pairs.append(Vector2(out[1][i], rpm[1][best]))
		_pairs_cache[line] = pairs
	var near : Array = []
	for p in _pairs_cache[line]:
		if absf((p as Vector2).x - q) <= 0.1 * q:
			near.append((p as Vector2).y)
	if near.is_empty():
		return 0.0
	near.sort()
	var n := near.size()
	return float(near[n / 2]) if n % 2 == 1 else 0.5 * (float(near[n / 2 - 1]) + float(near[n / 2]))

func _finish() -> void:
	if _fails == 0:
		print("Result: PASS (%d ok, 0 fail)" % _oks)
		get_tree().quit(0)
	else:
		print("Result: FAIL (%d ok, %d fail)" % [_oks, _fails])
		get_tree().quit(1)
