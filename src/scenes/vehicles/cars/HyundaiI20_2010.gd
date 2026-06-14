extends Car
class_name HyundaiI20_2010

## White Hyundai i20 2010 — Roman's car (#134). Thin per-car subclass:
## sets model path + paint + powertrain stats, base Car.gd does the rest.

const MODEL_PATH := "res://assets/models/hyundai_i20_2010/hyundai_i20_2010.glb"

func _ready() -> void:
	super._ready()
	vehicle_type   = "hyundai_i20_2010"
	speed_limit_kmh = 70.0
	engine_power_kw = 55.0
	fuel_capacity_l = 45.0
	_model_path    = MODEL_PATH
	_part_names    = DEFAULT_PART_NAMES
	_paint_color   = Color(0.92, 0.93, 0.93)   # off-white
	_real_world_length_m = 3.94   # Hyundai i20 PB (2010) = 3.94 m
	load_model()
