extends Node3D
# Photo-audit annotation helper: renders flotation_tank with coloured overlays at
# the model's ACTUAL 3D component positions (projected through the same camera as
# shot_placeable). Operator asked (2026-07-15) to mark: RED = paddle-shaft bearings
# (where paddles meet the tank side), ORANGE = paddle drive motors, BLUE horizontal
# = scraper bar, BLUE angled = the scraper's up-and-over (weir) path, PINK = water
# level line on the tank side. Run WINDOWED:
#   Godot --path . res://src/tests/shot_annotate_flotation.tscn -- [yaw] [pitch]

class Overlay extends Control:
	var cam : Camera3D
	var annots : Array = []
	func _draw() -> void:
		var f := ThemeDB.fallback_font
		for a in annots:
			if a.kind == "circle":
				if cam.is_position_behind(a.pos):
					continue
				draw_arc(cam.unproject_position(a.pos), a.r, 0.0, TAU, 48, a.color, 3.0, true)
			elif a.kind == "line":
				if cam.is_position_behind(a.a) or cam.is_position_behind(a.b):
					continue
				draw_line(cam.unproject_position(a.a), cam.unproject_position(a.b), a.color, a.get("w", 3.0))
		# legend (top-left)
		var legend := [
			[Color(1, 0.15, 0.15), "RED = paddle bearings (shaft -> tank side)"],
			[Color(1, 0.6, 0.05), "ORANGE = paddle drive motors"],
			[Color(0.2, 0.5, 1), "BLUE horizontal = scraper bar"],
			[Color(0.2, 0.5, 1), "BLUE angled = scraper up-and-over (weir)"],
			[Color(1, 0.4, 0.8), "PINK = water level"],
		]
		var ly := 22.0
		for row in legend:
			draw_string(f, Vector2(20.0, ly), row[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 18, row[0])
			ly += 24.0

func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var yaw : float = float(args[0]) if args.size() >= 1 else 42.0
	var pitch : float = float(args[1]) if args.size() >= 2 else 16.0
	var pid := "flotation_tank"
	# ── env / lighting / ground (same as shot_placeable) ─────────────────────
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
	var pm := PlaneMesh.new(); pm.size = Vector2(60.0, 60.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)
	# ── build ────────────────────────────────────────────────────────────────
	var node : Node = PlaceableCatalog.build_node(pid, false)
	add_child(node)
	(node as Node3D).global_position = Vector3.ZERO
	var item : Dictionary = PlaceableCatalog.get_item(pid)
	var sz : Vector3 = item.get("size", Vector3.ONE)
	# ── camera (same framing as shot_placeable) ──────────────────────────────
	var reach : float = maxf(sz.x, maxf(sz.y, sz.z))
	var dist : float = reach * 1.9 + 1.5
	var yr : float = deg_to_rad(yaw)
	var pr : float = deg_to_rad(pitch)
	var cam := Camera3D.new(); add_child(cam)
	cam.global_position = Vector3(sin(yr) * cos(pr) * dist, sz.y * 0.5 + sin(pr) * dist, cos(yr) * cos(pr) * dist)
	cam.look_at(Vector3(0.0, sz.y * 0.45, 0.0), Vector3.UP)
	cam.make_current()
	# ── annotation points, recomputed from _m_flotation geometry ─────────────
	var hz : float = sz.z * 0.5
	var flat_bot_y := 1.0
	var rim_y := 4.1
	var roll_y : float = rim_y - 0.35            # paddle shaft height
	var top_hx : float = sz.x * 0.46
	var surf_y : float = rim_y - 0.10            # water level
	var bearing_x : float = sz.x * 0.41          # +X shaft end (near the wall)
	var RED := Color(1, 0.15, 0.15)
	var ORANGE := Color(1, 0.6, 0.05)
	var BLUE := Color(0.2, 0.5, 1)
	var PINK := Color(1, 0.4, 0.8)
	var annots : Array = []
	# RED — paddle bearings (+X ends): inlet, 9 transport, outlet
	var paddle_z : Array = [-hz * 0.85]
	for i in 9:
		paddle_z.append(lerp(-hz * 0.65, hz * 0.65, float(i) / 8.0))
	paddle_z.append(hz * 0.85)
	for pz in paddle_z:
		annots.append({"kind": "circle", "color": RED, "pos": Vector3(bearing_x, roll_y, pz), "r": 13.0})
	# ORANGE — the 5 new drive motors (+X row)
	for k in 5:
		var mz : float = lerp(-hz * 0.5, hz * 0.5, float(k) / 4.0)
		var my : float = (rim_y + 0.95) - 0.10 - float(k) * 0.03
		annots.append({"kind": "circle", "color": ORANGE, "pos": Vector3(top_hx + 0.34, my, mz), "r": 20.0})
	# BLUE horizontal — scraper bar at +Z
	annots.append({"kind": "line", "color": BLUE,
		"a": Vector3(-sz.x * 0.37, rim_y + 0.5, hz * 0.97), "b": Vector3(sz.x * 0.37, rim_y + 0.5, hz * 0.97), "w": 4.0})
	# BLUE angled — scraper up-and-over (weir path)
	annots.append({"kind": "line", "color": BLUE,
		"a": Vector3(0.0, surf_y, hz * 0.9), "b": Vector3(0.0, rim_y + 0.62, hz * 1.12), "w": 4.0})
	# PINK — water level on the +X side wall
	annots.append({"kind": "line", "color": PINK,
		"a": Vector3(top_hx * 0.99, surf_y, -hz * 0.9), "b": Vector3(top_hx * 0.99, surf_y, hz * 0.9), "w": 2.0})
	# ── overlay ──────────────────────────────────────────────────────────────
	var cl := CanvasLayer.new(); add_child(cl)
	var ov := Overlay.new()
	ov.cam = cam
	ov.annots = annots
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	cl.add_child(ov)
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.45).timeout
	ov.queue_redraw()
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var outp := "user://shot_flotation_annotated.png"
	img.save_png(outp)
	preload("res://src/tests/shot_common.gd").check_image_content(img, outp)
	print("[SHOT] saved ", ProjectSettings.globalize_path(outp))
	get_tree().quit(0)
