extends Node
## Plant-wide COMPRESSED-AIR supply network (single global header).
##
## Real CeDo layout: a bank of screw compressors charges ONE ring main (the
## "header") that every air consumer taps off — the TITECH NIR sorter's ejector
## valve bank (hundreds of fast blasts/s to kick off-spec flakes), the PCU /
## compactor's pneumatic ram, blow-off guns, etc. There is no per-machine tank in
## this model; everyone shares the header, so a greedy consumer (or a tripped
## compressor) starves the rest. That shared-fate coupling is the whole point —
## it's the same source→header→stratified-consumers DNA as the material line.
##
## MODEL (deterministic, unit-light):
##   * Compressors each add `capacity` Nm³/min of FREE-AIR delivery (FAD) while
##     running. Total supply = Σ capacities of running compressors.
##   * Consumers each draw `demand` Nm³/min while enabled. Total demand =
##     Σ demands of enabled consumers, EACH scaled by its current duty (0..1).
##   * The header is a finite air RECEIVER of RECEIVER_VOLUME_M3. Net flow
##     (supply − demand) integrates into stored air; pressure is stored air over
##     the receiver volume (ideal-gas, isothermal). Pressure is clamped to a
##     compressor cut-out ceiling so it can't run away.
##   * When pressure falls below FAULT_BAR a global NO-AIR fault latches and the
##     network broadcasts it on EventBus (machine_alarm_raised). Faulted
##     consumers degrade — see consumer_air_factor(): a TITECH with no air can't
##     eject, a PCU ram can't fire. The fault clears (with hysteresis, at
##     CLEAR_BAR) once supply is restored and the header re-pressurises.
##
## This file is a self-contained autoload: it touches nothing but EventBus (and
## only if that autoload is present), so it can be registered and unit-tested in
## isolation. Drive it from a real game loop via _process (automatic) or, for a
## deterministic headless test, call tick(delta) by hand.

# ── header physics constants ──────────────────────────────────────────────────
## Receiver/ring-main volume the header pressure is computed against (m³). Larger
## = more buffering, so transient demand spikes sag the pressure more slowly.
const RECEIVER_VOLUME_M3 : float = 2.0
## Nominal working pressure the compressors charge the ring toward (bar gauge).
const NOMINAL_BAR        : float = 7.0
## Compressor cut-out ceiling — pressure is clamped here so a no-load network
## doesn't integrate to infinity (a real pressure switch unloads the screw).
const MAX_BAR            : float = 8.0
## Below this the header can no longer guarantee valve actuation → NO-AIR fault.
const FAULT_BAR          : float = 4.5
## Hysteresis: the fault only clears once pressure recovers back above this, so a
## header hovering at the threshold doesn't chatter the alarm on/off every tick.
const CLEAR_BAR          : float = 5.5
## Pressure the header starts cold at on boot / reset (ambient, empty ring).
const START_BAR          : float = 0.0

## EventBus alarm identity (matches the <subject>_<event> signals already there).
const ALARM_ID           : String = "NO-AIR"
const ALARM_SOURCE       : String = "air_network"
const ALARM_SEVERITY     : int    = 3   # high: starves the sorter + compactor

# ── live state ────────────────────────────────────────────────────────────────
## Current header pressure in bar (gauge). Read by consumers + any HUD gauge.
var current_pressure_bar : float = START_BAR
## Air currently stored in the receiver (Nm³ of free air, at NOMINAL reference).
## Pressure is derived from this so supply/demand integrate a real quantity.
var _stored_air_m3 : float = 0.0

## Registered compressors: each {capacity: Nm³/min FAD, running: bool}.
var _compressors : Array = []
## Registered consumers, keyed by id → {demand: Nm³/min, duty: 0..1, enabled: bool}.
## duty lets a consumer modulate its draw (a TITECH ejecting heavily pulls its
## full demand; idle it tapers toward 0) without re-registering.
var _consumers : Dictionary = {}

## Latched fault flag (true = header below spec, consumers degraded).
var _faulted : bool = false

## Last broadcast supply/demand, for HUD/telemetry readouts (Nm³/min).
var _last_supply : float = 0.0
var _last_demand : float = 0.0

# ── signals (local; HUD/audio can listen without going through EventBus) ───────
signal pressure_changed(bar: float)
signal air_fault_raised
signal air_fault_cleared

# =============================================================================
func _ready() -> void:
	# Seed the receiver so current_pressure_bar and _stored_air_m3 agree from t0.
	_stored_air_m3 = _air_for_pressure(current_pressure_bar)

## Live header drive. Split from _process so a headless test can inject a FIXED
## delta for deterministic sim time (the same pattern LineFlow.tick uses).
func _process(delta: float) -> void:
	# Don't integrate an empty header before a world exists — with zero compressors
	# registered, the cold 0-bar start latches a false NO-AIR fault on frame 1 and
	# sounds the alarm in the MAIN MENU. Tick only once the plant's air bank is
	# registered (world build). Tests call tick()/register directly, so are unaffected. (#77)
	if _compressors.is_empty():
		return
	tick(delta)

# =============================================================================
# REGISTRATION
# =============================================================================
## Register a compressor that adds `capacity` Nm³/min of free-air delivery while
## running. Returns the compressor's index (its handle) so a caller can flip it
## on/off later via set_compressor_running(). Compressors start RUNNING — a cold
## plant powers its air bank up first, same as the real start-up order.
func register_compressor(capacity: float, running: bool = true) -> int:
	var first := _compressors.is_empty()
	_compressors.append({
		"capacity": maxf(capacity, 0.0),
		"running":  running,
	})
	# The plant's air bank powers up BEFORE the shift starts, so the header is
	# already at working pressure when the world loads. Seeding it here (on the
	# first compressor = world build) stops the cold 0-bar receiver from latching
	# a false NO-AIR fault on frame 1 and blaring the alarm on every load. (#77)
	if first and running:
		_stored_air_m3 = _air_for_pressure(NOMINAL_BAR)
		current_pressure_bar = NOMINAL_BAR
	return _compressors.size() - 1

## Register (or re-register) an air consumer. `id` is a stable string key
## ("titech_sort", "pcu_compactor", …); `demand` is its full-tilt draw in
## Nm³/min. Re-registering the same id updates its demand in place (so rebuilding
## a line doesn't stack duplicate draws). duty defaults to full; toggle the load
## later with set_consumer_duty() / set_consumer_enabled().
func register_consumer(id: String, demand: float) -> void:
	if _consumers.has(id):
		_consumers[id]["demand"] = maxf(demand, 0.0)
		return
	_consumers[id] = {
		"demand":  maxf(demand, 0.0),
		"duty":    1.0,
		"enabled": true,
	}

## Drop a consumer entirely (machine removed in build mode).
func unregister_consumer(id: String) -> void:
	_consumers.erase(id)

# ── runtime controls ──────────────────────────────────────────────────────────
## Flip a compressor on/off by the handle register_compressor() returned (e.g. a
## tripped motor, or staged start-up). Out-of-range handles are ignored.
func set_compressor_running(handle: int, running: bool) -> void:
	if handle >= 0 and handle < _compressors.size():
		_compressors[handle]["running"] = running

## Set a consumer's instantaneous duty (0..1) — its fraction of full demand right
## now. A TITECH ejecting a dirty stream sits near 1.0; an idle one near 0.0.
func set_consumer_duty(id: String, duty: float) -> void:
	if _consumers.has(id):
		_consumers[id]["duty"] = clampf(duty, 0.0, 1.0)

## Enable/disable a consumer's draw without forgetting its demand (powered down).
func set_consumer_enabled(id: String, enabled: bool) -> void:
	if _consumers.has(id):
		_consumers[id]["enabled"] = enabled

# =============================================================================
# TICK
# =============================================================================
## Advance the header one step. Sums running supply vs enabled·duty demand,
## integrates the net into the receiver, recomputes pressure, and raises/clears
## the NO-AIR fault with hysteresis. Safe to call with delta == 0 (a no-op step
## that just refreshes the cached supply/demand readouts).
func tick(delta: float) -> void:
	delta = maxf(delta, 0.0)

	var supply := _total_supply()
	var demand := _total_demand()
	_last_supply = supply
	_last_demand = demand

	# Net free-air flow (Nm³/min) → Nm³ over this step (delta is seconds).
	var net_m3 := (supply - demand) * (delta / 60.0)
	_stored_air_m3 = maxf(_stored_air_m3 + net_m3, 0.0)

	# Clamp stored air to the compressor cut-out ceiling so a no-load ring doesn't
	# integrate past MAX_BAR (the real pressure switch unloads the screw here).
	var ceiling := _air_for_pressure(MAX_BAR)
	if _stored_air_m3 > ceiling:
		_stored_air_m3 = ceiling

	var new_pressure := _pressure_for_air(_stored_air_m3)
	if not is_equal_approx(new_pressure, current_pressure_bar):
		current_pressure_bar = new_pressure
		pressure_changed.emit(current_pressure_bar)
	else:
		current_pressure_bar = new_pressure

	_update_fault()

# =============================================================================
# QUERIES (consumers read these to degrade themselves)
# =============================================================================
## True while the header is below spec and consumers should degrade.
func is_faulted() -> bool:
	return _faulted

## A 0..1 capability factor a consumer should multiply its pneumatic action by.
## 1.0 at/above nominal pressure, fading to 0.0 at the fault threshold — so a
## TITECH's eject strength (or a PCU ram's force) tracks the actual header
## pressure instead of being a hard on/off. Below the fault line it's 0: no air,
## no actuation. A consumer that just wants a boolean can use is_faulted().
func consumer_air_factor() -> float:
	if _faulted:
		return 0.0
	if current_pressure_bar >= NOMINAL_BAR:
		return 1.0
	var span := NOMINAL_BAR - FAULT_BAR
	if span <= 0.0:
		return 1.0
	return clampf((current_pressure_bar - FAULT_BAR) / span, 0.0, 1.0)

## Headroom: current supply minus current demand (Nm³/min). Negative = the ring
## is being drained faster than it's charged and pressure is falling.
func supply_margin() -> float:
	return _last_supply - _last_demand

func total_supply() -> float:
	return _last_supply

func total_demand() -> float:
	return _last_demand

func compressor_count() -> int:
	return _compressors.size()

func consumer_count() -> int:
	return _consumers.size()

## Full snapshot for a HUD air-gauge / diagnostics panel.
func status() -> Dictionary:
	return {
		"pressure_bar": current_pressure_bar,
		"supply":       _last_supply,
		"demand":       _last_demand,
		"margin":       supply_margin(),
		"faulted":      _faulted,
		"air_factor":   consumer_air_factor(),
		"compressors":  _compressors.size(),
		"consumers":    _consumers.size(),
	}

## Reset to a cold, empty ring (e.g. starting a fresh save). Clears the fault but
## keeps registrations — the plant's machines are still there, the air is just off.
func reset() -> void:
	current_pressure_bar = START_BAR
	_stored_air_m3 = _air_for_pressure(START_BAR)
	_last_supply = 0.0
	_last_demand = 0.0
	if _faulted:
		_faulted = false
		_emit_fault_cleared()

## Clear every registration (full teardown, e.g. layout rebuild from scratch).
func clear() -> void:
	_compressors.clear()
	_consumers.clear()
	reset()

# =============================================================================
# INTERNAL
# =============================================================================
func _total_supply() -> float:
	var s := 0.0
	for c in _compressors:
		if bool(c.get("running", false)):
			s += float(c.get("capacity", 0.0))
	return s

func _total_demand() -> float:
	var d := 0.0
	for id in _consumers:
		var c : Dictionary = _consumers[id]
		if bool(c.get("enabled", true)):
			d += float(c.get("demand", 0.0)) * float(c.get("duty", 1.0))
	return d

## Raise/clear the latched NO-AIR fault with hysteresis: trip below FAULT_BAR,
## only recover once back above CLEAR_BAR. Broadcasts on EventBus when present.
func _update_fault() -> void:
	if _faulted:
		if current_pressure_bar >= CLEAR_BAR:
			_faulted = false
			_emit_fault_cleared()
	else:
		# Only a header that something is actually DRAWING from can be air-starved.
		# With zero demand (e.g. an empty new world, or all consumers powered down)
		# a low reading is meaningless — never raise NO-AIR, so it can't alarm.
		if current_pressure_bar < FAULT_BAR and _last_demand > 0.0:
			_faulted = true
			_emit_fault_raised()

func _emit_fault_raised() -> void:
	air_fault_raised.emit()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("machine_alarm_raised"):
		bus.emit_signal("machine_alarm_raised", ALARM_SOURCE, ALARM_ID, ALARM_SEVERITY)
	print("[AirNetwork] NO-AIR fault — header at %.2f bar (supply %.1f / demand %.1f Nm³/min). Consumers degraded." \
		% [current_pressure_bar, _last_supply, _last_demand])

func _emit_fault_cleared() -> void:
	air_fault_cleared.emit()
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("machine_alarm_cleared"):
		bus.emit_signal("machine_alarm_cleared", ALARM_SOURCE, ALARM_ID)
	print("[AirNetwork] NO-AIR cleared — header recovered to %.2f bar." % current_pressure_bar)

# ── ideal-gas (isothermal) air ↔ pressure helpers ─────────────────────────────
## Free-air volume (Nm³) stored in the receiver at a given gauge pressure. Gauge
## bar + 1 atm absolute, times the receiver volume, gives Nm³ at 1-atm reference.
func _air_for_pressure(bar: float) -> float:
	return maxf(bar, 0.0) * RECEIVER_VOLUME_M3

func _pressure_for_air(air_m3: float) -> float:
	if RECEIVER_VOLUME_M3 <= 0.0:
		return 0.0
	return maxf(air_m3 / RECEIVER_VOLUME_M3, 0.0)
