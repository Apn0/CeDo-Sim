extends SceneTree
## Proof the shovel conserves mass (operator 2026-07-16: "mass converted to
## nothing = physics violation"). With no bin nearby a scoop must remove NOTHING
## from the pile; with a bin, mass moves pile→bin with zero loss.
## Run: Godot_v4.6.3_console --headless --path <proj> --script res://test_shovel_conservation.gd

class MockPile extends Node3D:
	var mass_kg : float = 100.0
	func scoop(kg: float) -> float:
		var got : float = minf(kg, mass_kg)
		mass_kg -= got
		return got

class MockBin extends Node3D:
	var total : float = 0.0
	func add(kg: float, _dens: float, _lane: int) -> void:
		total += kg

var _ran := false

func _process(_d: float) -> bool:
	if _ran:
		return true
	_ran = true
	var root := get_root()
	var shovel = load("res://src/scenes/world/ShovelTool.gd").new()
	root.add_child(shovel)
	shovel.global_position = Vector3.ZERO
	var pile := MockPile.new()
	pile.add_to_group("floor_pile")
	root.add_child(pile)
	pile.global_position = Vector3(0.5, 0, 0)

	var fails := 0
	# Case 1: NO bin in reach → scoop must be refused, pile untouched.
	shovel._last_scoop = -10.0
	var r1 : float = shovel.scoop_once()
	if r1 == 0.0 and is_equal_approx(pile.mass_kg, 100.0):
		print("  OK  : no bin → scoop refused, pile still 100.0 kg (nothing deleted)")
	else:
		print("  FAIL: no bin but %.1f kg vanished from the pile (now %.1f)" % [r1, pile.mass_kg]); fails += 1

	# Case 2: bin in reach → mass moves pile→bin, conserved.
	var bin := MockBin.new()
	bin.add_to_group("waste_container")
	root.add_child(bin)
	bin.global_position = Vector3(1.0, 0, 0)
	shovel._last_scoop = -10.0
	var r2 : float = shovel.scoop_once()
	var moved_ok : bool = r2 > 0.0 and is_equal_approx(pile.mass_kg + bin.total, 100.0) and is_equal_approx(bin.total, r2)
	if moved_ok:
		print("  OK  : scooped %.1f kg pile→bin, total conserved (pile %.1f + bin %.1f = 100.0)" % [r2, pile.mass_kg, bin.total])
	else:
		print("  FAIL: not conserved — moved %.1f, pile %.1f, bin %.1f" % [r2, pile.mass_kg, bin.total]); fails += 1

	print("=== SHOVEL CONSERVATION TEST: %s ===" % ("PASS" if fails == 0 else "FAIL (%d)" % fails))
	quit(0 if fails == 0 else 1)
	return true
