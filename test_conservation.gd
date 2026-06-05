extends SceneTree
## Headless conservation harness for the wet/dirty material model (Wave 1).
##
## Runs a representative LDPE wash+dry+sort+extrude train ONE machine at a time,
## mirroring LineFlow's per-node order exactly, and asserts the master invariant:
##
##   fed + water_added == granulaat + waste + contam_removed
##                        + water_removed + poly_rejected + in_line
##
## Run:  godot --headless --script res://test_conservation.gd

var _fail := 0

func _init() -> void:
	print("=== Wave 1 conservation harness ===")
	_test_batch_primitives()
	_test_full_train()
	_test_bale_feed_samples()
	_test_new_models()
	if _fail == 0:
		print("\nALL CONSERVATION CHECKS PASSED")
	else:
		print("\n%d CHECK(S) FAILED" % _fail)
	quit()

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok  : %s" % msg)
	else:
		print("  FAIL: %s" % msg)
		_fail += 1

func _approx(a: float, b: float, eps := 0.01) -> bool:
	return absf(a - b) <= eps

# -----------------------------------------------------------------------------
# 1) The MaterialBatch transforms each conserve mass against their side stream.
# -----------------------------------------------------------------------------
func _test_batch_primitives() -> void:
	print("\n[1] MaterialBatch primitives")

	# split_fraction halves carry water + dirt proportionally and re-sum exactly.
	var b := MaterialBatch.new(1000.0, 3.0, {"LDPE": 0.8, "HDPE": 0.075, "other": 0.125},
							   "test", 100.0, 120.0)
	var taken := b.split_fraction(0.25)
	_ok(_approx(taken.mass_kg + b.mass_kg, 1000.0), "split_fraction conserves mass (%.2f+%.2f)" % [taken.mass_kg, b.mass_kg])
	_ok(_approx(taken.water_kg + b.water_kg, 100.0), "split_fraction conserves water")
	_ok(_approx(taken.contaminant_kg + b.contaminant_kg, 120.0), "split_fraction conserves dirt")

	# remove_water returns exactly what it took off the batch.
	var d := MaterialBatch.new(500.0, 1.5, {"LDPE": 1.0}, "wet", 200.0, 0.0)
	var before := d.mass_kg
	var removed := d.remove_water(0.7)
	_ok(_approx(removed, 140.0), "remove_water(0.7) of 200 -> 140 (%.2f)" % removed)
	_ok(_approx(before - d.mass_kg, removed), "remove_water mass drop == returned")
	_ok(_approx(d.water_kg, 60.0), "remove_water leaves 60 kg water (%.2f)" % d.water_kg)

	# remove_contaminant likewise.
	var e := MaterialBatch.new(500.0, 1.5, {"LDPE": 1.0}, "dirty", 0.0, 100.0)
	var bm := e.mass_kg
	var dc := e.remove_contaminant(0.5)
	_ok(_approx(dc, 50.0), "remove_contaminant(0.5) of 100 -> 50 (%.2f)" % dc)
	_ok(_approx(bm - e.mass_kg, dc), "remove_contaminant mass drop == returned")

	# add_water raises mass by exactly the water poured in.
	var f := MaterialBatch.new(500.0, 1.5, {"LDPE": 1.0}, "dry", 0.0, 0.0)
	f.add_water(80.0)
	_ok(_approx(f.mass_kg, 580.0), "add_water(80) -> 580 (%.2f)" % f.mass_kg)
	_ok(_approx(f.water_kg, 80.0), "add_water tracks 80 kg water")

	# reject_polymer kicks out off-spec and renormalises the surviving mix.
	var g := MaterialBatch.new(1000.0, 3.0, {"LDPE": 0.8, "HDPE": 0.075, "other": 0.125},
							   "mix", 0.0, 0.0)
	var rej := g.reject_polymer("other", 1.0)   # eject ALL "other"
	_ok(_approx(rej, 125.0), "reject_polymer all 'other' of 125 -> 125 (%.2f)" % rej)
	_ok(_approx(g.fraction_of("other"), 0.0), "reject_polymer zeroes 'other'")
	_ok(_approx(g.fraction_of("LDPE") + g.fraction_of("HDPE"), 1.0), "reject_polymer renormalises survivors")

# -----------------------------------------------------------------------------
# 2) A full plant train, processed node by node with LineFlow's exact ordering,
#    must keep the master ledger balanced to ~0.
# -----------------------------------------------------------------------------
func _test_full_train() -> void:
	print("\n[2] Full wash+dry+sort+extrude train ledger")

	var fed_mass := 0.0
	var water_added := 0.0
	var water_removed := 0.0
	var contam_removed := 0.0
	var poly_rejected := 0.0
	var waste_mass := 0.0
	var gran_mass := 0.0

	# Feed 1000 kg of Rotterdam film (wet + dirty) into the head.
	var flow := BaleDefs.feed_sample("rotterdam", 1000.0)
	fed_mass += flow.mass_kg
	print("  feed: %s" % flow)

	# The real order of a CeDo-style line — full sorting + wash + dry + extrude.
	var train := [
		"bunker", "sga_drum", "metal_belt", "ballistic_sep", "wind_sifter", "titech_sort",
		"shredder_1", "shredder_2", "inclined_belt_8m", "feed_hopper",
		"prewash_drum", "friction_washer", "intensive_washer", "flotation_tank", "rotation_tank",
		"kufferath_sieve", "rafter", "dewater_screw", "mech_dryer", "centrifuge",
		"mengsilo", "mas_bak", "compactor", "extruder_1",
	]
	for id in train:
		var pr := MachineFlow.profile(id)
		# a) contaminant stripped
		var cr := float(pr["contam_remove"])
		if cr > 0.0:
			contam_removed += flow.remove_contaminant(cr)
		# b) off-spec polymer rejected
		var ro := float(pr["reject_other"])
		if ro > 0.0:
			poly_rejected += flow.reject_polymer("other", ro)
		var rh := float(pr["reject_hdpe"])
		if rh > 0.0:
			poly_rejected += flow.reject_polymer("HDPE", rh)
		# c) drying
		var wr := float(pr["water_remove"])
		if wr > 0.0:
			water_removed += flow.remove_water(wr)
		# d) washing
		var wa := float(pr["water_add"])
		if wa > 0.0:
			var added := flow.polymer_kg() * wa
			flow.add_water(added)
			water_added += added
		# e) mechanical yield loss
		var wf := float(pr["waste"])
		if wf > 0.0:
			var w := flow.split_fraction(wf)
			waste_mass += w.mass_kg
		# f) sink banks granulaat
		if String(pr["role"]) == "sink":
			gran_mass += flow.mass_kg
			print("  %-16s -> granulaat %.1f kg  quality %.0f/100  (moisture %.1f%%, dirt %.2f%%, LDPE %.1f%%)" \
				% [id, flow.mass_kg, flow.quality_grade(), flow.moisture_pct(), flow.contam_pct(), flow.ldpe_fraction() * 100.0])
			flow = MaterialBatch.new()
		else:
			print("  %-16s -> %.1f kg  (H2O %.1f%%, dirt %.2f%%)" \
				% [id, flow.mass_kg, flow.moisture_pct(), flow.contam_pct()])

	var in_line := flow.mass_kg
	var residual := fed_mass + water_added \
		- gran_mass - waste_mass - contam_removed - water_removed - poly_rejected - in_line
	print("  --- ledger ---")
	print("  fed %.1f  +H2O %.1f  | gran %.1f  waste %.1f  dirt %.1f  H2O- %.1f  rejP %.1f  inLine %.1f" \
		% [fed_mass, water_added, gran_mass, waste_mass, contam_removed, water_removed, poly_rejected, in_line])
	_ok(_approx(residual, 0.0, 0.05), "master ledger balances (residual %.4f kg)" % residual)
	_ok(gran_mass > 0.0, "train actually produced granulaat (%.1f kg)" % gran_mass)

# -----------------------------------------------------------------------------
# 3) Every bale origin yields a wet, dirty, mostly-LDPE feed sample.
# -----------------------------------------------------------------------------
func _test_bale_feed_samples() -> void:
	print("\n[3] Bale feed samples are wet + dirty")
	for o in BaleDefs.origins():
		var s := BaleDefs.feed_sample(String(o["id"]), 100.0)
		var wet := s.moisture_pct() > 0.0
		var dirty := s.contam_pct() > 0.0
		var ldpe := s.ldpe_fraction()
		_ok(wet and dirty and ldpe > 0.4,
			"%-10s: %.0f kg  moisture %.1f%%  dirt %.1f%%  LDPE %.0f%%" \
			% [o["id"], s.mass_kg, s.moisture_pct(), s.contam_pct(), ldpe * 100.0])

# -----------------------------------------------------------------------------
# 4) Every new Wave-2 machine model builds headless without error and produces a
#    non-empty Node3D (this also parse-checks PlaceableCatalog end to end).
# -----------------------------------------------------------------------------
func _test_new_models() -> void:
	print("\n[4] Wave 2 machine models build headless")
	var ids := ["sga_drum", "metal_belt", "ballistic_sep", "wind_sifter",
		"titech_sort", "prewash_drum", "kufferath_sieve", "mengsilo", "zss_water"]
	for id in ids:
		var item := PlaceableCatalog.get_item(id)
		var node := PlaceableCatalog.build_node(id, false) as Node3D
		var parts := (node.get_child_count() if node else 0)
		_ok(not item.is_empty() and node != null and parts > 0,
			"%-16s builds (%d parts)" % [id, parts])
		if node:
			node.free()
