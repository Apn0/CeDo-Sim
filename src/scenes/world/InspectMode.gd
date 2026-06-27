extends Node3D

class_name InspectMode

## #inspect — READ-ONLY diagnostic overlay (F8 in MainWorld).
##
## When active, surfaces every WorldLayout marker as a colour-coded 3D gizmo plus
## a 3D label, AND drops the same satellite tile + floor-plan PNG used by
## WorldSetup as semi-transparent ground overlays. A free-fly camera (InspectFlyCam)
## takes over the viewport; the player capsule freezes in place. Toggling off
## restores the previous camera and player input cleanly.
##
## Each layout marker is rendered TWICE:
##   • OPAQUE gizmo at  MainWorld._layout_to_scene(saved_marker) — where the
##     world ACTUALLY put the corresponding object (post-rotation/anchor).
##   • 50%-alpha gizmo at the raw saved coords (no transform) — the BEFORE
##     position the operator drew in WorldSetup. The visual delta is the
##     diagnostic information for rotation/anchor debugging.
##
## All children are spawned on activate() and torn down on deactivate() — when
## Inspect Mode is OFF there are zero nodes and zero per-frame work.

const FLY_CAM_SCRIPT := preload("res://src/scenes/world/InspectFlyCam.gd")

# ── State ─────────────────────────────────────────────────────────────────────
var _active : bool = false
var _world : Node3D = null            # MainWorld (the parent)
var _player : CharacterBody3D = null  # cached PlayerController
var _previous_camera : Camera3D = null  # whatever was .current before we took over
var _fly_cam : Camera3D = null        # our free-fly Camera3D (script: InspectFlyCam)

# Gizmo container — single child Node3D so deactivate() can free it in one call.
var _gizmo_root : Node3D = null

# UI overlay (top-left coord readout)
var _canvas : CanvasLayer = null
var _readout : Label = null

# Cached marker list for the readout's "nearest marker" calculation: [{name, scene_pos}]
var _marker_index : Array = []

# ── Constants ────────────────────────────────────────────────────────────────
const SPHERE_RADIUS_M : float = 0.5
const RAW_ALPHA : float = 0.5            # contrasting-alpha for the BEFORE-transform gizmos
const SAT_OVERLAY_ALPHA : float = 0.55   # task spec
const FP_OVERLAY_ALPHA  : float = 0.55   # mirror satellite — calibrated against the satellite anyway
const SAT_OVERLAY_Y     : float = 0.1    # just above floor
const FP_OVERLAY_Y      : float = 0.12   # 2 cm above sat so they don't z-fight
const LABEL_HEIGHT_M    : float = 1.2    # how high the Label3D sits above its sphere

# Gizmo colours
const COLOR_PLAYER_SPAWN    : Color = Color(1.0, 0.0, 1.0)       # magenta
const COLOR_FACTORY_CENTER  : Color = Color(0.0, 1.0, 1.0)       # cyan
const COLOR_COMPRESSOR      : Color = Color(1.0, 0.55, 0.0)      # orange
const COLOR_VEHICLE         : Color = Color(0.0, 1.0, 0.0)       # green
const COLOR_LINE_START      : Color = Color(1.0, 1.0, 0.0)       # yellow
const COLOR_BALE_YARD       : Color = Color(1.0, 0.0, 0.0)       # red
const COLOR_RAW_TINT        : Color = Color(0.95, 0.95, 0.95)    # neutral-white (gets alpha)

# Runtime-centroid colours — distinct from layout-marker colours so the operator
# can tell "where I drew it" (above) from "where it actually IS now" (below).
# When the WorldSetup→runtime transform is correct, the layout-green sphere and
# the runtime-lime dot land on top of each other. When parking is wrong, the
# delta between them IS the bug.
const COLOR_RUNTIME_VEHICLE : Color = Color(0.5, 1.0, 0.2)       # lime  (paired with green VEHICLE)
const COLOR_RUNTIME_NPC     : Color = Color(0.3, 0.8, 1.0)       # sky   (no layout pairing; standalone)
const COLOR_RUNTIME_OBJECT  : Color = Color(1.0, 0.75, 0.85)     # pink  (placeables: machines, belts, etc.)
const CENTROID_RADIUS_M     : float = 0.30
const CENTROID_LABEL_PX     : float = 0.005

# Runtime centroid counts — populated by _spawn_runtime_centroids(), shown in the readout.
var _runtime_counts : Dictionary = {"vehicle": 0, "npc": 0, "object": 0}

# ── Public API ───────────────────────────────────────────────────────────────
func setup(world: Node3D) -> void:
	_world = world

func is_active() -> bool:
	return _active

func toggle() -> void:
	if _active:
		deactivate()
	else:
		activate()

func activate() -> void:
	if _active:
		return
	_active = true
	visible = true
	# Cache the player ref so deactivate() can hand input back cleanly even if
	# MainWorld replaces it later.
	if _world != null and "player" in _world:
		_player = _world.get("player") as CharacterBody3D
	# Snapshot which camera owns the viewport now so we can restore it later.
	_previous_camera = _find_current_camera()
	_spawn_fly_cam()
	_spawn_gizmos()
	_spawn_runtime_centroids()
	_spawn_overlays()
	_spawn_readout()
	# Freeze the player capsule and hand mouse-look over to the fly cam. The
	# player's CameraRig is deactivated so its mouse-look + F4-modal stay quiet.
	_freeze_player(true)
	print("[InspectMode] ON — %d markers indexed, runtime: vehicles=%d npcs=%d objects=%d" % [
		_marker_index.size(),
		int(_runtime_counts.get("vehicle", 0)),
		int(_runtime_counts.get("npc", 0)),
		int(_runtime_counts.get("object", 0)),
	])

func deactivate() -> void:
	if not _active:
		return
	_active = false
	visible = false
	# Restore player movement + camera ownership BEFORE freeing the fly cam so
	# the original camera goes current in the same frame the fly cam goes away.
	_freeze_player(false)
	if _previous_camera != null and is_instance_valid(_previous_camera):
		_previous_camera.current = true
	if _fly_cam != null and is_instance_valid(_fly_cam):
		_fly_cam.queue_free()
		_fly_cam = null
	if _gizmo_root != null and is_instance_valid(_gizmo_root):
		_gizmo_root.queue_free()
		_gizmo_root = null
	if _canvas != null and is_instance_valid(_canvas):
		_canvas.queue_free()
		_canvas = null
		_readout = null
	_marker_index.clear()
	_runtime_counts = {"vehicle": 0, "npc": 0, "object": 0}
	print("[InspectMode] OFF — gizmos + fly cam removed")

# ── Per-frame readout ────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not _active or _readout == null or _fly_cam == null:
		return
	if not is_instance_valid(_fly_cam):
		return
	var cam_pos : Vector3 = _fly_cam.global_position
	var basis := _fly_cam.global_transform.basis
	# yaw  = rotation around +Y, pitch = elevation. Use -basis.z (forward).
	var fwd : Vector3 = -basis.z
	var yaw_deg := rad_to_deg(atan2(fwd.x, fwd.z))
	var pitch_deg := rad_to_deg(asin(clampf(fwd.y, -1.0, 1.0)))
	# Look-at floor: trace cam→cam+fwd*∞ to y=0 plane.
	var floor_xz : Vector2 = _ray_to_floor(cam_pos, fwd)
	# Layout anchor + world_yaw — pulled via _world_frame forwarders if available.
	var anchor_x : float = NAN
	var anchor_z : float = NAN
	var world_yaw_deg : float = NAN
	if _world != null:
		var anchor_v : Variant = _world.call("_layout_anchor_xz") if _world.has_method("_layout_anchor_xz") else null
		if anchor_v is Vector3:
			anchor_x = (anchor_v as Vector3).x
			anchor_z = (anchor_v as Vector3).z
		var wy_v : Variant = _world.call("_world_yaw") if _world.has_method("_world_yaw") else null
		if wy_v != null:
			world_yaw_deg = rad_to_deg(float(wy_v))
	# Nearest marker (XZ horizontal distance from cam).
	var nearest_name := "—"
	var nearest_dist : float = INF
	for m in _marker_index:
		var p : Vector3 = m["scene_pos"]
		var d := Vector2(cam_pos.x - p.x, cam_pos.z - p.z).length()
		if d < nearest_dist:
			nearest_dist = d
			nearest_name = String(m["name"])
	var floor_str : String = "  (no floor hit)"
	if is_finite(floor_xz.x):
		floor_str = "(%.1f, %.1f)" % [floor_xz.x, floor_xz.y]
	var anchor_str := "—"
	if is_finite(anchor_x):
		anchor_str = "(%.1f, %.1f)" % [anchor_x, anchor_z]
	var wy_str := "—"
	if is_finite(world_yaw_deg):
		wy_str = "%.1f" % world_yaw_deg
	var nearest_str : String = "%s at %.1fm" % [nearest_name, nearest_dist] if is_finite(nearest_dist) else "—"
	_readout.text = (
		"INSPECT MODE  (F8 toggle · WASD fly · Space/Ctrl up/down · Shift sprint · Esc exit)\n"
		+ "cam: (%.1f, %.1f, %.1f)  yaw: %.1f  pitch: %.1f\n"
		+ "anchor: %s  world_yaw: %s\n"
		+ "look-at floor: %s  nearest_marker: %s\n"
		+ "runtime centroids — vehicles: %d (lime)  npcs: %d (sky)  objects: %d (pink)"
	) % [
		cam_pos.x, cam_pos.y, cam_pos.z, yaw_deg, pitch_deg,
		anchor_str, wy_str,
		floor_str, nearest_str,
		int(_runtime_counts.get("vehicle", 0)),
		int(_runtime_counts.get("npc", 0)),
		int(_runtime_counts.get("object", 0)),
	]

# ── Input ────────────────────────────────────────────────────────────────────
## Esc OR F8 exits Inspect Mode while it's active. We use _unhandled_input
## because PlayerController has been input-suspended for the duration — its
## own F8 listener can't fire so we must own the toggle-off path. Esc is
## intercepted with set_input_as_handled so the HUD pause card doesn't open
## under the gizmos.
func _unhandled_input(event: InputEvent) -> void:
	if not _active:
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k := event as InputEventKey
		var kc : int = k.keycode if k.keycode != 0 else k.physical_keycode
		if kc == KEY_ESCAPE or kc == KEY_F8:
			deactivate()
			get_viewport().set_input_as_handled()
			return

# ── Gizmo spawn ──────────────────────────────────────────────────────────────
func _spawn_gizmos() -> void:
	_gizmo_root = Node3D.new()
	_gizmo_root.name = "Gizmos"
	add_child(_gizmo_root)
	_marker_index.clear()
	# Single player_spawn marker (magenta)
	if WorldLayout.player_spawn != Vector3.ZERO:
		_spawn_marker_pair(WorldLayout.player_spawn, "player_spawn", COLOR_PLAYER_SPAWN)
	# Single factory_center marker (cyan)
	if WorldLayout.factory_center != Vector3.ZERO:
		_spawn_marker_pair(WorldLayout.factory_center, "factory_center", COLOR_FACTORY_CENTER)
	# Optional compressor (orange)
	if WorldLayout.compressor_spawn != Vector3.ZERO:
		_spawn_marker_pair(WorldLayout.compressor_spawn, "compressor", COLOR_COMPRESSOR)
	# Vehicle spawns — dict of id → Array[Vector3]
	for vid in WorldLayout.vehicle_spawns.keys():
		var arr : Array = WorldLayout.vehicle_spawns[vid]
		if not (arr is Array):
			continue
		for i in range(arr.size()):
			var p = arr[i]
			if p is Vector3:
				_spawn_marker_pair(p, "%s#%d" % [String(vid), i + 1], COLOR_VEHICLE)
	# Line starts — dict of id → Vector3
	for lid in WorldLayout.line_starts.keys():
		var p2 = WorldLayout.line_starts[lid]
		if p2 is Vector3:
			_spawn_marker_pair(p2, "line %s" % String(lid), COLOR_LINE_START, true)
	# Bale yards — array of {supplier_id, corners}
	for i in range(WorldLayout.bale_yards.size()):
		var yd = WorldLayout.bale_yards[i]
		if not (yd is Dictionary):
			continue
		_spawn_yard_gizmo(yd as Dictionary, i)

## Render both the SCENE-space gizmo (opaque) and the RAW gizmo (50% alpha,
## neutral-tinted) plus a Label3D on the scene one. Add the scene marker to
## _marker_index for the nearest-marker readout.
##
## `is_flag` switches the geometry from sphere → flag (small box on a thin
## pole) — used for line_starts so they're visually distinct from spheres.
func _spawn_marker_pair(saved: Vector3, label: String, col: Color, is_flag: bool = false) -> void:
	var scene_pos := _layout_to_scene(saved)
	# OPAQUE — at the post-transform scene position.
	_spawn_single_gizmo(scene_pos, label, col, 1.0, is_flag, true)
	# RAW — at the literal saved coords, contrasting tint at 50 % alpha.
	_spawn_single_gizmo(saved, label + " (raw)", _raw_tint(col), RAW_ALPHA, is_flag, false)
	_marker_index.append({"name": label, "scene_pos": scene_pos})

## Single gizmo: sphere-or-flag + (optional) Label3D above it.
func _spawn_single_gizmo(pos: Vector3, label: String, col: Color, alpha: float,
		is_flag: bool, with_label: bool) -> void:
	var holder := Node3D.new()
	holder.name = label
	holder.position = pos
	_gizmo_root.add_child(holder)
	if is_flag:
		_build_flag(holder, col, alpha)
	else:
		_build_sphere(holder, SPHERE_RADIUS_M, col, alpha)
	if with_label:
		_build_label(holder, label, col)

## Build a unique-instance MeshInstance3D so per-instance alpha works without
## stomping a shared material. Always Unshaded + cull-disabled so the gizmo
## reads from any angle / any lighting condition.
func _build_sphere(parent: Node3D, r: float, col: Color, alpha: float) -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = r
	sm.height = r * 2.0
	mi.mesh = sm
	mi.material_override = _make_mat(col, alpha)
	parent.add_child(mi)

## Flag = thin vertical pole + small horizontal box at the top. Used for line_starts.
func _build_flag(parent: Node3D, col: Color, alpha: float) -> void:
	var pole := MeshInstance3D.new()
	var pm := CylinderMesh.new()
	pm.top_radius = 0.05
	pm.bottom_radius = 0.05
	pm.height = 2.0
	pole.mesh = pm
	pole.position = Vector3(0.0, 1.0, 0.0)
	pole.material_override = _make_mat(col, alpha)
	parent.add_child(pole)
	var flag := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.5, 0.05)
	flag.mesh = bm
	flag.position = Vector3(0.45, 1.85, 0.0)
	flag.material_override = _make_mat(col, alpha)
	parent.add_child(flag)

## Build a billboarded depth-test-off Label3D so the text is always readable.
func _build_label(parent: Node3D, text: String, col: Color) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.006
	lbl.modulate = col
	lbl.outline_modulate = Color(0.0, 0.0, 0.0)
	lbl.outline_size = 8
	lbl.position = Vector3(0.0, LABEL_HEIGHT_M, 0.0)
	parent.add_child(lbl)

## 4 small red spheres (one per corner) + translucent red polygon fill + a
## centroid label "yard <i>: <supplier>".
func _spawn_yard_gizmo(yd: Dictionary, idx: int) -> void:
	var corners_raw : Array = yd.get("corners", [])
	if corners_raw.size() < 3:
		return
	var supplier : String = String(yd.get("supplier_id", "?"))
	var label_base := "yard %d: %s" % [idx + 1, supplier]
	# --- SCENE (post-transform) gizmo: corner markers + polygon fill + label ---
	var corners_scene : Array = []
	for c in corners_raw:
		if c is Vector3:
			corners_scene.append(_layout_to_scene(c))
	_build_yard_corners(corners_scene, COLOR_BALE_YARD, 1.0)
	_build_yard_polygon(corners_scene, COLOR_BALE_YARD, 0.35)
	var centroid := _centroid(corners_scene)
	_build_yard_label(centroid, label_base, COLOR_BALE_YARD)
	_marker_index.append({"name": label_base, "scene_pos": centroid})
	# --- RAW (pre-transform) gizmo at the literal saved coords ---
	var corners_raw_v3 : Array = []
	for c in corners_raw:
		if c is Vector3:
			corners_raw_v3.append(c)
	_build_yard_corners(corners_raw_v3, _raw_tint(COLOR_BALE_YARD), RAW_ALPHA)
	_build_yard_polygon(corners_raw_v3, _raw_tint(COLOR_BALE_YARD), RAW_ALPHA * 0.5)

# ── Runtime centroids ────────────────────────────────────────────────────────
## Drops a small labeled sphere at the global_position of every spawned vehicle,
## NPC, and placed object currently in the world. Paired with the layout-marker
## gizmos above (`_spawn_gizmos`), this is the diagnostic for "WorldSetup says X
## but runtime ended up at Y" — the operator can read the rotation/anchor delta
## off the screen instead of doing the math.
##
## Only walked once on activate(); gizmos are static thereafter (they don't track
## the vehicle if it drives away — that's a feature, the snapshot stays stable).
func _spawn_runtime_centroids() -> void:
	# Vehicles — the "parking wrong location" diagnostic. Group "vehicle" (sing.)
	# is added by BaseVehicle._ready.
	var veh_count : int = 0
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v is Node3D and is_instance_valid(v):
			_spawn_centroid(v as Node3D, COLOR_RUNTIME_VEHICLE)
			veh_count += 1
	# NPCs — class_name NPC, no group, walk from MainWorld root if present.
	# Falls back to scene-tree root walk if _world is null.
	var npc_count : int = 0
	var search_root : Node = _world if _world != null else get_tree().root
	npc_count = _scan_for_npcs(search_root)
	# Placeables — every placed object lives in the "placed_object" group
	# (PlaceableCatalog adds it to the body of every placeable). One small dot
	# per object; can be 100+ so we keep them tiny + no label by default.
	var obj_count : int = 0
	for o in get_tree().get_nodes_in_group("placed_object"):
		if o is Node3D and is_instance_valid(o):
			_spawn_centroid(o as Node3D, COLOR_RUNTIME_OBJECT, false)
			obj_count += 1
	_runtime_counts["vehicle"] = veh_count
	_runtime_counts["npc"] = npc_count
	_runtime_counts["object"] = obj_count

## Walk `root` recursively, drop a centroid for every NPC found. Returns count.
## Done by class-check because NPC.gd doesn't self-register into any group.
func _scan_for_npcs(root: Node) -> int:
	var n : int = 0
	if root == null:
		return 0
	if root is NPC:
		if root is Node3D:
			_spawn_centroid(root as Node3D, COLOR_RUNTIME_NPC)
		n += 1
		# Don't recurse into NPC subtree — its rig nodes aren't separate centroids.
		return n
	for ch in root.get_children():
		n += _scan_for_npcs(ch)
	return n

## Centroid = small sphere at the node's current global_position. When `with_label`
## is true, also drops a Label3D with the node's name; off by default for
## placed_object centroids since the count can be 100+.
func _spawn_centroid(target: Node3D, col: Color, with_label: bool = true) -> void:
	var holder := Node3D.new()
	holder.position = target.global_position
	# Pull the label off the node's name (strip Godot's @-prefix for unnamed nodes)
	var nm : String = target.name
	holder.name = "centroid_" + nm
	_gizmo_root.add_child(holder)
	# Tiny sphere — half the radius of layout markers so they read as "secondary".
	_build_sphere(holder, CENTROID_RADIUS_M, col, 1.0)
	if with_label:
		var lbl := Label3D.new()
		lbl.text = nm
		lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lbl.no_depth_test = true
		lbl.fixed_size = true
		lbl.pixel_size = CENTROID_LABEL_PX
		lbl.modulate = col
		lbl.outline_modulate = Color(0.0, 0.0, 0.0)
		lbl.outline_size = 6
		lbl.position = Vector3(0.0, CENTROID_RADIUS_M + 0.4, 0.0)
		holder.add_child(lbl)

func _build_yard_corners(corners: Array, col: Color, alpha: float) -> void:
	for v in corners:
		if not (v is Vector3): continue
		var holder := Node3D.new()
		holder.position = v
		_gizmo_root.add_child(holder)
		_build_sphere(holder, SPHERE_RADIUS_M * 0.5, col, alpha)

## Two-triangle (or fan-triangulated for 5+ corners) translucent polygon.
## Built from an ImmediateMesh so we don't need a per-yard concave mesh asset.
func _build_yard_polygon(corners: Array, col: Color, alpha: float) -> void:
	if corners.size() < 3:
		return
	var im := ImmediateMesh.new()
	var mat := _make_mat(col, alpha)
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, mat)
	var n := corners.size()
	# Lift the polygon ~3 cm above each corner's Y so it sits above the
	# satellite overlay quad without z-fighting and is clearly readable from
	# the operator's eye-level walk position.
	# Fan triangulation: (corners[0], corners[i], corners[i+1])
	for i in range(1, n - 1):
		var a : Vector3 = corners[0] + Vector3(0.0, 0.03, 0.0)
		var b : Vector3 = corners[i] + Vector3(0.0, 0.03, 0.0)
		var c : Vector3 = corners[i + 1] + Vector3(0.0, 0.03, 0.0)
		# Wind twice (CW + CCW) so the fill is visible from above AND from below;
		# avoids needing per-side material setup for the overhead diagnostic view.
		im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_add_vertex(c)
		im.surface_add_vertex(a); im.surface_add_vertex(c); im.surface_add_vertex(b)
	im.surface_end()
	var mi := MeshInstance3D.new()
	mi.mesh = im
	_gizmo_root.add_child(mi)

func _build_yard_label(centroid: Vector3, text: String, col: Color) -> void:
	var holder := Node3D.new()
	holder.position = centroid
	_gizmo_root.add_child(holder)
	_build_label(holder, text, col)

func _centroid(corners: Array) -> Vector3:
	if corners.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	var n := 0
	for v in corners:
		if v is Vector3:
			sum += v
			n += 1
	if n == 0:
		return Vector3.ZERO
	return sum / float(n)

## Standard "unshaded + cull-disabled + transparent if alpha<1" material so a
## gizmo reads true to its colour from any angle / under any lighting.
func _make_mat(col: Color, alpha: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.albedo_color = Color(col.r, col.g, col.b, alpha)
	if alpha < 0.999:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# No-depth-test would let gizmos shine through the building shell — handy
	# but the spec says depth-test ON for geometry (Label3D handles its own
	# always-readable flag). Leave depth_test default.
	return m

## Contrasting tint used for the "RAW" (pre-transform) gizmos. We desaturate
## toward a neutral-white so the BEFORE marker is visually distinct from the
## AFTER one at a glance, while still keeping a hint of the original colour.
func _raw_tint(_col: Color) -> Color:
	return COLOR_RAW_TINT

# ── Ground overlays (satellite + floor-plan) ─────────────────────────────────
## Recipe matches WorldSetup._apply_satellite_image() exactly: ImageTexture
## from user://satellite.png, unshaded, cull_disabled, alpha=0.55, PlaneMesh
## sized to satellite_extent_m, centred on factory_center (XZ; Y forced to
## SAT_OVERLAY_Y so it sits just above the operating floor).
func _spawn_overlays() -> void:
	_spawn_satellite_overlay()
	_spawn_floor_plan_overlay()

func _spawn_satellite_overlay() -> void:
	const SAT_PATH := "user://satellite.png"
	if not FileAccess.file_exists(SAT_PATH):
		return
	var img := Image.new()
	if img.load(SAT_PATH) != OK:
		push_warning("[InspectMode] failed to load %s" % SAT_PATH)
		return
	var tex := ImageTexture.create_from_image(img)
	var ext : float = WorldLayout.satellite_extent_m if WorldLayout.satellite_extent_m > 0.0 else 400.0
	var mi := MeshInstance3D.new()
	mi.name = "SatelliteOverlay"
	var pm := PlaneMesh.new()
	pm.size = Vector2(ext, ext)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, SAT_OVERLAY_ALPHA)
	mat.albedo_texture = tex
	mi.material_override = mat
	# Centre on factory_center (XZ), Y forced just above floor.
	# factory_center is in LAYOUT space (post-WorldLayout._load re-centring);
	# the satellite TILE in the live world is anchored on factory_center as well,
	# so we mirror that here. Operator wants to see WHERE THEY DREW IT — no
	# rotation-by-floor-plan-rot-deg.
	var fc : Vector3 = WorldLayout.factory_center
	mi.position = Vector3(fc.x, SAT_OVERLAY_Y, fc.z)
	add_child(mi)

## Mirror the satellite recipe, with calibration applied from WorldLayout's
## floor-plan block. floor_plan_rot_deg IS honoured here because that slider is
## per-plan calibration (different from world rotation derivation); the operator
## tuned it to align the PNG to the satellite.
func _spawn_floor_plan_overlay() -> void:
	if not WorldLayout.floor_plan_enabled:
		return
	const FP_PATH := "res://assets/models/floor_plan.png"
	if not ResourceLoader.exists(FP_PATH):
		return
	var tex : Texture2D = load(FP_PATH) as Texture2D
	if tex == null:
		return
	# Plan PNG aspect is 2400/1293 (WorldSetup constant). The user-tuned
	# `floor_plan_scale_m` is the Z extent the plan covers in world metres;
	# X extent follows the aspect ratio.
	var z_extent : float = WorldLayout.floor_plan_scale_m
	var x_extent : float = z_extent * (2400.0 / 1293.0)
	var mi := MeshInstance3D.new()
	mi.name = "FloorPlanOverlay"
	var pm := PlaneMesh.new()
	pm.size = Vector2(x_extent, z_extent)
	mi.mesh = pm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 1.0, 1.0, clampf(WorldLayout.floor_plan_opacity, 0.05, 1.0) * FP_OVERLAY_ALPHA / 0.55)
	mat.albedo_texture = tex
	mi.material_override = mat
	# Floor plan is positioned relative to factory_center via its offset_x/_z slots.
	var fc : Vector3 = WorldLayout.factory_center
	mi.position = Vector3(fc.x + WorldLayout.floor_plan_offset_x, FP_OVERLAY_Y, fc.z + WorldLayout.floor_plan_offset_z)
	mi.rotation = Vector3(0.0, deg_to_rad(WorldLayout.floor_plan_rot_deg), 0.0)
	add_child(mi)

# ── Readout overlay ──────────────────────────────────────────────────────────
func _spawn_readout() -> void:
	_canvas = CanvasLayer.new()
	_canvas.name = "InspectCanvas"
	_canvas.layer = 5     # above HUD (HUD's layer is typically lower)
	add_child(_canvas)
	_readout = Label.new()
	_readout.add_theme_font_size_override("font_size", 14)
	_readout.add_theme_color_override("font_color", Color(1.0, 1.0, 0.5))
	_readout.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_readout.add_theme_constant_override("outline_size", 6)
	_readout.position = Vector2(10, 10)
	_canvas.add_child(_readout)

# ── Fly-cam spawn ────────────────────────────────────────────────────────────
func _spawn_fly_cam() -> void:
	_fly_cam = Camera3D.new()
	_fly_cam.name = "InspectFlyCam"
	_fly_cam.set_script(FLY_CAM_SCRIPT)
	add_child(_fly_cam)
	# Seed pose from the player capsule + 5 m up + look-down 15°
	var start_pos := Vector3(0.0, 5.0, 10.0)
	var start_yaw := 0.0
	var start_pitch := -0.26   # ~-15°
	if _player != null and is_instance_valid(_player):
		start_pos = _player.global_position + Vector3.UP * 5.0
		# Match the player's current yaw so the operator's facing is preserved.
		start_yaw = _player.rotation.y
	if _fly_cam.has_method("init_pose"):
		_fly_cam.call("init_pose", start_pos, start_yaw, start_pitch)
	_fly_cam.current = true

# ── Player freeze + camera handover ──────────────────────────────────────────
## When activated, suspend the PlayerController's _physics_process so WASD,
## gravity, jump and crosshair interaction all stop while the fly cam runs.
## CameraRig is deactivated so it doesn't fight the fly cam for the viewport.
## When deactivated, both are restored.
func _freeze_player(freeze: bool) -> void:
	if _player == null or not is_instance_valid(_player):
		return
	if freeze:
		_player.set_physics_process(false)
		_player.set_process_input(false)
		# Stop residual velocity so the capsule doesn't slide while the operator
		# flies around.
		_player.velocity = Vector3.ZERO
		# Hand the FP camera (or any vehicle camera) off so .current stays clean.
		var rig : Node = _player.get("_camera_rig") if "_camera_rig" in _player else null
		if rig and rig.has_method("deactivate"):
			rig.call("deactivate")
	else:
		_player.set_physics_process(true)
		_player.set_process_input(true)
		var rig2 : Node = _player.get("_camera_rig") if "_camera_rig" in _player else null
		if rig2 and rig2.has_method("activate"):
			rig2.call("activate")

# ── Helpers ──────────────────────────────────────────────────────────────────
## Forward to MainWorld._layout_to_scene if available, else identity. Some
## scenes (sandbox / tests) don't expose the forwarder — we degrade gracefully
## by treating raw coords as scene coords so the gizmos still appear somewhere.
func _layout_to_scene(saved: Vector3) -> Vector3:
	if _world != null and _world.has_method("_layout_to_scene"):
		var v : Variant = _world.call("_layout_to_scene", saved)
		if v is Vector3:
			return v
	return saved

## Walk the camera-forward ray to the y=0 plane. Returns (NaN, NaN) when the
## ray is parallel to the floor or pointing skyward.
func _ray_to_floor(origin: Vector3, dir: Vector3) -> Vector2:
	if dir.y >= -0.001:
		return Vector2(NAN, NAN)
	var t : float = -origin.y / dir.y
	if t < 0.0:
		return Vector2(NAN, NAN)
	var hit := origin + dir * t
	return Vector2(hit.x, hit.z)

## Find whichever camera is currently `current` in the active viewport (the
## player's Head/Camera3D OR a CameraRig orbit camera OR a vehicle cab camera).
## Returned reference lets deactivate() flip .current back on the same node.
func _find_current_camera() -> Camera3D:
	var vp := get_viewport()
	if vp == null:
		return null
	return vp.get_camera_3d()
