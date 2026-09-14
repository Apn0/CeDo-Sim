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
var _active : Dictionary = {}

const SHOVEL_TASK_SCRIPT : Variant = preload("res://src/scenes/world/tasks/ShovelFloorPileTask.gd")
const BLOW_LEAVES_TASK_SCRIPT : Variant = preload("res://src/scenes/world/tasks/BlowLeavesTask.gd")
const HOSE_SWEEP_TASK_SCRIPT : Variant = preload("res://src/scenes/world/tasks/HoseSweepTask.gd")
const OVERFLOW_DUMP_TASK_SCRIPT : Variant = preload("res://src/scenes/world/tasks/OverflowDumpTask.gd")
const REFUEL_BLOWER_TASK_SCRIPT : Variant = preload("res://src/scenes/world/tasks/RefuelBlowerTask.gd")
const EMPTY_CART_TASK_SCRIPT : Variant = preload("res://src/scenes/world/tasks/EmptyLumpCartTask.gd")

# ── Storing fixen (operator 2026-08-07) ──────────────────────────────────────
# Active storingen, key "<machine_id>/<alarm_id>" -> {machine_id, alarm_id,
# severity, pos}. Fed by EventBus machine_alarm_raised/cleared plus the
# board-side INV-101 feed-starvation monitor below (the HmiOverlay version of
# that check only runs while the overlay is open — the operator's "no bale at
# feeder belt with nobody assigned" case must not depend on an open UI).
var _storing_alarms : Dictionary = {}
# Storing-fixen dispatch weight: score = priority − distance × this. Priorities
# span ~28-90 and the site ~200 m, so 0.15/m lets ~30 m of extra walking beat
# one severity point but never outweigh a big priority gap.
const STORING_DIST_COST_PER_M : float = 0.15
const STORING_ROLE : String = "storing_fixen"
# INV-101 mirror of HmiOverlay's derived fault: feed enabled + fed_mass
# stagnant longer than this. Same 3 s the overlay uses.
const NO_FEED_ALARM_S : float = 3.0
var _last_fed_mass : float = -1.0
var _no_feed_t : float = 0.0
# npc-ack registry: alarm codes acknowledged by a storing-fixen worker at an
# HMI panel (KwitterenStoringTask). HmiOverlay ORs these into its own
# KWITTEREN state so the bell calms; codes drop out when their fault clears.
var _npc_acked : Dictionary = {}
# Post-completion linger (task.linger_s): npc instance id -> wall-s first seen
# done. While lingering the worker stays in _active and gets NO new task.
var _done_seen : Dictionary = {}

var _scan_t : float = 0.0

func _ready() -> void:
	set_process(true)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		if bus.has_signal("machine_alarm_raised"):
			bus.connect("machine_alarm_raised", _on_machine_alarm_raised)
		if bus.has_signal("machine_alarm_cleared"):
			bus.connect("machine_alarm_cleared", _on_machine_alarm_cleared)

func _process(delta: float) -> void:
	_scan_t += delta
	if _scan_t >= SCAN_INTERVAL_S:
		_scan_t = 0.0
		_rescan()
	_tick_feed_starvation_monitor(delta)
	# Cull completed/failed active tasks — honouring the per-task linger:
	# a task with linger_s keeps its worker in _active (unavailable to
	# take_next_task) for linger_s seconds after completion.
	var now : float = Time.get_ticks_msec() / 1000.0
	for npc_id in _active.keys():
		var t : NpcAutonomyTask = _active[npc_id]
		if t == null:
			_active.erase(npc_id)
			_done_seen.erase(npc_id)
		elif t.is_done():
			if t.linger_s > 0.0:
				if not _done_seen.has(npc_id):
					_done_seen[npc_id] = now
				elif now - float(_done_seen[npc_id]) >= t.linger_s:
					_active.erase(npc_id)
					_done_seen.erase(npc_id)
			else:
				_active.erase(npc_id)
				_done_seen.erase(npc_id)

## Idle NPC asks for work. Returns the highest-priority compatible task, or
## null. Storing-fixen workers (operator 2026-08-07) pick by BOTH variables —
## closest + most important — via a combined score; every other role keeps the
## original pure-priority pick so the bench-proven assignment order stands.
func take_next_task(npc: Node) -> NpcAutonomyTask:
	if npc == null:
		return null
	if _active.has(npc.get_instance_id()):
		var cur : NpcAutonomyTask = _active[npc.get_instance_id()]
		if cur != null and cur.is_done():
			# Post-completion linger: the worker is still bound to the finished
			# task for its linger_s — no new task until _process releases them.
			return null
		# Already on a task — don't hand out another one.
		return cur
	var role : String = _role_of(npc)
	var storing_picker : bool = (role == STORING_ROLE)
	var npc_pos : Vector3 = (npc as Node3D).global_position if npc is Node3D else Vector3.ZERO
	var best : NpcAutonomyTask = null
	var best_score : float = -INF
	for tid in _open_tasks.keys():
		var t : NpcAutonomyTask = _open_tasks[tid]
		if t == null or t.is_done():
			continue
		if t._claimed_by != null and is_instance_valid(t._claimed_by):
			continue
		if t.excluded_npc != null and is_instance_valid(t.excluded_npc) and t.excluded_npc == npc:
			continue
		if t.accept_roles.size() > 0 and role != "" and not (role in t.accept_roles):
			continue
		if not t.can_start(npc):
			continue
		var score : float = float(t.priority)
		if storing_picker:
			score -= _task_distance_m(t, npc_pos) * STORING_DIST_COST_PER_M
		if score > best_score:
			best_score = score
			best = t
	if best != null:
		best.start(npc)
		_active[npc.get_instance_id()] = best
	return best

## Distance from an NPC to a task's work site, for the storing-fixen combined
## score. Prefers the live target node; falls back to the storing task's own
## stored position; 0 when neither exists (pure-priority behaviour).
func _task_distance_m(t: NpcAutonomyTask, from_pos: Vector3) -> float:
	if t.target_node != null and is_instance_valid(t.target_node):
		return (t.target_node.global_position - from_pos).length()
	var p = t.get("target_pos")
	if p is Vector3:
		return ((p as Vector3) - from_pos).length()
	return 0.0

## Forced release — NPC gives up (e.g. shift bell). Frees the task so another
## NPC can pick it up on the next scan.
func release_task(npc: Node) -> void:
	var nid : int = npc.get_instance_id()
	if _active.has(nid):
		var t : NpcAutonomyTask = _active[nid]
		if t and not t.is_done():
			t.release(npc)
			# npc-01 — un-claim: the base release() never clears _claimed_by, so
			# a shift-bell/production release left the still-open task pointing
			# at a valid NPC and take_next_task skipped it for the session.
			t._claimed_by = null
		_active.erase(nid)

## #198 operator override — CrewPanel task dropdown assigns a specific chore to
## a specific worker. Builds the concrete task targeting the NEAREST relevant
## node to the npc, hands it to the npc as a FORCED task (which overrides the
## production gate + auto-poll in NPC._autonomy_tick), and returns true.
## Returns false if npc is invalid or no valid target/dest exists for `kind`.
## BYPASSES accept_roles + shift-window gating — the operator's word is law.
func force_task(npc: Node, kind: String) -> bool:
	if npc == null or not is_instance_valid(npc):
		return false
	if not npc.has_method("assign_forced_task"):
		return false
	var tree := get_tree()
	if tree == null:
		return false
	var task : NpcAutonomyTask = _build_forced_task(tree, npc, kind)
	if task == null:
		return false
	npc.call("assign_forced_task", task)
	return true

## Concrete task factory for force_task(). Nearest-node target resolution per
## kind; returns null if the required target (or destination) is missing.
func _build_forced_task(tree: SceneTree, npc: Node, kind: String) -> NpcAutonomyTask:
	var mw_ref : Node = _find_main_world(tree)
	match kind:
		"blow_leaves":
			var blower : Node3D = _nearest_in_group(tree, "leaf_blower", npc)
			if blower == null:
				return null
			var s : Variant = BLOW_LEAVES_TASK_SCRIPT
			if s == null:
				return null
			return s.new(blower, mw_ref)
		"hose_sweep":
			var nozzle : Node3D = _nearest_in_group(tree, "hose_nozzle", npc)
			if nozzle == null:
				return null
			var s : Variant = HOSE_SWEEP_TASK_SCRIPT
			if s == null:
				return null
			return s.new(nozzle, mw_ref)
		"shovel_pile":
			var pile : Node3D = _nearest_in_group(tree, "floor_pile", npc)
			if pile == null:
				return null
			var s : Variant = SHOVEL_TASK_SCRIPT
			if s == null:
				return null
			return s.new(pile, mw_ref)
		"empty_lump_cart":
			var cart : Node3D = _nearest_in_group(tree, "lump_cart", npc)
			if cart == null:
				return null
			var dest : Node3D = _choose_lumps_destination(tree)
			if dest == null:
				return null
			var s : Variant = EMPTY_CART_TASK_SCRIPT
			if s == null:
				return null
			return s.new(cart, dest)
		"overflow_dump":
			var bin : Node3D = _nearest_in_group(tree, "waste_container", npc)
			if bin == null:
				return null
			# npc-04 — resolve a REAL receiving container. This arm used to pass
			# mw_ref (the whole MainWorld node) as the destination: the forklift
			# drove to world origin and the scooped mass silently vanished (the
			# root has neither add() nor receive_lumps()). No second container →
			# no valid task → force_task returns false → CrewPanel "geen doel".
			var dump_dest : Node3D = _choose_lumps_destination(tree, bin)
			if dump_dest == null:
				return null
			var s : Variant = OVERFLOW_DUMP_TASK_SCRIPT
			if s == null:
				return null
			return s.new(bin, dump_dest)
		"refuel_blower":
			# Target the blower that most needs it (lowest fuel), tie-broken by
			# nearest; the can is the one nearest the operator-picked npc.
			var blower : Node3D = _lowest_fuel_blower(tree, npc)
			if blower == null:
				return null
			var can : Node3D = _nearest_in_group(tree, "jerrycan", npc)
			if can == null:
				return null
			var s : Variant = REFUEL_BLOWER_TASK_SCRIPT
			if s == null:
				return null
			return s.new(blower, can, mw_ref)
		_:
			return null

# ── World scan: assemble the open task list from live state. ───────────────
# npc-01 — how long a FAILED task blocks re-emission for its target. The failed
# entry is kept in _open_tasks (take_next_task already skips done tasks) until
# the cooldown lapses; then the reap below frees the key and the generator
# re-emits a fresh task on the same scan. Prevents instant thrash against a
# persistently-failing target (e.g. no forklift available yet).
const FAIL_RETRY_COOLDOWN_S : float = 30.0

func _rescan() -> void:
	var tree := get_tree()
	if tree == null:
		return
	# npc-01 — reap terminal tasks FIRST so a still-qualifying target gets a
	# fresh task from its generator on this same scan. Previously a done task
	# wedged its key in _open_tasks forever: one failure (phase_timeout,
	# no_forklift_available, …) permanently blocked that cart/blower/pile.
	var now_s : float = Time.get_ticks_msec() / 1000.0
	for tid in _open_tasks.keys():
		var t : NpcAutonomyTask = _open_tasks[tid]
		if t == null:
			_open_tasks.erase(tid)
			continue
		if not t.is_done():
			continue
		if t.is_failed() and (now_s - t._failed_at) < FAIL_RETRY_COOLDOWN_S:
			continue   # hold as a re-emit block until the retry cooldown lapses
		_open_tasks.erase(tid)
	var seen : Dictionary = {}   # instance_id → true (for dedup vs stale entries)
	# Generators 1-6
	_scan_lump_carts(tree, seen)
	_scan_low_fuel_blowers(tree, seen)
	_scan_dirty_floor(tree, seen)
	_scan_floor_piles(tree, seen)
	_scan_overflow_containers(tree, seen)
	_scan_storing_alarms(seen)
	# Prune entries whose target has gone away.
	for tid in _open_tasks.keys():
		if not seen.has(tid):
			_open_tasks.erase(tid)
	# npc-09 — refresh open UNCLAIMED task priorities in place (what the header
	# comment always promised): a task emitted mid-shift picks up the +30
	# handover boost when the window opens, and a task emitted during a line
	# fault sheds its -50 penalty once the fault clears — instead of losing
	# every priority contest to fresher tasks for the rest of the shift.
	var mw_ref : Node = _find_main_world(tree)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	for otid in _open_tasks.keys():
		var ot : NpcAutonomyTask = _open_tasks[otid]
		if ot == null or ot.is_done():
			continue
		if ot._claimed_by != null and is_instance_valid(ot._claimed_by):
			continue
		# Storing tasks are exempt from the CLEANING modifier — the −50
		# line-problem penalty exists to park housekeeping during a fault,
		# and the storing task IS the fault response.
		if ot.task_name == "fix_storing" or ot.task_name == "kwitteren_storing":
			continue
		ot.priority = ot.base_priority + pri_mod

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
		var script : Variant = EMPTY_CART_TASK_SCRIPT
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(cart, dest)
		task.base_priority = task.priority   # npc-09 — snapshot for in-place refresh
		task.priority += pri_mod
		_open_tasks[tid] = task

## #198 — Operator's container policy (npc-05 — picks on fill_fraction() now;
## the old lumps-count constants are comment-history: INDOOR_HANDOVER_TARGET
## (= 3) is gone, INDOOR_HARD_CAP survives only as the lumps_count fallback in
## _scan_overflow_containers()). Destination logic:
##   1. If an indoor bin has room, use the emptiest one (normal "cool a few,
##      dump them inside, continue" flow).
##   2. During handover a bin already counts as full from fill_fraction()
##      >= 0.5 — the operator's goal is to leave the indoor bins near-empty
##      for team B, so loads route onward sooner.
##   3. Bins reporting is_full() are never "open", at any time.
##   4. The outdoor skip (group "waste_container_outdoor", lowest fill) is the
##      ultimate fallback (open-top, takes bulk overflow) once no indoor bin
##      is open; with no skip in the world, fall back to the emptiest indoor.
const INDOOR_HARD_CAP : int = 8   # npc-05 — only _scan_overflow_containers()'s lumps_count fallback reads this
## `exclude` (npc-04): skip this container when picking — a dump's SOURCE bin
## must never be chosen as its own destination.
func _choose_lumps_destination(tree: SceneTree, exclude: Node3D = null) -> Node3D:
	# npc-05 — #198 revived: indoor candidates are "waste_container" nodes NOT
	# in "waste_container_outdoor"; the outdoor skip is tracked separately as
	# the rule-4 fallback. Among open indoor bins take the emptiest; if none is
	# open (all full, or handover-tightened) return the least-filled skip; with
	# no skip in the world return the emptiest indoor anyway so a forklift run
	# at least moves the cart off the discharge (the container's own overflow
	# model handles the spill).
	var mw_ref : Node = _find_main_world(tree)
	var in_handover : bool = _shift_phase(mw_ref) == ShiftPhase.HANDOVER
	var best_open : Node3D = null
	var best_open_fill : float = INF
	var best_any : Node3D = null
	var best_any_fill : float = INF
	var outdoor_lowest : Node3D = null   # npc-05 — least-filled outdoor skip
	var outdoor_lowest_fill : float = INF
	for c in tree.get_nodes_in_group("waste_container"):
		if not (c is Node3D and is_instance_valid(c)):
			continue
		if exclude != null and c == exclude:
			continue   # npc-04 — never dump a container into itself
		if not c.has_method("receive_lumps"):
			continue
		var fill : float = 0.0
		if c.has_method("fill_fraction"):
			fill = float(c.call("fill_fraction"))
		if c.is_in_group("waste_container_outdoor"):
			# npc-05 — skips are destinations only, never indoor candidates
			# (otherwise: outdoor full → dump outdoor→outdoor loop).
			if fill < outdoor_lowest_fill:
				outdoor_lowest_fill = fill
				outdoor_lowest = c as Node3D
			continue
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
	if outdoor_lowest != null:
		return outdoor_lowest   # npc-05 — #198 rule 4: indoor full/tightened → outdoor skip
	return best_any   # npc-05 — no skip in the world: emptiest indoor still beats leaving the cart

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
		var script : Variant = BLOW_LEAVES_TASK_SCRIPT
		if script == null:
			continue
		var task : NpcAutonomyTask = script.new(blower as Node3D, mw_ref)
		task.base_priority = task.priority   # npc-09 — snapshot for in-place refresh
		task.priority += pri_mod
		_open_tasks[tid] = task
	# Hose nozzles (water + air, same group, distinguished by `air_mode` flag).
	# Emit one HoseSweepTask per nozzle whose mode-specific cooldown is met.
	var hose_script : Variant = HOSE_SWEEP_TASK_SCRIPT
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
		nz_task.base_priority = nz_task.priority   # npc-09 — snapshot for in-place refresh
		nz_task.priority += pri_mod
		_open_tasks[nz_tid] = nz_task

# ── Generator 3: shovel down FloorPiles that have built up. ──────────────────
# A FloorPile (src/sim/FloorPile.gd, group "floor_pile") accumulates loose
# material when bins overflow or LineFlow can't route a stream. Above
# SHOVEL_PILE_MIN_KG the heap starts blocking lanes / intakes, so an idle NPC
# grabs a shovel-worth of it into the nearest waste_container until it's low.
const SHOVEL_PILE_MIN_KG : float = 60.0
# 2026-08-31 review: this script used to be load()ed inside the per-pile loop
# below — a synchronous ResourceLoader hit per big heap on every 5 s scan.
# Hoisted to a parse-time preload (checked: neither ShovelFloorPileTask nor its
# base NpcAutonomyTask loads this board back, so no preload cycle).
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
		if SHOVEL_TASK_SCRIPT == null:
			continue   # same skip-this-pile degrade as the old per-loop load()
		var task : NpcAutonomyTask = SHOVEL_TASK_SCRIPT.new(pile as Node3D, mw_ref)
		task.base_priority = task.priority   # npc-09 — snapshot for in-place refresh
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

## npc-05 — When any indoor waste_container crosses is_full(), an NPC drives a
## forklift load of bulk lumps from that bin to the outdoor skip (group
## "waste_container_outdoor") with the most room — one OverflowDumpTask PER
## full indoor bin. No skip in the world, or no idle forklift → emit nothing.
func _scan_overflow_containers(tree: SceneTree, seen: Dictionary) -> void:
	# npc-05 — FIRST protect dump tasks that are ALREADY open from _rescan's
	# stale-prune (:235-237), before any of the gates below can early-return.
	# `seen` means "this target still exists", and a bin that is still in the
	# world and still full has NOT gone away. Because the gates returned before
	# populating it, the instant ANY forklift became occupied — an NPC boarding
	# one to run this very task, or the operator simply climbing into it — the
	# prune erased the in-flight task's key. Measured live as open=0 while
	# active=2. Note this only re-confirms EXISTING keys: with no skip in the
	# world (or no idle forklift) no NEW key is ever created, so a world without
	# an outdoor destination still emits and marks nothing.
	for held in tree.get_nodes_in_group("waste_container"):
		if not (held is Node3D and is_instance_valid(held)):
			continue
		if held.is_in_group("waste_container_outdoor"):
			continue
		var held_id : int = held.get_instance_id()
		if _open_tasks.has(held_id):
			seen[held_id] = true

	# npc-05 — destination: the outdoor skip with the lowest fill_fraction().
	var outdoor : Node3D = null
	var outdoor_fill : float = INF
	for c in tree.get_nodes_in_group("waste_container_outdoor"):
		if not (c is Node3D and is_instance_valid(c)):
			continue
		var fill : float = 0.0
		if c.has_method("fill_fraction"):
			fill = float(c.call("fill_fraction"))
		if fill < outdoor_fill:
			outdoor_fill = fill
			outdoor = c as Node3D
	if outdoor == null:
		return

	# npc-05 — global gate: without an idle forklift no dump run can start, so
	# don't emit (or refresh `seen`) for any bin this scan.
	var has_idle_forklift : bool = false
	for f in tree.get_nodes_in_group("forklift"):
		if f is Node3D and is_instance_valid(f):
			if not ("occupied" in f and bool(f.get("occupied"))):
				has_idle_forklift = true
				break
	if not has_idle_forklift:
		return

	var script : Variant = OVERFLOW_DUMP_TASK_SCRIPT
	if script == null:
		return

	var mw_ref : Node = _find_main_world(tree)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	# npc-05 — one task per full indoor bin (the old code emitted only for the
	# first bin it happened to find). Indoor = in "waste_container" but NOT in
	# "waste_container_outdoor".
	for bin in tree.get_nodes_in_group("waste_container"):
		if not (bin is Node3D and is_instance_valid(bin)):
			continue
		if bin.is_in_group("waste_container_outdoor"):
			continue   # npc-05 — the skip is a destination, never a source
		var is_full : bool = false
		if bin.has_method("is_full"):
			is_full = bool(bin.call("is_full"))
		elif "lumps_count" in bin:
			is_full = int(bin.get("lumps_count")) >= INDOOR_HARD_CAP
		if not is_full:
			continue
		var tid : int = bin.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		var task : NpcAutonomyTask = script.new(bin as Node3D, outdoor)
		task.base_priority = task.priority   # npc-09 — snapshot for in-place refresh
		task.priority += pri_mod
		_open_tasks[tid] = task

# ── Generator 1b: refuel low-fuel leaf blowers. ─────────────────────────────
# A two-stroke leaf blower runs dry (LeafBlower.fuel_pct()); once below
# RefuelBlowerTask.FUEL_LOW_FRACTION it can't do useful work, so an idle NPC
# fetches fuel from a jerrycan and tops it up. Only meaningful when at least
# one "jerrycan" is placed in the scene — with no can there's nowhere to refuel
# from, so we emit nothing. Deduped by the blower's instance id (shares the
# _open_tasks keyspace with the blow-circuit generator, so a given blower holds
# at most one of {refuel, blow} — refuel wins because this runs first).
func _scan_low_fuel_blowers(tree: SceneTree, seen: Dictionary) -> void:
	var jerrycans : Array = tree.get_nodes_in_group("jerrycan")
	if jerrycans.is_empty():
		return   # nowhere to refuel from — don't emit
	var rb_script : Variant = REFUEL_BLOWER_TASK_SCRIPT
	if rb_script == null:
		return
	# Read FUEL_LOW_FRACTION off the loaded script (avoids a hard class_name
	# dependency at parse time). Fall back to 0.25 if the const isn't present.
	var low_frac : float = 0.25
	var consts : Dictionary = rb_script.get_script_constant_map()
	if consts.has("FUEL_LOW_FRACTION"):
		low_frac = float(consts["FUEL_LOW_FRACTION"])
	var mw_ref : Node = _find_main_world(tree)
	var pri_mod : int = _cleaning_priority_modifier(mw_ref)
	for blower in tree.get_nodes_in_group("leaf_blower"):
		if not (blower is Node3D and is_instance_valid(blower)):
			continue
		if _blower_fuel_fraction(blower) >= low_frac:
			continue   # still has fuel — let the blow-circuit generator have it
		var tid : int = blower.get_instance_id()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		if blower.has_meta("autonomy_claimed_by"):
			continue
		var can : Node3D = _nearest_in_group(tree, "jerrycan", blower)
		if can == null:
			continue
		var task : NpcAutonomyTask = rb_script.new(blower as Node3D, can, mw_ref)
		task.base_priority = task.priority   # npc-09 — snapshot for in-place refresh
		task.priority += pri_mod
		_open_tasks[tid] = task

func _role_of(npc: Node) -> String:
	if npc == null:
		return ""
	# Prefer the role set LIVE on the NPC node (the spawner / CrewManager set it).
	# Reading it here decouples this autoload from the NPCSpawner class_name, whose
	# script references the Plant autoload — so the board stays compilable and
	# unit-testable headless (no NPCSpawner→Plant compile chain).
	if "npc_role" in npc and String(npc.npc_role) != "":
		return String(npc.npc_role)
	# Fallback: NPCSpawner.NPC_DATA by npc_id, loaded at RUNTIME (not a compile-time
	# class reference) so an un-tagged node still resolves in-game.
	if not ("npc_id" in npc) or String(npc.npc_id) == "":
		return ""
	var cat := _npc_role_catalog()
	var nid : String = String(npc.npc_id)
	if cat.has(nid):
		return String((cat[nid] as Dictionary).get("role", ""))
	return ""

# Lazily load NPCSpawner.NPC_DATA once via load() so this autoload carries NO
# compile-time dependency on NPCSpawner (which pulls in the Plant autoload).
var _role_catalog_cache : Dictionary = {}
var _role_catalog_tried : bool = false
func _npc_role_catalog() -> Dictionary:
	if _role_catalog_tried:
		return _role_catalog_cache
	_role_catalog_tried = true
	var scr = load("res://src/scenes/world/NPCSpawner.gd")
	if scr != null and scr.has_method("get_script_constant_map"):
		var consts : Dictionary = scr.get_script_constant_map()
		if consts.has("NPC_DATA") and consts["NPC_DATA"] is Dictionary:
			_role_catalog_cache = consts["NPC_DATA"]
	return _role_catalog_cache

# ── Shared spatial helpers ──────────────────────────────────────────────────

## Nearest live Node3D in `group` to `ref`'s global position. `ref` may be any
## Node3D (an npc or another node such as a blower); a non-Node3D / null ref
## degrades to distance-from-origin. Returns null if the group is empty.
func _nearest_in_group(tree: SceneTree, group: String, ref: Node) -> Node3D:
	if tree == null:
		return null
	var origin : Vector3 = Vector3.ZERO
	if ref is Node3D and is_instance_valid(ref):
		origin = (ref as Node3D).global_position
	var best : Node3D = null
	var best_d : float = INF
	for n in tree.get_nodes_in_group(group):
		if not (n is Node3D and is_instance_valid(n)):
			continue
		var d : float = ((n as Node3D).global_position - origin).length()
		if d < best_d:
			best_d = d
			best = n as Node3D
	return best

## The leaf blower that most needs refuelling: lowest fuel fraction, ties broken
## by proximity to `ref`. Returns null if no leaf blower exists.
func _lowest_fuel_blower(tree: SceneTree, ref: Node) -> Node3D:
	if tree == null:
		return null
	var origin : Vector3 = Vector3.ZERO
	if ref is Node3D and is_instance_valid(ref):
		origin = (ref as Node3D).global_position
	var best : Node3D = null
	var best_frac : float = INF
	var best_d : float = INF
	for b in tree.get_nodes_in_group("leaf_blower"):
		if not (b is Node3D and is_instance_valid(b)):
			continue
		var frac : float = _blower_fuel_fraction(b)
		var d : float = ((b as Node3D).global_position - origin).length()
		if frac < best_frac - 0.0001 or (absf(frac - best_frac) <= 0.0001 and d < best_d):
			best_frac = frac
			best_d = d
			best = b as Node3D
	return best

## Fuel fraction 0..1 for a leaf blower. Prefers the LeafBlower.fuel_pct() API;
## falls back to fuel_l / fuel_capacity_l; defaults to 1.0 (treat as full, i.e.
## "no refuel needed") when no fuel state is exposed.
func _blower_fuel_fraction(b: Node) -> float:
	if b == null:
		return 1.0
	if b.has_method("fuel_pct"):
		return float(b.call("fuel_pct"))
	var cap : float = float(b.get("fuel_capacity_l")) if "fuel_capacity_l" in b else 0.0
	var lvl : float = float(b.get("fuel_l")) if "fuel_l" in b else 0.0
	if cap > 0.0:
		return clampf(lvl / cap, 0.0, 1.0)
	return 1.0

# =============================================================================
# Storing fixen (operator 2026-08-07) — alarm registry, generator, ack registry
# =============================================================================

func _on_machine_alarm_raised(machine_id: String, alarm_id: String, severity: int) -> void:
	var key := "%s/%s" % [machine_id, alarm_id]
	if _storing_alarms.has(key):
		return
	_storing_alarms[key] = {
		"machine_id": machine_id, "alarm_id": alarm_id,
		"severity": severity, "pos": _station_pos(machine_id),
	}
	print("[NpcAutonomyBoard] storing raised: %s (sev %d)" % [key, severity])

func _on_machine_alarm_cleared(machine_id: String, alarm_id: String) -> void:
	var key := "%s/%s" % [machine_id, alarm_id]
	if _storing_alarms.has(key):
		print("[NpcAutonomyBoard] storing cleared: %s" % key)
	_storing_alarms.erase(key)
	# The fault is gone — its npc-ack is spent (mirrors HmiOverlay dropping
	# rows whose condition ended).
	_npc_acked.erase(alarm_id)

## True while the storing behind `key` is still active — FixStoringTask's
## completion condition.
func storing_active(key: String) -> bool:
	return _storing_alarms.has(key)

## Read-only snapshot of every active storing — for external HMI renderers
## (HmiWebOverlay's alarm strip). Returns [{key, machine_id, alarm_id,
## severity}]; order is the registry's insertion order.
func storing_list() -> Array:
	var out : Array = []
	for key in _storing_alarms:
		var e : Dictionary = _storing_alarms[key]
		out.append({
			"key": key,
			"machine_id": String(e.get("machine_id", "")),
			"alarm_id": String(e.get("alarm_id", "")),
			"severity": int(e.get("severity", 1)),
		})
	return out

## KwitterenStoringTask reached the HMI: record the ack. HmiOverlay ORs this
## into its own KWITTEREN state (bell amber-steady instead of red-flashing).
func mark_npc_acked(alarm_id: String) -> void:
	_npc_acked[alarm_id] = true

func npc_acked(alarm_id: String) -> bool:
	return _npc_acked.has(alarm_id)

## FixStoringTask completed: emit the acknowledge task for a DIFFERENT storing
## worker (operator rule — the fixer may not kwitteren their own fix).
func on_storing_fixed(key: String, fixer: Node) -> void:
	var entry : Dictionary = _storing_alarms.get(key, {})
	var aid : String = String(entry.get("alarm_id", key.get_slice("/", 1)))
	var panel : Node3D = _nearest_hmi_panel(fixer)
	var ppos : Vector3 = panel.global_position if panel != null \
		else ((fixer as Node3D).global_position if fixer is Node3D else Vector3.ZERO)
	var t := KwitterenStoringTask.new(key, aid, panel, ppos, fixer, self)
	_open_tasks[("kwit:" + key).hash()] = t

## The CrewManager (joined group "crew_manager") — machine positions + the
## relief hook route through it.
func crew_manager() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.get_first_node_in_group("crew_manager")

func _station_pos(machine_id: String) -> Vector3:
	var cm := crew_manager()
	if cm != null and cm.has_method("_machine_list"):
		for m in cm.call("_machine_list"):
			if String(m.get("id", "")) == machine_id:
				return m.get("pos", Vector3.ZERO)
	# Fallback: a placed_object whose placeable_id matches.
	var tree := get_tree()
	if tree != null:
		for po in tree.get_nodes_in_group("placed_object"):
			if po is Node3D and String(po.get_meta("placeable_id", "")) == machine_id:
				return (po as Node3D).global_position
	return Vector3.ZERO

func _nearest_hmi_panel(ref: Node) -> Node3D:
	var tree := get_tree()
	if tree == null:
		return null
	var from : Vector3 = (ref as Node3D).global_position if ref is Node3D else Vector3.ZERO
	var best : Node3D = null
	var best_d : float = INF
	for po in tree.get_nodes_in_group("placed_object"):
		if not (po is Node3D):
			continue
		var pid := String(po.get_meta("placeable_id", ""))
		# One rule since the generic `hmi_panel` / `hmi_wall` props were retired:
		# every HMI placeable id starts with `hmi_`.
		if not pid.begins_with("hmi_"):
			continue
		var d : float = ((po as Node3D).global_position - from).length()
		if d < best_d:
			best_d = d
			best = po as Node3D
	return best

## Generator 6 — one FixStoringTask per active storing. Keyed by the alarm key
## hash (storing targets are positions, not always live nodes, so the usual
## target-instance-id key does not apply).
func _scan_storing_alarms(seen: Dictionary) -> void:
	for key in _storing_alarms.keys():
		var e : Dictionary = _storing_alarms[key]
		var tid : int = ("storing:" + String(key)).hash()
		seen[tid] = true
		if _open_tasks.has(tid):
			continue
		var pos : Vector3 = e.get("pos", Vector3.ZERO)
		if pos == Vector3.ZERO:
			pos = _station_pos(String(e.get("machine_id", "")))
			e["pos"] = pos
		var t := FixStoringTask.new(String(key), String(e.get("machine_id", "")),
			String(e.get("alarm_id", "")), int(e.get("severity", 1)), pos, null, self)
		_open_tasks[tid] = t
	# Keep open kwitteren tasks alive across prunes (they are keyed off-node too).
	for tid2 in _open_tasks.keys():
		var t2 : NpcAutonomyTask = _open_tasks[tid2]
		if t2 != null and t2.task_name == "kwitteren_storing" and not t2.is_done():
			seen[tid2] = true

## INV-101 mirror — the operator's own example ("no bale at feeder belt").
## HmiOverlay derives this fault only while the overlay is OPEN; the board
## watches the live LineFlow continuously so a storing worker responds even
## with every UI closed. Raise/clear through the same registry as EventBus
## alarms so fix + kwitteren behave identically.
func _tick_feed_starvation_monitor(delta: float) -> void:
	var cm := crew_manager()
	if cm == null:
		return
	var lf : Node = cm.get("line_flow")
	if lf == null or not is_instance_valid(lf):
		return
	var enabled_val = lf.get("feed_enabled")
	var enabled : bool = bool(enabled_val) if enabled_val != null else false
	var fed_val = lf.get("fed_mass")
	var fed : float = float(fed_val) if (fed_val != null and (fed_val is float or fed_val is int)) else 0.0
	var key := "invoer/INV-101"
	if not enabled:
		_no_feed_t = 0.0
		_last_fed_mass = fed
		if _storing_alarms.has(key):
			_on_machine_alarm_cleared("invoer", "INV-101")
		return
	if fed > _last_fed_mass + 0.001:
		_no_feed_t = 0.0
		_last_fed_mass = fed
		if _storing_alarms.has(key):
			_on_machine_alarm_cleared("invoer", "INV-101")
		return
	_no_feed_t += delta
	if _no_feed_t >= NO_FEED_ALARM_S and not _storing_alarms.has(key):
		_on_machine_alarm_raised("invoer", "INV-101", 2)
