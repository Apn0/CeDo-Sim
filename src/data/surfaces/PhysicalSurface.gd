extends Resource
class_name PhysicalSurface

## A surface in the factory (concrete, steel grate, oil patch, water puddle).
## Single source of truth for: foot friction, vehicle traction, footstep audio,
## impact audio, visual particle/decal spawning.
##
## Create .tres instances in `src/data/surfaces/` (e.g. concrete.tres,
## oily_concrete.tres) and assign to floor mesh metadata or PhysicsMaterial
## lookup tables.

@export_group("Identity")
@export var surface_name: String = "unnamed"
@export var nl_name     : String = ""        # Dutch term (the user knows these)

@export_group("Friction")
@export_range(0.0, 2.0, 0.05) var foot_friction          : float = 0.7
@export_range(0.0, 2.0, 0.05) var vehicle_grip_modifier  : float = 1.0
## Multiplier applied to default VehicleBody3D wheel friction. Oily concrete
## ~0.55, painted lanes ~0.85, clean concrete 1.0, dry steel grate 1.1.

@export_group("Footstep audio")
@export var step_clips_walk: Array[AudioStream] = []
@export var step_clips_run : Array[AudioStream] = []

@export_group("Impact audio (dropped items, lump falls)")
@export var impact_clips_light: Array[AudioStream] = []   # impulse < 50 Ns
@export var impact_clips_heavy: Array[AudioStream] = []   # impulse >= 50 Ns

@export_group("Vehicle audio")
@export var tire_roll_clips: Array[AudioStream] = []     # looped under driving
@export var tire_skid_clips: Array[AudioStream] = []     # high lateral slip

@export_group("Visual feedback")
@export var step_particle_scene  : PackedScene             # optional puff
@export var impact_decal_scene   : PackedScene             # scuff / mark
@export var vehicle_track_decal  : PackedScene             # tyre tracks

# ── Helpers ───────────────────────────────────────────────────────────────────
func pick_step_clip(running: bool = false) -> AudioStream:
	var pool: Array[AudioStream] = step_clips_run if running else step_clips_walk
	if pool.is_empty():
		return null
	return pool.pick_random()

func pick_impact_clip(impulse_ns: float) -> AudioStream:
	var pool: Array[AudioStream] = impact_clips_heavy if impulse_ns >= 50.0 else impact_clips_light
	if pool.is_empty():
		return null
	return pool.pick_random()

func pick_tire_roll_clip() -> AudioStream:
	if tire_roll_clips.is_empty():
		return null
	return tire_roll_clips.pick_random()

func pick_tire_skid_clip() -> AudioStream:
	if tire_skid_clips.is_empty():
		return null
	return tire_skid_clips.pick_random()
