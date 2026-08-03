extends Node
## LINE 3C SEQ ALIGNMENT — the guard that makes code_for_macro_entry a
## transcription instead of a guess.
##
##   godot --headless --path <proj> res://src/tests/test_line3c_seq_alignment.tscn
##
## Line3CDef.code_for_macro_entry(macro_id, idx) derives a machine's PLANT ADDRESS
## from its macro_index. That derivation is only truthful while
## BuildMode.LINE_3C_SEQ and Line3CDef.STAGES stay index-aligned — inserting or
## reordering one row silently re-addresses every later stage, which would hand
## L3C.9R's 30.88 A to L3C.10L. This test is what makes that impossible to do
## quietly. No world, no physics, pure data: it is the cheapest check in the
## harness and the one every other 3C assertion rests on.
##
## It also asserts the two properties the addressing scheme needs from the spine
## itself: every stage code is UNIQUE (a duplicated code would collapse
## LineFlow's code_idx, LineFlow.gd:981-985), and every stage id resolves in
## PlaceableCatalog (an unresolvable id would make the macro place fewer machines
## than the SEQ claims, so indices past the gap would still line up but the world
## would be missing an address).
##
## MUTATION-PROVEN: swapping two LINE_3C_SEQ rows, appending a row, or renaming
## one id each turn a named check RED (see the run report).

const Line3CDefScript = preload("res://src/sim/Line3CDef.gd")

var _pass := 0
var _fail := 0


func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg); _pass += 1
	else:
		print("  FAIL  : %s" % msg); _fail += 1


func _ready() -> void:
	print("=== LINE 3C SEQ ALIGNMENT — BuildMode.LINE_3C_SEQ vs Line3CDef.STAGES ===")

	var seq : Array = BuildMode.LINE_3C_SEQ
	var stages : Array = Line3CDefScript.STAGES

	# NON-VACUITY: 0 == 0 would satisfy every check below.
	_ok(stages.size() > 0 and seq.size() > 0,
		"both tables are non-empty (%d SEQ entries / %d stages)" % [seq.size(), stages.size()])
	_ok(seq.size() == stages.size(),
		"LINE_3C_SEQ.size() %d == Line3CDef.stage_count() %d"
			% [seq.size(), Line3CDefScript.stage_count()])

	var id_mismatch : Array = []
	var code_mismatch : Array = []
	var n : int = mini(seq.size(), stages.size())
	for i in n:
		var seq_id := String((seq[i] as Dictionary).get("id", ""))
		var st_id := String((stages[i] as Dictionary)["id"])
		var st_code := String((stages[i] as Dictionary)["code"])
		if seq_id != st_id:
			id_mismatch.append("idx %d: SEQ '%s' vs STAGES '%s'" % [i, seq_id, st_id])
		var derived := Line3CDefScript.code_for_macro_entry(Line3CDefScript.MACRO_ID, i)
		if derived != st_code:
			code_mismatch.append("idx %d: derived '%s' vs stage '%s'" % [i, derived, st_code])
	_ok(id_mismatch.is_empty(),
		"every LINE_3C_SEQ id matches its stage id (%d mismatch: %s)"
			% [id_mismatch.size(), str(id_mismatch)])
	_ok(code_mismatch.is_empty(),
		"code_for_macro_entry(\"%s\", i) == STAGES[i].code for all %d entries (%d mismatch: %s)"
			% [Line3CDefScript.MACRO_ID, n, code_mismatch.size(), str(code_mismatch)])

	# Uniqueness of the addresses themselves. LineFlow's code_idx is a
	# first-match map keyed on l3c_code, so two stages sharing a code would drop
	# edges silently — the identical defect one layer up from the placeable id.
	var seen_codes : Dictionary = {}
	var dup_codes : Array = []
	for st in stages:
		var c := String((st as Dictionary)["code"])
		if seen_codes.has(c):
			dup_codes.append(c)
		seen_codes[c] = true
	_ok(dup_codes.is_empty(),
		"every Line3CDef stage code is UNIQUE (%d duplicate: %s)" % [dup_codes.size(), str(dup_codes)])

	# The macro can only address what it can actually build.
	var unresolved : Array = []
	for e in seq:
		var mid := String((e as Dictionary).get("id", ""))
		if mid == "" or PlaceableCatalog.get_item(mid).is_empty():
			unresolved.append(mid)
	_ok(unresolved.is_empty(),
		"every LINE_3C_SEQ id resolves in PlaceableCatalog (%d unresolved: %s)"
			% [unresolved.size(), str(unresolved)])

	# The contract must refuse everything that is not this macro — otherwise a
	# Line 3A friction_sep at index 2 would inherit L3C.4L.
	var leaks : Array = []
	for other in ["line_3a", "line_3b", "line_1", "line_intake_3a3b", "line_sort",
			"line_intake_3c6", ""]:
		for i2 in range(0, mini(4, n)):
			if Line3CDefScript.code_for_macro_entry(String(other), i2) != "":
				leaks.append("%s[%d]" % [String(other), i2])
	_ok(leaks.is_empty(),
		"code_for_macro_entry refuses every non-3C macro (%d leak: %s)" % [leaks.size(), str(leaks)])
	_ok(Line3CDefScript.code_for_macro_entry(Line3CDefScript.MACRO_ID, -1) == ""
			and Line3CDefScript.code_for_macro_entry(Line3CDefScript.MACRO_ID, stages.size()) == "",
		"code_for_macro_entry is bounds-safe (idx -1 and idx %d both return \"\")" % stages.size())

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
