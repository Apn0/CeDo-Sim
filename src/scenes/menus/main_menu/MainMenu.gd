extends Control

# #75 follow-up — SaveList is now a 4-column Tree (Name / Last Saved / In-game /
# Play time + machines) instead of a single-column ItemList. The Tree's root is
# hidden so each save shows as a top-level row.
@onready var save_list: Tree = $ScrollContainer/Centerer/Wrapper/SaveList
@onready var load_button: Button = $ScrollContainer/Centerer/Wrapper/LoadButton
@onready var delete_selected_button: Button = $ScrollContainer/Centerer/Wrapper/DeleteSelectedButton
@onready var delete_all_button: Button = $ScrollContainer/Centerer/Wrapper/DeleteAllButton
@onready var new_save_input: LineEdit = $ScrollContainer/Centerer/Wrapper/NewSaveInput
@onready var new_save_button: Button = $ScrollContainer/Centerer/Wrapper/NewSaveButton
@onready var world_setup_button: Button = $ScrollContainer/Centerer/Wrapper/WorldSetupButton
@onready var gauntlet_button: Button = $ScrollContainer/Centerer/Wrapper/GauntletButton

var game_state_script = preload("res://src/scenes/world/GameState.gd")

func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	delete_selected_button.pressed.connect(_on_delete_selected_pressed)
	delete_all_button.pressed.connect(_on_delete_all_pressed)
	new_save_button.pressed.connect(_on_new_save_pressed)
	world_setup_button.pressed.connect(_on_world_setup_pressed)
	gauntlet_button.pressed.connect(_on_gauntlet_pressed)
	# #153 — "Customise character" button. Added programmatically (less risky
	# than editing the .tscn) right after Gauntlet so it sits at the bottom of
	# the main menu's button column.
	var customize_btn := Button.new()
	customize_btn.text = "Customise character"
	customize_btn.custom_minimum_size = Vector2(0, 40)
	customize_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	customize_btn.pressed.connect(_on_customize_pressed)
	var vbox : Node = gauntlet_button.get_parent()
	if vbox != null:
		vbox.add_child(customize_btn)
		vbox.move_child(customize_btn, gauntlet_button.get_index() + 1)
	# #158 — "Macro sandbox" button. Flat grass + all 5 line macros laid out
	# for fast walkthrough (F8 prev / F9 next station).
	# Operator report (post-#158): could only reach it via Tab+Enter, mouse
	# clicks were eaten by overlapping Controls / inherited mouse_filter.
	# Force STOP + match the other buttons' minimum height so it has a real
	# clickable rect (Buttons with no min height collapse under the scroll
	# viewport's bottom edge).
	var sandbox_btn := Button.new()
	sandbox_btn.text = "Macro sandbox"
	sandbox_btn.custom_minimum_size = Vector2(0, 40)
	sandbox_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	sandbox_btn.pressed.connect(_on_sandbox_pressed)
	if vbox != null:
		vbox.add_child(sandbox_btn)
	# Extruder test gauntlet — flat-floor live-editing bench: one detailed
	# extruder + cutter-compactor + live ExtruderMachine sim. Meant to be run
	# alongside the Godot editor so live scene editing applies in-session.
	var extg_btn := Button.new()
	extg_btn.text = "Extruder test gauntlet"
	extg_btn.custom_minimum_size = Vector2(0, 40)
	extg_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	extg_btn.pressed.connect(_on_extruder_gauntlet_pressed)
	if vbox != null:
		vbox.add_child(extg_btn)
		vbox.move_child(sandbox_btn, customize_btn.get_index() + 1)
	# #225 — NPC task bench: flat 3-line world (feeder belt → shredder → wash →
	# extruder → laserfilter + 2 lump carts) running the REAL crew systems:
	# CrewManager, NpcAutonomyBoard auto-assignment, CrewPanel (C) manual
	# role/task assignment, live lump discharge into the carts.
	var npcbench_btn := Button.new()
	npcbench_btn.text = "NPC task bench"
	npcbench_btn.custom_minimum_size = Vector2(0, 40)
	npcbench_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	npcbench_btn.pressed.connect(_on_npc_task_bench_pressed)
	if vbox != null:
		vbox.add_child(npcbench_btn)
	# Feature Tester — sandbox with live dials for tuning a new feature's look
	# (starts with the water-pipe + film stream).
	var feature_btn := Button.new()
	feature_btn.text = "Feature tester"
	feature_btn.custom_minimum_size = Vector2(0, 40)
	feature_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	feature_btn.pressed.connect(_on_feature_tester_pressed)
	if vbox != null:
		vbox.add_child(feature_btn)
		vbox.move_child(feature_btn, sandbox_btn.get_index() + 1)
	var dragger_btn := Button.new()
	dragger_btn.text = "Line layout dragger"
	dragger_btn.custom_minimum_size = Vector2(0, 40)
	dragger_btn.mouse_filter = Control.MOUSE_FILTER_STOP
	dragger_btn.pressed.connect(_on_line_dragger_pressed)
	if vbox != null:
		vbox.add_child(dragger_btn)
		vbox.move_child(dragger_btn, feature_btn.get_index() + 1)
	# Tree column titles + widths. column 0 (name) is the widest because save
	# names can be long; the other three are sized for readable timestamps and
	# the secondary metadata.
	save_list.set_column_title(0, "Save name")
	save_list.set_column_title(1, "Last saved")
	save_list.set_column_title(2, "In-game day / shift")
	save_list.set_column_title(3, "Play time / machines")
	save_list.set_column_expand(0, true)
	save_list.set_column_expand(1, true)
	save_list.set_column_expand(2, true)
	save_list.set_column_expand(3, true)
	save_list.set_column_custom_minimum_width(0, 220)
	save_list.set_column_custom_minimum_width(1, 170)
	save_list.set_column_custom_minimum_width(2, 240)
	save_list.set_column_custom_minimum_width(3, 200)
	# Double-click a row → load (operator convenience).
	save_list.item_activated.connect(_on_load_pressed)

	_refresh_save_list()

func _on_world_setup_pressed() -> void:
	_go_to_scene("res://src/scenes/world/WorldSetup.tscn",
		"Loading world setup…", "")

## #153 — Character customizer / wardrobe. Opened from a button on the main
## menu OR from the in-game wardrobe locker (#154). Overlays the customizer
## scene on top of the current scene; the customizer handles its own
## save/cancel + pause/unpause + mouse-mode dance.
func open_character_customizer() -> void:
	var script := load("res://src/scenes/hud/CharacterCustomizer.gd")
	if script == null:
		push_error("[MainMenu] CharacterCustomizer.gd missing")
		return
	var customizer : Node = script.new()
	customizer.name = "CharacterCustomizer"
	get_tree().root.add_child(customizer)
	if customizer.has_method("open"):
		customizer.call("open")

func _on_customize_pressed() -> void:
	open_character_customizer()

## #158 — Macro sandbox. Flat grass world with all 5 line macros pre-spawned.
func _on_sandbox_pressed() -> void:
	_go_to_scene("res://src/scenes/world/SandboxWorld.tscn",
		"Loading macro sandbox…", "")

## Feature Tester — a dials sandbox for tuning a feature's look in real time.
func _on_feature_tester_pressed() -> void:
	get_tree().change_scene_to_file("res://src/scenes/menus/feature_tester/FeatureTester.tscn")

func _on_line_dragger_pressed() -> void:
	get_tree().change_scene_to_file("res://src/scenes/menus/line_dragger/LineDragger.tscn")

## Backlog-verification launcher. Loads GauntletWorld.tscn — a long platform
## with one station per pending / recently-finished task so the operator can
## walk past each and confirm. NOT a real shift: crew + LineFlow + bale yards
## stay out so verification is fast.
func _on_gauntlet_pressed() -> void:
	_go_to_scene("res://src/scenes/world/GauntletWorld.tscn",
		"Loading gauntlet…", "")

## Flat-floor extruder bench (extruder + PCU + live sim) for editor-driven
## live tuning. See ExtruderGauntlet.gd.
func _on_extruder_gauntlet_pressed() -> void:
	_go_to_scene("res://src/scenes/world/ExtruderGauntlet.tscn",
		"Loading extruder bench…", "")

## #225 — NPC task bench: 3 flat lines + live crew systems. See NpcTaskBench.gd.
func _on_npc_task_bench_pressed() -> void:
	_go_to_scene("res://src/scenes/world/NpcTaskBench.tscn",
		"Loading NPC task bench…", "")

# ── Save-file deletion ───────────────────────────────────────────────────────
## Translate the display name back to the on-disk filename. "default" is the
## historical label for the legacy `cedo_simulator_save.json`; everything else
## is `<name>_save.json` as written by GameState.
func _save_path_for(display_name: String) -> String:
	var stem : String = display_name
	if stem == "default":
		stem = "cedo_simulator"
	return "user://%s_save.json" % stem

func _delete_save_file(display_name: String) -> bool:
	var path := _save_path_for(display_name)
	if not FileAccess.file_exists(path):
		push_warning("[MainMenu] save not found at %s" % path)
		return false
	var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if err != OK:
		# Fallback for sandbox: try the user:// path directly.
		err = DirAccess.remove_absolute(path)
	if err != OK:
		push_error("[MainMenu] failed to delete %s (err %d)" % [path, err])
		return false
	print("[MainMenu] deleted %s" % path)
	return true

## The canonical save (display) name for a Tree row. Stored in the TreeItem's
## metadata (column 0) by `_add_save_row`; falls back to the cell's TEXT for
## migration safety.
func _row_name_from(item: TreeItem) -> String:
	if item == null:
		return ""
	var meta = item.get_metadata(0)
	if meta is String and meta != "":
		return meta
	return item.get_text(0)

## Walk every row in the Tree (the operator's save files). Used by delete-all
## + counting. Skips the hidden root.
func _save_rows() -> Array:
	var rows : Array = []
	var root := save_list.get_root()
	if root == null:
		return rows
	var c := root.get_first_child()
	while c != null:
		rows.append(c)
		c = c.get_next()
	return rows

func _on_delete_selected_pressed() -> void:
	var sel : TreeItem = save_list.get_selected()
	if sel == null:
		return
	var display_name : String = _row_name_from(sel)
	_show_confirm("Delete save \"%s\"?\nThis cannot be undone." % display_name,
		_make_delete_one_handler(display_name))

func _make_delete_one_handler(display_name: String) -> Callable:
	return func() -> void:
		if _delete_save_file(display_name):
			_refresh_save_list()

func _on_delete_all_pressed() -> void:
	var rows := _save_rows()
	if rows.is_empty():
		return
	_show_confirm("Delete ALL %d save files?\nThis cannot be undone." % rows.size(),
		_delete_all_handler)

func _delete_all_handler() -> void:
	var deleted := 0
	for r in _save_rows():
		if _delete_save_file(_row_name_from(r as TreeItem)):
			deleted += 1
	print("[MainMenu] deleted %d save(s)" % deleted)
	_refresh_save_list()

## Centralised confirm dialog. Two-button modal — only invokes `on_ok` on Yes.
func _show_confirm(message: String, on_ok: Callable) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.dialog_text = message
	dlg.title = "Confirm"
	dlg.get_ok_button().text = "Delete"
	add_child(dlg)
	dlg.confirmed.connect(func() -> void:
		on_ok.call()
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()

func _refresh_save_list() -> void:
	save_list.clear()
	# Create a hidden root — every save becomes its top-level child. Tree.clear()
	# wipes the root too, so we have to re-create on each refresh.
	save_list.create_item()
	var dir = DirAccess.open("user://")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with("_save.json"):
				var save_name = file_name.replace("_save.json", "")
				if save_name == "cedo_simulator":
					save_name = "default"
				_add_save_row(save_name, "user://" + file_name)
			file_name = dir.get_next()

# ── Save-row rendering ─────────────────────────────────────────────────────────
## Add ONE save to the Tree, populating all four columns from the save file's
## metadata. The canonical display name is stashed on column 0's metadata so
## load/delete lookups stay robust if the visible name is ever localised or
## truncated.
func _add_save_row(display_name: String, path: String) -> void:
	var root := save_list.get_root()
	var row := save_list.create_item(root)
	var cols := _describe_save_columns(path)
	row.set_text(0, display_name)
	row.set_metadata(0, display_name)
	row.set_text(1, cols[0])
	row.set_text(2, cols[1])
	row.set_text(3, cols[2])
	# Visual hint: corrupt rows show their fields in a muted colour. Help the
	# operator spot a busted save at a glance.
	if cols[0] == "(corrupt/old save)":
		var dim := Color(0.7, 0.4, 0.4)
		for c in 4:
			row.set_custom_color(c, dim)

## Returns [last_saved, in_game_day_shift, play_time_and_machines] strings for
## one save file. Read-only: parses the JSON without touching it. Missing
## fields collapse to "—" so the columns still align.
func _describe_save_columns(path: String) -> Array:
	var last := _last_saved_label(path)
	if not FileAccess.file_exists(path):
		return ["(empty)", "—", "—"]
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ["(corrupt/old save)", "—", "—"]
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return ["(corrupt/old save)", "—", "—"]
	# Column 1: last-saved wall-clock (already formatted).
	var col_last := last if last != "" else "—"
	# Column 2: in-game day + shift.
	var col_shift := "—"
	var shift = parsed.get("shift", {})
	if typeof(shift) == TYPE_DICTIONARY and not shift.is_empty():
		var day_index := int(shift.get("day_index", 0))
		var team_index := int(shift.get("team_index", 0))
		var shift_id := ShiftRota.team_shift(team_index, day_index)
		col_shift = "Dag %d · %s · %s" % [
			day_index + 1, ShiftRota.shift_label(shift_id), ShiftRota.team_label(team_index)]
	# Column 3: play time into the current shift + machine count.
	var pieces : Array[String] = []
	if typeof(shift) == TYPE_DICTIONARY and not shift.is_empty():
		var secs := float(shift.get("elapsed_seconds", 0.0))
		if secs > 0.0:
			pieces.append(_format_duration(secs))
	var machines = parsed.get("machines", {})
	if typeof(machines) == TYPE_DICTIONARY and machines.size() > 0:
		pieces.append("%d machine%s" % [machines.size(), "" if machines.size() == 1 else "s"])
	var col_play := "  ·  ".join(pieces) if not pieces.is_empty() else "—"
	return [col_last, col_shift, col_play]

## Last-saved wall-clock label. Prefers the explicit `saved_at` Unix timestamp
## (written by GameState for new saves); falls back to the file's modified time
## so existing saves still show a real date. Returns "" if neither is available.
func _last_saved_label(path: String) -> String:
	var unix := 0
	var file := FileAccess.open(path, FileAccess.READ)
	if file != null:
		var parsed = JSON.parse_string(file.get_as_text())
		if typeof(parsed) == TYPE_DICTIONARY:
			unix = int(parsed.get("saved_at", 0))
	if unix <= 0:
		unix = int(FileAccess.get_modified_time(path))
	if unix <= 0:
		return ""
	# Local time, human-readable: "Saved 2026-06-08 14:32".
	var dt := Time.get_datetime_dict_from_unix_time(unix)
	return "Saved %04d-%02d-%02d %02d:%02d" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute,
	]

## Format a duration in seconds as "Hh Mm" (or "Mm" under an hour).
func _format_duration(seconds: float) -> String:
	var total := int(seconds)
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total % 3600) / 60
	if hours > 0:
		return "%dh %02dm" % [hours, minutes]
	return "%dm" % minutes

func _on_load_pressed() -> void:
	# SaveList is a Tree now (per #75 follow-up). Pull the selected TreeItem and
	# resolve its display name via _row_name_from(). ItemList's get_selected_items
	# API would error here — it doesn't exist on Tree.
	var sel : TreeItem = save_list.get_selected()
	if sel == null:
		return
	var save_name : String = _row_name_from(sel)
	if save_name == "default":
		save_name = "cedo_simulator"
	_start_game(save_name, false)

func _on_new_save_pressed() -> void:
	var save_name = new_save_input.text.strip_edges()
	if save_name != "":
		_start_game(save_name, true)

func _start_game(save_name: String, is_new: bool) -> void:
	if not EventBus.has_user_signal("pending_save_setup"):
		# We'll just dynamically add properties to EventBus
		EventBus.set_meta("pending_save_name", save_name)
		EventBus.set_meta("pending_is_new_save", is_new)
	else:
		EventBus.set_meta("pending_save_name", save_name)
		EventBus.set_meta("pending_is_new_save", is_new)

	_go_to_scene("res://src/scenes/world/MainWorld.tscn",
		"Loading shift…",
		"Building the plant — this can take ~30 seconds. The window may say\n\"Not Responding\" while the world is built; it isn't stuck.")

## Full-screen loading curtain, then the scene change. change_scene_to_file
## loads + builds the target world in ONE main-thread frame (~27 s measured
## for MainWorld on the GTX 1070) during which no new frame is presented —
## whatever rendered LAST stays on screen and Windows flags the window
## "Not Responding". Painting this curtain and awaiting two frames first
## means the player stares at an honest loading screen instead of what
## looks like a crashed menu.
func _go_to_scene(path: String, headline: String, detail: String) -> void:
	var curtain := ColorRect.new()
	curtain.name = "LoadingCurtain"
	curtain.color = Color(0.10, 0.11, 0.13, 1.0)
	curtain.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.mouse_filter = Control.MOUSE_FILTER_STOP   # swallow stray clicks
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	curtain.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	center.add_child(box)
	var head := Label.new()
	head.text = headline
	head.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	head.add_theme_font_size_override("font_size", 40)
	box.add_child(head)
	var sub := Label.new()
	sub.text = detail
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.modulate = Color(1.0, 1.0, 1.0, 0.65)
	box.add_child(sub)
	add_child(curtain)
	# Two frames: one for layout, one so the curtain is actually PRESENTED
	# before the load freezes the main thread.
	await get_tree().process_frame
	await get_tree().process_frame
	get_tree().change_scene_to_file(path)
