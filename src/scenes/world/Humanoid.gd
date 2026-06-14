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
const PPE_HIVIS_ORANGE_BASE : String = "res://assets/textures/ppe/ppe_hivis_orange"
const PPE_HIVIS_YELLOW_BASE : String = "res://assets/textures/ppe/ppe_hivis_yellow"   # #186 — optional; falls back to a flat yellow if asset missing.
const PPE_DENIM_BASE        : String = "res://assets/textures/ppe/ppe_denim_pants"
const PPE_TILE_M            : float  = 0.45    # textile cell scale on the body

# #186 — Standard EN ISO 20471 hi-vis colours. The fluorescent yellow ("safety
# yellow") is what CeDo's coats actually are; orange is the alternative class.
const HIVIS_YELLOW : Color = Color(0.95, 0.92, 0.10)
const HIVIS_ORANGE : Color = Color(0.96, 0.42, 0.08)

static var _ppe_hivis_orange_mat : StandardMaterial3D = null
static var _ppe_hivis_yellow_mat : StandardMaterial3D = null
static var _ppe_denim_mat        : StandardMaterial3D = null

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

static func _hivis_material(color_tag: String = "yellow") -> StandardMaterial3D:
	# #186 — Two photo-extracted hi-vis PBR triplets are supported. The operator
	# spec is YELLOW (CeDo's real coats); the legacy orange set ships as a
	# fallback for code paths that still ask for it.
	if color_tag == "orange":
		if _ppe_hivis_orange_mat == null:
			_ppe_hivis_orange_mat = _ppe_material(PPE_HIVIS_ORANGE_BASE, HIVIS_ORANGE, 0.80)
		return _ppe_hivis_orange_mat
	if _ppe_hivis_yellow_mat == null:
		# Yellow texture is OPTIONAL on disk — if absent, _ppe_material falls
		# back to a flat HIVIS_YELLOW colour (visibly distinct from orange so the
		# operator can tell the wardrobe choice landed).
		_ppe_hivis_yellow_mat = _ppe_material(PPE_HIVIS_YELLOW_BASE, HIVIS_YELLOW, 0.80)
	return _ppe_hivis_yellow_mat

static func _denim_material() -> StandardMaterial3D:
	if _ppe_denim_mat == null:
		_ppe_denim_mat = _ppe_material(PPE_DENIM_BASE, Color(0.18, 0.22, 0.34), 0.85)
	return _ppe_denim_mat

# #186 — UNIFIED clothing-material resolver. Audit symptom: the previous build()
# had three competing material paths (hi-vis texture → shirt_color_override flat
# colour → ppe elif chain) where any non-default `shirt_color` killed the texture
# AND made the ppe branches dead code. This funnels EVERY shirt path through
# one decision so:
#   1) `shirt_type` picks the BASE material (t_shirt → flat tint, sweatshirt →
#      flat tint, hi_vis_coat → textured hi-vis).
#   2) `tint` is applied as an albedo TINT for the cloth path. Textured paths
#      keep their albedo at WHITE so the photo dominates (don't double-tint).
#   3) `ppe_class` is read by a separate _apply_ppe_vest() function so PPE is
#      always visible regardless of the shirt — see build() body.
static func _apply_clothing_material(clothing_class: String, tint: Color, hivis_tag: String = "yellow") -> StandardMaterial3D:
	match clothing_class:
		"hi_vis_coat":
			# Textured fluorescent jacket — tint is ignored on purpose so safety
			# colour is recognisable from a distance. (Operator: "hi-vis = yellow.")
			return _hivis_material(hivis_tag)
		"sweatshirt":
			# Textured fabric WHEN available, else a flat matte. Either way the
			# operator's tint comes through on albedo_color so the colour picker
			# isn't a no-op when a texture exists.
			var m_sw := StandardMaterial3D.new()
			var sw_path := "res://assets/textures/ppe/ppe_sweatshirt"
			var albedo_path := sw_path + "_albedo.png"
			if ResourceLoader.exists(albedo_path):
				m_sw.albedo_texture = load(albedo_path)
				m_sw.albedo_color   = tint            # photo × tint
				m_sw.uv1_triplanar  = true
				m_sw.uv1_scale      = Vector3.ONE / maxf(PPE_TILE_M, 0.01)
			else:
				m_sw.albedo_color = tint
			m_sw.metallic = 0.0
			m_sw.roughness = 0.75
			return m_sw
		"t_shirt", _:
			return _mat(tint, 0.55)

static func _apply_pants_material(tint: Variant, use_denim_texture: bool) -> StandardMaterial3D:
	if use_denim_texture and tint is Color == false:
		return _denim_material()
	if tint is Color:
		return _mat(tint, 0.85)
	return _denim_material()

## #166 — Runtime wardrobe swap. The Humanoid rig is rebuilt from scratch each
## call to build(), so the cheapest correct approach to "change clothes mid-game"
## is: build a fresh body with the new appearance dict, swap it in under the
## same parent, then free the old one. `holder` is the Node3D that currently
## holds the Body as a child (NPC root, or the player capsule). `shirt` and
## `variant` should be the same values the original build() got — preserve them
## via meta on the holder when you first spawn the NPC.
static func rebuild_appearance(holder: Node3D, shirt: Color, variant: int, new_appearance: Dictionary) -> Node3D:
	if holder == null or not is_instance_valid(holder):
		return null
	# MainWorld._spawn_npcs renames the rig "HumanoidBody" after attaching, but
	# the player + customizer keep the default "Body" name. Find either.
	var old : Node3D = holder.get_node_or_null("HumanoidBody") as Node3D
	if old == null:
		old = holder.get_node_or_null("Body") as Node3D
	var fresh : Node3D = Humanoid.build(shirt, variant, new_appearance)
	if fresh == null:
		return null
	# Match whatever the old name was so the NPC's per-frame body-scaling lookup
	# (#146 crouch/prone) still finds it after the swap.
	if old != null:
		fresh.name = old.name
	holder.add_child(fresh)
	if old:
		# Copy the world transform so the swap is visually seamless if `Body`
		# was offset/rotated by the NPC (most aren't — Body sits at origin).
		fresh.transform = old.transform
		old.queue_free()
	return fresh

## #133 / #186 — per-character appearance dict. Recognised keys:
##   "hair"       : "bald" / "buzz" / "short" (default) / "mid" / "long"
##                  / "ponytail" / "mullet"
##   "cap"        : true → a dark-blue work cap layered OVER the hair (brim
##                  covers the front, hair pokes through back/sides — no
##                  longer a replacement)
##   "beard"      : "none" / "thin" (rendered as sparse stubble dots, NOT
##                  planes) / "thick" / "full" / "mustache" / "goatee"
##   "hair_color" : optional Color, overrides the variant-driven default
##   "skin_color" : optional Color, overrides the variant-driven skin tone
##   "shirt_type" : "t_shirt" (default) / "sweatshirt" / "hi_vis_coat"
##   "shirt_color": optional Color — TINT for the shirt material (modulates the
##                  textured sweatshirt path; flat colour for t_shirt). Does NOT
##                  override hi_vis_coat colour (safety yellow is safety yellow).
##   "footwear"   : "work_boots" (default) / "shoes"
##   "ppe"        : "hi_vis" (default for crew → yellow vest + reflective bands)
##                  / "operator" (orange vest + hardhat) / "none" (personal
##                  clothes only). PPE is an ADDITIVE overlay — it shows over
##                  whatever shirt you picked, so the dropdown is never a no-op.
##   "wear_state" : "on_duty" (default — PPE shows) / "off_duty" (PPE hidden,
##                  hi_vis_coat downgrades to sweatshirt). Set automatically
##                  by MainWorld based on ShiftClock.shift_active.
##   "hivis_color": "yellow" (default — operator spec) / "orange" (legacy
##                  texture set) — picks which photo set the hi-vis vest/coat
##                  uses.
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
	# #126 — per-NPC proportions. Scale the whole body node so legs/torso/arms
	# all stretch consistently; head + face features inherit but stay attached.
	# Clamped so even an extreme value can't break collision badly.
	var height_mul : float = clampf(float(appearance.get("height_mul", 1.0)), 0.80, 1.20)
	var width_mul  : float = clampf(float(appearance.get("width_mul",  1.0)), 0.80, 1.25)
	root.scale = Vector3(width_mul, height_mul, width_mul)

	var shirt_type : String = String(appearance.get("shirt_type", "t_shirt"))
	var footwear : String = String(appearance.get("footwear", "work_boots"))

	# #186 — Unified material decision. wear_state ("on_duty"/"off_duty") flips
	# the OUTFIT slot the customizer wrote (operator can dress two looks). When
	# the dict was written before #186 (no wear_state), build() acts on the flat
	# fields directly. PPE class maps to an ADDITIVE vest mesh below — it never
	# clobbers the shirt material itself, so PPE is always visible.
	var wear_state : String = String(appearance.get("wear_state", "on_duty"))
	# Off-duty default override: if the dict is on-duty-shaped but the caller
	# asked for off-duty, downgrade hi_vis_coat to a plain sweatshirt so the
	# worker reads as "civilian" on arrival / after the bell.
	if wear_state == "off_duty" and shirt_type == "hi_vis_coat":
		shirt_type = "sweatshirt"

	# Resolve final shirt tint. shirt_color_override is now a TINT (it modulates
	# textured paths AND directly colours flat ones) — it no longer kills the
	# texture path. The default tint is hi-vis yellow so the legacy "no override"
	# case keeps showing the photo cleanly (albedo_color is left at WHITE inside
	# _hivis_material since hi_vis_coat ignores the tint by design).
	var shirt_tint : Color = HIVIS_YELLOW
	if shirt_color_override is Color:
		shirt_tint = shirt_color_override

	# Hi-vis tag — operator spec is YELLOW; "orange" still selectable via
	# appearance.hivis_color = "orange" for the legacy texture set.
	var hivis_tag : String = String(appearance.get("hivis_color", "yellow"))

	var m_skin  := _mat(skin, 0.85)
	var m_shirt : StandardMaterial3D = _apply_clothing_material(shirt_type, shirt_tint, hivis_tag)
	var m_pants : StandardMaterial3D = _apply_pants_material(pants_color_override, true)
	var m_boots := _mat(Color(0.10, 0.10, 0.11), 0.7)
	var m_hair  := _mat(hair, 0.9)
	var m_dark  := _mat(Color(0.05, 0.05, 0.06), 0.6)

	# Coat = same material as shirt (hi_vis_coat returns the textured hi-vis,
	# everything else falls through to the chosen clothing material). The
	# forearm now ALWAYS picks up the coat/shirt material for hi_vis_coat or
	# sweatshirt — only t_shirts expose bare skin on the forearm.
	var m_coat : StandardMaterial3D = m_shirt
	var m_forearm : StandardMaterial3D
	if shirt_type == "t_shirt":
		m_forearm = m_skin
	else:
		m_forearm = m_shirt
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

	# ── PPE ADDITIVE LAYER (#186) ──────────────────────────────────────────────
	# PPE is now an OVERLAY independent of the shirt — fixes the operator complaint
	# that "PPE dropdown does nothing." A "hi_vis" PPE adds a yellow vest with
	# reflective bands; an "operator" PPE adds an orange vest + a hardhat dome
	# over the head; "none" adds nothing (the worker is in personal clothes).
	# When wear_state is off_duty we suppress PPE so the look reads as "civilian".
	if wear_state != "off_duty" and shirt_type != "hi_vis_coat":
		match ppe_class:
			"hi_vis":
				var m_vest := _hivis_material(hivis_tag)
				_box(root, Vector3(0.43, 0.42, 0.26), Vector3(0.0, 0.26, 0.0), m_vest)
				var m_band_v := _mat(Color(0.80, 0.82, 0.84), 0.25)
				_box(root, Vector3(0.44, 0.03, 0.27), Vector3(0.0, 0.36, 0.0), m_band_v)
				_box(root, Vector3(0.44, 0.03, 0.27), Vector3(0.0, 0.12, 0.0), m_band_v)
			"operator":
				var m_vest_op := _hivis_material("orange")
				_box(root, Vector3(0.43, 0.42, 0.26), Vector3(0.0, 0.26, 0.0), m_vest_op)
				var m_band_o := _mat(Color(0.80, 0.82, 0.84), 0.25)
				_box(root, Vector3(0.44, 0.03, 0.27), Vector3(0.0, 0.36, 0.0), m_band_o)
				_box(root, Vector3(0.44, 0.03, 0.27), Vector3(0.0, 0.12, 0.0), m_band_o)
			_:
				pass

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
	# #126 — moustache + goatee are now independent appearance flags so an NPC
	# can have moustache-only (Romain) or goatee-only (Emrah) without the rest
	# of the chin/cheek beard geometry.
	var want_moustache_only : bool = bool(appearance.get("moustache", false))
	var want_goatee_only    : bool = bool(appearance.get("goatee", false))
	if beard_style == "none" and want_moustache_only and not want_goatee_only:
		beard_style = "mustache"
	elif beard_style == "none" and want_goatee_only and not want_moustache_only:
		beard_style = "goatee"
	elif beard_style == "none" and want_moustache_only and want_goatee_only:
		beard_style = "goatee"   # goatee already includes the mustache
	# "thin" is now STUBBLE — a sparse, deterministic dot pattern across the
	# chin/jaw/upper-lip face region (#186). Replaces the old plane-of-hair
	# cheek boxes which read as a flat beard. Other styles keep plane geom.
	var _has_chin   : bool = beard_style in ["thick", "full", "goatee"]
	var _has_cheeks : bool = beard_style in ["thick", "full"]
	var _has_stache : bool = beard_style in ["thick", "full", "mustache", "goatee"] or want_moustache_only
	var _has_neck   : bool = beard_style in ["thick", "full"]
	var _has_full   : bool = beard_style == "full"
	var _is_stubble : bool = beard_style == "thin"
	if beard_style != "none":
		var beard_mat : StandardMaterial3D = m_hair
		var bfz : float = fz + 0.015   # pushed outward to avoid Z-fight with face
		if _is_stubble:
			# Deterministic stubble: ~38 ~3mm boxes seeded by variant + skin so the
			# same NPC always looks the same across reloads, but different NPCs
			# don't share the exact pattern. Region: chin + lower cheeks +
			# moustache strip on the +Z face of the head.
			var rng := RandomNumberGenerator.new()
			rng.seed = (variant * 9973) ^ int(skin.r * 1000.0) ^ int(skin.g * 100.0) ^ int(skin.b * 10.0)
			var dot_size := Vector3(0.005, 0.005, 0.005)
			for _i in 38:
				# Region: x in [-0.10, 0.10], y in [head_y - 0.16, head_y - 0.04],
				# pushed onto the face plane (z = bfz).
				var dx : float = rng.randf_range(-0.10, 0.10)
				var dy : float = rng.randf_range(head_y - 0.16, head_y - 0.04)
				# Skip the mouth opening (a small ellipse) so the stubble doesn't
				# block lips.
				var mouth_dy := dy - (head_y - 0.08)
				if abs(dx) < 0.045 and abs(mouth_dy) < 0.012:
					continue
				_box(root, dot_size, Vector3(dx, dy, bfz + 0.001), beard_mat)
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

	# ── HAIR (#186) — supports bald, buzz, short, mid, long, ponytail, mullet.
	#     Drawn FIRST so the cap (if any) layers OVER it. Old behaviour replaced
	#     hair with the cap; operator complaint was "hair disappears when cap is
	#     on." Now the cap brim covers the front while the back/sides of the
	#     hair still poke through.
	if hair_style != "bald":
		match hair_style:
			"buzz":
				# Buzz-cut: thin crown only, no back piece. Reads as "fresh
				# clippers" from a distance.
				_box(root, Vector3(0.255, 0.04, 0.255), Vector3(0.0, head_y + 0.11, 0.0), m_hair)
			"short":
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)   # top
				_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, -0.11), m_hair)  # back
			"mid":
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.30, 0.06), Vector3(0.0, head_y - 0.01, -0.11), m_hair)
			"long":
				# Crown + a long back piece reaching the shoulders + small side
				# strands so it doesn't read as a bib stuck to the head.
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.45, 0.06), Vector3(0.0, head_y - 0.12, -0.11), m_hair)
				for sx in [-1.0, 1.0]:
					_box(root, Vector3(0.05, 0.32, 0.06),
						Vector3(sx * 0.115, head_y - 0.05, -0.04), m_hair)
			"ponytail":
				# Short crown + a slender vertical tail hanging off the back.
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, -0.11), m_hair)
				_box(root, Vector3(0.06, 0.35, 0.06), Vector3(0.0, head_y - 0.10, -0.14), m_hair)
			"mullet":
				# Business-in-the-front: short crown + long back-only piece.
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.32, 0.06), Vector3(0.0, head_y - 0.04, -0.11), m_hair)
			_:
				# Unknown style — fall back to "short" so a stale save doesn't
				# render a bald NPC silently.
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, -0.11), m_hair)

	# ── CAP (#186) — layered ON TOP of hair (not instead of). Cap brim covers
	#     the front, hair still pokes out the back/sides for everyone except
	#     a "bald" wearer. Independent of PPE class; the cap is a wardrobe item.
	if wears_cap:
		var cap_mat := _mat(Color(0.18, 0.22, 0.36), 0.78)
		_box(root, Vector3(0.28, 0.09, 0.28), Vector3(0.0, head_y + 0.135, 0.0), cap_mat)   # crown
		_box(root, Vector3(0.26, 0.02, 0.10), Vector3(0.0, head_y + 0.09,  fz + 0.04), cap_mat)  # brim
		# Optional fringe under the cap — auto-enabled whenever hair != bald so
		# the customizer (which doesn't expose hair_under_cap directly) just
		# does the right thing. Legacy NPC presets that set hair_under_cap=true
		# also still light up.
		if hair_style != "bald":
			_box(root, Vector3(0.24, 0.025, 0.02),
				Vector3(0.0, head_y + 0.075, fz + 0.05), m_hair)
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.025, 0.05, 0.04),
					Vector3(sx * 0.115, head_y + 0.04, fz - 0.01), m_hair)

	# Hardhat overlay if ppe_class == "operator" (drawn AFTER cap so it wins).
	if ppe_class == "operator" and wear_state != "off_duty":
		var m_hard := _mat(Color(0.94, 0.62, 0.10), 0.55)
		_box(root, Vector3(0.30, 0.08, 0.30), Vector3(0.0, head_y + 0.16, 0.0), m_hard)
		_box(root, Vector3(0.34, 0.02, 0.36), Vector3(0.0, head_y + 0.115, 0.02), m_hard)   # brim ring

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
