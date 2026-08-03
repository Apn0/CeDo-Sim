extends Node3D
## Dump the real shell triangles around the marked region to JSON so they can be
## plotted to-scale (#wall-fill). No more stats-guessing — we look at the geometry.
##   godot --headless --main-scene res://src/tests/probe_shell_dump.tscn
const TEST_SLOT := "new_building_test"
const OUT := "user://shell_full_dump.json"
const BX := Vector2(-1.0e9, 1.0e9)   # whole shell now (winding-error census)
const BY := Vector2(-1.0e9, 1.0e9)
const BZ := Vector2(-1.0e9, 1.0e9)
# the operator's marks (capture 040329) that define the region of interest
const MARKS := [
	[3, -256.81, -1.90, 114.84], [4, -260.53, -4.07, 119.28], [5, -253.09, -3.97, 110.16],
]

func _ready() -> void:
	print("=== SHELL DUMP ===")
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
	var tris : Array = []
	for i in range(0, faces.size(), 3):
		var a : Vector3 = xf * faces[i]
		var b : Vector3 = xf * faces[i + 1]
		var c : Vector3 = xf * faces[i + 2]
		var cen : Vector3 = (a + b + c) / 3.0
		if cen.x < BX.x or cen.x > BX.y: continue
		if cen.y < BY.x or cen.y > BY.y: continue
		if cen.z < BZ.x or cen.z > BZ.y: continue
		var n : Vector3 = (b - a).cross(c - a).normalized()
		var cls := "wall"
		if n.y <= -0.5: cls = "roof"
		elif n.y >= 0.5: cls = "floor"
		tris.append({"a": [a.x, a.y, a.z], "b": [b.x, b.y, b.z], "c": [c.x, c.y, c.z], "cls": cls,
			"n": [n.x, n.y, n.z]})
	var data := {"floor_y": floor_y, "tris": tris, "marks": MARKS,
		"box": {"x": [BX.x, BX.y], "y": [BY.x, BY.y], "z": [BZ.x, BZ.y]}}
	var f := FileAccess.open(OUT, FileAccess.WRITE)
	f.store_string(JSON.stringify(data))
	f.close()
	print("dumped %d region triangles → %s" % [tris.size(), ProjectSettings.globalize_path(OUT)])
	get_tree().quit(0)
