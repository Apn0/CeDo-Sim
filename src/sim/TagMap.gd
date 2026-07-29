extends RefCounted
class_name TagMap

## READ-ONLY bridge between the operator's REAL SCADA tag namespace and the sim.
##
## First slice of docs/DESIGN_hmi_tag_bridge_2026-07-22.md §8. This is the FIRST
## code consumer of src/data/plant/line3c_scada_tags.json (1056 tags exported
## from the operator's own 3c_tags.xlsx, 2026-07-04 — zero consumers before now).
##
## NOT AN AUTOLOAD, deliberately: an autoload boots before LineFlow / MainWorld
## exist, which is the live Walkie.gd:57 -> VoiceService bug class the design doc
## rejects (§5). Instantiate it where a LineFlow is already in hand:
##     var tm := TagMap.new()
##     var rows := tm.resolve_machine(id, line_flow.get_machine_info(id), ctx)
##
## NO WRITE PATH. Where a `setpoints/...` tag appears below it is the READBACK of
## an existing LineFlow setter, never a command channel. Four of the five control
## classes named in the design doc (§4a) still have no endpoint at all.
##
## CONSTRAINTS THIS FILE OBEYS
## ---------------------------
## * no-build-without-docs: every tag string is VERBATIM from the export and is
##   validated against it at load (see validation()); every row carries a `cite`
##   naming both sides. A tag with no simulated quantity behind it is ABSENT, not
##   guessed at. 112 of 1056 tags map today (10.6 %).
## * The equipment spine is the ONE place sim ids and real equipment numbers
##   already agree: Line3CDef code L3C.<n> == export segment scada/3c/info/<n>
##   (src/sim/Line3CDef.gd:59-96). UNITS below is that agreement, nothing more.
## * ADDRESSABILITY — RESOLVED. The 20 SCADA-aligned Line 3C units collapse onto
##   only 10 DISTINCT placeable ids (friction_sep x5, transport_screw x5,
##   mech_dryer x2, blower x2 + 6 singletons), and while LineFlow could only
##   address a machine by that id it returned the FIRST match, so ten of the
##   twenty units were unreachable and only one representative per id was mapped.
##   LineFlow now mints a per-instance key (LineFlow.gd _discover / _resolve) that
##   IS the l3c_code for a stamped Line 3C stage, so every unit is addressable by
##   its own plant tag. All 20 are mapped; use resolve_code(code, ...) rather than
##   resolve_machine(id, ...) — the latter is the legacy id-keyed path and still
##   reads whichever instance LineFlow's fallback returns.
##
## DELIBERATELY ABSENT CLASSES (979 tags). Reasons, so a later session cannot
## quietly invent them back:
##  * HISTORICAL — all 11 historicaldata/3c/* : no historian exists. LineFlow's
##    totals are live accumulators reset by reset_shift_telemetry (LineFlow.gd:326-338).
##  * OEE / AVAILABILITY / PERFORMANCE / QUALITY KPIs (12 under lines/3c): no OEE
##    or availability computation exists repo-wide; no planned-time, run-time or
##    reject-count model to divide. The reverse gap also holds — the export has no
##    performance/quality ACTUAL leaf, so LineFlow.granulaat_quality()
##    (LineFlow.gd:410) has no tag to bind to.
##  * */budgetted, */target : business targets entered in the MES.
##  * TIMER SETPOINTS (~250 setpoints + ~90 info leaves: em/leegdraaitijd,
##    starttijd, stoptijd, b*/t* start+stop times and their *bewaking, per-motor
##    aanlooptijd / uitlooptijd, every loopbewaking*/loopbewakingtijd): the sim has
##    ONE global stagger (PLCSequencer.stagger_s, PLCSequencer.gd:18) applied
##    uniformly. No per-unit start delay, run-up, run-down, run-empty, and no
##    run-monitoring (loopbewaking) alarm at all.
##  * LEVEL ALARM BANDS (niveauhoog/hooghoog/laag/laaglaag, every niveau*/alarm):
##    SiloLevelSensor has only HIGH/RESUME/OVERFLOW constants
##    (SiloLevelSensor.gd:51-53) and the quantity that does exist (buffer, kg) has
##    no modelled capacity to compare against.
##  * SiloLevelSensor.current_level_pct IS A DEAD SOURCE — it reads `level_pct`
##    off its silo (SiloLevelSensor.gd:88-94) and `level_pct` has ZERO producers
##    repo-wide, so it can only ever return 0.0. The design doc named it as a
##    candidate seed (§8); it is NOT adopted. All four niveau rows bind to
##    get_machine_info()["buffer"] (kg) instead and are flagged needs-operator
##    because no capacity exists to turn kg into %.
##  * niveau_enable INTERLOCKS (schroef_1/2/3_enable): no level-to-motor permit
##    exists; the only level governor acts on EDGE FLOW
##    (SiloLevelSensor.effective_feed_multiplier, :137-144) and is dead per above.
##  * draairichting (~40): rpm_pct is clamped 0..1 (LineFlow.gd:1506) and rotor rpm
##    is pct * nominal (:1536) — no signed direction.
##  * bsnelheidlangzaam / isnelheidlangzaam (~80): a second discrete speed step per
##    drive. The sim models one continuous 0..1 pct; the doc itself marks the b/i
##    meaning '[unsure]' (docs/plant/line3c_scada_tags.md:49). Guessing = invention.
##  * em/safety (21): the sim's only safety state is a LINE-GLOBAL e-stop
##    (LineFlow.gd:1648-1654). No per-unit safety chain, guard or door interlock.
##  * PER-MOTOR leaves on units whose motors the sim does not model as components.
##    Device names below are the export's own, re-verified verbatim 2026-07-27:
##      unit 3  — fqafvoerschroef1, fqafvoerschroef2, fqafvoerwalz,
##                fqpeddelwals1en2, motorafvoerschraper
##      unit 6  — hydrauliek, schroef 1, schroef 2, schroef 3
##      unit 11 — afvoerschraper, afvoerschroef, afvoerwals,
##                peddelwals 1_2_3_4, peddelwals 5_6_7_8, peddelwals 9_10
##                (all THREE paddle groups, not just 9_10)
##      unit 14l/14r — motorreinigingsschrapper, motorroterendeklep, plus
##                'fq_roterende_klep ' on 14l only (the trailing space is real)
##      unit 18 — motorroterroeras1, motorroterroeras2, motorventilator
##      setpoints-only watchdog pseudo-devices, e.g. unit 1 'loopbewaking roerwerk'
##                — implying a ROERWERK (agitator) on the dosing silo that
##                _default_components_for's 3 augers do not model at all.
##    _default_components_for gives these machines 1 or 4 generic components
##    (LineFlow.gd:1412-1459) against 6-10 real motors, and `amps` is PER-MACHINE
##    (LineFlow.gd:1599), never per motor. Which sim component is which named motor
##    is an operator question.
##  * KNOWN UNDER-MAPPING — unit 3 'intrekwals' (info + setpoints). This one is NOT
##    unmappable and is recorded so it is neither forgotten nor later invented with
##    a different target: sink_float matches LineFlow.gd:1422 on the substring
##    "sink", so it carries the same inlet/transport_1/transport_2/outlet components
##    unit 11 does, and unit 3's intrekwals is the same pull-in roller this file
##    already maps at unit 11 -> "inlet". Left out of THIS slice only to keep the
##    row count stable for the audit it was measured against; adding it is a
##    deliberate follow-up, and EXPECTED_ROWS must move with it.
##  * MEETING/TEMPERATUUR (14): one bulk MechDryerModel.temp_c (MechDryerModel.gd:7)
##    vs front+rear thermocouples per drum; the friction separators have no thermal
##    model at all. Binding two tags to one value would invent spatial resolution.
##  * MEETING/VIBRATIE (14): no vibration quantity exists. VibratingPivot.gd is a
##    visual animator, not a sensor.
##  * MEETING/OVERIG 6_6_maalmolen waterflow: mill matches only the shred arm
##    (MachineFlow.gd:365-366) so water_add == 0.0 — no water flow is simulated
##    there, unlike its two mapped siblings.
##  * LINE-6 EQUIPMENT IDENTITY: every meeting tag is named 6_<n> while sitting
##    under scada/3c (line3c_scada_tags.json "note";
##    docs/plant/line3c_scada_tags.md:7-11 flags it as open). The two mapped
##    meeting rows are flagged; no meeting tag is ASSERTED to be a 3C stage.
##  * SCADA UNITS WITH NO Line3CDef STAGE: info/20 + setpoints/20 (16) and
##    setpoints/7 (10). Line3CDef deliberately has no L3C.7/.8/.17/.20 — those tags
##    are sensors/valves/sumps, not machines on the HMI overview
##    (src/sim/Line3CDef.gd:21-22). Nothing to bind.
##  * EXTRUDER BACK-END: the sim's richest live models (ExtruderModel melt_temp /
##    screw_rpm / filter_loading_g / die_pressure_psi, CutterCompactor, MfiProxy,
##    LaserFilter) have NO tags in this export — it stops at unit 20 and
##    Line3CDef's 12 back-end stages carry RECONSTRUCTED codes
##    (src/sim/Line3CDef.gd:84-95). Real simulation, no real tag: the reverse gap.
##    Absent until the operator exports that HMI page.

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")
const MachineFlowScript = preload("res://src/sim/MachineFlow.gd")
const ProcessModelScript = preload("res://src/sim/ProcessModel.gd")

## The operator's export. Slash-hierarchical strings, NOT a tree — hierarchy
## exists only inside the strings, so any consumer must split("/") itself.
const EXPORT_PATH : String = "res://src/data/plant/line3c_scada_tags.json"

## Guards accidental edits to the table below: a row added or dropped without
## updating this number fails validation loudly instead of silently.
## 77 -> 112: the ten previously-unaddressable units (4r, 5r, 9l, 9r, 10l, 10r,
## 12, 13, 14r, 19) each gained em/status + em/hand + em/snelheid, and the five
## whose machine-level stroom leaf is the SAME device class as an already-approved
## sibling (4r/9l/9r/13 softstarterfrictiewasser, 14r softstarterdroger1) gained
## that too. 30 + 5 = 35.
const EXPECTED_ROWS : int = 112

## How a row turns a get_machine_info() snapshot (+ line context) into a value.
enum Kind {
	MACHINE_FIELD,      ## arg = get_machine_info key, passed through unchanged
	MACHINE_SPEED,      ## spin * rpm_pct * max_rpm
	COMPONENT_STATUS,   ## powered AND components[arg] > 0.0
	COMPONENT_RPM,      ## components[arg] * comp_max_rpm[arg]  (RPM — SCADA leaf is Hz)
	COMPONENT_PCT,      ## components[arg] 0..1 — READBACK of set_machine_component_pct
	ESTOP_ALARM,        ## estop_fault_id() == this machine key
	WATERFLOW,          ## MachineFlow water_add * thru  (kg/s process water taken on)
	LINE_CONST,         ## a Line3CDef static constant
	LINE_CTX,           ## arg = key the caller supplies in the line context dict
}

## SCADA unit segment -> [Line3CDef code, placeable id, Line3CDef.gd line].
## This table IS the equipment spine — transcribed, never derived.
## All 20 wash-line units are listed. Each one's em/status leaf was verified
## verbatim in the export, and each is now addressable by its OWN l3c_code
## (LineFlow mints the code as that node's per-instance key), so the ten units
## that used to collapse onto a mapped sibling are no longer vacuous duplicates.
## The placeable-id column stays because the legacy id-keyed resolve_machine()
## path still needs it; resolve_code() does not.
const UNITS : Dictionary = {
	"1":   ["L3C.1",   "doseersilo",          60],
	"3":   ["L3C.3",   "sink_float",          61],
	"4l":  ["L3C.4L",  "friction_sep",        62],
	"4r":  ["L3C.4R",  "friction_sep",        63],
	"5l":  ["L3C.5L",  "transport_screw",     64],
	"5r":  ["L3C.5R",  "transport_screw",     65],
	"6":   ["L3C.6",   "mill",                66],
	"9l":  ["L3C.9L",  "friction_sep",        67],
	"9r":  ["L3C.9R",  "friction_sep",        68],
	"10l": ["L3C.10L", "transport_screw",     69],
	"10r": ["L3C.10R", "transport_screw",     70],
	"11":  ["L3C.11",  "flotation_tank_wide", 71],
	"12":  ["L3C.12",  "transport_screw",     72],
	"13":  ["L3C.13",  "friction_sep",        73],
	"14l": ["L3C.14L", "mech_dryer",          77],
	"14r": ["L3C.14R", "mech_dryer",          78],
	"15":  ["L3C.15",  "blower",              79],
	"16":  ["L3C.16",  "plasmaq",             80],
	"18":  ["L3C.18",  "silo",                81],
	"19":  ["L3C.19",  "blower",              82],
}

## Line-context keys resolve_line() needs from the caller. Missing key -> the row
## resolves to null and is reported unresolved, never defaulted to a plausible 0.
const LINE_CTX_KEYS : Array = ["tail_thru_kg_h", "gran_mass_kg", "line_status"]
## Machine-context key resolve_machine() needs for the alarm rows.
const MACHINE_CTX_KEYS : Array = ["estop_fault_id"]

# ── cite fragments ────────────────────────────────────────────────────────────
const TAG_SRC : String = "TAG src/data/plant/line3c_scada_tags.json tags[] (verbatim, validated at load)"
const S_POWERED : String = "LineFlow.gd:1593 get_machine_info[\"powered\"]"
const S_HAND : String = "LineFlow.gd:1600 hand_mode (setter :1491-1496)"
const S_MANUAL : String = "LineFlow.gd:1601 manual_on readback of set_machine_manual_on :1498-1501 (drives powered at :1814-1816)"
const S_SPEED : String = "LineFlow.gd:1602-1603 rpm_pct*max_rpm gated by :1592 spin (SPIN_UP_S :47; spin's target is 1/0 regardless of rpm_pct, :1821-1822)"
const S_BUFFER : String = "LineFlow.gd:1594 buffer — kg waiting in the input buffer, NOT a %: no capacity is modelled"
## amps has TWO writers. The calibrated one (ProcessModel.stage_amps) contributes
## exactly 0 while l3c_code is unstamped; on the high-load drives MotorOverload
## then OVERWRITES the same key with its own current — both measured 2026-07-27 by
## src/tests/test_tag_snapshot.gd, see the per-row notes.
const S_AMPS : String = "LineFlow.gd:1599 amps <- ProcessModel.stage_amps (ProcessModel.gd:38-42) with amps_nominal from LineFlow.gd:467,474-482, THEN overwritten each tick by MotorOverload on high-load drives (LineFlow.gd:2269-2275, seeded at :678-680)"
const S_COMP : String = "LineFlow.gd:1605 components + :1593 powered"
const S_COMP_RPM : String = "LineFlow.gd:1604-1605 components x comp_max_rpm (_component_max_rpms :1570-1580)"
const S_COMP_PCT : String = "LineFlow.gd:1605 readback of set_machine_component_pct :1538-1545"
const S_ESTOP : String = "LineFlow.estop_fault_key / estop_fault_id; the MotorOverload 'mol' model (MotorOverload.gd:157) is NOT reachable through any public accessor, so this row covers the E-STOP component of the real alarm only"
## The instance a row reads is now the unit's OWN machine, addressed by its plant
## code. (This replaces S_FIRST_MATCH, which recorded the opposite and would be a
## FALSE cite now — a stale cite is worse than none.)
const S_BY_CODE : String = "addressed by l3c_code through LineFlow._resolve — the node whose per-instance key IS this unit's code, not a first match on the shared placeable id"

var _export_tags : Dictionary = {}
var _export_count : int = 0
var _rows : Array[Dictionary] = []
var _missing : PackedStringArray = PackedStringArray()
var _load_error : String = ""


func _init() -> void:
	_load_export()
	_build_rows()
	_validate()


# =============================================================================
# LOAD + VALIDATE
# =============================================================================
func _load_export() -> void:
	var f := FileAccess.open(EXPORT_PATH, FileAccess.READ)
	if f == null:
		_load_error = "cannot open %s" % EXPORT_PATH
		push_error("[TagMap] %s" % _load_error)
		return
	var raw := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		_load_error = "%s is not a JSON object" % EXPORT_PATH
		push_error("[TagMap] %s" % _load_error)
		return
	var tags = (parsed as Dictionary).get("tags", null)
	if not (tags is Array):
		_load_error = "%s has no tags[] array" % EXPORT_PATH
		push_error("[TagMap] %s" % _load_error)
		return
	for t in (tags as Array):
		_export_tags[String(t)] = true
	_export_count = _export_tags.size()


## Loud on failure by design: an invented or mistyped tag name is the exact
## no-build-without-docs violation this file exists to make impossible.
func _validate() -> void:
	_missing = PackedStringArray()
	for r in _rows:
		if not _export_tags.has(String(r["tag"])):
			_missing.append(String(r["tag"]))
	if _load_error != "":
		return
	if not _missing.is_empty():
		push_error("[TagMap] %d mapped tag(s) are NOT in the operator export — invented or mistyped: %s"
			% [_missing.size(), String(", ").join(_missing)])
	if _rows.size() != EXPECTED_ROWS:
		push_error("[TagMap] row count %d != EXPECTED_ROWS %d — the table was edited without updating the guard"
			% [_rows.size(), EXPECTED_ROWS])


## {ok, load_error, export_tags, mapped_tags, expected_rows, missing_from_export,
##  by_confidence, coverage_pct}. `ok` is false if ANY mapped tag is absent from
## the export, the row count drifted, or the export failed to load.
func validation() -> Dictionary:
	var by_conf : Dictionary = {}
	for r in _rows:
		var c := String(r["confidence"])
		by_conf[c] = int(by_conf.get(c, 0)) + 1
	return {
		"ok": _load_error == "" and _missing.is_empty() and _rows.size() == EXPECTED_ROWS,
		"load_error": _load_error,
		"export_tags": _export_count,
		"mapped_tags": _rows.size(),
		"expected_rows": EXPECTED_ROWS,
		"missing_from_export": _missing,
		"by_confidence": by_conf,
		"coverage_pct": (100.0 * float(_rows.size()) / float(_export_count)) if _export_count > 0 else 0.0,
	}


# =============================================================================
# QUERY
# =============================================================================
## The map itself. Read-only — callers must not mutate the returned rows.
func rows() -> Array[Dictionary]:
	return _rows

## Distinct placeable ids the machine rows address, in table order.
func machine_ids() -> Array[String]:
	var out : Array[String] = []
	for r in _rows:
		var mid := String(r["machine"])
		if mid != "" and not out.has(mid):
			out.append(mid)
	return out

func rows_for_machine(machine_id: String) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for r in _rows:
		if String(r["machine"]) == machine_id:
			out.append(r)
	return out

## Rows belonging to ONE Line 3C unit, addressed by its plant code. This is the
## instance-truthful query: rows_for_machine("friction_sep") returns the rows of
## all five separators at once, which is only meaningful when the caller has no
## way to tell them apart.
func rows_for_code(code: String) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for r in _rows:
		if String(r["l3c"]) == code:
			out.append(r)
	return out

func line_rows() -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for r in _rows:
		if String(r["machine"]) == "":
			out.append(r)
	return out


# =============================================================================
# RESOLVE — snapshot rows, {tag, value, machine_key, source_field, ...}
# `value` is null when the quantity is not present in this world; the row is
# still returned so an unresolved tag is VISIBLE instead of dropped.
# =============================================================================
## LEGACY, id-keyed. `info` must be get_machine_info(<placeable id>), which
## LineFlow resolves by first match — so on an id with several instances every
## returned row describes whichever one answered. Prefer resolve_code().
func resolve_machine(machine_id: String, info: Dictionary, machine_ctx: Dictionary) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for r in rows_for_machine(machine_id):
		out.append(_emit(r, _machine_value(r, info, machine_ctx)))
	return out


## Resolve ONE Line 3C unit by its plant code. `info` must be
## get_machine_info(code) — LineFlow's per-instance key for a stamped 3C stage IS
## its code, so the snapshot and the rows describe the same physical machine.
func resolve_code(code: String, info: Dictionary, machine_ctx: Dictionary) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for r in rows_for_code(code):
		out.append(_emit(r, _machine_value(r, info, machine_ctx)))
	return out


func resolve_line(line_ctx: Dictionary) -> Array[Dictionary]:
	var out : Array[Dictionary] = []
	for r in line_rows():
		out.append(_emit(r, _line_value(r, line_ctx)))
	return out


func _emit(row: Dictionary, value: Variant) -> Dictionary:
	return {
		"tag": String(row["tag"]),
		"value": value,
		"machine_key": String(row["machine"]),
		"source_field": String(row["source_field"]),
		"unit": String(row["unit"]),
		"l3c_code": String(row["l3c"]),
		"confidence": String(row["confidence"]),
		"note": String(row["note"]),
		"cite": String(row["cite"]),
		"resolved": value != null,
	}


func _machine_value(row: Dictionary, info: Dictionary, machine_ctx: Dictionary) -> Variant:
	if info.is_empty():
		return null
	var arg := String(row["arg"])
	match int(row["kind"]):
		Kind.MACHINE_FIELD:
			if not info.has(arg):
				return null
			return info[arg]
		Kind.MACHINE_SPEED:
			if not (info.has("spin") and info.has("rpm_pct") and info.has("max_rpm")):
				return null
			return float(info["spin"]) * float(info["rpm_pct"]) * float(info["max_rpm"])
		Kind.COMPONENT_STATUS:
			var comps : Dictionary = info.get("components", {})
			if not comps.has(arg):
				return null
			return bool(info.get("powered", false)) and float(comps[arg]) > 0.0
		Kind.COMPONENT_RPM:
			var comps_r : Dictionary = info.get("components", {})
			var maxes : Dictionary = info.get("comp_max_rpm", {})
			if not (comps_r.has(arg) and maxes.has(arg)):
				return null
			return float(comps_r[arg]) * float(maxes[arg])
		Kind.COMPONENT_PCT:
			var comps_p : Dictionary = info.get("components", {})
			if not comps_p.has(arg):
				return null
			return float(comps_p[arg])
		Kind.ESTOP_ALARM:
			# Prefer the per-INSTANCE key: LineFlow.estop_fault_key() names the node
			# that tripped, and a stamped 3C stage's key IS its code, so this lights
			# only the unit that actually faulted. estop_fault_id() names a machine
			# TYPE and would light all five separators at once.
			if machine_ctx.has("estop_fault_key"):
				return String(machine_ctx["estop_fault_key"]) == String(row["l3c"])
			if not machine_ctx.has("estop_fault_id"):
				return null
			return String(machine_ctx["estop_fault_id"]) == String(row["machine"])
		Kind.WATERFLOW:
			if not info.has("thru"):
				return null
			# The node's own water_add, read from the SAME MachineFlow profile
			# LineFlow seeded it from (LineFlow.gd:461-466). Identical to the live
			# node value while no build path stamps l3c_code — which the snapshot
			# MEASURES (stamped_l3c_codes). If that ever becomes non-zero, the
			# ProcessModel override at LineFlow.gd:474-482 takes over and this
			# lookup must be replaced by a real LineFlow accessor.
			var prof : Dictionary = MachineFlowScript.profile(String(row["machine"]))
			return float(prof.get("water_add", 0.0)) * float(info["thru"])
	return null


func _line_value(row: Dictionary, line_ctx: Dictionary) -> Variant:
	match int(row["kind"]):
		Kind.LINE_CONST:
			return Line3CDefScript.LINE_SPEED_KG_H
		Kind.LINE_CTX:
			var k := String(row["arg"])
			if not line_ctx.has(k):
				return null
			return line_ctx[k]
	return null


## Human-readable expression for the dump — what the value was computed from.
func _source_expr(kind: int, arg: String) -> String:
	match kind:
		Kind.MACHINE_FIELD:
			return "get_machine_info()[\"%s\"]" % arg
		Kind.MACHINE_SPEED:
			return "get_machine_info()[\"spin\"] * [\"rpm_pct\"] * [\"max_rpm\"]"
		Kind.COMPONENT_STATUS:
			return "get_machine_info()[\"powered\"] and [\"components\"][\"%s\"] > 0.0" % arg
		Kind.COMPONENT_RPM:
			return "get_machine_info()[\"components\"][\"%s\"] * [\"comp_max_rpm\"][\"%s\"]" % [arg, arg]
		Kind.COMPONENT_PCT:
			return "get_machine_info()[\"components\"][\"%s\"] (setpoint READBACK, 0..1)" % arg
		Kind.ESTOP_ALARM:
			return "LineFlow.estop_fault_id() == machine_key"
		Kind.WATERFLOW:
			return "MachineFlow.profile(id)[\"water_add\"] * get_machine_info()[\"thru\"] (kg/s)"
		Kind.LINE_CONST:
			return "Line3CDef.LINE_SPEED_KG_H"
		Kind.LINE_CTX:
			return "line_ctx[\"%s\"]" % arg
	return ""


# =============================================================================
# THE MAP — hand-authored, doc-cited. 77 rows.
# =============================================================================
func _add(tag: String, unit: String, kind: int, arg: String, sim: String, conf: String, note: String) -> void:
	var spine : Array = UNITS[unit]
	_rows.append({
		"tag": tag, "unit": unit, "l3c": String(spine[0]), "machine": String(spine[1]),
		"kind": kind, "arg": arg, "source_field": _source_expr(kind, arg),
		"confidence": conf, "note": note,
		"cite": "%s ; SPINE src/sim/Line3CDef.gd:%d (%s == %s) ; SIM src/sim/%s"
			% [TAG_SRC, int(spine[2]), String(spine[0]), String(spine[1]), sim],
	})


func _add_line(tag: String, kind: int, arg: String, sim: String, conf: String, note: String) -> void:
	_rows.append({
		"tag": tag, "unit": "", "l3c": "", "machine": "",
		"kind": kind, "arg": arg, "source_field": _source_expr(kind, arg),
		"confidence": conf, "note": note,
		"cite": "%s ; SIM src/sim/%s" % [TAG_SRC, sim],
	})


func _build_rows() -> void:
	_rows.clear()
	_unit_1_doseersilo()
	_unit_3_sink_float()
	_unit_4l_friction_sep()
	_unit_5l_transport_screw()
	_unit_6_mill()
	_unit_11_flotation_tank()
	_unit_14l_mech_dryer()
	_unit_15_blower()
	_unit_16_plasmaq()
	_unit_18_silo()
	_units_newly_addressable()
	_line_level()


## The ten units that were UNMAPPABLE until machines got per-instance keys: they
## share a placeable id with an already-mapped sibling (friction_sep x5,
## transport_screw x5, mech_dryer x2, blower x2), so before the fix a row here
## would have resolved to whichever instance LineFlow's first match returned —
## the vacuous multiplication this file refused to add. They are now reached by
## their OWN l3c_code.
##
## SCOPE, deliberately narrow. Each unit gets exactly the three em leaves its
## already-approved sibling carries (status / hand / snelheid — all three verified
## verbatim in the export for all ten), plus the machine-level stroom leaf for the
## five whose device is the SAME CLASS as an approved sibling's:
## softstarterfrictiewasser (4l is approved -> 4r/9l/9r/13) and softstarterdroger1
## (14l is approved -> 14r). 30 + 5 = 35 rows.
##
## NOT ADDED, and why — these are gaps, not oversights:
##  * PER-MOTOR stroom on 5r/10l/10r/12/19 ("schroef 1"/"schroef 2",
##    "afvoerschroef", "fqventilator"): `amps` is per-MACHINE, never per motor
##    (see the PER-MOTOR block in the header). Which motor carries the machine
##    total is an operator ruling, not ours.
##  * em/alarm on the friction siblings, and the softstarter*/status +
##    setpoints readbacks: available and bindable, but they add no quantity the
##    approved sibling row does not already prove. Deferred as a follow-up;
##    EXPECTED_ROWS must move with them.
func _units_newly_addressable() -> void:
	# unit -> [Dutch device name on the HMI, its stroom leaf or "" ]
	var em_only : Array = ["5r", "10l", "10r", "12", "19"]
	var with_stroom : Dictionary = {
		"4r":  ["softstarterfrictiewasser", "friction separator, one soft-started motor — same device class as the approved 4l row (:%d)"],
		"9l":  ["softstarterfrictiewasser", "friction separator, one soft-started motor — same device class as the approved 4l row (:%d)"],
		"9r":  ["softstarterfrictiewasser", "friction separator, one soft-started motor — same device class as the approved 4l row (:%d)"],
		"13":  ["softstarterfrictiewasser", "friction separator, one soft-started motor — same device class as the approved 4l row (:%d)"],
		"14r": ["softstarterdroger1", "mechanical dryer drum — same device class as the approved 14l row (:%d)"],
	}
	var all_units : Array = em_only + with_stroom.keys()
	for uu in all_units:
		var u := String(uu)
		var code := String((UNITS[u] as Array)[0])
		_add("scada/3c/info/%s/em/status" % u, u, Kind.MACHINE_FIELD, "powered",
			"%s ; %s" % [S_POWERED, S_BY_CODE], "certain",
			"UNMAPPABLE before per-instance keys: shares a placeable id with a mapped sibling, now reached as %s" % code)
		_add("scada/3c/info/%s/em/hand" % u, u, Kind.MACHINE_FIELD, "hand_mode",
			"%s ; %s" % [S_HAND, S_BY_CODE], "certain", "")
		_add("scada/3c/info/%s/em/snelheid" % u, u, Kind.MACHINE_SPEED, "",
			"%s ; %s" % [S_SPEED, S_BY_CODE], "probable",
			"spin is the spin-up RAMP, not a speed setting")
	for uu2 in with_stroom.keys():
		var u2 := String(uu2)
		var dev := String((with_stroom[u2] as Array)[0])
		var why := String((with_stroom[u2] as Array)[1])
		var spine_line : int = int((UNITS[u2] as Array)[2])
		var code2 := String((UNITS[u2] as Array)[0])
		_add("scada/3c/info/%s/%s/stroom" % [u2, dev], u2, Kind.MACHINE_FIELD, "amps",
			"%s ; nominal %.2f A from Line3CDef.gd:%d ; %s"
				% [S_AMPS, ProcessModelScript.hmi_amps_for_code(code2), spine_line, S_BY_CODE],
			"probable", why % spine_line)


## Unit 1 — dosing silo, 3 parallel augers + level. 13 rows.
func _unit_1_doseersilo() -> void:
	_add("scada/3c/info/1/em/status", "1", Kind.MACHINE_FIELD, "powered",
		S_POWERED, "certain", "PLC/HAND power state of the unit")
	_add("scada/3c/info/1/em/hand", "1", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/1/em/snelheid", "1", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "spin is the spin-up RAMP, not a speed setting")
	# schroef 1-3 == the 3 augers _default_components_for gives a doseersilo
	# (LineFlow.gd:1415-1421). 3 SCADA motors, 3 sim components: 1:1.
	_add("scada/3c/info/1/schroef 1/status", "1", Kind.COMPONENT_STATUS, "auger_1",
		"%s ; components from LineFlow.gd:1415-1421 ; DOC docs/plant/line3c_scada_tags.md:24" % S_COMP,
		"certain", "SCADA 'schroef 1' == sim component auger_1")
	_add("scada/3c/info/1/schroef 2/status", "1", Kind.COMPONENT_STATUS, "auger_2",
		"%s ; components from LineFlow.gd:1415-1421" % S_COMP,
		"certain", "SCADA 'schroef 2' == sim component auger_2")
	_add("scada/3c/info/1/schroef 3/status", "1", Kind.COMPONENT_STATUS, "auger_3",
		"%s ; components from LineFlow.gd:1415-1421" % S_COMP,
		"certain", "SCADA 'schroef 3' == sim component auger_3")
	_add("scada/3c/info/1/schroef 1/frequentie", "1", Kind.COMPONENT_RPM, "auger_1",
		"%s ; DOC docs/plant/line3c_scada_tags.md:46 ('frequentie')" % S_COMP_RPM,
		"needs-operator", "UNIT MISMATCH: sim yields RPM, the SCADA leaf is drive Hz")
	_add("scada/3c/info/1/schroef 2/frequentie", "1", Kind.COMPONENT_RPM, "auger_2",
		S_COMP_RPM, "needs-operator", "UNIT MISMATCH: RPM vs Hz")
	_add("scada/3c/info/1/schroef 3/frequentie", "1", Kind.COMPONENT_RPM, "auger_3",
		S_COMP_RPM, "needs-operator", "UNIT MISMATCH: RPM vs Hz")
	_add("scada/3c/setpoints/1/schroef 1/snelheid", "1", Kind.COMPONENT_PCT, "auger_1",
		S_COMP_PCT, "probable", "READ-ONLY readback; set_machine_component_pct is one of only 4 control classes with a real endpoint")
	_add("scada/3c/setpoints/1/schroef 2/snelheid", "1", Kind.COMPONENT_PCT, "auger_2",
		S_COMP_PCT, "probable", "READ-ONLY readback")
	_add("scada/3c/setpoints/1/schroef 3/snelheid", "1", Kind.COMPONENT_PCT, "auger_3",
		S_COMP_PCT, "probable", "READ-ONLY readback")
	_add("scada/3c/info/1/niveau meting/niveau", "1", Kind.MACHINE_FIELD, "buffer",
		"%s ; DOC docs/plant/line3c_scada_tags.md:24 ('niveau meting')" % S_BUFFER,
		"needs-operator", "kg, not %. SiloLevelSensor.current_level_pct is a dead source and is NOT used")


## Unit 3 — settling separator (Bezinkafscheider) + level. 5 rows.
func _unit_3_sink_float() -> void:
	_add("scada/3c/info/3/em/status", "3", Kind.MACHINE_FIELD, "powered",
		S_POWERED, "certain", "")
	_add("scada/3c/info/3/em/hand", "3", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/3/em/snelheid", "3", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "")
	_add("scada/3c/info/3/niveau meting/niveau", "3", Kind.MACHINE_FIELD, "buffer",
		S_BUFFER, "needs-operator", "kg, not %")
	_add("scada/3c/meeting/overig/6_3_bezinkafscheider waterflow", "3", Kind.WATERFLOW, "",
		"MachineFlow.gd:381-386 (sink_float water_add 0.40) x LineFlow.gd:1595 thru; applied per tick at LineFlow.gd:1993-1997 ; DOC docs/plant/line3c_scada_tags.md:43",
		"probable", "meeting tags are named 6_<n> under scada/3c — the 3c-vs-6 line identity is an OPEN operator question (docs/plant/line3c_scada_tags.md:7-11)")


## Unit 4L — friction separator, ONE soft-started motor. Representative of the
## 5 friction_sep units (4l/4r/9l/9r/13) that all collapse to one node. 9 rows.
func _unit_4l_friction_sep() -> void:
	_add("scada/3c/info/4l/em/status", "4l", Kind.MACHINE_FIELD, "powered",
		"%s ; %s" % [S_POWERED, S_BY_CODE], "certain", "one of the five friction_sep on Line 3C; reached by ITS code L3C.4L, not by the shared id")
	_add("scada/3c/info/4l/em/hand", "4l", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/4l/em/snelheid", "4l", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "spin is the spin-up RAMP, not a speed setting")
	_add("scada/3c/info/4l/em/alarm", "4l", Kind.ESTOP_ALARM, "",
		"%s ; _is_high_load_motor matches 'friction' at LineFlow.gd:594-598" % S_ESTOP,
		"probable", "PARTIAL: the MotorOverload trip half of this alarm has no public accessor")
	# friction_sep does NOT match the friction_washer/frictiewasser arm, so it
	# falls to the default single "drive" (LineFlow.gd:1453-1459) — 1:1 with the
	# one soft-started SCADA motor on this unit.
	_add("scada/3c/info/4l/softstarterfrictiewasser/status", "4l", Kind.COMPONENT_STATUS, "drive",
		"%s ; default single 'drive' at LineFlow.gd:1457-1459 ; DOC docs/plant/line3c_scada_tags.md:26" % S_COMP,
		"probable", "friction_sep takes the default 'drive' component, NOT the frictiewasser stirrer pair")
	_add("scada/3c/info/4l/softstarterfrictiewasser/stroom", "4l", Kind.MACHINE_FIELD, "amps",
		"%s ; nominal 29.92 A from Line3CDef.gd:62 ; MEASURED src/tests/test_tag_snapshot.gd 2026-07-27" % S_AMPS,
		"probable", "MEASURED CAVEAT: reads 31.50 A on a real MainWorld boot, NOT the calibrated 29.92 A. friction_sep matches _is_high_load_motor (LineFlow.gd:594-598), so a MotorOverload seeded from its PLACEHOLDER 90.0 A default (because amps_nominal was 0) overwrites this key: 90.0 x idle_frac 0.35 = 31.50 A of fictitious current")
	_add("scada/3c/info/4l/softstarterfrictiewasser/handauto", "4l", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "probable", "MACHINE scope, not motor scope: the sim has no per-component hand/auto")
	_add("scada/3c/setpoints/4l/softstarterfrictiewasser/stopstarthand", "4l", Kind.MACHINE_FIELD, "manual_on",
		S_MANUAL, "probable", "READ-ONLY readback; only effective while hand_mode")
	_add("scada/3c/setpoints/4l/em/handauto", "4l", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "probable", "READ-ONLY readback of set_machine_hand_mode")


## Unit 5L — transport screw, one VFD. Representative of the 5 transport_screw
## units (5l/5r/10l/10r/12). 6 rows.
func _unit_5l_transport_screw() -> void:
	_add("scada/3c/info/5l/em/status", "5l", Kind.MACHINE_FIELD, "powered",
		"%s ; %s" % [S_POWERED, S_BY_CODE], "certain", "one of the five transport_screw on Line 3C; reached by ITS code L3C.5L")
	_add("scada/3c/info/5l/em/hand", "5l", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/5l/em/snelheid", "5l", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "spin is the spin-up RAMP, not a speed setting")
	_add("scada/3c/info/5l/schroef 1/status", "5l", Kind.COMPONENT_STATUS, "drive",
		"%s ; MachineFlow.gd:149-152 (transport_screw role=conveyor) ; DOC docs/plant/line3c_scada_tags.md:27" % S_COMP,
		"probable", "single-drive conveyor, 1:1 with the one SCADA motor")
	_add("scada/3c/info/5l/schroef 1/frequentie", "5l", Kind.COMPONENT_RPM, "drive",
		S_COMP_RPM, "needs-operator", "UNIT MISMATCH: RPM vs Hz")
	_add("scada/3c/setpoints/5l/fqschroef1/snelheid", "5l", Kind.COMPONENT_PCT, "drive",
		S_COMP_PCT, "probable", "the export names this motor 'fqschroef1' under setpoints but 'schroef 1' under info — a real inconsistency in the operator export; both kept VERBATIM")


## Unit 6 — grinding mill (Maalmolen), soft-started cutter. 8 rows.
func _unit_6_mill() -> void:
	_add("scada/3c/info/6/em/status", "6", Kind.MACHINE_FIELD, "powered",
		S_POWERED, "certain", "")
	_add("scada/3c/info/6/em/hand", "6", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/6/em/snelheid", "6", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "")
	_add("scada/3c/info/6/em/alarm", "6", Kind.ESTOP_ALARM, "",
		"%s ; _is_high_load_motor matches 'mill' at LineFlow.gd:594-598" % S_ESTOP,
		"probable", "PARTIAL: MotorOverload trip half has no public accessor")
	_add("scada/3c/info/6/softstartersnijmolen/status", "6", Kind.COMPONENT_STATUS, "rotor",
		"%s ; mill -> rotor at LineFlow.gd:1429-1430 ; DOC docs/plant/line3c_scada_tags.md:28" % S_COMP,
		"probable", "the cutting rotor is the one mill component the sim models; hydrauliek + schroef 1-3 on this SCADA unit are absent")
	_add("scada/3c/info/6/softstartersnijmolen/stroom", "6", Kind.MACHINE_FIELD, "amps",
		"%s ; nominal 186.79 A from Line3CDef.gd:66 ; MEASURED src/tests/test_tag_snapshot.gd 2026-07-27" % S_AMPS,
		"probable", "MEASURED CAVEAT: reads 31.50 A, NOT the calibrated 186.79 A — mill matches _is_high_load_motor, so MotorOverload's placeholder 90.0 A x 0.35 supplies the number (6x too low)")
	_add("scada/3c/info/6/softstartersnijmolen/handauto", "6", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "probable", "machine scope, not motor scope")
	_add("scada/3c/setpoints/6/softstartersnijmolen/stopstarthand", "6", Kind.MACHINE_FIELD, "manual_on",
		S_MANUAL, "probable", "READ-ONLY readback")


## Unit 11 — flotation tank, the biggest unit in the export at 74 tags. 9 rows.
func _unit_11_flotation_tank() -> void:
	_add("scada/3c/info/11/em/status", "11", Kind.MACHINE_FIELD, "powered",
		S_POWERED, "certain", "")
	_add("scada/3c/info/11/em/hand", "11", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/11/em/snelheid", "11", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "")
	_add("scada/3c/info/11/niveau/niveau", "11", Kind.MACHINE_FIELD, "buffer",
		S_BUFFER, "needs-operator", "kg, not %: no tank capacity is modelled")
	_add("scada/3c/info/11/intrekwals/status", "11", Kind.COMPONENT_STATUS, "inlet",
		"%s ; flotation -> inlet/transport_1/transport_2/outlet at LineFlow.gd:1422-1426 ; DOC docs/plant/line3c_scada_tags.md:32" % S_COMP,
		"probable", "intrekwals (pull-in roller) == the tank INLET drive")
	_add("scada/3c/info/11/uittrekschroef/status", "11", Kind.COMPONENT_STATUS, "outlet",
		"%s ; LineFlow.gd:1426 ; DOC docs/plant/line3c_scada_tags.md:32" % S_COMP,
		"probable", "uittrekschroef (extraction screw) == the tank OUTLET drive")
	_add("scada/3c/info/11/uittrekschroef/frequentie", "11", Kind.COMPONENT_RPM, "outlet",
		S_COMP_RPM, "needs-operator", "UNIT MISMATCH: RPM vs Hz")
	_add("scada/3c/setpoints/11/uittrekschroef/snelheid", "11", Kind.COMPONENT_PCT, "outlet",
		"%s ; _component_topology('flotation') == 'series' at LineFlow.gd:1475-1476, combined at :1631-1645" % S_COMP_PCT,
		"probable", "load-bearing: series topology means the SLOWEST component caps tank throughput")
	_add("scada/3c/meeting/overig/6_11_flotatietank waterflow", "11", Kind.WATERFLOW, "",
		"MachineFlow.gd:29-50 (generic defaults) + :381-386 (the arm matches 'flotation_tank' and 'sink_float', NOT 'flotation_tank_wide') x LineFlow.gd:1595 thru ; DOC docs/plant/line3c_scada_tags.md:43",
		"needs-operator", "DEFECT, measured STATICALLY (src/tests/test_tag_snapshot.gd asserts it): MachineFlow.profile() is an EXACT `match id:` (MachineFlow.gd:28,51) and its float arm names 'flotation_tank' + 'sink_float' but NOT 'flotation_tank_wide' — L3C.11's own id (Line3CDef.gd:71) — so the sim's Flotatietank silently runs the generic profile (water_add 0.0 vs 0.40, contam_remove 0.0, process 'convey') and does nothing to the material. NOT inferable from this row's own value: water_add x thru is 0 whenever thru is 0, so a run cannot tell this defect apart from an idle line, which is why water_add is measured per profile instead")


## Unit 14L — mechanical dryer, soft-started drum. Representative of the
## mech_dryer pair (14l/14r, pair_id dryer_pair). 7 rows.
func _unit_14l_mech_dryer() -> void:
	_add("scada/3c/info/14l/em/status", "14l", Kind.MACHINE_FIELD, "powered",
		"%s ; %s" % [S_POWERED, S_BY_CODE], "certain", "one of the mech_dryer pair; reached by ITS code L3C.14L, so a 3A/3B dryer sharing the id can no longer answer for it")
	_add("scada/3c/info/14l/em/hand", "14l", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/14l/em/snelheid", "14l", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "spin is the spin-up RAMP, not a speed setting")
	_add("scada/3c/info/14l/softstarterdroger1/status", "14l", Kind.COMPONENT_STATUS, "drive",
		"%s ; default single 'drive' at LineFlow.gd:1457-1459 ; DOC docs/plant/line3c_scada_tags.md:35" % S_COMP,
		"probable", "the rotary-valve + cleaning-scraper motors on this SCADA unit are absent (no sim component)")
	_add("scada/3c/info/14l/softstarterdroger1/stroom", "14l", Kind.MACHINE_FIELD, "amps",
		"%s ; nominal 70.80 A from Line3CDef.gd:77 ; MEASURED src/tests/test_tag_snapshot.gd 2026-07-27" % S_AMPS,
		"probable", "MEASURED CAVEAT: reads exactly 0.00 A against a calibrated 70.80 A. mech_dryer is NOT a high-load motor, so nothing overwrites the dead calibrated path here — this row is where the l3c_code -> amps_nominal=0 chain shows through undisguised")
	_add("scada/3c/info/14l/softstarterdroger1/handauto", "14l", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "probable", "machine scope")
	_add("scada/3c/setpoints/14l/softstarterdroger1/stopstarthand", "14l", Kind.MACHINE_FIELD, "manual_on",
		S_MANUAL, "probable", "READ-ONLY readback")


## Unit 15 — transport fan, one VFD. 6 rows.
func _unit_15_blower() -> void:
	_add("scada/3c/info/15/em/status", "15", Kind.MACHINE_FIELD, "powered",
		"%s ; %s" % [S_POWERED, S_BY_CODE], "certain", "blower x2 on Line 3C and x5 in LINE_3A_SEQ alone; reached by ITS code L3C.15")
	_add("scada/3c/info/15/em/hand", "15", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/15/em/snelheid", "15", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "spin is the spin-up RAMP, not a speed setting")
	_add("scada/3c/info/15/fqventilator/status", "15", Kind.COMPONENT_STATUS, "drive",
		"%s ; blower -> single 'drive' at LineFlow.gd:1427-1428 ; DOC docs/plant/line3c_scada_tags.md:36" % S_COMP,
		"certain", "1:1 — one sim component, one SCADA motor on this unit")
	_add("scada/3c/info/15/fqventilator/frequentie", "15", Kind.COMPONENT_RPM, "drive",
		S_COMP_RPM, "needs-operator", "UNIT MISMATCH: RPM vs Hz")
	_add("scada/3c/setpoints/15/fqventilator/snelheid", "15", Kind.COMPONENT_PCT, "drive",
		S_COMP_PCT, "probable", "READ-ONLY readback")


## Unit 16 — Plasmaq. Carries ONLY an em block in the export, matching the sim
## exactly (docs/plant/line3c_scada_tags.md:37 '16 | em only'). 3 rows.
func _unit_16_plasmaq() -> void:
	_add("scada/3c/info/16/em/status", "16", Kind.MACHINE_FIELD, "powered",
		"%s ; DOC docs/plant/line3c_scada_tags.md:37" % S_POWERED, "certain", "")
	_add("scada/3c/info/16/em/hand", "16", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "certain", "")
	_add("scada/3c/info/16/em/snelheid", "16", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "")


## Unit 18 — extruder/mixing silo, VFD screw + level. 7 rows.
func _unit_18_silo() -> void:
	_add("scada/3c/info/18/em/status", "18", Kind.MACHINE_FIELD, "powered",
		S_POWERED, "probable", "")
	_add("scada/3c/info/18/em/hand", "18", Kind.MACHINE_FIELD, "hand_mode",
		S_HAND, "probable", "")
	_add("scada/3c/info/18/em/snelheid", "18", Kind.MACHINE_SPEED, "",
		S_SPEED, "probable", "")
	_add("scada/3c/info/18/niveau/niveau", "18", Kind.MACHINE_FIELD, "buffer",
		"%s ; MachineFlow.gd:368-369 (silo process == 'buffer')" % S_BUFFER,
		"needs-operator", "kg, not %")
	_add("scada/3c/info/18/fqschroef/status", "18", Kind.COMPONENT_STATUS, "drive",
		"%s ; default single 'drive' at LineFlow.gd:1457-1459 ; DOC docs/plant/line3c_scada_tags.md:38" % S_COMP,
		"probable", "the 2 agitator-shaft motors + fan on this SCADA unit are absent")
	_add("scada/3c/info/18/fqschroef/frequentie", "18", Kind.COMPONENT_RPM, "drive",
		S_COMP_RPM, "needs-operator", "UNIT MISMATCH: RPM vs Hz")
	_add("scada/3c/setpoints/18/fqschroef1/snelheid", "18", Kind.COMPONENT_PCT, "drive",
		S_COMP_PCT, "probable", "same info-vs-setpoints spelling split as unit 5l ('fqschroef' vs 'fqschroef1'); both VERBATIM")


## Line-level rows (root lines/3c). 4 rows.
func _line_level() -> void:
	_add_line("lines/3c/performance/targetspeed", Kind.LINE_CONST, "",
		"Line3CDef.gd:56 LINE_SPEED_KG_H = 1687.0 (same figure at ProcessModel.gd:24) ; DOC docs/plant/line3c_scada_tags.md:16",
		"certain", "transcribed from the plant HMI 'Techical overview'")
	_add_line("lines/3c/data/throughputactual", Kind.LINE_CTX, "tail_thru_kg_h",
		"LineFlow.gd:1595 thru (EMA-smoothed kg/s, :514) x 3600 at the tail stage; tail = Line3CDef.tail_code() 'Voorraad' -> voorraad_silo (Line3CDef.gd:95,144-149); existing thru*3600 precedent at LineFlow.gd:2227 ; DOC docs/plant/line3c_scada_tags.md:16",
		"probable", "caller supplies the tail stage reading")
	_add_line("lines/3c/data/productioncounter", Kind.LINE_CTX, "gran_mass_kg",
		"LineFlow.gd:130 gran_mass (kg granulaat this shift, reset by reset_shift_telemetry :326-338)",
		"probable", "")
	_add_line("lines/3c/data/linestatus", Kind.LINE_CTX, "line_status",
		"LineFlow.gd:2322-2332 4-state derivation already used for the SCADA push: Fault (is_estopped :1648-1649) > Starting (is_line_starting :1405) > Running (line_powered_fraction :1716-1720) > Idle ; DOC docs/plant/line3c_scada_tags.md:16",
		"certain", "")
