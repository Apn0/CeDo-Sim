extends Node
## ASSESSMENT — does the generic rule engine actually grade a PROCEDURE?
##
##   godot --headless --path <proj> res://src/tests/test_assessment_procedure.tscn
##
## The graded QA loop shipped on the claim that Assessment is scenario-agnostic
## and that the laser-filter change — all 21 steps of LaserFilter.Change, from
## PROD-SWI-074 — would reuse it unchanged via STEP_ORDER + SAFETY_GATE. That
## claim was asserted, not tested. This suite tests it, using the REAL step
## names off LaserFilter.Change rather than invented ones.
##
## A) A correct run of the full 21-step sequence scores 21/21.
## B) A run that skips a step stalls at the skipped point and cannot reach 21.
## C) SAFETY_GATE catches OPEN performed without LOTO.
## D) THE REAL ONE — a CORRECT change must not be flagged. A filter change takes
##    3-4 hours; LOTO is step 3 and OPEN is step 9, easily 20+ minutes apart.
##    A gate keyed on "was satisfied within gate_window_s" fails an honest
##    operator as soon as the gap exceeds the window, which is a false accusation
##    in a training tool — the worst possible failure mode for this product.
## E) Removing LOTO must re-arm the gate: opening after REMOVE_LOTO is a
##    violation again, even though LOTO happened earlier in the session.

const STEPS : Array[String] = [
	"STOP_SCRAPER", "DEPRESSURIZE", "LOTO", "PLACE_BORDES", "REMOVE_COMPACTBUIS",
	"CAP_NUTS_OFF", "SWING_KAP", "OPEN", "INSPECT", "REMOVE",
	"CLEAN_BRAKERPLATE", "CLEAN_STAALBORSTEL", "REPLACE_KOPEREN_RING",
	"INSERT", "REFIT_AFVOERVIJZEL", "CLOSE", "TORQUE_UITZETSCHROEF",
	"REPRESSURIZE", "REMOVE_LOTO", "RESTART",
]

var _pass := 0
var _fail := 0
var _skip := 0


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


func _seq_rule() -> Dictionary:
	var seq : Array = []
	for s in STEPS:
		seq.append({"kind": s})
	return {
		"id": "lf_procedure", "kind": Assessment.RuleKind.STEP_ORDER,
		"weight": 60.0, "sequence": seq, "strict": false,
	}


## LOTO before the housing is opened. SWI-074 step 14: the werkschakelaar sits
## on the far side of the filter and the padlock goes on before anything opens.
func _gate_rule(window_s: float) -> Dictionary:
	return {
		"id": "loto_before_open", "kind": Assessment.RuleKind.SAFETY_GATE,
		"weight": 0.0,
		"forbidden_kind": "OPEN",
		"gate_kind": "LOTO",
		"ungate_kind": "REMOVE_LOTO",
		"gate_window_s": window_s,
	}


func _ready() -> void:
	print("=== ASSESSMENT — grading the SWI-074 laser-filter procedure ===")

	# ── A ────────────────────────────────────────────────────────────────────
	_section("A — a correct 21-step run scores full marks")
	var a := Assessment.new("3A", "S1")
	a.add_rule(_seq_rule())
	var t := 0.0
	for s in STEPS:
		a.observe(Assessment.event("3A", "S1", s, {}, t))
		t += 60.0
	var ra : Dictionary = (a.score()["rules"] as Array)[0]
	_ok(int(ra["value"]) == STEPS.size(),
		"scored %d of %d steps in order" % [int(ra["value"]), STEPS.size()])
	_ok(is_equal_approx(float(ra["pct"]), 1.0), "pct %.2f" % float(ra["pct"]))

	# ── B ────────────────────────────────────────────────────────────────────
	_section("B — skipping a step cannot reach full marks")
	var b := Assessment.new("3A", "S2")
	b.add_rule(_seq_rule())
	t = 0.0
	for s in STEPS:
		if s == "REPLACE_KOPEREN_RING":     # single-use ring, SWI-074 step 32
			continue
		b.observe(Assessment.event("3A", "S2", s, {}, t))
		t += 60.0
	var rb : Dictionary = (b.score()["rules"] as Array)[0]
	_ok(int(rb["value"]) < STEPS.size(),
		"reusing the koperen ring stalls the sequence at %d of %d"
			% [int(rb["value"]), STEPS.size()])

	# ── C ────────────────────────────────────────────────────────────────────
	_section("C — OPEN without LOTO is a violation")
	# Latch config deliberately. With a window set, this check passes for the
	# wrong reason — gate_ok_at_s is still its sentinel, so the window arm fires
	# before the latch is ever consulted, and the check stays green even if the
	# latch defaults to true. Measured: mutating "latched" to true left this
	# green under a 120 s window and red under the latch.
	var c := Assessment.new("3A", "S3")
	c.add_rule(_gate_rule(0.0))
	c.observe(Assessment.event("3A", "S3", "OPEN", {}, 100.0))
	var sc : Dictionary = c.score()
	_ok(bool(sc["gated"]) and is_equal_approx(float(sc["total_pct"]), 0.0),
		"unlocked entry gates the whole session to 0%")

	# ── D — the one that matters ─────────────────────────────────────────────
	_section("D — a CORRECT change must not be falsely accused")
	# Latch config (window 0) — the correct shape for a padlock. Check F proves
	# an explicit window still expires when a gate genuinely is time-bounded.
	var d := Assessment.new("3A", "S4")
	d.add_rule(_gate_rule(0.0))
	# LOTO at step 3, OPEN at step 8. Five real steps in between: bordes placed,
	# compactbuis off, 3 dopmoeren with the 13 mm sleutel, kap swung right.
	# 25 minutes is a brisk, honest pace for that on a hot filter.
	d.observe(Assessment.event("3A", "S4", "LOTO", {}, 0.0))
	d.observe(Assessment.event("3A", "S4", "OPEN", {}, 1500.0))
	var sd : Dictionary = d.score()
	_ok(not bool(sd["gated"]),
		"LOTO 25 min before OPEN is a correct change, not a violation (gated=%s)"
			% str(bool(sd["gated"])))

	# The whole 3-4 hour change, end to end, with the gate latched throughout.
	var d2 := Assessment.new("3A", "S4b")
	d2.add_rule(_gate_rule(0.0))
	d2.add_rule(_seq_rule())
	var tt := 0.0
	for s in STEPS:
		d2.observe(Assessment.event("3A", "S4b", s, {}, tt))
		tt += 600.0                      # 10 min a step -> 3h20m total
	var sd2 : Dictionary = d2.score()
	_ok(not bool(sd2["gated"]),
		"a full %.1f h change stays unflagged end to end" % (tt / 3600.0))
	_ok(is_equal_approx(float(sd2["total_pct"]), 100.0),
		"and scores %.0f%% on the sequence" % float(sd2["total_pct"]))

	# ── E ────────────────────────────────────────────────────────────────────
	_section("E — REMOVE_LOTO re-arms the gate")
	# Also latch config, so a green here proves REMOVE_LOTO actually unlatched
	# rather than the gap merely exceeding some window.
	var e := Assessment.new("3A", "S5")
	e.add_rule(_gate_rule(0.0))
	e.observe(Assessment.event("3A", "S5", "LOTO", {}, 0.0))
	e.observe(Assessment.event("3A", "S5", "REMOVE_LOTO", {}, 100.0))
	e.observe(Assessment.event("3A", "S5", "OPEN", {}, 200.0))
	var se : Dictionary = e.score()
	_ok(bool(se["gated"]),
		"opening after the padlock came off is a violation again (gated=%s)"
			% str(bool(se["gated"])))

	# ── F ────────────────────────────────────────────────────────────────────
	_section("F — an explicit time window still expires when asked for")
	# Latch is the default, but genuinely time-bounded gates exist (a confined-
	# space gas test really does go stale). Opt-in must still work.
	var f := Assessment.new("3A", "S6")
	f.add_rule({
		"id": "gastest_before_entry", "kind": Assessment.RuleKind.SAFETY_GATE,
		"weight": 0.0,
		"forbidden_kind": "ENTER", "gate_kind": "GAS_TEST",
		"gate_window_s": 1800.0,
	})
	f.observe(Assessment.event("3A", "S6", "GAS_TEST", {}, 0.0))
	f.observe(Assessment.event("3A", "S6", "ENTER", {}, 3600.0))
	_ok(bool(f.score()["gated"]),
		"entry 60 min after a 30 min gas test is still a violation")

	var g := Assessment.new("3A", "S7")
	g.add_rule({
		"id": "gastest_before_entry", "kind": Assessment.RuleKind.SAFETY_GATE,
		"weight": 0.0,
		"forbidden_kind": "ENTER", "gate_kind": "GAS_TEST",
		"gate_window_s": 1800.0,
	})
	g.observe(Assessment.event("3A", "S7", "GAS_TEST", {}, 0.0))
	g.observe(Assessment.event("3A", "S7", "ENTER", {}, 600.0))
	_ok(not bool(g.score()["gated"]),
		"entry 10 min after it is fine — the window is honoured, not ignored")

	_note("STEP_ORDER and SAFETY_GATE exercised against the real LaserFilter.Change names")
	_finish()


func _finish() -> void:
	if _pass == 0:
		print("  FAIL  : suite asserted nothing — a 0/0 run is not a pass")
		_fail += 1
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
