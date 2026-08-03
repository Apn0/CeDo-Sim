extends Node3D

class_name WorldFrame

# =============================================================================
# #195 extraction — canonical world-yaw math + layout transforms moved out of
# MainWorld.gd. Owns the cached `_world_yaw()` (bale-yard-derived) and the
# legacy `_building_yaw()` fallback (ShellMesh-AABB), plus the `_bo()` /
# `_layout_*` helpers that every exterior subsystem uses to rotate and anchor
# building-local offsets into world space.
# =============================================================================
# CANONICAL: `WorldLayout.floor_plan_rot_deg` — the floor-plan PDF rotation
# slider in WorldSetup's right panel — drives every BUILDING-LOCAL exterior
# placement: fence / parking / road network / road markings / crosswalk /
# sidewalk / trees / power poles / street signs / transformer / neighbour
# buildings / overhead bay lights / NPC posts. Those are authored as offsets
# from the plant anchor and MUST be rotated onto it (`_bo()`).
#
# It does NOT apply to WorldSetup markers (vehicle spawns / line starts / yard
# corners / player_spawn / factory_center). Those are stored SCENE-ABSOLUTE —
# the operator already drew them at the building's real orientation — so
# `_layout_to_scene()` is the identity. See its docstring for the measurement.
#
# That slider is the ONE rotation knob the operator owns: they tune it
# visually until the PDF lays correctly on the satellite. Making it canonical
# means tuning the slider tunes the entire game world's orientation, period.
# Earlier attempts (bale-yard longest-edge derivation, shell-AABB derivation)
# both moved the world out from under the operator without their input.
#
# Fallback: when floor_plan_rot_deg is 0 (operator hasn't touched it),
# `_compute_building_yaw()` derives a sensible default from the shell mesh
# AABB so a fresh save still aligns.

# Reference back to MainWorld for _shell / _layout_rel_sane / _sort_corners_ccw
# / _player_spawn_pos / _get_factory_anchor / _on_floor and the layout summary
# flags. Set in _ready() (its parent IS MainWorld) and overridden by setup()
# when MainWorld constructs the instance directly via .new(self).
var _world : Node = null

var _world_yaw_cache : float = NAN
var _building_yaw_cache : float = NAN

func _ready() -> void:
	if _world == null:
		_world = get_parent()

## Allow MainWorld to construct the frame eagerly (before the node is parented
## into the tree) and hand its own self-reference in. Mirrors the
## child-node-manager pattern used by ExteriorManager but lets the canonical
## yaw be queried during _ready() of OTHER subsystems that already need it.
func setup(world: Node) -> void:
	_world = world

# =============================================================================
# WORLD YAW — canonical rotation convention (WORLD cluster fix)
# =============================================================================

## Floor-plan-PDF-rotation-derived principal yaw — the canonical rotation for
## every exterior subsystem. Tracks the operator's calibrated PDF rotation
## slider in WorldSetup. Falls back to shell-AABB when the slider is at 0
## (operator hasn't tuned the PDF yet).
func _world_yaw() -> float:
	if not is_nan(_world_yaw_cache):
		return _world_yaw_cache
	_world_yaw_cache = _compute_world_yaw()
	var src : String = "floor_plan_rot_deg" \
		if absf(WorldLayout.floor_plan_rot_deg) > 0.01 \
		else "shell-AABB fallback (operator: tune the Floor plan Rotation slider)"
	print("[WorldFrame] world_yaw = %.1f deg (canonical / %s)" \
		% [rad_to_deg(_world_yaw_cache), src])
	return _world_yaw_cache

## Walk the first authoritative bale-yard polygon, find its longest edge,
## return `atan2(u.x, u.z)`. The yaw lives in the LAYOUT FRAME (not the scene
## frame): the operator drew the rectangle in WorldSetup's north-up XZ plane,
## and that drawn orientation IS the yaw the building should adopt. Falls back
## to the ShellMesh-AABB helper when no yards are saved (sandbox / fresh setup).
##
## Works on RAW corners, which is now simply the scene position: markers are
## stored scene-absolute, so the drawn edge direction IS the scene edge
## direction and no conversion is required to measure it.
func _compute_world_yaw() -> float:
	# CANONICAL: the floor-plan PDF's calibrated rotation drives world yaw.
	# That slider in WorldSetup (right panel → Floor plan → Rotation) is the
	# operator's EXPLICIT statement of "this is how the building is oriented
	# relative to north" — they aligned the PDF on the satellite by eye. Every
	# exterior subsystem rotates to match it, and the bale-yard polygons /
	# building-shell AABB / lat-lon overrides no longer steer global rotation
	# behind the operator's back.
	#
	# History: bale-yard-derived yaw made everything rotate ~139° away from
	# the building shell if the operator drew yards on the satellite (which
	# they always did). Shell-AABB-derived yaw was identity-pinned to whatever
	# the .obj's bake happened to be, which the operator can't tune.
	# floor_plan_rot_deg is the one number the operator owns and can SEE —
	# making it canonical removes the surprise.
	#
	# Convention: the floor_plan slider rotates the PDF around +Y, same axis
	# as world_yaw, so the value transfers directly in radians. If the apparent
	# rotation goes the wrong way at runtime, negate the return below — that
	# tunes one sign for the whole project.
	if absf(WorldLayout.floor_plan_rot_deg) > 0.01:
		# Sign-flip: the operator-tuned `floor_plan_rot_deg` rotates the PDF
		# CLOCKWISE (top-down view), while world_yaw is consumed as a
		# Basis(Vector3.UP, …) which rotates CCW around +Y. The two
		# conventions are mirrored, so the raw slider value lands the world
		# at the 180°-mirror of where the operator drew. Negating bridges
		# them — now the slider rotates the world the same direction the
		# PDF visually rotates.
		return -deg_to_rad(WorldLayout.floor_plan_rot_deg)
	# Operator hasn't calibrated the floor plan yet — fall back to building
	# shell AABB so a fresh save still produces a sensible alignment.
	return _compute_building_yaw()

# Legacy ShellMesh-AABB helper. Now used ONLY as the fallback path inside
# `_compute_world_yaw()` when no bale yards exist. Direct callers were
# repointed at `_world_yaw()` as part of the WORLD-cluster fix.

func _building_yaw() -> float:
	if not is_nan(_building_yaw_cache):
		return _building_yaw_cache
	_building_yaw_cache = _compute_building_yaw()
	return _building_yaw_cache

## Derive the building's principal yaw from the ShellMesh AABB longest top-down
## edge. The bale-yard convention proper would walk the actual wall polygon,
## but the AABB longest-edge gives us 0° for shells that are world-axis aligned
## (X-long) and ±90° for shells whose long axis is Z; sufficient for the
## current building. Picks up any yaw baked into shell.global_transform too.
func _compute_building_yaw() -> float:
	var shell : MeshInstance3D = _world.call("_shell") as MeshInstance3D
	if shell == null or shell.mesh == null:
		return 0.0
	var local_aabb : AABB = shell.mesh.get_aabb()
	# Transform the LOCAL AABB's four floor corners into world space so any
	# yaw inside shell.global_transform shows up in the longest edge.
	var x0 := local_aabb.position.x; var x1 := x0 + local_aabb.size.x
	var z0 := local_aabb.position.z; var z1 := z0 + local_aabb.size.z
	var y_mid := local_aabb.position.y + local_aabb.size.y * 0.5
	var c00 : Vector3 = shell.global_transform * Vector3(x0, y_mid, z0)
	var c01 : Vector3 = shell.global_transform * Vector3(x0, y_mid, z1)
	var c10 : Vector3 = shell.global_transform * Vector3(x1, y_mid, z0)
	# Pick the longer of the two unique adjacent edges (00→01 vs 00→10).
	var e1 : Vector3 = c01 - c00; e1.y = 0.0
	var e2 : Vector3 = c10 - c00; e2.y = 0.0
	var u_axis : Vector3
	if e1.length_squared() >= e2.length_squared():
		u_axis = e1.normalized() if e1.length() > 0.001 else Vector3.RIGHT
	else:
		u_axis = e2.normalized() if e2.length() > 0.001 else Vector3.RIGHT
	# atan2(x, z) — same convention as bale yard `bale_yaw` so rotating a
	# local +X offset by this yaw aligns with the building's long edge.
	return atan2(u_axis.x, u_axis.z)

## Rotate a local-frame offset vector through the CANONICAL world yaw (the
## bale-yard-derived `_world_yaw()`) and anchor it onto `ga`. Single helper
## used everywhere fence / parking / roads / lights / props add a local-frame
## Vector3 to the spawn anchor. Was previously keyed off `_building_yaw()`
## which disagreed with the operator-drawn bale yards; repointed at
## `_world_yaw()` as part of the WORLD-cluster fix.
func _bo(ga: Vector3, offset: Vector3) -> Vector3:
	return ga + Basis(Vector3.UP, _world_yaw()) * offset

# =============================================================================
# LAYOUT-FRAME TRANSFORMS
# =============================================================================

## The plant anchor — the player's ACTUAL spawn this run (set in `_spawn_player`,
## MainWorld.gd), pinned to the operating floor.
##
## NOT a marker origin. WorldSetup markers are scene-absolute and are never
## anchored onto this (see `_layout_to_scene`). This is the origin for genuinely
## building-LOCAL offsets — `_bo()`'s callers (roads / fence / parking / lamps),
## the NPC post anchor — and the reference point `_layout_rel_sane` measures
## marker plausibility against.
func _layout_anchor_xz() -> Vector3:
	var psp : Vector3 = _world.get("_player_spawn_pos")
	if psp != Vector3.ZERO:
		return _world.call("_on_floor", psp, 0.0)
	# Pre-_spawn_player fallback (rare — only hit if a layout-consumer fires before
	# the player is built). Mirrors the chain in _get_factory_anchor().
	return _world.call("_get_factory_anchor")

## Map a saved WorldSetup marker to its scene position — the XZ IDENTITY.
##
## CANONICAL FRAME: markers are SCENE-ABSOLUTE, not offsets. WorldSetup's only
## marker writers (`_place_point` :1260, `_add_multi_marker` :1348,
## `_commit_to_layout` :1137) store `_screen_to_floor()` / `_marker_world()`
## output verbatim — a camera ray onto the y=0 plane of the SAME tile-anchored
## frame MainWorld.tscn puts BuildingShell in. Nothing is subtracted and no yaw
## is applied on the way in, so nothing may be applied on the way out.
##
## MEASURED (2026-07-21, the operator's world_layout.json): the factory mesh's
## true scene centre is (-198.90, 95.84); the stored player_spawn/factory_center
## is (-202.66, 94.04) — 4.2 m away. Read absolutely, 11 of 13 markers land
## INSIDE the building footprint; read as rotated offsets, 0 of 13 do and every
## vehicle lands 120-270 m off-plant in the field to the north-east.
##
## HISTORY — do not reintroduce: this used to `Basis(UP, _world_yaw()) * rel +
## _layout_anchor_xz()`. That double-counted the orientation the operator had
## already drawn into the markers AND re-anchored an absolute coordinate onto
## itself, throwing vehicles ~228 m and bale yards ~300-420 m. Rotate+anchor
## still belongs to `_bo()`, which serves genuinely building-LOCAL offsets
## (fence / roads / parking / lamps) — that path is correct and is untouched.
##
## Y is discarded (markers live on a y=0 click plane); callers pass the result
## through `_on_floor()` to pin it to the operating floor.
func _layout_to_scene(rel: Vector3) -> Vector3:
	# Refresh the PerfHud one-liner once per run so the overlay reports the
	# transform that actually ran.
	if not bool(_world.get("_layout_summary_logged")):
		var a : Vector3 = _layout_anchor_xz()
		_world.set("layout_conv_summary",
			"Layout: markers are scene-absolute (no rotation, no anchor) — plant anchor (%.1f, %.1f)" \
				% [a.x, a.z])
		_world.set("_layout_summary_logged", true)
	return Vector3(rel.x, 0.0, rel.z)
