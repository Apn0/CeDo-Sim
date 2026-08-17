extends RefCounted
class_name BaleBurst
## #23 / operator 2026-07-16 — open a de-wired bale into physical pieces made of
## the bale's OWN sheet meshes.
##
## HARD REQUIREMENT (operator): cutting the wires must SPLIT the bale — it must
## NOT replace it with a different mesh, and the material must NOT disappear.
## Earlier this file fabricated 6 generic re-tinted slab pieces and queue_free'd
## the real bale (its 30-60 Sheet_i meshes + patches). That is the forbidden
## mesh-swap. Now we REPARENT the bale's actual Sheet meshes into a small number
## of rigid-body chunks: same meshes, same materials, mass conserved, nothing
## vanishes. The bound bale becomes a loose, layered pile of its own film.

const CHUNKS          : int   = 6     # physical pieces the strip splits into
const MAX_PIECES_LIVE : int   = 72    # scene-wide safety cap (~12 bales' worth)

## Split `bale` into CHUNKS rigid pieces built from its real Sheet meshes, at the
## same world pose. Frees only the emptied bale husk. Returns the piece bodies.
static func open(bale: Node3D, scene: Node) -> Array:
	if bale == null or not is_instance_valid(bale) or scene == null:
		return []
	var sheets_root := bale.find_child("Sheets", true, false)
	# Fallback: a bale with no discoverable Sheets node can't be split from real
	# meshes — leave it intact rather than fabricate/replace it (honour the rule).
	if sheets_root == null or sheets_root.get_child_count() == 0:
		push_warning("[BaleBurst] no Sheets node on %s — leaving bale intact" % bale.name)
		return []

	var xf := bale.global_transform
	var size := _bale_size(bale)
	_cap_existing(scene)

	# Mass conservation: pieces together must weigh what the intact bale weighed.
	var src_mass : float = 0.0
	var src_rb := bale as RigidBody3D
	if src_rb != null:
		src_mass = src_rb.mass
	if src_mass < 1.0:
		src_mass = size.x * size.y * size.z * BaleDefs.BULK_DENSITY

	# Bin every real sheet/patch mesh by its position along the bale length (local
	# X) into CHUNKS contiguous groups. We carry the ACTUAL MeshInstances over —
	# no new geometry is fabricated.
	var half_x : float = size.x * 0.5
	var bins : Array = []
	for _c in CHUNKS:
		bins.append([])
	var meshes : Array[MeshInstance3D] = []
	_gather_meshes(sheets_root, meshes)
	for mi in meshes:
		var lx : float = bale.to_local(mi.global_position).x
		var frac : float = clampf((lx + half_x) / maxf(size.x, 0.001), 0.0, 0.999)
		var bi : int = clampi(int(frac * float(CHUNKS)), 0, CHUNKS - 1)
		bins[bi].append(mi)

	# Count the chunks that actually got sheets — EMPTY bins are skipped below, so
	# the bale mass has to be split across the SURVIVING chunks only. Dividing by
	# CHUNKS here would silently lose each empty chunk's share (src_mass/CHUNKS per
	# empty bin → mass destroyed; conservation bughunt 2026-07-17).
	var live_chunks : int = 0
	for i in CHUNKS:
		if not (bins[i] as Array).is_empty():
			live_chunks += 1
	if live_chunks == 0:
		return []
	var out : Array = []
	var prev : RigidBody3D = null
	var seg_len : float = size.x / float(CHUNKS)
	for i in CHUNKS:
		var group : Array = bins[i]
		if group.is_empty():
			continue
		var seg := RigidBody3D.new()
		seg.add_to_group("bale_piece")
		seg.mass = maxf(src_mass / float(live_chunks), 0.5)
		seg.linear_damp = 1.6
		seg.angular_damp = 3.5     # films settle, don't tumble
		var pm := PhysicsMaterial.new()
		pm.friction = 0.95         # sticky — layers cling, drape into a pile
		pm.bounce = 0.0
		seg.physics_material_override = pm
		# Collision box spanning this chunk (sheets ride visually inside it).
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(seg_len * 0.98, size.y, size.z)
		cs.shape = bx
		seg.add_child(cs)
		scene.add_child(seg)
		# Position the body at this chunk's centre (bale orientation preserved),
		# THEN move the real sheets in keeping their world pose — so the pile
		# starts exactly where the intact bale was, from its own meshes.
		var local_x : float = -half_x + seg_len * (float(i) + 0.5)
		seg.global_transform = xf * Transform3D(Basis(), Vector3(local_x, size.y * 0.5, 0.0))
		for mi in group:
			mi.reparent(seg, true)   # keep_global_transform — no visual jump
		# Soft pin to the previous chunk so the strip stays roughly layered as it
		# flops open (film clings), but can tear apart under a sharp pull.
		if prev != null:
			var joint := PinJoint3D.new()
			scene.add_child(joint)
			joint.global_position = (prev.global_position + seg.global_position) * 0.5
			joint.node_a = prev.get_path()
			joint.node_b = seg.get_path()
			joint.set_param(PinJoint3D.PARAM_IMPULSE_CLAMP, 4.0)
			joint.set_param(PinJoint3D.PARAM_DAMPING, 0.6)
		# Gentle opening: end pieces lift + fan outward, middle stays low.
		var s := (float(i) - float(CHUNKS - 1) * 0.5) / float(CHUNKS - 1)
		seg.linear_velocity = xf.basis * Vector3(s * 0.7, absf(s) * 0.5, 0.0)
		out.append(seg)
		_live_pieces.append(seg)
		prev = seg

	# The bale's material now lives in the piece bodies. Free only the emptied
	# husk (wires already cut, label + shell). If anything visual remains under
	# Sheets it was already carried over above.
	bale.queue_free()
	return out

static func _gather_meshes(n: Node, out: Array[MeshInstance3D]) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_gather_meshes(c, out)

static func _bale_size(bale: Node3D) -> Vector3:
	# Prefer the live collision shape (authoritative in-scene footprint).
	for c in bale.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape is BoxShape3D:
			return ((c as CollisionShape3D).shape as BoxShape3D).size
	if bale.has_meta("material_origin"):
		var o := BaleDefs.get_origin(String(bale.get_meta("material_origin")))
		if not o.is_empty():
			return o["size"]
	return Vector3(1.2, 1.05, 1.05)

## Keep the live piece count bounded — free the oldest if we'd exceed the cap.
static func _cap_existing(scene: Node) -> void:
	var tree := scene.get_tree()
	if tree == null:
		return
	var pieces := tree.get_nodes_in_group("bale_piece")
	var excess := pieces.size() + CHUNKS - MAX_PIECES_LIVE
	for k in range(maxi(0, excess)):
		if k < pieces.size() and is_instance_valid(pieces[k]):
			(pieces[k] as Node).queue_free()
