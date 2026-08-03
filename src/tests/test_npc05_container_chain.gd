extends SceneTree

## npc-05 — Container-emptying chain proof (design:
## docs/DESIGN_npc05_container_chain_2026-07-20.md §D5).
## Run headless:
##   godot --headless --path <proj> --script src/tests/test_npc05_container_chain.gd
##
## Proves the repaired chain: WasteContainer.outdoor_skip designation (D1),
## _scan_overflow_containers on the REAL groups with one task per full bin (D2),
## CrewManager out of the bin business (D3 Optie A), and outdoor-as-fallback
## destination routing incl. the handover tightening (D4).
##
## AUDIT REWRITE (2026-07-21) — the previous S5/S7 greens were vacuous and are
## replaced, not relaxed. What changed and why:
##   • The old StubForklift implemented load_bulk/unload_bulk, methods NO
##     production vehicle had. The "95 kg emptied == 95 kg received" ledger was
##     therefore performed BY THE MOCK: in a real session the mass vanished.
##     S5 now runs the SAME lifecycle twice — once against a forklift with NO
##     bulk API at all — and a static control asserts the production vehicle
##     script really declares the API.
##   • Every actor used to start inside its own arrival radius, so the task
##     completed without anything moving and _set_npc_destination /
##     _set_vehicle_destination were never called once. The actors now start
##     tens of metres apart and are stepped at a real speed, so the walk and
##     both drive legs must genuinely be travelled; the tick budget is derived
##     from the geometry INDEPENDENTLY of the task's own constants.
##   • S7 was a literal _check(true, ...). It now ticks a CrewManager that gets
##     past its empty-crew early return and asserts it leaves a full bin alone.
##   • The handover expectations were copied out of the code under test. They
##     are now pinned to the values the DESIGN states (last 3 sim-hours, bins
##     count as full from half) and probed on both sides of each boundary, so
##     the test goes red if the constant drifts instead of following it.
##
## NOTE (same gotcha as test_forced_task.gd): nodes added to `root` during
## _initialize are not in their groups until the first process_frame — all
## checks run from _run(), connected to process_frame.
##
## Stages (negative controls inline so no green is vacuous):
##   S1 no outdoor skip in world  → generator emits NOTHING, marks NOTHING seen.
##   S2 outdoor skip present      → exactly ONE task, wired indoor→outdoor;
##      second scan does not duplicate (per-bin dedup).
##   S3 second full indoor bin    → exactly TWO tasks.
##   S4 overfull skip is never an indoor source; occupied-forklift gate holds;
##      an ALREADY-OPEN task survives _rescan's prune when a forklift is taken.
##   S5 full lifecycle over real distance, twice (vehicle with and without a
##      bulk API): every leg is driven, the ledger balances, the density
##      travels, and the controls (non-full bin, refused board, abandonment)
##      all behave.
##   S6 destination routing (D4)  → open indoor wins; npc-04 exclude respected;
##      all-indoor-full → skip; handover boundaries probed both sides;
##      _find_main_world resolves the PRODUCTION current_scene branch.
##   S7 D3 structural — CrewManager has no _dispatch_for_full_bin and a ticking
##      CrewManager leaves a full bin untouched.

const Board   = preload("res://src/autoload/NpcAutonomyBoard.gd")
const WC      = preload("res://src/sim/WasteContainer.gd")
const ODT     = preload("res://src/scenes/world/tasks/OverflowDumpTask.gd")
const CrewMgr = preload("res://src/scenes/world/CrewManager.gd")
const ForkliftScript = preload("res://src/scenes/vehicles/Forklift.gd")

# ── Independently-stated spec values ─────────────────────────────────────────
# Written here from the DESIGN, not read back out of NpcAutonomyBoard. The
# checks that use them assert the production constants MATCH, so a silent
# constant change turns this test red instead of being followed.
const SPEC_HANDOVER_WINDOW_S : float = 3.0 * 60.0 * 60.0   # "last 3 sim-hours of the shift"
const SPEC_HANDOVER_FULL_AT  : float = 0.5                 # "counts as full from half, during handover"
# Physical-plausibility bounds the bench owns. Deliberately NOT the task's own
# numbers: a worker cannot climb into a forklift from across the hall, and a
# forklift cannot tip a bin it is nowhere near. They are the outer envelope —
# the drift checks below additionally pin the real constants inside them.
const PLAUSIBLE_BOARD_REACH_M : float = 3.0
const PLAUSIBLE_TIP_REACH_M   : float = 5.0
# NPC.walk_speed, and the forklift-to-plant distance the real-world run measured
# in the shipped WorldLayout. Both restated here so the phase-budget check below
# derives its requirement from the PLANT, not from the task's own constant.
const SPEC_NPC_WALK_SPEED     : float = 1.5     # m/s (NPC.gd walk_speed)
const SHIPPED_FORKLIFT_LEG_M  : float = 205.0   # measured forklift spawn → plant

# Bench locomotion speed (m/s) for the stepped actors. The bench's own number;
# the derived tick budgets below are computed from it.
const STEP_SPEED : float = 3.0
const STEP_DT    : float = 0.1

# ── Test doubles ─────────────────────────────────────────────────────────────
# Deliberately MINIMAL. The real Forklift.tscn is a 4.6 scene and is not
# --script-safe (same reasoning as StubBlower in test_forced_task.gd), so the
# bench cannot instantiate one — but it also must not paper over what the real
# one can and cannot do. Hence two variants, and a static control (S5c) that
# reads the production vehicle SCRIPT to prove the carry API exists there.

## A forklift that can carry nothing at all — no load_bulk, no unload_bulk.
## This is exactly what every shipped vehicle looked like when the old bench
## was passing, so the ledger below cannot be satisfied by vehicle cooperation.
class BareForklift extends Node3D:
	var occupied : bool = false

## A forklift that mirrors BaseVehicle's carry ledger, and records the largest
## load it ever held so "carries nothing afterwards" cannot pass by never having
## carried anything in the first place.
class CarryForklift extends Node3D:
	var occupied      : bool  = false
	var carried_bulk_kg : float = 0.0
	var carried_bulk_density : float = 0.0
	var max_seen_bulk : float = 0.0
	var load_calls    : int   = 0
	func load_bulk(kg: float, density_kg_m3: float = 0.0) -> void:
		load_calls += 1
		carried_bulk_kg += kg
		if density_kg_m3 > 0.0:
			carried_bulk_density = density_kg_m3
		max_seen_bulk = maxf(max_seen_bulk, carried_bulk_kg)
	func unload_bulk() -> float:
		var out := carried_bulk_kg
		carried_bulk_kg = 0.0
		return out

## Worker double. Unlike the old one it does not just COUNT calls — it moves.
## set_autonomy_destination steers whichever body is really being driven (the
## worker on foot, the vehicle once seated), mirroring production, where
## NPC.set_autonomy_destination routes through to BaseVehicle.npc_set_target.
class StubWorker extends CharacterBody3D:
	var npc_role      : String  = "all_rounder"
	var boarded       : int     = 0
	var disembarked   : int     = 0
	var dest_calls    : int     = 0
	var seated_in     : Node3D  = null
	var board_result  : bool    = true      # flip to false for the refusal control
	var walked_m      : float   = 0.0       # metres covered on foot
	var driven_m      : float   = 0.0       # metres covered in the vehicle
	var _target       : Vector3 = Vector3.ZERO
	var _has_target   : bool    = false

	func board_vehicle(v: Node3D) -> bool:
		if not board_result:
			return false
		boarded += 1
		seated_in = v
		if "occupied" in v:
			v.set("occupied", true)
		return true

	func disembark_vehicle() -> void:
		disembarked += 1
		if seated_in != null and "occupied" in seated_in:
			seated_in.set("occupied", false)
		seated_in = null

	func set_autonomy_destination(p: Vector3) -> void:
		dest_calls += 1
		_target = p
		_has_target = true

	## One locomotion step. Real metres — the task's arrival gates have to be
	## satisfied by actual travel, not by starting inside them.
	func step(dt: float, speed: float) -> void:
		if not _has_target:
			return
		var body : Node3D = seated_in if seated_in != null else self
		var to : Vector3 = _target - body.global_position
		var d : float = to.length()
		if d <= 0.0001:
			return
		var travel : float = minf(speed * dt, d)
		body.global_position += to.normalized() * travel
		if seated_in != null:
			driven_m += travel
			global_position = seated_in.global_position   # ride along in the cab
		else:
			walked_m += travel

## Minimal crew member so CrewManager.tick() gets past its empty-crew early
## return (CrewManager.gd:283) and actually executes its dispatch body.
class StubCrewWorker extends Node3D:
	var brain_steps : int = 0
	func step_brain(_delta: float) -> String:
		brain_steps += 1
		return ""
	func is_available() -> bool:
		return true
	func is_on_break() -> bool:
		return false

# Fake MainWorld + shift clock. `shift_elapsed_seconds` is set per probe from
# the SPEC constants above, never from the board's own window.
class FakeShiftClock extends RefCounted:
	var shift_active          : bool  = true
	var shift_elapsed_seconds : float = 0.0
	var shift_total_seconds   : float = 8.0 * 3600.0

class FakeWorld extends Node3D:
	var _player_spawn_pos : Vector3 = Vector3.ZERO   # _find_main_world() marker
	var shift_clock = null

var _fails : int = 0
var _ran   : bool = false
var _board : Node = null

func _check(cond: bool, label: String) -> void:
	if cond: print("  ok    : %s" % label)
	else: print("  FAIL  : %s" % label); _fails += 1

## A test container: gauge off (headless noise), outdoor flag BEFORE add_child
## so _ready()'s group join sees it (documented gotcha, WasteContainer.gd).
## `density` 0 leaves the container blending whatever it receives — used for the
## S5 sink so the density that ARRIVES is observable.
func _make_bin(nm: String, pos: Vector3, cap_m3: float, outdoor: bool, density: float = 100.0) -> StaticBody3D:
	var b : StaticBody3D = WC.new()
	b.name = nm
	b.show_gauge = false
	b.outdoor_skip = outdoor
	b.capacity_m3 = cap_m3
	b.override_density_kg_m3 = density     # 100 kg/m³ → kg maths stay round
	if outdoor:
		b.overflow_budget_m3 = 5.0
	root.add_child(b)
	b.position = pos
	return b

func _fill_full(b: Node) -> void:
	# capacity 1.0 m³ × 100 kg/m³ → 95 kg = fill 0.95 ≥ safe_fill 0.85.
	b.call("add", 95.0, 100.0, -1)

## Every method name reachable on `scr`, walking the whole base-script chain.
## Lets the bench interrogate a production vehicle script WITHOUT instantiating
## its scene — the check that would have caught the missing carry API.
func _script_methods(scr: Script) -> Dictionary:
	var out : Dictionary = {}
	var s : Script = scr
	while s != null:
		for d in s.get_script_method_list():
			out[String(d.get("name", ""))] = true
		s = s.get_base_script()
	return out

func _initialize() -> void:
	print("[TEST] npc-05 container chain")
	_board = Board.new()
	_board.name = "NpcAutonomyBoard"
	root.add_child(_board)
	process_frame.connect(_run)

func _run() -> void:
	if _ran:
		return
	_ran = true

	var fork := BareForklift.new()
	fork.name = "BareForklift"
	root.add_child(fork)
	fork.position = Vector3(0.5, 0.0, 0.0)
	fork.add_to_group("forklift")
	# Group joins for nodes added THIS frame need no extra wait — add_to_group
	# after add_child is immediate; only _initialize-time adds needed the defer.

	var bin_full := _make_bin("BinFull", Vector3(1.0, 0.0, 0.0), 1.0, false)
	_fill_full(bin_full)
	var bin_room := _make_bin("BinRoom", Vector3(1.5, 0.0, 0.0), 1.0, false)
	bin_room.call("add", 30.0, 100.0, -1)      # 0.30 fill — never a source

	# ── S1: no outdoor skip in the world ────────────────────────────────────
	var seen : Dictionary = {}
	_board.call("_scan_overflow_containers", self, seen)
	_check(_board._open_tasks.is_empty(), "S1 no outdoor → no task emitted")
	_check(seen.is_empty(), "S1 no outdoor → nothing marked seen (stale tasks prune)")

	# ── S2: outdoor skip present → one task, wired correctly, deduped ──────
	var skip := _make_bin("OutdoorSkip", Vector3(2.0, 0.0, 0.0), 30.0, true)
	_check(skip.is_in_group("waste_container_outdoor"), "S2 D1 flag joins waste_container_outdoor group")
	_check(skip.is_in_group("waste_container"), "S2 skip still in base waste_container group")
	seen = {}
	_board.call("_scan_overflow_containers", self, seen)
	_check(_board._open_tasks.size() == 1, "S2 exactly ONE task for one full bin (got %d)" % _board._open_tasks.size())
	var t = _board._open_tasks.get(bin_full.get_instance_id())
	_check(t != null, "S2 task keyed by the FULL bin's instance id")
	if t != null:
		_check(t.indoor_container == bin_full, "S2 task source = full indoor bin")
		_check(t.outdoor_container == skip, "S2 task destination = outdoor skip")
	seen = {}
	_board.call("_scan_overflow_containers", self, seen)
	_check(_board._open_tasks.size() == 1, "S2 rescan does not duplicate (dedup by bin iid)")
	_check(seen.has(bin_full.get_instance_id()), "S2 open task's bin still marked seen on rescan")

	# ── S3: second full bin → one task EACH ────────────────────────────────
	var bin_full2 := _make_bin("BinFull2", Vector3(1.0, 0.0, 1.0), 1.0, false)
	_fill_full(bin_full2)
	seen = {}
	_board.call("_scan_overflow_containers", self, seen)
	_check(_board._open_tasks.size() == 2, "S3 two full bins → two tasks (got %d)" % _board._open_tasks.size())

	# ── S4: skip never a source; occupied-forklift gate; prune safety ──────
	skip.call("add", 2600.0, 100.0, -1)        # 2600/3000 kg = 0.87 → is_full
	_check(bool(skip.call("is_full")), "S4 control: skip itself reads is_full")
	seen = {}
	_board.call("_scan_overflow_containers", self, seen)
	_check(_board._open_tasks.size() == 2, "S4 overfull skip emits NO task for itself")
	_check(not _board._open_tasks.has(skip.get_instance_id()), "S4 no task keyed by the skip")
	var board2 : Node = Board.new()
	board2.name = "Board2"
	root.add_child(board2)
	fork.occupied = true
	seen = {}
	board2.call("_scan_overflow_containers", self, seen)
	_check(board2._open_tasks.is_empty(), "S4 occupied forklift → gate holds, nothing emitted")

	# npc-05 REGRESSION (real-world defect): the occupied-forklift gate used to
	# return BEFORE marking any bin seen, and _rescan's stale-prune then erased
	# every dump task whose bin was not in `seen`. So the instant a worker
	# boarded a forklift to run the dump — or the operator climbed into one —
	# the in-flight task was deleted off the board (measured live as open=0
	# while active=2). Emit with an idle forklift, then take it, then run the
	# FULL _rescan the game runs and require the task to survive.
	fork.occupied = false
	seen = {}
	board2.call("_scan_overflow_containers", self, seen)
	var held_id : int = bin_full.get_instance_id()
	_check(board2._open_tasks.has(held_id), "S4 control: idle forklift → task emitted for the full bin")
	fork.occupied = true
	board2.call("_rescan")
	_check(board2._open_tasks.has(held_id),
		"S4 in-flight task SURVIVES _rescan while its forklift is occupied (prune regression)")
	# And the counter-control: a bin that genuinely LEAVES the world must still
	# be pruned, so the fix above cannot have simply disabled the prune.
	var bin_gone := _make_bin("BinGone", Vector3(1.0, 0.0, 2.0), 1.0, false)
	_fill_full(bin_gone)
	fork.occupied = false
	board2.call("_rescan")
	var gone_id : int = bin_gone.get_instance_id()
	_check(board2._open_tasks.has(gone_id), "S4 control: transient bin got its own task")
	bin_gone.free()
	board2.call("_rescan")
	_check(not board2._open_tasks.has(gone_id), "S4 prune still removes a task whose bin left the world")
	board2.free()

	# ── S5: full lifecycle over REAL distance ──────────────────────────────
	# Geometry (metres). Nothing starts inside an arrival radius, so the walk
	# leg and BOTH drive legs have to be genuinely travelled or the phases
	# cannot advance.
	var p_worker := Vector3(0.0, 0.0, 40.0)
	var p_fork   := Vector3(12.0, 0.0, 40.0)     # 12 m walk
	var p_bin    := Vector3(12.0, 0.0, 22.0)     # 18 m drive
	var p_sink   := Vector3(34.0, 0.0, 22.0)     # 22 m drive
	var leg_walk  : float = p_worker.distance_to(p_fork)
	var leg_drive : float = p_fork.distance_to(p_bin) + p_bin.distance_to(p_sink)
	# Derived INDEPENDENTLY of the task's constants: even if arrival were
	# declared the instant the actor is within the generous plausibility
	# envelope, this much ground still has to be covered.
	var min_ticks : int = int(floor(
		((leg_walk - PLAUSIBLE_BOARD_REACH_M) + (leg_drive - 2.0 * PLAUSIBLE_TIP_REACH_M))
		/ (STEP_SPEED * STEP_DT)))

	var s5a : Dictionary = _run_lifecycle("S5a bare forklift (NO bulk API)",
		BareForklift.new(), p_worker, p_fork, p_bin, p_sink, min_ticks)
	var s5b : Dictionary = _run_lifecycle("S5b carry-capable forklift",
		CarryForklift.new(), p_worker, p_fork, p_bin, p_sink, min_ticks)

	# The headline claim, now produced by PRODUCTION code on both runs: the
	# bare-forklift run is the one the old bench could never have passed,
	# because there was no mock to perform the conservation.
	for r in [s5a, s5b]:
		var tag : String = String(r["tag"])
		_check(absf(float(r["received"]) - 95.0) < 0.01,
			"%s: 95.00 kg emptied == %.2f kg received by the skip" % [tag, float(r["received"])])
		_check(float(r["source_left"]) == 0.0, "%s: source bin fully emptied" % tag)
		_check(absf(float(r["sink_density"]) - 100.0) < 0.01,
			"%s: the SOURCE density travelled with the load — sink blended %.1f kg/m3, expected the source's 100 (the dump used to hardcode 200)" %
			[tag, float(r["sink_density"])])
		_check(float(r["task_carrying"]) == 0.0, "%s: task holds no unaccounted mass afterwards" % tag)
		_check(float(r["refused"]) == 0.0,
			"%s: the skip accepted the whole load — nothing bounced back (%.2f kg refused)" % [tag, float(r["refused"])])
		_check(int(r["boarded"]) == 1 and int(r["disembarked"]) == 1,
			"%s: worker boarded and disembarked exactly once" % tag)

	# Movement actually happened — the old bench never called either setter.
	var walk_calls : int = int(s5b["dest_calls"])
	_check(walk_calls > 0, "S5 the task actually STEERED the actors (%d destination calls; the old bench made 0)" % walk_calls)
	_check(float(s5b["walked_m"]) >= leg_walk - PLAUSIBLE_BOARD_REACH_M,
		"S5 worker really walked to the forklift (%.1f m of a %.1f m leg)" % [float(s5b["walked_m"]), leg_walk])
	_check(float(s5b["driven_m"]) >= leg_drive - 2.0 * PLAUSIBLE_TIP_REACH_M,
		"S5 forklift really drove both legs (%.1f m of %.1f m)" % [float(s5b["driven_m"]), leg_drive])
	_check(int(s5b["ticks"]) >= min_ticks,
		"S5 took at least the %d ticks the geometry demands (took %d) — phases cannot have been satisfied at t=0" %
		[min_ticks, int(s5b["ticks"])])
	_check(Array(s5b["phase_order"]) == [0, 1, 2, 3, 4],
		"S5 phases ran in order WALK→DRIVE_IN→SCOOP→DRIVE_OUT→DUMP (saw %s)" % str(s5b["phase_order"]))
	# Arrival gates were genuinely satisfied, and are physically sane.
	_check(float(s5b["board_dist"]) <= PLAUSIBLE_BOARD_REACH_M,
		"S5 boarding happened within arm's reach of the forklift (%.2f m ≤ %.1f m)" %
		[float(s5b["board_dist"]), PLAUSIBLE_BOARD_REACH_M])
	_check(float(s5b["scoop_dist"]) <= PLAUSIBLE_TIP_REACH_M,
		"S5 scooping happened at the bin (%.2f m ≤ %.1f m)" % [float(s5b["scoop_dist"]), PLAUSIBLE_TIP_REACH_M])
	_check(float(s5b["dump_dist"]) <= PLAUSIBLE_TIP_REACH_M,
		"S5 dumping happened at the skip (%.2f m ≤ %.1f m)" % [float(s5b["dump_dist"]), PLAUSIBLE_TIP_REACH_M])
	# Drift guards: pin the production constants inside the plausibility envelope
	# instead of quietly inheriting whatever they become.
	_check(ODT.APPROACH_DIST_M > 0.0 and ODT.APPROACH_DIST_M <= PLAUSIBLE_BOARD_REACH_M,
		"S5 APPROACH_DIST_M (%.2f m) is still an arm's reach, not a hall's width" % ODT.APPROACH_DIST_M)
	_check(ODT.APPROACH_DIST_VEH > 0.0 and ODT.APPROACH_DIST_VEH <= PLAUSIBLE_TIP_REACH_M,
		"S5 APPROACH_DIST_VEH (%.2f m) is still a tipping distance" % ODT.APPROACH_DIST_VEH)

	# npc-05 REGRESSION: the phase budget used to be a flat 90 s, which makes any
	# leg longer than ~135 m structurally impossible to finish — and WorldLayout
	# parks the forklifts ~205 m from the plant, so every dump run in the shipped
	# layout died on "phase_timeout:0" and thrashed on the 30 s retry cooldown for
	# the whole shift. Requirement derived here, not read from the task: an NPC
	# walks at 1.5 m/s (NPC.walk_speed), so a 205 m approach needs ~137 s.
	var far_a := Node3D.new()
	var far_b := Node3D.new()
	root.add_child(far_a)
	root.add_child(far_b)
	far_a.global_position = Vector3.ZERO
	far_b.global_position = Vector3(SHIPPED_FORKLIFT_LEG_M, 0.0, 0.0)
	var probe = ODT.new(null, null)
	var far_budget : float = float(probe._travel_budget(far_a, far_b))
	var needed_s : float = SHIPPED_FORKLIFT_LEG_M / SPEC_NPC_WALK_SPEED
	_check(far_budget > needed_s,
		"S5 a %.0f m leg gets a budget (%.0f s) longer than the %.0f s it takes to walk it" %
		[SHIPPED_FORKLIFT_LEG_M, far_budget, needed_s])
	_check(absf(float(probe._travel_budget(null, null)) - ODT.PHASE_TIMEOUT_S) < 0.01,
		"S5 stationary phases still get the flat %.0f s floor" % ODT.PHASE_TIMEOUT_S)
	_check(far_budget <= ODT.PHASE_TIMEOUT_MAX_S,
		"S5 the budget is still capped (%.0f s ≤ %.0f s) — a wedged actor still dies" %
		[far_budget, ODT.PHASE_TIMEOUT_MAX_S])
	far_a.free()
	far_b.free()

	# The carry-capable vehicle was genuinely used and genuinely emptied.
	var cf : CarryForklift = s5b["fork"] as CarryForklift
	_check(cf.load_calls > 0 and cf.max_seen_bulk > 0.0,
		"S5b the vehicle's carry API was actually exercised (%d load calls, peak %.1f kg)" %
		[cf.load_calls, cf.max_seen_bulk])
	_check(cf.carried_bulk_kg == 0.0, "S5b forklift carries nothing after the dump")
	(s5a["fork"] as Node3D).free()
	cf.free()

	# ── S5c: the control that would have caught the real blocker ───────────
	# For the whole of npc-05's life, load_bulk/unload_bulk existed ONLY in
	# OverflowDumpTask's has_method() guards and in this bench's own stub. Read
	# the production vehicle script chain and require the API to be there.
	var fork_methods : Dictionary = _script_methods(ForkliftScript)
	_check(fork_methods.has("load_bulk") and fork_methods.has("unload_bulk"),
		"S5c the PRODUCTION Forklift script chain declares load_bulk + unload_bulk (the audit blocker)")
	_check(fork_methods.has("on_npc_entered") and fork_methods.has("can_enter"),
		"S5c the production Forklift is boardable (on_npc_entered + can_enter present)")

	# ── S5d: controls ──────────────────────────────────────────────────────
	var bin_ctl := _make_bin("BinCtl", Vector3(60.0, 0.0, 0.0), 1.0, false)
	bin_ctl.call("add", 30.0, 100.0, -1)
	var sink_ctl := _make_bin("SinkCtl", Vector3(62.0, 0.0, 0.0), 30.0, true, 0.0)
	var w_ctl := StubWorker.new()
	w_ctl.name = "CtlWorker"
	root.add_child(w_ctl)
	w_ctl.position = Vector3(60.0, 0.0, 2.0)
	var task_ctl = ODT.new(bin_ctl, sink_ctl)
	_check(not task_ctl.can_start(w_ctl), "S5d control: non-full bin refuses can_start")

	# Refused board: the task must FAIL and must NOT empty the bin. Before the
	# fix the board result was discarded, the phase advanced anyway, and the bin
	# was emptied into a forklift nobody was sitting in.
	var bin_rb := _make_bin("BinRefuse", Vector3(64.0, 0.0, 0.0), 1.0, false)
	_fill_full(bin_rb)
	var fork_rb := BareForklift.new()
	fork_rb.name = "ForkRefuse"
	root.add_child(fork_rb)
	fork_rb.position = Vector3(64.5, 0.0, 0.0)
	fork_rb.add_to_group("forklift")
	var w_rb := StubWorker.new()
	w_rb.name = "RefusingWorker"
	w_rb.board_result = false
	root.add_child(w_rb)
	w_rb.position = Vector3(64.0, 0.0, 0.0)
	var task_rb = ODT.new(bin_rb, sink_ctl)
	task_rb.start(w_rb)
	for _i in 40:
		if task_rb.tick(w_rb, STEP_DT):
			break
	_check(task_rb.is_failed(), "S5d refused board FAILS the task (was: silently drove on)")
	_check(float(bin_rb.mass_kg) + float(bin_rb.overflow_mass_kg) == 95.0,
		"S5d refused board leaves the source bin untouched (%.2f kg still in it)" %
		(float(bin_rb.mass_kg) + float(bin_rb.overflow_mass_kg)))
	_check(w_rb.boarded == 0, "S5d refusing worker never counted as seated")

	# Abandonment (production preempt / shift bell): release() must put the
	# worker back on his feet AND return the mass he was carrying. Before the
	# fix OverflowDumpTask had no release() override at all, so an abandoned
	# worker stayed welded into the seat with occupied=true — jamming the
	# idle-forklift gate for the rest of the session — and the scooped mass was
	# gone from the bin and held nowhere.
	var bin_ab := _make_bin("BinAbandon", Vector3(70.0, 0.0, 0.0), 1.0, false)
	_fill_full(bin_ab)
	var sink_ab := _make_bin("SinkAbandon", Vector3(90.0, 0.0, 0.0), 30.0, true, 0.0)
	var fork_ab := CarryForklift.new()
	fork_ab.name = "ForkAbandon"
	root.add_child(fork_ab)
	fork_ab.position = Vector3(70.5, 0.0, 0.0)
	fork_ab.add_to_group("forklift")
	var w_ab := StubWorker.new()
	w_ab.name = "AbandonWorker"
	root.add_child(w_ab)
	w_ab.position = Vector3(70.0, 0.0, 0.0)
	var task_ab = ODT.new(bin_ab, sink_ab)
	task_ab.start(w_ab)
	var scooped : bool = false
	for _i in 60:
		task_ab.tick(w_ab, STEP_DT)
		w_ab.step(STEP_DT, STEP_SPEED)
		if int(task_ab._phase) >= 3:      # past SCOOP_BULK, mass is aboard
			scooped = true
			break
	_check(scooped and float(bin_ab.mass_kg) + float(bin_ab.overflow_mass_kg) == 0.0,
		"S5d control: the abandonment run really did scoop the bin first")
	_check(fork_ab.occupied and w_ab.disembarked == 0, "S5d control: worker is seated at abandon time")
	task_ab.release(w_ab)
	_check(w_ab.disembarked == 1, "S5d release() disembarks the abandoned worker")
	_check(not fork_ab.occupied, "S5d release() frees the forklift (idle-forklift gate unjammed)")
	_check(absf(float(bin_ab.mass_kg) + float(bin_ab.overflow_mass_kg) - 95.0) < 0.01,
		"S5d release() returns the carried mass to the bin — nothing vanishes (%.2f kg)" %
		(float(bin_ab.mass_kg) + float(bin_ab.overflow_mass_kg)))

	# Role gate: the old bench's worker had no npc_role, so accept_roles was
	# never evaluated. Offer the task through the REAL take_next_task.
	var board3 : Node = Board.new()
	board3.name = "Board3"
	root.add_child(board3)
	var bin_role := _make_bin("BinRole", Vector3(100.0, 0.0, 0.0), 1.0, false)
	_fill_full(bin_role)
	var fork_role := CarryForklift.new()
	fork_role.name = "ForkRole"
	root.add_child(fork_role)
	fork_role.position = Vector3(100.5, 0.0, 0.0)
	fork_role.add_to_group("forklift")
	var w_wrong := StubWorker.new()
	w_wrong.name = "WrongRole"
	w_wrong.npc_role = "production_manager"      # not in OverflowDumpTask.accept_roles
	root.add_child(w_wrong)
	w_wrong.position = Vector3(100.0, 0.0, 1.0)
	var w_right := StubWorker.new()
	w_right.name = "RightRole"
	w_right.npc_role = "all_rounder"
	root.add_child(w_right)
	w_right.position = Vector3(100.0, 0.0, 2.0)
	board3.call("_rescan")
	_check(board3._open_tasks.has(bin_role.get_instance_id()), "S5d control: board3 emitted a task for the role probe")
	_check(board3.call("take_next_task", w_wrong) == null,
		"S5d accept_roles gate REFUSES a production_manager")
	var got = board3.call("take_next_task", w_right)
	_check(got != null and String(got.task_name) == "overflow_dump",
		"S5d accept_roles gate ACCEPTS an all_rounder")
	board3.free()
	for n in [bin_role, fork_role, w_wrong, w_right, bin_ctl, sink_ctl, w_ctl,
			bin_rb, fork_rb, w_rb, bin_ab, sink_ab, fork_ab, w_ab]:
		n.free()

	# ── S6: destination routing (D4) ───────────────────────────────────────
	# Clear the S2-S5 clutter so only this stage's bins are candidates.
	for n in [bin_full, bin_full2]:
		n.free()
	bin_room.free()
	var bin_a := _make_bin("BinA", Vector3(3.0, 0.0, 0.0), 1.0, false)
	bin_a.call("add", 30.0, 100.0, -1)         # 0.30 — open
	var bin_b := _make_bin("BinB", Vector3(3.5, 0.0, 0.0), 1.0, false)
	bin_b.call("add", 60.0, 100.0, -1)         # 0.60 — open (but ≥0.5 in handover)
	var dest = _board.call("_choose_lumps_destination", self)
	_check(dest == bin_a, "S6 open indoor with lowest fill wins over skip")
	dest = _board.call("_choose_lumps_destination", self, bin_a)
	_check(dest == bin_b, "S6 npc-04 exclude respected (source never destination)")
	bin_a.call("add", 65.0, 100.0, -1)         # → 0.95 full
	bin_b.call("add", 35.0, 100.0, -1)         # → 0.95 full
	dest = _board.call("_choose_lumps_destination", self)
	_check(dest == skip, "S6 all indoor full → outdoor skip is the fallback (even while overfull)")
	dest = _board.call("_choose_lumps_destination", self, skip)
	_check(dest != null and dest != skip and not dest.is_in_group("waste_container_outdoor"),
		"S6 skip-as-exclude falls back to an indoor bin")

	# ── S6b: handover, with the expectations stated by the DESIGN ──────────
	# The old check set elapsed 7 h of 8 h and asserted the skip — both numbers
	# reverse-engineered from HANDOVER_WINDOW_S, so it would have followed any
	# drift in the constant instead of catching it. Pin the constant to the
	# spec, then probe both sides of BOTH boundaries.
	_check(absf(Board.HANDOVER_WINDOW_S - SPEC_HANDOVER_WINDOW_S) < 0.01,
		"S6b HANDOVER_WINDOW_S is the documented 3 sim-hours (found %.0f s)" % Board.HANDOVER_WINDOW_S)
	# A decoy world, added to root FIRST and left in MID, so the root-children
	# fallback branch of _find_main_world returns something DIFFERENT from the
	# production current_scene branch. That makes it observable which branch ran
	# — the #audit-2026-07-08 note says the fallback is the one that returned
	# null in-game, and the old bench only ever exercised the fallback.
	var decoy := FakeWorld.new()
	decoy.name = "DecoyMidShiftWorld"
	var decoy_clock := FakeShiftClock.new()
	decoy_clock.shift_elapsed_seconds = 1.0 * 3600.0        # squarely MID
	decoy.shift_clock = decoy_clock
	root.add_child(decoy)
	var mw := FakeWorld.new()
	mw.name = "FakeMainWorld"
	var clock := FakeShiftClock.new()
	mw.shift_clock = clock
	root.add_child(mw)
	current_scene = mw

	bin_a.call("empty")
	bin_a.call("add", 60.0, 100.0, -1)         # 0.60 — open normally, full in handover
	# Boundary 1: just OUTSIDE the 3 h window → still MID → indoor bin wins.
	clock.shift_elapsed_seconds = clock.shift_total_seconds - SPEC_HANDOVER_WINDOW_S - 60.0
	dest = _board.call("_choose_lumps_destination", self)
	_check(dest == bin_a, "S6b one minute BEFORE the handover window opens, the 0.60 bin is still open")
	# Boundary 2: just INSIDE → handover tightening applies → skip.
	clock.shift_elapsed_seconds = clock.shift_total_seconds - SPEC_HANDOVER_WINDOW_S + 60.0
	dest = _board.call("_choose_lumps_destination", self)
	_check(dest == skip, "S6b one minute AFTER it opens, the 0.60 bin counts as full → outdoor skip")
	_check(int(_board.call("_shift_phase", mw)) == Board.ShiftPhase.HANDOVER,
		"S6b _find_main_world took the PRODUCTION current_scene branch (handover world, not the MID decoy)")
	# Fill boundary: the design says bins count as full from HALF during handover.
	bin_a.call("empty")
	bin_a.call("add", (SPEC_HANDOVER_FULL_AT * 100.0) - 1.0, 100.0, -1)   # 0.49
	dest = _board.call("_choose_lumps_destination", self)
	_check(dest == bin_a, "S6b handover: a bin just UNDER half is still open (fill 0.49)")
	bin_a.call("add", 2.0, 100.0, -1)                                      # 0.51
	dest = _board.call("_choose_lumps_destination", self)
	_check(dest == skip, "S6b handover: a bin just OVER half routes onward (fill 0.51)")
	# Branch control: with current_scene cleared, the fallback finds the MID
	# decoy instead — proving the two branches really do resolve differently and
	# that the greens above came from the production one.
	current_scene = null
	dest = _board.call("_choose_lumps_destination", self)
	_check(dest == bin_a and int(_board.call("_shift_phase", _board.call("_find_main_world", self))) == Board.ShiftPhase.MID,
		"S6b control: without current_scene the fallback resolves the MID decoy and routing changes")
	decoy.free()
	mw.free()

	# ── S7: D3 Optie A — CrewManager is out of the bin business ────────────
	var cm : Node = CrewMgr.new()
	cm.name = "CrewManager"
	root.add_child(cm)
	_check(not cm.has_method("_dispatch_for_full_bin"), "S7 _dispatch_for_full_bin removed from CrewManager")
	# The old check here was a literal _check(true, ...) after a tick on an
	# EMPTY crew — which returns at CrewManager.gd:283 before executing anything.
	# Give it a worker so the dispatch body really runs, and assert the property
	# D3 is about: a full indoor bin is none of CrewManager's business.
	var crew_w := StubCrewWorker.new()
	crew_w.name = "CrewWorker"
	root.add_child(crew_w)
	cm.workers = [crew_w]
	var bin_s7 := _make_bin("BinS7", Vector3(120.0, 0.0, 0.0), 1.0, false)
	_fill_full(bin_s7)
	var s7_before : float = float(bin_s7.mass_kg) + float(bin_s7.overflow_mass_kg)
	for _i in 20:
		cm.call("tick", 0.1)
	_check(crew_w.brain_steps == 20,
		"S7 CrewManager.tick() really executed its body (%d brain steps, not an early return)" % crew_w.brain_steps)
	_check(absf(float(bin_s7.mass_kg) + float(bin_s7.overflow_mass_kg) - s7_before) < 0.01,
		"S7 20 CrewManager ticks leave the full bin untouched (%.2f kg, was %.2f)" %
		[float(bin_s7.mass_kg) + float(bin_s7.overflow_mass_kg), s7_before])
	_check(not bool(cm.call("needs_worker", crew_w)),
		"S7 a full bin does not make CrewManager claim a worker (bin dispatch is gone)")

	if _fails == 0:
		print("[TEST] npc-05 container chain PASS")
	else:
		print("[TEST] npc-05 container chain FAIL (%d)" % _fails)
	quit(0 if _fails == 0 else 1)

## Drive ONE OverflowDumpTask through every phase over real ground, recording
## what actually happened. Nothing here performs the ledger: the mass moves
## because OverflowDumpTask + WasteContainer move it.
func _run_lifecycle(tag: String, fork: Node3D, p_worker: Vector3, p_fork: Vector3,
		p_bin: Vector3, p_sink: Vector3, min_ticks: int) -> Dictionary:
	fork.name = "Fork_%d" % randi()
	root.add_child(fork)
	fork.global_position = p_fork
	fork.add_to_group("forklift")
	var src := _make_bin("Src_%s" % fork.name, p_bin, 1.0, false)
	_fill_full(src)
	# Sink WITHOUT a density override, so whatever density arrives is readable.
	var sink := _make_bin("Sink_%s" % fork.name, p_sink, 30.0, true, 0.0)
	var w := StubWorker.new()
	w.name = "Worker_%s" % fork.name
	root.add_child(w)
	w.global_position = p_worker

	var task = ODT.new(src, sink)
	_check(task.can_start(w), "%s: can_start true for full source + valid sink" % tag)
	task.start(w)
	_check(not task.is_failed(), "%s: start() resolved a forklift (%s)" % [tag, task._fail_reason])

	var phase_order : Array = []
	var board_dist : float = -1.0
	var scoop_dist : float = -1.0
	var dump_dist  : float = -1.0
	var ticks : int = 0
	# Budget: 4x the derived minimum, so a stall shows up as an unfinished task
	# rather than as an infinite loop.
	var budget : int = maxi(min_ticks * 4, 400)
	for i in budget:
		ticks = i + 1
		var ph : int = int(task._phase)
		if phase_order.is_empty() or phase_order[phase_order.size() - 1] != ph:
			phase_order.append(ph)
		# Distances measured at the LAST tick of each phase, i.e. the geometry
		# the task accepted as "arrived".
		var d_bf : float = w.global_position.distance_to(fork.global_position)
		var d_fb : float = fork.global_position.distance_to(src.global_position)
		var d_fs : float = fork.global_position.distance_to(sink.global_position)
		var done : bool = task.tick(w, STEP_DT)
		var ph2 : int = int(task._phase)
		if ph == 0 and ph2 == 1:
			board_dist = d_bf
		elif ph == 1 and ph2 == 2:
			scoop_dist = d_fb
		elif ph == 3 and ph2 == 4:
			dump_dist = d_fs
		if done:
			break
		w.step(STEP_DT, STEP_SPEED)
	if phase_order.is_empty() or phase_order[phase_order.size() - 1] != int(task._phase):
		phase_order.append(int(task._phase))
	_check(task.is_done() and not task.is_failed(),
		"%s: task completed every phase (%d ticks, failed=%s '%s')" %
		[tag, ticks, str(task.is_failed()), task._fail_reason])
	var out : Dictionary = {
		"tag": tag, "fork": fork, "ticks": ticks, "phase_order": phase_order,
		"board_dist": board_dist, "scoop_dist": scoop_dist, "dump_dist": dump_dist,
		"received": float(sink.mass_kg) + float(sink.overflow_mass_kg),
		"sink_density": float(sink.blended_density),
		"source_left": float(src.mass_kg) + float(src.overflow_mass_kg),
		"task_carrying": float(task._carried_kg),
		"refused": float(task._refused_kg),
		"boarded": w.boarded, "disembarked": w.disembarked,
		"dest_calls": w.dest_calls, "walked_m": w.walked_m, "driven_m": w.driven_m,
	}
	# Every measurement above is already a value, so this stage's containers can
	# leave the world here. They MUST: S6 asserts which container the router
	# picks out of the whole tree, and a leftover empty bin (or a second outdoor
	# skip) from this run would quietly become the winning candidate.
	src.free()
	sink.free()
	w.free()
	return out
