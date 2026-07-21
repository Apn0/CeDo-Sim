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
#   NPC05_DISABLE_FENCE=1 ...    → measurement-only control, see below
#
# NPC05_DISABLE_FENCE is a CONTROL, not a fix. The operator asked whether
# removing perimeter-fence collision would unstick the forklift; answering with
# an opinion is how this project has been burned before, so the switch strips
# collision off the ChainLinkFence bodies AT RUNTIME, in this harness only, and
# the chain is measured with and without. Nothing is written back to
# src/scenes/world/exterior/ChainLinkFence.gd — a shipped fence with no
# collision would let every vehicle and NPC walk off the site.
# =============================================================================

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
	if OS.get_environment("NPC05_DISABLE_FENCE") == "1":
		_disable_fence_collision()
	for _i in range(SETTLE_FRAMES):
		await get_tree().physics_frame

	await _run()
	_finish(0 if _fails == 0 else 1)

## CONTROL ONLY (NPC05_DISABLE_FENCE=1). Strip collision from the perimeter
## fence so the run measures what the operator asked: does the fence explain the
## stall, or is the dead-reckoning autopilot the real blocker? ChainLinkFence
## builds one StaticBody3D per post ("Post_<seg>_<i>") and per panel
## ("PanelBody_<seg>_<i>"); zeroing their collision_layer removes them from
## every query without touching the scene tree shape or the fence source.
func _disable_fence_collision() -> void:
	var stripped : int = 0
	for n in _world.find_children("", "StaticBody3D", true, false):
		var nm := String(n.name)
		if not (nm.begins_with("Post_") or nm.begins_with("PanelBody_")):
			continue
		var body := n as StaticBody3D
		body.collision_layer = 0
		body.collision_mask = 0
		stripped += 1
	print("[harness] CONTROL: stripped collision from %d perimeter-fence bodies (runtime only — the fence source is unchanged)" % stripped)
	_info("CONTROL RUN — fence collision disabled; results are a measurement, not a proposed fix")


func _run() -> void:
	var tree := get_tree()

	# ── A. World inventory ───────────────────────────────────────────────────
	print("\n--- A. real-world inventory ---")
	var board := get_node_or_null("/root/NpcAutonomyBoard")
	_check(board != null, "NpcAutonomyBoard autoload present and ticking")
	if board == null:
		return
	var mw_resolved : Node = board.call("_find_main_world", tree)
	_check(mw_resolved == _world,
		"board._find_main_world resolves the REAL world (production current_scene branch): %s" %
		("MainWorld" if mw_resolved == _world else str(mw_resolved)))

	var outdoor : Array = tree.get_nodes_in_group("waste_container_outdoor")
	var forklifts : Array = tree.get_nodes_in_group("forklift")
	var all_bins : Array = tree.get_nodes_in_group("waste_container")
	var indoor_bins : Array = []
	for b in all_bins:
		if b is Node3D and not (b as Node).is_in_group("waste_container_outdoor"):
			indoor_bins.append(b)
	_info("waste_container total=%d  indoor=%d  outdoor_skip=%d  forklift=%d" %
		[all_bins.size(), indoor_bins.size(), outdoor.size(), forklifts.size()])
	for f in forklifts:
		var fk := f as Node3D
		_info("forklift '%s' @ %s occupied=%s" %
			[fk.name, _v(fk.global_position), str(fk.get("occupied"))])

	# GAP: no production vehicle implements the bulk-carry API the task calls.
	var carry_capable : int = 0
	for f in forklifts:
		if (f as Node).has_method("load_bulk") and (f as Node).has_method("unload_bulk"):
			carry_capable += 1
	_check(carry_capable > 0,
		"REAL-PATH GAP (audit blocker): %d/%d group-'forklift' vehicles implement load_bulk+unload_bulk (OverflowDumpTask.gd:95,112)" %
		[carry_capable, forklifts.size()])

	# ── B. the outdoor skip ──────────────────────────────────────────────────
	print("\n--- B. ContainerGuide-spawned skip (npc-05 O1) ---")
	_check(outdoor.size() >= 1, "ContainerGuide spawned an outdoor skip (%d found)" % outdoor.size())
	if outdoor.is_empty():
		return
	var skip := outdoor[0] as Node3D
	_check(skip.is_in_group("waste_container"), "skip is in group 'waste_container'")
	_check(skip.is_in_group("waste_container_outdoor"), "skip is in group 'waste_container_outdoor'")
	_check(skip.has_method("add") and skip.has_method("fill_fraction"),
		"skip exposes the real WasteContainer receive API")
	_info("skip '%s' @ %s  capacity=%.1f m3  fill=%.3f" %
		[skip.name, _v(skip.global_position), float(skip.get("capacity_m3")),
		float(skip.call("fill_fraction"))])

	# Is it actually OUTDOORS? Two independent measurements.
	var sp := skip.global_position
	var inside_poly : bool = Geometry2D.is_point_in_polygon(
		Vector2(sp.x, sp.z), PackedVector2Array(FOOTPRINT_XZ))
	var space := _world.get_world_3d().direct_space_state
	var up := PhysicsRayQueryParameters3D.create(sp + Vector3(0, 0.5, 0), sp + Vector3(0, 40.0, 0))
	up.collide_with_areas = false
	var roof := space.intersect_ray(up)
	var roof_desc : String = "open sky"
	if not roof.is_empty():
		roof_desc = "'%s' at y=%.2f (%.1f m up)" % [(roof["collider"] as Node).name,
			(roof["position"] as Vector3).y, (roof["position"] as Vector3).y - sp.y]
	_info("skip footprint test: point_in_building_polygon=%s ; up-ray hits %s" %
		[str(inside_poly), roof_desc])
	# npc-05 — DRIFT DETECTOR, not a loosened bound. The skip is deliberately
	# indoors right now: moving it to the geometrically-correct yard position was
	# measured and left the chain unable to reach it (dead-reckoning autopilot,
	# no obstacles in the navmesh — npc-06/npc-07). ContainerGuide.gd records the
	# A/B numbers. This check pins the two together: if someone moves the skip
	# outdoors, it goes red HERE with the reason, instead of the operator finding
	# out by watching a forklift wedge itself against a wall.
	_check(inside_poly == SKIP_EXPECTED_INDOORS,
		"skip placement matches the documented interim decision (indoors=%s, expected %s — see the A/B in ContainerGuide.gd; flip both when vehicle pathfinding lands)" %
		[str(inside_poly), str(SKIP_EXPECTED_INDOORS)])

	# ── C. navmesh + crew state ──────────────────────────────────────────────
	print("\n--- C. navigation + crew state ---")
	var map : RID = _world.get_world_3d().navigation_map
	_info("navigation map valid=%s  iteration=%d" %
		[str(map.is_valid()), NavigationServer3D.map_get_iteration_id(map)])
	var anchor : Vector3 = _world.call("_get_factory_anchor")
	_info("plant anchor %s" % _v(anchor))
	if not forklifts.is_empty():
		var fk0 := forklifts[0] as Node3D
		_info("forklift #0 is %.1f m from the plant anchor and %.1f m from the skip" %
			[fk0.global_position.distance_to(anchor), fk0.global_position.distance_to(skip.global_position)])
		_path_report(map, fk0.global_position, skip.global_position, "forklift spawn -> outdoor skip")
	var npcs : Dictionary = _world.get("npcs")
	var sc = _world.get("shift_clock")
	if sc != null:
		_info("NPCs=%d  shift_active=%s elapsed=%.0f s total=%.0f s time_scale=%.0f  board phase=%d" %
			[npcs.size(), str(sc.get("shift_active")), float(sc.get("shift_elapsed_seconds")),
			float(sc.get("shift_total_seconds")), float(sc.get("time_scale")),
			int(board.call("_shift_phase", _world))])
	var eligible : int = 0
	var blocked : int = 0
	for k in npcs.keys():
		var n = npcs[k]
		if n == null or not is_instance_valid(n):
			continue
		var role := String(n.get("npc_role"))
		if role in ["all_rounder", "permanent_feeder", "transitional", "asst_shift_leader", "extruder_op"]:
			eligible += 1
			if n.has_method("_production_needs_me") and bool(n.call("_production_needs_me")):
				blocked += 1
	_check(eligible > 0,
		"at least one spawned NPC holds a role OverflowDumpTask accepts (%d eligible, %d production-blocked right now)" %
		[eligible, blocked])

	# ── STAGE 1: the world exactly as the operator's layout leaves it ────────
	print("\n=== STAGE 1 — untouched layout: indoor bin on the plant floor, forklift where WorldLayout parks it ===")
	var bin1 : Node3D = await _make_source_bin(anchor + Vector3(8.0, 0.0, 8.0), space, "stage1")
	if bin1 == null:
		return
	_path_report(map, bin1.global_position, skip.global_position, "stage-1 bin -> outdoor skip")
	var r1 : Dictionary = await _attempt("STAGE 1", board, bin1, skip, _watch_s)
	_report_attempt(r1, bin1, skip)

	# ── STAGE 2: fair-geometry control ───────────────────────────────────────
	# Stage 1 answers "does it work in the shipped layout". If it stalls on the
	# APPROACH (a 200 m walk against a 90 s phase timeout), that failure masks
	# everything downstream — so stage 2 parks a forklift beside a fresh bin,
	# exactly as the operator himself would before starting a dump run. Nothing
	# is faked: the same real NPC, real Forklift, real OverflowDumpTask and real
	# WasteContainers run every phase from there. This is the arrangement that
	# gives the chain its BEST possible shot.
	print("\n=== STAGE 2 — fair geometry: forklift parked beside a fresh full bin (operator-plausible setup) ===")
	if is_instance_valid(bin1):
		bin1.queue_free()
		await tree.physics_frame
	if forklifts.is_empty():
		_check(false, "stage 2 needs a forklift in group 'forklift'")
		return
	var bin2 : Node3D = await _make_source_bin(anchor + Vector3(10.0, 0.0, -6.0), space, "stage2")
	if bin2 == null:
		return
	var fk_move := forklifts[0] as Node3D
	fk_move.global_position = bin2.global_position + Vector3(4.0, 0.6, 0.0)
	if "npc_autopilot" in fk_move:
		fk_move.set("npc_autopilot", false)
	for _i in range(30):
		await tree.physics_frame
	_info("parked forklift '%s' at %s — %.1f m from the bin, %.1f m from the skip" %
		[fk_move.name, _v(fk_move.global_position),
		fk_move.global_position.distance_to(bin2.global_position),
		fk_move.global_position.distance_to(skip.global_position)])
	# Put the nearest eligible NPC on the forklift's doorstep too, so the walk
	# leg cannot swallow the phase budget before boarding.
	var walker : Node3D = _nearest_eligible_npc(npcs, fk_move.global_position)
	if walker != null:
		walker.global_position = fk_move.global_position + Vector3(1.0, 0.0, 0.0)
		_info("moved eligible NPC '%s' to %s (%.2f m from the forklift, APPROACH_DIST_M 1.6)" %
			[String(walker.get("npc_name")), _v(walker.global_position),
			walker.global_position.distance_to(fk_move.global_position)])
	var r2 : Dictionary = await _attempt("STAGE 2", board, bin2, skip, _watch_s)
	_report_attempt(r2, bin2, skip)

	# ── STAGE 3: the operator's own CrewPanel order ──────────────────────────
	# NpcAutonomyBoard.force_task(npc, "overflow_dump") (NpcAutonomyBoard.gd:109)
	# is the code path behind the CrewPanel task dropdown — the operator picking
	# a worker and telling him "leeg die container". It builds a REAL
	# OverflowDumpTask through _build_forced_task (:163-178) with a REAL
	# destination from _choose_lumps_destination, and NPC._autonomy_tick runs it
	# ABOVE the production gate (NPC.gd:101-107). Nothing about the task, the
	# NPC, the forklift or the containers is mocked; this stage only removes the
	# question of WHICH worker gets picked, so the later phases are reachable.
	print("\n=== STAGE 3 — operator forces the dump on the worker standing at the forklift (CrewPanel path) ===")
	var r3 : Dictionary = {"tag": "STAGE 3", "removed": 0.0, "received": 0.0,
		"emitted": false, "claimed": false, "bin_before": 0.0, "bin_after": 0.0,
		"skip_before": 0.0, "skip_after": 0.0}
	if walker != null and is_instance_valid(walker):
		# Re-fill bin2 (stage 2 may have drained it) and re-park the actors.
		var g2 : int = 0
		while not bool(bin2.call("is_full")) and g2 < 500:
			bin2.call("add", 25.0, 200.0, -1)
			g2 += 1
		fk_move.global_position = bin2.global_position + Vector3(4.0, 0.6, 0.0)
		if "occupied" in fk_move:
			fk_move.set("occupied", false)
		walker.global_position = fk_move.global_position + Vector3(1.0, 0.0, 0.0)
		for _i in range(20):
			await tree.physics_frame
		var forced : bool = bool(board.call("force_task", walker, "overflow_dump"))
		_check(forced, "[STAGE 3] board.force_task(npc,'overflow_dump') accepted the operator's order")
		if forced:
			r3 = await _watch_forced("STAGE 3", walker, bin2, skip, _watch_s)
			_report_forced(r3, bin2, skip)

	# ── VERDICT ──────────────────────────────────────────────────────────────
	print("\n--- VERDICT: did material actually move? ---")
	# npc-05 boarding-deadlock regression. Two checks, deliberately: the second
	# one alone would pass vacuously in a run where nobody ever got seated.
	_check(_seen_seated_frames > 0,
		"a real worker was observed SEATED in a forklift mid-task (%d sampled frames)" % _seen_seated_frames)
	_check(_seen_seated_ticking > 0,
		"the task kept TICKING while its worker was seated — boarding no longer deadlocks it (%d of %d seated frames advanced _phase_t)" %
		[_seen_seated_ticking, _seen_seated_frames])
	var moved1 : bool = float(r1.get("removed", 0.0)) > 0.0 and float(r1.get("received", 0.0)) > 0.0
	var moved2 : bool = float(r2.get("removed", 0.0)) > 0.0 and float(r2.get("received", 0.0)) > 0.0
	var moved3 : bool = float(r3.get("removed", 0.0)) > 0.0 and float(r3.get("received", 0.0)) > 0.0
	_check(moved1, "STAGE 1 (shipped layout): material moved bin -> skip")
	_check(moved2, "STAGE 2 (fair geometry): material moved bin -> skip")
	_check(moved3, "STAGE 3 (operator order): material moved bin -> skip")
	# NOT a bare conservation check: a delta of 0-0 is exactly the vacuous green
	# this audit exists to catch, so the balance is only asserted once BOTH
	# sides are non-zero, and the zero case is reported as an explicit failure.
	for tag in ["STAGE 1", "STAGE 2", "STAGE 3"]:
		var r : Dictionary = r1
		if tag == "STAGE 2":
			r = r2
		elif tag == "STAGE 3":
			r = r3
		var rem : float = float(r.get("removed", 0.0))
		var rec : float = float(r.get("received", 0.0))
		if rem <= 0.0 and rec <= 0.0:
			_check(false, "%s ledger: NOTHING MOVED (removed=%.2f received=%.2f) — a 0==0 'balance' proves nothing" % [tag, rem, rec])
		elif rem > 0.0 and rec <= 0.0:
			_check(false, "%s ledger: MASS VANISHED — bin lost %.2f kg, skip received %.2f kg" % [tag, rem, rec])
		else:
			_check(absf(rem - rec) < 0.51,
				"%s ledger balanced: %.2f kg removed == %.2f kg received" % [tag, rem, rec])

## Build a REAL WasteContainer from the catalog, drop it on the floor at `want`,
## and fill it with real add() calls until the real is_full() trips.
func _make_source_bin(want: Vector3, space: PhysicsDirectSpaceState3D, tag: String) -> Node3D:
	var bin := PlaceableCatalog.build_node("waste_container", false) as Node3D
	if bin == null:
		_check(false, "[%s] PlaceableCatalog.build_node('waste_container') built a node" % tag)
		return null
	_world.add_child(bin)
	var from := want + Vector3(0, 4.0, 0)
	var q := PhysicsRayQueryParameters3D.create(from, want + Vector3(0, -8.0, 0))
	if bin is CollisionObject3D:
		q.exclude = [(bin as CollisionObject3D).get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		bin.global_position = want
		_info("[%s] no floor collider under %s — parked at the requested y" % [tag, _v(want)])
	else:
		bin.global_position = hit["position"] as Vector3
		_info("[%s] source bin on '%s' at %s" %
			[tag, (hit["collider"] as Node).name, _v(bin.global_position)])
	await get_tree().physics_frame
	_check(bin.is_in_group("waste_container") and not bin.is_in_group("waste_container_outdoor"),
		"[%s] source bin joined the REAL indoor scan group (WasteContainer.gd:107)" % tag)
	var bp := bin.global_position
	_check(Geometry2D.is_point_in_polygon(Vector2(bp.x, bp.z), PackedVector2Array(FOOTPRINT_XZ)),
		"[%s] source bin really is INDOORS (inside the building footprint polygon)" % tag)
	var guard : int = 0
	while not bool(bin.call("is_full")) and guard < 500:
		bin.call("add", 25.0, 200.0, -1)
		guard += 1
	_check(bool(bin.call("is_full")),
		"[%s] source bin reports is_full() after real add() calls (%.1f kg, fill=%.2f)" %
		[tag, float(bin.get("mass_kg")) + float(bin.get("overflow_mass_kg")),
		float(bin.call("fill_fraction"))])
	return bin

## Run the REAL board + REAL NPCs against `bin` for `watch_s` sim-seconds and
## return what happened. Nothing here drives the task — it only observes.
func _attempt(tag: String, board: Node, bin: Node3D, skip: Node3D, watch_s: float) -> Dictionary:
	var tree := get_tree()
	_last_phase = -1
	var bin_before : float = float(bin.get("mass_kg")) + float(bin.get("overflow_mass_kg"))
	var skip_before : float = float(skip.get("mass_kg")) + float(skip.get("overflow_mass_kg"))
	print("  [%s] LEDGER BEFORE — bin=%.2f kg  skip=%.2f kg ; watching %.0f sim-seconds" %
		[tag, bin_before, skip_before, watch_s])
	var frames : int = int(watch_s * 60.0)
	var emitted : bool = false
	var claimed : bool = false
	var claim_npc : Node = null
	var the_task : RefCounted = null
	var attempts : int = 0
	var best_phase : int = -1
	var last_task : RefCounted = null
	var last_npc : Node = null
	var bin_id : int = bin.get_instance_id()
	for f in range(frames):
		await tree.physics_frame
		var open : Dictionary = board.get("_open_tasks")
		if not emitted and open.has(bin_id):
			emitted = true
			print("    [t=%5.1fs] board EMITTED a task for the full bin: %s (priority %d)" %
				[f / 60.0, String((open[bin_id] as RefCounted).get("task_name")),
				int((open[bin_id] as RefCounted).get("priority"))])
		if the_task == null:
			var act : Dictionary = board.get("_active")
			for nid in act.keys():
				var t : RefCounted = act[nid]
				if t == null or String(t.get("task_name")) != "overflow_dump":
					continue
				if t.get("indoor_container") != bin or bool(t.get("_done")):
					continue
				claimed = true
				attempts += 1
				the_task = t
				claim_npc = instance_from_id(nid) as Node
				_last_phase = -1
				print("    [t=%5.1fs] attempt #%d CLAIMED by NPC '%s' (role %s) at %s" %
					[f / 60.0, attempts, String(claim_npc.get("npc_name")),
					String(claim_npc.get("npc_role")),
					_v((claim_npc as Node3D).global_position) if claim_npc is Node3D else "?"])
				break
		if the_task != null:
			_trace(the_task, claim_npc, skip, f)
			best_phase = maxi(best_phase, int(the_task.get("_phase")))
			if bool(the_task.get("_done")):
				print("    [t=%5.1fs] attempt #%d TERMINAL: failed=%s reason='%s' (reached phase %d)" %
					[f / 60.0, attempts, str(the_task.get("_failed")),
					String(the_task.get("_fail_reason")), int(the_task.get("_phase"))])
				# A real shift keeps trying: the board's FAIL_RETRY_COOLDOWN_S
				# (NpcAutonomyBoard.gd:201) re-emits after 30 s and another idle
				# NPC can pick it up. Keep watching instead of stopping at the
				# first failure — otherwise one unlucky claimer would hide
				# whether the chain EVER works.
				last_task = the_task
				last_npc = claim_npc
				if float(bin.get("mass_kg")) < bin_before - 0.5:
					break
				the_task = null
				claim_npc = null
		if f % 3600 == 3599:
			print("    [t=%5.1fs] ... open=%d active=%d bin=%.1f kg skip=%.1f kg" %
				[(f + 1) / 60.0, (board.get("_open_tasks") as Dictionary).size(),
				(board.get("_active") as Dictionary).size(),
				float(bin.get("mass_kg")), float(skip.get("mass_kg"))])
	var bin_after : float = float(bin.get("mass_kg")) + float(bin.get("overflow_mass_kg"))
	var skip_after : float = float(skip.get("mass_kg")) + float(skip.get("overflow_mass_kg"))
	if the_task != null:
		last_task = the_task
		last_npc = claim_npc
	print("  [%s] %d claim attempt(s); deepest phase reached = %d (%s)" %
		[tag, attempts, best_phase,
		_phase_names[best_phase] if best_phase >= 0 and best_phase < _phase_names.size() else "none"])
	return {
		"tag": tag, "emitted": emitted, "claimed": claimed,
		"task": last_task, "npc": last_npc,
		"attempts": attempts, "best_phase": best_phase,
		"removed": bin_before - bin_after, "received": skip_after - skip_before,
		"bin_before": bin_before, "bin_after": bin_after,
		"skip_before": skip_before, "skip_after": skip_after,
	}

func _report_attempt(r: Dictionary, bin: Node3D, skip: Node3D) -> void:
	var tag : String = String(r.get("tag", "?"))
	_check(bool(r.get("emitted", false)),
		"[%s] the REAL board emitted an OverflowDumpTask for the REAL full bin" % tag)
	_check(bool(r.get("claimed", false)),
		"[%s] a REAL NPC claimed the task through take_next_task()" % tag)
	var the_task : RefCounted = r.get("task") as RefCounted
	if the_task != null:
		_check(the_task.get("outdoor_container") == skip,
			"[%s] the task's destination IS the ContainerGuide-spawned skip" % tag)
		var fk : Node3D = the_task.get("_forklift") as Node3D
		_check(fk != null,
			"[%s] the task resolved a real idle forklift out of group 'forklift'" % tag)
		var done : bool = bool(the_task.get("_done"))
		var failed : bool = bool(the_task.get("_failed"))
		_check(done and not failed,
			"[%s] task ran to completion (done=%s failed=%s reason='%s')" %
			[tag, str(done), str(failed), String(the_task.get("_fail_reason"))])
		if not done or failed:
			_stall_report(r, bin, skip)
	print("  [%s] bin  : %.2f -> %.2f kg  (removed %.2f)" %
		[tag, float(r["bin_before"]), float(r["bin_after"]), float(r["removed"])])
	print("  [%s] skip : %.2f -> %.2f kg  (received %.2f)" %
		[tag, float(r["skip_before"]), float(r["skip_after"]), float(r["received"])])

## The truthful deliverable when the chain does not finish: where it stopped,
## what the geometry was, and which gate was still unsatisfied.
func _stall_report(r: Dictionary, bin: Node3D, skip: Node3D) -> void:
	var the_task : RefCounted = r.get("task") as RefCounted
	var claim_npc : Node = r.get("npc") as Node
	var ph : int = int(the_task.get("_phase"))
	var fk : Node3D = the_task.get("_forklift") as Node3D
	print("\n  STALL REPORT (%s)" % String(r.get("tag", "?")))
	# npc-05 — report the task's ACTUAL budget for this phase. It is no longer a
	# flat 90 s: _travel_budget sizes it from the leg the actor has to cover, so
	# printing the old constant here would misdescribe every stall.
	print("    stuck in phase   : %d (%s), _phase_t = %.1f s of a %.0f s budget" %
		[ph, _phase_names[ph] if ph < _phase_names.size() else "?",
		float(the_task.get("_phase_t")), float(the_task.get("_phase_budget"))])
	if claim_npc != null and is_instance_valid(claim_npc):
		var np := claim_npc as Node3D
		print("    npc              : '%s' @ %s" % [String(claim_npc.get("npc_name")), _v(np.global_position)])
		print("    npc seated=%s physics_process=%s  <-- if seated but physics is OFF, _autonomy_tick can never tick the task again" %
			[str(claim_npc.get("_seated_in_vehicle")), str(claim_npc.is_physics_processing())])
		print("    npc parent       : %s" % str(claim_npc.get_parent().name))
		print("    npc._autonomy_task set=%s  _autonomy_destination_active=%s" %
			[str(claim_npc.get("_autonomy_task") != null),
			str(claim_npc.get("_autonomy_destination_active"))])
	if fk != null and is_instance_valid(fk):
		print("    forklift         : '%s' @ %s occupied=%s npc_autopilot=%s target_active=%s" %
			[fk.name, _v(fk.global_position), str(fk.get("occupied")),
			str(fk.get("npc_autopilot")), str(fk.get("_npc_target_active"))])
		if claim_npc is Node3D:
			print("    dist npc  -> fork: %.2f m (needs <= APPROACH_DIST_M 1.6)" %
				(claim_npc as Node3D).global_position.distance_to(fk.global_position))
		print("    dist fork -> bin : %.2f m (needs <= APPROACH_DIST_VEH 3.5)" %
			fk.global_position.distance_to(bin.global_position))
		print("    dist fork -> skip: %.2f m (needs <= APPROACH_DIST_VEH 3.5)" %
			fk.global_position.distance_to(skip.global_position))

## Watch a FORCED task (NPC._forced_task) to completion. Same observation-only
## contract as _attempt: nothing here advances the task.
func _watch_forced(tag: String, npc: Node3D, bin: Node3D, skip: Node3D, watch_s: float) -> Dictionary:
	var tree := get_tree()
	_last_phase = -1
	var bin_before : float = float(bin.get("mass_kg")) + float(bin.get("overflow_mass_kg"))
	var skip_before : float = float(skip.get("mass_kg")) + float(skip.get("overflow_mass_kg"))
	var task : RefCounted = npc.get("_forced_task") as RefCounted
	print("  [%s] forced task '%s' on '%s'; bin=%.2f kg skip=%.2f kg" %
		[tag, String(task.get("task_name")) if task != null else "?",
		String(npc.get("npc_name")), bin_before, skip_before])
	if task != null:
		_check(task.get("indoor_container") == bin,
			"[%s] the forced task's SOURCE is the full indoor bin" % tag)
		_check(task.get("outdoor_container") == skip,
			"[%s] the forced task's DESTINATION is the ContainerGuide skip (rule-4 fallback)" % tag)
	var best_phase : int = -1
	var frames : int = int(watch_s * 60.0)
	for f in range(frames):
		await tree.physics_frame
		if task == null:
			break
		_trace(task, npc, skip, f)
		best_phase = maxi(best_phase, int(task.get("_phase")))
		if bool(task.get("_done")):
			print("    [t=%5.1fs] forced task TERMINAL: failed=%s reason='%s'" %
				[f / 60.0, str(task.get("_failed")), String(task.get("_fail_reason"))])
			break
		if f % 3600 == 3599:
			print("    [t=%5.1fs] ... phase=%d bin=%.1f kg skip=%.1f kg npc_seated=%s" %
				[(f + 1) / 60.0, int(task.get("_phase")), float(bin.get("mass_kg")),
				float(skip.get("mass_kg")), str(npc.get("_seated_in_vehicle"))])
	var bin_after : float = float(bin.get("mass_kg")) + float(bin.get("overflow_mass_kg"))
	var skip_after : float = float(skip.get("mass_kg")) + float(skip.get("overflow_mass_kg"))
	print("  [%s] deepest phase reached = %d (%s)" % [tag, best_phase,
		_phase_names[best_phase] if best_phase >= 0 and best_phase < _phase_names.size() else "none"])
	return {
		"tag": tag, "emitted": true, "claimed": true,
		"task": task, "npc": npc, "best_phase": best_phase,
		"removed": bin_before - bin_after, "received": skip_after - skip_before,
		"bin_before": bin_before, "bin_after": bin_after,
		"skip_before": skip_before, "skip_after": skip_after,
	}

func _report_forced(r: Dictionary, bin: Node3D, skip: Node3D) -> void:
	var tag : String = String(r.get("tag", "?"))
	var task : RefCounted = r.get("task") as RefCounted
	if task != null:
		var done : bool = bool(task.get("_done"))
		var failed : bool = bool(task.get("_failed"))
		_check(done and not failed,
			"[%s] forced task ran to completion (done=%s failed=%s reason='%s')" %
			[tag, str(done), str(failed), String(task.get("_fail_reason"))])
		if not done or failed:
			_stall_report(r, bin, skip)
	print("  [%s] bin  : %.2f -> %.2f kg  (removed %.2f)" %
		[tag, float(r["bin_before"]), float(r["bin_after"]), float(r["removed"])])
	print("  [%s] skip : %.2f -> %.2f kg  (received %.2f)" %
		[tag, float(r["skip_before"]), float(r["skip_after"]), float(r["received"])])

func _nearest_eligible_npc(npcs: Dictionary, to: Vector3) -> Node3D:
	var best : Node3D = null
	var best_d : float = INF
	for k in npcs.keys():
		var n = npcs[k]
		if n == null or not is_instance_valid(n) or not (n is Node3D):
			continue
		var role := String(n.get("npc_role"))
		if not (role in ["all_rounder", "permanent_feeder", "transitional", "asst_shift_leader", "extruder_op"]):
			continue
		var d : float = (n as Node3D).global_position.distance_to(to)
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best

func _trace(task: RefCounted, npc: Node, skip: Node3D, frame: int) -> void:
	var ph : int = int(task.get("_phase"))
	# npc-05 boarding-deadlock sampling (see the counters' declaration). A seated
	# worker has _physics_process off; if the task's own _phase_t still advances
	# in that state, its tick is genuinely reachable from somewhere else.
	var pt : float = float(task.get("_phase_t"))
	# Seated = NPC._seated_in_vehicle (the flag OperatorContext sets), OR the
	# blunt physics-process-off state older bodies still use. Reading BOTH means
	# this guard cannot be defeated by swapping the mechanism back.
	var seated : bool = false
	if npc != null and is_instance_valid(npc):
		seated = bool(npc.get("_seated_in_vehicle")) or not (npc as Node).is_physics_processing()
	if seated and not bool(task.get("_done")):
		_seen_seated_frames += 1
		if ph == _last_phase and pt > _last_phase_t + 0.0001:
			_seen_seated_ticking += 1
	_last_phase_t = pt
	if ph == _last_phase:
		return
	_last_phase = ph
	_phase_first_seen_frame = frame
	var fk : Node3D = task.get("_forklift") as Node3D
	var npos := "n/a"
	var pp := "n/a"
	if npc is Node3D and is_instance_valid(npc):
		npos = _v((npc as Node3D).global_position)
		pp = "seated" if bool(npc.get("_seated_in_vehicle")) else "on foot"
	var fpos := "n/a"
	var fdist := "n/a"
	if fk != null and is_instance_valid(fk):
		fpos = _v(fk.global_position)
		fdist = "%.1f m to skip" % fk.global_position.distance_to(skip.global_position)
	print("    [t=%5.1fs] phase -> %s | npc %s (%s) | fork %s (%s)" %
		[frame / 60.0, _phase_names[ph] if ph < _phase_names.size() else "?",
		npos, pp, fpos, fdist])

func _path_report(map: RID, from: Vector3, to: Vector3, label: String) -> void:
	if not map.is_valid():
		_check(false, "navmesh path %s: navigation map RID invalid" % label)
		return
	var path : PackedVector3Array = NavigationServer3D.map_get_path(map, from, to, true)
	var straight : float = from.distance_to(to)
	if path.size() < 2:
		_check(false, "navmesh path %s: NO PATH (straight line %.1f m)" % [label, straight])
		return
	var walked : float = 0.0
	for i in range(1, path.size()):
		walked += path[i - 1].distance_to(path[i])
	# A path that terminates far from the goal means the navmesh could not reach it.
	var end_gap : float = path[path.size() - 1].distance_to(to)
	_check(end_gap < 6.0,
		"navmesh path %s: %d pts, %.1f m along mesh (straight %.1f m), ends %.1f m from the goal" %
		[label, path.size(), walked, straight, end_gap])

func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]

func _finish(code: int) -> void:
	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	if _world != null and is_instance_valid(_world):
		get_tree().current_scene = null
		_world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(code)

func _backup_files() -> void:
	for p in PROTECT:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_buffer(f.get_length())
			f.close()
		else:
			_backups[p] = null

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
