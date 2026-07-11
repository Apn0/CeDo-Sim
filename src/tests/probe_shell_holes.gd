extends Node3D
## Find the OPEN BOUNDARY EDGES of the shell mesh near the marked region
## (#wall-fill). An edge used by only ONE triangle is a hole rim (a properly
## closed solid has every edge shared by 2 triangles). This locates exactly where
## the wall is missing — the rim the fill must close — instead of guessing from
## the operator's clicks.
##
##   godot --headless --main-scene res://src/tests/probe_shell_holes.tscn

const TEST_SLOT := "new_building_test"
const BX := Vector2(-268.0, -245.0)
const BY := Vector2(-9.5, 1.0)
const BZ := Vector2(103.0, 126.0)

func _vkey(v: Vector3) -> String:
	return "%d,%d,%d" % [roundi(v.x * 50.0), roundi(v.y * 50.0), roundi(v.z * 50.0)]  # 2 cm quantise

func _ready() -> void:
	print("=== SHELL OPEN-BOUNDARY (hole rim) ===")
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
		print("FATAL: ShellMesh missing"); get_tree().quit(1); return
	var xf : Transform3D = shell.global_transform
	var faces : PackedVector3Array = shell.mesh.get_faces()

	# Count each edge by quantised endpoint keys; store one representative world seg.
	var ecount : Dictionary = {}
	var eseg : Dictionary = {}
	for i in range(0, faces.size(), 3):
		var v := [xf * faces[i], xf * faces[i + 1], xf * faces[i + 2]]
		for e in [[0, 1], [1, 2], [2, 0]]:
			var ka := _vkey(v[e[0]])
			var kb := _vkey(v[e[1]])
			var key : String = ka + "|" + kb if ka < kb else kb + "|" + ka
			ecount[key] = int(ecount.get(key, 0)) + 1
			if not eseg.has(key):
				eseg[key] = [v[e[0]], v[e[1]]]

	# Boundary edges (count==1) whose midpoint sits in the region box.
	var rim : Array = []
	for key in ecount.keys():
		if int(ecount[key]) != 1:
			continue
		var seg : Array = eseg[key]
		var mid : Vector3 = (seg[0] + seg[1]) * 0.5
		if mid.x < BX.x or mid.x > BX.y: continue
		if mid.y < BY.x or mid.y > BY.y: continue
		if mid.z < BZ.x or mid.z > BZ.y: continue
		rim.append(seg)

	print("floor=%.2f  total tris=%d  region open-boundary edges=%d" % [floor_y, faces.size() / 3, rim.size()])
	if rim.is_empty():
		print("  (no open rim in region — shell is watertight here; the 'gap' is a thin/low-res surface, not a hole)")
	# Extent of the rim + list the segments (endpoints, height above floor).
	var mn := Vector3(1e9, 1e9, 1e9)
	var mx := Vector3(-1e9, -1e9, -1e9)
	for seg in rim:
		for p in seg:
			mn = Vector3(minf(mn.x, p.x), minf(mn.y, p.y), minf(mn.z, p.z))
			mx = Vector3(maxf(mx.x, p.x), maxf(mx.y, p.y), maxf(mx.z, p.z))
	if not rim.is_empty():
		print("  rim extent: X %.1f..%.1f  Y %.1f..%.1f (%.1f..%.1f m up)  Z %.1f..%.1f" % [
			mn.x, mx.x, mn.y, mx.y, mn.y - floor_y, mx.y - floor_y, mn.z, mx.z])
		var shown := 0
		for seg in rim:
			var a : Vector3 = seg[0]
			var b : Vector3 = seg[1]
			print("    edge (%.1f,%.1f,%.1f)->(%.1f,%.1f,%.1f)  len %.2f  %.1f-%.1f m up" % [
				a.x, a.y, a.z, b.x, b.y, b.z, a.distance_to(b), a.y - floor_y, b.y - floor_y])
			shown += 1
			if shown >= 30:
				print("    ... (%d more)" % (rim.size() - shown)); break
	get_tree().quit(0)
