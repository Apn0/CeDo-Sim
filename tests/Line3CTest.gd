extends Node3D

## Headless test for Line 3C (#144): the definition matches the plant HMI order,
## every stage's model builds, and feed is gated to the head (Doseer Silo) so
## material can't be injected straight into the extruder train.

const Def = preload("res://src/sim/Line3CDef.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	_test_order()
	_test_every_stage_builds()
	_test_intake_gate()
	_test_topology()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _test_order() -> void:
	print("[1] definition matches the HMI machine order")
	var expected := [
		"L3C.1", "L3C.3", "L3C.4L", "L3C.4R", "L3C.5L", "L3C.5R", "L3C.6",
		"L3C.9L", "L3C.9R", "L3C.10L", "L3C.10R", "L3C.11", "L3C.12", "L3C.13",
		"L3C.14L", "L3C.14R", "L3C.15", "L3C.16", "L3C.18", "L3C.19",
		"Cband", "PCU", "Extr", "Laser", "Degas", "Melt",
		"Kop", "Heet", "Ontw", "Centr", "Weeg", "Voorraad",
	]
	_ok(Def.STAGES.size() == expected.size(), "stage count = %d (got %d)" % [expected.size(), Def.STAGES.size()])
	var ok_order := true
	for i in min(expected.size(), Def.STAGES.size()):
		if String(Def.STAGES[i]["code"]) != expected[i]:
			ok_order = false
			print("    order mismatch at %d: %s != %s" % [i, Def.STAGES[i]["code"], expected[i]])
	_ok(ok_order, "every stage code is in the exact HMI order")
	_ok(String(Def.STAGES[0]["id"]) == "doseersilo", "head is the Doseer Silo (horizontal half-pipe dosing-bin model)")
	_ok(String(Def.STAGES[6]["name"]) == "Maalmolen", "L3C.6 is the Maalmolen (mill)")
	_ok(String(Def.STAGES[11]["name"]) == "Flotatietank", "L3C.11 is the Flotatietank")
	_ok(String(Def.STAGES[Def.order_of("PCU")]["id"]) == "compactor",
		"PCU is the compactor model, not an extruder box (operator)")
	_ok(String(Def.STAGES[Def.order_of("Extr")]["id"]) == "extruder_screw",
		"Extruder is its own stage (HMI: 138 rpm / 187 kW), between PCU and Laserfilter")
	_ok(Def.order_of("Extr") > Def.order_of("PCU") and Def.order_of("Laser") > Def.order_of("Extr"),
		"order: PCU (compactor) -> Extruder -> Laserfilter")
	_ok(String(Def.STAGES[Def.order_of("Laser")]["id"]) == "laser_filter",
		"Laserfilter is the big rotary disc unit (the HMI concentric circle), after the extruder")
	_ok(Def.order_of("Degas") > Def.order_of("Laser") and Def.order_of("Melt") > Def.order_of("Degas"),
		"TVEplus: vacuum degassing comes AFTER the Laserfilter, before the meltpump (filter-before-degas)")
	_ok(String(Def.STAGES[Def.order_of("Degas")]["id"]) == "vacuum_degas",
		"degassing is its own vacuum stage (not folded into the extruder)")

func _test_every_stage_builds() -> void:
	print("[2] every stage's catalog model builds")
	var all_built := true
	var missing := ""
	for st in Def.STAGES:
		var n := PlaceableCatalog.build_node(String(st["id"]), false) as Node3D
		if n == null:
			all_built = false
			missing += " " + String(st["id"])
		else:
			add_child(n)
			n.queue_free()
	_ok(all_built, "all 32 stage models build%s" % ("" if all_built else " — missing:" + missing))

func _test_intake_gate() -> void:
	print("[3] feed gated to the head; extruder train is the tail")
	_ok(Def.is_intake("L3C.1"), "L3C.1 Doseer Silo is the intake")
	_ok(not Def.is_intake("L3C.18"), "Extruder Silo is NOT an intake")
	_ok(not Def.is_intake("PCU"), "extruder PCU is NOT an intake")
	_ok(Def.intake_code() == "L3C.1", "intake_code() = L3C.1")
	_ok(Def.tail_code() == "Voorraad", "tail_code() = Voorraad (granulate store)")
	# The extruder train must come strictly AFTER the flotation + dryers.
	_ok(Def.order_of("PCU") > Def.order_of("L3C.11"), "extruder after flotation")
	_ok(Def.order_of("L3C.18") > Def.order_of("L3C.14L"), "extruder silo after the dryers")
	_ok(Def.order_of("Heet") > Def.order_of("PCU") and Def.order_of("Voorraad") > Def.order_of("Heet"),
		"back-end order: compactor → … → heetafslag → … → voorraad silo")
	_ok(Def.order_of("Voorraad") == Def.STAGES.size() - 1, "voorraad silo is the very last stage")

func _test_topology() -> void:
	print("[4] flow topology: splits + merges defined + fully connected")
	var b3 := Def.out_links("L3C.3")
	_ok(b3.has("L3C.4L") and b3.has("L3C.4R"), "L3C.3 SPLITS into 4L + 4R (parallel friction trains)")
	_ok(Def.out_links("L3C.5L").has("L3C.6") and Def.out_links("L3C.5R").has("L3C.6"),
		"5L + 5R MERGE at the Maalmolen")
	_ok(Def.out_links("L3C.13").has("L3C.14L") and Def.out_links("L3C.13").has("L3C.14R"),
		"L3C.13 SPLITS into the L/R dryers")
	var head : String = Def.intake_code()
	var tail : String = Def.tail_code()
	var targets := {}
	for l in Def.LINKS:
		targets[String(l[1])] = true
	var all_out_ok := true
	var all_in_ok := true
	for st in Def.STAGES:
		var c : String = String(st["code"])
		if c != tail and Def.out_links(c).is_empty():
			all_out_ok = false
			print("    no out-link from %s" % c)
		if c != head and not targets.has(c):
			all_in_ok = false
			print("    no in-link to %s" % c)
	_ok(all_out_ok, "every non-tail stage feeds something downstream")
	_ok(all_in_ok, "every non-head stage is fed from upstream")
