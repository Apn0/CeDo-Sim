extends Node

## #225 — NPC Task Bench end-to-end proof (scene-based; autoloads live).
##   godot --headless --path <proj> res://src/tests/test_npc_task_bench.tscn
##
## Stages (each with a NEGATIVE control so no green is vacuous):
##   S1 world: group populations are exact (3 filters, 6 carts, 2 containers…).
##   S2 geometry: every filter's eject mouth is above the cart rim, has EXACTLY
##      ONE cart in its catch window, and sits OUTSIDE every extruder footprint.
##   S3 dynamics: drive filter A's rope until chunks break off; chunks EXIST
##      mid-flight (control), land INSIDE the cart window, NONE on an extruder
##      footprint, and are then absorbed by the bound cart (group empties).
##   S4 assignment: role gate — shift_leader gets NOTHING from the board while
##      an all_rounder gets the EmptyLumpCartTask for a full cooled cart.
##   S5 autonomy: within ~8 s of bench-time, at least one NPC has claimed a
##      task from the board WITHOUT any manual call (the "automatic" ask).
##   S6 force path (CrewPanel backend): force_task succeeds, sets _forced_task;
##      after the jerrycan is removed, refuel force fails cleanly.
##   S7 crew systems: CrewManager holds all 8 workers; manual_assign pins a
##      role post; station_list() (panel data source) is non-empty.
##   S8 (#233) feeder shift adopts the REAL assigned NPC (no "Feeder X" ghost).
##   S9 board lifecycle (npc-01): release un-claims; a FAILED task holds its
##      key only for the retry cooldown, then the board re-emits a FRESH task
##      for the still-qualifying target (no session-long wedge).
##   S10 dump credit (phys-06): with the cart yanked off the forks the dump
##      FAILS and the container gains nothing; with the cart riding, it credits.

const BenchScene = preload("res://src/scenes/world/NpcTaskBench.tscn")

var _fails : int = 0

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

func _ready() -> void:
	print("[TEST] npc task bench")
	var bench = BenchScene.instantiate()
	add_child(bench)
	# Boot settles: navmesh bake is blocking, but NPC _ready defers + groups
	# register on tree entry.
	for i in 3:
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout

	var tree := get_tree()
	var filters : Array = tree.get_nodes_in_group("laser_filter")
	var carts   : Array = tree.get_nodes_in_group("lump_cart")
	var extruders : Array = []
	for id in ["extruder_3a", "extruder_3b", "extruder_1"]:
		var found : Array = []
		_find_by_meta(bench, "placeable_id", id, found)
		extruders.append_array(found)

	# ── S1 world ────────────────────────────────────────────────────────────
	_check(filters.size() == 3, "S1 exactly 3 live laser filters (%d)" % filters.size())
	_check(carts.size() == 6, "S1 exactly 6 lump carts — TWO per extruder (%d)" % carts.size())
	_check(tree.get_nodes_in_group("waste_container").size() == 2, "S1 2 waste containers")
	_check(tree.get_nodes_in_group("leaf_blower").size() >= 1, "S1 leaf blower present")
	_check(tree.get_nodes_in_group("jerrycan").size() >= 1, "S1 jerrycan present")
	_check(tree.get_nodes_in_group("floor_pile").size() >= 1, "S1 floor film pile present")
	_check(tree.get_nodes_in_group("crew_manager").size() == 1, "S1 CrewManager registered")
	_check(tree.get_nodes_in_group("forklift").size() >= 1, "S1 forklift present (lump-haul dependency)")
	_check(tree.get_nodes_in_group("line_fault").is_empty(), "S1 no line_fault nodes (cleaning priorities unpenalized)")
	_check(extruders.size() == 3, "S1 3 extruders found by placeable_id (%d)" % extruders.size())

	# ── S2 geometry (BOTH vertical nozzles: aisle +X, wall -X) ───────────────
	const RIM_Y := 0.95
	for f in filters:
		var ejects : Array = [f.call("eject_global"), f.call("eject_global_wall")]
		var elbl : Array = ["aisle", "wall"]
		for ei in ejects.size():
			var eject : Vector3 = ejects[ei]
			_check(eject.y > RIM_Y + 0.05,
				"S2 %s mouth above cart rim (%.2f > %.2f) @ x=%.1f" % [elbl[ei], eject.y, RIM_Y, eject.x])
			var in_window : int = 0
			for c in carts:
				var c3 := c as Node3D
				if absf(c3.global_position.x - eject.x) <= 0.55 and absf(c3.global_position.z - eject.z) <= 0.85:
					in_window += 1
			_check(in_window == 1,
				"S2 EXACTLY ONE cart under the %s nozzle (%d) @ x=%.1f" % [elbl[ei], in_window, eject.x])
			for e in extruders:
				var e3 := e as Node3D
				var clear : bool = absf(eject.x - e3.global_position.x) > 1.45 \
					or absf(eject.z - e3.global_position.z) > 7.15
				_check(clear, "S2 %s eject NOT over extruder footprint (eject x=%.1f vs extruder x=%.1f)" \
					% [elbl[ei], eject.x, e3.global_position.x])

	# ── S3 dynamics: chunks drop into BOTH carts, never onto the extruder ────
	var fa = filters[0]
	# Let the 2 s cart-binding cadence run so the filter binds both window carts.
	await get_tree().create_timer(2.2).timeout
	_check(fa.get("lump_cart") != null, "S3 filter bound the AISLE (+X) cart")
	_check(fa.get("lump_cart_wall") != null, "S3 filter bound the WALL (-X) cart")
	# Extrude fast: grow cap 0.05 m/call, rope breaks at 0.55 m. _grow_sausage
	# splits across BOTH active nozzles, so 80 calls ≈ 2 chunks per side.
	for i in 80:
		fa.call("_grow_sausage", 0.3, 60.0)
	var chunks_mid : int = tree.get_nodes_in_group("lump_chunk").size()
	_check(chunks_mid >= 2, "S3 CONTROL: chunks exist mid-flight (%d ≥ 2)" % chunks_mid)
	await get_tree().create_timer(2.0).timeout   # fall + settle
	var landed_ok := true
	var on_extruder := false
	var eject_a : Vector3 = fa.call("eject_global")
	var eject_w : Vector3 = fa.call("eject_global_wall")
	for ch in tree.get_nodes_in_group("lump_chunk"):
		var ch3 := ch as Node3D
		# each chunk must be at EITHER nozzle's drop column
		var at_aisle : bool = absf(ch3.global_position.x - eject_a.x) <= 0.70 and absf(ch3.global_position.z - eject_a.z) <= 1.0
		var at_wall  : bool = absf(ch3.global_position.x - eject_w.x) <= 0.70 and absf(ch3.global_position.z - eject_w.z) <= 1.0
		if not (at_aisle or at_wall):
			landed_ok = false
		for e in extruders:
			var e3 := e as Node3D
			if absf(ch3.global_position.x - e3.global_position.x) <= 1.45 \
					and absf(ch3.global_position.z - e3.global_position.z) <= 7.15:
				on_extruder = true
	_check(landed_ok, "S3 all settled chunks stayed at a nozzle drop column (in/at a cart)")
	_check(not on_extruder, "S3 NEGATIVE: no chunk on any extruder footprint")
	await get_tree().create_timer(2.5).timeout   # absorb cadence
	var chunks_left : int = tree.get_nodes_in_group("lump_chunk").size()
	_check(chunks_left == 0, "S3 settled chunks absorbed by the bound carts (%d left)" % chunks_left)

	# ── S4 assignment: role gate + full-cart task ────────────────────────────
	var board = get_node_or_null("/root/NpcAutonomyBoard")
	_check(board != null, "S4 NpcAutonomyBoard autoload present")
	var cart0 = fa.get("lump_cart")
	cart0.set("lumps_kg", 95.0)
	cart0.set("_last_received_at", -INF)   # long-cooled → is_cool() true
	if cart0.has_method("_sync_mass"): cart0.call("_sync_mass")
	board.call("_rescan")
	var romain = bench.get("npcs")["romain"]
	var vincent = bench.get("npcs")["vincent"]
	var t_leader = board.call("take_next_task", romain)
	_check(t_leader == null, "S4 NEGATIVE: shift_leader receives NO automatic task")
	var t_ar = board.call("take_next_task", vincent)
	_check(t_ar != null, "S4 all_rounder receives a task for the full cooled cart")
	if t_ar != null:
		var spath : String = t_ar.get_script().resource_path
		_check("EmptyLumpCart" in spath, "S4 ...and it IS the EmptyLumpCartTask (%s)" % spath.get_file())
		board.call("release_task", vincent)
		# npc-01 — release must UN-claim: the freed task is offerable to the
		# next asker instead of being wedged behind a stale _claimed_by.
		_check(t_ar.get("_claimed_by") == null, "S4 release_task clears the claim")
		var t_again = board.call("take_next_task", vincent)
		_check(t_again == t_ar, "S4 released task is re-offered to the next asker")
		board.call("release_task", vincent)

	# ── S5 autonomy: NPCs claim work WITHOUT manual calls ────────────────────
	await get_tree().create_timer(8.0).timeout
	var active : Dictionary = board.get("_active")
	_check(active.size() >= 1, "S5 auto-assignment: %d task(s) claimed by idle NPCs within 8 s" % active.size())

	# ── S6 force path (CrewPanel's backend) ──────────────────────────────────
	var pascal = bench.get("npcs")["pascal"]
	var ok_force : bool = board.call("force_task", pascal, "blow_leaves")
	_check(ok_force == true, "S6 force_task(blow_leaves) accepted")
	_check(pascal.get("_forced_task") != null, "S6 forced task set on the NPC (overrides gates)")
	var jerry : Array = tree.get_nodes_in_group("jerrycan")
	for j in jerry: (j as Node).free()
	var ok_refuel : bool = board.call("force_task", bench.get("npcs")["kevin"], "refuel_blower")
	_check(ok_refuel == false, "S6 NEGATIVE: refuel force fails cleanly with no jerrycan")

	# ── S7 crew systems (panel data + role assignment) ───────────────────────
	var cm = bench.get("crew_manager")
	_check((cm.get("workers") as Array).size() == 8, "S7 CrewManager holds all 8 workers")
	cm.call("manual_assign", pascal, "role:extruder_op")
	_check(String(pascal.get("npc_role")) == "extruder_op", "S7 manual_assign keeps/sets npc_role == extruder_op")
	var pinned = cm.call("pinned_station", pascal) if cm.has_method("pinned_station") else null
	_check(pinned != null and String(pinned) != "", "S7 worker pinned to the role post (panel round-trip)")
	_check((cm.call("station_list") as Array).size() > 0, "S7 station_list() non-empty (CrewPanel data source)")

	# ── S8 (#233) FEEDER = the REAL assigned NPC, not a spawned "Feeder X" ghost ─
	var yassine = bench.get("npcs")["yassine"]
	var y_name : String = String(yassine.get("npc_name"))
	cm.call("manual_assign", yassine, "role:permanent_feeder")
	await get_tree().process_frame
	await get_tree().process_frame
	var fkey := "role:permanent_feeder"
	var sfeeders : Dictionary = cm.get("_section_feeders")
	_check(sfeeders.has(fkey), "S8 a feeder shift was engaged for the assigned worker")
	var fw = sfeeders.get(fkey, null)
	if fw != null and is_instance_valid(fw):
		_check(String(fw.get("worker_name")) == y_name,
			"S8 feeder ADOPTS the real NPC's name (no 'Feeder X' ghost): '%s'" % String(fw.get("worker_name")))
		_check(not String(fw.get("worker_name")).begins_with("Feeder "),
			"S8 NEGATIVE: no generic 'Feeder …' ghost name")
	_check((cm.get("_feeder_owner") as Dictionary).get(fkey, null) == yassine,
		"S8 the feeder's owner IS the assigned NPC")
	_check(bool(yassine.get("visible")) == false,
		"S8 the assigned NPC's standing duplicate is retired (hidden)")
	# Un-assign → the feeding shift ends cleanly + the real NPC comes back on duty.
	cm.call("manual_assign", yassine, "__auto__")
	await get_tree().process_frame
	_check(not (cm.get("_section_feeders") as Dictionary).has(fkey),
		"S8 un-assign tears the feeder down (no orphan ghost)")
	_check(bool(yassine.get("visible")) == true, "S8 un-assign restores the real NPC")

	# ── S9 (npc-01) board lifecycle: a failure must not wedge the target ─────
	# The cart task is open again after S4's releases. Fail it: inside the retry
	# cooldown the failed entry HOLDS the key (negative control — no thrash);
	# once the cooldown lapses, the reap frees the key and the generator
	# re-emits a FRESH task for the same still-full cart on the same scan.
	var cart_tid : int = cart0.get_instance_id()
	var open_tasks : Dictionary = board.get("_open_tasks")
	_check(open_tasks.has(cart_tid), "S9 open task exists for the full cooled cart")
	var t_fail = open_tasks.get(cart_tid)
	if t_fail != null:
		t_fail.call("mark_failed", "test_injected")
		board.call("_rescan")
		open_tasks = board.get("_open_tasks")
		_check(open_tasks.get(cart_tid) == t_fail,
			"S9 CONTROL: failed task held as re-emit block inside the cooldown")
		t_fail.set("_failed_at", -1.0e6)   # simulate the 30 s retry cooldown lapsing
		board.call("_rescan")
		open_tasks = board.get("_open_tasks")
		var t_fresh = open_tasks.get(cart_tid)
		_check(t_fresh != null and t_fresh != t_fail,
			"S9 after the cooldown the board re-emits a FRESH task for the same cart")

	# ── S10 (phys-06) dump credit requires the cart ON the forks ─────────────
	# Unit-drive a task instance straight to the dump step (the full autopilot
	# haul is minutes of bench time). Yank the cart away → the dump must FAIL
	# and the container must NOT gain the mass; then the same step with the
	# cart riding properly DOES credit (positive control — no vacuous green).
	var elc = load("res://src/scenes/world/tasks/EmptyLumpCartTask.gd")
	var phase_dump : int = int((elc.get_script_constant_map()["Phase"] as Dictionary)["DUMP_AND_RETURN"])
	var fork_node = tree.get_nodes_in_group("forklift")[0] as Node3D
	var bin0 = tree.get_nodes_in_group("waste_container")[0]
	var yank_cart = fa.get("lump_cart_wall") as Node3D   # wall cart — unused by S4/S9
	yank_cart.set("lumps_kg", 80.0)
	yank_cart.set("_last_received_at", -INF)
	if yank_cart.has_method("_sync_mass"): yank_cart.call("_sync_mass")
	var t_yank = elc.new(yank_cart, bin0)
	t_yank.set("_forklift", fork_node)
	t_yank.set("_phase", phase_dump)
	t_yank.set("_cart_ride_dy", yank_cart.global_position.y - fork_node.global_position.y)
	# YANK: the cart "fell off" mid-haul — it lies far from the chassis.
	yank_cart.global_position = fork_node.global_position + Vector3(10.0, 0.0, 0.0)
	var bin_kg_before : float = float(bin0.get("mass_kg"))
	t_yank.call("tick", vincent, 0.016)
	_check(bool(t_yank.call("is_failed")), "S10 dump with the cart off the forks FAILS (cart_lost_in_transit)")
	_check(absf(float(bin0.get("mass_kg")) - bin_kg_before) < 0.001,
		"S10 NEGATIVE: container did NOT receive the lost cart's mass")
	_check(absf(float(yank_cart.get("lumps_kg")) - 80.0) < 0.001,
		"S10 the lost cart keeps its lumps (mass conserved where it fell)")
	# Positive control: same step with the cart genuinely riding the forks.
	yank_cart.global_position = fork_node.global_position + Vector3(0.0, 0.4, 1.0)
	var t_ride = elc.new(yank_cart, bin0)
	t_ride.set("_forklift", fork_node)
	t_ride.set("_phase", phase_dump)
	t_ride.set("_cart_ride_dy", yank_cart.global_position.y - fork_node.global_position.y)
	t_ride.call("tick", vincent, 0.016)
	_check(bool(t_ride.call("is_done")) and not bool(t_ride.call("is_failed")),
		"S10 CONTROL: dump with the cart ON the forks completes")
	_check(float(bin0.get("mass_kg")) - bin_kg_before >= 79.9,
		"S10 CONTROL: container received the dumped mass")
	_check(float(yank_cart.get("lumps_kg")) < 0.001, "S10 CONTROL: cart emptied")

	if _fails == 0:
		print("[TEST] npc task bench PASS")
	else:
		print("[TEST] npc task bench FAIL (%d)" % _fails)
	get_tree().quit(0 if _fails == 0 else 1)

func _find_by_meta(root: Node, key: String, value: String, out: Array) -> void:
	if root.has_meta(key) and String(root.get_meta(key)) == value:
		out.append(root)
	for c in root.get_children():
		_find_by_meta(c, key, value, out)
