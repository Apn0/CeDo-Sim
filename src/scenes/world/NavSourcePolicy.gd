extends RefCounted

# =============================================================================
# npc-07 — WHAT COUNTS AS NAVMESH SOURCE GEOMETRY.
# =============================================================================
# One pure predicate, no state, no autoload. MainWorld tags everything this
# returns true for and bakes the result.
#
# RULE ORDER IS LOAD-BEARING. RigidBody3D is rejected FIRST, before any group is
# read, and that is not defensive tidiness — it is the difference between a
# navmesh and a lie. PlaceableCatalog.build_yard_bale_mm creates a RigidBody3D
# and calls rb.add_to_group("placed_object") (PlaceableCatalog.gd:6069), so a
# policy that tests the group first sweeps all 3234 yard bales into a STATIC
# navmesh which then silently falsifies itself every time a stack settles. The
# failure mode is intermittent and very close to undebuggable.
#
# WHAT IS DELIBERATELY *NOT* HERE: an allow-list of walkable placeable ids
# (grating_platform / lump_platform / stairs / belt decks). Under
# PARSED_GEOMETRY_STATIC_COLLIDERS, Recast derives walkability from slope and
# climb, so tagging those bodies IN makes their top faces walkable for free. A
# hand-maintained id list would be a permanent maintenance tax on
# PlaceableCatalog.gd:1099 metadata for a distinction the voxeliser already
# makes correctly — and the first id someone forgot to add would strand a
# mezzanine.
# =============================================================================

class_name NavSourcePolicy

## Sub-colliders already covered by their parent machine's own box. Tagging them
## doubles the collider count Recast parses and changes nothing about the result.
const REDUNDANT_GROUPS : Array[String] = ["machine_leg", "machine_foot"]
## Groups whose static bodies ARE the plant's obstacle set.
const SOURCE_GROUPS : Array[String] = ["placed_object", "belt"]

## True when `n` should be parsed as navmesh source geometry.
## `bake_shell` gates the building envelope — see MainWorld.NAV_BAKE_SHELL for
## why it ships false.
static func is_nav_source(n: Node, bake_shell: bool) -> bool:
	if n == null or not is_instance_valid(n):
		return false
	# (1) Dynamic bodies never enter a static navmesh. Yard bales are the reason
	#     (see the header); parked vehicles are the same class of mistake — one
	#     that parks inside the mesh it was baked from strands every later path.
	if n is RigidBody3D or n is CharacterBody3D or n is AnimatableBody3D:
		return false
	# (2) Only static colliders. This also excludes MeshInstance3Ds, which is the
	#     point: under STATIC_COLLIDERS the parse walks bodies, not visuals.
	if not (n is StaticBody3D):
		return false
	# (3) Redundant sub-colliders.
	for g in REDUNDANT_GROUPS:
		if n.is_in_group(g):
			return false
	# (4) The building envelope, gated.
	if is_building_shell(n):
		return bake_shell
	# (5) The plant's real obstacle set.
	for g in SOURCE_GROUPS:
		if n.is_in_group(g):
			return true
	return false

## True for the shell's collision body or anything under it. Matched by name
## because WallOpenings builds the body itself (WallOpenings.gd:315-335) and puts
## it in no group.
static func is_building_shell(n: Node) -> bool:
	var p : Node = n
	while p != null:
		var nm := p.name
		if nm == "BuildingShell" or nm == "ShellMesh" or nm == "ShellCollision" \
				or nm == "WallOpenings":
			return true
		p = p.get_parent()
	return false
