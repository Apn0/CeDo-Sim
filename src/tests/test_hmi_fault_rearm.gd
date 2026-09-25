extends Node
## HMI FAULT RE-ARM (2026-09-24) — a fault that clears by itself and trips again
## is a NEW occurrence, and a KWITTEREN given to the first one must not silence
## the second.
##
##   godot --headless --path . res://src/tests/test_hmi_fault_rearm.tscn
##
## The defect (code read on main b8bda8a, then measured by this suite): the
## overlay's ack was a per-CODE set that only RESETTEN cleared. Trip 6557 →
## KWITTEREN → the pressure drops and the fault clears → it trips again: the
## second occurrence came up already "gekwiteerd", off the Actief tab, and the
## bell stayed amber-steady. Reference model: Apn0/TVE-micro backend/logic.py
## _latch_alarm, which dedupes only against an UNCLEARED alarm of the same type,
## so a re-latch is a new, unacknowledged alarm object (ISA-18.2).
##
## Second path, same defect: the overlay only looked at the plant while it was
## OPEN (_process returned on `not visible`). An operator acks and walks away,
## the fault clears and trips again while the panel is shut, and on reopen the
## overlay had seen neither edge — same code still "active", still acked.
##
## Fixture, and what is real in it:
##   * the real HmiOverlay.tscn, opened with the real hmi_extruder_all scope and
##     operated only through its own buttons (BELL, sub-tabs, KWITTEREN, close);
##     every check reads what the operator sees — the rows and the bell colour;
##   * a real LineFlow (0 machines, feed off so INV-101 stays out of it until
##     phase D, which swaps it for a second one under the closed panel);
##   * a real catalog laser_filter, and the real EremaFaultRegistry detector.
##   * NOT real: the pressure. It is written through LaserFilter's own
##     set_mp_after_filter_bar(), the setter ExtruderMachine calls every tick. A real brain cannot hold it: OFF it writes 0.0 every tick
##     (ExtruderMachine.gd `_update_downstream_signals`), RUNNING needs the
##     30-minute preheat and a clogged head filter. So the extruder here is a
##     bare Node3D in the "extruder_machine" group — the registry's
##     detect_active(null, filter) path, which it documents as supported.
##
## Pressures come from the 3C photo the registry cites: 343 bar was the reading
## in red alarm, 284-298 bar ran clean.

const WATCHDOG_S := 120.0
const CODE := "EREMA-6557"
const TRIP_BAR := 343.0
const CLEAR_BAR := 291.0
## How long a state is held while the panel is CLOSED. The overlay observes at
## 4 Hz, so this is four observation periods. Wall time, not frames.
const HOLD_S := 1.0
## Upper bound for the overlay's own 0.25 s refresh to show a change.
const SEE_TIMEOUT_S := 3.0

const _OV_SCENE := "res://src/scenes/hud/HmiOverlay.tscn"
const _OV_SCRIPT := "res://src/scenes/hud/HmiOverlay.gd"
const _SCOPES := "res://src/build/HmiScopes.gd"
const _REGISTRY := "res://src/sim/EremaFaultRegistry.gd"

var _fails := 0
var _oks := 0
var _ov : Node = null
var _ovs : Script = null
var _filter : Node = null
var _scope : Dictionary = {}
var _label := ""

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

# ── operator-side helpers ───────────────────────────────────────────────────

## (2026-09-25: this was set_upstream_pressure_indicator(psi), inverted
## through the registry's old psi * 0.0689. #278 split the melt pressure in two
## and removed that setter. With no melt flowing the filter's no-flow gate holds
## its dMP at 0, so the pressure BEFORE the filter, mp_before_filter_bar(),
## which EREMA 6557 reads, is exactly the bar written here.)
func _set_bar(bar: float) -> void:
	_filter.call("set_mp_after_filter_bar", bar)

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

func _bell() -> Button:
	return _ov.get("_alarm_bell_btn") as Button

func _press_bell() -> void:
	_bell().pressed.emit()

## "none" (nav blue, no faults), "acked" (amber, all acked), "unacked" (red).
func _bell_state() -> String:
	var sb := _bell().get_theme_stylebox("normal") as StyleBoxFlat
	if sb == null:
		return "?"
	if sb.bg_color.is_equal_approx(_ovs.get_script_constant_map()["C_NAV"]):
		return "none"
	if sb.bg_color.is_equal_approx(_ovs.get_script_constant_map()["LAMP_IDLE"]):
		return "acked"
	return "unacked"

## Rows of one STORINGEN sub-tab, newest first as the panel lists them.
## Pressing the tab rebuilds the screen and refreshes it, as on the real panel.
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

func _rows_for(rows: Array, code: String) -> Array:
	var out : Array = []
	for r in rows:
		if String(r["code"]) == code:
			out.append(r)
	return out

func _acked_text(r: Dictionary) -> bool:
	return String(r["text"]).contains("(gekwiteerd)")

## Wait on wall time until the bell (repainted only by the overlay's own
## 0.25 s refresh) reads `want`. Returns the seconds it took, or -1.0.
func _await_bell(want: String) -> float:
	var t0 := Time.get_ticks_msec()
	while _bell_state() != want:
		if Time.get_ticks_msec() - t0 > int(SEE_TIMEOUT_S * 1000.0):
			return -1.0
		await get_tree().process_frame
	return float(Time.get_ticks_msec() - t0) / 1000.0

func _hold(seconds: float) -> void:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < int(seconds * 1000.0):
		await get_tree().process_frame

## The navbar X — Sluiten. Returns true when the panel really is closed.
func _close() -> bool:
	for b in _live_buttons(_ov):
		if String((b as Button).tooltip_text) == "Sluiten":
			(b as Button).pressed.emit()
			return not bool(_ov.call("is_open"))
	return false

func _open_on_storingen() -> void:
	_ov.call("open_for", _label, _scope)
	_press_bell()

# ── the run ─────────────────────────────────────────────────────────────────

func _run() -> void:
	print("[TEST] HMI fault re-arm — a re-trip is a new, unacknowledged occurrence")
	_ovs = load(_OV_SCRIPT)
	var reg : Script = load(_REGISTRY)
	var trip_limit := float(reg.get_script_constant_map()["MPF1_PRESSURE_TRIP_BAR"])
	_check(TRIP_BAR > trip_limit and CLEAR_BAR < trip_limit,
		"the photo's pressures straddle the registry's 6557 limit (%.0f < %.0f < %.0f bar)"
		% [CLEAR_BAR, trip_limit, TRIP_BAR])

	# ── fixture ─────────────────────────────────────────────────────────────
	var lf := LineFlow.new()
	lf.name = "LineFlow"
	lf.add_to_group("line_flow")
	add_child(lf)
	lf.feed_enabled = false
	_filter = PlaceableCatalog.build_node("laser_filter", false)
	_check(_filter != null and _filter.has_method("set_mp_after_filter_bar"),
		"the catalog built a real LaserFilter")
	if _filter == null:
		_finish(); return
	add_child(_filter)
	var anchor := Node3D.new()
	anchor.name = "ExtruderAnchor"
	anchor.add_to_group("extruder_machine")
	add_child(anchor)
	anchor.position = Vector3(0, 0, 3)
	_set_bar(CLEAR_BAR)

	_scope = (load(_SCOPES) as Script).call("get_scope", "hmi_extruder_all")
	_label = String(_scope.get("label", "Extruder"))
	_check(not _scope.is_empty(), "the real hmi_extruder_all scope resolved")
	_ov = (load(_OV_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child(_ov)
	await get_tree().process_frame
	_open_on_storingen()
	_check(_ov.get("_line_flow") == lf, "the overlay resolved the real LineFlow (no PLC-000)")
	_check((_ov.get("_laser_filters") as Array).size() == 1 and (_ov.get("_extruder_machines") as Array).size() == 1,
		"the overlay sees exactly the one filter and the one extruder")
	_check(_tab_rows("Actief").is_empty() and _bell_state() == "none",
		"baseline at %.0f bar: no faults at all, bell nav-blue (anything later is 6557's)" % CLEAR_BAR)

	# ── A. the brief's trigger, panel open throughout ─────────────────────────
	print("-- A: trip, KWITTEREN, self-clear, re-trip — panel open")
	_set_bar(TRIP_BAR)
	var dt := await _await_bell("unacked")
	_check(dt >= 0.0, "A1 the overlay's own refresh raised the bell red %.2f s after the trip" % dt)
	var act := _tab_rows("Actief")
	_check(act.size() == 1 and String(act[0]["code"]) == CODE and not _acked_text(act[0]),
		"A1 Actief lists exactly %s, unacknowledged (rows %s)" % [CODE, act])
	_check(not bool(_filter.get("is_tripped")),
		"A1 the filter's own 318-bar latch stayed out of it (no flow) — 6557 is the only alarm")

	_check(_press("KWITTEREN"), "A2 pressed KWITTEREN")
	_check(_bell_state() == "acked", "A2 bell amber-steady after KWITTEREN (%s)" % _bell_state())
	_check(_rows_for(_tab_rows("Actief"), CODE).is_empty(), "A2 Actief no longer lists %s" % CODE)
	var gk := _rows_for(_tab_rows("Gekwitteerd"), CODE)
	_check(gk.size() == 1 and _acked_text(gk[0]), "A2 Gekwitteerd lists %s as gekwiteerd" % CODE)

	await _hold(HOLD_S)
	_check(_bell_state() == "acked",
		"A2b a STILL-ACTIVE occurrence stays acked through %.1f s of refreshes (no over-fix)" % HOLD_S)

	_set_bar(CLEAR_BAR)
	dt = await _await_bell("none")
	_check(dt >= 0.0, "A3 the fault cleared by itself; bell nav-blue %.2f s after the drop" % dt)
	var hist := _rows_for(_tab_rows("Historie"), CODE)
	_check(hist.size() == 2 and String(hist[0]["text"]).contains("Hersteld"),
		"A3 Historie: the clear is recorded as the newest %s row (%d rows)" % [CODE, hist.size()])

	_set_bar(TRIP_BAR)
	dt = await _await_bell("unacked")
	_check(dt >= 0.0,
		"A4 THE DEFECT: the re-trip raises the bell RED again (%s after %.2f s)" % [_bell_state(), dt])
	act = _rows_for(_tab_rows("Actief"), CODE)
	_check(act.size() == 1 and not _acked_text(act[0]),
		"A4 THE DEFECT: the re-trip is back on Actief, unacknowledged (rows %s)" % [act])
	hist = _rows_for(_tab_rows("Historie"), CODE)
	_check(hist.size() == 3 and not _acked_text(hist[0]) and _acked_text(hist[2]),
		"A4 Historie keeps the ack PER OCCURRENCE: new trip unacked, the first still gekwiteerd (%s)" % [hist])

	# ── C. control: panel closed, the fault does NOT clear ───────────────────
	print("-- C: KWITTEREN, close, fault stays active, reopen")
	_check(_press("KWITTEREN"), "C0 pressed KWITTEREN on the second occurrence")
	_check(_bell_state() == "acked", "C0 bell amber-steady")
	_check(_close(), "C0 closed the panel with its X button")
	await _hold(HOLD_S)
	_open_on_storingen()
	_check(_bell_state() == "acked",
		"C1 a fault that stayed active while the panel was shut is still acked on reopen (%s)" % _bell_state())

	# ── B. the same cycle with the panel CLOSED between ack and reopen ────────
	print("-- B: KWITTEREN, close, self-clear + re-trip while closed, reopen")
	_check(_close(), "B0 closed the panel with its X button (the C0 ack still stands)")
	_set_bar(CLEAR_BAR)
	await _hold(HOLD_S)
	_set_bar(TRIP_BAR)
	await _hold(HOLD_S)
	_open_on_storingen()
	_check(_bell_state() == "unacked",
		"B1 THE DEFECT, CLOSED PANEL: the re-trip while the operator was away is RED on reopen (%s)" % _bell_state())
	act = _rows_for(_tab_rows("Actief"), CODE)
	_check(act.size() == 1 and not _acked_text(act[0]),
		"B1 the re-trip is on Actief, unacknowledged (rows %s)" % [act])
	hist = _rows_for(_tab_rows("Historie"), CODE)
	_check(hist.size() == 5 and String(hist[1]["text"]).contains("Hersteld"),
		"B2 Historie recorded the clear that happened while the panel was shut (%d rows: %s)" % [hist.size(), hist])

	# ── D. the world is swapped under a CLOSED panel ─────────────────────────
	# The overlay is ONE shared instance under the root (Hmi.gd `static var
	# _overlay`) and outlives the world. Watching while closed must survive the
	# LineFlow being freed, log no PLC-000 for a plant that is not there, and not
	# read the old world's fed_mass as "nothing fed" in the new one (INV-101).
	# NOT real: fed_mass is written here (the new world's in 0.1 s steps,
	# LineFlow's tick rate).
	# The overlay reads nothing else for INV-101, and a world that really feeds
	# needs a head machine and a bale.
	# The old world has fed 5125 kg when the operator last looks at the panel —
	# open_for() takes its baseline from that. Without the closed panel following
	# fed_mass frame by frame, the new world's first 20 kg read as "nothing fed"
	# for 3 s and INV-101 is logged against a line that is feeding.
	print("-- D: the world is swapped while the panel is closed")
	lf.feed_enabled = true
	lf.fed_mass = 5125.0
	_check(_close(), "D0 closed the panel with its X button")
	_open_on_storingen()
	_check(_close(), "D0 a last look at the old world's panel (5125 kg fed), closed again")
	lf.queue_free()
	await _hold(HOLD_S)
	var lf2 := LineFlow.new()
	lf2.name = "LineFlow2"
	lf2.add_to_group("line_flow")
	add_child(lf2)
	lf2.feed_enabled = true
	for _i in range(40):
		lf2.fed_mass += 0.5
		await _hold(0.1)
	_check(_ov.get("_line_flow") == lf2,
		"D1 the closed panel bound the new world's LineFlow by itself")
	_open_on_storingen()
	hist = _tab_rows("Historie")
	_check(_rows_for(hist, "PLC-000").is_empty(),
		"D2 no PLC-000 logged for the %.1f s with no world (nothing to watch is not a fault)" % HOLD_S)
	_check(_rows_for(hist, "INV-101").is_empty(),
		"D3 no false INV-101: 20 kg fed in 4 s in the new world is feeding, even below the old world's 5125 kg")

	# ── info: what observing while closed costs ──────────────────────────────
	var n := 400
	var t0 := Time.get_ticks_usec()
	for _i in range(n):
		_ov.call("_compute_faults")
	print("  info  : _compute_faults() %.1f µs/call on this fixture (a closed panel now calls it at 4 Hz)"
		% (float(Time.get_ticks_usec() - t0) / float(n)))

	_finish()

func _finish() -> void:
	if _ov != null and is_instance_valid(_ov):
		_ov.queue_free()
	await get_tree().process_frame
	var verdict := "PASS" if _fails == 0 and _oks > 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if verdict == "PASS" else 1)
