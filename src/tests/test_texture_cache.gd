extends SceneTree

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	print("=== TEXTURE CACHE TEST ===")

	# Mock APPDATA
	var test_dir := "user://test_appdata_tc"
	var global_test_dir = ProjectSettings.globalize_path(test_dir)
	var prev_appdata = OS.get_environment("APPDATA")
	OS.set_environment("APPDATA", global_test_dir)

	DirAccess.make_dir_recursive_absolute(global_test_dir)

	# Test offline flag init logic
	var prev_offline = OS.get_environment("CEDO_OFFLINE")
	OS.set_environment("CEDO_OFFLINE", "1")
	var tc1 = load("res://src/autoload/TextureCache.gd").new()
	root.add_child(tc1)
	_ok(tc1._offline == true, "CEDO_OFFLINE=1 sets _offline to true")
	tc1.free()

	OS.set_environment("CEDO_OFFLINE", "0")
	var tc2 = load("res://src/autoload/TextureCache.gd").new()
	root.add_child(tc2)
	_ok(tc2._offline == false, "CEDO_OFFLINE=0 sets _offline to false")

	# Verify cache directory setup
	var expected_cache_dir = global_test_dir.replace("\\", "/") + "/SharedTextures/polyhaven/"
	_ok(tc2._cache_dir == expected_cache_dir, "Cache directory is correctly set up from APPDATA")
	_ok(DirAccess.dir_exists_absolute(expected_cache_dir), "Cache directory is created recursively")

	# Setup a mock asset with dummy files
	var asset_id = "test_asset"
	var res = "2k"
	var img = Image.create(1, 1, false, Image.FORMAT_RGBA8)

	for role in ["albedo", "normal", "roughness"]:
		var path = tc2._map_path(asset_id, res, role)
		var err = img.save_png(path)
		_ok(err == OK, "Created mock cache map " + path)

	var signal_state = {"called": false, "maps": {}}
	var cb = func(emitted_id, maps):
		if emitted_id == asset_id:
			signal_state["called"] = true
			signal_state["maps"] = maps

	tc2.pbr_set_ready.connect(cb)

	# Request it and see if it loads from disk immediately without HTTPRequest
	tc2.request_pbr_set(asset_id, res)

	_ok(signal_state["called"], "pbr_set_ready was emitted for cached asset")
	_ok(signal_state["maps"].size() == 3, "All 3 maps were loaded")
	if signal_state["maps"].size() == 3:
		_ok(signal_state["maps"]["albedo"] is ImageTexture, "Albedo is an ImageTexture")
		_ok(signal_state["maps"]["normal"] is ImageTexture, "Normal is an ImageTexture")
		_ok(signal_state["maps"]["roughness"] is ImageTexture, "Roughness is an ImageTexture")

	_ok(tc2.get_child_count() == 0, "No HTTPRequest was spawned for fully cached asset")

	# Test Idempotency
	signal_state["called"] = false
	tc2.request_pbr_set(asset_id, res)
	_ok(signal_state["called"], "pbr_set_ready was re-emitted immediately on second request")

	# Check the manifest was updated correctly
	var manifest = tc2._manifest
	_ok(manifest.has(asset_id), "Manifest contains the asset")
	if manifest.has(asset_id):
		var entry = manifest[asset_id]
		_ok(entry.has("first_fetched"), "Manifest entry has first_fetched")
		_ok(entry.has("resolutions"), "Manifest entry has resolutions")
		_ok((entry["resolutions"] as Array).has(res), "Manifest entry resolution array contains " + res)

	# Check corrupted file behavior
	# If a file is not a valid png, it should be deleted
	var bad_path = tc2._map_path("bad_asset", res, "albedo")
	var file = FileAccess.open(bad_path, FileAccess.WRITE)
	file.store_string("this is not a valid png")
	file.close()

	tc2.request_pbr_set("bad_asset", res)
	_ok(not FileAccess.file_exists(bad_path), "Corrupted cache entry was deleted")

	# Clean up
	tc2.free()

	# Delete all test files
	var d = DirAccess.open(expected_cache_dir)
	if d:
		d.list_dir_begin()
		var f_name = d.get_next()
		while f_name != "":
			if not d.current_is_dir():
				d.remove(f_name)
			f_name = d.get_next()

	DirAccess.remove_absolute(expected_cache_dir)
	var parent_dir = expected_cache_dir.get_base_dir()
	DirAccess.remove_absolute(parent_dir)
	var tc_dir = parent_dir.get_base_dir()
	DirAccess.remove_absolute(tc_dir)

	OS.set_environment("APPDATA", prev_appdata)
	if prev_offline != "":
		OS.set_environment("CEDO_OFFLINE", prev_offline)

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
