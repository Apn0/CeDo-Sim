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
# FULLY OPAQUE. At alpha 0.93 the 3D scene bled through the map — the operator's
# screenshot shows an NPC and a red machine visible *through* the panel, which is
# what made it unreadable. A map is a map, not a window.
const C_PANEL   := Color(0.06, 0.07, 0.06, 1.0)
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
	# Cache the counter-rotation that makes the map genuinely north-up.
	if main_world != null and main_world.has_method("_world_yaw"):
		var yaw : float = float(main_world.call("_world_yaw"))
		_yaw_cos = cos(yaw)
		_yaw_sin = sin(yaw)
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
	draw_rect(Rect2(Vector2.ZERO, size), Color(0, 0, 0, 0.72))

	# Centred square map panel — geometry comes from view_params() so the draw
	# path and the headless frame test share ONE projection setup.
	var vparams := view_params()
	var panel : Rect2 = vparams["panel"]
	draw_rect(panel, C_PANEL)
	draw_rect(panel, C_BORDER, false, 2.0)

	var center_px : Vector2 = vparams["center_px"]
	var scale_px : float = vparams["scale_px"]
	var origin : Vector2 = vparams["origin"]

	_draw_rings(center_px, scale_px, panel.size.x)
	# CeDo building outline — drawn first so machines / vehicles / crew render
	# ON TOP of it. Placed via the MEASURED building frame (fitted to the
	# shell's collision geometry by InteriorLightingManager), projected through
	# the same _to_px as every entity layer; hidden when no fit exists.
	_draw_building_outline(center_px, scale_px, origin, panel)
	# Bale yards, under the markers for the same reason as the outline.
	_draw_yards(center_px, scale_px, origin)

	# Machines (steel squares; ids only when zoomed in enough to be legible)
	# Operator 2026-07-20 ("very poor, see?"): every machine and every parked car
	# drew its label unconditionally, so the staff car park came out as one
	# unreadable pile of overlapping text. Labels are now claimed against a
	# collision list and dropped when they'd overlap something already drawn.
	_label_rects.clear()
	var label_machines := scale_px > 3.0
	# Vehicle names are only legible once the map is zoomed in — at wide zoom the
	# car park is a cluster a few pixels across and no label can be readable.
	var label_vehicles := scale_px > 5.0
	for nd in _machines():
		var n = nd.get("node", null)
		if n == null or not is_instance_valid(n):
			continue
		var px := _to_px((n as Node3D).global_position, center_px, scale_px, origin)
		var cl := _clamp_to(px, panel)
		draw_rect(Rect2(cl - Vector2(2.5, 2.5), Vector2(5, 5)), C_MACHINE)
		if label_machines and cl == px:
			_text_nc(cl + Vector2(5, 3), _short_id(String(nd.get("id", ""))), 10, C_DIM)

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
		if label_vehicles and cl == vp:
			_text_nc(cl + Vector2(7, 3), _vehicle_short(String(v.vehicle_type)), 10, col)

	# Player (always dead-centre, heading arrow)
	if main_world and main_world.player:
		_draw_heading_tri(center_px, _forward2(main_world.player), 9.0, C_PLAYER)

	# Compass, scale bar, legend, title
	_text(Vector2(center_px.x - 5, panel.position.y + 16), "N", 14, C_DIM)
	_draw_scalebar(panel, scale_px)
	_draw_legend(panel)
	# Inside the panel, not above it: at panel.position.y - 10 the title landed on
	# top of the HUD shift clock ("Shift starts in ... · SITE MAP" overlapped).
	_text(Vector2(panel.position.x + 8, panel.position.y + 20),
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

## Canonical building perimeter in the georeferenced BUILDING FRAME
## (tools/generate_building.py). This is the trusted SHAPE (150.7 x 71.5 m
## envelope — InteriorLightingManager sanity-checks the measured shell OBB
## against these spans, +-12 m). The FRAME that lands it in the scene is NOT
## baked here: hand-baked BF->PC affine constants placed 38/39 TL bars
## against open air (worst 5.67 m off) before 2701275; the surviving copy in
## this file displaced the outline the same way, drawing the player "outside"
## a building they were standing in. Placement now comes exclusively from the
## measured fit (_outline_scene_pts).
const _BF_OUTLINE : Array = [
	Vector2(0, 0), Vector2(150.7, 0), Vector2(150.7, 31.5), Vector2(131.5, 31.5),
	Vector2(131.5, 71.5), Vector2(81, 71.5), Vector2(81, 66), Vector2(57, 66),
	Vector2(57, 61), Vector2(0, 61)]

## Outline vertices in scene XZ, mapped through the frame that
## InteriorLightingManager FITS to the shell's actual collision faces
## (rotating-calipers OBB + roof-height raycast disambiguation). Cached after
## the first successful fetch: the shell is static and the fit runs exactly
## once per boot, so the mapping cannot change while the world lives. Empty
## while the fit is pending or absent (bench worlds, fit failure) — the
## outline is then NOT drawn: absent beats wrong.
var _outline_scene : PackedVector2Array = PackedVector2Array()

func _outline_scene_pts() -> PackedVector2Array:
	if _outline_scene.size() >= 3:
		return _outline_scene
	if main_world == null:
		return PackedVector2Array()
	var ilm := main_world.get_node_or_null("InteriorLightingManager") as InteriorLightingManager
	if ilm == null:
		return PackedVector2Array()
	var fit : Dictionary = ilm.get_building_frame()
	if fit.is_empty():
		return PackedVector2Array()
	var o : Vector2 = fit["o"]
	var fx : Vector2 = fit["x"]
	var fz : Vector2 = fit["z"]
	var pts := PackedVector2Array()
	pts.resize(_BF_OUTLINE.size())
	for i in _BF_OUTLINE.size():
		var b : Vector2 = _BF_OUTLINE[i]
		pts[i] = o + fx * b.x + fz * b.y
	_outline_scene = pts
	return _outline_scene

## The building outline pushed through the SAME _to_px projection as every
## entity layer — the headless frame test (src/tests/test_map_frame.gd)
## asserts on this exact function, so what is tested is what is drawn.
## Empty when no measured frame is available.
func outline_px(center_px: Vector2, scale_px: float, origin: Vector2) -> PackedVector2Array:
	var scene_pts := _outline_scene_pts()
	var pts := PackedVector2Array()
	if scene_pts.size() < 3:
		return pts
	pts.resize(scene_pts.size())
	for i in scene_pts.size():
		var s2 : Vector2 = scene_pts[i]
		pts[i] = _to_px(Vector3(s2.x, 0.0, s2.y), center_px, scale_px, origin)
	return pts

func _draw_building_outline(center_px: Vector2, scale_px: float, origin: Vector2, panel: Rect2) -> void:
	var pts := outline_px(center_px, scale_px, origin)
	if pts.size() < 3:
		return
	# Fill is subtle so bale / machine / crew markers inside the building stay legible.
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

## Bale-yard perimeters. Source is BaleYardManager's record of where each yard
## was ACTUALLY spawned (scene XZ), pushed through the same _to_px as the
## outline and every marker — so a yard rectangle and the bale squares standing
## inside it cannot drift apart. Not cached here: yards can be reset/restocked,
## and the list is a handful of quads.
func _draw_yards(center_px: Vector2, scale_px: float, origin: Vector2) -> void:
	if main_world == null or main_world.bale_yard_manager == null:
		return
	var fill := C_BALE
	fill.a = 0.09
	var edge := C_BALE
	edge.a = 0.45
	for poly in main_world.bale_yard_manager.get_yard_polygons():
		if poly.size() < 3:
			continue
		var pts := PackedVector2Array()
		pts.resize(poly.size())
		for i in poly.size():
			var s2 : Vector2 = poly[i]
			pts[i] = _to_px(Vector3(s2.x, 0.0, s2.y), center_px, scale_px, origin)
		draw_colored_polygon(pts, fill)
		for i in pts.size():
			draw_line(pts[i], pts[(i + 1) % pts.size()], edge, 1.2, true)

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
		[Color(C_BALE.r, C_BALE.g, C_BALE.b, 0.45), "Bale yard"],
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

## Rects already occupied by a label this frame (see _draw).
var _label_rects : Array[Rect2] = []

## Draw a label ONLY if it doesn't collide with one already placed this frame.
## Returns false when the label was dropped. Cheap O(n^2) — n is a few dozen and
## only while the map is open.
func _text_nc(pos: Vector2, s: String, fsize: int, col: Color) -> bool:
	# _font can be null under a dummy display server (headless frame test), where
	# get_string_size would crash before the label is ever rasterised.
	if s == "" or _font == null:
		return false
	var w : float = _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
	var r := Rect2(pos - Vector2(2.0, float(fsize)), Vector2(w + 4.0, float(fsize) + 4.0))
	for q in _label_rects:
		if r.intersects(q):
			return false
	_label_rects.append(r)
	_text(pos, s, fsize, col)
	return true

# =============================================================================
# PROJECTION + ENTITY GATHERING
# =============================================================================
## World XZ → screen pixels, player-centred, NORTH-UP. The scene frame is
## rotated by the canonical world yaw (130.2 deg), so raw world axes put
## north down-left; we counter-rotate into the layout (north-up) frame so
## the "N" compass label is honest. Yaw is cached in open().
var _yaw_cos : float = 1.0
var _yaw_sin : float = 0.0

## Canonical view setup — panel rect, pixel centre, px-per-metre scale and the
## player-centred origin. ONE source of truth: _draw and the headless frame
## test both build their projection from this dict, so an assertion on
## _to_px(view_params()...) is an assertion on the rendered map.
func view_params() -> Dictionary:
	var m := minf(size.x, size.y) * 0.82
	var panel := Rect2((size - Vector2(m, m)) * 0.5, Vector2(m, m))
	return {
		"panel": panel,
		"center_px": panel.position + panel.size * 0.5,
		"scale_px": (m * 0.5) / view_radius_m,
		"origin": _player_xz(),
	}

func _to_px(world_pos: Vector3, center_px: Vector2, scale_px: float, origin: Vector2) -> Vector2:
	var dx := world_pos.x - origin.x
	var dz := world_pos.z - origin.y
	return center_px + Vector2(dx * _yaw_cos - dz * _yaw_sin,
		dx * _yaw_sin + dz * _yaw_cos) * scale_px

func _clamp_to(px: Vector2, panel: Rect2) -> Vector2:
	return Vector2(
		clampf(px.x, panel.position.x + 2.0, panel.end.x - 2.0),
		clampf(px.y, panel.position.y + 2.0, panel.end.y - 2.0))

func _player_xz() -> Vector2:
	if main_world and main_world.player:
		var p := main_world.player.global_position
		return Vector2(p.x, p.z)
	return Vector2.ZERO

## A node's forward direction projected to map space (x, z), counter-rotated
## into the north-up frame like _to_px. Godot bodies face -Z.
func _forward2(n: Node3D) -> Vector2:
	var f := -n.global_transform.basis.z
	return Vector2(f.x * _yaw_cos - f.z * _yaw_sin,
		f.x * _yaw_sin + f.z * _yaw_cos)

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
