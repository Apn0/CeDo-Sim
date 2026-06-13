extends Node3D
class_name Floodlight

## Wall-mounted exterior spotlight aimed downward at a configurable tilt. Used
## along the CeDo plant's perimeter walls to light the yard, parking apron and
## truck-loading bays after dusk.
##
## Caller positions and orients the node so the +Z face of the node origin sits
## flush against the wall (this matches the convention used by Road / StaffParking
## for placing exterior props). The bracket is built flush with that +Z face,
## the arm projects forward (-Z, away from the wall) and the housing hangs at
## the arm's far end. The SpotLight3D shines along the local -Y axis rotated
## outward from the wall by `tilt_down_deg` (default 25° down from horizontal).
##
## Public API:
##   func setup(tilt_deg: float = 25.0) -> void
##
## Configuration is exposed via @export so WorldLayout / operator can tune
## tilt, housing size, beam range and energy per fixture.

@export var tilt_down_deg : float = 25.0
@export var housing_size  : Vector3 = Vector3(0.35, 0.22, 0.30)
@export var light_energy  : float = 4.0
@export var spot_range    : float = 30.0

# Bracket / arm dims — tuned to feel like an industrial cast-steel fixture.
const BRACKET_SIZE : Vector3 = Vector3(0.18, 0.18, 0.08)
const ARM_LENGTH   : float   = 0.55
const ARM_RADIUS   : float   = 0.035

func setup(tilt_deg: float = 25.0) -> void:
	tilt_down_deg = tilt_deg

func _ready() -> void:
	_build_bracket()
	_build_arm()
	_build_housing()
	_build_light()

# ── Steel mounting bracket flush with the +Z face of the node origin ──────────
func _build_bracket() -> void:
	var bracket := MeshInstance3D.new()
	bracket.name = "Bracket"
	var bm := BoxMesh.new()
	bm.size = BRACKET_SIZE
	bracket.mesh = bm
	# Flush with +Z face → bracket centre sits half its depth INTO +Z.
	bracket.position = Vector3(0.0, 0.0, BRACKET_SIZE.z * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.30, 0.32)
	mat.metallic = 0.6
	mat.roughness = 0.45
	bracket.material_override = mat
	add_child(bracket)

# ── Forward-projecting arm (cylinder) from bracket out to housing ─────────────
func _build_arm() -> void:
	var arm := MeshInstance3D.new()
	arm.name = "Arm"
	var cm := CylinderMesh.new()
	cm.top_radius = ARM_RADIUS
	cm.bottom_radius = ARM_RADIUS
	cm.height = ARM_LENGTH
	arm.mesh = cm
	# CylinderMesh default axis is +Y. Rotate so the arm runs along -Z
	# (away from the wall). Rotating +90° around X swings +Y to -Z.
	var basis := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	var arm_centre_z : float = -ARM_LENGTH * 0.5
	arm.transform = Transform3D(basis, Vector3(0.0, 0.0, arm_centre_z))
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.30, 0.32)
	mat.metallic = 0.6
	mat.roughness = 0.45
	arm.material_override = mat
	add_child(arm)

# ── Housing box at the far end of the arm, with emissive lens on -Y face ──────
func _build_housing() -> void:
	var housing_centre := Vector3(0.0, 0.0, -ARM_LENGTH - housing_size.z * 0.5)
	# Body of the housing — dark grey weatherproof shell.
	var housing := MeshInstance3D.new()
	housing.name = "Housing"
	var bm := BoxMesh.new()
	bm.size = housing_size
	housing.mesh = bm
	housing.position = housing_centre
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = Color(0.18, 0.18, 0.19)
	body_mat.metallic = 0.5
	body_mat.roughness = 0.55
	housing.material_override = body_mat
	add_child(housing)
	# Emissive lens face on the -Y (downward) side of the housing.
	var lens := MeshInstance3D.new()
	lens.name = "Lens"
	var qm := QuadMesh.new()
	qm.size = Vector2(housing_size.x * 0.85, housing_size.z * 0.85)
	lens.mesh = qm
	# QuadMesh faces +Z by default. Rotate so its normal points -Y (down).
	var lens_basis := Basis(Vector3.RIGHT, deg_to_rad(90.0))
	var lens_offset : float = 0.002  # avoid z-fighting with housing face
	var lens_centre := housing_centre + Vector3(0.0, -housing_size.y * 0.5 - lens_offset, 0.0)
	lens.transform = Transform3D(lens_basis, lens_centre)
	var lens_mat := StandardMaterial3D.new()
	lens_mat.albedo_color = Color(1.0, 0.96, 0.86)
	lens_mat.emission_enabled = true
	lens_mat.emission = Color(1.0, 0.96, 0.86)
	lens_mat.emission_energy_multiplier = 2.0
	lens_mat.roughness = 0.25
	lens.material_override = lens_mat
	add_child(lens)

# ── SpotLight3D — warm sodium-vapor cast, tilted outward from the wall ────────
func _build_light() -> void:
	var spot := SpotLight3D.new()
	spot.name = "Spot"
	spot.light_color = Color(1.0, 0.96, 0.86)
	spot.light_energy = light_energy
	spot.spot_range = spot_range
	spot.spot_angle = 35.0
	# SpotLight3D fires along its local -Z. We want the beam DOWN (node-local -Y)
	# when tilt = 0, then tilted outward from the wall (toward -Z in node-local)
	# by `tilt_down_deg`. Audit caught earlier sign error: +90° around +X maps
	# -Z to +Y (UP at the sky); we need -90° so -Z maps to -Y (DOWN at the yard).
	var down_basis  := Basis(Vector3.RIGHT, deg_to_rad(-90.0))
	var tilt_basis  := Basis(Vector3.RIGHT, deg_to_rad(tilt_down_deg))
	# Mount the spot at the housing centre so its beam emanates from the lens.
	var spot_pos := Vector3(0.0, 0.0, -ARM_LENGTH - housing_size.z * 0.5)
	spot.transform = Transform3D(tilt_basis * down_basis, spot_pos)
	add_child(spot)
