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

# Sub-phase 2 (LIFT) is broken out into 4 hydraulically-distinct steps so the
# NPC actually drives the forks INTO the cart's pockets instead of just
# pretending. Step values: lift_height_m setpoints for each beat.
const LIFT_FLAT_M       : float = -0.375   # tine bottoms on the floor (pocket-insert pose)
const LIFT_TRANSPORT_M  : float =  0.05    # cart cleared ~5 cm off the floor for hauling
const SLIDE_IN_OFFSET_M : float =  1.40    # how far past the cart centre we drive to seat the forks
const POCKET_APPROACH_M : float =  1.80    # standoff in front of cart when lining up

enum Phase { WALK_TO_FORKLIFT, DRIVE_TO_CART, LIFT_AND_HAUL, DUMP_AND_RETURN }
# Sub-states inside LIFT_AND_HAUL — explicit so a missed pocket cleanly times
# out at the engage step rather than silently advancing.
enum Lift { POSE_FORKS, APPROACH_POCKETS, SLIDE_IN, ENGAGE, HAUL }

const PHASE_TIMEOUT_S    : float = 90.0    # per phase; long enough for any plausible drive
const LIFT_STEP_TIMEOUT_S: float = 12.0    # per LIFT sub-state — short enough to retry quickly
const POSE_SETTLE_S      : float = 1.2     # let hydraulics reach the pose before driving in
const ENGAGE_HOLD_S      : float = 0.8     # raise + watch for cart actually riding the forks
const ENGAGE_RISE_MIN    : float = 0.03    # cart Y must climb at least this much during ENGAGE
const APPROACH_DIST_M    : float = 1.6     # close enough to interact (enter forklift / grab cart)
const APPROACH_DIST_VEH  : float = 3.5     # close enough when DRIVING a forklift
const SEATED_DIST_M      : float = 1.0     # tighter tolerance once aligned to pockets
# phys-06 — "cart still on the forks" gate for every HAUL tick + the dump credit:
const CART_ON_FORKS_MAX_DIST_M : float = 3.0    # cart-to-chassis distance while riding
const CART_RIDE_DROP_TOL_M     : float = 0.25   # relative-Y slack (bordes step ≈ 0.12 m)

var lump_cart  : Node3D = null   # the target cart (set on init)
var dest_node  : Node3D = null   # the lumps_container (or shipping_container if indoor is full)
var _phase     : int    = Phase.WALK_TO_FORKLIFT
var _phase_t   : float  = 0.0
var _forklift  : Node3D = null
# True only after THIS task's NPC actually boarded _forklift. release() must not
# command the lift otherwise: _find_nearest_idle_forklift can pick a forklift that
# another NPC claims first, and npc_set_lift is ungated (Forklift.gd) — an unguarded
# release would slam that working forklift's carriage to the floor mid-haul.
var _boarded   : bool   = false
var _lift_step : int    = Lift.POSE_FORKS
var _step_t    : float  = 0.0
var _cart_y_at_engage_start : float = 0.0
# phys-06 — cart-minus-forklift Y captured when HAUL starts; the on-forks check
# compares against THIS (not absolute Y) because hauls legitimately descend the
# ~0.12 m bordes step on the way to the container.
var _cart_ride_dy : float = 0.0

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
	_step_t  += delta
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
		_boarded = true
	_phase = Phase.DRIVE_TO_CART
	_phase_t = 0.0

func _tick_drive_to_cart(npc: Node) -> void:
	if lump_cart == null or not is_instance_valid(lump_cart):
		mark_failed("cart_gone")
		return
	# Drive to a STAND-OFF pose in front of the cart, lined up with its
	# pocket axis. The lump cart's pockets open along its local ±Z (per the
	# #201 compound-collision spec); approach from the +Z side so the forks
	# slide in cleanly.
	var approach_pos : Vector3 = _pocket_approach_position()
	if not _close_enough_pos(_forklift, approach_pos, APPROACH_DIST_VEH):
		_set_vehicle_destination(npc, approach_pos)
		return
	_phase = Phase.LIFT_AND_HAUL
	_phase_t = 0.0
	_lift_step = Lift.POSE_FORKS
	_step_t = 0.0

# ── Phase 2: LIFT_AND_HAUL ────────────────────────────────────────────────────
# Pure physics pickup. No attach_load / detach_load magic — the script just
# drives the hydraulics + chassis through the same motions a real operator
# would. The cart sits on the forks because of contact + gravity (the fork
# tine collision and the cart's pocket cavities were both added in #201).
#
# Sub-steps:
#   POSE_FORKS         hydraulics → tines flat on floor, spread = 0.20 m
#                                   (forks centred at ±0.10 m → pocket centres)
#   APPROACH_POCKETS   chassis    → stand-off ~1.8 m in front of cart's open side
#   SLIDE_IN           chassis    → drive forward ~1.4 m so tines seat in pockets
#   ENGAGE             hydraulics → raise lift; verify cart Y rose with the forks
#   HAUL               chassis    → drive to dest_node with cart riding the forks
func _tick_lift_and_haul(npc: Node) -> void:
	if lump_cart == null or not is_instance_valid(lump_cart):
		mark_failed("cart_gone")
		return
	if dest_node == null or not is_instance_valid(dest_node):
		mark_failed("dest_gone")
		return
	if _step_t > LIFT_STEP_TIMEOUT_S:
		# Sub-step took too long — bail so the board can reissue and another
		# attempt can try a fresh approach pose. Common cause: cart pinned
		# against a wall; next NPC may pick the opposite side.
		mark_failed("lift_step_timeout:%d" % _lift_step)
		return
	match _lift_step:
		Lift.POSE_FORKS:
			# Drop tines flat to the floor and pinch spread to pocket centres.
			# _step_t buffers a brief settle window so the hydraulics physically
			# reach the pose (lift speed ≈ 0.4 m/s loaded, spread ≈ 0.10 m/s)
			# BEFORE we start nudging the chassis forward.
			if _forklift.has_method("npc_pose_for_lump_cart"):
				_forklift.call("npc_pose_for_lump_cart")
			if _step_t >= POSE_SETTLE_S:
				_lift_step = Lift.APPROACH_POCKETS
				_step_t = 0.0
		Lift.APPROACH_POCKETS:
			var approach : Vector3 = _pocket_approach_position()
			if not _close_enough_pos(_forklift, approach, SEATED_DIST_M):
				_set_vehicle_destination(npc, approach)
				return
			_lift_step = Lift.SLIDE_IN
			_step_t = 0.0
		Lift.SLIDE_IN:
			# Drive forward THROUGH the cart's centre. The fork tines (real
			# AnimatableBody3D collision, #201) slip into the cart's pocket
			# cavities (real compound collision, #201). Target is just past
			# the cart so the autopilot keeps nudging forward until the
			# physical contact stops the chassis.
			var seat_pos : Vector3 = _pocket_seat_position()
			if not _close_enough_pos(_forklift, seat_pos, 0.6):
				_set_vehicle_destination(npc, seat_pos)
				return
			# Forks seated. Park the chassis and snapshot the cart Y so the
			# next step can verify it actually rises with the carriage.
			if _forklift.has_method("npc_stop"):
				_forklift.call("npc_stop")
			_cart_y_at_engage_start = lump_cart.global_position.y
			_lift_step = Lift.ENGAGE
			_step_t = 0.0
		Lift.ENGAGE:
			# Raise the carriage. After a short hold, check whether the cart
			# came up with us. ≥ ENGAGE_RISE_MIN means the tines engaged the
			# pocket cavities; otherwise we missed and the task fails so the
			# board reissues and a fresh attempt can re-line-up.
			if _forklift.has_method("npc_set_lift"):
				_forklift.call("npc_set_lift", LIFT_TRANSPORT_M)
			if _step_t >= ENGAGE_HOLD_S:
				var rise : float = lump_cart.global_position.y - _cart_y_at_engage_start
				if rise < ENGAGE_RISE_MIN:
					mark_failed("forks_missed_pockets")
					return
				# phys-06 — snapshot the ride offset so HAUL can verify the cart
				# keeps riding the forks relative to the chassis.
				_cart_ride_dy = lump_cart.global_position.y - _forklift.global_position.y
				_lift_step = Lift.HAUL
				_step_t = 0.0
		Lift.HAUL:
			# phys-06 — the cart rides on contact + gravity only (no attach
			# magic), so it CAN slide off mid-drive. Fail fast — the board
			# re-emits against the cart's actual position — instead of arriving
			# and "dumping" from empty forks.
			if not _cart_still_on_forks():
				mark_failed("cart_lost_in_transit")
				return
			if not _close_enough(_forklift, dest_node, APPROACH_DIST_VEH):
				_set_vehicle_destination(npc, dest_node.global_position)
				return
			_phase = Phase.DUMP_AND_RETURN
			_phase_t = 0.0

func _tick_dump_and_return(npc: Node) -> void:
	# phys-06 — final gate before crediting: if the cart fell off the forks on
	# the way here, dumping anyway would teleport up to 90 kg from wherever the
	# cart actually lies into the container (mass-conservation pillar).
	if not _cart_still_on_forks():
		mark_failed("cart_lost_in_transit")
		return
	# Move the lumps mass from cart → dest. Cart returns to zero, dest grows.
	var dumped : float = 0.0
	if lump_cart.has_method("empty"):
		dumped = float(lump_cart.call("empty"))
	if dest_node.has_method("receive_lumps") and dumped > 0.0:
		dest_node.call("receive_lumps", dumped)
	# Lower the carriage so the cart settles back on the floor — gravity does
	# the parting work, no detach magic. Exit the forklift; the next task will
	# pick the NPC up.
	if _forklift.has_method("npc_set_lift"):
		_forklift.call("npc_set_lift", LIFT_FLAT_M)
	if npc.has_method("disembark_vehicle"):
		npc.call("disembark_vehicle")
	mark_done()

## Lifecycle hardening (npc-01/phys-06 companion) — release() runs on normal
## completion AND on every abort/failure path. Leave the rig usable: carriage
## down, NPC out of the seat. Without this a failed haul left the worker seated
## forever, the forklift read "occupied", and every reissued task starved on
## no_forklift_available. Both calls are idempotent (npc_disembark_vehicle
## no-ops when the NPC isn't seated), so the happy path's own disembark is safe.
func release(npc: Node) -> void:
	# Only command the lift if THIS task's NPC boarded the forklift — see _boarded.
	if _boarded and _forklift != null and is_instance_valid(_forklift):
		if _forklift.has_method("npc_set_lift"):
			_forklift.call("npc_set_lift", LIFT_FLAT_M)
	if npc != null and is_instance_valid(npc) and npc.has_method("disembark_vehicle"):
		npc.call("disembark_vehicle")

# ── Helpers ─────────────────────────────────────────────────────────────────

## Stand-off pose in world space: POCKET_APPROACH_M out from the cart along
## its pocket bearing (cart's local +Z, which is the side the pockets open
## on per the #201 compound-collision spec).
func _pocket_approach_position() -> Vector3:
	if lump_cart == null or not is_instance_valid(lump_cart):
		return Vector3.ZERO
	var fwd : Vector3 = -lump_cart.global_transform.basis.z   # cart -Z = pocket-open face
	return lump_cart.global_position - fwd * POCKET_APPROACH_M

## Drive-through target so the chassis keeps nudging forward until the tines
## physically bottom out in the pocket cavities. SLIDE_IN_OFFSET_M is "past
## the cart centre," which the autopilot will never actually reach — that's
## the point: the cart's collision walls stop the forklift at the right depth.
func _pocket_seat_position() -> Vector3:
	if lump_cart == null or not is_instance_valid(lump_cart):
		return Vector3.ZERO
	var fwd : Vector3 = -lump_cart.global_transform.basis.z
	return lump_cart.global_position + fwd * SLIDE_IN_OFFSET_M

## Position-flavoured _close_enough (mirror of BlowLeavesTask's helper): test a
## node against a bare Vector3 target. npc-12 — replaces the old _make_marker
## wrapper, which allocated an out-of-tree Node3D EVERY physics tick of the
## driving phases (~60 permanent orphans/s per driving leg — Node3D is not
## RefCounted) just to reuse the node-vs-node check.
func _close_enough_pos(a: Node, pos: Vector3, r: float) -> bool:
	if a == null or not (a is Node3D):
		return false
	return ((a as Node3D).global_position - pos).length() <= r

## phys-06 — true while the cart is genuinely riding the forks: still near the
## chassis AND not sunk relative to it since HAUL began (measured against
## _cart_ride_dy, not absolute Y — hauls legitimately descend the bordes step).
func _cart_still_on_forks() -> bool:
	if lump_cart == null or not is_instance_valid(lump_cart):
		return false
	if _forklift == null or not is_instance_valid(_forklift):
		return false
	if lump_cart.global_position.distance_to(_forklift.global_position) > CART_ON_FORKS_MAX_DIST_M:
		return false
	return (lump_cart.global_position.y - _forklift.global_position.y) \
		>= _cart_ride_dy - CART_RIDE_DROP_TOL_M

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
