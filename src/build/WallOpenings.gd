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
## #105 — `thin_collision_source` lets the caller hand in a separate (single-
## face) mesh whose triangles drive collision while the visible shell stays
## thick. The thick shell's wall faces alone would trap the player capsule
## between inner + outer surfaces; the thin mesh has single-face walls so
## there's no wedge gap. When `thin_collision_source` is null we fall back to
## the visible shell's mesh — preserves the old behaviour for any caller that
## doesn't have a separate thin source.
func setup(shell: MeshInstance3D, thin_collision_source: Mesh = null) -> void:
	_shell = shell
	if _shell == null or _shell.mesh == null:
		push_error("[WallOpenings] No shell mesh to cache")
		return
	# Build the collision-source triangle list (`_orig_surfaces`) — from the thin
	# mesh when provided, otherwise from the visible shell. Visual triangles are
	# always read from the visible shell so the lit, textured wall is what the
	# player sees.
	_cache_surfaces_from(thin_collision_source if thin_collision_source != null else _shell.mesh, _orig_surfaces)
	# See _coplanar_tol's comment (#GATECARVE fix, 2026-08-29) — the two skins'
	# real separation depends on which geometry path this instance is fed.
	_coplanar_tol = WALL_THICK if solidify_enabled else _CLOSED_SHELL_COPLANAR_TOL
	if solidify_enabled:
		_visual_surfaces = _solidify_surfaces(_orig_surfaces)
	elif thin_collision_source != null:
		# Visual triangles come from the SOLID shell (already thick), collision
		# from the THIN mesh that was passed in. Independent arrays so each carve
		# pass works on its own data.
		_visual_surfaces = []
		_cache_surfaces_from(_shell.mesh, _visual_surfaces)
	else:
		# Single source for both — copy so a future in-place edit can't corrupt
		# the other pass. Defensive against the prior shared-reference pattern.
		_visual_surfaces = _orig_surfaces.duplicate(true)
	_ready_ok = true
	print("[WallOpenings] Cached %d collision surfaces and %d visual surfaces" \
		% [_orig_surfaces.size(), _visual_surfaces.size()])
	# Push the carved mesh + collision immediately, even before any opening.
	rebuild()

## Pull triangles out of any Mesh into the project's surface-dict layout.
## Used twice in setup() — once for collision, once for the visual override.
func _cache_surfaces_from(mesh: Mesh, dest: Array) -> void:
	dest.clear()
	if mesh == null:
		return
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		# Variant-first guard: a surface with only index data (null vertex buffer)
		# would throw 'Nil to PackedVector3Array' on a typed assign and crash the
		# door carve. Same nil-PackedArray class fixed in WorldSetup/MainWorld.
		var verts_raw0 : Variant = arr[Mesh.ARRAY_VERTEX]
		var verts: PackedVector3Array = verts_raw0 if verts_raw0 is PackedVector3Array else PackedVector3Array()
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
		dest.append({"v": fv, "n": fn})

func _cache_original() -> void:
	_orig_surfaces.clear()
	var mesh := _shell.mesh
	for s in mesh.get_surface_count():
		var arr: Array = mesh.surface_get_arrays(s)
		var verts_raw1 : Variant = arr[Mesh.ARRAY_VERTEX]
		var verts: PackedVector3Array = verts_raw1 if verts_raw1 is PackedVector3Array else PackedVector3Array()
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
## Returns true if the opening was registered (and a wall was actually cut),
## false if the box touches no shell geometry at all — a no-op that used to
## silently register anyway. Measured 2026-08-08: an operator's 41 repeated
## door_personnel clicks (each ~5-8 m from any wall — an OUTDOOR spot) each
## still ran the full O(shell_triangles) carve pass on both the visual AND
## collision mesh, growing the registered-opening count every time (so every
## LATER click got slower too, testing against a bigger box list) — the
## in-editor freeze/54-error session traced back to this. Skipping the
## rebuild entirely when nothing would be cut turns a silent, expensive no-op
## into a cheap, honest failure the caller can report.
func add_opening(id: String, center: Vector3, size: Vector3, rot_y: float) -> bool:
	if not _would_cut_anything(center, size, rot_y):
		push_warning("[WallOpenings] add_opening('%s') touches no shell geometry — skipped (no wall within the opening box)" % id)
		return false
	_openings[id] = {"center": center, "size": size, "rot_y": rot_y}
	rebuild()
	return true

## Cheap pre-check: does this box overlap ANY original (pre-carve) shell
## triangle? No mesh mutation, no rebuild — just the same _tri_box_status
## classifier the real carve uses, run once per triangle instead of the full
## recursive clip. O(shell_triangles), same as one pass of the real carve,
## but a small fraction of the cost since there's no subdivision or mesh
## re-emit.
func _would_cut_anything(center: Vector3, size: Vector3, rot_y: float) -> bool:
	if _shell == null:
		return false
	var inv : Transform3D = _shell.global_transform.affine_inverse() \
		if _shell.is_inside_tree() else Transform3D.IDENTITY
	var box := {"c": inv * center, "half": size * 0.5, "rot_y": rot_y}
	for surf in _orig_surfaces:
		var verts : PackedVector3Array = surf["v"]
		var vi := 0
		while vi + 2 < verts.size():
			if _tri_box_status(verts[vi], verts[vi + 1], verts[vi + 2], box) != -1:
				return true
			vi += 3
	return false

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

	# Reset the per-rebuild carve budget. Shared across the visual + collision
	# passes so the whole rebuild can't exceed the ceiling.
	_carve_remaining = _CARVE_TRI_BUDGET

	# global_transform requires the shell to be in the scene tree. setup() calls
	# rebuild() immediately, which in some test/headless paths runs BEFORE _shell
	# is tree-attached (causing "is_inside_tree()" warnings). Fall back to
	# identity in that case — equivalent to assuming mesh-local == world, which
	# is true for the test's origin-anchored shell. In-game the shell IS in the
	# tree at this point, so the real transform applies.
	var inv : Transform3D
	if _shell.is_inside_tree():
		inv = _shell.global_transform.affine_inverse()
	else:
		inv = Transform3D.IDENTITY
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

	# VISUAL: the (thick) solidified mesh, with openings carved out. Triangles
	# that PARTIALLY overlap an opening box are subdivided down to ~0.4 m so the
	# surrounding wall survives the carve. The old code dropped the whole
	# triangle on any overlap, which deleted the entire wall plane for a 1 m
	# door hole.
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
			var kept := _carve_triangle(a, b, c, boxes, 0)
			if kept.is_empty():
				continue
			# Re-use the source triangle's normals for ALL sub-triangles (good
			# enough — they all lie on the same source plane).
			var na := Vector3.UP
			var nb := Vector3.UP
			var nc := Vector3.UP
			if has_norm:
				na = sn[i0]; nb = sn[i0 + 1]; nc = sn[i0 + 2]
			for j in range(0, kept.size(), 3):
				out_v.append(kept[j]); out_v.append(kept[j + 1]); out_v.append(kept[j + 2])
				if has_norm:
					out_n.append(na); out_n.append(nb); out_n.append(nc)
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
	# FLAT per-face normals (#shell-winding). generate_normals() SMOOTHS by
	# merging coincident vertices, so where the .obj's mixed winding leaves two
	# neighbouring tris wound oppositely, their normals average toward ZERO and
	# the face shades BLACK (461/1948 faces measured that way — the "missing
	# walls"). smooth_group(-1) makes each face flat, so normals can never cancel;
	# with the shell material's CULL_DISABLED, both sides light either way. The
	# shell is nearly all flat planes, so flat shading reads correctly.
	st.set_smooth_group(-1)
	for v in fixed:
		st.add_vertex(v)
	st.generate_normals()
	st.commit(new_mesh)

## Coarse outward-winding pass (single global centroid). Cheap; only fixes
## grossly-inverted faces. It's NOT the black-face fix — that's the flat-normal
## (smooth_group -1) change in _emit_surface, which stops normal cancellation
## regardless of winding on the open, non-convex shell. Kept as harmless hygiene.
func _fix_winding_outward(verts: PackedVector3Array) -> PackedVector3Array:
	if verts.size() < 3:
		return verts
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
		if n.dot((a + b + c) / 3.0 - centroid) < 0.0:
			out[i0] = a; out[i0 + 1] = c; out[i0 + 2] = b
		else:
			out[i0] = a; out[i0 + 1] = b; out[i0 + 2] = c
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
			var kept := _carve_triangle(a, b, c, boxes, 0)
			for j in range(0, kept.size(), 3):
				faces.append(kept[j]); faces.append(kept[j + 1]); faces.append(kept[j + 2])
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
# TRIANGLE CARVE — subdivide partial overlaps so doors don't delete whole walls
# =============================================================================
const _CARVE_MIN_EDGE_M  : float = 0.4    # stop subdividing below this edge length
const _CARVE_MAX_DEPTH   : int   = 5      # safety cap on recursion (4^5 = 1024 leaves max/tri)
const _CARVE_TRI_BUDGET  : int   = 120000 # hard global ceiling per rebuild — prevents freeze

# Decremented as triangles are emitted during a rebuild. When it hits 0 the carve
# stops subdividing and falls back to cheap centroid-drop, so a degenerate/huge
# opening box can never lock the game up in the recursion.
var _carve_remaining : int = 0

## Returns a flat list of triangle vertices to KEEP (length always a multiple of
## 3). Empty array = the whole triangle was inside an opening. Triangles fully
## OUTSIDE all openings come back unchanged; partial overlaps are CLIPPED against
## the opening's wall-plane rectangle by Sutherland-Hodgman polygon clipping, so
## output edges land EXACTLY on the rectangle's perimeter (no teeth).
##
## Previously this used recursive midpoint subdivision which created a triangular
## staircase along the rectangle boundary — 342 boundary edges instead of 8 on a
## simple wall+door test (see src/tests/test_door_carve.gd).
## #GATECARVE fix (2026-08-29) — MEASURED, not guessed. The coplanarity
## tolerance now tracks `solidify_enabled` (an existing per-instance switch
## every caller already sets correctly for its own geometry — see setup()):
##
##   solidify_enabled=true  (thin imported mesh + runtime-solidified skins,
##     e.g. test_door_carve.gd's synthetic wall): the two skins are EXACTLY
##     WALL_THICK apart by construction, so tol = WALL_THICK (0.05 m, same
##     number as always — this path's behaviour is BIT-FOR-BIT UNCHANGED).
##
##   solidify_enabled=false (a pre-built closed-volume shell, e.g. the live
##     BuildingShellLoader.gd path via tools/generate_building.py): a
##     throwaway probe booting the real MainWorld and dumping every
##     _orig_surfaces/_visual_surfaces triangle's box-local Z near a live wall
##     (world (-254.77,-8.00,95.84), the same wall test_gate_carve.gd's own
##     outside->inside raycast finds) measured the inner skin at z=-0.2954
##     (outer skin at z=0.0046 — box mid-plane sits on the outer face where
##     the probe ray hits) — matching generate_building.py's own T=0.30 wall-
##     thickness constant almost exactly. The old 0.05 m tolerance was 5.9x
##     too small to ever reach that inner skin, so it was silently left
##     un-carved — solid from the inside, matching the operator's report
##     exactly (measured passability before this fix: 0/5 sample points
##     clear, test_gate_carve.gd). tol = 0.35 m = 0.30 m measured gap + 0.05 m
##     margin (rotation/corner slop) — still strictly inside the opening
##     box's own 1.0 m half-depth, so it can only pull in triangles that
##     already passed the box-overlap test, never geometry from an unrelated
##     wall.
##
## Tying the tolerance to solidify_enabled — rather than widening one global
## constant — is what keeps test_door_carve.gd's synthetic-wall path
## untouched: a bare global widen (tried first) let that test's solidify rim
## connectors (which span the full WALL_THICK between skins, at exactly the
## old tolerance's boundary) start passing too, flattening into 13 new
## off-plane teeth — a real regression, not a hypothetical one. Kept the same
## per-vertex-absolute-distance algorithm shape throughout (NOT the
## angle-based approach tried and reverted the same day).
var _coplanar_tol : float = WALL_THICK
const _SLIVER_AREA_TOL : float = 1e-6    # m²; drop triangles smaller than this
## Wider tolerance for the solidify_enabled=false (pre-built closed-volume
## shell) case — see _coplanar_tol's comment for the measured 0.2954 m gap
## this must clear.
const _CLOSED_SHELL_COPLANAR_TOL : float = 0.35
func _carve_triangle(a: Vector3, b: Vector3, c: Vector3, boxes: Array, depth: int) -> Array:
	# Classify against each box. Fully inside any → drop. Fully outside all → keep.
	var first_partial_box : Variant = null
	for box in boxes:
		var st := _tri_box_status(a, b, c, box)
		if st == 1:
			return []
		if st == 0 and first_partial_box == null:
			first_partial_box = box
	if first_partial_box == null:
		return [a, b, c]   # fully outside all openings
	# Safety budget — never normally needed with clip-based carve (each step
	# produces a bounded number of triangles), but keeps a worst-case ceiling.
	if _carve_remaining <= 0 or depth >= _CARVE_MAX_DEPTH:
		var centre := (a + b + c) / 3.0
		for box in boxes:
			if _point_in_box(centre, box):
				return []
		return [a, b, c]
	_carve_remaining -= 1
	# Clip against the FIRST partial box. The output triangles are guaranteed
	# strictly outside this box; recurse to handle any OTHER boxes that may
	# still partially overlap one of the clip outputs.
	var clipped : Array = _clip_triangle_against_box(a, b, c, first_partial_box)
	if clipped.is_empty():
		return []
	var out : Array = []
	@warning_ignore("integer_division")
	var n_tris : int = clipped.size() / 3
	for ti in n_tris:
		var ta : Vector3 = clipped[ti * 3]
		var tb : Vector3 = clipped[ti * 3 + 1]
		var tc : Vector3 = clipped[ti * 3 + 2]
		out.append_array(_carve_triangle(ta, tb, tc, boxes, depth + 1))
	return out

## Clip a triangle by ONE opening box and return a flat list of OUTSIDE
## sub-triangle vertices. The opening box is a 3D oriented box; for the
## common case (wall triangle coplanar with the box's Z=0 mid-plane), this
## reduces to a clean 2D rectangle subtraction. Non-coplanar triangles (e.g.
## a roof triangle merely brushing the door's vertical depth) are KEPT
## unchanged so the carve only affects actual wall geometry.
func _clip_triangle_against_box(a: Vector3, b: Vector3, c: Vector3, box: Dictionary) -> Array:
	var c0   : Vector3 = box["c"]
	var half : Vector3 = box["half"]
	var rot_y: float   = box["rot_y"]
	var cs := cos(-rot_y); var sn := sin(-rot_y)
	var v0 := _to_box(a - c0, cs, sn)
	var v1 := _to_box(b - c0, cs, sn)
	var v2 := _to_box(c - c0, cs, sn)
	# Coplanarity check — wall-plane carving only (the box's Z=0 is the wall).
	if absf(v0.z) > _coplanar_tol or absf(v1.z) > _coplanar_tol or absf(v2.z) > _coplanar_tol:
		return [a, b, c]
	var tri : Array = [Vector2(v0.x, v0.y), Vector2(v1.x, v1.y), Vector2(v2.x, v2.y)]
	var hx : float = half.x; var hy : float = half.y
	var avg_z : float = (v0.z + v1.z + v2.z) / 3.0
	# Four DISJOINT outside-of-rectangle zones (N, S, E, W). Each is a clip of
	# the triangle by 1-3 axis-aligned half-planes. Together they cover all of
	# (R² ∖ [-hx,hx]×[-hy,hy]) without overlap.
	#   N: y > hy   (full x range)
	#   S: y < -hy  (full x range)
	#   E: x > hx   AND -hy ≤ y ≤ hy
	#   W: x < -hx  AND -hy ≤ y ≤ hy
	var zones : Array = []
	var n_poly := _clip_poly_halfplane(tri, 1, true,  hy)
	if n_poly.size() >= 3: zones.append(n_poly)
	var s_poly := _clip_poly_halfplane(tri, 1, false, -hy)
	if s_poly.size() >= 3: zones.append(s_poly)
	var e_poly := _clip_poly_halfplane(tri,   0, true,  hx)
	e_poly      = _clip_poly_halfplane(e_poly, 1, false, hy)
	e_poly      = _clip_poly_halfplane(e_poly, 1, true,  -hy)
	if e_poly.size() >= 3: zones.append(e_poly)
	var w_poly := _clip_poly_halfplane(tri,   0, false, -hx)
	w_poly      = _clip_poly_halfplane(w_poly, 1, false, hy)
	w_poly      = _clip_poly_halfplane(w_poly, 1, true,  -hy)
	if w_poly.size() >= 3: zones.append(w_poly)
	# Triangulate each zone (fan from vertex 0), transform back to world space.
	var out : Array = []
	for zone in zones:
		for i in range(1, zone.size() - 1):
			var pa : Vector2 = zone[0]
			var pb : Vector2 = zone[i]
			var pc : Vector2 = zone[i + 1]
			var area : float = absf((pb.x - pa.x) * (pc.y - pa.y) - (pc.x - pa.x) * (pb.y - pa.y)) * 0.5
			if area < _SLIVER_AREA_TOL:
				continue   # drop slivers
			var wa : Vector3 = _from_box(Vector3(pa.x, pa.y, avg_z), cs, sn) + c0
			var wb : Vector3 = _from_box(Vector3(pb.x, pb.y, avg_z), cs, sn) + c0
			var wc : Vector3 = _from_box(Vector3(pc.x, pc.y, avg_z), cs, sn) + c0
			out.append(wa); out.append(wb); out.append(wc)
	return out

## Sutherland-Hodgman clip of a 2D polygon by ONE axis-aligned half-plane.
##   axis : 0 = X, 1 = Y
##   keep_gt : true = keep where coord > lim, false = keep where coord < lim
## Returns the clipped polygon (possibly empty / degenerate).
func _clip_poly_halfplane(poly: Array, axis: int, keep_gt: bool, lim: float) -> Array:
	if poly.size() < 3:
		return []
	var out : Array = []
	var n : int = poly.size()
	for i in n:
		var p : Vector2 = poly[i]
		var q : Vector2 = poly[(i + 1) % n]
		var p_coord : float = p.x if axis == 0 else p.y
		var q_coord : float = q.x if axis == 0 else q.y
		var p_in : bool = (p_coord > lim) if keep_gt else (p_coord < lim)
		var q_in : bool = (q_coord > lim) if keep_gt else (q_coord < lim)
		if p_in:
			out.append(p)
			if not q_in:
				var t : float = (lim - p_coord) / (q_coord - p_coord)
				out.append(p + (q - p) * t)
		elif q_in:
			var t : float = (lim - p_coord) / (q_coord - p_coord)
			out.append(p + (q - p) * t)
	return out

## Inverse of _to_box: rotate a box-local vector back to world delta.
func _from_box(v: Vector3, cs: float, sn: float) -> Vector3:
	return Vector3(v.x * cs + v.z * sn, v.y, -v.x * sn + v.z * cs)

## Classify a triangle against one oriented box:
## returns 1 if fully INSIDE, -1 if fully OUTSIDE, 0 if PARTIAL.
func _tri_box_status(a: Vector3, b: Vector3, c: Vector3, box: Dictionary) -> int:
	var c0: Vector3 = box["c"]
	var half: Vector3 = box["half"]
	var rot_y: float = box["rot_y"]
	var cs := cos(-rot_y)
	var sn := sin(-rot_y)
	var v0 := _to_box(a - c0, cs, sn)
	var v1 := _to_box(b - c0, cs, sn)
	var v2 := _to_box(c - c0, cs, sn)
	var inside_count := 0
	if absf(v0.x) <= half.x and absf(v0.y) <= half.y and absf(v0.z) <= half.z: inside_count += 1
	if absf(v1.x) <= half.x and absf(v1.y) <= half.y and absf(v1.z) <= half.z: inside_count += 1
	if absf(v2.x) <= half.x and absf(v2.y) <= half.y and absf(v2.z) <= half.z: inside_count += 1
	if inside_count == 3:
		return 1   # fully inside
	if not _tri_box_overlap(a, b, c, box):
		return -1  # fully outside
	return 0       # partial

func _point_in_box(p: Vector3, box: Dictionary) -> bool:
	var c0: Vector3 = box["c"]
	var half: Vector3 = box["half"]
	var rot_y: float = box["rot_y"]
	var cs := cos(-rot_y)
	var sn := sin(-rot_y)
	var v := _to_box(p - c0, cs, sn)
	return absf(v.x) <= half.x and absf(v.y) <= half.y and absf(v.z) <= half.z

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

func _project_box_half_extents(axis: Vector3, half: Vector3) -> float:
	return half.x * absf(axis.x) + half.y * absf(axis.y) + half.z * absf(axis.z)

func _project_triangle_extents(axis: Vector3, v0: Vector3, v1: Vector3, v2: Vector3) -> Vector2:
	var p0 := axis.dot(v0)
	var p1 := axis.dot(v1)
	var p2 := axis.dot(v2)
	return Vector2(minf(p0, minf(p1, p2)), maxf(p0, maxf(p1, p2)))

func _axis_overlap(axis: Vector3, v0: Vector3, v1: Vector3, v2: Vector3, half: Vector3) -> bool:
	var r := _project_box_half_extents(axis, half)
	var tri_extents := _project_triangle_extents(axis, v0, v1, v2)
	# Separated if the triangle's projection is entirely outside [-r, r].
	return not (tri_extents.x > r or tri_extents.y < -r)
