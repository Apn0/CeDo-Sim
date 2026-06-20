extends Car
class_name FordStreetka

## Pascal's car — black Ford Streetka droptop. Reuses Abdellilah's Ford Ka 2003
## GLB asset (FordKa2003.gd) but Y-scaled to 0.85 so it reads as the lower
## convertible/droptop variant, and painted black instead of sunset orange.
## Same wheel layout, same articulation (or lack thereof — single-mesh import).

const MODEL_PATH := "res://assets/models/ford_ka_2003/ford_ka.glb"

func _ready() -> void:
	super._ready()
	vehicle_type    = "ford_streetka"
	speed_limit_kmh = 60.0
	engine_power_kw = 44.0
	fuel_capacity_l = 35.0
	_model_path     = MODEL_PATH
	_part_names     = DEFAULT_PART_NAMES
	# Squish 15 % on Y — the Streetka rides lower than the regular Ka. Same
	# silhouette otherwise. Suspension stiffness in the .tscn is unchanged so
	# the wheels still articulate against the shorter body.
	_model_scale    = Vector3(1.0, 0.85, 1.0)
	# Black paint — Pascal's car.
	_paint_color    = Color(0.05, 0.05, 0.06)
	_real_world_length_m = 3.62   # Ford Streetka = Ka chassis = 3.62 m
	load_model()
