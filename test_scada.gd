extends SceneTree
## Headless harness for the ISA-101 SCADA dashboard (task #47).
##
## Proves, without launching the game and without depending on the engine clock:
##   * ScadaDashboard.gd parses + instances
##   * a Running → Idle → Running cycle completed in < 60 s logs EXACTLY one
##     Micro-Stop AND leaves the dashboard live (no full-shutdown visual)
##   * an Idle gap of > 60 s does NOT log a Micro-Stop
##   * parameters in-band stay grey; out-of-band alarm (ISA-101 colour rule)
##
## Time is driven by a manual counter injected via set_time_source(), so the
## result is fully deterministic and never touches Time.get_ticks.
##
## Run:  godot --headless --path . --script res://test_scada.gd
## (godot = whatever is on PATH, else %LOCALAPPDATA%\Godot\godot.exe — see
##  tests/run_tests.bat)

var _fail := 0
var _ran  := false

# Manual clock — the value the injected time source returns (seconds).
var _clock_s : float = 0.0

func _now() -> float:
	return _clock_s

func _process(_delta: float) -> bool:
	# Run once on the FIRST frame (not _init): only by now is the SceneTree root
	# actually in-tree, so a CanvasLayer we add reports is_inside_tree()==true and
	# its panel visibility is meaningful. Mirrors test_crew.gd.
	if _ran:
		return true
	_ran = true
	print("=== SCADA dashboard harness (task #47) ===")
	_parse()
	_micro_stop_under_window()
	_long_idle_no_micro_stop()
	_repeated_micro_stops()
	_isa101_alarm_colours()
	_params_dont_trip_shutdown()
	if _fail == 0:
		print("\nALL OK")
	else:
		print("\n%d FAILED" % _fail)
	return true   # returning true ends the main loop (clean quit)

func _ok(c: bool, msg: String) -> void:
	print(("  ok  : " if c else "  FAIL: ") + msg)
	if not c:
		_fail += 1

# -----------------------------------------------------------------------------
func _make_dash() -> ScadaDashboard:
	var dash := ScadaDashboard.new()
	get_root().add_child(dash)          # in-tree → _ready built the UI
	dash.set_time_source(Callable(self, "_now"))
	_clock_s = 0.0
	return dash

# -----------------------------------------------------------------------------
func _parse() -> void:
	print("\n[parse]")
	_ok(load("res://src/scenes/hud/ScadaDashboard.gd") != null,
		"loads res://src/scenes/hud/ScadaDashboard.gd")
	var dash := _make_dash()
	_ok(dash != null and dash is CanvasLayer, "instances as a CanvasLayer")
	_ok(dash.micro_stops is Array and dash.micro_stops.is_empty(),
		"micro_stops starts as an empty Array")
	dash.free()

# -----------------------------------------------------------------------------
# THE headline case: Running → Idle → Running, all inside 60 s.
# -----------------------------------------------------------------------------
func _micro_stop_under_window() -> void:
	print("\n[micro-stop < 60s]")
	var dash := _make_dash()

	_clock_s = 0.0
	dash.set_state("Running")
	_ok(dash.micro_stop_count() == 0, "Running: no micro-stop yet")
	_ok(not dash.is_shutdown_visible(), "dashboard live while Running")

	# Drop to Idle at t=10s (a momentary jam clear).
	_clock_s = 10.0
	dash.set_state("Idle")
	_ok(dash.micro_stop_count() == 0, "Running→Idle alone is not yet a micro-stop")
	_ok(not dash.is_shutdown_visible(),
		"Idle does NOT trigger a full visual shutdown")

	# Back to Running 25 s later (t=35s) — gap is 25 s < 60 s → micro-stop.
	_clock_s = 35.0
	var logged : bool = dash.set_state("Running")
	_ok(logged, "the Idle→Running edge reports it closed a micro-stop")
	_ok(dash.micro_stop_count() == 1,
		"exactly ONE Micro-Stop logged for a <60s blip (got %d)" % dash.micro_stop_count())
	_ok(not dash.is_shutdown_visible(),
		"dashboard stays LIVE after logging the micro-stop (no UI shutdown)")

	# Sanity on the logged record.
	if dash.micro_stop_count() == 1:
		var rec : Dictionary = dash.micro_stops[0]
		_ok(absf(float(rec["idle_duration_s"]) - 25.0) < 0.001,
			"logged idle_duration_s = %.1f (expected 25.0)" % float(rec["idle_duration_s"]))
		_ok(String(rec["from_state"]) == "Idle", "record remembers the from_state")
	dash.free()

# -----------------------------------------------------------------------------
# An Idle gap LONGER than the 60 s window is a real stop, not a micro-stop.
# -----------------------------------------------------------------------------
func _long_idle_no_micro_stop() -> void:
	print("\n[idle > 60s → no micro-stop]")
	var dash := _make_dash()

	_clock_s = 0.0
	dash.set_state("Running")
	_clock_s = 5.0
	dash.set_state("Idle")
	# Come back 90 s later — well past the window.
	_clock_s = 95.0
	var logged : bool = dash.set_state("Running")
	_ok(not logged, "a 90 s idle does NOT report a micro-stop")
	_ok(dash.micro_stop_count() == 0,
		"idle > 60 s logs ZERO micro-stops (got %d)" % dash.micro_stop_count())
	_ok(not dash.is_shutdown_visible(), "dashboard still live after a long idle")

	# Exactly at the boundary (60 s) must NOT count (strictly < window).
	_clock_s = 100.0
	dash.set_state("Idle")
	_clock_s = 160.0   # exactly 60.0 s later
	var logged_boundary : bool = dash.set_state("Running")
	_ok(not logged_boundary, "a gap of exactly 60.0 s is NOT a micro-stop (boundary)")
	_ok(dash.micro_stop_count() == 0, "boundary case logs nothing")
	dash.free()

# -----------------------------------------------------------------------------
# Two separate blips → two independent micro-stops, dashboard live throughout.
# -----------------------------------------------------------------------------
func _repeated_micro_stops() -> void:
	print("\n[repeated micro-stops]")
	var dash := _make_dash()
	_clock_s = 0.0
	dash.set_state("Running")
	# Blip 1: idle 2s.
	_clock_s = 1.0;  dash.set_state("Idle")
	_clock_s = 3.0;  dash.set_state("Running")
	# Blip 2: idle 4s.
	_clock_s = 20.0; dash.set_state("Idle")
	_clock_s = 24.0; dash.set_state("Running")
	_ok(dash.micro_stop_count() == 2,
		"two distinct <60s blips log two micro-stops (got %d)" % dash.micro_stop_count())
	_ok(not dash.is_shutdown_visible(), "dashboard live across repeated micro-stops")
	dash.free()

# -----------------------------------------------------------------------------
# ISA-101 colour rule: in-band = grey, out-of-band = alarm colour.
# -----------------------------------------------------------------------------
func _isa101_alarm_colours() -> void:
	print("\n[ISA-101 alarm colours]")
	var dash := _make_dash()
	# Doser amps nominal 30..50.
	dash.set_param("doser_amps", 40.0, 30.0, 50.0, "Doser A")
	_ok(not dash.is_param_alarming("doser_amps"), "in-band value is nominal (no alarm)")
	dash.set_param("doser_amps", 65.0, 30.0, 50.0, "Doser A")
	_ok(dash.is_param_alarming("doser_amps"), "above-band value alarms")
	dash.set_param("doser_amps", 10.0, 30.0, 50.0, "Doser A")
	_ok(dash.is_param_alarming("doser_amps"), "below-band value alarms")
	dash.set_param("doser_amps", 30.0, 30.0, 50.0, "Doser A")
	_ok(not dash.is_param_alarming("doser_amps"), "value exactly at the low limit is nominal")
	dash.free()

# -----------------------------------------------------------------------------
# A parameter going into alarm must NEVER hide the dashboard — only a real
# shutdown would, and micro-stops/param alarms are explicitly not that.
# -----------------------------------------------------------------------------
func _params_dont_trip_shutdown() -> void:
	print("\n[param alarm keeps dashboard live]")
	var dash := _make_dash()
	dash.set_state("Running")
	dash.set_param("temp_c", 999.0, 180.0, 220.0, "Melt °C")   # wildly out of band
	_ok(dash.is_param_alarming("temp_c"), "extreme param reads as alarming")
	_ok(not dash.is_shutdown_visible(),
		"a param alarm does NOT shut the dashboard down")
	dash.free()
