extends SceneTree

const _LaserFilter := preload("res://src/sim/LaserFilter.gd")

var _pass : int = 0
var _fail : int = 0
var _fail_lines : Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — LaserFilter headless test")
	print("============================================================")

	_test_sausage_growth_and_breakoff()

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
# Mocks
# =============================================================================
class MockMainWorld extends Node3D:
	pass

class MockParent extends Node3D:
	pass

# =============================================================================
# Tests
# =============================================================================
func _test_sausage_growth_and_breakoff() -> void:
	print("[1] LaserFilter sausage growth and breakoff")

	# Setup mock tree so _break_off_sausage can find a place to drop chunks
	var world = MockMainWorld.new()
	var parent = MockParent.new()
	var filter = _LaserFilter.new()

	world.add_child(parent)
	parent.add_child(filter)

	_ok(filter._sausage_len_m == 0.0, "Starts with zero sausage length")

	# Grow sausage by small amount
	filter._grow_sausage(1.0, 10.0)

	_ok(filter._sausage != null, "Sausage mesh created")
	_ok_approx(filter._sausage_len_m, 0.02, 0.0001, "Sausage length increased")

	var cyl = filter._sausage.mesh as CylinderMesh
	_ok(cyl != null, "Sausage mesh is a CylinderMesh")
	if cyl:
		_ok_approx(cyl.height, 0.02, 0.0001, "Cylinder height updated")

	# Force length to near max, then grow a bit more to trigger breakoff
	filter._sausage_len_m = 0.54
	filter._grow_sausage(1.0, 10.0)

	_ok_approx(filter._sausage_len_m, 0.0, 0.0001, "Sausage length reset after breakoff")

	var chunks = []
	for child in world.get_children():
		if child.name == "LumpChunk":
			chunks.append(child)

	for child in parent.get_children():
		if child.name == "LumpChunk":
			chunks.append(child)

	_ok(chunks.size() == 1, "One chunk dropped into world")
	if chunks.size() > 0:
		_ok(chunks[0] is RigidBody3D, "Dropped chunk is RigidBody3D")
		_ok(chunks[0].is_in_group("lump_chunk"), "Chunk is in lump_chunk group")

	world.queue_free()
