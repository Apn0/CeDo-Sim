extends Node3D
class_name DayNightCycle

## Dynamic 24-hour Day/Night cycle controller.
## Drives sun elevation, azimuth, procedural sky colors, and ambient lighting
## based on the in-game ShiftClock.

@export var latitude_deg : float = 51.5 # Netherlands latitude
@export var sunrise_hour : float = 6.25 # 06:15
@export var sunset_hour  : float = 21.5 # 21:30

var _sun         : DirectionalLight3D = null
var _world_env   : WorldEnvironment   = null
var _sky_mat     : ProceduralSkyMaterial = null
var _shift_clock : Node = null

var is_night     : bool = false
signal is_night_changed(night: bool)

func _ready() -> void:
	add_to_group("day_night_cycle")
	call_deferred("_bind_nodes")

func setup(p_sun: DirectionalLight3D, p_env: WorldEnvironment, p_clock: Node) -> void:
	_sun = p_sun
	_world_env = p_env
	_shift_clock = p_clock
	_bind_sky()

func _bind_nodes() -> void:
	if _sun == null:
		_sun = get_parent().find_child("DirectionalLight3D", true, false) as DirectionalLight3D
	if _world_env == null:
		_world_env = get_parent().find_child("WorldEnvironment", true, false) as WorldEnvironment
	if _shift_clock == null:
		_shift_clock = get_tree().root.find_child("ShiftClock", true, false)
	_bind_sky()

func _bind_sky() -> void:
	if _world_env and _world_env.environment and _world_env.environment.sky:
		var s := _world_env.environment.sky
		if s.sky_material is ProceduralSkyMaterial:
			_sky_mat = s.sky_material as ProceduralSkyMaterial

func _process(delta: float) -> void:
	if _shift_clock == null:
		_shift_clock = get_tree().root.find_child("ShiftClock", true, false)
		if _shift_clock == null:
			return

	if _sun == null or _world_env == null:
		_bind_nodes()
		if _sun == null:
			return

	var time_sec : float = 0.0
	if _shift_clock.has_method("get_time_of_day_seconds"):
		time_sec = float(_shift_clock.call("get_time_of_day_seconds"))
	elif "shift_elapsed_seconds" in _shift_clock:
		# Fallback: start at 07:00 (25200s) + elapsed
		time_sec = fmod(25200.0 + float(_shift_clock.get("shift_elapsed_seconds")), 86400.0)

	var hour : float = time_sec / 3600.0
	_update_sun_and_sky(hour)

func _update_sun_and_sky(hour: float) -> void:
	# Determine day vs night
	var day_frac : float = 0.0
	var elevation : float = 0.0
	var azimuth : float = 0.0

	var day_length : float = sunset_hour - sunrise_hour # ~15.25 h
	if hour >= sunrise_hour and hour <= sunset_hour:
		day_frac = (hour - sunrise_hour) / day_length
		# Elevation peaks around solar noon (13.8h) at ~58 degrees
		elevation = sin(day_frac * PI) * 58.0
		# Azimuth sweeps from East (65°) to South (180°) to West (295°)
		azimuth = lerpf(65.0, 295.0, day_frac)
		if is_night:
			is_night = false
			emit_signal("is_night_changed", false)
	else:
		# Night time — moon trajectory
		var night_frac : float = 0.0
		if hour > sunset_hour:
			night_frac = (hour - sunset_hour) / (24.0 - day_length)
		else:
			night_frac = (hour + (24.0 - sunset_hour)) / (24.0 - day_length)
		elevation = sin(night_frac * PI) * 35.0
		azimuth = lerpf(295.0, 65.0 + 360.0, night_frac)
		if not is_night:
			is_night = true
			emit_signal("is_night_changed", true)

	# Apply rotation to DirectionalLight3D (canonical -Z forward, X pitch)
	_sun.rotation_degrees = Vector3(-elevation, azimuth, 0.0)

	# Dynamic lighting colors & intensities
	var sun_color := Color.WHITE
	var sun_energy := 1.3
	var sky_top := Color(0.35, 0.48, 0.72)
	var sky_horiz := Color(0.72, 0.78, 0.84)
	var amb_energy := 0.75

	if is_night:
		# Cool silver moonlight
		sun_color = Color(0.60, 0.72, 0.95)
		sun_energy = 0.18
		sky_top = Color(0.04, 0.06, 0.12)
		sky_horiz = Color(0.08, 0.12, 0.20)
		amb_energy = 0.25
	elif hour >= sunrise_hour and hour < sunrise_hour + 1.5:
		# Dawn / Sunrise (warm peach & gold)
		var t : float = (hour - sunrise_hour) / 1.5
		sun_color = Color(1.0, 0.70, 0.45).lerp(Color(1.0, 0.95, 0.85), t)
		sun_energy = lerpf(0.5, 1.3, t)
		sky_top = Color(0.20, 0.30, 0.50).lerp(Color(0.35, 0.48, 0.72), t)
		sky_horiz = Color(0.95, 0.55, 0.35).lerp(Color(0.72, 0.78, 0.84), t)
		amb_energy = lerpf(0.4, 0.75, t)
	elif hour >= sunset_hour - 2.0 and hour <= sunset_hour:
		# Golden hour / Sunset (crimson & amber)
		var t : float = (hour - (sunset_hour - 2.0)) / 2.0
		sun_color = Color(1.0, 0.95, 0.85).lerp(Color(1.0, 0.48, 0.20), t)
		sun_energy = lerpf(1.3, 0.5, t)
		sky_top = Color(0.35, 0.48, 0.72).lerp(Color(0.18, 0.22, 0.45), t)
		sky_horiz = Color(0.72, 0.78, 0.84).lerp(Color(0.95, 0.40, 0.22), t)
		amb_energy = lerpf(0.75, 0.35, t)
	else:
		# Normal daylight
		sun_color = Color(1.0, 0.98, 0.92)
		sun_energy = 1.35
		sky_top = Color(0.35, 0.48, 0.72)
		sky_horiz = Color(0.72, 0.78, 0.84)
		amb_energy = 0.80

	_sun.light_color = sun_color
	_sun.light_energy = sun_energy

	if _sky_mat != null:
		_sky_mat.sky_top_color = sky_top
		_sky_mat.sky_horizon_color = sky_horiz
		_sky_mat.ground_horizon_color = sky_horiz.darkened(0.3)

	if _world_env and _world_env.environment:
		_world_env.environment.ambient_light_energy = amb_energy
