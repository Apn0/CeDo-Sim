extends Node3D
class_name LeafBlower

@export var max_force: float = 50.0
@export var max_range: float = 10.0
@export var spool_time_seconds: float = 1.0

var _state: int = State.OFF
var _current_spool: float = 0.0
var _active_bodies: Array[RigidBody3D] = []

@onready var wind_area: Area3D = $WindArea
@onready var raycast: RayCast3D = $RayCast3D

enum State {
	OFF,
	SPOOLING_UP,
	FULL_THROTTLE
}

func _ready() -> void:
	wind_area.body_entered.connect(_on_body_entered)
	wind_area.body_exited.connect(_on_body_exited)

func turn_on() -> void:
	if _state == State.OFF:
		_state = State.SPOOLING_UP

func turn_off() -> void:
	_state = State.OFF
	_current_spool = 0.0

func _physics_process(delta: float) -> void:
	if _state == State.OFF:
		return

	if _state == State.SPOOLING_UP:
		_current_spool += delta / spool_time_seconds
		if _current_spool >= 1.0:
			_current_spool = 1.0
			_state = State.FULL_THROTTLE

	var current_force_mag := max_force * _current_spool

	for body in _active_bodies:
		if not is_instance_valid(body) or not body.is_inside_tree():
			continue

		var dir_to_body := global_position.direction_to(body.global_position)
		var dist_to_body := global_position.distance_to(body.global_position)

		if dist_to_body > max_range:
			continue

		# Check for occlusion via raycast
		raycast.global_position = global_position
		raycast.target_position = raycast.to_local(body.global_position)
		raycast.force_raycast_update()

		if raycast.is_colliding():
			var collider := raycast.get_collider()
			if collider != body:
				# Occluded by something else (e.g., machine/wall)
				continue

		# Inverse-square attenuation. Add 1.0 to prevent division by zero near origin.
		var attenuation := 1.0 / (1.0 + (dist_to_body * dist_to_body))
		var applied_force := dir_to_body * current_force_mag * attenuation

		body.apply_central_force(applied_force)

func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("film_scrap"):
		if body not in _active_bodies:
			_active_bodies.append(body as RigidBody3D)

func _on_body_exited(body: Node3D) -> void:
	if body is RigidBody3D:
		_active_bodies.erase(body as RigidBody3D)
