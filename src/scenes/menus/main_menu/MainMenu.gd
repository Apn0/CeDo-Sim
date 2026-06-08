extends Control

@onready var save_list: ItemList = $CenterContainer/VBoxContainer/SaveList
@onready var load_button: Button = $CenterContainer/VBoxContainer/LoadButton
@onready var new_save_input: LineEdit = $CenterContainer/VBoxContainer/NewSaveInput
@onready var new_save_button: Button = $CenterContainer/VBoxContainer/NewSaveButton
@onready var world_setup_button: Button = $CenterContainer/VBoxContainer/WorldSetupButton

var game_state_script = preload("res://src/scenes/world/GameState.gd")

func _ready() -> void:
	load_button.pressed.connect(_on_load_pressed)
	new_save_button.pressed.connect(_on_new_save_pressed)
	world_setup_button.pressed.connect(_on_world_setup_pressed)

	_refresh_save_list()

func _on_world_setup_pressed() -> void:
	get_tree().change_scene_to_file("res://src/scenes/world/WorldSetup.tscn")

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
				save_list.add_item(save_name)
			file_name = dir.get_next()

func _on_load_pressed() -> void:
	var selected = save_list.get_selected_items()
	if selected.size() > 0:
		var save_name = save_list.get_item_text(selected[0])
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
