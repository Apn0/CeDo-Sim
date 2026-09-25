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

## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const PROTECT : Array[String] = [
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

const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)
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
	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return

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
	# every save rewrites the world layout. The guard armed above sends those
	# writes to its scratch file; stopping the timer keeps the run quiet too.
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
	for c in _wlg.final_checks(_world):
		_check(c[0], c[1])
	_finish(0 if _fails == 0 else 1)

# =============================================================================
# RESTORED 2026-08-11 — _backup_files / _run / _finish were referenced by
# _ready() but never written, so this file did not parse and had therefore never
# executed. `godot --headless --path . --check-only --script <this>` reported
# three "Function not found in base self" errors. The regression harness did not
# catch it: its parse gate is `--headless --path . --quit`, which boots the main
# scene and never loads anything under src/tests/.
# =============================================================================

## The verdict is printed and user:// restored BEFORE the world is freed, then
## restored again after: the headless teardown segfault lands inside world
## teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
func _finish(code: int) -> void:
	_wlg.restore()
	print("Result: %s (%d ok, %d fail)"
		% ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(code)

# ── observation ──────────────────────────────────────────────────────────────

## The live OverflowDumpTask, or null. The board keys _active by NPC instance
## id; we also sweep the NPCs themselves because a task that has been abandoned
## is off the board but may still be on the worker.
func _find_dump_task() -> Array:
	var board := get_node_or_null("/root/NpcAutonomyBoard")
	if board != null:
		for npc_id in board._active.keys():
			var t = board._active[npc_id]
			if t is OverflowDumpTask:
				return [t, instance_from_id(npc_id)]
	for n in get_tree().get_nodes_in_group("npc"):
		var t2 = n.get("_autonomy_task")
		if t2 is OverflowDumpTask:
			return [t2, n]
	return [null, null]

## The first real indoor WasteContainer, or null.
func _first_indoor_container() -> Node3D:
	for c in get_tree().get_nodes_in_group("waste_container"):
		if c is Node3D and is_instance_valid(c) 				and not c.is_in_group("waste_container_outdoor"):
			return c as Node3D
	return null

## Build a real catalog container at the first machine slot ContainerGuideManager
## declares, i.e. where the plant says a bin belongs.
func _place_container_on_a_guide_slot() -> Node3D:
	for node in get_tree().get_nodes_in_group("placed_object"):
		var machine := node as Node3D
		if machine == null or not is_instance_valid(machine):
			continue
		var pid := String(machine.get_meta("placeable_id", ""))
		if not ContainerGuideManager.SLOT_REGISTRY.has(pid):
			continue
		var slots : Array = ContainerGuideManager.SLOT_REGISTRY[pid]
		if slots.is_empty():
			continue
		var slot : Dictionary = slots[0]
		var cid := String(slot["container_id"])
		var body := PlaceableCatalog.build_node(cid, false)
		if body == null:
			continue
		_world.add_child(body)
		body.global_position = machine.global_transform * (slot["offset"] as Vector3)
		_info("placed '%s' on the %s slot at (%.1f, %.1f)"
			% [cid, pid, body.global_position.x, body.global_position.z])
		return body
	return null

func _point_in_polygon(p: Vector2, poly: Array[Vector2]) -> bool:
	var inside := false
	var j := poly.size() - 1
	for i in range(poly.size()):
		var a := poly[i]
		var b := poly[j]
		if ((a.y > p.y) != (b.y > p.y)) \
				and (p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x):
			inside = not inside
		j = i
	return inside

## Is there a roof above this point? Independent of the footprint polygon, so a
## stale polygon cannot fake a green on its own.
func _roof_above(node: Node3D) -> bool:
	var space := node.get_world_3d().direct_space_state
	var from := node.global_position + Vector3(0.0, 1.0, 0.0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, 60.0, 0.0))
	q.exclude = [node.get_rid()] if node is CollisionObject3D else []
	q.collide_with_areas = false
	return not space.intersect_ray(q).is_empty()

func _run() -> void:
	# ── where is the outdoor skip, really ────────────────────────────────────
	var skips := get_tree().get_nodes_in_group("waste_container_outdoor")
	_check(not skips.is_empty(), "ContainerGuide spawned an outdoor skip")
	if not skips.is_empty():
		var skip : Node3D = skips[0]
		var xz := Vector2(skip.global_position.x, skip.global_position.z)
		var in_poly := _point_in_polygon(xz, FOOTPRINT_XZ)
		var roofed := _roof_above(skip)
		_info("skip at (%.1f, %.1f); inside footprint=%s; roof overhead=%s"
			% [xz.x, xz.y, in_poly, roofed])
		_check(in_poly == roofed,
			"footprint polygon and the up-ray agree about the skip (%s vs %s)"
			% [in_poly, roofed])
		_check(in_poly == SKIP_EXPECTED_INDOORS,
			"skip is %s, which is what SKIP_EXPECTED_INDOORS declares"
			% ("INDOORS" if in_poly else "OUTDOORS"))

	# ── world census ─────────────────────────────────────────────────────────
	# A harness whose job is to name the stall point has to say what was even
	# present. The first restored run failed at "no task in 150s" with no way to
	# tell whether the board was broken or the world simply had nothing to
	# dispatch.
	for g in ["waste_container", "waste_container_outdoor", "forklift",
			"vehicle", "placed_object"]:
		_info("group '%s': %d node(s)" % [g, get_tree().get_nodes_in_group(g).size()])
	# NPC.gd joins no group at all, so it has to be counted by script.
	var n_npc := 0
	for n in _world.find_children("*", "", true, false):
		var scr = n.get_script()
		if scr != null and String(scr.resource_path).ends_with("NPC.gd"):
			n_npc += 1
	_info("NPC.gd nodes: %d (NPC.gd joins no group — counted by script)" % n_npc)

	# ── give the board something to dispatch ─────────────────────────────────
	# A freshly booted plant has empty bins, so the board correctly emits
	# nothing and the whole chain below never runs. (The first restored run of
	# this file reported exactly that: "no task in 150s".) Fill one REAL indoor
	# WasteContainer through its own add() — the same call LineFlow makes — so
	# needs_emptying() goes true. This is production output, not a stub: the
	# container, the board, the forklift and the worker are all the real ones.
	var indoor : Node3D = _first_indoor_container()
	if indoor == null:
		# A stock world ships ZERO indoor containers. ContainerGuideManager's
		# per-machine pass builds HOLOGRAM guides (ContainerGuide nodes marking
		# where a bin belongs), not WasteContainers; the only real container it
		# spawns is the outdoor skip in WORLD_CONTAINER_SPAWNS. The source bin
		# is the operator's to place. So the harness places one, on a real guide
		# slot, through the real catalog — the same action the operator takes.
		_info("no indoor container in the stock world — placing one on a guide "
			+ "slot (ContainerGuideManager builds holograms, not bins)")
		indoor = _place_container_on_a_guide_slot()
	_check(indoor != null, "an indoor WasteContainer is present to be emptied")
	if indoor != null:
		var cap_kg : float = float(indoor.capacity_m3) * float(indoor.blended_density)
		indoor.call("add", cap_kg * 0.95, float(indoor.blended_density), -1)
		_check(bool(indoor.call("needs_emptying")),
			"the filled bin reports needs_emptying (fill %.0f%%)"
			% (100.0 * float(indoor.call("fill_fraction"))))
		_info("filled '%s' at (%.1f, %.1f)"
			% [String(indoor.name), indoor.global_position.x,
			   indoor.global_position.z])

	# ── watch the chain ──────────────────────────────────────────────────────
	var t0 := Time.get_ticks_msec()
	var frames := 0
	var ever_saw_task := false
	var reached : int = -1
	var finished := false
	var last_npc : Node = null

	while (Time.get_ticks_msec() - t0) / 1000.0 < _watch_s:
		await get_tree().process_frame
		frames += 1
		var pair := _find_dump_task()
		var task = pair[0]
		var npc = pair[1]
		if task == null:
			# The task is gone. If we had one and it had reached DUMP, the chain
			# completed; otherwise it was abandoned and the stall report below
			# still names the last phase it held.
			if ever_saw_task and reached >= OverflowDumpTask.Phase.DUMP:
				finished = true
				break
			continue
		ever_saw_task = true
		last_npc = npc
		var ph := int(task._phase)
		reached = maxi(reached, ph)
		if ph != _last_phase:
			_info("phase -> %s at frame %d (t=%.1fs)"
				% [_phase_names[ph] if ph < _phase_names.size() else str(ph),
				   frames, (Time.get_ticks_msec() - t0) / 1000.0])
			_last_phase = ph
			_phase_first_seen_frame = frames

		if frames % 60 == 0:
			var fk = task._forklift
			if fk != null and is_instance_valid(fk):
				var p : Vector3 = fk.global_position
				var tgt = fk.get("_npc_target")
				var spd = float(fk.get("_current_speed_mps"))
				var pilot = fk.get("_pilot")
				var pmode = int(pilot._mode) if pilot != null else -1
				var pblk = float(pilot._blocked_secs) if pilot != null else 0.0
				var r_sz = fk.get("_npc_route").size() if fk.get("_npc_route") != null else 0
				_info("FK pos=(%.1f, %.1f) spd=%.2f tgt=%s r_sz=%d mode=%d blk=%.1f pt=%.1f/%.1f"
					% [p.x, p.z, spd, str(tgt), r_sz, pmode, pblk, float(task._phase_t), float(task._phase_budget)])
			if task.is_failed():
				_info("TASK IS FAILED: reason=%s" % task._fail_reason)

		# _seated_in_vehicle or disabled physics processing), the task's own clock
		# must keep advancing anyway. Counting both halves separately is what
		# distinguishes "never boarded" from "boarded and frozen".
		var pt := float(task._phase_t)
		var is_seated := false
		if npc != null and is_instance_valid(npc):
			if "_seated_in_vehicle" in npc and bool(npc.get("_seated_in_vehicle")):
				is_seated = true
			elif not (npc as Node3D).is_physics_processing():
				is_seated = true
		if is_seated:
			_seen_seated_frames += 1
			if pt > _last_phase_t + 1e-6:
				_seen_seated_ticking += 1
		_last_phase_t = pt

	# ── report ───────────────────────────────────────────────────────────────
	_check(ever_saw_task,
		"an OverflowDumpTask was actually assigned to a worker")
	if not ever_saw_task:
		_info("no task in %.0fs — the board never emitted one, so nothing "
			% _watch_s + "downstream of emission was exercised")
		return

	var reached_name : String = _phase_names[reached] \
		if reached >= 0 and reached < _phase_names.size() else str(reached)
	_info("furthest phase reached: %s" % reached_name)
	_check(finished, "the chain completed (reached DUMP and released the task)")
	if not finished:
		_info("STALL: held %s from frame %d to the end of the %.0fs window"
			% [reached_name, _phase_first_seen_frame, _watch_s])
		# Name the stall, do not just locate it. "stuck in DRIVE_TO_INDOOR" is
		# not actionable; whether the worker ever got ON the forklift, and how
		# far the forklift is from where it is driving, is.
		var t2 = _find_dump_task()[0]
		if last_npc != null:
			_info("stalled worker: %s at (%.1f, %.1f)"
				% [String(last_npc.name), (last_npc as Node3D).global_position.x,
				   (last_npc as Node3D).global_position.z])
			_info("worker physics_process=%s (false = seated in a vehicle)"
				% (last_npc as Node3D).is_physics_processing())
		if t2 != null:
			_info("task._boarded=%s  phase_t=%.1fs of budget %.1fs"
				% [t2._boarded, float(t2._phase_t), float(t2._phase_budget)])
			var fk = t2._forklift
			if fk != null and is_instance_valid(fk):
				_info("forklift '%s' at (%.1f, %.1f)"
					% [String(fk.name), fk.global_position.x, fk.global_position.z])
				if last_npc != null:
					_info("worker->forklift distance: %.1f m"
						% (last_npc as Node3D).global_position.distance_to(
							fk.global_position))
			else:
				_info("task holds NO forklift reference")
			var ic = t2.indoor_container
			if ic != null and is_instance_valid(ic):
				var from : Vector3 = fk.global_position if (fk != null 					and is_instance_valid(fk)) else (last_npc as Node3D).global_position
				_info("target bin at (%.1f, %.1f), %.1f m from the driver"
					% [ic.global_position.x, ic.global_position.z,
					   from.distance_to(ic.global_position)])

	_check(reached > OverflowDumpTask.Phase.WALK_TO_FORKLIFT,
		"the worker got past WALK_TO_FORKLIFT (reached %s)" % reached_name)
	_info("seated frames observed: %d, of which the task clock advanced: %d"
		% [_seen_seated_frames, _seen_seated_ticking])
	if _seen_seated_frames > 0:
		_check(_seen_seated_ticking > 0,
			"the autonomy tick SURVIVES boarding (the npc-05 deadlock guard)")
	else:
		_info("boarding guard NOT exercised: physics_process stayed true for "
			+ "every observed frame, so the seated signal this guard watches "
			+ "for never appeared — even on a run where task._boarded was true")
