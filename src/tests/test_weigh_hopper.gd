extends SceneTree

## #223 item 16 — headless smoke test for WeighHopper (the weegschaal 25-kg
## weigh-and-dump batch model). Run headless:
##   godot --headless --script src/tests/test_weigh_hopper.gd
##
## Doc: docs/plant/swi/TRAIN-de-weegschaal-p6c__117_CeDo39.md
##   "Bij 25 kg gaat bovenste klep dicht en onderste klep open.
##    Bij 0 kg wisselen de stand van de kleppen weer."
##
## What it checks:
##   1. Feeding 60 kg in small increments (ticking as we go) yields EXACTLY two
##      25-kg dumps → produced_kg == 50.0, dump_count == 2, hopper_kg == 10.0.
##   2. feed() returns 0.0 while the inlet klep is closed mid-cycle (hopper full,
##      not yet dumped), and reopens after a tick dumps the batch.

const WeighHopper = preload("res://src/sim/WeighHopper.gd")

const TOL := 1.0e-4

func _initialize() -> void:
	print("[TEST] #223 weigh-hopper 25-kg batch")
	var ok := true

	# ── Part A: 60 kg through the hopper in small increments ─────────────────
	var wh = WeighHopper.new()
	var target := 60.0
	var step := 3.0
	var accepted_total := 0.0
	var guard := 0
	while accepted_total < target - TOL and guard < 10000:
		guard += 1
		var want : float = minf(step, target - accepted_total)
		var got : float = wh.feed(want)
		accepted_total += got
		# Tick every iteration: when the hopper is full (inlet closed) this dumps
		# the 25 kg and reopens; while filling it releases nothing.
		wh.tick(1.0)
	# Any batch left full at the end (shouldn't happen here) gets one drain tick.
	wh.tick(1.0)

	if absf(accepted_total - 60.0) > TOL:
		print("  FAIL: accepted_total %f != 60.0" % accepted_total); ok = false
	if wh.dump_count != 2:
		print("  FAIL: dump_count %d != 2" % wh.dump_count); ok = false
	if absf(wh.produced_kg - 50.0) > TOL:
		print("  FAIL: produced_kg %f != 50.0" % wh.produced_kg); ok = false
	if absf(wh.hopper_kg - 10.0) > TOL:
		print("  FAIL: hopper_kg %f != 10.0 (remainder)" % wh.hopper_kg); ok = false
	if not wh.inlet_open:
		print("  FAIL: inlet should be open with 10 kg remainder"); ok = false

	# ── Part B: inlet klep closed → feed() returns 0 mid-cycle ───────────────
	var wh2 = WeighHopper.new()
	var a : float = wh2.feed(25.0)          # exactly one batch → inlet closes
	if absf(a - 25.0) > TOL:
		print("  FAIL: feed(25) accepted %f != 25.0" % a); ok = false
	if wh2.inlet_open:
		print("  FAIL: inlet should be CLOSED at 25 kg"); ok = false
	var rejected : float = wh2.feed(5.0)    # klep closed → nothing accepted
	if absf(rejected) > TOL:
		print("  FAIL: feed() returned %f while inlet closed (expected 0)" % rejected); ok = false
	var released : float = wh2.tick(1.0)    # dump the batch, reopen at 0 kg
	if absf(released - 25.0) > TOL:
		print("  FAIL: tick released %f != 25.0" % released); ok = false
	if not wh2.inlet_open:
		print("  FAIL: inlet should REOPEN after the dump"); ok = false
	if wh2.dump_count != 1 or absf(wh2.produced_kg - 25.0) > TOL:
		print("  FAIL: post-dump counters wrong (dumps=%d produced=%f)" % [wh2.dump_count, wh2.produced_kg]); ok = false

	if ok:
		print("[TEST] weigh-hopper PASS")
	else:
		print("[TEST] weigh-hopper FAIL")
	quit(0 if ok else 1)
