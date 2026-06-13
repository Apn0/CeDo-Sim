extends Car
class_name VWGolfMk6

## VW Golf (mk6-ish) — Mohammed's car (#134). Body comes from the multi-car
## traffic pack GLB, which packs 10 cars (206, Hiace, Avensis, Astra, Golf, A3,
## AClass, Almera, Clio, Vectra) into one scene. Load filter keeps the "Golf"
## body + its 4 nearest "wheel.*" nodes by proximity, then frees the other 9
## cars before they're ever drawn.
##
## NOTE — single body mesh: this pack ships each car as ONE mesh + 4 wheels.
## So this Golf gets spinning wheels + driveable + engine audio + paint tint,
## but doors don't open and glass isn't separately alpha-blended. Same
## limitation the OBJs would have had. Acceptable as an NPC parking-lot car;
## the player drives the Swift (full articulation).

const MODEL_PATH := "res://assets/models/traffic_cars_pack/ambulancesimulator_cars.glb"
const TARGET_NODE_NAME := "Golf"
# Other car-body names in the pack — anything matching this gets freed at load.
const OTHER_CARS := ["206", "Hiace", "Avensis", "Astra", "A3", "AClass", "Almera", "Clio", "Vectra"]

func _ready() -> void:
	super._ready()
	vehicle_type   = "vw_golf_mk6"
	speed_limit_kmh = 80.0
	engine_power_kw = 75.0
	fuel_capacity_l = 55.0
	_model_path    = MODEL_PATH
	_part_names    = DEFAULT_PART_NAMES
	_paint_color   = Color(0.32, 0.34, 0.36)   # dark gray (the 2008 Polo's color)
	# Traffic pack labels each car's body material by car name, not "carpaint".
	# Tell the paint matcher to also accept "golf" so the tint actually applies.
	_paint_extra_match = ["golf"]
	load_model()

## #157 — Runs BEFORE classifier (was AFTER, which let proximity-based wheel
## articulation steal wheels from neighbouring cars in the pack. Bug only
## "worked" on Golf by coincidence — Volvo (Astra) and BMW (AClass) demonstrated
## the failure). Frees the 9 non-target car bodies; their child wheels go too.
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
