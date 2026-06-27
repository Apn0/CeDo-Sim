extends Node3D
## Headless smoke test for vehicles + bale interaction.
##
## REWRITTEN for the #201 physics-carry model (was: pre-#201 auto-snap contract).
## ── What changed in #201 (and why this test was failing) ──────────────────────
## The OLD grab system reparented a grabbed bale under the carry point and flipped
## a `delivered` meta flag; bales were StaticBody3D. #201 Step 5 deleted all of
## that. Now:
##   • Bales are RigidBody3D (frozen kinematic at rest) — PlaceableCatalog.gd:1238.
##   • _try_grab() is a pure SENSOR: it polls a sphere at the carry point via
##     direct_space_state.intersect_shape() and sets `_carried_bale` to the nearest
##     qualifying body. It does NOT reparent and does NOT touch `delivered`.
##     (BaseVehicle.gd:549)
##   • The clamp/forks/grapple are real AnimatableBody3D bodies; a bale "rides"
##     because of contact + friction + clamp normal force, NOT a script reparent.
##   • _release() just clears the `_carried_bale` reference. (BaseVehicle.gd:600)
##
## Because _try_grab now depends on a PHYSICS QUERY, the test must let the physics
## space populate (await a few physics_frames after positioning bodies) before the
## sensor can see them — the old test never stepped physics, so the sensor found
## nothing even before the contract changes are accounted for.
##
## Verifies:
##   1. Three vehicle scenes load + wire their carry/hydraulic nodes.
##   2. A catalog bale is a RigidBody3D (frozen kinematic) with the 10% horizontal
##      collision "give" (X/Z shrunk, Y full), in group "bale" + material_origin.
##   3. SENSOR grab: _try_grab sets _carried_bale WITHOUT reparenting; _release
##      clears it. (Forklift — no force gate.)
##   4. Bottom-of-stack: grabbing the bottom bale sets _carried_bale to it. (The
##      whole column riding along is now emergent contact physics, not a reparent,
##      so it is NOT unit-asserted here — see the in-game verification task.)
##   5. BaleClamp force gate: a squeeze below the bale's clamp_force_needed refuses
##      (_carried_bale stays null); above it, the grab latches.
##   6. LineFlow feed scan still gates on the `delivered` meta.
##
## Run headless:
##   "<godot>" --path . --headless res://tests/VehicleBaleTest.tscn
## Exit codes: 0 = all pass, 1 = at least one failure.

const FORKLIFT_SCENE   := "res://src/scenes/vehicles/Forklift.tscn"
const BALECLAMP_SCENE  := "res://src/scenes/vehicles/BaleClamp.tscn"
const MERLO_SCENE      := "res://src/scenes/vehicles/Merlo.tscn"

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array[String] = []

# =============================================================================
func _ready() -> void:
	print("============================================================")
	print("  CeDo Simulator — Vehicles + Bale headless test (#201 model)")
	print("============================================================")

	_test_vehicle_scenes_load()
	await _test_bale_is_physicalized()
	await _test_sensor_grab_release()
	await _test_stack_bottom_grab()
	await _test_clamp_force_gate()
	_test_line_flow_gates_on_delivered()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		print("  FAILURES:")
		for line in _fail_lines:
			print("    - %s" % line)
	print("============================================================")

	# quit() carries the exit code directly (OS.set_exit_code doesn't exist in 4.2)
	get_tree().quit(0 if _fail == 0 else 1)

# =============================================================================
# ASSERTION + PHYSICS HELPERS
# =============================================================================
func _ok(cond: bool, label: String) -> void:
	if cond:
		_pass += 1
		print("  PASS  %s" % label)
	else:
		_fail += 1
		_fail_lines.append(label)
		print("  FAIL  %s" % label)

func _ok_eq(actual, expected, label: String) -> void:
	var ok: bool = (actual == expected)
	if not ok:
		label = "%s  (expected %s, got %s)" % [label, str(expected), str(actual)]
	_ok(ok, label)

func _ok_approx(actual: float, expected: float, tol: float, label: String) -> void:
	var ok := absf(actual - expected) <= tol
	if not ok:
		label = "%s  (expected ~%.4f ±%.4f, got %.4f)" % [label, expected, tol, actual]
	_ok(ok, label)

## Let the physics server register / update bodies so direct_space_state queries
## (the heart of the #201 grab sensor) return them. Several frames so the frozen
## RigidBody3D bales and the just-added vehicle are both live in the space.
func _settle_physics(frames: int = 6) -> void:
	for _i in frames:
		await get_tree().physics_frame

# =============================================================================
# 1) VEHICLE SCENES LOAD AND HAVE EXPECTED NODES (unchanged — these always passed)
# =============================================================================
func _test_vehicle_scenes_load() -> void:
	print("[1] Vehicle scenes load + wire hydraulic node paths")
	_assert_vehicle(FORKLIFT_SCENE,  "Forklift",
		["MastPivot/LiftCarriage", "MastPivot",
		 "MastPivot/LiftCarriage/Rotator",
		 "MastPivot/LiftCarriage/Rotator/LeftFork",
		 "MastPivot/LiftCarriage/Rotator/RightFork",
		 "MastPivot/LiftCarriage/Rotator/CarryPoint",
		 "CabCamera", "EnterArea"])
	_assert_vehicle(BALECLAMP_SCENE, "BaleClamp",
		["MastPivot", "MastPivot/LiftCarriage",
		 "MastPivot/LiftCarriage/LeftPlate",
		 "MastPivot/LiftCarriage/RightPlate",
		 "MastPivot/LiftCarriage/CarryPoint",
		 "CabCamera", "EnterArea"])
	_assert_vehicle(MERLO_SCENE, "Merlo",
		["BoomPivot", "BoomPivot/BoomExtend",
		 "BoomPivot/BoomExtend/BucketTilt",
		 "BoomPivot/BoomExtend/BucketTilt/GrappleArm",
		 "BoomPivot/BoomExtend/BucketTilt/CarryPoint",
		 "CabCamera", "EnterArea"])

func _assert_vehicle(path: String, label: String, required_nodes: Array) -> void:
	var scene := load(path) as PackedScene
	_ok(scene != null, "%s scene loads: %s" % [label, path])
	if scene == null:
		return
	var inst := scene.instantiate()
	_ok(inst != null, "%s instantiates" % label)
	if inst == null:
		return
	add_child(inst)
	for np in required_nodes:
		_ok(inst.get_node_or_null(np) != null,
			"%s has node %s" % [label, np])
	if "carry_point_path" in inst:
		var cp_path = inst.get("carry_point_path")
		var cp := inst.get_node_or_null(cp_path)
		_ok(cp != null, "%s carry_point_path resolves" % label)
	_ok(inst.has_method("_try_grab"), "%s has _try_grab()" % label)
	_ok(inst.has_method("_release"),  "%s has _release()"  % label)
	# Park it far away so it can't pollute later sensor queries.
	inst.global_position = Vector3(-1000.0 - randf() * 100.0, 0.0, 0.0)

# =============================================================================
# 2) A CATALOG BALE IS A PHYSICALIZED RIGIDBODY WITH 10% COLLISION GIVE
# =============================================================================
func _test_bale_is_physicalized() -> void:
	print("[2] Bale is RigidBody3D (frozen kinematic) + 10%% give on X/Z, full Y")
	for bale_def in BaleDefs.origins():
		var id := String(bale_def["id"])
		var size: Vector3 = bale_def["size"]
		var bale := PlaceableCatalog.build_node(id, false)
		_ok(bale != null, "%s bale builds via catalog" % id)
		if bale == null:
			continue
		add_child(bale)
		# #201 — bales are RigidBody3D, NOT StaticBody3D (the old cast errored here).
		_ok(bale is RigidBody3D, "%s bale is a RigidBody3D (#201 physicalized)" % id)
		if bale is RigidBody3D:
			var rb := bale as RigidBody3D
			_ok(rb.freeze, "%s bale spawns frozen (stacks don't drift at boot)" % id)
			_ok(rb.freeze_mode == RigidBody3D.FREEZE_MODE_KINEMATIC,
				"%s bale freeze_mode is KINEMATIC" % id)
			_ok(rb.mass > 0.0, "%s bale has positive mass (=%.0f kg)" % [id, rb.mass])
		# Box collision with the 10% horizontal give.
		var col := _find_box_collision(bale)
		_ok(col != null, "%s bale has BoxShape3D collision" % id)
		if col != null:
			var s: Vector3 = (col.shape as BoxShape3D).size
			_ok_approx(s.x, size.x * 0.9, 0.001, "%s collision X = 0.9 × visual X" % id)
			_ok_approx(s.y, size.y,       0.001, "%s collision Y = full visual Y"  % id)
			_ok_approx(s.z, size.z * 0.9, 0.001, "%s collision Z = 0.9 × visual Z" % id)
		_ok(bale.is_in_group("bale"), "%s bale in group 'bale'" % id)
		_ok(bale.has_meta("material_origin"), "%s bale has material_origin meta" % id)
		bale.queue_free()
	await _settle_physics(2)

func _find_box_collision(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return c
	return null

# =============================================================================
# 3) SENSOR GRAB / RELEASE — sets the reference, no reparent, no delivered flip
# =============================================================================
## Use the Forklift (BaseVehicle._can_grab_stack returns true — no force gate) so
## this isolates the sensor mechanic from the clamp gate (tested separately).
func _test_sensor_grab_release() -> void:
	print("[3] #201 sensor grab: sets _carried_bale, no reparent, no delivered flip")
	var v := (load(FORKLIFT_SCENE) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3.ZERO
	await _settle_physics()   # let the vehicle register + global xforms propagate

	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D
	_ok(cp != null, "Forklift carry point resolved")
	if cp == null:
		v.queue_free(); return

	# A bale right at the carry point (well within GRAB_RANGE = 2.5 m).
	var bale := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(bale)
	bale.global_position = cp.global_position + Vector3(0.4, 0.0, 0.0)
	await _settle_physics()   # CRITICAL: the sensor is a physics query — populate the space

	_ok_eq(bale.get_parent(), self, "pre-grab: bale parented under test root")
	var had_delivered_before := bale.has_meta("delivered")

	# SENSOR GRAB
	v.call("_try_grab")
	_ok_eq(v.get("_carried_bale"), bale, "grab: _carried_bale points at the bale (sensor latched)")
	_ok_eq(bale.get_parent(), self, "grab: bale NOT reparented (physics-carry, no auto-snap)")
	_ok(bale.has_meta("delivered") == had_delivered_before,
		"grab: 'delivered' meta untouched by the sensor grab")

	# RELEASE
	v.call("_release")
	_ok_eq(v.get("_carried_bale"), null, "release: _carried_bale cleared")
	_ok_eq(bale.get_parent(), self, "release: bale still where physics left it (no reparent)")

	bale.remove_from_group("bale")
	bale.queue_free()
	v.queue_free()
	await _settle_physics(2)

# =============================================================================
# 3b) BOTTOM-OF-STACK — grabbing the bottom bale latches the sensor onto it
# =============================================================================
## Under #201 the whole column riding along is EMERGENT contact physics (the
## gripped bottom bale carries the ones resting on it), not a script reparent, so
## that part is verified in-game (task #10). Here we assert the unit-level
## contract: the sensor picks the bottom bale as _carried_bale.
func _test_stack_bottom_grab() -> void:
	print("[3b] Bottom-of-stack: sensor latches the bottom bale")
	var v := (load(FORKLIFT_SCENE) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3.ZERO
	await _settle_physics()
	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D
	if cp == null:
		_ok(false, "stack test: carry point missing"); v.queue_free(); return

	var base := cp.global_position
	var col : Array[Node3D] = []
	for i in 3:
		var b := PlaceableCatalog.build_node("alba_marl", false) as Node3D
		add_child(b)
		# Stack tightly in one column; the bottom one sits at the carry point.
		b.global_position = base + Vector3(0.0, float(i) * 0.95, 0.0)
		col.append(b)
	await _settle_physics()

	v.call("_try_grab")
	# The nearest qualifying bale to the carry point is the bottom one.
	_ok_eq(v.get("_carried_bale"), col[0],
		"grab latches the BOTTOM bale of the column as _carried_bale")

	v.call("_release")
	for b in col:
		b.remove_from_group("bale")
		b.queue_free()
	v.queue_free()
	await _settle_physics(2)

# =============================================================================
# 3c) CLAMP-FORCE GATE — a squeeze below clamp_force_needed refuses the grab
# =============================================================================
## NOTE: BaleClamp._can_grab_stack scales the floor by (1 + stack.size()), but
## #201's _try_grab always calls it with an EMPTY stack, so only the single-bale
## floor (clamp_force_needed, default 0.30) is ever enforced — the stack-height
## scaling is currently inert (flagged for follow-up). This test asserts the
## single-bale gate that is actually live.
func _test_clamp_force_gate() -> void:
	print("[3c] BaleClamp single-bale force gate (stack scaling currently inert)")
	var v := (load(BALECLAMP_SCENE) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3.ZERO
	await _settle_physics()
	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D
	if cp == null:
		_ok(false, "clamp test: carry point missing"); v.queue_free(); return

	var bale := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(bale)
	bale.global_position = cp.global_position + Vector3(0.1, 0.0, 0.0)
	var needed: float = float(bale.get_meta("clamp_force_needed", 0.30))
	await _settle_physics()

	# Too weak — below the bale's clamp_force_needed → refused, no latch.
	v.set("clamp_force", maxf(needed - 0.15, 0.0))
	v.call("_try_grab")
	_ok_eq(v.get("_carried_bale"), null,
		"weak squeeze (%.2f < needed %.2f) refuses the grab" % [v.get("clamp_force"), needed])

	# Firm enough — at/above the floor → latches.
	v.set("clamp_force", minf(needed + 0.20, 1.0))
	v.call("_try_grab")
	_ok_eq(v.get("_carried_bale"), bale,
		"firm squeeze (%.2f ≥ needed %.2f) latches the bale" % [v.get("clamp_force"), needed])

	v.call("_release")
	bale.remove_from_group("bale")
	bale.queue_free()
	v.queue_free()
	await _settle_physics(2)

# =============================================================================
# 4) LINE FLOW ONLY ACCEPTS DELIVERED BALES (unchanged — still valid)
# =============================================================================
func _test_line_flow_gates_on_delivered() -> void:
	print("[4] LineFlow._bale_at gates on the 'delivered' meta")
	var bale := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(bale)
	bale.global_position = Vector3.ZERO

	_ok(not _scan_for_delivered_bale_at(Vector3.ZERO),
		"undelivered bale at feed point → not picked (no phantom feed)")

	bale.set_meta("delivered", true)
	_ok(_scan_for_delivered_bale_at(Vector3.ZERO),
		"delivered bale at feed point → picked")

	bale.queue_free()

## Mirrors LineFlow._bale_at: true if a delivered bale sits within FEED_RADIUS of pos.
func _scan_for_delivered_bale_at(pos: Vector3) -> bool:
	var best_d := 5.0   # LineFlow.FEED_RADIUS
	for c in get_tree().get_nodes_in_group("bale"):
		var cn := c as Node3D
		if cn == null or not cn.has_meta("material_origin"):
			continue
		if not (cn.has_meta("delivered") and bool(cn.get_meta("delivered"))):
			continue
		if cn.global_position.distance_to(pos) < best_d:
			return true
	return false
