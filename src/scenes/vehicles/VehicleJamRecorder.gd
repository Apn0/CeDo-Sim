extends Node

# =============================================================================
# npc-06 / npc-07 — LEG RECORDER (instrumentation, not behaviour).
# =============================================================================
# Records what a driving or walking leg ACTUALLY did — position trace, ground
# speed, how long the body spent wedged and where — so a jam can be ATTRIBUTED
# to one change instead of asserted. This project's recurring failure is the
# vacuous green (npc-05 printed 31/31 while the chain moved zero kilograms), and
# the antidote is a measurement taken BEFORE the fix that the fix has to move.
#
# READ-ONLY with respect to the body it watches: it never writes a transform, a
# velocity or a target, so a world with a recorder attached moves identically to
# one without. That is what makes the baseline it captures comparable to the
# post-fix run.
#
# Not wired into production. Tests add it as a child of the mover, call
# begin_leg / end_leg around the leg, and read `legs` afterwards.
#
# Deliberately NOT a signal of success on its own: `wedge_seconds` going to zero
# proves the body kept moving, it does not prove the body arrived. Pair it with
# an arrival assertion and, where mass is involved, with the container ledger.
# =============================================================================

class_name VehicleJamRecorder

## Ground speed below which the body counts as "not moving". Above the numerical
## drift BaseVehicle._drive zeroes at 0.05 m/s, so idle noise cannot open a wedge.
const WEDGE_SPEED_MPS : float = 0.10
## Sustained time under WEDGE_SPEED_MPS before the stall is recorded as a wedge.
## Long enough that an arrival brake or a turn-in-place is not one.
const WEDGE_HOLD_S : float = 1.0
## Spacing of the stored position trace. 1 Hz per the measurement brief.
const SAMPLE_INTERVAL_S : float = 1.0

## One dictionary per completed leg. Keys:
##   name, target, start, final, outcome        — what was asked and what happened
##   duration_s, distance_covered_m             — gross motion
##   final_dist_m, min_dist_m                   — how close it got, and its best
##   wedge_seconds, wedge_count, worst_wedge_pos, worst_wedge_s
##   path_points                                — waypoints the router produced
##   samples : Array[Dictionary] {t, pos, speed, dist}
var legs : Array[Dictionary] = []

var _body       : Node3D = null
var _leg        : Dictionary = {}
var _samples    : Array[Dictionary] = []
var _active     : bool  = false
var _t          : float = 0.0
var _sample_t   : float = 0.0
var _prev_pos   : Vector3 = Vector3.ZERO
var _slow_secs  : float = 0.0
var _wedge_open : bool  = false

## Point the recorder at the body whose motion it should sample. Safe to call
## before or after the node enters the tree.
func watch(body: Node3D) -> void:
	_body = body

## Open a leg. `target` is the point the mover was ORDERED to reach — distances
## are measured against it, so a fix that moves the goalposts shows up as a
## changed target rather than as a silently easier pass.
func begin_leg(leg_name: String, target: Vector3) -> void:
	if _active:
		end_leg("superseded")
	if _body == null or not is_instance_valid(_body):
		return
	_leg = {
		"name": leg_name,
		"target": target,
		"start": _body.global_position,
		"path_points": 0,
	}
	_samples = []
	_active = true
	_t = 0.0
	_sample_t = SAMPLE_INTERVAL_S      # force a sample on the first tick
	_prev_pos = _body.global_position
	_slow_secs = 0.0
	_wedge_open = false
	_leg["distance_covered_m"] = 0.0
	_leg["min_dist_m"] = _horiz(_body.global_position, target)
	_leg["wedge_seconds"] = 0.0
	_leg["wedge_count"] = 0
	_leg["worst_wedge_s"] = 0.0
	_leg["worst_wedge_pos"] = _body.global_position

## Close the leg and file it. `outcome` is the caller's verdict ("arrived",
## "timeout", "failed:<reason>") — the recorder does not infer it, because
## "stopped moving" and "arrived" are exactly the two states this whole exercise
## exists to tell apart.
func end_leg(outcome: String) -> void:
	if not _active:
		return
	_active = false
	var here : Vector3 = _body.global_position if (_body != null and is_instance_valid(_body)) \
		else Vector3.ZERO
	_leg["final"] = here
	_leg["outcome"] = outcome
	_leg["duration_s"] = _t
	_leg["final_dist_m"] = _horiz(here, _leg["target"])
	_leg["samples"] = _samples
	legs.append(_leg)
	_leg = {}
	_samples = []

## Number of waypoints the router produced for this leg. A count of 2 is a
## straight line through whatever is in the way — the signature this work
## exists to remove — so it is recorded rather than derived later.
func note_path_points(n: int) -> void:
	if _active:
		_leg["path_points"] = n

## Wedge time accumulated so far in the OPEN leg (0.0 when none is open).
func current_wedge_seconds() -> float:
	return float(_leg.get("wedge_seconds", 0.0)) if _active else 0.0

## The filed leg with this name, or an empty dictionary. Tests assert against
## this rather than an index so re-ordering legs cannot silently change which
## measurement a check reads.
func leg(leg_name: String) -> Dictionary:
	for l in legs:
		if String(l.get("name", "")) == leg_name:
			return l
	return {}

func _physics_process(delta: float) -> void:
	if not _active or _body == null or not is_instance_valid(_body) or delta <= 0.0:
		return
	_t += delta
	var here : Vector3 = _body.global_position
	var moved : float = _horiz(here, _prev_pos)
	var speed : float = moved / delta
	_prev_pos = here
	_leg["distance_covered_m"] = float(_leg["distance_covered_m"]) + moved
	var dist : float = _horiz(here, _leg["target"])
	_leg["min_dist_m"] = minf(float(_leg["min_dist_m"]), dist)

	# Wedge accounting. The hold window means only a SUSTAINED stall counts, and
	# once open every further slow tick adds to the total — so "crept forward at
	# 0.05 m/s for a minute" reads as a wedge, which is what the measured 0.33 m/s
	# outdoor-skip creep actually was.
	if speed < WEDGE_SPEED_MPS:
		_slow_secs += delta
		if _slow_secs >= WEDGE_HOLD_S:
			if not _wedge_open:
				_wedge_open = true
				_leg["wedge_count"] = int(_leg["wedge_count"]) + 1
				# Attribute the wedge to where it STARTED, not where it was noticed.
				_leg["wedge_seconds"] = float(_leg["wedge_seconds"]) + _slow_secs
			else:
				_leg["wedge_seconds"] = float(_leg["wedge_seconds"]) + delta
			if _slow_secs > float(_leg["worst_wedge_s"]):
				_leg["worst_wedge_s"] = _slow_secs
				_leg["worst_wedge_pos"] = here
	else:
		_slow_secs = 0.0
		_wedge_open = false

	_sample_t += delta
	if _sample_t >= SAMPLE_INTERVAL_S:
		_sample_t = 0.0
		_samples.append({"t": _t, "pos": here, "speed": speed, "dist": dist})

## Longest stall in the leg that happened within `radius` of `pos`, in seconds.
## The four jam signatures are coordinates, so the acceptance tests ask "did the
## body stall HERE", not "did it stall at all".
static func wedge_seconds_near(leg_dict: Dictionary, pos: Vector3, radius: float) -> float:
	var worst : Vector3 = leg_dict.get("worst_wedge_pos", Vector3.INF)
	if worst == Vector3.INF:
		return 0.0
	if Vector2(worst.x - pos.x, worst.z - pos.z).length() > radius:
		return 0.0
	return float(leg_dict.get("worst_wedge_s", 0.0))

## One-line human summary for the test log.
static func describe(leg_dict: Dictionary) -> String:
	if leg_dict.is_empty():
		return "(no leg recorded)"
	var f : Vector3 = leg_dict.get("final", Vector3.ZERO)
	var w : Vector3 = leg_dict.get("worst_wedge_pos", Vector3.ZERO)
	return ("%s: %s after %.1f s — final (%.2f, %.2f, %.2f), %.2f m from target "
		+ "(best %.2f m), covered %.1f m, path %d pts, wedged %.1f s in %d stall(s), "
		+ "worst %.1f s at (%.2f, %.2f, %.2f)") % [
			String(leg_dict.get("name", "?")), String(leg_dict.get("outcome", "?")),
			float(leg_dict.get("duration_s", 0.0)), f.x, f.y, f.z,
			float(leg_dict.get("final_dist_m", 0.0)), float(leg_dict.get("min_dist_m", 0.0)),
			float(leg_dict.get("distance_covered_m", 0.0)), int(leg_dict.get("path_points", 0)),
			float(leg_dict.get("wedge_seconds", 0.0)), int(leg_dict.get("wedge_count", 0)),
			float(leg_dict.get("worst_wedge_s", 0.0)), w.x, w.y, w.z]

func _horiz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()
