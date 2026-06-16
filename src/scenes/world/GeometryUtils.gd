extends Object

class_name GeometryUtils

# Pure utility math extracted from MainWorld.gd. All functions are static and
# take no MainWorld state — they operate on the Node3D arguments alone.
# Call from MainWorld via GeometryUtils.local_aabb(node) /
# GeometryUtils.fit_box_collider(body).

## Combined AABB of all of `node`'s mesh descendants, expressed in `node`'s OWN
## local space (accounts for nested child transforms). Used to seat a machine's
## bottom on the floor regardless of where its origin sits in the geometry.
static func local_aabb(node: Node3D) -> AABB:
	var bb := AABB()
	var started := false
	var inv := node.global_transform.affine_inverse()
	for c in node.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var a : AABB = mi.get_aabb()
		var xf : Transform3D = inv * mi.global_transform
		for ix in [0.0, 1.0]:
			for iy in [0.0, 1.0]:
				for iz in [0.0, 1.0]:
					var corner : Vector3 = a.position + Vector3(a.size.x * ix, a.size.y * iy, a.size.z * iz)
					var p : Vector3 = xf * corner
					if not started:
						bb = AABB(p, Vector3.ZERO); started = true
					else:
						bb = bb.expand(p)
	return bb

## #10 collision audit — give a procedurally-modelled body a SOLID collider sized
## to its visible meshes, so the player & vehicles can't walk through it. The body
## is already a StaticBody3D (BatteryStation / ServiceStation); it only ever had an
## Area3D proximity trigger, so we add the missing solid shape here.
static func fit_box_collider(body: Node3D) -> void:
	if body == null or body.has_node("SolidCollision"):
		return
	var bb := local_aabb(body)
	if bb.size.x < 0.02 or bb.size.y < 0.02 or bb.size.z < 0.02:
		return
	var cs := CollisionShape3D.new()
	cs.name = "SolidCollision"
	var box := BoxShape3D.new()
	box.size = bb.size
	cs.shape = box
	cs.position = bb.position + bb.size * 0.5
	body.add_child(cs)
