extends Node
## LUMP CART SPEED CLAMP (phys-05 interim, 2026-09-23) — a Lumpenwagen can never
## be flung faster than LumpCart.MAX_SPEED, while a normal shove is untouched.
##
##   godot --headless --path . res://src/tests/test_lump_cart_speed_clamp.tscn
##
## The vehicles are frozen-kinematic bodies (infinite mass); a cart squeezed
## between one and a wall used to leave at whatever velocity the solver needed
## to resolve the overlap. This suite reproduces the SYMPTOM directly — a
## 50 m/s impulse on the real catalog cart — and checks the clamp, then checks
## the anti-vacuity half: a 1.2 m/s shove (a walking push) keeps its speed.
##
## Measured 2026-09-23 with _integrate_forces disabled (mutation run): the
## 50 m/s impulse left the cart at 48.09 m/s and the twist at 53.33 rad/s (S2
## red twice); with the clamp: 5.76 m/s and 5.58 rad/s on the next physics
## tick, and the 1.2 m/s shove reads 1.04 m/s either way.

const WATCHDOG_S := 90.0
const FLING_MPS  := 50.0
const SHOVE_MPS  := 1.2

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

func _spawn_cart() -> RigidBody3D:
	var cart : Node3D = PlaceableCatalog.build_node("lump_cart", false)
	add_child(cart)
	cart.global_position = Vector3(0.0, 0.0, 0.0)
	return cart as RigidBody3D

func _run() -> void:
	print("[TEST] lump cart speed clamp")
	# A floor so the cart rests instead of falling through the sample.
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(200.0, 0.2, 200.0)
	col.shape = box
	col.position = Vector3(0.0, -0.1, 0.0)
	floor_body.add_child(col)
	add_child(floor_body)

	var cart := _spawn_cart()
	_check(cart != null and cart is LumpCart, "S1 catalog built a real LumpCart RigidBody")
	if cart == null:
		_finish(); return
	for _i in 10:
		await get_tree().physics_frame
	var rest_speed := cart.linear_velocity.length()
	_check(rest_speed < 0.2, "S1 cart at rest on the floor (%.3f m/s)" % rest_speed)

	# ── S2: the squeeze-eject symptom — a 50 m/s impulse ──
	cart.sleeping = false
	cart.apply_central_impulse(Vector3(1.0, 0.0, 0.0) * cart.mass * FLING_MPS)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var flung := cart.linear_velocity.length()
	_check(flung <= LumpCart.MAX_SPEED + 0.05,
		"S2 a %.0f m/s impulse leaves the cart at ≤ MAX_SPEED %.1f m/s (measured %.2f m/s)" % [FLING_MPS, LumpCart.MAX_SPEED, flung])
	_check(flung > 1.0, "S2 …but it does move (%.2f m/s) — the clamp is a ceiling, not a brake" % flung)
	cart.apply_torque_impulse(Vector3(0.0, 1.0, 0.0) * 500.0)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var spin := cart.angular_velocity.length()
	_check(spin <= LumpCart.MAX_SPIN_RAD + 0.05, "S2 a 500 N·m·s twist leaves it at ≤ %.1f rad/s (measured %.2f)" % [LumpCart.MAX_SPIN_RAD, spin])

	# ── S3: anti-vacuity — a walking shove is not touched ──
	var cart2 := _spawn_cart()
	cart2.global_position = Vector3(0.0, 0.0, 6.0)
	for _i in 10:
		await get_tree().physics_frame
	cart2.sleeping = false
	cart2.apply_central_impulse(Vector3(0.0, 0.0, 1.0) * cart2.mass * SHOVE_MPS)
	await get_tree().physics_frame
	var shoved := cart2.linear_velocity.length()
	_check(shoved > SHOVE_MPS * 0.6 and shoved <= SHOVE_MPS + 0.05,
		"S3 a %.1f m/s shove keeps most of its speed after one tick of friction (%.2f m/s) — below the clamp, untouched" % [SHOVE_MPS, shoved])
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] lump cart speed clamp %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
