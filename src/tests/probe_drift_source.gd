extends Node3D
# =============================================================================
# PROBE — nested bale clamps translate forever. Attributed 2026-07-21.
#
# CAUSE (measured, see numbers below): BaseVehicle._kinematic_move calls
#   var hit := move_and_collide(motion)          # BaseVehicle.gd:1267
# EVERY frame, including while parked, when motion is EXACTLY Vector3.ZERO
# (_current_speed_mps == 0). On a pair of overlapping frozen-kinematic hulls
# Rapier's contact-recovery pass inside move_and_collide still TRANSLATES the
# body — and it returns NULL, so `hit != null` is false, the slide branch at
# :1270-1278 never runs, rotate_y is a no-op (yaw_rate == 0), _settle_on_ground
# only touches Y, and _clamp_carried_against_obstacles contributes nothing.
# 100 % of the horizontal drift comes from that one zero-motion call.
#
# Minimal world — NO MainWorld, NO BuildMode, NO world_layout, NO NPCs, no
# build-mode placement (so nothing here can write user://world_layout.json):
#   one StaticBody3D floor + N pairs of BaleClamp.tscn sharing an XZ, each
#   pair separated in Y by a per-pair gap, i.e. the nested "ladder" condition
#   that pre-clearance-gate saves still contain.
#
#   GODOT --headless --path . res://src/tests/probe_drift_source.tscn
#
# MEASURED (900 frames / 15 s, Godot 4.6.3 + Rapier3D 0.8.34, headless):
#   gap 0.40 → 10.40 m XZ, pure +X, rot.y 0.0000, still moving at frame 900
#   gap 0.80 → 23.12 m XZ, gap 0.95 → 23.07 m, gap 1.05 → 22.89 m
#   per-frame recovery step 0.010–0.022 m XZ (~0.6–1.3 m/s), motion==ZERO,
#   move_and_collide returned NULL on every one of those frames.
#   Out-of-band move_and_collide(Vector3.ZERO) on the same bodies displaced
#   them 0.0011–0.0473 m in XZ and likewise returned NULL.
# =============================================================================

const CLAMP := preload("res://src/scenes/vehicles/BaleClamp.tscn")
const FRAMES := 900          # 15 s at 60 Hz
const GAPS : Array[float] = [0.40, 0.80, 0.95, 1.05]   # Y separation per pair

var _pairs : Array = []
var _frame := 0
var _start : Dictionary = {}     # instance_id -> Vector3 (baseline)
var _prev : Dictionary = {}      # instance_id -> Vector3 (previous frame)
var _last_step : Dictionary = {} # instance_id -> Vector3 (frame N-1 -> N)

func _ready() -> void:
	print("=== PROBE — nested-clamp drift source ===")
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(400.0, 2.0, 400.0)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(0.0, -1.0, 0.0)
	add_child(floor_body)

	var x := 0.0
	for gap in GAPS:
		var lo := CLAMP.instantiate() as Node3D
		var hi := CLAMP.instantiate() as Node3D
		add_child(lo)
		add_child(hi)
		lo.global_position = Vector3(x, 0.0, 0.0)
		hi.global_position = Vector3(x, gap, 0.0)
		_pairs.append({"lo": lo, "hi": hi, "gap": gap})
		x += 60.0
	print("[probe] %d pairs spawned, gaps=%s" % [_pairs.size(), str(GAPS)])

func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 1:
		for p in _pairs:
			for k in ["lo", "hi"]:
				var n : Node3D = p[k]
				_start[n.get_instance_id()] = n.global_position
				_prev[n.get_instance_id()] = n.global_position
		return
	for p in _pairs:
		for k in ["lo", "hi"]:
			var n2 : Node3D = p[k]
			var id2 := n2.get_instance_id()
			_last_step[id2] = n2.global_position - (_prev[id2] as Vector3)
			_prev[id2] = n2.global_position
	if _frame >= FRAMES:
		_report()
		get_tree().quit()

func _report() -> void:
	print("--- SUMMARY after %d frames ---" % _frame)
	for p in _pairs:
		var lo : Node3D = p["lo"]
		var hi : Node3D = p["hi"]
		var d_lo : Vector3 = lo.global_position - (_start[lo.get_instance_id()] as Vector3)
		var d_hi : Vector3 = hi.global_position - (_start[hi.get_instance_id()] as Vector3)
		var step : Vector3 = _last_step[lo.get_instance_id()]
		print("gap=%.2f  lo moved %s (xz=%.3f m) rot.y=%.4f | hi xz=%.3f m | last-frame step xz=%.6f | sep=%.3f"
			% [float(p["gap"]), str(d_lo), Vector2(d_lo.x, d_lo.z).length(), lo.rotation.y,
				Vector2(d_hi.x, d_hi.z).length(),
				Vector2(step.x, step.z).length(),
				(hi.global_position - lo.global_position).length()])
	# The load-bearing evidence: a SINGLE out-of-band move_and_collide with an
	# exactly-zero motion vector still displaces an overlapping frozen-kinematic
	# hull, and reports no collision — the same call BaseVehicle.gd:1267 makes
	# every frame on every parked vehicle.
	print("--- move_and_collide(Vector3.ZERO) direct probe ---")
	for p in _pairs:
		var lo : PhysicsBody3D = p["lo"]
		var before : Vector3 = lo.global_position
		var kc : KinematicCollision3D = lo.move_and_collide(Vector3.ZERO)
		var after : Vector3 = lo.global_position
		print("gap=%.2f  ZERO-motion delta=%s |xz|=%.6f  returned_collision=%s"
			% [float(p["gap"]), str(after - before),
				Vector2(after.x - before.x, after.z - before.z).length(),
				str(kc != null)])
	print("=== PROBE DONE ===")
