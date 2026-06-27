extends NpcAutonomyTask

class_name OverflowDumpTask

enum Phase { WALK_TO_FORKLIFT, DRIVE_TO_INDOOR, SCOOP_BULK, DRIVE_TO_OUTDOOR, DUMP }

const PHASE_TIMEOUT_S    : float = 90.0
const APPROACH_DIST_M    : float = 1.6
const APPROACH_DIST_VEH  : float = 3.5

var indoor_container  : Node3D = null
var outdoor_container : Node3D = null
var _phase     : int    = Phase.WALK_TO_FORKLIFT
var _phase_t   : float  = 0.0
var _forklift  : Node3D = null

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

func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
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
		_set_npc_destination(npc, _forklift.global_position)
		return
	if npc.has_method("board_vehicle"):
		npc.call("board_vehicle", _forklift)
	_phase = Phase.DRIVE_TO_INDOOR
	_phase_t = 0.0

func _tick_drive_to_indoor(npc: Node) -> void:
	if indoor_container == null or not is_instance_valid(indoor_container):
		mark_failed("indoor_gone")
		return
	if not _close_enough(_forklift, indoor_container, APPROACH_DIST_VEH):
		_set_vehicle_destination(npc, indoor_container.global_position)
		return
	_phase = Phase.SCOOP_BULK
	_phase_t = 0.0

func _tick_scoop_bulk(npc: Node) -> void:
	var amt : float = 0.0
	if indoor_container.has_method("empty"):
		amt = float(indoor_container.call("empty"))
	elif "lumps_count" in indoor_container:
		amt = float(indoor_container.get("lumps_count"))
		if indoor_container.has_method("clear_lumps"):
			indoor_container.call("clear_lumps")
	if _forklift.has_method("load_bulk"):
		_forklift.call("load_bulk", amt)
	_phase = Phase.DRIVE_TO_OUTDOOR
	_phase_t = 0.0

func _tick_drive_to_outdoor(npc: Node) -> void:
	if outdoor_container == null or not is_instance_valid(outdoor_container):
		mark_failed("outdoor_gone")
		return
	if not _close_enough(_forklift, outdoor_container, APPROACH_DIST_VEH):
		_set_vehicle_destination(npc, outdoor_container.global_position)
		return
	_phase = Phase.DUMP
	_phase_t = 0.0

func _tick_dump(npc: Node) -> void:
	var amt : float = 0.0
	if _forklift.has_method("unload_bulk"):
		amt = float(_forklift.call("unload_bulk"))
	if outdoor_container.has_method("add"):
		outdoor_container.call("add", amt, 200.0, -1)
	elif outdoor_container.has_method("receive_lumps") and amt > 0.0:
		outdoor_container.call("receive_lumps", amt)
	if npc.has_method("disembark_vehicle"):
		npc.call("disembark_vehicle")
	mark_done()

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

func _set_npc_destination(npc: Node, pos: Vector3) -> void:
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)

func _set_vehicle_destination(npc: Node, pos: Vector3) -> void:
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)
