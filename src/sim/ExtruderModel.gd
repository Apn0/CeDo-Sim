extends RefCounted
class_name ExtruderModel

## Pure simulation logic for one extruder — NO scene-tree dependency.
## Driven by a scene controller (ExtruderMachine.gd) which calls tick() each
## SimTick.sim_tick (10 Hz). Decoupling sim from scene lets us:
##   - unit-test in headless test scenes
##   - run faster-than-realtime for tuning sweeps
##   - keep simulation deterministic and frame-rate-independent
##
## State machine (the user's signature mechanic lives in VACUUM_ALARM):
##
##   OFF ──start──> IDLE ──ramp──> RUNNING
##                                  │
##           ┌──────────────────────┤
##           │ vacuum_lost          │
##           ▼                      │
##     VACUUM_ALARM ──restored──────┘
##           │
##           │ 120s expires
##           ▼
##         FAULT (melt runaway, lumps extrude catastrophically)
##           │
##           │ operator e-stop
##           ▼
##     EMERGENCY_STOP

enum State { OFF, IDLE, RUNNING, VACUUM_ALARM, FAULT, EMERGENCY_STOP }

# ── Configuration (injected on construction) ──────────────────────────────────
var config: ExtruderConfig

# ── State ─────────────────────────────────────────────────────────────────────
var state            : State = State.OFF
var melt_temp        : float = 25.0          # °C — starts at ambient
var screw_rpm        : float = 0.0
var throughput_kg_h  : float = 0.0
var filter_loading_g : float = 0.0           # grams accumulated since last swap
var runtime_s        : float = 0.0           # total RUNNING seconds

# Vacuum cascade
var vacuum_alarm_remaining_s: float = 0.0
var time_since_state_change : float = 0.0

# ── Construction ──────────────────────────────────────────────────────────────
func _init(cfg: ExtruderConfig) -> void:
	config = cfg

# =============================================================================
# TICK — called once per SimTick (delta = SimTick.TICK_DT, fixed 0.1 s)
# Returns list of events the scene controller should broadcast on EventBus.
# =============================================================================
func tick(delta: float, inputs: Dictionary) -> Array[String]:
	var events: Array[String] = []
	time_since_state_change += delta

	match state:
		State.OFF:
			_tick_off(delta)
		State.IDLE:
			_tick_idle(delta)
			if inputs.get("start_production", false):
				_transition(State.RUNNING, events)
		State.RUNNING:
			_tick_running(delta, inputs, events)
		State.VACUUM_ALARM:
			_tick_vacuum_alarm(delta, inputs, events)
		State.FAULT:
			_tick_fault(delta, inputs, events)
		State.EMERGENCY_STOP:
			_tick_e_stop(delta)
			if inputs.get("reset_after_estop", false):
				_transition(State.OFF, events)

	# E-stop input always honoured, regardless of current state
	if inputs.get("emergency_stop", false) and state != State.EMERGENCY_STOP:
		_transition(State.EMERGENCY_STOP, events)

	return events

# =============================================================================
# PER-STATE LOGIC
# =============================================================================
func _tick_off(delta: float) -> void:
	# Cool toward ambient
	melt_temp = move_toward(melt_temp, 25.0, 0.5 * delta)
	screw_rpm = 0.0
	throughput_kg_h = 0.0

func _tick_idle(delta: float) -> void:
	# Screw spinning at idle rpm, no feed, melt held at setpoint
	screw_rpm = config.screw_rpm_idle
	throughput_kg_h = config.idle_kg_per_h
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)

func _tick_running(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# Ramp throughput from idle to nominal over startup_ramp_s
	var ramp := clampf(runtime_s / config.startup_ramp_s, 0.0, 1.0)
	screw_rpm = lerpf(config.screw_rpm_idle, config.screw_rpm_nominal, ramp)
	throughput_kg_h = lerpf(config.idle_kg_per_h, config.nominal_kg_per_h, ramp)

	runtime_s += delta

	# Filter accumulates contamination
	filter_loading_g += throughput_kg_h * delta / 3600.0 * 1000.0
	if filter_loading_g >= config.backflush_threshold_grams:
		events.append("backflush_triggered")
		filter_loading_g -= config.backflush_threshold_grams

	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)

	# Inputs that can trigger alarm transitions
	if inputs.get("vacuum_lost", false):
		_transition(State.VACUUM_ALARM, events)

func _tick_vacuum_alarm(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# Production CONTINUES but a clock is ticking. Operator must fix vacuum
	# within grace period or the cascade fires.
	if time_since_state_change <= 0.1:
		vacuum_alarm_remaining_s = config.vacuum_alarm_grace_s

	vacuum_alarm_remaining_s -= delta
	# Screw + throughput unchanged during alarm — sim still produces.
	screw_rpm = config.screw_rpm_nominal
	throughput_kg_h = config.nominal_kg_per_h
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)

	if inputs.get("vacuum_restored", false):
		_transition(State.RUNNING, events)
		events.append("vacuum_alarm_cleared")
		return

	if vacuum_alarm_remaining_s <= 0.0:
		_transition(State.FAULT, events)
		events.append("vacuum_cascade_failure")

func _tick_fault(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# Melt runaway — temperature climbs, lumps extrude catastrophically.
	# Screw shuts down but melt is already in the barrel.
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	melt_temp += config.melt_temp_runaway_per_s * delta

	# Spawn lumps at a rate proportional to runaway severity
	# (scene controller picks this up to spawn rigid-body lump props)
	if int(time_since_state_change) % 3 == 0 and time_since_state_change > 0.5:
		events.append("fault_lump_produced")

	if inputs.get("operator_clear_fault", false):
		_transition(State.OFF, events)

func _tick_e_stop(delta: float) -> void:
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	melt_temp = move_toward(melt_temp, 25.0, 0.5 * delta)

# =============================================================================
# HELPERS
# =============================================================================
func _drift_melt_temp_toward(target: float, delta: float) -> void:
	melt_temp = move_toward(melt_temp, target, config.melt_temp_drift_per_s * delta)

func _transition(new_state: State, events: Array[String]) -> void:
	var old := state
	state = new_state
	time_since_state_change = 0.0
	events.append("state_changed:%d:%d" % [old, new_state])

# ── Queries ───────────────────────────────────────────────────────────────────
func get_state_name() -> String:
	return State.keys()[state]

func get_progress_percent_alarm() -> float:
	if state != State.VACUUM_ALARM:
		return 0.0
	return 1.0 - (vacuum_alarm_remaining_s / config.vacuum_alarm_grace_s)
