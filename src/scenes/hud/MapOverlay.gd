extends Control
class_name MapOverlay

## Top-down site map (toggled with M). Player-centred, live, and zoomable with the
## scroll wheel. Draws the factory floor's moving parts so the operator can see at a
## glance where everyone and everything is: machines (from LineFlow telemetry),
## vehicles, the crew, loose bales, and the player (with a heading arrow).
##
## North is -Z (up on screen), +X is east (right). The demo pipeline 300 m west sits
## off the default view — zoom out (scroll down) to bring it on-map; anything outside
## the current window is pinned to the rim as a direction marker so you can still find it.
##
## It is a pure custom-draw Control: open()/close() flip visibility and the per-frame
## redraw, handle_zoom() changes the shown radius. The HUD wires `main_world` and
## forwards the M / wheel / ESC input (see HUD._input).

var main_world : MainWorld = null

# View state — view_radius_m is the world half-span shown across the map's short edge.
var view_radius_m : float = 90.0
const MIN_RADIUS  : float = 25.0
const MAX_RADIUS  : float = 600.0
const ZOOM_STEP   : float = 0.82      # multiply/divide per wheel notch

# Marker colours
const C_PANEL   := Color(0.06, 0.07, 0.06, 0.93)
const C_BORDER  := Color(0.32, 0.52, 0.34, 0.9)
const C_RING    := Color(0.30, 0.42, 0.32, 0.5)
const C_BUILDING := Color(0.84, 0.82, 0.74, 0.9)   # cream — CeDo building outline
const C_MACHINE := Color(0.62, 0.66, 0.70, 1.0)
const C_BALE    := Color(0.78, 0.70, 0.45, 1.0)
const C_VEHICLE := Color(0.30, 0.78, 0.34, 1.0)
const C_LIFT    := Color(0.36, 0.62, 0.95, 1.0)
const C_PLAYER  := Color(1.0, 0.90, 0.30, 1.0)
const C_TEXT    := Color(0.86, 0.90, 0.84, 1.0)
const C_DIM     := Color(0.74, 0.78, 0.72, 1.0)

var _font : Font

# =============================================================================
func _ready() -> void:
	# set_anchors_AND_OFFSETS_preset() (not just set_anchors_preset) — the
	# anchors-only form leaves offsets at (0,0,0,0) which, under a CanvasLayer
	# parent (HUD), produced a 0×0 Control. With size 0×0 the map "opened" but
	# drew nothing visible — exactly the M-key bug the operator hit.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Top-level so we project into viewport space rather than inheriting any
	# transform from HUD; z_index high so nothing else in HUD covers us.
	top_level = true
	z_index   = 100
	mouse_filter = Control.MOUSE_FILTER_IGNORE   # input is routed via HUD._input
	visible = false
	_font = ThemeDB.fallback_font
	set_process(false)

func open() -> void:
	# Backstop: even with the preset fix above, force the size to match the
	# viewport every time we open — covers display-mode-changes (window resize,
	# fullscreen toggle) that may have happened since _ready.
	var vp := get_viewport()
	if vp:
		size = vp.get_visible_rect().size
	visible = true
	set_process(true)
	queue_redraw()
	print("[MapOverlay] open  size=%s  main_world=%s" % [str(size), str(main_world)])

func close() -> void:
	visible = false
	set_process(false)

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()

## +1 = zoom in (smaller radius), -1 = zoom out (larger radius).
func handle_zoom(dir: int) -> void:
	if dir > 0:
		view_radius_m = maxf(MIN_RADIUS, view_radius_m * ZOOM_STEP)
	else:
		view_radius_m = minf(MAX_RADIUS, view_radius_m / ZOOM_STEP)
	queue_redraw()

func _process(_delta: float) -> void:
	queue_redraw()   # live: vehicles, crew and the player keep moving

# =============================================================================
# DRAW
# =============================================================================
func _draw() -> void:
	if not visible:
		return
	# Full-screen dim
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.55))

	# Centred square map panel
	var m := minf(size.x, size.y) * 0.82
	var panel := Rect2((size - Vector2(m, m)) * 0.5, Vector2(m, m))
	draw_rect(panel, C_PANEL)
	draw_rect(panel, C_BORDER, false, 2.0)

	var center_px := panel.position + panel.size * 0.5
	var scale_px  := (m * 0.5) / view_radius_m            # pixels per metre
	var origin    := _player_xz()

	_draw_rings(center_px, scale_px, m)
	# CeDo building outline — drawn first so machines / vehicles / crew render
	# ON TOP of it. The shell mesh's AABB projected to ground gives a
	# rectangle that bounds the factory; good enough as a "where is the
	# building" reference at site-map scale.
	_draw_building_outline(center_px, scale_px, origin, panel)

	# Machines (steel squares; ids only when zoomed in enough to be legible)
	var label_machines := scale_px > 3.0
	for nd in _machines():
		var n = nd.get("node", null)
		if n == null or not is_instance_valid(n):
			continue
		var px := _to_px((n as Node3D).global_position, center_px, scale_px, origin)
		var cl := _clamp_to(px, panel)
		draw_rect(Rect2(cl - Vector2(2.5, 2.5), Vector2(5, 5)), C_MACHINE)
		if label_machines and cl == px:
			_text(cl + Vector2(5, 3), _short_id(String(nd.get("id", ""))), 10, C_DIM)

	# Loose bales (small tan squares)
	for b in _bales():
		var bn := b as Node3D
		if bn == null:
			continue
		var px := _to_px(bn.global_position, center_px, scale_px, origin)
		var cl := _clamp_to(px, panel)
		draw_rect(Rect2(cl - Vector2(2, 2), Vector2(4, 4)), C_BALE)

	# Crew (dots in each worker's tag colour)
	for npc in _npcs():
		var nn := npc as Node3D
		if nn == null:
			continue
		var px := _to_px(nn.global_position, center_px, scale_px, origin)
		var cl := _clamp_to(px, panel)
		draw_circle(cl, 3.0, _npc_color(nn))

	# Vehicles (heading triangles; labelled when on-map)
	for v in _vehicles():
		var vp := _to_px(v.global_position, center_px, scale_px, origin)
		var cl := _clamp_to(vp, panel)
		# Accept both "mast_lift" (canonical) and legacy "scissor_lift" so older
		# in-flight vehicles render with the lift colour after the rename.
		var vt := String(v.vehicle_type)
		var col := C_LIFT if (vt == "mast_lift" or vt == "scissor_lift") else C_VEHICLE
		_draw_heading_tri(cl, _forward2(v), 7.0, col)
		if cl == vp:
			_text(cl + Vector2(7, 3), _vehicle_short(String(v.vehicle_type)), 10, col)

	# Player (always dead-centre, heading arrow)
	if main_world and main_world.player:
		_draw_heading_tri(center_px, _forward2(main_world.player), 9.0, C_PLAYER)

	# Compass, scale bar, legend, title
	_text(Vector2(center_px.x - 5, panel.position.y + 16), "N", 14, C_DIM)
	_draw_scalebar(panel, scale_px)
	_draw_legend(panel)
	_text(Vector2(panel.position.x, panel.position.y - 10),
		"SITE MAP", 18, Color(0.78, 0.92, 0.78, 1.0))
	_text(Vector2(panel.end.x - 250, panel.position.y - 10),
		"[M] close   ·   scroll to zoom", 13, C_DIM)

# =============================================================================
# DRAW HELPERS
# =============================================================================
func _draw_rings(center_px: Vector2, scale_px: float, m: float) -> void:
	var step := 10.0
	if view_radius_m > 300.0:   step = 100.0
	elif view_radius_m > 150.0: step = 50.0
	elif view_radius_m > 60.0:  step = 25.0
	var r := step
	while r <= view_radius_m:
		var rp := r * scale_px
		if rp <= m * 0.5:
			draw_arc(center_px, rp, 0.0, TAU, 64, C_RING, 1.0, true)
		r += step

## Cached footprint polygon (mesh-local XZ) of the building shell. Computed
## once from the shell mesh's floor triangles unioned together — the shell
## is static so the polygon is too. Preserves L-shapes / concavities that
## the previous AABB-rectangle path lost.
var _footprint_local : PackedVector2Array = PackedVector2Array()
var _footprint_built : bool = false
var _footprint_mesh_rid : RID

## Draw the building shell's true XZ footprint (not its AABB) as a translucent
## cream outline + label. Uses MainWorld._shell() to find the MeshInstance3D;
## silently skips if the shell isn't loaded (sandbox world, headless test).
func _draw_building_outline(center_px: Vector2, scale_px: float, origin: Vector2, panel: Rect2) -> void:
	if main_world == null:
		return
	var shell : MeshInstance3D = main_world._shell() if main_world.has_method("_shell") else null
	if shell == null or not is_instance_valid(shell) or shell.mesh == null:
		return
	# Invalidate the cache if the shell mesh changed (level reload, swap).
	if _footprint_built and shell.mesh.get_rid() != _footprint_mesh_rid:
		_footprint_built = false
	if not _footprint_built:
		_footprint_local = _compute_footprint_polygon(shell.mesh)
		_footprint_mesh_rid = shell.mesh.get_rid()
		_footprint_built = true
	if _footprint_local.size() < 3:
		return
	# Project the polygon through the shell's world transform back to world XZ,
	# then to screen pixels via _to_px.
	var xfm := shell.global_transform
	var pts := PackedVector2Array()
	pts.resize(_footprint_local.size())
	for i in _footprint_local.size():
		var v : Vector2 = _footprint_local[i]
		var world : Vector3 = xfm * Vector3(v.x, 0.0, v.y)
		pts[i] = _to_px(world, center_px, scale_px, origin)
	# Fill is subtle so yard markers stay visible through it.
	var fill := C_BUILDING
	fill.a = 0.10
	draw_colored_polygon(pts, fill)
	for i in pts.size():
		var a : Vector2 = pts[i]
		var b : Vector2 = pts[(i + 1) % pts.size()]
		draw_line(a, b, C_BUILDING, 1.8, true)
	# Label near the polygon's top-left vertex if it's inside the panel.
	var top_left : Vector2 = pts[0]
	for p in pts:
		if p.y < top_left.y or (is_equal_approx(p.y, top_left.y) and p.x < top_left.x):
			top_left = p
	if panel.has_point(top_left):
		_text(top_left + Vector2(4, -4), "CEDO", 11, C_BUILDING)

## Walk the shell mesh's floor triangles, project to XZ, union them. The
## result is the building footprint in mesh-local coordinates — handles
## L-shapes / concavities the AABB lost. Runs once per shell mesh.
##
## Filtering: prefer triangles where all 3 vertices sit within FLOOR_EPS of
## the mesh's min_y (the explicit floor face). If the mesh has no floor
## triangles, fall back to ALL triangles whose XZ projection isn't
## degenerate — the union still gives the right outline because vertical
## walls project to zero-area lines that don't contribute.
const _FOOTPRINT_FLOOR_EPS_M : float = 0.05
const _FOOTPRINT_DEGENERATE_AREA : float = 0.0001
func _compute_footprint_polygon(mesh: Mesh) -> PackedVector2Array:
	if mesh.get_surface_count() == 0:
		return PackedVector2Array()
	var arrays := mesh.surface_get_arrays(0)
	var verts : PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	if verts.is_empty():
		return PackedVector2Array()
	var idx : PackedInt32Array = PackedInt32Array()
	if arrays.size() > Mesh.ARRAY_INDEX and arrays[Mesh.ARRAY_INDEX] != null:
		idx = arrays[Mesh.ARRAY_INDEX]
	var min_y : float = INF
	for v in verts:
		if v.y < min_y:
			min_y = v.y
	# Collect projected triangles in two buckets: floor (preferred) + all.
	var tris_floor : Array = []
	var tris_all : Array = []
	if idx.size() > 0:
		var n : int = idx.size()
		var i : int = 0
		while i < n:
			var v1 : Vector3 = verts[idx[i]]
			var v2 : Vector3 = verts[idx[i + 1]]
			var v3 : Vector3 = verts[idx[i + 2]]
			i += 3
			var p1 := Vector2(v1.x, v1.z)
			var p2 := Vector2(v2.x, v2.z)
			var p3 := Vector2(v3.x, v3.z)
			if absf((p2 - p1).cross(p3 - p1)) < _FOOTPRINT_DEGENERATE_AREA:
				continue
			var tri := PackedVector2Array([p1, p2, p3])
			tris_all.append(tri)
			if v1.y - min_y <= _FOOTPRINT_FLOOR_EPS_M \
					and v2.y - min_y <= _FOOTPRINT_FLOOR_EPS_M \
					and v3.y - min_y <= _FOOTPRINT_FLOOR_EPS_M:
				tris_floor.append(tri)
	else:
		var n : int = verts.size()
		var i : int = 0
		while i + 2 < n:
			var v1 : Vector3 = verts[i]
			var v2 : Vector3 = verts[i + 1]
			var v3 : Vector3 = verts[i + 2]
			i += 3
			var p1 := Vector2(v1.x, v1.z)
			var p2 := Vector2(v2.x, v2.z)
			var p3 := Vector2(v3.x, v3.z)
			if absf((p2 - p1).cross(p3 - p1)) < _FOOTPRINT_DEGENERATE_AREA:
				continue
			var tri := PackedVector2Array([p1, p2, p3])
			tris_all.append(tri)
			if v1.y - min_y <= _FOOTPRINT_FLOOR_EPS_M \
					and v2.y - min_y <= _FOOTPRINT_FLOOR_EPS_M \
					and v3.y - min_y <= _FOOTPRINT_FLOOR_EPS_M:
				tris_floor.append(tri)
	var tris : Array = tris_floor if tris_floor.size() > 0 else tris_all
	if tris.is_empty():
		return PackedVector2Array()
	# Union all triangle projections. After each merge keep the polygon with
	# the largest area — multi-component meshes (detached props, attached
	# fences) would otherwise grow into an Array of disjoint islands.
	var acc : PackedVector2Array = tris[0]
	for j in range(1, tris.size()):
		var merged : Array = Geometry2D.merge_polygons(acc, tris[j])
		if merged.is_empty():
			continue
		if merged.size() == 1:
			acc = merged[0]
			continue
		var best : PackedVector2Array = merged[0]
		var best_area : float = absf(_polygon_area(best))
		for k in range(1, merged.size()):
			var a_k : float = absf(_polygon_area(merged[k]))
			if a_k > best_area:
				best = merged[k]
				best_area = a_k
		acc = best
	return acc

static func _polygon_area(poly: PackedVector2Array) -> float:
	if poly.size() < 3:
		return 0.0
	var s : float = 0.0
	for i in poly.size():
		var p := poly[i]
		var q := poly[(i + 1) % poly.size()]
		s += p.x * q.y - q.x * p.y
	return s * 0.5

func _draw_heading_tri(c: Vector2, dir: Vector2, s: float, col: Color) -> void:
	var d := dir
	if d.length() < 0.01:
		d = Vector2(0, -1)
	d = d.normalized()
	var perp := Vector2(-d.y, d.x)
	var pts := PackedVector2Array([
		c + d * s,
		c - d * s * 0.6 + perp * s * 0.6,
		c - d * s * 0.6 - perp * s * 0.6,
	])
	draw_colored_polygon(pts, col)

func _draw_scalebar(panel: Rect2, scale_px: float) -> void:
	# Pick a round number of metres about a quarter of the view
	var target := view_radius_m * 0.5
	var nice := 10.0
	for cand in [5.0, 10.0, 25.0, 50.0, 100.0, 200.0, 500.0]:
		if cand <= target:
			nice = cand
	var bar_px := nice * scale_px
	var y := panel.end.y - 16.0
	var x0 := panel.position.x + 14.0
	draw_line(Vector2(x0, y), Vector2(x0 + bar_px, y), C_TEXT, 2.0)
	draw_line(Vector2(x0, y - 4), Vector2(x0, y + 4), C_TEXT, 2.0)
	draw_line(Vector2(x0 + bar_px, y - 4), Vector2(x0 + bar_px, y + 4), C_TEXT, 2.0)
	_text(Vector2(x0, y - 8), "%d m" % int(nice), 11, C_TEXT)

func _draw_legend(panel: Rect2) -> void:
	var rows := [
		[C_PLAYER,  "You"],
		[C_VEHICLE, "Vehicle"],
		[C_LIFT,    "Scissor lift"],
		[C_MACHINE, "Machine"],
		[C_BALE,    "Bale"],
		[C_BUILDING, "CeDo building"],
	]
	var x := panel.end.x - 132.0
	var y := panel.position.y + 14.0
	for row in rows:
		draw_rect(Rect2(Vector2(x, y - 7), Vector2(9, 9)), row[0] as Color)
		_text(Vector2(x + 15, y + 1), String(row[1]), 11, C_TEXT)
		y += 17.0
	# crew swatch (a circle, distinct from the squares above)
	draw_circle(Vector2(x + 4, y - 3), 4.0, Color.CORNFLOWER_BLUE)
	_text(Vector2(x + 15, y + 1), "Crew", 11, C_TEXT)

func _text(pos: Vector2, s: String, fsize: int, col: Color) -> void:
	if _font == null:
		return
	draw_string(_font, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize, col)

# =============================================================================
# PROJECTION + ENTITY GATHERING
# =============================================================================
## World XZ → screen pixels, player-centred. +X right, +Z down (so -Z = north = up).
func _to_px(world_pos: Vector3, center_px: Vector2, scale_px: float, origin: Vector2) -> Vector2:
	return center_px + Vector2(world_pos.x - origin.x, world_pos.z - origin.y) * scale_px

func _clamp_to(px: Vector2, panel: Rect2) -> Vector2:
	return Vector2(
		clampf(px.x, panel.position.x + 2.0, panel.end.x - 2.0),
		clampf(px.y, panel.position.y + 2.0, panel.end.y - 2.0))

func _player_xz() -> Vector2:
	if main_world and main_world.player:
		var p := main_world.player.global_position
		return Vector2(p.x, p.z)
	return Vector2.ZERO

## A node's forward direction projected to map space (x, z). Godot bodies face -Z.
func _forward2(n: Node3D) -> Vector2:
	var f := -n.global_transform.basis.z
	return Vector2(f.x, f.z)

func _machines() -> Array:
	if main_world and main_world.line_flow and "_nodes" in main_world.line_flow:
		return main_world.line_flow._nodes
	return []

func _bales() -> Array:
	if is_inside_tree():
		return get_tree().get_nodes_in_group("bale")
	return []

func _npcs() -> Array:
	if main_world:
		return main_world.npcs.values()
	return []

func _vehicles() -> Array:
	var out : Array = []
	if main_world == null:
		return out
	for c in main_world.get_children():
		if c is BaseVehicle:
			out.append(c)
	return out

# =============================================================================
# LABEL / COLOUR HELPERS
# =============================================================================
func _npc_color(n: Node) -> Color:
	# MainWorld stamps each NPC with its catalogue colour as meta; fall back to blue.
	if n.has_meta("map_color"):
		return n.get_meta("map_color")
	return Color.CORNFLOWER_BLUE

func _short_id(id: String) -> String:
	# Trim a trailing "_1"/"_2" instance suffix for a tidier label.
	var parts := id.split("_")
	if parts.size() > 1 and parts[parts.size() - 1].is_valid_int():
		parts.remove_at(parts.size() - 1)
		return "_".join(parts)
	return id

func _vehicle_short(vtype: String) -> String:
	match vtype:
		"forklift":     return "Forklift"
		"bale_clamp":   return "Clamp"
		"merlo":        return "Merlo"
		"mast_lift":    return "Lift"
		"scissor_lift": return "Lift"   # legacy alias
	return vtype
