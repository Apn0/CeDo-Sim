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
## 2026-09-25 (operator, from plan views): the uitvoerband is ONE conveyor under
## shredder_1's rotors with a 20° climb (uitvoerband_1), and the magnet is a
## CROSS-belt magnet (overband_magnet_l1) over that climb, 0.20 m toward the top
## of the plan, 0.25 m over the deck at the highest point under it. The checks
## below follow that; the operator's placement numbers are in test_line1_layout.
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

	# 2026-09-25 (operator): the uitvoerband is ONE conveyor under shredder_1's
	# rotors with a 20° climb (uitvoerband_1), and the magnet is a CROSS-belt
	# magnet over that climb (overband_magnet_l1). Both found by id.
	var magnet : Node3D = null
	var belt : Node3D = null
	var shredder : Node3D = null
	for n in get_tree().root.find_children("*", "Node3D", true, false):
		var n3 := n as Node3D
		if n3 == null or not n3.has_meta("macro_id"):
			continue
		if String(n3.get_meta("macro_id")) != "line_1":
			continue
		match String(n3.get_meta("placeable_id", "")):
			"overband_magnet_l1":
				magnet = n3
			"uitvoerband_1":
				belt = n3
			"shredder_1":
				shredder = n3

	_check(magnet != null, "T1 overband_magnet_l1 was placed on line 1")
	_check(belt != null, "T1 uitvoerband_1 was placed on line 1")
	if magnet == null or belt == null:
		_finish(); return

	# Leg frame of the uitvoerband: along its run, and across it.
	var anc : Dictionary = belt.get_meta("macro_anchor", {}) as Dictionary
	var rot : float = float(anc.get("rot_y", 0.0))
	var start : Vector3 = anc.get("start", Vector3.ZERO)
	var fwd := Vector3(-sin(rot), 0.0, -cos(rot))
	var rgt := Vector3(cos(rot), 0.0, -sin(rot))
	var mp : Vector3 = magnet.global_position
	var bp : Vector3 = belt.global_position

	# ── T2 — mounted: over the belt, 0.20 m toward the top of the plan ───────
	# (operator 2026-09-25: "move the magnet towards the top of the image about
	# 20 centimeters"). Its along position is the operator's midpoint rule,
	# measured in test_line1_layout.
	var off : float = (mp - bp).dot(rgt)
	_check(absf(off - 0.20) <= CENTRE_TOL_M,
		"T2 magnet hangs over the uitvoerband, %.3f m off its centre line (0.20, tol %.2f)"
			% [off, CENTRE_TOL_M])
	var u_len : float = float(belt.get("deck_length")) + float(belt.get("incline_run")) + float(belt.get("top_flat_m"))
	var m_al : float = (mp - start).dot(fwd)
	var b0 : float = (bp - start).dot(fwd)
	_check(m_al > b0 and m_al < b0 + u_len,
		"T2 ... over the belt's own length (%.2f m of %.2f m)" % [m_al - b0, u_len])

	# ── T3 — it straddles the belt: its own belt runs ACROSS it ─────────────
	var mb : AABB = _aabb(magnet)
	var bb : AABB = _aabb(belt)
	var m_across : float = absf(mb.size.x * rgt.x) + absf(mb.size.z * rgt.z)
	var m_along : float = absf(mb.size.x * fwd.x) + absf(mb.size.z * fwd.z)
	var b_across : float = absf(bb.size.x * rgt.x) + absf(bb.size.z * rgt.z)
	_check(m_across > b_across,
		"T3 magnet spans wider than the belt, so its legs clear it (%.2f m vs %.2f m)"
			% [m_across, b_across])
	_check(m_across > m_along,
		"T3 a cross-belt magnet: longer across the conveyor than along it (%.2f m vs %.2f m)"
			% [m_across, m_along])

	# (T4, "leg B was not stretched by the magnet", compared two transport_belts
	# that no longer exist as such: the magnet still mounts without advancing the
	# cursor, and the receiving belt's place is now the throw's landing point,
	# measured in test_line1_layout.)

	# ── T5/T6 — clearance over the deck, where the belt is highest under it ──
	# The magnet's lowest part over the belt is the bottom of its cooling fins,
	# which span ±0.31·size.x along the conveyor (the core, turned with the
	# cross-belt). The deck rises at 20° from the end of its flat part.
	var msz : Vector3 = PlaceableCatalog.get_item("overband_magnet")["size"]
	var low : float = mp.y + msz.y * 0.80 - msz.y * 0.22 * 0.5
	var flat_end : float = b0 + float(belt.get("deck_length"))
	var probe : float = m_al + msz.x * 0.62 * 0.5
	var deck : float = bp.y + float(belt.get("deck_height")) \
		+ maxf(0.0, probe - flat_end) * tan(deg_to_rad(float(belt.get("incline_deg"))))
	var rails : float = deck + 0.03 + float(belt.get("guard_h"))
	_check(low > rails,
		"T5 the conveyor's skirt boards stay under the magnet (%.3f m of air)" % (low - rails))
	_check(absf((low - deck) - PlaceableCatalog.OVERBAND_CLEARANCE_M) <= 0.02,
		"T6 magnet sits %.3f m over the belt deck (target %.2f m +-0.02)"
			% [low - deck, PlaceableCatalog.OVERBAND_CLEARANCE_M])
	_check(float(belt.get("guard_h")) < PlaceableCatalog.OVERBAND_CLEARANCE_M,
		"T6 the conveyor's own superstructure stays under the clearance (%.3f m < %.2f m)"
			% [float(belt.get("guard_h")), PlaceableCatalog.OVERBAND_CLEARANCE_M])

	# ── T7 — the shredder drops onto the uitvoerband ─────────────────────────
	_check(shredder != null, "T7 shredder_1 was placed")
	if shredder != null:
		var ssz : Vector3 = PlaceableCatalog.get_item("shredder_1")["size"]
		var outf : Vector3 = MachineFlow.profile("shredder_1")["out"]
		var out_y : float = shredder.global_position.y + outf.y * ssz.y
		var drop : float = out_y - (bp.y + float(belt.get("deck_height")))
		_check(drop > 0.05 and drop < 1.0,
			"T7 shredder_1 discharges DOWN onto the uitvoerband (%.3f m drop)" % drop)

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
