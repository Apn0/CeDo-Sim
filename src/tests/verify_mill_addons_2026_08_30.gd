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
	var ch_hx := hw * 0.55

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

	# ── 2026-08-30 operator corrections ──────────────────────────────────────
	# (a) the rust drum is a mobile FAN parked on the deck, not a flywheel keyed
	#     to the shaft; (b) the yellow object is a flat PLATE, not a chute that
	#     hangs through the deck; (c) the tool board's position 2 now carries the
	#     real second (smaller) wrench, not just paint.
	# X upper bound is -0.81, not -0.78: the cutting chamber's split-line flange
	# carries bolt heads whose centres sit exactly on x = -ch_hx = -0.792, and a
	# looser window swept one of them into the fan's bounding box and reported a
	# clearance failure that belonged to the chamber, not to the fan.
	var fan := _region(boxes, -hw - 0.02, -0.81, deck_top - 0.02, 2.90, -1.05, -0.05)
	_check("fan parts present on the deck", fan.size() >= 12, "found %d" % fan.size())
	var fan_aabb := _union(fan)
	print("[ADDONS] fan union pos=%s size=%s" % [str(fan_aabb.position), str(fan_aabb.size)])
	_check("fan sits ON the grating, not floating",
		fan_aabb.position.y >= deck_top - 0.02 and fan_aabb.position.y < deck_top + 0.06,
		"fan minY %.4f vs deck_top %.4f" % [fan_aabb.position.y, deck_top])
	_check("fan stays inside the deck footprint in X",
		fan_aabb.position.x > -hw - 0.02,
		"fan minX %.4f vs deck edge %.4f" % [fan_aabb.position.x, -hw])
	_check("fan clears the cutting chamber in X",
		fan_aabb.position.x + fan_aabb.size.x < -ch_hx,
		"fan maxX %.4f vs chamber %.4f" % [fan_aabb.position.x + fan_aabb.size.x, -ch_hx])

	# The old flywheel was a 1.248 m DISC on the rotor axis at x -1.06. Keying
	# this to a bounding box was wrong -- the first version caught the -X top
	# rail, whose centre sits exactly on y 2.95. Key it to the thing that
	# actually distinguishes a flywheel instead: sheer size. Nothing legitimate
	# in that strip is over 0.9 m tall (rails are 0.04, the fan drum 0.50), so a
	# tall part there means the disc came back.
	var fly_ghost: Array = []
	for fb in boxes:
		var fa: AABB = fb
		var fc := fa.position + fa.size * 0.5
		# -hw + 0.05, not -hw: the railing posts stand ON the -X plane and are
		# 1.05 m tall, so the looser bound flagged a post as a returning flywheel.
		if fc.x > -hw + 0.05 and fc.x < -ch_hx and fc.z > -0.60 and fc.z < 0.60 \
				and fa.size.y > 0.90:
			fly_ghost.append(fa)
	_check("the invented flywheel disc is GONE (no tall part left on the -X rotor axis)",
		fly_ghost.size() == 0, "%d oversized part(s) still there" % fly_ghost.size())

	# The old chute was a _flare4 descending to deck_top - 0.78. A plate does not.
	var plate := _region(boxes, -1.25, 1.25, deck_top - 0.90, deck_top + 1.30, 1.05, 1.45)
	_check("yellow plate parts present", plate.size() >= 2, "found %d" % plate.size())
	var plate_aabb := _union(plate)
	print("[ADDONS] plate union pos=%s size=%s" % [str(plate_aabb.position), str(plate_aabb.size)])
	_check("the plate stands ON the deck, nothing hangs through it any more",
		plate_aabb.position.y > deck_top - 0.06,
		"plate minY %.4f vs deck_top %.4f" % [plate_aabb.position.y, deck_top])
	_check("the plate is FLAT, not a converging chute (thin in Z)",
		plate_aabb.size.z < 0.30,
		"plate Z depth %.4f" % plate_aabb.size.z)

	# Position 2 on the tool board: real tool geometry proud of the paint plane.
	var tb_x2 := -hw + 0.03
	var paint_plane := tb_x2 + 0.0125 + 0.002
	var t2_tools: Array = []
	for b in boxes:
		var a: AABB = b
		var c := a.position + a.size * 0.5
		# The upper X bound is essential. Without it this swept in the STAIR's
		# posts once the stair moved to the +X face — they sit at z ~ 1.0 and
		# passed every other term, which made the wrench measure 2.43 m tall.
		if c.x > paint_plane + 0.008 and c.x < paint_plane + 0.08 \
				and c.z > 0.88 and c.z < 1.01 \
				and c.y > deck_top and c.y < 3.0:
			t2_tools.append(a)
	_check("position 2 now carries the real second wrench, not only paint",
		t2_tools.size() >= 4, "found %d tool part(s) proud of the board" % t2_tools.size())
	var t2_aabb := _union(t2_tools)
	var t1_tools: Array = []
	for b2 in boxes:
		var a2: AABB = b2
		var c2 := a2.position + a2.size * 0.5
		if c2.x > paint_plane + 0.008 and c2.x < paint_plane + 0.08 \
				and c2.z > 0.49 and c2.z < 0.63 \
				and c2.y > deck_top and c2.y < 3.0:
			t1_tools.append(a2)
	var t1_aabb := _union(t1_tools)
	print("[ADDONS] wrench1 h=%.4f   wrench2 h=%.4f" % [t1_aabb.size.y, t2_aabb.size.y])
	# Lower floor is 0.30, not 0.20. Godot CLAMPS degenerate BoxMesh dimensions,
	# so scaling the wrench to zero still measures 0.219 m and squeaked past a
	# 0.20 floor — the assertion looked live but could not catch a collapsed
	# tool. Real value is 0.394 m, so 0.30 keeps margin both ways.
	_check("the second wrench is SMALLER than the first, as the operator described",
		t2_aabb.size.y < t1_aabb.size.y - 0.05 and t2_aabb.size.y > 0.30,
		"wrench2 %.4f m vs wrench1 %.4f m" % [t2_aabb.size.y, t1_aabb.size.y])

	# ── Stair relocated beside the ladder (OPERATOR 2026-08-30) ──────────────
	# `_caged_ladder` sits at (hw+0.10, 0, hd*0.35) and its hoops reach 0.484 m,
	# so it owns X [1.056, 2.024] and Z [0.394, 1.362]. The flight must share the
	# +X aisle with it without touching it.
	var ladder_foot := Vector3(hw + 0.10, 0.0, hd * 0.35)
	var steps: Array = []
	for sb in boxes:
		var sa: AABB = sb
		var sc := sa.position + sa.size * 0.5
		# Treads only: outboard of the deck, below deck height, thin, and wide
		# enough to be a tread rather than a rail.
		if sc.x > hw + 0.05 and sc.y > 0.05 and sc.y < deck_y + 0.02 				and sa.size.y < 0.12 and sa.size.z > 0.40:
			steps.append(sa)
	_check("stair treads found outboard of the +X deck edge",
		steps.size() >= 6, "found %d" % steps.size())
	var st_aabb := _union(steps)
	print("[ADDONS] stair union pos=%s size=%s" % [str(st_aabb.position), str(st_aabb.size)])
	_check("the stair is on the SAME face as the ladder (+X), not the -Z face",
		st_aabb.position.x > hw,
		"stair minX %.4f vs deck edge %.4f" % [st_aabb.position.x, hw])
	_check("the stair tops out flush with the deck edge",
		absf(st_aabb.position.x - hw) < 0.20,
		"stair minX %.4f vs hw %.4f" % [st_aabb.position.x, hw])
	var foot := Vector3(st_aabb.position.x + st_aabb.size.x, 0.0,
		st_aabb.position.z + st_aabb.size.z * 0.5)
	var gap := Vector2(foot.x - ladder_foot.x, foot.z - ladder_foot.z).length()
	_check("the stair foot is beside the ladder foot (within 2.6 m)",
		gap < 2.6, "%.2f m apart" % gap)
	# Ladder cage volume; the flight must not intersect it.
	var cage := AABB(Vector3(ladder_foot.x - 0.484, 0.0, ladder_foot.z - 0.154),
		Vector3(0.968, deck_y + 0.9, 0.968))
	_check("the stair does not intersect the caged ladder",
		not st_aabb.intersects(cage),
		"stair %s vs cage %s" % [str(st_aabb), str(cage)])

	# The -Z railing used to be hand-built in two segments around a gap. With the
	# stair moved it is one continuous run again, so no rail should stop short.
	var mid_rail: Array = []
	for rb in boxes:
		var ra: AABB = rb
		var rc := ra.position + ra.size * 0.5
		# The Y band matters. The deck's -Z PERIMETER BEAM also sits on z = -hd,
		# is wider than 0.5 m and is thin, so without it this check stayed green
		# even with the entire -Z railing deleted — it was measuring the beam.
		if absf(rc.z + hd) < 0.05 and ra.size.x > 0.5 and ra.size.y < 0.12 \
				and rc.y > deck_top + 0.30:
			mid_rail.append(ra)
	var rail_span := _union(mid_rail)
	_check("the -Z railing is CONTINUOUS again (no leftover stair gap)",
		mid_rail.size() > 0 and rail_span.size.x > hw * 2.0 - 0.10,
		"%d rail run(s), widest span %.4f vs deck %.4f" % [mid_rail.size(), rail_span.size.x, hw * 2.0])

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
