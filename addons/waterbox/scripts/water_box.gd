# godot-waterbox
# By Adisoreq

# === Metadata === #

@tool
@icon("res://addons/waterbox/assets/icons/waterbox.svg")
class_name WaterBox
extends Node3D

# === Description === #

## A 3D water physics simulation node.
##
## [b]WaterBox[/b] automatically applies buoyancy and drag forces to any [RigidBody3D] 
## entering its associated [Area3D] volume. It supports advanced multi-point buoyancy 
## via [BuoyancyComponent] as well as a simplified fallback behavior for standard bodies.

# === Variables === #

var _gravity = 0.0;
var _submerged_bodies: Array[Node3D] = []

## The [Area3D] node defining the physical boundaries of the water simulation. Required for collision detection.
var water_area: Area3D = null

@export_group("Physics Settings", "water_")

## If [code]true[/code], the script will ignore objects that do not contain a [BuoyancyComponent].
@export var require_buoyancy_component: bool = false

## Specifies the density of the water, affecting the overall upward buoyancy force. Higher values push objects up harder.
@export_range(0.1, 10.0, 0.05) var water_density: float = 1.0

## Specifies the drag force of the water, dampening both linear and angular velocities of submerged objects.
@export_range(0.0, 1.0, 0.01) var water_drag: float = 0.5

# === Events === #

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	
	_gravity = ProjectSettings.get_setting("physics/3d/default_gravity", 9.81)
	_init_components()	


func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and not _submerged_bodies.has(body):
		_submerged_bodies.append(body)


func _on_body_exited(body: Node3D) -> void:
	_submerged_bodies.erase(body)


# === Functions === #

## Finds a child [Area3D] node and connects body enter/exit signals for tracking.
func _init_components() -> void:
	for child in get_children():
		if (child is Area3D):
			water_area = child
			
	if (water_area == null):
		push_warning("WaterBox '%s' needs and Area3D node for collision checking." % get_node(".").name)
		
	water_area.body_entered.connect(_on_body_entered)
	water_area.body_exited.connect(_on_body_exited)	


func _physics_process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
		
	for body in _submerged_bodies:
		if body is RigidBody3D:
			var buoyancy_comp = body.get_node_or_null("BuoyancyComponent")
			
			if buoyancy_comp == null:
				buoyancy_comp = body.get_parent().get_node_or_null("BuoyancyComponent")
			
			if buoyancy_comp and buoyancy_comp is BuoyancyComponent:
				_apply_component_buoyancy(body, buoyancy_comp, delta)
				
			elif !buoyancy_comp and !require_buoyancy_component:
				_apply_fallback_buoyancy(body, delta)
				
			elif !buoyancy_comp:
				pass


## Calculates and applies multi-point buoyancy force based on individual component points.[br][br]
## [b]Parameters:[/b][br]
## [param body] – The [RigidBody3D] object currently under control of WaterBox physics.[br]
## [param component] – The [BuoyancyComponent] containing the defined buoyancy points.
func _apply_component_buoyancy(body: RigidBody3D, component: BuoyancyComponent, delta: float) -> void:
	var water_top_y = _get_water_top_y()
	var points = component.buoyancy_points
	
	if not component.use_buoyancy_points or points.is_empty():
		_apply_fallback_buoyancy(body, delta)
		return
		
	var total_points_count = points.size()
	
	for point in points:
		var global_point_pos = point.global_position
		var depth = water_top_y - global_point_pos.y

		if depth > 0:
			var buoyancy_magnitude = depth * water_density * _gravity / total_points_count
			var force_vector = Vector3.UP * buoyancy_magnitude
			var relative_pos = global_point_pos - body.global_position
			
			body.apply_force(force_vector, relative_pos)
			
	body.linear_velocity *= (1.0 - water_drag * delta)
	body.angular_velocity *= (1.0 - water_drag * delta)


## Simplified fallback buoyancy algorithm that applies a single upward force to the object's center of mass.[br][br]
## Triggered when the object lacks a [BuoyancyComponent] or has no points defined.[br][br]
## [b]Parameters:[/b][br]
## [param body] – The [RigidBody3D] object currently under control of WaterBox physics.
func _apply_fallback_buoyancy(body: RigidBody3D, delta: float) -> void:
	var water_top_y = _get_water_top_y()
	var depth = water_top_y - body.global_position.y
	
	if depth > 0:
		var buoyancy_force = Vector3.UP * (depth * water_density * _gravity)
		body.apply_force(buoyancy_force)
		body.linear_velocity *= (1.0 - water_drag * delta)


## Returns the global Y coordinate of the water surface (the top edge of the [Area3D] collision shape).
func _get_water_top_y() -> float:
	var shape_owner = water_area.get_shape_owners()[0]
	var shape = water_area.shape_owner_get_shape(shape_owner, 0)
	var water_aabb = shape.get_debug_mesh().get_aabb()
	return water_area.global_transform.origin.y + (water_aabb.size.y * 0.5 * water_area.global_transform.basis.y.y)
