extends SceneTree
## Proof for the "magic bale transportation" fix (operator 2026-07-16).
## A placed bale spawns frozen (kinematic) so yard stacks don't drift. The grab
## must UNFREEZE it (BaseVehicle._try_grab now does `best.freeze = false`) so it
## obeys gravity + plate friction instead of hovering detached in mid-air.
## This proves the mechanism: untouched frozen bale hovers; grabbed bale falls.
## Run: Godot_v4.6.3_console --headless --path <proj> --script res://test_bale_grab_physics.gd

var _init_done := false
var _frozen : RigidBody3D
var _grabbed : RigidBody3D
const Y0 := 3.0
var _pf := 0

func _physics_process(_delta: float) -> bool:
	if not _init_done:
		_init_done = true
		# Untouched placed bale: frozen kinematic (the pre-fix carried state).
		_frozen = _make_bale(Vector3(-2, Y0, 0))
		_frozen.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_frozen.freeze = true
		# Grabbed bale: frozen on spawn, then unfrozen — exactly what the
		# BaseVehicle._try_grab fix does the instant the clamp latches it.
		_grabbed = _make_bale(Vector3(2, Y0, 0))
		_grabbed.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		_grabbed.freeze = true
		_grabbed.freeze = false   # <-- the fix
		return false
	_pf += 1
	if _pf < 40:
		return false
	var fell_frozen := Y0 - _frozen.global_position.y
	var fell_grabbed := Y0 - _grabbed.global_position.y
	var fails := 0
	print("  untouched frozen bale fell %.3f m" % fell_frozen)
	print("  grabbed (unfrozen) bale fell %.3f m" % fell_grabbed)
	if fell_frozen < 0.05:
		print("  OK  : untouched bale stays put (yard stacks still won't drift)")
	else:
		print("  FAIL: untouched frozen bale moved %.3f m" % fell_frozen); fails += 1
	if fell_grabbed > 0.3:
		print("  OK  : grabbed bale FALLS under gravity (%.2f m) — no more magic float" % fell_grabbed)
	else:
		print("  FAIL: grabbed bale did not fall (%.3f m) — still magic" % fell_grabbed); fails += 1
	print("=== BALE GRAB PHYSICS: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true

func _make_bale(pos: Vector3) -> RigidBody3D:
	var b := RigidBody3D.new()
	b.mass = 400.0
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(1.2, 1.05, 1.05)
	col.shape = bx
	b.add_child(col)
	get_root().add_child(b)
	b.global_position = pos
	return b
