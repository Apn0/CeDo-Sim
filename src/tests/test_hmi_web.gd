extends SceneTree
## Headless test for HmiWebOverlay (task #2 — Claude-Design HMI in a WebView).
##
## The WebView itself cannot exist headless (the addon skips creation), so this
## covers everything Godot OWNS around it — which is deliberately all the
## logic: the ◀/▶ navigation order parsed from the real HMI Index, the
## unknown-screen refusal, and gather_vals()' LineFlow → shell payload
## (amps/powered per plant code, the 4-state line pill, estop fault marking).
##
## Run (ALWAYS with --quit-after to dodge the autoload-hang issue):
##   godot --headless --path . --script res://src/tests/test_hmi_web.gd --quit-after 30

const OverlayScript = preload("res://src/scenes/hud/HmiWebOverlay.gd")

## Stand-in for LineFlow — only the read API gather_vals() touches.
class StubLineFlow extends Node:
	var estopped := false
	var starting := false
	var powered_fraction := 0.8
	var estop_key := ""
	func machine_list() -> Array:
		return [
			{"id": "mill", "key": "L3C.6", "l3c_code": "L3C.6"},
			{"id": "mech_dryer", "key": "L3C.14L", "l3c_code": "L3C.14L"},
			{"id": "silo", "key": "L3C.18", "l3c_code": "L3C.18"},
			{"id": "conveyor", "key": "conveyor#3", "l3c_code": ""},  # no code → excluded
		]
	func get_machine_info(key: String) -> Dictionary:
		match key:
			"L3C.6":    return {"amps": 186.79, "powered": true}
			"L3C.14L":  return {"amps": 70.8,  "powered": true}
			"L3C.18":   return {"amps": 3.0,   "powered": false}
		return {}
	func is_estopped() -> bool: return estopped

	func is_line_starting() -> bool: return starting
	func line_powered_fraction() -> float: return powered_fraction
	func estop_fault_key() -> String: return estop_key

## Stand-in for the real ShiftClock — only what _clock_lines() reads.
## 30 min 7 s into an EARLY shift (07:00 start) → "07:30:07".
class StubShiftClock extends Node:
	var shift_elapsed_seconds : float = 1807.0
	func get_time_string() -> String: return "07:30"
	func calendar_string() -> String: return "Dag 1 · Vroege dienst · Ploeg A"

func _fail(msg: String) -> void:
	print("RESULT FAIL: %s" % msg)
	quit(1)

var _ran := false

## Runs on the FIRST main-loop tick, not in _initialize(): nodes added to the
## root during _initialize are not yet inside the tree (is_inside_tree() ==
## false — measured), so group lookups through get_tree() find nothing there.
func _process(_delta: float) -> bool:
	if _ran:
		return false
	_ran = true
	_run()
	return false

func _run() -> void:
	print("==== HMI WEB OVERLAY TEST ====")

	# Headless guard — the whole fallback chain in Hmi.gd rests on this.
	if OverlayScript.webview_available():
		_fail("webview_available() must be false in a headless run"); return
	print("  ok    : webview_available() == false headless")

	var overlay := OverlayScript.new()
	get_root().add_child(overlay)

	# ── 1. Navigation order from the real HMI Index ───────────────────────
	overlay._ensure_screen_order()
	var order : Array = overlay._screen_order
	if order.size() != 33:
		_fail("Index parse: expected 33 screens, got %d" % order.size()); return
	if not order.has("Waslijn 3C Overzicht.dc.html"):
		_fail("Index parse: 'Waslijn 3C Overzicht.dc.html' missing"); return
	print("  ok    : Index parsed — 33 screens, Overzicht present")

	overlay._current_screen = "Waslijn 3C Overzicht.dc.html"
	var i : int = order.find("Waslijn 3C Overzicht.dc.html")
	if overlay._nav_target("next") != order[(i + 1) % order.size()]:
		_fail("nav next mismatch"); return
	if overlay._nav_target("prev") != order[(i - 1 + order.size()) % order.size()]:
		_fail("nav prev mismatch"); return
	if overlay._nav_target("home") != "HMI Index.dc.html":
		_fail("nav home must be the Index"); return
	overlay._current_screen = ""   # on the Index → ▶ enters the first card
	if overlay._nav_target("next") != order[0]:
		_fail("nav next from Index must open the first card"); return
	print("  ok    : nav next/prev/home follow the Index card order")

	# ── 2. Unknown screens are refused ────────────────────────────────────
	if overlay._is_known_screen("../../../project.godot"):
		_fail("path traversal accepted as a screen"); return
	if overlay._is_known_screen("bestaat_niet.dc.html"):
		_fail("nonexistent screen accepted"); return
	if not overlay._is_known_screen("HMI Index.dc.html"):
		_fail("the Index itself must be a known screen"); return
	print("  ok    : unknown/traversal screens refused, Index allowed")

	# ── 3. gather_vals() against a stub LineFlow ──────────────────────────
	var lf := StubLineFlow.new()
	get_root().add_child(lf)
	lf.add_to_group("line_flow")   # must already be in-tree
	overlay._current_screen = "Waslijn 3C Overzicht.dc.html"

	var v := overlay.gather_vals()
	if v.is_empty():
		print("  dbg   : overlay in_tree=%s lf in_tree=%s lf in_group=%s first=%s" % [
			str(overlay.is_inside_tree()), str(lf.is_inside_tree()),
			str(lf.is_in_group("line_flow")),
			str(get_first_node_in_group("line_flow"))])
		_fail("gather_vals returned empty with a LineFlow present"); return
	var units : Dictionary = v.get("units", {})
	if units.size() != 3:
		_fail("expected 3 coded units, got %d (codeless machines must be excluded)" % units.size()); return
	if absf(float(units["L3C.6"]["amps"]) - 186.79) > 0.001:
		_fail("L3C.6 amps wrong: %s" % str(units["L3C.6"])); return
	if not bool(units["L3C.6"]["on"]) or bool(units["L3C.18"]["on"]):
		_fail("powered mapping wrong: %s / %s" % [str(units["L3C.6"]), str(units["L3C.18"])]); return
	var pills : Dictionary = v.get("pills", {})
	if String(pills["Status Lijn 3C"]["text"]) != "Auto":
		_fail("line pill should be Auto at powered_fraction 0.8, got %s" % str(pills["Status Lijn 3C"])); return
	if String(pills["Status was"]["text"]) != "Aan":
		_fail("'Status was' should be Aan (L3C.6/L3C.14L powered)"); return
	if String(pills["Status Silo"]["text"]) != "Uit":
		_fail("'Status Silo' should be Uit (L3C.18 unpowered)"); return
	print("  ok    : units keyed by plant code, amps/powered exact, pills derived")

	# ── 4. estop variant — pill goes Storing, the faulted unit is flagged ─
	lf.estopped = true
	lf.estop_key = "L3C.6"
	var v2 := overlay.gather_vals()
	if String(v2["pills"]["Status Lijn 3C"]["text"]) != "Storing":
		_fail("estop must render the Storing pill"); return
	if not bool(v2["units"]["L3C.6"]["fault"]):
		_fail("estopped machine L3C.6 must carry fault=true"); return
	if bool(v2["units"]["L3C.14L"]["fault"]):
		_fail("non-faulted machine must not carry fault=true"); return
	print("  ok    : estop → Storing pill + per-unit fault flag")

	# ── 4b. the header clock must come from the PLANT, not the PC ────────
	# Regression guard: _find_shift_clock() originally searched only
	# current_scene, so any harness that add_child()s MainWorld without
	# assigning current_scene got an empty clock — and the page silently fell
	# back to the player's real wall clock, which LOOKS correct in a
	# screenshot. Caught in-game 2026-08-10 (screen read 04:20 on a 07:00
	# shift). The stub is deliberately added under root, NOT current_scene.
	var stub_clock := StubShiftClock.new()
	stub_clock.name = "ShiftClock"
	get_root().add_child(stub_clock)
	await process_frame
	overlay._shift_clock = null   # force a fresh lookup
	var v3 := overlay.gather_vals()
	var clk : Dictionary = v3.get("clock", {})
	if clk.is_empty():
		_fail("gather_vals produced no clock with a ShiftClock in the tree"); return
	if String(clk.get("date", "")) != "Dag 1 · Vroege dienst · Ploeg A":
		_fail("clock date should be the rota line, got '%s'" % String(clk.get("date", ""))); return
	if String(clk.get("time", "")) != "07:30:07":
		_fail("clock time should be plant time HH:MM:SS, got '%s'" % String(clk.get("time", ""))); return
	print("  ok    : header clock comes from ShiftClock (rota line + plant time)")

	# ── 5. every panel's web_screen must be a real, Index-listed file ─────
	# A typo here would ship a panel that opens to a blank WebView with only a
	# push_warning in the log — invisible in normal play.
	var Scopes = load("res://src/build/HmiScopes.gd")
	var mapped := 0
	for hmi_id in Scopes.ORDERED_IDS:
		var scope : Dictionary = Scopes.get_scope(hmi_id)
		var ws := String(scope.get("web_screen", ""))
		if ws == "":
			continue
		mapped += 1
		if not overlay._is_known_screen(ws):
			_fail("%s -> web_screen '%s' is not an Index-listed screen" % [hmi_id, ws]); return
		if overlay._read_screen_file(ws) == "":
			_fail("%s -> web_screen '%s' does not exist on disk" % [hmi_id, ws]); return
	if mapped < 6:
		_fail("expected at least 6 panels mapped to designs, found %d" % mapped); return
	print("  ok    : all %d panel->design mappings resolve to real screen files" % mapped)

	# ── 6. screen payload encodes the real file ───────────────────────────
	var html := overlay._read_screen_file("Waslijn 3C Overzicht.dc.html")
	if html == "" or html.find("data-screen-label=\"Waslijn 3C Overzicht\"") < 0:
		_fail("screen file read broken"); return
	print("  ok    : screen file readable with its data-screen-label intact")


	# ── 7. open_for and close logic ───────────────────────────────────────
	overlay.open_for("Test Panel", {})
	if not overlay.visible:
		_fail("open_for should make the overlay visible"); return
	if overlay._pending_screen != overlay.INDEX_FILE:
		_fail("open_for without web_screen should default to INDEX_FILE, got '%s'" % overlay._pending_screen); return
	if overlay._web != null:
		_fail("headless test should not create a WebView instance"); return

	overlay.open_for("Test Panel 2", {"web_screen": "Waslijn 3C Overzicht.dc.html"})
	if overlay._pending_screen != "Waslijn 3C Overzicht.dc.html":
		_fail("open_for with web_screen should set _pending_screen, got '%s'" % overlay._pending_screen); return

	overlay.close()
	if overlay.visible:
		_fail("close should make the overlay invisible"); return
	print("  ok    : open_for and close set visibility and _pending_screen correctly")

	print("PASS — HmiWebOverlay logic verified headless")
	quit(0)
