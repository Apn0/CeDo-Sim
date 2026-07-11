extends RefCounted
class_name BaleBurst
## #23 — open a wired bale into SIX physical pieces.
##
## Cutting the wires + releasing the clamp removes everything that held the sheet
## stack together, so the bale comes apart into 6 segment bodies along its length:
## the middle stays roughly upright while the end pieces fan/arc outward — the way a
## de-wired film bale actually flops open. These are REAL rigid bodies (each a short
## sub-stack of thin layered slabs), not one solid block and not 3 fake chunks.
##
## Honest limit: true per-sheet cloth bending isn't feasible at scale, so the "bend"
## is 6 fanned rigid pieces, which is stable and reads as the bale opening. The
## arc angle / direction are constants below — easy to tune once seen in-game.
## Pieces are capped scene-wide so they can't pile up forever while there's no
## shredder downstream to consume them.

const PIECES          : int   = 6
const MAX_PIECES_LIVE : int   = 60          # scene-wide safety cap (~10 bales' worth)
const LAYERS_PER_PIECE : int  = 8           # thin visual slabs per piece (film look)

## Replace `bale` with 6 fanned physical pieces at the same world pose; free the
## original. `scene` is where the pieces live (usually current_scene). Returns them.
static func open(bale: Node3D, scene: Node) -> Array:
	if bale == null or not is_instance_valid(bale) or scene == null:
		return []
	var xf := bale.global_transform
	var size := _bale_size(bale)
	var tint := _tint(bale)
	_cap_existing(scene)
	var seg_len := size.x / float(PIECES)
	# #223 audit (critical): mass conservation. The old hardcoded 4 kg/piece made
	# a 400-717 kg bale collapse to 24 kg — a one-sixth chunk of ~65-120 kg of
	# compressed film could be kicked across the floor like a box. Each piece now
	# carries its real share of the source bale's mass (read the source RigidBody
	# so per-origin weight overrides carry through; fall back to volume × bulk
	# density).
	var src_mass : float = 0.0
	var src_rb := bale as RigidBody3D
	if src_rb != null:
		src_mass = src_rb.mass
	if src_mass < 1.0:
		src_mass = size.x * size.y * size.z * BaleDefs.BULK_DENSITY
	var piece_mass : float = maxf(src_mass / float(PIECES), 1.0)
	var out : Array = []
	var prev : RigidBody3D = null
	var prev_x := 0.0
	for i in PIECES:
		# signed position across the length: -0.5 (left end) .. +0.5 (right end)
		var s := (float(i) - float(PIECES - 1) * 0.5) / float(PIECES - 1)
		var seg := RigidBody3D.new()
		seg.add_to_group("bale_piece")
		seg.mass = piece_mass
		seg.angular_damp = 1.2          # calm the joint chain so it flexes, not jitters
		var pm := PhysicsMaterial.new()
		pm.friction = 0.95
		pm.bounce = 0.0
		seg.physics_material_override = pm
		var dims := Vector3(seg_len * 0.96, size.y, size.z)
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = dims
		cs.shape = bx
		seg.add_child(cs)
		_build_layers(seg, dims, tint)
		scene.add_child(seg)
		# Lay the pieces ADJACENT in a row, bottom on the deck. The bend is REAL:
		# consecutive pieces are pin-jointed (below), so the strip FLEXES/curls under
		# gravity + the opening nudge — not rigid chunks thrown apart.
		var local_x := -size.x * 0.5 + seg_len * (float(i) + 0.5)
		seg.global_transform = xf * Transform3D(Basis(), Vector3(local_x, size.y * 0.5, 0.0))
		if prev != null:
			var joint := PinJoint3D.new()
			scene.add_child(joint)
			joint.global_position = xf * Vector3((prev_x + local_x) * 0.5, size.y * 0.5, 0.0)
			joint.node_a = prev.get_path()
			joint.node_b = seg.get_path()
		# Gentle opening nudge: ends lift + push outward; the joints turn that into a
		# flex/curl along the whole strip (the middle stays lowest).
		seg.linear_velocity = xf.basis * Vector3(s * 0.8, absf(s) * 0.6, 0.0)
		out.append(seg)
		prev = seg
		prev_x = local_x
	bale.queue_free()
	return out

## Many thin slabs stacked along X inside a piece, so it reads as a dense film stack
## without adding physics bodies (the piece is one rigid body).
static func _build_layers(seg: RigidBody3D, dims: Vector3, tint: Color) -> void:
	var t := dims.x / float(LAYERS_PER_PIECE)
	for j in LAYERS_PER_PIECE:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(t * 0.9, dims.y * 0.98, dims.z * 0.98)
		mi.mesh = bm
		var col := tint.lerp(Color(0.30, 0.50, 0.40), float(j % 3) * 0.12)
		var m := StandardMaterial3D.new()
		m.albedo_color = col
		m.roughness = 0.9
		mi.material_override = m
		mi.position = Vector3(-dims.x * 0.5 + t * (float(j) + 0.5), 0.0, 0.0)
		seg.add_child(mi)

static func _bale_size(bale: Node3D) -> Vector3:
	if bale.has_meta("material_origin"):
		var o := BaleDefs.get_origin(String(bale.get_meta("material_origin")))
		if not o.is_empty():
			return o["size"]
	return Vector3(1.2, 1.05, 1.05)

static func _tint(bale: Node3D) -> Color:
	if bale.has_meta("material_origin"):
		var o := BaleDefs.get_origin(String(bale.get_meta("material_origin")))
		if not o.is_empty():
			return o.get("tint", Color(0.62, 0.64, 0.60))
	return Color(0.62, 0.64, 0.60)

## Keep the live piece count bounded — free the oldest if we'd exceed the cap.
static func _cap_existing(scene: Node) -> void:
	var tree := scene.get_tree()
	if tree == null:
		return
	var pieces := tree.get_nodes_in_group("bale_piece")
	var excess := pieces.size() + PIECES - MAX_PIECES_LIVE
	for k in range(maxi(0, excess)):
		if k < pieces.size() and is_instance_valid(pieces[k]):
			(pieces[k] as Node).queue_free()
