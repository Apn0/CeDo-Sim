extends "res://src/scenes/hud/scopes/HmiScreenBase.gd"
class_name WashingScope

# NOTE ON THE `extends` ABOVE — it is a resource path, not the class_name.
# HmiScreenBase does declare `class_name`, but resolving a class_name requires
# Godot's global class cache (.godot/global_script_class_cache.cfg), which is
# gitignored and is only rebuilt by an editor/import pass.  The regression
# harness runs `--headless -s <test>` with no import pass, so on a fresh clone
# `extends HmiScreenBase` fails with "Could not resolve script" — which is how
# this line got written the wrong way round once already.  A path extends needs
# no cache and works identically in the editor and headless.

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
##  * SPINE   src/sim/Line3CDef.gd:59-96 — machine ids and Dutch names.
##  * TAGS    src/sim/TagMap.gd (112 doc-cited rows over
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
## HOW IT ADDRESSES MACHINES (this used to be defect #1)
## -----------------------------------------------------
## Every unit is resolved by its OWN plant code — get_machine_info("L3C.9R") —
## because LineFlow mints each node a per-instance key that IS its l3c_code for a
## stamped Line 3C stage.  Before that existed, the screen could only ask for a
## placeable id, LineFlow first-matched it, and ten of the twenty units shared an
## id with a mapped sibling (friction_sep x5, transport_screw x5, mech_dryer x2,
## blower x2); those ten rendered "--" and the other ten silently read whichever
## machine answered first — in a Line 3A world, a LINE 3A machine.  That second
## half was the more dangerous one: it was wrong without looking wrong.
##
## CONSEQUENCE: this screen binds only in a world where the `line_3c` macro has
## been placed.  In a 3A/3B-only world nothing carries an L3C code and every
## field renders "--" with that as its recorded reason.  That is the honest
## answer; falling back to the id would restore exactly the lie above.
##
## WHAT STILL DOES NOT BIND (measured, not hidden)
## -----------------------------------------------
##  1. Six Stroom boxes — L3C.5L/5R/10L/10R (per-motor "schroef 1"/"schroef 2"
##     leaves), L3C.12 ("afvoerschroef"), L3C.19 ("fqventilator").  The export
##     has no MACHINE-level current for these units, only per-motor ones, and
##     `amps` in the sim is per-machine (TagMap.gd PER-MOTOR block).  Picking one
##     motor's leaf to carry the machine total is an operator ruling.
##  2. L3C.15's box: the photo cannot settle whether it belongs to L3C.14 or
##     L3C.15.  Unchanged by this work and deliberately still unbound.
##  3. The three header chips and the alarm number: the sim has no line-level
##     mode annunciator and no wash-line fault registry.
##
## The eight bound Stroom boxes now read a CALIBRATED current: each unit's
## amps_nominal comes from its own Line3CDef row, so the five friction separators
## draw against 29.92 / 29.92 / 28.03 / 30.88 / 24.68 A instead of a shared
## placeholder.  On the high-load drives MotorOverload still owns the live number,
## but it is now seeded from that same per-unit nominal.
##
## Idiom: self-contained procedural Control, no .tscn, same shape as
## ExtruderBluPortScope.gd / LaserFilterScope.gd / KufferathsDryerScope.gd.
## Mounted by HmiOverlay for scope_id "washing" (HmiOverlay.gd:349); bind() is
## called from HmiOverlay.open_subscope().

# ---------------------------------------------------------------------------
# NO `line_id` export, deliberately.  This screen IS Line 3C — every caption is
# an L3C.<n> tag and every binding goes through TagMap's scada/3c namespace — so
# a switchable line id would be a lie.  HmiOverlay.open_subscope() probes for the
# property (HmiOverlay.gd:399-400) and simply skips it when it is absent.
# ---------------------------------------------------------------------------

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")
const TagMapScript = preload("res://src/sim/TagMap.gd")

# ---------------------------------------------------------------------------
# Palette
# ---------------------------------------------------------------------------
# The shared chrome palette (C_HEADER_BG, C_GREEN, C_NAV_*, C_UNAVAIL, UNAVAIL,
# ...) now lives ONCE in HmiScreenBase, measured against all 16 exported
# "Waslijn 3C *" screens by tools/hmi/palette_census.py.  Only what is unique to
# THIS screen stays here.
#
# The mockup cites this file used to carry per constant are not lost: they were
# :14/:20/:24/:35/:47/:105-118 of Waslijn 3C Overzicht.dc.html, and the same
# colours carry different line numbers on the other fifteen screens — which is
# exactly why the base takes its content as arguments and leaves citation to the
# screen.
# ---------------------------------------------------------------------------

## Row highlight behind the selected unit — mockup :56.  Unique to the Overzicht
## mimic; no per-unit screen has a selectable row.
const C_SELECT_CYAN : Color = Color(0.0, 180.0 / 255.0, 220.0 / 255.0, 0.30)

## What the amber alarm strip says instead of replaying the mockup's latched
## "149 L3C.11 Flotatietank Flow Meting: Water Flow te laag" (mockup :36).  The
## sim has no wash-line fault source at all: src/sim/EremaFaultRegistry.gd
## carries the EREMA extruder codes only and has no L3C entry.  This is the
## OPERATOR-FACING half; the machine-readable half is the reason string in
## refresh(), and the two are asserted to agree by the test.
const ALARM_UNAVAIL_REASON : String = "geen storingsbron gekoppeld — EremaFaultRegistry dekt alleen de extruder, er is geen waslijn-storingsregister"

# ---------------------------------------------------------------------------
# Field-count guards.  Two independent copies exist: these, and the literals in
# src/tests/test_waslijn3c_overzicht.gd.  Drift in either one fails the test.
# ---------------------------------------------------------------------------

## MEASURED 2026-07-29 on a real MainWorld boot with the line_3c macro placed,
## not predicted: 20 unit status (every one of the 20 L3C wash units carries
## em/status in the export and is now addressable by its own code) + 8 unit
## Stroom (4L/4R/6/9L/9R/13/14L/14R — the units whose MACHINE-level stroom leaf
## exists).  Was 13 / 25 while ten units were unreachable.
const BOUND_FIELDS_EXPECTED  : int = 28   # 20 unit status + 8 unit Stroom
const UNAVAIL_FIELDS_EXPECTED: int = 10   # 3 header chips + 1 alarm + 6 Stroom

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
# stroom: TagMap maps a MACHINE-level current for eight units.  The export also
#   carries per-motor stroom leaves for 1/3/5l/5r/10l/10r/11/12/18/19 (e.g.
#   "scada/3c/info/5l/schroef 1/stroom"), and TagMap deliberately leaves every
#   PER-MOTOR current unmapped — `amps` is per-MACHINE, never per motor.  Binding
#   a machine total to one of six motor leaves would invent resolution the sim
#   does not have, so those boxes stay unavailable.  Unit 16 has no stroom leaf
#   of any kind in the export (measured) and carries no box on the screen either.
# ---------------------------------------------------------------------------

const STATUS_TAG_FMT : String = "scada/3c/info/%s/em/status"

## Every entry is verbatim in the operator export and mapped by TagMap.  The five
## added beyond the original three (4r/9l/9r/13, 14r) INHERIT an already-approved
## decision rather than making a new one: each is the SAME device class
## (softstarterfrictiewasser / softstarterdroger1) as an approved sibling, and is
## that unit's only stroom leaf of that class.
const STROOM_TAGS : Dictionary = {
	"4l":  "scada/3c/info/4l/softstarterfrictiewasser/stroom",
	"4r":  "scada/3c/info/4r/softstarterfrictiewasser/stroom",
	"6":   "scada/3c/info/6/softstartersnijmolen/stroom",
	"9l":  "scada/3c/info/9l/softstarterfrictiewasser/stroom",
	"9r":  "scada/3c/info/9r/softstarterfrictiewasser/stroom",
	"13":  "scada/3c/info/13/softstarterfrictiewasser/stroom",
	"14l": "scada/3c/info/14l/softstarterdroger1/stroom",
	"14r": "scada/3c/info/14r/softstarterdroger1/stroom",
}

## Why a unit with no STROOM_TAGS entry cannot bind its box.
const NO_STROOM_ROW_REASON : String = "the export carries NO machine-level stroom leaf for this unit — only per-motor ones ('schroef 1'/'schroef 2'/'afvoerschroef'/'fqventilator'), and `amps` in the sim is per-MACHINE, never per motor. Which motor carries the machine total is an operator ruling, so this box stays unbound rather than guessing one. NOT caused by addressing: this unit IS addressable now."

# ---------------------------------------------------------------------------
# Dutch date parts — the header prints a long Dutch date (mockup :32
# "zaterdag 10 augustus 2024").  Locale formatting, not plant data.
# ---------------------------------------------------------------------------


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

# Audit rows, rebuilt by refresh()
## L3C units this world could actually answer for, counted fresh every refresh.
var _stamped   : int = 0


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

# ---------------------------------------------------------------------------
# Audit counts — HmiScreenBase.field_report() reads these through the two
# overrides below.  They cannot be plain consts: GDScript resolves a const in
# the BASE's method body to the base's own copy, so a subclass const of the same
# name would be shadowed and field_report() would silently report 0 / 0 — a
# vacuous green of exactly the kind this screen exists to prevent.
# ---------------------------------------------------------------------------

func _expected_bound() -> int:
	return BOUND_FIELDS_EXPECTED

func _expected_unavail() -> int:
	return UNAVAIL_FIELDS_EXPECTED

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
	root.add_child(_build_header_bar(HEADER_CHIPS))
	root.add_child(_build_alarm_strip(ALARM_UNAVAIL_REASON))
	root.add_child(_build_mimic())
	root.add_child(_build_audit_strip())
	root.add_child(_build_nav_bar())

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
		# MEASURED counts only — the stamped figure is what _resolve_tags actually
		# reached this refresh, never a hard-coded claim about the world.
		_audit_lbl.text = "BINDING  %d live via TagMap · %d niet beschikbaar (\"%s\")   |   %d van %d L3C-units geadresseerd via hun eigen code (l3c_code)" \
			% [_bound.size(), _unavail.size(), UNAVAIL, _stamped, _unit_meta_tagged_count()]

## How many units this screen has a TagMap row set for — the denominator of the
## audit strip's addressed count.
func _unit_meta_tagged_count() -> int:
	var n := 0
	for code in _unit_meta.keys():
		if String((_unit_meta[code] as Dictionary)["tag_unit"]) != "":
			n += 1
	return n

## One get_machine_info() + TagMap.resolve_code() pass per L3C UNIT, keyed back by
## tag string.
##
## THE LOAD-BEARING LINE IS `get_machine_info(code)`.  This loop used to
## de-duplicate by machine id and resolve once per DISTINCT id, which meant five
## friction separators shared one reading and ten units had no reading at all.
## The handle is now the unit's own plant code, which LineFlow mints as that
## node's per-instance key — so each box reads its own machine or nothing.
## Deliberately NO id fallback: falling back would put a Line 3A machine behind an
## L3C caption, which is the defect this replaces.
##
## `_stamped` (declared with the rest of the bound state) counts how many of the
## screen's units the world could actually answer for, so the audit strip prints
## a measurement instead of a claim.
func _resolve_tags() -> Dictionary:
	var out : Dictionary = {}
	_stamped = 0
	if _line_flow == null or not is_instance_valid(_line_flow):
		return out
	if _tagmap == null:
		_tagmap = TagMapScript.new()
	if not _line_flow.has_method("get_machine_info"):
		return out
	var ctx : Dictionary = {"estop_fault_id": ""}
	if _line_flow.has_method("estop_fault_id"):
		ctx["estop_fault_id"] = String(_line_flow.call("estop_fault_id"))
	# Per-INSTANCE fault identity when LineFlow offers it (TagMap prefers this
	# key so an alarm lights one separator, not all five).
	if _line_flow.has_method("estop_fault_key"):
		ctx["estop_fault_key"] = String(_line_flow.call("estop_fault_key"))
	for code in _unit_meta.keys():
		var meta : Dictionary = _unit_meta[code]
		if String(meta["tag_unit"]) == "":
			continue
		var info : Dictionary = _line_flow.call("get_machine_info", String(code))
		if typeof(info) != TYPE_DICTIONARY or info.is_empty():
			continue
		# A world that resolved the handle by id fallback would answer with a
		# machine carrying no code; that is not this unit and must not be shown.
		if String(info.get("l3c_code", "")) != String(code):
			continue
		_stamped += 1
		for r in _tagmap.resolve_code(String(code), info, ctx):
			out[String(r["tag"])] = r
	return out

func _refresh_status(code: String, meta: Dictionary, tag_unit: String, resolved: Dictionary) -> void:
	var dot : ColorRect = _status_dots.get(code, null)
	var key := "status:%s" % code
	if tag_unit == "":
		_mark_unavail(key, code, "mockup :43/:48/:94 (per-drive status square)",
			"TagMap has no row set for %s — its SCADA unit segment is not in TagMap.UNITS, so there is no operator tag to bind" % code)
		_paint_dot(dot, false, true)
		return
	var tag := STATUS_TAG_FMT % tag_unit
	var row : Dictionary = resolved.get(tag, {})
	if row.is_empty() or row.get("value", null) == null:
		_mark_unavail(key, code, "mockup :43/:48/:94 (per-drive status square)",
			"tag \"%s\" did not resolve — no machine in this world carries the code %s (place the line_3c macro; a %s from another line is NOT this unit and is deliberately not substituted)"
				% [tag, code, String(meta["id"])])
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
			"TagMap has no row set for %s — its SCADA unit segment is not in TagMap.UNITS" % code)
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
			"tag \"%s\" did not resolve — no machine in this world carries the code %s (place the line_3c macro; a %s from another line is NOT this unit)"
				% [tag, code, String(meta["id"])])
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

