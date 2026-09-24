class_name BeltBuilder
extends RefCounted

## Single entry point for every conveyor belt placeable. Collapses _m_belt,
## _m_intake_belt, _m_switch_belt, _m_compactor_belt, _m_compactorband,
## _m_inclined_belt, _m_metal_belt, _m_scraper_conveyor, _m_variable_belt,
## and _build_opzetband into one dict-driven dispatch over a BeltSpec dict
## (see make_spec() for the schema).
##
## `p`     — the PhysicsBody3D (or Node3D for opzetband early-return) whose
##           Model child receives the visual. For internal_builder_path specs
##           (opzetband family) we instantiate the script-backed scene and
##           return that instead.
## `id`    — the placeable id (also written to meta('placeable_id') in
##           non-ghost mode so K-edit / delete / save-load find this belt).
## `size`  — catalog size in metres (may be overridden by length_override_m or
##           two_click_endpoints).
## `spec`  — a BeltSpec dict (see make_spec()). The dispatch reads every field
##           via dict.get() with the same defaults, so callers can pass a
##           partial spec and only set what differs from the defaults.
## `ghost` — true → translucent preview, NO physics tagging, NO scripts.
##
## Returns the node that should be returned from PlaceableCatalog.build_node()
## (usually `p` itself; for internal_builder_path specs it returns the
## instantiated script-backed root e.g. ShredderFeedBelt).
##
## Tagging contract (non-ghost only): the returned node ends up with
##   meta('placeable_id') = id
##   group 'placed_object'
##   group 'belt'                (if spec.tag_as_belt)
##   meta('belt_speed')          (if spec.tag_as_belt)
##   set_script(BeltSurface)     (if spec.tag_as_belt and node is StaticBody3D)
##   member 'belt_speed_mps'     (if BeltSurface script attached)
##
## Carry direction is ALWAYS +basis.z (BeltSurface convention; matches
## PlayerController._apply_belt_carry). The discharge chute is built at local
## +Z (see build_chute), the shader scrolls toward +Z on positive speed, and
## BuildMode._build_full_line places each macro body with rot_y + PI so its
## local +Z points DOWNSTREAM along the macro march. New belts MUST yaw their
## physical body so local +Z points downstream. carry_axis = 'minus_basis_z'
## is reserved for legacy migration paths only.

# ── Imports / prefab constants ─────────────────────────────────────────────────
const _BELT_SURFACE_PATH : String = "res://src/sim/BeltSurface.gd"
const _FILM_FIELD_SCRIPT := preload("res://src/sim/FilmFlakeField.gd")

# P1 (2026-09-23) — bulk densities the film BED on a belt derives its depth
# from (kg/m ÷ (density × bed width), see FilmFlakeField.set_belt_state). Two
# stated assumptions, visual-only (never a conservation quantity):
#   SNIPPER — freshly shredded film, fluffy: ~60 kg/m³. A 7 cm shred of 50 µm
#             film weighs ~0.2 g; loose shreds pack at a few percent of solid
#             LDPE's 920 kg/m³.
#   FLAKE   — washed, dried flake on the compactorband: 90 kg/m³. Derived from
#             two operator statements (2026-09-23): the deck creeps at ~4 cm/s
#             and the bed is "heaped, 20 cm or more" at production; at 3A/3B's
#             0.61 kg/s that is 15 kg/m, and 15 kg/m over a 0.86 m bed is 20 cm
#             at ~90 kg/m³. Loose dried LDPE flake sits in the 50-150 range;
#             180 (ShredderFeedBelt.OUTPUT_DENSITY, a SETTLED pile) gave 10 cm.
const SNIPPER_BULK_KGM3 : float = 60.0
const FLAKE_BULK_KGM3   : float = 90.0

# Carry speeds (kept in sync with PlaceableCatalog defaults — see _BELT_CARRY_SPEED
# and _INTAKE_BELT_SPEED_MPS there). Duplicated here so BeltBuilder is usable
# without importing PlaceableCatalog state.
const _BELT_CARRY_SPEED : float = 1.0      # operator 2026-09-23: intake 1.5, others ~50 % slower
const _INTAKE_BELT_SPEED_MPS : float = 1.5

# ── Spec defaults ──────────────────────────────────────────────────────────────
## Returns a BeltSpec dict with every key set to its default. Caller pattern:
##   var s := BeltBuilder.make_spec()
##   s.deck_kind = "tilted"
##   s.incline_deg = 5.0
##   ...
##   BeltBuilder.build(body, id, size, s, ghost)
static func make_spec() -> Dictionary:
	return {
		# Deck geometry strategy. See judge spec for the full taxonomy:
		#   'flat' / 'tilted' / 'diagonal' / 'inclined_xz' / 'submerged_trough'
		#   / 'free_span' / 'opzetband' / 'none' (bespoke deck in extras callback)
		"deck_kind": "flat",
		# Pitch about X for deck_kind='tilted'. Positive = +Z end rises.
		"incline_deg": 0.0,
		# Vertical rise for diagonal / inclined_xz decks.
		"rise": 0.0,
		# Horizontal projection length for diagonal / inclined_xz decks.
		"horizontal_run": 0.0,
		# If > 0, ACTUAL conveying length overrides size.z (size.x/y still apply).
		"length_override_m": 0.0,
		# Deck top Y as fraction of size.y (ignored for diagonal/inclined_xz).
		"deck_y_frac": 0.75,
		# Belt-deck width as fraction of size.x.
		"deck_width_frac": 0.82,
		# Literal-metre deck width override (0 = use deck_width_frac).
		"override_deck_width": 0.0,
		# Vertical thickness of the deck box mesh.
		"deck_thickness_m": 0.05,
		# Prefab material for the deck BEFORE make_belt_material overlay.
		#   'DARK' / 'RUBBER' / 'STEEL'.
		"deck_material": "DARK",
		# make_belt_material scroll value. 0.0 = no scrolling (compactor_belt,
		# compactorband, metal_belt, scraper_conveyor — plain dark material).
		"deck_scroll": 0.6,
		# Multiplier on length used as uv_tile.y so slat pitch is constant.
		"deck_uv_tile_y_frac": 0.5,
		# End-roller strategy:
		#   'spinning_cyl' / 'static_cyl' / 'pulley_box' / 'sprocket_rotating' / 'none'
		"rollers": "spinning_cyl",
		# End-roller radius as fraction of size.y (ignored if override > 0).
		"roller_radius_frac": 0.22,
		# Literal-metre roller radius override (0 = use frac).
		"override_roller_radius": 0.0,
		# Side rails:
		#   'steel_simple' / 'painted_accent' / 'safety_mesh' / 'none'
		"side_rails": "steel_simple",
		# Per-belt accent color for side_rails='painted_accent'.
		"rail_color": Color(0.55, 0.55, 0.60),
		# Rail box X-thickness.
		"side_rail_thickness_m": 0.06,
		# Rail height as fraction of size.y.
		"side_rail_height_frac": 0.18,
		# Legs:
		#   true  = call standard _legs(p, size, deck_y, steel)
		#   false = no legs (rely on auto_legs_meta or bespoke/internal builder)
		"has_legs": true,
		# Sets meta('auto_legs') so BuildMode spawns floor-reaching legs as
		# siblings. Only variable_belt today. Mutually exclusive with has_legs.
		"auto_legs_meta": false,
		# Leg style:
		#   'simple' / 'tapered' / 'a_frame_diagonal' / 'i_beam' / 'bespoke_internal'
		"leg_style": "simple",
		# Leg material: 'STEEL' / 'GALV' / 'DARK'.
		"leg_material": "STEEL",
		# Motor:
		#   'none' / 'small_housing' / 'motor_unit_top' / 'motor_unit_head' / 'box_above_head'
		"motor": "none",
		# Local offset (relative to p) where motor is placed. Vector3.ZERO =
		# auto-computed from deck geometry (typical case).
		"motor_pos_local": Vector3.ZERO,
		# 'x' or 'z' — axis flag passed to _motor_unit / _cyl.
		"motor_axis": "x",
		# Chute:
		#   'none' / 'discharge_intake' / 'discharge_lip' / 'scraper_chute' / 'opzetband_internal'
		"chute": "none",
		# Absolute X/Y/Z extents of the chute.
		"chute_size_m": Vector3(0.30, 0.25, 0.30),
		# Composable extras: 'overband_magnet_gantry' / 'safety_mesh_guard' /
		# 'dust_hood_flue' / 'blue_blower_ducts' / 'submerged_trough_water' /
		# 'scraper_flight_bars' / 'catch_pan' / 'switch_belt_chassis' /
		# 'switch_belt_marker_meta'.
		"decorations": [],
		# Escape hatch for one-off per-belt geometry that doesn't justify a
		# decoration token. Each callable: f(p, deck_root, size, spec, ghost).
		"extras": [],
		# RPM for scraper-sprocket RotatingMechanism nodes (and any future
		# rotating-mech belt). Ignored when not used by a decoration.
		"rotating_rpm": 12.0,
		# Switch-belt mode: builds the inner 'Deck' Node3D containing pulleys+
		# skin+rails so SwitchBelt.gd can translate it ±1.5 m along carry axis.
		"sliding_deck": false,
		# Carry speed written to meta('belt_speed') and BeltSurface.belt_speed_mps.
		"belt_speed_mps": _BELT_CARRY_SPEED,
		# Tagging contract:
		#   true  = add 'belt' group, set 'belt_speed' meta, attach BeltSurface.
		#   false = no belt tagging (compactor_belt; static visual).
		"tag_as_belt": true,
		# Direction convention. '+basis.z' = match BeltSurface + PlayerController.
		# 'minus_basis_z' is reserved for variable_belt's legacy convention; new
		# belts MUST use '+basis.z'.
		"carry_axis": "+basis.z",
		# Extra groups added to body. Empty for current belts.
		"tag_extra_groups": [],
		# Free-form meta map written verbatim. Captures e.g. switch_belt's
		# {'switch_belt': true} and variable_belt's {'vb_start': ..., 'vb_end': ...}.
		"extra_metas": {},
		# Optional [Vector3 start, Vector3 end] for 2-click placeables. When
		# present, BeltBuilder rotates the body so the carry axis points
		# end-start, sets length_override_m = distance, writes vb_start / vb_end
		# metas. Empty = single-click placement.
		"two_click_endpoints": [],
		# If non-empty, BeltBuilder loads this script, instantiates it, applies
		# internal_overrides via set(), and returns the instance instead of
		# building from primitives. opzetband family uses this.
		"internal_builder_path": "",
		# Per-id payload passed verbatim to internal_builder_path instance via
		# set(key, value).
		"internal_overrides": {},
		# P1 — seat a FilmFlakeField (belt mode) on the deck skin. A belt that
		# builds its own deck in `extras` (deck_kind 'none') seats the field
		# itself with attach_film_field(); the flag is then moot.
		"film_field": true,
		# Bulk density the field derives its bed depth from — SNIPPER_BULK_KGM3
		# for shredded film, FLAKE_BULK_KGM3 for washed flake.
		"bed_bulk_density": FLAKE_BULK_KGM3,
	}

# ── Public entry point ─────────────────────────────────────────────────────────
## Build a belt visual under `p` according to `spec`. See class docstring.
static func build(p: Node3D, id: String, size: Vector3, spec: Dictionary, ghost: bool) -> Node3D:
	# 1) internal_builder_path early-return (opzetband family + any future
	#    PackedScene-backed belt). Skip every primitive build step; the script
	#    instance builds its own model. Still goes through tag_only() so the
	#    tagging contract is identical to the primitive path.
	var sub_path : String = String(spec.get("internal_builder_path", ""))
	if sub_path != "":
		if ghost:
			return _simple_ghost(size)
		var script_res : Resource = load(sub_path)
		if script_res == null:
			push_warning("[BeltBuilder] internal_builder_path missing: %s" % sub_path)
			return null
		var sub : Node = script_res.new()
		if not sub is Node3D:
			push_warning("[BeltBuilder] internal_builder_path %s did not produce Node3D" % sub_path)
			return null
		var sub3d : Node3D = sub as Node3D
		var overrides : Dictionary = spec.get("internal_overrides", {})
		for k in overrides.keys():
			sub3d.set(String(k), overrides[k])
		tag_only(sub3d, id, spec, ghost)
		return sub3d

	# 2) Two-click placement: rotate `p` so the carry axis (+basis.z) points
	#    from start → end, write vb_start / vb_end metas, override length.
	var endpoints : Array = spec.get("two_click_endpoints", [])
	if endpoints.size() == 2:
		var start_pos : Vector3 = endpoints[0]
		var end_pos : Vector3 = endpoints[1]
		var diff : Vector3 = end_pos - start_pos
		var length : float = diff.length()
		if length < 0.5:
			return null
		spec["length_override_m"] = length
		spec["extra_metas"] = _merge_dict(spec.get("extra_metas", {}),
			{"vb_start": start_pos, "vb_end": end_pos})
		# Position + orient the body so its conveying axis lines up with the
		# diff vector. Convention: local +Z points from start → end (matches
		# BeltSurface and PlayerController._apply_belt_carry).
		var fwd_xz : Vector3 = Vector3(diff.x, 0.0, diff.z)
		var horiz_len : float = fwd_xz.length()
		var yaw : float = atan2(diff.x, diff.z) if horiz_len > 0.01 else 0.0
		var pitch : float = 0.0 if horiz_len < 0.01 else atan2(diff.y, horiz_len)
		p.position = start_pos
		p.rotation = Vector3(pitch, yaw, 0.0)

	# 3) Build the model under `p`. build_internal returns the model parent so
	#    callers / extras can reach the deck root if they need to.
	build_internal(p, id, size, spec, ghost)

	# 4) Apply tagging contract (groups, metas, BeltSurface script).
	apply_tagging(p, spec, ghost)
	# Always set placeable_id regardless of tag_as_belt — K-edit / save-load
	# need it on every placed object, belt or not.
	if not ghost:
		p.set_meta("placeable_id", id)
		if not p.is_in_group("placed_object"):
			p.add_to_group("placed_object")
	return p

# ── Component builders (public so future exotic belts can compose a la carte) ──

## Build the full belt primitive geometry under `p` (deck + rollers + rails +
## motor + chute + decorations + extras). Does NOT tag the body — call
## apply_tagging() separately, or use the top-level build() which does both.
static func build_internal(p: Node3D, _id: String, size: Vector3, spec: Dictionary, ghost: bool) -> Node3D:
	# Resolve effective conveying length (size.z, override, or 2-click distance).
	var conv_len : float = float(spec.get("length_override_m", 0.0))
	if conv_len <= 0.0:
		conv_len = size.z
	var eff_size := Vector3(size.x, size.y, conv_len)

	# Legs sit on the static frame (rotated 0 for tilted decks).
	if bool(spec.get("has_legs", true)):
		build_legs(p, eff_size, eff_size.y * float(spec.get("deck_y_frac", 0.75)), spec, ghost)

	# Deck parent — for 'tilted' deck_kind this is a rotated Node3D, for 'flat'
	# it's `p` itself. Rollers + rails + deck-skin all parent under it so they
	# inherit the tilt.
	var deck_parent : Node3D = build_deck(p, eff_size, spec, ghost)
	var deck_y : float = _deck_top_y(spec, eff_size)
	build_rollers(deck_parent, eff_size, deck_y, spec, ghost)
	# #214 — Belt loop closure: bottom return strip + cylindrical wraps around
	# each end roller, so the deck reads as a continuous LOOP instead of a top
	# plate floating between two pulleys. Must run AFTER build_rollers (needs
	# the same roller_y / hz / r values) and BEFORE rails (so rails sit on top).
	build_belt_loop(deck_parent, eff_size, deck_y, spec, ghost)
	build_rails(deck_parent, eff_size, deck_y, spec, ghost)
	build_motor(p, eff_size, deck_y, spec, ghost)
	build_chute(p, eff_size, deck_y, spec, ghost)
	apply_decorations(p, eff_size, spec, ghost)

	# Run any per-id one-off extras LAST so they can override / add geometry.
	var extras : Array = spec.get("extras", [])
	for cb in extras:
		if cb is Callable:
			(cb as Callable).call(p, deck_parent, eff_size, spec, ghost)
	return deck_parent

## Build the belt deck (scrolling textured box + parent Node3D for the rest of
## the moving assembly). Returns the deck parent — for 'flat' deck_kind it's
## `p` itself; for 'tilted' it's a rotated child; for 'sliding_deck' it's the
## inner 'Deck' Node3D. Caller parents rollers / rails / deck_skin under it.
static func build_deck(p: Node3D, size: Vector3, spec: Dictionary, ghost: bool) -> Node3D:
	var deck_kind : String = String(spec.get("deck_kind", "flat"))
	var deck_y : float = _deck_top_y(spec, size)
	var deck_w : float = float(spec.get("override_deck_width", 0.0))
	if deck_w <= 0.0:
		deck_w = size.x * float(spec.get("deck_width_frac", 0.82))
	var deck_t : float = float(spec.get("deck_thickness_m", 0.05))
	var dark : StandardMaterial3D = _resolve_mat(String(spec.get("deck_material", "DARK")), ghost)
	# A spec that zeroes the deck width or thickness (inclined_belt_8m: its extras
	# build the real diagonal deck) wants NO skin here. It used to get a
	# zero-volume box anyway; since the film field seats on the skin (P1), that
	# box would also have carried a second, degenerate field.
	var degenerate : bool = deck_w <= 0.01 or deck_t <= 0.0

	# Build (or reuse) the deck PARENT — what subsequent rollers/rails attach to.
	var deck_parent : Node3D = p
	# deck_kind='none' = caller builds the deck themselves (in extras / bespoke
	# legacy geometry). Skip the standard deck_skin box entirely; deck_parent
	# stays as `p` so any subsequent rollers/rails (if not 'none') still attach.
	if deck_kind == "none" or degenerate:
		return deck_parent
	if bool(spec.get("sliding_deck", false)):
		# switch_belt: inner 'Deck' Node3D that SwitchBelt.gd translates ±1.5 m.
		deck_parent = Node3D.new()
		deck_parent.name = "Deck"
		p.add_child(deck_parent)
	elif deck_kind == "tilted":
		# Tilted deck: rotated child carries everything that should tilt together.
		# Sign convention: positive incline_deg → +Z end rises (matches _m_intake_belt).
		var pivot := Node3D.new()
		pivot.name = "DeckPivot"
		pivot.position = Vector3(0.0, deck_y, 0.0)
		pivot.rotation = Vector3(-deg_to_rad(float(spec.get("incline_deg", 0.0))), 0.0, 0.0)
		p.add_child(pivot)
		deck_parent = pivot

	# Deck SKIN — the actual textured box. Position depends on whether the deck
	# parent IS the rotated DeckPivot (skin sits relative to pivot origin which
	# already moved to deck_y) or some other parent (skin sits in absolute
	# local space). The 'Deck' sliding-deck root sits at world origin, so its
	# children use absolute deck_y like the flat path.
	var skin_y : float
	if deck_parent.name == "DeckPivot":
		# tilted: pivot is already at deck_y; skin sits at +0.22 * size.y above it.
		skin_y = size.y * 0.22
	elif deck_parent.name == "Deck":
		# sliding-deck switch_belt: 'Deck' root sits at world origin; legacy
		# _m_switch_belt places its deck_skin at deck_y + size.y * 0.20.
		skin_y = deck_y + size.y * 0.20
	else:
		# flat (_m_belt parity): deck_y + size.y * 0.22.
		skin_y = deck_y + size.y * 0.22
	var deck_skin : MeshInstance3D = _box(deck_parent, Vector3(deck_w, deck_t, size.z * 0.9),
		Vector3(0.0, skin_y, 0.0), dark)
	deck_skin.name = "DeckSkin"   # named for every kind: the film field is seated on it (P1)
	# Scrolling material overlay — only when deck_scroll != 0 (compactor_belt
	# etc. stay plain dark).
	var scroll : float = float(spec.get("deck_scroll", 0.6))
	if not ghost and abs(scroll) > 0.0001:
		var uv_y_frac : float = float(spec.get("deck_uv_tile_y_frac", 0.5))
		deck_skin.material_override = _make_belt_material(scroll,
			Vector2(1.0, size.z * uv_y_frac))
	# P1 (2026-09-23) — the film bed. One field per deck, on the skin's top face,
	# spanning it; LineFlow drives it (set_belt_state) from what the node moves.
	if not ghost and bool(spec.get("film_field", true)):
		attach_film_field(deck_parent, deck_w, size.z * 0.9, skin_y + deck_t * 0.5,
			float(spec.get("belt_speed_mps", _BELT_CARRY_SPEED)),
			float(spec.get("bed_bulk_density", FLAKE_BULK_KGM3)))
	return deck_parent

## Seat a belt-mode FilmFlakeField on a deck. `parent` is the node whose local
## +Z runs DOWNSTREAM along the deck and whose local +Y is the deck's normal
## (BeltBuilder's deck parent, or a bespoke frame the caller rotates the same
## way); `top_y` is the deck skin's top face in that frame. The field spans
## 92 % of the deck width and the given length, with a flake budget of ~120 per
## m² of bed (120..1500 — one MultiMesh draw and no per-flake CPU work). Public so
## belts that build their own deck (compactorband, inclined_belt_8m) use the
## same seat. Returns the field.
static func attach_film_field(parent: Node3D, deck_w: float, deck_len: float, top_y: float,
		speed_mps: float, bulk_density: float) -> Node3D:
	var field : Node3D = _FILM_FIELD_SCRIPT.new()
	field.name = "FilmField"
	var w : float = deck_w * 0.92
	field.set("area", Vector2(w, deck_len))
	field.set("surface_y", top_y + 0.005)
	field.set("flake_size", 0.07)
	field.set("flake_count", clampi(int(round(w * deck_len * 120.0)), 120, 1500))   # GPU-scrolled: ~120 per m²
	field.set("flow_speed", speed_mps)
	field.set("bed_bulk_density", bulk_density)
	field.call("set_belt_mode", true)
	# LineFlow._belt_speed_of reads this when the machine body carries no
	# belt_speed of its own (the wet-side beds of task 1c: sieve deck, goot,
	# screw trough, bunker deck, doseersilo bottom).
	field.set_meta("bed_speed_mps", speed_mps)
	parent.add_child(field)
	return field

## Standard 4-leg support frame. Legs are tagged 'machine_leg' + meta('leg_h')
## so extend_machine_legs() can stretch them to the floor when the body is
## raised. leg_style 'simple' is the only kind handled here; exotic leg
## families (a-frame, i-beam, tapered) are decoration-token concerns and live
## under apply_decorations or in the per-id legacy builder.
static func build_legs(p: Node3D, size: Vector3, deck_y: float, spec: Dictionary, ghost: bool) -> void:
	var leg_style : String = String(spec.get("leg_style", "simple"))
	if leg_style != "simple":
		# Non-standard leg families are handled by extras / decorations.
		return
	var leg_mat : StandardMaterial3D = _resolve_mat(String(spec.get("leg_material", "STEEL")), ghost)
	var hx : float = size.x * 0.42
	var hz : float = size.z * 0.42
	var signs : Array[float] = [-1.0, 1.0]
	for sx in signs:
		for sz in signs:
			var lg := _box(p, Vector3(0.08, deck_y, 0.08),
				Vector3(sx * hx, deck_y * 0.5, sz * hz), leg_mat)
			lg.add_to_group("machine_leg")
			lg.set_meta("leg_h", deck_y)

## End rollers — `rollers` field selects the strategy. `deck_parent` is the
## Node3D the rollers attach to (usually the rotated DeckPivot for tilted decks
## or `p` itself for flat decks).
static func build_rollers(deck_parent: Node3D, size: Vector3, deck_y: float, spec: Dictionary, ghost: bool) -> void:
	var kind : String = String(spec.get("rollers", "spinning_cyl"))
	if kind == "none":
		return
	var dark : StandardMaterial3D = _resolve_mat("DARK", ghost)
	# #214 — Striped roller material. Plain dark rollers had no visible texture
	# so spin was invisible at any real-game distance. The stripe material wraps
	# 6 dark/light radial bands around the cylinder (CylinderMesh wraps U around
	# its circumference), giving an unmistakable "spinning wheel" read even at
	# 20+ m. Used on spinning_cyl and static_cyl (a static rail roller still
	# benefits from looking like a real roller, not a plain shaft).
	var stripe : StandardMaterial3D = _roller_stripe_mat(ghost)
	# Roller radius (literal override or fraction of size.y).
	var r : float = float(spec.get("override_roller_radius", 0.0))
	if r <= 0.0:
		r = size.y * float(spec.get("roller_radius_frac", 0.22))
	# Local Y for the rollers — when deck_parent is the rotated 'DeckPivot',
	# the pivot is already at deck_y so rollers sit at y=0. Otherwise (flat
	# `p`, or the sliding 'Deck' root which sits at world origin), rollers
	# sit at deck_y in absolute local space.
	var roller_y : float
	if deck_parent.name == "DeckPivot":
		roller_y = 0.0
	else:
		roller_y = deck_y
	var hz : float = size.z * 0.45
	# Roller length must match the deck width — operator complaint: rollers
	# stuck out past the belt edges with the old `size.x * 0.9` (90 cm rollers
	# on an 82 cm deck). Now they align exactly.
	var deck_w_for_roller : float = float(spec.get("override_deck_width", 0.0))
	if deck_w_for_roller <= 0.0:
		deck_w_for_roller = size.x * float(spec.get("deck_width_frac", 0.82))
	var roller_len : float = deck_w_for_roller
	var carry_speed : float = float(spec.get("belt_speed_mps", _BELT_CARRY_SPEED))
	# rpm so that omega = v / r — visible roller surface tracks the belt speed.
	var rpm : float = 0.0 if r <= 0.0 else (carry_speed * 60.0) / (TAU * r)

	if kind == "spinning_cyl":
		_spinning_cyl(deck_parent, r, r, roller_len, Vector3(0.0, roller_y,  hz),
			stripe, "x", Vector3.RIGHT, ghost, rpm)
		_spinning_cyl(deck_parent, r, r, roller_len, Vector3(0.0, roller_y, -hz),
			stripe, "x", Vector3.RIGHT, ghost, rpm)
	elif kind == "static_cyl":
		_cyl(deck_parent, r, r, roller_len, Vector3(0.0, roller_y,  hz), stripe, "x")
		_cyl(deck_parent, r, r, roller_len, Vector3(0.0, roller_y, -hz), stripe, "x")
	elif kind == "pulley_box":
		# compactor_belt-style: extruded box pulleys instead of round cylinders.
		var box_w : float = size.x * 0.9
		_box(deck_parent, Vector3(box_w, r * 2.0, r * 2.0),
			Vector3(0.0, roller_y,  hz), dark)
		_box(deck_parent, Vector3(box_w, r * 2.0, r * 2.0),
			Vector3(0.0, roller_y, -hz), dark)
	# 'sprocket_rotating' is consumed by the 'scraper_flight_bars' decoration
	# (RotatingMechanism sprockets); rollers='none' covers belts that have
	# their drums built bespoke.

## #214 — Close the belt visually as a continuous LOOP. Adds (a) a bottom
## return strip of belt material directly under the deck, scrolling in the
## OPPOSITE direction to the top deck (because in a real conveyor the underside
## of the loop moves backward relative to the carry direction), and (b) a thin
## cylindrical "shell" wrapping each end roller at radius r + small margin so
## you can see the belt going UNDER and AROUND each pulley instead of the belt
## just disappearing into the roller. The shell uses the SAME scrolling belt
## material so its surface scrolls visually consistent with the deck.
##
## Skipped (no-op) when:
##  • rollers in {'none', 'pulley_box', 'sprocket_rotating'} — those families
##    are bespoke (no end rollers OR no round drum to wrap).
##  • deck_kind in {'none', 'submerged_trough', 'free_span', 'diagonal',
##    'inclined_xz', 'opzetband'} — non-standard deck geometries the loop
##    closure shouldn't second-guess.
##  • spec.deck_scroll == 0 (no-belt visual; compactor band, scraper, etc.).
##  • ghost — skip extra geometry for placement previews.
static func build_belt_loop(deck_parent: Node3D, size: Vector3, deck_y: float, spec: Dictionary, ghost: bool) -> void:
	if ghost:
		return
	var rollers_kind : String = String(spec.get("rollers", "spinning_cyl"))
	if rollers_kind == "none" or rollers_kind == "pulley_box" or rollers_kind == "sprocket_rotating":
		return
	var deck_kind : String = String(spec.get("deck_kind", "flat"))
	# Only the standard flat / tilted deck flavours have a clean two-pulley
	# top+bottom run geometry we can mirror under here. Submerged_trough has
	# its trough form, opzetband + free_span / inclined_xz / diagonal are
	# bespoke; closing the loop on those would punch through walls / decks.
	if deck_kind != "flat" and deck_kind != "tilted":
		return
	var scroll : float = float(spec.get("deck_scroll", 0.6))
	if abs(scroll) < 0.0001:
		return
	# Resolve dimensions — same formulas build_rollers + build_deck use, so
	# the wrap aligns to the rollers / deck pixel-for-pixel.
	var r : float = float(spec.get("override_roller_radius", 0.0))
	if r <= 0.0:
		r = size.y * float(spec.get("roller_radius_frac", 0.22))
	var deck_w : float = float(spec.get("override_deck_width", 0.0))
	if deck_w <= 0.0:
		deck_w = size.x * float(spec.get("deck_width_frac", 0.82))
	var deck_t : float = float(spec.get("deck_thickness_m", 0.05))
	var hz : float = size.z * 0.45                         # roller +/- Z offset
	# Roller Y in deck_parent local space — same logic as build_rollers.
	var roller_y : float
	if deck_parent.name == "DeckPivot":
		roller_y = 0.0
	else:
		roller_y = deck_y
	# 1) BOTTOM RETURN STRIP — mirror of the top deck box, sitting just under
	# the rollers. Same width, same length, same belt material, but its
	# scrolling direction is REVERSED so the under-run visually moves opposite
	# to the top — exactly how a real belt loop behaves. Slightly inset between
	# the rollers (length = size.z * 0.9 same as top) and pushed `deck_t` below
	# the roller bottom so it reads as a separate run with a visible gap.
	var bottom_y : float = roller_y - r - deck_t * 0.5 - 0.005
	var bottom_skin : MeshInstance3D = _box(deck_parent,
		Vector3(deck_w, deck_t, size.z * 0.9),
		Vector3(0.0, bottom_y, 0.0),
		_resolve_mat(String(spec.get("deck_material", "DARK")), ghost))
	var uv_y_frac : float = float(spec.get("deck_uv_tile_y_frac", 0.5))
	# Reversed scroll: the bottom of a loop moves backward relative to the top.
	bottom_skin.material_override = _make_belt_material(-scroll,
		Vector2(1.0, size.z * uv_y_frac))
	# 2) ROLLER WRAPS — thin cylindrical shells, radius r + margin, length =
	# slightly wider than the rollers (covers the belt edge over the drum).
	# The cylinder's circumferential UV makes the belt slat texture appear to
	# wrap around the drum, completing the closed loop the operator wants to
	# see. Static (not parented under a RotatingMechanism) so the slat pattern
	# doesn't double-rotate vs the underlying drum.
	var wrap_r : float = r + deck_t * 0.5 + 0.006          # margin over drum
	# Wrap length tracks deck width so the belt visibly meets the deck edge with
	# no gap, but pulls back ~10% on each axial side so the striped roller ends
	# still peek out and the operator can read the spin. Was size.x * 0.62 which
	# left the wrap visibly NARROWER than the deck — looked like a small belt
	# over wide rollers. deck_w_for_roller is recomputed here (different scope
	# from build_rollers): same formula so both functions resolve identically.
	var deck_w_for_roller : float = float(spec.get("override_deck_width", 0.0))
	if deck_w_for_roller <= 0.0:
		deck_w_for_roller = size.x * float(spec.get("deck_width_frac", 0.82))
	var wrap_len : float = deck_w_for_roller * 0.80
	# Belt material tile.y for a wrap is the circumference / texture height
	# (2πr ≈ slat_period) so the slat pitch matches the deck — a single drum
	# turn carries the same slat count as the equivalent length of top deck.
	var wrap_tile : Vector2 = Vector2(1.0, max(2.0 * PI * wrap_r * uv_y_frac, 0.5))
	# Both wraps scroll IN THE SAME +scroll direction — the belt is one
	# continuous loop, so the top of EVERY drum carries downstream. Operator
	# complaint: the previous `scroll * sz_sign` made the tail drum visually
	# run backward, breaking the continuous-loop illusion.
	for sz_sign in [1.0, -1.0]:
		var wrap : MeshInstance3D = _cyl(deck_parent, wrap_r, wrap_r, wrap_len,
			Vector3(0.0, roller_y, float(sz_sign) * hz),
			_resolve_mat(String(spec.get("deck_material", "DARK")), ghost),
			"x")
		wrap.material_override = _make_belt_material(scroll, wrap_tile)

## Side rails. Strategy selected by `side_rails`. For 'painted_accent' the
## rail color comes from spec.rail_color; for everything else a generic _STEEL
## material is used.
static func build_rails(deck_parent: Node3D, size: Vector3, deck_y: float, spec: Dictionary, ghost: bool) -> void:
	var kind : String = String(spec.get("side_rails", "steel_simple"))
	if kind == "none":
		return
	var color : Color
	if kind == "painted_accent":
		color = spec.get("rail_color", Color(0.55, 0.55, 0.60))
	elif kind == "safety_mesh":
		# Yellow wire-mesh guard handled by the decoration token; bail out here.
		return
	else:
		color = Color(0.60, 0.63, 0.67)   # _STEEL constant duplicated
	var mat : StandardMaterial3D = _mat(color, ghost, 0.5, 0.45)
	var rail_t : float = float(spec.get("side_rail_thickness_m", 0.06))
	var rail_h : float = size.y * float(spec.get("side_rail_height_frac", 0.18))
	# Rail Y — same logic as rollers: DeckPivot is already at deck_y so rails
	# sit at `side_rail_y_frac` * size.y relative; the sliding 'Deck' root and a
	# flat `p` both sit at world origin so rails sit at deck_y + that absolute.
	#
	# This was the bare literal 0.28 until 2026-09-17. Paired with the default
	# 0.18 height it puts a rail's TOP 0.333 * size.y above the deck and its
	# BOTTOM floating 0.171 * size.y clear of it — fine for a deep trough belt,
	# impossible for line 1's uitvoerband, which has to pass under an overband
	# magnet at a 0.25 m working clearance: the rails alone stood 0.333 m proud
	# of the deck, taller than the clearance itself. Promoted to a spec key so
	# that ONE belt can carry a skirt-board profile without moving every belt
	# built from the defaults.
	var rail_frac : float = float(spec.get("side_rail_y_frac", 0.28))
	var rail_y : float
	if deck_parent.name == "DeckPivot":
		rail_y = size.y * rail_frac
	else:
		rail_y = deck_y + size.y * rail_frac
	# Rail X-offset — outside the deck width.
	var rail_x : float = size.x * 0.44
	if deck_parent.name == "Deck":
		rail_x = size.x * 0.46   # switch_belt uses slightly wider rails on the inner deck
	_box(deck_parent, Vector3(rail_t, rail_h, size.z * 0.95),
		Vector3( rail_x, rail_y, 0.0), mat)
	_box(deck_parent, Vector3(rail_t, rail_h, size.z * 0.95),
		Vector3(-rail_x, rail_y, 0.0), mat)

## Motor housing / unit. `motor` strategy selects the geometry; 'none' is a
## no-op. The motor parents under `p` (NOT the deck pivot) so it stays at the
## fixed end of the belt regardless of any deck tilt.
static func build_motor(p: Node3D, size: Vector3, deck_y: float, spec: Dictionary, ghost: bool) -> void:
	var kind : String = String(spec.get("motor", "none"))
	if kind == "none":
		return
	var pos : Vector3 = spec.get("motor_pos_local", Vector3.ZERO)
	var axis : String = String(spec.get("motor_axis", "x"))
	var steel : StandardMaterial3D = _resolve_mat("STEEL", ghost)
	if kind == "small_housing":
		# Intake-belt style: small steel box near the upstream end.
		if pos == Vector3.ZERO:
			pos = Vector3(size.x * 0.55, deck_y + size.y * 0.10, -size.z * 0.27)
		_box(p, Vector3(size.x * 0.20, size.y * 0.30, size.x * 0.25), pos, steel)
	elif kind == "motor_unit_top" or kind == "motor_unit_head":
		# TEFC motor mounted at the top / head pulley end.
		if pos == Vector3.ZERO:
			var sign_z : float = 1.0 if kind == "motor_unit_head" else -1.0
			pos = Vector3(size.x * 0.50, deck_y + 0.06, sign_z * (size.z * 0.45 - 0.20))
		_motor_unit(p, 0.14, 0.30, pos, axis, ghost)
	elif kind == "box_above_head":
		# compactor_belt: large box above the head pulley, no spinning unit.
		if pos == Vector3.ZERO:
			pos = Vector3(0.0, deck_y + size.y * 0.30, size.z * 0.40)
		_box(p, Vector3(size.x * 0.40, size.y * 0.20, size.z * 0.18), pos, steel)
		# Yellow trim under the box so the head end reads.
		var yellow : StandardMaterial3D = _mat(Color(0.94, 0.78, 0.14), ghost, 0.2, 0.6)
		_box(p, Vector3(size.x * 0.45, 0.03, size.z * 0.04),
			pos + Vector3(0.0, -size.y * 0.12, 0.0), yellow)

## Discharge chute. Strategy selected by `chute`. For 'discharge_intake' the
## chute is parented under `p` (NOT a deck pivot) so it hangs vertically when
## the deck is tilted.
static func build_chute(p: Node3D, size: Vector3, deck_y: float, spec: Dictionary, ghost: bool) -> void:
	var kind : String = String(spec.get("chute", "none"))
	if kind == "none" or kind == "opzetband_internal":
		# 'opzetband_internal' is built inside the internal_builder_path script.
		return
	var csz : Vector3 = spec.get("chute_size_m", Vector3(0.30, 0.25, 0.30))
	var steel : StandardMaterial3D = _resolve_mat("STEEL", ghost)
	if kind == "discharge_intake":
		# 4 thin walls forming a +Z-end downspout. Top and bottom open so material
		# drops through. Sized from chute_size_m; thin wall thickness = 0.015 m.
		var chute_t : float = 0.015
		var outlet_z : float = size.z * 0.50
		# Account for the tilt of the deck so the chute top sits just below the
		# pulley level (deck end y rises by hz * sin(incline) for tilted decks).
		var hz : float = size.z * 0.45
		var incline_rad : float = deg_to_rad(float(spec.get("incline_deg", 0.0)))
		var outlet_y_off : float = hz * sin(incline_rad)
		var chute_top_y : float = deck_y + outlet_y_off + size.y * 0.22 - 0.04
		var chute_cy : float = chute_top_y - csz.y * 0.5
		for sx in [-1.0, 1.0]:
			_box(p, Vector3(chute_t, csz.y, csz.z),
				Vector3(float(sx) * csz.x * 0.5, chute_cy, outlet_z), steel)
		for sz_off in [-1.0, 1.0]:
			_box(p, Vector3(csz.x + chute_t * 2.0, csz.y, chute_t),
				Vector3(0.0, chute_cy, outlet_z + float(sz_off) * csz.z * 0.5), steel)
	elif kind == "discharge_lip":
		# compactorband: a single lip box at the +Z (head) end.
		_box(p, Vector3(csz.x, csz.y * 0.5, csz.z * 0.4),
			Vector3(0.0, deck_y + size.y * 0.30, size.z * 0.45), steel)

## Compose-extra decorations dispatched by token. Unknown tokens are silently
## ignored (they may be handled by a future BeltBuilder revision).
static func apply_decorations(p: Node3D, _size: Vector3, spec: Dictionary, ghost: bool) -> void:
	var decorations : Array = spec.get("decorations", [])
	for tok_raw in decorations:
		var tok : String = String(tok_raw)
		if tok == "switch_belt_marker_meta":
			if not ghost:
				p.set_meta("switch_belt", true)
		# Other decoration tokens are stubs for the migration steps that
		# follow this PR — adding them here would be premature without each
		# belt's pixel-for-pixel review. Migration order keeps the legacy
		# builders intact until each token is verified.

## Apply the tagging contract — groups, metas, BeltSurface script. Called by
## build(); also callable a la carte (tag_only) when a caller built the
## geometry themselves but wants the standard tagging.
static func apply_tagging(p: Node3D, spec: Dictionary, ghost: bool) -> void:
	if ghost:
		return
	# Extra groups first so 'belt' membership stays the last addition.
	var extra_groups : Array = spec.get("tag_extra_groups", [])
	for g in extra_groups:
		var gs : String = String(g)
		if not p.is_in_group(gs):
			p.add_to_group(gs)
	# Free-form metas verbatim.
	var metas : Dictionary = spec.get("extra_metas", {})
	for k in metas.keys():
		p.set_meta(String(k), metas[k])
	# Belt-specific tagging.
	if not bool(spec.get("tag_as_belt", true)):
		return
	if not p.is_in_group("belt"):
		p.add_to_group("belt")
	var speed : float = float(spec.get("belt_speed_mps", _BELT_CARRY_SPEED))
	p.set_meta("belt_speed", speed)
	# Audit item 6 — belt-to-belt projectile receiver zones. Every belt is a
	# potential receiver for an upstream belt's discharge: the calibrated aim
	# point lands inside a SAFE_ZONE of ±0.15 m along local Z (no jitter),
	# surrounded by a SPREAD_ZONE of ±0.30 m where dropped material may scatter
	# (normal distribution, see BeltSurface.compute_belt_to_belt_landing).
	# These metas let the projectile helper read the bands at runtime; specs
	# can override them via `safe_zone_m` / `spread_zone_m` for belts with
	# bespoke geometry (e.g. switch-belt where the spread is wider).
	p.set_meta("safe_zone_m",   float(spec.get("safe_zone_m",   0.15)))
	p.set_meta("spread_zone_m", float(spec.get("spread_zone_m", 0.30)))
	# BeltSurface script — only meaningful on a StaticBody3D. The script
	# uses +global_transform.basis.z, which is the project's convention
	# (downstream = local +Z, see BeltSurface.gd docstring). The carry_axis
	# field is a future-migration hook; today every consumer is on +basis.z
	# and we hard-fail on anything else to flag the migration.
	if not (p is StaticBody3D):
		return
	var carry_axis : String = String(spec.get("carry_axis", "+basis.z"))
	if carry_axis != "+basis.z":
		# Legacy variable_belt path. Don't attach BeltSurface (its convention
		# would be wrong); rely on legacy carry hack until migration step 7.
		push_warning("[BeltBuilder] %s: carry_axis '%s' bypasses BeltSurface" %
			[String(p.get_meta("placeable_id", "?")), carry_axis])
		return
	var belt_script : Resource = load(_BELT_SURFACE_PATH)
	if belt_script == null:
		return
	p.set_script(belt_script)
	p.set("belt_speed_mps", speed)

## Apply ONLY the tagging contract — for callers that built the geometry
## themselves (e.g. internal_builder_path scripts) but want belt physics.
## Idempotent; calling on a tagged body is a no-op.
static func tag_only(p: Node3D, id: String, spec: Dictionary, ghost: bool) -> void:
	if ghost:
		return
	p.set_meta("placeable_id", id)
	if not p.is_in_group("placed_object"):
		p.add_to_group("placed_object")
	apply_tagging(p, spec, ghost)

# ── Internals ──────────────────────────────────────────────────────────────────

## Effective deck top Y (handles diagonal/inclined_xz where rise drives it).
static func _deck_top_y(spec: Dictionary, size: Vector3) -> float:
	var kind : String = String(spec.get("deck_kind", "flat"))
	if kind == "diagonal" or kind == "inclined_xz":
		# Deck rises from 0 at -Z end to `rise` at +Z end; report the midpoint.
		return float(spec.get("rise", 0.0)) * 0.5
	return size.y * float(spec.get("deck_y_frac", 0.75))

## Shallow-merge two dicts; values in `b` win.
static func _merge_dict(a: Dictionary, b: Dictionary) -> Dictionary:
	var out : Dictionary = a.duplicate()
	for k in b.keys():
		out[k] = b[k]
	return out

## Resolve a material token ('DARK' / 'STEEL' / 'RUBBER' / 'GALV') to a real
## StandardMaterial3D. Tokens map to the same constants PlaceableCatalog uses,
## so the visual result matches the legacy builders byte-for-byte.
static func _resolve_mat(token: String, ghost: bool) -> StandardMaterial3D:
	match token:
		"STEEL":
			return _mat(Color(0.60, 0.63, 0.67), ghost, 0.5, 0.45)
		"DARK":
			return _mat(Color(0.24, 0.25, 0.28), ghost, 0.3, 0.7)
		"RUBBER":
			return _mat(Color(0.16, 0.16, 0.17), ghost, 0.1, 0.85)
		"GALV":
			return _mat(Color(0.56, 0.59, 0.63), ghost, 0.6, 0.35)
		_:
			return _mat(Color(0.60, 0.63, 0.67), ghost, 0.5, 0.45)

# ── Primitive shims ────────────────────────────────────────────────────────────
# These wrap PlaceableCatalog's static helpers so BeltBuilder doesn't have to
# import the catalog as a class. Same signature, same behaviour. Done as small
# pass-through statics to keep BeltBuilder self-contained for future tests.

static func _mat(c: Color, ghost: bool, metallic: float = 0.15, rough: float = 0.7) -> StandardMaterial3D:
	return PlaceableCatalog._mat(c, ghost, metallic, rough)

static func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: StandardMaterial3D) -> MeshInstance3D:
	return PlaceableCatalog._box(parent, size, pos, mat)

static func _cyl(parent: Node3D, r_top: float, r_bot: float, height: float,
		pos: Vector3, mat: StandardMaterial3D, axis: String = "y") -> MeshInstance3D:
	return PlaceableCatalog._cyl(parent, r_top, r_bot, height, pos, mat, axis)

static func _spinning_cyl(parent: Node3D, r_top: float, r_bot: float, length: float,
		pos: Vector3, mat: StandardMaterial3D, cyl_axis: String, spin_axis: Vector3,
		ghost: bool, rpm: float = 45.0) -> Node3D:
	return PlaceableCatalog._spinning_cyl(parent, r_top, r_bot, length, pos, mat,
		cyl_axis, spin_axis, ghost, rpm)

static func _motor_unit(parent: Node3D, r: float, length: float, pos: Vector3,
		axis: String, ghost: bool) -> void:
	PlaceableCatalog._motor_unit(parent, r, length, pos, axis, ghost)

static func _make_belt_material(scroll_speed: float, tile: Vector2) -> ShaderMaterial:
	return PlaceableCatalog.make_belt_material(scroll_speed, tile)

## #214 — Cached striped roller material (see PlaceableCatalog.make_roller_stripe_material).
## 6 radial dark/light stripes around the cylinder so spin is visible from any
## distance. Shim mirrors the other PlaceableCatalog helpers for self-containment.
static func _roller_stripe_mat(ghost: bool) -> StandardMaterial3D:
	return PlaceableCatalog.make_roller_stripe_material(ghost)

static func _simple_ghost(size: Vector3) -> Node3D:
	# Translucent box used as a placement preview. Mirrors PlaceableCatalog's
	# private _simple_ghost so BeltBuilder.ghost paths don't reach into the
	# catalog (the helper there is intentionally private).
	var n := Node3D.new()
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = size
	mi.mesh = bm
	mi.position = Vector3(0.0, size.y * 0.5, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.40, 0.80, 1.0, 0.4)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = m
	n.add_child(mi)
	return n
