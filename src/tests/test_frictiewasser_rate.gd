extends Node
## THE FRICTIEWASSER'S STIRRERS DO NOT SET ITS RATE — LineFlow rate-law guard.
##
##   godot --headless --path . res://src/tests/test_frictiewasser_rate.tscn
##
## Operator ruling 2026-09-26 (docs/audit/hmi_rpm_rate_2026-09-26.md §2): the
## 3A frictiewasser (`friction_washer`) is a water reservoir. Wash water flows in
## on the input side, the level rises, and the film overflows into the chute;
## the two stirrers (in SERIES, one per chamber) wash it, but do not set how fast
## it passes. So LineFlow.RATE_NOT_BY_RPM takes the stirrers' rpm AND rpm_pct out
## of its rate, and keeps only their on/off (LineFlow._mech_run_gate).
##
## Same ruling: every OTHER machine keeps today's rate law ("don't touch the
## base"), double count included, until the physical material model replaces
## it. The C checks pin that law on three neighbours, exactly as measured
## before this change (probe_hmi_speed_rate on line_3a, same audit doc §1).
##
## Before the change, measured: stirrer_1 at 0.5 -> 0.375 of the tank's rate,
## stirrer_2 at 0.5 -> 0.750, rpm_pct 0.5 -> 0.250, rpm_pct 0.25 -> 0.063.
##
## Method (as the probe): line_3a built alone through BuildMode._build_full_line,
## LineFlow.new() with set_process(false) AFTER add_child, started, 30 s empty.
## Each measurement parks 50 kg in the machine's input and sums `_moved_kg` over
## 10 ticks of 0.1 s; a ratio is against the same machine with every setting at
## 1.0, so air and the spin ramp cancel out.

const WATCHDOG_S : float = 150.0
const DT         : float = 0.1
const PARK_KG    : float = 50.0
const TOL        : float = 0.002

var _fails : int = 0
var _oks   : int = 0
var _lf : Node = null


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


func _node(id: String) -> Dictionary:
	for n in (_lf.get("_nodes") as Array):
		if String(n.get("id", "")) == id:
			return n
	return {}


func _reset(nd: Dictionary) -> void:
	var key := String(nd["key"])
	for c in (nd.get("components", {}) as Dictionary).keys():
		_lf.call("set_machine_component_pct", key, String(c), 1.0)
	_lf.call("set_machine_rpm_pct", key, 1.0)


## kg the machine moves in 1 s with PARK_KG parked in its input; the parked kg
## that is left is taken back out, so every measurement starts the same.
func _measure(nd: Dictionary) -> float:
	var bin : MaterialBatch = nd["in"] as MaterialBatch
	bin.split_mass(bin.mass_kg)
	bin.add(MaterialBatch.new(PARK_KG, PARK_KG / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "test_park", 0.0, 0.0))
	var moved := 0.0
	for _i in 10:
		_lf.call("tick", DT)
		moved += float(nd.get("_moved_kg", 0.0))
	bin.split_mass(bin.mass_kg)
	return moved


func _rotor_frac(nd: Dictionary, comp: String) -> float:
	var rot : Array = (nd.get("component_rotors", {}) as Dictionary).get(comp, [])
	if rot.is_empty() or not is_instance_valid(rot[0]):
		return -1.0
	return float(rot[0].call("commanded_rpm")) / float(rot[0].nominal_rpm)


func _run() -> void:
	print("[TEST] frictiewasser rate ignores stirrer rpm")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_3a", Vector3.ZERO, 0.0)
	await get_tree().process_frame
	_lf = LineFlow.new()
	add_child(_lf)
	_lf.set_process(false)   # the suite drives tick() itself; after add_child, as READY turns _process back on
	await get_tree().process_frame
	_lf.call("rebuild")
	_lf.call("start_line")
	for _i in int(30.0 / DT):
		_lf.call("tick", DT)

	# ── F0: fixture — the tank, its two stirrer rotors, and the rotor the old
	#    law read (anti-vacuity: without a stirrer as `mech` the double read the
	#    old law made could not show, and the S checks below would prove nothing).
	var fw := _node("friction_washer")
	_check(not fw.is_empty(), "F0 line_3a has a friction_washer flow node")
	if fw.is_empty():
		_finish(); return
	var key := String(fw["key"])
	_lf.call("_cache_component_rotors", fw)
	var cr : Dictionary = fw.get("component_rotors", {})
	_check(cr.has("stirrer_1") and cr.has("stirrer_2"),
		"F0 both stirrers are tagged rotors of their own (%s)" % str(cr.keys()))
	var mech = fw.get("mech")
	_check(mech != null and is_instance_valid(mech) and mech.has_meta("comp")
		and String(mech.get_meta("comp")).begins_with("stirrer_"),
		"F0 the rotor _mech_fraction reads is a stirrer (the old law read its rpm)")
	# Read at runtime, not as LineFlow.RATE_NOT_BY_RPM: on a LineFlow without the
	# list that would be a parse error, and a script that fails to parse leaves
	# the scene idle until the harness's timeout instead of failing here.
	var not_by_rpm : Array = (LineFlow as Script).get_script_constant_map().get("RATE_NOT_BY_RPM", [])
	_check(not_by_rpm.has("friction_washer"), "F0 friction_washer is in RATE_NOT_BY_RPM")
	_check(String(LineFlow._component_topology("friction_washer")) == "series",
		"F0 the stirrers are in SERIES, not parallel (operator 2026-09-26)")

	# ── F1: baseline, every setting at 1.0 — it must actually convey.
	_reset(fw)
	var base := _measure(fw)
	_check(base > 1.0, "F1 anti-vacuity: the frictiewasser conveys at 1.0 (%.3f kg in 1 s, rate %.2f kg/s)"
		% [base, float(fw.get("rate", 0.0))])
	if base <= 1.0:
		_finish(); return

	# ── S: its rate does not follow the stirrers, nor rpm_pct.
	var cases : Array = [
		["S1 stirrer_1 at 0.50", {"stirrer_1": 0.5}, -1.0],
		["S2 stirrer_2 at 0.50", {"stirrer_2": 0.5}, -1.0],
		["S3 both stirrers at 0.25", {"stirrer_1": 0.25, "stirrer_2": 0.25}, -1.0],
		["S4 both stirrers at 0 (the water still carries it)", {"stirrer_1": 0.0, "stirrer_2": 0.0}, -1.0],
		["S5 rpm_pct at 0.50", {}, 0.5],
		["S6 rpm_pct at 0.25", {}, 0.25],
	]
	for cs in cases:
		_reset(fw)
		var comps : Dictionary = cs[1]
		for c in comps:
			_lf.call("set_machine_component_pct", key, String(c), float(comps[c]))
		if float(cs[2]) >= 0.0:
			_lf.call("set_machine_rpm_pct", key, float(cs[2]))
		var r := _measure(fw) / base
		_check(absf(r - 1.0) <= TOL, "%s: conveys %.3f of its 1.0 rate (want 1.000; before the ruling it followed the stirrer)" % [cs[0], r])

	# ── R: the stirrers themselves still follow their sliders (the HMI's rpm
	#    readout and the machine's sound read them): the rate ignores them, the
	#    rotors do not.
	_reset(fw)
	_lf.call("set_machine_component_pct", key, "stirrer_1", 0.5)
	var f1 := _rotor_frac(fw, "stirrer_1")
	var f2 := _rotor_frac(fw, "stirrer_2")
	_check(absf(f1 - 0.5) <= 1.0e-4 and absf(f2 - 1.0) <= 1.0e-4,
		"R1 stirrer_1's rotor is commanded to 0.50 of nominal, stirrer_2's to 1.00 (%.3f / %.3f)" % [f1, f2])
	_check(absf(float(_lf.call("_mech_fraction", fw)) - 0.5) <= 1.0e-4,
		"R2 _mech_fraction still reads the stirrer's speed for the sound (%.3f)" % float(_lf.call("_mech_fraction", fw)))
	_reset(fw)

	# ── G: switched off, it stops at once and keeps what it holds; switched back
	#    on, it runs again. HAND with AAN/UIT off is the HMI's own off switch.
	var bin : MaterialBatch = fw["in"] as MaterialBatch
	bin.split_mass(bin.mass_kg)
	bin.add(MaterialBatch.new(PARK_KG, PARK_KG / LineFlow.FEED_DENSITY,
		LineFlow.DEFAULT_COMP.duplicate(), "test_park", 0.0, 0.0))
	_lf.call("set_machine_hand_mode", key, true)
	_lf.call("tick", DT)
	var first := float(fw.get("_moved_kg", 0.0))
	var off_moved := first
	for _i in 9:
		_lf.call("tick", DT)
		off_moved += float(fw.get("_moved_kg", 0.0))
	_check(not bool(fw["powered"]), "G1 HAND + AAN/UIT off: powered false")
	_check(first == 0.0, "G2 the first tick switched off moves nothing (%.4f kg; the spin is still %.2f)"
		% [first, float(fw["spin"])])
	_check(off_moved == 0.0 and absf(bin.mass_kg - PARK_KG) <= 1.0e-6,
		"G3 1 s switched off: 0 kg moved, the %.0f kg stay in its input (moved %.4f, holds %.3f)"
		% [PARK_KG, off_moved, bin.mass_kg])
	_lf.call("set_machine_hand_mode", key, false)
	var on_moved := 0.0
	for _i in 40:
		_lf.call("tick", DT)
		on_moved += float(fw.get("_moved_kg", 0.0))
	_check(on_moved > 1.0, "G4 back in AUTO it conveys again (%.3f kg in 4 s)" % on_moved)
	bin.split_mass(bin.mass_kg)

	# ── C: the base law is untouched on every other machine (operator
	#    2026-09-26, "don't touch the base"). Values as measured before this
	#    change; a change here needs his ruling first (audit doc §1).
	var controls : Array = [
		["C1 blower (1 untagged rotor), rpm_pct 0.50", "blower", "", 0.5, 0.250],
		["C2 blower, MACHINES-screen drive slider 0.50", "blower", "drive", 0.5, 0.125],
		["C3 transport_screw (no rotor), rpm_pct 0.50", "transport_screw", "", 0.5, 0.500],
		["C4 friction_sep (no rotor, not the frictiewasser), rpm_pct 0.50", "friction_sep", "", 0.5, 0.500],
	]
	for ct in controls:
		var nd := _node(String(ct[1]))
		if nd.is_empty():
			_check(false, "%s: no %s on line_3a" % [ct[0], ct[1]])
			continue
		_reset(nd)
		var b := _measure(nd)
		if String(ct[2]) == "":
			_lf.call("set_machine_rpm_pct", String(nd["key"]), float(ct[3]))
		else:
			_lf.call("set_machine_component_pct", String(nd["key"]), String(ct[2]), float(ct[3]))
		var r := _measure(nd) / b if b > 0.0 else -1.0
		_check(absf(r - float(ct[4])) <= TOL, "%s: conveys %.3f of its 1.0 rate (base law: %.3f)" % [ct[0], r, float(ct[4])])
		_reset(nd)
	_finish()


func _finish() -> void:
	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] frictiewasser rate %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
