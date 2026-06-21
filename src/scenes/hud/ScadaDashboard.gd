extends CanvasLayer

class_name ScadaDashboard

## ISA-101 "Dark Cockpit" SCADA dashboard for Line 3C (task #47).
##
## Design language — ISA-101 / "high-performance HMI":
##   • Everything NOMINAL is painted in muted, low-saturation GREY. A calm screen
##     means a healthy line — the operator's eye is never pulled by colour during
##     normal running.
##   • High-contrast colour (amber / red / cyan) is spent EXCLUSIVELY on alarm
##     deviations: a parameter outside its [nominal_low, nominal_high] band, or a
##     non-Running line state. Colour == "look here", nothing else.
##
## Public API (the sim machines push into this — see REGISTRATION at the bottom of
## the task note):
##   set_state(name)                               — "Running" / "Idle" / "Fault" / …
##   set_param(key, value, nominal_low, nominal_high) — a live process value + band
##   micro_stops : Array[Dictionary]               — logged Running→Idle→Running blips
##
## Background micro-stop logger:
##   A Running → Idle → Running transition completed in < MICRO_STOP_WINDOW_S
##   seconds is a "Micro-Stop": the kind of sub-minute blip (a momentary jam clear,
##   a doser hiccup) that wrecks OEE but never trips a full line alarm. We LOG it to
##   `micro_stops` and flash a discreet counter — but we deliberately DO NOT run the
##   full alarm-shutdown visual (the red banner / dimmed mimic). The dashboard stays
##   live so the operator keeps their situational picture.
##
## Built 100% programmatically (no .tscn), matching HUD.gd / PerfHud.gd.

# ── Tunables ────────────────────────────────────────────────────────────────────
const MICRO_STOP_WINDOW_S : float = 60.0   # Running→Idle→Running under this = micro-stop

# ── ISA-101 palette ─────────────────────────────────────────────────────────────
# Greys: the entire "normal" vocabulary. Saturated colours are alarms only.
const COL_BG          := Color(0.10, 0.11, 0.12, 0.92)   # near-black cockpit panel
const COL_BG_ROW      := Color(0.14, 0.15, 0.16, 1.0)    # value chip backing
const COL_GREY_TEXT   := Color(0.68, 0.70, 0.72, 1.0)    # nominal value text
const COL_GREY_LABEL  := Color(0.50, 0.52, 0.55, 1.0)    # parameter labels (dimmer)
const COL_GREY_LINE   := Color(0.24, 0.25, 0.27, 1.0)    # separators / borders
# Alarm vocabulary — used ONLY for deviations.
const COL_ALARM_HI    := Color(0.95, 0.27, 0.22, 1.0)    # red   — above band
const COL_ALARM_LO    := Color(0.98, 0.74, 0.16, 1.0)    # amber — below band
const COL_STATE_BAD   := Color(0.98, 0.74, 0.16, 1.0)    # amber — line not Running
const COL_ACCENT      := Color(0.40, 0.78, 0.95, 1.0)    # cyan — micro-stop flash

# ── State / data model ──────────────────────────────────────────────────────────
var micro_stops : Array = []          # Array[Dictionary] {t, idle_duration_s, ...}
var _state      : String = "Idle"     # current line State
var _params     : Dictionary = {}     # key -> {value, lo, hi, label}

# Micro-stop tracker: when the line last entered Idle from Running, and at what time.
var _idle_since_s : float = -1.0      # timestamp of the Running→Idle edge (-1 = n/a)
var _was_running  : bool  = false

# Injectable time source so the logic is testable without the engine clock.
# Returns elapsed seconds as a float. Default reads the engine wall clock; the
# headless test swaps in a manual counter (set_time_source) — that is why the
# micro-stop detection never touches Time.get_ticks directly here in the hot path.
var _time_source : Callable = Callable(self, "_engine_time_s")

# ── UI nodes ────────────────────────────────────────────────────────────────────
var _root_panel   : PanelContainer
var _state_label  : Label
var _state_chip   : PanelContainer
var _param_rows   : Dictionary = {}   # key -> {row, name_lbl, value_lbl, chip}
var _params_box   : VBoxContainer
var _microstop_lbl: Label
var _microstop_flash : float = 0.0    # seconds of cyan flash remaining on the counter

# =============================================================================
func _ready() -> void:
	layer = 20                        # above the 3-D world / base HUD, below pause
	_build_ui()
	_refresh_state_visual()
	_refresh_microstop_counter()

func _engine_time_s() -> float:
	# Production default — wall-clock seconds. The test replaces this Callable so
	# the deterministic path never depends on it.
	return float(Time.get_ticks_msec()) / 1000.0

func _now() -> float:
	return float(_time_source.call())

## Swap the clock. `cb` must be a Callable returning elapsed seconds (float).
## Used by the headless test to drive time deterministically.
func set_time_source(cb: Callable) -> void:
	_time_source = cb

# =============================================================================
# PUBLIC API — the sim machines push into these
# =============================================================================
## Set the line State ("Running" / "Idle" / "Fault" / "Starting" / …).
## Detects the Running→Idle→Running micro-stop window and logs it WITHOUT firing a
## full alarm shutdown. Returns true if this call closed a micro-stop.
func set_state(state_name: String) -> bool:
	var prev := _state
	_state = state_name
	var now := _now()
	var logged := false

	var is_running := _is_running_state(state_name)
	var was_running := _is_running_state(prev)

	if was_running and not is_running:
		# Running → (Idle / anything not-running): start the micro-stop stopwatch.
		_idle_since_s = now
	elif (not was_running) and is_running:
		# …→ Running again: if we left Running recently enough, that was a micro-stop.
		if _idle_since_s >= 0.0:
			var idle_dur := now - _idle_since_s
			if idle_dur < MICRO_STOP_WINDOW_S:
				_log_micro_stop(idle_dur, prev)
				logged = true
		_idle_since_s = -1.0

	_was_running = is_running
	if is_inside_tree():
		_refresh_state_visual()
	return logged

## Push a live process value plus its nominal band. Outside [lo, hi] → it alarms
## (the ONLY time colour appears in the value column).
func set_param(key: String, value: float, nominal_low: float, nominal_high: float, label: String = "") -> void:
	var rec : Dictionary = _params.get(key, {})
	rec["value"] = value
	rec["lo"] = nominal_low
	rec["hi"] = nominal_high
	if label != "":
		rec["label"] = label
	elif not rec.has("label"):
		rec["label"] = key
	_params[key] = rec
	if is_inside_tree():
		_refresh_param(key)

## Push a live STRING-valued process param. Same row layout as set_param but
## displays a text (e.g. fault_reason) instead of a float. is_alarming colours
## the value chip in alarm red regardless of band semantics. Used for status
## strings like "vacuum_lid_pushed_open" / "motor_torque_trip" that don't fit
## a numeric band.
func set_text_param(key: String, text: String, is_alarming: bool = false, label: String = "") -> void:
	var rec : Dictionary = _params.get(key, {})
	rec["text"] = text
	rec["text_alarm"] = is_alarming
	# Carry sentinel numeric so is_param_alarming() still works on the same key
	# (matches the alarm flag the caller passed in).
	rec["value"] = 1.0 if is_alarming else 0.0
	rec["lo"] = 0.0
	rec["hi"] = 0.5
	if label != "":
		rec["label"] = label
	elif not rec.has("label"):
		rec["label"] = key
	_params[key] = rec
	if is_inside_tree():
		_refresh_param(key)

## True when `key`'s last value sits outside its nominal band.
func is_param_alarming(key: String) -> bool:
	if not _params.has(key):
		return false
	var r : Dictionary = _params[key]
	var v : float = r["value"]
	return v < float(r["lo"]) or v > float(r["hi"])

## Current line state string.
func get_state() -> String:
	return _state

## How many micro-stops have been logged this session.
func micro_stop_count() -> int:
	return micro_stops.size()

## True only while a full-shutdown alarm visual would be showing. Micro-stops MUST
## NOT trip this — the test asserts the dashboard stays live across a blip.
func is_shutdown_visible() -> bool:
	return _root_panel != null and not _root_panel.visible

# =============================================================================
# MICRO-STOP LOGGING
# =============================================================================
func _is_running_state(state_name: String) -> bool:
	return state_name.strip_edges().to_lower() == "running"

func _log_micro_stop(idle_duration_s: float, prev_state: String) -> void:
	var entry := {
		"t": _now(),
		"idle_duration_s": idle_duration_s,
		"from_state": prev_state,
		"index": micro_stops.size(),
	}
	micro_stops.append(entry)
	# Discreet cyan flash on the counter — NOT a full-screen alarm. The dashboard
	# keeps running; we never hide _root_panel for a micro-stop.
	_microstop_flash = 2.0
	if is_inside_tree():
		_refresh_microstop_counter()
	push_warning("[SCADA] Micro-Stop #%d logged (idle %.1fs)" % [entry["index"], idle_duration_s])

# =============================================================================
# BUILD UI
# =============================================================================
func _build_ui() -> void:
	# Outer cockpit panel — top-right cluster, beneath the line-power banner.
	_root_panel = PanelContainer.new()
	_root_panel.name = "ScadaPanel"
	_root_panel.anchor_left = 1.0
	_root_panel.anchor_right = 1.0
	_root_panel.anchor_top = 0.0
	_root_panel.anchor_bottom = 0.0
	_root_panel.offset_left = -330.0
	_root_panel.offset_right = -12.0
	_root_panel.offset_top = 52.0
	_root_panel.offset_bottom = 320.0

	var style := StyleBoxFlat.new()
	style.bg_color = COL_BG
	style.set_corner_radius_all(6)
	style.set_border_width_all(1)
	style.border_color = COL_GREY_LINE
	style.content_margin_left = 12.0
	style.content_margin_right = 12.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	_root_panel.add_theme_stylebox_override("panel", style)
	add_child(_root_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 6)
	_root_panel.add_child(vbox)

	# ── Header row: title + state chip ──────────────────────────────────────────
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	vbox.add_child(header)

	var title := Label.new()
	title.text = "LINE 3C"
	title.add_theme_font_size_override("font_size", 13)
	title.add_theme_color_override("font_color", COL_GREY_LABEL)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	# State chip (its own backing so the state reads as a discrete annunciator).
	_state_chip = PanelContainer.new()
	var chip_style := StyleBoxFlat.new()
	chip_style.bg_color = COL_BG_ROW
	chip_style.set_corner_radius_all(4)
	chip_style.content_margin_left = 10.0
	chip_style.content_margin_right = 10.0
	chip_style.content_margin_top = 2.0
	chip_style.content_margin_bottom = 2.0
	_state_chip.add_theme_stylebox_override("panel", chip_style)
	header.add_child(_state_chip)

	_state_label = Label.new()
	_state_label.text = _state.to_upper()
	_state_label.add_theme_font_size_override("font_size", 14)
	_state_label.add_theme_color_override("font_color", COL_GREY_TEXT)
	_state_chip.add_child(_state_label)

	vbox.add_child(_hsep())

	# ── Parameter table ─────────────────────────────────────────────────────────
	_params_box = VBoxContainer.new()
	_params_box.add_theme_constant_override("separation", 3)
	vbox.add_child(_params_box)

	vbox.add_child(_hsep())

	# ── Micro-stop counter (footer) ─────────────────────────────────────────────
	_microstop_lbl = Label.new()
	_microstop_lbl.add_theme_font_size_override("font_size", 12)
	_microstop_lbl.add_theme_color_override("font_color", COL_GREY_LABEL)
	vbox.add_child(_microstop_lbl)

func _hsep() -> HSeparator:
	var s := HSeparator.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = COL_GREY_LINE
	sb.content_margin_top = 1.0
	sb.content_margin_bottom = 1.0
	s.add_theme_stylebox_override("separator", sb)
	return s

## Lazily build (or fetch) the row widgets for one parameter key.
func _ensure_param_row(key: String) -> Dictionary:
	if _param_rows.has(key):
		return _param_rows[key]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	_params_box.add_child(row)

	var name_lbl := Label.new()
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", COL_GREY_LABEL)
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_lbl)

	# Value chip — its backing stays grey; only the TEXT colours on alarm.
	var chip := PanelContainer.new()
	var cs := StyleBoxFlat.new()
	cs.bg_color = COL_BG_ROW
	cs.set_corner_radius_all(3)
	cs.content_margin_left = 8.0
	cs.content_margin_right = 8.0
	cs.content_margin_top = 1.0
	cs.content_margin_bottom = 1.0
	chip.add_theme_stylebox_override("panel", cs)
	row.add_child(chip)

	var value_lbl := Label.new()
	value_lbl.add_theme_font_size_override("font_size", 13)
	value_lbl.add_theme_color_override("font_color", COL_GREY_TEXT)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.custom_minimum_size = Vector2(78, 0)
	chip.add_child(value_lbl)

	var rec := {"row": row, "name_lbl": name_lbl, "value_lbl": value_lbl, "chip": chip}
	_param_rows[key] = rec
	return rec

# =============================================================================
# VISUAL REFRESH (grey = nominal, colour = alarm only)
# =============================================================================
func _refresh_param(key: String) -> void:
	if not _params.has(key):
		return
	var data : Dictionary = _params[key]
	var widgets := _ensure_param_row(key)
	var name_lbl : Label = widgets["name_lbl"]
	var value_lbl : Label = widgets["value_lbl"]
	name_lbl.text = String(data.get("label", key))
	# Text-valued param branch (status strings — see set_text_param).
	if data.has("text"):
		var t : String = String(data["text"])
		value_lbl.text = t if t != "" else "—"
		var alarm : bool = bool(data.get("text_alarm", false))
		if alarm:
			value_lbl.add_theme_color_override("font_color", COL_ALARM_HI)
		else:
			value_lbl.add_theme_color_override("font_color", COL_GREY_TEXT)
		return
	var v : float = data["value"]
	value_lbl.text = _fmt(v)
	# ISA-101: nominal stays grey; only a band breach earns colour.
	var lo : float = float(data["lo"])
	var hi : float = float(data["hi"])
	if v > hi:
		value_lbl.add_theme_color_override("font_color", COL_ALARM_HI)
	elif v < lo:
		value_lbl.add_theme_color_override("font_color", COL_ALARM_LO)
	else:
		value_lbl.add_theme_color_override("font_color", COL_GREY_TEXT)

func _refresh_state_visual() -> void:
	if _state_label == null:
		return
	_state_label.text = _state.to_upper()
	# Running = calm grey. Any non-running state is the deviation → amber.
	if _is_running_state(_state):
		_state_label.add_theme_color_override("font_color", COL_GREY_TEXT)
	else:
		_state_label.add_theme_color_override("font_color", COL_STATE_BAD)

func _refresh_microstop_counter() -> void:
	if _microstop_lbl == null:
		return
	var n := micro_stops.size()
	_microstop_lbl.text = "Micro-Stops:  %d" % n
	# Brief cyan flash right after one is logged; otherwise dim grey. A micro-stop
	# is informational — it never escalates to the red alarm vocabulary.
	if _microstop_flash > 0.0:
		_microstop_lbl.add_theme_color_override("font_color", COL_ACCENT)
	else:
		_microstop_lbl.add_theme_color_override("font_color", COL_GREY_LABEL)

func _fmt(v: float) -> String:
	# Integers print clean; fractional values get one decimal.
	if absf(v - roundf(v)) < 0.05:
		return "%d" % int(roundf(v))
	return "%.1f" % v

# =============================================================================
func _process(delta: float) -> void:
	if _microstop_flash > 0.0:
		_microstop_flash -= delta
		if _microstop_flash <= 0.0:
			_microstop_flash = 0.0
			_refresh_microstop_counter()
