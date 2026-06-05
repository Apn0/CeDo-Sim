extends RefCounted
class_name BaleDefs
## Incoming feedstock bales, by origin. These are the raw LDPE film bales that
## arrive on the lot and get fed (by forklift / bale-clamp) onto the feeding belt.
##
## size = Vector3(Length, Height, Depth) in metres, matching the real L·D·H the
## user gave (H mapped to Godot +Y so the bale rests on its base).
## ldpe_min/max = purity band. stack = how high they're stacked in the yard.
## tint/dirt/blue drive the visual look (see PlaceableCatalog._m_bale).
##
## WEIGHTS: the real yellow labels carry the measured weight, but exact kg per
## origin weren't given, so weight is ESTIMATED as volume × BULK_DENSITY. Adjust
## BULK_DENSITY (or add a per-origin "weight_kg") once the real figures are known.

const BULK_DENSITY : float = 320.0   # kg/m³ for baled LDPE film (ASSUMPTION)

static var _origins : Array[Dictionary] = []

static func origins() -> Array[Dictionary]:
	if _origins.is_empty():
		_origins = [
			{
				"id": "rotterdam", "name": "Rotterdam",
				"size": Vector3(1.30, 1.05, 1.05),          # L·H·D = 1.3·1.05·1.05
				"ldpe_min": 0.78, "ldpe_max": 0.86, "stack": 3,
				"tint": Color(0.72, 0.71, 0.66), "dirt": 0.13, "moisture": 0.09, "blue": 0.05,
			},
			{
				"id": "alba_marl", "name": "Alba Marl",
				"size": Vector3(1.30, 1.30, 1.30),
				"ldpe_min": 0.72, "ldpe_max": 0.80, "stack": 2,
				# the DIRTIEST feed (operator): brownish-grey with surface mud/sand, and
				# stored outdoors so the wettest too — but still mostly LDPE under the
				# dirt. Dirt is the yield driver here, not polymer purity.
				"tint": Color(0.40, 0.29, 0.18), "dirt": 0.14, "moisture": 0.12, "blue": 0.03,
			},
			{
				"id": "zwolle", "name": "Zwolle",
				"size": Vector3(1.20, 1.20, 1.20),
				"ldpe_min": 0.80, "ldpe_max": 0.86, "stack": 2,
				"tint": Color(0.79, 0.79, 0.75), "dirt": 0.07, "moisture": 0.05, "blue": 0.05,  # looks 'fresh' + dry
			},
			{
				"id": "forstplus", "name": "Forst+ (Fostplus)",
				"size": Vector3(1.30, 1.05, 1.01),
				# the CLEANEST feed (operator): clear-bluish, low dirt → the best yield.
				"ldpe_min": 0.80, "ldpe_max": 0.92, "stack": 3,
				"tint": Color(0.44, 0.60, 0.88), "dirt": 0.05, "moisture": 0.10, "blue": 0.62,
			},
		]
	return _origins

static func get_origin(id: String) -> Dictionary:
	for o in origins():
		if o["id"] == id:
			return o
	return {}

## Estimated bale weight (kg) from its footprint and the baled bulk density.
static func estimated_weight(size: Vector3) -> float:
	return size.x * size.y * size.z * BULK_DENSITY

## The polymer mix (fractions of the PLASTIC) for an origin. LDPE is the target;
## ~7.5% HDPE per the line-3A/3B TITECH data; the balance is PE/PET-G/PS/PP strays.
static func _composition(o: Dictionary) -> Dictionary:
	var ldpe := (float(o["ldpe_min"]) + float(o["ldpe_max"])) * 0.5
	var hdpe := 0.075
	var other := maxf(0.0, 1.0 - ldpe - hdpe)
	return {"LDPE": ldpe, "HDPE": hdpe, "other": other}

## The MaterialBatch a fresh bale of this origin contains — wet and dirty, exactly
## as it arrives on the lot. mass_kg is the total weighed mass; of that, `moisture`
## is water and `dirt` is contaminant, and the rest is clean polymer in the mix.
static func make_batch(id: String) -> MaterialBatch:
	var o := get_origin(id)
	if o.is_empty():
		return MaterialBatch.new()
	var size: Vector3 = o["size"]
	var vol := size.x * size.y * size.z
	var mass := vol * BULK_DENSITY
	var water := mass * float(o.get("moisture", 0.08))
	var dirt  := mass * float(o.get("dirt", 0.12))
	return MaterialBatch.new(mass, vol, _composition(o), String(o["name"]), water, dirt)

## A `kg`-sized sample of this origin's material at the bale's real moisture, dirt
## and polymer mix. LineFlow injects this at the line head so the head receives
## WET, DIRTY film — precisely what the wash + dry + sort train has to clean up.
static func feed_sample(id: String, kg: float) -> MaterialBatch:
	if kg <= 0.0:
		return MaterialBatch.new()
	var o := get_origin(id)
	if o.is_empty():
		var comp_def := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}
		return MaterialBatch.new(kg, kg / BULK_DENSITY, comp_def, "feed", kg * 0.08, kg * 0.12)
	return MaterialBatch.new(kg, kg / BULK_DENSITY, _composition(o), String(o["name"]),
							 kg * float(o.get("moisture", 0.08)), kg * float(o.get("dirt", 0.12)))
