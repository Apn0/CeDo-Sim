extends SceneTree
## Headless test for the REAL HmiOverlay open_for / is_open / close_overlay
## (2026-08-31 review finding: these were only covered by test_hmi_overlay.gd's
## TestableHmiOverlay, which REIMPLEMENTS open_for/close_overlay in the test —
## a bench that proves the mock, not the class). This suite instantiates the
## actual res://src/scenes/hud/HmiOverlay.gd, lets the real _ready() build the
## chrome (verified headless-safe by reading: Controls only, no SubViewports;
## _find_line_flow/_compute_faults/_refresh all tolerate a missing world), and
## exercises the real inherited methods.
##
## Run: godot --headless --path . --script res://src/tests/test_hmi_overlay_open_close.gd --quit-after 300
##
## Counted checks, not assert() — a failing assert aborts before quit() so the
## harness HANGS instead of failing, and assert compiles out of release builds.

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run_tests")

## Minimal LineFlow stand-in. Registered in the "line_flow" group — the FIRST
## anchor _find_line_flow() tries — so open_for's group lookup resolves it and
## the fed_mass baseline read is observable. Only carries what open_for reads.
class StubLineFlow extends Node:
	var fed_mass : float = 321.5

func _run_tests() -> void:
	print("=== HmiOverlay open_for / is_open / close_overlay Tests ===")

	var stub := StubLineFlow.new()
	stub.name = "StubLineFlow"
	stub.add_to_group("line_flow")
	root.add_child(stub)

	# The REAL class, real _ready (runs synchronously on add_child).
	var overlay = load("res://src/scenes/hud/HmiOverlay.gd").new()
	overlay.name = "HmiOverlayUnderTest"
	root.add_child(overlay)

	# 1. Fresh overlay is closed
	print("Test: Fresh overlay")
	_ok(overlay.is_open() == false, "Fresh overlay reports is_open() == false")
	_ok(overlay.visible == false, "Fresh overlay is invisible (_ready hides it)")

	# 2. open_for with a washing scope
	print("Test: open_for (scoped)")
	var wash_scope := {
		"label":  "Washing line",
		"lines":  ["1", "3a", "3b", "3c", "6"],
		"tokens": ["prewash", "wash", "flotation", "kufferath"],
	}
	overlay.open_for("Wasserij 3c", wash_scope)
	_ok(overlay.is_open() == true, "open_for makes is_open() true")
	_ok(overlay._station == "WASSERIJ 3C", "Station label stored upper-cased")
	# _show_screen ends in _refresh(), so the header must already show the
	# station + screen name — observable UI state, not just the private var.
	var title_ok: bool = overlay._header_title != null
	_ok(title_ok, "Header title label exists after open")
	_ok(title_ok and String(overlay._header_title.text).begins_with("WASSERIJ 3C"),
		"Header title shows the station label")
	_ok(title_ok and String(overlay._header_title.text).contains("HOOFDMENU"),
		"Header title shows the HOOFDMENU screen name")
	_ok(overlay._scope.get("tokens", []) == wash_scope["tokens"],
		"Scope tokens stored")
	# Deep copy claim: mutating the caller's dict must not leak into the panel.
	wash_scope["tokens"].append("mutant_token")
	var stored_tokens: Array = overlay._scope.get("tokens", [])
	_ok(not stored_tokens.has("mutant_token"),
		"Stored scope is a deep copy (caller mutation does not leak in)")
	# Scope must drive observable behaviour: wash tokens pick the wash tile grid.
	_ok(overlay._home_tiles_for_scope() == overlay.HOME_TILES_WASHING,
		"Wash-token scope selects the HOME_TILES_WASHING grid")
	# LineFlow binding through the real group-first lookup.
	_ok(overlay._line_flow == stub, "open_for resolves LineFlow via the line_flow group")
	_ok(abs(float(overlay._last_fed_mass) - 321.5) < 0.001,
		"open_for snapshots fed_mass as the feed baseline")

	# 3. Re-open on a different HMI re-applies the scope (comment at
	#    HmiOverlay.gd:360 promises wholesale replace + selection clear).
	print("Test: re-open re-applies scope")
	overlay._selected_machine_key = "shredder_1#0"   # simulate a stale selection
	var sort_scope := {"tokens": ["titech", "sga"]}  # deliberately NO "lines" key
	overlay.open_for("Sortering 3a", sort_scope)
	_ok(overlay.is_open() == true, "Re-open keeps the overlay open")
	_ok(overlay._station == "SORTERING 3A", "Re-open replaces the station label")
	_ok(overlay._scope.get("tokens", []) == ["titech", "sga"],
		"Re-open stores the NEW scope tokens")
	_ok(overlay._scope.get("lines", []).is_empty(),
		"Re-open replaces the scope wholesale (old 'lines' key gone, not merged)")
	_ok(overlay._home_tiles_for_scope() == overlay.HOME_TILES_SORTING,
		"Sorting-token scope now selects the HOME_TILES_SORTING grid")
	_ok(String(overlay._selected_machine_key) == "",
		"Re-open clears the stale MACHINES selection")

	# 4. Re-open generic (empty scope) fully drops the filter
	print("Test: re-open generic drops filter")
	overlay.open_for("Lijn 1")
	_ok(overlay._scope.is_empty(), "Empty scope stored as empty (filter dropped)")
	_ok(overlay._home_tiles_for_scope() == overlay.HOME_TILES_EXTRUDER,
		"Generic scope falls back to the extruder BluPort grid")

	# 5. close_overlay
	print("Test: close_overlay")
	overlay.close_overlay()
	_ok(overlay.is_open() == false, "close_overlay makes is_open() false")
	_ok(overlay.visible == false, "close_overlay hides the CanvasLayer")
	var content_ok: bool = overlay._content != null
	_ok(content_ok, "Content slot exists after close")
	_ok(content_ok and overlay._content.visible == true,
		"close_overlay's subscope teardown leaves main content visible")
	_ok(overlay._subscope_node == null and String(overlay._subscope_id) == "",
		"No subscope remains mounted after close")

	# 6. Closing an already-closed overlay is harmless
	print("Test: double close")
	overlay.close_overlay()
	_ok(overlay.is_open() == false, "Second close_overlay is a harmless no-op")

	# 7. Overlay can be re-opened after a close
	print("Test: reopen after close")
	overlay.open_for("Lijn 3c")
	_ok(overlay.is_open() == true, "open_for after close reopens the overlay")
	overlay.close_overlay()
	_ok(overlay.is_open() == false, "Final close leaves the overlay closed")

	# Cleanup
	root.remove_child(overlay)
	overlay.free()
	root.remove_child(stub)
	stub.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
