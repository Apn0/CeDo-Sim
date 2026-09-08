extends SceneTree

var _fail := 0
var _pass := 0

func _init() -> void:
    print("=== SettingsManager pending_keybinds verification ===")
    call_deferred("_run_tests")

func _run_tests() -> void:
    var SettingsManagerScript = load("res://src/autoload/SettingsManager.gd")
    var sm = SettingsManagerScript.new()

    # SettingsManager requires `_sync_pending_from_current` to populate `_pending_keybinds`
    # since `_ready()` isn't automatically called. However `_current_keybinds` is empty initially
    # before `_ready()` anyway, but we still call the sync to mirror real behaviour.
    sm._sync_pending_from_current()

    # 1. Test initial state
    _ok(sm.pending_keybinds() != null, "pending_keybinds returns a dictionary")

    # 2. Test setting a pending keybind
    var mock_events1: Array = [InputEventKey.new()]
    sm.set_pending_keybind("move_forward", mock_events1)

    var pending = sm.pending_keybinds()
    _ok(pending.has("move_forward"), "pending_keybinds has the set action")
    _ok(pending["move_forward"] == mock_events1, "pending_keybinds reflects the set events array")

    # 3. Test that setting multiple keybinds works and retains previous
    var mock_events2: Array = [InputEventMouseButton.new()]
    sm.set_pending_keybind("jump", mock_events2)

    pending = sm.pending_keybinds()
    _ok(pending.has("move_forward"), "pending_keybinds retains previous actions")
    _ok(pending["move_forward"] == mock_events1, "pending_keybinds previous action data is intact")

    _ok(pending.has("jump"), "pending_keybinds has the new action")
    _ok(pending["jump"] == mock_events2, "pending_keybinds new action data is intact")

    # 4. Test that setting the same keybind overwrites
    var mock_events3: Array = [InputEventJoypadButton.new()]
    sm.set_pending_keybind("move_forward", mock_events3)

    pending = sm.pending_keybinds()
    _ok(pending.has("move_forward"), "pending_keybinds retains action after overwrite")
    _ok(pending["move_forward"] == mock_events3, "pending_keybinds has overwritten data")

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
