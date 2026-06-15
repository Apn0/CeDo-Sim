extends StaticBody3D
class_name LabelItem

## A detached label — what you get after RMB-peeling one off a bale or
## container with the barcode scanner. Pick-up with E goes through the same
## Inventory path as scissors/scanner. The held visual is a paper card with a
## printed barcode + text on it. Useful for re-labelling a stripped bale or
## moving a tag from one buffer to another.
##
## DATA: `label_info` is a Dictionary the scanner peeled off the original
## host's "Label" child. We keep the host's name for context. Nothing else
## modifies these — they're a snapshot of what was on the source object at
## the moment of peel.

const tool_id : String = "label"
const PICKUP_RANGE : float = 1.4

var label_info       : Dictionary = {}
var origin_host_name : String = ""

var _held_by     : Node3D = null
var _player_near : bool   = false
var _player_node : Node   = null

# =============================================================================
func _ready() -> void:
	add_to_group("label_item")
	_build_visual()
	_build_pickup_trigger()

func _build_visual() -> void:
	var card := StandardMaterial3D.new()
	card.albedo_color = Color(0.93, 0.82, 0.15)   # yellow shipping label
	card.roughness = 0.85
	# The visible card
	var quad := MeshInstance3D.new()
	var qm := BoxMesh.new(); qm.size = Vector3(0.16, 0.10, 0.005)
	quad.mesh = qm
	quad.material_override = card
	add_child(quad)
	# Barcode stripes — six thin black bars on the card face
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.05, 0.05, 0.05)
	for i in range(6):
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new(); sm.size = Vector3(0.008, 0.05, 0.006)
		stripe.mesh = sm
		stripe.material_override = ink
		stripe.position = Vector3(-0.05 + i * 0.02, 0.005, 0.0)
		add_child(stripe)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new(); bx.size = Vector3(0.18, 0.12, 0.02)
	col.shape = bx
	add_child(col)

func _build_pickup_trigger() -> void:
	var area := Area3D.new()
	area.name = "PickupArea"
	area.collision_mask = 1
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new(); sp.radius = PICKUP_RANGE
	cs.shape = sp
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if _held_by != null:
		return
	if body.name != "Player":
		return
	_player_near = true
	_player_node = body
	_emit_prompt("Take label — %s" % origin_host_name)

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_player_node = null
	_emit_prompt_hide()

func _unhandled_input(event: InputEvent) -> void:
	if _held_by == null:
		if _player_near and event.is_action_pressed("interact"):
			_pick_up(_player_node)
			get_viewport().set_input_as_handled()
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv and not bool(inv.call("is_active", self)):
		return
	if event.is_action_pressed("interact"):
		_drop()
		get_viewport().set_input_as_handled()
		return

func _pick_up(player: Node3D) -> void:
	var inv := get_node_or_null("/root/Inventory")
	# Refuse the grab when the hotbar is full — otherwise take() fails and the
	# item ends up force-parented under Head in no slot, never active, impossible
	# to drop (the stuck state). Leave it in the world, untouched, and tell the
	# player to free a slot first.
	if inv and bool(inv.call("is_full")):
		_emit_prompt("Hands full — drop something first")
		return
	_held_by = player
	var took := false
	if inv:
		took = bool(inv.call("take", self))
	if not took:
		var head := player.get_node_or_null("Head") as Node3D
		var parent_node : Node = head if head != null else player
		get_parent().remove_child(self)
		parent_node.add_child(self)
	# Held: forward-facing card just below the camera.
	transform = Transform3D(Basis(), Vector3(0.16, -0.16, -0.32))
	collision_layer = 0
	collision_mask  = 0
	_emit_prompt_hide()

func _drop() -> void:
	if _held_by == null:
		return
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.call("remove", self)
	var player := _held_by
	var scene_root := get_tree().current_scene
	var drop_world := player.global_transform * Vector3(0.0, -0.5, -0.7)
	get_parent().remove_child(self)
	scene_root.add_child(self)
	global_position = drop_world
	visible = true
	collision_layer = 1
	collision_mask  = 1
	_held_by = null

func _emit_prompt(text: String) -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_show"):
		bus.emit_signal("interaction_prompt_show", self, text)

func _emit_prompt_hide() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("interaction_prompt_hide"):
		bus.emit_signal("interaction_prompt_hide", self)

# =============================================================================
# STATIC HELPER — build a stuck-on label visual for a host node. Used by
# PlaceableCatalog for bales/containers; the scanner reads its `label_info`
# meta. Re-usable for any other entity that wants a peelable tag later.
# =============================================================================
## Realistic paper shipping label stuck to one side face of a bale (or any host).
## Off-white paper card, ~11 × 8 cm, with printed text (supplier / weight / batch)
## and a small barcode in the lower band. NOT a floating billboard — the text
## lies flat on the card surface so you have to walk up to read it, exactly how
## real LDPE bales carry their tag. The BarcodeScanner ray-targets this card
## (visible mesh + collider) and reads the `label_info` metadata.
static func attach_to(host: Node3D, info: Dictionary, local_position: Vector3, local_basis: Basis = Basis(), card_color: Color = Color(0.93, 0.82, 0.15)) -> Node3D:
	if host == null:
		return null
	if host.get_node_or_null("Label") != null:
		return host.get_node_or_null("Label")
	var label := MeshInstance3D.new()
	label.name = "Label"
	var card := StandardMaterial3D.new()
	# Yellow shipping label — the original colour that worked. Restored per
	# operator (the off-white iteration was wrong; real CeDo bales DO carry
	# the bright-yellow sticker, that's what makes them findable on a stack).
	card.albedo_color = card_color
	card.roughness = 0.85
	# 22 × 14 cm — the previous working size, readable from a step or two away.
	var card_w := 0.22
	var card_h := 0.14
	var qm := BoxMesh.new(); qm.size = Vector3(card_w, card_h, 0.003)
	label.mesh = qm
	label.material_override = card

	# ── PLACEMENT JITTER (#170 follow-up) ────────────────────────────────────
	# Real CeDo bales don't have the sticker dead-centre under the middle wire
	# band — they're slapped on by a wet glove and end up shifted left or
	# right, biased to sit BETWEEN two of the three wires (where there's clear
	# poly to stick to). We recreate that here.
	#
	# Wire bands wrap the bale at 25 % / 50 % / 75 % of bale height (see
	# `_m_bale_detail` in PlaceableCatalog → `_build_wires`). The wire pitch is
	# therefore 25 % of bale height; the target sweet spot for the label is
	# midway between bands 1 and 2 → 37.5 % of bale height (NOT under the
	# centre wire at 50 %).
	#
	# The caller passes `local_position.y = bale_h * 0.55` for the old
	# centred placement, so we back out the bale height from it (this keeps
	# `attach_to` ignorant of the bale size without changing the call site
	# signature). If the caller ever stops doing that, we fall back to the
	# raw y value and just add the offsets in place.
	var local_basis_x : Vector3 = local_basis.x       # card horizontal in bale-local space
	var bale_h : float = 0.0
	if absf(local_position.y) > 0.0001:
		bale_h = local_position.y / 0.55
	# Same bale → same offset, every time (seed off batch id so the sticker
	# doesn't dance between frames or after a reload).
	var jitter_rng := RandomNumberGenerator.new()
	jitter_rng.seed = hash(String(info.get("batch", "")))
	var wire_pitch : float = bale_h * 0.25            # vertical spacing between wires
	var half_pitch : float = wire_pitch * 0.5
	# Horizontal (X): NORMAL(0, half_pitch * 0.15) along the card's own
	# horizontal axis (= `local_basis.x` in bale-local coords), clamped to
	# ±half_pitch * 0.25 so the tail can't punch the sticker past the wire-band
	# spacing. Operator spec: the wet-glove slap-on biases the sticker toward
	# the centre of the clear-poly window between bands 1 and 2 — a Gaussian
	# centred there matches the real-world pattern better than a flat range.
	var h_off : float = jitter_rng.randfn(0.0, half_pitch * 0.15)
	var h_clamp : float = half_pitch * 0.25
	h_off = clampf(h_off, -h_clamp, h_clamp)
	# Vertical (Y): UNIFORM ±half_pitch (one wire-band's worth of spread).
	# Only the X axis is normally-distributed per operator spec; Y stays a flat
	# range so the sticker reads as "somewhere between the wires" rather than
	# strongly biased to the centre. The wire clamp is implicit (the range is
	# already bounded by ±half_pitch).
	var v_off : float = jitter_rng.randf_range(-half_pitch, half_pitch)
	# Sweet spot Y = midway between band 1 (25 %) and band 2 (50 %) = 37.5 %
	# of bale height from the bale's bottom. Replace the centred Y the caller
	# gave us, then add the random jitters along bale-local Y (vertical) and
	# along the card's local +X (horizontal across the sticker).
	var jittered_pos : Vector3 = local_position
	jittered_pos.y = bale_h * 0.375 + v_off
	jittered_pos += local_basis_x * h_off
	label.transform = Transform3D(local_basis, jittered_pos)

	# ── PRINTED TEXT (flat on the card, not a billboard) ──────────────────────
	# Top: supplier. Middle: bale ID. Bottom: weight. Dark grey ink, flat on the
	# paper. #203 — dimensions/grade line dropped per operator (doesn't belong
	# on a real CeDo shipping sticker), and sizing reduced so the block fits.
	var nm   : String = String(info.get("item", ""))
	# Drop a redundant trailing "bale" word — it's obviously a bale, so the
	# sticker just shows the supplier (e.g. "FORST+ (FOSTPLUS)").
	for suffix in [" bale", " Bale", " BALE"]:
		if nm.ends_with(suffix):
			nm = nm.left(nm.length() - suffix.length())
			break
	var kg   : int    = int(info.get("weight_kg", 0))
	var lot  : String = String(info.get("batch", ""))
	# #203 — `dim` (dimensions/grade) intentionally dropped from the rendered
	# label. Operator said multiple times it doesn't belong on a shipping
	# sticker; the field is still in `info` for any non-visual lookup that
	# wants it.
	var sup_text : String = nm if nm != "" else "UNKNOWN"
	var bale_id  : String = lot if lot != "" else "B-00000"
	var text := Label3D.new()
	text.name = "PrintedText"
	# Anchored to TOP so the 3-line block starts at the card's top edge and grows
	# downward toward (but never INTO) the barcode band. Operator saw the previous
	# centered block bleed its bottom line into the barcode at station 203 —
	# `vertical_alignment = TOP` + a fixed top-anchor position pins the bottom of
	# the text block at a known Y, no matter how many lines or how big the font.
	# Card top = +card_h/2 = +7 cm. Barcode top sits at -2.4 cm (bc_y + bc_h/2).
	# 3 lines × ~2.0 cm at font 22 / pixel 0.0008 = ~6 cm, fits comfortably with
	# ~3 cm clear space above the barcode.
	text.text = "%s\nID %s\n%d kg" % [sup_text.to_upper(), bale_id, kg]
	text.font_size = 22
	text.outline_size = 0
	text.pixel_size = 0.0008
	text.modulate = Color(0.08, 0.08, 0.08)
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	text.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	text.no_depth_test = false
	text.position = Vector3(0.0, card_h * 0.42, 0.0018)   # anchor at card top, +1.8 mm forward
	label.add_child(text)

	# ── BARCODE STRIPES (lower band of the card) ──────────────────────────────
	# A proper-looking 1D barcode that spans nearly the FULL width of the card
	# with a small left/right margin (matching the existing left+bottom margin).
	# Built as a grid of equal-width modules; each module is black or white based
	# on the batch hash, with contiguous black runs merged into single bars. The
	# scanner doesn't optically decode them — it reads label_info meta — but the
	# user gets a realistic full-width SKU strip.
	var ink := StandardMaterial3D.new()
	ink.albedo_color = Color(0.05, 0.05, 0.05)
	var bc_h     := card_h * 0.26
	var bc_y     := -card_h * 0.30
	var margin   := card_w * 0.08                 # small left/right margin
	var bc_span  := card_w - margin * 2.0         # barcode spans the rest of the width
	var bc_left  := -card_w * 0.5 + margin
	var modules  := 40                            # fine modules → crisp dense code
	var mod_w    := bc_span / float(modules)
	var bar_seed : int = hash(lot)
	var i := 0
	while i < modules:
		# Is this module a black bar? Pseudo-random from the hash; force the
		# guard bars at both ends black so it reads like a real barcode.
		var bit : int = (bar_seed >> (i % 30)) & 0x1
		var is_bar : bool = (i < 2) or (i >= modules - 2) or bit == 1
		if not is_bar:
			i += 1
			continue
		# Merge the contiguous black run into one bar.
		var run := 1
		while i + run < modules:
			var nbit : int = (bar_seed >> ((i + run) % 30)) & 0x1
			var nbar : bool = (i + run >= modules - 2) or nbit == 1
			if not nbar:
				break
			run += 1
		var bw : float = mod_w * float(run) - 0.0006   # tiny gap between bars
		var cx : float = bc_left + (float(i) + float(run) * 0.5) * mod_w
		var stripe := MeshInstance3D.new()
		var sm := BoxMesh.new(); sm.size = Vector3(maxf(bw, 0.0006), bc_h, 0.0035)
		stripe.mesh = sm
		stripe.material_override = ink
		stripe.position = Vector3(cx, bc_y, 0.0018)
		label.add_child(stripe)
		i += run

	# Labels cull aggressively at 2 m (per user — they're only readable up close
	# Per operator handover: sync label visibility EXACTLY to the bale LOD cull
	# distance (54 m, set in PlaceableCatalog._m_bale_simple). The 2 m clamp we
	# had previously was too aggressive — labels vanished while bales stayed
	# visible. Engine-side fade keeps this cheap; the per-bale geometry cost is
	# the trade-off (see task #93: lazy-bake labels into single-quad textures
	# if FPS in yards hurts after this change).
	const _LABEL_VIS_RANGE : float = 54.0
	const _LABEL_FADE_MARGIN : float = 4.0
	label.visibility_range_end = _LABEL_VIS_RANGE
	label.visibility_range_end_margin = _LABEL_FADE_MARGIN
	label.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	for ch in label.get_children():
		if ch is GeometryInstance3D:
			(ch as GeometryInstance3D).visibility_range_end = _LABEL_VIS_RANGE
			(ch as GeometryInstance3D).visibility_range_end_margin = _LABEL_FADE_MARGIN
			(ch as GeometryInstance3D).visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	label.set_meta("label_info", info)
	host.add_child(label)
	return label
