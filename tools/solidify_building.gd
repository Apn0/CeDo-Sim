extends SceneTree
## Building solidifier — turns the thin-walled 3DBAG LOD2.2 shell (CeDo_building.obj,
## an unwelded triangle soup of zero-thickness surfaces) into a SOLID, welded mesh
## with real wall thickness, so it stops leaking light / glitching and gives proper
## collision. Output is a Godot ArrayMesh resource the building nodes point at.
##
## Run locally (headless), re-runnable any time the source .obj changes:
##   godot --headless --script res://tools/solidify_building.gd
## Tune WALL_THICKNESS below (metres). Coordinates are kept identical to the source
## (Dutch RD), so the result is a drop-in for the existing BuildingShell node offset.

const SRC            := "res://assets/models/CeDo_building.obj"
const OUT            := "res://assets/models/CeDo_building_solid.res"
const OUT_OBJ        := "res://assets/models/CeDo_building_solid.obj"   # external-viewable
const WALL_THICKNESS := 0.30          # metres of wall/roof thickness
const WELD_Q         := 1000.0        # weld tolerance: round positions to 1 mm

func _initialize() -> void:
	var t0 := Time.get_ticks_msec()
	print("[solidify] reading %s" % SRC)
	var f := FileAccess.open(SRC, FileAccess.READ)
	if f == null:
		push_error("[solidify] cannot open %s" % SRC); quit(1); return

	var raw : PackedVector3Array = PackedVector3Array()
	var tris : Array = []                       # [i0,i1,i2] 0-based into raw
	while not f.eof_reached():
		var line := f.get_line()
		if line.begins_with("v "):
			var p := line.split(" ", false)
			if p.size() >= 4:
				raw.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
		elif line.begins_with("f "):
			var p := line.split(" ", false)
			var idx : Array = []
			for k in range(1, p.size()):
				var tok := p[k].split("/")[0]
				var vi := tok.to_int()
				if vi < 0: vi = raw.size() + vi + 1     # negative = relative
				idx.append(vi - 1)
			for k in range(1, idx.size() - 1):          # fan-triangulate n-gons
				tris.append([idx[0], idx[k], idx[k + 1]])
	f.close()
	print("[solidify] raw: %d verts, %d tris" % [raw.size(), tris.size()])

	# ── Weld coincident vertices ───────────────────────────────────────────────
	var weld := {}
	var uniq : PackedVector3Array = PackedVector3Array()
	var remap : PackedInt32Array = PackedInt32Array()
	remap.resize(raw.size())
	for i in raw.size():
		var pv := raw[i]
		var key := "%d_%d_%d" % [roundi(pv.x * WELD_Q), roundi(pv.y * WELD_Q), roundi(pv.z * WELD_Q)]
		if weld.has(key):
			remap[i] = weld[key]
		else:
			var ni := uniq.size()
			weld[key] = ni
			uniq.append(pv)
			remap[i] = ni
	var wt : Array = []
	for t in tris:
		var a : int = remap[t[0]]; var b : int = remap[t[1]]; var c : int = remap[t[2]]
		if a != b and b != c and a != c:
			wt.append([a, b, c])
	print("[solidify] welded: %d verts, %d tris" % [uniq.size(), wt.size()])

	# ── Per-vertex normals (area-weighted) for the inward offset direction ──────
	var vn : PackedVector3Array = PackedVector3Array()
	vn.resize(uniq.size())
	for i in vn.size(): vn[i] = Vector3.ZERO
	for t in wt:
		var fn := (uniq[t[1]] - uniq[t[0]]).cross(uniq[t[2]] - uniq[t[0]])
		vn[t[0]] += fn; vn[t[1]] += fn; vn[t[2]] += fn
	for i in vn.size():
		vn[i] = vn[i].normalized() if vn[i].length() > 1e-9 else Vector3.UP

	# ── Boundary directed edges (used by exactly one triangle) ──────────────────
	var present := {}
	for t in wt:
		present["%d_%d" % [t[0], t[1]]] = true
		present["%d_%d" % [t[1], t[2]]] = true
		present["%d_%d" % [t[2], t[0]]] = true
	var boundary : Array = []
	for t in wt:
		for ed in [[t[0], t[1]], [t[1], t[2]], [t[2], t[0]]]:
			if not present.has("%d_%d" % [ed[1], ed[0]]):
				boundary.append(ed)
	print("[solidify] open boundary edges: %d" % boundary.size())

	# ── Build the solid: outer shell + inner shell (offset, reversed) + side walls
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var inner := func(i: int) -> Vector3: return uniq[i] - vn[i] * WALL_THICKNESS
	for t in wt:
		st.add_vertex(uniq[t[0]]); st.add_vertex(uniq[t[1]]); st.add_vertex(uniq[t[2]])
	for t in wt:                                            # inner, reversed winding
		st.add_vertex(inner.call(t[0])); st.add_vertex(inner.call(t[2])); st.add_vertex(inner.call(t[1]))
	for ed in boundary:                                     # bridge the open edges
		var oa := uniq[ed[0]]; var ob := uniq[ed[1]]
		var ia : Vector3 = inner.call(ed[0]); var ib : Vector3 = inner.call(ed[1])
		st.add_vertex(oa); st.add_vertex(ob); st.add_vertex(ib)
		st.add_vertex(oa); st.add_vertex(ib); st.add_vertex(ia)
	st.generate_normals()                                   # flat per-face normals
	var mesh := st.commit()

	var err := ResourceSaver.save(mesh, OUT)
	# ALSO export a plain .obj so the result opens in any external 3D viewer
	# (Windows 3D Viewer, Blender, online glTF/obj viewers) WITHOUT Godot.
	_write_obj(mesh, OUT_OBJ)
	var dt := Time.get_ticks_msec() - t0
	print("[solidify] %s saved (err %d) — %d tris out, %.1fs" % [
		OUT, err, wt.size() * 2 + boundary.size() * 2, dt / 1000.0])
	quit(0 if err == OK else 1)

## Write an ArrayMesh surface to a standard Wavefront .obj (vertices + normals +
## triangle faces). Viewable in any external tool — the whole point: no Godot needed.
func _write_obj(m: ArrayMesh, path: String) -> void:
	var arr := m.surface_get_arrays(0)
	var vs : PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var ns : PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	var of := FileAccess.open(path, FileAccess.WRITE)
	if of == null:
		push_error("[solidify] cannot write %s" % path); return
	of.store_line("# CeDo factory — solidified, welded, %d verts. By solidify_building.gd" % vs.size())
	for v in vs:
		of.store_line("v %.4f %.4f %.4f" % [v.x, v.y, v.z])
	var has_n : bool = ns.size() == vs.size()
	if has_n:
		for n in ns:
			of.store_line("vn %.4f %.4f %.4f" % [n.x, n.y, n.z])
	# generate_normals() without index leaves the surface unindexed → 3 verts/tri.
	for i in range(0, vs.size(), 3):
		if has_n:
			of.store_line("f %d//%d %d//%d %d//%d" % [i + 1, i + 1, i + 2, i + 2, i + 3, i + 3])
		else:
			of.store_line("f %d %d %d" % [i + 1, i + 2, i + 3])
	of.close()
	print("[solidify] wrote viewable OBJ → %s" % ProjectSettings.globalize_path(path))
