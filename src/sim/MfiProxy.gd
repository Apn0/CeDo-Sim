extends RefCounted
class_name MfiProxy
## Predictive MFI / die-pressure proxy — an INSTANTANEOUS soft-sensor for melt
## flow index, with NO lab delay (a real MFI is a 10-minute bench test on a
## granulaat sample; this is the proxy the line "knows" in real time).
##
## PHYSICS — capillary / die flow (Hagen–Poiseuille intuition):
##
##     MFI ∝ Q / (P_die · η(T))
##
##   • Q       — mass throughput (kg/h) pushed through the die.
##   • P_die   — melt pressure at the die plate (bar), after the kopfilter
##               (operator ruling 2026-09-24; LineFlow feeds ExtruderScrew's
##               die_pressure). For a FIXED die geometry and a fixed Q, a HIGHER
##               pressure means the melt is harder to push → stiffer,
##               higher-molecular-weight, LOWER-MFI material.
##               So at constant Q and T, predicted_mfi is INVERSELY proportional
##               to P_die — the property this proxy exists to surface.
##   • η(T)    — shear/temperature viscosity. Hotter melt flows easier (lower η),
##               which RAISES MFI at the same Q and P_die. Modelled with an
##               Arrhenius-style decay around a reference temperature.
##
## The proportionality constant MFI_GAIN folds the die geometry (length, radius,
## the 2.16 kg ISO-1133 test weight, unit conversions) into one calibration
## number. It is DERIVED from an anchor point (CAL_*), not typed. The output is
## ABSOLUTE, not a ratio: QaSpec grades it against fixed limits and the SCADA
## panel draws it against a fixed band, so the anchor has to move whenever the
## scale of its inputs does.
##
## DOWNSTREAM VISUALS (particles / shaders) — predicted_mfi is a single float in
## a known band, so a consumer can normalise it once and drive a look:
##   var f := mfi.normalized()                       # 0..1 across MFI_VIS_LOW..HIGH
##   # GPUParticles3D: emission/speed ↑ with flow  → material.emission_rate = lerp(lo, hi, f)
##   # ShaderMaterial:  set_shader_parameter("mfi", f) and tint runny vs stiff melt,
##   #                  or scale a flow-line scroll speed / strand-sag in the vertex stage.
## Because update() is pure + instantaneous, a visual can read predicted_mfi (or
## call normalized()) every frame straight after the sim tick with no smoothing lag.

# ── Calibration (folds die geometry + test weight + unit scaling) ──────────────
## The anchor: line 3B's nominal point from the plant. Output p50 799 kg/h and
## melt p50 246 °C come from the EREMA WinCC archive (docs/plant/
## trends_overview.md §2). The 140 bar die plate is ExtruderScrew.PROFILES
## "3B": the bottom of FORM-008 row 26's kopdruk window, per the operator's
## 2026-09-24 ruling that this pressure is the die plate after the kopfilter.
## Until 2026-09-24 the anchor was an invented 950 kg/h / 250 bar / 215 °C
## (MFI_GAIN 0.263). Fed the plant's point, that gain reads 4.3 on line 3A,
## which QaSpec grades REGRADE.
const CAL_Q_KG_H : float = 799.0
const CAL_P_BAR  : float = 140.0
const CAL_T_C    : float = 246.0
## The MFI the anchor reads. NOT a plant number: no document gives CeDo's
## granulaat MFI, and QaSpec's band is a labelled placeholder. 1.0 is this
## proxy's own original design target. It is kept so that a nominal line lands
## where QaSpec and the SCADA band expect it.
const CAL_MFI    : float = 1.0
## Overall gain on Q / (P·η), solved from the anchor. It never changes the
## proportions the proxy reports, only their absolute level.
const MFI_GAIN : float = (CAL_MFI * CAL_P_BAR * VISCOSITY_REF
	* pow(2.0, (REF_TEMP_C - CAL_T_C) / TEMP_DECADE_C) / CAL_Q_KG_H)

# ── Viscosity model η(T) ───────────────────────────────────────────────────────
## Reference viscosity (arbitrary normalised Pa·s-like units) at REF_TEMP_C.
const VISCOSITY_REF      : float = 1.0
const REF_TEMP_C         : float = 215.0    # LDPE-film reclaim melt setpoint
## Arrhenius-ish sensitivity: every TEMP_DECADE_C degrees hotter ~halves η.
## η(T) = VISCOSITY_REF · 2^((REF_TEMP_C − T) / TEMP_DECADE_C)
const TEMP_DECADE_C      : float = 30.0
## Above this, an incoming `viscosity_or_temp` is interpreted as a TEMPERATURE
## in °C and converted through viscosity_at_temp(); at/below it, it is taken as a
## viscosity value directly. Melt temps (~150–260 °C) sit far above any sane
## normalised viscosity (~0.2–3.0), so the split is unambiguous in practice.
const VISCOSITY_TEMP_THRESHOLD : float = 20.0

# ── Visual normalisation band (g/10 min) ───────────────────────────────────────
## The MFI window a downstream visual maps onto 0..1 (see normalized()).
const MFI_VIS_LOW  : float = 0.2
const MFI_VIS_HIGH : float = 2.5

# ── Cached output ───────────────────────────────────────────────────────────────
## Last computed predicted MFI (g/10 min). Read directly by HMI / visuals; also
## returned by update(). Starts at 0 until the first update() call.
var predicted_mfi : float = 0.0

# Last resolved inputs, kept for the HMI / debugging (what the proxy last saw).
var last_throughput   : float = 0.0   # Q   (kg/h)
var last_die_pressure : float = 0.0   # P   (bar)
var last_viscosity    : float = 0.0   # η   (resolved, normalised units)

# =============================================================================
# CORE
# =============================================================================
## Recompute and cache predicted_mfi from live extruder numbers. INSTANTANEOUS —
## no averaging, no lab delay.
##
##   Q                  — throughput (kg/h). Non-positive → 0 melt flowing → MFI 0.
##   die_pressure       — die-plate melt pressure (bar). Clamped away from 0 so a
##                        starved/zeroed sensor can't divide-by-zero into infinity.
##   viscosity_or_temp  — EITHER a viscosity (≤ VISCOSITY_TEMP_THRESHOLD) used as
##                        η directly, OR a melt temperature in °C (> threshold)
##                        converted via viscosity_at_temp(). This is the η(T) term.
##
## Returns the freshly cached predicted_mfi.
func update(Q: float, die_pressure: float, viscosity_or_temp: float) -> float:
	var eta := resolve_viscosity(viscosity_or_temp)
	last_throughput   = Q
	last_die_pressure = die_pressure
	last_viscosity    = eta

	# No throughput or no viscosity → nothing meaningfully flowing.
	if Q <= 0.0 or eta <= 0.0:
		predicted_mfi = 0.0
		return predicted_mfi

	# Guard the denominator: a real die never sees 0 bar while extruding, but a
	# cold/starved sensor can report ~0. Floor it so MFI stays finite.
	var p := maxf(die_pressure, 0.001)
	predicted_mfi = MFI_GAIN * Q / (p * eta)
	return predicted_mfi

## η(T): viscosity at melt temperature T (°C). Arrhenius-style — hotter melt is
## exponentially runnier, which is what lets temperature trade off against
## pressure in the MFI prediction. Pure; safe to call standalone for tuning.
static func viscosity_at_temp(temp_c: float) -> float:
	return VISCOSITY_REF * pow(2.0, (REF_TEMP_C - temp_c) / TEMP_DECADE_C)

## Interpret the flexible third argument of update(): a big number is a melt
## temperature in °C (run through viscosity_at_temp); a small one is already a
## viscosity and used as-is. Lets callers pass whichever they have on hand.
static func resolve_viscosity(viscosity_or_temp: float) -> float:
	if viscosity_or_temp > VISCOSITY_TEMP_THRESHOLD:
		return viscosity_at_temp(viscosity_or_temp)
	return viscosity_or_temp

# =============================================================================
# QUERIES (for HMI + downstream visuals)
# =============================================================================
## predicted_mfi mapped to 0..1 across [MFI_VIS_LOW, MFI_VIS_HIGH], clamped.
## A particle system or shader can consume this directly as a flow intensity.
func normalized() -> float:
	if MFI_VIS_HIGH <= MFI_VIS_LOW:
		return 0.0
	return clampf((predicted_mfi - MFI_VIS_LOW) / (MFI_VIS_HIGH - MFI_VIS_LOW), 0.0, 1.0)

## A coarse operator-readable grade of the melt's flow behaviour.
func flow_label() -> String:
	if predicted_mfi <= 0.0:
		return "no flow"
	if predicted_mfi < MFI_VIS_LOW:
		return "stiff"          # high MW / high pressure — sluggish melt
	if predicted_mfi > MFI_VIS_HIGH:
		return "runny"          # low MW / low pressure — thin melt
	return "nominal"

func to_dict() -> Dictionary:
	return {
		"predicted_mfi": predicted_mfi,
		"throughput":    last_throughput,
		"die_pressure":  last_die_pressure,
		"viscosity":     last_viscosity,
		"normalized":    normalized(),
		"flow_label":    flow_label(),
	}

func _to_string() -> String:
	return "MfiProxy(MFI %.2f g/10min [%s]  Q %.0f kg/h  P %.0f bar  eta %.2f)" \
		% [predicted_mfi, flow_label(), last_throughput, last_die_pressure, last_viscosity]
