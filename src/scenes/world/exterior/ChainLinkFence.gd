extends Node3D
class_name ChainLinkFence

## Procedural chain-link fence built along a polyline (Array[Vector3] waypoints,
## Y = base of fence at each point). For every segment between consecutive
## waypoints this builder:
##   * Places galvanised-steel CylinderMesh posts every `post_spacing` m
##     (2.5 m default) along the segment, plus one post at each endpoint.
##   * Spans every pair of adjacent posts with a single QuadMesh panel
##     (post_spacing x fence_height) carrying a translucent grey
##     StandardMaterial3D so the mesh reads as a chain-link weave without
##     having to model every link.
##   * Ties posts together with a thin top and bottom horizontal BoxMesh rail.
##
## Caller-supplied parameters (passed via setup() BEFORE _ready() runs):
##   waypoints : Array[Vector3]  — world positions of fence corners; Y is the
##                                 base (ground) of the fence at that corner.
##
## Operator-tunable @export vars (set in inspector or from WorldLayout):
##   fence_height — total fence height in metres (default 2.2 m).
##   post_spacing — distance between adjacent posts in metres (default 2.5 m).
##   post_radius  — galvanised post tube radius in metres (default 0.04 m).
##
## Works equally for fencing the staff-parking perimeter, the bale-yard
## boundary, or the plant lot edge — caller just supplies a different polyline.

@export var fence_height : float = 2.2
@export var post_spacing : float = 2.5
@export var post_radius  : float = 0.04

var _waypoints : Array = []  # Array[Vector3]

func setup(waypoints: Array) -> void:
	_waypoints = waypoints.duplicate()

func _ready() -> void:
	if _waypoints.size() < 2:
		push_warning("[ChainLinkFence] needs at least 2 waypoints - got %d" % _waypoints.size())
		return
	_build_segments()

# ── Materials ─────────────────────────────────────────────────────────────────
func _make_post_material() -> StandardMaterial3D:
	# Galvanised steel — cool, slightly bluish, dulled by zinc oxidation.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.74, 0.76)
	mat.metallic = 0.55
	mat.roughness = 0.4
	return mat

func _make_rail_material() -> StandardMaterial3D:
	# Same galvanised stock as posts but a touch dirtier on the horizontals.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.68, 0.70, 0.72)
	mat.metallic = 0.5
	mat.roughness = 0.5
	return mat

func _make_mesh_material() -> StandardMaterial3D:
	# Translucent grey weave stand-in — alpha-blended so background reads
	# through, double-sided so it's visible from inside the lot too.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.55, 0.57, 0.58, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.7
	mat.metallic = 0.0
	return mat

# ── Segment loop ──────────────────────────────────────────────────────────────
func _build_segments() -> void:
	var post_mat  := _make_post_material()
	var rail_mat  := _make_rail_material()
	var mesh_mat  := _make_mesh_material()
	for i in range(_waypoints.size() - 1):
		var a : Vector3 = _waypoints[i]
		var b : Vector3 = _waypoints[i + 1]
		_build_one_segment(a, b, post_mat, rail_mat, mesh_mat, i)

func _build_one_segment(a: Vector3, b: Vector3, post_mat: Material,
		rail_mat: Material, mesh_mat: Material, seg_idx: int) -> void:
	var dir2 := Vector2(b.x - a.x, b.z - a.z)
	var length := dir2.length()
	if length < 0.05:
		return
	var yaw : float = atan2(dir2.x, dir2.y)        # rotation about +Y
	var basis := Basis(Vector3.UP, yaw)
	# Number of panels along this segment — at least one, even if the segment
	# is shorter than post_spacing.
	var panel_count : int = max(1, int(ceil(length / post_spacing)))
	var actual_spacing : float = length / float(panel_count)
	# Direction unit vector in world-XZ from a to b.
	var dir3 : Vector3 = (b - a)
	dir3.y = 0.0
	dir3 = dir3.normalized()
	# Posts: panel_count + 1 of them (both endpoints included).
	for p in range(panel_count + 1):
		var pos : Vector3 = a + dir3 * (actual_spacing * float(p))
		_build_post(pos, post_mat, seg_idx, p)
	# Panels + rails between each consecutive post pair.
	for p in range(panel_count):
		var p0 : Vector3 = a + dir3 * (actual_spacing * float(p))
		var p1 : Vector3 = a + dir3 * (actual_spacing * float(p + 1))
		var mid : Vector3 = (p0 + p1) * 0.5
		_build_panel(mid, basis, actual_spacing, mesh_mat, seg_idx, p)
		_build_rail(mid, basis, actual_spacing, rail_mat, seg_idx, p, true)   # top
		_build_rail(mid, basis, actual_spacing, rail_mat, seg_idx, p, false)  # bottom

# ── Per-element builders ──────────────────────────────────────────────────────
func _build_post(base_pos: Vector3, mat: Material, seg_idx: int, idx: int) -> void:
	var post := MeshInstance3D.new()
	post.name = "Post_%d_%d" % [seg_idx, idx]
	var cm := CylinderMesh.new()
	cm.top_radius = post_radius
	cm.bottom_radius = post_radius
	cm.height = fence_height
	post.mesh = cm
	post.material_override = mat
	add_child(post)
	# CylinderMesh is centred on origin, so lift by half-height to sit on base_pos.y.
	post.position = base_pos + Vector3(0.0, fence_height * 0.5, 0.0)

func _build_panel(mid: Vector3, basis: Basis, span: float, mat: Material,
		seg_idx: int, idx: int) -> void:
	var panel := MeshInstance3D.new()
	panel.name = "Mesh_%d_%d" % [seg_idx, idx]
	var qm := QuadMesh.new()
	qm.size = Vector2(span, fence_height)
	panel.mesh = qm
	panel.material_override = mat
	add_child(panel)
	# QuadMesh faces +Z in its local space — basis already aligns local +Z with
	# the segment direction, so the panel naturally runs along the segment with
	# its plane standing vertical.
	var centre : Vector3 = Vector3(mid.x, mid.y + fence_height * 0.5, mid.z)
	# Rotate the quad so its width (local X) lies along the segment and its
	# height (local Y) points up: yaw-rotate by 90deg around Y on top of basis.
	var quad_basis := basis * Basis(Vector3.UP, deg_to_rad(90.0))
	panel.transform = Transform3D(quad_basis, centre)

func _build_rail(mid: Vector3, basis: Basis, span: float, mat: Material,
		seg_idx: int, idx: int, is_top: bool) -> void:
	var rail := MeshInstance3D.new()
	rail.name = "Rail_%s_%d_%d" % ["Top" if is_top else "Bot", seg_idx, idx]
	var bm := BoxMesh.new()
	# Thin square cross-section, length = span along local +Z (basis-aligned).
	var rail_thickness : float = post_radius * 1.4
	bm.size = Vector3(rail_thickness, rail_thickness, span)
	rail.mesh = bm
	rail.material_override = mat
	add_child(rail)
	var y_off : float = (fence_height - rail_thickness * 0.5) if is_top else (rail_thickness * 0.5)
	var centre : Vector3 = Vector3(mid.x, mid.y + y_off, mid.z)
	rail.transform = Transform3D(basis, centre)
