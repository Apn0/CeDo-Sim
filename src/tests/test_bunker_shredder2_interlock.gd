extends Node
## BUNKER / SHREDDER-2 MOL INTERLOCK — LineFlow.gd:_tick_bunker_shredder2_interlock().
##
##   godot --headless --path . res://src/tests/test_bunker_shredder2_interlock.tscn
##
## Places the real "line_sort" macro (BuildMode._build_full_line) and runs the
## real LineFlow.tick() — no bench stand-in for either. Forces shredder-2's MOL
## via MotorOverload.force_trip() (its own documented "owner-facing manual
## trip, e.g. an interlock" API) rather than waiting out the sustained-overload
## timer, so the test stays fast and deterministic.
##
## Exercises the exact identity trap the fix exists to avoid: LINE_SORT_SEQ
## places catalog id "transport_belt" 7 times (indices 2, 4, 5, 15, 16, 17,
## 18); S2 below asserts specifically that macro_index 4 (the bunker's real
## outfeed) loses power while the other six "transport_belt" instances do not
## — a same-id, wrong-instance mutation would go undetected without it.

var _fails : int = 0

func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _run() -> void:
	print("[TEST] bunker/shredder-2 MOL interlock")

	var bm := BuildMode.new()
	add_child(bm)
	await get_tree().process_frame
	bm.call("_build_full_line", "line_sort", Vector3.ZERO, 0.0)
	await get_tree().process_frame   # let placed machines' own _ready() run

	var lf := LineFlow.new()
	add_child(lf)
	await get_tree().process_frame
	lf.call("rebuild")

	var nodes : Array = lf.get("_nodes")
	_check(nodes.size() > 15, "line_sort placed a real node graph (%d nodes)" % nodes.size())

	# ── locate bunker / outfeed / shredder-2 by (macro_id, macro_index), the
	# same addressing the fix itself uses — NOT by id, since "transport_belt"
	# is not unique. ────────────────────────────────────────────────────────
	var bunker_i := -1
	var outfeed_i := -1
	var shredder2_i := -1
	var other_transport_belts : Array = []   # every OTHER "transport_belt" instance
	for i in nodes.size():
		var node3d = (nodes[i] as Dictionary).get("node")
		if node3d == null or not is_instance_valid(node3d) or not (node3d as Node3D).has_meta("macro_index"):
			continue
		var idx : int = int((node3d as Node3D).get_meta("macro_index"))
		var id : String = String((nodes[i] as Dictionary).get("id", ""))
		if idx == 3:
			bunker_i = i
		elif idx == 4:
			outfeed_i = i
		elif idx == 19:
			shredder2_i = i
		elif id == "transport_belt":
			other_transport_belts.append(i)

	_check(bunker_i >= 0, "bunker instance found (macro_index 3)")
	_check(outfeed_i >= 0, "bunker's outfeed belt found (macro_index 4)")
	_check(shredder2_i >= 0, "shredder-2 instance found (macro_index 19)")
	_check(other_transport_belts.size() >= 5,
		"multiple OTHER transport_belt instances exist to prove id-matching wasn't enough (%d found)"
			% other_transport_belts.size())

	if bunker_i < 0 or outfeed_i < 0 or shredder2_i < 0:
		print("[TEST] bunker/shredder-2 MOL interlock FAIL (setup incomplete)")
		get_tree().quit(1)
		return

	var titech_i : int = -1
	for i in nodes.size():
		if String((nodes[i] as Dictionary).get("id", "")) == "titech_sort":
			titech_i = i
			break
	_check(titech_i >= 0, "a TITECH sorter instance found (id titech_sort)")

	# ── S1 baseline: start the real PLC sequencer and let it fully power the
	# line up (capped near TARGET_STARTUP_S = 20s, LineFlow.gd:49) before
	# asserting anything about `powered` — un-started machines are supposed
	# to read powered=false, so the interlock can't be demonstrated stopping
	# something that was never running. ─────────────────────────────────────
	lf.call("start_line")
	for _i in 260: lf.tick(0.1)   # 26s sim time, safety margin over the 20s cap
	_check(bool(nodes[bunker_i]["powered"]), "S1 bunker powered after line start")
	_check(bool(nodes[outfeed_i]["powered"]), "S1 outfeed belt powered after line start")
	_check(bool(nodes[shredder2_i]["powered"]), "S1 shredder-2 powered after line start")

	# ── S2 force shredder-2's MOL to trip → bunker + its OWN outfeed stop, ───
	#     every OTHER transport_belt instance and TITECH are unaffected ──────
	var mol = nodes[shredder2_i].get("mol")
	_check(mol != null, "S2 shredder-2 carries a MotorOverload (mol) component")
	if mol == null:
		print("[TEST] bunker/shredder-2 MOL interlock FAIL (no mol on shredder-2)")
		get_tree().quit(1)
		return
	mol.call("force_trip")
	_check(bool(mol.call("is_tripped")), "S2 MOL reports tripped after force_trip()")

	lf.tick(0.1)   # PLC already fully started (S1) — this tick is purely the trip's effect

	_check(not bool(nodes[bunker_i]["powered"]), "S2 bunker loses power on MOL trip")
	_check(not bool(nodes[outfeed_i]["powered"]), "S2 bunker's outfeed belt loses power on MOL trip")
	_check(bool(nodes[titech_i]["powered"]), "S2 TITECH keeps running (unaffected)")
	var wrong_belt_killed : Array = []
	for i in other_transport_belts:
		if not bool(nodes[i]["powered"]):
			wrong_belt_killed.append(i)
	_check(wrong_belt_killed.is_empty(),
		"S2 no OTHER transport_belt instance was killed by id-collision (%d wrongly killed)"
			% wrong_belt_killed.size())

	# ── S3 reset → interlock releases (no per-tick re-latching once healthy) ─
	mol.call("reset", true)
	lf.tick(0.1)
	_check(bool(nodes[bunker_i]["powered"]), "S3 bunker re-powers once the MOL trip is reset")
	_check(bool(nodes[outfeed_i]["powered"]), "S3 outfeed belt re-powers once the MOL trip is reset")

	if _fails == 0:
		print("[TEST] bunker/shredder-2 MOL interlock PASS")
	else:
		print("[TEST] bunker/shredder-2 MOL interlock FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
