extends NpcAutonomyTask

class_name ShovelFloorPileTask

# =============================================================================
# #198 — Shovel down a FloorPile that has built up under a chute / beside an
# overflowing bin. Real flow (mirrors ShovelTool's manual UX, #154): the NPC
# walks to the heap, scoops it a shovelful at a time, tips each scoop into the
# nearest waste_container in reach, and keeps going until the pile is low.
#
# Cycle (3 sub-phases), same shape as BlowLeavesTask:
#   WALK_TO_PILE   — find the target floor pile, walk into scoop range.
#   SHOVEL         — on a fixed beat, lift SCOOP_KG off the pile and deposit it
#                    into the nearest waste_container (or discard if none is in
#                    reach). Loop until the pile drops below LOW_MASS_KG.
#   DONE           — pile cleared (or gone); stamp + release.
# =============================================================================

enum Phase { WALK_TO_PILE, SHOVEL }

const PHASE_TIMEOUT_S : float = 120.0    # any single leg shouldn't take longer
const APPROACH_DIST_M : float = 2.0      # close enough to shovel the heap
const DEPOSIT_RANGE_M : float = 3.0      # a bin this close catches the scoop
const SCOOP_KG        : float = 25.0     # mass lifted per scoop (matches ShovelTool)
const SCOOP_BEAT_S    : float = 0.6      # seconds between scoops (the shovel rhythm)
const LOW_MASS_KG     : float = 20.0     # stop once the pile is down to ~this
const LUMPS_DENSITY_KG_M3 : float = 200.0

var floor_pile  : Node3D = null
var _phase      : int    = Phase.WALK_TO_PILE
var _phase_t    : float  = 0.0
var _scoop_t    : float  = 0.0
var _world_ref  : Node   = null

func _init(pile: Node3D, world_ref: Node) -> void:
	task_name = "shovel_floor_pile"
	# Housekeeping duty — above idle cleaning circuits (a heap blocks lanes /
	# machine intakes) but below the safety-critical lump-cart haul.
	priority = 40
	target_node = pile
	floor_pile = pile
	_world_ref = world_ref
	accept_roles = PackedStringArray(["all_rounder", "permanent_feeder", "transitional", "extruder_op"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if floor_pile == null or not is_instance_valid(floor_pile):
		return false
	# Refuse if another NPC already claimed this pile.
	if floor_pile.has_meta("autonomy_claimed_by"):
		var claimer = floor_pile.get_meta("autonomy_claimed_by")
		if claimer != null and is_instance_valid(claimer) and claimer != npc:
			return false
	# Nothing to shovel — don't accept.
	if float(floor_pile.get("mass_kg")) <= LOW_MASS_KG:
		return false
	return true

func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_PILE
	_phase_t = 0.0
	_scoop_t = 0.0
	floor_pile.set_meta("autonomy_claimed_by", npc)

func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
		mark_failed("phase_timeout:%d" % _phase)
		release(npc)
		return true
	match _phase:
		Phase.WALK_TO_PILE: _tick_walk_to_pile(npc)
		Phase.SHOVEL:       _tick_shovel(npc, delta)
	return _done

func _tick_walk_to_pile(npc: Node) -> void:
	if floor_pile == null or not is_instance_valid(floor_pile):
		mark_failed("pile_gone")
		release(npc)
		return
	if not _close_enough(npc, floor_pile.global_position, APPROACH_DIST_M):
		_set_dest(npc, floor_pile.global_position)
		return
	_phase = Phase.SHOVEL
	_phase_t = 0.0
	_scoop_t = 0.0

func _tick_shovel(npc: Node, delta: float) -> void:
	if floor_pile == null or not is_instance_valid(floor_pile):
		mark_done()
		release(npc)
		return
	# Pile low enough — done.
	if float(floor_pile.get("mass_kg")) <= LOW_MASS_KG:
		floor_pile.set_meta("last_cleaned_at", _now_sim_s())
		release(npc)
		mark_done()
		return
	# Scoop on the beat: lift a shovelful off the pile, deposit into the nearest
	# waste_container in reach (or discard clear if none — same as ShovelTool).
	_scoop_t += delta
	if _scoop_t < SCOOP_BEAT_S:
		return
	_scoop_t = 0.0
	if not floor_pile.has_method("scoop"):
		mark_done()
		release(npc)
		return
	var got : float = float(floor_pile.call("scoop", SCOOP_KG))
	if got <= 0.0:
		release(npc)
		mark_done()
		return
	var bin := _nearest_waste_container(npc)
	if bin != null:
		if bin.has_method("receive_lumps"):
			bin.call("receive_lumps", got)
		elif bin.has_method("add"):
			bin.call("add", got, LUMPS_DENSITY_KG_M3, -1)

func release(_npc: Node) -> void:
	if floor_pile != null and is_instance_valid(floor_pile):
		floor_pile.remove_meta("autonomy_claimed_by")

# ── Helpers ─────────────────────────────────────────────────────────────────

func _nearest_waste_container(npc: Node) -> Node:
	var tree := npc.get_tree() if npc.has_method("get_tree") else null
	if tree == null:
		return null
	var origin : Vector3 = npc.global_position
	var best : Node = null
	var best_d : float = DEPOSIT_RANGE_M
	for c in tree.get_nodes_in_group("waste_container"):
		var cn := c as Node3D
		if cn == null or not is_instance_valid(cn):
			continue
		var d : float = cn.global_position.distance_to(origin)
		if d < best_d:
			best_d = d
			best = c
	return best

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
