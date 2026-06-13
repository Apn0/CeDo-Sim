extends RefCounted
class_name Humanoid

## Low-poly blocky humanoid built from primitive boxes/spheres — replaces the
## capsule "pill" NPCs. Returns a Node3D rig whose vertical CENTRE is at the
## parent origin (feet at y = -0.9, head top at y = +0.9), so it drops straight
## onto a CharacterBody3D whose CapsuleShape3D is centred on the node origin.
##
## Parts (matching the operator's checklist): feet, lower legs, upper legs, core
## (pelvis + chest), arms (upper + lower), hands, neck, head, and a face with
## eyebrows, eyes, nose, mouth, ears + hair.
##
## `shirt`/`pants`/`skin`/`hair` let the caller vary appearance per worker. Pass
## the NPC's map colour as `shirt` so each worker still reads as a distinct
## colour from a distance (and on the MapOverlay).

const _SKIN_TONES : Array[Color] = [
	Color(0.94, 0.78, 0.66), Color(0.86, 0.66, 0.52),
	Color(0.72, 0.52, 0.38), Color(0.52, 0.36, 0.26),
]
const _HAIR_TONES : Array[Color] = [
	Color(0.09, 0.07, 0.06), Color(0.28, 0.18, 0.09),
	Color(0.55, 0.42, 0.20), Color(0.62, 0.62, 0.64),
]

# ── PPE textures (#132) ──────────────────────────────────────────────────────
# When the shift starts, every crew member shows up in the company hi-vis vest
# + denim work trousers (the operator's spec). Photo-extracted PBR triplets
# already exist under `assets/textures/ppe/` from the extraction pipeline
# (#110). We load them lazily and cache the resulting materials so 9 NPCs ×
# 2 PPE materials = one albedo/normal/rough sample set in VRAM, not 18.
#
# Triplanar mapping (object space) lets us skip UV unwrapping on the box-mesh
# NPCs — the PPE pattern just wraps onto the torso / legs at the right scale.
# Falls back to the operator's calibrated flat colours when the textures are
# absent (public clone without the gitignored assets).
const PPE_HIVIS_BASE   : String = "res://assets/textures/ppe/ppe_hivis_orange"
const PPE_DENIM_BASE   : String = "res://assets/textures/ppe/ppe_denim_pants"
const PPE_TILE_M       : float  = 0.45    # textile cell scale on the body

static var _ppe_hivis_mat : StandardMaterial3D = null
static var _ppe_denim_mat : StandardMaterial3D = null

static func _ppe_material(base_path: String, fallback: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.metallic = 0.0
	m.roughness = rough
	# Try to mount the photo-extracted PBR set. Each asset is optional; we wire
	# whatever's present and let the StandardMaterial3D defaults handle the rest.
	var albedo_path := base_path + "_albedo.png"
	if ResourceLoader.exists(albedo_path):
		m.albedo_texture = load(albedo_path)
		m.albedo_color   = Color.WHITE       # don't double-tint the photo
	else:
		m.albedo_color = fallback             # public-clone fallback
	var normal_path := base_path + "_normal.png"
	if ResourceLoader.exists(normal_path):
		m.normal_enabled = true
		m.normal_texture = load(normal_path)
		m.normal_scale   = 0.6
	var rough_path := base_path + "_rough.png"
	if ResourceLoader.exists(rough_path):
		m.roughness_texture = load(rough_path)
	# Triplanar so the box-mesh body parts pick up the pattern without UV unwrap.
	if m.albedo_texture != null:
		m.uv1_triplanar = true
		m.uv1_scale = Vector3.ONE / maxf(PPE_TILE_M, 0.01)
	return m

static func _hivis_material() -> StandardMaterial3D:
	if _ppe_hivis_mat == null:
		_ppe_hivis_mat = _ppe_material(PPE_HIVIS_BASE, Color(0.96, 0.42, 0.08), 0.80)
	return _ppe_hivis_mat

static func _denim_material() -> StandardMaterial3D:
	if _ppe_denim_mat == null:
		_ppe_denim_mat = _ppe_material(PPE_DENIM_BASE, Color(0.18, 0.22, 0.34), 0.85)
	return _ppe_denim_mat

## #133 — per-NPC appearance dict. Recognised keys:
##   "hair"       : "short" (default), "mid", "bald"
##   "cap"        : true → a dark-blue work cap replaces the hair on top
##   "beard"      : "none" / "thin" / "thick" / "full" / "mustache" / "goatee"
##   "hair_color" : optional Color, overrides the variant-driven default
##   "skin_color" : optional Color, overrides the variant-driven skin tone
static func build(shirt: Color, variant: int = 0, appearance: Dictionary = {}) -> Node3D:
	var skin_raw : Variant = appearance.get("skin_color", null)
	if skin_raw is Dictionary and skin_raw.has("r"):
		skin_raw = Color(float(skin_raw["r"]), float(skin_raw["g"]), float(skin_raw["b"]))
	var skin  : Color = skin_raw if skin_raw is Color else _SKIN_TONES[variant % _SKIN_TONES.size()]
	# Intentional: every two skin tones map to the next hair tone.
	@warning_ignore("integer_division")
	var hair_raw : Variant = appearance.get("hair_color", null)
	if hair_raw is Dictionary and hair_raw.has("r"):
		hair_raw = Color(float(hair_raw["r"]), float(hair_raw["g"]), float(hair_raw["b"]))
	var hair  : Color = hair_raw if hair_raw is Color else _HAIR_TONES[(variant / 2) % _HAIR_TONES.size()]
	# `shirt` is kept as the MapOverlay colour (set as meta by MainWorld); the
	# in-world torso / arms now always use the company hi-vis material so the
	# crew reads as on-shift regardless of which NPC they are. Per-person
	# distinguishing features come from the head (#133).
	var boots : Color = Color(0.10, 0.10, 0.11)
	var _shirt_ignored := shirt   # silence "unused" — kept for API compat
	# Resolve appearance flags up front so the head builder reads them once.
	var hair_style : String = String(appearance.get("hair", "short"))
	var beard_style : String = String(appearance.get("beard", "none"))
	var wears_cap : bool = bool(appearance.get("cap", false))
	# #155 — wardrobe customizer extras (#153): pants_color tints the trousers,
	# ppe selects vest / glasses / etc. for the player. Colors come through as
	# either Color objects or {r,g,b} dicts after JSON roundtrip via GameState.
	var pants_color_override : Variant = appearance.get("pants_color", null)
	var shirt_color_override : Variant = appearance.get("shirt_color", null)
	var ppe_class : String = String(appearance.get("ppe", "hi_vis"))
	if pants_color_override is Dictionary and pants_color_override.has("r"):
		pants_color_override = Color(float(pants_color_override["r"]),
			float(pants_color_override["g"]), float(pants_color_override["b"]))
	if shirt_color_override is Dictionary and shirt_color_override.has("r"):
		shirt_color_override = Color(float(shirt_color_override["r"]),
			float(shirt_color_override["g"]), float(shirt_color_override["b"]))

	var root := Node3D.new()
	root.name = "Body"

	var shirt_type : String = String(appearance.get("shirt_type", "t_shirt"))
	var footwear : String = String(appearance.get("footwear", "work_boots"))

	var m_skin  := _mat(skin, 0.85)
	var m_shirt : StandardMaterial3D = _hivis_material()
	var m_pants : StandardMaterial3D = _denim_material()
	var m_boots := _mat(boots, 0.7)
	var m_hair  := _mat(hair, 0.9)
	var m_dark  := _mat(Color(0.05, 0.05, 0.06), 0.6)
	if shirt_color_override is Color:
		m_shirt = _mat(shirt_color_override, 0.55)
	elif ppe_class == "none":
		m_shirt = _mat(Color(0.20, 0.25, 0.30), 0.85)
	elif ppe_class == "operator":
		m_shirt = _mat(Color(0.80, 0.40, 0.10), 0.70)
	if pants_color_override is Color:
		m_pants = _mat(pants_color_override, 0.85)
	# Hi-vis coat: yellow fluorescent jacket with reflective silver bands.
	var m_coat : StandardMaterial3D = m_shirt
	if shirt_type == "hi_vis_coat":
		m_coat = _hivis_material()
	var m_forearm : StandardMaterial3D = m_skin if shirt_type == "t_shirt" else m_shirt
	if shirt_type == "hi_vis_coat":
		m_forearm = m_coat
	var m_shoe : StandardMaterial3D = m_boots
	if footwear == "shoes":
		m_shoe = _mat(Color(0.22, 0.20, 0.18), 0.80)

	# ── LEGS ──────────────────────────────────────────────────────────────────
	# Feet at y≈-0.9. Boots, shins, thighs stacked up to the pelvis at y≈-0.18.
	for sx in [-1.0, 1.0]:
		var x : float = float(sx) * 0.12
		_box(root, Vector3(0.16, 0.08, 0.30), Vector3(x, -0.86, 0.04), m_shoe)    # foot
		if footwear == "work_boots":
			_box(root, Vector3(0.15, 0.12, 0.16), Vector3(x, -0.78, 0.0), m_boots)  # ankle boot cuff
		_box(root, Vector3(0.13, 0.40, 0.13), Vector3(x, -0.62, 0.0),  m_pants)   # lower leg (shin)
		_box(root, Vector3(0.16, 0.40, 0.16), Vector3(x, -0.24, 0.0),  m_pants)   # upper leg (thigh)

	# ── CORE ──────────────────────────────────────────────────────────────────
	_box(root, Vector3(0.36, 0.16, 0.20), Vector3(0.0, -0.06, 0.0), m_pants)      # pelvis
	_box(root, Vector3(0.40, 0.46, 0.22), Vector3(0.0,  0.26, 0.0), m_shirt)      # chest/torso
	if shirt_type == "hi_vis_coat":
		_box(root, Vector3(0.42, 0.50, 0.24), Vector3(0.0, 0.24, 0.0), m_coat)   # coat shell
		# Reflective silver bands across the chest + waist.
		var m_band := _mat(Color(0.80, 0.82, 0.84), 0.25)
		_box(root, Vector3(0.43, 0.03, 0.25), Vector3(0.0, 0.38, 0.0), m_band)
		_box(root, Vector3(0.43, 0.03, 0.25), Vector3(0.0, 0.08, 0.0), m_band)

	# ── ARMS ──────────────────────────────────────────────────────────────────
	for sx in [-1.0, 1.0]:
		var x : float = float(sx) * 0.27
		_box(root, Vector3(0.11, 0.26, 0.12), Vector3(x, 0.34, 0.0), m_shirt)     # upper arm
		_box(root, Vector3(0.10, 0.26, 0.11), Vector3(x, 0.08, 0.0), m_forearm)   # forearm
		_box(root, Vector3(0.10, 0.10, 0.12), Vector3(x, -0.08, 0.02), m_skin)    # hand

	# ── NECK + HEAD ─────────────────────────────────────────────────────────────
	_box(root, Vector3(0.12, 0.08, 0.12), Vector3(0.0, 0.53, 0.0), m_skin)        # neck
	var head_y := 0.68
	_box(root, Vector3(0.24, 0.28, 0.24), Vector3(0.0, head_y, 0.0), m_skin)      # head

	# Ears (sides of head)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.03, 0.07, 0.06), Vector3(sx * 0.135, head_y, 0.0), m_skin)

	# Face features on the +Z face of the head.
	var fz := 0.122
	# Eyebrows
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.06, 0.015, 0.01), Vector3(sx * 0.055, head_y + 0.07, fz), m_hair)
	# Eyes
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.045, 0.03, 0.01), Vector3(sx * 0.055, head_y + 0.04, fz), m_dark)
	# Nose
	_box(root, Vector3(0.04, 0.07, 0.05), Vector3(0.0, head_y - 0.01, fz + 0.01), m_skin)
	# Mouth
	_box(root, Vector3(0.09, 0.02, 0.01), Vector3(0.0, head_y - 0.08, fz), m_dark)

	# ── BEARD (#133) — geometry pushed 0.015 outward from face to prevent Z-fighting.
	#     Styles: thin, thick, full (thick + more coverage), mustache, goatee (chin + mustache).
	var _has_chin   : bool = beard_style in ["thin", "thick", "full", "goatee"]
	var _has_cheeks : bool = beard_style in ["thin", "thick", "full"]
	var _has_stache : bool = beard_style in ["thick", "full", "mustache", "goatee"]
	var _has_neck   : bool = beard_style in ["thick", "full"]
	var _has_full   : bool = beard_style == "full"
	if beard_style != "none":
		var beard_mat : StandardMaterial3D = m_hair
		var bfz : float = fz + 0.015   # pushed outward to avoid Z-fight with face
		if _has_chin:
			_box(root, Vector3(0.13, 0.05, 0.02),
				Vector3(0.0, head_y - 0.13, bfz), beard_mat)
		if _has_cheeks:
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.025, 0.10, 0.18),
					Vector3(sx * 0.125, head_y - 0.06, 0.015), beard_mat)
			_box(root, Vector3(0.18, 0.025, 0.18),
				Vector3(0.0, head_y - 0.15, 0.015), beard_mat)
		if _has_stache:
			_box(root, Vector3(0.10, 0.022, 0.02),
				Vector3(0.0, head_y - 0.06, bfz), beard_mat)
		if _has_neck:
			_box(root, Vector3(0.10, 0.06, 0.12),
				Vector3(0.0, head_y - 0.20, 0.015), beard_mat)
		if _has_full:
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.03, 0.08, 0.14),
					Vector3(sx * 0.13, head_y - 0.02, 0.02), beard_mat)

	# ── HAIR / CAP (#133) — bald skips both; cap replaces the top with a dark-
	#     blue work cap (small brim included). The back-of-head piece still gets
	#     drawn for short/mid hair so the silhouette reads as a head from behind.
	if wears_cap:
		var cap_mat := _mat(Color(0.18, 0.22, 0.36), 0.78)
		_box(root, Vector3(0.28, 0.09, 0.28), Vector3(0.0, head_y + 0.135, 0.0), cap_mat)   # crown
		_box(root, Vector3(0.26, 0.02, 0.10), Vector3(0.0, head_y + 0.09,  fz + 0.04), cap_mat)  # brim
	elif hair_style != "bald":
		_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)   # top
		# "mid" = mid-long hair — back piece extends further down the neck.
		var back_h : float = 0.30 if hair_style == "mid" else 0.22
		var back_y_offset : float = head_y - (back_h - 0.22) * 0.5 + 0.03
		_box(root, Vector3(0.26, back_h, 0.06), Vector3(0.0, back_y_offset, -0.11), m_hair)

	return root

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)

static func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = 0.0
	return m
