extends RefCounted
class_name ExtruderScrew
## Non-Newtonian single-screw extruder physics for LDPE melt (#45).
##
## SELF-CONTAINED pure-sim module — NO scene-tree dependency, exactly like
## ExtruderModel.gd / MaterialBatch.gd. A scene controller (or LineFlow, or a
## headless test) constructs one and calls tick(delta) at a fixed rate
## (SimTick.TICK_DT = 0.1 s is the house cadence). Decoupling from the scene
## keeps it unit-testable, deterministic, and runnable faster-than-real-time
## for tuning sweeps.
##
## WHAT IT MODELS — the thing an extruder operator actually fights: you cannot
## get throughput without screw rpm, but rpm dumps mechanical work straight into
## the melt as heat, and LDPE's viscosity makes that a vicious feedback loop:
##
##   • SHEAR-THINNING (pseudoplastic, power-law / Ostwald–de Waele):
##       the faster you turn the screw, the LOWER the apparent viscosity.
##       eta_app = K · gamma_dot^(n-1),  n < 1  → eta falls as gamma_dot rises.
##       (LDPE melt at extrusion temps sits around n ≈ 0.35.) Temperature thins
##       it further via an Arrhenius factor, so a hotter melt is also runnier.
##
##   • VISCOUS DISSIPATION / SHEAR HEAT:
##       mechanical work per unit volume = eta_app · gamma_dot^2
##                                       = K · gamma_dot^(n+1).
##       n+1 ≈ 1.35, and gamma_dot ∝ rpm, so the heat generated climbs STEEPLY
##       (super-linearly — "exponentially" to the operator) with rpm. This is
##       why pushing rpm for throughput cooks the melt.
##
##   • ADIABATIC-LEANING THERMAL PROFILE:
##       the melt is a thermal mass. Each tick its temperature integrates
##         + shear heat (mechanical, ALWAYS positive while turning)
##         + conduction toward the barrel-zone setpoint (two-way; weak)
##         − cooling-fan extraction (forced convection off the barrel)
##         − ambient losses (small)
##       Because shear heat is internal and unbounded, melt_temp can — and at
##       high rpm WILL — climb ABOVE the barrel setpoint purely on friction.
##       That is the headline behaviour: the barrel heaters are not what's
##       hottest; the polymer cooking itself is.
##
##   • COOLING-FAN CONTROL:
##       barrel blowers are the operator's only brake on a self-heating melt.
##       A PI controller drives cooling_fan_level (0..1) to pull melt_temp back
##       into the MELT_TARGET_LO..HI window (190–200 °C). Fans can only REMOVE
##       heat (one-directional actuator), so they fight runaway but can't warm a
##       cold start — exactly like the real barrel-zone cooling.
##
##   • DIE PRESSURE (for the downstream MFI-proxy task to read):
##       drag/pressure-flow balance → die_pressure ∝ eta_app · throughput.
##       A thinner (hotter / faster-sheared) melt at the same output drops the
##       head pressure; this is the raw signal a melt-flow-index proxy keys on.
##
## All temperatures are °C, rpm is screw rev/min, viscosity is Pa·s (apparent),
## pressure is bar. Coefficients are heuristic, tuned so a ~110 rpm LDPE screw
## settles near the 190–200 °C target with the fan doing real work.

# =============================================================================
# TUNING CONSTANTS  (heuristic, LDPE-flavoured; safe to expose later as a Resource)
# =============================================================================
# ── Rheology (power-law + Arrhenius thermal thinning) ─────────────────────────
const POWER_LAW_N        : float = 0.35    # LDPE flow index (<1 ⇒ shear-thinning)
const CONSISTENCY_K      : float = 21000.0 # Pa·sⁿ consistency at the reference temp
const RPM_TO_SHEAR       : float = 3.0     # gamma_dot (1/s) per screw rpm in the channel
const SHEAR_RATE_FLOOR   : float = 1.0     # 1/s — avoids the gamma_dot→0 viscosity blow-up
const VISC_REF_TEMP_C    : float = 190.0   # Arrhenius reference temperature
const VISC_TEMP_COEFF    : float = 0.013   # 1/°C — viscosity halves roughly every ~55 °C up
const VISC_MIN_PAS       : float = 50.0    # numeric floor on apparent viscosity

# ── Shear-heat coupling (viscous dissipation → melt energy) ───────────────────
# shear_heat (a per-tick °C-rate source) = SHEAR_HEAT_GAIN · eta_app · gamma_dot²
# scaled into the melt's thermal mass. Kept as a published rate so the HMI/test
# can read "how hard is the melt cooking itself right now".
const SHEAR_HEAT_GAIN    : float = 7.0e-8  # converts eta·gamma² (W/m³-ish) to °C/s

# ── Thermal masses / couplings (°C-rate terms) ────────────────────────────────
const BARREL_COUPLING    : float = 0.18    # 1/s conduction of melt toward barrel setpoint
const AMBIENT_LOSS       : float = 0.010   # 1/s passive loss of melt toward ambient
const FAN_MAX_COOLING    : float = 0.55    # 1/s extraction at fan=1.0 per (melt−ambient)
const AMBIENT_C          : float = 25.0

# ── Cooling-fan PI controller (holds the 190–200 °C window) ───────────────────
const MELT_TARGET_LO     : float = 190.0
const MELT_TARGET_HI     : float = 200.0
const MELT_TARGET_MID    : float = 195.0   # PI setpoint (centre of the window)
const FAN_KP             : float = 0.06    # proportional gain (per °C of overshoot)
const FAN_KI             : float = 0.015   # integral gain (clears steady-state offset)
const FAN_INTEGRAL_CLAMP : float = 30.0    # anti-windup bound on the integral term
const FAN_SLEW_PER_S     : float = 2.5     # max fan-level change per second (real inertia)

# ── Screw drive ───────────────────────────────────────────────────────────────
const RPM_SLEW_PER_S     : float = 25.0    # screw can't jump rpm instantly
const SCREW_RPM_MAX      : float = 200.0

# ── Die / head pressure ───────────────────────────────────────────────────────
# die_pressure (bar) = DIE_RESISTANCE · eta_app · throughput_norm. throughput_norm
# is throughput as a fraction of design, so an empty screw makes no head pressure.
const DIE_RESISTANCE     : float = 6.5e-4
const DESIGN_THROUGHPUT  : float = 0.5     # normalising flow (arb. units ~ kg/s)

# =============================================================================
# STATE  (the spec's required surface)
# =============================================================================
var screw_rpm         : float = 0.0     # live screw speed (rev/min)
var viscosity         : float = 0.0     # apparent melt viscosity (Pa·s)
var shear_heat        : float = 0.0     # viscous-dissipation heat source (°C/s)
var barrel_temp       : float = 195.0   # barrel-zone heater SETPOINT (°C)
var melt_temp         : float = 25.0    # actual polymer melt temperature (°C)
var cooling_fan_level : float = 0.0     # 0..1 forced-convection cooling demand
var die_pressure      : float = 0.0     # head pressure at the die (bar)

# ── Command / load inputs (set by the caller; sensible standalone defaults) ────
var rpm_setpoint      : float = 0.0     # commanded screw rpm (slews toward it)
var throughput        : float = DESIGN_THROUGHPUT  # mass flow proxy feeding the die
var fan_auto          : bool  = true    # PI fan controller on (false ⇒ manual fan)

# ── Internal controller state ─────────────────────────────────────────────────
var _fan_integral     : float = 0.0

# =============================================================================
func _init(barrel_setpoint_c: float = 195.0, start_melt_c: float = 25.0) -> void:
	barrel_temp = barrel_setpoint_c
	melt_temp   = start_melt_c
	viscosity   = _apparent_viscosity(0.0, melt_temp)

# =============================================================================
# COMMAND SURFACE  (caller pokes these; tick() integrates the physics)
# =============================================================================
## Command a new screw speed (rev/min). The screw slews toward it (RPM_SLEW_PER_S).
func set_rpm(rpm: float) -> void:
	rpm_setpoint = clampf(rpm, 0.0, SCREW_RPM_MAX)

## Barrel-zone heater setpoint (°C). The melt conducts toward this, but shear heat
## can carry the melt well above it.
func set_barrel_setpoint(temp_c: float) -> void:
	barrel_temp = temp_c

## Mass-flow proxy through the die (drives die_pressure). 0 ⇒ starved screw.
func set_throughput(flow: float) -> void:
	throughput = maxf(0.0, flow)

## Manual fan override (disables the PI controller and pins the level).
func set_fan_manual(level: float) -> void:
	fan_auto = false
	cooling_fan_level = clampf(level, 0.0, 1.0)

## Hand the fan back to the automatic PI controller.
func set_fan_auto() -> void:
	fan_auto = true

# =============================================================================
# TICK — integrate one step. delta in seconds (SimTick.TICK_DT = 0.1 s nominal).
# =============================================================================
func tick(delta: float) -> void:
	var dt := maxf(delta, 0.0001)

	# 1) Screw drive slews toward the commanded rpm (no instant jumps).
	screw_rpm = move_toward(screw_rpm, rpm_setpoint, RPM_SLEW_PER_S * dt)

	# 2) Rheology — shear rate from rpm, then shear-thinning apparent viscosity.
	#    Higher rpm ⇒ higher gamma_dot ⇒ LOWER eta (power-law, n<1); a hotter melt
	#    is also thinner (Arrhenius). Floor the shear rate so eta stays finite at
	#    a stopped screw.
	var gamma_dot : float = maxf(screw_rpm * RPM_TO_SHEAR, SHEAR_RATE_FLOOR)
	viscosity = _apparent_viscosity(gamma_dot, melt_temp)

	# 3) Viscous dissipation — mechanical work the screw pours into the melt as
	#    heat. = eta·gamma_dot², which is K·gamma_dot^(n+1): n+1≈1.35, and
	#    gamma_dot ∝ rpm, so this climbs STEEPLY with rpm. Zero at a stopped screw
	#    (the floored gamma_dot still yields a tiny value, so gate on real rpm).
	if screw_rpm > 0.01:
		shear_heat = SHEAR_HEAT_GAIN * viscosity * gamma_dot * gamma_dot
	else:
		shear_heat = 0.0

	# 4) Cooling fan — PI controller pulls the melt back into 190–200 °C. Fans can
	#    only REMOVE heat, so the demand is clamped to [0,1] and slew-limited.
	if fan_auto:
		_update_fan_controller(dt)

	# 5) Adiabatic-leaning thermal integration. melt_temp is a thermal mass driven
	#    by four °C-rate terms:
	#      + shear_heat                          (internal, always ≥ 0 while turning)
	#      + barrel conduction toward setpoint   (two-way, weak)
	#      − fan extraction (forced convection)  (one-way, ∝ fan × (melt−ambient))
	#      − ambient loss                        (one-way, small)
	#    Shear heat is internal and unbounded, so at high rpm the melt overshoots
	#    the barrel setpoint — the polymer cooks itself hotter than the heaters.
	var d_barrel : float = BARREL_COUPLING * (barrel_temp - melt_temp)
	var above_ambient : float = maxf(melt_temp - AMBIENT_C, 0.0)
	var d_fan    : float = -FAN_MAX_COOLING * cooling_fan_level * above_ambient
	var d_amb    : float = -AMBIENT_LOSS * above_ambient
	var dT_dt : float = shear_heat + d_barrel + d_fan + d_amb
	melt_temp += dT_dt * dt
	melt_temp = maxf(melt_temp, AMBIENT_C)   # can't drop below ambient

	# 6) Die / head pressure — drag-flow vs head-resistance balance. Thinner melt
	#    (hotter / faster sheared) at the same throughput drops head pressure; the
	#    MFI proxy keys on exactly this signal. Starved screw ⇒ no head pressure.
	var flow_norm : float = throughput / DESIGN_THROUGHPUT if DESIGN_THROUGHPUT > 0.0 else 0.0
	die_pressure = DIE_RESISTANCE * viscosity * flow_norm

# =============================================================================
# RHEOLOGY
# =============================================================================
## Apparent viscosity (Pa·s) for a shear rate (1/s) at a melt temperature (°C).
## Power-law shear-thinning (eta ∝ gamma_dot^(n-1), n<1) combined with Arrhenius
## thermal thinning (eta falls as temperature rises above the reference).
func _apparent_viscosity(gamma_dot: float, temp_c: float) -> float:
	var g : float = maxf(gamma_dot, SHEAR_RATE_FLOOR)
	var shear_factor : float = pow(g, POWER_LAW_N - 1.0)        # <1 and falling with g
	var temp_factor  : float = exp(-VISC_TEMP_COEFF * (temp_c - VISC_REF_TEMP_C))
	return maxf(CONSISTENCY_K * shear_factor * temp_factor, VISC_MIN_PAS)

# =============================================================================
# COOLING-FAN PI CONTROLLER
# =============================================================================
## Drive cooling_fan_level (0..1) to hold melt_temp near MELT_TARGET_MID. Error is
## "how far above the midpoint" (cooling can only pull DOWN), with anti-windup on
## the integral and a slew limit so the fan has realistic inertia.
func _update_fan_controller(dt: float) -> void:
	var error : float = melt_temp - MELT_TARGET_MID      # +ve ⇒ too hot ⇒ cool harder
	# Integrate only meaningfully — clamp to kill wind-up when pinned at the rails.
	_fan_integral = clampf(_fan_integral + error * dt, -FAN_INTEGRAL_CLAMP, FAN_INTEGRAL_CLAMP)
	var demand : float = FAN_KP * error + FAN_KI * _fan_integral
	demand = clampf(demand, 0.0, 1.0)
	# Slew-limit the actuator toward the demand (no instant fan-speed steps).
	cooling_fan_level = move_toward(cooling_fan_level, demand, FAN_SLEW_PER_S * dt)
	cooling_fan_level = clampf(cooling_fan_level, 0.0, 1.0)

# =============================================================================
# QUERIES  (for HMI / telemetry / the downstream MFI-proxy task)
# =============================================================================
## True while the melt sits inside the 190–200 °C operating window.
func melt_in_target_band() -> bool:
	return melt_temp >= MELT_TARGET_LO and melt_temp <= MELT_TARGET_HI

## °C the melt is running ABOVE the barrel setpoint (≥0). Positive means the screw
## is shear-heating the polymer hotter than the heaters alone would — the headline
## adiabatic behaviour.
func superheat_over_barrel() -> float:
	return maxf(melt_temp - barrel_temp, 0.0)

## A crude melt-flow-index PROXY (higher ⇒ runnier melt). The dedicated MFI task
## will refine this; exposed so callers have a single number to read today. MFI
## moves inversely with apparent viscosity.
func mfi_proxy() -> float:
	return 1.0e5 / maxf(viscosity, VISC_MIN_PAS)

func to_dict() -> Dictionary:
	return {
		"screw_rpm":         screw_rpm,
		"viscosity":         viscosity,
		"shear_heat":        shear_heat,
		"barrel_temp":       barrel_temp,
		"melt_temp":         melt_temp,
		"cooling_fan_level": cooling_fan_level,
		"die_pressure":      die_pressure,
	}

func _to_string() -> String:
	return "ExtruderScrew(%.0f rpm | eta %.0f Pa·s | shear %.2f °C/s | melt %.1f°C (barrel %.0f) | fan %.0f%% | die %.1f bar)" % [
		screw_rpm, viscosity, shear_heat, melt_temp, barrel_temp, cooling_fan_level * 100.0, die_pressure]
