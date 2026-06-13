extends Node3D
class_name Road

## Procedural asphalt road that follows a centerline polyline. Used to model
## De Asselen Kuil and its turn into the CeDo plant lot (#134 / #135). Builds:
##  • Asphalt strip of width `road_width` along consecutive segments of the
##    polyline (one BoxMesh per segment + a wedge filler at each corner).
##  • Center dashed white line (every other dash mesh) running along each segment.
##  • Solid white edge stripes on both sides.
##  • Grass shoulders flanking each segment.
##
## Input: an Array of Vector3 waypoints (Y is ignored — road is at y = surface_y).
## Operator drops waypoints clicking on the WorldSetup satellite overlay later;
## hardcoded defaults from the satellite imagery cover MainWorld for now.

@export var road_width      : float = 6.5
@export var lane_count      : int   = 2
@export var dash_length     : float = 2.5
@export var dash_gap        : float = 4.0
@export var edge_stripe_w   : float = 0.12
@export var shoulder_width  : float = 1.4
@export var surface_y       : float = 0.0
@export var paint_y_offset  : float = 0.012

var _waypoints : Array = []  # Array[Vector3]

func setup(waypoints: Array) -> void:
	_waypoints = waypoints.duplicate()

func _ready() -> void:
	if _waypoints.size() < 2:
		push_warning("[Road] needs at least 2 waypoints — got %d" % _waypoints.size())
		return
	_build_segments()

func _build_segments() -> void:
	var asphalt_mat := StandardMaterial3D.new()
	asphalt_mat.albedo_color = Color(0.12, 0.12, 0.13)
	asphalt_mat.roughness = 0.93
	var paint_mat := StandardMaterial3D.new()
	paint_mat.albedo_color = Color(0.95, 0.95, 0.92)
	paint_mat.roughness = 0.55
	var grass_mat := StandardMaterial3D.new()
	grass_mat.albedo_color = Color(0.36, 0.48, 0.22)
	grass_mat.roughness = 0.96
	for i in range(_waypoints.size() - 1):
		var a : Vector3 = _waypoints[i]
		var b : Vector3 = _waypoints[i + 1]
		_build_one_segment(a, b, asphalt_mat, paint_mat, grass_mat, i)

func _build_one_segment(a: Vector3, b: Vector3, asphalt_mat: Material,
		paint_mat: Material, grass_mat: Material, idx: int) -> void:
	var dir2 := Vector2(b.x - a.x, b.z - a.z)
	var length := dir2.length()
	if length < 0.1:
		return
	var yaw : float = atan2(dir2.x, dir2.y)        # rotation about Y
	var mid : Vector3 = Vector3((a.x + b.x) * 0.5, surface_y, (a.z + b.z) * 0.5)
	var basis := Basis(Vector3.UP, yaw)
	# Asphalt strip
	var asphalt := MeshInstance3D.new()
	asphalt.name = "Road_Asphalt_%d" % idx
	var bm := BoxMesh.new()
	bm.size = Vector3(road_width, 0.06, length)
	asphalt.mesh = bm
	asphalt.transform = Transform3D(basis, mid + Vector3(0.0, -0.03, 0.0))
	asphalt.material_override = asphalt_mat
	add_child(asphalt)
	# Grass shoulders on both sides
	for side in [-1, 1]:
		var grass := MeshInstance3D.new()
		grass.name = "Road_Grass_%d_%s" % [idx, "L" if side == -1 else "R"]
		var gm := BoxMesh.new()
		gm.size = Vector3(shoulder_width, 0.04, length)
		grass.mesh = gm
		var grass_offset : Vector3 = basis * Vector3(float(side) * (road_width * 0.5 + shoulder_width * 0.5), -0.02, 0.0)
		grass.transform = Transform3D(basis, mid + grass_offset)
		grass.material_override = grass_mat
		add_child(grass)
	# Edge stripes (solid white) along both sides of the asphalt
	for side in [-1, 1]:
		var stripe := MeshInstance3D.new()
		stripe.name = "Road_EdgeStripe_%d_%s" % [idx, "L" if side == -1 else "R"]
		var sm := BoxMesh.new()
		sm.size = Vector3(edge_stripe_w, 0.005, length)
		stripe.mesh = sm
		var off : Vector3 = basis * Vector3(float(side) * (road_width * 0.5 - edge_stripe_w * 0.5), paint_y_offset, 0.0)
		stripe.transform = Transform3D(basis, mid + off)
		stripe.material_override = paint_mat
		add_child(stripe)
	# Center dashed line (only if this is a two-lane road)
	if lane_count >= 2:
		var period : float = dash_length + dash_gap
		var n_dashes : int = int(floor(length / period))
		for d in n_dashes:
			var dash := MeshInstance3D.new()
			dash.name = "Road_Dash_%d_%d" % [idx, d]
			var dm := BoxMesh.new()
			dm.size = Vector3(edge_stripe_w, 0.005, dash_length)
			dash.mesh = dm
			var t : float = (float(d) * period + dash_length * 0.5) - length * 0.5
			var off : Vector3 = basis * Vector3(0.0, paint_y_offset, t)
			dash.transform = Transform3D(basis, mid + off)
			dash.material_override = paint_mat
			add_child(dash)
