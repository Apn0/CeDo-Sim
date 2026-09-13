extends RefCounted

# =============================================================================
# npc-05 / npc-06 — STAND-OFF POSE for a vehicle approaching a solid target.
# =============================================================================
# THE DEFECT THIS FIXES, AND THE MECHANISM — WHICH IS NOT THE OBVIOUS ONE.
#
# OverflowDumpTask aimed the forklift at container.global_position: the CENTRE of
# a solid body, i.e. a point inside it. It then gated the phase on centre-to-
# centre distance <= APPROACH_DIST_VEH (3.5 m). Measured result: the forklift
# stranded 4.90 m from the outdoor skip and the mass never moved.
#
# The tempting reading is "a forklift is longer than 3.5 m from origin to fork
# tips, so the gate is unsatisfiable". That is WRONG, and acting on it would have
# meant raising the radius — converting a visible strand into an invisible one.
# _npc_drive hard-stops at NPC_ARRIVE_TOL 2.2 m (BaseVehicle.gd:913, :997-1001)
# and 2.2 < 3.5, so a vehicle that actually REACHES its waypoint clears the gate
# with 1.3 m to spare. The real mechanism is the same contact wedge as jam 1: the
# chassis touches the skip before the ORIGIN can close to 3.5 m of the centre,
# and the autopilot keeps commanding forward into it.
#
# So the repair is to move the WAYPOINT out of the target's body, not to widen
# the gate. The in-repo precedent is EmptyLumpCartTask._pocket_approach_position
# (EmptyLumpCartTask.gd:283-287, used at :133-148), which is the one driving leg
# in the codebase that does not aim at a centre — and the one that works.
#
# The approach FACE is chosen from where the vehicle actually is, rather than
# assumed to be the target's local -Z as the lump cart's is. A skip has no
# pocket axis, and hardcoding one would park the forklift on the far side of the
# body it is trying to reach.
# =============================================================================

class_name ApproachPose

## Clearance between the target's surface and the stand-off point, on top of the
## target's own half-depth. Slightly under APPROACH_DIST_VEH so a vehicle that
## reaches the pose is inside the gate rather than exactly on it.
const DEFAULT_STANDOFF_M : float = 3.0
## Fallback half-extent when the target has no box collider to measure.
const FALLBACK_HALF_M : float = 1.5

## A reachable point in front of `target`, on the side `from` is standing on.
## Returns `target`'s own position when it cannot be measured — degrading to the
## old centre-aim rather than to a NaN.
static func for_target(target: Node3D, from: Node3D,
		standoff_m: float = DEFAULT_STANDOFF_M) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var centre : Vector3 = target.global_position
	if from == null or not is_instance_valid(from):
		return centre
	var to_veh : Vector3 = from.global_position - centre
	to_veh.y = 0.0
	if to_veh.length_squared() < 0.01:
		return centre
	# Pick the horizontal face whose outward normal points most nearly at the
	# vehicle, preferring faces that are physically unobstructed (clear of machines/walls).
	# Aligning to the target's own axes puts the forklift square to the face.
	var half := _half_extents(target)
	var best_n := Vector3.ZERO
	var best_dot := -INF
	var best_half := FALLBACK_HALF_M
	var fallback_n := Vector3.ZERO
	var fallback_dot := -INF
	var fallback_half := FALLBACK_HALF_M

	for axis in [target.global_transform.basis.x, target.global_transform.basis.z]:
		for s in [1.0, -1.0]:
			var n : Vector3 = (axis * s)
			n.y = 0.0
			if n.length_squared() < 0.01:
				continue
			n = n.normalized()
			var d : float = n.dot(to_veh.normalized())
			var h : float = half.x if axis == target.global_transform.basis.x else half.z
			var candidate : Vector3 = centre + n * (h + standoff_m)
			var is_free := _pose_free(target, candidate)
			if is_free:
				if d > best_dot:
					best_dot = d
					best_n = n
					best_half = h
			else:
				if d > fallback_dot:
					fallback_dot = d
					fallback_n = n
					fallback_half = h

	if best_n == Vector3.ZERO:
		best_n = fallback_n
		best_half = fallback_half
	if best_n == Vector3.ZERO:
		return centre
	return centre + best_n * (best_half + standoff_m)

## Test whether a candidate stand-off pose is free of solid colliders (machines, walls)
## and standable for a vehicle.
static func _pose_free(target: Node3D, pose: Vector3) -> bool:
	if target.is_inside_tree() and target.get_world_3d() != null:
		var space := target.get_world_3d().direct_space_state
		if space != null:
			var shape := BoxShape3D.new()
			shape.size = Vector3(1.4, 1.4, 1.4)
			var query := PhysicsShapeQueryParameters3D.new()
			query.shape = shape
			query.transform = Transform3D(Basis(), pose + Vector3(0.0, 0.7, 0.0))
			query.collision_mask = 1
			query.exclude = [target.get_rid()]
			var hits := space.intersect_shape(query, 1)
			if not hits.is_empty():
				return false
	if BaseVehicle._route_grid != null:
		var clr : float = BaseVehicle._route_grid.goal_clearance(pose)
		if clr > BaseVehicle.NPC_ARRIVE_TOL or clr < 0.0:
			return false
	return true

## XZ distance test against a bare position. Deliberately NOT 3D: the shipped
## _close_enough measures full length including Y, so an elevated container
## centre silently inflates the gate by its own height and the vehicle has to
## drive closer than the number says to satisfy it.
static func arrived_at(vehicle: Node3D, pose: Vector3, tol: float) -> bool:
	if vehicle == null or not is_instance_valid(vehicle):
		return false
	var p : Vector3 = vehicle.global_position
	return Vector2(p.x - pose.x, p.z - pose.z).length() <= tol

## Half-extents of the target's first box collider, in its own local axes.
static func _half_extents(target: Node3D) -> Vector3:
	for c in target.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size * 0.5
	return Vector3(FALLBACK_HALF_M, FALLBACK_HALF_M, FALLBACK_HALF_M)
