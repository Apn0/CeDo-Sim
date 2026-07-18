extends CharacterBody3D

class_name NPC

# NPC identity
var npc_name: String = ""
var npc_role: String = ""  # shift_leader, extruder_op, feeder, etc.

# Movement parameters
var walk_speed: float = 2.0  # m/s (slower than player)
var wander_radius: float = 10.0
var wander_change_interval: float = 5.0  # seconds

# Behavior
var current_velocity: Vector3 = Vector3.ZERO
var target_position: Vector3 = Vector3.ZERO
var is_walking: bool = false
var wander_timer: float = 0.0

# ── #198 NPC autonomy task hook ─────────────────────────────────────────────
# `npc_id` is the catalogue key (romain / pascal / abdellilah / ...). Set by
# NPCSpawner when this NPC is instantiated. Used by NpcAutonomyBoard to look
# up the role and decide which tasks this NPC can accept.
var npc_id : String = ""
# Currently-running autonomy task (or null = idle). When non-null the NPC's
# physics step routes through _autonomy_tick instead of the free-wander.
var _autonomy_task : RefCounted = null
# Cooldown so an idle NPC only polls the board every 3 s, not every frame.
var _autonomy_poll_t : float = 0.0
const _AUTONOMY_POLL_INTERVAL_S : float = 3.0
# Destination an active task is steering the NPC toward. The NPC's existing
# pathfinding consumes this; the task only sets it.
var _autonomy_destination_active : bool = false

## Called by NpcAutonomyTask (or its subclasses) to steer the NPC toward a
## world position. Hooks into the existing target_position field so the rest
## of the NPC's locomotion code drives the body the same way it would for a
## free-wander target.
func set_autonomy_destination(pos: Vector3) -> void:
	# #202 — if this NPC is currently boarded into a vehicle, route the
	# destination to the vehicle's autopilot (BaseVehicle.npc_set_target) so the
	# CHASSIS drives toward the waypoint, not the hidden walking body.
	var op_ctx := get_tree().get_root().find_child("OperatorContext", true, false)
	if op_ctx and op_ctx.has_method("npc_vehicle_of"):
		var v = op_ctx.call("npc_vehicle_of", self)
		if v != null and v.has_method("npc_set_target"):
			v.call("npc_set_target", pos)
			return
	target_position = pos
	is_walking = true
	_autonomy_destination_active = true

func clear_autonomy_destination() -> void:
	_autonomy_destination_active = false
	is_walking = false

## Called by tasks that need to move the NPC into a vehicle's driver seat.
## Reuses the #148 vehicle-entry parity (NPCs board vehicles the same way the
## player does via OperatorContext).
func board_vehicle(vehicle: Node) -> void:
	if vehicle == null:
		return
	var op_ctx := get_tree().get_root().find_child("OperatorContext", true, false)
	if op_ctx and op_ctx.has_method("npc_board_vehicle"):
		op_ctx.call("npc_board_vehicle", self, vehicle)

func disembark_vehicle() -> void:
	var op_ctx := get_tree().get_root().find_child("OperatorContext", true, false)
	if op_ctx and op_ctx.has_method("npc_disembark_vehicle"):
		op_ctx.call("npc_disembark_vehicle", self)

## Per-tick autonomy tick: poll the board when idle, tick the active task
## otherwise. Called from _physics_process before the wander/walk logic.
func _autonomy_tick(delta: float) -> void:
	# Already on a task — tick it.
	if _autonomy_task != null:
		var t : NpcAutonomyTask = _autonomy_task
		if t == null or t.is_done():
			_autonomy_task = null
			clear_autonomy_destination()
			return
		if t.tick(self, delta):
			t.release(self)
			_autonomy_task = null
			clear_autonomy_destination()
		return
	# Idle — poll the board on cadence.
	_autonomy_poll_t += delta
	if _autonomy_poll_t < _AUTONOMY_POLL_INTERVAL_S:
		return
	_autonomy_poll_t = 0.0
	if not Engine.has_singleton("NpcAutonomyBoard"):
		# Autoload not configured (e.g. unit-test scene). Fall back to wander.
		return
	# Direct autoload access — Engine.has_singleton is a heuristic; the real
	# call goes through the engine's autoload table.
	var board := get_node_or_null("/root/NpcAutonomyBoard")
	if board == null:
		return
	var task : NpcAutonomyTask = board.call("take_next_task", self)
	if task != null:
		_autonomy_task = task

# Social state (mutual-aid economy)
var relationship_points: Dictionary = {}  # NPC ID -> points
var is_helping: bool = false
var help_target: Node = null

# ── Crew brain (Wave 4) ───────────────────────────────────────────────────────
# An NPC is "managed" once CrewManager calls assign_post(); until then it free-
# wanders exactly as before (zero regression for any unmanaged NPC). When managed
# the body still moves in _physics_process, but the *decisions* (arrive → service
# → return, break, off-duty) are advanced by CrewManager via step_brain(), so the
# coordination logic runs deterministically and is testable without the physics
# server ticking.
enum Task { FREE, AT_POST, GOING, SERVICING, ON_BREAK, OFF_DUTY,
	# #147 Phase 3 — task planner states for "operate target at world_pos"
	# when the target is too high to reach from the floor and the operator has
	# to fetch a mast lift first.
	PLAN_OPERATE,            # decide reachable-from-floor vs need-lift
	WALK_TO_TARGET,          # reachable: walk straight to target XZ + dwell
	WALK_TO_LIFT,            # need-lift: walk to claimed mast lift's dismount pos
	WAIT_BOARD_LIFT,         # at lift's boarding pos, awaiting sit-down
	RIDING_LIFT,             # lift raising / lowering, operator in basket
	OPERATING,               # at target, performing the action (uses existing service_secs dwell)
	RELEASING_LIFT,          # dismount + release reservation
	# #148 Phase 4 — vehicle boarding parity sub-states. NPCs walk to the
	# boarding position (vehicle.get_boarding_position()) like the player would,
	# pause briefly for the "open door + climb in" beat, then call
	# vehicle.on_npc_entered which reparents them under SeatMarker. Reverse on exit.
	WALK_TO_BOARDING_POS,    # heading to the door-side step
	BOARDING,                # short dwell for the door-open + sit-down animation beat
	DISMOUNTING,             # short dwell for the open-door + step-out beat
}
enum Purpose { POST, SERVICE, BREAK, OPERATE }

var managed            : bool    = false
var on_duty            : bool    = true
var task_state         : int     = Task.FREE
var home_position      : Vector3 = Vector3.ZERO

# ── Phase 1: pathfinding (NavigationAgent3D) ─────────────────────────────────
# NPCs route through the NavigationRegion3D MainWorld bakes from the floor +
# exterior ground. `target_position` stays the FINAL destination (arrive/dwell
# logic compares against it); `_nav_agent.target_position` is synced every
# physics tick, and the agent's next-path-position drives the per-frame walk
# direction so workers route AROUND machines, walls, posts — not through them.
var _nav_agent : NavigationAgent3D = null
# Cached previous target so we only re-path when the destination actually moves
# (cheap micro-optimisation; the agent itself dedupes too).
var _last_nav_target : Vector3 = Vector3(NAN, NAN, NAN)
# ── Phase 3 prep: physical interaction reach ─────────────────────────────────
# How high a standing worker can reach with arms extended, measured from feet
# (capsule bottom). Used by future task planner to decide whether the operator
# needs to fetch a mast lift to reach an elevated target (#147).
var reach_height_max   : float   = 2.2

# ── Phase 2 (#146): locomotion state machine ─────────────────────────────────
# State enum drives speed multiplier + capsule height + body Y-scale + jump
# impulse. The state machine reads three forward raycasts every physics tick
# to pick the right pose for the obstacle ahead:
#   head_ray   (1.55 m) — hit ⇒ overhead obstacle ⇒ CROUCH_WALK
#   chest_ray  (1.05 m) — hit ⇒ low duct / pipe   ⇒ PRONE_CRAWL
#   step_ray   (forward + down, 0.6 m forward, 0.6 m down) — miss ⇒ gap ⇒ JUMP
#                                                        — hit far ⇒ step-up to JUMP
# Default state is WALK when moving and IDLE when not. JUMP locks until the
# capsule re-lands (is_on_floor), after which the obstacle check resumes.
enum Locomotion { IDLE, WALK, CROUCH_WALK, JUMP, PRONE_CRAWL, VAULT }
const _SPEED_MULT := {
	Locomotion.IDLE: 0.0,
	Locomotion.WALK: 1.0,
	Locomotion.CROUCH_WALK: 0.55,
	Locomotion.JUMP: 1.0,
	Locomotion.PRONE_CRAWL: 0.30,
	Locomotion.VAULT: 0.0,    # capsule driven by lerp, not by walk speed
}
const _CAPSULE_HEIGHT := {
	Locomotion.IDLE: 1.8,
	Locomotion.WALK: 1.8,
	Locomotion.CROUCH_WALK: 1.20,
	Locomotion.JUMP: 1.8,
	Locomotion.PRONE_CRAWL: 0.55,
	Locomotion.VAULT: 1.8,
}
const _BODY_Y_SCALE := {
	Locomotion.IDLE: 1.0,
	Locomotion.WALK: 1.0,
	Locomotion.CROUCH_WALK: 0.66,
	Locomotion.JUMP: 1.0,
	Locomotion.PRONE_CRAWL: 0.30,
	Locomotion.VAULT: 1.0,
}
const _JUMP_VELOCITY  : float = 5.5
const _OBSTACLE_CHECK_INTERVAL : float = 0.20

# ── Vault / climb (#cluster VAULT_CLIMB) ─────────────────────────────────────
# When the NavigationAgent3D's next path segment steps up by more than CLIMB_MIN_DY
# but no more than CLIMB_MAX_DY, the NPC mantles up to that segment instead of
# getting stuck against the ledge. Below CLIMB_MIN_DY the existing step-up /
# physics carries it; above CLIMB_MAX_DY the obstacle is too tall to vault.
#
# TODO: real climb animation goes through AnimationTree once Phase 1 lands.
const CLIMB_MIN_DY     : float = 0.30   # navmesh agent_max_climb threshold
const CLIMB_MAX_DY     : float = 1.4    # matches player's CLIMB_MAX_HEIGHT
const CLIMB_DURATION_S : float = 0.5    # lerp time for the mantle
var _vault_locked  : bool    = false
var _vault_timer   : float   = 0.0
var _vault_start   : Vector3 = Vector3.ZERO
var _vault_end     : Vector3 = Vector3.ZERO

var locomotion : int = Locomotion.IDLE
var _capsule_shape : CapsuleShape3D = null
var _body_node     : Node3D = null
var _ray_head      : RayCast3D = null
var _ray_chest     : RayCast3D = null
var _ray_step      : RayCast3D = null
# ── Animation Phase 1 (cluster: Skeleton3D rig + locomotion BlendSpace) ──
# Cached AnimationTree under the HumanoidBody — the locomotion blend node's
# blend_position is updated every physics tick from horizontal velocity so the
# walk cycle (legs / arms / torso) ramps in as the NPC starts moving and ramps
# back to idle when stationary. See Humanoid._install_skeleton_rig().
# TODO Phase 2: feed the BlendSpace2D Y axis with strafe (velocity decomposed
# into local right vs facing direction). For Phase 1 we keep Y at 0.
var _anim_tree     : AnimationTree = null
const _ANIM_RUN_SPEED_NPC : float = 4.0    # m/s that maps to BlendSpace X=2 (run)

# ── Sine-based walking gait (audit item 2) ────────────────────────────────────
# Procedural leg + arm swing driven by ground-plane velocity. The Humanoid rig
# wraps each leg under a HipPivot_L / HipPivot_R Node3D and each arm under a
# ShoulderPivot_L / ShoulderPivot_R Node3D, so rotating those nodes about
# local X swings the whole limb around the hip/shoulder joint. _walk_phase
# accumulates at TAU / GAIT_STRIDE_M radians per metre walked, so one full
# L-then-R-then-L cycle covers GAIT_STRIDE_M metres of ground. Arms swing
# opposite their same-side leg (real human gait — left arm forward when right
# leg is forward). Resets toward 0 in IDLE so the limbs settle.
const GAIT_STRIDE_M       : float = 0.90   # one full cycle per 0.90 m
const GAIT_SWING_LEGS_RAD : float = 0.35   # ±~20° hip swing
const GAIT_SWING_ARMS_RAD : float = 0.25   # ±~14° shoulder swing
var _walk_phase     : float = 0.0
var _hip_pivot_l    : Node3D = null
var _hip_pivot_r    : Node3D = null
var _shoul_pivot_l  : Node3D = null
var _shoul_pivot_r  : Node3D = null
var _gait_cached    : bool   = false

var _obstacle_check_timer : float = 0.0
var _jump_locked   : bool  = false
var assigned_station_id: String  = ""
# #124 — facing the worker should hold once they arrive at home_position. NAN
# means "no opinion, keep whatever rotation the walk happened to leave". Set
# by CrewManager.assign_to_position for HIER-pinned crew so the operator can
# face them in a specific direction (e.g., looking at a machine).
var home_facing_rad    : float   = NAN
var service_station_id : String  = ""
var service_secs       : float   = 4.0       # dwell to clear a jam
var service_timer      : float   = 0.0
var arrive_dist        : float   = 1.6       # "close enough" to a target (m, horizontal)
var post_radius        : float   = 2.5       # idle wander radius around the post
var _purpose           : int     = Purpose.POST

signal fault_serviced(station_id: String)

func _ready() -> void:
	npc_name = name
	_build_name_tag()
	_install_nav_agent()
	_install_locomotion_state_machine()
	# Defer so global_position is valid after the node fully enters the tree
	call_deferred("_choose_random_wander_target")

# ── Phase 2 (#146): locomotion state machine setup ────────────────────────────
## Cache references to the capsule + humanoid body (tagged by MainWorld._spawn_npcs
## with the names "BodyCollision" and "HumanoidBody"), and build three forward
## RayCast3D children that the state machine reads each tick to pick the right
## pose for whatever obstacle is ahead.
func _install_locomotion_state_machine() -> void:
	var col_node := get_node_or_null("BodyCollision") as CollisionShape3D
	if col_node and col_node.shape is CapsuleShape3D:
		_capsule_shape = col_node.shape as CapsuleShape3D
	_body_node = get_node_or_null("HumanoidBody") as Node3D
	# Animation Phase 1: cache the AnimationTree on the HumanoidBody rig so
	# _physics_process can push the speed → blend_position update every tick.
	# Safe if the rig isn't present (test scenes) — _update_animation_blend
	# guards against null.
	_anim_tree = _resolve_anim_tree(_body_node)
	# Head-level forward ray — hit ⇒ overhead obstacle ⇒ CROUCH_WALK.
	_ray_head = RayCast3D.new()
	_ray_head.name = "RayHead"
	_ray_head.position = Vector3(0.0, 0.65, 0.0)            # ~1.55 m world height (capsule centre + 0.65)
	_ray_head.target_position = Vector3(0.0, 0.0, -0.9)     # look 0.9 m forward (NPC -Z = forward in walk dir)
	_ray_head.collide_with_areas = false
	_ray_head.collide_with_bodies = true
	# Don't hit self.
	_ray_head.add_exception(self)
	add_child(_ray_head)
	# Chest-level forward ray — hit ⇒ low pipe / duct ⇒ PRONE_CRAWL.
	_ray_chest = RayCast3D.new()
	_ray_chest.name = "RayChest"
	_ray_chest.position = Vector3(0.0, 0.15, 0.0)
	_ray_chest.target_position = Vector3(0.0, 0.0, -0.9)
	_ray_chest.add_exception(self)
	add_child(_ray_chest)
	# Step-up / gap ray — angled forward + down. Probes ahead of the NPC and
	# below the feet so a flat floor 0.5 m forward DEFINITELY hits the cast.
	# The previous geometry ended 0.1 m ABOVE the feet, so on flat factory floor
	# the ray missed every tick, the no-hit branch returned JUMP, and NPCs
	# jumped continuously. New cast: start at body center (≈0.9 m above feet),
	# end 1.5 m below body center + 0.8 m forward — well below floor level so
	# `not is_colliding()` only fires on a REAL gap.
	_ray_step = RayCast3D.new()
	_ray_step.name = "RayStep"
	_ray_step.position = Vector3(0.0, 0.0, 0.0)             # body centre
	_ray_step.target_position = Vector3(0.0, -1.5, -0.8)    # 0.8 m forward, 1.5 m down — reaches floor
	_ray_step.add_exception(self)
	add_child(_ray_step)

## Add a NavigationAgent3D child so the NPC pathfinds through the
## NavigationRegion3D MainWorld bakes from the floor + exterior ground. Agent
## tuned for a 1.8 m capsule: 0.4 m radius (matches the body capsule), 1.8 m
## height, 0.6 m arrive distance, 1.0 m path desired distance so corners read
## as smooth turns instead of stutters at every waypoint.
func _install_nav_agent() -> void:
	_nav_agent = NavigationAgent3D.new()
	_nav_agent.name = "NavAgent"
	_nav_agent.path_desired_distance = 0.7
	_nav_agent.target_desired_distance = arrive_dist
	_nav_agent.radius = 0.35
	_nav_agent.height = 1.8
	_nav_agent.max_speed = walk_speed
	# Avoidance OFF for now — Phase 2 will enable agent-vs-agent RVO once the
	# state machine can react to it. Plain pathing is enough to stop walking
	# through machine bodies.
	_nav_agent.avoidance_enabled = false
	# Stay on the floor — agents at human height shouldn't try to climb 2 m
	# obstacles, and the navmesh agent_max_climb already caps that.
	add_child(_nav_agent)

## Minecraft-style floating name tag: a billboard Label3D above the head, drawn
## on top (no depth test) so you can pick a worker out even behind a machine.
func _build_name_tag() -> void:
	var tag := Label3D.new()
	tag.name = "NameTag"
	tag.text = npc_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.position = Vector3(0.0, 1.25, 0.0)     # above the 1.8 m capsule's head
	tag.pixel_size = 0.006
	tag.font_size = 64
	tag.outline_size = 16
	tag.modulate = Color(1, 1, 1)
	tag.outline_modulate = Color(0, 0, 0, 0.85)
	tag.no_depth_test = true                   # show through geometry (find them on the floor)
	tag.render_priority = 2
	tag.fixed_size = false                     # world-space — scales with distance
	add_child(tag)

func _physics_process(delta: float) -> void:
	# Vault/climb override (#cluster VAULT_CLIMB): while a mantle tween is
	# active, we own the transform directly — gravity, walk, nav, jump all stand
	# aside until we set the NPC down on top of the ledge.
	if _vault_locked:
		_advance_vault(delta)
		return
	# #198 — autonomy tick has highest priority. If an autonomy task is active
	# (or the board hands one out this tick), it owns the target_position.
	# Falls through to the legacy wander/managed code path only when idle.
	_autonomy_tick(delta)
	if _autonomy_destination_active:
		# Task is steering the NPC; skip the free-wander / managed-post motion
		# decisions and let the locomotion code drive the body toward
		# target_position. The task's tick() will clear the destination when
		# it advances or completes.
		pass
	elif not managed:
		_update_wander(delta)            # legacy free wander
	else:
		_managed_motion(delta)

	# Phase 2 (#146): pick / apply the locomotion state (IDLE / WALK / CROUCH /
	# JUMP / PRONE) BEFORE deriving velocity so the speed multiplier + jump
	# impulse apply this tick. The state machine also resizes the capsule + the
	# body's Y-scale to match the pose (taller for stand, shorter for crouch).
	_update_locomotion(delta)

	# Audit item 2 — sine-based walking gait. _walk_phase advances by the ground
	# distance walked this tick (TAU per GAIT_STRIDE_M), then _apply_gait pushes
	# sin(phase)*amp onto the Humanoid's HipPivot_L/R and ShoulderPivot_L/R
	# nodes so the legs and arms visibly swing. The cache is lazy so a fresh
	# spawn whose body hasn't entered the tree yet won't bind to null.
	_advance_walk_phase(delta)
	_apply_gait()

	# Apply gravity
	if not is_on_floor():
		current_velocity.y -= 9.8 * delta
	# Land detection — clear the jump lock so the obstacle check can pick a
	# normal pose again. JUMP keeps XZ velocity but adds the impulse to Y.
	elif _jump_locked:
		_jump_locked = false
		locomotion = Locomotion.WALK

	# Move towards target (unless the brain wants us standing still). The
	# `direction.length_squared() > 0.0001` guard catches the floating-point
	# edge case where horiz_dist > arrive_dist passes but `target - global` is
	# effectively zero after zeroing Y (target floats directly above/below the
	# NPC). Without it `.normalized()` returns NaN and move_and_slide poisons
	# the body's transform — 9 NPCs each producing NaN every frame is the
	# `instance_set_transform !v.is_finite()` smoking gun.
	if is_walking and _horiz_dist(target_position) > arrive_dist:
		# Sync the agent's destination from `target_position` (which CrewManager
		# / wander logic mutates directly). Re-targeting on the same value is
		# a no-op inside the agent, so it's safe to call every tick — we only
		# pay the path-replan cost when the destination actually moves.
		var direction : Vector3
		if _nav_agent != null:
			if not target_position.is_equal_approx(_last_nav_target):
				_nav_agent.target_position = target_position
				_last_nav_target = target_position
			# get_next_path_position returns the next waypoint along the routed
			# path, or the agent's own position if it can't route (no navmap
			# baked yet, target unreachable, etc.). Falling back to straight-
			# line in that case keeps unmanaged / pre-navmesh worlds working.
			var next_wp : Vector3 = _nav_agent.get_next_path_position()
			if next_wp.distance_to(global_position) < 0.05:
				# Fallback: agent has no path (navmesh empty / disabled / first
				# tick before bake completes). Use the straight-line direction
				# so the NPC still moves instead of standing frozen.
				direction = target_position - global_position
			else:
				# Vault / climb (#cluster VAULT_CLIMB): if the next path
				# waypoint is meaningfully higher than the NPC's current Y
				# (more than agent_max_climb but no more than the player's
				# max mantle), the agent is trying to walk us up onto a ledge.
				# Trigger a vault tween instead of fighting the physics.
				var dy : float = next_wp.y - global_position.y
				if not _vault_locked and dy > CLIMB_MIN_DY and dy <= CLIMB_MAX_DY:
					_start_vault(next_wp)
					return        # vault tween consumes the rest of this tick
				direction = next_wp - global_position
		else:
			direction = target_position - global_position
		direction.y = 0
		if direction.length_squared() > 0.0001:
			direction = direction.normalized()
			# Phase 2 (#146): apply per-state speed multiplier so crouching and
			# prone-crawling actually look slow, jump preserves run pace.
			var spd : float = walk_speed * float(_SPEED_MULT.get(locomotion, 1.0))
			current_velocity.x = direction.x * spd
			current_velocity.z = direction.z * spd
			# Face the walk direction. CANONICAL CONVENTION: forward = local -Z,
			# so we want -basis.z to point along `direction`. atan2(-x, -z) makes
			# the body yaw so that its -Z axis aligns with the walk vector — the
			# Humanoid's face (built on -Z per VISUAL FRONT RULE) then correctly
			# leads motion. Previously this was atan2(x, z), which inverted the
			# convention and made the body walk backwards relative to its face.
			rotation.y = atan2(-direction.x, -direction.z)
		else:
			current_velocity.x = 0
			current_velocity.z = 0
	else:
		current_velocity.x = 0
		# #124 — arrived at post AND the operator specified a facing direction
		# (HIER pin): snap rotation so the worker holds that orientation. Default
		# stays NAN for everyone else so this is a no-op for the regular crew.
		if not is_nan(home_facing_rad):
			rotation.y = home_facing_rad
		current_velocity.z = 0

	velocity = current_velocity
	move_and_slide()

	# Animation Phase 1: feed horizontal velocity into the locomotion
	# BlendSpace2D so the walk / run pose blends with idle as the NPC moves.
	_update_animation_blend()

## Managed body motion: AT_POST idles in a small wander around the post; GOING
## heads to its target; SERVICING / ON_BREAK / OFF_DUTY stand still. The brain
## (state transitions, service timer) is advanced by CrewManager.step_brain().
func _managed_motion(delta: float) -> void:
	match task_state:
		Task.AT_POST:
			wander_timer -= delta
			if wander_timer <= 0.0:
				_wander_near(home_position, post_radius)
				wander_timer = wander_change_interval
			is_walking = true
		Task.GOING:
			is_walking = true
		_:
			is_walking = false

func _update_wander(delta: float) -> void:
	"""Update wandering behavior."""
	wander_timer -= delta

	if wander_timer <= 0:
		_choose_random_wander_target()
		wander_timer = wander_change_interval

func _choose_random_wander_target() -> void:
	"""Pick a random target within wander radius."""
	var random_offset = Vector3(
		randf_range(-wander_radius, wander_radius),
		0,
		randf_range(-wander_radius, wander_radius)
	)
	target_position = global_position + random_offset
	is_walking = true

# =============================================================================
# CREW BRAIN  (advanced by CrewManager.step_brain — no physics dependency)
# =============================================================================
## Advance one logic step. Returns a station id when a service has JUST completed
## this step (so the caller can apply the world effect, e.g. relieve the jam),
## otherwise "". Also auto-returns the worker to its post after servicing.
func step_brain(delta: float) -> String:
	if not managed:
		return ""
	# #147 — operate-target planner runs first; if it's the active task, route
	# all brain ticks there instead of through the legacy service path.
	if task_state == Task.PLAN_OPERATE \
			or task_state == Task.WALK_TO_TARGET \
			or task_state == Task.WALK_TO_LIFT \
			or task_state == Task.WAIT_BOARD_LIFT \
			or task_state == Task.OPERATING \
			or task_state == Task.RELEASING_LIFT:
		return _step_operate_brain(delta)
	match task_state:
		Task.GOING:
			if has_arrived():
				match _purpose:
					Purpose.SERVICE:
						task_state   = Task.SERVICING
						service_timer = service_secs
					Purpose.BREAK:
						task_state = Task.ON_BREAK
					_:
						task_state = Task.AT_POST
		Task.SERVICING:
			service_timer -= delta
			if service_timer <= 0.0:
				var sid := service_station_id
				service_station_id = ""
				emit_signal("fault_serviced", sid)
				return_to_post()
				return sid
	return ""

func has_arrived() -> bool:
	return _horiz_dist(target_position) <= arrive_dist

func _horiz_dist(p: Vector3) -> float:
	var a := global_position; a.y = 0.0
	var b := p;               b.y = 0.0
	return a.distance_to(b)

# ── Phase 3 prep ──────────────────────────────────────────────────────────────
## True if `world_pos` is within arm's reach of a standing worker at `global_position`.
## Used by the task planner (#147) — if false, the planner queues a "use mast
## lift" subtask so the operator doesn't try to grab a 6-m-high conveyor stop
## button while standing on the floor.
func can_reach(world_pos: Vector3) -> bool:
	var feet_y : float = global_position.y - 0.9       # capsule centre - half-height
	return (world_pos.y - feet_y) <= reach_height_max

# =============================================================================
# #147 Phase 3 — task planner for "operate target at world_pos"
# =============================================================================
# Public entry point: CrewManager (or any scheduler) calls dispatch_to_operate
# with a world target + a callback to fire when the operator is in position +
# the dwell has expired. The planner picks the path:
#   reachable from floor  → WALK_TO_TARGET → OPERATING (dwell) → fire callback
#   need lift             → claim nearest free lift → WALK_TO_LIFT →
#                           (Phase 4 wires WAIT_BOARD_LIFT / RIDING_LIFT) →
#                           OPERATING → RELEASING_LIFT → fire callback
# Phase 3 ships the decision + reservation; Phase 4 fills the board / dismount.

var _operate_target_pos : Vector3 = Vector3.ZERO
var _operate_callback   : Callable = Callable()
var _operate_dwell_s    : float = 4.0
var _claimed_lift       : Node = null
# Reference set by CrewManager so dispatch_to_operate can find a free lift.
var lift_booking        : LiftBooking = null

# #148 Phase 4 — dwell for the boarding/dismounting beat (door swing + climb
# in/out). Keeps the action visually distinct from a teleport.
const BOARDING_DWELL_S : float = 1.2

# #148 Phase 4 — generic vehicle boarding (not lift-specific). Public entry
# point if a non-lift task needs the NPC to board a forklift / car / clamp.
# Same state machine as the lift path: WALK_TO_BOARDING_POS → BOARDING →
# (caller-controlled) → DISMOUNTING. on_done fires after dismount with reason.
var board_target_vehicle : Node = null
var board_callback       : Callable = Callable()

func dispatch_to_operate(target_world_pos: Vector3, on_done: Callable,
		dwell_s: float = 4.0) -> void:
	managed = true
	on_duty = true
	_operate_target_pos = target_world_pos
	_operate_callback   = on_done
	_operate_dwell_s    = dwell_s
	_purpose            = Purpose.OPERATE
	task_state          = Task.PLAN_OPERATE

## Called by CrewManager.step_brain (which calls NPC.step_brain). When the brain
## is in any PLAN_OPERATE-derived state, run the planner. Returns "" most ticks;
## returns "operate_done" the tick the callback fires.
func _step_operate_brain(delta: float) -> String:
	match task_state:
		Task.PLAN_OPERATE:
			if can_reach(_operate_target_pos):
				# Reachable from the floor: head straight to the target XZ. Y
				# is dropped for walk; arrive_dist handles the dwell trigger.
				target_position = Vector3(_operate_target_pos.x,
					global_position.y, _operate_target_pos.z)
				is_walking = true
				task_state = Task.WALK_TO_TARGET
			else:
				# Need a lift. Claim the nearest free one.
				if lift_booking == null:
					push_warning("[%s] need lift but no LiftBooking wired" % npc_name)
					_finish_operate("no_booking")
					return ""
				var lift : Node = lift_booking.find_nearest_free(global_position)
				if lift == null or not lift_booking.claim(lift, npc_name):
					push_warning("[%s] no free mast lift available" % npc_name)
					_finish_operate("no_lift_available")
					return ""
				# Sanity: does this lift reach high enough?
				if lift.has_method("max_reach_top_y"):
					var max_y : float = float(lift.call("max_reach_top_y", reach_height_max))
					if max_y < _operate_target_pos.y:
						push_warning("[%s] nearest lift max_reach %.1fm < target %.1fm" \
							% [npc_name, max_y, _operate_target_pos.y])
						lift_booking.release(lift, npc_name)
						_finish_operate("lift_too_short")
						return ""
				_claimed_lift = lift
				# Walk to the lift's dismount/boarding spot.
				var board_pos : Vector3 = lift.global_position
				if lift.has_method("get_dismount_position"):
					board_pos = lift.call("get_dismount_position")
				target_position = Vector3(board_pos.x, global_position.y, board_pos.z)
				is_walking = true
				task_state = Task.WALK_TO_LIFT
		Task.WALK_TO_TARGET:
			if has_arrived():
				is_walking = false
				task_state = Task.OPERATING
				service_timer = _operate_dwell_s
		Task.WALK_TO_LIFT:
			if has_arrived():
				is_walking = false
				# #148 Phase 4 — head to the boarding spot beside the lift's
				# driver door instead of teleporting in.
				if _claimed_lift != null and _claimed_lift.has_method("get_boarding_position"):
					var bp : Vector3 = _claimed_lift.call("get_boarding_position")
					target_position = Vector3(bp.x, global_position.y, bp.z)
					is_walking = true
				task_state = Task.WALK_TO_BOARDING_POS
		Task.WALK_TO_BOARDING_POS:
			if has_arrived():
				is_walking = false
				task_state = Task.BOARDING
				service_timer = BOARDING_DWELL_S    # door swing + climb-in beat
		Task.BOARDING:
			service_timer -= delta
			if service_timer <= 0.0:
				# Actually board now — parents NPC under SeatMarker, flips
				# vehicle.occupied=true, mirrors player's on_operator_entered.
				if _claimed_lift != null and _claimed_lift.has_method("on_npc_entered"):
					_claimed_lift.call("on_npc_entered", self)
				# #157 — drive the lift over to the target's XZ so the
				# operator's vertical reach actually covers it. Without this,
				# raising the platform only helps when the lift was already
				# parked under the goal. Off-screen for the operator (the lift
				# "drove itself there"); the platform raise then handles the Y.
				if _claimed_lift is Node3D:
					var lift_pos := (_claimed_lift as Node3D).global_position
					(_claimed_lift as Node3D).global_position = Vector3(
						_operate_target_pos.x, lift_pos.y, _operate_target_pos.z)
				_drive_lift_to_target_height()
				task_state = Task.WAIT_BOARD_LIFT
		Task.WAIT_BOARD_LIFT:
			# Wait for the platform to reach the target height; that's when
			# the operator can perform the action at the target.
			if _claimed_lift != null and is_instance_valid(_claimed_lift) \
					and _claimed_lift.has_method("is_at_autonomous_target") \
					and _claimed_lift.call("is_at_autonomous_target"):
				task_state = Task.OPERATING
				service_timer = _operate_dwell_s
		Task.OPERATING:
			service_timer -= delta
			if service_timer <= 0.0:
				if _claimed_lift != null:
					task_state = Task.RELEASING_LIFT
					_claimed_lift.call("set_autonomous_target_top_world_y",
						_claimed_lift.global_position.y + 0.5)   # back to stowed
				else:
					_finish_operate("ok")
					return "operate_done"
		Task.RELEASING_LIFT:
			if _claimed_lift != null and is_instance_valid(_claimed_lift) \
					and _claimed_lift.has_method("is_at_autonomous_target") \
					and _claimed_lift.call("is_at_autonomous_target"):
				_claimed_lift.call("release_autonomous_target")
				# #148 Phase 4 — dismount sequence: short dwell for the
				# stand-up + open-door + step-down beat, then reparent + flip
				# occupied=false in on_npc_exited.
				task_state = Task.DISMOUNTING
				service_timer = BOARDING_DWELL_S
		Task.DISMOUNTING:
			service_timer -= delta
			if service_timer <= 0.0:
				if _claimed_lift != null and _claimed_lift.has_method("on_npc_exited"):
					_claimed_lift.call("on_npc_exited", self)
				if lift_booking != null:
					lift_booking.release(_claimed_lift, npc_name)
				_claimed_lift = null
				_finish_operate("ok")
				return "operate_done"
		_:
			pass
	return ""

## Command the claimed lift to raise its platform so the operator on board can
## reach the target. Stops _operate_target_pos.y BELOW the platform top by
## (reach_height_max - 0.2) so the operator's arm reach still covers the goal
## without overshooting.
func _drive_lift_to_target_height() -> void:
	if _claimed_lift == null or not _claimed_lift.has_method("set_autonomous_target_top_world_y"):
		return
	var platform_top_target : float = _operate_target_pos.y - (reach_height_max - 0.3)
	_claimed_lift.call("set_autonomous_target_top_world_y", platform_top_target)

func _finish_operate(reason: String) -> void:
	is_walking = false
	if _operate_callback.is_valid():
		_operate_callback.call(reason)
	_operate_callback = Callable()
	task_state = Task.AT_POST

func _wander_near(center: Vector3, radius: float) -> void:
	target_position = center + Vector3(
		randf_range(-radius, radius), 0.0, randf_range(-radius, radius))
	is_walking = true

# ── Public API used by CrewManager ────────────────────────────────────────────
func assign_post(station_id: String, pos: Vector3) -> void:
	managed             = true
	on_duty             = true
	assigned_station_id = station_id
	home_position       = pos
	target_position     = pos
	task_state          = Task.AT_POST
	is_walking          = true

func dispatch_to(pos: Vector3, station_id: String, secs: float = -1.0) -> void:
	service_station_id = station_id
	if secs > 0.0:
		service_secs = secs
	target_position = pos
	_purpose        = Purpose.SERVICE
	task_state      = Task.GOING
	is_walking      = true

func go_on_break(pos: Vector3) -> void:
	target_position = pos
	_purpose        = Purpose.BREAK
	task_state      = Task.GOING
	is_walking      = true

func return_to_post() -> void:
	target_position = home_position
	_purpose        = Purpose.POST
	task_state      = Task.GOING
	is_walking      = true

func set_off_duty(off: bool) -> void:
	on_duty = not off
	if off:
		task_state = Task.OFF_DUTY
		is_walking = false
		# Cancel any in-flight operate (mast-lift / reach plan) so the worker
		# doesn't keep driving a lift platform after being yanked off-duty by
		# the time-rewind path. Releasing the lift booking + nullifying the
		# callback keeps the lift available for the next dispatch instead of
		# staying claimed by a frozen off-duty worker.
		if _operate_callback.is_valid():
			_operate_callback = Callable()
		if _claimed_lift != null and is_instance_valid(_claimed_lift):
			if _claimed_lift.has_method("release_autonomous_target"):
				_claimed_lift.call("release_autonomous_target")
			if _claimed_lift.has_method("on_npc_exited"):
				_claimed_lift.call("on_npc_exited", self)
			# Release the booking via the runtime autoload (matches the path the
			# normal _finish_operate cleanup at NPC.gd:626-630 uses). Resolved
			# lazily so the headless test harness — which has no autoload —
			# still parses + runs without crashing on a missing singleton.
			var lb := get_node_or_null("/root/lift_booking")
			if lb != null and lb.has_method("release"):
				lb.call("release", _claimed_lift, npc_name)
			_claimed_lift = null
	elif task_state == Task.OFF_DUTY:
		return_to_post()

## Clear the worker's post assignment WITHOUT requiring a re-post.
## Used by CrewManager._on_time_set when the operator rewinds the clock into
## pre-shift territory: the worker needs to be off-duty AND have its stale
## assigned_station_id wiped so current_task() doesn't print "post: …" for an
## NPC that PreShiftSequence is about to teleport to arrival_anchor / dressing.
## Symmetric to assign_post (which sets all three). Safe to call on an
## already-off-duty worker.
func clear_post() -> void:
	assigned_station_id = ""
	service_station_id  = ""
	managed             = true   # CrewManager still owns them, just not posted
	set_off_duty(true)

## Free to be dispatched: managed, on duty, and standing at its post.
func is_available() -> bool:
	return managed and on_duty and task_state == Task.AT_POST

func is_servicing() -> bool: return task_state == Task.SERVICING
func is_on_break()  -> bool: return task_state == Task.ON_BREAK
func is_off_duty()  -> bool: return task_state == Task.OFF_DUTY

## Short human-readable status for the HUD crew roster.
func current_task() -> String:
	match task_state:
		Task.AT_POST:
			return "post: %s" % assigned_station_id
		Task.GOING:
			match _purpose:
				Purpose.SERVICE: return "→ storing %s" % service_station_id
				Purpose.BREAK:   return "→ pauze"
				_:               return "→ post"
		Task.SERVICING: return "verhelpt %s" % service_station_id
		Task.ON_BREAK:  return "pauze"
		Task.OFF_DUTY:  return "vrij (rust)"
		_:              return "rondlopen"

func add_relationship_points(npc_id: String, points: int) -> void:
	"""Add relationship points with another NPC (mutual-aid)."""
	if not relationship_points.has(npc_id):
		relationship_points[npc_id] = 0
	relationship_points[npc_id] += points

func get_relationship_points(npc_id: String) -> int:
	"""Get relationship points with another NPC."""
	return relationship_points.get(npc_id, 0)

func set_helping(target: Node) -> void:
	"""Set this NPC to help another NPC/task."""
	help_target = target
	is_helping = true

func stop_helping() -> void:
	"""Stop helping."""
	is_helping = false
	help_target = null

func get_role_string() -> String:
	"""Return human-readable role."""
	var roles = {
		"shift_leader": "Shift Leader",
		"asst_shift_leader": "Assistant Shift Leader",
		"extruder_op": "Extruder Operator",
		"feeder": "Feeder",
		"permanent_feeder": "Permanent Feeder",
		"transitional": "Transitional (Feeder→Extruder)",
		"all_rounder": "All-Rounder",
		"production_manager": "Production Manager",
	}
	return roles.get(npc_role, npc_role)

# =============================================================================
# Vault / climb  (#cluster VAULT_CLIMB)
# =============================================================================
## Begin a mantle from current position up to `dest_world` (a navmesh waypoint
## that is CLIMB_MIN_DY..CLIMB_MAX_DY higher than the NPC's current Y). Owns
## the transform until the lerp completes — no walk velocity, no gravity. The
## locomotion state flips to VAULT so the pose/scale matches a "climbing up"
## body instead of a "walking" body.
## TODO: real climb animation goes through AnimationTree once Phase 1 lands.
func _start_vault(dest_world: Vector3) -> void:
	_vault_locked = true
	_vault_timer  = 0.0
	_vault_start  = global_position
	# Bias the landing slightly past the ledge edge so we don't fall back off.
	var planar_dir := Vector3(dest_world.x - global_position.x, 0.0,
		dest_world.z - global_position.z)
	if planar_dir.length_squared() > 0.0001:
		planar_dir = planar_dir.normalized() * 0.4
	else:
		planar_dir = Vector3.ZERO
	_vault_end = Vector3(dest_world.x, dest_world.y, dest_world.z) + planar_dir
	current_velocity = Vector3.ZERO
	locomotion = Locomotion.VAULT

## Advance the vault tween. Lerps from _vault_start → _vault_end over
## CLIMB_DURATION_S seconds with ease-out. When the tween completes, hand
## control back to the normal locomotion / pathfinding loop.
func _advance_vault(delta: float) -> void:
	_vault_timer += delta
	var t := clampf(_vault_timer / CLIMB_DURATION_S, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - t, 2.0)
	global_position = _vault_start.lerp(_vault_end, eased)
	_update_animation_blend()
	if t >= 1.0:
		_vault_locked = false
		_vault_timer = 0.0
		current_velocity = Vector3.ZERO
		locomotion = Locomotion.WALK

# =============================================================================
# Phase 2 (#146) — locomotion state machine
# =============================================================================
## Pick a new locomotion state from the obstacle raycasts (rate-limited so we
## don't re-resize the capsule every frame), then apply the resulting pose
## (capsule height, body Y-scale, jump impulse).
func _update_locomotion(delta: float) -> void:
	if _capsule_shape == null:
		return                        # not fully installed (e.g. in test scenes)
	# JUMP locks until landing — see _physics_process gravity block.
	if _jump_locked:
		_apply_locomotion_pose()
		return
	# Refresh the obstacle check at OBSTACLE_CHECK_INTERVAL. If we're idle
	# (no walking intent) we just hold the IDLE pose; nothing to detect.
	_obstacle_check_timer -= delta
	if _obstacle_check_timer <= 0.0:
		_obstacle_check_timer = _OBSTACLE_CHECK_INTERVAL
		var want_walk : bool = is_walking and _horiz_dist(target_position) > arrive_dist
		if not want_walk:
			locomotion = Locomotion.IDLE
		else:
			locomotion = _classify_obstacle_ahead()
			# JUMP triggers an impulse the first tick it's entered.
			if locomotion == Locomotion.JUMP:
				current_velocity.y = _JUMP_VELOCITY
				_jump_locked = true
	_apply_locomotion_pose()

## Read the three forward raycasts and return the appropriate locomotion state.
## Priority: low pipe (PRONE) > overhead (CROUCH) > step/gap (JUMP) > default (WALK).
func _classify_obstacle_ahead() -> int:
	# Chest-level hit means there's something blocking at ~waist height —
	# can't crouch under that, have to crawl. Highest priority.
	if _ray_chest != null and _ray_chest.is_colliding():
		return Locomotion.PRONE_CRAWL
	# Head-level hit but chest clear = overhead obstacle, crouch under it.
	if _ray_head != null and _ray_head.is_colliding():
		return Locomotion.CROUCH_WALK
	# Step-up / gap detection: if the angled-down step ray finds nothing,
	# there's no ground 1 m ahead at floor level — that's either a gap (jump)
	# or a tall obstacle (jump up). Either way: JUMP.
	if _ray_step != null and not _ray_step.is_colliding():
		return Locomotion.JUMP
	return Locomotion.WALK

## Apply the current state's pose: resize capsule height + offset, scale the
## humanoid body's Y, lower its origin so the feet stay on the floor (the
## body is built around the node origin = capsule centre; when crouched the
## capsule shrinks upward so the body's centre lowers proportionally).
func _apply_locomotion_pose() -> void:
	if _capsule_shape == null:
		return
	var h : float = float(_CAPSULE_HEIGHT.get(locomotion, 1.8))
	if absf(_capsule_shape.height - h) > 0.001:
		_capsule_shape.height = h
	# Body Y-scale only — XZ stays 1.0 so shoulders don't squash.
	if _body_node != null:
		var ys : float = float(_BODY_Y_SCALE.get(locomotion, 1.0))
		if absf(_body_node.scale.y - ys) > 0.001:
			_body_node.scale = Vector3(1.0, ys, 1.0)
			# Lower the body so its feet stay on the floor — the body mesh is
			# centred at the node origin, scaling Y shrinks toward that origin,
			# so we have to shift it DOWN by half the height loss.
			var origin_drop : float = (1.8 - h) * 0.5
			_body_node.position.y = -origin_drop

# =============================================================================
# Animation Phase 1 — feed velocity into the AnimationTree's BlendSpace2D
# =============================================================================
## Look for the AnimationTree node Humanoid._install_skeleton_rig parented
## directly under the rig root ("HumanoidBody"). Returns null if the body has
## no rig (test scenes / legacy NPC.tscn without a Humanoid child).
func _resolve_anim_tree(body_node: Node) -> AnimationTree:
	if body_node == null:
		return null
	# Direct child first — that's where _install_skeleton_rig puts it.
	var direct := body_node.get_node_or_null("AnimationTree")
	if direct is AnimationTree:
		return direct as AnimationTree
	# Fallback: recursive scan, in case a future patch nests the rig.
	for c in body_node.get_children():
		if c is AnimationTree:
			return c as AnimationTree
		if c is Node:
			var hit := _resolve_anim_tree(c)
			if hit != null:
				return hit
	return null

## Map the NPC's horizontal speed onto the BlendSpace2D's X axis so the rig
## blends idle (0) → walk (1) → run (2). Y is reserved for strafe in Phase 2.
##
## When the rig got rebuilt by Humanoid.rebuild_appearance (wardrobe swap), the
## old AnimationTree was freed with the body; refresh the cached reference if
## the previously-cached one is no longer valid.
## Phase 2: travel the AnimationTree's StateMachine to match locomotion. Same
## param layout as PlayerController._update_animation_blend.
var _last_anim_state : String = "locomotion"

func _update_animation_blend() -> void:
	if _anim_tree == null or not is_instance_valid(_anim_tree):
		# Rebuilt by Humanoid.rebuild_appearance — re-resolve under the (possibly
		# replaced) body node. Safe no-op if still not present.
		_body_node = get_node_or_null("HumanoidBody") as Node3D
		_anim_tree = _resolve_anim_tree(_body_node)
		if _anim_tree == null:
			return
	# Map NPC.Locomotion → state name. CROUCH_WALK = held crouch pose (Phase 3
	# would author a crouch-walk locomotion BlendSpace row). PRONE_CRAWL = prone.
	# VAULT uses the vault climbing pose. JUMP keeps using the locomotion state.
	var want_state : String = "locomotion"
	match locomotion:
		Locomotion.CROUCH_WALK: want_state = "crouch"
		Locomotion.PRONE_CRAWL: want_state = "prone"
		Locomotion.VAULT:       want_state = "vault"
		_:                      want_state = "locomotion"
	# NPC sitting in vehicle — set via assign_vehicle / clear_vehicle in the
	# vehicle entry code.
	if npc_autopilot_seated:
		want_state = "seated"
	if want_state != _last_anim_state:
		var pb := _anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if pb != null:
			pb.travel(want_state)
		_last_anim_state = want_state
	if want_state != "locomotion":
		return
	var horiz : float = Vector2(velocity.x, velocity.z).length()
	var walk_t : float = horiz / maxf(walk_speed, 0.1)
	var bx : float = clampf(walk_t, 0.0, 2.0)
	if horiz < 0.05:
		bx = 0.0
	_anim_tree.set("parameters/locomotion/blend_position", Vector2(bx, 0.0))

## Flagged by FeederWorker / vehicle entry code when the NPC sits down.
var npc_autopilot_seated : bool = false

# =============================================================================
# Sine-based walking gait (audit item 2)
# =============================================================================
## Resolve the four limb-pivot Node3Ds the gait animator rotates. Humanoid.build
## adds them as named children of the rig root ("HipPivot_L", "HipPivot_R",
## "ShoulderPivot_L", "ShoulderPivot_R"). Called lazily so a body that hasn't
## entered the scene tree yet doesn't poison the cache with null lookups.
func _cache_gait_pivots() -> void:
	# Invalidate if the previously-cached pivots were freed (Humanoid.rebuild_appearance
	# swaps the body out and the old pivots are queue_freed). Cheap is_instance_valid
	# check per-tick keeps the cache honest without a signal subscription.
	if _gait_cached:
		var all_ok : bool = true
		if _hip_pivot_l != null and not is_instance_valid(_hip_pivot_l):
			all_ok = false
		if _hip_pivot_r != null and not is_instance_valid(_hip_pivot_r):
			all_ok = false
		if _shoul_pivot_l != null and not is_instance_valid(_shoul_pivot_l):
			all_ok = false
		if _shoul_pivot_r != null and not is_instance_valid(_shoul_pivot_r):
			all_ok = false
		if all_ok:
			return
		# At least one pivot was freed — drop the cache and re-resolve below.
		_hip_pivot_l = null
		_hip_pivot_r = null
		_shoul_pivot_l = null
		_shoul_pivot_r = null
		_gait_cached = false
	if _body_node == null or not is_instance_valid(_body_node):
		_body_node = get_node_or_null("HumanoidBody") as Node3D
		if _body_node == null:
			return
	_hip_pivot_l   = _body_node.get_node_or_null("HipPivot_L")    as Node3D
	_hip_pivot_r   = _body_node.get_node_or_null("HipPivot_R")    as Node3D
	_shoul_pivot_l = _body_node.get_node_or_null("ShoulderPivot_L") as Node3D
	_shoul_pivot_r = _body_node.get_node_or_null("ShoulderPivot_R") as Node3D
	# Cache only when we found at least one pivot — otherwise re-try next tick.
	if _hip_pivot_l != null or _hip_pivot_r != null \
			or _shoul_pivot_l != null or _shoul_pivot_r != null:
		_gait_cached = true

## Advance the gait phase by the ground distance travelled this tick (only
## while we're meant to be walking and the locomotion state is one of the
## moving ones). Maps TAU of phase per GAIT_STRIDE_M of ground, so the cycle
## naturally scales with speed: faster walk = faster swing.
func _advance_walk_phase(delta: float) -> void:
	var moving := is_walking and (locomotion == Locomotion.WALK \
			or locomotion == Locomotion.CROUCH_WALK \
			or locomotion == Locomotion.PRONE_CRAWL)
	if not moving:
		# Settle phase toward 0 over ~0.3s when stopped so the limbs come to rest
		# at neutral instead of freezing mid-swing.
		_walk_phase = move_toward(_walk_phase, 0.0, delta * TAU * 2.0)
		return
	var horiz : float = Vector2(velocity.x, velocity.z).length()
	# Distance walked this tick → phase delta (TAU per GAIT_STRIDE_M metres).
	var phase_d : float = (horiz * delta / maxf(GAIT_STRIDE_M, 0.01)) * TAU
	_walk_phase = fposmod(_walk_phase + phase_d, TAU)

## DEPRECATED (Animation Phase 1): the legacy sine-gait drove the four limb
## pivots (HipPivot_*, ShoulderPivot_*) directly. Phase 1 reparents every limb
## mesh OUT from under those pivots and under a BoneAttachment3D bound to a
## Skeleton3D, then drives the bones via an AnimationTree BlendSpace2D. The
## pivots are still emitted by Humanoid.build() but their children are now empty,
## so rotating them would do nothing. This stub is kept so any future caller
## that still invokes _apply_gait() is a clean no-op (not a script error and
## NOT a competing pose source vs the AnimationTree). The whole sine-gait block
## (constants, vars, _cache_gait_pivots, _advance_walk_phase, _apply_gait) is
## slated for removal once Phase 1 lands in-game. The animation surface is now
## _update_animation_blend() / Humanoid._install_skeleton_rig().
func _apply_gait() -> void:
	# Intentionally empty — driven by the AnimationTree BlendSpace2D now.
	pass
