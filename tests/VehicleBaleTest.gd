extends Node3D
## Headless smoke test for vehicles + bale interaction.
##
## Verifies:
##   1. Three vehicle scenes (Forklift, BaleClamp, Merlo) load + instantiate.
##   2. Each vehicle wires its expected hydraulic/carry-point nodes.
##   3. A bale spawns through PlaceableCatalog with the 10% horizontal "give"
##      (collision shape shrunk on X/Z, full on Y) and carries a PhysicsMaterial.
##   4. The "delivered" meta flag follows pickup → release lifecycle.
##   5. _try_grab reparents the bale to the vehicle's carry point + flips
##      delivered=false; _release reparents back + flips delivered=true.
##
## Run headless:
##   "<godot>" --headless --path . res://tests/VehicleBaleTest.tscn
##
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
	print("  CeDo Simulator — Vehicles + Bale headless test")
	print("============================================================")

	_test_vehicle_scenes_load()
	_test_bale_collision_give()
	_test_grab_release_lifecycle()
	_test_stack_pickup()
	_test_clamp_force_gates_stack()
	_test_carry_clamp_against_obstacle()
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
# ASSERTION HELPERS
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

# =============================================================================
# 1) VEHICLE SCENES LOAD AND HAVE EXPECTED NODES
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
	# Required node paths exist
	for np in required_nodes:
		_ok(inst.get_node_or_null(np) != null,
			"%s has node %s" % [label, np])
	# Carry point path is exported and matches a real node
	if "carry_point_path" in inst:
		var cp_path = inst.get("carry_point_path")
		var cp := inst.get_node_or_null(cp_path)
		_ok(cp != null, "%s carry_point_path resolves" % label)
	# Bale-grab API is inherited from BaseVehicle
	_ok(inst.has_method("_try_grab"), "%s has _try_grab()" % label)
	_ok(inst.has_method("_release"),  "%s has _release()"  % label)
	# Keep instance for later tests
	inst.global_position = Vector3(-1000.0 - randf() * 100.0, 0.0, 0.0)

# =============================================================================
# 2) BALE COLLISION SHAPE HAS 10% HORIZONTAL "GIVE"
# =============================================================================
func _test_bale_collision_give() -> void:
	print("[2] Bale collision shape (10%% give on X/Z, full Y)")
	for bale_def in BaleDefs.origins():
		var id := String(bale_def["id"])
		var size: Vector3 = bale_def["size"]
		var bale := PlaceableCatalog.build_node(id, false)
		_ok(bale != null, "%s bale builds via catalog" % id)
		if bale == null:
			continue
		add_child(bale)
		# Find the box collision shape
		var col := _find_box_collision(bale)
		_ok(col != null, "%s bale has BoxShape3D collision" % id)
		if col == null:
			continue
		var s: Vector3 = (col.shape as BoxShape3D).size
		_ok_approx(s.x, size.x * 0.9, 0.001, "%s collision X = 0.9 × visual X" % id)
		_ok_approx(s.y, size.y,       0.001, "%s collision Y = full visual Y"  % id)
		_ok_approx(s.z, size.z * 0.9, 0.001, "%s collision Z = 0.9 × visual Z" % id)
		# Physics material override is set
		var pm = (bale as StaticBody3D).physics_material_override
		_ok(pm != null, "%s bale has physics_material_override" % id)
		if pm != null:
			_ok(pm.friction > 0.0 and pm.friction < 1.0,
				"%s bale friction in (0, 1) = %.2f" % [id, pm.friction])
			_ok(pm.bounce >= 0.0 and pm.bounce <= 0.25,
				"%s bale bounce ≤ 0.25 (=%.2f) — soft, not rubber" % [id, pm.bounce])
		# Bale is in the "bale" group + tagged with material_origin meta
		_ok(bale.is_in_group("bale"), "%s bale in group 'bale'" % id)
		_ok(bale.has_meta("material_origin"), "%s bale has material_origin meta" % id)
		bale.queue_free()

func _find_box_collision(node: Node) -> CollisionShape3D:
	for c in node.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return c
	return null

# =============================================================================
# 3) GRAB → CARRY → RELEASE LIFECYCLE
# =============================================================================
func _test_grab_release_lifecycle() -> void:
	print("[3] Grab/release lifecycle for each vehicle")
	_grab_release_with(FORKLIFT_SCENE, "Forklift")
	_grab_release_with(BALECLAMP_SCENE, "BaleClamp")
	_grab_release_with(MERLO_SCENE, "Merlo")

func _grab_release_with(scene_path: String, label: String) -> void:
	var scene := load(scene_path) as PackedScene
	if scene == null:
		_ok(false, "%s scene missing for grab test" % label)
		return
	var v := scene.instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3(0.0, 0.0, 0.0)

	# Bale near the vehicle's carry point
	var bale := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(bale)
	var carry_cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D
	_ok(carry_cp != null, "%s carry point resolved" % label)
	if carry_cp != null:
		# Position bale within GRAB_RANGE (2.5m) of the carry point
		bale.global_position = carry_cp.global_position + Vector3(0.5, 0.0, 0.0)

	# Initial state: bale parented to test root
	_ok_eq(bale.get_parent(), self, "%s pre-grab: bale parented under test root" % label)

	# Vehicle grabs
	v.call("_try_grab")
	# After grab: bale parented under carry point, delivered meta = false
	if carry_cp != null:
		_ok_eq(bale.get_parent(), carry_cp,
			"%s post-grab: bale reparented to carry point" % label)
	_ok(bale.has_meta("delivered") and bale.get_meta("delivered") == false,
		"%s post-grab: bale.delivered == false (won't feed the line while carried)" % label)

	# Vehicle releases
	v.call("_release")
	# After release: bale parented back to original parent (test root), delivered = true
	_ok_eq(bale.get_parent(), self, "%s post-release: bale reparented to original" % label)
	_ok(bale.has_meta("delivered") and bale.get_meta("delivered") == true,
		"%s post-release: bale.delivered == true (now eligible to feed the line)" % label)

	# queue_free() is deferred — the freed bale lingers in the "bale" group until
	# end of frame, and these tests all run synchronously in one _ready() pass. Pull
	# it out of the group now so the later feed-scan test (#4) doesn't see this
	# released (delivered=true) bale sitting near the origin as a phantom feed.
	bale.remove_from_group("bale")
	v.queue_free()
	bale.queue_free()

# =============================================================================
# 3b) BOTTOM-OF-STACK PICKUP — grab the bottom bale, the whole column rides along
# =============================================================================
## Build a 3-tall column of bales, grab the BOTTOM one with a forklift, and assert
## all three reparent to the carry point (and all three return on release). This is
## the "pick up the bottom bale and take all 2/3" behaviour.
func _test_stack_pickup() -> void:
	print("[3b] Bottom-of-stack pickup (whole column rides along)")
	var v := (load(FORKLIFT_SCENE) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3(0, 0, 0)
	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D

	# 3 bales stacked in one column at the carry point (~0.9 m tall each).
	var col : Array[Node3D] = []
	var base := cp.global_position if cp else Vector3.ZERO
	for i in 3:
		var b := PlaceableCatalog.build_node("alba_marl", false) as Node3D
		add_child(b)
		b.global_position = base + Vector3(0.0, float(i) * 0.95, 0.0)
		col.append(b)

	v.call("_try_grab")
	var grabbed := 0
	for b in col:
		if b.get_parent() == cp:
			grabbed += 1
	_ok(grabbed == 3, "grab bottom bale → all 3 in the column ride the carry point (got %d)" % grabbed)
	# All three must be flagged not-delivered while carried.
	var all_held := true
	for b in col:
		if not (b.has_meta("delivered") and b.get_meta("delivered") == false):
			all_held = false
	_ok(all_held, "every carried bale in the stack is delivered=false")

	v.call("_release")
	var returned := 0
	for b in col:
		if b.get_parent() == self:
			returned += 1
	_ok(returned == 3, "release → all 3 bales returned to the world (got %d)" % returned)

	for b in col:
		b.remove_from_group("bale")
		b.queue_free()
	v.queue_free()

# =============================================================================
# 3c) CLAMP-FORCE GATE — a weak squeeze can't lift a tall stack
# =============================================================================
## The bale clamp scales the required grip by stack height. A light clamp_force
## that easily lifts ONE bale must REFUSE a 3-tall column (until squeezed harder).
func _test_clamp_force_gates_stack() -> void:
	print("[3c] Clamp-force gate scales with stack height")
	var v := (load(BALECLAMP_SCENE) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3(0, 0, 0)
	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D
	var base := cp.global_position if cp else Vector3.ZERO

	# A 3-tall column; each bale needs clamp_force_needed=0.30 on its own, so a
	# 3-stack floor is ~0.90. Set a middling force that lifts one but not three.
	var col : Array[Node3D] = []
	for i in 3:
		var b := PlaceableCatalog.build_node("rotterdam", false) as Node3D
		add_child(b)
		b.global_position = base + Vector3(0.0, float(i) * 0.95, 0.0)
		col.append(b)

	v.set("clamp_force", 0.45)            # > one-bale floor (0.30), < three-bale floor (~0.90)
	v.call("_try_grab")
	_ok(v.get("_carried_bale") == null, "weak squeeze (0.45) refuses the 3-stack")

	v.set("clamp_force", 0.95)            # plenty for three
	v.call("_try_grab")
	var n := 0
	for b in col:
		if b.get_parent() == cp:
			n += 1
	_ok(v.get("_carried_bale") != null and n == 3,
		"firm squeeze (0.95) lifts the whole 3-stack (got %d)" % n)

	v.call("_release")
	for b in col:
		b.remove_from_group("bale")
		b.queue_free()
	v.queue_free()

# =============================================================================
# 3d) CARRIED LOAD CAN'T SINK THROUGH OBSTACLES BELOW IT
# =============================================================================
## Lowering a clamped bale onto another bale used to pass straight through it
## (kinematic-vs-kinematic in Godot doesn't auto-stop). The new positional clamp
## should push the carried stack UP so the lowest bale's bottom rests on the
## obstacle's top. Headless: grab a bale, place a static bale below it inside the
## clamp's natural carry position, run the clamp, assert the carried bale's
## bottom is at-or-above the static bale's top.
func _test_carry_clamp_against_obstacle() -> void:
	print("[3d] Carried bale can't sink through obstacles below it")
	var v := (load(BALECLAMP_SCENE) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3.ZERO
	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D

	# Grab a primary bale at the carry point's natural position.
	var primary := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(primary)
	primary.global_position = cp.global_position + Vector3(0.05, 0, 0)
	# Make sure the clamp's force gate doesn't refuse.
	v.set("clamp_force", 0.9)
	v.call("_try_grab")
	if v.get("_carried_bale") == null:
		_ok(false, "carry-clamp test: prerequisite grab failed")
		return

	# Park a static bale directly UNDER the carried one (top sits 0.4 m below
	# where the carried bale naturally hangs from the carry point).
	var carried_bottom_y: float = primary.global_position.y - 0.5
	var obstacle := PlaceableCatalog.build_node("zwolle", false) as Node3D
	add_child(obstacle)
	var ob_size: float = 1.2   # zwolle is 1.2 m cubic
	var obstacle_top_y: float = carried_bottom_y + 0.4   # 40 cm of intrusion if unclamped
	obstacle.global_position = Vector3(primary.global_position.x,
		obstacle_top_y - ob_size * 0.5, primary.global_position.z)

	# Call the clamp directly — _kinematic_move would also run the chassis settle
	# raycast which can pick up the test obstacle as "floor" and lift/drop the
	# vehicle, polluting the test. The clamp itself is the unit under test.
	v.call("_clamp_carried_against_obstacles")

	var new_bottom: float = primary.global_position.y - 0.5
	_ok(new_bottom >= obstacle_top_y - 0.01,
		"carried bale's bottom rests AT or ABOVE the obstacle's top (bottom=%.2f, top=%.2f)"
			% [new_bottom, obstacle_top_y])

	obstacle.remove_from_group("bale")
	primary.remove_from_group("bale")
	v.queue_free()
	primary.queue_free()
	obstacle.queue_free()

# =============================================================================
# 4) LINE FLOW ONLY ACCEPTS DELIVERED BALES
# =============================================================================
func _test_line_flow_gates_on_delivered() -> void:
	print("[4] LineFlow._bale_at gates on the 'delivered' meta")
	# We don't want to run the full LineFlow (it depends on placed machines etc).
	# Instead we exercise the gate logic directly by building a tiny inline copy.
	var bale := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(bale)
	bale.global_position = Vector3.ZERO

	# A "scenery" bale (never delivered) is invisible to the feed scanner
	_ok(not _scan_for_delivered_bale_at(Vector3.ZERO),
		"undelivered bale at feed point → not picked (no phantom feed)")

	# A "delivered" bale (vehicle-released) is picked
	bale.set_meta("delivered", true)
	_ok(_scan_for_delivered_bale_at(Vector3.ZERO),
		"delivered bale at feed point → picked")

	bale.queue_free()

## Mirrors LineFlow._bale_at: returns true if there's a delivered bale within
## FEED_RADIUS of pos. Kept inline so the test doesn't depend on the LineFlow
## scene tree.
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
