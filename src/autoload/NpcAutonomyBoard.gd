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
	# Generators 2-4 (stubs — see file footer for the planned generators).
	_scan_dirty_floor(tree, seen)
	_scan_overflow_containers(tree, seen)
	# Prune entries whose target has gone away.
	for tid in _open_tasks.keys():
		if not seen.has(tid):
			_open_tasks.erase(tid)

func _scan_lump_carts(tree: SceneTree, seen: Dictionary) -> void:
	for cart in tree.get_nodes_in_group("lump_cart"):
		if not is_instance_valid(cart):
			continue
		if not cart.has_method("is_cool") or not cart.has_method("has_lumps_worth_emptying"):
			continue
		if not bool(cart.call("is_cool")) or not bool(cart.call("has_lumps_worth_emptying")):
			continue
		var tid : int = cart.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			# Task already pending for this cart — leave it.
			continue
		var dest : Node3D = _choose_lumps_destination(tree)
		if dest == null:
			continue
		var script := load("res://src/scenes/world/tasks/EmptyLumpCartTask.gd")
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(cart, dest)
		_open_tasks[tid] = task

## Pick the indoor lumps_container by default; if it's full, fall back to the
## outdoor shipping_container per operator spec.
func _choose_lumps_destination(tree: SceneTree) -> Node3D:
	var indoor : Node3D = null
	for c in tree.get_nodes_in_group("lumps_container_indoor"):
		if c is Node3D and is_instance_valid(c):
			indoor = c
			break
	if indoor != null:
		var full : bool = false
		if indoor.has_method("is_full"):
			full = bool(indoor.call("is_full"))
		if not full:
			return indoor
	for c in tree.get_nodes_in_group("shipping_container_outdoor"):
		if c is Node3D and is_instance_valid(c):
			return c as Node3D
	return indoor   # nothing else — fall back to indoor even if full

# ── Stubs for future task generators (operator-described pipeline). ─────────
# Each can be filled in by writing a new NpcAutonomyTask subclass under
# src/scenes/world/tasks/ and emitting it here.

## Floor-wash + leaf-blower: NPC walks to the spray hose / leaf blower tool,
## brings it to a dirty patch near the wash line, runs it for ~30 s, returns
## the tool. Detect dirty patches by "dirty_floor" group nodes the
## flotation/scheidingsgoot drips into (each tick adds a "dirtiness" float;
## task fires above a threshold).
const CLEAN_COOLDOWN_S : float = 60.0 * 60.0   # 1 sim-hour between cleaning cycles per blower
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
	for blower in tree.get_nodes_in_group("leaf_blower"):
		if not is_instance_valid(blower):
			continue
		var tid : int = blower.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		var last : float = float(blower.get_meta("last_cleaned_at", -INF))
		var now : float = _now_sim_s_global(mw_ref)
		if (now - last) < CLEAN_COOLDOWN_S:
			continue
		if blower.has_meta("autonomy_claimed_by"):
			continue
		var script := load("res://src/scenes/world/tasks/BlowLeavesTask.gd")
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(blower as Node3D, mw_ref)
		_open_tasks[tid] = task

func _find_main_world(tree: SceneTree) -> Node:
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

## When the indoor lumps_container crosses is_full(), an NPC drives a forklift
## load of bulk lumps from indoor → outdoor shipping_container instead.
func _scan_overflow_containers(_tree: SceneTree, _seen: Dictionary) -> void:
	# TODO #198-followup: OverflowDumpTask. Triggered when
	# lumps_container_indoor.is_full() AND shipping_container_outdoor exists
	# AND there's at least one forklift idle. Phase pipeline mirrors
	# EmptyLumpCartTask: walk_to_forklift → drive_to_indoor → scoop_bulk →
	# drive_to_outdoor → dump.
	pass

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
