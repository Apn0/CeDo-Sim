extends SceneTree
## phys-07 guard — a broken-off LumpChunk must not tunnel the 2.5 cm lump-cart
## floor plate. Uses the PRODUCTION chunk (LaserFilter.make_lump_chunk), so
## removing continuous_cd there turns checks 1, 2 and 5 red; check 5 alone goes
## red if _break_off_chan() stops going through make_lump_chunk.
##
## Measured 2026-09-22 (Rapier3D, 60 Hz): a chunk hitting the isolated plate at
## -50 m/s from 0.30 m above (outside the contact-prediction margin) tunnels
## without CCD and is caught with it. A normal 1.5 m drop into a real cart is
## caught either way — check 4 keeps that in-game case honest.
##
## Check 3 is the anti-vacuity control: the same production chunk with CCD
## forced OFF must tunnel. If it ever stops tunnelling (engine / physics change),
## this rig can no longer prove the fix does anything — the suite FAILS and says
## so instead of passing on a test that cannot fail.
##
## Run (physics ticks, NOT frames — do not add --quit-after 300: measured to end
## the run before tick 150 with exit 0 and no verdict):
##   timeout 120 <godot> --headless --path . --script res://src/tests/test_lump_chunk_ccd.gd

const FAST_VEL    : float = -50.0
const DROP_HEIGHT : float = 1.5
const CHUNK_LEN   : float = 0.10
const END_TICK    : int   = 150
const WATCHDOG    : int   = END_TICK + 30

# PlaceableCatalog._lump_cart_compound_collision local frame (wheel_r 0.07, frame_h 0.10, wall_t 0.025).
const CART_SIZE   := Vector3(0.85, 1.1, 1.30)
const CART_BASE_Y : float = 0.07 * 2.0 + 0.10
const WALL_T      : float = 0.025
const PLATE_TOP_Y : float = CART_BASE_Y + WALL_T

var _pf := 0
var _done := false
var _ok := 0
var _fail := 0
var _fast_fixed   : RigidBody3D
var _fast_control : RigidBody3D
var _cart_drop    : RigidBody3D
var _bases := {}

func _physics_process(_delta: float) -> bool:
	_pf += 1
	# Watchdog FIRST — a runtime error further down aborts this function before
	# quit(); without this the process idles forever with no verdict.
	if _pf > WATCHDOG:
		print("Result: 0 ok, 1 fail (watchdog — verdict never completed; see SCRIPT ERROR above)")
		quit(2)
		return true
	if _pf == 1:
		_setup()
		return false
	if _pf >= END_TICK and not _done:
		_done = true
		# _verdict() calls quit() itself. Do NOT `return true` here: a runtime
		# error aborts only _verdict(), control comes back, and returning true
		# would end the main loop with exit 0 and no verdict (measured). Returning
		# false keeps ticking, so the watchdog above ends it with a FAIL verdict.
		_verdict()
	return false

func _setup() -> void:
	# load(), not preload(): LaserFilter/PlaceableCatalog compile against
	# autoload names, which do not exist yet when a --script file is compiled.
	var lf : GDScript = load("res://src/sim/LaserFilter.gd")
	var pc : GDScript = load("res://src/build/PlaceableCatalog.gd")

	var probe : RigidBody3D = lf.make_lump_chunk(CHUNK_LEN, null)
	_check(probe.continuous_cd, "1. production LumpChunk has continuous_cd = true",
		"production LumpChunk has continuous_cd = false (phys-07 regressed)")
	probe.free()

	_bases["fast_fixed"]   = Vector3(500.0, 0.0, 500.0)
	_bases["fast_control"] = Vector3(500.0, 0.0, 540.0)
	_bases["cart_drop"]    = Vector3(500.0, 0.0, 580.0)

	_isolated_plate(_bases["fast_fixed"])
	_fast_fixed = _drop(lf.make_lump_chunk(CHUNK_LEN, null), _bases["fast_fixed"], 0.30, FAST_VEL)

	_isolated_plate(_bases["fast_control"])
	var ctl : RigidBody3D = lf.make_lump_chunk(CHUNK_LEN, null)
	ctl.continuous_cd = false
	_fast_control = _drop(ctl, _bases["fast_control"], 0.30, FAST_VEL)

	_real_cart_on_ground(pc, _bases["cart_drop"])
	_cart_drop = _drop(lf.make_lump_chunk(CHUNK_LEN, null), _bases["cart_drop"], DROP_HEIGHT, 0.0)

	_check_real_call_site(lf)

## Check 5: drive the REAL production path — grow a rope until
## _break_off_chan() fires on its own — so re-inlining a bare RigidBody3D.new()
## at the call site (bypassing make_lump_chunk) is caught too.
func _check_real_call_site(lf: GDScript) -> void:
	var world := Node3D.new()          # _break_off_chan parents to its grandparent
	get_root().add_child(world)
	world.global_position = Vector3(500.0, 50.0, 620.0)
	var mount := Node3D.new()
	world.add_child(mount)
	var filt : Node3D = lf.new()
	mount.add_child(filt)
	filt.set_physics_process(false)    # no cart rebinding / absorb — only the rope path
	var spawned : RigidBody3D = null
	for _i in 1000:                    # grow_m is capped at 0.05 m/tick
		filt.call("_grow_sausage_chan", 0, 0.1, 1000.0)
		for c in world.get_children():
			if c is RigidBody3D and c.is_in_group("lump_chunk"):
				spawned = c
		if spawned != null:
			break
	if spawned == null:
		_check(false, "", "5. _grow_sausage_chan never broke a rope off (no LumpChunk spawned) — check cannot run")
	else:
		_check(spawned.continuous_cd,
			"5. real _break_off_chan() path spawns a LumpChunk with continuous_cd = true",
			"real _break_off_chan() path spawned a LumpChunk WITHOUT continuous_cd (call site bypasses make_lump_chunk)")
	world.queue_free()

func _verdict() -> void:
	var y_fixed := _local_y(_fast_fixed, "fast_fixed")
	var y_ctl   := _local_y(_fast_control, "fast_control")
	var y_cart  := _local_y(_cart_drop, "cart_drop")
	print("  fast_fixed   chunk local Y = %.3f" % y_fixed)
	print("  fast_control chunk local Y = %.3f" % y_ctl)
	print("  cart_drop    chunk local Y = %.3f" % y_cart)
	_check(y_fixed > PLATE_TOP_Y,
		"2. production chunk at %.0f m/s is stopped by the 2.5 cm plate (Y=%.3f)" % [FAST_VEL, y_fixed],
		"production chunk at %.0f m/s TUNNELLED the plate (Y=%.3f)" % [FAST_VEL, y_fixed])
	_check(y_ctl < -1.0,
		"3. control: same chunk with CCD off tunnels (Y=%.3f) — the rig can detect a tunnel" % y_ctl,
		"control did NOT tunnel (Y=%.3f): this rig can no longer prove CCD matters — re-derive FAST_VEL" % y_ctl)
	_check(y_cart > PLATE_TOP_Y,
		"4. 1.5 m drop into a real LumpCart lands on the floor plate (Y=%.3f)" % y_cart,
		"1.5 m drop into a real LumpCart ended below the plate (Y=%.3f)" % y_cart)
	print("Result: %d ok, %d fail" % [_ok, _fail])
	quit(0 if _fail == 0 else 1)

func _local_y(b: RigidBody3D, key: String) -> float:
	return b.global_position.y - (_bases[key] as Vector3).y

func _check(ok: bool, ok_msg: String, fail_msg: String) -> void:
	if ok:
		_ok += 1
		print("  ok   : %s" % ok_msg)
	else:
		_fail += 1
		print("  FAIL : %s" % fail_msg)

## The literal phys-07 geometry: ONLY the cart's floor plate, nothing beneath.
func _isolated_plate(base: Vector3) -> void:
	var plate := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(CART_SIZE.x * 0.88, WALL_T, CART_SIZE.z * 0.88)
	col.shape = box
	plate.add_child(col)
	get_root().add_child(plate)
	plate.global_position = base + Vector3(0.0, CART_BASE_Y + WALL_T * 0.5, 0.0)

## Mirrors the PlaceableCatalog lump_cart branch (LumpCart.gd, mass, damping,
## friction, custom CoM) with the REAL compound collision, parked on a ground box.
func _real_cart_on_ground(pc: GDScript, base: Vector3) -> void:
	var ground := StaticBody3D.new()
	var gcol := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(10.0, 1.0, 10.0)
	gcol.shape = gbox
	ground.add_child(gcol)
	get_root().add_child(ground)
	ground.global_position = base + Vector3(0.0, -0.5, 0.0)
	var cart : RigidBody3D = load("res://src/sim/LumpCart.gd").new()
	cart.call("_sync_mass")
	cart.linear_damp = 0.9
	cart.angular_damp = 3.0
	var pm := PhysicsMaterial.new()
	pm.friction = 0.9
	pm.bounce = 0.02
	cart.physics_material_override = pm
	cart.center_of_mass_mode = RigidBody3D.CENTER_OF_MASS_MODE_CUSTOM
	cart.center_of_mass = Vector3(0.0, 0.18, 0.0)
	pc._lump_cart_compound_collision(cart, CART_SIZE)
	get_root().add_child(cart)
	cart.global_position = base

func _drop(chunk: RigidBody3D, base: Vector3, height_above_plate: float, vy: float) -> RigidBody3D:
	get_root().add_child(chunk)
	chunk.global_position = base + Vector3(0.0, PLATE_TOP_Y + height_above_plate, 0.0)
	chunk.linear_velocity = Vector3(0.0, vy, 0.0)
	return chunk
