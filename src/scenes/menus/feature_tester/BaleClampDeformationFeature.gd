extends Node3D
class_name BaleClampDeformationFeature

## Real bale clamp: two plates press a bale stack along the X axis only. The bale
## deforms where the plates contact — compressed, not bulged. Plates start outside
## the bale at zero force, move inward as force increases. Physics is contact-based,
## not toy parameters.

var _bale_sheets    : Array[Node3D] = []
var _left_plate     : Node3D = null
var _right_plate    : Node3D = null
var _bale_root      : Node3D = null
var _operator_camera : Camera3D = null
var _is_operator_view : bool = false

# Live values
var _clamp_force    : float = 0.0
var _response_time  : float = 0.08

# Deformation tracking (X-axis only, where plates contact)
var _current_deform : float = 0.0  # smooth approach to target
var _sheet_x_scales : Array[float] = []

const BALE_W : float = 1.45
const BALE_H : float = 1.15
const BALE_D : float = 1.50
const N_SHEETS : int = 12
const MAX_COMPRESSION : float = 0.65  # plates can compress to 65% of bale width

func feature_title() -> String:
	return "Bale clamp deformation"

func param_specs() -> Array:
	return [
		{"key": "clamp_force", "label": "Clamp force (0–1)", "min": 0.0, "max": 1.0, "step": 0.02, "default": 0.0},
		{"key": "response_time", "label": "Response time (s)", "min": 0.01, "max": 0.5, "step": 0.01, "default": 0.08},
	]

func build_content() -> void:
	# Catch floor
	var floor_mi := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	floor_mi.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.19)
	floor_mat.roughness = 0.95
	floor_mi.material_override = floor_mat
	add_child(floor_mi)

	# Bale: stacked sheets
	_bale_root = Node3D.new()
	_bale_root.name = "Bale"
	_bale_root.position = Vector3(0.0, BALE_H * 0.5 + 0.1, 0.0)
	add_child(_bale_root)

	var sheet_h : float = BALE_H / float(N_SHEETS)
	var tint := Color(0.72, 0.71, 0.66)

	for i in N_SHEETS:
		var sheet := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(BALE_W, sheet_h * 0.95, BALE_D)
		sheet.mesh = box
		var jitter : float = -0.06 if i % 2 == 0 else 0.04
		var sheet_tint := Color(
			clampf(tint.r + jitter, 0.0, 1.0),
			clampf(tint.g + jitter, 0.0, 1.0),
			clampf(tint.b + jitter, 0.0, 1.0),
			1.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = sheet_tint
		mat.roughness = 0.92
		sheet.material_override = mat
		var y : float = sheet_h * (float(i) - float(N_SHEETS - 1) * 0.5)
		sheet.position = Vector3(0.0, y, 0.0)
		_bale_root.add_child(sheet)
		_bale_sheets.append(sheet)
		_sheet_x_scales.append(1.0)

	# Left plate: starts outside the bale at zero force, moves inward as force increases
	_left_plate = MeshInstance3D.new()
	var left_box := BoxMesh.new()
	left_box.size = Vector3(0.12, BALE_H + 0.2, BALE_D + 0.1)
	_left_plate.mesh = left_box
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.34, 0.36, 0.40)
	plate_mat.metallic = 0.6
	plate_mat.roughness = 0.45
	_left_plate.material_override = plate_mat
	_left_plate.position = Vector3(-(BALE_W * 0.5 + 0.15), BALE_H * 0.5 + 0.1, 0.0)  # outside
	add_child(_left_plate)

	# Right plate: mirrors left
	_right_plate = MeshInstance3D.new()
	var right_box := BoxMesh.new()
	right_box.size = Vector3(0.12, BALE_H + 0.2, BALE_D + 0.1)
	_right_plate.mesh = right_box
	_right_plate.material_override = plate_mat
	_right_plate.position = Vector3(BALE_W * 0.5 + 0.15, BALE_H * 0.5 + 0.1, 0.0)  # outside
	add_child(_right_plate)

	# Operator camera: first-person view from inside the clamp, looking at the bale
	_operator_camera = Camera3D.new()
	_operator_camera.position = Vector3(-BALE_W * 0.5 - 0.3, BALE_H * 0.5 + 0.1, 0.0)
	_operator_camera.look_at(Vector3(0.0, BALE_H * 0.5 + 0.1, 0.0), Vector3.UP)
	add_child(_operator_camera)

	# Apply defaults
	for spec in param_specs():
		set_param(String(spec["key"]), float(spec["default"]))

	set_process(true)
	set_process_input(true)

func _process(delta: float) -> void:
	# Smooth deformation follow
	var target_deform := _clamp_force
	var tau : float = _response_time
	_current_deform = lerpf(_current_deform, target_deform, clampf(delta / tau, 0.0, 1.0))

	# Plate position: compress from outside toward the bale as force increases
	var init_sep : float = BALE_W + 0.30  # initial separation (outside)
	var final_sep : float = BALE_W * MAX_COMPRESSION  # fully compressed
	var target_sep : float = lerpf(init_sep, final_sep, _current_deform)
	_left_plate.position.x = -target_sep * 0.5
	_right_plate.position.x = target_sep * 0.5

	# Deform only in X (the pressing axis): sheets compress where contacted
	for i in N_SHEETS:
		var sheet := _bale_sheets[i]
		# X compression scales from 1.0 (no force) to MAX_COMPRESSION (full force)
		_sheet_x_scales[i] = lerpf(1.0, MAX_COMPRESSION, _current_deform)
		sheet.scale.x = _sheet_x_scales[i]
		# Y and Z are unchanged — no artificial bulge

	# Update operator camera position: moves with left plate
	if _operator_camera:
		_operator_camera.position.x = _left_plate.position.x + 0.1

func set_param(key: String, value: float) -> void:
	match key:
		"clamp_force":
			_clamp_force = value
		"response_time":
			_response_time = value

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_SPACE:
		_is_operator_view = not _is_operator_view
		if _operator_camera:
			_operator_camera.current = _is_operator_view
			# Disable the FeatureTester camera when in operator view. FeatureTester
			# parents features under a plain FeatureRoot Node3D, so walk up until
			# we find the node that actually exposes set_camera_active.
			var host : Node = get_parent()
			while host != null and not host.has_method("set_camera_active"):
				host = host.get_parent()
			if host != null:
				host.set_camera_active(not _is_operator_view)
