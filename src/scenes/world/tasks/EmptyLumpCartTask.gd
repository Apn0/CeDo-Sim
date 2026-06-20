extends NpcAutonomyTask

class_name EmptyLumpCartTask

# =============================================================================
# #198 — Empty a cooled, ~full LumpCart by forklift to the indoor
# lumps_container. If the indoor container is full, the destination switches
# to the outdoor shipping_container (open-top). Modelled in 4 sub-phases the
# NPC walks through in sequence:
#
#   PHASE 0  walk_to_forklift   — find nearest free forklift, enter cab
#   PHASE 1  drive_to_cart      — drive forklift up to the lump cart
#   PHASE 2  lift_and_haul      — engage forks under the cart, drive to dest
#   PHASE 3  dump_and_return    — tilt forks, dump lumps into container,
#                                 return the empty cart, exit forklift
#
# The cart's `lumps_kg` is moved into the destination container in PHASE 3.
# Phases advance based on proximity + a per-phase max-duration timeout so a
# stuck NPC eventually gives up cleanly (priority drops, board re-emits).

enum Phase { WALK_TO_FORKLIFT, DRIVE_TO_CART, LIFT_AND_HAUL, DUMP_AND_RETURN }

const PHASE_TIMEOUT_S    : float = 90.0    # per phase; long enough for any plausible drive
const APPROACH_DIST_M    : float = 1.6     # close enough to interact (enter forklift / grab cart)
const APPROACH_DIST_VEH  : float = 3.5     # close enough when DRIVING a forklift

var lump_cart  : Node3D = null   # the target cart (set on init)
var dest_node  : Node3D = null   # the lumps_container (or shipping_container if indoor is full)
var _phase     : int    = Phase.WALK_TO_FORKLIFT
var _phase_t   : float  = 0.0
var _forklift  : Node3D = null

func _init(cart: Node3D, dest: Node3D) -> void:
	task_name = "empty_lump_cart"
	# High priority: a full cooled cart sitting under the laser-filter discharge
	# means the line will jam if not handled. Below safety / line-down tasks but
	# above routine floor cleaning.
	priority = 60
	target_node = cart
	lump_cart = cart
	dest_node = dest
	# Forklift work isn't a shift-leader role. Filter to the people who actually
	# drive forklifts on a real CeDo shift (the all-rounder + the feeders +
	# transitional, plus the asst shift-leader who fills gaps).
	accept_roles = PackedStringArray(["all_rounder", "permanent_feeder", "transitional", "asst_shift_leader", "extruder_op"])

func can_start(npc: Node) -> bool:
	if not super.can_start(npc):
		return false
	if dest_node == null or not is_instance_valid(dest_node):
		return false
	# Skip if cart was already emptied between the board emitting this task and
	# the NPC accepting it (race-safe).
	if "has_lumps_worth_emptying" in lump_cart:
		return bool(lump_cart.call("has_lumps_worth_emptying"))
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
		Phase.DRIVE_TO_CART:     _tick_drive_to_cart(npc)
		Phase.LIFT_AND_HAUL:     _tick_lift_and_haul(npc)
		Phase.DUMP_AND_RETURN:   _tick_dump_and_return(npc)
	return _done

func _tick_walk_to_forklift(npc: Node) -> void:
	if _forklift == null or not is_instance_valid(_forklift):
		mark_failed("forklift_gone")
		return
	if not _close_enough(npc, _forklift, APPROACH_DIST_M):
		_set_npc_destination(npc, _forklift.global_position)
		return
	# At the forklift — enter the driver seat. Reuses #148 (NPC Phase 4 vehicle
	# entry parity) which exposes board_vehicle(npc, vehicle).
	if npc.has_method("board_vehicle"):
		npc.call("board_vehicle", _forklift)
	_phase = Phase.DRIVE_TO_CART
	_phase_t = 0.0

func _tick_drive_to_cart(npc: Node) -> void:
	if lump_cart == null or not is_instance_valid(lump_cart):
		mark_failed("cart_gone")
		return
	if not _close_enough(_forklift, lump_cart, APPROACH_DIST_VEH):
		_set_vehicle_destination(npc, lump_cart.global_position)
		return
	# Engage forks. Phase 2 conceptually grabs the cart and attaches it to
	# the forks; mechanically we just parent the cart node under the forklift's
	# fork-tip so it moves with the truck.
	if _forklift.has_method("attach_load"):
		_forklift.call("attach_load", lump_cart)
	_phase = Phase.LIFT_AND_HAUL
	_phase_t = 0.0

func _tick_lift_and_haul(npc: Node) -> void:
	if dest_node == null or not is_instance_valid(dest_node):
		mark_failed("dest_gone")
		return
	if not _close_enough(_forklift, dest_node, APPROACH_DIST_VEH):
		_set_vehicle_destination(npc, dest_node.global_position)
		return
	_phase = Phase.DUMP_AND_RETURN
	_phase_t = 0.0

func _tick_dump_and_return(npc: Node) -> void:
	# Move the lumps mass from cart → dest. Cart returns to zero, dest grows.
	var dumped : float = 0.0
	if lump_cart.has_method("empty"):
		dumped = float(lump_cart.call("empty"))
	if dest_node.has_method("receive_lumps") and dumped > 0.0:
		dest_node.call("receive_lumps", dumped)
	# Detach the cart, drop it back near the laser filter's discharge zone (where
	# it lives between cycles).
	if _forklift.has_method("detach_load"):
		_forklift.call("detach_load")
	# Exit the forklift — the NPC walks off, the next task will pick them up.
	if npc.has_method("disembark_vehicle"):
		npc.call("disembark_vehicle")
	mark_done()

# ── Helpers ─────────────────────────────────────────────────────────────────

func _find_nearest_idle_forklift(npc: Node) -> Node3D:
	var tree := npc.get_tree() if npc.has_method("get_tree") else null
	if tree == null:
		return null
	var best : Node3D = null
	var best_d : float = INF
	for v in tree.get_nodes_in_group("forklift"):
		if v is Node3D and is_instance_valid(v):
			# Skip occupied ones.
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
	# #148 — when an NPC is in a vehicle, the same set_autonomy_destination
	# call on the NPC propagates to the vehicle's NPC autopilot path so the
	# behaviour layer doesn't have to know whether the NPC is walking or
	# driving.
	if npc.has_method("set_autonomy_destination"):
		npc.call("set_autonomy_destination", pos)
