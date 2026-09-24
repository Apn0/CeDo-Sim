extends Node
## LEGACY PROPS ON AN UNCONFIGURED WORLD (2026-09-24, C11) — a first launch
## (no world_layout.json yet) builds its demo props without SCRIPT ERRORs.
##
##   godot --headless --path . res://src/tests/test_legacy_props_spawner.tscn
##
## LegacyPropsSpawner runs only while `WorldLayout.is_configured()` is false
## (MainWorld.gd:279-282) — a fresh install, never the operator's own world —
## and it called `world.call("_fit_box_collider")` / `("_local_aabb")`, helpers
## that had moved to GeometryUtils. Each boot printed 3 "Nonexistent function"
## SCRIPT ERRORs (75 across a fresh-clone harness run), the battery station,
## wall outlet and diesel pump got no solid collider, and the feeder station
## aborted right after adding its shredder — so the shredder stayed unseated
## and Mohammed, his bale clamp and his tools were never spawned.
##
## Measured before the fix (mutation: the two `world.call` lines restored):
## checks 2-5 red.
##
## USER FILES. user://world_layout.json is the operator's world and is in git
## nowhere, so this suite never writes it: WorldLayout is pointed at NO_LAYOUT
## (the suite refuses to boot a world if that override is not honoured) and the
## real file is only compared, byte for byte, at the end. A change there was
## made by someone else sharing this app_userdata (another session's suite, or
## the game), so it is left as is, never restored over, and the start-of-run
## copy is kept beside it as world_layout.json.legacyprops-<unix>.bak with a
## WARN line. The slot's own files go through AtomicFile (write_text / delete),
## never a raw FileAccess.WRITE, and are put back BEFORE world.queue_free():
## the headless teardown segfaults about one run in four and never reaches code
## after it. (As first landed in 1588462 this suite restored world_layout.json
## unconditionally, with a truncating FileAccess.WRITE, after the teardown.)
## Same pattern as test_legacy_props_unconfigured_boot (#277).

const WATCHDOG_S := 240.0
const BOOT_FRAMES : int = 120
const SETTLE_FRAMES : int = 30
const TEST_SLOT : String = "__legacyprops__"
const NO_LAYOUT : String = "user://__legacyprops___no_layout.json"
const REAL_WL : String = "user://world_layout.json"

var _protect : Array[String] = []   # this slot's files only — never REAL_WL
var _backups : Dictionary = {}
var _real_wl_before : Variant = null
var _wl_verdict := ""                # "", "same" or "warned" — each is printed once
var _world : Node = null
var _done := false
var _oks := 0
var _fails := 0

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
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	_protect = [
		"user://%s_save.json" % TEST_SLOT,
		"user://%s_factory.json" % TEST_SLOT,
	]
	_backup_files()
	AtomicFile.delete(NO_LAYOUT)   # a killed run's leftover
	call_deferred("_run")

func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	_cleanup()
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _solid(n: Node) -> bool:
	if n == null:
		return false
	var cs := n.get_node_or_null("SolidCollision") as CollisionShape3D
	return cs != null and cs.shape is BoxShape3D and (cs.shape as BoxShape3D).size.length() > 0.1

func _run() -> void:
	print("[TEST] legacy props on an unconfigured world")
	# The unconfigured path: point the layout at a file that does not exist and
	# drop the in-memory markers the autoload loaded at boot.
	WorldLayout.layout_path_override = NO_LAYOUT
	if WorldLayout.get_layout_path() != NO_LAYOUT:
		# Without the override any save() of this world would land on REAL_WL.
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to boot a world that could save over %s" % REAL_WL)
		_done = true
		_cleanup()
		print("Result: FAIL (0 ok, 1 fail — layout override not honoured)")
		get_tree().quit(2)
		return
	WorldLayout.clear()
	var bus := get_node_or_null("/root/EventBus")
	bus.set_meta("pending_save_name", TEST_SLOT)
	bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	_world = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	var autosave := _world.find_child("AutosaveTimer", true, false) as Timer
	if autosave != null:
		autosave.stop()
	for _i in range(SETTLE_FRAMES):
		await get_tree().physics_frame

	_check(not WorldLayout.is_configured(), "1 the world under test is UNCONFIGURED — the legacy path ran")
	var station := _world.find_child("BatteryStation", true, false)
	_check(_solid(station), "2 the battery station has a solid collider (%s)" % str(station != null))
	_check(_solid(_world.find_child("PowerOutlet", true, false)) and _solid(_world.find_child("FuelPump", true, false)),
		"3 the wall outlet and the diesel pump have solid colliders")
	var floor_y : float = float(_world.call("_floor_top_y"))
	var seated := false
	var detail := "no shredder in group"
	for s in get_tree().get_nodes_in_group("shredder"):
		var n3 := s as Node3D
		if n3 == null:
			continue
		var bb : AABB = GeometryUtils.local_aabb(n3)
		var bottom : float = n3.global_position.y + bb.position.y
		detail = "bottom %.3f m vs floor %.3f m at %s" % [bottom, floor_y, str(n3.global_position)]
		if absf(bottom - floor_y) < 0.05 and n3.global_position.length() > 1.0:
			seated = true
			break
	_check(seated, "4 the feeder station's shredder is seated on the floor (%s)" % detail)
	var feeder_ok := false
	for n in _world.find_children("*", "", true, false):
		if "worker_name" in n and String(n.get("worker_name")) == "Mohammed":
			feeder_ok = true
			break
	_check(feeder_ok, "5 the feeder station finished — Mohammed was spawned after the shredder")
	await _finish()

func _finish() -> void:
	if _done:
		return
	_done = true
	# user:// is put right BEFORE the world teardown: a headless teardown
	# segfaults about one run in four (CLAUDE.md) and never reaches code after it.
	_cleanup()
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] legacy props spawner %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
		_cleanup()   # again, for anything the teardown itself wrote
	get_tree().quit(0 if _fails == 0 else 1)

## Put user:// back. Safe to call more than once. The layout override is left
## pointing at NO_LAYOUT on purpose: WorldLayout still holds the cleared,
## fresh-install state, and pointing it back at the real file before the
## process exits would let any late save() write that empty state over REAL_WL.
func _cleanup() -> void:
	AtomicFile.delete(NO_LAYOUT)
	_restore_files()
	_check_real_layout()

## The file's bytes, or null when it does not exist.
func _read_or_null(path: String) -> Variant:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func _same_bytes(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_NIL or typeof(b) == TYPE_NIL:
		return typeof(a) == typeof(b)
	return (a as PackedByteArray) == (b as PackedByteArray)

func _backup_files() -> void:
	_real_wl_before = _read_or_null(REAL_WL)
	for p in _protect:
		_backups[p] = _read_or_null(p)

func _restore_files() -> void:
	for p in _protect:
		var data : Variant = _backups.get(p, null)
		if typeof(data) == TYPE_NIL:
			AtomicFile.delete(p)
		elif not _same_bytes(_read_or_null(p), data):
			AtomicFile.write_text(p, (data as PackedByteArray).get_string_from_utf8())

## This suite never writes REAL_WL (see the header), so a change to it during
## the run was made by someone else sharing this app_userdata. Restoring the
## start-of-run copy over it would revert their edit: leave it, and keep that
## copy beside it so neither version is lost.
func _check_real_layout() -> void:
	if _wl_verdict == "warned":
		return
	if _same_bytes(_read_or_null(REAL_WL), _real_wl_before):
		if _wl_verdict == "":
			print("  info  : %s is byte-identical to the start of the run (this suite never writes it)" % REAL_WL)
			_wl_verdict = "same"
		return
	_wl_verdict = "warned"
	if typeof(_real_wl_before) == TYPE_NIL:
		print("  WARN  : %s appeared during the run (not written by this suite) — left as is" % REAL_WL)
		return
	var keep := "%s.legacyprops-%d.bak" % [REAL_WL, int(Time.get_unix_time_from_system())]
	var err := AtomicFile.write_text(keep, (_real_wl_before as PackedByteArray).get_string_from_utf8())
	print("  WARN  : %s changed during the run (not written by this suite) — left as is; the start-of-run copy is %s (%s)"
		% [REAL_WL, keep, error_string(err)])
