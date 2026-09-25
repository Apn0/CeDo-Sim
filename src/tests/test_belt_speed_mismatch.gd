extends Node
## BELT SPEED MISMATCH (round 8, 2026-09-24) — the operator's gameplay: "a belt
## fed faster than it runs heaps up → chute blockage → overload trip", with
## the HMI speed setting as the lever.
##
##   godot --headless --path . res://src/tests/test_belt_speed_mismatch.tscn
##
## Real line 1 (BuildMode._build_full_line + LineFlow), the head feed off, a
## charge injected into the uitvoerband's buffer every tick (it throws onto a
## transport belt; two transport belts until 2026-09-25), the
## SECOND belt slowed with set_machine_rpm_pct (what the HMI slider calls):
##   D — its deck runs slower (the bed field's speed follows the setting)
##   H — the excess packs the transfer chute first (rulings §21 "both, in
##       that order"); the overflow beyond it stands as a heap (FloorPile,
##       mirroring the kg) at the slow belt's infeed; the heap is not a reject
##       catch
##   T — the UPSTREAM belt's drive (pushing into the packed chute) climbs past
##       its trip current and trips after 3 s: MOTOR-OVERLOAD on the bus, it
##       stops, its bed holds; the slow belt itself does not trip
##   A — anti-vacuity: the same feed at full speed never trips
##   R — RESETTEN (reset_trip) on the tripped drive clears it; at full speed
##       the backlog drains and the heap goes

const WATCHDOG_S := 300.0
const INJECT_KGPS := 3.0

var _fails := 0
var _oks := 0
var _alarms : Dictionary = {}
var _cleared : Dictionary = {}
var _recv2 : float = 0.0

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
		bus.machine_alarm_raised.connect(func(m: String, a: String, _s: int) -> void:
			_alarms[m + "/" + a] = int(_alarms.get(m + "/" + a, 0)) + 1)
		bus.machine_alarm_cleared.connect(func(m: String, a: String) -> void:
			_cleared[m + "/" + a] = int(_cleared.get(m + "/" + a, 0)) + 1)
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _run() -> void:
	print("[TEST] belt speed mismatch — round 8")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.set("feed_enabled", false)
	lf.call("start_line")
	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	# Two belts in series with a transfer between them: since 2026-09-25 line
	# 1's uitvoerband (under shredder 1) throws onto the transport belt that
	# feeds the drum. Until then these were two transport_belts.
	var b1 := -1
	var b2 := -1
	for i in nodes.size():
		if String(nodes[i].get("id", "")) == "uitvoerband_1":
			b1 = i
	for e in edges:
		if int(e["a"]) == b1 and String(nodes[int(e["b"])].get("id", "")) == "transport_belt":
			b2 = int(e["b"])
	var linked := false
	for e in edges:
		if int(e["a"]) == b1 and int(e["b"]) == b2:
			linked = true
	_check(b1 >= 0 and b2 >= 0 and linked, "F1 the uitvoerband feeds a transport belt on line 1 (#%d → #%d)" % [b1, b2])
	if not linked:
		_finish(); return
	var n1 : Dictionary = nodes[b1]
	var n2 : Dictionary = nodes[b2]
	var v2 = n2.get("view")
	_check(v2 != null and bool(v2.get("belt_mode")), "F1 the second belt has a belt-mode bed field")
	var mol2 = n2.get("mol")
	var mol1 = n1.get("mol")
	_check(mol2 != null and float(mol2.get("load_capacity_kg")) > 10.0,
		"F2 the second belt's drive carries a MotorOverload sized to its deck (%.0f kg)" % (float(mol2.get("load_capacity_kg")) if mol2 != null else -1.0))
	_check(mol1 != null and float(mol1.get("load_capacity_kg")) > 10.0,
		"F2 …and so does the first (%.0f kg)" % (float(mol1.get("load_capacity_kg")) if mol1 != null else -1.0))
	var key2 := String(n2.get("key", ""))
	# wait for the PLC to power the belts up
	var t := 0
	while t < 400 and (float(n1["spin"]) < 0.99 or float(n2["spin"]) < 0.99):
		lf.call("tick", 0.1)
		t += 1
	_check(float(n1["spin"]) >= 0.99 and float(n2["spin"]) >= 0.99, "F3 both belts at full spin after %.1f s" % (t * 0.1))
	var base_speed : float = float(v2.call("belt_speed_mps"))
	# ── A anti-vacuity: full speed, the same charge, no trip ──
	var bin1 : MaterialBatch = n1.get("in")
	var bin2 : MaterialBatch = n2.get("in")
	for i in 900:
		bin1.add(MaterialBatch.new(INJECT_KGPS * 0.1, INJECT_KGPS * 0.1 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
		var b2_before : float = bin2.mass_kg
		lf.call("tick", 0.1)
		_recv2 += bin2.mass_kg - b2_before + float(n2.get("_moved_kg", 0.0))
		if i % 100 == 99:
			print("  info  : t=%3d s belt2 received %.2f kg/s over the last 10 s (bin %.1f) | belt1 thru %.2f | transit %.1f" % [
				(i + 1) / 10, _recv2 / 10.0, bin2.mass_kg, float(n1["thru"]), float(lf.call("in_transit_mass"))])
			_recv2 = 0.0
		if i % 150 == 0:
			print("  info  : A t=%3d s belt1 thru %.2f backlog %.1f | belt2 thru %.2f backlog %.1f powered %s spin %.2f amps %.1f tripped %s estop '%s'" % [
				i / 10, float(n1["thru"]), float(n1.get("_backlog_kg", 0.0)), float(n2["thru"]), float(n2.get("_backlog_kg", 0.0)),
				str(n2["powered"]), float(n2["spin"]), float(mol2.get("current_amps")), str(mol2.call("is_tripped")), String(lf.call("estop_fault_id"))])
	_check(not bool(mol2.call("is_tripped")) and not bool(mol1.call("is_tripped")) and float(n2.get("_backlog_kg", 0.0)) < 20.0,
		"A1 at full speed 90 s of %.1f kg/s trips neither belt (belt 2 backlog %.1f kg)" % [INJECT_KGPS, float(n2.get("_backlog_kg", 0.0))])
	_check(float(lf.call("belt_heap_kg", key2)) == 0.0, "A1 …and no heap stands at its infeed")
	# ── D the HMI slider: slow the second belt to 25 % ──
	lf.call("set_machine_rpm_pct", key2, 0.25)
	for i in 30:
		bin1.add(MaterialBatch.new(INJECT_KGPS * 0.1, INJECT_KGPS * 0.1 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
		lf.call("tick", 0.1)
	var slow_speed : float = float(v2.call("belt_speed_mps"))
	_check(absf(slow_speed / maxf(base_speed, 1e-6) - 0.25) < 0.03,
		"D1 the deck runs at the setting: %.3f m/s vs %.3f at 100 %% (ratio %.2f)" % [slow_speed, base_speed, slow_speed / maxf(base_speed, 1e-6)])
	# ── H the chute packs, T the upstream drive trips ──
	var t_pack := -1.0
	var t_trip := -1.0
	var amps_max := 0.0
	var tt := 0
	while tt < 3000 and t_trip < 0.0:
		bin1.add(MaterialBatch.new(INJECT_KGPS * 0.1, INJECT_KGPS * 0.1 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
		lf.call("tick", 0.1)
		tt += 1
		amps_max = maxf(amps_max, float(mol1.get("current_amps")))
		if t_pack < 0.0 and float(lf.call("_packed_chute_kg_out_of", n1)) > 0.0:
			t_pack = tt * 0.1
		if bool(mol1.call("is_tripped")):
			t_trip = tt * 0.1
	var excess_at_trip : float = float(lf.call("_belt_excess_kg", n2))
	print("  info  : chute packing from %.1f s, upstream trip at %.1f s with belt-2 excess %.0f kg (chute holds %.0f), max %.0f A on belt 1 (threshold %.0f A)" % [t_pack, t_trip, excess_at_trip, LineFlow.CHUTE_PACK_KG, amps_max, float(mol1.get("trip_threshold"))])
	_check(t_pack > 0.0 and t_trip > t_pack, "H1 the transfer chute packs FIRST (%.1f s); the drive pushing into it trips after (%.1f s)" % [t_pack, t_trip])
	_check(t_trip > 0.0 and not bool(mol2.call("is_tripped")), "T1 the UPSTREAM belt's drive tripped; the slow belt itself did not")
	_check(int(_alarms.get(String(n1["id"]) + "/MOTOR-OVERLOAD", 0)) >= 1, "T1 MOTOR-OVERLOAD on the bus for the belt (%d)" % int(_alarms.get(String(n1["id"]) + "/MOTOR-OVERLOAD", 0)))
	_check(float(lf.call("belt_heap_kg", key2)) == 0.0, "H1 no spill yet: the trip stopped the feed before the overflow (%.0f kg excess, chute %.0f)" % [excess_at_trip, LineFlow.CHUTE_PACK_KG])
	# ── H2 reset WITHOUT fixing the speed: the overflow spills, the drive re-trips ──
	var key1 := String(n1.get("key", ""))
	_check(bool(lf.call("reset_trip", key1)), "H2 RESETTEN on the tripped drive (speed still at 25 %%)")
	var t_heap := -1.0
	var t_retrip := -1.0
	var heap_kg := 0.0
	var excess_at_heap := 0.0
	var t2 := 0
	while t2 < 900 and (t_heap < 0.0 or t_retrip < 0.0):
		bin1.add(MaterialBatch.new(INJECT_KGPS * 0.1, INJECT_KGPS * 0.1 / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(), "test_inject", 0.0, 0.0))
		lf.call("tick", 0.1)
		t2 += 1
		if t_heap < 0.0 and float(lf.call("belt_heap_kg", key2)) > 0.0:
			t_heap = t2 * 0.1
			heap_kg = float(lf.call("belt_heap_kg", key2))
			excess_at_heap = float(lf.call("_belt_excess_kg", n2))
		if t_retrip < 0.0 and bool(mol1.call("is_tripped")):
			t_retrip = t2 * 0.1
	print("  info  : after the reset — heap from %.1f s (%.0f kg spilled, excess %.0f), re-trip at %.1f s" % [t_heap, heap_kg, excess_at_heap, t_retrip])
	_check(t_heap > 0.0, "H2 fed on at the wrong speed, the overflow beyond the packed chute SPILLS as a heap at the slow belt's infeed (%.1f s after the reset)" % t_heap)
	_check(absf(heap_kg - maxf(excess_at_heap - LineFlow.CHUTE_PACK_KG, 0.0)) < 1e-3 and heap_kg > 0.0,
		"H2 the heap is the overflow beyond the chute: %.0f kg = excess %.0f − chute %.0f" % [heap_kg, excess_at_heap, LineFlow.CHUTE_PACK_KG])
	var pile_ok := false
	for pl in get_tree().get_nodes_in_group("floor_pile"):
		if pl.name == "BeltHeap" and pl.has_meta("mirror_kg"):
			pile_ok = true
	_check(pile_ok, "H2 the heap is a FloorPile named BeltHeap marked as a mirror (never a reject catch)")
	_check(t_retrip > 0.0, "T1 …and the drive trips AGAIN %.1f s after a reset that did not fix the speed" % t_retrip)
	# the tripped belt stops (the spin runs down over a few seconds) and THEN its
	# bed holds — the bed keeps slewing while the deck is still coasting.
	var v1 = n1.get("view")
	for i in 60:
		lf.call("tick", 0.1)
	_check(float(n1["spin"]) < 0.1 and not bool(n1["powered"]), "T2 the tripped upstream belt is unpowered and its spin ran down (%.2f)" % float(n1["spin"]))
	var bed_stopped : float = float(v1.call("bed_kg_per_m"))
	for i in 60:
		lf.call("tick", 0.1)
	_check(absf(float(v1.call("bed_kg_per_m")) - bed_stopped) < 1e-6 and float(v1.call("belt_speed_mps")) == 0.0,
		"T2 its bed holds what was on it once stopped (%.2f kg/m over 6 s, deck 0 m/s)" % bed_stopped)
	# ── R RESETTEN at full speed: the trip clears, the backlog drains, the heap goes ──
	lf.call("set_machine_rpm_pct", key2, 1.0)
	_check(bool(lf.call("reset_trip", key1)), "R1 RESETTEN resets the tripped upstream drive")
	_check(int(_cleared.get(String(n1["id"]) + "/MOTOR-OVERLOAD", 0)) >= 1, "R1 …and the alarm clears on the bus")
	var drained := false
	var td := 0
	while td < 3000 and not drained:
		lf.call("tick", 0.1)
		td += 1
		drained = float(lf.call("belt_heap_kg", key2)) == 0.0 and float(n2.get("_backlog_kg", 0.0)) < 5.0
	_check(float(n1["spin"]) >= 0.99 and float(n2["spin"]) >= 0.99, "R2 both belts run again at full speed (spin %.2f / %.2f)" % [float(n1["spin"]), float(n2["spin"])])
	_check(drained, "R2 the backlog drained and the heap is gone after %.1f s" % (td * 0.1))
	_check(not bool(mol1.call("is_tripped")) and not bool(mol2.call("is_tripped")), "R2 no re-trip at full speed")
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	await get_tree().process_frame
	get_tree().quit(0 if _fails == 0 else 1)
