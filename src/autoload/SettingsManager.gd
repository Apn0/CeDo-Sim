extends Node

## Owns all settings — graphics, audio, gameplay, key bindings.
## Persists to `user://settings.cfg` (ConfigFile format).
## Applies live to the engine on apply().
##
## Architecture:
##   _current : the live, applied, saved state
##   _pending : the working copy the UI mutates
##   apply()  : _pending → _current, save, push to engine
##   cancel() : _current → _pending
##
## Design influences:
##   - Euro Truck Simulator 2 (separates engine/cabin/UI audio; tabbed menu)
##   - Hardspace: Shipbreaker (rebindable keys, simple flat structure)
##   - Game Developer "Better game settings" checklist (logical grouping)

# ── Persistence ───────────────────────────────────────────────────────────────
const SAVE_PATH := "user://settings.cfg"

# ── Defaults (single source of truth) ─────────────────────────────────────────
const DEFAULTS_GRAPHICS := {
	"display_mode":     "windowed",       # windowed / borderless / fullscreen
	"resolution_w":     1920,
	"resolution_h":     1080,
	"vsync":            "enabled",        # disabled / enabled / adaptive
	"max_fps":          144,              # 0 = unlimited
	"render_scale":     1.0,              # 0.5 – 2.0
	"msaa":             2,                # 0/2/4/8
	"fxaa":             true,
	"shadow_quality":   2,                # 0=off, 1=low, 2=med, 3=high, 4=ultra
	"shadow_distance":  150.0,            # metres
	"volumetric_fog":   false,            # off by default — adds haze; opt-in via menu
	"ssao":             true,
	"sdfgi":            true,             # real-time global illumination (fills shadow/back faces)
	"brightness":       1.0,              # 0.5 – 1.5
	"fov":              75.0,             # 60 – 110 degrees
}

const DEFAULTS_AUDIO := {
	"master_db":        0.0,
	"machines_db":      0.0,
	"voices_db":        0.0,
	"ambient_db":       -6.0,
	"ui_db":            -3.0,
	"mute_unfocused":   true,
}

const DEFAULTS_GAMEPLAY := {
	"mouse_sensitivity_x":      0.003,
	"mouse_sensitivity_y":      0.003,
	"invert_mouse_y":           false,
	"invert_cam_x":             false,    # external/orbit free-cam: invert horizontal (yaw)
	"invert_cam_y":             false,    # external/orbit free-cam: invert vertical (pitch)
	"mouse_smoothing":          0.2,      # 0.0 – 1.0
	"gamepad_deadzone":         0.15,
	"head_bob":                 true,
	"hud_opacity":              1.0,      # 0.5 – 1.0
	"show_interaction_prompts": true,
	"autosave_interval_s":      60,       # 0 = off
	# Shift time compression: game-seconds per real second (#166). 24 → an 8 h
	# shift plays out in ~20 real min. 1 = true real-time (8 real h); raise for a
	# faster shift. ShiftClock reads this so the operator sets the pace they want.
	"shift_time_scale":         24.0,
	"subtitles":                true,
	"subtitle_size":            "medium", # small / medium / large
	"tutorial_hints":           true,
	"language":                 "en",     # en / nl
	"units":                    "metric", # metric / imperial
}

# ── Working state ─────────────────────────────────────────────────────────────
var _current_graphics : Dictionary
var _current_audio    : Dictionary
var _current_gameplay : Dictionary
var _current_keybinds : Dictionary = {}   # action_name → Array[InputEvent]

var _pending_graphics : Dictionary
var _pending_audio    : Dictionary
var _pending_gameplay : Dictionary
var _pending_keybinds : Dictionary = {}

# Cached defaults for keybinds — captured from project.godot on first run
var _default_keybinds : Dictionary = {}

signal settings_applied     # emitted after apply() finishes
signal keybinds_changed     # emitted after key rebind

# ── Action groups — display order + grouping in the Controls tab ─────────────
# Same keys are reused across vehicles (forklift / bale clamp / Merlo), so the
# "Forklift hydraulics" group also covers the bale clamp's lift/tilt/clamp and
# the Merlo's boom/telescope/curl/grapple — see ACTION_LABELS for the full map.
const ACTION_GROUPS := [
	{
		"label":   "Movement",
		"actions": ["move_forward", "move_backward", "move_left", "move_right", "jump",
					"crouch_toggle", "prone_toggle"],
	},
	{
		"label":   "Interaction & UI",
		"actions": ["interact", "ui_cancel", "camera_toggle", "map_toggle", "crew_panel", "debug_unstuck"],
	},
	{
		"label":   "Walkie-talkie",
		"actions": ["walkie_headset", "walkie_vol_down", "walkie_vol_up"],
	},
	{
		"label":   "Hand tools (on foot)",
		"actions": ["tool_use", "tool_place_mode",
					"hotbar_1", "hotbar_2", "hotbar_3", "hotbar_4", "hotbar_drop"],
	},
	{
		"label":   "Walkie-talkie (extra)",
		"actions": ["walkie_ptt"],
	},
	{
		"label":   "Vehicle aux (lights / horn / wipers / LPG)",
		"actions": ["vehicle_lights", "vehicle_hazards", "vehicle_blinker_left", "vehicle_blinker_right", "vehicle_horn",
					"vehicle_wipers", "lpg_switch_active"],
	},
	{
		"label":   "Vehicle (drive)",
		"actions": ["vehicle_forward", "vehicle_reverse",
					"vehicle_steer_left", "vehicle_steer_right",
					"vehicle_brake", "vehicle_handbrake"],
	},
	{
		"label":   "Vehicle hydraulics (forklift / bale clamp / Merlo)",
		"actions": ["forklift_lift_up", "forklift_lift_down",
					"forklift_tilt_back", "forklift_tilt_fwd",
					"forklift_rotator_left", "forklift_rotator_right",
					"forklift_forks_widen", "forklift_forks_pinch"],
	},
	{
		"label":   "Build mode",
		"actions": ["build_mode_toggle", "build_place", "build_cancel",
					"build_rotate_ccw", "build_rotate_cw",
					"build_raise", "build_lower",
					"build_grid_toggle", "build_delete"],
	},
]

# Human-readable labels for actions in the Controls UI
const ACTION_LABELS := {
	"move_forward":             "Walk forward",
	"move_backward":            "Walk backward",
	"move_left":                "Strafe left",
	"move_right":               "Strafe right",
	"jump":                     "Jump",
	"crouch_toggle":            "Crouch (toggle) — Left Ctrl",
	"prone_toggle":             "Lie down / prone (toggle) — Z",
	"interact":                 "Interact / enter vehicle",
	"ui_cancel":                "Pause / cancel",
	"camera_toggle":            "Cycle camera mode (P — also F4-tap)\n  F4 + ←/→/↑/↓ pan orbit · F4 + scroll wheel zoom",
	"map_toggle":               "Open / close the site map (M)",
	"crew_panel":               "Open crew assignment panel — assign workers → posts (Numpad .)",
	"debug_unstuck":            "Unstuck me — lift +2 m, else teleport to PlayerSpawn (F12)",
	"walkie_headset":           "Walkie: toggle earpiece / speaker (J)",
	"walkie_vol_down":          "Walkie: volume down (,)",
	"walkie_vol_up":            "Walkie: volume up (.)",
	"tool_use":                 "Use held tool (Left mouse — e.g. scissors → cut wire)",
	"tool_place_mode":          "Place held tool into a slot (G — on foot)",
	"hotbar_1":                 "Hand: slot 1 (1)",
	"hotbar_2":                 "Hand: slot 2 (2)",
	"hotbar_3":                 "Hand: slot 3 (3)",
	"hotbar_4":                 "Hand: slot 4 (4)",
	"hotbar_drop":              "Drop held tool (Q)",
	"walkie_ptt":               "Walkie: push-to-talk (U)",
	"vehicle_lights":           "Vehicle: work lights (L)",
	"vehicle_hazards":          "Vehicle: hazard blinkers (K)",
	"vehicle_blinker_left":     "Vehicle: left blinker ([)",
	"vehicle_blinker_right":    "Vehicle: right blinker (])",
	"vehicle_horn":             "Vehicle: horn — mast lift (N)",
	"vehicle_wipers":           "Vehicle: windscreen wipers on/off — Merlo P40 (Y)",
	"lpg_switch_active":        "Switch active LPG tank — bale clamp (H)",
	"vehicle_forward":          "Drive forward",
	"vehicle_reverse":          "Reverse",
	"vehicle_steer_left":       "Steer left",
	"vehicle_steer_right":      "Steer right",
	"vehicle_brake":            "Brake",
	"vehicle_handbrake":        "Handbrake (toggle)",
	# Same keys serve every vehicle's tool:
	#   Forklift  : lift R/F · tilt T/G · rotator Z/C · forks V/B
	#   Bale clamp: lift R/F · tilt T/G · — (unused) — · clamp open V / close B
	#   Merlo     : boom  R/F · telescope T/G · bucket curl Z/C · grapple open V / close B
	"forklift_lift_up":         "Lift / boom up   (R)",
	"forklift_lift_down":       "Lift / boom down (F)",
	"forklift_tilt_back":       "Tilt back / telescope out (T)",
	"forklift_tilt_fwd":        "Tilt fwd / telescope in   (G)",
	"forklift_rotator_left":    "Rotator / bucket curl in  (Z)",
	"forklift_rotator_right":   "Rotator / bucket curl out (C)",
	"forklift_forks_widen":     "Widen forks / clamp open / grapple open  (V)  — releases bale",
	"forklift_forks_pinch":     "Pinch forks / clamp close / grapple close (B)  — grabs bale",
	"build_mode_toggle":        "Toggle build mode",
	"build_place":              "Place / confirm corner (Left mouse)",
	"build_cancel":             "Cancel / step back     (Right mouse)",
	"build_rotate_ccw":         "Rotate placement CCW (Q · scroll down)",
	"build_rotate_cw":          "Rotate placement CW  (E · scroll up)",
	"build_raise":              "Raise placement height (R)",
	"build_lower":              "Lower placement height (F)",
	"build_grid_toggle":        "Toggle grid snap (G)",
	"build_delete":             "Delete pointed object (X)",
}

# =============================================================================
func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Register the runtime-added aux actions (hotbar, walkie PTT, vehicle
	# lights/hazards/horn/wipers, LPG switch, tool placement) FIRST, so they
	# exist before we snapshot the defaults — otherwise the Controls tab would
	# list them with no binding and "reset to defaults" wouldn't know them.
	# Each of PlayerController/HUD/MerloP40/ToolPlacementMode also calls its own
	# has_action()-guarded fallback; this is just the earliest, central one.
	_ensure_aux_actions()
	# Capture project-defined keybinds as the "defaults" baseline
	_capture_default_keybinds()
	# Initialise current state from defaults, then overlay any saved values
	_current_graphics = DEFAULTS_GRAPHICS.duplicate()
	_current_audio    = DEFAULTS_AUDIO.duplicate()
	_current_gameplay = DEFAULTS_GAMEPLAY.duplicate()
	_current_keybinds = _duplicate_keybinds(_default_keybinds)

	_load_from_disk()
	_sync_pending_from_current()
	apply()

	# Listen for focus-loss to honour mute_unfocused
	get_tree().root.connect("size_changed", _on_window_size_changed)

# =============================================================================
# PUBLIC API (consumers query these helpers — read live state from _current)
# =============================================================================
func graphics() -> Dictionary: return _current_graphics
func audio() -> Dictionary:    return _current_audio
func gameplay() -> Dictionary: return _current_gameplay
func keybinds() -> Dictionary: return _current_keybinds

# UI calls these for the working copy
func pending_graphics() -> Dictionary: return _pending_graphics
func pending_audio() -> Dictionary:    return _pending_audio
func pending_gameplay() -> Dictionary: return _pending_gameplay
func pending_keybinds() -> Dictionary: return _pending_keybinds

func set_pending(category: String, key: String, value) -> void:
	match category:
		"graphics": _pending_graphics[key] = value
		"audio":    _pending_audio[key]    = value
		"gameplay": _pending_gameplay[key] = value

func set_pending_keybind(action: String, events: Array) -> void:
	_pending_keybinds[action] = events

# =============================================================================
# APPLY / CANCEL / RESET
# =============================================================================
func apply() -> void:
	_current_graphics = _pending_graphics.duplicate(true)
	_current_audio    = _pending_audio.duplicate(true)
	_current_gameplay = _pending_gameplay.duplicate(true)
	_current_keybinds = _duplicate_keybinds(_pending_keybinds)
	_apply_to_engine()
	_save_to_disk()
	settings_applied.emit()

func cancel() -> void:
	_sync_pending_from_current()

func reset_category(category: String) -> void:
	match category:
		"graphics": _pending_graphics = DEFAULTS_GRAPHICS.duplicate()
		"audio":    _pending_audio    = DEFAULTS_AUDIO.duplicate()
		"gameplay": _pending_gameplay = DEFAULTS_GAMEPLAY.duplicate()
		"keybinds": _pending_keybinds = _duplicate_keybinds(_default_keybinds)

func reset_all() -> void:
	reset_category("graphics")
	reset_category("audio")
	reset_category("gameplay")
	reset_category("keybinds")

# =============================================================================
# APPLY TO ENGINE
# =============================================================================
func _apply_to_engine() -> void:
	_apply_graphics()
	_apply_audio()
	_apply_keybinds()

func _apply_graphics() -> void:
	# Display mode
	match _current_graphics.get("display_mode", "windowed"):
		"fullscreen": DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
		"borderless":
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
		"windowed":
			DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, false)
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	# Resolution (only when windowed/borderless — exclusive fullscreen uses native)
	if _current_graphics.get("display_mode", "windowed") != "fullscreen":
		DisplayServer.window_set_size(Vector2i(
			_current_graphics.get("resolution_w", 1920),
			_current_graphics.get("resolution_h", 1080)))

	# VSync
	match _current_graphics.get("vsync", "enabled"):
		"disabled": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		"enabled":  DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
		"adaptive": DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ADAPTIVE)

	# Max FPS
	Engine.max_fps = int(_current_graphics.get("max_fps", 0))

	# Viewport-level settings
	var vp := get_tree().root
	if vp:
		# Render scale
		vp.scaling_3d_scale = float(_current_graphics.get("render_scale", 1.0))
		# MSAA
		var msaa_v: int = int(_current_graphics.get("msaa", 2))
		var msaa_enum := Viewport.MSAA_DISABLED
		match msaa_v:
			2: msaa_enum = Viewport.MSAA_2X
			4: msaa_enum = Viewport.MSAA_4X
			8: msaa_enum = Viewport.MSAA_8X
		vp.msaa_3d = msaa_enum
		# FXAA (screen-space AA)
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA \
			if _current_graphics.get("fxaa", true) else Viewport.SCREEN_SPACE_AA_DISABLED

	# FOV applied to whatever camera is current at next frame
	_apply_fov_to_current_camera()

	# Environment-level settings (SSAO, SDFGI, fog, brightness, shadow distance).
	# No-op if the scene's WorldEnvironment isn't in the tree yet (e.g. at boot,
	# before MainWorld loads — MainWorld calls refresh_environment() once ready).
	_apply_environment_settings()

## Push graphics settings that live on the active Environment / sun.
## Safe to call any time — silently skips whatever isn't in the tree yet.
func _apply_environment_settings() -> void:
	var env := _find_active_environment()
	if env:
		env.ssao_enabled           = bool(_current_graphics.get("ssao", true))
		env.sdfgi_enabled          = bool(_current_graphics.get("sdfgi", true))
		# Default OFF — a stale save without this key was falling back to true and
		# adding grey haze over everything.
		env.volumetric_fog_enabled = bool(_current_graphics.get("volumetric_fog", false))
		env.fog_enabled            = bool(_current_graphics.get("fog", false))
		# Brightness via colour-adjustment (only enable when non-neutral)
		var b := float(_current_graphics.get("brightness", 1.0))
		env.adjustment_enabled    = not is_equal_approx(b, 1.0)
		env.adjustment_brightness = b
	var sun := _find_directional_light()
	if sun:
		sun.directional_shadow_max_distance = float(_current_graphics.get("shadow_distance", 150.0))
		sun.shadow_enabled = int(_current_graphics.get("shadow_quality", 2)) > 0

## Re-apply environment settings — call after the main scene (and its
## WorldEnvironment) has entered the tree so saved prefs take effect.
func refresh_environment() -> void:
	_apply_environment_settings()

func _find_active_environment() -> Environment:
	var we := get_tree().root.find_child("WorldEnvironment", true, false) as WorldEnvironment
	return we.environment if we else null

func _find_directional_light() -> DirectionalLight3D:
	return get_tree().root.find_child("DirectionalLight3D", true, false) as DirectionalLight3D

func _apply_audio() -> void:
	_set_bus_db("Master",   _current_audio.get("master_db", 0.0))
	_set_bus_db("Machines", _current_audio.get("machines_db", 0.0))
	_set_bus_db("Voices",   _current_audio.get("voices_db", 0.0))
	_set_bus_db("Ambient",  _current_audio.get("ambient_db", -6.0))
	_set_bus_db("UI",       _current_audio.get("ui_db", -3.0))

func _apply_keybinds() -> void:
	for action in _current_keybinds:
		if not InputMap.has_action(action):
			continue
		InputMap.action_erase_events(action)
		for ev in _current_keybinds[action]:
			if ev is InputEvent:
				InputMap.action_add_event(action, ev)
	keybinds_changed.emit()

func _apply_fov_to_current_camera() -> void:
	# Defer one frame so the camera is current after a display mode change.
	call_deferred("_set_fov_on_current_camera")

func _set_fov_on_current_camera() -> void:
	var cam := get_viewport().get_camera_3d() if get_viewport() else null
	if cam:
		cam.fov = float(_current_graphics.get("fov", 75.0))

func _set_bus_db(bus_name: String, db: float) -> void:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, db)

# =============================================================================
# DISK PERSISTENCE
# =============================================================================
func _save_to_disk() -> void:
	var cfg := ConfigFile.new()
	for k in _current_graphics: cfg.set_value("graphics", k, _current_graphics[k])
	for k in _current_audio:    cfg.set_value("audio",    k, _current_audio[k])
	for k in _current_gameplay: cfg.set_value("gameplay", k, _current_gameplay[k])
	# Keybinds: serialise InputEvents by their basic properties
	for action in _current_keybinds:
		var ev_data: Array = []
		for ev in _current_keybinds[action]:
			var d := _serialise_event(ev)
			if not d.is_empty():
				ev_data.append(d)
		cfg.set_value("keybinds", action, ev_data)
	cfg.save(SAVE_PATH)

func _load_from_disk() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return  # First run — keep defaults
	# Overlay saved values on defaults so new settings keep their defaults
	for k in DEFAULTS_GRAPHICS: _current_graphics[k] = cfg.get_value("graphics", k, _current_graphics[k])
	for k in DEFAULTS_AUDIO:    _current_audio[k]    = cfg.get_value("audio",    k, _current_audio[k])
	for k in DEFAULTS_GAMEPLAY: _current_gameplay[k] = cfg.get_value("gameplay", k, _current_gameplay[k])
	# Keybinds — replace defaults entirely with saved if present
	if cfg.has_section("keybinds"):
		for action in cfg.get_section_keys("keybinds"):
			var ev_data: Array = cfg.get_value("keybinds", action, [])
			var events: Array  = []
			for d in ev_data:
				var ev := _deserialise_event(d)
				if ev:
					events.append(ev)
			if events.size() > 0:
				_current_keybinds[action] = events

# =============================================================================
# KEYBIND HELPERS
# =============================================================================
## Central registration of the gameplay actions that used to be added ad-hoc in
## various _ready() methods. Idempotent: only adds an action / event when it's
## missing, so the per-system fallbacks remain harmless.
func _ensure_aux_actions() -> void:
	var binds := {
		"hotbar_1":          KEY_1,
		"hotbar_2":          KEY_2,
		"hotbar_3":          KEY_3,
		"hotbar_4":          KEY_4,
		"hotbar_drop":       KEY_Q,
		"lpg_switch_active": KEY_H,
		"vehicle_lights":    KEY_L,
		"vehicle_hazards":   KEY_K,
		"vehicle_blinker_left": KEY_BRACKETLEFT,
		"vehicle_blinker_right": KEY_BRACKETRIGHT,
		"vehicle_horn":      KEY_N,
		"vehicle_wipers":    KEY_Y,
		"walkie_ptt":        KEY_U,
		"tool_place_mode":   KEY_G,
	}
	for action_name in binds:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var key_code: int = binds[action_name]
		var has_event := false
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey and (ev as InputEventKey).keycode == key_code:
				has_event = true
				break
		if not has_event:
			var k := InputEventKey.new()
			k.keycode = key_code as Key
			InputMap.action_add_event(action_name, k)

func _capture_default_keybinds() -> void:
	for action in InputMap.get_actions():
		if action.begins_with("ui_") and action != "ui_cancel":
			continue  # leave Godot's built-in UI nav alone
		var events := InputMap.action_get_events(action)
		# Copy events so resets work cleanly even after rebinds
		_default_keybinds[action] = events.duplicate()

func _duplicate_keybinds(src: Dictionary) -> Dictionary:
	var out := {}
	for action in src:
		var arr: Array = []
		for ev in src[action]:
			arr.append(ev)   # InputEvent is RefCounted, sharing is fine
		out[action] = arr
	return out

func _serialise_event(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {
			"type":      "key",
			"keycode":   (ev as InputEventKey).keycode,
			"physical":  (ev as InputEventKey).physical_keycode,
		}
	elif ev is InputEventMouseButton:
		return {
			"type":          "mouse",
			"button_index":  (ev as InputEventMouseButton).button_index,
		}
	elif ev is InputEventJoypadButton:
		return {
			"type":          "joybutton",
			"button_index":  (ev as InputEventJoypadButton).button_index,
		}
	elif ev is InputEventJoypadMotion:
		return {
			"type":          "joymotion",
			"axis":          (ev as InputEventJoypadMotion).axis,
			"axis_value":    (ev as InputEventJoypadMotion).axis_value,
		}
	return {}

func _deserialise_event(d: Dictionary) -> InputEvent:
	match d.get("type", ""):
		"key":
			var ev := InputEventKey.new()
			ev.keycode = d.get("keycode", 0)
			ev.physical_keycode = d.get("physical", 0)
			return ev
		"mouse":
			var ev := InputEventMouseButton.new()
			ev.button_index = d.get("button_index", 0)
			return ev
		"joybutton":
			var ev := InputEventJoypadButton.new()
			ev.button_index = d.get("button_index", 0)
			return ev
		"joymotion":
			var ev := InputEventJoypadMotion.new()
			ev.axis = d.get("axis", 0)
			ev.axis_value = d.get("axis_value", 1.0)
			return ev
	return null

# =============================================================================
# INTERNAL
# =============================================================================
func _sync_pending_from_current() -> void:
	_pending_graphics = _current_graphics.duplicate(true)
	_pending_audio    = _current_audio.duplicate(true)
	_pending_gameplay = _current_gameplay.duplicate(true)
	_pending_keybinds = _duplicate_keybinds(_current_keybinds)

func _on_window_size_changed() -> void:
	pass  # placeholder hook for future window-resize logic
