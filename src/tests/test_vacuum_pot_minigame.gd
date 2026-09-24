extends Node
## VACUUM POT CLEANING MINI-GAME (P3 stage B, 2026-09-24, rulings §14) — the
## operator's sequence on a REAL catalog extruder with its SimBrain, driven
## headless through VacuumPotService (the same calls VacuumPotInteract makes
## for E / hold-E), never through input events.
##
##   godot --headless --path . res://src/tests/test_vacuum_pot_minigame.tscn
##
## A — the alarm: a full primary pot pushes its lid → VACUUM_ALARM naming the
##     pot; the old hold-E "restore vacuum" is REFUSED while the pot is full.
## L — the lid: only the full pot's lid can be pulled; the pull integrates and
##     completes; the required time grows with the minutes since the alarm;
##     letting go springs it back; the lid is parked, a MeltBlock of the pot's
##     kg appears inside.
## P — the planes: a push into a cell gains depth; a second push with the tool
##     still in is refused; pull out, push again; every plane at ≥ 90 % frees
##     the block, which drops 1 cm.
## B — the block: taken out → the model's pot is empty; its kg go into a lump
##     cart whole.
## R — the lid back within the window → vacuum_restored → RUNNING, alarm
##     cleared on the bus. Then the lapse: a second full pot, 125 s untouched
##     → FAULT with the laser-filter alarm; the lid is stickier (elapsed
##     counts through FAULT); it can still be pulled and cleaned in FAULT.
## G — the pot's crosshair body exists on the built extruder; prompts read
##     right at each stage without a player.

# The service by PATH, not class_name: a fresh class_name is unknown to a
# standalone headless run until the editor (or the harness import step)
# rebuilds the global class cache — measured 2026-09-24 (this suite idled).
const VPS := preload("res://src/scenes/interactions/VacuumPotService.gd")
const EXTRUDER_ID := "extruder_3a"
const WATCHDOG_S := 240.0

var _fails := 0
var _oks := 0
var _alarms : Dictionary = {}       # alarm id → raised count
var _cleared : Dictionary = {}

class CartStub extends Node:
	var got : float = 0.0
	func receive_lump(kg: float) -> float:
		got += kg
		return 0.0

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
			_alarms[a] = int(_alarms.get(a, 0)) + 1)
		bus.machine_alarm_cleared.connect(func(_m: String, a: String) -> void:
			_cleared[a] = int(_cleared.get(a, 0)) + 1)
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame

func _run() -> void:
	print("[TEST] vacuum pot cleaning mini-game — rulings §14")
	var body : Node3D = PlaceableCatalog.build_node(EXTRUDER_ID, false)
	add_child(body)
	await _frames(3)
	var brain : Node = null
	for m in get_tree().get_nodes_in_group("extruder_machine"):
		if m.get_parent() == body:
			brain = m
	var model = brain.get("model") if brain != null else null
	_check(brain != null and model != null, "G0 the catalog extruder carries its SimBrain and model")
	if model == null:
		_finish(); return
	var primary : Node3D = body.find_child("VacPot_primary", true, false)
	var secondary : Node3D = body.find_child("VacPot_secondary", true, false)
	var svc : Node = primary.get_node_or_null("PotService") if primary != null else null
	_check(primary != null and secondary != null and svc != null and svc is StaticBody3D and svc.has_method("crosshair_hold_tick"),
		"G1 each pot has a PotService crosshair body (hold-E capable)")
	var svc_col := svc.get_child(0) if svc != null else null
	_check(svc_col is CollisionShape3D, "G1 the pot body has a collision shape for the crosshair ray")
	var lid : Node3D = primary.get_node("Lid")
	var lid_home : Vector3 = lid.get_meta("lid_home")
	_check(bool(lid.get_meta("lid_side", false)) and lid_home.x > float(primary.get_meta("dome_r")) and absf(lid.rotation.z - PI * 0.5) < 1e-4,
		"G1 the lid is on the pot's FRONT face (+X), a vertical disc — rulings §20 (lid at x %.2f, dome r %.2f)" % [lid_home.x, float(primary.get_meta("dome_r"))])
	var cap : float = ExtruderModel.VACUUM_POT_CAPACITY_KG
	# ── A the alarm ──
	model.state = ExtruderModel.State.RUNNING
	model.primary_pot_fill_kg = cap
	model.secondary_pot_fill_kg = cap * 0.3
	brain.call("_on_sim_tick", 0.1)
	_check(model.state == ExtruderModel.State.VACUUM_ALARM and String(model.vacuum_alarm_pot) == "primary",
		"A1 the full primary pot pushed its lid: VACUUM_ALARM names 'primary' (got %s, pot '%s')" % [model.get_state_name(), model.vacuum_alarm_pot])
	_check(int(_alarms.get("vacuum", 0)) == 1, "A1 one 'vacuum' alarm on the bus")
	brain.get("_pending")["vacuum_restored"] = true
	var ev : Array = model.call("tick", 0.1, {"vacuum_restored": true})
	_check(model.state == ExtruderModel.State.VACUUM_ALARM and ev.has("vacuum_restore_refused_pot_full"),
		"A2 the hold-E 'restore vacuum' is refused while the pot is full (event %s)" % str(ev))
	brain.get("_pending").clear()
	await _frames(2)
	_check(String(svc.call("crosshair_prompt", null)).begins_with("Hold E: pull the primary pot's lid off"),
		"G2 the pot prompt asks for the lid pull: '%s'" % String(svc.call("crosshair_prompt", null)))
	# ── L the lid ──
	_check(VPS.can_pull_lid(model, primary) and not VPS.can_pull_lid(model, secondary),
		"L1 only the FULL pot's lid can be pulled (secondary at 30 %% cannot)")
	var need0 : float = VPS.lid_pull_required_s(model)
	var saved_elapsed : float = model.vacuum_alarm_elapsed_s
	model.vacuum_alarm_elapsed_s = 300.0
	var need5 : float = VPS.lid_pull_required_s(model)
	model.vacuum_alarm_elapsed_s = saved_elapsed
	_check(need5 > need0 + 4.0, "L2 the lid sticks harder with time: %.1f s at the alarm, %.1f s five minutes in" % [need0, need5])
	var p1 : float = VPS.tick_lid_pull(model, primary, 0.5)
	VPS.cancel_lid_pull(primary)
	var st := VPS.state(primary)
	_check(p1 > 0.1 and p1 < 1.0 and float(st["pull"]) == 0.0 and not bool(st["lid_off"]),
		"L3 letting go of a half-pulled lid springs it back (was at %.0f %%)" % (100.0 * p1))
	var pulled := 0.0
	var pulls := 0
	while pulled < 1.0 and pulls < 400:
		pulled = VPS.tick_lid_pull(model, primary, 0.1)
		brain.call("_on_sim_tick", 0.1)
		pulls += 1
	_check(pulled >= 1.0 and bool(VPS.state(primary)["lid_off"]) and bool(primary.get_meta("lid_off", false)),
		"L4 the lid came off after %.1f s of pulling (required %.1f s)" % [pulls * 0.1, need0])
	await _frames(2)
	_check(lid.position.distance_to(lid_home) > 0.05 and absf(lid.rotation.z - PI * 0.5) > 0.5,
		"L4 the lid is parked under the opening and the driver leaves it there (%.2f m from its seat)" % lid.position.distance_to(lid_home))
	var block : Node = VPS.state(primary)["block"]
	_check(block != null and block.get_parent() == primary and absf(float(block.get("kg")) - cap) < 1e-6,
		"L5 a MeltBlock of the pot's %.0f kg sits inside the open pot" % cap)
	var centre : Vector3 = primary.get_meta("pot_centre")
	_check(block != null and (block as Node3D).position.x > centre.x + 0.02,
		"L5 …in the opening on the front face, proud of it (x %.3f vs centre %.3f)" % [(block as Node3D).position.x, centre.x])
	var block_before : Vector3 = (block as Node3D).position
	# ── P the planes ──
	var first := VPS.next_cell(primary)
	var r1 : Dictionary = VPS.push(model, primary, String(first[0]), int(first[1]))
	_check(bool(r1["ok"]) and float(r1["gained"]) > 0.2 and float(r1["gained"]) <= 1.0,
		"P1 a push into %s/%d gains %.0f %% (soft melt just after the alarm)" % [first[0], int(first[1]), 100.0 * float(r1["gained"])])
	var r2 : Dictionary = VPS.push(model, primary, String(first[0]), int(first[1]))
	_check(not bool(r2["ok"]) and String(r2["why"]).begins_with("pull the tool out"),
		"P2 a second push with the tool still in is refused: '%s'" % String(r2["why"]))
	_check(VPS.pull_out(primary) and not VPS.pull_out(primary), "P2 pull out, then there is nothing to pull out")
	var pushes := 1
	var freed := false
	while not freed and pushes < 200:
		var nc := VPS.next_cell(primary)
		if String(nc[0]) == "":
			break
		var r : Dictionary = VPS.push(model, primary, String(nc[0]), int(nc[1]))
		pushes += 1
		freed = bool(r["released"])
		VPS.pull_out(primary)
	var pp := VPS.plane_progress(primary)
	print("  info  : P planes after %d pushes — top %.2f bottom %.2f left %.2f right %.2f" % [pushes, pp["top"], pp["bottom"], pp["left"], pp["right"]])
	_check(freed and VPS.all_planes_clear(primary), "P3 every plane ≥ 90 %% after %d pushes: the block is FREE" % pushes)
	var shift : Vector3 = (block as Node3D).position - block_before
	_check(shift.distance_to(Vector3(0.01, -0.01, 0.0)) < 1e-4 and bool(block.get("free")),
		"P4 the freed block dropped 1 cm down and 1 cm out towards the operator (shift %s)" % str(shift))
	_check(String(svc.call("crosshair_prompt", null)).begins_with("E: take the melt block out"),
		"G3 the prompt now offers the block: '%s'" % String(svc.call("crosshair_prompt", null)))
	# ── B the block ──
	var taken : Node = VPS.take_block(primary, brain)
	_check(taken == block and taken.get_parent() != primary and String(brain.get("_pending").get("pot_emptied", "")) == "primary",
		"B1 taking the block lifts it out of the pot and tells the model the pot is empty")
	var ev2 : Array = brain.get("model").call("tick", 0.1, brain.get("_pending").duplicate())
	brain.get("_pending").clear()
	# < 0.01, not == 0: the alarm tick's degassing pass condenses micrograms of
	# backflush into the pot every tick (that is the model, not a leak).
	_check(model.primary_pot_fill_kg < 0.01 and ev2.has("pot_emptied:primary"), "B2 the model's primary pot is empty (%.4f kg; event pot_emptied:primary)" % model.primary_pot_fill_kg)
	var cart := CartStub.new()
	add_child(cart)
	var got : float = float(taken.call("dump_into", cart))
	_check(absf(got - cap) < 1e-6 and absf(cart.got - cap) < 1e-6, "B3 the block's %.0f kg go into the lump cart whole (mass conserved)" % cap)
	await _frames(1)
	# ── R the lid back, in time ──
	_check(VPS.can_relid(primary) and String(svc.call("crosshair_prompt", null)).begins_with("E: put the primary pot's lid back"),
		"R1 with the block gone the prompt offers the lid")
	_check(VPS.relid(primary, brain) and bool(brain.get("_pending").get("vacuum_restored", false)),
		"R1 the lid seats and vacuum_restored is requested")
	var elapsed_before : float = model.vacuum_alarm_elapsed_s
	brain.call("_on_sim_tick", 0.1)
	_check(model.state == ExtruderModel.State.RUNNING and int(_cleared.get("vacuum", 0)) == 1,
		"R2 within the window (%.1f s since the alarm): RUNNING again, 'vacuum' cleared on the bus" % elapsed_before)
	await _frames(2)
	_check(lid.position.distance_to(lid_home) < 1e-4 and absf(lid.rotation.z - PI * 0.5) < 1e-4 and not bool(primary.get_meta("lid_off", false)),
		"R2 the lid sits back on its seat and the driver owns it again")
	# ── R the lapse ──
	model.primary_pot_fill_kg = cap
	brain.call("_on_sim_tick", 0.1)
	_check(model.state == ExtruderModel.State.VACUUM_ALARM, "R3 a full pot again → VACUUM_ALARM")
	for i in 1250:
		model.call("tick", 0.1, {})
	_check(model.state == ExtruderModel.State.FAULT, "R4 125 s untouched → the cascade shut the line down (FAULT)")
	# the model was ticked directly above, so the brain never saw the FAULT
	# transition: hand it the event it would have broadcast (typed array —
	# _broadcast takes Array[String]).
	var evs : Array[String] = ["state_changed:%d:%d" % [ExtruderModel.State.VACUUM_ALARM, ExtruderModel.State.FAULT]]
	brain.call("_broadcast", evs)
	_check(int(_alarms.get("fault", 0)) >= 1 and int(_alarms.get("laserfilter_error", 0)) >= 1 and int(_alarms.get("headfilter_error", 0)) == 0,
		"R4 the bus carries 'fault' AND 'laserfilter_error' (the primary pot is the laser filter's), no head-filter alarm")
	_check(model.vacuum_alarm_elapsed_s > 124.0 and VPS.lid_pull_required_s(model) > need0 + 1.9,
		"R5 elapsed keeps counting into FAULT (%.0f s): the lid now needs %.1f s" % [model.vacuum_alarm_elapsed_s, VPS.lid_pull_required_s(model)])
	_check(VPS.can_pull_lid(model, primary), "R5 the pot can still be cleaned in FAULT")
	var pulls2 := 0
	while VPS.tick_lid_pull(model, primary, 0.1) < 1.0 and pulls2 < 400:
		pulls2 += 1
	while not VPS.block_free(primary) and pushes < 600:
		var nc2 := VPS.next_cell(primary)
		if String(nc2[0]) == "":
			break
		VPS.push(model, primary, String(nc2[0]), int(nc2[1]))
		VPS.pull_out(primary)
		pushes += 1
	var blk2 : Node = VPS.take_block(primary, brain)
	VPS.relid(primary, brain)
	var ev3 : Array = model.call("tick", 0.1, brain.get("_pending").duplicate())
	brain.get("_pending").clear()
	_check(blk2 != null and model.primary_pot_fill_kg < 0.01 and model.state == ExtruderModel.State.FAULT,
		"R6 cleaned and re-lidded in FAULT: pot empty, but the line stays FAULT until the operator clears it (%s)" % str(ev3))
	var ev4 : Array = model.call("tick", 0.1, {"operator_clear_fault": true})
	_check(model.state != ExtruderModel.State.FAULT, "R6 operator_clear_fault then takes it out of FAULT (%s → %s)" % [str(ev4), model.get_state_name()])
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
