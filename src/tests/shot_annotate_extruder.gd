extends Node3D
# =============================================================================
# Photo-audit helper (operator request 2026-07-20): render the CURRENT extruder
# model and draw a labelled box around each component, so the operator can say
# "that one is in the wrong place" instead of guessing what he's looking at.
#
# The boxes are NOT eyeballed onto the image. Each part's centre + extents are
# taken from the SAME formulas _m_extruder_unit uses (PlaceableCatalog.gd
# ~10127-10450), then the 8 corners are projected through the render camera with
# unproject_position(). If a part moves in the builder, its box moves with it.
#
#   Godot --path . res://src/tests/shot_annotate_extruder.tscn -- [id] [yaw] [pitch]
#   default id = extruder_3c (the only line with the melt pump fitted)
# =============================================================================

class Overlay extends Control:
	var cam : Camera3D
	var parts : Array = []            # {name, centre, half, color}
	var subtitle : String = ""

	func _draw() -> void:
		var f := ThemeDB.fallback_font
		var placed : Array[Rect2] = []
		for part in parts:
			var r : Rect2 = _screen_rect(part["centre"], part["half"])
			if r.size.x <= 0.0:
				continue
			var col : Color = part["color"]
			draw_rect(r, col, false, 2.5)
			# Label just above the box, nudged down if it would collide with one
			# already drawn (the parts overlap a lot in a side view).
			var txt : String = part["name"]
			var tw : float = f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
			var lp := Vector2(r.position.x, r.position.y - 7.0)
			var guard := 0
			while guard < 40:
				var lr := Rect2(lp - Vector2(3, 15), Vector2(tw + 6, 19))
				var clash := false
				for q in placed:
					if lr.intersects(q):
						clash = true
						break
				if not clash:
					placed.append(lr)
					break
				lp.y -= 19.0
				guard += 1
			# Leader line from the label to the box when it drifted upward.
			if lp.y < r.position.y - 12.0:
				draw_line(Vector2(lp.x + 4.0, lp.y + 3.0),
					Vector2(r.position.x + 4.0, r.position.y), col, 1.0)
			draw_string(f, lp, txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, col)
		if subtitle != "":
			draw_string(f, Vector2(18.0, 26.0), subtitle,
				HORIZONTAL_ALIGNMENT_LEFT, -1, 19, Color(1, 1, 1))

	## 2D bounding rect of a 3D box, from its 8 projected corners.
	func _screen_rect(centre: Vector3, half: Vector3) -> Rect2:
		var mn := Vector2(INF, INF)
		var mx := Vector2(-INF, -INF)
		for i in 8:
			var c := centre + Vector3(
				half.x * (1.0 if (i & 1) else -1.0),
				half.y * (1.0 if (i & 2) else -1.0),
				half.z * (1.0 if (i & 4) else -1.0))
			if cam.is_position_behind(c):
				return Rect2()
			var s := cam.unproject_position(c)
			mn.x = minf(mn.x, s.x); mn.y = minf(mn.y, s.y)
			mx.x = maxf(mx.x, s.x); mx.y = maxf(mx.y, s.y)
		return Rect2(mn, mx - mn)

const C_MOTOR  := Color(1.00, 0.35, 0.25)
const C_PCU    := Color(1.00, 0.75, 0.10)
const C_FILTER := Color(0.30, 0.85, 1.00)
const C_VAC    := Color(0.55, 1.00, 0.45)
const C_DIE    := Color(1.00, 0.45, 0.90)
const C_PELLET := Color(0.70, 0.65, 1.00)
const C_HMI    := Color(1.00, 1.00, 1.00)

func _ready() -> void:
	var args : PackedStringArray = OS.get_cmdline_user_args()
	var pid : String = String(args[0]) if args.size() >= 1 else "extruder_3c"
	var yaw : float = float(args[1]) if args.size() >= 2 else 90.0
	var pitch : float = float(args[2]) if args.size() >= 3 else 6.0

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.60, 0.65, 0.71)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.62, 0.64, 0.67)
	env.ambient_light_energy = 1.15
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(-38.0), 0.0)
	sun.light_energy = 1.25
	add_child(sun)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(80.0, 80.0)
	ground.mesh = pm
	var gmat := StandardMaterial3D.new(); gmat.albedo_color = Color(0.34, 0.35, 0.36)
	ground.material_override = gmat
	add_child(ground)

	var node : Node = PlaceableCatalog.build_node(pid, false)
	if node == null:
		print("[ANNOT] ERROR: no placeable '", pid, "'")
		get_tree().quit(1); return
	add_child(node)
	(node as Node3D).global_position = Vector3.ZERO

	var item : Dictionary = PlaceableCatalog.get_item(pid)
	var size : Vector3 = item.get("size", Vector3.ONE)
	var cam := Camera3D.new(); add_child(cam)
	var reach : float = maxf(size.x, maxf(size.y, size.z))
	# Tight enough that the machine fills the frame — the labels need the room.
	var dist : float = reach * 0.92 + 1.0
	var yr := deg_to_rad(yaw)
	var pr := deg_to_rad(pitch)
	cam.global_position = Vector3(
		sin(yr) * cos(pr) * dist,
		size.y * 0.5 + sin(pr) * dist,
		cos(yr) * cos(pr) * dist)
	cam.look_at(Vector3(0.0, size.y * 0.42, 0.0), Vector3.UP)
	cam.make_current()

	var ov := Overlay.new()
	ov.cam = cam
	ov.parts = _parts_for(size, pid)
	ov.subtitle = "%s — CURRENT model. Boxes come from the builder's own formulas." % pid
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ov)

	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	var img := get_viewport().get_texture().get_image()
	var outp : String = "user://annot_%s.png" % pid
	img.save_png(outp)
	print("[ANNOT] saved ", ProjectSettings.globalize_path(outp))
	get_tree().quit(0)

## Mirrors the locals of _m_extruder_unit so every box tracks the real geometry.
func _parts_for(size: Vector3, pid: String) -> Array:
	var barrel_cy : float = size.y * 0.31
	var hood_r : float = size.x * 0.33
	var hood_cy : float = barrel_cy * 0.95
	var hood_top : float = hood_cy + hood_r

	# SECTION 1 — PCU on its portal + the intake slider.
	var tw_z : float = -size.z * 0.20
	var drum_r : float = size.x * 0.34
	var tower_leg_h : float = hood_top + 0.35
	var drum_base : float = tower_leg_h + 0.12
	var drum_h : float = size.y * 0.42
	var slider_bot : float = hood_cy + hood_r * 0.55
	var slider_w : float = drum_r * 0.62

	# SECTION 2 — gearbox, screw-drive motor, main HMI.
	var gb_z : float = -size.z * 0.27
	var hmi_x : float = size.x * 0.46
	var sc_y : float = barrel_cy * 1.15

	# SECTION 4/5b/5/6/7.
	var c2_z : float = size.z * 0.02
	var kf_z : float = size.z * 0.22
	var kf_house_w : float = size.x * 0.46
	var kf_house_d : float = size.z * 0.08
	var kf_low_y : float = barrel_cy * 1.04
	var kf_up_y : float = barrel_cy * 1.62
	var kf_bot : float = barrel_cy * 0.82
	var kf_top : float = kf_up_y + barrel_cy * 0.30
	var pz : float = size.z * 0.42
	var cab_w : float = size.x * 0.88
	var cab_base : float = size.y * 0.04
	var cab_h : float = size.y * 0.56
	var cab_len : float = size.z * 0.16
	var pf_z : float = pz + cab_len * 0.5
	var die_r : float = size.x * 0.18

	var out : Array = [
		{"name": "SCREW-DRIVE MOTOR (turns the screw)", "color": C_MOTOR,
		 "centre": Vector3(0.0, barrel_cy, -size.z * 0.34),
		 "half": Vector3(size.x * 0.20, size.x * 0.20, size.z * 0.055)},
		{"name": "GEARBOX", "color": C_MOTOR,
		 "centre": Vector3(0.0, barrel_cy * 0.7, gb_z),
		 "half": Vector3(size.x * 0.30, barrel_cy * 0.525, size.z * 0.045)},
		{"name": "MAIN HMI (on the extruder)", "color": C_HMI,
		 "centre": Vector3(hmi_x, sc_y, gb_z + size.z * 0.05),
		 "half": Vector3(0.10, sc_y * 0.5, 0.16)},
		{"name": "PCU / cutter-compactor drum", "color": C_PCU,
		 "centre": Vector3(0.0, drum_base + drum_h * 0.5, tw_z),
		 "half": Vector3(drum_r, drum_h * 0.5, drum_r)},
		{"name": "PCU portal frame (straddles the barrel)", "color": C_PCU,
		 "centre": Vector3(0.0, tower_leg_h * 0.5, tw_z),
		 "half": Vector3(size.x * 0.42 + 0.07, tower_leg_h * 0.5, drum_r * 0.80)},
		{"name": "INTAKE SLIDER (intrek/opzetschuif) — NEW", "color": C_PCU,
		 "centre": Vector3(0.0, (slider_bot + drum_base) * 0.5, tw_z),
		 "half": Vector3(slider_w * 0.65, maxf(drum_base - slider_bot, 0.15) * 0.5, slider_w * 0.65)},
		{"name": "melt take-off stub -> STANDALONE laser filter (separate model)", "color": C_FILTER,
		 "centre": Vector3(0.0, hood_top + size.x * 0.10, c2_z),
		 "half": Vector3(size.x * 0.12, size.x * 0.16, size.x * 0.12)},
		{"name": "VACUUM DEGAS 1", "color": C_VAC,
		 "centre": Vector3(0.0, hood_top + size.x * 0.14, size.z * 0.06),
		 "half": Vector3(size.x * 0.12, size.x * 0.26, size.x * 0.12)},
		{"name": "VACUUM DEGAS 2", "color": C_VAC,
		 "centre": Vector3(0.0, hood_top + size.x * 0.14, size.z * 0.13),
		 "half": Vector3(size.x * 0.12, size.x * 0.26, size.x * 0.12)},
		{"name": "HEAD FILTER / kopfilter (2 piston stations)", "color": C_FILTER,
		 "centre": Vector3(0.0, (kf_bot + kf_top) * 0.5, kf_z),
		 "half": Vector3(kf_house_w * 0.5, (kf_top - kf_bot) * 0.5, kf_house_d * 0.5)},
		{"name": "head-filter mini control panel (INVENTED - no doc)", "color": C_HMI,
		 "centre": Vector3(kf_house_w * 0.5 + 0.02, kf_low_y - barrel_cy * 0.05, kf_z - kf_house_d * 0.3),
		 "half": Vector3(0.09, size.x * 0.09, 0.09)},
		{"name": "PELLETIZER cabinet", "color": C_PELLET,
		 "centre": Vector3(0.0, cab_base + cab_h * 0.5, pz),
		 "half": Vector3(cab_w * 0.5, cab_h * 0.5, cab_len * 0.5)},
		{"name": "DIE plate + hot-face cutter", "color": C_DIE,
		 "centre": Vector3(0.0, barrel_cy, pf_z + 0.07),
		 "half": Vector3(die_r, die_r, 0.10)},
		{"name": "pelletizer HMI pedestal", "color": C_HMI,
		 "centre": Vector3(-cab_w * 0.72, barrel_cy * 0.95, pf_z - 0.10),
		 "half": Vector3(0.22, barrel_cy * 0.95, 0.16)},
	]
	if pid == "extruder_3c":
		out.append({"name": "MELT PUMP (3C only)", "color": C_FILTER,
			"centre": Vector3(0.0, hood_cy, size.z * 0.30),
			"half": Vector3(size.x * 0.15, barrel_cy * 0.45, size.z * 0.035)})
	# kf_up_y is referenced above via kf_top; keep the local alive for clarity.
	var _unused_up := kf_up_y
	return out
