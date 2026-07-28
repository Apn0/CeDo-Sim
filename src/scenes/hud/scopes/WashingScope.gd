extends Control
class_name WashingScope

## WASLIJN 3C — OVERZICHT.  Port of the operator's real L&P / Siemens SIMATIC
## plant-mimic screen onto live sim state.
##
## SOURCE OF EVERY LABEL AND POSITION IN THIS FILE
## -----------------------------------------------
##  * MOCKUP  docs/plant/hmi_screens_2026-07-26/Waslijn 3C Overzicht.dc.html
##            (canvas 1280x800 at :14; mimic pane top:92 .. bottom:44 => 1280x664
##            at :40).  Cited per element as "mockup :<line>".
##  * PHOTO   assets/reference_photos/hmi/IMG-20240811-WA0010.jpg — the frame the
##            mockup header byte-matches (HMI clock 18:00:30, mockup :32).  Used
##            to decide WHICH units carry a Stroom box and how each box is
##            formatted.  A second frame IMG-20240811-WA0009.jpg (17:59:50) shows
##            the same boxes with different numbers, which is why NO photo value
##            is baked in here — they are live samples, not constants.
##  * SPINE   src/sim/Line3CDef.gd:53-90 — machine ids and Dutch names.
##  * TAGS    src/sim/TagMap.gd (77 doc-cited rows over
##            src/data/plant/line3c_scada_tags.json).
##
## WHAT THIS FILE REPLACED (and why)
## ---------------------------------
## It used to render a Waslijn 3A panel whose seven "process values" (19.4 %,
## 32.2 RPM, 13 ppm, -17.3 % ...) and six P&ID run flags were CONSTRUCTION-TIME
## LITERALS: bind() had zero callers repo-wide, and the scope's own header
## recorded that its reference image washing_3A.png is AI-ENHANCED with
## hallucinated screen text.  The 3A M1A doseerschroef widget and its
## `m1a_start_pressed` signal are gone with it — nothing in the repo connected
## that signal.  The genuine taped operator note it carried ("Tijdens starten
## hoort de doseerschroef M1A op 0% te staan.") belongs to line 3A and is NOT on
## the 3C Overzicht screen, so it is not reproduced here; it survives in
## docs/plant/hmi_reference.md.
##
## THE HONESTY RULE THIS SCREEN OBEYS
## ----------------------------------
## Every rendered process value is either
##   (a) BOUND      — resolved through TagMap over LineFlow.get_machine_info(),
##                    carrying the operator's own verbatim tag string, or
##   (b) UNAVAILABLE — rendered as the literal "--" (UNAVAIL) with a recorded
##                    reason, never as a plausible number.
## field_report() returns both lists so a headless test can assert the split
## instead of trusting it.  Counts are guarded by BOUND_FIELDS_EXPECTED /
## UNAVAIL_FIELDS_EXPECTED below: a regression that starts faking an unavailable
## field moves the counts and fails.
##
## KNOWN DEFECTS THIS SCREEN MAKES VISIBLE (it does not hide them)
## ---------------------------------------------------------------
##  1. LineFlow._find_node_by_id (LineFlow.gd:1483-1487) first-matches a
##     NON-UNIQUE placeable id.  Ten of the twenty L3C units on this screen share
##     an id with a mapped sibling (friction_sep x5, transport_screw x5,
##     mech_dryer x2, blower x2), so only the ten TagMap representatives
##     (TagMap.gd:149-160) are addressable.  The other ten render "--".
##  2. amps: ProcessModel.stage_amps contributes 0 A while l3c_code is stamped on
##     0 of 47 nodes, and MotorOverload then overwrites the same key from a
##     PLACEHOLDER 90 A default on high-load drives (TagMap.gd:175-179 and the
##     per-row notes at TagMap.gd:518-520, 561-563, 608-610).  The three bound
##     Stroom boxes therefore read the sim's real — but UNCALIBRATED — current.
##     That is a measurement, not a fake; the footer says so on screen.
##
## Idiom: self-contained procedural Control, no .tscn, same shape as
## ExtruderBluPortScope.gd / LaserFilterScope.gd / KufferathsDryerScope.gd.
## Mounted by HmiOverlay for scope_id "washing" (HmiOverlay.gd:349); bind() is
## called from HmiOverlay.open_subscope().

# ---------------------------------------------------------------------------
# Signals
# ---------------------------------------------------------------------------

signal request_close()

# ---------------------------------------------------------------------------
# NO `line_id` export, deliberately.  This screen IS Line 3C — every caption is
# an L3C.<n> tag and every binding goes through TagMap's scada/3c namespace — so
# a switchable line id would be a lie.  HmiOverlay.open_subscope() probes for the
# property (HmiOverlay.gd:399-400) and simply skips it when it is absent.
# ---------------------------------------------------------------------------

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")
const TagMapScript = preload("res://src/sim/TagMap.gd")

# ---------------------------------------------------------------------------
# Palette — hex values taken verbatim from the mockup's inline styles
# ---------------------------------------------------------------------------

const C_MIMIC_BG    : Color = Color("#1a1008")   # mockup :14, :40 (dark-brown field)
const C_HEADER_BG   : Color = Color("#2a2e36")   # mockup :20 L&P bar, :35 alarm strip
const C_HEADER_EDGE : Color = Color("#3a3f47")   # mockup :20
const C_TEXT        : Color = Color("#e8ecf2")   # mockup :14
const C_GREEN       : Color = Color("#35c23a")   # mockup :24 status chip / :43 square
const C_CHIP_FG     : Color = Color("#111111")   # mockup :24 chip text
const C_AMBER       : Color = Color("#e6b84a")   # mockup :35 alarm strip text
const C_BOX_BG      : Color = Color("#ffffff")   # mockup :47 value box
const C_BOX_FG      : Color = Color("#111111")   # mockup :47
const C_BOX_EDGE    : Color = Color("#aaaaaa")   # mockup :47
const C_SELECT_CYAN : Color = Color(0.0, 180.0 / 255.0, 220.0 / 255.0, 0.30)  # mockup :56
const C_NAV_BG      : Color = Color("#eef1f5")   # mockup :105
const C_NAV_KEY     : Color = Color("#ffffff")   # mockup :106
const C_NAV_EDGE    : Color = Color("#9aa0aa")   # mockup :106
const C_NAV_FG      : Color = Color("#20242a")
const C_NAV_HOME    : Color = Color("#4a5a7a")   # mockup :107
const C_NAV_ALARM   : Color = Color("#e8c040")   # mockup :116
const C_LOGO_A      : Color = Color("#2f6fb0")   # mockup :21 chevron
const C_LOGO_B      : Color = Color("#3a4a5a")   # mockup :21 chevron
const C_UNAVAIL     : Color = Color("#8a929c")   # sim-side: an unbound field

## The literal every unbound field renders.  Never a number, never a blank.
const UNAVAIL : String = "--"

# ---------------------------------------------------------------------------
# Field-count guards.  Two independent copies exist: these, and the literals in
# src/tests/test_waslijn3c_overzicht.gd.  Drift in either one fails the test.
# ---------------------------------------------------------------------------

const BOUND_FIELDS_EXPECTED  : int = 13   # 10 unit status + 3 unit Stroom
const UNAVAIL_FIELDS_EXPECTED: int = 25   # 3 header chips + 1 alarm + 10 status + 11 Stroom

# ---------------------------------------------------------------------------
# Mimic geometry (mockup pixel space)
# ---------------------------------------------------------------------------

const MIMIC_W : float = 1280.0            # mockup :14
const MIMIC_H : float = 664.0             # mockup :40 — 800 - 92 (header) - 44 (nav)

# ---------------------------------------------------------------------------
# HEADER CHIPS — verbatim labels, mockup :24 / :27 / :30.
# All three are UNAVAILABLE: the sim has no line-level Auto/Hand mode, no wash
# section state and no silo section state.  LineFlow's only line-wide states are
# is_estopped / is_line_starting / line_powered_fraction (LineFlow.gd:1405,
# 1648, 1716), which are RUN states, not the AUTO/AAN mode annunciators these
# chips show.  Aggregating per-machine hand_mode into a line mode would be an
# invented rule, so it is not done.
# ---------------------------------------------------------------------------

const HEADER_CHIPS : Array = [
	{"label": "Status Lijn 3C", "cite": "mockup :24",
	 "reason": "no line-level Auto/Hand mode exists in the sim; hand_mode is PER MACHINE (LineFlow.gd:1491-1496) and the aggregation rule is undocumented"},
	{"label": "Status was", "cite": "mockup :27",
	 "reason": "no wash-SECTION on/off state exists; LineFlow models machines, not sections"},
	{"label": "Status Silo", "cite": "mockup :30",
	 "reason": "no silo-SECTION on/off state exists; LineFlow models machines, not sections"},
]

# ---------------------------------------------------------------------------
# MIMIC TILES.
#
# `caption` + `name` are VERBATIM from the cited mockup line.  `px`/`py` are that
# line's own left/top in mockup pixel space.  The mockup's coordinates are loose
# approximations of the photo (the real screen is a 3D isometric plant render,
# not a flat field), so positions here are LAYOUT-APPROXIMATE by construction and
# are not claimed as measurements.
#
# `units` are the Line3CDef stage codes the caption covers — the real screen uses
# one caption for an L/R pair ("L3C.5L/R") with one Stroom box per side.  The
# machine id and Dutch name come from Line3CDef.STAGES (looked up at build time,
# never duplicated here).
#
# `amp_box` records whether the REAL screen shows a Stroom box for that unit,
# read off IMG-20240811-WA0010.jpg.  `amp_fmt` records that box's own formatting,
# which is PER TAG and not per magnitude: L3C.4/6/9/13/14 print bare integers
# ("26 A", "203 A", "107 A") while L3C.5/10/15/19 print a Dutch comma decimal
# ("2,64 A", "4,07 A", "14,49 A").
#
# The mockup MIS-ATTRIBUTES four boxes; the attributions below are the photo's,
# not the mockup's, and each divergence is called out in `amp_note`.
# ---------------------------------------------------------------------------

const GROUPS : Array = [
	{"caption": "L3C.1", "name": "Doseer Silo", "px": 40.0, "py": 280.0, "cite": "mockup :42", "units": [
		{"code": "L3C.1", "amp_box": false, "amp_fmt": "",
		 "amp_note": "photo: status square only, no Stroom box (mockup :42-43 agrees)"},
	]},
	{"caption": "L3C.3", "name": "Bezinkafscheider", "px": 140.0, "py": 36.0, "cite": "mockup :46", "units": [
		{"code": "L3C.3", "amp_box": false, "amp_fmt": "",
		 "amp_note": "MOCKUP DEFECT :47 puts a '0 A' box here; on the photo L3C.3 has NO box — that box is L3C.4L's 26 A"},
	]},
	{"caption": "L3C.5L/R", "name": "Transportschroef", "px": 300.0, "py": 12.0, "cite": "mockup :51", "units": [
		{"code": "L3C.5L", "amp_box": true, "amp_fmt": "comma2",
		 "amp_note": "photo 2,64 A (mockup :52 box, zeroed to '0,00 A')"},
		{"code": "L3C.5R", "amp_box": true, "amp_fmt": "comma2",
		 "amp_note": "photo 2,60 A; the mockup files this box under L3C.4L/R at :59 — MIS-ATTRIBUTED"},
	]},
	{"caption": "L3C.6", "name": "Maalmolen", "px": 380.0, "py": 120.0, "cite": "mockup :56", "select": true, "units": [
		{"code": "L3C.6", "amp_box": true, "amp_fmt": "int",
		 "amp_note": "photo 203 A (mockup :55 box, zeroed to '0 A')"},
	]},
	{"caption": "L3C.4L/R", "name": "Frictiescheider", "px": 140.0, "py": 240.0, "cite": "mockup :61", "units": [
		{"code": "L3C.4L", "amp_box": true, "amp_fmt": "int",
		 "amp_note": "photo 26 A; the mockup files this box under L3C.3 at :47 — MIS-ATTRIBUTED"},
		{"code": "L3C.4R", "amp_box": true, "amp_fmt": "int",
		 "amp_note": "photo 26 A (mockup :60 box)"},
	]},
	{"caption": "L3C.9L/R", "name": "Frictiescheider", "px": 420.0, "py": 258.0, "cite": "mockup :66", "units": [
		{"code": "L3C.9L", "amp_box": true, "amp_fmt": "int", "amp_note": "photo 29 A (mockup :64 box)"},
		{"code": "L3C.9R", "amp_box": true, "amp_fmt": "int", "amp_note": "photo 30 A (mockup :65 box)"},
	]},
	{"caption": "L3C.10L/R", "name": "Transportschroef", "px": 570.0, "py": 12.0, "cite": "mockup :69", "units": [
		{"code": "L3C.10L", "amp_box": true, "amp_fmt": "comma2", "amp_note": "photo 4,07 A (mockup :70 box)"},
		{"code": "L3C.10R", "amp_box": true, "amp_fmt": "comma2", "amp_note": "photo 4,26 A (mockup :71 box)"},
	]},
	{"caption": "L3C.11", "name": "Flotatietank", "px": 700.0, "py": 12.0, "cite": "mockup :74", "units": [
		{"code": "L3C.11", "amp_box": false, "amp_fmt": "",
		 "amp_note": "photo CONFIRMS no Stroom box on L3C.11 — its two standing alarms are level and FLOW, not current"},
	]},
	{"caption": "L3C.12", "name": "Transportschroef", "px": 900.0, "py": 200.0, "cite": "mockup :77", "units": [
		{"code": "L3C.12", "amp_box": false, "amp_fmt": "",
		 "amp_note": "MOCKUP DEFECT :78 puts a box here; it reads 34 A and belongs to L3C.13 — proven because IMG-20240811-WA0013.jpg (the L3C.12 unit screen, same shift 18:03:00) shows L3C.12 Stroom = 03,97 A"},
	]},
	{"caption": "L3C.13", "name": "Frictiescheider L-R", "px": 900.0, "py": 260.0, "cite": "mockup :81", "units": [
		{"code": "L3C.13", "amp_box": true, "amp_fmt": "int", "amp_note": "photo 34 A (the box the mockup mis-files at :78)"},
	]},
	{"caption": "L3C.14L/R", "name": "Mechanische Drogers", "px": 1050.0, "py": 12.0, "cite": "mockup :84", "units": [
		{"code": "L3C.14L", "amp_box": true, "amp_fmt": "int", "amp_note": "photo 107 A (mockup :85 box)"},
		{"code": "L3C.14R", "amp_box": true, "amp_fmt": "int", "amp_note": "photo 106 A (mockup :87 box)"},
	]},
	{"caption": "L3C.15", "name": "Transport Ventilator", "px": 1100.0, "py": 310.0, "cite": "mockup :90", "units": [
		{"code": "L3C.15", "amp_box": true, "amp_fmt": "comma2",
		 "amp_note": "the middle box of the L3C.14 cluster (mockup :86) reads 15,30 A; geometrically it sits between the drogers and this caption and its magnitude fits a blower, not a 100 A drum — OWNER UNRESOLVED between L3C.14 and L3C.15, so this box is never bound"},
	]},
	{"caption": "L3C.16", "name": "Plasmaq", "px": 80.0, "py": 360.0, "cite": "mockup :93", "units": [
		{"code": "L3C.16", "amp_box": false, "amp_fmt": "",
		 "amp_note": "status square only (mockup :93-94); the export has em/* leaves ONLY for unit 16 — no stroom tag exists"},
	]},
	{"caption": "L3C.18", "name": "Extruder Silo", "px": 350.0, "py": 330.0, "cite": "mockup :97", "units": [
		{"code": "L3C.18", "amp_box": false, "amp_fmt": "", "amp_note": "no Stroom box on the overview (mockup :97)"},
	]},
	{"caption": "L3C.19", "name": "Rondmengventilator", "px": 520.0, "py": 340.0, "cite": "mockup :100", "units": [
		{"code": "L3C.19", "amp_box": true, "amp_fmt": "comma2", "amp_note": "photo 14,49 A (mockup :101 box)"},
	]},
]

# ---------------------------------------------------------------------------
# TAG SELECTION.
#
# status: every one of the ten TagMap representative units carries
#   scada/3c/info/<unit>/em/status  ->  get_machine_info()["powered"]
#   (TagMap.gd:450, 487, 503, 532, 549, 572, 599, 619, 637, 647).
#
# stroom: TagMap maps a machine-level current for exactly THREE units.  The
#   export DOES carry per-motor stroom leaves for units 1/3/5l/11/15/18 too
#   (e.g. "scada/3c/info/5l/schroef 1/stroom"), but TagMap deliberately leaves
#   every PER-MOTOR current unmapped — `amps` is per-MACHINE, never per motor
#   (TagMap.gd:74-91).  Binding a machine total to a motor leaf would invent
#   resolution the sim does not have, so those boxes stay unavailable.
# ---------------------------------------------------------------------------

const STATUS_TAG_FMT : String = "scada/3c/info/%s/em/status"

const STROOM_TAGS : Dictionary = {
	"4l":  "scada/3c/info/4l/softstarterfrictiewasser/stroom",   # TagMap.gd:518
	"6":   "scada/3c/info/6/softstartersnijmolen/stroom",        # TagMap.gd:561
	"14l": "scada/3c/info/14l/softstarterdroger1/stroom",        # TagMap.gd:608
}

## Why a unit with no STROOM_TAGS entry cannot bind its box.
const NO_STROOM_ROW_REASON : String = "TagMap has no machine-level stroom row for this unit; the export's per-motor stroom leaves are deliberately unmapped (TagMap.gd:74-91: amps is per-MACHINE, never per motor)"

# ---------------------------------------------------------------------------
# Dutch date parts — the header prints a long Dutch date (mockup :32
# "zaterdag 10 augustus 2024").  Locale formatting, not plant data.
# ---------------------------------------------------------------------------

const NL_WEEKDAYS : Array = ["zondag", "maandag", "dinsdag", "woensdag",
	"donderdag", "vrijdag", "zaterdag"]
const NL_MONTHS : Array = ["januari", "februari", "maart", "april", "mei", "juni",
	"juli", "augustus", "september", "oktober", "november", "december"]

# ---------------------------------------------------------------------------
# Bound state
# ---------------------------------------------------------------------------

var _scope     : Dictionary = {}
var _line_flow : Node       = null
var _tagmap    : TagMap     = null

# code -> {"id", "name", "tag_unit"} resolved from Line3CDef + TagMap.UNITS
var _unit_meta : Dictionary = {}

# Node caches
var _mimic         : Control = null
var _tiles         : Array   = []          # [{node, px, py}]
var _status_dots   : Dictionary = {}       # code -> ColorRect
var _amp_labels    : Dictionary = {}       # code -> Label
var _chip_labels   : Dictionary = {}       # chip label -> Label
var _alarm_nr_lbl  : Label = null
var _alarm_txt_lbl : Label = null
var _clock_lbl     : Label = null
var _audit_lbl     : Label = null

# Audit rows, rebuilt by refresh()
var _bound     : Array[Dictionary] = []
var _unavail   : Array[Dictionary] = []

var _clock_accum : float = 1.0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(960, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_unit_meta()
	_build_ui()
	refresh()

func _process(delta: float) -> void:
	_clock_accum += delta
	if _clock_accum < 1.0:
		return
	_clock_accum = 0.0
	_update_clock()
	refresh()

# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

## Wire the scope dict + the live LineFlow.  `line_flow` is duck-typed (Object,
## not a typed LineFlow) so a headless test can pass a stub that answers
## get_machine_info() — which is exactly how the mutation half of
## src/tests/test_waslijn3c_overzicht.gd proves this screen is not faking.
func bind(scope: Dictionary = {}, line_flow: Node = null) -> void:
	_scope = scope.duplicate(true) if not scope.is_empty() else {}
	_line_flow = line_flow
	if _tagmap == null:
		_tagmap = TagMapScript.new()
	refresh()

## Audit surface.  {bound:[...], unavailable:[...], bound_count, unavailable_count,
## total, expected_bound, expected_unavailable}.  Each bound row carries the
## operator's verbatim tag, TagMap's own source_field expression and the value
## actually rendered; each unavailable row carries a reason string.
func field_report() -> Dictionary:
	return {
		"bound": _bound.duplicate(true),
		"unavailable": _unavail.duplicate(true),
		"bound_count": _bound.size(),
		"unavailable_count": _unavail.size(),
		"total": _bound.size() + _unavail.size(),
		"expected_bound": BOUND_FIELDS_EXPECTED,
		"expected_unavailable": UNAVAIL_FIELDS_EXPECTED,
	}

## The text currently painted for a field key ("status:L3C.6" / "stroom:L3C.6" /
## "chip:Status was" / "alarm").  Lets a test assert what the OPERATOR sees, not
## just what the audit dict claims.
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
		"alarm":
			return _alarm_nr_lbl.text if _alarm_nr_lbl != null else ""
	return ""

# ---------------------------------------------------------------------------
# Spine lookup — ids and Dutch names come from Line3CDef, never re-typed here
# ---------------------------------------------------------------------------

func _build_unit_meta() -> void:
	_unit_meta.clear()
	# code -> TagMap unit segment, inverted from TagMap.UNITS (TagMap.gd:149-160).
	var code_to_unit : Dictionary = {}
	for u in TagMapScript.UNITS.keys():
		var spine : Array = TagMapScript.UNITS[u]
		code_to_unit[String(spine[0])] = String(u)
	for st in Line3CDefScript.STAGES:
		var code := String(st["code"])
		_unit_meta[code] = {
			"id": String(st["id"]),
			"name": String(st["name"]),
			"tag_unit": String(code_to_unit.get(code, "")),
		}

func _meta(code: String) -> Dictionary:
	return _unit_meta.get(code, {"id": "", "name": "", "tag_unit": ""})

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_MIMIC_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# NOTE: the mockup's "SIEMENS / SIMATIC HMI" strip (:16-18) is the physical
	# panel bezel silkscreen, NOT part of the WinCC page — it is deliberately not
	# drawn inside the screen.
	root.add_child(_build_header_bar())
	root.add_child(_build_alarm_strip())
	root.add_child(_build_mimic())
	root.add_child(_build_audit_strip())
	root.add_child(_build_nav_bar())

# --- L&P header (mockup :20-33) ---------------------------------------------

func _build_header_bar() -> Control:
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

	# L&P chevron logo (mockup :21) — two nested triangles.
	var logo := Control.new()
	logo.custom_minimum_size = Vector2(36, 28)
	logo.draw.connect(func() -> void:
		logo.draw_colored_polygon(PackedVector2Array([
			Vector2(8, 2), Vector2(18, 14), Vector2(8, 26)]), C_LOGO_A)
		logo.draw_colored_polygon(PackedVector2Array([
			Vector2(16, 2), Vector2(26, 14), Vector2(16, 26)]), C_LOGO_B)
	)
	h.add_child(logo)

	h.add_child(_mklabel("L&P", 14, C_TEXT))   # mockup :22

	# The photo stacks "Status Lijn 3C" over "Status was" as a left-centre pair
	# with "Status Silo" separately to their right; the mockup lays all three in
	# one flex row (:23-31).  The photo layout is followed here.
	var pair := VBoxContainer.new()
	pair.add_theme_constant_override("separation", 2)
	pair.add_child(_build_chip(HEADER_CHIPS[0]))
	pair.add_child(_build_chip(HEADER_CHIPS[1]))
	h.add_child(pair)

	var silo_wrap := VBoxContainer.new()
	silo_wrap.alignment = BoxContainer.ALIGNMENT_CENTER
	silo_wrap.add_child(_build_chip(HEADER_CHIPS[2]))
	h.add_child(silo_wrap)

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

# --- alarm strip (mockup :35-37) --------------------------------------------

func _build_alarm_strip() -> Control:
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
	# No wash-line fault source exists: EremaFaultRegistry.gd covers the EREMA
	# extruder codes only and has no L3C entry, so the strip states that rather
	# than replaying the photo's latched "149 L3C.11 ... Water Flow te laag".
	_alarm_txt_lbl = _mklabel(
		"geen storingsbron gekoppeld — EremaFaultRegistry dekt alleen de extruder, er is geen waslijn-storingsregister",
		12, C_UNAVAIL)
	h.add_child(_alarm_txt_lbl)
	return pc

# --- mimic pane (mockup :40-102) --------------------------------------------

func _build_mimic() -> Control:
	_mimic = Control.new()
	_mimic.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_mimic.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mimic.clip_contents = true
	_mimic.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var pane_bg := ColorRect.new()
	pane_bg.color = C_MIMIC_BG
	pane_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pane_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mimic.add_child(pane_bg)

	_tiles.clear()
	for g in GROUPS:
		var tile := _build_group_tile(g)
		_mimic.add_child(tile)
		_tiles.append({
			"node": tile,
			"px": float(g["px"]) / MIMIC_W,
			"py": float(g["py"]) / MIMIC_H,
		})
	_mimic.resized.connect(_layout_tiles)
	return _mimic

func _build_group_tile(g: Dictionary) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 2)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# caption block — L3C code over Dutch name, verbatim (mockup cite in `cite`)
	var cap_holder : Control = col
	if bool(g.get("select", false)):
		# mockup :56 — the Maalmolen caption sits on a cyan selected-highlight,
		# confirmed on the photo.
		var hl := PanelContainer.new()
		var hsb := StyleBoxFlat.new()
		hsb.bg_color = C_SELECT_CYAN
		hsb.content_margin_left = 8
		hsb.content_margin_right = 8
		hsb.content_margin_top = 4
		hsb.content_margin_bottom = 4
		hl.add_theme_stylebox_override("panel", hsb)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 0)
		hl.add_child(inner)
		col.add_child(hl)
		cap_holder = inner

	var code_lbl := _mklabel(String(g["caption"]), 12, C_TEXT)
	code_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_holder.add_child(code_lbl)
	var name_lbl := _mklabel(String(g["name"]), 12, C_TEXT)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cap_holder.add_child(name_lbl)

	for u in g["units"]:
		col.add_child(_build_unit_row(u as Dictionary))
	return col

func _build_unit_row(u: Dictionary) -> Control:
	var code := String(u["code"])
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 5)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE

	# Run-status square.  The mockup enumerates only three of these (L3C.1 :43,
	# L3C.3 :48, L3C.16 :94) but the real screen carries a per-drive set the
	# mockup does not enumerate, so one square per UNIT is drawn and the
	# enumeration is declared approximate rather than invented into the mockup.
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(10, 10)
	dot.color = C_UNAVAIL
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot.set_meta("render_text", UNAVAIL)
	_status_dots[code] = dot
	row.add_child(dot)

	# Per-unit tag suffix, so an L/R pair is readable under one caption.
	var suffix := code.substr(String(code).length() - 1)
	if suffix == "L" or suffix == "R":
		row.add_child(_mklabel(suffix, 11, C_TEXT))

	if bool(u.get("amp_box", false)):
		var box := PanelContainer.new()
		var sb := StyleBoxFlat.new()
		sb.bg_color = C_BOX_BG            # mockup :47 white box, grey border
		sb.border_color = C_BOX_EDGE
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		sb.content_margin_left = 8
		sb.content_margin_right = 8
		sb.content_margin_top = 2
		sb.content_margin_bottom = 2
		box.add_theme_stylebox_override("panel", sb)
		var lbl := _mklabel(UNAVAIL, 12, C_BOX_FG)
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		lbl.custom_minimum_size = Vector2(52, 0)
		box.add_child(lbl)
		_amp_labels[code] = lbl
		row.add_child(box)
	return row

func _layout_tiles() -> void:
	if _mimic == null or not is_instance_valid(_mimic):
		return
	var sz : Vector2 = _mimic.size
	for t in _tiles:
		var node : Control = t["node"]
		if node == null or not is_instance_valid(node):
			continue
		node.size = node.get_combined_minimum_size()
		node.position = Vector2(float(t["px"]) * sz.x, float(t["py"]) * sz.y)

# --- honesty audit strip (sim-side, NOT on the plant screen) ------------------

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

# --- bottom nav (mockup :105-118) -------------------------------------------

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

	# Verbatim key labels, left to right, mockup :106-117.  The real bar also
	# carries FIVE blank/unassigned keys the mockup omits (one after home, four
	# after "Stop Runtime") — they are not drawn because their count is the only
	# thing known about them.  The four emoji keys in the mockup are its own
	# stand-ins; the photo shows report / two-person / wrench / triangle-A
	# glyphs, so they are drawn as unlabelled keys here rather than as invented
	# text.  Every key is DISABLED: none of them is wired to anything.
	var keys : Array = [
		{"t": "<",             "w": 36.0, "bg": C_NAV_KEY},   # mockup :106 (verbatim glyph is a left triangle)
		{"t": "",              "w": 40.0, "bg": C_NAV_HOME},  # mockup :107 home
		{"t": "Clean\nscreen", "w": 60.0, "bg": C_NAV_KEY},   # mockup :108
		{"t": "Stop\nRuntime", "w": 50.0, "bg": C_NAV_KEY},   # mockup :109
		{"t": "",              "w": 0.0,  "bg": C_NAV_KEY, "spacer": true},  # mockup :110
		{"t": "",              "w": 40.0, "bg": C_NAV_KEY},   # mockup :111 report glyph
		{"t": "",              "w": 40.0, "bg": C_NAV_KEY},   # mockup :112 two-person glyph
		{"t": "Logout",        "w": 56.0, "bg": C_NAV_KEY},   # mockup :113
		{"t": "Reset",         "w": 50.0, "bg": C_NAV_KEY},   # mockup :114
		{"t": "",              "w": 36.0, "bg": C_NAV_KEY},   # mockup :115 wrench glyph
		{"t": "",              "w": 36.0, "bg": C_NAV_ALARM}, # mockup :116 triangle-A glyph
		{"t": ">",             "w": 36.0, "bg": C_NAV_KEY},   # mockup :117
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

func _mklabel(txt: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

# ---------------------------------------------------------------------------
# Refresh — rebuilds the audit AND repaints, from one pass, so the dict and the
# pixels can never disagree.
# ---------------------------------------------------------------------------

func refresh() -> void:
	_bound.clear()
	_unavail.clear()

	# Header chips + alarm strip: structurally unavailable, always.
	for chip in HEADER_CHIPS:
		_unavail.append({
			"field": "chip:%s" % String(chip["label"]),
			"label": String(chip["label"]),
			"cite": String(chip["cite"]),
			"reason": String(chip["reason"]),
		})
	_unavail.append({
		"field": "alarm",
		"label": "alarmregel",
		"cite": "mockup :36",
		"reason": "no wash-line fault registry exists; src/sim/EremaFaultRegistry.gd carries the EREMA extruder codes only, no L3C entry",
	})

	var resolved := _resolve_tags()

	for g in GROUPS:
		for uu in g["units"]:
			var u : Dictionary = uu
			var code := String(u["code"])
			var meta := _meta(code)
			var tag_unit := String(meta["tag_unit"])
			_refresh_status(code, meta, tag_unit, resolved)
			if bool(u.get("amp_box", false)):
				_refresh_stroom(code, meta, tag_unit, u, resolved)

	if _audit_lbl != null:
		_audit_lbl.text = "BINDING  %d live via TagMap · %d niet beschikbaar (\"%s\")   |   amps zijn ONGEKALIBREERD zolang l3c_code op 0 van 47 nodes staat (TagMap.gd:175-179)" \
			% [_bound.size(), _unavail.size(), UNAVAIL]

## One get_machine_info() + TagMap.resolve_machine() pass per DISTINCT machine
## id this screen needs, keyed back by tag string.
func _resolve_tags() -> Dictionary:
	var out : Dictionary = {}
	if _line_flow == null or not is_instance_valid(_line_flow):
		return out
	if _tagmap == null:
		_tagmap = TagMapScript.new()
	if not _line_flow.has_method("get_machine_info"):
		return out
	var ctx : Dictionary = {"estop_fault_id": ""}
	if _line_flow.has_method("estop_fault_id"):
		ctx["estop_fault_id"] = String(_line_flow.call("estop_fault_id"))
	var seen : Dictionary = {}
	for code in _unit_meta.keys():
		var meta : Dictionary = _unit_meta[code]
		if String(meta["tag_unit"]) == "":
			continue
		var mid := String(meta["id"])
		if seen.has(mid):
			continue
		seen[mid] = true
		var info : Dictionary = _line_flow.call("get_machine_info", mid)
		if typeof(info) != TYPE_DICTIONARY or info.is_empty():
			continue
		for r in _tagmap.resolve_machine(mid, info, ctx):
			out[String(r["tag"])] = r
	return out

func _refresh_status(code: String, meta: Dictionary, tag_unit: String, resolved: Dictionary) -> void:
	var dot : ColorRect = _status_dots.get(code, null)
	var key := "status:%s" % code
	if tag_unit == "":
		_mark_unavail(key, code, "mockup :43/:48/:94 (per-drive status square)",
			"placeable id \"%s\" is NOT unique on the line — LineFlow._find_node_by_id (LineFlow.gd:1483-1487) first-matches it, so only the TagMap representative unit is addressable (TagMap.gd:29-36)" % String(meta["id"]))
		_paint_dot(dot, false, true)
		return
	var tag := STATUS_TAG_FMT % tag_unit
	var row : Dictionary = resolved.get(tag, {})
	if row.is_empty() or row.get("value", null) == null:
		_mark_unavail(key, code, "mockup :43/:48/:94 (per-drive status square)",
			"tag \"%s\" did not resolve — no LineFlow, or get_machine_info(\"%s\") returned nothing" % [tag, String(meta["id"])])
		_paint_dot(dot, false, true)
		return
	var on := bool(row["value"])
	_bound.append({
		"field": key,
		"code": code,
		"machine_id": String(meta["id"]),
		"tag": tag,
		"source_field": String(row["source_field"]),
		"confidence": String(row["confidence"]),
		"value": on,
		"rendered": "AAN" if on else "UIT",
	})
	_paint_dot(dot, on, false)

func _refresh_stroom(code: String, meta: Dictionary, tag_unit: String,
		u: Dictionary, resolved: Dictionary) -> void:
	var lbl : Label = _amp_labels.get(code, null)
	var key := "stroom:%s" % code
	var cite := String(u.get("amp_note", ""))
	if tag_unit == "":
		_mark_unavail(key, code, cite,
			"placeable id \"%s\" is NOT unique — only the TagMap representative unit is addressable (LineFlow.gd:1483-1487, TagMap.gd:29-36)" % String(meta["id"]))
		_paint_amps(lbl, UNAVAIL)
		return
	if code == "L3C.15":
		_mark_unavail(key, code, cite,
			"box OWNER UNRESOLVED between L3C.14 and L3C.15 on the photo; binding it would assert an attribution the evidence does not support")
		_paint_amps(lbl, UNAVAIL)
		return
	if not STROOM_TAGS.has(tag_unit):
		_mark_unavail(key, code, cite, NO_STROOM_ROW_REASON)
		_paint_amps(lbl, UNAVAIL)
		return
	var tag := String(STROOM_TAGS[tag_unit])
	var row : Dictionary = resolved.get(tag, {})
	if row.is_empty() or row.get("value", null) == null:
		_mark_unavail(key, code, cite,
			"tag \"%s\" did not resolve — no LineFlow, or get_machine_info(\"%s\") returned nothing" % [tag, String(meta["id"])])
		_paint_amps(lbl, UNAVAIL)
		return
	var v := float(row["value"])
	var txt := _fmt_amps(v, String(u.get("amp_fmt", "int")))
	_bound.append({
		"field": key,
		"code": code,
		"machine_id": String(meta["id"]),
		"tag": tag,
		"source_field": String(row["source_field"]),
		"confidence": String(row["confidence"]),
		"value": v,
		"rendered": txt,
	})
	_paint_amps(lbl, txt)

func _mark_unavail(field: String, code: String, cite: String, reason: String) -> void:
	_unavail.append({"field": field, "code": code, "cite": cite, "reason": reason})

func _paint_dot(dot: ColorRect, on: bool, unavailable: bool) -> void:
	if dot == null or not is_instance_valid(dot):
		return
	if unavailable:
		dot.color = C_UNAVAIL
		dot.set_meta("render_text", UNAVAIL)
		dot.tooltip_text = UNAVAIL
		return
	# mockup :43 — a run-status square is green #35c23a when the drive runs.
	dot.color = C_GREEN if on else Color(0.30, 0.30, 0.30, 1.0)
	dot.set_meta("render_text", "AAN" if on else "UIT")
	dot.tooltip_text = "AAN" if on else "UIT"

func _paint_amps(lbl: Label, txt: String) -> void:
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
	# mockup :32 — long Dutch date on line 1, HH:MM:SS on line 2.
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
