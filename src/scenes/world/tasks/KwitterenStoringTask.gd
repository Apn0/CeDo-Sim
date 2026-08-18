extends NpcAutonomyTask

class_name KwitterenStoringTask

# =============================================================================
# 'Storing kwitteren' — the second half of the operator's 2026-08-07 storing
# order: "clearing the alarm at the HMI is a DIFFERENT (storing) operator's
# task". Emitted by NpcAutonomyBoard.on_storing_fixed() with excluded_npc set
# to the fixer, so the board never hands it to the worker who fixed the
# storing. If only ONE storing-fixen worker is on shift, the task stays open
# until another becomes available — deliberate, per the order; the alarm bell
# stays red-flashing until then, exactly like an unacknowledged real plant.
#
# Effect when the worker reaches the HMI: the board records the alarm code in
# its npc-ack registry, which HmiOverlay ORs into its own KWITTEREN state —
# the bell drops from red-flashing to amber-steady. Acknowledge only silences;
# it never clears a fault (same rule as the player's KWITTEREN button).
# =============================================================================

const PHASE_TIMEOUT_S : float = 180.0
const APPROACH_DIST_M : float = 2.0
const ACK_DWELL_S     : float = 2.0     # a beat at the panel — no instant drive-by ack
const BASE_PRIORITY   : int   = 65      # just under fix_storing (70)

var alarm_key  : String = ""
var alarm_id   : String = ""
var hmi_pos    : Vector3 = Vector3.ZERO
var _dwell_t   : float = 0.0
var _phase_t   : float = 0.0
var _board_ref : Node  = null


func _init(key: String, aid: String, panel: Node3D, panel_pos: Vector3,
		fixer: Node, board: Node) -> void:
	task_name = "kwitteren_storing"
	alarm_key = key
	alarm_id = aid
	base_priority = BASE_PRIORITY
	priority = base_priority
	target_node = panel
	hmi_pos = panel_pos
	excluded_npc = fixer        # the fixer may NOT acknowledge their own fix
	_board_ref = board
	linger_s = 3.0
	accept_roles = PackedStringArray(["storing_fixen"])


func can_start(npc: Node) -> bool:
	if _done:
		return false
	if excluded_npc != null and is_instance_valid(excluded_npc) and npc == excluded_npc:
		return false
	return true


func tick(npc: Node, delta: float) -> bool:
	if _done:
		return true
	_phase_t += delta
	if _phase_t > PHASE_TIMEOUT_S:
		mark_failed("phase_timeout")
		release(npc)
		return true
	if not _close_enough(npc, hmi_pos, APPROACH_DIST_M):
		_set_dest(npc, hmi_pos)
		_dwell_t = 0.0
		return false
	_dwell_t += delta
	if _dwell_t < ACK_DWELL_S:
		return false
	if _board_ref != null and is_instance_valid(_board_ref) \
			and _board_ref.has_method("mark_npc_acked"):
		_board_ref.call("mark_npc_acked", alarm_id)
	release(npc)
	mark_done()
	return true


func _close_enough(npc: Node, pos: Vector3, r: float) -> bool:
	if npc == null or not (npc is Node3D):
		return false
	return ((npc as Node3D).global_position - pos).length() <= r


func _set_dest(npc: Node, pos: Vector3) -> void:
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)
