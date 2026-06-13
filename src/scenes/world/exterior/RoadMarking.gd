extends Node3D
class_name RoadMarking

## Painted ground markings on asphalt. One instance can build MANY marks via
## repeated build_at(...) calls — the caller passes the kind, world position,
## yaw (radians) and an optional color name. All marks sit at
## `paint_y_offset` above `surface_y` to avoid z-fighting with the road slab.
##
## Caller responsibilities:
##   • Pass the desired position in this node's local space (typically the
##     RoadMarking node is parented under MainWorld at the exterior origin,
##     so local == world for flat ground).
##   • Pass `yaw_rad` so that local +Z aligns with the traffic direction (the
##     mark is built oriented along +Z and rotated about Y by `yaw_rad`).
##   • Pass `color_name` = "white" (default, faded road paint) or "yellow"
##     (warning markings). Anything else falls back to white with a warning.
##
## Supported `kind` values:
##   "stop_text"          — block STOP letters built as four 3-bar PrismMesh +
##                          BoxMesh glyph stand-ins (~0.5 m tall, 0.6 m wide).
##   "give_way_triangle"  — pair of thin PrismMesh triangles forming a row
##                          (the Dutch "haaietanden" give-way teeth).
##   "arrow_straight"     — BoxMesh stem + PrismMesh arrowhead, pointing +Z.
##   "arrow_left"         — stem + perpendicular shaft + rotated head, left.
##   "arrow_right"        — same as arrow_left, mirrored to the right.

@export var surface_y      : float = 0.0
@export var paint_y_offset : float = 0.012

# ── Public API ────────────────────────────────────────────────────────────────
func build_at(kind: String, pos: Vector3, yaw_rad: float = 0.0, color_name: String = "white") -> void:
	var paint_mat : StandardMaterial3D = _make_paint_material(color_name)
	var basis := Basis(Vector3.UP, yaw_rad)
	var origin : Vector3 = Vector3(pos.x, surface_y + paint_y_offset, pos.z)
	var anchor := Node3D.new()
	anchor.name = "Mark_%s" % kind
	anchor.transform = Transform3D(basis, origin)
	add_child(anchor)
	match kind:
		"stop_text":
			_build_stop_text(anchor, paint_mat)
		"give_way_triangle":
			_build_give_way(anchor, paint_mat)
		"arrow_straight":
			_build_arrow_straight(anchor, paint_mat)
		"arrow_left":
			_build_arrow_turn(anchor, paint_mat, -1)
		"arrow_right":
			_build_arrow_turn(anchor, paint_mat, 1)
		_:
			push_warning("[RoadMarking] unknown kind '%s' — skipped" % kind)
			anchor.queue_free()

# ── Material helper ───────────────────────────────────────────────────────────
func _make_paint_material(color_name: String) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	match color_name:
		"white":
			mat.albedo_color = Color(0.95, 0.95, 0.92)
			mat.roughness = 0.55
		"yellow":
			mat.albedo_color = Color(0.92, 0.78, 0.10)
			mat.roughness = 0.60
		_:
			push_warning("[RoadMarking] unknown color '%s' — defaulting to white" % color_name)
			mat.albedo_color = Color(0.95, 0.95, 0.92)
			mat.roughness = 0.55
	mat.metallic = 0.0
	return mat

# ── Glyph primitives ──────────────────────────────────────────────────────────
# All glyph helpers build geometry centred on local (0, 0, 0) of the anchor.
# Paint is 5 mm thick (Y) so it reads on the asphalt without z-fighting.
const PAINT_THICKNESS : float = 0.005
const GLYPH_HEIGHT    : float = 0.50
const GLYPH_WIDTH     : float = 0.60
const GLYPH_BAR       : float = 0.10   # bar thickness in the X / Z plane

func _add_box(parent: Node3D, nm: String, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.transform = Transform3D(Basis(), pos)
	mi.material_override = mat
	parent.add_child(mi)

func _add_prism(parent: Node3D, nm: String, size: Vector3, pos: Vector3, yaw_rad: float, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.name = nm
	var pm := PrismMesh.new()
	pm.size = size
	mi.mesh = pm
	mi.transform = Transform3D(Basis(Vector3.UP, yaw_rad), pos)
	mi.material_override = mat
	parent.add_child(mi)

# ── STOP text (S T O P, each letter a 3-bar glyph stand-in) ───────────────────
# Glyph is laid out in the X (width) × Z (length-along-traffic) plane.
# Each letter ~0.6 m wide on X, ~0.5 m tall on Z (long axis along traffic).
func _build_stop_text(parent: Node3D, mat: Material) -> void:
	var letters : Array = ["S", "T", "O", "P"]
	var spacing : float = GLYPH_WIDTH + 0.18
	var total_w : float = float(letters.size() - 1) * spacing
	for i in letters.size():
		var x : float = -total_w * 0.5 + float(i) * spacing
		var letter_anchor := Node3D.new()
		letter_anchor.name = "Letter_%s" % letters[i]
		letter_anchor.position = Vector3(x, 0.0, 0.0)
		parent.add_child(letter_anchor)
		_build_letter(letter_anchor, letters[i], mat)

# Builds a 3-bar glyph stand-in for the given letter. All four letters use the
# same 3-bar topology — one horizontal bar at top, one in the middle, one at
# bottom, with vertical stems specific to each letter. Close enough at the
# distance the player ever reads them.
func _build_letter(parent: Node3D, letter: String, mat: Material) -> void:
	var w : float = GLYPH_WIDTH
	var h : float = GLYPH_HEIGHT
	var t : float = GLYPH_BAR
	var y : float = 0.0
	# Three horizontal cross-bars (top / middle / bottom) along X, of width w.
	var bar_size := Vector3(w, PAINT_THICKNESS, t)
	# Vertical stems run along Z, of length h.
	var stem_size := Vector3(t, PAINT_THICKNESS, h)
	match letter:
		"S":
			# top bar, mid bar, bottom bar + left-upper stem + right-lower stem
			_add_box(parent, "S_top", bar_size, Vector3(0.0, y, h * 0.5 - t * 0.5), mat)
			_add_box(parent, "S_mid", bar_size, Vector3(0.0, y, 0.0), mat)
			_add_box(parent, "S_bot", bar_size, Vector3(0.0, y, -h * 0.5 + t * 0.5), mat)
			_add_box(parent, "S_stem_UL", Vector3(t, PAINT_THICKNESS, h * 0.5),
					Vector3(-w * 0.5 + t * 0.5, y, h * 0.25), mat)
			_add_box(parent, "S_stem_LR", Vector3(t, PAINT_THICKNESS, h * 0.5),
					Vector3(w * 0.5 - t * 0.5, y, -h * 0.25), mat)
		"T":
			# top bar + central vertical stem
			_add_box(parent, "T_top", bar_size, Vector3(0.0, y, h * 0.5 - t * 0.5), mat)
			_add_box(parent, "T_stem", stem_size, Vector3(0.0, y, 0.0), mat)
		"O":
			# top bar, bottom bar, left stem, right stem
			_add_box(parent, "O_top", bar_size, Vector3(0.0, y, h * 0.5 - t * 0.5), mat)
			_add_box(parent, "O_bot", bar_size, Vector3(0.0, y, -h * 0.5 + t * 0.5), mat)
			_add_box(parent, "O_stem_L", stem_size, Vector3(-w * 0.5 + t * 0.5, y, 0.0), mat)
			_add_box(parent, "O_stem_R", stem_size, Vector3( w * 0.5 - t * 0.5, y, 0.0), mat)
		"P":
			# left full-height stem + top bar + mid bar + right-upper stem
			_add_box(parent, "P_stem_L", stem_size, Vector3(-w * 0.5 + t * 0.5, y, 0.0), mat)
			_add_box(parent, "P_top", bar_size, Vector3(0.0, y, h * 0.5 - t * 0.5), mat)
			_add_box(parent, "P_mid", bar_size, Vector3(0.0, y, 0.0), mat)
			_add_box(parent, "P_stem_UR", Vector3(t, PAINT_THICKNESS, h * 0.5),
					Vector3(w * 0.5 - t * 0.5, y, h * 0.25), mat)
		_:
			push_warning("[RoadMarking] unsupported STOP letter '%s'" % letter)

# ── Give-way triangles (haaietanden — Dutch "shark teeth") ────────────────────
# A row of two thin triangles, points facing the oncoming traffic (-Z).
# Each triangle ~0.40 m wide on X, ~0.60 m long on Z.
func _build_give_way(parent: Node3D, mat: Material) -> void:
	var tri_w : float = 0.40
	var tri_l : float = 0.60
	var gap   : float = 0.20
	var total_w : float = 2.0 * tri_w + gap
	for i in 2:
		var x : float = -total_w * 0.5 + tri_w * 0.5 + float(i) * (tri_w + gap)
		# PrismMesh's "tip" points along +Z by default; size = (width, height, depth).
		# We rotate by 180° so the tip points -Z (toward the oncoming car).
		_add_prism(parent, "Tooth_%d" % i,
				Vector3(tri_w, PAINT_THICKNESS, tri_l),
				Vector3(x, 0.0, 0.0),
				PI,
				mat)

# ── Straight arrow (stem along +Z, head pointing +Z) ──────────────────────────
# Stem ~0.18 m wide × 2.5 m long; head ~0.55 m wide × 0.9 m long.
func _build_arrow_straight(parent: Node3D, mat: Material) -> void:
	var stem_w : float = 0.18
	var stem_l : float = 2.50
	var head_w : float = 0.55
	var head_l : float = 0.90
	# Stem centred behind the arrowhead.
	_add_box(parent, "Stem",
			Vector3(stem_w, PAINT_THICKNESS, stem_l),
			Vector3(0.0, 0.0, -head_l * 0.5),
			mat)
	# Head — PrismMesh tip points +Z (no extra yaw needed).
	_add_prism(parent, "Head",
			Vector3(head_w, PAINT_THICKNESS, head_l),
			Vector3(0.0, 0.0, stem_l * 0.5 - head_l * 0.5),
			0.0,
			mat)

# ── Turn arrows (left / right) ────────────────────────────────────────────────
# Stem along +Z, perpendicular shaft branching out to ±X, head at the shaft's
# tip pointing ±X. dir = -1 for left (toward -X), +1 for right (toward +X).
func _build_arrow_turn(parent: Node3D, mat: Material, dir: int) -> void:
	var stem_w  : float = 0.18
	var stem_l  : float = 2.20
	var shaft_l : float = 0.90      # how far the perpendicular shaft sticks out
	var shaft_w : float = 0.18
	var head_w  : float = 0.55
	var head_l  : float = 0.55
	# Vertical stem (same as straight arrow but slightly shorter).
	_add_box(parent, "Stem",
			Vector3(stem_w, PAINT_THICKNESS, stem_l),
			Vector3(0.0, 0.0, 0.0),
			mat)
	# Perpendicular shaft branching off the upper end of the stem.
	var shaft_centre_x : float = float(dir) * (shaft_l * 0.5)
	var shaft_z : float = stem_l * 0.5 - shaft_w * 0.5
	_add_box(parent, "Shaft",
			Vector3(shaft_l, PAINT_THICKNESS, shaft_w),
			Vector3(shaft_centre_x, 0.0, shaft_z),
			mat)
	# Head — PrismMesh tip points +Z by default; rotate by ±90° about Y so the
	# tip points ±X (along the shaft).
	var head_yaw : float = -PI * 0.5 if dir == -1 else PI * 0.5
	var head_x : float = float(dir) * (shaft_l - head_l * 0.5)
	_add_prism(parent, "Head",
			Vector3(head_w, PAINT_THICKNESS, head_l),
			Vector3(head_x, 0.0, shaft_z),
			head_yaw,
			mat)
