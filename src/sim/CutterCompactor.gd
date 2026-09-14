extends RefCounted
class_name CutterCompactor

## Task #44 — Cutter-Compactor (a.k.a. "Schneidverdichter" / agglomerator) THERMO sim.
##
## Pure simulation logic for ONE cutter-compactor — NO scene-tree dependency, in the
## same mould as ExtruderModel.gd and MaterialBatch.gd (both extend RefCounted). A
## scene controller (or LineFlow, see the REGISTRATION snippet) constructs one, sets
## disc_rpm + dosing_gate from the HMI, calls tick(delta) every SimTick (10 Hz), and
## reads back pot_temperature / motor_amps / state for the HMI and any visuals.
##
## WHAT IT IS (real machine): loose, fluffy LDPE film flake is thrown against the pot
## wall by a fast rotating disc/knife. Friction heats the flake to just below its melt
## point so it shrinks, balls up ("agglomerates") and densifies — feeding the extruder
## screw a dense, free-flowing crumb instead of low-bulk-density fluff. The whole craft
## is keeping the POT TEMPERATURE in a narrow window with the dosing gate.
##
## THERMODYNAMICS (lumped single-capacity model, deliberately simple + deterministic):
##
## FRICTION-ONLY HEAT SOURCE — there are NO external heating elements on the real
## machine. Every joule of heat in the pot comes from the rotating disc/knives doing
## mechanical work on the flake. The model encodes that as the assertion:
##         friction_heat_W = FRICTION_GAIN · rpm² · (idle + load) · knife_dullness
##   * No band heaters, no jacket steam, no preheat. Cooling is passive (jacket loss).
##   * If the knives go DULL (#knife_sharpness), the friction multiplier climbs —
##     more work for the same throughput, kW spikes, operator reaches for the
##     emergency water injection. That cascade is the operator's whole job.
##
##     friction_heat_W  ∝  disc_rpm²  ·  (idle + load·dosing_gate) · KNIFE_MULT
##     cooling_W        =  (pot_T − ambient) · COOL_COEF
##     evap_sink_W      =  moisture flashing off the warm flake (a real heat sink)
##                          → gated by air_flush_on; with the flush OFF the steam
##                          re-condenses ("sauna effect") and adds back to the
##                          internal thermal load — quality + motor both suffer.
##     dT/dt            =  (friction_heat − cooling − evap_sink) / THERMAL_MASS
##
## Heat scales with the SQUARE of rpm (friction power ≈ torque·ω, torque itself rising
## with ω) and with how much flake is in the pot (the dosing gate): more flake = more
## rubbing surfaces = more heat, up to a point, but also more cold mass + moisture to
## warm, which is why a slammed-open gate can actually STALL a cold pot.
##
## SETPOINT BAND — the operator targets pot_temperature 10–15 °C BELOW the polymer
## melt point. For LDPE (the only resin this plant runs) melt is ~115 °C, so the
## target band is 100–105 °C ("sticky, not melted"). The constants
## TEMP_BELOW_MELT_C_MIN/MAX encode that distance for future per-polymer use.
##
## BEHAVIOUR BANDS (the operator's whole job, per the task spec):
##   • pot_T < 90 °C ............ UNDERHEATED. Flake hasn't softened, so it bridges the
##                               outlet and the screw_fill_efficiency DROPS (starved
##                               extruder). efficiency falls off linearly below 90.
##   • 100 ≤ pot_T ≤ 105 °C ..... SWEET SPOT. screw_fill_efficiency == 1.0 → the
##                               machine yields its MAXIMUM throughput.
##   • pot_T > 110 °C ........... OVERHEATED → "DONUT" STALL. The crumb fuses into one
##                               molten ring ("doughnut") that seizes the disc: motor
##                               RPM instantly drops to 0 and motor load spikes to the
##                               LOCKED-ROTOR current. Latches until reset() (crew
##                               clears the donut + the pot cools below the reset band).
##
## MASS CONSERVATION: feed() pours a MaterialBatch into the pot; tick() flashes off
## moisture with MaterialBatch.remove_water (a conserving side stream, returned to the
## caller so the plant ledger stays balanced) and discharges densified crumb at a rate
## gated by screw_fill_efficiency. Nothing is created or destroyed — see MaterialBatch.

# =============================================================================
# STATE MACHINE
# =============================================================================
enum State {
	OFF,          # disc stopped, cooling to ambient
	HEATING,      # running, pot below the sweet spot (screw underfilled)
	RUNNING,      # running in/above the underheat band, discharging crumb
	DONUT_STALL,  # overheated → fused ring seized the rotor (the signature fault)
}

# ── Behaviour-band thresholds (°C) — the numbers the spec calls out ───────────
const T_UNDERHEAT   : float = 90.0    # below this, screw fill efficiency drops
const T_SWEET_LOW   : float = 100.0   # sweet-spot band lower edge (max throughput)
const T_SWEET_HIGH  : float = 105.0   # sweet-spot band upper edge
const T_DONUT       : float = 110.0   # above this → Donut stall trips
const T_RESET_BELOW : float = 80.0    # pot must cool below this before a reset takes
const T_SEIZE       : float = 125.0   # operator anecdote: pot at 125 °C with motor OFF
                                       # → charge solidifies into a single block fused to
                                       # the knives → multi-day teardown to recover

# ── Setpoint-band geometry (relative to polymer melt point) ────────────────────
# Real operator rule: "10–15 °C below the polymer's melt point — sticky not melted".
# For LDPE (the only resin CeDo runs) melt point is ~115 °C, so the target band is
# 100–105 °C, which is exactly T_SWEET_LOW..T_SWEET_HIGH above. The constants are
# kept separate so future per-polymer configs can derive the same band from a
# different melt point (PA, PMMA, etc.) without re-hardcoding T_SWEET_*.
const TEMP_BELOW_MELT_C_MIN : float = 10.0   # minimum °C below melt point
const TEMP_BELOW_MELT_C_MAX : float = 15.0   # maximum °C below melt point
const LDPE_MELT_POINT_C     : float = 115.0  # reference resin

# ── Thermal model coefficients (tuned for a believable ~tens-of-seconds ramp) ──
const AMBIENT_C       : float = 25.0      # cold-start / soak temperature (°C)
const THERMAL_MASS    : float = 4200.0    # J/°C lumped heat capacity of pot + charge
const COOL_COEF       : float = 14.0      # W per °C above ambient (passive + jacket)
const FRICTION_GAIN   : float = 0.0025    # W per (rpm² · load-fraction) friction coeff —
														 # tuned so MODERATE rpm settles in the sweet
														 # spot (a usable operator window) while a
														 # slammed-open disc overheats into a Donut
const IDLE_LOAD_FRAC   : float = 0.18      # friction with an empty pot (disc vs air/walls)
const EVAP_LATENT_J_KG : float = 2_260_000.0  # J per kg of water flashed off (latent heat)
const EVAP_HEAT_FRAC   : float = 0.30      # frac of SURPLUS friction heat drying skims off
const NOMINAL_RPM      : float = 1500.0    # disc speed the machine is rated at

# ── Motor / electrical ────────────────────────────────────────────────────────
const MOTOR_IDLE_AMPS    : float = 22.0   # spinning, empty pot
const MOTOR_FULL_AMPS    : float = 95.0   # spinning, fully dosed, in the sweet spot
const LOCKED_ROTOR_AMPS  : float = 620.0  # seized-rotor inrush during a Donut stall
const RPM_SPINUP_PER_S   : float = 1800.0 # rpm/s the disc ramps toward its setpoint

# ── Throughput / process ────────────────────────────────────────────────────────
const DISCHARGE_KG_S  : float = 6.0       # crumb out at full fill efficiency + full gate
const POT_CAPACITY_KG : float = 60.0      # how much flake the pot holds before it backs up

# =============================================================================
# CONTROL INPUTS (driven by the HMI / LineFlow each tick)
# =============================================================================
var disc_rpm_setpoint : float = 0.0        # commanded disc speed (0 = motor off)
var dosing_gate       : float = 0.0        # 0..1 — how far the flake feed gate is open

# =============================================================================
# OPERATOR-ANECDOTE MECHANICS  (#A1 / #A2 / #A4)
# =============================================================================
# #A1 — Power-cap override + SOFTSTARTER trip (operator-confirmed mechanism)
#
# The compactor's documented limit is ~200 kW (manual ceiling). Operators on
# elite runs push the setpoint well above that to keep a wet feed compacting.
#
# REAL-WORLD TRIP MECHANISM (corrected this turn): the hardware-rated CIRCUIT
# BREAKER sits at 600+ kW and basically NEVER trips in practice. The real-world
# motor stop comes from the motor SOFTSTARTER — a PLC safeguard that integrates
# instantaneous overage above POWER_KW_SOFTSTARTER_BASELINE. When the integrated
# budget exceeds POWER_KW_SOFTSTARTER_BUDGET_KWS the motor is stopped.
#
# Operator-confirmed data points for the trip curve:
#   * 5 seconds at 300 kW → trip   ((300-240)·5 = 300 kW·s, exactly the budget)
#   * 3 seconds at 350 kW → trip   ((350-240)·~3 = 330 kW·s, just over budget)
#
# Recovery: below POWER_KW_SOFTSTARTER_BASELINE the budget DRAINS at
# SOFTSTARTER_DRAIN_KWS_PER_S kW·s/s, so brief spikes followed by cool draws
# don't carry over forever.
#
# Both the hardware breaker (instant, basically never) and the softstarter
# (gradual, common) set the legacy `breaker_tripped` flag so existing callers
# keep working. The new `softstarter_tripped` flag distinguishes the cause so
# the HMI can show the right reason on the alarm card.
#
# The power-cap slider's upper clamp is POWER_KW_BREAKER (== hardware ceiling,
# 600 kW) — the slider isn't the safety device, the softstarter is. Operator
# can set the cap anywhere up to the hardware ceiling; if they push too long
# the softstarter pulls the plug.
const POWER_KW_RATED                  : float = 200.0    # documented ceiling ("don't exceed")
const POWER_KW_HARDWARE_BREAKER       : float = 600.0    # mechanical breaker — basically never trips
# Back-compat alias. Existing code (and the set_power_cap_kw upper clamp) read
# POWER_KW_BREAKER as "the slider's hard max". We point it at the hardware
# breaker now (600 kW) — the softstarter is the real safety, not this number.
const POWER_KW_BREAKER                : float = POWER_KW_HARDWARE_BREAKER
const POWER_KW_SOFTSTARTER_BASELINE   : float = 240.0    # PLC accumulator threshold
const POWER_KW_SOFTSTARTER_BUDGET_KWS : float = 300.0    # trip when accumulator >= this (kW·s)
const SOFTSTARTER_DRAIN_KWS_PER_S     : float = 50.0     # drain rate below baseline (kW·s/s)
const POWER_KW_MIN                    : float = 30.0     # below this, motor stalls regardless of setpoint
const POWER_KW_RAMP_INCREMENT         : float = 5.0      # operator-facing step (manual procedure)
# Legacy — preserved for any external reader. The softstarter is integral, not
# a fixed-window timer, so this constant no longer drives the trip logic. Kept
# at 1.0 s so anyone reading it still sees a sensible "sustained-overdraw" hint.
const BREAKER_TRIP_HOLD_S             : float = 1.0
# Operator setpoint: caps the MAX kW the motor is allowed to draw before the
# controller chokes the disc RPM to stay under it. Default at the documented limit.
var power_cap_kw_setpoint    : float = POWER_KW_RATED

# #A2 — Feed moisture coupling
# Wet feed forces the compactor into doing evaporation work BEFORE it can
# compact. Higher moisture → more friction kW for the same throughput. Set by
# the upstream dewatering screw each tick; when the de-water unit is poorly
# tuned (or the operator's anecdote: "couldn't adjust the plus-mark"), this
# climbs and the compactor's draw climbs to match.
var feed_moisture_pct        : float = 4.0     # % water by mass in incoming flake (4 % typical, 12 % wet)
const MOISTURE_KW_PER_PCT    : float = 2.5     # extra kW the motor must do per % moisture above DRY
const MOISTURE_DRY_BASELINE  : float = 4.0     # at-and-below this, no penalty

# Live derived
var power_kw                 : float = 0.0     # live electrical input (motor_amps × line voltage / 1000)
var breaker_tripped          : bool  = false   # legacy field — true on EITHER hardware OR softstarter trip
var softstarter_tripped      : bool  = false   # NEW — true only when the PLC softstarter pulled the plug
# Live softstarter accumulator (kW·s). Integrates (power_kw - baseline) above
# baseline, drains at SOFTSTARTER_DRAIN_KWS_PER_S below it. Crossing
# POWER_KW_SOFTSTARTER_BUDGET_KWS trips the motor. Exposed for HMI gauges.
var softstarter_budget_kws   : float = 0.0

# Cumulative shift-waste readout for the laser-filter RPM-strategy tradeoff
# (#A3). Total kg of lumps the upstream laser filter ejected this shift, so
# the SCADA can show "your low-RPM call saved X kg".
var lumps_kg_this_shift      : float = 0.0

# =============================================================================
# KNIFE WEAR  (#PCU-K)
# =============================================================================
# Sharp knives are the operator's whole job per the manual. As they dull they
# don't CUT the flake — they DRAG it — and the friction work to densify the
# same kg of charge climbs. The motor compensates by drawing more kW, the pot
# climbs toward overheating, the operator reaches for the emergency water
# injection, and if they ignore the warning long enough the pot seizes.
#
# Decay is per RUNNING second (not wall-clock), so a paused or stopped
# compactor doesn't shed sharpness. A full set lasts ~25 operating hours
# under nominal load (matches the typical sharpen-cycle observed by maintenance).
const KNIFE_DECAY_PER_H_NOMINAL   : float = 0.04   # 1/h at nominal load — 25 h to dull
const KNIFE_FRICTION_MULT_FRESH   : float = 1.00
const KNIFE_FRICTION_MULT_DULL    : float = 1.65   # +65 % friction work when fully dull
const KNIFE_SHARPEN_TIME_S        : float = 1800.0 # 30 min off-line for the sharpen task
var knife_sharpness              : float = 1.00    # 1.0 = brand-new, 0.0 = needs replacement
var _knife_sharpen_remaining_s   : float = 0.0     # >0 while a sharpen task is running

# =============================================================================
# AIR-FLUSH MODULE  (#PCU-AF)
# =============================================================================
# Real machine: a small extractor fan that pulls the flash-steam out of the
# pot HEAD-SPACE so it doesn't re-condense onto cooler incoming flake. With
# the flush OFF you get the "sauna effect" — steam loops back into the
# charge as liquid water, the evap heat sink stops being a real heat sink
# (energy is just shuffled around inside the pot), motor load climbs, and
# the resulting pellet has more residual moisture (downstream quality hit).
const AIR_FLUSH_EVAP_BOOST      : float = 1.00    # with flush ON, full latent skim
const AIR_FLUSH_EVAP_PENALTY    : float = 0.25    # with flush OFF, only 25 % of evap energy leaves
var air_flush_on                : bool  = true    # operator setpoint; default ON

# =============================================================================
# EMERGENCY WATER INJECTION  (#PCU-EWI)
# =============================================================================
# The "fire extinguisher" of the compactor — a brief water spray straight
# into the pot that converts surplus friction heat into steam (cooling the
# charge instantly). Documented as a LAST RESORT; routine use means the
# process is unstable. Each use bumps a per-shift counter; above
# EWI_INSTABILITY_THRESHOLD the SCADA flags the compactor as unstable for
# the shift report. Counter resets on shift handover.
const EWI_COOL_C_PER_USE        : float = 18.0    # °C drop per injection event
const EWI_COOLDOWN_S            : float = 12.0    # min seconds between uses (pot needs to re-soak)
const EWI_INSTABILITY_THRESHOLD : int   = 5       # uses/shift above which we flag "unstable"
var emergency_water_uses_shift  : int   = 0
var _ewi_cooldown_remaining_s   : float = 0.0
var process_unstable_flag       : bool  = false

# =============================================================================
# LIVE STATE (read back by the HMI / visuals / tests)
# =============================================================================
var state           : State          = State.OFF
var pot_temperature : float          = AMBIENT_C    # the integrated internal temperature
var disc_rpm        : float          = 0.0          # live disc speed after spin-up ramp
var motor_amps      : float          = 0.0          # live motor current draw (A)
var charge          : MaterialBatch  = MaterialBatch.new()  # flake currently in the pot
var screw_fill_efficiency : float    = 0.0          # 0..1 — how well the screw is filled
var throughput_kg_s : float          = 0.0          # densified crumb leaving this tick (smoothed)
var stalled         : bool           = false        # convenience mirror of DONUT_STALL

# Identity (for EventBus messages + the HMI). Defaults to the catalog id.
var machine_id : String = "cutter_compactor"

# Internal bookkeeping
var _last_friction_w : float = 0.0
var _last_cooling_w  : float = 0.0
var _time_in_state   : float = 0.0

# ── Conservation ledger (kg) — mirrors LineFlow's fed/gran/water bookkeeping so a
# test (or the plant ledger) can prove nothing is silently created or destroyed:
#   total_fed_kg == charge.mass_kg + discharged_kg + water_removed_kg
# total_fed counts EVERYTHING that entered the pot (feed() AND the gate trickle).
var total_fed_kg       : float = 0.0   # all flake that ever entered the pot
var discharged_kg      : float = 0.0   # densified crumb pulled out via discharge()
var water_removed_kg   : float = 0.0   # moisture flashed off (conserving side stream)

# =============================================================================
# SIGNALS — also broadcast on the EventBus autoload when present (see _emit_bus).
# A pure RefCounted can't be in the tree, so listeners can EITHER connect these
# directly OR (the project's convention) subscribe on the global EventBus.
# =============================================================================
signal state_changed(machine_id: String, old_state: int, new_state: int)
signal donut_stall_triggered(machine_id: String, pot_temp_c: float, locked_rotor_amps: float)
signal donut_stall_cleared(machine_id: String)

# =============================================================================
# CONSTRUCTION
# =============================================================================
func _init(id: String = "cutter_compactor") -> void:
	machine_id = id

# =============================================================================
# CONTROL API
# =============================================================================
## Start the motor: command a disc speed (defaults to nominal) and open the gate.
func start(rpm: float = NOMINAL_RPM, gate: float = 1.0) -> void:
	disc_rpm_setpoint = maxf(rpm, 0.0)
	dosing_gate = clampf(gate, 0.0, 1.0)

## Stop the motor (disc spins down, pot cools). Does NOT clear a latched Donut.
func stop() -> void:
	disc_rpm_setpoint = 0.0
	dosing_gate = 0.0

func set_rpm(rpm: float) -> void:
	disc_rpm_setpoint = maxf(rpm, 0.0)

func set_dosing_gate(g: float) -> void:
	dosing_gate = clampf(g, 0.0, 1.0)

# #A1 — operator-tunable power cap, intentionally NOT clamped to rated.
# Lets the operator set a cap above POWER_KW_RATED to push throughput on a
# wet/dirty feed. The upper clamp is the HARDWARE breaker (POWER_KW_BREAKER
# == POWER_KW_HARDWARE_BREAKER == 600 kW) — the slider is NOT the safety
# device. The motor SOFTSTARTER (integral budget, see POWER_KW_SOFTSTARTER_*)
# is what actually stops the motor; an operator who dials the cap to 400 kW
# and runs there will trip the softstarter long before they ever touch the
# 600 kW hardware breaker.
func set_power_cap_kw(kw: float) -> void:
	power_cap_kw_setpoint = clampf(kw, POWER_KW_MIN, POWER_KW_BREAKER)

# #A2 — upstream dewatering screw or wash-line module reports moisture here.
func set_feed_moisture_pct(pct: float) -> void:
	feed_moisture_pct = clampf(pct, 0.0, 30.0)

# #A1 — manual reset for a tripped breaker (after the operator has un-seized
# the pot per the existing Donut-stall reset protocol). Clears BOTH the
# legacy breaker flag and the softstarter state — including the integrated
# budget — so the motor starts the next run with a clean accumulator.
func reset_breaker() -> void:
	if breaker_tripped or softstarter_tripped:
		breaker_tripped = false
		softstarter_tripped = false
		softstarter_budget_kws = 0.0
		_emit_bus("machine_alarm_cleared", [machine_id, "SOFTSTARTER-TRIP"])
		_emit_bus("machine_alarm_cleared", [machine_id, "HARDWARE-BREAKER-TRIP"])

# Power-cap ramp helpers — the manual prescribes raising the cap in 5 kW steps
# while watching pot temperature climb. Operator HMI's up/down buttons should
# bind to these so the discrete clicks match the procedure.
func bump_power_cap_up_5kw() -> void:
	set_power_cap_kw(power_cap_kw_setpoint + POWER_KW_RAMP_INCREMENT)
func bump_power_cap_down_5kw() -> void:
	set_power_cap_kw(power_cap_kw_setpoint - POWER_KW_RAMP_INCREMENT)

# #PCU-AF — operator toggles the air-flush extractor fan from the HMI.
func set_air_flush(on: bool) -> void:
	air_flush_on = on

# #PCU-EWI — emergency water injection. Returns true if the spray fired,
# false if it's still on cooldown. Counter advances on every successful use;
# above EWI_INSTABILITY_THRESHOLD the unstable-flag latches for the shift.
func inject_emergency_water() -> bool:
	if _ewi_cooldown_remaining_s > 0.0:
		return false
	if state == State.DONUT_STALL or state == State.OFF:
		return false
	pot_temperature = maxf(AMBIENT_C, pot_temperature - EWI_COOL_C_PER_USE)
	emergency_water_uses_shift += 1
	_ewi_cooldown_remaining_s = EWI_COOLDOWN_S
	if emergency_water_uses_shift > EWI_INSTABILITY_THRESHOLD:
		process_unstable_flag = true
	return true

## ShiftClock calls this at handover. Resets the per-shift EWI counter and the
## instability flag (the new shift starts with a clean ledger).
func reset_shift_counters() -> void:
	emergency_water_uses_shift = 0
	process_unstable_flag = false
	lumps_kg_this_shift = 0.0

# #PCU-K — sharpen-knife task. Takes the compactor offline for
# KNIFE_SHARPEN_TIME_S seconds; on completion knife_sharpness resets to 1.0.
# Called by the operator HMI / maintenance task; ticks down in tick().
func start_sharpen_task() -> bool:
	if state != State.OFF:
		return false   # safety — operator must stop the motor first
	if _knife_sharpen_remaining_s > 0.0:
		return false   # already running
	_knife_sharpen_remaining_s = KNIFE_SHARPEN_TIME_S
	return true

func sharpen_task_progress_pct() -> float:
	if _knife_sharpen_remaining_s <= 0.0:
		return 1.0
	return clampf(1.0 - _knife_sharpen_remaining_s / KNIFE_SHARPEN_TIME_S, 0.0, 1.0)

## Pour a batch of flake into the pot (conserving — the batch is drained into the
## resident charge). Used by feed() from LineFlow's upstream connector.
func feed(batch: MaterialBatch) -> void:
	if batch == null or batch.is_empty():
		return
	total_fed_kg += batch.mass_kg
	charge.add(batch)

## Clear a latched Donut stall. The crew has cracked the fused ring out; this only
## "takes" once the pot has cooled below T_RESET_BELOW (you can't restart into a
## still-molten pot). Returns true if the reset succeeded.
func reset() -> bool:
	if state != State.DONUT_STALL:
		if breaker_tripped or softstarter_tripped:
			reset_breaker()
		return true
	if pot_temperature > T_RESET_BELOW:
		return false
	stalled = false
	reset_breaker()
	_set_state(State.OFF)
	donut_stall_cleared.emit(machine_id)
	_emit_bus("machine_alarm_cleared", [machine_id, "DONUT-STALL"])
	return true

# =============================================================================
# TICK — integrate temperature + run the state machine. Fixed delta from SimTick.
# Returns kg of water flashed off this tick (a conserving side stream the caller
# routes to the plant's water-removed counter, exactly like LineFlow does).
# =============================================================================
func tick(delta: float) -> float:
	delta = maxf(delta, 0.0)
	_time_in_state += delta
	# Cool-down + sharpen-task timers always advance regardless of state, so the
	# operator's wait clocks tick during OFF / DONUT_STALL too.
	if _ewi_cooldown_remaining_s > 0.0:
		_ewi_cooldown_remaining_s = max(0.0, _ewi_cooldown_remaining_s - delta)
	if _knife_sharpen_remaining_s > 0.0:
		_knife_sharpen_remaining_s = max(0.0, _knife_sharpen_remaining_s - delta)
		if _knife_sharpen_remaining_s == 0.0:
			knife_sharpness = 1.0                       # crew finished — fresh knives

	# ── 1. DONUT STALL is a hard latch: rotor seized, locked-rotor current ────────
	if state == State.DONUT_STALL:
		disc_rpm = 0.0                                   # instantly 0 — the ring jammed it
		motor_amps = LOCKED_ROTOR_AMPS                   # spike to locked-rotor inrush
		throughput_kg_s = 0.0
		screw_fill_efficiency = 0.0
		# The seized pot keeps cooling (no friction input) so the crew can eventually
		# reset it. No discharge, no evaporation worth modelling while fused solid.
		# But if pot is still above T_SEIZE with motor off, the charge has fused
		# solid to the knives — operator anecdote says this is a 3–5 day teardown.
		_integrate_temperature(delta, 0.0)
		return 0.0

	# ── 2. Spin the disc toward its commanded speed (motors don't snap to rpm) ────
	disc_rpm = move_toward(disc_rpm, disc_rpm_setpoint, RPM_SPINUP_PER_S * delta)

	# ── 3. Meter flake in through the dosing gate, capped by remaining pot room ────
	#    (feed() is the bulk path from upstream; this models the gate's own trickle so
	#     dosing_gate alone still loads a standalone unit in a headless test.)
	var room := maxf(0.0, POT_CAPACITY_KG - charge.mass_kg)
	if dosing_gate > 0.0 and disc_rpm > 1.0 and room > 0.0:
		var meter := minf(DISCHARGE_KG_S * dosing_gate * delta, room)
		if meter > 0.0:
			# Wet, dirty fluff at a typical post-wash moisture — the warm pot's job is
			# partly to finish drying it. Conserving MaterialBatch (mass = poly+water).
			charge.add(MaterialBatch.new(meter, meter / 60.0, {"LDPE": 1.0}, "dose",
										 meter * 0.10, 0.0))
			total_fed_kg += meter

	# ── 4. Friction heat from rpm² and how loaded the pot is, then integrate T ────
	var load_frac := _pot_load_fraction()
	var friction_w := _friction_watts(load_frac)
	var flashed_kg := _integrate_temperature(delta, friction_w)
	water_removed_kg += flashed_kg

	# ── 5. Behaviour bands → screw fill efficiency + the Donut trip ──────────────
	screw_fill_efficiency = _fill_efficiency_for(pot_temperature)

	if pot_temperature > T_DONUT:
		_trigger_donut()
		return flashed_kg

	# ── 6. Discharge densified crumb, gated by fill efficiency + the dosing gate ──
	var out_kg := 0.0
	if disc_rpm > 1.0 and charge.mass_kg > 0.0:
		var eff_rate := DISCHARGE_KG_S * screw_fill_efficiency * clampf(dosing_gate, 0.05, 1.0)
		out_kg = minf(eff_rate * delta, charge.mass_kg)
	# (the discharged crumb is RETURNED to the caller via discharge(); here we only
	#  advance telemetry — see discharge() for the conserving hand-off.)
	throughput_kg_s = lerpf(throughput_kg_s, out_kg / maxf(delta, 0.0001), 0.3)

	# ── 7. Motor current: idle → full across load, scaled by live rpm fraction ────
	motor_amps = _motor_amps_for(load_frac)

	# ── 7.5 #A1/A2/A4 — Power-cap override + moisture penalty + breaker trip ────
	# kW = amps × line voltage / 1000. Industrial CeDo gear runs on a 400 V
	# 3-phase feed (line-to-line) so kW ≈ I × √3 × 400 × cos(φ) / 1000 with
	# cos(φ) ≈ 0.85 — collapsed to a single 0.59 factor for the sim. Add the
	# moisture penalty: wet feed forces the motor to do evaporation work on top
	# of compaction, raising kW at the same throughput.
	const KW_PER_AMP : float = 0.59
	var moisture_penalty_kw : float = max(0.0,
		feed_moisture_pct - MOISTURE_DRY_BASELINE) * MOISTURE_KW_PER_PCT
	power_kw = motor_amps * KW_PER_AMP + moisture_penalty_kw
	# Power-cap override: if the operator has set the cap BELOW current draw,
	# choke the disc RPM setpoint so the motor stops drawing more than the cap.
	# Choke is gentle — 10 % per second — so the operator FEELS the cap pulling
	# them back instead of an instant cliff. The "push past 150 kW" anecdote
	# comes from operators raising the cap to 280+ before starting a run.
	if power_kw > power_cap_kw_setpoint and disc_rpm_setpoint > 0.0:
		var cap_choke : float = clampf(
			(power_kw - power_cap_kw_setpoint) / max(power_cap_kw_setpoint, 1.0),
			0.0, 0.20)
		disc_rpm_setpoint = max(0.0, disc_rpm_setpoint * (1.0 - cap_choke * delta))
	# SOFTSTARTER trip (the operator-confirmed real-world mechanism). The
	# motor SOFTSTARTER (a PLC safeguard) integrates instantaneous overage
	# above POWER_KW_SOFTSTARTER_BASELINE into softstarter_budget_kws (kW·s).
	# When that budget exceeds POWER_KW_SOFTSTARTER_BUDGET_KWS the motor is
	# stopped. Operator-confirmed data points: 5 s at 300 kW trips; 3 s at
	# 350 kW trips. Below baseline the budget DRAINS at
	# SOFTSTARTER_DRAIN_KWS_PER_S kW·s/s, so brief spikes followed by cool
	# draws don't carry over forever.
	if power_kw > POWER_KW_SOFTSTARTER_BASELINE:
		softstarter_budget_kws += (power_kw - POWER_KW_SOFTSTARTER_BASELINE) * delta
	else:
		softstarter_budget_kws = max(0.0,
			softstarter_budget_kws - SOFTSTARTER_DRAIN_KWS_PER_S * delta)
	# Softstarter trip — the common, real-world way the motor stops on
	# overdraw. Sets BOTH softstarter_tripped (the accurate cause flag) and
	# breaker_tripped (the legacy flag downstream code already reads).
	if softstarter_budget_kws >= POWER_KW_SOFTSTARTER_BUDGET_KWS \
			and not softstarter_tripped:
		softstarter_tripped = true
		breaker_tripped = true
		disc_rpm_setpoint = 0.0
		dosing_gate = 0.0
		# DONUT_STALL is the existing "frozen pot, no rotor" state — best
		# match for the softstarter-stopped outcome (charge sits in the pot
		# and will solidify until reset). The HMI can read softstarter_tripped
		# to label the alarm "SOFTSTARTER TRIP" rather than "DONUT".
		_set_state(State.DONUT_STALL)
		donut_stall_triggered.emit(machine_id, pot_temperature, motor_amps)
		_emit_bus("machine_alarm_raised", [machine_id, "SOFTSTARTER-TRIP", 3])
	# Hardware breaker — the 600 kW mechanical safety. Basically never trips
	# in real life (the softstarter pulls the plug long before this), but
	# modelled as an instantaneous safety net for the pathological case.
	elif power_kw > POWER_KW_HARDWARE_BREAKER and not breaker_tripped:
		breaker_tripped = true
		disc_rpm_setpoint = 0.0
		dosing_gate = 0.0
		_set_state(State.DONUT_STALL)
		donut_stall_triggered.emit(machine_id, pot_temperature, motor_amps)
		_emit_bus("machine_alarm_raised", [machine_id, "HARDWARE-BREAKER-TRIP", 3])

	# ── 8. State (HEATING below the sweet spot, RUNNING once in/above the band) ───
	if disc_rpm_setpoint <= 0.0 and disc_rpm < 1.0:
		_set_state(State.OFF)
	elif pot_temperature < T_UNDERHEAT:
		_set_state(State.HEATING)
	else:
		_set_state(State.RUNNING)

	return flashed_kg

## Pull up to `screw_fill_efficiency`-gated crumb OUT of the pot as a conserving
## MaterialBatch (mass leaves `charge`). LineFlow calls this after tick() to move
## the densified crumb down the connector. Empty batch when stalled / starved.
func discharge(delta: float) -> MaterialBatch:
	if state == State.DONUT_STALL or charge.mass_kg <= 0.0 or disc_rpm <= 1.0:
		return MaterialBatch.new()
	var eff_rate := DISCHARGE_KG_S * screw_fill_efficiency * clampf(dosing_gate, 0.05, 1.0)
	var take := minf(eff_rate * maxf(delta, 0.0), charge.mass_kg)
	if take <= 0.0:
		return MaterialBatch.new()
	var crumb := charge.split_mass(take)
	discharged_kg += crumb.mass_kg
	return crumb

## Conservation residual (kg): everything fed − (still in the pot + crumb discharged
## + moisture flashed off). → 0 means nothing was silently created or destroyed,
## exactly the invariant MaterialBatch + LineFlow.ledger_residual() guarantee.
func ledger_residual() -> float:
	return total_fed_kg - charge.mass_kg - discharged_kg - water_removed_kg

# =============================================================================
# THERMODYNAMICS
# =============================================================================
## Friction power (W). Scales with disc_rpm² (friction power ≈ torque·ω, torque
## itself rising with ω), pot load (idle floor + dosed flake rubbing), AND the
## knife dullness multiplier (#PCU-K) — dull knives drag, so the same throughput
## costs more friction work. Knife sharpness also DECAYS proportionally to the
## work it's doing, so a faster-loaded run wears the edge faster.
func _friction_watts(load_frac: float) -> float:
	if disc_rpm <= 1.0:
		_last_friction_w = 0.0
		return 0.0
	# Knife wear: decay scales with (disc_rpm/nominal) × load — heavier rubbing
	# dulls the edge faster. Bounded so a stalled-and-spinning empty disc still
	# loses sharpness at a low background rate.
	var dt_to_h : float = 1.0 / 3600.0
	var rpm_frac : float = clampf(disc_rpm / max(NOMINAL_RPM, 1.0), 0.0, 1.5)
	var wear_rate : float = KNIFE_DECAY_PER_H_NOMINAL * rpm_frac * (IDLE_LOAD_FRAC + load_frac)
	knife_sharpness = max(0.0, knife_sharpness - wear_rate * dt_to_h)   # tick-rate decay applied each call
	var knife_mult : float = lerpf(KNIFE_FRICTION_MULT_DULL,
		KNIFE_FRICTION_MULT_FRESH, clampf(knife_sharpness, 0.0, 1.0))
	var rpm2 := disc_rpm * disc_rpm
	_last_friction_w = FRICTION_GAIN * rpm2 * (IDLE_LOAD_FRAC + load_frac) * knife_mult
	return _last_friction_w

## Advance pot_temperature one step and flash off moisture. Returns kg of water
## removed (a conserving side stream). Evaporation is ENERGY-LIMITED: drying is
## endothermic, so it can only consume a fraction of the SURPLUS friction heat
## (friction minus jacket cooling). Modelling it as a bounded brake — rather than a
## fixed mass rate × full latent heat — keeps the thermo self-stabilising: the pot
## still net-heats toward its band, while a wet charge both dries AND damps the
## climb (realistic), and we never vaporise more water than the heat input supports.
func _integrate_temperature(delta: float, friction_w: float) -> float:
	_last_cooling_w = (pot_temperature - AMBIENT_C) * COOL_COEF
	var surplus_w := friction_w - _last_cooling_w        # heat available above cooling

	var flashed := 0.0
	var evap_w := 0.0
	# Drying only runs once the flake is warm (>80 °C) AND there's surplus heat to
	# drive it. It skims a fraction of the surplus into latent heat of vaporisation.
	# #PCU-AF — with the air-flush extractor OFF, only a small fraction of the
	# evap energy actually LEAVES the pot; the rest re-condenses on cooler
	# incoming flake (the "sauna effect") and the steam loops back into the
	# charge as liquid water. We model that by scaling the evap heat-sink:
	# flush ON → full skim, flush OFF → mostly disabled.
	var flush_factor : float = AIR_FLUSH_EVAP_BOOST if air_flush_on else AIR_FLUSH_EVAP_PENALTY
	if pot_temperature >= 80.0 and charge.water_kg > 0.0 and surplus_w > 0.0 and delta > 0.0:
		evap_w = surplus_w * EVAP_HEAT_FRAC * flush_factor
		var evap_kg := (evap_w * delta) / EVAP_LATENT_J_KG          # kg the energy can flash
		evap_kg = minf(evap_kg, charge.water_kg)                    # bounded by available water
		flashed = charge.remove_water(
			clampf(evap_kg / charge.water_kg, 0.0, 1.0))            # conserving (drops mass+vol)
		# Recompute the actual latent draw from what truly evaporated (water may have
		# run out mid-step), so the energy book stays honest.
		evap_w = (flashed * EVAP_LATENT_J_KG) / delta

	var net_w := friction_w - _last_cooling_w - evap_w
	pot_temperature += (net_w / THERMAL_MASS) * delta
	pot_temperature = maxf(pot_temperature, AMBIENT_C)       # never below soak temp
	return flashed

# =============================================================================
# BEHAVIOUR BANDS
# =============================================================================
## screw_fill_efficiency (0..1) for a pot temperature, per the spec's three bands:
##   < 90 °C        → drops off linearly toward 0 (cold flake bridges the outlet)
##   90..100 °C     → ramps 0.6 → 1.0 (warming, fill improving)
##   100..105 °C    → 1.0 (sweet spot, MAX throughput)
##   105..110 °C    → tapers 1.0 → ~0.85 (getting tacky, fill slightly worse)
##   ≥ 110 °C       → 0 (handled as a Donut stall by the caller, not here)
static func _fill_efficiency_for(temp_c: float) -> float:
	if temp_c < T_UNDERHEAT:
		# Linear drop: 0 at ambient-ish (40 °C), 0.6 at the 90 °C edge.
		return clampf((temp_c - 40.0) / (T_UNDERHEAT - 40.0) * 0.6, 0.0, 0.6)
	if temp_c < T_SWEET_LOW:
		return lerpf(0.6, 1.0, (temp_c - T_UNDERHEAT) / (T_SWEET_LOW - T_UNDERHEAT))
	if temp_c <= T_SWEET_HIGH:
		return 1.0
	if temp_c < T_DONUT:
		return lerpf(1.0, 0.85, (temp_c - T_SWEET_HIGH) / (T_DONUT - T_SWEET_HIGH))
	return 0.0

## Convenience: which band the pot is in right now, as a short string for the HMI.
func band() -> String:
	if state == State.DONUT_STALL:
		return "DONUT-STALL"
	if pot_temperature < T_UNDERHEAT:
		return "UNDERHEATED"
	if pot_temperature <= T_SWEET_HIGH and pot_temperature >= T_SWEET_LOW:
		return "SWEET-SPOT"
	if pot_temperature > T_DONUT:
		return "OVERHEAT"
	return "OK"

## Unified cause-of-stop status string for the HMI. Returns empty when the
## compactor is running normally; a short ALL-CAPS phrase when it's halted
## or alarmed. The SCADA dashboard reads this and colours the value chip
## red when non-empty — same pattern as the extruder's fault_reason.
##
## Priority order matches what the operator most needs to see first:
##   1. SOFTSTARTER TRIP — PLC pulled the plug because integrated kW·s
##      exceeded 300 above the 240 kW baseline (or instant hardware breaker
##      above 600 kW). Recovery: reset_breaker() after addressing the cause.
##   2. DONUT STALL     — pot overheated past 110 °C, fused ring seized the
##      rotor. Recovery: reset() after pot cools below 80 °C.
##   3. PROCESS UNSTABLE — operator hit emergency water injection more than
##      5 times this shift. Not a stop — but the SCADA flags it so the shift
##      report calls it out. Returned only when no harder fault is active.
##   4. OFF             — the operator stopped the disc deliberately. Empty
##      string OK when no operator-set fault and disc is just idle/heating.
##   Empty               — nominal, return "" so the dashboard stays grey.
func cause_of_stop() -> String:
	if softstarter_tripped:
		return "SOFTSTARTER TRIP"
	if state == State.DONUT_STALL:
		return "DONUT STALL"
	if process_unstable_flag:
		return "PROCESS UNSTABLE"
	return ""

## True when cause_of_stop() returns a non-empty string — used by the HMI
## to decide whether to paint the chip alarm-red.
func is_alarming() -> bool:
	return softstarter_tripped or state == State.DONUT_STALL or process_unstable_flag

# =============================================================================
# ELECTRICAL
# =============================================================================
## Live motor current (A). Idle→full across pot load, scaled by the live rpm
## fraction so a spinning-up or starved disc draws proportionally less.
func _motor_amps_for(load_frac: float) -> float:
	if disc_rpm <= 1.0:
		return 0.0
	var rpm_frac := clampf(disc_rpm / maxf(NOMINAL_RPM, 1.0), 0.0, 1.25)
	var base := lerpf(MOTOR_IDLE_AMPS, MOTOR_FULL_AMPS, clampf(load_frac, 0.0, 1.0))
	return base * rpm_frac

# =============================================================================
# DONUT STALL
# =============================================================================
func _trigger_donut() -> void:
	if state == State.DONUT_STALL:
		return
	stalled = true
	disc_rpm = 0.0                       # instantly seized
	motor_amps = LOCKED_ROTOR_AMPS       # locked-rotor current spike
	throughput_kg_s = 0.0
	screw_fill_efficiency = 0.0
	_set_state(State.DONUT_STALL)
	donut_stall_triggered.emit(machine_id, pot_temperature, LOCKED_ROTOR_AMPS)
	# Project convention: a stall is a sev-3 machine alarm + a lump on the EventBus.
	_emit_bus("machine_alarm_raised", [machine_id, "DONUT-STALL", 3])
	_emit_bus("machine_lump_produced", [machine_id, charge.mass_kg, pot_temperature])

# =============================================================================
# HELPERS / QUERIES
# =============================================================================
## How loaded the pot is, 0..1, as the friction + amps driver.
func _pot_load_fraction() -> float:
	return clampf(charge.mass_kg / POT_CAPACITY_KG, 0.0, 1.0)

func _set_state(new_state: State) -> void:
	if new_state == state:
		return
	var old := state
	state = new_state
	_time_in_state = 0.0
	state_changed.emit(machine_id, old, new_state)
	_emit_bus("machine_state_changed", [machine_id, old, new_state])

func get_state_name() -> String:
	return State.keys()[state]

func is_stalled() -> bool:
	return state == State.DONUT_STALL

## A snapshot dict for the HMI to render (mirrors LineFlow.get_machine_info shape).
func telemetry() -> Dictionary:
	return {
		"id":             machine_id,
		"state":          get_state_name(),
		"band":           band(),
		"pot_temp_c":     pot_temperature,
		"disc_rpm":       disc_rpm,
		"disc_rpm_set":   disc_rpm_setpoint,
		"dosing_gate":    dosing_gate,
		"motor_amps":     motor_amps,
		"fill_eff":       screw_fill_efficiency,
		"throughput_kgs": throughput_kg_s,
		"charge_kg":      charge.mass_kg,
		"friction_w":     _last_friction_w,
		"cooling_w":      _last_cooling_w,
		"stalled":        stalled,
	}

## Resolve the EventBus autoload (a RefCounted isn't in the tree, so we reach it
## through the main loop's root) and emit `sig` with `args` IF the signal exists.
## Silent no-op headless or before autoloads exist, so the sim never hard-depends
## on the tree — exactly how LineFlow guards its EventBus calls.
func _emit_bus(sig: String, args: Array) -> void:
	var loop := Engine.get_main_loop()
	if loop == null or not (loop is SceneTree):
		return
	var root := (loop as SceneTree).root
	if root == null:
		return
	var bus := root.get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal(sig):
		bus.callv("emit_signal", [sig] + args)
