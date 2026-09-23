extends Node
## Cost of the belt film beds (P1, 2026-09-23). Headless has no camera, so the
## field's 30 m distance cull never fires: this measures the WORST case — every
## field animating a full, moving bed at its 20 Hz tick. Builds N intake belts
## through the catalog (build_node, merged), drives every field, and reports
## the microseconds the fields themselves spent per frame (FilmFlakeField's
## own profiling counter — attribution, not a frame monitor) next to the wall
## time per frame.
##
##   godot --headless --path . res://src/tests/probe_belt_field_cost.tscn

const N_BELTS := 24
const WARM := 30
const FRAMES := 240

var _fields : Array = []
var _phase := 0
var _f := 0
var _wall_us := 0
var _t_prev := 0
var _results : Array = []

func _ready() -> void:
	for i in N_BELTS:
		var body : Node3D = PlaceableCatalog.build_node("transportband_%d" % (1 + (i % 7)), false)
		add_child(body)
		body.global_position = Vector3(3.0 * float(i), 0.0, 0.0)
	await get_tree().process_frame
	for c in get_tree().get_nodes_in_group("film_field"):
		_fields.append(c)
	var budgets : Array = []
	for f in _fields:
		budgets.append(int(f.get("flake_count")))
	print("[PROBE] %d belts, %d fields, flake budgets %s" % [N_BELTS, _fields.size(), budgets])
	FilmFlakeField.profiling = true
	_set_phase(0)

func _drive_all(ph: int) -> void:
	for f in _fields:
		match ph:
			0: f.call("set_belt_state", 0.0, 0.5, true, 0.0, 0.0, 0.1)      # bare
			1: f.call("set_belt_state", 1.2, 0.5, true, 0.0, 0.0, 0.1)      # thin bed, ~43 % of flakes
			2: f.call("set_belt_state", 20.0, 0.5, true, 0.0, 0.0, 0.1)     # full bed, every flake
			3: f.call("set_belt_state", 20.0, 0.5, false, 0.0, 0.0, 0.1)    # full bed, deck STOPPED

func _set_phase(ph: int) -> void:
	_phase = ph
	_f = 0
	_wall_us = 0
	# let the slew settle (a bed fills over the belt's transit time)
	for _i in 400:
		_drive_all(ph)
	FilmFlakeField.profile_us = 0
	_t_prev = Time.get_ticks_usec()

func _process(_delta: float) -> void:
	var now : int = Time.get_ticks_usec()
	_f += 1
	if _f == WARM:
		FilmFlakeField.profile_us = 0
		_t_prev = now
		return
	if _f < WARM:
		return
	_wall_us += now - _t_prev
	_t_prev = now
	if _f < WARM + FRAMES:
		return
	var field_us : float = float(FilmFlakeField.profile_us) / float(FRAMES)
	var wall_ms : float = float(_wall_us) / float(FRAMES) / 1000.0
	var vis := 0
	for f in _fields:
		vis += int(f.call("visible_count"))
	var names := ["bare", "thin bed moving", "full bed moving", "full bed stopped"]
	_results.append("  %-18s %5d flakes visible   fields %7.1f us/frame (%5.1f us per field)   wall %.2f ms/frame"
		% [names[_phase], vis, field_us, field_us / float(maxi(_fields.size(), 1)), wall_ms])
	if _phase < 3:
		_set_phase(_phase + 1)
	else:
		for r in _results:
			print(r)
		print("Result: PASS (probe)")
		get_tree().quit(0)
