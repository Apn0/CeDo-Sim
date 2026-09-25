extends Node3D
## Reproduction + regression test for #90 — a NEW save MUST begin with an EMPTY
## factory, while a CONTINUED save still gets its build back.
##
## Placed-build layouts are now PER-SAVE (user://<save>_factory.json). This proves:
##   1a NEW save  : per-save file absent + no legacy fallback   → 0 placed objects
##   1b CONTINUE  : per-save file absent + legacy global present → migrates → 3 placed
##   1c CONTINUE  : per-save file present (1 machine)            → loads its own → 1
##   2  END-TO-END: boot the REAL MainWorld with pending_is_new_save=true and a
##                  populated legacy global present → its BuildMode is EMPTY.
##
## All touched user:// files are backed up + restored, so real saves are untouched.
## The phase-2 boot is a real MainWorld with the world's own BuildMode, whose
## _save_layout ends in WorldLayout.save(). world_layout.json was never on the
## backup list above, so any save in this run would have gone to the operator's
## file with nothing to put it back. Measured 2026-09-25: no save happened (0 in
## the HEAD log; the run.sh sentinel saw the file unchanged). The guard is here
## so a change to the boot path cannot start writing it unseen. WorldLayout's
## writes go to a scratch file, and the real one is only compared, never
## written (src/tests/world_layout_guard.gd).
##   godot --headless --main-scene res://src/tests/test_new_world_wipe.tscn

const LEGACY          := "user://factory_layout.json"
const PER_SAVE_NEW    := "user://__nww_new_factory.json"
const PER_SAVE_CONT   := "user://__nww_cont_factory.json"
const PER_SAVE_OWN    := "user://__nww_own_factory.json"
const CONSUMED_FLAG   := "user://world_layout_consumed.flag"
const TEST_SAVE_SLOT  := "__nww_test_tmp"
const TEST_SAVE_PATH  := "user://__nww_test_tmp_save.json"
const TEST_SAVE_FACT  := "user://__nww_test_tmp_factory.json"
const LAYOUT_VERSION  := 2   # must match BuildMode.LAYOUT_VERSION

var _pass := 0
var _fail := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SAVE_SLOT,
	[LEGACY, PER_SAVE_NEW, PER_SAVE_CONT, PER_SAVE_OWN, CONSUMED_FLAG, TEST_SAVE_PATH, TEST_SAVE_FACT])
## The phase-2 world, kept alive until the guard's final save has run.
var _world : Node = null


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1


func _ready() -> void:
	print("=== #90 — per-save factory layout (new=empty, continue=restored) ===")
	# Before any BuildMode or world exists, so no save can reach world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return

	# Plant a populated, CURRENT-version LEGACY global (3 machines) + an OWN per-save
	# file (1 machine). Without the version marker BuildMode would ignore them (#29),
	# so these prove the per-save routing — not the version guard — does the work.
	_write(LEGACY, _layout_json(["extruder_3b", "plasmaq", "laser_filter"]))
	_write(PER_SAVE_OWN, _layout_json(["mengsilo"]))
	_ok(FileAccess.file_exists(LEGACY), "planted legacy global factory_layout.json (3 machines)")

	# ── Phase 1: BuildMode load routing (no heavy MainWorld) ────────────────────
	print("\n[Phase 1 — BuildMode per-save routing]")
	var n_new : int = await _run_buildmode(PER_SAVE_NEW, false)
	_ok(n_new == 0,
		"NEW save (per-save file absent, fallback OFF) → 0 placed, ignores legacy (got %d)" % n_new)

	var n_mig : int = await _run_buildmode(PER_SAVE_CONT, true)
	_ok(n_mig == 3,
		"CONTINUE (per-save absent, fallback ON) → migrates legacy global → 3 placed (got %d)" % n_mig)

	var n_own : int = await _run_buildmode(PER_SAVE_OWN, true)
	_ok(n_own == 1,
		"CONTINUE with its OWN per-save file → loads own (1), not legacy (got %d)" % n_own)

	# ── Phase 2: end-to-end, boot the real MainWorld as a NEW save ──────────────
	print("\n[Phase 2 — real MainWorld, new save]")
	await _run_mainworld_new_save()

	print("\n[LEAK GUARD]")
	if _world != null:
		for c in _wlg.final_checks(_world):
			_ok(c[0], c[1])
	else:
		var c : Array = _wlg.real_layout_check()
		_ok(c[0], c[1])

	# The verdict is printed and user:// restored BEFORE the world is freed,
	# then restored again after: the headless teardown segfault lands inside
	# world teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
	_wlg.restore()
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fail == 0 else 1)


# ── Phase 1 helper: spawn a bare BuildMode with an injected path + fallback ─────
func _run_buildmode(path: String, fallback: bool) -> int:
	var bm = load("res://src/build/BuildMode.gd").new()
	bm.layout_path = path
	bm.allow_legacy_fallback = fallback
	add_child(bm)
	for i in range(8):
		await get_tree().process_frame
	var placed : Node = bm.find_child("PlacedObjects", true, false)
	var n := -1
	if placed != null:
		n = 0
		for c in placed.get_children():
			if c.has_meta("placeable_id"):
				n += 1
	bm.queue_free()
	await get_tree().process_frame
	return n


# ── Phase 2 helper: boot the real MainWorld with is_new_save = true ─────────────
func _run_mainworld_new_save() -> void:
	var bus := get_node_or_null("/root/EventBus")
	_ok(bus != null, "EventBus autoload present")
	if bus:
		bus.set_meta("pending_save_name", TEST_SAVE_SLOT)
		bus.set_meta("pending_is_new_save", true)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	_ok(scn != null, "MainWorld.tscn loaded")
	if scn == null:
		return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(45):
		await get_tree().process_frame
	var bm : Node = world.find_child("BuildMode", true, false)
	_ok(bm != null, "MainWorld spawned a BuildMode")
	var placed : Node = null
	if bm:
		placed = bm.find_child("PlacedObjects", true, false)
	# A NEW save starts with no PER-SAVE build. The SHARED site structure
	# (walls, doors, gates, windows in WorldLayout.structure_items) is overlaid
	# on every save by design (BuildMode.load_layout), so it is counted apart:
	# since 2026-09-25 the operator's world keeps his 3A/3B gate there.
	# Shared = exactly what _save_layout writes back to the shared layer.
	var cc := -1
	var shared_n := 0
	if placed:
		cc = 0
		for c in placed.get_children():
			var sd : Dictionary = c.get_meta("surface_data", {})
			var t : String = String(sd.get("type", ""))
			if t == "door" or t == "gate" or t == "window" \
					or PlaceableCatalog.is_wall(String(c.get_meta("placeable_id", ""))):
				shared_n += 1
			else:
				cc += 1
	_ok(cc == 0,
		"NEW world via real MainWorld → no per-save objects (count=%d), legacy ignored" % cc)
	var want_shared : int = (WorldLayout.structure_items as Array).size()
	_ok(shared_n == want_shared,
		"NEW world still carries the shared site structure (%d placed, %d in structure_items)" % [shared_n, want_shared])
	_world = world


# ── Helpers ─────────────────────────────────────────────────────────────────
func _layout_json(ids: Array) -> String:
	var arr : Array = [{"layout_version": LAYOUT_VERSION}]
	var x := 5.0
	for id in ids:
		arr.append({"id": id, "x": x, "y": 0.0, "z": 5.0, "rot_y": 0.0, "h": 0.0})
		x += 4.0
	return JSON.stringify(arr, "\t")


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(text)
		f.close()
