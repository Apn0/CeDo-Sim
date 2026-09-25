extends Node3D
## WASLIJN 3C OVERZICHT — is the ported screen HONEST?
##
##   godot --headless --path <proj> res://src/tests/test_waslijn3c_overzicht.tscn
##
## Boots the REAL MainWorld (not a bench — this project has shipped bench greens
## that proved nothing: npc-05 printed 31/31 while moving zero kg), builds BOTH
## the line_3c macro (the spine this screen is actually about) and line_3a
## alongside it, powers and FEEDS them, then mounts
## src/scenes/hud/scopes/WashingScope.gd — the port of
## docs/plant/hmi_screens_2026-07-26/Waslijn 3C Overzicht.dc.html — and asks it
## what it claims to be showing.
##
## WHY BOTH LINES. Line 3A re-uses the same placeable ids as Line 3C
## (friction_sep, transport_screw, mech_dryer, blower). Building it alongside is
## the adversarial half of the run: if the screen ever falls back to addressing a
## machine by its id, a LINE 3A machine will answer for an L3C caption, and
## criterion G below catches exactly that.
##
## NON-VACUOUS PASS CRITERIA, STATED UP FRONT
## ------------------------------------------
##  A. STRUCTURE   the Control instantiates and paints; field_report() accounts
##                 for EVERY field exactly once (bound + unavailable == total,
##                 total == 38).
##  B. SPLIT       bound == 28 and unavailable == 10, compared against LITERALS
##                 held here — a second, independent copy of the numbers the
##                 scope guards in BOUND_FIELDS_EXPECTED / UNAVAIL_FIELDS_EXPECTED.
##                 Drift in either copy fails.  This is the check that catches a
##                 regression which starts FAKING an unavailable field: faking one
##                 moves it from the unavailable list to the bound list and both
##                 counts break.
##                 WAS 13 / 25 while ten of the twenty L3C units were unreachable
##                 (one placeable id, up to five units). The count moved because
##                 those ten became addressable by their own plant code — the
##                 MEASUREMENT below is what these literals track, and if a run
##                 disagrees the run wins and both copies move to it.
##  C. PROVENANCE  every bound field names a tag that is VERBATIM in the
##                 operator's export, resolves to a NON-NULL value, and its
##                 source_field expression genuinely goes through
##                 get_machine_info().  A bound field with no tag, or a tag the
##                 export does not contain, is a FAIL.
##  D. AGREEMENT   what the audit dict says matches what the operator SEES: every
##                 bound field's painted text is NOT "--", and every unavailable
##                 field's painted text IS exactly "--".  The dict cannot lie
##                 about the pixels.
##  E. LIVENESS    the anti-vacuity check.  A screen bound to a data source that
##                 returns every correct KEY at its type default (all false, all
##                 0.0) would satisfy A-D perfectly.  So: >= 16 of the 20 bound
##                 status fields must read TRUE on a running line, at least one
##                 bound Stroom must be > 0.0, and the bound Stroom values must
##                 contain at least 4 DISTINCT numbers — four is the number of
##                 distinct calibrated currents the spine actually holds for the
##                 bound units, and it is unreachable by any screen that reads one
##                 instance for a whole machine type.  MUTATION 2 proves this
##                 check is the one doing the work.
##  F. REASONS     every unavailable field carries a non-empty reason string —
##                 "--" without a recorded cause is how invented values creep back.
##  G. INSTANCE    the check the old first-match screen could never have passed:
##                 every bound field must resolve through a machine whose OWN
##                 l3c_code equals the caption's code.  A Line 3A friction_sep
##                 answering for L3C.4L is a FAIL, not a near miss.
##
## MUTATION TESTS (both required to go RED, or the criteria above prove nothing)
## ---------------------------------------------------------------------------
##  M1 DEAD SOURCE   rebind to a stub whose get_machine_info() returns {}.
##                   Expected: bound collapses to 0, unavailable rises to 38,
##                   and checks B/C/E fail.
##  M2 CORRECT-KEYS-DEAD-VALUES  rebind to a stub returning the FULL
##                   get_machine_info() key set at type defaults (powered=false,
##                   amps=0.0).  Expected: A-D still pass (13/25 exactly), and
##                   ONLY E fails.  This is the npc-05 shape, and if E did not
##                   exist this run would print a green that proves nothing.
##
## user:// SAFETY: every file this test can touch is byte-backed-up and restored,
## and the operator's allernieuwste_* saves are hash-checked before and after.

const TagMapScript = preload("res://src/sim/TagMap.gd")
const WashingScopeScript = preload("res://src/scenes/hud/scopes/WashingScope.gd")

# ── Building frame (bf) -> Plant Coordinates affine — same constants
# regression_world_save.gd and test_tag_snapshot.gd use.
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)

const TEST_SLOT := "__wl3covz__"
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const TOUCHED := [
	"user://world_layout_consumed.flag",
	"user://__wl3covz___save.json", "user://__wl3covz___factory.json",
]
const DUMP_PATH := "user://waslijn3c_overzicht_report.json"

## THE screen's own line. Every machine it places carries an l3c_code derived from
## its macro_index (Line3CDef.code_for_macro_entry), which is what makes each unit
## addressable by its plant tag.
const MACRO_3C := "line_3c"
const LINE_3C_START_BF := Vector2(4.0, 62.0)
## The decoy: same placeable ids, different plant equipment, no codes. Criterion G
## is aimed squarely at this.
const MACRO_ID := "line_3a"
const LINE_START_BF := Vector2(4.0, 22.0)

const TICK_DT := 0.1
const TICK_COUNT := 400
## kg/s charged into EVERY head. RE-MEASURED 2026-07-29 after the trip points
## moved: MotorOverload is now seeded from each stage's OWN calibrated nominal
## instead of the 90.0 A placeholder, so a friction separator's threshold is the
## max(nominal x 1.5, 120 A) floor of 120 A against a 149.6 A locked rotor
## (29.92 x 5) rather than 135 A against 450 A — i.e. it takes MORE accumulated
## backlog to trip, not less. The 0.05 figure was derived against the OLD numbers
## and is kept only because the run re-measures the trip state every time and
## prints it by name (see _drive_line); it is not tuned out of sight.
## 0.05 x the world's heads is comfortably above Line3CDef's LINE_SPEED_KG_H 1687
## and inside what both chains pass without binding.
const FEED_RATE := 0.05
const FEED_DENSITY := 320.0
const FEED_COMP := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}

# ── The independent copies of the documented split (criterion B). These and
# WashingScope.BOUND_FIELDS_EXPECTED / UNAVAIL_FIELDS_EXPECTED are deliberately
# TWO copies: criterion B compares them, and a single shared constant could never
# disagree with itself.
const EXPECT_BOUND   := 28      # 20 unit status + 8 unit Stroom
const EXPECT_UNAVAIL := 10      # 3 header chips + 1 alarm + 6 Stroom
const EXPECT_TOTAL   := 38
const EXPECT_BOUND_STATUS := 20
const MIN_STATUS_TRUE := 16
## Distinct bound-Stroom values required by criterion E. The eight bound units
## hold SIX distinct calibrated nominals (29.92 x2 / 186.79 / 28.03 / 30.88 /
## 24.68 / 70.80 / 63.51), so a screen reading one instance per machine TYPE
## cannot reach four: friction_sep would supply one number for five units.
const MIN_DISTINCT_STROOM := 4

var _pass := 0
var _fail := 0
var _skip := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, TOUCHED)
var _guarded : Dictionary = {}
var _dump : Dictionary = {}
## The REAL LineFlow, kept for criterion G. Held separately from whatever the
## screen is currently bound to, so the identity check interrogates the world
## rather than the stub — a stub could otherwise agree with itself.
var _line_flow_ref : Node = null


## A LineFlow stand-in that answers the call but knows nothing (MUTATION 1).
class StubDeadSource extends Node:
	func get_machine_info(_id: String) -> Dictionary:
		return {}
	func estop_fault_id() -> String:
		return ""


## A LineFlow stand-in with every CORRECT key at its type default (MUTATION 2) —
## the npc-05 shape: structurally perfect, physically dead. `key` and `l3c_code`
## echo the requested handle so the stub is STRUCTURALLY correct (the screen
## verifies the answering machine carries the code it asked for); everything that
## is a measurement sits at its type default.
class StubDefaultValues extends Node:
	func get_machine_info(_id: String) -> Dictionary:
		return {
			"id": _id, "key": _id, "l3c_code": _id, "amps_nominal": 0.0,
			"role": "", "process": "", "rate": 0.0, "spin": 0.0,
			"powered": false, "buffer": 0.0, "thru": 0.0, "moist": 0.0,
			"contam": 0.0, "quality": 0.0, "amps": 0.0,
			"hand_mode": false, "manual_on": false, "rpm_pct": 0.0,
			"max_rpm": 0.0, "comp_max_rpm": {}, "components": {},
		}
	func estop_fault_id() -> String:
		return ""
	func estop_fault_key() -> String:
		return ""


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1

func _note(msg: String) -> void:
	print("  note  : %s" % msg)

func _section(t: String) -> void:
	print("\n[%s]" % t)

func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU


func _ready() -> void:
	print("=== WASLIJN 3C OVERZICHT — ported screen honesty check ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via a .tscn, not --script)")
		get_tree().quit(2); return

	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return
	_guard_operator_saves()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame

	var lf = world.get("line_flow")
	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if lf == null or bm == null:
		print("FATAL: LineFlow (%s) or BuildMode (%s) missing after boot"
			% [str(lf != null), str(bm != null)])
		_finish(world); return

	await _build_world(bm, lf)
	_drive_line(lf)
	await _exercise_screen(lf)

	for c in _wlg.final_checks(world):
		_ok(c[0], c[1])
	_verify_operator_saves()
	_write_dump()
	_finish(world)


## The verdict is printed and user:// restored BEFORE the world is freed, then
## restored again after: the headless teardown segfault lands inside world
## teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
func _finish(world: Node = null) -> void:
	_wlg.restore()
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Dump: %s" % ProjectSettings.globalize_path(DUMP_PATH))
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	if world != null and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
func _place_macro(bm, macro_id: String, start_bf: Vector2) -> void:
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[macro_id] = {}       # clean const seed, on-disk macro untouched
	var start : Vector3 = Plant.pc_to_scene(_bf_to_pc(start_bf))
	var fdir : Vector3 = Plant.pc_to_scene(_bf_to_pc(start_bf + Vector2(1.0, 0.0))) - start
	fdir = fdir.normalized()
	bm.call("_build_full_line", macro_id, start, atan2(-fdir.x, -fdir.z))
	for _i in range(10):
		await get_tree().process_frame


func _build_world(bm, lf) -> void:
	_section("WORLD — line_3c (the screen's own spine) + line_3a as the id decoy")
	await _place_macro(bm, MACRO_3C, LINE_3C_START_BF)
	await _place_macro(bm, MACRO_ID, LINE_START_BF)

	lf.call("rebuild")
	for _i in range(10):
		await get_tree().process_frame

	# The screen can only bind what is addressable. Prove all twenty units are
	# really in the world before asserting anything about the screen — twenty
	# empty get_machine_info() results would otherwise read as "screen is honest".
	var listed : Array = lf.call("machine_list")
	var codes : Dictionary = {}
	for e2 in listed:
		var c := String((e2 as Dictionary).get("l3c_code", ""))
		if c != "":
			codes[c] = true
	var absent : Array = []
	for u in TagMapScript.UNITS.keys():
		var want := String((TagMapScript.UNITS[String(u)] as Array)[0])
		if not codes.has(want):
			absent.append(want)
	_ok(absent.is_empty(),
		"all %d mapped L3C units are live and addressable by their own code (%d absent: %s)"
			% [TagMapScript.UNITS.size(), absent.size(), str(absent)])
	# The decoy has to be present or criterion G proves nothing: a world with no
	# duplicate-id machine cannot exhibit the first-match defect in the first place.
	var decoy := 0
	for nd in (lf.get("_nodes") as Array):
		var n = (nd as Dictionary).get("node", null)
		if n != null and is_instance_valid(n) and (n as Node).has_meta("macro_id") \
				and String((n as Node).get_meta("macro_id")) == MACRO_ID:
			decoy += 1
	_ok(decoy > 0 and listed.size() > decoy,
		"the id DECOY is really there: %d line_3a machines alongside the 3C spine (%d total) — criterion G is vacuous without them"
			% [decoy, listed.size()])
	_ok((lf.call("code_conflicts") as Array).is_empty(),
		"no L3C code was claimed twice across the two macros (%d conflict(s))"
			% (lf.call("code_conflicts") as Array).size())
	_dump["world"] = {
		"macros_built": [MACRO_3C, MACRO_ID], "machines": listed.size(),
		"decoy_line_3a_machines": decoy, "codes_live": codes.size(),
		"units_absent": absent,
	}


# =============================================================================
func _drive_line(lf) -> void:
	_section("RUN — power the line, FEED it, complete PLC stagger + rotor spin-up")
	lf.call("start_line")
	var injected := 0.0
	for _i in range(TICK_COUNT):
		injected += _feed_heads(lf, TICK_DT)
		lf.call("tick", TICK_DT)
	_ok(injected > 0.0,
		"FEED: %.1f kg injected at the line heads over %.1f s of sim time"
			% [injected, TICK_DT * float(TICK_COUNT)])
	# MEASURE the trip state rather than assuming the chosen feed avoided it: a
	# tripped high-load drive forces amps to 0 A and would silently defeat
	# criterion E's Stroom clause. Reported either way, never asserted away.
	var tripped : Array = []
	for nd in (lf.get("_nodes") as Array):
		var mol = (nd as Dictionary).get("mol", null)
		if mol != null and mol.has_method("is_tripped") and bool(mol.call("is_tripped")):
			tripped.append(String((nd as Dictionary)["id"]))
	if tripped.is_empty():
		_note("MotorOverload: no drive tripped at %.2f kg/s per head" % FEED_RATE)
	else:
		_note("MotorOverload TRIPPED at %.2f kg/s per head: %s — any bound Stroom on these reads 0 A"
			% [FEED_RATE, str(tripped)])
	_dump["feed_kg"] = injected
	_dump["motor_overload_tripped"] = tripped


func _feed_heads(lf, delta: float) -> float:
	var nodes : Array = lf.get("_nodes")
	var fed := 0.0
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if String(nd["role"]) == "sink":
			continue
		if bool(lf.call("_has_incoming", i)):
			continue
		var draw : float = FEED_RATE * delta
		(nd["in"] as MaterialBatch).add(MaterialBatch.new(
			draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "wl3c_feed",
			draw * 0.08, draw * 0.12))
		fed += draw
	return fed


# =============================================================================
func _exercise_screen(lf) -> void:
	_section("SCREEN — mount WashingScope (Waslijn 3C Overzicht) and bind it live")
	_line_flow_ref = lf

	var tm : TagMap = TagMapScript.new()
	var tmv : Dictionary = tm.validation()
	_ok(bool(tmv["ok"]),
		"TagMap validates against the operator export (%d tags, %d rows)"
			% [int(tmv["export_tags"]), int(tmv["mapped_tags"])])
	var export_tags : Dictionary = {}
	for r in tm.rows():
		export_tags[String(r["tag"])] = true

	var scope : Control = WashingScopeScript.new()
	get_tree().root.add_child(scope)
	# _process() also refreshes once a second; drive a few frames so the real
	# code path (not just the direct call) has run at least once.
	for _i in range(4):
		await get_tree().process_frame
	_ok(is_instance_valid(scope) and scope.get_child_count() > 0,
		"A: scope instantiates and builds a tree (%d children)" % scope.get_child_count())

	scope.call("bind", {}, lf)
	await get_tree().process_frame

	var failures := _audit(scope, export_tags, "LIVE")
	for f in failures:
		print("        [live] %s" % f)
	_ok(failures.is_empty(), "A-G: the LIVE screen is honest (%d violation(s))" % failures.size())

	var rep : Dictionary = scope.call("field_report")
	_dump["live_report"] = rep
	print("        bound=%d unavailable=%d total=%d (scope guards: %d / %d)"
		% [int(rep["bound_count"]), int(rep["unavailable_count"]), int(rep["total"]),
		   int(rep["expected_bound"]), int(rep["expected_unavailable"])])
	# Calibrated nominal per stage code, straight off the spine — printed NEXT TO
	# the live reading so the amps claim stays a measurement. The nominal is now
	# genuinely per-unit (each stamped stage seeds its own MotorOverload from it),
	# so a Stroom box reading exactly 0 A on a powered unit would be the old dead
	# calibrated path resurfacing.
	var nominal : Dictionary = {}
	for st in Line3CDef.STAGES:
		nominal[String((st as Dictionary)["code"])] = float((st as Dictionary)["amps"])
	for b in (rep["bound"] as Array):
		var br : Dictionary = b
		var extra := ""
		if String(br["field"]).begins_with("stroom:"):
			extra = "   [spine nominal %.2f A]" % float(nominal.get(String(br["code"]), 0.0))
		print("        BOUND  %-16s %-20s %-58s -> %s%s"
			% [String(br["field"]), String(br["machine_id"]), String(br["tag"]),
			   String(br["rendered"]), extra])

	# A bound Stroom reading EXACTLY 0 A while its unit is powered and its spine
	# nominal is non-zero was the l3c_code-unstamped signature. It is now an
	# ASSERTION rather than a note: with the code stamped there is no legitimate
	# way for a powered, metered unit to read zero except a MotorOverload trip,
	# which _drive_line measures and prints by name.
	var dead_amps : Array = []
	var powered_now : Dictionary = {}
	for b4 in (rep["bound"] as Array):
		var b4r : Dictionary = b4
		if String(b4r["field"]).begins_with("status:"):
			powered_now[String(b4r["code"])] = bool(b4r["value"])
	for b5 in (rep["bound"] as Array):
		var b5r : Dictionary = b5
		if not String(b5r["field"]).begins_with("stroom:"):
			continue
		var code5 := String(b5r["code"])
		if is_zero_approx(float(b5r["value"])) and float(nominal.get(code5, 0.0)) > 0.0 \
				and bool(powered_now.get(code5, false)):
			dead_amps.append("%s (spine %.2f A)" % [code5, float(nominal.get(code5, 0.0))])
	var tripped : Array = _dump.get("motor_overload_tripped", [])
	_ok(dead_amps.is_empty() or not tripped.is_empty(),
		"no bound Stroom reads 0 A on a powered, metered unit (%d do: %s) — this is where the dead calibrated amps path used to show through undisguised"
			% [dead_amps.size(), str(dead_amps)])
	# Distinctness on the SCREEN, not just in the sim: five friction separators
	# rendering one number is the visible face of the addressing defect.
	var stroom_vals : Dictionary = {}
	for b6 in (rep["bound"] as Array):
		var b6r : Dictionary = b6
		if String(b6r["field"]).begins_with("stroom:"):
			stroom_vals["%.4f" % float(b6r["value"])] = true
	_ok(stroom_vals.size() >= MIN_DISTINCT_STROOM,
		"the bound Stroom boxes render %d DISTINCT values (>= %d) — one instance per machine TYPE could not produce this"
			% [stroom_vals.size(), MIN_DISTINCT_STROOM])
	_dump["zero_amps_while_powered"] = dead_amps
	_dump["distinct_stroom_values"] = stroom_vals.size()

	# ── MUTATION 1 — dead source ─────────────────────────────────────────────
	_section("MUTATION 1 — rebind to a stub whose get_machine_info() returns {}")
	var dead := StubDeadSource.new()
	get_tree().root.add_child(dead)
	scope.call("bind", {}, dead)
	await get_tree().process_frame
	var m1 := _audit(scope, export_tags, "M1")
	var m1rep : Dictionary = scope.call("field_report")
	print("        bound=%d unavailable=%d" % [int(m1rep["bound_count"]), int(m1rep["unavailable_count"])])
	for f1 in m1:
		print("        [m1] %s" % f1)
	_ok(not m1.is_empty(),
		"MUTATION 1 goes RED: %d violation(s) with a dead data source" % m1.size())
	_ok(int(m1rep["bound_count"]) == 0 and int(m1rep["unavailable_count"]) == EXPECT_TOTAL,
		"MUTATION 1 collapses every field to unavailable (%d bound / %d unavailable)"
			% [int(m1rep["bound_count"]), int(m1rep["unavailable_count"])])
	_dump["mutation_1"] = {"violations": m1, "bound": int(m1rep["bound_count"]),
		"unavailable": int(m1rep["unavailable_count"])}
	dead.queue_free()

	# ── MUTATION 2 — correct keys, dead values ───────────────────────────────
	_section("MUTATION 2 — rebind to a stub with every key at its type default")
	var flat := StubDefaultValues.new()
	get_tree().root.add_child(flat)
	scope.call("bind", {}, flat)
	await get_tree().process_frame
	var m2 := _audit(scope, export_tags, "M2")
	var m2rep : Dictionary = scope.call("field_report")
	print("        bound=%d unavailable=%d" % [int(m2rep["bound_count"]), int(m2rep["unavailable_count"])])
	for f2 in m2:
		print("        [m2] %s" % f2)
	_ok(not m2.is_empty(),
		"MUTATION 2 goes RED: %d violation(s) with structurally-perfect dead values" % m2.size())
	# The point of M2: the SPLIT is still perfect, so only LIVENESS caught it.
	_ok(int(m2rep["bound_count"]) == EXPECT_BOUND and int(m2rep["unavailable_count"]) == EXPECT_UNAVAIL,
		"MUTATION 2 keeps the %d/%d split intact — so criterion B alone would have passed it"
			% [EXPECT_BOUND, EXPECT_UNAVAIL])
	var only_liveness := true
	for f2b in m2:
		if not String(f2b).begins_with("E:"):
			only_liveness = false
	_ok(only_liveness,
		"MUTATION 2 is caught by criterion E (LIVENESS) and nothing else — E is load-bearing")
	_dump["mutation_2"] = {"violations": m2, "bound": int(m2rep["bound_count"]),
		"unavailable": int(m2rep["unavailable_count"])}
	flat.queue_free()

	# Restore the live binding so the dump reflects the real screen.
	scope.call("bind", {}, lf)
	await get_tree().process_frame
	scope.queue_free()


## Criteria A-F as data. Returns a list of violation strings (empty == honest),
## so the SAME function can be asserted empty on the live run and NON-empty on
## each mutation. Anything else would be grading the mutation by hand.
func _audit(scope: Control, export_tags: Dictionary, _tag: String) -> Array:
	var out : Array = []
	var rep : Dictionary = scope.call("field_report")
	var bound : Array = rep["bound"]
	var unavail : Array = rep["unavailable"]

	# A — accounting
	if int(rep["total"]) != bound.size() + unavail.size():
		out.append("A: total %d != bound %d + unavailable %d" % [int(rep["total"]), bound.size(), unavail.size()])
	if int(rep["total"]) != EXPECT_TOTAL:
		out.append("A: total %d != documented %d" % [int(rep["total"]), EXPECT_TOTAL])
	var seen_keys : Dictionary = {}
	for r in bound + unavail:
		var k := String((r as Dictionary)["field"])
		if seen_keys.has(k):
			out.append("A: field %s accounted twice" % k)
		seen_keys[k] = true

	# B — split, against this file's own literals AND the scope's guards
	if bound.size() != EXPECT_BOUND:
		out.append("B: bound %d != documented %d" % [bound.size(), EXPECT_BOUND])
	if unavail.size() != EXPECT_UNAVAIL:
		out.append("B: unavailable %d != documented %d" % [unavail.size(), EXPECT_UNAVAIL])
	if int(rep["expected_bound"]) != EXPECT_BOUND or int(rep["expected_unavailable"]) != EXPECT_UNAVAIL:
		out.append("B: scope guards (%d/%d) drifted from this test's literals (%d/%d)"
			% [int(rep["expected_bound"]), int(rep["expected_unavailable"]), EXPECT_BOUND, EXPECT_UNAVAIL])

	# C — provenance
	for b in bound:
		var br : Dictionary = b
		var tag := String(br.get("tag", ""))
		if tag == "":
			out.append("C: bound field %s carries no tag" % String(br["field"]))
		elif not export_tags.has(tag):
			out.append("C: bound field %s cites tag %s which TagMap does not map" % [String(br["field"]), tag])
		if br.get("value", null) == null:
			out.append("C: bound field %s has a null value" % String(br["field"]))
		if String(br.get("source_field", "")).find("get_machine_info") < 0:
			out.append("C: bound field %s does not resolve through get_machine_info (%s)"
				% [String(br["field"]), String(br.get("source_field", ""))])

	# D — dict vs pixels
	for b2 in bound:
		var br2 : Dictionary = b2
		var painted := String(scope.call("rendered_text", String(br2["field"])))
		if painted == WashingScopeScript.UNAVAIL or painted == "":
			out.append("D: bound field %s paints \"%s\"" % [String(br2["field"]), painted])
	for uu in unavail:
		var ur : Dictionary = uu
		var painted_u := String(scope.call("rendered_text", String(ur["field"])))
		if painted_u != WashingScopeScript.UNAVAIL:
			out.append("D: unavailable field %s paints \"%s\", not \"%s\""
				% [String(ur["field"]), painted_u, WashingScopeScript.UNAVAIL])

	# E — liveness
	var status_bound := 0
	var status_true := 0
	var stroom_bound := 0
	var stroom_positive := 0
	var distinct : Dictionary = {}
	for b3 in bound:
		var br3 : Dictionary = b3
		if String(br3["field"]).begins_with("status:"):
			status_bound += 1
			if bool(br3["value"]):
				status_true += 1
		elif String(br3["field"]).begins_with("stroom:"):
			stroom_bound += 1
			var v := float(br3["value"])
			distinct["%.4f" % v] = true
			if v > 0.0:
				stroom_positive += 1
	if status_bound != EXPECT_BOUND_STATUS:
		out.append("E: %d bound status fields, documented %d" % [status_bound, EXPECT_BOUND_STATUS])
	if status_true < MIN_STATUS_TRUE:
		out.append("E: only %d of %d bound status fields read TRUE on a running line (need >= %d)"
			% [status_true, status_bound, MIN_STATUS_TRUE])
	if stroom_positive < 1:
		out.append("E: no bound Stroom reads > 0 A (%d bound)" % stroom_bound)
	if distinct.size() < MIN_DISTINCT_STROOM:
		out.append("E: bound Stroom values collapse to %d distinct number(s), need >= %d — a screen reading one instance per machine TYPE cannot reach this"
			% [distinct.size(), MIN_DISTINCT_STROOM])

	# F — reasons
	for u2 in unavail:
		var ur2 : Dictionary = u2
		if String(ur2.get("reason", "")).strip_edges() == "":
			out.append("F: unavailable field %s carries no reason" % String(ur2["field"]))

	# G — instance identity. Ask LineFlow directly for the code the screen claims
	# to be showing and check the machine that answers carries THAT code. This is
	# the check a first-match screen fails: in this world a Line 3A friction_sep
	# shares the id with five L3C units and would answer for all of them.
	if _line_flow_ref != null and is_instance_valid(_line_flow_ref) \
			and _line_flow_ref.has_method("get_machine_info"):
		var checked := 0
		for b4 in bound:
			var br4 : Dictionary = b4
			var code := String(br4.get("code", ""))
			if code == "":
				continue
			var info : Dictionary = _line_flow_ref.call("get_machine_info", code)
			checked += 1
			if info.is_empty():
				out.append("G: bound field %s — get_machine_info(\"%s\") returns nothing" % [String(br4["field"]), code])
			elif String(info.get("l3c_code", "")) != code:
				out.append("G: bound field %s resolves to a machine whose own code is \"%s\", not %s"
					% [String(br4["field"]), String(info.get("l3c_code", "")), code])
		if not bound.is_empty() and checked == 0:
			out.append("G: no bound field carried a code — the identity check ran on nothing")
	return out


# =============================================================================
# user:// file safety
# =============================================================================
func _guard_operator_saves() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for fn in dir.get_files():
		if not (fn.begins_with("allernieuwste_") and fn.ends_with(".json")):
			continue
		var f := FileAccess.open("user://" + fn, FileAccess.READ)
		if f:
			_guarded["user://" + fn] = f.get_as_text().sha256_text()
			f.close()

func _verify_operator_saves() -> void:
	var changed : Array = []
	for p in _guarded.keys():
		var f := FileAccess.open(p, FileAccess.READ)
		var h := f.get_as_text().sha256_text() if f else "<gone>"
		if f: f.close()
		if h != String(_guarded[p]):
			changed.append(p)
	if _guarded.is_empty():
		_note("no allernieuwste_*.json present to guard")
		_skip += 1
	else:
		_ok(changed.is_empty(), "operator allernieuwste_* saves byte-identical after the run (%d changed: %s)"
			% [changed.size(), str(changed)])

func _write_dump() -> void:
	var f := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_dump, "  "))
		f.close()
