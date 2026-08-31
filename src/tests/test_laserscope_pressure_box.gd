extends SceneTree
## Headless test for LaserFilterScope.PressureBox (inner class, LaserFilterScope.gd:538).
##
## 2026-08-31 review finding: "LaserFilterScope setup and update untested" —
## line 558 is PressureBox.setup(), not the outer scope (which has no setup/update).
## The outer class drives PressureBox exactly like this test does:
##   _build_pressure_box() -> PressureBox.new() + setup(label, color)   (line 332)
##   _refresh_readouts()   -> box.update(<bar value>)                    (line 401)
##
## Run: godot --headless --path . --script res://src/tests/test_laserscope_pressure_box.gd --quit-after 300
##
## Counted checks, not assert(): a failing assert() aborts before quit() so the
## harness HANGS instead of going red, and assert() compiles out of release builds.
##
## Headless note: the dummy rasterizer never fires CanvasItem draw callbacks, so
## the gauge's fill rect cannot be observed directly. The fill fraction is
## asserted from its two real inputs instead — the state update() stores
## (_value_bar) and the class's own display scale (PRESSURE_MAX_BAR) — through
## the same clampf the draw code uses. Band colours ARE observable: _band_color()
## is called directly at and beyond the documented alarm bounds.

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
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== LaserFilterScope.PressureBox Tests ===")

	var Scope = load("res://src/scenes/hud/scopes/LaserFilterScope.gd")
	var scope_loaded: bool = Scope != null
	_ok(scope_loaded, "LaserFilterScope.gd should load")
	if not scope_loaded:
		_finish()
		return
	var PBox = Scope.PressureBox
	var pbox_found: bool = PBox != null
	_ok(pbox_found, "PressureBox inner class should exist on LaserFilterScope")
	if not pbox_found:
		_finish()
		return

	# ── 1. setup() — mirrors _build_pressure_box(): new + setup, then tree entry.
	print("Test: setup() applies label, colour, sizing, stylebox")
	var label_color := Color(0.55, 0.85, 0.95, 1.0)
	var box = PBox.new()
	box.setup("MP < MF", label_color)
	root.add_child(box)

	_ok(box is PanelContainer, "PressureBox should be a PanelContainer")
	_ok(box.custom_minimum_size == Vector2(0, 86), "setup should set custom_minimum_size to (0, 86)")

	_ok(box.has_theme_stylebox_override("panel"), "setup should install a panel stylebox override")
	var sb = box.get_theme_stylebox("panel")
	var sb_flat: bool = sb is StyleBoxFlat
	_ok(sb_flat, "panel stylebox should be a StyleBoxFlat")
	_ok(sb_flat and sb.bg_color.is_equal_approx(PBox.C_TILE), "stylebox bg should be the tile colour")
	_ok(sb_flat and sb.border_color.is_equal_approx(PBox.C_TILE_EDGE), "stylebox border should be the tile edge colour")
	_ok(sb_flat and sb.get_border_width(SIDE_LEFT) == 1, "stylebox border width should be 1")
	_ok(sb_flat and sb.get_corner_radius(CORNER_TOP_LEFT) == 4, "stylebox corner radius should be 4")

	# Real Control tree: PanelContainer > MarginContainer > VBoxContainer > (HBox row, gauge).
	var one_child: bool = box.get_child_count() == 1
	_ok(one_child, "box should have exactly one child (the margin container)")
	_ok(one_child and box.get_child(0) is MarginContainer, "box child should be a MarginContainer")
	var col: Node = box.get_child(0).get_child(0) if (one_child and box.get_child(0).get_child_count() > 0) else null
	var col_ok: bool = col != null and col is VBoxContainer
	_ok(col_ok, "margin container should hold a VBoxContainer")
	_ok(col_ok and col.get_child_count() == 2, "column should hold 2 children (value row + gauge)")

	var label_ok: bool = box._label != null
	_ok(label_ok, "setup should create the label")
	_ok(label_ok and box._label.text == "MP < MF", "label text should be the setup() argument")
	_ok(label_ok and box._label.has_theme_color_override("font_color"), "label should have a font_color override")
	_ok(label_ok and box._label.get_theme_color("font_color").is_equal_approx(label_color), "label colour should be the setup() argument")
	_ok(label_ok and box._label.get_theme_font_size("font_size") == 13, "label font size should be 13")
	_ok(label_ok and box._label.is_inside_tree(), "label should actually be in the control tree")

	var value_ok: bool = box._value != null
	_ok(value_ok, "setup should create the value label")
	_ok(value_ok and box._value.text == "  0", "value label should start at '  0'")
	_ok(value_ok and box._value.horizontal_alignment == HORIZONTAL_ALIGNMENT_RIGHT, "value label should be right-aligned")
	_ok(value_ok and box._value.custom_minimum_size == Vector2(70, 0), "value label min width should be 70")

	var unit_ok: bool = box._unit != null
	_ok(unit_ok, "setup should create the unit label")
	_ok(unit_ok and box._unit.text == "bar", "unit label should read 'bar'")

	var gauge_ok: bool = box._gauge != null
	_ok(gauge_ok, "setup should create the gauge control")
	_ok(gauge_ok and box._gauge.custom_minimum_size == Vector2(0, 14), "gauge min height should be 14")
	_ok(gauge_ok and box._gauge.draw.is_connected(box._draw_gauge), "gauge draw should be wired to _draw_gauge")

	# ── 2. update() — value text formatting ("%4d" of the rounded bar value).
	print("Test: update() value text formatting")
	box.update(207.3)
	_ok(value_ok and box._value.text == " 207", "207.3 bar should render as ' 207' (rounded, width 4)")
	_ok(is_equal_approx(box._value_bar, 207.3), "update should store the raw bar value")
	box.update(0.0)
	_ok(value_ok and box._value.text == "   0", "0 bar should render as '   0'")
	box.update(1234.6)
	_ok(value_ok and box._value.text == "1235", "1234.6 bar should round up to '1235'")
	box.update(-12.0)
	_ok(value_ok and box._value.text == " -12", "negative bar should render as ' -12'")

	# ── 3. Gauge fill fraction — clamped 0..1 on the class's own display scale.
	# (Headless: draw never fires, so assert the fraction from update()'s stored
	# state through the same clampf(_value_bar / PRESSURE_MAX_BAR) the draw uses.)
	print("Test: gauge fill fraction clamps to 0..1")
	_ok(is_equal_approx(PBox.PRESSURE_MAX_BAR, 350.0), "gauge display scale should be 0-350 bar (photo axis)")
	box.update(175.0)
	var f_mid: float = clampf(box._value_bar / PBox.PRESSURE_MAX_BAR, 0.0, 1.0)
	_ok(absf(f_mid - 0.5) < 0.0001, "175 bar should fill half the 0-350 gauge")
	box.update(700.0)
	var f_over: float = clampf(box._value_bar / PBox.PRESSURE_MAX_BAR, 0.0, 1.0)
	_ok(is_equal_approx(f_over, 1.0), "700 bar (2x scale) should clamp the fill to 1.0")
	box.update(-25.0)
	var f_neg: float = clampf(box._value_bar / PBox.PRESSURE_MAX_BAR, 0.0, 1.0)
	_ok(is_equal_approx(f_neg, 0.0), "negative bar should clamp the fill to 0.0")

	# ── 4. Band colours at and beyond the documented alarm bounds.
	# #223 docs->code hmi_reference.md: green <=250, yellow 250-300, red >300
	# (approaching the 318-bar upstream trip). update() then _band_color(),
	# exactly the pair the draw path evaluates.
	print("Test: alarm band colours (green/yellow/red)")
	var GREEN  := Color(0.22, 0.78, 0.32, 1.0)
	var YELLOW := Color(0.95, 0.80, 0.15, 1.0)
	var RED    := Color(0.95, 0.30, 0.20, 1.0)
	box.update(0.0)
	_ok(box._band_color().is_equal_approx(GREEN), "0 bar should band green")
	box.update(207.0)
	_ok(box._band_color().is_equal_approx(GREEN), "207 bar (normal run) should band green")
	box.update(249.9)
	_ok(box._band_color().is_equal_approx(GREEN), "249.9 bar should still band green")
	box.update(250.0)
	_ok(box._band_color().is_equal_approx(YELLOW), "250 bar (green bound) should band yellow")
	box.update(299.9)
	_ok(box._band_color().is_equal_approx(YELLOW), "299.9 bar should still band yellow")
	box.update(300.0)
	_ok(box._band_color().is_equal_approx(RED), "300 bar (yellow bound) should band red")
	box.update(318.0)
	_ok(box._band_color().is_equal_approx(RED), "318 bar (upstream trip) should band red")
	box.update(700.0)
	_ok(box._band_color().is_equal_approx(RED), "beyond-scale pressure should band red")

	# ── 5. update() before setup() — null guards must hold (no crash).
	print("Test: update() before setup() is guarded")
	var bare = PBox.new()
	bare.update(50.0)
	_ok(is_equal_approx(bare._value_bar, 50.0), "bare update should still store the value without crashing")
	_ok(bare._value == null and bare._gauge == null, "bare box should have no label/gauge (guards were exercised)")

	# Cleanup — children free with their parents.
	root.remove_child(box)
	box.free()
	bare.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
