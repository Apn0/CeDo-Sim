extends Control
class_name LaserFilterScope

## EREMA laser-filter HMI screen (matches the photo in 3A_HMI_laserfilter_screen.png).
##
## Layout:
##   ┌─────────────────────────────────────────────────────────────────────────┐
##   │  ┌──────────────────────────────────┐  ┌─────────────────────────────┐  │
##   │  │                                  │  │  MP < MF   [ 145 ] bar      │  │
##   │  │   3-trace rolling chart          │  │  ▮▮▮▮▮▮▮▯▯                  │  │
##   │  │   yellow = melt T   °C           │  │  ΔMP       [   3 ] bar      │  │
##   │  │   red    = ΔMP      bar          │  │  ▮▮▯▯▯▯▯▯▯▯                 │  │
##   │  │   blue   = motor 1  rpm          │  │  MP > MF   [ 142 ] bar      │  │
##   │  │                                  │  │  ▮▮▮▮▮▮▮▯▯                  │  │
##   │  │  ─── legend ───                  │  │                             │  │
##   │  │                                  │  │  [ disc schematic ]         │  │
##   │  └──────────────────────────────────┘  └─────────────────────────────┘  │
##   │  ◯ Motor  On                                                            │
##   │  ──────────────────────────────────────────────────────────────────────  │
##   │  [🏠]  [→◇→]  [🔔]  [Rx]  [📈]  [🔧]                                    │
##   └─────────────────────────────────────────────────────────────────────────┘
##
## Bind a live LaserFilter via `set_filter(filter)`. The chart polls the model
## every _process tick and appends to rolling buffers; the pressure boxes show
## current values with a green/yellow/red colour-band on the bar gauge.
##
## Units:
##   * LaserFilter exposes pressures in PSI (`upstream_pressure_psi_indicator`,
##     `delta_p_psi`). This screen displays in BAR — convert via PSI_TO_BAR.
##   * Motor 1 speed comes from `scraper_rpm` (the operator's setpoint, already
##     in real RPM).
##   * Melt temperature isn't tracked on LaserFilter itself — we read the
##     upstream ExtruderModel via `_filter.get_node_or_null('../ExtruderModel')`
##     if available; otherwise the trace falls back to a derived value from
##     the boost state (boost active = ~225 °C, idle = ~210 °C with noise).
##
## Signals:
##   request_close()   — fired by the 🏠 home button (header back-out)
##   request_advance() — fired by the →◇→ button (forces a _disc_advance on
##                       the parent LaserFilter)

signal request_close()
signal request_advance()

# ── Public bindings ──────────────────────────────────────────────────────────
@export var filter_id : String = "MPF1"

# ── Constants ────────────────────────────────────────────────────────────────
const PSI_TO_BAR : float = 0.0689
const CHART_WINDOW_S : float = 30.0 * 60.0   # 30-min rolling window
const CHART_SAMPLE_HZ : float = 2.0          # 2 samples/s → ~3600 points/window
const CHART_MAX_SAMPLES : int = 3700

# Y-axis ranges (matches the photo).
const TEMP_MIN_C : float = 0.0
const TEMP_MAX_C : float = 350.0
const PRESSURE_MIN_BAR : float = 0.0
# #223 docs->code docs/plant/hmi_reference.md — photo chart axis is 0-350 bar
# (real running values: MP<MF 207 bar, dMP 182 bar). Old 0-10 scale pinned the trace.
const PRESSURE_MAX_BAR : float = 350.0
const MOTOR_MIN_RPM : float = 0.0
const MOTOR_MAX_RPM : float = 60.0           # LaserFilter.MAX_SCRAPER_RPM

# Pressure colour bands (bar).
# #223 docs->code docs/plant/swi/laserfilter-smeltdrukverschil__062_CeDo72.md —
# Grenswaarden 0-300 bar, upstream trip at 318 bar (plant setting; manual says 320).
# Normal running is 182-207 bar (hmi_reference.md) so: green ≤250, yellow 250-300, red >300.
const PRESS_GREEN_MAX  : float = 250.0
const PRESS_YELLOW_MAX : float = 300.0

# Trace colours.
const COL_TEMP   : Color = Color(1.00, 0.85, 0.05, 1.0)  # yellow
const COL_DELTA  : Color = Color(0.95, 0.30, 0.20, 1.0)  # red
const COL_MOTOR  : Color = Color(0.25, 0.55, 0.95, 1.0)  # blue

# Chassis palette (matches HmiOverlay).
const C_BEZEL    : Color = Color(0.10, 0.13, 0.14, 1.0)
const C_SCREEN   : Color = Color(0.05, 0.07, 0.08, 1.0)
const C_TILE     : Color = Color(0.18, 0.21, 0.23, 1.0)
const C_TILE_EDGE: Color = Color(0.40, 0.45, 0.45, 1.0)
const C_TEXT     : Color = Color(0.92, 0.95, 0.95, 1.0)
const C_TEXT_DIM : Color = Color(0.65, 0.70, 0.70, 1.0)
const C_GRID     : Color = Color(0.20, 0.24, 0.26, 1.0)
const C_AXIS     : Color = Color(0.55, 0.60, 0.60, 1.0)
const LAMP_OFF   : Color = Color(0.42, 0.45, 0.43, 1.0)
const LAMP_RUN   : Color = Color(0.22, 0.85, 0.32, 1.0)

# ── State ────────────────────────────────────────────────────────────────────
var _filter : LaserFilter = null

# Rolling sample buffers (parallel arrays — same length).
var _t_buf       : PackedFloat32Array = PackedFloat32Array()   # sim time (s)
var _temp_buf    : PackedFloat32Array = PackedFloat32Array()   # melt °C
var _delta_buf   : PackedFloat32Array = PackedFloat32Array()   # ΔMP bar
var _motor_buf   : PackedFloat32Array = PackedFloat32Array()   # motor 1 rpm
var _sim_time_s  : float = 0.0
var _sample_acc  : float = 0.0

# UI refs built in _ready.
var _chart        : Control = null
var _legend       : Label = null
var _press_inlet  : PressureBox = null
var _press_delta  : PressureBox = null
var _press_outlet : PressureBox = null
# #223 docs->code swi/laserfilter-smeltdrukverschil__062_CeDo72.md — dMP-MF1 setpoint readout box.
var _press_setpt  : PressureBox = null
var _motor_lamp   : ColorRect = null
var _motor_lbl    : Label = null
var _title_lbl    : Label = null

# Live readout cache (avoid recomputing in _draw).
var _cur_temp_c   : float = 210.0
var _cur_delta_bar: float = 0.0
var _cur_motor_rpm: float = 0.0
var _cur_inlet_bar: float = 0.0

# ── Lifecycle ────────────────────────────────────────────────────────────────
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func _process(delta: float) -> void:
	_sim_time_s += delta
	_sample_acc += delta
	# Always pull current values for the live readouts (cheap).
	_pull_telemetry()
	# Append to rolling buffer at CHART_SAMPLE_HZ (don't bloat the chart).
	var sample_interval : float = 1.0 / CHART_SAMPLE_HZ
	if _sample_acc >= sample_interval:
		_sample_acc = 0.0
		_append_sample()
	# Update read-out widgets every frame so the numbers feel live.
	_refresh_readouts()
	# Repaint the chart trace.
	if _chart != null and is_instance_valid(_chart):
		_chart.queue_redraw()

# ── Public API ───────────────────────────────────────────────────────────────
## Bind a LaserFilter to this scope. Resets the rolling buffers so we don't
## carry samples from a previous filter into the new chart.
func set_filter(f: LaserFilter) -> void:
	_filter = f
	_t_buf.clear()
	_temp_buf.clear()
	_delta_buf.clear()
	_motor_buf.clear()
	_sim_time_s = 0.0
	_sample_acc = 0.0
	if _title_lbl != null and is_instance_valid(_title_lbl):
		_title_lbl.text = "LASERFILTER  %s" % filter_id

# ── Telemetry pulls ──────────────────────────────────────────────────────────
func _pull_telemetry() -> void:
	if _filter == null or not is_instance_valid(_filter):
		# Keep last values; chart stays flat-line.
		return
	# ── ΔMP (the headline pressure) — psi → bar.
	_cur_delta_bar = _filter.delta_p_psi * PSI_TO_BAR
	# ── Inlet pressure (MP < MF) — upstream proxy reported by ExtruderMachine.
	_cur_inlet_bar = _filter.upstream_pressure_psi_indicator * PSI_TO_BAR
	# ── Motor 1 speed = disc-motor rpm (operator setpoint; #223 — no ΔP boost).
	_cur_motor_rpm = clampf(_filter.scraper_rpm, 0.0, LaserFilter.MAX_SCRAPER_RPM)
	# ── Melt temperature: LaserFilter doesn't track this, so probe the parent
	# ExtruderModel/ExtruderMachine via siblings. Fall back to a synthetic
	# value tied to the boost state so the yellow trace still moves.
	_cur_temp_c = _resolve_melt_temp_c()

func _resolve_melt_temp_c() -> float:
	if _filter == null or not is_instance_valid(_filter):
		return _cur_temp_c
	# Walk siblings under the same parent (the extruder unit macro lays the
	# laser filter and extruder model under the same Node3D parent). Look for
	# a node carrying `melt_temp_c` or a `get_melt_temp` accessor.
	var parent : Node = _filter.get_parent()
	if parent != null:
		for sib in parent.get_children():
			if sib == _filter:
				continue
			if "melt_temp_c" in sib:
				return float(sib.get("melt_temp_c"))
			if sib.has_method("get_melt_temp"):
				return float(sib.call("get_melt_temp"))
	# Synthetic fallback: the rotor purge cycle gives the trace its sawtooth.
	# Base 210 °C, +15 °C while boost is latched, +2 °C noise from front loading.
	var base : float = 210.0
	var noise : float = sin(_sim_time_s * 0.6) * 2.0
	# A high front_loading_g means the cake is packing → small temp rise as
	# the melt has to push through tighter mesh.
	var pack_rise : float = clampf(_filter.front_loading_g * 0.02, 0.0, 8.0)
	return base + noise + pack_rise

func _append_sample() -> void:
	_t_buf.append(_sim_time_s)
	_temp_buf.append(_cur_temp_c)
	_delta_buf.append(_cur_delta_bar)
	_motor_buf.append(_cur_motor_rpm)
	# Trim by both age (older than the rolling window) AND hard cap.
	var oldest : float = _sim_time_s - CHART_WINDOW_S
	var drop : int = 0
	while drop < _t_buf.size() and _t_buf[drop] < oldest:
		drop += 1
	if drop > 0:
		_t_buf = _t_buf.slice(drop)
		_temp_buf = _temp_buf.slice(drop)
		_delta_buf = _delta_buf.slice(drop)
		_motor_buf = _motor_buf.slice(drop)
	if _t_buf.size() > CHART_MAX_SAMPLES:
		var over : int = _t_buf.size() - CHART_MAX_SAMPLES
		_t_buf = _t_buf.slice(over)
		_temp_buf = _temp_buf.slice(over)
		_delta_buf = _delta_buf.slice(over)
		_motor_buf = _motor_buf.slice(over)

# ── UI construction ──────────────────────────────────────────────────────────
var _ui_built : bool = false

func _build_ui() -> void:
	# Idempotency guard: the scope can re-enter the tree (HmiOverlay reopen)
	# and fire _ready() again, which re-ran the whole build and tried to re-add
	# the already-parented _chart → "already has a parent" crash. Build once.
	if _ui_built:
		return
	_ui_built = true
	# Bezel background.
	var bg := ColorRect.new()
	bg.color = C_BEZEL
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	# Outer margin so the chassis breathes.
	var outer := MarginContainer.new()
	outer.set_anchors_preset(Control.PRESET_FULL_RECT)
	outer.add_theme_constant_override("margin_left", 18)
	outer.add_theme_constant_override("margin_right", 18)
	outer.add_theme_constant_override("margin_top", 18)
	outer.add_theme_constant_override("margin_bottom", 18)
	add_child(outer)
	# Root VBox: title | main | nav.
	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 10)
	outer.add_child(root)
	# Title bar.
	_title_lbl = Label.new()
	_title_lbl.text = "LASERFILTER  %s" % filter_id
	_title_lbl.add_theme_font_size_override("font_size", 18)
	_title_lbl.add_theme_color_override("font_color", C_TEXT)
	root.add_child(_title_lbl)
	# Main row: chart on the left, pressure column + schematic on the right.
	var main := HBoxContainer.new()
	main.add_theme_constant_override("separation", 12)
	main.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	root.add_child(main)
	# Left column (chart + legend + motor lamp at the bottom).
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	left.size_flags_stretch_ratio = 2.0
	main.add_child(left)
	left.add_child(_build_chart())
	_legend = _build_legend()
	left.add_child(_legend)
	left.add_child(_build_motor_status_row())
	# Right column (3 pressure boxes + schematic).
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 10)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	right.size_flags_stretch_ratio = 1.0
	right.custom_minimum_size = Vector2(280, 0)
	main.add_child(right)
	_press_inlet  = _build_pressure_box("MP < MF", Color(0.55, 0.85, 0.95, 1.0))
	_press_delta  = _build_pressure_box("ΔMP",     COL_DELTA)
	_press_outlet = _build_pressure_box("MP > MF", Color(0.55, 0.85, 0.95, 1.0))
	right.add_child(_press_inlet)
	right.add_child(_press_delta)
	right.add_child(_press_outlet)
	# #223 docs->code — dMP-MF1 setpoint the disc-motor strategy targets (SWI Grenswaarden 0-300 bar).
	_press_setpt = _build_pressure_box("dMP-MF1 (0-300 bar)", Color(0.80, 0.75, 0.55, 1.0))
	right.add_child(_press_setpt)
	right.add_child(_build_schematic_placeholder())
	# Bottom nav strip.
	root.add_child(_build_nav_strip())

func _build_chart() -> Control:
	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_SCREEN
	sb.border_color = C_TILE_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	holder.add_theme_stylebox_override("panel", sb)
	# The custom-drawn surface. Subclass-pattern would be nicer, but we wire
	# the draw call via Control.draw and let queue_redraw drive repaint.
	_chart = Control.new()
	_chart.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_chart.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	_chart.custom_minimum_size = Vector2(0, 280)
	_chart.draw.connect(_draw_chart.bind(_chart))
	holder.add_child(_chart)
	return holder

func _build_legend() -> Label:
	var lbl := Label.new()
	lbl.text = "[yellow] Melt T (°C)     [red] ΔMP (bar)     [blue] Motor 1 (rpm)"
	lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	lbl.add_theme_font_size_override("font_size", 11)
	return lbl

func _build_motor_status_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var motor_title := Label.new()
	motor_title.text = "Motor"
	motor_title.add_theme_color_override("font_color", C_TEXT)
	motor_title.add_theme_font_size_override("font_size", 13)
	row.add_child(motor_title)
	_motor_lamp = ColorRect.new()
	_motor_lamp.color = LAMP_OFF
	_motor_lamp.custom_minimum_size = Vector2(16, 16)
	row.add_child(_motor_lamp)
	_motor_lbl = Label.new()
	_motor_lbl.text = "Off"
	_motor_lbl.add_theme_color_override("font_color", C_TEXT_DIM)
	_motor_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(_motor_lbl)
	return row

func _build_pressure_box(label_text: String, label_color: Color) -> PressureBox:
	# Inline subclass via the helper struct at the bottom of the file. A
	# PressureBox is a PanelContainer with `update(value_bar)` and renders a
	# bar gauge that turns green / yellow / red depending on band.
	var box := PressureBox.new()
	box.setup(label_text, label_color)
	return box

func _build_schematic_placeholder() -> Control:
	# Simple flat-rectangle schematic of the EREMA rotary disc filter. Not a
	# real 3D viewport — just a stylized icon so the screen looks alive when
	# you haven't bound a model yet.
	var holder := PanelContainer.new()
	holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	holder.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	holder.custom_minimum_size = Vector2(260, 120)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TILE
	sb.border_color = C_TILE_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	holder.add_theme_stylebox_override("panel", sb)
	var canvas := Control.new()
	canvas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	canvas.size_flags_vertical   = Control.SIZE_EXPAND_FILL
	canvas.draw.connect(_draw_schematic.bind(canvas))
	holder.add_child(canvas)
	return holder

func _build_nav_strip() -> Control:
	var bar := PanelContainer.new()
	bar.custom_minimum_size = Vector2(0, 50)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_TILE
	sb.border_color = C_TILE_EDGE
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	bar.add_child(row)
	# 🏠 Home — emits request_close.
	row.add_child(_nav_button("HOME", func(): request_close.emit()))
	# →◇→ Filter advance — emits request_advance.
	row.add_child(_nav_button("→◇→", func(): request_advance.emit()))
	# 🔔 Alarms — placeholder (would jump to STORINGEN in the parent overlay).
	row.add_child(_nav_button("ALARM", func(): pass))
	# Rx Recipe — placeholder.
	row.add_child(_nav_button("Rx", func(): pass))
	# 📈 Trend — placeholder (this screen IS the trend, so this is a no-op).
	row.add_child(_nav_button("TREND", func(): pass))
	# 🔧 Settings — placeholder.
	row.add_child(_nav_button("SET", func(): pass))
	return bar

func _nav_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(80, 36)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(on_press)
	return b

# ── Per-frame refresh ────────────────────────────────────────────────────────
func _refresh_readouts() -> void:
	if _press_inlet != null and is_instance_valid(_press_inlet):
		_press_inlet.update(_cur_inlet_bar)
	if _press_delta != null and is_instance_valid(_press_delta):
		_press_delta.update(_cur_delta_bar)
	if _press_outlet != null and is_instance_valid(_press_outlet):
		# Outlet = inlet - ΔMP, clamped to zero (can't go negative).
		_press_outlet.update(maxf(0.0, _cur_inlet_bar - _cur_delta_bar))
	# #223 docs->code — dMP-MF1 setpoint = the dP alarm threshold (SCRAPER_BOOST_PSI) in bar.
	if _press_setpt != null and is_instance_valid(_press_setpt):
		_press_setpt.update(LaserFilter.SCRAPER_BOOST_PSI * PSI_TO_BAR)
	# Motor lamp green when scraper is actually turning.
	if _motor_lamp != null and is_instance_valid(_motor_lamp):
		var running : bool = _cur_motor_rpm > 0.5 \
			and _filter != null and is_instance_valid(_filter) \
			and not _filter.is_halted \
			and not _filter.is_line_down()
		_motor_lamp.color = LAMP_RUN if running else LAMP_OFF
		if _motor_lbl != null and is_instance_valid(_motor_lbl):
			_motor_lbl.text = "On  (%d rpm)" % int(round(_cur_motor_rpm)) if running else "Off"

# ── Custom draw: 3-trace chart ───────────────────────────────────────────────
func _draw_chart(canvas: Control) -> void:
	var sz : Vector2 = canvas.size
	if sz.x < 4.0 or sz.y < 4.0:
		return
	# Inset for axis labels.
	var pad_l : float = 36.0
	var pad_r : float = 40.0
	var pad_t : float = 10.0
	var pad_b : float = 22.0
	var plot_x : float = pad_l
	var plot_y : float = pad_t
	var plot_w : float = sz.x - pad_l - pad_r
	var plot_h : float = sz.y - pad_t - pad_b
	if plot_w < 8.0 or plot_h < 8.0:
		return
	# Background grid.
	var grid_steps : int = 6
	for i in grid_steps + 1:
		var gy : float = plot_y + plot_h * float(i) / float(grid_steps)
		canvas.draw_line(Vector2(plot_x, gy), Vector2(plot_x + plot_w, gy), C_GRID, 1.0)
	var grid_steps_x : int = 6
	for i in grid_steps_x + 1:
		var gx : float = plot_x + plot_w * float(i) / float(grid_steps_x)
		canvas.draw_line(Vector2(gx, plot_y), Vector2(gx, plot_y + plot_h), C_GRID, 1.0)
	# Y-axes.
	canvas.draw_line(Vector2(plot_x, plot_y), Vector2(plot_x, plot_y + plot_h), C_AXIS, 1.0)
	canvas.draw_line(Vector2(plot_x + plot_w, plot_y), Vector2(plot_x + plot_w, plot_y + plot_h), C_AXIS, 1.0)
	# X-axis baseline.
	canvas.draw_line(Vector2(plot_x, plot_y + plot_h), Vector2(plot_x + plot_w, plot_y + plot_h), C_AXIS, 1.0)
	# Axis labels (LEFT = °C, RIGHT = bar / rpm).
	var font := ThemeDB.fallback_font
	var fsz : int = 10
	if font != null:
		# Left axis ticks (0 / 175 / 350 °C).
		canvas.draw_string(font, Vector2(2, plot_y + 8), "%d" % int(TEMP_MAX_C), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_TEMP)
		canvas.draw_string(font, Vector2(2, plot_y + plot_h * 0.5 + 4), "%d" % int((TEMP_MIN_C + TEMP_MAX_C) * 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_TEMP)
		canvas.draw_string(font, Vector2(2, plot_y + plot_h - 2), "%d" % int(TEMP_MIN_C), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_TEMP)
		# Right axis ticks (bar). Motor RPM shares the right axis with its own
		# scaling label below.
		canvas.draw_string(font, Vector2(plot_x + plot_w + 4, plot_y + 8), "%d" % int(PRESSURE_MAX_BAR), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_DELTA)
		canvas.draw_string(font, Vector2(plot_x + plot_w + 4, plot_y + plot_h * 0.5 + 4), "%d" % int((PRESSURE_MIN_BAR + PRESSURE_MAX_BAR) * 0.5), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_DELTA)
		canvas.draw_string(font, Vector2(plot_x + plot_w + 4, plot_y + plot_h - 2), "%d" % int(PRESSURE_MIN_BAR), HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, COL_DELTA)
		# X-axis label.
		canvas.draw_string(font, Vector2(plot_x + plot_w * 0.5 - 30, plot_y + plot_h + 16), "30 min rolling", HORIZONTAL_ALIGNMENT_LEFT, -1, fsz, C_TEXT_DIM)
	# Trace plotting — need enough samples to draw a line.
	var n : int = _t_buf.size()
	if n < 2:
		return
	# Window bounds for X normalisation: oldest sample → newest sample.
	var t0 : float = _t_buf[0]
	var t1 : float = _t_buf[n - 1]
	var span : float = maxf(0.001, t1 - t0)
	# Helper to convert a (time, value, value_min, value_max) sample to pixel space.
	# Inlined as 3 loops below for perf (no per-sample Callable indirection).
	var pts_temp : PackedVector2Array = PackedVector2Array()
	var pts_delta : PackedVector2Array = PackedVector2Array()
	var pts_motor : PackedVector2Array = PackedVector2Array()
	pts_temp.resize(n)
	pts_delta.resize(n)
	pts_motor.resize(n)
	for i in n:
		var fx : float = plot_x + plot_w * (_t_buf[i] - t0) / span
		# Temperature on left axis (0..350 °C).
		var ty : float = plot_y + plot_h * (1.0 - clampf(
			(_temp_buf[i] - TEMP_MIN_C) / (TEMP_MAX_C - TEMP_MIN_C), 0.0, 1.0))
		pts_temp[i] = Vector2(fx, ty)
		# ΔMP on right axis (0..10 bar).
		var dy : float = plot_y + plot_h * (1.0 - clampf(
			(_delta_buf[i] - PRESSURE_MIN_BAR) / (PRESSURE_MAX_BAR - PRESSURE_MIN_BAR), 0.0, 1.0))
		pts_delta[i] = Vector2(fx, dy)
		# Motor RPM mapped onto the right axis (0..MAX_SCRAPER_RPM → 0..10 bar
		# visual range — they're co-located, the legend says what's what).
		var my : float = plot_y + plot_h * (1.0 - clampf(
			(_motor_buf[i] - MOTOR_MIN_RPM) / (MOTOR_MAX_RPM - MOTOR_MIN_RPM), 0.0, 1.0))
		pts_motor[i] = Vector2(fx, my)
	canvas.draw_polyline(pts_temp,  COL_TEMP,  1.5)
	canvas.draw_polyline(pts_delta, COL_DELTA, 1.5)
	canvas.draw_polyline(pts_motor, COL_MOTOR, 1.5)

func _draw_schematic(canvas: Control) -> void:
	var sz : Vector2 = canvas.size
	if sz.x < 8.0 or sz.y < 8.0:
		return
	# Housing rectangle (steel grey).
	var housing := Rect2(Vector2(sz.x * 0.10, sz.y * 0.20), Vector2(sz.x * 0.55, sz.y * 0.60))
	canvas.draw_rect(housing, Color(0.55, 0.58, 0.60, 1.0), true)
	canvas.draw_rect(housing, C_TILE_EDGE, false, 1.5)
	# Disc inside housing (concentric circles).
	var disc_center := housing.position + housing.size * 0.5
	var disc_r : float = min(housing.size.x, housing.size.y) * 0.40
	canvas.draw_circle(disc_center, disc_r, Color(0.78, 0.80, 0.82, 1.0))
	canvas.draw_arc(disc_center, disc_r, 0.0, TAU, 32, C_TILE_EDGE, 1.5)
	canvas.draw_circle(disc_center, disc_r * 0.18, Color(0.30, 0.32, 0.34, 1.0))
	# Eight orifice marks around the disc.
	for i in 8:
		var ang : float = TAU * float(i) / 8.0
		var o := disc_center + Vector2(cos(ang), sin(ang)) * disc_r * 0.65
		canvas.draw_circle(o, disc_r * 0.06, Color(0.10, 0.12, 0.14, 1.0))
	# Motor block on the right (a small dark rectangle with a shaft into the housing).
	var motor_rect := Rect2(Vector2(sz.x * 0.70, sz.y * 0.35), Vector2(sz.x * 0.22, sz.y * 0.30))
	canvas.draw_rect(motor_rect, Color(0.30, 0.32, 0.34, 1.0), true)
	canvas.draw_rect(motor_rect, C_TILE_EDGE, false, 1.5)
	# Shaft.
	var shaft_y : float = motor_rect.position.y + motor_rect.size.y * 0.5
	canvas.draw_line(Vector2(housing.end.x, shaft_y),
					Vector2(motor_rect.position.x, shaft_y),
					Color(0.65, 0.68, 0.70, 1.0), 3.0)
	# Inlet pipe nub on the left.
	var inlet_y : float = housing.position.y + housing.size.y * 0.5
	canvas.draw_line(Vector2(0.0, inlet_y), Vector2(housing.position.x, inlet_y),
					Color(0.50, 0.85, 0.95, 1.0), 3.0)
	# Discharge nub at the bottom (where the sausage drops).
	var disch_x : float = housing.position.x + housing.size.x * 0.5
	canvas.draw_line(Vector2(disch_x, housing.end.y), Vector2(disch_x, sz.y),
					Color(0.95, 0.45, 0.20, 1.0), 3.0)

# =============================================================================
# Inner class — pressure read-out box (label + big number + bar gauge).
# =============================================================================
class PressureBox extends PanelContainer:
	# #223 docs->code docs/plant/hmi_reference.md + swi/laserfilter-smeltdrukverschil__062_CeDo72.md
	# Grenswaarden 0-300 bar, upstream trip 318 bar; normal run 182-207 bar.
	# Bands: green <=250, yellow 250-300, red >300 (approaching the 318-bar trip).
	const PRESS_GREEN_MAX  : float = 250.0
	const PRESS_YELLOW_MAX : float = 300.0
	const PRESSURE_MAX_BAR : float = 350.0     # display scale of the bar gauge (photo axis 0-350)

	const C_TILE     : Color = Color(0.18, 0.21, 0.23, 1.0)
	const C_TILE_EDGE: Color = Color(0.40, 0.45, 0.45, 1.0)
	const C_TEXT     : Color = Color(0.92, 0.95, 0.95, 1.0)
	const C_TEXT_DIM : Color = Color(0.65, 0.70, 0.70, 1.0)

	var _label : Label = null
	var _value : Label = null
	var _unit  : Label = null
	var _gauge : Control = null
	var _value_bar : float = 0.0
	var _label_color : Color = Color(0.55, 0.85, 0.95, 1.0)

	func setup(label_text: String, label_color: Color) -> void:
		_label_color = label_color
		custom_minimum_size = Vector2(0, 86)
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_TILE
		sb.border_color = C_TILE_EDGE
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		add_theme_stylebox_override("panel", sb)
		var inner := MarginContainer.new()
		inner.add_theme_constant_override("margin_left", 10)
		inner.add_theme_constant_override("margin_right", 10)
		inner.add_theme_constant_override("margin_top", 6)
		inner.add_theme_constant_override("margin_bottom", 6)
		add_child(inner)
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 2)
		inner.add_child(col)
		# Top row: label + big numeric value + unit.
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(row)
		_label = Label.new()
		_label.text = label_text
		_label.add_theme_color_override("font_color", _label_color)
		_label.add_theme_font_size_override("font_size", 13)
		_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(_label)
		_value = Label.new()
		_value.text = "  0"
		_value.add_theme_color_override("font_color", C_TEXT)
		_value.add_theme_font_size_override("font_size", 24)
		_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_value.custom_minimum_size = Vector2(70, 0)
		row.add_child(_value)
		_unit = Label.new()
		_unit.text = "bar"
		_unit.add_theme_color_override("font_color", C_TEXT_DIM)
		_unit.add_theme_font_size_override("font_size", 12)
		row.add_child(_unit)
		# Bar gauge below.
		_gauge = Control.new()
		_gauge.custom_minimum_size = Vector2(0, 14)
		_gauge.draw.connect(_draw_gauge)
		col.add_child(_gauge)

	func update(value_bar: float) -> void:
		_value_bar = value_bar
		if _value != null:
			_value.text = "%4d" % int(round(value_bar))
		if _gauge != null:
			_gauge.queue_redraw()

	func _band_color() -> Color:
		# #223 docs->code hmi_reference.md: green <=250, yellow 250-300, red >300 bar (318-bar trip).
		if _value_bar < PRESS_GREEN_MAX:
			return Color(0.22, 0.78, 0.32, 1.0)
		elif _value_bar < PRESS_YELLOW_MAX:
			return Color(0.95, 0.80, 0.15, 1.0)
		return Color(0.95, 0.30, 0.20, 1.0)

	func _draw_gauge() -> void:
		if _gauge == null:
			return
		var sz : Vector2 = _gauge.size
		if sz.x < 4.0 or sz.y < 2.0:
			return
		# Frame.
		_gauge.draw_rect(Rect2(Vector2.ZERO, sz), Color(0.08, 0.10, 0.11, 1.0), true)
		_gauge.draw_rect(Rect2(Vector2.ZERO, sz), C_TILE_EDGE, false, 1.0)
		# Fill — clamp to gauge scale (PRESSURE_MAX_BAR ⇒ full bar).
		var f : float = clampf(_value_bar / PRESSURE_MAX_BAR, 0.0, 1.0)
		var fill := Rect2(Vector2(1.0, 1.0), Vector2((sz.x - 2.0) * f, sz.y - 2.0))
		_gauge.draw_rect(fill, _band_color(), true)
