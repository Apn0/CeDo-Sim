extends SceneTree

var _fail := 0
var _pass := 0

func _init() -> void:
    print("=== SettingsManager pending_audio verification ===")
    call_deferred("_run_tests")

func _run_tests() -> void:
    # Need to load the script and instantiate it to test it properly without autoloads
    var SettingsManagerScript = load("res://src/autoload/SettingsManager.gd")
    var sm = SettingsManagerScript.new()

    # Check that pending_audio is populated correctly based on defaults
    # Since sm._ready() is not called automatically when instantiating via new()
    sm._sync_pending_from_current()

    # 1. Test initial state
    _ok(sm.pending_audio() != null, "pending_audio returns a dictionary")

    # 2. Test setting a pending value
    sm.set_pending("audio", "master_volume", 0.75)
    _ok(sm.pending_audio().get("master_volume") == 0.75, "pending_audio reflects set_pending")

    # 3. Test that getting pending_audio gives us the updated dictionary
    var audio_dict = sm.pending_audio()
    _ok(audio_dict.get("master_volume") == 0.75, "dictionary returned from pending_audio has the updated value")

    # 4. Test that setting multiple values works
    sm.set_pending("audio", "sfx_volume", 0.6)
    _ok(sm.pending_audio().get("master_volume") == 0.75, "pending_audio retains previous values")
    _ok(sm.pending_audio().get("sfx_volume") == 0.6, "pending_audio stores new values")

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
