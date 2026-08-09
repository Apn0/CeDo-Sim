extends RefCounted
class_name QaSpec
## Product spec for the graded quality-analysis loop — the thing a lab result is
## judged AGAINST. Pure data + pure functions: no scene, no clock, no signals.
##
## RULE 1 COMPLIANCE (CLAUDE.md "no build without docs"). Every limit below
## carries an explicit `confidence` in the same vocabulary TagMap uses
## (TagMap.gd:470-479): "certain" | "probable" | "needs-operator". Only ONE of
## these numbers is operator-sourced today:
##
##   * moisture_max_pct 0.5  — "probable". ProcessModel.gd:104 sets
##     FINAL_MOISTURE_PCT = 0.3 with the comment "granulaat out ~= 0 (operator:
##     0.1-0.5%, often less)". 0.5 is the top of that stated operator band.
##
## Everything else is a PLACEHOLDER and says so. The mfi band is carried
## forward verbatim from the magic numbers already in
## QualityAnalysisTerminal.gd:194 (`v < 0.4 or v > 3.5`) — deliberately, because
## carrying a stub forward WITH the label that says it is a stub is the Rule-1
## move. Inventing prettier, more "realistic" numbers is not: it would look
## authoritative and be fiction.
##
## NOTE those terminal magic numbers are already inconsistent with MfiProxy's
## own MFI_VIS_LOW/HIGH of 0.2/2.5 (MfiProxy.gd:58-59) — but those are DISPLAY
## normalisation bounds, not a product spec, so neither is evidence for the
## other. The operator has to settle it. Until then `needs_operator_count()`
## reports how many limits are still guesses and the scorecard prints it.
##
## Verdict composition: each check returns a Grade ordinal and the batch verdict
## is the WORST of them (maxi composes because ACCEPT < REGRADE < REJECT).

enum Grade { ACCEPT = 0, REGRADE = 1, REJECT = 2 }

const GRADE_NAMES : Array[String] = ["ACCEPT", "REGRADE", "REJECT"]

## Confidence vocabulary, mirrored from TagMap.gd:470-479 so one grep finds
## every unproven number in the project.
const CONF_CERTAIN        : String = "certain"
const CONF_PROBABLE       : String = "probable"
const CONF_NEEDS_OPERATOR : String = "needs-operator"

const DEFAULT_SPEC_PATH : String = "res://src/data/plant/qa_spec_ldpe.json"

var spec_id : String = "LDPE-REGRIND-3C"

# ── ACCEPT band / REJECT thresholds ──────────────────────────────────────────
# Between the two lies REGRADE: off-spec for prime sale, still sellable down.
var mfi_min             : float = 0.4
var mfi_max             : float = 3.5
var mfi_reject_min      : float = 0.2
var mfi_reject_max      : float = 5.0
var moisture_max_pct    : float = 0.5
var moisture_reject_pct : float = 1.0
var contam_max_pct      : float = 0.5
var contam_reject_pct   : float = 2.0
var ldpe_min_fraction   : float = 0.95
var ldpe_reject_fraction: float = 0.85

## limit name -> {"confidence": String, "source": String}
var provenance : Dictionary = {}


func _init(d: Dictionary = {}) -> void:
	if not d.is_empty():
		_apply(d)


## The shipped default. Numbers and their provenance live together so a caller
## can never read one without being able to read the other.
static func default_ldpe() -> QaSpec:
	return QaSpec.new({
		"spec_id": "LDPE-REGRIND-3C",
		"moisture_max_pct": {
			"v": 0.5, "confidence": CONF_PROBABLE,
			"source": "ProcessModel.gd:104 — operator band 0.1-0.5%, top of band",
		},
		"moisture_reject_pct": {
			"v": 1.0, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — 2x the accept ceiling, not operator-stated",
		},
		"mfi_min": {
			"v": 0.4, "confidence": CONF_NEEDS_OPERATOR,
			"source": "carried from QualityAnalysisTerminal.gd:194 stub",
		},
		"mfi_max": {
			"v": 3.5, "confidence": CONF_NEEDS_OPERATOR,
			"source": "carried from QualityAnalysisTerminal.gd:194 stub",
		},
		"mfi_reject_min": {
			"v": 0.2, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — MfiProxy.gd:58 display floor, NOT a spec",
		},
		"mfi_reject_max": {
			"v": 5.0, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — no operator source",
		},
		"contam_max_pct": {
			"v": 0.5, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — no operator source",
		},
		"contam_reject_pct": {
			"v": 2.0, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — no operator source",
		},
		"ldpe_min_fraction": {
			"v": 0.95, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — no operator source",
		},
		"ldpe_reject_fraction": {
			"v": 0.85, "confidence": CONF_NEEDS_OPERATOR,
			"source": "placeholder — no operator source",
		},
	})


static func from_dict(d: Dictionary) -> QaSpec:
	return QaSpec.new(d)


## Loads an operator-authored spec. Falls back to default_ldpe() when the file
## is absent or malformed — never to silence, because a spec that failed to load
## and a spec that says nothing look identical downstream.
static func from_json(path: String = DEFAULT_SPEC_PATH) -> QaSpec:
	if not FileAccess.file_exists(path):
		return default_ldpe()
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return default_ldpe()
	var parsed : Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return default_ldpe()
	return QaSpec.new(parsed as Dictionary)


## Accepts BOTH shapes per key so a hand-edited file stays readable:
##   "mfi_min": 0.4                                  (bare number)
##   "mfi_min": {"v": 0.4, "confidence": "...", ...} (number + provenance)
func _apply(d: Dictionary) -> void:
	if d.has("spec_id"):
		spec_id = String(d["spec_id"])
	for key in [
		"mfi_min", "mfi_max", "mfi_reject_min", "mfi_reject_max",
		"moisture_max_pct", "moisture_reject_pct",
		"contam_max_pct", "contam_reject_pct",
		"ldpe_min_fraction", "ldpe_reject_fraction",
	]:
		if not d.has(key):
			continue
		var raw : Variant = d[key]
		if typeof(raw) == TYPE_DICTIONARY:
			var sub : Dictionary = raw
			set(key, float(sub.get("v", get(key))))
			provenance[key] = {
				"confidence": String(sub.get("confidence", CONF_NEEDS_OPERATOR)),
				"source": String(sub.get("source", "")),
			}
		else:
			set(key, float(raw))
			provenance[key] = {"confidence": CONF_NEEDS_OPERATOR, "source": ""}


## How many limits are still guesses. The scorecard prints this so nobody mistakes
## a graded run for a calibrated one.
func needs_operator_count() -> int:
	var n := 0
	for key in provenance:
		if String((provenance[key] as Dictionary).get("confidence", "")) == CONF_NEEDS_OPERATOR:
			n += 1
	return n


func unproven_limits() -> Array:
	var out : Array = []
	for key in provenance:
		if String((provenance[key] as Dictionary).get("confidence", "")) == CONF_NEEDS_OPERATOR:
			out.append(String(key))
	out.sort()
	return out


func confidence_of(limit: String) -> String:
	if not provenance.has(limit):
		return CONF_NEEDS_OPERATOR
	return String((provenance[limit] as Dictionary).get("confidence", CONF_NEEDS_OPERATOR))


# ── individual checks ────────────────────────────────────────────────────────

## MFI comes from MfiProxy.predicted_mfi, which STARTS at 0.0 (MfiProxy.gd:64)
## and whose flow_label() maps 0.0 to "no flow" (:127-134) — so a proxy that was
## never updated is indistinguishable from a genuinely stalled line. Worse,
## LineFlow only writes nd["mfi_value"] inside `if ex != null` (LineFlow.gd:2360
## guarding :2372), so an extruder node with no ExtruderScrew reports a
## plausible 0.00 forever. Callers MUST pass NAN, not 0.0, when the value is
## unavailable — and missing data can never grade ACCEPT.
func check_mfi(mfi: float) -> int:
	if is_nan(mfi):
		return Grade.REGRADE
	if mfi < mfi_reject_min or mfi > mfi_reject_max:
		return Grade.REJECT
	if mfi < mfi_min or mfi > mfi_max:
		return Grade.REGRADE
	return Grade.ACCEPT


func check_moisture(pct: float) -> int:
	if is_nan(pct):
		return Grade.REGRADE
	if pct > moisture_reject_pct:
		return Grade.REJECT
	if pct > moisture_max_pct:
		return Grade.REGRADE
	return Grade.ACCEPT


func check_contam(pct: float) -> int:
	if is_nan(pct):
		return Grade.REGRADE
	if pct > contam_reject_pct:
		return Grade.REJECT
	if pct > contam_max_pct:
		return Grade.REGRADE
	return Grade.ACCEPT


func check_polymer(ldpe_frac: float) -> int:
	if is_nan(ldpe_frac):
		return Grade.REGRADE
	if ldpe_frac < ldpe_reject_fraction:
		return Grade.REJECT
	if ldpe_frac < ldpe_min_fraction:
		return Grade.REGRADE
	return Grade.ACCEPT


## The whole verdict. `mfi` is passed separately because it is NOT a property of
## the material ledger — it is melt telemetry off MfiProxy, and MaterialBatch
## has no concept of it.
##
## These four accessors are the COMPLETE set of MaterialBatch inputs to a
## verdict: moisture_pct() :74-75, contam_pct() :78-79, ldpe_fraction() :66-67,
## and (advisory only, never graded) quality_grade() :89-95. All are pure.
func evaluate(batch: MaterialBatch, mfi: float) -> Dictionary:
	if batch == null:
		return {
			"verdict": GRADE_NAMES[Grade.REJECT],
			"reasons": ["no_batch"],
			"checks": {},
			"spec_id": spec_id,
		}
	var c_mfi := check_mfi(mfi)
	var c_moist := check_moisture(batch.moisture_pct())
	var c_contam := check_contam(batch.contam_pct())
	var c_poly := check_polymer(batch.ldpe_fraction())

	var worst : int = maxi(maxi(c_mfi, c_moist), maxi(c_contam, c_poly))
	var reasons : Array = []
	if is_nan(mfi):
		reasons.append("mfi_unavailable")
	elif c_mfi != Grade.ACCEPT:
		reasons.append("mfi_low" if mfi < mfi_min else "mfi_high")
	if c_moist != Grade.ACCEPT:
		reasons.append("moisture_high")
	if c_contam != Grade.ACCEPT:
		reasons.append("contam_high")
	if c_poly != Grade.ACCEPT:
		reasons.append("polymer_impure")

	return {
		"verdict": GRADE_NAMES[worst],
		"reasons": reasons,
		"checks": {
			"mfi": c_mfi,
			"moisture": c_moist,
			"contam": c_contam,
			"polymer": c_poly,
		},
		"spec_id": spec_id,
	}


func to_dict() -> Dictionary:
	return {
		"spec_id": spec_id,
		"mfi_min": mfi_min,
		"mfi_max": mfi_max,
		"mfi_reject_min": mfi_reject_min,
		"mfi_reject_max": mfi_reject_max,
		"moisture_max_pct": moisture_max_pct,
		"moisture_reject_pct": moisture_reject_pct,
		"contam_max_pct": contam_max_pct,
		"contam_reject_pct": contam_reject_pct,
		"ldpe_min_fraction": ldpe_min_fraction,
		"ldpe_reject_fraction": ldpe_reject_fraction,
		"provenance": provenance.duplicate(true),
		"needs_operator": needs_operator_count(),
	}
