extends Node
## SHREDDER FEED BELT — held_kg() mass-conservation check.
##
##   godot --headless --path . res://src/tests/test_shredder_feed_belt.tscn
##
## held_kg() = _throat_kg + Σ(rider.mass * rider.kg_total) is the belt's own
## conservation invariant (ShredderFeedBelt.gd:83-87) — the claim a downstream
## mass-ledger test relies on. This drives the REAL accept_bale()/_process()
## path (require_shredder=false, the belt's own documented standalone-test
## escape hatch — see the doc comment on @export require_shredder) with
## digest_rate=0 so no mass can leave as shredded output, and checks the
## total holds constant from bale-drop through full transfer into the
## throat — not just at t=0 (a naive `return _throat_kg + bale.mass` at
## accept time would pass a t=0-only check and still be wrong mid-transfer).
##
## fill_setpoint is set far above 1.0 so the throat-full interlock never
## engages during S3 — that's a DIFFERENT behaviour (belt stalls when the
## shredder can't keep up) this test isn't exercising.
##
## _process() is called directly with a fixed dt rather than relying on the
## engine's automatic per-frame call, so the run is deterministic; set_process
## (false) stops the engine from ALSO auto-driving it with a real frame delta
## in between, which would otherwise double-tick and make timing non-
## reproducible.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] ShredderFeedBelt.held_kg()")

	var belt := ShredderFeedBelt.new()
	belt.require_shredder = false      # belt's own doc'd standalone-test escape hatch
	belt.digest_rate = 0.0             # isolate accept->throat transfer; no output leak
	belt.fill_setpoint = 999.0         # keep the throat-full interlock out of this test
	belt.belt_speed = 3.0              # fast creep so the rider reaches the top quickly
	belt.feed_rate = 5.0               # fast feed so the throat drains the rider quickly
	belt.start_requested = true
	add_child(belt)
	await get_tree().process_frame     # _ready() runs: caches path metrics, builds SmoothedRate
	belt.set_process(false)            # own every tick manually — no engine auto-_process race

	_check(is_equal_approx(float(belt.call("held_kg")), 0.0), "S1 empty belt: held_kg() == 0")

	var bale := RigidBody3D.new()
	bale.set_meta("scanned", true)
	bale.set_meta("weight_kg", 400.0)
	# accept_bale() reads the bale's PRE-reparent world basis.x as its long axis
	# and tags anything >35° off the belt's travel (+Z) as cross-wise, latching
	# BELT-JAM after JAM_TIMER_S if uncorrected (#211a). An identity-rotation
	# RigidBody3D's local +X reads as 90° off — rotate it lengthwise-onto-Z so
	# this test exercises the mass path, not the (separately owned) jam fault.
	bale.rotate_y(-PI / 2.0)
	add_child(bale)

	var ok : bool = belt.call("accept_bale", bale, 0)
	_check(ok, "S2 accept_bale() accepts a scanned 400 kg bale")
	_check(is_equal_approx(float(belt.call("held_kg")), 400.0),
		"S2 held_kg() == 400.0 immediately after accept (%.2f)" % float(belt.call("held_kg")))

	# ── S3 drive the REAL belt (ride -> feed -> throat) and confirm held_kg()
	# never drifts off 400 with digestion disabled.
	var dt := 0.05
	var max_drift := 0.0
	for _i in 600:
		belt.call("_process", dt)
		var h : float = float(belt.call("held_kg"))
		max_drift = maxf(max_drift, absf(h - 400.0))
	_check(max_drift < 0.5,
		"S3 held_kg() stayed within 0.5 kg of 400 across ride+feed, digest_rate=0 (max drift %.3f kg)" % max_drift)

	var riders : Array = belt.get("_riders")
	var throat_kg : float = float(belt.get("_throat_kg"))
	_check(riders.is_empty(), "S3 the rider fully transferred into the throat (0 riders left)")
	_check(throat_kg > 399.0,
		"S3 all ~400 kg landed in _throat_kg (%.2f)" % throat_kg)
	_check(is_equal_approx(float(belt.call("held_kg")), throat_kg),
		"S3 held_kg() == _throat_kg once no riders remain (%.2f vs %.2f)"
			% [float(belt.call("held_kg")), throat_kg])

	# ── S4 turn digestion back on — held_kg() must now DECREASE, proving it
	# tracks live state and isn't just echoing a frozen accept-time constant.
	belt.digest_rate = 0.5
	for _i in 40:
		belt.call("_process", dt)
	var after : float = float(belt.call("held_kg"))
	_check(after < throat_kg - 1.0,
		"S4 held_kg() drops once digestion resumes (%.2f -> %.2f)" % [throat_kg, after])

	# ── S5 HMI control requests
	_check(belt.is_running(), "S5 belt is running before stop request")
	belt.request_stop()
	_check(not belt.start_requested, "S5 request_stop() sets start_requested to false")
	_check(not belt.is_running(), "S5 belt is_running() is false after stop request")
	belt.request_start()
	_check(belt.start_requested, "S5 request_start() sets start_requested to true")
	_check(belt.is_running(), "S5 belt is_running() is true after start request")

	if _fails == 0:
		print("[TEST] ShredderFeedBelt.held_kg() PASS")
	else:
		print("[TEST] ShredderFeedBelt.held_kg() FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
