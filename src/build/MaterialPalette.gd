extends Object
class_name MaterialPalette

## Cached singleton StandardMaterial3D palette, derived from reference photos of
## the real CeDo halls. Every getter returns the SAME instance every call, so a
## hundred meshes sharing one material cost one material in VRAM.
##
## Naming convention: `mat_<category>_<descriptor>()`. Categories so far:
##   concrete  — floor / slab variants (worn, wet, oily, dirt buildup)
##   paint     — safety paint stripes, equipment paint
##   timber    — heavy structural wood + crate wood
##   steel     — raw / galvanised / aged / riveted, including pipes
##   light     — emissive: fluorescent / LED / sodium
##
## Add new entries here in the category they belong to, NOT scattered through
## per-builder _mat() calls — one place to tune the whole look later.

# ── internal: lazy-build + cache ──────────────────────────────────────────────
static var _cache : Dictionary = {}

## NB: name `_lazy` not `_get` — `_get` collides with Godot's Object._get() virtual.
static func _lazy(key: String, color: Color, metallic: float, roughness: float,
				 emission: Color = Color(0, 0, 0, 0), emission_energy: float = 0.0,
				 cull_disabled: bool = false) -> StandardMaterial3D:
	if _cache.has(key):
		return _cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.metallic = metallic
	m.roughness = roughness
	if emission_energy > 0.0:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = emission_energy
	if cull_disabled:
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_cache[key] = m
	return m


# ── FLOOR / CONCRETE ─────────────────────────────────────────────────────────
## Light grey worn polished concrete — the base floor everywhere indoors.
static func mat_concrete_worn() -> StandardMaterial3D:
	return _lazy("concrete_worn", Color(0.55, 0.55, 0.55), 0.0, 0.82)

## Wet streak / shallow puddle — darker + far less rough so the lights reflect.
## Use for puddle patches over concrete, not as a fill colour.
static func mat_concrete_wet() -> StandardMaterial3D:
	return _lazy("concrete_wet", Color(0.30, 0.32, 0.36), 0.0, 0.20)

## Oil / grease spill — near-black, slightly glossy.
static func mat_oil_grease() -> StandardMaterial3D:
	return _lazy("oil_grease", Color(0.12, 0.11, 0.10), 0.0, 0.45)

## Dirt / fine-dust buildup at wall bases and column feet.
static func mat_dirt_buildup() -> StandardMaterial3D:
	return _lazy("dirt_buildup", Color(0.35, 0.32, 0.28), 0.0, 0.95)


# ── PAINT (safety stripes + equipment) ──────────────────────────────────────
## Worn yellow safety-stripe paint on the floor — faded, chipped, very matte.
static func mat_paint_safety_yellow_worn() -> StandardMaterial3D:
	return _lazy("paint_safety_yellow_worn", Color(0.68, 0.58, 0.18), 0.0, 0.85)

## Fresh / equipment yellow — crane hoist, guard frames. Brighter, less wear.
static func mat_paint_safety_yellow() -> StandardMaterial3D:
	return _lazy("paint_safety_yellow", Color(0.92, 0.78, 0.10), 0.0, 0.65)


# ── TIMBER (heavy structural + crate wood) ──────────────────────────────────
## Heavy dark structural timber — the wooden archways / columns / roof trusses
## visible in hal 0. Vertical grain, weather-checked, near-matte.
static func mat_timber_dark() -> StandardMaterial3D:
	return _lazy("timber_dark", Color(0.18, 0.13, 0.09), 0.0, 0.95)

## Dark wooden ceiling-deck planks (above the timber arches).
static func mat_wood_deck_dark() -> StandardMaterial3D:
	return _lazy("wood_deck_dark", Color(0.16, 0.12, 0.08), 0.0, 0.92)

## Natural pine packing crates — light tan, matte.
static func mat_wood_crate_pine() -> StandardMaterial3D:
	return _lazy("wood_crate_pine", Color(0.72, 0.58, 0.38), 0.0, 0.85)


# ── STEEL (raw / galvanised / aged / pipes) ─────────────────────────────────
## Galvanised steel — overhead crane rails, mesh panels, raceway. Slight gloss.
static func mat_steel_galvanised() -> StandardMaterial3D:
	return _lazy("steel_galvanised", Color(0.55, 0.58, 0.62), 0.55, 0.35)

## Bare medium-grey process pipe steel — large HVAC / extraction runs.
static func mat_steel_pipe_grey() -> StandardMaterial3D:
	return _lazy("steel_pipe_grey", Color(0.50, 0.52, 0.55), 0.55, 0.40)

## Old riveted steel base plate — rust-streaked, dirty, low gloss.
static func mat_steel_riveted_rust() -> StandardMaterial3D:
	return _lazy("steel_riveted_rust", Color(0.30, 0.26, 0.22), 0.30, 0.65)

## Generic dark aged steel — old machine frames, brackets, conduits.
static func mat_steel_dark_aged() -> StandardMaterial3D:
	return _lazy("steel_dark_aged", Color(0.22, 0.22, 0.24), 0.25, 0.60)


# ── STAINLESS variants (large process drums + tanks) ────────────────────────
## Dirty / weathered stainless steel — long-streak water marks + patchy
## oxidation. Use for big wash drums + tank exteriors that have been in service.
static func mat_stainless_weathered() -> StandardMaterial3D:
	return _lazy("stainless_weathered", Color(0.62, 0.62, 0.60), 0.55, 0.55)

## Dark recessed text effect on stainless (capacity placards, equipment ids).
## Same colour family as engraved/embossed lettering reads against bare metal.
static func mat_text_embossed_dark() -> StandardMaterial3D:
	return _lazy("text_embossed_dark", Color(0.20, 0.20, 0.20), 0.30, 0.85)


# ── PAINT variants (peeling / equipment-aged) ───────────────────────────────
## Heavy-peel yellow safety paint on steel — chunks missing, brown rust
## undercoat showing through. Distinct from `mat_paint_safety_yellow_worn`
## which is just faded; this one is failing.
static func mat_paint_yellow_peeling() -> StandardMaterial3D:
	return _lazy("paint_yellow_peeling", Color(0.66, 0.55, 0.12), 0.0, 0.92)

## Dirty oxidised blue equipment paint — old machine frames around water.
static func mat_paint_blue_oxidised() -> StandardMaterial3D:
	return _lazy("paint_blue_oxidised", Color(0.16, 0.22, 0.34), 0.0, 0.75)


# ── RUBBER / GRATING / WET FLOOR ────────────────────────────────────────────
## Solid industrial rubber tire — drum support rollers, forklift tires.
static func mat_rubber_tire_solid() -> StandardMaterial3D:
	return _lazy("rubber_tire_solid", Color(0.07, 0.07, 0.08), 0.0, 0.95)

## Galvanised steel walkway grating — dirty, slightly oxidised.
static func mat_grating_steel() -> StandardMaterial3D:
	return _lazy("grating_steel", Color(0.42, 0.43, 0.44), 0.55, 0.55)

## High-reflective wet concrete — almost-mirror puddle (more reflective than
## `mat_concrete_wet`). Use for the larger standing-water sheet in machine pits.
static func mat_concrete_wet_mirror() -> StandardMaterial3D:
	return _lazy("concrete_wet_mirror", Color(0.22, 0.24, 0.28), 0.10, 0.10)


# ── LIGHTS (emissive — used for fixtures, NOT for actual illumination) ──────
## Cool-white fluorescent strip light fixture (the bright bar shape itself).
## Pair with an actual OmniLight3D for cast lighting; this is only the bulb.
static func mat_light_fluorescent_cool() -> StandardMaterial3D:
	return _lazy("light_fluorescent_cool", Color(0.92, 0.95, 1.00),
		0.0, 0.10, Color(0.92, 0.95, 1.00), 3.5)

## Warm white LED floodlight head (a slight amber bias).
static func mat_light_led_warm() -> StandardMaterial3D:
	return _lazy("light_led_warm", Color(1.00, 0.95, 0.85),
		0.0, 0.10, Color(1.00, 0.95, 0.85), 4.0)

## Sodium-orange exterior security light (for the outside walls / yard).
static func mat_light_sodium() -> StandardMaterial3D:
	return _lazy("light_sodium", Color(1.00, 0.65, 0.30),
		0.0, 0.10, Color(1.00, 0.65, 0.30), 3.0)

## Tiny indicator-LED materials (HMI / status display dots on machine fascias).
static func mat_indicator_red() -> StandardMaterial3D:
	return _lazy("indicator_red", Color(0.95, 0.20, 0.18), 0.0, 0.20, Color(1.0, 0.20, 0.15), 4.0)
static func mat_indicator_green() -> StandardMaterial3D:
	return _lazy("indicator_green", Color(0.30, 0.92, 0.40), 0.0, 0.20, Color(0.30, 1.0, 0.40), 4.0)
static func mat_indicator_blue() -> StandardMaterial3D:
	return _lazy("indicator_blue", Color(0.30, 0.55, 0.95), 0.0, 0.20, Color(0.30, 0.55, 1.0), 4.0)


# ── TEST / DEBUG ────────────────────────────────────────────────────────────
## Returns the count of materials currently cached (for sanity tests).
static func cached_count() -> int:
	return _cache.size()
