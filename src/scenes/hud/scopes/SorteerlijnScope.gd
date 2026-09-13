extends Control
class_name SorteerlijnScope

## Sorteerlijn (sorting line) scope panel for the Lijn 3A/3B sorting HMI.
##
## Reconstruction of the real CeDo line-3A/3B sorting touchscreen, combining
## photo references from the bunker HMI (HMI_sorteerlijn_bunker.jpg), the
## partial sorter overview (sorteerlijn_partial.png), the 3A/3B center-HMI
## photo (sorting_line_3A_3B_center_of_HMI.png) and the operator P&ID PDF
## (sorteerlijn_overzicht.pdf).
##
## Three sub-pages (TabContainer):
##   "Overzicht"        — blue-background P&ID mimic with labeled bubble nodes
##                        (2020/2025/2031/2035/2040/3002/3004/3006/3008/3010/
##                        3103/3104/3107/3108), Sorteer tags on 3002/3006,
##                        Zwanenhals on the right, a status feed text box,
##                        a "Herstart" button that pops a job-info dialog,
##                        and a DAMP pump icon bottom-left.
##   "Bunker setpoints" — 10-row setpoint table (name / setpoint / limit /
##                        on-off toggle) plus the Bunkersnelheid sub-panel
##                        (Beide / Zonder 3A / Zonder 3B / Vertraging,
##                        Pers alleen / Sortir omschal / Vert terug) and a
##                        center "filling setpoint" actual value.
##   "Startup"          — 3-step FSM per SWI-049: Automaatknop → Voorverwarmen
##                        (15 s) → Groene drukknop op het paneel.
##
## Bottom button row is always visible (Auto highlights green when active):
##   Auto | Hand | Bell | I | 0 | Nummer richtlijnen | 0 | Enkeling-Stop |
##   reset | Overzicht | Start scherm
##
## Usage:
##   var scope_panel := SorteerlijnScope.new()
##   scope_panel.bind(sorteerlijn_model)     # optional — stubs out cleanly
##   scope_panel.faults_active = false       # set true to block startup FSM
##   parent.add_child(scope_panel)
##   scope_panel.request_close.connect(close_callback)
##   scope_panel.startup_completed.connect(on_ready)
##
## Signals:
##   request_close()       — bottom-row "Start scherm" press wants to return
##                           to HmiOverlay HOOFDMENU.
##   startup_completed()   — operator finished the 3-step startup; READY.

signal request_close()
signal startup_completed()

# -----------------------------------------------------------------------------
# Palette — kept locally so the scope panel can be instantiated standalone
# (HmiOverlay's PALETTE constants are class-scoped to HmiOverlay; depending on
# them would force an instance reference). Values match HmiOverlay where they
# overlap so the panel reads as part of the same plant.
# -----------------------------------------------------------------------------
const C_BEZEL      : Color = Color(0.10, 0.11, 0.13, 1.0)
const C_HEADER     : Color = Color(0.12, 0.19, 0.25, 1.0)
const C_SCREEN     : Color = Color(0.74, 0.78, 0.76, 1.0)
const C_TILE       : Color = Color(0.86, 0.88, 0.86, 1.0)
const C_TILE_EDGE  : Color = Color(0.38, 0.42, 0.40, 1.0)
const C_TEXT_DARK  : Color = Color(0.10, 0.12, 0.11, 1.0)
const C_AMBER      : Color = Color(1.0, 0.86, 0.45, 1.0)
const C_PID_BG     : Color = Color(0.08, 0.18, 0.40, 1.0)    # deep blue P&ID
const C_PID_NODE   : Color = Color(0.94, 0.96, 0.98, 1.0)
const C_PID_LINE   : Color = Color(0.85, 0.90, 0.96, 0.85)
const C_PID_TAG    : Color = Color(1.0, 0.86, 0.18, 1.0)     # yellow Sorteer
const LAMP_OFF     : Color = Color(0.42, 0.45, 0.43, 1.0)
const LAMP_IDLE    : Color = Color(0.90, 0.66, 0.18, 1.0)
const LAMP_RUN     : Color = Color(0.27, 0.78, 0.32, 1.0)
const LAMP_FAULT   : Color = Color(0.86, 0.22, 0.18, 1.0)
const C_BTN        : Color = Color(0.22, 0.25, 0.28, 1.0)
const C_BTN_SEL    : Color = Color(0.20, 0.46, 0.62, 1.0)
const C_BTN_GREEN  : Color = Color(0.20, 0.55, 0.28, 1.0)

# -----------------------------------------------------------------------------
# Startup FSM
# -----------------------------------------------------------------------------
enum StartupState { IDLE, AUTOMAAT, VOORVERWARM, READY, FAULT_BLOCK }

const PREHEAT_SECONDS : float = 15.0

# -----------------------------------------------------------------------------
# P&ID node layout — coordinates are normalised (0..1) inside the P&ID panel
# so the mimic survives a resize. Order matches the operator drawing.
# -----------------------------------------------------------------------------
const PID_NODES : Array = [
	{"id": "2020", "x": 0.08, "y": 0.18, "tag": ""},
	{"id": "2025", "x": 0.18, "y": 0.34, "tag": ""},
	{"id": "2031", "x": 0.08, "y": 0.55, "tag": ""},
	{"id": "2035", "x": 0.18, "y": 0.74, "tag": ""},
	{"id": "2040", "x": 0.30, "y": 0.86, "tag": ""},
	{"id": "3002", "x": 0.42, "y": 0.30, "tag": "Sorteer"},
	{"id": "3004", "x": 0.52, "y": 0.48, "tag": ""},
	{"id": "3006", "x": 0.62, "y": 0.30, "tag": "Sorteer"},
	{"id": "3008", "x": 0.72, "y": 0.48, "tag": ""},
	{"id": "3010", "x": 0.82, "y": 0.30, "tag": ""},
	{"id": "3103", "x": 0.45, "y": 0.72, "tag": ""},
	{"id": "3104", "x": 0.58, "y": 0.72, "tag": ""},
	{"id": "3107", "x": 0.72, "y": 0.72, "tag": ""},
	{"id": "3108", "x": 0.84, "y": 0.62, "tag": ""},
]

# Status feed lines shown in the Overzicht textbox.
const STATUS_FEED : Array = [
	"5170 Transportband in werking",
	"4003 Sorteercriteria OK",
	"4003 Sorteed aanwezig",
	"1251 Product aanwezig",
	"Status 1-1-1",
]

# Bunker setpoint defaults — row 1 empty, 2..10 full per spec
const BUNKER_SETPOINTS : Array = [
	{"name": "Setpoint 1",  "sp": 0,   "lim": 0,   "on": false},
	{"name": "Setpoint 2",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 3",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 4",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 5",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 6",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 7",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 8",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 9",  "sp": 100, "lim": 110, "on": true},
	{"name": "Setpoint 10", "sp": 100, "lim": 110, "on": true},
]

# -----------------------------------------------------------------------------
# State
# -----------------------------------------------------------------------------
var _model : Object = null
var faults_active : bool = false
var _automaat_active : bool = true     # bottom-row Auto/Hand toggle

var _startup_state : int = StartupState.IDLE
var _preheat_remaining : float = 0.0

# Dynamic refs (rebuilt on bind / startup state change)
var _tabs : TabContainer = null
var _startup_label : Label = null
var _startup_button : Button = null
var _startup_progress : ProgressBar = null
var _startup_fault_warn : Label = null
var _auto_button : Button = null
var _hand_button : Button = null
var _bunker_fill_value : Label = null
var _filling_actual : int = 258

# -----------------------------------------------------------------------------
# Construction
# -----------------------------------------------------------------------------
func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(880, 560)
	_build_ui()
	set_process(true)
	# #218 — auto-wire SWI-049 READY → request_start on every feed belt.
	# Guarded against headless tests that instantiate the scope outside a
	# SceneTree (get_tree() would be null).
	if is_inside_tree():
		var tree : SceneTree = get_tree()
		if tree != null and tree.current_scene != null:
			wire_to_feed_belts(tree.current_scene)

## Bind to an optional SorteerlijnModel. Stubs out cleanly when no model is
## passed — the panel falls back to local state for the demo / test path.
func bind(model: Object = null) -> void:
	_model = model
	if _model != null and is_instance_valid(_model):
		if "filling_setpoint" in _model:
			_filling_actual = int(_model.filling_setpoint)
		if _bunker_fill_value != null and is_instance_valid(_bunker_fill_value):
			_bunker_fill_value.text = "%d" % _filling_actual

## #218 — When startup_completed fires, walk every ShredderFeedBelt in the
## scene and call request_start so the operator's SWI-049 sequence actually
## starts material flow. Idempotent: connecting twice for the same scene_root
## is a no-op, matching how HmiOverlay may re-mount this scope across closes.
func wire_to_feed_belts(scene_root : Node) -> void:
	if scene_root == null:
		return
	var cb : Callable = Callable(self, "_on_startup_completed_wired").bind(scene_root)
	if not startup_completed.is_connected(cb):
		startup_completed.connect(cb)

func _on_startup_completed_wired(scene_root : Node) -> void:
	if scene_root == null or not is_instance_valid(scene_root):
		return
	var tree : SceneTree = scene_root.get_tree()
	if tree == null:
		return
	for belt in tree.get_nodes_in_group("shredder_feed_belt"):
		if belt != null and belt.has_method("request_start"):
			# #audit-H9 — only start the belts that belong to THIS sorteerlijn
			# (bunker + SGA). Without this filter, startup_completed on line 1's
			# sorteerlijn would request_start on every ShredderFeedBelt in the
			# scene, including those on unrelated lines. We identify the sorteerlijn
			# belt by macro_id containing "bunker" or "sga" (the two machine types
			# that spawn ShredderFeedBelt). Any belt without a macro_id meta is also
			# accepted for backwards compatibility with hand-placed or test belt nodes.
			var owns_belt := true
			if (belt as Node3D).has_meta("macro_id"):
				var mid := String((belt as Node3D).get_meta("macro_id"))
				owns_belt = mid.contains("bunker") or mid.contains("sga")
			if owns_belt:
				belt.request_start()

# -----------------------------------------------------------------------------
# UI top-level
# -----------------------------------------------------------------------------
func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	var root := VBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 4)
	add_child(root)

	# Tabs
	_tabs = TabContainer.new()
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(_tabs)

	var t_overzicht := _build_overzicht_tab()
	t_overzicht.name = "Overzicht"
	_tabs.add_child(t_overzicht)

	var t_bunker := _build_bunker_tab()
	t_bunker.name = "Bunker setpoints"
	_tabs.add_child(t_bunker)

	var t_startup := _build_startup_tab()
	t_startup.name = "Startup"
	_tabs.add_child(t_startup)

	# Bottom button row — always visible.
	var br := _build_bottom_row()
	root.add_child(br)

# =============================================================================
# TAB 1 — OVERZICHT (P&ID mimic)
# =============================================================================
func _build_overzicht_tab() -> Control:
	var page := MarginContainer.new()
	page.add_theme_constant_override("margin_left", 6)
	page.add_theme_constant_override("margin_right", 6)
	page.add_theme_constant_override("margin_top", 6)
	page.add_theme_constant_override("margin_bottom", 6)

	var split := HBoxContainer.new()
	split.add_theme_constant_override("separation", 8)
	page.add_child(split)

	# Left: the blue P&ID itself
	var pid_holder := PanelContainer.new()
	pid_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pid_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pid_holder.add_theme_stylebox_override("panel", _sb(C_PID_BG, 4, 4))
	split.add_child(pid_holder)

	var pid := Control.new()
	pid.custom_minimum_size = Vector2(520, 380)
	pid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pid_holder.add_child(pid)

	# Zwanenhals label on the right edge of the P&ID
	var zw := Label.new()
	zw.text = "Zwanenhals"
	zw.add_theme_color_override("font_color", C_PID_NODE)
	zw.add_theme_font_size_override("font_size", 12)
	zw.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	zw.offset_left = -120
	zw.offset_top = 12
	zw.offset_right = -8
	zw.offset_bottom = 32
	pid.add_child(zw)

	# Bubble nodes — laid out at PID_NODES coordinates after the holder has
	# its real size (deferred so size is non-zero).
	pid.call_deferred("_dummy")  # noop — placeholder for clarity
	_populate_pid_nodes(pid)
	pid.resized.connect(func(): _populate_pid_nodes(pid))

	# DAMP pump icon bottom-left
	var damp := PanelContainer.new()
	damp.add_theme_stylebox_override("panel", _sb(Color(0.18, 0.32, 0.55, 1.0), 6, 4))
	damp.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	damp.offset_left = 8
	damp.offset_top = -52
	damp.offset_right = 96
	damp.offset_bottom = -8
	pid.add_child(damp)
	var dlbl := Label.new()
	dlbl.text = "DAMP\npump"
	dlbl.add_theme_color_override("font_color", C_PID_NODE)
	dlbl.add_theme_font_size_override("font_size", 11)
	dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	damp.add_child(dlbl)

	# Right: status feed text box + Herstart button
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(260, 0)
	right.add_theme_constant_override("separation", 6)
	split.add_child(right)

	var feed_lbl := Label.new()
	feed_lbl.text = "STATUS"
	feed_lbl.add_theme_color_override("font_color", C_AMBER)
	feed_lbl.add_theme_font_size_override("font_size", 12)
	right.add_child(feed_lbl)

	var feed_box := PanelContainer.new()
	feed_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	feed_box.add_theme_stylebox_override("panel", _sb(C_SCREEN, 4, 6))
	right.add_child(feed_box)
	var feed_v := VBoxContainer.new()
	feed_v.add_theme_constant_override("separation", 2)
	feed_box.add_child(feed_v)
	for line in STATUS_FEED:
		var l := Label.new()
		l.text = "  " + String(line)
		l.add_theme_color_override("font_color", C_TEXT_DARK)
		l.add_theme_font_size_override("font_size", 12)
		feed_v.add_child(l)

	var herstart := Button.new()
	herstart.text = "Herstart"
	herstart.custom_minimum_size = Vector2(0, 36)
	herstart.pressed.connect(_on_herstart_pressed)
	right.add_child(herstart)

	return page

# Build the P&ID bubble nodes inside the supplied Control. Re-runs on resize
# so coordinates stay correct after layout. Clears any previously-added
# bubbles (everything named pid_node_*).
func _populate_pid_nodes(pid: Control) -> void:
	if not is_instance_valid(pid):
		return
	# Strip stale bubbles only — keep zwanenhals/damp.
	for c in pid.get_children():
		if String(c.name).begins_with("pid_node_"):
			c.queue_free()
	var sz := pid.size
	if sz.x <= 0 or sz.y <= 0:
		return
	for node in PID_NODES:
		var px : float = float(node.x) * sz.x
		var py : float = float(node.y) * sz.y
		# Bubble background
		var bub := PanelContainer.new()
		bub.name = "pid_node_%s" % String(node.id)
		bub.add_theme_stylebox_override("panel", _sb(C_PID_NODE, 8, 4))
		bub.position = Vector2(px - 22, py - 14)
		bub.custom_minimum_size = Vector2(44, 28)
		pid.add_child(bub)
		var id_lbl := Label.new()
		id_lbl.text = String(node.id)
		id_lbl.add_theme_color_override("font_color", C_PID_BG)
		id_lbl.add_theme_font_size_override("font_size", 12)
		id_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		bub.add_child(id_lbl)
		# Optional yellow "Sorteer" tag — sits just above the bubble.
		var tag : String = String(node.tag)
		if tag != "":
			var tag_lbl := Label.new()
			tag_lbl.name = "pid_node_%s_tag" % String(node.id)
			tag_lbl.text = tag
			tag_lbl.add_theme_color_override("font_color", C_PID_TAG)
			tag_lbl.add_theme_font_size_override("font_size", 11)
			tag_lbl.position = Vector2(px - 26, py - 32)
			pid.add_child(tag_lbl)

func _on_herstart_pressed() -> void:
	# Popup with current job info (per spec).
	var dlg := AcceptDialog.new()
	dlg.title = "Herstart — programma actief"
	dlg.dialog_text = "Programma: 1\nProduct type: Standard\nBestemming: Lane 4\nAantal: 100"
	add_child(dlg)
	dlg.popup_centered()
	dlg.confirmed.connect(func(): dlg.queue_free())
	dlg.canceled.connect(func(): dlg.queue_free())

# =============================================================================
# TAB 2 — BUNKER SETPOINTS
# =============================================================================
func _build_bunker_tab() -> Control:
	var page := MarginContainer.new()
	page.add_theme_constant_override("margin_left", 6)
	page.add_theme_constant_override("margin_right", 6)
	page.add_theme_constant_override("margin_top", 6)
	page.add_theme_constant_override("margin_bottom", 6)

	var col := HBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	page.add_child(col)

	# Left: 10-row setpoint table
	var table_holder := PanelContainer.new()
	table_holder.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	table_holder.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_holder.add_theme_stylebox_override("panel", _sb(C_SCREEN, 6, 6))
	col.add_child(table_holder)
	var tbl_v := VBoxContainer.new()
	tbl_v.add_theme_constant_override("separation", 2)
	table_holder.add_child(tbl_v)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 6)
	tbl_v.add_child(head)
	for h in ["Naam", "Setpoint", "Limit", "Aan/Uit"]:
		var hl := Label.new()
		hl.text = h
		hl.add_theme_color_override("font_color", C_TEXT_DARK)
		hl.add_theme_font_size_override("font_size", 12)
		hl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(hl)
	tbl_v.add_child(HSeparator.new())

	for i in BUNKER_SETPOINTS.size():
		var row : Dictionary = BUNKER_SETPOINTS[i]
		var rb := HBoxContainer.new()
		rb.add_theme_constant_override("separation", 6)
		tbl_v.add_child(rb)
		var nm := Label.new()
		nm.text = String(row.name)
		nm.add_theme_color_override("font_color", C_TEXT_DARK)
		nm.add_theme_font_size_override("font_size", 12)
		nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.add_child(nm)
		var sp := SpinBox.new()
		sp.min_value = 0
		sp.max_value = 999
		sp.step = 1
		sp.value = int(row.sp)
		sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.add_child(sp)
		var lim := SpinBox.new()
		lim.min_value = 0
		lim.max_value = 999
		lim.step = 1
		lim.value = int(row.lim)
		lim.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rb.add_child(lim)
		var tog := CheckButton.new()
		tog.button_pressed = bool(row.on)
		rb.add_child(tog)

	# Right: speed/timing sub-panel + filling-setpoint readout
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(320, 0)
	right.add_theme_constant_override("separation", 8)
	col.add_child(right)

	var sp_panel := PanelContainer.new()
	sp_panel.add_theme_stylebox_override("panel", _sb(C_TILE, 8, 8))
	right.add_child(sp_panel)
	var sp_v := VBoxContainer.new()
	sp_v.add_theme_constant_override("separation", 4)
	sp_panel.add_child(sp_v)
	var hdr := Label.new()
	hdr.text = "Bunkersnelheid setpoint"
	hdr.add_theme_color_override("font_color", C_TEXT_DARK)
	hdr.add_theme_font_size_override("font_size", 13)
	sp_v.add_child(hdr)
	sp_v.add_child(HSeparator.new())
	sp_v.add_child(_kv_row("Beide", "875"))
	sp_v.add_child(_kv_row("Zonder 3A", "875"))
	sp_v.add_child(_kv_row("Zonder 3B", "875"))
	sp_v.add_child(_kv_row("Vertraging", "30 sec"))
	sp_v.add_child(HSeparator.new())
	sp_v.add_child(_kv_row("Pers alleen", "200"))
	sp_v.add_child(_kv_row("Sortir omschal", "75s / 0s"))
	sp_v.add_child(_kv_row("Vert terug", "30s / 30s"))

	var fill_panel := PanelContainer.new()
	fill_panel.add_theme_stylebox_override("panel", _sb(C_SCREEN, 8, 8))
	right.add_child(fill_panel)
	var fv := VBoxContainer.new()
	fill_panel.add_child(fv)
	var fhdr := Label.new()
	fhdr.text = "filling setpoint (actueel)"
	fhdr.add_theme_color_override("font_color", C_TEXT_DARK)
	fhdr.add_theme_font_size_override("font_size", 13)
	fhdr.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fv.add_child(fhdr)
	_bunker_fill_value = Label.new()
	_bunker_fill_value.text = "%d" % _filling_actual
	_bunker_fill_value.add_theme_color_override("font_color", C_TEXT_DARK)
	_bunker_fill_value.add_theme_font_size_override("font_size", 28)
	_bunker_fill_value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fv.add_child(_bunker_fill_value)

	return page

func _kv_row(key: String, value: String) -> Control:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var k := Label.new()
	k.text = key
	k.add_theme_color_override("font_color", C_TEXT_DARK)
	k.add_theme_font_size_override("font_size", 12)
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(k)
	var v := PanelContainer.new()
	v.add_theme_stylebox_override("panel", _sb(C_SCREEN, 4, 2))
	hb.add_child(v)
	var vl := Label.new()
	vl.text = "[ %s ]" % value
	vl.add_theme_color_override("font_color", C_TEXT_DARK)
	vl.add_theme_font_size_override("font_size", 12)
	v.add_child(vl)
	return hb

# =============================================================================
# TAB 3 — STARTUP (3-step FSM per SWI-049)
# =============================================================================
func _build_startup_tab() -> Control:
	var page := MarginContainer.new()
	page.add_theme_constant_override("margin_left", 16)
	page.add_theme_constant_override("margin_right", 16)
	page.add_theme_constant_override("margin_top", 16)
	page.add_theme_constant_override("margin_bottom", 16)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	page.add_child(v)

	_startup_fault_warn = Label.new()
	_startup_fault_warn.text = ""
	_startup_fault_warn.add_theme_color_override("font_color", LAMP_FAULT)
	_startup_fault_warn.add_theme_font_size_override("font_size", 14)
	v.add_child(_startup_fault_warn)

	_startup_label = Label.new()
	_startup_label.text = "Druk de automaatknop"
	_startup_label.add_theme_color_override("font_color", C_TEXT_DARK)
	_startup_label.add_theme_font_size_override("font_size", 18)
	_startup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_startup_label)

	_startup_progress = ProgressBar.new()
	_startup_progress.min_value = 0
	_startup_progress.max_value = PREHEAT_SECONDS
	_startup_progress.value = 0
	_startup_progress.visible = false
	_startup_progress.custom_minimum_size = Vector2(0, 18)
	v.add_child(_startup_progress)

	_startup_button = Button.new()
	_startup_button.text = "AUTOMAAT"
	_startup_button.custom_minimum_size = Vector2(0, 96)
	_startup_button.add_theme_font_size_override("font_size", 22)
	_startup_button.pressed.connect(_on_startup_button)
	v.add_child(_startup_button)

	_startup_state = StartupState.IDLE
	_apply_startup_state()
	return page

func _on_startup_button() -> void:
	# Block transitions while faults are active.
	if faults_active:
		_startup_state = StartupState.FAULT_BLOCK
		_apply_startup_state()
		return
	match _startup_state:
		StartupState.IDLE:
			_startup_state = StartupState.AUTOMAAT
		StartupState.AUTOMAAT:
			# automaatknop already lit — pressing moves to voorverwarm
			_startup_state = StartupState.VOORVERWARM
			_preheat_remaining = PREHEAT_SECONDS
		StartupState.VOORVERWARM:
			# voorverwarm button only progresses once preheat finished
			if _preheat_remaining <= 0.0:
				_startup_state = StartupState.READY
			# else: ignore — operator must wait
		StartupState.READY:
			# Final groene drukknop already pressed → emit done & stay.
			emit_signal("startup_completed")
		StartupState.FAULT_BLOCK:
			if not faults_active:
				_startup_state = StartupState.IDLE
	_apply_startup_state()

func _apply_startup_state() -> void:
	if not is_instance_valid(_startup_button):
		return
	if faults_active and _startup_state != StartupState.FAULT_BLOCK:
		_startup_state = StartupState.FAULT_BLOCK
	match _startup_state:
		StartupState.IDLE:
			_startup_label.text = "Druk de automaatknop"
			_startup_button.text = "AUTOMAAT"
			_set_btn_bg(_startup_button, C_BTN)
			_startup_progress.visible = false
			_startup_fault_warn.text = ""
		StartupState.AUTOMAAT:
			_startup_label.text = "Automaatknop staat aan. Druk de voorverwarmknop."
			_startup_button.text = "VOORVERWARMEN"
			_set_btn_bg(_startup_button, C_BTN_GREEN)
			_startup_progress.visible = false
			_startup_fault_warn.text = ""
		StartupState.VOORVERWARM:
			_startup_label.text = "Druk de voorverwarmknop. Wacht tot scherm groen wordt."
			_startup_button.text = "VOORVERWARMEN…"
			_set_btn_bg(_startup_button, C_AMBER)
			_startup_progress.visible = true
			_startup_fault_warn.text = ""
		StartupState.READY:
			_startup_label.text = "Druk de groene drukknop op het paneel."
			_startup_button.text = "START (groene drukknop)"
			_set_btn_bg(_startup_button, C_BTN_GREEN)
			_startup_progress.visible = false
			_startup_fault_warn.text = ""
		StartupState.FAULT_BLOCK:
			_startup_label.text = "Storingen aanwezig — eerst oplossen"
			_startup_button.text = "GEBLOKKEERD"
			_set_btn_bg(_startup_button, LAMP_FAULT)
			_startup_progress.visible = false
			_startup_fault_warn.text = "Storingen aanwezig — eerst oplossen"

func _process(delta: float) -> void:
	if _startup_state == StartupState.VOORVERWARM:
		_preheat_remaining = maxf(0.0, _preheat_remaining - delta)
		if is_instance_valid(_startup_progress):
			_startup_progress.value = PREHEAT_SECONDS - _preheat_remaining
		if _preheat_remaining <= 0.0:
			# Auto-advance to READY when timer expires (unless faults).
			if faults_active:
				_startup_state = StartupState.FAULT_BLOCK
			else:
				_startup_state = StartupState.READY
			_apply_startup_state()
	# Re-evaluate fault state every tick so an inbound fault flips the FSM
	# even between button presses.
	if faults_active and _startup_state != StartupState.FAULT_BLOCK:
		_apply_startup_state()

# =============================================================================
# BOTTOM BUTTON ROW — always visible across all tabs
# =============================================================================
func _build_bottom_row() -> Control:
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _sb(C_BEZEL, 6, 6))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	bar.add_child(hb)

	_auto_button = _bottom_btn("Auto")
	_auto_button.pressed.connect(func():
		_automaat_active = true
		_refresh_auto_hand()
	)
	hb.add_child(_auto_button)

	_hand_button = _bottom_btn("Hand")
	_hand_button.pressed.connect(func():
		_automaat_active = false
		_refresh_auto_hand()
	)
	hb.add_child(_hand_button)

	hb.add_child(_bottom_btn("🔊"))
	hb.add_child(_bottom_btn("I"))
	hb.add_child(_bottom_btn("0"))
	hb.add_child(_bottom_btn("Nummer richtlijnen"))
	hb.add_child(_bottom_btn("0"))
	hb.add_child(_bottom_btn("Enkeling-Stop"))
	var reset := _bottom_btn("reset")
	reset.pressed.connect(_on_reset_pressed)
	hb.add_child(reset)
	var ovz := _bottom_btn("Overzicht")
	ovz.pressed.connect(func():
		if is_instance_valid(_tabs):
			_tabs.current_tab = 0
	)
	hb.add_child(ovz)
	var ss := _bottom_btn("Start scherm")
	ss.pressed.connect(func(): emit_signal("request_close"))
	hb.add_child(ss)

	_refresh_auto_hand()
	return bar

func _bottom_btn(label: String) -> Button:
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(72, 36)
	b.add_theme_font_size_override("font_size", 12)
	return b

func _refresh_auto_hand() -> void:
	if is_instance_valid(_auto_button):
		_set_btn_bg(_auto_button, C_BTN_GREEN if _automaat_active else C_BTN)
	if is_instance_valid(_hand_button):
		_set_btn_bg(_hand_button, C_BTN if _automaat_active else C_AMBER)

func _on_reset_pressed() -> void:
	# Clear the local startup FSM. Faults remain owned by the parent.
	_startup_state = StartupState.IDLE
	_preheat_remaining = 0.0
	if is_instance_valid(_startup_progress):
		_startup_progress.value = 0
	_apply_startup_state()

# =============================================================================
# Helpers
# =============================================================================
func _sb(c: Color, radius: int = 6, pad: int = 6) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.corner_radius_top_left = radius
	sb.corner_radius_top_right = radius
	sb.corner_radius_bottom_left = radius
	sb.corner_radius_bottom_right = radius
	sb.content_margin_left = pad
	sb.content_margin_right = pad
	sb.content_margin_top = pad
	sb.content_margin_bottom = pad
	return sb

func _set_btn_bg(btn: Button, c: Color) -> void:
	var sb := _sb(c, 4, 6)
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", _sb(c.lightened(0.08), 4, 6))
	btn.add_theme_stylebox_override("pressed", _sb(c.darkened(0.10), 4, 6))
	btn.add_theme_color_override("font_color", Color(0.96, 0.97, 0.98, 1.0))
