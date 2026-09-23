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

const BULK_DENSITY : float = 175.0   # kg/m³ for baled LDPE film
# Calibrated from operator-reported weights: Alba Marl 1.60³ ≈ 700 kg → ~170 kg/m³;
# Zwolle 1.50³ ≈ 625 kg → ~185 kg/m³. Split at 175. The bale is mostly trapped
# air + loose film, NOT a solid LDPE block (which would be 920 kg/m³).

static var _origins : Array[Dictionary] = []

static func origins() -> Array[Dictionary]:
	if _origins.is_empty():
		_origins = [
			{
				"id": "rotterdam", "name": "Rotterdam",
				"size": Vector3(1.45, 1.25, 1.25),          # L·H·D = 1.45·1.25·1.25
				"ldpe_min": 0.78, "ldpe_max": 0.86, "stack": 3,
				"tint": Color(0.72, 0.71, 0.66), "dirt": 0.13, "moisture": 0.09, "blue": 0.05,
			},
			{
				"id": "alba_marl", "name": "Alba Marl",
				"size": Vector3(1.60, 1.60, 1.60),
				"ldpe_min": 0.72, "ldpe_max": 0.80, "stack": 2,
				# the DIRTIEST feed (operator): brownish-grey with surface mud/sand, and
				# stored outdoors so the wettest too — but still mostly LDPE under the
				# dirt. Dirt is the yield driver here, not polymer purity.
				"tint": Color(0.40, 0.29, 0.18), "dirt": 0.14, "moisture": 0.12, "blue": 0.03,
			},
			{
				"id": "zwolle", "name": "Zwolle",
				"size": Vector3(1.50, 1.50, 1.50),
				"ldpe_min": 0.80, "ldpe_max": 0.86, "stack": 2,
				"tint": Color(0.79, 0.79, 0.75), "dirt": 0.07, "moisture": 0.05, "blue": 0.05,  # looks 'fresh' + dry
			},
			{
				"id": "forstplus", "name": "Forst+ (Fostplus)",
				"size": Vector3(1.45, 1.15, 1.50),
				# the CLEANEST feed (operator): clear-bluish, low dirt → the best yield.
				"ldpe_min": 0.80, "ldpe_max": 0.92, "stack": 3,
				"tint": Color(0.44, 0.60, 0.88), "dirt": 0.05, "moisture": 0.10, "blue": 0.62,
			},
			# ── LINE 1 (operator 2026-09-23, rulings §11 and §18) ─────────────────
			# "LINE 1 (NORMALLY) ONLY PROCESSES AGRICULTURAL (BLACK) FILM" — the
			# stretch film farmers use — never the Rotterdam / Alba / Zwolle bales.
			# Big bales: ~1.70 m high, ~2 m wide, ~1.5 m thick, ~1000 kg; and "a 30
			# percent smaller version" (taken as 30 % smaller in each dimension —
			# a stated reading). They can hold scrap metal (car wheels, plough
			# parts, nails, wire, "very sometimes even an anvil"): `metal_chance`
			# is a placeholder for the metal-detect conveyor build (queued), not
			# used yet. Field soil makes them the dirtiest, wettest feed.
			{
				"id": "line_1_folie", "name": "LINE_1_FOLIE",
				"size": Vector3(2.00, 1.70, 1.50), "weight_kg": 1000.0,
				"ldpe_min": 0.84, "ldpe_max": 0.94, "stack": 2,
				"tint": Color(0.10, 0.10, 0.11), "dirt": 0.18, "moisture": 0.15, "blue": 0.0,
				"line": "1", "metal_chance": 0.10,
			},
			{
				"id": "line_1_folie_small", "name": "LINE_1_FOLIE (klein)",
				"size": Vector3(1.40, 1.19, 1.05), "weight_kg": 343.0,
				"ldpe_min": 0.84, "ldpe_max": 0.94, "stack": 3,
				"tint": Color(0.10, 0.10, 0.11), "dirt": 0.18, "moisture": 0.15, "blue": 0.0,
				"line": "1", "metal_chance": 0.10,
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

## An origin's NOMINAL weight: its `weight_kg` when the operator gave one
## (LINE_1_FOLIE), else the footprint × bulk-density estimate.
static func nominal_weight(o: Dictionary) -> float:
	if o.has("weight_kg"):
		return float(o["weight_kg"])
	return estimated_weight(o.get("size", Vector3(1.45, 1.25, 1.25)))

# ── Per-bale weight variance (operator 2026-09-23, rulings §18) ──────────────
# "weight of large bales ~1000kg (+/- 15%, 1SD; apply this variance/ratio to
# all bale types that are present in the sim thus far (since I noticed while
# testing that e.g. all Rotterdam bales are the exact same weight → which is
# not realistic)". Every bale drawn from a Gaussian around its origin's
# nominal weight, σ = WEIGHT_SD_FRAC, clipped at ±3 σ; deterministic per
# build order (a headless boot reproduces the same yard).
const WEIGHT_SD_FRAC : float = 0.15
static var _weight_seq : int = 0

# ── Metal in line-1 bales (rulings §11) ─────────────────────────────────────
# "car wheels, plough parts, very sometimes even an anvil, large nails, balls
# of wire, farm scrap". Rolled once per bale in assign_weight() from the
# origin's `metal_chance` (only LINE_1_FOLIE has one). The mix and the kg per
# kind are STATED PLACEHOLDERS; the anvil is rare on purpose ("very sometimes").
const METAL_KINDS : Array = [
	{"id": "wheel",       "kg": 12.0, "cum": 0.30},
	{"id": "plough_part", "kg": 25.0, "cum": 0.55},
	{"id": "wire_ball",   "kg": 4.0,  "cum": 0.80},
	{"id": "nails",       "kg": 2.0,  "cum": 0.96},
	{"id": "anvil",       "kg": 50.0, "cum": 1.00},
]

static func roll_metal(body: Node, origin_id: String, seq: int) -> bool:
	var o : Dictionary = get_origin(origin_id) if origin_id != "" else {}
	var chance : float = float(o.get("metal_chance", 0.0)) if not o.is_empty() else 0.0
	if body == null or chance <= 0.0:
		return false
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(origin_id) * 17 + seq * 7919 + 3
	if rng.randf() >= chance:
		return false
	var u : float = rng.randf()
	var kind : Dictionary = METAL_KINDS.back()
	for k in METAL_KINDS:
		if u < float(k["cum"]):
			kind = k
			break
	body.set_meta("metal_pieces", 1)
	body.set_meta("metal_kind", String(kind["id"]))
	body.set_meta("metal_kg", float(kind["kg"]))
	return true

static func weight_factor(seq: int, origin_id: String = "") -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(origin_id) * 31 + seq * 104729
	return clampf(rng.randfn(1.0, WEIGHT_SD_FRAC), 1.0 - 3.0 * WEIGHT_SD_FRAC, 1.0 + 3.0 * WEIGHT_SD_FRAC)

## Give a freshly built bale body its own weight and remember it on the node
## (`weight_kg` — what ShredderFeedBelt and the feeder already read, and what
## LineFlow's remaining_kg starts from; `weight_nominal_kg` for readers that
## want the origin's figure). Idempotent: a body that already carries
## `weight_kg` (detail_bale upgrading a light bale) keeps it.
static func assign_weight(body: Node, size: Vector3, origin_id: String = "") -> float:
	if body != null and body.has_meta("weight_kg"):
		return float(body.get_meta("weight_kg"))
	var o : Dictionary = get_origin(origin_id) if origin_id != "" else {}
	var nominal : float = nominal_weight(o) if not o.is_empty() else estimated_weight(size)
	_weight_seq += 1
	var w : float = nominal * weight_factor(_weight_seq, origin_id)
	if body != null:
		body.set_meta("weight_kg", w)
		body.set_meta("weight_nominal_kg", nominal)
		roll_metal(body, origin_id, _weight_seq)     # rulings §11: line-1 bales can hide scrap
	return w

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
