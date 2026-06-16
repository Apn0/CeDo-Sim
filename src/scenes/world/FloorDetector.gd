extends Object

class_name FloorDetector

# =============================================================================
# FLOOR GENERATION
# =============================================================================
# Floor-detection tunables.
const FLOOR_HORIZONTAL_DOT  := 0.9    # cos(~25°) — face counts as horizontal if up-normal ≥ this
const FLOOR_Y_BUCKET_M      := 0.5    # 0.5 m bins for the area histogram
const FLOOR_AREA_THRESHOLD  := 0.5    # candidate bucket must have ≥ 50% of the max bucket's area
const FLOOR_BOX_SIZE_XZ     := 4000.0 # the collision floor is a huge flat slab; players can't walk off
const FLOOR_BOX_THICKNESS   := 1.0
# Quicksand fix (B): the shell mesh has its own horizontal floor triangles at the
# operating-floor Y (that's how _detect_operating_floor_y finds it). If TempFloor's
# top is at the SAME Y, the player's capsule sits on two coincident colliders, the
# solver oscillates contacts, and the capsule slowly sinks ("quicksand"). Lifting
# the TempFloor's top by 5 cm makes the shell's interior floor sit 5 cm BELOW the
# walkable surface and never contact the capsule. Machines still seat correctly
# because _floor_top_y() returns the LIFTED value.
const FLOOR_LIFT_OFFSET     := 0.05

# =============================================================================
# Floor generation — replace TempFloor's mesh + collision with a simple flat
# box positioned at the building's operating-floor Y.
#
# Why this is necessary: the building shell .obj is BLOSM-derived in real RD
# coordinates (Y range 67.83 – 112.14 m above sea level). After BuildingShell's
# parent transform shifts it down to world space, the operating floor sits at
# world Y ≈ −9.33 and the roof at ≈ −0.83. The OLD code keyed off `min_y` of
# ALL vertices, which picked the lowest mesh point (foundation level, world
# Y ≈ −15) and built a 10-m-thick Delaunay surface above it. Players spawned
# at the marker fell straight through the building, NPCs floated mid-air, and
# every machine placement was off. This rewrite asks the .obj an empirical
# question instead: "where is your biggest flat horizontal up-facing surface?"
# — the answer is the operating floor.
##
## Returns the lifted operating-floor top-Y so the caller can cache it (used by
## MainWorld._floor_top_y for machine placement, capsule spawn, etc.).
static func generate_floor_from_shell(floor_node: StaticBody3D, shell_mesh: MeshInstance3D) -> float:
	if shell_mesh == null:
		push_warning("[FloorDetector] Shell mesh missing — defaulting to world Y=0")
		return 0.0
	var floor_y := detect_operating_floor_y(shell_mesh)
	if is_nan(floor_y) or is_inf(floor_y):
		push_warning("[FloorDetector] Could not detect operating floor; defaulting to world Y=0")
		floor_y = 0.0
	print("[FloorDetector] Operating floor detected at world Y = %.3f" % floor_y)

	if floor_node == null:
		push_error("[FloorDetector] TempFloor node missing — cannot install floor")
		return floor_y + FLOOR_LIFT_OFFSET

	# Position the box so its TOP surface is at floor_y + FLOOR_LIFT_OFFSET — the
	# 5 cm gap lifts the walkable surface clear of the shell's coincident interior
	# floor triangles (quicksand fix B; see FLOOR_LIFT_OFFSET comment).
	var top_y : float = floor_y + FLOOR_LIFT_OFFSET
	floor_node.global_position = Vector3(0.0, top_y - FLOOR_BOX_THICKNESS * 0.5, 0.0)
	floor_node.global_rotation = Vector3.ZERO

	# Replace any prior mesh / collision (from the old Delaunay code or scene
	# defaults) with a simple flat 4000×1×4000 box.
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

	return top_y    # the TempFloor's TOP — what _floor_top_y() must return

## Detect the operating floor's world-Y by histogramming up-facing horizontal
## triangle area in 0.5 m Y buckets, then picking the LOWEST bucket whose
## area is at least 50 % of the maximum. The "≥ 50% of max" gate keeps small
## terraces/mezzanines out; the "lowest among candidates" picks the ground
## floor over a same-area roof. Returns +INF if no horizontal faces exist.
static func detect_operating_floor_y(shell_mesh: MeshInstance3D) -> float:
	var mesh := shell_mesh.mesh as ArrayMesh
	if mesh == null: return INF
	var xf := shell_mesh.global_transform
	var area_by_y : Dictionary = {}

	for s in range(mesh.get_surface_count()):
		var arr : Array = mesh.surface_get_arrays(s)
		# Variant-first: a null vertex buffer assigned straight to a typed
		# PackedVector3Array THROWS before the null check below can run (the
		# 'verts == null' line was dead — a typed var can't hold null). Guard
		# with `is` so floor detection survives a degenerate surface instead of
		# crashing and leaving the floor cache at its -9 m sentinel (whole scene
		# spawns underground).
		var verts_raw : Variant = arr[Mesh.ARRAY_VERTEX]
		var verts : PackedVector3Array = verts_raw if verts_raw is PackedVector3Array else PackedVector3Array()
		if verts.is_empty(): continue
		var idx_raw : Variant = arr[Mesh.ARRAY_INDEX]
		var idx : PackedInt32Array = idx_raw if idx_raw is PackedInt32Array else PackedInt32Array()
		if idx.is_empty():
			# Non-indexed mesh: triangles are sequential triples of vertices.
			for i in range(0, verts.size() - 2, 3):
				floor_add_face(verts[i], verts[i + 1], verts[i + 2], xf, area_by_y)
		else:
			for i in range(0, idx.size() - 2, 3):
				floor_add_face(verts[idx[i]], verts[idx[i + 1]], verts[idx[i + 2]], xf, area_by_y)

	if area_by_y.is_empty():
		# No horizontal faces — degenerate mesh. Caller falls back to Y=0.
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

static func floor_add_face(v1: Vector3, v2: Vector3, v3: Vector3, xf: Transform3D, dict: Dictionary) -> void:
	var p1 := xf * v1
	var p2 := xf * v2
	var p3 := xf * v3
	var cross := (p2 - p1).cross(p3 - p1)
	var len_cross := cross.length()
	if len_cross < 1e-3: return
	# Skip downward-facing triangles (ceilings, undersides) — we only want the
	# floor's top surface. cross.y / len_cross is the up-component of the normal.
	if cross.y / len_cross < FLOOR_HORIZONTAL_DOT: return
	var area := len_cross * 0.5
	var avg_y := (p1.y + p2.y + p3.y) / 3.0
	var bucket := snappedf(avg_y, FLOOR_Y_BUCKET_M)
	dict[bucket] = float(dict.get(bucket, 0.0)) + area
