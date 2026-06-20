extends Node3D
class_name ShiftLifecycleManager

const PRE_SHIFT_WINDOW_S : float = 30.0 * 60.0
const NPC_DRIVE_SPEED_MPS : float = 8.0

# How long BEFORE arrives_at_s the NPC car is visible on the road, driving in.
# The drive-in polyline is ~119 m long; NPC_DRIVE_SPEED_MPS = 8 m/s traverses
# it in ~15 s, so the window matches the polyline length / speed exactly. With
# a longer window the car would just sit at the polyline endpoint for the lead
# time before actually moving — bad. With a shorter window the car would pop
# in mid-segment instead of at the far entry. Outside the window the car is
# HIDDEN so it isn't floating motionless waiting for its slot.
const DRIVE_IN_WINDOW_S : float = 15.0

var _world : Node = null
var _shift_clock : Node = null
var _staff_parking : Node = null
var _player_spawn_pos : Vector3 = Vector3.ZERO

func _ready() -> void:
	if _world == null:
		_world = get_parent()
	# #198 — _on_time_jumped only fires on big clock jumps. To make the drive-in
	# actually animate (cars rolling smoothly toward the bay over DRIVE_IN_WINDOW_S
	# seconds, not teleporting between positions on jump events), we run the
	# position pass every physics frame while the clock is in pre-shift.
	set_physics_process(true)

func _physics_process(_delta: float) -> void:
	if _shift_clock == null or _staff_parking == null:
		return
	var el : float = _shift_clock.shift_elapsed_seconds
	# Only the drive-in window matters per-frame; once we cross 0 every car is
	# parked in its bay and there's nothing to animate. Saves the loop cost in
	# the common case (mid/post-shift).
	if el >= 0.0:
		return
	_position_cars_for_elapsed(el)

func setup(world: Node, shift_clock: Node, staff_parking: Node, player_spawn_pos: Vector3) -> void:
	_world = world
	_shift_clock = shift_clock
	_staff_parking = staff_parking
	_player_spawn_pos = player_spawn_pos
	_start_or_resume_shift()

func _start_or_resume_shift() -> void:
	if not _shift_clock: return
	var game_state = _world.game_state if "game_state" in _world else null
	if game_state and game_state.has_shift_data():
		_shift_clock.load_shift_state()
		_shift_clock.resume_shift()
	else:
		_shift_clock.start_pre_shift(PRE_SHIFT_WINDOW_S)

	if _shift_clock.has_method("apply_starting_settings"):
		_shift_clock.apply_starting_settings()
	if _shift_clock.has_signal("time_jumped") and not _shift_clock.time_jumped.is_connected(_on_time_jumped):
		_shift_clock.time_jumped.connect(_on_time_jumped)

	_on_time_jumped(_shift_clock.shift_elapsed_seconds)

func _on_time_jumped(new_elapsed: float) -> void:
	if new_elapsed < 0.0:
		var pss := _world.get_node_or_null("PreShiftSequence")
		if pss == null:
			# #198 — Find the PreShiftSpawner child and re-fire its setup() with
			# force=true so it installs the PreShiftSequence node. Previously this
			# looked for "PreShiftSequenceSpawner" (a name that never existed)
			# and called a phantom "spawn_pre_shift_sequence" method, so the
			# pre-shift arrival loop never ran for resumed-in-pre-shift saves
			# and the operator never saw colleagues driving in.
			var spawner : Node = _world.get_node_or_null("PreShiftSpawner")
			if spawner == null:
				spawner = _world.find_child("PreShiftSpawner", false, false)
			if spawner and spawner.has_method("setup"):
				var npcs_d : Dictionary = _world.npcs if "npcs" in _world else {}
				spawner.call("setup", _world, npcs_d, _shift_clock, _staff_parking,
					_player_spawn_pos, true)
			pss = _world.get_node_or_null("PreShiftSequence")
			if pss != null and pss.has_method("recompute_for"):
				pss.call("recompute_for", new_elapsed)
		else:
			if pss.has_method("recompute_for"):
				pss.call("recompute_for", new_elapsed)
	else:
		var pss2 := _world.get_node_or_null("PreShiftSequence")
		if pss2 != null and pss2.has_method("_on_bell"):
			pss2.call("_on_bell")
	_position_cars_for_elapsed(new_elapsed)

func _position_cars_for_elapsed(elapsed: float) -> void:
	if _staff_parking == null: return
	var anchor : Vector3 = _player_spawn_pos
	var ground_y : float = anchor.y
	var poly : Array[Vector3] = [
		Vector3(anchor.x - 25.0, ground_y - 1.0 + 0.3, anchor.z + 30.0),
		Vector3(anchor.x - 42.0, ground_y - 1.0 + 0.3, anchor.z + 20.0),
		Vector3(anchor.x - 42.0, ground_y - 1.0 + 0.3, anchor.z + 0.0),
		Vector3(anchor.x - 42.0, ground_y - 1.0 + 0.3, anchor.z - 40.0),
	]
	var npc_data : Dictionary = _world.NPC_DATA
	var car_slots : Dictionary = _world._CAR_SLOTS
	var schedule : Dictionary = _world.PRE_SHIFT_SCHEDULE
	for npc_id in npc_data.keys():
		var data : Dictionary = npc_data[npc_id]
		var car_path : String = String(data.get("car", ""))
		if car_path == "" or car_path == "passenger:player": continue
		if not car_slots.has(npc_id): continue
		var sched : Dictionary = schedule.get(npc_id, {})
		var arrives_at : float = float(sched.get("arrives_at_s", -1.0e9))
		var car : Node3D = _find_car_for(npc_id, data)
		if car == null: continue
		if elapsed >= arrives_at:
			# Already arrived — parked in the bay.
			car.visible = true
			var slot : Dictionary = car_slots[npc_id]
			car.transform = _staff_parking.bay_world_transform(int(slot["side"]), int(slot["idx"]))
		else:
			var t_remaining : float = arrives_at - elapsed   # always positive here
			if t_remaining > DRIVE_IN_WINDOW_S:
				# Too far out — hide the car so it doesn't sit floating at the
				# polyline endpoint thousands of metres away from where the schedule
				# says it should be. It pops back in when t_remaining crosses below
				# DRIVE_IN_WINDOW_S below.
				car.visible = false
				continue
			# In the drive-in window. Map t_remaining ∈ [0, DRIVE_IN_WINDOW_S] to
			# a position along the polyline from the bay entry (d=0, at arrival)
			# to the far end (d=length, at start of window). At intermediate t
			# the car is moving inward at constant speed = length / window.
			car.visible = true
			var d : float = t_remaining * NPC_DRIVE_SPEED_MPS
			var pos_on_road : Vector3 = _point_along_polyline(poly, d)
			car.global_position = pos_on_road
			var face_to : Vector3 = _heading_toward_entry(poly, d)
			if face_to.length() > 0.001: car.look_at(car.global_position + face_to, Vector3.UP)

func _point_along_polyline(poly: Array[Vector3], dist: float) -> Vector3:
	if poly.size() < 2: return poly[0] if poly.size() == 1 else Vector3.ZERO
	var remaining : float = maxf(0.0, dist)
	for i in poly.size() - 1:
		var a : Vector3 = poly[i]
		var b : Vector3 = poly[i + 1]
		var seg : float = a.distance_to(b)
		if remaining <= seg: return a.lerp(b, remaining / maxf(seg, 0.0001))
		remaining -= seg
	return poly[poly.size() - 1]

func _heading_toward_entry(poly: Array[Vector3], dist: float) -> Vector3:
	if poly.size() < 2: return Vector3.ZERO
	var remaining : float = maxf(0.0, dist)
	for i in poly.size() - 1:
		var a : Vector3 = poly[i]
		var b : Vector3 = poly[i + 1]
		var seg : float = a.distance_to(b)
		if remaining <= seg:
			var dir : Vector3 = (a - b); dir.y = 0.0
			return dir.normalized() if dir.length() > 0.001 else Vector3.ZERO
		remaining -= seg
	var dir2 : Vector3 = poly[poly.size() - 2] - poly[poly.size() - 1]; dir2.y = 0.0
	return dir2.normalized() if dir2.length() > 0.001 else Vector3.ZERO

func _find_car_for(_npc_id: String, data: Dictionary) -> Node3D:
	var wanted : String = "%s's car" % String(data.get("name", ""))
	for child in _world.get_children():
		if child is Node3D and child.has_meta("display_label"):
			if String(child.get_meta("display_label")) == wanted: return child as Node3D
	return null
