extends NpcAutonomyTask

class_name OverflowDumpTask

# =============================================================================
# #198 — Empty an overflowing WasteContainer. When a container crosses its
# safe-fill point (WasteContainer.needs_emptying()), an idle NPC walks over and
# empties it (WasteContainer.empty()), the same reset a forklift-tip or manual
# reset would produce. Keeps a full skip / fines bay / overflowing bin from
# staying BLOCKED and spilling onto the floor.
#
# Cycle (2 sub-phases), same shape as the other cleaning tasks:
#   WALK_TO_BIN   — walk into reach of the container.
#   DUMP          — call empty(); stamp + release.
# =============================================================================

enum Phase { WALK_TO_BIN, DUMP }

const PHASE_TIMEOUT_S : float = 120.0
const APPROACH_DIST_M : float = 2.2      # close enough to tip / reset the bin

var container   : Node3D = null
var _phase      : int    = Phase.WALK_TO_BIN
var _phase_t    : float  = 0.0
var _world_ref  : Node   = null

func _init(bin: Node3D, world_ref: Node) -> void:
	task_name = "overflow_dump"
	# Above routine cleaning circuits (an overflowing bin is a real spill/block
	# problem) but below the lump-cart haul.
	priority = 45
	target_node = bin
	container = bin
	_world_ref = world_ref
	accept_roles = PackedStringArray(["all_rounder", "permanent_feeder", "transitional", "extruder_op"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if container == null or not is_instance_valid(container):
		return false
	if container.has_meta("autonomy_claimed_by"):
		var claimer = container.get_meta("autonomy_claimed_by")
		if claimer != null and is_instance_valid(claimer) and claimer != npc:
			return false
	# Race-safe: skip if it was emptied between emit and accept.
	if container.has_method("needs_emptying"):
		return bool(container.call("needs_emptying"))
	return true

func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_BIN
	_phase_t = 0.0
	container.set_meta("autonomy_claimed_by", npc)

func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
		mark_failed("phase_timeout:%d" % _phase)
		release(npc)
		return true
	match _phase:
		Phase.WALK_TO_BIN: _tick_walk_to_bin(npc)
		Phase.DUMP:        _tick_dump(npc)
	return _done

func _tick_walk_to_bin(npc: Node) -> void:
	if container == null or not is_instance_valid(container):
		mark_failed("container_gone")
		release(npc)
		return
	if not _close_enough(npc, container.global_position, APPROACH_DIST_M):
		_set_dest(npc, container.global_position)
		return
	_phase = Phase.DUMP
	_phase_t = 0.0

func _tick_dump(npc: Node) -> void:
	if container != null and is_instance_valid(container) and container.has_method("empty"):
		container.call("empty")
		container.set_meta("last_cleaned_at", _now_sim_s())
	release(npc)
	mark_done()

func release(_npc: Node) -> void:
	if container != null and is_instance_valid(container):
		container.remove_meta("autonomy_claimed_by")

# ── Helpers ─────────────────────────────────────────────────────────────────

func _close_enough(npc: Node, target_pos: Vector3, r: float) -> bool:
	if npc == null or not (npc is Node3D):
		return false
	return (npc.global_position - target_pos).length() <= r

func _set_dest(npc: Node, pos: Vector3) -> void:
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)

func _now_sim_s() -> float:
	if _world_ref == null:
		return Time.get_ticks_msec() / 1000.0
	var sc = _world_ref.get("shift_clock")
	if sc != null and "shift_elapsed_seconds" in sc:
		return float(sc.shift_elapsed_seconds)
	return Time.get_ticks_msec() / 1000.0
