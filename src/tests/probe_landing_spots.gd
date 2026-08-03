extends Node
# =============================================================================
# PROBE — what geometry exists at the two spots where the operator's five
# build-placed bale clamps ended up in the 2026-07-20 session?
#   trio : scene (  0.0, y, 0.0) +/- 1.2
#   duo  : scene (331.9, y, 0.0) +/- 0.3
# Down-rays from y=+60 to y=-60 at each spot + the aim point for reference.
#   GODOT --headless --path . res://src/tests/probe_landing_spots.tscn
# =============================================================================

const SPOTS := {
	"trio_origin":  Vector3(0.0, 0.0, 0.0),
	"duo_332":      Vector3(331.93, 0.0, -0.1),
	"aim_marker":   Vector3(-197.823, 0.0, 90.448),
	"halfway":      Vector3(66.0, 0.0, 45.0),
}

func _ready() -> void:
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", "__clamprepro__")
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(80):
		await get_tree().process_frame
	await get_tree().physics_frame
	await get_tree().physics_frame

	var space : PhysicsDirectSpaceState3D = (world as Node3D).get_world_3d().direct_space_state
	print("\n=== LANDING-SPOT PROBES (t=0) ===")
	_probe_all(space)
	# First probe found MerloP40 grapple COLLIDERS at the scene origin two
	# physics frames after boot (AnimatableBody3D + sync_to_physics under
	# Rapier). Re-probe after 10 s of settling: does the phantom persist, or
	# was it a first-sync transient?
	print("\n[SETTLE] running 600 physics frames (10 s)...")
	for i in range(600):
		await get_tree().physics_frame
	print("\n=== LANDING-SPOT PROBES (t=10s) ===")
	_probe_all(space)
	world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

func _probe_all(space: PhysicsDirectSpaceState3D) -> void:
	for key in SPOTS:
		var p : Vector3 = SPOTS[key]
		# All hits top-down: repeat with exclusions to walk through overlapping bodies.
		var excl : Array = []
		var found := 0
		print("[%s] at XZ (%.1f, %.1f):" % [key, p.x, p.z])
		while found < 6:
			var q := PhysicsRayQueryParameters3D.create(
				Vector3(p.x, 60.0, p.z), Vector3(p.x, -60.0, p.z))
			q.exclude = excl
			q.collide_with_areas = false
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				if found == 0:
					print("    (nothing hit between y=+60 and y=-60)")
				break
			var col : Node = hit["collider"]
			var hp : Vector3 = hit["position"]
			print("    y=%+7.2f  %s  (path=%s)" % [hp.y, col.name, col.get_path()])
			excl.append(hit["rid"])
			found += 1
