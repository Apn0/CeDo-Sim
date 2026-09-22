extends Node
## LUMP CART OVERFLOW (P6, 2026-09-23) — a full Lumpenwagen overflows onto the
## floor, its fill is visible, and no lump kg vanishes.
##
##   godot --headless --path . res://src/tests/test_lump_cart_overflow.tscn
##
## Places the real "line_3b" macro (BuildMode._build_full_line — laser filter +
## its two carts) and drives the PRODUCTION purge path, LaserFilter._disc_advance(),
## against a cart filled through LumpCart.receive_lump(). No mock stands in for
## either. Then builds line_1, line_3a and line_3c too and checks every filter's
## two mound points land straight under the nozzle on the surface the cart
## stands on (floor or bordes), never on the cart — the ray in
## LaserFilter._floor_y_below() is asserted, not assumed. A first draft put a
## solid pile BESIDE the cart; its shape query found the achter side of lines 1,
## 3A and 3B entirely inside the extruder's 14 m collider, which is why the
## mound now sits at the cart and is soft.
##
## Before this change (measured 2026-09-23): receive_lump() returned at
## is_full() and dropped the kg; nothing ever read is_full(); the cart never
## showed its load (settled chunks were freed on absorption); lumps_kg_this_shift
## counted kg that existed nowhere.

const WATCHDOG_S : float = 240.0
const PURGE_G    : float = 2000.0   # front_loading_g before each _disc_advance → 2000 × 0.85 = 1.7 kg purged

var _fails : int = 0
var _oks   : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _filters() -> Array:
	return get_tree().get_nodes_in_group("laser_filter")

func _piles() -> Array:
	return get_tree().get_nodes_in_group("floor_pile")

## Wall top + plate extents read straight off the cart's collision boxes, by a
## different selection than LumpCart._measure_bucket() (tallest box's top face,
## widest box's XZ) so the heap is checked against the physics, not against itself.
func _cart_rim(cart: Node3D) -> Dictionary:
	var rim_y := -INF
	var half_w := 0.0
	var half_d := 0.0
	for c in cart.get_children():
		var cs := c as CollisionShape3D
		if cs == null or not (cs.shape is BoxShape3D):
			continue
		var sz : Vector3 = (cs.shape as BoxShape3D).size
		rim_y = maxf(rim_y, cs.position.y + sz.y * 0.5)
		half_w = maxf(half_w, absf(cs.position.x) + sz.x * 0.5)
		half_d = maxf(half_d, absf(cs.position.z) + sz.z * 0.5)
	return {"rim_y": rim_y, "half_w": half_w, "half_d": half_d}

## Bodies overlapping a cylinder (r, h) standing on `at`, minus `ignore`.
func _overlaps_at(at: Vector3, r: float, h: float, ignore: Array) -> Array:
	var space := get_viewport().world_3d.direct_space_state
	var q := PhysicsShapeQueryParameters3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = r
	cyl.height = h
	q.shape = cyl
	q.transform = Transform3D(Basis(), at + Vector3(0.0, h * 0.5 + 0.02, 0.0))
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var out : Array = []
	for hit in space.intersect_shape(q, 64):
		var col = hit.get("collider")
		if col == null or ignore.has(col):
			continue
		var owner_name := String(col.name)
		var pnode : Node = (col as Node).get_parent() if col is Node else null
		if pnode != null:
			owner_name = "%s/%s" % [pnode.name, col.name]
		if not out.has(owner_name):
			out.append(owner_name)
	return out

func _run() -> void:
	print("[TEST] lump cart overflow")
	# A floor: BuildMode alone places no ground, and a RigidBody cart with
	# nothing under it sinks ~7 cm in the frames this suite runs (measured — the
	# voor carts, which unlike the achter carts stand on no bordes). The real
	# world has a floor; give the fixture one so the mound's ray and the carts
	# agree on where the ground is.
	var floor_body := StaticBody3D.new()
	floor_body.name = "TestFloor"
	floor_body.collision_layer = 1
	var floor_col := CollisionShape3D.new()
	var floor_box := BoxShape3D.new()
	floor_box.size = Vector3(600.0, 0.2, 600.0)
	floor_col.shape = floor_box
	floor_col.position = Vector3(0.0, -0.1, 0.0)
	floor_body.add_child(floor_col)
	add_child(floor_body)
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	# LaserFilter._physics_process binds its carts on the first physics tick
	# while unbound; give it a few.
	for _i in 4:
		await get_tree().physics_frame

	var filters := _filters()
	_check(filters.size() == 1, "line_3b placed exactly one laser filter (%d)" % filters.size())
	if filters.size() != 1:
		_finish(); return
	var lf : LaserFilter = filters[0] as LaserFilter
	var achter = lf.lump_cart_achter
	var voor   = lf.lump_cart_voor
	_check(achter != null and is_instance_valid(achter), "achter nozzle has a bound cart")
	_check(voor != null and is_instance_valid(voor), "voor nozzle has a bound cart")
	if achter == null or voor == null:
		_finish(); return
	var ca : LumpCart = achter as LumpCart
	var cv : LumpCart = voor as LumpCart

	# ── S1: the bucket was measured from the cart's own collision boxes ──
	var bucket : Dictionary = ca.get("_bucket")
	_check(not bucket.is_empty(), "S1 cart measured its bucket from its collision shapes: %s" % str(bucket))
	var rim := _cart_rim(ca)
	if bucket.is_empty():
		_finish(); return
	var heap : MeshInstance3D = ca.get_node_or_null("LumpHeap") as MeshInstance3D
	_check(heap != null and not heap.visible, "S1 empty cart: heap node exists and is hidden")

	# ── S2: fill through receive_lump — returns refused kg, heap tracks the load ──
	var r1 : float = ca.receive_lump(45.0)
	_check(r1 == 0.0 and is_equal_approx(ca.lumps_kg, 45.0), "S2 receive_lump(45) → 0 refused, cart holds 45 kg")
	var h_half : float = ca.heap_height_m()
	_check(heap.visible and absf(h_half - 0.5 * float(bucket["h_max"])) < 1.0e-4,
		"S2 heap at half load is half the wall height (%.3f of %.3f m)" % [h_half, float(bucket["h_max"])])
	var r2 : float = ca.receive_lump(45.0)
	_check(r2 == 0.0 and ca.is_full(), "S2 receive_lump(45) again → 90 kg, is_full()")
	var top_y : float = heap.position.y + (heap.mesh as BoxMesh).size.y * 0.5
	_check(absf(top_y - float(rim["rim_y"])) < 0.005,
		"S2 at FULL_THRESHOLD the heap top sits on the wall top (%.4f vs rim %.4f m)" % [top_y, float(rim["rim_y"])])
	var hs : Vector3 = (heap.mesh as BoxMesh).size
	_check(hs.x * 0.5 < float(rim["half_w"]) and hs.z * 0.5 < float(rim["half_d"]),
		"S2 heap footprint inside the walls (%.3f×%.3f m in %.3f×%.3f m)" % [hs.x, hs.z, 2.0 * float(rim["half_w"]), 2.0 * float(rim["half_d"])])
	var r3 : float = ca.receive_lump(15.0)
	_check(absf(r3 - 5.0) < 1.0e-6 and is_equal_approx(ca.lumps_kg, LumpCart.CAPACITY_KG),
		"S2 receive_lump(15) at 90 kg → accepts 10 to CAPACITY (100), refuses %.3f kg" % r3)
	var h_cap : float = ca.heap_height_m()
	_check(h_cap > float(bucket["h_max"]) and absf(h_cap - float(bucket["h_max"]) * LumpCart.CAPACITY_KG / LumpCart.FULL_THRESHOLD_KG) < 1.0e-4,
		"S2 at CAPACITY the heap stands over the rim (%.3f > %.3f m)" % [h_cap, float(bucket["h_max"])])
	var r4 : float = ca.receive_lump(1.0)
	_check(absf(r4 - 1.0) < 1.0e-9 and is_equal_approx(ca.lumps_kg, LumpCart.CAPACITY_KG),
		"S2 receive_lump(1) at CAPACITY → all 1.0 kg refused, cart unchanged")
	_check(ca.heap_hot_fraction() > 0.99, "S2 a fresh load reads hot (hot fraction %.2f)" % ca.heap_hot_fraction())

	# ── S3: PRODUCTION purge into a full achter cart → floor pile beside it ──
	_check(_piles().is_empty(), "S3 no FloorPile exists before the first purge")
	lf.front_loading_g = PURGE_G
	lf.back_loading_g = 0.0
	var shift_0 : float = lf.lumps_kg_this_shift
	lf.call("_disc_advance")
	var purged : float = lf.lumps_kg_this_shift - shift_0
	_check(absf(purged - PURGE_G * 0.001 * lf.ROTATION_PURGE_FRACTION) < 1.0e-6,
		"S3 one advance purged %.3f kg (%.0f g × %.2f)" % [purged, PURGE_G, lf.ROTATION_PURGE_FRACTION])
	var share : float = purged * 0.5
	_check(is_equal_approx(ca.lumps_kg, LumpCart.CAPACITY_KG), "S3 full achter cart took nothing (still %.1f kg)" % ca.lumps_kg)
	_check(absf(cv.lumps_kg - share) < 1.0e-6, "S3 voor cart took its half share (%.3f kg)" % cv.lumps_kg)
	var piles := _piles()
	_check(piles.size() == 1, "S3 exactly one FloorPile spawned (%d)" % piles.size())
	if piles.is_empty():
		_finish(); return
	var pile : FloorPile = piles[0] as FloorPile
	_check(absf(pile.mass_kg - share) < 1.0e-6, "S3 the pile holds the refused half share (%.3f kg)" % pile.mass_kg)
	_check(absf(lf.lumps_kg_on_floor - share) < 1.0e-6 and lf.lumps_kg_lost == 0.0,
		"S3 filter counters: on_floor %.3f kg, lost %.3f kg" % [lf.lumps_kg_on_floor, lf.lumps_kg_lost])
	_check(pile.get_parent() != null and pile.get_parent() != lf,
		"S3 pile parented beside the filter (under '%s'), not inside it" % (pile.get_parent().name if pile.get_parent() != null else "<none>"))

	# ── S4: the mound sits at the cart's spot under the nozzle, on the floor, and is SOFT ──
	var pa : Vector3 = pile.global_position
	var cart_pos : Vector3 = (achter as Node3D).global_position
	var ea : Vector3 = lf.eject_global_achter()
	var dxz_nozzle : float = Vector2(pa.x - ea.x, pa.z - ea.z).length()
	_check(dxz_nozzle < 0.05, "S4 mound centred under the achter nozzle (XZ off by %.3f m)" % dxz_nozzle)
	_check(absf(pa.y - cart_pos.y) < 0.05,
		"S4 mound on the surface the cart stands on, not on the cart (pile y %.3f, cart base y %.3f)" % [pa.y, cart_pos.y])
	_check(pile.solid == false, "S4 the mound is soft (solid == false) — a collider here would eject the RigidBody cart")
	var pcol : CollisionShape3D = pile.get("_col") as CollisionShape3D
	_check(pcol != null and pcol.disabled, "S4 the mound's collider stays disabled while it holds %.3f kg" % pile.mass_kg)
	var overl := _overlaps_at(pa, 0.3, 0.2, [pile.get("_body"), achter, voor])
	_check(overl.is_empty(), "S4 nothing but the cart stands where the mound is (%s)" % str(overl))

	# ── S5: a second purge reuses the same pile ──
	lf.front_loading_g = PURGE_G
	lf.call("_disc_advance")
	_check(_piles().size() == 1, "S5 second purge reused the pile (%d piles)" % _piles().size())
	_check(absf(pile.mass_kg - 2.0 * share) < 1.0e-6, "S5 pile now holds both refused shares (%.3f kg)" % pile.mass_kg)

	# ── S6: a full cart no longer swallows settled chunks ──
	var chunk : RigidBody3D = LaserFilter.make_lump_chunk(0.10, StandardMaterial3D.new())
	chunk.freeze = true
	get_tree().root.add_child(chunk)
	chunk.global_position = cart_pos + Vector3(0.0, 0.5, 0.0)
	lf.get("_live_chunks").append(chunk)
	lf.call("_absorb_settled_chunks", 2.0)
	_check(is_instance_valid(chunk) and not chunk.is_queued_for_deletion(),
		"S6 chunk resting in the FULL cart is kept as visible overflow")
	var dumped : float = ca.empty()
	_check(is_equal_approx(dumped, LumpCart.CAPACITY_KG) and not heap.visible, "S6 empty() returns %.1f kg and hides the heap" % dumped)
	lf.call("_absorb_settled_chunks", 2.0)
	_check(chunk.is_queued_for_deletion(), "S6 the same chunk is absorbed once the cart is emptied")

	# ── S7: no cart parked at all → the whole purge goes to the floor ──
	(achter as Node3D).global_position += Vector3(0.0, 0.0, 60.0)
	(voor as Node3D).global_position += Vector3(0.0, 0.0, 60.0)
	lf.set("_cart_recheck_t", 100.0)
	for _i in 3:
		await get_tree().physics_frame
	_check(lf.lump_cart_achter == null and lf.lump_cart_voor == null, "S7 both carts unbound after moving away")
	_check(lf.call("_active_channels") == [0], "S7 with no cart the achter channel alone stays active")
	var pile_before : float = pile.mass_kg
	lf.front_loading_g = PURGE_G
	lf.call("_disc_advance")
	_check(absf(pile.mass_kg - pile_before - purged) < 1.0e-6,
		"S7 no cart: the full %.3f kg purge lands on the achter pile (%.3f → %.3f kg)" % [purged, pile_before, pile.mass_kg])

	# ── S8: conservation — every kg the scraper shed this shift exists somewhere ──
	var shed : float = lf.lumps_kg_this_shift - shift_0
	var held : float = cv.lumps_kg + pile.mass_kg + lf.lumps_kg_lost
	_check(absf(held - shed) < 1.0e-6,
		"S8 shed %.3f kg == voor cart %.3f + floor %.3f + lost %.3f" % [shed, cv.lumps_kg, pile.mass_kg, lf.lumps_kg_lost])

	# ── S9: spill points clear of every machine on all four extruder lines ──
	bm.call("_build_full_line", "line_1",  Vector3(0.0, 0.0, 150.0), 0.0)
	bm.call("_build_full_line", "line_3a", Vector3(150.0, 0.0, 0.0), 0.0)
	bm.call("_build_full_line", "line_3c", Vector3(150.0, 0.0, 150.0), 0.0)
	await get_tree().process_frame
	for _i in 3:
		await get_tree().physics_frame
	var all_f := _filters()
	_check(all_f.size() == 4, "S9 four laser filters after building line_1 / line_3a / line_3c (%d)" % all_f.size())
	for f in all_f:
		var flt : LaserFilter = f as LaserFilter
		var tag : String = String(flt.get_meta("macro_id")) if flt.has_meta("macro_id") else flt.name
		for chan in [0, 1]:
			var sp : Vector3 = flt.spill_point_global(chan)
			var ej : Vector3 = flt.eject_global_achter() if chan == 0 else flt.eject_global_voor()
			var off : float = Vector2(sp.x - ej.x, sp.z - ej.z).length()
			var cart = flt.lump_cart_achter if chan == 0 else flt.lump_cart_voor
			var y_ok := true
			var cy_txt := "no cart bound"
			if cart != null and is_instance_valid(cart):
				var cy : float = (cart as Node3D).global_position.y
				y_ok = absf(sp.y - cy) < 0.05
				cy_txt = "cart base y %.3f" % cy
			_check(off < 0.05 and y_ok, "S9 %s nozzle %d mound point %s under the nozzle, on the cart's surface (%s)"
				% [tag, chan, str(sp.snappedf(0.01)), cy_txt])
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] lump cart overflow %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
