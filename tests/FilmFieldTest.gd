extends Node3D

## Headless test for FilmFlakeField (#161): flakes build, drift downstream,
## wrap at the far edge, and get dunked under the surface inside a paddle zone.

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	await _test_build_and_drift()
	await _test_dunk_zone()
	await _test_wrap()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _make_field() -> Node3D:
	var f : Node3D = preload("res://src/sim/FilmFlakeField.gd").new()
	f.flake_count = 60
	f.area = Vector2(2.0, 6.0)
	f.surface_y = 0.0
	add_child(f)
	return f

func _test_build_and_drift() -> void:
	print("[1] field builds flakes + drifts downstream")
	var f = _make_field()
	f.flow_speed = 1.0
	await get_tree().process_frame    # let _ready build the MultiMesh
	f.set_process(false)              # take manual control of ticking
	f._mm.visible_instance_count = f._mm.instance_count   # wake the perf idle-gate (in-game LineFlow does this via set_live_state)
	_ok(f._mm != null and f._mm.instance_count == 60, "60 flake instances built")
	f._px[0] = 0.0
	f._pz[0] = 0.0
	f._process(0.5)                   # 1.0 m/s × 0.5 s = +0.5 downstream
	_ok(absf(f.flake_local_pos(0).z - 0.5) < 0.02, "flake drifted +0.5 m (z=%.2f)" % f.flake_local_pos(0).z)
	f.queue_free()

func _test_dunk_zone() -> void:
	print("[2] paddle dunk zone pushes film under the surface")
	var f = _make_field()
	f.flow_speed = 0.1
	f.dunk_depth = 0.4
	await get_tree().process_frame
	f.set_process(false)
	f._mm.visible_instance_count = f._mm.instance_count   # wake the perf idle-gate
	f._px[0] = 0.0
	f._pz[0] = 0.0
	f.add_dunk_zone(0.0, 0.0, 1.0)
	for i in range(8):
		f._process(0.15)
	_ok(f.dunk_amount(0) > 0.3, "flake in zone is being dunked (%.2f)" % f.dunk_amount(0))
	_ok(f.flake_local_pos(0).y < 0.0, "dunked flake sits below the surface (y=%.2f)" % f.flake_local_pos(0).y)
	f.queue_free()

func _test_wrap() -> void:
	print("[3] flakes wrap at the downstream edge (stay in bounds)")
	var f = _make_field()
	f.flow_speed = 5.0
	await get_tree().process_frame
	f.set_process(false)
	f._mm.visible_instance_count = f._mm.instance_count   # wake the perf idle-gate
	# Drive well past the far edge; every flake must wrap back into [-3, 3].
	for i in range(20):
		f._process(0.2)
	var in_bounds := true
	for i in range(f.flake_count):
		if absf(f.flake_local_pos(i).z) > f.area.y * 0.5 + 0.01:
			in_bounds = false
			break
	_ok(in_bounds, "all flakes wrapped within the field length")
	f.queue_free()
