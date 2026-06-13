extends Car
class_name FordKa2003

## Ford Ka 2003 in sunset orange — Abdellilah's car (#134), confirmed by the
## operator's own Google Maps satellite of the CeDo staff parking lot (the
## sunset-orange Ka was visible in the left-row top slot).

const MODEL_PATH := "res://assets/models/ford_ka_2003/ford_ka.glb"

func _ready() -> void:
	super._ready()
	vehicle_type   = "ford_ka_2003"
	speed_limit_kmh = 65.0
	engine_power_kw = 44.0
	fuel_capacity_l = 35.0
	_model_path    = MODEL_PATH
	_part_names    = DEFAULT_PART_NAMES
	# Sunset orange (warm, not vibrant — Ford "Tango Red" / "Magma" feel).
	_paint_color   = Color(0.92, 0.46, 0.18)
	load_model()
