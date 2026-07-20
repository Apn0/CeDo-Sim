extends Node3D

# =============================================================================
# MASS-CONSERVATION LEDGER — operator issue C, 2026-07-20.
#
# Operator: a pile of fines forms at floor level "creating fines out of nothing,
# or from unshredded bales — which is also not possible". Both are impossible, so
# mass is being created. This test measures it instead of arguing about it.
#
# INSTRUMENT FIRST: this is a measurement harness, not a fix. It sums every kg
# accumulator that the bale->belt->shredder->pile path touches and compares the
# total against the bale's own starting weight.
#
# It is EXPECTED TO FAIL on the un-fixed code, and it fails for a specific,
# diagnosable reason rather than a vague delta:
#   * ShredderFeedBelt runs a DIMENSIONLESS ledger. `fill` and `rider["mass"]`
#     are 0..1, not kilograms (ShredderFeedBelt.gd:75, :632).
#   * accept_bale hard-codes `"mass": 1.0` (:632) — it never reads the bale's
#     weight_kg / remaining_kg / RigidBody3D.mass. A 700 kg bale and a 1 kg husk
#     enter identically.
#   * kilograms are MINTED once, in the wrong direction, from a made-up constant:
#     _emit_output(digested * OUTPUT_KG_PER_FILL) with OUTPUT_KG_PER_FILL = 350.0
#     (:788, :93), with nothing debited anywhere.
#
# NOT WIRED INTO run.sh until the fix lands — a permanently red harness teaches
# people to ignore red. Run it directly:
#   Godot --headless --path . src/tests/test_mass_ledger.tscn
# =============================================================================

const DT := 1.0 / 60.0
const TICKS := 900                      # 15 s of belt time
const BALE_KG := 420.0                  # a realistic LDPE film bale
const TOL_KG := 1.0

var _ok := 0
var _fail := 0

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	var belt = load("res://src/scenes/world/ShredderFeedBelt.gd").new()
	# require_shredder is forced FALSE on every catalog-built opzetband
	# (PlaceableCatalog.gd:5162), which disables the only interlock and lets the
	# belt digest with no shredder at all. Forcing it true here keeps the test
	# from passing vacuously on a path the real game never takes.
	belt.set("require_shredder", true)
	add_child(belt)
	(belt as Node3D).global_transform = Transform3D.IDENTITY

	var bale := Node3D.new()
	bale.set_meta("scanned", true)
	bale.set_meta("weight_kg", BALE_KG)
	bale.set_meta("remaining_kg", BALE_KG)
	bale.add_to_group("bale")
	add_child(bale)
	bale.global_transform = Transform3D.IDENTITY

	var start_kg := BALE_KG
	print("\n[mass ledger] start: one bale of %.1f kg" % start_kg)

	var accepted : bool = bool(belt.call("accept_bale", bale, 0))
	print("  accept_bale -> %s" % str(accepted))
	_check(accepted, "the belt accepted the bale (otherwise nothing is measured)")

	# Deterministic ticking: the belt only has _process (ShredderFeedBelt.gd:777),
	# so drive it directly rather than trusting frame pacing.
	for _i in TICKS:
		belt.call("_process", DT)

	var acc := _sum_accumulators(belt)
	var total : float = acc["total"]
	var delta : float = total - start_kg

	print("  after %d ticks (%.1f s):" % [TICKS, TICKS * DT])
	print("    bales still holding kg : %8.2f" % acc["bales"])
	print("    belt riders (kg-ish)   : %8.2f   <- dimensionless 0..1 in reality" % acc["riders"])
	print("    belt fill   (kg-ish)   : %8.2f   <- dimensionless 0..1 in reality" % acc["fill"])
	print("    shredder buffer+overflow%8.2f" % acc["shredder"])
	print("    floor piles            : %8.2f" % acc["piles"])
	print("    waste containers       : %8.2f" % acc["bins"])
	print("    ----------------------------------")
	print("    TOTAL                  : %8.2f   (start %.2f, delta %+.2f)"
		% [total, start_kg, delta])

	_check(absf(delta) <= TOL_KG,
		"mass is conserved end to end (delta %+.2f kg, tolerance %.1f)" % [delta, TOL_KG])
	if absf(delta) > TOL_KG:
		if delta > 0.0:
			print("\n  DIAGNOSIS: %.2f kg was CREATED. The belt mints kg at" % delta)
			print("  ShredderFeedBelt.gd:788 as `digested * OUTPUT_KG_PER_FILL` (350.0)")
			print("  from a dimensionless fill delta, debiting nothing.")
		else:
			print("\n  DIAGNOSIS: %.2f kg VANISHED — check the minf(1.0, ...) clamp at" % delta)
			print("  ShredderFeedBelt.gd:832, the uncredited queue_free at :838, and the")
			print("  discarded FloorPile.add() refusal at :978.")

	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_ok, _fail])
	print("=========================================")
	get_tree().quit(1 if _fail > 0 else 0)

## Every kg accumulator on the bale -> belt -> shredder -> pile path.
## Riders and fill are converted with the belt's OWN constant, so the number
## shown is what the code itself implies those units are worth.
func _sum_accumulators(belt: Node) -> Dictionary:
	var per_fill : float = float(belt.get("OUTPUT_KG_PER_FILL")) if "OUTPUT_KG_PER_FILL" in belt else 350.0
	var bales := 0.0
	for b in get_tree().get_nodes_in_group("bale"):
		if is_instance_valid(b) and (b as Node).has_meta("remaining_kg"):
			bales += float((b as Node).get_meta("remaining_kg"))
	var riders := 0.0
	var rlist : Variant = belt.get("_riders")
	if rlist is Array:
		for r in (rlist as Array):
			if r is Dictionary:
				riders += float((r as Dictionary).get("mass", 0.0)) * per_fill
	var fill_kg : float = float(belt.get("fill")) * per_fill
	var shredder := 0.0
	for sh in get_tree().get_nodes_in_group("shredder"):
		shredder += float(sh.get("buffer_kg")) + float(sh.get("overflow_kg"))
	var piles := 0.0
	for fp in get_tree().get_nodes_in_group("floor_pile"):
		piles += float(fp.get("mass_kg"))
	var bins := 0.0
	for wc in get_tree().get_nodes_in_group("waste_container"):
		if "mass_kg" in wc:
			bins += float(wc.get("mass_kg"))
	return {
		"bales": bales, "riders": riders, "fill": fill_kg,
		"shredder": shredder, "piles": piles, "bins": bins,
		"total": bales + riders + fill_kg + shredder + piles + bins,
	}

func _check(cond: bool, msg: String) -> void:
	if cond:
		_ok += 1
		print("  ok   : %s" % msg)
	else:
		_fail += 1
		print("  FAIL : %s" % msg)
