extends Node
## LINE 1 METAL DETECTION (rulings §11, 2026-09-24) — the operator: "Only line 1
## has metal detection. The very first conveyor, before the Westa conveyor, has
## a sensor at about three quarters of its length: on detection it slows to a
## stop, reverses about one full conveyor length to clear the debris, slows to
## a stop, and runs forward again until an operator stops it or the next
## detection." And line-1 bales "can hold extreme metal: car wheels, plough
## parts, very sometimes even an anvil, large nails, balls of wire".
##
##   godot --headless --path . res://src/tests/test_line1_metal_detect.tscn
##
## M — BaleDefs rolls metal into LINE_1_FOLIE bales (some, not all; never into
##     Rotterdam bales) with a kind and a weight.
## C — the cycle on a bare ShredderFeedBelt driven tick by tick: trip at 3/4,
##     speed to 0, reverse, rider back at the load end, forward, a SECOND trip
##     on the same bale; the operator's stop ends the cycle; taking the scrap
##     off the bale clears alarm + lamp and the bale then feeds through.
## N — a belt without the sensor never trips on the same bale.
## P — production: opzetband_1 is built with the sensor and named lamps,
##     opzetband_3a3b without.
## S — the scrap bin (rulings §20): builds, takes a piece with its kg and
##     shows it, stands beside opzetband 1 in line 1, is not a flow node.

const WATCHDOG_S := 300.0
const DT := 0.1

var _fails := 0
var _oks := 0
var _alarms_raised : int = 0
var _alarms_cleared : int = 0

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
	var bus := get_node_or_null("/root/EventBus")
	if bus != null:
		bus.machine_alarm_raised.connect(func(_m: String, a: String, _s: int) -> void:
			if a == "METAL-DETECT":
				_alarms_raised += 1)
		bus.machine_alarm_cleared.connect(func(_m: String, a: String) -> void:
			if a == "METAL-DETECT":
				_alarms_cleared += 1)
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _new_belt(sensor: bool) -> ShredderFeedBelt:
	var belt := ShredderFeedBelt.new()
	belt.name = "opzetband_1_test" if sensor else "opzetband_3a3b_test"
	belt.metal_detect = sensor
	belt.metal_sensor_frac = 0.75
	belt.require_shredder = false
	belt.deck_length = 0.0
	belt.incline_deg = 25.0
	belt.incline_run = 10.0 * cos(deg_to_rad(25.0))    # opzetband_1: 10 m @ 25°
	belt.deck_width = 4.0
	belt.belt_speed = 0.12
	belt.start_requested = true
	add_child(belt)
	return belt

func _metal_bale() -> Node3D:
	var bale : Node3D = PlaceableCatalog.build_node("line_1_folie", false)
	# accept_bale() reads the bale's PRE-reparent basis.x as its long axis and
	# latches BELT-JAM after 5 s on anything > 35° off the belt's travel (+Z)
	# — the first run of this suite faulted both belts that way. Lay the
	# 2.0 m side along Z, as test_shredder_feed_belt does.
	bale.rotate_y(-PI / 2.0)
	add_child(bale)
	bale.set_meta("scanned", true)
	bale.set_meta("metal_pieces", 1)
	bale.set_meta("metal_kind", "wheel")
	bale.set_meta("metal_kg", 12.0)
	return bale

func _belt_speed(belt: ShredderFeedBelt) -> float:
	var body : Node = belt.get("_belt_body")
	return float(body.get_meta("belt_speed", 0.0)) if body != null else 0.0

func _rider_progress(belt: ShredderFeedBelt) -> float:
	var riders : Array = belt.get("_riders")
	return float(riders[0]["progress"]) if riders.size() > 0 else -1.0

func _run() -> void:
	print("[TEST] line 1 metal detection — rulings §11")
	# ── M ──
	var n_metal := 0
	var kinds_ok := true
	var l1 : Array = []
	for i in 60:
		var b : Node3D = PlaceableCatalog.build_node("line_1_folie", false, true)
		add_child(b)
		l1.append(b)
		if int(b.get_meta("metal_pieces", 0)) > 0:
			n_metal += 1
			if String(b.get_meta("metal_kind", "")) == "" or float(b.get_meta("metal_kg", 0.0)) <= 0.0:
				kinds_ok = false
	var n_rot := 0
	for i in 30:
		var b : Node3D = PlaceableCatalog.build_node("rotterdam", false, true)
		add_child(b)
		l1.append(b)
		if int(b.get_meta("metal_pieces", 0)) > 0:
			n_rot += 1
	_check(n_metal >= 5 and n_metal <= 28, "M1 of 60 LINE_1_FOLIE bales, %d hide metal (chance 0.25 — 'several times a shift': some, not all)" % n_metal)
	_check(kinds_ok, "M1 every metal bale names its scrap kind and weight")
	_check(n_rot == 0, "M1 Rotterdam bales never carry metal (%d of 30)" % n_rot)
	for b in l1:
		b.queue_free()
	await get_tree().process_frame
	# ── C the cycle ──
	var belt := _new_belt(true)
	await get_tree().process_frame
	belt.set_process(false)            # this suite owns every tick
	var bale := _metal_bale()
	await get_tree().process_frame
	_check(belt.accept_bale(bale, 0), "C0 the belt accepts the metal bale")
	var path_total : float = float(belt.get("_path_total"))
	var t_trip1 := -1.0
	var p_trip1 := -1.0
	var min_speed := 1.0
	var min_p_after_trip := 2.0
	var t_trip2 := -1.0
	var t := 0.0
	var ticks := 0
	while ticks < 3600:
		belt._process(DT)
		t += DT
		ticks += 1
		var det : int = belt.metal_detections
		if det >= 1 and t_trip1 < 0.0:
			t_trip1 = t
			p_trip1 = _rider_progress(belt)
		if t_trip1 >= 0.0:
			min_speed = minf(min_speed, _belt_speed(belt))
			min_p_after_trip = minf(min_p_after_trip, _rider_progress(belt))
		if det >= 2 and t_trip2 < 0.0:
			t_trip2 = t
			break
	print("  info  : C path %.2f m, trip 1 at %.1f s (progress %.3f), min speed %.3f m/s, rider back to %.3f, trip 2 at %.1f s" % [path_total, t_trip1, p_trip1, min_speed, min_p_after_trip, t_trip2])
	_check(t_trip1 > 0.0 and absf(p_trip1 - 0.75) < 0.02, "C1 the sensor trips as the bale crosses 3/4 of the belt (progress %.3f)" % p_trip1)
	_check(min_speed < -0.10, "C1 the belt slowed to a stop and REVERSED (min speed %.3f m/s, belt speed 0.12)" % min_speed)
	_check(min_p_after_trip < 0.02, "C1 the reversal carried the bale a full length back to the load end (progress %.3f)" % min_p_after_trip)
	_check(t_trip2 > t_trip1, "C1 running forward again it tripped a SECOND time on the same bale (%.1f s after the first)" % (t_trip2 - t_trip1))
	_check(_alarms_raised == 2, "C1 two METAL-DETECT alarms on the bus (%d)" % _alarms_raised)
	var scrap : Node = null
	for c in bale.get_children():
		if c.is_in_group("metal_scrap"):
			scrap = c
	_check(scrap != null and String(scrap.get("kind")) == "wheel", "C2 a MetalScrap (wheel) rides the bale for the operator to see")
	# the operator stops the belt
	belt.request_stop()
	for i in 150:                       # 15 s: six ramp constants (tau 2.5 s) — "slows to a stop"
		belt._process(DT)
	_check(absf(_belt_speed(belt)) < 0.01 and not belt.metal_cycle_active(), "C3 the operator's stop ends the cycle where it is (speed %.3f after 15 s, cycle off)" % _belt_speed(belt))
	# …and takes the scrap off the bale
	var kg_before : float = float(bale.get_meta("remaining_kg", 0.0))
	if scrap != null:
		scrap.call("remove_from_bale")
	_check(int(bale.get_meta("metal_pieces", 1)) == 0, "C4 the bale is clean after the scrap is taken")
	_check(_alarms_cleared == 1, "C4 the METAL-DETECT alarm cleared (%d)" % _alarms_cleared)
	_check(scrap != null and scrap.get_parent() != bale, "C4 the scrap left the bale (now a world prop)")
	# restart: the bale passes the sensor and feeds through
	belt.request_start()
	var det_before : int = belt.metal_detections
	# "consumed" = the rider list is empty again (bale_consumed removes it). A
	# lambda setting a local flag cannot report it: GDScript lambdas capture
	# locals BY VALUE (the first run of this suite waited 240 s on one).
	ticks = 0
	while ticks < 2400 and belt.rider_count() > 0:
		belt._process(DT)
		ticks += 1
	_check(belt.metal_detections == det_before, "C5 no further trip once the metal is gone (%d)" % belt.metal_detections)
	_check(belt.rider_count() == 0, "C5 the clean bale fed through to the throat (%d ticks)" % ticks)
	_check(kg_before <= 0.0 or true, "C5 (info) remaining_kg before removal %.1f" % kg_before)
	belt.queue_free()
	if scrap != null and is_instance_valid(scrap):
		scrap.queue_free()
	await get_tree().process_frame
	# ── N no sensor ──
	var belt2 := _new_belt(false)
	await get_tree().process_frame
	belt2.set_process(false)
	var bale2 := _metal_bale()
	await get_tree().process_frame
	belt2.accept_bale(bale2, 0)
	ticks = 0
	while ticks < 2400 and belt2.rider_count() > 0:
		belt2._process(DT)
		ticks += 1
	_check(belt2.metal_detections == 0 and belt2.rider_count() == 0, "N1 a belt without the sensor never trips: the metal bale feeds straight through (%d ticks)" % ticks)
	belt2.queue_free()
	await get_tree().process_frame
	# ── P production ──
	var oz1 : Node3D = PlaceableCatalog.build_node("opzetband_1", false)
	add_child(oz1)
	await get_tree().process_frame
	var fb1 : Node = oz1 if oz1 is ShredderFeedBelt else oz1.find_child("*", true, false)
	if not (fb1 is ShredderFeedBelt):
		for c in oz1.find_children("*", "", true, false):
			if c is ShredderFeedBelt:
				fb1 = c
	_check(fb1 is ShredderFeedBelt and bool(fb1.get("metal_detect")) and absf(float(fb1.get("metal_sensor_frac")) - 0.75) < 1e-6,
		"P1 opzetband_1 is built WITH the sensor at 3/4")
	_check(oz1.find_child("MetaalDetectorHead", true, false) != null,
		"P1 the #196 detector head is actually ON the built belt (it never was before 2026-09-24: grafted before the belt's _ready)")
	_check(oz1.find_child("LampMetal", true, false) != null and oz1.find_child("LampClear", true, false) != null,
		"P1 the detector head's METAL / CLEAR lamps are named (switchable)")
	var oz3 : Node3D = PlaceableCatalog.build_node("opzetband_3a3b", false)
	add_child(oz3)
	await get_tree().process_frame
	var fb3 : Node = oz3 if oz3 is ShredderFeedBelt else null
	if fb3 == null:
		for c in oz3.find_children("*", "", true, false):
			if c is ShredderFeedBelt:
				fb3 = c
	_check(fb3 is ShredderFeedBelt and not bool(fb3.get("metal_detect")), "P1 opzetband_3a3b has NO sensor (operator: only line 1)")
	# ── S the scrap bin (rulings §20: "a scrap bin near the belt") ──
	var bin : Node3D = PlaceableCatalog.build_node("scrap_bin", false)
	add_child(bin)
	await get_tree().process_frame
	_check(bin != null and bin.is_in_group("scrap_bin") and bin.has_method("add_scrap"), "S1 scrap_bin builds as a ScrapBin (group scrap_bin, add_scrap)")
	var piece : Node3D = load("res://src/scenes/world/MetalScrap.gd").new()
	piece.set("kind", "plough_part")
	piece.set("kg", 25.0)
	add_child(piece)
	await get_tree().process_frame
	var got : float = float(piece.call("dump_into", bin))
	_check(absf(got - 25.0) < 1e-6 and absf(float(bin.get("scrap_kg")) - 25.0) < 1e-6 and int(bin.call("piece_count")) == 1,
		"S2 a plough part dropped in: 25 kg, 1 piece in the bin, the prop gone")
	_check(bin.find_child("ScrapHeap", true, false) != null and bin.find_child("ScrapHeap", true, false).get_child_count() == 1,
		"S2 a lump of it shows in the bin")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var oz_pos := Vector3.INF
	var bin_pos := Vector3.INF
	for n in get_tree().get_nodes_in_group("placed_object"):
		var pid := String(n.get_meta("placeable_id", ""))
		if pid == "opzetband_1":
			oz_pos = (n as Node3D).global_position
		elif pid == "scrap_bin":
			bin_pos = (n as Node3D).global_position
	_check(oz_pos != Vector3.INF and bin_pos != Vector3.INF and oz_pos.distance_to(bin_pos) < 8.0,
		"S3 line 1 places a scrap bin beside opzetband 1 (%.1f m apart)" % (oz_pos.distance_to(bin_pos) if oz_pos != Vector3.INF and bin_pos != Vector3.INF else -1.0))
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.set("feed_enabled", false)
	lf.call("rebuild")
	var bin_in_flow := false
	for nd in (lf.get("_nodes") as Array):
		if String(nd.get("id", "")) == "scrap_bin":
			bin_in_flow = true
	_check(not bin_in_flow, "S3 the scrap bin is NOT a flow node (role none)")
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
