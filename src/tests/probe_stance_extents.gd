extends Node
## One-shot measurement: how TALL is the rig in each stance pose, really?
## The NPC capsule heights (_CAPSULE_HEIGHT) were tuned against the old
## Y-squash; after the 2026-08-28 rig unification the poses are real, so the
## capsule must fit the posed body. Prints measured extents — no assertions.
##   godot --headless --path . res://src/tests/probe_stance_extents.tscn

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var body : Node3D = Humanoid.build(Color.WHITE, 0, {"ppe": "operator"})
	add_child(body)
	await get_tree().process_frame
	var atree : AnimationTree = body.get_node_or_null("AnimationTree") as AnimationTree
	var pb := atree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	for state in ["locomotion", "crouch", "prone", "seated", "jump"]:
		pb.travel(state)
		for _f in 60:
			await get_tree().process_frame
		var lo : float = 1e9
		var hi : float = -1e9
		var stack : Array = [body]
		while not stack.is_empty():
			var n : Node = stack.pop_back()
			for c in n.get_children():
				stack.append(c)
			if n is MeshInstance3D:
				var mi := n as MeshInstance3D
				var aabb : AABB = mi.get_aabb()
				for i in 8:
					var wy : float = (mi.global_transform * aabb.get_endpoint(i)).y
					lo = minf(lo, wy)
					hi = maxf(hi, wy)
		print("[EXTENT] %-11s low=%+.2f high=%+.2f  height=%.2f m" % [state, lo, hi, hi - lo])
	get_tree().quit(0)
