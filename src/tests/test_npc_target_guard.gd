extends Node
## Guard test for BaseVehicle.npc_set_target's absurd-waypoint filter
## (BaseVehicle.gd, NPC_TARGET_MAX_R). The entry point used to accept ANY
## Vector3 — no finite check, no bounds check. This proves the guard now:
##   · ACCEPTS a normal in-plant waypoint (the real feeder lot centre),
##   · ACCEPTS a waypoint just inside the radius (the radius must not be so
##     tight that it clips legitimate plant geometry),
##   · REFUSES the measured 2026-07-20 bead coordinate x = 814.75,
##   · REFUSES a non-finite (NAN) coordinate,
## and that a refusal leaves the PREVIOUS valid waypoint untouched — the guard
## rejects the bad order, it must not invent or clear one.
##
## Two push_warning lines from BaseVehicle are EXPECTED in the output; they are
## the guard reporting, not a failure.
##
##   godot --headless --path . res://src/tests/test_npc_target_guard.tscn
##
## Touches no save file and needs no world: the vehicle is a bare BaseVehicle
## parented to this test node and freed before quit.

# A real in-plant waypoint: the feeder lot centre CrewManager binds
# (scene frame, ~205 m from the scene origin — comfortably inside the radius).
const GOOD_TARGET  : Vector3 = Vector3(-186.0, -8.0, 90.0)
# The measured bead from the operator's 2026-07-20 save / repro_feeder_drive.
const ABSURD_TARGET: Vector3 = Vector3(814.75, -8.35, 0.06)

func _ready() -> void:
	print("=== npc_set_target absurd-waypoint guard ===")
	var fails := 0

	var v := BaseVehicle.new()
	v.name = "GuardTestClamp"
	v.vehicle_type = "bale_clamp"
	add_child(v)                       # must be in-tree: global_position is read on refusal
	v.global_position = Vector3(-184.0, -8.0, 90.0)

	# 1 — a normal waypoint is accepted and fully engages the autopilot.
	v.npc_set_target(GOOD_TARGET)
	if v._npc_target.is_equal_approx(GOOD_TARGET) and v._npc_target_active and v.npc_autopilot:
		print("  ok    : normal target %s accepted" % str(GOOD_TARGET))
	else:
		print("  FAIL  : normal target %s was NOT accepted (target=%s active=%s autopilot=%s)" % [
			str(GOOD_TARGET), str(v._npc_target), str(v._npc_target_active), str(v.npc_autopilot)])
		fails += 1

	# 2 — just inside the radius is still accepted (the bound is not over-tight).
	var edge := Vector3(BaseVehicle.NPC_TARGET_MAX_R - 1.0, -8.0, 0.0)
	v.npc_set_target(edge)
	if v._npc_target.is_equal_approx(edge):
		print("  ok    : in-radius target at %.0f m accepted" % (BaseVehicle.NPC_TARGET_MAX_R - 1.0))
	else:
		print("  FAIL  : in-radius target at %.0f m was refused" % (BaseVehicle.NPC_TARGET_MAX_R - 1.0))
		fails += 1

	# Re-baseline on the good target so refusals below are checked against it.
	v.npc_set_target(GOOD_TARGET)

	# 3 — the measured bead coordinate is refused, prior waypoint untouched.
	v.npc_set_target(ABSURD_TARGET)
	if v._npc_target.is_equal_approx(GOOD_TARGET) and v._npc_target_active:
		print("  ok    : absurd target %s refused, previous waypoint intact" % str(ABSURD_TARGET))
	else:
		print("  FAIL  : absurd target %s was ACCEPTED (target now %s)" % [
			str(ABSURD_TARGET), str(v._npc_target)])
		fails += 1

	# 4 — a non-finite coordinate is refused, prior waypoint untouched.
	var nan_target := Vector3(NAN, -8.0, 90.0)
	v.npc_set_target(nan_target)
	if v._npc_target.is_equal_approx(GOOD_TARGET) and v._npc_target_active:
		print("  ok    : non-finite target refused, previous waypoint intact")
	else:
		print("  FAIL  : non-finite target was ACCEPTED (target now %s)" % str(v._npc_target))
		fails += 1

	v.queue_free()
	print("Result: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	get_tree().quit(0 if fails == 0 else 1)
