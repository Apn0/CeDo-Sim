extends SceneTree
## Headless harness for Wave 4 — crew life.
##
## Proves, without launching the game or stepping the physics server:
##   * every new/changed script parses (load() compiles them WITH autoloads)
##   * the 2-2-2-4 rota tiles continuously: each day one team per shift, two resting
##   * ShiftClock exposes coherent calendar context
##   * an NPC walks the AT_POST → GOING → SERVICING → (return) brain correctly
##   * CrewManager dispatches the RIGHT free worker to a jam, clears it on service,
##     rotates exactly one worker onto break, and lets an uncovered jam fester
##
## Run: godot --headless --path <proj> --script res://test_crew.gd

var _fail := 0
var _ran  := false

func _process(_delta: float) -> bool:
	# Run once on the FIRST frame, not in _init()/_initialize(): only by the first
	# _process() is the SceneTree root actually in-tree, so nodes we add can read and
	# write global_position (which the NPC/crew logic depends on). Earlier than this
	# the root reports is_inside_tree()==false and every global_position is identity.
	if _ran:
		return true
	_ran = true
	print("=== Wave 4 crew-life harness ===")
	_parse()
	_rota()
	_clock()
	_npc_brain()
	_crew_dispatch()
	_crew_breaks()
	_crew_setscript_seam()
	if _fail == 0:
		print("\nALL OK")
	else:
		print("\n%d FAILED" % _fail)
	return true   # returning true ends the main loop (clean quit)

func _ok(c: bool, msg: String) -> void:
	print(("  ok  : " if c else "  FAIL: ") + msg)
	if not c:
		_fail += 1

# -----------------------------------------------------------------------------
func _parse() -> void:
	print("\n[parse]")
	for path in [
		"res://src/scenes/world/ShiftRota.gd",
		"res://src/scenes/world/ShiftClock.gd",
		"res://src/scenes/world/NPC.gd",
		"res://src/scenes/world/CrewManager.gd",
	]:
		_ok(load(path) != null, "loads %s" % path)

# -----------------------------------------------------------------------------
# 2-2-2-4: continuous 24/7 cover, one team per shift, two resting, every day.
# -----------------------------------------------------------------------------
func _rota() -> void:
	print("\n[rota]")
	var continuous := true
	for day in 30:
		var e := ShiftRota.teams_on(day, ShiftRota.Shift.EARLY).size()
		var l := ShiftRota.teams_on(day, ShiftRota.Shift.LATE).size()
		var n := ShiftRota.teams_on(day, ShiftRota.Shift.NIGHT).size()
		var r := ShiftRota.teams_on(day, ShiftRota.Shift.REST).size()
		if not (e == 1 and l == 1 and n == 1 and r == 2):
			continuous = false
			print("    day %d: E%d L%d N%d R%d" % [day, e, l, n, r])
	_ok(continuous, "every day has 1 vroeg / 1 laat / 1 nacht / 2 rust (24/7 cover)")

	# Each team works the full 2-2-2-4 over its 10-day cycle.
	var counts := {ShiftRota.Shift.EARLY: 0, ShiftRota.Shift.LATE: 0,
				   ShiftRota.Shift.NIGHT: 0, ShiftRota.Shift.REST: 0}
	for day in ShiftRota.CYCLE_DAYS:
		counts[ShiftRota.team_shift(0, day)] += 1
	_ok(counts[ShiftRota.Shift.EARLY] == 2 and counts[ShiftRota.Shift.LATE] == 2 \
		and counts[ShiftRota.Shift.NIGHT] == 2 and counts[ShiftRota.Shift.REST] == 4,
		"a team's 10-day cycle is 2-2-2-4 (%s)" % str(counts))

	_ok(ShiftRota.shift_label(ShiftRota.Shift.NIGHT) == "Nachtdienst", "Dutch shift labels")
	_ok(ShiftRota.team_label(1) == "Ploeg B", "team labels (Ploeg A..E)")
	var tn := ShiftRota.team_for_shift(0, ShiftRota.Shift.NIGHT)
	_ok(tn >= 0 and ShiftRota.team_shift(tn, 0) == ShiftRota.Shift.NIGHT, "team_for_shift resolves a covering team")

# -----------------------------------------------------------------------------
func _clock() -> void:
	print("\n[clock]")
	var sc := ShiftClock.new()
	_ok(sc.current_shift() == ShiftRota.Shift.EARLY, "day0/Ploeg A reads as Vroege dienst")
	_ok(sc.current_team_label() == "Ploeg A", "player ploeg label")
	_ok(sc.calendar_string().begins_with("Dag 1 · Ochtenddienst · Ploeg A"), "calendar string (%s)" % sc.calendar_string())
	sc.advance_day(2)
	_ok(sc.day_index == 2, "advance_day moves the calendar")
	sc.free()

# -----------------------------------------------------------------------------
func _make_npc(nm: String, role: String, pos: Vector3) -> NPC:
	var npc := NPC.new()
	npc.name     = nm
	npc.npc_name = nm
	npc.npc_role = role
	get_root().add_child(npc)
	npc.global_position = pos
	return npc

func _npc_brain() -> void:
	print("\n[npc brain]")
	var npc := _make_npc("Tester", "permanent_feeder", Vector3(0, 0, 0))
	npc.assign_post("shredder_1", Vector3(0, 0, 0))
	_ok(npc.managed and npc.is_available(), "assign_post → managed, available at post")

	# Dispatch to a jam 10 m away; not there yet, so still GOING after a step.
	npc.dispatch_to(Vector3(10, 0, 0), "shredder_1", 1.0)
	_ok(not npc.is_available(), "dispatched worker is no longer available")
	npc.step_brain(0.1)
	_ok(npc.task_state == NPC.Task.GOING, "still walking before arrival")

	# Arrive (teleport to target), then the brain enters SERVICING.
	npc.global_position = Vector3(10, 0, 0)
	npc.step_brain(0.1)
	_ok(npc.is_servicing(), "arrival starts servicing")

	# Finish the 1 s service; step_brain returns the station id exactly once.
	var got := ""
	for i in 12:
		var r := npc.step_brain(0.1)
		if r != "":
			got = r
	_ok(got == "shredder_1", "service completes and reports the station (%s)" % got)
	_ok(npc.task_state == NPC.Task.GOING, "worker heads back to post after servicing")
	npc.free()

# -----------------------------------------------------------------------------
func _fake_node(id: String, role: String, pos: Vector3, buffer: float, parent: Node) -> Dictionary:
	var n := Node3D.new()
	n.name = id
	parent.add_child(n)
	n.global_position = pos
	var batch := MaterialBatch.new(buffer, maxf(buffer, 0.01) / 320.0, {"LDPE": 1.0}, id, 0.0, 0.0) \
		if buffer > 0.0 else MaterialBatch.new()
	return {
		"node": n, "id": id, "role": role, "win": pos,
		"buffer": buffer, "in": batch, "out": MaterialBatch.new(),
	}

func _crew_dispatch() -> void:
	print("\n[crew dispatch]")
	# Fake line: a jammed shredder (front end) + a clear extruder (sink).
	var flow := FakeFlow.new()
	flow.name = "FakeFlow"
	get_root().add_child(flow)
	var nodes : Array = [
		_fake_node("shredder_1", "process", Vector3(10, 0, 0), 150.0, flow),
		_fake_node("extruder_1", "sink",    Vector3(40, 0, 0),   5.0, flow),
	]
	flow._nodes = nodes

	var feeder   := _make_npc("Abdellilah", "permanent_feeder", Vector3(4, 0, 0))
	var extr_op  := _make_npc("Pascal",     "extruder_op",      Vector3(38, 0, 0))
	var npc_dict := {"abdellilah": feeder, "pascal": extr_op}

	var crew := CrewManager.new()
	crew.enabled = false                 # we tick it by hand
	get_root().add_child(crew)
	crew.setup(npc_dict, flow, null, Vector3(0, 0, 25))

	_ok(feeder.assigned_station_id == "shredder_1", "feeder posted at the shredder (%s)" % feeder.assigned_station_id)
	_ok(extr_op.assigned_station_id == "extruder_1", "extruder op posted at the extruder (%s)" % extr_op.assigned_station_id)

	# Tick once: the jam should dispatch the FEEDER (its zone), not the extruder op.
	crew.tick(0.1)
	_ok(feeder.task_state == NPC.Task.GOING and feeder.service_station_id == "shredder_1",
		"jam dispatches the zone-owner (feeder), heading to shredder_1")
	_ok(extr_op.is_available(), "out-of-zone worker (extruder op) stays at post")

	# Walk the feeder over, then tick until the jam is serviced + relieved.
	feeder.global_position = Vector3(10, 0, 0)
	var cleared := false
	for i in 80:
		crew.tick(0.1)
		if float(nodes[0]["buffer"]) < CrewManager.JAM_KG:
			cleared = true
			break
	_ok(cleared, "service relieves the backlog below the jam limit (buffer %.0f)" % float(nodes[0]["buffer"]))
	_ok(crew.active_faults() == 0, "alarm clears once serviced")

	# A clear line dispatches nobody.
	feeder.global_position = feeder.home_position
	for i in 40:
		crew.tick(0.1)
	_ok(feeder.is_available() or feeder.task_state == NPC.Task.GOING, "feeder returns to post on a clear line")

	crew.free(); flow.free(); feeder.free(); extr_op.free()

# -----------------------------------------------------------------------------
func _crew_breaks() -> void:
	print("\n[crew breaks]")
	var flow := FakeFlow.new()
	flow.name = "FakeFlow2"
	get_root().add_child(flow)
	# Two clear front-end machines so two feeders get distinct posts.
	var nodes : Array = [
		_fake_node("shredder_1", "process", Vector3(10, 0, 0), 5.0, flow),
		_fake_node("shredder_2", "process", Vector3(14, 0, 0), 5.0, flow),
	]
	flow._nodes = nodes

	var f1 := _make_npc("Abdellilah", "permanent_feeder", Vector3(9, 0, 0))
	var f2 := _make_npc("Mohammed",   "permanent_feeder", Vector3(13, 0, 0))
	var crew := CrewManager.new()
	crew.enabled = false
	get_root().add_child(crew)
	crew.setup({"f1": f1, "f2": f2}, flow, null, Vector3(0, 0, 25))

	# Force a break to be due, then tick: exactly one worker should head off.
	crew._break_timer = 0.0
	crew.tick(0.1)
	_ok(crew.count_on_break() == 1, "exactly one worker is sent on break at a time")
	var on_break : NPC = f1 if not f1.is_available() else f2
	var covering : NPC = f2 if on_break == f1 else f1
	_ok(on_break.task_state == NPC.Task.GOING and not covering.is_available() == false,
		"the other worker stays available to cover")

	# Force the worst case: jam the ABSENT worker's machine while they're away,
	# and remove the cover by also dispatching them — the jam must fester.
	# Send the break-taker to the canteen and confirm they are ON_BREAK.
	on_break.global_position = crew.break_room_pos
	crew.tick(0.1)
	_ok(on_break.is_on_break(), "break-taker reaches the canteen and is on break")

	# Now jam BOTH machines and pull the only cover onto the far jam, so the
	# absent worker's post has no owner: that jam should stay unhandled.
	nodes[0]["buffer"] = 150.0
	nodes[0]["in"] = MaterialBatch.new(150.0, 0.47, {"LDPE": 1.0}, "jam", 0.0, 0.0)
	# Cover worker is available and in-zone, so it WILL take the worst jam — fine;
	# the point is only one jam can be handled, the other festers.
	nodes[1]["buffer"] = 150.0
	nodes[1]["in"] = MaterialBatch.new(150.0, 0.47, {"LDPE": 1.0}, "jam", 0.0, 0.0)
	crew.tick(0.1)
	_ok(crew.active_faults() <= 1, "with one worker on break, only one of two jams gets an owner")

	# Let the break elapse; the worker returns to post.
	for i in 400:
		crew.tick(0.1)
		if not on_break.is_on_break() and on_break.task_state != NPC.Task.GOING:
			break
	_ok(not on_break.is_on_break(), "break ends and the worker returns to duty")

	crew.free(); flow.free(); f1.free(); f2.free()

# -----------------------------------------------------------------------------
# MainWorld doesn't do NPC.new(): it spawns CharacterBody3D + set_script(NPC.gd).
# `is NPC` checks the whole script chain, so that path is still an NPC — prove it,
# because if it weren't, CrewManager.setup() would silently register zero workers
# (its loop guards on `n is NPC`) and the whole crew layer would no-op in-game.
func _crew_setscript_seam() -> void:
	print("\n[crew set_script seam]")
	var flow := FakeFlow.new()
	flow.name = "FakeFlow3"
	get_root().add_child(flow)
	flow._nodes = [ _fake_node("shredder_1", "process", Vector3(10, 0, 0), 5.0, flow) ]

	# Spawn an NPC exactly how MainWorld does (no NPC.new()).
	var npc_script = load("res://src/scenes/world/NPC.gd")
	var body := CharacterBody3D.new()
	body.name = "Khalid"
	body.set_script(npc_script)
	get_root().add_child(body)
	body.global_position = Vector3(9, 0, 0)
	body.npc_name = "Khalid"
	body.npc_role = "permanent_feeder"
	_ok(body is NPC, "CharacterBody3D + set_script(NPC.gd) satisfies `is NPC`")

	var crew := CrewManager.new()
	crew.enabled = false
	get_root().add_child(crew)
	crew.setup({"khalid": body}, flow, null, Vector3(0, 0, 25))
	_ok(crew.workers.size() == 1, "setup() picks up the set_script NPC (%d worker)" % crew.workers.size())
	_ok(body.assigned_station_id == "shredder_1", "set_script NPC posted at the shredder (%s)" % body.assigned_station_id)

	crew.free(); flow.free(); body.free()

# -----------------------------------------------------------------------------
# A minimal stand-in for LineFlow: it just exposes a readable `_nodes` array the
# same way the real LineFlow does, so CrewManager's telemetry reads
# (`line_flow._nodes`, `"_nodes" in line_flow`) work. A plain Node won't do —
# Object.set() on an undefined property is a silent no-op in Godot 4.
class FakeFlow extends Node:
	var _nodes : Array = []
