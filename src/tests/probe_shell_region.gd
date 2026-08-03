extends Node3D
## Read the REAL shell geometry around the operator's marked region (#wall-fill).
## Boots MainWorld, pulls ShellMesh triangles in a box around the marks, and
## reports the wall structure so the missing wall can be filled to MATCH the
## surrounding build (thickness, where the wall stops, how it meets the roof, the
## actual gap) — instead of naively connecting the clicked points.
##
##   godot --headless --main-scene res://src/tests/probe_shell_region.tscn

const TEST_SLOT := "new_building_test"
# Box around the marks (they span X[-260.5,-253.1] Y[-4.2,-1.9] Z[110.2,119.3]).
# Padded to catch the surrounding wall + roof + floor + the gap.
const BX := Vector2(-268.0, -245.0)
const BY := Vector2(-9.5, 1.0)
const BZ := Vector2(103.0, 126.0)

func _ready() -> void:
	print("=== SHELL REGION GEOMETRY ===")
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(70):
		await get_tree().process_frame

	var floor_y : float = Plant.floor_top_y() if Plant.is_initialized() else -9.0
	var shell := world.find_child("ShellMesh", true, false) as MeshInstance3D
	if shell == null or shell.mesh == null:
		print("FATAL: ShellMesh/mesh not found"); get_tree().quit(1); return
	var xf : Transform3D = shell.global_transform
	var faces : PackedVector3Array = shell.mesh.get_faces()
	print("floor_top_y=%.2f   shell total triangles=%d   region box X%s Y%s Z%s" % [
		floor_y, faces.size() / 3, str(BX), str(BY), str(BZ)])

	var wall : Array = []   # {cen, n}
	var roof : Array = []
	var flr  : Array = []
	for i in range(0, faces.size(), 3):
		var a : Vector3 = xf * faces[i]
		var b : Vector3 = xf * faces[i + 1]
		var c : Vector3 = xf * faces[i + 2]
		var cen : Vector3 = (a + b + c) / 3.0
		if cen.x < BX.x or cen.x > BX.y: continue
		if cen.y < BY.x or cen.y > BY.y: continue
		if cen.z < BZ.x or cen.z > BZ.y: continue
		var n : Vector3 = (b - a).cross(c - a).normalized()
		var rec := {"cen": cen, "n": n}
		if absf(n.y) >= 0.5:
			if n.y < 0.0: roof.append(rec)
			else: flr.append(rec)
		else:
			wall.append(rec)

	print("\nin-region triangles: WALL=%d  ROOF(down)=%d  FLOOR(up)=%d" % [wall.size(), roof.size(), flr.size()])
	_report("WALL", wall, floor_y)
	_report("ROOF", roof, floor_y)
	_report("FLOOR", flr, floor_y)

	# Wall thickness + facing: bucket wall tris by rounded horizontal normal, then
	# by plane offset (normal·centroid). Two offsets on the same normal = a wall
	# with a front + back face; their spacing = the wall thickness.
	print("\n-- WALL planes (facing → plane offsets along normal; 2 offsets = thickness) --")
	var buckets : Dictionary = {}
	for w in wall:
		var n : Vector3 = w["n"]
		var key := "%.1f,%.1f" % [n.x, n.z]
		var off : float = n.dot(w["cen"])
		if not buckets.has(key): buckets[key] = []
		buckets[key].append(off)
	for key in buckets.keys():
		var offs : Array = buckets[key]
		offs.sort()
		var lo : float = offs[0]
		var hi : float = offs[offs.size() - 1]
		print("   normal(x,z)=(%s)  count=%d  offset range=%.2f..%.2f  (span=%.2f m ~ thickness/extent)" % [
			key, offs.size(), lo, hi, hi - lo])

	# Vertical profile of the WALL along Y: where does wall geometry exist vs a gap?
	print("\n-- WALL vertical coverage (0.5 m bins, # = has wall tri) --")
	var bins : Dictionary = {}
	for w in wall:
		var by : int = int(floor((w["cen"].y - floor_y) / 0.5))
		bins[by] = int(bins.get(by, 0)) + 1
	for b in range(0, 18):
		var h0 : float = floor_y + b * 0.5
		var cnt : int = int(bins.get(b, 0))
		print("   %.1f-%.1f m: %s (%d)" % [h0 - floor_y, h0 - floor_y + 0.5, "#".repeat(min(cnt, 40)), cnt])

	get_tree().quit(0)

func _report(label: String, arr: Array, floor_y: float) -> void:
	if arr.is_empty():
		print("  %s: none in region" % label); return
	var ymin := 1e9
	var ymax := -1e9
	for r in arr:
		ymin = minf(ymin, r["cen"].y)
		ymax = maxf(ymax, r["cen"].y)
	print("  %s: %d tris, Y %.2f..%.2f  (%.1f..%.1f m above floor)" % [
		label, arr.size(), ymin, ymax, ymin - floor_y, ymax - floor_y])
