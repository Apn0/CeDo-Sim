extends Car
class_name VolvoV40Placeholder

## Vincent's car — black previous-gen Volvo V40 mk2 (~2012-2018).
## PLACEHOLDER: reuses the traffic_cars_pack's "Astra" body (Opel/Vauxhall
## hatchback, same C-segment as a V40 mk2) tinted black. Same single-mesh
## limitation as the Golf — wheels spin, doors don't open.
##
## Replace by dropping a real Volvo V40 mk2 GLB into
## res://assets/models/volvo_v40_mk2/ and updating MODEL_PATH + TARGET_NODE_NAME
## (and adjust _model_scale if proportions differ).

const MODEL_PATH := "res://assets/models/traffic_cars_pack/ambulancesimulator_cars.glb"
const TARGET_NODE_NAME := "Astra"
const OTHER_CARS := ["206", "Hiace", "Avensis", "Golf", "A3", "AClass", "Almera", "Clio", "Vectra"]

func _ready() -> void:
	super._ready()
	vehicle_type    = "volvo_v40_placeholder"
	speed_limit_kmh = 85.0
	engine_power_kw = 88.0
	fuel_capacity_l = 50.0
	_model_path     = MODEL_PATH
	_part_names     = DEFAULT_PART_NAMES
	_paint_color    = Color(0.05, 0.05, 0.06)   # black
	_real_world_length_m = 4.37   # Volvo V40 II = 4.37 m
	_paint_extra_match = ["astra"]               # pack labels body material by car name
	load_model()

## #157 — Runs BEFORE classifier. Frees the 9 non-target car bodies; wheels
## are children of bodies in this GLB so they're freed transitively. Result:
## only the target car (body + 4 wheels) remains for articulation.
func _filter_imported_tree(root: Node) -> void:
	_free_other_cars(root)

func _free_other_cars(n: Node) -> void:
	var kids : Array = n.get_children().duplicate()
	for c in kids:
		if String(c.name) in OTHER_CARS:
			# Detach IMMEDIATELY so the classifier walk that runs next this
			# frame doesn't see it. queue_free() alone is deferred and the
			# node would still be visible mid-frame.
			n.remove_child(c)
			c.queue_free()
		else:
			_free_other_cars(c)
