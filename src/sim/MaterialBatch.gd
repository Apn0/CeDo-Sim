extends RefCounted
class_name MaterialBatch
## The canonical accounting unit of material moving through the plant.
##
## DISCRETE-HYBRID model (per the design rule):
##   • On conveyor belts and inside pressurised transport pipes the material does
##     not change, so it travels as a SINGLE snapshotted MaterialBatch instance
##     (cheap — no per-particle simulation).
##   • At transformation points — cyclones, shredders/mills, the PCU/compactor —
##     a batch is EXPANDED into physicalised particles for the duration it's in
##     that zone, then RE-SNAPSHOTTED back into a batch on the way out.
##
## Whichever representation is active, the MaterialBatch stays the source of
## truth for accounting, which guarantees the hard invariant:
##
##   VOLUME AND WEIGHT MUST ALWAYS MATCH INPUT/OUTPUT.
##
## Nothing is created or destroyed — a process that changes bulk density (baled
## film → loose flake → dried flake → melt → pellet) does so by moving mass/volume
## into explicit side streams (water, air, waste), never by silently losing it.
## split_*() and add()/merge() below conserve mass and volume exactly.
##
## WET + DIRTY MODEL: a real film-recycling line exists to fight two enemies —
## WATER and CONTAMINATION. So mass_kg is the TOTAL wet, dirty mass, and two
## explicit sub-masses ride inside it:
##   • water_kg       — free + clinging water (washing ADDS it, drying DRIVES it off)
##   • contaminant_kg — sand, paper, organics, non-PE fines (washing/sorting strip it)
## The remainder (mass_kg − water − contaminant) is clean polymer solids, whose
## LDPE/HDPE/other mix is held in `composition`. Every conserving op carries the
## two sub-masses, and the process primitives (remove_water / remove_contaminant /
## add_water / reject_polymer) move them into explicit side streams.

var mass_kg   : float = 0.0
var volume_m3 : float = 0.0
# polymer_id (String) → mass fraction of the POLYMER SOLIDS (sums to ~1.0).
# Water and contaminant are NOT in here — they are tracked as sub-masses below.
var composition : Dictionary = {}
# Human-readable provenance ("Rotterdam", "mixed", "flake 3B", …).
var origin : String = ""

# Sub-masses contained WITHIN mass_kg (the balance is clean polymer solids).
var water_kg       : float = 0.0   # moisture riding with the film
var contaminant_kg : float = 0.0   # dirt / sand / paper / organics — NOT plastic

func _init(mass: float = 0.0, volume: float = 0.0, comp: Dictionary = {}, src: String = "",
		water: float = 0.0, contaminant: float = 0.0) -> void:
	mass_kg = mass
	volume_m3 = volume
	composition = comp.duplicate()
	origin = src
	water_kg = water
	contaminant_kg = contaminant

# =============================================================================
# QUERIES
# =============================================================================
func bulk_density() -> float:
	return mass_kg / volume_m3 if volume_m3 > 0.0 else 0.0

func is_empty() -> bool:
	return mass_kg <= 0.0001 and volume_m3 <= 0.0001

func fraction_of(polymer_id: String) -> float:
	return float(composition.get(polymer_id, 0.0))

func ldpe_fraction() -> float:
	return fraction_of("LDPE")

## Clean polymer solids (kg): everything that is not water or contaminant.
func polymer_kg() -> float:
	return maxf(0.0, mass_kg - water_kg - contaminant_kg)

## Moisture as a percent of total mass (0..100).
func moisture_pct() -> float:
	return (water_kg / mass_kg) * 100.0 if mass_kg > 0.0 else 0.0

## Contamination as a percent of total mass (0..100).
func contam_pct() -> float:
	return (contaminant_kg / mass_kg) * 100.0 if mass_kg > 0.0 else 0.0

## Clean polymer as a percent of total mass (0..100).
func purity_pct() -> float:
	return (polymer_kg() / mass_kg) * 100.0 if mass_kg > 0.0 else 0.0

## A 0..100 melt-quality grade for a stream about to be pelletised. Penalises
## residual moisture (brutal in the melt — bubbles/hydrolysis), residual dirt
## (gels/black specks), and off-spec polymer (raises MFI scatter). Heuristic,
## tuned so a well-washed, well-dried, well-sorted LDPE stream lands ~90+.
func quality_grade() -> float:
	var offspec := (1.0 - ldpe_fraction()) * 100.0   # % of polymer that isn't LDPE
	var q := 100.0
	q -= moisture_pct() * 6.0     # 1% residual moisture ≈ −6 pts
	q -= contam_pct()  * 10.0     # 1% residual dirt     ≈ −10 pts
	q -= offspec       * 0.25     # 1% off-spec polymer  ≈ −0.25 pts
	return clampf(q, 0.0, 100.0)

func duplicate_batch() -> MaterialBatch:
	return MaterialBatch.new(mass_kg, volume_m3, composition, origin, water_kg, contaminant_kg)

# =============================================================================
# CONSERVING SPLIT / MERGE
# =============================================================================
## Remove `frac` (0..1) of this batch and return it as a new batch. The two
## halves together still equal the original mass + volume (conserved). Water and
## contaminant split proportionally so concentrations are preserved.
func split_fraction(frac: float) -> MaterialBatch:
	frac = clampf(frac, 0.0, 1.0)
	var taken := MaterialBatch.new(mass_kg * frac, volume_m3 * frac, composition, origin,
								   water_kg * frac, contaminant_kg * frac)
	mass_kg        -= taken.mass_kg
	volume_m3      -= taken.volume_m3
	water_kg       -= taken.water_kg
	contaminant_kg -= taken.contaminant_kg
	return taken

## Take `kg` of mass off this batch (proportional volume + sub-masses go with it).
func split_mass(kg: float) -> MaterialBatch:
	if mass_kg <= 0.0:
		return MaterialBatch.new(0.0, 0.0, composition, origin)
	return split_fraction(clampf(kg / mass_kg, 0.0, 1.0))

## Pour `other` into this batch. Mass + volume + sub-masses add; the polymer
## composition is mass-weighted by POLYMER mass (so dirt/water don't dilute the
## reported polymer mix).
func add(other: MaterialBatch) -> void:
	if other == null or other.is_empty():
		return
	var w_self  := polymer_kg()
	var w_other := other.polymer_kg()
	if w_self + w_other <= 0.0:          # both are pure water/dirt — weight by total
		w_self  = mass_kg
		w_other = other.mass_kg
	var wsum := w_self + w_other
	if wsum > 0.0:
		var blended : Dictionary = {}
		for k in composition:
			blended[k] = float(composition[k]) * w_self
		for k in other.composition:
			blended[k] = float(blended.get(k, 0.0)) + float(other.composition[k]) * w_other
		for k in blended:
			blended[k] = float(blended[k]) / wsum
		composition = blended
	mass_kg        += other.mass_kg
	volume_m3      += other.volume_m3
	water_kg       += other.water_kg
	contaminant_kg += other.contaminant_kg
	if origin != other.origin and other.origin != "":
		origin = "mixed"

static func merge(a: MaterialBatch, b: MaterialBatch) -> MaterialBatch:
	var r := a.duplicate_batch()
	r.add(b)
	return r

# =============================================================================
# PROCESS TRANSFORMS
# Each conserves mass: it removes a side stream and RETURNS how much left, so the
# caller can route it (scraper bin, effluent counter) and keep the plant ledger
# balanced. Volume tracks the lost/gained mass so bulk density moves realistically.
# =============================================================================
## DRYING (centrifuge / thermal / mechanical dryer): drive off `frac` (0..1) of
## the water. Returns kg of water removed — it leaves as vapour / press effluent.
## Volume shrinks with the lost water, so the flake's bulk density rises.
func remove_water(frac: float) -> float:
	frac = clampf(frac, 0.0, 1.0)
	var dw := water_kg * frac
	if dw <= 0.0:
		return 0.0
	water_kg  -= dw
	mass_kg    = maxf(0.0, mass_kg - dw)
	volume_m3  = maxf(0.0, volume_m3 - dw / 1000.0)   # water ≈ 1000 kg/m³
	return dw

## WASHING / SORTING: strip `frac` (0..1) of the dirt out to a reject stream.
## Returns kg of contaminant removed (caller sends it to the nearest scraper bin).
func remove_contaminant(frac: float) -> float:
	frac = clampf(frac, 0.0, 1.0)
	var dc := contaminant_kg * frac
	if dc <= 0.0:
		return 0.0
	var dv := volume_m3 * (dc / mass_kg) if mass_kg > 0.0 else 0.0
	contaminant_kg -= dc
	mass_kg         = maxf(0.0, mass_kg - dc)
	volume_m3       = maxf(0.0, volume_m3 - dv)
	return dc

## WASHING: take on `kg` of clean process water (raises moisture + bulk volume).
## This is where the line's water demand comes from (fed by the ZSS water plant).
func add_water(kg: float) -> void:
	if kg <= 0.0:
		return
	water_kg  += kg
	mass_kg   += kg
	volume_m3 += kg / 1000.0

## OPTICAL / BALLISTIC SORTING (TITECH / TOMRA / wind sifter): reject `frac`
## (0..1) of one polymer key (e.g. "other" or "HDPE") to a reject stream. Returns
## kg removed. The remaining composition renormalises over the surviving polymer.
func reject_polymer(key: String, frac: float) -> float:
	frac = clampf(frac, 0.0, 1.0)
	var poly := polymer_kg()
	if poly <= 0.0:
		return 0.0
	var dm := poly * float(composition.get(key, 0.0)) * frac
	if dm <= 0.0:
		return 0.0
	var dv := volume_m3 * (dm / mass_kg) if mass_kg > 0.0 else 0.0
	# Convert the fractions to absolute polymer masses, subtract, renormalise.
	var new_poly := poly - dm
	if new_poly > 0.0:
		var abs_masses : Dictionary = {}
		for k in composition:
			abs_masses[k] = float(composition[k]) * poly
		abs_masses[key] = maxf(0.0, float(abs_masses.get(key, 0.0)) - dm)
		for k in abs_masses:
			composition[k] = float(abs_masses[k]) / new_poly
	mass_kg    = maxf(0.0, mass_kg - dm)
	volume_m3  = maxf(0.0, volume_m3 - dv)
	return dm

# =============================================================================
func to_dict() -> Dictionary:
	return {"mass_kg": mass_kg, "volume_m3": volume_m3, "composition": composition,
			"origin": origin, "water_kg": water_kg, "contaminant_kg": contaminant_kg}

func _to_string() -> String:
	return "MaterialBatch(%.1f kg [poly %.1f / H2O %.1f / dirt %.1f], %.3f m3, %s)" \
		% [mass_kg, polymer_kg(), water_kg, contaminant_kg, volume_m3, origin]
