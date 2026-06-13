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
##     friction_heat_W  ∝  disc_rpm²  ·  (idle + load·dosing_gate)
##     cooling_W        =  (pot_T − ambient) · COOL_COEF
##     evap_sink_W      =  moisture flashing off the warm flake (a real heat sink)
##     dT/dt            =  (friction_heat − cooling − evap_sink) / THERMAL_MASS
##
## Heat scales with the SQUARE of rpm (friction power ≈ torque·ω, torque itself rising
## with ω) and with how much flake is in the pot (the dosing gate): more flake = more
## rubbing surfaces = more heat, up to a point, but also more cold mass + moisture to
## warm, which is why a slammed-open gate can actually STALL a cold pot.
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
		return true
	if pot_temperature > T_RESET_BELOW:
		return false
	stalled = false
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

	# ── 1. DONUT STALL is a hard latch: rotor seized, locked-rotor current ────────
	if state == State.DONUT_STALL:
		disc_rpm = 0.0                                   # instantly 0 — the ring jammed it
		motor_amps = LOCKED_ROTOR_AMPS                   # spike to locked-rotor inrush
		throughput_kg_s = 0.0
		screw_fill_efficiency = 0.0
		# The seized pot keeps cooling (no friction input) so the crew can eventually
		# reset it. No discharge, no evaporation worth modelling while fused solid.
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
## itself rising with ω) and with pot load (idle floor + dosed flake rubbing).
func _friction_watts(load_frac: float) -> float:
	if disc_rpm <= 1.0:
		_last_friction_w = 0.0
		return 0.0
	var rpm2 := disc_rpm * disc_rpm
	_last_friction_w = FRICTION_GAIN * rpm2 * (IDLE_LOAD_FRAC + load_frac)
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
	if pot_temperature >= 80.0 and charge.water_kg > 0.0 and surplus_w > 0.0 and delta > 0.0:
		evap_w = surplus_w * EVAP_HEAT_FRAC
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
