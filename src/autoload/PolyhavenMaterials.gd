## PolyhavenMaterials — Polyhaven PBR upgrades for CeDo Simulator.
##
## Two upgrade tracks:
##
## 1. STANDALONE materials (PBR_ASSETS) — new shared StandardMaterial3D instances
##    for surfaces that MaterialPalette never covered (exterior walls, yard, etc.).
##    Call the accessor (exterior_wall_block() etc.) and assign to mesh.
##
## 2. PALETTE UPGRADES (_register_palette_upgrades) — patches MaterialPalette's own
##    cached material instances with real normal + roughness maps from Polyhaven.
##    MaterialPalette.mat_*() returns the SAME object every call, so patching here
##    propagates to every mesh already using that material with no extra scene work.
##
## Decision rules followed:
##   - Photo-extracted textures (concrete_worn, timber_dark, stainless_weathered,
##     grating_steel, paint_cream_steel, ppe textures) → LEFT ALONE. Reference photos
##     of the actual CeDo facility beat any generic Polyhaven asset.
##   - Flat-colour materials with no photo → Polyhaven normal + roughness added.
##   - apply_albedo=false on all steel/paint → keeps the photo-calibrated colour tint
##     but gains real surface microdetail from the normal/roughness maps.
##   - apply_albedo=true only for wood where the flat colour is a placeholder tint,
##     and the Polyhaven grain reads better than a solid brown block.
extends Node

# ── 1. STANDALONE MATERIALS ───────────────────────────────────────────────────
# Surfaces not covered at all by MaterialPalette (exterior / generic variants).

# asset_id → kind label
const PBR_ASSETS: Dictionary = {
	"exterior_wall_block":     "rough_block_wall",    # cached ✓
	"exterior_wall_concrete":  "rock_face",           # cached ✓
	"exterior_ground_grass":   "aerial_grass_rock",   # cached ✓
	"interior_wall_light_var": "beige_wall_001",      # cached ✓
	"steel_plate_variant":     "metal_plate",         # new download
	"concrete_floor_variant":  "concrete_floor_02",   # new download
	# Operator-picked surface set (2026-07-04, from the real plant's look):
	"factory_floor_dirty":     "dirty_concrete",      # interior hall floor
	"ground_gravel":           "gravel_floor_03",     # roads + staff parking
	"ground_brick_pavement":   "brick_pavement_03",   # bale-lot yard paving
	# Also operator-shortlisted, not yet assigned to a surface (wire by adding
	# a kind + a consumer): rusty_metal_grid, rusty_metal_sheet, rusty_metal_03,
	# green_metal_rust.
}

# [albedo_color, roughness, tile_metres]
const FALLBACK: Dictionary = {
	"exterior_wall_block":     [Color(0.52, 0.50, 0.47), 0.94, 2.5],
	"exterior_wall_concrete":  [Color(0.44, 0.44, 0.43), 0.92, 2.0],
	"exterior_ground_grass":   [Color(0.25, 0.32, 0.14), 0.98, 4.0],
	"interior_wall_light_var": [Color(0.80, 0.76, 0.68), 0.88, 2.0],
	"steel_plate_variant":     [Color(0.50, 0.51, 0.53), 0.60, 1.5],
	"concrete_floor_variant":  [Color(0.40, 0.38, 0.35), 0.88, 2.5],
	"factory_floor_dirty":     [Color(0.34, 0.32, 0.30), 0.92, 2.5],
	"ground_gravel":           [Color(0.45, 0.43, 0.40), 0.97, 1.8],
	"ground_brick_pavement":   [Color(0.47, 0.44, 0.41), 0.90, 1.6],
}

var _cache: Dictionary    = {}   # kind → StandardMaterial3D (standalone)
var _by_asset: Dictionary = {}   # asset_id → kind  (standalone track only)

# ── 2. PALETTE UPGRADE TRACK ──────────────────────────────────────────────────
# asset_id → Array[{mat, apply_albedo, normal_scale}]
var _palette_by_asset: Dictionary = {}

var _tc: Node = null

func _ready() -> void:
	_tc = get_node_or_null("/root/TextureCache")
	if _tc == null:
		push_warning("PolyhavenMaterials: TextureCache not found — HD upgrades disabled")
		return
	_tc.connect("pbr_set_ready", Callable(self, "_on_pbr_ready"))

	# Kick off standalone materials.
	for kind in PBR_ASSETS:
		var asset_id: String = PBR_ASSETS[kind]
		_by_asset[asset_id] = kind
		_build(kind)
		_tc.request_pbr_set(asset_id, "2k")

	# Patch existing MaterialPalette materials for all flat-colour entries.
	_register_palette_upgrades()


# ── PALETTE UPGRADE REGISTRATION ──────────────────────────────────────────────

func _register_palette_upgrades() -> void:
	# Wood — apply_albedo=true: flat colour is placeholder; real grain wins.
	_pu(MaterialPalette.mat_wood_deck_dark(),  "wood_floor_dark_01", 1.2, 0.8, true)
	_pu(MaterialPalette.mat_timber_post(),     "wood_floor_dark_01", 1.0, 0.7, false)
	_pu(MaterialPalette.mat_wood_crate_pine(), "wood_floor_dark_01", 0.6, 0.6, false)

	# Steel — apply_albedo=false: exact photo-calibrated tints must stay.
	# normal+roughness from metal_plate adds surface microdetail to all variants.
	_pu(MaterialPalette.mat_steel_galvanised(),    "metal_plate", 1.5, 0.5, false)
	_pu(MaterialPalette.mat_steel_pipe_grey(),     "metal_plate", 1.5, 0.3, false)
	_pu(MaterialPalette.mat_steel_dark_aged(),     "metal_plate", 1.5, 0.6, false)
	_pu(MaterialPalette.mat_steel_riveted_rust(),  "rust_coarse", 1.0, 0.9, false)

	# Paint — apply_albedo=false: CeDo equipment colours are exact matches to
	# reference photos; only the micro-chip and paint-flake normal detail is added.
	_pu(MaterialPalette.mat_paint_safety_yellow_worn(), "painted_metal", 1.2, 0.5, false)
	_pu(MaterialPalette.mat_paint_safety_yellow(),      "painted_metal", 1.2, 0.4, false)
	_pu(MaterialPalette.mat_paint_yellow_peeling(),     "painted_metal", 1.0, 0.8, false)
	# Blue machine housings — operator pick (2026-07): blue_metal_plate's seam +
	# rivet normal/roughness detail over the photo-calibrated CeDo blues
	# (apply_albedo stays false, so the exact blue tints are untouched).
	_pu(MaterialPalette.mat_paint_blue_oxidised(),      "blue_metal_plate", 1.0, 0.7, false)
	_pu(MaterialPalette.mat_paint_blue_industrial(),    "blue_metal_plate", 1.0, 0.5, false)


## Register one MaterialPalette material for a Polyhaven upgrade.
## tile_m sets triplanar UV scale (only written if triplanar not already active).
func _pu(m: StandardMaterial3D, asset_id: String, tile_m: float,
		normal_scale: float, apply_albedo: bool) -> void:
	if not m.uv1_triplanar:
		m.uv1_triplanar       = true
		m.uv1_world_triplanar = true
		var inv := 1.0 / tile_m
		m.uv1_scale = Vector3(inv, inv, inv)
	if not _palette_by_asset.has(asset_id):
		_palette_by_asset[asset_id] = []
	_palette_by_asset[asset_id].append({
		"mat": m, "apply_albedo": apply_albedo, "normal_scale": normal_scale
	})
	_tc.request_pbr_set(asset_id, "2k")


# ── SHARED SIGNAL HANDLER ─────────────────────────────────────────────────────

func _on_pbr_ready(asset_id: String, maps: Dictionary) -> void:
	# Track 1: standalone materials.
	if _by_asset.has(asset_id):
		var kind: String = _by_asset[asset_id]
		if _cache.has(kind):
			_apply_maps(_cache[kind], maps, 1.2, true)

	# Track 2: MaterialPalette material patches.
	if _palette_by_asset.has(asset_id):
		for entry: Dictionary in _palette_by_asset[asset_id]:
			_apply_maps(
				entry["mat"],
				maps,
				float(entry["normal_scale"]),
				bool(entry["apply_albedo"])
			)


func _apply_maps(m: StandardMaterial3D, maps: Dictionary,
		normal_scale: float, apply_albedo: bool) -> void:
	if apply_albedo and maps.has("albedo"):
		m.albedo_texture = maps["albedo"]
		m.albedo_color   = Color.WHITE
	if maps.has("normal"):
		m.normal_enabled = true
		m.normal_texture = maps["normal"]
		m.normal_scale   = normal_scale
	if maps.has("roughness"):
		m.roughness_texture = maps["roughness"]


# ── STANDALONE MATERIAL BUILDERS + ACCESSORS ─────────────────────────────────

func _build(kind: String) -> StandardMaterial3D:
	if _cache.has(kind):
		return _cache[kind]
	var fb: Array = FALLBACK[kind]
	var m := StandardMaterial3D.new()
	m.albedo_color        = fb[0]
	m.roughness           = fb[1]
	m.uv1_triplanar       = true
	m.uv1_world_triplanar = true
	var inv: float = 1.0 / float(fb[2])
	m.uv1_scale = Vector3(inv, inv, inv)
	_cache[kind] = m
	return m

func get_material(kind: String) -> StandardMaterial3D:
	if not _cache.has(kind):
		_build(kind)
	return _cache[kind]

func exterior_wall_block()     -> StandardMaterial3D: return get_material("exterior_wall_block")
func exterior_wall_concrete()  -> StandardMaterial3D: return get_material("exterior_wall_concrete")
func exterior_ground_grass()   -> StandardMaterial3D: return get_material("exterior_ground_grass")
func interior_wall_light_var() -> StandardMaterial3D: return get_material("interior_wall_light_var")
func steel_plate_variant()     -> StandardMaterial3D: return get_material("steel_plate_variant")
func concrete_floor_variant()  -> StandardMaterial3D: return get_material("concrete_floor_variant")
func factory_floor_dirty()     -> StandardMaterial3D: return get_material("factory_floor_dirty")
func ground_gravel()           -> StandardMaterial3D: return get_material("ground_gravel")
func ground_brick_pavement()   -> StandardMaterial3D: return get_material("ground_brick_pavement")
