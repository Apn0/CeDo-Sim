extends "res://src/scenes/hud/scopes/HmiScreenBase.gd"
class_name L3CUnitScreen

# NOTE ON THE `extends` ABOVE: resource path, not class_name — .godot/ is
# gitignored so the global class cache does not survive a clone, and the
# regression harness runs headless with no import pass to rebuild it.  See the
# same note in WashingScope.gd.

## WASLIJN 3C — PER-UNIT DETAIL SCREEN, one engine for all thirteen.
##
## WHAT THIS IS
## ------------
## Thirteen of the 34 exported screens are per-unit detail screens.  They share
## a layout: a left panel of equipment-module setpoints, a grid of motor cards,
## a column of safety lamps, and (on the two silo screens) a level panel.  What
## differs between them is DATA — which unit, which motors, which lamps, and the
## operator's exact Dutch wording for each.
##
## So this file is the layout engine and src/data/plant/l3c_unit_screens.gd is
## the data.  Adding a screen is adding a spec entry, not another 900-line file.
##
## THE THING THAT MUST NOT HAPPEN
## ------------------------------
## The real screens are NOT internally consistent, and that inconsistency is the
## operator's plant rather than noise to be tidied:
##
##     L3C.1   "Safety zone was"      L3C.4  "Safety zone wash"
##     L3C.1   "Safety zone voorwas"  L3C.4  "Safety zone prewash"
##     L3C.3   "Peddelwalzen"         L3C.11 "Peddelwals 1,2,3,4" + "5,6,7,8"
##     L3C.1   "Uittrekschroef midden" (lower-case m, beside two capitalised)
##
## Every label here is transcribed verbatim from the export and keyed by its own
## string.  A refactor that "normalises" these is a REGRESSION, and
## src/tests/test_l3c_unit_screens.gd fails if the divergences collapse.
##
## THE HONESTY RULE (inherited from HmiScreenBase)
## -----------------------------------------------
## Every value is BOUND through TagMap over LineFlow.get_machine_info(), or it
## renders "--" with a recorded reason.  Never a plausible number.
##
## WHAT BINDS ON A UNIT SCREEN, AND WHAT CANNOT (measured, not guessed)
## --------------------------------------------------------------------
## The export splits each unit's tags into an `em/` (equipment-module) group and
## one group per motor:
##
##     scada/3c/info/14l/em/status|hand|snelheid|starttijd|stoptijd|leegdraaitijd
##     scada/3c/info/14l/softstarterdroger1/status|stroom|handauto|start|stop
##     scada/3c/info/14l/motorreinigingsschrapper/...
##     scada/3c/info/14l/motorroterendeklep/...
##
##  * BINDS — the left panel's Status and Hand/Auto (em/status -> `powered`,
##    em/hand -> `hand_mode`), and the Stroom of the ONE motor card that carries
##    the machine's current.
##
##  * DOES NOT BIND — the five timer rows (StartTijd, StopTijd, LeegdraaiTijd,
##    Bewaking StartTijd, Bewaking StopTijd) and every motor card's Loopbewaking.
##    These are PLC setpoints.  LineFlow.get_machine_info() (LineFlow.gd:1682)
##    returns no start/stop/run-out timing of any kind — the sim starts and stops
##    machines instantly.  There is nothing to read, so they render "--".
##
##  * DOES NOT BIND — the secondary motor cards.  The sim's `components`
##    (LineFlow.gd:1486) are RPM-FRACTION throttles, not motors: they carry no
##    current and no run state, and `mech_dryer` matches no branch there at all,
##    so L3C.14 has no components whatsoever.  TagMap already recorded this at
##    TagMap.gd:722 — "the rotary-valve + cleaning-scraper motors on this SCADA
##    unit are absent (no sim component)".
##
## WHICH CARD GETS THE CURRENT — NOT A FRESH GUESS
## ------------------------------------------------
## A three-card screen has one machine-level `amps` between three cards, so
## something has to decide which card shows it.  That decision was already made
## and cited in TagMap (TagMap.gd:723): `softstarterdroger1/stroom` resolves to
## MACHINE_FIELD `amps`.  A soft starter sits on the main drum drive, not on a
## scraper.  This screen READS that mapping rather than re-deciding it, so the
## unit screen and the Overzicht can never disagree about the same number.
## Spec entries name the carrying motor explicitly (`stroom_from_machine`), and
## the test asserts exactly one card per screen claims it.

const TagMapScript = preload("res://src/sim/TagMap.gd")
const SpecScript = preload("res://src/data/plant/l3c_unit_screens.gd")

# ---------------------------------------------------------------------------
# Reasons.  Each is stated once and attached to every field it explains, so the
# audit cannot drift from the header above.
# ---------------------------------------------------------------------------

const R_NO_TIMERS : String = "the sim has no start/stop/run-out timing: LineFlow.get_machine_info() (LineFlow.gd:1682) returns no timer field of any kind and machines start and stop instantly. This is a PLC setpoint with no sim counterpart, not an addressing failure"

const R_NO_PER_MOTOR : String = "the sim does not model this motor. LineFlow's `components` (LineFlow.gd:1486) are RPM-FRACTION throttles carrying neither current nor run state, and the unit's machine class matches no component branch there at all. Recorded independently at TagMap.gd:722"

const R_NO_SAFETY : String = "the sim has no safety-circuit model: no work switch, no light-curtain zone, no door interlock. LineFlow exposes is_estopped as a LINE-wide flag only, which is not this lamp"

const R_NO_LINE_MODE : String = "the sim has no line-level Auto/Hand annunciator, no wash-section state and no silo-section state. Aggregating per-machine hand_mode into a line mode would be an invented rule"

const R_NO_ALARM_SRC : String = "no wash-line fault registry exists; src/sim/EremaFaultRegistry.gd carries the EREMA extruder codes only, no L3C entry"

## Operator-facing text for the amber strip — the counterpart of R_NO_ALARM_SRC.
const ALARM_UNAVAIL_REASON : String = "geen storingsbron gekoppeld — EremaFaultRegistry dekt alleen de extruder, er is geen waslijn-storingsregister"

# ---------------------------------------------------------------------------
# State
# ---------------------------------------------------------------------------

var _spec      : Dictionary = {}
var _scope     : Dictionary = {}
var _line_flow : Node       = null
var _tagmap    : TagMap     = null

var _screen_id  : String = ""
var _status_pill : Label   = null
var _mode_hand   : Label   = null
var _mode_auto   : Label   = null
var _card_dots   : Dictionary = {}     # verbatim card title -> ColorRect
## What the Hand/Auto pair currently renders — the readable form of the mode
## field, so rendered_text() can report the pixels rather than the intent.
var _mode_render : String = UNAVAIL

var _bound_expected   : int = 0
var _unavail_expected : int = 0

# ---------------------------------------------------------------------------
# Lifecycle
# ---------------------------------------------------------------------------

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	custom_minimum_size = Vector2(960, 560)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if _screen_id != "":
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

## Choose WHICH unit screen this is.  Must be called before the node enters the
## tree, or it rebuilds in place.  `id` is a key of SpecScript.SCREENS.
func set_screen(id: String) -> void:
	if not SpecScript.SCREENS.has(id):
		push_warning("[L3CUnitScreen] unknown screen id: %s" % id)
		return
	_screen_id = id
	_spec = (SpecScript.SCREENS[id] as Dictionary)
	if is_inside_tree():
		for c in get_children():
			c.queue_free()
		_status_dots.clear()
		_status_texts.clear()
		_amp_labels.clear()
		_chip_labels.clear()
		_value_boxes.clear()
		_lamps.clear()
		_card_dots.clear()
		_build_ui()
		refresh()

## Wire the scope dict + the live LineFlow.  `line_flow` is duck-typed so a
## headless test can pass a stub that answers get_machine_info() — which is how
## the mutation half of the test proves this screen is not faking.
func bind(scope: Dictionary = {}, line_flow: Node = null) -> void:
	_scope = scope.duplicate(true) if not scope.is_empty() else {}
	_line_flow = line_flow
	if _tagmap == null:
		_tagmap = TagMapScript.new()
	refresh()

func screen_id() -> String:
	return _screen_id

## Two widget kinds exist only on the unit screens, so they are read here rather
## than in the base.  Both were found by the test: they were reported BOUND while
## rendered_text() answered "" for them, which makes a bound field unverifiable.
##   "mode:<code>"  -> the Hand/Auto pair; answers whichever key is lit.
##   "card:<title>" -> a motor card's status band.
func rendered_text(field_key: String) -> String:
	var parts := field_key.split(":", true, 1)
	var kind := String(parts[0])
	var arg := String(parts[1]) if parts.size() > 1 else ""
	match kind:
		"mode":
			if arg != String(_spec.get("code", "")):
				return ""
			return _mode_render
		"card":
			var dot : ColorRect = _status_dots.get("card:%s" % arg, null)
			if dot == null:
				return ""
			return String(dot.get_meta("render_text", ""))
	return super(field_key)

## The verbatim Dutch strings this screen renders, in render order.  The
## anti-normalisation test compares these ACROSS screens.
func verbatim_labels() -> Array:
	var out : Array = []
	out.append(String(_spec.get("title", "")))
	for row in (_spec.get("timers", []) as Array):
		out.append(String(row))
	for card in (_spec.get("cards", []) as Array):
		out.append(String((card as Dictionary).get("title", "")))
	for lamp in (_spec.get("lamps", []) as Array):
		out.append(String(lamp))
	return out

func _expected_bound() -> int:
	return _bound_expected

func _expected_unavail() -> int:
	return _unavail_expected

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

func _build_ui() -> void:
	var bg := ColorRect.new()
	bg.color = C_SCREEN_BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_theme_constant_override("separation", 0)
	add_child(root)

	# The "SIEMENS / SIMATIC HMI" strip at the top of every mockup is the
	# physical panel bezel silkscreen, not part of the WinCC page — deliberately
	# not drawn, same ruling as WashingScope.
	root.add_child(_build_header_bar(SpecScript.HEADER_CHIPS))
	root.add_child(_build_alarm_strip(ALARM_UNAVAIL_REASON))

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 16)
	root.add_child(body)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 14)
	pad.add_theme_constant_override("margin_top", 10)
	pad.add_child(_build_left_panel())
	body.add_child(pad)

	body.add_child(_build_cards_column())
	body.add_child(_build_lamp_column())

	root.add_child(_build_audit_strip())
	root.add_child(_build_nav_bar())

## Left panel — the equipment-module group: title, Status, Hand/Auto, timers.
## The panel face colour for THIS screen.  Not a constant: L3C.14 Rechts uses a
## dark slate #5a6070 where its Links sibling uses the light grey #c8cdd6, and it
## is a 1024x768 canvas rather than 1280x800 (hmi_screen_inventory_2026-07-28.md:
## "THIS FILE IS STRUCTURALLY DIFFERENT FROM ITS FIVE SIBLINGS and a porter must
## not assume one template").  Rendering both in one grey would have been a quiet
## infidelity that no test looks for, so the spec carries it.
func _panel_bg() -> Color:
	var hex := String(_spec.get("panel_bg", ""))
	return Color(hex) if hex != "" else C_PANEL_BG

## Text colour that stays legible on whichever panel face this screen uses.
func _panel_fg() -> Color:
	return C_TEXT if _panel_bg().get_luminance() < 0.5 else C_BOX_FG

func _build_left_panel() -> Control:
	var pc := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = _panel_bg()
	sb.border_color = C_PANEL_EDGE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 12
	sb.content_margin_bottom = 12
	pc.add_theme_stylebox_override("panel", sb)
	pc.size_flags_vertical = Control.SIZE_SHRINK_BEGIN

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pc.add_child(v)

	var title := _mklabel(String(_spec.get("title", "")), 16, _panel_fg())
	v.add_child(title)

	# Status row.
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	srow.add_child(_mklabel("Status", 13, _panel_fg()))
	_status_pill = _mklabel(UNAVAIL, 13, C_BOX_FG)
	_status_pill.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_pill.custom_minimum_size = Vector2(72, 20)
	var pill := PanelContainer.new()
	var psb := StyleBoxFlat.new()
	psb.bg_color = C_UNAVAIL
	psb.content_margin_left = 8
	psb.content_margin_right = 8
	pill.add_theme_stylebox_override("panel", psb)
	pill.add_child(_status_pill)
	srow.add_child(pill)
	v.add_child(srow)
	# Register it so rendered_text("status:<code>") can read the pixels. Without
	# this the field reports as BOUND while nothing can read what it renders.
	_status_texts[String(_spec.get("code", ""))] = _status_pill

	# Hand / Auto pair.
	var mrow := HBoxContainer.new()
	mrow.add_theme_constant_override("separation", 6)
	var hand_key := _mkmode_key("Hand")
	var auto_key := _mkmode_key("Auto")
	_mode_hand = hand_key.get_child(0) as Label
	_mode_auto = auto_key.get_child(0) as Label
	mrow.add_child(hand_key)
	mrow.add_child(auto_key)
	v.add_child(mrow)

	# Column headings — verbatim, including the e-diaeresis in "Reëel".
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 6)
	var spacer := _mklabel("", 12, _panel_fg())
	spacer.custom_minimum_size = Vector2(140, 0)
	hrow.add_child(spacer)
	hrow.add_child(_mkcol_head("Gewenst"))
	hrow.add_child(_mkcol_head("Reëel"))
	v.add_child(hrow)

	for row_name in (_spec.get("timers", []) as Array):
		v.add_child(_build_timer_row(String(row_name)))
	return pc

## One timer row: verbatim label, Gewenst box, Reëel box, and (on the rows that
## have one) the OFF checkbox.  Both boxes are UNAVAIL — see R_NO_TIMERS.
func _build_timer_row(row_name: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var lbl := _mklabel(row_name, 12, _panel_fg())
	lbl.custom_minimum_size = Vector2(140, 0)
	h.add_child(lbl)
	h.add_child(_mkvalue_box("%s.gewenst" % row_name, 60))
	# "Bewaking *" rows have a Gewenst box only; the export leaves the Reëel
	# column empty on them rather than showing a blank box.
	if not row_name.begins_with("Bewaking"):
		h.add_child(_mkvalue_box("%s.reeel" % row_name, 60))
	else:
		var gap := Control.new()
		gap.custom_minimum_size = Vector2(60, 0)
		h.add_child(gap)
	# The OFF checkbox is absent on LeegdraaiTijd in every screen checked.
	if row_name != "LeegdraaiTijd":
		var cb := ColorRect.new()
		cb.custom_minimum_size = Vector2(10, 10)
		cb.color = _panel_bg()
		h.add_child(cb)
		h.add_child(_mklabel("OFF", 11, _panel_fg()))
	return h

func _mkcol_head(txt: String) -> Label:
	var l := _mklabel(txt, 12, _panel_fg())
	l.custom_minimum_size = Vector2(60, 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

## A Hand or Auto key: a coloured PanelContainer wrapping its label.  refresh()
## recolours the panel from hand_mode; the caller keeps the child Label.
func _mkmode_key(txt: String) -> PanelContainer:
	var box := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = C_UNAVAIL
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 4
	sb.content_margin_bottom = 4
	box.add_theme_stylebox_override("panel", sb)
	box.add_child(_mklabel(txt, 12, C_BOX_FG))
	return box

## Motor cards, laid out as the export does: a top row, then a second row on the
## screens that have one.
func _build_cards_column() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var top := HFlowContainer.new()
	top.add_theme_constant_override("h_separation", 8)
	top.add_theme_constant_override("v_separation", 8)
	v.add_child(top)
	for card in (_spec.get("cards", []) as Array):
		top.add_child(_build_motor_card(card as Dictionary))

	if not (_spec.get("cards_bottom", []) as Array).is_empty():
		var pad := Control.new()
		pad.custom_minimum_size = Vector2(0, 24)
		v.add_child(pad)
		var bot := HFlowContainer.new()
		bot.add_theme_constant_override("h_separation", 8)
		bot.add_theme_constant_override("v_separation", 8)
		v.add_child(bot)
		for card in (_spec.get("cards_bottom", []) as Array):
			bot.add_child(_build_motor_card(card as Dictionary))
	return v

func _build_motor_card(card: Dictionary) -> Control:
	var title := String(card.get("title", ""))
	var pc := PanelContainer.new()
	pc.custom_minimum_size = Vector2(220, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = _panel_bg()
	sb.border_color = C_PANEL_EDGE
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	pc.add_theme_stylebox_override("panel", sb)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	pc.add_child(v)

	# Header band — verbatim motor name, green when that drive runs.
	var head := PanelContainer.new()
	var hsb := StyleBoxFlat.new()
	hsb.bg_color = C_UNAVAIL
	hsb.content_margin_left = 10
	hsb.content_margin_right = 10
	hsb.content_margin_top = 4
	hsb.content_margin_bottom = 4
	head.add_theme_stylebox_override("panel", hsb)
	var hl := _mklabel(title, 13, C_BOX_FG)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_child(hl)
	v.add_child(head)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(0, 3)
	dot.color = C_UNAVAIL
	dot.set_meta("render_text", UNAVAIL)
	v.add_child(dot)
	_card_dots[title] = dot
	_status_dots["card:%s" % title] = dot

	# Start / Stop keys.  Both DISABLED: writing a start command into the sim
	# from this screen is not wired, and a key that looks live but does nothing
	# is worse than one that looks dead.
	var keys := HBoxContainer.new()
	keys.add_theme_constant_override("separation", 4)
	for t in ["Start", "Stop"]:
		var b := Button.new()
		b.text = String(t)
		b.disabled = true
		b.tooltip_text = "niet gekoppeld"
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 12)
		keys.add_child(b)
	v.add_child(keys)

	# Card rows come from the SPEC, because the export's cards are not uniform:
	# on L3C.14 the Mechanische Droger card has Loopbewaking + Stroom, the
	# Reinigingsschraper has Aanlooptijd + Uitlooptijd in BOTH columns, and the
	# Doseersluis has Aanlooptijd + Uitlooptijd + Loopbewaking under Gewenst.
	# Hard-coding one row set would have silently rewritten two cards in three.
	# The same row name occurs in both columns, so keys carry the column.
	v.add_child(_mkright("Gewenst"))
	for r in (card.get("gewenst", []) as Array):
		v.add_child(_mkcard_row(title, String(r), "%s.gewenst.%s" % [title, String(r)]))
	v.add_child(_mkright("Reëel"))
	for r in (card.get("reeel", []) as Array):
		v.add_child(_mkcard_row(title, String(r), "%s.reeel.%s" % [title, String(r)]))
	return pc

func _mkright(txt: String) -> Control:
	var l := _mklabel(txt, 12, _panel_fg())
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l

func _mkcard_row(card_title: String, label: String, key: String) -> Control:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	var l := _mklabel(label, 12, _panel_fg())
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	var box := _mkvalue_box(key, 70)
	h.add_child(box)
	if label == "Stroom":
		# Register under the card title so refresh() and rendered_text() can find
		# it without re-deriving the key.
		_amp_labels[card_title] = _value_boxes[key]
	return h

func _build_lamp_column() -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	v.alignment = BoxContainer.ALIGNMENT_BEGIN
	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_top", 100)
	pad.add_theme_constant_override("margin_right", 20)
	pad.add_child(v)
	for lamp in (_spec.get("lamps", []) as Array):
		v.add_child(_mklamp(String(lamp)))
	return pad

# ---------------------------------------------------------------------------
# Refresh
# ---------------------------------------------------------------------------

func refresh() -> void:
	_bound.clear()
	_unavail.clear()
	if _spec.is_empty():
		return

	var code := String(_spec.get("code", ""))
	var info : Dictionary = {}
	if _line_flow != null and _line_flow.has_method("get_machine_info"):
		info = _line_flow.call("get_machine_info", code) as Dictionary

	_refresh_header_chips()
	_refresh_status_and_mode(code, info)
	_refresh_timers()
	_refresh_cards(code, info)
	_refresh_lamps()
	_recount()
	_refresh_audit()

func _refresh_header_chips() -> void:
	for chip in SpecScript.HEADER_CHIPS:
		var label := String((chip as Dictionary)["label"])
		_mark_unavail("chip:%s" % label, "", String((chip as Dictionary).get("cite", "")),
			R_NO_LINE_MODE)
	_mark_unavail("alarm", "", String(_spec.get("cite_alarm", "")), R_NO_ALARM_SRC)

func _refresh_status_and_mode(code: String, info: Dictionary) -> void:
	var cite := String(_spec.get("cite_status", ""))
	if info.is_empty():
		_paint_pill(_status_pill, UNAVAIL, C_UNAVAIL)
		_paint_mode(false, true)
		_mark_unavail("status:%s" % code, code, cite, _no_machine_reason(code))
		_mark_unavail("mode:%s" % code, code, cite, _no_machine_reason(code))
		return
	var powered := bool(info.get("powered", false))
	_paint_pill(_status_pill, "Aan" if powered else "Uit", C_GREEN if powered else C_UNAVAIL)
	_bound.append({
		"field": "status:%s" % code, "code": code, "cite": cite,
		"tag": "scada/3c/info/%s/em/status" % String(_spec.get("tag_unit", "")),
		"source_field": "powered", "rendered": _status_pill.text,
	})
	var hand := bool(info.get("hand_mode", false))
	_paint_mode(hand, false)
	_bound.append({
		"field": "mode:%s" % code, "code": code, "cite": cite,
		"tag": "scada/3c/info/%s/em/hand" % String(_spec.get("tag_unit", "")),
		"source_field": "hand_mode", "rendered": "Hand" if hand else "Auto",
	})

## Every timer box, both columns, on every screen: structurally unavailable.
func _refresh_timers() -> void:
	var cite := String(_spec.get("cite_timers", ""))
	for row_name in (_spec.get("timers", []) as Array):
		var rn := String(row_name)
		_paint_box("%s.gewenst" % rn, UNAVAIL)
		_mark_unavail("box:%s.gewenst" % rn, "", cite, R_NO_TIMERS)
		if not rn.begins_with("Bewaking"):
			_paint_box("%s.reeel" % rn, UNAVAIL)
			_mark_unavail("box:%s.reeel" % rn, "", cite, R_NO_TIMERS)

func _refresh_cards(code: String, info: Dictionary) -> void:
	var cite := String(_spec.get("cite_cards", ""))
	var carrier := String(_spec.get("stroom_from_machine", ""))
	var all_cards : Array = []
	all_cards.append_array(_spec.get("cards", []) as Array)
	all_cards.append_array(_spec.get("cards_bottom", []) as Array)

	for c in all_cards:
		var card := c as Dictionary
		var title := String(card.get("title", ""))
		var dot : ColorRect = _card_dots.get(title, null)

		# A card may name its OWN machine code. Two shapes exist in the export and
		# conflating them would be wrong in both directions:
		#
		#   ONE MACHINE, MANY MOTORS — L3C.3 Bezinkafscheider's six cards
		#     (Intrekwals, Peddelwalzen, Afvoerwals, Uittrekschroef L/R,
		#     Afvoerschraper) are six drives of a single unit. The sim has one
		#     `amps` between them and no per-motor state, so at most one card can
		#     carry it.
		#
		#   MANY MACHINES, ONE SCREEN — L3C.4 Frictiescheider's two cards are
		#     L3C.4L and L3C.4R, genuinely separate machines with separate
		#     calibrated nominals. Each binds its OWN node, and treating them as
		#     one unit's motors would resurrect the shared-id defect on a screen.
		var card_code := String(card.get("code", ""))
		var card_info : Dictionary = info
		if card_code != "" and card_code != code:
			card_info = {}
			if _line_flow != null and _line_flow.has_method("get_machine_info"):
				card_info = _line_flow.call("get_machine_info", card_code) as Dictionary

		# Every card row EXCEPT Stroom is a PLC timing setpoint with no sim
		# counterpart — Loopbewaking, Aanlooptijd, Uitlooptijd alike.
		for col in ["gewenst", "reeel"]:
			for r in (card.get(col, []) as Array):
				var rn := String(r)
				if rn == "Stroom":
					continue
				var key := "%s.%s.%s" % [title, col, rn]
				_paint_box(key, UNAVAIL)
				_mark_unavail("box:%s" % key, code, cite, R_NO_TIMERS)

		var stroom_key := "%s.reeel.Stroom" % title
		# A card binds when EITHER it is the screen-level carrier named by
		# stroom_from_machine, OR it names its own machine code.
		var is_carrier : bool = (title == carrier) or (card_code != "")
		var eff_code : String = card_code if card_code != "" else code
		var eff_unit : String = String(card.get("tag_unit", _spec.get("tag_unit", "")))
		var eff_motor : String = String(card.get("tag_motor",
			_spec.get("stroom_tag_motor", "")))
		# A card with no Stroom row cannot show a current whatever the tags say.
		if not (card.get("reeel", []) as Array).has("Stroom"):
			is_carrier = false
		if not is_carrier:
			_paint_dot(dot, false, true)
			_paint_box(stroom_key, UNAVAIL)
			_mark_unavail("card:%s" % title, code, cite, R_NO_PER_MOTOR)
			if (card.get("reeel", []) as Array).has("Stroom"):
				_mark_unavail("stroom:%s" % title, code, cite, R_NO_PER_MOTOR)
			continue

		if card_info.is_empty():
			_paint_dot(dot, false, true)
			_paint_box(stroom_key, UNAVAIL)
			_mark_unavail("card:%s" % title, eff_code, cite, _no_machine_reason(eff_code))
			_mark_unavail("stroom:%s" % title, eff_code, cite, _no_machine_reason(eff_code))
			continue

		var powered := bool(card_info.get("powered", false))
		_paint_dot(dot, powered, false)
		var amps := float(card_info.get("amps", 0.0))
		var txt := _fmt_amps(amps, String(_spec.get("amps_fmt", "int")))
		_paint_box(stroom_key, txt)
		_bound.append({
			"field": "card:%s" % title, "code": eff_code, "cite": cite,
			"tag": "scada/3c/info/%s/%s/status" % [eff_unit, eff_motor],
			"source_field": "powered", "rendered": String(dot.get_meta("render_text", "")),
		})
		_bound.append({
			"field": "stroom:%s" % title, "code": eff_code, "cite": cite,
			"tag": "scada/3c/info/%s/%s/stroom" % [eff_unit, eff_motor],
			"source_field": "amps", "rendered": txt,
		})

func _refresh_lamps() -> void:
	var cite := String(_spec.get("cite_lamps", ""))
	for lamp in (_spec.get("lamps", []) as Array):
		var name_v := String(lamp)
		_paint_dot(_lamps.get(name_v, null), false, true)
		_mark_unavail("lamp:%s" % name_v, "", cite, R_NO_SAFETY)

## Why a unit did not resolve.  Distinguishes "wrong world" from "broken
## addressing", because those need opposite fixes and look identical on screen.
func _no_machine_reason(code: String) -> String:
	return ("no machine answers to %s. This screen addresses units by their own "
		+ "plant code, so it binds only in a world where the `line_3c` macro has "
		+ "been placed; in a 3A/3B-only world nothing carries an L3C code. "
		+ "Falling back to the placeable id would first-match a LINE 3A machine "
		+ "and render its numbers under a 3C caption") % code

func _recount() -> void:
	_bound_expected = _bound.size()
	_unavail_expected = _unavail.size()

func _refresh_audit() -> void:
	if _audit_lbl == null or not is_instance_valid(_audit_lbl):
		return
	_audit_lbl.text = "%s — %d gebonden / %d niet beschikbaar" % [
		_screen_id, _bound.size(), _unavail.size()]

# ---------------------------------------------------------------------------
# Painting
# ---------------------------------------------------------------------------

func _paint_pill(lbl: Label, txt: String, col: Color) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	lbl.text = txt
	var box := lbl.get_parent() as PanelContainer
	if box == null:
		return
	var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb != null:
		sb.bg_color = col

func _paint_mode(hand: bool, unavailable: bool) -> void:
	_paint_mode_key(_mode_hand, hand, unavailable)
	_paint_mode_key(_mode_auto, not hand, unavailable)
	_mode_render = UNAVAIL if unavailable else ("Hand" if hand else "Auto")

func _paint_mode_key(lbl: Label, active: bool, unavailable: bool) -> void:
	if lbl == null or not is_instance_valid(lbl):
		return
	var box := lbl.get_parent() as PanelContainer
	if box == null:
		return
	var sb := box.get_theme_stylebox("panel") as StyleBoxFlat
	if sb == null:
		return
	if unavailable:
		sb.bg_color = C_UNAVAIL
		return
	sb.bg_color = C_GREEN if active else C_BTN_GREY
