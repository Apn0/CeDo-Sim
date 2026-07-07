extends NpcAutonomyTask

class_name HoseSweepTask

# =============================================================================
# #198 — Pick up a HoseNozzle (water OR compressed-air, distinguished by the
# nozzle's `air_mode` export) and run a cleaning sweep around the relevant
# part of the plant. Water hose spends more time per stop (real spray-down
# of the wash-line floor); air hose moves faster and visits more spots
# because it's lower-power but more precise (the operator's "slightly less
# powerful leaf blower").
#
# Same 3-phase shape as BlowLeavesTask:
#   WALK_TO_NOZZLE    — find the nozzle, walk, pick it up (re-parent under NPC)
#   CIRCUIT           — visit each waypoint, dwell DWELL_S, advance
#   RETURN_NOZZLE     — back to pickup spot, drop, stamp cooldown
#
# Picking the nozzle up by re-parenting works for both modes because
# HoseNozzle's chain visual lives at the world root (not under the nozzle),
# so the chain follows the new carrier transparently.
# =============================================================================

enum Phase { WALK_TO_NOZZLE, CIRCUIT, RETURN_NOZZLE }

const PHASE_TIMEOUT_S : float = 120.0
const APPROACH_DIST_M : float = 1.4
const WAYPOINT_DIST_M : float = 1.8

# Per-mode tuning. Water = slow + thorough, air = quick + many stops.
const WATER_DWELL_S   : float = 9.0     # full hose-down per spot
const AIR_DWELL_S     : float = 3.5     # quick blast-down per spot
const WATER_COOLDOWN_HINT_S : float = 90.0 * 60.0   # consumed by the board
const AIR_COOLDOWN_HINT_S   : float = 40.0 * 60.0

# Water cleaning route — the wet half of the wash-line floor: prewash drum,
# scheidingsgoot/glijgoot run, friction L/R, dewater_screw bay.
const WATER_CIRCUIT_POINTS : Array = [
	Vector3( 4.0, 0.0,  12.0),    # prewash drum apron
	Vector3( 8.0, 0.0,   4.0),    # scheidingsgoot
	Vector3(10.0, 0.0,  -8.0),    # friction L apron
	Vector3(14.0, 0.0,  -8.0),    # friction R apron
	Vector3( 6.0, 0.0, -16.0),    # dewater bay
]
# Air cleaning route — the dry half: extruder bay, sorting belts, intake
# transfer decks. Air hose can't be used near the wet equipment safely.
const AIR_CIRCUIT_POINTS : Array = [
	Vector3(-2.0, 0.0,  18.0),    # opzetband foot
	Vector3(-6.0, 0.0,   4.0),    # sorting belt aisle
	Vector3(-12.0, 0.0, -4.0),    # extruder bay 1
	Vector3(-12.0, 0.0, -14.0),   # extruder bay 2
	Vector3(-8.0, 0.0, -20.0),    # silo apron
	Vector3( 0.0, 0.0, -10.0),    # central aisle
]

var nozzle : Node3D = null
var _is_air : bool = false
var _circuit : Array = []
var _dwell_s : float = WATER_DWELL_S
var _phase   : int = Phase.WALK_TO_NOZZLE
var _phase_t : float = 0.0
var _circuit_idx : int = 0
var _dwell_t : float = 0.0
var _pickup_pos : Vector3 = Vector3.ZERO
var _world_ref : Node = null

func _init(nz: Node3D, world_ref: Node) -> void:
	nozzle = nz
	_world_ref = world_ref
	_is_air = bool(nz.get("air_mode")) if "air_mode" in nz else false
	if _is_air:
		task_name = "air_hose_sweep"
		priority = 28              # just under leaf blower
		_circuit = AIR_CIRCUIT_POINTS
		_dwell_s = AIR_DWELL_S
	else:
		task_name = "water_hose_sweep"
		priority = 32              # just above leaf blower (water is higher-touch)
		_circuit = WATER_CIRCUIT_POINTS
		_dwell_s = WATER_DWELL_S
	target_node = nz
	accept_roles = PackedStringArray(["all_rounder", "permanent_feeder", "transitional", "extruder_op"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if nozzle == null or not is_instance_valid(nozzle):
		return false
	if nozzle.has_meta("autonomy_claimed_by"):
		var claimer = nozzle.get_meta("autonomy_claimed_by")
		if claimer != null and is_instance_valid(claimer) and claimer != npc:
			return false
	return true

func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_NOZZLE
	_phase_t = 0.0
	_circuit_idx = 0
	_dwell_t = 0.0
	_pickup_pos = nozzle.global_position
	nozzle.set_meta("autonomy_claimed_by", npc)

func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
		mark_failed("phase_timeout:%d" % _phase)
		release(npc)
		return true
	match _phase:
		Phase.WALK_TO_NOZZLE: _tick_walk_to_nozzle(npc)
		Phase.CIRCUIT:        _tick_circuit(npc, delta)
		Phase.RETURN_NOZZLE:  _tick_return_nozzle(npc)
	return _done

func _tick_walk_to_nozzle(npc: Node) -> void:
	if nozzle == null or not is_instance_valid(nozzle):
		mark_failed("nozzle_gone")
		release(npc)
		return
	if not _close_enough(npc, nozzle.global_position, APPROACH_DIST_M):
		_set_dest(npc, nozzle.global_position)
		return
	# Pick up — re-parent under NPC, same hand offset as the leaf blower so
	# the rig reads consistently across tools.
	if nozzle.get_parent() != npc:
		var saved_xform : Transform3D = nozzle.global_transform
		nozzle.get_parent().remove_child(nozzle)
		npc.add_child(nozzle)
		nozzle.transform = Transform3D(Basis.IDENTITY, Vector3(0.35, 0.95, 0.4))
		nozzle.set_meta("saved_world_xform", saved_xform)
	_phase = Phase.CIRCUIT
	_phase_t = 0.0
	_circuit_idx = 0
	_dwell_t = 0.0

func _tick_circuit(npc: Node, delta: float) -> void:
	if _circuit_idx >= _circuit.size():
		_phase = Phase.RETURN_NOZZLE
		_phase_t = 0.0
		return
	var wp_world : Vector3 = _waypoint_world(_circuit_idx)
	if not _close_enough(npc, wp_world, WAYPOINT_DIST_M):
		_set_dest(npc, wp_world)
		return
	# Real effect during the dwell: the hose washes down / blasts loose dirt, so
	# nearby FloorPiles shrink while the colleague is spraying. Water reduces more
	# per beat than the lower-power air hose.
	_wash_nearby(npc, delta)
	_dwell_t += delta
	if _dwell_t >= _dwell_s:
		_dwell_t = 0.0
		_circuit_idx += 1

# Shrink any FloorPile within WASH_RADIUS_M of the NPC while the hose is running.
# Water hose washes more mass per second than the air hose. Uses FloorPile.scoop
# (the same "remove N kg" API the shovel uses) so the pile's cone + collider
# shrink and the change is visible.
const WASH_RADIUS_M       : float = 3.0
const WATER_WASH_KG_PER_S : float = 8.0
const AIR_WASH_KG_PER_S   : float = 3.0
func _wash_nearby(npc: Node, delta: float) -> void:
	if npc == null or not (npc is Node3D):
		return
	var tree := npc.get_tree() if npc.has_method("get_tree") else null
	if tree == null:
		return
	var rate : float = AIR_WASH_KG_PER_S if _is_air else WATER_WASH_KG_PER_S
	var remove_kg : float = rate * delta
	if remove_kg <= 0.0:
		return
	var origin : Vector3 = npc.global_position
	for p in tree.get_nodes_in_group("floor_pile"):
		var pn := p as Node3D
		if pn == null or not is_instance_valid(pn):
			continue
		if pn.global_position.distance_to(origin) > WASH_RADIUS_M:
			continue
		if pn.has_method("scoop"):
			pn.call("scoop", remove_kg)

func _tick_return_nozzle(npc: Node) -> void:
	if not _close_enough(npc, _pickup_pos, APPROACH_DIST_M):
		_set_dest(npc, _pickup_pos)
		return
	if nozzle != null and is_instance_valid(nozzle):
		if nozzle.get_parent() == npc:
			npc.remove_child(nozzle)
			var mw : Node = npc.get_parent()
			if mw != null:
				mw.add_child(nozzle)
				var saved : Transform3D = nozzle.get_meta("saved_world_xform",
					Transform3D(Basis.IDENTITY, _pickup_pos))
				nozzle.global_transform = saved
		nozzle.set_meta("last_cleaned_at", _now_sim_s())
	release(npc)
	mark_done()

func release(_npc: Node) -> void:
	if nozzle != null and is_instance_valid(nozzle):
		nozzle.remove_meta("autonomy_claimed_by")

# ── Helpers ─────────────────────────────────────────────────────────────────

func _waypoint_world(i: int) -> Vector3:
	if _world_ref == null:
		return _circuit[i]
	var psp : Vector3 = _world_ref.get("_player_spawn_pos")
	var ga := Vector3(psp.x, psp.y, psp.z)
	return _world_ref.call("_bo", ga, _circuit[i])

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
