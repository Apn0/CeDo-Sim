extends Node3D
class_name VibratingPivot

## Sinusoidal position oscillator for vibrating-screen / shaker machinery.
##
## Defaults (8 cm peak-to-peak @ 8 Hz) match the operator's trilzeef spec.
## Set `amplitude_m` to ZERO peak displacement (so peak-to-peak = 2 × amplitude),
## and `frequency_hz` to the eccentric-motor frequency in revolutions per
## second. `axis` picks which local axis carries the wobble — most shakers
## drive the deck vertically (Y).
##
## Usage:
##     var vp := VibratingPivot.new()
##     vp.amplitude_m = 0.04
##     vp.frequency_hz = 8.0
##     parent.add_child(vp)
##     # …then re-parent the visible deck meshes under `vp`.

@export var amplitude_m   : float = 0.04   # 4 cm zero-to-peak → 8 cm peak-to-peak
@export var frequency_hz  : float = 8.0
@export var axis          : Vector3 = Vector3(0.0, 1.0, 0.0)

# Anchor pose — the (rest) transform the wobble adds to. Captured on _ready so
# callers can position / rotate the pivot before adding to the tree, and the
# vibration centres on that intended pose instead of accumulating around the
# very first frame's `position`.
var _rest_position : Vector3 = Vector3.ZERO
var _time_s        : float   = 0.0

func _ready() -> void:
	_rest_position = position

func _process(delta: float) -> void:
	_time_s += delta
	var offset : float = sin(_time_s * frequency_hz * TAU) * amplitude_m
	position = _rest_position + axis * offset
