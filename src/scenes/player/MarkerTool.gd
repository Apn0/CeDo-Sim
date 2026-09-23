extends Node3D
class_name MarkerTool

## In-world precise point marker tool (#markers).
##
## A multi-point successor to the old single-shot F10 feedback capture: instead
## of "here is a screenshot, guess which spot I meant", the operator drops as
## many exact orbs as they like and the developer reads their world coordinates.
##
## The PlayerController toggles this on F10 and routes input to it while active:
##   * a CYAN preview orb tracks the crosshair raycast hit every frame
##   * LMB  → stick an AMBER persistent orb at the current preview point
##   * G    → cycle snap  (OFF → GRID → EDGE-vertex)
##   * H    → delete every placed orb
##   * RMB / F10 → exit and write user://feedback/<stamp>/markers.json (+ shot)
##
## Placed orbs survive exiting the mode (so they can be referenced while walking
## around); only H clears them. Orbs are plain MeshInstance3D with NO colliders,
## so the placement ray never sees them. Everything renders unshaded + depth-test
## off so a 4 cm orb stays visible even when it lands inside a machine.
##
## Design note: the geometry-free logic (grid snap, nearest-vertex edge snap,
## JSON build, place_at) is decoupled from the live raycast so it is unit-testable
## headless — see src/tests/test_marker_tool.gd.

enum Snap { OFF, GRID, EDGE }

const PREVIEW_COLOR : Color = Color(0.20, 0.90, 1.00)   # cyan — live crosshair orb
const PLACED_COLOR  : Color = Color(1.00, 0.80, 0.10)   # amber — stuck markers
const SNAP_COLOR    : Color = Color(0.35, 1.00, 0.45)   # green — preview while a snap is active
const ORB_RADIUS    : float = 0.04                      # 4 cm — small but findable
const PLACED_RADIUS : float = 0.05
const RAY_RANGE     : float = 250.0                     # match the feedback tagging ray
const GRID_SIZE     : float = 0.10                      # 10 cm world grid
const EDGE_SNAP_MAX : float = 0.35                      # only snap to a vertex within 35 cm
const MAX_EDGE_VERTS: int   = 240000                    # skip edge snap on pathological meshes

var active   : bool = false
var snap     : int  = Snap.OFF
var markers  : Array = []            # each: Dictionary record (see _record)

var _camera      : Camera3D = null
var _exclude     : Array = []        # RIDs to skip in the placement ray (player body)
var _preview     : MeshInstance3D = null
var _preview_lbl : Label3D = null
var _placed_root : Node3D = null
var _last_point  : Vector3 = Vector3.ZERO
var _last_ctx    : Dictionary = {}
var _has_point   : bool = false
var _vert_cache  : Dictionary = {}   # collider instance id -> PackedVector3Array (world space)
var _shift_clock : ShiftClock = null # lazy-found; ShiftClock is not an autoload

# ── lifecycle ────────────────────────────────────────────────────────────────

func _ready() -> void:
	_placed_root = Node3D.new()
	_placed_root.name = "PlacedMarkers"
	add_child(_placed_root)
	set_process(false)

## Enter marker mode. `camera` is the eye the crosshair ray is cast from;
## `exclude_rids` skips the player body so we never tag the operator's own capsule.
func begin(camera: Camera3D, exclude_rids: Array) -> void:
	_camera = camera
	_exclude = exclude_rids
	active = true
	_has_point = false
	_ensure_preview()
	_preview.visible = true
	if _preview_lbl:
		_preview_lbl.visible = true
	set_process(true)
	_banner("[F10] MARKER MODE — LMB place · G snap · H clear · RMB exit")

## Leave marker mode and persist. Placed orbs stay in the world (only H clears
## them). Returns the globalised capture directory, or "" if nothing was written.
func exit_and_save() -> String:
	active = false
	set_process(false)
	if _preview:
		_preview.visible = false
	if _preview_lbl:
		_preview_lbl.visible = false
	var out_dir := _write_capture()
	_banner("[F10] exited — %d marker(s) saved → %s" % [markers.size(), out_dir])
	return out_dir

# ── per-frame preview ────────────────────────────────────────────────────────

func _process(_delta: float) -> void:
	if not active or _camera == null or not is_instance_valid(_camera):
		return
	var res := _resolve_point()
	_has_point = res.get("hit", false)
	if not _has_point:
		if _preview:
			_preview.visible = false
		return
	_last_point = res["point"]
	_last_ctx = res["ctx"]
	_preview.visible = true
	_preview.global_position = _last_point
	_tint(_preview, SNAP_COLOR if res.get("snapped", false) else PREVIEW_COLOR)
	if _preview_lbl:
		_preview_lbl.text = "%s\n%s" % [_snap_name().to_upper(), _fmt(_last_point)]

## Raycast from the camera through the crosshair, then apply the active snap.
## Returns {hit, point, snapped, ctx}. `ctx` carries the enrichment (hit object,
## placeable_id, PC coords) recorded alongside a placed marker.
func _resolve_point() -> Dictionary:
	var from := _camera.global_position
	var to := from - _camera.global_transform.basis.z * RAY_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = _exclude
	var space := get_world_3d().direct_space_state
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return {"hit": false}
	var raw : Vector3 = hit["position"]
	var snapped_flag := false
	var point := raw
	if snap == Snap.GRID:
		point = snap_to_grid(raw, GRID_SIZE)
		snapped_flag = true
	elif snap == Snap.EDGE:
		var e := _edge_snap(hit, raw)
		point = e["point"]
		snapped_flag = e["snapped"]
	return {"hit": true, "point": point, "snapped": snapped_flag, "ctx": _context_for(hit, raw)}

# ── actions ──────────────────────────────────────────────────────────────────

## Stick a persistent orb at the current preview point.
func place() -> void:
	if not _has_point:
		_banner("[F10] no surface under crosshair")
		return
	place_at(_last_point, _last_ctx)

## Decoupled placement — creates an orb + record at `point`. Exposed for tests.
func place_at(point: Vector3, ctx: Dictionary) -> void:
	var idx := markers.size() + 1
	var orb := _make_orb(PLACED_RADIUS, PLACED_COLOR)
	orb.global_position = point
	_placed_root.add_child(orb)
	var lbl := _make_label("#%d" % idx)
	lbl.position = Vector3(0.0, PLACED_RADIUS + 0.06, 0.0)
	orb.add_child(lbl)
	markers.append(_record(idx, point, ctx, orb))
	_banner("[F10] marker #%d @ %s (%s)" % [idx, _fmt(point), _snap_name()])

## Delete every placed orb.
func clear() -> void:
	for m in markers:
		var n = m.get("node")
		if n != null and is_instance_valid(n):
			n.queue_free()
	var n_cleared := markers.size()
	markers.clear()
	_banner("[F10] cleared %d marker(s)" % n_cleared)

## Cycle OFF → GRID → EDGE → OFF.
func cycle_snap() -> void:
	snap = (snap + 1) % 3
	_banner("[F10] snap: %s" % _snap_name().to_upper())

# ── snap math (pure, unit-testable) ──────────────────────────────────────────

## Round each component to the nearest `step`. step <= 0 is a no-op.
static func snap_to_grid(p: Vector3, step: float) -> Vector3:
	if step <= 0.0:
		return p
	return Vector3(snappedf(p.x, step), snappedf(p.y, step), snappedf(p.z, step))

## Nearest vertex in `verts` to `p`, but only if within `max_dist`.
## Returns {found: bool, point: Vector3}.
static func nearest_vertex(p: Vector3, verts: PackedVector3Array, max_dist: float) -> Dictionary:
	var best := Vector3.ZERO
	var best_d := max_dist * max_dist
	var found := false
	for v in verts:
		var d := p.distance_squared_to(v)
		if d <= best_d:
			best_d = d
			best = v
			found = true
	return {"found": found, "point": best}

## Snap the raw hit to the nearest visible-mesh vertex of the hit object.
func _edge_snap(hit: Dictionary, raw: Vector3) -> Dictionary:
	var collider = hit.get("collider")
	if collider == null:
		return {"point": raw, "snapped": false}
	var verts := _object_world_vertices(collider)
	if verts.is_empty():
		return {"point": raw, "snapped": false}
	var nv := nearest_vertex(raw, verts, EDGE_SNAP_MAX)
	if nv["found"]:
		return {"point": nv["point"], "snapped": true}
	return {"point": raw, "snapped": false}

## Collect (and cache) the world-space vertices of every MeshInstance3D under the
## hit object's placed_object ancestor (or the collider itself). Cached per
## collider id — meshes are static, so we only pay the walk once per object.
func _object_world_vertices(collider: Object) -> PackedVector3Array:
	if not (collider is Node):
		return PackedVector3Array()
	var id := (collider as Object).get_instance_id()
	if _vert_cache.has(id):
		return _vert_cache[id]
	var root : Node = collider as Node
	var n : Node = root
	while n != null:
		if n.is_in_group("placed_object"):
			root = n
			break
		n = n.get_parent()
	var out := PackedVector3Array()
	for mi_node in _find_mesh_instances(root):
		var mi := mi_node as MeshInstance3D
		if mi == null or mi.mesh == null:
			continue
		var faces : PackedVector3Array = mi.mesh.get_faces()
		if faces.is_empty():
			continue
		var xf : Transform3D = mi.global_transform
		for v in faces:
			out.append(xf * v)
			if out.size() > MAX_EDGE_VERTS:
				_vert_cache[id] = PackedVector3Array()   # too heavy — disable for this object
				return _vert_cache[id]
	_vert_cache[id] = out
	return out

func _find_mesh_instances(root: Node) -> Array:
	var found : Array = []
	if root is MeshInstance3D:
		found.append(root)
	for c in root.get_children():
		found.append_array(_find_mesh_instances(c))
	return found

# ── context / persistence ────────────────────────────────────────────────────

## Build the enrichment recorded with a marker: what the ray hit, the nearest
## placed_object's placeable_id, and PC (plant) coordinates when available.
func _context_for(hit: Dictionary, raw: Vector3) -> Dictionary:
	var ctx : Dictionary = {}
	var collider = hit.get("collider")
	ctx["hit_name"] = String(collider.name) if collider != null else ""
	ctx["hit_path"] = String(collider.get_path()) if collider is Node else ""
	# Climb to the nearest placed_object for a stable placeable_id.
	if collider is Node:
		var n : Node = collider as Node
		while n != null:
			if n.is_in_group("placed_object"):
				if n.has_meta("placeable_id"):
					ctx["placeable_id"] = String(n.get_meta("placeable_id"))
				ctx["placed_name"] = String(n.name)
				break
			n = n.get_parent()
	# PC coords — same frame as the layout markers, so a tagged point needs no
	# scene->plant conversion downstream.
	var plant := get_node_or_null("/root/Plant")
	if plant != null and plant.has_method("is_initialized") and plant.is_initialized():
		var pcv : Vector2 = plant.scene_to_pc(raw)
		ctx["world_point_pc"] = [pcv.x, pcv.y]
	return ctx

func _record(idx: int, point: Vector3, ctx: Dictionary, node: Node) -> Dictionary:
	var rec := {
		"index":       idx,
		"world_point": [point.x, point.y, point.z],
		"snap":        _snap_name(),
		"node":        node,
	}
	for k in ctx.keys():
		rec[k] = ctx[k]
	return rec

## The JSON payload written on exit (node handles stripped — not serialisable).
func _build_markers_json() -> Dictionary:
	var list : Array = []
	for m in markers:
		var clean := {}
		for k in m.keys():
			if k == "node":
				continue
			clean[k] = m[k]
		list.append(clean)
	var payload := {
		"format":      "cedo-markers-v1",
		"captured_at": Time.get_datetime_string_from_system(true),
		"shift_time":  _shift_time_string(),   # "" if no ShiftClock (e.g. a bench scene)
		"count":       list.size(),
		"grid_size_m": GRID_SIZE,
		"markers":     list,
	}
	if _camera != null and is_instance_valid(_camera):
		var fwd : Vector3 = -_camera.global_transform.basis.z
		payload["camera"] = {
			"position": [_camera.global_position.x, _camera.global_position.y, _camera.global_position.z],
			"forward":  [fwd.x, fwd.y, fwd.z],
			"fov_deg":  _camera.fov,
		}
	return payload

## Write markers.json + a screenshot + a context.json superset that the existing
## "check feedback" reader recognises. Returns the globalised directory.
func _write_capture() -> String:
	var stamp := _timestamp()
	var dir_path := "user://feedback/%s" % stamp
	DirAccess.make_dir_recursive_absolute(dir_path)
	# Screenshot — the active viewport's last frame (may be null headless).
	var vp := get_viewport()
	if vp != null:
		var tex := vp.get_texture()
		if tex != null:
			var img : Image = tex.get_image()
			if img != null:
				img.save_png("%s/screenshot.png" % dir_path)
	var data := _build_markers_json()
	var jf := FileAccess.open("%s/markers.json" % dir_path, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(data, "  "))
		jf.close()
	# context.json — keep the legacy feedback pipeline working, now enriched.
	var ctx := {
		"format":      "cedo-feedback-v1",
		"captured_at": data["captured_at"],
		"shift_time":  data.get("shift_time", ""),
		"kind":        "markers",
		"marker_count": data["count"],
		"markers":     data["markers"],
	}
	if data.has("camera"):
		ctx["camera"] = data["camera"]
	var cf := FileAccess.open("%s/context.json" % dir_path, FileAccess.WRITE)
	if cf != null:
		cf.store_string(JSON.stringify(ctx, "  "))
		cf.close()
	return ProjectSettings.globalize_path(dir_path)

## In-shift clock time, e.g. "13:40" ("glitched at 13:40" instead of only a
## wall-clock ISO stamp). Same lazy /root lookup discipline as DayNightCycle /
## Walkie / HmiWebOverlay — ShiftClock is not an autoload, and may genuinely
## not exist (bench/probe scenes have no shift), so this must stay null-safe.
func _shift_time_string() -> String:
	if _shift_clock == null or not is_instance_valid(_shift_clock):
		var tree := get_tree()
		if tree != null and tree.root != null:
			_shift_clock = tree.root.find_child("ShiftClock", true, false)
	if _shift_clock != null and is_instance_valid(_shift_clock):
		return _shift_clock.get_time_string()
	return ""

# ── visuals ──────────────────────────────────────────────────────────────────

func _ensure_preview() -> void:
	if _preview != null and is_instance_valid(_preview):
		return
	_preview = _make_orb(ORB_RADIUS, PREVIEW_COLOR)
	_preview.name = "PreviewOrb"
	add_child(_preview)
	_preview_lbl = _make_label("")
	_preview_lbl.position = Vector3(0.0, ORB_RADIUS + 0.06, 0.0)
	_preview.add_child(_preview_lbl)

func _make_orb(radius: float, color: Color) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = radius
	sph.height = radius * 2.0
	sph.radial_segments = 16
	sph.rings = 8
	mi.mesh = sph
	mi.material_override = _orb_material(color)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi

func _orb_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true          # always visible, even inside geometry
	mat.render_priority = 8
	return mat

func _tint(orb: MeshInstance3D, color: Color) -> void:
	if orb == null:
		return
	var mat := orb.material_override as StandardMaterial3D
	if mat != null:
		mat.albedo_color = color
		mat.emission = color

func _make_label(text: String) -> Label3D:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0006
	lbl.font_size = 48
	lbl.outline_size = 12
	lbl.modulate = Color(1, 1, 1)
	lbl.render_priority = 9
	return lbl

# ── helpers ──────────────────────────────────────────────────────────────────

func _snap_name() -> String:
	match snap:
		Snap.GRID: return "grid"
		Snap.EDGE: return "edge"
		_:         return "off"

func _fmt(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]

func _timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		int(t["year"]), int(t["month"]), int(t["day"]),
		int(t["hour"]), int(t["minute"]), int(t["second"])]

func _banner(msg: String) -> void:
	print("[markers] %s" % msg)
	var bus := get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", msg, false)
