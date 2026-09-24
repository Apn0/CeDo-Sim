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
##       toward the profile's melt window (melt_target_lo..hi). Fans can only
##       REMOVE heat (one-directional actuator), so they fight runaway but can't
##       warm a cold start — exactly like the real barrel-zone cooling.
##
##   • DIE-PLATE PRESSURE (for the downstream MFI-proxy task to read):
##       the melt pressure at the die plate (matrijs), AFTER the kopfilter —
##       operator ruling 2026-09-24. Drag/pressure-flow balance →
##       die_pressure ∝ eta_app · throughput, anchored so the profile's nominal
##       rpm, melt and output read the profile's die_plate_bar. A thinner
##       (hotter / faster-sheared) melt at the same output drops it; this is the
##       raw signal a melt-flow-index proxy keys on.
##
## All temperatures are °C, rpm is screw rev/min, viscosity is Pa·s (apparent),
## pressure is bar. The rheology and heat coefficients are heuristic and have
## no plant source. The OPERATING POINT they run at — rpm, melt window, output,
## die-plate pressure — is per line and comes from plant data (PROFILES).
## Until 2026-09-24 that point was invented: 200 rpm, a 190–200 °C melt and a
## die pressure of 0.11 bar, against the plant's 95–110 rpm, 246–257 °C and
## ~120–140 bar. docs/audit/extruder_screw_die_plate_2026-09-24.md.

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

# ── Cooling-fan PI controller (holds the profile's melt window) ──────────────
const FAN_KP             : float = 0.06    # proportional gain (per °C of overshoot)
const FAN_KI             : float = 0.015   # integral gain (clears steady-state offset)
const FAN_INTEGRAL_CLAMP : float = 30.0    # anti-windup bound on the integral term
const FAN_SLEW_PER_S     : float = 2.5     # max fan-level change per second (real inertia)

# ── Screw drive ───────────────────────────────────────────────────────────────
const RPM_SLEW_PER_S     : float = 25.0    # screw can't jump rpm instantly
const SCREW_RPM_MAX      : float = 200.0

# ── Per-line operating point (2026-09-24) ─────────────────────────────────────
# Every number is read off a plant source; none is tuned by feel.
#   rpm_nominal      "Snelheid hoofdmotor" p50 of the EREMA WinCC archive,
#                    2023-06-19..28 (docs/plant/trends_overview.md §2;
#                    src/data/plant/trends/extruder_trends_summary.json)
#   kg_h_nominal     "Output" p50 of the same archive
#   melt_lo/mid/hi   "Smelt temperatuur voor meltfilter" operating band (p5–p95
#                    of running data) and p50, same archive
#   die_plate_bar    the melt pressure at the die plate, AFTER the kopfilter
#                    (operator ruling 2026-09-24). No gauge reads it, so it is
#                    DERIVED from FORM-008 rows 25/26, "Kopdruk kopfilter"
#                    3A 120–150 / 3B 140–155 bar (docs/plant/checklist_3a_3b.md):
#                    kopdruk = die plate + the kopfilter's dP, and a fresh pack's
#                    dP is ~0, so the bottom of each window is that line's die
#                    plate.
# test_screw_die_plate_bar reads the trend numbers back out of the JSON, so a
# drift between this table and the data turns a check red instead of rotting.
const PROFILES : Dictionary = {
	"3A": {"rpm_nominal": 95.0, "kg_h_nominal": 908.0,
		"melt_lo": 247.0, "melt_mid": 257.0, "melt_hi": 265.0, "die_plate_bar": 120.0},
	"3B": {"rpm_nominal": 110.0, "kg_h_nominal": 799.0,
		"melt_lo": 230.0, "melt_mid": 246.0, "melt_hi": 257.0, "die_plate_bar": 140.0},
}
## The extruders that have a profile of their own. Lines 1, 3C and 6 have no
## trend export and no FORM-008 kopdruk row: they carry DEFAULT_PROFILE and say
## so through `profile_carried`. That is a labelled stand-in, not a measurement.
const OWN_PROFILE : Dictionary = {"extruder_3a": "3A", "extruder_3b": "3B"}
const DEFAULT_PROFILE : String = "3B"

# =============================================================================
# STATE  (the spec's required surface)
# =============================================================================
var screw_rpm         : float = 0.0     # live screw speed (rev/min)
var viscosity         : float = 0.0     # apparent melt viscosity (Pa·s)
var shear_heat        : float = 0.0     # viscous-dissipation heat source (°C/s)
var barrel_temp       : float = 0.0     # barrel-zone heater SETPOINT (°C)
var melt_temp         : float = 25.0    # actual polymer melt temperature (°C)
var cooling_fan_level : float = 0.0     # 0..1 forced-convection cooling demand
var die_pressure      : float = 0.0     # die-plate pressure, after the kopfilter (bar)

# ── Operating point (set by apply_profile; see PROFILES) ──────────────────────
var profile_id              : String = ""
var profile_carried         : bool   = false  # true ⇒ this line has no profile of its own
var rpm_nominal             : float  = 0.0    # screw rpm at rpm_pct 1.0
var nominal_throughput_kg_s : float  = 0.0
var melt_target_lo          : float  = 0.0
var melt_target_mid         : float  = 0.0    # PI setpoint of the cooling fan
var melt_target_hi          : float  = 0.0
var die_plate_nominal_bar   : float  = 0.0
var _eta_nominal            : float  = 1.0    # viscosity at the nominal rpm + melt

# ── Command / load inputs (set by the caller; sensible standalone defaults) ────
var rpm_setpoint      : float = 0.0     # commanded screw rpm (slews toward it)
var throughput        : float = 0.0     # mass flow through the die (kg/s)
var fan_auto          : bool  = true    # PI fan controller on (false ⇒ manual fan)

# ── Internal controller state ─────────────────────────────────────────────────
var _fan_integral     : float = 0.0

# =============================================================================
## Built on DEFAULT_PROFILE. `barrel_setpoint_c` overrides the profile's barrel
## setpoint (tests pin it); `start_melt_c` is the melt at t=0.
func _init(barrel_setpoint_c: float = NAN, start_melt_c: float = 25.0) -> void:
	apply_profile(DEFAULT_PROFILE)
	throughput = nominal_throughput_kg_s
	if not is_nan(barrel_setpoint_c):
		barrel_temp = barrel_setpoint_c
	melt_temp   = start_melt_c
	viscosity   = _apparent_viscosity(0.0, melt_temp)

## Set the operating point from PROFILES. The lumped barrel's setpoint is the
## melt the trend shows (melt_mid): FORM-008 rows 23/24 list seven zone
## setpoints (200-235-175-240-245-250-255) that this one-node model cannot place.
func apply_profile(key: String) -> void:
	profile_id = key if PROFILES.has(key) else DEFAULT_PROFILE
	var p : Dictionary = PROFILES[profile_id]
	rpm_nominal             = float(p["rpm_nominal"])
	nominal_throughput_kg_s = float(p["kg_h_nominal"]) / 3600.0
	melt_target_lo          = float(p["melt_lo"])
	melt_target_mid         = float(p["melt_mid"])
	melt_target_hi          = float(p["melt_hi"])
	die_plate_nominal_bar   = float(p["die_plate_bar"])
	barrel_temp             = melt_target_mid
	_eta_nominal = _apparent_viscosity(rpm_nominal * RPM_TO_SHEAR, melt_target_mid)

## The profile for a LineFlow extruder id: its own where one exists, else
## DEFAULT_PROFILE with `profile_carried` set.
func configure_for_extruder(extruder_id: String) -> void:
	apply_profile(String(OWN_PROFILE.get(extruder_id, DEFAULT_PROFILE)))
	profile_carried = not OWN_PROFILE.has(extruder_id)

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

## Mass flow through the die in kg/s (drives die_pressure). 0 ⇒ starved screw.
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

	# 4) Cooling fan — PI controller pulls the melt back into its window. Fans can
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

	# 6) Die-plate pressure — drag-flow vs die-resistance balance. Thinner melt
	#    (hotter / faster sheared) at the same throughput drops it; the MFI proxy
	#    keys on exactly this signal. Starved screw ⇒ no pressure. Anchored at the
	#    profile's nominal point instead of a free resistance constant: the old
	#    DIE_RESISTANCE 6.5e-4 · eta · flow read 0.11 bar at 950 kg/h, which put
	#    the MFI proxy at 1491 g/10min and made the QA bench REJECT every sample.
	var flow_norm : float = throughput / nominal_throughput_kg_s if nominal_throughput_kg_s > 0.0 else 0.0
	die_pressure = die_plate_nominal_bar * (viscosity / maxf(_eta_nominal, VISC_MIN_PAS)) * flow_norm

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
## Drive cooling_fan_level (0..1) to hold melt_temp near melt_target_mid. Error is
## "how far above the midpoint" (cooling can only pull DOWN), with anti-windup on
## the integral and a slew limit so the fan has realistic inertia.
func _update_fan_controller(dt: float) -> void:
	var error : float = melt_temp - melt_target_mid      # +ve ⇒ too hot ⇒ cool harder
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
## True while the melt sits inside the profile's melt window (the trend's p5–p95).
func melt_in_target_band() -> bool:
	return melt_temp >= melt_target_lo and melt_temp <= melt_target_hi

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
		"profile_id":        profile_id,
		"profile_carried":   profile_carried,
	}

func _to_string() -> String:
	return "ExtruderScrew[%s%s](%.0f rpm | eta %.0f Pa·s | shear %.2f °C/s | melt %.1f°C (barrel %.0f) | fan %.0f%% | die plate %.1f bar)" % [
		profile_id, " carried" if profile_carried else "", screw_rpm, viscosity, shear_heat,
		melt_temp, barrel_temp, cooling_fan_level * 100.0, die_pressure]
