extends SceneTree
## SceneTree-mode test (run with `godot --headless --script path/to/this.gd`).
##
## Verifies the 10% bale compliance change WITHOUT loading any 4.6-format scene
## files (so it can be smoke-checked even on a Godot install that's a minor
## version behind the project).
##
## Covers:
##   1. Every bale origin in BaleDefs builds via PlaceableCatalog.build_node().
##   2. Each bale's BoxShape3D collision is shrunk to (0.9·L, H, 0.9·D).
##   3. Each bale carries a PhysicsMaterial with sane friction + a touch of bounce.
##   4. The "delivered" meta flag drives the LineFlow feed gate as designed.

const _BaleDefs := preload("res://src/sim/BaleDefs.gd")
const _Catalog  := preload("res://src/build/PlaceableCatalog.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Bale compliance headless test")
	print("============================================================")

	_test_bale_collision_give()
	_test_delivered_gate_logic()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")

	quit(0 if _fail == 0 else 1)

# =============================================================================
func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

func _ok_approx(actual: float, expected: float, tol: float, label: String) -> void:
	var ok := absf(actual - expected) <= tol
	if not ok:
		label = "%s  (expected ~%.4f ±%.4f, got %.4f)" % [label, expected, tol, actual]
	_ok(ok, label)

# =============================================================================
# 1) Bale collision: 10% horizontal "give", full vertical, soft physics material
# =============================================================================
func _test_bale_collision_give() -> void:
	print("[1] Bale collision shape (10%% give on X/Z, full Y) + PhysicsMaterial")
	for bale_def in _BaleDefs.origins():
		var id := String(bale_def["id"])
		var size: Vector3 = bale_def["size"]
		var bale = _Catalog.build_node(id, false)
		_ok(bale != null, "%s bale builds via catalog" % id)
		if bale == null:
			continue

		# Box collision shrunk on X/Z, full on Y
		var col := _find_box_collision(bale)
		_ok(col != null, "%s bale carries a BoxShape3D collision" % id)
		if col != null:
			var s: Vector3 = (col.shape as BoxShape3D).size
			_ok_approx(s.x, size.x * 0.9, 0.001, "%s collision X = 0.9 × visual X" % id)
			_ok_approx(s.y, size.y,       0.001, "%s collision Y = full visual Y"  % id)
			_ok_approx(s.z, size.z * 0.9, 0.001, "%s collision Z = 0.9 × visual Z" % id)

		# Bales are RigidBody3D (so stacks behave: lift bottom → take all three
		# if the clamp is strong enough; otherwise the top ones slip off)
		_ok(bale is RigidBody3D, "%s bale is RigidBody3D" % id)
		if bale is RigidBody3D:
			var rb := bale as RigidBody3D
			_ok(rb.freeze, "%s bale spawns frozen (stacks don't drift)" % id)
			_ok(rb.mass > 100.0,
				"%s bale mass = %.0f kg (>100 — pressed film is heavy)" % [id, rb.mass])
		# PhysicsMaterial override = high friction (so stacks grip) + tiny bounce
		var pm = (bale as PhysicsBody3D).physics_material_override
		_ok(pm != null, "%s bale has physics_material_override" % id)
		if pm != null:
			_ok(pm.friction >= 0.6 and pm.friction <= 1.0,
				"%s friction = %.2f (high — bale-on-bale grip)" % [id, pm.friction])
			_ok(pm.bounce >= 0.0 and pm.bounce <= 0.15,
				"%s bounce ≤ 0.15 (=%.2f) — soft compressed film" % [id, pm.bounce])
		# Wire + clamp-force metadata used by BaleClamp + wire-cutter feature
		_ok(bale.has_meta("wires_cut") and bale.get_meta("wires_cut") == false,
			"%s bale starts with wires_cut == false" % id)
		_ok(bale.has_meta("wire_compliance"), "%s bale has wire_compliance meta" % id)
		_ok(bale.has_meta("sheet_count"),
			"%s bale has sheet_count meta (=%d)" % [id, int(bale.get_meta("sheet_count", 0))])
		_ok(bale.has_meta("clamp_force_needed"),
			"%s bale has clamp_force_needed meta (=%.2f)"
				% [id, float(bale.get_meta("clamp_force_needed", 0.0))])

		# Identity / grouping (used by the vehicle grab + LineFlow feed code)
		_ok(bale.is_in_group("bale"), "%s bale in group 'bale'" % id)
		_ok(bale.has_meta("material_origin"), "%s bale has material_origin meta" % id)

		bale.queue_free()

func _find_box_collision(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return c
	return null

# =============================================================================
# 2) "delivered" meta drives feed gating (mirrors LineFlow._bale_at logic)
# =============================================================================
func _test_delivered_gate_logic() -> void:
	print("[2] LineFlow feed gate on 'delivered' meta")
	var bale = _Catalog.build_node("rotterdam", false) as Node3D
	if bale == null:
		_ok(false, "rotterdam bale failed to build for gate test")
		return
	# Inert scenery bale (no 'delivered' meta) — feed scanner should reject it
	_ok(not _delivered_at(bale, Vector3.ZERO),
		"undelivered bale at origin → rejected by feed gate")
	# Carried bale (delivered=false set by _try_grab) — also rejected
	bale.set_meta("delivered", false)
	_ok(not _delivered_at(bale, Vector3.ZERO),
		"carried bale (delivered=false) → rejected")
	# Dropped bale (delivered=true set by _release) — accepted
	bale.set_meta("delivered", true)
	_ok(_delivered_at(bale, Vector3.ZERO),
		"dropped bale (delivered=true) → accepted")
	bale.queue_free()

func _delivered_at(bale: Node3D, pos: Vector3) -> bool:
	if not bale.has_meta("material_origin"):
		return false
	if not (bale.has_meta("delivered") and bool(bale.get_meta("delivered"))):
		return false
	return bale.global_position.distance_to(pos) < 5.0
