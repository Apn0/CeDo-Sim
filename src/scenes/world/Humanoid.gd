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

static func build(shirt: Color, variant: int = 0) -> Node3D:
	var skin  : Color = _SKIN_TONES[variant % _SKIN_TONES.size()]
	var hair  : Color = _HAIR_TONES[(variant / 2) % _HAIR_TONES.size()]
	var pants : Color = Color(0.16, 0.18, 0.26)          # dark work trousers
	var boots : Color = Color(0.10, 0.10, 0.11)

	var root := Node3D.new()
	root.name = "Body"

	var m_skin  := _mat(skin, 0.85)
	var m_shirt := _mat(shirt, 0.8)
	var m_pants := _mat(pants, 0.85)
	var m_boots := _mat(boots, 0.7)
	var m_hair  := _mat(hair, 0.9)
	var m_dark  := _mat(Color(0.05, 0.05, 0.06), 0.6)    # eyes/brows/mouth ink

	# ── LEGS ──────────────────────────────────────────────────────────────────
	# Feet at y≈-0.9. Boots, shins, thighs stacked up to the pelvis at y≈-0.18.
	for sx in [-1.0, 1.0]:
		var x : float = float(sx) * 0.12
		_box(root, Vector3(0.16, 0.08, 0.30), Vector3(x, -0.86, 0.04), m_boots)   # foot
		_box(root, Vector3(0.13, 0.40, 0.13), Vector3(x, -0.62, 0.0),  m_pants)   # lower leg (shin)
		_box(root, Vector3(0.16, 0.40, 0.16), Vector3(x, -0.24, 0.0),  m_pants)   # upper leg (thigh)

	# ── CORE ──────────────────────────────────────────────────────────────────
	_box(root, Vector3(0.36, 0.16, 0.20), Vector3(0.0, -0.06, 0.0), m_pants)      # pelvis
	_box(root, Vector3(0.40, 0.46, 0.22), Vector3(0.0,  0.26, 0.0), m_shirt)      # chest/torso

	# ── ARMS ──────────────────────────────────────────────────────────────────
	for sx in [-1.0, 1.0]:
		var x : float = float(sx) * 0.27
		_box(root, Vector3(0.11, 0.26, 0.12), Vector3(x, 0.34, 0.0), m_shirt)     # upper arm
		_box(root, Vector3(0.10, 0.26, 0.11), Vector3(x, 0.08, 0.0), m_skin)      # forearm
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

	# ── HAIR (cap over the top + back of the head) ──────────────────────────────
	_box(root, Vector3(0.26, 0.09, 0.26), Vector3(0.0, head_y + 0.135, 0.0), m_hair)   # top
	_box(root, Vector3(0.26, 0.22, 0.06), Vector3(0.0, head_y + 0.03, -0.11), m_hair)  # back

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
