extends Node
## QA SPEC / LAB / ASSESSMENT — pure-data guard on the graded quality loop.
##
##   godot --headless --path <proj> res://src/tests/test_qa_spec.tscn
##
## A) QaSpec verdict boundaries — ACCEPT band, REGRADE shoulder, REJECT beyond,
##    driven off MaterialBatch.moisture_pct() :74-75, contam_pct() :78-79 and
##    ldpe_fraction() :66-67. No other MaterialBatch field feeds a verdict.
## B) NAN MFI can never grade ACCEPT. MfiProxy.predicted_mfi starts at 0.0
##    (MfiProxy.gd:64) and flow_label() maps 0.0 to "no flow" (:127-134), so a
##    never-updated proxy is indistinguishable from a stalled line.
## C) QaLab bench delay — submitted at t=0 with bench_delay_s=600 is still
##    pending at t=599.9 and resolved at t=600.0, under a FIXED DT.
## D) QaLab is NON-DESTRUCTIVE by default: the source batch is byte-identical
##    after a submit, so the plant mass ledger never sees the assay.
## E) The snapshot's composition is a DEEP COPY — MaterialBatch.to_dict()
##    :222-224 hands back the LIVE dict by reference.
## F) Assessment keys on line_id + session_id: foreign events are DROPPED AND
##    COUNTED, never silently scored.
## G) quantity_escaped meters only the kg banked while armed — the gap between
##    a REJECT verdict landing and the operator holding.
## H) A rule that never armed scores "n/a" and is excluded from the mean, so a
##    session where nothing happened cannot read 100%.
## I) QaSpec reports which of its limits are still unproven (Rule 1 honesty).
##
## NON-VACUITY: check 0 asserts the fixtures really produced both an ACCEPT and
## a REJECT, so a 0/0 run cannot read green (CLAUDE.md Rule 3 — npc-05 printed
## 31/31 while moving 0.00 kg).
##
## MUTATION-PROVEN: widening mfi_max past the fixture turns A red; returning
## ACCEPT for NAN turns B red; flipping tick()'s comparison turns C red;
## swapping duplicate_batch() for split_mass() turns D red; dropping the
## composition.duplicate() turns E red; removing the session check in observe()
## turns F red; metering while disarmed turns G red.

const DT : float = 0.1

var _pass : int = 0
var _fail : int = 0
var _skip : int = 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1


func _note(msg: String) -> void:
	print("  note  : %s" % msg)


func _section(t: String) -> void:
	print("\n[%s]" % t)


func _ready() -> void:
	print("=== QA SPEC / LAB / ASSESSMENT — graded quality loop, pure data ===")

	var spec := QaSpec.default_ldpe()

	# ── A ────────────────────────────────────────────────────────────────────
	_section("A — QaSpec verdict boundaries")
	var b_ok := MaterialBatch.new(100.0, 0.20, {"LDPE": 1.0}, "test", 0.2, 0.2)
	var r_ok := spec.evaluate(b_ok, 1.20)
	_ok(String(r_ok["verdict"]) == "ACCEPT",
		"in-band batch grades ACCEPT (mfi 1.20, vocht %.2f%%, vuil %.2f%%)"
			% [b_ok.moisture_pct(), b_ok.contam_pct()])

	var b_wet := MaterialBatch.new(100.0, 0.20, {"LDPE": 1.0}, "test", 2.0, 0.2)
	var r_wet := spec.evaluate(b_wet, 1.20)
	_ok(String(r_wet["verdict"]) == "REJECT",
		"wet batch grades REJECT (vocht %.2f%% > reject %.2f%%)"
			% [b_wet.moisture_pct(), spec.moisture_reject_pct])

	var b_damp := MaterialBatch.new(100.0, 0.20, {"LDPE": 1.0}, "test", 0.7, 0.2)
	var r_damp := spec.evaluate(b_damp, 1.20)
	_ok(String(r_damp["verdict"]) == "REGRADE",
		"shoulder batch grades REGRADE (vocht %.2f%% in %.2f..%.2f)"
			% [b_damp.moisture_pct(), spec.moisture_max_pct, spec.moisture_reject_pct])

	_ok(String(spec.evaluate(b_ok, 0.10)["verdict"]) == "REJECT",
		"mfi 0.10 below reject floor %.2f -> REJECT" % spec.mfi_reject_min)
	_ok(String(spec.evaluate(b_ok, 0.30)["verdict"]) == "REGRADE",
		"mfi 0.30 in the low shoulder -> REGRADE")

	# ── B ────────────────────────────────────────────────────────────────────
	_section("B — NAN MFI never ACCEPTs")
	var r_nan := spec.evaluate(b_ok, NAN)
	_ok(String(r_nan["verdict"]) != "ACCEPT",
		"NAN mfi -> %s, reasons %s" % [String(r_nan["verdict"]), str(r_nan["reasons"])])
	_ok((r_nan["reasons"] as Array).has("mfi_unavailable"),
		"missing telemetry is named in the reasons, not silently graded")

	# ── C / D / E ────────────────────────────────────────────────────────────
	_section("C — bench delay under a fixed DT")
	var lab := QaLab.new("3C", "TEST-SESSION", spec)
	lab.set_bench_delay_s(600.0)
	var src_batch := MaterialBatch.new(50.0, 0.10, {"LDPE": 1.0}, "test", 0.1, 0.1)
	var pre_mass := src_batch.mass_kg
	var pre_vol := src_batch.volume_m3
	var pre_water := src_batch.water_kg
	var sid := lab.submit_sample(src_batch, {"source_key": "L3C.18", "mfi": 1.20})
	_ok(sid > 0, "submit_sample returned id %d" % sid)

	var t := 0.0
	while t < 599.85:
		lab.tick(DT)
		t += DT
	_ok(lab.pending_count() == 1,
		"still on the bench at t=%.1f s (%d pending)" % [t, lab.pending_count()])
	while lab.pending_count() > 0 and t < 601.0:
		lab.tick(DT)
		t += DT
	_ok(lab.pending_count() == 0 and int(lab.stats()["resolved"]) == 1,
		"resolved at t=%.1f s (%d resolved)" % [t, int(lab.stats()["resolved"])])

	_section("D — non-destructive by default")
	_ok(is_equal_approx(src_batch.mass_kg, pre_mass)
			and is_equal_approx(src_batch.volume_m3, pre_vol)
			and is_equal_approx(src_batch.water_kg, pre_water),
		"source batch untouched (%.4f kg / %.4f m3 before and after)" % [pre_mass, pre_vol])
	_ok(not lab.destructive, "lab defaults to non-destructive, so the ledger never sees the assay")

	_section("E — snapshot composition is a deep copy")
	var res := lab.result(sid)
	_ok(not res.is_empty(), "result(%d) is retrievable after resolution" % sid)
	var comp_before := float((res["composition"] as Dictionary).get("LDPE", -1.0))
	src_batch.composition["LDPE"] = 0.5
	_ok(is_equal_approx(float((res["composition"] as Dictionary).get("LDPE", -1.0)), comp_before),
		"snapshot LDPE stayed %.3f after mutating the source dict" % comp_before)
	_ok(float(res["submitted_at_s"]) < float(res["ready_at_s"]),
		"verdict was frozen at submit (%.1f s) and revealed later (%.1f s)"
			% [float(res["submitted_at_s"]), float(res["ready_at_s"])])

	# ── F ────────────────────────────────────────────────────────────────────
	_section("F — Assessment keys on line_id + session_id")
	var asm := Assessment.new("3C", "TEST-SESSION")
	asm.add_rule({
		"id": "escaped", "kind": Assessment.RuleKind.QUANTITY_ESCAPED, "weight": 100.0,
		"arm_kind": "qa_sample_ready", "arm_when": {"verdict": "REJECT"},
		"meter_kind": "mass_banked", "meter_field": "kg",
		"disarm_kind": "operator_decision", "disarm_when": {"action": "hold"},
		"budget_kg": 250.0,
	})
	asm.observe(Assessment.event("3A", "TEST-SESSION", "mass_banked", {"kg": 999.0}, 0.0))
	asm.observe(Assessment.event("3C", "OTHER-SESSION", "mass_banked", {"kg": 999.0}, 0.0))
	var counts := asm.score()["counts"] as Dictionary
	_ok(int(counts["dropped_wrong_line"]) == 1 and int(counts["dropped_wrong_session"]) == 1,
		"foreign events dropped (line %d / session %d), never scored"
			% [int(counts["dropped_wrong_line"]), int(counts["dropped_wrong_session"])])

	# ── H (before arming, while the rule is still untouched) ─────────────────
	_section("H — an unarmed rule scores n/a, not 100%")
	var idle := asm.score()
	_ok(String((idle["rules"] as Array)[0]["status"]) == "n/a",
		"rule that never armed reports status n/a")
	_ok(is_equal_approx(float(idle["total_pct"]), 0.0) and is_equal_approx(float(idle["scored_weight"]), 0.0),
		"nothing scored yet, so no weight counted — a do-nothing session cannot pass")

	# ── G ────────────────────────────────────────────────────────────────────
	_section("G — quantity_escaped meters only the armed window")
	asm.observe(Assessment.event("3C", "TEST-SESSION", "qa_sample_ready",
		{"sample_id": 1, "verdict": "REJECT"}, 0.0))
	asm.observe(Assessment.event("3C", "TEST-SESSION", "mass_banked", {"kg": 40.0}, 10.0))
	asm.observe(Assessment.event("3C", "TEST-SESSION", "operator_decision",
		{"sample_id": 1, "action": "hold"}, 20.0))
	asm.observe(Assessment.event("3C", "TEST-SESSION", "mass_banked", {"kg": 500.0}, 30.0))
	var sc := asm.score()
	var esc := float((sc["rules"] as Array)[0]["value"])
	_ok(is_equal_approx(esc, 40.0),
		"escaped %.1f kg — the 40 kg banked while armed, not the 500 kg after the hold" % esc)
	_ok(int(sc["counts"]["events"]) > 0,
		"assessment saw %d in-session events (non-vacuous)" % int(sc["counts"]["events"]))

	# ── I ────────────────────────────────────────────────────────────────────
	_section("I — Rule 1: the spec admits what it does not know")
	var unproven := spec.unproven_limits()
	_ok(spec.needs_operator_count() == unproven.size() and unproven.size() > 0,
		"%d of the spec limits are still placeholders: %s"
			% [spec.needs_operator_count(), str(unproven)])
	_ok(spec.confidence_of("moisture_max_pct") == QaSpec.CONF_PROBABLE,
		"moisture ceiling is the one operator-sourced limit (ProcessModel.gd:104 band)")

	# ── 0 — non-vacuity ──────────────────────────────────────────────────────
	_section("0 — non-vacuity")
	_ok(String(r_ok["verdict"]) == "ACCEPT" and String(r_wet["verdict"]) == "REJECT",
		"fixtures produced a real ACCEPT and a real REJECT, so the boundaries were exercised")
	_ok(int(lab.stats()["submitted"]) == 1 and int(lab.stats()["resolved"]) == 1,
		"lab actually ran a sample end to end (%d submitted, %d resolved)"
			% [int(lab.stats()["submitted"]), int(lab.stats()["resolved"])])

	_note("spec %s: mfi %.2f..%.2f, vocht<=%.2f%%, vuil<=%.2f%%, ldpe>=%.3f"
		% [spec.spec_id, spec.mfi_min, spec.mfi_max, spec.moisture_max_pct,
		   spec.contam_max_pct, spec.ldpe_min_fraction])
	_note("verdict of the resolved sample: %s (%s)"
		% [String(res["verdict"]), str(res["reasons"])])
	_finish()


func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
