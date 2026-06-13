extends Node3D
class_name Crosswalk

## White zebra-striped pedestrian crossing. Caller positions this node at the
## centre of the crossing and rotates it (Y-yaw) so that the local +Z axis
## aligns with the traffic (lane) direction — the bars are then laid out
## perpendicular to +Z, exactly like real road paint.
##
## Caller-passed parameters (all optional, sensible defaults):
##   bar_length     — span across the road (perpendicular to traffic), in m
##   bar_width      — stripe width along the traffic direction, in m
##   bar_gap        — gap between stripes along the traffic direction, in m
##   bar_count      — number of white stripes
##   surface_y      — asphalt top Y (matches Road.gd / StaffParking.gd)
##   paint_y_offset — small lift above surface_y to dodge z-fighting (~0.012)
##
## Full crossing footprint:
##   width  (along +Z, traffic dir) = bar_count*(bar_width+bar_gap) - bar_gap
##   length (across the road, X)    = bar_length
##
## Paint material matches Road.gd's paint_mat for visual consistency
## (Color(0.95, 0.95, 0.92), roughness 0.55).

@export var bar_length     : float = 4.0   # span across the road (perpendicular to traffic)
@export var bar_width      : float = 0.45  # along traffic direction
@export var bar_gap        : float = 0.45
@export var bar_count      : int   = 6
@export var surface_y      : float = 0.0
@export var paint_y_offset : float = 0.012

func setup(bar_count_in: int = 6) -> void:
	bar_count = bar_count_in

func _ready() -> void:
	if bar_count <= 0:
		push_warning("[Crosswalk] bar_count must be > 0 — got %d" % bar_count)
		return
	_build_stripes()

func _build_stripes() -> void:
	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = Color(0.95, 0.95, 0.92)
	paint_mat.roughness = 0.55
	paint_mat.metallic = 0.0
	var period : float = bar_width + bar_gap
	var total_width : float = float(bar_count) * period - bar_gap
	# Centre the run along local Z so the crossing's midpoint sits at the node origin.
	var z0 : float = -total_width * 0.5 + bar_width * 0.5
	for i in bar_count:
		var stripe := MeshInstance3D.new()
		stripe.name = "Stripe_%d" % i
		var bm := BoxMesh.new()
		bm.size = Vector3(bar_length, 0.005, bar_width)
		stripe.mesh = bm
		var z : float = z0 + float(i) * period
		stripe.position = Vector3(0.0, surface_y + paint_y_offset, z)
		stripe.material_override = paint_mat
		add_child(stripe)
