extends Node3D
# Render every AnimationTree state of the Humanoid rig to PNGs so stance /
# locomotion fixes are proven by pixels, not asserted. Run WINDOWED:
#   Godot --path . res://src/tests/shot_humanoid_stances.tscn
# Optional user args:  -- <yaw_deg> (default 210 = 3/4 from the front-left)
# Output: docs/plant/renders/shot_stance_<state>.png (one per state).
#
# Operator bug report 2026-08-28: walk showed a stiff statue, crouch did
# nothing, prone folded the torso down while the LEGS stayed standing. Root
# cause: limb meshes lived on legacy HipPivot/ShoulderPivot nodes, not on the
# skeleton the animations drive. This shot tool is the before/after evidence.

const _STATES : Array = [
	# [state_name, blend_position or null, settle_s]
	["locomotion_idle", Vector2(0.0, 0.0), 0.6],
	["locomotion_walk", Vector2(1.0, 0.0), 0.5],
	["locomotion_run",  Vector2(2.0, 0.0), 0.45],
	["jump",   null, 0.6],
	["crouch", null, 0.6],
	["prone",  null, 0.6],
	["seated", null, 0.6],
	["climb",  null, 0.6],
]

func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var yaw : float = float(args[0]) if args.size() >= 1 else 210.0
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.62, 0.65)
	env.ambient_light_energy = 1.1
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.25
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(30.0, 30.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	ground.position.y = -0.9   # feet are at y = -0.86 in rig space
	add_child(ground)

	# The player's default look: operator PPE so limbs (orange arms, denim legs)
	# read clearly against the grey floor.
	var body : Node3D = Humanoid.build(Color(0.95, 0.45, 0.10), 0, {"ppe": "operator"})
	add_child(body)

	var atree : AnimationTree = body.get_node_or_null("AnimationTree") as AnimationTree
	if atree == null:
		print("[SHOT] ERROR: no AnimationTree on the Humanoid rig")
		get_tree().quit(1); return

	var cam := Camera3D.new()
	add_child(cam)
	var yr : float = deg_to_rad(yaw)
	var dist : float = 3.4
	cam.global_position = Vector3(sin(yr) * dist, 0.9, cos(yr) * dist)
	cam.look_at(Vector3(0.0, -0.1, 0.0), Vector3.UP)
	cam.make_current()

	var out_dir := "res://docs/plant/renders/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var pb := atree.get("parameters/playback") as AnimationNodeStateMachinePlayback
	var fails : int = 0
	for entry in _STATES:
		var tag : String = String(entry[0])
		var state : String = tag.get_slice("_", 0) if tag.begins_with("locomotion") else tag
		if pb != null:
			pb.travel(state)
		if entry[1] != null:
			atree.set("parameters/locomotion/blend_position", entry[1] as Vector2)
		await get_tree().create_timer(float(entry[2])).timeout
		# Walk/run are cycles — a shot at a swing zero-crossing looks like
		# standing still. Poll for a frame where the leg swing is near its
		# peak so the PNG proves the gait, and the timeout proves a dead rig.
		var skel : Skeleton3D = body.get_node_or_null("Skeleton3D") as Skeleton3D
		var bi : int = skel.find_bone("LUpperLeg") if skel != null else -1
		if tag.begins_with("locomotion_") and tag != "locomotion_idle" and bi >= 0:
			var hit_peak := false
			for _f in 180:
				var qq : Quaternion = skel.get_bone_pose_rotation(bi)
				if rad_to_deg(2.0 * acos(clampf(absf(qq.w), -1.0, 1.0))) >= 15.0:
					hit_peak = true
					break
				await get_tree().process_frame
			if not hit_peak:
				# 180 frames (3 s) is several full gait loops. Never reaching the
				# swing peak means the cycle is not driving the bone — shoot the
				# frame anyway (it is the evidence) but FAIL loudly instead of
				# quietly saving a statue that looks like a fine still.
				print("[SHOT] DEAD-RIG: %s never reached the swing peak in 180 frames" % tag)
				fails += 1
		# Diagnose the anim data-path: what the tree thinks the blend is, and
		# what the skeleton bone actually holds at shot time.
		if bi >= 0:
			var q : Quaternion = skel.get_bone_pose_rotation(bi)
			print("[SHOT-DIAG] %s blend=%s cur_state=%s LUpperLeg_rot_deg=%.1f" % [
				tag, str(atree.get("parameters/locomotion/blend_position")),
				(pb.get_current_node() if pb != null else "?"),
				rad_to_deg(2.0 * acos(clampf(absf(q.w), -1.0, 1.0)))])
		var img := get_viewport().get_texture().get_image()
		var outp : String = out_dir + "shot_stance_%s.png" % tag
		img.save_png(outp)
		if not preload("res://src/tests/shot_common.gd").check_image_content(img, outp):
			fails += 1
		print("[SHOT] saved ", ProjectSettings.globalize_path(outp))
	get_tree().quit(1 if fails > 0 else 0)
