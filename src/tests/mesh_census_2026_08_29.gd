extends Node3D
## TEMPORARY research tool (2026-08-29, drum-standard investigation).
## Builds EVERY catalog placeable via _build_model() directly — BYPASSING
## StaticMerge (PlaceableCatalog.gd:1512), which collapses ~30-80 authored
## _box/_cyl parts into one mesh per material and therefore destroys any
## "how many parts did the author actually model" signal.
## Prints: id, authored MeshInstance3D parts, total surfaces, total vertices.
## Regex-counting `_box(`/`_cyl(` call sites UNDERCOUNTS loops (the drum's 16
## flange bolts are ONE call site but 16 meshes), so this is the honest number.
## Run:  <godot> --headless --path . res://src/tests/mesh_census_2026_08_29.tscn

func _count(n: Node, acc: Dictionary) -> void:
	if n is MeshInstance3D:
		acc["meshes"] = int(acc["meshes"]) + 1
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			acc["surfaces"] = int(acc["surfaces"]) + mi.mesh.get_surface_count()
			acc["verts"] = int(acc["verts"]) + mi.mesh.get_faces().size()
	for c in n.get_children():
		_count(c, acc)

func _ready() -> void:
	print("id\tcategory\tparts\tsurfaces\tverts")
	for it in PlaceableCatalog.items():
		var pid := String(it.get("id", ""))
		if pid == "":
			continue
		var cat := String(it.get("category", ""))
		var sz : Vector3 = it.get("size", Vector3.ONE)
		var col : Color = it.get("color", Color.WHITE)
		var root := Node3D.new()
		add_child(root)
		PlaceableCatalog._build_model(root, pid, cat, sz, col, false)
		var acc := {"meshes": 0, "surfaces": 0, "verts": 0}
		_count(root, acc)
		print("%s\t%s\t%d\t%d\t%d" % [pid, cat, acc["meshes"], acc["surfaces"], acc["verts"]])
		root.queue_free()
		await get_tree().process_frame
	print("[CENSUS] done")
	get_tree().quit(0)
