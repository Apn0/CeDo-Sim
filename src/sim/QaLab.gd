extends RefCounted
class_name QaLab
## The QA bench — samples of banked granulaat go in, graded results come out
## AFTER A DELAY. That delay is the entire point of this class.
##
## WHY THE DELAY IS THE PRODUCT
## ---------------------------
## MfiProxy is explicit that it is an INSTANTANEOUS soft-sensor and that "a real
## MFI is a 10-minute bench test on a granulaat sample" (MfiProxy.gd:4-5). The
## sim had the proxy but not the wait. The wait is the skill being trained:
## the proxy says one thing, the bench result lands ten minutes later, and by
## then the line has banked several hundred more kg. Hold, release, or regrade?
##
## So: the verdict is computed AT SUBMIT and frozen. Only the REVEAL is delayed.
## That is what makes a QA sample a lagging indicator the operator must reason
## about, and it is exactly what Assessment's QUANTITY_ESCAPED rule meters —
## kilograms banked between the verdict existing and the operator acting on it.
##
## CLOCK CHOICE (deliberate — do not "fix" this to SimTick)
## -------------------------------------------------------
## Driven from LineFlow.tick(), NOT SimTick.sim_tick. SimTick runs with
## process_mode = PROCESS_MODE_ALWAYS (SimTick.gd:41), so it keeps ticking
## through a pause menu and a bench sample would resolve while the player sits
## in the settings screen. LineFlow.tick() also happens to be the same clock
## that produced the material being graded, and bench_delay_s is expressed on
## the same axis as ProcessModel.WASH_RESIDENCE_S = 600.0 (ProcessModel.gd:145)
## and EXTRUDER_RESIDENCE_S = 300.0 (:146) — one coherent process-time axis.
##
## If a future requirement genuinely needs the bench to run through a pause, the
## change is: subscribe to SimTick.sim_tick and STOP calling tick() from
## LineFlow — never both, or every sample resolves at double rate.
##
## LEDGER SAFETY
## -------------
## Non-destructive by default: `destructive = false` grades a duplicate_batch()
## (MaterialBatch.gd:97-98) and the plant's mass ledger never sees it. Turning
## `destructive` on makes the assay consume real mass and is a FOUR-place edit
## in LineFlow (declare the counter, subtract it in ledger_residual(), subtract
## it in _update_label(), zero it in reset_shift_telemetry()) — skip any one and
## the conservation harness goes red. Left off until someone needs it.

signal sample_submitted(sample: Dictionary)
signal sample_ready(result: Dictionary)

const SCHEMA_VERSION : int = 1

## 10 minutes, on the same axis as ProcessModel's residence times.
const DEFAULT_BENCH_DELAY_S : float = 600.0
## 25 g — bench-test charge scale. ISO 1133's 2.16 kg test weight is folded into
## MfiProxy.MFI_GAIN (MfiProxy.gd:41), not used as a sample mass.
const SAMPLE_KG : float = 0.025
const MAX_LOG   : int   = 64

const VERDICT_ACCEPT  : String = "ACCEPT"
const VERDICT_REGRADE : String = "REGRADE"
const VERDICT_REJECT  : String = "REJECT"

var line_id       : String = "3C"
var session_id    : String = ""
var spec          : QaSpec = null
var bench_delay_s : float  = DEFAULT_BENCH_DELAY_S
var time_scale    : float  = 1.0
var destructive   : bool   = false

var _bus        : Node  = null
var _sim_time_s : float = 0.0
var _seq        : int   = 0
var _pending    : Array = []
var _ready_q    : Array = []
var _log        : Array = []
var _by_id      : Dictionary = {}
var _n_submitted : int = 0
var _n_resolved  : int = 0
var _n_accept    : int = 0
var _n_regrade   : int = 0
var _n_reject    : int = 0


func _init(line: String = "3C", session: String = "", sp: QaSpec = null) -> void:
	line_id = line
	session_id = session
	spec = sp if sp != null else QaSpec.default_ldpe()


func set_bus(bus: Node) -> void:
	_bus = bus


func set_spec(sp: QaSpec) -> void:
	if sp != null:
		spec = sp


func set_bench_delay_s(seconds: float) -> void:
	bench_delay_s = maxf(0.0, seconds)


func set_time_scale(scale: float) -> void:
	time_scale = maxf(0.0001, scale)


func set_session(line: String, session: String) -> void:
	line_id = line
	session_id = session


# ── the two calls that matter ────────────────────────────────────────────────

## Take a sample and start the bench clock. Returns the sample id, or -1 if
## there was nothing to sample.
##
## `source` carries the melt telemetry that is NOT on MaterialBatch — see
## _snapshot(). Callers MUST pass NAN (never 0.0) for any unavailable reading.
func submit_sample(batch: MaterialBatch, source: Dictionary = {}) -> int:
	if batch == null or batch.is_empty():
		return -1
	_seq += 1
	var graded : MaterialBatch = batch.split_mass(SAMPLE_KG) if destructive else batch.duplicate_batch()
	var snap := _snapshot(graded, source, _seq)
	_pending.push_back({
		"sample_id": _seq,
		"ready_at_s": _sim_time_s + bench_delay_s / time_scale,
		"snap": snap,
	})
	_n_submitted += 1
	sample_submitted.emit(snap)
	_emit_bus("qa_sample_submitted", snap)
	return _seq


## Advance the bench clock. Returns how many results resolved this tick.
func tick(delta: float) -> int:
	if delta <= 0.0:
		return 0
	_sim_time_s += delta
	var resolved := 0
	# Backwards so remove_at() cannot skip an element.
	for i in range(_pending.size() - 1, -1, -1):
		var p : Dictionary = _pending[i]
		if float(p["ready_at_s"]) > _sim_time_s:
			continue
		var res : Dictionary = p["snap"]
		_pending.remove_at(i)
		_by_id[int(res["sample_id"])] = res
		_log.push_front(res)
		if _log.size() > MAX_LOG:
			_log.resize(MAX_LOG)
		_ready_q.push_back(res)
		_n_resolved += 1
		match String(res["verdict"]):
			VERDICT_ACCEPT:  _n_accept += 1
			VERDICT_REGRADE: _n_regrade += 1
			VERDICT_REJECT:  _n_reject += 1
		sample_ready.emit(res)
		_emit_bus("qa_sample_ready", res)
		if String(res["verdict"]) == VERDICT_REJECT:
			_raise_alarm(res)
		resolved += 1
	return resolved


# ── snapshot ─────────────────────────────────────────────────────────────────

## Freeze everything the verdict depends on, at submit time.
func _snapshot(graded: MaterialBatch, source: Dictionary, sid: int) -> Dictionary:
	var mfi : float = float(source.get("mfi", NAN))
	var verdict : Dictionary = spec.evaluate(graded, mfi)

	var snap : Dictionary = graded.to_dict()
	# MaterialBatch.to_dict() hands back the LIVE composition dict by reference
	# (MaterialBatch.gd:222-224). Two snapshots of one batch would alias and
	# mutate together, so take our own copy.
	snap["composition"] = graded.composition.duplicate()

	snap["schema_version"] = SCHEMA_VERSION
	snap["sample_id"] = sid
	snap["line_id"] = line_id
	snap["session_id"] = session_id
	snap["source_key"] = String(source.get("source_key", ""))
	snap["source_id"] = String(source.get("source_id", ""))
	snap["operator"] = String(source.get("operator", ""))
	snap["submitted_at_s"] = _sim_time_s
	snap["ready_at_s"] = _sim_time_s + bench_delay_s / time_scale
	snap["bench_delay_s"] = bench_delay_s

	snap["moisture_pct"] = graded.moisture_pct()
	snap["contam_pct"] = graded.contam_pct()
	snap["purity_pct"] = graded.purity_pct()
	snap["ldpe_fraction"] = graded.ldpe_fraction()
	snap["polymer_kg"] = graded.polymer_kg()
	snap["quality_grade"] = graded.quality_grade()
	snap["bulk_density"] = graded.bulk_density()

	# polymer_kg() clamps at 0 (MaterialBatch.gd:70-71), which hides an
	# over-subscribed batch where water + dirt exceed total mass. For a QA layer
	# that is precisely the corruption worth seeing, so keep the raw figure too.
	snap["polymer_kg_raw"] = graded.mass_kg - graded.water_kg - graded.contaminant_kg
	snap["batch_consistent"] = snap["polymer_kg_raw"] >= -1.0e-6

	snap["mfi"] = mfi
	snap["melt_temp_c"] = float(source.get("melt_temp_c", NAN))
	snap["die_bar"] = float(source.get("die_bar", NAN))
	snap["thru_kg_s"] = float(source.get("thru_kg_s", NAN))

	snap["spec_id"] = String(verdict["spec_id"])
	snap["verdict"] = String(verdict["verdict"])
	snap["reasons"] = (verdict["reasons"] as Array).duplicate()
	snap["checks"] = (verdict["checks"] as Dictionary).duplicate()
	return snap


# ── queries ──────────────────────────────────────────────────────────────────

func pending_count() -> int:
	return _pending.size()


func pending() -> Array:
	var out : Array = []
	for p in _pending:
		var snap : Dictionary = p["snap"]
		out.append({
			"sample_id": int(p["sample_id"]),
			"source_key": String(snap.get("source_key", "")),
			"submitted_at_s": float(snap.get("submitted_at_s", 0.0)),
			"ready_at_s": float(p["ready_at_s"]),
			"remaining_s": maxf(0.0, float(p["ready_at_s"]) - _sim_time_s),
		})
	return out


func remaining_s(sample_id: int) -> float:
	for p in _pending:
		if int(p["sample_id"]) == sample_id:
			return maxf(0.0, float(p["ready_at_s"]) - _sim_time_s)
	return -1.0


## Pull path for a consumer that would rather poll than connect to sample_ready.
func drain_ready() -> Array:
	var out := _ready_q.duplicate()
	_ready_q.clear()
	return out


func result(sample_id: int) -> Dictionary:
	return _by_id.get(sample_id, {})


func log_rows(limit: int = 12) -> Array:
	return _log.slice(0, maxi(0, limit))


func stats() -> Dictionary:
	return {
		"submitted": _n_submitted,
		"resolved": _n_resolved,
		"pending": _pending.size(),
		"accept": _n_accept,
		"regrade": _n_regrade,
		"reject": _n_reject,
	}


func lab_time_s() -> float:
	return _sim_time_s


func cancel(sample_id: int) -> bool:
	for i in range(_pending.size()):
		if int(_pending[i]["sample_id"]) == sample_id:
			_pending.remove_at(i)
			return true
	return false


## New shift: clear the log and counters but KEEP anything still on the bench —
## a sample submitted before the handover is still physically in the machine.
## Mirrors the #218 rule that a rebuild must not reset shift state
## (LineFlow.gd:249-252).
func reset_shift() -> void:
	_log.clear()
	_ready_q.clear()
	_by_id.clear()
	_n_submitted = 0
	_n_resolved = 0
	_n_accept = 0
	_n_regrade = 0
	_n_reject = 0


func to_dict() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"line_id": line_id,
		"session_id": session_id,
		"spec_id": spec.spec_id if spec != null else "",
		"bench_delay_s": bench_delay_s,
		"time_scale": time_scale,
		"destructive": destructive,
		"lab_time_s": _sim_time_s,
		"stats": stats(),
	}


# ── bus ──────────────────────────────────────────────────────────────────────

## Defensive shape used everywhere in this project (LineFlow.gd:1828,
## QualityAnalysisBench.gd:123-124) — the bus may legitimately be absent in a
## headless suite.
func _emit_bus(event_name: String, data: Dictionary) -> void:
	if _bus == null:
		return
	if _bus.has_signal("scada_event"):
		_bus.emit_signal("scada_event", line_id, event_name, data)


func _raise_alarm(res: Dictionary) -> void:
	if _bus == null:
		return
	if _bus.has_signal("machine_alarm_raised"):
		_bus.emit_signal("machine_alarm_raised", String(res.get("source_key", line_id)),
			"QA-REJECT", 2)
	if _bus.has_signal("scanner_banner"):
		_bus.emit_signal("scanner_banner",
			"LAB %s\nmonster %d — %s" % [String(res["verdict"]), int(res["sample_id"]),
			", ".join(res.get("reasons", []) as Array)], true)
