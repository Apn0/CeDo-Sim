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

# ── Body mass from build sliders ─────────────────────────────────────────────
# Mass follows near-volume scaling: at constant tissue density, body mass is
# proportional to height × width × depth. The exponent is slightly below 1.0
# because real bodies don't scale density-perfectly with frame size (taller
# people are not proportionally thicker through every tissue). Calibrated so
# the customizer's slider extremes map exactly to the operator-specified range:
#   smallest build (0.80 / 0.80 / 0.80) →  50 kg
#   default build  (1.00 / 1.00 / 1.00) →  88 kg
#   largest build  (1.20 / 1.25 / 1.25) → 150 kg
const BODY_MASS_REF_KG   : float = 88.1
const BODY_MASS_EXPONENT : float = 0.8463

## Physical body mass (kg) for an appearance dict's build sliders. Used by the
## player controller (push impulses, belt/vehicle physics) and available to
## NPCs — one law for every human in the plant.
static func body_mass_kg(appearance: Dictionary) -> float:
	var h : float = clampf(float(appearance.get("height_mul", 1.0)), 0.80, 1.20)
	var w : float = clampf(float(appearance.get("width_mul",  1.0)), 0.80, 1.25)
	var d : float = clampf(float(appearance.get("depth_mul",  w)),   0.80, 1.25)
	return BODY_MASS_REF_KG * pow(h * w * d, BODY_MASS_EXPONENT)

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

static func _apply_pants_material(tint: Variant, use_denim_texture: bool, mirror_uv: bool = false) -> StandardMaterial3D:
	# No operator override → denim photo material if we're supposed to use it.
	# Override present → tinted flat colour (override wins so the colour picker
	# is never a no-op, matching the new shirt rule).
	# mirror_uv=true → left-leg variant: same photo, horizontally flipped + vertical
	# half-phase shift, so left + right legs no longer read as a copy-paste pair.
	# Operator complaint: trouser texture was identical on both legs.
	var has_override := tint is Color
	var base : StandardMaterial3D
	if not has_override and use_denim_texture:
		base = _denim_material()
	elif has_override:
		base = _mat(tint, 0.85)
	else:
		base = _denim_material()
	if not mirror_uv:
		return base
	# Per-side variant — duplicate so we don't poison the shared cache.
	var mirrored : StandardMaterial3D = base.duplicate() as StandardMaterial3D
	mirrored.uv1_scale  = Vector3(-base.uv1_scale.x, base.uv1_scale.y, base.uv1_scale.z)
	mirrored.uv1_offset = Vector3(base.uv1_offset.x + 1.0, base.uv1_offset.y + 0.5, base.uv1_offset.z)
	return mirrored

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
	# Rig names by owner: NPCs = "HumanoidBody" (MainWorld._spawn_npcs), the
	# PLAYER = "PlayerBody" (PlayerSpawner._spawn_player:208), customizer
	# preview = default "Body". Operator bug 2026-08-28 (double player body):
	# "PlayerBody" was MISSING from this lookup, so every shift-bell wardrobe
	# rebuild on the player found no old rig, freed nothing, and added a stray
	# second body ("Body", default render layers → visible head in first
	# person) next to the untouched original.
	var old : Node3D = holder.get_node_or_null("HumanoidBody") as Node3D
	if old == null:
		old = holder.get_node_or_null("PlayerBody") as Node3D
	if old == null:
		old = holder.get_node_or_null("Body") as Node3D
	var fresh : Node3D = Humanoid.build(shirt, variant, new_appearance)
	if fresh == null:
		return null
	if old != null:
		# Detach the old rig BEFORE adding the like-named fresh one. add_child
		# is immediate while queue_free is deferred, so adding first would make
		# Godot auto-rename the incoming duplicate ("@HumanoidBody@N") — and
		# every per-frame get_node_or_null lookup (#146 crouch/prone scaling,
		# anim-tree rebind) would silently stop finding the new rig.
		# Match the old name so those lookups still resolve after the swap.
		fresh.name = old.name
		# Copy the world transform so the swap is visually seamless if the rig
		# was offset/rotated by the NPC (most aren't — it sits at origin).
		fresh.transform = old.transform
		holder.remove_child(old)
		old.queue_free()
	holder.add_child(fresh)
	return fresh

## #133 / #186 — per-character appearance dict. Recognised keys:
##   "hair"       : "bald" / "buzz" / "short" (default) / "mid" / "long"
##                  / "ponytail" / "mullet"
##   "cap"        : true → a work cap layered OVER the hair (brim
##                  covers the front, hair pokes through back/sides — no
##                  longer a replacement). Default colour is dark navy; use
##                  "cap_color" to override (e.g. a brighter company blue).
##   "cap_color"  : optional Color — overrides the default dark-navy cap tint.
##                  A {r,g,b} dict also accepted (JSON-roundtrip from
##                  GameState). Use to express the brighter company blue
##                  variant seen on Kevin / Abdellilah in the worker_outfit
##                  photo (operator spec).
##   "beard"      : "none" / "thin" (rendered as sparse stubble dots, NOT
##                  planes) / "thick" / "full" / "mustache" / "goatee"
##   "hair_color" : optional Color, overrides the variant-driven default
##   "skin_color" : optional Color, overrides the variant-driven skin tone
##   "shirt_type" : "t_shirt" (default) / "sweatshirt" / "hi_vis_coat"
##   "shirt_color": optional Color — TINT for the shirt material (modulates the
##                  textured sweatshirt path; flat colour for t_shirt). Does NOT
##                  override hi_vis_coat colour (safety yellow is safety yellow).
##   "footwear"   : "work_boots" (default) / "shoes"
##   "ppe"        : "hi_vis" (default for crew → yellow vest + chest + shoulder
##                  reflective bands + white work gloves) / "operator" (orange
##                  vest + chest + shoulder bands + white work gloves +
##                  hardhat) / "none" (personal clothes only, bare hands). PPE
##                  is an ADDITIVE overlay — it shows over whatever shirt you
##                  picked, so the dropdown is never a no-op. The shoulder
##                  bands (#212 worker_outfit photo) sit just above the chest
##                  band and wrap across both shoulders; the gloves sit at
##                  the wrist on top of the existing hand mesh.
##   "wear_state" : "on_duty" (default — PPE shows) / "off_duty" (PPE hidden,
##                  hi_vis_coat downgrades to sweatshirt). Set automatically
##                  by MainWorld based on ShiftClock.shift_active.
##   "hivis_color": "yellow" (default — operator spec) / "orange" (legacy
##                  texture set) — picks which photo set the hi-vis vest/coat
##                  uses.
##
## IMPORTANT — ORIENTATION CONTRACT (corrected #205):
##   This rig is authored with the visible front (face/eyes/nose/chest/beard)
##   on LOCAL -Z — the Godot canonical forward. See line 419 inside the head
##   block: `var fz := -0.122` and the comment "VISUAL FRONT RULE — visible
##   front MUST sit on local -Z to match the canonical convention".
##   Callers that parent the result to a CharacterBody3D / NPC / vehicle seat
##   whose forward is -basis.z (CeDo convention) DO NOT need to rotate the
##   rig. NPCSpawner.gd attaches without rotation and the NPCs face the
##   right way; PlayerSpawner.gd was wrongly applying `rotation.y = PI` per
##   the OLD docstring (which had face on +Z) and the operator was seeing
##   the back of their own head in the wardrobe mirror. Fixed in #205.
##   GauntletWorld._build_player keeps a `rotation.y = PI` because its
##   capsule's own yaw cancels into the right gauntlet-station orientation;
##   that's a self-contained test scene quirk, not a contract.
static func build(shirt: Color, variant: int = 0, appearance: Dictionary = {}) -> Node3D:
	var skin_raw : Variant = appearance.get("skin_color", null)
	if skin_raw is Dictionary and skin_raw.has("r"):
		skin_raw = Color(float(skin_raw["r"]), float(skin_raw["g"]), float(skin_raw["b"]))
	var skin  : Color = skin_raw if skin_raw is Color else _SKIN_TONES[variant % _SKIN_TONES.size()]
	var hair_raw : Variant = appearance.get("hair_color", null)
	if hair_raw is Dictionary and hair_raw.has("r"):
		hair_raw = Color(float(hair_raw["r"]), float(hair_raw["g"]), float(hair_raw["b"]))
	# Intentional: every two skin tones map to the next hair tone. The annotation
	# has to sit on the line that DOES the division — it was one line too high
	# (attached to hair_raw), so the warning still fired.
	@warning_ignore("integer_division")
	var hair_idx : int = (variant / 2) % _HAIR_TONES.size()
	var hair  : Color = hair_raw if hair_raw is Color else _HAIR_TONES[hair_idx]
	# `shirt` is kept as the MapOverlay colour (set as meta by MainWorld); the
	# in-world torso / arms now always use the company hi-vis material so the
	# crew reads as on-shift regardless of which NPC they are. Per-person
	# distinguishing features come from the head (#133).
	var _boots : Color = Color(0.10, 0.10, 0.11)   # legacy palette anchor, no longer applied — kept for API compat
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
	# #212 — Optional explicit cap colour override. Mirrors the shirt/pants colour
	# pattern so a JSON-roundtripped {r,g,b} dict also works (GameState save→load).
	# When absent we fall back to the dark-navy default inside the cap branch.
	var cap_color_override : Variant = appearance.get("cap_color", null)
	if cap_color_override is Dictionary and cap_color_override.has("r"):
		cap_color_override = Color(float(cap_color_override["r"]),
			float(cap_color_override["g"]), float(cap_color_override["b"]))

	var root := Node3D.new()
	root.name = "Body"
	# #126 — per-NPC proportions. Scale the whole body node so legs/torso/arms
	# all stretch consistently; head + face features inherit but stay attached.
	# Clamped so even an extreme value can't break collision badly.
	# #C — `width_mul` (X = shoulder/hip width) and `depth_mul` (Z = chest
	# thickness / front-to-back) are now independent axes so the customizer can
	# express a broad-but-thin or narrow-but-stocky build. `depth_mul` falls
	# back to `width_mul` for old appearance dicts that only carry width — so
	# every existing NPC + save keeps its current proportions unchanged.
	var height_mul : float = clampf(float(appearance.get("height_mul", 1.0)), 0.80, 1.20)
	var width_mul  : float = clampf(float(appearance.get("width_mul",  1.0)), 0.80, 1.25)
	var depth_mul  : float = clampf(float(appearance.get("depth_mul",  width_mul)), 0.80, 1.25)
	root.scale = Vector3(width_mul, height_mul, depth_mul)

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
	# Audit item 26 — TEMPERATURE-DEPENDENT off-duty clothing. The wear_state
	# toggle (on_duty/off_duty) is what the operator chose in the customizer,
	# but the season should still drive whether an off-duty worker arrives in
	# a t-shirt or in a sweatshirt/coat. The temperature comes from
	# ShiftClock.get_outdoor_temp_c() (autoload sibling) so the wardrobe
	# pipeline reads it without depending on a static singleton. Cold (< 5 °C)
	# upgrades a t-shirt to a sweatshirt and a sweatshirt to a hi-vis coat;
	# warm (> 22 °C) downgrades the off-duty look to a t-shirt regardless of
	# what was stored. The customizer's intent (style/colour) is preserved on
	# the slot the operator wrote; only the SHIRT CLASS gets adjusted.
	if wear_state == "off_duty":
		var temp_c : float = _resolve_outdoor_temp_c()
		if temp_c < 5.0:
			if shirt_type == "t_shirt":
				shirt_type = "sweatshirt"
			elif shirt_type == "sweatshirt":
				shirt_type = "hi_vis_coat"
		elif temp_c > 22.0:
			shirt_type = "t_shirt"

	# Resolve final shirt tint. shirt_color_override is now a TINT (it modulates
	# textured paths AND directly colours flat ones) — it no longer kills the
	# texture path. The default tint is hi-vis yellow so the legacy "no override"
	# case keeps showing the photo cleanly (albedo_color is left at WHITE inside
	# _hivis_material since hi_vis_coat ignores the tint by design).
	var shirt_tint : Color = HIVIS_ORANGE
	if shirt_color_override is Color:
		shirt_tint = shirt_color_override

	# Hi-vis tag — operator spec 2026-07-16 is ORANGE ONLY. Default flipped from
	# "yellow" to "orange": the orange PBR set (ppe_hivis_orange_*.png) exists on
	# disk so the vest also picks up its photo texture (matching the denim pants),
	# whereas the yellow path had no texture and rendered flat.
	var hivis_tag : String = String(appearance.get("hivis_color", "orange"))

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
	# Wrapped in a HIP PIVOT Node3D at the hip joint (y=-0.06) so the gait
	# animator in NPC.gd can rotate the whole leg about X without offsetting
	# the foot in world space (rotating about the actual hip joint, not about
	# the rig origin). The pivot's local Y + each mesh's local Y still sum to
	# the same world Y the boxes had before — _set_body_render_layer_split
	# (which sums parent Node3D Y to classify head-vs-body) is unaffected.
	# Pivot names: HipPivot_L / HipPivot_R (NPC gait reads these).
	var _hip_y : float = -0.06
	for sx in [-1.0, 1.0]:
		var x : float = float(sx) * 0.12
		var hip := Node3D.new()
		hip.name = "HipPivot_R" if sx > 0.0 else "HipPivot_L"
		hip.position = Vector3(x, _hip_y, 0.0)
		root.add_child(hip)
		_box(hip, Vector3(0.16, 0.08, 0.30), Vector3(0.0, -0.86 - _hip_y, -0.04), m_shoe)    # foot — toes point FRONT (-Z), #205 flip fix
		if footwear == "work_boots":
			_box(hip, Vector3(0.15, 0.12, 0.16), Vector3(0.0, -0.78 - _hip_y, 0.0), m_boots)  # ankle boot cuff
		# Per-side denim variant — left leg (sx < 0) gets a mirrored + phase-shifted
		# UV so left + right legs don't read as a copy-paste pair. Fixes operator
		# complaint that the trouser texture was identical on both legs.
		var m_pants_side : StandardMaterial3D = _apply_pants_material(pants_color_override, true, sx < 0.0)
		_box(hip, Vector3(0.13, 0.40, 0.13), Vector3(0.0, -0.62 - _hip_y, 0.0),  m_pants_side)   # lower leg (shin)
		_box(hip, Vector3(0.16, 0.40, 0.16), Vector3(0.0, -0.24 - _hip_y, 0.0),  m_pants_side)   # upper leg (thigh)

	# ── CORE ──────────────────────────────────────────────────────────────────
	_box(root, Vector3(0.36, 0.16, 0.20), Vector3(0.0, -0.06, 0.0), m_pants)      # pelvis
	_box(root, Vector3(0.40, 0.46, 0.22), Vector3(0.0,  0.26, 0.0), m_shirt)      # chest/torso
	if shirt_type == "hi_vis_coat":
		_box(root, Vector3(0.42, 0.50, 0.24), Vector3(0.0, 0.24, 0.0), m_coat)   # coat shell
		# Reflective silver bands across the chest + waist.
		var m_band := _mat(Color(0.80, 0.82, 0.84), 0.25)
		_box(root, Vector3(0.43, 0.03, 0.25), Vector3(0.0, 0.38, 0.0), m_band)
		_box(root, Vector3(0.43, 0.03, 0.25), Vector3(0.0, 0.08, 0.0), m_band)
		# #212 — Shoulder reflective bands. Per the worker_outfit photo the
		# CeDo coat has TWO additional cross-chest reflective strips sitting
		# just above the existing chest band, hugging the shoulder line. We
		# model them as two short horizontal strips (one per side) on top of
		# the upper-chest at y ≈ 0.45, so they read as the shoulder pair
		# rather than a single wide band continuous with the chest one.
		_box(root, Vector3(0.20, 0.03, 0.25), Vector3(-0.12, 0.45, 0.0), m_band)
		_box(root, Vector3(0.20, 0.03, 0.25), Vector3( 0.12, 0.45, 0.0), m_band)

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
				# #212 — Shoulder reflective bands above the chest band.
				# Two short cross-chest strips, one per shoulder, sized just
				# wide enough to hug the upper-chest box (0.40 wide) without
				# overlapping the chest band underneath them.
				_box(root, Vector3(0.20, 0.03, 0.28), Vector3(-0.12, 0.43, 0.0), m_band_v)
				_box(root, Vector3(0.20, 0.03, 0.28), Vector3( 0.12, 0.43, 0.0), m_band_v)
			"operator":
				var m_vest_op := _hivis_material("orange")
				_box(root, Vector3(0.43, 0.42, 0.26), Vector3(0.0, 0.26, 0.0), m_vest_op)
				var m_band_o := _mat(Color(0.80, 0.82, 0.84), 0.25)
				_box(root, Vector3(0.44, 0.03, 0.27), Vector3(0.0, 0.36, 0.0), m_band_o)
				_box(root, Vector3(0.44, 0.03, 0.27), Vector3(0.0, 0.12, 0.0), m_band_o)
				# #212 — Shoulder reflective bands above the chest band
				# (mirrors the hi_vis case so both PPE classes carry the
				# upgraded reflective layout from the worker_outfit photo).
				_box(root, Vector3(0.20, 0.03, 0.28), Vector3(-0.12, 0.43, 0.0), m_band_o)
				_box(root, Vector3(0.20, 0.03, 0.28), Vector3( 0.12, 0.43, 0.0), m_band_o)
			_:
				pass

	# ── ARMS ──────────────────────────────────────────────────────────────────
	# Wrapped in a SHOULDER PIVOT Node3D at the shoulder joint (y=+0.47, top of
	# the upper-arm box) so the gait animator in NPC.gd can swing the whole arm
	# from the shoulder. Same Y-sum invariant as legs: pivot.y + mesh.y == old
	# mesh.y, so render-layer classification stays put.
	# Pivot names: ShoulderPivot_L / ShoulderPivot_R (NPC gait reads these).
	#
	# #212 — White work gloves. When the NPC is in a hi-vis loadout (hi_vis or
	# operator PPE, AND on duty) we layer a slightly-oversized white box over
	# the bare-skin hand. It lives INSIDE the shoulder pivot so it swings with
	# the arm. We skip the glove on the "none" PPE (off-shift attire) and any
	# off_duty state — same suppression rule as the vest/bands above.
	var _show_gloves : bool = (wear_state != "off_duty") \
		and (ppe_class == "hi_vis" or ppe_class == "operator")
	var m_glove : StandardMaterial3D = null
	if _show_gloves:
		m_glove = _mat(Color(0.92, 0.92, 0.92), 0.60)
	var _shoulder_y : float = 0.47
	for sx in [-1.0, 1.0]:
		var x : float = float(sx) * 0.27
		var sh := Node3D.new()
		sh.name = "ShoulderPivot_R" if sx > 0.0 else "ShoulderPivot_L"
		sh.position = Vector3(x, _shoulder_y, 0.0)
		root.add_child(sh)
		_box(sh, Vector3(0.11, 0.26, 0.12), Vector3(0.0, 0.34 - _shoulder_y, 0.0), m_shirt)     # upper arm
		_box(sh, Vector3(0.10, 0.26, 0.11), Vector3(0.0, 0.08 - _shoulder_y, 0.0), m_forearm)   # forearm
		_box(sh, Vector3(0.10, 0.10, 0.12), Vector3(0.0, -0.08 - _shoulder_y, -0.02), m_skin)    # hand — front (-Z), #205 flip fix
		if _show_gloves:
			# Glove is 1mm larger on every axis than the hand to avoid Z-fight
			# while still reading as "wrapping" the hand from any camera angle.
			_box(sh, Vector3(0.11, 0.11, 0.13), Vector3(0.0, -0.08 - _shoulder_y, -0.02), m_glove)

	# ── NECK + HEAD ─────────────────────────────────────────────────────────────
	_box(root, Vector3(0.12, 0.08, 0.12), Vector3(0.0, 0.53, 0.0), m_skin)        # neck
	var head_y := 0.68
	_box(root, Vector3(0.24, 0.28, 0.24), Vector3(0.0, head_y, 0.0), m_skin)      # head

	# Ears (sides of head)
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.03, 0.07, 0.06), Vector3(sx * 0.135, head_y, 0.0), m_skin)

	# Face features on the -Z face of the head (VISUAL FRONT RULE — visible
	# front MUST sit on local -Z to match the canonical convention). `fz` is
	# negative so eyes/nose/mouth/eyebrows all land on the canonical-forward side.
	var fz := -0.122
	# Eyebrows
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.06, 0.015, 0.01), Vector3(sx * 0.055, head_y + 0.07, fz), m_hair)
	# Eyes
	for sx in [-1.0, 1.0]:
		_box(root, Vector3(0.045, 0.03, 0.01), Vector3(sx * 0.055, head_y + 0.04, fz), m_dark)
	# Nose — pokes further forward, so MORE negative Z (fz - 0.01).
	_box(root, Vector3(0.04, 0.07, 0.05), Vector3(0.0, head_y - 0.01, fz - 0.01), m_skin)
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
		# Beard is pushed FURTHER FORWARD than the face plane to avoid Z-fight.
		# With face on -Z, "further forward" = more negative Z → fz - 0.015.
		var bfz : float = fz - 0.015
		if _is_stubble:
			# Deterministic stubble: ~38 ~3mm boxes seeded by variant + skin so the
			# same NPC always looks the same across reloads, but different NPCs
			# don't share the exact pattern. Region: chin + lower cheeks +
			# moustache strip on the -Z (front) face of the head.
			var rng := RandomNumberGenerator.new()
			rng.seed = (variant * 9973) ^ int(skin.r * 1000.0) ^ int(skin.g * 100.0) ^ int(skin.b * 10.0)
			var dot_size := Vector3(0.005, 0.005, 0.005)
			for _i in 38:
				# Region: x in [-0.10, 0.10], y in [head_y - 0.16, head_y - 0.04],
				# pushed onto the face plane (z = bfz, which is negative).
				var dx : float = rng.randf_range(-0.10, 0.10)
				var dy : float = rng.randf_range(head_y - 0.16, head_y - 0.04)
				# Skip the mouth opening (a small ellipse) so the stubble doesn't
				# block lips.
				var mouth_dy := dy - (head_y - 0.08)
				if abs(dx) < 0.045 and abs(mouth_dy) < 0.012:
					continue
				# Push 0.001 further forward (more negative Z) than bfz.
				_box(root, dot_size, Vector3(dx, dy, bfz - 0.001), beard_mat)
		if _has_chin:
			_box(root, Vector3(0.13, 0.05, 0.02),
				Vector3(0.0, head_y - 0.13, bfz), beard_mat)
		if _has_cheeks:
			# Cheek + jaw beard: same forward-of-face plane → negative Z.
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.025, 0.10, 0.18),
					Vector3(sx * 0.125, head_y - 0.06, -0.015), beard_mat)
			_box(root, Vector3(0.18, 0.025, 0.18),
				Vector3(0.0, head_y - 0.15, -0.015), beard_mat)
		if _has_stache:
			_box(root, Vector3(0.10, 0.022, 0.02),
				Vector3(0.0, head_y - 0.06, bfz), beard_mat)
		if _has_neck:
			_box(root, Vector3(0.10, 0.06, 0.12),
				Vector3(0.0, head_y - 0.20, -0.015), beard_mat)
		if _has_full:
			for sx in [-1.0, 1.0]:
				_box(root, Vector3(0.03, 0.08, 0.14),
					Vector3(sx * 0.13, head_y - 0.02, -0.02), beard_mat)

	# ── HAIR (#186) — supports bald, buzz, short, mid, long, ponytail, mullet.
	#     Drawn FIRST so the cap (if any) layers OVER it. Old behaviour replaced
	#     hair with the cap; operator complaint was "hair disappears when cap is
	#     on." Now the cap brim covers the front while the back/sides of the
	#     hair still poke through.
	if hair_style != "bald":
		# With face on -Z, the BACK of the head is on +Z. All "back-of-head"
		# hair pieces sit at positive Z.
		match hair_style:
			"buzz":
				# Buzz-cut: thin crown only, no back piece. Reads as "fresh
				# clippers" from a distance.
				_box(root, Vector3(0.255, 0.04, 0.255), Vector3(0.0, head_y + 0.11, 0.0), m_hair)
			"short":
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)   # top
				_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, 0.11), m_hair)   # back
			"mid":
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.30, 0.06), Vector3(0.0, head_y - 0.01, 0.11), m_hair)
			"long":
				# Crown + a long back piece reaching the shoulders + small side
				# strands so it doesn't read as a bib stuck to the head.
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.45, 0.06), Vector3(0.0, head_y - 0.12, 0.11), m_hair)
				for sx in [-1.0, 1.0]:
					# Side strands hang BEHIND the ears (slightly +Z).
					_box(root, Vector3(0.05, 0.32, 0.06),
						Vector3(sx * 0.115, head_y - 0.05, 0.04), m_hair)
			"ponytail":
				# Short crown + a slender vertical tail hanging off the back (+Z).
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, 0.11), m_hair)
				_box(root, Vector3(0.06, 0.35, 0.06), Vector3(0.0, head_y - 0.10, 0.14), m_hair)
			"mullet":
				# Business-in-the-front: short crown + long back-only piece (+Z).
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.32, 0.06), Vector3(0.0, head_y - 0.04, 0.11), m_hair)
			_:
				# Unknown style — fall back to "short" so a stale save doesn't
				# render a bald NPC silently.
				_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)
				_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, 0.11), m_hair)

	# ── CAP (#186) — layered ON TOP of hair (not instead of). Cap brim covers
	#     the front, hair still pokes out the back/sides for everyone except
	#     a "bald" wearer. Independent of PPE class; the cap is a wardrobe item.
	if wears_cap:
		# #212 — Cap colour resolution: explicit override > default dark navy.
		# A brighter company-blue (e.g. Color(0.13, 0.34, 0.78)) reproduces the
		# Kevin / Abdellilah caps in the worker_outfit reference photo without
		# breaking the legacy dark-navy look for NPCs that don't set the field.
		var cap_color : Color = Color(0.18, 0.22, 0.36)
		if cap_color_override is Color:
			cap_color = cap_color_override
		var cap_mat := _mat(cap_color, 0.78)
		_box(root, Vector3(0.28, 0.09, 0.28), Vector3(0.0, head_y + 0.135, 0.0), cap_mat)   # crown
		# Rig is authored face-on-LOCAL-(-Z): `fz := -0.122` at line 432 places
		# eyes/nose/mouth on the -Z face of the head box. "Forward of the face
		# plane" therefore means MORE NEGATIVE local Z. A prior fix had this
		# inverted (`fz + 0.04`), which tucked the brim INSIDE the head on the
		# +Z side — making the cap read as 180° turned and the whole head look
		# like it was facing backwards.
		_box(root, Vector3(0.26, 0.02, 0.10), Vector3(0.0, head_y + 0.09, fz - 0.04), cap_mat)  # brim (forward of face)
		# Optional fringe under the cap — auto-enabled whenever hair != bald so
		# the customizer (which doesn't expose hair_under_cap directly) just
		# does the right thing. Legacy NPC presets that set hair_under_cap=true
		# also still light up.
		if hair_style != "bald":
			# Forehead fringe sits IN FRONT of the face plane (more negative local Z).
			_box(root, Vector3(0.24, 0.025, 0.02),
				Vector3(0.0, head_y + 0.075, fz - 0.05), m_hair)
			for sx in [-1.0, 1.0]:
				# Side temple strands tucked slightly BEHIND the face plane
				# (less negative local Z) so they sit between the ear and the brim.
				_box(root, Vector3(0.025, 0.05, 0.04),
					Vector3(sx * 0.115, head_y + 0.04, fz + 0.01), m_hair)

	# Hardhat overlay if ppe_class == "operator" (drawn AFTER cap so it wins).
	if ppe_class == "operator" and wear_state != "off_duty":
		var m_hard := _mat(Color(0.94, 0.62, 0.10), 0.55)
		_box(root, Vector3(0.30, 0.08, 0.30), Vector3(0.0, head_y + 0.16, 0.0), m_hard)
		_box(root, Vector3(0.34, 0.02, 0.36), Vector3(0.0, head_y + 0.115, 0.02), m_hard)   # brim ring

	# ── ANIMATION PHASE 1 (cluster: Skeleton3D rig + locomotion BlendSpace) ──
	# After the box meshes are placed at their anatomical positions, install a
	# Skeleton3D rig + AnimationPlayer + AnimationTree alongside them.  Each
	# existing MeshInstance3D gets reparented under the BoneAttachment3D for the
	# bone that anatomically owns it (decided by its local position).  That way
	# the rig is BONE-DRIVEN: when the AnimationTree poses bones (idle / walk /
	# run blend), the visible boxes follow along — no skin resource required.
	#
	# NOTE: the existing `_set_body_render_layer_split` walker (MainWorld) and
	# `_set_render_layers_recursive` (CharacterCustomizer) both recurse over all
	# MeshInstance3D descendants of the rig root, so reparenting under
	# BoneAttachment3D nodes preserves the FP-vs-mirror render-layer behaviour.
	_install_skeleton_rig(root)

	# Phase 2: Foot-IK target nodes. (The SkeletonIK3D nodes live inside the rig,
	# but their targets must live in world space outside the rig so they don't
	# inherit the rig's animation transforms).
	# TODO: Controller needs to update these targets via raycasts.
	var foot_ik_targets := Node3D.new()
	foot_ik_targets.name = "FootIKTargets"
	var target_l := Marker3D.new()
	target_l.name = "Target_L"
	foot_ik_targets.add_child(target_l)
	var target_r := Marker3D.new()
	target_r.name = "Target_R"
	foot_ik_targets.add_child(target_r)
	root.add_child(foot_ik_targets)

	return root

# Audit item 26 — outdoor temperature resolver. Reads ShiftClock.get_outdoor_temp_c()
# via the autoload-sibling path used elsewhere in the codebase. Returns a mild
# +12 °C "neither warm nor cold" fallback when ShiftClock isn't reachable (test
# scenes, character customizer preview), so off-duty wardrobe choices land on
# whatever the operator picked instead of being silently overridden.
static func _resolve_outdoor_temp_c() -> float:
	# Engine.get_main_loop() is the safe way to reach the SceneTree from a static
	# function (we don't have a `self` to read get_tree() from).
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var root := (ml as SceneTree).root
		if root != null:
			var sc := root.get_node_or_null("MainWorld/ShiftClock")
			if sc != null and sc.has_method("get_outdoor_temp_c"):
				return float(sc.call("get_outdoor_temp_c"))
	return 12.0   # mild fallback — outside the cold/warm thresholds

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

# ═════════════════════════════════════════════════════════════════════════════
# ANIMATION PHASE 1 — Skeleton3D rig + AnimationPlayer + AnimationTree
# ═════════════════════════════════════════════════════════════════════════════
# Bone REST positions, expressed in PARENT bone's local space. (For root bone
# Hips the parent is the Skeleton3D origin, which lives at the rig's local
# origin = capsule centre.) Y axis is up; -Z is the canonical forward of the
# rig AFTER the +PI yaw applied at attach sites — internally bones are authored
# face-on-+Z (matching the box layout), and the attach-site yaw flips it.
#
# Numbers are anatomical centres of rotation, NOT the centres of the visible
# box meshes. The boxes get reparented under BoneAttachment3D nodes; their
# local position becomes (box_centre - bone_centre) so the visual layout is
# untouched at the rest pose.
const _BONE_NAMES : Array[String] = [
	"Hips", "Spine", "Chest", "Neck", "Head",
	"LShoulder", "LUpperArm", "LLowerArm", "LHand",
	"RShoulder", "RUpperArm", "RLowerArm", "RHand",
	"LUpperLeg", "LLowerLeg", "LFoot",
	"RUpperLeg", "RLowerLeg", "RFoot",
]
# parent_index for each bone (matches the order above; -1 = root)
const _BONE_PARENTS : Array[int] = [
	-1, 0, 1, 2, 3,
	2, 5, 6, 7,
	2, 9, 10, 11,
	0, 13, 14,
	0, 16, 17,
]
# Bone REST origin in PARENT-bone space (rotation rest = identity).
# Derived from the box-mesh anatomical layout above; see comments in build()
# (feet at y=-0.86, knee joint ≈ y=-0.44, hip joint ≈ y=-0.04, etc.).
# Each entry mirrors L→R via the x-sign on shoulder/leg bones.
const _BONE_REST_ORIGIN : Dictionary = {
	"Hips":       Vector3( 0.00, -0.06, 0.00),    # capsule-centre offset
	"Spine":      Vector3( 0.00,  0.16, 0.00),    # → spine pivot at y = 0.10
	"Chest":      Vector3( 0.00,  0.16, 0.00),    # → chest pivot at y = 0.26
	"Neck":       Vector3( 0.00,  0.27, 0.00),    # → neck pivot at y = 0.53
	"Head":       Vector3( 0.00,  0.15, 0.00),    # → head pivot at y = 0.68
	"LShoulder":  Vector3( 0.18,  0.21, 0.00),    # → shoulder at y = 0.47
	"LUpperArm":  Vector3( 0.00, -0.13, 0.00),    # → upper-arm pivot at y = 0.34
	"LLowerArm":  Vector3( 0.00, -0.13, 0.00),    # → elbow at y = 0.21
	"LHand":      Vector3( 0.00, -0.13, 0.00),    # → wrist at y = 0.08
	"RShoulder":  Vector3(-0.18,  0.21, 0.00),
	"RUpperArm":  Vector3( 0.00, -0.13, 0.00),
	"RLowerArm":  Vector3( 0.00, -0.13, 0.00),
	"RHand":      Vector3( 0.00, -0.13, 0.00),
	"LUpperLeg":  Vector3( 0.12, -0.18, 0.00),    # → hip joint at y = -0.24
	"LLowerLeg":  Vector3( 0.00, -0.20, 0.00),    # → knee at y = -0.44
	"LFoot":      Vector3( 0.00, -0.38, 0.00),    # → ankle at y = -0.82
	"RUpperLeg":  Vector3(-0.12, -0.18, 0.00),
	"RLowerLeg":  Vector3( 0.00, -0.20, 0.00),
	"RFoot":      Vector3( 0.00, -0.38, 0.00),
}

## Install a Skeleton3D + per-bone BoneAttachment3D + AnimationPlayer +
## AnimationTree(BlendSpace2D "Locomotion") under `root`, and reparent each
## existing MeshInstance3D direct child of `root` under the BoneAttachment3D
## for the bone that anatomically owns it.
##
## NOTE: The vertical scale of `root` (#126 height_mul) does NOT apply to the
## skeleton's own pose-space transforms — bones are authored at the unit-height
## anatomical positions and the whole skeleton then inherits the root scale.
## So a 1.10× tall NPC's hips rest at y = -0.06 × 1.10 = -0.066 in WORLD space,
## but the bone rest itself stays at -0.06. The box meshes were authored the
## same way (root-relative), so they line up after reparenting.
static func _install_skeleton_rig(root: Node3D) -> void:
	if root == null:
		return
	# Build the Skeleton3D first, with all bones at their REST poses.
	var skel := Skeleton3D.new()
	skel.name = "Skeleton3D"
	var bone_index : Dictionary = {}
	for i in _BONE_NAMES.size():
		var bname : String = _BONE_NAMES[i]
		var bi : int = skel.add_bone(bname)
		bone_index[bname] = bi
		var parent_i : int = _BONE_PARENTS[i]
		if parent_i >= 0:
			skel.set_bone_parent(bi, parent_i)
		var rest_origin : Vector3 = _BONE_REST_ORIGIN.get(bname, Vector3.ZERO)
		var rest := Transform3D(Basis(), rest_origin)
		skel.set_bone_rest(bi, rest)
		skel.set_bone_pose_position(bi, rest_origin)
		skel.set_bone_pose_rotation(bi, Quaternion.IDENTITY)
		skel.set_bone_pose_scale(bi, Vector3.ONE)
	root.add_child(skel)
	# One BoneAttachment3D per bone — children of the Skeleton3D, named after
	# the bone so the AnimationPlayer track resolver can find them by path.
	# We cache them in a dict so the box-reparent step is O(1) per mesh.
	#
	# We ALSO seed each attachment's transform to the bone's rest world-position
	# BEFORE the first frame. That's so MainWorld._set_body_render_layer_split
	# (called right after add_child) can sum position.y up the chain and get the
	# original anatomical y immediately — Godot otherwise leaves the attachment
	# at (0,0,0) until its first physics/process tick syncs from the bone.
	var attach_by_bone : Dictionary = {}
	for bname in _BONE_NAMES:
		var att := BoneAttachment3D.new()
		att.name = "BA_" + bname
		att.bone_name = bname
		# Seed the rest-pose transform so the splitter walker reads correct y
		# on the first call. The bone auto-sync overwrites this with the SAME
		# value (rest pose) once the animation tree starts driving the bones.
		att.position = _bone_world_origin(bname)
		skel.add_child(att)
		attach_by_bone[bname] = att

	# Phase 2: Attachment slots
	var slot_portofoon := BoneAttachment3D.new()
	slot_portofoon.name = "Slot_Portofoon"
	slot_portofoon.bone_name = "Chest"
	skel.add_child(slot_portofoon)

	var slot_hose := BoneAttachment3D.new()
	slot_hose.name = "Slot_Hose"
	slot_hose.bone_name = "RHand"
	skel.add_child(slot_hose)

	var slot_steering := BoneAttachment3D.new()
	slot_steering.name = "Slot_Steering"
	slot_steering.bone_name = "Chest"
	skel.add_child(slot_steering)

	# Phase 2: Foot IK
	var ik_l := SkeletonIK3D.new()
	ik_l.name = "IK_Foot_L"
	ik_l.root_bone = "LUpperLeg"
	ik_l.tip_bone = "LFoot"
	ik_l.target_node = NodePath("../../FootIKTargets/Target_L")
	skel.add_child(ik_l)

	var ik_r := SkeletonIK3D.new()
	ik_r.name = "IK_Foot_R"
	ik_r.root_bone = "RUpperLeg"
	ik_r.tip_bone = "RFoot"
	ik_r.target_node = NodePath("../../FootIKTargets/Target_R")
	skel.add_child(ik_r)
	# ── Reparent EVERY MeshInstance3D descendant of root under its bone ──────
	# 2026-08-28 rig unification: the Skeleton3D + AnimationTree is the ONE
	# animation system — limbs included. (The sine-based pivot gait this used
	# to defer to was an empty stub; limb meshes on the pivots never animated:
	# walk read as a statue and prone folded the torso while the legs stayed
	# standing.) Meshes under the legacy HipPivot_*/ShoulderPivot_* nodes
	# classify by their root-local position, which _local_in_root computes by
	# summing Node3D origins up the parent chain — pivots included.
	var all_meshes : Array = []
	_collect_meshes_recursive(root, all_meshes)
	for mi in all_meshes:
		var mi3d : MeshInstance3D = mi
		var local_in_root : Vector3 = _local_in_root(mi3d, root)
		var owner_bone : String = _classify_bone_owner(local_in_root)
		var att : BoneAttachment3D = attach_by_bone[owner_bone]
		# Bone REST origin in rig-root space.
		var bone_world : Vector3 = _bone_world_origin(owner_bone)
		var local_offset : Vector3 = local_in_root - bone_world
		# Reparent. Preserve the visual position — the BoneAttachment3D sits at
		# the bone's posed origin, so subtracting bone_world keeps the mesh
		# exactly where it was when the bone is at its rest pose.
		var prev_parent : Node = mi3d.get_parent()
		if prev_parent != null:
			prev_parent.remove_child(mi3d)
		att.add_child(mi3d)
		mi3d.position = local_offset
		mi3d.rotation = Vector3.ZERO   # legacy pivots applied rotations to the
		mi3d.scale = Vector3.ONE       # parent; the mesh transform stays clean
	# ── AnimationPlayer ──────────────────────────────────────────────────────
	var ap := AnimationPlayer.new()
	ap.name = "AnimationPlayer"
	root.add_child(ap)
	var lib := AnimationLibrary.new()
	lib.add_animation("idle", _build_anim_idle(skel))
	lib.add_animation("walk", _build_anim_walk(skel))
	lib.add_animation("run",  _build_anim_run(skel))
	lib.add_animation("strafe_l", _build_anim_strafe_l(skel))   # #224
	lib.add_animation("strafe_r", _build_anim_strafe_r(skel))   # #224
	# Phase 2 stance poses (single-frame holds). The state machine below travels
	# between locomotion / crouch / prone / seated based on the controller's stance.
	lib.add_animation("crouch_pose", _build_anim_crouch(skel))
	lib.add_animation("prone_pose",  _build_anim_prone(skel))
	lib.add_animation("seated_pose", _build_anim_seated(skel))
	lib.add_animation("climb_pose",  _build_anim_climb(skel))
	lib.add_animation("jump_pose",   _build_anim_jump(skel))
	ap.add_animation_library("", lib)
	# We do NOT call ap.play("idle") here — the rig root isn't in the scene
	# tree yet, and play() requires the player to be active. The AnimationTree
	# (added next, active=true) drives playback the instant the rig is added
	# to a parent. If for some reason the tree is disabled, the NPC just
	# stands in its rest pose, which is anatomically correct (not a T-pose).
	# ── AnimationTree with BlendSpace2D locomotion node ──────────────────────
	# X axis: speed (0 = idle, 1 = walk, 2 = run). Y axis: strafe (reserved for
	# Phase 2 — we author one row at Y=0 for now).  We DON'T bake a
	# AnimationNodeStateMachine here; the BlendSpace2D is the single root node,
	# which is the minimum surface area for NPC.gd / PlayerController.gd to
	# update via `set("parameters/blend_position", v2)`.
	var atree := AnimationTree.new()
	atree.name = "AnimationTree"
	# Both AnimationPlayer and AnimationTree are children of `root` (the rig
	# Body node). NodePath("../AnimationPlayer") resolves from the tree node up
	# to root then back down to ap — works whether or not `root` is currently
	# parented (get_path() would return a useless path while root is detached).
	atree.anim_player = NodePath("../AnimationPlayer")
	var bs := AnimationNodeBlendSpace2D.new()
	bs.blend_mode = AnimationNodeBlendSpace2D.BLEND_MODE_INTERPOLATED
	bs.min_space = Vector2(0.0, -1.0)
	bs.max_space = Vector2(2.0,  1.0)
	bs.snap = Vector2(0.1, 0.1)
	# Three points along the speed axis. Y=0 is "straight forward"; strafe rows
	# are Phase 2.
	var n_idle := AnimationNodeAnimation.new()
	n_idle.animation = "idle"
	var n_walk := AnimationNodeAnimation.new()
	n_walk.animation = "walk"
	var n_run := AnimationNodeAnimation.new()
	n_run.animation = "run"
	bs.add_blend_point(n_idle, Vector2(0.0, 0.0))
	bs.add_blend_point(n_walk, Vector2(1.0, 0.0))
	bs.add_blend_point(n_run,  Vector2(2.0, 0.0))
	# #224 — strafe rows on the Y axis (left = -1, right = +1) at walk speed.
	var n_strafe_l := AnimationNodeAnimation.new()
	n_strafe_l.animation = "strafe_l"
	var n_strafe_r := AnimationNodeAnimation.new()
	n_strafe_r.animation = "strafe_r"
	bs.add_blend_point(n_strafe_l, Vector2(1.0, -1.0))
	bs.add_blend_point(n_strafe_r, Vector2(1.0,  1.0))
	# Phase 2: wrap the locomotion BlendSpace + three pose animations in a
	# StateMachine. The controller (PlayerController._update_animation_blend and
	# NPC._update_animation_blend) travels between states by writing
	# parameters/playback. Locomotion still receives speed via
	# parameters/locomotion/blend_position (note the new nested path).
	var n_crouch := AnimationNodeAnimation.new()
	n_crouch.animation = "crouch_pose"
	var n_prone := AnimationNodeAnimation.new()
	n_prone.animation = "prone_pose"
	var n_seated := AnimationNodeAnimation.new()
	n_seated.animation = "seated_pose"
	var n_climb := AnimationNodeAnimation.new()
	n_climb.animation = "climb_pose"
	# Operator bug report 2026-08-28: jumping showed the same stiff statue as
	# everything else — there was NO airborne pose at all. "jump" is a static
	# in-air hold (legs tucked asymmetrically, arms out for balance); the
	# controller travels here while off the floor and back on landing.
	var n_jump := AnimationNodeAnimation.new()
	n_jump.animation = "jump_pose"
	var sm := AnimationNodeStateMachine.new()
	sm.add_node("locomotion", bs,        Vector2(   0.0,   0.0))
	sm.add_node("crouch",     n_crouch,  Vector2( 200.0, 120.0))
	sm.add_node("prone",      n_prone,   Vector2( 400.0, 120.0))
	sm.add_node("seated",     n_seated,  Vector2( 600.0, 120.0))
	sm.add_node("climb",      n_climb,   Vector2( 800.0, 120.0))
	sm.add_node("jump",       n_jump,    Vector2(1000.0, 120.0))
	# Godot 4.6 has no set_start_node() — the initial state is selected by
	# adding a transition from the built-in "Start" pseudonode (it always
	# exists, alongside "End"). SWITCH_MODE_IMMEDIATE so locomotion is active
	# from frame 0 with no hold on the Start node.
	var t_start := AnimationNodeStateMachineTransition.new()
	t_start.switch_mode = AnimationNodeStateMachineTransition.SWITCH_MODE_IMMEDIATE
	sm.add_transition("Start", "locomotion", t_start)
	# Bi-directional transitions between locomotion and each pose state, plus
	# pose-to-pose so the operator can rebind crouch→prone without first standing.
	var pose_states := ["crouch", "prone", "seated", "climb", "jump"]
	for to in pose_states:
		var t_to := AnimationNodeStateMachineTransition.new()
		t_to.xfade_time = 0.25
		sm.add_transition("locomotion", to, t_to)
		var t_back := AnimationNodeStateMachineTransition.new()
		t_back.xfade_time = 0.25
		sm.add_transition(to, "locomotion", t_back)
	for a_state in pose_states:
		for b_state in pose_states:
			if a_state == b_state:
				continue
			var t_ab := AnimationNodeStateMachineTransition.new()
			t_ab.xfade_time = 0.25
			sm.add_transition(a_state, b_state, t_ab)
	atree.tree_root = sm
	atree.active = true
	root.add_child(atree)

## Bone-owner heuristic — picks a bone name from a box's LOCAL-to-RIG-ROOT
## position so each mesh gets parented under the right bone. The Humanoid is
## authored at known anatomical Y bands, so a simple piecewise classifier is
## enough.
##  · y < -0.78  (foot box ≈ -0.86, boot cuff ≈ -0.78)               → Foot
##  · -0.78 ≤ y < -0.44 (shin ≈ -0.62)                                → LowerLeg
##  · -0.44 ≤ y < -0.10 (thigh ≈ -0.24)                               → UpperLeg
##  · -0.10 ≤ y <  0.16 (pelvis ≈ -0.06, waist bands ≈ 0.08, 0.12)    → Hips
##  ·  0.16 ≤ y <  0.50 (chest ≈ 0.26, vest bands ≈ 0.36, 0.38)       → Chest
##  ·  0.50 ≤ y <  0.58 (neck ≈ 0.53)                                 → Neck
##  ·  y ≥  0.58 (head ≈ 0.68, ears, face features, hair, cap, hardhat) → Head
## The arm-region split is x-sign based: |x| > 0.20 = arm (further split by Y
## into UpperArm / LowerArm / Hand), |x| ≤ 0.20 = trunk.
##
## NOTE on edge cases: the MOUTH sits at y ≈ 0.60 (head_y - 0.08), so the
## Head threshold is 0.58 (not 0.62) so face features that hang below the head
## centre still ride with the head. The CHIN/BEARD plates go as low as
## y ≈ 0.48 (head_y - 0.20), which classify as Neck — close enough to the head
## that they still read correctly during a head-nod animation; Phase 2 will
## stuff them under Head explicitly.
static func _classify_bone_owner(local: Vector3) -> String:
	var x : float = local.x
	var y : float = local.y
	# ── ARMS (off-centre torso boxes) ──
	# Upper-arm/forearm/hand boxes are placed at |x| ≈ 0.27 (see ARMS section
	# in build()); torso/PPE bands are at x ≈ 0.0. A clean split at |x| > 0.20.
	if absf(x) > 0.20:
		if y >= 0.20:
			return "LUpperArm" if x > 0.0 else "RUpperArm"
		elif y >= -0.02:
			return "LLowerArm" if x > 0.0 else "RLowerArm"
		else:
			return "LHand" if x > 0.0 else "RHand"
	# ── LEGS (off-centre lower-body boxes) ──
	# Foot/shin/thigh boxes are at |x| ≈ 0.12; pelvis+waist bands at x ≈ 0.0.
	# Split: y < -0.10 AND |x| > 0.05 = a leg box.
	if y < -0.10 and absf(x) > 0.05:
		if y < -0.74:
			return "LFoot" if x > 0.0 else "RFoot"
		elif y < -0.44:
			return "LLowerLeg" if x > 0.0 else "RLowerLeg"
		else:
			return "LUpperLeg" if x > 0.0 else "RUpperLeg"
	# ── TRUNK / HEAD ──
	# Everything centred (or near-centred) drops through to the spine column.
	# Head threshold lowered to 0.58 so the mouth box (≈0.60) still rides
	# with the head rotation.
	if y >= 0.58:
		return "Head"
	elif y >= 0.50:
		return "Neck"
	elif y >= 0.16:
		return "Chest"
	# Pelvis / waist band region — sits on the hips bone.
	return "Hips"

## Recursively collect every MeshInstance3D under `node` into `out`. Skips
## anything that's already under a BoneAttachment3D (in case _install_skeleton_rig
## is ever re-entered on a partially-rigged tree).
static func _collect_meshes_recursive(node: Node, out: Array) -> void:
	for c in node.get_children():
		if c is BoneAttachment3D:
			continue   # already rigged — don't re-collect its descendants
		# 2026-08-28 rig unification (operator bug report: walk was a statue,
		# prone folded the torso while the legs stayed standing). This walker
		# used to SKIP the HipPivot_L/R and ShoulderPivot_L/R subtrees for the
		# sine-based pivot gait (audit item 2) — but that gait was long dead
		# (NPC._apply_gait is an empty stub), so limb meshes sat on static
		# pivots while the AnimationTree rotated limb bones that owned no
		# meshes. Limbs are now collected like everything else and reparent
		# under their bones; _local_in_root sums positions through the pivots,
		# so classification is unchanged. The empty pivot Node3Ds stay in the
		# tree for name-compat (e.g. MainWorld's FP layer splitter still
		# honours the old ancestry).
		if c is MeshInstance3D:
			out.append(c)
		if c is Node:
			_collect_meshes_recursive(c, out)

## Express a node's transform-origin in the rig ROOT's local space by walking
## up the parent chain summing positions. Used to classify a mesh by its
## anatomical position regardless of whether it's under an intermediate pivot
## (HipPivot_*, ShoulderPivot_*) or directly under root.
static func _local_in_root(node: Node3D, root: Node3D) -> Vector3:
	var acc : Vector3 = node.position
	var p : Node = node.get_parent()
	# Limit the walk to a sane depth so a malformed tree can't infinite-loop.
	for _i in 16:
		if p == null or p == root or not (p is Node3D):
			break
		acc += (p as Node3D).position
		p = p.get_parent()
	return acc

## Compute a bone's REST origin in SKELETON-local space (= rig root space) by
## walking up the parent chain and accumulating origins. Used to convert each
## box's pre-rig local position into a post-rig bone-local offset.
static func _bone_world_origin(bone_name: String) -> Vector3:
	var acc : Vector3 = Vector3.ZERO
	var cur : String = bone_name
	# Hard cap to avoid an infinite loop if the constants ever get mis-edited.
	for _i in 32:
		if not _BONE_REST_ORIGIN.has(cur):
			break
		acc += _BONE_REST_ORIGIN[cur] as Vector3
		var idx : int = _BONE_NAMES.find(cur)
		if idx < 0:
			break
		var parent_i : int = _BONE_PARENTS[idx]
		if parent_i < 0:
			break
		cur = _BONE_NAMES[parent_i]
	return acc

# ─── Procedural animation authoring ──────────────────────────────────────────
# Each animation is a small set of bone-rotation tracks targeting the
# Skeleton3D via the path "Skeleton3D:<bone_name>". TYPE_ROTATION_3D keys take
# Quaternion values; we author 4 keyframes per bone (0, 1/4, 1/2, 3/4 of the
# loop) and let Godot's loop interpolation close the cycle.
#
# Convention reminder: the rig is authored face-on-+Z internally, and attach
# sites yaw the whole rig by +PI to align face with -basis.z. That means
# "swing the leg FORWARD" in animation space is a rotation around X by a
# NEGATIVE angle (forward = +Z internally → bone tip rotates toward +Z by
# tilting around the +X axis NEGATIVELY in right-handed Y-up). We pick the
# signs so the rendered result reads as "walk forward" after the +PI yaw.

const _IDLE_LOOP_S : float = 2.0
const _WALK_LOOP_S : float = 1.2
const _RUN_LOOP_S  : float = 0.8

## Subtle breathing — chest tilts back a few degrees on inhale, neck nods. No
## limb motion; this is what plays when the operator is standing at a HMI.
static func _build_anim_idle(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = _IDLE_LOOP_S
	a.loop_mode = Animation.LOOP_LINEAR
	# Spine tilt — ±2° on a slow sine.
	_add_rot_track(a, "Spine", [
		[0.00, Quaternion.IDENTITY],
		[0.50, Quaternion(Vector3.RIGHT, deg_to_rad(-2.0))],
		[1.00, Quaternion.IDENTITY],
		[1.50, Quaternion(Vector3.RIGHT, deg_to_rad( 1.0))],
	])
	# Head sway — tiny yaw left/right so the head doesn't read as locked.
	_add_rot_track(a, "Head", [
		[0.00, Quaternion.IDENTITY],
		[0.50, Quaternion(Vector3.UP, deg_to_rad( 2.5))],
		[1.00, Quaternion.IDENTITY],
		[1.50, Quaternion(Vector3.UP, deg_to_rad(-2.5))],
	])
	# Arms hang with a faint inward bias so they don't look pinned to T.
	_add_rot_track(a, "LUpperArm", [
		[0.00, Quaternion(Vector3.FORWARD, deg_to_rad( 5.0))],
		[1.00, Quaternion(Vector3.FORWARD, deg_to_rad( 3.0))],
	])
	_add_rot_track(a, "RUpperArm", [
		[0.00, Quaternion(Vector3.FORWARD, deg_to_rad(-5.0))],
		[1.00, Quaternion(Vector3.FORWARD, deg_to_rad(-3.0))],
	])
	return a

## Walk cycle — alternating leg swing, arms counter-swing, slight hip
## counter-rotation. 1.2 s loop matches a 2 m/s gait at ~80 SPM.
static func _build_anim_walk(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = _WALK_LOOP_S
	a.loop_mode = Animation.LOOP_LINEAR
	# Leg swing: ±25° around X (forward/back), 180° out of phase L vs R.
	# Knee bends on the back-swing return so the foot lifts cleanly.
	_add_rot_track(a, "LUpperLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad( 25.0))],   # forward
		[0.3,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-25.0))],   # back
		[0.9,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
	])
	_add_rot_track(a, "LLowerLeg", [
		[0.0,  Quaternion.IDENTITY],
		[0.3,  Quaternion(Vector3.RIGHT, deg_to_rad(-10.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-35.0))],   # knee lifts on rear pass
		[0.9,  Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))],
	])
	_add_rot_track(a, "RUpperLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-25.0))],
		[0.3,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad( 25.0))],
		[0.9,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
	])
	_add_rot_track(a, "RLowerLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-35.0))],
		[0.3,  Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))],
		[0.6,  Quaternion.IDENTITY],
		[0.9,  Quaternion(Vector3.RIGHT, deg_to_rad(-10.0))],
	])
	# Arms swing opposite the same-side leg (Left arm forward when Right leg
	# forward) — that's how humans walk.
	_add_rot_track(a, "LUpperArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-22.0))],
		[0.3,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad( 22.0))],
		[0.9,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
	])
	_add_rot_track(a, "RUpperArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad( 22.0))],
		[0.3,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-22.0))],
		[0.9,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
	])
	# Faint elbow bend so arms aren't sticks.
	_add_rot_track(a, "LLowerArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-12.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-22.0))],
	])
	_add_rot_track(a, "RLowerArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-22.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-12.0))],
	])
	# Hip counter-rotation around Y — the pelvis twists opposite the chest.
	_add_rot_track(a, "Hips", [
		[0.0,  Quaternion(Vector3.UP, deg_to_rad( 4.0))],
		[0.6,  Quaternion(Vector3.UP, deg_to_rad(-4.0))],
	])
	_add_rot_track(a, "Chest", [
		[0.0,  Quaternion(Vector3.UP, deg_to_rad(-4.0))],
		[0.6,  Quaternion(Vector3.UP, deg_to_rad( 4.0))],
	])
	return a

## Run cycle — same shape as walk, larger amplitudes, faster (0.8 s loop) and
## more forward lean on the torso.
static func _build_anim_run(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = _RUN_LOOP_S
	a.loop_mode = Animation.LOOP_LINEAR
	_add_rot_track(a, "LUpperLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad( 40.0))],
		[0.2,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
		[0.4,  Quaternion(Vector3.RIGHT, deg_to_rad(-35.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
	])
	_add_rot_track(a, "LLowerLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))],
		[0.2,  Quaternion(Vector3.RIGHT, deg_to_rad(-25.0))],
		[0.4,  Quaternion(Vector3.RIGHT, deg_to_rad(-60.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-30.0))],
	])
	_add_rot_track(a, "RUpperLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-35.0))],
		[0.2,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
		[0.4,  Quaternion(Vector3.RIGHT, deg_to_rad( 40.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(  0.0))],
	])
	_add_rot_track(a, "RLowerLeg", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-60.0))],
		[0.2,  Quaternion(Vector3.RIGHT, deg_to_rad(-30.0))],
		[0.4,  Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))],
		[0.6,  Quaternion(Vector3.RIGHT, deg_to_rad(-25.0))],
	])
	_add_rot_track(a, "LUpperArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-45.0))],
		[0.4,  Quaternion(Vector3.RIGHT, deg_to_rad( 45.0))],
	])
	_add_rot_track(a, "RUpperArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad( 45.0))],
		[0.4,  Quaternion(Vector3.RIGHT, deg_to_rad(-45.0))],
	])
	# Elbows held bent (~90°) like a real running arm — fixed pose.
	_add_rot_track(a, "LLowerArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-85.0))],
	])
	_add_rot_track(a, "RLowerArm", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(-85.0))],
	])
	# Forward lean of the spine on a run.
	_add_rot_track(a, "Spine", [
		[0.0,  Quaternion(Vector3.RIGHT, deg_to_rad(  8.0))],
	])
	# Stronger hip counter-rotation than walk.
	_add_rot_track(a, "Hips", [
		[0.0,  Quaternion(Vector3.UP, deg_to_rad(  7.0))],
		[0.4,  Quaternion(Vector3.UP, deg_to_rad( -7.0))],
	])
	_add_rot_track(a, "Chest", [
		[0.0,  Quaternion(Vector3.UP, deg_to_rad( -7.0))],
		[0.4,  Quaternion(Vector3.UP, deg_to_rad(  7.0))],
	])
	return a

## #224 Side-step (strafe) — lateral weight-shift gait for BlendSpace2D Y=±1.
## dir = +1 steps LEFT, -1 steps RIGHT. Legs abduct/adduct sideways (around the
## Z/FORWARD axis) instead of the fore/aft X swing; the torso leans into the step
## and the arms float out for balance. Angles are a first pass — eyeball-tune in
## game. 1.0 s loop.
static func _build_anim_strafe_l(_skel: Skeleton3D) -> Animation:
	return _build_strafe(1.0)
static func _build_anim_strafe_r(_skel: Skeleton3D) -> Animation:
	return _build_strafe(-1.0)
static func _build_strafe(dir: float) -> Animation:
	var a := Animation.new()
	a.length = 1.0
	a.loop_mode = Animation.LOOP_LINEAR
	# Lead + trail legs alternate an out-step / follow around the FORWARD axis.
	_add_rot_track(a, "LUpperLeg", [
		[0.0, Quaternion(Vector3.FORWARD, deg_to_rad( 16.0 * dir))],
		[0.5, Quaternion(Vector3.FORWARD, deg_to_rad(  2.0 * dir))],
		[1.0, Quaternion(Vector3.FORWARD, deg_to_rad( 16.0 * dir))],
	])
	_add_rot_track(a, "RUpperLeg", [
		[0.0, Quaternion(Vector3.FORWARD, deg_to_rad(  2.0 * dir))],
		[0.5, Quaternion(Vector3.FORWARD, deg_to_rad( 16.0 * dir))],
		[1.0, Quaternion(Vector3.FORWARD, deg_to_rad(  2.0 * dir))],
	])
	_add_rot_track(a, "LLowerLeg", [
		[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( -6.0))],
		[0.5, Quaternion(Vector3.RIGHT, deg_to_rad(-20.0))],
		[1.0, Quaternion(Vector3.RIGHT, deg_to_rad( -6.0))],
	])
	_add_rot_track(a, "RLowerLeg", [
		[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-20.0))],
		[0.5, Quaternion(Vector3.RIGHT, deg_to_rad( -6.0))],
		[1.0, Quaternion(Vector3.RIGHT, deg_to_rad(-20.0))],
	])
	# Arms float out from the sides + a torso lean into the travel direction.
	_add_rot_track(a, "LUpperArm", [[0.0, Quaternion(Vector3.FORWARD, deg_to_rad( 16.0))]])
	_add_rot_track(a, "RUpperArm", [[0.0, Quaternion(Vector3.FORWARD, deg_to_rad(-16.0))]])
	_add_rot_track(a, "Spine", [[0.0, Quaternion(Vector3.FORWARD, deg_to_rad( 5.0 * dir))]])
	return a

## Add one TYPE_ROTATION_3D track to `a` for the given bone, keyed at the
## supplied (time, quaternion) pairs. The path resolves against the
## Skeleton3D named "Skeleton3D" added by _install_skeleton_rig.
static func _add_rot_track(a: Animation, bone_name: String, keys: Array) -> void:
	var ti : int = a.add_track(Animation.TYPE_ROTATION_3D)
	a.track_set_path(ti, NodePath("Skeleton3D:" + bone_name))
	a.track_set_interpolation_loop_wrap(ti, true)
	a.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	for k in keys:
		var t : float = float(k[0])
		var q : Quaternion = k[1] as Quaternion
		a.rotation_track_insert_key(ti, t, q)

## Add one TYPE_POSITION_3D track. Used by the stance poses below to lower the
## Hips when crouching / proning / sitting.
static func _add_pos_track(a: Animation, bone_name: String, keys: Array) -> void:
	var ti : int = a.add_track(Animation.TYPE_POSITION_3D)
	a.track_set_path(ti, NodePath("Skeleton3D:" + bone_name))
	a.track_set_interpolation_loop_wrap(ti, true)
	a.track_set_interpolation_type(ti, Animation.INTERPOLATION_LINEAR)
	for k in keys:
		var t : float = float(k[0])
		var p : Vector3 = k[1] as Vector3
		a.position_track_insert_key(ti, t, p)

# ── Phase 2 stance poses ──────────────────────────────────────────────────────
# Each is a 0.5 s loop holding a single static pose. The AnimationTree state
# machine in _install_skeleton_rig travels between locomotion ↔ crouch / prone
# / seated based on the controller's _stance / vehicle-occupied state, with a
# 0.25 s crossfade. Procedurally generated so no external rig data is needed.

## Crouch pose — hips drop ~20 cm via the Hips position track, knees bend
## forward, thighs rotate back, mild forward Spine lean. Holds statically.
static func _build_anim_crouch(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	_add_pos_track(a, "Hips", [
		[0.0, Vector3(0.0, -0.22, 0.0)],
		[0.5, Vector3(0.0, -0.22, 0.0)],
	])
	_add_rot_track(a, "LUpperLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 70.0))]])
	_add_rot_track(a, "RUpperLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 70.0))]])
	_add_rot_track(a, "LLowerLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))]])
	_add_rot_track(a, "RLowerLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))]])
	_add_rot_track(a, "Spine",     [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 15.0))]])
	return a

## Prone pose — face-down. The Hips bone rotates +90° around X so the whole
## kinematic chain lays horizontal (rig-internal forward is +Z, so POSITIVE X
## pitch tips the torso chest-toward-+Z = a forward dive onto the belly; the
## first cut used -90° and rendered face-UP, arms poking skyward — caught by
## shot_humanoid_stances after the 2026-08-28 rig unification), plus a downward
## position so the body settles near floor level instead of floating where the
## capsule centre was. Arms rest alongside the head, slightly raised.
static func _build_anim_prone(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	_add_pos_track(a, "Hips", [[0.0, Vector3(0.0, -0.75, 0.0)]])
	_add_rot_track(a, "Hips",     [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 90.0))]])
	_add_rot_track(a, "Spine",    [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(  5.0))]])
	# Nod the head BACK relative to the flat chain so the face doesn't bury
	# itself in the floor (negative X = tilt toward the rig's -Z back side).
	_add_rot_track(a, "Head",     [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-30.0))]])
	# From the hanging rest (-Y) a -160° X swing carries the arm up past the
	# shoulder toward the head; with the chain face-down that lays the arms
	# beside the head, elbows softly bent so the gloves rest near the floor.
	_add_rot_track(a, "LUpperArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-160.0))]])
	_add_rot_track(a, "RUpperArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-160.0))]])
	_add_rot_track(a, "LLowerArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( -20.0))]])
	_add_rot_track(a, "RLowerArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( -20.0))]])
	_add_rot_track(a, "LUpperLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(  -5.0))]])
	_add_rot_track(a, "RUpperLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(  -5.0))]])
	return a

## Jump / airborne pose — static in-air hold (operator bug report 2026-08-28:
## there was no airborne pose, jumps showed the stiff statue). Asymmetric leg
## tuck (lead knee up, trail leg back) + arms out from the sides and slightly
## back for balance, small forward spine lean. The 0.25 s state crossfade does
## the takeoff/landing smoothing.
static func _build_anim_jump(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	# Lead (left) leg: thigh up, knee folded. Trail (right) leg: swept back.
	_add_rot_track(a, "LUpperLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 45.0))]])
	_add_rot_track(a, "LLowerLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-70.0))]])
	_add_rot_track(a, "RUpperLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-20.0))]])
	_add_rot_track(a, "RLowerLeg", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-45.0))]])
	# Arms abduct sideways (FORWARD axis, same sign convention as idle's inward
	# bias but opposite direction) + a little behind the torso.
	_add_rot_track(a, "LUpperArm", [[0.0,
		Quaternion(Vector3.FORWARD, deg_to_rad(-35.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))]])
	_add_rot_track(a, "RUpperArm", [[0.0,
		Quaternion(Vector3.FORWARD, deg_to_rad( 35.0)) * Quaternion(Vector3.RIGHT, deg_to_rad(-15.0))]])
	_add_rot_track(a, "LLowerArm", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-25.0))]])
	_add_rot_track(a, "RLowerArm", [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-25.0))]])
	_add_rot_track(a, "Spine",     [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(  6.0))]])
	return a

## Climb pose — used during vault/mantle. Arms raised, one knee bent up.
static func _build_anim_climb(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	_add_pos_track(a, "Hips",     [[0.0, Vector3(0.0, -0.15, 0.0)]])
	_add_rot_track(a, "LUpperLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 80.0))]])
	_add_rot_track(a, "RUpperLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 10.0))]])
	_add_rot_track(a, "LLowerLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-80.0))]])
	_add_rot_track(a, "RLowerLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( -5.0))]])
	_add_rot_track(a, "LUpperArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(130.0))]])
	_add_rot_track(a, "RUpperArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(130.0))]])
	_add_rot_track(a, "LLowerArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 40.0))]])
	_add_rot_track(a, "RLowerArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 40.0))]])
	_add_rot_track(a, "Spine",    [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 10.0))]])
	return a

## Seated pose — used when entering any vehicle. Hips slightly lowered, hips
## flexed 90° (legs forward), knees bent 90° (shins down), elbows bent so the
## hands rest near the lap (close enough to a steering wheel for a placeholder
## seated-driving look). Per-vehicle bespoke seated poses are Phase 3 work.
static func _build_anim_seated(_skel: Skeleton3D) -> Animation:
	var a := Animation.new()
	a.length = 0.5
	a.loop_mode = Animation.LOOP_LINEAR
	_add_pos_track(a, "Hips",     [[0.0, Vector3(0.0, -0.12, 0.0)]])
	_add_rot_track(a, "LUpperLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 90.0))]])
	_add_rot_track(a, "RUpperLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 90.0))]])
	_add_rot_track(a, "LLowerLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))]])
	_add_rot_track(a, "RLowerLeg",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-90.0))]])
	_add_rot_track(a, "LUpperArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 30.0))]])
	_add_rot_track(a, "RUpperArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad( 30.0))]])
	_add_rot_track(a, "LLowerArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-60.0))]])
	_add_rot_track(a, "RLowerArm",[[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(-60.0))]])
	_add_rot_track(a, "Spine",    [[0.0, Quaternion(Vector3.RIGHT, deg_to_rad(  8.0))]])
	return a
