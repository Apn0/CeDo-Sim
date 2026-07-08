extends Node

# =============================================================================
# #198 — Autoload: dynamic plant-operator task board for autonomous NPCs.
# =============================================================================
# Periodically scans the live world for work that needs doing (full+cool lump
# carts, floor patches that need washing/blowing, overflowing lumps containers,
# etc.), instantiates a concrete NpcAutonomyTask per item, and serves them to
# idle NPCs on demand.
#
# Idle NPC's autonomy hook (in NPC.gd) calls take_next_task(self) every few
# seconds. The board returns the highest-priority task whose accept_roles
# includes the NPC's role (or that has empty accept_roles = anyone), and that
# isn't already claimed by another NPC.
#
# Each registered TaskGenerator below contributes 0..N tasks per scan; the
# board dedupes by target_node (one task per cart, one per dirty patch) so
# two NPCs never collide on the same work item.

const SCAN_INTERVAL_S : float = 5.0

# #198 — Shift-phase windows (sim-time, relative to shift_clock's elapsed).
# Drives the operator's stated cleaning cadence: NPCs prep the floor at the
# very start (catch-up from the previous shift's leftovers) and again in the
# last 3 hours (so team B inherits a clean workspace), but mostly sit on
# their hands in the middle because cleaning earlier just gets undone before
# bell. Outside both windows, the cooldown timer alone still allows a task
# if a tool genuinely hasn't been used in ages — a low-priority background
# fallback that line problems will preempt.
const STARTUP_WINDOW_S        : float = 30.0 * 60.0           # first 30 sim-min of shift
const HANDOVER_WINDOW_S       : float = 3.0 * 60.0 * 60.0     # last 3 sim-hours of shift
const PRIORITY_BOOST_HANDOVER : int   = 30                    # << bumps cleaning above line-routine
const PRIORITY_BOOST_STARTUP  : int   = 15                    # << smaller boost, still well below line-down
const PRIORITY_PENALTY_PROBLEM: int   = 50                    # << line-down kills cleaning preference

enum ShiftPhase { OFF_SHIFT, STARTUP, MID, HANDOVER }

# Pending tasks, keyed by their target_node's instance_id so a re-scan that
# re-discovers the same work item updates priority/dest in place instead of
# spawning duplicates.
var _open_tasks : Dictionary = {}   # int -> NpcAutonomyTask
# Active tasks (claimed by an NPC). Cleared on done/failed.
var _active : Dictionary = {}       # int -> NpcAutonomyTask, key = npc instance id

var _scan_t : float = 0.0

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_rescan()
	# Cull completed/failed active tasks.
	for npc_id in _active.keys():
		var t : NpcAutonomyTask = _active[npc_id]
		if t == null or t.is_done():
			_active.erase(npc_id)

## Idle NPC asks for work. Returns the highest-priority compatible task, or null.
func take_next_task(npc: Node) -> NpcAutonomyTask:
	if npc == null:
		return null
	if _active.has(npc.get_instance_id()):
		# Already on a task — don't hand out another one.
		return _active[npc.get_instance_id()]
	var role : String = _role_of(npc)
	var best : NpcAutonomyTask = null
	var best_pri : int = -1
	for tid in _open_tasks.keys():
		var t : NpcAutonomyTask = _open_tasks[tid]
		if t == null or t.is_done():
			continue
		if t._claimed_by != null and is_instance_valid(t._claimed_by):
			continue
		if t.accept_roles.size() > 0 and role != "" and not (role in t.accept_roles):
			continue
		if not t.can_start(npc):
			continue
		if t.priority > best_pri:
			best_pri = t.priority
			best = t
	if best != null:
		best.start(npc)
		_active[npc.get_instance_id()] = best
	return best

## Forced release — NPC gives up (e.g. shift bell). Frees the task so another
## NPC can pick it up on the next scan.
func release_task(npc: Node) -> void:
	var nid : int = npc.get_instance_id()
	if _active.has(nid):
		var t : NpcAutonomyTask = _active[nid]
		if t and not t.is_done():
			t.release(npc)
		_active.erase(nid)

# ── World scan: assemble the open task list from live state. ───────────────
func _rescan() -> void:
	var tree := get_tree()
	if tree == null:
		return
	var seen : Dictionary = {}   # instance_id → true (for dedup vs stale entries)
	# Generator 1: empty cooled lump carts.
	_scan_lump_carts(tree, seen)
	# Generators 2-5.
	_scan_dirty_floor(tree, seen)
	_scan_floor_piles(tree, seen)
	_scan_overflow_containers(tree, seen)
	# Prune entries whose target has gone away.
	for tid in _open_tasks.keys():
		if not seen.has(tid):
			_open_tasks.erase(tid)

func _scan_lump_carts(tree: SceneTree, seen: Dictionary) -> void:
	# #198 dynamic — Operator's spec: cooled lump carts go into the indoor
	# container, which holds ~8-10. End-of-shift, the goal is to leave that
	# container as empty as possible for team B, so we relax the "must be
	# cool + worth-emptying" gate during the handover window: even a
	# half-full cart gets emptied if cooled. Mid-shift, only full+cool
	# carts emit (so the crew isn't constantly chasing tiny loads).
	var mw_ref : Node = _find_main_world(tree)
	var phase : int = _shift_phase(mw_ref)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	var is_handover_push : bool = (phase == ShiftPhase.HANDOVER or phase == ShiftPhase.STARTUP)
	for cart in tree.get_nodes_in_group("lump_cart"):
		if not is_instance_valid(cart):
			continue
		if not cart.has_method("is_cool"):
			continue
		# Always require lumps to be cool (operator: 1-3 sim-hour cool-down
		# before they're safe to move).
		if not bool(cart.call("is_cool")):
			continue
		# Mid-shift: also require the cart to be worth a forklift run.
		# Handover push: any cooled lumps go.
		if not is_handover_push:
			if not cart.has_method("has_lumps_worth_emptying"):
				continue
			if not bool(cart.call("has_lumps_worth_emptying")):
				continue
		var tid : int = cart.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		var dest : Node3D = _choose_lumps_destination(tree)
		if dest == null:
			continue
		var script := load("res://src/scenes/world/tasks/EmptyLumpCartTask.gd")
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(cart, dest)
		task.priority += pri_mod
		_open_tasks[tid] = task

## #198 — Operator's container policy: indoor lumps container holds ~8-10
## lumps; we always WANT it as close to empty as possible at handover. So
## the destination logic:
##   1. If indoor container has room AND we're not in handover, use it
##      (normal "cool a few, dump them inside, continue" flow).
##   2. If we ARE in handover AND indoor already holds >= 3, route this load
##      to the outdoor shipping container instead — the operator's goal is
##      to leave the indoor container at most 1-3 deep for team B.
##   3. If indoor is full (>=8) at any time, route to outdoor.
##   4. Outdoor shipping container is the ultimate fallback (open-top, takes
##      bulk overflow).
const INDOOR_HANDOVER_TARGET : int = 3    # leave at most this many for team B
const INDOOR_HARD_CAP        : int = 8    # absolute "container is full"
func _choose_lumps_destination(tree: SceneTree) -> Node3D:
	# Real destinations are WasteContainer nodes (group "waste_container"); nothing
	# in the repo tags the old "lumps_container_indoor"/"shipping_container_outdoor"
	# groups. We prefer a container that isn't full (has_method receive_lumps +
	# not is_full); among those, take the emptiest. If every container is full we
	# still return the emptiest so a forklift run at least moves the cart off the
	# discharge (the container's own overflow model handles the spill).
	var mw_ref : Node = _find_main_world(tree)
	var in_handover : bool = _shift_phase(mw_ref) == ShiftPhase.HANDOVER
	var best_open : Node3D = null
	var best_open_fill : float = INF
	var best_any : Node3D = null
	var best_any_fill : float = INF
	for c in tree.get_nodes_in_group("waste_container"):
		if not (c is Node3D and is_instance_valid(c)):
			continue
		if not c.has_method("receive_lumps"):
			continue
		var fill : float = 0.0
		if c.has_method("fill_fraction"):
			fill = float(c.call("fill_fraction"))
		if fill < best_any_fill:
			best_any_fill = fill
			best_any = c as Node3D
		# During handover we tighten what counts as "open" so the crew leaves the
		# nearest bins emptier for team B (route to a less-loaded bin sooner).
		var full : bool = false
		if c.has_method("is_full"):
			full = bool(c.call("is_full"))
		if in_handover and fill >= 0.5:
			full = true
		if not full and fill < best_open_fill:
			best_open_fill = fill
			best_open = c as Node3D
	if best_open != null:
		return best_open
	return best_any   # everything full — emptiest still beats leaving the cart

# ── Stubs for future task generators (operator-described pipeline). ─────────
# Each can be filled in by writing a new NpcAutonomyTask subclass under
# src/scenes/world/tasks/ and emitting it here.

## Floor-wash + leaf-blower: NPC walks to the spray hose / leaf blower tool,
## brings it to a dirty patch near the wash line, runs it for ~30 s, returns
## the tool. Detect dirty patches by "dirty_floor" group nodes the
## flotation/scheidingsgoot drips into (each tick adds a "dirtiness" float;
## task fires above a threshold).
const CLEAN_COOLDOWN_S       : float = 60.0 * 60.0   # 1 h between leaf-blower cycles per blower
const WATER_HOSE_COOLDOWN_S  : float = 90.0 * 60.0   # 1.5 h between water hose-down cycles
const AIR_HOSE_COOLDOWN_S    : float = 40.0 * 60.0   # 40 min between air-hose blast cycles
func _scan_dirty_floor(tree: SceneTree, seen: Dictionary) -> void:
	# #198 followup — Leaf blower cleaning cycle. Emit one BlowLeavesTask per
	# leaf blower that hasn't been used in the last CLEAN_COOLDOWN_S. Without
	# a true DirtyFloorPatch + dirtiness accumulator, this is the "always-on"
	# fallback that gives the operator visible NPC cleaning behaviour. When
	# the dirty-patch system arrives, this generator gets gated on
	# patch.dirtiness > threshold instead of a flat cooldown.
	# SprayFloorTask (hose) follows the same pattern — add a sibling generator
	# when the hose's water-supply state is wired up.
	var mw_ref : Node = _find_main_world(tree)
	# Dynamic scheduling: outside the startup + handover windows AND with no
	# line problem to react to, don't bother emitting cleaning tasks unless
	# the cooldown timer says the tool genuinely hasn't been touched in ages.
	# Inside the windows we use a shortened "handover_cooldown" so a fresh
	# blower can be re-grabbed sooner during the end-of-shift push.
	var phase : int = _shift_phase(mw_ref)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	var handover_cooldown_s : float = CLEAN_COOLDOWN_S * 0.25   # 15 min instead of 60
	for blower in tree.get_nodes_in_group("leaf_blower"):
		if not is_instance_valid(blower):
			continue
		var tid : int = blower.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		var last : float = float(blower.get_meta("last_cleaned_at", -INF))
		var now : float = _now_sim_s_global(mw_ref)
		var cooldown_s : float = handover_cooldown_s if phase == ShiftPhase.HANDOVER or phase == ShiftPhase.STARTUP else CLEAN_COOLDOWN_S
		if (now - last) < cooldown_s:
			continue
		if blower.has_meta("autonomy_claimed_by"):
			continue
		var script := load("res://src/scenes/world/tasks/BlowLeavesTask.gd")
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(blower as Node3D, mw_ref)
		task.priority += pri_mod
		_open_tasks[tid] = task
	# Hose nozzles (water + air, same group, distinguished by `air_mode` flag).
	# Emit one HoseSweepTask per nozzle whose mode-specific cooldown is met.
	var hose_script := load("res://src/scenes/world/tasks/HoseSweepTask.gd")
	for nz in tree.get_nodes_in_group("hose_nozzle"):
		if not is_instance_valid(nz):
			continue
		var nz_tid : int = nz.get_instance_id()
		seen[nz_tid] = true
		if _open_tasks.has(nz_tid):
			continue
		if nz.has_meta("autonomy_claimed_by"):
			continue
		var is_air : bool = bool(nz.get("air_mode")) if "air_mode" in nz else false
		var cooldown : float = AIR_HOSE_COOLDOWN_S if is_air else WATER_HOSE_COOLDOWN_S
		# Cooldown shrinks during the cleaning windows (startup + handover) so
		# crews can re-grab a tool sooner on the end-of-shift push.
		if phase == ShiftPhase.HANDOVER or phase == ShiftPhase.STARTUP:
			cooldown *= 0.33
		var nz_last : float = float(nz.get_meta("last_cleaned_at", -INF))
		var nz_now : float = _now_sim_s_global(mw_ref)
		if (nz_now - nz_last) < cooldown:
			continue
		if hose_script == null:
			continue
		var nz_task : NpcAutonomyTask = hose_script.new(nz as Node3D, mw_ref)
		nz_task.priority += pri_mod
		_open_tasks[nz_tid] = nz_task

# ── Generator 3: shovel down FloorPiles that have built up. ──────────────────
# A FloorPile (src/sim/FloorPile.gd, group "floor_pile") accumulates loose
# material when bins overflow or LineFlow can't route a stream. Above
# SHOVEL_PILE_MIN_KG the heap starts blocking lanes / intakes, so an idle NPC
# grabs a shovel-worth of it into the nearest waste_container until it's low.
const SHOVEL_PILE_MIN_KG : float = 60.0
func _scan_floor_piles(tree: SceneTree, seen: Dictionary) -> void:
	var mw_ref : Node = _find_main_world(tree)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	for pile in tree.get_nodes_in_group("floor_pile"):
		if not is_instance_valid(pile):
			continue
		if not (pile is Node3D):
			continue
		if float(pile.get("mass_kg")) < SHOVEL_PILE_MIN_KG:
			continue
		var tid : int = pile.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		if pile.has_meta("autonomy_claimed_by"):
			continue
		var script := load("res://src/scenes/world/tasks/ShovelFloorPileTask.gd")
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(pile as Node3D, mw_ref)
		task.priority += pri_mod
		_open_tasks[tid] = task

func _find_main_world(tree: SceneTree) -> Node:
	# #audit-2026-07-08 — the root-children scan returned null in-game (autoload
	# nodes precede the world under /root and the match was fragile), so mw_ref was
	# null: BlowLeavesTask/HoseSweepTask fell back to raw plant-local waypoints near
	# origin and every cleaning task timed out ("NPCs do nothing"). current_scene is
	# the authoritative world node when loaded via change_scene — prefer it, keep the
	# scan as a fallback for harness/embedded cases.
	var cs := tree.current_scene
	if cs != null and cs is Node3D and "_player_spawn_pos" in cs:
		return cs
	for c in tree.get_root().get_children():
		if c is Node3D and "_player_spawn_pos" in c:
			return c
	return null

func _now_sim_s_global(mw: Node) -> float:
	if mw != null:
		var sc = mw.get("shift_clock")
		if sc != null and "shift_elapsed_seconds" in sc:
			return float(sc.shift_elapsed_seconds)
	return Time.get_ticks_msec() / 1000.0

# #198 dynamic scheduling — return the current shift phase so generators can
# decide whether to emit, and so they can boost/penalise task priority based
# on the operator's stated cleaning cadence.
func _shift_phase(mw: Node) -> int:
	if mw == null:
		return ShiftPhase.OFF_SHIFT
	var sc = mw.get("shift_clock")
	if sc == null or not bool(sc.get("shift_active")):
		return ShiftPhase.OFF_SHIFT
	var el : float = float(sc.get("shift_elapsed_seconds"))
	var total : float = float(sc.get("shift_total_seconds"))
	if el < 0.0:
		return ShiftPhase.OFF_SHIFT     # pre-shift, NPCs are arriving/dressing
	if el < STARTUP_WINDOW_S:
		return ShiftPhase.STARTUP
	if total > 0.0 and (total - el) < HANDOVER_WINDOW_S:
		return ShiftPhase.HANDOVER
	return ShiftPhase.MID

# Active line problems preempt cleaning — operator made the point that these
# behaviours are dynamic, not static schedules. Returns true if any line is
# down/faulted right now (ScadaDashboard active alarm list, or fallback to
# any node in group "line_fault"). When true, generators DROP their cleaning
# task priority by PRIORITY_PENALTY_PROBLEM so line-fix tasks (when those
# exist) easily out-bid the cleaners.
func _line_problem_active(mw: Node) -> bool:
	if mw == null:
		return false
	var scada = mw.get("scada")
	if scada != null and scada.has_method("any_active_alarm"):
		if bool(scada.call("any_active_alarm")):
			return true
	# Fallback: any node tagged with the convention group "line_fault".
	var t := get_tree() if has_method("get_tree") else null
	if t != null:
		var faults : Array = t.get_nodes_in_group("line_fault")
		if not faults.is_empty():
			return true
	return false

# Returns the priority modifier to apply on top of a task's base priority,
# combining shift-phase boost with line-problem penalty. Cleaning generators
# call this once at emit time.
func _cleaning_priority_modifier(mw: Node) -> int:
	var mod : int = 0
	match _shift_phase(mw):
		ShiftPhase.STARTUP:  mod += PRIORITY_BOOST_STARTUP
		ShiftPhase.HANDOVER: mod += PRIORITY_BOOST_HANDOVER
		_: pass
	if _line_problem_active(mw):
		mod -= PRIORITY_PENALTY_PROBLEM
	return mod

## When a WasteContainer crosses needs_emptying(), an NPC walks over and empties
## it (WasteContainer.empty()) so it stops spilling onto the floor. On-foot reset
## rather than a forklift tip — cheap, and enough to keep the bin from staying
## BLOCKED. One OverflowDumpTask per over-full container.
func _scan_overflow_containers(tree: SceneTree, seen: Dictionary) -> void:
	var mw_ref : Node = _find_main_world(tree)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	for bin in tree.get_nodes_in_group("waste_container"):
		if not is_instance_valid(bin):
			continue
		if not (bin is Node3D):
			continue
		if not bin.has_method("needs_emptying"):
			continue
		if not bool(bin.call("needs_emptying")):
			continue
		var tid : int = bin.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		if bin.has_meta("autonomy_claimed_by"):
			continue
		var script := load("res://src/scenes/world/tasks/OverflowDumpTask.gd")
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(bin as Node3D, mw_ref)
		task.priority += pri_mod
		_open_tasks[tid] = task

func _role_of(npc: Node) -> String:
	if npc == null:
		return ""
	if not ("npc_id" in npc):
		return ""
	var npc_id : String = String(npc.npc_id)
	if npc_id == "":
		return ""
	# Pull role out of NPCSpawner.NPC_DATA without coupling to MainWorld.
	var npc_data : Dictionary = NPCSpawner.NPC_DATA if "NPC_DATA" in NPCSpawner else {}
	if not npc_data.has(npc_id):
		return ""
	return String(npc_data[npc_id].get("role", ""))
