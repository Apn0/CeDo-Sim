extends SceneTree
## Headless test for MapOverlay.handle_zoom (src/scenes/hud/MapOverlay.gd:90).
## Finding: handle_zoom untested in the harness (2026-08-31 review) —
## test_map_overlay_init.gd touches it (S4) but is not wired into run.sh, and
## covers neither repeated clamping, nor dir=0, nor the downstream projection.
##
## Run: APPDATA=... CEDO_OFFLINE=1 godot --headless --path . \
##        --script res://src/tests/test_map_overlay_zoom.gd --quit-after 300
##
## Counted checks, not assert() — house shape per test_walkie.gd (a failing
## assert aborts before quit() so the harness hangs; assert compiles out of
## release builds).
##
## The overlay is instantiated OUTSIDE the tree, no quiet subclass needed:
## handle_zoom() and view_params() touch no tree state (queue_redraw()
## early-outs when the CanvasItem is not inside the tree, and view_params()
## reads only `size`, which is settable off-tree). Every method exercised —
## handle_zoom, view_params, _to_px — is the REAL inherited implementation.

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== MapOverlay.handle_zoom Tests ===")

	var scr = load("res://src/scenes/hud/MapOverlay.gd")
	var scr_ok: bool = scr != null
	_ok(scr_ok, "MapOverlay.gd loads")
	if not scr_ok:
		# Cannot instantiate anything — every dependent claim is already a FAIL
		# via the counted check above; report and stop.
		_finish()
		return

	var ov = scr.new()

	# ── 1. Constants + defaults the zoom maths depends on ─────────────────────
	print("Test: Zoom constants and defaults")
	_ok(ov.view_radius_m == 90.0, "Default view_radius_m is 90.0")
	_ok(ov.MIN_RADIUS == 25.0, "MIN_RADIUS is 25.0")
	_ok(ov.MAX_RADIUS == 600.0, "MAX_RADIUS is 600.0")
	_ok(ov.ZOOM_STEP > 0.0 and ov.ZOOM_STEP < 1.0,
		"ZOOM_STEP in (0,1) — direction claims below depend on this (%.2f)" % ov.ZOOM_STEP)

	# ── 2. Direction: +1 shrinks the radius (zoom in), -1 grows it ────────────
	print("Test: Zoom direction")
	ov.view_radius_m = 90.0
	ov.handle_zoom(1)
	_ok(ov.view_radius_m < 90.0, "handle_zoom(+1) shrinks the radius (zoom in)")
	_ok(is_equal_approx(ov.view_radius_m, 90.0 * ov.ZOOM_STEP),
		"handle_zoom(+1) multiplies by ZOOM_STEP exactly (%.3f)" % ov.view_radius_m)

	ov.view_radius_m = 90.0
	ov.handle_zoom(-1)
	_ok(ov.view_radius_m > 90.0, "handle_zoom(-1) grows the radius (zoom out)")
	_ok(is_equal_approx(ov.view_radius_m, 90.0 / ov.ZOOM_STEP),
		"handle_zoom(-1) divides by ZOOM_STEP exactly (%.3f)" % ov.view_radius_m)

	# Round trip away from the bounds is lossless (multiply then divide).
	ov.view_radius_m = 90.0
	ov.handle_zoom(1)
	ov.handle_zoom(-1)
	_ok(is_equal_approx(ov.view_radius_m, 90.0),
		"in-then-out round trip returns to 90.0 away from the bounds (%.3f)" % ov.view_radius_m)

	# ── 3. dir == 0 — per code, `if dir > 0` sends 0 down the else branch,
	# i.e. it behaves as a zoom OUT. Documenting the code as written. ─────────
	print("Test: dir == 0 takes the else branch (zooms out)")
	ov.view_radius_m = 90.0
	ov.handle_zoom(0)
	_ok(is_equal_approx(ov.view_radius_m, 90.0 / ov.ZOOM_STEP),
		"handle_zoom(0) zooms OUT (else branch per MapOverlay.gd:91) (%.3f)" % ov.view_radius_m)

	# ── 4. Repeated zoom-in clamps at MIN_RADIUS and never overshoots ─────────
	print("Test: MIN_RADIUS clamp under 50x zoom-in")
	ov.view_radius_m = 90.0
	var never_under: bool = true
	var monotonic_in: bool = true
	for _i in range(50):
		var before: float = ov.view_radius_m
		ov.handle_zoom(1)
		if ov.view_radius_m < ov.MIN_RADIUS:
			never_under = false
		if ov.view_radius_m > before:
			monotonic_in = false
	_ok(never_under, "radius never dropped below MIN_RADIUS during 50 zoom-ins")
	_ok(monotonic_in, "radius never increased during 50 zoom-ins")
	_ok(ov.view_radius_m == ov.MIN_RADIUS,
		"after 50 zoom-ins the radius sits EXACTLY at MIN_RADIUS (%.6f)" % ov.view_radius_m)
	# Pinned at the bound: one more zoom-in must not move it at all.
	ov.handle_zoom(1)
	_ok(ov.view_radius_m == ov.MIN_RADIUS, "zoom-in at MIN_RADIUS stays exactly at MIN_RADIUS")
	# Not stuck: the opposite direction must leave the bound again.
	ov.handle_zoom(-1)
	_ok(ov.view_radius_m > ov.MIN_RADIUS, "zoom-out from MIN_RADIUS leaves the bound (not stuck)")

	# ── 5. Repeated zoom-out clamps at MAX_RADIUS and never overshoots ────────
	print("Test: MAX_RADIUS clamp under 50x zoom-out")
	ov.view_radius_m = 90.0
	var never_over: bool = true
	var monotonic_out: bool = true
	for _i in range(50):
		var before: float = ov.view_radius_m
		ov.handle_zoom(-1)
		if ov.view_radius_m > ov.MAX_RADIUS:
			never_over = false
		if ov.view_radius_m < before:
			monotonic_out = false
	_ok(never_over, "radius never rose above MAX_RADIUS during 50 zoom-outs")
	_ok(monotonic_out, "radius never decreased during 50 zoom-outs")
	_ok(ov.view_radius_m == ov.MAX_RADIUS,
		"after 50 zoom-outs the radius sits EXACTLY at MAX_RADIUS (%.6f)" % ov.view_radius_m)
	ov.handle_zoom(-1)
	_ok(ov.view_radius_m == ov.MAX_RADIUS, "zoom-out at MAX_RADIUS stays exactly at MAX_RADIUS")
	ov.handle_zoom(1)
	_ok(ov.view_radius_m < ov.MAX_RADIUS, "zoom-in from MAX_RADIUS leaves the bound (not stuck)")

	# ── 6. Downstream: the zoom actually drives the rendered projection.
	# view_params() is the ONE source of truth _draw() builds its projection
	# from (MapOverlay.gd:400) — scale_px = (short_edge * 0.82 * 0.5) / radius.
	# A zoom that changed view_radius_m but not scale_px would leave the map
	# visually frozen, so assert the real thing the draw path consumes. ───────
	print("Test: zoom drives view_params().scale_px and _to_px projection")
	ov.size = Vector2(1000.0, 800.0)   # settable off-tree; view_params reads it
	ov.view_radius_m = 90.0
	var vp0: Dictionary = ov.view_params()
	var has0: bool = vp0.has("scale_px") and vp0.has("center_px") and vp0.has("panel") and vp0.has("origin")
	_ok(has0, "view_params() carries panel/center_px/scale_px/origin")
	var scale0: float = float(vp0.get("scale_px", 0.0))
	var expect0: float = (800.0 * 0.82 * 0.5) / 90.0
	_ok(has0 and is_equal_approx(scale0, expect0),
		"scale_px at radius 90 is (short_edge*0.82*0.5)/90 (%.4f vs %.4f)" % [scale0, expect0])

	ov.handle_zoom(1)
	var vp1: Dictionary = ov.view_params()
	var scale1: float = float(vp1.get("scale_px", 0.0))
	_ok(has0 and scale1 > scale0, "zoom-in RAISES scale_px (more px per metre)")
	_ok(has0 and is_equal_approx(scale1, (800.0 * 0.82 * 0.5) / (90.0 * ov.ZOOM_STEP)),
		"zoomed-in scale_px matches the new radius exactly (%.4f)" % scale1)
	_ok(has0 and vp1.get("panel", Rect2()) == vp0.get("panel", Rect2(1, 1, 1, 1)),
		"zoom does not move the panel rect (only the world window changes)")

	# Project the same world point through _to_px at both zooms: 10 m east of
	# the origin must land farther from the map centre when zoomed in.
	if has0:
		var c: Vector2 = vp0["center_px"]
		var o: Vector2 = vp0["origin"]
		var p0: Vector2 = ov._to_px(Vector3(o.x + 10.0, 0.0, o.y), c, scale0, o)
		var p1: Vector2 = ov._to_px(Vector3(o.x + 10.0, 0.0, o.y), c, scale1, o)
		_ok(is_equal_approx(p0.distance_to(c), 10.0 * scale0),
			"_to_px puts a 10 m offset at 10*scale_px from centre (%.2f px)" % p0.distance_to(c))
		_ok(p1.distance_to(c) > p0.distance_to(c),
			"after zoom-in the SAME world point renders farther from centre (%.2f -> %.2f px)"
			% [p0.distance_to(c), p1.distance_to(c)])
	else:
		_ok(false, "_to_px 10 m offset check (guard tripped: view_params incomplete)")
		_ok(false, "_to_px zoom-in spread check (guard tripped: view_params incomplete)")

	# Cleanup — the overlay never entered the tree, plain free() suffices.
	ov.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
