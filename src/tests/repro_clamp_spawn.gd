extends Node
# =============================================================================
# REPRO — operator 2026-07-20 19:13-19:27 session ("allernieuwste" save):
# 5 build-mode bale-clamp placements at the F10 marker point
# (-197.82, -9.0, 90.45) on ExteriorGroundBody. Operator saw clamps 1-4 never
# appear and clamp 5 appear at the aim point; the quit-save recorded all five
# at (0, y, 0) x3 and (332, y, 0) x2 — two deterministic stacks on the z~0
# axis, 220+ m from the aim point.
#
# This test replays the exact placement path (BuildMode._place_current on a
# ghost parked at the operator's marker point) in the REAL MainWorld and logs
# every clamp per physics frame with a >2 m/frame jump detector.
#
# HISTORY (measured, both tickrates):
#   pre-fix  : all 5 clicks placed; nested hulls shoved each other into a
#              vertical ladder (max y +1.44 clean / +4.26 at 5-FPS stall —
#              clamps parked on the building-shell overhang 10+ m up). The
#              operator-reported 220 m relocation to (0,0)/(332,0) did NOT
#              reproduce at either tickrate — BuildMode._arm_vehicle_watchdog
#              now trips loudly if it ever happens live.
#   post-fix : clearance gate refuses clicks 2..5; the single clamp rests on
#              the ground. This file asserts exactly that (PASS/FAIL).
#
#   GODOT --headless --path . res://src/tests/repro_clamp_spawn.tscn
#   CLAMPREPRO_STALL_MS=200 ...  → same, under a 5-FPS starved-frame regime
# =============================================================================

const TEST_SLOT := "__clamprepro__"
const AIM := Vector3(-197.823196, -9.0, 90.448288)   # operator's F10 marker
const CLICKS := 5
const FRAMES_BETWEEN_CLICKS := 60                     # 1 s at 60 Hz
const WATCH_FRAMES := 1800                            # 30 s after last click
                                                      # (pre-fix ladders formed
                                                      # within ~5 s; 30 s is
                                                      # ample margin)
const JUMP_M := 2.0                                   # per-frame teleport threshold

## This slot's own files. The operator's world_layout.json is not on the list:
## world saves go to the guard's scratch file, and the real one is only
## compared, never written (src/tests/world_layout_guard.gd).
const PROTECT := [
	"user://__clamprepro___save.json",
	"user://__clamprepro___factory.json",
]

const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new(TEST_SLOT, PROTECT)
var _prev_pos : Dictionary = {}    # instance_id -> Vector3
var _jump_count := 0
# CLAMPREPRO_STALL_MS=200 recreates the operator's 5-FPS session: each frame
# stalls so the engine wants ~12 physics catch-up steps but is capped at
# max_physics_steps_per_frame (8) — the delta-starved regime where deep-overlap
# depenetration behaves differently than at a healthy tickrate.
var _stall_ms := 0

func _process(_delta: float) -> void:
	if _stall_ms > 0:
		OS.delay_msec(_stall_ms)

func _ready() -> void:
	_stall_ms = int(OS.get_environment("CLAMPREPRO_STALL_MS")) \
		if OS.get_environment("CLAMPREPRO_STALL_MS") != "" else 0
	print("=== REPRO — bale clamp build-mode spawn teleport ===")
	if _stall_ms > 0:
		print("[STALL] %d ms per frame (5-FPS regime simulation)" % _stall_ms)
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
		print("FATAL: MainWorld.tscn failed to load"); _wlg.restore(); _wlg.disarm(); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for i in range(80):
		await get_tree().process_frame

	var bm : Node = world.get("build_mode")
	if bm == null:
		print("FATAL: world.build_mode is null"); _wlg.restore(); _wlg.disarm(); get_tree().quit(2); return

	# Ground truth at the aim point BEFORE any placement: what does a down-ray see?
	var space : PhysicsDirectSpaceState3D = (world as Node3D).get_world_3d().direct_space_state
	var pre := PhysicsRayQueryParameters3D.create(AIM + Vector3(0, 4, 0), AIM + Vector3(0, -4, 0))
	var pre_hit := space.intersect_ray(pre)
	if pre_hit.is_empty():
		print("[GROUND] no collider within +/-4 m of AIM — exterior ground missing here!")
	else:
		print("[GROUND] down-ray at AIM hits %s at y=%.2f" \
			% [(pre_hit["collider"] as Node).name, (pre_hit["position"] as Vector3).y])

	# Enter placing mode through the real path so ghost + state are authentic.
	bm.call("_enter_placing", "vehicle_baleclamp")
	await get_tree().process_frame
	var ghost : Node3D = bm.get("_ghost")
	if ghost == null:
		print("FATAL: ghost not built by _enter_placing"); _wlg.restore(); _wlg.disarm(); get_tree().quit(2); return

	for click in range(1, CLICKS + 1):
		# Park the ghost exactly where the operator's crosshair ray landed. The
		# live raycast is bypassed (no real input headless) — the F10 markers
		# already prove the operator's ray hit this exact point.
		ghost.visible = true
		ghost.global_position = AIM
		bm.set("_ghost_rot_y", 0.0)
		bm.call("_place_current")
		var placed := _clamps(bm)
		print("[CLICK %d] placed_total=%d" % [click, placed.size()])
		for c in placed:
			print("    clamp id=%d pos=(%.2f, %.2f, %.2f)" % [c.get_instance_id(),
				c.global_position.x, c.global_position.y, c.global_position.z])
		for f in range(FRAMES_BETWEEN_CLICKS):
			await get_tree().physics_frame
			_watch(bm, "between-clicks")

	print("[WATCH] %d clamps placed — watching %d physics frames (%.0f s sim)" \
		% [_clamps(bm).size(), WATCH_FRAMES, WATCH_FRAMES / 60.0])
	for f in range(WATCH_FRAMES):
		await get_tree().physics_frame
		_watch(bm, "watch")
		if f % 600 == 599:   # once per 10 s
			_report(bm, "t=%3.0fs" % [(f + 1) / 60.0])

	_report(bm, "FINAL")
	# ── POST-FIX EXPECTATIONS (this file is now the lasting regression) ────────
	# 1. Exactly ONE clamp: the clearance gate must refuse clicks 2..5 (each
	#    ghost sits inside clamp #1's hull). Pre-fix behaviour was 5 nested
	#    hulls that shoved each other into a vertical ladder (operator save
	#    2026-07-20: stacks at y -0.65/1.54/3.57 and 0.23/1.33).
	# 2. It rests ON THE GROUND (y < -7.5; exterior ground -9.0 + ride 0.4 +
	#    drop cushion). Pre-fix ladders parked clamps on the shell overhang at
	#    y +1.4 / +4.3, 10+ m above the floor.
	# 3. Within 3 m XZ of the click point, no >2 m/frame teleports.
	var clamps := _clamps(bm)
	var fails := 0
	if clamps.size() != 1:
		fails += 1
		print("  FAIL  : expected 1 placed clamp (gate refuses nested clicks), got %d" % clamps.size())
	else:
		print("  ok    : clearance gate — 1 placed, %d nested clicks refused" % (CLICKS - 1))
	for c in clamps:
		var gp : Vector3 = (c as Node3D).global_position
		var d : float = Vector2(gp.x - AIM.x, gp.z - AIM.z).length()
		if d > 3.0:
			fails += 1
			print("  FAIL  : clamp %.1f m XZ from click point (limit 3.0)" % d)
		else:
			print("  ok    : clamp %.1f m XZ from click point" % d)
		if gp.y > -7.5:
			fails += 1
			print("  FAIL  : clamp rests at y=%.2f — above ground (ladder/overhang regression)" % gp.y)
		else:
			print("  ok    : clamp rests on the ground (y=%.2f)" % gp.y)
	if _jump_count > 0:
		fails += 1
		print("  FAIL  : %d teleport jump(s) >%.0f m/frame observed" % [_jump_count, JUMP_M])
	else:
		print("  ok    : no per-frame teleports")
	for c in _wlg.final_checks(world):
		if c[0]:
			print("  ok    : %s" % c[1])
		else:
			fails += 1
			print("  FAIL  : %s" % c[1])

	# The verdict is printed and user:// restored BEFORE the world is freed,
	# then restored again after: the headless teardown segfault lands inside
	# world teardown (CLAUDE.md, 15 of 62 boots) and never reaches code after it.
	_wlg.restore()
	print("\n=========================================")
	print("Result: %s (%d fail)" % ["PASS" if fails == 0 else "FAIL", fails])
	print("=========================================")

	world.queue_free()
	await get_tree().process_frame
	_wlg.restore()
	_wlg.disarm()
	get_tree().quit(0 if fails == 0 else 1)

func _clamps(bm: Node) -> Array:
	var out : Array = []
	var root : Node = bm.get("_placed_root")
	if root == null:
		return out
	for c in root.get_children():
		if c is Node3D and c.has_meta("placeable_id") \
				and String(c.get_meta("placeable_id")) == "vehicle_baleclamp":
			out.append(c)
	return out

func _watch(bm: Node, phase: String) -> void:
	for c in _clamps(bm):
		var id : int = c.get_instance_id()
		var p : Vector3 = (c as Node3D).global_position
		if _prev_pos.has(id):
			var prev : Vector3 = _prev_pos[id]
			if prev.distance_to(p) > JUMP_M:
				_jump_count += 1
				var vel := Vector3.ZERO
				var frozen := false
				if c is RigidBody3D:
					vel = (c as RigidBody3D).linear_velocity
					frozen = (c as RigidBody3D).freeze
				print("[JUMP %s] frame=%d clamp=%d  (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)  |v|=%.1f freeze=%s" \
					% [phase, Engine.get_physics_frames(), id,
					prev.x, prev.y, prev.z, p.x, p.y, p.z, vel.length(), str(frozen)])
		_prev_pos[id] = p

func _report(bm: Node, tag: String) -> void:
	print("[POS %s]" % tag)
	for c in _clamps(bm):
		var d : float = Vector2((c as Node3D).global_position.x - AIM.x,
			(c as Node3D).global_position.z - AIM.z).length()
		print("    clamp=%d pos=(%.2f, %.2f, %.2f)  dist_from_aim=%.1f m" \
			% [c.get_instance_id(), c.global_position.x, c.global_position.y,
			c.global_position.z, d])

