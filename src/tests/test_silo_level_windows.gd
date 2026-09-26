extends Node
## SILO LEVEL WINDOWS (P5 silo half, 2026-09-23) — the three silos the operator
## says carry a visible level do, at the windows he described, and the level
## behind each glass follows the machine's buffer.
##
##   godot --headless --path . res://src/tests/test_silo_level_windows.tscn
##
## Operator rulings 2026-09-23 §3/§9 (recollection, quoted in the doc):
##   doseersilo   — 2 square ~30x30 cm windows, 90 cm apart horizontally,
##                  centred along the tank, on both sides
##   mengsilo     — 1 small 15x15 cm window a third of the way up, one side
##   extruder silo — 4 vertical windows per LONG side, each in the inner
##                  sub-quadrant of its quadrant, not touching
##   VSS          — none
##
## S1 geometry, on the UNMERGED builder (the catalog's own _m_* call on a bare
##    Node3D, before StaticMerge folds the panes away): pane count, size,
##    which faces, spacing, and the witness metas the level drive uses.
## S2 the level drive: set_silo_fill() from 0 to 1 — witnesses hidden below
##    their window, partial inside it, full above it, monotonic, and the
##    witness top sits ON the level line (also on the doseersilo's sloped wall).
## S3 production path: build_node keeps SiloFill through the merge, and a real
##    LineFlow node drives it from its buffer against SILO_FULL_KG.
##
## MultiMesh is not involved; every number here is a node property.

const WATCHDOG_S := 240.0
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

func _build_unmerged(id: String) -> Node3D:
	var item : Dictionary = PlaceableCatalog.get_item(id)
	var p := Node3D.new()
	p.name = "Unmerged_" + id
	add_child(p)
	match id:
		"doseersilo":    PlaceableCatalog._m_doseersilo(p, item["size"], item["color"], false)
		"mengsilo":      PlaceableCatalog._m_mengsilo(p, item["size"], item["color"], false)
		"extruder_silo": PlaceableCatalog._m_extruder_silo(p, item["size"], item["color"], false)
	return p

## Every WindowGlass pane under `root`: {pos (global), normal (global), size (Vector2)}.
func _panes(root: Node) -> Array:
	var out : Array = []
	for c in root.find_children("WindowGlass", "", true, false):
		var mi := c as MeshInstance3D
		if mi == null:
			continue
		out.append({"pos": mi.global_position, "normal": mi.global_transform.basis.z.normalized(),
			"size": mi.get_meta("window_size", Vector2.ZERO), "node": mi})
	return out

func _leg_h(root: Node) -> float:
	for c in root.find_children("*", "", true, false):
		if c.is_in_group("machine_leg") and c.has_meta("leg_h"):
			return float(c.get_meta("leg_h"))
	return -1.0

# ── S1 ─────────────────────────────────────────────────────────────────────────
func _s1() -> void:
	# doseersilo
	var ds := _build_unmerged("doseersilo")
	await get_tree().process_frame
	var dp := _panes(ds)
	_check(dp.size() == 4, "S1 doseersilo has 4 windows (%d)" % dp.size())
	var ok_size := true
	var zs : Array = []
	var sides := {"+x": 0, "-x": 0}
	for w in dp:
		var sz : Vector2 = w["size"]
		if absf(sz.x - 0.30) > 1e-6 or absf(sz.y - 0.30) > 1e-6:
			ok_size = false
		zs.append(float((w["pos"] as Vector3).z))
		if (w["normal"] as Vector3).x > 0.5:
			sides["+x"] += 1
		elif (w["normal"] as Vector3).x < -0.5:
			sides["-x"] += 1
	_check(ok_size, "S1 doseersilo windows are 0.30 x 0.30 m squares")
	_check(sides["+x"] == 2 and sides["-x"] == 2, "S1 doseersilo: two windows on each long side (+x %d, -x %d)" % [sides["+x"], sides["-x"]])
	# The trough is TILTED (rulings §17), so "90 cm apart along the tank" is a
	# distance along the trough, measured here as the 3-D distance between the
	# two panes of one side, and "centred" as the pair's midpoint sitting on
	# the trough's centre plane (z = 0 in the trough's frame).
	var trough := ds.find_child("Trough", true, false) as Node3D
	_check(trough != null, "S1 doseersilo has its tilted Trough frame")
	var pair_ok := true
	var centred_ok := true
	for side in [1.0, -1.0]:
		var pts : Array = []
		for w in dp:
			if (w["normal"] as Vector3).x * side > 0.5:
				pts.append(w["pos"])
		if pts.size() != 2:
			pair_ok = false
			continue
		if absf((pts[0] as Vector3).distance_to(pts[1]) - 0.90) > 1e-3:
			pair_ok = false
		if trough != null:
			var mid_local : Vector3 = trough.to_local(((pts[0] as Vector3) + (pts[1] as Vector3)) * 0.5)
			if absf(mid_local.z) > 1e-3:
				centred_ok = false
	_check(pair_ok, "S1 doseersilo windows 0.90 m apart along the tank on each side")
	_check(centred_ok, "S1 doseersilo window pairs centred along the tank")
	var ds_fill := ds.find_child("SiloFill", true, false) as Node3D
	_check(ds_fill != null and float(ds_fill.get_meta("silo_fill_range_y", 0.0)) > 0.8,
		"S1 doseersilo level range %.2f m (the trough wall's height, in the trough's frame)" % (float(ds_fill.get_meta("silo_fill_range_y", 0.0)) if ds_fill else -1.0))
	var mean_z : float = 0.0
	if ds_fill != null:
		# The walls are vertical in the trough's frame and the whole trough is
		# tilted (rulings §17): every witness holder's up-axis leans off world
		# up by the trough's tilt, and the pane sits flat on the wall (no
		# slope scaling, unlike the old half-pipe).
		var wits : int = 0
		var leaning := true
		var lean_deg : float = 0.0
		for h in ds_fill.get_children():
			if h.has_meta("win_bottom_y"):
				wits += 1
				var up : Vector3 = (h as Node3D).global_transform.basis.y.normalized()
				lean_deg = rad_to_deg(acos(clampf(up.dot(Vector3.UP), -1.0, 1.0)))
				if lean_deg < 20.0 or lean_deg > 25.0:
					leaning = false
		_check(wits == 4 and leaning, "S1 doseersilo: 4 witnesses leaning with the trough (%.1f° off vertical, operator: 20-25)" % lean_deg)
	# mengsilo
	var ms := _build_unmerged("mengsilo")
	await get_tree().process_frame
	var mp := _panes(ms)
	_check(mp.size() == 1, "S1 mengsilo has exactly 1 window (%d)" % mp.size())
	if mp.size() == 1:
		var sz : Vector2 = mp[0]["size"]
		_check(absf(sz.x - 0.15) < 1e-6 and absf(sz.y - 0.15) < 1e-6, "S1 mengsilo window is 0.15 x 0.15 m")
		var leg_h := _leg_h(ms)
		var total_h : float = float(PlaceableCatalog.get_item("mengsilo")["size"].y)
		var frac_up : float = ((mp[0]["pos"] as Vector3).y - leg_h) / (total_h - leg_h)
		_check(leg_h > 0.0 and absf(frac_up - 1.0 / 3.0) < 0.01, "S1 mengsilo window a third of the way up (%.3f of the height above the legs)" % frac_up)
		_check(absf((mp[0]["normal"] as Vector3).y) < 0.01, "S1 mengsilo window is on a side, upright")
	var ms_fill := ms.find_child("SiloFill", true, false) as Node3D
	if ms_fill != null and mp.size() == 1:
		var base : float = float(ms_fill.get_meta("silo_fill_base_y"))
		var rng : float = float(ms_fill.get_meta("silo_fill_range_y"))
		var wy : float = (mp[0]["pos"] as Vector3).y
		_check(wy > base and wy < base + rng, "S1 mengsilo window lies inside the level range (enters at %.0f %%)" % (100.0 * (wy - 0.075 - base) / rng))
	# extruder silo
	var es := _build_unmerged("extruder_silo")
	await get_tree().process_frame
	var ep := _panes(es)
	_check(ep.size() == 8, "S1 extruder silo has 8 windows (%d)" % ep.size())
	var on_long := 0
	var on_short := 0
	var vertical := true
	for w in ep:
		var nrm : Vector3 = w["normal"]
		if absf(nrm.x) > 0.99:
			on_long += 1
		elif absf(nrm.z) > 0.99:
			on_short += 1
		var sz : Vector2 = w["size"]
		if sz.y <= sz.x:
			vertical = false
	_check(on_long == 8 and on_short == 0, "S1 extruder silo windows are all on the LONG (x) faces, none on the short faces (%d / %d)" % [on_long, on_short])
	_check(vertical, "S1 extruder silo windows are vertical (taller than wide)")
	var es_fill := es.find_child("SiloFill", true, false) as Node3D
	if es_fill != null and ep.size() == 8:
		var base : float = float(es_fill.get_meta("silo_fill_base_y"))
		var rng : float = float(es_fill.get_meta("silo_fill_range_y"))
		var cy : float = base + rng * 0.5
		var bd : float = 0.0
		for w in ep:
			bd = maxf(bd, absf((w["pos"] as Vector3).z))
		# inner sub-quadrant: |dz| and |dy| equal to a quarter of the half-extents
		var ok_cluster := true
		var min_gap_y := 9.0
		var min_gap_z := 9.0
		for i in ep.size():
			var pi : Vector3 = ep[i]["pos"]
			if absf(absf(pi.y - cy) - rng * 0.125) > 0.01:
				ok_cluster = false
			for j in ep.size():
				if i == j:
					continue
				var pj : Vector3 = ep[j]["pos"]
				if (ep[i]["normal"] as Vector3).dot(ep[j]["normal"]) < 0.9:
					continue
				if absf(pi.y - pj.y) > 0.01:
					min_gap_y = minf(min_gap_y, absf(pi.y - pj.y) - (ep[i]["size"] as Vector2).y)
				if absf(pi.z - pj.z) > 0.01:
					min_gap_z = minf(min_gap_z, absf(pi.z - pj.z) - (ep[i]["size"] as Vector2).x)
		_check(ok_cluster, "S1 extruder silo windows sit an eighth of the box height above and below its centre")
		_check(min_gap_y > 0.05 and min_gap_z > 0.05, "S1 extruder silo windows do not touch (gaps %.2f m vertical, %.2f m along the face)" % [min_gap_y, min_gap_z])
		_check(bd > 0.0 and bd < rng, "S1 extruder silo window pairs sit %.2f m either side of the face centre (inner half)" % bd)
	# VSS: none
	var vss := PlaceableCatalog.build_node("vss_silo", false)
	if vss != null:
		add_child(vss)
		await get_tree().process_frame
		_check(vss.find_child("SiloFill", true, false) == null and _panes(vss).is_empty(), "S1 the VSS has no level window (operator: none)")
		vss.queue_free()
	# keep ds / ms / es for S2
	await _s2(ds, ms, es)
	ds.queue_free(); ms.queue_free(); es.queue_free()

# ── S2 ─────────────────────────────────────────────────────────────────────────
func _witness_state(fill: Node3D) -> Array:
	var out : Array = []
	for h in fill.get_children():
		if not h.has_meta("win_bottom_y"):
			continue
		var wit := h.get_node_or_null("LevelWitness") as MeshInstance3D
		var hgt : float = (wit.mesh as BoxMesh).size.y if (wit != null and wit.visible) else 0.0
		out.append({"holder": h, "wit": wit, "h": hgt, "wb": float(h.get_meta("win_bottom_y")),
			"wt": float(h.get_meta("win_top_y")), "ys": float(h.get_meta("win_y_scale")), "wh": float(h.get_meta("win_h"))})
	return out

func _s2(ds: Node3D, ms: Node3D, es: Node3D) -> void:
	for pair in [["doseersilo", ds], ["mengsilo", ms], ["extruder_silo", es]]:
		var label : String = pair[0]
		var root : Node3D = pair[1]
		var fill := root.find_child("SiloFill", true, false) as Node3D
		if fill == null:
			_check(false, "S2 %s has a SiloFill" % label)
			continue
		var base : float = float(fill.get_meta("silo_fill_base_y"))
		var rng : float = float(fill.get_meta("silo_fill_range_y"))
		PlaceableCatalog.set_silo_fill(root, 0.0, fill)
		var st0 := _witness_state(fill)
		var all_hidden := true
		for w in st0:
			if w["h"] > 0.0:
				all_hidden = false
		_check(all_hidden and st0.size() > 0, "S2 %s empty: all %d witnesses hidden" % [label, st0.size()])
		PlaceableCatalog.set_silo_fill(root, 1.0, fill)
		var st1 := _witness_state(fill)
		var all_full := true
		for w in st1:
			if absf(float(w["h"]) - float(w["wh"])) > 1e-4:
				all_full = false
		_check(all_full, "S2 %s full: every witness fills its window" % label)
		# a level through the middle of the first window: the witness top sits ON the level line
		var w0 : Dictionary = st1[0]
		var mid_y : float = (float(w0["wb"]) + float(w0["wt"])) * 0.5
		var frac_mid : float = (mid_y - base) / rng
		PlaceableCatalog.set_silo_fill(root, frac_mid, fill)
		var stm := _witness_state(fill)
		var wm : Dictionary = stm[0]
		var expect_h : float = (mid_y - float(wm["wb"])) / float(wm["ys"])
		_check(absf(float(wm["h"]) - expect_h) < 1e-4, "S2 %s level mid-window: witness %.3f m tall (window %.3f)" % [label, float(wm["h"]), float(wm["wh"])])
		# the witness's top edge, in machine y, equals the level line — also on a sloped wall
		var wit : MeshInstance3D = wm["wit"]
		var holder : Node3D = wm["holder"]
		var top_local := Vector3(0.0, wit.position.y + float(wm["h"]) * 0.5, 0.0)
		var top_machine_y : float = (holder.transform * top_local).y
		_check(absf(top_machine_y - mid_y) < 1e-3, "S2 %s witness top at machine y %.3f == level %.3f (wall y-scale %.2f)" % [label, top_machine_y, mid_y, float(wm["ys"])])
		# monotonic over 20 steps
		var last := -1.0
		var mono := true
		for k in 21:
			PlaceableCatalog.set_silo_fill(root, float(k) / 20.0, fill)
			var tot := 0.0
			for w in _witness_state(fill):
				tot += float(w["h"])
			if tot < last - 1e-6:
				mono = false
			last = tot
		_check(mono, "S2 %s witness heights never decrease as the level rises" % label)
		_check(absf(float(fill.get_meta("silo_fill_frac")) - 1.0) < 1e-6, "S2 %s SiloFill records the last fraction" % label)

# ── S3 ─────────────────────────────────────────────────────────────────────────
func _s3() -> void:
	var body : Node3D = PlaceableCatalog.build_node("mengsilo", false)
	_check(body != null, "S3 build_node(mengsilo)")
	if body == null:
		return
	add_child(body)
	await get_tree().process_frame
	var fill := body.find_child("SiloFill", true, false) as Node3D
	_check(fill != null, "S3 SiloFill survives StaticMerge (no_merge)")
	if fill == null:
		return
	var wits := _witness_state(fill)
	_check(wits.size() == 1 and wits[0]["wit"] != null, "S3 the witness mesh survives the merge")
	var lf := LineFlow.new()
	add_child(lf)
	lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	await get_tree().process_frame
	lf.set("feed_enabled", false)
	lf.call("rebuild")
	await get_tree().process_frame
	var nodes : Array = lf.get("_nodes")
	var nd : Dictionary = {}
	for n in nodes:
		if String(n.get("id", "")) == "mengsilo":
			nd = n
	_check(not nd.is_empty(), "S3 LineFlow discovered the mengsilo")
	if nd.is_empty():
		return
	_check(nd.get("silo_fill") == fill, "S3 the node carries its SiloFill")
	lf.call("start_line")
	var bin : MaterialBatch = nd.get("in", null) as MaterialBatch
	var kg : float = LineFlow.SILO_FULL_KG * 0.5
	bin.add(MaterialBatch.new(kg, kg / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
	lf.tick(TICK_S)
	var frac : float = float(fill.get_meta("silo_fill_frac"))
	var buf : float = float(nd["buffer"])
	_check(absf(frac - clampf(buf / LineFlow.SILO_FULL_KG, 0.0, 1.0)) < 1e-6 and frac > 0.3,
		"S3 after one tick the glass reads %.2f = buffer %.1f kg / SILO_FULL_KG %.0f" % [frac, buf, LineFlow.SILO_FULL_KG])
	for _t in 20:
		lf.tick(TICK_S)
	var frac2 : float = float(fill.get_meta("silo_fill_frac"))
	_check(frac2 < frac and frac2 > 0.0, "S3 the level falls as the silo discharges (%.2f -> %.2f after 2 s)" % [frac, frac2])
	body.queue_free()
	lf.queue_free()

# ── S4: the compactor kijkglas rides the same witness ─────────────────────────
func _s4() -> void:
	var cc : Node3D = PlaceableCatalog.build_node("compactor", false)
	_check(cc != null, "S4 build_node(compactor)")
	if cc == null:
		return
	add_child(cc)
	await get_tree().process_frame
	var panes := _panes(cc)
	_check(panes.size() == 1 and absf((panes[0]["size"] as Vector2).x - 0.24) < 1e-6, "S4 the compactor carries one 0.24 m kijkglas port (%d)" % panes.size())
	var pf := cc.find_child("PotFill", true, false) as MeshInstance3D
	var fill := cc.find_child("SiloFill", true, false) as Node3D
	_check(pf != null and fill != null, "S4 PotFill and the kijkglas witness root both exist")
	if pf == null or fill == null:
		cc.queue_free()
		return
	var ky : float = float(pf.get_meta("kijkglas_y"))
	_check(panes.size() == 1 and absf((panes[0]["pos"] as Vector3).y - ky) < 0.01, "S4 the port sits at the kijkglas height %.2f m" % ky)
	PlaceableCatalog.set_pot_fill(cc, 0.20)
	var w20 := _witness_state(fill)
	PlaceableCatalog.set_pot_fill(cc, 0.33)
	var w33 := _witness_state(fill)
	PlaceableCatalog.set_pot_fill(cc, 0.50)
	var w50 := _witness_state(fill)
	_check(w20.size() == 1 and float(w20[0]["h"]) == 0.0, "S4 at 20 % pot load the glass shows nothing (below the window)")
	_check(w33.size() == 1 and float(w33[0]["h"]) > 0.01 and float(w33[0]["h"]) < 0.24, "S4 at 33 % the level line is IN the glass (%.3f of 0.24 m)" % float(w33[0]["h"]))
	_check(w50.size() == 1 and absf(float(w50[0]["h"]) - 0.24) < 1e-4, "S4 at 50 % the glass is full")
	cc.queue_free()

# ── main ───────────────────────────────────────────────────────────────────────
func _run() -> void:
	print("[TEST] silo level windows — P5")
	await _s1()
	await _s3()
	await _s4()
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
