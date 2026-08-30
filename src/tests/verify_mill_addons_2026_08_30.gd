extends Node3D
## Measures the two items added on 2026-08-30 (+BP2 cabinet, tool shadow board)
## against the mill they were added to. Builds via `_build_model()` directly, the
## same way src/tests/mesh_census_2026_08_29.gd does, so StaticMerge's bake does
## not hide loop bodies.
##
##   <godot> --path . res://src/tests/verify_mill_addons_2026_08_30.tscn --quit-after 12

const MILL_ID := "mill"

var _fail := 0
var _ok := 0

func _ready() -> void:
	var item: Dictionary = PlaceableCatalog.get_item(MILL_ID)
	if item.is_empty():
		push_error("no mill in catalog"); get_tree().quit(1); return
	var sz: Vector3 = item.get("size", Vector3.ONE)

	var root := Node3D.new()
	add_child(root)
	PlaceableCatalog._build_model(root, MILL_ID, String(item.get("category", "")), sz,
		item.get("color", Color.WHITE), false)
	var real_parts := _count(root)

	var groot := Node3D.new()
	add_child(groot)
	PlaceableCatalog._build_model(groot, MILL_ID, String(item.get("category", "")), sz,
		item.get("color", Color.WHITE), true)
	var ghost_parts := _count(groot)

	print("[ADDONS] parts real=%d ghost=%d" % [real_parts, ghost_parts])

	# Frame constants, re-derived here rather than copied from the builder.
	var deck_y := sz.y * 0.40
	var hw := sz.x * 0.40
	var hd := sz.z * 0.34
	var deck_top := deck_y + 0.01
	var ch_hz := hd * 0.50

	# --- collect world AABBs of every mesh, then bucket by region -------------
	var boxes: Array = []
	_collect(root, boxes)
	print("[ADDONS] measured %d mesh AABBs" % boxes.size())

	# +BP2 cabinet occupies X[-0.25,0.35] Z[-1.20,-0.90] on the deck.
	var cab := _region(boxes, -0.26, 0.36, deck_top - 0.02, deck_top + 0.90, -1.22, -0.88)
	_check("cabinet parts present", cab.size() >= 8, "found %d" % cab.size())
	var cab_aabb := _union(cab)
	print("[ADDONS] cabinet union pos=%s size=%s" % [str(cab_aabb.position), str(cab_aabb.size)])
	_check("cabinet stands ON the deck (base within 20 mm of grating top)",
		absf(cab_aabb.position.y - deck_top) < 0.02,
		"base %.4f vs deck_top %.4f" % [cab_aabb.position.y, deck_top])
	_check("cabinet does not reach the motor skid (X < 0.3995)",
		cab_aabb.position.x + cab_aabb.size.x < 0.3995,
		"cabinet maxX %.4f" % (cab_aabb.position.x + cab_aabb.size.x))
	_check("cabinet clears the cutting chamber (+Z face < -0.782)",
		cab_aabb.position.z + cab_aabb.size.z < -0.782,
		"cabinet maxZ %.4f" % (cab_aabb.position.z + cab_aabb.size.z))
	_check("cabinet clears the -Z railing (min Z > -1.564)",
		cab_aabb.position.z > -1.564,
		"cabinet minZ %.4f" % cab_aabb.position.z)
	_check("cabinet stays inside the deck footprint in X",
		cab_aabb.position.x > -hw and cab_aabb.position.x + cab_aabb.size.x < hw,
		"X[%.4f,%.4f] vs +-%.4f" % [cab_aabb.position.x, cab_aabb.position.x + cab_aabb.size.x, hw])

	# Tool board hangs on the -X railing plane.
	var brd := _region(boxes, -hw - 0.06, -hw + 0.10, 1.90, 3.10, 0.20, 1.30)
	_check("tool board parts present", brd.size() >= 10, "found %d" % brd.size())
	var brd_aabb := _union(brd)
	print("[ADDONS] board union pos=%s size=%s" % [str(brd_aabb.position), str(brd_aabb.size)])
	var rail_base := deck_y - 0.02
	_check("board hangs below the top rail (2.95)",
		brd_aabb.position.y + brd_aabb.size.y <= rail_base + 1.05 + 0.001,
		"board maxY %.4f vs top rail %.4f" % [brd_aabb.position.y + brd_aabb.size.y, rail_base + 1.05])
	_check("board clears the toe board (min Y > deck top)",
		brd_aabb.position.y > deck_top,
		"board minY %.4f vs %.4f" % [brd_aabb.position.y, deck_top])
	_check("board hangs INSIDE the railing (does not stick out past -hw-0.05)",
		brd_aabb.position.x > -hw - 0.05,
		"board minX %.4f vs %.4f" % [brd_aabb.position.x, -hw - 0.05])
	# A per-axis Z comparison against the chamber is meaningless here (the board
	# hangs at the railing plane, 0.6 m outside the chamber in X), so test the
	# thing that actually matters: no volume intersection with the chamber, and
	# none with the yellow near-side chute either.
	var ch_hx := hw * 0.55
	var base_y := deck_y + 0.06
	var chamber := AABB(Vector3(-ch_hx, base_y, -ch_hz),
		Vector3(ch_hx * 2.0, sz.y * 0.26, ch_hz * 2.0))
	_check("board does not intersect the cutting chamber",
		not brd_aabb.intersects(chamber),
		"board %s vs chamber %s" % [str(brd_aabb), str(chamber)])
	var yc := AABB(Vector3(-hw * 0.42 - 0.36, deck_top - 0.78, hd * 0.755 - 0.28),
		Vector3(0.72, 0.78, 0.56))
	_check("board does not intersect the yellow near-side chute",
		not brd_aabb.intersects(yc),
		"board %s vs chute %s" % [str(brd_aabb), str(yc)])

	# The removed TYPICAL box lived at X -1.1952, Z +0.8993 on the deck.
	var old_spot := _region(boxes, -1.36, -1.03, deck_top, deck_top + 0.45, 0.78, 1.02)
	_check("the invented TYPICAL control box is GONE from its old spot",
		old_spot.size() == 0, "still %d parts there" % old_spot.size())

	print("[ADDONS] RESULT: %d ok, %d fail" % [_ok, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	get_tree().quit(0 if _fail == 0 else 1)

func _check(what: String, cond: bool, detail: String) -> void:
	if cond:
		_ok += 1
		print("  ok   %s  (%s)" % [what, detail])
	else:
		_fail += 1
		printerr("  FAIL %s  (%s)" % [what, detail])

func _count(n: Node) -> int:
	var c := 1 if n is MeshInstance3D else 0
	for ch in n.get_children():
		c += _count(ch)
	return c

func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null:
			out.append(mi.global_transform * mi.mesh.get_aabb())
	for ch in n.get_children():
		_collect(ch, out)

func _region(boxes: Array, x0: float, x1: float, y0: float, y1: float,
		z0: float, z1: float) -> Array:
	var hit: Array = []
	for b in boxes:
		var a: AABB = b
		var c := a.position + a.size * 0.5
		if c.x >= x0 and c.x <= x1 and c.y >= y0 and c.y <= y1 and c.z >= z0 and c.z <= z1:
			hit.append(a)
	return hit

func _union(arr: Array) -> AABB:
	if arr.is_empty():
		return AABB()
	var u: AABB = arr[0]
	for i in range(1, arr.size()):
		u = u.merge(arr[i])
	return u
