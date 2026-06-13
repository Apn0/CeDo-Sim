extends Node3D
class_name Sidewalk

## Procedural concrete paving strip that follows a polyline. Mirrors Road.gd's
## segment-by-segment construction but strips away painted lines and shoulders:
## just a clean slab of weathered concrete, slightly raised above surface_y to
## read as a curb-height step (~0.08 m).
##
## Caller passes in the waypoint Array via setup(...) before _ready(). Y values
## on the waypoints are ignored — the slab sits at surface_y + slab_height/2.
## Intended to run alongside the road polyline, offset perpendicularly by
## half-(road_width + shoulder_width) so the inner edge of the sidewalk meets
## the outer edge of the grass shoulder.
##
## At each interior bend a wedge filler is dropped so two segments meeting at
## an angle don't leave a triangular gap on the outside of the corner.

@export var sidewalk_width : float = 1.8
@export var slab_height    : float = 0.08
@export var surface_y      : float = 0.0

var _waypoints : Array = []  # Array[Vector3]

func setup(waypoints: Array) -> void:
	_waypoints = waypoints.duplicate()

func _ready() -> void:
	if _waypoints.size() < 2:
		push_warning("[Sidewalk] needs at least 2 waypoints — got %d" % _waypoints.size())
		return
	_build_segments()

func _build_segments() -> void:
	var concrete_mat := StandardMaterial3D.new()
	concrete_mat.albedo_color = Color(0.66, 0.64, 0.61)
	concrete_mat.roughness = 0.88
	for i in range(_waypoints.size() - 1):
		var a : Vector3 = _waypoints[i]
		var b : Vector3 = _waypoints[i + 1]
		_build_one_segment(a, b, concrete_mat, i)
	# Corner wedge fillers for interior bends
	for i in range(1, _waypoints.size() - 1):
		var prev : Vector3 = _waypoints[i - 1]
		var here : Vector3 = _waypoints[i]
		var next : Vector3 = _waypoints[i + 1]
		_build_corner_filler(prev, here, next, concrete_mat, i)

func _build_one_segment(a: Vector3, b: Vector3, concrete_mat: Material, idx: int) -> void:
	var dir2 := Vector2(b.x - a.x, b.z - a.z)
	var length := dir2.length()
	if length < 0.1:
		return
	var yaw : float = atan2(dir2.x, dir2.y)        # rotation about Y
	var mid : Vector3 = Vector3((a.x + b.x) * 0.5, surface_y, (a.z + b.z) * 0.5)
	var basis := Basis(Vector3.UP, yaw)
	var slab := MeshInstance3D.new()
	slab.name = "Sidewalk_Slab_%d" % idx
	var bm := BoxMesh.new()
	bm.size = Vector3(sidewalk_width, slab_height, length)
	slab.mesh = bm
	slab.transform = Transform3D(basis, mid + Vector3(0.0, slab_height * 0.5, 0.0))
	slab.material_override = concrete_mat
	add_child(slab)

func _build_corner_filler(prev: Vector3, here: Vector3, next: Vector3,
		concrete_mat: Material, idx: int) -> void:
	# Bisect the two segment yaws to align a square patch over the joint,
	# closing any triangular gap on the outside of the bend.
	var d_in := Vector2(here.x - prev.x, here.z - prev.z)
	var d_out := Vector2(next.x - here.x, next.z - here.z)
	if d_in.length() < 0.1 or d_out.length() < 0.1:
		return
	var yaw_in : float = atan2(d_in.x, d_in.y)
	var yaw_out : float = atan2(d_out.x, d_out.y)
	# If segments are colinear there is no gap to patch.
	if abs(wrapf(yaw_out - yaw_in, -PI, PI)) < 0.01:
		return
	var yaw_mid : float = yaw_in + wrapf(yaw_out - yaw_in, -PI, PI) * 0.5
	var basis := Basis(Vector3.UP, yaw_mid)
	var filler := MeshInstance3D.new()
	filler.name = "Sidewalk_Corner_%d" % idx
	var bm := BoxMesh.new()
	bm.size = Vector3(sidewalk_width, slab_height, sidewalk_width)
	filler.mesh = bm
	var pos : Vector3 = Vector3(here.x, surface_y + slab_height * 0.5, here.z)
	filler.transform = Transform3D(basis, pos)
	filler.material_override = concrete_mat
	add_child(filler)
