extends Node
## WET-SIDE FLAKE BEDS (task 1c, rulings §1 / §12, 2026-09-24) — flake where
## the operator sees it on the wet side, "same flake, wet and darker", built
## with "the textured soil simulation" (the belts' heap + flake layer).
##
##   godot --headless --path . res://src/tests/test_wet_side_beds.tscn
##
## B — geometry read off UNMERGED builds (the catalog's own _m_* on a bare
##     Node3D): the Kufferath deck descends toward its outlet and carries one
##     bed; the scheidingsgoot carries a bed in each of its five segments, all
##     downhill; the dewatering screw builds both its closed tube and the open
##     trough (closed by default, switchable); the bunker and doseersilo beds.
## P — the production path: build_node + StaticMerge keep every bed.
## G — the graph decides which screw troughs open: a flotation-fed one opens,
##     a rafter-fed one stays closed (rulings §12), after a real rebuild().
## L — line 1 for real: a bale through BuildMode._build_full_line + LineFlow;
##     the sieve, goot and screw beds fill with WET flake (moisture from the
##     sim, tint darker than dry) and empty again.

const WATCHDOG_S := 480.0

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

func _fields(root: Node) -> Array:
	var out : Array = []
	for c in root.find_children("*", "", true, false):
		if c.is_in_group("film_field"):
			out.append(c)
	return out

func _build_unmerged(id: String) -> Node3D:
	var item : Dictionary = PlaceableCatalog.get_item(id)
	var p := Node3D.new()
	add_child(p)
	match id:
		"kufferath_sieve": PlaceableCatalog._m_kufferath(p, item["size"], item["color"], false)
		"scheidingsgoot":  PlaceableCatalog._m_scheidingsgoot(p, item["size"], item["color"], false)
		"dewater_screw":   PlaceableCatalog._m_dewater(p, item["size"], item["color"], false)
		"bunker":          PlaceableCatalog._m_bunker(p, item["size"], item["color"], false)
		"doseersilo":      PlaceableCatalog._m_doseersilo(p, item["size"], item["color"], false)
	return p

func _run() -> void:
	print("[TEST] wet-side flake beds — rulings §1 / §12")
	# ── B1 Kufferath ──
	var kf := _build_unmerged("kufferath_sieve")
	await get_tree().process_frame
	var deck_piv := kf.find_child("SieveDeck", true, false) as Node3D
	_check(deck_piv != null, "B1 kufferath has its SieveDeck bed pivot")
	if deck_piv != null:
		var zy : float = deck_piv.global_transform.basis.z.y
		_check(zy < -0.2, "B1 the deck DESCENDS toward +Z — feed box high at -Z, outlet low at +Z as the ports say (z-axis y %.2f)" % zy)
	var kf_f := _fields(kf)
	_check(kf_f.size() == 1 and bool(kf_f[0].get("belt_mode")), "B1 one belt-mode bed on the sieve deck (%d)" % kf_f.size())
	_check(kf_f.size() == 1 and absf(float(kf_f[0].get_meta("bed_speed_mps", -1.0)) - PlaceableCatalog.KUFFERATH_BED_SPEED_MPS) < 1e-6,
		"B1 the bed carries its transport speed (%.2f m/s)" % PlaceableCatalog.KUFFERATH_BED_SPEED_MPS)
	# ── B2 scheidingsgoot ──
	var sg := _build_unmerged("scheidingsgoot")
	await get_tree().process_frame
	var sg_f := _fields(sg)
	_check(sg_f.size() == 5, "B2 scheidingsgoot: a bed in each of the 5 segments — stem, 2 branches, 2 run-outs (%d)" % sg_f.size())
	var downhill := 0
	for f in sg_f:
		if (f as Node3D).global_transform.basis.z.y < -0.2:
			downhill += 1
	_check(downhill == sg_f.size() and sg_f.size() > 0, "B2 every goot bed scrolls DOWNHILL (%d of %d)" % [downhill, sg_f.size()])
	# ── B3 dewatering screw ──
	var dw := _build_unmerged("dewater_screw")
	await get_tree().process_frame
	var tube := dw.find_child("DewaterTube", true, false) as Node3D
	var trough := dw.find_child("DewaterTrough", true, false) as Node3D
	_check(tube != null and trough != null, "B3 the dewater screw builds both the closed tube and the open trough")
	_check(tube != null and trough != null and tube.visible and not trough.visible, "B3 closed by default (tube shown, trough hidden)")
	var flipped : bool = PlaceableCatalog.set_dewater_open(dw, true)
	_check(flipped and tube != null and not tube.visible and trough != null and trough.visible and bool(dw.get_meta("dewater_open", false)),
		"B3 set_dewater_open(true) shows the trough, hides the tube, records dewater_open")
	var dw_f := _fields(dw)
	_check(dw_f.size() == 1 and (dw_f[0] as Node3D).global_transform.basis.z.y > 0.2, "B3 the trough bed CLIMBS toward +Z (low inlet, high outlet)")
	var auger_in_trough := false
	if trough != null:
		for c in trough.find_children("*", "", true, false):
			if c.has_meta("comp") and String(c.get_meta("comp")) == "dewater_auger":
				auger_in_trough = true
	_check(auger_in_trough, "B3 the screw is visible inside the open trough")
	# ── B4 bunker + doseersilo ──
	var bk := _build_unmerged("bunker")
	await get_tree().process_frame
	var bk_f := _fields(bk)
	var deck := bk.find_child("BunkerDeck", true, false)
	var bk_speed : float = float(bk_f[0].get_meta("bed_speed_mps", -1.0)) if bk_f.size() == 1 else -1.0
	_check(bk_f.size() == 1 and deck != null and absf(bk_speed - float(deck.get_meta("belt_speed", -2.0))) < 1e-6,
		"B4 the bunker bed creeps at the deck's own belt_speed (%.4f m/s)" % bk_speed)
	var ds := _build_unmerged("doseersilo")
	await get_tree().process_frame
	var ds_f := _fields(ds)
	_check(ds_f.size() == 1 and (ds_f[0] as Node).get_parent().name == "Trough", "B4 the doseersilo bed rides the tilted Trough")
	for n in [kf, sg, dw, bk, ds]:
		n.queue_free()
	# ── P production path ──
	for pair in [["kufferath_sieve", 1], ["scheidingsgoot", 5], ["dewater_screw", 1], ["bunker", 1], ["doseersilo", 1]]:
		var body : Node3D = PlaceableCatalog.build_node(String(pair[0]), false)
		add_child(body)
		await get_tree().process_frame
		var n_f : int = _fields(body).size()
		_check(n_f == int(pair[1]), "P1 %s keeps %d bed(s) through build_node + StaticMerge (%d)" % [pair[0], int(pair[1]), n_f])
		if String(pair[0]) == "dewater_screw":
			_check(body.find_child("DewaterTrough", true, false) != null and body.find_child("DewaterTube", true, false) != null,
				"P1 both dewater looks survive StaticMerge (no_merge)")
		body.queue_free()
	await get_tree().process_frame
	# ── G the graph decides ──
	var ft_sz : Vector3 = PlaceableCatalog.get_item("flotation_tank")["size"]
	var rf_sz : Vector3 = PlaceableCatalog.get_item("rafter")["size"]
	var ft : Node3D = PlaceableCatalog.build_node("flotation_tank", false)
	add_child(ft)
	ft.global_position = Vector3(0.0, 0.0, 0.0)
	var dw1 : Node3D = PlaceableCatalog.build_node("dewater_screw", false)
	add_child(dw1)
	dw1.global_position = Vector3(0.0, 0.0, ft_sz.z * 0.5 + 2.5)
	var rf : Node3D = PlaceableCatalog.build_node("rafter", false)
	add_child(rf)
	rf.global_position = Vector3(60.0, 0.0, 0.0)
	var dw2 : Node3D = PlaceableCatalog.build_node("dewater_screw", false)
	add_child(dw2)
	dw2.global_position = Vector3(60.0, 0.0, -(rf_sz.z * 0.5 + 2.5))
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.set("feed_enabled", false)
	lf.call("rebuild")
	await get_tree().process_frame
	var g_nodes : Array = lf.get("_nodes")
	var g_edges : Array = lf.get("_edges")
	var fed_by : Dictionary = {}
	for e in g_edges:
		var src : String = String((g_nodes[int(e["a"])] as Dictionary).get("id", ""))
		var tgt = (g_nodes[int(e["b"])] as Dictionary).get("node")
		fed_by[tgt] = src
	print("  info  : G edges — dw1 fed by '%s', dw2 fed by '%s'" % [String(fed_by.get(dw1, "-")), String(fed_by.get(dw2, "-"))])
	_check(String(fed_by.get(dw1, "")) == "flotation_tank" and String(fed_by.get(dw2, "")) == "rafter", "G0 fixture wired: flotation_tank → dw1, rafter → dw2")
	_check(bool(dw1.get_meta("dewater_open", false)), "G1 the flotation-fed screw's trough is OPEN after rebuild()")
	_check(not bool(dw2.get_meta("dewater_open", true)), "G1 the rafter-fed screw stays CLOSED")
	var dw1_trough := dw1.find_child("DewaterTrough", true, false) as Node3D
	var dw2_trough := dw2.find_child("DewaterTrough", true, false) as Node3D
	_check(dw1_trough != null and dw1_trough.visible and dw2_trough != null and not dw2_trough.visible, "G1 …and the looks follow (dw1 trough visible, dw2 hidden)")
	lf.queue_free()
	for n in [ft, dw1, rf, dw2]:
		n.queue_free()
	await get_tree().process_frame
	# ── L line 1 for real ──
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var lf1 := LineFlow.new()
	add_child(lf1)
	await get_tree().process_frame
	lf1.call("rebuild")
	await get_tree().process_frame
	lf1.call("start_line")
	var nodes : Array = lf1.get("_nodes")
	var edges : Array = lf1.get("_edges")
	var has_incoming : Dictionary = {}
	for e in edges:
		has_incoming[int((e as Dictionary)["b"])] = true
	var head_node : Node3D = null
	for i2 in nodes.size():
		var nd : Dictionary = nodes[i2]
		if String(nd.get("role", "")) == "sink" or has_incoming.has(i2):
			continue
		var n3d = nd.get("node")
		if n3d != null and is_instance_valid(n3d):
			head_node = n3d as Node3D
			break
	_check(head_node != null and String(head_node.get_meta("placeable_id", "?")) == "opzetband_1", "L0 line 1's source head is opzetband_1")
	if head_node == null:
		_finish(); return
	# An Array of records, each holding its LineFlow node dict by reference: a
	# node dict cannot be a Dictionary KEY, its contents (thru, moist…) change
	# every tick and so does its hash (measured: the first run of this suite).
	var watched : Array = []
	for nd in nodes:
		var id := String(nd.get("id", ""))
		if id in ["kufferath_sieve", "scheidingsgoot", "dewater_screw"]:
			watched.append({"nd": nd, "id": id, "max_depth": 0.0, "moist": 0.0, "tint": 1.0, "views": (nd.get("views", []) as Array).size()})
	_check(watched.size() == 4, "L0 line 1 carries 2 Kufferath sieves, the scheidingsgoot and a dewatering screw (%d watched)" % watched.size())
	var goot_views := 0
	var dw_open_l1 := false
	for w0 in watched:
		if w0["id"] == "scheidingsgoot":
			goot_views = int(w0["views"])
		if w0["id"] == "dewater_screw":
			dw_open_l1 = bool(((w0["nd"] as Dictionary).get("node") as Node).get_meta("dewater_open", false))
	_check(goot_views == 5, "L0 LineFlow sees all 5 goot beds (views = %d)" % goot_views)
	_check(dw_open_l1, "L0 line 1's dewatering screw (after the flotation tank) is OPEN")
	var bale : Node3D = PlaceableCatalog.build_node("rotterdam", false)
	add_child(bale)
	bale.global_position = lf1.call("_head_feed_point", head_node)
	bale.set_meta("delivered", true)
	var bale_gone := false
	var ticks := 0
	while ticks < 4000:
		lf1.call("tick", 0.1)
		ticks += 1
		if ticks % 10 == 0:
			await get_tree().process_frame
		for w in watched:
			var nd : Dictionary = w["nd"]
			for v in (nd.get("views", []) as Array):
				var d : float = float(v.call("bed_depth_m"))
				if d > float(w["max_depth"]):
					w["max_depth"] = d
					w["moist"] = float(nd["moist"])
					# Belt mode tints the HEAP's StandardMaterial and the flake
					# ShaderMaterial's "tint" (there is no _mat in belt mode).
					var hm : StandardMaterial3D = v.get("_heap_mat")
					if hm != null:
						w["tint"] = hm.albedo_color.r
					else:
						var fm : ShaderMaterial = v.get("_flake_shader_mat")
						w["tint"] = (fm.get_shader_parameter("tint") as Color).r if fm != null else 1.0
		if not bale_gone and (not is_instance_valid(bale) or bale.is_queued_for_deletion()):
			bale_gone = true
		if bale_gone and float(lf1.call("in_transit_mass")) < 0.05 and ticks > 600:
			break
	print("  info  : L ran %d ticks (%.0f s sim), bale gone %s" % [ticks, ticks * 0.1, str(bale_gone)])
	var wet_beds := 0
	var dark_beds := 0
	var moist_seen := 0.0
	for w in watched:
		print("  info  : %-16s max bed depth %.1f cm, moisture %.1f %%, tint r %.2f" % [w["id"], float(w["max_depth"]) * 100.0, float(w["moist"]), float(w["tint"])])
		if float(w["max_depth"]) > 0.002:
			wet_beds += 1
			if float(w["tint"]) < 0.90:
				dark_beds += 1
		moist_seen = maxf(moist_seen, float(w["moist"]))
	_check(bale_gone, "L1 the bale was taken off the intake belt")
	_check(wet_beds >= 3, "L1 at least three of the four wet-side beds carried flake (%d)" % wet_beds)
	_check(moist_seen > 10.0, "L1 the stream there is WET (max moisture %.1f %% at peak bed)" % moist_seen)
	_check(dark_beds == wet_beds and wet_beds > 0, "L1 every filled bed was tinted darker than dry film (%d of %d)" % [dark_beds, wet_beds])
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
