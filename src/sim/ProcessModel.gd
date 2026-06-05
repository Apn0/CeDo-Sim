extends RefCounted
class_name ProcessModel

## BAKED physics model for LINE 3C (#173) — the "exact numbers, computed once,
## read cheap at runtime" approach the operator asked for.
##
## Each of the 23 Line3CDef stages gets calibrated coefficients for what it does
## to the material (water, contamination, density separation, yield) PLUS an
## energy model that reproduces the real HMI currents. The heavy part is DERIVING
## the coefficients (deep research + plant figures + the HMI amps); the runtime
## just evaluates closed-form transfer functions — microseconds, no lag.
##
## ── STATUS ────────────────────────────────────────────────────────────────────
## • ENERGY model: CALIBRATED NOW to the real HMI amps in Line3CDef — at full
##   load each stage draws exactly its screenshot current, scaling down toward a
##   motor idle current as throughput drops.
## • SEPARATION / WASH / DRY coefficients: pending the deep-research figures
##   (friction-wash water uptake & contaminant removal, sink/float efficiency vs
##   density, drying curves, dewatering press, melt+laser-filter capture). Until
##   those land, callers fall back to MachineFlow's existing per-pass fractions.

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")

const NOMINAL_KG_H : float = 1687.0    # Line 3C design throughput (Line3CDef.LINE_SPEED_KG_H)

# A loaded induction motor still draws ~30-40% of full-load current at no load
# (magnetising + friction + windage). We use 35%: amps(load) ramps from this
# idle floor up to the full HMI reading at nominal throughput.
const MOTOR_IDLE_FRAC : float = 0.35

# =============================================================================
# ENERGY MODEL  (calibrated to the real HMI amps)
# =============================================================================
## Live current (A) for a stage drawing `hmi_amps` at full load, when the line is
## running at `load_frac` (= current throughput / nominal). Calibrated so that
## load_frac = 1.0 returns exactly the HMI amps, and an unloaded-but-spinning
## motor sits at MOTOR_IDLE_FRAC of that. Returns 0 when stopped or unmetered.
static func stage_amps(hmi_amps: float, load_frac: float, running: bool) -> float:
	if not running or hmi_amps <= 0.0:
		return 0.0
	var idle := hmi_amps * MOTOR_IDLE_FRAC
	return idle + (hmi_amps - idle) * clampf(load_frac, 0.0, 1.25)

## Same, but looks the stage's nominal current up from Line3CDef by its HMI code.
static func live_amps_for_stage(code: String, load_frac: float, running: bool) -> float:
	return stage_amps(hmi_amps_for_code(code), load_frac, running)

## The nominal (full-load) HMI current for a stage code, or 0 if not on the HMI.
static func hmi_amps_for_code(code: String) -> float:
	for st in Line3CDefScript.STAGES:
		if String(st["code"]) == code:
			return float(st["amps"])
	return 0.0

## Total nominal connected current of the whole line at full load (sum of the HMI
## readings) — a sanity anchor for the energy model / future kWh-per-tonne calc.
static func line_nominal_amps() -> float:
	var total := 0.0
	for st in Line3CDefScript.STAGES:
		total += float(st["amps"])
	return total

## Load fraction implied by a throughput (kg/h) against the line's design rate.
static func load_fraction(throughput_kg_h: float) -> float:
	if NOMINAL_KG_H <= 0.0:
		return 0.0
	return clampf(throughput_kg_h / NOMINAL_KG_H, 0.0, 1.25)

# =============================================================================
# MATERIAL TRANSFER MODEL  (per-pass coefficients, keyed by Line3CDef HMI code)
# =============================================================================
## What each stage does to the material in ONE pass. Keys map straight onto the
## MaterialBatch process primitives LineFlow already applies:
##   water_add     — kg water taken on = water_add × current polymer_kg (wash wets)
##   water_remove  — fraction of CURRENT water driven off (dry / press / degas)
##   contam_remove — fraction of CURRENT dirt stripped to a scraper bin
##   reject_other  — fraction of off-spec polymer (PET/PVC heavies) sunk out
##   reject_hdpe   — fraction of HDPE sorted out
##   waste         — fraction of TOTAL mass lost as fines (mechanical yield loss)
##
## ── CALIBRATION (sources in the bake test) ───────────────────────────────────
## The per-pass numbers are chosen so the WHOLE-LINE composition reproduces the
## VERIFIED research anchors when an input of dirty-wet post-consumer film flake
## is run head→tail:
##   • mass yield 73-85 % (Austrian real-plant LCA, PMC9460591: 73% measured)
##   • density separators clear the sinking heavies/PET/PVC at high efficiency
##     (sink-float ~97.5% PO recovery ceiling, Adamcová 2021 — de-rated for film)
##   • washing is distributed across the friction stages (washing = the dominant
##     wet-line duty, Granada LCA, Martín-Lara 2022)
##   • flake leaves bone-dry to the extruder after the mech dryers + Plasmaq press
##     + extruder vacuum degas (drying drivers per Berkane 2023)
## Friction-wash per-pass efficiencies, dryer in/out moisture, and screw-press
## outlet moisture were NOT pinned by verified sources — these are engineering
## estimates tuned to the verified ENDPOINTS, and are the values the operator's
## real figures should refine. L/R duplicates are modelled as series passes
## (matching the LineFlow chain); true L/R-parallel is a later topology refinement.

# ── REAL OPERATING POINTS (CeDo training binder + operator, #174) ─────────────
# Documented anchors the bake is calibrated against. All tunable as exact data lands.
const MELT_TEMP_C        : float = 250.0      # extruder melt temp (operator)
const VACUUM_ZONES       : int   = 2          # vacuum vent PORTS — HMI/operator-derived (2 columns on the HMI). NB EREMA publishes "triple degassing" as 3 STAGES (PCU pre-dry + reverse-degas + vacuum zone), not a port count; confirm port count with operator.
const COMPACTOR_KW       : float = 150.0      # compactor power band 130–160 kW (doc 102)
const FEED_MOISTURE_PCT  : float = 8.0        # flake AT the compactor feed: 5–10% typ (2–18% extreme)
const FINAL_MOISTURE_PCT : float = 0.3        # granulate out ≈ 0 (operator: 0.1–0.5%, often less)
const LASER_MICRON       : float = 165.0      # laserfilter mesh ~150–210 µm (L3a/L3b, doc 121)
# ── Labelled 3C extruder HMI (operator screenshot, #175) — real operating points ──
# These are the values read straight off the 3C extruder HMI and are the authoritative
# component IDs for the back-end (PCU = compactor; the big concentric circle = the
# Laserfilter, NOT the PCU; the gear block = the Meltpump).
const PCU_TEMP_C        : float = 112.0       # PCU (compactor) preconditioning temp
const PCU_KW            : float = 169.0       # PCU (compactor) drive power
const EXTRUDER_RPM      : float = 138.0       # extruder screw speed
const EXTRUDER_TORQUE_PCT : float = 53.0      # extruder torque/load
const EXTRUDER_KW       : float = 187.0       # extruder drive power
const LASER_INLET_BAR   : float = 259.0       # melt pressure into the laserfilter
const LASER_LOAD_PCT    : float = 81.45       # laserfilter screen loading
const MELTPUMP_BAR      : float = 25.0        # meltpump regulated pressure
const HEAD_BAR          : float = 86.0        # die-head pressure
const EXTRUDER_KG_H     : float = 716.0       # throughput shown on this HMI snapshot
# ── EREMA model identification (#175 research — sources in the report) ─────────
# The HMI fingerprint (PCU label + big rotary Laserfilter + printed/moist film duty)
# identifies this as an EREMA INTAREMA TVEplus single-Laserfilter machine. Size is
# inferred from EREMA's published PE-LD/LLDPE throughput table + the model-number
# decode [PCU-bowl-Ø-dm][screw-Ø-cm]: 1512 = 1.5 m PCU + 120 mm screw, rated
# 950–1200 kg/h, so 716 kg/h is ~65% load. Confirm the model plate with the operator.
const EREMA_PLATFORM    : String = "INTAREMA TVEplus"   # sourced: erema.com/intarema_tveplus (conf 0.85)
const EREMA_MODEL       : String = "1512"               # inferred from decode + 950–1200 band (conf 0.55)
const EREMA_SCREW_MM    : float  = 120.0                # inferred (1512 → 120 mm screw)
const EREMA_PCU_M       : float  = 1.5                  # inferred (1512 → 1.5 m PCU bowl)
const FILTER_BEFORE_DEGAS : bool = true                 # sourced: TVEplus filters before it degasses (conf 0.95)
# CeDo runs a SINGLE Laserfilter — the operator confirms no double/DuaFil variant
# exists for this line's filter, so the double-filter arrangement is intentionally
# NOT modelled (not in the plant documentation).
const LASER_MAX_BAR     : float  = 320.0                # sourced: POWERFIL Laserfilter max working pressure
const LASER_FINENESS_MIN_MICRON : float = 70.0          # sourced: Laserfilter fineness floor ~70 µm
# Operator: 1687 kg/h dirty flake in → ~1000–1200 kg/h granulate out. So CeDo's
# REAL yield is ~59–71% (mid ~65%) — below the literature 73–85% (dirty film +
# fines flung to the gutter cost more). The operator's number wins.
const NOMINAL_YIELD   : float = 0.65
const OUTPUT_KG_H_LOW : float = 1000.0
const OUTPUT_KG_H_HIGH: float = 1200.0
# Residence times (operator): wash line Doseer Silo → Extruder Silo ≈ 10 min
# (8–12, longer while the compactor/flotation/bezink buffers fill at start-up);
# extruder Compactor → pelletizer ≈ 5 min (4–6). Whole line ≈ 15 min.
const WASH_RESIDENCE_S     : float = 600.0
const EXTRUDER_RESIDENCE_S : float = 300.0
# Known heavies-reject draw at the two density separators: ~1 × 400 kg container
# every ~4 h each ≈ 100 kg/h (operator). The friction/dryer FINES carry no plant
# count, so they're estimated so the whole-line yield lands in the verified band.
const REJECT_KG_H : Dictionary = { "L3C.3": 100.0, "L3C.11": 100.0 }

const STAGE_PHYSICS : Dictionary = {
	"L3C.1":  {},                                                              # Doseer Silo — intake buffer (moisture here doesn't matter; it gets washed)
	"L3C.3":  {"contam_remove": 0.22, "reject_other": 0.42, "water_add": 0.14, "waste": 0.004},  # Bezinkafscheider — heavies sink (~100 kg/h)
	"L3C.4L": {"contam_remove": 0.25, "water_add": 0.10, "waste": 0.012},      # Frictiescheider — scrub wash + microplastic fines to the gutter
	"L3C.4R": {"contam_remove": 0.25, "water_add": 0.10, "waste": 0.012},
	"L3C.5L": {"water_remove": 0.12},                                          # Transportschroef — drains a little
	"L3C.5R": {"water_remove": 0.12},
	"L3C.6":  {"waste": 0.012},                                                # Maalmolen — wet mill, fines loss
	"L3C.9L": {"contam_remove": 0.25, "water_add": 0.08, "waste": 0.012},      # Frictiescheider
	"L3C.9R": {"contam_remove": 0.25, "water_add": 0.08, "waste": 0.012},
	"L3C.10L":{"water_remove": 0.12},
	"L3C.10R":{"water_remove": 0.12},
	"L3C.11": {"contam_remove": 0.55, "reject_other": 0.90, "water_add": 0.10, "waste": 0.004},  # Flotatietank — heavies sink (~100 kg/h, clears the rest)
	"L3C.12": {"water_remove": 0.12},
	"L3C.13": {"contam_remove": 0.40, "water_add": 0.06, "waste": 0.012},      # Frictiescheider — final wash + fines
	"L3C.14L":{"water_remove": 0.50, "waste": 0.016},                          # Mechanische droger — sieve flings fines + water out
	"L3C.14R":{"water_remove": 0.50, "waste": 0.016},
	"L3C.15": {"water_remove": 0.20},                                          # Transportventilator — air carry
	"L3C.16": {"water_remove": 0.38},                                          # Plasmaq — screw-press dewatering → flake at ~5–10% to compactor
	"L3C.18": {},                                                              # Extruder Silo — buffer (compactor feed ≈ FEED_MOISTURE_PCT)
	"L3C.19": {"water_remove": 0.05},                                          # Rondmeng ventilator — light mixing air
	"Cband":  {},                                                              # Compactorband — feed belt into the compactor (inert convey)
	# PCU = the EREMA cutter/COMPACTOR (friction heat + steam): pre-dries + densifies
	# the flake. The EXTRUDER screw then melts at 250 °C and the 2× vacuum degas
	# zones pull the residual moisture off — together they take the 5–10% feed down
	# to ≈ 0. (Labelled 3C HMI: PCU 112 °C/169 kW; Extruder 138 rpm/187 kW.)
	"PCU":    {"water_remove": 0.85, "contam_remove": 0.35},                    # Compactor (PCU) — friction pre-dry + densify (melt contained, no fines)
	"Extr":   {"water_remove": 0.10},                                          # Extruder screw — plasticise + reverse-degas precondition (the filter loop runs here)
	# TVEplus order: FILTER first, THEN degas. The screw loops the melt out through
	# the Laserfilter and back, then the vacuum zone degasses the CLEANED melt.
	"Laser":  {"contam_remove": 0.60, "waste": 0.004},                         # Laserfilter — rotary DISC melt filter (BEFORE degassing — TVEplus patent)
	"Degas":  {"water_remove": 0.85, "contam_remove": 0.20},                    # Vacuum degassing — pulls residual moisture + volatiles off the FILTERED melt
	"Melt":   {"waste": 0.003},                                                # Meltpump — pressurises the cleaned, degassed melt to the die
	"Kop":    {"waste": 0.003},                                                # Diekop — pelletizer die head (single-Laserfilter TVEplus: NOT a screen filter)
	# ── pelletizer water cycle (operator: pellet water is surface-only) ───────
	# Heetafslag hot-face cut forms the granulate and a water ring quenches the
	# pellet OUTSIDE only (a few % surface water); the dewater screen + centrifuge
	# then pull almost all of it back off, so the granulate leaves at 0.1–0.5%.
	"Heet":   {"water_add": 0.05, "waste": 0.004},                             # Heetafslag — pellets form + surface quench water on
	"Ontw":   {"water_remove": 0.80, "waste": 0.002},                          # Ontwaterzeef — vibrating dewater screen drains surface water
	"Centr":  {"water_remove": 0.78, "waste": 0.002},                          # Centrifuge — spin-dry to ~0.2% residual
	"Weeg":   {},                                                              # Weegschaal — 25 kg batch weigh (inert)
	"Voorraad": {},                                                            # Voorraad Silo — finished-granulate store (line product sink)
}

## Calibrated per-pass transfer coefficients for a Line 3C stage (by HMI code).
## Missing keys default to 0, so a stage with no entry is an inert pass-through.
static func stage_transfer(code: String) -> Dictionary:
	var t := {"water_add": 0.0, "water_remove": 0.0, "contam_remove": 0.0,
			  "reject_other": 0.0, "reject_hdpe": 0.0, "waste": 0.0}
	var ov : Dictionary = STAGE_PHYSICS.get(code, {})
	for k in ov:
		t[k] = ov[k]
	return t

## True when this HMI code is a calibrated Line 3C bake stage.
static func has_stage(code: String) -> bool:
	return STAGE_PHYSICS.has(code)
