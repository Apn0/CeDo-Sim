extends SceneTree
## SHREDDER FEED BELT — public run/fault/intake API (2026-08-31 review findings).
##
## Run: godot --headless --path . --script res://src/tests/test_shredder_feed_belt_api.gd --quit-after 300
##
## Three review findings, one suite (src/scenes/world/ShredderFeedBelt.gd):
##   A  request_start()/request_stop() (:416) — flip start_requested and the
##      is_running() verdict, and are idempotent (start twice, stop twice).
##   B  is_faulted()/belt_jam_active()/reset_faults() (:541) — latches raised via
##      the code's OWN trigger (_raise_fault), read back through the public
##      getters; a latched fault kills is_running() (the latch wins over
##      start_requested); re-raising a held latch is a no-op (no signal spam);
##      reset_faults() clears all three latches.
##   C  can_accept()/accept_bale() (:605) — can_accept true on an empty ready
##      belt; a scanned lengthwise bale is accepted, REPARENTED onto the belt,
##      tracked as a rider, and its kilograms debited onto the belt ledger;
##      refusals: load-zone occupied and latched fault, each with its exact
##      reason string; an UNSCANNED bale is still physically accepted but
##      flagged untraced (#152 realism — the scan is traceability, not a gate).
##
## Scope split (no duplication): test_shredder_feed_belt.gd (committed) owns the
## held_kg() mass-conservation invariant through _process; test_feed_belt_orientation.gd
## owns the #211a cross-wise jam TIMER path. This suite owns the plain public API
## state machine — STATE only, no physics stepping, no _process ticks.
##
## require_shredder=false is the belt's own documented standalone-test escape
## hatch (see the @export comment) so is_running() reduces to
## faults + start_requested + fill — exactly the surface under test.
##
## Counted checks, never assert() — test_walkie.gd is the canonical shape: a
## failing assert aborts before quit() so the harness hangs instead of failing,
## and assert compiles out of release builds.

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

func _initialize() -> void:
	call_deferred("_run_tests")

const BELT_SCRIPT := "res://src/scenes/world/ShredderFeedBelt.gd"

## Fresh belt in the tree with the standalone escape hatch engaged. _ready()
## normally fires inside root.add_child(); the is_node_ready() guard covers a
## MainLoop-script environment where it would not, without ever double-running
## it. set_process(false): this suite asserts state, never motion — the engine
## must not tick the sim between checks.
func _make_belt() -> Node3D:
	var belt : Node3D = load(BELT_SCRIPT).new()
	belt.set("require_shredder", false)
	root.add_child(belt)
	if not belt.is_node_ready():
		belt._ready()
	belt.set_process(false)
	return belt

## A bale the belt recognises: RigidBody3D with a weight meta, rotated so its
## long axis (local +X, per the catalog size) lies along belt travel (+Z) —
## an identity-rotation bale reads ~90 deg cross-wise (#233) and would tag the
## rider for the jam timer, which is test_feed_belt_orientation.gd's scope.
## Parented into the tree FIRST (as a real world bale is) because accept_bale
## samples the PRE-reparent global_transform for the yaw check — on an
## out-of-tree node that read errors and returns identity, silently discarding
## the lengthwise rotation.
func _make_bale(scanned: bool, kg: float) -> RigidBody3D:
	var b := RigidBody3D.new()
	if scanned:
		b.set_meta("scanned", true)
	b.set_meta("weight_kg", kg)
	b.rotate_y(-PI / 2.0)
	root.add_child(b)
	return b

func _run_tests() -> void:
	print("=== ShredderFeedBelt public API tests ===")

	# ── A — request_start / request_stop (#218 HMI hooks) ─────────────────────
	print("Test: request_start / request_stop")
	var belt_a := _make_belt()
	var path_total_a : float = float(belt_a.get("_path_total"))
	_ok(path_total_a > 0.0, "A0 _ready ran: path metrics cached (non-vacuous fixture)")
	_ok(bool(belt_a.get("start_requested")), "A1 belt comes up start_requested (#218 sandbox default)")
	_ok(bool(belt_a.call("is_running")), "A2 healthy released belt reports is_running()")
	belt_a.call("request_stop")
	_ok(not bool(belt_a.get("start_requested")), "A3 request_stop() parks the belt (start_requested false)")
	_ok(not bool(belt_a.call("is_running")), "A4 parked belt is not running")
	belt_a.call("request_stop")
	_ok(not bool(belt_a.get("start_requested")) and not bool(belt_a.call("is_running")),
		"A5 request_stop() twice is idempotent — still parked")
	belt_a.call("request_start")
	_ok(bool(belt_a.get("start_requested")) and bool(belt_a.call("is_running")),
		"A6 request_start() releases the belt again")
	belt_a.call("request_start")
	_ok(bool(belt_a.get("start_requested")) and bool(belt_a.call("is_running")),
		"A7 request_start() twice is idempotent — still running")

	# ── B — fault latches: raise via the code's own trigger, read via getters ──
	print("Test: fault latches / reset_faults")
	var belt_b := _make_belt()
	_ok(not bool(belt_b.call("is_faulted")), "B1 fresh belt: is_faulted() false")
	_ok(not bool(belt_b.call("belt_jam_active"))
		and not bool(belt_b.call("intake_overfill_active"))
		and not bool(belt_b.call("thermal_shutdown_active")),
		"B2 fresh belt: all three per-fault getters clear")
	_ok(bool(belt_b.call("is_running")), "B3 pre-fault the belt runs (non-vacuity for B7)")
	var jam_ids : Array = []
	belt_b.connect("belt_jam", func(bid): jam_ids.append(String(bid)))
	belt_b.call("_raise_fault", "belt_jam", "BELT-JAM")
	_ok(bool(belt_b.call("is_faulted")), "B4 belt_jam latch sets is_faulted()")
	_ok(bool(belt_b.call("belt_jam_active")), "B5 belt_jam_active() reads the latch")
	_ok(not bool(belt_b.call("intake_overfill_active"))
		and not bool(belt_b.call("thermal_shutdown_active")),
		"B6 the other two latches stay clear")
	_ok(not bool(belt_b.call("is_running")),
		"B7 faulted belt refuses to run — latch wins over start_requested")
	var jam_once : bool = jam_ids.size() == 1
	_ok(jam_once, "B8 belt_jam signal emitted exactly once")
	_ok(jam_once and jam_ids[0] != "", "B9 belt_jam carries a non-empty belt id")
	belt_b.call("_raise_fault", "belt_jam", "BELT-JAM")
	_ok(jam_ids.size() == 1, "B10 re-raising a held latch is a no-op (no signal spam)")
	belt_b.call("_raise_fault", "intake_overfill", "INTAKE-OVERFILL")
	belt_b.call("_raise_fault", "thermal_shutdown", "THERMAL-SHUTDOWN")
	_ok(bool(belt_b.call("intake_overfill_active")) and bool(belt_b.call("thermal_shutdown_active")),
		"B11 overfill + thermal latches set via the same trigger, read via getters")
	belt_b.call("reset_faults")
	_ok(not bool(belt_b.call("is_faulted")), "B12 reset_faults() clears is_faulted()")
	_ok(not bool(belt_b.call("belt_jam_active"))
		and not bool(belt_b.call("intake_overfill_active"))
		and not bool(belt_b.call("thermal_shutdown_active")),
		"B13 reset_faults() clears all three per-fault getters")
	_ok(bool(belt_b.call("is_running")), "B14 reset belt resumes running")

	# ── C — can_accept / accept_bale gates ────────────────────────────────────
	print("Test: can_accept / accept_bale")
	var belt_c := _make_belt()
	var accepted : Array = []
	var reject_reasons : Array = []
	belt_c.connect("bale_accepted", func(b): accepted.append(b))
	belt_c.connect("bale_rejected", func(_b, reason): reject_reasons.append(String(reason)))
	_ok(bool(belt_c.call("can_accept")), "C1 empty ready belt: can_accept() true")
	_ok(bool(belt_c.call("accept_bale", null)) == false, "C2 null bale refused")
	var bale1 := _make_bale(true, 400.0)
	_ok(bool(belt_c.call("accept_bale", bale1)), "C3 scanned lengthwise bale accepted")
	_ok(int(belt_c.call("rider_count")) == 1, "C4 accepted bale tracked as a rider")
	_ok(bale1.get_parent() == belt_c, "C5 accepted bale reparented onto the belt")
	_ok(bool(bale1.get_meta("on_belt", false)), "C6 on_belt meta set (LineFlow double-draw guard)")
	_ok(is_equal_approx(float(bale1.get_meta("remaining_kg", -1.0)), 0.0),
		"C7 kilograms debited off the bale node (no double-count)")
	_ok(is_equal_approx(float(belt_c.call("held_kg")), 400.0),
		"C8 belt ledger now holds the bale's 400 kg")
	_ok(bale1.freeze == false, "C9 rigid bale left dynamic so the deck can drag it")
	_ok(int(belt_c.get("bales_accepted")) == 1, "C10 bales_accepted counter incremented")
	var acc_once : bool = accepted.size() == 1
	_ok(acc_once, "C11 bale_accepted emitted exactly once")
	_ok(acc_once and accepted[0] == bale1, "C12 bale_accepted carries the bale node")
	# Load-zone gate: the fresh rider sits at progress 0 — inside LOAD_ZONE_M.
	_ok(not bool(belt_c.call("can_accept")), "C13 rider in the load zone: can_accept() false")
	var bale2 := _make_bale(true, 300.0)
	_ok(bool(belt_c.call("accept_bale", bale2)) == false, "C14 second bale refused while zone occupied")
	var rej_once : bool = reject_reasons.size() == 1
	_ok(rej_once, "C15 refusal emitted bale_rejected")
	_ok(rej_once and reject_reasons[0] == "load zone occupied", "C16 rejection reason: load zone occupied")
	_ok(int(belt_c.call("rider_count")) == 1 and int(belt_c.get("bales_accepted")) == 1,
		"C17 refused bale neither tracked nor counted")

	# Clear the load zone to test can_accept() -> true and the lane argument
	var riders : Array = belt_c.get("_riders")
	var path_total : float = float(belt_c.get("_path_total"))
	# Advance progress so that `progress * _path_total >= LOAD_ZONE_M (which is 1.4)`
	riders[0]["progress"] = 2.0 / maxf(path_total, 1.0)
	_ok(bool(belt_c.call("can_accept")), "C17a rider cleared load zone: can_accept() true")

	# Test accept_bale lane argument
	var deck_width : float = float(belt_c.get("deck_width"))
	_ok(bool(belt_c.call("accept_bale", bale2, 1)), "C17b second bale accepted in lane 1")
	_ok(int(belt_c.call("rider_count")) == 2, "C17c second bale tracked as rider")
	var second_rider : Dictionary = riders[1]
	_ok(is_equal_approx(float(second_rider["lane_x"]), 0.5 * deck_width * 0.5), "C17d lane 1 sets lane_x offset correctly")

	# Fault gate sits BEFORE the load-zone gate in accept_bale.
	var bale3 := _make_bale(true, 350.0)
	belt_c.call("_raise_fault", "belt_jam", "BELT-JAM")
	_ok(bool(belt_c.call("accept_bale", bale3)) == false, "C18 faulted belt refuses a bale")
	var rej_twice : bool = reject_reasons.size() == 2
	_ok(rej_twice, "C19 fault refusal emitted bale_rejected")
	_ok(rej_twice and reject_reasons[1] == "belt fault", "C20 rejection reason: belt fault")
	belt_c.call("reset_faults")

	# ── D — unscanned bale: accepted-but-untraced (#152 realism) ──────────────
	print("Test: unscanned bale is untraced, not rejected")
	var belt_d := _make_belt()
	var bale_u := _make_bale(false, 250.0)
	_ok(int(belt_d.get("untraced_count")) == 0, "D1 fresh belt: untraced_count 0")
	_ok(bool(belt_d.call("accept_bale", bale_u)), "D2 unscanned bale still physically accepted")
	_ok(bool(bale_u.get_meta("untraced", false)), "D3 bale flagged untraced for the scanlog")
	_ok(int(belt_d.get("untraced_count")) == 1, "D4 untraced_count incremented")
	_ok(int(belt_d.get("bales_rejected")) == 0, "D5 traceability miss is not a physical reject")

	# Cleanup — bale1/bale_u were reparented onto their belts and free with
	# them; bale2 was refused, so it is still parented where _make_bale put it.
	root.remove_child(bale2)
	bale2.free()
	for belt in [belt_a, belt_b, belt_c, belt_d]:
		root.remove_child(belt)
		belt.free()

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)
