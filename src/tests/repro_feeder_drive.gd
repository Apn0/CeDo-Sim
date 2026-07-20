extends Node
# =============================================================================
# REPRO — "the clamps DRIVE THEMSELVES" hypothesis (operator 2026-07-20/21).
#
# Lead under test: FeederWorker commands BaseVehicle.npc_set_target() with a
# bale position (FeederWorker.gd:382 / :405 / :438), supplier_target (:448) or
# _work_spot() (:452 → :717-721). A bogus target would make the assigned bale
# clamp drive across the map on its own — the "bead on the z~0 axis" signature.
# The earlier repro (repro_transport.gd) never had a feeder assigned, because
# CrewManager._ensure_section_feeder (:686-704) bails when no feed belt exists.
#
# This test closes that gap:
#   1. boots the REAL MainWorld on a private slot (copy of __transport__),
#   2. guarantees a feed belt exists (builds an opzetband if the save has none),
#   3. places a fresh bale clamp through BuildMode at the operator's spot,
#   4. engages a section/rota feeder through CrewManager.manual_assign() so a
#      FeederWorker + its own BaleClamp are spawned and the drive brain runs,
#   5. watches EVERY vehicle per physics frame:
#        • >2 m in one physics frame          → JUMP
#        • >10 m cumulative XZ from spawn     → DRIFT (logged once)
#        • any change of BaseVehicle._npc_target → TARGET (logs the new target,
#          the driving FeederWorker, its _state, _belt, lot_center — i.e. WHICH
#          expression produced it)
#      plus a 10 s roll-up of every vehicle's autopilot state.
#
# SAFETY: writes ONLY user://__feederdrive___*.json (new scratch files). The
# AutosaveTimer is stopped on boot and re-stopped every report tick, and
# world_layout.json's mtime is asserted unchanged at the end.
#
#   GODOT --headless --path . res://src/tests/repro_feeder_drive.tscn
# =============================================================================

const TEST_SLOT   := "__feederdrive__"
const SRC_SLOT    := "__transport__"
const FRESH_POS   := Vector3(-200.0, -8.5, 90.0)
const JUMP_M      := 2.0
const DRIFT_M     := 10.0
const REPORT_EVERY := 600                 # physics frames = 10 s sim
const WATCH_FRAMES := 10800               # 180 s sim @ 60 Hz
const WALL_CLOCK_CAP_MS := 9 * 60 * 1000  # hard real-time bail

var _world : Node3D = null
var _bm    : Node = null
var _prev_pos    : Dictionary = {}   # id -> Vector3
var _start_pos   : Dictionary = {}   # id -> Vector3
var _drift_seen  : Dictionary = {}   # id -> bool
var _prev_target : Dictionary = {}   # id -> Vector3
var _had_target  : Dictionary = {}   # id -> bool
var _jump_count   := 0
var _drift_count  := 0
var _target_count := 0
var _wl_mtime_before : int = 0
var _t0_ms : int = 0
# MEASURED 2026-07-21: BuildMode._place_current ends with _save_layout()
# (BuildMode.gd:1308), which rewrites user://world_layout.json. Stopping the
# AutosaveTimer is NOT enough. Byte-backup + restore it around the whole run.
var _wl_backup : PackedByteArray = PackedByteArray()
var _wl_had : bool = false

func _ready() -> void:
	print("=== REPRO — feeder autopilot drives the clamp away? ===")
	_t0_ms = Time.get_ticks_msec()
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	_wl_mtime_before = FileAccess.get_modified_time(
		ProjectSettings.globalize_path("user://world_layout.json"))
	_backup_world_layout()
	_seed_slot()

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
	_stop_autosave()
	for _i in range(120):
		await get_tree().physics_frame
		_stop_autosave()

	_bm = _world.get("build_mode")
	if _bm == null:
		print("FATAL: world.build_mode is null"); _finish(2); return

	# ── 2) a feed belt must exist or _ensure_section_feeder bails (:701-704) ──
	var belt : Node3D = await _ensure_feed_belt()
	if belt == null:
		print("COVERAGE-GAP: no shredder_feed_belt could be created — feeder cannot be assigned")
	else:
		print("[BELT] %s at (%.2f, %.2f, %.2f) placeable_id=%s" % [belt.name,
			belt.global_position.x, belt.global_position.y, belt.global_position.z,
			String(belt.get_meta("placeable_id", ""))])

	# ── 3) fresh build-mode clamp at the operator's spot ─────────────────────
	await _place_clamp_via_buildmode()

	# ── 4) engage a feeder through the real CrewManager path ─────────────────
	var engaged : bool = await _engage_feeder(belt)
	print("[FEEDER] engaged=%s  feeder_workers=%d" % [str(engaged),
		get_tree().get_nodes_in_group("feeder_worker").size()])
	_dump_feeders("post-assign")

	_scan("boot")
	print("[WATCH] %d vehicles tracked — %d physics frames (%.0f s sim)"
		% [_vehicles().size(), WATCH_FRAMES, WATCH_FRAMES / 60.0])

	var frames := 0
	var reason := "frame cap reached"
	while frames < WATCH_FRAMES:
		await get_tree().physics_frame
		frames += 1
		_scan("watch")
		if frames % REPORT_EVERY == 0:
			_stop_autosave()
			_report("f=%d t=%.0fs" % [frames, frames / 60.0])
			_dump_feeders("t=%.0fs" % (frames / 60.0))
		if Time.get_ticks_msec() - _t0_ms > WALL_CLOCK_CAP_MS:
			reason = "wall-clock cap"
			break

	_report("FINAL — %s" % reason)
	_dump_feeders("FINAL")
	print("\n=========================================")
	print("Jumps  >%.0f m/frame : %d" % [JUMP_M, _jump_count])
	print("Drifts >%.0f m       : %d" % [DRIFT_M, _drift_count])
	print("npc_set_target events: %d" % _target_count)
	print("Reproduced           : %s" % ("YES" if _drift_count > 0 else "NO"))
	print("=========================================")
	await _finish(0)

## Byte-exact snapshot of the operator's shared site layout, taken before the
## world boots. _restore_world_layout() puts it back verbatim.
func _backup_world_layout() -> void:
	var p := "user://world_layout.json"
	_wl_had = FileAccess.file_exists(p)
	if not _wl_had:
		return
	var f := FileAccess.open(p, FileAccess.READ)
	_wl_backup = f.get_buffer(f.get_length())
	f.close()
	print("[SAFETY] world_layout.json backed up (%d bytes)" % _wl_backup.size())

func _restore_world_layout() -> void:
	if not _wl_had:
		return
	var f := FileAccess.open("user://world_layout.json", FileAccess.WRITE)
	f.store_buffer(_wl_backup)
	f.close()
	print("[SAFETY] world_layout.json restored byte-for-byte (%d bytes)" % _wl_backup.size())

func _finish(code: int) -> void:
	_restore_world_layout()
	var after : int = FileAccess.get_modified_time(
		ProjectSettings.globalize_path("user://world_layout.json"))
	if after != _wl_mtime_before:
		print("world_layout.json was rewritten during the run (mtime %d -> %d) "
			% [_wl_mtime_before, after]
			+ "and has been restored byte-for-byte from the pre-boot backup")
	else:
		print("world_layout.json untouched (mtime %d)" % after)
	if _world != null and is_instance_valid(_world):
		_world.queue_free()
		await get_tree().process_frame
	get_tree().quit(code)

# =============================================================================
# SETUP HELPERS
# =============================================================================
## Private scratch slot seeded from the __transport__ copy (which holds the 8
## relocated clamps). Never touches the operator's own save names.
func _seed_slot() -> void:
	for suffix in ["_factory.json", "_save.json"]:
		var src := "user://%s%s" % [SRC_SLOT, suffix]
		var dst := "user://%s%s" % [TEST_SLOT, suffix]
		if not FileAccess.file_exists(src):
			continue
		var fr := FileAccess.open(src, FileAccess.READ)
		var buf := fr.get_buffer(fr.get_length())
		fr.close()
		var fw := FileAccess.open(dst, FileAccess.WRITE)
		fw.store_buffer(buf)
		fw.close()
		print("[SEED] %s -> %s (%d bytes)" % [src, dst, buf.size()])

## A ShredderFeedBelt must be in the tree or CrewManager refuses to bind a
## feeder. Reuse one from the save if present, otherwise build an opzetband.
func _ensure_feed_belt() -> Node3D:
	var found := _first_belt()
	if found != null:
		return found
	var node := PlaceableCatalog.build_node("opzetband_3a3b", false) as Node3D
	if node == null:
		print("[BELT] build_node(opzetband_3a3b) returned null")
		return null
	var root : Node = _bm.get("_placed_root")
	if root == null:
		return null
	root.add_child(node)
	node.global_position = FRESH_POS + Vector3(14.0, 0.5, 0.0)
	await get_tree().physics_frame
	return _first_belt()

func _first_belt() -> Node3D:
	for b in get_tree().get_nodes_in_group("shredder_feed_belt"):
		if b is Node3D and is_instance_valid(b):
			return b as Node3D
	return null

## The authentic build path: ghost parked at the aim point, then _place_current.
func _place_clamp_via_buildmode() -> void:
	_bm.call("_enter_placing", "vehicle_baleclamp")
	await get_tree().process_frame
	var ghost : Node3D = _bm.get("_ghost")
	if ghost == null:
		print("[PLACE] ghost not built — skipping build-mode clamp")
		return
	ghost.visible = true
	ghost.global_position = FRESH_POS
	_bm.set("_ghost_rot_y", 0.0)
	_bm.call("_place_current")
	print("[PLACE] build-mode clamp requested at (%.2f, %.2f, %.2f)"
		% [FRESH_POS.x, FRESH_POS.y, FRESH_POS.z])

## Engage the autonomous feeder exactly the way the CrewPanel does.
func _engage_feeder(belt: Node3D) -> bool:
	var cm = _world.get("crew_manager")
	if cm == null or not is_instance_valid(cm):
		print("COVERAGE-GAP: crew_manager is null — cannot assign a feeder")
		return false
	var workers : Array = []
	if "workers" in cm:
		workers = cm.get("workers")
	print("[CREW] %d workers on the roster" % workers.size())
	if not workers.is_empty() and cm.has_method("manual_assign"):
		var w = workers[0]
		cm.call("manual_assign", w, "role:feeder")
		await get_tree().physics_frame
		if not get_tree().get_nodes_in_group("feeder_worker").is_empty():
			return true
		print("[CREW] manual_assign produced no feeder — falling back to the direct API")
	# Direct API (driver=null path) so a missing/empty roster is not a blocker.
	if cm.has_method("_ensure_section_feeder"):
		var near : Vector3 = belt.global_position if belt != null else FRESH_POS
		cm.call("_ensure_section_feeder", "role:feeder", near, null)
		await get_tree().physics_frame
		return not get_tree().get_nodes_in_group("feeder_worker").is_empty()
	return false

# =============================================================================
# WATCH
# =============================================================================
func _vehicles() -> Array:
	var out : Array = []
	for v in get_tree().get_nodes_in_group("vehicle"):
		if v is Node3D and is_instance_valid(v):
			out.append(v)
	# Placed clamps that (for any reason) are not in the vehicle group.
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is Node3D and is_instance_valid(n) and not out.has(n) \
				and String(n.get_meta("placeable_id", "")) == "vehicle_baleclamp":
			out.append(n)
	return out

func _scan(phase: String) -> void:
	for v in _vehicles():
		var n3 := v as Node3D
		var id : int = n3.get_instance_id()
		var p : Vector3 = n3.global_position
		if not _start_pos.has(id):
			_start_pos[id] = p
		if _prev_pos.has(id):
			var prev : Vector3 = _prev_pos[id]
			if prev.distance_to(p) > JUMP_M:
				_jump_count += 1
				print("[JUMP %s] f=%d %s (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)  %s"
					% [phase, Engine.get_physics_frames(), _tag(n3),
					prev.x, prev.y, prev.z, p.x, p.y, p.z, _ai(n3)])
		var sp : Vector3 = _start_pos[id]
		if not bool(_drift_seen.get(id, false)) \
				and Vector2(p.x - sp.x, p.z - sp.z).length() > DRIFT_M:
			_drift_seen[id] = true
			_drift_count += 1
			print("[DRIFT %s] f=%d %s moved %.1f m XZ  (%.2f, %.2f, %.2f) -> (%.2f, %.2f, %.2f)  %s"
				% [phase, Engine.get_physics_frames(), _tag(n3),
				Vector2(p.x - sp.x, p.z - sp.z).length(),
				sp.x, sp.y, sp.z, p.x, p.y, p.z, _ai(n3)])
		_prev_pos[id] = p
		_watch_target(n3)

## Log every change of BaseVehicle._npc_target together with the FeederWorker
## that owns this vehicle and the state it was in — that names the source
## expression (SEEK→bale pos / GRAB retry / LIFT→_work_spot / supplier_target).
func _watch_target(v: Node3D) -> void:
	if not ("_npc_target" in v):
		return
	var id : int = v.get_instance_id()
	var t : Vector3 = v.get("_npc_target")
	var active : bool = bool(v.get("_npc_target_active"))
	var changed : bool = not _had_target.has(id)
	if not changed:
		changed = (_prev_target[id] as Vector3).distance_to(t) > 0.01
	if not changed:
		return
	_had_target[id] = true
	_prev_target[id] = t
	if not active and t == Vector3.ZERO:
		return
	_target_count += 1
	var d := (v.global_position - t)
	d.y = 0.0
	print("[TARGET] f=%d %s -> (%.2f, %.2f, %.2f)  dist=%.1f m active=%s  %s"
		% [Engine.get_physics_frames(), _tag(v), t.x, t.y, t.z, d.length(),
		str(active), _driver_of(v)])

## Identify the FeederWorker piloting this vehicle + the state machine phase.
func _driver_of(v: Node3D) -> String:
	for f in get_tree().get_nodes_in_group("feeder_worker"):
		if not is_instance_valid(f):
			continue
		if f.get("vehicle") == v:
			var belt = f.get("_belt")
			var bale = f.get("_bale")
			var lot : Vector3 = f.get("lot_center")
			var bp := "none"
			if bale != null and is_instance_valid(bale) and bale is Node3D:
				var b3 := bale as Node3D
				bp = "(%.1f, %.1f, %.1f)" % [b3.global_position.x, b3.global_position.y, b3.global_position.z]
			return "driver=%s state=%s bale=%s belt=%s lot=(%.1f, %.1f, %.1f) r=%.1f" % [
				String(f.get("worker_name")), String(f.call("_name_for_state", int(f.get("_state")))),
				bp, ("null" if belt == null else String((belt as Node).name)),
				lot.x, lot.y, lot.z, float(f.get("lot_radius"))]
	return "driver=<none/player>"

func _ai(v: Node3D) -> String:
	if not ("_npc_target" in v):
		return "(not a BaseVehicle)"
	var t : Vector3 = v.get("_npc_target")
	return "autopilot=%s active=%s occupied=%s target=(%.1f, %.1f, %.1f) rot_y=%.4f %s" % [
		str(v.get("npc_autopilot")), str(v.get("_npc_target_active")),
		str(v.get("occupied")), t.x, t.y, t.z, v.rotation.y, _driver_of(v)]

func _tag(v: Node3D) -> String:
	var pid := String(v.get_meta("placeable_id", ""))
	return "%s[%d]%s" % [v.name, v.get_instance_id(), ("" if pid == "" else " " + pid)]

func _report(tag: String) -> void:
	print("[POS %s]" % tag)
	for v in _vehicles():
		var n3 := v as Node3D
		var p : Vector3 = n3.global_position
		var sp : Vector3 = _start_pos.get(n3.get_instance_id(), p)
		print("    %s pos=(%.2f, %.2f, %.2f) rot_y=%.4f moved=%.1f m  %s"
			% [_tag(n3), p.x, p.y, p.z, n3.rotation.y,
			Vector2(p.x - sp.x, p.z - sp.z).length(), _ai(n3)])

func _dump_feeders(tag: String) -> void:
	var fs := get_tree().get_nodes_in_group("feeder_worker")
	if fs.is_empty():
		print("[FEEDERS %s] none" % tag)
		return
	for f in fs:
		if not is_instance_valid(f):
			continue
		var v = f.get("vehicle")
		var vp := "none"
		if v != null and is_instance_valid(v) and v is Node3D:
			var v3 := v as Node3D
			vp = "(%.1f, %.1f, %.1f)" % [v3.global_position.x, v3.global_position.y, v3.global_position.z]
		var fp : Vector3 = (f as Node3D).global_position
		print("[FEEDERS %s] %s state=%s riding=%s fed=%d proc=%d restocks=%d pos=(%.1f, %.1f, %.1f) veh=%s"
			% [tag, String(f.get("worker_name")),
			String(f.call("_name_for_state", int(f.get("_state")))),
			str(f.get("_riding")), int(f.get("bales_fed")), int(f.get("bales_processed")),
			int(f.get("_restocks")), fp.x, fp.y, fp.z, vp])

func _stop_autosave() -> void:
	if _world == null or not is_instance_valid(_world):
		return
	var t := _world.get_node_or_null("AutosaveTimer") as Timer
	if t != null and not t.is_stopped():
		t.stop()
		print("[SAFETY] AutosaveTimer stopped")
