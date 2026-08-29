extends Node
## Line 1 — no false MOTOR-OVERLOAD trip on a node that's genuinely keeping up.
##
##   godot --headless --path . res://src/tests/test_line1_no_false_overload.tscn
##
## Regression guard for the 2026-08-29 MotorOverload bug: LineFlow used to call
## `mol.add_load(_backlog_kg)` EVERY TICK, where `_backlog_kg` is the node's
## CURRENT BUFFER LEVEL (a stock), not a one-off inflow event — so a machine
## comfortably processing a small, stable queue still had that same standing
## kg re-counted as fresh load every tick, and raced from idle to a full trip
## in ~10 s of sim time despite never actually falling behind.
##
## Measured live: a single Rotterdam bale (396.5 kg) fed onto line 1's real
## infeed via the production feed path (BuildMode._build_full_line +
## LineFlow.start_line/tick — no mocks) tripped the downstream 'mill' node's
## MotorOverload while 'mill's own buffer stayed under 7 kg the entire run.
## test_motor_overload.gd proves the FIX at the class level (set_load mirrors
## a stock instead of accumulating it); this proves the INTEGRATION — that
## LineFlow's call site actually uses set_load, not a reintroduced
## add_load/relieve pair, by reproducing the exact scenario that broke.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] line 1 — no false overload trip")
	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_1", Vector3.ZERO, 0.0)
	await get_tree().process_frame

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")
	await get_tree().process_frame
	lf.call("start_line")
	for _i in 60:
		lf.call("tick", 0.1)

	var nodes : Array = lf.get("_nodes")
	var edges : Array = lf.get("_edges")
	var has_incoming : Dictionary = {}
	for e in edges:
		has_incoming[int((e as Dictionary)["b"])] = true
	var head_node : Node3D = null
	for i in nodes.size():
		var nd : Dictionary = nodes[i]
		if String(nd.get("role", "")) == "sink" or has_incoming.has(i):
			continue
		var n3d = nd.get("node")
		if n3d != null and is_instance_valid(n3d):
			head_node = n3d as Node3D
			break
	_check(head_node != null, "line 1 has a resolvable source head")
	if head_node == null:
		print("Result: FAIL (1 fail)")
		get_tree().quit(1); return

	var feed_point : Vector3 = lf.call("_head_feed_point", head_node)
	var bale : Node3D = PlaceableCatalog.build_node("rotterdam", false)
	add_child(bale)
	bale.global_position = feed_point
	bale.set_meta("delivered", true)

	# Track every high-load node (shredder_1/2, mill, friction separators — see
	# LineFlow._is_high_load_motor) across the whole run: none may trip while
	# genuinely keeping up. This is the exact scenario that broke before —
	# 'mill' tripped despite a <7 kg buffer throughout.
	var tracked : Array = []
	for i2 in nodes.size():
		if LineFlow._is_high_load_motor(String((nodes[i2] as Dictionary).get("id", "")),
				String((nodes[i2] as Dictionary).get("process", ""))):
			tracked.append(i2)
	_check(tracked.size() > 0, "at least one high-load node exists to guard (%d found)" % tracked.size())

	var t : int = 0
	var bale_gone_at : float = -1.0
	var false_trip_ids : Array = []
	while t < 2000:   # 200 s — comfortably past the ~50 s single-bale drain time
		lf.call("tick", 0.1)
		t += 1
		if bale_gone_at < 0.0 and (not is_instance_valid(bale) or bale.is_queued_for_deletion()):
			bale_gone_at = float(t) * 0.1
		for ti in tracked:
			var tnd : Dictionary = nodes[ti]
			var mol = tnd.get("mol")
			var buf : float = float(tnd.get("buffer", 0.0))
			if mol != null and bool(mol.call("is_tripped")) and buf < 50.0:
				# A trip alongside a SMALL buffer is exactly the false-trip
				# signature (a genuine overload trips WITH a large buffer —
				# see test_motor_overload.gd's "still catches a REAL
				# sustained overload" case, buffer 300 kg vs 120 kg capacity).
				var tid := String(tnd.get("id", ""))
				if not false_trip_ids.has(tid):
					false_trip_ids.append(tid)
		if bale_gone_at >= 0.0 and float(lf.call("in_transit_mass")) < 0.05:
			break

	_check(bale_gone_at >= 0.0, "the bale was actually consumed (%.1f s)" % bale_gone_at)
	_check(false_trip_ids.is_empty(),
		"NO high-load node false-tripped with a small buffer (offenders: %s)" % str(false_trip_ids))
	_check(float(lf.call("ledger_residual")) < 1.0,
		"mass ledger still balances (residual %.3f kg)" % float(lf.call("ledger_residual")))

	print("[TEST] line 1 no false overload %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	get_tree().quit(1 if _fails > 0 else 0)
