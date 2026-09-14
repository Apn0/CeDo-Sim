extends Node
## Task #44 — headless verification of the Cutter-Compactor thermo sim.
##
## Follows the pattern of repo-root test_settings_wiring.gd: runs in _ready, prints a
## pass/fail summary, and quits with code 0 (all pass) / 1 (any fail).
##
## Run it either way:
##   godot --headless --path . res://src/tests/test_cutter_compactor.tscn
##   godot --headless --path . --main-scene res://src/tests/test_cutter_compactor.tscn
##
## CutterCompactor is a pure RefCounted (no scene-tree dependency for its core), so we
## drive tick(delta) with FIXED deltas for deterministic sim time — the same approach
## ExtruderModel/LineFlow tests use. We assert all three temperature BANDS the spec
## calls out (underheat fill-drop, 100-105 °C max throughput, >110 °C Donut stall),
## that the stall zeroes rpm + spikes to locked-rotor amps, the EventBus alarm fires,
## reset() behaviour, and that mass is conserved through the pot.

const CutterCompactorScript = preload("res://src/sim/CutterCompactor.gd")

var _fail := 0
var _pass := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _section(title: String) -> void:
	print("\n[%s]" % title)

## Drive the sim forward `seconds` at a fixed 10 Hz tick (SimTick cadence).
func _run_for(cc, seconds: float, dt: float = 0.1) -> void:
	var steps := int(round(seconds / dt))
	for _i in steps:
		cc.tick(dt)

func _ready() -> void:
	print("=== Cutter-Compactor thermodynamics verification (Task #44) ===")

	_test_constants_and_init()
	_test_underheat_band()
	_test_sweet_spot_band()
	_test_donut_stall()
	_test_eventbus_signal()
	_test_reset_behaviour()
	_test_mass_conservation()
	_test_fill_efficiency_curve()

	_finish()

# ── 0. Static band thresholds + cold-start state ──────────────────────────────
func _test_constants_and_init() -> void:
	_section("init + band thresholds")
	var cc = CutterCompactorScript.new("cutter_compactor")
	_ok(abs(cc.pot_temperature - cc.AMBIENT_C) < 0.001, "pot starts at ambient (%.1f °C)" % cc.pot_temperature)
	_ok(cc.state == cc.State.OFF, "starts in OFF state")
	_ok(cc.motor_amps == 0.0, "motor draws 0 A at rest")
	_ok(cc.is_stalled() == false, "not stalled at start")
	# The spec's literal band edges.
	_ok(cc.T_UNDERHEAT == 90.0, "underheat threshold = 90 °C")
	_ok(cc.T_SWEET_LOW == 100.0 and cc.T_SWEET_HIGH == 105.0, "sweet spot band = 100–105 °C")
	_ok(cc.T_DONUT == 110.0, "Donut threshold = 110 °C")

# ── 1. BAND A: below 90 °C → screw_fill_efficiency drops ──────────────────────
func _test_underheat_band() -> void:
	_section("BAND <90 °C — screw fill efficiency drops")
	var cc = CutterCompactorScript.new()
	# A cold pot, briefly nudged: stays well under 90 °C.
	cc.start(800.0, 0.5)     # modest rpm + half gate → slow warm-up
	_run_for(cc, 2.0)        # 2 s — nowhere near 90 °C yet
	_ok(cc.pot_temperature < cc.T_UNDERHEAT, "pot still underheated (%.1f °C < 90)" % cc.pot_temperature)
	_ok(cc.screw_fill_efficiency < 1.0, "fill efficiency reduced while cold (%.2f < 1.0)" % cc.screw_fill_efficiency)
	_ok(cc.state == cc.State.HEATING, "state is HEATING below the sweet spot")
	# Direct band check: efficiency at 70 °C must be < efficiency at 100 °C.
	var eff_cold : float = CutterCompactorScript._fill_efficiency_for(70.0)
	var eff_hot  : float = CutterCompactorScript._fill_efficiency_for(100.0)
	_ok(eff_cold < eff_hot, "fill_eff(70°C)=%.2f < fill_eff(100°C)=%.2f" % [eff_cold, eff_hot])
	_ok(eff_hot == 1.0, "fill_eff(100°C) == 1.0 (top of band)")

# ── 2. BAND B: 100–105 °C → max throughput (fill efficiency == 1.0) ───────────
func _test_sweet_spot_band() -> void:
	_section("BAND 100–105 °C — maximum throughput")
	# Pure-band assertions on the efficiency curve (deterministic, no integration).
	_ok(CutterCompactorScript._fill_efficiency_for(100.0) == 1.0, "fill_eff(100°C) == 1.0")
	_ok(CutterCompactorScript._fill_efficiency_for(102.5) == 1.0, "fill_eff(102.5°C) == 1.0 (mid sweet spot)")
	_ok(CutterCompactorScript._fill_efficiency_for(105.0) == 1.0, "fill_eff(105°C) == 1.0")
	# Just outside the band the efficiency must come OFF its max.
	_ok(CutterCompactorScript._fill_efficiency_for(107.0) < 1.0, "fill_eff(107°C) < 1.0 (past sweet spot)")
	_ok(CutterCompactorScript._fill_efficiency_for(95.0) < 1.0, "fill_eff(95°C) < 1.0 (approaching)")

	# Integration check: park the pot IN the band and confirm full fill + a positive
	# discharge (max throughput) while it stays there.
	var cc = CutterCompactorScript.new()
	cc.pot_temperature = 102.0
	cc.start(cc.NOMINAL_RPM, 1.0)
	cc.feed(_flake(40.0))
	cc.tick(0.1)
	_ok(cc.pot_temperature >= 100.0 and cc.pot_temperature <= 106.0,
		"pot held in/near sweet spot after a tick (%.1f °C)" % cc.pot_temperature)
	_ok(cc.screw_fill_efficiency == 1.0, "screw_fill_efficiency == 1.0 in the sweet spot")
	var out := cc.discharge(0.1)
	_ok(out.mass_kg > 0.0, "discharges densified crumb at max throughput (%.2f kg)" % out.mass_kg)

# ── 3. BAND C: above 110 °C → DONUT stall (rpm→0, amps→locked-rotor) ──────────
func _test_donut_stall() -> void:
	_section("BAND >110 °C — DONUT stall")
	var cc = CutterCompactorScript.new()
	cc.pot_temperature = 109.5     # poised just under the trip
	cc.start(cc.NOMINAL_RPM, 1.0)
	cc.disc_rpm = cc.NOMINAL_RPM   # pre-spun (skip the ramp dip) so the rpm² friction
	# on a near-full pot drives it cleanly over 110 °C → Donut.
	cc.feed(_flake(55.0))
	var tripped := false
	for _i in range(200):          # up to 20 s — plenty to cross 110 °C
		cc.tick(0.1)
		if cc.is_stalled():
			tripped = true
			break
	_ok(tripped, "pot crossed 110 °C and tripped the Donut stall")
	_ok(cc.state == cc.State.DONUT_STALL, "state == DONUT_STALL")
	_ok(cc.pot_temperature > cc.T_DONUT, "trip happened above 110 °C (%.1f °C)" % cc.pot_temperature)
	# The signature failure mode: instant 0 rpm + locked-rotor current spike.
	_ok(cc.disc_rpm == 0.0, "disc RPM instantly dropped to 0 on stall")
	_ok(abs(cc.motor_amps - cc.LOCKED_ROTOR_AMPS) < 0.001,
		"motor load spiked to locked-rotor amps (%.0f A)" % cc.motor_amps)
	_ok(cc.motor_amps > cc.MOTOR_FULL_AMPS * 3.0, "locked-rotor amps >> normal full-load amps")
	_ok(cc.throughput_kg_s == 0.0, "throughput is 0 while stalled")
	# Latches: ticking on stays stalled with rpm pinned at 0.
	cc.tick(0.1)
	_ok(cc.is_stalled() and cc.disc_rpm == 0.0, "Donut stall latches (still 0 rpm next tick)")

# ── 4. EventBus alarm broadcast on stall ──────────────────────────────────────
func _test_eventbus_signal() -> void:
	_section("EventBus + direct signal on stall")
	var cc = CutterCompactorScript.new("cc_test")
	# Direct signal hook (single-statement lambdas stored in vars — the proven style
	# from test_settings_wiring.gd, avoids any multi-line-lambda parser fragility).
	var seen := {"direct": false, "amps": 0.0}
	var on_stall := func(_id, _t, a):
		seen["direct"] = true
		seen["amps"] = a
	cc.donut_stall_triggered.connect(on_stall)
	# EventBus hook (autoload present when booted via the .tscn through the project).
	var bus := get_node_or_null("/root/EventBus")
	var bus_seen := {"hit": false, "id": ""}
	if bus != null and bus.has_signal("machine_alarm_raised"):
		var on_bus := func(mid, aid, _sev):
			if aid == "DONUT-STALL":
				bus_seen["hit"] = true
				bus_seen["id"] = mid
		bus.machine_alarm_raised.connect(on_bus)
	# Force the trip.
	cc.pot_temperature = 111.0
	cc.start(cc.NOMINAL_RPM, 1.0)
	cc.tick(0.1)
	_ok(cc.is_stalled(), "forced stall for signal test")
	_ok(seen["direct"], "donut_stall_triggered signal emitted directly")
	_ok(abs(seen["amps"] - cc.LOCKED_ROTOR_AMPS) < 0.001, "signal carried locked-rotor amps")
	if bus != null and bus.has_signal("machine_alarm_raised"):
		_ok(bus_seen["hit"], "EventBus.machine_alarm_raised fired with DONUT-STALL")
		_ok(bus_seen["id"] == "cc_test", "EventBus alarm carried the machine id")
	else:
		print("  skip : EventBus autoload not present (run via .tscn for this check)")

# ── 5. reset() — only takes once the pot has cooled below the reset band ───────
func _test_reset_behaviour() -> void:
	_section("reset() gating")
	var cc = CutterCompactorScript.new()
	cc.pot_temperature = 112.0
	cc.start(cc.NOMINAL_RPM, 1.0)
	cc.tick(0.1)
	_ok(cc.is_stalled(), "stalled for reset test")
	# A hot pot refuses to reset.
	_ok(cc.reset() == false, "reset() refused while pot still hot (>80 °C)")
	_ok(cc.is_stalled(), "still stalled after refused reset")
	# Cool it (no rpm, no friction) until below the reset band, then reset takes.
	cc.stop()
	_run_for(cc, 600.0)        # 10 min sim time — passively cools toward ambient
	_ok(cc.pot_temperature < cc.T_RESET_BELOW, "pot cooled below reset band (%.1f °C)" % cc.pot_temperature)
	_ok(cc.reset() == true, "reset() succeeds once cool")
	_ok(cc.state == cc.State.OFF, "machine back to OFF after reset")
	_ok(cc.is_stalled() == false, "no longer stalled after reset")

	# Softstarter trip recovery: budget & breaker flags cleared
	cc.pot_temperature = 50.0
	cc.softstarter_budget_kws = cc.POWER_KW_SOFTSTARTER_BUDGET_KWS + 10.0
	cc.softstarter_tripped = true
	cc.breaker_tripped = true
	cc._set_state(cc.State.DONUT_STALL)
	_ok(cc.reset() == true, "reset() clears softstarter trip on cooled pot")
	_ok(cc.softstarter_tripped == false, "softstarter_tripped cleared")
	_ok(cc.breaker_tripped == false, "breaker_tripped cleared")
	_ok(cc.softstarter_budget_kws == 0.0, "softstarter budget reset to 0")

# ── 6. Mass conservation through the pot (MaterialBatch ledger) ────────────────
func _test_mass_conservation() -> void:
	_section("mass conservation")
	# Moderate rpm so the pot stays productive (in/near the sweet spot) for the whole
	# run instead of rocketing into a Donut stall — exercises the steady discharge +
	# evaporation paths. The built-in ledger counts BOTH feed() and the gate trickle.
	var cc = CutterCompactorScript.new()
	cc.start(700.0, 0.6)        # rpm chosen so the pot settles warm (>80 °C, so it dries)
								# but BELOW the Donut threshold — a steady productive run
	# 40 kg — WITHIN the 60 kg pot so the gate trickle has room to add mass
	# (a full pot leaves room=0 and the trickle can never register).
	cc.feed(_flake(40.0))
	for _i in range(3000):      # 300 s of run — the pot heats ~0.3 °C/s, so it
		cc.tick(0.1)            # needs a few sim-minutes to reach the >80 °C
		cc.discharge(0.1)       # band where drying + discharge actually engage
	# total_fed == in pot + discharged crumb + water flashed off. No silent loss.
	print("    fed=%.2f  in_pot=%.2f  discharged=%.2f  water_off=%.2f  residual=%.5f"
		% [cc.total_fed_kg, cc.charge.mass_kg, cc.discharged_kg, cc.water_removed_kg,
		   cc.ledger_residual()])
	_ok(abs(cc.ledger_residual()) < 0.01,
		"ledger balances (residual %.5f kg ≈ 0)" % cc.ledger_residual())
	_ok(cc.total_fed_kg > 40.0, "ledger counted feed() + gate trickle (%.1f kg)" % cc.total_fed_kg)
	_ok(cc.discharged_kg > 0.0, "some crumb was discharged (%.1f kg)" % cc.discharged_kg)
	_ok(cc.water_removed_kg > 0.0, "some moisture was flashed off (%.2f kg)" % cc.water_removed_kg)

# ── 7. Fill-efficiency curve monotonic shape ──────────────────────────────────
func _test_fill_efficiency_curve() -> void:
	_section("fill efficiency curve shape")
	# Rising through the underheat region, flat across the sweet spot, then tapering.
	_ok(CutterCompactorScript._fill_efficiency_for(50.0)
		< CutterCompactorScript._fill_efficiency_for(80.0), "eff rises 50→80 °C")
	_ok(CutterCompactorScript._fill_efficiency_for(80.0)
		< CutterCompactorScript._fill_efficiency_for(95.0), "eff rises 80→95 °C")
	_ok(CutterCompactorScript._fill_efficiency_for(110.0) == 0.0, "eff at 110 °C == 0 (stall edge)")
	# Bounds.
	for t in [0.0, 25.0, 90.0, 100.0, 105.0, 109.9]:
		var e : float = CutterCompactorScript._fill_efficiency_for(t)
		_ok(e >= 0.0 and e <= 1.0, "fill_eff(%.1f°C)=%.2f within [0,1]" % [t, e])

# ── helpers ───────────────────────────────────────────────────────────────────
## A wet LDPE flake batch (mass = poly + water), matching MaterialBatch's model.
func _flake(kg: float) -> MaterialBatch:
	return MaterialBatch.new(kg, kg / 60.0, {"LDPE": 1.0}, "test", kg * 0.10, 0.0)

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("RESULT: %s" % ["PASS" if _fail == 0 else "FAIL"])
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
