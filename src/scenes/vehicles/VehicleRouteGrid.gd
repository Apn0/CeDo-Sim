extends RefCounted

# =============================================================================
# npc-06 — VEHICLE GLOBAL ROUTE (occupancy grid + A*).
# =============================================================================
# BUILT BECAUSE IT WAS MEASURED NECESSARY, NOT ASSUMED. VehiclePilot's local
# sensing was shipped and benched first, and it did exactly half the job:
#
#   jam 1, dead reckoning : wedged 46.8 s at (-81.25, 156.22), covered 23.7 m
#   jam 1, pilot only     : wedged  0.0 s, covered 175.5 m in 180 s — and closed
#                           26 m of a 136 m leg, then circled. Tripling the time
#                           budget moved the best distance by 0.10 m while the
#                           distance travelled nearly doubled.
#
# So the wedge is a sensing defect (fixed, and attributable) and the remaining
# failure is a routing defect. A vehicle with whiskers and no map rounds the
# obstacle in front of it and then has no idea which way the goal is.
#
# WHY A GRID AND NOT A SECOND NAVMESH. Recast erodes uniformly by agent_radius;
# a forklift's swept clearance is heading-dependent and its turning circle is not
# representable at all. Worse, _npc_drive declares arrival at NPC_ARRIVE_TOL
# 2.2 m and immediately yaws at the next node, so it CORNER-CUTS up to 2.2 m off
# every waypoint — reintroducing the collision the path was computed to avoid.
# A grid samples the REAL colliders instead, so it discovers the un-spawned
# entry-gate gap empirically rather than eroding it away, needs no tagging, has
# no cell_size/agent_radius voxel pathology, and cannot seal the building.
#
# The grid is the STRATEGY and VehiclePilot is the TACTICS. The route says which
# way; the whiskers still handle the metre in front of the bumper, which is where
# corner-cutting and settling bales live. Neither replaces the other.
# =============================================================================

class_name VehicleRouteGrid

## Cell size. 2.0 m is a bit under a forklift width, so a blocked cell means "a
## vehicle-sized hull does not fit here" at roughly the resolution the vehicle
## cares about, and the whole site is ~6200 cells rather than a Recast heightfield.
const CELL_M : float = 2.0
## Probe hull. Slightly larger than CELL_M in XZ so adjacent free cells really do
## admit a chassis, and 2.0 m tall.
const PROBE_XZ : float = 2.2
const PROBE_H  : float = 2.0
## The probe sits this far above the operating floor, so the containment slab and
## low kerbs do not mark every cell on the site solid.
const PROBE_CLEARANCE_M : float = 0.35
## Refuse to build a grid larger than this many cells. A runaway extent (the
## 4000 m slab leaking into the bounds) must fail loudly, not allocate for ever.
const MAX_CELLS : int = 200000

var region_min : Vector2 = Vector2.ZERO      # world XZ of cell (0,0)
var cols : int = 0
var rows : int = 0
var floor_y : float = 0.0
var build_ms : int = 0
var blocked_cells : int = 0

var _astar : AStarGrid2D = null
var _solid : PackedByteArray = PackedByteArray()

## Sample the world into an occupancy grid. `bounds` is the site AABB
## (NavSiteBounds.compute); `y` the operating floor height. Returns false when
## the extent is unusable — callers must then fall back to the direct target
## rather than pretend a route exists.
func build(world: Node3D, bounds: AABB, y: float) -> bool:
	if bounds.size == Vector3.ZERO:
		push_warning("[VehicleRouteGrid] empty site bounds — no grid built")
		return false
	var t0 := Time.get_ticks_msec()
	floor_y = y
	region_min = Vector2(bounds.position.x, bounds.position.z)
	cols = int(ceil(bounds.size.x / CELL_M))
	rows = int(ceil(bounds.size.z / CELL_M))
	if cols <= 0 or rows <= 0 or cols * rows > MAX_CELLS:
		push_warning("[VehicleRouteGrid] refusing a %d x %d grid (%d cells, cap %d) — check the site bounds"
			% [cols, rows, cols * rows, MAX_CELLS])
		return false

	var space := world.get_world_3d().direct_space_state
	if space == null:
		return false
	var shape := BoxShape3D.new()
	shape.size = Vector3(PROBE_XZ, PROBE_H, PROBE_XZ)
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = shape
	q.collide_with_areas = false
	q.collide_with_bodies = true

	_solid = PackedByteArray()
	_solid.resize(cols * rows)
	blocked_cells = 0
	for cz in range(rows):
		for cx in range(cols):
			var p := cell_to_world(Vector2i(cx, cz))
			q.transform = Transform3D(Basis(), Vector3(p.x, floor_y + PROBE_CLEARANCE_M + PROBE_H * 0.5, p.y))
			var solid := false
			for hit in space.intersect_shape(q, 8):
				if _blocks(hit.get("collider", null)):
					solid = true
					break
			_solid[cz * cols + cx] = 1 if solid else 0
			if solid:
				blocked_cells += 1

	_astar = AStarGrid2D.new()
	_astar.region = Rect2i(0, 0, cols, rows)
	_astar.cell_size = Vector2(CELL_M, CELL_M)
	# Never cut a diagonal between two solid cells — that is how a route slips
	# through a wall corner the chassis cannot actually pass.
	_astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_astar.update()
	for cz in range(rows):
		for cx in range(cols):
			if _solid[cz * cols + cx] == 1:
				_astar.set_point_solid(Vector2i(cx, cz), true)
	build_ms = Time.get_ticks_msec() - t0
	return true

## Only STATIC geometry blocks a route. A parked vehicle moves, and a settling
## bale stack moves on its own — baking either into the route makes the grid
## silently false the moment physics runs. The pilot's whiskers handle both.
func _blocks(collider: Variant) -> bool:
	if collider == null or not (collider is Node):
		return false
	if not (collider is StaticBody3D):
		return false
	var n := collider as Node
	# The containment slab and the exterior apron are the surface, not obstacles.
	if n.name == "TempFloor" or n.name == "ExteriorGroundBody":
		return false
	if n.get_parent() != null and n.get_parent().name == "TempFloor":
		return false
	return true

func cell_to_world(c: Vector2i) -> Vector2:
	return region_min + Vector2((c.x + 0.5) * CELL_M, (c.y + 0.5) * CELL_M)

func world_to_cell(p: Vector3) -> Vector2i:
	return Vector2i(int(floor((p.x - region_min.x) / CELL_M)),
		int(floor((p.z - region_min.y) / CELL_M)))

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < cols and c.y < rows

func is_solid(c: Vector2i) -> bool:
	if not in_bounds(c):
		return true
	return _solid[c.y * cols + c.x] == 1

## Route from `from` to `to` as sparse world waypoints, INCLUDING the true goal
## as the final point. Empty when no route exists — the caller must report that
## as a named failure and must NOT fall back to dead reckoning, which is the
## behaviour this whole exercise exists to remove.
##
## Endpoints are snapped to the nearest free cell: a goal is routinely INSIDE a
## container or a cart pocket (EmptyLumpCartTask's seat position is deliberately
## unreachable), and a router that refused those would break working tasks.
func route(from: Vector3, to: Vector3) -> PackedVector3Array:
	var out := PackedVector3Array()
	if _astar == null:
		return out
	# Endpoints are CLAMPED into the region before the free-cell search. A vehicle
	# can legitimately stand outside the surveyed site — the measured jam-1 start
	# is 22 m past the east fence corner, off the 240 x 240 m apron entirely — and
	# an unclamped lookup silently returns "no route" for it, which reads as the
	# grid being broken rather than the start being off-map. Clamped, the vehicle
	# dead-reckons the open ground to the site edge and picks the route up there.
	var a := _nearest_free(_clamp_cell(world_to_cell(from)))
	var b := _nearest_free(_clamp_cell(world_to_cell(to)))
	if a == Vector2i(-1, -1) or b == Vector2i(-1, -1):
		return out
	var cells := _astar.get_id_path(a, b)
	if cells.is_empty():
		return out
	var pts : Array[Vector2] = []
	for c in cells:
		pts.append(cell_to_world(c))
	pts = _string_pull(pts)
	for p in pts:
		out.append(Vector3(p.x, floor_y, p.y))
	# The last grid point is a cell centre; the caller asked for a specific pose.
	if out.size() > 0:
		out.remove_at(out.size() - 1)
	out.append(Vector3(to.x, floor_y, to.z))
	return out

## Drop intermediate points the vehicle can drive straight past. Without this the
## route is one waypoint every 2 m and _npc_drive's 2.2 m arrival tolerance makes
## the vehicle chase points it is already standing on.
func _string_pull(pts: Array[Vector2]) -> Array[Vector2]:
	if pts.size() <= 2:
		return pts
	var out : Array[Vector2] = [pts[0]]
	var anchor := 0
	for i in range(2, pts.size()):
		if not _line_free(pts[anchor], pts[i]):
			out.append(pts[i - 1])
			anchor = i - 1
	out.append(pts[pts.size() - 1])
	return out

## Grid line-of-sight: sample the segment at half a cell and reject if any sample
## lands on a solid cell.
func _line_free(a: Vector2, b: Vector2) -> bool:
	var d := b - a
	var steps := int(ceil(d.length() / (CELL_M * 0.5)))
	for i in range(steps + 1):
		var p := a + d * (float(i) / float(maxi(steps, 1)))
		if is_solid(world_to_cell(Vector3(p.x, 0.0, p.y))):
			return false
	return true

func _clamp_cell(c: Vector2i) -> Vector2i:
	return Vector2i(clampi(c.x, 0, maxi(cols - 1, 0)), clampi(c.y, 0, maxi(rows - 1, 0)))

## Nearest free cell by expanding rings. Bounded so a fully solid grid returns a
## miss instead of scanning the whole site.
##
## npc-05 REALWORLD — TRIED AND MEASURED, REVERTED. A version of this function
## preferred a free cell whose local neighbourhood was at least 20 cells (BFS),
## on the theory that the npc-05 forklift's parking spot snaps into a walled-off
## 2-cell pocket (measured) and a bigger, connected cell would give it a real
## route instead of none. It did: route() started returning a path instead of
## empty. But the measured route was 125.4 m for a 33.5 m straight-line leg
## (NPCDBG on a real MainWorld boot) — the only way out of that pocket at grid
## resolution is around the far end of a ~118 m unbroken wall of solid cells, so
## "prefer a bigger component" forced a detour roughly 4x the direct distance,
## which blows the phase budget by itself before the vehicle even starts making
## progress. Dead reckoning (this function's plain nearest-free, unchanged
## below) had already covered the same 33.5 m leg in 128 s on an earlier real
## boot — proof the whiskers find a much shorter real path than the coarse grid
## admits, almost certainly through a gap narrower than one 2 m cell that the
## rasterised wall can't represent. Reverted rather than kept "for future work":
## a wrong route is worse than no route, since no route degrades to the
## already-working dead reckoning.
func _nearest_free(c: Vector2i) -> Vector2i:
	if in_bounds(c) and not is_solid(c):
		return c
	for r in range(1, 12):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dz) != r:
					continue
				var t := Vector2i(c.x + dx, c.y + dz)
				if in_bounds(t) and not is_solid(t):
					return t
	return Vector2i(-1, -1)
