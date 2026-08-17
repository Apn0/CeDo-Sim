extends Node3D
class_name VerletRope3D

## High-performance Verlet-integration rope, hose, and wire simulator for Godot 4.
## Dynamically simulates flexible hydraulic hoses, hanging electrical drops,
## and bale tie wires with length constraints, gravity, and attachment anchors.

@export var start_anchor_path : NodePath
@export var end_anchor_path   : NodePath
@export var rope_length       : float = 2.5
@export var segment_count     : int = 12
@export var radius            : float = 0.015
@export var damping           : float = 0.95
@export var gravity_vec       : Vector3 = Vector3(0.0, -9.8, 0.0)
@export var iterations        : int = 6
@export var rope_color        : Color = Color(0.12, 0.12, 0.14) # black hydraulic hose

var _particles : Array[Vector3] = []
var _prev_pos  : Array[Vector3] = []
var _segment_len : float = 0.2

var _mesh_inst : MeshInstance3D = null
var _imm_mesh  : ImmediateMesh = null
var _mat       : StandardMaterial3D = null

var _start_node : Node3D = null
var _end_node   : Node3D = null

func _ready() -> void:
	if has_node(start_anchor_path):
		_start_node = get_node(start_anchor_path) as Node3D
	if has_node(end_anchor_path):
		_end_node = get_node(end_anchor_path) as Node3D

	_init_particles()
	_init_mesh()

func _init_particles() -> void:
	_particles.clear()
	_prev_pos.clear()
	_segment_len = rope_length / float(maxi(1, segment_count))

	var start_p : Vector3 = _start_node.global_position if _start_node else global_position
	var end_p   : Vector3 = _end_node.global_position if _end_node else (start_p + Vector3(0.0, -rope_length, 0.0))

	for i in (segment_count + 1):
		var t : float = float(i) / float(segment_count)
		var p : Vector3 = start_p.lerp(end_p, t)
		_particles.append(p)
		_prev_pos.append(p)

func _init_mesh() -> void:
	_imm_mesh = ImmediateMesh.new()
	_mesh_inst = MeshInstance3D.new()
	_mesh_inst.mesh = _imm_mesh
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = rope_color
	_mat.roughness = 0.65
	_mat.metallic = 0.1
	_mesh_inst.material_override = _mat
	# Set top level so mesh draws directly in world coordinates
	_mesh_inst.top_level = true
	add_child(_mesh_inst)

func _physics_process(delta: float) -> void:
	if _particles.size() < 2:
		return

	var start_target : Vector3 = _start_node.global_position if _start_node else global_position
	var end_target   : Vector3 = _end_node.global_position if _end_node else _particles[_particles.size() - 1]

	# 1. Verlet Integration step
	for i in range(1, segment_count):
		var cur : Vector3 = _particles[i]
		var prev : Vector3 = _prev_pos[i]
		var vel : Vector3 = (cur - prev) * damping
		_prev_pos[i] = cur
		_particles[i] = cur + vel + gravity_vec * (delta * delta)

	# Pin endpoints
	_particles[0] = start_target
	_particles[segment_count] = end_target

	# 2. Distance constraint relaxation
	for iter in iterations:
		_particles[0] = start_target
		_particles[segment_count] = end_target
		for i in segment_count:
			var p1 : Vector3 = _particles[i]
			var p2 : Vector3 = _particles[i + 1]
			var delta_p : Vector3 = p2 - p1
			var dist : float = delta_p.length()
			if dist > 0.0001:
				var diff : float = (dist - _segment_len) / dist
				var offset : Vector3 = delta_p * (0.5 * diff)
				if i != 0:
					_particles[i] += offset
				if i + 1 != segment_count:
					_particles[i + 1] -= offset

	# 3. Redraw ImmediateMesh ribbon/tube
	_redraw_mesh()

func _redraw_mesh() -> void:
	if _imm_mesh == null:
		return

	_imm_mesh.clear_surfaces()
	_imm_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)

	for i in (segment_count + 1):
		var p : Vector3 = _particles[i]
		var next_p : Vector3 = _particles[mini(i + 1, segment_count)]
		var dir : Vector3 = (next_p - p).normalized()
		var side : Vector3 = dir.cross(Vector3.UP).normalized()
		if side.length_squared() < 0.001:
			side = dir.cross(Vector3.FORWARD).normalized()

		_imm_mesh.surface_add_vertex(p - side * radius)
		_imm_mesh.surface_add_vertex(p + side * radius)

	_imm_mesh.surface_end()
