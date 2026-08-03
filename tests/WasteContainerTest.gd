extends SceneTree

const _Container := preload("res://src/sim/WasteContainer.gd")

var _pass: int = 0
var _fail: int = 0
var _fail_lines: Array = []

func _init() -> void:
	print("============================================================")
	print("  CeDo Simulator — WasteContainer headless test")
	print("============================================================")

	_test_add_and_empty()

	print("============================================================")
	print("  RESULT: %d passed · %d failed" % [_pass, _fail])
	if _fail > 0:
		for l in _fail_lines:
			print("  - " + l)

	quit(0 if _fail == 0 else 1)

func _ok(c: bool, m: String) -> void:
	if c:
		_pass += 1
	else:
		_fail += 1
		_fail_lines.append(m)
	print(("  ok  : " if c else "  FAIL: ") + m)

func _test_add_and_empty() -> void:
	print("\n[WasteContainer: add and empty logic]")
	var c := _Container.new()

	c.capacity_m3 = 1.0
	c.override_density_kg_m3 = 100.0
	c.overflow_budget_m3 = 0.5

	_ok(c.mass_kg == 0.0, "Starts with 0 mass")
	_ok(c.overflow_mass_kg == 0.0, "Starts with 0 overflow mass")

	# Add 60 kg (fits inside 100 kg capacity)
	var refused = c.add(60.0, 100.0, -1)
	_ok(refused == 0.0, "60 kg added, 0 refused")
	_ok(c.mass_kg == 60.0, "Bin mass is 60 kg")
	_ok(c.overflow_mass_kg == 0.0, "Overflow is 0 kg")

	# Add another 80 kg. Total 140 kg. Capacity 100 kg. Budget 50 kg.
	# Bin gets 40 kg (mass_kg -> 100). Overflow gets 40 kg (overflow_mass_kg -> 40).
	refused = c.add(80.0, 100.0, -1)
	_ok(refused == 0.0, "80 kg added, 0 refused (fits in budget)")
	_ok(c.mass_kg == 100.0, "Bin mass capped at 100 kg")
	_ok(c.overflow_mass_kg == 40.0, "Overflow mass has remaining 40 kg")

	# Empty the container
	var removed = c.empty()
	_ok(removed == 140.0, "Emptying returned the 140 kg total")
	_ok(c.mass_kg == 0.0, "Bin mass is 0 after empty")
	_ok(c.overflow_mass_kg == 0.0, "Overflow mass is 0 after empty")

	c.free()
