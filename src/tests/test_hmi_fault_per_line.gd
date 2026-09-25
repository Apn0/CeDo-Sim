extends Node
## HMI FAULT PER LINE (2026-09-24) — the same EREMA code on two extruders is
## two alarms: each one lights the bell, gets its own row and its own
## KWITTEREN, and every row says which line it is.
##
##   godot --headless --path . res://src/tests/test_hmi_fault_per_line.tscn
##
## The defect (measured with probe_hmi_fault_code_collision, identical on main
## 500af33 and on b8bda8a before #275): the overlay keyed first-seen,
## occurrence, history and shield by CODE. 3A's 6557 trips → KWITTEREN → 3C's
## 6557 trips while 3A's is still active: the bell stayed amber, Actief stayed
## empty, Historie got no row, and 3C's clear was later logged as "Hersteld
## (gekwiteerd)" although nobody acknowledged it. A second cause under it: a
## real ExtruderMachine keeps its line on `config_resource.line_id`, and
## _compute_faults read `em.line_id`, so every real extruder's alarm carried
## the scope "extruder" and no line at all.
##
## Operator ruling 2026-09-24 (AskUserQuestion): one alarm per line, the row
## shows the line; a shield (Afschermen) covers its own line only. The shield
## half is NOT tested here: nothing in the sim writes the shield table yet.
##
## Fixture, and what is real in it:
##   * the real HmiOverlay.tscn with the real hmi_extruder_all scope, operated
##     through its own buttons (BELL, sub-tabs, KWITTEREN); the checks read the
##     rows and the bell colour, as in test_hmi_fault_rearm;
##   * two REAL catalog extruders (extruder_3a, extruder_3c — MachineBrains
##     attaches the brain and its per-line ExtruderConfig), 100 m apart, each
##     with a real catalog laser_filter beside it; the real EremaFaultRegistry.
##   * NOT real: the pressure, written through LaserFilter's own
##     set_mp_after_filter_bar(). Each brain's SimTick handler is
##     disconnected, because OFF it writes 0.0 over that every tick
##     (ExtruderMachine `_update_downstream_signals`); nothing else is touched.
##   * phase B blanks both configs' line_id to reach the no-line fallback.

const WATCHDOG_S := 120.0
const CODE := "EREMA-6557"
const TRIP_BAR := 343.0
const CLEAR_BAR := 291.0
const SEE_TIMEOUT_S := 3.0

const _OV_SCENE := "res://src/scenes/hud/HmiOverlay.tscn"
const _OV_SCRIPT := "res://src/scenes/hud/HmiOverlay.gd"
const _SCOPES := "res://src/build/HmiScopes.gd"

var _fails := 0
var _oks := 0
var _ov : Node = null
var _ovs : Script = null
var _filters : Array = []   # [3A's, 3C's]
var _brains : Array = []    # [3A's, 3C's]

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (%d ok, %d fail — watchdog: verdict never completed; see SCRIPT ERROR above)" % [_oks, _fails + 1])
	get_tree().quit(2)

# ── operator-side helpers (as in test_hmi_fault_rearm) ──────────────────────

## (2026-09-25: this was set_upstream_pressure_indicator(psi), inverted
## through the registry's old psi * 0.0689. #278 split the melt pressure in two
## and removed that setter. With no melt flowing the filter's no-flow gate holds
## its dMP at 0, so the pressure BEFORE the filter, mp_before_filter_bar(),
## which EREMA 6557 reads, is exactly the bar written here.)
func _set_bar(i: int, bar: float) -> void:
	(_filters[i] as Node).call("set_mp_after_filter_bar", bar)

func _live_buttons(root: Node) -> Array:
	var out : Array = []
	for n in root.find_children("*", "Button", true, false):
		if not n.is_queued_for_deletion():
			out.append(n)
	return out

func _press(text: String) -> bool:
	for b in _live_buttons(_ov):
		if String((b as Button).text) == text:
			(b as Button).pressed.emit()
			return true
	print("  (no live button '%s')" % text)
	return false

## "none" (nav blue, no faults), "acked" (amber, all acked), "unacked" (red).
func _bell_state() -> String:
	var sb := (_ov.get("_alarm_bell_btn") as Button).get_theme_stylebox("normal") as StyleBoxFlat
	if sb == null:
		return "?"
	if sb.bg_color.is_equal_approx(_ovs.get_script_constant_map()["C_NAV"]):
		return "none"
	if sb.bg_color.is_equal_approx(_ovs.get_script_constant_map()["LAMP_IDLE"]):
		return "acked"
	return "unacked"

## Wait on wall time until the bell (repainted by the overlay's own 0.25 s
## refresh) reads `want`. True when it did within SEE_TIMEOUT_S.
func _await_bell(want: String) -> bool:
	var t0 := Time.get_ticks_msec()
	while _bell_state() != want:
		if Time.get_ticks_msec() - t0 > int(SEE_TIMEOUT_S * 1000.0):
			return false
		await get_tree().process_frame
	return true

## Rows of one STORINGEN sub-tab, newest first: {code (as shown, line
## included), text}. Pressing the tab rebuilds and refreshes the screen.
func _tab_rows(tab_text: String) -> Array:
	_press(tab_text)
	var out : Array = []
	var box = _ov.get("_fault_box")
	if box == null:
		return out
	for row in (box as Node).get_children():
		if row.is_queued_for_deletion() or not (row is PanelContainer):
			continue
		var hb := row.get_child(0) as HBoxContainer
		if hb == null or hb.get_child_count() < 3:
			continue
		out.append({
			"code": String((hb.get_child(0) as Label).text),
			"text": String((hb.get_child(2) as Label).text),
		})
	return out

func _codes(rows: Array) -> Array:
	var out : Array = []
	for r in rows:
		out.append(String(r["code"]))
	return out

func _count(rows: Array, shown_code: String, text_has: String = "", acked = null) -> int:
	var n := 0
	for r in rows:
		if String(r["code"]) != shown_code:
			continue
		if text_has != "" and not String(r["text"]).contains(text_has):
			continue
		if acked != null and String(r["text"]).contains("(gekwiteerd)") != bool(acked):
			continue
		n += 1
	return n

func _hold(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().process_frame

# ── the run ─────────────────────────────────────────────────────────────────

func _run() -> void:
	print("[TEST] HMI fault per line — one EREMA code on two extruders is two alarms")
	_ovs = load(_OV_SCRIPT)
	var A := CODE + " 3A"
	var C := CODE + " 3C"

	# ── fixture ─────────────────────────────────────────────────────────────
	var lf := LineFlow.new()
	lf.name = "LineFlow"
	lf.add_to_group("line_flow")
	add_child(lf)
	lf.feed_enabled = false
	for i in 2:
		var ex : Node3D = PlaceableCatalog.build_node(["extruder_3a", "extruder_3c"][i], false)
		var f : Node3D = PlaceableCatalog.build_node("laser_filter", false)
		if ex == null or f == null:
			_check(false, "the catalog built extruder %d and its laser filter" % i)
			_finish(); return
		add_child(ex)
		ex.position = Vector3(100.0 * i, 0, 0)
		add_child(f)
		f.position = Vector3(100.0 * i, 0, 9)
		_filters.append(f)
	await get_tree().process_frame
	var st : Node = get_node("/root/SimTick")
	var by_line := {}
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
		var cfg = em.get("config_resource")
		by_line[String(cfg.get("line_id")) if cfg != null else ""] = em
	_check(by_line.has("3A") and by_line.has("3C") and by_line.size() == 2,
		"two real extruder brains, config line ids %s" % [by_line.keys()])
	if not (by_line.has("3A") and by_line.has("3C")):
		_finish(); return
	_brains = [by_line["3A"], by_line["3C"]]
	for i in 2:
		_set_bar(i, CLEAR_BAR)

	var scope : Dictionary = (load(_SCOPES) as Script).call("get_scope", "hmi_extruder_all")
	_ov = (load(_OV_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_ov)
	await get_tree().process_frame
	_ov.call("open_for", String(scope.get("label", "Extruder")), scope)
	(_ov.get("_alarm_bell_btn") as Button).pressed.emit()
	_check(_ov.call("_closest_laser_filter_to", _brains[0]) == _filters[0]
		and _ov.call("_closest_laser_filter_to", _brains[1]) == _filters[1],
		"the overlay pairs each extruder with its own filter")
	_check(_tab_rows("Actief").is_empty() and _bell_state() == "none",
		"baseline at %.0f bar: no faults, bell nav-blue" % CLEAR_BAR)

	# ── A: 3A trips, is acknowledged, then 3C trips while 3A is still active ─
	_set_bar(0, TRIP_BAR)
	_check(await _await_bell("unacked"), "A1 control: 3A's 6557 alone lights the bell red")
	var act := _tab_rows("Actief")
	_check(_codes(act) == [A], "A1 Actief shows one row, labelled with its line: %s" % [_codes(act)])
	# The alarm's scope is now "extruder_3A" (it was "extruder" for every real
	# extruder). The tile lamps match scopes by token substring: exactly the
	# EXTRUDER tiles may go to fault, no other tile. Defs read from the overlay.
	var k := _ovs.get_script_constant_map()
	var faults : Array = _ov.call("_compute_faults")
	var lit : Array = []
	var want : Array = []
	for def in (k["STAGES"] as Array) + (k["SECTIONS"] as Array):
		if int(_ov.call("_group_status", def["tokens"], faults)) == int(k["ST_FAULT"]):
			lit.append(def["name"])
		if String(def["name"]) == "EXTRUDER":
			want.append(def["name"])
	_check(not want.is_empty() and lit == want,
		"A1 tile lamps: only the EXTRUDER tiles show the fault (%s)" % [lit])

	_check(_press("KWITTEREN"), "A2 pressed KWITTEREN")
	var amber : bool = await _await_bell("acked")
	_check(amber and _tab_rows("Actief").is_empty(), "A2 3A acknowledged: bell amber, Actief empty")

	_set_bar(1, TRIP_BAR)
	_check(await _await_bell("unacked"),
		"A3 3C's 6557 trips while 3A's (acknowledged) is still active: bell RED")
	act = _tab_rows("Actief")
	_check(_codes(act) == [C], "A3 Actief shows 3C's row and only 3C's: %s" % [_codes(act)])
	var hist := _tab_rows("Historie")
	_check(_count(hist, C, "Massadruk", false) == 1 and _count(hist, A, "Massadruk", true) == 1,
		"A4 Historie: 3C's trip is its own row, not gekwiteerd; 3A's stays gekwiteerd (%s)" % [_codes(hist)])

	_check(_press("KWITTEREN"), "A5 pressed KWITTEREN again")
	_check(await _await_bell("acked"), "A5 both acknowledged: bell amber")
	var ackd := _tab_rows("Gekwitteerd")
	_check(_count(ackd, A) == 1 and _count(ackd, C) == 1,
		"A5 Gekwitteerd lists both lines: %s" % [_codes(ackd)])

	_set_bar(0, CLEAR_BAR)
	await _hold(0.6)
	hist = _tab_rows("Historie")
	_check(_count(hist, A, "Hersteld", true) == 1 and _count(hist, C, "Hersteld") == 0,
		"A6 3A clears while 3C runs on: 'Hersteld' logged for 3A (gekwiteerd), none for 3C (%s)" % [_codes(hist)])
	_check(_bell_state() == "acked", "A6 3C still active and acknowledged: bell amber")

	_set_bar(0, TRIP_BAR)
	_check(await _await_bell("unacked"),
		"A7 3A trips again while 3C is acked: a new 3A occurrence, bell RED (3C's ack does not cover it)")
	_check(_codes(_tab_rows("Actief")) == [A], "A7 Actief shows the new 3A row only")

	_check(_press("KWITTEREN"), "A8 pressed KWITTEREN")
	_set_bar(0, CLEAR_BAR)
	_set_bar(1, CLEAR_BAR)
	_check(await _await_bell("none"), "A8 both clear: bell nav-blue")
	hist = _tab_rows("Historie")
	# 3A trip, 3C trip, 3A clear, 3A trip, then both clears: six transitions,
	# no more (a key that changed between observations would add rows).
	_check(hist.size() == 6 and _count(hist, A, "Hersteld") == 2 and _count(hist, C, "Hersteld") == 1,
		"A8 Historie holds exactly the 6 transitions that happened: %s" % [_codes(hist)])

	# ── B: extruders with no line id still raise one alarm each ─────────────
	for em in _brains:
		(em.get("config_resource") as Resource).set("line_id", "")
	_set_bar(0, TRIP_BAR)
	_check(await _await_bell("unacked"), "B1 unlabelled extruder 1 trips: bell red")
	act = _tab_rows("Actief")
	_check(_codes(act) == [CODE], "B1 the row shows the bare code when there is no line: %s" % [_codes(act)])
	_press("KWITTEREN")
	_check(await _await_bell("acked"), "B2 acknowledged: bell amber")
	_set_bar(1, TRIP_BAR)
	_check(await _await_bell("unacked"),
		"B3 unlabelled extruder 2 trips while 1 is acked: bell RED (told apart by machine, not by line)")
	_check(_tab_rows("Actief").size() == 1, "B3 Actief shows the one new row")

	_finish()

func _finish() -> void:
	if _ov != null and is_instance_valid(_ov):
		_ov.queue_free()
	await get_tree().process_frame
	var verdict := "PASS" if _fails == 0 and _oks > 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
