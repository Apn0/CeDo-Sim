extends Node
class_name LiftBooking

## #147 — Phase 3: lift reservations so two NPCs don't both try to claim the
## same mast lift. Lifts are identified by their VehicleBody3D node; reservations
## are keyed by lift instance ID, value = npc_id (or "" if free).
##
## This is a tiny module — operators register their lifts at world spawn,
## NPCs call claim()/release()/find_nearest_free() during task planning.
## Not an autoload: CrewManager owns the singleton instance for the run.

# lift_id -> npc_id (or "" if free)
var _reservations : Dictionary = {}
# lift_id -> Node (the actual mast-lift VehicleBody3D)
var _lifts        : Dictionary = {}

func register_lift(lift: Node) -> void:
	if lift == null:
		return
	var lid : int = lift.get_instance_id()
	_lifts[lid] = lift
	if not _reservations.has(lid):
		_reservations[lid] = ""

func unregister_lift(lift: Node) -> void:
	if lift == null:
		return
	var lid : int = lift.get_instance_id()
	_lifts.erase(lid)
	_reservations.erase(lid)

## Claim a lift for an NPC. Returns true if the claim succeeded (lift was free
## or already held by this NPC); false if another NPC holds it.
func claim(lift: Node, npc_id: String) -> bool:
	if lift == null:
		return false
	var lid : int = lift.get_instance_id()
	register_lift(lift)
	var current : String = String(_reservations.get(lid, ""))
	if current == "" or current == npc_id:
		_reservations[lid] = npc_id
		return true
	return false

func release(lift: Node, npc_id: String) -> void:
	if lift == null:
		return
	var lid : int = lift.get_instance_id()
	if String(_reservations.get(lid, "")) == npc_id:
		_reservations[lid] = ""

## Find the closest mast lift to `from_pos` that is currently free. Returns
## null if no free lift exists.
func find_nearest_free(from_pos: Vector3) -> Node:
	var best : Node = null
	var best_d : float = INF
	for lid in _lifts.keys():
		if String(_reservations.get(lid, "")) != "":
			continue
		var lift : Node = _lifts[lid]
		if lift == null or not is_instance_valid(lift):
			continue
		var d : float = (lift as Node3D).global_position.distance_to(from_pos)
		if d < best_d:
			best_d = d
			best = lift
	return best
