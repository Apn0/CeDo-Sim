class_name StaticMerge
extends RefCounted

# =============================================================================
# #224 — Static-mesh baker for placeable machine models.
# =============================================================================
# Bakes every STATIC MeshInstance3D descendant of a machine root into a SINGLE
# merged MeshInstance3D (one surface per distinct material *look*), so a machine
# built from ~30-80 _box/_cyl parts renders in a handful of draw calls instead of
# one-per-part. Triangles are preserved (and detail can be added freely) while
# the draw-call count collapses — the whole point of the "detail + static-merge"
# approach (goal: more triangles WITHOUT tanking the framerate, #221).
#
# DYNAMIC parts are left completely untouched so they keep working:
#   * anything in group "mechanism" (RotatingMechanism-driven rotors/discs) or
#     UNDER such a node — it must keep spinning;
#   * anything carrying set_meta("comp", ...) — rotors/scrapers/belts/cutters/
#     flow endpoints that other systems (LineFlow, RPM, HMI) reference by name;
#   * particles (steam), lights, labels, cameras, areas, animatable/rigid bodies,
#     and any node with a script (behavioural);
#   * anything tagged set_meta("no_merge", true) (per-model opt-out).
# Collision (StaticBody3D CollisionShape3Ds) is never a MeshInstance3D, so it is
# preserved automatically.
#
# Grouping is by material SIGNATURE (albedo/metallic/roughness/emission/…), not
# object identity — the builders mint a fresh StandardMaterial3D per part, so
# identity grouping would defeat the merge. Same-looking parts collapse to one
# surface = one draw call.
# =============================================================================

## Merge all static descendant meshes of `root` in place. Safe to call on any
## Node3D; a no-op when there is nothing worth merging (< 2 static meshes).
static func merge_static(root: Node3D) -> void:
	if root == null or not is_instance_valid(root):
		return
	if root.has_meta("no_merge"):
		return
	var statics : Array = []
	_collect(root, root, statics, false)
	if statics.size() < 2:
		return

	# Group source surfaces by material signature.
	var by_sig : Dictionary = {}   # sig String -> {st: SurfaceTool, mat: Material}
	for e in statics:
		var mi : MeshInstance3D = e["mi"]
		var mesh : Mesh = mi.mesh
		if mesh == null:
			continue
		var xf : Transform3D = e["xf"]
		for si in mesh.get_surface_count():
			var mat : Material = mi.get_active_material(si)
			var sig : String = _mat_sig(mat)
			if not by_sig.has(sig):
				var st0 := SurfaceTool.new()
				st0.begin(Mesh.PRIMITIVE_TRIANGLES)
				by_sig[sig] = {"st": st0, "mat": mat}
			(by_sig[sig]["st"] as SurfaceTool).append_from(mesh, si, xf)

	if by_sig.is_empty():
		return

	# Commit into one ArrayMesh, one surface per signature.
	var merged := ArrayMesh.new()
	for sig in by_sig.keys():
		var st : SurfaceTool = by_sig[sig]["st"]
		st.index()
		var before : int = merged.get_surface_count()
		st.commit(merged)
		if merged.get_surface_count() > before:
			merged.surface_set_material(before, by_sig[sig]["mat"])

	var out := MeshInstance3D.new()
	out.name = "StaticMerged"
	out.mesh = merged
	root.add_child(out)

	# Drop the originals now that their geometry lives in the merged mesh.
	for e in statics:
		var mi : MeshInstance3D = e["mi"]
		if is_instance_valid(mi):
			if mi.get_parent() != null:
				mi.get_parent().remove_child(mi)
			mi.queue_free()

## Recursively gather static MeshInstance3Ds with their transform relative to
## `root`. `dyn_anc` carries "an ancestor is dynamic" down the walk.
static func _collect(node: Node, root: Node3D, out: Array, dyn_anc: bool) -> void:
	var dyn : bool = dyn_anc or _is_dynamic(node)
	if not dyn and node is MeshInstance3D and node != root:
		var mi := node as MeshInstance3D
		if mi.mesh != null and mi.visible:
			out.append({"mi": mi, "xf": _rel_xform(mi, root)})
	for c in node.get_children():
		_collect(c, root, out, dyn)

## Transform of `node` expressed in `root`'s local frame — accumulated up the
## parent chain so it works BEFORE the tree is entered (build time), unlike
## global_transform.
static func _rel_xform(node: Node3D, root: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var n : Node = node
	while n != null and n != root:
		if n is Node3D:
			xf = (n as Node3D).transform * xf
		n = n.get_parent()
	return xf

static func _is_dynamic(node: Node) -> bool:
	if node == null:
		return false
	if node.has_meta("no_merge"):
		return true
	if node.has_meta("comp"):
		return true          # named component — referenced/animated elsewhere
	if node.get_script() != null:
		return true          # behavioural node
	if node is GPUParticles3D or node is CPUParticles3D:
		return true
	if node is Light3D or node is Label3D or node is Camera3D:
		return true
	if node is Area3D or node is AnimatableBody3D or node is RigidBody3D:
		return true
	if node.is_in_group("mechanism") or node.is_in_group("steam_plume") \
			or node.is_in_group("hmi_panel") or node.is_in_group("interactive"):
		return true
	# Support legs / foot pads are rescaled to the floor AFTER the model is built
	# (extend_machine_legs runs at placement time). If the merge bakes them away
	# here, a raised machine has no legs left to lengthen and floats above the
	# floor on nothing (bughunt 2026-07-17). Keep them separate so the floor-snap
	# can still find, stretch and hide them. Cheap: legs are low-poly cylinders.
	if node.is_in_group("machine_leg") or node.is_in_group("machine_foot"):
		return true
	return false

## A compact signature of a material's LOOK, so visually-identical parts (which
## the builders create as distinct StandardMaterial3D objects) collapse into one
## merged surface.
static func _mat_sig(mat: Material) -> String:
	if mat == null:
		return "null"
	if mat is StandardMaterial3D:
		var m := mat as StandardMaterial3D
		var em : Color = m.emission if m.emission_enabled else Color(0, 0, 0, 0)
		return "std|%s|%.3f|%.3f|%s|%d|%d|%d" % [
			str(m.albedo_color), m.metallic, m.roughness, str(em),
			int(m.transparency), int(m.cull_mode), int(m.shading_mode)]
	# Non-standard material (shader etc.): keep distinct by identity.
	return "obj|%d" % mat.get_instance_id()
