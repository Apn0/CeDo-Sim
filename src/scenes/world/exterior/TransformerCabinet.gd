extends Node3D
class_name TransformerCabinet

## Small grey-painted steel utility cabinet that sits at the exterior anchor
## origin. Reads as an electrical distribution / transformer cabinet at
## distance: concrete plinth, painted steel body, overhanging rain-hood cap,
## six recessed ventilation louvres on the +Z (front) face, and a small
## yellow-and-black DANGER decal on the door.
##
## Caller wire-up:
##   var tc := TransformerCabinet.new()
##   tc.body_size     = Vector3(0.9, 1.5, 0.6)   # optional override
##   tc.plinth_height = 0.08                     # optional override
##   add_child(tc)
##   tc.transform = Transform3D(Basis(Vector3.UP, yaw), pos)
##
## setup() is called from _ready() but is safe to invoke manually if the
## caller mutates exports after instancing but before adding to the tree.
##
## Origin convention: the cabinet's local origin sits at the BOTTOM of the
## concrete plinth (i.e. on the ground plane). The front of the cabinet
## (door + louvres + DANGER decal) faces local +Z, matching the project
## axis convention (+Z = north).

# ── Configuration (operator-tunable) ──────────────────────────────────────────
@export var body_size     : Vector3 = Vector3(0.9, 1.5, 0.6)
@export var plinth_height : float   = 0.08

# ── Internal palette ──────────────────────────────────────────────────────────
const _COL_BODY      : Color = Color(0.62, 0.63, 0.65)   # utility grey paint
const _COL_CAP       : Color = Color(0.38, 0.39, 0.41)   # darker grey rain hood
const _COL_PLINTH    : Color = Color(0.62, 0.60, 0.58)   # weathered concrete
const _COL_LOUVRE    : Color = Color(0.26, 0.27, 0.29)   # recessed dark slits
const _COL_DANGER_BG : Color = Color(0.95, 0.78, 0.10)   # hazard yellow
const _COL_DANGER_FG : Color = Color(0.05, 0.05, 0.05)   # near-black triangle

var _built : bool = false

func _ready() -> void:
	setup()

## Build (or rebuild) the cabinet meshes. Safe to call manually.
func setup() -> void:
	if _built:
		return
	_built = true
	_build_plinth()
	_build_body()
	_build_cap()
	_build_louvres()
	_build_danger_decal()

# ── Concrete plinth slab ──────────────────────────────────────────────────────
func _build_plinth() -> void:
	var plinth := MeshInstance3D.new()
	plinth.name = "Plinth"
	var bm := BoxMesh.new()
	# Plinth is a touch wider/deeper than the body, like a poured pad.
	bm.size = Vector3(body_size.x + 0.10, plinth_height, body_size.z + 0.10)
	plinth.mesh = bm
	plinth.position = Vector3(0.0, plinth_height * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _COL_PLINTH
	mat.roughness = 0.85
	mat.metallic = 0.0
	plinth.material_override = mat
	add_child(plinth)

# ── Painted steel body ────────────────────────────────────────────────────────
func _build_body() -> void:
	var body := MeshInstance3D.new()
	body.name = "Body"
	var bm := BoxMesh.new()
	bm.size = body_size
	body.mesh = bm
	body.position = Vector3(0.0, plinth_height + body_size.y * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _COL_BODY
	mat.metallic = 0.35
	mat.roughness = 0.55
	body.material_override = mat
	add_child(body)

# ── Overhanging cap (rain hood) ───────────────────────────────────────────────
func _build_cap() -> void:
	var cap := MeshInstance3D.new()
	cap.name = "Cap"
	var bm := BoxMesh.new()
	# Slightly wider/deeper than the body so it reads as an overhanging hood.
	var cap_h : float = 0.05
	bm.size = Vector3(body_size.x + 0.08, cap_h, body_size.z + 0.08)
	cap.mesh = bm
	cap.position = Vector3(0.0, plinth_height + body_size.y + cap_h * 0.5, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _COL_CAP
	mat.metallic = 0.4
	mat.roughness = 0.5
	cap.material_override = mat
	add_child(cap)

# ── Six horizontal louvres on the +Z (front) face ─────────────────────────────
func _build_louvres() -> void:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = _COL_LOUVRE
	mat.metallic = 0.2
	mat.roughness = 0.7
	# Vent block lives in the UPPER portion of the door, centred horizontally.
	# Total vent area roughly 60% body width, 35% body height, sitting at ~70%
	# height up the door.
	var front_face_z : float = body_size.z * 0.5
	var slit_count   : int   = 6
	var vent_w       : float = body_size.x * 0.55
	var vent_h       : float = body_size.y * 0.32
	var slit_h       : float = 0.018                                       # individual bar thickness
	var gap          : float = (vent_h - slit_h * float(slit_count)) / float(slit_count - 1)
	var vent_y_centre : float = plinth_height + body_size.y * 0.72
	var top_y        : float = vent_y_centre + vent_h * 0.5 - slit_h * 0.5
	for i in slit_count:
		var slit := MeshInstance3D.new()
		slit.name = "Louvre_%d" % i
		var bm := BoxMesh.new()
		# A thin, slightly-recessed bar — depth is tiny, just enough to read.
		bm.size = Vector3(vent_w, slit_h, 0.012)
		slit.mesh = bm
		# Recessed bars sit INSIDE the body — push them slightly INWARD from
		# the front face so they look like cuts, not stickers. front_face_z
		# is positive +Z; recessing means a smaller Z value.
		var y : float = top_y - float(i) * (slit_h + gap)
		slit.position = Vector3(0.0, y, front_face_z - 0.005)
		slit.material_override = mat
		add_child(slit)

# ── DANGER decal: yellow square + inline black triangle ───────────────────────
func _build_danger_decal() -> void:
	var front_face_z : float = body_size.z * 0.5
	# Place the decal on the lower-right area of the door, well clear of the
	# louvre block. Decal centre sits at ~30% door height.
	var decal_size : float = 0.18
	var decal_x    : float = body_size.x * 0.28
	var decal_y    : float = plinth_height + body_size.y * 0.30
	# Yellow backing quad — facing +Z, lifted slightly off the door face to
	# avoid z-fighting (paint_y_offset convention).
	var backing := MeshInstance3D.new()
	backing.name = "DangerBacking"
	var qm := QuadMesh.new()
	qm.size = Vector2(decal_size, decal_size)
	backing.mesh = qm
	backing.position = Vector3(decal_x, decal_y, front_face_z + 0.005)
	var bg_mat := StandardMaterial3D.new()
	bg_mat.albedo_color = _COL_DANGER_BG
	bg_mat.roughness = 0.6
	bg_mat.metallic = 0.0
	backing.material_override = bg_mat
	add_child(backing)
	# Black warning triangle — PrismMesh is naturally triangular when viewed
	# from the front. Mount it just in front of the yellow backing.
	var tri := MeshInstance3D.new()
	tri.name = "DangerTriangle"
	var pm := PrismMesh.new()
	pm.size = Vector3(decal_size * 0.72, decal_size * 0.62, 0.006)
	tri.mesh = pm
	tri.position = Vector3(decal_x, decal_y - decal_size * 0.04, front_face_z + 0.009)
	var fg_mat := StandardMaterial3D.new()
	fg_mat.albedo_color = _COL_DANGER_FG
	fg_mat.roughness = 0.7
	fg_mat.metallic = 0.0
	tri.material_override = fg_mat
	add_child(tri)
