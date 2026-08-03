extends Node
# =============================================================================
# REPRO — catch the clamp TRANSPORTER in the act (operator 2026-07-20 sessions
# A+B: placed bale clamps keep relocating onto the z~0 scene axis; the
# "__transport__" factory copy holds the 8 relocated clamps as beads on z~0:
# x +813.6 x2 / +11.7 x2 / -763.1 x2 / +0.1 x2, all grounded).
#
# This test boots the REAL MainWorld on the __transport__ save copy, places one
# FRESH clamp at the operator's spot (-200, -8.5, 90), then REWINDS the shift
# clock to 06:19 (elapsed -2460 s — before Pascal/Vincent's T-40 arrival) and
# lets the ENTIRE pre-shift commute wave replay at time_scale 24: every NPC-car
# drive-in window (ShiftLifecycleManager teleports the VehicleBody3D cars along
# the polyline each physics frame), every PreShiftSequence arrival, the bell,
# and CrewManager posting — through to +120 game-s past the bell.
#
# Every clamp is watched per physics frame with a >2 m/frame jump detector AND
# a >5 m cumulative drift detector. On any hit, an intersect_shape sphere
# (r=3.0, mask 0xFFFFFFFF, bodies+areas) at the clamp's position logs every
# candidate PUSHER (name, path, class, layers, velocity). Parent changes are
# logged too (a reparent silently changes global_position).
#
# SAFETY: never writes world_layout.json — the AutosaveTimer (whose
# SaveCoordinator.save_game → BuildMode._save_layout → WorldLayout.save chain
# is the only writer in this scenario) is stopped right after boot and
# re-stopped every report tick; mtime is verified at the end.
#
#   GODOT --headless --path . res://src/tests/repro_transport.tscn
# =============================================================================

const TEST_SLOT := "__transport__"
const FRESH_POS := Vector3(-200.0, -8.5, 90.0)   # operator's fresh spawn this session
const JUMP_M := 2.0                               # per-frame teleport threshold
const DRIFT_M := 5.0                              # cumulative transport threshold
const REPORT_EVERY := 600                         # physics frames = 10 s engine sim
const MAX_WATCH_FRAMES := 15000                   # hard cap ≈ 250 s engine sim
const POST_BELL_GAME_S := 120.0                   # keep watching past the bell
const FF_HOUR := 6
const FF_MINUTE := 19                             # 06:19 → elapsed -2460 s: before the
                                                  # earliest arrival (pascal/vincent
                                                  # T-40 min = -2400 s) minus the 15 s
                                                  # drive-in window
const FF_TIME_SCALE := 24.0                       # operator runs 1.0 — too slow to
                                                  # cover 2 580 game-s in budget

var _world : Node3D = null
var _bm : Node = null
var _sc : Node = null
var _prev_pos : Dictionary = {}      # instance_id -> Vector3
var _start_pos : Dictionary = {}     # instance_id -> Vector3 (first seen)
var _parent_path : Dictionary = {}   # instance_id -> String
var _drift_logged : Dictionary = {}  # instance_id -> bool
var _labels : Dictionary = {}        # instance_id -> String (L1..L8 / FRESH)
var _jump_count := 0
var _drift_count := 0
var _wl_mtime_before : int = 0

func _ready() -> void:
	print("=== REPRO — clamp transporter hunt (__transport__ save) ===")
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	_wl_mtime_before = FileAccess.get_modified_time(
		ProjectSettings.globalize_path("user://world_layout.json"))

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", TEST_SLOT)
		bus.set_meta("pending_is_new_save", false)

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load"); get_tree().quit(2); return
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	_stop_autosave()   # BEFORE anything else: the 60 s autosave chain writes world_layout.json
	_watch("boot")     # snapshot the 8 loaded clamps at their saved z~0 beads
	for i in range(80):
		await get_tree().physics_frame
		_stop_autosave()
		_watch("settle")

	_bm = _world.get("build_mode")
	if _bm == null:
		print("FATAL: world.build_mode is null"); get_tree().quit(2); return
	_sc = _world.get("shift_clock")
	if _sc == null:
		print("FATAL: world.shift_clock is null"); get_tree().quit(2); return

	# ── Fresh clamp at the operator's spot (mimics this session's new spawn) ──
	var fresh := PlaceableCatalog.build_node("vehicle_baleclamp", false)
	if fresh == null:
		print("FATAL: build_node(vehicle_baleclamp) returned null"); get_tree().quit(2); return
	var placed_root : Node = _bm.get("_placed_root")
	if placed_root == null:
		print("FATAL: BuildMode._placed_root is null"); get_tree().quit(2); return
	placed_root.add_child(fresh)
	fresh.global_position = FRESH_POS
	_labels[fresh.get_instance_id()] = "FRESH"
	print("[PLACE] fresh clamp id=%d at (%.2f, %.2f, %.2f)" \
		% [fresh.get_instance_id(), FRESH_POS.x, FRESH_POS.y, FRESH_POS.z])

	_assign_labels()
	print("[CLOCK] boot state: elapsed=%.1f s active=%s time_scale=%.1f" \
		% [float(_sc.get("shift_elapsed_seconds")), str(_sc.get("shift_active")),
		float(_sc.get("time_scale"))])

	# ── Fast-forward setup: rewind to 06:19 so EVERY commute wave replays ─────
	# seek_to_wall_time emits time_jumped → ShiftLifecycleManager._on_time_jumped
	# → PreShiftSequence.recompute_for + _position_cars_for_elapsed: the REAL
	# time-jump path the live game uses.
	_sc.call("seek_to_wall_time", FF_HOUR, FF_MINUTE, false)
	_sc.set("time_scale", FF_TIME_SCALE)
	print("[CLOCK] after seek: elapsed=%.1f s (%s) time_scale=%.1f — commute wave: " \
		% [float(_sc.get("shift_elapsed_seconds")), String(_sc.call("get_time_string")),
		float(_sc.get("time_scale"))]
		+ "pascal/vincent T-40, emrah T-35, romain/mohammed T-25, yassine T-20, "
		+ "abdellilah T-17, peter T-12, kevin T-10, bell at 0")

	var frames := 0
	var reason := "frame cap (%d) reached" % MAX_WATCH_FRAMES
	while frames < MAX_WATCH_FRAMES:
		await get_tree().physics_frame
		frames += 1
		_watch("watch")
		if frames % REPORT_EVERY == 0:
			_stop_autosave()
			_report("f=%d clock=%s elapsed=%.0f" % [frames,
				String(_sc.call("get_time_string")), float(_sc.get("shift_elapsed_seconds"))])
		if float(_sc.get("shift_elapsed_seconds")) >= POST_BELL_GAME_S:
			reason = "reached +%.0f game-s past the bell" % POST_BELL_GAME_S
			break

	_report("FINAL — %s" % reason)
	print("\n=========================================")
	print("Jumps >%.0f m/frame : %d" % [JUMP_M, _jump_count])
	print("Drifts >%.0f m      : %d" % [DRIFT_M, _drift_count])
	print("Reproduced          : %s" % ("YES" if (_jump_count > 0 or _drift_count > 0) else "NO"))
	print("=========================================")
	var wl_mtime_after : int = FileAccess.get_modified_time(
		ProjectSettings.globalize_path("user://world_layout.json"))
	if wl_mtime_after != _wl_mtime_before:
		print("!!! world_layout.json mtime CHANGED during this run (%d -> %d)" \
			% [_wl_mtime_before, wl_mtime_after])
	else:
		print("world_layout.json untouched (mtime %d)" % wl_mtime_after)
	_world.queue_free()
	await get_tree().process_frame
	get_tree().quit(0)

# =============================================================================
## All placed bale clamps, wherever they live in the tree (group survives a
## reparent, unlike a _placed_root child scan).
func _clamps() -> Array:
	var out : Array = []
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is Node3D and n.has_meta("placeable_id") \
				and String(n.get_meta("placeable_id")) == "vehicle_baleclamp":
			out.append(n)
	return out

func _assign_labels() -> void:
	var idx := 0
	for c in _clamps():
		var id : int = c.get_instance_id()
		if not _labels.has(id):
			idx += 1
			_labels[id] = "L%d" % idx
	for c in _clamps():
		var id2 : int = c.get_instance_id()
		var p : Vector3 = (c as Node3D).global_position
		print("[TRACK] %s id=%d pos=(%.2f, %.2f, %.2f) parent=%s" \
			% [_labels[id2], id2, p.x, p.y, p.z, str((c as Node).get_parent().get_path())])

func _label(c: Node) -> String:
	return String(_labels.get(c.get_instance_id(), "?%d" % c.get_instance_id()))

# =============================================================================
func _watch(phase: String) -> void:
	for c in _clamps():
		var n3 := c as Node3D
		var id : int = n3.get_instance_id()
		var p : Vector3 = n3.global_position
		var par : String = str(n3.get_parent().get_path()) if n3.get_parent() != null else "<none>"
		if _parent_path.has(id) and String(_parent_path[id]) != par:
			print("[REPARENT %s] frame=%d %s: %s -> %s  pos=(%.2f, %.2f, %.2f)" \
				% [phase, Engine.get_physics_frames(), _label(n3),
				String(_parent_path[id]), par, p.x, p.y, p.z])
		_parent_path[id] = par
		if not _start_pos.has(id):
			_start_pos[id] = p
		if _prev_pos.has(id):
			var prev : Vector3 = _prev_pos[id]
			if prev.distance_to(p) > JUMP_M:
				_jump_count += 1
				_log_move("JUMP", phase, n3, prev, p)
		var sp : Vector3 = _start_pos[id]
		if not bool(_drift_logged.get(id, false)) \
				and Vector2(p.x - sp.x, p.z - sp.z).length() > DRIFT_M:
			_drift_logged[id] = true
			_drift_count += 1
			_log_move("DRIFT", phase, n3, sp, p)
		_prev_pos[id] = p

func _log_move(kind: String, phase: String, c: Node3D, from: Vector3, to: Vector3) -> void:
	var vel := Vector3.ZERO
	var frozen := false
	if c is RigidBody3D:
		vel = (c as RigidBody3D).linear_velocity
		frozen = (c as RigidBody3D).freeze
	print("[%s %s] frame=%d clock=%s %s  (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)  |v|=%.1f freeze=%s" \
		% [kind, phase, Engine.get_physics_frames(),
		String(_sc.call("get_time_string")) if _sc != null else "?",
		_label(c), from.x, from.y, from.z, to.x, to.y, to.z, vel.length(), str(frozen)])
	_probe_pushers(c, to, "at-new-pos")
	_probe_pushers(c, from, "at-old-pos")

## THE PUSHER hunt — everything physical within r=3.0 of `at`.
func _probe_pushers(c: Node3D, at: Vector3, tag: String) -> void:
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = sphere
	q.transform = Transform3D(Basis.IDENTITY, at)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_bodies = true
	q.collide_with_areas = true
	if c is CollisionObject3D:
		q.exclude = [(c as CollisionObject3D).get_rid()]
	var space : PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var hits : Array = space.intersect_shape(q, 16)
	if hits.is_empty():
		print("    [PUSHER %s] nothing within 3.0 m" % tag)
		return
	for r in hits:
		var rd : Dictionary = r
		var col : Object = rd.get("collider")
		var cn := col as Node
		if cn == null:
			continue
		var extra := ""
		if cn is RigidBody3D:
			var rb := cn as RigidBody3D
			extra = "  |v|=%.1f vel=(%.1f, %.1f, %.1f) freeze=%s" \
				% [rb.linear_velocity.length(), rb.linear_velocity.x,
				rb.linear_velocity.y, rb.linear_velocity.z, str(rb.freeze)]
		var layers := ""
		if cn is CollisionObject3D:
			var co := cn as CollisionObject3D
			layers = " layer=%d mask=%d" % [co.collision_layer, co.collision_mask]
		var cpos := Vector3.ZERO
		if cn is Node3D:
			cpos = (cn as Node3D).global_position
		print("    [PUSHER %s] %s (%s)%s pos=(%.2f, %.2f, %.2f) path=%s%s" \
			% [tag, cn.name, cn.get_class(), layers, cpos.x, cpos.y, cpos.z,
			str(cn.get_path()), extra])

# =============================================================================
func _report(tag: String) -> void:
	print("[POS %s]" % tag)
	for c in _clamps():
		var n3 := c as Node3D
		var p : Vector3 = n3.global_position
		var sp : Vector3 = _start_pos.get(n3.get_instance_id(), p)
		print("    %s pos=(%.2f, %.2f, %.2f)  moved=%.1f m" \
			% [_label(n3), p.x, p.y, p.z,
			Vector2(p.x - sp.x, p.z - sp.z).length()])
	_report_cars()

## Commute-car positions — correlate drive-in windows with clamp motion.
func _report_cars() -> void:
	var lines : Array = []
	for child in _world.get_children():
		if child is Node3D and child.has_meta("display_label"):
			var n3 := child as Node3D
			lines.append("%s vis=%s (%.1f, %.1f, %.1f)" \
				% [String(child.get_meta("display_label")), str(n3.visible),
				n3.global_position.x, n3.global_position.y, n3.global_position.z])
	if not lines.is_empty():
		print("    [CARS] " + " | ".join(lines))

## The 60 s autosave chain (SaveCoordinator.save_game → BuildMode._save_layout →
## WorldLayout.save) is the ONLY writer of world_layout.json in this scenario —
## keep it dead for the whole run. Re-called every report tick in case a
## settings_applied recreated/restarted the timer.
func _stop_autosave() -> void:
	if _world == null:
		return
	var t := _world.get_node_or_null("AutosaveTimer") as Timer
	if t != null and not t.is_stopped():
		t.stop()
		print("[SAFETY] AutosaveTimer stopped (no saves during watch)")
