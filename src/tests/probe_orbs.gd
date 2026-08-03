extends Node3D
## Precise per-orb geometry probe (#orb-inspect). Boots MainWorld, then reproduces
## each F10 marker ray (camera → orb) against the REAL physics world and reports
## the exact surface: collider, hit normal, surface class (wall/roof/floor + which
## way it faces), height above the operating floor, and inside/outside the
## building footprint. This is the "you have the coords + geometry + scripts, so
## tell me exactly what's there" answer.
##
##   godot --headless --main-scene res://src/tests/probe_orbs.tscn

const TEST_SLOT := "new_building_test"
const CAM := Vector3(-250.522, -7.344, 117.806)   # capture 20260708_040329 camera
const ORBS := [
	[1, Vector3(-211.88, -6.53, 156.44)],
	[2, Vector3(-246.45, -6.43, 156.31)],
	[3, Vector3(-256.81, -1.90, 114.84)],
	[4, Vector3(-260.53, -4.07, 119.28)],
	[5, Vector3(-253.09, -3.97, 110.16)],
	[6, Vector3(-259.44, -4.22, 113.56)],
]
# building-frame affine (same as the regression harness) for inside/outside + wall side
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)
const BF_RECTS := [
	[0.0, 120.0, 0.0, 61.0], [120.0, 150.7, 0.0, 31.5], [120.0, 131.5, 31.5, 61.0],
	[57.0, 81.0, 61.0, 66.0], [81.0, 131.5, 61.0, 71.5],
]

func _pc_to_bf(pc: Vector2) -> Vector2:
	var d := pc - BF_O
	return Vector2(d.dot(BF_XU), d.dot(BF_ZU))
func _bf_inside(bf: Vector2, m: float) -> bool:
	for r in BF_RECTS:
		if bf.x >= r[0]-m and bf.x <= r[1]+m and bf.y >= r[2]-m and bf.y <= r[3]+m:
			return true
	return false

func _ready() -> void:
	print("=== PRECISE ORB PROBE ===")
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(70):
		await get_tree().process_frame

	var floor_y : float = Plant.floor_top_y() if Plant.is_initialized() else -9.0
	print("floor_top_y = %.2f   camera = %s" % [floor_y, str(CAM)])
	var space := get_world_3d().direct_space_state

	for entry in ORBS:
		var idx : int = entry[0]
		var orb : Vector3 = entry[1]
		var dir := (orb - CAM).normalized()
		var to := CAM + dir * (CAM.distance_to(orb) + 2.0)
		var q := PhysicsRayQueryParameters3D.create(CAM, to)
		q.collision_mask = 0xFFFFFFFF
		q.collide_with_areas = true
		q.collide_with_bodies = true
		var hit := space.intersect_ray(q)

		var bf := _pc_to_bf(Plant.scene_to_pc(orb)) if Plant.is_initialized() else Vector2.ZERO
		var inside := _bf_inside(bf, 0.6)
		print("\n[#%d] orb=(%.1f, %.1f, %.1f)  %.1f m above floor  bf=(%.1f, %.1f)  %s" % [
			idx, orb.x, orb.y, orb.z, orb.y - floor_y, bf.x, bf.y,
			"INSIDE footprint" if inside else "OUTSIDE footprint"])
		if hit.is_empty():
			print("     ray reached nothing (orb was on a now-collider-less object?)")
			continue
		var col : Node = hit["collider"]
		var nrm : Vector3 = hit["normal"]
		var hp : Vector3 = hit["position"]
		var cls := _classify(nrm)
		# how far the physics hit is from where the orb was recorded (big gap =
		# the orb sat on something that no longer has a collider here)
		var gap := hp.distance_to(orb)
		print("     ray HIT: %s" % _pathish(col))
		print("     surface: %s   normal=(%.2f, %.2f, %.2f)   hit %.2f m from orb" % [cls, nrm.x, nrm.y, nrm.z, gap])
		# nearest OTHER placeable within 6 m (what the operator may have meant)
		_report_nearby(orb, col)

func _classify(n: Vector3) -> String:
	if n.y > 0.7: return "FLOOR (up-facing)"
	if n.y < -0.7: return "ROOF/ceiling underside (down-facing)"
	# wall — describe facing in world XZ
	var deg := rad_to_deg(atan2(n.x, n.z))
	return "WALL (vertical, outward normal ~%.0f° in XZ)" % deg

func _pathish(n: Node) -> String:
	if n == null: return "null"
	return "%s   (%s)" % [n.name, String(n.get_path())]

func _report_nearby(orb: Vector3, _hit_col: Node) -> void:
	var best : Node3D = null
	var best_d := 6.0
	for n in get_tree().get_nodes_in_group("placed_object"):
		if not (n is Node3D): continue
		var d : float = (n as Node3D).global_position.distance_to(orb)
		if d < best_d:
			best_d = d; best = n
	if best != null:
		var pid : String = String(best.get_meta("placeable_id")) if best.has_meta("placeable_id") else String(best.name)
		print("     nearest placed_object: '%s' at %.1f m" % [pid, best_d])
