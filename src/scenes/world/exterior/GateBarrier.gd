extends Node3D
class_name GateBarrier

## Red-and-white striped boom barrier at the node's origin. The hinge sits at
## the +Y top of a steel post on the -X side; the lifting arm extends +X from
## that pivot. Caller passes in the desired arm angle via `setup(angle_deg)`
## BEFORE the node enters the tree, or toggles open/closed at runtime via
## `set_open()`. 0 deg = arm horizontal (closed, blocking the road), 90 deg =
## arm vertical (open, vehicle may pass).
##
## All geometry is primitive meshes with inline StandardMaterial3D — no
## textures, no preloads. Stripe pattern is real geometry (alternating red /
## white BoxMesh children every ~0.6 m along the arm), so it reads correctly
## from any angle and under any lighting.
##
## Usage:
##   var gate := GateBarrier.new()
##   gate.setup(0.0)            # closed
##   add_child(gate)
##   gate.transform = ...        # place at the gate-house position
##   gate.set_open(true)         # raise arm

@export var arm_length    : float = 4.0
@export var arm_height    : float = 0.14
@export var post_height   : float = 1.1
@export var arm_angle_deg : float = 0.0

# Internal tunables (kept private; operator rarely needs to touch these).
const POST_RADIUS    : float = 0.08
const HOUSING_SIZE   : Vector3 = Vector3(0.32, 0.22, 0.28)
const BAND_LENGTH    : float = 0.6   # target stripe length along the arm
const ARM_THICKNESS  : float = 0.10  # arm cross-section depth (Y when down... wait, arm extends +X; this is the vertical thickness when closed)

# Built nodes we may need to address again (the pivot owns the whole arm).
var _pivot : Node3D = null

func setup(angle_deg: float = 0.0) -> void:
	arm_angle_deg = angle_deg

func _ready() -> void:
	_build_post()
	_build_housing()
	_build_arm()
	_apply_arm_angle()

# ── Convenience toggle (no tween — snaps to the target angle) ─────────────────
func set_open(open: bool) -> void:
	arm_angle_deg = 90.0 if open else 0.0
	_apply_arm_angle()

# ── Steel base post on the -X side of the origin ──────────────────────────────
func _build_post() -> void:
	var post := MeshInstance3D.new()
	post.name = "Post"
	var cm := CylinderMesh.new()
	cm.top_radius = POST_RADIUS
	cm.bottom_radius = POST_RADIUS
	cm.height = post_height
	post.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.63, 0.65)   # galvanised steel, slightly cool grey
	mat.metallic = 0.75
	mat.roughness = 0.45
	post.material_override = mat
	# The post sits on the -X side of the origin (origin = arm pivot in plan).
	# Origin Y is taken to be ground level; the post centre is therefore at
	# half-height above ground, and its top reaches y = post_height.
	post.position = Vector3(-POST_RADIUS - 0.02, post_height * 0.5, 0.0)
	add_child(post)

# ── Dark control housing perched on top of the post ───────────────────────────
func _build_housing() -> void:
	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	var bm := BoxMesh.new()
	bm.size = HOUSING_SIZE
	housing.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.16, 0.16, 0.18)   # dark grey weatherproof box
	mat.roughness = 0.7
	mat.metallic = 0.1
	housing.material_override = mat
	housing.position = Vector3(
		-POST_RADIUS - 0.02,
		post_height + HOUSING_SIZE.y * 0.5,
		0.0)
	add_child(housing)

# ── The lifting arm: pivot at origin top-of-post, then segmented stripes ──────
func _build_arm() -> void:
	# Pivot sits at the top of the post (hinge end of the arm). The pivot's
	# rotation about its local Z axis raises/lowers the arm. Arm geometry is
	# built as children of the pivot, extending along +X from the pivot.
	_pivot = Node3D.new()
	_pivot.name = "ArmPivot"
	_pivot.position = Vector3(0.0, post_height, 0.0)
	add_child(_pivot)
	# How many alternating bands fit along the arm? Aim for ~BAND_LENGTH each;
	# we accept slight rounding so the bands tile exactly.
	var n_bands : int = max(1, int(round(arm_length / BAND_LENGTH)))
	var band_len : float = arm_length / float(n_bands)
	var red_mat := StandardMaterial3D.new()
	red_mat.albedo_color = Color(0.78, 0.10, 0.10)
	red_mat.roughness = 0.55
	red_mat.metallic = 0.0
	var white_mat := StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.95, 0.95, 0.92)
	white_mat.roughness = 0.55
	white_mat.metallic = 0.0
	for i in n_bands:
		var band := MeshInstance3D.new()
		band.name = "ArmBand_%d" % i
		var bm := BoxMesh.new()
		# Arm extends along +X from the pivot; arm_height is vertical thickness.
		bm.size = Vector3(band_len, arm_height, ARM_THICKNESS)
		band.mesh = bm
		# Centre each band along +X starting at the pivot (i=0 nearest hinge).
		var cx : float = (float(i) + 0.5) * band_len
		band.position = Vector3(cx, 0.0, 0.0)
		# Alternate red/white. Convention: hinge-end is red (high-visibility tip
		# is also red at the far end with an odd band count, which is typical).
		band.material_override = red_mat if (i % 2 == 0) else white_mat
		_pivot.add_child(band)
	# Small white counterweight nub on the -X side of the pivot, for visual
	# balance — real barriers have a counter-mass behind the hinge.
	var cw := MeshInstance3D.new()
	cw.name = "Counterweight"
	var cwm := BoxMesh.new()
	cwm.size = Vector3(0.22, arm_height * 1.4, ARM_THICKNESS * 1.2)
	cw.mesh = cwm
	var cw_mat := StandardMaterial3D.new()
	cw_mat.albedo_color = Color(0.20, 0.20, 0.22)
	cw_mat.roughness = 0.6
	cw_mat.metallic = 0.2
	cw.material_override = cw_mat
	cw.position = Vector3(-0.14, 0.0, 0.0)
	_pivot.add_child(cw)

# ── Apply current angle to the pivot ──────────────────────────────────────────
# 0 deg → arm horizontal (closed). 90 deg → arm vertical, pointing +Y (open).
# Rotation is about the pivot's local -Z axis so that +X arm lifts upward.
func _apply_arm_angle() -> void:
	if _pivot == null:
		return
	var a : float = deg_to_rad(clamp(arm_angle_deg, 0.0, 90.0))
	# Hinge axis = +Z (Vector3.BACK). Right-hand rule: positive rotation about
	# +Z maps +X to +Y, so at 90° the +X arm points STRAIGHT UP (open). Was
	# Vector3(0,0,-1) which sent the arm into the ground. Audit caught this.
	_pivot.transform = Transform3D(Basis(Vector3(0.0, 0.0, 1.0), a), _pivot.position)
