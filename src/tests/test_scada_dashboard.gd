extends SceneTree
## Headless test for the ScadaDashboard public API — set_state / set_param /
## set_text_param (2026-08-31 review finding, ScadaDashboard.gd:97).
##
## Run: godot --headless --path . --script res://src/tests/test_scada_dashboard.gd --quit-after 300
##
## HISTORY 2026-08-31: this file used to be an 8-line launcher for
## test_scada_dashboard.tscn (logic in test_scada_dashboard_scene.gd). That
## scene suite still exists untouched and can run via its own .tscn, but it was
## never wired into the harness and does not print the house 'Result: PASS'
## verdict line. Every check it made is a subset of the checks below, now in
## the house SceneTree/_ok counted shape. Old launcher: test_scada_dashboard.gd.bak.
##
## CONTRACT NOTE (measured from the code, not the review text): set_state()
## performs NO name validation — ANY string is stored verbatim, and its bool
## return means "this call closed a micro-stop", not "name was valid". The
## checks below assert that real contract.
##
## Counted checks, never bare assert(): a failing assert aborts before quit()
## so the harness HANGS instead of failing, and assert compiles out of release
## builds (see test_walkie.gd for the full rationale).

var _pass := 0
var _fail := 0
var _skip := 0

# Injectable clock for ScadaDashboard.set_time_source — driven manually below
# so micro-stop window arithmetic is deterministic.
var _mock_time := 0.0

func _mock_time_s() -> float:
	return _mock_time

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== ScadaDashboard API Tests ===")

	var SD = load("res://src/scenes/hud/ScadaDashboard.gd")
	var dash = SD.new()
	dash.set_time_source(Callable(self, "_mock_time_s"))
	# _ready builds a pure Control/Label tree programmatically (no SubViewports,
	# no rendering dependencies) — headless-safe, so we use the REAL _ready.
	root.add_child(dash)

	# ── 1. Construction / initial state ────────────────────────────────────────
	print("Test: Initial state")
	_ok(dash._root_panel != null, "root panel is built by the real _ready")
	_ok(dash.get_state() == "Idle", "default state is Idle")
	# Guard the label deref: null claim first, dependents gated with 'and' so a
	# tripped guard counts them as FAIL, never a crash before the verdict.
	var lbl_ok: bool = dash._state_label != null
	_ok(lbl_ok, "state label is built")
	_ok(lbl_ok and dash._state_label.text == "IDLE", "state label shows IDLE uppercased")
	_ok(lbl_ok and dash._state_label.get_theme_color("font_color") == SD.COL_STATE_BAD, "Idle (non-running) paints amber at boot")
	_ok(dash.micro_stop_count() == 0, "no micro-stops at boot")
	_ok(dash.is_shutdown_visible() == false, "shutdown visual not showing at boot")

	# ── 2. set_state: every documented name + garbage ─────────────────────────
	print("Test: set_state stores every documented state name")
	_mock_time = 0.0
	# 1000 s jumps so no transition in this loop can close the 60 s micro-stop
	# window — every return here must be false.
	for state_name in ["Running", "Idle", "Fault", "Starting"]:
		_mock_time += 1000.0
		var closed = dash.set_state(state_name)
		_ok(closed == false, "set_state('%s') closes no micro-stop here" % state_name)
		_ok(dash.get_state() == state_name, "state stored verbatim: '%s'" % state_name)
		_ok(lbl_ok and dash._state_label.text == state_name.to_upper(), "label shows '%s'" % state_name.to_upper())
		var want_col = SD.COL_GREY_TEXT if state_name == "Running" else SD.COL_STATE_BAD
		_ok(lbl_ok and dash._state_label.get_theme_color("font_color") == want_col, "'%s' colour: grey iff Running, amber otherwise" % state_name)

	print("Test: set_state with a garbage name")
	_mock_time += 1000.0
	var g = dash.set_state("Bogus")
	_ok(g == false, "garbage name closes no micro-stop (return is micro-stop flag, not validity)")
	_ok(dash.get_state() == "Bogus", "garbage name IS stored — set_state validates nothing (measured contract)")
	_ok(lbl_ok and dash._state_label.get_theme_color("font_color") == SD.COL_STATE_BAD, "unknown state treated as deviation -> amber")

	print("Test: set_state Running match is case/space-insensitive")
	_mock_time += 1000.0
	dash.set_state("  running  ")
	_ok(lbl_ok and dash._state_label.get_theme_color("font_color") == SD.COL_GREY_TEXT, "'  running  ' counts as Running -> calm grey")

	# ── 3. set_state: micro-stop logging (the true-return path) ───────────────
	print("Test: micro-stop logging")
	# currently Running at t=6000
	_mock_time = 6010.0
	_ok(dash.set_state("Idle") == false, "Running->Idle only starts the stopwatch")
	_mock_time = 6040.0
	_ok(dash.set_state("Running") == true, "Running->Idle->Running in 30 s returns true (micro-stop closed)")
	_ok(dash.micro_stop_count() == 1, "exactly one micro-stop logged")
	var have_ms: bool = dash.micro_stops.size() == 1
	_ok(have_ms, "micro_stops array holds one entry")
	_ok(have_ms and absf(float(dash.micro_stops[0]["idle_duration_s"]) - 30.0) < 0.001, "logged idle duration is 30 s")
	_ok(have_ms and String(dash.micro_stops[0]["from_state"]) == "Idle", "entry records from_state Idle")
	_ok(dash.is_shutdown_visible() == false, "micro-stop does NOT fire the full shutdown visual")
	var ms_lbl_ok: bool = dash._microstop_lbl != null
	_ok(ms_lbl_ok and dash._microstop_lbl.text == "Micro-Stops:  1", "footer counter shows 1")
	_ok(ms_lbl_ok and dash._microstop_lbl.get_theme_color("font_color") == SD.COL_ACCENT, "counter flashes cyan, never alarm red")

	_mock_time = 7000.0
	dash.set_state("Idle")
	_mock_time = 7060.0
	_ok(dash.set_state("Running") == false, "idle of exactly 60 s is NOT a micro-stop (strict <)")
	_ok(dash.micro_stop_count() == 1, "count unchanged after the 60 s stop")

	_mock_time = 8000.0
	dash.set_state("Idle")
	_mock_time = 8100.0
	_ok(dash.set_state("Running") == false, "100 s stop is a real stop, not a micro-stop")
	_ok(dash.micro_stop_count() == 1, "count unchanged after the 100 s stop")

	_mock_time = 9000.0
	dash.set_state("Fault")
	_mock_time = 9005.0
	_ok(dash.set_state("Running") == true, "Running->Fault->Running in 5 s is a micro-stop too")
	var have_ms2: bool = dash.micro_stops.size() == 2
	_ok(have_ms2, "second entry logged")
	_ok(have_ms2 and String(dash.micro_stops[1]["from_state"]) == "Fault", "entry records from_state Fault")

	# ── 4. set_param: nominal band vs alarms, update-not-duplicate ────────────
	print("Test: set_param nominal vs alarm bands")
	dash.set_param("pressure", 5.0, 0.0, 10.0, "Pressure")
	_ok(dash._params.has("pressure"), "param stored under its key")
	_ok(dash.is_param_alarming("pressure") == false, "5.0 inside [0,10] does not alarm")
	var have_prow: bool = dash._param_rows.has("pressure")
	_ok(have_prow, "a row was built for the param")
	var prow: Dictionary = dash._param_rows.get("pressure", {})
	_ok(have_prow and prow["name_lbl"].text == "Pressure", "row label shows the given label")
	_ok(have_prow and prow["value_lbl"].text == "5", "integer value formats clean ('5')")
	_ok(have_prow and prow["value_lbl"].get_theme_color("font_color") == SD.COL_GREY_TEXT, "nominal value stays ISA-101 grey")

	var rows_before: int = dash._params_box.get_child_count()
	dash.set_param("pressure", 12.0, 0.0, 10.0)
	_ok(dash._params_box.get_child_count() == rows_before, "repeat key UPDATES the row — no duplicate row widget")
	_ok(dash._param_rows.size() == 1, "still exactly one row record")
	_ok(absf(float(dash._params["pressure"]["value"]) - 12.0) < 0.001, "stored value updated in place")
	_ok(dash.is_param_alarming("pressure") == true, "12.0 above the band alarms")
	_ok(have_prow and prow["value_lbl"].text == "12", "value label updated in place")
	_ok(have_prow and prow["value_lbl"].get_theme_color("font_color") == SD.COL_ALARM_HI, "above band paints red (COL_ALARM_HI)")
	_ok(have_prow and prow["name_lbl"].text == "Pressure", "label persists when omitted on update")

	dash.set_param("temp", -5.0, 0.0, 100.0)
	_ok(dash.is_param_alarming("temp") == true, "-5.0 below the band alarms")
	var have_trow: bool = dash._param_rows.has("temp")
	_ok(have_trow, "second key gets its own row")
	var trow: Dictionary = dash._param_rows.get("temp", {})
	_ok(have_trow and trow["value_lbl"].get_theme_color("font_color") == SD.COL_ALARM_LO, "below band paints amber (COL_ALARM_LO), distinct from red")
	_ok(have_trow and trow["name_lbl"].text == "temp", "missing label falls back to the key")

	dash.set_param("pressure", 5.0, 0.0, 10.0)
	_ok(dash.is_param_alarming("pressure") == false, "back inside the band the alarm clears")
	_ok(have_prow and prow["value_lbl"].get_theme_color("font_color") == SD.COL_GREY_TEXT, "colour returns to grey when nominal again")

	dash.set_param("mfi", 7.34, 0.0, 20.0)
	var have_mrow: bool = dash._param_rows.has("mfi")
	var mrow: Dictionary = dash._param_rows.get("mfi", {})
	_ok(have_mrow and mrow["value_lbl"].text == "7.3", "fractional value formats to one decimal")

	# ── 5. set_text_param: is_alarming true/false, update-not-duplicate ───────
	print("Test: set_text_param")
	dash.set_text_param("status", "OK", false, "System Status")
	_ok(dash.is_param_alarming("status") == false, "non-alarming text param reports no alarm (sentinel 0.0)")
	var have_srow: bool = dash._param_rows.has("status")
	_ok(have_srow, "text param gets a row too")
	var srow: Dictionary = dash._param_rows.get("status", {})
	_ok(have_srow and srow["value_lbl"].text == "OK", "text value displayed")
	_ok(have_srow and srow["value_lbl"].get_theme_color("font_color") == SD.COL_GREY_TEXT, "non-alarming text stays grey")
	_ok(have_srow and srow["name_lbl"].text == "System Status", "text param label shown")

	var rows_before2: int = dash._params_box.get_child_count()
	dash.set_text_param("status", "vacuum_lid_pushed_open", true)
	_ok(dash._params_box.get_child_count() == rows_before2, "repeat text key updates — no duplicate row")
	_ok(dash.is_param_alarming("status") == true, "alarming text param alarms via sentinel value 1.0")
	_ok(have_srow and srow["value_lbl"].text == "vacuum_lid_pushed_open", "text updated in place")
	_ok(have_srow and srow["value_lbl"].get_theme_color("font_color") == SD.COL_ALARM_HI, "alarming text paints red")

	dash.set_text_param("status", "", false)
	_ok(have_srow and srow["value_lbl"].text == "—", "empty text renders the em-dash placeholder")
	_ok(dash.is_param_alarming("status") == false, "alarm clears when re-pushed non-alarming")

	# ── 6. Misc guards ────────────────────────────────────────────────────────
	_ok(dash.is_param_alarming("no_such_key") == false, "unknown key never alarms")

	# Cleanup — CanvasLayer.free() frees the whole built label tree with it.
	root.remove_child(dash)
	dash.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
