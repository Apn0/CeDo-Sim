extends RefCounted
class_name Assessment
## Generic training-assessment rule engine. Knows NOTHING about quality analysis,
## laser filters, or any other scenario — it ingests event envelopes and scores
## rules. That is deliberate: the graded QA loop is the first consumer, and the
## laser-filter change procedure (LaserFilter.gd already encodes all 22 steps
## from PROD-SWI-074) must reuse this class unchanged via STEP_ORDER +
## SAFETY_GATE rather than growing a second scoring system.
##
## KEYED ON line_id + session_id, ENFORCED AT INGEST
## ------------------------------------------------
## Every event must match both or it is dropped AND COUNTED. The counts are
## surfaced in score()["counts"], which is the non-vacuity handle: a suite can
## assert events > 0 and dropped_* == 0 rather than merely "not null". This is
## the exact defect class CLAUDE.md warns about — npc-05 printed 31/31 while
## moving 0.00 kg, and test_tag_snapshot was bitten by a "non-null" check that
## turned out to be a tautology.
##
## Retrofitting these keys later would touch every rule, every recording and
## every chart, which is why they are here from the first commit even though
## nothing multi-line ships yet.
##
## ANTI-VACUOUS SCORING
## --------------------
## A rule that never armed reports status "n/a" and is EXCLUDED from the
## weighted mean. A session where nothing happened therefore scores "n/a", not
## 100%. A trainee cannot pass by doing nothing.

enum RuleKind { DECISION_CORRECT, LATENCY, QUANTITY_ESCAPED, STEP_ORDER, SAFETY_GATE }

const SCHEMA_VERSION : int = 1

var line_id    : String = ""
var session_id : String = ""

var _rules   : Array = []
var _state   : Dictionary = {}    # rule_id -> per-kind working state
var _findings : Array = []
var _clock_s : float = 0.0
var _events  : int = 0
var _dropped_line    : int = 0
var _dropped_session : int = 0


func _init(line: String = "", session: String = "") -> void:
	line_id = line
	session_id = session


func reset(line: String, session: String) -> void:
	line_id = line
	session_id = session
	_state.clear()
	_findings.clear()
	_clock_s = 0.0
	_events = 0
	_dropped_line = 0
	_dropped_session = 0
	for r in _rules:
		_init_state(r)


## Envelope constructor. Static so producers do not need an instance.
static func event(line: String, session: String, kind: String,
		payload: Dictionary, at_s: float) -> Dictionary:
	return {
		"line_id": line,
		"session_id": session,
		"kind": kind,
		"at_s": at_s,
		"payload": payload,
	}


func add_rule(rule: Dictionary) -> bool:
	if not rule.has("id") or not rule.has("kind"):
		return false
	var rid := String(rule["id"])
	for r in _rules:
		if String(r["id"]) == rid:
			return false
	var copy := rule.duplicate(true)
	copy["weight"] = float(copy.get("weight", 0.0))
	_rules.append(copy)
	_init_state(copy)
	return true


func rules() -> Array:
	return _rules.duplicate(true)


func clock_s() -> float:
	return _clock_s


func findings() -> Array:
	return _findings.duplicate(true)


func tick(delta: float) -> void:
	if delta <= 0.0:
		return
	_clock_s += delta
	for r in _rules:
		if int(r["kind"]) == RuleKind.DECISION_CORRECT:
			_expire_decisions(r)
		elif int(r["kind"]) == RuleKind.LATENCY:
			_expire_latency(r)


## Ingest one envelope. Returns false when it was dropped.
func observe(ev: Dictionary) -> bool:
	if String(ev.get("line_id", "")) != line_id:
		_dropped_line += 1
		return false
	if String(ev.get("session_id", "")) != session_id:
		_dropped_session += 1
		return false
	_events += 1
	var kind := String(ev.get("kind", ""))
	var payload : Dictionary = ev.get("payload", {})
	var at_s := float(ev.get("at_s", _clock_s))
	for r in _rules:
		match int(r["kind"]):
			RuleKind.DECISION_CORRECT: _on_decision(r, kind, payload, at_s)
			RuleKind.LATENCY:          _on_latency(r, kind, payload, at_s)
			RuleKind.QUANTITY_ESCAPED: _on_escaped(r, kind, payload, at_s)
			RuleKind.STEP_ORDER:       _on_step_order(r, kind, at_s)
			RuleKind.SAFETY_GATE:      _on_safety(r, kind, payload, at_s)
	return true


# ── state ────────────────────────────────────────────────────────────────────

func _init_state(r: Dictionary) -> void:
	var rid := String(r["id"])
	match int(r["kind"]):
		RuleKind.DECISION_CORRECT:
			_state[rid] = {"open": {}, "correct": 0, "incorrect": 0, "missed": 0}
		RuleKind.LATENCY:
			_state[rid] = {"open": {}, "samples": [], "expired": 0}
		RuleKind.QUANTITY_ESCAPED:
			_state[rid] = {"armed": false, "armed_at_s": -1.0, "kg": 0.0, "episodes": 0}
		RuleKind.STEP_ORDER:
			_state[rid] = {"idx": 0, "broken": false, "best": 0}
		RuleKind.SAFETY_GATE:
			_state[rid] = {"gate_ok_at_s": -1.0e12, "violations": 0, "checks": 0}


## Does a payload match every key/value in `expect`? A non-dictionary `expect`
## (typically absent) matches everything. A key the payload does not carry is a
## NON-match: a rule that asks for {"action": "hold"} must not fire on an event
## that never mentioned an action.
func _matches(payload: Dictionary, expect: Variant) -> bool:
	if typeof(expect) != TYPE_DICTIONARY:
		return true
	for k in (expect as Dictionary):
		if not payload.has(k):
			return false
		if String(payload[k]) != String((expect as Dictionary)[k]):
			return false
	return true


func _finding(rule_id: String, at_s: float, status: String, detail: String) -> void:
	_findings.append({"rule_id": rule_id, "at_s": at_s, "status": status, "detail": detail})


# ── 1) DECISION_CORRECT ──────────────────────────────────────────────────────

func _on_decision(r: Dictionary, kind: String, payload: Dictionary, at_s: float) -> void:
	var st : Dictionary = _state[String(r["id"])]
	var match_field := String(r.get("match_field", "sample_id"))
	if kind == String(r.get("trigger_kind", "")):
		var want_key := String(payload.get(String(r.get("trigger_field", "verdict")), ""))
		var map : Dictionary = r.get("map", {})
		if not map.has(want_key):
			return
		(st["open"] as Dictionary)[String(payload.get(match_field, ""))] = {
			"want": String(map[want_key]), "at_s": at_s,
		}
	elif kind == String(r.get("decision_kind", "")):
		var key := String(payload.get(match_field, ""))
		var open : Dictionary = st["open"]
		if not open.has(key):
			return
		var rec : Dictionary = open[key]
		var got := String(payload.get(String(r.get("decision_field", "action")), ""))
		open.erase(key)
		if got == String(rec["want"]):
			st["correct"] = int(st["correct"]) + 1
			_finding(String(r["id"]), at_s, "correct", "%s -> %s" % [key, got])
		else:
			st["incorrect"] = int(st["incorrect"]) + 1
			_finding(String(r["id"]), at_s, "incorrect",
				"%s -> %s (expected %s)" % [key, got, String(rec["want"])])


func _expire_decisions(r: Dictionary) -> void:
	var st : Dictionary = _state[String(r["id"])]
	var window := float(r.get("window_s", 300.0))
	var open : Dictionary = st["open"]
	for key in open.keys():
		if _clock_s - float((open[key] as Dictionary)["at_s"]) < window:
			continue
		open.erase(key)
		st["missed"] = int(st["missed"]) + 1
		_finding(String(r["id"]), _clock_s, "missed", "%s — no decision inside %.0f s" % [key, window])


# ── 2) LATENCY ───────────────────────────────────────────────────────────────

func _on_latency(r: Dictionary, kind: String, payload: Dictionary, at_s: float) -> void:
	var st : Dictionary = _state[String(r["id"])]
	var match_field := String(r.get("match_field", "sample_id"))
	var key := String(payload.get(match_field, ""))
	if kind == String(r.get("start_kind", "")) and _matches(payload, r.get("start_when")):
		(st["open"] as Dictionary)[key] = at_s
	elif kind == String(r.get("stop_kind", "")) and _matches(payload, r.get("stop_when")):
		var open : Dictionary = st["open"]
		if not open.has(key):
			return
		var dt := at_s - float(open[key])
		open.erase(key)
		(st["samples"] as Array).append(dt)
		_finding(String(r["id"]), at_s, "measured", "%s took %.1f s" % [key, dt])


func _expire_latency(r: Dictionary) -> void:
	var st : Dictionary = _state[String(r["id"])]
	var fail_s := float(r.get("fail_s", 300.0))
	var open : Dictionary = st["open"]
	for key in open.keys():
		if _clock_s - float(open[key]) < fail_s:
			continue
		open.erase(key)
		st["expired"] = int(st["expired"]) + 1
		(st["samples"] as Array).append(fail_s)
		_finding(String(r["id"]), _clock_s, "expired", "%s never responded within %.0f s" % [key, fail_s])


# ── 3) QUANTITY_ESCAPED ──────────────────────────────────────────────────────
# The headline metric: kg of out-of-spec product banked between the lab verdict
# landing and the operator acting on it.

func _on_escaped(r: Dictionary, kind: String, payload: Dictionary, at_s: float) -> void:
	var st : Dictionary = _state[String(r["id"])]
	if kind == String(r.get("arm_kind", "")) and _matches(payload, r.get("arm_when")):
		if not bool(st["armed"]):
			st["armed"] = true
			st["armed_at_s"] = at_s
			st["episodes"] = int(st["episodes"]) + 1
	elif kind == String(r.get("disarm_kind", "")) and _matches(payload, r.get("disarm_when")):
		if bool(st["armed"]):
			st["armed"] = false
			_finding(String(r["id"]), at_s, "disarmed",
				"%.1f kg banked over %.1f s" % [float(st["kg"]), at_s - float(st["armed_at_s"])])
	elif kind == String(r.get("meter_kind", "")) and bool(st["armed"]):
		st["kg"] = float(st["kg"]) + float(payload.get(String(r.get("meter_field", "kg")), 0.0))


# ── 4) STEP_ORDER ────────────────────────────────────────────────────────────

func _on_step_order(r: Dictionary, kind: String, at_s: float) -> void:
	var st : Dictionary = _state[String(r["id"])]
	var seq : Array = r.get("sequence", [])
	if seq.is_empty() or bool(st["broken"]):
		return
	var idx := int(st["idx"])
	if idx < seq.size() and String((seq[idx] as Dictionary).get("kind", "")) == kind:
		st["idx"] = idx + 1
		st["best"] = maxi(int(st["best"]), idx + 1)
		return
	# Out-of-order only counts as a break in strict mode, and only for a kind
	# that is actually part of this sequence — unrelated traffic is ignored.
	if not bool(r.get("strict", false)):
		return
	for step in seq:
		if String((step as Dictionary).get("kind", "")) == kind:
			st["broken"] = true
			_finding(String(r["id"]), at_s, "out_of_order",
				"%s arrived at position %d" % [kind, idx])
			return


# ── 5) SAFETY_GATE ───────────────────────────────────────────────────────────
# A hard gate, not a weighted score. One violation zeroes the whole session.

func _on_safety(r: Dictionary, kind: String, payload: Dictionary, at_s: float) -> void:
	var st : Dictionary = _state[String(r["id"])]
	if kind == String(r.get("gate_kind", "")) and _matches(payload, r.get("gate_when")):
		st["gate_ok_at_s"] = at_s
		return
	if kind != String(r.get("forbidden_kind", "")) or not _matches(payload, r.get("forbidden_when")):
		return
	st["checks"] = int(st["checks"]) + 1
	if at_s - float(st["gate_ok_at_s"]) > float(r.get("gate_window_s", 120.0)):
		st["violations"] = int(st["violations"]) + 1
		_finding(String(r["id"]), at_s, "violation",
			"forbidden action without the gate satisfied within %.0f s"
				% float(r.get("gate_window_s", 120.0)))


# ── scoring ──────────────────────────────────────────────────────────────────

func score() -> Dictionary:
	var rows : Array = []
	var gated := false
	var wsum := 0.0
	var acc := 0.0
	for r in _rules:
		var row := _score_rule(r)
		rows.append(row)
		if bool(row.get("gate_tripped", false)):
			gated = true
		if String(row["status"]) == "n/a":
			continue
		var w := float(row["weight"])
		if w <= 0.0:
			continue
		wsum += w
		acc += w * float(row["pct"])
	var total : float = (acc / wsum) * 100.0 if wsum > 0.0 else 0.0
	return {
		"schema_version": SCHEMA_VERSION,
		"line_id": line_id,
		"session_id": session_id,
		"gated": gated,
		"total_pct": 0.0 if gated else total,
		"scored_weight": wsum,
		"rules": rows,
		"counts": {
			"events": _events,
			"dropped_wrong_line": _dropped_line,
			"dropped_wrong_session": _dropped_session,
		},
	}


func _score_rule(r: Dictionary) -> Dictionary:
	var rid := String(r["id"])
	var kind := int(r["kind"])
	var st : Dictionary = _state[rid]
	var row : Dictionary = {
		"id": rid, "kind": kind, "weight": float(r.get("weight", 0.0)),
		"status": "n/a", "value": 0.0, "target": 0.0, "pct": 0.0, "detail": "",
	}
	match kind:
		RuleKind.DECISION_CORRECT:
			var tot := int(st["correct"]) + int(st["incorrect"]) + int(st["missed"])
			if tot == 0:
				row["detail"] = "never triggered"
				return row
			row["status"] = "scored"
			row["value"] = float(st["correct"])
			row["target"] = float(tot)
			row["pct"] = float(st["correct"]) / float(tot)
			row["detail"] = "%d correct, %d wrong, %d missed" % [
				int(st["correct"]), int(st["incorrect"]), int(st["missed"])]
		RuleKind.LATENCY:
			var samples : Array = st["samples"]
			if samples.is_empty():
				row["detail"] = "never triggered"
				return row
			var sum := 0.0
			for s in samples:
				sum += float(s)
			var mean := sum / float(samples.size())
			var target := float(r.get("target_s", 60.0))
			var fail := float(r.get("fail_s", 300.0))
			row["status"] = "scored"
			row["value"] = mean
			row["target"] = target
			row["pct"] = clampf(inverse_lerp(fail, target, mean), 0.0, 1.0)
			row["detail"] = "mean %.1f s over %d response(s), %d expired" % [
				mean, samples.size(), int(st["expired"])]
		RuleKind.QUANTITY_ESCAPED:
			if int(st["episodes"]) == 0:
				row["detail"] = "never armed"
				return row
			var budget := maxf(0.0001, float(r.get("budget_kg", 250.0)))
			row["status"] = "scored"
			row["value"] = float(st["kg"])
			row["target"] = budget
			row["pct"] = clampf(1.0 - float(st["kg"]) / budget, 0.0, 1.0)
			row["detail"] = "%.1f kg escaped over %d episode(s), budget %.0f kg" % [
				float(st["kg"]), int(st["episodes"]), budget]
		RuleKind.STEP_ORDER:
			var seq : Array = r.get("sequence", [])
			if seq.is_empty() or int(st["best"]) == 0:
				row["detail"] = "never started"
				return row
			row["status"] = "scored"
			row["value"] = float(st["best"])
			row["target"] = float(seq.size())
			row["pct"] = clampf(float(st["best"]) / float(seq.size()), 0.0, 1.0)
			row["detail"] = "%d of %d steps in order%s" % [
				int(st["best"]), seq.size(), " (broken)" if bool(st["broken"]) else ""]
		RuleKind.SAFETY_GATE:
			if int(st["checks"]) == 0:
				row["detail"] = "never exercised"
				return row
			row["status"] = "scored"
			row["value"] = float(st["violations"])
			row["target"] = 0.0
			row["pct"] = 1.0 if int(st["violations"]) == 0 else 0.0
			row["gate_tripped"] = int(st["violations"]) > 0
			row["detail"] = "%d violation(s) over %d check(s)" % [
				int(st["violations"]), int(st["checks"])]
	return row


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"line_id": line_id,
		"session_id": session_id,
		"clock_s": _clock_s,
		"score": score(),
		"findings": findings(),
	}
