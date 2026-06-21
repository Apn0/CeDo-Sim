extends Car
class_name FordKa2003

## Ford Ka 2003 in sunset orange — Abdellilah's car (#134), confirmed by the
## operator's own Google Maps satellite of the CeDo staff parking lot (the
## sunset-orange Ka was visible in the left-row top slot).

const MODEL_PATH := "res://assets/models/ford_ka_2003/ford_ka.glb"

func _ready() -> void:
	# Ford Ka Mk1 — 44 kW small hatch, softer accel per the audit (5.0 m/s²).
	throttle_accel_mps2 = 5.0
	super._ready()
	vehicle_type   = "ford_ka_2003"
	speed_limit_kmh = 65.0
	engine_power_kw = 44.0
	fuel_capacity_l = 35.0
	_model_path    = MODEL_PATH
	_part_names    = DEFAULT_PART_NAMES
	# Sunset orange (warm, not vibrant — Ford "Tango Red" / "Magma" feel).
	_paint_color   = Color(0.92, 0.46, 0.18)
	_real_world_length_m = 3.62   # Ford Ka Mk1 = 3.62 m
	# Pitch correction for the shared `ford_ka.glb` asset (operator reported
	# nose-down). I cannot run the game to verify the sign visually — operator
	# tunes this number directly in this file. Try one of:
	#     0.0    — leave as-imported (current default)
	#     90.0   — rotate front bumper UP if asset imports nose-down
	#    -90.0   — rotate front bumper DOWN if 90.0 overshoots and it's now nose-UP
	#   180.0   — flip upside-down (rare)
	# The applied value is printed at load so you can confirm what's running.
	# F10 feedback 20260621: the GLB exports Y-up while Godot is Z-up, so
	# without correction the chassis pitches ~90° nose-down on spawn. -90°
	# rotates it back to upright. Same value applies to Pascal's Streetka.
	_model_pitch_correction_deg = -90.0
	load_model()
