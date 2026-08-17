extends Node
# =============================================================================
# PROBE — does the operator's saved FOV reach the vehicle CAB cameras?
#
# SettingsManager saves graphics.fov (operator has 65.0). The old
# _set_fov_on_current_camera() only stamped whatever Camera3D was `current` at
# the instant apply() ran — at boot that is the player head camera. A cab
# camera is created later by BaseVehicle._ready() with `current = false`, so it
# kept Camera3D's built-in default fov = 75.0 forever.
#
# This boots a real MainWorld and prints, per vehicle, the cab camera's fov
# next to the saved setting. NOTHING IS WRITTEN TO DISK.
#
#   GODOT --headless --path . res://src/tests/probe_cabcam_fov.tscn
# =============================================================================

func _ready() -> void:
	print("=== PROBE — cab camera FOV vs saved setting ===")
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(120):
		await get_tree().process_frame

	var saved := 75.0
	if has_node("/root/SettingsManager"):
		saved = float(get_node("/root/SettingsManager").graphics().get("fov", 75.0))
	print("saved graphics.fov = %.1f" % saved)

	var cur := get_viewport().get_camera_3d()
	print("viewport current camera: %s fov=%.1f"
		% [(cur.name if cur else "<none>"), (cur.fov if cur else -1.0)])

	print("\n%-16s | %-26s | %-8s | %s" % ["vehicle_type", "cab camera node", "fov", "verdict"])
	print("-".repeat(16) + "-+-" + "-".repeat(26) + "-+-" + "-".repeat(8) + "-+-" + "-".repeat(12))
	var seen := {}
	var bad := 0
	var total := 0
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not (n is Node3D):
			continue
		var vt := String(n.get("vehicle_type"))
		if vt == "" or seen.has(vt):
			continue
		seen[vt] = true
		var p = n.get("cab_camera_path")
		if p == null or String(p) == "":
			continue
		var cam := (n as Node3D).get_node_or_null(NodePath(String(p))) as Camera3D
		if cam == null:
			print("%-16s | %-26s | %-8s | %s" % [vt, String(p), "n/a", "NO CAMERA"])
			continue
		total += 1
		var ok : bool = is_equal_approx(cam.fov, saved)
		if not ok:
			bad += 1
		print("%-16s | %-26s | %-8.1f | %s" % [vt, String(p), cam.fov, ("MATCHES saved" if ok else "STALE (want %.1f)" % saved)])

	print("\n%d/%d cab cameras carry the saved FOV; %d stale." % [total - bad, total, bad])
	get_tree().quit(0 if bad == 0 else 1)
