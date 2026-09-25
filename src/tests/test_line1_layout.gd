extends Node
## LINE 1 — every placement the operator gave on 2026-09-25, measured.
##
##   godot --headless --path . res://src/tests/test_line1_layout.tscn
##
## The operator laid out line 1's head and wet street from plan and side renders
## (docs/plant/operator_rulings_2026-09-25.md, "Line 1's wet tail", L1-L8). Each
## ruling is a distance between two machines ("flush", "30 cm", "6 m", "on the
## centre line"), so each check here measures the two built machines against
## each other, in the leg frame the macro stamps on them (macro_anchor), with a
## 2 cm tolerance. The SEQ numbers that produce these positions are derived in
## BuildMode.LINE_1_SEQ's comments; this file is what fails when one of them, or
## a model they were derived from, moves.
##
## Built like test_line1_overband_mount: a bare BuildMode, no world, so no
## building shell hides a leg and nothing is saved.

const TOL : float = 0.02

var _fails : int = 0
var _ok : int = 0
var _by_idx : Dictionary = {}

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_ok += 1
	else:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _aabb(root: Node3D) -> AABB:
	var out := AABB()
	var seeded := false
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree() or mi.top_level:
			continue
		var w : AABB = mi.global_transform * mi.get_aabb()
		if not seeded:
			out = w
			seeded = true
		else:
			out = out.merge(w)
	return out

## The leg frame a node was placed in: {start, fwd, rgt}.
func _leg(n: Node3D) -> Dictionary:
	var anc : Dictionary = n.get_meta("macro_anchor", {}) as Dictionary
	var r : float = float(anc.get("rot_y", 0.0))
	return {"start": anc.get("start", Vector3.ZERO) as Vector3,
		"fwd": Vector3(-sin(r), 0.0, -cos(r)), "rgt": Vector3(cos(r), 0.0, -sin(r))}

func _along(p: Vector3, leg: Dictionary) -> float:
	return (p - (leg["start"] as Vector3)).dot(leg["fwd"] as Vector3)

func _lat(p: Vector3, leg: Dictionary) -> float:
	return (p - (leg["start"] as Vector3)).dot(leg["rgt"] as Vector3)

## [min, max] of an AABB projected on a leg direction ("fwd" or "rgt").
func _span(b: AABB, leg: Dictionary, axis: String) -> Array:
	var dir : Vector3 = leg[axis]
	var lo : float = INF
	var hi : float = -INF
	for i in 8:
		var v : float = (b.get_endpoint(i) - (leg["start"] as Vector3)).dot(dir)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	return [lo, hi]

## The node at the n-th SEQ entry with this id (0-based among that id).
func _nth(id: String, n: int = 0) -> Node3D:
	var k := 0
	for i in BuildMode.LINE_1_SEQ.size():
		if String((BuildMode.LINE_1_SEQ[i] as Dictionary).get("id", "")) == id:
			if k == n:
				return _by_idx.get(i) as Node3D
			k += 1
	return null

func _has_meta_below(n: Node, key: String) -> bool:
	for c in n.find_children("*", "", true, false):
		if (c as Node).has_meta(key):
			return true
	return false

## Horizontal throw of a particle leaving at speed v, `ang` deg above level,
## landing `drop` m lower (the operator's method: speed, drop, spread).
func _throw(v: float, drop: float, ang: float) -> float:
	var a : float = deg_to_rad(ang)
	var vx : float = v * cos(a)
	var vy : float = v * sin(a)
	return vx * (vy + sqrt(vy * vy + 2.0 * 9.81 * drop)) / 9.81

func _run() -> void:
	print("[TEST] line 1 — the operator's 2026-09-25 layout, measured")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3(-142.7, 0.0, 42.9), 0.0)
	await get_tree().process_frame
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 != null and n3.has_meta("macro_id") and String(n3.get_meta("macro_id")) == "line_1":
			_by_idx[int(n3.get_meta("macro_index"))] = n3
	_check(_by_idx.size() == BuildMode.LINE_1_SEQ.size(),
		"every LINE_1_SEQ entry was built (%d of %d)" % [_by_idx.size(), BuildMode.LINE_1_SEQ.size()])
	_head()
	_street()
	_tank_and_mill()
	print("\n[TEST] %d ok, %d fail" % [_ok, _fails])
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 else "FAIL", _ok, _fails])
	get_tree().quit(0 if _fails == 0 else 1)

# ── L4/L5: Westa, shredder, uitvoerband, magnet, receiving belt ─────────────────
func _head() -> void:
	print("  -- head (L4, L5) --")
	var wsta := _nth("westa_band_1")
	var shr := _nth("shredder_1")
	var u := _nth("uitvoerband_1")
	var m := _nth("overband_magnet_l1")
	var dfb := _nth("drum_feed_belt")
	var r : Node3D = null
	if u != null:
		var iu : int = int(u.get_meta("macro_index"))
		for i in range(iu + 1, BuildMode.LINE_1_SEQ.size()):
			if String((BuildMode.LINE_1_SEQ[i] as Dictionary).get("id", "")) == "transport_belt":
				r = _by_idx.get(i) as Node3D
				break
	_check(wsta != null and shr != null and u != null and m != null and r != null and dfb != null,
		"head machines found (westa, shredder_1, uitvoerband_1, overband_magnet_l1, receiving belt, drum_feed_belt)")
	if wsta == null or shr == null or u == null or m == null or r == null or dfb == null:
		return
	var ssz : Vector3 = PlaceableCatalog.get_item("shredder_1")["size"]
	# Westa: "sticks into the shredder hopper about 30 centimeters", and climbs
	# until it clears the rim ("Westa should climb steeper").
	var la := _leg(wsta)
	var lip : Vector3 = wsta.call("_discharge_lip_pos")
	var collar_near : float = _along(shr.global_position, la) - ssz.z * 1.04 * 0.5
	var into : float = _along(lip, la) - collar_near
	_check(absf(into - PlaceableCatalog.SHREDDER_1_HOPPER_OVERLAP_M) <= TOL,
		"L4 the Westa's lip is 0.30 m into the shredder's hopper (%.3f)" % into)
	var over_rim : float = lip.y - (shr.global_position.y + ssz.y)
	_check(over_rim > 0.05 and over_rim < 0.6,
		"L4 the Westa's lip clears the hopper rim (%.3f m above it)" % over_rim)
	# Uitvoerband: under the rotors, tail 0.10 past their end, end 2.50 past the
	# other end, flat to 0.30 past the shredder, then 20°.
	var lb := _leg(u)
	var s_al : float = _along(shr.global_position, lb)
	var rotor_half : float = ssz.x * 0.86 * 0.5
	var tail_al : float = _along(u.global_position, lb)
	_check(absf((s_al - tail_al) - (rotor_half + 0.10)) <= TOL,
		"L5 the uitvoerband starts 0.10 m past the rotors' end (%.3f)" % (s_al - tail_al - rotor_half))
	var u_len : float = float(u.get("deck_length")) + float(u.get("incline_run")) + float(u.get("top_flat_m"))
	_check(absf((tail_al + u_len - s_al) - (rotor_half + 2.50)) <= TOL,
		"L5 the uitvoerband ends 2.50 m past the rotors' other end (%.3f)" % (tail_al + u_len - s_al - rotor_half))
	_check(absf(_lat(u.global_position, lb) - _lat(shr.global_position, lb)) <= TOL,
		"L5 the uitvoerband is centred on the rotors (%.3f m off)" % (_lat(u.global_position, lb) - _lat(shr.global_position, lb)))
	var flat_past : float = tail_al + float(u.get("deck_length")) - s_al - ssz.x * 0.5
	_check(absf(flat_past - 0.30) <= TOL,
		"L5 it runs flat until 0.30 m past the shredder (%.3f)" % flat_past)
	_check(absf(float(u.get("incline_deg")) - 20.0) < 0.01,
		"L5 then climbs at 20° (%.2f°)" % float(u.get("incline_deg")))
	_check(not _has_meta_below(shr, "shredder_discharge_conveyor"),
		"L5 line 1's shredder has no conveyor of its own (\"a single conveyor\")")
	# Receiving belt: centred on the landing point of the throw, its tail 0.30 m
	# past the uitvoerband's edge, in line with the drum-feed belt.
	var u_lip : Vector3 = u.call("_discharge_lip_pos")
	var r_deck : float = r.global_position.y + 0.675
	var land : float = _along(u_lip, lb) + _throw(float(u.get("belt_speed")), u_lip.y - r_deck, 20.0)
	_check(absf(_along(r.global_position, lb) - land) <= TOL,
		"L5 the receiving belt is centred on the throw's landing point (%.3f m off)" % (_along(r.global_position, lb) - land))
	var lc := _leg(r)
	var r_tail : float = _along(r.global_position, lc) - 2.0
	var past_edge : float = _along(lc["start"], lc) - r_tail - 0.5
	_check(absf(past_edge - 0.30) <= TOL,
		"L5 its tail starts 0.30 m past the uitvoerband's edge (%.3f)" % past_edge)
	_check(absf(_lat(dfb.global_position, lc) - _lat(r.global_position, lc)) <= TOL,
		"the receiving belt and the drum-feed belt share a centre line (%.3f m off)"
			% (_lat(dfb.global_position, lc) - _lat(r.global_position, lc)))
	var seam : float = _along(dfb.global_position, lc) - (_along(r.global_position, lc) + 2.0)
	_check(absf(seam) <= 0.05, "the drum-feed belt starts where the receiving belt ends (%.3f m)" % seam)
	var step : float = r_deck - (dfb.global_position.y + float(dfb.get("deck_height")))
	_check(step > 0.0 and step <= 0.1, "the transfer drops %.3f m (0 < drop <= 0.1)" % step)
	# Magnet: cross-belt, centred midway between the receiving belt's near edge
	# and the shredder's collar face, 0.20 m toward the top, 0.25 m over the deck.
	var r_near : float = float(_span(_aabb(r), lb, "fwd")[0])
	var mid : float = (s_al + ssz.x * 1.12 * 0.5 + r_near) * 0.5
	_check(absf(_along(m.global_position, lb) - mid) <= TOL,
		"L5 the magnet sits on the midpoint line (%.3f m off)" % (_along(m.global_position, lb) - mid))
	var m_lat : float = _lat(m.global_position, lb) - _lat(u.global_position, lb)
	_check(absf(m_lat - 0.20) <= TOL, "L5 the magnet is 0.20 m toward the top (%.3f)" % m_lat)
	var mb := _aabb(m)
	var m_along_ext : Array = _span(mb, lb, "fwd")
	var m_lat_ext : Array = _span(mb, lb, "rgt")
	_check(float(m_lat_ext[1]) - float(m_lat_ext[0]) > float(m_along_ext[1]) - float(m_along_ext[0]),
		"L5 its belt runs ACROSS the uitvoerband (%.2f across, %.2f along)"
			% [float(m_lat_ext[1]) - float(m_lat_ext[0]), float(m_along_ext[1]) - float(m_along_ext[0])])
	var msz : Vector3 = PlaceableCatalog.get_item("overband_magnet")["size"]
	var low : float = m.global_position.y + msz.y * 0.80 - msz.y * 0.22 * 0.5
	var flat_end : float = tail_al + float(u.get("deck_length"))
	var probe : float = _along(m.global_position, lb) + msz.x * 0.62 * 0.5
	var deck : float = float(u.get("deck_height")) + maxf(0.0, probe - flat_end) * tan(deg_to_rad(20.0))
	_check(absf((low - deck) - PlaceableCatalog.OVERBAND_CLEARANCE_M) <= TOL,
		"L5 its lowest part is 0.25 m over the deck under it (%.3f)" % (low - deck))
	var cg : Dictionary = load("res://src/scenes/world/ContainerGuide.gd").SLOT_REGISTRY
	var slot : Vector3 = m.to_global((cg["overband_magnet_l1"] as Array)[0]["offset"] as Vector3)
	_check(_lat(slot, lb) - _lat(u.global_position, lb) < -1.5,
		"L5 the scrap skip stands on the far side from the receiving belt (%.2f m)" % (_lat(slot, lb) - _lat(u.global_position, lb)))

# ── L6: drum, scheidingsgoot, separators, dryers, blowers, stair ───────────────
func _street() -> void:
	print("  -- wet street (L6) --")
	var drum := _nth("vw_trommel")
	var goot := _nth("scheidingsgoot")
	var fl := _nth("friction_sep", 0)
	var fr := _nth("friction_sep", 1)
	var dl := _nth("mech_dryer", 0)
	var dr := _nth("mech_dryer", 1)
	var bl := _nth("blower", 0)
	var br := _nth("blower", 1)
	_check(drum != null and goot != null and fl != null and fr != null and dl != null and dr != null
		and bl != null and br != null, "wet-street machines found")
	if drum == null or goot == null or fl == null or fr == null or dl == null or dr == null or bl == null or br == null:
		return
	var ld := _leg(drum)
	var dsz : Vector3 = PlaceableCatalog.get_item("vw_trommel")["size"]
	var d_al : float = _along(drum.global_position, ld)
	var shell_end : float = d_al + PlaceableCatalog.vw_trommel_discharge_lip_local(dsz).z
	var hood_end : float = d_al + PlaceableCatalog.vw_trommel_hood_end_z(dsz)
	var gb := _aabb(goot)
	_check(absf(float(_span(gb, ld, "fwd")[0]) - shell_end) <= TOL,
		"L6 the scheidingsgoot sits flush against the drum's end (%.3f)" % (float(_span(gb, ld, "fwd")[0]) - shell_end))
	var lip_y : float = drum.global_position.y + PlaceableCatalog.vw_trommel_discharge_lip_local(dsz).y
	_check(gb.end.y < lip_y and lip_y - gb.end.y <= 0.15,
		"L6 its inlet sits just under the drum's lip (%.3f m under)" % (lip_y - gb.end.y))
	var g_lat : float = _lat(goot.global_position, ld)
	var gsz : Vector3 = PlaceableCatalog.get_item("scheidingsgoot")["size"]
	for f in [fl, fr]:
		var fb := _aabb(f as Node3D)
		var lat_ext : Array = _span(fb, ld, "rgt")
		var side : float = 1.0 if _lat((f as Node3D).global_position, ld) > g_lat else -1.0
		var inner : float = float(lat_ext[0]) if side > 0.0 else float(lat_ext[1])
		var gap : float = (inner - g_lat) * side - gsz.x * 0.5
		_check(absf(gap) <= TOL, "L6 a separator sits flush against the goot's side (%.3f)" % gap)
		_check(absf(float(_span(fb, ld, "fwd")[0]) - hood_end) <= TOL,
			"L6 its upstream end is level with the drum's hood (%.3f)" % (float(_span(fb, ld, "fwd")[0]) - hood_end))
		# Low at the inlet, rising toward the dryer. StaticMerge bakes the
		# housing into one mesh, but its legs stay separate (they are stretched
		# at placement): the tallest one stands at the discharge end.
		var tallest_al : float = -INF
		var tallest_h : float = -1.0
		for mm in (f as Node3D).find_children("*", "MeshInstance3D", true, false):
			var lg := mm as MeshInstance3D
			if lg.is_in_group("machine_leg") and float(lg.get_meta("leg_h", 0.0)) > tallest_h:
				tallest_h = float(lg.get_meta("leg_h", 0.0))
				tallest_al = _along(lg.global_position, ld)
		_check(tallest_h > 0.5 and tallest_al > _along((f as Node3D).global_position, ld),
			"L6 the separator's housing rises from its inlet toward the dryer (tallest leg %.2f m, downstream)" % tallest_h)
	var fr_model := fr.get_node_or_null("Model") as Node3D
	_check(fr_model != null and fr_model.scale.x < 0.0, "L6 the right-hand separator is mirrored (motor outside)")
	var gl : Array = _span(gb, ld, "rgt")
	_check(minf(g_lat - float(gl[0]), float(gl[1]) - g_lat) >= absf(_lat(fl.global_position, ld) - g_lat) - 0.05,
		"L6 the goot's legs reach over both separators' hoppers")
	for pair in [[fl, dl, bl], [fr, dr, br]]:
		var f : Node3D = pair[0]
		var d : Node3D = pair[1]
		var b : Node3D = pair[2]
		var seam : float = float(_span(_aabb(d), ld, "fwd")[0]) - float(_span(_aabb(f), ld, "fwd")[1])
		_check(absf(seam) <= TOL, "L6 a dryer starts where its separator ends (%.3f)" % seam)
		_check(absf(_lat(d.global_position, ld) - _lat(f.global_position, ld)) <= TOL,
			"L6 ... on the same centre line (%.3f)" % (_lat(d.global_position, ld) - _lat(f.global_position, ld)))
		var outward : float = 1.0 if _lat(d.global_position, ld) > g_lat else -1.0
		var dsz2 : Vector3 = PlaceableCatalog.get_item("mech_dryer")["size"]
		var stub_edge : float = _lat(d.global_position, ld) + outward * dsz2.x * 0.42 * 0.22
		var b_ext : Array = _span(_aabb(b), ld, "rgt")
		var b_inner : float = float(b_ext[0]) if outward > 0.0 else float(b_ext[1])
		var clear : float = (b_inner - stub_edge) * outward
		_check(absf(clear - 0.30) <= TOL, "L6 a blower stands 0.30 m from its dryer's outlet stub (%.3f)" % clear)
		var motor_dir : Vector3 = -b.global_transform.basis.x.normalized()
		_check(motor_dir.dot(ld["rgt"] as Vector3) * outward > 0.9, "L6 ... with its motor pointing outward")
	# Stair: from the walkway's outer side, down to the floor, its left side
	# against the dewatering screw's right side.
	var fs := drum.find_child("FloorStair", true, false) as Node3D
	var screw := _nth("dewater_screw_l1")
	_check(fs != null and screw != null, "the drum's stair and the dewatering screw found")
	if fs != null and screw != null:
		var sb := _aabb(fs)
		_check(sb.position.y <= 0.05, "L6 the stair reaches the floor (foot at %.3f m)" % sb.position.y)
		var st_hi : float = float(_span(sb, ld, "fwd")[1])
		var sc_lo : float = float(_span(_aabb(screw), ld, "fwd")[0])
		_check(absf(st_hi - sc_lo) <= TOL,
			"L7 the stair's left side is against the dewatering screw's right side (%.3f)" % (st_hi - sc_lo))

# ── L7: tank, walkway, mill ────────────────────────────────────────────────────
func _tank_and_mill() -> void:
	print("  -- tank and mill (L7) --")
	var drum := _nth("vw_trommel")
	var tank := _nth("flotation_tank")
	var mill := _nth("mill")
	var dr := _nth("mech_dryer", 1)
	_check(drum != null and tank != null and mill != null and dr != null, "tank, mill, drum found")
	if drum == null or tank == null or mill == null or dr == null:
		return
	var ld := _leg(drum)
	_check(not _has_meta_below(tank, "tank_catwalk"), "L7 line 1's tank has no catwalk of its own")
	var tsz : Vector3 = PlaceableCatalog.get_item("flotation_tank")["size"]
	var dsz : Vector3 = PlaceableCatalog.get_item("vw_trommel")["size"]
	var walk_lat : float = _lat(drum.global_position, ld) + minf(dsz.x * 0.46, 1.55) + 0.95 * 0.5 + 0.05
	var cat_lat : float = _lat(tank.global_position, ld) - (tsz.x * 0.46 + 0.16 + 0.60)
	_check(absf(cat_lat - walk_lat) <= TOL,
		"L7 where the tank's catwalk was lines up with the drum's walkway (%.3f)" % (cat_lat - walk_lat))
	var gap : float = float(_span(_aabb(mill), ld, "fwd")[0]) - float(_span(_aabb(tank), ld, "fwd")[1])
	_check(absf(gap - 6.0) <= TOL, "L7 tank's leftmost point to mill's rightmost point: %.3f m (6.0)" % gap)
	_check(absf(_lat(mill.global_position, ld) - _lat(tank.global_position, ld)) <= TOL,
		"L7 the mill is on the tank's centre line (%.3f)" % (_lat(mill.global_position, ld) - _lat(tank.global_position, ld)))
	var t_lat : Array = _span(_aabb(tank), ld, "rgt")
	var d_lat : Array = _span(_aabb(dr), ld, "rgt")
	_check(float(t_lat[0]) >= float(d_lat[1]) - 0.001,
		"L7 the tank clears the right-hand dryer (%.3f m)" % (float(t_lat[0]) - float(d_lat[1])))
	# The dewatering screw (L3): it runs across the tank's discharge end, turning
	# LEFT of the tank's travel, "the left bottom corner of the dewatering screw
	# with the right bottom corner of the flotation tank" and "1.5 meters
	# sticking out" past its other side. Measured on the two catalog footprints
	# (the 6 m screw body, the 4.5 m tank box), across the drum's leg: the tank
	# travels back along it, so the tank's right side is the drum's left (-rgt).
	var screw := _nth("dewater_screw_l1")
	_check(screw != null, "the dewatering screw found")
	if screw == null:
		return
	var ssz : Vector3 = PlaceableCatalog.get_item("dewater_screw_l1")["size"]
	var t_c : float = _lat(tank.global_position, ld)
	var s_c : float = _lat(screw.global_position, ld)
	var t_right : float = t_c - tsz.x * 0.5
	var t_left : float = t_c + tsz.x * 0.5
	var s_in : float = s_c - ssz.z * 0.5
	var s_out : float = s_c + ssz.z * 0.5
	_check(absf(s_in - t_right) <= TOL,
		"L3 the screw's low end is flush with the tank's right side (%.3f)" % (s_in - t_right))
	_check(absf((s_out - t_left) - 1.5) <= TOL,
		"L3 its high end sticks out 1.5 m past the tank's left side (%.3f)" % (s_out - t_left))
	# A placed machine's downstream is its local +Z (rotation = leg + PI).
	var s_fw : Vector3 = screw.global_transform.basis.z
	_check(s_fw.dot(ld["rgt"] as Vector3) > 0.99,
		"L3 the screw runs to the LEFT of the tank's travel, across it (%.3f)" % s_fw.dot(ld["rgt"] as Vector3))
	# "The tank and the dewatering screw should not overlap": the two bodies
	# (catalog boxes) meet flush. The tank's weir chute hangs 0.74 m off its
	# discharge wall at 35° on purpose (the overflow INTO the screw), so the
	# tank's mesh reaches over the screw, and must not reach past it.
	var t_lo : float = _along(tank.global_position, ld) - tsz.z * 0.5
	var s_hi : float = _along(screw.global_position, ld) + ssz.x * 0.5
	_check(absf(t_lo - s_hi) <= TOL,
		"L3 the screw's body meets the tank's body flush, no overlap (%.3f m apart)" % (t_lo - s_hi))
	var t_mesh_lo : float = float(_span(_aabb(tank), ld, "fwd")[0])
	var s_mesh : Array = _span(_aabb(screw), ld, "fwd")
	_check(t_mesh_lo < t_lo - 0.3 and t_mesh_lo > float(s_mesh[0]),
		"L3 the tank's weir chute reaches over the screw (%.3f m) but not past it (%.3f m to spare)"
			% [t_lo - t_mesh_lo, t_mesh_lo - float(s_mesh[0])])
