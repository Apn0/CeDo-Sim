extends Node3D
## LINE 3B LEDGER — mass conservation, on a REAL MainWorld boot.
##
##   godot --headless --path <proj> res://src/tests/test_line3b_identity.tscn
##
## docs/audit/material_trace_2026-08-18.md found that LineFlow.ledger_residual()
## — fed_mass + water_added - (gran+waste+contam+water_removed+poly_rejected) -
## in_transit — was asserted for line_3c ONLY (test_line3c_identity.gd). Macros
## exist for line_3a, line_3b, line_1, line_sort, line_intake_3a3b and none of
## them proved conservation. This file closes that gap for line_3b, mirroring
## test_line3c_identity.gd's structure (same MainWorld boot, same touched-file
## backup/restore, same drive-and-measure loop, same documented tolerance).
##
## line_3b has no Line3BDef.gd (unlike line_3c/Line3CDef.gd) — no per-stage HMI
## amps/current table was ever transcribed for this line, so this file makes NO
## per-instance identity or amps_nominal claims. It asserts exactly what the
## audit said was missing: the mass ledger.
##
## FEED RATE, TRACED: docs/plant/misc_sources.md line 190, from the operator's
## own CEDO.xlsx ("Extruder output | 1000kg/u | nominal extruder output 1000
## kg/h — matches docx '1,000 kg/h goal'"), and line 206/246: "That flake stream
## splits across the two extruder lines [3A and 3B] at ~1000-1050 kg/h each".
## 1000 kg/h is therefore the documented per-line design rate for BOTH 3A and
## 3B — not invented, not borrowed from 3C's own 1687 kg/h (which is 3C-specific,
## Line3CDef.gd:5/50). FEED_DENSITY and FEED_COMP are LineFlow's OWN generic
## feed constants (LineFlow.gd:31/40, `FEED_DENSITY` and `DEFAULT_COMP`) — the
## same numbers LineFlow itself uses on the physical-bale feed path, not new
## invented figures.
##
## user:// SAFETY: every file this test can touch is byte-backed-up and restored,
## and the operator's allernieuwste_* saves are hash-checked before and after.

const TEST_SLOT := "__l3bident__"
const TOUCHED := [
	"user://world_layout.json", "user://world_layout_consumed.flag",
	"user://__l3bident___save.json", "user://__l3bident___factory.json",
]
const DUMP_PATH := "user://line3b_identity.json"

const MACRO_ID := "line_3b"

# ── Building frame (bf) -> Plant Coordinates affine — same constants
# regression_world_save.gd / test_tag_snapshot.gd / test_line3c_identity.gd use.
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)
# Anchor matches test_lump_cart_coverage.gd's LINES["line_3b"] so this stays
# clear of every other test's synthetic line at the same 20-bf-unit spacing.
const LINE_START_BF := Vector2(4.0, 42.0)

const TICK_DT := 0.1
const TICK_COUNT := 400
## 1000 kg/h (docs/plant/misc_sources.md:190/206) = 0.2778 kg/s per head.
const FEED_RATE := 0.2778
const FEED_DENSITY := 320.0                                    # LineFlow.gd:31 FEED_DENSITY
const FEED_COMP := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}  # LineFlow.gd:40 DEFAULT_COMP

var _pass := 0
var _fail := 0
var _skip := 0
var _backups : Dictionary = {}
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

func _bf_to_pc(bf: Vector2) -> Vector2:
	return BF_O + bf.x * BF_XU + bf.y * BF_ZU


func _ready() -> void:
	print("=== LINE 3B LEDGER — mass conservation (measured) ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via a .tscn, not --script)")
		get_tree().quit(2); return

	_backup_files()
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
		world.queue_free(); _finish(); return

	await _build_world(bm, lf)
	_drive_line(lf)
	_assert_ledger(lf)

	world.queue_free()
	_verify_operator_saves()
	_write_dump()
	_finish()


func _finish() -> void:
	_restore_files()
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Dump: %s" % ProjectSettings.globalize_path(DUMP_PATH))
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)


# =============================================================================
func _build_world(bm, lf) -> void:
	_section("WORLD — the %s macro from its clean seed" % MACRO_ID)
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[MACRO_ID] = {}

	var start : Vector3 = Plant.pc_to_scene(_bf_to_pc(LINE_START_BF))
	var fdir : Vector3 = Plant.pc_to_scene(_bf_to_pc(LINE_START_BF + Vector2(1.0, 0.0))) - start
	fdir = fdir.normalized()
	var rot_y : float = atan2(-fdir.x, -fdir.z)
	bm.call("_build_full_line", MACRO_ID, start, rot_y)
	for _i in range(10):
		await get_tree().process_frame
	lf.call("rebuild")
	for _i in range(10):
		await get_tree().process_frame

	# Non-vacuity: the macro really placed a LineFlow-tracked line. Not an exact
	# count against LINE_3B_SEQ.size() — a handful of SEQ entries are furniture
	# (lump_platform / lump_cart_spot / lump_cart) that BuildMode places but
	# LineFlow does not track as flow machines, so machine count is expected to
	# run a few below the raw SEQ length; that gap is not what this file is
	# asserting (see the ledger check below for the actual claim).
	var listed : Array = lf.call("machine_list")
	_ok(listed.size() > 0, "the macro really built: %d LineFlow machines (of %d SEQ entries)"
		% [listed.size(), BuildMode.LINE_3B_SEQ.size()])
	_dump["machines"] = listed.size()


# =============================================================================
func _drive_line(lf) -> void:
	_section("RUN — power the line and FEED it")
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
		_note("MotorOverload: no drive tripped at %.4f kg/s per head" % FEED_RATE)
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
			draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "l3a_ident_feed",
			draw * 0.08, draw * 0.12))
		fed += draw
	return fed


# =============================================================================
## MEASURED CORRECTION, not a loosened tolerance — same reasoning as
## test_line3c_identity.gd's A3.7. ledger_residual() is fed_mass + water_added
## - (out + in-transit) (LineFlow.gd:2024-2027), and LineFlow.fed_mass is
## incremented ONLY on the physical-bale path (LineFlow.gd:2231), which a
## headless world never runs. This test charges the head batches directly
## (same as 3C's _feed_heads), so its own injected mass is invisible to
## fed_mass and shows up as a residual exactly equal to -injected. The
## quantity that actually has to balance is ledger_residual() + injected; a
## real leak moves THAT, and the raw residual is printed next to it so the
## correction cannot hide one.
func _assert_ledger(lf) -> void:
	_section("LEDGER — mass conservation on line_3b")
	var residual : float = float(lf.call("ledger_residual"))
	var injected : float = float(_dump.get("feed_kg", 0.0))
	var balanced : float = residual + injected
	var tol : float = maxf(0.05, 0.01 * injected)
	print("        ledger_residual %.4f kg ; injected %.4f kg (not counted by fed_mass) ; corrected %.6f kg (tolerance %.4f kg)"
		% [residual, injected, balanced, tol])
	_ok(injected > 0.0 and absf(balanced) <= tol,
		"mass ledger balances on line_3b: %.6f kg residual over %.2f kg charged (<= %.4f kg)"
			% [balanced, injected, tol])
	_dump["ledger_residual"] = residual
	_dump["ledger_residual_corrected"] = balanced


# =============================================================================
# user:// file safety
# =============================================================================
func _backup_files() -> void:
	for p in TOUCHED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f: f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in _backups.keys():
		var orig = _backups[p]
		if orig is String:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f: f.store_string(orig); f.close()
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
