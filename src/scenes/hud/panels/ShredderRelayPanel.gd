extends Control
class_name ShredderRelayPanel

## Relay-logic panel for Shredder 2 — NO touchscreen, NO tabs, NO machine list.
##
## This is the deliberate counterpoint to HmiOverlay.gd: a brushed-stainless
## cabinet face with exactly three physical controls:
##
##   1. KEY SWITCH      — 3-position cycle (I=Auto, II=Hand, III=Onderhoud).
##                        Click rotates to the next position. A row of three
##                        small lamps shows which detent is active (green).
##   2. GREEN START     — illuminated pushbutton "Automaat start".
##                        Lights up green while running; grey when idle;
##                        flashes when pressed with the key in the wrong
##                        position (operator feedback that Auto isn't armed).
##   3. RED MUSHROOM    — "Noodstop" e-stop. Always available, always wins.
##                        Latches the panel into e_stop_active until the host
##                        releases it (real cabinets need a quarter-turn reset
##                        — the host scene drives that, this panel just emits).
##
## The panel is a pure view+input widget; it does NOT poke any model or
## LineFlow directly. Signals out, state in via the public set_* methods.
## That way the same panel can be embedded in a 3D Hmi node, a debug overlay,
## or a unit test without dragging in the rest of the HUD scope/scopes layer.
##
## Visual style:
##   - Brushed stainless background (Color(0.72, 0.72, 0.75)) drawn as a full-
##     surface ColorRect.
##   - Buttons are drawn directly via _draw() on a custom Control so the chrome
##     rim, lens, and lamp glow are pixel-controlled (no theme dependency).
##   - All three controls are positioned absolutely on the panel face: the
##     operator's muscle memory matters more than responsive layout here.

signal request_close()
signal start_pressed()
signal stop_pressed()
signal key_position_changed(pos: int)

enum KeyPos { AUTO, HAND, ONDERHOUD }

@export var shredder_id: String = "shredder_2_l3ab"

# ------------------------------------------------------------------ palette
const C_PANEL      : Color = Color(0.72, 0.72, 0.75, 1.0)   # brushed stainless
const C_PANEL_EDGE : Color = Color(0.42, 0.43, 0.46, 1.0)
const C_HEADER_BG  : Color = Color(0.16, 0.18, 0.22, 1.0)
const C_HEADER_TX  : Color = Color(0.92, 0.93, 0.95, 1.0)
const C_LABEL_TX   : Color = Color(0.10, 0.11, 0.13, 1.0)
const C_CHROME     : Color = Color(0.86, 0.87, 0.90, 1.0)   # chrome rim
const C_CHROME_DK  : Color = Color(0.45, 0.46, 0.49, 1.0)
const C_LAMP_OFF   : Color = Color(0.36, 0.38, 0.36, 1.0)
const C_LAMP_GREEN : Color = Color(0.30, 0.85, 0.34, 1.0)
const C_LAMP_GREEN_DIM : Color = Color(0.18, 0.34, 0.20, 1.0)
const C_LAMP_RED   : Color = Color(0.92, 0.20, 0.16, 1.0)
const C_LAMP_RED_DK: Color = Color(0.55, 0.10, 0.08, 1.0)
const C_BUTTON_GREY: Color = Color(0.55, 0.57, 0.55, 1.0)
const C_MUSHROOM_RED: Color = Color(0.86, 0.16, 0.14, 1.0)
const C_MUSHROOM_DK : Color = Color(0.42, 0.06, 0.05, 1.0)
const C_KEYHEAD    : Color = Color(0.30, 0.27, 0.18, 1.0)   # brass key head
const C_KEYHEAD_HI : Color = Color(0.78, 0.66, 0.32, 1.0)

const PANEL_SIZE : Vector2 = Vector2(720, 460)
const FLASH_HZ   : float   = 2.5    # Hz — wrong-key feedback flash rate

# ------------------------------------------------------------------ state
var key_position    : int  = KeyPos.AUTO
var running         : bool = false
var e_stop_active   : bool = false

var _flash_t        : float = 0.0
var _flash_active   : bool  = false   # green start button flashes after a bad press

# control nodes (absolutely positioned)
var _bg             : ColorRect = null
var _header         : Panel     = null
var _key_widget     : Control   = null
var _start_widget   : Control   = null
var _stop_widget    : Control   = null
var _close_button   : Button    = null
var _lamps_widget   : Control   = null
var _title_lbl      : Label     = null
var _subtitle_lbl   : Label     = null
var _key_lbl        : Label     = null
var _start_lbl      : Label     = null
var _stop_lbl       : Label     = null

# ============================================================================
func _ready() -> void:
	custom_minimum_size = PANEL_SIZE
	set_deferred("size", PANEL_SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process(true)
	_build()
	_refresh()

func _process(delta: float) -> void:
	if not _flash_active:
		return
	_flash_t += delta * FLASH_HZ
	if _start_widget != null:
		_start_widget.queue_redraw()

# ----------------------------------------------------------------- public API
## Tell the panel whether the shredder is actually running (drives the green
## lamp inside the START pushbutton). The host (Hmi node, ShredderModel,
## whoever) is the source of truth — this panel just renders.
func set_running(v: bool) -> void:
	if running == v:
		return
	running = v
	if _start_widget != null:
		_start_widget.queue_redraw()

## Latch / release the E-stop. While latched the mushroom button is drawn
## depressed and start_pressed() will never fire even if the operator clicks
## the green button.
func set_e_stop(v: bool) -> void:
	if e_stop_active == v:
		return
	e_stop_active = v
	if v:
		running = false
		_flash_active = false
	if _stop_widget != null:
		_stop_widget.queue_redraw()
	if _start_widget != null:
		_start_widget.queue_redraw()

## Force the key into a specific detent (e.g. on overlay re-open to restore
## prior state). Emits key_position_changed.
func set_key_position(pos: int) -> void:
	pos = clampi(pos, KeyPos.AUTO, KeyPos.ONDERHOUD)
	if key_position == pos:
		return
	key_position = pos
	_flash_active = false
	if _key_widget != null:
		_key_widget.queue_redraw()
	if _lamps_widget != null:
		_lamps_widget.queue_redraw()
	if _start_widget != null:
		_start_widget.queue_redraw()
	emit_signal("key_position_changed", key_position)

# ----------------------------------------------------------------- build
func _build() -> void:
	# Background brushed-stainless face.
	_bg = ColorRect.new()
	_bg.color = C_PANEL
	_bg.anchor_right = 1.0
	_bg.anchor_bottom = 1.0
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	# Header strip with title + subtitle.
	_header = Panel.new()
	_header.position = Vector2(0, 0)
	_header.size = Vector2(PANEL_SIZE.x, 64)
	var hdr_sb := StyleBoxFlat.new()
	hdr_sb.bg_color = C_HEADER_BG
	hdr_sb.border_color = C_PANEL_EDGE
	hdr_sb.border_width_bottom = 2
	_header.add_theme_stylebox_override("panel", hdr_sb)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)

	_title_lbl = Label.new()
	_title_lbl.text = "Besturing"
	_title_lbl.position = Vector2(20, 8)
	_title_lbl.add_theme_color_override("font_color", C_HEADER_TX)
	_title_lbl.add_theme_font_size_override("font_size", 14)
	_header.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.text = "Shredder 2"
	_subtitle_lbl.position = Vector2(20, 28)
	_subtitle_lbl.add_theme_color_override("font_color", C_HEADER_TX)
	_subtitle_lbl.add_theme_font_size_override("font_size", 24)
	_header.add_child(_subtitle_lbl)

	# ----- KEY SWITCH widget (left third)
	_key_widget = Control.new()
	_key_widget.position = Vector2(60, 110)
	_key_widget.size = Vector2(200, 240)
	_key_widget.mouse_filter = Control.MOUSE_FILTER_STOP
	_key_widget.draw.connect(_draw_key_switch)
	_key_widget.gui_input.connect(_on_key_widget_input)
	add_child(_key_widget)

	_key_lbl = Label.new()
	_key_lbl.text = "SLEUTELSCHAKELAAR"
	_key_lbl.position = Vector2(60, 360)
	_key_lbl.size = Vector2(200, 20)
	_key_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_key_lbl.add_theme_color_override("font_color", C_LABEL_TX)
	_key_lbl.add_theme_font_size_override("font_size", 12)
	add_child(_key_lbl)

	# ----- 3 detent lamps next to the key switch (vertical column on its right)
	_lamps_widget = Control.new()
	_lamps_widget.position = Vector2(260, 110)
	_lamps_widget.size = Vector2(80, 240)
	_lamps_widget.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lamps_widget.draw.connect(_draw_detent_lamps)
	add_child(_lamps_widget)

	# ----- GREEN START pushbutton (middle)
	_start_widget = Control.new()
	_start_widget.position = Vector2(370, 130)
	_start_widget.size = Vector2(160, 160)
	_start_widget.mouse_filter = Control.MOUSE_FILTER_STOP
	_start_widget.draw.connect(_draw_start_button)
	_start_widget.gui_input.connect(_on_start_widget_input)
	add_child(_start_widget)

	_start_lbl = Label.new()
	_start_lbl.text = "AUTOMAAT START"
	_start_lbl.position = Vector2(370, 300)
	_start_lbl.size = Vector2(160, 20)
	_start_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_start_lbl.add_theme_color_override("font_color", C_LABEL_TX)
	_start_lbl.add_theme_font_size_override("font_size", 12)
	add_child(_start_lbl)

	# ----- RED MUSHROOM stop (right)
	_stop_widget = Control.new()
	_stop_widget.position = Vector2(560, 120)
	_stop_widget.size = Vector2(140, 180)
	_stop_widget.mouse_filter = Control.MOUSE_FILTER_STOP
	_stop_widget.draw.connect(_draw_mushroom_stop)
	_stop_widget.gui_input.connect(_on_stop_widget_input)
	add_child(_stop_widget)

	_stop_lbl = Label.new()
	_stop_lbl.text = "NOODSTOP"
	_stop_lbl.position = Vector2(560, 310)
	_stop_lbl.size = Vector2(140, 20)
	_stop_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_stop_lbl.add_theme_color_override("font_color", C_LABEL_TX)
	_stop_lbl.add_theme_font_size_override("font_size", 12)
	add_child(_stop_lbl)

	# ----- close button bottom-right
	_close_button = Button.new()
	_close_button.text = "  X  "
	_close_button.position = Vector2(PANEL_SIZE.x - 60, PANEL_SIZE.y - 40)
	_close_button.size = Vector2(40, 28)
	_close_button.add_theme_font_size_override("font_size", 14)
	_close_button.pressed.connect(_on_close_pressed)
	add_child(_close_button)

func _refresh() -> void:
	if _key_widget != null:
		_key_widget.queue_redraw()
	if _lamps_widget != null:
		_lamps_widget.queue_redraw()
	if _start_widget != null:
		_start_widget.queue_redraw()
	if _stop_widget != null:
		_stop_widget.queue_redraw()

# =========================================================== draw callbacks

func _draw_key_switch() -> void:
	# Big chromed bezel + brass key head. Rotates to show the current detent.
	var w := _key_widget
	var c := w.size * 0.5
	# bezel
	w.draw_circle(c, 72.0, C_CHROME_DK)
	w.draw_circle(c, 66.0, C_CHROME)
	w.draw_circle(c, 56.0, Color(0.20, 0.21, 0.22, 1.0))
	# detent ticks at I (top-left), II (top), III (top-right)
	for i in 3:
		var ang := -PI * 0.75 + (PI * 0.5) * float(i)
		var p_out := c + Vector2(cos(ang), sin(ang)) * 60.0
		var p_in  := c + Vector2(cos(ang), sin(ang)) * 52.0
		w.draw_line(p_in, p_out, Color(0.18, 0.19, 0.20, 1.0), 3.0)
	# key head — rotated to current position
	var key_ang : float = -PI * 0.75 + (PI * 0.5) * float(key_position)
	var key_tip := c + Vector2(cos(key_ang), sin(key_ang)) * 50.0
	w.draw_line(c, key_tip, C_KEYHEAD_HI, 6.0)
	w.draw_line(c, key_tip, C_KEYHEAD, 2.0)
	# central hub
	w.draw_circle(c, 12.0, C_KEYHEAD)
	w.draw_circle(c, 8.0, C_KEYHEAD_HI)
	# little Roman numerals at the tick ends
	var fnt := ThemeDB.fallback_font
	var labels := ["I", "II", "III"]
	for i in 3:
		var ang2 := -PI * 0.75 + (PI * 0.5) * float(i)
		var p := c + Vector2(cos(ang2), sin(ang2)) * 84.0
		w.draw_string(fnt, p + Vector2(-6, 4), labels[i], HORIZONTAL_ALIGNMENT_CENTER, -1, 12, C_LABEL_TX)

func _draw_detent_lamps() -> void:
	# Three small lamps in a vertical column labelled I / II / III.
	var w := _lamps_widget
	var names := ["I  AUTO", "II  HAND", "III  ONDERHOUD"]
	var ys := [40.0, 100.0, 160.0]
	for i in 3:
		var center := Vector2(20.0, ys[i])
		# bezel
		w.draw_circle(center, 12.0, C_CHROME_DK)
		w.draw_circle(center, 10.0, C_CHROME)
		# lens
		var lit : bool = (i == key_position)
		var col := C_LAMP_GREEN if lit else C_LAMP_OFF
		w.draw_circle(center, 7.0, col)
		if lit:
			# soft halo
			w.draw_circle(center, 12.0, Color(C_LAMP_GREEN.r, C_LAMP_GREEN.g, C_LAMP_GREEN.b, 0.18))
		# label
		var fnt := ThemeDB.fallback_font
		w.draw_string(fnt, Vector2(40.0, ys[i] + 5.0), names[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 12, C_LABEL_TX)

func _draw_start_button() -> void:
	# Illuminated green pushbutton. Renders 3 layers: chrome rim, lens, glow.
	var w := _start_widget
	var c := w.size * 0.5
	# chrome rim
	w.draw_circle(c, 72.0, C_CHROME_DK)
	w.draw_circle(c, 66.0, C_CHROME)
	# button face — colour depends on lamp state
	var lit : bool = running and not e_stop_active
	var flashing : bool = _flash_active and not e_stop_active
	var face_col : Color
	if flashing:
		var on : bool = (int(_flash_t) % 2) == 0
		face_col = C_LAMP_GREEN if on else C_LAMP_GREEN_DIM
	elif lit:
		face_col = C_LAMP_GREEN
	else:
		face_col = C_BUTTON_GREY
	w.draw_circle(c, 56.0, face_col)
	# glossy highlight
	w.draw_circle(c + Vector2(-12, -16), 18.0, Color(1.0, 1.0, 1.0, 0.22))
	# inner ring
	w.draw_arc(c, 56.0, 0.0, TAU, 48, Color(0.18, 0.20, 0.18, 0.6), 1.5)
	# "I" symbol on the button
	var fnt := ThemeDB.fallback_font
	var sym := "I"
	var sym_col := C_LABEL_TX if not lit and not flashing else Color(0.06, 0.20, 0.06, 1.0)
	w.draw_string(fnt, c + Vector2(-4, 8), sym, HORIZONTAL_ALIGNMENT_CENTER, -1, 22, sym_col)

func _draw_mushroom_stop() -> void:
	# Big red mushroom — slightly squashed when latched.
	var w := _stop_widget
	var c := w.size * 0.5
	# yellow safety collar
	w.draw_circle(c, 64.0, Color(0.95, 0.78, 0.10, 1.0))
	w.draw_circle(c, 60.0, Color(0.10, 0.10, 0.10, 1.0))
	# mushroom cap
	var cap_r : float = 50.0 if not e_stop_active else 54.0
	w.draw_circle(c, cap_r, C_MUSHROOM_DK)
	w.draw_circle(c, cap_r - 4.0, C_MUSHROOM_RED)
	# highlight crescent
	w.draw_circle(c + Vector2(-14, -18), 14.0, Color(1.0, 0.5, 0.45, 0.35))
	# embossed "STOP" text
	var fnt := ThemeDB.fallback_font
	var label : String = "STOP" if not e_stop_active else "RESET"
	w.draw_string(fnt, c + Vector2(-22, 6), label, HORIZONTAL_ALIGNMENT_CENTER, -1, 18, Color(0.10, 0.02, 0.02, 1.0))

# ========================================================== input handlers

func _on_key_widget_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			# cycle: AUTO → HAND → ONDERHOUD → AUTO
			var nxt : int = (key_position + 1) % 3
			set_key_position(nxt)

func _on_start_widget_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	if e_stop_active:
		# Hard-blocked by the e-stop. Real cabinet would do nothing, so neither do we.
		return
	if key_position != KeyPos.AUTO:
		# Wrong-mode feedback: kick the flash routine. The host sees no
		# start_pressed signal because the relay chain is broken at the key.
		_flash_active = true
		_flash_t = 0.0
		if _start_widget != null:
			_start_widget.queue_redraw()
		return
	_flash_active = false
	emit_signal("start_pressed")

func _on_stop_widget_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if not (mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT):
		return
	# A mushroom stop is single-action: pressing it always emits stop_pressed.
	# The host is in charge of latching e_stop_active via set_e_stop() based on
	# its own safety state machine.
	emit_signal("stop_pressed")

func _on_close_pressed() -> void:
	emit_signal("request_close")

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		emit_signal("request_close")
		get_viewport().set_input_as_handled()
