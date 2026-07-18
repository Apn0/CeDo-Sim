extends Node
# #233 — proves the ShredderFeedBelt cross-wise fix + feeder self-recovery that
# were the FEED/jam deadlock (#2):
#   A) a bale fed LENGTHWISE (long axis = model X, aligned to belt travel) is NOT
#      tagged cross-wise and does NOT jam — so material actually flows.
#   B) a bale fed CROSS-WISE still jams after the 5 s window (the mechanic is intact),
#      and reset_faults() (what the feeder now calls) recovers the belt so it accepts
#      again — no permanent deadlock.
# Run: godot --headless --path . res://src/tests/test_feed_belt_orientation.tscn
var _fails := 0
func _check(c: bool, msg: String) -> void:
	print(("  ok    : " if c else "  FAIL  : ") + msg)
	if not c:
		_fails += 1

func _ready() -> void:
	call_deferred("_run")

func _make_belt() -> Node:
	var belt = load("res://src/scenes/world/ShredderFeedBelt.gd").new()
	if "require_shredder" in belt:
		belt.set("require_shredder", false)
	add_child(belt)
	(belt as Node3D).global_transform = Transform3D.IDENTITY
	return belt

## A bale is just a Node3D with the scan gate met + a yaw. Long axis = local +X.
func _make_bale(yaw_rad: float) -> Node3D:
	var b := Node3D.new()
	b.set_meta("scanned", true)
	b.add_to_group("bale")
	add_child(b)   # must be in-tree so global_transform reflects the yaw
	b.global_transform = Transform3D(Basis(Vector3.UP, yaw_rad), Vector3.ZERO)
	return b

func _run() -> void:
	print("[TEST] feed belt orientation")

	# ── A: lengthwise bale (feeder's BALE_FEED_YAW = -90° → X onto belt +Z) ────
	var belt_a := _make_belt()
	await get_tree().process_frame
	var bale_a := _make_bale(-PI / 2.0)
	_check(bool(belt_a.call("accept_bale", bale_a, 0)), "A lengthwise bale accepted")
	var riders_a : Array = belt_a.get("_riders")
	var cw_a : bool = riders_a.size() > 0 and bool(riders_a[0]["cross_wise"])
	var yaw_a : float = float(riders_a[0].get("yaw_deg", 99.0)) if riders_a.size() > 0 else 99.0
	_check(not cw_a, "A lengthwise bale is NOT tagged cross-wise (dev %.0f°)" % yaw_a)
	for _i in 70:
		belt_a._process(0.1)   # 7 s > JAM_TIMER_S (5 s)
	_check(not bool(belt_a.call("is_faulted")), "A no BELT-JAM after 7 s — lengthwise feeds clean")

	# ── B: cross-wise bale (X along belt +X = across) → jams, then recovers ────
	var belt_b := _make_belt()
	await get_tree().process_frame
	var bale_b := _make_bale(0.0)
	_check(bool(belt_b.call("accept_bale", bale_b, 0)), "B cross-wise bale still accepted (modelled failure)")
	var riders_b : Array = belt_b.get("_riders")
	_check(riders_b.size() > 0 and bool(riders_b[0]["cross_wise"]), "B cross-wise bale IS tagged cross-wise")
	for _j in 70:
		belt_b._process(0.1)
	_check(bool(belt_b.call("is_faulted")), "B BELT-JAM latches after the 5 s window (mechanic intact)")
	# Recovery: reset (the feeder now calls this) clears the latch + it accepts again.
	belt_b.call("reset_faults")
	_check(not bool(belt_b.call("is_faulted")), "B reset_faults() clears the jam (feeder recovery)")
	(belt_b.get("_riders") as Array).clear()   # isolate the re-accept from the old jammed rider
	_check(bool(belt_b.call("accept_bale", _make_bale(-PI / 2.0), 0)), "B belt accepts a fresh bale after recovery")

	# ── C (#4): a released bale BURSTS into physical film pieces + still feeds ─
	var belt_c := _make_belt()
	await get_tree().process_frame
	var bale_c := _make_bale(-PI / 2.0)
	bale_c.set_meta("sheet_count", 6)
	var n_before : int = get_tree().get_nodes_in_group("film_piece").size()
	_check(bool(belt_c.call("burst_bale", bale_c)), "C burst_bale accepted the released bale")
	var made : int = get_tree().get_nodes_in_group("film_piece").size() - n_before
	_check(made == 6, "C bale burst into 6 physical film pieces (got %d)" % made)
	_check(not bool(bale_c.get("visible")), "C the whole block is hidden — pieces are the visible fall-apart")
	_check((belt_c.get("_riders") as Array).size() == 1, "C mass STILL flows: 1 invisible rider carries the bale to the shredder")
	# pieces are real RigidBody3D physics bodies
	var one_piece : Node = get_tree().get_nodes_in_group("film_piece")[0]
	_check(one_piece is RigidBody3D, "C the pieces are real RigidBody3D (physically tumble)")

	if _fails == 0:
		print("[TEST] feed belt orientation PASS")
	else:
		print("[TEST] feed belt orientation FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)
