extends SceneTree

var _fail := 0
var _pass := 0

func _init() -> void:
    print("=== SettingsManager apply verification ===")
    call_deferred("_run_tests")

func _run_tests() -> void:
    var SettingsManagerScript = load("res://src/autoload/SettingsManager.gd")
    var sm = SettingsManagerScript.new()
    root.add_child(sm)

    # Wait for _ready to finish naturally
    call_deferred("_test_apply", sm)

var _applied_emitted := false

func _on_settings_applied() -> void:
    _applied_emitted = true

func _test_apply(sm: Node) -> void:
    # 1. Ensure state matches defaults first
    var initial_audio = sm.audio()
    _ok(initial_audio.has("master_db"), "Initial audio has master_db")

    # 2. Modify pending state
    sm.set_pending("audio", "master_db", -15.0)

    # Track signal
    sm.settings_applied.connect(_on_settings_applied)

    # 3. Apply
    sm.apply()

    # 4. Verify that current state was updated
    var new_audio = sm.audio()
    _ok(new_audio.get("master_db") == -15.0, "Current audio updated after apply()")

    # 5. Verify that signal was emitted
    _ok(_applied_emitted, "settings_applied signal was emitted")

    # 6. Verify that it was saved to disk
    var cfg := ConfigFile.new()
    var load_err = cfg.load(sm.SAVE_PATH)
    _ok(load_err == OK, "Saved config file exists and is loadable")

    if load_err == OK:
        _ok(cfg.get_value("audio", "master_db") == -15.0, "Applied value was saved to disk")

    # Clean up to avoid side effects for other tests
    var dir = DirAccess.open("user://")
    if dir and dir.file_exists("settings.cfg"):
        dir.remove("settings.cfg")

    sm.free()

    print("\n=========================================")
    print("Result: %d ok, %d fail" % [_pass, _fail])
    print("=========================================")
    quit(0 if _fail == 0 else 1)

func _ok(cond: bool, msg: String) -> void:
    if cond:
        print("  ok   : %s" % msg)
        _pass += 1
    else:
        print("  FAIL : %s" % msg)
        _fail += 1
