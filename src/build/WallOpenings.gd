extends Node
class_name WallOpenings

## Cuts real openings (doorways / windows) into the imported building shell at
## runtime — WITHOUT ever touching the source .obj on disk.
##
## The CeDo_building.obj is a non-manifold triangle soup, so CSG boolean
## subtraction produces garbage. Instead we keep an in-memory copy of the
## original mesh's triangles and, for every registered opening box, drop the
## triangles that overlap that box (full triangle-vs-OBB SAT test, so even large
## wall quads get carved). The surviving triangles are reassembled into a fresh
## ArrayMesh and a new trimesh collision is generated — giving a true, walkable
## hole in both the visuals and the physics.
##
## Openings are defined in WORLD space (center + size + rotation about Y). They
## are stored by id so the door/window that owns an opening can move/remove it.

# Give the imported (zero-thickness) shell real depth so walls/roof don't look
# like 2D planes. Walls (near-vertical faces) get WALL_THICK, roof/floor faces
# get FLAT_THICK. The building material has back-face culling disabled, so the
# extra faces light correctly without needing perfect winding.
@export var solidify_enabled: bool = true
const WALL_THICK: float = 0.05    # 5 cm side walls
const FLAT_THICK: float = 0.01    # 1 cm roof / floor

# The MeshInstance3D holding the building shell (BuildingShell/ShellMesh).
var _shell: MeshInstance3D = null

# Cached original geometry, flattened to non-indexed triangles, in MESH-LOCAL
# space. Array of { "v": PackedVector3Array, "n": PackedVector3Array }.
# _orig_surfaces  = the CLEAN thin mesh — used for COLLISION (no rim-lip noise).
# _visual_surfaces = the solidified (thick) mesh — used for VISUALS only.
var _orig_surfaces: Array = []
var _visual_surfaces: Array = []

# Registered openings, keyed by id → { center:Vector3, size:Vector3, rot_y:float }
var _openings: Dictionary = {}

var _ready_ok: bool = false

# =============================================================================
func setup(shell: MeshInstance3D) -> void:
	_shell = shell
	if _shell == null or _shell.mesh == null:
		push_error("[WallOpenings] No shell mesh to cache")
		return
	_cache_original()                       # _orig_surfaces = clean thin mesh
	if solidify_enabled:
		_visual_surfaces = _solidify_surfaces(_orig_surfaces)
	else:
		_visual_surfaces = _orig_surfaces
	_ready_ok = true
	print("[WallOpenings] Cached %d surfaces from building shell" % _orig_surfaces.size())
	# Push the (now thick) mesh + collision immediately, even before any opening.
	rebuild()

func _cache_original() -> void:
	_orig_surfaces.clear()
	var mesh := _shell.mesh
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms := PackedVector3Array()
		if arr[Mesh.ARRAY_NORMAL] != null:
			norms = arr[Mesh.ARRAY_NORMAL]
		var indices := PackedInt32Array()
		if arr[Mesh.ARRAY_INDEX] != null:
			indices = arr[Mesh.ARRAY_INDEX]

		var fv := PackedVector3Array()
		var fn := PackedVector3Array()
		var have_norm := norms.size() == verts.size()
		if indices.size() > 0:
			for i in indices:
				fv.append(verts[i])
				if have_norm:
					fn.append(norms[i])
		else:
			fv = verts.duplicate()
			if have_norm:
				fn = norms.duplicate()
		_orig_surfaces.append({"v": fv, "n": fn})

# =============================================================================
# SOLIDIFY  (give the flat shell thickness)
# =============================================================================
func _solidify_surfaces(surfaces: Array) -> Array:
	var out: Array = []
	for surf in surfaces:
		var sv: PackedVector3Array = surf["v"]
		var nv := PackedVector3Array()
		for i0 in range(0, sv.size(), 3):
			var a := sv[i0]
			var b := sv[i0 + 1]
			var c := sv[i0 + 2]
			var n := (b - a).cross(c - a)
			if n.length() < 0.000000001:
				continue
			n = n.normalized()
			var th := WALL_THICK if absf(n.y) < 0.5 else FLAT_THICK
			var off := n * th
			var a2 := a - off
			var b2 := b - off
			var c2 := c - off
			# Front (original) + back (offset, reversed winding).
			nv.append(a); nv.append(b); nv.append(c)
			nv.append(a2); nv.append(c2); nv.append(b2)
			# Rim quads so cut edges (e.g. door openings) show a solid cross-section.
			_quad(nv, a, b, b2, a2)
			_quad(nv, b, c, c2, b2)
			_quad(nv, c, a, a2, c2)
		out.append({"v": nv, "n": PackedVector3Array()})   # normals regenerated on emit
	return out

func _quad(nv: PackedVector3Array, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3) -> void:
	nv.append(p0); nv.append(p1); nv.append(p2)
	nv.append(p0); nv.append(p2); nv.append(p3)

# =============================================================================
# PUBLIC API
# =============================================================================
func add_opening(id: String, center: Vector3, size: Vector3, rot_y: float) -> void:
	_openings[id] = {"center": center, "size": size, "rot_y": rot_y}
	rebuild()

func remove_opening(id: String) -> void:
	if _openings.erase(id):
		rebuild()

func has_opening(id: String) -> bool:
	return _openings.has(id)

# =============================================================================
# REBUILD
# =============================================================================
func rebuild() -> void:
	if not _ready_ok:
		return

	var inv := _shell.global_transform.affine_inverse()
	# Pre-compute each opening in MESH-LOCAL space (so we test triangles directly
	# without transforming every vertex to world).
	var boxes: Array = []
	for id in _openings:
		var op: Dictionary = _openings[id]
		var c_world: Vector3 = op["center"]
		var c_local: Vector3 = inv * c_world
		boxes.append({
			"c": c_local,
			"half": (op["size"] as Vector3) * 0.5,
			"rot_y": float(op["rot_y"]),
		})

	# VISUAL: the (thick) solidified mesh, with openings carved out.
	var new_mesh := ArrayMesh.new()
	for surf in _visual_surfaces:
		var sv: PackedVector3Array = surf["v"]
		var sn: PackedVector3Array = surf["n"]
		var has_norm := sn.size() == sv.size()
		var out_v := PackedVector3Array()
		var out_n := PackedVector3Array()
		for i0 in range(0, sv.size(), 3):
			var a := sv[i0]
			var b := sv[i0 + 1]
			var c := sv[i0 + 2]
			if _tri_in_any_box(a, b, c, boxes):
				continue
			out_v.append(a); out_v.append(b); out_v.append(c)
			if has_norm:
				out_n.append(sn[i0]); out_n.append(sn[i0 + 1]); out_n.append(sn[i0 + 2])
		if out_v.size() == 0:
			continue
		_emit_surface(new_mesh, out_v, out_n)
	_shell.mesh = new_mesh

	# COLLISION: the CLEAN thin mesh, same openings carved. No rim-lip noise, so
	# the player/vehicles get a smooth floor and proper walls (not a field of
	# tiny 1 cm ledges that the thick mesh's edges would create).
	_regen_collision(boxes)
	print("[WallOpenings] Rebuilt — %d openings (visual thick, collision clean)" % _openings.size())

func _emit_surface(new_mesh: ArrayMesh, out_v: PackedVector3Array, _out_n: PackedVector3Array) -> void:
	# We ALWAYS regenerate normals from winding via SurfaceTool, ignoring any
	# normals the source OBJ supplied — the .obj export had mixed winding so the
	# inherited normals made some wall/roof faces render black on one side
	# (the symptom in the user's screenshots). With CULL_DISABLED set on the
	# shell material, the renderer auto-flips the normal for the back face, so
	# as long as the front-face normal is consistent with the winding, BOTH
	# sides light correctly.
	#
	# We also pass winding through a centroid-based pre-pass that flips any
	# triangle whose normal points TOWARD the mesh centroid (i.e. inward) —
	# catches the inverted-normal faces the OBJ exporter left behind.
	var fixed := _fix_winding_outward(out_v)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for v in fixed:
		st.add_vertex(v)
	st.generate_normals()
	st.commit(new_mesh)

## Walk every triangle and flip its winding if the geometric normal points
## toward the mesh centroid. A "mostly closed" shape (like our building shell)
## should have all face normals pointing OUTWARD; an inverted face has its
## normal pointing INWARD, which makes it render dark on the side the player
## sees. Centroid heuristic catches that case without needing user input.
func _fix_winding_outward(verts: PackedVector3Array) -> PackedVector3Array:
	if verts.size() < 3:
		return verts
	# Centroid = average of all vertices (good enough for a closed shell)
	var centroid := Vector3.ZERO
	for v in verts:
		centroid += v
	centroid /= float(verts.size())
	var out := PackedVector3Array()
	out.resize(verts.size())
	for i0 in range(0, verts.size(), 3):
		var a := verts[i0]
		var b := verts[i0 + 1]
		var c := verts[i0 + 2]
		var n := (b - a).cross(c - a)
		var tri_center := (a + b + c) / 3.0
		var outward := tri_center - centroid
		if n.dot(outward) < 0.0:
			# Normal points inward — flip the winding (swap two vertices)
			out[i0]     = a
			out[i0 + 1] = c
			out[i0 + 2] = b
		else:
			out[i0]     = a
			out[i0 + 1] = b
			out[i0 + 2] = c
	return out

func _regen_collision(boxes: Array) -> void:
	# Drop old collision, then build a fresh concave shape from the CLEAN thin
	# triangles (carved), so collision is smooth — no rim lips from the thick mesh.
	for ch in _shell.get_children():
		if ch is StaticBody3D:
			ch.queue_free()
	var faces := PackedVector3Array()
	for surf in _orig_surfaces:
		var sv: PackedVector3Array = surf["v"]
		for i0 in range(0, sv.size(), 3):
			var a := sv[i0]
			var b := sv[i0 + 1]
			var c := sv[i0 + 2]
			if _tri_in_any_box(a, b, c, boxes):
				continue
			faces.append(a); faces.append(b); faces.append(c)
	if faces.is_empty():
		return
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	cs.shape = shape
	body.add_child(cs)
	_shell.add_child(body)

# =============================================================================
# TRIANGLE vs ORIENTED BOX  (Akenine-Möller SAT, reduced to Y-rotation only)
# =============================================================================
func _tri_in_any_box(a: Vector3, b: Vector3, c: Vector3, boxes: Array) -> bool:
	for box in boxes:
		if _tri_box_overlap(a, b, c, box):
			return true
	return false

func _tri_box_overlap(a: Vector3, b: Vector3, c: Vector3, box: Dictionary) -> bool:
	var c0: Vector3 = box["c"]
	var half: Vector3 = box["half"]
	var rot_y: float = box["rot_y"]
	# Bring triangle into the box's local frame (translate by -center, undo rot_y)
	var cs := cos(-rot_y)
	var sn := sin(-rot_y)
	var v0 := _to_box(a - c0, cs, sn)
	var v1 := _to_box(b - c0, cs, sn)
	var v2 := _to_box(c - c0, cs, sn)

	# 1) Test the 3 box axes (AABB of the triangle vs the box half-extents).
	if minf(v0.x, minf(v1.x, v2.x)) > half.x or maxf(v0.x, maxf(v1.x, v2.x)) < -half.x:
		return false
	if minf(v0.y, minf(v1.y, v2.y)) > half.y or maxf(v0.y, maxf(v1.y, v2.y)) < -half.y:
		return false
	if minf(v0.z, minf(v1.z, v2.z)) > half.z or maxf(v0.z, maxf(v1.z, v2.z)) < -half.z:
		return false

	# 2) Test the triangle's face normal.
	var e0 := v1 - v0
	var e1 := v2 - v1
	var normal := e0.cross(e1)
	if not _axis_overlap(normal, v0, v1, v2, half):
		return false

	# 3) Test the 9 edge × box-axis cross products.
	var edges: Array[Vector3] = [e0, e1, v0 - v2]
	var axes: Array[Vector3]  = [Vector3.RIGHT, Vector3.UP, Vector3.BACK]
	for e in edges:
		for ax in axes:
			var axis := e.cross(ax)
			if axis.length_squared() < 0.0000001:
				continue
			if not _axis_overlap(axis, v0, v1, v2, half):
				return false
	return true

func _to_box(d: Vector3, cs: float, sn: float) -> Vector3:
	# Rotate around Y by the given cos/sin (already negated by caller).
	return Vector3(d.x * cs - d.z * sn, d.y, d.x * sn + d.z * cs)

func _axis_overlap(axis: Vector3, v0: Vector3, v1: Vector3, v2: Vector3, half: Vector3) -> bool:
	var p0 := axis.dot(v0)
	var p1 := axis.dot(v1)
	var p2 := axis.dot(v2)
	var r := half.x * absf(axis.x) + half.y * absf(axis.y) + half.z * absf(axis.z)
	var tri_min := minf(p0, minf(p1, p2))
	var tri_max := maxf(p0, maxf(p1, p2))
	# Separated if the triangle's projection is entirely outside [-r, r].
	return not (tri_min > r or tri_max < -r)
