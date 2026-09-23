extends Node
## PROBE (2026-09-23) — WHERE the CPU-side frame time of a booted world goes.
## probe_world_soak_growth measured a steady ~9.4 ms of TIME_PROCESS per frame
## (headless) with two lines placed; bench_mainworld_perf's ablation could not
## attribute it (its header: window-to-window noise 20-50 %). This probe times
## the systems DIRECTLY instead — it calls each per-frame / per-tick entry point
## itself N times in a row and takes the wall clock, so the number is the
## function's own cost, not a difference of two noisy windows:
##   LineFlow.tick(1/60)                (every frame — its _process calls tick)
##   every NPC._physics_process(1/60)   (60 Hz each)
##   every BaseVehicle._physics_process (60 Hz each)
##   CrewManager._physics_process       (60 Hz)
##   NpcAutonomyBoard._process          (60 Hz)
##   SimTick.sim_tick.emit(0.1)         (10 Hz — extruder machines etc.)
## Caveat: a physics callback called outside the physics step still runs its
## logic (move_and_slide works from any callback) but the world is being
## advanced N extra steps per system — the run is discarded, nothing is saved.
## Same scratch-slot + layout_path_override discipline as the soak probe; boots
## a fresh world and places line_3b + line_sort (no real save on this machine).
## Numbers are printed, not asserted. Not wired in run.sh.
##
##   godot --headless --path . res://src/tests/probe_tick_cost.tscn

const SCRATCH := "__tickcost__"
const WL_SCRATCH := "user://__tickcost___world.json"
const BOOT_FRAMES := 120
const SETTLE_FRAMES := 240
const REF_FRAMES := 120
const WATCHDOG_S := 600.0
const BF_O  := Vector2(573.404, 463.647)
const BF_XU := Vector2(-0.64279, 0.76604)
const BF_ZU := Vector2(-0.76604, -0.64279)
var _flag_before : PackedByteArray = PackedByteArray()

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

## Time `n` direct calls of `fn` (a Callable); returns µs per call.
func _time_calls(fn: Callable, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for _i in n:
		fn.call()
	return float(Time.get_ticks_usec() - t0) / float(n)

func _run() -> void:
	print("[PROBE] tick cost attribution (headless)")
	if get_node_or_null("/root/WorldLayout") == null:
		print("FATAL: WorldLayout autoload missing (boot via the .tscn, not --script)")
		get_tree().quit(2); return
	_flag_before = _slurp("user://world_layout_consumed.flag")
	WorldLayout.layout_path_override = WL_SCRATCH
	if WorldLayout.get_layout_path() != WL_SCRATCH:
		_cleanup_scratch()
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to run")
		get_tree().quit(2); return
	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", SCRATCH)
		bus.set_meta("pending_is_new_save", true)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	var world : Node = scn.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(world)
	get_tree().current_scene = world
	for _i in range(BOOT_FRAMES):
		await get_tree().process_frame
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
	for _i in range(SETTLE_FRAMES):
		await get_tree().process_frame

	# Reference: the engine's own per-frame figures over REF_FRAMES frames.
	var proc_sum := 0.0
	var phys_sum := 0.0
	var wall0 := Time.get_ticks_usec()
	for _i in range(REF_FRAMES):
		await get_tree().process_frame
		proc_sum += Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
		phys_sum += Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var wall_ms : float = float(Time.get_ticks_usec() - wall0) / 1000.0 / REF_FRAMES
	var proc_ms : float = proc_sum / REF_FRAMES
	var phys_ms : float = phys_sum / REF_FRAMES
	var fps : float = 1000.0 / maxf(wall_ms, 0.001)
	print("  info  : reference over %d frames — TIME_PROCESS %.2f ms, TIME_PHYSICS_PROCESS %.2f ms, wall %.2f ms/frame (%.1f fps headless)"
		% [REF_FRAMES, proc_ms, phys_ms, wall_ms, fps])

	# Direct timings. rows: [name, us_per_call, calls_per_s]
	var rows : Array = []
	if mw != null and mw.line_flow != null:
		var lf := mw.line_flow
		# LineFlow._process(delta) calls tick(delta) EVERY FRAME (LineFlow.gd, FLOW
		# TICK) — not at SimTick's 10 Hz — so its per-frame cost is one tick(1/60).
		rows.append(["LineFlow.tick(1/60) per frame  ×%d nodes" % lf._nodes.size(), _time_calls(func(): lf.tick(1.0 / 60.0), 60), 60.0])
		# What the game actually pays per frame: _process accumulates frame time and
		# ticks at FLOW_TICK_DT (10 Hz) — 60 calls of _process(1/60) = 10 ticks.
		rows.append(["LineFlow._process(1/60) as shipped (10 Hz accumulator)", _time_calls(func(): lf._process(1.0 / 60.0), 60), 60.0])
	var st := get_node_or_null("/root/SimTick")
	if st != null:
		rows.append(["SimTick.sim_tick.emit(0.1)  (%d subscribers)" % int(st.call("subscriber_count")),
			_time_calls(func(): st.sim_tick.emit(0.1), 20), 10.0])
	var npc_us := 0.0
	var npc_n := 0
	if mw != null:
		for n in mw.npcs.values():
			var npc := n as Node
			if npc != null and npc.has_method("_physics_process"):
				npc_us += _time_calls(func(): npc._physics_process(1.0 / 60.0), 30)
				npc_n += 1
	if npc_n > 0:
		rows.append(["NPC._physics_process  ×%d workers (sum)" % npc_n, npc_us, 60.0])
	var veh_us := 0.0
	var veh_n := 0
	if mw != null:
		for c in mw.get_children():
			if c is BaseVehicle:
				var v := c as Node
				veh_us += _time_calls(func(): v._physics_process(1.0 / 60.0), 30)
				veh_n += 1
	if veh_n > 0:
		rows.append(["BaseVehicle._physics_process  ×%d vehicles (sum)" % veh_n, veh_us, 60.0])
	var cm = mw.get("crew_manager") if mw != null else null
	if cm != null and cm.has_method("_physics_process"):
		rows.append(["CrewManager._physics_process", _time_calls(func(): cm._physics_process(1.0 / 60.0), 30), 60.0])
	var board := get_node_or_null("/root/NpcAutonomyBoard")
	if board != null and board.has_method("_process"):
		rows.append(["NpcAutonomyBoard._process", _time_calls(func(): board._process(1.0 / 60.0), 30), 60.0])
	var hud = mw.get("hud") if mw != null else null
	if hud == null and mw != null:
		hud = mw.find_child("HUD", true, false)
	if hud != null and hud.has_method("_process"):
		rows.append(["HUD._process", _time_calls(func(): hud._process(1.0 / 60.0), 30), 60.0])

	rows.sort_custom(func(a, b): return float(a[1]) * float(a[2]) > float(b[1]) * float(b[2]))
	var attributed_ms_per_frame := 0.0
	print("  info  : %-48s %10s %9s %11s" % ["system", "us/call", "calls/s", "ms/frame@60"])
	for r in rows:
		var us : float = float(r[1])
		var per_s : float = float(r[2])
		var ms_frame : float = us * per_s / 60.0 / 1000.0
		attributed_ms_per_frame += ms_frame
		print("  info  : %-48s %10.1f %9.0f %11.3f" % [String(r[0]), us, per_s, ms_frame])
	print("  info  : attributed %.2f ms/frame of a %.2f ms TIME_PROCESS + %.2f ms TIME_PHYSICS reference (unattributed = engine, physics server, navigation, render-less servers, everything not listed)"
		% [attributed_ms_per_frame, proc_ms, phys_ms])

	world.queue_free()
	await get_tree().process_frame
	_cleanup_scratch()
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
