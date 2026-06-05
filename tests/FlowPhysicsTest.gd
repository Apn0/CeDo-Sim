extends Node3D

## #145 — PHYSICALIZED MATERIAL TRANSPORT.
## Proves the three things the operator demanded ("physics, not approaches"):
##
##   [A] ROTATION DRIVES FLOW — with the line powered DOWN, a fed head machine
##       does NOT pass material on; it backs up in the head's buffer and ZERO
##       granulaat is produced (rotors aren't turning).
##   [B] NO INSTANT LINE-WIDE OUTPUT — right after starting, granulaat at the
##       sink is STILL zero: the line powers up downstream-first and material
##       has to physically traverse the connectors (transit delay).
##   [C] IT EVENTUALLY ARRIVES — given enough time, material rides all the way
##       through and the extruder banks granulaat.
##   [D] CONSERVATION HOLDS — at every check the ledger residual ≈ 0, now
##       including the mass riding the connectors.

const LineFlowScript = preload("res://src/sim/LineFlow.gd")

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
	print("=== #145 PHYSICALIZED MATERIAL TRANSPORT ===")
	# Build a 3-stage line in flow order: bunker(head) → shredder → extruder(sink).
	var ids := ["bunker", "shredder_1", "extruder_1"]
	var z := 0.0
	var head : Node3D = null
	for id in ids:
		var item := PlaceableCatalog.get_item(id)
		if item.is_empty():
			_ok(false, "catalog has '%s'" % id)
			_finish(); return
		var size : Vector3 = item["size"]
		var node := PlaceableCatalog.build_node(id, false) as Node3D
		add_child(node)
		node.global_position = Vector3(0.0, 0.0, z + size.z * 0.5)
		# The extruder's feed throat (in-port) faces +Z; as the LAST machine its
		# throat must face the upstream line (−Z), so turn it around.
		if id == "extruder_1":
			node.rotation.y = PI
		z += size.z + 1.5
		node.set_meta("placeable_id", id)
		if not node.is_in_group("placed_object"):
			node.add_to_group("placed_object")
		if head == null:
			head = node

	# LineFlow discovers them on _ready; reset to a COLD start (auto_start off).
	# Drive tick() ourselves with a fixed delta, so disable its own _process to
	# avoid double-ticking and make sim time deterministic.
	var lf = LineFlowScript.new()
	add_child(lf)
	lf.set_process(false)
	lf.auto_start = false
	lf.feed_enabled = true
	lf.rebuild()
	_ok(lf._nodes.size() == 3, "3 machines discovered (got %d)" % lf._nodes.size())
	_ok(lf._edges.size() == 2, "2 links formed head→…→sink (got %d)" % lf._edges.size())

	# A delivered bale sitting on the head so the line has something to draw.
	var bale_id := String(BaleDefs.origins()[0]["id"])
	var bale := PlaceableCatalog.build_node(bale_id, false) as Node3D
	add_child(bale)
	bale.global_position = head.global_position
	if not bale.is_in_group("bale"):
		bale.add_to_group("bale")
	bale.set_meta("material_origin", bale_id)
	bale.set_meta("delivered", true)
	bale.set_meta("remaining_kg", 4000.0)
	if bale is RigidBody3D:
		(bale as RigidBody3D).freeze = true

	# ── [A] Rotation gates flow: run COLD (unpowered) for ~4 s ─────────────────
	_run(lf, 260)
	_ok(lf.gran_mass <= 0.0,
		"A: powered-down line produces NO granulaat (gran=%.1f)" % lf.gran_mass)
	_ok(lf.line_powered_fraction() <= 0.0,
		"A: no machine is powered yet (%.0f%%)" % (lf.line_powered_fraction() * 100.0))
	_ok(_head_buffer(lf) > 0.0,
		"A: fed material BACKS UP in the head buffer (%.1f kg waiting)" % _head_buffer(lf))
	_ok(absf(lf.ledger_residual()) < 2.0,
		"A: conservation holds cold (residual %.3f kg)" % lf.ledger_residual())

	# ── [B] Start the line; granulaat must NOT appear instantly ────────────────
	lf.start_line()
	_run(lf, 120)   # ~2 s after start — sink+shredder powering, head not yet conveying
	_ok(lf.gran_mass <= 0.0,
		"B: NO instant line-wide output — sink still 0 just after start (gran=%.1f)" % lf.gran_mass)
	_ok(lf.is_line_starting() or lf.line_powered_fraction() < 1.0,
		"B: line is still powering up downstream-first (%.0f%% powered)" % (lf.line_powered_fraction() * 100.0))

	# ── [C] Give it time — material rides the whole line to the extruder ───────
	_run(lf, 2600)  # ~43 s
	_ok(lf.gran_mass > 0.0,
		"C: material traversed the line and the extruder banked granulaat (%.1f kg)" % lf.gran_mass)
	_ok(lf.line_powered_fraction() >= 1.0,
		"C: whole line is now up to speed (%.0f%% powered)" % (lf.line_powered_fraction() * 100.0))

	# ── [D] Conservation across the whole run, pipes included ──────────────────
	_ok(absf(lf.ledger_residual()) < 2.0,
		"D: conservation holds running (residual %.3f kg, in-line %.1f kg, pipes %.1f kg)"
			% [lf.ledger_residual(), lf.in_transit_mass(), lf.pipe_mass()])

	_finish()

# ── helpers ───────────────────────────────────────────────────────────────────
## Drive the flow with a FIXED 1/60 s delta — deterministic regardless of how the
## headless engine paces process vs physics frames.
func _run(lf, frames: int) -> void:
	for i in range(frames):
		lf.tick(1.0 / 60.0)

func _head_buffer(lf) -> float:
	# The head is the node with no incoming link (index 0 of flow order).
	for nd in lf._nodes:
		if String(nd["role"]) != "sink" and not lf._has_incoming(lf._nodes.find(nd)):
			return float(nd["buffer"])
	return 0.0

func _finish() -> void:
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()
