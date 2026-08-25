extends SceneTree

func _init() -> void:
    print("=== KufferathsDryerScope Tests ===")
    var fails := 0

    var KufferathsDryerScope = preload("res://src/scenes/hud/scopes/KufferathsDryerScope.gd")

    # Test 1: Instantiation and default state
    var scope = KufferathsDryerScope.new()
    if scope._built:
        print("  FAIL  : _built should be false initially")
        fails += 1

    # Test 2: set_dryer_pair pads to exactly 2 elements
    scope.set_dryer_pair([])
    if scope._dryer_cycles.size() != 2:
        print("  FAIL  : set_dryer_pair([]) should pad to 2 elements, got %d" % scope._dryer_cycles.size())
        fails += 1
    if scope._dryer_cycles[0] != null or scope._dryer_cycles[1] != null:
        print("  FAIL  : padded elements should be null")
        fails += 1

    # Test 3: set_dryer_pair keeps only non-null up to passed, but pads
    var dummy1 = Object.new()
    scope.set_dryer_pair([dummy1, null])
    if scope._dryer_cycles.size() != 2:
        print("  FAIL  : set_dryer_pair size mismatch")
        fails += 1
    if scope._dryer_cycles[0] != dummy1 or scope._dryer_cycles[1] != null:
        print("  FAIL  : set_dryer_pair array contents incorrect")
        fails += 1

    if fails == 0:
        print("  ok    : KufferathsDryerScope initialization and set_dryer_pair logic correct")
    print("Result: %s" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))

    # Cleanup memory to prevent memory leak warnings
    dummy1.free()
    scope.free()

    quit(0 if fails == 0 else 1)
