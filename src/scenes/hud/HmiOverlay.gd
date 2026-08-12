extends CanvasLayer
class_name HmiOverlay

const _SCOPES := preload("res://src/build/HmiScopes.gd")
const _ZONE_PANEL := preload("res://src/scenes/hud/ExtruderZonePanel.gd")
const _EREMA_FAULTS := preload("res://src/sim/EremaFaultRegistry.gd")

## Reconstruction of the real CeDo line PLC touchscreen.
##
## Modelled on the actual operator panels documented in the Cedo-PROD-SWI work
## instructions (e.g. "Lijn 1 Opstart" step 7 "Was 1 hoofd plc scherm": press
## [storingen] on the touchscreen, return via [hoofdmenu], press [start]). The
## SWIs don't contain clean screen exports — only blurry panel photos plus the
## exact button/menu flow — so this is a faithful *reconstruction* of that flow,
## not a pixel copy.
##
## Four screens, every button touch-clickable (mouse is freed to VISIBLE while
## open), wired to the live LineFlow sim:
##   HOOFDMENU      — section dashboard with live status lamps
##   OVERZICHT      — line mimic (Bunker→…→Extruder→Granulaat) + START/STOP/
##                    LEEGDRAAIEN + AUTOMAAT/HAND
##   STORINGEN      — active alarm list, KWITTEREN / RESETTEN
##   HANDBEDIENING  — per-section manual run/stop (gated by AUTOMAAT)
##
## Owned globally — Hmi.gd lazy-loads one instance and reuses it. open_for(label)
## sets the station title and shows it; close returns the cursor to captured.

enum Screen { HOOFDMENU, OVERZICHT, STORINGEN, HANDBEDIENING, MACHINES }

# Signal emitted when a tile on the new HOOFDMENU grid is pressed.
# Carries a scope_id string that open_subscope() can route to a panel.
signal request_subscope(scope_id)

# Storingen sub-tab routing.
enum FaultTab { HISTORY, ACTIVE, ACKNOWLEDGE, SHIELD }

# Sub-scope screen tile definitions for the new HOOFDMENU grid (#207b).
# The tile set is chosen per panel scope by _home_tiles_for_scope() so a
# washing panel doesn't show extruder module tiles and vice-versa.
#
# EXTRUDER grid (#bullet-10, FIX 3) — the documented EREMA BluPort module grid
# from OTHER-erema-bluport-modulegrid-LIJN-3C (188_CeDo1) / hmi_reference.md:131.
# Verbatim Dutch tile labels, in the photographed layout:
#   Row 1: Doseren, Wateronthardheid, Extruder 1, Smeltfilter 1, Smeltpomp 1, Granulaatsysteem
#   Row 2: Smeltfilter 2
#   Row 3: (2e) Doseren
# The invented "Devicon" / "Dryven Controller" tiles (in NO doc) are removed.
const HOME_TILES_EXTRUDER := [
	[
		{"label": "Doseren",            "scope_id": "doseren",             "icon": "D"},
		{"label": "Wateronthardheid",   "scope_id": "wateronthardheid",    "icon": "W"},
		{"label": "Extruder 1",         "scope_id": "extruder_1_blueport", "icon": "E"},
		{"label": "Smeltfilter 1",      "scope_id": "filter_unit_1",       "icon": "F1"},
		{"label": "Smeltpomp 1",        "scope_id": "smeltpomp_1",         "icon": "P1"},
	],
	[
		{"label": "Granulaatsysteem",   "scope_id": "granulaatsysteem",    "icon": "G"},
		{"label": "Smeltfilter 2",      "scope_id": "filter_unit_2",       "icon": "F2"},
		null,
		null,
		{"label": "Doseren (2)",        "scope_id": "doseren_2",           "icon": "D2"},
	],
]

# WASHING grid — routes to the finished wash-line + Kufferath dryer screens.
const HOME_TILES_WASHING := [
	[
		{"label": "Waslijn",            "scope_id": "washing",             "icon": "W"},
		{"label": "Kufferath drogers",  "scope_id": "kufferaths_dryer",    "icon": "K"},
		null,
		null,
		null,
	],
	# Per-unit detail screens, in PLANT ORDER down the line rather than
	# alphabetical — an operator walks the line, they do not read an index.
	# Tile labels are shortened only to fit; the FULL verbatim title is the panel
	# heading on the screen itself (l3c_unit_screens.gd) and is never reworded.
	[
		{"label": "L3C.1 Doseer Silo",  "scope_id": "l3c_unit:L3C.1",      "icon": "1"},
		{"label": "L3C.3 Bezinkafsch.", "scope_id": "l3c_unit:L3C.3",      "icon": "3"},
		{"label": "L3C.4 Frictiesch.",  "scope_id": "l3c_unit:L3C.4",      "icon": "4"},
		{"label": "L3C.5 Transportsch.","scope_id": "l3c_unit:L3C.5",      "icon": "5"},
		{"label": "L3C.6 Maalmolen",    "scope_id": "l3c_unit:L3C.6",      "icon": "6"},
	],
	[
		{"label": "L3C.10 Transportsch.","scope_id": "l3c_unit:L3C.10",    "icon": "10"},
		{"label": "L3C.11 Flotatietank","scope_id": "l3c_unit:L3C.11",     "icon": "11"},
		{"label": "L3C.12 Transportsch.","scope_id": "l3c_unit:L3C.12",    "icon": "12"},
		{"label": "L3C.14 Droger L",    "scope_id": "l3c_unit:L3C.14L",    "icon": "14L"},
		{"label": "L3C.14 Droger R",    "scope_id": "l3c_unit:L3C.14R",    "icon": "14R"},
	],
	[
		{"label": "L3C.16 Plasmaq",     "scope_id": "l3c_unit:L3C.16",     "icon": "16"},
		{"label": "L3C.18 Extr. Silo",  "scope_id": "l3c_unit:L3C.18",     "icon": "18"},
		{"label": "L3C.19 Rondmengv.",  "scope_id": "l3c_unit:L3C.19",     "icon": "19"},
		null,
		null,
	],
]

# SORTING grid — routes to the finished sorteerlijn screen.
const HOME_TILES_SORTING := [
	[
		{"label": "Sorteerlijn",        "scope_id": "sorteerlijn",         "icon": "S"},
		null,
		null,
		null,
		null,
	],
]

# Icon navbar items — replaces the 5 footer buttons (#207b). Each entry has:
#   glyph : Unicode/text label shown on the button
#   kind  : "close"   → triggers close_overlay
#           "screen"  → switches to a built-in screen (set `screen`)
#           "alarm"   → bell icon, badged by active-fault count
#           "noop"    → reserved/placeholder (still tap-able, does nothing)
const NAVBAR_ITEMS := [
	{"glyph": "X",     "kind": "close",  "tip": "Sluiten"},
	{"glyph": "GRID",  "kind": "screen", "screen": Screen.HOOFDMENU, "tip": "Hoofdmenu"},
	{"glyph": "HOME",  "kind": "screen", "screen": Screen.OVERZICHT, "tip": "Overzicht"},
	{"glyph": "BELL",  "kind": "alarm",  "tip": "Storingen"},
	{"glyph": "FAV",   "kind": "noop",   "tip": "Favoriet"},
	{"glyph": "EDIT",  "kind": "screen", "screen": Screen.HANDBEDIENING, "tip": "Handbediening"},
	{"glyph": "TREND", "kind": "noop",   "tip": "Trend"},
	{"glyph": "Rx",    "kind": "noop",   "tip": "Recept"},
	{"glyph": "PWR",   "kind": "noop",   "tip": "Energie"},
	{"glyph": "ECO",   "kind": "noop",   "tip": "Eco / save"},
	{"glyph": "PLC",   "kind": "screen", "screen": Screen.MACHINES, "tip": "Machines"},
	{"glyph": ">",     "kind": "noop",   "tip": "Start"},
]

# --- Plant colour scheme (Siemens-ish steel + signal lamps) -------------------
const C_DIM        := Color(0.0, 0.0, 0.0, 0.62)
const C_BEZEL      := Color(0.10, 0.11, 0.13, 1.0)
const C_HEADER     := Color(0.12, 0.19, 0.25, 1.0)
const C_SCREEN     := Color(0.74, 0.78, 0.76, 1.0)   # the greenish-grey HMI glass
const C_TILE       := Color(0.86, 0.88, 0.86, 1.0)
const C_TILE_EDGE  := Color(0.38, 0.42, 0.40, 1.0)
const C_TEXT_DARK  := Color(0.10, 0.12, 0.11, 1.0)
const C_AMBER      := Color(1.0, 0.86, 0.45, 1.0)
const C_NAV        := Color(0.18, 0.27, 0.34, 1.0)
const C_NAV_SEL    := Color(0.20, 0.46, 0.62, 1.0)
# Signal lamps
const LAMP_OFF     := Color(0.42, 0.45, 0.43, 1.0)   # grey  — not installed
const LAMP_IDLE    := Color(0.90, 0.66, 0.18, 1.0)   # amber — present, idle
const LAMP_RUN     := Color(0.27, 0.78, 0.32, 1.0)   # green — running
const LAMP_FAULT   := Color(0.86, 0.22, 0.18, 1.0)   # red   — fault

# Status codes returned by _group_status / _stage_status
const ST_OFF   := 0
const ST_IDLE  := 1
const ST_RUN   := 2
const ST_FAULT := 3

# Live process-fault thresholds, read off the LineFlow per-machine telemetry.
const BUFFER_JAM_KG := 120.0   # input backlog (kg) that trips an "ophoping" alarm
const DRYER_WET_PCT := 8.0     # pre-extruder moisture % that's too wet to pellet cleanly
const MELT_DIRT_PCT := 1.0     # contamination % carried into the melt = wash underperforming
const QUALITY_MIN   := 70.0    # granulaat grade below this is off-spec

# Line mimic: the conceptual Line-1 process order. Each stage matches LineFlow
# nodes whose placeable id contains any of the listed tokens.
const STAGES := [
	{"name": "BUNKER",      "tokens": ["bunker"]},
	{"name": "SORTEREN",    "tokens": ["sga", "metal_belt", "ballistic", "wind_sifter", "titech", "tomra", "sorteer"]},
	{"name": "SHREDDERS",   "tokens": ["shredder"]},
	{"name": "OPVOER",      "tokens": ["inclined_belt", "feed_hopper", "transport_belt", "transport_screw", "conveyor", "blower"]},
	{"name": "WASSEN",      "tokens": ["prewash", "friction", "intensive", "wash", "was"]},
	{"name": "FLOTATIE",    "tokens": ["flotation", "rotation", "sink_float"]},
	{"name": "ZEVEN",       "tokens": ["kufferath", "rafter", "sieve", "zeef"]},
	{"name": "ONTWATEREN",  "tokens": ["dewater"]},
	{"name": "DROGEN",      "tokens": ["mech_dryer", "dryer", "droger", "centrifuge"]},
	{"name": "MENGSILO",    "tokens": ["mengsilo", "mas_bak", "compactor", "silo"]},
	{"name": "EXTRUDER",    "tokens": ["extruder", "intarema", "erema", "pelletizer", "heetafslag"]},
	{"name": "GRANULAAT",   "tokens": ["__sink__"]},
]

# Main-menu section dashboard groups.
const SECTIONS := [
	{"name": "SORTEERLIJN",  "tokens": ["bunker", "sga", "metal_belt", "ballistic", "wind_sifter", "titech", "tomra", "sorteer"]},
	{"name": "SHREDDERS",    "tokens": ["shredder"]},
	{"name": "WASLIJN",      "tokens": ["prewash", "friction", "intensive", "wash", "was", "flotation", "rotation", "kufferath", "rafter", "dewater", "sieve"]},
	{"name": "MAS DROGERS",  "tokens": ["mech_dryer", "dryer", "droger", "centrifuge", "mas"]},
	{"name": "EXTRUDER",     "tokens": ["extruder", "intarema", "erema", "mengsilo", "compactor", "silo", "pelletizer", "heetafslag"]},
	{"name": "WATER / ZSS",  "tokens": ["zss", "eop", "water", "tank", "pomp", "pump"]},
]

# =============================================================================
var _line_flow : Node = null
var _station   : String = "LIJN 1"
var _screen    : int = Screen.HOOFDMENU
var _refresh_acc : float = 0.0

# Scope this panel is bound to (#165). Set by open_for(label, scope); empty =
# "see everything" (generic / pre-#165 behaviour).
#   lines  : Array[String]   line tags this panel may control
#   tokens : Array[String]   id-substrings of in-scope machines
#   label  : String          friendly title shown in the header
var _scope : Dictionary = {}

# Operating state (local to the panel; START/STOP/AUTOMAAT drive the sim)
var _automaat       : bool = true
var _leegdraaien    : bool = false       # empty-run flag (display only)
var _manual_run     : Dictionary = {}    # section name -> bool (HANDBEDIENING)
var _acked_faults   : Dictionary = {}    # fault code -> true
var _last_fed_mass  : float = 0.0
var _no_feed_secs   : float = 0.0

# --- Persistent chrome widgets ---
var _dim          : ColorRect
var _bezel        : PanelContainer
var _header_title : Label
var _clock_lbl    : Label
var _alarm_chip   : Label
var _content      : MarginContainer
var _nav_btns     : Dictionary = {}      # screen -> Button (built-in screens still navigable)

# Icon navbar (#207b) — built once, refreshed for the bell badge.
var _navbar_btns      : Array = []        # all 12 Buttons in display order
var _alarm_bell_btn   : Button = null     # the BELL button (bg flashes when faults > 0)
var _alarm_bell_flash : float = 0.0       # 0..1 sin-driven flash amount

# Fault timestamp + history (#207c).
# Active fault scope -> first-seen tijd_s (s, in-game wall clock from Time.get_ticks_msec).
var _fault_first_seen : Dictionary = {}
# Ring buffer of every fault transition (cap 256). Each entry: {code, tijd_s, msg, state, suppressed}
# state: "active" | "cleared". Most-recent at the END.
var _fault_history : Array = []
const FAULT_HISTORY_CAP : int = 256
# User-suppressed fault codes (#207c — shield sub-tab).
var _shielded_faults : Dictionary = {}
# Currently selected sub-tab inside the STORINGEN screen.
var _fault_tab : int = FaultTab.ACTIVE
# Active sub-scope screen (#207d) — when set, hides _content's HOOFDMENU.
var _subscope_node : Control = null
var _subscope_id   : String = ""

# --- Per-screen dynamic widgets (rebuilt on screen change) ---
var _stage_tiles  : Array = []           # [{def, lamp:ColorRect, val:Label}]
var _section_tiles: Array = []           # [{def, lamp:ColorRect}]
var _ov_status    : Label = null
var _ov_totals    : Label = null
var _start_btn    : Button = null
var _stop_btn     : Button = null
var _auto_btn     : Button = null
var _fault_box    : VBoxContainer = null
var _manual_rows  : Array = []           # [{section, lamp:ColorRect, btn:Button}]

# --- MACHINES screen state ---------------------------------------------------
# The selection is a per-instance KEY (LineFlow's nd["key"]), never a bare
# placeable id: an id is a machine TYPE and several machines share it, so a bare
# id sent the operator's HAND/RUN/RPM commands to whichever instance LineFlow
# happened to list first — toggling the 3rd blower toggled the 1st.
# Session-scoped by design; nothing persists a machine handle across a save, and
# the ordinal half of the key is only stable between two LineFlow rebuilds.
var _selected_machine_key : String = ""
var _machines_list_vb    : VBoxContainer = null   # left column: scrollable list
var _machines_detail_vb  : VBoxContainer = null   # right column: live detail
var _machines_list_rows  : Array = []             # [{key, id, btn, lamp, lbl}]
# Rebuilt every time the selection changes; refresh() updates only the live widgets.
var _md_title_lbl    : Label = null
var _md_powered_lamp : ColorRect = null
var _md_status_lbl   : Label = null
var _md_buffer_bar   : ProgressBar = null
var _md_thru_lbl     : Label = null
var _md_hand_btn     : Button = null
var _md_run_btn      : Button = null
var _md_safeguard_lbl: Label = null
var _md_rpm_slider   : HSlider = null
var _md_rpm_pct_lbl  : Label = null
var _md_master_max_rpm : float = 100.0   # (legacy) machine primary max rpm
var _md_comp_max     : Dictionary = {}   # component → its rotor's rated max rpm
var _md_comp_rows    : Array = []   # [{name, slider:HSlider, pct_lbl:Label, rpm_lbl:Label, nom_rpm}]
var _md_amps_lbl     : Label = null

## Per-component design RPMs the operator's slider scales. RPM is the rotor's
## actual SPEED (independent of material) — what the operator commands. Throughput
## (kg/s) is the consequence, gated by material availability. A paddle spinning
## empty still has its full RPM here (and still draws the motor idle current).
const _NOMINAL_RPM := {
	# Tank stirrer / paddle stages — slow scrapers.
	"inlet":       30.0,
	"transport_1": 45.0,
	"transport_2": 45.0,
	"outlet":      30.0,
	# Dosing-silo augers — motor RPMs, before the gearbox. Operator usually thinks
	# in Hz (10 Hz ≈ 300 RPM on a 4-pole motor; 50 Hz ≈ 1500 RPM = full speed).
	"auger_1":     1500.0,
	"auger_2":     1500.0,
	"auger_3":     1500.0,
	# Conveyors / belts / screws (motor side, before any gearbox).
	"drive":       1450.0,
	# Shredder / mill rotors run far slower than the drive motor (post-gearbox).
	"rotor":        800.0,
}
static func _nominal_rpm_for(comp_name: String) -> float:
	return float(_NOMINAL_RPM.get(comp_name, 100.0))

# =============================================================================
func _ready() -> void:
	add_to_group("esc_modal_overlay")
	layer = 45
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SECTIONS:
		_manual_run[String(s["name"])] = false
	_build_chrome()
	visible = false
	call_deferred("_find_line_flow")

func _find_line_flow() -> void:
	# Don't overwrite an already-resolved reference (the test harness assigns
	# directly, and we shouldn't drop a live ref because of a transient tree state).
	if _line_flow != null and is_instance_valid(_line_flow):
		return
	# Resolution was current_scene.find_child ONLY, which returns null whenever the
	# HMI runs while current_scene isn't the world (loading curtain, pre-shift, a
	# nested/added world) — producing a FALSE "PLC connection bad" + empty machine
	# list on a perfectly healthy line (MEASURED: LineFlow was live with 27 machines
	# /23 links yet this lookup missed it). Try the robust anchors too: LineFlow is
	# ALWAYS added to the "line_flow" group (MainWorld.gd:268) and hangs under root.
	var tree := get_tree()
	var lf : Node = tree.get_first_node_in_group("line_flow")
	if lf == null:
		var root := tree.current_scene
		if root:
			lf = root.find_child("LineFlow", true, false)
	if lf == null:
		lf = tree.root.find_child("LineFlow", true, false)
	_line_flow = lf

# =============================================================================
# OPEN / CLOSE
# =============================================================================
## Open this overlay scoped to a specific HMI's machine subset (#165). `scope`
## is the dictionary from HmiScopes.gd (lines + tokens + label); pass an empty
## dict (or omit) to see everything — the legacy / generic behaviour.
##
## Re-opening on a different HMI always re-applies the new scope and clears
## stale selection state so HMI-A's MACHINES selection never leaks into HMI-B.
func open_for(label: String, scope: Dictionary = {}) -> void:
	_station = label.to_upper()
	# Replace scope wholesale (don't merge) so closing/re-opening a generic
	# panel after a scoped one fully drops the filter.
	_scope = scope.duplicate(true) if not scope.is_empty() else {}
	# Drop the previous MACHINES selection — the new scope likely doesn't
	# include the previously-selected id, and the rebuild below picks a
	# fresh in-scope default.
	_selected_machine_key = ""
	_find_line_flow()
	if _line_flow and "fed_mass" in _line_flow:
		_last_fed_mass = float(_line_flow.fed_mass)
	_show_screen(Screen.HOOFDMENU)
	visible = true

func is_open() -> bool:
	return visible

func close_overlay() -> void:
	# Closing the whole HMI also tears down any active sub-scope.
	close_subscope()
	visible = false
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

# =============================================================================
# SUB-SCOPE ROUTING (#207d) — tile press on HOOFDMENU opens a per-scope screen
# =============================================================================
const _SUBSCOPE_SCRIPTS := {
	"extruder_1_blueport": "res://src/scenes/hud/scopes/ExtruderBluPortScope.gd",
	"filter_unit_1":       "res://src/scenes/hud/scopes/LaserFilterScope.gd",
	"filter_unit_2":       "res://src/scenes/hud/scopes/LaserFilterScope.gd",
	# Sorteerlijn (3A/3B bunker) — P&ID + SWI-049 3-step startup FSM. The scope
	# auto-wires its startup_completed signal to every ShredderFeedBelt in the
	# scene on _ready(), so pressing the green hardware button actually starts
	# material flow. No extra binding needed here.
	"sorteerlijn":         "res://src/scenes/hud/scopes/SorteerlijnScope.gd",
	# Kufferaths DRD dryer pair — 2-column anti-phase display. open_subscope()
	# binds the local line's MechDryerCycle pair via set_dryer_pair() below.
	"kufferaths_dryer":    "res://src/scenes/hud/scopes/KufferathsDryerScope.gd",
	"washing":             "res://src/scenes/hud/scopes/WashingScope.gd",
	# Per-unit L3C detail screens. ONE layout engine driven by the verbatim spec
	# in src/data/plant/l3c_unit_screens.gd; the scope_id after "l3c_unit:" is the
	# spec key, so adding a screen is adding a spec entry and a menu row — not a
	# new script. open_subscope() calls set_screen() with that suffix below.
	"l3c_unit:L3C.1":     "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.3":     "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.4":     "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.5":     "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.6":     "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.10":    "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.11":    "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.12":    "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.14L":   "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.14R":   "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.16":    "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.18":    "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	"l3c_unit:L3C.19":    "res://src/scenes/hud/scopes/L3CUnitScreen.gd",
	# The remaining BluPort module tiles (FIX 3) don't have a finished scope
	# file yet — open_subscope() bails cleanly (returns false) so the operator
	# stays on HOOFDMENU. The TILE labels are documented-correct (188_CeDo1);
	# the screens are stubbed until built.
	"doseren":             "",
	"doseren_2":           "",
	"wateronthardheid":    "",
	"smeltpomp_1":         "",
	"granulaatsysteem":    "",
}

## Mount a per-scope screen as a child of the bezel. Returns true on success.
func open_subscope(scope_id: String) -> bool:
	# Always tear down any previous sub-scope first — never stack.
	close_subscope()
	if not _SUBSCOPE_SCRIPTS.has(scope_id):
		push_warning("[HmiOverlay] Unknown subscope id: %s" % scope_id)
		return false
	var script_path := String(_SUBSCOPE_SCRIPTS[scope_id])
	if script_path == "":
		# Placeholder tile (Devicon / MFU / Complete Systems / Drive Controller).
		return false
	if not ResourceLoader.exists(script_path):
		push_warning("[HmiOverlay] Subscope script missing: %s" % script_path)
		return false
	var script := load(script_path)
	if script == null:
		return false
	var inst : Object = script.new()
	if not (inst is Control):
		push_warning("[HmiOverlay] Subscope %s is not a Control" % scope_id)
		return false
	var ctrl := inst as Control
	# Anchor full-rect over the bezel so the navbar/header still show through
	# only if the subscope leaves gaps — most subscopes own the whole glass.
	ctrl.set_anchors_preset(Control.PRESET_FULL_RECT)
	_bezel.add_child(ctrl)
	_subscope_node = ctrl
	_subscope_id = scope_id
	# Hide the main content area while a sub-scope owns the glass.
	if _content != null:
		_content.visible = false
	# Standard signal contract — every scope file emits request_close(); wire
	# it back into close_subscope() so the X / Esc returns to HOOFDMENU.
	if ctrl.has_signal("request_close"):
		ctrl.connect("request_close", Callable(self, "close_subscope"))
	# Best-effort context binding: ExtruderBluPortScope wants a line_id; the
	# laser filter scopes want a filter_id. Probe via property name; if the
	# property isn't there the assignment is a no-op (via `in` check).
	if "line_id" in ctrl:
		ctrl.set("line_id", _line_id_from_scope())
	if "filter_id" in ctrl:
		ctrl.set("filter_id", "MPF1" if scope_id == "filter_unit_1" else "MPF2")
	# Kufferaths DRD scope needs the actual L/R MechDryerCycle refs so the
	# Schritt / Motorlast / Schrittlaufzeit pills can read live state. Pulled
	# from LineFlow._dryer_pairs by line_id; falls back to empty Array which
	# the scope tolerates (pills sit at neutral).
	if scope_id == "kufferaths_dryer" and ctrl.has_method("set_dryer_pair"):
		ctrl.call("set_dryer_pair", _dryer_pair_for_line(_line_id_from_scope()))
	# #bullet-10 (FIX 1) — the BluPort extruder scope and the laser-filter scope
	# both ship a setter (set_model / set_filter) that had ZERO callers, so those
	# screens rendered defaults/zeros. Resolve the scoped machine and bind it.
	if scope_id == "extruder_1_blueport" and ctrl.has_method("set_model"):
		var ex_model : Object = _find_extruder_model_for_scope()
		if ex_model != null:
			ctrl.call("set_model", ex_model)
	if (scope_id == "filter_unit_1" or scope_id == "filter_unit_2") and ctrl.has_method("set_filter"):
		var lf : Object = _find_laser_filter_for_scope()
		if lf != null:
			ctrl.call("set_filter", lf)
	# WashingScope (now the Waslijn 3C Overzicht plant mimic) shipped a bind()
	# with ZERO callers repo-wide, which is exactly why every process value on it
	# was a construction-time literal. It reads live state through
	# TagMap x LineFlow.get_machine_info(), so hand it the scope dict + the live
	# LineFlow. Without this call the screen renders "--" everywhere, which is
	# honest but dead.
	if scope_id == "washing" and ctrl.has_method("bind"):
		ctrl.call("bind", _scope, _line_flow)
	# Per-unit L3C screens: the spec key rides in the scope_id after the colon,
	# so one script serves every unit. set_screen() must come BEFORE bind(), or
	# the screen binds a machine code it does not have yet and reports every
	# field unavailable — honest, but wrong.
	if scope_id.begins_with("l3c_unit:") and ctrl.has_method("set_screen"):
		ctrl.call("set_screen", scope_id.substr("l3c_unit:".length()))
		if ctrl.has_method("bind"):
			ctrl.call("bind", _scope, _line_flow)
		# Operator 2026-08-07 — the bottom-nav < / > keys navigate the 13 unit
		# screens in HOME_TILES_WASHING plant order (wrap-around), replacing
		# their "niet gekoppeld" disabled state.
		if ctrl.has_method("wire_nav"):
			var order : Array = _l3c_unit_scope_order()
			var idx : int = order.find(scope_id)
			if idx >= 0 and order.size() > 1:
				var prev_id : String = String(order[(idx - 1 + order.size()) % order.size()])
				var next_id : String = String(order[(idx + 1) % order.size()])
				ctrl.call("wire_nav",
					func() -> void: open_subscope(prev_id),
					func() -> void: open_subscope(next_id))
	return true

## The l3c_unit:* scope ids in HOOFDMENU tile order — the < / > nav sequence.
func _l3c_unit_scope_order() -> Array:
	var out : Array = []
	for tile in HOME_TILES_WASHING:
		var sid := String((tile as Dictionary).get("scope_id", ""))
		if sid.begins_with("l3c_unit:"):
			out.append(sid)
	return out

## Resolve the ExtruderModel for the panel's current scope line (#bullet-10).
## Reuses _find_extruder_model_for() (which matches on the extruder machine's
## config_resource.line_id). Falls back to the first extruder in the scene when
## the scope carries no line tag so a generic panel still binds something live.
func _find_extruder_model_for_scope() -> Object:
	var line_id := _line_id_from_scope()
	if line_id != "":
		var m := _find_extruder_model_for("extruder_" + line_id.to_lower())
		if m != null:
			return m
	# No line tag (or no match): take the first extruder machine's model.
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		if em != null and is_instance_valid(em) and "model" in em and em.model != null:
			return em.model
	return null

## Resolve the LaserFilter serving this scope's extruder line (#bullet-10). The
## macros lay one laser_filter per extruder and ExtruderMachine caches the
## closest member of the "laser_filter" group, so we mirror that: find the
## in-scope extruder machine and return the laser_filter nearest to it. Falls
## back to the first laser_filter in the scene when no extruder is resolvable.
func _find_laser_filter_for_scope() -> Object:
	var extruder_node : Node3D = _find_extruder_machine_for_scope()
	var lf : Object = _closest_laser_filter_to(extruder_node)
	if lf != null:
		return lf
	var filters : Array = get_tree().get_nodes_in_group("laser_filter")
	return filters[0] if not filters.is_empty() else null

## The LaserFilter nearest to `node` (mirrors ExtruderMachine's own
## _closest_in_group). Returns null when no laser_filter is in the scene or when
## `node` is null and the group is empty.
func _closest_laser_filter_to(node: Node3D) -> Object:
	var filters : Array = get_tree().get_nodes_in_group("laser_filter")
	if filters.is_empty():
		return null
	if node == null or not is_instance_valid(node):
		return filters[0]
	var best : Node = null
	var best_d2 : float = INF
	for n in filters:
		var n3 := n as Node3D
		if n3 == null:
			continue
		var d2 : float = (n3.global_position - node.global_position).length_squared()
		if d2 < best_d2:
			best_d2 = d2
			best = n
	return best if best != null else filters[0]

## The ExtruderMachine (scene node) matching this scope's line, or the first one.
func _find_extruder_machine_for_scope() -> Node3D:
	var want := _line_id_from_scope().to_lower()
	var first : Node3D = null
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var n3 := em as Node3D
		if n3 == null or not is_instance_valid(n3):
			continue
		if first == null:
			first = n3
		if want == "":
			continue
		var cfg = em.get("config_resource")
		if cfg != null and String(cfg.get("line_id")).to_lower() == want:
			return n3
	return first

func close_subscope() -> void:
	if _subscope_node != null and is_instance_valid(_subscope_node):
		_subscope_node.queue_free()
	_subscope_node = null
	_subscope_id = ""
	if _content != null:
		_content.visible = true

# Best-effort: derive a Lijn id from the current scope's `lines` list. Returns
# "1" / "3a" / "3c" / "6" etc., or the first entry if multiple — the subscope's
# header just needs *a* tag.
func _line_id_from_scope() -> String:
	if _scope.is_empty():
		return ""
	var lines : Array = _scope.get("lines", [])
	if lines.is_empty():
		return ""
	return String(lines[0])

# Resolve the L/R MechDryerCycle pair for a given line id from LineFlow's
# _dryer_pairs registry. Returns [cycle_L, cycle_R] or [] when no pair is
# discovered for that line. KufferathsDryerScope.set_dryer_pair() accepts the
# empty case gracefully (pills sit at neutral).
func _dryer_pair_for_line(line_id: String) -> Array:
	if _line_flow == null or not is_instance_valid(_line_flow):
		return []
	if not "_dryer_pairs" in _line_flow:
		return []
	var pairs : Dictionary = _line_flow.get("_dryer_pairs")
	if pairs == null or pairs.is_empty():
		return []
	# Pair ids are line-scoped (e.g. "dryer_pair" on Line 3C). If the registry
	# carries multiple pairs (multi-line worlds), prefer the one whose pair_id
	# contains the line_id; otherwise fall back to the first pair.
	var key_lower : String = line_id.to_lower()
	var picked : Dictionary = {}
	for pid in pairs.keys():
		var pid_lower : String = String(pid).to_lower()
		if pid_lower.contains(key_lower) or key_lower.is_empty():
			picked = pairs[pid]
			break
	if picked.is_empty():
		# No line-id match — just take whichever pair exists.
		picked = pairs.values()[0]
	var c_l : Object = picked.get("cycle_L", null)
	var c_r : Object = picked.get("cycle_R", null)
	if c_l == null and c_r == null:
		return []
	return [c_l, c_r]

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("interact"):
		# #207d — a single Esc unwinds one level. If a sub-scope is mounted,
		# Esc returns to the main HOOFDMENU; otherwise it closes the overlay.
		if _subscope_node != null and is_instance_valid(_subscope_node):
			close_subscope()
		else:
			close_overlay()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not visible:
		return
	# Track feed-starvation for the synthetic "no material" alarm.
	if _line_flow and "feed_enabled" in _line_flow and bool(_line_flow.feed_enabled):
		var fed := float(_line_flow.fed_mass) if "fed_mass" in _line_flow else 0.0
		if fed <= _last_fed_mass + 0.001:
			_no_feed_secs += delta
		else:
			_no_feed_secs = 0.0
		_last_fed_mass = fed
	else:
		_no_feed_secs = 0.0
	# Clear the empty-run flag once the line has drained.
	if _leegdraaien and _in_transit() < 0.5:
		_leegdraaien = false
	_refresh_acc += delta
	if _refresh_acc >= 0.25:
		_refresh_acc = 0.0
		_refresh()

# =============================================================================
# CHROME (persistent: bezel + header + content slot + footer nav)
# =============================================================================
const PANEL_W := 900.0
const PANEL_H := 624.0

func _build_chrome() -> void:
	_dim = ColorRect.new()
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.color = C_DIM
	_dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_dim)

	_bezel = PanelContainer.new()
	_bezel.set_anchors_preset(Control.PRESET_CENTER)
	_bezel.custom_minimum_size = Vector2(PANEL_W, PANEL_H)
	_bezel.offset_left   = -PANEL_W * 0.5
	_bezel.offset_top    = -PANEL_H * 0.5
	_bezel.offset_right  =  PANEL_W * 0.5
	_bezel.offset_bottom =  PANEL_H * 0.5
	_bezel.add_theme_stylebox_override("panel", _sb(C_BEZEL, 12, 14))
	add_child(_bezel)

	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 0)
	_bezel.add_child(outer)

	# ---- Header bar -------------------------------------------------------
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", _sb(C_HEADER, 6, 10))
	outer.add_child(header)
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 12)
	header.add_child(hrow)

	var logo := Label.new()
	logo.text = "cedo"
	logo.add_theme_font_size_override("font_size", 24)
	logo.add_theme_color_override("font_color", Color(0.35, 0.72, 0.92, 1))
	hrow.add_child(logo)

	_header_title = Label.new()
	_header_title.text = "LIJN 1  ·  HOOFDMENU"
	_header_title.add_theme_font_size_override("font_size", 19)
	_header_title.add_theme_color_override("font_color", C_AMBER)
	_header_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_header_title)

	_alarm_chip = Label.new()
	_alarm_chip.text = "● GEEN STORING"
	_alarm_chip.add_theme_font_size_override("font_size", 14)
	_alarm_chip.add_theme_color_override("font_color", Color(0.6, 0.95, 0.6, 1))
	_alarm_chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_alarm_chip)

	_clock_lbl = Label.new()
	_clock_lbl.text = "--:--:--"
	_clock_lbl.add_theme_font_size_override("font_size", 16)
	_clock_lbl.add_theme_color_override("font_color", Color(0.85, 0.9, 0.92, 1))
	_clock_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hrow.add_child(_clock_lbl)

	# ---- Content slot (the glass) ----------------------------------------
	var glass := PanelContainer.new()
	glass.add_theme_stylebox_override("panel", _sb(C_SCREEN, 0, 0))
	glass.size_flags_vertical = Control.SIZE_EXPAND_FILL
	outer.add_child(glass)
	_content = MarginContainer.new()
	_content.add_theme_constant_override("margin_left", 16)
	_content.add_theme_constant_override("margin_right", 16)
	_content.add_theme_constant_override("margin_top", 14)
	_content.add_theme_constant_override("margin_bottom", 14)
	glass.add_child(_content)

	# ---- Footer navbar (#207b) — 12-icon strip -----------------------------
	var footer := PanelContainer.new()
	footer.add_theme_stylebox_override("panel", _sb(C_HEADER, 6, 6))
	outer.add_child(footer)
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 4)
	footer.add_child(frow)
	_nav_btns.clear()
	_navbar_btns.clear()
	_alarm_bell_btn = null
	for entry in NAVBAR_ITEMS:
		var b := _build_navbar_item(entry as Dictionary)
		frow.add_child(b)
		_navbar_btns.append(b)

func _build_navbar_item(entry: Dictionary) -> Button:
	var kind := String(entry.get("kind", "noop"))
	var glyph := String(entry.get("glyph", "?"))
	var bg : Color = C_NAV
	var fg : Color = Color(0.92, 0.95, 0.97, 1)
	if kind == "close":
		bg = Color(0.55, 0.20, 0.18, 1)
	var b := _flat_button(glyph, Vector2(64, 42), bg, fg)
	b.add_theme_font_size_override("font_size", 13)
	b.tooltip_text = String(entry.get("tip", glyph))
	match kind:
		"close":
			b.pressed.connect(close_overlay)
		"screen":
			var screen : int = int(entry["screen"])
			b.pressed.connect(_show_screen.bind(screen))
			_nav_btns[screen] = b
		"alarm":
			_alarm_bell_btn = b
			b.pressed.connect(_show_screen.bind(Screen.STORINGEN))
		"noop":
			pass
	return b

func _nav_button(text: String, screen: int) -> Button:
	# Retained for back-compat / tests that drive nav by screen id. The chrome no
	# longer instantiates these, but headless callers can still ask for one.
	var b := _flat_button(text, Vector2(150, 42), C_NAV, Color(0.92, 0.95, 0.97, 1))
	b.pressed.connect(_show_screen.bind(screen))
	_nav_btns[screen] = b
	return b

# =============================================================================
# SCREEN ROUTER
# =============================================================================
func _show_screen(screen: int) -> void:
	# If we're invoked before _ready had a chance to build the chrome (headless
	# test harnesses can do this when there's no main scene), build it now so the
	# call doesn't blow up. Production hits this via Hmi.gd well after _ready.
	if _content == null:
		_build_chrome()
	_screen = screen
	# Clear dynamic refs + content
	_stage_tiles.clear()
	_section_tiles.clear()
	_manual_rows.clear()
	_machines_list_rows.clear()
	_md_comp_rows.clear()
	_ov_status = null
	_ov_totals = null
	_start_btn = null
	_stop_btn = null
	_auto_btn = null
	_fault_box = null
	_machines_list_vb = null
	_machines_detail_vb = null
	_md_title_lbl = null
	_md_powered_lamp = null
	_md_status_lbl = null
	_md_buffer_bar = null
	_md_thru_lbl = null
	_md_hand_btn = null
	_md_run_btn = null
	_md_safeguard_lbl = null
	_md_rpm_slider = null
	_md_rpm_pct_lbl = null
	_md_amps_lbl = null
	for c in _content.get_children():
		c.queue_free()
	match screen:
		Screen.HOOFDMENU:     _build_hoofdmenu()
		Screen.OVERZICHT:     _build_overzicht()
		Screen.STORINGEN:     _build_storingen()
		Screen.HANDBEDIENING: _build_handbediening()
		Screen.MACHINES:      _build_machines()
	# Highlight active nav tab
	for s in _nav_btns:
		var btn: Button = _nav_btns[s]
		btn.add_theme_stylebox_override("normal", _sb(C_NAV_SEL if s == screen else C_NAV, 4, 6))
	_refresh()

# =============================================================================
# SCREEN: HOOFDMENU — section dashboard
# =============================================================================
func _build_hoofdmenu() -> void:
	# #207b — replace the previous 3-col SECTIONS dashboard with a 2-row × 5-col
	# tile grid that routes each tile to a sub-scope screen via request_subscope.
	# Existing built-in screens (OVERZICHT / STORINGEN / HANDBEDIENING / MACHINES)
	# are still reachable from the icon navbar at the bottom.
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	_content.add_child(v)

	var h := Label.new()
	h.text = "HOOFDMENU"
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(h)

	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)

	# #bullet-10 (FIX 2/3) — the tile set depends on the panel scope so a wash
	# panel routes to the wash/kufferath screens, a sorting panel to sorteerlijn,
	# and an extruder panel shows the documented BluPort module grid.
	for row in _home_tiles_for_scope():
		for entry in row:
			if entry == null:
				grid.add_child(_home_tile_placeholder())
			else:
				grid.add_child(_home_tile(entry as Dictionary))

## Pick the HOOFDMENU tile grid for the currently-bound scope (#bullet-10).
## Uses the scope's tokens to decide: washing tokens → wash grid, sorting
## tokens → sorting grid, otherwise the extruder BluPort module grid (also the
## generic/no-scope default, matching the documented 3C panel).
func _home_tiles_for_scope() -> Array:
	var tokens : Array = _scope.get("tokens", []) if not _scope.is_empty() else []
	var has := func(subs: Array) -> bool:
		for tk in tokens:
			var t := String(tk)
			for s in subs:
				if t.find(String(s)) != -1:
					return true
		return false
	# Sorting panel — bunker / sga / titech / tomra tokens.
	if has.call(["sga", "titech", "tomra", "ballistic", "wind_sifter", "sorteer", "bunker"]):
		return HOME_TILES_SORTING
	# Washing panel — wash / flotation / kufferath / dryer tokens.
	if has.call(["wash", "was", "flotation", "kufferath", "dryer", "droger", "centrifuge", "dewater"]):
		return HOME_TILES_WASHING
	# Default: extruder BluPort module grid.
	return HOME_TILES_EXTRUDER

func _home_tile(entry: Dictionary) -> Button:
	var label_text := String(entry.get("label", "?"))
	var scope_id := String(entry.get("scope_id", ""))
	var icon_text := String(entry.get("icon", ""))
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(150, 110)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var bg_idle  := Color(0.18, 0.20, 0.25, 1)
	var bg_hover := Color(0.30, 0.55, 0.85, 1)
	var bg_press := Color(0.22, 0.42, 0.70, 1)
	btn.add_theme_stylebox_override("normal", _sb(bg_idle, 6, 4, C_TILE_EDGE, 1))
	btn.add_theme_stylebox_override("hover",  _sb(bg_hover, 6, 4, C_TILE_EDGE, 1))
	btn.add_theme_stylebox_override("pressed",_sb(bg_press, 6, 4, C_TILE_EDGE, 1))
	btn.text = ""
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 6)
	col.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(col)
	var name_lbl := Label.new()
	name_lbl.text = label_text
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 0.97, 1))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(name_lbl)
	var icon_lbl := Label.new()
	icon_lbl.text = icon_text
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.add_theme_font_size_override("font_size", 28)
	icon_lbl.add_theme_color_override("font_color", Color(0.85, 0.90, 0.95, 1))
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(icon_lbl)
	btn.pressed.connect(_on_home_tile_pressed.bind(scope_id))
	return btn

func _home_tile_placeholder() -> Control:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(150, 110)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_theme_stylebox_override("panel",
		_sb(Color(0.14, 0.15, 0.18, 1), 6, 4, Color(0.22, 0.25, 0.30, 1), 1))
	return box

func _on_home_tile_pressed(scope_id: String) -> void:
	emit_signal("request_subscope", scope_id)
	if scope_id != "":
		open_subscope(scope_id)

func _section_tile(tile_name: String) -> Dictionary:
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(250, 96)
	btn.add_theme_stylebox_override("normal", _sb(C_TILE, 8, 0, C_TILE_EDGE, 2))
	btn.add_theme_stylebox_override("hover", _sb(Color(0.92, 0.94, 0.92), 8, 0, C_NAV_SEL, 2))
	btn.add_theme_stylebox_override("pressed", _sb(Color(0.80, 0.86, 0.90), 8, 0, C_NAV_SEL, 2))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(row)
	var lamp := ColorRect.new()
	lamp.custom_minimum_size = Vector2(22, 22)
	lamp.color = LAMP_OFF
	lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(lamp)
	var lbl := Label.new()
	lbl.text = tile_name
	lbl.add_theme_font_size_override("font_size", 17)
	lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(lbl)
	return {"btn": btn, "lamp": lamp}

# =============================================================================
# SCREEN: OVERZICHT — line mimic + master controls
# =============================================================================
func _build_overzicht() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	_content.add_child(v)

	_ov_status = Label.new()
	_ov_status.add_theme_font_size_override("font_size", 17)
	_ov_status.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(_ov_status)

	# Mimic: 5 columns x 2 rows of stage tiles
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	# #165 — only render stages this physical HMI controls.
	for st in STAGES:
		if not _scope_has_tile(st["tokens"]):
			continue
		var tile := _stage_tile(String(st["name"]))
		grid.add_child(tile["box"])
		_stage_tiles.append({"def": st, "lamp": tile["lamp"], "val": tile["val"]})

	_ov_totals = Label.new()
	_ov_totals.add_theme_font_size_override("font_size", 14)
	_ov_totals.add_theme_color_override("font_color", Color(0.18, 0.22, 0.20, 1))
	v.add_child(_ov_totals)

	# Master control bar
	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 10)
	v.add_child(ctrl)
	_start_btn = _flat_button("▶  START", Vector2(150, 56), LAMP_RUN, Color.WHITE)
	_start_btn.add_theme_font_size_override("font_size", 18)
	_start_btn.pressed.connect(_on_start)
	ctrl.add_child(_start_btn)
	_stop_btn = _flat_button("■  STOP", Vector2(150, 56), LAMP_FAULT, Color.WHITE)
	_stop_btn.add_theme_font_size_override("font_size", 18)
	_stop_btn.pressed.connect(_on_stop)
	ctrl.add_child(_stop_btn)
	var leeg := _flat_button("⧗  LEEGDRAAIEN", Vector2(190, 56), Color(0.72, 0.52, 0.16, 1), Color.WHITE)
	leeg.add_theme_font_size_override("font_size", 16)
	leeg.pressed.connect(_on_leegdraaien)
	ctrl.add_child(leeg)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ctrl.add_child(sp)
	_auto_btn = _flat_button("AUTOMAAT", Vector2(170, 56), C_NAV_SEL, Color.WHITE)
	_auto_btn.add_theme_font_size_override("font_size", 16)
	_auto_btn.pressed.connect(_on_toggle_auto)
	ctrl.add_child(_auto_btn)

func _stage_tile(tile_name: String) -> Dictionary:
	var box := PanelContainer.new()
	box.custom_minimum_size = Vector2(150, 84)
	box.add_theme_stylebox_override("panel", _sb(C_TILE, 6, 0, C_TILE_EDGE, 1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	box.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 6)
	col.add_child(top)
	var lamp := ColorRect.new()
	lamp.custom_minimum_size = Vector2(16, 16)
	lamp.color = LAMP_OFF
	top.add_child(lamp)
	var nl := Label.new()
	nl.text = tile_name
	nl.add_theme_font_size_override("font_size", 13)
	nl.add_theme_color_override("font_color", C_TEXT_DARK)
	top.add_child(nl)
	var val := Label.new()
	val.text = "—"
	val.add_theme_font_size_override("font_size", 12)
	val.add_theme_color_override("font_color", Color(0.25, 0.30, 0.27, 1))
	col.add_child(val)
	return {"box": box, "lamp": lamp, "val": val}

# =============================================================================
# SCREEN: STORINGEN — active alarm list
# =============================================================================
func _build_storingen() -> void:
	# #207c — 4 sub-tabs (history / active / acknowledge / shield) + 3-col table
	# (Nr. | Tijd | Storingtabel). Active is default. Header chip stays static
	# (alarm indicator moved to the navbar bell).
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_content.add_child(v)

	var h := Label.new()
	h.text = "STORINGEN"
	h.add_theme_font_size_override("font_size", 16)
	h.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(h)

	# Sub-tab bar
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 4)
	v.add_child(tabs)
	# Dutch alarm-filter tabs, ISA-18.2 order (Actief default → Gekwitteerd →
	# Onderdrukt → Historie). Was unfinished "icon word" placeholders
	# ("shield shield" etc.) while the rest of the HMI is Dutch.
	tabs.add_child(_fault_tab_btn("Actief",       FaultTab.ACTIVE))
	tabs.add_child(_fault_tab_btn("Gekwitteerd",  FaultTab.ACKNOWLEDGE))
	tabs.add_child(_fault_tab_btn("Onderdrukt",   FaultTab.SHIELD))
	tabs.add_child(_fault_tab_btn("Historie",     FaultTab.HISTORY))

	# 3-col table header
	var hdr := PanelContainer.new()
	hdr.add_theme_stylebox_override("panel", _sb(Color(0.20, 0.27, 0.34, 1), 4, 4))
	v.add_child(hdr)
	var hdr_row := HBoxContainer.new()
	hdr_row.add_theme_constant_override("separation", 6)
	hdr.add_child(hdr_row)
	_add_fault_col_header(hdr_row, "Nr.",          90,  HORIZONTAL_ALIGNMENT_RIGHT)
	_add_fault_col_header(hdr_row, "Tijd",         110, HORIZONTAL_ALIGNMENT_CENTER)
	_add_fault_col_header(hdr_row, "Storingtabel", 0,   HORIZONTAL_ALIGNMENT_LEFT)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	_fault_box = VBoxContainer.new()
	_fault_box.add_theme_constant_override("separation", 4)
	_fault_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_fault_box)

	var ctrl := HBoxContainer.new()
	ctrl.add_theme_constant_override("separation", 10)
	v.add_child(ctrl)
	var ack := _flat_button("KWITTEREN", Vector2(180, 44), Color(0.20, 0.40, 0.55, 1), Color.WHITE)
	ack.pressed.connect(_on_kwitteren)
	ctrl.add_child(ack)
	var reset := _flat_button("RESETTEN", Vector2(180, 44), Color(0.40, 0.42, 0.45, 1), Color.WHITE)
	reset.pressed.connect(_on_reset_faults)
	ctrl.add_child(reset)

func _fault_tab_btn(text: String, tab: int) -> Button:
	var active := (tab == _fault_tab)
	var bg := C_NAV_SEL if active else C_NAV
	var b := _flat_button(text, Vector2(140, 32), bg, Color.WHITE)
	b.add_theme_font_size_override("font_size", 12)
	b.pressed.connect(_on_fault_tab_picked.bind(tab))
	return b

func _on_fault_tab_picked(tab: int) -> void:
	_fault_tab = tab
	# Rebuild only the storingen screen — keep navbar + chrome intact.
	if _screen == Screen.STORINGEN:
		_show_screen(Screen.STORINGEN)

func _add_fault_col_header(row: HBoxContainer, text: String, min_w: int, align: int) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.add_theme_color_override("font_color", Color(0.92, 0.95, 0.97, 1))
	lbl.horizontal_alignment = align
	if min_w > 0:
		lbl.custom_minimum_size = Vector2(min_w, 0)
	else:
		lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)

# =============================================================================
# SCREEN: HANDBEDIENING — per-section manual run/stop
# =============================================================================
func _build_handbediening() -> void:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	_content.add_child(v)

	var h := Label.new()
	h.text = "HANDBEDIENING — alleen actief in HAND-modus"
	h.add_theme_font_size_override("font_size", 15)
	h.add_theme_color_override("font_color", C_TEXT_DARK)
	v.add_child(h)

	for s in SECTIONS:
		# #165 — manual rows are gated by scope, same rule as the dashboard.
		if not _scope_has_tile(s["tokens"]):
			continue
		var sec_name := String(s["name"])
		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", _sb(C_TILE, 6, 0, C_TILE_EDGE, 1))
		v.add_child(row)
		var hr := HBoxContainer.new()
		hr.add_theme_constant_override("separation", 12)
		row.add_child(hr)
		var lamp := ColorRect.new()
		lamp.custom_minimum_size = Vector2(18, 18)
		lamp.color = LAMP_OFF
		hr.add_child(lamp)
		var nl := Label.new()
		nl.text = sec_name
		nl.add_theme_font_size_override("font_size", 15)
		nl.add_theme_color_override("font_color", C_TEXT_DARK)
		nl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hr.add_child(nl)
		var btn := _flat_button("START", Vector2(130, 40), LAMP_RUN, Color.WHITE)
		btn.pressed.connect(_on_manual_toggle.bind(sec_name))
		hr.add_child(btn)
		_manual_rows.append({"section": sec_name, "lamp": lamp, "btn": btn})

# =============================================================================
# CONTROL ACTIONS
# =============================================================================
func _on_start() -> void:
	_leegdraaien = false
	if _line_flow and "feed_enabled" in _line_flow:
		_line_flow.feed_enabled = true
	_refresh()

func _on_stop() -> void:
	_leegdraaien = false
	if _line_flow and "feed_enabled" in _line_flow:
		_line_flow.feed_enabled = false
	_refresh()

func _on_leegdraaien() -> void:
	# Empty-run: stop feeding new material, let what's in the line drain out.
	if _line_flow and "feed_enabled" in _line_flow:
		_line_flow.feed_enabled = false
	_leegdraaien = _in_transit() >= 0.5
	_refresh()

func _on_toggle_auto() -> void:
	_automaat = not _automaat
	_refresh()

func _on_manual_toggle(section: String) -> void:
	if _automaat:
		return                                  # HAND-modus required
	_manual_run[section] = not bool(_manual_run.get(section, false))
	_refresh()

func _on_kwitteren() -> void:
	for f in _compute_faults():
		_acked_faults[String(f["code"])] = true
	_refresh()

func _on_reset_faults() -> void:
	_acked_faults.clear()
	_refresh()

# =============================================================================
# REFRESH (4 Hz) — only the active screen's dynamic widgets
# =============================================================================
func _refresh() -> void:
	# Header clock + title + alarm chip (always)
	var t := Time.get_time_dict_from_system()
	_clock_lbl.text = "%02d:%02d:%02d" % [t["hour"], t["minute"], t["second"]]
	var screen_name : String = ["HOOFDMENU", "OVERZICHT", "STORINGEN", "HANDBEDIENING", "MACHINES"][_screen]
	_header_title.text = "%s  ·  %s" % [_station, screen_name]
	var faults := _compute_faults()
	# Operator 2026-08-07 — a storing-fixen worker acknowledging at a panel
	# (KwitterenStoringTask → NpcAutonomyBoard.mark_npc_acked) counts exactly
	# like the player's KWITTEREN: the bell calms to amber-steady. Ack only
	# silences; the fault row still stands until its condition ends.
	var board := get_node_or_null("/root/NpcAutonomyBoard")
	var unacked := 0
	for f in faults:
		var fcode := String(f["code"])
		if _acked_faults.has(fcode):
			continue
		if board != null and board.has_method("npc_acked") and bool(board.call("npc_acked", fcode)):
			continue
		unacked += 1
	# #207c — header chip is now a small static text label; the live alarm
	# indicator lives on the navbar bell (CHANGE A).
	if faults.is_empty():
		_alarm_chip.text = "geen storing"
		_alarm_chip.add_theme_color_override("font_color", Color(0.55, 0.78, 0.55, 1))
	else:
		_alarm_chip.text = "%d storing%s" % [faults.size(), "en" if faults.size() != 1 else ""]
		_alarm_chip.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 1))
	_refresh_alarm_bell(faults.size(), unacked)

	match _screen:
		Screen.HOOFDMENU:     _refresh_hoofdmenu(faults)
		Screen.OVERZICHT:     _refresh_overzicht(faults)
		Screen.STORINGEN:     _refresh_storingen(faults)
		Screen.HANDBEDIENING: _refresh_handbediening()
		Screen.MACHINES:      _refresh_machines()

# #207b/207c — recolour the navbar BELL when faults are active. Red + animated
# flash when any fault is un-acked; amber + steady when all are acked; default
# nav blue when the active list is empty.
func _refresh_alarm_bell(total: int, unacked: int) -> void:
	if _alarm_bell_btn == null:
		return
	var bg : Color
	if total == 0:
		_alarm_bell_flash = 0.0
		bg = C_NAV
		_alarm_bell_btn.text = "BELL"
	elif unacked > 0:
		# Pulse between red and brightened red so the bell visibly draws the eye.
		var phase := fmod(Time.get_ticks_msec() / 1000.0 * 2.0, TAU)
		var t : float = 0.5 + 0.5 * sin(phase)
		_alarm_bell_flash = t
		bg = LAMP_FAULT.lerp(Color(1.0, 0.40, 0.30, 1), t)
		_alarm_bell_btn.text = "BELL %d" % total
	else:
		_alarm_bell_flash = 0.0
		bg = LAMP_IDLE
		_alarm_bell_btn.text = "BELL %d" % total
	_alarm_bell_btn.add_theme_stylebox_override("normal", _sb(bg, 4, 6))
	_alarm_bell_btn.add_theme_stylebox_override("hover", _sb(bg.lightened(0.10), 4, 6))
	_alarm_bell_btn.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.15), 4, 6))

func _refresh_hoofdmenu(faults: Array) -> void:
	for t in _section_tiles:
		(t["lamp"] as ColorRect).color = _lamp_color(_group_status(t["def"]["tokens"], faults))

func _refresh_overzicht(faults: Array) -> void:
	var feed_on := _feed_on()
	# #165 — show which lines this physical HMI owns, so the operator
	# understands what START / STOP scopes to.
	var scope_lines : Array = _scope.get("lines", []) if not _scope.is_empty() else []
	var scope_tag := ""
	if not scope_lines.is_empty():
		var parts : PackedStringArray = PackedStringArray()
		for ln in scope_lines:
			parts.append(String(ln).to_upper())
		scope_tag = "  [bereik: %s]" % ", ".join(parts)
	if _leegdraaien:
		_ov_status.text = "STATUS:  LEEGDRAAIEN ACTIEF — lijn loopt leeg (%.0f kg in lijn)%s" % [_in_transit(), scope_tag]
		_ov_status.add_theme_color_override("font_color", Color(0.62, 0.42, 0.10, 1))
	elif feed_on:
		_ov_status.text = "STATUS:  LOPEND%s%s" % ["" if faults.is_empty() else "  ▲ met storing", scope_tag]
		_ov_status.add_theme_color_override("font_color", Color(0.13, 0.42, 0.16, 1))
	else:
		_ov_status.text = "STATUS:  GESTOPT%s" % scope_tag
		_ov_status.add_theme_color_override("font_color", Color(0.55, 0.20, 0.16, 1))
	for t in _stage_tiles:
		var sc := _stage_status(t["def"]["tokens"], faults)
		(t["lamp"] as ColorRect).color = _lamp_color(sc)
		(t["val"] as Label).text = _stage_value(t["def"]["tokens"])
	_ov_totals.text = "Doorvoer:  gevoed %.0f kg   ·   granulaat %.0f kg   ·   afval %.0f kg   ·   in lijn %.0f kg" \
		% [_fed(), _gran(), _waste(), _in_transit()]
	# Button enable states reflect feed
	_start_btn.disabled = feed_on
	_stop_btn.disabled = not feed_on
	_auto_btn.text = "AUTOMAAT" if _automaat else "HANDBEDIENING"
	_auto_btn.add_theme_stylebox_override("normal", _sb(C_NAV_SEL if _automaat else Color(0.62, 0.45, 0.14, 1), 4, 6))

func _refresh_storingen(faults: Array) -> void:
	if _fault_box == null:
		return
	for c in _fault_box.get_children():
		c.queue_free()
	# #207c — pick the row set per sub-tab. Always render the same 3-column table.
	var rows : Array = _rows_for_tab(faults)
	if rows.is_empty():
		var ok := Label.new()
		ok.text = "Geen invoeren in deze weergave."
		ok.add_theme_font_size_override("font_size", 14)
		ok.add_theme_color_override("font_color", C_TEXT_DARK)
		_fault_box.add_child(ok)
		return
	for entry in rows:
		var line := _build_fault_row(entry as Dictionary)
		_fault_box.add_child(line)

# Build one of the 3-col fault rows from a uniform dict:
#   {code, tijd_s, msg, state, suppressed, acked}
func _build_fault_row(f: Dictionary) -> PanelContainer:
	var acked := bool(f.get("acked", false))
	var suppressed := bool(f.get("suppressed", false))
	var state := String(f.get("state", "active"))
	var bg : Color
	if suppressed:
		bg = Color(0.78, 0.78, 0.82, 1)
	elif state == "cleared":
		bg = Color(0.86, 0.90, 0.86, 1)
	elif acked:
		bg = Color(0.93, 0.86, 0.62, 1)
	else:
		bg = Color(0.95, 0.74, 0.70, 1)
	var line := PanelContainer.new()
	line.add_theme_stylebox_override("panel", _sb(bg, 4, 4, Color(0.5, 0.3, 0.25, 1), 1))
	var hr := HBoxContainer.new()
	hr.add_theme_constant_override("separation", 6)
	line.add_child(hr)
	var code := Label.new()
	code.text = String(f.get("code", ""))
	code.add_theme_font_size_override("font_size", 13)
	code.add_theme_color_override("font_color", Color(0.3, 0.25, 0.2, 1))
	code.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	code.custom_minimum_size = Vector2(90, 0)
	hr.add_child(code)
	var tijd := Label.new()
	tijd.text = _format_tijd(float(f.get("tijd_s", 0.0)))
	tijd.add_theme_font_size_override("font_size", 13)
	tijd.add_theme_color_override("font_color", C_TEXT_DARK)
	tijd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tijd.custom_minimum_size = Vector2(110, 0)
	hr.add_child(tijd)
	var txt := Label.new()
	var msg := String(f.get("msg", ""))
	if suppressed:
		msg = "[shield] %s" % msg
	elif acked:
		msg = "%s   (gekwiteerd)" % msg
	elif state == "cleared":
		msg = "%s   (hersteld)" % msg
	txt.text = msg
	txt.add_theme_font_size_override("font_size", 13)
	txt.add_theme_color_override("font_color", C_TEXT_DARK)
	txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	txt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hr.add_child(txt)
	return line

# Format a tijd_s (seconds since boot) as HH:MM:SS for the storingen table.
func _format_tijd(tijd_s: float) -> String:
	var ts := int(max(tijd_s, 0.0))
	var hh := (ts / 3600) % 100
	var mm := (ts / 60) % 60
	var ss := ts % 60
	return "%02d:%02d:%02d" % [hh, mm, ss]

# Compose the active row set for the chosen sub-tab.
func _rows_for_tab(active_faults: Array) -> Array:
	var rows : Array = []
	match _fault_tab:
		FaultTab.ACTIVE:
			for f in active_faults:
				var code := String(f.get("code", ""))
				if _shielded_faults.has(code):
					continue
				if _acked_faults.has(code):
					continue
				rows.append({
					"code": code,
					"tijd_s": _fault_first_seen.get(code, 0.0),
					"msg": String(f.get("text", "")),
					"state": "active",
					"suppressed": false,
					"acked": false,
				})
		FaultTab.ACKNOWLEDGE:
			# Recently acknowledged — uses the history ring + ack table.
			var seen := {}
			for i in range(_fault_history.size() - 1, -1, -1):
				var h : Dictionary = _fault_history[i]
				var code := String(h.get("code", ""))
				if seen.has(code):
					continue
				if not _acked_faults.has(code):
					continue
				seen[code] = true
				rows.append({
					"code": code,
					"tijd_s": h.get("tijd_s", 0.0),
					"msg": String(h.get("msg", "")),
					"state": String(h.get("state", "active")),
					"suppressed": bool(h.get("suppressed", false)),
					"acked": true,
				})
				if rows.size() >= 50:
					break
		FaultTab.HISTORY:
			# Full ring buffer (newest first).
			for i in range(_fault_history.size() - 1, -1, -1):
				var h : Dictionary = _fault_history[i]
				var code := String(h.get("code", ""))
				rows.append({
					"code": code,
					"tijd_s": h.get("tijd_s", 0.0),
					"msg": String(h.get("msg", "")),
					"state": String(h.get("state", "active")),
					"suppressed": bool(h.get("suppressed", false)),
					"acked": _acked_faults.has(code),
				})
		FaultTab.SHIELD:
			for code_v in _shielded_faults.keys():
				var code := String(code_v)
				rows.append({
					"code": code,
					"tijd_s": _fault_first_seen.get(code, 0.0),
					"msg": String(_shielded_faults[code_v]),
					"state": "shielded",
					"suppressed": true,
					"acked": _acked_faults.has(code),
				})
	return rows

func _refresh_handbediening() -> void:
	for r in _manual_rows:
		var sec_name := String(r["section"])
		var present := _group_status(_section_def(sec_name)["tokens"]) != ST_OFF
		var on := bool(_manual_run.get(sec_name, false)) and not _automaat
		(r["lamp"] as ColorRect).color = LAMP_RUN if on else (LAMP_IDLE if present else LAMP_OFF)
		var btn: Button = r["btn"]
		btn.disabled = _automaat
		btn.text = "STOP" if on else "START"
		btn.add_theme_stylebox_override("normal", _sb(LAMP_FAULT if on else LAMP_RUN, 4, 6))

# =============================================================================
# SIM QUERIES
# =============================================================================
func _feed_on() -> bool:
	return _line_flow != null and "feed_enabled" in _line_flow and bool(_line_flow.feed_enabled)

func _fed() -> float:
	return float(_line_flow.fed_mass) if (_line_flow and "fed_mass" in _line_flow) else 0.0

func _gran() -> float:
	return float(_line_flow.gran_mass) if (_line_flow and "gran_mass" in _line_flow) else 0.0

func _waste() -> float:
	return float(_line_flow.waste_mass) if (_line_flow and "waste_mass" in _line_flow) else 0.0

func _in_transit() -> float:
	var m := 0.0
	if _line_flow and "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			if nd.has("in"):  m += float(nd["in"].mass_kg)
			if nd.has("out"): m += float(nd["out"].mass_kg)
	return m

## Status for a mimic stage: ST_OFF (no such node), ST_IDLE (present, no
## material), ST_RUN (material flowing), ST_FAULT (matched + active alarm).
func _stage_status(tokens: Array, faults: Array = []) -> int:
	# An active fault scoped to this stage overrides everything → red lamp.
	for f in faults:
		var scope := String(f.get("scope", ""))
		if scope != "" and _id_matches(scope, tokens):
			return ST_FAULT
	if tokens.size() == 1 and String(tokens[0]) == "__sink__":
		return ST_RUN if _gran() > 0.0 else (ST_IDLE if _feed_on() else ST_OFF)
	var present := false
	var active := false
	if _line_flow and "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			if not _id_matches(String(nd.get("id", "")), tokens):
				continue
			present = true
			var m := 0.0
			if nd.has("in"):  m += float(nd["in"].mass_kg)
			if nd.has("out"): m += float(nd["out"].mass_kg)
			if m > 0.01:
				active = true
	if not present:
		return ST_OFF
	if active:
		return ST_RUN
	# Was both arms ST_IDLE (copy-paste bug). Stopped + no feed pending → OFF
	# (grey), feed pending → IDLE (amber). Audit-caught.
	return ST_IDLE if _feed_on() else ST_OFF

func _stage_value(tokens: Array) -> String:
	# The line end shows banked granulaat + its run-average melt grade.
	if tokens.size() == 1 and String(tokens[0]) == "__sink__":
		return "%.0f kg\nQ %.0f/100" % [_gran(), _granulaat_quality()]
	var m := _stage_metrics(tokens)
	if not bool(m["found"]):
		return "n.v.t."
	# Line 1: backlog in the buffer + the smoothed throughput leaving the stage.
	var line1 := "%.0f kg  %.1f kg/s" % [float(m["kg"]), float(m["thru"])]
	# Line 2: the extruder reports melt grade; every wet/dry stage reports the two
	# enemies an operator chases — moisture and contamination.
	var line2 := ""
	if "extruder" in tokens:
		line2 = "Q %.0f/100" % float(m["quality"])
	else:
		line2 = "H2O %.0f%%  vuil %.1f%%" % [float(m["moist"]), float(m["contam"])]
	return line1 + "\n" + line2

## Aggregate the live LineFlow telemetry across every node matching `tokens`.
## Moisture/dirt/quality are averaged mass-weighted by throughput (the stream
## that's actually moving), falling back to a plain average when the stage idles.
func _stage_metrics(tokens: Array) -> Dictionary:
	var m := {"found": false, "kg": 0.0, "thru": 0.0, "moist": 0.0, "contam": 0.0, "quality": 0.0}
	if _line_flow == null or not ("_nodes" in _line_flow):
		return m
	var wsum := 0.0
	var moist_w := 0.0
	var contam_w := 0.0
	var qual_w := 0.0
	var n := 0
	var moist_p := 0.0
	var contam_p := 0.0
	var qual_p := 0.0
	for nd in _line_flow._nodes:
		if not _id_matches(String(nd.get("id", "")), tokens):
			continue
		m["found"] = true
		m["kg"]   = float(m["kg"]) + float(nd.get("buffer", 0.0))
		var th := float(nd.get("thru", 0.0))
		m["thru"] = float(m["thru"]) + th
		var mo := float(nd.get("moist", 0.0))
		var co := float(nd.get("contam", 0.0))
		var qu := float(nd.get("quality", 0.0))
		wsum += th
		moist_w += mo * th
		contam_w += co * th
		qual_w += qu * th
		n += 1
		moist_p += mo
		contam_p += co
		qual_p += qu
	if wsum > 0.001:
		m["moist"]   = moist_w / wsum
		m["contam"]  = contam_w / wsum
		m["quality"] = qual_w / wsum
	elif n > 0:
		m["moist"]   = moist_p / n
		m["contam"]  = contam_p / n
		m["quality"] = qual_p / n
	return m

## The material currently queued at the extruder INPUT — i.e. exactly what is
## about to be pelletised. This is the honest "is the melt wet/dirty?" reading.
func _sink_feed() -> Dictionary:
	var r := {"found": false, "moist": 0.0, "contam": 0.0, "kg": 0.0}
	if _line_flow == null or not ("_nodes" in _line_flow):
		return r
	for nd in _line_flow._nodes:
		if String(nd.get("role", "")) != "sink":
			continue
		var b = nd.get("in", null)
		if b != null and b.mass_kg > 0.05:
			r["found"]  = true
			r["moist"]  = b.moisture_pct()
			r["contam"] = b.contam_pct()
			r["kg"]     = b.mass_kg
	return r

func _granulaat_quality() -> float:
	if _line_flow and _line_flow.has_method("granulaat_quality"):
		return float(_line_flow.granulaat_quality())
	return 0.0

func _stage_tokens(stage_name: String) -> Array:
	for st in STAGES:
		if String(st["name"]) == stage_name:
			return st["tokens"]
	return []

func _node_name(id: String) -> String:
	var item := PlaceableCatalog.get_item(id)
	return String(item.get("name", id)) if not item.is_empty() else id

## Section status for dashboards = best status across its matching stages.
func _group_status(tokens: Array, faults: Array = []) -> int:
	for f in faults:
		var scope := String(f.get("scope", ""))
		if scope != "" and _id_matches(scope, tokens):
			return ST_FAULT
	var best := ST_OFF
	if _line_flow and "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			if not _id_matches(String(nd.get("id", "")), tokens):
				continue
			var m := 0.0
			if nd.has("in"):  m += float(nd["in"].mass_kg)
			if nd.has("out"): m += float(nd["out"].mass_kg)
			var sc := ST_RUN if m > 0.01 else ST_IDLE
			if sc > best:
				best = sc
	return best

func _id_matches(id: String, tokens: Array) -> bool:
	for tk in tokens:
		if id.find(String(tk)) != -1:
			return true
	return false

# =============================================================================
# SCOPE FILTERING (#165)
# =============================================================================
## True iff the LineFlow node id is INSIDE this panel's scope. Empty scope =
## see everything (generic panel / pre-#165 back-compat).
func _scope_has_node(node_id: String, node_line: String = "") -> bool:
	if _scope.is_empty():
		return true
	return _SCOPES.matches(_scope, node_id, node_line)

## True iff a STAGES / SECTIONS / HANDBEDIENING tile (defined by a token list)
## overlaps the scope. For empty scope, everything is in. For a non-empty
## scope, the tile is in if any of its tokens overlaps any scope token AND at
## least one in-scope node matches the tile.
func _scope_has_tile(tile_tokens: Array) -> bool:
	if _scope.is_empty():
		return true
	# __sink__ (the granulaat tile) is line-end, controllable only by the
	# extruder HMI(s).
	if tile_tokens.size() == 1 and String(tile_tokens[0]) == "__sink__":
		var scope_tokens : Array = _scope.get("tokens", [])
		for st in scope_tokens:
			if String(st) == "extruder" or String(st).begins_with("extruder"):
				return true
		return false
	# Token overlap first (cheap rule-out).
	var scope_tokens2 : Array = _scope.get("tokens", [])
	if not scope_tokens2.is_empty():
		var overlap := false
		for tt in tile_tokens:
			var ts := String(tt)
			for st in scope_tokens2:
				var s := String(st)
				if ts.find(s) != -1 or s.find(ts) != -1:
					overlap = true
					break
			if overlap:
				break
		if not overlap:
			return false
	# At least one live LineFlow node must intersect both the tile AND the
	# scope's line filter — keeps off-line sections out of the dashboard.
	if _line_flow == null or not ("_nodes" in _line_flow):
		return true   # no line yet; show the tile so the panel isn't blank
	for nd in _line_flow._nodes:
		var nid := String(nd.get("id", ""))
		if not _id_matches(nid, tile_tokens):
			continue
		if _scope_has_node(nid, String(nd.get("line", ""))):
			return true
	# No in-scope node found — hide the tile.
	return false

func _section_def(section_name: String) -> Dictionary:
	for s in SECTIONS:
		if String(s["name"]) == section_name:
			return s
	return {"name": section_name, "tokens": []}

## Synthetic-but-honest alarms derived from live sim state. Real plants list
## PLC faults here; the sim doesn't raise them yet, so these reflect operating
## conditions an operator would actually see on this screen.
## Live alarms derived from the running sim. Operating-state alarms (no PLC, no
## feed, empty-run) are line-wide (scope ""); process alarms carry a `scope` token
## naming the machine/stage at fault, so the matching mimic tile lights red.
func _compute_faults() -> Array:
	var out : Array = []
	_find_line_flow()   # self-heal a transient early null before crying PLC fault
	if _line_flow == null:
		out.append({"code": "PLC-000", "text": "Geen lijn-PLC gekoppeld in deze scene", "scope": ""})
		_record_fault_transitions(out)
		return out
	# --- operating state ---------------------------------------------------
	if _feed_on() and _no_feed_secs > 3.0:
		out.append({"code": "INV-101", "text": "Geen baal op invoerpunt — lijn vraagt materiaal", "scope": ""})
	if _leegdraaien:
		out.append({"code": "RUN-200", "text": "Leegdraaien actief — geen nieuwe invoer", "scope": ""})

	# --- live process faults from per-machine telemetry --------------------
	# 1) Backlog: material piling up faster than the slowest machine can take it.
	var worst_kg := 0.0
	var worst_id := ""
	if "_nodes" in _line_flow:
		for nd in _line_flow._nodes:
			var buf := float(nd.get("buffer", 0.0))
			if buf > worst_kg:
				worst_kg = buf
				worst_id = String(nd.get("id", ""))
	if worst_kg > BUFFER_JAM_KG:
		out.append({"code": "BUF-300",
			"text": "Ophoping bij %s — %.0f kg in buffer, doorvoer geblokkeerd" % [_node_name(worst_id), worst_kg],
			"scope": worst_id})

	# 2) Wet melt: what's queued at the extruder is too wet → drying underperforms.
	var feed := _sink_feed()
	if bool(feed["found"]) and float(feed["moist"]) > DRYER_WET_PCT:
		out.append({"code": "DRG-310",
			"text": "Droger: restvocht %.0f%% — extruder krijgt nat materiaal" % float(feed["moist"]),
			"scope": "dryer"})
	# 3) Dirty melt: contamination carried into the extruder → wash underperforms.
	if bool(feed["found"]) and float(feed["contam"]) > MELT_DIRT_PCT:
		out.append({"code": "VUIL-420",
			"text": "Smelt te vuil (%.1f%%) — controleer wasrendement" % float(feed["contam"]),
			"scope": "extruder"})

	# 4) Off-spec granulaat: the run-average melt grade has dropped below norm.
	var q := _granulaat_quality()
	if _gran() > 0.0 and q < QUALITY_MIN:
		out.append({"code": "QUA-400",
			"text": "Granulaatkwaliteit %.0f/100 onder norm (min %d)" % [q, int(QUALITY_MIN)],
			"scope": "__sink__"})

	# 5) EREMA canonical fault labels (from operator-style HMI emulator).
	# Walks every extruder_machine in the scene, asks the registry for live
	# trip detections and appends them in the standard {code, text, scope} form.
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		var model : Object = null
		if "model" in em and em.model != null:
			model = em.model
		var line_id : String = ""
		if "line_id" in em:
			line_id = String(em.line_id)
		# #bullet-10 (FIX 5) — hand the registry the laser_filter serving this
		# extruder so the documented 6522/6557 alarms detect off live state.
		var lf : Object = _closest_laser_filter_to(em as Node3D)
		for f in _EREMA_FAULTS.detect_active(model, lf):
			out.append({
				"code":  "EREMA-%04d" % int(f.get("nr", 0)),
				"text":  String(f.get("msg", "")),
				"scope": "extruder" if line_id.is_empty() else "extruder_" + line_id,
			})
	# #207c — persistent tijd_s + ring buffer of fault transitions.
	_record_fault_transitions(out)
	return out

# Tags each active fault with its first-seen tijd_s (seconds since boot), pushes
# new-active / new-cleared transitions onto the ring buffer (cap 256).
func _record_fault_transitions(active: Array) -> void:
	var now_s := float(Time.get_ticks_msec()) / 1000.0
	var active_codes := {}
	for f in active:
		var code := String(f.get("code", ""))
		active_codes[code] = true
		if not _fault_first_seen.has(code):
			_fault_first_seen[code] = now_s
			_push_fault_history({
				"code": code,
				"tijd_s": now_s,
				"msg": String(f.get("text", "")),
				"state": "active",
				"suppressed": _shielded_faults.has(code),
			})
		# Stamp tijd_s on the entry so consumers (rows builder, refresh) can read it.
		f["tijd_s"] = float(_fault_first_seen.get(code, now_s))
	# Detect transitions to cleared: drop the first-seen on the way out so a
	# future re-trip carries a fresh tijd_s.
	for code_v in _fault_first_seen.keys():
		var code := String(code_v)
		if active_codes.has(code):
			continue
		# Was active last tick, now gone — record the clear and forget the timestamp.
		_push_fault_history({
			"code": code,
			"tijd_s": now_s,
			"msg": "Hersteld",
			"state": "cleared",
			"suppressed": _shielded_faults.has(code),
		})
		_fault_first_seen.erase(code)

func _push_fault_history(entry: Dictionary) -> void:
	_fault_history.append(entry)
	while _fault_history.size() > FAULT_HISTORY_CAP:
		_fault_history.pop_front()

# =============================================================================
# HELPERS
# =============================================================================
func _lamp_color(status: int) -> Color:
	match status:
		ST_RUN:   return LAMP_RUN
		ST_IDLE:  return LAMP_IDLE
		ST_FAULT: return LAMP_FAULT
		_:        return LAMP_OFF

func _flat_button(text: String, min_size: Vector2, bg: Color, fg: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = min_size
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", fg)
	b.add_theme_color_override("font_hover_color", fg)
	b.add_theme_color_override("font_pressed_color", fg)
	b.add_theme_color_override("font_disabled_color", Color(fg.r, fg.g, fg.b, 0.45))
	b.add_theme_stylebox_override("normal", _sb(bg, 4, 6))
	b.add_theme_stylebox_override("hover", _sb(bg.lightened(0.10), 4, 6))
	b.add_theme_stylebox_override("pressed", _sb(bg.darkened(0.15), 4, 6))
	b.add_theme_stylebox_override("disabled", _sb(bg.darkened(0.35), 4, 6))
	return b

func _sb(bg: Color, radius: int, margin: int, border: Color = Color(0, 0, 0, 0), border_w: int = 0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if margin > 0:
		s.content_margin_left = margin
		s.content_margin_right = margin
		s.content_margin_top = margin * 0.6
		s.content_margin_bottom = margin * 0.6
	if border_w > 0:
		s.border_width_left = border_w
		s.border_width_right = border_w
		s.border_width_top = border_w
		s.border_width_bottom = border_w
		s.border_color = border
	return s

# =============================================================================
# SCREEN: MACHINES — per-machine HMI (overview + click-drill detail)
# =============================================================================
## Two-column screen: scrollable list of every LineFlow machine on the left,
## the selected machine's live detail panel on the right (HAND/AUTO toggle, ON/
## OFF, fill bar, master RPM%, per-component RPM sliders + live RPM readouts).
## HAND mode bypasses the PLC + safeguards so the operator can start any
## component (or a whole tank) directly — at their own responsibility.
func _build_machines() -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	h.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_content.add_child(h)

	# Left: machine list
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	left.custom_minimum_size = Vector2(280, 0)
	h.add_child(left)
	var lh := Label.new()
	lh.text = "MACHINES"
	lh.add_theme_font_size_override("font_size", 15)
	lh.add_theme_color_override("font_color", C_TEXT_DARK)
	left.add_child(lh)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(scroll)
	_machines_list_vb = VBoxContainer.new()
	_machines_list_vb.add_theme_constant_override("separation", 4)
	_machines_list_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_machines_list_vb)
	_populate_machine_list()

	# Right: detail panel for the selected machine
	_machines_detail_vb = VBoxContainer.new()
	_machines_detail_vb.add_theme_constant_override("separation", 8)
	_machines_detail_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_machines_detail_vb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_machines_detail_vb)
	# Pick an initial selection if none yet — and only within scope (#165).
	if _selected_machine_key == "" and _line_flow != null and _line_flow.has_method("machine_list"):
		var ml: Array = _line_flow.call("machine_list")
		for entry in ml:
			# Scope is a question about the machine TYPE, so it still takes the id.
			if _scope_has_node(String(entry["id"]), String(entry.get("line", ""))):
				_selected_machine_key = String(entry.get("key", ""))
				break
	_build_machine_detail()

func _populate_machine_list() -> void:
	for c in _machines_list_vb.get_children():
		c.queue_free()
	_machines_list_rows.clear()
	_find_line_flow()   # self-heal a transient early null so a live line isn't hidden
	if _line_flow == null or not _line_flow.has_method("machine_list"):
		var empty := Label.new()
		empty.text = "(geen machines)"
		empty.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_list_vb.add_child(empty)
		return
	for m in _line_flow.call("machine_list"):
		var mid := String(m["id"])
		# The HANDLE. machine_list emits one row per NODE, so two blowers are two
		# rows; without a distinct key they would both address the first one.
		var mkey := String(m.get("key", mid))
		# #165 — drop out-of-scope machines so a sorting HMI never lists the
		# washing line, etc. `line` is optional on machine_list (LineFlow
		# doesn't carry it yet) — HmiScopes falls back to id-suffix sniffing.
		var node_line := String(m.get("line", ""))
		if not _scope_has_node(mid, node_line):
			continue
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 32)
		btn.text = ""    # filled by children
		btn.add_theme_stylebox_override("normal",
			_sb(C_TILE if mkey != _selected_machine_key else C_NAV_SEL, 4, 0, C_TILE_EDGE, 1))
		btn.add_theme_stylebox_override("hover",
			_sb(C_NAV_SEL.lightened(0.08), 4, 0, C_NAV_SEL, 1))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		btn.add_child(row)
		var lamp := ColorRect.new()
		lamp.custom_minimum_size = Vector2(14, 14)
		lamp.color = LAMP_OFF
		lamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lamp)
		var lbl := Label.new()
		# LineFlow supplies the display label: the plant tag (L3C.9R) when the
		# machine has one, otherwise "<name> #<n>". Two blowers no longer render
		# as the same row.
		lbl.text = String(m.get("label", mid.replace("_", " ")))
		lbl.add_theme_font_size_override("font_size", 13)
		lbl.add_theme_color_override("font_color",
			C_TEXT_DARK if mkey != _selected_machine_key else Color.WHITE)
		lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(lbl)
		btn.pressed.connect(_on_machine_picked.bind(mkey))
		_machines_list_vb.add_child(btn)
		_machines_list_rows.append({"key": mkey, "id": mid, "btn": btn, "lamp": lamp, "lbl": lbl})

	# LineFlow is wired but produced no rows — either nothing is placed yet, or
	# none of the placed machines fall in this HMI's scope. Show a legible message
	# so an empty line doesn't read as a BROKEN panel (the operator hit exactly
	# this on a save with 0 placed line machines).
	if _machines_list_rows.is_empty():
		var none := Label.new()
		# Distinguish "no line built at all" from "a line IS built but none of its
		# machines fall in THIS HMI's scope" — otherwise a scoped panel on a running
		# plant misleads the operator into rebuilding a line that already exists.
		var total : int = _line_flow.call("machine_list").size()
		none.text = "(geen machines geplaatst — bouw een lijn met Tab)" if total == 0 \
			else "(%d machines op de lijn — geen binnen deze HMI-scope)" % total
		none.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_list_vb.add_child(none)

func _on_machine_picked(key: String) -> void:
	_selected_machine_key = key
	# Rebuild the list (so the selection highlight is correct) and the right pane.
	if _machines_list_vb != null:
		_populate_machine_list()
	_build_machine_detail()

## (Re)build the right-hand detail pane for `_selected_machine_key`. Called on
## selection change. Live values are refreshed by _refresh_machines().
func _build_machine_detail() -> void:
	if _machines_detail_vb == null:
		return
	for c in _machines_detail_vb.get_children():
		c.queue_free()
	_md_comp_rows.clear()
	_md_title_lbl = null
	_md_powered_lamp = null
	_md_status_lbl = null
	_md_buffer_bar = null
	_md_thru_lbl = null
	_md_hand_btn = null
	_md_run_btn = null
	_md_safeguard_lbl = null
	_md_rpm_slider = null
	_md_rpm_pct_lbl = null
	_md_amps_lbl = null

	if _selected_machine_key == "":
		var hint := Label.new()
		hint.text = "Selecteer een machine links."
		hint.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_detail_vb.add_child(hint)
		return
	if _line_flow == null or not _line_flow.has_method("get_machine_info"):
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_key)
	if info.is_empty():
		var miss := Label.new()
		miss.text = "Machine '%s' niet gevonden (niet meer op de lijn?)" % _selected_machine_key
		miss.add_theme_color_override("font_color", C_TEXT_DARK)
		_machines_detail_vb.add_child(miss)
		return

	# Title row: name + powered lamp + status
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 10)
	_machines_detail_vb.add_child(trow)
	_md_powered_lamp = ColorRect.new()
	_md_powered_lamp.custom_minimum_size = Vector2(18, 18)
	_md_powered_lamp.color = LAMP_OFF
	trow.add_child(_md_powered_lamp)
	_md_title_lbl = Label.new()
	# Plant tag first when the machine has one (L3C.9R), so the detail pane names
	# the SAME unit the operator's SCADA screen does; the model name otherwise.
	var _title_code := String(info.get("l3c_code", ""))
	_md_title_lbl.text = _title_code if _title_code != "" \
		else String(info["id"]).replace("_", " ").to_upper()
	_md_title_lbl.add_theme_font_size_override("font_size", 18)
	_md_title_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	trow.add_child(_md_title_lbl)
	_md_status_lbl = Label.new()
	_md_status_lbl.add_theme_font_size_override("font_size", 13)
	_md_status_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.27, 1))
	trow.add_child(_md_status_lbl)
	# Live current draw — a paddle spinning empty still pulls ~35% nominal (motor
	# idle floor), which is the energy cost the operator was asking to see.
	_md_amps_lbl = Label.new()
	_md_amps_lbl.text = "0 A"
	_md_amps_lbl.add_theme_font_size_override("font_size", 13)
	_md_amps_lbl.add_theme_color_override("font_color", C_AMBER)
	trow.add_child(_md_amps_lbl)

	# HAND / AUTO + RUN row
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 8)
	_machines_detail_vb.add_child(crow)
	_md_hand_btn = _flat_button("AUTOMAAT", Vector2(150, 38), C_NAV_SEL, Color.WHITE)
	_md_hand_btn.pressed.connect(_on_machine_toggle_hand)
	crow.add_child(_md_hand_btn)
	_md_run_btn = _flat_button("AAN/UIT", Vector2(120, 38), Color(0.40, 0.42, 0.45, 1), Color.WHITE)
	_md_run_btn.pressed.connect(_on_machine_toggle_run)
	crow.add_child(_md_run_btn)
	_md_safeguard_lbl = Label.new()
	_md_safeguard_lbl.text = ""
	_md_safeguard_lbl.add_theme_font_size_override("font_size", 13)
	_md_safeguard_lbl.add_theme_color_override("font_color", LAMP_FAULT)
	crow.add_child(_md_safeguard_lbl)

	# Buffer / fill bar + throughput
	var brow := HBoxContainer.new()
	brow.add_theme_constant_override("separation", 8)
	_machines_detail_vb.add_child(brow)
	var blbl := Label.new()
	blbl.text = "Vul / buffer"
	blbl.custom_minimum_size = Vector2(110, 0)
	blbl.add_theme_color_override("font_color", C_TEXT_DARK)
	brow.add_child(blbl)
	_md_buffer_bar = ProgressBar.new()
	_md_buffer_bar.min_value = 0.0
	_md_buffer_bar.max_value = 250.0    # OVERLOAD_KG; visually saturates near e-stop
	_md_buffer_bar.value = 0.0
	_md_buffer_bar.custom_minimum_size = Vector2(0, 22)
	_md_buffer_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	brow.add_child(_md_buffer_bar)
	_md_thru_lbl = Label.new()
	_md_thru_lbl.text = "—"
	_md_thru_lbl.add_theme_font_size_override("font_size", 13)
	_md_thru_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	_md_thru_lbl.custom_minimum_size = Vector2(150, 0)
	brow.add_child(_md_thru_lbl)

	# Per-rotor RPM sliders, each in REAL rpm (0..that rotor's rated max). Real
	# machines have NO single "master" — each rotor/drive has its own motor
	# (e.g. the dosing silo's 3 augers), so there is one slider PER component.
	_md_comp_max = info.get("comp_max_rpm", {})
	var comps : Dictionary = info.get("components", {})
	for cname in comps.keys():
		var row := _md_make_rpm_row(String(cname).replace("_", " "), String(cname),
			float(comps[cname]), float(info.get("rate", 0.0)), float(info.get("spin", 0.0)))
		_machines_detail_vb.add_child(row)

	# Extruder-only: append the 7-zone temperature setpoint panel bound to this
	# line's ExtruderModel. Operator can drop individual zones to keep paper /
	# cellulose contamination from burning at the screw (the matrix's "Drop
	# Zone Temps" lever) — the model's motor_torque_pct climbs in response,
	# eventually feeding lumps into the laser filter or tripping FAULT.
	if String(info["id"]).begins_with("extruder"):
		var ex_model := _find_extruder_model_for(String(info["id"]))
		if ex_model != null:
			var sep := HSeparator.new()
			_machines_detail_vb.add_child(sep)
			var zone_panel := _ZONE_PANEL.new()
			zone_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_machines_detail_vb.add_child(zone_panel)
			zone_panel.bind(ex_model)

	# Spacer at the bottom so the panel reads cleanly.
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_machines_detail_vb.add_child(sp)

## Resolve the ExtruderModel powering the LineFlow node `machine_id`. The id
## convention from the catalog is `extruder_<line>` (e.g. "extruder_3a"); the
## scene controller carries the line tag on `config_resource.line_id`. We walk
## the "extruder_machine" group (joined by ExtruderMachine._ready) and match
## case-insensitively against that line tag. Returns null when no controller
## with a matching line is currently in the scene — caller skips the panel.
func _find_extruder_model_for(machine_id: String) -> Object:
	var prefix := "extruder_"
	if not machine_id.begins_with(prefix):
		return null
	var want := machine_id.substr(prefix.length()).to_lower()
	for em in get_tree().get_nodes_in_group("extruder_machine"):
		if em == null or not is_instance_valid(em):
			continue
		var cfg = em.get("config_resource")
		if cfg == null:
			continue
		var line_id := String(cfg.get("line_id")).to_lower()
		if line_id == want:
			return em.get("model")
	return null

func _md_make_rpm_row(label_text: String, comp_key: String, pct: float, _design_rate: float, _spin: float) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var lbl := Label.new()
	lbl.text = label_text
	lbl.custom_minimum_size = Vector2(110, 0)
	lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(lbl)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 2.0
	slider.step = 0.05
	slider.value = pct
	slider.custom_minimum_size = Vector2(0, 22)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var pct_lbl := Label.new()
	pct_lbl.text = "%d %%" % int(round(pct * 100.0))
	pct_lbl.custom_minimum_size = Vector2(60, 0)
	pct_lbl.add_theme_color_override("font_color", C_TEXT_DARK)
	pct_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(pct_lbl)
	var rpm_lbl := Label.new()
	# Live RPM readout — the ROTOR speed the operator's setting commands,
	# INDEPENDENT of material. A paddle spinning at full RPM with no inflow still
	# reads its full RPM here (and still draws idle current, shown up top).
	rpm_lbl.text = "— RPM"
	rpm_lbl.custom_minimum_size = Vector2(100, 0)
	rpm_lbl.add_theme_color_override("font_color", Color(0.25, 0.30, 0.27, 1))
	rpm_lbl.add_theme_font_size_override("font_size", 13)
	row.add_child(rpm_lbl)
	# Wire the slider write-back. __master__ goes to set_machine_rpm_pct; component
	# keys go to set_machine_component_pct.
	if comp_key == "__master__":
		# Master is REAL RPM (0..rated max), not a percentage.
		slider.max_value = _md_master_max_rpm
		slider.step = maxf(_md_master_max_rpm / 40.0, 1.0)
		slider.value = pct * _md_master_max_rpm
		pct_lbl.text = "%d RPM" % int(round(pct * _md_master_max_rpm))
		slider.value_changed.connect(_on_master_rpm_changed)
		_md_rpm_slider = slider
		_md_rpm_pct_lbl = pct_lbl
	else:
		# This component (one motor) is controlled in REAL rpm, 0..its rotor's max.
		var cmax : float = float(_md_comp_max.get(comp_key, _nominal_rpm_for(comp_key)))
		slider.max_value = cmax
		slider.step = maxf(cmax / 40.0, 1.0)
		slider.value = pct * cmax
		pct_lbl.text = "%d RPM" % int(round(pct * cmax))
		slider.value_changed.connect(_on_component_rpm_changed.bind(comp_key))
		_md_comp_rows.append({
			"name": comp_key, "slider": slider, "pct_lbl": pct_lbl, "rpm_lbl": rpm_lbl,
			"nom_rpm": cmax, "max_rpm": cmax,
		})
	return row

## The placeable id of the currently selected machine, for the #165 scope gate.
## Scope is a question about the machine TYPE ("does this HMI cover blowers"),
## so it needs the id, not the per-instance key. Empty when nothing is selected
## or the selection no longer exists — _scope_has_node("") is then the refusal.
func _selected_machine_scope_id() -> String:
	if _line_flow == null or _selected_machine_key == "":
		return ""
	if not _line_flow.has_method("get_machine_info"):
		return ""
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_key)
	return String(info.get("id", ""))

func _on_machine_toggle_hand() -> void:
	if _line_flow == null or _selected_machine_key == "":
		return
	# #165 — refuse scope-violating writes. Belt-and-braces: the UI already
	# filters the list, but a stale selection from a previous panel could
	# survive an open_for() race. This is the hard gate.
	if not _scope_has_node(_selected_machine_scope_id()):
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_key)
	var was_hand := bool(info.get("hand_mode", false))
	_line_flow.call("set_machine_hand_mode", _selected_machine_key, not was_hand)

func _on_machine_toggle_run() -> void:
	if _line_flow == null or _selected_machine_key == "":
		return
	if not _scope_has_node(_selected_machine_scope_id()):
		return   # #165 — scope guard
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_key)
	if not bool(info.get("hand_mode", false)):
		return   # AAN/UIT only works in HAND mode (PLC owns it in AUTO)
	var was_on := bool(info.get("manual_on", false))
	_line_flow.call("set_machine_manual_on", _selected_machine_key, not was_on)

func _on_master_rpm_changed(value: float) -> void:
	if _line_flow == null or _selected_machine_key == "":
		return
	if not _scope_has_node(_selected_machine_scope_id()):
		return   # #165 — scope guard
	# Slider is in real RPM; LineFlow wants a 0..1 fraction of the rated max.
	var frac : float = value / maxf(_md_master_max_rpm, 1.0)
	_line_flow.call("set_machine_rpm_pct", _selected_machine_key, frac)
	if _md_rpm_pct_lbl != null:
		_md_rpm_pct_lbl.text = "%d RPM" % int(round(value))

func _on_component_rpm_changed(value: float, comp_key: String) -> void:
	if _line_flow == null or _selected_machine_key == "":
		return
	if not _scope_has_node(_selected_machine_scope_id()):
		return   # #165 — scope guard
	# Slider is real rpm for this rotor; LineFlow wants a 0..1 fraction of its max.
	var cmax : float = float(_md_comp_max.get(comp_key, 100.0))
	_line_flow.call("set_machine_component_pct", _selected_machine_key, comp_key, value / maxf(cmax, 1.0))
	for r in _md_comp_rows:
		if String(r["name"]) == comp_key:
			(r["pct_lbl"] as Label).text = "%d RPM" % int(round(value))
			break

## 4 Hz live refresh of the MACHINES screen (list lamps + detail panel readouts).
func _refresh_machines() -> void:
	if _line_flow == null or not _line_flow.has_method("get_machine_info"):
		return
	# Update the list-row lamps (live powered state).
	for r in _machines_list_rows:
		var li : Dictionary = _line_flow.call("get_machine_info", String(r["key"]))
		if li.is_empty():
			continue
		var c : Color = LAMP_OFF
		if bool(li.get("powered", false)) and float(li.get("spin", 0.0)) > 0.05:
			c = LAMP_RUN
		elif float(li.get("buffer", 0.0)) > 1.0:
			c = LAMP_IDLE
		(r["lamp"] as ColorRect).color = c
	# Update the detail panel.
	if _md_title_lbl == null or _selected_machine_key == "":
		return
	var info : Dictionary = _line_flow.call("get_machine_info", _selected_machine_key)
	if info.is_empty():
		return
	var hand := bool(info.get("hand_mode", false))
	var powered := bool(info.get("powered", false))
	var manual_on := bool(info.get("manual_on", false))
	var spin := float(info.get("spin", 0.0))
	var buffer := float(info.get("buffer", 0.0))
	var thru := float(info.get("thru", 0.0))
	var rate := float(info.get("rate", 0.0))
	_md_powered_lamp.color = LAMP_RUN if (powered and spin > 0.05) else (LAMP_IDLE if buffer > 1.0 else LAMP_OFF)
	_md_status_lbl.text = "%.1f%% spin · %.1f kg buffer · %.2f kg/s" % [spin * 100.0, buffer, thru]
	_md_hand_btn.text = ("HAND  ●" if hand else "AUTOMAAT")
	_md_hand_btn.add_theme_stylebox_override("normal",
		_sb(Color(0.72, 0.52, 0.16, 1) if hand else C_NAV_SEL, 4, 6))
	_md_run_btn.text = ("AAN" if manual_on else "UIT")
	_md_run_btn.add_theme_stylebox_override("normal",
		_sb(LAMP_RUN if (hand and manual_on) else Color(0.40, 0.42, 0.45, 1), 4, 6))
	_md_run_btn.disabled = not hand
	_md_safeguard_lbl.text = "⚠ Beveiligingen overruled (HAND)" if hand else ""
	_md_buffer_bar.value = clampf(buffer, 0.0, _md_buffer_bar.max_value)
	# Throughput / rate
	_md_thru_lbl.text = "%.2f / %.2f kg/s" % [thru, rate]
	# (No master row anymore — each rotor is controlled per-component below.)
	_md_comp_max = info.get("comp_max_rpm", _md_comp_max)
	# Live current — non-zero whenever the rotor is spinning (even starved), which is
	# the energy cost the operator was asking to see for "spinning empty."
	if _md_amps_lbl != null:
		var amps := float(info.get("amps", 0.0))
		_md_amps_lbl.text = "Stroom: %.1f A" % amps
	# Per-component readouts: pct_lbl = the SETPOINT in rpm (fraction × this
	# rotor's max); rpm_lbl = the LIVE actual rpm (with the spin-up ramp).
	var comps : Dictionary = info.get("components", {})
	for r in _md_comp_rows:
		var cname := String(r["name"])
		if not comps.has(cname):
			continue
		var cpct := float(comps[cname])
		var cmax := float(r.get("max_rpm", 100.0))
		(r["pct_lbl"] as Label).text = "%d RPM" % int(round(cpct * cmax))
		(r["rpm_lbl"] as Label).text = "%.0f RPM" % (cmax * spin * cpct)
