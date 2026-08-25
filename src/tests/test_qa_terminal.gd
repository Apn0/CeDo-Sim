extends SceneTree

var _fail := 0
var _ran := false

class MockQaLab extends RefCounted:
    const SAMPLE_KG = 0.025

func _process(_delta: float) -> bool:
    if not _ran:
        _ran = true
        _run_tests()
    return true

func _run_tests():
    print("Testing QualityAnalysisTerminal...")

    # We must patch the script to avoid the QaLab compile error in headless mode.
    # While text replacement is typically frowned upon, Godot 4's headless runner
    # does not fully register class_names when invoked via --script. In particular,
    # QaLab relies on QaSpec and MaterialBatch which self-reference in headless
    # mode and fail to compile, creating a cascade that breaks any file containing
    # 'QaLab'. We use this patch specifically to isolate the UI component testing.
    var file = FileAccess.open("res://src/scenes/hud/QualityAnalysisTerminal.gd", FileAccess.READ)
    var text = file.get_as_text()
    file.close()

    text = text.replace("QaLab.SAMPLE_KG", "0.025")

    var TermClass = GDScript.new()
    TermClass.source_code = text
    TermClass.reload()

    var term = TermClass.new()
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

    # Check formatting methods
    var fmt = term._num(1.234, 2)
    if fmt != "1.23":
        print("FAIL: Number formatting failed, got " + fmt)
        _fail += 1

    fmt = term._num(NAN, 2)
    if fmt != "—":
        print("FAIL: NAN formatting failed, got " + fmt)
        _fail += 1

    var mmss = term._mmss(65.0)
    if mmss != "1:05":
        print("FAIL: MMSS formatting failed, got " + mmss)
        _fail += 1

    # Check colour mappings
    var c = term._verdict_colour("ACCEPT")
    if c != term.C_OK:
        print("FAIL: ACCEPT colour wrong")
        _fail += 1

    c = term._verdict_colour("REJECT")
    if c != term.C_BAD:
        print("FAIL: REJECT colour wrong")
        _fail += 1

    term.queue_free()

    print("Test finished. Failures: ", _fail)
    quit(_fail)
