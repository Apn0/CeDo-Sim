extends Node3D

## Headless test for the feed-line trio: ShredderFeedBelt (#153), scan-gating
## (#152), and the FeederWorker loop (#151). Scene-based so autoloads load.

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond: _passed += 1
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	_build_floor()
	await _test_scan_gate()
	await _test_belt_feeds_and_stops()
	await _test_feeder_loop()
	await _test_personal_kit()
	await _test_feeder_drives()
	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

# ── 5. Feeder DRIVES its vehicle through the loop ─────────────────────────────
func _test_feeder_drives() -> void:
	print("[5] FeederWorker drives: board → drive → clamp → drive → cut+scan → load")
	var belt := _make_belt(Vector3(0, 0, 25))
	belt.belt_speed = 4.0
	belt.digest_rate = 0.5
	var lot := Vector3(8, 0, 25)
	for i in range(3):
		_make_bale(lot + Vector3(0, 0.6, float(i) - 1.0), false)
	var worker = preload("res://src/scenes/world/FeederWorker.gd").new()
	worker.worker_name = "Driver"
	worker.lot_center = lot
	worker.lot_radius = 22.0
	worker.process_secs = 0.4
	add_child(worker)
	worker.global_position = Vector3(3, 1.0, 25)
	# Hand the worker a fresh bale clamp parked beside them.
	var vscene := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
	var v := vscene.instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3(2, 0.5, 22)
	worker.assign_vehicle(v)
	# Plenty of sim time to board + complete at least one drive loop.
	for i in range(1400):
		await get_tree().physics_frame
	_ok(bool(worker.get("_riding")), "worker boarded + is riding the vehicle")
	_ok(bool(v.get("npc_autopilot")), "vehicle is under NPC autopilot")
	_ok(worker.bales_processed >= 1, "driver cut+scanned at least one bale (%d)" % worker.bales_processed)
	_ok(belt.bales_accepted >= 1, "driver delivered a bale to the belt (%d)" % belt.bales_accepted)

# ── 4. Personal kit: NPC-owned vehicle + holstered, non-grabbable tools ───────
func _test_personal_kit() -> void:
	print("[4] Feeder personal kit: owned vehicle + stowed tools")
	var worker = preload("res://src/scenes/world/FeederWorker.gd").new()
	worker.worker_name = "Mohammed"
	worker.assigned_line = "Line 3A/3B"
	add_child(worker)
	worker.global_position = Vector3(40, 1, 0)
	await get_tree().physics_frame
	# Personal vehicle — a fresh bale clamp, tagged NPC-owned.
	var vscene := load("res://src/scenes/vehicles/BaleClamp.tscn") as PackedScene
	var v := vscene.instantiate() as Node3D
	add_child(v)
	v.global_position = Vector3(42, 0.5, 0)
	worker.assign_vehicle(v)
	await get_tree().physics_frame
	_ok(bool(v.get("npc_owned")), "assigned vehicle carries the ownership tag")
	_ok(v.call("can_enter"), "ownership is a tag, NOT a lock — anyone can still board")
	_ok(String(v.get("npc_owner_name")) == "Mohammed", "vehicle tagged with owner name")
	# Personal scissors stowed on the holster, pickup disabled.
	var scissors := WireCutter.new()
	add_child(scissors)
	worker.stow_personal_tool(scissors, -1.0)
	var area := scissors.get_node_or_null("PickupArea") as Area3D
	_ok(area != null and not area.monitoring, "stowed scissors not player-grabbable")
	_ok(scissors.get_parent() != null and scissors.get_parent().name == "Holster",
			"scissors ride the worker's holster")

func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new(); bs.size = Vector3(80, 1, 80)
	cs.shape = bs
	cs.position = Vector3(0, -0.5, 0)
	floor_body.add_child(cs)
	add_child(floor_body)

func _make_belt(pos: Vector3) -> Node:
	var belt = preload("res://src/scenes/world/ShredderFeedBelt.gd").new()
	add_child(belt)
	belt.global_position = pos
	return belt

func _make_bale(pos: Vector3, scanned: bool) -> Node3D:
	var b := PlaceableCatalog.build_node("rotterdam", false) as Node3D
	add_child(b)
	b.global_position = pos
	if b is RigidBody3D:
		(b as RigidBody3D).freeze = true
	b.set_meta("scanned", scanned)
	return b

# ── 1. Scan gate ─────────────────────────────────────────────────────────────
func _test_scan_gate() -> void:
	print("[1] Scan gate: belt refuses unscanned, accepts scanned")
	var belt := _make_belt(Vector3(-20, 0, 0))
	var unscanned := _make_bale(Vector3(-20, 0.6, 1), false)
	var ok_unscanned : bool = belt.call("accept_bale", unscanned, 0)
	_ok(not ok_unscanned, "unscanned bale REJECTED by the belt")
	_ok(belt.call("rider_count") == 0, "rejected bale not on belt")
	var scanned := _make_bale(Vector3(-20, 0.6, 2), true)
	var ok_scanned : bool = belt.call("accept_bale", scanned, 0)
	_ok(ok_scanned, "scanned bale ACCEPTED by the belt")
	_ok(belt.call("rider_count") == 1, "accepted bale is riding the belt")
	await get_tree().physics_frame

# ── 2. Belt feeds + stops at setpoint ────────────────────────────────────────
func _test_belt_feeds_and_stops() -> void:
	print("[2] Belt feeds fill + halts at the shredder set-point")
	var belt := _make_belt(Vector3(20, 0, 0))
	belt.belt_speed = 6.0      # speed the ride up for the test
	belt.feed_rate  = 2.0
	belt.digest_rate = 0.0     # freeze digestion so fill only rises
	var b := _make_bale(Vector3(20, 0.6, 1), true)
	belt.call("accept_bale", b, 0)
	# Run ~4 s of sim — bale should ride to the top and feed the throat.
	for i in range(240):
		await get_tree().physics_frame
	_ok(belt.fill > 0.0, "throat fill rose as the bale fed (fill=%.2f)" % belt.fill)
	# Drive fill above set-point → belt must stop.
	belt.fill = 0.95
	_ok(not belt.call("is_running"), "belt STOPS when throat at/above set-point")
	belt.fill = 0.10
	_ok(belt.call("is_running"), "belt RESUMES once throat has room")

# ── 3. Feeder worker runs the full loop ──────────────────────────────────────
func _test_feeder_loop() -> void:
	print("[3] FeederWorker: seek → cut+scan → carry → load")
	var belt := _make_belt(Vector3(0, 0, 0))
	belt.belt_speed = 4.0
	belt.digest_rate = 0.5     # eat fast so the belt keeps running for the test
	# Three UNSCANNED bales in a small lot — the worker must scan them itself.
	var lot := Vector3(6, 0, 0)
	for i in range(3):
		_make_bale(lot + Vector3(0, 0.6, float(i) - 1.0), false)
	var worker = preload("res://src/scenes/world/FeederWorker.gd").new()
	worker.worker_name = "Tester"
	worker.lot_center = lot
	worker.walk_speed = 8.0
	worker.process_secs = 0.4
	add_child(worker)
	worker.global_position = Vector3(3, 1.0, 0)
	# Run ~9 s of sim for the worker to process + feed at least one bale.
	for i in range(540):
		await get_tree().physics_frame
	_ok(worker.bales_processed >= 1, "worker cut+scanned at least one bale (%d)" % worker.bales_processed)
	_ok(worker.bales_fed >= 1, "worker fed at least one scanned bale onto the belt (%d)" % worker.bales_fed)
	# Cumulative — robust against the bale already being digested by check-time.
	_ok(belt.bales_accepted >= 1, "belt accepted the fed bale (%d)" % belt.bales_accepted)
	_ok(belt.bales_rejected == 0, "no scan-gate rejections (worker scanned first)")
