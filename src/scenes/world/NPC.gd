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
enum Task { FREE, AT_POST, GOING, SERVICING, ON_BREAK, OFF_DUTY }
enum Purpose { POST, SERVICE, BREAK }

var managed            : bool    = false
var on_duty            : bool    = true
var task_state         : int     = Task.FREE
var home_position      : Vector3 = Vector3.ZERO
var assigned_station_id: String  = ""
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
	# Defer so global_position is valid after the node fully enters the tree
	call_deferred("_choose_random_wander_target")

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
	# Pick where the body should be heading this frame. Unmanaged NPCs free-wander
	# exactly as before; managed NPCs head to the target their brain has set, idling
	# in a small wander around their post and standing still while servicing/on break.
	if not managed:
		_update_wander(delta)            # legacy free wander
	else:
		_managed_motion(delta)

	# Apply gravity
	if not is_on_floor():
		current_velocity.y -= 9.8 * delta

	# Move towards target (unless the brain wants us standing still)
	if is_walking and _horiz_dist(target_position) > arrive_dist:
		var direction = (target_position - global_position)
		direction.y = 0  # Keep horizontal only
		direction = direction.normalized()
		current_velocity.x = direction.x * walk_speed
		current_velocity.z = direction.z * walk_speed
	else:
		current_velocity.x = 0
		current_velocity.z = 0

	velocity = current_velocity
	move_and_slide()

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
	elif task_state == Task.OFF_DUTY:
		return_to_post()

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
