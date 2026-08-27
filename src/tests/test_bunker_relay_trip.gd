extends Node
## BUNKER RELAY TRIP — sustained low-speed motor stall/relay trip
## (LineFlow.gd:_tick_advanced_systems, ruling B3 2026-07-06, PR #113).
##
##   godot --headless --path . res://src/tests/test_bunker_relay_trip.tscn
##
## Places the real "line_sort" macro (BuildMode._build_full_line) and runs the
## real LineFlow.tick() — no bench stand-in. Drives the bunker's own
## bunker_speed_max/bunker_relay_trip_below catalog meta and rpm_pct exactly
## like the HMI slider would, rather than poking a fabricated threshold.
##
## THE FORMULA UNDER TEST: trip_delay = lerp(120.0, 900.0, speed/trip_below) —
## the ruling gives exactly one sourced anchor (200 -> 900s / 15 min); the
## implementation's own comment says the rest of the curve is unsourced and
## linear until docs say otherwise. This test locks in THAT documented
## formula (so a change to it is a visible, deliberate diff), not some
## independently-invented "correct" curve.
##
## OBSERVED BEHAVIOUR, DELIBERATELY EXERCISED (S3/S4): the trip only sets
## powered=false for the ONE tick it fires on — LineFlow's own PLC block runs
## before _tick_advanced_systems every tick and re-asserts powered=true for
## any fully-started stage, so at sustained low speed this reads as a
## periodic "stall event" (matching the ruling's "fire ... events ~every
## 15 min", plural), not a latch a human has to clear. If that's not the
## intended behaviour, this test is what needs updating alongside the fix —
## it is asserting what the code DOES, not a guess at what it SHOULD do.

var _fails : int = 0
var _alarms : Array = []   # [{id, alarm_id, sev}] captured off EventBus

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _on_alarm_raised(id: String, alarm_id: String, sev: int) -> void:
	_alarms.append({"id": id, "alarm_id": alarm_id, "sev": sev})

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] bunker relay trip (sustained low speed)")

	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("machine_alarm_raised"):
		bus.machine_alarm_raised.connect(_on_alarm_raised)

	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_sort", Vector3.ZERO, 0.0)
	await get_tree().process_frame

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")

	var nodes : Array = lf.get("_nodes")
	var bunker_i := -1
	for i in nodes.size():
		var node3d = (nodes[i] as Dictionary).get("node")
		if node3d == null or not is_instance_valid(node3d) or not (node3d as Node3D).has_meta("macro_index"):
			continue
		if int((node3d as Node3D).get_meta("macro_index")) == 3:
			bunker_i = i
			break
	_check(bunker_i >= 0, "bunker instance found (macro_index 3)")
	if bunker_i < 0:
		print("[TEST] bunker relay trip FAIL (setup incomplete)")
		get_tree().quit(1); return

	var bunker_node : Node3D = nodes[bunker_i]["node"]
	# PlaceableCatalog._m_bunker() stamps bunker_relay_trip_below/bunker_speed_max
	# on the composite "Model" CHILD node, not on the StaticBody3D root BuildMode
	# places (that root only carries placement meta — macro_id etc). This test
	# ORIGINALLY checked bunker_node directly and caught LineFlow reading the
	# wrong node for this exact reason (its check silently never matched
	# anything, so the feature never fired in real gameplay); LineFlow.gd now
	# falls through to the "Model" child when the root doesn't carry the meta.
	# Resolve the same way here so this test verifies the CATALOG DATA exists
	# (a real precondition) without re-asserting LineFlow's internal node
	# resolution, which S1-S5 below exercise end-to-end anyway.
	var meta_node : Node3D = bunker_node
	if not meta_node.has_meta("bunker_relay_trip_below"):
		meta_node = bunker_node.get_node_or_null("Model")
	_check(meta_node != null and meta_node.has_meta("bunker_relay_trip_below"),
		"bunker's catalog meta (root or Model child) carries bunker_relay_trip_below")
	if meta_node == null or not meta_node.has_meta("bunker_relay_trip_below"):
		print("[TEST] bunker relay trip FAIL (setup incomplete — no bunker_relay_trip_below meta anywhere)")
		get_tree().quit(1); return
	var trip_below : float = float(meta_node.get_meta("bunker_relay_trip_below"))
	var max_speed : float = float(meta_node.get_meta("bunker_speed_max"))
	_check(is_equal_approx(trip_below, 200.0), "trip_below == 200 (catalog value, %.1f)" % trip_below)
	_check(is_equal_approx(max_speed, 1000.0), "bunker_speed_max == 1000 (catalog value, %.1f)" % max_speed)

	# ── S1 baseline: start the real PLC and ramp fully up before asserting
	# anything about `powered` (same ramp margin as the shredder-2 interlock
	# test — TARGET_STARTUP_S = 20s). ─────────────────────────────────────────
	lf.call("start_line")
	for _i in 260: lf.tick(0.1)
	_check(bool(nodes[bunker_i]["powered"]), "S1 bunker powered after line start")
	_check(float(nodes[bunker_i].get("_bunker_relay_t", 0.0)) == 0.0,
		"S1 relay timer starts at 0")

	# ── S2 default speed (rpm_pct 1.0 -> 1000, well above trip_below) never
	# accrues the timer, no matter how long it runs. ──────────────────────────
	for _i in 50: lf.tick(1.0)
	_check(bool(nodes[bunker_i]["powered"]), "S2 bunker still powered at full speed")
	_check(float(nodes[bunker_i].get("_bunker_relay_t", 0.0)) == 0.0,
		"S2 relay timer stays at 0 at full speed (no false accrual)")
	_check(_alarms.is_empty(), "S2 no RELAY-TRIP alarm at full speed")

	# ── S3 drop to half of trip_below (speed 100) and tick to exactly the
	# documented trip_delay = lerp(120, 900, 100/200) = 510s. ────────────────
	nodes[bunker_i]["rpm_pct"] = 0.1
	var speed_setting : float = 0.1 * max_speed
	var expect_delay : float = lerpf(120.0, 900.0, speed_setting / trip_below)
	_check(is_equal_approx(expect_delay, 510.0), "expected trip_delay at speed 100 == 510s (%.1f)" % expect_delay)

	for _i in int(expect_delay) - 1:
		lf.tick(1.0)
	_check(bool(nodes[bunker_i]["powered"]), "S3 still powered just BEFORE the trip_delay elapses")
	_check(_alarms.is_empty(), "S3 no alarm yet just before trip_delay")

	lf.tick(1.0)   # the tick that crosses trip_delay
	_check(not bool(nodes[bunker_i]["powered"]),
		"S3 the tick that crosses trip_delay sets powered=false")
	_check(_alarms.size() == 1 and String(_alarms[0]["alarm_id"]) == "RELAY-TRIP" and int(_alarms[0]["sev"]) == 3,
		"S3 EventBus got exactly one RELAY-TRIP alarm, severity 3 (%s)" % str(_alarms))
	_check(float(nodes[bunker_i].get("_bunker_relay_t", -1.0)) == 0.0,
		"S3 relay timer resets to 0 on the trip tick itself")

	# ── S4 the NEXT tick: LineFlow's own PLC block re-asserts powered=true for
	# a fully-started stage (documented above) — this is the actual shipped
	# behaviour, not an assumption. ───────────────────────────────────────────
	lf.tick(1.0)
	_check(bool(nodes[bunker_i]["powered"]),
		"S4 PLC re-powers the bunker the very next tick (periodic stall, not a latch)")

	# ── S5 speed still low -> the timer accrues again toward a SECOND trip
	# (proves the fault is periodic, matching the ruling's "events", plural,
	# not a one-shot). Only check accrual restarted, not a full second 510s
	# wait, to keep the test fast. ────────────────────────────────────────────
	for _i in 5: lf.tick(1.0)
	_check(float(nodes[bunker_i].get("_bunker_relay_t", 0.0)) > 0.0,
		"S5 relay timer accrues again while speed stays low (periodic, not one-shot)")

	if _fails == 0:
		print("[TEST] bunker relay trip PASS")
	else:
		print("[TEST] bunker relay trip FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
