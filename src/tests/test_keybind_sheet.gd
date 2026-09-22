extends Node
## KEY SHEET (Q4, 2026-09-23) — KeybindSheet.build_rows() lists every action the
## Controls tab knows with its LIVE InputMap binding; the F1 action exists and
## is bound; the sheet renders one row per action and follows a rebind.
##
##   godot --headless --path . res://src/tests/test_keybind_sheet.tscn
##
## Needs the SettingsManager autoload (boot via the .tscn, not --script): its
## _ready() runs _ensure_aux_actions(), which is where help_overlay's F1
## fallback lives, and it applies any saved keybinds — the sheet must show
## those, not project.godot's defaults.

const WATCHDOG_S := 60.0

var _fails := 0
var _oks   := 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if c:
		_oks += 1
	else:
		_fails += 1

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _row(rows: Array, action: String) -> Dictionary:
	for r in rows:
		if String((r as Dictionary).get("action", "")) == action:
			return r
	return {}

func _run() -> void:
	print("[TEST] keybind sheet")
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		print("FATAL: SettingsManager autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return

	# ── S1: the content model covers the Controls tab exactly once each ──
	var rows := KeybindSheet.build_rows()
	var expected : Array = []
	for g in sm.ACTION_GROUPS:
		for a in (g as Dictionary).get("actions", []):
			expected.append(String(a))
	_check(rows.size() > 40, "S1 sheet has a real number of rows (%d)" % rows.size())
	_check(rows.size() == expected.size(), "S1 one row per Controls-tab action (%d rows, %d actions)" % [rows.size(), expected.size()])
	var seen := {}
	var dupes : Array = []
	var missing : Array = []
	for r in rows:
		var a := String((r as Dictionary)["action"])
		if seen.has(a):
			dupes.append(a)
		seen[a] = true
	for a in expected:
		if not seen.has(a):
			missing.append(a)
	_check(dupes.is_empty() and missing.is_empty(), "S1 no duplicate or missing actions (dupes %s, missing %s)" % [str(dupes), str(missing)])
	var blank_labels : Array = []
	var multi_line : Array = []
	for r in rows:
		var d : Dictionary = r
		if String(d["label"]).strip_edges() == "":
			blank_labels.append(d["action"])
		if String(d["label"]).find("\n") >= 0:
			multi_line.append(d["action"])
	_check(blank_labels.is_empty() and multi_line.is_empty(), "S1 every row has a one-line label (blank %s, multi-line %s)" % [str(blank_labels), str(multi_line)])
	var groups := {}
	for r in rows:
		groups[String((r as Dictionary)["group"])] = true
	_check(groups.size() == sm.ACTION_GROUPS.size(), "S1 every group is represented (%d of %d)" % [groups.size(), sm.ACTION_GROUPS.size()])

	# ── S2: the keys column is the live InputMap ──
	var mismatches : Array = []
	var unbound : Array = []
	for r in rows:
		var d : Dictionary = r
		var a := String(d["action"])
		if not InputMap.has_action(a) or InputMap.action_get_events(a).is_empty():
			unbound.append(a)
			if String(d["keys"]) != KeybindSheet.UNBOUND or bool(d["bound"]):
				mismatches.append(a)
			continue
		var want := KeybindSheet.format_events(InputMap.action_get_events(a))
		if String(d["keys"]) != want or not bool(d["bound"]):
			mismatches.append(a)
	_check(mismatches.is_empty(), "S2 every row's keys == the InputMap's events, formatted (mismatch %s)" % str(mismatches))
	_check(unbound.is_empty(), "S2 every Controls-tab action is registered and bound at boot, before any player exists (unbound: %s)" % str(unbound))
	_check(String(_row(rows, "hotbar_5").get("keys", "")) == "5", "S2 hotbar_5 shows '5' (qol-07 — it used to be missing from the Controls tab)")
	_check(String(_row(rows, "feedback_capture").get("keys", "")) == "F10", "S2 feedback_capture shows F10 (the reserved key)")
	_check(String(_row(rows, "tool_use").get("keys", "")) == "Left mouse", "S2 a mouse binding is named, not numbered ('%s')" % String(_row(rows, "tool_use").get("keys", "")))

	# ── S3: the F1 action exists, is in the sheet, and is bound to F1 only ──
	_check(InputMap.has_action("help_overlay"), "S3 help_overlay action exists")
	var f1_events : Array = InputMap.action_get_events("help_overlay") if InputMap.has_action("help_overlay") else []
	_check(f1_events.size() == 1 and f1_events[0] is InputEventKey and (f1_events[0] as InputEventKey).keycode == KEY_F1,
		"S3 help_overlay is bound to exactly F1 (%s)" % KeybindSheet.format_events(f1_events))
	_check(String(_row(rows, "help_overlay").get("keys", "")) == "F1", "S3 the sheet lists itself under F1")
	var f1_owners : Array = []
	for a in InputMap.get_actions():
		for ev in InputMap.action_get_events(a):
			if ev is InputEventKey and ((ev as InputEventKey).keycode == KEY_F1 or (ev as InputEventKey).physical_keycode == KEY_F1):
				f1_owners.append(String(a))
	_check(f1_owners == ["help_overlay"], "S3 F1 belongs to help_overlay alone (%s)" % str(f1_owners))

	# ── S4: the sheet renders one row per action and follows a rebind ──
	var sheet := KeybindSheet.new()
	add_child(sheet)
	await get_tree().process_frame
	_check(not sheet.visible and not sheet.is_open(), "S4 sheet starts hidden")
	sheet.open()
	await get_tree().process_frame
	_check(sheet.is_open() and sheet.visible, "S4 open() shows it")
	_check(sheet.row_count() == rows.size(), "S4 rendered %d rows for %d actions" % [sheet.row_count(), rows.size()])
	_check(sheet.group_count() == sm.ACTION_GROUPS.size(), "S4 rendered %d group headers" % sheet.group_count())
	var labels_in_tree := 0
	for lbl in sheet.find_children("*", "Label", true, false):
		labels_in_tree += 1
	# title + hint + one header per group + two labels per row
	var want_labels : int = 2 + sm.ACTION_GROUPS.size() + 2 * rows.size()
	_check(labels_in_tree == want_labels, "S4 %d Label nodes in the sheet (expected %d)" % [labels_in_tree, want_labels])
	sheet.close()
	_check(not sheet.is_open(), "S4 close() hides it")
	sheet.toggle()
	_check(sheet.is_open(), "S4 toggle() re-opens it")
	sheet.toggle()
	_check(not sheet.is_open(), "S4 toggle() closes it again")

	# Rebind map_toggle M → N at runtime, reopen: the sheet must say N.
	var saved_events : Array = InputMap.action_get_events("map_toggle").duplicate()
	InputMap.action_erase_events("map_toggle")
	var kn := InputEventKey.new()
	kn.keycode = KEY_N
	InputMap.action_add_event("map_toggle", kn)
	sheet.open()
	var after_rows := KeybindSheet.build_rows()
	_check(String(_row(after_rows, "map_toggle").get("keys", "")) == "N", "S4 after a live rebind the sheet shows the new key (map_toggle → N)")
	sheet.close()
	InputMap.action_erase_events("map_toggle")
	for ev in saved_events:
		InputMap.action_add_event("map_toggle", ev)
	_check(String(_row(KeybindSheet.build_rows(), "map_toggle").get("keys", "")) == KeybindSheet.format_events(saved_events),
		"S4 binding restored after the test (%s)" % KeybindSheet.format_events(saved_events))

	var verdict := "PASS" if _fails == 0 else "FAIL"
	print("[TEST] keybind sheet %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	print("Result: %s (%d ok, %d fail)" % [verdict, _oks, _fails])
	get_tree().quit(0 if _fails == 0 else 1)
