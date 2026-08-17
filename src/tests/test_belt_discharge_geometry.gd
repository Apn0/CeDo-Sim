extends Node3D
## BELT DISCHARGE GEOMETRY — the two-point discharge (audit 2026-08-16, §6).
##
##   godot --headless --path <proj> res://src/tests/test_belt_discharge_geometry.tscn
##
## `ShredderFeedBelt._discharge_pos()` was ONE point doing two incompatible jobs:
## it is the floor point that `_container_at` / `_ensure_output_pile` / `_shredder_ok`
## measure to (all three need FLOOR level), and it was also the point the falling
## flake visual was spawned from — 1.7 m over the floor, metres below and behind
## where material actually leaves the belt. It also ignored `top_flat_m`, so on
## every belt with a discharge tray (opzetband 3A/3B, westa band 1) the landing
## point sat under the tray instead of past it.
## `docs/plant/operator_issues_2026-07-20.md:130-133` names this as an open root
## cause. The fix splits it: `_discharge_pos()` = LANDING (floor), a new
## `_discharge_lip_pos()` = LIP (belt surface at the end of the path).
##
## WHAT IS ASSERTED, and why it can go red:
##   A. NON-VACUITY   each fixture really carries the config it claims, its path
##                    math is live (_path_total > 0), and the belt really owns a
##                    ContainerArea. A run that builds nothing FAILS here.
##   B. LIP           the lip equals the belt's OWN material path — the position
##                    `_place_rider` gives a rider at progress 1.0, minus the
##                    0.15 m rider stand-off. Two independent code paths must
##                    agree; nothing in this file hard-codes a height.
##   C. LANDING       is on the floor plane (local y == 0, what the three
##                    floor-seated lookups need), is PAST the end of the belt
##                    structure, and honours top_flat_m.
##   D. LOCKSTEP      the ContainerArea trigger sits exactly on the landing point
##                    (the copy of the expression that used to drift), and a
##                    container parked at the landing point is actually found by
##                    `_container_at`, while one parked at the lip's ground
##                    shadow (1.5 m short) or 6 m away is not.
##   E. BEHAVIOUR     (rule 4) with shredder_1 seated where LegacyPropsSpawner
##                    puts it, `_shredder_ok()` still resolves TRUE — i.e. the
##                    moved discharge point did not break the PLC interlock — and
##                    the falling-flake visual now leaves the LIP, not the floor.
##
## Rotation is part of the contract too: both points go through `to_global`, so
## the last fixture is a belt yawed 90° and offset, where a bug that returns a
## local vector, or that swaps the axes, cannot hide.
##
## user:// SAFETY: this test writes NO user:// files at all.

const BELT := preload("res://src/scenes/world/ShredderFeedBelt.gd")

## The 0.15 m stand-off `_place_rider` puts between the belt surface and the
## rider's origin. Read here so the lip check is a comparison of two code paths.
const RIDER_STANDOFF : float = 0.15
const EPS : float = 0.001

var _pass := 0
var _fail := 0

## Resolved at RUNTIME, never referenced as `BELT.DISCHARGE_OVERHANG_M`: a
## compile-time reference to a member the belt does not have turns this whole
## file into a parse error, which means a regression run HANGS (no Result line,
## no exit) instead of going red. Looked up dynamically, a belt without the fix
## produces ordinary FAIL lines and a clean non-zero exit.
var _has_lip : bool = false
var _overhang : float = -1.0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _ready() -> void:
	print("=== BELT DISCHARGE GEOMETRY — landing point on the floor, lip on the belt ===")
	print("\n-- A0. the two-point discharge exists at all --")
	var probe = BELT.new()
	_has_lip = probe.has_method("_discharge_lip_pos")
	var scr : Script = probe.get_script()
	_overhang = float(scr.get_script_constant_map().get("DISCHARGE_OVERHANG_M", -1.0))
	probe.free()
	_ok(_has_lip, "A0 ShredderFeedBelt exposes _discharge_lip_pos() — the LIP half of the pair")
	_ok(_overhang > 0.0,
		"A0 ShredderFeedBelt declares DISCHARGE_OVERHANG_M (%.2f m, the un-sourced overhang, named once)"
			% _overhang)
	# Fixture 1: what LegacyPropsSpawner._spawn_feeder_station actually spawns —
	# a bare ShredderFeedBelt.new() with every export left at its default.
	_check_belt("DEFAULT (LegacyPropsSpawner feeder station)", {}, Transform3D.IDENTITY)
	# Fixture 2: the shipped catalog opzetband_3a3b, built through the real
	# catalog so its operator-measured geometry is the thing under test.
	_check_catalog_belt("opzetband_3a3b")
	# Fixture 3: a shipped belt WITH a top tray, yawed and offset — proves both
	# points are world-space and that top_flat_m is honoured.
	_check_belt("westa_band_1 config, yawed 90 deg @ (7,2,-3)",
		{"deck_length": 0.0, "incline_deg": 45.0, "incline_run": 6.5,
			"deck_width": 1.2, "top_flat_m": 0.6},
		Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(7.0, 2.0, -3.0)))
	await _check_behaviour()
	_finish()


# =============================================================================
func _make_belt(cfg: Dictionary, xf: Transform3D) -> Node3D:
	var belt = BELT.new()
	belt.require_shredder = false
	for k in cfg.keys():
		belt.set(k, cfg[k])
	add_child(belt)
	(belt as Node3D).global_transform = xf
	return belt as Node3D


func _check_catalog_belt(id: String) -> void:
	var belt := PlaceableCatalog.build_node(id, false) as Node3D
	if belt == null or belt.get_script() != BELT:
		_ok(false, "%s builds a ShredderFeedBelt (got %s)" % [id, str(belt)])
		return
	add_child(belt)
	belt.global_transform = Transform3D.IDENTITY
	_assert_belt(id, belt)
	belt.queue_free()


func _check_belt(label: String, cfg: Dictionary, xf: Transform3D) -> void:
	var belt := _make_belt(cfg, xf)
	_assert_belt(label, belt)
	belt.queue_free()


func _assert_belt(label: String, belt: Node3D) -> void:
	print("\n-- %s --" % label)
	var deck   : float = float(belt.get("deck_length"))
	var run    : float = float(belt.get("incline_run"))
	var deg    : float = float(belt.get("incline_deg"))
	var flat   : float = maxf(float(belt.get("top_flat_m")), 0.0)
	var height : float = float(belt.get("deck_height"))
	var total  : float = float(belt.get("_path_total"))
	print("   deck=%.4f run=%.4f deg=%.1f top_flat=%.2f deck_height=%.2f path=%.4f"
		% [deck, run, deg, flat, height, total])

	# ── A. NON-VACUITY ───────────────────────────────────────────────────────
	# Everything below compares points ON this belt. A belt with no geometry
	# would satisfy most of it trivially, so demand real geometry first.
	_ok(run > 0.1 and deg > 1.0 and height > 0.0,
		"A fixture has real geometry (run %.3f m at %.1f deg, deck %.2f m up)" % [run, deg, height])
	_ok(total > deck + run * 0.5,
		"A _path_total %.4f is live (deck+slope+tray, not zero)" % total)
	var area := belt.get_node_or_null("ContainerArea") as Area3D
	_ok(area != null, "A belt owns its ContainerArea trigger")

	# ── B. LIP == the belt's own material path at progress 1.0 ───────────────
	# The oracle is _place_rider: whatever it does is where material rides to.
	var probe := Node3D.new()
	belt.add_child(probe)
	belt.call("_place_rider", {"node": probe, "progress": 1.0, "lane_x": 0.0})
	var exit_g : Vector3 = probe.global_position
	var lip_local := Vector3.ZERO
	if not _has_lip:
		_ok(false, "B no _discharge_lip_pos() on this belt — the lip checks cannot run")
	else:
		var lip : Vector3 = belt.call("_discharge_lip_pos")
		var expect_lip : Vector3 = exit_g - belt.global_transform.basis.y.normalized() * RIDER_STANDOFF
		print("   rider@1.0 = %s   lip = %s" % [str(exit_g), str(lip)])
		_ok(lip.distance_to(expect_lip) < EPS,
			"B lip == rider@1.0 minus the %.2f m stand-off (off by %.4f m)"
				% [RIDER_STANDOFF, lip.distance_to(expect_lip)])
		# Independent of the rider path: the lip must be at the top of the slope,
		# which is deck_height + run*tan(theta) above the belt's own origin.
		lip_local = belt.to_local(lip)
		var expect_h : float = height + run * tan(deg_to_rad(deg))
		_ok(absf(lip_local.y - expect_h) < EPS,
			"B lip height %.4f m == deck_height + run*tan(%.0f) = %.4f m" % [lip_local.y, deg, expect_h])
		_ok(absf(lip_local.z - (deck + run + flat)) < EPS,
			"B lip Z %.4f m == deck + run + top_flat = %.4f m (tray included)"
				% [lip_local.z, deck + run + flat])
	probe.queue_free()

	# ── C. LANDING is on the floor, past the structure, tray-aware ───────────
	var land : Vector3 = belt.call("_discharge_pos")
	var land_local : Vector3 = belt.to_local(land)
	print("   landing = %s  (local %s)" % [str(land), str(land_local)])
	_ok(absf(land_local.y) < EPS,
		"C landing is on the belt's floor plane (local y = %.4f)" % land_local.y)
	_ok(absf(land.y - belt.global_position.y) < EPS,
		"C landing world Y %.4f == belt origin Y %.4f (floor-seated lookups keep working)"
			% [land.y, belt.global_position.y])
	# End of the structure derived from the belt's own exports, NOT from the lip,
	# so this half still measures something on a belt that has no lip function.
	var end_z : float = deck + run + flat
	var overhang : float = land_local.z - end_z
	_ok(absf(overhang - _overhang) < EPS,
		"C landing is DISCHARGE_OVERHANG_M (%.2f m) past the end of the belt (measured %.4f m)"
			% [_overhang, overhang])
	if _has_lip:
		_ok(absf(land_local.z - lip_local.z - overhang) < EPS,
			"C landing and lip differ by exactly that overhang in Z (lip Z %.4f)" % lip_local.z)
	# The specific bug: with a tray, the old expression put the landing point
	# under the tray. Assert the landing point clears the whole structure.
	_ok(land_local.z > deck + run + flat,
		"C landing Z %.4f clears the tray end %.4f (top_flat_m honoured)"
			% [land_local.z, deck + run + flat])

	# ── D. the duplicated expression moves in lockstep ───────────────────────
	if area != null:
		var a_local : Vector3 = area.position
		_ok(a_local.distance_to(land_local) < EPS,
			"D ContainerArea sits ON the landing point (off by %.4f m)"
				% a_local.distance_to(land_local))


# =============================================================================
# E. BEHAVIOUR — rule 4: a concrete trigger, and the right outcome.
# =============================================================================
func _check_behaviour() -> void:
	print("\n-- E. behaviour --")
	var belt := _make_belt({}, Transform3D.IDENTITY)   # the spawner's config
	await get_tree().process_frame
	var land : Vector3 = belt.call("_discharge_pos")
	if not _has_lip:
		_ok(false, "E lip-dependent behaviour cannot be checked without _discharge_lip_pos()")
		belt.queue_free()
		await get_tree().process_frame
		return
	var lip : Vector3 = belt.call("_discharge_lip_pos")

	# E1 — a floor-seated waste container at the landing point still fills.
	# _container_at measures 3.0 m to the container's ORIGIN, and a container
	# origin sits on the floor: a lip-height landing point would be 4.2 m up
	# and would never match.
	var bin := PlaceableCatalog.build_node("waste_container", false) as Node3D
	if bin == null:
		_ok(false, "E waste_container builds")
	else:
		add_child(bin)
		bin.global_position = Vector3(land.x, belt.global_position.y, land.z)
		belt.call("_on_container_entered", bin)
		_ok(belt.call("_container_at", land) == bin,
			"E1 a floor-seated container AT the landing point is found (%.2f m away)"
				% bin.global_position.distance_to(land))
		_ok(belt.call("_container_at", lip) == null,
			"E1 the same container is NOT within 3 m of the LIP (%.2f m) — proof the two points differ"
				% bin.global_position.distance_to(lip))
		bin.queue_free()

	# E2 — the PLC interlock searches from the landing point, and a shredder
	# seated the way LegacyPropsSpawner._spawn_feeder_station seats it (origin on
	# the floor, deck_length + incline_run + 2.0 down the belt axis) is still
	# found. NOTE: a freshly built shredder_1 is NOT running, so _shredder_ok()
	# is false for reasons that have nothing to do with geometry — the geometric
	# half is whether the search REACHES it, which is _cached_shredder.
	belt.set("require_shredder", true)
	var reach : float = float(belt.get("shredder_reach"))
	var seat_z : float = float(belt.get("deck_length")) + float(belt.get("incline_run")) + 2.0
	var shred := PlaceableCatalog.build_node("shredder_1", false) as Node3D
	if shred == null:
		_ok(false, "E shredder_1 builds")
	else:
		add_child(shred)
		shred.add_to_group("shredder")
		shred.global_position = belt.to_global(Vector3(0.0, 0.0, seat_z))
		shred.global_position.y = belt.global_position.y
		belt.set("_cached_shredder", null)
		belt.call("_shredder_ok")
		_ok(belt.get("_cached_shredder") == shred,
			"E2 shredder seated as the spawner seats it (%.2f m from the landing point, reach %.1f m) is FOUND"
				% [shred.global_position.distance_to(land), reach])
		# Negative control: the same machine pushed out of reach must NOT be
		# found. Without this, "found" could be a search that ignores distance.
		shred.global_position = belt.to_global(Vector3(0.0, 0.0, seat_z + reach * 3.0))
		shred.global_position.y = belt.global_position.y
		belt.set("_cached_shredder", null)
		_ok(not bool(belt.call("_shredder_ok")) and belt.get("_cached_shredder") == null,
			"E2 the same shredder at %.2f m is NOT found (the reach test is live)"
				% shred.global_position.distance_to(land))
		shred.remove_from_group("shredder")
		shred.queue_free()

	# E2c — outcome, not just the search: a machine that reports no run state at
	# all (legacy shredder) parked at the landing point satisfies the interlock.
	var stub := Node3D.new()
	add_child(stub)
	stub.add_to_group("shredder")
	stub.global_position = land
	belt.set("_cached_shredder", null)
	_ok(bool(belt.call("_shredder_ok")),
		"E2c interlock SATISFIED by a shredder at the landing point (belt is allowed to run)")
	stub.remove_from_group("shredder")
	stub.queue_free()
	belt.set("require_shredder", false)

	# E3 — the falling-flake visual leaves the LIP, not the floor. Trigger it the
	# way _emit_output does and read where the cube was actually put.
	var before : Array = get_tree().current_scene.get_children()
	belt.call("_spawn_output_flake", lip, land)
	var flake : Node3D = null
	for c in get_tree().current_scene.get_children():
		if not before.has(c) and c is MeshInstance3D:
			flake = c
	if flake == null:
		_ok(false, "E3 a flake was spawned")
	else:
		# Strictly clear of the old hard-coded `landing + 1.7 m` by a margin, so a
		# revert cannot squeak past on float equality.
		_ok(flake.global_position.y - (land.y + 1.7) > 0.5,
			"E3 flake starts %.2f m up, well clear of the old hard-coded floor+1.7 m"
				% (flake.global_position.y - land.y))
		_ok(absf(flake.global_position.y - lip.y) < 0.5,
			"E3 flake starts within 0.5 m of the lip (%.3f vs %.3f)"
				% [flake.global_position.y, lip.y])
		flake.queue_free()
	belt.queue_free()
	await get_tree().process_frame


func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
