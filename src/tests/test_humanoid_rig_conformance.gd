extends Node
## Humanoid rig conformance — guards the 2026-08-28 animation fixes.
##
##   godot --headless --path . res://src/tests/test_humanoid_rig_conformance.tscn
##
## Operator bug report (screenshots, 2026-08-28): walk/run/jump showed a stiff
## statue, crouch did nothing visible, prone folded the torso down while the
## LEGS stayed standing — and a second player body spawned inside the first.
## Root causes fixed: (1) limb meshes lived on legacy HipPivot/ShoulderPivot
## nodes while the AnimationTree drove limb bones that owned no meshes;
## (2) prone's Hips sign was -90° (face-UP, arms skyward); (3) there was no
## airborne pose at all; (4) Humanoid.rebuild_appearance didn't know the
## player rig's name "PlayerBody", so every shift-bell wardrobe rebuild added
## a stray second body and freed nothing.
## Three layers: S1 rig structure, S2 animated poses, S3 rebuild one-body.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _bone_angle_deg(skel: Skeleton3D, bone: String) -> float:
	var q : Quaternion = skel.get_bone_pose_rotation(skel.find_bone(bone))
	return rad_to_deg(2.0 * acos(clampf(absf(q.w), -1.0, 1.0)))

func _run() -> void:
	print("[TEST] humanoid rig conformance")
	var body : Node3D = Humanoid.build(Color(0.9, 0.5, 0.1), 0, {"ppe": "operator"})
	add_child(body)
	await get_tree().process_frame

	# ── S1 — rig structure: every mesh bone-owned, pivots empty ─────────────
	print("  -- S1: rig structure --")
	var loose : int = 0
	var on_bones : int = 0
	var stack : Array = [body]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var owned := false
			var p : Node = n.get_parent()
			while p != null and p != body:
				if p is BoneAttachment3D:
					owned = true
					break
				p = p.get_parent()
			if owned: on_bones += 1
			else: loose += 1
	_check(loose == 0, "every MeshInstance3D sits under a BoneAttachment3D (loose: %d)" % loose)
	_check(on_bones > 20, "the rig actually has meshes (%d bone-owned)" % on_bones)
	for pivot_name in ["HipPivot_L", "HipPivot_R", "ShoulderPivot_L", "ShoulderPivot_R"]:
		var pivot : Node = body.get_node_or_null(pivot_name)
		_check(pivot != null and pivot.get_child_count() == 0,
			"%s exists for name-compat and owns NOTHING" % pivot_name)
	# Leg meshes must live under leg-bone attachments — MainWorld's FP layer
	# splitter (first person shows only the legs) classifies by these names.
	var skel : Skeleton3D = body.get_node_or_null("Skeleton3D") as Skeleton3D
	var leg_meshes : int = 0
	for ba_name in ["BA_LFoot", "BA_RFoot", "BA_LLowerLeg", "BA_RLowerLeg",
			"BA_LUpperLeg", "BA_RUpperLeg"]:
		var ba : Node = skel.get_node_or_null(ba_name)
		if ba != null:
			for c2 in ba.get_children():
				if c2 is MeshInstance3D:
					leg_meshes += 1
	_check(leg_meshes >= 6, "feet/shins/thighs are bone-owned (%d leg meshes)" % leg_meshes)

	# ── S2 — animated poses reach the bones ─────────────────────────────────
	print("  -- S2: animated poses --")
	var atree : AnimationTree = body.get_node_or_null("AnimationTree") as AnimationTree
	var ap : AnimationPlayer = body.get_node_or_null("AnimationPlayer") as AnimationPlayer
	_check(ap.has_animation("jump_pose"), "jump_pose animation exists in the library")
	var pb := atree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	# Walk: blend to the walk point and sample the leg swing over one loop —
	# the amplitude proves the cycle drives the bones (a statue reads ~0°).
	# Travel first and give the SM a few frames: setting blend_position before
	# the tree has instantiated the parameter path is a SILENT no-op.
	pb.travel("locomotion")
	for _w in 5:
		await get_tree().process_frame
	atree.set("parameters/locomotion/blend_position", Vector2(1.0, 0.0))
	var max_swing : float = 0.0
	for _f in 90:
		await get_tree().process_frame
		max_swing = maxf(max_swing, _bone_angle_deg(skel, "LUpperLeg"))
	_check(max_swing >= 15.0, "walk cycle swings LUpperLeg (peak %.1f°, statue would be ~0°)" % max_swing)
	# Jump: travel and confirm the tuck lands on the bone (60 frames ≈ 1 s so
	# the 0.25 s crossfade is fully finished before the gate reads the bone).
	pb.travel("jump")
	for _f2 in 60:
		await get_tree().process_frame
	_check(absf(_bone_angle_deg(skel, "LUpperLeg") - 45.0) < 3.0,
		"jump pose tucks the lead leg (LUpperLeg %.1f°, want 45°)" % _bone_angle_deg(skel, "LUpperLeg"))
	# Prone: whole chain flat AND face-down. The face-down sign is the +90°
	# Hips X rotation — the -90° regression (face-up, arms skyward) keys the
	# quaternion with a NEGATIVE x component.
	pb.travel("prone")
	for _f3 in 60:
		await get_tree().process_frame
	var hips_q : Quaternion = skel.get_bone_pose_rotation(skel.find_bone("Hips"))
	_check(hips_q.x > 0.6, "prone is FACE-DOWN (+90° Hips pitch; face-up bug had x=%.2f)" % hips_q.x)
	var head_y : float = (skel.get_node("BA_Head") as Node3D).global_position.y
	var foot_y : float = (skel.get_node("BA_LFoot") as Node3D).global_position.y
	_check(head_y < -0.2, "prone lays the HEAD near the floor (y=%.2f)" % head_y)
	_check(foot_y < 0.0, "prone lays the FEET down too — the standing-legs bug (y=%.2f)" % foot_y)

	# ── S3 — rebuild_appearance keeps exactly ONE body ──────────────────────
	print("  -- S3: rebuild one-body guard --")
	for rig_name in ["PlayerBody", "HumanoidBody", "Body"]:
		var holder := Node3D.new()
		add_child(holder)
		var first : Node3D = Humanoid.build(Color.WHITE, 0, {})
		first.name = rig_name
		holder.add_child(first)
		var fresh : Node3D = Humanoid.rebuild_appearance(holder, Color.WHITE, 1, {"hair": "long"})
		await get_tree().process_frame
		var bodies : int = 0
		for c3 in holder.get_children():
			if is_instance_valid(c3) and not c3.is_queued_for_deletion() \
					and (c3 as Node3D) != null and c3.get_node_or_null("Skeleton3D") != null:
				bodies += 1
		_check(bodies == 1, "rebuild_appearance('%s') leaves exactly ONE body (got %d)" % [rig_name, bodies])
		_check(fresh != null and String(fresh.name) == rig_name,
			"the fresh rig keeps the name '%s' so per-frame lookups still resolve" % rig_name)
		holder.queue_free()

	print("[TEST] humanoid rig conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
