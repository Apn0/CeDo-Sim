extends NpcAutonomyTask

class_name BlowLeavesTask

# =============================================================================
# #198 — Pick up a leaf blower, walk a cleaning circuit around the plant
# interior (wash-line floor, sorting belt aisle, extruder bay), return the
# blower to where it was found. Visible "NPC is autonomously cleaning the
# shop floor" behaviour the operator asked for.
#
# Cycle (4 sub-phases):
#   WALK_TO_BLOWER     — find the nearest unclaimed leaf blower, walk to it,
#                         pick it up (re-parent under NPC).
#   CIRCUIT_n          — walk a fixed circuit of CIRCUIT_POINTS waypoints
#                         relative to the plant anchor. At each waypoint the
#                         NPC stands for DWELL_S seconds (running the blower
#                         visual / audio if hooked up later).
#   RETURN_BLOWER      — walk back to the pickup spot, drop the blower,
#                         disembark.
# =============================================================================

enum Phase { WALK_TO_BLOWER, CIRCUIT, RETURN_BLOWER }

const PHASE_TIMEOUT_S : float = 120.0   # any single leg shouldn't take longer
const APPROACH_DIST_M : float = 1.4     # close enough to grab the blower
const WAYPOINT_DIST_M : float = 1.8     # "arrived" tolerance at each circuit point
const DWELL_S         : float = 6.0     # seconds standing at each waypoint blowing
# Circuit waypoints in PLANT-LOCAL (X, Z) frame — rotated into world by _bo()
# when used. #198 (operator clarification): leaf blower is INEFFECTIVE in the
# wash-line area because water makes the film foil HEAVY and STICKY — blowing
# just smears it. Circuit stays on the DRY side: bale-yard intake, sorting
# aisle, extruder bay, silo apron. Wet equipment (prewash drum, friction L/R,
# scheidingsgoot, dewater bay, flotation tank) is the water hose's job.
const CIRCUIT_POINTS : Array = [
	Vector3(-2.0,  0.0,  18.0),    # opzetband foot (bale-yard intake side)
	Vector3(-6.0,  0.0,   4.0),    # sorting belt aisle
	Vector3(-12.0, 0.0,  -4.0),    # extruder bay 1
	Vector3(-12.0, 0.0, -14.0),    # extruder bay 2
	Vector3( -2.0, 0.0, -20.0),    # silo apron
]

var leaf_blower : Node3D = null
var _phase      : int    = Phase.WALK_TO_BLOWER
var _phase_t    : float  = 0.0
var _circuit_idx: int    = 0
var _dwell_t    : float  = 0.0
var _pickup_pos : Vector3 = Vector3.ZERO
var _world_ref  : Node = null

func _init(blower: Node3D, world_ref: Node) -> void:
	task_name = "blow_leaves"
	# Lower priority than safety-critical lump cart emptying but a clear visible
	# duty so any idle all-rounder / feeder / transitional NPC can pick it up.
	priority = 30
	target_node = blower
	leaf_blower = blower
	_world_ref = world_ref
	accept_roles = PackedStringArray(["all_rounder", "permanent_feeder", "transitional", "extruder_op"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if leaf_blower == null or not is_instance_valid(leaf_blower):
		return false
	# Refuse if another NPC already grabbed this blower (covered by board
	# claim, but double-check here too).
	if leaf_blower.has_meta("autonomy_claimed_by"):
		var claimer = leaf_blower.get_meta("autonomy_claimed_by")
		if claimer != null and is_instance_valid(claimer) and claimer != npc:
			return false
	return true

func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_BLOWER
	_phase_t = 0.0
	_circuit_idx = 0
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
		Phase.CIRCUIT:        _tick_circuit(npc, delta)
		Phase.RETURN_BLOWER:  _tick_return_blower(npc)
	return _done

func _tick_walk_to_blower(npc: Node) -> void:
	if leaf_blower == null or not is_instance_valid(leaf_blower):
		mark_failed("blower_gone")
		release(npc)
		return
	if not _close_enough(npc, leaf_blower.global_position, APPROACH_DIST_M):
		_set_dest(npc, leaf_blower.global_position)
		return
	# Pick up: parent the blower under the NPC so it moves with them.
	# Keep a small forward+up offset so it visually reads as "in hand".
	if leaf_blower.get_parent() != npc:
		var saved_xform : Transform3D = leaf_blower.global_transform
		leaf_blower.get_parent().remove_child(leaf_blower)
		npc.add_child(leaf_blower)
		# npc-11 — shared operator-corrected hand offset (2026-07-16 feedback);
		# calibration note lives at NpcAutonomyTask.TOOL_CARRY_OFFSET.
		leaf_blower.transform = Transform3D(Basis.IDENTITY, TOOL_CARRY_OFFSET)
		leaf_blower.set_meta("saved_world_xform", saved_xform)
	_phase = Phase.CIRCUIT
	_phase_t = 0.0
	_circuit_idx = 0
	_dwell_t = 0.0

func _tick_circuit(npc: Node, delta: float) -> void:
	if _circuit_idx >= CIRCUIT_POINTS.size():
		_phase = Phase.RETURN_BLOWER
		_phase_t = 0.0
		return
	var wp_world : Vector3 = _waypoint_world(_circuit_idx)
	if not _close_enough(npc, wp_world, WAYPOINT_DIST_M):
		_set_dest(npc, wp_world)
		return
	# Arrived — dwell for DWELL_S seconds (the "blowing" beat), then advance.
	# Real effect: the blast pushes nearby loose film scrap away from the NPC so
	# the world visibly changes when a colleague cleans (not just a cosmetic walk).
	_blow_nearby_scrap(npc)
	_dwell_t += delta
	if _dwell_t >= DWELL_S:
		_dwell_t = 0.0
		_circuit_idx += 1

# Push any RigidBody3D in group "film_scrap" within BLOW_RADIUS_M away from the
# NPC, low and outward, as if the leaf blower's air cone hit it. Cheap per-frame
# radial impulse — the scraps are light (mass 0.05) so a small nudge scatters them.
const BLOW_RADIUS_M   : float = 3.5
const BLOW_IMPULSE    : float = 0.12
func _blow_nearby_scrap(npc: Node) -> void:
	if npc == null or not (npc is Node3D):
		return
	var tree := npc.get_tree() if npc.has_method("get_tree") else null
	if tree == null:
		return
	var origin : Vector3 = npc.global_position
	for s in tree.get_nodes_in_group("film_scrap"):
		if not (s is RigidBody3D) or not is_instance_valid(s):
			continue
		var to : Vector3 = s.global_position - origin
		var d : float = to.length()
		if d > BLOW_RADIUS_M or d < 0.001:
			continue
		var dir : Vector3 = to / d
		dir.y = maxf(dir.y, 0.25)   # bias slightly upward so scrap skips, not drags
		# Falloff with distance so close scrap gets the strongest push.
		var falloff : float = 1.0 - (d / BLOW_RADIUS_M)
		s.apply_central_impulse(dir.normalized() * BLOW_IMPULSE * falloff)

func _tick_return_blower(npc: Node) -> void:
	if not _close_enough(npc, _pickup_pos, APPROACH_DIST_M):
		_set_dest(npc, _pickup_pos)
		return
	# Drop the blower back at its saved station transform (shared npc-03 helper).
	_drop_tool(npc, leaf_blower)
	if leaf_blower != null and is_instance_valid(leaf_blower):
		# Stamp the cleaning time so the board doesn't immediately re-emit.
		leaf_blower.set_meta("last_cleaned_at", _now_sim_s())
	release(npc)
	mark_done()

func release(npc: Node) -> void:
	# npc-03 — an abort (phase timeout, shift bell, production preemption,
	# operator clear) must put the blower DOWN. Without this the tool stayed
	# welded to the NPC's hand forever and — with the claim meta removed
	# below — a later task could "pick it up" out of his hands.
	_drop_tool(npc, leaf_blower)
	if leaf_blower != null and is_instance_valid(leaf_blower):
		leaf_blower.remove_meta("autonomy_claimed_by")

# ── Helpers ─────────────────────────────────────────────────────────────────

func _waypoint_world(i: int) -> Vector3:
	# Rotate a plant-local offset into world coords using MainWorld's canonical
	# _bo() helper so the circuit follows the building's actual yaw.
	if _world_ref == null:
		return CIRCUIT_POINTS[i]
	var psp : Vector3 = _world_ref.get("_player_spawn_pos")
	var ga := Vector3(psp.x, psp.y, psp.z)
	return _world_ref.call("_bo", ga, CIRCUIT_POINTS[i])

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
