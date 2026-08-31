extends SceneTree
## Headless counted-check suite for HmiWebOverlay.gather_vals()
## (2026-08-31 review finding: gather_vals untested — HmiWebOverlay.gd:275).
##
## gather_vals() is pure GDScript aggregation (LineFlow group node +
## /root/NpcAutonomyBoard + a ShiftClock found through the tree); the
## WebView/JS side is NOT involved — _post/_push_vals own that boundary and
## are not under test here. Everything gather_vals reads is mocked with the
## exact node names / groups / methods the code looks up.
##
## Run: godot --headless --path . --script res://src/tests/test_hmi_web_gather_vals.gd --quit-after 300
##
## Counted checks, not assert(): a failing assert() aborts before quit() so
## the harness HANGS instead of failing, and assert compiles out of release.

const OverlayScript = preload("res://src/scenes/hud/HmiWebOverlay.gd")

var _pass := 0
var _fail := 0
var _skip := 0
var _ran := false

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

## Crash-proof lookups: a missing key degrades the claim to FAIL (via a
## null/"" mismatch), never to a script error that would abort before the
## verdict prints.
func _dict(v: Variant) -> Dictionary:
	return v if typeof(v) == TYPE_DICTIONARY else {}

func _uget(units: Dictionary, code: String, field: String) -> Variant:
	return _dict(units.get(code, {})).get(field, null)

func _pill(pills: Dictionary, key: String, field: String) -> String:
	return String(_dict(pills.get(key, {})).get(field, ""))

## Nodes added to the root during _initialize are not yet inside the tree
## (measured — see test_hmi_web.gd), so group lookups through get_tree()
## would find nothing there. Run on the first main-loop tick instead.
func _process(_delta: float) -> bool:
	if not _ran:
		_ran = true
		_run_tests()
	return false

func _run_tests() -> void:
	print("=== HmiWebOverlay.gather_vals Tests ===")

	# The real NpcAutonomyBoard autoload owns /root/NpcAutonomyBoard. Rename
	# it away so the alarm claims measure the absent-board path first, then a
	# mock under the real name (walkie pattern; restored before the verdict).
	# gather_vals caches no board: _top_alarm does a fresh get_node_or_null
	# per call, so a rename before the first call is enough.
	if root.has_node("NpcAutonomyBoard"):
		root.get_node("NpcAutonomyBoard").name = "NpcAutonomyBoard_Real"

	var overlay := OverlayScript.new()
	root.add_child(overlay)
	overlay._current_screen = "Waslijn 3C Overzicht.dc.html"

	# ── 1. No LineFlow anywhere → the whole payload degrades to {} ────────
	print("Test: no LineFlow")
	var v0 : Dictionary = overlay.gather_vals()
	_ok(v0.is_empty(), "no line_flow node in the tree -> empty dict")

	# ── 2. Populated subtree ──────────────────────────────────────────────
	print("Test: populated subtree")
	var lf := MockLineFlow.new()
	lf.rows = [
		{"key": "mill",   "l3c_code": "L3C.6"},
		{"key": "doseer", "l3c_code": "L3C.1"},
		{"key": "silo",   "l3c_code": "L3C.18"},
		{"key": "belt",   "l3c_code": ""},        # codeless -> must not appear
		{"key": "ghost",  "l3c_code": "L3C.99"},  # no machine_info -> defaults
	]
	lf.infos = {
		"mill":   {"amps": 186.79, "powered": true},
		"doseer": {"amps": 3,      "powered": true},   # INT amps -> float out
		"silo":   {"amps": 7.25,   "powered": false},
	}
	lf.fraction = 0.5
	root.add_child(lf)
	lf.add_to_group("line_flow")

	var v : Dictionary = overlay.gather_vals()
	_ok(not v.is_empty(), "payload not empty with a LineFlow present")
	_ok(String(v.get("type", "")) == "vals", "type == 'vals'")
	_ok(String(v.get("screen", "")) == "Waslijn 3C Overzicht.dc.html",
		"screen echoes _current_screen")

	var units : Dictionary = _dict(v.get("units"))
	_ok(units.size() == 4, "4 coded units (codeless row excluded), got %d" % units.size())
	_ok(units.has("L3C.6") and units.has("L3C.1") and units.has("L3C.18") and units.has("L3C.99"),
		"units keyed by l3c_code")
	_ok(not units.has(""), "codeless machine did not sneak in under ''")
	var amps6 : Variant = _uget(units, "L3C.6", "amps")
	_ok(typeof(amps6) == TYPE_FLOAT and absf(float(amps6) - 186.79) < 0.0001,
		"L3C.6 amps round-trips as float 186.79")
	var amps1 : Variant = _uget(units, "L3C.1", "amps")
	_ok(typeof(amps1) == TYPE_FLOAT and float(amps1) == 3.0,
		"int amps in machine_info coerced to float 3.0")
	var on6 : Variant = _uget(units, "L3C.6", "on")
	_ok(typeof(on6) == TYPE_BOOL and bool(on6) == true, "L3C.6 on == true (stays bool)")
	var on18 : Variant = _uget(units, "L3C.18", "on")
	_ok(typeof(on18) == TYPE_BOOL and bool(on18) == false, "L3C.18 on == false (stays bool)")
	_ok(_uget(units, "L3C.99", "amps") == 0.0 and _uget(units, "L3C.99", "on") == false,
		"missing machine_info degrades to amps 0.0 / on false")
	_ok(_uget(units, "L3C.6", "fault") == false and _uget(units, "L3C.18", "fault") == false,
		"empty estop_fault_key -> no unit carries fault")

	var pills : Dictionary = _dict(v.get("pills"))
	_ok(_pill(pills, "Status Lijn 3C", "text") == "Auto", "line pill Auto at fraction 0.5")
	_ok(_pill(pills, "Status Lijn 3C", "bg") == "#35c23a", "Auto pill is green")
	_ok(_pill(pills, "Status was", "text") == "Aan", "'Status was' Aan (L3C.6 powered)")
	_ok(_pill(pills, "Status Silo", "text") == "Uit", "'Status Silo' Uit (L3C.18 unpowered)")
	_ok(_pill(pills, "Status Silo", "bg") == "#6a7a8a", "Uit silo pill is grey")

	# ── 3. Alarm/clock degrade with board renamed away, no ShiftClock ─────
	print("Test: alarm/clock degrade")
	_ok(v.has("alarm") and typeof(v["alarm"]) == TYPE_NIL,
		"no /root/NpcAutonomyBoard -> alarm null")
	_ok(v.has("clock") and typeof(v["clock"]) == TYPE_DICTIONARY and _dict(v["clock"]).is_empty(),
		"no ShiftClock anywhere -> clock {}")

	# ── 4. Alarm from the board registry ──────────────────────────────────
	print("Test: alarm from NpcAutonomyBoard")
	var board := MockBoard.new()
	board.name = "NpcAutonomyBoard"
	root.add_child(board)
	var va : Dictionary = overlay.gather_vals()
	_ok(va.has("alarm") and typeof(va["alarm"]) == TYPE_NIL,
		"board with empty storing_list -> alarm null")
	board.storing = [
		{"severity": 1, "alarm_id": "A-101", "machine_id": "L3C.6"},
		{"severity": 3, "alarm_id": "A-207", "machine_id": "L3C.14L"},
		{"severity": 2, "alarm_id": "A-055", "machine_id": "L3C.18"},
	]
	var vb : Dictionary = overlay.gather_vals()
	var alarm : Dictionary = _dict(vb.get("alarm"))
	_ok(not alarm.is_empty(), "active storing list -> alarm dict")
	_ok(String(alarm.get("nr", "")) == "A-207", "alarm picks the highest severity entry")
	_ok(String(alarm.get("text", "")) == "L3C.14L — A-207", "alarm text is 'machine — id'")

	# ── 5. Estop pill + per-unit fault + wash exclusion ───────────────────
	print("Test: estop + wash exclusion")
	lf.infos = {
		"mill":   {"amps": 0.0,  "powered": false},
		"doseer": {"amps": 3.0,  "powered": true},   # L3C.1 excluded from 'Status was'
		"silo":   {"amps": 7.25, "powered": true},   # L3C.18 excluded from 'Status was'
	}
	lf.estopped = true
	lf.estop_key = "silo"
	var vc : Dictionary = overlay.gather_vals()
	var cpills : Dictionary = _dict(vc.get("pills"))
	_ok(_pill(cpills, "Status Lijn 3C", "text") == "Storing", "estop -> Storing pill")
	_ok(_pill(cpills, "Status Lijn 3C", "bg") == "#e02020", "Storing pill is red")
	_ok(_pill(cpills, "Status was", "text") == "Uit",
		"'Status was' Uit despite powered L3C.1+L3C.18 (both excluded from wash)")
	_ok(_pill(cpills, "Status Silo", "text") == "Aan", "'Status Silo' Aan when L3C.18 powered")
	var cunits : Dictionary = _dict(vc.get("units"))
	_ok(_uget(cunits, "L3C.18", "fault") == true, "estopped unit (key match) carries fault=true")
	_ok(_uget(cunits, "L3C.1", "fault") == false, "other units carry fault=false")

	# ── 6. Start pill, Uit pill and the 0.05 fraction boundary ────────────
	print("Test: Start / Uit pills")
	lf.estopped = false
	lf.estop_key = ""
	lf.starting = true
	var vd : Dictionary = overlay.gather_vals()
	_ok(_pill(_dict(vd.get("pills")), "Status Lijn 3C", "text") == "Start", "starting -> Start pill")
	_ok(_pill(_dict(vd.get("pills")), "Status Lijn 3C", "bg") == "#e8c040", "Start pill is amber")
	lf.starting = false
	lf.fraction = 0.05    # Auto needs STRICTLY > 0.05
	var ve : Dictionary = overlay.gather_vals()
	_ok(_pill(_dict(ve.get("pills")), "Status Lijn 3C", "text") == "Uit",
		"fraction exactly 0.05 (boundary) -> Uit pill")
	_ok(_pill(_dict(ve.get("pills")), "Status Lijn 3C", "bg") == "#6a7a8a", "Uit pill is grey")
	lf.fraction = 0.06
	var vf : Dictionary = overlay.gather_vals()
	_ok(_pill(_dict(vf.get("pills")), "Status Lijn 3C", "text") == "Auto", "fraction 0.06 -> Auto pill")

	# ── 7. Clock lines from a ShiftClock found via the tree fallback ──────
	print("Test: clock lines")
	var sc := MockShiftClock.new()
	sc.name = "ShiftClock"
	root.add_child(sc)   # under root, NOT current_scene -> tree-fallback path
	var vg : Dictionary = overlay.gather_vals()
	var clk : Dictionary = _dict(vg.get("clock"))
	_ok(not clk.is_empty(), "ShiftClock under root (no current_scene) -> clock populated")
	_ok(String(clk.get("date", "")) == "Dag 2 · Late dienst · Ploeg B",
		"date line is ShiftClock.calendar_string()")
	_ok(String(clk.get("time", "")) == "22:15:05",
		"time = get_time_string + elapsed mod 60 (125.7 -> :05)")
	sc.shift_elapsed_seconds = -3.2
	var vh : Dictionary = overlay.gather_vals()
	_ok(String(_dict(vh.get("clock")).get("time", "")) == "22:15:03",
		"negative elapsed seconds absf'd (-3.2 -> :03)")

	# ── 8. LineFlow lacking estop_fault_key: has_method guard ─────────────
	print("Test: LineFlow without estop_fault_key")
	root.remove_child(lf)
	lf.free()   # cached _line_flow invalidated -> fresh group lookup
	var lf2 := MockLineFlowNoEstop.new()
	root.add_child(lf2)
	lf2.add_to_group("line_flow")
	var vi : Dictionary = overlay.gather_vals()
	_ok(not vi.is_empty(), "re-finds a LineFlow after the cached one was freed")
	_ok(_uget(_dict(vi.get("units")), "L3C.6", "fault") == false,
		"no estop_fault_key method -> fault stays false (has_method guard)")
	_ok(_pill(_dict(vi.get("pills")), "Status Lijn 3C", "text") == "Auto",
		"pills still derived without the estop method")

	# Cleanup — free the mock board BEFORE restoring the real autoload name.
	root.remove_child(overlay)
	overlay.free()
	root.remove_child(lf2)
	lf2.free()
	root.remove_child(board)
	board.free()
	root.remove_child(sc)
	sc.free()
	if root.has_node("NpcAutonomyBoard_Real"):
		root.get_node("NpcAutonomyBoard_Real").name = "NpcAutonomyBoard"

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)

# ── Mocks: exactly the read API gather_vals() touches ─────────────────────

class MockLineFlow extends Node:
	var estopped := false
	var starting := false
	var fraction := 0.5
	var estop_key := ""
	var rows : Array = []
	var infos : Dictionary = {}
	func machine_list() -> Array: return rows
	func get_machine_info(key: String) -> Dictionary: return infos.get(key, {})
	func is_estopped() -> bool: return estopped
	func is_line_starting() -> bool: return starting
	func line_powered_fraction() -> float: return fraction
	func estop_fault_key() -> String: return estop_key

class MockLineFlowNoEstop extends Node:
	## Deliberately LACKS estop_fault_key() — exercises the has_method guard.
	func machine_list() -> Array:
		return [{"key": "mill", "l3c_code": "L3C.6"}]
	func get_machine_info(_key: String) -> Dictionary:
		return {"amps": 10.0, "powered": true}
	func is_estopped() -> bool: return false
	func is_line_starting() -> bool: return false
	func line_powered_fraction() -> float: return 0.9

class MockShiftClock extends Node:
	var shift_elapsed_seconds : float = 125.7
	func get_time_string() -> String: return "22:15"
	func calendar_string() -> String: return "Dag 2 · Late dienst · Ploeg B"

class MockBoard extends Node:
	var storing : Array = []
	func storing_list() -> Array: return storing
