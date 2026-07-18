extends Node3D
##
## Top-down RTS marker-placement scene. Loads the empty building shell, paints a
## satellite-image floor (via PDOK Luchtfoto WMS), and lets the user click to drop
## markers for: player spawn, vehicle spawns (per type), line starts (per line),
## and bale-yard rectangles. Saves to WorldLayout (user://world_layout.json).
##
## v1 scope: this scene does NOT run gameplay — it's purely a layout authoring
## tool. After Save the user returns to the main menu.
##

# Prefer the solidified shell (tools/solidify_building.gd); the raw thin .obj is the
# fallback. WorldSetup shifts whichever it loads to the local origin for display.
const BUILDING_OBJ        := "res://assets/models/CeDo_building.obj"
const BUILDING_SOLID      := "res://assets/models/CeDo_building_solid.res"
const SATELLITE_CACHE     := "user://satellite.png"
# PDOK Luchtfoto WMS — open Dutch aerial. EPSG:4326 keeps the bbox input simple
# (paste lat/lon corners straight from Google Maps).
const PDOK_WMS            := "https://service.pdok.nl/hwh/luchtfotorgb/wms/v1_0"
const PDOK_LAYER          := "Actueel_orthoHR"
const WMS_IMG_SIZE        := 1024

# Default lat/lon center of the CeDo plant in Sittard-Geleen (Krijtstraat area).
# User can change this in-scene; the field is just a starting hint.
const DEFAULT_LAT         := 50.9695
const DEFAULT_LON         := 5.8194
const DEFAULT_EXTENT_M    := 400.0

# Camera defaults — ORTHOGRAPHIC projection (no parallax: the building shell
# sits 67–112 m above the floor, and any perspective drift while panning made
# marker placement misalign on the far side of the building from the camera).
# `cam_size` is the orthographic viewport HEIGHT in metres (what world-height
# fills the screen). `CAM_Y` is the fixed Y the camera sits at — high enough
# above the tallest geometry (~112 m roof) that the building never clips into
# the camera. The clamp range below is for the ortho size, NOT a Y position.
const CAM_Y               := 600.0
const CAM_SIZE_DEFAULT    := 180.0
const CAM_SIZE_MIN        := 30.0
const CAM_SIZE_MAX        := 600.0
const CAM_PAN_SPEED       := 1.0   # world m per pixel of mouse drag

# Marker visual sizes — the world-space radius is rescaled with the ortho
# zoom so a dot stays roughly the same on-screen size at any zoom level.
# At cam_size = 180 m, the default radius works out to ~0.9 m (~7-8 px on a
# 1080-tall viewport); zoomed all the way out to 600 m it scales to 3 m so the
# dot remains clickable.
const MARKER_DOT_RADIUS_REF := 0.9      # radius at cam_size == 180 m
const MARKER_DOT_HEIGHT_REF := 1.8      # height at cam_size == 180 m
const MARKER_SIZE_REF_M     := 180.0
const YARD_PREVIEW_ALPHA    := 0.35

# Tool IDs (drive UI + click handler).
# `point`     — single point per tool id, replace on re-click (e.g. player spawn)
# `multi`     — append a new point on each click; right-click a marker to delete
# `polygon`   — collect 4 corners, then commit as a yard with a supplier
enum Tool {
	NONE,
	PLAYER_SPAWN,
	FACTORY_CENTER,
	VEHICLE_FORKLIFT,
	VEHICLE_BALE_CLAMP,
	VEHICLE_MERLO,
	VEHICLE_MERLO_P40,
	VEHICLE_MAST_LIFT,
	LINE_1, LINE_3A, LINE_3B, LINE_3C, LINE_6,
	BALE_YARD,
	# #221-PC Phase 5 — operator-draggable previously-hardcoded placements.
	STAFF_PARKING,
	PLAYER_SWIFT,
	COMPRESSOR_SPAWN,
}

# Tool metadata
const TOOL_DEFS := {
	Tool.PLAYER_SPAWN:       {"label": "Player spawn",            "color": Color.WHITE,         "kind": "point"},
	Tool.FACTORY_CENTER:     {"label": "Factory center",          "color": Color.MAGENTA,       "kind": "point"},
	Tool.VEHICLE_FORKLIFT:   {"label": "Forklift (click multi)",  "color": Color.ORANGE,        "kind": "multi"},
	Tool.VEHICLE_BALE_CLAMP: {"label": "Bale clamp (click multi)","color": Color.GOLD,          "kind": "multi"},
	Tool.VEHICLE_MERLO:      {"label": "Merlo (click multi)",     "color": Color.CRIMSON,       "kind": "multi"},
	Tool.VEHICLE_MERLO_P40:  {"label": "Merlo P40 (click multi)", "color": Color.ORANGE_RED,    "kind": "multi"},
	Tool.VEHICLE_MAST_LIFT:  {"label": "Mast lift (click multi)", "color": Color.LIGHT_BLUE,    "kind": "multi"},
	Tool.LINE_1:             {"label": "Line 1 start",            "color": Color.LIME_GREEN,    "kind": "point"},
	Tool.LINE_3A:            {"label": "Line 3A start",           "color": Color.SPRING_GREEN,  "kind": "point"},
	Tool.LINE_3B:            {"label": "Line 3B start",           "color": Color.TURQUOISE,     "kind": "point"},
	Tool.LINE_3C:            {"label": "Line 3C start",           "color": Color.AQUAMARINE,    "kind": "point"},
	Tool.LINE_6:             {"label": "Line 6 start",            "color": Color.SEA_GREEN,     "kind": "point"},
	Tool.BALE_YARD:          {"label": "Bale yard (4 corners)",   "color": Color.YELLOW,        "kind": "polygon"},
	# #221-PC Phase 5 — single-click placement of the parking lot anchor and
	# the player's parked Swift. Both formerly hardcoded; now draggable.
	Tool.STAFF_PARKING:      {"label": "Staff parking",           "color": Color.DEEP_SKY_BLUE, "kind": "point"},
	Tool.PLAYER_SWIFT:       {"label": "Player Swift (start)",    "color": Color.LIGHT_SALMON,  "kind": "point"},
	Tool.COMPRESSOR_SPAWN:   {"label": "Compressor spawn",        "color": Color.CYAN,          "kind": "point"},
}

# Tool → WorldLayout vehicle key. Map kept here so MainWorld's spawn code can
# look up the canonical id without knowing about the Tool enum.
const VEHICLE_TOOL_TO_ID := {
	Tool.VEHICLE_FORKLIFT:   "forklift",
	Tool.VEHICLE_BALE_CLAMP: "bale_clamp",
	Tool.VEHICLE_MERLO:      "merlo",
	Tool.VEHICLE_MERLO_P40:  "merlo_p40",
	Tool.VEHICLE_MAST_LIFT:  "mast_lift",
}
const LINE_TOOL_TO_ID := {
	Tool.LINE_1:  "1",
	Tool.LINE_3A: "3a",
	Tool.LINE_3B: "3b",
	Tool.LINE_3C: "3c",
	Tool.LINE_6:  "6",
}

# ── Runtime ──────────────────────────────────────────────────────────────────
var camera          : Camera3D
var ground_quad     : MeshInstance3D
var ground_material : StandardMaterial3D
var shell_center    : Vector3 = Vector3.ZERO   # building shell AABB centre (XZ used for quad)
var markers_root    : Node3D
var rect_preview    : MeshInstance3D
var cam_target      : Vector3 = Vector3.ZERO   # camera pans by moving its XZ target
var cam_size        : float   = CAM_SIZE_DEFAULT   # orthographic viewport height in metres
# Floor-plan overlay (the calibrated CeDo127 PDF used to align machine markers).
var plan_quad       : MeshInstance3D = null
var plan_material   : StandardMaterial3D = null
const FLOOR_PLAN_PATH := "res://assets/models/floor_plan.png"
var current_tool    : int     = Tool.NONE

# Mouse-drag state for moving an already-placed marker (corner or vehicle).
# Set on LMB-down if the cursor is near a draggable node; cleared on LMB-up.
var dragging_node   : Node3D = null
var dragging_kind   : String = ""        # "point" / "multi" / "yard_corner" / "pending_corner"
var dragging_tool   : int    = Tool.NONE # for "point"/"multi": tool id; for yard corners: index info
var dragging_yard_idx    : int = -1      # finalised yard array index when kind=="yard_corner"
var dragging_corner_idx  : int = -1      # which of the 4 corners is being moved
const DRAG_PICK_RADIUS_M : float = 3.0   # XZ tolerance for picking a marker on click-down

# UI refs (built in _build_ui)
var status_label    : Label
var lat_input       : LineEdit
var lon_input       : LineEdit
var extent_input    : LineEdit
var tool_buttons    : Dictionary = {}
var supplier_select : OptionButton = null
var yard_panel      : VBoxContainer = null    # whole "pending yard" sub-panel (hidden by default)
var yard_status_lbl : Label = null

# Single-instance point markers (player spawn, line starts).
var point_markers   : Dictionary = {}    # tool_id → MeshInstance3D

# Marker-group calibration (live, relative nudge — baked into saved coords on Save).
var _marker_cal_x   : float = 0.0
var _marker_cal_z   : float = 0.0
var _marker_cal_rot : float = 0.0
# The building shell's TRUE RD-scale centre (before it's shifted to the local origin
# for display). Used as the satellite-fetch geographic centre so re-fetch gets the
# real CeDo tile instead of an empty RD (0,0) white plane.
var _shell_rd_center : Vector3 = Vector3.ZERO

# Multi-instance vehicle markers — each vehicle tool can have N markers.
var multi_markers   : Dictionary = {}    # tool_id → Array[MeshInstance3D]

# Polygonal bale yards. A "pending" yard is currently being placed (≤ 4 corners,
# not yet committed). "finalized" yards are fully placed + assigned to a supplier.
var pending_yard_corners : Array = []                # Array[Vector3]
var pending_yard_dots    : Array = []                # Array[MeshInstance3D]
var pending_yard_poly    : MeshInstance3D = null     # translucent polygon preview
var finalized_yards      : Array = []                # Array[Dictionary]: {supplier_id, corners,
													 #                    dots[], poly, label}

# Undo history. Each entry knows how to undo itself; kinds:
#   {"kind": "point",  "tool_id": int, "prev_pos": Vector3|null}
#   {"kind": "multi",  "tool_id": int, "pos": Vector3}
#   {"kind": "pending_corner"}
#   {"kind": "yard",   "data": Dictionary}      (a finalised yard was just added)
var history         : Array      = []

# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_build_environment()
	_build_camera()
	_build_ground()
	_build_building_shell()
	_build_floor_plan_overlay()
	markers_root = Node3D.new()
	markers_root.name = "Markers"
	add_child(markers_root)
	_build_ui()
	_apply_loaded_layout()        # show any existing markers
	_frame_loaded_markers()       # ALWAYS centre+zoom to fit them so none are off-screen
	_try_load_cached_satellite()

## Centre and zoom the ortho camera to fit EVERY loaded marker. Without this, the
## camera framed only shell_center / player_spawn, so a layout placed in a frame
## offset from the shell AABB centre (or with player_spawn localized to 0,0) opened
## looking at empty space and the markers appeared "gone" — even though they exist.
func _frame_loaded_markers() -> void:
	var pts : Array = []
	for child in markers_root.get_children():
		if child is Node3D:
			pts.append((child as Node3D).global_position)
	# Include the building-shell centre so the satellite + floor-plan overlay (which
	# sit there) stay in frame alongside the markers, not just the markers' tight box.
	pts.append(shell_center)
	if pts.is_empty():
		return
	var minx : float = pts[0].x; var maxx : float = pts[0].x
	var minz : float = pts[0].z; var maxz : float = pts[0].z
	for p in pts:
		minx = minf(minx, p.x); maxx = maxf(maxx, p.x)
		minz = minf(minz, p.z); maxz = maxf(maxz, p.z)
	cam_target = Vector3((minx + maxx) * 0.5, 0.0, (minz + maxz) * 0.5)
	var span : float = maxf(maxx - minx, maxz - minz)
	cam_size = clampf(span * 0.7 + 25.0, CAM_SIZE_MIN, CAM_SIZE_MAX)
	_update_camera()
	print("[WorldSetup] Framed %d existing markers — centre (%.0f, %.0f), span %.0f m" \
		% [pts.size(), cam_target.x, cam_target.z, span])

# ── Scene construction ───────────────────────────────────────────────────────
func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.6, 0.65, 0.7)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.8, 0.8, 0.85)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-65, -35, 0)
	sun.light_energy = 0.8
	add_child(sun)

func _build_camera() -> void:
	camera = Camera3D.new()
	# Orthographic projection: no perspective drift between the floor quad and
	# the building roof when the camera pans. A marker's screen pixel maps to
	# exactly one (X, Z) regardless of camera offset.
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = cam_size
	camera.near = 0.05
	camera.far  = 4000.0
	camera.current = true
	add_child(camera)
	_update_camera()

func _update_camera() -> void:
	# Build the basis explicitly — looking straight down with `look_at(target,
	# Vector3.UP)` is singular (up vector parallel to view). The adversarial
	# review flagged that even our previous `Vector3.FORWARD` trick gets fragile
	# in ortho at the high altitude needed to clear the 112 m roof. Constructing
	# the basis by hand sidesteps both problems:
	#   camera local -Z (forward) ─→ world -Y (down)
	#   camera local  Y (up)      ─→ world  Z (forward in scene = up on screen)
	#   camera local  X (right)   ─→ world  X (right on screen)
	# Renamed from `basis` → `cam_basis` because `Node3D.basis` is a property and
	# the bare name shadows it (linter warning).
	var cam_basis := Basis(Vector3.RIGHT, Vector3.FORWARD, Vector3.UP)
	# Basis columns are (x, y, z) → that gives x=RIGHT, y=FORWARD (+Z), z=UP (+Y).
	# Camera looks down its local -Z, so local -Z = -UP = world -Y. ✓
	camera.global_transform = Transform3D(cam_basis, Vector3(cam_target.x, CAM_Y, cam_target.z))
	camera.size = cam_size

func _build_ground() -> void:
	ground_quad = MeshInstance3D.new()
	ground_quad.name = "GroundQuad"
	var pm := PlaneMesh.new()
	pm.size = Vector2(DEFAULT_EXTENT_M, DEFAULT_EXTENT_M)
	pm.subdivide_depth = 1
	pm.subdivide_width = 1
	ground_quad.mesh = pm
	ground_material = StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.30, 0.32, 0.30)
	ground_material.roughness = 1.0
	ground_quad.material_override = ground_material
	ground_quad.position = Vector3(0, -0.05, 0)   # just below floor
	add_child(ground_quad)

func _build_building_shell() -> void:
	var src := BUILDING_SOLID if ResourceLoader.exists(BUILDING_SOLID) else BUILDING_OBJ
	var mesh = ResourceLoader.load(src)
	if mesh == null:
		push_warning("[WorldSetup] %s could not load" % src)
		return
	var mi := MeshInstance3D.new()
	mi.name = "ShellMesh"
	mi.mesh = mesh
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(1, 1, 1, 0.25)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)
	_shell_mesh_inst = mi
	# Scene-open camera centres on the player-spawn marker when one is set
	# (it's the user's canonical anchor for THIS scene — same XZ used by the
	# satellite fetch); falls back to the building/terrain centre on a fresh
	# layout where no spawn has been placed yet.
	var aabb := mi.get_aabb()
	var raw_center := Vector3(aabb.position.x + aabb.size.x * 0.5, 0, aabb.position.z + aabb.size.z * 0.5)
	# The building .obj geometry is baked at Dutch RD coordinates (~184,000 / ~329,000),
	# but the saved markers live in a LOCAL frame near the origin. If we leave the shell
	# at RD it renders ~184 km from the markers (and the satellite/floor-plan anchored to
	# it go with it) — so nothing shows together. Shift the mesh so its centre sits at the
	# local origin; then shell + satellite + floor-plan + markers all share ONE frame.
	_shell_rd_center = raw_center   # remember the TRUE RD centre for satellite fetches
	if absf(raw_center.x) > 10000.0 or absf(raw_center.z) > 10000.0:
		mi.position = -raw_center
		shell_center = Vector3.ZERO
		print("[WorldSetup] Building shell was at RD %s — shifted to local origin to match markers" % str(raw_center))
	else:
		shell_center = raw_center
	cam_target = WorldLayout.player_spawn if WorldLayout.player_spawn != Vector3.ZERO else shell_center
	# Frame the building footprint: ortho size = max(width, depth) × 0.9 fits it
	# vertically in the viewport with a little margin.
	cam_size = clampf(maxf(aabb.size.x, aabb.size.z) * 0.9, CAM_SIZE_MIN, CAM_SIZE_MAX)
	ground_quad.position = Vector3(shell_center.x, -0.05, shell_center.z)
	_update_camera()
	# #131 — Compute every connected component (~124 buildings in the tile) and
	# overlay a translucent rectangle on each so the FACTORY_CENTER tool snaps
	# the click onto the correct building's centroid, not the raw click point.
	# Removes the "lights are over the wrong building" failure that's been
	# bouncing back for multiple sessions.
	_build_component_overlays()

# =============================================================================
# #131 — BUILDING-SELECTOR OVERLAY
# =============================================================================
## The source tile (`CeDo_building.obj`) contains ~124 separate buildings — each
## an independent connected component of triangles. solidify_building.py picks
## the factory by reading `factory_center` from world_layout.json and grabbing
## the connected component containing or nearest to that point. Across multiple
## sessions the marker drifted and the wrong building got isolated.
##
## This block computes every connected component on shell-load, draws a
## translucent rectangle over each so the user can SEE the targets in the
## top-down view, snaps any FACTORY_CENTER click onto the nearest component's
## centroid (so a slightly-off click still hits the right building), and
## highlights the currently-selected component in bright magenta.

var _shell_mesh_inst      : MeshInstance3D = null
var _components           : Array          = []   # [{centroid: V3, aabb: AABB, tris: int}]
var _component_overlays   : Array          = []   # parallel MeshInstance3Ds
var _picked_component_idx : int            = -1

# Faint cream so the unpicked buildings are visible but unobtrusive; bright
# magenta on the picked one so it can't be confused with the rest.
const COMPONENT_BASE_COLOR   : Color = Color(0.85, 0.78, 0.62, 0.22)
const COMPONENT_PICKED_COLOR : Color = Color(1.00, 0.10, 0.85, 0.55)

func _build_component_overlays() -> void:
	if _shell_mesh_inst == null:
		return
	_compute_components_from(_shell_mesh_inst)
	# Build a translucent ground-plane quad over each component's XZ AABB.
	for c in _components:
		var aabb : AABB = c["aabb"]
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(aabb.size.x, aabb.size.z)
		q.mesh = qm
		# QuadMesh faces +Z by default; rotate to lie flat (face +Y) and lift it
		# just above the ground quad / satellite so it isn't z-fighting.
		q.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		q.position = aabb.position + Vector3(aabb.size.x * 0.5, 0.02, aabb.size.z * 0.5)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = COMPONENT_BASE_COLOR
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		q.material_override = mat
		q.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(q)
		_component_overlays.append(q)
	_refresh_component_highlight()

## Walks the mesh's vertex / index arrays, welds verts within 1 mm, then runs
## union-find over the triangle list — every triangle whose welded vertices
## are reachable through shared verts lands in the same connected component.
## One-shot at scene load; the ~124-component result is cached.
func _compute_components_from(mesh_inst: MeshInstance3D) -> void:
	if not _components.is_empty():
		return
	var mesh : Mesh = mesh_inst.mesh
	if mesh == null:
		return
	var arrays : Array = mesh.surface_get_arrays(0)
	if arrays.size() < Mesh.ARRAY_INDEX + 1:
		return
	# Guard against null/empty surface arrays — happens on meshes with no index
	# buffer OR no vertex buffer. Strict-typed assignment of nil to PackedX
	# throws "Trying to assign value of type 'Nil' to a variable of type 'PackedInt32Array'."
	var verts_raw : Variant = arrays[Mesh.ARRAY_VERTEX]
	var verts : PackedVector3Array = verts_raw if verts_raw is PackedVector3Array else PackedVector3Array()
	var idx_raw : Variant = arrays[Mesh.ARRAY_INDEX]
	var indices : PackedInt32Array = idx_raw if idx_raw is PackedInt32Array else PackedInt32Array()
	if verts.size() == 0:
		return
	# If the mesh has no index buffer (triangle soup), synthesise sequential ids.
	if indices.size() == 0:
		indices = PackedInt32Array()
		indices.resize(verts.size())
		for i in verts.size():
			indices[i] = i
	# Weld verts by 1 mm rounding so 124 buildings sitting side-by-side in the
	# tile resolve cleanly into distinct components.
	var weld_table : Dictionary = {}
	var welded : PackedInt32Array = PackedInt32Array()
	welded.resize(verts.size())
	for i in verts.size():
		var v : Vector3 = verts[i]
		var key := Vector3i(int(round(v.x * 1000.0)),
							int(round(v.y * 1000.0)),
							int(round(v.z * 1000.0)))
		var w : int
		if weld_table.has(key):
			w = int(weld_table[key])
		else:
			w = int(weld_table.size())
			weld_table[key] = w
		welded[i] = w
	var n_unique : int = weld_table.size()
	var parent : PackedInt32Array = PackedInt32Array()
	parent.resize(n_unique)
	for i in n_unique:
		parent[i] = i
	@warning_ignore("integer_division")
	var n_tri : int = indices.size() / 3
	for ti in n_tri:
		var a := welded[indices[ti * 3]]
		var b := welded[indices[ti * 3 + 1]]
		var c := welded[indices[ti * 3 + 2]]
		_uf_union(parent, a, b)
		_uf_union(parent, b, c)
	# Group + accumulate per-component stats.
	var groups : Dictionary = {}
	for ti in n_tri:
		var root := _uf_find(parent, welded[indices[ti * 3]])
		var g : Dictionary
		if groups.has(root):
			g = groups[root]
		else:
			g = {"vsum": Vector3.ZERO, "vcnt": 0,
				 "bb_min": Vector3(INF, INF, INF),
				 "bb_max": Vector3(-INF, -INF, -INF),
				 "tris": 0}
			groups[root] = g
		for k in 3:
			var vi := indices[ti * 3 + k]
			var v : Vector3 = verts[vi]
			g["vsum"] = (g["vsum"] as Vector3) + v
			g["vcnt"] = int(g["vcnt"]) + 1
			g["bb_min"] = Vector3(minf(g["bb_min"].x, v.x),
								  minf(g["bb_min"].y, v.y),
								  minf(g["bb_min"].z, v.z))
			g["bb_max"] = Vector3(maxf(g["bb_max"].x, v.x),
								  maxf(g["bb_max"].y, v.y),
								  maxf(g["bb_max"].z, v.z))
		g["tris"] = int(g["tris"]) + 1
	# Convert to scene-local centroid + AABB (mesh local + shell mesh.position).
	var shift : Vector3 = mesh_inst.position
	for root in groups.keys():
		var g : Dictionary = groups[root]
		var local_c : Vector3 = (g["vsum"] as Vector3) / float(g["vcnt"])
		var local_aabb := AABB(g["bb_min"], (g["bb_max"] as Vector3) - (g["bb_min"] as Vector3))
		_components.append({
			"centroid": local_c + shift,
			"aabb":     AABB(local_aabb.position + shift, local_aabb.size),
			"tris":     int(g["tris"]),
		})
	# Largest-first so #0 is usually the biggest hall (helps the user spot the
	# factory at a glance if factory_center hasn't been set yet).
	_components.sort_custom(func(a, b): return int(a["tris"]) > int(b["tris"]))
	print("[WorldSetup] Connected components: %d (largest = %d tris)" \
		% [_components.size(), int(_components[0]["tris"]) if _components.size() > 0 else 0])

func _uf_find(parent: PackedInt32Array, x: int) -> int:
	while parent[x] != x:
		parent[x] = parent[parent[x]]
		x = parent[x]
	return x

func _uf_union(parent: PackedInt32Array, a: int, b: int) -> void:
	var ra := _uf_find(parent, a)
	var rb := _uf_find(parent, b)
	if ra != rb:
		parent[ra] = rb

## Find the connected component whose XZ AABB contains the given world point.
## Falls back to NEAREST-CENTROID when the click misses every AABB so the user
## can still click roughly near a building they want.
func _find_component_at_xz(world_pos: Vector3) -> int:
	var px := world_pos.x
	var pz := world_pos.z
	# First pass: containment.
	var best := -1
	var best_d := INF
	for i in _components.size():
		var aabb : AABB = _components[i]["aabb"]
		if px < aabb.position.x or px > aabb.position.x + aabb.size.x:
			continue
		if pz < aabb.position.z or pz > aabb.position.z + aabb.size.z:
			continue
		var cent : Vector3 = _components[i]["centroid"]
		var d : float = Vector2(cent.x, cent.z).distance_to(Vector2(px, pz))
		if d < best_d:
			best_d = d
			best = i
	if best >= 0:
		return best
	# Fallback: nearest centroid.
	best_d = INF
	for i in _components.size():
		var cent : Vector3 = _components[i]["centroid"]
		var d : float = Vector2(cent.x, cent.z).distance_to(Vector2(px, pz))
		if d < best_d:
			best_d = d
			best = i
	return best

## Recolour every overlay quad so the currently-picked one stands out. Called
## on initial overlay build AND every time the user clicks FACTORY_CENTER.
func _refresh_component_highlight() -> void:
	var fc : Vector3 = WorldLayout.factory_center
	_picked_component_idx = -1
	if fc != Vector3.ZERO and not _components.is_empty():
		_picked_component_idx = _find_component_at_xz(fc)
	for i in _component_overlays.size():
		var mi : MeshInstance3D = _component_overlays[i]
		if mi == null:
			continue
		var mat := mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		mat.albedo_color = COMPONENT_PICKED_COLOR if i == _picked_component_idx \
			else COMPONENT_BASE_COLOR

## Floor-plan overlay: a semi-transparent quad sitting just above the satellite
## quad, textured with assets/models/floor_plan.png (the cropped CeDo127 PDF).
## Visible only when the user toggles it on in the sidebar; the calibration
## (offset / scale / rotation / opacity) persists in WorldLayout so the user
## aligns the plan to the building once and never again.
func _build_floor_plan_overlay() -> void:
	plan_quad = MeshInstance3D.new()
	plan_quad.name = "FloorPlanOverlay"
	var pm := PlaneMesh.new()
	pm.size = Vector2(WorldLayout.floor_plan_scale_m, WorldLayout.floor_plan_scale_m)
	plan_quad.mesh = pm
	plan_material = StandardMaterial3D.new()
	plan_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plan_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	plan_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	plan_material.albedo_color = Color(1, 1, 1, WorldLayout.floor_plan_opacity)
	var tex := load(FLOOR_PLAN_PATH) as Texture2D
	if tex:
		plan_material.albedo_texture = tex
	else:
		push_warning("[WorldSetup] floor_plan.png not found at %s" % FLOOR_PLAN_PATH)
	plan_quad.material_override = plan_material
	plan_quad.visible = WorldLayout.floor_plan_enabled
	add_child(plan_quad)
	_apply_floor_plan_calibration()

## Push the persisted calibration onto the overlay quad. Called on _ready and
## whenever a slider in the sidebar moves.
func _apply_floor_plan_calibration() -> void:
	if plan_quad == null: return
	plan_quad.visible = WorldLayout.floor_plan_enabled
	# Image native aspect ≈ 2400 / 1293 ≈ 1.856. Scale_m is the Z (height) of
	# the plan in world metres; X is scale_m × aspect.
	var aspect : float = 2400.0 / 1293.0
	var pm := plan_quad.mesh as PlaneMesh
	pm.size = Vector2(WorldLayout.floor_plan_scale_m * aspect, WorldLayout.floor_plan_scale_m)
	# Position: above the satellite quad (Y +0.02 over -0.05 so it's on top).
	plan_quad.global_position = Vector3(
		shell_center.x + WorldLayout.floor_plan_offset_x,
		-0.03,
		shell_center.z + WorldLayout.floor_plan_offset_z,
	)
	plan_quad.rotation = Vector3(0, deg_to_rad(WorldLayout.floor_plan_rot_deg), 0)
	if plan_material:
		plan_material.albedo_color = Color(1, 1, 1, clampf(WorldLayout.floor_plan_opacity, 0.05, 1.0))

# ── UI ───────────────────────────────────────────────────────────────────────
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	# Top bar
	var top := PanelContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 0
	top.offset_left = 0
	top.offset_right = 0
	top.custom_minimum_size.y = 44
	layer.add_child(top)
	status_label = Label.new()
	status_label.add_theme_font_size_override("font_size", 16)
	status_label.text = "World Setup — pick a tool on the left, then click on the floor."
	top.add_child(status_label)

	# Left: marker tools — anchored top-left + bottom-left, fixed 230 px wide.
	var left := PanelContainer.new()
	left.anchor_left   = 0.0
	left.anchor_right  = 0.0
	left.anchor_top    = 0.0
	left.anchor_bottom = 1.0
	left.offset_left   = 8
	left.offset_right  = 8 + 230
	left.offset_top    = 50
	left.offset_bottom = -8
	left.mouse_filter  = Control.MOUSE_FILTER_STOP
	layer.add_child(left)
	var lv := VBoxContainer.new()
	left.add_child(lv)

	var hdr := Label.new()
	hdr.text = "Markers"
	hdr.add_theme_font_size_override("font_size", 18)
	lv.add_child(hdr)

	for tool_id in TOOL_DEFS.keys():
		var def : Dictionary = TOOL_DEFS[tool_id]
		var b := Button.new()
		b.text = def["label"]
		var col : Color = def["color"]
		b.add_theme_color_override("font_color", col)
		b.pressed.connect(_on_tool_pressed.bind(tool_id))
		lv.add_child(b)
		tool_buttons[tool_id] = b

	lv.add_child(HSeparator.new())
	var undo_btn := Button.new()
	undo_btn.text = "Undo last (Ctrl+Z)"
	undo_btn.pressed.connect(_undo_last)
	lv.add_child(undo_btn)
	var clear_btn := Button.new()
	clear_btn.text = "Clear all markers"
	clear_btn.pressed.connect(_on_clear_pressed)
	lv.add_child(clear_btn)

	# Pending-yard supplier panel — only visible while 1–4 corners are placed
	# but the user hasn't picked a supplier yet. Once they confirm, panel hides
	# again and the user can start a new yard.
	yard_panel = VBoxContainer.new()
	yard_panel.add_theme_constant_override("separation", 4)
	lv.add_child(yard_panel)
	yard_status_lbl = Label.new()
	yard_status_lbl.text = "Pending yard: 0 / 4 corners"
	yard_status_lbl.add_theme_font_size_override("font_size", 12)
	yard_panel.add_child(yard_status_lbl)
	var sup_lbl := Label.new()
	sup_lbl.text = "Supplier:"
	sup_lbl.add_theme_font_size_override("font_size", 11)
	yard_panel.add_child(sup_lbl)
	supplier_select = OptionButton.new()
	# Populate from BaleDefs so the list stays in sync with the sim's supplier
	# catalogue. Falls back to a hard list if BaleDefs isn't loaded yet.
	if Engine.has_singleton("BaleDefs") or ResourceLoader.exists("res://src/sim/BaleDefs.gd"):
		var BD = load("res://src/sim/BaleDefs.gd")
		var origins : Array = BD.origins()
		for o in origins:
			supplier_select.add_item(String(o.get("name", o.get("id", "?"))))
			supplier_select.set_item_metadata(supplier_select.item_count - 1, String(o.get("id", "")))
	else:
		for s in [["rotterdam","Rotterdam"], ["alba_marl","Alba Marl"],
				  ["zwolle","Zwolle"], ["forstplus","Forst+"]]:
			supplier_select.add_item(s[1])
			supplier_select.set_item_metadata(supplier_select.item_count - 1, s[0])
	yard_panel.add_child(supplier_select)
	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm yard"
	confirm_btn.pressed.connect(_confirm_pending_yard)
	yard_panel.add_child(confirm_btn)
	var discard_btn := Button.new()
	discard_btn.text = "Discard pending"
	discard_btn.pressed.connect(_discard_pending_yard)
	yard_panel.add_child(discard_btn)
	_refresh_yard_panel()

	# Right: WMS satellite + save — anchored top-right + bottom-right, 280 px wide.
	var right := PanelContainer.new()
	right.anchor_left   = 1.0
	right.anchor_right  = 1.0
	right.anchor_top    = 0.0
	right.anchor_bottom = 1.0
	right.offset_left   = -340     # = -(width + margin); wider to fit the SpinBox + slider pairs
	right.offset_right  = -8
	right.offset_top    = 50
	right.offset_bottom = -8
	right.mouse_filter  = Control.MOUSE_FILTER_STOP
	layer.add_child(right)
	var rv := VBoxContainer.new()
	right.add_child(rv)

	var sat_hdr := Label.new()
	sat_hdr.text = "PDOK Luchtfoto"
	sat_hdr.add_theme_font_size_override("font_size", 18)
	rv.add_child(sat_hdr)

	# Priority for the satellite tile centre: override > player-spawn marker > shell.
	# Show whichever one will actually be used so the user can verify before fetching.
	var auto_info := Label.new()
	auto_info.name = "AutoInfo"
	auto_info.add_theme_font_size_override("font_size", 12)
	rv.add_child(auto_info)
	_refresh_auto_info(auto_info)

	var override_lbl := Label.new()
	override_lbl.text = "Override (leave 0 to use auto):"
	override_lbl.add_theme_font_size_override("font_size", 12)
	rv.add_child(override_lbl)
	var lat_box := _field("Lat", "0")
	lat_input = lat_box.get_child(1) as LineEdit
	lat_input.text_changed.connect(func(_t): _refresh_auto_info())
	rv.add_child(lat_box)
	var lon_box := _field("Lon", "0")
	lon_input = lon_box.get_child(1) as LineEdit
	lon_input.text_changed.connect(func(_t): _refresh_auto_info())
	rv.add_child(lon_box)
	var ext_box := _field("Extent (m)", str(DEFAULT_EXTENT_M))
	extent_input = ext_box.get_child(1) as LineEdit
	rv.add_child(ext_box)

	var fetch_btn := Button.new()
	fetch_btn.text = "Fetch satellite"
	fetch_btn.pressed.connect(_on_fetch_satellite)
	rv.add_child(fetch_btn)
	rv.add_child(HSeparator.new())

	# ── Floor-plan overlay ──────────────────────────────────────────────────
	var fp_hdr := Label.new()
	fp_hdr.text = "Floor plan (CeDo127 PDF)"
	fp_hdr.add_theme_font_size_override("font_size", 18)
	rv.add_child(fp_hdr)
	_build_marker_controls(rv)
	_build_floor_plan_controls(rv)

	rv.add_child(HSeparator.new())

	var info := Label.new()
	info.text = "Controls:\nLMB — place (or drag for yard)\nRMB drag — pan camera\nWheel — zoom"
	info.add_theme_font_size_override("font_size", 13)
	rv.add_child(info)

	rv.add_child(HSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "Save & return to menu"
	save_btn.add_theme_font_size_override("font_size", 16)
	save_btn.pressed.connect(_on_save_pressed)
	rv.add_child(save_btn)

	var back_btn := Button.new()
	back_btn.text = "Cancel (no save)"
	back_btn.pressed.connect(_on_back_pressed)
	rv.add_child(back_btn)

## Builds the floor-plan calibration UI: enable toggle + opacity / scale /
## rotation / X / Z offset sliders + reset button. Each slider mutates
## WorldLayout.floor_plan_* directly and re-applies the calibration; the
## values aren't persisted to disk until the user clicks "Save & return to
## menu" (same as every other WorldSetup change).
## Marker-group calibration panel: slide ALL placed markers together to line them
## up with the satellite/building. Offsets in metres, rotation in degrees (the
## satellite is north-up, so this is north-oriented). 2-decimal precision. The
## adjustment is relative each session and baked into the saved layout on Save.
func _build_marker_controls(parent: VBoxContainer) -> void:
	var hdr := Label.new()
	hdr.text = "Marker calibration"
	hdr.add_theme_font_size_override("font_size", 18)
	parent.add_child(hdr)
	var hint := Label.new()
	hint.text = "Move/rotate ALL markers onto the building (north-up)."
	hint.add_theme_font_size_override("font_size", 11)
	parent.add_child(hint)

	var sbs : Array = []
	sbs.append(_calib_control(parent, "Offset X (m)",  -2000.0, 2000.0, 0.1, 0.0,
		func(v: float): _marker_cal_x = v))
	sbs.append(_calib_control(parent, "Offset Z (m)",  -2000.0, 2000.0, 0.1, 0.0,
		func(v: float): _marker_cal_z = v))
	sbs.append(_calib_control(parent, "Rotation (°)",   -180.0,  180.0, 0.1, 0.0,
		func(v: float): _marker_cal_rot = v))

	var reset_btn := Button.new()
	reset_btn.text = "Reset marker calibration"
	reset_btn.pressed.connect(func() -> void:
		for sb in sbs:
			(sb as SpinBox).value = 0.0)   # fires value_changed → resets + re-applies
	parent.add_child(reset_btn)

	var sep := HSeparator.new()
	parent.add_child(sep)

## Generic calibration control (label + SpinBox + slider, two-way synced). Like
## _fp_control but calls _apply_marker_calibration() after the setter instead of
## the floor-plan refresh. `step` drives the displayed decimals (0.01 → 2 places).
## Returns the SpinBox so callers can reset it.
func _calib_control(parent: VBoxContainer, label_text: String,
				 low: float, high: float, step: float, init: float,
				 setter: Callable) -> SpinBox:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var sb := SpinBox.new()
	sb.min_value = low
	sb.max_value = high
	sb.step      = step
	sb.value     = init
	sb.allow_greater = true
	sb.allow_lesser  = true
	sb.custom_minimum_size = Vector2(86, 0)
	sb.get_line_edit().select_all_on_focus = true
	row.add_child(sb)
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step      = step
	s.value     = init
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	var _syncing := [false]
	var on_change := func(v: float) -> void:
		setter.call(v)
		_apply_marker_calibration()
	sb.value_changed.connect(func(v: float) -> void:
		if _syncing[0]: return
		_syncing[0] = true
		s.value = clampf(v, low, high)
		_syncing[0] = false
		on_change.call(v))
	s.value_changed.connect(func(v: float) -> void:
		if _syncing[0]: return
		_syncing[0] = true
		sb.value = v
		_syncing[0] = false
		on_change.call(v))
	return sb

func _build_floor_plan_controls(parent: VBoxContainer) -> void:
	var enable_cb := CheckBox.new()
	enable_cb.text = "Show overlay"
	enable_cb.button_pressed = WorldLayout.floor_plan_enabled
	enable_cb.toggled.connect(func(on: bool) -> void:
		WorldLayout.floor_plan_enabled = on
		_apply_floor_plan_calibration())
	parent.add_child(enable_cb)

	_fp_control(parent, "Opacity",      0.0,     1.0, 0.05, 2, WorldLayout.floor_plan_opacity,
		func(v: float): WorldLayout.floor_plan_opacity = v)
	_fp_control(parent, "Scale (m)",   20.0,  1500.0, 0.1,  1, WorldLayout.floor_plan_scale_m,
		func(v: float): WorldLayout.floor_plan_scale_m = v)
	_fp_control(parent, "Rotation (°)", -180.0, 180.0, 0.1, 1, WorldLayout.floor_plan_rot_deg,
		func(v: float): WorldLayout.floor_plan_rot_deg = v)
	_fp_control(parent, "Offset X (m)", -2000.0, 2000.0, 0.1, 1, WorldLayout.floor_plan_offset_x,
		func(v: float): WorldLayout.floor_plan_offset_x = v)
	_fp_control(parent, "Offset Z (m)", -2000.0, 2000.0, 0.1, 1, WorldLayout.floor_plan_offset_z,
		func(v: float): WorldLayout.floor_plan_offset_z = v)

	var reset_btn := Button.new()
	reset_btn.text = "Reset overlay calibration"
	reset_btn.pressed.connect(_on_reset_floor_plan)
	parent.add_child(reset_btn)

## Floor-plan control: label + SpinBox (typed input) + Slider (coarse drag),
## bound to the same backing value via `setter`. The SpinBox accepts values
## outside the slider range (allow_greater / allow_lesser) so the user can
## type any precise coordinate; the slider is just a fast-coarse-adjust UI.
## `decimals` controls the SpinBox display precision (1 → "0.1", 2 → "0.05").
func _fp_control(parent: VBoxContainer, label_text: String,
				 low: float, high: float, step: float, _decimals: int, init: float,
				 setter: Callable) -> void:
	var lbl := Label.new()
	lbl.text = label_text
	lbl.add_theme_font_size_override("font_size", 12)
	parent.add_child(lbl)
	# Row: SpinBox on the left (for typing), slider filling the rest.
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var sb := SpinBox.new()
	sb.min_value = low
	sb.max_value = high
	sb.step      = step
	sb.value     = init
	sb.allow_greater = true   # let the user type a value above the slider's max
	sb.allow_lesser  = true
	sb.custom_minimum_size = Vector2(86, 0)
	# Render with the requested number of decimals.
	sb.get_line_edit().select_all_on_focus = true
	# Godot's SpinBox doesn't have a "decimals" property — we drive the
	# rendered string via the step value (e.g. step=0.1 → "X.X") and trust
	# the user's input formatter.
	row.add_child(sb)
	var s := HSlider.new()
	s.min_value = low
	s.max_value = high
	s.step      = step
	s.value     = init
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(s)
	# Two-way sync. `_syncing` is wrapped in an Array so the inner lambdas can
	# mutate it (GDScript lambdas don't capture rebound locals otherwise).
	var _syncing := [false]
	var on_change := func(v: float) -> void:
		setter.call(v)
		_apply_floor_plan_calibration()
	sb.value_changed.connect(func(v: float) -> void:
		if _syncing[0]: return
		_syncing[0] = true
		# Slider can't represent values outside [low,high]; clamp here only.
		s.value = clampf(v, low, high)
		_syncing[0] = false
		on_change.call(v))
	s.value_changed.connect(func(v: float) -> void:
		if _syncing[0]: return
		_syncing[0] = true
		sb.value = v
		_syncing[0] = false
		on_change.call(v))

func _on_reset_floor_plan() -> void:
	WorldLayout.floor_plan_enabled  = false
	WorldLayout.floor_plan_opacity  = 0.6
	WorldLayout.floor_plan_offset_x = 0.0
	WorldLayout.floor_plan_offset_z = 0.0
	WorldLayout.floor_plan_scale_m  = 100.0
	WorldLayout.floor_plan_rot_deg  = 0.0
	_apply_floor_plan_calibration()
	# Force the sidebar to re-render with the reset values (cheap rebuild).
	# Status hint so the user knows they need to re-enable + re-calibrate.
	if status_label:
		status_label.text = "Floor-plan calibration reset (reopen the scene to refresh sliders)."

func _field(label_text: String, default_val: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	var l := Label.new()
	l.text = label_text
	box.add_child(l)
	var le := LineEdit.new()
	le.text = default_val
	box.add_child(le)
	return box

# ── Input ────────────────────────────────────────────────────────────────────
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and k.ctrl_pressed and k.keycode == KEY_Z:
			_undo_last()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			cam_size = clampf(cam_size * 0.9, CAM_SIZE_MIN, CAM_SIZE_MAX)
			_update_camera(); _rescale_markers()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			cam_size = clampf(cam_size * 1.1, CAM_SIZE_MIN, CAM_SIZE_MAX)
			_update_camera(); _rescale_markers()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_click_down(mb.position)
			else:
				_on_left_click_up(mb.position)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and (mb.button_mask & MOUSE_BUTTON_MASK_RIGHT) == 0:
			# Plain right-click (no drag in progress) → delete marker under cursor
			# if any. We check `button_mask` so a RMB-drag for camera-pan doesn't
			# also delete a marker when the user releases the button.
			_on_right_click(mb.position)
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if dragging_node:
			# Move the dragged marker — XZ from the cursor, Y kept at its own value
			# so corner dots / vehicle dots stay at the right height.
			var hit := _screen_to_floor(mm.position)
			dragging_node.position = Vector3(hit.x, dragging_node.position.y, hit.z)
			if dragging_kind == "pending_corner":
				if dragging_corner_idx >= 0 and dragging_corner_idx < pending_yard_corners.size():
					pending_yard_corners[dragging_corner_idx] = Vector3(hit.x, 0.0, hit.z)
				_redraw_pending_yard()
			elif dragging_kind == "yard_corner":
				_update_finalized_yard_drag(hit)
		elif mm.button_mask & MOUSE_BUTTON_MASK_RIGHT:
			# Pan in world metres ≈ 1 viewport-height per 600 px of mouse motion.
			var px_to_m := cam_size / 600.0
			cam_target.x -= mm.relative.x * px_to_m
			cam_target.z -= mm.relative.y * px_to_m
			_update_camera()

func _screen_to_floor(screen_pos: Vector2) -> Vector3:
	# Cast a ray from camera through cursor down to the y=0 plane, then return the
	# hit in MARKERS_ROOT-LOCAL space so all placement / drag / pick logic works in
	# one frame regardless of the marker calibration transform. At identity (no
	# calibration) to_local() is a no-op, so behaviour is unchanged.
	if camera == null: return Vector3.ZERO
	var origin := camera.project_ray_origin(screen_pos)
	var dir    := camera.project_ray_normal(screen_pos)
	var world : Vector3
	if absf(dir.y) < 1e-4:
		world = cam_target
	else:
		var t := -origin.y / dir.y
		world = cam_target if t < 0.0 else origin + dir * t
	return markers_root.to_local(world) if markers_root else world

## A marker's WORLD position (calibration baked in) as a y=0 vector — used when
## committing to WorldLayout so the saved layout reflects the calibrated layout.
func _marker_world(node: Node3D) -> Vector3:
	var w : Vector3 = markers_root.to_global(node.position) if markers_root else node.position
	return Vector3(w.x, 0.0, w.z)

# ── Marker calibration (move/rotate the whole marker group onto the building) ──
## Live group transform applied to markers_root so the user can slide ALL markers
## together to line them up with the satellite/building, the same way the floor-plan
## overlay is calibrated. Offsets are metres; rotation is degrees (north-up: the
## satellite is north-oriented, so 0° keeps the layout as-placed). Baked into the
## saved coordinates on Save via _marker_world(); not stored as a separate field.
func _apply_marker_calibration() -> void:
	if markers_root == null:
		return
	# Rotate the whole group AROUND THE FACTORY-CENTER marker so it stays pinned while
	# you spin the layout, then apply the X/Z offset. Falls back to the origin if no
	# factory centre has been placed yet.
	var pivot := Vector3.ZERO
	if point_markers.has(Tool.FACTORY_CENTER) and is_instance_valid(point_markers[Tool.FACTORY_CENTER]):
		pivot = (point_markers[Tool.FACTORY_CENTER] as Node3D).position
	pivot.y = 0.0
	var b := Basis(Vector3.UP, deg_to_rad(_marker_cal_rot))
	var origin : Vector3 = pivot - b * pivot + Vector3(_marker_cal_x, 0.0, _marker_cal_z)
	markers_root.transform = Transform3D(b, origin)

func _on_left_click_down(screen_pos: Vector2) -> void:
	if current_tool == Tool.NONE: return
	var hit := _screen_to_floor(screen_pos)
	# 1) Try to PICK a draggable marker under the cursor before any new-placement
	#    action — clicking ON a corner drags it instead of dropping a new one.
	if _begin_drag_at(hit):
		return
	# 2) Otherwise, dispatch by tool kind.
	var def : Dictionary = TOOL_DEFS[current_tool]
	match def["kind"]:
		"point":   _place_point(current_tool, hit)
		"multi":   _add_multi_marker(current_tool, hit)
		"polygon": _add_yard_corner(hit)

func _on_left_click_up(_screen_pos: Vector2) -> void:
	# End any active drag. Nothing else to do — placements happen on click-down.
	dragging_node = null
	dragging_kind = ""
	dragging_tool = Tool.NONE
	dragging_yard_idx = -1
	dragging_corner_idx = -1
	_commit_to_layout()

## Right-click on a marker → delete it. Looks across multi vehicles, pending
## corners, and finalised yard corners (where deleting a corner removes the
## whole yard since 3-corner polygons don't make sense for our use). Single
## "point" markers (player spawn / line starts) intentionally don't delete on
## right-click — use the Undo button or click the same tool elsewhere instead.
func _on_right_click(screen_pos: Vector2) -> void:
	var hit := _screen_to_floor(screen_pos)
	var hit_xz := Vector2(hit.x, hit.z)
	# Multi vehicles
	for tool_id in multi_markers:
		var arr : Array = multi_markers[tool_id]
		for i in arr.size():
			var node : MeshInstance3D = arr[i]
			if Vector2(node.position.x, node.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
				node.queue_free()
				arr.remove_at(i)
				WorldLayout.remove_vehicle_spawn(VEHICLE_TOOL_TO_ID[tool_id], i)
				status_label.text = "Removed one %s." % str(TOOL_DEFS[tool_id]["label"])
				return
	# Pending yard corner
	for i in pending_yard_dots.size():
		var d : MeshInstance3D = pending_yard_dots[i]
		if Vector2(d.position.x, d.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
			d.queue_free()
			pending_yard_dots.remove_at(i)
			pending_yard_corners.remove_at(i)
			_redraw_pending_yard()
			_refresh_yard_panel()
			status_label.text = "Removed pending yard corner."
			return
	# Finalised yard corner — deletes the whole yard
	for yi in finalized_yards.size():
		var yard : Dictionary = finalized_yards[yi]
		for ci in (yard.get("dots", []) as Array).size():
			var dot : MeshInstance3D = yard["dots"][ci]
			if Vector2(dot.position.x, dot.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
				_remove_finalized_yard(yi)
				status_label.text = "Removed bale yard (right-click any corner = delete yard)."
				return

## Find the first draggable marker within DRAG_PICK_RADIUS_M of `hit`; start
## drag mode on it and return true. Returns false if nothing's in range.
func _begin_drag_at(hit: Vector3) -> bool:
	var hit_xz := Vector2(hit.x, hit.z)
	# Multi vehicles
	for tool_id in multi_markers:
		var arr : Array = multi_markers[tool_id]
		for i in arr.size():
			var node : MeshInstance3D = arr[i]
			if Vector2(node.position.x, node.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
				dragging_node = node; dragging_kind = "multi"
				dragging_tool = tool_id; dragging_corner_idx = i
				return true
	# Single-point markers (player spawn / line starts)
	for tool_id in point_markers:
		var node : MeshInstance3D = point_markers[tool_id]
		if Vector2(node.position.x, node.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
			dragging_node = node; dragging_kind = "point"; dragging_tool = tool_id
			return true
	# Pending-yard corners (not yet committed)
	for i in pending_yard_dots.size():
		var d : MeshInstance3D = pending_yard_dots[i]
		if Vector2(d.position.x, d.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
			dragging_node = d; dragging_kind = "pending_corner"
			dragging_corner_idx = i
			return true
	# Finalised-yard corners (after Confirm)
	for yi in finalized_yards.size():
		var dots : Array = finalized_yards[yi].get("dots", [])
		for ci in dots.size():
			var dot : MeshInstance3D = dots[ci]
			if Vector2(dot.position.x, dot.position.z).distance_to(hit_xz) <= DRAG_PICK_RADIUS_M:
				dragging_node = dot; dragging_kind = "yard_corner"
				dragging_yard_idx = yi; dragging_corner_idx = ci
				return true
	return false

## Push every marker's current position into WorldLayout. Called after drag
## ends (LMB up), so the persisted layout matches what's on screen.
func _commit_to_layout() -> void:
	# After a drag ends, push the new positions into WorldLayout.
	# Multi vehicles: rebuild the full array from the marker positions.
	for tool_id in multi_markers:
		var vid : String = VEHICLE_TOOL_TO_ID[tool_id]
		WorldLayout.clear_vehicle_spawns(vid)
		for node in multi_markers[tool_id]:
			var mi : MeshInstance3D = node
			WorldLayout.add_vehicle_spawn(vid, _marker_world(mi))
	# Point markers (player spawn / line starts)
	for tool_id in point_markers:
		var mi2 : MeshInstance3D = point_markers[tool_id]
		var p := _marker_world(mi2)
		if tool_id == Tool.PLAYER_SPAWN:
			WorldLayout.player_spawn = p          # player spawn ONLY — no longer touches factory_center
		elif tool_id == Tool.FACTORY_CENTER:
			WorldLayout.factory_center = p        # independent marker (decoupled from player spawn)
		elif LINE_TOOL_TO_ID.has(tool_id):
			WorldLayout.set_line_start(LINE_TOOL_TO_ID[tool_id], p)
		# #221-PC Phase 5 — operator-draggable previously-hardcoded placements.
		elif tool_id == Tool.STAFF_PARKING:
			WorldLayout.staff_parking = p
		elif tool_id == Tool.PLAYER_SWIFT:
			WorldLayout.player_swift = p
		elif tool_id == Tool.COMPRESSOR_SPAWN:
			WorldLayout.compressor_spawn = p
	# Finalised yards: refresh corners from their dot nodes.
	for yard in finalized_yards:
		var dots : Array = yard.get("dots", [])
		var corners : Array = []
		for d in dots:
			var md : MeshInstance3D = d
			corners.append(_marker_world(md))
		yard["corners"] = corners
	# Push finalised yards back into WorldLayout.
	WorldLayout.bale_yards.clear()
	for yard in finalized_yards:
		WorldLayout.add_bale_yard(yard.get("supplier_id", ""), yard.get("corners", []))

# ── Tool buttons ─────────────────────────────────────────────────────────────
func _on_tool_pressed(tool_id: int) -> void:
	current_tool = tool_id
	status_label.text = "Tool: %s — click on the floor" % str(TOOL_DEFS[tool_id]["label"])
	for k in tool_buttons:
		var btn : Button = tool_buttons[k]
		btn.flat = (k != tool_id)

func _undo_last() -> void:
	if history.is_empty():
		status_label.text = "Nothing to undo."
		return
	var entry : Dictionary = history.pop_back()
	match entry.get("kind", ""):
		"point":
			var tool_id : int = entry["tool_id"]
			if point_markers.has(tool_id):
				point_markers[tool_id].queue_free()
				point_markers.erase(tool_id)
			var prev = entry["prev_pos"]
			if prev != null:
				var def : Dictionary = TOOL_DEFS[tool_id]
				var node := _make_dot(def["color"])
				node.position = prev
				markers_root.add_child(node)
				point_markers[tool_id] = node
			var p : Vector3 = prev if prev != null else Vector3.ZERO
			if tool_id == Tool.PLAYER_SPAWN:
				WorldLayout.player_spawn = p
			elif tool_id == Tool.FACTORY_CENTER:
				WorldLayout.factory_center = p   # ZERO when prev == null → cleared
				_refresh_component_highlight()
			elif tool_id == Tool.COMPRESSOR_SPAWN:
				WorldLayout.compressor_spawn = p
			elif LINE_TOOL_TO_ID.has(tool_id):
				if prev == null: WorldLayout.line_starts.erase(LINE_TOOL_TO_ID[tool_id])
				else:            WorldLayout.set_line_start(LINE_TOOL_TO_ID[tool_id], p)
			status_label.text = "Undid %s placement." % str(TOOL_DEFS[tool_id]["label"])
			if tool_id == Tool.PLAYER_SPAWN: _refresh_auto_info()
		"multi":
			var tool_id2 : int = entry["tool_id"]
			var arr : Array = multi_markers.get(tool_id2, [])
			if arr.size() > 0:
				var last : MeshInstance3D = arr.pop_back()
				last.queue_free()
				multi_markers[tool_id2] = arr
				var vid : String = VEHICLE_TOOL_TO_ID[tool_id2]
				WorldLayout.remove_vehicle_spawn(vid, WorldLayout.get_vehicle_spawns(vid).size() - 1)
			status_label.text = "Undid one %s placement." % str(TOOL_DEFS[tool_id2]["label"])
		"pending_corner":
			if pending_yard_dots.size() > 0:
				pending_yard_dots.pop_back().queue_free()
				pending_yard_corners.pop_back()
				_redraw_pending_yard()
				_refresh_yard_panel()
			status_label.text = "Undid pending yard corner."
		"yard":
			# A finalised yard was undone — remove the most-recent one and
			# rebuild it into the pending state so the user can adjust.
			if finalized_yards.size() == 0: return
			var y : Dictionary = finalized_yards.pop_back()
			# Tear down its visuals.
			for d in y.get("dots", []): if is_instance_valid(d): d.queue_free()
			if y.get("poly") and is_instance_valid(y["poly"]): y["poly"].queue_free()
			if y.get("label") and is_instance_valid(y["label"]): y["label"].queue_free()
			if WorldLayout.bale_yards.size() > 0: WorldLayout.bale_yards.pop_back()
			status_label.text = "Undid last bale yard."
		_:
			status_label.text = "Nothing to undo."

func _on_clear_pressed() -> void:
	for m in point_markers.values(): m.queue_free()
	point_markers.clear()
	for tool_id in multi_markers:
		for n in multi_markers[tool_id]: n.queue_free()
	multi_markers.clear()
	_discard_pending_yard()
	for y in finalized_yards:
		for d in y.get("dots", []): if is_instance_valid(d): d.queue_free()
		if y.get("poly") and is_instance_valid(y["poly"]): y["poly"].queue_free()
		if y.get("label") and is_instance_valid(y["label"]): y["label"].queue_free()
	finalized_yards.clear()
	history.clear()
	WorldLayout.clear()
	status_label.text = "All markers cleared (not yet saved)."
	_refresh_auto_info()

# ── Marker placement / visuals ───────────────────────────────────────────────
func _place_point(tool_id: int, world_pos: Vector3) -> void:
	# Capture previous state for undo BEFORE we overwrite anything.
	var prev_pos = null
	if point_markers.has(tool_id):
		prev_pos = point_markers[tool_id].position
		point_markers[tool_id].queue_free()
	var def : Dictionary = TOOL_DEFS[tool_id]
	var node := _make_dot(def["color"])
	node.position = Vector3(world_pos.x, 0.0, world_pos.z)
	markers_root.add_child(node)
	point_markers[tool_id] = node

	# Persist to WorldLayout in-memory (saved on Save & Return). _place_point is
	# only called for `kind == "point"` tools — player spawn + line starts.
	var p := Vector3(world_pos.x, 0.0, world_pos.z)
	# #131 — FACTORY_CENTER snaps onto the centroid of whichever connected
	# component the click falls in. A slightly-off click still hits the right
	# building, and the saved value is the building's TRUE centre so
	# solidify_building.py picks the same component next time.
	if tool_id == Tool.FACTORY_CENTER and not _components.is_empty():
		var idx := _find_component_at_xz(p)
		if idx >= 0:
			var cent : Vector3 = _components[idx]["centroid"]
			p = Vector3(cent.x, 0.0, cent.z)
			node.position = p
	if tool_id == Tool.PLAYER_SPAWN:
		WorldLayout.player_spawn = p          # player spawn ONLY (decoupled from factory_center)
	elif tool_id == Tool.FACTORY_CENTER:
		WorldLayout.factory_center = p        # its own independent marker
		_refresh_component_highlight()
	elif tool_id == Tool.COMPRESSOR_SPAWN:
		WorldLayout.compressor_spawn = p
	elif LINE_TOOL_TO_ID.has(tool_id):
		WorldLayout.set_line_start(LINE_TOOL_TO_ID[tool_id], p)
	history.append({"kind": "point", "tool_id": tool_id, "prev_pos": prev_pos})
	status_label.text = "Placed %s at (%.1f, %.1f) — Ctrl+Z to undo" % [def["label"], p.x, p.z]
	# Moving the player-spawn marker re-anchors the satellite centre, so push
	# the new RD coords into the Auto-centre info label immediately.
	if tool_id == Tool.PLAYER_SPAWN:
		_refresh_auto_info()

## Marker world radius & height scale linearly with the ortho zoom so the dots
## stay roughly the same on-screen size regardless of how zoomed-in/out we are.
## Without this they'd be ~2 px (invisible) at max zoom-out, or fill the screen
## at max zoom-in.
func _marker_radius() -> float:
	return MARKER_DOT_RADIUS_REF * (cam_size / MARKER_SIZE_REF_M)
func _marker_height() -> float:
	return MARKER_DOT_HEIGHT_REF * (cam_size / MARKER_SIZE_REF_M)

func _make_dot(color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	var r := _marker_radius()
	var h := _marker_height()
	cyl.top_radius    = r
	cyl.bottom_radius = r
	cyl.height        = h
	mi.mesh = cyl
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = 0.6
	mi.material_override = m
	mi.position.y = h * 0.5
	return mi

## Iterate every placed marker — point, multi, pending corner, finalised corner
## — and resize its CylinderMesh so the dots stay clickable when the user zooms
## in or out. Called from the mouse-wheel handler.
func _rescale_markers() -> void:
	var r := _marker_radius()
	var h := _marker_height()
	var apply := func(node):
		if node == null or not is_instance_valid(node): return
		var cyl := (node as MeshInstance3D).mesh as CylinderMesh
		if cyl == null: return
		cyl.top_radius = r; cyl.bottom_radius = r; cyl.height = h
		(node as MeshInstance3D).position.y = h * 0.5
	for tool_id in point_markers: apply.call(point_markers[tool_id])
	for tool_id in multi_markers:
		for n in multi_markers[tool_id]: apply.call(n)
	for d in pending_yard_dots: apply.call(d)
	for y in finalized_yards:
		for d in y.get("dots", []): apply.call(d)

# =============================================================================
# Multi-instance vehicle placement
# =============================================================================
func _add_multi_marker(tool_id: int, world_pos: Vector3) -> void:
	var def : Dictionary = TOOL_DEFS[tool_id]
	var node := _make_dot(def["color"])
	node.position = Vector3(world_pos.x, node.position.y, world_pos.z)
	markers_root.add_child(node)
	var arr : Array = multi_markers.get(tool_id, [])
	arr.append(node)
	multi_markers[tool_id] = arr
	var vid : String = VEHICLE_TOOL_TO_ID[tool_id]
	WorldLayout.add_vehicle_spawn(vid, Vector3(world_pos.x, 0.0, world_pos.z))
	history.append({"kind": "multi", "tool_id": tool_id, "pos": Vector3(world_pos.x, 0.0, world_pos.z)})
	status_label.text = "Placed %s (%d total) — right-click to delete." % [def["label"], arr.size()]

# =============================================================================
# Polygonal bale yard (collect 4 corners → assign supplier → commit)
# =============================================================================
const YARD_CORNER_COLOR := Color(1.0, 0.85, 0.2)   # tagged corner dot
const YARD_FILL_COLOR   := Color(0.9, 0.75, 0.10, YARD_PREVIEW_ALPHA + 0.20)
const YARD_PENDING_FILL := Color(1.0, 0.95, 0.30, YARD_PREVIEW_ALPHA - 0.05)

func _add_yard_corner(world_pos: Vector3) -> void:
	if pending_yard_corners.size() >= 4:
		status_label.text = "4 corners placed — confirm or discard in the left sidebar."
		return
	var dot := _make_dot(YARD_CORNER_COLOR)
	dot.position = Vector3(world_pos.x, dot.position.y, world_pos.z)
	markers_root.add_child(dot)
	pending_yard_corners.append(Vector3(world_pos.x, 0.0, world_pos.z))
	pending_yard_dots.append(dot)
	_redraw_pending_yard()
	_refresh_yard_panel()
	history.append({"kind": "pending_corner"})
	status_label.text = "Yard corner %d / 4 — drag to adjust, right-click to remove." % pending_yard_corners.size()

## Build (or rebuild) the translucent polygon between the pending corners. Uses
## the simple "fan triangulation" from the first corner — fine for convex
## quads, which is what the user is drawing.
func _redraw_pending_yard() -> void:
	if pending_yard_poly:
		pending_yard_poly.queue_free()
		pending_yard_poly = null
	if pending_yard_corners.size() < 3:
		return
	pending_yard_poly = _build_polygon_mesh(pending_yard_corners, YARD_PENDING_FILL)
	markers_root.add_child(pending_yard_poly)

func _build_polygon_mesh(corners: Array, color: Color) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(1, corners.size() - 1):
		var p0 : Vector3 = corners[0];          p0.y = 0.02
		var p1 : Vector3 = corners[i];          p1.y = 0.02
		var p2 : Vector3 = corners[i + 1];      p2.y = 0.02
		st.add_vertex(p0)
		st.add_vertex(p1)
		st.add_vertex(p2)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	return mi

## Show/hide + update the pending-yard panel in the left sidebar based on how
## many corners are placed. Visible only when 1–4 corners exist; the Confirm
## button is disabled until exactly 4 are set.
func _refresh_yard_panel() -> void:
	if yard_panel == null: return
	var n := pending_yard_corners.size()
	yard_panel.visible = (n > 0)
	if yard_status_lbl:
		yard_status_lbl.text = "Pending yard: %d / 4 corners" % n
	# Confirm button is the 4th child (after status label, "Supplier:", select).
	for child in yard_panel.get_children():
		if child is Button and (child as Button).text == "Confirm yard":
			(child as Button).disabled = (n != 4)

func _confirm_pending_yard() -> void:
	if pending_yard_corners.size() != 4:
		status_label.text = "Place 4 corners before confirming."
		return
	var supplier_id : String = supplier_select.get_item_metadata(supplier_select.selected) if supplier_select else ""
	if supplier_id == "":
		status_label.text = "Pick a supplier before confirming."
		return
	# Replace the pending preview with a permanent yard polygon, tagged for the
	# supplier. Keep the corner dots so the user can keep dragging them later.
	if pending_yard_poly: pending_yard_poly.queue_free()
	pending_yard_poly = null
	var poly := _build_polygon_mesh(pending_yard_corners, YARD_FILL_COLOR)
	markers_root.add_child(poly)
	# Supplier label hovering above the yard centroid.
	var centroid := Vector3.ZERO
	for c in pending_yard_corners: centroid += c
	centroid /= float(pending_yard_corners.size())
	var lbl := Label3D.new()
	lbl.text = supplier_id
	lbl.font_size = 56
	lbl.pixel_size = 0.02
	lbl.modulate = Color(0.15, 0.1, 0.0)
	lbl.position = Vector3(centroid.x, 0.5, centroid.z)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	markers_root.add_child(lbl)
	var yard := {
		"supplier_id": supplier_id,
		"corners":     pending_yard_corners.duplicate(true),
		"dots":        pending_yard_dots.duplicate(false),
		"poly":        poly,
		"label":       lbl,
	}
	finalized_yards.append(yard)
	# Clear pending state — fresh slate for the next yard.
	pending_yard_corners = []
	pending_yard_dots    = []
	WorldLayout.add_bale_yard(supplier_id, yard["corners"])
	history.append({"kind": "yard", "data": yard})
	_refresh_yard_panel()
	status_label.text = "Bale yard for '%s' confirmed. Click another corner to start a new yard." % supplier_id

func _discard_pending_yard() -> void:
	for d in pending_yard_dots:
		if is_instance_valid(d): d.queue_free()
	if pending_yard_poly and is_instance_valid(pending_yard_poly):
		pending_yard_poly.queue_free()
	pending_yard_corners.clear()
	pending_yard_dots.clear()
	pending_yard_poly = null
	_refresh_yard_panel()

func _remove_finalized_yard(yi: int) -> void:
	if yi < 0 or yi >= finalized_yards.size(): return
	var y : Dictionary = finalized_yards[yi]
	for d in y.get("dots", []):
		if is_instance_valid(d): d.queue_free()
	if y.get("poly") and is_instance_valid(y["poly"]):  y["poly"].queue_free()
	if y.get("label") and is_instance_valid(y["label"]): y["label"].queue_free()
	finalized_yards.remove_at(yi)
	if yi < WorldLayout.bale_yards.size():
		WorldLayout.bale_yards.remove_at(yi)

## When a dragged finalised-yard corner moves, rebuild its polygon so the
## visual stays in sync with the dot positions.
func _update_finalized_yard_drag(_hit: Vector3) -> void:
	if dragging_yard_idx < 0 or dragging_yard_idx >= finalized_yards.size(): return
	var y : Dictionary = finalized_yards[dragging_yard_idx]
	var dots : Array = y.get("dots", [])
	var corners : Array = []
	for d in dots:
		var md : MeshInstance3D = d
		corners.append(Vector3(md.position.x, 0.0, md.position.z))
	# Rebuild the polygon mesh + centroid for the supplier label.
	if y.get("poly") and is_instance_valid(y["poly"]): y["poly"].queue_free()
	y["poly"] = _build_polygon_mesh(corners, YARD_FILL_COLOR)
	markers_root.add_child(y["poly"])
	y["corners"] = corners
	if y.get("label") and is_instance_valid(y["label"]):
		var centroid := Vector3.ZERO
		for c in corners: centroid += c
		centroid /= float(max(1, corners.size()))
		(y["label"] as Label3D).position = Vector3(centroid.x, 0.5, centroid.z)

func _apply_loaded_layout() -> void:
	# Player spawn (single)
	if WorldLayout.player_spawn != Vector3.ZERO:
		var node := _make_dot(TOOL_DEFS[Tool.PLAYER_SPAWN]["color"])
		node.position = Vector3(WorldLayout.player_spawn.x, node.position.y, WorldLayout.player_spawn.z)
		markers_root.add_child(node)
		point_markers[Tool.PLAYER_SPAWN] = node
	# Factory center (single, independent of player spawn)
	if WorldLayout.factory_center != Vector3.ZERO:
		var fc_node := _make_dot(TOOL_DEFS[Tool.FACTORY_CENTER]["color"])
		fc_node.position = Vector3(WorldLayout.factory_center.x, fc_node.position.y, WorldLayout.factory_center.z)
		markers_root.add_child(fc_node)
		point_markers[Tool.FACTORY_CENTER] = fc_node
	# #221-PC Phase 5 — operator-draggable markers (parking + Swift).
	if WorldLayout.staff_parking != Vector3.ZERO:
		var sp_node := _make_dot(TOOL_DEFS[Tool.STAFF_PARKING]["color"])
		sp_node.position = Vector3(WorldLayout.staff_parking.x, sp_node.position.y, WorldLayout.staff_parking.z)
		markers_root.add_child(sp_node)
		point_markers[Tool.STAFF_PARKING] = sp_node
	if WorldLayout.player_swift != Vector3.ZERO:
		var sw_node := _make_dot(TOOL_DEFS[Tool.PLAYER_SWIFT]["color"])
		sw_node.position = Vector3(WorldLayout.player_swift.x, sw_node.position.y, WorldLayout.player_swift.z)
		markers_root.add_child(sw_node)
		point_markers[Tool.PLAYER_SWIFT] = sw_node
	if WorldLayout.compressor_spawn != Vector3.ZERO:
		var cs_node := _make_dot(TOOL_DEFS[Tool.COMPRESSOR_SPAWN]["color"])
		cs_node.position = Vector3(WorldLayout.compressor_spawn.x, cs_node.position.y, WorldLayout.compressor_spawn.z)
		markers_root.add_child(cs_node)
		point_markers[Tool.COMPRESSOR_SPAWN] = cs_node
	# Vehicles — arrays of positions per type
	for k in VEHICLE_TOOL_TO_ID:
		var vid : String = VEHICLE_TOOL_TO_ID[k]
		var arr : Array = WorldLayout.get_vehicle_spawns(vid)
		for pos in arr:
			var node2 := _make_dot(TOOL_DEFS[k]["color"])
			node2.position = Vector3(pos.x, node2.position.y, pos.z)
			markers_root.add_child(node2)
			var bucket : Array = multi_markers.get(k, [])
			bucket.append(node2)
			multi_markers[k] = bucket
	# Line starts (single per id)
	for k in LINE_TOOL_TO_ID:
		var lid : String = LINE_TOOL_TO_ID[k]
		if WorldLayout.line_starts.has(lid):
			var node3 := _make_dot(TOOL_DEFS[k]["color"])
			var p : Vector3 = WorldLayout.line_starts[lid]
			node3.position = Vector3(p.x, node3.position.y, p.z)
			markers_root.add_child(node3)
			point_markers[k] = node3
	# Polygonal bale yards
	for y in WorldLayout.bale_yards:
		var corners : Array = y.get("corners", [])
		if corners.size() < 3: continue
		var dots : Array = []
		for c in corners:
			var dot := _make_dot(YARD_CORNER_COLOR)
			dot.position = Vector3(c.x, dot.position.y, c.z)
			markers_root.add_child(dot)
			dots.append(dot)
		var poly := _build_polygon_mesh(corners, YARD_FILL_COLOR)
		markers_root.add_child(poly)
		var centroid := Vector3.ZERO
		for c2 in corners: centroid += c2
		centroid /= float(corners.size())
		var lbl := Label3D.new()
		lbl.text = String(y.get("supplier_id", ""))
		lbl.font_size = 56
		lbl.pixel_size = 0.02
		lbl.modulate = Color(0.15, 0.1, 0.0)
		lbl.position = Vector3(centroid.x, 0.5, centroid.z)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		markers_root.add_child(lbl)
		finalized_yards.append({
			"supplier_id": y.get("supplier_id", ""),
			"corners":     corners.duplicate(true),
			"dots":        dots,
			"poly":        poly,
			"label":       lbl,
		})

# ── Save / cancel ────────────────────────────────────────────────────────────
func _on_save_pressed() -> void:
	_commit_to_layout()   # bake the current marker calibration into the saved coords
	WorldLayout.save()
	status_label.text = "Saved — returning to main menu"
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

func _on_back_pressed() -> void:
	# Reload so unsaved edits are discarded (re-read from disk).
	WorldLayout._load()
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

# ── PDOK Luchtfoto WMS fetch ─────────────────────────────────────────────────
## Update the sidebar's "Auto-centre" info label to reflect whichever centre
## the next Fetch will use (override / player spawn / shell, in priority order).
func _refresh_auto_info(lbl: Label = null) -> void:
	var node : Label = lbl
	if node == null:
		node = find_child("AutoInfo", true, false) as Label
	if node == null: return
	var c : Dictionary = _satellite_center()
	var rd : Vector2 = c["rd"]
	node.text = "Auto-centre: %s\nRD (%.0f, %.0f)" % [c["label"], rd.x, rd.y]

## The satellite tile's centre is the FACTORY CENTER marker. Period.
##
## Previously a priority chain (lat/lon override > player_spawn > building
## shell AABB) silently picked whatever was available, which meant the
## operator could place factory_center and the satellite would still land
## somewhere else — the building-shell AABB centre, usually nowhere near
## what the operator meant. The fix: factory_center is the single source of
## truth. If it's not set, we tell the operator to set it; we do NOT fall
## back to "best guess" centres that move the tile somewhere random.
##
## The only fallback is the building shell, used when factory_center has
## never been placed (fresh save) — so the first Fetch shows the plant. Once
## the operator clicks Factory Center even ONCE, that pin owns the tile.
func _satellite_center() -> Dictionary:
	var fc : Vector3 = WorldLayout.factory_center
	if fc != Vector3.ZERO:
		# Two sub-cases — both pin the satellite to the factory_center marker.
		# a) Still in REAL RD scale (~1e5): the marker IS a valid Dutch coord.
		if absf(fc.x) > 10000.0 or absf(fc.z) > 10000.0:
			return {"rd": Vector2(fc.x, -fc.z), "world": Vector3(fc.x, 0.0, fc.z), "label": "factory center (RD)"}
		# b) Already localized to a small frame: combine the marker's local XZ
		# with the building's TRUE baked RD so the WMS query asks for the right
		# patch of Dutch ground, and park the local quad where the operator
		# placed the marker.
		var rd_base : Vector3 = _shell_rd_center if _shell_rd_center != Vector3.ZERO else shell_center
		var rd_fc : Vector2 = Vector2(rd_base.x + fc.x, -(rd_base.z + fc.z))
		return {"rd": rd_fc, "world": Vector3(fc.x, 0.0, fc.z), "label": "factory center"}
	# No factory_center placed yet — first-time fetch shows the building so
	# the operator can place the marker on top of the right spot. After they
	# place it, every subsequent fetch follows the marker.
	var rd_src : Vector3 = _shell_rd_center if _shell_rd_center != Vector3.ZERO else shell_center
	return {"rd": Vector2(rd_src.x, -rd_src.z), "world": Vector3(shell_center.x, 0.0, shell_center.z), "label": "building shell (place Factory center to override)"}

func _on_fetch_satellite() -> void:
	var extent_m : float = float(extent_input.text) if extent_input else float(DEFAULT_EXTENT_M)
	if extent_m <= 0.0: extent_m = DEFAULT_EXTENT_M
	var c : Dictionary = _satellite_center()
	var rd : Vector2 = c["rd"]
	# Park the ground quad under the SAME XZ as the satellite centre so the
	# image visually aligns with what the camera is over.
	ground_quad.position = (c["world"] as Vector3) + Vector3(0, -0.05, 0)
	print("[WorldSetup] satellite centre = %s → RD (%.1f, %.1f)" % [c["label"], rd.x, rd.y])
	var half := extent_m * 0.5
	# WMS 1.3.0 + projected CRS uses (minX,minY,maxX,maxY) axis order.
	var bbox := "%f,%f,%f,%f" % [rd.x - half, rd.y - half, rd.x + half, rd.y + half]
	var url := "%s?service=WMS&version=1.3.0&request=GetMap&layers=%s&crs=EPSG:28992&bbox=%s&width=%d&height=%d&format=image/png" % [
		PDOK_WMS, PDOK_LAYER, bbox, WMS_IMG_SIZE, WMS_IMG_SIZE
	]
	status_label.text = "Fetching satellite tile…"
	print("[WorldSetup] WMS GET: %s" % url)
	var req := HTTPRequest.new()
	req.set_tls_options(TLSOptions.client())
	add_child(req)
	req.request_completed.connect(_on_satellite_fetched.bind(req, extent_m, rd))
	var err := req.request(url)
	if err != OK:
		status_label.text = "HTTP error: %s" % str(err)

func _on_satellite_fetched(result: int, code: int, headers: PackedStringArray, body: PackedByteArray, req: HTTPRequest, extent_m: float, rd_center: Vector2) -> void:
	req.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		status_label.text = "Satellite fetch failed (HTTP %d, result %d)" % [code, result]
		print("[WorldSetup] WMS fail body prefix: %s" % body.slice(0, 200).get_string_from_utf8())
		return
	# PDOK Luchtfoto may return PNG or JPEG. Sniff and decode either.
	var img := Image.new()
	var err := ERR_INVALID_DATA
	# PNG magic: 89 50 4E 47
	if body.size() > 4 and body[0] == 0x89 and body[1] == 0x50:
		err = img.load_png_from_buffer(body)
	# JPEG magic: FF D8 FF
	elif body.size() > 3 and body[0] == 0xFF and body[1] == 0xD8:
		err = img.load_jpg_from_buffer(body)
	else:
		# Probably an XML/HTML error response from the WMS server.
		var prefix := body.slice(0, 300).get_string_from_utf8()
		status_label.text = "WMS returned non-image — see console"
		print("[WorldSetup] non-image response: %s" % prefix)
		print("[WorldSetup] response headers: %s" % str(headers))
		return
	if err != OK:
		status_label.text = "Could not decode satellite (err %d)" % err
		return
	# Cache as PNG regardless of source format so re-entry path is uniform.
	img.save_png(SATELLITE_CACHE)
	# Park the quad at the LOCAL display centre (the building shell, which is shifted
	# to the origin), NOT at the raw RD coordinate. rd_center is only the geographic
	# FETCH location (~184,000); positioning the tile there drops it ~184 km from the
	# markers and it renders invisible — the "fetched but blank/not loading" bug.
	var world_center : Vector3 = _satellite_center()["world"]
	_apply_satellite_image(img, extent_m, world_center)
	WorldLayout.satellite_center_rd = rd_center
	WorldLayout.satellite_extent_m  = extent_m
	WorldLayout.has_satellite       = true
	status_label.text = "Satellite loaded (%.0f m extent, RD %.0f/%.0f)" % [extent_m, rd_center.x, rd_center.y]

## WGS84 (lat,lon decimal degrees) → RD New (EPSG:28992) easting/northing in m.
## Polynomial approximation; sub-metre accurate inside the Netherlands.
## Source: PDOK / Kadaster documented coefficients (Schreutelkamp & Strang 2001).
func _wgs84_to_rd(lat: float, lon: float) -> Vector2:
	const PHI0 := 52.15517440
	const LAM0 := 5.38720621
	var dphi := 0.36 * (lat - PHI0)
	var dlam := 0.36 * (lon - LAM0)
	var x := 155000.0 \
		+ 190094.945    * dlam \
		-  11832.228    * dphi * dlam \
		-    114.221    * dphi * dphi * dlam \
		-     32.391    * dlam * dlam * dlam \
		-      2.340    * dphi * dphi * dphi * dlam \
		-      0.608    * dphi * dlam * dlam * dlam \
		-      0.008    * dlam * dlam \
		+      0.148    * dphi * dphi * dlam * dlam * dlam
	var y := 463000.0 \
		+ 309056.544    * dphi \
		+   3638.893    * dlam * dlam \
		+     73.077    * dphi * dphi \
		-    157.984    * dphi * dlam * dlam \
		+     59.788    * dphi * dphi * dphi \
		+      0.433    * dlam \
		-      6.439    * dphi * dphi * dlam * dlam \
		-     44.840    * dphi * dphi * dphi * dlam * dlam \
		+      0.092    * dlam * dlam * dlam * dlam \
		-      0.054    * dphi * dlam * dlam * dlam * dlam
	return Vector2(x, y)

func _try_load_cached_satellite() -> void:
	if not FileAccess.file_exists(SATELLITE_CACHE):
		# No tile on disk yet — make sure the user knows where to find Fetch.
		if status_label:
			status_label.text = "No satellite tile yet — click Fetch satellite (right sidebar) to load one."
		return
	var img := Image.new()
	if img.load(SATELLITE_CACHE) != OK: return
	var ext : float = WorldLayout.satellite_extent_m if WorldLayout.has_satellite else float(DEFAULT_EXTENT_M)
	# Position the cached tile at the LOCAL building centre, NOT the raw RD centre.
	# The RD value (~184,000 / ~329,000) is only the geographic fetch location; the
	# quad must sit over the building + markers near the origin, or it renders ~184 km
	# away and is invisible. _satellite_center() resolves to the building shell here
	# (player_spawn localizes to 0,0), so the overlay lands on the plant. (#layout)
	var center : Vector3 = _satellite_center()["world"]
	_apply_satellite_image(img, ext, center)

## `center_world` is the game-world XZ position the quad should sit at — i.e.
## the centre of the geographic area the tile actually shows. Lets the quad
## follow whichever centre _satellite_center() returned (override / shell).
func _apply_satellite_image(img: Image, extent_m: float, center_world: Vector3) -> void:
	var tex := ImageTexture.create_from_image(img)
	ground_material.albedo_texture = tex
	ground_material.albedo_color   = Color(1, 1, 1)
	# Unshaded so the texture reads true to colour regardless of ambient lighting.
	ground_material.shading_mode   = BaseMaterial3D.SHADING_MODE_UNSHADED
	(ground_quad.mesh as PlaneMesh).size = Vector2(extent_m, extent_m)
	ground_quad.position = Vector3(center_world.x, -0.05, center_world.z)
