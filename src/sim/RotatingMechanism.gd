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
##
## Public API for changing speed (see also issue: audit-RPM-ramp):
##   * `rpm` (@export) — the COMMANDED setpoint. Writing it is rate-limited
##     through an exponential ramp (real motors don't snap to speed).
##   * `set_target_rpm(v)` — explicit, named alias for setting the setpoint
##     without bypassing the ramp. Prefer this in scripts that read like PLC
##     logic.
##   * `snap_to_rpm(v)` — EXPLICIT bypass: forces both target and live rpm to
##     `v` in one tick. Reserved for emergency stop, Editor preview, and
##     deterministic test scaffolding. Production callers should use the
##     setpoint-based API above so the ramp is honored.
##   * `current_rpm()` — live rpm AFTER the ramp (for HMI / throughput).

const SmoothedRateScript = preload("res://src/sim/SmoothedRate.gd")

@export var rpm           : float = 30.0      # COMMANDED setpoint (ramped, not snapped)
@export var nominal_rpm   : float = 30.0      # speed at which capacity is rated
@export var axis          : Vector3 = Vector3.RIGHT   # local spin axis
## When true, the rotor spins toward target_rpm at spin_up_s. Defaults to
## FALSE — production rotors are driven by LineFlow's per-tick
## set_running(bool(nd["powered"])); cosmetic-only rotors (HVAC fans,
## decorative ceiling fans) must explicitly set running=true at construction.
@export var running       : bool  = false
@export var capacity_kg_s : float = 5.0       # throughput at nominal rpm
@export var scrub         : float = 0.0       # 0..1 contaminant scoured per pass (friction rotors)
@export var spin_up_s     : float = 1.2       # seconds to ramp rpm from 0 → target on start

var angle      : float = 0.0
var _base      : Basis = Basis()
var _rpm_target: float = 0.0
# Live (ramped) rpm. Underscore prefix = treat as private. Do NOT poke this
# field directly to "skip the ramp"; call snap_to_rpm() instead, which keeps
# the smoother and target in lockstep with the visible value.
var _rpm_cur   : float = 0.0
var _smoother : SmoothedRate = null

# =============================================================================
func _ready() -> void:
	add_to_group("mechanism")
	_base = transform.basis
	# A degenerate parent (zero scale, NaN rotation from atan2 on a zero-length
	# vector, etc.) makes _base non-finite or singular at spawn. Every later
	# frame would then compute `_base * Basis(axis, angle)` and write a NaN
	# basis back into transform.basis — the renderer reports that with
	# "instance_set_transform !v.is_finite()" forever. Reset to identity so
	# the spin can still run on a clean local frame; visuals are tied to the
	# parent's position, not its scale/rotation.
	if not (_base.x.is_finite() and _base.y.is_finite() and _base.z.is_finite()) \
			or _base.determinant() < 1e-6:
		push_warning("[RotatingMechanism] non-finite/singular parent basis on '%s' — resetting to identity" % name)
		_base = Basis()
		transform.basis = Basis()
	# Spawn-time initialization snaps to the configured setpoint on purpose —
	# the spinner is "born up to speed" at whatever PlaceableCatalog wired in.
	_rpm_target = rpm if running else 0.0
	_rpm_cur = _rpm_target
	_smoother = SmoothedRateScript.new(_rpm_cur, _tau_from_spin_up(spin_up_s))

func _process(delta: float) -> void:
	# Ramp the live rpm toward target (motors don't snap to speed). The commanded
	# rpm is CAPPED at the rated maximum (nominal_rpm) so a bad setpoint — e.g.
	# 6000 on a 60-rpm screw — can never spin it past spec.
	var capped : float = clampf(rpm, 0.0, nominal_rpm) if nominal_rpm > 0.0 else maxf(rpm, 0.0)
	_rpm_target = capped if running else 0.0
	# Exponential approach via SmoothedRate (tau ≈ spin_up_s / 3, so ~95% of
	# the step is reached in `spin_up_s` seconds — the historic linear ramp
	# hit the target exactly at that time, this asymptotically approaches it
	# in roughly the same period without the discontinuity at arrival).
	if _smoother == null:
		_smoother = SmoothedRateScript.new(_rpm_cur, _tau_from_spin_up(spin_up_s))
	else:
		# Keep tau in sync if spin_up_s was reconfigured at runtime.
		_smoother.set_tau(_tau_from_spin_up(spin_up_s))
		_smoother.value = _rpm_cur
	_rpm_cur = _smoother.approach(_rpm_target, delta)
	if absf(_rpm_cur) > 0.001:
		angle = wrapf(angle + (_rpm_cur / 60.0) * TAU * delta, -TAU, TAU)
		# Defensive: a zero-length axis produces NaN in Basis(axis, angle), and
		# any other route to NaN here cascades to every render frame for the
		# rest of the session (~46k errors per minute). Bail out cleanly instead.
		if axis.length_squared() < 1e-9 or not is_finite(angle):
			if OS.is_debug_build():
				push_warning("[RotatingMechanism] non-finite axis/angle on '%s' (parent: %s)" \
					% [name, String(get_parent().name) if get_parent() else "<orphan>"])
			return
		var b := _base * Basis(axis.normalized(), angle)
		if not b.x.is_finite() or not b.y.is_finite() or not b.z.is_finite():
			if OS.is_debug_build():
				push_warning("[RotatingMechanism] non-finite basis emitted by '%s'" % name)
			return
		transform.basis = b

# Map the legacy "linear ramp time" knob (spin_up_s) to the exponential
# smoother's time constant. tau = T / 3 puts ~95% of the step at t = T.
func _tau_from_spin_up(t: float) -> float:
	return maxf(t, 0.01) / 3.0

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

## Set the commanded rpm setpoint WITHOUT snapping live rpm. The ramp in
## _process slews `_rpm_cur` toward this value at the configured spin_up_s
## time constant. This is the recommended public setter for runtime callers
## (LineFlow, PelletizerKnifeReplace, etc.) — equivalent to writing `rpm = v`
## directly but more self-documenting at the call site.
func set_target_rpm(v: float) -> void:
	rpm = v

## EXPLICIT bypass: force both the commanded setpoint and the live rpm to `v`
## in one tick, skipping the ramp. Reserved for:
##   * Emergency stop (operator slams the e-stop — motor cuts instantly, the
##     mechanical inertia is modeled elsewhere if at all).
##   * Editor preview / scene-construction snap-to-pose.
##   * Deterministic test scaffolding (per-tick assertions on throughput).
## Production sim code should NOT call this — use `rpm = v` or
## `set_target_rpm(v)` so the motor's spin-up is honored.
func snap_to_rpm(v: float) -> void:
	rpm = v
	_rpm_target = clampf(v, 0.0, nominal_rpm) if nominal_rpm > 0.0 else maxf(v, 0.0)
	if not running:
		_rpm_target = 0.0
	_rpm_cur = _rpm_target
	if _smoother != null:
		_smoother.snap_to(_rpm_cur)
