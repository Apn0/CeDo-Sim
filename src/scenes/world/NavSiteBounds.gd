extends RefCounted

# =============================================================================
# npc-06 / npc-07 — SITE EXTENT, measured at runtime.
# =============================================================================
# Both navigation consumers need to know how big the plant actually is:
#   · the vehicle route grid, to size its occupancy array;
#   · the navmesh bake, whose filter_baking_aabb is a PRECONDITION, not tuning.
#
# WHY THIS IS NOT A CONSTANT. BuildingShellLoader's TempFloor is a 4000 x 4000 m
# slab (BuildingShellLoader.gd:89) that exists so nothing can fall out of the
# world — it is not plant surface. Anything that takes its extent as the site
# extent is sizing itself to 16,000,000 m2 instead of ~24,600 m2. At the
# cell_size a real obstacle bake needs (0.25 m) that is 256M heightfield columns
# and multiple GB: it thrashes or OOMs, it does not merely run slowly.
#
# And it is measured rather than hardcoded because this project has already
# shipped a site map validated against a copy of its own stale constant. The
# bounds come from the bodies that are actually there.
# =============================================================================

class_name NavSiteBounds

## Padding beyond the outermost real geometry. Enough that a vehicle rounding the
## far side of the site still has grid under it.
const PAD_M : float = 20.0
## A source whose footprint exceeds this is the containment slab, not the site.
## The building itself measures ~151 x 72 m, so 1000 m rejects only the slab.
const MAX_SANE_SPAN_M : float = 1000.0

## XZ extent of the real plant: building shell, exterior apron
## and everything BuildMode has placed. Returns an AABB with Y spanning the
## bodies found. Empty (size == ZERO) when the world has no recognisable
## geometry — callers must treat that as "do not proceed", never as "everything".
static func compute(world: Node) -> AABB:
	var out := AABB()
	var have := false
	for n in _sources(world):
		var box := body_aabb(n)
		if box.size == Vector3.ZERO:
			continue
		# Reject the containment slab. Without this the answer is always 4000 m.
		if box.size.x > MAX_SANE_SPAN_M or box.size.z > MAX_SANE_SPAN_M:
			continue
		if not have:
			out = box
			have = true
		else:
			out = out.merge(box)
	if not have:
		return AABB()
	return out.grow(PAD_M)

## Bodies whose extent defines the site. Static geometry only: a parked vehicle
## or a settling bale must not be able to grow the site every time it moves.
static func _sources(world: Node) -> Array[Node3D]:
	var out : Array[Node3D] = []
	var tree := world.get_tree()
	if tree == null:
		return out
	for g in ["placed_object"]:
		for n in tree.get_nodes_in_group(g):
			if n is StaticBody3D and is_instance_valid(n):
				out.append(n as Node3D)
	# The shell and the exterior apron are not in any of those groups.
	for nm in ["BuildingShell", "ShellMesh", "ExteriorGroundBody"]:
		var n := world.find_child(nm, true, false)
		if n is Node3D:
			out.append(n as Node3D)
	return out


## World-space AABB of a node's collision shapes, falling back to its visual mesh.
## Collision is preferred: it is what a vehicle can actually hit. PUBLIC because
## the navmesh connectivity guard needs it too — the shell NODE sits at an
## RD-georeferenced origin, so only its geometry says where the building is.
static func body_aabb(n: Node3D) -> AABB:
	if n == null or not is_instance_valid(n):
		return AABB()
	var out := AABB()
	var have := false
	for c in n.get_children():
		var box := AABB()
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null:
			var sh := (c as CollisionShape3D).shape
			if sh is BoxShape3D:
				box = AABB(-(sh as BoxShape3D).size * 0.5, (sh as BoxShape3D).size)
			elif sh is ConcavePolygonShape3D or sh is ConvexPolygonShape3D:
				box = sh.get_debug_mesh().get_aabb()
			else:
				continue
			box = (c as Node3D).global_transform * box
		elif c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
			box = (c as Node3D).global_transform * (c as MeshInstance3D).mesh.get_aabb()
		else:
			continue
		if not have:
			out = box
			have = true
		else:
			out = out.merge(box)
	if not have and n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		return n.global_transform * (n as MeshInstance3D).mesh.get_aabb()
	return out if have else AABB()
