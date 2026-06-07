extends SceneTree

var _pass : int = 0
var _fail : int = 0

func _init():
	print("============================================================")
	print("  CeDo Simulator — SecuritySaveTest")
	print("============================================================")

	_test_array_root()
	_test_bad_dict_values()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	quit(_fail)

func _test_array_root():
	print("Testing with array root...")
	var file_path = "user://test_security_save_array.json"
	var file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string('["malicious", "array"]')
	file.close()

	var json_string = FileAccess.get_file_as_string(file_path)
	var json = JSON.new()
	var error = json.parse(json_string)

	if error == OK:
		var data = json.data
		if typeof(data) != TYPE_DICTIONARY:
			_pass += 1
		else:
			_fail += 1
	else:
		_fail += 1

	DirAccess.remove_absolute(file_path)

func _test_bad_dict_values():
	print("Testing with bad dictionary values...")
	var file_path = "user://test_security_save_dict.json"

	var file = FileAccess.open(file_path, FileAccess.WRITE)
	file.store_string('{"shift": ["not_dict"], "player": "also_not_dict", "factory_center": "str", "npcs": 123, "machines": null}')
	file.close()

	var json_string = FileAccess.get_file_as_string(file_path)
	var json = JSON.new()
	var error = json.parse(json_string)

	if error == OK:
		var data = json.data
		if typeof(data) == TYPE_DICTIONARY:
			var shift_data = data.get("shift", {}) if typeof(data.get("shift")) == TYPE_DICTIONARY else {}
			var player_data = data.get("player", {}) if typeof(data.get("player")) == TYPE_DICTIONARY else {}
			var npc_data = data.get("npcs", {}) if typeof(data.get("npcs")) == TYPE_DICTIONARY else {}
			var machine_data = data.get("machines", {}) if typeof(data.get("machines")) == TYPE_DICTIONARY else {}

			if typeof(shift_data) == TYPE_DICTIONARY and shift_data.size() == 0:
				_pass += 1
			else:
				_fail += 1

			if typeof(player_data) == TYPE_DICTIONARY and player_data.size() == 0:
				_pass += 1
			else:
				_fail += 1

			if typeof(npc_data) == TYPE_DICTIONARY and npc_data.size() == 0:
				_pass += 1
			else:
				_fail += 1

			if typeof(machine_data) == TYPE_DICTIONARY and machine_data.size() == 0:
				_pass += 1
			else:
				_fail += 1

			var fc = data.get("factory_center", {})
			var factory_center = Vector3.ZERO
			if typeof(fc) == TYPE_DICTIONARY and fc.has("x"):
				factory_center = Vector3(fc["x"], fc.get("y", 0), fc.get("z", 0))

			if typeof(factory_center) == TYPE_VECTOR3 and factory_center == Vector3.ZERO:
				_pass += 1
			else:
				_fail += 1
		else:
			_fail += 1

	DirAccess.remove_absolute(file_path)
