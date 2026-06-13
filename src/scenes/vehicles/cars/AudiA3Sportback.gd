extends Car
class_name AudiA3Sportback

## Audi A3 Sportback — Emrah's car (#134). Color left at the GLB's default
## (operator can adjust _paint_color if a specific shade is wanted later).

const MODEL_PATH := "res://assets/models/audi_a3_sportback/audi_a3_sportback.glb"

func _ready() -> void:
	super._ready()
	vehicle_type   = "audi_a3_sportback"
	speed_limit_kmh = 90.0
	engine_power_kw = 90.0
	fuel_capacity_l = 55.0
	_model_path    = MODEL_PATH
	_part_names    = DEFAULT_PART_NAMES
	_paint_color   = Color(1, 1, 1, 0)         # leave factory paint
	load_model()
