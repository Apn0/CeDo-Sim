extends Node3D
class_name RotatingMechanism

## Reusable spinning mechanism — the shared base for paddles, transport screws,
## friction-separator rotors, magnet drums, scraper sprockets, gears, beacons.
## Parent the visual mesh(es) under this node; it spins them about `axis` at
## `rpm` while `running`. Its `throughput()` (kg/s it can move) scales with the
## current rpm vs nominal, so the flow sim (#145) can read a real transport rate
## off any conveying mechanism instead of teleporting material.
##
## A FRICTION rotor is just one of these at high rpm with scrub > 0 (it scours
## dirt off the flake); a SCREW is one along Z; a PADDLE is one along Z with
## blades; a MAGNET DRUM is one along X. One component, parameterised.

@export var rpm           : float = 30.0      # current speed
@export var nominal_rpm   : float = 30.0      # speed at which capacity is rated
@export var axis          : Vector3 = Vector3.RIGHT   # local spin axis
@export var running       : bool  = true
@export var capacity_kg_s : float = 5.0       # throughput at nominal rpm
@export var scrub         : float = 0.0       # 0..1 contaminant scoured per pass (friction rotors)
@export var spin_up_s     : float = 1.2       # seconds to ramp rpm from 0 → target on start

var angle      : float = 0.0
var _base      : Basis = Basis()
var _rpm_target: float = 0.0
var _rpm_cur   : float = 0.0

# =============================================================================
func _ready() -> void:
	add_to_group("mechanism")
	_base = transform.basis
	_rpm_target = rpm if running else 0.0
	_rpm_cur = _rpm_target

func _process(delta: float) -> void:
	# Ramp the live rpm toward target (motors don't snap to speed). The commanded
	# rpm is CAPPED at the rated maximum (nominal_rpm) so a bad setpoint — e.g.
	# 6000 on a 60-rpm screw — can never spin it past spec.
	var capped : float = clampf(rpm, 0.0, nominal_rpm) if nominal_rpm > 0.0 else maxf(rpm, 0.0)
	_rpm_target = capped if running else 0.0
	var ramp := (maxf(capped, 1.0) / maxf(spin_up_s, 0.01)) * delta
	_rpm_cur = move_toward(_rpm_cur, _rpm_target, ramp)
	if absf(_rpm_cur) > 0.001:
		angle = wrapf(angle + (_rpm_cur / 60.0) * TAU * delta, -TAU, TAU)
		# Defensive: a zero-length axis produces NaN in Basis(axis, angle), and
		# any other route to NaN here cascades to every render frame for the
		# rest of the session (~46k errors per minute). Bail out cleanly instead.
		if axis.length_squared() < 1e-9 or not is_finite(angle):
			if OS.is_debug_build():
				push_warning("[RotatingMechanism] non-finite axis/angle on '%s' (parent: %s)" \
					% [name, get_parent().name if get_parent() else "<orphan>"])
			return
		var b := _base * Basis(axis.normalized(), angle)
		if not b.x.is_finite() or not b.y.is_finite() or not b.z.is_finite():
			if OS.is_debug_build():
				push_warning("[RotatingMechanism] non-finite basis emitted by '%s'" % name)
			return
		transform.basis = b

## kg/s this mechanism can currently convey (0 while stopped / spun down).
func throughput() -> float:
	if nominal_rpm <= 0.0:
		return 0.0
	return capacity_kg_s * clampf(_rpm_cur / nominal_rpm, 0.0, 1.5)

## Fraction of contaminant a pass through this rotor scours off (friction sep).
func scrub_fraction() -> float:
	return scrub if _rpm_cur > nominal_rpm * 0.5 else 0.0

## Live speed (rpm), after spin-up ramp. For HMI / debugging.
func current_rpm() -> float:
	return _rpm_cur

func set_running(v: bool) -> void:
	running = v

func is_up_to_speed() -> bool:
	return _rpm_cur >= rpm * 0.95
