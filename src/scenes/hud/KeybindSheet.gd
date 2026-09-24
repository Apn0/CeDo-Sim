extends Control
class_name KeybindSheet

## Q4 (2026-09-23) — the in-game key sheet, toggled with F1 (action
## `help_overlay`). One page listing every action the Settings → Controls tab
## knows (SettingsManager.ACTION_GROUPS / ACTION_LABELS) with its LIVE binding
## read from the InputMap when the sheet opens, so a rebind shows here without
## a restart. A pure reference: it does not pause the shift and does not take
## the mouse. HUD builds one and forwards F1 / ESC to it
## (HUD._handle_keybind_sheet_input).
##
## build_rows() is the whole content model and is static, so the headless
## suite (test_keybind_sheet) asserts on exactly what gets rendered. The
## SettingsManager autoload is reached through the tree, never as a bare
## identifier, so this file also parses where no autoloads exist.

const C_PANEL   := Color(0.06, 0.07, 0.06, 0.97)
const C_BORDER  := Color(0.32, 0.52, 0.34, 0.9)
const C_TITLE   := Color(0.78, 0.92, 0.78, 1.0)
const C_GROUP   := Color(1.0, 0.88, 0.60, 1.0)
const C_LABEL   := Color(0.86, 0.90, 0.84, 1.0)
const C_KEY     := Color(1.0, 0.90, 0.30, 1.0)
const C_UNBOUND := Color(0.55, 0.55, 0.55, 1.0)
const UNBOUND   := "—"

var _sections : VBoxContainer = null
var _scroll   : ScrollContainer = null
var _row_count : int = 0
var _group_count : int = 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	top_level = true
	z_index = 90
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	_build()

# =============================================================================
# CONTENT MODEL
# =============================================================================
static func _settings() -> Node:
	var loop := Engine.get_main_loop()
	if loop is SceneTree and (loop as SceneTree).root != null:
		return (loop as SceneTree).root.get_node_or_null("/root/SettingsManager")
	return null

## Human-readable binding list for one action's events, e.g. "F4", "Left mouse",
## "Ctrl+S / Pad btn 3". UNBOUND when the action has no events.
static func format_events(events: Array) -> String:
	if events.is_empty():
		return UNBOUND
	var parts : Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var keycode : int = k.keycode if k.keycode != 0 else k.physical_keycode
			var s := ""
			if k.ctrl_pressed:
				s += "Ctrl+"
			if k.alt_pressed:
				s += "Alt+"
			if k.shift_pressed:
				s += "Shift+"
			s += OS.get_keycode_string(keycode)
			parts.append(s)
		elif ev is InputEventMouseButton:
			match (ev as InputEventMouseButton).button_index:
				MOUSE_BUTTON_LEFT:       parts.append("Left mouse")
				MOUSE_BUTTON_RIGHT:      parts.append("Right mouse")
				MOUSE_BUTTON_MIDDLE:     parts.append("Middle mouse")
				MOUSE_BUTTON_WHEEL_UP:   parts.append("Wheel up")
				MOUSE_BUTTON_WHEEL_DOWN: parts.append("Wheel down")
				_: parts.append("Mouse %d" % (ev as InputEventMouseButton).button_index)
		elif ev is InputEventJoypadButton:
			parts.append("Pad btn %d" % (ev as InputEventJoypadButton).button_index)
		elif ev is InputEventJoypadMotion:
			parts.append("Pad axis %d" % (ev as InputEventJoypadMotion).axis)
	if parts.is_empty():
		return UNBOUND
	return " / ".join(parts)

## Every action the Controls tab lists, in its group order, with the LIVE
## binding. Row: {group, action, label, keys, bound}. The label is the Controls
## tab's first line (ACTION_LABELS embeds hints and one multi-line entry); the
## keys column is the InputMap, which is what actually fires.
static func build_rows() -> Array:
	var rows : Array = []
	var sm := _settings()
	if sm == null:
		return rows
	var groups : Array = sm.ACTION_GROUPS
	var labels : Dictionary = sm.ACTION_LABELS
	for g in groups:
		var gname := String((g as Dictionary).get("label", ""))
		for action in (g as Dictionary).get("actions", []):
			var a := String(action)
			var events : Array = []
			if InputMap.has_action(a):
				events = InputMap.action_get_events(a)
			var label := String(labels.get(a, a)).split("\n")[0]
			rows.append({
				"group": gname,
				"action": a,
				"label": label,
				"keys": format_events(events),
				"bound": not events.is_empty(),
			})
	return rows

# =============================================================================
# UI
# =============================================================================
func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)

	var card := PanelContainer.new()
	card.name = "Card"
	card.set_anchors_preset(Control.PRESET_CENTER)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ps := StyleBoxFlat.new()
	ps.bg_color = C_PANEL
	ps.border_color = C_BORDER
	ps.set_border_width_all(2)
	ps.set_corner_radius_all(8)
	ps.content_margin_left = 24.0
	ps.content_margin_right = 24.0
	ps.content_margin_top = 16.0
	ps.content_margin_bottom = 16.0
	card.add_theme_stylebox_override("panel", ps)
	add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	card.add_child(vbox)

	var title := Label.new()
	title.name = "Title"
	title.text = "KEY SHEET"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", C_TITLE)
	vbox.add_child(title)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.custom_minimum_size = Vector2(760.0, 560.0)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vbox.add_child(_scroll)

	_sections = VBoxContainer.new()
	_sections.name = "Sections"
	_sections.add_theme_constant_override("separation", 10)
	_sections.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_sections)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = "[F1] / [Esc] close   ·   rebind under Settings → Controls (P)"
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", C_LABEL)
	vbox.add_child(hint)

## Rebuild the sections from the live InputMap. Called by open(), so a rebind
## made in Settings shows the next time the sheet is opened.
func refresh() -> void:
	if _sections == null:
		return
	for c in _sections.get_children():
		_sections.remove_child(c)
		c.queue_free()
	_row_count = 0
	_group_count = 0
	var current_group := ""
	var grid : GridContainer = null
	for r in build_rows():
		var row : Dictionary = r
		if String(row["group"]) != current_group:
			current_group = String(row["group"])
			_group_count += 1
			var head := Label.new()
			head.text = current_group.to_upper()
			head.add_theme_font_size_override("font_size", 13)
			head.add_theme_color_override("font_color", C_GROUP)
			_sections.add_child(head)
			grid = GridContainer.new()
			grid.columns = 2
			grid.add_theme_constant_override("h_separation", 24)
			grid.add_theme_constant_override("v_separation", 2)
			_sections.add_child(grid)
		var key_lbl := Label.new()
		key_lbl.text = String(row["keys"])
		key_lbl.custom_minimum_size = Vector2(150.0, 0.0)
		key_lbl.add_theme_font_size_override("font_size", 13)
		key_lbl.add_theme_color_override("font_color", C_KEY if bool(row["bound"]) else C_UNBOUND)
		grid.add_child(key_lbl)
		var lbl := Label.new()
		lbl.text = String(row["label"])
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color", C_LABEL)
		grid.add_child(lbl)
		_row_count += 1

func row_count() -> int:
	return _row_count

func group_count() -> int:
	return _group_count

func open() -> void:
	var vp := get_viewport()
	if vp != null:
		var vs : Vector2 = vp.get_visible_rect().size
		size = vs
		if _scroll != null:
			_scroll.custom_minimum_size = Vector2(minf(760.0, vs.x * 0.9), minf(560.0, vs.y * 0.75))
	refresh()
	visible = true

func close() -> void:
	visible = false

func is_open() -> bool:
	return visible

func toggle() -> void:
	if visible:
		close()
	else:
		open()
