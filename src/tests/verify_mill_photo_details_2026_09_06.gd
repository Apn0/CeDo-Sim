extends Node3D
## Measures the four photo details added to the maalmolen on 2026-09-06 against
## the mill they were added to:
##   1. the hopper-lid CLAMP BANK on the +X hopper wall
##   2. the motor FAN COWL, its chord-fitted grille and the yellow sticker
##   3. the `.com` suffix on the NEUE HERBOLD wordmark
##   4. the under-deck discharge: GREY finish (was dark-aged) + bolted access
##      plate and name sticker
##
## Sibling of verify_mill_addons_2026_08_30.gd and follows its idiom: builds via
## `_build_model()` directly, so `StaticMerge.merge_static` does not bake the
## loop bodies away and every part is countable.
##
##   <godot> --path . res://src/tests/verify_mill_photo_details_2026_09_06.tscn --quit-after 12

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
	print("[PHOTO0906] parts real=%d ghost=%d" % [real_parts, _count(groot)])

	# Frame constants, re-derived here rather than copied from the builder, so a
	# silent change to the builder's own constants shows up as a failure.
	var deck_y := sz.y * 0.40
	var hw := sz.x * 0.40
	var hd := sz.z * 0.34
	var ch_h := sz.y * 0.26
	var base_y := deck_y + 0.06
	var ch_top := base_y + ch_h
	var ch_hz := hd * 0.50
	var hop_h := 0.99
	var mouth_hx := 1.12
	var hop_top := ch_top + hop_h
	var mot_r := 0.26
	var mot_x := hw * 0.833 - 0.40
	var mot_y := deck_y + 0.01 + 0.03 + 0.03 + mot_r
	var mot_z := -(ch_hz + 0.36)
	var cowl_r := mot_r * 1.10
	var gr := cowl_r * 0.72

	var parts: Array = []
	_collect(root, parts)
	print("[PHOTO0906] measured %d meshes" % parts.size())

	# ── 1. hopper-lid clamp bank ─────────────────────────────────────────────
	# Collected from the BUILDER'S OWN `HopperClamps` node, not from a bounding
	# region. That distinction is load-bearing and was found by mutation: with a
	# region of x >= 0.80, "the bank hangs outside the wall face" could never go
	# red, because any part that sank into the wall simply left the region and
	# the surviving union still started at x >= 0.80. The check passed by
	# construction. Sinking the whole bank 130 mm into the hopper (mutation M12)
	# left it green. Reading the node makes every span check below real.
	var bank: Array = []
	var bank_node := _find(root, "HopperClamps")
	if bank_node != null:
		_collect(bank_node, bank)
	_check("clamp bank present on the +X hopper wall", bank.size() >= 15,
		"%d parts under HopperClamps" % bank.size())
	var bank_a := _union(bank)
	print("[PHOTO0906] bank pos=%s size=%s" % [str(bank_a.position), str(bank_a.size)])
	_check("bank hangs OUTSIDE the hopper's +X flare panel face",
		bank_a.position.x > 0.78,
		"bank minX %.4f vs panel outer face ~0.810" % bank_a.position.x)
	_check("bank does not overhang the machine footprint (maxX < hw)",
		bank_a.position.x + bank_a.size.x < hw,
		"bank maxX %.4f vs hw %.4f" % [bank_a.position.x + bank_a.size.x, hw])
	# The rim stiffener is a real box at y = hop_top + 0.03; an AABB test, not a
	# coordinate comparison, because the two DO overlap in X and Z.
	var rim := AABB(Vector3(mouth_hx - 0.05, hop_top, -0.10 - 0.731),
		Vector3(0.10, 0.06, 1.462))
	_check("bank clears the hopper's own +X rim stiffener",
		not bank_a.intersects(rim),
		"bank maxY %.4f vs stiffener base %.4f" % [bank_a.position.y + bank_a.size.y, hop_top])
	# Three dark contact pads at the outer tip of the three brackets.
	var pads := _region(parts, 1.24, 1.40, 3.95, 4.15, -0.65, 0.55)
	_check("THREE dark contact pads, one per bracket", pads.size() == 3,
		"%d pads" % pads.size())
	# Two spindle barrel nuts, in the band between the ribs and the hoses.
	var nuts := _region(parts, 1.05, 1.20, 3.86, 3.97, -0.65, 0.55)
	_check("TWO spindle barrel nuts", nuts.size() == 2, "%d nuts" % nuts.size())
	# Cheap but real: the bank must span the wall, not bunch at one end.
	_check("bank spans the wall in Z (three brackets, not one)",
		bank_a.size.z > 0.80,
		"bank Z span %.4f" % bank_a.size.z)

	# ── 2. motor fan cowl, grille, sticker ───────────────────────────────────
	# X upper bound is 0.56, not 0.58: the FIRST cooling fin ring sits at
	# x = mot_x - mot_len * 0.36 = 0.5763 and would otherwise be swept in.
	var cowl := _region(parts, 0.28, 0.56, 1.90, 2.60, -1.45, -0.85)
	# NOT a bare count: the +BP2 cabinet's cable bundle can run into this band on
	# its way to the motor, so `cowl.size()` is not the cowl's own part count. The
	# barrel is found by SHAPE instead — it is the only part that is tall
	# (0.572 m across) and mid-length in X (0.16 m); the five cooling fin rings
	# are tall too but only 0.03 m long, and the motor body is 0.62 m.
	#
	# The search spans the whole motor length up to X 1.60, past the drive end,
	# on purpose. Mutation M15 moved the cowl to the WRONG (drive) end and, with
	# the search stopping at 1.10, the barrel simply fell out of it: "the cowl is
	# on the non-drive end" was SKIPPED rather than failed. Reaching past the
	# drive end is what makes that check able to go red at all.
	var barrel: Array = []
	for cb in _region(parts, 0.28, 1.60, 1.90, 2.60, -1.45, -0.85):
		var ca: AABB = cb
		# The cross-section gate is what keeps the drive-belt guard out: a
		# cylinder's AABB is SQUARE across its axis, a flat guard panel's is not.
		if ca.size.y > 0.50 and ca.size.x > 0.10 and ca.size.x < 0.20 \
				and absf(ca.size.y - ca.size.z) < 0.05:
			barrel.append(ca)
	_check("the fan cowl barrel is present, exactly one", barrel.size() == 1,
		"%d barrel candidates among %d parts in the band" % [barrel.size(), cowl.size()])
	if barrel.size() == 1:
		var ba: AABB = barrel[0]
		_check("the cowl is on the NON-DRIVE end (left of the motor body centre)",
			ba.position.x + ba.size.x < mot_x,
			"cowl maxX %.4f vs motor centre %.4f" % [ba.position.x + ba.size.x, mot_x])
		_check("the cowl barrel is proud of the motor body (cowl_r > mot_r)",
			ba.size.y > mot_r * 2.0 + 0.01,
			"cowl dia %.4f vs body dia %.4f" % [ba.size.y, mot_r * 2.0])
		# The check that was MISSING when this suite first went green. Adding the
		# cowl pushed the motor's non-drive end 166 mm further -X, straight into
		# the `+BP2` cabinet: the grille plane ended up 10 mm inside it and the
		# render showed the cabinet, not the grille. Every geometric assertion
		# above still passed, because none of them looked at the neighbour. An
		# AABB test against the cabinet's real box, not a coordinate comparison.
		# The cabinet's box is FOUND, not written down. The first version of this
		# check hardcoded the cabinet at its post-fix position, so moving the
		# cabinet back into the cowl (mutation M23) left the check green: it was
		# comparing the cowl against a constant, not against the cabinet. Same
		# stale-constant failure the repo has hit before. Located by shape: the
		# enclosure body is the model's only 0.60 x 0.80 x 0.30 box.
		var cabs: Array = []
		for xb in parts:
			var xa: AABB = xb
			if xa.size.x > 0.55 and xa.size.x < 0.65 					and xa.size.y > 0.75 and xa.size.y < 0.85 					and xa.size.z > 0.25 and xa.size.z < 0.35:
				cabs.append(xa)
		_check("the +BP2 cabinet body is locatable, exactly one",
			cabs.size() == 1, "%d candidates" % cabs.size())
		if cabs.size() == 1:
			var cab: AABB = cabs[0]
			_check("the fan cowl does not intersect the +BP2 cabinet",
				not ba.intersects(cab),
				"cowl minX %.4f vs cabinet maxX %.4f" % [ba.position.x, cab.position.x + cab.size.x])

	# Grille plane only. The `size.x < 0.02` gate is load-bearing: without it the
	# cable bundle's cylinders land in this band too, and one of them — 0.34 m
	# long — was being measured as the "outermost grille bar", which made the
	# chord-fit check fail against a part that is not a grille bar at all.
	var grille: Array = []
	for gb0 in _region(parts, 0.30, 0.37, 1.90, 2.60, -1.45, -0.85):
		var g0: AABB = gb0
		if g0.size.x < 0.02:
			grille.append(g0)
	_check("grille has its 14 bars and a hub", grille.size() == 15,
		"%d parts in the grille plane" % grille.size())
	# Chord-fitting: the OUTERMOST horizontal bar must be much shorter than the
	# centre one. A square patch of equal-length bars fails this.
	var widest := 0.0
	var outer_len := 0.0
	var outer_dy := 0.0
	for gb in grille:
		var ga: AABB = gb
		var gc := ga.position + ga.size * 0.5
		if ga.size.z > widest:
			widest = ga.size.z
		if ga.size.z > 0.05 and absf(gc.y - mot_y) > outer_dy:
			outer_dy = absf(gc.y - mot_y)
			outer_len = ga.size.z
	_check("the grille is CHORD-FITTED to the cowl disc, not a square patch",
		outer_len > 0.0 and outer_len < 0.65 * widest,
		"outermost bar %.4f m vs centre bar %.4f m" % [outer_len, widest])
	_check("the grille does not overhang the cowl rim",
		widest < 2.0 * gr + 0.03,
		"widest bar %.4f vs cowl grille dia %.4f" % [widest, 2.0 * gr])
	# The sticker: the only small-footprint part in the cowl barrel's X band.
	var stick: Array = []
	for sb in parts:
		var sa: AABB = sb
		var sc := sa.position + sa.size * 0.5
		if sc.x > 0.40 and sc.x < 0.47 and sa.size.y < 0.12 and sa.size.z < 0.12 \
				and sc.z < -0.85 and sc.z > -1.45:
			stick.append(sa)
	_check("exactly one yellow sticker on the cowl", stick.size() == 1,
		"%d candidates" % stick.size())
	if stick.size() == 1:
		var sa2: AABB = stick[0]
		var sc2 := sa2.position + sa2.size * 0.5
		var rad := sqrt(pow(sc2.y - mot_y, 2.0) + pow(sc2.z - mot_z, 2.0))
		_check("the sticker lies ON the cowl barrel (radius within 20 mm)",
			absf(rad - cowl_r) < 0.02,
			"sticker radius %.4f vs cowl_r %.4f" % [rad, cowl_r])
		_check("the sticker is on the cowl's UPPER shoulder, as photographed",
			sc2.y > mot_y + 0.10 and sc2.z > mot_z,
			"sticker at y %.4f z %.4f (motor axis y %.4f z %.4f)" % [sc2.y, sc2.z, mot_y, mot_z])
	# Lifting eye: a torus stood upright by its pivot, so it must be thin in Z.
	var eyes := _region(parts, 0.74, 0.90, 2.54, 2.66, -1.21, -1.07)
	_check("lifting eye present above the motor", eyes.size() == 1,
		"%d parts" % eyes.size())
	if eyes.size() == 1:
		var ea: AABB = eyes[0]
		_check("the lifting eye STANDS UP (ring plane vertical, not flat)",
			ea.size.z < ea.size.y * 0.6,
			"eye size %s" % str(ea.size))

	# ── 3. the `.com` suffix ─────────────────────────────────────────────────
	# Label3D nodes carry no mesh, so they are invisible to `_collect`; walk for
	# them directly and read the text back off the wordmark.
	var labels: Array = []
	_labels(root, labels)
	var texts: Array = []
	for lb in labels:
		texts.append((lb as Label3D).text)
	_check("the wordmark is still NEUE HERBOLD", texts.has("NEUE HERBOLD"),
		"labels: %s" % str(texts))
	_check("the `.com` suffix is present, as a SEPARATE smaller label",
		texts.has(".com"), "labels: %s" % str(texts))
	var main_px := 0.0
	var com_px := 0.0
	for lb2 in labels:
		var l2 := lb2 as Label3D
		if l2.text == "NEUE HERBOLD":
			main_px = l2.pixel_size
		elif l2.text == ".com":
			com_px = l2.pixel_size
	_check("the suffix is drawn SMALLER than the wordmark",
		com_px > 0.0 and main_px > 0.0 and com_px < main_px * 0.6,
		"pixel_size .com %.5f vs wordmark %.5f" % [com_px, main_px])
	var main_pos := Vector3.ZERO
	var com_pos := Vector3.ZERO
	for lb3 in labels:
		var l3 := lb3 as Label3D
		if l3.text == "NEUE HERBOLD":
			main_pos = l3.global_position
		elif l3.text == ".com":
			com_pos = l3.global_position
	_check("the suffix sits low and RIGHT of the wordmark, as photographed",
		com_pos.x > main_pos.x + 0.40 and com_pos.y < main_pos.y,
		"com %s vs mark %s" % [str(com_pos), str(main_pos)])

	# ── 4. under-deck discharge ──────────────────────────────────────────────
	# Material check, not geometry: the whole point of the change is the finish.
	# galvanised is (0.55,0.58,0.62); dark-aged is (0.22,0.22,0.24).
	var dark := 0
	var lit := 0
	var mats: Array = []
	_collect_mats(root, mats)
	for mm in mats:
		var e: Dictionary = mm
		var c: Vector3 = e["c"]
		var pos: Vector3 = e["p"]
		# The chute BODY only: below the deck, on the machine centreline, and
		# tall. The size gate matters — without it this sweeps in parts that are
		# meant to be dark and always will be: the cast-iron outlet flange
		# (0.05 m tall) and the ten cast-iron access-plate bolts (0.022 m), which
		# would make the check fail for the wrong reason.
		var szy: float = e["h"]
		if pos.y < deck_y - 0.10 and absf(pos.x) < 0.55 and absf(pos.z) < 0.50 \
				and szy > 0.40:
			if (c.x + c.y + c.z) / 3.0 < 0.40:
				dark += 1
			else:
				lit += 1
	_check("the under-deck discharge is GREY, not dark-aged",
		dark == 0 and lit > 0,
		"%d dark-finish part(s), %d light-finish part(s) below deck" % [dark, lit])

	# The Z floor has to be 0.28, not 0.32: the plate is TILTED with the panel, so
	# its four bottom bolts sit 25 mm nearer the machine than its top ones and a
	# 0.32 floor silently dropped them (6 bolts found, not 10). Widening Z lets
	# `_flare4`'s own +Z panel in — it is centred at z 0.3100 — so that is
	# excluded by width instead: the panel is 0.75 m across, the plate 0.42.
	var acc: Array = []
	for ab0 in _region(parts, -0.30, 0.45, 1.30, 1.85, 0.28, 0.47):
		var a0: AABB = ab0
		if a0.size.x < 0.60:
			acc.append(a0)
	_check("access plate assembly present on the chute's +Z face",
		acc.size() == 12, "%d parts (want plate + 10 bolts + sticker)" % acc.size())
	var bolts: Array = []
	var plate: Array = []
	for ab in acc:
		var aa: AABB = ab
		if aa.size.x < 0.03:
			bolts.append(aa)
		elif aa.size.x > 0.35:
			plate.append(aa)
	_check("TEN bolt heads around the access plate", bolts.size() == 10,
		"%d bolts" % bolts.size())
	_check("exactly one access plate", plate.size() == 1, "%d plates" % plate.size())
	if plate.size() == 1:
		# Not a raw minZ: a tilted 0.34 m plate has a deep AABB, so its minZ sits
		# 50 mm behind its own centre and says nothing about whether it is seated.
		# Measure the PERPENDICULAR offset from the panel plane instead.
		var pa: AABB = plate[0]
		var pc := pa.position + pa.size * 0.5
		var dis_h2 := deck_y * 0.45
		var dis_bd2 := 0.38
		var dis_td2 := ch_hz * 1.10
		var tilt2 := atan2((dis_td2 - dis_bd2) * 0.5, dis_h2)
		var pan_c := Vector3(0.0, base_y - dis_h2 * 0.5, (dis_bd2 + dis_td2) * 0.25)
		var nrm := Vector3(0.0, -sin(tilt2), cos(tilt2))
		var off := (pc - pan_c).dot(nrm)
		_check("the plate is SEATED on the panel — proud of it, but not floating",
			off > 0.015 and off < 0.06,
			"perpendicular offset %.4f m from the panel plane" % off)

	print("[PHOTO0906] RESULT: %d ok, %d fail" % [_ok, _fail])
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

func _collect_mats(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.material_override is StandardMaterial3D:
			var c: Color = (mi.material_override as StandardMaterial3D).albedo_color
			var wa: AABB = mi.global_transform * mi.mesh.get_aabb()
			out.append({"p": mi.global_position, "c": Vector3(c.r, c.g, c.b), "h": wa.size.y})
	for ch in n.get_children():
		_collect_mats(ch, out)

func _labels(n: Node, out: Array) -> void:
	if n is Label3D:
		out.append(n)
	for ch in n.get_children():
		_labels(ch, out)

func _find(n: Node, want: String) -> Node:
	if n.name == want:
		return n
	for ch in n.get_children():
		var hit := _find(ch, want)
		if hit != null:
			return hit
	return null

func _region(boxes: Array, x0: float, x1: float, y0: float, y1: float,
		z0: float, z1: float) -> Array:
	var hit: Array = []
	for b in boxes:
		var a: AABB = b
		var c := a.position + a.size * 0.5
		if c.x >= x0 and c.x <= x1 and c.y >= y0 and c.y <= y1 and c.z >= z0 and c.z <= z1:
			hit.append(a)
	return hit

func _union(boxes: Array) -> AABB:
	if boxes.is_empty():
		return AABB()
	var u: AABB = boxes[0]
	for b in boxes:
		u = u.merge(b)
	return u
