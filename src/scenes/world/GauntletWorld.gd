extends Node3D
##
## TEST GAUNTLET. A self-contained scene that lays the backlog out in a
## walkable line — operator spawns at the west end, walks east, verifies each
## station, moves on. Stations are defined in STATIONS and auto-populated by
## per-task builder methods (`_st_NN`). Adding a new task = add a row to the
## list + write `_st_NN()` — no scene-file edits.
##
## Spawned with Player + flashlight + bay lights so it's lit + walkable; the
## crew + LineFlow + bale yards are NOT spawned (this is for visual / quick
## interaction verification, NOT a live shift).

const STATION_SPACING_M : float = 14.0
const STATION_DEPTH_M   : float = 12.0   # +Z space behind each sign for props
const PLATFORM_WIDTH_M  : float = 16.0
const FLOOR_THICKNESS_M : float = 0.5
const SIGN_HEIGHT_M     : float = 3.2

## task_id, title, builder method name.
##
## DONE this gauntlet build is marked completed in the task list — the station
## still gets built so the operator can verify visually. PENDING gets a
## placeholder cube + sign in muted grey.
const STATIONS : Array[Dictionary] = [
	{"id":  95, "title": "Vehicle glass cabs",                       "fn": "_st_95",  "status": "pending"},
	{"id":  98, "title": "Silo lump bin model",                      "fn": "_st_98",  "status": "done"},
	{"id":  99, "title": "Mech_dryer pair → blower → cyclone",       "fn": "_st_99",  "status": "pending"},
	{"id": 100, "title": "Flotation → weir-scoop dewater_screw",     "fn": "_st_100", "status": "pending"},
	{"id": 101, "title": "Horizontal extraction screw on silo",      "fn": "_st_101", "status": "done"},
	{"id": 116, "title": "Door furniture (roller / pedestrian)",     "fn": "_st_116", "status": "pending"},
	{"id": 117, "title": "Bale yard close-LOD shading",              "fn": "_st_117", "status": "pending"},
	{"id": 122, "title": "Door type auto-classify by W/H/BY",        "fn": "_st_122", "status": "done"},
	{"id": 124, "title": "Crew assignment UI",                       "fn": "_st_124", "status": "pending"},
	{"id": 125, "title": "Yard bale labels (proximity MM)",          "fn": "_st_125", "status": "pending"},
	{"id": 126, "title": "Humanoid proportion review",               "fn": "_st_126", "status": "done"},
	{"id": 127, "title": "Bale yard spawn deferred (frame-batch)",   "fn": "_st_127", "status": "done"},
	{"id": 128, "title": "Manager Peter indoor spawn",               "fn": "_st_128", "status": "done"},
	{"id": 134, "title": "Crew arrival cars + Yasin shotgun",        "fn": "_st_134", "status": "pending"},
	{"id": 135, "title": "Player spawns in their car on the road",   "fn": "_st_135", "status": "pending"},
	{"id": 139, "title": "Pack-up cascade (VSSs FULL ramp)",         "fn": "_st_139", "status": "pending"},
	{"id": 141, "title": "Conveyor angle + head/tail overlap",       "fn": "_st_141", "status": "pending"},
]

# Cached anchors so per-station builders can attach to one parent each.
var _stations_root : Node3D = null

func _ready() -> void:
	_build_floor()
	_build_sky_light()
	_stations_root = Node3D.new()
	_stations_root.name = "Stations"
	add_child(_stations_root)
	for i in STATIONS.size():
		var entry : Dictionary = STATIONS[i]
		var x : float = float(i) * STATION_SPACING_M
		_build_station_sign(Vector3(x, 0.0, 0.0), entry)
		if has_method(String(entry["fn"])):
			call(entry["fn"], Vector3(x, 0.0, 4.0))
		else:
			_build_placeholder(Vector3(x, 0.0, 4.0), String(entry["status"]))
	_build_player()
	_spawn_hud()
	# Reset cursor so the player can walk straight from spawn.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	print("[Gauntlet] %d stations laid out over %.0f m" % [
		STATIONS.size(), float(STATIONS.size()) * STATION_SPACING_M])

## Spawn the same HUD MainWorld uses so ESC opens the pause menu (Resume /
## Save & Quit). The HUD's shift_clock + crew_manager refs stay null — the
## pause overlay only needs the input handler + Resume / Quit buttons to
## work, and those don't depend on a live shift.
func _spawn_hud() -> void:
	var hud_scene := load("res://src/scenes/hud/HUD.tscn") as PackedScene
	if hud_scene == null:
		push_error("[Gauntlet] HUD.tscn not found — ESC menu unavailable")
		return
	var hud = hud_scene.instantiate()
	add_child(hud)

# ─── World bones ──────────────────────────────────────────────────────────────

func _build_floor() -> void:
	var length : float = float(STATIONS.size()) * STATION_SPACING_M + 20.0
	var floor_body := StaticBody3D.new()
	floor_body.name = "GauntletFloor"
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, FLOOR_THICKNESS_M, PLATFORM_WIDTH_M)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.30, 0.32)
	mat.roughness = 0.88
	mesh.material_override = mat
	mesh.position = Vector3(length * 0.5 - 10.0, -FLOOR_THICKNESS_M * 0.5, 0.0)
	floor_body.add_child(mesh)
	var col := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	bx.size = bm.size
	col.shape = bx
	col.position = mesh.position
	floor_body.add_child(col)

func _build_sky_light() -> void:
	# One world-light (sun) so everything is lit without per-station bay lights.
	var dl := DirectionalLight3D.new()
	dl.name = "Sun"
	dl.rotation_degrees = Vector3(-45.0, 30.0, 0.0)
	dl.light_energy = 1.2
	add_child(dl)
	# A small ambient lift via an env-config WorldEnvironment.
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.50, 0.62, 0.74)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.45, 0.50, 0.58)
	environment.ambient_light_energy = 0.45
	env.environment = environment
	add_child(env)

func _build_player() -> void:
	var script := load("res://src/scenes/player/PlayerController.gd")
	if script == null:
		push_error("[Gauntlet] PlayerController.gd not found")
		return
	var p : CharacterBody3D = script.new()
	p.name = "Player"
	# Children FIRST so PlayerController's @onready $Head and $Head/Camera3D
	# resolve when `p` enters the tree. Adding `p` bare crashed _build_flashlight
	# because camera_3d was still null at _ready().
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
	# Spawn west of the first station, centred on the platform Z axis, facing +X
	# so the operator sees the first sign immediately. PlayerController's yaw
	# is owned by the body's rotation.y (camera rolls under it).
	p.global_position = Vector3(-10.0, 1.0, 0.0)
	p.rotation.y = -PI * 0.5

func _build_station_sign(pos: Vector3, entry: Dictionary) -> void:
	# The board's long axis runs along Z (perpendicular to the walking direction)
	# so the operator sees the full board face as they walk past. Label3D uses
	# BILLBOARD_FIXED_Y so the text always faces the camera horizontally — no
	# need to guess the right Y rotation for which side they'll approach from.
	var holder := Node3D.new()
	holder.name = "Sign_%d" % int(entry["id"])
	holder.position = pos
	_stations_root.add_child(holder)
	var board_w : float = 4.0
	var board_h : float = 1.2
	# Two side posts on the long edges of the board — out of the label area.
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = Color(0.25, 0.27, 0.30)
	post_mat.metallic = 0.5
	post_mat.roughness = 0.35
	for sz in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(0.12, SIGN_HEIGHT_M, 0.12)
		post.mesh = pm
		post.material_override = post_mat
		# Posts at ±Z of the board (long edges); centred on X = 0 so the operator
		# walking +X sees them only at the periphery, not bisecting the text.
		post.position = Vector3(0.0, SIGN_HEIGHT_M * 0.5, sz * (board_w * 0.5 - 0.15))
		holder.add_child(post)
	# Board: thin slab whose long axis runs along Z. Operator walking +X looks
	# at the board's wide face (the YZ plane), reading the whole title at once.
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, board_h, board_w)
	board.mesh = bm
	var bm_mat := StandardMaterial3D.new()
	var status : String = String(entry["status"])
	if status == "done":
		bm_mat.albedo_color = Color(0.18, 0.38, 0.22)   # forest green
	else:
		bm_mat.albedo_color = Color(0.46, 0.42, 0.16)   # caution-tape yellow
	bm_mat.roughness = 0.7
	board.material_override = bm_mat
	board.position = Vector3(0.0, SIGN_HEIGHT_M - 0.4, 0.0)
	holder.add_child(board)
	# Billboarded label — always faces the camera, so the operator reads it
	# whether they're approaching, passing, or looking back.
	var label := Label3D.new()
	label.text = "#%d  %s\n[%s]" % [int(entry["id"]), String(entry["title"]), status.to_upper()]
	label.font_size = 56
	label.outline_size = 10
	label.modulate = Color(1.0, 1.0, 1.0)
	label.position = Vector3(0.0, SIGN_HEIGHT_M - 0.4, 0.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	label.pixel_size = 0.006
	label.no_depth_test = true   # draw on top of the board so it can't get clipped
	label.fixed_size = false
	holder.add_child(label)

func _build_placeholder(pos: Vector3, status: String) -> void:
	# Striped barber-pole — tall and high-contrast so it's recognisable as
	# "nothing built here yet" from across the gauntlet. Plain cubes vanished
	# against the dark floor. Stripes change colour by status.
	var holder := Node3D.new()
	holder.position = pos
	_stations_root.add_child(holder)
	var pole_h : float = 2.4
	var stripe_h : float = 0.30
	var n_stripes : int = int(round(pole_h / stripe_h))
	var col_a : Color
	var col_b : Color
	if status == "done":
		col_a = Color(0.18, 0.55, 0.30)
		col_b = Color(0.95, 0.95, 0.95)
	else:
		col_a = Color(0.92, 0.20, 0.18)   # caution red
		col_b = Color(0.96, 0.92, 0.20)   # caution yellow
	for i in n_stripes:
		var seg := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.30, stripe_h, 0.30)
		seg.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col_a if (i % 2 == 0) else col_b
		mat.roughness = 0.75
		seg.material_override = mat
		seg.position = Vector3(0.0, stripe_h * (float(i) + 0.5), 0.0)
		holder.add_child(seg)

# ─── Per-task station builders ────────────────────────────────────────────────
# Convention: receive `anchor` = position behind the sign where the prop goes.
# Use PlaceableCatalog.build_node() wherever possible so the gauntlet exercises
# the same code path the build menu uses.

func _build_placed(id: String, anchor: Vector3, yaw_deg: float = 0.0) -> Node3D:
	var n : Node3D = PlaceableCatalog.build_node(id, false, false)
	if n == null:
		return null
	add_child(n)
	n.global_position = anchor
	n.rotation.y = deg_to_rad(yaw_deg)
	return n

# #95 — vehicle glass: nothing implemented yet, placeholder.
func _st_95(anchor: Vector3) -> void:
	_build_placeholder(anchor, "pending")

# #98 — extruder_silo + lump_cart_spot floor marking + lump_cart parked on it.
# This matches the line macro: every extruder has a yellow marking where the
# cart must be at shift start (extruder operator's check). Operator confirmed
# the cart belongs at the marking, NOT integrated into the silo.
func _st_98(anchor: Vector3) -> void:
	_build_placed("extruder_silo", anchor)
	var spot : Node3D = PlaceableCatalog.build_node("lump_cart_spot", false, false)
	if spot:
		add_child(spot)
		spot.global_position = anchor + Vector3(2.8, 0.0, 0.0)
	var cart : Node3D = PlaceableCatalog.build_node("lump_cart", false, false)
	if cart:
		add_child(cart)
		cart.global_position = anchor + Vector3(2.8, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "extruder_silo (lump bin REMOVED)    lump_cart_spot (yellow marking)    lump_cart (pushable)"
	lbl.font_size = 24; lbl.outline_size = 6
	lbl.position = anchor + Vector3(1.4, 3.6, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #99 — mech_dryer pair → header → blower → cyclone. Flow: dryer drum tops →
# common header → blower INLET EYE (+X side) → blower TOP OUTLET → over to the
# cyclone's TANGENTIAL INLET (+X side, high). All connection-point Y values
# come from the actual machine model code (dryer drum top ≈ 2.72 m, blower
# inlet eye y = size.y * 0.5, outlet box y = size.y * 0.85, cyclone tangential
# inlet at body_cy + body_h * 0.15 ≈ 3.78 m), not guessed.
func _st_99(anchor: Vector3) -> void:
	var d_off    : float = 3.0               # half-spacing between dryers (drum dia + clearance)
	var blo_x    : float = 4.5               # blower offset +X from chain centreline
	var blo_z    : float = 6.0               # blower z downstream of dryer row
	var cy_x     : float = 0.0
	var cy_z     : float = 9.5               # cyclone past the blower
	var pipe_r   : float = 0.10              # 20 cm dia — typical plant exhaust duct
	# Dryer model: size.x = 2.4, rad = 0.42*size.x = 1.008, drum_cy = clear+rad = 1.708,
	# so drum TOP sits at drum_cy + rad ≈ 2.72 m above the dryer's base. Connect
	# the exhaust stub there.
	var dryer_top_y : float = 2.72
	# Header rides 30 cm above the drum tops so it doesn't clip the drums.
	var header_y    : float = dryer_top_y + 0.5
	var d1 : Node3D = PlaceableCatalog.build_node("mech_dryer", false, false)
	if d1: add_child(d1); d1.global_position = anchor + Vector3(-d_off, 0.0, 0.0)
	var d2 : Node3D = PlaceableCatalog.build_node("mech_dryer", false, false)
	if d2: add_child(d2); d2.global_position = anchor + Vector3( d_off, 0.0, 0.0)
	var blo : Node3D = PlaceableCatalog.build_node("blower", false, false)
	if blo: add_child(blo); blo.global_position = anchor + Vector3(blo_x, 0.0, blo_z)
	var cy : Node3D = PlaceableCatalog.build_node("cyclone", false, false)
	if cy: add_child(cy); cy.global_position = anchor + Vector3(cy_x, 0.0, cy_z)
	# ── 1) Exhaust stubs off each dryer drum top to header height ────────────
	_build_steel_pipe(anchor + Vector3(-d_off, dryer_top_y, 0.0),
		anchor + Vector3(-d_off, header_y,    0.0), pipe_r)
	_build_steel_pipe(anchor + Vector3( d_off, dryer_top_y, 0.0),
		anchor + Vector3( d_off, header_y,    0.0), pipe_r)
	# ── 2) Horizontal header tying both stubs together ──────────────────────
	_build_steel_pipe(anchor + Vector3(-d_off, header_y, 0.0),
		anchor + Vector3( d_off, header_y, 0.0), pipe_r)
	# Brackets to hang the header from the ceiling line (gauntlet has no roof —
	# just a short vertical hanger above the header centre so it doesn't float).
	_build_steel_pipe(anchor + Vector3(0.0, header_y, 0.0),
		anchor + Vector3(0.0, header_y + 0.7, 0.0), pipe_r * 0.5)
	# ── 3) Header centre runs +Z + +X toward the blower's inlet eye. Blower
	#       inlet is on +X face at y = size.y * 0.5 = 0.6 (default blower size).
	#       Centre of the inlet eye in world coords: (blo_x + blower_x/2, 0.6,
	#       blo_z) — defaulting to (4.5 + 0.5, 0.6, 6.0) = (5.0, 0.6, 6.0).
	var blower_inlet := anchor + Vector3(blo_x + 0.5, 0.6, blo_z)
	# Route header → above blower → drop down to inlet height → slide into eye.
	_build_steel_pipe(anchor + Vector3(0.0, header_y, 0.0),
		anchor + Vector3(0.0, header_y, blo_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(0.0, header_y, blo_z),
		anchor + Vector3(blo_x + 0.5, header_y, blo_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(blo_x + 0.5, header_y, blo_z),
		blower_inlet, pipe_r)
	# ── 4) Blower TOP outlet (y = size.y * 0.85 = 1.02) up + over + down to
	#       the cyclone's tangential inlet on the cyclone's +X side at y ≈ 3.78.
	#       Cyclone is at (cy_x, 0, cy_z); inlet world coords:
	#       (cy_x + size.x * 0.36 = +0.58, 3.78, cy_z) with default cyclone size.
	var blower_outlet := anchor + Vector3(blo_x, 1.02, blo_z)
	var cyclone_inlet := anchor + Vector3(cy_x + 0.58, 3.78, cy_z)
	var run_y         : float = 4.30
	_build_steel_pipe(blower_outlet,
		anchor + Vector3(blo_x, run_y, blo_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(blo_x, run_y, blo_z),
		anchor + Vector3(cy_x + 0.58, run_y, blo_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(cy_x + 0.58, run_y, blo_z),
		anchor + Vector3(cy_x + 0.58, run_y, cy_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(cy_x + 0.58, run_y, cy_z),
		cyclone_inlet, pipe_r)
	# ── 5) Flange-style joint pucks where each pipe meets a machine —
	#       cheap visual cue that the duct is actually bolted in, not floating.
	_build_pipe_flange(anchor + Vector3(-d_off, dryer_top_y, 0.0), pipe_r)
	_build_pipe_flange(anchor + Vector3( d_off, dryer_top_y, 0.0), pipe_r)
	_build_pipe_flange(blower_inlet, pipe_r)
	_build_pipe_flange(blower_outlet, pipe_r)
	_build_pipe_flange(cyclone_inlet, pipe_r)

## A short wider disc at a pipe-to-machine junction, reading as a bolted flange.
func _build_pipe_flange(at: Vector3, pipe_r: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = pipe_r * 1.55
	cm.bottom_radius = pipe_r * 1.55
	cm.height = 0.04
	cm.radial_segments = 12
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.42, 0.46)
	mat.metallic = 0.6
	mat.roughness = 0.30
	mi.material_override = mat
	add_child(mi)
	mi.global_position = at

## Draw a galvanised-steel cylindrical pipe between two world-space points.
## Lives in the gauntlet root, not parented to any machine, so machines stay
## independent placeables that can be jogged without breaking the chain. Adds
## sphere "elbow fillers" at both endpoints — cylinder ends are flat caps that
## leave visible seams at corners; spheres of the same diameter mask that
## without needing a real torus elbow mesh.
func _build_steel_pipe(from: Vector3, to: Vector3, radius: float) -> void:
	var diff := to - from
	var length := diff.length()
	if length < 0.01:
		return
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 12
	mi.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.59, 0.63)
	mat.metallic = 0.55
	mat.roughness = 0.35
	mi.material_override = mat
	add_child(mi)
	mi.global_position = (from + to) * 0.5
	# CylinderMesh defaults to +Y axis; align it with the from→to direction.
	var dir := diff.normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		var axis := Vector3.UP.cross(dir).normalized()
		var angle := acos(clampf(Vector3.UP.dot(dir), -1.0, 1.0))
		mi.transform.basis = Basis(axis, angle)
	# Elbow fillers at both ends so corners read as smooth bends, not square seams.
	_build_pipe_elbow(from, radius)
	_build_pipe_elbow(to,   radius)

## Sphere of pipe-radius at a corner — masks the flat-cap seam left by two
## cylinders meeting at an angle. Reused across every pipe so a long chain
## ends up with one sphere per junction.
func _build_pipe_elbow(at: Vector3, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 12
	sm.rings = 8
	mi.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.56, 0.59, 0.63)
	mat.metallic = 0.55
	mat.roughness = 0.35
	mi.material_override = mat
	add_child(mi)
	mi.global_position = at

# #100 — flotation tank → dewatering screw, IN LINE so the weir chute on the
# tank's +Z outlet drops into the dewater_screw's catch scoop. Flotation tank
# size (4.5, 1.6, 9.0) → +Z outlet at z = +4.5 from its centre. Dewater_screw
# size (1.2, 2.6, 4.5) with scoop at -size.z * 0.42 ≈ -1.89 from its centre.
# Placing the screw at z = +6.5 puts its scoop at world z ≈ +4.61, just past
# the weir-chute's drop point.
func _st_100(anchor: Vector3) -> void:
	var ft : Node3D = PlaceableCatalog.build_node("flotation_tank", false, false)
	if ft:
		add_child(ft)
		ft.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var dw : Node3D = PlaceableCatalog.build_node("dewater_screw", false, false)
	if dw:
		add_child(dw)
		dw.global_position = anchor + Vector3(0.0, 0.0, 6.5)

# #101 — extraction screw on silo (done this turn — non-extruder silo now has
# a visible horizontal screw at the base).
func _st_101(anchor: Vector3) -> void:
	_build_placed("silo", anchor)

# #116 — door furniture (pending).
func _st_116(anchor: Vector3) -> void:
	_build_placeholder(anchor, "pending")

# #117 — close-LOD bale shading. Render two bales: one "far-LOD" simple model,
# one "detail" model, so the operator can see what the second per-yard MM needs
# to add (visible wire shadow + sticker proximity).
func _st_117(anchor: Vector3) -> void:
	var simple : Node3D = PlaceableCatalog.build_node("rotterdam", true, true)
	if simple:
		add_child(simple)
		simple.global_position = anchor + Vector3(-1.0, 0.0, 0.0)
	var detail : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if detail:
		add_child(detail)
		detail.global_position = anchor + Vector3(1.0, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "far LOD          close LOD\n(simple)         (detail+wires)"
	lbl.font_size = 28; lbl.outline_size = 6
	lbl.position = anchor + Vector3(0.0, 1.8, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #122 — door type auto-classify. Render three coloured slabs sized to match
# what solidify_building.py classifies as door / gate / window so the operator
# can eyeball the rule (the script does the actual carve).
func _st_122(anchor: Vector3) -> void:
	var samples := [
		{"label": "DOOR\n0.9×2.1 m", "size": Vector3(0.9, 2.1, 0.06), "col": Color(0.42, 0.32, 0.22), "by": 0.0},
		{"label": "GATE\n3.5×3.0 m", "size": Vector3(3.5, 3.0, 0.06), "col": Color(0.18, 0.22, 0.36), "by": 0.0},
		{"label": "WINDOW\n1.4×0.9 m", "size": Vector3(1.4, 0.9, 0.06), "col": Color(0.55, 0.78, 0.86), "by": 1.2},
	]
	var x : float = -3.0
	for s in samples:
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = s["size"]
		slab.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = s["col"]
		mat.roughness = 0.7
		slab.material_override = mat
		slab.position = anchor + Vector3(x, float(s["by"]) + (s["size"] as Vector3).y * 0.5, 0.0)
		add_child(slab)
		var lbl := Label3D.new()
		lbl.text = String(s["label"])
		lbl.font_size = 28; lbl.outline_size = 6
		lbl.position = anchor + Vector3(x, float(s["by"]) + (s["size"] as Vector3).y + 0.5, 0.05)
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.pixel_size = 0.005
		add_child(lbl)
		x += 2.5

# #124 — crew assignment UI (pending).
func _st_124(anchor: Vector3) -> void:
	_build_placeholder(anchor, "pending")

# #125 — yard bale labels. Render one detail bale (which already carries the
# baked sticker quad #93) so the operator can verify the sticker reads at close
# range; the pending #125 piece is making this MM-driven per yard.
func _st_125(anchor: Vector3) -> void:
	var b : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if b:
		add_child(b)
		b.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "Detail bale w/ baked sticker (#93)\nPending: proximity-load this MM per yard"
	lbl.font_size = 24; lbl.outline_size = 6
	lbl.position = anchor + Vector3(0.0, 1.8, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #126 — humanoid proportion review (done — small touches: arms run a bit
# longer, head sits proportional). Render one of each NPC so operator can eye
# the silhouette.
func _st_126(anchor: Vector3) -> void:
	var script := load("res://src/scenes/world/Humanoid.gd")
	if script == null:
		return
	# Direct NPC_DATA lookup from the MainWorld class. Show five distinct
	# silhouettes so the operator can eyeball proportions + #133 appearances.
	var i := 0
	for who in ["pascal", "kevin", "emrah", "mohammed", "peter"]:
		var npc_data : Dictionary = MainWorld.NPC_DATA.get(who, {})
		var col : Color = npc_data.get("color", Color.WHITE)
		var app : Dictionary = npc_data.get("appearance", {})
		var body : Node3D = script.build(col, i, app)
		add_child(body)
		body.global_position = anchor + Vector3(float(i) * 1.4 - 2.8, 1.0, 0.0)
		i += 1

# #127 — bale yard deferred spawn. Visible proof: a small "yard" of stacked
# bales (catalog `bale_stack5`) that loads in one frame; if the deferred path
# regresses you'd see a hitch right here when the gauntlet boots.
func _st_127(anchor: Vector3) -> void:
	for i in 4:
		var b : Node3D = PlaceableCatalog.build_node("rotterdam_stack5", false, false)
		if b == null:
			b = PlaceableCatalog.build_node("rotterdam", false, false)
		if b == null:
			continue
		add_child(b)
		b.global_position = anchor + Vector3(float(i % 2) * 1.4 - 0.7, 0.0, float(i / 2) * 1.4)

# #128 — Peter spawns indoors. Render Peter inside a 4×4 m floor outline so the
# operator can see "the manager stayed inside the building AABB" at a glance.
func _st_128(anchor: Vector3) -> void:
	var outline := MeshInstance3D.new()
	var om := BoxMesh.new(); om.size = Vector3(4.0, 0.02, 4.0)
	outline.mesh = om
	var omat := StandardMaterial3D.new()
	omat.albedo_color = Color(0.20, 0.45, 0.85)
	outline.material_override = omat
	outline.position = anchor + Vector3(0.0, 0.01, 0.0)
	add_child(outline)
	var script := load("res://src/scenes/world/Humanoid.gd")
	if script != null:
		var npc_data : Dictionary = MainWorld.NPC_DATA.get("peter", {})
		var body : Node3D = script.build(npc_data.get("color", Color.WHITE), 0,
			npc_data.get("appearance", {}))
		add_child(body)
		body.global_position = anchor + Vector3(0.0, 0.0, 0.0)

# #134 — crew cars (pending).
func _st_134(anchor: Vector3) -> void:
	_build_placeholder(anchor, "pending")

# #135 — player spawns in their car (pending).
func _st_135(anchor: Vector3) -> void:
	_build_placeholder(anchor, "pending")

# #139 — pack-up cascade (pending).
func _st_139(anchor: Vector3) -> void:
	_build_placeholder(anchor, "pending")

# #141 — transportband chain with proper Y-stacking + length-aware overlap.
# Each belt's deck height at the inlet/outlet depends on the deck pivot
# offset (size.y * 0.75 + size.y * 0.22) PLUS the incline-driven ±sin(α) rise
# across the half-length. Belt N+1's base Y is set so its INLET deck top sits
# a chute-drop below belt N's OUTLET deck top. The chute on each belt (added
# this turn in _m_intake_belt) visually bridges the drop.
func _st_141(anchor: Vector3) -> void:
	var ids := ["intake_belt_4", "intake_belt_5", "intake_belt_6", "intake_belt_7"]
	const CHUTE_DROP_M : float = 0.22
	# NO Z overlap: with axis-aligned BoxShape3D collisions the previous belt's
	# bbox extended INTO the next belt's bbox by Z_OVERLAP_M, the player walked
	# into that intersected wall and got stuck shaking against the side. Belts
	# now sit head-to-tail, the chute on each belt's outlet hangs into the next
	# belt's inlet (the chute is parented to the body, so it sticks past the +Z
	# end of the belt).
	const Z_OVERLAP_M  : float = 0.0
	var z : float = anchor.z
	var prev_outlet_top_y : float = -1.0   # sentinel: first belt sits on the floor
	for id in ids:
		var item : Dictionary = PlaceableCatalog.get_item(id)
		var bsize : Vector3 = item["size"]
		var blen : float = bsize.z
		var spec : Dictionary = PlaceableCatalog._intake_belt_spec(id)
		var incline_rad : float = deg_to_rad(float(spec["incline"]))
		# Mirror the math from _m_intake_belt: deck pivot at deck_y, deck box
		# centred at deck_y + size.y * 0.22, pulleys at ±hz from the pivot. The
		# inlet/outlet deck-top heights vs the belt's base:
		var deck_top : float = bsize.y * 0.75 + bsize.y * 0.22
		var lift_at_end : float = (blen * 0.45) * sin(incline_rad)
		var inlet_top_off  : float = deck_top - lift_at_end
		var outlet_top_off : float = deck_top + lift_at_end
		var base_y : float = 0.0
		if prev_outlet_top_y > 0.0:
			base_y = maxf(0.0, prev_outlet_top_y - CHUTE_DROP_M - inlet_top_off)
		var n : Node3D = PlaceableCatalog.build_node(id, false, false)
		if n == null:
			z += blen - Z_OVERLAP_M
			continue
		add_child(n)
		n.global_position = Vector3(anchor.x, base_y, z + blen * 0.5)
		n.rotation.y = 0.0
		prev_outlet_top_y = base_y + outlet_top_off
		z += blen - Z_OVERLAP_M
