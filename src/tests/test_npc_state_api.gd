extends SceneTree
## Headless suite for the four NPC.gd state-transition APIs flagged in the
## 2026-08-31 review:
##   (a) set_autonomy_destination / clear_autonomy_destination  (NPC.gd:61)
##   (b) assign_forced_task / clear_forced_task                 (NPC.gd:207)
##   (c) assign_post / return_to_post / clear_post              (NPC.gd:956)
##   (d) board_vehicle / disembark_vehicle                      (NPC.gd:87)
##
## Run: godot --headless --path . --script res://src/tests/test_npc_state_api.gd --quit-after 300
##
## QuietNPC overrides ONLY _ready (the name-tag / nav-agent / raycast build is
## irrelevant headless — house pattern, see test_customizer_resolves_gamestate.gd
## QuietCustomizer); every method under test is the REAL inherited NPC
## implementation. Sections (a)-(c) run with NO OperatorContext in the tree
## (the op_ctx-null branch). Section (d) adds the REAL OperatorContext (plain
## Node, light _ready) so board/disembark exercise the true npc-05 chain —
## only the VEHICLE is mocked, with exactly the surface OperatorContext probes:
## can_enter / on_npc_entered / on_npc_exited / npc_set_target / npc_stop /
## npc_autopilot.
##
## ONE push_warning from OperatorContext ("lacks on_npc_entered()") is EXPECTED
## in the output — that is the D refusal path reporting, not a failure.
##
## Counted checks, never assert(): a failing assert aborts _run_tests before
## quit() so the harness HANGS instead of going red, and assert compiles out
## of release builds. Scope split vs the other NPC suites (headers read
## 2026-08-31): test_npc_target_guard = BaseVehicle.npc_set_target's absurd-
## waypoint filter; test_npc05_realworld = full MainWorld container chain.
## Neither touches these four small state APIs directly.

const DEST_A   : Vector3 = Vector3(3.5, 0.0, -7.25)
const POST_POS : Vector3 = Vector3(-12.0, 0.0, 4.0)
const AWAY_POS : Vector3 = Vector3(20.0, 0.0, 20.0)
const DEST_D   : Vector3 = Vector3(-30.0, 0.0, 8.5)

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

## Count recorded mock calls of one method — avoids raw indexing so no check
## can crash before the verdict prints.
func _count_calls(calls: Array, method: String) -> int:
	var n := 0
	for c in calls:
		if c is Dictionary and String(c.get("method", "")) == method:
			n += 1
	return n

## Latest recorded call of one method, or {} — callers gate on has()/is checks.
func _last_call(calls: Array, method: String) -> Dictionary:
	for i in range(calls.size() - 1, -1, -1):
		var c = calls[i]
		if c is Dictionary and String(c.get("method", "")) == method:
			return c
	return {}

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== NPC state API tests (2026-08-31 review) ===")

	var npc := QuietNPC.new()
	npc.name = "TestWorker"
	root.add_child(npc)   # in-tree: set_autonomy_destination/board walk get_tree()

	# ── (a) autonomy destination — walking branch (no OperatorContext) ──────
	print("Test: (a) set/clear_autonomy_destination")
	_ok(npc.target_position == Vector3.ZERO, "baseline: target_position starts ZERO")
	_ok(npc.is_walking == false, "baseline: not walking")
	_ok(npc._autonomy_destination_active == false, "baseline: autonomy destination inactive")
	npc.set_autonomy_destination(DEST_A)
	_ok(npc.target_position.is_equal_approx(DEST_A), "set stores the vector in target_position")
	_ok(npc.is_walking == true, "set flips is_walking on")
	_ok(npc._autonomy_destination_active == true, "set raises _autonomy_destination_active")
	npc.clear_autonomy_destination()
	_ok(npc._autonomy_destination_active == false, "clear drops _autonomy_destination_active")
	_ok(npc.is_walking == false, "clear stops the walk")
	_ok(npc.target_position.is_equal_approx(DEST_A),
		"clear leaves target_position untouched (per code: it only stops steering)")

	# ── (b) forced task assign/clear ────────────────────────────────────────
	print("Test: (b) assign/clear_forced_task")
	var base_task := NpcAutonomyTask.new()   # real minimal base-class instance
	npc.assign_forced_task(base_task)
	_ok(npc._forced_task == base_task, "assign stores the task in _forced_task")
	_ok(base_task._claimed_by == npc, "assign runs the REAL base start() (task claims the NPC)")
	npc.clear_forced_task()
	_ok(npc._forced_task == null, "clear nulls _forced_task")

	var rt := RecordingTask.new()
	npc.assign_forced_task(rt)
	_ok(rt.start_calls == 1, "assign calls start() exactly once")
	_ok(npc._forced_task == rt, "recording task stored")
	npc.set_autonomy_destination(DEST_A)   # the forced task steering its NPC
	_ok(npc._autonomy_destination_active == true, "task steering active before clear")
	npc.clear_forced_task()
	_ok(rt.release_calls == 1, "clear calls the task's release() (tool dropped / vehicle exited)")
	_ok(npc._forced_task == null, "clear nulls the recording task")
	_ok(npc._autonomy_destination_active == false, "clear also clears the steering destination")
	_ok(npc.is_walking == false, "clear stops the walk")

	npc.is_walking = true
	npc.clear_forced_task()   # nothing assigned — gated body must not run
	_ok(rt.release_calls == 1, "clear with no task is a no-op (no double release)")
	_ok(npc.is_walking == true, "clear with no task does NOT touch steering flags (gated body)")
	npc.is_walking = false

	npc.assign_forced_task(rt)
	npc.assign_forced_task(null)
	_ok(npc._forced_task == null, "assign(null) empties the slot without crashing")
	_ok(rt.release_calls == 1, "assign(null) overwrites WITHOUT releasing the old task (per code)")

	# ── (c) post assign / return / clear ────────────────────────────────────
	print("Test: (c) assign_post / return_to_post / clear_post")
	npc.assign_post("extruder_3", POST_POS)
	_ok(npc.managed == true, "assign_post marks the NPC managed")
	_ok(npc.on_duty == true, "assign_post puts the NPC on duty")
	_ok(npc.assigned_station_id == "extruder_3", "assign_post stores the station id")
	_ok(npc.home_position.is_equal_approx(POST_POS), "assign_post stores the post position as home")
	_ok(npc.target_position.is_equal_approx(POST_POS), "assign_post steers toward the post")
	_ok(npc.task_state == NPC.Task.AT_POST, "assign_post sets task_state AT_POST")
	_ok(npc.is_walking == true, "assign_post starts the walk")
	_ok(npc.is_available() == true, "posted worker reports available")

	npc.target_position = AWAY_POS   # simulate having been dispatched away
	npc.walk_speed = 2.2             # simulate the prior brisk dispatch pace
	npc.return_to_post()
	_ok(npc.target_position.is_equal_approx(POST_POS), "return_to_post steers back to home_position")
	_ok(npc._purpose == NPC.Purpose.POST, "return_to_post sets Purpose.POST")
	_ok(npc.task_state == NPC.Task.GOING, "return_to_post sets task_state GOING")
	_ok(npc.is_walking == true, "return_to_post walks")
	_ok(absf(npc.walk_speed - 1.5) < 0.001, "return_to_post restores the 1.5 m/s work pace")

	npc.service_station_id = "line2_winder"   # stale service id must be wiped too
	npc.clear_post()
	_ok(npc.assigned_station_id == "", "clear_post wipes assigned_station_id")
	_ok(npc.service_station_id == "", "clear_post wipes service_station_id")
	_ok(npc.managed == true, "clear_post keeps the NPC managed (CrewManager still owns it)")
	_ok(npc.on_duty == false, "clear_post sends the worker off duty")
	_ok(npc.task_state == NPC.Task.OFF_DUTY, "clear_post parks task_state OFF_DUTY")
	_ok(npc.is_walking == false, "clear_post stops the walk")
	_ok(npc.is_available() == false, "cleared worker no longer available")

	npc.dispatch_to(AWAY_POS, "machine_4", 12.5)
	_ok(npc.service_station_id == "machine_4", "dispatch_to stores the service station id")
	_ok(npc.service_secs == 12.5, "dispatch_to stores the service duration if > 0")
	_ok(npc.target_position.is_equal_approx(AWAY_POS), "dispatch_to sets target_position")
	_ok(npc._purpose == NPC.Purpose.SERVICE, "dispatch_to sets purpose SERVICE")
	_ok(npc.task_state == NPC.Task.GOING, "dispatch_to sets task_state GOING")
	_ok(npc.is_walking == true, "dispatch_to starts walk")
	_ok(absf(npc.walk_speed - 2.2) < 0.001, "dispatch_to sets brisk 2.2 pace")

	npc.go_on_break(Vector3(10, 0, 10))
	_ok(npc.target_position.is_equal_approx(Vector3(10, 0, 10)), "go_on_break sets target_position")
	_ok(npc._purpose == NPC.Purpose.BREAK, "go_on_break sets purpose BREAK")
	_ok(npc.task_state == NPC.Task.GOING, "go_on_break sets task_state GOING")
	_ok(npc.is_walking == true, "go_on_break starts walk")
	_ok(absf(npc.walk_speed - 1.4) < 0.001, "go_on_break sets relaxed 1.4 pace")

	var callback_called := false
	npc._operate_callback = func(reason: String): callback_called = true
	npc.set_off_duty(true)
	_ok(npc.on_duty == false, "set_off_duty(true) marks on_duty false")
	_ok(npc.task_state == NPC.Task.OFF_DUTY, "set_off_duty(true) forces OFF_DUTY task_state")
	_ok(npc.is_walking == false, "set_off_duty(true) halts walk")
	_ok(npc._operate_callback.is_valid() == false, "set_off_duty(true) clears in-flight operate callback")
	_ok(callback_called == false, "cleared callback is not executed")

	npc.set_off_duty(false)
	_ok(npc.on_duty == true, "set_off_duty(false) marks on_duty true")
	_ok(npc.task_state == NPC.Task.GOING, "set_off_duty(false) from OFF_DUTY delegates to return_to_post")
	_ok(npc.target_position.is_equal_approx(POST_POS), "return_to_post targets home_position")
	_ok(npc._purpose == NPC.Purpose.POST, "return_to_post sets Purpose.POST")

	# ── (d) board/disembark via the REAL OperatorContext ────────────────────
	print("Test: (d) board_vehicle / disembark_vehicle")
	var v0 := MockVehicle.new()
	_ok(npc.board_vehicle(v0) == false,
		"board with NO OperatorContext in tree returns false (npc-05: a refused board is visible)")
	_ok(npc._seated_in_vehicle == false, "refused board leaves the NPC unseated")

	# Runtime load, NOT the OperatorContext class_name: a --script main loop is
	# compiled BEFORE autoloads register, and OperatorContext.gd references the
	# EventBus autoload as a bare identifier (OperatorContext.gd:73) — a compile-
	# time reference here caches a failed compile and .new() then blows up.
	# load() at runtime compiles it after the autoloads exist (test_walkie.gd
	# does the same with Walkie.gd).
	var op_ctx: Node = load("res://src/operator/OperatorContext.gd").new()
	op_ctx.name = "OperatorContext"
	root.add_child(op_ctx)

	_ok(npc.board_vehicle(null) == false, "board(null) refused")

	var v_bare := Node3D.new()   # lacks on_npc_entered — the EXPECTED warning
	_ok(npc.board_vehicle(v_bare) == false,
		"vehicle without on_npc_entered() refused (push_warning above is expected)")

	var v_refuse := MockVehicle.new()
	v_refuse.can_enter_result = false
	_ok(npc.board_vehicle(v_refuse) == false, "vehicle refusing can_enter() -> board false")
	_ok(_count_calls(v_refuse.calls, "on_npc_entered") == 0, "refused vehicle never told on_npc_entered")
	_ok(npc._seated_in_vehicle == false, "refusal leaves _seated_in_vehicle false")
	_ok(npc.visible == true, "refusal leaves the walking body visible")

	var v1 := MockVehicle.new()
	_ok(npc.board_vehicle(v1) == true, "board of a willing vehicle returns true")
	_ok(npc._seated_in_vehicle == true,
		"board flips _seated_in_vehicle (locomotion parks, decision layer stays alive)")
	_ok(npc.visible == false, "board hides the walking body")
	_ok(op_ctx.npc_vehicle_of(npc) == v1, "OperatorContext records the npc->vehicle link")
	var v1_entered: bool = _count_calls(v1.calls, "on_npc_entered") == 1
	_ok(v1_entered, "vehicle told on_npc_entered exactly once")
	_ok(v1_entered and _last_call(v1.calls, "on_npc_entered").get("npc") == npc,
		"on_npc_entered received THIS npc")

	# While boarded, set_autonomy_destination must route to the CHASSIS (#202).
	var prev_target  := npc.target_position
	var prev_walking : bool = npc.is_walking
	var prev_active  : bool = npc._autonomy_destination_active
	npc.set_autonomy_destination(DEST_D)
	var routed: bool = _count_calls(v1.calls, "npc_set_target") == 1
	_ok(routed, "boarded set_autonomy_destination routes to vehicle.npc_set_target")
	var routed_pos = _last_call(v1.calls, "npc_set_target").get("pos", null)
	_ok(routed and routed_pos is Vector3 and (routed_pos as Vector3).is_equal_approx(DEST_D),
		"vehicle received the exact destination")
	_ok(npc.target_position.is_equal_approx(prev_target),
		"boarded routing leaves the walking target_position untouched")
	_ok(npc.is_walking == prev_walking, "boarded routing leaves is_walking untouched")
	_ok(npc._autonomy_destination_active == prev_active,
		"boarded routing leaves _autonomy_destination_active untouched")

	# Second board while seated — per code it re-registers to the new chassis
	# and never releases the first (v1 gets no on_npc_exited).
	var v2 := MockVehicle.new()
	_ok(npc.board_vehicle(v2) == true, "second board while seated returns true (per code)")
	_ok(op_ctx.npc_vehicle_of(npc) == v2, "link overwritten to the second vehicle")
	_ok(_count_calls(v1.calls, "on_npc_exited") == 0, "first vehicle NOT exited on overwrite (per code)")
	_ok(npc._seated_in_vehicle == true, "still seated after the re-board")

	npc.disembark_vehicle()
	_ok(npc._seated_in_vehicle == false, "disembark clears _seated_in_vehicle")
	_ok(npc.visible == true, "disembark shows the walking body again")
	_ok(op_ctx.npc_vehicle_of(npc) == null, "disembark unregisters the npc->vehicle link")
	_ok(_count_calls(v2.calls, "npc_stop") == 1, "disembark stops the autopilot")
	_ok(_count_calls(v2.calls, "on_npc_exited") == 1, "vehicle told on_npc_exited exactly once")
	_ok(v2.npc_autopilot == false, "disembark drops the chassis npc_autopilot flag")

	var v2_calls_before := v2.calls.size()
	npc.disembark_vehicle()
	_ok(v2.calls.size() == v2_calls_before, "second disembark is a no-op (not seated)")
	_ok(npc._seated_in_vehicle == false, "still unseated after the no-op disembark")

	# ── (e) forced task autonomy tick ───────────────────────────────────────
	print("Test: (e) forced task _autonomy_tick")
	var t_tick := RecordingTask.new()
	npc.assign_forced_task(t_tick)
	npc._autonomy_tick(0.1)
	_ok(t_tick.tick_calls == 1, "_autonomy_tick calls tick() on the forced task")
	_ok(npc._forced_task == t_tick, "task stays active if tick returns false and is_done is false")

	t_tick.mock_tick_ret = true
	npc._autonomy_tick(0.1)
	_ok(t_tick.tick_calls == 2, "second _autonomy_tick calls tick() again")
	_ok(npc._forced_task == null, "_autonomy_tick clears the forced task if tick() returns true")
	_ok(t_tick.release_calls == 1, "clearing via tick() return value calls release()")

	var t_done := RecordingTask.new()
	npc.assign_forced_task(t_done)
	t_done.mock_done = true
	npc._autonomy_tick(0.1)
	_ok(t_done.tick_calls == 0, "_autonomy_tick does not call tick() if is_done() is already true")
	_ok(npc._forced_task == null, "_autonomy_tick clears the forced task if is_done() is true")
	_ok(t_done.release_calls == 1, "clearing via is_done() calls release()")

	# Cleanup — free every node we created; verdict prints LAST, after teardown.
	root.remove_child(npc)
	npc.free()
	root.remove_child(op_ctx)
	op_ctx.free()
	v0.free()
	v_bare.free()
	v_refuse.free()
	v1.free()
	v2.free()
	base_task = null
	rt = null

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)

## House-approved quiet subclass: skips ONLY the _ready scene build (name tag,
## nav agent, raycasts) which needs nothing under test here. All four APIs and
## everything they call remain the real inherited NPC implementation.
class QuietNPC extends NPC:
	func _ready() -> void:
		pass

## Real base-class task that records its lifecycle calls, then defers to the
## REAL NpcAutonomyTask implementation via super — proves NPC.clear_forced_task
## actually invokes release() (the tool-drop / vehicle-exit hook).
class RecordingTask extends NpcAutonomyTask:
	var start_calls   : int = 0
	var release_calls : int = 0

	func start(npc: Node) -> void:
		start_calls += 1
		super.start(npc)

	func release(npc: Node) -> void:
		release_calls += 1
		super.release(npc)

	var tick_calls    : int = 0
	var mock_done     : bool = false
	var mock_tick_ret : bool = false

	# `_npc` / `_delta`, not `npc` / `delta`. This mock ignores both, and
	# tools/regression/run.sh's unused-parameter lint is a GATE, not a warning:
	# it aborts the entire harness before a single suite runs. That has now
	# happened twice in one day — #197 with one parameter, #210 with these two —
	# so the underscore is load-bearing, not style.
	func tick(_npc: Node, _delta: float) -> bool:
		tick_calls += 1
		return mock_tick_ret

	func is_done() -> bool:
		return mock_done

## Mocks exactly the surface OperatorContext probes on a vehicle during
## npc_board_vehicle / npc_disembark_vehicle / npc_vehicle_of routing:
## can_enter, on_npc_entered, on_npc_exited, npc_set_target, npc_stop and the
## npc_autopilot property (OperatorContext sets it false on disembark).
class MockVehicle extends Node3D:
	var calls : Array = []
	var can_enter_result : bool = true
	var npc_autopilot : bool = true

	func can_enter() -> bool:
		calls.append({"method": "can_enter"})
		return can_enter_result

	func on_npc_entered(npc: Node) -> void:
		calls.append({"method": "on_npc_entered", "npc": npc})

	func on_npc_exited(npc: Node) -> void:
		calls.append({"method": "on_npc_exited", "npc": npc})

	func npc_set_target(pos: Vector3) -> void:
		calls.append({"method": "npc_set_target", "pos": pos})

	func npc_stop() -> void:
		calls.append({"method": "npc_stop"})
