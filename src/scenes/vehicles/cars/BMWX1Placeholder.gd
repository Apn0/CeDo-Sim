extends Car
class_name BMWX1Placeholder

## Peter's car — white BMW X1/X3 (production manager's car).
## PLACEHOLDER: traffic_cars_pack has no BMW; using the AClass (Mercedes
## A-Class) body painted white as the closest premium-segment stand-in.
## Replace by dropping a real BMW GLB into res://assets/models/bmw_x1/.

const MODEL_PATH := "res://assets/models/traffic_cars_pack/ambulancesimulator_cars.glb"
const TARGET_NODE_NAME := "AClass"
const OTHER_CARS := ["206", "Hiace", "Avensis", "Astra", "Golf", "A3", "Almera", "Clio", "Vectra"]

func _ready() -> void:
	# BMW X1 — punchier than the fleet base but #223 real: 7.5 m/s² was ~3× a
	# real SUV; ~0-100 in ~8.5 s ≈ 3.3 m/s². Tau stays at the Car default (0.6 s).
	throttle_accel_mps2 = 3.3
	super._ready()
	vehicle_type    = "bmw_x1_placeholder"
	speed_limit_kmh = 95.0
	engine_power_kw = 110.0
	fuel_capacity_l = 58.0
	_model_path     = MODEL_PATH
	_part_names     = DEFAULT_PART_NAMES
	_paint_color    = Color(0.94, 0.94, 0.93)   # off-white
	_real_world_length_m = 4.46   # BMW X1 E84 = 4.46 m
	_paint_extra_match = ["aclass"]              # pack labels body material by car name
	load_model()

## #157 — Runs BEFORE classifier. Frees the 9 non-target car bodies; wheels
## are children of bodies in this GLB so they're freed transitively.
func _filter_imported_tree(root: Node) -> void:
	_free_other_cars(root)

func _free_other_cars(n: Node) -> void:
	var kids : Array = n.get_children().duplicate()
	for c in kids:
		if String(c.name) in OTHER_CARS:
			n.remove_child(c)     # detach immediately so the classifier doesn't see it
			c.queue_free()
		else:
			_free_other_cars(c)
