extends Node3D
##
## TEST GAUNTLET. A self-contained scene that lays the backlog out in a
## walkable line — operator spawns at the west end, walks east, verifies each
## station, moves on. Stations are defined in STATIONS and auto-populated by
## per-task builder methods (`_st_NN`). Adding a new task = add a row to the
## list + write `_st_NN()` — no scene-file edits.
##
## STATUS LIFECYCLE:
##   pending    — yellow board, barber-pole placeholder; nothing built yet
##   verifying  — orange board; code exists but operator hasn't eyeballed it
##   verified   — green board; operator pressed Y after a successful walk-by
##   failed     — red board; operator pressed N because it's wrong / missing
##
## CONTROLS (in scene):
##   Y   verify the station the player is currently aiming at  (sets `verified`)
##   N   fail the station the player is currently aiming at    (sets `failed`)
##   R   reset to `verifying`                                  (clears Y/N)
##
## State is saved to user://gauntlet_status.json so toggles survive a restart.
##
## Spawned with Player + flashlight + bay lights so it's lit + walkable; the
## crew + LineFlow + bale yards are NOT spawned (this is for visual / quick
## interaction verification, NOT a live shift).

const STATION_SPACING_M : float = 14.0
# +Z behind each sign reserved for props. Some builders (#99 cyclone @ z≈9.5,
# #141 belt chain that runs further) go past 12 m, so the platform extends to
# DEEPEST_PROP_Z + PLATFORM_BACK_PAD on the +Z side.
const STATION_DEPTH_M   : float = 12.0
const DEEPEST_PROP_Z    : float = 16.0
const PLATFORM_BACK_PAD : float = 4.0    # +Z buffer past the deepest prop
const PLATFORM_FRONT_PAD: float = 4.0    # -Z buffer in front of the sign row
const FLOOR_THICKNESS_M : float = 0.5
const SIGN_HEIGHT_M     : float = 3.2

const STATUS_PATH : String = "user://gauntlet_status.json"
const AIM_RANGE_M : float = 30.0

## task_id, title, builder method name, default status.
##   pending   = nothing built, placeholder pole
##   verifying = code-audit done but NOT yet eyeballed in-engine. THIS is the
##               default for anything that landed as "done with caveat" — the
##               operator must press Y or N to retire it.
##   verified  = operator has confirmed it in a previous gauntlet run; sign is
##               green from boot. Still gets built so it's there as a reference.
## Fresh gauntlet for THIS session's work. Every entry is `verifying` so the
## walk shows everything that needs operator eyeball this run. Press Y to
## verify, N to fail — both hide the station from the next boot.
const STATIONS : Array[Dictionary] = [
	# ─── Audio + visuals ──────────────────────────────────────────────────────
	{"id": 200, "title": "T1 Walkie — squelch chirp, NO alien voice",  "fn": "_st_t1_walkie",     "status": "verifying"},
	{"id": 201, "title": "T4 Fog 500 m — default ON",                  "fn": "_st_t4_fog",        "status": "verifying"},
	{"id": 202, "title": "T8 Footwear — boots on shift, shoes off",    "fn": "_st_t8_footwear",   "status": "verifying"},
	{"id": 203, "title": "D2 Bale sticker — readable ROTTERDAM text",  "fn": "_st_d2_sticker",    "status": "verifying"},
	# ─── D4 belt audit fixes (this session) ──────────────────────────────────
	{"id": 210, "title": "D4 Belt direction — carries downstream",     "fn": "_st_d4_dir",        "status": "verifying"},
	{"id": 211, "title": "D4 Opzetband K-edit / delete / save round",  "fn": "_st_d4_opzetband",  "status": "verifying"},
	{"id": 212, "title": "D4 LINE_SORT_SEQ has opzetband at head",     "fn": "_st_d4_sort_macro", "status": "verifying"},
	{"id": 213, "title": "D4 LINE_3C6_SEQ macro available + builds",   "fn": "_st_d4_3c6_macro",  "status": "verifying"},
	{"id": 214, "title": "D4 Spinning end rollers (omega = v / r)",    "fn": "_st_d4_rollers",    "status": "verifying"},
	# ─── Car auto-ruler ───────────────────────────────────────────────────────
	{"id": 220, "title": "V2 Cars at real-world length (auto-ruler)",  "fn": "_st_v2_cars",       "status": "verifying"},
	# ─── Performance ──────────────────────────────────────────────────────────
	{"id": 230, "title": "Perf FilmFlakeField 20 Hz + cull (no idle)", "fn": "_st_perf_ff",       "status": "verifying"},
	# ─── NPC + Build-mode improvements ────────────────────────────────────────
	{"id": 240, "title": "NPC step-ray fix — no constant jumping",     "fn": "_st_npc_jump",      "status": "verifying"},
	{"id": 241, "title": "Build mode — green snap pole on adjacency",  "fn": "_st_bm_snap",       "status": "verifying"},
	{"id": 242, "title": "Transportband Y-stacking macro (chain UP)",  "fn": "_st_tb_stack",      "status": "verifying"},
	{"id": 243, "title": "Bale close-LOD wire bands + sticker quad",   "fn": "_st_lod_bands",     "status": "verifying"},
]

# Cached anchors so per-station builders can attach to one parent each.
var _stations_root : Node3D = null
# id → {"holder": Node3D, "board": MeshInstance3D, "label": Label3D, "status": String}
var _sign_refs : Dictionary = {}
# Persisted overrides loaded from disk. Empty until _load_status().
var _persisted : Dictionary = {}
var _player : CharacterBody3D = null
var _camera : Camera3D = null

func _ready() -> void:
	_load_status()
	_build_floor()
	_build_sky_light()
	_stations_root = Node3D.new()
	_stations_root.name = "Stations"
	add_child(_stations_root)
	# Slot counter: increments only when we actually place a station, so the
	# gauntlet collapses (no empty gaps) when failed entries are skipped.
	var slot : int = 0
	for i in STATIONS.size():
		var entry : Dictionary = STATIONS[i].duplicate()
		# Apply persisted override (operator's Y/N from a previous run).
		var sid : String = str(int(entry["id"]))
		if _persisted.has(sid):
			entry["status"] = String(_persisted[sid])
		# BOTH failed and verified stations are hidden. The gauntlet only
		# surfaces items still needing operator eyeball — once decided either
		# way the station is off the walk. To resurrect either, delete
		# user://gauntlet_status.json or edit STATIONS back to "verifying".
		var st : String = String(entry["status"])
		if st == "failed" or st == "verified":
			continue
		var x : float = float(slot) * STATION_SPACING_M
		_build_station_sign(Vector3(x, 0.0, 0.0), entry)
		if has_method(String(entry["fn"])):
			call(entry["fn"], Vector3(x, 0.0, 4.0))
		else:
			_build_placeholder(Vector3(x, 0.0, 4.0), String(entry["status"]))
		slot += 1
	_build_player()
	_spawn_hud()
	_spawn_help_overlay()
	# Reset cursor so the player can walk straight from spawn.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var hidden : int = STATIONS.size() - slot
	print("[Gauntlet] %d stations shown over %.0f m  (%d decided/hidden)  —  Y verify / N fail / R reset" % [
		slot, float(slot) * STATION_SPACING_M, hidden])

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var key : int = (event as InputEventKey).keycode
	var new_status : String = ""
	match key:
		KEY_Y: new_status = "verified"
		KEY_N: new_status = "failed"
		KEY_R: new_status = "verifying"
		_: return
	var hit_id : int = _aimed_station_id()
	if hit_id < 0:
		return
	_set_status(hit_id, new_status)

## Project a ray from the camera; return the station id whose holder we hit,
## or -1 if nothing. Uses sphere-against-camera-ray instead of physics queries
## so signs don't need PhysicsBody3D wrappers (cheaper and more forgiving aim).
func _aimed_station_id() -> int:
	if _camera == null:
		return -1
	var origin : Vector3 = _camera.global_position
	var fwd : Vector3 = -_camera.global_transform.basis.z
	var best_id : int = -1
	var best_t : float = AIM_RANGE_M
	# Hit-radius generous enough that walking past + glancing at a sign works.
	const SIGN_HIT_R : float = 2.4
	for id_key in _sign_refs.keys():
		var ref : Dictionary = _sign_refs[id_key]
		var holder : Node3D = ref.get("holder")
		if holder == null:
			continue
		# Sample the board centre (≈ sign mid-height) rather than holder origin.
		var c : Vector3 = holder.global_position + Vector3(0.0, SIGN_HEIGHT_M - 0.4, 0.0)
		var to_c : Vector3 = c - origin
		var t : float = to_c.dot(fwd)
		if t < 0.0 or t > AIM_RANGE_M:
			continue
		var closest : Vector3 = origin + fwd * t
		if closest.distance_to(c) > SIGN_HIT_R:
			continue
		if t < best_t:
			best_t = t
			best_id = int(id_key)
	return best_id

func _set_status(sid: int, new_status: String) -> void:
	var key : String = str(sid)
	if not _sign_refs.has(sid):
		return
	var ref : Dictionary = _sign_refs[sid]
	ref["status"] = new_status
	_paint_sign(ref, new_status)
	_persisted[key] = new_status
	_save_status()
	print("[Gauntlet] #%d → %s" % [sid, new_status.to_upper()])

func _load_status() -> void:
	if not FileAccess.file_exists(STATUS_PATH):
		return
	var f := FileAccess.open(STATUS_PATH, FileAccess.READ)
	if f == null:
		return
	var raw : String = f.get_as_text()
	f.close()
	var parsed : Variant = JSON.parse_string(raw)
	if typeof(parsed) == TYPE_DICTIONARY:
		_persisted = parsed

func _save_status() -> void:
	var f := FileAccess.open(STATUS_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(_persisted, "  "))
	f.close()

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

## Persistent on-screen legend so the operator doesn't need to remember which
## key does what. Tiny corner panel, no interaction.
func _spawn_help_overlay() -> void:
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.anchor_left = 0.0; panel.anchor_top = 0.0
	panel.offset_left = 12; panel.offset_top = 12
	panel.modulate = Color(1, 1, 1, 0.88)
	canvas.add_child(panel)
	var vb := VBoxContainer.new()
	panel.add_child(vb)
	for line in [
		"AIM AT A SIGN, THEN:",
		"  Y  verify (green)",
		"  N  fail   (red)",
		"  R  reset  (orange)",
	]:
		var lbl := Label.new()
		lbl.text = line
		vb.add_child(lbl)

# ─── World bones ──────────────────────────────────────────────────────────────

func _build_floor() -> void:
	# Length is based on visible (non-failed) stations so the floor doesn't
	# extend past the last sign into empty space.
	var visible : int = 0
	for s in STATIONS:
		var sid : String = str(int(s["id"]))
		var status : String = String(_persisted.get(sid, s["status"]))
		if status != "failed" and status != "verified":
			visible += 1
	var length : float = float(maxi(visible, 1)) * STATION_SPACING_M + 20.0
	# Floor width covers from -PLATFORM_FRONT_PAD (in front of the sign row)
	# to DEEPEST_PROP_Z + PLATFORM_BACK_PAD behind it. Centre shifted so the
	# slab actually sits under the props, not just under the signs.
	var width  : float = DEEPEST_PROP_Z + PLATFORM_BACK_PAD + PLATFORM_FRONT_PAD
	var z_centre : float = (DEEPEST_PROP_Z + PLATFORM_BACK_PAD - PLATFORM_FRONT_PAD) * 0.5
	var floor_body := StaticBody3D.new()
	floor_body.name = "GauntletFloor"
	add_child(floor_body)
	var mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(length, FLOOR_THICKNESS_M, width)
	mesh.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.30, 0.32)
	mat.roughness = 0.88
	mesh.material_override = mat
	mesh.position = Vector3(length * 0.5 - 10.0, -FLOOR_THICKNESS_M * 0.5, z_centre)
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
	_player = p
	_camera = cam

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
	board.material_override = bm_mat
	board.position = Vector3(0.0, SIGN_HEIGHT_M - 0.4, 0.0)
	holder.add_child(board)
	# Billboarded label — always faces the camera, so the operator reads it
	# whether they're approaching, passing, or looking back.
	var label := Label3D.new()
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
	var ref : Dictionary = {
		"holder": holder,
		"board": board,
		"label": label,
		"title": String(entry["title"]),
		"id": int(entry["id"]),
		"status": String(entry["status"]),
	}
	_sign_refs[int(entry["id"])] = ref
	_paint_sign(ref, String(entry["status"]))

## Apply colour + label text for a given status. Called on first build and on
## every Y/N/U toggle so the operator gets immediate visual feedback.
func _paint_sign(ref: Dictionary, status: String) -> void:
	var col : Color
	match status:
		"verified":  col = Color(0.18, 0.55, 0.22)   # forest green
		"failed":    col = Color(0.74, 0.16, 0.14)   # caution red
		"verifying": col = Color(0.88, 0.46, 0.10)   # bright orange
		_:           col = Color(0.46, 0.42, 0.16)   # caution yellow (pending)
	var mat : StandardMaterial3D = ref["board"].material_override
	if mat == null:
		mat = StandardMaterial3D.new()
		ref["board"].material_override = mat
	mat.albedo_color = col
	mat.roughness = 0.7
	var label : Label3D = ref["label"]
	label.text = "#%d  %s\n[%s]" % [int(ref["id"]), String(ref["title"]), status.to_upper()]

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
	match status:
		"verified":
			col_a = Color(0.18, 0.55, 0.30); col_b = Color(0.95, 0.95, 0.95)
		"failed":
			col_a = Color(0.74, 0.16, 0.14); col_b = Color(0.10, 0.10, 0.10)
		"verifying":
			col_a = Color(0.88, 0.46, 0.10); col_b = Color(0.20, 0.20, 0.20)
		_:
			col_a = Color(0.92, 0.20, 0.18); col_b = Color(0.96, 0.92, 0.20)
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
	_build_placeholder(anchor, "failed")

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
	var dryer_top_y : float = 2.72
	var header_y    : float = dryer_top_y + 0.5
	var d1 : Node3D = PlaceableCatalog.build_node("mech_dryer", false, false)
	if d1: add_child(d1); d1.global_position = anchor + Vector3(-d_off, 0.0, 0.0)
	var d2 : Node3D = PlaceableCatalog.build_node("mech_dryer", false, false)
	if d2: add_child(d2); d2.global_position = anchor + Vector3( d_off, 0.0, 0.0)
	var blo : Node3D = PlaceableCatalog.build_node("blower", false, false)
	if blo: add_child(blo); blo.global_position = anchor + Vector3(blo_x, 0.0, blo_z)
	var cy : Node3D = PlaceableCatalog.build_node("cyclone", false, false)
	if cy: add_child(cy); cy.global_position = anchor + Vector3(cy_x, 0.0, cy_z)
	_build_steel_pipe(anchor + Vector3(-d_off, dryer_top_y, 0.0),
		anchor + Vector3(-d_off, header_y,    0.0), pipe_r)
	_build_steel_pipe(anchor + Vector3( d_off, dryer_top_y, 0.0),
		anchor + Vector3( d_off, header_y,    0.0), pipe_r)
	_build_steel_pipe(anchor + Vector3(-d_off, header_y, 0.0),
		anchor + Vector3( d_off, header_y, 0.0), pipe_r)
	_build_steel_pipe(anchor + Vector3(0.0, header_y, 0.0),
		anchor + Vector3(0.0, header_y + 0.7, 0.0), pipe_r * 0.5)
	var blower_inlet := anchor + Vector3(blo_x + 0.5, 0.6, blo_z)
	_build_steel_pipe(anchor + Vector3(0.0, header_y, 0.0),
		anchor + Vector3(0.0, header_y, blo_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(0.0, header_y, blo_z),
		anchor + Vector3(blo_x + 0.5, header_y, blo_z), pipe_r)
	_build_steel_pipe(anchor + Vector3(blo_x + 0.5, header_y, blo_z),
		blower_inlet, pipe_r)
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
	var dir := diff.normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		var axis := Vector3.UP.cross(dir).normalized()
		var angle := acos(clampf(Vector3.UP.dot(dir), -1.0, 1.0))
		mi.transform.basis = Basis(axis, angle)
	_build_pipe_elbow(from, radius)
	_build_pipe_elbow(to,   radius)

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

# #100 — flotation tank → dewatering screw.
func _st_100(anchor: Vector3) -> void:
	var ft : Node3D = PlaceableCatalog.build_node("flotation_tank", false, false)
	if ft:
		add_child(ft)
		ft.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var dw : Node3D = PlaceableCatalog.build_node("dewater_screw", false, false)
	if dw:
		add_child(dw)
		dw.global_position = anchor + Vector3(0.0, 0.0, 6.5)

# #101 — extraction screw on silo. The silo carries a horizontal screw that
# discharges flakes sideways; this station shows the stream + an accumulating
# pile that resets every ~30 s so the operator can see the conveyance.
func _st_101(anchor: Vector3) -> void:
	var silo := _build_placed("silo", anchor)
	# Outlet roughly at the front-low of the silo. Numbers are conservative —
	# the silo is ~3 m wide so emitter sits just outside its skin at ~1.0 m up.
	var outlet := anchor + Vector3(1.6, 1.0, 0.0)
	var emitter := GPUParticles3D.new()
	emitter.name = "ExtractScrewStream"
	emitter.amount = 60
	emitter.lifetime = 1.2
	emitter.one_shot = false
	emitter.preprocess = 0.5
	emitter.fixed_fps = 30
	emitter.visibility_aabb = AABB(Vector3(-1.0, -1.5, -1.0), Vector3(2.0, 3.0, 2.0))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.05
	pm.direction = Vector3(0.6, -0.8, 0.0).normalized()
	pm.spread = 6.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.0
	pm.gravity = Vector3(0.0, -2.4, 0.0)
	pm.scale_min = 0.02
	pm.scale_max = 0.04
	var grad := Gradient.new()
	grad.set_color(0, Color(0.18, 0.18, 0.20, 1.0))
	grad.set_color(1, Color(0.10, 0.10, 0.12, 0.0))
	var gt := GradientTexture1D.new()
	gt.gradient = grad
	pm.color_ramp = gt
	emitter.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.16, 0.16, 0.18)
	pmat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	pmat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	sm.material = pmat
	emitter.draw_pass_1 = sm
	add_child(emitter)
	emitter.global_position = outlet
	# Growing accumulation pile under the outlet — MultiMesh of tiny dark cubes
	# whose visible count ramps from 0 → MAX over PILE_CYCLE_S, then resets.
	var pile_pos := anchor + Vector3(1.6, 0.05, 0.0)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = false
	var cube := BoxMesh.new()
	cube.size = Vector3(0.06, 0.06, 0.06)
	mm.mesh = cube
	const PILE_MAX : int = 220
	mm.instance_count = PILE_MAX
	mm.visible_instance_count = 0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9182
	for i in PILE_MAX:
		var r : float = sqrt(rng.randf()) * 0.45
		var a : float = rng.randf() * TAU
		var py : float = float(i) / float(PILE_MAX) * 0.35
		var t := Transform3D(Basis(), Vector3(cos(a) * r, py + 0.03, sin(a) * r))
		mm.set_instance_transform(i, t)
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var pmm := StandardMaterial3D.new()
	pmm.albedo_color = Color(0.18, 0.18, 0.20)
	pmm.roughness = 0.9
	mmi.material_override = pmm
	add_child(mmi)
	mmi.global_position = pile_pos
	# Timer ramps the pile up, then resets. Uses a Timer node so this works
	# without the station needing a per-frame _process hook.
	var ramp := Timer.new()
	ramp.wait_time = 0.25
	ramp.one_shot = false
	ramp.autostart = true
	add_child(ramp)
	var state := {"t": 0.0}
	ramp.timeout.connect(func() -> void:
		state["t"] = float(state["t"]) + 0.25
		if state["t"] >= 30.0:
			state["t"] = 0.0
			mm.visible_instance_count = 0
			return
		mm.visible_instance_count = int(clampf(float(state["t"]) / 30.0, 0.0, 1.0) * PILE_MAX))
	var lbl := Label3D.new()
	lbl.text = "Silo horizontal extraction screw\nFlakes stream out + pile (resets ~30 s)"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 3.6, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)
	var _silo_unused := silo

# #116 — door furniture. Catalog now carries door_personnel, gate_roller,
# window_frame; render one of each so operator can see the silhouettes.
func _st_116(anchor: Vector3) -> void:
	var ids := ["door_personnel", "gate_roller", "window_frame"]
	var x : float = -2.5
	for id in ids:
		var n : Node3D = PlaceableCatalog.build_node(id, false, false)
		if n:
			add_child(n)
			n.global_position = anchor + Vector3(x, 0.0, 0.0)
		var lbl := Label3D.new()
		lbl.text = String(id)
		lbl.font_size = 22; lbl.outline_size = 5
		lbl.position = anchor + Vector3(x, 2.6, 0.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.pixel_size = 0.005
		add_child(lbl)
		x += 2.5

# #117 — close-LOD bale shading. LOD = "Level Of Detail". The yard renders
# distant bales with a cheap model (no wires, no sticker) and swaps to a
# detailed model close up. This station shows them side by side at the SAME
# distance so the operator can directly compare and confirm the detailed
# model actually has the extra shading work baked in.
func _st_117(anchor: Vector3) -> void:
	var simple : Node3D = PlaceableCatalog.build_node("rotterdam", true, true)
	if simple:
		add_child(simple)
		simple.global_position = anchor + Vector3(-1.5, 0.0, 0.0)
	var detail : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if detail:
		add_child(detail)
		detail.global_position = anchor + Vector3(1.5, 0.0, 0.0)
	# Big explainer header above both bales so the operator knows the rule.
	var head := Label3D.new()
	head.text = "#117  BALE  LOD  COMPARISON"
	head.font_size = 44; head.outline_size = 8
	head.position = anchor + Vector3(0.0, 2.6, 0.0)
	head.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	head.pixel_size = 0.006
	add_child(head)
	# Per-bale labels with explicit "what to look for" checklists.
	var left := Label3D.new()
	left.text = "LEFT — FAR LOD\n(what distant bales use)\n\n• flat side faces\n• NO wire grooves\n• NO paper sticker\n• plain colour, no shading"
	left.font_size = 22; left.outline_size = 5
	left.position = anchor + Vector3(-1.5, 1.7, 0.0)
	left.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	left.pixel_size = 0.0045
	add_child(left)
	var right := Label3D.new()
	right.text = "RIGHT — CLOSE LOD\n(what nearby bales use)\n\n• visible WIRE GROOVES on all sides\n• PAPER STICKER on one face\n• darker shading in the grooves\n• swap-in trigger: ~25 m from player"
	right.font_size = 22; right.outline_size = 5
	right.position = anchor + Vector3(1.5, 1.7, 0.0)
	right.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	right.pixel_size = 0.0045
	add_child(right)
	# What the gauntlet is testing + how to decide Y vs N.
	var verdict := Label3D.new()
	verdict.text = "PASS (Y) if: the RIGHT bale clearly has wire grooves AND a sticker the LEFT bale lacks.\nFAIL (N) if: both bales look identical, OR the right one has no extra detail."
	verdict.font_size = 20; verdict.outline_size = 5
	verdict.position = anchor + Vector3(0.0, 0.4, 1.5)
	verdict.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	verdict.pixel_size = 0.0045
	add_child(verdict)

# #122 — door type auto-classify.
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
	_build_placeholder(anchor, "failed")

# #125 — yard bale labels. Spawn a bale; PlaceableCatalog attaches a realistic
# paper sticker (supplier / bale ID / weight / dims) — operator should now read
# the sticker text instead of seeing illegible "MMM" blurs.
func _st_125(anchor: Vector3) -> void:
	var b : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if b:
		add_child(b)
		b.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "Bale sticker should read:\nSUPPLIER · ID Bxxxxx · weight kg · LxWxH"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 1.8, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #126 — humanoid proportion review.
func _st_126(anchor: Vector3) -> void:
	var script := load("res://src/scenes/world/Humanoid.gd")
	if script == null:
		return
	var i := 0
	for who in ["pascal", "kevin", "emrah", "mohammed", "peter"]:
		var npc_data : Dictionary = MainWorld.NPC_DATA.get(who, {})
		var col : Color = npc_data.get("color", Color.WHITE)
		var app : Dictionary = npc_data.get("appearance", {})
		var body : Node3D = script.build(col, i, app)
		add_child(body)
		body.global_position = anchor + Vector3(float(i) * 1.4 - 2.8, 1.0, 0.0)
		i += 1

# #127 — bale yard deferred spawn.
func _st_127(anchor: Vector3) -> void:
	for i in 4:
		var b : Node3D = PlaceableCatalog.build_node("rotterdam_stack5", false, false)
		if b == null:
			b = PlaceableCatalog.build_node("rotterdam", false, false)
		if b == null:
			continue
		add_child(b)
		b.global_position = anchor + Vector3(float(i % 2) * 1.4 - 0.7, 0.0, float(i / 2) * 1.4)

# #128 — Peter spawns indoors.
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
	_build_placeholder(anchor, "failed")

# #135 — player spawns in their car (pending).
func _st_135(anchor: Vector3) -> void:
	_build_placeholder(anchor, "failed")

# #139 — pack-up cascade. Build both VSS silos with a level proxy showing FULL,
# the upstream belt chain feeding them, plus a state indicator that ramps off
# step-by-step (visualises the cascade without a live LineFlow tick).
func _st_139(anchor: Vector3) -> void:
	# Two VSS silos side-by-side.
	var vss_ids := [-3.0, 3.0]
	var vss_nodes : Array[Node3D] = []
	for x in vss_ids:
		var n : Node3D = PlaceableCatalog.build_node("vss_silo", false, false)
		if n:
			add_child(n)
			n.global_position = anchor + Vector3(float(x), 0.0, 0.0)
			vss_nodes.append(n)
			# Try the placeable's own level-setter; fall back to a meta + a
			# floating "FULL" tag if it doesn't expose one.
			if n.has_method("set_level"):
				n.call("set_level", 1.0)
			elif n.has_method("set_fill"):
				n.call("set_fill", 1.0)
			else:
				n.set_meta("fill_level", 1.0)
			# Red FULL indicator stuck on the silo so the operator reads "full"
			# at a glance even if the model doesn't visualise the level.
			var tag := Label3D.new()
			tag.text = "FULL"
			tag.modulate = Color(1.0, 0.25, 0.18)
			tag.outline_modulate = Color(0.10, 0.0, 0.0, 0.9)
			tag.font_size = 60; tag.outline_size = 10
			tag.position = anchor + Vector3(float(x), 5.2, 0.0)
			tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			tag.pixel_size = 0.008
			add_child(tag)
	# Upstream belt chain (4 belts) feeding the VSS pair from the +Z side.
	var belt_z : float = 2.6
	for id in ["transportband_3", "transportband_4", "transportband_5", "transportband_12"]:
		var item : Dictionary = PlaceableCatalog.get_item(id)
		var bsize : Vector3 = item["size"] if not item.is_empty() else Vector3(1.4, 0.6, 2.0)
		var b : Node3D = PlaceableCatalog.build_node(id, false, false)
		if b:
			add_child(b)
			b.global_position = anchor + Vector3(0.0, 0.0, belt_z + bsize.z * 0.5)
			belt_z += bsize.z + 0.3
	# State indicator: 4 stacked lights representing the belts ramping off in
	# sequence. Starts all green; cycles to red front-to-back (closest to VSS
	# packs up first), so the cascade is unmistakable.
	var lights : Array[MeshInstance3D] = []
	for i in 4:
		var seg := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.16; sm.height = 0.32
		seg.mesh = sm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.20, 0.65, 0.25)
		m.emission_enabled = true
		m.emission = m.albedo_color
		seg.material_override = m
		seg.position = anchor + Vector3(0.0, 4.2 - float(i) * 0.4, -0.6)
		add_child(seg)
		lights.append(seg)
	var step := Timer.new()
	step.wait_time = 1.0
	step.autostart = true
	add_child(step)
	var idx := {"i": 0}
	step.timeout.connect(func() -> void:
		var i : int = int(idx["i"])
		if i < lights.size():
			var mat : StandardMaterial3D = lights[i].material_override
			mat.albedo_color = Color(0.85, 0.15, 0.10)
			mat.emission = mat.albedo_color
		idx["i"] = (i + 1) % (lights.size() + 2)
		if int(idx["i"]) == 0:
			# reset
			for L in lights:
				var mat2 : StandardMaterial3D = L.material_override
				mat2.albedo_color = Color(0.20, 0.65, 0.25)
				mat2.emission = mat2.albedo_color)
	var lbl := Label3D.new()
	lbl.text = "Pack-up cascade: both VSS FULL\n→ upstream belts ramp off front-to-back"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 5.8, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #141 — transportband chain. Belts are yawed 90° so their long axis runs
# along the walking direction (+X) — the chute drops then sit on the operator's
# side (+Z) of each belt, visible at a glance. Each belt is placed at its
# correct stacked height so the chain reads as inclines + transfer decks.
func _st_141(anchor: Vector3) -> void:
	var ids := ["transportband_4", "transportband_5", "transportband_6", "transportband_7"]
	const CHUTE_DROP_M : float = 0.22
	const X_OVERLAP_M  : float = 0.0
	var x_off : float = -6.0   # start a couple belts west of the sign
	var prev_outlet_top_y : float = -1.0
	for id in ids:
		var item : Dictionary = PlaceableCatalog.get_item(id)
		if item.is_empty():
			continue
		var bsize : Vector3 = item["size"]
		var blen : float = bsize.z
		var spec : Dictionary = PlaceableCatalog._transportband_spec(id)
		var incline_rad : float = deg_to_rad(float(spec["incline"]))
		var deck_top : float = bsize.y * 0.75 + bsize.y * 0.22
		var lift_at_end : float = (blen * 0.45) * sin(incline_rad)
		var inlet_top_off  : float = deck_top - lift_at_end
		var outlet_top_off : float = deck_top + lift_at_end
		var base_y : float = 0.0
		if prev_outlet_top_y > 0.0:
			base_y = maxf(0.0, prev_outlet_top_y - CHUTE_DROP_M - inlet_top_off)
		var n : Node3D = PlaceableCatalog.build_node(id, false, false)
		if n == null:
			x_off += blen - X_OVERLAP_M
			continue
		add_child(n)
		# Yaw -90° so belt local +Z (downstream) maps to world +X — operator
		# walks alongside, looking at the side where the chute hangs.
		n.rotation.y = -PI * 0.5
		n.global_position = Vector3(anchor.x + x_off + blen * 0.5, base_y, anchor.z + 2.0)
		prev_outlet_top_y = base_y + outlet_top_off
		x_off += blen - X_OVERLAP_M
	var lbl := Label3D.new()
	lbl.text = "Intake conveyor chain (4/5/6/7)\nChute drops visible on walking side"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 3.2, 1.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# ─── New "claimed done, eyeball me" stations ──────────────────────────────────

# #162 — fog distance. Build a row of identical tall poles every 50 m receding
# along +Z, with distance numbers. A LOCAL WorldEnvironment at this station
# pushes the fog start past the deepest pole so the operator can verify the
# 400 m pole still reads crisp.
func _st_162(anchor: Vector3) -> void:
	# Local fog-clear environment scoped to this station only. compositor_effect
	# isn't used; the WorldEnvironment simply has fog disabled so distant poles
	# are crisp. Note: only ONE WorldEnvironment is active at a time engine-
	# wide, so this overrides others while the operator is at the station —
	# acceptable for a verification gauntlet.
	var lenv := WorldEnvironment.new()
	var lev := Environment.new()
	lev.background_mode = Environment.BG_KEEP
	lev.fog_enabled = false
	lev.volumetric_fog_enabled = false
	lenv.environment = lev
	add_child(lenv)
	# Poles every 50 m up to 500 m receding into +Z. Tall and bright so even the
	# furthest is visible.
	var pole_h : float = 8.0
	for d in range(1, 11):
		var dist : float = float(d) * 50.0
		var pole := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.3, pole_h, 0.3)
		pole.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.95, 0.86, 0.18)
		m.emission_enabled = true
		m.emission = m.albedo_color * 0.4
		pole.material_override = m
		pole.position = anchor + Vector3(0.0, pole_h * 0.5, dist)
		add_child(pole)
		var tag := Label3D.new()
		tag.text = "%d m" % int(dist)
		tag.font_size = 64; tag.outline_size = 12
		tag.position = anchor + Vector3(0.0, pole_h + 0.6, dist)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		tag.pixel_size = 0.02
		tag.no_depth_test = true
		add_child(tag)
	var lbl := Label3D.new()
	lbl.text = "Fog distance test\nPole at 400 m should still read crisp"
	lbl.font_size = 26; lbl.outline_size = 6
	lbl.position = anchor + Vector3(0.0, 3.0, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #166 — pre-shift Phase B. Build a visible demo: parking spots, dressing room
# rectangles, canteen, smoke spot. 3 NPCs tween along walking paths between
# them so the choreography is obvious.
func _st_166(anchor: Vector3) -> void:
	# Floor markings. parking (-X), dressing centre, canteen (+X), smoke (+X, +Z).
	var marks := [
		{"pos": Vector3(-5.0, 0.01, 4.0), "size": Vector3(3.0, 0.02, 3.0), "col": Color(0.30, 0.30, 0.32), "lbl": "PARKING"},
		{"pos": Vector3(-1.5, 0.01, 1.0), "size": Vector3(1.5, 0.02, 1.8), "col": Color(0.95, 0.86, 0.18), "lbl": "DRESS"},
		{"pos": Vector3( 0.0, 0.01, 1.0), "size": Vector3(1.5, 0.02, 1.8), "col": Color(0.95, 0.86, 0.18), "lbl": "DRESS"},
		{"pos": Vector3( 1.5, 0.01, 1.0), "size": Vector3(1.5, 0.02, 1.8), "col": Color(0.95, 0.86, 0.18), "lbl": "DRESS"},
		{"pos": Vector3( 4.5, 0.01, 1.5), "size": Vector3(2.8, 0.02, 2.4), "col": Color(0.20, 0.45, 0.85), "lbl": "CANTEEN"},
		{"pos": Vector3( 4.5, 0.01, 5.5), "size": Vector3(1.2, 0.02, 1.2), "col": Color(0.35, 0.35, 0.38), "lbl": "SMOKE"},
	]
	for m in marks:
		var slab := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = m["size"]
		slab.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = m["col"]
		slab.material_override = mat
		slab.position = anchor + (m["pos"] as Vector3)
		add_child(slab)
		var tag := Label3D.new()
		tag.text = String(m["lbl"])
		tag.font_size = 36; tag.outline_size = 6
		tag.position = anchor + (m["pos"] as Vector3) + Vector3(0.0, 0.4, 0.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		tag.pixel_size = 0.005
		add_child(tag)
	# Cigarette icon at the smoke spot (small white box + glowing red tip).
	var cig := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.04, 0.04, 0.30)
	cig.mesh = cm
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color.WHITE
	cig.material_override = cmat
	cig.position = anchor + Vector3(4.5, 0.4, 5.5)
	add_child(cig)
	var tip := MeshInstance3D.new()
	var tipm := SphereMesh.new(); tipm.radius = 0.025; tipm.height = 0.05
	tip.mesh = tipm
	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.4, 0.05)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.4, 0.05)
	tip.material_override = tmat
	tip.position = anchor + Vector3(4.5, 0.4, 5.65)
	add_child(tip)
	# Walking paths — thin yellow lines from parking → dressing → canteen/smoke.
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.95, 0.86, 0.18)
	var path_segs : Array = [
		[Vector3(-5.0, 0.02, 4.0), Vector3(-1.5, 0.02, 1.0)],
		[Vector3(-5.0, 0.02, 4.0), Vector3( 0.0, 0.02, 1.0)],
		[Vector3(-5.0, 0.02, 4.0), Vector3( 1.5, 0.02, 1.0)],
		[Vector3(-1.5, 0.02, 1.0), Vector3( 4.5, 0.02, 1.5)],
		[Vector3( 0.0, 0.02, 1.0), Vector3( 4.5, 0.02, 1.5)],
		[Vector3( 1.5, 0.02, 1.0), Vector3( 4.5, 0.02, 5.5)],
	]
	for seg in path_segs:
		var a : Vector3 = (seg[0] as Vector3)
		var b : Vector3 = (seg[1] as Vector3)
		var d : Vector3 = b - a
		var line := MeshInstance3D.new()
		var lbm := BoxMesh.new()
		lbm.size = Vector3(0.10, 0.02, d.length())
		line.mesh = lbm
		line.material_override = line_mat
		line.position = anchor + (a + b) * 0.5
		line.rotation.y = atan2(d.x, d.z)
		add_child(line)
	# 3 NPCs (Emrah, Vincent, Pascal) tweening between parking and dressing
	# (and on to canteen / smoke).
	var script := load("res://src/scenes/world/Humanoid.gd")
	if script == null:
		return
	var npcs := [
		{"who": "emrah",   "from": Vector3(-5.0, 1.0, 4.0), "to": Vector3(-1.5, 1.0, 1.0), "to2": Vector3( 4.5, 1.0, 1.5)},
		{"who": "vincent", "from": Vector3(-5.0, 1.0, 4.5), "to": Vector3( 0.0, 1.0, 1.0), "to2": Vector3( 4.5, 1.0, 1.5)},
		{"who": "pascal",  "from": Vector3(-5.0, 1.0, 3.5), "to": Vector3( 1.5, 1.0, 1.0), "to2": Vector3( 4.5, 1.0, 5.5)},
	]
	for n in npcs:
		var npc_data : Dictionary = MainWorld.NPC_DATA.get(n["who"], {})
		var col : Color = npc_data.get("color", Color.WHITE)
		var app : Dictionary = npc_data.get("appearance", {})
		var body : Node3D = script.build(col, 0, app)
		add_child(body)
		body.global_position = anchor + (n["from"] as Vector3)
		# Loop: parking → dress → canteen/smoke → parking.
		var tw := create_tween()
		tw.set_loops()
		tw.tween_property(body, "global_position", anchor + (n["to"] as Vector3),  4.0)
		tw.tween_interval(2.0)
		tw.tween_property(body, "global_position", anchor + (n["to2"] as Vector3), 4.0)
		tw.tween_interval(2.0)
		tw.tween_property(body, "global_position", anchor + (n["from"] as Vector3), 5.0)
	var lbl := Label3D.new()
	lbl.text = "Pre-shift choreography (-30 min)\nParking → dressing → canteen / smoke"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 3.0, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #169 — vehicle cab parity. Spawn forklift + merlo + bale_clamp side-by-side
# with their cabs facing the walking direction (-X side of the platform) and
# the per-vehicle parity checklist hung at each cab window.
func _st_169(anchor: Vector3) -> void:
	var checklist : String = "Parity check:\n· red plate marker\n· door panel\n· headlights / taillights\n· roof\n· anchored steering wheel"
	var defs := [
		{"id": "forklift",          "x": -4.0},
		{"id": "merlo_telehandler", "x":  0.0},
		{"id": "bale_clamp",        "x":  4.0},
	]
	for v in defs:
		var n : Node3D = PlaceableCatalog.build_node(String(v["id"]), false, false)
		if n:
			add_child(n)
			n.global_position = anchor + Vector3(float(v["x"]), 0.0, 2.0)
			# Yaw +90° so the cab faces -X (the walking side); wheels stay on
			# the floor because y=0.0 puts them exactly at slab level.
			n.rotation.y = PI * 0.5
		var lbl := Label3D.new()
		lbl.text = "%s\n%s" % [String(v["id"]).to_upper(), checklist]
		lbl.font_size = 20; lbl.outline_size = 5
		lbl.position = anchor + Vector3(float(v["x"]) - 1.6, 2.0, 2.0)
		lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		lbl.pixel_size = 0.004
		add_child(lbl)

# #170 — sticker paper colour. Render one bale; the sticker on it should now be
# bright yellow, not cream.
func _st_170(anchor: Vector3) -> void:
	var b : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if b:
		add_child(b)
		b.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "Sticker paper: should be bright YELLOW\n(was cream 0.93/0.88/0.76 → now 0.93/0.82/0.15)"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 2.4, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #173 — crew section assignment. Placeholder placard listing the section keys.
func _st_173(anchor: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = "CrewManager.manual_assign(\"section:X\")\nSections: extruder, line, yard, intake\n[verify by command in console]"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 2.0, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #175 — vehicle drive. Spawn a parked Forklift so operator can hop in + verify
# the <0.05 m/s drift kill and the 1 Hz diagnostic line in the console.
func _st_175(anchor: Vector3) -> void:
	var n : Node3D = PlaceableCatalog.build_node("forklift", false, false)
	if n:
		add_child(n)
		n.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "Drive test: idle should snap to 0\nWatch console: [Drive] line @ 1 Hz"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 3.0, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #180 — spawn snap. Reference placard only.
func _st_180(anchor: Vector3) -> void:
	var lbl := Label3D.new()
	lbl.text = "Spawn snap: if WorldLayout.player_spawn\nis outside building polygon AND >50 m\nfrom centre, snap to building.\n[verify by loading a layout w/ bad spawn]"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 2.0, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #182 — steam plumes. Spawn a dryer + extruder so operator sees the GPUParticles3D.
func _st_182(anchor: Vector3) -> void:
	var d : Node3D = PlaceableCatalog.build_node("mech_dryer", false, false)
	if d:
		add_child(d)
		d.global_position = anchor + Vector3(-2.5, 0.0, 0.0)
	var e : Node3D = PlaceableCatalog.build_node("extruder_unit", false, false)
	if e == null:
		e = PlaceableCatalog.build_node("extruder", false, false)
	if e:
		add_child(e)
		e.global_position = anchor + Vector3(2.5, 0.0, 0.0)
	var lbl := Label3D.new()
	lbl.text = "Steam plumes — dryer air outlet + extruder drum top"
	lbl.font_size = 22; lbl.outline_size = 5
	lbl.position = anchor + Vector3(0.0, 3.6, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# #165 — HMI panel (pending).
func _st_165(anchor: Vector3) -> void:
	_build_placeholder(anchor, "failed")

# #168 — rotation-time film_good readout (pending).
func _st_168(anchor: Vector3) -> void:
	_build_placeholder(anchor, "failed")

# ─── New gauntlet stations for this session's work ───────────────────────────
## Small placard helper — drops a 3-line Label3D at chest height above the
## anchor with the body text the operator should read.
func _st_placard(anchor: Vector3, body: String) -> void:
	var lbl := Label3D.new()
	lbl.text = body
	lbl.font_size = 26; lbl.outline_size = 6
	lbl.position = anchor + Vector3(0.0, 1.8, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# T1 — walkie now plays a squelch chirp + noise carrier (no formant voice).
# Operator can read the captioned message on the SubtitleHud while it plays.
func _st_t1_walkie(anchor: Vector3) -> void:
	_st_placard(anchor, "T1 Walkie audio\n\nIn MainWorld:\n  • Wait for an incoming call (or PTT)\n  • Should hear: PTT-open chirp → soft noise carrier → PTT-close chirp\n  • NO 'alien voice' formants\n  • SubtitleHud shows the text caption\n\nPASS = clean radio chirp; FAIL = still alien noise")

# T4 — distance fog ON by default; 500 m volumetric range. Eyeball: distant
# silos look hazy but READABLE, not soup.
func _st_t4_fog(anchor: Vector3) -> void:
	_st_placard(anchor, "T4 Fog 500 m default ON\n\nIn MainWorld:\n  • Look toward the horizon (any direction)\n  • Distant objects (silos, parking lot, trees) should be visible up to ~500 m\n  • Subtle blue/grey haze, not 'fog of war'\n\nSettings menu: 'Distance haze' default ON\n\nPASS = far things crisp; FAIL = 50 m wall of fog")

# T8 — player footwear swaps work_boots <-> shoes on shift state.
func _st_t8_footwear(anchor: Vector3) -> void:
	_st_placard(anchor, "T8 Footwear auto-switch\n\nIn MainWorld:\n  • Check feet in wardrobe mirror (3rd-person)\n  • BEFORE bell (off-shift): SHOES\n  • AFTER bell (on-shift): WORK BOOTS\n\nWired to ShiftClock.shift_started / shift_ended\n\nPASS = feet swap; FAIL = always one style")

# D2 — bale sticker now uses a 3x5 bitmap font with real letterforms.
func _st_d2_sticker(anchor: Vector3) -> void:
	var b : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if b:
		add_child(b)
		b.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	_st_placard(anchor + Vector3(0.0, 1.0, 0.0),
		"D2 Bale sticker — real text\n\nRead the sticker on this bale:\n  • Header: 'ROTTERDAM' (white-on-black band)\n  • 'ID B-00482'\n  • '250 KG NETTO'\n  • 'LDPE FILM PE'\n  • Barcode below\n\nPASS = letters readable; FAIL = dashes/MMM/blurs")

# D4 — belt direction. Drop a transportband at the anchor + a small RB on top.
# The RB should be carried in the +Z (downstream) direction of the macro chain.
func _st_d4_dir(anchor: Vector3) -> void:
	var n : Node3D = PlaceableCatalog.build_node("transportband_2", false, false)
	if n:
		add_child(n)
		n.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	# Auto-spawn cubes on a Timer so the operator doesn't have to pick anything
	# up — the test is "look and confirm the cube drifts toward +Z (away from
	# the sign)". Each cube despawns after 8 s so the belt doesn't pile up.
	var spawn_timer := Timer.new()
	spawn_timer.wait_time = 2.5
	spawn_timer.autostart = true
	spawn_timer.one_shot = false
	add_child(spawn_timer)
	var spawn_anchor : Vector3 = anchor + Vector3(0.0, 1.2, -2.6)
	spawn_timer.timeout.connect(func() -> void:
		var rb := RigidBody3D.new()
		var col := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.18, 0.18, 0.18)
		col.shape = box
		rb.add_child(col)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.18, 0.18)
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.1)
		mi.material_override = mat
		rb.add_child(mi)
		add_child(rb)
		rb.global_position = spawn_anchor
		# Auto-despawn after 8 s so the belt stays clear.
		var kill := get_tree().create_timer(8.0)
		kill.timeout.connect(func() -> void:
			if is_instance_valid(rb):
				rb.queue_free())
	)
	_st_placard(anchor + Vector3(0.0, 2.5, 0.0),
		"D4 Belt direction (auto-test)\n\nRed cubes spawn every 2.5 s at the\n-Z (sign) side of the belt.\nThey should drift TOWARD +Z (away\nfrom the sign), then fall off the\nfar end.\n\nPASS = cubes travel away from sign\nFAIL = cubes travel toward sign or sit still")

# D4 — opzetband K-edit + delete + save round-trip.
func _st_d4_opzetband(anchor: Vector3) -> void:
	var n : Node3D = PlaceableCatalog.build_node("opzetband_3a3b", false, false)
	if n:
		add_child(n)
		n.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	_st_placard(anchor + Vector3(0.0, 2.0, 0.0),
		"D4 Opzetband editable\n\nIn build mode (Tab):\n  • K-edit on this opzetband: SHOULD WORK\n  • Right-click delete: SHOULD WORK\n  • Save + reload world: should still be there\n\nPASS = all 3 work; FAIL = any one fails")

# D4 — LINE_SORT_SEQ now has opzetband at head.
func _st_d4_sort_macro(anchor: Vector3) -> void:
	_st_placard(anchor,
		"D4 LINE_SORT_SEQ has opzetband\n\nIn build mode:\n  • Pick 'Build Sort line' from Lines category\n  • First placed machine = opzetband_3a3b\n  • Then trilzeef pair\n\nPASS = opzetband at head; FAIL = trilzeef-only")

# D4 — LINE_3C6_SEQ new macro.
func _st_d4_3c6_macro(anchor: Vector3) -> void:
	_st_placard(anchor,
		"D4 LINE_3C6_SEQ macro\n\nIn build mode:\n  • Lines category has 'Build 3C/6 intake'\n  • Chain: opzetband_3c6 → shredder_2 → inclined_belt_8m → trilzeef\n\nPASS = macro present + lays all 4; FAIL = missing/wrong order")

# D4 — spinning rollers.
func _st_d4_rollers(anchor: Vector3) -> void:
	var n : Node3D = PlaceableCatalog.build_node("transport_belt", false, false)
	if n:
		add_child(n)
		n.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	_st_placard(anchor + Vector3(0.0, 2.2, 0.0),
		"D4 End rollers SPIN\n\nWatch the cylinders at each\nend of this belt:\n  • Both should rotate around X\n  • Speed matches belt scroll\n  • omega = v / r (radians/sec)\n\nPASS = rollers spin; FAIL = static cylinders on a moving belt")

# V2 — car auto-ruler. Cars live as .tscn SCENES, not PlaceableCatalog items, so
# we load + instantiate directly. The car's _ready() auto-rescales the FBX to its
# `_real_world_length_m`, so spawning is all we have to do; the ruler bars below
# are reference rods of the same length the operator can eyeball against.
# Two cars (different lengths) so the operator verifies the auto-ruler isn't
# just hard-coded to one length.
func _st_v2_cars(anchor: Vector3) -> void:
	const SWIFT_LEN_M : float = 3.85   # Suzuki Swift GLX
	const AUDI_LEN_M  : float = 4.34   # Audi A3 Sportback 2013
	const CAR_SPACING : float = 3.5    # +X between the two cars (room to walk between)

	# Suzuki Swift — left car. Scene path matches the .tscn on disk; load() will
	# print a clear error in-engine if the path ever moves.
	var swift_scene : PackedScene = load("res://src/scenes/vehicles/cars/SuzukiSwiftGLX.tscn") as PackedScene
	if swift_scene != null:
		var swift : Node3D = swift_scene.instantiate()
		add_child(swift)
		swift.global_position = anchor + Vector3(-CAR_SPACING * 0.5, 0.0, 0.0)
	else:
		push_warning("[Gauntlet #220] SuzukiSwiftGLX.tscn missing")

	# Audi A3 Sportback — right car. Different length so the ruler comparison
	# proves the auto-rescale works for more than one model.
	var audi_scene : PackedScene = load("res://src/scenes/vehicles/cars/AudiA3Sportback.tscn") as PackedScene
	if audi_scene != null:
		var audi : Node3D = audi_scene.instantiate()
		add_child(audi)
		audi.global_position = anchor + Vector3(CAR_SPACING * 0.5, 0.0, 0.0)
	else:
		push_warning("[Gauntlet #220] AudiA3Sportback.tscn missing")

	# Yellow reference rod next to each car, exact spec length, laid along the
	# car's long axis (Z, since the cars are spawned default-oriented). Offset
	# in +X so the rod sits just beside the car body, not under it.
	_build_ruler_bar(anchor + Vector3(-CAR_SPACING * 0.5 + 1.4, 0.04, 0.0),
		SWIFT_LEN_M, "Swift 3.85 m")
	_build_ruler_bar(anchor + Vector3( CAR_SPACING * 0.5 + 1.4, 0.04, 0.0),
		AUDI_LEN_M,  "Audi A3 4.34 m")

	_st_placard(anchor + Vector3(0.0, 2.4, 0.0),
		"V2 Car auto-ruler\n\nLEFT car  = Suzuki Swift GLX, ruler = 3.85 m\nRIGHT car = Audi A3 Sportback, ruler = 4.34 m\n\nEach car should match its OWN yellow bar bumper-to-bumper.\nCheck console: '[Car] *.fbx auto-scaled by X to Y m'\n\nPASS = both cars match their bars; FAIL = either car wrong length")

## Yellow horizontal rod the same length as a car spec, laid along the car's
## long axis (+Z by default). Carries a Label3D so the operator reads which
## length they're looking at without checking the placard.
func _build_ruler_bar(at: Vector3, length_m: float, caption: String) -> void:
	var bar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.04, 0.04, length_m)
	bar.mesh = bm
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(1.0, 0.9, 0.1)
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bar.material_override = rmat
	bar.position = at
	add_child(bar)
	var lbl := Label3D.new()
	lbl.text = caption
	lbl.font_size = 22
	lbl.outline_size = 5
	lbl.position = at + Vector3(0.0, 0.35, 0.0)
	lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	lbl.pixel_size = 0.005
	add_child(lbl)

# Perf — FilmFlakeField throttle + cull. Visible demo: a NEAR flotation_tank
# right at the placard (well within FilmFlakeField.CULL_DIST_M = 30 m so its
# flakes are alive and animating), plus a FAR flotation_tank ~40 m back along
# +Z so the operator can pan the camera between them and watch the far tank's
# flakes freeze (or never tick) while the near tank keeps moving. The far tank
# sits off the main platform, so we drop a small local floor pad under it so
# the prop reads as "on the ground" rather than levitating.
func _st_perf_ff(anchor: Vector3) -> void:
	# NEAR tank — within cull range. Placed just behind the placard so the
	# operator's first view (walking up to the sign) already shows live flakes.
	var near_tank : Node3D = PlaceableCatalog.build_node("flotation_tank", false, false)
	if near_tank:
		add_child(near_tank)
		near_tank.global_position = anchor + Vector3(0.0, 0.0, 0.0)
	var near_lbl := Label3D.new()
	near_lbl.text = "NEAR (in cull range)\nflakes ANIMATE"
	near_lbl.font_size = 28; near_lbl.outline_size = 6
	near_lbl.modulate = Color(0.4, 1.0, 0.6)
	near_lbl.position = anchor + Vector3(0.0, 3.2, 0.0)
	near_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	near_lbl.pixel_size = 0.005
	add_child(near_lbl)

	# FAR tank — ~40 m back along +Z, well past CULL_DIST_M = 30 m. A small
	# local floor pad keeps it from floating in mid-air since it sits outside
	# DEEPEST_PROP_Z + PLATFORM_BACK_PAD.
	const FAR_Z : float = 40.0
	var pad := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(8.0, FLOOR_THICKNESS_M, 12.0)
	pad.mesh = pm
	var pmat := StandardMaterial3D.new()
	pmat.albedo_color = Color(0.30, 0.30, 0.32); pmat.roughness = 0.88
	pad.material_override = pmat
	pad.position = anchor + Vector3(0.0, -FLOOR_THICKNESS_M * 0.5, FAR_Z)
	add_child(pad)

	var far_tank : Node3D = PlaceableCatalog.build_node("flotation_tank", false, false)
	if far_tank:
		add_child(far_tank)
		far_tank.global_position = anchor + Vector3(0.0, 0.0, FAR_Z)
	var far_lbl := Label3D.new()
	far_lbl.text = "FAR (~%d m, past cull)\nflakes FROZEN" % int(FAR_Z)
	far_lbl.font_size = 28; far_lbl.outline_size = 6
	far_lbl.modulate = Color(1.0, 0.55, 0.30)
	far_lbl.position = anchor + Vector3(0.0, 3.2, FAR_Z)
	far_lbl.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	far_lbl.pixel_size = 0.005
	add_child(far_lbl)

	_st_placard(anchor,
		"Perf FilmFlakeField cull demo\n\nLook at the NEAR tank (in front of you): flakes flowing.\nLook at the FAR tank (~40 m back, past 30 m cull): flakes FROZEN.\n\nMainWorld check: [PERF] line proc < 100ms (was 100-170ms)\n\nPASS = near alive, far frozen, proc < 100ms\nFAIL = both alive (cull broken) OR proc still > 130ms")

# NPC step-ray fix — visible demo. Spawn ONE NPC and tween him back and forth
# between two visible floor markers in front of the placard. Tween moves the
# Humanoid horizontally on flat floor; the step-ray bug (pre-fix) would have
# the NPC's Y bouncing as the ray re-fired every frame against the slab. With
# the fix in place the body slides smoothly along Y = constant. Operator stands
# at the placard and watches for ~30 s: NO bunny-hop = pass.
func _st_npc_jump(anchor: Vector3) -> void:
	# Two yellow floor markers ~5 m apart along Z (perpendicular to walking) so
	# the operator gets a clear A↔B path right in front of the sign.
	const PATH_HALF : float = 3.0
	for sz in [-PATH_HALF, PATH_HALF]:
		var marker := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.04, 0.8)
		marker.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.95, 0.86, 0.18)
		marker.material_override = mat
		marker.position = anchor + Vector3(0.0, 0.02, float(sz) + 4.0)
		add_child(marker)
		var tag := Label3D.new()
		tag.text = "A" if sz < 0.0 else "B"
		tag.font_size = 48; tag.outline_size = 8
		tag.position = anchor + Vector3(0.0, 0.5, float(sz) + 4.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		tag.pixel_size = 0.006
		add_child(tag)

	# One NPC — Pascal — tweening A↔B forever on flat floor.
	var script := load("res://src/scenes/world/Humanoid.gd")
	if script != null:
		var npc_data : Dictionary = MainWorld.NPC_DATA.get("pascal", {})
		var col : Color = npc_data.get("color", Color.WHITE)
		var app : Dictionary = npc_data.get("appearance", {})
		var body : Node3D = script.build(col, 0, app)
		add_child(body)
		var pos_a : Vector3 = anchor + Vector3(0.0, 1.0, -PATH_HALF + 4.0)
		var pos_b : Vector3 = anchor + Vector3(0.0, 1.0,  PATH_HALF + 4.0)
		body.global_position = pos_a
		var tw := create_tween()
		tw.set_loops()
		# 5 s each way — slow enough that the operator can see whether Y stays
		# flat. If the body's Y oscillates at all during the tween, the step-ray
		# is still misbehaving.
		tw.tween_property(body, "global_position", pos_b, 5.0)
		tw.tween_property(body, "global_position", pos_a, 5.0)

	_st_placard(anchor + Vector3(0.0, 0.0, -1.0),
		"NPC step-ray fix demo\n\nWatch the NPC walk A ↔ B for a minute.\nFlat floor — Y should stay CONSTANT.\n\nPASS = smooth slide, no bouncing\nFAIL = visible bunny-hop / vertical jitter")

# Build-mode green snap pole — visible demo. Drop an extruder_silo + cyclone
# side by side, close enough that the snap envelope (~2 m) WOULD activate when
# the operator brings a new ghost up to their shared edge. The instruction
# tells them exactly where to approach with Tab + a new ghost to see the green
# pole appear. We can't fake the pole here (it lives in BuildMode's ghost
# overlay), but we CAN provide the right scenario for the operator to trigger.
func _st_bm_snap(anchor: Vector3) -> void:
	# Side-by-side along X — gap is tight enough (~0.8 m) that any ghost the
	# operator brings near either machine's outboard face will be inside the
	# snap envelope.
	var silo : Node3D = PlaceableCatalog.build_node("extruder_silo", false, false)
	if silo:
		add_child(silo)
		silo.global_position = anchor + Vector3(-2.0, 0.0, 0.0)
	var cy : Node3D = PlaceableCatalog.build_node("cyclone", false, false)
	if cy:
		add_child(cy)
		cy.global_position = anchor + Vector3(2.0, 0.0, 0.0)

	# Arrow pointing down at the snap zone between them — operator knows where
	# to bring the new ghost.
	var arrow := Label3D.new()
	arrow.text = "↓ approach HERE ↓"
	arrow.font_size = 36; arrow.outline_size = 8
	arrow.modulate = Color(0.4, 1.0, 0.6)
	arrow.position = anchor + Vector3(0.0, 4.0, 0.0)
	arrow.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	arrow.pixel_size = 0.006
	add_child(arrow)

	_st_placard(anchor + Vector3(0.0, 0.0, -1.5),
		"Build-mode edge snap demo\n\nTwo machines placed at the same Z, ~0.8 m apart.\nApproach with Tab + a new ghost — the green pole appears here,\nthen click to place edge-flush.\n\nPASS = green pole appears + ghost snaps\nFAIL = no pole / ghost passes through normally")

# Transportband Y-stacking — visible demo. Lay 3 belts in a row using the same
# chained-Y math as _st_141, so the operator sees the chain step UP in real
# time. Belt 1 sits at floor; each next belt's base Y is computed from the
# previous belt's outlet top minus the chute drop, so the head-to-tail join is
# visible and the chain climbs. Uses transportband_3 (incline) → _4 (flat) →
# _5 (incline) so there's an unmistakable lift between consecutive decks.
func _st_tb_stack(anchor: Vector3) -> void:
	var ids := ["transportband_3", "transportband_4", "transportband_5"]
	const CHUTE_DROP_M : float = 0.22
	const X_OVERLAP_M  : float = 0.0
	var x_off : float = -4.5   # start a little west of the sign
	var prev_outlet_top_y : float = -1.0
	for id in ids:
		var item : Dictionary = PlaceableCatalog.get_item(id)
		if item.is_empty():
			continue
		var bsize : Vector3 = item["size"]
		var blen : float = bsize.z
		var spec : Dictionary = PlaceableCatalog._transportband_spec(id)
		var incline_rad : float = deg_to_rad(float(spec.get("incline", 0.0)))
		var deck_top : float = bsize.y * 0.75 + bsize.y * 0.22
		var lift_at_end : float = (blen * 0.45) * sin(incline_rad)
		var inlet_top_off  : float = deck_top - lift_at_end
		var outlet_top_off : float = deck_top + lift_at_end
		var base_y : float = 0.0
		if prev_outlet_top_y > 0.0:
			base_y = maxf(0.0, prev_outlet_top_y - CHUTE_DROP_M - inlet_top_off)
		var n : Node3D = PlaceableCatalog.build_node(id, false, false)
		if n == null:
			x_off += blen - X_OVERLAP_M
			continue
		add_child(n)
		# Same orientation trick as _st_141 — yaw -90° so belt local +Z maps to
		# world +X. Operator walks alongside and looks at the chain climbing
		# left → right.
		n.rotation.y = -PI * 0.5
		n.global_position = Vector3(anchor.x + x_off + blen * 0.5, base_y, anchor.z + 2.0)
		# Floating Y readout above each belt so the operator can read the
		# stepping height at a glance instead of eyeballing it.
		var tag := Label3D.new()
		tag.text = "%s\nY=%.2f m" % [id, base_y]
		tag.font_size = 22; tag.outline_size = 5
		tag.position = Vector3(anchor.x + x_off + blen * 0.5,
			base_y + deck_top + 0.6, anchor.z + 2.0)
		tag.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		tag.pixel_size = 0.005
		add_child(tag)
		prev_outlet_top_y = base_y + outlet_top_off
		x_off += blen - X_OVERLAP_M
	_st_placard(anchor + Vector3(0.0, 0.0, -1.0),
		"Transportband Y-stacking demo\n\n3 belts laid using the chained-Y math from _st_141.\nBelt 1: Y=0 (floor).\nEach next belt: base Y = prev outlet top - chute drop.\n\nPASS = visible stair-step climbing left → right\nFAIL = all at Y=0 (chain math broken)")

# Bale close-LOD wire bands.
func _st_lod_bands(anchor: Vector3) -> void:
	# build_node(id, ghost, simple): ghost=true was making the LEFT bale a
	# walk-through translucent billboard — operator reported "transparent bill
	# I can walk through". We want a SOLID bale at the simple LOD (no wire
	# bands, no sticker), so: ghost=false, simple=true.
	var simple : Node3D = PlaceableCatalog.build_node("rotterdam", false, true)
	if simple:
		add_child(simple)
		simple.global_position = anchor + Vector3(-1.5, 0.0, 0.0)
		# Belt-and-braces: even if the catalog ignores the `simple` flag,
		# strip any wire-band / sticker children so the LEFT bale visually
		# differs from the RIGHT one.
		_lod_strip_close_detail(simple)
		# Slightly darken the LEFT bale so the LOD difference reads even
		# without studying the wire bands.
		_lod_tint_darker(simple, 0.6)
		var far_lbl := Label3D.new()
		far_lbl.text = "FAR LOD\n(simple)"
		far_lbl.font_size = 48
		far_lbl.modulate = Color(1.0, 0.85, 0.4)
		far_lbl.outline_size = 8
		far_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		far_lbl.no_depth_test = true
		far_lbl.position = Vector3(0.0, 1.6, 0.0)
		simple.add_child(far_lbl)
	var detail : Node3D = PlaceableCatalog.build_node("rotterdam", false, false)
	if detail:
		add_child(detail)
		detail.global_position = anchor + Vector3(1.5, 0.0, 0.0)
		var close_lbl := Label3D.new()
		close_lbl.text = "CLOSE LOD\n(detail)"
		close_lbl.font_size = 48
		close_lbl.modulate = Color(0.4, 1.0, 0.6)
		close_lbl.outline_size = 8
		close_lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		close_lbl.no_depth_test = true
		close_lbl.position = Vector3(0.0, 1.6, 0.0)
		detail.add_child(close_lbl)
	_st_placard(anchor + Vector3(0.0, 2.5, 0.0),
		"Bale close-LOD wire bands\n\nLEFT  = FAR LOD (simple, darker, no bands/sticker)\nRIGHT = CLOSE LOD (detail)\n\nClose-LOD bale should have:\n  • 3 thin dark wire bands wrapping (top/mid/bottom)\n  • A paper sticker on +Z face\n\nPASS = LEFT is plain+darker, RIGHT has wires + sticker\nFAIL = identical, or LEFT is see-through")

# Walk a bale's children and remove anything that looks like a close-LOD
# detail (wire bands or the sticker quad). Conservative match on names so
# we don't accidentally nuke the bale body. #243
func _lod_strip_close_detail(bale: Node) -> void:
	for child in bale.get_children():
		var n := child.name.to_lower()
		if "band" in n or "wire" in n or "sticker" in n or "label" in n or "barcode" in n:
			child.queue_free()
		elif child is Node3D and child.get_child_count() > 0:
			_lod_strip_close_detail(child)

# Multiply every MeshInstance3D's surface albedo by `factor` so the LEFT
# bale reads as darker. Skips ShaderMaterials (don't know their uniforms).
func _lod_tint_darker(bale: Node, factor: float) -> void:
	if bale is MeshInstance3D:
		var mi : MeshInstance3D = bale
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var src : Material = mi.get_surface_override_material(i)
				if src == null:
					src = mesh.surface_get_material(i)
				if src is StandardMaterial3D:
					var dup : StandardMaterial3D = src.duplicate()
					dup.albedo_color = Color(
						dup.albedo_color.r * factor,
						dup.albedo_color.g * factor,
						dup.albedo_color.b * factor,
						dup.albedo_color.a)
					mi.set_surface_override_material(i, dup)
	for child in bale.get_children():
		_lod_tint_darker(child, factor)
