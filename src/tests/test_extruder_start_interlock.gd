extends Node
## The extruder's start button and its "natraject" — operator rulings
## 2026-09-25, docs/plant/operator_rulings_2026-09-25.md §I1-§I9.
##
##   godot --headless --path . res://src/tests/test_extruder_start_interlock.tscn
##
## WHAT THE OPERATOR SAID (recollection; no SWI lists the extruder's start
## conditions, and the raw WinCC archive logs none of these machines):
##   * The right white LED ring button first runs safety checks. One fails:
##     nothing starts, the alarm rings and shows the problem, and the button
##     does nothing until the alarm is RESET — on the HMI, not at the machine.
##   * Checks passed: blower -> centrifuge -> sieve -> heetafslag water ->
##     knives -> laserfilter scraper -> screw, each once the one before is up.
##     The ring blinks 0.5 s off / 0.5 s on, and is solid as the screw ramps.
##   * A stop or a trip stops the screw FIRST; the ring blinks while the rest
##     runs down, and goes off once everything stands.
##   * Rulings on the sim: the extruder, not the line, runs its natraject (the
##     line's start no longer powers it); a natraject machine that stops under
##     a running screw trips the extruder; "natraject" is a hidden setting,
##     on by default, that the player can switch on the extruder panel.
##
## BEFORE this suite: the only thing that could refuse a start was the barrel
## temperature. The line's start powered the pellet side and pushed material
## through the extruder whether or not it had been started (found by reading
## LineFlow and ExtruderModel: fully decoupled).
##
##   A  the sequence alone (ExtruderStartSequence), on a fake plant: order,
##      waits, the ring, refusal, the latch, the trip, the run-down, the
##      natraject setting, the timeout and the mid-start abort.
##   B  a real 3B line (BuildMode._build_full_line -> LineFlow.rebuild ->
##      start_line -> tick) with its real extruder brain, and a 3C line with
##      no brain beside it: who powers what, the start in order by the
##      machines' own spin, kg through the natraject, a trip on loss, the
##      latch, the HMI reset, and recovery.
##   C  the HMI: the touchscreen's extruder panel and the web HMI's line strip
##      (ring lamp, status, ALARM RESET, the natraject switch), and an extruder
##      with no pellet side started by switching natraject off.
##
## The brains are unhooked from SimTick and stepped by hand with LineFlow, so
## every time below is sim time. A bare BuildMode never saves; nothing here
## writes world_layout.json.

const SEQ := preload("res://src/sim/ExtruderStartSequence.gd")
const REG := preload("res://src/sim/EremaFaultRegistry.gd")
const DT : float = 0.1
const WATCHDOG_S : float = 420.0
const STEPS : Array[String] = ["weegschaal", "centrifuge", "ontwaterzeef", "heetafslag", "laser_filter"]
const FEED_KG_S : float = 0.26        # ~950 kg/h, 3B's nominal (as test_extruder_silo_chain)

var _oks : int = 0
var _fails : int = 0
var _done : bool = false
var _lf : Node = null
var _brains : Array = []
var _moved : Dictionary = {}          # flow body instance id -> Σ _moved_kg
var _t : float = 0.0


func _check(cond: bool, label: String) -> void:
	if cond:
		_oks += 1
		print("  ok    : %s" % label)
	else:
		_fails += 1
		print("  FAIL  : %s" % label)


func _info(label: String) -> void:
	print("  info  : %s" % label)


func _ready() -> void:
	print("=== extruder start button: checks, natraject in order, trip on loss, HMI reset ===")
	if get_node_or_null("/root/EventBus") == null:
		print("FATAL: autoloads missing — boot the .tscn, not --script")
		get_tree().quit(2)
		return
	# Watchdog: a runtime SCRIPT ERROR aborts the coroutine and the scene would
	# idle forever with no verdict (CLAUDE.md, "a headless run that outlives...").
	get_tree().create_timer(WATCHDOG_S).timeout.connect(_on_watchdog)
	await get_tree().process_frame
	_part_a()
	await _part_b()
	_finish()


func _on_watchdog() -> void:
	if _done:
		return
	_done = true
	print("Result: FAIL (watchdog — no verdict after %.0f s; %d ok, %d fail so far)" % [WATCHDOG_S, _oks, _fails])
	get_tree().quit(2)


# ── A. the sequence alone, on a fake plant ────────────────────────────────────
func _fake_plant() -> Dictionary:
	var p := {}
	for id in STEPS:
		p[id] = {"found": true, "available": true, "why": "", "powered": false, "spin": 0.0, "stuck": false}
	return p


## One tick of the sequence, then the fake plant follows its commands the way
## LineFlow does: powered = commanded and not held off, spin ramps over 2.5 s.
func _fake_step(seq, plant: Dictionary, driven: bool, turning: bool) -> Dictionary:
	var out : Dictionary = seq.tick(DT, plant, driven, turning)
	for id in STEPS:
		var m : Dictionary = plant[id]
		m["powered"] = bool(seq.run_cmd[id]) and bool(m["available"])
		var target : float = 1.0 if bool(m["powered"]) and not bool(m["stuck"]) else 0.0
		m["spin"] = move_toward(float(m["spin"]), target, DT / 2.5)
	return out


func _part_a() -> void:
	print("  -- A. the start sequence alone --")
	var seq = SEQ.new()
	var plant := _fake_plant()
	var r : String = seq.press(plant)
	_check(r == "" and seq.phase == SEQ.Phase.NATRAJECT_UP and seq.led() == SEQ.Led.BLINK,
		"A1 a press with every natraject machine ready starts the sequence (phase %d, ring blinking)" % seq.phase)

	var on_t := {}
	var up_t := {}
	var screw_t := -1.0
	var starts := 0
	var lit : Array = []
	var t := 0.0
	for _i in range(int(30.0 / DT)):
		var out := _fake_step(seq, plant, screw_t >= 0.0, screw_t >= 0.0)
		t += DT
		lit.append(bool(seq.led_lit()))
		for id in STEPS:
			if bool(seq.run_cmd[id]) and not on_t.has(id):
				on_t[id] = t
			if float(plant[id]["spin"]) >= SEQ.SPUN_UP and not up_t.has(id):
				up_t[id] = t
		if bool(out["start_screw"]):
			starts += 1
			if screw_t < 0.0:
				screw_t = t
		if screw_t >= 0.0 and t > screw_t + 2.0:
			break
	var order_ok := on_t.size() == STEPS.size()
	var wait_ok := order_ok
	for k in range(1, STEPS.size()):
		if not order_ok:
			break
		order_ok = order_ok and float(on_t[STEPS[k]]) > float(on_t[STEPS[k - 1]])
		wait_ok = wait_ok and up_t.has(STEPS[k - 1]) and float(on_t[STEPS[k]]) >= float(up_t[STEPS[k - 1]])
	_check(order_ok and wait_ok,
		"A2 switched on in the ruled order, each only once the one before is up: %s"
		% ", ".join(STEPS.map(func(id): return "%s %.1f s" % [id, float(on_t.get(id, -1.0))])))
	_check(starts == 1 and up_t.has("laser_filter") and screw_t >= float(up_t["laser_filter"]),
		"A3 the screw start is asked for once (%d), at %.1f s, after the laserfilter is up (%.1f s)"
		% [starts, screw_t, float(up_t.get("laser_filter", -1.0))])
	# The ring: 0.5 s off first, then 0.5 s on (operator: "0.5 seconds off, 0.5
	# seconds on"), solid from the screw start.
	var blink_ok : bool = lit.size() > 17 and not bool(lit[2]) and bool(lit[6]) and not bool(lit[11]) and bool(lit[16])
	_check(blink_ok and seq.led() == SEQ.Led.SOLID and seq.led_lit(),
		"A4 the ring blinks off 0.5 s / on 0.5 s while the natraject comes up (0.3 s %s, 0.7 s %s, 1.2 s %s, 1.7 s %s) and is solid with the screw"
		% [lit[2], lit[6], lit[11], lit[16]])

	# A machine that stops under the running screw trips it.
	plant["centrifuge"]["available"] = false
	plant["centrifuge"]["why"] = "staat in HAND"
	var trip := ""
	for _i in range(5):
		var out2 := _fake_step(seq, plant, true, true)
		if String(out2["trip"]) != "":
			trip = String(out2["trip"])
			break
	_check(trip.contains("Centrifuge") and trip.contains("HAND") and seq.alarm == trip
			and seq.phase == SEQ.Phase.RUN_DOWN and seq.led() == SEQ.Led.BLINK,
		"A5 the centrifuge dropping out under a running screw trips it: '%s', alarm latched, ring blinking" % trip)

	# The screw stops first; the rest runs down in reverse, each once the one
	# after it has stopped.
	for _i in range(int(2.0 / DT)):
		_fake_step(seq, plant, false, true)
	var held : bool = bool(seq.run_cmd["laser_filter"]) and bool(seq.run_cmd["weegschaal"])
	var off_t := {}
	var down_t := {}
	t = 0.0
	for _i in range(int(30.0 / DT)):
		_fake_step(seq, plant, false, false)
		t += DT
		for id in STEPS:
			if not bool(seq.run_cmd[id]) and not off_t.has(id):
				off_t[id] = t
			if float(plant[id]["spin"]) <= SEQ.SPUN_DOWN and not down_t.has(id):
				down_t[id] = t
		if seq.phase == SEQ.Phase.IDLE:
			break
	var rev : Array = STEPS.duplicate()
	rev.reverse()
	var rd_ok := off_t.size() == STEPS.size()
	for k in range(1, rev.size()):
		if not rd_ok:
			break
		rd_ok = rd_ok and float(off_t[rev[k]]) >= float(off_t[rev[k - 1]]) \
			and float(off_t[rev[k]]) >= float(down_t.get(rev[k - 1], INF))
	_check(held and rd_ok and seq.phase == SEQ.Phase.IDLE and seq.led() == SEQ.Led.OFF,
		"A6 nothing stops while the screw still turns (%s); then laserfilter first, weegschaal last, each once the one before stands: %s; ring off"
		% [held, ", ".join(rev.map(func(id): return "%s %.1f s" % [id, float(off_t.get(id, -1.0))]))])

	# The latch: fixed, pressed again — nothing, until the alarm is reset.
	plant["centrifuge"]["available"] = true
	var r2 : String = seq.press(plant)
	var none_on := true
	for id in STEPS:
		none_on = none_on and not bool(seq.run_cmd[id])
	var latched_ok : bool = r2.begins_with("alarm") and none_on and seq.phase == SEQ.Phase.IDLE
	seq.reset_alarm()
	var r3 : String = seq.press(plant)
	_check(latched_ok and r3 == "" and seq.phase == SEQ.Phase.NATRAJECT_UP,
		"A7 with the alarm latched a press does nothing ('%s'); after the reset the same press starts the sequence" % r2)

	# A failed check refuses the start and starts nothing.
	var s2 = SEQ.new()
	var p2 := _fake_plant()
	p2["ontwaterzeef"]["available"] = false
	p2["ontwaterzeef"]["why"] = "staat in HAND"
	var r4 : String = s2.press(p2)
	for _i in range(20):
		_fake_step(s2, p2, false, false)
	var none2 := true
	for id in STEPS:
		none2 = none2 and not bool(s2.run_cmd[id])
	_check(r4 == "Start geweigerd — Ontwaterzeef: staat in HAND" and s2.alarm == r4 and none2
			and s2.phase == SEQ.Phase.IDLE and s2.led() == SEQ.Led.OFF,
		"A8 the sieve in HAND refuses the start: '%s', nothing switched on, ring off" % r4)
	var s3 = SEQ.new()
	var p3 := _fake_plant()
	p3["weegschaal"]["found"] = false
	var r5 : String = s3.press(p3)
	_check(r5 == "Start geweigerd — Blower + weegschaal niet gevonden",
		"A9 a missing natraject machine refuses the start: '%s'" % r5)

	# Natraject off: no checks, nothing started; the screw is followed.
	var s4 = SEQ.new()
	s4.natraject_enabled = false
	var r6 : String = s4.press({})
	var o6 : Dictionary = s4.tick(DT, {}, false, false)
	var none4 := true
	for id in STEPS:
		none4 = none4 and not bool(s4.run_cmd[id])
	s4.tick(DT, {}, true, true)
	var solid4 : bool = s4.led() == SEQ.Led.SOLID
	s4.tick(DT, {}, false, false)
	s4.tick(DT, {}, false, false)
	_check(r6 == "" and not bool(o6["start_screw"]) and none4 and solid4 and s4.phase == SEQ.Phase.IDLE,
		"A10 natraject OFF: no machine found is fine, nothing is switched on, the ring follows the screw (solid %s) and goes off after it" % solid4)

	# A machine that never comes up aborts the start.
	var s5 = SEQ.new()
	var p5 := _fake_plant()
	p5["ontwaterzeef"]["stuck"] = true
	s5.press(p5)
	var abort_t := -1.0
	t = 0.0
	for _i in range(int(30.0 / DT)):
		var o5 := _fake_step(s5, p5, false, false)
		t += DT
		if bool(o5["start_screw"]):
			break
		if s5.alarm != "" and abort_t < 0.0:
			abort_t = t
			break
	_check(s5.alarm == "Start afgebroken — Ontwaterzeef komt niet op toeren" and abort_t > 0.0
			and s5.phase == SEQ.Phase.RUN_DOWN,
		"A11 a sieve that never gets up to speed aborts the start after %.1f s: '%s'" % [abort_t, s5.alarm])

	# A machine already started that trips aborts the start, and the screw never starts.
	var s6 = SEQ.new()
	var p6 := _fake_plant()
	s6.press(p6)
	var screw6 := false
	for _i in range(int(4.0 / DT)):
		screw6 = screw6 or bool(_fake_step(s6, p6, false, false)["start_screw"])
	p6["weegschaal"]["available"] = false
	p6["weegschaal"]["why"] = "motor uitgevallen (thermisch)"
	for _i in range(int(20.0 / DT)):
		screw6 = screw6 or bool(_fake_step(s6, p6, false, false)["start_screw"])
	_check(not screw6 and s6.alarm == "Start afgebroken — Blower + weegschaal: motor uitgevallen (thermisch)",
		"A12 the weegschaal tripping mid-start aborts it and the screw never starts: '%s'" % s6.alarm)


# ── B. a real 3B line with its extruder brain ─────────────────────────────────
func _step_world() -> void:
	for b in _brains:
		for key in ["_laser_filter", "_head_filter"]:
			var f = b.get(key)
			if f != null and is_instance_valid(f) and f.has_method("_physics_process"):
				f.call("_physics_process", DT)
		b.call("_on_sim_tick", DT)
	_lf.call("tick", DT)
	_t += DT
	for nd in (_lf.get("_nodes") as Array):
		var body = (nd as Dictionary).get("node", null)
		if body == null or not is_instance_valid(body):
			continue
		var bid : int = (body as Object).get_instance_id()
		_moved[bid] = float(_moved.get(bid, 0.0)) + float((nd as Dictionary).get("_moved_kg", 0.0))


func _nd(body: Node3D) -> Dictionary:
	return _lf.call("node_for_body", body)


## kg a flow node has taken: processed + still in its input buffer.
func _received(body: Node3D) -> float:
	var nd := _nd(body)
	var bin = nd.get("in", null)
	return float(_moved.get(body.get_instance_id(), 0.0)) + (float(bin.mass_kg) if bin != null else 0.0)


func _flow_body(id: String, macro: String) -> Node3D:
	for e in _lf.call("flow_bodies"):
		var b : Node3D = e["body"]
		if String(e["id"]) == id and String(b.get_meta("macro_id", "")) == macro:
			return b
	return null


func _press(brain: Node) -> void:
	(brain.get("_pending") as Dictionary)["start_production"] = true


func _part_b() -> void:
	print("  -- B. a real 3B line: BuildMode, LineFlow, the extruder brain --")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3b", Vector3.ZERO, 0.0)
	bm.call("_build_full_line", "line_3c", Vector3(400.0, 0.0, 0.0), 0.0)
	var lone : Node3D = PlaceableCatalog.build_node("extruder_3a", false)
	add_child(lone)
	lone.global_position = Vector3(800.0, 0.0, 0.0)
	# Unhook every brain from SimTick before a frame passes: they are stepped
	# by hand below, together with LineFlow.
	var st : Node = get_node("/root/SimTick")
	var b3b : Node = null
	var b3a : Node = null
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var cb := Callable(em, "_on_sim_tick")
		if st.sim_tick.is_connected(cb):
			st.sim_tick.disconnect(cb)
		var lid : String = String(em.get("config_resource").get("line_id"))
		if lid == "3B":
			b3b = em
		elif lid == "3A":
			b3a = em
	_check(b3b != null and b3a != null and b3a.get_parent() == lone,
		"B0 two extruder brains: the 3B line's and the free-built 3A's (the 3C macro's extruder_screw has none)")
	if b3b == null or b3a == null:
		return
	_brains = [b3b, b3a]
	_lf = LineFlow.new()
	add_child(_lf)
	await get_tree().process_frame
	_lf.call("rebuild")

	# Claimed at rebuild, before any brain tick.
	var nat : Dictionary = b3b.call("natraject_bodies")
	var own_ok := nat.size() == STEPS.size()
	var names : Array = []
	for id in STEPS:
		var b = nat.get(id, null)
		own_ok = own_ok and b != null and String(b.get_meta("macro_id", "")) == "line_3b" \
			and _lf.call("node_owner", b) == b3b
		names.append("%s@%s" % [id, String(b.get_meta("macro_id", "?")) if b != null else "none"])
	var ex3b : Node3D = b3b.get_parent()
	own_ok = own_ok and _lf.call("node_owner", ex3b) == b3b
	var hs3c : Node3D = _flow_body("heetafslag", "line_3c")
	_check(own_ok and hs3c != null and _lf.call("node_owner", hs3c) == null,
		"B0 right after LineFlow.rebuild the 3B brain holds its own flow node and its line's natraject %s; the 3C heetafslag has no owner"
		% str(names))
	if nat.size() != STEPS.size():
		return      # nothing below can be measured without the natraject
	var band3b : Node3D = _flow_body("compactorband", "line_3b")

	# The line's start no longer runs the extruder or its natraject.
	_lf.call("start_line")
	(_nd(ex3b)["in"] as MaterialBatch).add(MaterialBatch.new(5.0, 5.0 / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "interlock", 0.0, 0.0))
	for _i in range(int(30.0 / DT)):
		_step_world()
	var off_ok := not bool(_nd(ex3b).get("powered", true))
	var off_names : Array = []
	for id in STEPS:
		var p : bool = bool(_nd(nat[id]).get("powered", true))
		off_ok = off_ok and not p
		if p:
			off_names.append(id)
	_check(off_ok and band3b != null and bool(_nd(band3b).get("powered", false))
			and hs3c != null and bool(_nd(hs3c).get("powered", false)),
		"B1 30 s after the line's start: 3B's extruder node and natraject stay OFF %s, while its compactorband and 3C's heetafslag run"
		% (str(off_names) if not off_names.is_empty() else "(all off)"))
	_check(_received(nat["laser_filter"]) < 1e-6,
		"B1 5 kg put in the stopped 3B extruder go nowhere (laserfilter received %.3f kg)" % _received(nat["laser_filter"]))

	# The press: the natraject in order, then the screw.
	var m3b : ExtruderModel = b3b.get("model")
	var green : float = float(m3b.call("_preheat_ready_temp"))
	m3b.melt_temp = m3b.config.melt_temp_setpoint
	var seq = m3b.start_seq
	_press(b3b)
	var t0 := _t
	var on_t := {}
	var up_t := {}
	var starting_t := -1.0
	var running_t := -1.0
	var hold_ok := true
	var min_melt := INF
	var lit : Array = []
	var solid_ok := true
	for _i in range(int(45.0 / DT)):
		_step_world()
		var t := _t - t0
		lit.append(bool(seq.led_lit()))
		for id in STEPS:
			var nd := _nd(nat[id])
			if bool(nd.get("powered", false)) and not on_t.has(id):
				on_t[id] = t
			if float(nd.get("spin", 0.0)) >= SEQ.SPUN_UP and not up_t.has(id):
				up_t[id] = t
		if m3b.state == ExtruderModel.State.STARTING and starting_t < 0.0:
			starting_t = t
		if starting_t < 0.0:
			hold_ok = hold_ok and m3b.state == ExtruderModel.State.PREHEAT
			min_melt = minf(min_melt, m3b.melt_temp)
		else:
			solid_ok = solid_ok and bool(seq.led_lit())
		if m3b.state == ExtruderModel.State.RUNNING and running_t < 0.0:
			running_t = t
			break
	var order_ok := on_t.size() == STEPS.size() and up_t.size() == STEPS.size()
	for k in range(1, STEPS.size()):
		if not order_ok:
			break
		order_ok = order_ok and float(on_t[STEPS[k]]) >= float(up_t[STEPS[k - 1]])
	_check(order_ok,
		"B2 LineFlow powers them in the ruled order, each once the one before spun up: %s"
		% ", ".join(STEPS.map(func(id): return "%s on %.1f / up %.1f s" % [id, float(on_t.get(id, -1.0)), float(up_t.get(id, -1.0))])))
	_check(starting_t > 0.0 and starting_t >= float(up_t.get("laser_filter", INF)) and hold_ok and min_melt >= green,
		"B3 the screw starts at %.1f s, after the laserfilter is up; meanwhile the model holds the barrel in PREHEAT (%s), melt never under green (min %.2f, green %.3f C)"
		% [starting_t, hold_ok, min_melt, green])
	_check(lit.size() > 7 and not bool(lit[2]) and bool(lit[6]) and solid_ok,
		"B4 the ring blinks (0.3 s %s, 0.7 s %s) while the natraject comes up and is solid from the screw start (%s)"
		% [lit[2] if lit.size() > 2 else "?", lit[6] if lit.size() > 6 else "?", solid_ok])
	_check(running_t > 0.0 and absf(m3b.screw_rpm - m3b.screw_rpm_setpoint) < 1e-3
			and bool(_nd(ex3b).get("powered", false)),
		"B5 RUNNING at %.1f s at its %.0f rpm setpoint, and now its flow node runs" % [running_t, m3b.screw_rpm_setpoint])

	# Real kg through the natraject.
	var fed := 5.0
	var feed_tick : float = FEED_KG_S * DT
	for _i in range(int(60.0 / DT)):
		(_nd(ex3b)["in"] as MaterialBatch).add(MaterialBatch.new(feed_tick, feed_tick / LineFlow.FEED_DENSITY,
			LineFlow.DEFAULT_COMP.duplicate(), "interlock", 0.0, 0.0))
		fed += feed_tick
		_step_world()
	for _i in range(int(60.0 / DT)):
		_step_world()
	var silo3b : Node3D = _flow_body("voorraad_silo", "line_3b")
	var at_silo : float = _received(silo3b) if silo3b != null else 0.0
	_info("kg along the 3B natraject after 60 s feed + 60 s drain (fed %.1f kg): %s, voorraad_silo %.1f"
		% [fed, ", ".join(STEPS.map(func(id): return "%s %.1f" % [id, _received(nat[id])])), at_silo])
	_check(at_silo >= 0.5 * fed,
		"B6 the fed kg pass the running natraject into the voorraad_silo (%.1f of %.1f kg)" % [at_silo, fed])

	# A natraject machine stops under the running screw: the extruder trips.
	var cf_key : String = String(_lf.call("natraject_status", nat["centrifuge"]).get("key", ""))
	_lf.call("set_machine_hand_mode", cf_key, true)     # HAND, manual off: switched off
	var trip_t := -1.0
	var t1 := _t
	for _i in range(int(3.0 / DT)):
		_step_world()
		if m3b.state == ExtruderModel.State.FAULT:
			trip_t = _t - t1
			break
	var rows : Array = REG.detect_active(m3b, null)
	var row_ok := false
	for f in rows:
		row_ok = row_ok or (int(f["nr"]) == 4401 and String(f["msg"]) == seq.alarm)
	_check(trip_t > 0.0 and trip_t <= 0.3 and m3b.fault_reason == "natraject_stopped"
			and m3b.natraject_trip_text.contains("Centrifuge") and seq.alarm.contains("Centrifuge") and row_ok,
		"B7 the centrifuge switched off under the running screw trips 3B in %.1f s (%s, '%s'), and the HMI lists alarm 4401"
		% [trip_t, m3b.fault_reason, m3b.natraject_trip_text])

	var off_t := {}
	var down_t := {}
	var rpm_at_first_off := -1.0
	var ring_blink := false
	var t2 := _t
	for _i in range(int(40.0 / DT)):
		_step_world()
		var t := _t - t2
		ring_blink = ring_blink or seq.led() == SEQ.Led.BLINK
		for id in STEPS:
			if not bool(seq.run_cmd[id]) and not off_t.has(id):
				off_t[id] = t
				if rpm_at_first_off < 0.0:
					rpm_at_first_off = m3b.screw_rpm
			if float(_nd(nat[id]).get("spin", 1.0)) <= SEQ.SPUN_DOWN and not down_t.has(id):
				down_t[id] = t
		if seq.phase == SEQ.Phase.IDLE:
			break
	var rev : Array = STEPS.duplicate()
	rev.reverse()
	var rd_ok := off_t.size() == STEPS.size()
	for k in range(1, rev.size()):
		if not rd_ok:
			break
		rd_ok = rd_ok and float(off_t[rev[k]]) >= float(down_t.get(rev[k - 1], INF))
	_check(rpm_at_first_off >= 0.0 and rpm_at_first_off < 0.5 and rd_ok and ring_blink
			and seq.phase == SEQ.Phase.IDLE and seq.led() == SEQ.Led.OFF
			and not bool(_nd(ex3b).get("powered", true)),
		"B8 the screw stood first (%.2f rpm at the first switch-off), then %s, each once the one before stood; ring blinked, now off"
		% [rpm_at_first_off, ", ".join(rev.map(func(id): return "%s %.1f s" % [id, float(off_t.get(id, -1.0))]))])

	# The latch: the centrifuge back in AUTO, the FAULT cleared at the machine as
	# before — the button still does nothing until the HMI resets the alarm.
	_lf.call("set_machine_hand_mode", cf_key, false)
	(b3b.get("_pending") as Dictionary)["operator_clear_fault"] = true
	_step_world()
	m3b.melt_temp = m3b.config.melt_temp_setpoint
	_press(b3b)
	var any_on := false
	for _i in range(int(5.0 / DT)):
		_step_world()
		for id in STEPS:
			any_on = any_on or bool(_nd(nat[id]).get("powered", false))
	var hint : String = String(b3b.call("_interact_hint"))
	_check(m3b.state != ExtruderModel.State.STARTING and m3b.state != ExtruderModel.State.RUNNING
			and not any_on and seq.alarm != "" and hint.contains("HMI"),
		"B9 fixed, FAULT cleared, start pressed: nothing starts (%s, natraject on: %s) while the alarm stands; the machine says '%s'"
		% [m3b.get_state_name(), any_on, hint])

	# "Nothing" includes the warm-up: a cold-barrel press, which normally goes
	# to PREHEAT, does not start it either while the alarm stands.
	m3b.melt_temp = 150.0
	_press(b3b)
	_step_world()
	var cold_state : String = m3b.get_state_name()
	_check(m3b.state == ExtruderModel.State.OFF and seq.alarm != "",
		"B9 with the alarm standing a cold-barrel press does not start the warm-up either (%s)" % cold_state)
	m3b.melt_temp = m3b.config.melt_temp_setpoint

	await _part_c_hmi(b3b, b3a, nat)


# ── C. the HMI: reset where the plant resets it, and the natraject switch ─────
func _part_c_hmi(b3b: Node, b3a: Node, nat: Dictionary) -> void:
	print("  -- C. the HMI: alarm reset and the natraject switch --")
	var m3b : ExtruderModel = b3b.get("model")
	var seq = m3b.start_seq
	var ov : Node = (load("res://src/scenes/hud/HmiOverlay.tscn") as PackedScene).instantiate()
	get_tree().root.add_child(ov)
	await get_tree().process_frame
	ov.set("_line_flow", _lf)
	ov.call("open_for", "Wassen", HmiScopes.get_scope("hmi_washing_all"))
	var faults : Array = ov.call("_compute_faults")
	var row := {}
	for f in faults:
		if String(f.get("code", "")) == "EREMA-4401" and String(f.get("line", "")) == "3B":
			row = f
	ov.call("_on_reset_faults")
	var kept : bool = seq.alarm != ""
	_check(not row.is_empty() and String(row["text"]) == seq.alarm and String(row["scope"]) == "extruder_3B" and kept,
		"C1 the alarm is in the Storingstabel as EREMA-4401 on extruder_3B ('%s'); RESETTEN on the WASHING panel leaves it (%s)"
		% [String(row.get("text", "")), kept])
	ov.call("open_for", "Extruder (alle lijnen)", HmiScopes.get_scope("hmi_extruder_all"))
	ov.call("_on_reset_faults")
	var gone := true
	for f in ov.call("_compute_faults"):
		gone = gone and String(f.get("code", "")) != "EREMA-4401"
	_check(seq.alarm == "" and gone,
		"C2 RESETTEN on the extruder panel clears it, and 4401 leaves the list")
	ov.queue_free()

	# Recovery: the same press now runs the whole sequence again.
	m3b.melt_temp = m3b.config.melt_temp_setpoint
	_press(b3b)
	var back := -1.0
	var t0 := _t
	for _i in range(int(45.0 / DT)):
		_step_world()
		if m3b.state == ExtruderModel.State.RUNNING:
			back = _t - t0
			break
	_check(back > 0.0,
		"C3 after the reset the start button runs the natraject and the screw again: RUNNING %.1f s after the press" % back)

	# The touchscreen's extruder panel: ring, status, reset, switch.
	var zp = load("res://src/scenes/hud/ExtruderZonePanel.gd").new()
	add_child(zp)
	zp.call("bind", m3b)
	var lamp : Label = zp.find_child("StartRingLamp", true, false) as Label
	var stat : Label = zp.find_child("StartStatus", true, false) as Label
	var rbtn : Button = zp.find_child("StartAlarmReset", true, false) as Button
	var tog : CheckButton = zp.find_child("NatrajectToggle", true, false) as CheckButton
	zp.call("_process", 0.0)
	var solid_panel : bool = lamp != null and lamp.text == "●"
	# A refusal to reset from the panel: the heetafslag in HAND, then a start.
	b3b.get("_pending")["stop_production"] = true
	for _i in range(int(60.0 / DT)):
		_step_world()
		if seq.phase == SEQ.Phase.IDLE and m3b.state == ExtruderModel.State.OFF:
			break
	var hs_key : String = String(_lf.call("natraject_status", nat["heetafslag"]).get("key", ""))
	_lf.call("set_machine_hand_mode", hs_key, true)
	m3b.melt_temp = m3b.config.melt_temp_setpoint
	_press(b3b)
	_step_world()
	zp.call("_process", 0.0)
	var refused : String = seq.alarm
	var shown : bool = stat != null and stat.text.begins_with(refused) and rbtn != null and not rbtn.disabled
	if rbtn != null:
		rbtn.pressed.emit()
	_lf.call("set_machine_hand_mode", hs_key, false)
	_check(lamp != null and stat != null and rbtn != null and tog != null and solid_panel
			and refused == "Start geweigerd — Heetafslag: staat in HAND" and shown and seq.alarm == "" and rbtn.disabled,
		"C4 the extruder panel shows the ring (solid while running), the refusal '%s', and its ALARM RESET clears it" % refused)

	# The web HMI's line strip, on the free-built 3A with no pellet side.
	var m3a : ExtruderModel = b3a.get("model")
	var wov = load("res://src/scenes/hud/HmiWebOverlay.gd").new()
	add_child(wov)
	wov.call("open_for", "Extruder (alle lijnen)", HmiScopes.get_scope("hmi_extruder_all"))
	wov.call("select_extruder_line", "3a")
	var bar : Node = wov.get_node_or_null("ExtruderLineBar")
	var wreset : Button = bar.find_child("StartAlarmReset", true, false) as Button if bar != null else null
	var wtog : CheckButton = bar.find_child("NatrajectToggle", true, false) as CheckButton if bar != null else null
	var wstat : Label = bar.find_child("StartStatus", true, false) as Label if bar != null else null
	m3a.melt_temp = m3a.config.melt_temp_setpoint
	_press(b3a)
	_step_world()
	wov.call("_refresh_start_controls")
	var a_alarm : String = m3a.start_seq.alarm
	var a_shown : bool = wstat != null and wstat.text.begins_with(a_alarm)
	if wreset != null:
		wreset.pressed.emit()
	_check(a_alarm.begins_with("Start geweigerd") and a_alarm.contains("niet gevonden") and a_shown
			and m3a.start_seq.alarm == "" and m3a.state != ExtruderModel.State.STARTING,
		"C5 an extruder built with no pellet side refuses to start ('%s'), shown on the web HMI's strip, reset there" % a_alarm)
	if wtog != null:
		wtog.toggled.emit(false)
	m3a.melt_temp = m3a.config.melt_temp_setpoint
	_press(b3a)
	_step_world()
	var a_nat_on := false
	for id in STEPS:
		a_nat_on = a_nat_on or bool(m3a.start_seq.run_cmd[id])
	_check(wtog != null and not m3a.start_seq.natraject_enabled and m3a.state == ExtruderModel.State.STARTING
			and not a_nat_on and m3a.start_seq.alarm == "",
		"C6 natraject switched OFF on the web HMI: the same press starts the screw at once (%s), nothing else" % m3a.get_state_name())
	var zp2 = load("res://src/scenes/hud/ExtruderZonePanel.gd").new()
	add_child(zp2)
	zp2.call("bind", m3a)
	var tog2 : CheckButton = zp2.find_child("NatrajectToggle", true, false) as CheckButton
	var was_off : bool = tog2 != null and not tog2.button_pressed
	if tog2 != null:
		tog2.toggled.emit(true)
	_check(was_off and m3a.start_seq.natraject_enabled,
		"C7 the extruder panel shows 3A's natraject OFF (%s) and its switch turns it back ON (the default)" % was_off)

	zp2.queue_free()
	zp.queue_free()
	wov.queue_free()
	await get_tree().process_frame


# ── verdict ───────────────────────────────────────────────────────────────────
func _finish() -> void:
	if _done:
		return
	_done = true
	if _lf != null and is_instance_valid(_lf):
		for b in _brains:
			if b != null and is_instance_valid(b):
				_lf.call("release_nodes", b)
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 and _oks > 0 else "FAIL", _oks, _fails])
	get_tree().quit(0 if _fails == 0 and _oks > 0 else 1)
