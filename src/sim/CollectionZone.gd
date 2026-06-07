extends Area3D
class_name CollectionZone

@export var freeze_instead_of_free: bool = false
var scrap_count: int = 0

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node3D) -> void:
	if body is RigidBody3D and body.is_in_group("film_scrap"):
		scrap_count += 1

		if freeze_instead_of_free:
			body.freeze = true
			# Optionally remove it from the group so it's not blown anymore
			body.remove_from_group("film_scrap")
		else:
			body.queue_free()
