extends CanvasLayer

class_name HUD

## Shift clock display + pause menu with Save & Quit.
## Owns the ESC key globally — PlayerController no longer handles it.
##
## Layout (built programmatically):
##   ┌──────────────┐   Top-left: dark pill showing HH:MM + amber progress bar.
##   │  07:23  ████ │
##   └──────────────┘
##
##   (on ESC) full-screen dim overlay + centred card with Resume / Save & Quit.

# ── Runtime references (wired in _connect_signals via call_deferred) ──────────
var shift_clock : ShiftClock
var main_world  : MainWorld

# ── UI nodes ──────────────────────────────────────────────────────────────────
var _time_label   : Label
var _progress_bar : ProgressBar
var _pause_overlay: Control   # full-screen dim + card; hidden by default
var _end_of_shift_overlay: Control # end of shift full-screen dim + card
var _settings_menu: CanvasLayer   # lazy-instantiated settings overlay
var _map_overlay  : MapOverlay    # top-down site map, toggled with M

# Walkie-talkie status (bottom-left): battery %, route (headset/speaker), volume.
var _walkie_panel  : PanelContainer
var _walkie_batt   : Label
var _walkie_route  : Label
var _walkie_vol    : Label
var _walkie_call   : Label      # last received call (fades)
var _walkie_call_t : float = 0.0

# Walkie message-picker overlay (#179 fix). U opens a small panel listing the
# canned PTT lines with numeric hotkeys; the operator chooses one with 1..9 or
# arrow + Enter, and the second U press (or Esc) closes it without sending.
# The overlay is HUD-scoped (top-right) so it doesn't interfere with the
# bottom-left walkie status panel.
var _walkie_menu_panel : PanelContainer = null
var _walkie_menu_vbox  : VBoxContainer  = null
var _walkie_menu_rows  : Array          = []      # Array[Label]
var _walkie_menu_open  : bool           = false
var _walkie_menu_sel   : int            = 0

# Crew / rota panel (top-left, beneath the clock) — Wave 4 shift context
var crew_manager   : CrewManager
var _crew_panel    : PanelContainer
var _crew_assign_panel : CanvasLayer = null   # interactive assignment overlay (Numpad ".")
var _calendar_label: Label
var _roster_label  : Label
var _crew_accum    : float = 0.0   # throttles the ~2 Hz roster refresh

# Line power banner (#171, top-right) — the material line's PLC power-up state so
# the staged downstream-first start-up reads as "OPSTARTEN 67%", not "broken".
var line_flow      : Node = null
var _line_panel    : PanelContainer
var _line_label    : Label

# Interaction prompt (bottom-centre "[E] ..." hint)
var _prompt_panel  : PanelContainer
var _prompt_label  : Label
var _prompt_source : Node = null   # most recent emitter — clears when it hides

# Vehicle HUD (bottom-right cluster, shown only while in a vehicle)
var _vehicle_panel  : PanelContainer
var _vehicle_speed  : Label
var _vehicle_fuel_lbl: Label
var _vehicle_fuel_bar: ProgressBar
var _vehicle_adblue_row: HBoxContainer   # diesel only — DEF / AdBlue level
var _vehicle_adblue_bar: ProgressBar
var _vehicle_hb_lbl : Label
# Clamp force readout — only visible while in a BaleClamp. Shows the locked-in
# clamp force, ramps live while the operator holds B, and turns amber once the
# force passes the carried bale's wire_compliance (= wires are bulging = the
# concrete-scissors action will succeed).
var _vehicle_clamp_row : HBoxContainer
var _vehicle_clamp_lbl : Label
var _vehicle_clamp_bar : ProgressBar
var _vehicle_clamp_hint: Label
var _bound_vehicle  : Node = null   # set on operator_entered_vehicle

# Hotbar (bottom-centre, 4 boxes for inventory slots) + scanner banner
var _hotbar_row   : HBoxContainer
var _hotbar_boxes : Array = []     # Array[PanelContainer]
var _hotbar_labels: Array = []     # Array[Label]    — slot name ("scissors" / "—")
var _scanner_banner_panel : PanelContainer
var _scanner_banner_label : Label
var _scanner_banner_fade  : float = 0.0   # seconds remaining

# "✓ Saved" toast (top-right, under the line banner) — confirms every save
# (autosave tick, pause-card Save, Save & Quit) actually reached disk. Before
# this, saving only print()ed to console — invisible in multi-hour shifts.
# #Q1 — also shows the save name + wall-clock time so the operator knows
# WHICH file is on disk and WHEN it landed, without opening the menu.
var _save_toast_panel : PanelContainer
var _save_toast_label : Label   # #Q1 — text updated at each save with name+time
var _save_toast_fade  : float = 0.0   # seconds remaining

# =============================================================================
func _ready() -> void:
	layer = 10                       # above everything 3-D
	_ensure_map_action()
	_build_time_display()
	_build_crew_panel()
	_build_line_panel()
	_build_map_overlay()
	_build_walkie_panel()
	_build_walkie_menu()
	_build_pause_menu()
	_build_end_of_shift_overlay()
	_build_interaction_prompt()
	_build_vehicle_hud()
	_build_hotbar()
	_build_scanner_banner()
	_build_save_toast()
	_build_crosshair()
	call_deferred("_connect_signals")

## A small fixed dot at the screen centre — an aiming reference for scanning, cutting
## wires, and pointing tools. (#7)
func _build_crosshair() -> void:
	var dot := ColorRect.new()
	dot.name = "Crosshair"
	dot.color = Color(1.0, 1.0, 1.0, 0.85)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.custom_minimum_size = Vector2(5, 5)
	dot.size = Vector2(5, 5)
	dot.position = Vector2(-2.5, -2.5)   # centre the 5x5 dot on the anchor point
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot)

# Wire up after the whole scene tree has finished its _ready() pass.
func _connect_signals() -> void:
	# current_scene is MainWorld; root.get_child(0) would be an autoload.
	main_world = get_tree().current_scene as MainWorld
	if main_world:
		shift_clock = main_world.shift_clock
		crew_manager = main_world.crew_manager
		line_flow = main_world.line_flow
		if _map_overlay:
			_map_overlay.main_world = main_world
	# Inventory signals → keep the hotbar visuals in sync.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		if inv.has_signal("active_changed"):
			inv.active_changed.connect(_on_inventory_active_changed)
		if inv.has_signal("slots_changed"):
			inv.slots_changed.connect(_on_inventory_slots_changed)
		_refresh_hotbar()
	# Scanner banner pop-in
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("scanner_banner"):
		bus.scanner_banner.connect(_on_scanner_banner)
		_refresh_crew_panel()        # seed the roster immediately
	# "✓ Saved" toast — SaveCoordinator emits after every flush (autosave + manual).
	if bus and bus.has_signal("autosave_completed"):
		bus.autosave_completed.connect(_on_autosave_completed)
	if shift_clock:
		shift_clock.time_updated.connect(_on_time_updated)
		shift_clock.shift_ended.connect(_on_shift_ended)
		_on_time_updated(shift_clock.get_time_string())  # seed the display now
	elif main_world == null:
		# Expected outside MainWorld (the gauntlet bench, probe scenes): there is
		# no shift there, so a warning just cries wolf every boot.
		print("[HUD] no MainWorld in this scene — clock/progress hidden (expected on the bench)")
	else:
		push_warning("[HUD] ShiftClock not found — time display will be blank")

	_connect_walkie()

	# Global event hooks
	EventBus.interaction_prompt_show.connect(_on_prompt_show)
	EventBus.interaction_prompt_hide.connect(_on_prompt_hide)
	EventBus.operator_entered_vehicle.connect(_on_operator_entered_vehicle)
	EventBus.operator_exited_vehicle.connect(_on_operator_exited_vehicle)

	# Settings — opacity / prompt visibility / hints / units. Apply now and on every change.
	_refresh_hud_settings()
	var sm := get_node_or_null("/root/SettingsManager")
	if sm and sm.has_signal("settings_applied"):
		sm.settings_applied.connect(_refresh_hud_settings)

# =============================================================================
# SETTINGS WIRING — Settings → Gameplay → HUD-related toggles
# =============================================================================
func _refresh_hud_settings() -> void:
	if not has_node("/root/SettingsManager"): return
	var g : Dictionary = SettingsManager.gameplay()
	# HUD opacity — applied to every top-level Control child of this CanvasLayer.
	var a := clampf(float(g.get("hud_opacity", 1.0)), 0.1, 1.0)
	for c in get_children():
		if c is Control:
			c.modulate.a = a
	# Interaction prompt visibility
	if _prompt_panel:
		var allow := bool(g.get("show_interaction_prompts", true))
		# If the user turned prompts OFF, force-hide regardless of pending event.
		# Turning back ON does not retroactively re-show a dismissed prompt;
		# the next interaction_prompt_show event will appear normally.
		if not allow and _prompt_panel.visible:
			_prompt_panel.visible = false
	# Tutorial hints + units — keep / refresh the hint label.
	_refresh_tutorial_hint()

func _hud_units_label() -> String:
	# Read by any HUD widget that wants to show a unit. For now used only by
	# _refresh_tutorial_hint; future displays (speed, distance, mass) should
	# also consult this so "metric / imperial" actually swings them.
	if not has_node("/root/SettingsManager"): return "m"
	return "ft" if String(SettingsManager.gameplay().get("units", "metric")) == "imperial" else "m"

var _hint_label : Label = null
func _refresh_tutorial_hint() -> void:
	# Renamed from `show` — that shadowed CanvasLayer.show() and triggered the
	# SHADOWED_VARIABLE_BASE_CLASS warning.
	var show_hint := true
	if has_node("/root/SettingsManager"):
		show_hint = bool(SettingsManager.gameplay().get("tutorial_hints", true))
	# Lazily build the hint label so we don't touch the scene tree until needed.
	if show_hint and _hint_label == null:
		_hint_label = Label.new()
		_hint_label.name = "TutorialHint"
		_hint_label.text = "Press P for menu  ·  E to interact  ·  units: %s" % _hud_units_label()
		_hint_label.add_theme_font_size_override("font_size", 13)
		_hint_label.modulate = Color(1, 1, 1, 0.7)
		_hint_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
		_hint_label.offset_left = 12
		_hint_label.offset_bottom = -10
		_hint_label.offset_top = -28
		add_child(_hint_label)
	elif show_hint and _hint_label:
		_hint_label.text = "Press P for menu  ·  E to interact  ·  units: %s" % _hud_units_label()
		_hint_label.visible = true
	elif (not show_hint) and _hint_label:
		_hint_label.visible = false

## In-hand control hint for the currently-held tool (leaf blower / hose nozzle).
## Updated only on the Inventory active-tool-changed signal, never per-frame.
##
## Strategy: run the normal _refresh_tutorial_hint() first so the label is built,
## shown/hidden, and seeded with the default text exactly as before — honouring the
## "tutorial_hints" setting. Then, ONLY when the active tool is one we have a hint
## for AND the label is actually visible (hints enabled), overwrite its text. When
## the active tool is neither (or there is none) the label keeps the default text,
## so the non-tool hint behaviour is completely unchanged.
func _refresh_inhand_hint() -> void:
	_refresh_tutorial_hint()
	if _hint_label == null or not _hint_label.visible:
		return   # hints disabled or no label — leave the default path untouched
	var txt := _inhand_hint_text()
	if txt != "":
		_hint_label.text = txt

## Returns the in-hand control hint for the active held tool, or "" if the active
## tool is neither the leaf blower nor a hose nozzle (or there is no active tool).
## All member access is guarded with has_method / `in` so it stays safe if a tool
## drops a member.
func _inhand_hint_text() -> String:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("active"):
		return ""
	var tool : Node = inv.call("active")
	if tool == null:
		return ""
	# tool_id is a const String on each tool; fall back to type check below.
	var tid := ""
	if "tool_id" in tool:
		tid = String(tool.get("tool_id"))
	# ── Leaf blower ──────────────────────────────────────────────────────────
	if tid == "leafblower" or tool is LeafBlower:
		# When the engine isn't primed, steer the operator to the prime sequence.
		if ("_needs_prime" in tool) and bool(tool.get("_needs_prime")):
			return "Leaf blower NOT primed  —  right-click 3x to prime, then hold LMB to blow"
		return "Leaf blower  —  LMB: blow  ·  RMB x3: prime engine  ·  E at jerry can: refuel"
	# ── Hose nozzle ──────────────────────────────────────────────────────────
	if tid == "hose_nozzle" or tid == "hose" or tool is HoseNozzle:
		return "Hose  —  LMB: tip valve (spray)  ·  E at reel: base valve  ·  F: reel in  ·  Q: drop"
	return ""

# =============================================================================
# BUILD UI
# =============================================================================
func _build_time_display() -> void:
	# ── Outer pill ────────────────────────────────────────────────────────────
	var panel := PanelContainer.new()
	panel.name = "TimePanel"
	panel.anchor_left   = 0.0
	panel.anchor_top    = 0.0
	panel.anchor_right  = 0.0
	panel.anchor_bottom = 0.0
	panel.offset_left   = 12.0
	panel.offset_top    = 12.0
	panel.offset_right  = 118.0
	panel.offset_bottom = 62.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.72)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 8.0
	style.content_margin_right  = 8.0
	style.content_margin_top    = 5.0
	style.content_margin_bottom = 5.0
	panel.add_theme_stylebox_override("panel", style)
	add_child(panel)

	# ── Inner layout ──────────────────────────────────────────────────────────
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	panel.add_child(vbox)

	_time_label = Label.new()
	_time_label.text = "07:00"
	_time_label.add_theme_font_size_override("font_size", 26)
	_time_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.68, 1.0))
	_time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_time_label)

	_progress_bar = ProgressBar.new()
	_progress_bar.min_value = 0.0
	_progress_bar.max_value = 100.0
	_progress_bar.value     = 0.0
	_progress_bar.show_percentage = false
	_progress_bar.custom_minimum_size = Vector2(0.0, 5.0)

	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.18, 0.18, 0.18, 1.0)
	_progress_bar.add_theme_stylebox_override("background", bar_bg)

	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.82, 0.52, 0.12, 1.0)   # amber
	_progress_bar.add_theme_stylebox_override("fill", bar_fill)

	vbox.add_child(_progress_bar)

# =============================================================================
# CREW / ROTA PANEL (top-left under the clock — Wave 4 shift context)
# =============================================================================
## A persistent shift-context panel: the 2-2-2-4 calendar line (which dag / dienst
## / ploeg) plus a live roster of every crew member and what they're doing right
## now (at post, walking to a jam, servicing, on break). Refreshed ~2× a second.
func _build_crew_panel() -> void:
	_crew_panel = PanelContainer.new()
	_crew_panel.name = "CrewPanel"
	_crew_panel.anchor_left   = 0.0
	_crew_panel.anchor_top    = 0.0
	_crew_panel.anchor_right  = 0.0
	_crew_panel.anchor_bottom = 0.0
	_crew_panel.offset_left   = 12.0
	_crew_panel.offset_top    = 70.0     # just below the time pill (ends at ~62)
	_crew_panel.offset_right  = 330.0
	_crew_panel.offset_bottom = 300.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.66)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 10.0
	style.content_margin_right  = 10.0
	style.content_margin_top    = 7.0
	style.content_margin_bottom = 7.0
	_crew_panel.add_theme_stylebox_override("panel", style)
	add_child(_crew_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	_crew_panel.add_child(vbox)

	# Calendar header, e.g. "Dag 1 · Vroege dienst · Ploeg A"
	_calendar_label = Label.new()
	_calendar_label.text = "Dag 1 · Vroege dienst · Ploeg A"
	_calendar_label.add_theme_font_size_override("font_size", 14)
	_calendar_label.add_theme_color_override("font_color", Color(0.62, 0.83, 1.0, 1.0))
	vbox.add_child(_calendar_label)

	vbox.add_child(HSeparator.new())

	# Live crew roster (one line per worker) + break/fault footer.
	_roster_label = Label.new()
	_roster_label.text = ""
	_roster_label.add_theme_font_size_override("font_size", 12)
	_roster_label.add_theme_color_override("font_color", Color(0.88, 0.88, 0.86, 1.0))
	vbox.add_child(_roster_label)

## Pull the latest calendar + roster strings from ShiftClock / CrewManager.
func _refresh_crew_panel() -> void:
	if _calendar_label and shift_clock:
		_calendar_label.text = shift_clock.calendar_string()
	if _roster_label == null:
		return
	if crew_manager == null:
		_roster_label.text = ""        # crew skipped (no NPCs/line) — show clock only
		return
	var lines := crew_manager.roster_lines()
	var footer := "—  Pauze %d · Storingen %d" % \
		[crew_manager.count_on_break(), crew_manager.active_faults()]
	_roster_label.text = "\n".join(lines) + "\n" + footer

# =============================================================================
# LINE POWER BANNER (#171, top-right) — PLC power-up + granulaat readout
# =============================================================================
func _build_line_panel() -> void:
	_line_panel = PanelContainer.new()
	_line_panel.name = "LinePanel"
	_line_panel.anchor_left = 1.0; _line_panel.anchor_right = 1.0
	_line_panel.anchor_top = 0.0;  _line_panel.anchor_bottom = 0.0
	_line_panel.offset_left = -290.0; _line_panel.offset_right = -12.0
	_line_panel.offset_top = 12.0;    _line_panel.offset_bottom = 44.0
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.05, 0.74)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10.0; style.content_margin_right = 10.0
	style.content_margin_top = 5.0;   style.content_margin_bottom = 5.0
	_line_panel.add_theme_stylebox_override("panel", style)
	add_child(_line_panel)
	_line_label = Label.new()
	_line_label.add_theme_font_size_override("font_size", 13)
	_line_label.text = "LIJN  —"
	_line_panel.add_child(_line_label)
	_line_panel.visible = false

## Pull the material line's PLC state + granulaat tally and paint the banner.
func _refresh_line_panel() -> void:
	if _line_panel == null:
		return
	if line_flow == null or not is_instance_valid(line_flow):
		_line_panel.visible = false
		return
	_line_panel.visible = true
	var frac : float = float(line_flow.call("line_powered_fraction"))
	var starting : bool = bool(line_flow.call("is_line_starting"))
	var pct := int(round(frac * 100.0))
	var state : String
	var col : Color
	if frac <= 0.001:
		state = "UIT";                  col = Color(0.70, 0.40, 0.40)
	elif starting or frac < 0.999:
		state = "OPSTARTEN %d%%" % pct;  col = Color(0.95, 0.78, 0.30)
	else:
		state = "DRAAIT";               col = Color(0.35, 0.85, 0.45)
	var gran : float = float(line_flow.get("gran_mass"))
	var amps : float = float(line_flow.call("live_line_amps"))
	var line_name : String = "LIJN"
	if line_flow.has_method("active_line_name"):
		var an : String = String(line_flow.call("active_line_name"))
		if an != "":
			line_name = an
	_line_label.text = "%s  ·  %s   ·   %.0f A   ·   gran %.0f kg" % [line_name, state, amps, gran]
	_line_label.add_theme_color_override("font_color", col)

# =============================================================================
# SITE MAP (full-screen top-down overlay, toggled with M)
# =============================================================================
func _build_map_overlay() -> void:
	_map_overlay = MapOverlay.new()
	_map_overlay.name = "MapOverlay"
	add_child(_map_overlay)

# =============================================================================
# WALKIE-TALKIE PANEL (bottom-left) — battery / route / volume + incoming calls
# =============================================================================
func _build_walkie_panel() -> void:
	_walkie_panel = PanelContainer.new()
	_walkie_panel.name = "WalkiePanel"
	_walkie_panel.anchor_left = 0.0
	_walkie_panel.anchor_top = 1.0
	_walkie_panel.anchor_right = 0.0
	_walkie_panel.anchor_bottom = 1.0
	_walkie_panel.offset_left = 12.0
	_walkie_panel.offset_right = 250.0
	_walkie_panel.offset_top = -104.0
	_walkie_panel.offset_bottom = -12.0

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.05, 0.74)
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 6.0
	style.content_margin_bottom = 6.0
	_walkie_panel.add_theme_stylebox_override("panel", style)
	add_child(_walkie_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_walkie_panel.add_child(vbox)

	var title := Label.new()
	title.text = "PORTOFOON"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95, 1.0))
	vbox.add_child(title)

	_walkie_batt = Label.new()
	_walkie_batt.add_theme_font_size_override("font_size", 14)
	vbox.add_child(_walkie_batt)

	_walkie_route = Label.new()
	_walkie_route.add_theme_font_size_override("font_size", 12)
	_walkie_route.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82, 1.0))
	vbox.add_child(_walkie_route)

	_walkie_vol = Label.new()
	_walkie_vol.add_theme_font_size_override("font_size", 12)
	_walkie_vol.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82, 1.0))
	vbox.add_child(_walkie_vol)

	_walkie_call = Label.new()
	_walkie_call.add_theme_font_size_override("font_size", 11)
	_walkie_call.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45, 1.0))
	_walkie_call.text = ""
	vbox.add_child(_walkie_call)

	_refresh_walkie()

## Pull current walkie state and paint the panel.
func _refresh_walkie() -> void:
	var w := get_node_or_null("/root/Walkie")
	if w == null:
		return
	if _walkie_batt:
		var pct: int = w.battery_percent()
		var alive: bool = w.battery_alive()
		_walkie_batt.text = "Accu  %d%%" % pct
		var col := Color(0.35, 0.8, 0.3)
		if not alive:       col = Color(0.85, 0.2, 0.15)
		elif pct < 15:      col = Color(0.9, 0.5, 0.1)
		_walkie_batt.add_theme_color_override("font_color", col)
	if _walkie_route:
		_walkie_route.text = "Route  %s" % ("oortje" if bool(w.get("headset_on")) else "luidspreker")
	if _walkie_vol:
		var v := float(w.get("volume"))
		var bars := int(round(v * 10.0))
		_walkie_vol.text = "Vol    [%s%s]" % ["█".repeat(bars), "·".repeat(10 - bars)]

func _connect_walkie() -> void:
	var w := get_node_or_null("/root/Walkie")
	if w == null:
		return
	if w.has_signal("battery_changed"):
		w.battery_changed.connect(func(_p): _refresh_walkie())
	if w.has_signal("headset_changed"):
		w.headset_changed.connect(func(_h): _refresh_walkie())
	if w.has_signal("volume_changed"):
		w.volume_changed.connect(func(_v): _refresh_walkie())
	if w.has_signal("call_received"):
		w.call_received.connect(_on_walkie_call)
	# PTT: HUD owns the visible "you said X" echo and the input → Walkie.transmit
	# routing lives in HUD._input below.
	if w.has_signal("transmit_sent"):
		w.transmit_sent.connect(_on_walkie_transmit)
	_refresh_walkie()

func _on_walkie_call(from_name: String, text: String, heard: bool) -> void:
	if _walkie_call == null:
		return
	if heard:
		_walkie_call.text = "📻 %s" % text
		_walkie_call.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45, 1.0))
	else:
		_walkie_call.text = "✕ gemist gesprek (%s)" % from_name
		_walkie_call.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 1.0))
	_walkie_call_t = 6.0

## Player's own PTT key-up gets echoed locally so they see what went out. Cyan
## tint distinguishes "you" from incoming amber.
func _on_walkie_transmit(text: String, heard: bool) -> void:
	if _walkie_call == null:
		return
	if heard:
		_walkie_call.text = "▶  you: %s" % text
		_walkie_call.add_theme_color_override("font_color", Color(0.55, 0.85, 0.95, 1.0))
	else:
		_walkie_call.text = "✕ TX failed — radio is dead"
		_walkie_call.add_theme_color_override("font_color", Color(0.7, 0.4, 0.4, 1.0))
	_walkie_call_t = 4.0

# =============================================================================
# WALKIE MESSAGE PICKER (#179) — top-right panel populated from Walkie.PTT_LINES
# =============================================================================
## Build a hidden panel listing the canned PTT lines with numeric hotkeys (1..N).
## Stays hidden until the operator presses U; selection is highlighted live.
func _build_walkie_menu() -> void:
	var w := get_node_or_null("/root/Walkie")
	if w == null:
		return
	var lines : Array = []
	# PTT_LINES is a typed Array[String] constant on the Walkie autoload.
	var raw = w.get("PTT_LINES")
	if raw is Array:
		lines = raw
	if lines.is_empty():
		return

	_walkie_menu_panel = PanelContainer.new()
	_walkie_menu_panel.name = "WalkieMenu"
	# Top-right anchor (clear of bottom-left walkie status + map button).
	_walkie_menu_panel.anchor_left = 1.0
	_walkie_menu_panel.anchor_right = 1.0
	_walkie_menu_panel.anchor_top = 0.0
	_walkie_menu_panel.anchor_bottom = 0.0
	_walkie_menu_panel.offset_left = -300.0
	_walkie_menu_panel.offset_right = -12.0
	_walkie_menu_panel.offset_top = 60.0
	_walkie_menu_panel.offset_bottom = 60.0
	_walkie_menu_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.05, 0.86)
	style.border_color = Color(0.55, 0.78, 0.95, 0.85)
	style.border_width_left = 1
	style.border_width_right = 1
	style.border_width_top = 1
	style.border_width_bottom = 1
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left = 10.0
	style.content_margin_right = 10.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 8.0
	_walkie_menu_panel.add_theme_stylebox_override("panel", style)
	add_child(_walkie_menu_panel)

	_walkie_menu_vbox = VBoxContainer.new()
	_walkie_menu_vbox.add_theme_constant_override("separation", 2)
	_walkie_menu_panel.add_child(_walkie_menu_vbox)

	var title := Label.new()
	title.text = "PORTOFOON — kies bericht"
	title.add_theme_font_size_override("font_size", 11)
	title.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95, 1.0))
	_walkie_menu_vbox.add_child(title)

	_walkie_menu_rows.clear()
	for i in range(lines.size()):
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 13)
		_walkie_menu_vbox.add_child(row)
		_walkie_menu_rows.append(row)

	var footer := Label.new()
	footer.text = "1-%d / ↑↓+Enter to send · U or Esc to close" % lines.size()
	footer.add_theme_font_size_override("font_size", 10)
	footer.add_theme_color_override("font_color", Color(0.7, 0.7, 0.65, 0.9))
	_walkie_menu_vbox.add_child(footer)

	_refresh_walkie_menu()

## Repaint the row labels — bold + highlight the currently selected line.
func _refresh_walkie_menu() -> void:
	var w := get_node_or_null("/root/Walkie")
	if w == null or _walkie_menu_rows.is_empty():
		return
	var lines : Array = []
	var raw = w.get("PTT_LINES")
	if raw is Array:
		lines = raw
	for i in range(_walkie_menu_rows.size()):
		var row : Label = _walkie_menu_rows[i]
		if i >= lines.size():
			row.text = ""
			continue
		var prefix : String = "▶ " if i == _walkie_menu_sel else "  "
		row.text = "%s%d. %s" % [prefix, i + 1, String(lines[i])]
		if i == _walkie_menu_sel:
			row.add_theme_color_override("font_color", Color(1.0, 0.95, 0.55, 1.0))
		else:
			row.add_theme_color_override("font_color", Color(0.85, 0.85, 0.82, 1.0))

func _open_walkie_menu() -> void:
	if _walkie_menu_panel == null:
		_build_walkie_menu()
	if _walkie_menu_panel == null:
		return
	_walkie_menu_open = true
	_walkie_menu_sel = 0
	_walkie_menu_panel.visible = true
	_refresh_walkie_menu()

func _close_walkie_menu() -> void:
	_walkie_menu_open = false
	if _walkie_menu_panel:
		_walkie_menu_panel.visible = false

## Send the currently selected canned line and close the menu.
func _send_walkie_menu_selection() -> void:
	var w := get_node_or_null("/root/Walkie")
	if w != null and w.has_method("transmit_line"):
		w.call("transmit_line", _walkie_menu_sel)
	_close_walkie_menu()

## Guarantee newly-added actions exist at runtime. When an action is added to
## project.godot while the editor is already open, the running game keeps the old
## in-memory InputMap and the new action silently does nothing — so we register
## any missing ones here as a fallback. Harmless if the project already defines them.
func _ensure_map_action() -> void:
	# action name -> the physical keycode it should be bound to.
	var fallbacks := {
		"map_toggle":      KEY_M,
		"crouch_toggle":   KEY_CTRL,
		"prone_toggle":    KEY_Z,
		"walkie_headset":  KEY_J,
		"walkie_vol_down": KEY_COMMA,
		"walkie_vol_up":   KEY_PERIOD,
		"walkie_ptt":      KEY_U,    # opens the canned-message picker (#179 fix).
		"crew_panel":      KEY_KP_PERIOD,   # Numpad "." — open the crew assignment panel
		"crew_start_line": KEY_INSERT,      # Insert — deploy crew to start Line 1
		# Was V, but V = forklift_forks_widen (clamp release) in the cab, so
		# releasing the clamp also keyed the radio. Moved to U (unused) so the
		# two never double-fire. Operators can still talk while driving.
	}
	# tool_use is on the LEFT MOUSE BUTTON — register separately because the
	# fallback dict is keyboard-only.
	if not InputMap.has_action("tool_use"):
		InputMap.add_action("tool_use")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("tool_use", mb)
	for action in fallbacks:
		var key: int = fallbacks[action]
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var has_key := false
		for ev in InputMap.action_get_events(action):
			if ev is InputEventKey and (ev as InputEventKey).keycode == key:
				has_key = true
				break
		if not has_key:
			var k := InputEventKey.new()
			k.keycode = key as Key
			InputMap.action_add_event(action, k)


func _build_end_of_shift_overlay() -> void:
	_end_of_shift_overlay = Control.new()
	_end_of_shift_overlay.name = "EndOfShiftOverlay"
	_end_of_shift_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_of_shift_overlay.visible = false
	add_child(_end_of_shift_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_end_of_shift_overlay.add_child(dim)

	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.07, 0.07, 0.96)
	ps.corner_radius_top_left     = 8
	ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8
	ps.corner_radius_bottom_right = 8
	ps.content_margin_left   = 30.0
	ps.content_margin_right  = 30.0
	ps.content_margin_top    = 24.0
	ps.content_margin_bottom = 24.0
	card.add_theme_stylebox_override("panel", ps)
	_end_of_shift_overlay.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.text = "SHIFT ENDED"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.60, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var next_shift_btn := Button.new()
	next_shift_btn.text = "Start Next Shift"
	next_shift_btn.custom_minimum_size = Vector2(164.0, 36.0)
	next_shift_btn.pressed.connect(_on_next_shift_pressed)
	vbox.add_child(next_shift_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Save && Quit"
	quit_btn.custom_minimum_size = Vector2(164.0, 36.0)
	quit_btn.pressed.connect(_on_save_quit_pressed)
	vbox.add_child(quit_btn)

func _build_pause_menu() -> void:
	# ── Full-screen dim + centred card ────────────────────────────────────────
	_pause_overlay = Control.new()
	_pause_overlay.name = "PauseOverlay"
	_pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_pause_overlay.visible = false
	add_child(_pause_overlay)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	_pause_overlay.add_child(dim)

	# Card
	var card := PanelContainer.new()
	card.set_anchors_preset(Control.PRESET_CENTER)

	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.07, 0.07, 0.96)
	ps.corner_radius_top_left     = 8
	ps.corner_radius_top_right    = 8
	ps.corner_radius_bottom_left  = 8
	ps.corner_radius_bottom_right = 8
	ps.content_margin_left   = 30.0
	ps.content_margin_right  = 30.0
	ps.content_margin_top    = 24.0
	ps.content_margin_bottom = 24.0
	card.add_theme_stylebox_override("panel", ps)
	_pause_overlay.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	var title := Label.new()
	title.text = "SHIFT PAUSED"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.60, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	resume_btn.custom_minimum_size = Vector2(164.0, 36.0)
	resume_btn.pressed.connect(_on_resume_pressed)
	vbox.add_child(resume_btn)

	var settings_btn := Button.new()
	settings_btn.text = "Settings"
	settings_btn.custom_minimum_size = Vector2(164.0, 36.0)
	settings_btn.pressed.connect(_on_settings_pressed)
	vbox.add_child(settings_btn)

	# Manual save without quitting — before this the only mid-shift saves were
	# the 60 s autosave and the undiscoverable F5 freecam_save.
	var save_btn := Button.new()
	save_btn.text = "Save"
	save_btn.custom_minimum_size = Vector2(164.0, 36.0)
	save_btn.pressed.connect(_on_save_pressed)
	vbox.add_child(save_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Save & Quit"
	quit_btn.custom_minimum_size = Vector2(164.0, 36.0)
	quit_btn.pressed.connect(_on_save_quit_pressed)
	vbox.add_child(quit_btn)

# =============================================================================
# INTERACTION PROMPT (bottom-centre — "[E] Enter forklift" etc.)
# =============================================================================
func _build_interaction_prompt() -> void:
	_prompt_panel = PanelContainer.new()
	_prompt_panel.name = "InteractionPrompt"
	# Bottom-centre anchor
	_prompt_panel.anchor_left   = 0.5
	_prompt_panel.anchor_top    = 1.0
	_prompt_panel.anchor_right  = 0.5
	_prompt_panel.anchor_bottom = 1.0
	# Centred horizontally + offset up from bottom edge
	_prompt_panel.offset_left   = -180.0
	_prompt_panel.offset_right  =  180.0
	_prompt_panel.offset_top    = -120.0
	_prompt_panel.offset_bottom = -76.0
	_prompt_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.78)
	style.corner_radius_top_left     = 5
	style.corner_radius_top_right    = 5
	style.corner_radius_bottom_left  = 5
	style.corner_radius_bottom_right = 5
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	_prompt_panel.add_theme_stylebox_override("panel", style)
	add_child(_prompt_panel)

	_prompt_label = Label.new()
	_prompt_label.text = ""
	_prompt_label.add_theme_font_size_override("font_size", 16)
	_prompt_label.add_theme_color_override("font_color", Color(1.0, 0.93, 0.72, 1))
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_panel.add_child(_prompt_label)

func _on_prompt_show(source: Node, prompt: String, show_key_hint: bool = true) -> void:
	_prompt_source = source
	_prompt_label.text = ("[E]  %s" % prompt) if show_key_hint else prompt
	# Settings → Gameplay → "Show interaction prompts": if off, swallow the show.
	var allow := true
	if has_node("/root/SettingsManager"):
		allow = bool(SettingsManager.gameplay().get("show_interaction_prompts", true))
	_prompt_panel.visible = allow

func _on_prompt_hide(source: Node) -> void:
	# Only clear if the source that hid is the one currently showing —
	# protects against out-of-order enter/exit events between overlapping zones
	if source == _prompt_source:
		_prompt_panel.visible = false
		_prompt_source = null
		_prompt_label.text = ""

# =============================================================================
# VEHICLE HUD (bottom-right — speed / fuel / handbrake; visible only in cab)
# =============================================================================
func _build_vehicle_hud() -> void:
	_vehicle_panel = PanelContainer.new()
	_vehicle_panel.name = "VehicleHUD"
	# Bottom-right anchor
	_vehicle_panel.anchor_left   = 1.0
	_vehicle_panel.anchor_top    = 1.0
	_vehicle_panel.anchor_right  = 1.0
	_vehicle_panel.anchor_bottom = 1.0
	_vehicle_panel.offset_left   = -260.0
	_vehicle_panel.offset_right  = -16.0
	_vehicle_panel.offset_top    = -130.0
	_vehicle_panel.offset_bottom = -16.0
	_vehicle_panel.visible = false

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.05, 0.05, 0.78)
	style.corner_radius_top_left     = 6
	style.corner_radius_top_right    = 6
	style.corner_radius_bottom_left  = 6
	style.corner_radius_bottom_right = 6
	style.content_margin_left   = 12.0
	style.content_margin_right  = 12.0
	style.content_margin_top    = 10.0
	style.content_margin_bottom = 10.0
	_vehicle_panel.add_theme_stylebox_override("panel", style)
	add_child(_vehicle_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_vehicle_panel.add_child(vbox)

	# Speed
	_vehicle_speed = Label.new()
	_vehicle_speed.text = "0.0 km/h"
	_vehicle_speed.add_theme_font_size_override("font_size", 22)
	_vehicle_speed.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7, 1))
	_vehicle_speed.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_vehicle_speed)

	# Fuel row: label + bar
	var fuel_row := HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 8)
	vbox.add_child(fuel_row)

	_vehicle_fuel_lbl = Label.new()
	_vehicle_fuel_lbl.text = "FUEL"
	_vehicle_fuel_lbl.add_theme_font_size_override("font_size", 12)
	_vehicle_fuel_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	fuel_row.add_child(_vehicle_fuel_lbl)

	_vehicle_fuel_bar = ProgressBar.new()
	_vehicle_fuel_bar.min_value = 0.0
	_vehicle_fuel_bar.max_value = 100.0
	_vehicle_fuel_bar.value     = 100.0
	_vehicle_fuel_bar.show_percentage = true
	_vehicle_fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_fuel_bar.custom_minimum_size = Vector2(160, 14)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.18, 0.18, 0.18, 1)
	_vehicle_fuel_bar.add_theme_stylebox_override("background", bg)
	# Fill colour is set live in _update_vehicle_hud()
	fuel_row.add_child(_vehicle_fuel_bar)

	# AdBlue / DEF row (diesel machines only — hidden otherwise).
	_vehicle_adblue_row = HBoxContainer.new()
	var ad_lbl := Label.new()
	ad_lbl.text = "DEF "
	ad_lbl.add_theme_font_size_override("font_size", 12)
	ad_lbl.add_theme_color_override("font_color", Color(0.55, 0.7, 0.95, 1))
	_vehicle_adblue_row.add_child(ad_lbl)
	_vehicle_adblue_bar = ProgressBar.new()
	_vehicle_adblue_bar.min_value = 0.0
	_vehicle_adblue_bar.max_value = 100.0
	_vehicle_adblue_bar.value = 100.0
	_vehicle_adblue_bar.show_percentage = true
	_vehicle_adblue_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_adblue_bar.custom_minimum_size = Vector2(160, 12)
	_vehicle_adblue_row.add_child(_vehicle_adblue_bar)
	_vehicle_adblue_row.visible = false
	vbox.add_child(_vehicle_adblue_row)

	# Handbrake
	_vehicle_hb_lbl = Label.new()
	_vehicle_hb_lbl.text = "🅿  HANDBRAKE"
	_vehicle_hb_lbl.add_theme_font_size_override("font_size", 13)
	_vehicle_hb_lbl.add_theme_color_override("font_color", Color(0.95, 0.55, 0.10, 1))
	_vehicle_hb_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_vehicle_hb_lbl)

	# Clamp force row (BaleClamp only — hidden in other vehicles)
	_vehicle_clamp_row = HBoxContainer.new()
	_vehicle_clamp_row.add_theme_constant_override("separation", 8)
	_vehicle_clamp_row.visible = false
	vbox.add_child(_vehicle_clamp_row)

	_vehicle_clamp_lbl = Label.new()
	_vehicle_clamp_lbl.text = "CLAMP"
	_vehicle_clamp_lbl.add_theme_font_size_override("font_size", 12)
	_vehicle_clamp_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	_vehicle_clamp_row.add_child(_vehicle_clamp_lbl)

	_vehicle_clamp_bar = ProgressBar.new()
	_vehicle_clamp_bar.min_value = 0.0
	_vehicle_clamp_bar.max_value = 100.0
	_vehicle_clamp_bar.value = 50.0
	_vehicle_clamp_bar.show_percentage = true
	_vehicle_clamp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vehicle_clamp_bar.custom_minimum_size = Vector2(160, 14)
	var cbg := StyleBoxFlat.new()
	cbg.bg_color = Color(0.18, 0.18, 0.18, 1)
	_vehicle_clamp_bar.add_theme_stylebox_override("background", cbg)
	_vehicle_clamp_row.add_child(_vehicle_clamp_bar)

	# Wire-cut hint — shows when force ≥ wire compliance on the carried bale.
	# (The Shift+B in-cab wire cut was REMOVED — cutting happens ON FOOT with the
	# concrete scissors after dismounting, see BaleClamp.gd — so the hint teaches
	# the real procedure instead of a dead control.)
	_vehicle_clamp_hint = Label.new()
	_vehicle_clamp_hint.text = "Wires bulging — exit cab (E) and cut each wire with the concrete scissors"
	_vehicle_clamp_hint.add_theme_font_size_override("font_size", 11)
	_vehicle_clamp_hint.add_theme_color_override("font_color", Color(0.95, 0.78, 0.30, 1))
	_vehicle_clamp_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_vehicle_clamp_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_vehicle_clamp_hint.custom_minimum_size = Vector2(200.0, 0.0)
	_vehicle_clamp_hint.visible = false
	vbox.add_child(_vehicle_clamp_hint)

func _on_operator_entered_vehicle(vehicle: Node) -> void:
	_bound_vehicle = vehicle
	_vehicle_panel.visible = true
	# Clamp row only visible for the bale clamp
	var is_clamp := "clamp_force" in vehicle
	_vehicle_clamp_row.visible = is_clamp
	_vehicle_clamp_hint.visible = false

func _on_operator_exited_vehicle(_vehicle: Node) -> void:
	_bound_vehicle = null
	_vehicle_panel.visible = false
	_vehicle_clamp_row.visible = false
	_vehicle_clamp_hint.visible = false

func _process(delta: float) -> void:
	# Crew/rota panel refresh (throttled ~2 Hz) — runs regardless of vehicle state.
	_crew_accum += delta
	if _crew_accum >= 0.5:
		_crew_accum = 0.0
		_refresh_crew_panel()
		_refresh_walkie()         # battery % ticks down slowly; 2 Hz is plenty
		_refresh_line_panel()     # material-line PLC power-up state (#171)

	# Fade the last incoming-call line after a few seconds.
	if _walkie_call_t > 0.0:
		_walkie_call_t -= delta
		if _walkie_call_t <= 0.0 and _walkie_call:
			_walkie_call.text = ""

	# Scanner banner: decay its visible time, hide when zero.
	if _scanner_banner_fade > 0.0:
		_scanner_banner_fade -= delta
		if _scanner_banner_fade <= 0.0 and _scanner_banner_panel:
			_scanner_banner_panel.visible = false

	# "✓ Saved" toast: same decay pattern as the scanner banner.
	if _save_toast_fade > 0.0:
		_save_toast_fade -= delta
		if _save_toast_fade <= 0.0 and _save_toast_panel:
			_save_toast_panel.visible = false

	if _bound_vehicle == null or not _vehicle_panel.visible:
		return
	# Speed (m/s → km/h). Prefer the kinematic forward-speed signal because
	# vehicles run in freeze=true / FREEZE_MODE_KINEMATIC, which makes
	# linear_velocity a contact-response value (~0) instead of motion speed.
	if _bound_vehicle.has_method("get_speed_mps"):
		var spd: float = _bound_vehicle.get_speed_mps()
		_vehicle_speed.text = "%.1f km/h" % (spd * 3.6)
	elif "linear_velocity" in _bound_vehicle:
		var v: Vector3 = _bound_vehicle.linear_velocity
		_vehicle_speed.text = "%.1f km/h" % (v.length() * 3.6)
	# Fuel
	if "fuel_l" in _bound_vehicle and "fuel_capacity_l" in _bound_vehicle:
		var pct := float(_bound_vehicle.fuel_l) / float(_bound_vehicle.fuel_capacity_l) * 100.0
		_vehicle_fuel_bar.value = pct
		# Colour: green > 50, amber 15-50, red < 15
		var fill := StyleBoxFlat.new()
		if pct < 15.0:    fill.bg_color = Color(0.85, 0.15, 0.10, 1)
		elif pct < 50.0:  fill.bg_color = Color(0.95, 0.65, 0.10, 1)
		else:             fill.bg_color = Color(0.30, 0.75, 0.20, 1)
		_vehicle_fuel_bar.add_theme_stylebox_override("fill", fill)
	# Handbrake — only show when engaged
	if "handbrake_engaged" in _bound_vehicle:
		_vehicle_hb_lbl.visible = bool(_bound_vehicle.handbrake_engaged)
	# Clamp force (bale clamp only)
	if _vehicle_clamp_row.visible and "clamp_force" in _bound_vehicle:
		var f := float(_bound_vehicle.clamp_force)
		_vehicle_clamp_bar.value = f * 100.0
		# Amber when bulging (above the carried bale's wire compliance), green
		# at safe grip levels, dim grey when not yet enough to lift one bale.
		var fill := StyleBoxFlat.new()
		var compliance := 0.55
		if "_carried_bale" in _bound_vehicle and _bound_vehicle._carried_bale != null:
			compliance = float((_bound_vehicle._carried_bale as Node).get_meta("wire_compliance", 0.55))
		var min_grip := 0.30
		if "_carried_bale" in _bound_vehicle and _bound_vehicle._carried_bale != null:
			min_grip = float((_bound_vehicle._carried_bale as Node).get_meta("clamp_force_needed", 0.30))
		if f < min_grip:                    fill.bg_color = Color(0.55, 0.55, 0.55, 1)
		elif f < compliance:                fill.bg_color = Color(0.30, 0.75, 0.20, 1)
		else:                               fill.bg_color = Color(0.95, 0.65, 0.10, 1)
		_vehicle_clamp_bar.add_theme_stylebox_override("fill", fill)
		# Show the cut hint only when bulging AND we're actually carrying a bale
		var carried = _bound_vehicle._carried_bale if "_carried_bale" in _bound_vehicle else null
		var bulging := carried != null and f >= compliance and not bool(carried.get_meta("wires_cut", false))
		_vehicle_clamp_hint.visible = bulging

# =============================================================================
# INPUT — ESC owned here, not in PlayerController
# =============================================================================
## Open/close the interactive crew assignment overlay (Numpad "."). Lazily creates
## the panel on first use and reuses it after.
func _toggle_crew_panel() -> void:
	if crew_manager == null:
		return
	if _crew_assign_panel == null or not is_instance_valid(_crew_assign_panel):
		_crew_assign_panel = load("res://src/scenes/hud/CrewPanel.gd").new() as CanvasLayer
		add_child(_crew_assign_panel)
	if _crew_assign_panel.has_method("toggle_for"):
		_crew_assign_panel.call("toggle_for", crew_manager)

func _input(event: InputEvent) -> void:
	if _handle_walkie_input(event):
		return
	if _handle_crew_panel_input(event):
		return
	if _handle_crew_start_line_input(event):
		return
	if _handle_map_input(event):
		return
	if _handle_pause_menu_input(event):
		return

func _handle_walkie_input(event: InputEvent) -> bool:
	# ── Walkie-talkie (J = headset/speaker, , / . = volume, U = message menu) ─
	var w := get_node_or_null("/root/Walkie")
	if w != null:
		# Message picker is modal-ish — when open it swallows nav/select keys so
		# vehicle/player controls (W/S, arrow keys, Enter) don't double-fire.
		if _walkie_menu_open:
			if event.is_action_pressed("walkie_ptt"):
				_close_walkie_menu()
				get_viewport().set_input_as_handled()
				return true
			if event.is_action_pressed("ui_cancel"):
				_close_walkie_menu()
				get_viewport().set_input_as_handled()
				return true
			if event.is_action_pressed("ui_accept"):
				_send_walkie_menu_selection()
				get_viewport().set_input_as_handled()
				return true
			if event.is_action_pressed("ui_up"):
				if not _walkie_menu_rows.is_empty():
					_walkie_menu_sel = (_walkie_menu_sel - 1 + _walkie_menu_rows.size()) % _walkie_menu_rows.size()
					_refresh_walkie_menu()
				get_viewport().set_input_as_handled()
				return true
			if event.is_action_pressed("ui_down"):
				if not _walkie_menu_rows.is_empty():
					_walkie_menu_sel = (_walkie_menu_sel + 1) % _walkie_menu_rows.size()
					_refresh_walkie_menu()
				get_viewport().set_input_as_handled()
				return true
			# Numeric hotkeys 1..9 — fire and close immediately.
			if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
				var kc : int = (event as InputEventKey).keycode
				if kc >= KEY_1 and kc <= KEY_9:
					var idx : int = kc - KEY_1
					if idx < _walkie_menu_rows.size():
						_walkie_menu_sel = idx
						_send_walkie_menu_selection()
					get_viewport().set_input_as_handled()
					return true
			# Other KEY/BUTTON presses while open are swallowed so they can't leak
			# through to vehicle / player controls behind the overlay. Mouse motion
			# is intentionally let through — the menu is non-modal cursor-wise, so
			# the operator can keep looking around while choosing a message.
			if event is InputEventKey or event is InputEventMouseButton:
				get_viewport().set_input_as_handled()
			return true
		if event.is_action_pressed("walkie_headset"):
			w.toggle_headset()
			get_viewport().set_input_as_handled()
			return true
		if event.is_action_pressed("walkie_vol_down"):
			w.volume_down()
			get_viewport().set_input_as_handled()
			return true
		if event.is_action_pressed("walkie_vol_up"):
			w.volume_up()
			get_viewport().set_input_as_handled()
			return true
		if event.is_action_pressed("walkie_ptt"):
			# U now opens the message picker instead of firing a canned line
			# blindly. Second U (or Esc) closes; number keys / Enter send.
			_open_walkie_menu()
			get_viewport().set_input_as_handled()
			return true
	return false

func _handle_crew_panel_input(event: InputEvent) -> bool:
	# ── Crew assignment panel (Numpad ".") ───────────────────────────────────
	if event.is_action_pressed("crew_panel"):
		_toggle_crew_panel()
		get_viewport().set_input_as_handled()
		return true
	return false

func _handle_crew_start_line_input(event: InputEvent) -> bool:
	# ── Line 1 Startup with Crew (Insert) ────────────────────────────────────
	var triggered := false
	if event.is_action_pressed("crew_start_line"):
		triggered = true
	elif event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		if (event as InputEventKey).keycode == KEY_INSERT:
			triggered = true
	if triggered:
		var cm : CrewManager = crew_manager
		if cm == null and get_tree() != null:
			cm = get_tree().get_first_node_in_group("crew_manager") as CrewManager
		if cm != null and cm.has_method("start_line_1_with_crew"):
			cm.start_line_1_with_crew()
			get_viewport().set_input_as_handled()
			return true
	return false

func _handle_map_input(event: InputEvent) -> bool:
	# ── Site map (M to toggle, scroll to zoom, ESC to close) ──────────────────
	if event.is_action_pressed("map_toggle"):
		if _map_overlay:
			_map_overlay.toggle()
		get_viewport().set_input_as_handled()
		return true
	if _map_overlay and _map_overlay.is_open():
		# While the map is up it owns the wheel (zoom) and ESC (close).
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
			var btn := (event as InputEventMouseButton).button_index
			if btn == MOUSE_BUTTON_WHEEL_UP:
				_map_overlay.handle_zoom(1)
				get_viewport().set_input_as_handled()
				return true
			elif btn == MOUSE_BUTTON_WHEEL_DOWN:
				_map_overlay.handle_zoom(-1)
				get_viewport().set_input_as_handled()
				return true
		if event.is_action_pressed("ui_cancel"):
			_map_overlay.close()
			get_viewport().set_input_as_handled()
			return true
	return false

func _handle_pause_menu_input(event: InputEvent) -> bool:
	# P opens the pause menu directly (skipping the modal-close path that ESC has
	# to do because operators reach the Settings card from any state via P).
	if event.is_action_pressed("menu_toggle") and (_settings_menu == null or not _settings_menu.visible):
		get_viewport().set_input_as_handled()
		if _pause_overlay.visible:
			_do_resume()
		else:
			_do_pause()
		return true
	if event.is_action_pressed("ui_cancel"):
		if _end_of_shift_overlay and _end_of_shift_overlay.visible:
			get_viewport().set_input_as_handled()
			return true

		# Modal overlays such as the HMI own the first ESC press. Close them here in
		# _input before the pause menu toggles behind their _unhandled_input handler.
		for overlay in get_tree().get_nodes_in_group("esc_modal_overlay"):
			if overlay is CanvasLayer and overlay.has_method("is_open") and bool(overlay.call("is_open")):
				if overlay.has_method("close_overlay"):
					overlay.call("close_overlay")
					get_viewport().set_input_as_handled()
					return true
		# When the settings overlay is open, let IT handle ESC (cancel rebind
		# capture, or close the menu) — don't toggle the pause card behind it.
		if _settings_menu and _settings_menu.visible:
			return true
		get_viewport().set_input_as_handled()
		if _pause_overlay.visible:
			_do_resume()
		else:
			_do_pause()
		return true
	return false

# =============================================================================
# PAUSE / RESUME
# =============================================================================
func _do_pause() -> void:
	_pause_overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if shift_clock:
		shift_clock.pause_shift()

func _do_resume() -> void:
	_pause_overlay.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if shift_clock:
		shift_clock.resume_shift()

# =============================================================================
# SIGNAL HANDLERS
# =============================================================================
func _on_time_updated(time_string: String) -> void:
	if _time_label:
		# #166 — during the pre-shift window prepend a countdown so the player
		# knows the bell hasn't rung yet. "Shift starts in 12:34 · 06:48"
		if shift_clock and shift_clock.is_pre_shift():
			var s : int = int(ceilf(shift_clock.get_pre_shift_remaining_seconds()))
			# Whole minutes are the intent; floori keeps it explicit (a bare s / 60
			# trips INTEGER_DIVISION, and warnings are errors here).
			var mm : int = floori(s / 60.0)
			_time_label.text = "Shift starts in %02d:%02d · %s" % [mm, s % 60, time_string]
		else:
			_time_label.text = time_string
	if _progress_bar and shift_clock:
		_progress_bar.value = shift_clock.get_progress_percent() * 100.0

func _on_shift_ended() -> void:
	if _end_of_shift_overlay:
		_end_of_shift_overlay.visible = true
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	if shift_clock:
		shift_clock.pause_shift()

func _on_next_shift_pressed() -> void:
	if _end_of_shift_overlay:
		_end_of_shift_overlay.visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if shift_clock:
		shift_clock.roll_to_next_shift()

func _on_resume_pressed() -> void:
	_do_resume()

func _on_settings_pressed() -> void:
	# Lazy-load on first use so the pause menu is cheap until needed
	if _settings_menu == null:
		var scene := load("res://src/scenes/menus/SettingsMenu.tscn") as PackedScene
		if not scene:
			push_error("[HUD] SettingsMenu.tscn missing")
			return
		_settings_menu = scene.instantiate()
		add_child(_settings_menu)
		_settings_menu.closed.connect(_on_settings_closed)
	# Hide the pause card while settings overlay is up (it would visually clash)
	_pause_overlay.visible = false
	_settings_menu.open()

func _on_settings_closed() -> void:
	# Return to the pause overlay (game still paused)
	_pause_overlay.visible = true

func _on_save_pressed() -> void:
	# Stay paused — the operator just wants confirmation the shift is on disk.
	# SaveCoordinator emits autosave_completed, which pops the "✓ Saved" toast.
	if main_world:
		main_world.save_game()

func _on_save_quit_pressed() -> void:
	if main_world:
		main_world.save_and_quit()
	else:
		get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

# =============================================================================
# HOTBAR (4 inventory slots — bottom-centre)
# =============================================================================
func _build_hotbar() -> void:
	_hotbar_row = HBoxContainer.new()
	_hotbar_row.name = "Hotbar"
	_hotbar_row.anchor_left   = 0.5
	_hotbar_row.anchor_right  = 0.5
	_hotbar_row.anchor_top    = 1.0
	_hotbar_row.anchor_bottom = 1.0
	_hotbar_row.offset_left   = -330.0   # #punch: widened for the 5th slot (5×120 + 4×8)
	_hotbar_row.offset_right  =  330.0
	_hotbar_row.offset_top    = -76.0
	_hotbar_row.offset_bottom = -16.0
	_hotbar_row.add_theme_constant_override("separation", 8)
	_hotbar_row.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(_hotbar_row)
	_hotbar_boxes  = []
	_hotbar_labels = []
	var _n_slots : int = int(get_node("/root/Inventory").NUM_SLOTS) if has_node("/root/Inventory") else 5
	for i in _n_slots:
		var box := PanelContainer.new()
		box.custom_minimum_size = Vector2(120, 60)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.06, 0.07, 0.06, 0.85)
		sb.border_color = Color(0.32, 0.52, 0.34, 1.0)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(6)
		sb.content_margin_top = 6.0; sb.content_margin_bottom = 6.0
		sb.content_margin_left = 8.0; sb.content_margin_right = 8.0
		box.add_theme_stylebox_override("panel", sb)
		var vb := VBoxContainer.new()
		vb.add_theme_constant_override("separation", 2)
		box.add_child(vb)
		var key_lbl := Label.new()
		key_lbl.text = "[%d]" % (i + 1)
		key_lbl.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6, 1))
		key_lbl.add_theme_font_size_override("font_size", 11)
		vb.add_child(key_lbl)
		var name_lbl := Label.new()
		name_lbl.text = "—"
		name_lbl.add_theme_color_override("font_color", Color(0.86, 0.92, 0.84, 1))
		name_lbl.add_theme_font_size_override("font_size", 14)
		vb.add_child(name_lbl)
		_hotbar_row.add_child(box)
		_hotbar_boxes.append(box)
		_hotbar_labels.append(name_lbl)

func _refresh_hotbar() -> void:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null:
		return
	var active : int = int(inv.get("active_idx"))
	for i in _hotbar_labels.size():
		var lbl : Label = _hotbar_labels[i]
		lbl.text = String(inv.call("slot_label", i))
		var box : PanelContainer = _hotbar_boxes[i]
		var sb : StyleBoxFlat = box.get_theme_stylebox("panel") as StyleBoxFlat
		if sb == null:
			continue
		# Active slot pops with a brighter border + a soft amber glow.
		if i == active:
			sb.border_color = Color(0.95, 0.78, 0.30, 1.0)
			sb.set_border_width_all(2)
			sb.bg_color = Color(0.10, 0.10, 0.06, 0.92)
		else:
			sb.border_color = Color(0.32, 0.52, 0.34, 1.0)
			sb.set_border_width_all(1)
			sb.bg_color = Color(0.06, 0.07, 0.06, 0.85)

func _on_inventory_active_changed(_idx: int) -> void:
	_refresh_hotbar()
	_refresh_inhand_hint()   # swap the bottom-left hint to held-tool controls

func _on_inventory_slots_changed() -> void:
	_refresh_hotbar()

# =============================================================================
# SCANNER BANNER (centre-top, fades after ~3 s)
# =============================================================================
func _build_scanner_banner() -> void:
	_scanner_banner_panel = PanelContainer.new()
	_scanner_banner_panel.name = "ScannerBanner"
	_scanner_banner_panel.anchor_left   = 0.5
	_scanner_banner_panel.anchor_right  = 0.5
	_scanner_banner_panel.anchor_top    = 0.0
	_scanner_banner_panel.anchor_bottom = 0.0
	_scanner_banner_panel.offset_left   = -240.0
	_scanner_banner_panel.offset_right  =  240.0
	_scanner_banner_panel.offset_top    =  60.0
	_scanner_banner_panel.offset_bottom =  60.0
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.10, 0.06, 0.88)
	sb.border_color = Color(0.20, 1.00, 0.30, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_scanner_banner_panel.add_theme_stylebox_override("panel", sb)
	_scanner_banner_label = Label.new()
	_scanner_banner_label.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86, 1))
	_scanner_banner_label.add_theme_font_size_override("font_size", 13)
	_scanner_banner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_scanner_banner_panel.add_child(_scanner_banner_label)
	_scanner_banner_panel.visible = false
	add_child(_scanner_banner_panel)

# =============================================================================
# SAVE TOAST ("✓ Saved" — top-right, fades after ~1.5 s)
# =============================================================================
func _build_save_toast() -> void:
	_save_toast_panel = PanelContainer.new()
	_save_toast_panel.name = "SaveToast"
	# Top-right, tucked under the line-power banner (y 12..44); the walkie menu
	# opens at y 60 on the same edge but is user-toggled, so a 1.5 s overlap is
	# acceptable in the rare save-while-choosing-a-message case.
	_save_toast_panel.anchor_left   = 1.0
	_save_toast_panel.anchor_right  = 1.0
	_save_toast_panel.anchor_top    = 0.0
	_save_toast_panel.anchor_bottom = 0.0
	_save_toast_panel.offset_left   = -220.0   # #Q1 widened: fits "✓ Opgeslagen — <name>  HH:MM"
	_save_toast_panel.offset_right  = -12.0
	_save_toast_panel.offset_top    = 50.0
	_save_toast_panel.offset_bottom = 50.0
	# Same StyleBox recipe as the scanner banner — dark green + green border.
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.06, 0.10, 0.06, 0.88)
	sb.border_color = Color(0.20, 1.00, 0.30, 1.0)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(6)
	sb.content_margin_left = 14.0
	sb.content_margin_right = 14.0
	sb.content_margin_top = 8.0
	sb.content_margin_bottom = 8.0
	_save_toast_panel.add_theme_stylebox_override("panel", sb)
	var lbl := Label.new()
	lbl.text = "✓ Saved"
	lbl.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86, 1))
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_save_toast_panel.add_child(lbl)
	_save_toast_label = lbl   # #Q1 — keep ref so _on_autosave_completed can update it
	_save_toast_panel.visible = false
	add_child(_save_toast_panel)

func _on_autosave_completed() -> void:
	if _save_toast_panel == null:
		return
	# #Q1 — show save name + wall-clock time so the operator knows which file
	# landed on disk and when, without opening the pause menu.
	var save_name := "shift"
	if has_node("/root/GameState"):
		var gs := get_node("/root/GameState")
		if "save_file_path" in gs:
			var fp : String = String(gs.save_file_path)
			# e.g. user://mijn_world_save.json → "mijn_world"
			save_name = fp.get_file().trim_suffix("_save.json").trim_suffix(".json")
			if save_name == "" or save_name == "cedo_simulator":
				save_name = "default"
	var t := Time.get_datetime_dict_from_system()
	var ts := "%02d:%02d" % [int(t.get("hour", 0)), int(t.get("minute", 0))]
	if _save_toast_label != null:
		_save_toast_label.text = "✓ Opgeslagen — %s  %s" % [save_name, ts]
	_save_toast_panel.visible = true
	_save_toast_fade = 2.5   # slightly longer so the operator can read the name

func _on_scanner_banner(text: String, is_error: bool = false) -> void:
	if _scanner_banner_label == null:
		return
	_scanner_banner_label.text = text
	if is_error:
		_scanner_banner_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3, 1))
	else:
		_scanner_banner_label.add_theme_color_override("font_color", Color(0.86, 0.95, 0.86, 1))
	_scanner_banner_panel.visible = true
	_scanner_banner_fade = 3.0
	# (HUD already has _process running; the banner fades in the same per-frame
	# tick, see the bottom of the original _process up at line ~646.)
