extends Node3D
class_name TreeCluster

## Simple procedural trees for the CeDo plant exterior. The caller (typically
## MainWorld or a future WorldLayout component) constructs an empty TreeCluster
## node, adds it to the scene, and then calls ONE of the two factory entry
## points to populate it:
##
##   • cluster_at(centre, radius, n, seed_in)
##       drops `n` trees randomly inside a horizontal disc of `radius` metres
##       around `centre` (centre is in this node's local space).
##
##   • along_line(waypoints, spacing, seed_in)
##       walks the polyline `waypoints` and drops a tree every `spacing`
##       metres — used for fence-line shade trees along the parking lot or
##       lining the access road.
##
## Each tree is a CylinderMesh trunk (weathered bark, height = trunk_h) plus a
## SphereMesh canopy (matte foliage, radius = canopy_r) seated trunk_h above
## the trunk base. Per-instance scale (0.8..1.25) and Y-rotation are drawn
## from a RandomNumberGenerator seeded by tree index so the same cluster
## replays identically across saves. Caller passes `seed_in` so different
## clusters in the same world don't accidentally share variation.
##
## No textures, no preloads — all surface detail is mesh + flat StandardMaterial3D.

@export var trunk_h  : float = 3.2
@export var canopy_r : float = 1.8

func cluster_at(centre: Vector3, radius: float, n: int, seed_in: int = 0) -> void:
	if n <= 0:
		push_warning("[TreeCluster] cluster_at called with n=%d — nothing to build" % n)
		return
	if radius <= 0.0:
		push_warning("[TreeCluster] cluster_at called with radius=%f — nothing to build" % radius)
		return
	var trunk_mat := _make_trunk_material()
	var canopy_mat := _make_canopy_material()
	# Disc-distribution RNG (separate from per-tree variation RNG).
	var disc_rng := RandomNumberGenerator.new()
	disc_rng.seed = int(seed_in) * 1009 + 7
	for i in n:
		var r : float = sqrt(disc_rng.randf()) * radius
		var theta : float = disc_rng.randf() * TAU
		var pos : Vector3 = centre + Vector3(cos(theta) * r, 0.0, sin(theta) * r)
		_build_tree(pos, seed_in + i, trunk_mat, canopy_mat)

func along_line(waypoints: Array, spacing: float = 4.0, seed_in: int = 0) -> void:
	if waypoints.size() < 2:
		push_warning("[TreeCluster] along_line needs at least 2 waypoints — got %d" % waypoints.size())
		return
	if spacing <= 0.01:
		push_warning("[TreeCluster] along_line spacing=%f too small" % spacing)
		return
	var trunk_mat := _make_trunk_material()
	var canopy_mat := _make_canopy_material()
	var idx : int = 0
	# Walk each segment of the polyline, dropping a tree every `spacing` metres.
	# Carry leftover distance from segment to segment so spacing stays even
	# across corners.
	var carry : float = 0.0
	for s in range(waypoints.size() - 1):
		var a : Vector3 = waypoints[s]
		var b : Vector3 = waypoints[s + 1]
		var seg : Vector3 = b - a
		# Flatten to horizontal for spacing — trunks stand on the local y=0 plane.
		seg.y = 0.0
		var seg_len : float = seg.length()
		if seg_len < 0.01:
			continue
		var dir : Vector3 = seg / seg_len
		var t : float = carry
		while t <= seg_len:
			var pos : Vector3 = Vector3(a.x, 0.0, a.z) + dir * t
			_build_tree(pos, seed_in + idx, trunk_mat, canopy_mat)
			idx += 1
			t += spacing
		carry = t - seg_len

# ── Internals ─────────────────────────────────────────────────────────────────

func _make_trunk_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.32, 0.22, 0.15)   # weathered bark brown
	mat.roughness = 0.92
	mat.metallic = 0.0
	return mat

func _make_canopy_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.42, 0.18)   # matte foliage green
	mat.roughness = 0.95
	mat.metallic = 0.0
	return mat

func _build_tree(pos: Vector3, idx: int, trunk_mat: Material, canopy_mat: Material) -> void:
	# Deterministic per-tree variation — same idx → same tree shape across saves.
	var rng := RandomNumberGenerator.new()
	rng.seed = int(idx)
	var scale_f : float = rng.randf_range(0.8, 1.25)
	var yaw : float = rng.randf() * TAU
	var basis := Basis(Vector3.UP, yaw).scaled(Vector3(scale_f, scale_f, scale_f))
	# Group node so trunk + canopy share one transform.
	var tree := Node3D.new()
	tree.name = "Tree_%d" % idx
	add_child(tree)
	tree.transform = Transform3D(basis, pos)
	# Trunk — cylinder, base on the ground plane.
	var trunk := MeshInstance3D.new()
	trunk.name = "Trunk"
	var cm := CylinderMesh.new()
	cm.top_radius = 0.10
	cm.bottom_radius = 0.14
	cm.height = trunk_h
	trunk.mesh = cm
	trunk.material_override = trunk_mat
	tree.add_child(trunk)
	trunk.position = Vector3(0.0, trunk_h * 0.5, 0.0)
	# Canopy — sphere, seated trunk_h above the trunk base.
	var canopy := MeshInstance3D.new()
	canopy.name = "Canopy"
	var sm := SphereMesh.new()
	sm.radius = canopy_r
	sm.height = canopy_r * 2.0
	canopy.mesh = sm
	canopy.material_override = canopy_mat
	tree.add_child(canopy)
	canopy.position = Vector3(0.0, trunk_h + canopy_r * 0.6, 0.0)
