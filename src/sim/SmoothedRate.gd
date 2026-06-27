extends RefCounted
class_name SmoothedRate

## First-order low-pass smoother. Used wherever a discrete setpoint must
## drive a smooth output (RPM ramps, vehicle throttle, belt speed, NPC walk
## speed). Time-constant based — framerate-independent.
##
## Usage:
##   var s := SmoothedRate.new(0.0, 2.5)   # initial value 0, time-constant 2.5 s
##   func _physics_process(delta):
##       output = s.approach(target_setpoint, delta)

var value : float = 0.0
var tau_s : float = 1.0

func _init(initial : float = 0.0, tau_seconds : float = 1.0) -> void:
	value = initial
	tau_s = max(0.01, tau_seconds)

## Pulls value toward target by an exponential decay step. Returns the new value.
func approach(target : float, delta : float) -> float:
	if tau_s <= 0.0001:
		value = target
		return value
	# value_new = value + (target - value) * (1 - exp(-delta / tau))
	# This is the closed-form solution of dy/dt = (target - y) / tau.
	var k : float = 1.0 - exp(-delta / tau_s)
	value += (target - value) * k
	return value

## Linear ramp instead of exponential — useful when you need a fixed rate
## (e.g. forklift mast cylinder at fixed flow rate) instead of an asymptote.
## rate_per_s is in units / second.
func ramp_linear(target : float, rate_per_s : float, delta : float) -> float:
	var max_step : float = abs(rate_per_s) * delta
	var diff : float = target - value
	if abs(diff) <= max_step:
		value = target
	else:
		value += sign(diff) * max_step
	return value

## Snap helper — for when an operator explicitly wants to bypass smoothing
## (e.g. emergency stop instantly cuts throttle). Returns the new value.
func snap_to(v : float) -> float:
	value = v
	return v

func get_value() -> float:
	return value

func set_tau(tau_seconds : float) -> void:
	tau_s = max(0.01, tau_seconds)
