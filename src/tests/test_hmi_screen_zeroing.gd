extends Node3D
## HMI MOCKUP ZEROING — the delivered EREMA extruder screen must carry no
## hardcoded non-zero process value (audit defect C4, 2026-08-16).
##
##   godot --headless --path <proj> res://src/tests/test_hmi_screen_zeroing.tscn
##
## WHY THIS EXISTS. `docs/plant/hmi_screens_2026-07-26/EREMA Extruder Scherm
## 3C.dc.html` is a delivered mockup. `HMI Index.dc.html:16` states the set-wide
## convention for the whole set — "Waarden op nul, labels verbatim" — and
## `hmi_screen_inventory_2026-07-28.md:10-13` states why: the mockups are a layout
## spec, the PHOTOS are the data. On 2026-08-16 an agent pasted the ten captured
## readings into this file as literals. Nothing at runtime can overwrite them:
## `hmi_shell.html:326-405` / `:527-553` only rebinds (a) boxes whose text matches
## the amps shape /^\d+(,\d+)?\s*A$/, (b) state squares, (c) "Status …" pills and
## (d) the alarm row — and this screen contains ZERO of all four. So E-stop line 3C,
## walk to the extruder panel (`HmiScopes.gd:220`, scope `hmi_extruder_all`), and a
## literal 120 rpm / 108 °C / 193 kW would still be on screen on a dead line.
##
## WHAT IS CHECKED
##   A. NON-VACUITY   the fixture really is the screen we think it is: it exists,
##                    it is Index-listed, the panel scope points at it, it carries
##                    the 9 expected process labels and exactly the value spans we
##                    are about to inspect. A missing/renamed file FAILS here
##                    rather than silently passing every "is zero" check below.
##   B. ZEROING       every value span reads a bare 0 — or a {{binding}} whose
##                    backing DCLogic value is 0. Pasting live numbers back in by
##                    EITHER route (literal span, or template + numeric array)
##                    turns this RED.
##   C. BINDABILITY   (project rule 4 — behaviour) measured proof that a literal
##                    here is permanent: 0 amps-shaped boxes and 0 "Status …"
##                    pills on this screen, so the shell's val message can rewrite
##                    nothing on it.
##   D. PROVENANCE    the captured readings still exist in the inventory doc, and
##                    the screen still carries its in-file provenance comment. So
##                    zeroing the mockup loses no plant data — if someone strips
##                    the record instead of the literals, this goes RED too.
##
## user:// SAFETY: this test is read-only. It opens no user:// file, writes
## nothing, and never touches user://world_layout.json.

const Scopes := preload("res://src/build/HmiScopes.gd")

const SCREENS_DIR   := "res://docs/plant/hmi_screens_2026-07-26/"
const SCREEN_FILE   := "EREMA Extruder Scherm 3C.dc.html"
const INDEX_FILE    := "HMI Index.dc.html"
const SHELL_FILE    := "hmi_shell.html"
const INVENTORY_DOC := "res://docs/plant/hmi_screen_inventory_2026-07-28.md"
const PANEL_ID      := "hmi_extruder_all"

## Labels transcribed verbatim from the source photo — these MUST stay (the
## convention zeroes values, never labels). If the fixture loses them the file
## is no longer the screen this test guards.
const EXPECTED_LABELS := [
	"SV-vulpeil", "afzuiging 1", "afzuiging 2", "schuif", "ex - belasting",
	"extr rpm", "SV-temperatuur", "SV-belasting", "SV-vermogen",
]

## The value spans the delivered file has (9 boxes + the blue rpm setpoint row +
## the sc-for zone cell). Hardcoded on purpose: it is the non-vacuity floor.
const EXPECTED_VALUE_SPANS := 11

## The real captured readings (inventory doc :193, source photos
## 2024-04-10-13-29-20-271.jpg / -22-533.jpg). They belong in the DOC, never in
## the mockup — so this list is used two ways: they must NOT be in the screen,
## and they MUST still be in the inventory doc.
const CAPTURED := ["45", "55", "100", "102", "120", "108", "61", "193",
	"113", "157", "184", "213"]

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _read(path: String) -> String:
	return FileAccess.get_file_as_string(path)


func _ready() -> void:
	print("=== HMI MOCKUP ZEROING — delivered screens carry no hardcoded process value ===")
	var html := _read(SCREENS_DIR + SCREEN_FILE)
	var spans := _value_spans(html)
	_check_non_vacuity(html, spans)
	_check_zeroing(html, spans)
	_check_bindability(html)
	_check_provenance(html)
	_finish()


## Every "big number" span in a delivered screen: the value cells all carry
## font-weight:600, the labels and unit suffixes do not.
func _value_spans(html: String) -> Array[String]:
	var out: Array[String] = []
	var re := RegEx.new()
	re.compile("<span style=\"[^\"]*font-weight:600[^\"]*\">([^<]*)</span>")
	for m in re.search_all(html):
		out.append(m.get_string(1).strip_edges())
	return out


# =============================================================================
# A. NON-VACUITY — assert the fixture is what we think before judging it
# =============================================================================
func _check_non_vacuity(html: String, spans: Array[String]) -> void:
	print("\n-- A. fixture non-vacuity --")
	_ok(html.length() > 3000, "screen file read: %d chars" % html.length())
	_ok(html.find("data-screen-label=\"EREMA extruder\"") >= 0,
		"screen carries data-screen-label=\"EREMA extruder\"")

	# The panel the operator actually opens must point at THIS file, else the
	# test would be guarding a file nothing renders.
	var scope: Dictionary = Scopes.get_scope(PANEL_ID)
	_ok(not scope.is_empty(), "scope '%s' exists" % PANEL_ID)
	_ok(String(scope.get("web_screen", "")) == SCREEN_FILE,
		"'%s'.web_screen == '%s' (the panel opens this file)" % [PANEL_ID, SCREEN_FILE])

	# Constraint: the file must stay listed in the HMI Index (the ◀/▶ order and
	# HmiWebOverlay._is_known_screen() are both parsed from it).
	var index := _read(SCREENS_DIR + INDEX_FILE)
	_ok(index.length() > 1000, "HMI Index read: %d chars" % index.length())
	_ok(index.find("href=\"%s\"" % SCREEN_FILE) >= 0,
		"screen is still listed in %s" % INDEX_FILE)

	var missing: Array[String] = []
	for lbl in EXPECTED_LABELS:
		if html.find(">%s</div>" % lbl) < 0:
			missing.append(lbl)
	_ok(missing.is_empty(),
		"all %d process labels present verbatim (missing: %s)"
			% [EXPECTED_LABELS.size(), str(missing)])

	_ok(spans.size() == EXPECTED_VALUE_SPANS,
		"found %d value spans to inspect (expect %d — 9 boxes + rpm setpoint + zone cell)"
			% [spans.size(), EXPECTED_VALUE_SPANS])
	_ok(html.find("<sc-for list=\"{{ zones }}\"") >= 0,
		"the 4-zone sc-for strip is still present")
	for zone_name in ["EZ-1", "ZZ-1", "ZZ-2", "ZZ-3"]:
		_ok(html.find("\"%s\"" % zone_name) >= 0,
			"zone '%s' still named in the DCLogic array" % zone_name)


# =============================================================================
# B. ZEROING — the actual defect guard
# =============================================================================
func _check_zeroing(html: String, spans: Array[String]) -> void:
	print("\n-- B. every process value is zero --")
	var script_block := _script_block(html)
	_ok(script_block.length() > 40, "DCLogic script block read: %d chars" % script_block.length())

	var zero_re := RegEx.new()
	zero_re.compile("^0([.,]0+)?$")
	var bind_re := RegEx.new()
	bind_re.compile("^\\{\\{\\s*([A-Za-z0-9_.]+)\\s*\\}\\}$")

	var bad: Array[String] = []
	var literal_zero := 0
	var bound := 0
	for raw in spans:
		if zero_re.search(raw) != null:
			literal_zero += 1
			continue
		var b := bind_re.search(raw)
		if b == null:
			bad.append("'%s' is neither 0 nor a {{binding}}" % raw)
			continue
		# A binding is only honest if what it resolves to is also zero.
		bound += 1
		var key: String = b.get_string(1).get_slice(".", b.get_string(1).get_slice_count(".") - 1)
		for val in _script_numbers_for(script_block, key):
			if absf(val) > 0.0001:
				bad.append("binding '%s' resolves to %s in the DCLogic block" % [raw, str(val)])
	_ok(bad.is_empty(), "all %d value spans read zero (%d literal, %d bound) — %s"
		% [spans.size(), literal_zero, bound,
		   "clean" if bad.is_empty() else "; ".join(bad)])

	# Second, blunter net: none of the captured readings may appear AS a value.
	var as_value: Array[String] = []
	for n in CAPTURED:
		for raw in spans:
			if raw == n:
				as_value.append(n)
				break
	_ok(as_value.is_empty(),
		"no captured reading (%s) appears as a value span — found: %s"
			% [", ".join(CAPTURED), str(as_value)])


## Text of the <script type="text/x-dc"> DCLogic block.
func _script_block(html: String) -> String:
	var i := html.find("data-dc-script")
	if i < 0:
		return ""
	var s := html.find(">", i)
	var e := html.find("</script>", s)
	if s < 0 or e < 0:
		return ""
	return html.substr(s + 1, e - s - 1)


## Every numeric literal assigned to `key` in the DCLogic block, e.g. `temp: 113`.
func _script_numbers_for(block: String, key: String) -> Array[float]:
	var out: Array[float] = []
	if key == "":
		return out
	var re := RegEx.new()
	re.compile("[\"']?\\b%s\\b[\"']?\\s*:\\s*([0-9]+(?:[.,][0-9]+)?)" % key)
	for m in re.search_all(block):
		out.append(float(m.get_string(1).replace(",", ".")))
	return out


# =============================================================================
# C. BINDABILITY — rule 4: prove a literal here really is permanent
# =============================================================================
func _check_bindability(html: String) -> void:
	print("\n-- C. nothing on this screen is runtime-bindable --")
	var shell := _read(SCREENS_DIR + SHELL_FILE)
	_ok(shell.find("__hmiApply") >= 0,
		"hmi_shell.html read and still exposes __hmiApply (the only val sink)")

	# (a) The shell rebinds a box only if its text already looks like amps.
	var amps_re := RegEx.new()
	amps_re.compile("<span[^>]*>\\s*[0-9]+(,[0-9]+)?\\s*A\\s*</span>")
	var amps := amps_re.search_all(html).size()
	_ok(amps == 0, "0 amps-shaped boxes on this screen (found %d) — the units sink cannot reach it" % amps)

	# (b) …and a pill only if a span reads "Status …".
	var pill_re := RegEx.new()
	pill_re.compile("<span[^>]*>\\s*Status\\s")
	var pills := pill_re.search_all(html).size()
	_ok(pills == 0, "0 'Status …' pills on this screen (found %d) — the pills sink cannot reach it" % pills)

	# Positive control: the same probes DO find sinks on a screen that has them,
	# so a broken regex cannot manufacture the green above.
	var overzicht := _read(SCREENS_DIR + "Waslijn 3C Overzicht.dc.html")
	_ok(overzicht.length() > 3000, "control screen 'Waslijn 3C Overzicht' read: %d chars" % overzicht.length())
	var ctrl_amps := amps_re.search_all(overzicht).size()
	var ctrl_pills := pill_re.search_all(overzicht).size()
	_ok(ctrl_amps > 0 or ctrl_pills > 0,
		"control screen HAS sinks (%d amps boxes, %d pills) — the probes work" % [ctrl_amps, ctrl_pills])


# =============================================================================
# D. PROVENANCE — zeroing the mockup must not lose the capture
# =============================================================================
func _check_provenance(html: String) -> void:
	print("\n-- D. the captured values survive in the docs --")
	var inv := _read(INVENTORY_DOC)
	_ok(inv.length() > 10000, "inventory doc read: %d chars" % inv.length())
	_ok(inv.find("### EREMA extruder") >= 0, "inventory doc has the EREMA extruder section")

	# The readings, in the exact shape the inventory records them.
	var records := ["SV-vulpeil = \"45 cm\"", "SV-temperatuur = \"108 °C\"",
		"SV-vermogen = \"193 kW\"", "SV-belasting = \"61 %\"",
		"ZZ-3 \"213 °C\"", "afzuiging 1 = \"55 %\""]
	var lost: Array[String] = []
	for r in records:
		if inv.find(r) < 0:
			lost.append(r)
	_ok(lost.is_empty(), "all %d spot-checked captures still recorded in the inventory (lost: %s)"
		% [records.size(), str(lost)])
	_ok(inv.find("2024-04-10-13-29-20-271.jpg") >= 0,
		"inventory names the source photo (provenance is traceable)")

	# The screen itself must say WHY its boxes are zero.
	_ok(html.find("PROVENANCE") >= 0 and html.find("HMI Index.dc.html:16") >= 0,
		"screen carries an in-file provenance comment citing the zeroing convention")
	_ok(html.find("2024-04-10-13-29-20-271.jpg") >= 0,
		"screen's comment names the source photo")
	_ok(html.find("3A/3B") >= 0 and html.find("265-270 cm") >= 0,
		"screen carries the 3A/3B generation caveat + the documented 3C PCU-vulpeil")
	_ok(inv.find("265-270 cm") >= 0,
		"inventory carries the same caveat (do not calibrate 3C from 45 cm)")


# =============================================================================
func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, 0 skip" % [_pass, _fail])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
