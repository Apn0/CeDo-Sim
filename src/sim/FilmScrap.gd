extends RigidBody3D
class_name FilmScrap

func _ready() -> void:
	# Constraints: Extremely low mass, high linear and angular dampening
	mass = 0.05
	linear_damp = 5.0
	angular_damp = 5.0

	# Ensure low friction and zero bounce via PhysicsMaterial
	var mat := PhysicsMaterial.new()
	mat.friction = 0.1
	mat.bounce = 0.0
	physics_material_override = mat

	# Add to a group for the collection zone to identify
	add_to_group("film_scrap")
