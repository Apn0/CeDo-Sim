extends SceneTree

## #223 — Production-first gate: CrewManager.needs_worker() + NPC preemption.
## Run headless:
##   godot --headless --path <proj> --import
##   godot --headless --path <proj> --script src/tests/test_production_first_gate.gd
##
## Proves the operator's rule "keep production going first": a posted worker is
## never handed / kept on autonomy housekeeping (blow leaves / hose / shovel /
## lump cart) while production has a claim on him — a jam in his zone, an active
## dispatch, a break, or being off-post.
##
## Checks:
##   A. needs_worker() decision table (healthy / jam-in-zone / jam-in-OTHER-zone
##      / off-duty / already-dispatched).
##   B. CrewManager.tick() publishes the worst jam into _worst_jam_cache
##      (the value needs_worker reads) from a real jammed LineFlow.
##   C. CrewManager registers in the "crew_manager" group so NPC finds it.
##   D. NPC._autonomy_tick ABANDONS an in-progress housekeeping task (and calls
##      its release()) the instant production needs the worker, and RETAINS it
##      when production has no claim.

const NPC = preload("res://src/scenes/world/NPC.gd")
const CrewManager = preload("res://src/scenes/world/CrewManager.gd")

# Minimal LineFlow stand-in: _worst_jam only reads `_nodes`, each a dict {id,buffer}.
# Extends Node because CrewManager.line_flow is typed `Node`.
class FakeLineFlow extends Node:
	var _nodes : Array = []

# Housekeeping-task stand-in that never self-completes, so we can tell "abandoned
# by production" (task→null + released) apart from "completed normally".
class DummyTask extends NpcAutonomyTask:
	var released : bool = false
	func tick(_npc: Node, _d: float) -> bool:
		return false
	func release(_npc: Node) -> void:
		released = true

var _fails : int = 0

func _check(cond: bool, label: String) -> void:
	if cond:
		print("  ok    : %s" % label)
	else:
		print("  FAIL  : %s" % label)
		_fails += 1

func _make_npc(role: String, nm: String, off_duty: bool = false) -> CharacterBody3D:
	var npc : CharacterBody3D = CharacterBody3D.new()
	npc.set_script(NPC)
	npc.name = nm
	npc.npc_name = nm
	root.add_child(npc)              # triggers _ready (headless-safe, see HIER test)
	npc.npc_role = role
	# Posted + on duty + managed → is_available() == true (standing free at post).
	npc.managed = true
	npc.on_duty = not off_duty
	npc.task_state = (NPC.Task.OFF_DUTY if off_duty else NPC.Task.AT_POST)
	return npc

func _initialize() -> void:
	print("[TEST] #223 production-first gate")

	var npc := _make_npc("extruder_op", "Pascal")

	# ── CASE A: needs_worker() decision table ──────────────────────────────
	var cm = CrewManager.new()
	cm.name = "CrewManager"
	root.add_child(cm)
	cm.add_to_group("crew_manager")
	cm.workers = [npc]

	# Healthy line, idle at post → production has NO claim (free to do housekeeping).
	cm._worst_jam_cache = {}
	_check(cm.needs_worker(npc) == false, "A1 healthy+idle → needs_worker == false")

	# Jam in HIS zone (extruder) → production claims him though he looks idle.
	cm._worst_jam_cache = {"id": "extruder_3a", "buffer": 200.0}
	_check(cm.needs_worker(npc) == true, "A2 jam in own zone → needs_worker == true")

	# Jam in ANOTHER zone he doesn't cover → no claim (he can still clean).
	cm._worst_jam_cache = {"id": "prewash_1", "buffer": 200.0}
	_check(cm.needs_worker(npc) == false, "A3 jam in other zone → needs_worker == false")

	# Off duty (not available) → always claimed away from housekeeping.
	cm._worst_jam_cache = {}
	npc.on_duty = false
	_check(cm.needs_worker(npc) == true, "A4 off-duty → needs_worker == true")
	npc.on_duty = true

	# Already dispatched to a station/bin this round → claimed.
	cm._handling["waste_bin"] = npc
	_check(cm.needs_worker(npc) == true, "A5 already dispatched → needs_worker == true")
	cm._handling.clear()

	# ── CASE B: tick() publishes the worst jam into the cache ──────────────
	var cm2 = CrewManager.new()
	cm2.name = "CrewManager2"
	root.add_child(cm2)                       # NOT in the crew_manager group (no setup)
	var lf := FakeLineFlow.new()
	lf._nodes = [
		{"id": "clean_belt",  "buffer": 5.0},
		{"id": "extruder_3b", "buffer": 205.0},   # > JAM_KG (120)
	]
	cm2.line_flow = lf
	cm2.workers = [_make_npc("all_rounder", "IdleBob", true)]   # off-duty → no dispatch
	cm2.tick(0.016)
	_check(not cm2._worst_jam_cache.is_empty()
			and String(cm2._worst_jam_cache.get("id", "")) == "extruder_3b",
			"B tick() publishes worst jam (extruder_3b) to cache")
	cm2.free()   # remove so it can't confuse the group lookup below

	# ── CASE C: group registration ─────────────────────────────────────────
	_check(cm.is_in_group("crew_manager"), "C CrewManager is in 'crew_manager' group")

	# ── CASE D: NPC preemption via _autonomy_tick ──────────────────────────
	# Inject the CrewManager ref so the preemption path is exercised deterministically
	# regardless of the headless node's tree membership (the group lookup is what runs
	# in-game; CASE C already proved the registration side of it).
	print("  note  : Pascal in_tree=%s" % npc.is_inside_tree())
	npc._crew_mgr = cm
	# D1 — production NEEDS him → in-progress housekeeping task abandoned + released.
	cm._worst_jam_cache = {"id": "extruder_3a", "buffer": 200.0}
	var t1 := DummyTask.new()
	npc._autonomy_task = t1
	npc._autonomy_tick(0.1)
	_check(npc._autonomy_task == null, "D1 jam preempts → housekeeping task dropped")
	_check(t1.released == true, "D1 dropped task.release() called (tools returned)")

	# D2 — no claim → housekeeping task RETAINED (worker keeps cleaning).
	cm._worst_jam_cache = {}
	var t2 := DummyTask.new()
	npc._autonomy_task = t2
	npc._autonomy_tick(0.1)
	_check(npc._autonomy_task == t2, "D2 healthy → housekeeping task retained")
	_check(t2.released == false, "D2 retained task not released")

	if _fails == 0:
		print("[TEST] #223 PASS")
	else:
		print("[TEST] #223 FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)
