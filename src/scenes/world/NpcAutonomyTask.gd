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
var target_node  : Node3D = null        # where the NPC is heading
var accept_roles : PackedStringArray = PackedStringArray()   # empty = any role

# ── Task lifecycle state ────────────────────────────────────────────────────
var _claimed_by : Node = null   # the NPC who took this task
var _done       : bool = false
var _failed     : bool = false
var _fail_reason: String = ""

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
	_done = true   # failure is also a terminal state
