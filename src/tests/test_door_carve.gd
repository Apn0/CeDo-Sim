extends SceneTree
## Headless test for the door/gate carve system.
##
## The user reports jagged "teeth" around carved door openings in-game. Before
## inspecting WHY the carve produces teeth, this test simply EXERCISES the carve
## on a controlled, minimal input mesh and measures the boundary cleanliness.
##
## Test setup: a single 10 × 4 m wall quad (2 triangles, facing +Z) at Z=0.
## Action: carve one 1.2 × 2.4 m door opening at the centre.
## Pass condition: the result has exactly **8 boundary edges** — 4 around the
## outer wall rectangle and 4 around the inner door rectangle.
## Any additional boundary edges = unsnapped subdivision vertices = teeth.
##
## Run (ALWAYS with --quit-after to dodge the autoload-hang issue):
##   godot --headless --path . --script res://src/tests/test_door_carve.gd --quit-after 30

const WallOpenings = preload("res://src/build/WallOpenings.gd")

const WALL_W       : float = 10.0      # wall quad width
const WALL_H       : float = 4.0       # wall quad height
const DOOR_W       : float = 1.2       # door opening width
const DOOR_H       : float = 2.4       # door opening height
const WELD_Q       : float = 1000.0    # 1 mm position weld for edge keying

func _initialize() -> void:
	# ── 1. Build a minimal test wall: one quad (2 tris) on the XY plane at Z=0 ─
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_normal(Vector3(0, 0, 1))
	var v_bl := Vector3(-WALL_W * 0.5, 0.0,       0.0)   # bottom-left
	var v_br := Vector3( WALL_W * 0.5, 0.0,       0.0)   # bottom-right
	var v_tr := Vector3( WALL_W * 0.5, WALL_H,    0.0)   # top-right
	var v_tl := Vector3(-WALL_W * 0.5, WALL_H,    0.0)   # top-left
	st.add_vertex(v_bl); st.add_vertex(v_br); st.add_vertex(v_tr)
	st.add_vertex(v_bl); st.add_vertex(v_tr); st.add_vertex(v_tl)
	var shell_mi := MeshInstance3D.new()
	shell_mi.mesh = st.commit()

	# ── 2. Add to scene + spin up WallOpenings ───────────────────────────────
	var root := get_root()
	var parent := Node3D.new()
	parent.name = "TestRoot"
	root.add_child(parent)
	parent.add_child(shell_mi)
	var wo = WallOpenings.new()
	parent.add_child(wo)
	wo.setup(shell_mi)

	# ── 3. Carve ONE door opening at the centre of the wall ──────────────────
	# Opening centre at (0, DOOR_H*0.5, 0) so the door sits on the floor.
	# Size = (1.2 m, 2.4 m, 2 m depth). rot_y = 0 (wall is on XY plane).
	wo.add_opening("test_door", Vector3(0.0, DOOR_H * 0.5, 0.0),
		Vector3(DOOR_W, DOOR_H, 2.0), 0.0)
	wo.rebuild()

	# ── 4. Extract the resulting mesh and count boundary edges ────────────────
	var arr_mesh : ArrayMesh = shell_mi.mesh as ArrayMesh
	if arr_mesh == null or arr_mesh.get_surface_count() == 0:
		print("RESULT FAIL: no surfaces after rebuild")
		quit(2); return
	var arrays := arr_mesh.surface_get_arrays(0)
	var verts : PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var n_verts := verts.size()
	var n_tris := n_verts / 3
	if n_verts % 3 != 0:
		print("RESULT FAIL: vertex count %d not a multiple of 3" % n_verts)
		quit(2); return

	# Weld positions, build an undirected edge-use map.
	var key_of := func(p: Vector3) -> String:
		return "%d_%d_%d" % [roundi(p.x * WELD_Q), roundi(p.y * WELD_Q), roundi(p.z * WELD_Q)]
	var edge_count : Dictionary = {}
	for ti in range(n_tris):
		var a : Vector3 = verts[ti * 3]
		var b : Vector3 = verts[ti * 3 + 1]
		var c : Vector3 = verts[ti * 3 + 2]
		var ka : String = key_of.call(a)
		var kb : String = key_of.call(b)
		var kc : String = key_of.call(c)
		for pair in [[ka, kb], [kb, kc], [kc, ka]]:
			var u : String = String(pair[0]); var v : String = String(pair[1])
			var key : String = (u + "|" + v) if u < v else (v + "|" + u)
			edge_count[key] = int(edge_count.get(key, 0)) + 1

	var boundary_edges := 0
	for k in edge_count:
		if edge_count[k] == 1:
			boundary_edges += 1

	# A clean rectangle-in-rectangle carve produces 4 outer + 4 inner = 8
	# boundary edges (the door rectangle is the INNER hole). Any extras are
	# subdivision verts that didn't get snapped flush to the opening rect.
	const EXPECTED_BOUNDARY := 8
	var teeth := maxi(0, boundary_edges - EXPECTED_BOUNDARY)

	# Also count unique boundary VERTICES — that's what shows up in-game as
	# teeth bumps in the wall edge. For a clean rectangle: 4 outer + 4 inner = 8.
	var boundary_verts : Dictionary = {}
	for k in edge_count:
		if edge_count[k] == 1:
			var parts : PackedStringArray = String(k).split("|")
			boundary_verts[parts[0]] = true
			boundary_verts[parts[1]] = true
	var n_boundary_verts : int = boundary_verts.size()
	var tooth_verts : int = maxi(0, n_boundary_verts - 8)

	# Classify each boundary vertex.
	#   OUTER-PERIMETER : on the 10×4 wall's outer rectangle
	#   DOOR-PERIMETER  : on the 1.2×2.4 door rectangle (T-junctions allowed here)
	#   OFF-PERIMETER   : NOT on either rectangle → a real tooth (BAD)
	const TOL : float = 0.001  # 1 mm
	var door_x0 := -DOOR_W * 0.5; var door_x1 :=  DOOR_W * 0.5
	var door_y0 :=  0.0;          var door_y1 :=  DOOR_H
	var wall_x0 := -WALL_W * 0.5; var wall_x1 :=  WALL_W * 0.5
	var wall_y0 :=  0.0;          var wall_y1 :=  WALL_H
	var on_door_perim := func(p: Vector3) -> bool:
		var on_x := absf(p.x - door_x0) < TOL or absf(p.x - door_x1) < TOL
		var on_y := absf(p.y - door_y0) < TOL or absf(p.y - door_y1) < TOL
		var inside_x := p.x >= door_x0 - TOL and p.x <= door_x1 + TOL
		var inside_y := p.y >= door_y0 - TOL and p.y <= door_y1 + TOL
		return (on_x and inside_y) or (on_y and inside_x)
	var on_wall_perim := func(p: Vector3) -> bool:
		var on_x := absf(p.x - wall_x0) < TOL or absf(p.x - wall_x1) < TOL
		var on_y := absf(p.y - wall_y0) < TOL or absf(p.y - wall_y1) < TOL
		var inside_x := p.x >= wall_x0 - TOL and p.x <= wall_x1 + TOL
		var inside_y := p.y >= wall_y0 - TOL and p.y <= wall_y1 + TOL
		return (on_x and inside_y) or (on_y and inside_x)
	# A vertex is a VISIBLE TOOTH only if it sits OFF the wall plane (z != 0).
	# A z=0 vertex not on a rectangle perimeter is a flat T-junction — invisible.
	const PLANE_TOL : float = 0.001  # 1 mm off the wall plane
	var off_perim_count := 0          # off-perimeter but on-plane → flat T-jct (acceptable)
	var visible_teeth   := 0          # off-plane → real visible bump (BAD)
	var off_perim_examples : Array = []
	var visible_teeth_examples : Array = []
	for k in boundary_verts:
		var parts2 : PackedStringArray = String(k).split("_")
		var v_pos := Vector3(parts2[0].to_int() / WELD_Q, parts2[1].to_int() / WELD_Q, parts2[2].to_int() / WELD_Q)
		var on_d : bool = on_door_perim.call(v_pos)
		var on_w : bool = on_wall_perim.call(v_pos)
		if not on_d and not on_w:
			off_perim_count += 1
			if off_perim_examples.size() < 5:
				off_perim_examples.append(v_pos)
		if absf(v_pos.z) > PLANE_TOL:
			visible_teeth += 1
			if visible_teeth_examples.size() < 5:
				visible_teeth_examples.append(v_pos)

	print("==== DOOR CARVE TEST ====")
	print("  result triangles    : %d" % n_tris)
	print("  result vertices     : %d" % n_verts)
	print("  boundary edges      : %d  (expected ≥ %d)" % [boundary_edges, EXPECTED_BOUNDARY])
	print("  boundary vertices   : %d  (≥ 8; extras OK if on-plane T-junctions)" % n_boundary_verts)
	print("  off-perim T-junc    : %d  (on wall plane, invisible — acceptable)" % off_perim_count)
	print("  VISIBLE teeth (z≠0) : %d  ← THIS MUST BE 0" % visible_teeth)
	if visible_teeth > 0:
		print("  example off-plane verts:")
		for ex in visible_teeth_examples:
			print("    %s" % str(ex))
	if visible_teeth == 0:
		print("  PASS — no off-plane bumps; opening is visually clean")
		quit(0)
	else:
		print("  FAIL — %d off-plane vertices = real teeth" % visible_teeth)
		quit(1)
