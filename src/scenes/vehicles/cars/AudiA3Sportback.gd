extends Car
class_name AudiA3Sportback

## Audi A3 Sportback — Emrah's car (#134). Color left at the GLB's default
## (operator can adjust _paint_color if a specific shade is wanted later).

const MODEL_PATH := "res://assets/models/audi_a3_sportback/audi_a3_sportback.glb"

func _ready() -> void:
	# Audi A3 — premium hatch, slightly quicker than the fleet base. #223: 7.5 m/s²
	# was ~3× real; a warm hatch does ~0-100 in ~9 s ≈ 3.1 m/s².
	throttle_accel_mps2 = 3.1
	super._ready()
	vehicle_type   = "audi_a3_sportback"
	speed_limit_kmh = 90.0
	engine_power_kw = 90.0
	fuel_capacity_l = 55.0
	_model_path    = MODEL_PATH
	_part_names    = DEFAULT_PART_NAMES
	_paint_color   = Color(1, 1, 1, 0)         # leave factory paint
	_real_world_length_m = 4.34   # Audi A3 Sportback 2013 = 4.34 m
	load_model()
