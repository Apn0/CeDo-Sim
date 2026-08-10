extends Node

# =============================================================================
# npc-06 — LOCAL SENSING + RECOVERY for the NPC vehicle autopilot.
# =============================================================================
# WHY THIS EXISTS, AND WHY IT IS NOT A NAVMESH.
#
# BaseVehicle._npc_drive models the vehicle as a POINT at global_position: yaw
# toward the target, speed = cruise * cos(yaw_err), and _kinematic_move zeroes
# the translation on contact while rotation.y and _current_speed_mps are
# rewritten every frame from the same unchanged target. There is no ray, no
# progress test and no recovery state, so the chassis grinds on whatever its
# front corner meets and never stops asking to go forward.
#
# That is a SENSING defect, not a routing one, and the control experiment says
# so: jam 1 reproduced at (-79.90, 157.13) with all 339 perimeter-fence
# colliders stripped, and jammed at (-79.95, 157.25) anyway. A perfect global
# path fed to a blind controller still drives its front corner into the first
# thing the straight line to the next waypoint crosses. So the missing organ is
# sensing, and this file is the sensing.
#
# A global route (occupancy grid + A*) is the RIGHT long-term answer for taking
# a geometrically sensible way round, and it is deliberately not built here:
# nobody has yet produced a jam that survives whiskers, and a second routing
# system built on speculation is a second thing to keep true.
#
# WHAT THIS DOES NOT DO: it never writes to the vehicle. advise() reads the
# world and sets the four output fields below; BaseVehicle applies them. Keeping
# the pilot side-effect-free is what lets the jam recorder attribute a cleared
# jam to this layer rather than to a hidden transform write.
# =============================================================================

class_name VehiclePilot

enum Mode { RUN, EVADE, REVERSE }

# ── Sensing ───────────────────────────────────────────────────────────────────
## Whisker fan, degrees off the chassis heading. Centre plus two pairs: the ±25°
## pair sees what the vehicle is about to hit, the ±55° pair is what tells EVADE
## which way is open.
const WHISKER_DEG : Array[float] = [0.0, -25.0, 25.0, -55.0, 55.0]
## Whisker reach. Scales with speed so a moving vehicle looks far enough ahead to
## turn at NPC_TURN_RATE instead of arriving already committed.
##
## The floor is 6.0 m and that number is load-bearing, not padding. Rays are
## CAPPED at the reach, so with a 3.0 m floor a vehicle backed 3 m off a wall
## reads 3.0 on every whisker — front and sides alike — and _open_side can never
## find one "more open" than dead ahead. Measured: the pilot then reversed 9 times
## and never once evaded, bouncing off the fence instead of rounding it. At 6.0 m
## the same pose reads 3.0 ahead and ~5.2 on the ±55° pair, which is the
## discrimination the side choice needs.
const WHISKER_MIN_M   : float = 6.0
const WHISKER_SPEED_K : float = 1.6
## Whisker height above the chassis origin — above the floor and the low kerbs
## the gravity probe already handles, below the roof trusses.
const WHISKER_Y : float = 0.5

# ── Stuck detection ───────────────────────────────────────────────────────────
# Thresholds lifted verbatim from FeederWorker's PROVEN wall-follow stopgap
# (FeederWorker.gd:118-121): they have already been tuned against real contacts
# on this plant, and reusing them means one number to re-tune instead of two.
const BLOCK_MIN_FRAC  : float = 0.35   # of the ground the cruise speed says we should cover
const BLOCK_TRIGGER_S : float = 0.4    # grinding this long == a real obstacle

# ── Recovery ──────────────────────────────────────────────────────────────────
## EVADE is a WALL-FOLLOW, not a timed swerve. A fixed commit window was tried
## and measured: 1.5 s of 49° bias clears ~4 m, then RUN re-aims at the target and
## drives back into the same obstacle. Against the 205 m perimeter fence run that
## oscillates — the forklift covered 80.8 m without wedging and still ended
## 139.6 m from a target it started 136.4 m from. So the exit condition is
## GEOMETRIC (the bearing to the target has opened up), not temporal, and the
## timer below only bounds a genuine circle.
const EVADE_MIN_SECS    : float = 0.8   # no left/right flip-flop on first contact
const EVADE_MAX_SECS    : float = 25.0  # circling — back out and pick the other side
const EVADE_YAW_RAD     : float = 0.85  # ~49°, inside one NPC_TURN_RATE second
## How far along the bearing to the target must be clear before EVADE releases.
## Capped so a distant target does not keep the follow engaged across open ground.
const BEARING_PROBE_MAX_M : float = 14.0
const REVERSE_SPEED_MPS : float = 1.5
const REVERSE_MAX_M     : float = 3.0   # back out this far, then try again
const REVERSE_LOCKOUT_S : float = 2.0   # EVADE straight after a reverse, don't re-charge
const REAR_CLEAR_M      : float = 2.0   # abort the reverse rather than back into something
## Contact closer than this cannot be steered out of — reverse instead of evade.
const REVERSE_IF_CLOSER_M : float = 0.8

# ── Ease-in escalation ────────────────────────────────────────────────────────
# BaseVehicle.gd:1016-1017 floors the sub-4 m approach at 0.25 * cruise with no
# escape. Against a contact that is what produced the measured 0.33 m/s creep on
# the outdoor-skip leg: the vehicle is "arriving" forever. Time-box it.
const EASE_BAND_M    : float = 4.0
const EASE_PATIENCE_S : float = 3.0
const EASE_PROGRESS_M : float = 0.5

# ── Outputs (read by BaseVehicle._npc_drive after advise()) ───────────────────
## Yaw offset to add to the desired heading, radians.
var yaw_bias : float = 0.0
## Multiplier on the commanded speed, [0, 1].
var speed_scale : float = 1.0
## Back away from a contact. Applied by NEGATING the final commanded speed, so it
## composes with carry-first mode instead of fighting it — see the note in
## BaseVehicle._npc_drive.
var recovery_reverse : bool = false
## Hold the current heading instead of slewing toward the target. Backing out
## while yawing toward the thing you are stuck on re-wedges the same corner.
var hold_heading : bool = false
## Absolute yaw to steer to, replacing the target bearing entirely. NAN when the
## pilot is not overriding. Used by the wall-follow: while rounding an obstacle
## the heading must come from the OBSTACLE, not from where we wish we were going.
var heading_override : float = NAN

# ── Counters (anti-vacuity: a cleared jam with zero engagements is a coincidence)
var evade_count : int = 0
var recovery_reverse_count : int = 0
var wedge_seconds_total : float = 0.0

var _mode : int = Mode.RUN
var _mode_t : float = 0.0
var _blocked_secs : float = 0.0
var _reverse_travel : float = 0.0
var _lockout_s : float = 0.0
var _prev_pos : Vector3 = Vector3.ZERO
var _have_prev : bool = false
var _ease_secs : float = 0.0
var _ease_best_d : float = INF
var _exclude : Array[RID] = []
var _exclude_ttl : int = 0
var _evade_sign : float = 1.0
var _cruise_hint : float = 3.0

## Called once per physics tick from BaseVehicle._npc_drive, BEFORE the yaw and
## speed writes. `cruise` is the vehicle's own cruise speed (m/s) and `dist` the
## XZ distance to the active waypoint.
func advise(v: Node3D, delta: float, cruise: float, target: Vector3) -> void:
	yaw_bias = 0.0
	speed_scale = 1.0
	recovery_reverse = false
	hold_heading = false
	heading_override = NAN
	if v == null or not is_instance_valid(v) or delta <= 0.0:
		return
	var flat : Vector3 = target - v.global_position
	flat.y = 0.0
	var dist : float = flat.length()

	var here : Vector3 = v.global_position
	var moved : float = 0.0
	if _have_prev:
		moved = Vector2(here.x - _prev_pos.x, here.z - _prev_pos.z).length()
	_prev_pos = here
	_have_prev = true

	# Grinding: covered far less ground than the commanded speed says we should
	# have. Measured on ACHIEVED motion, so it catches both a hard contact and the
	# ease-in creep without needing to know which one it is.
	var expected : float = cruise * delta * BLOCK_MIN_FRAC
	if moved < expected:
		_blocked_secs += delta
		wedge_seconds_total += delta
	else:
		_blocked_secs = 0.0

	# Ease-in band watchdog — inside 4 m the speed floor keeps commanding motion
	# even when the distance has stopped closing. Escalate rather than creep.
	if dist < EASE_BAND_M:
		if dist < _ease_best_d - EASE_PROGRESS_M:
			_ease_best_d = dist
			_ease_secs = 0.0
		else:
			_ease_secs += delta
	else:
		_ease_secs = 0.0
		_ease_best_d = INF

	_lockout_s = maxf(0.0, _lockout_s - delta)
	_mode_t += delta
	var whiskers : Array[float] = _cast_whiskers(v, cruise)

	match _mode:
		Mode.RUN:     _tick_run(v, whiskers)
		Mode.EVADE:   _tick_evade(v, whiskers, target, dist)
		Mode.REVERSE: _tick_reverse(v, moved, whiskers)

## Clear per-leg state. Called by BaseVehicle when a waypoint is reached or a new
## one is issued, so a fresh leg does not inherit the previous leg's stuck timer.
func reset_leg() -> void:
	_mode = Mode.RUN
	_mode_t = 0.0
	_blocked_secs = 0.0
	_reverse_travel = 0.0
	_lockout_s = 0.0
	_have_prev = false
	_ease_secs = 0.0
	_ease_best_d = INF

# ── States ────────────────────────────────────────────────────────────────────

func _tick_run(v: Node3D, whiskers: Array[float]) -> void:
	# Slow down for something dead ahead before it becomes a contact.
	var ahead : float = whiskers[0]
	var reach : float = _whisker_len(v)
	if ahead < reach:
		speed_scale = clampf(ahead / maxf(reach, 0.01), 0.25, 1.0)
	if _blocked_secs < BLOCK_TRIGGER_S and _ease_secs < EASE_PATIENCE_S:
		return
	# Two cases need backing out rather than steering out: a cul-de-sac (no
	# whisker meaningfully more open than dead ahead), and a contact already
	# closer than the vehicle can turn out of — a 49° yaw against a wall 0.8 m
	# away just grinds the other front corner. Everything else evades.
	if _open_side(whiskers) < 0 or ahead < REVERSE_IF_CLOSER_M:
		_enter_reverse()
	else:
		_enter_evade(whiskers)

## Wall-follow. The heading comes from the obstacle: turn away from the committed
## side while the front is closing, drift back toward the line when it opens. That
## traces the obstacle's edge instead of bouncing off it. Releases the moment the
## bearing to the target is clear — the geometric condition, so a 205 m fence run
## is followed for as long as it actually blocks and no longer.
func _tick_evade(v: Node3D, whiskers: Array[float], target: Vector3, dist: float) -> void:
	speed_scale = 0.6
	var reach : float = _whisker_len(v)
	var turn : float = EVADE_YAW_RAD if whiskers[0] < reach * 0.6 else -EVADE_YAW_RAD * 0.4
	heading_override = v.rotation.y + turn * _evade_sign
	if whiskers[0] < REVERSE_IF_CLOSER_M:
		_enter_reverse()
		return
	if _mode_t < EVADE_MIN_SECS:
		return
	# A wall-follow is only a follow while it MOVES. A front-CORNER contact the
	# whiskers straddle (rays at 0°/±25°/±55° pass beside it) grinds here with
	# every ray reading open: measured on the jam-1 leg 2026-08-10 — dead stop
	# at 0.01 m/s against the parked V40's corner, _blocked_secs climbing while
	# this state waited for the 25 s circling cap. RUN escalates on the same
	# grind signal after 0.4 s; the follow must not be 60x more patient.
	if _blocked_secs >= BLOCK_TRIGGER_S:
		_enter_reverse()
		return
	if _bearing_clear(v, target, dist):
		_mode = Mode.RUN
		_mode_t = 0.0
		_blocked_secs = 0.0
		_ease_secs = 0.0
		_ease_best_d = INF
		return
	# Circling. The side we committed to does not go anywhere; back out, which
	# also clears the commit so the next _enter_evade can choose the other way.
	if _mode_t >= EVADE_MAX_SECS:
		_enter_reverse()

func _tick_reverse(v: Node3D, moved: float, whiskers: Array[float]) -> void:
	recovery_reverse = true
	hold_heading = true
	speed_scale = clampf(REVERSE_SPEED_MPS / maxf(_cruise_hint, 0.01), 0.05, 1.0)
	_reverse_travel += moved
	if _reverse_travel < REVERSE_MAX_M and not _rear_blocked(v) and _mode_t <= 4.0:
		return
	# Hand STRAIGHT to the wall-follow, never back to RUN. RUN re-aims at the
	# target, which is the bearing we just backed off, so the vehicle charges the
	# same obstacle again — measured as an endless reverse/charge loop that
	# covered 80.8 m and closed 0 m of a 136 m leg. Backing out exists to buy the
	# room to TURN; this is where the turn gets spent.
	_blocked_secs = 0.0
	_reverse_travel = 0.0
	_ease_secs = 0.0
	_ease_best_d = INF
	_lockout_s = REVERSE_LOCKOUT_S
	_enter_evade(whiskers)

## Commit to rounding the obstacle on one side. NEVER bounces back to REVERSE:
## reverse hands control here, so a "no clearly open side" answer that reversed
## again would be an infinite reverse/evade ping-pong. When nothing is clearly
## open the widest whisker wins, and a true tie FLIPS the previous choice — a
## deterministic tie-break would otherwise re-pick the wall it just failed on.
func _enter_evade(whiskers: Array[float]) -> void:
	var side : int = _open_side(whiskers)
	if side >= 0:
		# Take the sign straight off the whisker's own angle: an index-parity rule
		# silently inverts the moment someone re-orders or adds a ray.
		_evade_sign = signf(WHISKER_DEG[side])
	else:
		var widest : int = 1
		for i in range(2, whiskers.size()):
			if whiskers[i] > whiskers[widest]:
				widest = i
		var s : float = signf(WHISKER_DEG[widest])
		_evade_sign = -_evade_sign if is_equal_approx(s, _evade_sign) else s
	_mode = Mode.EVADE
	_mode_t = 0.0
	_blocked_secs = 0.0
	evade_count += 1

func _enter_reverse() -> void:
	_mode = Mode.REVERSE
	_mode_t = 0.0
	_reverse_travel = 0.0
	_blocked_secs = 0.0
	recovery_reverse_count += 1

# ── Sensing helpers ───────────────────────────────────────────────────────────

## Free distance along each whisker, in WHISKER_DEG order. A ray that hits
## nothing reports its full length.
func _cast_whiskers(v: Node3D, cruise: float) -> Array[float]:
	_cruise_hint = maxf(cruise, 0.5)
	var out : Array[float] = []
	var space := v.get_world_3d().direct_space_state
	if space == null:
		for _d in WHISKER_DEG:
			out.append(WHISKER_MIN_M)
		return out
	_refresh_exclusions(v)
	var reach : float = _whisker_len(v)
	var origin : Vector3 = v.global_position + Vector3(0.0, WHISKER_Y, 0.0) \
		+ (-v.global_transform.basis.z) * _front_offset(v)
	for deg in WHISKER_DEG:
		var dir : Vector3 = (-v.global_transform.basis.z).rotated(Vector3.UP, deg_to_rad(deg))
		var q := PhysicsRayQueryParameters3D.create(origin, origin + dir * reach)
		q.exclude = _exclude
		var hit := space.intersect_ray(q)
		if hit:
			out.append(origin.distance_to((hit as Dictionary)["position"]))
		else:
			out.append(reach)
	return out

## True when the straight line from the front bumper toward the target is free
## for the lesser of the remaining distance and BEARING_PROBE_MAX_M. This is the
## wall-follow's release condition and the whole reason it terminates.
func _bearing_clear(v: Node3D, target: Vector3, dist: float) -> bool:
	var space := v.get_world_3d().direct_space_state
	if space == null:
		return true
	var origin : Vector3 = v.global_position + Vector3(0.0, WHISKER_Y, 0.0)
	var to : Vector3 = target - v.global_position
	to.y = 0.0
	if to.length_squared() < 0.01:
		return true
	var probe : float = minf(dist, BEARING_PROBE_MAX_M)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + to.normalized() * probe)
	q.exclude = _exclude
	return space.intersect_ray(q).is_empty()

func _rear_blocked(v: Node3D) -> bool:
	var space := v.get_world_3d().direct_space_state
	if space == null:
		return false
	var back : Vector3 = v.global_transform.basis.z
	var origin : Vector3 = v.global_position + Vector3(0.0, WHISKER_Y, 0.0) \
		+ back * _front_offset(v)
	var q := PhysicsRayQueryParameters3D.create(origin, origin + back * REAR_CLEAR_M)
	q.exclude = _exclude
	return not space.intersect_ray(q).is_empty()

func _whisker_len(v: Node3D) -> float:
	var sp : float = absf(float(v.get("_current_speed_mps"))) if "_current_speed_mps" in v else 0.0
	return maxf(WHISKER_MIN_M, sp * WHISKER_SPEED_K)

## Half the chassis length, so whiskers start at the front bumper rather than at
## the origin — otherwise the first metre of every ray is inside the vehicle.
func _front_offset(v: Node3D) -> float:
	for c in v.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size.z * 0.5 + 0.1
	return 1.4

## Index of the whisker with the most room, or -1 when nothing is meaningfully
## more open than dead ahead (a cul-de-sac — reversing is the only real move).
func _open_side(whiskers: Array[float]) -> int:
	var best : int = -1
	var best_d : float = whiskers[0] * 1.25 + 0.5
	for i in range(1, whiskers.size()):
		if whiskers[i] > best_d:
			best_d = whiskers[i]
			best = i
	return best

## Whiskers must ignore the vehicle itself and anything riding on it (a grabbed
## bale is reparented under the carry point). Refreshed on a timer rather than
## per-ray: the descendant walk is not free and the load set changes at grab
## speed, not at frame speed.
func _refresh_exclusions(v: Node3D) -> void:
	_exclude_ttl -= 1
	if _exclude_ttl > 0 and not _exclude.is_empty():
		return
	_exclude_ttl = 30
	_exclude = []
	_collect_bodies(v)

func _collect_bodies(n: Node) -> void:
	if n is CollisionObject3D:
		_exclude.append((n as CollisionObject3D).get_rid())
	for c in n.get_children():
		_collect_bodies(c)
