extends SceneTree
## Headless harness for the compressed-air supply network (AirNetwork autoload).
##
## Proves, with a FIXED hand-injected delta (deterministic — no physics server,
## no frame pacing), the three pillars of the air header:
##   1. pressure BUILDS when a compressor runs with no load,
##   2. pressure FALLS and a NO-AIR fault RAISES when demand exceeds supply,
##      degrading consumers (consumer_air_factor → 0, is_faulted → true), and the
##      fault is broadcast on EventBus (machine_alarm_raised),
##   3. the fault CLEARS once supply is restored and the header re-pressurises,
##      re-broadcast on EventBus (machine_alarm_cleared).
##
## Also checks registration plumbing (TITECH + PCU register as consumers, a
## compressor adds supply) and the hysteresis band (no alarm chatter).
##
## Run: godot --headless --path <proj> --script res://src/tests/test_air_network.gd

const AirNetworkScript = preload("res://src/autoload/AirNetwork.gd")

const DT : float = 0.05   # fixed 50 ms step — deterministic sim time

var _fail := 0
var _ran  := false

func _process(_delta: float) -> bool:
	# Run once on the first frame, not in _init(): only by the first _process() is
	# the SceneTree root actually in-tree, so an AirNetwork we add as a child can
	# resolve /root/EventBus (mirrors test_crew.gd's structure).
	if _ran:
		return true
	_ran = true
	print("=== AirNetwork compressed-air header harness ===")
	_test_registration()
	_test_pressure_builds()
	_test_starve_raises_fault()
	_test_supply_restored_clears()
	_test_hysteresis_no_chatter()
	if _fail == 0:
		print("\nALL OK")
	else:
		print("\n%d FAILED" % _fail)
	return true   # returning true ends the main loop (clean quit)

func _ok(c: bool, msg: String) -> void:
	print(("  ok  : " if c else "  FAIL: ") + msg)
	if not c:
		_fail += 1

## Fresh, in-tree AirNetwork for each test (isolated state). Added under the root
## so its EventBus lookup works; _ready() seeds the receiver from START_BAR.
func _make_net() -> Node:
	var net = AirNetworkScript.new()
	get_root().add_child(net)
	return net

## Step the header n fixed ticks.
func _run(net: Node, n: int) -> void:
	for _i in n:
		net.tick(DT)

# -----------------------------------------------------------------------------
func _test_registration() -> void:
	print("\n[registration]")
	var net := _make_net()
	var h : int = net.register_compressor(100.0)
	_ok(h == 0, "register_compressor returns a handle (%d)" % h)
	_ok(net.compressor_count() == 1, "one compressor registered")

	# The two real air consumers: TITECH NIR ejector bank + the PCU/compactor ram.
	net.register_consumer("titech_sort", 60.0)
	net.register_consumer("pcu_compactor", 25.0)
	_ok(net.consumer_count() == 2, "TITECH + PCU registered as consumers")

	# Re-registering an id updates demand in place (no duplicate stacking on a
	# layout rebuild).
	net.register_consumer("titech_sort", 70.0)
	_ok(net.consumer_count() == 2, "re-register updates in place, no duplicate")

	net.tick(0.0)   # delta 0 just refreshes the cached readouts
	_ok(is_equal_approx(net.total_supply(), 100.0), "supply sums running compressors (%.1f)" % net.total_supply())
	_ok(is_equal_approx(net.total_demand(), 95.0), "demand sums enabled consumers (%.1f)" % net.total_demand())
	net.free()

# -----------------------------------------------------------------------------
# 1) A running compressor with NO load charges the header up from cold.
# -----------------------------------------------------------------------------
func _test_pressure_builds() -> void:
	print("\n[pressure builds, no load]")
	# The fix (#77): a RUNNING compressor pre-charges the air bank on registration,
	# so the header is at working pressure from t0 and never false-alarms on load.
	var hot := _make_net()
	hot.register_compressor(120.0)
	_ok(hot.current_pressure_bar >= hot.NOMINAL_BAR, "running compressor pre-charges header on register (%.2f bar)" % hot.current_pressure_bar)
	_ok(not hot.is_faulted(), "no NO-AIR fault at load with a running compressor")

	# Register the compressor OFF so the header starts genuinely cold, to test the
	# charge-up integration explicitly.
	var net := _make_net()
	net.register_compressor(120.0, false)
	_ok(net.current_pressure_bar <= 0.001, "header starts cold with compressor off (%.3f bar)" % net.current_pressure_bar)
	net.set_compressor_running(0, true)
	var p0 : float = net.current_pressure_bar
	_run(net, 20)   # 1.0 s of charging
	var p1 : float = net.current_pressure_bar
	_ok(p1 > p0, "pressure rises while charging (%.2f → %.2f bar)" % [p0, p1])

	# Keep charging to full — pressure must clamp at the cut-out ceiling (not run
	# away), and only THEN is the header above spec with no fault. (A cold ring is
	# legitimately in NO-AIR until the compressor has charged it past the line.)
	_run(net, 2000)
	_ok(net.current_pressure_bar <= net.MAX_BAR + 0.001,
		"pressure clamps at MAX_BAR (%.2f ≤ %.2f)" % [net.current_pressure_bar, net.MAX_BAR])
	_ok(net.current_pressure_bar >= net.NOMINAL_BAR,
		"a no-load ring sits at/above nominal (%.2f bar)" % net.current_pressure_bar)
	_ok(not net.is_faulted(), "no fault once charged above the threshold")
	_ok(is_equal_approx(net.consumer_air_factor(), 1.0),
		"full air factor at working pressure (%.2f)" % net.consumer_air_factor())
	net.free()

# -----------------------------------------------------------------------------
# 2) Demand > supply drains the charged header below spec → NO-AIR fault, and
#    consumers degrade. The fault must hit EventBus too.
# -----------------------------------------------------------------------------
func _test_starve_raises_fault() -> void:
	print("\n[demand > supply raises NO-AIR fault]")
	var net := _make_net()

	# Listen for the EventBus broadcast (the fault must reach the global hub so the
	# HUD / sorter / siren react, exactly like LineFlow's e-stop does).
	var bus := get_root().get_node_or_null("EventBus")
	var got_alarm := [false]
	var got_id := [""]
	if bus != null and bus.has_signal("machine_alarm_raised"):
		bus.machine_alarm_raised.connect(func(mid, aid, _sev):
			if String(aid) == net.ALARM_ID:
				got_alarm[0] = true
				got_id[0] = String(mid))
	else:
		print("    note: EventBus autoload not present — checking local fault state only")

	# Charge the ring up first (compressor on, no draw). A cold ring trips a NO-AIR
	# alarm on tick 1 and clears it once charged — so reset the listener AFTER the
	# charge, to prove specifically that the STARVATION below raises a fresh alarm.
	var comp : int = net.register_compressor(120.0)
	_run(net, 400)
	_ok(net.current_pressure_bar >= net.NOMINAL_BAR, "header charged to working pressure first (%.2f bar)" % net.current_pressure_bar)
	_ok(not net.is_faulted(), "not faulted while charged")
	got_alarm[0] = false
	got_id[0] = ""

	# Now KILL supply and slam on a heavy draw: TITECH ejecting hard + PCU firing,
	# far more than the (now-stopped) compressor can feed.
	var p_before : float = net.current_pressure_bar
	net.set_compressor_running(comp, false)
	net.register_consumer("titech_sort", 90.0)
	net.register_consumer("pcu_compactor", 40.0)
	net.tick(0.0)   # delta 0: refresh cached supply/demand without moving pressure
	_ok(net.supply_margin() < 0.0, "supply margin goes negative (%.1f Nm³/min)" % net.supply_margin())

	# Step until the header sags below the fault line (bounded loop — deterministic).
	for _i in 400:
		net.tick(DT)
		if net.is_faulted():
			break
	_ok(net.current_pressure_bar < p_before, "pressure falls under over-demand (%.2f → %.2f bar)" % [p_before, net.current_pressure_bar])
	_ok(net.is_faulted(), "NO-AIR fault latches below FAULT_BAR (%.2f bar)" % net.current_pressure_bar)
	_ok(is_equal_approx(net.consumer_air_factor(), 0.0),
		"faulted header degrades consumers (air_factor=%.2f → can't eject)" % net.consumer_air_factor())
	if bus != null:
		_ok(got_alarm[0], "fault broadcast on EventBus.machine_alarm_raised")
		_ok(got_id[0] == net.ALARM_SOURCE, "alarm carries the air-network source id (%s)" % got_id[0])
	net.free()

# -----------------------------------------------------------------------------
# 3) Restore supply → header re-pressurises → fault clears (and EventBus hears it).
# -----------------------------------------------------------------------------
func _test_supply_restored_clears() -> void:
	print("\n[supply restored clears the fault]")
	var net := _make_net()

	var bus := get_root().get_node_or_null("EventBus")
	var got_clear := [false]
	if bus != null and bus.has_signal("machine_alarm_cleared"):
		bus.machine_alarm_cleared.connect(func(_mid, aid):
			if String(aid) == net.ALARM_ID:
				got_clear[0] = true)

	# Drive straight into a fault: no compressor, a steady draw, from cold.
	net.register_consumer("titech_sort", 80.0)
	for _i in 200:
		net.tick(DT)
		if net.is_faulted():
			break
	_ok(net.is_faulted(), "set up: header is in NO-AIR fault (%.2f bar)" % net.current_pressure_bar)

	# Bring a big compressor online that comfortably out-supplies the draw.
	net.register_compressor(300.0)
	var cleared := false
	for _i in 800:
		net.tick(DT)
		if not net.is_faulted():
			cleared = true
			break
	_ok(cleared, "fault clears once supply is restored (%.2f bar)" % net.current_pressure_bar)
	_ok(net.current_pressure_bar >= net.CLEAR_BAR,
		"clears only after recovering past the hysteresis band (≥ %.1f bar)" % net.CLEAR_BAR)
	_ok(net.consumer_air_factor() > 0.0, "consumers regain air after recovery (%.2f)" % net.consumer_air_factor())
	if bus != null:
		_ok(got_clear[0], "clear broadcast on EventBus.machine_alarm_cleared")
	net.free()

# -----------------------------------------------------------------------------
# Hysteresis: a header hovering right at the fault line must NOT chatter the alarm
# on and off every tick — it trips once at FAULT_BAR and only resets past CLEAR_BAR.
# -----------------------------------------------------------------------------
func _test_hysteresis_no_chatter() -> void:
	print("\n[hysteresis — no alarm chatter]")
	var net := _make_net()
	var raises := [0]
	var clears := [0]
	net.air_fault_raised.connect(func(): raises[0] += 1)
	net.air_fault_cleared.connect(func(): clears[0] += 1)

	# Cold ring, supply == 0, a tiny trickle demand: it trips once and stays starved.
	net.register_consumer("trickle", 1.0)
	for _i in 400:
		net.tick(DT)
		if net.is_faulted():
			break
	# Keep ticking under the same starved load — it must NOT re-raise or clear.
	for _i in 200:
		net.tick(DT)
	_ok(raises[0] == 1, "fault raised exactly once, no chatter (%d raises)" % raises[0])
	_ok(clears[0] == 0, "no spurious clear while still starved (%d clears)" % clears[0])
	net.free()
