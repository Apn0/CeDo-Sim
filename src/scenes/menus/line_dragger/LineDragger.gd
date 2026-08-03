extends Control
## 2D top-down drag interface for line machine layout.
##
## Shows each machine in LINE_3A_SEQ as a labeled rectangle on a scrollable
## canvas. Drag a rectangle to reposition that machine laterally (X) or along
## the line (Z). Saving writes chain-relative deltas to LineMacroStore so
## subsequent BuildMode placements use the corrected layout.
##
## Coordinate convention on the canvas:
##   canvas X → world lateral (rgt, machine "x" field)
##   canvas Y → world forward (fwd, machine "z" / place_z cursor)
##   1 metre  = PIXELS_PER_M pixels

## BuildMode and PlaceableCatalog are class_name classes — accessed directly.

const LINE_GAP_M       : float = 0.5
const PIXELS_PER_M     : float = 18.0
const CANVAS_PAD       : float = 80.0   # px margin around content
const SNAP_M           : float = 0.25   # drag snaps to 25 cm grid

# Line 3A sequence (mirrored from BuildMode.LINE_3A_SEQ for direct access)
const LINE_3A_SEQ : Array[Dictionary] = [
	{"id": "vss_silo"},
	{"id": "vuilsnippersilo"},
	{"id": "transport_screw"},
	{"id": "friction_washer"},
	{"id": "transfer_chute"},
	# 2026-07-06: slot IS Pomp C1 (see BuildMode.LINE_3A_SEQ — both mirrors
	# must change together; in-place id swap keeps every macro_index stable).
	{"id": "pomp_c1", "x": -3.5, "z": 0.0},
	{"id": "friction_sep"},
	{"id": "flotation_tank"},
	{"id": "dewater_screw"},
	{"id": "friction_sep"},
	{"id": "transport_screw"},
	{"id": "mech_dryer", "gap": 1.2},
	{"id": "blower"},
	{"id": "mengsilo"},
	{"id": "transport_screw", "x": 5.0, "z": -3.0, "branch_recirc": true},
	{"id": "blower",          "x": 5.0, "z":  0.0},
	{"id": "ringleiding",     "x": 5.0, "z":  3.0},
	{"id": "cyclone",         "x": 5.0, "z":  6.0},
	{"id": "transport_screw"},
	{"id": "verdeelwals"},
	{"id": "blower"},
	{"id": "wind_sifter"},
	{"id": "blower"},
	{"id": "cyclone"},
	{"id": "verdeelwals"},
	{"id": "thermal_dryer"},
	{"id": "cyclone"},
	{"id": "blower"},
	{"id": "cyclone"},
	{"id": "extruder_silo", "gap": 1.5},
	{"id": "extruder_3a"},
	{"id": "lump_cart_spot", "x": 2.8, "z": -5.0},
	{"id": "lump_cart",      "x": 2.8, "z": -5.0},
]

# Per-machine record kept in _machines array (one entry per SEQ index).
# All positions in METRES (world local frame, lateral=X, forward=Z).
# {
#   idx, id, label, nominal_x, nominal_z, width, depth,
#   color, current_x, current_z, is_branch
# }
var _machines : Array = []
var _line_id  : String = "line_3a"

# Drag state
var _drag_idx    : int     = -1
var _drag_off    : Vector2 = Vector2.ZERO   # mouse pos − rect top-left at drag start

# Canvas pan state
var _pan_offset  : Vector2 = Vector2.ZERO
var _panning     : bool    = false
var _pan_origin  : Vector2 = Vector2.ZERO
var _pan_start   : Vector2 = Vector2.ZERO

# Canvas bounds (metres) — derived from machine positions
var _content_min : Vector2 = Vector2.ZERO
var _content_max : Vector2 = Vector2.ZERO

@onready var _canvas       : Control = $CanvasArea
@onready var _info_label   : Label   = $Sidebar/VBox/InfoLabel
@onready var _save_btn     : Button  = $Sidebar/VBox/SaveButton
@onready var _reset_btn    : Button  = $Sidebar/VBox/ResetButton
@onready var _back_btn     : Button  = $Sidebar/VBox/BackButton
@onready var _line_label   : Label   = $Sidebar/VBox/LineLabel

func _ready() -> void:
	_build_nominal()
	_apply_saved_overrides()
	_center_view()
	_save_btn.pressed.connect(_on_save)
	_reset_btn.pressed.connect(_on_reset)
	_back_btn.pressed.connect(_on_back)
	_canvas.draw.connect(_on_canvas_draw)
	_canvas.gui_input.connect(_on_canvas_input)
	_line_label.text = "Line: %s  (%d machines)" % [_line_id.to_upper(), _machines.size()]

# ── Nominal layout ────────────────────────────────────────────────────────────

func _build_nominal() -> void:
	_machines.clear()
	var seq : Array[Dictionary] = LINE_3A_SEQ
	var main_z : float = 0.0
	var last_main_z : float = 0.0   # cursor just AFTER the last main machine (branch anchor)
	for i in range(seq.size()):
		var entry : Dictionary = seq[i]
		var mid : String = String(entry.get("id", ""))
		if mid.is_empty():
			continue
		var item : Dictionary = PlaceableCatalog.get_item(mid)
		var size3 : Vector3 = Vector3(2.0, 2.0, 2.0)
		var col   : Color   = Color(0.36, 0.50, 0.70)
		var lbl   : String  = mid
		if not item.is_empty():
			size3 = item.get("size", size3) as Vector3
			col   = item.get("color", col) as Color
			lbl   = item.get("name", mid) as String
		var depth : float = maxf(size3.z, 0.5)
		var width : float = maxf(size3.x, 0.5)
		var ex    : float = float(entry.get("x",   0.0))
		var ez    : float = float(entry.get("z",   0.0))
		var is_br : bool  = not is_equal_approx(ex, 0.0)
		var place_z : float
		if not is_br:
			var gap_after : float = float(entry.get("gap", LINE_GAP_M))
			main_z += depth * 0.5
			place_z = main_z
			main_z += depth * 0.5 + gap_after
			last_main_z = main_z   # cursor after this machine = branch anchor
		else:
			place_z = last_main_z + ez   # matches BuildMode: main_z + entry.z
		_machines.append({
			"idx":       i,
			"id":        mid,
			"label":     lbl,
			"nominal_x": ex,
			"nominal_z": place_z,
			"width":     width,
			"depth":     depth,
			"color":     col,
			"current_x": ex,
			"current_z": place_z,
			"is_branch": is_br,
		})
	_recalc_bounds()

func _apply_saved_overrides() -> void:
	var acc : Dictionary = LineMacroStore.accumulated_chain(_line_id, _machines.size())
	for m in _machines:
		var d : Dictionary = acc.get(m["idx"], {})
		m["current_x"] = m["nominal_x"] + float(d.get("dx", 0.0))
		m["current_z"] = m["nominal_z"] + float(d.get("dz", 0.0))
	_recalc_bounds()

func _recalc_bounds() -> void:
	if _machines.is_empty():
		return
	var min_x : float =  1e9
	var min_z : float =  1e9
	var max_x : float = -1e9
	var max_z : float = -1e9
	for m in _machines:
		var hw : float = m["width"] * 0.5
		var hd : float = m["depth"] * 0.5
		min_x = minf(min_x, m["current_x"] - hw)
		max_x = maxf(max_x, m["current_x"] + hw)
		min_z = minf(min_z, m["current_z"] - hd)
		max_z = maxf(max_z, m["current_z"] + hd)
	_content_min = Vector2(min_x, min_z)
	_content_max = Vector2(max_x, max_z)

# ── View helpers ──────────────────────────────────────────────────────────────

func _center_view() -> void:
	# Pan so the content is centered in the canvas.
	var content_size_px := (_content_max - _content_min) * PIXELS_PER_M
	var canvas_size     := _canvas.size if _canvas.size.length() > 10.0 else Vector2(800, 600)
	_pan_offset = (canvas_size - content_size_px) * 0.5 - _content_min * PIXELS_PER_M

func _world_to_canvas(world_x: float, world_z: float) -> Vector2:
	return Vector2(world_x, world_z) * PIXELS_PER_M + _pan_offset

func _canvas_to_world(canvas_pos: Vector2) -> Vector2:
	return (canvas_pos - _pan_offset) / PIXELS_PER_M

# ── Drawing ───────────────────────────────────────────────────────────────────

func _on_canvas_draw() -> void:
	# Background grid (1 m lines)
	var grid_col := Color(0.25, 0.27, 0.30)
	var canvas_sz : Vector2 = _canvas.size
	var world_tl : Vector2 = _canvas_to_world(Vector2.ZERO)
	var world_br : Vector2 = _canvas_to_world(canvas_sz)
	var gx : float = floor(world_tl.x)
	while gx <= ceil(world_br.x):
		var px : float = _world_to_canvas(gx, 0.0).x
		_canvas.draw_line(Vector2(px, 0.0), Vector2(px, canvas_sz.y), grid_col, 1.0)
		gx += 1.0
	var gz : float = floor(world_tl.y)
	while gz <= ceil(world_br.y):
		var py : float = _world_to_canvas(0.0, gz).y
		_canvas.draw_line(Vector2(0.0, py), Vector2(canvas_sz.x, py), grid_col, 1.0)
		gz += 1.0

	# Main centreline axis
	var axis_x := _world_to_canvas(0.0, 0.0).x
	_canvas.draw_line(Vector2(axis_x, 0.0), Vector2(axis_x, canvas_sz.y),
		Color(0.40, 0.42, 0.50, 0.6), 2.0)

	# Flow arrow along the line (downward on canvas = forward in world)
	var arrow_x := axis_x + 12.0
	for gz2 in range(int(world_tl.y), int(world_br.y) + 1, 4):
		var py2 := _world_to_canvas(0.0, float(gz2)).y
		_canvas.draw_line(Vector2(arrow_x, py2), Vector2(arrow_x, py2 + 40.0),
			Color(0.55, 0.55, 0.65, 0.35), 1.5)
		_canvas.draw_line(Vector2(arrow_x - 5.0, py2 + 32.0),
			Vector2(arrow_x, py2 + 40.0), Color(0.55, 0.55, 0.65, 0.35), 1.5)
		_canvas.draw_line(Vector2(arrow_x + 5.0, py2 + 32.0),
			Vector2(arrow_x, py2 + 40.0), Color(0.55, 0.55, 0.65, 0.35), 1.5)

	# Machines
	for i in range(_machines.size()):
		var m : Dictionary = _machines[i]
		var cx := _world_to_canvas(m["current_x"], m["current_z"])
		var wpx : float = m["width"] * PIXELS_PER_M
		var dpx : float = m["depth"] * PIXELS_PER_M
		var rect := Rect2(cx.x - wpx * 0.5, cx.y - dpx * 0.5, wpx, dpx)
		var base_col : Color = m["color"]
		var fill_col := base_col.lightened(0.05) if i != _drag_idx else base_col.lightened(0.25)
		_canvas.draw_rect(rect, fill_col)
		_canvas.draw_rect(rect, Color(1, 1, 1, 0.7), false, 1.5)

		# Show drift arrow when moved from nominal
		var dx : float = m["current_x"] - m["nominal_x"]
		var dz : float = m["current_z"] - m["nominal_z"]
		if abs(dx) > 0.05 or abs(dz) > 0.05:
			var nom_c := _world_to_canvas(m["nominal_x"], m["nominal_z"])
			_canvas.draw_line(nom_c, cx, Color(1.0, 0.85, 0.2, 0.7), 1.5)
			_canvas.draw_circle(nom_c, 3.0, Color(1.0, 0.85, 0.2, 0.5))

		# Label — truncated if box is too small
		var font := ThemeDB.fallback_font
		var font_sz := clampi(int(minf(wpx, dpx) * 0.22), 8, 14)
		var short_lbl : String = m["label"]
		if short_lbl.length() > 18:
			short_lbl = short_lbl.substr(0, 16) + "…"
		var tw := font.get_string_size(short_lbl, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x
		if tw < wpx - 4.0:
			_canvas.draw_string(font, cx + Vector2(-tw * 0.5, font_sz * 0.4), short_lbl,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz, Color(1, 1, 1, 0.92))

# ── Input ─────────────────────────────────────────────────────────────────────

func _on_canvas_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_start_drag(mb.position)
			else:
				_end_drag()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_panning    = true
				_pan_origin = mb.position
				_pan_start  = _pan_offset
			else:
				_panning = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			pass  # zoom later
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			pass
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _panning:
			_pan_offset = _pan_start + (mm.position - _pan_origin)
			_canvas.queue_redraw()
		elif _drag_idx >= 0:
			_do_drag(mm.position)

func _start_drag(pos: Vector2) -> void:
	# Find topmost machine under cursor (iterate reversed so later-drawn = on top)
	for i in range(_machines.size() - 1, -1, -1):
		var m : Dictionary = _machines[i]
		var cx := _world_to_canvas(m["current_x"], m["current_z"])
		var wpx : float = m["width"]  * PIXELS_PER_M
		var dpx : float = m["depth"] * PIXELS_PER_M
		var rect := Rect2(cx.x - wpx * 0.5, cx.y - dpx * 0.5, wpx, dpx)
		if rect.has_point(pos):
			_drag_idx = i
			_drag_off = pos - cx
			_update_info(i)
			_canvas.queue_redraw()
			return

func _do_drag(pos: Vector2) -> void:
	var world_centre := _canvas_to_world(pos - _drag_off)
	# Snap to grid
	world_centre.x = round(world_centre.x / SNAP_M) * SNAP_M
	world_centre.y = round(world_centre.y / SNAP_M) * SNAP_M
	var m : Dictionary = _machines[_drag_idx]
	m["current_x"] = world_centre.x
	m["current_z"] = world_centre.y
	_update_info(_drag_idx)
	_recalc_bounds()
	_canvas.queue_redraw()

func _end_drag() -> void:
	_drag_idx = -1
	_canvas.queue_redraw()

func _update_info(i: int) -> void:
	var m : Dictionary = _machines[i]
	var dx : float = float(m["current_x"]) - float(m["nominal_x"])
	var dz : float = float(m["current_z"]) - float(m["nominal_z"])
	_info_label.text = (
		"[%d] %s\n" % [i, m["label"]] +
		"pos  X=%.2f m  Z=%.2f m\n" % [m["current_x"], m["current_z"]] +
		"Δx=%.2f  Δz=%.2f" % [dx, dz]
	)

# ── Save / Reset ──────────────────────────────────────────────────────────────

func _on_save() -> void:
	# Convert absolute per-machine offsets → chain-relative deltas for LineMacroStore.
	# Chain rule: stored_delta[i] = abs_delta[i] - accumulated_delta_up_to[i-1]
	var out_deltas : Dictionary = {}
	var acc_dx : float = 0.0
	var acc_dz : float = 0.0
	for m in _machines:
		var i : int = int(m["idx"])
		var abs_dx : float = float(m["current_x"]) - float(m["nominal_x"])
		var abs_dz : float = float(m["current_z"]) - float(m["nominal_z"])
		var rel_dx : float = abs_dx - acc_dx
		var rel_dz : float = abs_dz - acc_dz
		if abs(rel_dx) > 0.001 or abs(rel_dz) > 0.001:
			out_deltas[i] = {
				"dx":     rel_dx,
				"dy":     0.0,
				"dz":     rel_dz,
				"drot_y": 0.0,
				"scale":  [1.0, 1.0, 1.0],
			}
		acc_dx = abs_dx
		acc_dz = abs_dz
	LineMacroStore.save_overrides(_line_id, out_deltas, _machines.size())
	_info_label.text = "Saved %d overrides." % out_deltas.size()

func _on_reset() -> void:
	LineMacroStore.reset(_line_id)
	for m in _machines:
		m["current_x"] = m["nominal_x"]
		m["current_z"] = m["nominal_z"]
	_recalc_bounds()
	_center_view()
	_canvas.queue_redraw()
	_info_label.text = "Reset to defaults."

func _on_back() -> void:
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

# ── Resize ────────────────────────────────────────────────────────────────────

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		# NOTIFICATION_RESIZED fires during initial layout BEFORE @onready has
		# assigned _canvas — bail out; _ready() runs _center_view() afterwards.
		if _canvas == null:
			return
		_center_view()
		_canvas.queue_redraw()
