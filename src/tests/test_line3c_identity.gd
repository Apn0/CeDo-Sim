extends Node3D
## LINE 3C IDENTITY — does per-instance addressing actually make the calibrated
## currents real, per machine?
##
##   godot --headless --path <proj> res://src/tests/test_line3c_identity.tscn
##
## Boots the REAL MainWorld and places the `line_3c` macro (BuildMode.LINE_3C_SEQ,
## transcribed from Line3CDef.STAGES). A BENCH GREEN IS WORTHLESS HERE — this
## project shipped npc-05 printing 31/31 while moving zero kg against its own
## stub, so nothing below runs against a stand-in.
##
## THE QUESTION IT ANSWERS
## -----------------------
## Before this work, `l3c_code` was stamped on 0 of 47 nodes, so
## sum(amps_nominal) was 0.00 A against ProcessModel.line_nominal_amps() 488.49 A:
## the whole calibrated amps path (LineFlow.gd:467-482 -> ProcessModel.gd:38-42)
## was dead, and the only writer of nd["amps"] was MotorOverload seeded from its
## PLACEHOLDER 90.0 A default. One placeable id mapped to up to five different
## L3C units, so no scheme keyed on the id could ever have fixed it.
##
## TWO CORRECTIONS TO THE OBVIOUS FORMULATION, both verified in source. Grading
## against the naive wording would mark a CORRECT fix as failed:
##
##  C1. "the five friction separators must read five DIFFERENT currents" is not
##      reachable from the source data. Line3CDef.gd:62 and :63 give L3C.4L and
##      L3C.4R the SAME 29.92 A. Five instances yield FOUR distinct values; an
##      implementation producing five distinct numbers has invented one. The
##      correct claim, and what is asserted here, is that each instance reads ITS
##      OWN nominal: 29.92 / 29.92 / 28.03 / 30.88 / 24.68.
##
##  C2. "L3C.14L must read 70.80 A" holds only at load_frac >= 1.0.
##      ProcessModel.stage_amps (ProcessModel.gd:38-42) returns
##      idle + (hmi - idle) * load with MOTOR_IDLE_FRAC 0.35 (:29) — 24.78 A at
##      zero load. And on friction_sep the literal never lands in nd["amps"] at
##      all: it matches _is_high_load_motor (LineFlow.gd:594-598) so MotorOverload
##      OVERWRITES the key every tick (LineFlow.gd:2269-2275). So the LITERALS are
##      asserted on amps_nominal (exact, load-independent) and the LIVE amps are
##      asserted against the formula, its own seed, and distinctness.
##
## user:// SAFETY: every file this test can touch is byte-backed-up and restored,
## and the operator's allernieuwste_* saves are hash-checked before and after.

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")
const ProcessModelScript = preload("res://src/sim/ProcessModel.gd")

# ── Building frame (bf) — the same fitted frame regression_world_save.gd and
# test_tag_snapshot.gd use.
# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")

const TEST_SLOT := "__l3cident__"
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const TOUCHED := [
	"user://world_layout_consumed.flag",
	"user://__l3cident___save.json", "user://__l3cident___factory.json",
]
const DUMP_PATH := "user://line3c_identity.json"

const MACRO_ID := "line_3c"
const LINE_START_BF := Vector2(4.0, 22.0)

const TICK_DT := 0.1
const TICK_COUNT := 400
## Per-head charge, kg/s. Line3CDef.LINE_SPEED_KG_H is 1687 kg/h (Line3CDef.gd:50)
## = 0.4686 kg/s, so this runs the spine at its own DESIGN rate rather than at an
## arbitrary number. A pure 3C world has exactly one head (the Doseer Silo), so
## this is also the whole line's intake. Not saturated on purpose: a MotorOverload
## trip zeroes the very currents under test. The trip state is MEASURED every run
## (see _drive_line), never assumed away.
const FEED_RATE := 0.4686
const FEED_DENSITY := 320.0
const FEED_COMP := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}

## The five friction separators and their calibrated full-load currents, straight
## off the spine. FOUR distinct values — see C1 above.
const FRICTION_CODES : Array = ["L3C.4L", "L3C.4R", "L3C.9L", "L3C.9R", "L3C.13"]
const FRICTION_LINES : Array = [62, 63, 67, 68, 73]      # Line3CDef.gd line numbers
const DRYER_CODES : Array = ["L3C.14L", "L3C.14R"]
const DRYER_LINES : Array = [77, 78]
const AMP_EPS := 0.0001

## THE LITERALS, TRANSCRIBED BY HAND from Line3CDef.gd:62,63,67,68,73 and :77,78.
## An INDEPENDENT copy on purpose. Checking amps_nominal against
## ProcessModel.hmi_amps_for_code() alone is TAUTOLOGICAL: that function reads the
## same STAGES table LineFlow read, so it proves the value was copied faithfully
## and says nothing about WHICH value. Mutation-proven — keying the currents by
## PLACEABLE ID (the fake fix, every friction_sep reading 29.92 A) left the
## hmi_amps_for_code comparison GREEN and was caught only by distinctness. These
## constants close that hole: they are the acceptance numbers themselves, and they
## must be re-read off Line3CDef by a human if the plant data ever changes.
const FRICTION_AMPS : Array = [29.92, 29.92, 28.03, 30.88, 24.68]
const DRYER_AMPS : Array = [70.80, 63.51]

var _pass := 0
var _fail := 0
var _skip := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, TOUCHED)
var _guarded : Dictionary = {}
var _dump : Dictionary = {}


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1

func _note(msg: String) -> void:
	print("  note  : %s" % msg)

func _section(t: String) -> void:
	print("\n[%s]" % t)



func _ready() -> void:
	print("=== LINE 3C IDENTITY — calibrated currents, per instance (measured) ===")
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
	await _assert_round_trip(bm, lf)
	_drive_line(lf)
	_assert_identity(lf)

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
func _build_world(bm, lf) -> void:
	_section("WORLD — the line_3c macro from its clean seed")
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[MACRO_ID] = {}

	var fr : Dictionary = await BFrame.wait_fitted(bm)
	_ok(not fr.is_empty(), "building frame FITTED from the shell (InteriorLightingManager)")
	if fr.is_empty():
		return
	var start : Vector3 = BFrame.to_scene(fr, LINE_START_BF, Plant.floor_top_y())
	bm.call("_build_full_line", MACRO_ID, start, BFrame.forward_rot_y(fr))
	for _i in range(10):
		await get_tree().process_frame
	lf.call("rebuild")
	for _i in range(10):
		await get_tree().process_frame

	var listed : Array = lf.call("machine_list")
	# Bound on the entries LineFlow CAN discover: it drops every MachineFlow
	# role-"none" id. Until 2026-09-25 the 3C furniture tail (1 lump platform,
	# 2 spots, 2 carts) defaulted to role "process", so all 37 entries were
	# flow nodes and the raw SEQ size worked as the bound; with that furniture
	# at role none the line builds 32 (docs/audit/cycle_guard_swap_2026-09-25.md).
	var flow_entries := 0
	for e in BuildMode.LINE_3C_SEQ:
		if String(MachineFlow.profile(String((e as Dictionary).get("id", ""))).get("role", "")) != "none":
			flow_entries += 1
	_ok(listed.size() >= flow_entries and flow_entries > 0,
		"the macro really built: %d LineFlow machines for %d flow SEQ entries (%d SEQ entries in all)"
			% [listed.size(), flow_entries, BuildMode.LINE_3C_SEQ.size()])
	_dump["machines"] = listed.size()


# =============================================================================
## MIGRATION / PERSISTENCE. The plant address is DERIVED at discovery time from
## macro_id + macro_index, two metas BuildMode already wrote, persisted and
## restored long before this work (BuildMode.gd:1627-1628 / :2625-2628 /
## :3023-3026). So the save FORMAT is unchanged: no new key is written, none is
## read that a legacy file lacks, LAYOUT_VERSION is NOT bumped (bumping it wipes
## every pre-patch save by design, BuildMode.gd:50), and an old save loads and
## behaves exactly as before — its 3A/3B machines simply derive no code.
##
## That is a claim about persistence, so it is MEASURED here rather than argued:
## save the built world, clear it, load it back, and require all 32 codes to
## return. A derivation that only worked at placement time — e.g. one restored
## AFTER the rebuild that reads it — would come back empty.
func _assert_round_trip(bm, lf) -> void:
	_section("MIGRATION — the derived codes survive save -> clear -> reload")
	if not (bm.has_method("_save_layout") and bm.has_method("load_layout")):
		_note("BuildMode._save_layout / load_layout missing — round-trip skipped")
		_skip += 1
		return
	var before : Dictionary = {}
	for e in (lf.call("machine_list") as Array):
		var c := String((e as Dictionary).get("l3c_code", ""))
		if c != "":
			before[c] = true
	bm.call("_save_layout")
	# Clear the way BuildMode's own delete path does: free the machines, then
	# rebuild() IMMEDIATELY (BuildMode.gd:2081, 2170, 2201 all pair the two).
	# Skipping the rebuild leaves _nodes holding freed Node3Ds, which is a real
	# hazard rather than a test artefact — see the guard added at LineFlow's head
	# feed loop, which this round-trip is what found.
	var placed_root = bm.get("_placed_root")
	var freed := 0
	if placed_root != null and is_instance_valid(placed_root):
		for ch in (placed_root as Node).get_children():
			ch.queue_free()
			freed += 1
	# queue_free is DEFERRED — the nodes leave the "placed_object" group at the end
	# of the frame, so rebuild() must come AFTER the frames, not before, or it
	# re-discovers the very machines being freed.
	for _i in range(8):
		await get_tree().process_frame
	lf.call("rebuild")
	for _i in range(2):
		await get_tree().process_frame
	# Assert on the CODES, not on the machine count: clearing BuildMode's placed
	# root cannot remove machines that never lived there (MainWorld spawns a couple
	# of fixed units of its own), and demanding an empty world would be asserting
	# something this clear does not do. Every coded 3C stage must be gone, though —
	# that is what makes the reload check below non-vacuous.
	var left_codes : Array = []
	var left_total : int = 0
	for e_l in (lf.call("machine_list") as Array):
		left_total += 1
		var lc := String((e_l as Dictionary).get("l3c_code", ""))
		if lc != "":
			left_codes.append(lc)
	_ok(freed > 0 and left_codes.is_empty(),
		"the 3C spine was really CLEARED before reloading (%d freed, 0 of %d remaining machines still carries a code; %d do: %s)"
			% [freed, left_total, left_codes.size(), str(left_codes)])
	if left_total > 0:
		_note("%d machine(s) survive the clear because they are not children of BuildMode._placed_root (MainWorld's own fixed equipment) — none of them is a 3C stage" % left_total)
	bm.call("load_layout")
	for _i in range(12):
		await get_tree().process_frame
	lf.call("rebuild")
	for _i in range(8):
		await get_tree().process_frame
	var after : Dictionary = {}
	for e2 in (lf.call("machine_list") as Array):
		var c2 := String((e2 as Dictionary).get("l3c_code", ""))
		if c2 != "":
			after[c2] = true
	var lost : Array = []
	for k in before.keys():
		if not after.has(String(k)):
			lost.append(String(k))
	_ok(before.size() == Line3CDefScript.stage_count(),
		"before the round-trip the world really held all %d codes (%d) — 0 -> 0 would pass the next check for free"
			% [Line3CDefScript.stage_count(), before.size()])
	_ok(lost.is_empty() and after.size() == before.size(),
		"every derived l3c_code survives save -> reload (%d before, %d after, %d lost: %s) — no new save key, no migration"
			% [before.size(), after.size(), lost.size(), str(lost)])
	_dump["round_trip"] = {"codes_before": before.size(), "codes_after": after.size(), "lost": lost}


# =============================================================================
func _drive_line(lf) -> void:
	_section("RUN — power the line and FEED it (amps are 0 on a stopped line)")
	lf.call("start_line")
	var injected := 0.0
	for _i in range(TICK_COUNT):
		injected += _feed_heads(lf, TICK_DT)
		lf.call("tick", TICK_DT)
	_ok(injected > 0.0, "FEED: %.1f kg injected over %.1f s of sim time"
		% [injected, TICK_DT * float(TICK_COUNT)])
	var tripped : Array = []
	for nd in (lf.get("_nodes") as Array):
		var mol = (nd as Dictionary).get("mol", null)
		if mol != null and mol.has_method("is_tripped") and bool(mol.call("is_tripped")):
			tripped.append(String((nd as Dictionary).get("key", "")))
	if tripped.is_empty():
		_note("MotorOverload: no drive tripped at %.2f kg/s per head" % FEED_RATE)
	else:
		_note("MotorOverload TRIPPED: %s — a tripped drive reads 0 A by design" % str(tripped))
	_dump["feed_kg"] = injected
	_dump["tripped"] = tripped


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
			draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "l3c_ident_feed",
			draw * 0.08, draw * 0.12))
		fed += draw
	return fed


# =============================================================================
func _nodes_by_code(lf) -> Dictionary:
	var out : Dictionary = {}
	for nd in (lf.get("_nodes") as Array):
		var c := String((nd as Dictionary).get("l3c_code", ""))
		if c != "":
			out[c] = nd
	return out


func _assert_identity(lf) -> void:
	_section("A3.1 — every stage is its OWN unit")
	var nodes : Array = lf.get("_nodes")
	var by_code := _nodes_by_code(lf)

	# Non-vacuity first: 0 stamped nodes would satisfy every "no duplicate" claim.
	var stamped : int = by_code.size()
	_ok(stamped == Line3CDefScript.stage_count(),
		"l3c_code stamped on %d nodes == Line3CDef.stage_count() %d"
			% [stamped, Line3CDefScript.stage_count()])
	_ok((lf.call("code_conflicts") as Array).is_empty(),
		"no l3c_code was claimed twice (%d conflict(s): %s)"
			% [(lf.call("code_conflicts") as Array).size(), str(lf.call("code_conflicts"))])

	# Every node uniquely addressable, and the resolver reaches the node that
	# ANSWERED — identity, not merely non-emptiness (the vacuous version).
	var listed : Array = lf.call("machine_list")
	var keys : Dictionary = {}
	var blank_keys := 0
	for e in listed:
		var k := String((e as Dictionary).get("key", ""))
		if k == "":
			blank_keys += 1
		keys[k] = true
	_ok(blank_keys == 0 and keys.size() == listed.size(),
		"every one of %d machine_list rows has a DISTINCT non-empty key (%d distinct, %d blank)"
			% [listed.size(), keys.size(), blank_keys])
	var wrong_instance : Array = []
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var info : Dictionary = lf.call("get_machine_info", String(nd.get("key", "")))
		if info.is_empty() or String(info.get("key", "")) != String(nd.get("key", "")):
			wrong_instance.append(String(nd.get("key", "")))
	_ok(wrong_instance.is_empty(),
		"get_machine_info(key) resolves to THAT node for all %d machines (%d wrong: %s)"
			% [nodes.size(), wrong_instance.size(), str(wrong_instance).substr(0, 200)])

	var fr_set : Dictionary = {}
	var fr_missing : Array = []
	for c in FRICTION_CODES:
		if by_code.has(String(c)):
			fr_set[String(c)] = true
		else:
			fr_missing.append(String(c))
	var fr_nodes := 0
	for nd2 in nodes:
		if String((nd2 as Dictionary).get("id", "")) == "friction_sep":
			fr_nodes += 1
	_ok(fr_nodes == FRICTION_CODES.size() and fr_missing.is_empty(),
		"exactly %d friction_sep nodes, carrying the code SET %s (%d missing: %s)"
			% [FRICTION_CODES.size(), str(FRICTION_CODES), fr_missing.size(), str(fr_missing)])

	# ── A3.2 the calibrated nominal, per instance, EXACT ─────────────────────
	_section("A3.2/A3.3 — amps_nominal per instance, against Line3CDef literals")
	var nominal_mismatch : Array = []
	var fr_nominals : Array = []
	var fr_distinct : Dictionary = {}
	for ci in FRICTION_CODES.size():
		var code := String(FRICTION_CODES[ci])
		if not by_code.has(code):
			# An absent code must FAIL here too, not skip: a mutation that stops
			# stamping would otherwise leave this loop iterating over nothing and
			# reporting "0 mismatch" — the vacuous green this project keeps shipping.
			nominal_mismatch.append("%s: absent from the world" % code)
			continue
		var nd3 : Dictionary = by_code[code]
		# TWO independent expectations. The literal is the load-bearing one; the
		# hmi_amps_for_code() lookup is kept because a disagreement between them
		# means the spine table itself moved and this file is now stale.
		var want : float = float(FRICTION_AMPS[ci])
		var via_pm : float = ProcessModelScript.hmi_amps_for_code(code)
		var got : float = float(nd3.get("amps_nominal", 0.0))
		fr_nominals.append(got)
		fr_distinct["%.4f" % got] = true
		if absf(got - want) > AMP_EPS:
			nominal_mismatch.append("%s: %.2f != the transcribed literal %.2f (Line3CDef.gd:%d)"
				% [code, got, want, int(FRICTION_LINES[ci])])
		if absf(via_pm - want) > AMP_EPS:
			nominal_mismatch.append("%s: ProcessModel.hmi_amps_for_code says %.2f but Line3CDef.gd:%d reads %.2f — the spine table moved, re-transcribe FRICTION_AMPS"
				% [code, via_pm, int(FRICTION_LINES[ci]), want])
		print("        %s  amps_nominal %6.2f A   [Line3CDef.gd:%d]" % [code, got, int(FRICTION_LINES[ci])])
	_ok(nominal_mismatch.is_empty(),
		"each friction_sep carries ITS OWN calibrated nominal — %s A, against the HAND-TRANSCRIBED literals, not against the same table LineFlow read (%d mismatch: %s)"
			% [str(FRICTION_AMPS), nominal_mismatch.size(), str(nominal_mismatch)])
	# C1: the source data gives 4L and 4R the SAME 29.92 A. FOUR distinct values
	# is the correct answer; five would mean a number was invented.
	_ok(fr_distinct.size() == 4,
		"the five friction nominals hold %d DISTINCT values — 4 is correct (L3C.4L and L3C.4R are both 29.92 A, Line3CDef.gd:62-63); 5 would be an invented number"
			% fr_distinct.size())
	_dump["friction_amps_nominal"] = fr_nominals

	var dryer_mismatch : Array = []
	for di in DRYER_CODES.size():
		var dcode := String(DRYER_CODES[di])
		if not by_code.has(dcode):
			dryer_mismatch.append("%s absent" % dcode)
			continue
		var dnd : Dictionary = by_code[dcode]
		var dwant : float = float(DRYER_AMPS[di])          # hand-transcribed literal
		var d_via_pm : float = ProcessModelScript.hmi_amps_for_code(dcode)
		var dgot : float = float(dnd.get("amps_nominal", 0.0))
		if absf(dgot - dwant) > AMP_EPS:
			dryer_mismatch.append("%s: %.2f != the transcribed literal %.2f (Line3CDef.gd:%d)"
				% [dcode, dgot, dwant, int(DRYER_LINES[di])])
		if absf(d_via_pm - dwant) > AMP_EPS:
			dryer_mismatch.append("%s: ProcessModel.hmi_amps_for_code says %.2f but Line3CDef.gd:%d reads %.2f — re-transcribe DRYER_AMPS"
				% [dcode, d_via_pm, int(DRYER_LINES[di]), dwant])
		print("        %s amps_nominal %6.2f A   [Line3CDef.gd:%d]" % [dcode, dgot, int(DRYER_LINES[di])])
	_ok(dryer_mismatch.is_empty(),
		"L3C.14L reads 70.80 A nominal and L3C.14R 63.51 A (%d mismatch: %s) — both were 0.00 A before"
			% [dryer_mismatch.size(), str(dryer_mismatch)])

	# ── A3.4 LIVE amps on the friction separators ────────────────────────────
	_section("A3.4 — live amps on the high-load drives (MotorOverload writes these)")
	var mol_seed_bad : Array = []
	var amps_bad : Array = []
	var fr_live : Array = []
	var fr_live_distinct : Dictionary = {}
	for c2 in FRICTION_CODES:
		var code2 := String(c2)
		if not by_code.has(code2):
			mol_seed_bad.append("%s: absent from the world" % code2)
			amps_bad.append("%s: absent from the world" % code2)
			continue
		var nd4 : Dictionary = by_code[code2]
		var mol = nd4.get("mol", null)
		var a : float = float(nd4.get("amps", 0.0))
		fr_live.append(a)
		fr_live_distinct["%.4f" % a] = true
		if mol == null:
			mol_seed_bad.append("%s has no MotorOverload" % code2)
		else:
			# The seed is what made the old numbers fictitious: amps_nominal was 0,
			# so LineFlow.gd:678-680 fell back to MotorOverload's 90.0 A default.
			if absf(float(mol.get("nominal_amps")) - float(nd4.get("amps_nominal", 0.0))) > AMP_EPS:
				mol_seed_bad.append("%s: mol nominal %.2f != stage nominal %.2f"
					% [code2, float(mol.get("nominal_amps")), float(nd4.get("amps_nominal", 0.0))])
			if absf(a - float(mol.get("current_amps"))) > 0.001:
				amps_bad.append("%s: nd amps %.4f != mol current %.4f"
					% [code2, a, float(mol.get("current_amps"))])
		print("        %s  live %7.3f A  (mol nominal %6.2f A)"
			% [code2, a, float(mol.get("nominal_amps")) if mol != null else -1.0])
	_ok(mol_seed_bad.is_empty(),
		"every friction_sep MotorOverload is seeded from ITS OWN calibrated nominal, not the 90.0 A placeholder (%d bad: %s)"
			% [mol_seed_bad.size(), str(mol_seed_bad)])
	_ok(amps_bad.is_empty(),
		"nd[\"amps\"] equals that node's own MotorOverload current (%d mismatch: %s)"
			% [amps_bad.size(), str(amps_bad)])
	_ok(fr_live_distinct.size() >= 4,
		"the five live friction currents hold %d DISTINCT values (>= 4 required — one per distinct nominal); a single shared number is the defect this work removes"
			% fr_live_distinct.size())
	_dump["friction_amps_live"] = fr_live

	# ── A3.5 the dryer pair — the calibrated path with NO second writer ───────
	_section("A3.5 — L3C.14L: the stage where the calibrated path shows undisguised")
	var probe : float = ProcessModelScript.stage_amps(70.80, 1.0, true)
	_ok(absf(probe - 70.80) <= 0.001,
		"formula alive: ProcessModel.stage_amps(70.80, load 1.0, running) = %.4f A (the literal is a FULL-LOAD figure, ProcessModel.gd:38-42)" % probe)
	var d14l : Dictionary = by_code.get("L3C.14L", {})
	var d14r : Dictionary = by_code.get("L3C.14R", {})
	if d14l.is_empty() or d14r.is_empty():
		_ok(false, "L3C.14L / L3C.14R present in the world")
	else:
		var a14l : float = float(d14l.get("amps", 0.0))
		var a14r : float = float(d14r.get("amps", 0.0))
		# mech_dryer does NOT match _is_high_load_motor, so nothing overwrites the
		# calibrated value — this node reads exactly what stage_amps computed.
		var rate14 : float = float(d14l.get("rate", 0.0))
		var load14 : float = clampf(float(d14l.get("thru", 0.0)) / rate14, 0.0, 1.25) if rate14 > 0.0 else 0.0
		var want14 : float = ProcessModelScript.stage_amps(
			float(d14l.get("amps_nominal", 0.0)), load14, float(d14l.get("spin", 0.0)) > 0.1)
		print("        L3C.14L live %.4f A  (nominal %.2f A, load %.4f, spin %.2f)"
			% [a14l, float(d14l.get("amps_nominal", 0.0)), load14, float(d14l.get("spin", 0.0))])
		print("        L3C.14R live %.4f A  (nominal %.2f A)" % [a14r, float(d14r.get("amps_nominal", 0.0))])
		_ok(a14l > 0.0,
			"L3C.14L draws %.4f A — it read EXACTLY 0.00 A before, because amps_nominal was 0" % a14l)
		_ok(absf(a14l - want14) <= 0.001,
			"L3C.14L matches ProcessModel.stage_amps(nominal, measured load, spinning) = %.4f A (no second writer on a mech_dryer)" % want14)
		_ok(not is_equal_approx(a14l, a14r),
			"L3C.14L %.4f A != L3C.14R %.4f A — the pair is addressed as two machines, not one"
				% [a14l, a14r])
		_ok(String(d14l.get("pair_id", "")) == "dryer_pair"
				and String(d14l.get("pair_side", "")) == "L"
				and String(d14r.get("pair_side", "")) == "R",
			"the MechDryerCycle pair tags are live (pair_id \"%s\", sides \"%s\"/\"%s\") — pair_id was \"\" on all 47 nodes before"
				% [String(d14l.get("pair_id", "")), String(d14l.get("pair_side", "")),
					String(d14r.get("pair_side", ""))])
		_dump["dryer"] = {"L3C.14L": a14l, "L3C.14R": a14r}

	# ── A3.6 the line total ──────────────────────────────────────────────────
	_section("A3.6 — the line total the '~488 A' comment was about")
	var sum_nominal := 0.0
	for nd5 in nodes:
		sum_nominal += float((nd5 as Dictionary).get("amps_nominal", 0.0))
	var line_nominal : float = ProcessModelScript.line_nominal_amps()
	var live : float = float(lf.call("live_line_amps"))
	print("        sum(amps_nominal) %.2f A   ProcessModel.line_nominal_amps() %.2f A   live_line_amps %.2f A"
		% [sum_nominal, line_nominal, live])
	_ok(absf(sum_nominal - line_nominal) <= 0.01,
		"sum(amps_nominal) %.2f A == ProcessModel.line_nominal_amps() %.2f A — it was 0.00 A before"
			% [sum_nominal, line_nominal])
	_ok(live > 0.0, "live_line_amps %.2f A > 0 on a running, fed 3C line" % live)
	_dump["amps"] = {"sum_nominal": sum_nominal, "line_nominal": line_nominal, "live": live}

	# ── A3.7 stamping ALSO swaps the material-transfer coefficients ──────────
	# LineFlow.gd:474-481 replaces MachineFlow's water/contam/reject/waste with
	# ProcessModel.stage_transfer on every coded node, and switches on the dryer
	# pair controller. Neither may create or destroy mass.
	_section("A3.7 — mass ledger under the newly-live ProcessModel coefficients")
	# MEASURED CORRECTION, not a loosened tolerance. ledger_residual() is
	# fed_mass + water_added - (out + in-transit) (LineFlow.gd:1748-1751), and
	# LineFlow.fed_mass is incremented ONLY on the physical-bale path
	# (LineFlow.gd:1895), which a headless world never runs — test_tag_snapshot.gd
	# records the same thing at :313. This test charges the head batches directly,
	# so its own injected mass is invisible to fed_mass and shows up as a residual
	# exactly equal to -injected. The quantity that actually has to balance is
	# ledger_residual() + injected; a real leak moves THAT, and the raw residual is
	# printed next to it so the correction cannot hide one.
	var residual : float = float(lf.call("ledger_residual"))
	var injected : float = float(_dump.get("feed_kg", 0.0))
	var balanced : float = residual + injected
	var tol : float = maxf(0.05, 0.01 * injected)
	print("        ledger_residual %.4f kg ; injected %.4f kg (not counted by fed_mass) ; corrected %.6f kg (tolerance %.4f kg)"
		% [residual, injected, balanced, tol])
	_ok(injected > 0.0 and absf(balanced) <= tol,
		"mass ledger balances under the newly-live ProcessModel coefficients: %.6f kg residual over %.2f kg charged (<= %.4f kg)"
			% [balanced, injected, tol])
	_dump["ledger_residual"] = residual
	_dump["ledger_residual_corrected"] = balanced


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
