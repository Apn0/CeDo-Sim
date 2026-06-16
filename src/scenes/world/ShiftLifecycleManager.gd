extends Node3D

class_name ShiftLifecycleManager

# =============================================================================
# #195 follow-up — Shift start/resume + time-jump car repositioning extracted
# from MainWorld.gd.
# =============================================================================
# Owns the bell-driven shift bring-up (fresh game → pre-shift; saved game →
# resume), and the time_jumped handler that backsolves every NPC car's
# position on De Asselen Kuil so the world matches the operator's chosen
# clock instant. MainWorld instantiates one of these as a child node and
# calls setup(world, shift_clock, staff_parking, player_spawn_pos) once
# during world bring-up. The manager then defers to MainWorld for canonical
# helpers (NPC_DATA / PRE_SHIFT_SCHEDULE / _CAR_SLOTS / _spawn_pre_shift_sequence).
#
# Spawned children (PreShiftSequence) still go under MainWorld via the world
# reference, preserving the original scene shape.

# ── #166 Pre-shift arrival window ──────────────────────────────────────────
# A fresh game starts PRE_SHIFT_WINDOW_S game-seconds before the bell so the
# arrival sequence has room to play out. ShiftClock seeds to -1800 and ticks
# up to 0; the bell fires shift_started again at that moment.
const PRE_SHIFT_WINDOW_S : float = 30.0 * 60.0   # 30 minutes

## Average car-driving speed on De Asselen Kuil for the NPC drive-in. ~28 km/h
## (residential road). Used by _position_cars_for_elapsed to backsolve a
## starting position on the road polyline so a car arrives at its bay exactly
## at arrives_at_s. Phase B minimal-first: cars are TELEPORTED to that position
## but not yet driven forward — a future Phase C can animate them along the
## polyline. The teleport alone already cures the "car appears in bay before
## the operator's set time" complaint.
const NPC_DRIVE_SPEED_MPS : float = 8.0

# Reference back to MainWorld for NPC_DATA / PRE_SHIFT_SCHEDULE / _CAR_SLOTS /
# game_state / _spawn_pre_shift_sequence. Set by setup().
var _world : Node = null
var _shift_clock : Node = null
var _staff_parking : Node = null
var _player_spawn_pos : Vector3 = Vector3.ZERO

func _ready() -> void:
	if _world == null:
		_world = get_parent()

## Wire the manager to MainWorld + its dependencies. Must be called once
## immediately after add_child(); _start_or_resume_shift() then drives the bell.
func setup(world: Node, shift_clock: Node, staff_parking: Node, player_spawn_pos: Vector3) -> void:
	_world = world
	_shift_clock = shift_clock
	_staff_parking = staff_parking
	_player_spawn_pos = player_spawn_pos
	_start_or_resume_shift()

# =============================================================================
# SHIFT START / RESUME
# =============================================================================
func _start_or_resume_shift() -> void:
	## MainWorld is the single authority for starting or resuming the shift.
	## ShiftClock._ready() deliberately does NOT self-load to avoid the sibling
	## ordering race (ShiftClock is child[0]; GameState is child[1]).
	if not _shift_clock:
		return
	var game_state = _world.game_state if "game_state" in _world else null
	if game_state and game_state.has_shift_data():
		_shift_clock.load_shift_state()
		_shift_clock.resume_shift()
		print("[ShiftLifecycleManager] Shift resumed at %s" % _shift_clock.get_time_string())
	else:
		# #166 — Fresh game starts 30 min BEFORE the bell so the pre-shift arrival
		# sequence (Emrah at T-35, Pascal smoking at T-33, …, Kevin at T-10) has
		# room to play out. The bell still emits shift_started at T=0.
		_shift_clock.start_pre_shift(PRE_SHIFT_WINDOW_S)
		print("[ShiftLifecycleManager] Pre-shift started (%.0f min until bell)" % (PRE_SHIFT_WINDOW_S / 60.0))
	# Apply the operator's "Starting time / Starting date" settings (gameplay
	# tab). Empty strings = no-op (use the just-loaded shift state as-is). The
	# call may seek the clock backwards into pre-shift OR forwards past the
	# bell; either way it emits time_jumped which MainWorld handles below.
	if _shift_clock.has_method("apply_starting_settings"):
		_shift_clock.apply_starting_settings()
	# Wire the recomputer so future Apply clicks in the Settings menu (or a
	# live debug seek) reposition NPCs + cars without a save/reload round-trip.
	if _shift_clock.has_signal("time_jumped") \
			and not _shift_clock.time_jumped.is_connected(_on_time_jumped):
		_shift_clock.time_jumped.connect(_on_time_jumped)
	# Pre-position cars + NPC pre-shift state to the now-canonical elapsed.
	# This handles both the "operator picked a time" path and the "fresh game
	# with no time override" path (elapsed == -PRE_SHIFT_WINDOW_S) uniformly.
	_on_time_jumped(_shift_clock.shift_elapsed_seconds)

## ShiftClock.time_jumped handler. Re-evaluate every NPC + their car at the
## new elapsed value. If the new instant is BEFORE a given NPC's arrival, the
## NPC is hidden + their car is repositioned along De Asselen Kuil at the
## distance corresponding to (arrives_at_s - elapsed) * NPC_DRIVE_SPEED_MPS
## back from the parking-lot entry. If the new instant is AT-OR-AFTER, the
## car teleports into its parking bay and the NPC's pre-shift state recomputes.
func _on_time_jumped(new_elapsed: float) -> void:
	# Ensure a PreShiftSequence exists if the new time is in pre-shift; if we
	# landed past the bell, force any existing sequence to hand off.
	if new_elapsed < 0.0:
		var pss := _world.get_node_or_null("PreShiftSequence")
		if pss == null:
			# Force-spawn the sequence: we KNOW the new time is pre-shift
			# (new_elapsed < 0), the is_pre_shift gate inside the spawn
			# helper is a tautology in this path but the implicit coupling
			# has bitten us — a resumed-past-bell save that the operator
			# rewinds to 06:35 needs a brand-new PSS regardless.
			_world._spawn_pre_shift_sequence(true)
			pss = _world.get_node_or_null("PreShiftSequence")
			# setup() seeds every scheduled NPC at the arrival_anchor with
			# off_duty=true but does NOT route them to dressing / canteen /
			# smoke until a _physics_process tick crosses each arrives_at_s.
			# After a rewind to e.g. -1500s (06:35 on a Vroege day) most
			# NPCs are already past their arrives_at_s and should be IN the
			# canteen, not parked at the arrival anchor. recompute_for() is
			# the deterministic placer; call it immediately so the world
			# matches the new instant without waiting for a physics tick.
			if pss != null and pss.has_method("recompute_for"):
				pss.call("recompute_for", new_elapsed)
		else:
			if pss.has_method("recompute_for"):
				pss.call("recompute_for", new_elapsed)
	else:
		var pss2 := _world.get_node_or_null("PreShiftSequence")
		if pss2 != null and pss2.has_method("_on_bell"):
			pss2.call("_on_bell")
	# Reposition cars along the road / into bays per NPC arrival time vs new
	# elapsed value. Safe to call mid-shift (everyone has already arrived).
	_position_cars_for_elapsed(new_elapsed)

## Reposition every NPC car according to whether their arrives_at_s has passed.
## - elapsed >= arrives_at_s → car parked in its bay (default state).
## - elapsed < arrives_at_s  → car positioned on De Asselen Kuil at distance
##   (arrives_at_s - elapsed) * NPC_DRIVE_SPEED_MPS back from the parking entry.
##
## The road waypoints are anchor + (-42,_,-40) → (-42,_,0) → (-42,_,20) →
## (-25,_,30) → (0,_,30) (lines 2174-2180). The parking entry is roughly the
## (-25,_,30) waypoint; we walk the polyline backwards from there.
func _position_cars_for_elapsed(elapsed: float) -> void:
	if _staff_parking == null:
		return
	var anchor : Vector3 = _player_spawn_pos
	var ground_y : float = anchor.y
	# Road polyline IN ORDER FROM PARKING ENTRY BACK TO SOUTH END — so the
	# "distance d along here" walk gives us how far back along the road the
	# car still has to travel before its arrives_at_s.
	var poly : Array[Vector3] = [
		Vector3(anchor.x - 25.0, ground_y - 1.0 + 0.3, anchor.z + 30.0),  # parking entry
		Vector3(anchor.x - 42.0, ground_y - 1.0 + 0.3, anchor.z + 20.0),
		Vector3(anchor.x - 42.0, ground_y - 1.0 + 0.3, anchor.z + 0.0),
		Vector3(anchor.x - 42.0, ground_y - 1.0 + 0.3, anchor.z - 40.0),  # south end
	]
	var npc_data : Dictionary = _world.NPC_DATA
	var car_slots : Dictionary = _world._CAR_SLOTS
	var schedule : Dictionary = _world.PRE_SHIFT_SCHEDULE
	for npc_id in npc_data.keys():
		var data : Dictionary = npc_data[npc_id]
		var car_path : String = String(data.get("car", ""))
		if car_path == "" or car_path == "passenger:player":
			continue
		if not car_slots.has(npc_id):
			continue
		var sched : Dictionary = schedule.get(npc_id, {})
		var arrives_at : float = float(sched.get("arrives_at_s", -1.0e9))
		var car : Node3D = _find_car_for(npc_id, data)
		if car == null:
			continue
		if elapsed >= arrives_at:
			# Past arrival → park in bay (canonical state).
			var slot : Dictionary = car_slots[npc_id]
			car.transform = _staff_parking.bay_world_transform(
				int(slot["side"]), int(slot["idx"]))
		else:
			# Still en-route → place on the road polyline at distance back
			# from the parking entry. The car points forward (toward the entry).
			var d : float = (arrives_at - elapsed) * NPC_DRIVE_SPEED_MPS
			var pos_on_road : Vector3 = _point_along_polyline(poly, d)
			car.global_position = pos_on_road
			var face_to : Vector3 = _heading_toward_entry(poly, d)
			if face_to.length() > 0.001:
				car.look_at(car.global_position + face_to, Vector3.UP)

## Walk a polyline from index 0 forward by `dist` metres, returning the world
## position. If `dist` exceeds the polyline length, returns the last point.
func _point_along_polyline(poly: Array[Vector3], dist: float) -> Vector3:
	if poly.size() < 2:
		return poly[0] if poly.size() == 1 else Vector3.ZERO
	var remaining : float = maxf(0.0, dist)
	for i in poly.size() - 1:
		var a : Vector3 = poly[i]
		var b : Vector3 = poly[i + 1]
		var seg : float = a.distance_to(b)
		if remaining <= seg:
			var t : float = remaining / maxf(seg, 0.0001)
			return a.lerp(b, t)
		remaining -= seg
	return poly[poly.size() - 1]

## Heading vector pointing from the car's road position TOWARD the parking
## entry (poly[0]). Walks the polyline by `dist`, finds the segment, returns
## the vector from THAT point back to the segment's start (toward poly[0]).
func _heading_toward_entry(poly: Array[Vector3], dist: float) -> Vector3:
	if poly.size() < 2:
		return Vector3.ZERO
	var remaining : float = maxf(0.0, dist)
	for i in poly.size() - 1:
		var a : Vector3 = poly[i]
		var b : Vector3 = poly[i + 1]
		var seg : float = a.distance_to(b)
		if remaining <= seg:
			var dir : Vector3 = (a - b)
			dir.y = 0.0
			return dir.normalized() if dir.length() > 0.001 else Vector3.ZERO
		remaining -= seg
	var dir2 : Vector3 = poly[poly.size() - 2] - poly[poly.size() - 1]
	dir2.y = 0.0
	return dir2.normalized() if dir2.length() > 0.001 else Vector3.ZERO

## Locate the spawned car node for an NPC. Cars are tagged with
## set_meta("display_label", "<name>'s car") at spawn (line 2514), so we scan
## MainWorld's children for that tag. Returns null if absent (car not spawned).
func _find_car_for(_npc_id: String, data: Dictionary) -> Node3D:
	var wanted : String = "%s's car" % String(data.get("name", ""))
	for child in _world.get_children():
		if child is Node3D and child.has_meta("display_label"):
			if String(child.get_meta("display_label")) == wanted:
				return child as Node3D
	return null
