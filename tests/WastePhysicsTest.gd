extends Node3D

## #154 (chute spill → pile + shovel + place-to-catch) and #159 (solid piles).
##
##   [159] A FloorPile carries a REAL collider that grows with the heap, so the
##         player / vehicles can't walk or drive through it.
##   [154a] An uncaught chute reject SPAWNS a floor pile right under the chute.
##   [154b] Park a container under the chute and it CATCHES the reject instead —
##          no new pile forms.
##   [154c] The shovel scoops a heap a shovelful at a time into a nearby bin.

const LineFlowScript       = preload("res://src/sim/LineFlow.gd")
const FloorPileScript      = preload("res://src/sim/FloorPile.gd")
const WasteContainerScript = preload("res://src/sim/WasteContainer.gd")
const ShovelToolScript     = preload("res://src/scenes/world/ShovelTool.gd")
const MaterialBatchScript  = preload("res://src/sim/MaterialBatch.gd")

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	print("=== #154 / #159  WASTE PHYSICS ===")
	_test_pile_collision()
	_test_chute_spill()
	_test_container_catches()
	_test_shovel()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

# ── [159] FloorPile gets a real, growing collider ─────────────────────────────
func _test_pile_collision() -> void:
	print("[159] floor pile is a SOLID collider that grows with the heap")
	var pile = FloorPileScript.new()
	add_child(pile)
	pile.global_position = Vector3(-500.0, 0.0, 0.0)   # well away from the other tests
	_ok(pile.get_node_or_null("PileBody") is StaticBody3D, "pile has a StaticBody collider")
	# Empty pile → collider disabled (no phantom obstacle).
	_ok(pile._col != null and pile._col.disabled, "empty pile collider is disabled")
	pile.add(400.0, 200.0)
	_ok(not pile._col.disabled, "filled pile collider is ENABLED (solid)")
	var shp := pile._cshape as CylinderShape3D
	_ok(shp != null and shp.radius > 0.3 and shp.height > 0.1,
		"collider grew to the heap (r=%.2f h=%.2f)" % [shp.radius, shp.height])
	var r_small := shp.radius
	pile.add(2000.0, 200.0)
	_ok(shp.radius > r_small, "collider radius grows with more mass (%.2f → %.2f)" % [r_small, shp.radius])

# ── [154a] Uncaught chute reject spawns a floor pile ──────────────────────────
func _test_chute_spill() -> void:
	print("[154a] an uncaught chute reject heaps up on the floor")
	var lf = LineFlowScript.new()
	add_child(lf)
	var spill_at := Vector3(500.0, 2.0, 500.0)   # nothing within 40 m to catch it
	var before := get_tree().get_nodes_in_group("floor_pile").size()
	var w = MaterialBatchScript.new(60.0, 0.04, {"dirt": 1.0}, "reject", 0.0, 60.0)
	lf._dump_waste(spill_at, w, get_tree().get_nodes_in_group("waste_container"), 2)   # DIRT
	var piles := get_tree().get_nodes_in_group("floor_pile")
	_ok(piles.size() == before + 1, "a new floor pile spawned under the chute (%d → %d)" % [before, piles.size()])
	# The new pile is the one near the spill point.
	var got := 0.0
	for p in piles:
		if (p as Node3D).global_position.distance_to(Vector3(500.0, 0.0, 500.0)) < 5.0:
			got = float(p.get("mass_kg"))
	_ok(got > 0.0, "the reject mass landed on the new pile (%.1f kg)" % got)
	lf.queue_free()

# ── [154b] A container parked under the chute catches it instead ──────────────
func _test_container_catches() -> void:
	print("[154b] park a container under the chute → it catches the reject")
	var lf = LineFlowScript.new()
	add_child(lf)
	var bin = WasteContainerScript.new()
	bin.capacity_m3 = 5.0           # accepted_streams defaults to an empty catch-all
	add_child(bin)
	bin.global_position = Vector3(200.0, 0.0, 0.0)
	var before := get_tree().get_nodes_in_group("floor_pile").size()
	var w = MaterialBatchScript.new(60.0, 0.04, {"dirt": 1.0}, "reject", 0.0, 60.0)
	lf._dump_waste(Vector3(200.0, 2.0, 0.0), w, get_tree().get_nodes_in_group("waste_container"), 2)
	_ok(bin.mass_kg + bin.overflow_mass_kg > 0.0,
		"the container caught the reject (%.1f kg)" % (bin.mass_kg + bin.overflow_mass_kg))
	_ok(get_tree().get_nodes_in_group("floor_pile").size() == before,
		"no new floor pile formed (the chute was caught)")
	bin.queue_free()
	lf.queue_free()

# ── [154c] The shovel scoops a heap into a nearby bin ─────────────────────────
func _test_shovel() -> void:
	print("[154c] the shovel scoops a floor heap into a nearby container")
	var pile = FloorPileScript.new()
	add_child(pile)
	pile.global_position = Vector3(300.0, 0.0, 0.0)
	pile.add(120.0, 200.0)
	var bin = WasteContainerScript.new()
	bin.capacity_m3 = 3.0
	add_child(bin)
	bin.global_position = Vector3(301.0, 0.0, 0.0)
	var shovel = ShovelToolScript.new()
	add_child(shovel)
	shovel.global_position = Vector3(300.0, 0.0, 0.0)
	var pile_before : float = pile.mass_kg
	var bin_before : float = bin.mass_kg + bin.overflow_mass_kg
	var moved : float = shovel.scoop_once()
	_ok(moved > 0.0, "a scoop lifted material (%.1f kg)" % moved)
	_ok(pile.mass_kg < pile_before, "the heap shrank (%.1f → %.1f kg)" % [pile_before, pile.mass_kg])
	_ok(bin.mass_kg + bin.overflow_mass_kg > bin_before,
		"the container gained the scoop (%.1f → %.1f kg)" % [bin_before, bin.mass_kg + bin.overflow_mass_kg])
