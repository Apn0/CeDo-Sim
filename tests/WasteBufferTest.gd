extends Node3D
## Headless verification of the Wave 5 MVP waste-buffer slice:
##   • WasteContainer entity — capacity / blended density / overflow_state
##   • Stream routing — a FINES bin refuses COARSE_FILM
##   • Spillover — accepted volume splits between bin + overflow once full
##   • Forklift skip pickup + dump-zone empty
##
## Runs as a .tscn-based test (real main loop so autoloads + global classes load).

const FORKLIFT      := "res://src/scenes/vehicles/Forklift.tscn"
const _Container    := preload("res://src/sim/WasteContainer.gd")
const _FloorPile    := preload("res://src/sim/FloorPile.gd")

var _pass := 0
var _fail := 0
var _lines : Array[String] = []

func _ready() -> void:
	print("=== Wave 5 MVP: waste-buffer + skip dump test ===")
	_test_container_basic()
	_test_stream_routing()
	_test_overflow_transition()
	_test_skip_pickup_and_dump()
	_test_overflow_mound_visible()
	_test_floor_pile_cascade()
	_test_floor_pile_caps_at_max_radius()
	_test_ibc_valve_drains()
	_test_fill_gauge()
	print("\nRESULT: %d passed · %d failed" % [_pass, _fail])
	for l in _lines:
		print("  - " + l)
	get_tree().quit(0 if _fail == 0 else 1)

func _ok(c: bool, m: String) -> void:
	if c: _pass += 1
	else:
		_fail += 1
		_lines.append(m)
	print(("  ok  : " if c else "  FAIL: ") + m)

# -----------------------------------------------------------------------------
func _test_container_basic() -> void:
	print("\n[container basics]")
	var c : Node = _Container.new()
	add_child(c)
	c.capacity_m3 = 1.0
	c.override_density_kg_m3 = 100.0    # fixed 100 kg/m³ → 100 kg fills 1 m³
	_ok(c.fill_fraction() == 0.0, "empty bin reads 0%% fill")
	# Add 40 kg of 100 kg/m³ material → 0.4 m³ of 1 m³ = 40% fill
	var leftover : float = c.add(40.0, 100.0, -1)
	_ok(leftover == 0.0, "40 kg of 100 kg/m³ fits with no leftover")
	_ok(absf(c.fill_fraction() - 0.4) < 0.01,
		"fill_fraction = 40%% after 40 kg in 1 m³ × 100 kg/m³ (got %.2f)" % c.fill_fraction())
	_ok(c.overflow_state == _Container.OverflowState.NONE, "still NONE under safe_fill")
	# Push past safe_fill (default 0.85) → WARNING
	c.add(50.0, 100.0, -1)
	_ok(c.overflow_state == _Container.OverflowState.WARNING,
		"crosses safe_fill (90%%) → WARNING state")
	_ok(c.needs_emptying(), "needs_emptying() flips true past safe_fill")
	c.queue_free()

func _test_stream_routing() -> void:
	print("\n[stream routing — stream-specific bins refuse wrong stream]")
	var fines : Node = _Container.new()
	add_child(fines)
	fines.capacity_m3 = 1.0
	fines.override_density_kg_m3 = 180.0
	fines.accepted_streams = [1]   # Stream.FINES only
	# Dump 50 kg of COARSE_FILM (cls=0) into it → should be refused entirely
	var refused : float = fines.add(50.0, 90.0, 0)
	_ok(refused == 50.0, "FINES-only bin refuses 50 kg of COARSE_FILM (returned %.0f)" % refused)
	_ok(fines.mass_kg == 0.0, "refused mass is NOT added to the bin")
	# Same bin accepts FINES happily
	refused = fines.add(50.0, 180.0, 1)
	_ok(refused == 0.0, "FINES bin accepts a FINES batch")
	_ok(fines.mass_kg > 0.0, "FINES mass was added")
	fines.queue_free()

func _test_overflow_transition() -> void:
	print("\n[overflow — spillover splits across bin + ground]")
	var c : Node = _Container.new()
	add_child(c)
	c.capacity_m3 = 1.0
	c.override_density_kg_m3 = 100.0   # 1 m³ × 100 = 100 kg into the bin
	c.overflow_budget_m3 = 0.5          # +50 kg can spill before BLOCKED
	# Dump 130 kg in one shot → 100 should sit in bin, 30 should spill
	var refused : float = c.add(130.0, 100.0, -1)
	_ok(refused == 0.0, "130 kg fits within capacity + overflow budget (0 refused)")
	_ok(absf(c.mass_kg - 100.0) < 1.0,
		"bin saturates at capacity (~100 kg, got %.1f)" % c.mass_kg)
	_ok(c.overflow_mass_kg > 0.0,
		"spillover captured the remainder (%.1f kg on the floor)" % c.overflow_mass_kg)
	_ok(c.overflow_state == _Container.OverflowState.SPILLING,
		"overflow_state advances to SPILLING")
	# Push past the overflow budget too → BLOCKED + further mass refused
	refused = c.add(200.0, 100.0, -1)
	_ok(refused > 0.0, "more material is REFUSED once BLOCKED (returned %.0f kg)" % refused)
	_ok(c.overflow_state == _Container.OverflowState.BLOCKED, "overflow_state → BLOCKED")
	# Empty resets everything
	var dumped : float = c.empty()
	_ok(dumped > 0.0, "empty() returned the total mass that was in the bin + spillover")
	_ok(c.mass_kg == 0.0 and c.overflow_mass_kg == 0.0, "bin + spillover both zero after empty()")
	_ok(c.overflow_state == _Container.OverflowState.NONE, "state back to NONE")
	c.queue_free()

func _test_skip_pickup_and_dump() -> void:
	print("\n[forklift skip pickup + dump-zone empty]")
	# Spawn a forklift + a steel skip + a dump zone in a clean test scene.
	var v := (load(FORKLIFT) as PackedScene).instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3.ZERO
	var cp := v.get_node_or_null(v.get("carry_point_path")) as Node3D

	# Steel skip (a real waste_container placeable) at the carry point so it's
	# guaranteed within GRAB_RANGE of the forks.
	var skip := PlaceableCatalog.build_node("skip_steel", false) as Node3D
	add_child(skip)
	skip.global_position = cp.global_position + Vector3(0.1, 0.0, 0.0)
	skip.set("accepted_streams", [0])    # COARSE_FILM
	skip.set("capacity_m3", 2.0)
	# Seed it with some mass so we can verify "emptied" by checking it goes to 0.
	var refused : float = skip.call("add", 100.0, 90.0, 0)
	_ok(refused == 0.0, "100 kg seeded into the skip")
	_ok(skip.call("fill_fraction") > 0.0, "skip starts non-empty (%.2f)" % skip.call("fill_fraction"))

	# Grab — forklift's _try_grab should pick up the skip via the same path bales use.
	v.call("_try_grab")
	var carried = v.get("_carried_bale")
	_ok(carried == skip, "forklift _try_grab picked up the skip as carried object")

	# Dump zone — register a marker in the dump_zone group at the skip's current
	# carry-world position (so the test doesn't need to drive the forklift).
	var zone := Node3D.new()
	zone.add_to_group("dump_zone")
	add_child(zone)
	zone.global_position = cp.global_position

	# Release — the drop check should empty the skip because it's inside the zone.
	v.call("_release")
	_ok(v.get("_carried_bale") == null, "forklift released the skip")
	_ok(absf(float(skip.call("fill_fraction"))) < 0.01,
		"skip is empty after release inside the dump zone (fill=%.2f)" % skip.call("fill_fraction"))

	v.queue_free()
	skip.queue_free()
	zone.queue_free()

# -----------------------------------------------------------------------------
func _test_overflow_mound_visible() -> void:
	print("\n[overflow mound — cone grows from spillover_kg]")
	var c : Node = _Container.new()
	add_child(c)
	c.capacity_m3 = 1.0
	c.override_density_kg_m3 = 100.0
	c.overflow_budget_m3 = 1.0   # generous so spillover stays in the bin
	# Initially the mound mesh is invisible (no spillover yet).
	var mound: MeshInstance3D = c.get_node_or_null("OverflowMound") as MeshInstance3D
	_ok(mound != null, "OverflowMound child mesh exists")
	_ok(mound != null and not mound.visible, "mound starts invisible (no spillover yet)")
	# Push 150 kg → 100 in bin, 50 spilling → mound should become visible w/ size.
	c.add(150.0, 100.0, -1)
	_ok(c.overflow_mass_kg > 0.0, "spillover registered (%.1f kg)" % c.overflow_mass_kg)
	_ok(mound != null and mound.visible, "mound becomes visible after spillover")
	if mound != null:
		var cyl := mound.mesh as CylinderMesh
		_ok(cyl != null and cyl.bottom_radius > 0.01,
			"mound cone has a real radius (got %.2f m)" % (cyl.bottom_radius if cyl else 0.0))
		_ok(cyl != null and cyl.height > 0.01,
			"mound cone has a real height (got %.2f m)" % (cyl.height if cyl else 0.0))
	c.empty()
	_ok(mound != null and not mound.visible, "emptying hides the mound again")
	c.queue_free()

func _test_floor_pile_cascade() -> void:
	print("\n[floor pile — bin overflow cascades to nearest FloorPile]")
	var pile : Node = _FloorPile.new()
	add_child(pile)
	pile.global_position = Vector3.ZERO
	pile.max_radius_m = 4.0    # plenty of room for the test cascade
	# Bin sits 5 m away — pile is within 30 m search range.
	var c : Node = _Container.new()
	add_child(c)
	c.global_position = Vector3(5, 0, 0)
	c.capacity_m3 = 0.5
	c.override_density_kg_m3 = 100.0
	c.overflow_budget_m3 = 0.2
	# Push a LOT — 200 kg, only 0.7 m³ × 100 = 70 kg fits in bin+budget. 130 kg
	# should cascade to the floor pile.
	var refused : float = c.add(200.0, 100.0, -1)
	_ok(refused == 0.0, "200 kg fully placed (0 returned to caller after cascade)")
	_ok(pile.mass_kg > 0.0,
		"floor pile picked up the cascade (%.1f kg on the floor)" % pile.mass_kg)
	_ok(pile.mass_kg > 100.0 and pile.mass_kg < 160.0,
		"cascade mass is roughly what spilled past the bin (%.1f kg, expected ~130)" % pile.mass_kg)
	pile.clear()
	c.queue_free()
	pile.queue_free()

func _test_floor_pile_caps_at_max_radius() -> void:
	print("\n[floor pile — refuses excess past max_radius]")
	var pile : Node = _FloorPile.new()
	add_child(pile)
	pile.max_radius_m = 1.0
	pile.angle_repose = 33.0
	# Pile volume cap at r=1 m, angle 33°: V = (π × 1³ × tan33°)/3 ≈ 0.68 m³.
	# At density 100 kg/m³ that's ~68 kg.
	var refused : float = pile.add(200.0, 100.0)
	_ok(refused > 0.0, "pile refuses mass past its max_radius (%.1f kg refused)" % refused)
	_ok(pile.mass_kg <= 80.0, "accepted mass capped (%.1f kg, expected ≤ ~70)" % pile.mass_kg)
	pile.queue_free()

func _test_ibc_valve_drains() -> void:
	print("\n[IBC tote — empty() drains everything]")
	var ibc : Node = _Container.new()
	add_child(ibc)
	ibc.fluid_valve = true
	ibc.movable = false
	ibc.capacity_m3 = 1.0
	ibc.override_density_kg_m3 = 1000.0   # water
	ibc.add(600.0, 1000.0, -1)
	_ok(ibc.mass_kg > 0.0, "IBC accepts 600 kg of water (fill %.0f%%)"
		% (ibc.fill_fraction() * 100.0))
	var drained : float = ibc.empty()
	_ok(drained >= 599.0, "valve drains the full mass (%.0f kg out)" % drained)
	_ok(ibc.mass_kg == 0.0, "IBC reads 0 after valve drain")
	ibc.queue_free()

func _test_fill_gauge() -> void:
	print("\n[fill gauge — visible level + colour tracks fill]")
	var c : Node = _Container.new()
	add_child(c)
	c.capacity_m3 = 1.0
	c.override_density_kg_m3 = 100.0   # 100 kg = full
	_ok(c.get_node_or_null("FillGauge") != null, "gauge node built on the container")
	_ok(is_equal_approx(c.gauge_display_fraction(), 0.0), "empty bin → gauge at 0")
	c.add(50.0, 100.0, -1)
	_ok(absf(c.gauge_display_fraction() - 0.5) < 0.05, "half full → gauge ~0.5 (%.2f)" % c.gauge_display_fraction())
	c.add(60.0, 100.0, -1)   # now over capacity → spilling, gauge clamps at 1.0
	_ok(is_equal_approx(c.gauge_display_fraction(), 1.0), "over capacity → gauge clamps at 1.0")
	_ok(c.overflow_state >= 1, "over-capacity sets a warning/spill state (%d)" % c.overflow_state)
	c.queue_free()
