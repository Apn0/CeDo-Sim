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
## PREHEAT is appended, not inserted: the numeric values of the first eight are
## carried in saves, EventBus machine_state_changed payloads and recorded event
## streams, so renumbering them would silently rewrite history.
enum State { OFF, IDLE, STARTING, RUNNING, STOPPING, VACUUM_ALARM, FAULT, EMERGENCY_STOP, PREHEAT }
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

## STARTING: the screw ramps from standstill up to the operator's rpm setpoint
## at config.screw_rpm_min per START_RAMP_S (60 rpm in 3 s = 20 rpm/s), then the
## model is RUNNING. Operator 2026-09-25: a start "will ramp up to that 80. It
## will not be 80 instantly. Because there is the ramp up curve", and "it will
## ramp up in about ... three seconds to that 60 rpm". The RATE is derived from
## the 3 s to 60 (his number, kept against the raw archive's ~5 s, rulings file
## §E4); that the same rate carries on above 60 is a modelling choice. (Was 4 s
## from idle to NOMINAL, whatever the setpoint.)
const START_RAMP_S        : float = 3.0
## STOPPING → OFF decay. Time-constant; `rpm *= exp(-delta / STOP_DECAY_S)`
## so framerate-independent. 4 s ≈ the emulator's `*= 0.9` step at 0.5 s tick.
const STOP_DECAY_S        : float = 4.0
## Shop-floor ambient. Was a bare 25.0 literal in three places; the preheat
## rate is derived from it, so it has to be one number.
const AMBIENT_C : float = 25.0
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
var melt_temp        : float = AMBIENT_C     # °C — starts at ambient
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
# P3 stage B (2026-09-24, rulings §14): which pot pushed its lid at the last
# lid alarm ("primary" / "secondary" / "both"), and how long the vacuum has
# been gone — through VACUUM_ALARM and on into the FAULT it cascades to — for
# the lid's stickiness ("harder and harder, the longer the vacuum has been not
# in vacuum") and the melt's stiffness under the plamuurmes.
var vacuum_alarm_pot : String = ""
var vacuum_alarm_elapsed_s : float = 0.0

# Seven-zone temperature setpoints (operator-tunable). Built from
# config.zone_temp_setpoints if that's set with length == ZONE_COUNT,
# otherwise filled with config.melt_temp_setpoint on first tick / construction.
var zone_temp_setpoints : Array[float] = []

# Operator screw speed setpoint (rpm). A start ramps the screw to it and a stop
# leaves it alone. A NEW extruder starts at config.screw_rpm_min (60), not at
# nominal (operator ruling 2026-09-25): at nominal, a first start at the green
# button's temperature tripped 318 bar ~15 s in. It is not saved, so a reloaded
# world starts at 60 too. 0 means "no operator setpoint — run at nominal".
var screw_rpm_setpoint : float = 0.0
# Live actual temperatures for the 7 individual zones.
var actual_zone_temps : Array[float] = [113.0, 157.0, 184.0, 213.0, 215.0, 215.0, 215.0]

# Motor torque (% of design max). Computed from average zone-setpoint shortfall;
# in STOPPING it follows the rpm down instead (_coast_down_torque_pct).
# > TORQUE_TRIP_PCT for TORQUE_TRIP_SUSTAIN_S → FAULT (motor_torque_trip).
# > LUMP_PASSTHROUGH_TORQUE_PCT → un-melted lumps go downstream to the laser
# filter; the LaserFilter reads `lump_passthrough_rate_g_s` and ups its loading.
var motor_torque_pct          : float = 0.0
var _torque_trip_accum_s      : float = 0.0
var lump_passthrough_rate_g_s : float = 0.0
# STOPPING: the torque and screw rpm on the tick the stop was entered. The
# coast-down torque is scaled from them (_coast_down_torque_pct), so it depends
# on how far the screw has slowed, not on how many ticks that took.
var _stop_entry_torque_pct    : float = 0.0
var _stop_entry_rpm           : float = 0.0

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

## Melt-temperature sensitivity of the pre-meltfilter pressure, bar per °C of
## melt BELOW setpoint (negative above it). Least-squares fit of the 3A WinCC
## trends "Smeltdruk voor meltfilter" vs "Smelt temperatuur voor meltfilter"
## (src/data/plant/trends/3a_*.json, samples paired within 120 s, running only:
## P > 150 bar, T > 200 °C): slope -6.83 bar/°C, r = -0.76, n = 967. WEAK: the
## pressure series covers only 2023-06-28 08:41-09:54, and 948 of the 967
## pairs sit in one 5 °C bin. Refit when a longer pressure export exists.
const DIE_PRESSURE_BAR_PER_C : float = 6.83
## The pre-meltfilter level that slope was taken at (the operator's 280-bar safe
## maximum; 3A trend p50 271 / p95 280). The melt-set pressures scale by the
## same FRACTION per °C, 6.83 / 280 = 2.44 %/°C, as #275 did.
const MELT_FIT_LEVEL_BAR : float = 280.0
## The die plate's flow index: die_plate_bar ∝ throughput^n, a power-law melt
## through a fixed die. It IS LineFlow's screw's own LDPE n (a heuristic 0.35,
## no plant source), so the BluPort and the Quality terminal carry one die law
## (operator ruling 2026-09-25, docs/plant/operator_rulings_2026-09-25.md).
const _ScrewLaw := preload("res://src/sim/ExtruderScrew.gd")
const DIE_FLOW_INDEX : float = _ScrewLaw.POWER_LAW_N
## Melt viscosity relative to a melt at setpoint, from the fit above: 1.0 at
## setpoint, +2.44 % per °C colder. It scales the melt-set pressures here, and
## ExtruderMachine forwards it to the LaserFilter, where it scales the screen's
## own dMP too (operator 2026-09-25: "dMP rises too" when the melt runs colder).
## That puts the fit's 6.83 bar/°C on MP<MF itself, not only on its 25-bar
## melt-set part. Computed, so every state reads the current melt.
var melt_viscosity_factor : float:
	get:
		return maxf(0.1, 1.0 + (config.melt_temp_setpoint - melt_temp) * DIE_PRESSURE_BAR_PER_C / MELT_FIT_LEVEL_BAR)
# ── Melt pressures, BAR (2026-09-24) ─────────────────────────────────────────
# Replaces the single `die_pressure_psi` (base "280 psi", no source). Every plant
# source gives ~280 in BAR, and the one number fed two trips that sit at two
# different points of the line, so neither could fire. Operator rulings
# (docs/plant/operator_rulings_2026-09-24.md), line order screw -> laserfilter
# (MF1) -> degassing -> melt pump -> kopfilter (MF2) -> heetafslag:
#   * BEFORE the laserfilter (MP<MF) = the melt-set pressure AFTER it (MP>MF)
#     + the screen's own dMP. 280 bar there is a safe maximum, kept under the
#     318-bar emergency shutdown (LaserFilter, the trip authority).
#   * MP<PEL, the 160-bar pelletiser interlock, reads the dP ACROSS the kopfilter.
# The melt-set parts follow the rheology proxy — pressure ∝ throughput ×
# viscosity, the die plate ∝ throughput^DIE_FLOW_INDEX × viscosity (2026-09-25)
# — with viscosity read off the MELT temperature (DIE_PRESSURE_BAR_PER_C,
# #275's operator ruling), not motor torque: a zone drop raises torque, and
# pressure only once the melt really cools.
var mp_after_laserfilter_bar  : float = 0.0   # MP>MF: melt-set, after the screen
var die_plate_bar             : float = 0.0   # melt pump vs die plate, out of the kopfilter
# Filter dPs, mirrored in by ExtruderMachine from the live LaserFilter / HeadFilter
# (0 while not producing, or with no filter placed).
var laserfilter_dp_bar        : float = 0.0   # dMP-MF1
var kopfilter_dp_bar          : float = 0.0   # dP across the kopfilter pack
# Derived readouts (_refresh_line_pressures):
var mp_before_laserfilter_bar : float = 0.0   # MP<MF = after + dMP
var kopdruk_bar               : float = 0.0   # into the kopfilter (MD_vor_SF2) = die plate + pack dP
var mp_pel_bar                : float = 0.0   # MP<PEL = kopfilter dP (operator ruling)

var die_face_state : int = DieFaceState.OFF
var pelletizer : PelletizerModel = null

# ── Construction ──────────────────────────────────────────────────────────────
func _init(cfg: ExtruderConfig) -> void:
	config = cfg
	# Initialise per-zone setpoints. If the config supplies a properly sized
	# array we adopt it; otherwise every zone inherits the global
	# `melt_temp_setpoint` and the operator can drop individual zones later
	# via set_zone_temp() (e.g. to avoid burning paper/cellulose).
	if config != null:
		screw_rpm_setpoint = config.screw_rpm_min
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
	# P3 stage B: the operator lifted the melt block out of a pot (MeltBlock via
	# VacuumPotService.take_block). Any state — a pot can be cleaned in FAULT too.
	if inputs.has("pot_emptied"):
		var emptied : String = String(inputs["pot_emptied"])
		if emptied == "primary" or emptied == "both":
			primary_pot_fill_kg = 0.0
		if emptied == "secondary" or emptied == "both":
			secondary_pot_fill_kg = 0.0
		events.append("pot_emptied:" + emptied)

	match state:
		State.OFF:
			_tick_off(delta)
			if inputs.get("clean_vacuum_lines", false):
				clean_vacuum_lines()
				events.append("vacuum_lines_cleaned")
			elif inputs.get("preheat_on", false):
				_transition(State.PREHEAT, events)
			elif inputs.get("start_production", false):
				_route_start_request(events)
		State.IDLE:
			_tick_idle(delta)
			if inputs.get("clean_vacuum_lines", false):
				clean_vacuum_lines()
				events.append("vacuum_lines_cleaned")
			elif inputs.get("preheat_on", false):
				_transition(State.PREHEAT, events)
			elif inputs.get("start_production", false):
				_route_start_request(events)
		State.STARTING:
			_tick_starting(delta, inputs, events)
			# Operator can abort mid-ramp; falls through to STOPPING
			if inputs.get("stop_production", false):
				_transition(State.STOPPING, events)
			elif is_equal_approx(screw_rpm, _setpoint_rpm()):
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
		State.PREHEAT:
			_tick_preheat(delta, events)
			# The green button only works once the display block is green.
			if inputs.get("start_production", false) and preheat_ready():
				_transition(State.STARTING, events)
			elif inputs.get("stop_production", false):
				_transition(State.OFF, events)
		State.VACUUM_ALARM:
			_tick_vacuum_alarm(delta, inputs, events)
		State.FAULT:
			_tick_fault(delta, inputs, events)
			if inputs.get("clean_vacuum_lines", false):
				clean_vacuum_lines()
				events.append("vacuum_lines_cleaned")
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
	melt_temp = move_toward(melt_temp, AMBIENT_C, 0.5 * delta)
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	_set_melt_pressures(0.0, 1.0)
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	die_face_state = DieFaceState.OFF

## A start request from a cold barrel goes to PREHEAT, not STARTING.
##
## Before this existed, pressing start on a cold machine entered STARTING and
## tripped on motor torque 2 s later, every single time, with no operator action
## that could ever fix it: melt begins at ambient, _tick_off actively cools
## toward ambient, and nothing in OFF/IDLE turned the heaters on. Measured over
## a recorded shift, 81 % of starts on line 3A and 98 % on L1 went
## STARTING -> FAULT. Routing the request to PREHEAT is what the panel does in
## practice — the green button is simply not live until the block is green.
func _route_start_request(events: Array[String]) -> void:
	if preheat_ready():
		_transition(State.STARTING, events)
	else:
		_transition(State.PREHEAT, events)


## True once the barrel is hot enough that a start neither trips on torque nor
## pushes un-melted lumps into the laserfilter.
##
## Torque carries (setpoint - melt) * motor_torque_per_10c_below / 10 on top of
## the base, so both thresholds are derived from torque rather than picked:
## stay far enough below TORQUE_TRIP_PCT (the 110 % trip) AND below
## LUMP_PASSTHROUGH_TORQUE_PCT (95 %, where lumps start passing), each with the
## same 25 % margin, and take the warmer of the two.
##
## Until 2026-09-25 only the torque trip counted: green at 196.25 C on 3A/3B,
## which is 97.5 % torque, ABOVE the lump point. Measured
## (probe_warm_restart_pressure, section J): a warm restart pressed the moment
## the block went green reached RUNNING at 95.7 % torque, passed 3.4 g/s of
## lumps, caked the screen and tripped 318 bar 3.3 s after the green button;
## green at 196.75 C passed none (MP<MF peak 182 bar). Operator ruling
## 2026-09-25: the green button also waits until the screw passes no lumps,
## with the same margin. Green is now 201.875 C (13.1 C under 215).
func preheat_ready() -> bool:
	return melt_temp >= _preheat_ready_temp()


func _preheat_ready_temp() -> float:
	var per_c : float = maxf(0.001, config.motor_torque_per_10c_below / 10.0)
	# The cold-melt deficit that still fits under a torque limit, with a 25 %
	# margin so a brief ramp excursion cannot cross it.
	var trip_deficit_c : float = (TORQUE_TRIP_PCT - config.motor_torque_base_pct) / per_c * 0.75
	var lump_deficit_c : float = (LUMP_PASSTHROUGH_TORQUE_PCT - config.motor_torque_base_pct) / per_c * 0.75
	var allowed_deficit_c : float = maxf(0.0, minf(trip_deficit_c, lump_deficit_c))
	return config.melt_temp_setpoint - allowed_deficit_c


## 0 .. 1 warm-up progress, for the HMI block that goes green.
func preheat_progress() -> float:
	var lo : float = AMBIENT_C
	var hi : float = _preheat_ready_temp()
	if hi <= lo:
		return 1.0
	return clampf((melt_temp - lo) / (hi - lo), 0.0, 1.0)


## Barrel warm-up. Heaters on, screw stopped, no feed.
##
## Rate is derived from config.preheat_min_s so the documented duration is the
## single source of truth: Cedo-PROD-SWI-042 p4 step 19 says extruder start-up
## "duurt altijd minimaal 30 minuten, in deze opwarm tijd" — always at least 30
## minutes of warm-up. That step also records "Nog SWI maken opstarten
## extruders", i.e. no dedicated extruder start-up SWI exists, so step 19 is the
## authority for this number.
##
## Deliberately NOT modelled on the 15 s "voorverwarmknop" in SWI-048/049: those
## documents are "Opstarten sorteerlijn", the SORTING LINE. ExtruderMachine.gd
## used to cite SWI-049 for the extruder's startup; that citation was wrong.
func _tick_preheat(delta: float, events: Array[String]) -> void:
	var was_ready := preheat_ready()
	var span_c : float = maxf(1.0, config.melt_temp_setpoint - AMBIENT_C)
	var rate : float = span_c / maxf(1.0, config.preheat_min_s)
	melt_temp = move_toward(melt_temp, config.melt_temp_setpoint, rate * delta)
	screw_rpm = 0.0
	throughput_kg_h = 0.0
	_set_melt_pressures(0.0, 1.0)
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	die_face_state = DieFaceState.OFF
	if not was_ready and preheat_ready():
		events.append("preheat_ready")


func _tick_idle(delta: float) -> void:
	# Screw spinning at idle rpm, no feed, melt held at setpoint. Live
	# rheology/lump readings stay at zero — no production = no die pressure,
	# no torque load, no lump passthrough. Without these the gauges would
	# carry stale post-RUN values from before the operator paused production.
	screw_rpm = config.screw_rpm_idle
	throughput_kg_h = config.idle_kg_per_h
	_set_melt_pressures(0.0, 1.0)
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)
	die_face_state = DieFaceState.OFF

func _tick_running(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# The screw runs at the operator's setpoint, which a stop does not change
	# (operator 2026-09-25). There used to be an idle -> nominal ramp here over
	# startup_ramp_s, timed off the LIFETIME runtime_s: a model's first start
	# re-ramped from idle whatever the setpoint, and every later start ran on at
	# nominal flow. Measured 2026-09-25 (probe_warm_restart_pressure): a restart
	# at the preheat-ready melt then tripped 318 bar 4.3-4.8 s after the green
	# button, and nothing the operator set could change that.
	_drive_screw_to_setpoint(delta)
	for i in range(min(actual_zone_temps.size(), zone_temp_setpoints.size())):
		actual_zone_temps[i] = move_toward(actual_zone_temps[i], zone_temp_setpoints[i], 1.5 * delta)

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
	# Computed BEFORE _step_degassing so everything that tick reads the
	# CURRENT torque (the melt pressures themselves follow melt temperature since
	# 2026-09-24 — see _step_degassing).
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
		vacuum_alarm_pot = _pots_at_capacity()
		vacuum_alarm_elapsed_s = 0.0
		_transition(State.VACUUM_ALARM, events)
		return
	# (b) Back-compat: explicit `vacuum_lost` input still triggers (manual
	# operator-side trigger, e.g. a vacuum-line break).
	if inputs.get("vacuum_lost", false):
		fault_reason = "vacuum_lost_input"
		_transition(State.VACUUM_ALARM, events)

## Standstill -> the operator's setpoint at 20 rpm/s (60 rpm in START_RAMP_S,
## operator 2026-09-25). Material flows during the ramp in proportion to the screw.
func _tick_starting(delta: float, _inputs: Dictionary, events: Array[String]) -> void:
	# Linear ramp to the setpoint, from standstill — or, on a restart during the
	# coast-down, from wherever the screw still is. The per-tick step keeps
	# consumers (RotatingMechanism) smooth.
	var rate : float = _min_rpm() / maxf(0.01, START_RAMP_S)
	screw_rpm = move_toward(screw_rpm, _setpoint_rpm(), rate * delta)
	# The flow follows the screw, the same law as RUNNING: 0 at standstill.
	throughput_kg_h = _flow_at_rpm(screw_rpm)
	if pelletizer != null:
		pelletizer.tick(delta, true)
		throughput_kg_h *= pelletizer.get_throughput_multiplier()
	_drift_melt_temp_toward(config.melt_temp_setpoint, delta)
	_evaluate_die_face_state()
	# Motor torque comes online with the screw so the SCADA chart shows a
	# realistic surge during start-up rather than a flat 0 → step.
	_update_motor_torque(delta, events)
	# The melt pressures climb with the flow the ramp moves. The model raises no
	# pressure fault of its own here; the laserfilter's 318-bar trip and the
	# 160-bar MP<PEL interlock (ExtruderMachine) are armed in STARTING.
	_set_melt_pressures_from_flow()

## Time-constant decay (rpm *= exp(-delta / STOP_DECAY_S)). Frame-rate
## independent and matches the emulator's `*= 0.9` decay step at 0.5 s tick.
## Production continues at the residual rpm fraction so downstream catches
## the tail-end material; no new lumps are emitted (melt pressures follow the flow
## down, the motor torque follows the rpm down from where the stop began).
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
	# Not _update_motor_torque(): that runs the 110 % trip accumulator, and a
	# coasting screw is already stopping.
	motor_torque_pct = _coast_down_torque_pct()
	_set_melt_pressures_from_flow()
	# Lump passthrough stops as the screw stops — no fresh un-melted material.
	lump_passthrough_rate_g_s = 0.0

func _tick_vacuum_alarm(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# Production CONTINUES but a clock is ticking. Operator must fix vacuum
	# within grace period or the cascade fires.
	if time_since_state_change <= 0.1:
		vacuum_alarm_remaining_s = config.vacuum_alarm_grace_s

	vacuum_alarm_remaining_s -= delta
	vacuum_alarm_elapsed_s += delta
	# Screw + throughput unchanged during alarm — sim still produces. They used
	# to be forced to NOMINAL here, which the comment above never said: a line
	# the operator runs at 60 or 80 rpm jumped to 110 rpm and full flow the
	# moment a pot lid popped. Same law as RUNNING now.
	_drive_screw_to_setpoint(delta)
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
		# P3 stage B: a pot whose lid the melt pushed open cannot hold vacuum
		# until it is EMPTIED (the mini-game) — the hold-E shortcut alone no
		# longer clears a lid alarm; it still clears the manual vacuum_lost.
		if not pots_below_capacity():
			events.append("vacuum_restore_refused_pot_full")
		else:
			# Operator addressed the alarm — clear the cause string so the SCADA
			# "fault_reason" chip drops back to grey on the next push. Without this
			# the dashboard would keep painting the chip alarm-red (e.g. carrying
			# "vacuum_lost_input") well after the line resumed RUNNING.
			fault_reason = ""
			vacuum_alarm_pot = ""
			vacuum_alarm_elapsed_s = 0.0
			_transition(State.RUNNING, events)
			events.append("vacuum_alarm_cleared")
			return

	if vacuum_alarm_remaining_s <= 0.0:
		# fault_reason is preserved from the original VACUUM_ALARM trigger
		# (e.g. "vacuum_lid_pushed_open"); the cascade name is the same regardless.
		_transition(State.FAULT, events)
		events.append("vacuum_cascade_failure")

func _tick_fault(delta: float, inputs: Dictionary, events: Array[String]) -> void:
	# P3 stage B: the lid keeps getting stickier through the FAULT a lid alarm
	# cascaded into (VacuumPotService.lid_pull_required_s reads this).
	if fault_reason.begins_with("vacuum"):
		vacuum_alarm_elapsed_s += delta
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
	_set_melt_pressures(0.0, 1.0)   # screw stopped → no flow → no head pressure
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
	_set_melt_pressures(0.0, 1.0)
	motor_torque_pct = 0.0
	lump_passthrough_rate_g_s = 0.0
	melt_temp = move_toward(melt_temp, AMBIENT_C, 0.5 * delta)
	die_face_state = DieFaceState.OFF

# =============================================================================
# HELPERS
# =============================================================================
func _drift_melt_temp_toward(target: float, delta: float) -> void:
	melt_temp = move_toward(melt_temp, target, config.melt_temp_drift_per_s * delta)

## The lowest screw speed the drive accepts (config.screw_rpm_min, 60).
func _min_rpm() -> float:
	return maxf(0.0, config.screw_rpm_min)

## Where a start ramps the screw to and RUNNING holds it: the operator's
## setpoint, which persists across stops. 0 means "no setpoint: nominal".
func _setpoint_rpm() -> float:
	return screw_rpm_setpoint if screw_rpm_setpoint > 0.0 else config.screw_rpm_nominal

## Melt output at a screw speed: nominal_kg_per_h at screw_rpm_nominal, in
## proportion (the law RUNNING has always applied to an operator setpoint).
func _flow_at_rpm(rpm: float) -> float:
	return config.nominal_kg_per_h * maxf(0.0, rpm) / maxf(config.screw_rpm_nominal, 1.0)

## RUNNING and VACUUM_ALARM: the screw moves toward the operator's setpoint at
## 25 rpm/s, and the flow follows the screw, times the pelletiser's knife-wear
## multiplier.
func _drive_screw_to_setpoint(delta: float) -> void:
	screw_rpm = move_toward(screw_rpm, _setpoint_rpm(), 25.0 * delta)
	throughput_kg_h = _flow_at_rpm(screw_rpm)
	if pelletizer != null:
		pelletizer.tick(delta, true)
		throughput_kg_h *= pelletizer.get_throughput_multiplier()

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
	if new_state == State.STOPPING:
		# This tick's torque and rpm, from the state the stop was pressed in.
		_stop_entry_torque_pct = motor_torque_pct
		_stop_entry_rpm = screw_rpm
	if new_state == State.OFF or new_state == State.IDLE:
		vacuum_alarm_pot = ""              # the lid episode is over either way
		vacuum_alarm_elapsed_s = 0.0
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

## P3 stage B: no pot at capacity — the condition for a vacuum to be restorable.
func pots_below_capacity() -> bool:
	return primary_pot_fill_kg < VACUUM_POT_CAPACITY_KG \
		and secondary_pot_fill_kg < VACUUM_POT_CAPACITY_KG

func _pots_at_capacity() -> String:
	var p_full : bool = primary_pot_fill_kg >= VACUUM_POT_CAPACITY_KG
	var s_full : bool = secondary_pot_fill_kg >= VACUUM_POT_CAPACITY_KG
	if p_full and s_full:
		return "both"
	if p_full:
		return "primary"
	if s_full:
		return "secondary"
	return ""

# =============================================================================
# MELT PRESSURES (bar) — see the field block near the top
# =============================================================================
## `throughput_norm` = throughput / nominal and `melt_factor` = the melt
## temperature term (`melt_viscosity_factor`): both 1.0 at nominal,
## throughput 0.0 with the screw stopped.
## MP>MF stays proportional to the flow. The die plate is a power-law die,
## ∝ throughput^n with LineFlow's screw's own n (DIE_FLOW_INDEX): one die law
## in both models (operator ruling 2026-09-25,
## docs/plant/operator_rulings_2026-09-25.md). Both arguments are required on
## purpose: a one-argument `_set_melt_pressures(q * m)` from before 2026-09-25
## would compute pow(q·m, n), quietly wrong, so it must fail to compile.
func _set_melt_pressures(throughput_norm: float, melt_factor: float) -> void:
	var q : float = maxf(0.0, throughput_norm)
	var m : float = maxf(0.0, melt_factor)
	mp_after_laserfilter_bar = config.mp_after_laserfilter_nominal_bar * q * m
	die_plate_bar = config.die_plate_nominal_bar * pow(q, DIE_FLOW_INDEX) * m
	_refresh_line_pressures()

## The melt-set pressures for the CURRENT flow and melt: throughput / nominal
## and melt_viscosity_factor. Every state in which melt moves calls this —
## RUNNING and VACUUM_ALARM through _step_degassing, STARTING and STOPPING
## directly — so a pressure is a function of the flow it reads, never of the
## previous tick's pressure.
##
## 2026-09-25 — STARTING / STOPPING used to call `_scale_melt_pressures(rpm_frac)`,
## which multiplied the LAST tick's pressures by the rpm fraction every tick. On
## the way down they fell as the product of every rpm fraction so far, and the
## tick size set how fast: 1.2 s into a stop (rpm 0.74 of nominal) the die plate
## read 0.142 of running at 0.1 s ticks and 0.024 at 0.05 s ticks, against 0.747
## for the flow. On the way up they started from the 0 that OFF / PREHEAT / IDLE
## park them at, so they read 0 bar for the whole ramp. Guarded by
## test_extruder_ramp_pressures.
func _set_melt_pressures_from_flow() -> void:
	var throughput_norm : float = 0.0
	if config.nominal_kg_per_h > 0.001:
		throughput_norm = throughput_kg_h / config.nominal_kg_per_h
	_set_melt_pressures(throughput_norm, melt_viscosity_factor)

## ExtruderMachine mirrors the live filter dPs in every tick (bar). The laser
## filter stays the authority for its own 318-bar trip — it sums the same two
## terms itself (LaserFilter.mp_before_filter_bar()); this copy is the readout
## the HMI, SCADA and Storingstabel read off the model.
func set_filter_pressure_drops(laser_dp_bar: float, kop_dp_bar: float) -> void:
	laserfilter_dp_bar = maxf(0.0, laser_dp_bar)
	kopfilter_dp_bar = maxf(0.0, kop_dp_bar)
	_refresh_line_pressures()

func _refresh_line_pressures() -> void:
	mp_before_laserfilter_bar = mp_after_laserfilter_bar + laserfilter_dp_bar
	kopdruk_bar = die_plate_bar + kopfilter_dp_bar
	# Operator ruling 2026-09-24: MP<PEL, the 160-bar interlock (EREMA manual
	# 4.3.7), is the pressure difference across the kopfilter (MF2).
	mp_pel_bar = kopfilter_dp_bar

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
	# Melt-set pressures (bar). MP>MF ∝ viscosity × throughput; the die plate is
	# a power-law die, ∝ viscosity × throughput^DIE_FLOW_INDEX (operator ruling
	# 2026-09-25). throughput_norm = throughput / nominal.
	# Viscosity follows the MELT temperature at the slope the plant's own data
	# shows (DIE_PRESSURE_BAR_PER_C, as a fraction of MELT_FIT_LEVEL_BAR). A
	# starved screw (throughput → 0) drops both toward zero. The filter dPs add
	# on top of these in _refresh_line_pressures().
	#
	# 2026-09-24 (#275) — viscosity used to be motor_torque_pct /
	# motor_torque_base_pct, and torque carries the ZONE-SETPOINT shortfall (avg
	# zone setpoint vs melt), not the melt itself. Operator ruling 2026-09-24:
	# pressure follows melt temperature only — a zone drop raises torque as
	# before (and torque still drives the lumps into the laserfilter), and
	# pressure only once the melt really cools.
	_set_melt_pressures_from_flow()
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

## Read live actual zone temperature by index (clamped).
func get_actual_zone_temp(zone_index: int) -> float:
	if zone_index >= 0 and zone_index < actual_zone_temps.size():
		return actual_zone_temps[zone_index]
	return melt_temp

## The operator's rpm setpoint: no lower than screw_rpm_min (operator
## 2026-09-25: "the minimum value possible to set 60 rpm"; was 0, which meant
## "run at nominal"). The 250 top is unchanged and was not ruled on:
## test_screw_die_plate_bar drives 3B to ~174 rpm across its output band, above
## the config's screw_rpm_max 145 (source unknown).
func set_screw_rpm_setpoint(rpm: float) -> void:
	screw_rpm_setpoint = clampf(rpm, config.screw_rpm_min, maxf(config.screw_rpm_min, 250.0))

func set_primary_suction(pct: float) -> void:
	primary_suction_pct = clampf(pct, 0.0, 1.0)

func set_secondary_suction(pct: float) -> void:
	secondary_suction_pct = clampf(pct, 0.0, 1.0)

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

## Motor torque while the screw coasts down in STOPPING: the torque on the tick
## the stop was entered, times rpm / the rpm it was entered at.
##
## From the plant, not from feel. The raw EREMA archive for 3A and 3B logs
## load_extruder (the "belasting" the BluPort, the HMI and SCADA show from this
## field) and speed_extruder in the same ~5 s cycle. 83 stops from a steady run,
## 17 samples caught mid-stop: load / entry load = 0.969 x rpm / entry rpm, mean
## error 0.098 of the entry load; a held load is off by 0.369, rpm^2 by 0.237.
## tools/audit/fit_stop_load_vs_rpm.py, docs/audit/extruder_stop_torque_2026-09-25.md.
##
## It used to be `motor_torque_pct *= rpm_frac` every tick, which follows the
## product of every tick's fraction: 1.2 s into a stop from nominal it read
## 0.142 of running at 0.1 s ticks and 0.024 at 0.05 s ticks. screw_rpm decays as
## exp(-t / STOP_DECAY_S), so this ratio depends on time alone. Guarded by
## test_extruder_stop_torque.
func _coast_down_torque_pct() -> float:
	if _stop_entry_rpm <= 0.001:
		return 0.0
	return _stop_entry_torque_pct * clampf(screw_rpm / _stop_entry_rpm, 0.0, 1.0)

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
