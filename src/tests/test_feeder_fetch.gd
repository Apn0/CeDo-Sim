extends Node
# =============================================================================
# #241 — FEEDER TOOL FETCH regression.
#
# Before this fix CrewManager._ensure_section_feeder conjured a WireCutter + a
# BarcodeScanner AT THE FEEDER'S FEET (global_position = feeder.global_position)
# and stowed them in the same frame — equipment materialised out of thin air in
# the worker's hands. The rule the operator set is "tools must come from
# somewhere": the kit lies at a real pickup point and the worker WALKS to it.
#
# This test boots the REAL MainWorld on a scratch save slot, drops a feed belt +
# a synthetic driver on known-open exterior ground, engages a section feeder
# through the real CrewManager entry point, and proves:
#
#   1. FIRST world position of BOTH tools is the resolved TOOL REST pose — and is
#      more than 3 m from where the feeder spawned (the old bug put them at 0 m).
#   2. Neither tool is holstered on the feeder at assignment time; they sit loose
#      in the world waiting to be collected.
#   3. The feeder actually WALKS: it covers the ground between its spawn and the
#      pickup instead of teleporting or standing still, and it ARRIVES — the
#      no-progress deadlock guard must not have force-completed the leg (a
#      force-complete is a teleport-stow of the last few metres).
#   4. It ends up HOLDING BOTH — personal_scissors + personal_scanner set, both
#      re-parented onto the holster.
#   5. Re-kitting an already-kitted feeder is a no-op (re-pin / world reload must
#      not stack a second set of tools).
#
# TWO POSES, both asserted, so "arrival" cannot be bought by moving the goalposts:
#   REST  (_tool_rest_pos) — where the kit lies, on the belt frame at hand height.
#   STAND (_fetch_pos)     — the floor spot the worker walks to. Asserted to be
#                            within arm's reach of REST, so a fix cannot pass by
#                            parking the walk target somewhere convenient.
#
#   GODOT --headless --path . res://src/tests/test_feeder_fetch.tscn
# =============================================================================

const TEST_SLOT   := "__feederfetch__"
# Same known-open exterior apron the clamp repro aims at (ExteriorGroundBody top
# y = -9.0, verified by a down-ray there). NOT an empty straight line: the measured
# route grazes the BuildingShell ~1 m from the driver spawn and crosses the belt's
# own deck, which is the point — the walk has to get round both on foot.
const BELT_POS    := Vector3(-197.823196, -9.0, 90.448288)
const DRIVER_OFF  := Vector3(16.0, 1.0, 0.0)   # feeder spawns here — a real walk away
const BOOT_FRAMES := 80
const WALK_FRAMES := 2400                      # 40 s at 60 Hz; the in-engine
                                               # blocked-walk watchdog gives up at
                                               # 20 s, so this always terminates
const MIN_SPAWN_GAP_M := 3.0                   # tools must NOT appear at the feeder
const ARRIVE_M        := 2.0                   # counts as "got there" (walk stops at 1.8)
const REACH_M         := 2.5                   # stand spot ↔ kit: arm's reach, not a shortcut

## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const PROTECT := [
	"user://__feederfetch___save.json",
	"user://__feederfetch___factory.json",
]

const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)
var _fails   : int = 0

func _check(ok: bool, msg: String) -> void:
	print(("  ok    : " if ok else "  FAIL  : ") + msg)
	if not ok:
		_fails += 1

func _ready() -> void:
	print("=== #241 — feeder fetches its kit, never conjures it ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	# Before boot, so no world save can reach the operator's world_layout.json.
	if not _wlg.arm(get_tree()):
		get_tree().quit(2); return

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); _bail(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame

	var cm : Node = _find_crew_manager(world)
	if cm == null:
		print("FATAL: no CrewManager in the booted world"); _bail(2); return

	# ── Deterministic fixture: a feed belt on open exterior ground, and a driver
	# far enough away that the feeder cannot possibly spawn on top of its kit.
	var belt := _ensure_belt(world)
	if belt == null:
		print("FATAL: could not resolve/build a shredder_feed_belt"); _bail(2); return
	var driver := Node3D.new()
	driver.name = "TestDriver"
	world.add_child(driver)
	driver.global_position = belt.global_position + DRIVER_OFF
	await get_tree().physics_frame

	# ── The real entry point the operator's pin + every world load routes through.
	cm.call("_ensure_section_feeder", "role:feeder", driver.global_position, driver)
	await get_tree().process_frame

	var feeder : Node = _feeder_for(cm, "role:feeder")
	if feeder == null:
		print("FATAL: _ensure_section_feeder produced no feeder"); _bail(2); return
	var spawn_pos : Vector3 = (feeder as Node3D).global_position

	# ── 1/2 — where did the tools FIRST appear? ─────────────────────────────────
	var sc  := feeder.get("_pending_scissors") as Node3D
	var scn2 := feeder.get("_pending_scanner") as Node3D
	_check(sc != null, "a wire cutter was resolved for the feeder")
	_check(scn2 != null, "a barcode scanner was resolved for the feeder")
	_check(feeder.get("personal_scissors") == null and feeder.get("personal_scanner") == null,
		"nothing is in the feeder's hands at assignment time (kit is still in the world)")
	_check(bool(feeder.call("is_fetching_tools")), "feeder is in the TOOL_FETCH leg")

	var stand : Vector3 = feeder.get("_fetch_pos")
	var rest  : Vector3 = feeder.get("_tool_rest_pos")
	print("[POS] feeder spawn=(%.2f, %.2f, %.2f)  kit rests=(%.2f, %.2f, %.2f)  stands=(%.2f, %.2f, %.2f)"
		% [spawn_pos.x, spawn_pos.y, spawn_pos.z, rest.x, rest.y, rest.z,
			stand.x, stand.y, stand.z])
	_check(_horiz(stand, rest) <= REACH_M,
		"the standing spot is within arm's reach of the kit (%.2f m, limit %.1f)"
			% [_horiz(stand, rest), REACH_M])
	_check(_horiz(stand, spawn_pos) > MIN_SPAWN_GAP_M,
		"the standing spot is %.1f m from the feeder — a real walk, not their own feet"
			% _horiz(stand, spawn_pos))
	for pair in [[sc, "wire cutter"], [scn2, "barcode scanner"]]:
		var t := pair[0] as Node3D
		var label := String(pair[1])
		if t == null:
			continue
		var first : Vector3 = t.global_position
		print("    %s first world pos=(%.2f, %.2f, %.2f)" % [label, first.x, first.y, first.z])
		var d_feeder : float = _horiz(first, spawn_pos)
		var d_rest : float = _horiz(first, rest)
		_check(d_feeder > MIN_SPAWN_GAP_M,
			"%s spawned %.1f m from the feeder (must be >%.1f — never at their feet)"
				% [label, d_feeder, MIN_SPAWN_GAP_M])
		_check(d_rest <= 1.0,
			"%s rests AT the resolved tool spot (%.2f m off)" % [label, d_rest])
		_check(t.get_parent() != null and not _is_descendant_of(t, feeder),
			"%s is loose in the world, not already holstered" % label)

	# ── 3/4 — the walk, then the holster ───────────────────────────────────────
	var start_gap : float = _horiz(spawn_pos, stand)
	var closest : float = start_gap
	var closest_rest : float = _horiz(spawn_pos, rest)
	var frames_walked : int = 0
	for f in range(WALK_FRAMES):
		await get_tree().physics_frame
		frames_walked = f + 1
		if not is_instance_valid(feeder):
			break
		var here : Vector3 = (feeder as Node3D).global_position
		closest = minf(closest, _horiz(here, stand))
		closest_rest = minf(closest_rest, _horiz(here, rest))
		if not bool(feeder.call("is_fetching_tools")):
			break
	print("[WALK] %d frames (%.1f s), start gap %.1f m, closest to stand %.2f m, closest to kit %.2f m, side-steps %d"
		% [frames_walked, frames_walked / 60.0, start_gap, closest, closest_rest,
			int(feeder.get("walk_sidesteps"))])

	_check(not bool(feeder.call("is_fetching_tools")), "the fetch leg completed")
	_check(closest < start_gap * 0.5,
		"the feeder COVERED the ground to its kit (closed %.1f m of %.1f m)"
			% [start_gap - closest, start_gap])
	_check(closest <= ARRIVE_M,
		"the feeder ARRIVED at the standing spot (%.2f m, limit %.1f)" % [closest, ARRIVE_M])
	_check(closest_rest <= ARRIVE_M + REACH_M,
		"the feeder got within reach of the kit itself (%.2f m, limit %.1f)"
			% [closest_rest, ARRIVE_M + REACH_M])
	# The deadlock guard force-completing the leg IS the teleport-stow this fix
	# exists to remove: the worker would take tools they never physically reached.
	_check(int(feeder.get("walk_forced_completions")) == 0,
		"the leg ended by ARRIVING, not by the deadlock guard force-completing it (%d force-completes)"
			% int(feeder.get("walk_forced_completions")))

	var held_sc  := feeder.get("personal_scissors") as Node3D
	var held_scn := feeder.get("personal_scanner") as Node3D
	_check(held_sc != null and is_instance_valid(held_sc), "feeder ends up holding the wire cutter")
	_check(held_scn != null and is_instance_valid(held_scn), "feeder ends up holding the barcode scanner")
	_check(held_sc == sc and held_scn == scn2,
		"they are the SAME instances that lay at the pickup point (not fresh copies)")
	if held_sc != null:
		_check(_is_descendant_of(held_sc, feeder), "wire cutter is parented onto the holster")
	if held_scn != null:
		_check(_is_descendant_of(held_scn, feeder), "barcode scanner is parented onto the holster")

	# ── 5 — idempotency: re-kitting must not conjure a second set ──────────────
	var before_sc  : int = get_tree().get_nodes_in_group("wire_cutter").size()
	var before_scn : int = get_tree().get_nodes_in_group("barcode_scanner").size()
	cm.call("_kit_feeder_from_pickup", world, feeder, belt, belt.global_position)
	cm.call("_ensure_section_feeder", "role:feeder", driver.global_position, driver)
	await get_tree().process_frame
	_check(get_tree().get_nodes_in_group("wire_cutter").size() == before_sc,
		"re-kit + re-pin spawned no extra wire cutter (%d)" % before_sc)
	_check(get_tree().get_nodes_in_group("barcode_scanner").size() == before_scn,
		"re-kit + re-pin spawned no extra scanner (%d)" % before_scn)
	_check(feeder.get("personal_scissors") == held_sc and feeder.get("personal_scanner") == held_scn,
		"the feeder still carries the same kit after re-assignment")
	_check(_feeder_for(cm, "role:feeder") == feeder, "re-pin reused the existing feeder (no duplicate worker)")
	for c in _wlg.final_checks(world):
		_check(c[0], c[1])

	# The verdict is printed and user:// restored BEFORE the world is freed,
	# then restored again after: the headless teardown segfault lands inside
	# world teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
	_wlg.restore()
	print("\n=========================================")
	print("Result: %s (%d fail)" % ["PASS" if _fails == 0 else "FAIL", _fails])
	print("=========================================")
	world.queue_free()
	await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if _fails == 0 else 1)

# ── Helpers ──────────────────────────────────────────────────────────────────

func _horiz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _is_descendant_of(n: Node, root: Node) -> bool:
	var p : Node = n.get_parent()
	while p != null:
		if p == root:
			return true
		p = p.get_parent()
	return false

func _find_crew_manager(world: Node) -> Node:
	if world.get("crew_manager") != null:
		return world.get("crew_manager") as Node
	for c in world.get_children():
		if c is CrewManager:
			return c
	return null

func _feeder_for(cm: Node, key: String) -> Node:
	var d = cm.get("_section_feeders")
	if d == null or not (d is Dictionary):
		return null
	var f = (d as Dictionary).get(key, null)
	return f as Node if (f != null and is_instance_valid(f)) else null

## Prefer a belt the world already has near the test apron; otherwise build one
## there, so the fixture never depends on what the operator has placed.
func _ensure_belt(world: Node) -> Node3D:
	for b in get_tree().get_nodes_in_group("shredder_feed_belt"):
		if b is Node3D and is_instance_valid(b) \
				and _horiz((b as Node3D).global_position, BELT_POS) < 40.0:
			return b as Node3D
	var belt = load("res://src/scenes/world/ShredderFeedBelt.gd").new()
	belt.name = "TestFeedBelt"
	world.add_child(belt)
	(belt as Node3D).global_position = BELT_POS
	return belt as Node3D

func _bail(code: int) -> void:
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(code)

