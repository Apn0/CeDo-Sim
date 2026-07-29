extends Control
class_name HmiScreenBase

# ---------------------------------------------------------------------------
# SHARED CHROME for the operator's L&P / Siemens SIMATIC screens on line 3C.
#
# WHY THIS EXISTS
# ---------------
# The plant export is 34 screens (docs/plant/hmi_screens_2026-07-26/).  Thirteen
# of them are per-unit detail screens that share the SAME four bands — the L&P
# header with its three status chips and Dutch clock, the amber alarm strip, the
# mimic pane, and the twelve-key bottom nav — and differ only in the pane
# between them.  WashingScope.gd alone is 985 lines; copying its chrome twelve
# more times would mean thirteen copies of one palette and one nav bar.
#
# This repo has been bitten by exactly that before (docs: the stale-constant
# class of bug, where geometry is hand-baked in one place and measured in
# another, and the two silently drift).  So the chrome lives here ONCE.
#
# WHAT DELIBERATELY DOES *NOT* LIVE HERE
# --------------------------------------
# Citations.  Every screen cites its own mockup by line number, and those line
# numbers differ per file (the header chips are :24/:27/:30 in Overzicht but
# :19/:20/:21 in L3C.4 Frictiescheider).  A shared cite would be wrong on twelve
# screens out of thirteen, so the builders below take their content as arguments
# and each screen keeps its own const block with its own cites.
#
# Dutch labels, likewise.  The real screens are NOT internally consistent —
# L3C.1 says "Safety zone was"/"Safety zone voorwas" where L3C.4 says "Safety
# zone wash"/"Safety zone prewash"; L3C.3 says "Peddelwalzen" where L3C.11 says
# "Peddelwals 1,2,3,4".  Those are the operator's real screens and the
# difference is data, not noise.  Nothing here may normalise them, and
# src/tests/test_l3c_unit_screens.gd asserts the divergence survives.
#
# THE HONESTY RULE (inherited by every screen)
# --------------------------------------------
# Every rendered process value is either
#   (a) BOUND      — resolved through TagMap over LineFlow.get_machine_info(),
#                    carrying the operator's own verbatim tag string, or
#   (b) UNAVAILABLE — rendered as the literal "--" (UNAVAIL) with a recorded
#                    reason, never as a plausible number.
# field_report() returns both lists so a headless test can assert the split
# instead of trusting it.
# ---------------------------------------------------------------------------

## Emitted when the operator dismisses the screen (X key or Escape).
signal request_close

# ---------------------------------------------------------------------------
# Palette — hex values taken verbatim from the mockups' inline styles.
#
# MEASURED, not assumed.  `python tools/hmi/palette_census.py` censuses the 16
# "Waslijn 3C *" screens and fails if one of them uses a hex no constant here
# declares.  Result 2026-07-29: 49 distinct hexes over the family, of which the
# 24 below are the shared chrome — each used by 12 to 16 of the 16 screens.
#
# The first draft of this comment claimed the palette was identical across all
# 34 exported screens.  The census refuted that immediately: over all 34 there
# are 269 distinct hexes, because the export also contains BRITAS, EREMA,
# BluPort, MAS DRD, COAD, WEIMA and Sorteerlijn screens — other vendors' HMIs
# with their own house styles.  Run the census with --all to see it.
#
# What is NOT here, deliberately: per-screen content colours, e.g. the greys and
# golds of the machine SVG hand-drawn into L3C.14 Rechts (each used by exactly
# one screen), and #f0f2ee, the silo-level graphic ground on L3C.1 and L3C.18.
# Those belong to the screen that draws them, not to the chrome.
# ---------------------------------------------------------------------------

const C_MIMIC_BG    : Color = Color("#1a1008")   # dark-brown mimic field
const C_SCREEN_BG   : Color = Color("#2a2e36")   # page background
const C_HEADER_BG   : Color = Color("#2a2e36")   # L&P bar, alarm strip
const C_HEADER_EDGE : Color = Color("#3a3f47")
const C_TEXT        : Color = Color("#e8ecf2")
const C_GREEN       : Color = Color("#35c23a")   # status chip / run square
const C_CHIP_FG     : Color = Color("#111111")
const C_AMBER       : Color = Color("#e6b84a")   # alarm strip text
const C_PANEL_BG    : Color = Color("#c8cdd6")   # unit detail panel face
const C_PANEL_EDGE  : Color = Color("#9aa4b0")
const C_BTN_GREY    : Color = Color("#6a7a8a")   # inactive Hand/Start key
const C_BOX_BG      : Color = Color("#ffffff")   # value box
const C_BOX_FG      : Color = Color("#111111")
const C_BOX_EDGE    : Color = Color("#aaaaaa")
const C_CHECK_EDGE  : Color = Color("#888888")   # OFF-checkbox ring, 13/16 screens
const C_NAV_BG      : Color = Color("#eef1f5")
const C_NAV_KEY     : Color = Color("#ffffff")
const C_NAV_EDGE    : Color = Color("#9aa0aa")
const C_NAV_FG      : Color = Color("#20242a")
const C_NAV_HOME    : Color = Color("#4a5a7a")
const C_NAV_ALARM   : Color = Color("#e8c040")
const C_LOGO_A      : Color = Color("#2f6fb0")   # L&P chevron
const C_LOGO_B      : Color = Color("#3a4a5a")
const C_LAMP_EDGE   : Color = Color("#1f8a20")   # safety lamp ring, lit green
const C_RED         : Color = Color("#e02020")   # lamp fill, fault/not-safe
const C_RED_EDGE    : Color = Color("#a02020")   # lamp ring, fault/not-safe
const C_UNAVAIL     : Color = Color("#8a929c")   # sim-side: an unbound field

## The literal every unbound field renders.  Never a number, never a blank.
const UNAVAIL : String = "--"

## Verbatim chip labels.  Identical on every 3C screen checked; the CITES are
## not, which is why they are supplied per screen rather than held here.
const CHIP_LIJN : String = "Status Lijn 3C"
const CHIP_WAS  : String = "Status was"
const CHIP_SILO : String = "Status Silo"

const NL_WEEKDAYS : Array = ["zondag", "maandag", "dinsdag", "woensdag",
	"donderdag", "vrijdag", "zaterdag"]
const NL_MONTHS : Array = ["januari", "februari", "maart", "april", "mei", "juni",
	"juli", "augustus", "september", "oktober", "november", "december"]

# ---------------------------------------------------------------------------
# Audit state
# ---------------------------------------------------------------------------

var _bound   : Array[Dictionary] = []
var _unavail : Array[Dictionary] = []

# Widget registries, keyed so rendered_text() can answer for any screen.
var _status_dots : Dictionary = {}       # key -> ColorRect
var _amp_labels  : Dictionary = {}       # key -> Label
var _chip_labels : Dictionary = {}       # chip label -> Label
var _value_boxes : Dictionary = {}       # key -> Label (timer / setpoint boxes)
var _lamps       : Dictionary = {}       # verbatim label -> ColorRect

var _alarm_nr_lbl  : Label = null
var _alarm_txt_lbl : Label = null
var _clock_lbl     : Label = null
var _audit_lbl     : Label = null

var _clock_accum : float = 1.0

# ---------------------------------------------------------------------------
# Audit surface
# ---------------------------------------------------------------------------

## Overridden per screen with the MEASURED count, never a predicted one.
func _expected_bound() -> int:
	return 0

## Overridden per screen with the MEASURED count, never a predicted one.
func _expected_unavail() -> int:
	return 0

## {bound:[...], unavailable:[...], bound_count, unavailable_count, total,
## expected_bound, expected_unavailable}.  Each bound row carries the operator's
## verbatim tag, TagMap's own source_field expression and the value actually
## rendered; each unavailable row carries a reason string.
func field_report() -> Dictionary:
	return {
		"bound": _bound.duplicate(true),
		"unavailable": _unavail.duplicate(true),
		"bound_count": _bound.size(),
		"unavailable_count": _unavail.size(),
		"total": _bound.size() + _unavail.size(),
		"expected_bound": _expected_bound(),
		"expected_unavailable": _expected_unavail(),
	}

func _mark_unavail(field: String, code: String, cite: String, reason: String) -> void:
	_unavail.append({"field": field, "code": code, "cite": cite, "reason": reason})

## The text currently painted for a field key ("status:L3C.6" / "stroom:L3C.6" /
## "chip:Status was" / "box:StartTijd.gewenst" / "lamp:Deur Molen" / "alarm").
## Lets a test assert what the OPERATOR sees, not just what the audit claims.
func rendered_text(field_key: String) -> String:
	var parts := field_key.split(":", true, 1)
	var kind := String(parts[0])
	var arg := String(parts[1]) if parts.size() > 1 else ""
	match kind:
		"status":
			var dot : ColorRect = _status_dots.get(arg, null)
			if dot == null:
				return ""
			return String(dot.get_meta("render_text", ""))
		"stroom":
			var lbl : Label = _amp_labels.get(arg, null)
			return lbl.text if lbl != null else ""
		"chip":
			var clbl : Label = _chip_labels.get(arg, null)
			return clbl.text if clbl != null else ""
		"box":
			var blbl : Label = _value_boxes.get(arg, null)
			return blbl.text if blbl != null else ""
		"lamp":
			var lamp : ColorRect = _lamps.get(arg, null)
			if lamp == null:
				return ""
			return String(lamp.get_meta("render_text", ""))
		"alarm":
			return _alarm_nr_lbl.text if _alarm_nr_lbl != null else ""
	return ""

# ---------------------------------------------------------------------------
# Chrome band 1 — L&P header with chips + Dutch clock
# ---------------------------------------------------------------------------

## `chips` is an Array of {label:String} in left-to-right order.  The caller owns
## the cites; this only draws.  All chips render UNAVAIL until a screen proves it
## has a real source for them — see the note in each screen's refresh().
func _build_header_bar(chips: Array) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 46)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_HEADER_BG
	sb.border_color = C_HEADER_EDGE
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 14)
	pc.add_child(h)

	# L&P chevron logo — two nested triangles.
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(36, 28)
	logo.draw.connect(func() -> void:
		logo.draw_colored_polygon(PackedVector2Array([
			Vector2(8, 2), Vector2(18, 14), Vector2(8, 26)]), C_LOGO_A)
		logo.draw_colored_polygon(PackedVector2Array([
			Vector2(16, 2), Vector2(26, 14), Vector2(16, 26)]), C_LOGO_B)
	)
	h.add_child(logo)

	h.add_child(_mklabel("L&P", 14, C_TEXT))

	# The photo stacks "Status Lijn 3C" over "Status was" as a left-centre pair
	# with "Status Silo" separately to their right; the mockups lay all three in
	# one flex row.  The photo layout is followed.
	if chips.size() >= 2:
		var pair := VBoxContainer.new()
		pair.add_theme_constant_override("separation", 2)
		pair.add_child(_build_chip(chips[0]))
		pair.add_child(_build_chip(chips[1]))
		h.add_child(pair)
	for i in range(2, chips.size()):
		var wrap := VBoxContainer.new()
		wrap.alignment = BoxContainer.ALIGNMENT_CENTER
		wrap.add_child(_build_chip(chips[i]))
		h.add_child(wrap)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(spacer)

	_clock_lbl = _mklabel("", 12, C_TEXT)
	_clock_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_clock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	h.add_child(_clock_lbl)
	_update_clock()

	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(32, 26)
	close_btn.pressed.connect(func() -> void: request_close.emit())
	h.add_child(close_btn)
	return pc

func _build_chip(chip: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_mklabel(String(chip["label"]), 12, C_TEXT))
	var val := _mklabel(UNAVAIL, 12, C_CHIP_FG)
	val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val.custom_minimum_size = Vector2(64, 18)
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	# Unbound: neutral grey, NOT the mockup's green — a green chip here would
	# assert a state the sim does not have.
	sb.bg_color = C_UNAVAIL
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(val)
	row.add_child(box)
	_chip_labels[String(chip["label"])] = val
	return row

# ---------------------------------------------------------------------------
# Chrome band 2 — amber alarm strip
# ---------------------------------------------------------------------------

## `reason` is why the strip cannot show a real alarm.  No wash-line fault source
## exists (src/sim/EremaFaultRegistry.gd covers the EREMA extruder codes only and
## has no L3C entry), so every screen states that rather than replaying the
## latched alarm frozen into its mockup.
func _build_alarm_strip(reason: String) -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 22)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_HEADER_BG
	sb.border_color = C_HEADER_EDGE
	sb.border_width_bottom = 1
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	pc.add_theme_stylebox_override("panel", sb)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	pc.add_child(h)
	_alarm_nr_lbl = _mklabel(UNAVAIL, 12, C_UNAVAIL)
	_alarm_nr_lbl.custom_minimum_size = Vector2(34, 0)
	h.add_child(_alarm_nr_lbl)
	_alarm_txt_lbl = _mklabel(reason, 12, C_UNAVAIL)
	h.add_child(_alarm_txt_lbl)
	return pc

# ---------------------------------------------------------------------------
# Chrome band 4 — audit strip (sim-side, not on the real panel)
# ---------------------------------------------------------------------------

func _build_audit_strip() -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 20)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_HEADER_BG
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	pc.add_theme_stylebox_override("panel", sb)
	_audit_lbl = _mklabel("", 11, C_UNAVAIL)
	pc.add_child(_audit_lbl)
	return pc

# ---------------------------------------------------------------------------
# Chrome band 5 — the twelve-key bottom nav
# ---------------------------------------------------------------------------

## Structurally identical on every exported screen.  The real bar also carries
## FIVE blank/unassigned keys the mockups omit (one after home, four after "Stop
## Runtime") — they are not drawn because their count is the only thing known
## about them.  The four emoji keys in the mockups are the mockups' own stand-ins;
## the photo shows report / two-person / wrench / triangle-A glyphs, so they are
## drawn as unlabelled keys rather than as invented text.  Every key is DISABLED:
## none of them is wired to anything.
func _build_nav_bar() -> Control:
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(0, 44)
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_NAV_BG
	sb.border_color = Color("#b8bfc9")
	sb.border_width_top = 1
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	pc.add_theme_stylebox_override("panel", sb)

	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 4)
	pc.add_child(h)

	var keys : Array = [
		{"t": "<",             "w": 36.0, "bg": C_NAV_KEY},   # verbatim glyph is a left triangle
		{"t": "",              "w": 40.0, "bg": C_NAV_HOME},  # home
		{"t": "Clean\nscreen", "w": 60.0, "bg": C_NAV_KEY},
		{"t": "Stop\nRuntime", "w": 50.0, "bg": C_NAV_KEY},
		{"t": "",              "w": 0.0,  "bg": C_NAV_KEY, "spacer": true},
		{"t": "",              "w": 40.0, "bg": C_NAV_KEY},   # report glyph
		{"t": "",              "w": 40.0, "bg": C_NAV_KEY},   # two-person glyph
		{"t": "Logout",        "w": 56.0, "bg": C_NAV_KEY},
		{"t": "Reset",         "w": 50.0, "bg": C_NAV_KEY},
		{"t": "",              "w": 36.0, "bg": C_NAV_KEY},   # wrench glyph
		{"t": "",              "w": 36.0, "bg": C_NAV_ALARM}, # triangle-A glyph
		{"t": ">",             "w": 36.0, "bg": C_NAV_KEY},
	]
	for k in keys:
		if bool(k.get("spacer", false)):
			var sp := Control.new()
			sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			h.add_child(sp)
			continue
		var b := Button.new()
		b.text = String(k["t"])
		b.custom_minimum_size = Vector2(float(k["w"]), 0)
		b.disabled = true
		b.tooltip_text = "niet gekoppeld"
		var bsb := StyleBoxFlat.new()
		bsb.bg_color = k["bg"]
		bsb.border_color = C_NAV_EDGE
		bsb.border_width_left = 1
		bsb.border_width_top = 1
		bsb.border_width_right = 1
		bsb.border_width_bottom = 1
		b.add_theme_stylebox_override("disabled", bsb)
		b.add_theme_color_override("font_disabled_color", C_NAV_FG)
		b.add_theme_font_size_override("font_size", 11)
		h.add_child(b)
	return pc

# ---------------------------------------------------------------------------
# Widget primitives
# ---------------------------------------------------------------------------

func _mklabel(txt: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

## A white bordered read-out box.  `key` registers it for rendered_text("box:key")
## so a test can read the pixels, not the intent.  Starts UNAVAIL by design.
func _mkvalue_box(key: String, width: float) -> Control:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_BOX_BG
	sb.border_color = C_BOX_EDGE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 8
	sb.content_margin_right = 8
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	box.add_theme_stylebox_override("panel", sb)
	var lbl := _mklabel(UNAVAIL, 12, C_UNAVAIL)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.custom_minimum_size = Vector2(width, 0)
	box.add_child(lbl)
	if key != "":
		_value_boxes[key] = lbl
	return box

## A round safety/status lamp.  `label` is the operator's VERBATIM Dutch text and
## is used as the registry key — which is why two screens that word the same
## concept differently keep two distinct lamps, as they must.
func _mklamp(label: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_child(_mklabel(label, 12, C_TEXT))
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(14, 14)
	dot.color = C_UNAVAIL
	dot.set_meta("render_text", UNAVAIL)
	row.add_child(dot)
	_lamps[label] = dot
	return row

func _paint_dot(dot: ColorRect, on: bool, unavailable: bool) -> void:
	if dot == null or not is_instance_valid(dot):
		return
	if unavailable:
		dot.color = C_UNAVAIL
		dot.set_meta("render_text", UNAVAIL)
		dot.tooltip_text = UNAVAIL
		return
	# A run-status square is green #35c23a when the drive runs.
	dot.color = C_GREEN if on else Color(0.30, 0.30, 0.30, 1.0)
	dot.set_meta("render_text", "AAN" if on else "UIT")
	dot.tooltip_text = "AAN" if on else "UIT"

func _paint_amps(lbl: Label, txt: String) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.text = txt
	lbl.add_theme_color_override("font_color", C_UNAVAIL if txt == UNAVAIL else C_BOX_FG)

func _paint_box(key: String, txt: String) -> void:
	var lbl : Label = _value_boxes.get(key, null)
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.text = txt
	lbl.add_theme_color_override("font_color", C_UNAVAIL if txt == UNAVAIL else C_BOX_FG)

## Per-tag formatting, taken off the photo: L3C.4/6/9/13/14 print bare integers,
## L3C.5/10/15/19 print a Dutch comma decimal.  Unit suffix " A" as on screen.
func _fmt_amps(v: float, fmt: String) -> String:
	if fmt == "comma2":
		return ("%.2f" % v).replace(".", ",") + " A"
	return "%d A" % int(round(v))

func _update_clock() -> void:
	if _clock_lbl == null or not is_instance_valid(_clock_lbl):
		return
	# Long Dutch date on line 1, HH:MM:SS on line 2.
	var t : Dictionary = Time.get_datetime_dict_from_system()
	var wd : int = clampi(int(t.get("weekday", 0)), 0, 6)
	var mo : int = clampi(int(t.get("month", 1)) - 1, 0, 11)
	_clock_lbl.text = "%s %d %s %d\n%02d:%02d:%02d" % [
		String(NL_WEEKDAYS[wd]), int(t.get("day", 1)), String(NL_MONTHS[mo]),
		int(t.get("year", 0)),
		int(t.get("hour", 0)), int(t.get("minute", 0)), int(t.get("second", 0)),
	]

# ---------------------------------------------------------------------------
# Input
# ---------------------------------------------------------------------------

func _gui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		request_close.emit()
		accept_event()
