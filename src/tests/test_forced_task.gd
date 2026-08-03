extends SceneTree

## #223 followup — Operator-forced NPC task override.
## Run headless:
##   godot --headless --path <proj> --import
##   godot --headless --path <proj> --script src/tests/test_forced_task.gd
##
## Proves the CrewPanel task-dropdown path: an operator can FORCE any worker onto
## a specific task via NpcAutonomyBoard.force_task(worker, kind), and that forced
## task OUTRANKS the production-first gate.
##
## NOTE: the checks run on the first process_frame, not in _initialize — nodes
## added to `root` during _initialize are not yet inside the tree (so they are
## not in their groups and get_tree() is null). By the first frame they are.
##
## Checks:
##   A. force_task(npc, "refuel_blower") returns true AND npc._forced_task is set.
##   B. Forced task survives the production-first gate (needs_worker() == true).
##   C. force_task(npc2, "blow_leaves") returns true on a fresh worker.
##   D. force_task returns FALSE for "refuel_blower" with no jerrycan (no crash).

const NPC = preload("res://src/scenes/world/NPC.gd")
const Board = preload("res://src/autoload/NpcAutonomyBoard.gd")

# Stub leaf blower: bare Node3D + the fuel vars force_task reads. The real
# LeafBlower.gd pulls in the Plant autoload, so it isn't --script-safe.
class StubBlower extends Node3D:
	var fuel_l : float = 0.5
	var fuel_capacity_l : float = 5.0
	func fuel_pct() -> float:
		return fuel_l / maxf(fuel_capacity_l, 0.001)
	func refuel(_l: float = -1.0) -> void:
		fuel_l = fuel_capacity_l

# Fake CrewManager: production-first arbiter, always claims the worker.
class FakeCrew extends Node:
	func needs_worker(_w) -> bool:
		return true

var _fails : int = 0
var _ran : bool = false
var _board : Node = null
var _blower : Node3D = null
var _jerrycan : Node3D = null
var _npc : CharacterBody3D = null
var _npc2 : CharacterBody3D = null
var _npc3 : CharacterBody3D = null

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

func _make_npc(nm: String, pos: Vector3) -> CharacterBody3D:
	var npc : CharacterBody3D = CharacterBody3D.new()
	npc.set_script(NPC)
	npc.name = nm
	npc.npc_name = nm
	npc.npc_role = "all_rounder"
	root.add_child(npc)
	npc.position = pos            # local == global under root; no in-tree needed
	npc.managed = true
	npc.on_duty = true
	npc.task_state = NPC.Task.AT_POST
	return npc

func _make_blower(pos: Vector3) -> StubBlower:
	var b := StubBlower.new()
	b.name = "StubBlower"
	root.add_child(b)
	b.position = pos
	b.add_to_group("leaf_blower")
	return b

func _make_jerrycan(pos: Vector3) -> Node3D:
	var c := Node3D.new()
	c.name = "StubJerrycan"
	root.add_child(c)
	c.position = pos
	c.add_to_group("jerrycan")
	return c

func _initialize() -> void:
	print("[TEST] forced-task override")
	_board = Board.new()
	_board.name = "NpcAutonomyBoard"
	root.add_child(_board)
	_blower = _make_blower(Vector3(0.0, 0.0, 0.0))
	_jerrycan = _make_jerrycan(Vector3(5.0, 0.0, 0.0))
	_npc  = _make_npc("Emrah", Vector3(3.0, 0.0, 0.0))
	_npc2 = _make_npc("Kevin", Vector3(2.0, 0.0, 2.0))
	_npc3 = _make_npc("Pascal", Vector3(1.0, 0.0, -2.0))
	# Defer to the first frame — everything is in-tree + in groups by then.
	process_frame.connect(_run)

func _run() -> void:
	if _ran:
		return
	_ran = true

	# ── CASE A: force a refuel task ────────────────────────────────────────
	var ok_a : bool = _board.call("force_task", _npc, "refuel_blower")
	_check(ok_a == true, "A force_task(refuel_blower) returns true")
	_check(_npc._forced_task != null, "A npc._forced_task is set after force")

	# ── CASE B: production gate must NOT abandon the forced task ────────────
	var crew := FakeCrew.new()
	crew.name = "CrewManager"
	root.add_child(crew)
	crew.add_to_group("crew_manager")
	_npc._crew_mgr = crew
	_check(crew.needs_worker(_npc) == true, "B FakeCrew.needs_worker == true (production claims)")
	_npc._autonomy_tick(0.1)
	_check(_npc._forced_task != null, "B forced task survives production-first gate")

	# ── CASE C: force a blow_leaves task on a fresh worker ─────────────────
	var ok_c : bool = _board.call("force_task", _npc2, "blow_leaves")
	_check(ok_c == true, "C force_task(blow_leaves) returns true on fresh worker")

	# ── CASE D: no jerrycan → refuel force fails cleanly ───────────────────
	_jerrycan.free()
	var ok_d : bool = _board.call("force_task", _npc3, "refuel_blower")
	_check(ok_d == false, "D force_task(refuel_blower) returns false with no jerrycan")
	_check(_npc3._forced_task == null, "D no forced task assigned when target missing")

	if _fails == 0:
		print("[TEST] forced-task PASS")
	else:
		print("[TEST] forced-task FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
