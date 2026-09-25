extends Node3D
# =============================================================================
# REGRESSION — nested vehicles must not translate forever, and a save with
# nested vehicle poses must not load nested.
#
#   GODOT --headless --path . res://src/tests/test_nested_vehicle_drift.tscn
#   exit code 0 = PASS, 1 = FAIL
#
# WHAT IT GUARDS (measured 2026-07-21, src/tests/probe_drift_source.gd):
#   Two bale clamps overlapping at the same XZ are pushed by Rapier's contact
#   recovery INSIDE BaseVehicle's move_and_collide (BaseVehicle.gd, the sweep in
#   _kinematic_move). Both hulls get the same recovery vector, so the overlap
#   never resolves and the pair translates forever at constant speed — 23 m in
#   15 s here, 185 m in 150 s in MainWorld — with rotation.y exactly 0 and the
#   call returning null, so nothing downstream could observe it.
#
# CHECK A — drift is bounded and stops.
#   Three deliberately nested pairs run 3600 frames (60 s at 60 Hz).
#   • TOTAL_BOUND_M = 0.05 m. Justification: BaseVehicle._clamp_recovery_overshoot
#     undoes horizontal travel beyond |motion| * (1 + RECOVERY_SLACK_REL), and a
#     parked vehicle's |motion| is exactly 0 — so its horizontal budget is
#     exactly 0 and the expected reading is 0.0000 m. The bound is a detection
#     floor, not a tolerance: 5 cm is 460× below the 23 m this same scene
#     produced before the fix, and 7× below the 0.36 m an earlier ABSOLUTE
#     1e-4 m/frame slack produced (measured — that variant stayed bounded but
#     never converged, which is why the slack is relative).
#   • TAIL_BOUND_M = 0.005 m of travel during the LAST 600 frames (10 s). This is
#     the "must converge, not creep" test: pre-fix the tail was ~7-13 m
#     (0.012-0.022 m per frame, still rising at the end); with an absolute slack
#     it was exactly 0.06 m. 5 mm over 10 s = 0.5 mm/s.
#
# CHECK B — de-nest on load.
#   A scratch layout file (user://test_denest_layout.json — NEVER world_layout
#   or allernieuwste_*) holding two nested vehicle pairs is loaded through a real
#   BuildMode with load_shared_structure=false. After load, no two placed
#   vehicles may overlap, and none may be missing. Overlap is re-derived here
#   from catalog sizes with a plain AABB test (all entries are rot_y=0), so the
#   assertion does not reuse BuildMode's own SAT helper.
# =============================================================================

const CLAMP := preload("res://src/scenes/vehicles/BaleClamp.tscn")
const BUILD_MODE := preload("res://src/build/BuildMode.gd")

const FRAMES        : int   = 3600     # 60 s at 60 Hz
const TAIL_FRAMES   : int   = 600      # last 10 s
const TOTAL_BOUND_M : float = 0.05
const TAIL_BOUND_M  : float = 0.005
const GAPS : Array[float] = [0.40, 0.80, 1.05]

# Scratch save used by CHECK B. Deliberately NOT world_layout.json.
const TEST_LAYOUT_PATH := "user://test_denest_layout.json"
# CHECK B spawns a REAL BuildMode, and a live BuildMode can reach _save_layout()
# → WorldLayout.save(). With load_shared_structure = false this instance holds no
# structure items, so such a save would write an EMPTY structure list over the
# operator's shared walls/doors/gates. Measured: a run did bump
# world_layout.json's mtime, content identical. That was this file's own
# restore, which rewrote the backup bytes unconditionally. Now WorldLayout's
# writes go to a scratch file, and the real one is only compared at the end,
# md5 + mtime, never written (src/tests/world_layout_guard.gd).
const WorldLayoutGuard := preload("res://src/tests/world_layout_guard.gd")
var _wlg := WorldLayoutGuard.new("__nesteddrift__")
const DENEST_VEHICLE_ID := "vehicle_baleclamp"
const DENEST_ORIGIN_X : float = 2000.0   # far from the CHECK A pairs

# CHECK C — the clamp must not touch a vehicle that is legitimately driving.
const DRIVE_ORIGIN := Vector3(500.0, 0.0, 0.0)
const DRIVE_MPS      : float = 3.0
const DRIVE_FRAMES   : int   = 300      # 5 s
const DRIVE_WALL_X   : float = 512.0    # 12 m downrange, reachable in 5 s
const DRIVE_MIN_M    : float = 5.0      # must actually move
var _drive_body : Node3D = null

var _bodies : Array[Node3D] = []
var _frame  : int = 0
var _start  : Array[Vector3] = []
var _tail   : Array[Vector3] = []
var _failures : Array[String] = []
var _denest_lines : Array[String] = []

func _ready() -> void:
	print("=== REGRESSION — nested vehicle drift + load de-nest ===")
	var floor_body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(4000.0, 2.0, 400.0)
	cs.shape = bs
	floor_body.add_child(cs)
	floor_body.position = Vector3(1000.0, -1.0, 0.0)
	add_child(floor_body)

	var x := 0.0
	for gap in GAPS:
		for y in [0.0, gap]:
			var v := CLAMP.instantiate() as Node3D
			add_child(v)
			v.global_position = Vector3(x, y, 0.0)
			_bodies.append(v)
		x += 60.0
	for b in _bodies:
		_start.append(b.global_position)
		_tail.append(b.global_position)
	print("[test] CHECK A: %d nested clamps (gaps %s), running %d frames"
		% [_bodies.size(), str(GAPS), FRAMES])
	_setup_drive_check()
	_run_denest_check()

# -----------------------------------------------------------------------------
# CHECK C — an isolated, MOVING vehicle must still travel and must still be
# stopped by a wall. Guards the two ways the displacement clamp could regress
# driving: freezing a legitimate sweep, or bypassing the sweep's collision.
# -----------------------------------------------------------------------------
func _setup_drive_check() -> void:
	var wall := StaticBody3D.new()
	var wcs := CollisionShape3D.new()
	var wbs := BoxShape3D.new()
	wbs.size = Vector3(1.0, 6.0, 40.0)
	wcs.shape = wbs
	wall.add_child(wcs)
	wall.position = Vector3(DRIVE_WALL_X, 3.0, 0.0)
	add_child(wall)
	_drive_body = CLAMP.instantiate() as Node3D
	add_child(_drive_body)
	_drive_body.global_position = DRIVE_ORIGIN
	# forward = -basis.z, so rotation.y = -PI/2 points the machine down +X.
	_drive_body.rotation.y = -PI * 0.5
	print("[test] CHECK C: driving one isolated clamp %+.1f m/s at a wall %.1f m downrange"
		% [DRIVE_MPS, DRIVE_WALL_X - DRIVE_ORIGIN.x])

# -----------------------------------------------------------------------------
# CHECK B — load a save whose vehicle poses are nested, assert none stay nested.
# -----------------------------------------------------------------------------
func _run_denest_check() -> void:
	var entries : Array = [{"layout_version": 2}]
	# Two nested pairs: same XZ, ~0.8 m apart in Y — the ladder signature that
	# pre-clearance-gate saves contain.
	for pair in 2:
		var px : float = DENEST_ORIGIN_X + float(pair) * 40.0
		entries.append({"id": DENEST_VEHICLE_ID, "x": px, "y": 0.0, "z": 0.0, "rot_y": 0.0})
		entries.append({"id": DENEST_VEHICLE_ID, "x": px, "y": 0.8, "z": 0.0, "rot_y": 0.0})
	var f := FileAccess.open(TEST_LAYOUT_PATH, FileAccess.WRITE)
	if f == null:
		_failures.append("CHECK B: could not write %s" % TEST_LAYOUT_PATH)
		return
	f.store_string(JSON.stringify(entries, "\t"))
	f.close()

	if not _wlg.arm(get_tree()):
		_failures.append("CHECK B: WorldLayout.layout_path_override not honoured — refusing to run a BuildMode that may overwrite world_layout.json")
		return
	var bm := Node3D.new()
	bm.set_script(BUILD_MODE)
	# Set BEFORE add_child — _ready() calls load_layout() immediately.
	bm.set("layout_path", TEST_LAYOUT_PATH)
	bm.set("allow_legacy_fallback", false)
	bm.set("load_shared_structure", false)
	add_child(bm)

	var placed : Array[Node3D] = []
	for n in get_tree().get_nodes_in_group("vehicle"):
		if not (n is Node3D):
			continue
		var n3 : Node3D = n
		if n3.global_position.x > DENEST_ORIGIN_X - 100.0:
			placed.append(n3)
	var expected := entries.size() - 1
	_denest_lines.append("CHECK B: expected %d restored vehicles, found %d" % [expected, placed.size()])
	if placed.size() != expected:
		_failures.append("CHECK B: %d of %d saved vehicles survived the load — a saved vehicle must never be dropped"
			% [placed.size(), expected])
	var item : Dictionary = PlaceableCatalog.get_item(DENEST_VEHICLE_ID)
	var sz : Vector3 = item.get("size", Vector3(2.0, 2.5, 4.0)) if not item.is_empty() else Vector3(2.0, 2.5, 4.0)
	var overlaps := 0
	for i in placed.size():
		for j in range(i + 1, placed.size()):
			var a : Vector3 = placed[i].global_position
			var b : Vector3 = placed[j].global_position
			_denest_lines.append("  [%d] %s   [%d] %s   d=%.2f m"
				% [i, str(a.round()), j, str(b.round()), a.distance_to(b)])
			if _aabb_overlap(a, b, sz):
				overlaps += 1
				_failures.append("CHECK B: restored vehicles %d and %d still overlap (%s vs %s)"
					% [i, j, str(a), str(b)])
	_denest_lines.append("CHECK B: overlapping pairs after load = %d (want 0)" % overlaps)
	# Leave no scratch save behind, and keep the loaded vehicles out of CHECK A.
	bm.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_LAYOUT_PATH))

## Axis-aligned overlap of two 85 %-footprint hull boxes standing on their
## placement origin. Exact for the rot_y = 0 entries this test writes.
func _aabb_overlap(a: Vector3, b: Vector3, size: Vector3) -> bool:
	var hx := size.x * 0.85 * 0.5
	var hy := size.y * 0.85 * 0.5
	var hz := size.z * 0.85 * 0.5
	var a_cy := a.y + size.y * 0.5 + 0.1
	var b_cy := b.y + size.y * 0.5 + 0.1
	return absf(a.x - b.x) < hx * 2.0 \
		and absf(a.z - b.z) < hz * 2.0 \
		and absf(a_cy - b_cy) < hy * 2.0

# -----------------------------------------------------------------------------
# CHECK A — run the clock.
# -----------------------------------------------------------------------------
func _physics_process(_delta: float) -> void:
	_frame += 1
	if _frame == 1:
		for i in _bodies.size():
			_start[i] = _bodies[i].global_position
	# Command speed BEFORE the vehicle's own _physics_process runs (parents tick
	# before children), standing in for a held throttle without an input device.
	if _frame <= DRIVE_FRAMES and _drive_body != null and is_instance_valid(_drive_body):
		_drive_body.set("_current_speed_mps", DRIVE_MPS)
	if _frame == FRAMES - TAIL_FRAMES:
		for i in _bodies.size():
			_tail[i] = _bodies[i].global_position
	if _frame >= FRAMES:
		_report()

func _report() -> void:
	print("--- CHECK A: %d frames (%.0f s) ---" % [_frame, float(_frame) / 60.0])
	var worst_total := 0.0
	var worst_tail := 0.0
	for i in _bodies.size():
		var now : Vector3 = _bodies[i].global_position
		var total := _xz(now - _start[i])
		var tail := _xz(now - _tail[i])
		worst_total = maxf(worst_total, total)
		worst_tail = maxf(worst_tail, tail)
		print("  body %d  gap=%.2f  total xz=%.4f m  last-%d-frame xz=%.4f m  rot.y=%.4f"
			% [i, GAPS[i / 2], total, TAIL_FRAMES, tail, _bodies[i].rotation.y])
	print("  worst total = %.4f m (bound %.2f)   worst tail = %.4f m (bound %.2f)"
		% [worst_total, TOTAL_BOUND_M, worst_tail, TAIL_BOUND_M])
	if worst_total > TOTAL_BOUND_M:
		_failures.append("CHECK A: worst total drift %.4f m exceeds the %.2f m bound" % [worst_total, TOTAL_BOUND_M])
	if worst_tail > TAIL_BOUND_M:
		_failures.append("CHECK A: still moving — %.4f m travelled in the last %d frames (bound %.2f m)"
			% [worst_tail, TAIL_FRAMES, TAIL_BOUND_M])
	print("--- CHECK C: driven vehicle ---")
	if _drive_body == null or not is_instance_valid(_drive_body):
		_failures.append("CHECK C: drive body vanished")
	else:
		var end_x := _drive_body.global_position.x
		var travelled := end_x - DRIVE_ORIGIN.x
		# Nose of the real chassis hull — BaleClamp.tscn BodyCollision is a
		# BoxShape3D 1.2 x 1.0 x 2.5, so half its depth is 1.25 m (the catalog
		# size 3.6 m is the visual envelope, not the collider).
		var deepest := end_x + 1.25
		var wall_face := DRIVE_WALL_X - 0.5
		print("  travelled %.3f m (min %.1f)   hull nose x=%.3f   wall near face x=%.3f   penetration=%.3f m"
			% [travelled, DRIVE_MIN_M, deepest, wall_face, deepest - wall_face])
		if travelled < DRIVE_MIN_M:
			_failures.append("CHECK C: driven vehicle only travelled %.3f m — the displacement clamp is eating legitimate motion"
				% travelled)
		# 0.10 m tolerance: the sweep resolves contact within one frame's travel
		# (3 m/s / 60 Hz = 0.05 m), so anything deeper means the sweep's collision
		# response was bypassed.
		if deepest > wall_face + 0.10:
			_failures.append("CHECK C: driven vehicle penetrated the wall %.3f m (hull nose x=%.3f, wall face x=%.3f)"
				% [deepest - wall_face, deepest, wall_face])
	print("--- CHECK B: de-nest on load ---")
	# Over the whole run, after the BuildMode is long gone.
	var wl_check : Array = _wlg.real_layout_check()
	_denest_lines.append(String(wl_check[1]))
	if not bool(wl_check[0]):
		_failures.append("CHECK B: " + String(wl_check[1]))
	_wlg.disarm()
	for line in _denest_lines:
		print("  " + line)
	if _failures.is_empty():
		print("RESULT: PASS")
		get_tree().quit(0)
	else:
		for msg in _failures:
			print("  FAIL: " + msg)
		print("RESULT: FAIL (%d)" % _failures.size())
		get_tree().quit(1)

func _xz(v: Vector3) -> float:
	return Vector2(v.x, v.z).length()
