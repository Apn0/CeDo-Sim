extends Node

class_name GameState

# Base save data file path (can be overridden)
var save_file_path: String = "user://cedo_simulator_save.json"

# Game state data
var is_new_save: bool = true
var factory_center: Vector3 = Vector3.ZERO

var shift_data: Dictionary = {}
var player_data: Dictionary = {}
var npc_data: Dictionary = {}
# #152 — Player customizer/wardrobe selections (shirt color, pants color, hair,
# beard, cap, PPE). Loaded by PlayerController._build_player_body() on spawn so
# the visible body matches what the operator picked in the wardrobe (#153).
# Defaults match the existing NPC PPE convention (orange hi-vis + dark blue
# pants, short hair, no beard, no cap) so an empty save reads as "fresh hire".
var player_appearance: Dictionary = {}
var npc_appearances: Dictionary = {}
var custom_npc_roles: Dictionary = {}

# #224 — Player wardrobe (two outfits per character: on_duty + off_duty) keyed
# by display name, plus the operator's chosen display name. CharacterCustomizer
# WRITES these via gs.set(...) and PlayerSpawner READS them on spawn — but they
# were never DECLARED here, so gs.set() silently no-oped (GDScript ignores set()
# on an undeclared property) and every customization was dropped on save, leaving
# the player reset to base after reload. Declaring + persisting them closes the
# leak end-to-end. See save_game()/load_game() below.
var player_wardrobes: Dictionary = {}
var player_name: String = ""
var machine_data: Dictionary = {}
# #124 — operator-set crew pins (HIER + station/role pins) keyed by npc_name.
# Empty on a fresh save; populated by CrewManager.save_pins_dict() each save.
var crew_pins_data: Dictionary = {}

# Signals
signal game_saved
signal game_loaded

func _ready() -> void:
	print("GameState initialized")
	
	# Check if MainMenu passed a specific save name
	if EventBus.has_meta("pending_save_name"):
		var pending_name = str(EventBus.get_meta("pending_save_name"))
		if pending_name != "":
			# Sanitize the save name to prevent path traversal
			var safe_name = pending_name.get_file().validate_filename()
			if safe_name != "":
				save_file_path = "user://%s_save.json" % safe_name
			
	if EventBus.has_meta("pending_is_new_save"):
		is_new_save = EventBus.get_meta("pending_is_new_save")
		# Clear it so it doesn't persist across reloads
		EventBus.remove_meta("pending_is_new_save")
		
	# Load game if save exists AND we aren't explicitly starting a new one
	if not is_new_save and FileAccess.file_exists(save_file_path):
		load_game()

func save_game() -> void:
	"""Save complete game state to file."""
	# #224 — Anti-clobber: an autosave / save-and-quit that fires while the
	# in-memory appearance is still empty (e.g. a save triggered before load_game
	# repopulated it) must NOT wipe customizations already on disk. Only re-read
	# when we'd otherwise write blanks over something real.
	if player_appearance.is_empty() and npc_appearances.is_empty() and player_wardrobes.is_empty():
		_recover_appearance_from_disk()
	var save_data = {
		"version": 1,
		"timestamp": Time.get_ticks_msec(),
		# Wall-clock save time (Unix seconds, UTC). The legacy `timestamp` above is
		# engine-uptime ms and cannot express "when" — the main menu reads `saved_at`
		# to show the last-saved date/time, falling back to the file mtime for older
		# saves that predate this field.
		"saved_at": int(Time.get_unix_time_from_system()),
		"is_new_save": is_new_save,
		"factory_center": {"x": factory_center.x, "y": factory_center.y, "z": factory_center.z},
		"shift": shift_data,
		"player": player_data,
		"npcs": npc_data,
		"machines": machine_data,
		"crew_pins": crew_pins_data,
		"player_appearance": player_appearance,
		"npc_appearances": npc_appearances,
		"custom_npc_roles": custom_npc_roles,
		# #224 — the wardrobe (two-outfit) + display name the customizer writes.
		"player_wardrobes": player_wardrobes,
		"player_name": player_name,
	}

	var json = JSON.stringify(save_data)
	var file = FileAccess.open(save_file_path, FileAccess.WRITE)

	if file:
		file.store_string(json)
		print("Game saved to: ", save_file_path)
		emit_signal("game_saved")
	else:
		push_error("Failed to save game to: ", save_file_path)

func load_game() -> void:
	"""Load complete game state from file."""
	var file = FileAccess.open(save_file_path, FileAccess.READ)

	if file:
		var json_string = file.get_as_text()
		var json = JSON.new()
		var error = json.parse(json_string)

		if error == OK:
			var data = json.data
			
			if typeof(data) != TYPE_DICTIONARY:
				push_error("Save file root is not a JSON object")
				return

			is_new_save = data.get("is_new_save", false) if typeof(data.get("is_new_save")) == TYPE_BOOL else false
			
			var fc = data.get("factory_center", {})
			if typeof(fc) == TYPE_DICTIONARY and fc.has("x"):
				var fx = fc.get("x")
				var fy = fc.get("y", 0)
				var fz = fc.get("z", 0)
				if (typeof(fx) in [TYPE_FLOAT, TYPE_INT]) and (typeof(fy) in [TYPE_FLOAT, TYPE_INT]) and (typeof(fz) in [TYPE_FLOAT, TYPE_INT]):
					factory_center = Vector3(float(fx), float(fy), float(fz))
				
			shift_data = data.get("shift", {}) if typeof(data.get("shift")) == TYPE_DICTIONARY else {}
			player_data = data.get("player", {}) if typeof(data.get("player")) == TYPE_DICTIONARY else {}
			npc_data = data.get("npcs", {}) if typeof(data.get("npcs")) == TYPE_DICTIONARY else {}
			machine_data = data.get("machines", {}) if typeof(data.get("machines")) == TYPE_DICTIONARY else {}
			crew_pins_data = data.get("crew_pins", {}) if typeof(data.get("crew_pins")) == TYPE_DICTIONARY else {}
			player_appearance = data.get("player_appearance", {}) if typeof(data.get("player_appearance")) == TYPE_DICTIONARY else {}
			npc_appearances = data.get("npc_appearances", {}) if typeof(data.get("npc_appearances")) == TYPE_DICTIONARY else {}
			custom_npc_roles = data.get("custom_npc_roles", {}) if typeof(data.get("custom_npc_roles")) == TYPE_DICTIONARY else {}
			
			# #224 — restore the wardrobe + display name so PlayerSpawner's
			# `"player_wardrobes" in game_state` / `player_name` reads see the
			# operator's saved outfits instead of falling back to base.
			player_wardrobes = data.get("player_wardrobes", {}) if typeof(data.get("player_wardrobes")) == TYPE_DICTIONARY else {}
			player_name = String(data.get("player_name", "")) if typeof(data.get("player_name")) == TYPE_STRING else ""
			print("Game loaded from: ", save_file_path)
			emit_signal("game_loaded")
		else:
			push_error("Failed to parse save file")
	else:
		push_warning("No save file found at: ", save_file_path)

# #224 — Read ONLY the appearance fields back from the existing save so an
# empty-in-memory save doesn't blank out a customization already on disk. Called
# from save_game() when all three appearance dicts are empty.
func _recover_appearance_from_disk() -> void:
	if not FileAccess.file_exists(save_file_path):
		return
	var file = FileAccess.open(save_file_path, FileAccess.READ)
	if file == null:
		return
	var json = JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return
	var data = json.data
	if typeof(data) != TYPE_DICTIONARY:
		return
	if typeof(data.get("player_appearance")) == TYPE_DICTIONARY:
		player_appearance = data["player_appearance"]
	if typeof(data.get("npc_appearances")) == TYPE_DICTIONARY:
		npc_appearances = data["npc_appearances"]
	if typeof(data.get("player_wardrobes")) == TYPE_DICTIONARY:
		player_wardrobes = data["player_wardrobes"]
	if typeof(data.get("player_name")) == TYPE_STRING:
		player_name = data["player_name"]
	if not player_appearance.is_empty() or not npc_appearances.is_empty() or not player_wardrobes.is_empty():
		print("[GameState] Preserved on-disk appearance (in-memory was empty)")

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
	if ResourceLoader.exists(save_file_path):
		var error = DirAccess.remove_absolute(save_file_path)
		if error == OK:
			print("Save file deleted")
			is_new_save = true
			factory_center = Vector3.ZERO
			shift_data.clear()
			player_data.clear()
			npc_data.clear()
			machine_data.clear()
			npc_appearances.clear()
			player_appearance.clear()
			player_wardrobes.clear()
			custom_npc_roles.clear()
			player_name = ""
		else:
			push_error("Failed to delete save file")
