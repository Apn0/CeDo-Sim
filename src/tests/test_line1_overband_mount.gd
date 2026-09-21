extends Node
## LINE 1 — the overband magnet is MOUNTED on the uitvoerband, not queued behind it.
##
##   godot --headless --path . res://src/tests/test_line1_overband_mount.tscn
##
## WHY THIS FILE EXISTS. Operator correction, 2026-09-16 (live chat): the
## overband magnet is a cross-belt separator suspended OVER the uitvoerband,
## centred along its length — "not as a sequence". `_m_overband_magnet` had
## always built it that way (its own header says "suspended self-cleaning
## cross-belt separator above the conveyor"; the cross-belt drums run on the X
## axis and the scrap chute discharges to +X, both transverse to the conveyor),
## but LINE_1_SEQ placed it as an ordinary station. That was wrong twice over:
## the magnet stood on the floor 4 m downstream of the belt it is supposed to
## straddle, and because a main entry advances the macro's cursor it also shoved
## every machine after it ~3.5 m further along leg B.
##
## The fix is the macro's {"mount_over": N} key (BuildMode.gd), which anchors an
## entry on an earlier entry's placed centre and does NOT advance the cursor.
## This asserts the RESULT of that in-world, by measuring the two machines
## against each other — the SEQ names entry index 3, and an index is exactly the
## kind of thing that goes stale the moment somebody inserts a station above it.
##
## NOT asserted here yet: the 25 cm working clearance between the magnet's
## pick-up face and the belt deck. The magnet's face currently sits 0.57 m above
## the deck, and closing that to 0.25 m is a separate decision about HOW (shrink
## the gantry, hang the core lower, or raise the conveyor) that was still open
## when this file was written. Measured, printed below, deliberately not gated —
## a gate written before the decision would just have to be rewritten with it.

const CENTRE_TOL_M : float = 0.05

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
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

func _run() -> void:
	print("[TEST] line 1 — overband magnet mounted over the uitvoerband")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	# Built away from the world origin on purpose: a placement bug that resolves
	# to (0,0,0) is invisible when the line itself starts there.
	bm.call("_build_full_line", "line_1", Vector3(-142.7, 0.0, 42.9), 0.0)
	await get_tree().process_frame

	var magnet : Node3D = null
	var belt : Node3D = null
	var belts : Array = []
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 == null or not n3.has_meta("macro_id"):
			continue
		if String(n3.get_meta("macro_id")) != "line_1":
			continue
		match String(n3.get_meta("placeable_id", "")):
			"overband_magnet":
				magnet = n3
			"transport_belt":
				belts.append(n3)

	_check(magnet != null, "T1 overband_magnet was placed on line 1")
	_check(belts.size() >= 2, "T1 both transport_belts were placed (%d)" % belts.size())
	if magnet == null or belts.is_empty():
		_finish(); return

	# The uitvoerband is whichever transport_belt the magnet is nearest — resolved
	# by MEASUREMENT, so this does not depend on the SEQ's entry index staying put.
	var best := INF
	for b in belts:
		var d : float = (b as Node3D).global_position.distance_to(magnet.global_position)
		if d < best:
			best = d
			belt = b as Node3D

	# ── T2 — mounted: the two centres coincide in plan ───────────────────────
	var mp : Vector3 = magnet.global_position
	var bp : Vector3 = belt.global_position
	var horiz : float = Vector2(mp.x - bp.x, mp.z - bp.z).length()
	_check(horiz <= CENTRE_TOL_M,
		"T2 magnet is centred on the uitvoerband (%.3f m off, tol %.2f)" % [horiz, CENTRE_TOL_M])

	# ── T3 — it straddles that belt rather than standing in the line ─────────
	# Measured on the real AABBs: the magnet must be WIDER than the belt (its
	# legs land outside the belt's sides) and no LONGER than it along the run
	# (centred over it, not overhanging either end).
	var mb : AABB = _aabb(magnet)
	var bb : AABB = _aabb(belt)
	var belt_runs_x : bool = bb.size.x > bb.size.z       # leg B runs along world X
	var m_across : float = mb.size.z if belt_runs_x else mb.size.x
	var b_across : float = bb.size.z if belt_runs_x else bb.size.x
	var m_along  : float = mb.size.x if belt_runs_x else mb.size.z
	var b_along  : float = bb.size.x if belt_runs_x else bb.size.z
	_check(m_across > b_across,
		"T3 magnet spans wider than the belt, so its legs clear it (%.2f m vs %.2f m)"
			% [m_across, b_across])
	_check(m_along <= b_along + 0.01,
		"T3 magnet sits within the belt's length (%.2f m over %.2f m)" % [m_along, b_along])

	# ── T4 — the mount did NOT advance the macro cursor ──────────────────────
	# The other transport_belt is the short leg-C belt, one 90 degree turn on from
	# the uitvoerband. Straight-line distance is therefore NOT the leg-B run — the
	# corner cuts it — so this compares against a threshold derived from what a
	# SEQUENCE placement would have had to insert: the magnet's own 3.0 m depth
	# plus half a belt. MEASURED 2026-09-16, both ways round:
	#   magnet as a sequence entry -> the belts are 6.32 m apart  (fails)
	#   magnet mounted on the belt -> the belts are 3.20 m apart  (passes)
	# so the 5.0 m line sits well clear of both readings rather than hugging one.
	var other : Node3D = null
	for b in belts:
		if b != belt:
			other = b as Node3D
			break
	if other != null:
		var step : float = other.global_position.distance_to(bp)
		var mag_depth : float = float((PlaceableCatalog.get_item("overband_magnet")["size"] as Vector3).z)
		var belt_half : float = float((PlaceableCatalog.get_item("transport_belt")["size"] as Vector3).z) * 0.5
		var limit : float = mag_depth + belt_half
		_check(step < limit,
			"T4 leg B was not stretched by the magnet's footprint (%.2f m < %.2f m)"
				% [step, limit])

	# ── T5 — the magnet clears the conveyor it straddles ─────────────────────
	# The pick-up face is the bottom of the cross-belt drums, found by MEASURING
	# the rotating assembly rather than re-deriving the model's own fractions:
	# the drums hang under RotatingMachine nodes, so they are the meshes whose
	# parent exposes an `axis`. (Reading it off size.y * 0.69 would be a second
	# copy of a number _m_overband_magnet already owns.)
	#
	# This asserts NON-INTERPENETRATION, which holds whichever datum the 25 cm
	# clearance is eventually measured from, so it does not have to be rewritten
	# when that is settled. Both candidate clearances are printed below.
	var face_y : float = INF
	for m in magnet.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		if mi == null or mi.mesh == null or not mi.is_visible_in_tree() or mi.top_level:
			continue
		var par := mi.get_parent()
		if par == null or par.get("axis") == null:
			continue
		face_y = minf(face_y, (mi.global_transform * mi.get_aabb()).position.y)
	_check(is_finite(face_y), "T5 the magnet's cross-belt drums were found")
	var belt_top : float = bb.position.y + bb.size.y
	if is_finite(face_y):
		_check(face_y > belt_top,
			"T5 nothing on the conveyor reaches the magnet (%.3f m of air, belt tops out at %.3f m)"
				% [face_y - belt_top, belt_top])

	# ── T6 — the operator's working clearance, over the DECK ─────────────────
	# Belt deck top from BeltBuilder's own default, not a copy of it: a hand-baked
	# 0.675 here would rot the moment deck_y_frac changed. Measured to the
	# magnet's LOWEST part, so the clearance is a floor and not an average.
	var bsize : Vector3 = PlaceableCatalog.get_item("transport_belt")["size"]
	var frac : float = float(BeltBuilder.make_spec().get("deck_y_frac", 0.75))
	var deck_top : float = belt.global_position.y + bsize.y * frac
	if is_finite(face_y):
		var clear : float = face_y - deck_top
		_check(absf(clear - PlaceableCatalog.OVERBAND_CLEARANCE_M) <= 0.02,
			"T6 magnet sits %.3f m over the belt deck (target %.2f m +-0.02)"
				% [clear, PlaceableCatalog.OVERBAND_CLEARANCE_M])
		# The rails had to come down before the belt could be raised at all — if
		# they creep back up they eat the clearance from below without T6 moving.
		_check(belt_top - deck_top < PlaceableCatalog.OVERBAND_CLEARANCE_M,
			"T6 the conveyor's own superstructure stays under the clearance (%.3f m < %.2f m)"
				% [belt_top - deck_top, PlaceableCatalog.OVERBAND_CLEARANCE_M])

	# ── T7 — the shredder drop, RE-DERIVED after the lift ────────────────────
	# Raising the uitvoerband 0.281 m shortened the fall out of shredder_1 from
	# 0.675 m to 0.394 m. That is still a real drop (the belt is below the
	# outlet, material falls onto it) and still generous next to the 0.30 m
	# BELT_TRANSFER_DROP_M used for belt-to-belt transfers, so the transfer is
	# asserted as a BAND rather than a magic number: it must not invert (belt
	# above the outlet) and must not become a free-fall.
	var shredder : Node3D = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 != null and n3.has_meta("macro_id") \
			and String(n3.get_meta("macro_id")) == "line_1" \
			and String(n3.get_meta("placeable_id", "")) == "shredder_1":
			shredder = n3
			break
	_check(shredder != null, "T7 shredder_1 was placed")
	if shredder != null:
		var ssz : Vector3 = PlaceableCatalog.get_item("shredder_1")["size"]
		var outf : Vector3 = MachineFlow.profile("shredder_1")["out"]
		var out_y : float = shredder.global_position.y + outf.y * ssz.y
		var drop : float = out_y - deck_top
		_check(drop > 0.05 and drop < 1.0,
			"T7 shredder_1 still discharges DOWN onto the raised uitvoerband (%.3f m drop)" % drop)

	_finish()

func _finish() -> void:
	if _fails == 0:
		print("[TEST] line 1 overband mount PASS")
		print("Result: PASS (0 fail)")
		get_tree().quit(0)
	else:
		print("[TEST] line 1 overband mount FAIL (%d fail)" % _fails)
		print("Result: FAIL (%d fail)" % _fails)
		get_tree().quit(1)
