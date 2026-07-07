extends Node3D
## Headless proof for the F10 in-world point marker tool (MarkerTool.gd).
##
## Covers the two things the operator actually relies on:
##   1. exact placement — the point recorded is the point they aimed at, and the
##      snap modes (grid / edge-vertex) move it where they say they do;
##   2. persistence — exiting writes markers.json with every point so the
##      developer can read the precise coordinates.
##
##   godot --headless --path <proj> --main-scene res://src/tests/test_marker_tool.tscn

const MarkerToolScript = preload("res://src/scenes/player/MarkerTool.gd")

var _fails : int = 0

func _check(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
	else:
		print("  FAIL  : %s" % msg)
		_fails += 1

func _ready() -> void:
	print("=== MarkerTool headless proof ===")
	_test_pure_math()
	_test_place_and_persist()
	await _test_live_raycast()
	print("Result: %s" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
	get_tree().quit(0 if _fails == 0 else 1)

# ── pure snap math ────────────────────────────────────────────────────────────
func _test_pure_math() -> void:
	print("[pure]")
	var g := MarkerToolScript.snap_to_grid(Vector3(1.04, 2.07, -0.03), 0.1)
	_check(g.is_equal_approx(Vector3(1.0, 2.1, 0.0)), "grid snap rounds to 10 cm  → %s" % g)

	var verts := PackedVector3Array([Vector3(0,0,0), Vector3(1,0,0), Vector3(0,1,0)])
	var near := MarkerToolScript.nearest_vertex(Vector3(0.9, 0.05, 0.0), verts, 0.35)
	_check(near["found"] and (near["point"] as Vector3).is_equal_approx(Vector3(1,0,0)),
		"nearest_vertex picks the (1,0,0) corner within 35 cm")
	var far := MarkerToolScript.nearest_vertex(Vector3(5,5,5), verts, 0.35)
	_check(not far["found"], "nearest_vertex refuses a vertex beyond the threshold")

# ── place / clear / json / exit-save (no physics) ─────────────────────────────
func _test_place_and_persist() -> void:
	print("[place+persist]")
	var mt : Node3D = MarkerToolScript.new()
	add_child(mt)   # runs _ready → builds _placed_root

	mt.place_at(Vector3(1.5, 0.25, -3.0), {"placeable_id": "silo_a", "hit_name": "Body"})
	mt.place_at(Vector3(-2.0, 0.0, 4.0), {"hit_name": "Wall"})
	_check(mt.markers.size() == 2, "two markers recorded")
	_check(mt.get_node("PlacedMarkers").get_child_count() == 2, "two orb nodes in the world")
	var w0 : Array = mt.markers[0]["world_point"]
	_check(abs(w0[0] - 1.5) < 1e-4 and abs(w0[2] + 3.0) < 1e-4, "marker #1 stored at the exact point")

	var payload : Dictionary = mt._build_markers_json()
	_check(payload["count"] == 2, "json count == 2")
	_check(not payload["markers"][0].has("node"), "json strips the non-serialisable node ref")
	_check(payload["markers"][0].has("world_point"), "json keeps world_point")

	var dir : String = mt.exit_and_save()
	_check(dir != "", "exit_and_save returned a directory")
	var jpath := "user://feedback/%s/markers.json" % dir.get_file()
	_check(FileAccess.file_exists(jpath), "markers.json written to %s" % jpath)
	if FileAccess.file_exists(jpath):
		var txt := FileAccess.get_file_as_string(jpath)
		var parsed = JSON.parse_string(txt)
		_check(parsed != null and int(parsed.get("count", -1)) == 2, "markers.json parses back with count 2")
	# also proves the legacy "check feedback" reader still finds a context.json
	var cpath := "user://feedback/%s/context.json" % dir.get_file()
	_check(FileAccess.file_exists(cpath), "context.json superset written for the feedback pipeline")

	var proot : Node = mt.get_node("PlacedMarkers")
	mt.clear()
	_check(mt.markers.size() == 0, "H clears the marker list")
	# queue_free() is deferred — the orbs are gone this frame in intent, freed next.
	var all_queued := true
	for c in proot.get_children():
		if not (c as Node).is_queued_for_deletion():
			all_queued = false
	_check(proot.get_child_count() == 0 or all_queued, "H frees the orb nodes")
	mt.queue_free()

# ── live crosshair raycast + edge snap against a real body ─────────────────────
func _test_live_raycast() -> void:
	print("[live ray]")
	# A 2 m box centred at (0,0,-5): spans z ∈ [-6,-4], corners at ±1.
	var body := StaticBody3D.new()
	body.position = Vector3(0, 0, -5)
	body.add_to_group("placed_object")
	body.set_meta("placeable_id", "test_box")
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 2, 2)
	shape.shape = box
	body.add_child(shape)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2, 2, 2)
	mi.mesh = bm
	body.add_child(mi)
	add_child(body)

	var cam := Camera3D.new()   # at origin, looking down -Z (default basis)
	add_child(cam)

	await get_tree().physics_frame
	await get_tree().physics_frame

	var mt : Node3D = MarkerToolScript.new()
	add_child(mt)
	mt.begin(cam, [])

	# OFF: raw hit is the front face at z = -4, dead centre.
	mt.snap = MarkerToolScript.Snap.OFF
	var r : Dictionary = mt._resolve_point()
	_check(r.get("hit", false), "crosshair ray hits the box")
	if r.get("hit", false):
		var p : Vector3 = r["point"]
		_check(abs(p.z + 4.0) < 0.05 and abs(p.x) < 0.05 and abs(p.y) < 0.05,
			"hit point is the front face centre (0,0,-4) → %s" % p)
		_check(String(r["ctx"].get("placeable_id", "")) == "test_box",
			"context resolved the placed_object placeable_id")

	# GRID: point lands on the 10 cm lattice.
	mt.snap = MarkerToolScript.Snap.GRID
	var rg : Dictionary = mt._resolve_point()
	if rg.get("hit", false):
		var pg : Vector3 = rg["point"]
		var on_grid : bool = abs(pg.x - snappedf(pg.x, 0.1)) < 1e-4 and abs(pg.z - snappedf(pg.z, 0.1)) < 1e-4
		_check(on_grid and rg.get("snapped", false), "grid snap lands on the 10 cm lattice → %s" % pg)

	# EDGE: the hit object's mesh vertices are reachable and snap to a real corner.
	var verts : PackedVector3Array = mt._object_world_vertices(body)
	_check(verts.size() > 0, "edge snap reads %d mesh vertices off the box" % verts.size())
	var e : Dictionary = mt._edge_snap({"collider": body}, Vector3(0.92, 0.9, -4.03))
	_check(e["snapped"] and (e["point"] as Vector3).is_equal_approx(Vector3(1, 1, -4)),
		"edge snap pulls a near point onto the exact corner (1,1,-4) → %s" % e["point"])

	mt.queue_free()
	body.queue_free()
	cam.queue_free()
