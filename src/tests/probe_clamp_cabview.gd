extends Node
# =============================================================================
# PROBE — what does the BaleClamp CabCamera actually LOOK AT?
#
# Companion to probe_clamp_throttle_dir.gd. That one proved W drives toward
# +local_Z (the mast side). This one answers the other half of the question:
# is +local_Z what the operator SEES, and what (if anything) blocks it.
#
# Method: instantiate BaleClamp.tscn, take the CabCamera's global transform,
# shoot the camera's own forward ray (-cam.basis.z) and intersect it against
# the world-space AABB of every MeshInstance3D on the vehicle. Anything the ray
# enters is directly on the operator's centre sightline.
#
#   GODOT --headless --path . res://src/tests/probe_clamp_cabview.tscn
# =============================================================================

func _ready() -> void:
	for path in ["res://src/scenes/vehicles/BaleClamp.tscn",
				 "res://src/scenes/vehicles/Forklift.tscn",
				 "res://src/scenes/vehicles/Merlo.tscn",
				 "res://src/scenes/vehicles/MerloP40.tscn"]:
		_probe(path)
	get_tree().quit(0)

func _probe(path: String) -> void:
	print("\n=== %s ===" % path.get_file())
	var scn := load(path) as PackedScene
	if scn == null:
		print("  FATAL: failed to load"); return
	var v : Node3D = scn.instantiate()
	# NOTE: do NOT add to the tree — _ready() would build lights/beeper and the
	# camera rig. We want the AUTHORED pose exactly as saved in the .tscn.
	var cam : Camera3D = _find_cam(v)
	if cam == null:
		print("  FATAL: no Camera3D found"); v.free(); return

	var cam_xf : Transform3D = _rel_xf(v, cam)
	var eye : Vector3 = cam_xf.origin
	var fwd : Vector3 = -cam_xf.basis.z
	print("  CabCamera local pos = (%+.2f, %+.2f, %+.2f)   look dir = (%+.2f, %+.2f, %+.2f)  [%s]"
		% [eye.x, eye.y, eye.z, fwd.x, fwd.y, fwd.z,
			("+Z side" if fwd.z > 0.5 else ("-Z side" if fwd.z < -0.5 else "sideways"))])

	var hits : Array = []
	_walk(v, v, eye, fwd, hits)
	hits.sort_custom(func(a, b): return float(a["t"]) < float(b["t"]))
	if hits.is_empty():
		print("  centre sightline: NOTHING on it (clear view)")
	else:
		print("  centre sightline hits (nearest first):")
		for h in hits:
			print("    %6.2f m  %-28s  aabb size=(%.2f, %.2f, %.2f) centre_z=%+.2f"
				% [float(h["t"]), String(h["name"]),
					(h["size"] as Vector3).x, (h["size"] as Vector3).y, (h["size"] as Vector3).z,
					(h["c"] as Vector3).z])
	v.free()

func _find_cam(root: Node) -> Camera3D:
	if root is Camera3D:
		return root as Camera3D
	for c in root.get_children():
		var r := _find_cam(c)
		if r != null:
			return r
	return null

## Transform of `n` expressed in `root`'s local space (works outside the tree).
func _rel_xf(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur : Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf

func _walk(root: Node3D, n: Node, eye: Vector3, fwd: Vector3, hits: Array) -> void:
	if n is MeshInstance3D:
		var mi := n as MeshInstance3D
		if mi.mesh != null and mi.visible:
			var xf := _rel_xf(root, mi)
			var aabb : AABB = xf * mi.mesh.get_aabb()
			var t := _ray_aabb(eye, fwd, aabb)
			if t >= 0.0:
				hits.append({"t": t, "name": String(mi.name), "size": aabb.size, "c": aabb.get_center()})
	for c in n.get_children():
		_walk(root, c, eye, fwd, hits)

## Slab test. Returns entry distance along `dir` (>=0), or -1 if no hit ahead.
func _ray_aabb(o: Vector3, d: Vector3, box: AABB) -> float:
	var tmin := -1e20
	var tmax :=  1e20
	var lo := box.position
	var hi := box.position + box.size
	for i in range(3):
		var oi : float = o[i]
		var di : float = d[i]
		if absf(di) < 1e-9:
			if oi < lo[i] or oi > hi[i]:
				return -1.0
			continue
		var t1 : float = (lo[i] - oi) / di
		var t2 : float = (hi[i] - oi) / di
		if t1 > t2:
			var tmp := t1; t1 = t2; t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
	if tmax < maxf(tmin, 0.0):
		return -1.0
	return maxf(tmin, 0.0)
