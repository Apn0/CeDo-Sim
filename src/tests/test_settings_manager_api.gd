extends SceneTree

const SettingsManager = preload("res://src/autoload/SettingsManager.gd")

var _fail := 0
var _pass := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _section(title: String) -> void:
	print("\n[%s]" % title)

func _initialize() -> void:
	print("=== SettingsManager API verification ===")

	var sm = SettingsManager.new()
	sm.name = "SettingsManager"
	# Need to load/init it so it gets its defaults
	# For Node, ready isn't called unless it's in tree.
	# But actually we are in SceneTree so we can add it to root.
	root.add_child(sm)

	# The setup creates defaults in ready via _load_from_disk() -> _ensure_aux_actions() -> _sync_pending_from_current()
	# Because we are in SceneTree, we should use call_deferred to do assertions to let the node's ready fire.
	call_deferred("_test_api", sm)

func _test_api(sm: Node) -> void:
	_section("Public API Getters")

	var graphics = sm.graphics()
	_ok(typeof(graphics) == TYPE_DICTIONARY, "graphics() returns a Dictionary")
	_ok(graphics.has("display_mode"), "graphics() has display_mode")
	_ok(graphics.has("fov"), "graphics() has fov")

	var audio = sm.audio()
	_ok(typeof(audio) == TYPE_DICTIONARY, "audio() returns a Dictionary")
	_ok(audio.has("master_db"), "audio() has master_db")

	var gameplay = sm.gameplay()
	_ok(typeof(gameplay) == TYPE_DICTIONARY, "gameplay() returns a Dictionary")
	_ok(gameplay.has("mouse_sensitivity_x"), "gameplay() has mouse_sensitivity_x")

	var keybinds = sm.keybinds()
	_ok(typeof(keybinds) == TYPE_DICTIONARY, "keybinds() returns a Dictionary")
	_ok(keybinds.has("menu_toggle"), "keybinds() has menu_toggle")

	_section("Pending API Getters")

	var p_graphics = sm.pending_graphics()
	_ok(typeof(p_graphics) == TYPE_DICTIONARY, "pending_graphics() returns a Dictionary")
	_ok(p_graphics.has("display_mode"), "pending_graphics() has display_mode")

	var p_audio = sm.pending_audio()
	_ok(typeof(p_audio) == TYPE_DICTIONARY, "pending_audio() returns a Dictionary")
	_ok(p_audio.has("master_db"), "pending_audio() has master_db")

	var p_gameplay = sm.pending_gameplay()
	_ok(typeof(p_gameplay) == TYPE_DICTIONARY, "pending_gameplay() returns a Dictionary")
	_ok(p_gameplay.has("mouse_sensitivity_x"), "pending_gameplay() has mouse_sensitivity_x")

	var p_keybinds = sm.pending_keybinds()
	_ok(typeof(p_keybinds) == TYPE_DICTIONARY, "pending_keybinds() returns a Dictionary")
	_ok(p_keybinds.has("menu_toggle"), "pending_keybinds() has menu_toggle")

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	quit(0 if _fail == 0 else 1)
