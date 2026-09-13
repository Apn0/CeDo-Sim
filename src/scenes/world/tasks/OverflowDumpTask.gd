extends NpcAutonomyTask

class_name OverflowDumpTask

enum Phase { WALK_TO_FORKLIFT, DRIVE_TO_INDOOR, SCOOP_BULK, DRIVE_TO_OUTDOOR, DUMP }

const PHASE_TIMEOUT_S    : float = 90.0
const APPROACH_DIST_M    : float = 1.6
const APPROACH_DIST_VEH  : float = 3.5

# npc-05 — the phase budget is a FLOOR plus travel time, not a flat 90 s.
# WorldLayout parks the forklifts ~205 m from the plant, and an NPC walks at
# 1.5 m/s: the approach leg alone needs ~137 s, so every dump run in the shipped
# layout died on "phase_timeout:0", was re-emitted 30 s later by
# FAIL_RETRY_COOLDOWN_S, and thrashed for the whole shift. A flat budget makes
# any leg longer than ~135 m structurally impossible, which is a property of the
# constant rather than of the plant. Budget = leg length at a pessimistic
# 1.0 m/s (slower than the 1.5 m/s walk and far slower than the drive) plus the
# 90 s floor for the stationary phases, capped so a genuinely wedged actor still
# dies instead of holding the task forever.
const PHASE_TRAVEL_SPEED_MIN : float = 1.0     # m/s — pessimistic, covers walking
const PHASE_TIMEOUT_MAX_S    : float = 600.0

var _phase_budget : float = PHASE_TIMEOUT_S

var indoor_container  : Node3D = null
var outdoor_container : Node3D = null
var _phase     : int    = Phase.WALK_TO_FORKLIFT
var _phase_t   : float  = 0.0
var _forklift  : Node3D = null
# npc-05 — the task's OWN carry ledger. The vehicle's load_bulk/unload_bulk is
# now real (BaseVehicle) and is still driven so the chassis knows what it holds,
# but the authoritative kg lives here: when the has_method() probes missed (they
# always did, in every real session), the scooped mass was assigned to a local
# and vanished. Mass now cannot leave the bin without being accounted for.
var _carried_kg      : float = 0.0
var _carried_density : float = 0.0
# True between a CONFIRMED board and the matching disembark, so release() can
# put an abandoned worker back on his feet instead of leaving him welded into a
# seat with the vehicle's occupied flag stuck on.
var _boarded : bool = false
# Mass the destination could not take (skip blocked AND no floor pile) and that
# was handed back to the source bin. Non-zero means the dump did not fully land.
var _refused_kg : float = 0.0

func _init(indoor: Node3D, outdoor: Node3D) -> void:
	task_name = "overflow_dump"
	priority = 50
	target_node = indoor
	indoor_container = indoor
	outdoor_container = outdoor
	accept_roles = PackedStringArray(["all_rounder", "permanent_feeder", "transitional", "asst_shift_leader", "extruder_op"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if indoor_container == null or not is_instance_valid(indoor_container):
		return false
	if outdoor_container == null or not is_instance_valid(outdoor_container):
		return false
	# npc-04 — the destination must be able to RECEIVE material. A node with
	# neither add() nor receive_lumps() (e.g. the world root the forced path
	# used to pass) would silently vaporise the scooped mass in _tick_dump.
	if not (outdoor_container.has_method("add") or outdoor_container.has_method("receive_lumps")):
		return false
	if indoor_container.has_method("is_full"):
		if not bool(indoor_container.call("is_full")):
			return false
	return true

func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_FORKLIFT
	_phase_t = 0.0
	_forklift = _find_nearest_idle_forklift(npc)
	if _forklift == null:
		mark_failed("no_forklift_available")
		return
	_phase_budget = _travel_budget(npc, _forklift)

## npc-05 — advance to `next_phase` and size its budget from the ground the
## actor has to cover to finish it. Pass null endpoints for the stationary
## phases (scoop / dump), which get the flat floor.
func _enter_phase(next_phase: int, from_node: Node, to_node: Node) -> void:
	_phase = next_phase
	_phase_t = 0.0
	_phase_budget = _travel_budget(from_node, to_node)

func _travel_budget(from_node: Node, to_node: Node) -> float:
	var d : float = 0.0
	if from_node is Node3D and to_node is Node3D \
			and is_instance_valid(from_node) and is_instance_valid(to_node):
		d = (from_node as Node3D).global_position.distance_to((to_node as Node3D).global_position)
	return minf(PHASE_TIMEOUT_MAX_S, PHASE_TIMEOUT_S + d / PHASE_TRAVEL_SPEED_MIN)

func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > _phase_budget:
		mark_failed("phase_timeout:%d" % _phase)
		return true
	match _phase:
		Phase.WALK_TO_FORKLIFT:  _tick_walk_to_forklift(npc)
		Phase.DRIVE_TO_INDOOR:   _tick_drive_to_indoor(npc)
		Phase.SCOOP_BULK:        _tick_scoop_bulk(npc)
		Phase.DRIVE_TO_OUTDOOR:  _tick_drive_to_outdoor(npc)
		Phase.DUMP:              _tick_dump(npc)
	return _done

func _tick_walk_to_forklift(npc: Node) -> void:
	if _forklift == null or not is_instance_valid(_forklift):
		mark_failed("forklift_gone")
		return
	if not _close_enough(npc, _forklift, APPROACH_DIST_M):
		_set_destination(npc, _forklift.global_position)
		return
	# npc-05 — the board result is now HONOURED. It used to advance the phase
	# unconditionally: a refused board (no OperatorContext, can_enter() false,
	# vehicle taken between the scan and the arrival) degraded into a ghost drive
	# where every arrival test was measured against a forklift nobody was in.
	# A void return (test doubles, vehicles predating the bool) counts as success
	# so this stays backwards-compatible; only an explicit false fails the task.
	if npc.has_method("board_vehicle"):
		var seated = npc.call("board_vehicle", _forklift)
		if typeof(seated) == TYPE_BOOL and not bool(seated):
			mark_failed("board_refused")
			return
		_boarded = true
	_enter_phase(Phase.DRIVE_TO_INDOOR, _forklift, indoor_container)

func _tick_drive_to_indoor(npc: Node) -> void:
	if indoor_container == null or not is_instance_valid(indoor_container):
		mark_failed("indoor_gone")
		return
	if _forklift == null or not is_instance_valid(_forklift):
		mark_failed("forklift_gone")
		return
	# npc-05 — route to a reachable stand-off pose outside the container body
	# via ApproachPose, so the forklift chassis does not wedge on the hull.
	var approach_pos : Vector3 = ApproachPose.for_target(indoor_container, _forklift)
	if not ApproachPose.arrived_at(_forklift, approach_pos, APPROACH_DIST_VEH):
		_set_destination(npc, approach_pos)
		return
	_enter_phase(Phase.SCOOP_BULK, null, null)

func _tick_scoop_bulk(_npc: Node) -> void:
	# npc-05 — read the source's OWN blended density BEFORE emptying it (empty()
	# resets blended_density to its 200 default). The dump used to hand the
	# destination a hardcoded 200 kg/m3, so even with the mass conserved the
	# m3 / fill_fraction ledger drifted whenever the source was not 200.
	var density : float = 0.0
	if "blended_density" in indoor_container:
		density = float(indoor_container.get("blended_density"))
	var amt : float = 0.0
	if indoor_container.has_method("empty"):
		amt = float(indoor_container.call("empty"))
	elif "lumps_count" in indoor_container:
		amt = float(indoor_container.get("lumps_count"))
		if indoor_container.has_method("clear_lumps"):
			indoor_container.call("clear_lumps")
	# The task owns the ledger; the vehicle mirrors it when it can carry.
	_carried_kg += amt
	if density > 0.0:
		_carried_density = density
	if _forklift != null and is_instance_valid(_forklift) and _forklift.has_method("load_bulk"):
		_forklift.call("load_bulk", amt, _carried_density)
	_enter_phase(Phase.DRIVE_TO_OUTDOOR, _forklift, outdoor_container)

func _tick_drive_to_outdoor(npc: Node) -> void:
	if outdoor_container == null or not is_instance_valid(outdoor_container):
		mark_failed("outdoor_gone")
		return
	if _forklift == null or not is_instance_valid(_forklift):
		mark_failed("forklift_gone")
		return
	# npc-05 — stand-off pose outside the outdoor skip
	var approach_pos : Vector3 = ApproachPose.for_target(outdoor_container, _forklift)
	if not ApproachPose.arrived_at(_forklift, approach_pos, APPROACH_DIST_VEH):
		_set_destination(npc, approach_pos)
		return
	_enter_phase(Phase.DUMP, null, null)

func _tick_dump(npc: Node) -> void:
	# npc-05 — tip the TASK's ledger, not whatever the vehicle happens to report.
	# Keep the vehicle in sync so its carry flag clears, but never let its answer
	# override ours: a vehicle without the bulk API used to return 0.0 here and
	# the whole scooped load evaporated.
	if _forklift != null and is_instance_valid(_forklift) and _forklift.has_method("unload_bulk"):
		_forklift.call("unload_bulk")
	var amt : float = _carried_kg
	_carried_kg = 0.0
	var density : float = _carried_density if _carried_density > 0.0 else 200.0
	var refused : float = 0.0
	if outdoor_container.has_method("add"):
		refused = float(outdoor_container.call("add", amt, density, -1))
	elif outdoor_container.has_method("receive_lumps") and amt > 0.0:
		refused = float(outdoor_container.call("receive_lumps", amt))
	# The skip is BLOCKED and even its floor pile is maxed. Rather than deleting
	# the remainder from the world, carry it back into the source bin (which runs
	# its own overflow/floor-pile model). _refused_kg records that the run did not
	# fully land, so a caller can tell "dumped" from "dumped what fitted".
	if refused > 0.0 and indoor_container != null and is_instance_valid(indoor_container) \
			and indoor_container.has_method("add"):
		_refused_kg = refused
		indoor_container.call("add", refused, density, -1)
	_disembark(npc)
	mark_done()

## npc-05 — abandonment path (NPC._abandon_autonomy_task on a production
## preempt, the shift bell, the operator clearing the order). The base class's
## release() is a no-op, so an abandoned worker used to stay parented into the
## forklift seat with occupied=true — permanently jamming the idle-forklift gate
## every future dump task depends on — while the mass he had already scooped was
## gone from the bin and held nowhere.
func release(npc: Node) -> void:
	if _carried_kg > 0.0 and indoor_container != null and is_instance_valid(indoor_container) \
			and indoor_container.has_method("add"):
		var d : float = _carried_density if _carried_density > 0.0 else 200.0
		indoor_container.call("add", _carried_kg, d, -1)
	_carried_kg = 0.0
	if _forklift != null and is_instance_valid(_forklift) and _forklift.has_method("unload_bulk"):
		_forklift.call("unload_bulk")
	_disembark(npc)

func _disembark(npc: Node) -> void:
	if not _boarded:
		return
	_boarded = false
	if npc != null and is_instance_valid(npc) and npc.has_method("disembark_vehicle"):
		npc.call("disembark_vehicle")

func _find_nearest_idle_forklift(npc: Node) -> Node3D:
	var tree := npc.get_tree() if npc.has_method("get_tree") else null
	if tree == null:
		return null
	var best : Node3D = null
	var best_d : float = INF
	for v in tree.get_nodes_in_group("forklift"):
		if v is Node3D and is_instance_valid(v):
			if "occupied" in v and bool(v.occupied):
				continue
			var d : float = (v.global_position - npc.global_position).length()
			if d < best_d:
				best_d = d
				best = v
	return best

func _close_enough(a: Node, b: Node, r: float) -> bool:
	if a == null or b == null: return false
	if not (a is Node3D and b is Node3D): return false
	return (a.global_position - b.global_position).length() <= r

## ONE destination setter for both feet and wheels. There used to be two, byte
## for byte identical, which read as a foot/vehicle distinction that does not
## live here: NPC.set_autonomy_destination (NPC.gd:61-73) is what forwards the
## point to the vehicle autopilot when the worker is seated. Two names for one
## call invited a future edit to only one of them.
func _set_destination(npc: Node, pos: Vector3) -> void:
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)
