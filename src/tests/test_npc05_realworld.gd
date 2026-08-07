extends Node
# =============================================================================
# npc-05 — REAL MainWorld boot proof of the container-emptying chain.
# =============================================================================
# The existing bench (src/tests/test_npc05_container_chain.gd) proves the
# GENERATION half against real WasteContainers, but its execution half (S5)
# runs on a StubForklift/StubWorker in a synthetic SceneTree: the kg ledger is
# performed by the stub's own load_bulk/unload_bulk, and every actor starts
# inside its arrival radius so no walking or driving ever happens.
#
# This file boots the REAL MainWorld (same pattern as repro_clamp_spawn.gd),
# with the REAL ContainerGuide-spawned outdoor skip, the REAL Forklift, the
# REAL NPC bodies, the REAL NavigationRegion3D and the REAL NpcAutonomyBoard
# autoload ticking on its own _process. Nothing is stubbed. It measures how far
# the chain actually gets and reports the exact stall point if it does not
# finish.
#
#   GODOT --headless --path . res://src/tests/test_npc05_realworld.tscn
#   NPC05_WATCH_S=240 ...        → longer observation window
#
# (The NPC05_DISABLE_FENCE control was removed 2026-08-03 together with the
# perimeter fence itself — the operator ordered the fence deleted outright.)

const TEST_SLOT : String = "__npc05real__"

const PROTECT : Array[String] = [
	"user://world_layout.json",
	"user://__npc05real___save.json",
	"user://__npc05real___factory.json",
]

# Building shell footprint (XZ), the same polygon tools/regression/run.sh writes
# to tools/regression/out/positions.json ("building_footprint"). Used to answer
# the operator's question "is the outdoor skip actually outdoors?" independently
# of any comment in ContainerGuide.gd. Cross-checked at runtime by an up-ray
# that looks for a roof above the skip, so a stale polygon cannot fake a green.
const FOOTPRINT_XZ : Array[Vector2] = [
	Vector2(-277.800964, 61.443527), Vector2(-127.102165, 60.918190),
	Vector2(-126.992348, 92.417923), Vector2(-146.192184, 92.484825),
	Vector2(-146.052750, 132.484512), Vector2(-196.552383, 132.660583),
	Vector2(-196.571548, 127.160645), Vector2(-220.571335, 127.244308),
	Vector2(-220.588791, 122.244370), Vector2(-277.588318, 122.443039),
]

# npc-05 — where the ContainerGuide skip is CURRENTLY meant to be. True = inside
# the building footprint, which is the deliberate interim placement: the yard
# position is geometrically right but unreachable by the current dead-reckoning
# vehicle autopilot (measured A/B recorded in ContainerGuide.gd). Flip this to
# false in the same commit that moves the skip back outdoors.
const SKIP_EXPECTED_INDOORS : bool = true

const BOOT_FRAMES : int = 120        # _ready cascade + first ContainerGuide pass
const SETTLE_FRAMES : int = 120      # let physics/crew settle before we intervene

var _backups : Dictionary = {}
var _fails : int = 0
var _oks : int = 0
var _world : Node3D = null
var _watch_s : float = 180.0

# Stall bookkeeping — what the chain was doing on the last observed tick.
var _last_phase : int = -1
var _phase_first_seen_frame : int = -1
# npc-05 BOARDING-DEADLOCK GUARD. OperatorContext.npc_board_vehicle() calls
# set_physics_process(false) on the worker it seats. While the autonomy tick
# lived in NPC._physics_process, boarding the forklift silently killed the task
# that ordered the boarding: _phase_t froze at 0.0, so not even PHASE_TIMEOUT_S
# could fire, and the worker sat motionless for the rest of the shift holding
# the forklift's occupied flag. These record whether a task was ever observed
# advancing its own clock while its NPC had physics processing switched off —
# i.e. whether the tick really does survive boarding.
var _seen_seated_frames  : int = 0
var _seen_seated_ticking : int = 0
var _last_phase_t : float = 0.0
var _phase_names : Array[String] = ["WALK_TO_FORKLIFT", "DRIVE_TO_INDOOR",
	"SCOOP_BULK", "DRIVE_TO_OUTDOOR", "DUMP"]

func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)

func _info(label: String) -> void:
	print("  info  : %s" % label)

func _ready() -> void:
	var env := OS.get_environment("NPC05_WATCH_S")
	if env != "":
		_watch_s = float(env)
	print("=== npc-05 REAL MainWorld chain proof ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	_backup_files()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(2); return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	# Production parity: when the game boots via change_scene, current_scene IS
	# the world. NpcAutonomyBoard._find_main_world (NpcAutonomyBoard.gd:480-482)
	# prefers it, and BaseVehicle.on_npc_exited (BaseVehicle.gd:353) reparents
	# the dismounting NPC onto it. Leaving it null would exercise a code path
	# the shipped game never takes.
	get_tree().current_scene = _world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	# Kill the autosave timer. MainWorld's SaveCoordinator fires every 60 s and
	# rewrites user://world_layout.json — a file this harness must never leave
	# modified. (_backup_files/_restore_files still cover it belt-and-braces.)
	var autosave := _world.find_child("AutosaveTimer", true, false) as Timer
	if autosave != null:
		autosave.stop()
		print("[harness] AutosaveTimer stopped — world_layout.json will not be rewritten")

	# Advance the clock out of the 31-minute pre-shift arrival window and into
	# mid-shift through the CANONICAL setter, so PreShiftSequence + CrewManager
	# both re-evaluate on time_jumped exactly as they do when the operator sets
	# a starting time. Without this every eligible NPC is OFF_DUTY, so
	# CrewManager.needs_worker() (CrewManager.gd:457) returns true for all of
	# them and NPC._autonomy_tick (NPC.gd:114) never polls the board at all.
	var clock = _world.get("shift_clock")
	if clock != null and clock.has_method("seek_to_wall_time"):
		clock.call("seek_to_wall_time", 10, 0, false)
		print("[harness] shift clock seeked to 10:00 (mid-shift)")
	for _i in range(SETTLE_FRAMES):
		await get_tree().physics_frame

	await _run()
	_finish(0 if _fails == 0 else 1)

func _restore_files() -> void:
	for p in PROTECT:
		var data = _backups.get(p, null)
		if data == null:
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
		else:
			var f := FileAccess.open(p, FileAccess.WRITE)
			f.store_buffer(data)
			f.close()
