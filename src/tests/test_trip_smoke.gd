extends Node
## TRIP SMOKE (P2's second half, 2026-09-23) — a packed-up drive sometimes
## smokes, heavily, at its motor, and the crew are told.
##
##   godot --headless --path . res://src/tests/test_trip_smoke.tscn
##
## Operator 2026-09-23 (rulings §5): "Visible smoke sometimes" — "Heavy smoke,
## people react". Built as: on a MotorOverload trip edge, with probability
## LineFlow.smoke_chance, the machine's SmokePlume (installed on demand at the
## motor housing) emits for SMOKE_S seconds and a SMOKE alarm goes out; the
## CrewManager radios and dispatches on it.
##
## Fixture: one real friction separator (a high-load drive with a MotorOverload
## relay) as a LineFlow node. The chance is forced to 1 and to 0 — a suite must
## not roll dice. A GPUParticles3D exists headless as a node (nothing renders);
## its emitting flag, position and lifetime are what is asserted.

const WATCHDOG_S := 200.0
const TICK_S := 0.1

var _fails := 0
var _oks := 0
var _alarms : Array = []

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
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _on_alarm(id: String, code: String, sev: int) -> void:
	_alarms.append({"id": id, "code": code, "sev": sev})

func _smoke_alarms() -> int:
	var n := 0
	for a in _alarms:
		if String(a["code"]) == "SMOKE":
			n += 1
	return n

func _motor_global(body: Node3D) -> Vector3:
	if body.has_meta("motor_pos_local"):
		return body.to_global(body.get_meta("motor_pos_local"))
	for c in body.find_children("*", "", true, false):
		if c is Node3D and c.has_meta("motor_pos_local"):
			return (c as Node3D).to_global(c.get_meta("motor_pos_local"))
	return Vector3(NAN, NAN, NAN)

func _run() -> void:
	print("[TEST] trip smoke — P2 second half")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("machine_alarm_raised"):
		bus.connect("machine_alarm_raised", _on_alarm)
	var body : Node3D = PlaceableCatalog.build_node("friction_sep", false)
	_check(body != null, "F1 catalog built a friction separator")
	if body == null:
		_finish(); return
	add_child(body)
	body.global_position = Vector3(12.0, 0.0, -4.0)   # off the origin so a position check means something
	await get_tree().process_frame
	var motor_g := _motor_global(body)
	_check(not is_nan(motor_g.x), "F1 its builder left a motor anchor (motor_pos_local) at %s" % str(motor_g))
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.set("feed_enabled", false)
	lf.call("rebuild")
	await get_tree().process_frame
	var nodes : Array = lf.get("_nodes")
	var nd : Dictionary = {}
	for n in nodes:
		if String(n.get("id", "")) == "friction_sep":
			nd = n
	_check(not nd.is_empty(), "F1 LineFlow discovered it")
	if nd.is_empty():
		_finish(); return
	var mol = nd.get("mol")
	_check(mol != null, "F1 it carries a MotorOverload relay")
	if mol == null:
		_finish(); return
	_check(body.find_child("SmokePlume", true, false) == null, "F1 no plume exists before any trip (nothing invented from nothing)")
	lf.call("start_line")
	for _t in 40:
		lf.tick(TICK_S)
	_check(float(nd["spin"]) >= 0.99, "F1 up to speed (spin %.2f)" % float(nd["spin"]))
	# ── chance 1: a trip smokes ──
	lf.set("smoke_chance", 1.0)
	mol.call("force_trip")
	lf.tick(TICK_S)
	lf.tick(TICK_S)
	var plume := body.find_child("SmokePlume", true, false) as GPUParticles3D
	_check(plume != null, "S1 a SmokePlume was installed on the trip edge")
	if plume == null:
		_finish(); return
	_check(plume.emitting, "S1 it is emitting")
	_check(plume.is_in_group("smoke_plume") and not plume.is_in_group("steam_plume"), "S1 tagged smoke_plume, not steam")
	var d_motor : float = plume.global_position.distance_to(motor_g)
	_check(d_motor < 0.05, "S1 the plume sits on the motor housing (%.3f m from the anchor)" % d_motor)
	_check(plume.amount >= 120, "S1 heavy: %d puffs (the steam plume has 80)" % plume.amount)
	_check(_smoke_alarms() == 1 and String(_alarms[_alarms.size() - 1]["id"]) == "friction_sep", "S1 one SMOKE alarm went out for it")
	_check(bool(lf.call("is_smoking", "friction_sep")), "S1 is_smoking() reads true")
	_check(not bool(nd["powered"]), "S1 the trip still stops the drive (powered=false)")
	# ── it runs for SMOKE_S then stops ──
	var ticks_needed : int = int(ceil(LineFlow.SMOKE_S / TICK_S))
	var still_on_at_half := false
	for t in ticks_needed + 5:
		lf.tick(TICK_S)
		if t == ticks_needed / 2 and plume.emitting:
			still_on_at_half = true
	_check(still_on_at_half, "S2 still smoking halfway through SMOKE_S")
	_check(not plume.emitting and not bool(lf.call("is_smoking", "friction_sep")), "S2 stops emitting after SMOKE_S = %.0f s" % LineFlow.SMOKE_S)
	# ── chance 0: a second trip does not smoke ──
	mol.call("reset")
	lf.set("smoke_chance", 0.0)
	for _t in 40:
		lf.tick(TICK_S)
	_check(bool(nd["powered"]) and float(nd["spin"]) > 0.9, "S3 reset and back up to speed for the second trip (spin %.2f)" % float(nd["spin"]))
	var alarms_before : int = _smoke_alarms()
	mol.call("force_trip")
	lf.tick(TICK_S)
	lf.tick(TICK_S)
	_check(not plume.emitting and _smoke_alarms() == alarms_before, "S3 with the chance at 0 the trip does not smoke (no plume, no alarm)")
	var plumes := 0
	for c in body.find_children("SmokePlume", "", true, false):
		plumes += 1
	_check(plumes == 1, "S3 the plume node is reused, not stacked (%d)" % plumes)
	# ── chance 1 again: the edge fires again after a reset ──
	mol.call("reset")
	lf.set("smoke_chance", 1.0)
	for _t in 40:
		lf.tick(TICK_S)
	mol.call("force_trip")
	lf.tick(TICK_S)
	_check(plume.emitting and _smoke_alarms() == alarms_before + 1, "S4 a third trip smokes again (edge re-armed by the reset)")
	# ── the crew react ──
	var cm : Node = load("res://src/scenes/world/CrewManager.gd").new()
	cm.set("line_flow", lf)
	cm.call("_on_machine_alarm", "friction_sep", "SMOKE", 3)
	cm.call("_on_machine_alarm", "friction_sep", "BUF-300", 2)
	var seen : Array = cm.get("smoke_alarms")
	_check(seen.size() == 1 and String(seen[0]) == "friction_sep", "C1 the crew log the SMOKE alarm and ignore the others (%s)" % str(seen))
	cm.free()
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
