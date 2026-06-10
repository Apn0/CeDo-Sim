extends Control

@onready var save_list: ItemList = $CenterContainer/Centerer/VBoxContainer/SaveList
@onready var load_button: Button = $CenterContainer/Centerer/VBoxContainer/LoadButton
@onready var delete_selected_button: Button = $CenterContainer/Centerer/VBoxContainer/DeleteSelectedButton
@onready var delete_all_button: Button = $CenterContainer/Centerer/VBoxContainer/DeleteAllButton
@onready var new_save_input: LineEdit = $CenterContainer/Centerer/VBoxContainer/NewSaveInput
@onready var new_save_button: Button = $CenterContainer/Centerer/VBoxContainer/NewSaveButton
@onready var world_setup_button: Button = $CenterContainer/Centerer/VBoxContainer/WorldSetupButton

var game_state_script = preload("res://src/scenes/world/GameState.gd")

func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	delete_selected_button.pressed.connect(_on_delete_selected_pressed)
	delete_all_button.pressed.connect(_on_delete_all_pressed)
	new_save_button.pressed.connect(_on_new_save_pressed)
	world_setup_button.pressed.connect(_on_world_setup_pressed)

	_refresh_save_list()

func _on_world_setup_pressed() -> void:
	get_tree().change_scene_to_file("res://src/scenes/world/WorldSetup.tscn")

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

## The canonical save (display) name for a row. Stored in item metadata by
## `_add_save_row`; the visible item text now also carries the info line, so we
## must NOT use get_item_text() for load/delete lookups. Falls back to the first
## text line if metadata is somehow missing.
func _row_name(index: int) -> String:
	var meta = save_list.get_item_metadata(index)
	if meta is String and meta != "":
		return meta
	return save_list.get_item_text(index).get_slice("\n", 0)

func _on_delete_selected_pressed() -> void:
	var selected := save_list.get_selected_items()
	if selected.is_empty():
		return
	var display_name : String = _row_name(selected[0])
	_show_confirm("Delete save \"%s\"?\nThis cannot be undone." % display_name,
		_make_delete_one_handler(display_name))

func _make_delete_one_handler(display_name: String) -> Callable:
	return func() -> void:
		if _delete_save_file(display_name):
			_refresh_save_list()

func _on_delete_all_pressed() -> void:
	if save_list.item_count == 0:
		return
	_show_confirm("Delete ALL %d save files?\nThis cannot be undone." % save_list.item_count,
		_delete_all_handler)

func _delete_all_handler() -> void:
	var deleted := 0
	for i in save_list.item_count:
		if _delete_save_file(_row_name(i)):
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
	# We need to access GameState functionality. Since GameState is an autoload
	# or an instantiated node, but we might not have it yet if it's attached
	# to MainWorld, we'll implement a static-like way or read the dir here
	# For now, let's just do a basic dir scan for .json files in user://
	var dir = DirAccess.open("user://")
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with("_save.json"):
				# Extract save name
				var save_name = file_name.replace("_save.json", "")
				# Avoid the default old save name if possible, or just list it
				if save_name == "cedo_simulator":
					save_name = "default"
				_add_save_row(save_name, "user://" + file_name)
			file_name = dir.get_next()

# ── Save-row rendering ─────────────────────────────────────────────────────────
## Add one ItemList row showing the save name plus a secondary metadata line
## (last-saved date/time, in-game day + shift, play time into the shift, machine
## count). The canonical display name is stored in the item's metadata so the
## load/delete handlers stay robust even though the visible text now carries the
## extra info line.
func _add_save_row(display_name: String, path: String) -> void:
	var idx := save_list.add_item("%s\n%s" % [display_name, _describe_save(path)])
	save_list.set_item_metadata(idx, display_name)

## Build the metadata summary line for one save file. Read-only: parses the JSON
## without mutating it. Returns "(corrupt/old save)" if it can't be read/parsed.
func _describe_save(path: String) -> String:
	var when := _last_saved_label(path)
	if not FileAccess.file_exists(path):
		return "Empty"
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return "(corrupt/old save)"
	var parsed = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return "(corrupt/old save)"
	var parts: Array[String] = []
	if when != "":
		parts.append(when)
	# In-game calendar — day is 0-based on disk, shown 1-based to match the HUD.
	var shift = parsed.get("shift", {})
	if typeof(shift) == TYPE_DICTIONARY and not shift.is_empty():
		var day_index := int(shift.get("day_index", 0))
		var team_index := int(shift.get("team_index", 0))
		var shift_id := ShiftRota.team_shift(team_index, day_index)
		parts.append("Dag %d · %s · %s" % [
			day_index + 1,
			ShiftRota.shift_label(shift_id),
			ShiftRota.team_label(team_index),
		])
		var secs := float(shift.get("elapsed_seconds", 0.0))
		if secs > 0.0:
			parts.append("%s in dienst" % _format_duration(secs))
	# Machine count — only surfaced once any have been placed/saved.
	var machines = parsed.get("machines", {})
	if typeof(machines) == TYPE_DICTIONARY and machines.size() > 0:
		parts.append("%d machine%s" % [machines.size(), "" if machines.size() == 1 else "s"])
	if parts.is_empty():
		return "(corrupt/old save)"
	return "  ·  ".join(parts)

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
	var selected = save_list.get_selected_items()
	if selected.size() > 0:
		var save_name = _row_name(selected[0])
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
		
	get_tree().change_scene_to_file("res://src/scenes/world/MainWorld.tscn")
