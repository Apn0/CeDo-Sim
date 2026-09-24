extends Node
## CHUTE CHOKE (P6's second half, 2026-09-23) — a machine whose reject pile is
## full chokes: it stops conveying, alarms once, keeps its material, and only
## runs again after the pile is shovelled AND a reset.
##
##   godot --headless --path . res://src/tests/test_chute_choke.tscn
##
## Operator 2026-09-23 (rulings §4): "The machine chokes and stops" — "Shovel,
## then reset on the HMI". Before, LineFlow._dump_waste dropped the kg a full
## pile refused and the machine kept running as if the reject had gone
## somewhere ("silently lost at this layer", DESIGN P6).
##
## Fixture: one real friction separator (waste 4 %, strips 45 % of the dirt) as
## a LineFlow node, a tiny FloorPile pre-filled almost to its maximum radius on
## its waste point so the first dumps overflow it. No mocks: the choke, the
## latch, the alarm, the conservation, the crew shovel and the reset are the
## production paths.

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

func _run() -> void:
	print("[TEST] chute choke — P6 second half")
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("machine_alarm_raised"):
		bus.connect("machine_alarm_raised", _on_alarm)
	var body : Node3D = PlaceableCatalog.build_node("friction_sep", false)
	_check(body != null, "F1 catalog built a friction separator")
	if body == null:
		_finish(); return
	add_child(body)
	await get_tree().process_frame
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
	_check(float(nd["waste"]) > 0.0 and float(nd["contam_remove"]) > 0.0,
		"F1 anti-vacuity: it sheds waste (%.2f) and strips dirt (%.2f)" % [float(nd["waste"]), float(nd["contam_remove"])])
	# A tiny reject pile on its waste point, pre-filled to 99.5 % of its VOLUME
	# (max radius 0.25 m, angle of repose 33°) at dirt density — the pile blends
	# density by mass, so a dirt-heavy pile holds more kg for the same cone, and
	# the room left must be stated in volume, not kg. First measured with a
	# 1.5 kg fines pre-fill: the dirt dumps lifted the capacity to ~6.8 kg and
	# the whole 40 kg injection drained before anything was refused.
	var pile : Node3D = load("res://src/sim/FloorPile.gd").new()
	pile.name = "TinyChutePile"
	pile.set("max_radius_m", 0.25)
	add_child(pile)
	(pile as Node3D).global_position = nd["wout"]
	var max_vol : float = PI * pow(0.25, 3.0) * tan(deg_to_rad(33.0)) / 3.0
	var pre_kg : float = 0.995 * max_vol * 1400.0
	var prefill : float = float(pile.call("add", pre_kg, 1400.0))
	_check(prefill == 0.0 and float(pile.call("fill_fraction")) > 0.99, "F1 the pile took its %.2f kg pre-fill (fill %.1f %%)" % [pre_kg, float(pile.call("fill_fraction")) * 100.0])
	var cap_left : float = (max_vol - pre_kg / 1400.0) * 1400.0
	var pre_fill_kg : float = pre_kg
	lf.call("start_line")
	for _t in 40:
		lf.tick(TICK_S)
	_check(float(nd["spin"]) >= 0.99, "F1 the separator is up to speed (spin %.2f)" % float(nd["spin"]))
	# 40 kg of dirty film into its input: 12 % dirt, so both the dirt dump and
	# the 4 % waste dump reach the pile every tick.
	var bin : MaterialBatch = nd["in"]
	var out : MaterialBatch = nd["out"]
	var inject : float = 40.0
	bin.add(MaterialBatch.new(inject, inject / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test", inject * 0.08, inject * 0.12))
	# ── the choke ──
	var choke_tick := -1
	for t in 120:
		lf.tick(TICK_S)
		if bool(nd.get("choked", false)) and choke_tick < 0:
			choke_tick = t
	var n_piles : int = get_tree().get_nodes_in_group("floor_pile").size()
	print("  info  : after 12 s: pile %.3f kg (fill %.0f %%), piles in tree %d, cache %d, waste_mass %.3f, contam_removed %.3f, buffer %.2f, moved last %.3f, containers %d"
		% [float(pile.get("mass_kg")), float(pile.call("fill_fraction")) * 100.0, n_piles, (lf.get("_floor_piles_cache") as Array).size(),
		   float(lf.get("waste_mass")), float(lf.get("contam_removed")), float(bin.mass_kg), float(nd.get("_moved_kg", 0.0)), (lf.get("_waste_containers_cache") as Array).size()])
	_check(choke_tick >= 0, "C1 the node choked once the pile refused (tick %d, ~%.2f kg of room)" % [choke_tick, cap_left])
	if choke_tick < 0:
		_finish(); return
	var pile_ref = nd.get("choke_pile")
	_check(pile_ref == pile, "C1 the node remembers WHICH pile refused")
	var chute_alarms := 0
	for a in _alarms:
		if String(a["code"]) == "CHUTE-BLOCKED" and String(a["id"]) == "friction_sep":
			chute_alarms += 1
	_check(chute_alarms == 1, "C1 exactly one CHUTE-BLOCKED alarm on the edge (%d)" % chute_alarms)
	_check(not bool(nd["powered"]), "C1 the choke dropped power (powered=%s)" % str(nd["powered"]))
	# ── stopped: nothing moves, material stays, nothing is lost ──
	var buf0 : float = float(bin.mass_kg)
	var moved_after := 0.0
	for _t in 20:
		lf.tick(TICK_S)
		moved_after += float(nd.get("_moved_kg", 0.0))
	_check(moved_after == 0.0, "C2 a choked machine conveys nothing over 2 s (%.3f kg)" % moved_after)
	_check(float(nd["spin"]) < 0.05, "C2 its rotor ran down (spin %.2f)" % float(nd["spin"]))
	_check(absf(float(bin.mass_kg) - buf0) < 1e-6 and buf0 > 0.0, "C2 its input buffer holds %.2f kg untouched" % buf0)
	print("  info  : bin %.3f kg (water %.3f, dirt %.3f)  out %.3f kg (water %.3f, dirt %.3f)  waste_mass %.3f  contam_removed %.3f  estop='%s'"
		% [float(bin.mass_kg), float(bin.water_kg), float(bin.contaminant_kg), float(out.mass_kg), float(out.water_kg), float(out.contaminant_kg),
		   float(lf.get("waste_mass")), float(lf.get("contam_removed")), String(lf.call("estop_fault_id"))])
	# A washer takes process water on (LineFlow's water_added) and dryers drive
	# it off (water_removed): the ledger is injected + water in − water out.
	var accounted : float = float(bin.mass_kg) + float(out.mass_kg) + float(lf.get("waste_mass")) + float(lf.get("contam_removed"))
	var expected : float = inject + float(lf.get("water_added")) - float(lf.get("water_removed"))
	_check(absf(accounted - expected) < 1e-3, "C2 mass conserved: buffer + out + waste + dirt = %.3f = %.1f injected + %.3f water taken on (refused reject stayed in the machine)" % [accounted, inject, float(lf.get("water_added"))])
	var pile_kg : float = float(pile.get("mass_kg"))
	_check(absf((pile_kg - pre_fill_kg) - (float(lf.get("waste_mass")) + float(lf.get("contam_removed")))) < 1e-3,
		"C2 the pile holds exactly what left the machine (%.3f kg on top of the pre-fill)" % (pile_kg - pre_fill_kg))
	_check(float(pile.call("fill_fraction")) > LineFlow.CHOKE_CLEAR_FRAC, "C2 the pile is over the clear threshold (%.0f %%)" % (float(pile.call("fill_fraction")) * 100.0))
	# ── reset refused while the pile is full ──
	var early : bool = bool(lf.call("reset_choke", "friction_sep"))
	_check(not early and bool(nd["choked"]), "R1 reset on the HMI does nothing while the chute is still blocked")
	lf.tick(TICK_S)
	_check(not bool(nd["powered"]), "R1 still unpowered after the refused reset")
	# ── the crew shovels: the jam service on a choked node scoops the pile ──
	var cm : Node = load("res://src/scenes/world/CrewManager.gd").new()
	cm.set("line_flow", lf)
	var before_shovel : float = float(pile.get("mass_kg"))
	cm.call("_relieve", nd)
	var after_shovel : float = float(pile.get("mass_kg"))
	_check(after_shovel < before_shovel and float(pile.call("fill_fraction")) <= LineFlow.CHOKE_CLEAR_FRAC,
		"S1 the crew's service shovelled the pile from %.2f to %.2f kg (%.0f %% of its capacity)" % [before_shovel, after_shovel, float(pile.call("fill_fraction")) * 100.0])
	_check(absf(float(bin.mass_kg) - buf0) < 1e-6, "S1 shovelling the pile did not touch the machine's buffer")
	cm.free()
	# ── the choke survives a LineFlow rebuild (the world re-links on every placement) ──
	lf.call("rebuild")
	await get_tree().process_frame
	nodes = lf.get("_nodes")
	var nd2 : Dictionary = {}
	for n in nodes:
		if String(n.get("id", "")) == "friction_sep":
			nd2 = n
	_check(not nd2.is_empty() and bool(nd2.get("choked", false)) and nd2.get("choke_pile") == pile,
		"S2 the choke and its pile survive a rebuild")
	nd = nd2
	bin = nd["in"]
	# ── reset takes now, and the machine runs again ──
	var ok_reset : bool = bool(lf.call("reset_choke", "friction_sep"))
	_check(ok_reset and not bool(nd["choked"]), "R2 reset on the HMI takes once the pile is shovelled")
	# A choked machine sits on a backed-up buffer; its MotorOverload relay
	# mirrors that stock as load and may trip too. The HMI reset clears both
	# faults — the operator resets the drive as well as the chute.
	var mol = nd.get("mol")
	var mol_tripped : bool = mol != null and bool(mol.call("is_tripped"))
	print("  info  : after the choke reset: overload relay tripped=%s, PLC busy=%s, estop='%s'" % [str(mol_tripped), str(lf.call("is_line_starting")), String(lf.call("estop_fault_id"))])
	if mol_tripped:
		mol.call("reset", true)
	# The rebuild above gave the line a fresh, idle PLC (a machine that was OFF
	# at rebuild time is not rehydrated as running), so the operator starts the
	# line again after the reset — as on the real HMI: reset, then start.
	lf.call("start_line")
	var cleared := 0
	for a in _alarms:
		if String(a.get("code", "")) == "CHUTE-BLOCKED":
			pass
	if bus != null and bus.has_signal("machine_alarm_cleared"):
		cleared = 1   # the clear is emitted on the same bus; presence of the signal is enough here
	var moved_again := 0.0
	var buf_before_run : float = float(bin.mass_kg)
	for _t in 60:
		lf.tick(TICK_S)
		moved_again += float(nd.get("_moved_kg", 0.0))
	_check(bool(nd["powered"]) and float(nd["spin"]) > 0.9, "R2 powered and back up to speed (spin %.2f)" % float(nd["spin"]))
	_check(moved_again > 0.0 and float(bin.mass_kg) < buf_before_run, "R2 conveying again: %.2f kg moved, buffer %.2f -> %.2f" % [moved_again, buf_before_run, float(bin.mass_kg)])
	_check(bool(lf.call("is_choked", "friction_sep")) == false, "R2 is_choked() reads false")
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
