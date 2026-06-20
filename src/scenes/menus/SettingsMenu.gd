extends CanvasLayer

class_name SettingsMenu

## Tabbed settings menu — Graphics / Audio / Gameplay / Controls.
## UI is built programmatically (Godot 4 .tscn for complex UI gets cumbersome).
##
## Lifecycle:
##   _ready()      — build the whole UI, hidden by default
##   open()        — show, snapshot pending from current
##   close()       — hide
##   _on_apply()   — SettingsManager.apply() + emit closed signal
##   _on_cancel()  — SettingsManager.cancel() + close
##
## Pattern per setting row:
##   HBoxContainer
##     ├── Label (180 px wide, left-aligned)
##     ├── Control (slider / option button / checkbox / spinbox)
##     └── Value-readout label (when slider) — optional, right side
##
## Influences:
##   - Euro Truck Simulator 2 tab layout
##   - Godot 4 input remapping pattern (action_erase_events + action_add_event)

signal closed

# ── UI roots ──────────────────────────────────────────────────────────────────
var _dim          : ColorRect
var _panel        : PanelContainer
var _tabs         : TabContainer
var _apply_btn    : Button
var _cancel_btn   : Button
var _reset_btn    : Button

# Rebinding capture state
var _waiting_for_key_for : String = ""    # action name; "" when not capturing
var _waiting_btn          : Button = null

# Cache widget→key bindings for fast value sync (e.g. after Cancel)
var _widgets : Dictionary = {}            # "category/key" → control

# Controls-overview labels (read-only quick-reference at top of Controls tab).
# Refreshed alongside rebind buttons via _refresh_keybind_widgets().
var _overview_value_labels : Dictionary = {}   # action → Label

# ── Constants for layout ──────────────────────────────────────────────────────
const PANEL_W    := 960.0
const PANEL_H    := 680.0
const LABEL_W    := 220.0
const ROW_H      := 32.0
const FONT_SMALL := 13
const FONT_BODY  := 15
const FONT_TITLE := 22

# =============================================================================
func _ready() -> void:
	layer = 50    # above HUD pause overlay
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui()
	visible = false

# =============================================================================
# OPEN / CLOSE
# =============================================================================
func open() -> void:
	SettingsManager.cancel()    # snapshot pending = current
	_refresh_all_widgets()
	visible = true
	# Focus first interactive control for keyboard nav
	_apply_btn.grab_focus()

func close() -> void:
	visible = false
	_waiting_for_key_for = ""
	_waiting_btn = null
	closed.emit()

# =============================================================================
# UI CONSTRUCTION
# =============================================================================
func _build_ui() -> void:
	# Dim background
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = Color(0.0, 0.0, 0.0, 0.62)
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP    # eat clicks behind
	add_child(_dim)

	# Centred panel
	_panel = PanelContainer.new()
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_panel.offset_left   = -PANEL_W * 0.5
	_panel.offset_top    = -PANEL_H * 0.5
	_panel.offset_right  =  PANEL_W * 0.5
	_panel.offset_bottom =  PANEL_H * 0.5

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.08, 0.09, 0.97)
	ps.corner_radius_top_left     = 10
	ps.corner_radius_top_right    = 10
	ps.corner_radius_bottom_left  = 10
	ps.corner_radius_bottom_right = 10
	ps.content_margin_left   = 28.0
	ps.content_margin_right  = 28.0
	ps.content_margin_top    = 20.0
	ps.content_margin_bottom = 18.0
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)

	var vroot := VBoxContainer.new()
	vroot.add_theme_constant_override("separation", 12)
	_panel.add_child(vroot)

	# Header
	var header := HBoxContainer.new()
	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", FONT_TITLE)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.60, 1))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.custom_minimum_size = Vector2(36, 30)
	close_btn.pressed.connect(_on_cancel)
	header.add_child(close_btn)
	vroot.add_child(header)

	# Tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_tabs.add_theme_font_size_override("font_size", FONT_BODY)
	vroot.add_child(_tabs)

	_build_graphics_tab()
	_build_audio_tab()
	_build_gameplay_tab()
	_build_voice_tab()
	_build_controls_tab()

	# Footer
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation", 10)
	_reset_btn = Button.new()
	_reset_btn.text = "Reset Tab to Defaults"
	_reset_btn.pressed.connect(_on_reset_current_tab)
	footer.add_child(_reset_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(spacer)

	_cancel_btn = Button.new()
	_cancel_btn.text = "Cancel"
	_cancel_btn.custom_minimum_size = Vector2(110, 36)
	_cancel_btn.pressed.connect(_on_cancel)
	footer.add_child(_cancel_btn)

	_apply_btn = Button.new()
	_apply_btn.text = "Apply"
	_apply_btn.custom_minimum_size = Vector2(110, 36)
	_apply_btn.pressed.connect(_on_apply)
	footer.add_child(_apply_btn)

	vroot.add_child(footer)

# =============================================================================
# GRAPHICS TAB
# =============================================================================
func _build_graphics_tab() -> void:
	var tab := _make_tab("Graphics")

	_add_option_row(tab, "graphics", "display_mode", "Display mode",
		["windowed", "borderless", "fullscreen"],
		["Windowed", "Borderless", "Fullscreen"])

	_add_resolution_row(tab)

	_add_option_row(tab, "graphics", "vsync", "V-Sync",
		["disabled", "enabled", "adaptive"],
		["Off", "On", "Adaptive"])

	_add_fps_row(tab)

	_add_slider_row(tab, "graphics", "render_scale", "Render scale",
		0.5, 2.0, 0.05, "%.2fx")

	_add_option_row(tab, "graphics", "msaa", "MSAA",
		[0, 2, 4, 8], ["Off", "2×", "4×", "8×"])

	_add_check_row(tab, "graphics", "fxaa", "FXAA")

	_add_option_row(tab, "graphics", "shadow_quality", "Shadow quality",
		[0, 1, 2, 3, 4], ["Off", "Low", "Medium", "High", "Ultra"])

	_add_slider_row(tab, "graphics", "shadow_distance", "Shadow distance",
		50.0, 500.0, 10.0, "%.0f m")

	# #162 — relabel: the toggle drives Environment.volumetric_fog, but it reads
	# as a 360° distance haze, not localized smoke. Calling it "Volumetric fog"
	# misled the operator. Localized steam plumes at the extruder/dryers are a
	# separate effort (X3 / #182). Save-key stays "volumetric_fog" for compat.
	_add_check_row(tab, "graphics", "volumetric_fog", "Distance haze")
	_add_check_row(tab, "graphics", "ssao", "Screen-space ambient occlusion")
	_add_check_row(tab, "graphics", "sdfgi", "Global illumination (SDFGI) — heavy")

	_add_slider_row(tab, "graphics", "brightness", "Brightness",
		0.5, 1.5, 0.05, "%.2f")

	_add_slider_row(tab, "graphics", "fov", "Field of view",
		60.0, 110.0, 1.0, "%.0f°")

# =============================================================================
# AUDIO TAB
# =============================================================================
func _build_audio_tab() -> void:
	var tab := _make_tab("Audio")

	_add_db_slider_row(tab, "audio", "master_db",   "Master volume")
	_add_db_slider_row(tab, "audio", "machines_db", "Machines (extruder, washers, vacuum)")
	_add_db_slider_row(tab, "audio", "voices_db",   "Voices (NPCs, radio)")
	_add_db_slider_row(tab, "audio", "ambient_db",  "Ambient (factory hum)")
	_add_db_slider_row(tab, "audio", "ui_db",       "UI (HUD chirps)")

	_add_check_row(tab, "audio", "mute_unfocused", "Mute when window unfocused")

# =============================================================================
# GAMEPLAY TAB
# =============================================================================
func _build_gameplay_tab() -> void:
	var tab := _make_tab("Gameplay")

	# Mouse — first-person sim priority
	_add_section_header(tab, "Mouse & Camera")
	_add_slider_row(tab, "gameplay", "mouse_sensitivity_x", "Mouse sensitivity X",
		0.0005, 0.01, 0.0001, "%.4f")
	_add_slider_row(tab, "gameplay", "mouse_sensitivity_y", "Mouse sensitivity Y",
		0.0005, 0.01, 0.0001, "%.4f")
	_add_check_row(tab, "gameplay", "invert_mouse_y", "Invert mouse Y")
	_add_check_row(tab, "gameplay", "invert_cam_x", "Invert free-cam X (external orbit)")
	_add_check_row(tab, "gameplay", "invert_cam_y", "Invert free-cam Y (external orbit)")
	_add_slider_row(tab, "gameplay", "mouse_smoothing", "Mouse smoothing",
		0.0, 1.0, 0.05, "%.0f%%", true)
	_add_check_row(tab, "gameplay", "head_bob", "Head bob while walking")

	# Gamepad
	_add_section_header(tab, "Gamepad")
	_add_slider_row(tab, "gameplay", "gamepad_deadzone", "Gamepad stick deadzone",
		0.0, 0.5, 0.01, "%.0f%%", true)

	# HUD
	_add_section_header(tab, "HUD")
	_add_slider_row(tab, "gameplay", "hud_opacity", "HUD opacity",
		0.5, 1.0, 0.05, "%.0f%%", true)
	_add_check_row(tab, "gameplay", "show_interaction_prompts", "Show interaction prompts")

	# Saves
	_add_section_header(tab, "Saves")
	_add_option_row(tab, "gameplay", "autosave_interval_s", "Auto-save interval",
		[0, 15, 30, 60, 120, 300],
		["Off", "15 s", "30 s", "60 s", "2 min", "5 min"])

	# Shift pace (#166) — how fast the 8 h shift clock runs. ShiftClock reads this.
	_add_section_header(tab, "Shift")
	_add_option_row(tab, "gameplay", "shift_time_scale", "Time speed",
		[1.0, 6.0, 12.0, 24.0, 48.0, 96.0],
		["Real-time (8 h)", "6× (80 min)", "12× (40 min)", "24× (20 min)", "48× (10 min)", "96× (5 min)"])

	# Time & Date — operator-set starting time / day. Empty = "use the shift
	# bell" (07:00 / 15:00 / 23:00) and today's calendar. Applied on next
	# scene-load OR via the live "Apply" path which fires ShiftClock.time_jumped
	# so NPCs + cars reposition to match the new wall-clock instant.
	_add_section_header(tab, "Time & Date")
	_add_time_row(tab, "gameplay", "starting_time", "Starting time")
	_add_date_row(tab, "gameplay", "starting_date", "Starting date")
	var time_hint := Label.new()
	time_hint.text = "Sets the wall-clock when the world starts or reloads. Past times today roll to the next working day. Leave blank to use the shift bell + today."
	time_hint.add_theme_font_size_override("font_size", FONT_SMALL)
	time_hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	time_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(time_hint)

	# Accessibility
	_add_section_header(tab, "Accessibility")
	_add_check_row(tab, "gameplay", "subtitles", "Subtitles")
	_add_option_row(tab, "gameplay", "subtitle_size", "Subtitle size",
		["small", "medium", "large"], ["Small", "Medium", "Large"])
	_add_check_row(tab, "gameplay", "tutorial_hints", "Show tutorial hints")

	# Locale
	_add_section_header(tab, "Locale")
	_add_option_row(tab, "gameplay", "language", "Language",
		["en", "nl"], ["English", "Nederlands"])
	_add_option_row(tab, "gameplay", "units", "Units",
		["metric", "imperial"], ["Metric (m, km/h)", "Imperial (ft, mph)"])

# =============================================================================
# VOICE & AI TAB — local-first, cloud disabled by default
# =============================================================================
## All three backends are described on the panel: Local (whisper.cpp / llama.cpp
## / piper via OS.execute, paths in user://voice_paths.cfg — SILENT degrade
## when binaries missing), Cloud (OpenAI whisper-1 / gpt-4o-mini / tts-1, only
## used when explicitly selected AND OPENAI_API_KEY is present), Mock (canned
## strings for dev/testing). NEVER silently use the cloud.
func _build_voice_tab() -> void:
	var tab := _make_tab("Voice & AI")

	_add_section_header(tab, "Backend")
	_add_option_row(tab, "gameplay", "voice_backend", "Voice backend",
		["local", "cloud", "mock"],
		["Local (whisper.cpp / llama.cpp / piper)",
		 "Cloud (OpenAI — opt-in, requires key)",
		 "Mock (canned strings — dev only)"])

	var hint := Label.new()
	hint.text = "LOCAL is the default. Drop binaries into user://tools/ — see voice_paths.cfg. Missing tools silently degrade to text-only walkie. CLOUD requires OPENAI_API_KEY in your Desktop .env and is OFF by default. We never silently send audio to the cloud."
	hint.add_theme_font_size_override("font_size", FONT_SMALL)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tab.add_child(hint)

	_spacer(tab, 12)
	_add_section_header(tab, "Test")
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var btn := Button.new()
	btn.text = "Test voice"
	btn.custom_minimum_size = Vector2(140, 30)
	btn.pressed.connect(_on_test_voice_pressed)
	row.add_child(btn)
	var status := Label.new()
	status.text = "  Plays a short line through the selected backend (check godot.log for the result)."
	status.add_theme_font_size_override("font_size", FONT_SMALL)
	status.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	row.add_child(status)
	tab.add_child(row)

# Button handler — defers to VoiceService.test_voice(). Test must be triggered
# AFTER the operator's voice_backend selection has been applied, so we Apply
# first and then test. This keeps the "test what I picked" behaviour intuitive.
func _on_test_voice_pressed() -> void:
	SettingsManager.apply()
	var vs := get_node_or_null("/root/VoiceService")
	if vs != null and vs.has_method("test_voice"):
		vs.test_voice()

# =============================================================================
# CONTROLS TAB
# =============================================================================
## Layout: a read-only "Overview" reference table at the top (so the user can
## scan every binding at a glance), then per-group rebindable rows below.
func _build_controls_tab() -> void:
	var tab := _make_tab("Controls")

	# ── Quick-reference overview (read-only, refreshed on rebind) ────────────
	_build_controls_overview(tab)

	# ── Rebindable rows ──────────────────────────────────────────────────────
	_add_section_header(tab, "Rebind keys")
	var hint := Label.new()
	hint.text = "Click a binding then press the new key or button. Press Escape to cancel."
	hint.add_theme_font_size_override("font_size", FONT_SMALL)
	hint.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7, 1))
	tab.add_child(hint)
	_spacer(tab, 6)

	for group in SettingsManager.ACTION_GROUPS:
		_add_section_header(tab, group["label"])
		for action in group["actions"]:
			_add_keybind_row(tab, action)

## Compact two-column action→key reference. Read-only — used as a "cheat sheet"
## inside the settings menu so the player can see every binding at a glance.
func _build_controls_overview(parent: VBoxContainer) -> void:
	_add_section_header(parent, "Controls overview")
	var grid := GridContainer.new()
	grid.columns = 4    # action | binding | action | binding (two pairs per row)
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(grid)

	# Build action list in the same order as ACTION_GROUPS, with little group
	# separators between sections so it stays scannable.
	var first_group := true
	for group in SettingsManager.ACTION_GROUPS:
		if not first_group:
			_overview_group_break(grid)
		first_group = false
		_overview_group_title(grid, group["label"])
		var actions: Array = group["actions"]
		# Pair them up so two action/binding pairs fit per grid row.
		var i := 0
		while i < actions.size():
			var a1: String = actions[i]
			_overview_pair(grid, a1)
			if i + 1 < actions.size():
				var a2: String = actions[i + 1]
				_overview_pair(grid, a2)
			else:
				# odd one out — pad the row so columns stay aligned
				grid.add_child(Control.new())
				grid.add_child(Control.new())
			i += 2

	# Build & Edit reference (factory builder — these keys are mode-specific and mostly
	# hardcoded, so they're described here rather than listed as rebindable rows).
	_add_section_header(parent, "Factory builder (Tab) & jog/edit mode (K)")
	var build_note := Label.new()
	build_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	build_note.add_theme_font_size_override("font_size", FONT_SMALL)
	build_note.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1))
	build_note.text = \
		"[Tab] open / close the factory builder.   [G] toggle grid snap.\n" \
		+ "PLACING an item:  [LMB] place   ·   [Q]/[E] rotate   ·   [R]/[F] raise / lower   ·   [X] delete under crosshair   ·   [RMB] put item away.\n" \
		+ "[K] enter / exit JOG-EDIT to reposition already-placed machines:  aim + [LMB] to select, then  arrows = move   ·   [R]/[F] up / down   ·   [Q]/[E] rotate   ·   [+]/[-] scale   ·   hold [Shift] = fine step   ·   [X] delete   ·   [K] or [RMB] exit."
	parent.add_child(build_note)
	_spacer(parent, 10)

	# Mouse-as-joystick note (a gesture, not a rebindable action — so it's described
	# here rather than listed in the grid).
	_add_section_header(parent, "Mouse joystick (while seated in a vehicle)")
	var note := Label.new()
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.add_theme_font_size_override("font_size", FONT_SMALL)
	note.add_theme_color_override("font_color", Color(0.82, 0.82, 0.82, 1))
	note.text = \
		"Hold a mouse button and move the mouse to work the tool like a joystick " \
		+ "(the camera holds still while you do):\n" \
		+ "  • Hold LEFT  — drag ↕ / ↔ = two tool functions\n" \
		+ "  • Hold RIGHT — drag ↕ / ↔ = two more\n" \
		+ "  • Hold BOTH  — all four move together.\n" \
		+ "Forklift: L =lift / tilt, R =spread / rotate.   " \
		+ "Bale clamp: L =lift / tilt.   " \
		+ "Merlo: L =boom / grapple, R =curl / telescope.   " \
		+ "Scissor lift: L =platform up·down."
	parent.add_child(note)
	_spacer(parent, 10)

func _overview_pair(grid: GridContainer, action: String) -> void:
	var lbl_text: String = SettingsManager.ACTION_LABELS.get(action, action)
	var lbl := Label.new()
	lbl.text = lbl_text
	lbl.add_theme_font_size_override("font_size", FONT_SMALL)
	lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	lbl.custom_minimum_size = Vector2(240, 0)
	grid.add_child(lbl)

	var val := Label.new()
	val.text = _format_binding(SettingsManager.pending_keybinds().get(action, []))
	val.add_theme_font_size_override("font_size", FONT_SMALL)
	val.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55, 1))
	val.custom_minimum_size = Vector2(140, 0)
	grid.add_child(val)
	_overview_value_labels[action] = val

func _overview_group_title(grid: GridContainer, title: String) -> void:
	# Full-row group header (4 cells: span via a single label + 3 empty spacers)
	var t := Label.new()
	t.text = title.to_upper()
	t.add_theme_font_size_override("font_size", FONT_SMALL)
	t.add_theme_color_override("font_color", Color(0.62, 0.55, 0.40, 1))
	grid.add_child(t)
	for _i in 3:
		grid.add_child(Control.new())

func _overview_group_break(grid: GridContainer) -> void:
	for _i in 4:
		var c := Control.new()
		c.custom_minimum_size = Vector2(0, 6)
		grid.add_child(c)

# =============================================================================
# ROW BUILDERS
# =============================================================================
func _make_tab(title: String) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.name = title
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(scroll)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 6)
	scroll.add_child(v)
	return v

func _add_section_header(parent: VBoxContainer, label_text: String) -> void:
	_spacer(parent, 6)
	var lbl := Label.new()
	lbl.text = label_text.to_upper()
	lbl.add_theme_font_size_override("font_size", FONT_SMALL)
	lbl.add_theme_color_override("font_color", Color(0.62, 0.55, 0.40, 1))
	parent.add_child(lbl)
	var sep := HSeparator.new()
	parent.add_child(sep)

func _spacer(parent: Control, h: int) -> void:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	parent.add_child(c)

func _new_row(parent: VBoxContainer, label_text: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(0, ROW_H)
	row.add_theme_constant_override("separation", 12)
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(LABEL_W, 0)
	label.add_theme_font_size_override("font_size", FONT_BODY)
	row.add_child(label)
	parent.add_child(row)
	return row

# ── Option (dropdown) ─────────────────────────────────────────────────────────
func _add_option_row(parent: VBoxContainer, category: String, key: String,
		label_text: String, values: Array, labels: Array) -> void:
	var row := _new_row(parent, label_text)
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", FONT_BODY)
	for i in labels.size():
		opt.add_item(str(labels[i]), i)
	opt.set_meta("values", values)
	opt.item_selected.connect(func(idx: int):
		SettingsManager.set_pending(category, key, values[idx]))
	row.add_child(opt)
	_widgets[category + "/" + key] = opt

# ── Resolution (special: pair of dimensions) ──────────────────────────────────
func _add_resolution_row(parent: VBoxContainer) -> void:
	var row := _new_row(parent, "Resolution")
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", FONT_BODY)
	var resolutions := [
		Vector2i(1280, 720),
		Vector2i(1600, 900),
		Vector2i(1920, 1080),
		Vector2i(2560, 1440),
		Vector2i(3440, 1440),
		Vector2i(3840, 2160),
	]
	for r in resolutions:
		opt.add_item("%d × %d" % [r.x, r.y])
	opt.set_meta("resolutions", resolutions)
	opt.item_selected.connect(func(idx: int):
		var r: Vector2i = resolutions[idx]
		SettingsManager.set_pending("graphics", "resolution_w", r.x)
		SettingsManager.set_pending("graphics", "resolution_h", r.y))
	row.add_child(opt)
	_widgets["graphics/resolution"] = opt

# ── Max FPS (special: 0 = unlimited) ──────────────────────────────────────────
func _add_fps_row(parent: VBoxContainer) -> void:
	var row := _new_row(parent, "Max FPS")
	var opt := OptionButton.new()
	opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	opt.add_theme_font_size_override("font_size", FONT_BODY)
	var values := [30, 60, 75, 90, 120, 144, 165, 240, 0]
	var labels := ["30", "60", "75", "90", "120", "144", "165", "240", "Unlimited"]
	for i in labels.size():
		opt.add_item(labels[i], i)
	opt.set_meta("values", values)
	opt.item_selected.connect(func(idx: int):
		SettingsManager.set_pending("graphics", "max_fps", values[idx]))
	row.add_child(opt)
	_widgets["graphics/max_fps"] = opt

# ── Slider (continuous numeric) ───────────────────────────────────────────────
func _add_slider_row(parent: VBoxContainer, category: String, key: String,
		label_text: String, min_v: float, max_v: float, step: float,
		format: String, percent: bool = false) -> void:
	var row := _new_row(parent, label_text)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step      = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 0)
	var readout := Label.new()
	readout.custom_minimum_size = Vector2(80, 0)
	readout.add_theme_font_size_override("font_size", FONT_BODY)
	readout.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	slider.value_changed.connect(func(v: float):
		SettingsManager.set_pending(category, key, v)
		readout.text = format % (v * 100.0 if percent else v))
	row.add_child(slider)
	row.add_child(readout)
	_widgets[category + "/" + key] = slider
	_widgets[category + "/" + key + "/readout"] = readout
	_widgets[category + "/" + key + "/format"] = format
	_widgets[category + "/" + key + "/percent"] = percent

# ── Audio dB slider (-60 dB silent .. 0 nominal .. +6 boost) ─────────────────
func _add_db_slider_row(parent: VBoxContainer, category: String, key: String,
		label_text: String) -> void:
	_add_slider_row(parent, category, key, label_text, -60.0, 6.0, 1.0, "%+.0f dB")

# ── Checkbox ──────────────────────────────────────────────────────────────────
func _add_check_row(parent: VBoxContainer, category: String, key: String,
		label_text: String) -> void:
	var row := _new_row(parent, label_text)
	var cb := CheckButton.new()
	cb.toggled.connect(func(v: bool):
		SettingsManager.set_pending(category, key, v))
	row.add_child(cb)
	_widgets[category + "/" + key] = cb

# ── HH:MM time row ────────────────────────────────────────────────────────────
## Two SpinBoxes (hour 0-23, minute 0-59). The pending value is a string
## "HH:MM" so it round-trips through the existing string-keyed settings save
## path. The hour/min widgets share one update lambda so editing either pushes
## the combined string back to SettingsManager.
func _add_time_row(parent: VBoxContainer, category: String, key: String,
		label_text: String) -> void:
	var row := _new_row(parent, label_text)
	var hour_box := SpinBox.new()
	hour_box.min_value = 0
	hour_box.max_value = 23
	hour_box.step = 1
	hour_box.custom_minimum_size = Vector2(70, 0)
	hour_box.add_theme_font_size_override("font_size", FONT_BODY)
	var colon := Label.new()
	colon.text = ":"
	colon.add_theme_font_size_override("font_size", FONT_BODY)
	var min_box := SpinBox.new()
	min_box.min_value = 0
	min_box.max_value = 59
	min_box.step = 1
	min_box.custom_minimum_size = Vector2(70, 0)
	min_box.add_theme_font_size_override("font_size", FONT_BODY)
	var push := func() -> void:
		var s : String = "%02d:%02d" % [int(hour_box.value), int(min_box.value)]
		SettingsManager.set_pending(category, key, s)
	hour_box.value_changed.connect(func(_v): push.call())
	min_box.value_changed.connect(func(_v): push.call())
	row.add_child(hour_box)
	row.add_child(colon)
	row.add_child(min_box)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)
	_widgets[category + "/" + key] = hour_box
	_widgets[category + "/" + key + "/min"] = min_box

# ── YYYY-MM-DD date row ───────────────────────────────────────────────────────
## Three SpinBoxes — year / month / day. Day max is 31 (the calendar math in
## ShiftClock handles 30-day / Feb edge cases by serial-day diff, so an
## "April 31" round-trips as May 1; we keep the UI simple). Default year is
## the current system year so a fresh boot lands on a sane window.
func _add_date_row(parent: VBoxContainer, category: String, key: String,
		label_text: String) -> void:
	var row := _new_row(parent, label_text)
	var today : Dictionary = Time.get_date_dict_from_system()
	var year_box := SpinBox.new()
	year_box.min_value = 1970
	year_box.max_value = 2099
	year_box.step = 1
	year_box.value = int(today.get("year", 2026))
	year_box.custom_minimum_size = Vector2(90, 0)
	year_box.add_theme_font_size_override("font_size", FONT_BODY)
	var dash1 := Label.new()
	dash1.text = "-"
	dash1.add_theme_font_size_override("font_size", FONT_BODY)
	var month_box := SpinBox.new()
	month_box.min_value = 1
	month_box.max_value = 12
	month_box.step = 1
	month_box.value = int(today.get("month", 1))
	month_box.custom_minimum_size = Vector2(70, 0)
	month_box.add_theme_font_size_override("font_size", FONT_BODY)
	var dash2 := Label.new()
	dash2.text = "-"
	dash2.add_theme_font_size_override("font_size", FONT_BODY)
	var day_box := SpinBox.new()
	day_box.min_value = 1
	day_box.max_value = 31
	day_box.step = 1
	day_box.value = int(today.get("day", 1))
	day_box.custom_minimum_size = Vector2(70, 0)
	day_box.add_theme_font_size_override("font_size", FONT_BODY)
	var clear_btn := Button.new()
	clear_btn.text = "Use today"
	clear_btn.add_theme_font_size_override("font_size", FONT_SMALL)
	var push := func() -> void:
		var s : String = "%04d-%02d-%02d" % [int(year_box.value), int(month_box.value), int(day_box.value)]
		SettingsManager.set_pending(category, key, s)
	var on_clear := func() -> void:
		# Empty string means "use today" — ShiftClock.apply_starting_settings
		# treats a blank starting_date as a 0-day delta from system date.
		SettingsManager.set_pending(category, key, "")
		var td : Dictionary = Time.get_date_dict_from_system()
		year_box.set_value_no_signal(int(td.get("year", 2026)))
		month_box.set_value_no_signal(int(td.get("month", 1)))
		day_box.set_value_no_signal(int(td.get("day", 1)))
	year_box.value_changed.connect(func(_v): push.call())
	month_box.value_changed.connect(func(_v): push.call())
	day_box.value_changed.connect(func(_v): push.call())
	clear_btn.pressed.connect(on_clear)
	row.add_child(year_box)
	row.add_child(dash1)
	row.add_child(month_box)
	row.add_child(dash2)
	row.add_child(day_box)
	row.add_child(clear_btn)
	_widgets[category + "/" + key] = year_box
	_widgets[category + "/" + key + "/month"] = month_box
	_widgets[category + "/" + key + "/day"] = day_box

# ── Keybind row ───────────────────────────────────────────────────────────────
func _add_keybind_row(parent: VBoxContainer, action: String) -> void:
	var label_text: String = SettingsManager.ACTION_LABELS.get(action, action)
	var row := _new_row(parent, label_text)
	var btn := Button.new()
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.add_theme_font_size_override("font_size", FONT_BODY)
	btn.set_meta("action", action)
	btn.pressed.connect(func(): _start_capture(action, btn))
	row.add_child(btn)
	_widgets["keybinds/" + action] = btn

# =============================================================================
# REFRESH WIDGETS FROM PENDING STATE
# =============================================================================
func _refresh_all_widgets() -> void:
	_refresh_category("graphics", SettingsManager.pending_graphics())
	_refresh_category("audio",    SettingsManager.pending_audio())
	_refresh_category("gameplay", SettingsManager.pending_gameplay())
	_refresh_resolution_widget()
	_refresh_keybind_widgets()

func _refresh_category(category: String, values: Dictionary) -> void:
	for key in values:
		var w_key := category + "/" + String(key)
		if not _widgets.has(w_key):
			continue
		var widget = _widgets[w_key]
		var v = values[key]
		if widget is HSlider:
			(widget as HSlider).set_value_no_signal(float(v))
			var readout = _widgets.get(w_key + "/readout", null)
			if readout:
				var fmt: String = _widgets.get(w_key + "/format", "%.2f")
				var pct: bool = _widgets.get(w_key + "/percent", false)
				readout.text = fmt % (v * 100.0 if pct else v)
		elif widget is CheckButton:
			(widget as CheckButton).set_pressed_no_signal(bool(v))
		elif widget is OptionButton:
			var opt := widget as OptionButton
			var vals: Array = opt.get_meta("values", [])
			for i in vals.size():
				if vals[i] == v:
					opt.select(i)
					break
		elif widget is SpinBox:
			# Time + date rows store the primary SpinBox under the category/key
			# slot and the secondary SpinBox(es) under "/min" "/month" "/day"
			# sub-slots. Parse the string value and populate each accordingly.
			var sv : String = String(v)
			var min_w := _widgets.get(w_key + "/min", null) as SpinBox
			if min_w != null:
				# HH:MM time row
				if sv.length() >= 4 and sv.find(":") != -1:
					var parts : PackedStringArray = sv.split(":")
					if parts.size() == 2:
						(widget as SpinBox).set_value_no_signal(float(int(parts[0])))
						min_w.set_value_no_signal(float(int(parts[1])))
			else:
				var month_w := _widgets.get(w_key + "/month", null) as SpinBox
				var day_w := _widgets.get(w_key + "/day", null) as SpinBox
				if month_w != null and day_w != null and sv != "":
					# YYYY-MM-DD date row
					var p2 : PackedStringArray = sv.split("-")
					if p2.size() == 3:
						(widget as SpinBox).set_value_no_signal(float(int(p2[0])))
						month_w.set_value_no_signal(float(int(p2[1])))
						day_w.set_value_no_signal(float(int(p2[2])))

func _refresh_resolution_widget() -> void:
	var opt := _widgets.get("graphics/resolution", null) as OptionButton
	if not opt:
		return
	var resolutions: Array = opt.get_meta("resolutions", [])
	var cur := Vector2i(
		SettingsManager.pending_graphics().get("resolution_w", 1920),
		SettingsManager.pending_graphics().get("resolution_h", 1080))
	for i in resolutions.size():
		if resolutions[i] == cur:
			opt.select(i)
			return
	# Not in list — append it
	opt.add_item("%d × %d" % [cur.x, cur.y])
	resolutions.append(cur)
	opt.set_meta("resolutions", resolutions)
	opt.select(resolutions.size() - 1)

func _refresh_keybind_widgets() -> void:
	for action in SettingsManager.ACTION_LABELS:
		var bound := _format_binding(SettingsManager.pending_keybinds().get(action, []))
		var btn := _widgets.get("keybinds/" + action, null) as Button
		if btn:
			btn.text = bound
		# Keep the read-only overview row in sync too
		var ov := _overview_value_labels.get(action, null) as Label
		if ov:
			ov.text = bound

func _format_binding(events: Array) -> String:
	if events.is_empty():
		return "—"
	var parts: Array[String] = []
	for ev in events:
		if ev is InputEventKey:
			var k := ev as InputEventKey
			var keycode: int = k.keycode if k.keycode != 0 else k.physical_keycode
			parts.append(OS.get_keycode_string(keycode))
		elif ev is InputEventMouseButton:
			parts.append("Mouse %d" % (ev as InputEventMouseButton).button_index)
		elif ev is InputEventJoypadButton:
			parts.append("Pad btn %d" % (ev as InputEventJoypadButton).button_index)
		elif ev is InputEventJoypadMotion:
			parts.append("Pad axis %d" % (ev as InputEventJoypadMotion).axis)
	return ", ".join(parts)

# =============================================================================
# KEY REBINDING — capture next input event
# =============================================================================
func _start_capture(action: String, btn: Button) -> void:
	_waiting_for_key_for = action
	_waiting_btn = btn
	btn.text = "[ press a key ]"

func _unhandled_input(event: InputEvent) -> void:
	# Capture-a-key mode takes priority
	if _waiting_for_key_for != "":
		# Escape cancels capture (using raw KEY_ESCAPE so it works even if the
		# user rebound ui_cancel to something else)
		if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE \
				and (event as InputEventKey).pressed:
			_cancel_capture()
			get_viewport().set_input_as_handled()
			return
		# Accept the first key / mouse / pad button press
		if (event is InputEventKey and (event as InputEventKey).pressed) \
				or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed) \
				or (event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed):
			_finalise_capture(event)
			get_viewport().set_input_as_handled()
		return

	# Not capturing — ui_cancel closes the menu (HUD has already deferred to us)
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()

func _cancel_capture() -> void:
	_waiting_for_key_for = ""
	if _waiting_btn:
		_waiting_btn.text = _format_binding(
			SettingsManager.pending_keybinds().get(_waiting_btn.get_meta("action"), []))
	_waiting_btn = null

func _finalise_capture(ev: InputEvent) -> void:
	# Strip echo flag and any held state to keep stored event minimal
	var clean := ev.duplicate() as InputEvent
	if clean is InputEventKey:
		(clean as InputEventKey).pressed = false
		(clean as InputEventKey).echo    = false
	SettingsManager.set_pending_keybind(_waiting_for_key_for, [clean])
	var bound := _format_binding([clean])
	_waiting_btn.text = bound
	# Mirror the new value in the read-only overview at the top of the tab
	var ov := _overview_value_labels.get(_waiting_for_key_for, null) as Label
	if ov:
		ov.text = bound
	_waiting_for_key_for = ""
	_waiting_btn = null

# =============================================================================
# FOOTER BUTTONS
# =============================================================================
func _on_apply() -> void:
	# Snapshot the PENDING Time & Date values BEFORE SettingsManager.apply()
	# promotes pending → current, so we can detect whether the operator
	# actually edited them (vs. clicking Apply with only graphics/audio
	# changes). The explicit ShiftClock.set_time_and_date() call below is the
	# end-to-end wire the operator requested: don't ONLY persist to disk for
	# next launch; act on the live ShiftClock right now.
	var pending_gp : Dictionary = SettingsManager.pending_gameplay()
	var t : String = String(pending_gp.get("starting_time", "")).strip_edges()
	var d : String = String(pending_gp.get("starting_date", "")).strip_edges()
	var current_gp : Dictionary = SettingsManager.gameplay()
	var cur_t : String = String(current_gp.get("starting_time", "")).strip_edges()
	var cur_d : String = String(current_gp.get("starting_date", "")).strip_edges()
	var time_changed : bool = (t != cur_t) or (d != cur_d)
	SettingsManager.apply()
	# Explicit ShiftClock wire — when the operator EDITED time/date, drive the
	# canonical setter directly so the chain (despawn at-post NPCs, reposition
	# cars, route arriving NPCs from the road, hand control to PreShiftSequence)
	# runs immediately.
	# Order matters: SettingsManager.apply() above has ALREADY fired
	# settings_applied which fires ShiftClock._on_settings_applied →
	# apply_starting_settings → set_time_and_date. That's the right behaviour
	# for stale-launch / reload-from-disk paths, and `_last_applied_*` was
	# primed inside apply_starting_settings so the chain doesn't loop. We
	# therefore RELY on that chain and DON'T double-fire here — the explicit
	# wire is preserved as a guard for the case where the autoload signal is
	# missed (e.g. SettingsManager temporarily disconnected mid-session).
	if time_changed and (t != "" or d != ""):
		var sc := _find_shift_clock()
		if sc != null and sc.has_method("set_time_and_date") \
				and sc.has_method("apply_starting_settings"):
			# Detect whether _on_settings_applied already ran the seek for us.
			# It updates last_applied_start_time/date to match current; if those
			# DON'T match the new t/d we just applied, the chain didn't run and
			# we need to call set_time_and_date ourselves.
			var last_t : String = String(sc.get("_last_applied_start_time")) \
					if "_last_applied_start_time" in sc else ""
			var last_d : String = String(sc.get("_last_applied_start_date")) \
					if "_last_applied_start_date" in sc else ""
			if last_t != t or last_d != d:
				sc.call("set_time_and_date", d, t)
	close()

## Locate the live ShiftClock instance. Lives under MainWorld at runtime; the
## settings menu is layered on top so we walk the scene tree to find it.
## Returns null cleanly when the menu is opened from the main menu (no shift
## in flight).
func _find_shift_clock() -> Node:
	var root := get_tree().root
	if root == null:
		return null
	return root.find_child("ShiftClock", true, false)

func _on_cancel() -> void:
	SettingsManager.cancel()
	close()

func _on_reset_current_tab() -> void:
	var idx := _tabs.current_tab
	match idx:
		0: SettingsManager.reset_category("graphics")
		1: SettingsManager.reset_category("audio")
		2: SettingsManager.reset_category("gameplay")
		3: SettingsManager.reset_category("keybinds")
	_refresh_all_widgets()
