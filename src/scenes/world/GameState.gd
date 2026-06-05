extends Node

class_name GameState

# Save data file path
const SAVE_FILE_PATH: String = "user://cedo_simulator_save.json"

# Game state data
var shift_data: Dictionary = {}
var player_data: Dictionary = {}
var npc_data: Dictionary = {}
var machine_data: Dictionary = {}

# Signals
signal game_saved
signal game_loaded

func _ready() -> void:
	print("GameState initialized")
	# Load game if save exists
	if FileAccess.file_exists(SAVE_FILE_PATH):
		load_game()

func save_game() -> void:
	"""Save complete game state to file."""
	var save_data = {
		"version": 1,
		"timestamp": Time.get_ticks_msec(),
		"shift": shift_data,
		"player": player_data,
		"npcs": npc_data,
		"machines": machine_data,
	}

	var json = JSON.stringify(save_data)
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.WRITE)

	if file:
		file.store_string(json)
		print("Game saved to: ", SAVE_FILE_PATH)
		emit_signal("game_saved")
	else:
		push_error("Failed to save game to: ", SAVE_FILE_PATH)

func load_game() -> void:
	"""Load complete game state from file."""
	var file = FileAccess.open(SAVE_FILE_PATH, FileAccess.READ)

	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_string)

		if error == OK:
			var data = json.data
			shift_data = data.get("shift", {})
			player_data = data.get("player", {})
			npc_data = data.get("npcs", {})
			machine_data = data.get("machines", {})
			print("Game loaded from: ", SAVE_FILE_PATH)
			emit_signal("game_loaded")
		else:
			push_error("Failed to parse save file")
	else:
		push_warning("No save file found at: ", SAVE_FILE_PATH)

func save_shift_state(data: Dictionary) -> void:
	"""Save shift-specific state."""
	shift_data = data

func load_shift_state() -> Dictionary:
	"""Load shift-specific state."""
	return shift_data.duplicate()

func has_shift_data() -> bool:
	"""Check if shift data exists."""
	return shift_data.size() > 0

func save_player_state(data: Dictionary) -> void:
	"""Save player position and state."""
	player_data = data

func load_player_state() -> Dictionary:
	"""Load player position and state."""
	return player_data.duplicate()

func save_npc_state(npc_id: String, data: Dictionary) -> void:
	"""Save individual NPC state."""
	if not npc_data.has(npc_id):
		npc_data[npc_id] = {}
	npc_data[npc_id] = data

func load_npc_state(npc_id: String) -> Dictionary:
	"""Load individual NPC state."""
	return npc_data.get(npc_id, {}).duplicate()

func save_machine_state(machine_id: String, data: Dictionary) -> void:
	"""Save machine state (for future simulation features)."""
	if not machine_data.has(machine_id):
		machine_data[machine_id] = {}
	machine_data[machine_id] = data

func load_machine_state(machine_id: String) -> Dictionary:
	"""Load machine state."""
	return machine_data.get(machine_id, {}).duplicate()

func clear_save() -> void:
	"""Delete save file."""
	if ResourceLoader.exists(SAVE_FILE_PATH):
		var error = DirAccess.remove_absolute(SAVE_FILE_PATH)
		if error == OK:
			print("Save file deleted")
			shift_data.clear()
			player_data.clear()
			npc_data.clear()
			machine_data.clear()
		else:
			push_error("Failed to delete save file")
