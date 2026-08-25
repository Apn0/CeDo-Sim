extends SceneTree

# We don't preload ContainerGuide directly because we just want to benchmark the function logic.

func _apply_holographic_material_original(root: Node) -> void:
	for child in root.find_children("*", "MeshInstance3D", true, false):
		var mi := child as MeshInstance3D
		if mi == null:
			continue
		var m := StandardMaterial3D.new()
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _apply_holographic_material_optimized(root: Node) -> void:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node = stack.pop_back()
		if node != root and node is MeshInstance3D:
			var mi := node as MeshInstance3D
			var m := StandardMaterial3D.new()
			mi.material_override = m
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		for i in range(node.get_child_count() - 1, -1, -1):
			stack.append(node.get_child(i))

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — Holographic Material Benchmark")
	print("============================================================")

	var root = Node3D.new()
	var parent1 = Node3D.new()
	root.add_child(parent1)
	for i in range(5):
		var mi = MeshInstance3D.new()
		parent1.add_child(mi)
		var parent2 = Node3D.new()
		parent1.add_child(parent2)
		for j in range(5):
			var mi2 = MeshInstance3D.new()
			parent2.add_child(mi2)

	for i in range(20):
		var n = Node.new()
		root.add_child(n)

	var iter_count = 5000

	var t0 = Time.get_ticks_usec()
	for i in range(iter_count):
		_apply_holographic_material_original(root)
	var t1 = Time.get_ticks_usec()

	var t2 = Time.get_ticks_usec()
	for i in range(iter_count):
		_apply_holographic_material_optimized(root)
	var t3 = Time.get_ticks_usec()

	print("Original recursive find_children time for %d iterations: %d us" % [iter_count, (t1 - t0)])
	print("Optimized stack traversal time for %d iterations: %d us" % [iter_count, (t3 - t2)])

	quit(0)
