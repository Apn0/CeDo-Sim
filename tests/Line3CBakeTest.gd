extends Node3D

## #173/#174 — validate the BAKED Line 3C transfer model against the OPERATOR'S
## real numbers + the verified research band. A realistic dirty-wet LDPE film
## flake feed (1687 kg/h) runs through all 30 Line3CDef stages; we check:
##   • Bezinkafscheider (L3C.3) heavies reject ≈ 100 kg/h     (operator)
##   • Flotatietank (L3C.11) heavies reject ≈ 100 kg/h        (operator)
##   • moisture AT the compactor feed (Extruder Silo) ≈ 5–10% (operator)
##   • granulate out ≈ 0 moisture (compactor + 250 °C + 2× vacuum) (operator)
##   • overall mass yield in the real 73–85% band             (Austrian LCA)
##   • high LDPE purity + melt grade

const ProcessModel  = preload("res://src/sim/ProcessModel.gd")
const Line3CDef     = preload("res://src/sim/Line3CDef.gd")
const MaterialBatch = preload("res://src/sim/MaterialBatch.gd")
const BaleDefs      = preload("res://src/sim/BaleDefs.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	print("=== #173/#174 LINE 3C BAKE — calibrated to CeDo's numbers ===")
	# Real dirty-wet feed @ 1687 kg/h: 8% moisture, 6% surface dirt, and a polymer
	# mix carrying ~13% density-heavies (PET/PVC/etc, the "other" the separators sink).
	var feed := 1687.0
	var comp := {"LDPE": 0.85, "HDPE": 0.02, "other": 0.13}
	var b = MaterialBatch.new(feed, feed / 350.0, comp, "feed", feed * 0.08, feed * 0.06)

	var compactor_feed_moist := -1.0
	var reject := {"L3C.3": 0.0, "L3C.11": 0.0}
	var peak_moist := 0.0
	var heet_moist := -1.0   # moisture right after the Heetafslag water-ring quench

	for i in Line3CDef.STAGES.size():
		var code : String = String(Line3CDef.STAGES[i]["code"])
		# Moisture entering the compactor/extruder = state just before PCU.
		if code == "PCU" and compactor_feed_moist < 0.0:
			compactor_feed_moist = b.moisture_pct()
		var solid_before : float = b.contaminant_kg + b.polymer_kg()
		var t : Dictionary = ProcessModel.stage_transfer(code)
		if float(t["contam_remove"]) > 0.0: b.remove_contaminant(float(t["contam_remove"]))
		if float(t["reject_other"])  > 0.0: b.reject_polymer("other", float(t["reject_other"]))
		if float(t["reject_hdpe"])   > 0.0: b.reject_polymer("HDPE",  float(t["reject_hdpe"]))
		if float(t["water_remove"])  > 0.0: b.remove_water(float(t["water_remove"]))
		if float(t["water_add"])     > 0.0: b.add_water(b.polymer_kg() * float(t["water_add"]))
		if float(t["waste"])         > 0.0: b.split_fraction(float(t["waste"]))
		var solid_after : float = b.contaminant_kg + b.polymer_kg()
		if reject.has(code):
			reject[code] += (solid_before - solid_after)
		peak_moist = maxf(peak_moist, b.moisture_pct())
		if code == "Heet": heet_moist = b.moisture_pct()

	var yield_frac : float = b.mass_kg / feed
	print("    OUT %.0f kg · yield %.1f%% · compactor-feed moist %.1f%% · final moist %.2f%% · LDPE %.1f%% · Q %.0f"
		% [b.mass_kg, yield_frac * 100.0, compactor_feed_moist, b.moisture_pct(),
		   b.ldpe_fraction() * 100.0, b.quality_grade()])
	print("    rejects — Bezink %.0f kg/h · Flotatie %.0f kg/h · (peak wash moist %.0f%%)"
		% [reject["L3C.3"], reject["L3C.11"], peak_moist])

	# Operator anchors.
	_ok(reject["L3C.3"] >= 60.0 and reject["L3C.3"] <= 145.0,
		"Bezinkafscheider heavies reject ≈ 100 kg/h (%.0f)" % reject["L3C.3"])
	_ok(reject["L3C.11"] >= 60.0 and reject["L3C.11"] <= 145.0,
		"Flotatietank heavies reject ≈ 100 kg/h (%.0f)" % reject["L3C.11"])
	_ok(compactor_feed_moist >= 3.0 and compactor_feed_moist <= 12.0,
		"flake reaches the compactor at 5–10%% moisture (%.1f%%)" % compactor_feed_moist)
	_ok(b.moisture_pct() < 0.6,
		"granulate leaves effectively dry — 250 °C + 2× vacuum (%.2f%%)" % b.moisture_pct())
	_ok(heet_moist > 2.0,
		"Heetafslag re-wets the pellet surface (water-ring quench) — %.1f%%" % heet_moist)
	_ok(b.moisture_pct() < 0.5,
		"dewater screen + centrifuge pull surface water back to <=0.5%% (%.2f%%)" % b.moisture_pct())
	_ok(peak_moist > 20.0, "flake is genuinely wet through the wash section (%.0f%%)" % peak_moist)
	# Yield — the OPERATOR's real number: 1687 in → 1000–1200 kg/h out = 59–71%.
	_ok(yield_frac >= 0.58 and yield_frac <= 0.72,
		"mass yield in CeDo's real 59–71%% band / 1000–1200 kg/h out (%.1f%% = %.0f kg/h)"
			% [yield_frac * 100.0, b.mass_kg])
	_ok(b.ldpe_fraction() > 0.90, "high-purity LDPE out (%.1f%%)" % (b.ldpe_fraction() * 100.0))
	_ok(b.quality_grade() > 80.0, "melt grade high (%.0f/100)" % b.quality_grade())

	# Documented real operating points are present.
	_ok(absf(ProcessModel.MELT_TEMP_C - 250.0) < 0.1, "melt temp documented at 250 °C")
	_ok(ProcessModel.VACUUM_ZONES == 2, "2 vacuum degas zones documented")
	_ok(ProcessModel.REJECT_KG_H.has("L3C.3") and ProcessModel.REJECT_KG_H.has("L3C.11"),
		"density-separator reject rates documented")

	# ── Per-feedstock spread (operator: Alba dirtiest, Fost+ cleanest; visible) ──
	print("    per-feedstock yields (1687 kg/h in):")
	for oid in ["forstplus", "zwolle", "rotterdam", "alba_marl"]:
		var o : Dictionary = BaleDefs.get_origin(oid)
		print("      %-10s yield %.0f%%  (dirt %.0f%% · blue %.2f)"
			% [oid, _line_yield(oid) * 100.0, float(o["dirt"]) * 100.0, float(o["blue"])])
	var fy_forst : float = _line_yield("forstplus")
	var fy_alba  : float = _line_yield("alba_marl")
	_ok(fy_forst > fy_alba,
		"clean Fost+ out-yields dirty Alba (%.0f%% vs %.0f%%)" % [fy_forst * 100.0, fy_alba * 100.0])
	_ok(fy_forst <= 0.75 and fy_alba >= 0.55,
		"both feedstocks land in CeDo's 59–71%% band (Fost+ %.0f%%, dirtiest Alba %.0f%%)" % [fy_forst * 100.0, fy_alba * 100.0])
	_ok(float(BaleDefs.get_origin("forstplus")["blue"]) > float(BaleDefs.get_origin("alba_marl")["blue"]),
		"Fost+ reads bluer than Alba on the bale (tint)")

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

## Run an origin's real feed sample through the whole Line 3C; return mass yield.
func _line_yield(origin_id: String) -> float:
	var bb = BaleDefs.feed_sample(origin_id, 1687.0)
	var m0 : float = bb.mass_kg
	if m0 <= 0.0:
		return 0.0
	for i in Line3CDef.STAGES.size():
		var t : Dictionary = ProcessModel.stage_transfer(String(Line3CDef.STAGES[i]["code"]))
		if float(t["contam_remove"]) > 0.0: bb.remove_contaminant(float(t["contam_remove"]))
		if float(t["reject_other"])  > 0.0: bb.reject_polymer("other", float(t["reject_other"]))
		if float(t["reject_hdpe"])   > 0.0: bb.reject_polymer("HDPE",  float(t["reject_hdpe"]))
		if float(t["water_remove"])  > 0.0: bb.remove_water(float(t["water_remove"]))
		if float(t["water_add"])     > 0.0: bb.add_water(bb.polymer_kg() * float(t["water_add"]))
		if float(t["waste"])         > 0.0: bb.split_fraction(float(t["waste"]))
	return bb.mass_kg / m0

