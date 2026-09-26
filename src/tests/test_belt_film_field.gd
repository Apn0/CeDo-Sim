extends Node
## BELT FILM BED (P1, 2026-09-23) — every conveyor deck carries a FilmFlakeField
## in belt mode, seated on the deck's top face, and LineFlow drives its bed from
## what the node actually moves.
##
##   godot --headless --path . res://src/tests/test_belt_film_field.tscn
##
## S1 geometry. The builders are called UNMERGED — BeltBuilder through the
##    catalog's own _m_* functions on a bare Node3D, the same calls build_node
##    makes before StaticMerge folds the deck into one ArrayMesh — so the deck
##    skin still exists as its own box. The field must sit on that box's top
##    face, share its plane, and span it. The inclined belt's deck must climb
##    the same diagonal as its rollers (it did not: measured 2026-09-23, fixed
##    alongside). Then the production path: build_node keeps the field through
##    the merge and LineFlow's finder returns it.
## S2 bed model on a bare field: kg/m = thru / speed, depth from density and
##    width, heap scaled to the depth, flakes in proportion and ON the bed, a
##    stopped deck holds, a moving starved deck drains within its transit time,
##    wet goes glossy, dirt goes brown.
## S3 colour order and size spread as the operator described them.
## S4 line 1 booted for real (BuildMode macro + LineFlow): the belts' fields
##    are belt-mode, the flotation tank's is not, a steady injection upstream
##    becomes a bed on that belt AND on the next one, an unfed belt shows
##    nothing, and switching the belt to HAND-off freezes the bed.
##
## A headless MultiMesh keeps no readable instance data (CLAUDE.md), so nothing
## here reads instance transforms: counts, node graph, heap mesh, shader
## uniforms and the bed numbers are what is asserted.

const WATCHDOG_S := 300.0
const TICK_S := 0.1

var _fails := 0
var _oks := 0

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

func _find_field(root: Node) -> Node:
	for c in root.find_children("*", "", true, false):
		if c.is_in_group("film_field"):
			return c
	return null

# ── S1 ─────────────────────────────────────────────────────────────────────────
func _s1_case(label: String, p: Node3D, climb_min: float) -> void:
	await get_tree().process_frame
	var field : Node = _find_field(p)
	_check(field != null, "S1 %s carries a FilmFlakeField" % label)
	if field == null:
		return
	var f3 := field as Node3D
	_check(bool(field.get("belt_mode")), "S1 %s field is in belt mode" % label)
	var skin : MeshInstance3D = p.find_child("DeckSkin", true, false) as MeshInstance3D
	_check(skin != null and skin.mesh is BoxMesh, "S1 %s deck skin box present in the unmerged build" % label)
	if skin == null or not (skin.mesh is BoxMesh):
		return
	var box : Vector3 = (skin.mesh as BoxMesh).size
	var top : float = box.y * 0.5
	var lp : Vector3 = skin.to_local(f3.global_position)
	_check(absf(lp.x) < 0.02 and absf(lp.z) < 0.02,
		"S1 %s field origin over the skin's centre (dx %.3f dz %.3f)" % [label, lp.x, lp.z])
	var surf_local : Vector3 = skin.to_local(f3.to_global(Vector3(0.0, float(field.get("surface_y")), 0.0)))
	_check(absf(surf_local.y - (top + 0.005)) < 0.006,
		"S1 %s film surface sits %.3f m above the skin's centre; the top face is at %.3f" % [label, surf_local.y, top])
	var n_dot : float = f3.global_transform.basis.y.normalized().dot(skin.global_transform.basis.y.normalized())
	_check(n_dot > 0.999, "S1 %s field shares the deck's plane (normal dot %.4f)" % [label, n_dot])
	var area : Vector2 = field.get("area")
	_check(absf(area.x - box.x * 0.92) < 0.02 and absf(area.y - box.z) < 0.02,
		"S1 %s field spans the deck: %.2f x %.2f m vs skin %.2f x %.2f" % [label, area.x, area.y, box.x, box.z])
	var fz : Vector3 = f3.global_transform.basis.z.normalized()
	var sz : Vector3 = skin.global_transform.basis.z.normalized()
	_check(absf(fz.dot(sz)) > 0.999, "S1 %s field drifts along the deck's long axis" % label)
	if climb_min > 0.0:
		_check(fz.y > climb_min, "S1 %s deck climbs toward +Z like its rollers (+Z.y = %.3f, want > %.2f)" % [label, fz.y, climb_min])
	if climb_min > 0.5:
		# the top roller's axle must lie on the deck plane, not 8 m off it
		var top_roller : Node3D = null
		for c in p.find_children("*", "", true, false):
			var mi := c as MeshInstance3D
			if mi != null and mi.mesh is CylinderMesh:
				if top_roller == null or mi.global_position.y > top_roller.global_position.y:
					top_roller = mi
		if top_roller != null:
			var off : float = absf((top_roller.global_position - skin.global_position).dot(skin.global_transform.basis.y.normalized()))
			_check(off < 0.30, "S1 %s top roller axle %.2f m off the deck plane" % [label, off])
	var heap := field.get_node_or_null("BedHeap") as MeshInstance3D
	_check(heap != null, "S1 %s field built its bed heap" % label)
	_check(heap != null and not heap.visible, "S1 %s bed heap hidden while the belt is bare" % label)
	if heap != null:
		var aabb : AABB = heap.mesh.get_aabb()
		var crest : float = aabb.position.y + aabb.size.y
		_check(absf(aabb.size.x - area.x) < 0.01 and absf(aabb.size.z - area.y) < 0.01 and aabb.position.y < 0.001 and crest > 0.9 and crest <= 1.25,
			"S1 %s heap spans the field (%.2f x %.2f m), feet on the deck, unit crest %.2f" % [label, aabb.size.x, aabb.size.z, crest])
		var hm := heap.mesh.surface_get_material(0) as StandardMaterial3D
		_check(hm != null and hm.albedo_texture != null and hm.normal_enabled and hm.normal_texture != null,
			"S1 %s heap wears the film texture with a normal map" % label)
	var fm : ShaderMaterial = field.get("_flake_shader_mat")
	_check(fm != null and absf(float(fm.get_shader_parameter("belt_len")) - area.y) < 1e-6,
		"S1 %s flakes use the scrolling shader with belt_len = %.2f" % [label, area.y])
	if fm != null:
		var ax : Vector3 = fm.get_shader_parameter("belt_axis")
		var up : Vector3 = fm.get_shader_parameter("belt_up")
		_check(ax.dot(f3.global_transform.basis.z.normalized()) > 0.999 and up.dot(f3.global_transform.basis.y.normalized()) > 0.999,
			"S1 %s shader knows the field's world axes" % label)
	_check(int(field.call("visible_count")) == 0, "S1 %s no flakes visible while the belt is bare" % label)
	_check(int(field.get("flake_count")) >= 120 and int(field.get("flake_count")) <= 1500,
		"S1 %s flake budget %d (120..1500, ~120 per m2)" % [label, int(field.get("flake_count"))])

func _s1() -> void:
	var cases := ["transport_belt", "transportband_3", "switch_belt", "compactorband", "inclined_belt_8m"]
	for id in cases:
		var item : Dictionary = PlaceableCatalog.get_item(id)
		var size : Vector3 = item["size"]
		var color : Color = item["color"]
		var p := Node3D.new()
		p.name = "Unmerged_" + id
		add_child(p)
		match id:
			"transport_belt":    PlaceableCatalog._m_belt(p, size, color, false)
			"transportband_3":   PlaceableCatalog._m_intake_belt(p, id, size, color, false)
			"switch_belt":       PlaceableCatalog._m_switch_belt(p, size, color, false)
			"compactorband":     PlaceableCatalog._m_compactorband(p, size, color, false)
			"inclined_belt_8m":  PlaceableCatalog._m_inclined_belt(p, size, color, false)
		var climb_min : float = -1.0
		if id == "transportband_3":
			climb_min = 0.10          # 10° incline: sin = 0.174
		elif id == "inclined_belt_8m":
			climb_min = 0.60          # 45° diagonal: 0.707
		await _s1_case(id, p, climb_min)
		p.queue_free()
	# Production path: build_node + StaticMerge, and LineFlow's finder.
	var lf_probe := LineFlow.new()
	for id in ["transportband_3", "inclined_belt_8m", "compactorband"]:
		var body : Node3D = PlaceableCatalog.build_node(id, false)
		_check(body != null, "S1 build_node(%s)" % id)
		if body == null:
			continue
		add_child(body)
		await get_tree().process_frame
		var field : Node = _find_field(body)
		_check(field != null and bool(field.get("belt_mode")), "S1 %s keeps its belt-mode field through the static merge" % id)
		var via_lf : Node = lf_probe.call("_find_film_field", body)
		_check(via_lf == field and field != null, "S1 LineFlow._find_film_field finds %s's field" % id)
		if field != null:
			_check(field.get_node_or_null("BedHeap") != null, "S1 %s heap survives the merge (scripted subtree is dynamic)" % id)
			var mmi : int = 0
			for c in field.get_children():
				if c is MultiMeshInstance3D:
					mmi += 1
			_check(mmi == 1, "S1 %s field has its one MultiMeshInstance3D" % id)
		body.queue_free()
	lf_probe.free()

# ── S2 ─────────────────────────────────────────────────────────────────────────
func _drive(f: Node, n: int, thru: float, v: float, moving: bool, wet: float = 0.0, dirt: float = 0.0) -> void:
	for _i in n:
		f.call("set_belt_state", thru, v, moving, wet, dirt, TICK_S)

func _s2() -> void:
	var f : Node3D = load("res://src/sim/FilmFlakeField.gd").new()
	f.set("area", Vector2(0.82, 6.0))
	f.set("bed_bulk_density", 60.0)
	f.set("flake_count", 150)
	f.set("surface_y", 1.0)
	f.call("set_belt_mode", true)
	add_child(f)
	await get_tree().process_frame
	var full : float = float(f.call("belt_full_kg_per_m"))
	_check(absf(full - 0.20 * 60.0 * 0.82) < 1e-6, "S2 full bed = 0.20 m x 60 kg/m3 x 0.82 m = %.3f kg/m" % full)
	# slews, does not jump: 10 ticks toward 2.4 kg/m at one belt-full per 12 s transit
	_drive(f, 10, 1.2, 0.5, true)
	var b10 : float = float(f.call("bed_kg_per_m"))
	_check(absf(b10 - full * 1.0 / 12.0) < 1e-4, "S2 after 1.0 s the bed is %.3f kg/m (one belt-full per 12 s transit)" % b10)
	_drive(f, 190, 1.2, 0.5, true)
	var bed : float = float(f.call("bed_kg_per_m"))
	var depth : float = float(f.call("bed_depth_m"))
	_check(absf(bed - 2.4) < 1e-6, "S2 steady 1.2 kg/s at 0.5 m/s -> %.3f kg/m (2.4)" % bed)
	_check(absf(depth - 2.4 / (60.0 * 0.82)) < 1e-6, "S2 depth %.4f m = kg/m / (density x width)" % depth)
	var vis : int = int(f.call("visible_count"))
	var want_vis : int = int(round(150.0 * (0.25 + 0.75 * depth / 0.20)))
	_check(vis == want_vis, "S2 %d of 150 flakes visible at %.1f cm (want %d)" % [vis, depth * 100.0, want_vis])
	var heap := f.get_node("BedHeap") as MeshInstance3D
	var fm : ShaderMaterial = f.get("_flake_shader_mat")
	_check(heap.visible, "S2 bed heap shown")
	_check(absf(heap.scale.y - depth) < 1e-6, "S2 heap scaled to the bed depth (%.4f)" % heap.scale.y)
	_check(absf(heap.position.y - 1.0) < 1e-6, "S2 heap stands on the surface")
	_check(absf(float(fm.get_shader_parameter("bed_depth")) - depth) < 1e-6, "S2 shader lifts the flakes by the bed depth")
	# the scroll: 10 frames of 0.1 s at 0.5 m/s → 0.5 m, wrapped at the 6 m deck
	for _i in 10:
		f.call("_process", 0.1)
	_check(absf(float(f.call("scroll_m")) - 0.5) < 1e-6 and absf(float(fm.get_shader_parameter("scroll")) - 0.5) < 1e-6,
		"S2 the bed scrolled 0.50 m in 1.0 s at 0.5 m/s (%.3f)" % float(f.call("scroll_m")))
	for _i in 130:
		f.call("_process", 0.1)
	_check(float(f.call("scroll_m")) < 6.0 and absf(float(f.call("scroll_m")) - 1.0) < 1e-4,
		"S2 the scroll wraps at the deck length (7.0 m travelled -> %.3f)" % float(f.call("scroll_m")))
	var fy : float = (f.call("flake_local_pos", 0) as Vector3).y
	_check(fy >= 1.0 + depth - 1e-6 and fy <= 1.0 + depth + 0.02 + 0.25 * depth + 1e-6,
		"S2 flake 0 sits ON the bed top (y %.4f, bed top %.4f)" % [fy, 1.0 + depth])
	_check(absf(float(f.get("flow_speed")) - 0.5) < 1e-6, "S2 flakes drift at the deck speed, not load-scaled")
	# hold: a stopped deck keeps its bed
	_drive(f, 50, 0.0, 0.0, false)
	_check(absf(float(f.call("bed_kg_per_m")) - 2.4) < 1e-9, "S2 stopped deck holds %.3f kg/m through 5 s of zero flow" % float(f.call("bed_kg_per_m")))
	_check(int(f.call("visible_count")) == vis, "S2 stopped deck keeps its %d flakes visible" % vis)
	_check(float(f.call("belt_speed_mps")) == 0.0 and float(f.get("flow_speed")) == 0.0, "S2 stopped deck drifts nothing")
	var sc0 : float = float(f.call("scroll_m"))
	for _i in 10:
		f.call("_process", 0.1)
	_check(float(f.call("scroll_m")) == sc0, "S2 stopped deck does not scroll")
	# drain: moving and starved empties within the transit time
	_drive(f, 10, 0.0, 0.5, true)
	var b_dr : float = float(f.call("bed_kg_per_m"))
	_check(b_dr > 1.0 and b_dr < 2.4, "S2 starved moving deck drains gradually (%.3f kg/m after 1 s)" % b_dr)
	_drive(f, 30, 0.0, 0.5, true)
	_check(float(f.call("bed_kg_per_m")) == 0.0 and int(f.call("visible_count")) == 0 and not heap.visible,
		"S2 bare again within the 12 s transit: 0 kg/m, 0 flakes, heap hidden")
	# full: more than a belt-full shows every flake
	_drive(f, 200, 6.0, 0.5, true)
	_check(int(f.call("visible_count")) == 150 and float(f.call("bed_depth_m")) > 0.20,
		"S2 %.1f cm bed (over BED_FULL) shows all 150 flakes" % (float(f.call("bed_depth_m")) * 100.0))
	# wet and dirty
	var hmat : StandardMaterial3D = heap.mesh.surface_get_material(0)
	_drive(f, 1, 6.0, 0.5, true, 1.0, 0.0)
	var rough_f : float = float(fm.get_shader_parameter("rough"))
	_check(rough_f < 0.30 and hmat.roughness < 0.30, "S2 wet flake and bed go glossy (roughness %.2f / %.2f)" % [rough_f, hmat.roughness])
	_drive(f, 1, 6.0, 0.5, true, 0.0, 1.0)
	var tint_f : Color = fm.get_shader_parameter("tint")
	_check(tint_f.r > tint_f.b + 0.05 and hmat.albedo_color.r > hmat.albedo_color.b + 0.05,
		"S2 dirty flake and bed tint brown (r %.2f > b %.2f)" % [tint_f.r, tint_f.b])
	# ── S3 on the same field ──
	var counts := {"white": 0, "blue": 0, "other": 0, "black": 0}
	var n_s := 6000
	for i in n_s:
		counts[String(f.call("colour_bucket", i))] += 1
	var w01 : float = float(counts["white"]) / float(n_s)
	_check(w01 >= 0.60, "S3 white/translucent is the majority: %.1f %%" % (w01 * 100.0))
	_check(counts["blue"] > counts["other"] and counts["other"] > counts["black"] and counts["black"] > 0,
		"S3 order after white: blue %d > other %d > black %d > 0" % [counts["blue"], counts["other"], counts["black"]])
	var blues : Array = f.get("BLUES")
	var mism := 0
	for i in 400:
		if String(f.call("colour_bucket", i)) == "blue":
			var c : Color = f.call("_flake_color", i)
			var hit := false
			for b in blues:
				if (b as Color).is_equal_approx(c):
					hit = true
			if not hit:
				mism += 1
	_check(mism == 0, "S3 every blue-bucket flake draws from BLUES (%d mismatches)" % mism)
	var asp : PackedFloat32Array = f.get("_aspect")
	var gau : PackedFloat32Array = f.get("_gauge")
	var a_min := 9.0; var a_max := 0.0; var g_min := 9.0; var g_max := 0.0
	for i in asp.size():
		a_min = minf(a_min, asp[i]); a_max = maxf(a_max, asp[i])
		g_min = minf(g_min, gau[i]); g_max = maxf(g_max, gau[i])
	_check(a_min < 0.70 and a_max > 2.80, "S3 mixed sizes: length multiplier spans %.2f .. %.2f" % [a_min, a_max])
	_check(g_min < 0.70 and g_max > 1.40, "S3 mixed sizes: size multiplier spans %.2f .. %.2f" % [g_min, g_max])
	f.queue_free()

# ── S4 ─────────────────────────────────────────────────────────────────────────
func _s4() -> void:
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.set("feed_enabled", false)   # no head feed: the injection below is the only source
	lf.call("start_line")
	var nodes : Array = lf.get("_nodes")
	var belts : Array = []          # indices of belt-id nodes, in placement order
	var tank_view : Node = null
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		var nid := String(nd.get("id", ""))
		if LineFlow._is_belt_id(nid):
			belts.append(i)
		if nid == "flotation_tank":
			tank_view = nd.get("view")
	_check(belts.size() >= 3, "S4 line 1 has %d belt nodes" % belts.size())
	# The fed belt and the one after it. Since 2026-09-25 line 1's first
	# conveyor after shredder 1 is uitvoerband_1 (a feed-belt model with its own
	# bed), and it throws onto the one transport_belt left before the drum.
	var tb : Array = []
	var cband : int = -1
	var no_field : Array = []
	for i in belts:
		var nd : Dictionary = nodes[i]
		var nid := String(nd["id"])
		var v = nd.get("view")
		if v == null:
			no_field.append(nid)
			continue
		_check(bool(v.get("belt_mode")), "S4 %s#%d field is belt-mode" % [nid, i])
		if nid == "uitvoerband_1" or nid == "transport_belt":
			tb.append(i)
		elif nid == "compactorband":
			cband = i
	print("  info  : belt nodes without a field: %s (drum_feed_belt is a ShredderFeedBelt scene — listed as open)" % [no_field])
	_check(tb.size() == 2 and cband >= 0 and String((nodes[tb[0]] as Dictionary)["id"]) == "uitvoerband_1",
		"S4 the uitvoerband, the belt after it (%s) and the compactorband (#%d) carry fields" % [tb, cband])
	if tb.size() > 0:
		_check(((nodes[tb[0]] as Dictionary).get("views", []) as Array).size() == 2,
			"S4 the uitvoerband carries a bed on its flat deck AND on its climb (%d)"
				% ((nodes[tb[0]] as Dictionary).get("views", []) as Array).size())
	_check(tank_view != null and bool(tank_view.get("mat_mode")) and not bool(tank_view.get("belt_mode")),
		"S4 the flotation tank's field stays a float raft (mat mode, not belt mode)")
	if tb.size() < 2 or cband < 0:
		return
	var n1 : Dictionary = nodes[tb[0]]
	var n2 : Dictionary = nodes[tb[1]]
	var v1 : Node = n1["view"]
	var v2 : Node = n2["view"]
	var vc : Node = nodes[cband]["view"]
	# steady injection of 3 kg/s into the first belt's input buffer, 20 s
	var bin1 : MaterialBatch = n1.get("in", null) as MaterialBatch
	_check(bin1 != null, "S4 the uitvoerband has an input buffer")
	if bin1 == null:
		return
	var edges : Array = lf.get("_edges")
	var into1 : Array = []
	var outof1 : Array = []
	for e in edges:
		if int(e["b"]) == tb[0]:
			into1.append(String((nodes[int(e["a"])] as Dictionary)["id"]))
		if int(e["a"]) == tb[0]:
			outof1.append(String((nodes[int(e["b"])] as Dictionary)["id"]))
	print("  info  : belt#%d edges in %s, out %s" % [tb[0], into1, outof1])
	# The PLC starts the line as a cascade (downstream first, with dwell), so
	# the belt is unpowered for the first seconds; anything injected then piles
	# up as backlog and drains later at the design rate. Wait for its power.
	var t_pwr := 0
	while float(n1["spin"]) < 0.99 and t_pwr < 900:
		lf.tick(TICK_S)
		t_pwr += 1
	print("  info  : belt#%d powered and at full spin after %.1f s of start-up cascade" % [tb[0], float(t_pwr) * TICK_S])
	_check(float(n1["spin"]) >= 0.99, "S4 the fed belt came up to full spin (%.2f)" % float(n1["spin"]))
	for t in 200:
		bin1.add(MaterialBatch.new(0.3, 0.3 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
		lf.tick(TICK_S)
		if t == 0 or t == 25 or t == 100 or t == 199:
			print("  info  : t=%3d belt#%d thru %.2f moved %.3f backlog %.3f spin %.2f | belt#%d thru %.2f"
				% [t + 1, tb[0], float(n1["thru"]), float(n1.get("_moved_kg", 0.0)), float(n1.get("_backlog_kg", 0.0)),
				   float(n1["spin"]), tb[1], float(n2["thru"])])
	var thru1 : float = float(n1["thru"])
	# LineFlow's own lookup: the body's belt_speed meta, else the bed field's
	# (a feed-belt model such as uitvoerband_1 carries it on the field).
	var speed1 : float = float(lf.call("_belt_speed_of", n1))
	var bed1 : float = float(v1.call("bed_kg_per_m"))
	print("  info  : belt#%d thru %.2f kg/s, deck %.2f m/s, spin %.2f -> bed %.2f kg/m, depth %.1f cm, %d flakes"
		% [tb[0], thru1, speed1, float(n1["spin"]), bed1, float(v1.call("bed_depth_m")) * 100.0, int(v1.call("visible_count"))])
	_check(thru1 > 2.5, "S4 the fed belt moves %.2f kg/s" % thru1)
	_check(absf(bed1 - thru1 / speed1) < 0.5, "S4 its bed is thru / deck speed: %.2f vs %.2f kg/m" % [bed1, thru1 / speed1])
	_check(int(v1.call("visible_count")) > 0 and float(v1.call("bed_depth_m")) > 0.02,
		"S4 the fed belt shows a bed (%d flakes, %.1f cm)" % [int(v1.call("visible_count")), float(v1.call("bed_depth_m")) * 100.0])
	var bed2 : float = float(v2.call("bed_kg_per_m"))
	print("  info  : belt#%d thru %.2f kg/s -> bed %.2f kg/m, %d flakes" % [tb[1], float(n2["thru"]), bed2, int(v2.call("visible_count"))])
	_check(bed2 > 0.0 and int(v2.call("visible_count")) > 0, "S4 the next belt downstream carries a bed too (%.2f kg/m)" % bed2)
	_check(float(vc.call("bed_kg_per_m")) == 0.0 and int(vc.call("visible_count")) == 0,
		"S4 the unfed compactorband shows nothing (anti-vacuity: fields are empty until material arrives)")
	# switch the fed belt to HAND and leave it off (the HMI's per-machine
	# override): power drops, spin runs down over SPIN_UP_S, then the bed holds
	n1["hand_mode"] = true
	n1["manual_on"] = false
	for _t in 60:
		lf.tick(TICK_S)
	var spin_after : float = float(n1["spin"])
	_check(spin_after < 0.05, "S4 after HAND-off the fed belt's spin is %.2f" % spin_after)
	var held : float = float(v1.call("bed_kg_per_m"))
	for _t in 40:
		lf.tick(TICK_S)
	# How much is left depends on the transit time against the 2.5 s spin-down:
	# at the operator's 1.0 m/s a 4 m belt empties in 4 s, so most of the bed
	# has left before the deck stands; at the old 0.4 m/s (10 s transit) about
	# three quarters stayed. The drain slows with the deck (transit is taken at
	# the live speed), which is why something always remains.
	_check(held > 0.0, "S4 the stopped belt still carries %.2f kg/m" % held)
	_check(float(v1.call("bed_kg_per_m")) == held, "S4 the bed holds exactly through 4 s stopped (%.3f kg/m)" % held)
	_check(float(v1.call("belt_speed_mps")) == 0.0, "S4 the stopped belt's flakes drift nothing")

# ── main ───────────────────────────────────────────────────────────────────────
func _run() -> void:
	print("[TEST] belt film bed — P1")
	await _s1()
	await _s2()
	await _s4()
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
