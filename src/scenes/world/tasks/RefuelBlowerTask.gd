extends NpcAutonomyTask

class_name RefuelBlowerTask

# =============================================================================
# Carry a low-fuel LEAF BLOWER over to a JERRY CAN, top it off, and carry it
# back to where it was found. Housekeeping-adjacent duty: a blower that's run
# low is useless for the shop-floor cleaning circuit, so an idle colleague
# fetches it, walks it to the fuel can, refuels it, and returns it.
#
# Modelled closely on BlowLeavesTask — same base class, same _set_dest /
# _close_enough helper style, same pickup/re-parent-under-NPC pattern.
#
# Cycle (4 sub-phases):
#   WALK_TO_BLOWER — walk to the low-fuel leaf blower, pick it up (re-parent
#                    under the NPC so it moves with them).
#   CARRY_TO_CAN   — walk to the jerry can carrying the blower.
#   REFUEL         — stand at the can for REFUEL_DWELL_S seconds, then top the
#                    blower's tank to full.
#   RETURN         — walk back to the pickup spot, drop the blower, disembark.
# =============================================================================

# Blowers below this fuel fraction are considered "low" — the board's
# _scan_low_fuel_blowers generator references this to decide when to emit an
# auto RefuelBlowerTask.
const FUEL_LOW_FRACTION := 0.5

enum Phase { WALK_TO_BLOWER, CARRY_TO_CAN, REFUEL, RETURN }

const PHASE_TIMEOUT_S : float = 120.0   # any single leg shouldn't take longer
const APPROACH_DIST_M : float = 1.4     # close enough to grab / drop the blower
const CAN_DIST_M      : float = 1.6     # close enough to the jerry can to fill
const REFUEL_DWELL_S  : float = 2.0     # seconds standing at the can pouring fuel

var leaf_blower : Node3D = null
var jerry_can   : Node3D = null
var _phase      : int    = Phase.WALK_TO_BLOWER
var _phase_t    : float  = 0.0
var _dwell_t    : float  = 0.0
var _pickup_pos : Vector3 = Vector3.ZERO
var _world_ref  : Node = null

func _init(blower: Node3D, can: Node3D, world_ref: Node) -> void:
	task_name = "refuel_blower"
	# Just above the housekeeping circuit (blow_leaves = 30): a low tank blocks
	# cleaning, so refuelling should be picked before starting a fresh circuit.
	priority = 45
	target_node = blower
	leaf_blower = blower
	jerry_can = can
	_world_ref = world_ref
	accept_roles = PackedStringArray([
		"all_rounder", "permanent_feeder", "transitional",
		"extruder_op", "asst_shift_leader"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if leaf_blower == null or not is_instance_valid(leaf_blower):
		return false
	if jerry_can == null or not is_instance_valid(jerry_can):
		return false
	# Refuse if another NPC already grabbed this blower (covered by board claim,
	# but double-check here too).
	if leaf_blower.has_meta("autonomy_claimed_by"):
		var claimer = leaf_blower.get_meta("autonomy_claimed_by")
		if claimer != null and is_instance_valid(claimer) and claimer != npc:
			return false
	return true

func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_BLOWER
	_phase_t = 0.0
	_dwell_t = 0.0
	_pickup_pos = leaf_blower.global_position
	leaf_blower.set_meta("autonomy_claimed_by", npc)

func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
		mark_failed("phase_timeout:%d" % _phase)
		release(npc)
		return true
	match _phase:
		Phase.WALK_TO_BLOWER: _tick_walk_to_blower(npc)
		Phase.CARRY_TO_CAN:   _tick_carry_to_can(npc)
		Phase.REFUEL:         _tick_refuel(npc, delta)
		Phase.RETURN:         _tick_return(npc)
	return _done

func _tick_walk_to_blower(npc: Node) -> void:
	if leaf_blower == null or not is_instance_valid(leaf_blower):
		mark_failed("blower_gone")
		release(npc)
		return
	if not _close_enough(npc, leaf_blower.global_position, APPROACH_DIST_M):
		_set_dest(npc, leaf_blower.global_position)
		return
	# Pick up: parent the blower under the NPC so it moves with them, seated at
	# the shared hand offset (npc-11: the old local (0.35, 0.95, 0.4) was the
	# operator-rejected float-above-the-head pose that BlowLeavesTask already
	# dropped on 2026-07-16; see NpcAutonomyTask.TOOL_CARRY_OFFSET).
	if leaf_blower.get_parent() != npc:
		var saved_xform : Transform3D = leaf_blower.global_transform
		leaf_blower.get_parent().remove_child(leaf_blower)
		npc.add_child(leaf_blower)
		leaf_blower.transform = Transform3D(Basis.IDENTITY, TOOL_CARRY_OFFSET)
		leaf_blower.set_meta("saved_world_xform", saved_xform)
	_phase = Phase.CARRY_TO_CAN
	_phase_t = 0.0

func _tick_carry_to_can(npc: Node) -> void:
	if jerry_can == null or not is_instance_valid(jerry_can):
		mark_failed("can_gone")
		release(npc)
		return
	if not _close_enough(npc, jerry_can.global_position, CAN_DIST_M):
		_set_dest(npc, jerry_can.global_position)
		return
	_phase = Phase.REFUEL
	_phase_t = 0.0
	_dwell_t = 0.0

func _tick_refuel(npc: Node, delta: float) -> void:
	# Dwell at the can (the "pouring fuel" beat), then top the tank to full.
	_dwell_t += delta
	if _dwell_t < REFUEL_DWELL_S:
		return
	if leaf_blower != null and is_instance_valid(leaf_blower):
		# Prefer the tool's own refuel() API (also recolours its fuel LED); fall
		# back to setting the fuel field directly if the method isn't present.
		if leaf_blower.has_method("refuel"):
			leaf_blower.call("refuel")
		elif "fuel_l" in leaf_blower:
			var cap = leaf_blower.get("fuel_capacity_l") if "fuel_capacity_l" in leaf_blower else null
			if cap != null:
				leaf_blower.set("fuel_l", cap)
	_dwell_t = 0.0
	_phase = Phase.RETURN
	_phase_t = 0.0

func _tick_return(npc: Node) -> void:
	if not _close_enough(npc, _pickup_pos, APPROACH_DIST_M):
		_set_dest(npc, _pickup_pos)
		return
	# Drop the blower back at its saved station transform (shared npc-03 helper).
	_drop_tool(npc, leaf_blower)
	if leaf_blower != null and is_instance_valid(leaf_blower):
		# Stamp the refuel time so the board doesn't immediately re-emit.
		leaf_blower.set_meta("last_refuelled_at", _now_sim_s())
	release(npc)
	mark_done()

func release(npc: Node) -> void:
	# npc-03 — any abort must put the blower DOWN (same weld-to-hand failure as
	# the blow-circuit task; see BlowLeavesTask.release).
	_drop_tool(npc, leaf_blower)
	if leaf_blower != null and is_instance_valid(leaf_blower):
		leaf_blower.remove_meta("autonomy_claimed_by")

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
