extends SceneTree
## phys-01 + phys-08 proof — walking-into-it cart shove actually moves the cart.
## Before the fix the parked friction 0.9 capped a per-tick friction impulse of
## mu*g*dt = 0.147 m/s, more than KinematicPush delivers at walk (0.046) or
## sprint (0.101): the cart was a bolted-down wall (displacement exactly 0).
## Asserts:
##   (a) a 2 m/s pusher displaces the cart (>0.3 m over the push window),
##   (b) the shove enters the rolling-friction state (0.04) and the parked
##       friction (0.9) is restored PUSH_ROLL_TIMEOUT_S after the last shove,
##   (c) phys-08 dedup — N slide contacts on ONE body in a single tick apply
##       ONE impulse + ONE pusher brake (3 duplicate contacts == 1 contact),
##   (d) phys-04 LumpCart half — restore_fill puts kg/mass/cool-timer back.
## Run: Godot_v4.6.3_console --headless --path <proj> --script res://test_cart_push.gd

const CART_SCRIPT := preload("res://src/sim/LumpCart.gd")
const KP          := preload("res://src/sim/KinematicPush.gd")

const PUSHER_KG : float = 88.1   # PlayerController mass_kg
const TAU_S     : float = 0.5    # PlayerController._PUSH_ACCEL_TAU_S
const WALK_MPS  : float = 2.0

## Rig sits far from the world origin: running with --path loads the project
## autoloads, and geometry they park near (0,0,0) ejected an origin-spawned
## cart (−16.7 m with zero pusher contact on the first run of this test).
const BASE := Vector3(500.0, 0.0, 500.0)

const SETTLE_END  := 30    # ticks: let the cart settle on the floor
const PUSH_END    := 150   # ticks: 2 s of walking into the cart
const IDLE_END    := 230   # ticks: 1.33 s > PUSH_ROLL_TIMEOUT_S decay window
const DEDUP_READ  := 242   # ticks: impulses applied at IDLE_END, read after sync

var _init_done := false
var _pf := 0
var _fails := 0

var _cart : RigidBody3D
var _pusher : CharacterBody3D
var _c_single : RigidBody3D   # dedup reference: exactly 1 contact
var _c_dup : RigidBody3D      # dedup probe: 3 duplicate contacts, same body
var _cart_x0 := 0.0
var _saw_rolling := false
var _vx_pusher_single := 0.0
var _vx_pusher_dup := 0.0

func _physics_process(delta: float) -> bool:
	if not _init_done:
		_init_done = true
		_make_floor()
		_cart = _make_cart(BASE + Vector3(0.0, 0.31, 0.0), true)
		_pusher = _make_pusher(BASE + Vector3(-1.3, 0.55, 0.0))
		# Dedup carts float free (gravity off, far from the floor) so their
		# velocity after the synthetic impulses is untouched by contacts.
		_c_single = _make_cart(BASE + Vector3(10.0, 5.0, 0.0), false)
		_c_dup = _make_cart(BASE + Vector3(-10.0, 5.0, 0.0), false)
		return false
	_pf += 1

	if _pf == SETTLE_END:
		_cart_x0 = _cart.global_position.x

	# ── push phase: walk into the cart, KinematicPush after move_and_slide ──
	if _pf > SETTLE_END and _pf <= PUSH_END:
		_pusher.velocity = Vector3(WALK_MPS, 0.0, 0.0)
		_pusher.move_and_slide()
		KP.apply(_pusher, PUSHER_KG, TAU_S, delta)
		if _cart.physics_material_override.friction < 0.1:
			_saw_rolling = true

	if _pf == PUSH_END:
		_pusher.velocity = Vector3.ZERO
		var moved : float = _cart.global_position.x - _cart_x0
		print("  cart displacement after %.1f s @ %.1f m/s push: %.3f m" \
			% [(PUSH_END - SETTLE_END) / 60.0, WALK_MPS, moved])
		_check(moved > 0.3, "(a) cart moves under body-shove (>0.3 m)",
			"cart barely moved (%.3f m) — still bolted down" % moved)
		_check(moved < 6.0, "(a) displacement sane (<6 m, no launch)",
			"cart flew %.3f m — solver launch" % moved)
		_check(_saw_rolling, "(b) shove entered rolling friction (%.2f)" \
			% _cart.physics_material_override.friction,
			"friction never dropped below 0.1 during the push")

	# ── idle phase: no shoves → PUSH_ROLL_TIMEOUT_S decay re-parks the cart ──
	if _pf == IDLE_END:
		var fr : float = _cart.physics_material_override.friction
		_check(fr > 0.5, "(b) parked friction restored after decay (%.2f)" % fr,
			"friction stuck at %.2f — creep protection lost" % fr)
		_run_dedup_impulses()

	if _pf == DEDUP_READ:
		_check_dedup()
		_check_restore_fill()
		print("=== CART PUSH: %s ===" % ("PASS" if _fails == 0 else "FAIL (%d)" % _fails))
		quit(0 if _fails == 0 else 1)
		return true
	return false

## (c) — feed KinematicPush.apply_contacts one contact vs THREE duplicate
## contacts on the same body. With dedup both must yield the same cart velocity
## and the same single pusher brake. Velocities are read a few ticks later
## (DEDUP_READ) because the node's cached linear_velocity syncs on step.
func _run_dedup_impulses() -> void:
	var n := Vector3(-1.0, 0.0, 0.0)   # normal points at the pusher → push_dir = +x
	_pusher.velocity = Vector3(WALK_MPS, 0.0, 0.0)
	KP.apply_contacts(_pusher, PUSHER_KG, TAU_S, 1.0 / 60.0,
		[{"rb": _c_single, "normal": n, "point": _c_single.global_position}])
	_vx_pusher_single = _pusher.velocity.x
	_pusher.velocity = Vector3(WALK_MPS, 0.0, 0.0)
	var dup := {"rb": _c_dup, "normal": n, "point": _c_dup.global_position}
	KP.apply_contacts(_pusher, PUSHER_KG, TAU_S, 1.0 / 60.0, [dup, dup, dup])
	_vx_pusher_dup = _pusher.velocity.x

func _check_dedup() -> void:
	var v1 : float = _c_single.linear_velocity.x
	var v3 : float = _c_dup.linear_velocity.x
	var ratio : float = PUSHER_KG / (PUSHER_KG + _c_single.mass)
	print("  dedup: 1-contact cart vx=%.4f, 3-contact cart vx=%.4f" % [v1, v3])
	_check(v1 > 0.02, "(c) synthetic contact shoves the cart (vx=%.4f)" % v1,
		"single-contact impulse did nothing (vx=%.4f)" % v1)
	_check(absf(v3 - v1) < 0.001,
		"(c) 3 duplicate contacts == 1 contact (dv %.4f)" % absf(v3 - v1),
		"duplicate contacts multiplied the shove: %.4f vs %.4f" % [v3, v1])
	var expect_brake : float = WALK_MPS * ratio   # one reduction: v*(1-(1-ratio))
	_check(absf(_vx_pusher_dup - expect_brake) < 0.001,
		"(c) pusher braked ONCE for 3 contacts (vx=%.4f)" % _vx_pusher_dup,
		"pusher over-braked: vx=%.4f, expected %.4f" % [_vx_pusher_dup, expect_brake])
	_check(absf(_vx_pusher_dup - _vx_pusher_single) < 0.001,
		"(c) pusher brake identical for 1 vs 3 contacts",
		"pusher brake differs: %.4f vs %.4f" % [_vx_pusher_dup, _vx_pusher_single])

## (d) — phys-04 LumpCart half: restore_fill round-trips kg → mass and re-arms
## the cool timer with the persisted remaining seconds.
func _check_restore_fill() -> void:
	_c_single.call("restore_fill", 95.0, 120.0)
	var kg : float = float(_c_single.get("lumps_kg"))
	var left : float = float(_c_single.call("cool_remaining_s"))
	_check(is_equal_approx(kg, 95.0) and is_equal_approx(_c_single.mass, 135.0),
		"(d) restore_fill: 95 kg lumps → 135 kg body mass",
		"restore_fill gave lumps=%.1f mass=%.1f (want 95/135)" % [kg, _c_single.mass])
	_check(left > 119.0 and left <= 120.0 and not bool(_c_single.call("is_cool")),
		"(d) restore_fill: cool timer re-armed (%.1f s left, hot)" % left,
		"cool timer wrong: %.1f s left (want ~120, not cool)" % left)

func _check(ok: bool, ok_msg: String, fail_msg: String) -> void:
	if ok:
		print("  OK  : %s" % ok_msg)
	else:
		print("  FAIL: %s" % fail_msg)
		_fails += 1

func _make_floor() -> void:
	var f := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(40.0, 1.0, 10.0)
	col.shape = bx
	f.add_child(col)
	get_root().add_child(f)
	f.global_position = BASE + Vector3(0.0, -0.5, 0.0)   # top face at y=0

## Mirrors the PlaceableCatalog lump_cart branch: LumpCart script, _sync_mass
## (mass = 40 kg empty), parked friction 0.9 / damp 0.9 — the exact values the
## phys-01 rolling entry must defeat. Single box stands in for the 13-shape
## compound collider (friction/impulse behavior doesn't depend on the layout).
func _make_cart(pos: Vector3, gravity_on: bool) -> RigidBody3D:
	var c : RigidBody3D = CART_SCRIPT.new()
	c.call("_sync_mass")
	c.linear_damp = 0.9
	c.angular_damp = 3.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.02
	c.physics_material_override = pm
	if not gravity_on:
		c.gravity_scale = 0.0
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.75, 0.6, 1.05)
	col.shape = bx
	c.add_child(col)
	get_root().add_child(c)
	c.global_position = pos
	return c

func _make_pusher(pos: Vector3) -> CharacterBody3D:
	var p := CharacterBody3D.new()
	p.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING   # pure lateral drive
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = Vector3(0.5, 1.0, 0.5)
	col.shape = bx
	p.add_child(col)
	get_root().add_child(p)
	p.global_position = pos
	return p
