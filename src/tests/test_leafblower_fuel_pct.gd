extends SceneTree

var _fails := 0
func _ok(cond: bool, msg: String) -> void:
    if cond:
        print("  ok  : ", msg)
    else:
        print(" FAIL : ", msg)
        _fails += 1

func _init() -> void:
    call_deferred("_run_tests")

func _run_tests() -> void:
    print("=== LeafBlower Tests ===")

    var blower = preload("res://src/operator/LeafBlower.gd").new()

    blower.fuel_capacity_l = 10.0
    blower.fuel_l = 10.0
    _ok(blower.fuel_pct() == 1.0, "fuel_pct is 1.0 when full")

    blower.fuel_l = 5.0
    _ok(blower.fuel_pct() == 0.5, "fuel_pct is 0.5 when half full")

    blower.fuel_l = 0.0
    _ok(blower.fuel_pct() == 0.0, "fuel_pct is 0.0 when empty")

    blower.fuel_l = 12.0
    _ok(blower.fuel_pct() == 1.0, "fuel_pct is clamped to 1.0")

    blower.fuel_l = -1.0
    _ok(blower.fuel_pct() == 0.0, "fuel_pct is clamped to 0.0")

    blower.fuel_capacity_l = 0.0
    blower.fuel_l = 10.0
    _ok(blower.fuel_pct() == 0.0, "fuel_pct is 0.0 when capacity is 0.0")

    blower.fuel_capacity_l = -1.0
    _ok(blower.fuel_pct() == 0.0, "fuel_pct is 0.0 when capacity is negative")

    blower.free()

    if _fails == 0:
        print("PASS")
    else:
        print("FAIL (", _fails, " failures)")

    quit(_fails)
