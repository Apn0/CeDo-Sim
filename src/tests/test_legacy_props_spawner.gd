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

const WATCHDOG_S := 240.0
const BOOT_FRAMES : int = 120
const SETTLE_FRAMES : int = 30
const TEST_SLOT : String = "__legacyprops__"
const NO_LAYOUT : String = "user://__legacyprops___no_layout.json"

var _protect : Array[String] = []
var _backups : Dictionary = {}
var _world : Node = null
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
		"user://world_layout.json",
		"user://%s_save.json" % TEST_SLOT,
		"user://%s_factory.json" % TEST_SLOT,
	]
	_backup_files()
	call_deferred("_run")

func _on_watchdog() -> void:
	_restore_files()
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
	await _teardown()
	_finish()

func _teardown() -> void:
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	AtomicFile.delete(NO_LAYOUT)
	_restore_files()

func _backup_files() -> void:
	for p in _protect:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			if f != null:
				_backups[p] = f.get_buffer(f.get_length())
				f.close()

func _restore_files() -> void:
	for p in _protect:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f != null:
				f.store_buffer(data)
				f.close()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] legacy props spawner %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
