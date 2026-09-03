extends Node3D
## MEASUREMENT PROBE — does the NPC pilot actually converge, or does
## test_jam_baseline's progress metric abort a legitimate detour?
##
## test_jam_baseline calls a leg 'stalled' after NO_PROGRESS_FRAMES (2400 = 40 s)
## without improving the STRAIGHT-LINE XZ distance to the goal by 0.5 m
## (test_jam_baseline.gd:387-394). jam3's goal sits 17.5 m from its start, but
## the plant's only doorway is the 3A/3B gate ~60 m in the opposite direction, so
## the straight-line distance is GUARANTEED to grow for the whole outbound run.
## That abort therefore fires regardless of how well the pilot drives.
##
## This probe drives the same leg through the same npc_set_target entry point
## with a much larger budget and measures PROGRESS ALONG THE ROUTE (waypoint
## index) instead of straight-line distance, so "the pilot cannot converge" and
## "the test measures the wrong thing" can be told apart.
##
## Prints only. No assert(). Restores every user:// file it touches.

const TOUCHED := [
	"user://world_layout.json", "user://world_layout_consumed.flag",
	"user://__pilotprobe___save.json", "user://__pilotprobe___factory.json",
]
const BOOT_FRAMES  := 240
const DRIVE_FRAMES := 36000        # 600 s at 60 Hz — 5x the suite's budget
const LOG_EVERY    := 120          # every 2 s
const ARRIVE_TOL   := 2.2

var _backups : Dictionary = {}

func _ready() -> void:
	print("=== PILOT CONVERGENCE PROBE ===")
	_backup_files()
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", "__pilotprobe__")
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var anchor : Vector3 = Plant.origin() if Plant.has_method("origin") else Vector3(-202.655532836914, -9.0, 94.0448760986328)
	# Which leg: default jam3 (indoor skip -> outdoor skip), or "jam1" for the
	# yard -> plant run. Same start/goal arithmetic as test_jam_baseline.
	var leg_name := "jam3"
	var uargs := OS.get_cmdline_user_args()
	if uargs.size() > 0:
		leg_name = String(uargs[0])
	var start : Vector3 = anchor + Vector3(12.0, 0.0, 28.0)     # SKIP_INDOOR_OFFSET
	var goal  : Vector3 = anchor + Vector3(12.0, 0.0, 45.5)     # SKIP_OUTDOOR_OFFSET
	if leg_name == "jam1b":
		# The anchor IS the player spawn, and the player stands on it in every
		# headless boot, so the ordered goal is occupied. Park 4 m short of it
		# along the approach bearing instead.
		var jam1_pos_b := Vector3(-79.90, -7.93, 157.13)
		var to_plant_b : Vector3 = anchor - jam1_pos_b
		to_plant_b.y = 0.0
		to_plant_b = to_plant_b.normalized()
		start = jam1_pos_b - to_plant_b * 22.0
		goal = anchor - to_plant_b * 4.0
	if leg_name == "jam1":
		var jam1_pos := Vector3(-79.90, -7.93, 157.13)
		var to_plant : Vector3 = anchor - jam1_pos
		to_plant.y = 0.0
		to_plant = to_plant.normalized()
		start = jam1_pos - to_plant * 22.0
		goal = anchor
	print("  LEG: %s" % leg_name)
	print("  anchor=%s" % str(anchor.round()))
	print("  start =%s  goal=%s  straight-line %.2f m" % [
		str(start.round()), str(goal.round()),
		Vector2(start.x - goal.x, start.z - goal.z).length()])

	var fl : Node3D = null
	for v in get_tree().get_nodes_in_group("vehicle"):
		var n := v as Node3D
		if n != null and String(n.name).to_lower().contains("forklift"):
			fl = n
			break
	if fl == null:
		print("  FATAL: no forklift in group 'vehicle'"); _finish(world); return

	fl.global_position = Vector3(start.x, start.y + 1.2, start.z)
	fl.rotation = Vector3.ZERO
	for _j in range(20):
		await get_tree().physics_frame
	print("  forklift '%s' placed at %s" % [String(fl.name), str(fl.global_position.round())])

	# Is the ORDERED GOAL even free for a vehicle-sized hull? VehicleRouteGrid
	# snaps its endpoints with _nearest_free but then appends the ordered goal
	# verbatim as the final waypoint, so a goal inside a machine produces a
	# route whose last point can never be reached.
	var space := get_world_3d().direct_space_state
	var hull := BoxShape3D.new()
	hull.size = Vector3(2.4, 2.2, 4.0)
	var hq := PhysicsShapeQueryParameters3D.new()
	hq.shape = hull
	hq.collide_with_areas = false
	hq.exclude = [fl.get_rid()] if fl is CollisionObject3D else []
	for probe_name_v in [["goal", goal], ["goal+2.2m tol ring", goal]]:
		pass
	hq.transform = Transform3D(Basis(), Vector3(goal.x, start.y + 1.2, goal.z))
	var gres : Array = space.intersect_shape(hq, 8)
	var gnames : Array = []
	for r in gres:
		var nn := r.get("collider") as Node
		if nn != null:
			gnames.append(String(nn.name))
	print("  GOAL CLEARANCE: a 2.4 x 2.2 x 4.0 m hull at the ordered goal is %s%s" % [
		"CLEAR" if gnames.is_empty() else "BLOCKED by ",
		"" if gnames.is_empty() else str(gnames)])
	# How far from the goal do you have to stand to be clear?
	var need : float = -1.0
	for step_v in [0.0, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 8.0]:
		var step : float = float(step_v)
		var dirv : Vector3 = (start - goal)
		dirv.y = 0.0
		if dirv.length_squared() < 0.01:
			dirv = Vector3.FORWARD
		dirv = dirv.normalized()
		hq.transform = Transform3D(Basis(), Vector3(goal.x, start.y + 1.2, goal.z) + dirv * step)
		if space.intersect_shape(hq, 4).is_empty():
			need = step
			break
	print("  GOAL CLEARANCE: nearest clear hull pose along the approach bearing is %.1f m from the goal (npc_arrived tolerance is 2.2 m)" % need)

	fl.call("npc_set_target", goal)
	var pts : int = int(fl.call("npc_route_points")) if fl.has_method("npc_route_points") else -1
	print("  route points = %d" % pts)
	var route = fl.get("_npc_route")
	if route is PackedVector3Array:
		for k in (route as PackedVector3Array).size():
			var wp : Vector3 = (route as PackedVector3Array)[k]
			print("    wp %2d %s  (%.1f m from goal)" % [
				k, str(wp.round()), Vector2(wp.x - goal.x, wp.z - goal.z).length()])

	# ── drive, logging route progress rather than straight-line distance ──
	var outcome := "budget_exhausted"
	var best_line : float = INF
	var best_idx  : int = -1
	var idx_stall : int = 0
	var path_len  : float = 0.0
	var prev : Vector3 = fl.global_position
	for f in range(DRIVE_FRAMES):
		await get_tree().physics_frame
		if not is_instance_valid(fl):
			outcome = "vehicle_gone"; break
		path_len += Vector2(fl.global_position.x - prev.x, fl.global_position.z - prev.z).length()
		prev = fl.global_position
		if bool(fl.call("npc_arrived")):
			outcome = "arrived"; break
		var i : int = int(fl.get("_npc_route_i"))
		var d_line : float = Vector2(fl.global_position.x - goal.x, fl.global_position.z - goal.z).length()
		best_line = minf(best_line, d_line)
		if i > best_idx:
			best_idx = i
			idx_stall = 0
		else:
			idx_stall += 1
		# The honest non-convergence test: the ROUTE INDEX stops advancing for
		# 120 s. A vehicle threading a 120 m detour still ticks waypoints off.
		if idx_stall > 7200:
			outcome = "route_index_stalled"; break
		if f % LOG_EVERY == 0:
			var pil = fl.get("_pilot")
			var mode : int = int(pil.get("_mode")) if pil != null else -1
			var mname : String = ["RUN", "EVADE", "REVERSE"][mode] if mode >= 0 and mode < 3 else "?"
			var tgt : Vector3 = fl.get("_npc_target")
			print("  t=%6.1fs pos=%s wp=%d/%d d_wp=%6.2f d_goal=%7.2f spd=%5.2f pilot=%-7s evades=%d revs=%d covered=%.0f m" % [
				float(f) / 60.0, str(fl.global_position.round()), i, pts,
				Vector2(fl.global_position.x - tgt.x, fl.global_position.z - tgt.z).length(),
				d_line, float(fl.get("_current_speed_mps")), mname,
				int(pil.get("evade_count")) if pil != null else -1,
				int(pil.get("recovery_reverse_count")) if pil != null else -1,
				path_len])

	print("  ── VERDICT ──")
	print("  outcome            : %s" % outcome)
	print("  final pos          : %s" % str(fl.global_position.round()) if is_instance_valid(fl) else "gone")
	print("  waypoints reached  : %d of %d" % [best_idx, pts])
	print("  best straight-line : %.2f m from goal (started %.2f m)" % [
		best_line, Vector2(start.x - goal.x, start.z - goal.z).length()])
	print("  path travelled     : %.1f m" % path_len)
	if is_instance_valid(fl):
		var pil2 = fl.get("_pilot")
		if pil2 != null:
			print("  pilot totals       : evades=%d recovery_reverses=%d wedge=%.1f s" % [
				int(pil2.get("evade_count")), int(pil2.get("recovery_reverse_count")),
				float(pil2.get("wedge_seconds_total"))])
	_finish(world)

func _finish(world: Node) -> void:
	if world != null:
		world.queue_free()
		await get_tree().process_frame
	_restore_files()
	get_tree().quit(0)

func _backup_files() -> void:
	for p in TOUCHED:
		if FileAccess.file_exists(p):
			var f := FileAccess.open(p, FileAccess.READ)
			_backups[p] = f.get_as_text() if f else null
			if f: f.close()
		else:
			_backups[p] = null

func _restore_files() -> void:
	for p in _backups.keys():
		var orig = _backups[p]
		if orig is String:
			var f := FileAccess.open(p, FileAccess.WRITE)
			if f: f.store_string(orig); f.close()
		elif FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	print("  (restored touched user:// files)")
