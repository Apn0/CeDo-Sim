extends NpcAutonomyTask

class_name FixStoringTask

# =============================================================================
# 'Storing fixen' — operator order 2026-08-07, implementing the Tier-1
# storings-loop that docs/plant/npc_rol_taak_prioriteit.md:66-77 lists as the
# missing piece: alarm → walk to the unit → fix → storing gone.
#
# A storing-fixen worker walks to the alarmed machine and SERVICES it until the
# alarm clears (NpcAutonomyBoard.storing_active(alarm_key) goes false — the
# board tracks EventBus machine_alarm_raised/cleared plus its own INV-101
# feed-starvation monitor). Servicing relieves LineFlow backlog through the
# same CrewManager relief mechanic the jam dispatch uses, so the fix is real
# for buffer jams; for latched trips the worker holds the post until the
# condition ends (an e-stop reset stays a player action for now).
#
# The HMI acknowledge (kwitteren) is deliberately NOT part of this task —
# per the operator, that belongs to a DIFFERENT storing worker
# (KwitterenStoringTask, emitted by the board when this task completes).
#
# Dispatch: only "storing_fixen" accepts this. The board picks by
# closest + most important (see take_next_task's storing branch), and the
# 3 s post-completion linger comes from linger_s below.
# =============================================================================

enum Phase { WALK_TO_MACHINE, SERVICE }

const PHASE_TIMEOUT_S  : float = 180.0
const APPROACH_DIST_M  : float = 2.5
const SERVICE_BEAT_S   : float = 4.0    # == CrewManager.SERVICE_SECS dwell rhythm
const BASE_PRIORITY    : int   = 70     # above every housekeeping task (max 60)
const SEVERITY_BONUS   : int   = 5      # per severity point

var alarm_key   : String = ""           # "<machine_id>/<alarm_id>" board registry key
var machine_id  : String = ""
var alarm_id    : String = ""
var target_pos  : Vector3 = Vector3.ZERO
var _phase      : int    = Phase.WALK_TO_MACHINE
var _phase_t    : float  = 0.0
var _service_t  : float  = 0.0
var _board_ref  : Node   = null


func _init(key: String, mid: String, aid: String, severity: int,
		pos: Vector3, node: Node3D, board: Node) -> void:
	task_name = "fix_storing"
	alarm_key = key
	machine_id = mid
	alarm_id = aid
	base_priority = BASE_PRIORITY + severity * SEVERITY_BONUS
	priority = base_priority
	target_pos = pos
	target_node = node          # may be null — storing targets can be
	_board_ref = board          # positions from CrewManager._machine_list()
	linger_s = 3.0              # operator: stay assigned 3 s after completion
	accept_roles = PackedStringArray(["storing_fixen"])


## target_node may legitimately be null (position-only target) — the base
## can_start would refuse that, so override with the storing-specific check.
func can_start(_npc: Node) -> bool:
	return not _done and _storing_still_active()


func start(npc: Node) -> void:
	super.start(npc)
	_phase = Phase.WALK_TO_MACHINE
	_phase_t = 0.0
	_service_t = 0.0


func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	# The storing cleared while walking/servicing (another cause resolved it,
	# or the service below relieved it) — task complete either way.
	if not _storing_still_active():
		_complete(npc)
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
		mark_failed("phase_timeout:%d" % _phase)
		release(npc)
		return true
	match _phase:
		Phase.WALK_TO_MACHINE:
			if not _close_enough(npc, target_pos, APPROACH_DIST_M):
				_set_dest(npc, target_pos)
			else:
				_phase = Phase.SERVICE
				_phase_t = 0.0
				_service_t = 0.0
		Phase.SERVICE:
			_service_t += delta
			if _service_t >= SERVICE_BEAT_S:
				_service_t = 0.0
				_relieve_backlog()
	return _done


func _complete(npc: Node) -> void:
	release(npc)
	mark_done()
	if _board_ref != null and _board_ref.has_method("on_storing_fixed"):
		_board_ref.call("on_storing_fixed", alarm_key, npc)


func _storing_still_active() -> bool:
	if _board_ref == null or not is_instance_valid(_board_ref):
		return false
	return bool(_board_ref.call("storing_active", alarm_key))


## Relieve the alarmed machine's backlog through CrewManager's own relief
## mechanic — the identical effect a jam-dispatch responder has. Duck-typed:
## if the crew manager or its relief hook is absent, the service dwell still
## counts (self-clearing storingen end on their own condition).
func _relieve_backlog() -> void:
	var cm := _crew_manager()
	if cm != null and cm.has_method("relieve_station"):
		cm.call("relieve_station", machine_id)


func _crew_manager() -> Node:
	if _board_ref == null or not is_instance_valid(_board_ref):
		return null
	if _board_ref.has_method("crew_manager"):
		return _board_ref.call("crew_manager")
	return null


func _close_enough(npc: Node, pos: Vector3, r: float) -> bool:
	if npc == null or not (npc is Node3D):
		return false
	return ((npc as Node3D).global_position - pos).length() <= r


func _set_dest(npc: Node, pos: Vector3) -> void:
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)
