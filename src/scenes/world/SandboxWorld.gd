extends Node3D

## #158 — Sandbox / showcase world. Boots completely independent of MainWorld:
## flat grass, sun + sky, player at the centre, all 5 line macros pre-spawned
## in a row with big floating labels above each. F11 = teleport to next macro
## for fast walkthroughs.
##
## Layout (top-down, looking from +Y down):
##
##     +X (east) →
##
##   [Station 0]  [Station 1]  [Station 2]  [Station 3]  [Station 4]
##    Line 1       Line 3A      Line 3B      Intake 3A/3B  Sort line
##
##   each station is ~80 m apart along +X; macros march along -Z (north) from
##   their anchor, so the operator stands at the anchor reading the sign and
##   sees the macro stretching away in front of them.

const BM = preload("res://src/build/BuildMode.gd")
const PlaceableCatalog = preload("res://src/build/PlaceableCatalog.gd")

# Station anchor positions and the macros they showcase.
const STATION_SPACING_M : float = 80.0
const SIGN_HEIGHT_M     : float = 6.0
const LINE_GAP_M        : float = 0.6   # match BuildMode.LINE_GAP_M

# Each station: (display_name, macro_const_name_in_BuildMode)
var _stations : Array = [
	{"name": "Line 1 (full)",           "seq": BM.LINE_1_SEQ},
	{"name": "Line 3A (full)",          "seq": BM.LINE_3A_SEQ},
	{"name": "Line 3B (full)",          "seq": BM.LINE_3B_SEQ},
	{"name": "3A/3B intake (front-end)","seq": BM.INTAKE_3A3B_SEQ},
	{"name": "Sort line (2× trilzeef)", "seq": BM.LINE_SORT_SEQ},
]
var _station_anchors : Array = []        # Array[Vector3]
var _current_station_idx : int = 0

func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_player()
	_build_hud()
	_build_stations()
	_register_walkthrough_keys()

# ── Environment: sun + sky + ambient ──────────────────────────────────────────
func _build_environment() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.4
	sun.shadow_enabled = true
	add_child(sun)
	var env_node := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.42, 0.62, 0.88)
	sky_mat.sky_horizon_color = Color(0.78, 0.86, 0.92)
	sky_mat.ground_horizon_color = Color(0.55, 0.60, 0.55)
	sky_mat.ground_bottom_color = Color(0.30, 0.35, 0.28)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env_node.environment = env
	add_child(env_node)

# ── Big flat grass plane + static collision ───────────────────────────────────
func _build_ground() -> void:
	# Visual plane.
	var mi := MeshInstance3D.new()
	mi.name = "Grass"
	var pm := PlaneMesh.new()
	pm.size = Vector2(800.0, 800.0)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.46, 0.22)
	mat.roughness = 0.96
	mi.material_override = mat
	add_child(mi)
	# Static collision body.
	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var sh := BoxShape3D.new()
	sh.size = Vector3(800.0, 0.2, 800.0)
	col.shape = sh
	col.position = Vector3(0.0, -0.1, 0.0)
	body.add_child(col)
	add_child(body)

# ── Player (same wiring as GauntletWorld / MainWorld) ────────────────────────
var _player : CharacterBody3D = null

func _build_player() -> void:
	var script := load("res://src/scenes/player/PlayerController.gd")
	if script == null:
		push_error("[Sandbox] PlayerController.gd missing")
		return
	var p : CharacterBody3D = script.new()
	p.name = "Player"
	var head := Node3D.new()
	head.name = "Head"
	head.position = Vector3(0.0, 0.7, 0.0)
	p.add_child(head)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	cam.current = true
	head.add_child(cam)
	var col := CollisionShape3D.new()
	col.name = "Collision"
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape = cap
	p.add_child(col)
	add_child(p)
	p.global_position = Vector3(0.0, 1.0, 12.0)
	_player = p

# ── HUD: bottom-centre banner showing the current station ────────────────────
var _hud_label : Label = null

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.name = "SandboxHUD"
	add_child(cl)
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_CENTER_TOP)
	bg.offset_left = -340
	bg.offset_right = 340
	bg.offset_top = 20
	bg.offset_bottom = 80
	cl.add_child(bg)
	_hud_label = Label.new()
	_hud_label.add_theme_font_size_override("font_size", 24)
	_hud_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hud_label.text = "Sandbox — F8: prev station · F9: next station · F12: unstuck"
	bg.add_child(_hud_label)

# ── Stations: spawn each macro at its anchor + a giant Label3D sign ──────────
func _build_stations() -> void:
	var x : float = -float(_stations.size() - 1) * 0.5 * STATION_SPACING_M
	for i in _stations.size():
		var station : Dictionary = _stations[i]
		var anchor := Vector3(x + float(i) * STATION_SPACING_M, 0.0, 0.0)
		_station_anchors.append(anchor)
		_spawn_macro_at(station["seq"], anchor, 0.0)
		_spawn_station_sign(anchor + Vector3(0.0, 0.0, 3.0),
			"#%d — %s" % [i + 1, String(station["name"])])

## Iterate a macro SEQ (same format as BuildMode.LINE_*_SEQ) and place each
## entry. Forward = -Z (north). Branches (entries with x ≠ 0) are placed at
## the current main_z's lateral offset; they don't advance main_z.
func _spawn_macro_at(seq : Array, anchor : Vector3, rot_y : float) -> void:
	var fwd := Vector3(-sin(rot_y), 0.0, -cos(rot_y))
	var rgt := Vector3(cos(rot_y), 0.0, -sin(rot_y))
	var main_z : float = 0.0
	for entry in seq:
		var id : String = String(entry["id"])
		var item := PlaceableCatalog.get_item(id)
		if item.is_empty():
			push_warning("[Sandbox] catalog missing id '%s'" % id)
			continue
		var size : Vector3 = item["size"]
		var off_x : float = float(entry.get("x", 0.0))
		var off_z : float = float(entry.get("z", 0.0))
		var pos : Vector3
		if off_x == 0.0 and off_z == 0.0:
			# Main-line entry — sits at main_z and advances main_z by its depth + gap.
			pos = anchor + fwd * (main_z + size.z * 0.5)
			main_z += size.z + LINE_GAP_M
		else:
			# Branch entry — relative to the current main_z position.
			pos = anchor + fwd * main_z + fwd * off_z + rgt * off_x
		var node : Node3D = PlaceableCatalog.build_node(id, false, false)
		if node == null:
			continue
		add_child(node)
		node.global_position = pos
		node.rotation.y = rot_y

func _spawn_station_sign(at : Vector3, text : String) -> void:
	var holder := Node3D.new()
	holder.name = "Sign_" + text.substr(0, 8)
	holder.position = at
	add_child(holder)
	# Steel post.
	var post := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.06; cm.bottom_radius = 0.06; cm.height = SIGN_HEIGHT_M
	post.mesh = cm
	post.position = Vector3(0.0, SIGN_HEIGHT_M * 0.5, 0.0)
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.30, 0.30, 0.32)
	post_mat.metallic = 0.6
	post.material_override = post_mat
	holder.add_child(post)
	# Yellow billboard plate.
	var plate := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(8.0, 2.4)
	plate.mesh = qm
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.94, 0.78, 0.14)
	pm.roughness = 0.6
	plate.material_override = pm
	plate.position = Vector3(0.0, SIGN_HEIGHT_M + 1.2, 0.0)
	holder.add_child(plate)
	# Label3D in front of the plate.
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 96
	lbl.outline_size = 14
	lbl.modulate = Color(0.10, 0.10, 0.15)
	lbl.position = Vector3(0.0, SIGN_HEIGHT_M + 1.2, 0.05)
	lbl.pixel_size = 0.012
	lbl.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	holder.add_child(lbl)

# ── Walkthrough keys ─────────────────────────────────────────────────────────
func _register_walkthrough_keys() -> void:
	# F8 = previous station, F9 = next station. Lazy-registered so the saved
	# InputMap doesn't need updating for this sandbox-only scene.
	if not InputMap.has_action("sandbox_prev"):
		InputMap.add_action("sandbox_prev")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_F8
		InputMap.action_add_event("sandbox_prev", k)
	if not InputMap.has_action("sandbox_next"):
		InputMap.add_action("sandbox_next")
		var k2 := InputEventKey.new()
		k2.physical_keycode = KEY_F9
		InputMap.action_add_event("sandbox_next", k2)

func _input(event : InputEvent) -> void:
	if event.is_action_pressed("sandbox_next"):
		_jump_to_station((_current_station_idx + 1) % _station_anchors.size())
	elif event.is_action_pressed("sandbox_prev"):
		_jump_to_station((_current_station_idx - 1 + _station_anchors.size()) % _station_anchors.size())

func _jump_to_station(idx : int) -> void:
	_current_station_idx = idx
	if _player == null or idx < 0 or idx >= _station_anchors.size():
		return
	var a : Vector3 = _station_anchors[idx]
	_player.global_position = a + Vector3(0.0, 1.0, 12.0)
	_player.rotation.y = PI    # face -Z (toward the macro and its sign)
	if _hud_label:
		_hud_label.text = "Station %d/%d — %s   ·   F8 prev · F9 next · F12 unstuck" \
			% [idx + 1, _stations.size(), String(_stations[idx]["name"])]
