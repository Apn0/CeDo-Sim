extends RefCounted

class_name NpcAutonomyTask

# =============================================================================
# #198 — Pluggable NPC task base class.
# =============================================================================
# Idle NPCs poll NpcAutonomyBoard.take_next_task(npc) every few seconds. The
# board scans world state, instantiates one concrete subclass per detected
# work item, sorts by priority, and hands the highest-priority compatible task
# to the asking NPC.
#
# Subclass contract:
#   • Set `task_name`, `priority`, `target_node`, `accept_roles` in _init().
#   • Override start(npc) — claim resources, set up sub-targets.
#   • Override tick(npc, delta) — return true when complete.
#   • Override release(npc) — release resources (drop tool, exit forklift).
#
# Roles match NPC_DATA[npc_id].role: shift_leader / asst_shift_leader /
# extruder_op / all_rounder / permanent_feeder / production_manager /
# transitional. Tasks declare which roles can do them (an empty array =
# anyone). The board never offers a task to an NPC whose role doesn't match.

# ── Task identity (subclass sets these) ─────────────────────────────────────
var task_name    : String = "task"
var priority     : int    = 0           # higher = more urgent
# npc-09 — emit-time snapshot of the subclass's own priority BEFORE the board
# adds the shift-phase / line-problem modifier. NpcAutonomyBoard sets it right
# after instantiation and its _rescan refreshes open unclaimed tasks in place
# as `base_priority + current modifier`, so the handover boost appears (and a
# line-problem penalty clears) on tasks emitted earlier in the shift.
var base_priority : int   = 0
var target_node  : Node3D = null        # where the NPC is heading
var accept_roles : PackedStringArray = PackedStringArray()   # empty = any role

# ── Task lifecycle state ────────────────────────────────────────────────────
var _claimed_by : Node = null   # the NPC who took this task
var _done       : bool = false
var _failed     : bool = false
var _fail_reason: String = ""
# npc-01 — wall-clock second of mark_failed(). The board holds a failed task
# in _open_tasks as a re-emit block for a short retry cooldown, so a
# persistently-failing target doesn't thrash a fresh task every scan.
var _failed_at  : float = 0.0

func can_start(_npc: Node) -> bool:
	# Subclass can refuse based on per-NPC checks (carrying something, in a
	# vehicle, etc.). Default: any NPC the board offers it to is eligible.
	return target_node != null and is_instance_valid(target_node) and not _done

func start(npc: Node) -> void:
	_claimed_by = npc

func tick(_npc: Node, _delta: float) -> bool:
	# Return true when the task is complete. Subclasses must override.
	return true

func release(_npc: Node) -> void:
	# Subclass: drop the tool, exit the vehicle, etc. Called both on normal
	# completion and on abandonment.
	pass

func is_done() -> bool:
	return _done

func is_failed() -> bool:
	return _failed

func mark_done() -> void:
	_done = true

func mark_failed(reason: String) -> void:
	_failed = true
	_fail_reason = reason
	_failed_at = Time.get_ticks_msec() / 1000.0
	_done = true   # failure is also a terminal state

# ── Shared tool-carry helpers (npc-03 / npc-11) ─────────────────────────────
# ONE hand-carry offset for every tool-carrying task so per-tool offsets can't
# diverge again. Operator 2026-07-16 (on the leaf blower): the old
# (0.35, 0.95, 0.4) put the tool ~1.85 m up — floating ABOVE the head — and
# +0.4 on Z = BEHIND him. NPC origin is the capsule centre, so hand height is
# ~y=0 and forward is -Z: right side, hand height, nozzle forward.
const TOOL_CARRY_OFFSET : Vector3 = Vector3(0.25, -0.05, -0.30)

## Put a carried tool DOWN: re-parent it from the NPC's hand back into the
## world and restore its saved station transform ("saved_world_xform" meta,
## stamped at pickup); fall back to the NPC's current position when the meta
## is missing — a real worker puts the tool down where he's called away.
## Called from both the happy-path return leg and release(), so ANY abort —
## phase timeout, shift bell, production preemption, operator clear — drops
## the tool instead of leaving it welded to the hand, where a later task
## could "re-pick-it-up" out of another worker's grip.
func _drop_tool(npc: Node, tool_node: Node3D) -> void:
	if tool_node == null or not is_instance_valid(tool_node):
		return
	if npc == null or not is_instance_valid(npc):
		return
	if tool_node.get_parent() != npc:
		return   # not in this NPC's hand — nothing to put down
	var world : Node = npc.get_parent()
	if world == null:
		return   # NPC mid-despawn; the tool is freed with it
	npc.remove_child(tool_node)
	world.add_child(tool_node)
	if tool_node.has_meta("saved_world_xform"):
		tool_node.global_transform = tool_node.get_meta("saved_world_xform")
	elif npc is Node3D:
		tool_node.global_transform = Transform3D(Basis.IDENTITY, (npc as Node3D).global_position)
