extends SceneTree

var _fail := 0
var _ran := false

class MockScanLog extends Node:
    func entries() -> Array:
        return [
            {"time": "12:00", "batch": "B1", "item": "Baal1", "weight_kg": 500, "line": "L1", "by": "Op1"},
            {"time": "12:05", "batch": "B2", "item": "Baal2", "weight_kg": 600, "line": "L2", "by": "Op2"}
        ]
    func count() -> int:
        return 2
    func total_kg() -> float:
        return 1100.0

class MockEventBus extends Node:
    signal scanlog_changed

class MockMainWorld extends Node:
    var reset_called = false
    var restock_called = false
    func reset_yard_bales() -> int:
        reset_called = true
        return 5
    func restock_yard_bales() -> int:
        restock_called = true
        return 10

func _process(_delta: float) -> bool:
    if not _ran:
        _ran = true
        _run_tests()
    return true

func _run_tests():
    print("Testing ShiftLeaderTerminal...")

    var Terminal = load("res://src/scenes/hud/ShiftLeaderTerminal.gd")
    var term = Terminal.new()
    self.root.add_child(term)

    if term._built:
        print("FAIL: Terminal already built before open()")
        _fail += 1

    term.open()

    if not term._built:
        print("FAIL: Terminal not built on open()")
        _fail += 1

    if not term.visible:
        print("FAIL: Terminal not visible after open()")
        _fail += 1

    term.toggle()

    if term.visible:
        print("FAIL: Terminal still visible after toggle()")
        _fail += 1

    term.toggle()
    if not term.visible:
        print("FAIL: Terminal not visible after second toggle()")
        _fail += 1

    # Test setup with mocks
    var mock_bus = MockEventBus.new()
    var mock_slog = MockScanLog.new()
    self.root.add_child(mock_bus)
    self.root.add_child(mock_slog)

    term.setup(mock_bus, mock_slog)

    # Trigger refresh
    mock_bus.scanlog_changed.emit()

    if not term._foot:
        print("FAIL: _foot is null")
        _fail += 1
    elif not ("1100" in term._foot.text and "2" in term._foot.text):
        print("FAIL: _foot text incorrect after refresh, got: ", term._foot.text)
        _fail += 1

    # Test MainWorld interactions
    var mock_mw = MockMainWorld.new()
    self.root.add_child(mock_mw)
    self.current_scene = mock_mw

    term._on_reset_pressed()
    if not mock_mw.reset_called:
        print("FAIL: reset_yard_bales not called on MainWorld")
        _fail += 1
    if not "5" in term._foot.text:
        print("FAIL: _foot text not updated after reset, got: ", term._foot.text)
        _fail += 1

    term._on_restock_pressed()
    if not mock_mw.restock_called:
        print("FAIL: restock_yard_bales not called on MainWorld")
        _fail += 1
    if not "Bestelling" in term._foot.text:
        print("FAIL: _foot text not updated after restock, got: ", term._foot.text)
        _fail += 1

    term.free()
    mock_bus.free()
    mock_slog.free()
    mock_mw.free()

    print("Test finished. Failures: ", _fail)
    quit(_fail)
