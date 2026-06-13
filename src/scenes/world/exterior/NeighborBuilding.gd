extends Node3D
class_name NeighborBuilding

## Blocky neighbouring industrial building stand-in for the warehouses across
## De Asselen Kuil from the CeDo lot. The caller passes every parameter via
## build_at() so a wire-up loop (e.g. WorldLayout / MainWorld) can drop a row
## of differently-coloured warehouse stand-ins along the road without any
## per-building configuration here.
##
## What build_at() produces:
##  • One BoxMesh body of caller-supplied size (X width, Y height, Z depth),
##    painted with a slightly varied corrugated-metal albedo around
##    `paint_color` (each channel jittered by up to ±0.04 from a deterministic
##    seed so two adjacent buildings don't read identical). Roughness 0.7,
##    metallic 0.35 — reads as faded painted sheet steel.
##  • Optional flat roof slab: BoxMesh slightly wider than the body, painted
##    `roof_color` (default bitumen grey Color(0.18, 0.18, 0.20)). Toggle via
##    `has_roof`.
##  • Optional Label3D name tag mounted on the +Z face near the top of the
##    body — white text, 48 pt, outline 4, billboard disabled so it reads as
##    a painted sign rather than floating UI.
##
## All parameters are caller-supplied; no @export config beyond `has_roof`.
## Yaw rotates the whole instance about Y. seed_in drives the per-channel
## albedo jitter so saves replay identically.

@export var has_roof : bool = true

func build_at(pos: Vector3, size: Vector3, paint_color: Color,
		label_text: String = "", roof_color: Color = Color(0.18, 0.18, 0.20),
		yaw_rad: float = 0.0, seed_in: int = 0) -> void:
	if size.x <= 0.0 or size.y <= 0.0 or size.z <= 0.0:
		push_warning("[NeighborBuilding] build_at got non-positive size: %s" % str(size))
		return
	# Orient the whole instance — children inherit this basis.
	transform = Transform3D(Basis(Vector3.UP, yaw_rad), pos)
	_build_body(size, paint_color, seed_in)
	if has_roof:
		_build_roof(size, roof_color)
	if label_text != "":
		_build_label(size, label_text)

# ── Corrugated-metal painted body ─────────────────────────────────────────────
func _build_body(size: Vector3, paint_color: Color, seed_in: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_in
	var jitter_r : float = rng.randf_range(-0.04, 0.04)
	var jitter_g : float = rng.randf_range(-0.04, 0.04)
	var jitter_b : float = rng.randf_range(-0.04, 0.04)
	var varied := Color(
		clamp(paint_color.r + jitter_r, 0.0, 1.0),
		clamp(paint_color.g + jitter_g, 0.0, 1.0),
		clamp(paint_color.b + jitter_b, 0.0, 1.0),
		1.0
	)
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = size
	body.mesh = bm
	# Body sits on its base — translate up by half-height so pos is the ground anchor.
	body.position = Vector3(0.0, size.y * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = varied
	mat.roughness = 0.7
	mat.metallic = 0.35
	body.material_override = mat
	add_child(body)

# ── Flat bitumen roof slab ────────────────────────────────────────────────────
func _build_roof(size: Vector3, roof_color: Color) -> void:
	var roof := MeshInstance3D.new()
	roof.name = "Roof"
	var rm := BoxMesh.new()
	# Slightly wider than the body in X and Z; thin slab in Y.
	var overhang : float = 0.25
	var slab_h : float = 0.15
	rm.size = Vector3(size.x + overhang * 2.0, slab_h, size.z + overhang * 2.0)
	roof.mesh = rm
	# Sit the slab on top of the body.
	roof.position = Vector3(0.0, size.y + slab_h * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = roof_color
	mat.roughness = 0.9
	mat.metallic = 0.0
	roof.material_override = mat
	add_child(roof)

# ── Painted-sign name tag on the +Z face ──────────────────────────────────────
func _build_label(size: Vector3, label_text: String) -> void:
	var label := Label3D.new()
	label.name = "NameTag"
	label.text = label_text
	label.font_size = 48
	label.outline_size = 4
	label.modulate = Color(1.0, 1.0, 1.0, 1.0)
	label.outline_modulate = Color(0.0, 0.0, 0.0, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	label.double_sided = false
	label.no_depth_test = false
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Mount on the +Z face, near the top of the body. Lift slightly off the
	# surface to avoid z-fighting with the painted body (same trick as
	# paint_y_offset in Road / StaffParking).
	var face_offset : float = 0.02
	var top_margin : float = size.y * 0.18
	label.position = Vector3(0.0, size.y - top_margin, size.z * 0.5 + face_offset)
	# Label3D default faces -Z; rotate 180° so it reads from the +Z side.
	label.rotation = Vector3(0.0, PI, 0.0)
	add_child(label)
