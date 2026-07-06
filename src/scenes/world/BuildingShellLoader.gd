extends Node3D

class_name BuildingShellLoader

# =============================================================================
# #195 — Building shell loader extracted from MainWorld.gd.
# =============================================================================
# Owns the building-shell visual mesh swap (thin .obj → solid .res when present)
# plus the WallOpenings spawn that carves doors / windows / gates at runtime.
# MainWorld instantiates one of these as a child node and calls
# load_shell_and_openings() exactly once during world setup; the loader then
# materialises the visual swap + collision regen via WallOpenings.
#
# Spawned nodes (WallOpenings) are still parented under MainWorld (not under
# this loader), so the resulting scene tree shape is identical to the
# pre-extract layout. The freshly-created WallOpenings instance is also
# written back to `_world.wall_openings` because BuildMode reads it from
# MainWorld a few hundred lines later.

# Reference back to MainWorld for _shell() / _generate_floor_from_shell() / the
# `building_shell_path` export and the `wall_openings` instance var. Set when
# the loader is added to the tree (its parent IS MainWorld), and re-set
# defensively in load_shell_and_openings() in case setup() ran before _ready.
var _world : Node = null
var _building_shell_path : String = ""

func _ready() -> void:
	if _world == null:
		_world = get_parent()

# ── Public entry point ──────────────────────────────────────────────────────
func setup(world: Node, building_shell_path: String) -> void:
	_world = world
	_building_shell_path = building_shell_path

func load_shell_and_openings() -> void:
	if _world == null:
		_world = get_parent()
	_load_building_shell()
	_spawn_wall_openings()

# =============================================================================
# BUILDING SHELL
# =============================================================================
func _load_building_shell() -> void:
	var mesh_instance := _world._shell() as MeshInstance3D
	if not mesh_instance:
		push_error("[BuildingShellLoader] ShellMesh not found")
		return
	# 2026-07-06 — the CeDo_building_solid.res swap is RETIRED. It was a stale
	# bake of the old 3DBAG solidify; preferring it silently overrode the
	# parametric rebuild (CeDo_factory_solid.obj, referenced by the tscn) at
	# runtime, so the editor showed the new building while the game loaded the
	# old one ("columns are not present anymore"). The tscn's mesh IS the
	# canonical shell now — never swap it out.
	print("[BuildingShellLoader] Using parametric shell from the scene (tools/generate_building.py)")
	_generate_floor_from_shell(mesh_instance)
	print("[BuildingShellLoader] Dynamic floor generated from building corners")

# Caches the building mesh so doors/windows can carve real, walkable openings
# at runtime (never touches the source .obj). Must exist BEFORE BuildMode loads
# its layout, since saved doors/windows re-cut their holes on load.
func _spawn_wall_openings() -> void:
	var shell := _world._shell() as MeshInstance3D
	if not shell:
		push_error("[BuildingShellLoader] ShellMesh not found — wall openings disabled")
		return
	var wall_openings = WallOpenings.new()
	wall_openings.name = "WallOpenings"
	# The parametric shell is built from CLOSED solid boxes/prisms — proper
	# volumes, not parallel zero-gap skins — so it serves as both the visual
	# and the collision source. The #105 wedge-trap only applied to the old
	# solidified thin mesh (capsule pinched between inner/outer faces of the
	# same wall); box walls have no such gap. No thin source, no re-solidify.
	wall_openings.solidify_enabled = false
	print("[BuildingShellLoader] Parametric shell: visual + collision from the same solid mesh")
	_world.add_child(wall_openings)
	wall_openings.setup(shell, null)
	# BuildMode reads `wall_openings` off MainWorld later (line ~1246), so keep
	# the reference live on the parent. Forwarder for the extraction.
	_world.wall_openings = wall_openings
	print("[BuildingShellLoader] WallOpenings ready")

var operating_floor_y: float = -9.0

const FLOOR_HORIZONTAL_DOT  := 0.9
const FLOOR_Y_BUCKET_M      := 0.5
const FLOOR_AREA_THRESHOLD  := 0.5
const FLOOR_BOX_SIZE_XZ     := 4000.0
const FLOOR_BOX_THICKNESS   := 1.0
const FLOOR_LIFT_OFFSET     := 0.05

func _generate_floor_from_shell(shell_mesh: MeshInstance3D) -> void:
	var floor_y := _detect_operating_floor_y(shell_mesh)
	if is_nan(floor_y) or is_inf(floor_y):
		push_warning("[BuildingShellLoader] Could not detect operating floor; defaulting to world Y=0")
		floor_y = 0.0
	print("[BuildingShellLoader] Operating floor detected at world Y = %.3f" % floor_y)

	var floor_node := shell_mesh.get_tree().current_scene.find_child("TempFloor", true, false) as StaticBody3D
	if floor_node == null:
		push_error("[BuildingShellLoader] TempFloor node missing — cannot install floor"); return

	var top_y : float = floor_y + FLOOR_LIFT_OFFSET
	floor_node.global_position = Vector3(0.0, top_y - FLOOR_BOX_THICKNESS * 0.5, 0.0)
	floor_node.global_rotation = Vector3.ZERO

	var mi := floor_node.find_child("MeshInstance3D", false, false) as MeshInstance3D
	if mi:
		var bm := BoxMesh.new()
		bm.size = Vector3(FLOOR_BOX_SIZE_XZ, FLOOR_BOX_THICKNESS, FLOOR_BOX_SIZE_XZ)
		mi.mesh = bm
		mi.transform = Transform3D()
	var cs := floor_node.find_child("CollisionShape3D", false, false) as CollisionShape3D
	if cs:
		var bx := BoxShape3D.new()
		bx.size = Vector3(FLOOR_BOX_SIZE_XZ, FLOOR_BOX_THICKNESS, FLOOR_BOX_SIZE_XZ)
		cs.shape = bx
		cs.transform = Transform3D()

	operating_floor_y = top_y

func _detect_operating_floor_y(shell_mesh: MeshInstance3D) -> float:
	var mesh := shell_mesh.mesh as ArrayMesh
	if mesh == null: return INF
	var xf := shell_mesh.global_transform
	var area_by_y : Dictionary = {}

	for s in range(mesh.get_surface_count()):
		var arr : Array = mesh.surface_get_arrays(s)
		var verts_raw : Variant = arr[Mesh.ARRAY_VERTEX]
		var verts : PackedVector3Array = verts_raw if verts_raw is PackedVector3Array else PackedVector3Array()
		if verts.is_empty(): continue
		var idx_raw : Variant = arr[Mesh.ARRAY_INDEX]
		var idx : PackedInt32Array = idx_raw if idx_raw is PackedInt32Array else PackedInt32Array()
		if idx.is_empty():
			for i in range(0, verts.size() - 2, 3):
				_floor_add_face(verts[i], verts[i + 1], verts[i + 2], xf, area_by_y)
		else:
			for i in range(0, idx.size() - 2, 3):
				_floor_add_face(verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]], xf, area_by_y)

	if area_by_y.is_empty():
		return INF

	var max_area := 0.0
	for b in area_by_y:
		if float(area_by_y[b]) > max_area: max_area = float(area_by_y[b])
	var threshold := max_area * FLOOR_AREA_THRESHOLD
	var candidates : Array = []
	for b in area_by_y:
		if float(area_by_y[b]) >= threshold:
			candidates.append(float(b))
	candidates.sort()
	return float(candidates[0])

func _floor_add_face(v1: Vector3, v2: Vector3, v3: Vector3, xf: Transform3D, dict: Dictionary) -> void:
	var p1 := xf * v1
	var p2 := xf * v2
	var p3 := xf * v3
	var cross := (p2 - p1).cross(p3 - p1)
	var len_cross := cross.length()
	if len_cross < 1e-3: return
	if cross.y / len_cross < FLOOR_HORIZONTAL_DOT: return
	var area := len_cross * 0.5
	var avg_y := (p1.y + p2.y + p3.y) / 3.0
	var bucket := snappedf(avg_y, FLOOR_Y_BUCKET_M)
	dict[bucket] = float(dict.get(bucket, 0.0)) + area
