extends Node
## One-off probe (P1, 2026-09-23): which way does each belt deck's local +Z
## point in WORLD space, and does it climb? The film field drifts along its
## own +Z, so it must share the deck's plane and point downstream — measured
## here off the built geometry, never assumed from the builder's comments.
##
##   godot --headless --path . res://src/tests/probe_deck_orientation.tscn

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	for id in ["transport_belt", "transportband_3", "switch_belt", "compactorband", "inclined_belt_8m"]:
		var body : Node3D = PlaceableCatalog.build_node(id, false)
		if body == null:
			print("  %-18s NOT BUILT" % id)
			continue
		add_child(body)
		await get_tree().process_frame
		var skins : Array = []
		var n_mi := 0
		for c in body.find_children("*", "", true, false):
			var mi := c as MeshInstance3D
			if mi == null or mi.mesh == null:
				continue
			n_mi += 1
			var s : Vector3 = mi.mesh.get_aabb().size * mi.scale
			if s.z > 2.0 and s.y < 0.2 and s.x > 0.5:
				skins.append(mi)
		print("  %-18s %d mesh instances, %d deck-like" % [id, n_mi, skins.size()])
		if id == "transport_belt" or id == "inclined_belt_8m":
			for c in body.find_children("*", "", true, false):
				var mi := c as MeshInstance3D
				if mi != null and mi.mesh != null:
					print("  %-18s   mesh %-14s %s scale=%s parent=%s" % [id, mi.mesh.get_class(), mi.mesh.get_aabb().size, mi.scale, mi.get_parent().name])
		for mi in skins:
			var b : Basis = (mi as MeshInstance3D).global_transform.basis
			print("  %-18s %s %s name=%s at %s  +Z=%s  +Y=%s" % [id, mi.mesh.get_class(),
				mi.mesh.get_aabb().size * mi.scale, mi.name, (mi as Node3D).global_position, b.z.normalized(), b.y.normalized()])
		body.queue_free()
	# Convention check + the UNMERGED inclined belt (extras called directly).
	var n := Node3D.new()
	add_child(n)
	n.rotation = Vector3(deg_to_rad(45.0), 0.0, 0.0)
	print("  Rx(+45deg): local +Z -> %s   local +Y -> %s" % [n.transform.basis.z, n.transform.basis.y])
	var p := Node3D.new()
	add_child(p)
	PlaceableCatalog._inclined_belt_extras(p, p, Vector3(1.0, 8.5, 8.5), {}, false)
	for c in p.get_children():
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.z > 10.0:
			print("  inclined deck box %s at %s rot=%s  +Z=%s +Y=%s" % [(mi.mesh as BoxMesh).size, mi.position, mi.rotation, mi.global_transform.basis.z, mi.global_transform.basis.y])
	var q := Node3D.new()
	add_child(q)
	var sp : Dictionary = BeltBuilder.make_spec()
	sp.deck_kind = "tilted"; sp.incline_deg = 10.0
	BeltBuilder.build_internal(q, "transportband_3", Vector3(1.0, 1.30, 8.0), sp, false)
	for c in q.find_children("*", "", true, false):
		var mi := c as MeshInstance3D
		if mi != null and mi.mesh is BoxMesh and (mi.mesh as BoxMesh).size.z > 5.0 and (mi.mesh as BoxMesh).size.y < 0.1:
			print("  tilted deck box %s parent=%s at %s  +Z=%s +Y=%s" % [(mi.mesh as BoxMesh).size, mi.get_parent().name, mi.global_position, mi.global_transform.basis.z, mi.global_transform.basis.y])
	print("Result: PASS (probe)")
	get_tree().quit(0)
