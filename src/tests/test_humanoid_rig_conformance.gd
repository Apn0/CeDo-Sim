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

## World-space vertical extent of every mesh in the rig — the same measurement
## probe_stance_extents prints. Used to prove a pose neither sinks through the
## floor nor merely pretends to crouch.
func _mesh_y_range(root: Node3D) -> Vector2:
	var lo : float = 1e9
	var hi : float = -1e9
	var stack : Array = [root]
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
	return Vector2(lo, hi)

func _lowest_mesh_y(root: Node3D) -> float:
	return _mesh_y_range(root).x

func _height(root: Node3D) -> float:
	var r : Vector2 = _mesh_y_range(root)
	return r.y - r.x

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
	# Check the SIGNED X component, not just the angle magnitude: a -45° tuck
	# (leg swung BACKWARD) has the identical |angle| and would sail through a
	# magnitude-only gate while looking wrong.
	var jump_q : Quaternion = skel.get_bone_pose_rotation(skel.find_bone("LUpperLeg"))
	_check(absf(_bone_angle_deg(skel, "LUpperLeg") - 45.0) < 3.0 and jump_q.x > 0.3,
		"jump pose tucks the lead leg FORWARD (%.1f°, quat.x %.2f — want 45°, x>0)"
		% [_bone_angle_deg(skel, "LUpperLeg"), jump_q.x])
	# The trail leg must go the OTHER way, or the "tuck" is both legs in
	# lockstep — a scissor, not a jump.
	var jump_r : Quaternion = skel.get_bone_pose_rotation(skel.find_bone("RUpperLeg"))
	_check(jump_r.x < 0.0, "jump pose sweeps the trail leg back (quat.x %.2f)" % jump_r.x)
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
	# Ground poses must not sink through the floor: the standing sole sits at
	# y = -0.90, so nothing may go below that. (Measured with
	# probe_stance_extents; prone was -0.97 and crouch -0.97 before the fix.)
	_check(_lowest_mesh_y(body) > -0.92,
		"prone rests ON the floor plane, not through it (low %.2f, stand sole -0.90)"
		% _lowest_mesh_y(body))
	# Crouch must be a REAL crouch. The first cut measured 1.70 m against a
	# 1.78 m stand — a 4%% squat the operator read as "crouching does nothing".
	pb.travel("crouch")
	for _f4 in 60:
		await get_tree().process_frame
	var crouch_h : float = _height(body)
	_check(crouch_h < 1.50, "crouch actually crouches (%.2f m vs 1.78 m standing)" % crouch_h)
	_check(_lowest_mesh_y(body) > -0.92 and _lowest_mesh_y(body) < -0.85,
		"crouch keeps the feet PLANTED on the floor plane (low %.2f)" % _lowest_mesh_y(body))

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

	# ── S4 — the REAL FP layer splitter still finds the legs ────────────────
	# First person shows only the operator's legs (operator request
	# 2026-07-05). MainWorld classifies by ancestor NAME, and the unification
	# moved every leg mesh off HipPivot* onto BA_*Leg/BA_*Foot — so run the
	# actual production function over a real rig and count the buckets.
	print("  -- S4: MainWorld FP leg/head render split --")
	var mw_script := load("res://src/scenes/world/MainWorld.gd")
	var mw = mw_script.new()
	var fp_body : Node3D = Humanoid.build(Color.WHITE, 0, {"ppe": "operator"})
	fp_body.name = "PlayerBody"      # the walker's stop-name
	add_child(fp_body)
	await get_tree().process_frame
	mw.call("_set_body_render_layer_split", fp_body)
	var n_leg : int = 0
	var n_head : int = 0
	var s2 : Array = [fp_body]
	while not s2.is_empty():
		var n2 : Node = s2.pop_back()
		for c4 in n2.get_children():
			s2.append(c4)
		if n2 is MeshInstance3D:
			# Leg bucket = layer 2 (1<<1), FP-culled bucket = layer 4 (1<<2).
			if int((n2 as MeshInstance3D).layers) == 2: n_leg += 1
			elif int((n2 as MeshInstance3D).layers) == 4: n_head += 1
	_check(n_leg >= 6,
		"the FP splitter still tags the LEGS visible after the bone move (%d leg meshes, was 0 with the old HipPivot-only rule)" % n_leg)
	_check(n_head > 0, "torso/head/arms stay FP-culled (%d meshes)" % n_head)
	# SandboxWorld._tag_body_layers uses a DIFFERENT rule — summed local Y with
	# a 0.55 head threshold. The unification could have broken it, because the
	# meshes moved under BoneAttachment3D nodes: it only still works because a
	# mesh's position became (rig_local - bone_rest) while its attachment is
	# seeded to bone_rest, so the sum cancels back to the anatomical height.
	# Replicate that walk here and prove the head still lands above 0.55.
	var head_hits : int = 0
	var s3 : Array = [fp_body]
	while not s3.is_empty():
		var n3 : Node = s3.pop_back()
		for c5 in n3.get_children():
			s3.append(c5)
		if n3 is MeshInstance3D:
			var y_local : float = (n3 as MeshInstance3D).position.y
			var par : Node = n3.get_parent()
			while par != null and (not (par is Node3D) or par.name != "PlayerBody"):
				if par is Node3D:
					y_local += (par as Node3D).position.y
				par = par.get_parent()
			if y_local >= 0.55:
				head_hits += 1
	_check(head_hits >= 4,
		"the sandbox Y-sum walk still reconstructs anatomical height at rest (%d meshes above 0.55 — head/cap/face)" % head_hits)
	mw.free()

	print("[TEST] humanoid rig conformance %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	# CANONICAL VERDICT LINE. tools/regression/run.sh gates on
	# grep -E "Result: PASS|RESULT: PASS" -- the descriptive line above does
	# NOT match it. Measured 2026-08-28: all four conformance tests passed
	# standalone and reported FAIL in the harness for this reason alone.
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
