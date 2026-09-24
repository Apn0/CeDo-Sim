extends Node
# =============================================================================
# LegacyPropsSpawner on an UNCONFIGURED world — the first-launch / fresh-install
# path, which is the ONLY path that runs it (MainWorld._spawn_world_items gates
# it on `not WorldLayout.is_configured()`). The operator's own world is
# configured, so nothing he plays and no other suite on his machine reaches it.
#
# Measured 2026-09-24 on main b8bda8a (fresh copy, no assets/, no
# user://world_layout.json): the spawner routed four calls through
# world.call("_fit_box_collider") / world.call("_local_aabb") — helpers that
# d8932f2 (2026-06-16, the MainWorld 16-module extraction) had moved into
# GeometryUtils as static local_aabb() / fit_box_collider(). Neither name
# exists on MainWorld, and a failed call() ABORTS the calling function, so on
# every fresh install:
#   * the battery station got no solid collider (walk-through bench);
#   * the power outlet got no solid collider, and the fuel pump was never
#     spawned at all (the abort came one line before it);
#   * the feeder-station shredder stayed at the world origin, and the feeder
#     worker, the bale clamp and the scissors and scanner were never spawned.
#
# Boots the REAL MainWorld with WorldLayout reset to its fresh-install state and
# redirected (layout_path_override) to a file that does not exist, then proves:
#   1. the legacy path actually ran (is_configured() false; the bench exists) —
#      without it every check below would pass on an empty world;
#   2. zero "Nonexistent function" errors during the boot and zero errors raised
#      from LegacyPropsSpawner.gd — counted by an engine Logger, not inferred;
#   3. every world.call("X") in LegacyPropsSpawner.gd names a method the booted
#      MainWorld really has (the static form of 2 — it names the culprit);
#   4. battery station, outlet and pump each carry a SOLID collider: a
#      CollisionShape3D that is a DIRECT child of the StaticBody3D, enclosing
#      the model's meshes, live in the physics space (a point query at its
#      centre finds it), and a down-ray onto it stops on the body itself.
#      Their Area3D proximity trigger already carries a CollisionShape3D
#      grandchild, so a recursive "has a CollisionShape3D" is green on the bug;
#   5. the feeder-station shredder sits ON the floor at the belt's discharge;
#   6. the rest of the feeder station exists — the worker and his vehicle
#      (searched tree-wide: within a second he has boarded it, so he is its
#      child, not the world's).
#
# The operator's user://world_layout.json is never written (override), and the
# suite asserts that its bytes are unchanged at the end. If they changed, it was
# someone else sharing this app_userdata, so the suite does NOT restore over it.
#
# Sibling: test_legacy_props_spawner (#275, 1588462) landed the same fix the
# same evening with 5 checks, written in parallel. Both are kept (an add/add on
# a test name is two tests). That one infers the errors from the colliders;
# this one counts them (2), resolves EVERY world.call name, not just the two
# that broke (3), proves each collider is in the physics space (4), and pins
# the shredder to its own belt's discharge rather than any floor spot (5).
# Its own slot (__legacypropsboot__), so the two never share save files.
#
#   GODOT --headless --path . res://src/tests/test_legacy_props_unconfigured_boot.tscn
# =============================================================================

const SLOT        := "__legacypropsboot__"
const SCRATCH_WL  := "user://__legacypropsboot___world_layout.json"   # never created by us
const SPAWNER_SRC := "res://src/scenes/world/LegacyPropsSpawner.gd"
const REAL_WL     := "user://world_layout.json"
const BOOT_FRAMES := 90
const PHYS_SETTLE := 30
const WATCHDOG_S  := 240.0
const FLOOR_TOL_M := 0.02
const DISC_TOL_M  := 0.05
const AABB_TOL_M  := 0.01

# Save-slot files a boot of SLOT can write, restored to their prior state.
const PROTECT := [
	"user://__legacypropsboot___save.json",
	"user://__legacypropsboot___factory.json",
]

## Counts what the engine reports while MainWorld boots. Engine errors can be
## raised off the main thread (navmesh bake), hence the mutex.
class BootLog extends Logger:
	var mutex := Mutex.new()
	var nonexistent : Array[String] = []
	var from_spawner : Array[String] = []
	var script_errors : int = 0
	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type == Logger.ERROR_TYPE_WARNING:
			return
		var text := "%s:%d  %s %s" % [file.get_file(), line, code, rationale]
		mutex.lock()
		if error_type == Logger.ERROR_TYPE_SCRIPT:
			script_errors += 1
		if code.contains("Nonexistent function") or rationale.contains("Nonexistent function"):
			nonexistent.append(text)
		if file.ends_with("LegacyPropsSpawner.gd"):
			from_spawner.append(text)
		mutex.unlock()
	func _log_message(_message: String, _error: bool) -> void:
		pass

var _fails   : int = 0
var _oks     : int = 0
var _backups : Dictionary = {}
var _real_wl_before = null
var _started_ms : int = 0
var _done : bool = false
var _log : BootLog = null

func _check(ok: bool, msg: String) -> void:
	print(("  ok    : " if ok else "  FAIL  : ") + msg)
	if ok:
		_oks += 1
	else:
		_fails += 1

# Watchdog: a runtime error inside the _ready coroutine aborts it, and a scene
# suite with nothing left to call quit() idles until the harness kills it. This
# turns that hang into a failing verdict.
func _process(_d: float) -> void:
	if _done or _started_ms == 0:
		return
	if float(Time.get_ticks_msec() - _started_ms) / 1000.0 > WATCHDOG_S:
		_done = true
		print("  FAIL  : watchdog — the suite did not finish within %.0f s" % WATCHDOG_S)
		print("Result: FAIL (%d ok, %d fail) — watchdog" % [_oks, _fails + 1])
		_cleanup()
		get_tree().quit(2)

func _ready() -> void:
	print("=== LegacyPropsSpawner on an unconfigured (fresh-install) world ===")
	_started_ms = Time.get_ticks_msec()
	var wl := get_node_or_null("/root/WorldLayout")
	if wl == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		_verdict_and_quit(2); return
	_backup_files()

	# ── Fresh-install WorldLayout. The autoload already _load()ed the operator's
	# real file before this scene existed, so redirect it AND reset every script
	# variable to the value a never-loaded instance has. Anything the boot saves
	# goes to SCRATCH_WL, which does not exist beforehand.
	if AtomicFile.exists_any(SCRATCH_WL):
		AtomicFile.delete(SCRATCH_WL)
	wl.set("layout_path_override", SCRATCH_WL)
	if String(wl.call("get_layout_path")) != SCRATCH_WL:
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to run")
		_verdict_and_quit(2); return
	_reset_to_fresh(wl)
	_check(not bool(wl.call("is_configured")),
		"WorldLayout reads as UNCONFIGURED (fresh install) — the path that runs LegacyPropsSpawner")
	_check(not AtomicFile.exists_any(SCRATCH_WL), "the redirected layout file does not exist")

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", SLOT)
		bus.set_meta("pending_is_new_save", false)   # straight to _spawn_world_items, no ENTER ritual

	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		print("FATAL: MainWorld.tscn failed to load")
		_verdict_and_quit(2); return

	_log = BootLog.new()
	OS.add_logger(_log)
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	for _i in range(PHYS_SETTLE):
		await get_tree().physics_frame

	# ── 1 — the legacy path ran ─────────────────────────────────────────────
	var bench := world.get_node_or_null("BatteryStation") as Node3D
	_check(bench != null, "the legacy spawner ran: MainWorld has a BatteryStation")

	# ── 2 — the engine's own error stream during the boot ──────────────────
	_log.mutex.lock()
	var nonexistent := _log.nonexistent.duplicate()
	var from_spawner := _log.from_spawner.duplicate()
	var script_errors := _log.script_errors
	_log.mutex.unlock()
	print("  info  : %d SCRIPT ERROR(s) during the boot in total" % script_errors)
	for line in nonexistent.slice(0, 6):
		print("    nonexistent: %s" % line)
	for line in from_spawner.slice(0, 6):
		print("    spawner    : %s" % line)
	_check(nonexistent.is_empty(),
		"zero 'Nonexistent function' errors during the boot (%d)" % nonexistent.size())
	_check(from_spawner.is_empty(),
		"zero errors raised from LegacyPropsSpawner.gd (%d)" % from_spawner.size())

	# ── 3 — every world.call() the spawner makes resolves on MainWorld ─────
	var names := _world_call_names()
	print("  info  : LegacyPropsSpawner calls on the world: %s" % ", ".join(names))
	_check(names.size() >= 4, "the source scan found the spawner's world.call() sites (%d names)" % names.size())
	for n in names:
		_check(world.has_method(n), "MainWorld has %s() — LegacyPropsSpawner calls it" % n)

	# ── 4 — solid colliders on the three procedural props ─────────────────
	_check_solid(world, "BatteryStation", "battery station (walkie bench)")
	_check_solid(world, "PowerOutlet", "power outlet")
	_check_solid(world, "FuelPump", "fuel pump")

	# ── 5 — the feeder-station shredder is seated on the floor ─────────────
	_check_shredder(world)

	# ── 6 — the rest of the feeder station was spawned ────────────────────
	var worker : Node3D = null
	for c in get_tree().root.find_children("*", "", true, false):
		if c is FeederWorker:
			print("  info  : FeederWorker '%s' at %s" % [String(c.get("worker_name")), String(c.get_path())])
			if String(c.get("worker_name")) == "Mohammed":
				worker = c
	_check(worker != null, "the feeder worker (Mohammed) was spawned — the step after the shredder")
	if worker != null:
		var v = worker.get("vehicle")
		_check(v != null and is_instance_valid(v), "the feeder worker was handed his own vehicle")

	_verdict_and_quit(0 if _fails == 0 else 1, world)

# ── Checks ───────────────────────────────────────────────────────────────────

func _check_solid(world: Node, node_name: String, label: String) -> void:
	var body := world.get_node_or_null(node_name) as Node3D
	_check(body != null, "%s exists" % label)
	if body == null:
		return
	_check(body is StaticBody3D, "%s is a StaticBody3D" % label)
	var solid : CollisionShape3D = null
	for c in body.get_children():
		if c is CollisionShape3D and (c as CollisionShape3D).shape != null and not (c as CollisionShape3D).disabled:
			solid = c
	_check(solid != null, "%s has a SOLID collider (a CollisionShape3D directly under the body)" % label)
	if solid == null:
		return
	# The box must enclose every mesh of the model — measured here from the
	# meshes' own AABBs, not from the helper that sized it.
	var model := _mesh_bounds_in(body, body.global_transform.affine_inverse())
	var box := solid.shape as BoxShape3D
	if box != null and model.size != Vector3.ZERO:
		var b := AABB(solid.position - box.size * 0.5, box.size)
		var grown := b.grow(AABB_TOL_M)
		var encloses := grown.has_point(model.position) and grown.has_point(model.end)
		_check(encloses and model.size.y > 0.2,
			"%s's collider encloses the model (box %s at %s, meshes %s at %s)"
				% [label, _v(b.size), _v(b.position), _v(model.size), _v(model.position)])
	# Behaviour: the shape is live in the physics space, not just a node.
	# (a) A point query at the box centre finds the body. It also names anything
	#     else standing in the prop — the legacy Merlo P40 parks 0.50 m from the
	#     outlet post and its hull contains it (measured 2026-09-24; kinematic,
	#     with a zero recovery budget when parked, it neither drifts nor gets
	#     stuck: it drives off the same with and without the outlet's collider).
	var space := body.get_world_3d().direct_space_state
	var pq := PhysicsPointQueryParameters3D.new()
	pq.position = solid.global_position
	pq.collide_with_areas = false
	var inside : Array[String] = []
	var found := false
	for h in space.intersect_point(pq, 16):
		if h.get("collider") == body:
			found = true
		elif h.get("collider") is Node:
			inside.append(String((h["collider"] as Node).name))
	_check(found, "the %s's collider is live in the physics space (a point query at its centre finds it)" % label)
	if not inside.is_empty():
		print("  info  : the %s overlaps %s at spawn (legacy layout, not gated here)" % [label, ", ".join(inside)])
	# (b) A ray dropped onto the prop stops ON the prop, not on the floor. Vehicle
	#     hulls are excluded: a ray that starts inside one measures nothing (on
	#     Rapier it went straight through the outlet to the ground).
	var top : Vector3 = solid.global_transform * Vector3(0.0, (box.size.y * 0.5 if box else 0.5), 0.0)
	var q := PhysicsRayQueryParameters3D.create(top + Vector3.UP * 0.5, top + Vector3.DOWN * 4.0)
	q.collide_with_areas = false
	var skip : Array[RID] = []
	for n in get_tree().root.find_children("*", "", true, false):
		if n is BaseVehicle:
			skip.append((n as CollisionObject3D).get_rid())
	q.exclude = skip
	var hit : Dictionary = space.intersect_ray(q)
	var hit_name : String = "nothing"
	if not hit.is_empty() and hit.get("collider") != null:
		hit_name = "%s at %s" % [String((hit["collider"] as Node).name), _v(hit.get("position", Vector3.ZERO))]
	_check(not hit.is_empty() and hit.get("collider") == body,
		"a ray dropped onto the %s stops on it (hit: %s)" % [label, hit_name])

func _check_shredder(world: Node) -> void:
	var belt := world.get_node_or_null("ShredderFeedBelt_Mohammed") as Node3D
	_check(belt != null, "the feeder station's feed belt exists")
	if belt == null:
		return
	# Where LegacyPropsSpawner says the shredder goes: at the belt's discharge.
	var disc : Vector3 = belt.to_global(Vector3(0.0, 0.0,
		float(belt.get("deck_length")) + float(belt.get("incline_run")) + 2.0))
	var shredder : Node3D = null
	var best := INF
	for s in get_tree().get_nodes_in_group("shredder"):
		if s is Node3D and s.get_parent() == world:
			var d := _horiz((s as Node3D).global_position, disc)
			if d < best:
				best = d
				shredder = s
	_check(shredder != null, "the feeder station's shredder exists")
	if shredder == null:
		return
	var gp := shredder.global_position
	print("  info  : shredder at %s, belt discharge at %s" % [_v(gp), _v(disc)])
	_check(best <= DISC_TOL_M,
		"the shredder stands at the belt's discharge (%.2f m off in plan, limit %.2f)" % [best, DISC_TOL_M])
	var floor_y : float = float(world.call("_floor_top_y"))
	var bottom : float = _mesh_bounds_in(shredder, Transform3D.IDENTITY).position.y
	_check(absf(bottom - floor_y) <= FLOOR_TOL_M,
		"the shredder sits ON the floor (mesh bottom y %.3f, floor top %.3f, limit %.2f)"
			% [bottom, floor_y, FLOOR_TOL_M])

# ── Helpers ──────────────────────────────────────────────────────────────────

## Union of every MeshInstance3D's AABB under `root`, carried into the space
## `to_space` maps global coordinates into (IDENTITY = global).
func _mesh_bounds_in(root: Node3D, to_space: Transform3D) -> AABB:
	var out := AABB()
	var started := false
	for c in root.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		if mi.mesh == null:
			continue
		var a : AABB = (to_space * mi.global_transform) * mi.get_aabb()
		if not started:
			out = a; started = true
		else:
			out = out.merge(a)
	return out

## Every method name LegacyPropsSpawner.gd routes through world.call("…") in
## CODE. Comments are stripped first: the file's header documents the two
## names that used to be called this way.
func _world_call_names() -> Array[String]:
	var out : Array[String] = []
	var re := RegEx.new()
	re.compile("world\\.call\\(\\s*[\"']([A-Za-z_][A-Za-z0-9_]*)[\"']")
	for line in FileAccess.get_file_as_string(SPAWNER_SRC).split("\n"):
		for m in re.search_all(_code_part(line)):
			var n := m.get_string(1)
			if not out.has(n):
				out.append(n)
	return out

## `line` up to its first `#` that is not inside a string literal.
func _code_part(line: String) -> String:
	var quote := ""
	var i := 0
	while i < line.length():
		var ch := line[i]
		if quote != "":
			if ch == "\\":
				i += 1
			elif ch == quote:
				quote = ""
		elif ch == "\"" or ch == "'":
			quote = ch
		elif ch == "#":
			return line.substr(0, i)
		i += 1
	return line

## Give the WorldLayout autoload the state a fresh install has: every script
## variable takes the value of a never-loaded instance, except the override.
func _reset_to_fresh(wl: Node) -> void:
	var fresh : Object = (wl.get_script() as Script).new()
	for p in (wl.get_script() as Script).get_script_property_list():
		var pname := String(p.get("name", ""))
		if pname == "" or pname == "layout_path_override":
			continue
		if (int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		var val = fresh.get(pname)
		if val is Dictionary or val is Array:
			val = val.duplicate(true)
		wl.set(pname, val)
	if fresh is Node:
		(fresh as Node).free()

func _horiz(a: Vector3, b: Vector3) -> float:
	return Vector2(a.x - b.x, a.z - b.z).length()

func _v(p: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [p.x, p.y, p.z]

func _verdict_and_quit(code: int, world: Node = null) -> void:
	if _done:
		return
	# The operator's world ground truth must come through byte-identical.
	_check(_same_bytes(_read_or_null(REAL_WL), _real_wl_before),
		"user://world_layout.json is byte-identical at the end (this suite only ever writes the scratch path)")
	_done = true
	if _log != null:
		OS.remove_logger(_log)
	if code != 2:
		code = 0 if _fails == 0 else 1
	print("  info  : boot + checks took %.1f s (watchdog %.0f s)"
		% [float(Time.get_ticks_msec() - _started_ms) / 1000.0, WATCHDOG_S])
	print("\n=========================================")
	print("Result: %s (%d ok, %d fail)" % ["PASS" if _fails == 0 and code == 0 else "FAIL", _oks, _fails])
	print("=========================================")
	# Restore BEFORE the world teardown: a headless teardown segfaults about one
	# run in four and never reaches code after it.
	_cleanup()
	if world != null:
		world.queue_free()
		await get_tree().process_frame
		_cleanup()
	get_tree().quit(code)

func _cleanup() -> void:
	var wl := get_node_or_null("/root/WorldLayout")
	if wl != null:
		wl.set("layout_path_override", "")
	AtomicFile.delete(SCRATCH_WL)
	_restore_files()

## The file's bytes, or null when it does not exist.
func _read_or_null(path: String) -> Variant:
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else null

func _same_bytes(a: Variant, b: Variant) -> bool:
	if typeof(a) == TYPE_NIL or typeof(b) == TYPE_NIL:
		return typeof(a) == typeof(b)
	return (a as PackedByteArray) == (b as PackedByteArray)

func _backup_files() -> void:
	_real_wl_before = _read_or_null(REAL_WL)
	for p in PROTECT:
		_backups[p] = _read_or_null(p)

func _restore_files() -> void:
	for p in PROTECT:
		var data : Variant = _backups.get(p, null)
		if typeof(data) == TYPE_NIL:
			AtomicFile.delete(p)
		else:
			AtomicFile.write_text(p, (data as PackedByteArray).get_string_from_utf8())
	# The override means this suite never writes the real layout, so a change
	# here was made by someone else — another suite or a game sharing this
	# app_userdata (measured 2026-09-24: a second harness ran beside this one).
	# Never overwrite it: that would revert their edit. Keep what this suite
	# saw at start beside it instead, so neither version is lost.
	if typeof(_real_wl_before) != TYPE_NIL and not _same_bytes(_read_or_null(REAL_WL), _real_wl_before):
		var keep := "user://world_layout.json.legacypropsboot-%d.bak" % Time.get_unix_time_from_system()
		AtomicFile.write_text(keep, (_real_wl_before as PackedByteArray).get_string_from_utf8())
		print("  WARN  : user://world_layout.json changed during the run (not by this suite) — left as is; the start-of-run copy is %s" % keep)
