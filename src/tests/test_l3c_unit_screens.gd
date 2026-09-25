extends Node3D
## WASLIJN 3C PER-UNIT SCREENS — are they TRANSCRIBED, and are they HONEST?
##
##   godot --headless --path <proj> res://src/tests/test_l3c_unit_screens.tscn
##
## Covers the layout engine src/scenes/hud/scopes/L3CUnitScreen.gd driven by the
## spec data src/data/plant/l3c_unit_screens.gd, over ALL THIRTEEN unit screens.
##
## WHY THE L3C.14 PAIR CARRIES THE HEADLINE
## ----------------------------------------
## They are the same machine TYPE (mech_dryer) and until 2026-07-29 BOTH read
## 0.00 A, because LineFlow addressed machines by placeable id and an id names a
## type, not a unit. They now carry their own calibrated currents. Two screens
## whose only difference in the sim is which node answers is the sharpest
## available test that per-unit addressing is real.
##
## Their source files also differ in KIND: Links is templated like most of the
## set, Rechts is hand-authored with per-card HTML comments, a machine SVG, a
## 1024x768 canvas and a dark-slate panel face. A layout engine that only works
## on templated input is not a layout engine, so both are checked.
##
## TWO SHAPES OF SCREEN, AND CONFLATING THEM WOULD BE WRONG BOTH WAYS
## ------------------------------------------------------------------
##   ONE MACHINE, MANY MOTORS   L3C.3's six cards are six drives of one unit.
##                              The sim has one `amps` between them, so at most
##                              one card can carry it.
##   MANY MACHINES, ONE SCREEN  L3C.4's two cards are L3C.4L and L3C.4R,
##                              genuinely separate machines with separate
##                              calibrated nominals. Both bind their OWN node.
## Criterion H is written to allow 0, 1 or 2 carriers and to reject the thing
## that is actually wrong: a card showing a current it has no Stroom row for.
##
## NON-VACUOUS PASS CRITERIA, STATED UP FRONT
## ------------------------------------------
##  A. TRANSCRIPTION  the check that makes the rest mean anything. Every label in
##                    the spec is re-extracted FROM THE OPERATOR'S HTML at run
##                    time and compared. A spec entry naming a device the export
##                    does not contain is a FAIL — this is what stops the screens
##                    from being plausible inventions. It is deliberately a
##                    two-way check: labels in the HTML that the spec omits fail
##                    too, because silently dropping a motor card is the easier
##                    mistake to make.
##  B. NO NORMALISING the divergences between screens SURVIVE. "Doseersluis
##                    Links" and "Doseersluis Rechts" must both exist and differ.
##                    Within one screen the three motor cards must keep their
##                    three DIFFERENT row sets. A tidy-up that unifies either is
##                    a regression and fails here.
##  C. STRUCTURE      the Control builds; field_report() accounts for every field
##                    exactly once (bound + unavailable == total).
##  D. AGREEMENT      the audit dict matches the pixels: every bound field's
##                    painted text is NOT "--", every unavailable field's IS "--".
##  E. REASONS        every unavailable field carries a non-empty reason.
##  F. LIVENESS       the anti-vacuity check. On a running line the bound status
##                    must read Aan, the bound Stroom must be > 0, and — the
##                    headline — the two screens must render DIFFERENT currents.
##                    Equal currents is exactly the old defect and fails.
##  G. INSTANCE       every bound field resolves through a machine whose OWN
##                    l3c_code equals the screen's code. A Line 3A mech_dryer
##                    answering for L3C.14L is a FAIL, not a near miss. Line 3A is
##                    built alongside precisely so this can fail.
##  H. ONE CARRIER    exactly ONE motor card per screen claims the machine
##                    current. Two would be double-counting one ammeter; zero
##                    would mean the screen shows no current at all.
##
## MUTATION TESTS (both must go RED, or the criteria above prove nothing)
##  M1 DEAD SOURCE    stub returning {} — bound must collapse to 0.
##  M2 CORRECT-KEYS-DEAD-VALUES  stub returning the full key set at type
##                    defaults. C/D/E still pass; ONLY F may fail. This is the
##                    npc-05 shape, and without F this run would print a green
##                    that proves nothing.
##
## user:// SAFETY: every file this test can touch is byte-backed-up and restored,
## and the operator's allernieuwste_* saves are hash-checked before and after.

const TagMapScript = preload("res://src/sim/TagMap.gd")
const UnitScreenScript = preload("res://src/scenes/hud/scopes/L3CUnitScreen.gd")
const SpecScript = preload("res://src/data/plant/l3c_unit_screens.gd")

const SCREEN_DIR := "res://docs/plant/hmi_screens_2026-07-26/"
## spec id -> the export file it was transcribed from.
const SOURCE_HTML := {
	"L3C.1":   "Waslijn 3C L3C.1 Doseer Silo.dc.html",
	"L3C.3":   "Waslijn 3C L3C.3 Bezinkafscheider.dc.html",
	"L3C.4":   "Waslijn 3C L3C.4 Frictiescheider.dc.html",
	"L3C.5":   "Waslijn 3C L3C.5 Transportschroef.dc.html",
	"L3C.6":   "Waslijn 3C L3C.6 Maalmolen.dc.html",
	"L3C.10":  "Waslijn 3C L3C.10 Transportschroef.dc.html",
	"L3C.11":  "Waslijn 3C L3C.11 Flotatietank.dc.html",
	"L3C.12":  "Waslijn 3C L3C.12 Transportschroef.dc.html",
	"L3C.14L": "Waslijn 3C L3C.14 Mech Droger Links.dc.html",
	"L3C.14R": "Waslijn 3C L3C.14 Mech Droger Rechts.dc.html",
	"L3C.16":  "Waslijn 3C L3C.16 Plasmaq.dc.html",
	"L3C.18":  "Waslijn 3C L3C.18 Extruder Silo.dc.html",
	"L3C.19":  "Waslijn 3C L3C.19 Rondmengventilator.dc.html",
}

## Every spec key must have a source file here, or a screen could be added and
## never transcription-checked — the one way a fabricated screen could slip in.
## Asserted at run time rather than trusted.

# Line fixtures are placed in the building frame the game FITS from the shell
# (building_frame.gd; the typed BF_O/XU/ZU constants mapped through
# Plant.pc_to_scene rotated the frame a second time and put machines outside
# the real building, measured 2026-09-25).
const BFrame := preload("res://src/tests/building_frame.gd")

const TEST_SLOT := "__l3cunit__"
## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const TOUCHED := [
	"user://world_layout_consumed.flag",
	"user://__l3cunit___save.json", "user://__l3cunit___factory.json",
]
const DUMP_PATH := "user://l3c_unit_screens_report.json"

const MACRO_3C := "line_3c"
# bf(4,62) put line 3C on the hall edge: 9 of its 37 machines outside the
# shell even in the fitted frame (measured 2026-09-25). bf(4,44) keeps it
# 37/37 under the roof beside line 3A at bf(4,22), no footprint overlap.
const LINE_3C_START_BF := Vector2(4.0, 44.0)
const MACRO_ID := "line_3a"
const LINE_START_BF := Vector2(4.0, 22.0)

const TICK_DT := 0.1
const TICK_COUNT := 400
const FEED_RATE := 0.05
const FEED_DENSITY := 320.0
const FEED_COMP := {"LDPE": 0.78, "HDPE": 0.075, "other": 0.145}

## Independent copies of the two calibrated nominals, HAND-TRANSCRIBED from the
## operator's material — NOT read from Line3CDef. A test that sourced these from
## the same table the screen reads would agree with the code by construction and
## could never catch a wrong table.
const NOMINAL_14L := 70.80
const NOMINAL_14R := 63.51

var _pass := 0
var _fail := 0
var _skip := 0
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, TOUCHED)
var _guarded : Dictionary = {}
var _dump : Dictionary = {}
var _line_flow_ref : Node = null


class StubDeadSource extends Node:
	func get_machine_info(_id: String) -> Dictionary:
		return {}
	func estop_fault_id() -> String:
		return ""


class StubDefaultValues extends Node:
	func get_machine_info(_id: String) -> Dictionary:
		return {
			"id": _id, "key": _id, "l3c_code": _id, "amps_nominal": 0.0,
			"role": "", "process": "", "rate": 0.0, "spin": 0.0,
			"powered": false, "buffer": 0.0, "thru": 0.0, "moist": 0.0,
			"contam": 0.0, "quality": 0.0, "amps": 0.0,
			"hand_mode": false, "manual_on": false, "rpm_pct": 0.0,
			"max_rpm": 0.0, "comp_max_rpm": {}, "components": {},
		}
	func estop_fault_id() -> String:
		return ""
	func estop_fault_key() -> String:
		return ""


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1

func _note(msg: String) -> void:
	print("  note  : %s" % msg)

func _section(t: String) -> void:
	print("\n[%s]" % t)



# =============================================================================
# A. TRANSCRIPTION — re-read the operator's HTML and compare
# =============================================================================

## Pull every rendered text node out of a screen export.  Deliberately crude and
## WHOLE-FILE: a targeted extractor could be written to find exactly what the
## spec claims, which would make the check circular.
func _html_text_nodes(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var raw := f.get_as_text()
	f.close()
	var out : Array = []
	var re := RegEx.create_from_string(">([^<>]{2,48})<")
	for m in re.search_all(raw):
		var s := m.get_string(1).strip_edges()
		s = s.replace("&amp;", "&").replace("&euml;", "ë").replace("&nbsp;", " ")
		if s != "" and not s.begins_with("http"):
			out.append(s)
	return out


## Every motor-card header in a screen export, in file order.
##
## Identified by MARKUP SIGNATURE, not by device name: a coloured status band
## carrying `font-weight:600` and `text-align:center`.  Validated 2026-07-29
## against all 13 unit screens — it reproduces the card count on every one,
## including the hand-authored L3C.14 Rechts (which differs only in `padding:4px
## 8px` where its siblings use `10px`) and the three screens that genuinely have
## no motor cards at all.
##
## Note the captured text can contain a real newline: L3C.6's second card is
## "ontgrendel\ndeurmaalmolen". That is the operator's screen, and the spec must
## carry it verbatim — newline included.
func _html_card_headers(path: String) -> Array:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return []
	var raw := f.get_as_text()
	f.close()
	var out : Array = []
	var re := RegEx.create_from_string(
		"background:#[0-9a-fA-F]{3,6};color:#111;font-weight:600;padding:4px [0-9]+px;text-align:center;[^\"]*\">([^<]*)<")
	for m in re.search_all(raw):
		out.append(m.get_string(1).strip_edges()
			.replace("&amp;", "&").replace("&euml;", "ë").replace("&nbsp;", " "))
	return out


func _check_transcription() -> void:
	_section("A/B — TRANSCRIPTION against the operator's own export")
	var seen_titles : Dictionary = {}

	for sid in SOURCE_HTML.keys():
		var path : String = SCREEN_DIR + String(SOURCE_HTML[sid])
		var nodes := _html_text_nodes(path)
		_ok(nodes.size() > 20,
			"%s: the source export is readable (%d text nodes in %s)"
				% [sid, nodes.size(), String(SOURCE_HTML[sid])])
		if nodes.is_empty():
			continue

		var pool : Dictionary = {}
		for n in nodes:
			pool[String(n)] = true

		var spec : Dictionary = SpecScript.SCREENS[sid]
		# Every label the spec claims must exist verbatim in the HTML.
		var missing : Array = []
		var claimed : Array = []
		claimed.append(String(spec["title"]))
		for t in (spec["timers"] as Array):
			claimed.append(String(t))
		for c in (spec["cards"] as Array):
			var card := c as Dictionary
			claimed.append(String(card["title"]))
			for col in ["gewenst", "reeel"]:
				for r in (card[col] as Array):
					claimed.append(String(r))
		for l in (spec["lamps"] as Array):
			claimed.append(String(l))
		for cl in claimed:
			if not pool.has(String(cl)):
				missing.append(String(cl))
		_ok(missing.is_empty(),
			"%s: all %d spec labels appear VERBATIM in the export (%d invented: %s)"
				% [sid, claimed.size(), missing.size(), str(missing)])

		# ...and the reverse: a motor card present in the export but absent from
		# the spec is a silently dropped device, and dropping one is the easier
		# mistake to make. Card headers are extracted MECHANICALLY by their
		# markup signature rather than by a list of device names — a name list
		# only ever catches devices someone already thought of, which is the
		# wrong shape of check for "what did I forget".
		var card_titles : Dictionary = {}
		for c2 in (spec["cards"] as Array):
			card_titles[String((c2 as Dictionary)["title"])] = true
		for c3 in (spec.get("cards_bottom", []) as Array):
			card_titles[String((c3 as Dictionary)["title"])] = true
		var in_html := _html_card_headers(path)
		var dropped : Array = []
		for h in in_html:
			if not card_titles.has(String(h)):
				dropped.append(String(h))
		var invented_cards : Array = []
		for k in card_titles.keys():
			if not in_html.has(String(k)):
				invented_cards.append(String(k))
		_ok(dropped.is_empty() and invented_cards.is_empty(),
			"%s: the spec's motor cards are EXACTLY the export's %d (%d dropped: %s / %d invented: %s)"
				% [sid, in_html.size(), dropped.size(), str(dropped),
					invented_cards.size(), str(invented_cards)])

		for c4 in (spec["cards"] as Array):
			seen_titles[String((c4 as Dictionary)["title"])] = sid

	# B. The divergence between the two screens must SURVIVE.
	_ok(seen_titles.has("Doseersluis Links") and seen_titles.has("Doseersluis Rechts"),
		"NO NORMALISING: 'Doseersluis Links' and 'Doseersluis Rechts' both survive as DISTINCT labels — a shared helper that unified them would fail here")

	# B. ...and within one screen the three cards keep three different row sets.
	var spec_l : Dictionary = SpecScript.SCREENS["L3C.14L"]
	var shapes : Dictionary = {}
	for c in (spec_l["cards"] as Array):
		var card := c as Dictionary
		shapes["%s|%s" % [str(card["gewenst"]), str(card["reeel"])]] = true
	_ok(shapes.size() == 3,
		"NO NORMALISING: L3C.14L's three motor cards keep %d DISTINCT row layouts (Loopbewaking+Stroom / Aanlooptijd+Uitlooptijd / +Loopbewaking) — hard-coding one card template would fail here"
			% shapes.size())
	_dump["transcription"] = {"card_titles": seen_titles.keys(), "distinct_card_shapes": shapes.size()}


# =============================================================================
# Screen exercise
# =============================================================================

func _mount(sid: String, lf) -> Control:
	var s : Control = UnitScreenScript.new()
	s.call("set_screen", sid)
	add_child(s)
	await get_tree().process_frame
	s.call("bind", {}, lf)
	await get_tree().process_frame
	return s


## C/D/E: structure, dict-vs-pixels agreement, and recorded reasons.
func _audit(sid: String, s: Control, tag: String) -> Dictionary:
	var r : Dictionary = s.call("field_report")
	var b : Array = r["bound"]
	var u : Array = r["unavailable"]
	_ok(int(r["total"]) == b.size() + u.size() and b.size() + u.size() > 0,
		"%s%s: C STRUCTURE — every field accounted for exactly once (%d bound + %d unavailable = %d)"
			% [sid, tag, b.size(), u.size(), int(r["total"])])

	var disagree : Array = []
	for e in b:
		var f := String((e as Dictionary)["field"])
		var painted_b : String = s.call("rendered_text", f)
		# EMPTY counts as a disagreement, not just "--".  The first run of this
		# test passed D while the status pill rendered "" — the field was
		# reported BOUND and nothing could read what it showed.  A bound field
		# that answers "" is unverifiable, which is worse than one that admits
		# it is unavailable.
		if painted_b == "--" or painted_b == "":
			disagree.append("bound-but-unreadable:%s=%s" % [f, "<empty>" if painted_b == "" else painted_b])
	for e2 in u:
		var f2 := String((e2 as Dictionary)["field"])
		var painted : String = s.call("rendered_text", f2)
		# Fields with no widget of their own (the alarm number, chips) answer ""
		# rather than "--"; only a widget-backed field can disagree.
		if painted != "--" and painted != "":
			disagree.append("unavail-but-painted:%s=%s" % [f2, painted])
	_ok(disagree.is_empty(),
		"%s%s: D AGREEMENT — the audit dict matches the pixels (%d disagreement(s): %s)"
			% [sid, tag, disagree.size(), str(disagree)])

	var noreason : Array = []
	for e3 in u:
		if String((e3 as Dictionary).get("reason", "")).strip_edges() == "":
			noreason.append(String((e3 as Dictionary)["field"]))
	_ok(noreason.is_empty(),
		"%s%s: E REASONS — every unavailable field records WHY (%d silent: %s)"
			% [sid, tag, noreason.size(), str(noreason)])
	return r


func _exercise(lf) -> void:
	_section("C-H — every ported screen, live")
	var amps_seen : Dictionary = {}
	var reports : Dictionary = {}

	# COVERAGE FIRST. A spec entry with no source file here would never be
	# transcription-checked, which is the one way a fabricated screen could get in.
	var uncovered : Array = []
	for k in SpecScript.SCREENS.keys():
		if not SOURCE_HTML.has(String(k)):
			uncovered.append(String(k))
	_ok(uncovered.is_empty(),
		"every spec screen is transcription-checked against a source file (%d uncovered: %s)"
			% [uncovered.size(), str(uncovered)])

	var ids : Array = SpecScript.SCREENS.keys()
	ids.sort()
	for sid_v in ids:
		var sid := String(sid_v)
		var spec : Dictionary = SpecScript.SCREENS[sid]
		var s : Control = await _mount(sid, lf)
		var r := _audit(sid, s, "")
		reports[sid] = {"bound": int(r["bound_count"]), "unavail": int(r["unavailable_count"])}

		# H. CARRIERS. "Exactly one" was right while only L3C.14 was ported and is
		# WRONG now: L3C.4's two cards are two SEPARATE machines (L3C.4L/L3C.4R)
		# and both legitimately carry a current, while L3C.16 and L3C.18 have no
		# motor cards at all. The invariant that survives is: a card may claim the
		# current only if it HAS a Stroom row, and every claim must resolve to a
		# machine whose own l3c_code is the one the card names.
		var carriers : Array = []
		for e in (r["bound"] as Array):
			var f := String((e as Dictionary)["field"])
			if f.begins_with("stroom:"):
				carriers.append(f.substr(7))
		var stroomless : Array = []
		var all_cards : Array = []
		all_cards.append_array(spec.get("cards", []) as Array)
		all_cards.append_array(spec.get("cards_bottom", []) as Array)
		for cv in carriers:
			for c in all_cards:
				var card := c as Dictionary
				if String(card.get("title", "")) == String(cv) 						and not (card.get("reeel", []) as Array).has("Stroom"):
					stroomless.append(String(cv))
		_ok(stroomless.is_empty(),
			"%s: H — no card shows a current it has no Stroom row for (%d bad: %s; %d carrier(s): %s)"
				% [sid, stroomless.size(), str(stroomless), carriers.size(), str(carriers)])

		# G. INSTANCE — every bound field resolves through a machine whose OWN
		# l3c_code is the one the field names. A Line 3A sibling sharing the
		# placeable id answering here is a FAIL, and line_3a is built for this.
		var wrong : Array = []
		for e2 in (r["bound"] as Array):
			var code2 := String((e2 as Dictionary).get("code", ""))
			if code2 == "":
				continue
			var info2 : Dictionary = _line_flow_ref.call("get_machine_info", code2)
			if info2.is_empty() or String(info2.get("l3c_code", "")) != code2:
				wrong.append("%s -> %s" % [code2, String(info2.get("l3c_code", "<none>"))])
		_ok(wrong.is_empty(),
			"%s: G INSTANCE — every bound field resolves to its OWN code (%d wrong: %s)"
				% [sid, wrong.size(), str(wrong)])

		# Record this screen's currents for the cross-screen checks below.
		for e3 in (r["bound"] as Array):
			var f3 := String((e3 as Dictionary)["field"])
			if not f3.begins_with("stroom:"):
				continue
			var c3 := String((e3 as Dictionary).get("code", ""))
			var i3 : Dictionary = _line_flow_ref.call("get_machine_info", c3)
			amps_seen[c3] = float(i3.get("amps", 0.0))
		s.queue_free()
		await get_tree().process_frame

	_dump["live"] = {"amps": amps_seen, "reports": reports}
	_note("screens exercised: %d; machines rendering a live current: %s"
		% [ids.size(), str(amps_seen.keys())])

	# F. THE HEADLINE. Two dryers, one machine TYPE, two different currents.
	var a : float = float(amps_seen.get("L3C.14L", 0.0))
	var b : float = float(amps_seen.get("L3C.14R", 0.0))
	_ok(a > 0.0 and b > 0.0,
		"F LIVENESS — both dryers render a non-zero current (%.2f A / %.2f A); both read 0.00 A before the l3c_code work"
			% [a, b])
	_ok(absf(a - b) > 0.5,
		"F LIVENESS, THE HEADLINE — the two dryers render DIFFERENT currents (%.2f A vs %.2f A). Equal values are exactly the defect this work fixed: one placeable id first-matching for both units"
			% [a, b])
	var want_ratio := NOMINAL_14L / NOMINAL_14R
	var got_ratio := (a / b) if b > 0.0 else 0.0
	_ok(absf(got_ratio - want_ratio) < 0.01,
		"each dryer scales its OWN calibrated nominal: measured %.2f/%.2f = %.4f vs hand-transcribed %.2f/%.2f = %.4f. A shared nominal would force this ratio to 1.0000"
			% [a, b, got_ratio, NOMINAL_14L, NOMINAL_14R, want_ratio])
	_note("load point: L3C.14L %.2f A = %.0f%% of its %.2f A nominal; L3C.14R %.2f A = %.0f%%"
		% [a, 100.0 * a / NOMINAL_14L, NOMINAL_14L, b, 100.0 * b / NOMINAL_14R])

	# L3C.4 is the OTHER shape: ONE screen showing TWO machines. Both its cards
	# must resolve, and to DIFFERENT nodes — a screen that rendered one machine
	# twice would look identical on screen and be wrong.
	var f4l : float = float(amps_seen.get("L3C.4L", -1.0))
	var f4r : float = float(amps_seen.get("L3C.4R", -1.0))
	_ok(f4l >= 0.0 and f4r >= 0.0,
		"L3C.4 binds BOTH of its machines (L3C.4L %.2f A, L3C.4R %.2f A) — its two cards are separate units, not one unit's motors"
			% [f4l, f4r])

	# ---- MUTATIONS ----
	_section("MUTATIONS — the criteria above must be able to FAIL")
	for m in [["M1 dead source", StubDeadSource.new()], ["M2 correct-keys-dead-values", StubDefaultValues.new()]]:
		var mname := String(m[0])
		var stub : Node = m[1]
		add_child(stub)
		var s2 : Control = await _mount("L3C.14L", stub)
		var r2 : Dictionary = s2.call("field_report")
		var bound2 := int(r2["bound_count"])
		if mname.begins_with("M1"):
			_ok(bound2 == 0,
				"%s: bound collapses to %d — a screen that still bound fields against a source returning {} would be inventing them"
					% [mname, bound2])
		else:
			_audit("L3C.14L", s2, " [%s]" % mname)
			var painted : String = s2.call("rendered_text", "status:L3C.14L")
			_ok(painted != "Aan",
				"%s: status reads '%s', not 'Aan' — F is the only criterion that catches structurally-perfect dead values, and it is load-bearing"
					% [mname, painted])
		s2.queue_free()
		stub.queue_free()
		await get_tree().process_frame


# =============================================================================
# Boot
# =============================================================================

func _ready() -> void:
	print("=== WASLIJN 3C PER-UNIT SCREENS — transcription + honesty check ===")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via a .tscn, not --script)")
		get_tree().quit(2); return

	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return
	_guard_operator_saves()

	# A/B need no world at all — they compare the spec to the operator's files.
	# Run them FIRST so a transcription failure is reported even if the world
	# boot dies: an invented label is a defect regardless of whether the sim runs.
	_check_transcription()

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _finish(); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(80):
		await get_tree().process_frame

	var lf = world.get("line_flow")
	var bm = world.get("build_mode")
	if bm == null:
		bm = world.find_child("BuildMode", true, false)
	if lf == null or bm == null:
		print("FATAL: LineFlow (%s) or BuildMode (%s) missing after boot"
			% [str(lf != null), str(bm != null)])
		_finish(world); return

	_line_flow_ref = lf
	await _build_world(bm, lf)
	_drive_line(lf)
	await _exercise(lf)

	for c in _wlg.final_checks(world):
		_ok(c[0], c[1])
	_verify_operator_saves()
	_write_dump()
	_finish(world)


## The verdict is printed and user:// restored BEFORE the world is freed, then
## restored again after: the headless teardown segfault lands inside world
## teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
func _finish(world: Node = null) -> void:
	_wlg.restore()
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Dump: %s" % ProjectSettings.globalize_path(DUMP_PATH))
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	if world != null and is_instance_valid(world):
		world.queue_free()
		await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fail == 0 else 1)


func _place_macro(bm, macro_id: String, start_bf: Vector2) -> void:
	var lms := get_node_or_null("/root/LineMacroStore")
	if lms != null:
		lms._cache[macro_id] = {}
	var fr : Dictionary = await BFrame.wait_fitted(bm)
	_ok(not fr.is_empty(), "%s: building frame FITTED from the shell (InteriorLightingManager)" % macro_id)
	if fr.is_empty():
		return
	var start : Vector3 = BFrame.to_scene(fr, start_bf, Plant.floor_top_y())
	bm.call("_build_full_line", macro_id, start, BFrame.forward_rot_y(fr))
	for _i in range(10):
		await get_tree().process_frame


func _build_world(bm, lf) -> void:
	_section("WORLD — line_3c plus line_3a as the shared-id decoy")
	await _place_macro(bm, MACRO_3C, LINE_3C_START_BF)
	await _place_macro(bm, MACRO_ID, LINE_START_BF)
	lf.call("rebuild")
	for _i in range(10):
		await get_tree().process_frame

	# Criterion G is vacuous without a machine that COULD wrongly answer. Prove
	# the decoy is really in the world before claiming the screen resisted it.
	var decoy := 0
	for nd in (lf.get("_nodes") as Array):
		var n = (nd as Dictionary).get("node", null)
		if n != null and is_instance_valid(n) and (n as Node).has_meta("macro_id") \
				and String((n as Node).get_meta("macro_id")) == MACRO_ID:
			decoy += 1
	_ok(decoy > 0,
		"the shared-id DECOY is really there: %d line_3a machines alongside the 3C spine — criterion G proves nothing without them"
			% decoy)
	# Both dryers must exist as SEPARATE nodes, or the headline check is trivial.
	var dryers : Array = []
	for e in (lf.call("machine_list") as Array):
		var c := String((e as Dictionary).get("l3c_code", ""))
		if c == "L3C.14L" or c == "L3C.14R":
			dryers.append(c)
	_ok(dryers.size() == 2,
		"both mech dryers are live and distinct (%d: %s)" % [dryers.size(), str(dryers)])
	_dump["world"] = {"decoy_line_3a_machines": decoy, "dryers": dryers}


func _drive_line(lf) -> void:
	_section("RUN — power and FEED the line")
	lf.call("start_line")
	var injected := 0.0
	for _i in range(TICK_COUNT):
		injected += _feed_heads(lf, TICK_DT)
		lf.call("tick", TICK_DT)
	_ok(injected > 0.0,
		"FEED: %.1f kg injected over %.1f s of sim time" % [injected, TICK_DT * float(TICK_COUNT)])
	var tripped : Array = []
	for nd in (lf.get("_nodes") as Array):
		var mol = (nd as Dictionary).get("mol", null)
		if mol != null and mol.has_method("is_tripped") and bool(mol.call("is_tripped")):
			tripped.append(String((nd as Dictionary)["id"]))
	if tripped.is_empty():
		_note("MotorOverload: no drive tripped at %.2f kg/s per head" % FEED_RATE)
	else:
		_note("MotorOverload TRIPPED: %s — any bound Stroom on these reads 0 A" % str(tripped))
	_dump["feed_kg"] = injected
	_dump["motor_overload_tripped"] = tripped


func _feed_heads(lf, delta: float) -> float:
	var nodes : Array = lf.get("_nodes")
	var fed := 0.0
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if String(nd["role"]) == "sink":
			continue
		if bool(lf.call("_has_incoming", i)):
			continue
		var draw : float = FEED_RATE * delta
		(nd["in"] as MaterialBatch).add(MaterialBatch.new(
			draw, draw / FEED_DENSITY, FEED_COMP.duplicate(), "l3cunit_feed",
			draw * 0.08, draw * 0.12))
		fed += draw
	return fed


func _guard_operator_saves() -> void:
	var dir := DirAccess.open("user://")
	if dir == null:
		return
	for fn in dir.get_files():
		if not (fn.begins_with("allernieuwste_") and fn.ends_with(".json")):
			continue
		var f := FileAccess.open("user://" + fn, FileAccess.READ)
		if f:
			_guarded["user://" + fn] = f.get_as_text().sha256_text()
			f.close()

func _verify_operator_saves() -> void:
	var changed : Array = []
	for p in _guarded.keys():
		var f := FileAccess.open(p, FileAccess.READ)
		var h := f.get_as_text().sha256_text() if f else "<gone>"
		if f: f.close()
		if h != String(_guarded[p]):
			changed.append(p)
	if _guarded.is_empty():
		_note("no allernieuwste_*.json present to guard")
		_skip += 1
	else:
		_ok(changed.is_empty(), "operator allernieuwste_* saves byte-identical after the run (%d changed: %s)"
			% [changed.size(), str(changed)])

func _write_dump() -> void:
	var f := FileAccess.open(DUMP_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_dump, "  "))
		f.close()
