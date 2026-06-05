extends Node3D

## #173 visual coupling — the flake layer's LOOK is a pure function of the live
## baked numbers, so tweaking the model later still makes the visuals match.
##   [1] FilmFlakeField.set_live_state: density←present, speed←load, wet/dirty←tint
##   [2] LineFlow discovers a machine's field, applies the BAKED coefficients, and
##       drives the field from the node's live buffer/moisture/contam each tick.

const FilmFlakeField = preload("res://src/sim/FilmFlakeField.gd")
const LineFlowScript = preload("res://src/sim/LineFlow.gd")
const ProcessModel   = preload("res://src/sim/ProcessModel.gd")
const MaterialBatch  = preload("res://src/sim/MaterialBatch.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	print("=== #173 FLAKE COUPLING — visuals driven by live numbers ===")
	_test_set_live_state()
	_test_lineflow_drives_field()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _test_set_live_state() -> void:
	print("[1] set_live_state maps numbers → look")
	var f = FilmFlakeField.new()
	f.flake_count = 100
	f.flow_speed = 0.5
	add_child(f)                       # _ready builds the MultiMesh synchronously
	# Density follows material present.
	f.set_live_state(0.0, 0.0, 0.0, 0.0)
	_ok(f.visible_count() == 0, "no material → no visible flakes")
	f.set_live_state(0.5, 0.0, 0.0, 1.0)
	_ok(f.visible_count() == 100, "full buffer → all flakes visible")
	f.set_live_state(0.0, 0.0, 0.0, 0.5)
	_ok(f.visible_count() == 50, "half buffer → half the flakes")
	# Throughput drives drift speed.
	f.set_live_state(1.0, 0.0, 0.0, 1.0)
	_ok(f.flow_speed > 0.5, "higher throughput → faster drift (%.2f)" % f.flow_speed)
	# Wetness drives a glossy, darker look.
	f.set_live_state(0.5, 0.0, 0.0, 1.0)        # dry
	var dry_rough : float = f._mat.roughness
	f.set_live_state(0.5, 1.0, 0.0, 1.0)        # soaked
	_ok(f._mat.roughness < dry_rough, "wet flake is glossier (rough %.2f → %.2f)" % [dry_rough, f._mat.roughness])
	# Dirt pulls the tint brown (red channel stays high, blue drops).
	f.set_live_state(0.5, 0.0, 1.0, 1.0)
	_ok(f._mat.albedo_color.b < f._mat.albedo_color.r, "dirty flake tints brown")
	f.queue_free()

func _test_lineflow_drives_field() -> void:
	print("[2] LineFlow finds the field, applies baked coefficients, drives it")
	var machine := PlaceableCatalog.build_node("flotation_tank", false) as Node3D
	add_child(machine)
	machine.global_position = Vector3(0, 0, 0)
	machine.set_meta("placeable_id", "flotation_tank")
	machine.set_meta("l3c_code", "L3C.11")        # Flotatietank — a baked stage
	if not machine.is_in_group("placed_object"):
		machine.add_to_group("placed_object")
	var field = FilmFlakeField.new()
	field.flake_count = 80
	machine.add_child(field)

	var lf = LineFlowScript.new()
	add_child(lf)
	lf.set_process(false)
	lf.auto_start = false                         # keep it cold so buffer doesn't drain
	lf.rebuild()

	# Find the discovered node for our machine.
	var nd : Dictionary = {}
	for n in lf._nodes:
		if String(n.get("l3c_code", "")) == "L3C.11":
			nd = n
			break
	_ok(not nd.is_empty(), "machine discovered as a Line 3C node")
	_ok(nd.get("view") != null, "LineFlow linked the machine's flake field")
	# The BAKED coefficient was applied (not MachineFlow's generic flotation value).
	var baked : Dictionary = ProcessModel.stage_transfer("L3C.11")
	_ok(absf(float(nd.get("contam_remove", -1)) - float(baked["contam_remove"])) < 0.001,
		"baked contam_remove applied (%.2f)" % float(nd.get("contam_remove", -1)))

	# Put material in the machine and tick — the field should light up with flakes.
	(nd["in"] as MaterialBatch).add(MaterialBatch.new(200.0, 0.6, {"LDPE": 1.0}, "test", 60.0, 20.0))
	for i in range(4):
		lf.tick(1.0 / 60.0)
	_ok(field.visible_count() > 0, "material present → field shows flakes (%d)" % field.visible_count())
	lf.queue_free()
