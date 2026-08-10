extends Node3D
## QA LOOP — the graded quality assay on a REAL MainWorld boot.
##
##   godot --headless --path <proj> res://src/tests/test_qa_loop.tscn
##
## WHY THIS EXISTS SEPARATELY FROM test_qa_spec
## --------------------------------------------
## test_qa_spec is pure data and proves the arithmetic. CLAUDE.md Rule 3 says a
## bench green proves the mock and not the feature — npc-05 printed 31/31 while
## moving 0.00 kg. So this suite boots the real world, builds line_3c, runs it
## until the sink has actually banked granulaat, and only then takes a sample.
##
## WHAT IT PROVES
## --------------
## 1) NON-VACUITY: the line banked > 0 kg and discovered > 0 machines. Every
##    later check is meaningless without this, so it is asserted first.
## 2) take_product_sample() returns real material off the banked parcel.
## 3) The assay is NON-DESTRUCTIVE: ledger_residual() is unchanged across the
##    whole submit -> resolve cycle. This is the check that would catch someone
##    "improving" QaLab to split_mass() off the live batch — the conservation
##    invariant at LineFlow.gd:1893 is the project's hardest rule.
## 4) The bench delay is real against LineFlow's own clock: still pending part
##    way through, resolved once ticked past it.
## 5) Assessment scores the escaped kg between the REJECT verdict and the hold.
##
## Cleanup follows test_lump_cart_coverage: user:// files are backed up in
## memory and restored in _finish() BEFORE the verdict block, and the operator's
## allernieuwste_* saves are hashed and verified byte-identical.

const TEST_SLOT := "__qaloop__"
const TOUCHED := [
	"user://world_layout.json", "user://world_layout_consumed.flag",
	"user://__qaloop___save.json", "user://__qaloop___factory.json",
]
# Building-frame -> plant-coordinate affine, copied verbatim from
# src/tests/test_lump_cart_coverage.gd:38-40.
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)

const DT := 0.1
## Feed shape copied from test_tag_snapshot.gd:121-123 so both suites drive the
## line the same way — wet and dirty LDPE-dominant film, as it arrives off a bale.
const FEED_RATE    := 8.0
const FEED_DENSITY := 320.0
const FEED_COMP    := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}
## Material has to physically traverse the line before the sink banks anything:
## ProcessModel.WASH_RESIDENCE_S 600 + EXTRUDER_RESIDENCE_S 300, plus pipe
## transit. Ticking less than that guarantees 0 kg and a false failure.
const WARMUP_TICKS := 15000            # 1500 s of sim time

var _pass := 0
var _fail := 0
var _skip := 0
var _backups : Dictionary = {}
var _guarded : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1


func _note(msg: String) -> void:
	print("  note  : %s" % msg)


func _skip_msg(msg: String) -> void:
	print("  skip  : %s" % msg)
	_skip += 1


func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + BF_XU * bf.x + BF_ZU * bf.y


func _ready() -> void:
	print("=== QA LOOP — graded assay on a real MainWorld boot, ledger intact ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2)
		return
	_backup_files()
	_guard_operator_saves()

	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var world = load("res://src/scenes/world/MainWorld.tscn").instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame

	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if bm == null:
		_skip_msg("BuildMode unavailable — cannot place line_3c")
		_finish()
		return
	await _place_macro(bm, "line_3c", Vector2(0.0, 0.0))

	var lf = world.get("line_flow")
	if lf == null:
		lf = get_tree().get_first_node_in_group("line_flow")
	_ok(lf != null, "LineFlow resolved off MainWorld.line_flow (MainWorld.gd:24)")
	if lf == null:
		_finish()
		return

	# ── 1) non-vacuity ───────────────────────────────────────────────────────
	print("\n[1 — non-vacuity: the npc-05 guard]")
	# BuildMode places nodes, LineFlow only sees them after rebuild(). It must
	# come AFTER the awaited frames, not before — BuildMode finishes wiring at
	# the end of the frame, and rebuilding early leaves _nodes holding freed
	# Node3Ds (test_line3c_identity.gd:223-238 records both halves of this).
	lf.call("rebuild")
	lf.call("enable_qa", "3C", "TEST-SHIFT", null)
	# Machines boot unpowered (LineFlow.gd:612). start_line() runs the PLC
	# sequencer, which staggers the stages over TARGET_STARTUP_S — the warmup
	# ticks below cover that as well as the material residence time.
	lf.call("start_line")
	var injected := 0.0
	for _i in range(WARMUP_TICKS):
		injected += _feed_heads(lf, DT)
		lf.call("tick", DT)
	_ok(injected > 0.0, "injected %.1f kg at the line heads" % injected)
	var gran : float = float(lf.get("gran_mass"))
	var n_nodes : int = (lf.get("_nodes") as Array).size()
	_ok(n_nodes > 0, "%d machines discovered on the line" % n_nodes)
	_ok(gran > 0.0, "line banked %.2f kg granulaat — a green here is not vacuous" % gran)
	if gran <= 0.0:
		_note("no granulaat banked, so the assay checks below cannot mean anything")
		world.queue_free()
		_finish()
		return

	# ── 2) real sample ───────────────────────────────────────────────────────
	print("\n[2 — take_product_sample draws real material]")
	var before : float = float(lf.call("ledger_residual"))
	var lab = lf.call("qa_lab")
	_ok(lab != null, "LineFlow exposes qa_lab() after enable_qa()")
	var batch = lf.call("take_product_sample", 0.025)
	_ok(batch != null and batch.mass_kg > 0.0,
		"take_product_sample returned %.5f kg of banked granulaat"
			% (batch.mass_kg if batch != null else -1.0))
	if batch == null:
		world.queue_free()
		_finish()
		return

	# ── 3) bench delay against LineFlow's own clock ──────────────────────────
	print("\n[3 — the bench delay is real]")
	var sid : int = lab.submit_sample(batch, {"source_key": "L3C.18", "mfi": NAN})
	_ok(sid > 0, "sample %d on the bench" % sid)
	var half := int((lab.bench_delay_s * 0.5) / DT)
	for _i in range(half):
		lf.call("tick", DT)
	_ok(lab.pending_count() == 1,
		"still pending half way through (%.0f s of %.0f s)" % [lab.bench_delay_s * 0.5, lab.bench_delay_s])
	var rest := int((lab.bench_delay_s * 0.5) / DT) + 4
	for _i in range(rest):
		lf.call("tick", DT)
	var res : Dictionary = lab.result(sid)
	_ok(not res.is_empty(), "resolved after the full delay, verdict %s" % String(res.get("verdict", "—")))
	_ok(String(res.get("verdict", "")) != "ACCEPT",
		"NAN mfi did not grade ACCEPT on a real sample (got %s, reasons %s)"
			% [String(res.get("verdict", "—")), str(res.get("reasons", []))])

	# ── 4) the conservation invariant ────────────────────────────────────────
	print("\n[4 — the assay never touches the mass ledger]")
	var after : float = float(lf.call("ledger_residual"))
	_ok(absf(after - before) < 0.5,
		"ledger residual %.4f -> %.4f kg across the whole assay" % [before, after])

	# ── 5) assessment meters the escaped kg ──────────────────────────────────
	print("\n[5 — Assessment meters what escaped]")
	var asm = lf.call("assessment")
	_ok(asm != null, "LineFlow exposes assessment()")
	if asm != null:
		asm.add_rule({
			"id": "offspec_escaped", "kind": Assessment.RuleKind.QUANTITY_ESCAPED,
			"weight": 100.0,
			"arm_kind": "qa_sample_ready", "arm_when": {"verdict": "REJECT"},
			"meter_kind": "mass_banked", "meter_field": "kg",
			"disarm_kind": "operator_decision", "disarm_when": {"action": "hold"},
			"budget_kg": 250.0,
		})
		asm.observe(Assessment.event("3C", "TEST-SHIFT", "qa_sample_ready",
			{"sample_id": sid, "verdict": "REJECT"}, 0.0))
		asm.observe(Assessment.event("3C", "TEST-SHIFT", "mass_banked", {"kg": 60.0}, 5.0))
		asm.observe(Assessment.event("3C", "TEST-SHIFT", "operator_decision",
			{"sample_id": sid, "action": "hold"}, 9.0))
		asm.observe(Assessment.event("3C", "TEST-SHIFT", "mass_banked", {"kg": 900.0}, 20.0))
		var sc : Dictionary = asm.score()
		var esc : float = float((sc["rules"] as Array)[0]["value"])
		_ok(is_equal_approx(esc, 60.0),
			"metered %.1f kg escaped — only what was banked before the hold" % esc)
		_ok(int(sc["counts"]["dropped_wrong_line"]) == 0
				and int(sc["counts"]["dropped_wrong_session"]) == 0,
			"no events dropped on the live line/session key")

	_note("spec %s, %d limits still needing an operator number"
		% [lab.spec.spec_id, lab.spec.needs_operator_count()])
	_note("lab stats: %s" % str(lab.stats()))

	world.queue_free()
	_verify_operator_saves()
	_finish()


## Push material into every head node (no incoming edge, not a sink). Copied
## from test_tag_snapshot.gd:_feed_heads so both suites feed identically.
## Note this bypasses the physical-bale path, so LineFlow.fed_mass stays 0 and
## the injected mass shows up as ledger residual — which is why check 4 compares
## the residual BEFORE and AFTER the assay rather than against zero.
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
			draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "qaloop_feed",
			draw * 0.08, draw * 0.12))
		fed += draw
	return fed


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


func _backup_files() -> void:
	for p in TOUCHED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f:
				f.close()
		else:
			_backups[p] = null


func _restore_files() -> void:
	for p in _backups.keys():
		var orig = _backups[p]
		if orig is String:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f:
				f.store_string(orig)
				f.close()
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("  (restored touched user:// files)")


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
		if f:
			f.close()
		if h != String(_guarded[p]):
			changed.append(p)
	if not _guarded.is_empty():
		_ok(changed.is_empty(),
			"operator allernieuwste_* saves byte-identical after the run (%d changed: %s)"
				% [changed.size(), str(changed)])


## A run that asserted nothing is a FAILURE, not a pass. CLAUDE.md Rule 3: "a
## 0/0 suite, or a skip, is not a pass." This suite exists specifically to prove
## the assay on real material, so if it bailed before running a single check —
## no BuildMode, no LineFlow, no granulaat — the honest verdict is red. An
## earlier version of this function printed PASS on 0 ok / 0 fail / 1 skip,
## which is the exact vacuous green the rule warns about.
func _finish() -> void:
	_restore_files()
	var vacuous := _pass == 0
	if vacuous:
		print("  FAIL  : suite asserted nothing (%d ok, %d skip) — a 0/0 run is not a pass" % [_pass, _skip])
		_fail += 1
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
