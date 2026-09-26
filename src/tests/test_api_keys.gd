extends SceneTree

const CFG_PATH = "user://api_keys.cfg"
const KEY_PATH = "user://api_keys.key"
const ApiKeysScript = preload("res://src/autoload/ApiKeys.gd")

var _fail := 0
var _pass := 0

var _original_cfg_content = null
var _original_key_content = null

class MockApiKeys extends "res://src/autoload/ApiKeys.gd":
	var mock_env_path = ""
	var mock_bootstrap_allowed = true
	func _desktop_env_path() -> String:
		return mock_env_path
	func _env_bootstrap_allowed() -> bool:
		return mock_bootstrap_allowed

func _init() -> void:
	print("=== ApiKeys verification ===")
	_backup_files()

	_test_empty_keys()
	_test_bootstrap_from_env()
	_test_migration_from_plaintext()
	_test_migration_from_os_id()
	_test_exported_build_ignores_env()

	_restore_files()

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	if _fail == 0:
		print("RESULT: PASS")
	print("=========================================")
	quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _backup_files() -> void:
	if FileAccess.file_exists(CFG_PATH):
		var f := FileAccess.open(CFG_PATH, FileAccess.READ)
		if f:
			_original_cfg_content = f.get_buffer(f.get_length())
			f.close()

	if FileAccess.file_exists(KEY_PATH):
		var f := FileAccess.open(KEY_PATH, FileAccess.READ)
		if f:
			_original_key_content = f.get_buffer(f.get_length())
			f.close()

	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEY_PATH))

func _restore_files() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEY_PATH))

	if _original_cfg_content != null:
		var f := FileAccess.open(CFG_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_original_cfg_content)
			f.close()

	if _original_key_content != null:
		var f := FileAccess.open(KEY_PATH, FileAccess.WRITE)
		if f:
			f.store_buffer(_original_key_content)
			f.close()

func _clear_test_files() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CFG_PATH))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(KEY_PATH))

func _test_empty_keys() -> void:
	print("\n[1] Default keys should be empty")
	_clear_test_files()
	var api = MockApiKeys.new()
	api._ready()
	_ok(api.google() == "", "Google key is empty by default")
	_ok(api.openai() == "", "OpenAI key is empty by default")
	api.free()

func _test_bootstrap_from_env() -> void:
	print("\n[2] Bootstrap from .env")
	_clear_test_files()
	var env_path = "user://test_desktop.env"
	var f = FileAccess.open(env_path, FileAccess.WRITE)
	f.store_line("GOOGLE_API_KEY=test_google_123")
	f.store_line("OPENAI_API_KEY=test_openai_456")
	f.close()

	var api = MockApiKeys.new()
	api.mock_env_path = env_path
	api._ready()

	_ok(api.google() == "test_google_123", "Bootstrapped Google key correctly")
	_ok(api.openai() == "test_openai_456", "Bootstrapped OpenAI key correctly")

	# Verify it's encrypted on disk by loading it back
	var check_cfg = ConfigFile.new()
	var test_key = OS.get_unique_id()
	var enc_err = check_cfg.load_encrypted_pass(CFG_PATH, test_key)
	_ok(enc_err == OK, "File can be loaded with the generated encryption key")

	# Verify it matches
	_ok(check_cfg.get_value("google", "api_key", "") == "test_google_123", "Saved google key matches")
	_ok(check_cfg.get_value("openai", "api_key", "") == "test_openai_456", "Saved openai key matches")

	api.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(env_path))

func _test_migration_from_plaintext() -> void:
	print("\n[3] Migration from plaintext config")
	_clear_test_files()

	var cfg = ConfigFile.new()
	cfg.set_value("google", "api_key", "plain_google")
	cfg.set_value("openai", "api_key", "plain_openai")
	cfg.save(CFG_PATH)

	var api = MockApiKeys.new()
	api._ready()

	_ok(api.google() == "plain_google", "Migrated Google key from plaintext")
	_ok(api.openai() == "plain_openai", "Migrated OpenAI key from plaintext")

	var check_cfg = ConfigFile.new()
	var secure_err = check_cfg.load_encrypted_pass(CFG_PATH, OS.get_unique_id())
	_ok(secure_err == OK, "File is now stored with the secure key")

	api.free()

func _test_migration_from_os_id() -> void:
	print("\n[4] Migration from legacy key file encryption")
	_clear_test_files()

	var legacy_key := "legacy_secret_key_789"
	var cfg = ConfigFile.new()
	cfg.set_value("google", "api_key", "legacy_google")
	cfg.set_value("openai", "api_key", "legacy_openai")
	cfg.save_encrypted_pass(CFG_PATH, legacy_key)

	var kf = FileAccess.open(KEY_PATH, FileAccess.WRITE)
	kf.store_string(legacy_key)
	kf.close()

	var api = MockApiKeys.new()
	api._ready()

	_ok(api.google() == "legacy_google", "Migrated Google key from legacy key file")
	_ok(api.openai() == "legacy_openai", "Migrated OpenAI key from legacy key file")
	_ok(not FileAccess.file_exists(KEY_PATH), "Legacy key file was removed after migration")

	var check_cfg = ConfigFile.new()
	var secure_err = check_cfg.load_encrypted_pass(CFG_PATH, OS.get_unique_id())
	_ok(secure_err == OK, "File is now stored with the secure OS ID key")

	api.free()

func _test_exported_build_ignores_env() -> void:
	print("
[5] An exported build never reads the player's Desktop .env")
	var real = ApiKeysScript.new()
	_ok(real._env_bootstrap_allowed() == OS.has_feature("editor"),
		"the real gate follows the 'editor' feature (this run: editor=%s)" % OS.has_feature("editor"))
	real.free()
	_clear_test_files()
	var env_path = "user://test_desktop.env"
	var f = FileAccess.open(env_path, FileAccess.WRITE)
	f.store_line("GOOGLE_API_KEY=player_google_999")
	f.store_line("OPENAI_API_KEY=player_openai_999")
	f.close()

	var api = MockApiKeys.new()
	api.mock_env_path = env_path
	api.mock_bootstrap_allowed = false   # what OS.has_feature("editor") is in an export
	api._ready()

	_ok(api.google() == "", "Google key NOT taken from the .env")
	_ok(api.openai() == "", "OpenAI key NOT taken from the .env")
	var check_cfg = ConfigFile.new()
	check_cfg.load_encrypted_pass(CFG_PATH, OS.get_unique_id())
	_ok(check_cfg.get_value("google", "api_key", "") == "", "nothing written to api_keys.cfg")

	api.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(env_path))
