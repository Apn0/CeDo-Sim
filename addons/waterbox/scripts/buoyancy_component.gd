# godot-waterbox
# By Adisoreq

# === Metadata === #

class_name BuoyancyComponent
extends Node3D

# === Description === #

## A component that defines multi-point buoyancy behavior for a [RigidBody3D].
##
## [b]BuoyancyComponent[/b] works hand-in-hand with [WaterBox]. It allows you to place 
## [Marker3D] nodes inside this component to act as individual flotation points (e.g., the four corners of a boat). 
## If no points are manually assigned, it will automatically search its children for [Marker3D] nodes at runtime.

# === Variables === #

## If [code]true[/code], [WaterBox] will use the multi-point array for calculations. If [code]false[/code], it defaults to fallback behavior.
@export var use_buoyancy_points: bool = true

## An array of [Marker3D] nodes representing the distribution of buoyancy forces across the object.
@export var buoyancy_points: Array[Marker3D] = []

# === Events === #

func _ready() -> void:
	if buoyancy_points.is_empty():
		_auto_discover_points()
		
	if not (get_parent() is RigidBody3D):
		push_warning("BuoyancyComponent should be child of the RigidBody3D object.")

# === Functions === #

## Automatically scans the component's direct children for [Marker3D] nodes and adds them to [member buoyancy_points] if empty.
func _auto_discover_points() -> void:
	for child in get_children():
		if child is Marker3D:
			buoyancy_points.append(child)
			
	if buoyancy_points.is_empty():
		push_warning("BuoyancyComponent for object '%s' has no buoyancy markers!" % get_parent().name)


## Returns [code]true[/code] if the component contains at least one buoyancy marker.
func has_points() -> bool:
	return !buoyancy_points.is_empty()
