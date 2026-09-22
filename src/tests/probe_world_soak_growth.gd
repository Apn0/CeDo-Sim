extends Node
## PROBE (2026-09-23) — does a booted MainWorld GROW while it just runs?
## Boots the operator's newest real save (copied into the `__soak__` scratch
## slot, exactly as bench_mainworld_perf does — the real save is never booted,
## and WorldLayout is pointed at a scratch path BEFORE the boot so the 60 s
## autosave can never touch the real world_layout.json), then samples the
## engine monitors over two SAMPLE_FRAMES windows SOAK_GAP_FRAMES apart:
##   OBJECT_NODE_COUNT / OBJECT_ORPHAN_NODE_COUNT / OBJECT_COUNT / MEMORY_STATIC
##   TIME_PROCESS / TIME_PHYSICS_PROCESS (mean per frame; see the bench header
##   for why the physics figure is not an absolute tick duration)
## and prints the DELTA. A steady world reads ~0 growth; a leak (an array that
## only ever appends, nodes spawned and never freed) reads as a slope.
## bench_mainworld_perf.gd already owns per-frame COST; this probe owns GROWTH.
## Numbers are printed, not asserted. Not wired in run.sh.
##
##   godot --headless --path . res://src/tests/probe_world_soak_growth.tscn
##   SOAK_GAP_FRAMES=<n> (env, default 1500)

const SCRATCH := "__soak__"
const WL_SCRATCH := "user://__soak___world.json"
const BOOT_FRAMES := 120
# Building-frame → plant-coordinate frame, as test_lump_cart_coverage.gd places its lines.
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)
var _flag_before : PackedByteArray = PackedByteArray()
const SAMPLE_FRAMES := 300
const WATCHDOG_S := 900.0

var _gap_frames : int = 1500

func _ready() -> void:
	var wd := Timer.new()
	wd.one_shot = true
	wd.wait_time = WATCHDOG_S
	wd.timeout.connect(_on_watchdog)
	add_child(wd)
	wd.start()
	call_deferred("_run")

func _on_watchdog() -> void:
	_cleanup_scratch()
	print("Result: FAIL (0 ok, 1 fail — watchdog: verdict never completed; see SCRIPT ERROR above)")
	get_tree().quit(2)

func _newest_real_slot() -> String:
	var best := ""
	var best_t := 0
	var d := DirAccess.open("user://")
	if d == null:
		return ""
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		if not d.current_is_dir() and f.ends_with("_factory.json") and not f.begins_with("__"):
			var t := FileAccess.get_modified_time("user://" + f)
			var stem := f.trim_suffix("_factory.json")
			if t > best_t and FileAccess.file_exists("user://%s_save.json" % stem):
				best_t = t
				best = stem
		f = d.get_next()
	d.list_dir_end()
	return best

func _prepare_scratch_slot() -> bool:
	var stem := _newest_real_slot()
	if stem == "":
		return false
	print("  info  : scratch slot copied from real save '%s'" % stem)
	for suffix in ["_factory.json", "_save.json"]:
		DirAccess.copy_absolute("user://%s%s" % [stem, suffix], "user://%s%s" % [SCRATCH, suffix])
	return FileAccess.file_exists("user://%s_factory.json" % SCRATCH)

func _cleanup_scratch() -> void:
	WorldLayout.layout_path_override = ""
	for tail in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(WL_SCRATCH + tail):
			DirAccess.remove_absolute(WL_SCRATCH + tail)
	for suffix in ["_factory.json", "_save.json"]:
		for tail in ["", ".bak", ".tmp"]:
			var p := "user://%s%s%s" % [SCRATCH, suffix, tail]
			if FileAccess.file_exists(p):
				DirAccess.remove_absolute(p)

func _slurp(p: String) -> PackedByteArray:
	if not FileAccess.file_exists(p):
		return PackedByteArray()
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return PackedByteArray()
	var b := f.get_buffer(f.get_length())
	f.close()
	return b

func _stats(a: Array) -> String:
	if a.is_empty():
		return "n/a"
	var lo : float = a[0]
	var hi : float = a[0]
	var sum := 0.0
	for v in a:
		lo = minf(lo, v)
		hi = maxf(hi, v)
		sum += v
	return "min %.3f  mean %.3f  max %.3f" % [lo, sum / a.size(), hi]

func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var sum := 0.0
	for v in a:
		sum += v
	return sum / a.size()

func _sample_window(tag: String) -> Dictionary:
	var proc_ms : Array = []
	var phys_ms : Array = []
	var frame_ms : Array = []
	var last := Time.get_ticks_usec()
	for _i in range(SAMPLE_FRAMES):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		frame_ms.append(float(now - last) / 1000.0)
		last = now
		proc_ms.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var out := {
		"nodes": int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		"orphans": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		"objects": int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		"resources": int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)),
		"mem_mb": Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
		"active": int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		"proc_mean": _mean(proc_ms),
		"phys_mean": _mean(phys_ms),
		"wall_mean": _mean(frame_ms),
	}
	print("  info  : %s — TIME_PROCESS ms/frame: %s" % [tag, _stats(proc_ms)])
	print("  info  : %s — TIME_PHYSICS_PROCESS ms/frame: %s (not an absolute tick duration — see bench header)" % [tag, _stats(phys_ms)])
	print("  info  : %s — wall ms/frame: %s" % [tag, _stats(frame_ms)])
	print("  info  : %s — nodes %d, orphan nodes %d, objects %d, resources %d, static memory %.2f MB, physics active %d"
		% [tag, int(out["nodes"]), int(out["orphans"]), int(out["objects"]), int(out["resources"]), float(out["mem_mb"]), int(out["active"])])
	return out

func _run() -> void:
	print("[PROBE] world soak growth (headless)")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	var env_gap := OS.get_environment("SOAK_GAP_FRAMES")
	if env_gap != "":
		_gap_frames = maxi(int(env_gap), 1)
	# No real save on this machine (measured 2026-09-23: user:// holds only
	# __test__ slots) → boot a NEW world and place two real lines through
	# BuildMode so machines, LineFlow and the crew have work during the soak.
	var have_slot := _prepare_scratch_slot()
	if not have_slot:
		print("  info  : no real save to copy — booting a fresh world and placing line_3b + line_sort")
	_flag_before = _slurp("user://world_layout_consumed.flag")
	WorldLayout.layout_path_override = WL_SCRATCH
	if WorldLayout.get_layout_path() != WL_SCRATCH:
		_cleanup_scratch()
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to run")
		get_tree().quit(2); return
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", SCRATCH)
		bus.set_meta("pending_is_new_save", not have_slot)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if scn == null:
		_cleanup_scratch()
		print("FATAL: MainWorld.tscn failed to load"); get_tree().quit(2); return
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	var t0 := Time.get_ticks_msec()
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
	print("  info  : boot + %d settle frames: %d ms" % [BOOT_FRAMES, Time.get_ticks_msec() - t0])
	if not have_slot:
		var mw := world as MainWorld
		var bm = world.get("build_mode") if mw != null else null
		if bm == null:
			bm = world.find_child("BuildMode", true, false)
		if bm != null:
			var lms := get_node_or_null("/root/LineMacroStore")
			for entry in [["line_3b", Vector2(4.0, 42.0)], ["line_sort", Vector2(4.0, 22.0)]]:
				var macro_id : String = entry[0]
				var start_bf : Vector2 = entry[1]
				if lms != null:
					lms._cache[macro_id] = {}
				var start : Vector3 = Plant.pc_to_scene(BF_O + start_bf.x * BF_XU + start_bf.y * BF_ZU)
				var ahead : Vector3 = Plant.pc_to_scene(BF_O + (start_bf.x + 1.0) * BF_XU + start_bf.y * BF_ZU)
				var fdir : Vector3 = (ahead - start).normalized()
				bm.call("_build_full_line", macro_id, start, atan2(-fdir.x, -fdir.z))
				for _i in range(10):
					await get_tree().process_frame
			if mw != null and mw.line_flow != null:
				mw.line_flow.rebuild()
				mw.line_flow.start_line()
				print("  info  : placed line_3b + line_sort: LineFlow %d nodes, line started" % mw.line_flow._nodes.size())
		for _i in range(60):
			await get_tree().process_frame

	var w1 := await _sample_window("window 1")
	var t_gap0 := Time.get_ticks_msec()
	for _i in range(_gap_frames):
		await get_tree().process_frame
	var gap_s : float = float(Time.get_ticks_msec() - t_gap0) / 1000.0
	var w2 := await _sample_window("window 2 (%d frames / %.1f s later)" % [_gap_frames, gap_s])
	var per_min : float = 60.0 / maxf(gap_s, 0.001)
	print("  info  : GROWTH over %.1f s: nodes %+d (%+.1f/min), orphans %+d, objects %+d (%+.1f/min), resources %+d, static memory %+.2f MB (%+.2f MB/min), TIME_PROCESS mean %+.3f ms, wall mean %+.3f ms"
		% [gap_s,
		   int(w2["nodes"]) - int(w1["nodes"]), float(int(w2["nodes"]) - int(w1["nodes"])) * per_min,
		   int(w2["orphans"]) - int(w1["orphans"]),
		   int(w2["objects"]) - int(w1["objects"]), float(int(w2["objects"]) - int(w1["objects"])) * per_min,
		   int(w2["resources"]) - int(w1["resources"]),
		   float(w2["mem_mb"]) - float(w1["mem_mb"]), (float(w2["mem_mb"]) - float(w1["mem_mb"])) * per_min,
		   float(w2["proc_mean"]) - float(w1["proc_mean"]),
		   float(w2["wall_mean"]) - float(w1["wall_mean"])])
	world.queue_free()
	await get_tree().process_frame
	_cleanup_scratch()
	# A NEW-world boot may write world_layout_consumed.flag (only tests read it):
	# put it back exactly as found, or remove it if it did not exist.
	var flag_p := "user://world_layout_consumed.flag"
	if _flag_before.is_empty():
		if FileAccess.file_exists(flag_p):
			DirAccess.remove_absolute(flag_p)
	elif _slurp(flag_p) != _flag_before:
		var w := FileAccess.open(flag_p, FileAccess.WRITE)
		if w != null:
			w.store_buffer(_flag_before)
			w.close()
	print("Result: PASS (1 ok, 0 fail — measurement printed above)")
	get_tree().quit(0)
