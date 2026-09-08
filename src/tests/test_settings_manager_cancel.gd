extends SceneTree

var _fail := 0
var _pass := 0

func _init() -> void:
    print("=== SettingsManager cancel verification ===")
    call_deferred("_run_tests")

func _run_tests() -> void:
    var SettingsManagerScript = load("res://src/autoload/SettingsManager.gd")
    var sm = SettingsManagerScript.new()

    sm._current_graphics = {"fov": 75.0, "display_mode": "windowed"}
    sm._pending_graphics = {"fov": 75.0, "display_mode": "windowed"}

    sm._current_audio = {"master_db": 0.0, "ui_db": -3.0}
    sm._pending_audio = {"master_db": 0.0, "ui_db": -3.0}

    sm._current_gameplay = {"mouse_sensitivity_x": 0.003, "head_bob": true}
    sm._pending_gameplay = {"mouse_sensitivity_x": 0.003, "head_bob": true}

    sm._current_keybinds = {"jump": []}
    sm._pending_keybinds = {"jump": []}

    # 1. Modify pending states
    sm.set_pending("graphics", "fov", 90.0)
    sm.set_pending("audio", "master_db", -5.0)
    sm.set_pending("gameplay", "head_bob", false)
    sm.set_pending_keybind("jump", [InputEventKey.new()])

    _ok(sm.pending_graphics().get("fov") == 90.0, "Pending graphics is updated")
    _ok(sm.graphics().get("fov") == 75.0, "Current graphics is unchanged")

    _ok(sm.pending_audio().get("master_db") == -5.0, "Pending audio is updated")
    _ok(sm.audio().get("master_db") == 0.0, "Current audio is unchanged")

    _ok(sm.pending_gameplay().get("head_bob") == false, "Pending gameplay is updated")
    _ok(sm.gameplay().get("head_bob") == true, "Current gameplay is unchanged")

    _ok(sm.pending_keybinds().get("jump").size() == 1, "Pending keybinds is updated")
    _ok(sm.keybinds().get("jump").size() == 0, "Current keybinds is unchanged")

    # 2. Cancel
    sm.cancel()

    # 3. Verify pending states are reset
    _ok(sm.pending_graphics().get("fov") == 75.0, "Pending graphics is reverted after cancel")
    _ok(sm.graphics().get("fov") == 75.0, "Current graphics is still unchanged")

    _ok(sm.pending_audio().get("master_db") == 0.0, "Pending audio is reverted after cancel")
    _ok(sm.audio().get("master_db") == 0.0, "Current audio is still unchanged")

    _ok(sm.pending_gameplay().get("head_bob") == true, "Pending gameplay is reverted after cancel")
    _ok(sm.gameplay().get("head_bob") == true, "Current gameplay is still unchanged")

    _ok(sm.pending_keybinds().get("jump").size() == 0, "Pending keybinds is reverted after cancel")
    _ok(sm.keybinds().get("jump").size() == 0, "Current keybinds is still unchanged")

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
