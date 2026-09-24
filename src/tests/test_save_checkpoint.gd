extends Node
## SAVE CHECKPOINT (Q2, 2026-09-23) — SaveCoordinator.save_checkpoint() copies
## the live slot (save + factory sidecar) under a stamped name the main menu
## lists as its own save, never touching the live slot on failure.
##
##   godot --headless --path . res://src/tests/test_save_checkpoint.tscn
##
## Uses the REAL GameState (its _ready picks the slot from EventBus meta, as
## MainMenu does) and the REAL SaveCoordinator with no world/player/clock/crew
## — save_game() is null-safe on all four, which is what makes this cheap. Every
## file it writes carries the `__cptest__` prefix and is deleted at the end;
## the operator's saves are never read or written.

const SLOT       := "__cptest__"
const WATCHDOG_S := 60.0

var _fails := 0
var _oks   := 0
var _created : Array[String] = []

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _slot_files() -> Array[String]:
	var out : Array[String] = []
	var dir := DirAccess.open("user://")
	if dir == null:
		return out
	dir.list_dir_begin()
	var f := dir.get_next()
	while f != "":
		if not dir.current_is_dir() and f.begins_with(SLOT):
			out.append(f)
		f = dir.get_next()
	out.sort()
	return out

func _run() -> void:
	print("[TEST] save checkpoint")
	var bus := get_node_or_null("/root/EventBus")
	if bus == null:
		print("FATAL: EventBus autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	# Sweep leftovers from a killed earlier run so the counts below are honest.
	for f in _slot_files():
		AtomicFile.delete("user://" + f)
	_check(_slot_files().is_empty(), "S0 no %s* files in user:// before the test" % SLOT)

	bus.set_meta("pending_save_name", SLOT)
	bus.set_meta("pending_is_new_save", true)
	var gs := GameState.new()
	add_child(gs)
	await get_tree().process_frame
	var live_save := "user://%s_save.json" % SLOT
	var live_factory := "user://%s_factory.json" % SLOT
	_check(String(gs.save_file_path) == live_save, "S1 GameState took the slot from EventBus meta (%s)" % gs.save_file_path)
	_created.append(live_save)
	_created.append(live_factory)
	var factory_text := '{"objects": [{"id": "trilzeef", "x": 1.5}], "note": "checkpoint fixture"}'
	_check(AtomicFile.write_text(live_factory, factory_text) == OK, "S1 factory sidecar fixture written")

	var sc := SaveCoordinator.new()
	add_child(sc)
	await get_tree().process_frame
	sc.setup(null, null, gs, null, null)

	# ── S2: a checkpoint copies both files under a stamped stem ──
	var t0 := int(Time.get_unix_time_from_system())
	var stem : String = sc.save_checkpoint()
	_check(stem.begins_with(SLOT + "_cp_"), "S2 checkpoint stem is '<slot>_cp_<stamp>' (%s)" % stem)
	if stem == "":
		_finish(); return
	var cp_save := "user://%s_save.json" % stem
	var cp_factory := "user://%s_factory.json" % stem
	_created.append(cp_save)
	_created.append(cp_factory)
	_check(AtomicFile.exists_any(live_save), "S2 the live save was written first (%s)" % live_save)
	_check(FileAccess.file_exists(cp_save), "S2 checkpoint save exists (%s)" % cp_save)
	_check(FileAccess.file_exists(cp_factory), "S2 checkpoint factory sidecar exists (%s)" % cp_factory)
	var cp_data = AtomicFile.read_json(cp_save, TYPE_DICTIONARY)
	_check(typeof(cp_data) == TYPE_DICTIONARY and cp_data.has("saved_at"), "S2 checkpoint save parses as a save (has saved_at)")
	if typeof(cp_data) == TYPE_DICTIONARY:
		var at := int(cp_data.get("saved_at", 0))
		_check(at >= t0 - 1 and at <= t0 + 5, "S2 checkpoint saved_at is now (%d vs %d)" % [at, t0])
	_check(AtomicFile.read_text(cp_save) == AtomicFile.read_text(live_save), "S2 checkpoint save is byte-equal to the live save")
	_check(AtomicFile.read_text(cp_factory) == factory_text, "S2 checkpoint factory is byte-equal to the live sidecar")
	_check(String(gs.save_file_path) == live_save, "S2 the live slot is still the live slot (GameState path unchanged)")
	# What the main menu would list: every *_save.json — the checkpoint is one.
	var listed := false
	for f in _slot_files():
		if f == stem + "_save.json":
			listed = true
	_check(listed, "S2 the checkpoint is a *_save.json the main menu's scan lists")

	# ── S3: a second checkpoint in the same second gets its own name ──
	var stem2 : String = sc.save_checkpoint()
	_created.append("user://%s_save.json" % stem2)
	_created.append("user://%s_factory.json" % stem2)
	_check(stem2 != "" and stem2 != stem, "S3 second checkpoint has a distinct stem (%s vs %s)" % [stem2, stem])
	_check(FileAccess.file_exists("user://%s_save.json" % stem2), "S3 second checkpoint save exists")
	_check(FileAccess.file_exists(cp_save), "S3 the first checkpoint was not overwritten")

	# ── S4: no GameState → nothing written, "" returned ──
	var before := _slot_files().size()
	var sc2 := SaveCoordinator.new()
	add_child(sc2)
	await get_tree().process_frame
	sc2.setup(null, null, null, null, null)
	var stem3 : String = sc2.save_checkpoint()
	_check(stem3 == "", "S4 no GameState → save_checkpoint() returns an empty stem")
	_check(_slot_files().size() == before, "S4 no GameState → no file written (%d before, %d after)" % [before, _slot_files().size()])

	# ── S5: no factory sidecar → the save is still checkpointed, no sidecar copy ──
	_check(AtomicFile.delete(live_factory) == OK, "S5 fixture: live factory sidecar removed")
	var stem4 : String = sc.save_checkpoint()
	_created.append("user://%s_save.json" % stem4)
	_created.append("user://%s_factory.json" % stem4)
	_check(stem4 != "" and FileAccess.file_exists("user://%s_save.json" % stem4), "S5 checkpoint without a sidecar still writes the save (%s)" % stem4)
	_check(not FileAccess.file_exists("user://%s_factory.json" % stem4), "S5 …and writes no phantom factory sidecar")
	_finish()

func _finish() -> void:
	# Leave nothing behind: primaries and their .bak/.tmp generations.
	for pth in _created:
		AtomicFile.delete(pth)
	var left := _slot_files()
	_check(left.is_empty(), "cleanup: no %s* files left in user:// (%s)" % [SLOT, str(left)])
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		if bus.has_meta("pending_save_name"):
			bus.remove_meta("pending_save_name")
		if bus.has_meta("pending_is_new_save"):
			bus.remove_meta("pending_is_new_save")
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] save checkpoint %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
