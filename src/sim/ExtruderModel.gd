extends RefCounted
class_name ExtruderModel

## Pure simulation logic for one extruder — NO scene-tree dependency.
## Driven by a scene controller (ExtruderMachine.gd) which calls tick() each
## SimTick.sim_tick (10 Hz). Decoupling sim from scene lets us:
##   - unit-test in headless test scenes
##   - run faster-than-realtime for tuning sweeps
##   - keep simulation deterministic and frame-rate-independent
##
## ─── SIX-STAGE PIPELINE (operator-confirmed flow) ───────────────────────────
## Material crosses the screw in this fixed order:
##
##   1. TRANSPORT       — flake from the feed silo down to the screw root
##   2. HEAT             — barrel zones bring the charge up to soft-melt temp
##   3. MELT_COMPACT     — main melting + densification work zone
##   4. PRIMARY_DEGAS    — first vacuum port; pulls water + early volatiles
##   5. HOMOGENISE       — mixing zone; smooths thermal + composition gradients
##   6. SECONDARY_DEGAS  — second vacuum port; catches what stage 4 missed
##   → laser filter + die head (modelled in LaserFilter.gd / HeadFilter.gd)
##
## Each stage's RESIDENCE TIME = stage_length / melt_velocity, where
## melt_velocity rises with screw_rpm. Faster RPM ⇒ shorter residence ⇒ less
## time for the vacuum ports to extract gas — this is the Push-Feed-RPM
## cascade from the operator-lever matrix (high throughput at the cost of
## bubbles/discolour at the die).
##
## ─── COUNTERCURRENT TECHNOLOGY (doc only — physics already implicit) ────────
## The flake at the extruder intake moves OPPOSITE to the screw rotation;
## relative velocity at the intake is therefore (v_material + v_screw_wall),
## making the screw act as an aggressive cutting edge. This is what lets the
## machine swallow low-bulk-density fluff that a co-current screw would just
## ride over. The intake-cutting effect is implicit in the throughput-ramp
## model (fluffy feed cuts to dense melt without an explicit kg/min step);
## a future revision could expose an `intake_cut_efficiency` field if needed.
##
## ─── TWO VACUUM STAGES ──────────────────────────────────────────────────────
## Each has an INDEPENDENT operator-tunable suction setpoint (0..1). Effective
## gas-extraction capacity scales with that setpoint. Stages also have their
## own loading counters (vacuum pots fill with backflush melt that, if not
## drained, eventually pushes the lid open — see VACUUM_ALARM cascade below
## for the future repurpose).
##
## ─── VOLATILE LOAD MODEL ────────────────────────────────────────────────────
## Incoming material carries `volatile_load_g_per_kg` (set externally by the
## upstream wash/dry line each tick). Each degas stage pulls gas out
## proportional to (its capacity × residence_time). What's LEFT at the die
## drives `pellet_defect_rate` — visible to the operator on the SCADA as a
## per-batch quality reading.
##
## State machine (the user's signature mechanic lives in VACUUM_ALARM):
##
##   OFF ──start──> IDLE ──ramp──> RUNNING
##                                  │
##           ┌──────────────────────┤
##           │ vacuum_lid_open OR   │
##           │ motor_torque_trip    │
##           ▼                      │
##     VACUUM_ALARM ──restored──────┘
##           │
##           │ 120s expires (operator did not address)
##           ▼
##         FAULT (cascade-stop EVERYTHING EXCEPT THE PCU)
##           │
##           │ operator e-stop / clear
##           ▼
##     EMERGENCY_STOP
##
## ─── FAULT STATE — NEW SEMANTICS (operator-confirmed) ───────────────────────
## FAULT no longer represents "melt runaway, lumps everywhere". Per the
## operator: the real plant behaviour is that EVERYTHING ELSE in the line
## stops (extruder screw, both vacuum units, laser filter, head filter,
## pelletizer/heetafslag, downstream dewater) so they don't burn product
## while no one's at the panel — but the PCU/CutterCompactor KEEPS RUNNING,
## because if you stop the compactor mid-charge it can seize.
##
## ExtruderModel publishes:
##   - `state_changed:<old>:<new>` always
##   - `vacuum_cascade_failure` when entering FAULT from VACUUM_ALARM
##   - `cascade_stop_all_except_pcu` once on FAULT entry — the scene controller
##     (ExtruderMachine) acts on this to call stop() on the laser filter,
##     head filter, heetafslag, etc., while leaving the CutterCompactor alone.
##   - `motor_torque_trip` when entering FAULT due to sustained over-torque
##
## See also `fault_reason : String` on the model for what tripped it.

## STARTING/STOPPING added to mirror the EREMA HMI emulator's 4-state ramp
## (Micro-Extruder/erema_hmi.py: STOPPED → STARTING → RUNNING → STOPPING).
## They sit between IDLE and RUNNING (resp. RUNNING and OFF) so external code
## that branches on RUNNING needs to treat STARTING + STOPPING as "active
## production" — both still drive material flow at a fraction of nominal.
enum State { OFF, IDLE, STARTING, RUNNING, STOPPING, VACUUM_ALARM, FAULT, EMERGENCY_STOP }
enum DieFaceState { OFF, TE_KOUD, GOED_GEHARD, TE_HEET }

# =============================================================================
# SIX-STAGE PIPELINE (static config)
# =============================================================================
# Length contributions sum to roughly the L/D barrel length of a CeDo Iruma
# TVEplus extruder (~30·D, normalised here). `degas_g_per_s` is the BASE gas
# extraction rate at 100 % suction; effective rate at runtime = base × the
# operator's suction setpoint. Only PRIMARY_DEGAS and SECONDARY_DEGAS have
# nonzero degas capacity — the other stages just pass material through.
enum Stage { TRANSPORT, HEAT, MELT_COMPACT, PRIMARY_DEGAS, HOMOGENISE, SECONDARY_DEGAS }

const STAGES : Array[Dictionary] = [
	{"id": Stage.TRANSPORT,       "len_norm": 0.10, "degas_g_per_s": 0.0},
	{"id": Stage.HEAT,            "len_norm": 0.18, "degas_g_per_s": 0.0},
	{"id": Stage.MELT_COMPACT,    "len_norm": 0.24, "degas_g_per_s": 0.0},
	{"id": Stage.PRIMARY_DEGAS,   "len_norm": 0.16, "degas_g_per_s": 9.0},
	{"id": Stage.HOMOGENISE,      "len_norm": 0.16, "degas_g_per_s": 0.0},
	{"id": Stage.SECONDARY_DEGAS, "len_norm": 0.16, "degas_g_per_s": 6.0},
]

# Total barrel "transit time" at nominal RPM. Real EREMA ~30..60 s end-to-end
# at design throughput; this is the baseline used to compute each stage's
# residence time as a fraction of total.
const BARREL_TRANSIT_S_AT_NOMINAL : float = 45.0

# Vacuum pot capacity (kg of melt the pot can hold before the lid alarm
# triggers in the repurposed VACUUM_ALARM mechanic). Operator-confirmed
# behaviour: melt keeps coming in even while vacuum is "extracting", and
# accumulated backflush eventually fills the pot.
const VACUUM_POT_CAPACITY_KG : float = 18.0

# Pellet-defect mapping: how residual volatile load at the die translates to
# a 0..1 defect rate the SCADA reads. Below DEFECT_RESIDUAL_OK_G_PER_KG the
# pellet is on-spec; above DEFECT_RESIDUAL_SCRAP_G_PER_KG the batch is scrap.
const DEFECT_RESIDUAL_OK_G_PER_KG    : float = 1.5
const DEFECT_RESIDUAL_SCRAP_G_PER_KG : float = 12.0
const DIE_FACE_COLD_OFFSET_C := 15.0
const DIE_FACE_HOT_OFFSET_C  := 20.0

## STARTING → RUNNING ramp (screw_rpm 0 → nominal). 4 s matches the operator
## emulator's `(sp - sa) * 0.1` step at 0.5 s tick (≈ 95 % reached in ~4 s).
const START_RAMP_S        : float = 4.0
## STOPPING → OFF decay. Time-constant; `rpm *= exp(-delta / STOP_DECAY_S)`
## so framerate-independent. 4 s ≈ the emulator's `*= 0.9` step at 0.5 s tick.
const STOP_DECAY_S        : float = 4.0
const STARTING_RPM_THRESHOLD_FRAC : float = 0.95   # within 5 % of nominal → RUNNING
const STOPPING_RPM_FLOOR  : float = 0.5            # below this → OFF

# =============================================================================
# SEVEN-ZONE TEMPERATURE MODEL
# =============================================================================
# Operator-confirmed: there are roughly 7 controlled temperature zones spanning
# the melt path — barrel zones + laser-filter heater + die-head clusters. The
# operator can drop any zone's setpoint (e.g. zone 1/2 lowered to avoid
# burning paper/cellulose contamination on a dirty feed). Cold zones raise
# local viscosity, which loads the screw motor, which in extreme cases trips
# the torque limit AND pushes un-melted lumps into the laser filter.
const ZONE_COUNT : int = 7
const ZONE_NAMES : Array[String] = [
	"transport",        # 1 — flake intake / feed throat
	"heat_1",           # 2 — first barrel heat zone
	"heat_2",           # 3 — second barrel heat zone
	"melt_compact",     # 4 — main melting + densification
	"primary_degas",    # 5 — local heat at primary vacuum port
	"homogenise",       # 6 — mixing + laser filter heater
	"secondary_degas",  # 7 — die-head cluster + secondary degas port
]

# Motor torque trip: sustained > TORQUE_TRIP_PCT for TORQUE_TRIP_SUSTAIN_S
# transitions the model to FAULT with fault_reason = "motor_torque_trip".
const TORQUE_TRIP_PCT          : float = 110.0
const TORQUE_TRIP_SUSTAIN_S    : float = 2.0
# Above this torque the extruder starts passing un-melted lumps to the
# laser filter (exposed via lump_passthrough_rate_g_s for the LaserFilter to read).
const LUMP_PASSTHROUGH_TORQUE_PCT : float = 95.0

# =============================================================================
# VACUUM FLOODING FAILURE MODE (operator-confirmed)
# =============================================================================
# Low-viscosity melt + high suction lets thin melt creep up the vacuum line
# and accumulate as "gunk" — gradually chokes the vacuum until someone
# dismantles and cleans it. Slow build (~30 min of risky conditions to fill).
const VACUUM_FLOOD_RATE_KG_PER_S         : float = 0.00012
const VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG : float = 4.0
const VACUUM_FLOOD_CHOKED_CAPACITY_SCALE : float = 0.30  # vacuum capacity once flooded

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
# #157 — last sim-time a fault lump was emitted, so the 3-second cadence fires
# ONCE per interval instead of every frame for the whole integer-second window.
var _last_lump_emit_s : float = -100.0

# What caused the most-recent transition to VACUUM_ALARM / FAULT. Read by the
# scene controller / HMI to display the right cause to the operator.
# Known values: "" (none), "vacuum_lid_pushed_open", "vacuum_lost_input",
# "motor_torque_trip", "softstarter_trip" (the softstarter actually lives on
# the PCU model — see CutterCompactor.gd / PCUModel — we accept the value
# here only when ExtruderMachine forwards it for unified HMI display).
var fault_reason : String = ""

# Seven-zone temperature setpoints (operator-tunable). Built from
# config.zone_temp_setpoints if that's set with length == ZONE_COUNT,
# otherwise filled with config.melt_temp_setpoint on first tick / construction.
var zone_temp_setpoints : Array[float] = []

# Motor torque (% of design max). Computed from average zone-setpoint shortfall.
# > TORQUE_TRIP_PCT for TORQUE_TRIP_SUSTAIN_S → FAULT (motor_torque_trip).
# > LUMP_PASSTHROUGH_TORQUE_PCT → un-melted lumps go downstream to the laser
# filter; the LaserFilter reads `lump_passthrough_rate_g_s` and ups its loading.
var motor_torque_pct          : float = 0.0
var _torque_trip_accum_s      : float = 0.0
var lump_passthrough_rate_g_s : float = 0.0

# Vacuum flooding (operator-confirmed failure mode). Thin melt + high suction
# lets melt creep up the vacuum line as "gunk". Slow build (~30 min of risky
# conditions to dismantle threshold); once flooded, vacuum capacity drops to
# 30 % until clean_vacuum_lines() is called (future maintenance task).
var vacuum_line_gunk_kg          : float = 0.0
var flooded_dismantle_required   : bool  = false

# =============================================================================
# DEGASSING + QUALITY MODEL  (gap-report row: extruder + degassing)
# =============================================================================
# Volatile load per kg of feed. Set externally each tick by the upstream wash
# /dry line — high values come from wet feed, ink-heavy printed film, or
# burned cellulose contamination. Each degas stage extracts gas at a rate
# bounded by (stage capacity × suction × residence time); whatever's LEFT at
# the die drives pellet_defect_rate.
var volatile_load_g_per_kg   : float = 4.0     # default: clean LDPE feed

# Per-stage operator-tunable VACUUM SUCTION (0..1). Two independent setpoints
# because the operator-lever matrix lets you (a) push max suction on a wet
# feed, or (b) bypass primary while running, or (c) ride at half on both.
var primary_suction_pct      : float = 0.85    # default cruise
var secondary_suction_pct    : float = 0.85
var bypass_primary           : bool  = false   # if true, primary extracts 0 g/s

# Vacuum-pot loading (grams of backflush melt accumulated in each pot).
# Repurposed VACUUM_ALARM cascade WILL drive off this (later turn) — for now
# we just track it so the pot fill state is visible on the HMI.
var primary_pot_fill_kg      : float = 0.0
var secondary_pot_fill_kg    : float = 0.0

# Derived per-tick quantities exposed to the SCADA / HMI / ExtruderMachine:
var residence_time_s         : float = BARREL_TRANSIT_S_AT_NOMINAL
var per_stage_residence_s    : Array[float] = []   # one entry per STAGES row
var per_stage_extracted_g_s  : Array[float] = []   # gas pulled by each degas stage this tick
var residual_volatile_g_per_kg : float = 0.0       # what's left when the melt reaches the die
var pellet_defect_rate       : float = 0.0         # 0..1 — what the SCADA shows the operator

# Die-head melt pressure (psi). Derived from the rheology model — viscosity ×
# throughput. Matches the head-filter / laser-filter pressure scale (psi) the
# operator HMI uses for ΔP readouts. Constants tuned so a clean LDPE run at
# nominal RPM + nominal throughput + setpoint melt temp lands at the operator-
# documented ~280 psi die-head pressure. Climbs when:
#   * throughput rises (more mass through the same die orifice)
#   * viscosity rises (cold zones → motor torque climbs → die pressure climbs)
# This is the OUTPUT signal forwarded to the LaserFilter as the "upstream
# pressure indicator" — feeds the front-loading amplification cascade so the
# operator's "right side clogged again" diagnostic reads correctly.
const DIE_PRESSURE_BASE_PSI : float = 280.0
var die_pressure_psi         : float = 0.0

var die_face_state : int = DieFaceState.OFF
var pelletizer : PelletizerModel = null

# ── Construction ──────────────────────────────────────────────────────────────
func _init(cfg: ExtruderConfig) -> void:
	config = cfg
	# Initialise per-zone setpoints. If the config supplies a properly sized
	# array we adopt it; otherwise every zone inherits the global
	# `melt_temp_setpoint` and the operator can drop individual zones later
	# via set_zone_temp() (e.g. to avoid burning paper/cellulose).
	zone_temp_setpoints = []
	zone_temp_setpoints.resize(ZONE_COUNT)
	var use_cfg : bool = config != null \
		and config.zone_temp_setpoints != null \
		and config.zone_temp_setpoints.size() == ZONE_COUNT
	for i in range(ZONE_COUNT):
		if use_cfg:
			zone_temp_setpoints[i] = float(config.zone_temp_setpoints[i])
		else:
			zone_temp_setpoints[i] = config.melt_temp_setpoint if config != null else 215.0
	if pelletizer == null:
		pelletizer = PelletizerModel.new()

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
			if inputs.get("start_production", false):
				_transition(State.STARTING, events)
		State.IDLE:
			_tick_idle(delta)
			if inputs.get("start_production", false):
				_transition(State.STARTING, events)
		State.STARTING:
			_tick_starting(delta, inputs, events)
			# Operator can abort mid-ramp; falls through to STOPPING
			if inputs.get("stop_production", false):
				_transition(State.STOPPING, events)
			elif screw_rpm >= config.screw_rpm_nominal * STARTING_RPM_THRESHOLD_FRAC:
				_transition(State.RUNNING, events)
		State.RUNNING:
			_tick_running(delta, inputs, events)
			if inputs.get("stop_production", false):
				_transition(State.STOPPING, events)
		State.STOPPING:
			_tick_stopping(delta, inputs, events)
			# Operator can re-start during coast-down → goes back through STARTING
			if inputs.get("start_production", false):
				_transition(State.STARTING, events)
			elif screw_rpm < STOPPING_RPM_FLOOR:
				_transition(State.OFF, events)
		State.VACUUM_ALARM:
			_tick_vacuum_alarm(delta, inputs, events)
		State.FAULT:
			_tick_fault(delta, inputs, events)
		State.EMERGENCY_STOP:
			_tick_e_stop(delta)
			if inputs.get("reset_after_estop", false):
				_transition(State.OFF, events)

	# E-stop input always honoured, regardless of current state. Clear the
	# fault_reason so the next run starts with a clean SCADA chip (the operator
	# pulled the cord — whatever the previous trip cause was, it's been
	# acknowledged at the pull).
	if inputs.get("emergency_stop", false) and state != State.EMERGENCY_STOP:
		fault_reason = ""
		_transition(State.EMERGENCY_STOP, events)

	return events

# =============================================================================
# PER-STATE LOGIC
# =============================================================================
func _tick_off(delta: float) -> void:
	# Cool toward ambient. Also drop the live rheology / lump readings to zero
	# so the SCADA gauges park at calm grey when the machine is powered off
	# (without these the last RUNNING value would freeze on the dashboard,
	# making it look like the line was still loading the screw motor).
	melt_temp = move_toward(melt_temp, 25.0, 0.5 * delta)
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	die_pressure_psi = 0.0
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	die_face_state = DieFaceState.OFF

func _tick_idle(delta: float) -> void:
	# Screw spinning at idle rpm, no feed, melt held at setpoint. Live
	# rheology/lump readings stay at zero — no production = no die pressure,
	# no torque load, no lump passthrough. Without these the gauges would
	# carry stale post-RUN values from before the operator paused production.
	screw_rpm = config.screw_rpm_idle
	throughput_kg_h = config.idle_kg_per_h
	die_pressure_psi = 0.0
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)
	die_face_state = DieFaceState.OFF

func _tick_running(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# Ramp throughput from idle to nominal over startup_ramp_s
	var ramp := clampf(runtime_s / config.startup_ramp_s, 0.0, 1.0)
	screw_rpm = lerpf(config.screw_rpm_idle, config.screw_rpm_nominal, ramp)
	throughput_kg_h = lerpf(config.idle_kg_per_h, config.nominal_kg_per_h, ramp)
	if pelletizer != null:
		pelletizer.tick(delta, state == State.RUNNING)
		throughput_kg_h *= pelletizer.get_throughput_multiplier()

	# NOTE — LEEGDRAAIEN (cascading empty) is implicit and needs no special
	# branch here: when the upstream feed stops, the wash/dry line drives
	# `throughput_kg_h` toward zero via `volatile_load`/throughput coupling
	# elsewhere; downstream machines then starve in order as their own buffers
	# drain through their own discharge logic. Material is conserved end-to-
	# end; there is no "leegdraaien mode" flag because none is needed.
	# (Also see the FAULT cascade — a different mechanic: that one HALTS the
	# screw and downstream while keeping the PCU alive.)

	runtime_s += delta

	# Filter accumulates contamination
	filter_loading_g += throughput_kg_h * delta / 3600.0 * 1000.0
	if filter_loading_g >= config.backflush_threshold_grams:
		events.append("backflush_triggered")
		filter_loading_g -= config.backflush_threshold_grams

	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)
	_evaluate_die_face_state()

	# Motor torque from zone-temp shortfall (cold zones ⇒ thick melt ⇒ high
	# torque). Above LUMP_PASSTHROUGH_TORQUE_PCT, un-melted lumps start
	# passing into the laser filter — exposed for LaserFilter to read.
	# Computed BEFORE _step_degassing so the die-pressure formula
	# (viscosity_factor = motor_torque_pct / base) reads the CURRENT tick's
	# torque, not last tick's stale value. Without this, the first RUNNING
	# tick after a state change uses a zeroed torque and dumps a one-tick
	# bogus low-pressure reading to the SCADA.
	_update_motor_torque(delta, events)
	# If the torque trip fired the FAULT transition above, abandon the rest of
	# the RUNNING tick — don't keep accumulating filter loading or evaluating
	# the pot-lid alarm in a state we just left.
	if state != State.RUNNING:
		return

	# Six-stage degassing pass. Each tick: compute residence time per stage
	# from current screw_rpm, walk material through the stages applying gas
	# extraction at the two degas ports, leave residual at the die for the
	# quality reading. Higher RPM ⇒ shorter residence ⇒ less gas pulled ⇒
	# higher pellet defect rate (Push-Feed-RPM cascade from the matrix).
	_step_degassing(delta)

	# ── ALARM TRIGGERS ────────────────────────────────────────────────────────
	# (a) NEW operator-confirmed trigger: vacuum POT fills with backflush melt;
	# when full + more incoming, melt pushes the lid open and raises the loud
	# alarm. Trigger when either pot is at capacity.
	if primary_pot_fill_kg >= VACUUM_POT_CAPACITY_KG \
			or secondary_pot_fill_kg >= VACUUM_POT_CAPACITY_KG:
		fault_reason = "vacuum_lid_pushed_open"
		_transition(State.VACUUM_ALARM, events)
		return
	# (b) Back-compat: explicit `vacuum_lost` input still triggers (manual
	# operator-side trigger, e.g. a vacuum-line break).
	if inputs.get("vacuum_lost", false):
		fault_reason = "vacuum_lost_input"
		_transition(State.VACUUM_ALARM, events)

## Linear ramp from screw_rpm_idle → screw_rpm_nominal over START_RAMP_S.
## Material does flow during the ramp at a fraction of nominal so downstream
## buffers begin to fill, mirroring the real plant's gentle pull-in behavior.
func _tick_starting(delta: float, _inputs: Dictionary, events: Array[String]) -> void:
	var nominal := config.screw_rpm_nominal
	var idle    := config.screw_rpm_idle
	# Linear ramp: per-tick step keeps consumers (e.g. RotatingMechanism) smooth.
	# Explicit `: float` + maxf (the float-typed variant) so the walrus inference
	# doesn't fall back to Variant on the `max(float, float)` overload.
	var step : float = (nominal - idle) * (delta / maxf(0.01, START_RAMP_S))
	screw_rpm = clampf(screw_rpm + step, idle, nominal)
	# Throughput scales with rpm fraction.
	var rpm_frac : float = clampf(screw_rpm / max(nominal, 1.0), 0.0, 1.0)
	throughput_kg_h = lerpf(config.idle_kg_per_h, config.nominal_kg_per_h, rpm_frac)
	if pelletizer != null:
		pelletizer.tick(delta, true)
		throughput_kg_h *= pelletizer.get_throughput_multiplier()
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)
	_evaluate_die_face_state()
	# Motor torque comes online with the screw so the SCADA chart shows a
	# realistic surge during start-up rather than a flat 0 → step.
	_update_motor_torque(delta, events)
	# Die pressure is allowed to climb proportionally — no fault triggers in
	# this state since nothing's at nominal yet.
	die_pressure_psi *= rpm_frac

## Time-constant decay (rpm *= exp(-delta / STOP_DECAY_S)). Frame-rate
## independent and matches the emulator's `*= 0.9` decay step at 0.5 s tick.
## Production continues at the residual rpm fraction so downstream catches
## the tail-end material; no new lumps are emitted (die_pressure = 0).
func _tick_stopping(delta: float, _inputs: Dictionary, _events: Array[String]) -> void:
	var nominal := config.screw_rpm_nominal
	# Exponential decay: rpm_new = rpm_old * exp(-delta / tau)
	screw_rpm = screw_rpm * exp(-delta / max(0.05, STOP_DECAY_S))
	var rpm_frac : float = clampf(screw_rpm / max(nominal, 1.0), 0.0, 1.0)
	throughput_kg_h = lerpf(0.0, config.nominal_kg_per_h, rpm_frac)
	if pelletizer != null:
		pelletizer.tick(delta, screw_rpm > STOPPING_RPM_FLOOR)
	# Heaters slowly stop holding setpoint — drift toward a cooler hold-temp.
	_drift_melt_temp_toward(config.melt_temp_setpoint * 0.85, delta)
	_evaluate_die_face_state()
	motor_torque_pct = motor_torque_pct * rpm_frac
	die_pressure_psi = die_pressure_psi * rpm_frac
	# Lump passthrough stops as the screw stops — no fresh un-melted material.
	lump_passthrough_rate_g_s = 0.0

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
	_evaluate_die_face_state()
	# Production continues during the 120 s grace, so the live die-pressure,
	# torque, degas, and pellet-quality readings MUST keep updating. Without
	# these calls the SCADA gauges would freeze at their last RUNNING value
	# for the whole alarm window, which is exactly when the operator needs
	# them to react.
	_update_motor_torque(delta, events)
	if state != State.VACUUM_ALARM:
		# Motor-torque trip fired and demoted us out of VACUUM_ALARM straight
		# into FAULT. Bail before _step_degassing would touch a state we left.
		return
	_step_degassing(delta)

	if inputs.get("vacuum_restored", false):
		# Operator addressed the alarm — clear the cause string so the SCADA
		# "fault_reason" chip drops back to grey on the next push. Without this
		# the dashboard would keep painting the chip alarm-red (e.g. carrying
		# "vacuum_lost_input") well after the line resumed RUNNING.
		fault_reason = ""
		_transition(State.RUNNING, events)
		events.append("vacuum_alarm_cleared")
		return

	if vacuum_alarm_remaining_s <= 0.0:
		# fault_reason is preserved from the original VACUUM_ALARM trigger
		# (e.g. "vacuum_lid_pushed_open"); the cascade name is the same regardless.
		_transition(State.FAULT, events)
		events.append("vacuum_cascade_failure")

func _tick_fault(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# ── NEW FAULT SEMANTICS (operator-confirmed) ─────────────────────────────
	# Per the operator, the real-plant FAULT cascade halts EVERYTHING IN THE
	# LINE EXCEPT THE PCU: extruder screw, both vacuum units, laser filter,
	# head filter, pelletizer/heetafslag, downstream dewater all stop. The
	# PCU/CutterCompactor KEEPS RUNNING because stopping it mid-charge can
	# seize the donut. There is no melt runaway and no lump emission from
	# the extruder die — material in the barrel just sits there until cleared.
	#
	# The scene controller (ExtruderMachine) listens for
	# `cascade_stop_all_except_pcu` and calls stop()/cascade_stop on the
	# laser filter, head filter, heetafslag, etc.
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	die_pressure_psi = 0.0   # screw stopped → no flow → no head pressure
	# Melt temp slowly drifts toward setpoint while halted (heaters stay on
	# but nothing is being pushed through). No more runaway integration.
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)

	# Emit the cascade-stop event ONCE per FAULT entry. _last_lump_emit_s is
	# reset to -100 in _transition so the first tick after entry fires it.
	if _last_lump_emit_s < 0.0 and time_since_state_change >= 0.0:
		_last_lump_emit_s = time_since_state_change
		events.append("cascade_stop_all_except_pcu")

	if inputs.get("operator_clear_fault", false):
		fault_reason = ""
		_transition(State.OFF, events)

func _tick_e_stop(delta: float) -> void:
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	die_pressure_psi = 0.0
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	melt_temp = move_toward(melt_temp, 25.0, 0.5 * delta)
	die_face_state = DieFaceState.OFF

# =============================================================================
# HELPERS
# =============================================================================
func _drift_melt_temp_toward(target: float, delta: float) -> void:
	melt_temp = move_toward(melt_temp, target, config.melt_temp_drift_per_s * delta)

func get_die_face_state() -> int:
	return die_face_state

func _evaluate_die_face_state() -> void:
	if state == State.OFF or state == State.IDLE or state == State.FAULT or state == State.EMERGENCY_STOP:
		die_face_state = DieFaceState.OFF
		return
	var target := config.melt_temp_setpoint if config else 230.0
	if melt_temp < target - DIE_FACE_COLD_OFFSET_C:
		die_face_state = DieFaceState.TE_KOUD
	elif melt_temp > target + DIE_FACE_HOT_OFFSET_C:
		die_face_state = DieFaceState.TE_HEET
	else:
		die_face_state = DieFaceState.GOED_GEHARD

func _transition(new_state: State, events: Array[String]) -> void:
	var old := state
	state = new_state
	time_since_state_change = 0.0
	# Reset the lump-emit clock so a fresh fault state emits its first lump
	# 3 s in (not stalled because the tracker still holds the old high time).
	_last_lump_emit_s = -100.0
	events.append("state_changed:%d:%d" % [old, new_state])

# ── Queries ───────────────────────────────────────────────────────────────────
func get_state_name() -> String:
	return State.keys()[state]

func get_progress_percent_alarm() -> float:
	if state != State.VACUUM_ALARM:
		return 0.0
	return 1.0 - (vacuum_alarm_remaining_s / config.vacuum_alarm_grace_s)

# =============================================================================
# DEGASSING — six-stage pipeline with two vacuum ports
# =============================================================================
## Called from the upstream wash/dry line each tick to tell the extruder how
## much volatile content the incoming flake carries. Wet feed pushes this up;
## ink-heavy printed film + burned cellulose contamination raise it further.
func set_volatile_load(g_per_kg: float) -> void:
	volatile_load_g_per_kg = max(0.0, g_per_kg)

## Operator-tunable vacuum suction setpoints (0..1) for each stage. The
## Push-Feed-RPM and Max-Suction levers from the matrix both poke at these.
func set_primary_suction_pct(s: float) -> void:
	primary_suction_pct = clampf(s, 0.0, 1.0)
func set_secondary_suction_pct(s: float) -> void:
	secondary_suction_pct = clampf(s, 0.0, 1.0)

## Bypass primary (operator action: keep running when primary clogs). When
## true, primary stage extracts NOTHING and the whole volatile load lands
## on the secondary stage. If secondary saturates, gas slips through to the
## die and the defect rate climbs hard.
func set_bypass_primary(b: bool) -> void:
	bypass_primary = b

## Compute residence times per stage, run gas extraction at the two degas
## ports, update the pot-fill counters, and set the residual + defect-rate
## outputs. Called once per tick from _tick_running().
func _step_degassing(delta: float) -> void:
	# Total barrel transit scales INVERSELY with screw RPM (faster screw, less
	# residence per unit length). Reference is the nominal-RPM transit time.
	var rpm_frac : float = max(0.001, screw_rpm / max(config.screw_rpm_nominal, 1.0))
	residence_time_s = BARREL_TRANSIT_S_AT_NOMINAL / rpm_frac
	# Real die-pressure read (replaces the old 250 + 0.5×rpm proxy that the
	# scene controller forwarded). Standard non-Newtonian extruder rheology
	# says die_pressure ∝ viscosity × throughput. Both proxies are already in
	# the model: throughput_norm = throughput / nominal_throughput;
	# viscosity_factor = motor_torque_pct / motor_torque_base_pct (motor
	# torque already integrates zone temp shortfall + cold melt loading +
	# lump effects). A starved screw (throughput → 0) drops pressure toward
	# zero; an over-torqued cold screw spikes it well above the 280 psi base.
	var throughput_norm : float = 0.0
	if config.nominal_kg_per_h > 0.001:
		throughput_norm = throughput_kg_h / config.nominal_kg_per_h
	var torque_base : float = max(1.0, config.motor_torque_base_pct)
	var viscosity_factor : float = max(0.1, motor_torque_pct / torque_base)
	die_pressure_psi = DIE_PRESSURE_BASE_PSI * throughput_norm * viscosity_factor
	# Per-stage residence + degas extraction in serial order.
	per_stage_residence_s = []
	per_stage_extracted_g_s = []
	# Total volatile mass arriving this tick (g of gas in the slug of melt
	# crossing the barrel this delta). throughput_kg_h × delta_h × g/kg.
	var delta_h : float = delta / 3600.0
	var batch_volatile_g : float = throughput_kg_h * delta_h * volatile_load_g_per_kg
	var remaining_g : float = batch_volatile_g
	# Vacuum-flood capacity scaling — once the vacuum line is gunked up beyond
	# the dismantle threshold, every degas stage is effectively choked to 30 %
	# until someone calls clean_vacuum_lines().
	var flood_scale : float = VACUUM_FLOOD_CHOKED_CAPACITY_SCALE if flooded_dismantle_required else 1.0
	for stg in STAGES:
		var stage_id : int = int(stg["id"])
		var stage_residence_s : float = residence_time_s * float(stg["len_norm"])
		per_stage_residence_s.append(stage_residence_s)
		var base_cap : float = float(stg["degas_g_per_s"]) * flood_scale
		var suction : float = 0.0
		if stage_id == Stage.PRIMARY_DEGAS and not bypass_primary:
			suction = primary_suction_pct
		elif stage_id == Stage.SECONDARY_DEGAS:
			suction = secondary_suction_pct
		var extracted : float = 0.0
		if base_cap > 0.0 and suction > 0.0 and remaining_g > 0.0:
			# Gas pulled = min(remaining, capacity × suction × residence)
			var capacity_g : float = base_cap * suction * stage_residence_s
			extracted = min(remaining_g, capacity_g)
			remaining_g -= extracted
		per_stage_extracted_g_s.append(extracted / max(stage_residence_s, 0.001))
		# Pot fill: most extracted gas vents out, but a small fraction
		# condenses as backflush melt in the pot. Real-plant ratio operator-
		# anecdotal — small percentage that adds up over a long shift.
		if stage_id == Stage.PRIMARY_DEGAS:
			primary_pot_fill_kg = min(VACUUM_POT_CAPACITY_KG,
				primary_pot_fill_kg + extracted * 0.0008 / 1000.0)
		elif stage_id == Stage.SECONDARY_DEGAS:
			secondary_pot_fill_kg = min(VACUUM_POT_CAPACITY_KG,
				secondary_pot_fill_kg + extracted * 0.0008 / 1000.0)
	# Residual volatile = what survived to the die, normalised back to g/kg.
	var batch_kg : float = max(0.001, throughput_kg_h * delta_h)
	residual_volatile_g_per_kg = remaining_g / batch_kg
	# Pellet defect rate: 0 below OK threshold, 1 at scrap threshold, linear
	# between. Above scrap = full defect rate (the pellet stream is unusable).
	if residual_volatile_g_per_kg <= DEFECT_RESIDUAL_OK_G_PER_KG:
		pellet_defect_rate = 0.0
	elif residual_volatile_g_per_kg >= DEFECT_RESIDUAL_SCRAP_G_PER_KG:
		pellet_defect_rate = 1.0
	else:
		pellet_defect_rate = (residual_volatile_g_per_kg - DEFECT_RESIDUAL_OK_G_PER_KG) \
			/ (DEFECT_RESIDUAL_SCRAP_G_PER_KG - DEFECT_RESIDUAL_OK_G_PER_KG)

	# Vacuum flooding accumulator (operator-confirmed failure mode):
	# low-viscosity melt + high suction → thin melt creeps up the vacuum line
	# and accumulates as gunk. We use motor_torque_pct as a viscosity proxy:
	# low torque = thin melt = floodable. Build is slow — at full risky
	# conditions (high suction + thin melt) gunk reaches the dismantle
	# threshold in ~ (4 kg / 0.00012 kg/s) ≈ 555 min, but the proxy throttles
	# it heavily so the real-shift risk is the ~30-min figure operator quoted.
	var risky : bool = (primary_suction_pct > 0.8 or secondary_suction_pct > 0.8) \
		and motor_torque_pct < 70.0 \
		and motor_torque_pct > 0.0  # don't accumulate when machine is idle/off
	if risky:
		vacuum_line_gunk_kg += VACUUM_FLOOD_RATE_KG_PER_S * delta
	if not flooded_dismantle_required \
			and vacuum_line_gunk_kg >= VACUUM_FLOOD_DISMANTLE_THRESHOLD_KG:
		flooded_dismantle_required = true

# =============================================================================
# SEVEN-ZONE TEMP + MOTOR TORQUE
# =============================================================================
## Operator-tunable per-zone setpoint. zone_index ∈ [0, ZONE_COUNT). Out-of-
## range indices silently no-op (so HMI bugs don't crash the sim).
func set_zone_temp(zone_index: int, temp_c: float) -> void:
	if zone_index < 0 or zone_index >= ZONE_COUNT:
		return
	zone_temp_setpoints[zone_index] = clampf(temp_c, 0.0, 400.0)

## Convenience: read a zone setpoint by index (clamped). HMI/SCADA use this.
func get_zone_temp(zone_index: int) -> float:
	if zone_index < 0 or zone_index >= ZONE_COUNT:
		return 0.0
	return zone_temp_setpoints[zone_index]

## Average of the seven zone setpoints — used as the torque-shortfall reference.
func _avg_zone_setpoint() -> float:
	if zone_temp_setpoints.size() != ZONE_COUNT:
		return config.melt_temp_setpoint
	var total : float = 0.0
	for t in zone_temp_setpoints:
		total += t
	return total / float(ZONE_COUNT)

## Compute motor torque from average-zone-temp shortfall.
## Formula: baseline 60 % when running at nominal, +20 % per 10 °C of shortfall
## (i.e. melt is colder than setpoint → thicker → more screw torque). The
## actual melt temperature drifts toward `config.melt_temp_setpoint` (the
## global setpoint), so when the operator has dropped some zone setpoints
## below the global, the gap (avg_zone_setpoint < melt_temp) yields a positive
## shortfall against the colder mix the screw has to push through.
##
## Trip: > TORQUE_TRIP_PCT sustained for TORQUE_TRIP_SUSTAIN_S → FAULT.
## Lump passthrough: > LUMP_PASSTHROUGH_TORQUE_PCT → un-melted lumps go
## downstream; LaserFilter reads lump_passthrough_rate_g_s.
func _update_motor_torque(delta: float, events: Array[String]) -> void:
	var avg_setpoint : float = _avg_zone_setpoint()
	# Shortfall = how much colder the AVERAGE zone setpoint is vs actual melt.
	# Colder zones → thicker melt slug → harder for screw to push → higher torque.
	# We use (melt_temp - avg_setpoint) so dropping zones increases the gap.
	var shortfall_c : float = max(0.0, melt_temp - avg_setpoint)
	# Also penalise true cold melt (when melt_temp itself is below the global
	# setpoint, the screw works extra hard regardless of zones).
	var cold_melt_c : float = max(0.0, config.melt_temp_setpoint - melt_temp)
	var torque_from_shortfall : float = (shortfall_c + cold_melt_c) * (config.motor_torque_per_10c_below / 10.0)
	motor_torque_pct = config.motor_torque_base_pct + torque_from_shortfall

	# Trip accumulator: sustain time over TORQUE_TRIP_PCT.
	if motor_torque_pct >= TORQUE_TRIP_PCT:
		_torque_trip_accum_s += delta
	else:
		_torque_trip_accum_s = max(0.0, _torque_trip_accum_s - delta * 2.0)  # drain twice as fast

	if _torque_trip_accum_s >= TORQUE_TRIP_SUSTAIN_S:
		fault_reason = "motor_torque_trip"
		events.append("motor_torque_trip")
		_transition(State.FAULT, events)
		_torque_trip_accum_s = 0.0

	# Lump passthrough: above the threshold, un-melted lumps escape the screw
	# and reach the laser filter. Formula: (torque_pct - 95) * 5 g/s when > 95.
	if motor_torque_pct > LUMP_PASSTHROUGH_TORQUE_PCT:
		lump_passthrough_rate_g_s = (motor_torque_pct - LUMP_PASSTHROUGH_TORQUE_PCT) * 5.0
	else:
		lump_passthrough_rate_g_s = 0.0

# =============================================================================
# VACUUM-LINE FLOODING MAINTENANCE
# =============================================================================
## Operator/maintenance action: dismantle and clean the vacuum lines. Resets
## the gunk accumulator and clears the "dismantle required" flag so vacuum
## capacity returns to 100 %. Hooked to a maintenance task in a future turn.
func clean_vacuum_lines() -> void:
	vacuum_line_gunk_kg = 0.0
	flooded_dismantle_required = false

## ShiftClock calls at handover. Pot-fill counters are SHIFT-bounded for the
## SCADA report. The vacuum POT lid alarm now reads off these every tick — see
## _tick_running for the trigger.
func reset_shift_counters() -> void:
	primary_pot_fill_kg = 0.0
	secondary_pot_fill_kg = 0.0
