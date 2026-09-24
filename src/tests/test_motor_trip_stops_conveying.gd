extends Node
## MOTOR-OVERLOAD TRIP MUST STOP THE DRIVE — LineFlow tick-order guard.
##
##   godot --headless --path . res://src/tests/test_motor_trip_stops_conveying.tscn
##
## Places the real "line_sort" macro (BuildMode._build_full_line), runs the real
## LineFlow.tick(), puts material in shredder-2's and the bunker's input buffers,
## and force-trips shredder-2's MotorOverload (its documented owner-facing API).
##
## What it measures, per tick, straight off the node dicts LineFlow itself keeps:
##   _moved_kg  — kg that left the machine's input buffer this tick
##   spin       — the 0..1 rotor ramp the conveying rate is gated by
##   powered    — the run state the mechanisms and the HMI read
## plus every RotatingMechanism's commanded_rpm() on the tripped node.
##
## Why it exists (measured 2026-09-23, before the fix): LineFlow's tick order is
## _tick_plc_power_downstream → _tick_feed → _tick_process_machines →
## _tick_advanced_systems → _tick_bunker_shredder2_interlock. The PLC step wrote
## powered=true on every started node and ran the rotor/mechanism ramp from it;
## the trip check in _tick_advanced_systems flipped powered=false AFTER the
## conveying split had already run at full rate. Next tick the PLC wrote true
## again. So a tripped drive kept conveying at its full design rate, its rotors
## kept spinning, and the only trace of the trip was 0 A on the telemetry and
## the alarm — the "stop conveying (conserving)" comment at the trip site was
## not what happened. The bunker/shredder-2 interlock lost its effect the same
## way. The fix applies latched trips inside the PLC step, before the ramp.
##
## Anti-vacuity: S2 asserts both machines were actually moving material BEFORE
## the trip; a fixture that never conveys cannot pass.

const WATCHDOG_S : float = 150.0   # SCRIPT ERROR inside _run() → idle forever; this prints a verdict instead
const TICK_S     : float = 0.1
const TRIP_TICKS : int   = 30      # 3.0 s — past SPIN_UP_S (2.5 s) so spin can reach 0

var _fails : int = 0
var _oks   : int = 0

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

func _node_index_by_macro(nodes: Array, macro_index: int) -> int:
	for i in nodes.size():
		var node3d = (nodes[i] as Dictionary).get("node")
		if node3d == null or not is_instance_valid(node3d) or not (node3d as Node3D).has_meta("macro_index"):
			continue
		if int((node3d as Node3D).get_meta("macro_index")) == macro_index:
			return i
	return -1

func _node_index_by_id(nodes: Array, id: String) -> int:
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) == id:
			return i
	return -1

func _inject(nd: Dictionary, kg: float) -> void:
	var bin : MaterialBatch = nd.get("in", null) as MaterialBatch
	bin.add(MaterialBatch.new(kg, kg / LineFlow.FEED_DENSITY, LineFlow.DEFAULT_COMP.duplicate(),
		"test_inject", 0.0, 0.0))

func _max_commanded_rpm(nd: Dictionary) -> float:
	var top := -1.0
	for m in nd.get("mechs", []):
		if m != null and is_instance_valid(m) and m.has_method("commanded_rpm"):
			top = maxf(top, float(m.call("commanded_rpm")))
	var single = nd.get("mech")
	if single != null and is_instance_valid(single) and single.has_method("commanded_rpm"):
		top = maxf(top, float(single.call("commanded_rpm")))
	return top

func _run() -> void:
	print("[TEST] motor-overload trip stops conveying")

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
	_check(nodes.size() > 15, "line_sort placed a real node graph (%d nodes)" % nodes.size())

	var bunker_i    := _node_index_by_macro(nodes, LineFlow._SORT_BUNKER_IDX)
	var outfeed_i   := _node_index_by_macro(nodes, LineFlow._SORT_BUNKER_OUT_IDX)
	var shredder2_i := _node_index_by_macro(nodes, LineFlow._SORT_SHREDDER2_IDX)
	var titech_i    := _node_index_by_id(nodes, "titech_sort")
	_check(bunker_i >= 0, "bunker found (macro_index %d)" % LineFlow._SORT_BUNKER_IDX)
	_check(outfeed_i >= 0, "bunker outfeed belt found (macro_index %d)" % LineFlow._SORT_BUNKER_OUT_IDX)
	_check(shredder2_i >= 0, "shredder-2 found (macro_index %d)" % LineFlow._SORT_SHREDDER2_IDX)
	_check(titech_i >= 0, "a TITECH sorter found (id titech_sort)")
	if bunker_i < 0 or outfeed_i < 0 or shredder2_i < 0 or titech_i < 0:
		_finish(); return

	var s2 : Dictionary = nodes[shredder2_i]
	var bk : Dictionary = nodes[bunker_i]
	var mol = s2.get("mol")
	_check(mol != null, "shredder-2 carries a MotorOverload (mol) component")
	if mol == null:
		_finish(); return

	# ── S1: real PLC start, fully powered up (cap ~20 s, LineFlow.TARGET_STARTUP_S) ──
	lf.call("start_line")
	for _i in 260:
		lf.call("tick", TICK_S)
	_check(bool(s2["powered"]) and bool(bk["powered"]), "S1 shredder-2 + bunker powered after line start")
	_check(float(s2["spin"]) >= 0.99, "S1 shredder-2 spin at full (%.2f)" % float(s2["spin"]))

	# ── S2: material in both input buffers, both machines genuinely conveying ──
	# Sized off the node's own design rate, kept under OVERLOAD_KG (250) so the
	# buffer e-stop cannot fire and confuse the trip measurement.
	var s2_kg := clampf(float(s2.get("rate", 1.0)) * 40.0, 60.0, 200.0)
	var bk_kg := clampf(float(bk.get("rate", 1.0)) * 40.0, 60.0, 200.0)
	_inject(s2, s2_kg)
	_inject(bk, bk_kg)
	# Injection bypasses the feed ledger, so the residual is -(s2_kg + bk_kg) from
	# here on; what conservation means below is that it does not MOVE again.
	var residual_0 : float = float(lf.call("ledger_residual"))
	var moved_pre_s2 := 0.0
	var moved_pre_bk := 0.0
	for _i in 5:
		lf.call("tick", TICK_S)
		moved_pre_s2 += float(s2.get("_moved_kg", 0.0))
		moved_pre_bk += float(bk.get("_moved_kg", 0.0))
	_check(moved_pre_s2 > 0.0, "S2 anti-vacuity: shredder-2 conveys before the trip (%.3f kg in 0.5 s, rate %.2f kg/s)"
		% [moved_pre_s2, float(s2.get("rate", 0.0))])
	_check(moved_pre_bk > 0.0, "S2 anti-vacuity: bunker conveys before the trip (%.3f kg in 0.5 s)" % moved_pre_bk)

	# ── S3: force the trip (MotorOverload's documented owner-facing API) ──
	mol.call("force_trip")
	_check(bool(mol.call("is_tripped")), "S3 MOL reports tripped after force_trip()")
	var buf_at_trip : float = (s2["in"] as MaterialBatch).mass_kg

	lf.call("tick", TICK_S)
	var first_tick_moved_s2 := float(s2.get("_moved_kg", 0.0))
	var first_tick_moved_bk := float(bk.get("_moved_kg", 0.0))
	_check(first_tick_moved_s2 == 0.0,
		"S3 first tick after the trip: shredder-2 moves NOTHING (moved %.4f kg)" % first_tick_moved_s2)
	_check(first_tick_moved_bk == 0.0,
		"S3 first tick after the trip: bunker moves NOTHING — interlock (moved %.4f kg)" % first_tick_moved_bk)

	var moved_trip_s2 := first_tick_moved_s2
	var moved_trip_bk := first_tick_moved_bk
	var moved_trip_of := 0.0
	for _i in TRIP_TICKS:
		lf.call("tick", TICK_S)
		moved_trip_s2 += float(s2.get("_moved_kg", 0.0))
		moved_trip_bk += float(bk.get("_moved_kg", 0.0))
		moved_trip_of += float(nodes[outfeed_i].get("_moved_kg", 0.0))
	_check(moved_trip_s2 == 0.0, "S3 %.1f s tripped: shredder-2 conveyed 0 kg (got %.3f kg)"
		% [(TRIP_TICKS + 1) * TICK_S, moved_trip_s2])
	_check(moved_trip_bk == 0.0, "S3 %.1f s tripped: bunker conveyed 0 kg — interlock (got %.3f kg)"
		% [(TRIP_TICKS + 1) * TICK_S, moved_trip_bk])
	_check(float(s2["spin"]) <= 0.01, "S3 shredder-2 rotor spin decayed to 0 (%.3f)" % float(s2["spin"]))
	_check(float(bk["spin"]) <= 0.01, "S3 bunker spin decayed to 0 — interlock (%.3f)" % float(bk["spin"]))
	_check(not bool(s2["powered"]), "S3 shredder-2 powered == false while tripped")
	_check(float(s2.get("amps", -1.0)) == 0.0, "S3 shredder-2 reads 0 A while tripped (%.1f A)" % float(s2.get("amps", -1.0)))
	var rpm_cmd := _max_commanded_rpm(s2)
	if rpm_cmd < 0.0:
		print("  note  : shredder-2 has no RotatingMechanism child in this fixture — rpm check not evaluated")
	else:
		_check(rpm_cmd == 0.0, "S3 every mechanism on shredder-2 is commanded to 0 rpm (max %.1f)" % rpm_cmd)
	var buf_after : float = (s2["in"] as MaterialBatch).mass_kg
	_check(absf(buf_after - buf_at_trip) < 1.0e-6,
		"S3 shredder-2 input buffer untouched while tripped — conserving (%.3f → %.3f kg)" % [buf_at_trip, buf_after])
	_check(bool(nodes[titech_i]["powered"]), "S3 TITECH keeps running (downstream, unaffected)")
	_check(float(nodes[titech_i]["spin"]) >= 0.99, "S3 TITECH spin stays at full (%.2f)" % float(nodes[titech_i]["spin"]))

	# ── S4: reset → PLC run command wins again, rotor ramps back, conveying resumes ──
	mol.call("reset", true)
	var moved_post_s2 := 0.0
	var moved_post_bk := 0.0
	for _i in 40:   # 4.0 s: past SPIN_UP_S so spin is back at 1.0
		lf.call("tick", TICK_S)
		moved_post_s2 += float(s2.get("_moved_kg", 0.0))
		moved_post_bk += float(bk.get("_moved_kg", 0.0))
	_check(bool(s2["powered"]), "S4 shredder-2 re-powered after reset")
	_check(float(s2["spin"]) >= 0.99, "S4 shredder-2 spin back at full (%.2f)" % float(s2["spin"]))
	_check(moved_post_s2 > 0.0, "S4 shredder-2 conveys again after reset (%.3f kg in 4 s)" % moved_post_s2)
	_check(bool(bk["powered"]) and moved_post_bk > 0.0,
		"S4 bunker re-powered and conveying again — interlock released (%.3f kg in 4 s)" % moved_post_bk)
	var residual_1 : float = float(lf.call("ledger_residual"))
	_check(absf(residual_1 - residual_0) < 1.0e-3,
		"mass ledger unchanged across trip + reset (residual %.3f → %.3f kg, injected %.1f kg bypasses the feed counter)"
			% [residual_0, residual_1, s2_kg + bk_kg])
	print("  info  : outfeed belt moved %.3f kg while shredder-2 was tripped" % moved_trip_of)
	_finish()

func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] motor-overload trip stops conveying %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
