extends Node
## MAINWORLD FPS BENCH — WINDOWED (real GPU), informational, not in the harness.
##
##   godot --path <proj> --resolution 1600x900 res://src/tests/bench_mainworld_fps.tscn
##   env (all optional): PERF_SAVE_DIR=<abs dir holding <stem>_factory.json/_save.json>
##                       PERF_SLOT=<stem>   PERF_FRAMES=300   PERF_WARMUP_S=120
##
## Unlike bench_mainworld_perf.gd (headless, CPU only) this needs a window: it reads
## the GPU's own timers (RenderingServer.viewport_get_measured_render_time_*), the
## draw-call/primitive counters, and attributes cost by ABLATIONS THAT MOVE FRAME TIME
## BY MUCH MORE THAN ITS WINDOW-TO-WINDOW NOISE:
##   render loop off      -> what remains is simulation + physics (+ engine) cost
##   world processing off -> what remains is rendering (+ engine) cost
##   3D resolution 50 %   -> if fps jumps, the frame is fill-rate / GPU bound
##   shadows off, MSAA off -> the price of each
## Every row prints its own min..max next to the median; a delta smaller than that
## range is noise and must not be quoted. VSync is forced OFF so frame time is not
## quantised to the display refresh; the player's real fps is capped by their vsync.
## Frame time is wall-clock between frames, so it includes everything.
##
## user:// SAFETY: the real save is never booted. Its pair is COPIED to the scratch
## slot `__fpsbench__`, WorldLayout is pointed at a scratch path before boot (the 60 s
## autosave would otherwise rewrite world_layout.json), scratch files removed at exit.

const SCRATCH := "__fpsbench__"
const WL_SCRATCH := "user://__fpsbench___world.json"
const STEADY_MS := 80.0

var _world : Node3D = null
var _frames : int = 300
var _ring : PackedFloat64Array = PackedFloat64Array()
var _last_us : int = 0
var _tracking : bool = true


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us != 0 and _tracking:
		_ring.append(float(now - _last_us) / 1000.0)
		if _ring.size() > 60:
			_ring.remove_at(0)
	_last_us = now


func _ready() -> void:
	print("=== MAINWORLD FPS BENCH (windowed) ===")
	if DisplayServer.get_name() == "headless":
		print("FATAL: headless has no GPU — run WITHOUT --headless")
		get_tree().quit(2)
		return
	_frames = int(OS.get_environment("PERF_FRAMES")) if OS.get_environment("PERF_FRAMES") != "" else 300
	var warm_s := float(OS.get_environment("PERF_WARMUP_S")) if OS.get_environment("PERF_WARMUP_S") != "" else 120.0

	if not _prepare_scratch_slot():
		print("FATAL: no save pair to copy — set PERF_SAVE_DIR / PERF_SLOT")
		get_tree().quit(2)
		return
	WorldLayout.layout_path_override = WL_SCRATCH
	if WorldLayout.get_layout_path() != WL_SCRATCH:
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to run")
		get_tree().quit(2)
		return

	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	var vp := get_viewport()
	var vrid := vp.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vrid, true)
	print("adapter : %s | vendor %s | type %d | driver %s"
		% [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
		int(RenderingServer.get_video_adapter_type()), OS.get_video_adapter_driver_info()])
	print("renderer: %s | window %s | vsync forced OFF | msaa_3d %d | scaling_3d_scale %.2f | ssaa/taa %s/%s"
		% [RenderingServer.get_current_rendering_method(), str(vp.get_visible_rect().size),
		int(vp.msaa_3d), vp.scaling_3d_scale, str(vp.screen_space_aa), str(vp.use_taa)])

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", SCRATCH)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	var t0 := Time.get_ticks_msec()
	var settled := false
	while float(Time.get_ticks_msec() - t0) / 1000.0 < warm_s:
		await get_tree().process_frame
		if _ring.size() >= 60 and _ring_max() < STEADY_MS:
			settled = true
			break
	print("boot: frame time %s after %.1f s" % ["SETTLED" if settled else "DID NOT SETTLE",
		float(Time.get_ticks_msec() - t0) / 1000.0])
	for _i in 30:
		await get_tree().process_frame

	_census()

	if OS.get_environment("PERF_STAGE") == "split":
		await _split_stage()
		_cleanup_scratch()
		get_tree().quit(0)
		return
	if OS.get_environment("PERF_STAGE") == "throttle":
		await _throttle_stage()
		_cleanup_scratch()
		get_tree().quit(0)
		return
	if OS.get_environment("PERF_STAGE") == "lf":
		await _lf_stage()
		_cleanup_scratch()
		get_tree().quit(0)
		return
	if OS.get_environment("PERF_STAGE") == "solo":
		await _solo_stage()
		_cleanup_scratch()
		get_tree().quit(0)
		return

	print("\n-- A. spawn view, full world --")
	var base1 := await _sample("baseline#1", _frames)

	var cam := get_viewport().get_camera_3d()
	print("camera  : %s at %s" % [cam.get_path() if cam else "NONE",
		str(cam.global_position) if cam else "-"])

	print("\n-- B. ablations at the spawn view (each bracketed by a baseline) --")
	# render loop off: frame time = sim + physics + engine only
	RenderingServer.render_loop_enabled = false
	var no_render := await _sample("render loop OFF (sim only)", _frames)
	RenderingServer.render_loop_enabled = true
	var base2 := await _sample("baseline#2", _frames)

	# world processing off: frame time = render + engine only
	var saved_mode := _world.process_mode
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	var no_sim := await _sample("world processing OFF (render only)", _frames)
	_world.process_mode = saved_mode
	var base3 := await _sample("baseline#3", _frames)

	var saved_scale := vp.scaling_3d_scale
	vp.scaling_3d_scale = 0.5
	var half := await _sample("3D resolution 50 %", _frames)
	vp.scaling_3d_scale = saved_scale

	var lights := _shadow_lights()
	for l in lights:
		(l as Light3D).shadow_enabled = false
	var no_shadow := await _sample("all shadows OFF (%d lights)" % lights.size(), _frames)
	for l in lights:
		(l as Light3D).shadow_enabled = true

	var saved_msaa := vp.msaa_3d
	vp.msaa_3d = Viewport.MSAA_DISABLED
	var no_msaa := await _sample("MSAA OFF (was %d)" % int(saved_msaa), _frames)
	vp.msaa_3d = saved_msaa
	var base4 := await _sample("baseline#4", _frames)

	# A view among the machines: mean position of every placed object.
	var moved := _teleport_into_plant()
	if moved:
		for _i in 90:
			await get_tree().process_frame
		print("\n-- C. inside the plant (player moved to the placed-object centroid) --")
		await _sample("plant view baseline", _frames)
		RenderingServer.render_loop_enabled = false
		await _sample("plant view, render loop OFF", _frames)
		RenderingServer.render_loop_enabled = true

	print("\n== SUMMARY (median frame ms | fps) ==")
	var b := _median([base1["med"], base2["med"], base3["med"], base4["med"]])
	var brange := [minf(minf(base1["med"], base2["med"]), minf(base3["med"], base4["med"])),
		maxf(maxf(base1["med"], base2["med"]), maxf(base3["med"], base4["med"]))]
	print("  baseline (4 windows): %.2f ms (%.1f fps)   window-to-window %.2f..%.2f ms" % [b, 1000.0 / b, brange[0], brange[1]])
	for row in [["sim+physics only (render off)", no_render], ["render only (world off)", no_sim],
			["3D resolution 50 %", half], ["shadows off", no_shadow], ["MSAA off", no_msaa]]:
		var m : float = row[1]["med"]
		print("  %-32s %.2f ms (%.1f fps)  delta vs baseline %+.2f ms  [%s]" % [row[0], m, 1000.0 / m, m - b,
			"beyond noise" if absf(m - b) > (brange[1] - brange[0]) else "WITHIN NOISE"])

	_cleanup_scratch()
	get_tree().quit(0)


# ─── SPLIT STAGE (PERF_STAGE=split) ──────────────────────────────────────────
# PROCESS_MODE_DISABLED on the world removed ~46 ms/frame, but it disables scripts,
# collision bodies (they leave the physics space) and more, all at once. This splits
# that lump with switches that each remove ONE thing:
#   scripts off  : set_process/set_physics_process(false) on every node that has them on
#   physics off  : PhysicsServer3D.set_active(false) — the step stops, bodies stay
#   nav off      : NavigationServer3D.set_active(false)
# Alternating off/on windows, REPS pairs each, median of paired deltas + range.
func _split_stage() -> void:
	const REPS := 3
	var groups := _processing_nodes_by_script()
	var total_nodes := 0
	for k in groups:
		total_nodes += (groups[k] as Array).size()
	print("\n-- SPLIT: %d nodes run a script _process/_physics_process, in %d distinct scripts --" % [total_nodes, groups.size()])
	var labels : Array = groups.keys()
	labels.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size())
	for i in range(mini(15, labels.size())):
		print("    %5d x %s" % [(groups[labels[i]] as Array).size(), labels[i]])

	var all_nodes : Array = []
	for k in labels:
		all_nodes.append_array(groups[k])

	var results : Array = []
	for nm in ["scripts off", "physics server off", "navigation server off", "ALL THREE off"]:
		var deltas : Array = []
		var offs : Array = []
		for r in REPS:
			var saved : Array = []
			if nm == "scripts off" or nm == "ALL THREE off":
				for n in all_nodes:
					if is_instance_valid(n):
						saved.append([n, (n as Node).is_processing(), (n as Node).is_physics_processing()])
						(n as Node).set_process(false)
						(n as Node).set_physics_process(false)
			if nm == "physics server off" or nm == "ALL THREE off":
				PhysicsServer3D.set_active(false)
			if nm == "navigation server off" or nm == "ALL THREE off":
				NavigationServer3D.set_active(false)
			var off := await _sample("  %s #%d OFF" % [nm, r + 1], _frames)
			for s in saved:
				if is_instance_valid(s[0]):
					(s[0] as Node).set_process(s[1])
					(s[0] as Node).set_physics_process(s[2])
			PhysicsServer3D.set_active(true)
			NavigationServer3D.set_active(true)
			var on := await _sample("  %s #%d ON " % [nm, r + 1], _frames)
			deltas.append(float(on["med"]) - float(off["med"]))
			offs.append(float(off["med"]))
		results.append([nm, deltas])
	print("\n== SPLIT SUMMARY: median(ON) - median(OFF) per paired window, ms of frame time ==")
	for r in results:
		var d : Array = r[1]
		var pd := PackedFloat64Array(d)
		print("  %-24s %+7.2f ms  (pairs: %s)  range %.1f..%.1f" % [r[0], _median_arr(pd),
			", ".join(d.map(func(x): return "%.1f" % x)), _sorted(pd)[0], _sorted(pd)[pd.size() - 1]])


# ─── SOLO STAGE (PERF_STAGE=solo) ────────────────────────────────────────────
# split showed script _process/_physics_process is ~47 ms of a ~65 ms frame, and that
# with ALL of them off the frame is quiet (~17 ms, window range ~1-3 ms). That quiet
# floor is what makes this precise: with everything off, switch ONE script group on,
# measure, switch it off. cost(group) = median(solo window) - median(floor window).
# The floor is re-measured between groups so drift shows up in the table.
# Caveat: a script that depends on another (e.g. a belt on a machine) is measured
# without its partner running; this is the marginal cost, not a partition of the 47 ms.
func _solo_stage() -> void:
	const REPS := 2
	var groups := _processing_nodes_by_script()
	var labels : Array = groups.keys()
	labels.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size())
	var all_nodes : Array = []
	for k in labels:
		all_nodes.append_array(groups[k])
	var orig : Array = []
	for n in all_nodes:
		orig.append([n, (n as Node).is_processing(), (n as Node).is_physics_processing()])
	_set_scripts(orig, false)
	print("\n-- SOLO: %d nodes / %d script groups; all off, one group on at a time --" % [all_nodes.size(), labels.size()])
	var floors : Array = []
	var f0 := await _sample("floor (all scripts off)", _frames)
	floors.append(float(f0["med"]))
	var rows : Array = []
	for label in labels:
		var mine : Array = []
		for s in orig:
			if (groups[label] as Array).has(s[0]):
				mine.append(s)
		var meds : Array = []
		for r in REPS:
			_set_scripts(mine, true)
			var w := await _sample("%s x%d (#%d)" % [label, (groups[label] as Array).size(), r + 1], _frames)
			_set_scripts(mine, false)
			meds.append(float(w["med"]))
		var fl := await _sample("floor", _frames)
		floors.append(float(fl["med"]))
		rows.append([label, (groups[label] as Array).size(), meds, floors[floors.size() - 2], floors[floors.size() - 1]])
	_set_scripts(orig, true)
	print("\n== SOLO SUMMARY: marginal frame-time cost of each script group (ms), heaviest first ==")
	print("  floor windows: %s ms" % ", ".join(floors.map(func(x): return "%.1f" % x)))
	var out : Array = []
	for r in rows:
		var fl : float = (float(r[3]) + float(r[4])) / 2.0
		var pm := PackedFloat64Array(r[2])
		out.append([_median_arr(pm) - fl, r[0], r[1], (r[2] as Array).map(func(x): return x - fl)])
	out.sort_custom(func(a, b): return a[0] > b[0])
	var total := 0.0
	for o in out:
		total += maxf(0.0, o[0])
		print("  %+7.2f ms  %-34s %4d nodes   per-window %s" % [o[0], o[1], o[2],
			", ".join((o[3] as Array).map(func(x): return "%+.1f" % x))])
	print("  sum of positive marginals: %.1f ms (compare: scripts-off delta in split = ~47.6 ms)" % total)


# ─── THROTTLE STAGE (PERF_STAGE=throttle) ────────────────────────────────────
# EXPERIMENT ONLY — nothing here ships. What would fps be if LineFlow.tick ran on a
# fixed sim step instead of every rendered frame? LineFlow's own _process is stopped
# and tick(accumulated_delta) is called from here every 1/hz s. Sim time is conserved
# (the accumulated delta is passed whole), which is exactly what a real throttle would do.
# Alternates: baseline / 10 Hz / baseline / 20 Hz / baseline, 3 rounds. p95 and the
# 1%-low are printed because a throttle trades a lower MEAN for a periodic spike.
func _throttle_stage() -> void:
	var lf = _world.get("line_flow")
	if lf == null:
		print("FATAL: MainWorld.line_flow missing")
		return
	var ctl := _Throttle.new()
	ctl.lf = lf
	add_child(ctl)
	var rows : Dictionary = {}
	for r in 3:
		for mode in [["every frame (as shipped)", 0.0], ["10 Hz", 10.0], ["20 Hz", 20.0]]:
			ctl.hz = mode[1]
			lf.set_process(mode[1] == 0.0)
			ctl.set_process(mode[1] > 0.0)
			var w := await _sample("%s #%d" % [mode[0], r + 1], _frames)
			if not rows.has(mode[0]):
				rows[mode[0]] = []
			(rows[mode[0]] as Array).append(w)
	lf.set_process(true)
	ctl.queue_free()
	print("\n== THROTTLE SUMMARY (median over 3 windows of: median frame ms | mean fps | p95 ms | 1%-low fps) ==")
	for k in rows:
		var meds := PackedFloat64Array()
		var means := PackedFloat64Array()
		var p95s := PackedFloat64Array()
		var lows := PackedFloat64Array()
		for w in rows[k]:
			meds.append(w["med"])
			means.append(w["mean_fps"])
			p95s.append(w["p95"])
			lows.append(w["low_fps"])
		print("  %-26s %6.1f ms | %5.1f fps | p95 %6.1f ms | 1%%-low %5.1f fps   (median-ms windows: %s)" % [
			k, _median_arr(meds), _median_arr(means), _median_arr(p95s), _median_arr(lows),
			", ".join(Array(meds).map(func(x): return "%.1f" % x))])


class _Throttle extends Node:
	var lf : Node = null
	var hz : float = 10.0
	var _acc : float = 0.0
	func _process(delta: float) -> void:
		_acc += delta
		if _acc >= 1.0 / hz:
			lf.call("tick", _acc)
			_acc = 0.0


# ─── LF STAGE (PERF_STAGE=lf) ────────────────────────────────────────────────
# LineFlow._process(delta) just calls tick(delta), every rendered frame. Stop its own
# _process, then drive the SAME sequence from here (copied from LineFlow.tick, minus
# the mass-balance log) timing each step with Time.get_ticks_usec. Everything else in
# the world keeps running normally, so the numbers are in situ.
func _lf_stage() -> void:
	var lf = _world.get("line_flow")
	if lf == null:
		print("FATAL: MainWorld.line_flow missing")
		return
	print("\n-- LF: LineFlow has %d nodes; groups: bale=%d floor_pile=%d waste_container=%d --" % [
		(lf.get("_nodes") as Array).size(), get_tree().get_nodes_in_group("bale").size(),
		get_tree().get_nodes_in_group("floor_pile").size(), get_tree().get_nodes_in_group("waste_container").size()])
	lf.set_process(false)
	var steps : Array = [
		["_tick_cache_spatial_queries", []],
		["_tick_plc_power_downstream", ["d"]],
		["_tick_feed", ["d"]],
		["_tick_process_machines", ["d"]],
		["_tick_advanced_systems", ["d"]],
		["_tick_bunker_shredder2_interlock", []],
		["_tick_dryer_pairs", ["d"]],
		["_tick_route_outputs", ["d"]],
		["_push_scada", ["d"]],
		["_update_label", []],
	]
	var acc : Dictionary = {}
	var samples := {}
	for s in steps:
		samples[s[0]] = []
	var whole : Array = []
	var last := Time.get_ticks_usec()
	var n := int(OS.get_environment("PERF_FRAMES")) if OS.get_environment("PERF_FRAMES") != "" else 300
	for i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var d := float(now - last) / 1e6
		last = now
		var t_all := Time.get_ticks_usec()
		for s in steps:
			var t0 := Time.get_ticks_usec()
			if (s[1] as Array).is_empty():
				lf.call(s[0])
			else:
				lf.call(s[0], d)
			(samples[s[0]] as Array).append(float(Time.get_ticks_usec() - t0) / 1000.0)
		whole.append(float(Time.get_ticks_usec() - t_all) / 1000.0)
	lf.set_process(true)
	print("\n== LF BREAKDOWN over %d frames: ms per call (mean | median | max), share of the summed mean ==" % n)
	var total := _mean(PackedFloat64Array(whole))
	var rows : Array = []
	for s in steps:
		var a := PackedFloat64Array(samples[s[0]])
		rows.append([_mean(a), _median_arr(a), _sorted(a)[a.size() - 1], s[0]])
	rows.sort_custom(func(a, b): return a[0] > b[0])
	for r in rows:
		print("  %7.2f | %7.2f | %8.2f ms  %5.1f %%  %s" % [r[0], r[1], r[2], 100.0 * r[0] / maxf(total, 0.001), r[3]])
	print("  whole tick() (steps above; QaLab/assessment omitted): mean %.2f ms | median %.2f ms | max %.2f ms" % [
		total, _median_arr(PackedFloat64Array(whole)), _sorted(PackedFloat64Array(whole))[whole.size() - 1]])


func _set_scripts(entries: Array, on: bool) -> void:
	for s in entries:
		if is_instance_valid(s[0]):
			if on:
				(s[0] as Node).set_process(s[1])
				(s[0] as Node).set_physics_process(s[2])
			else:
				(s[0] as Node).set_process(false)
				(s[0] as Node).set_physics_process(false)


func _processing_nodes_by_script() -> Dictionary:
	var out : Dictionary = {}
	var stack : Array = [_world]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n.is_processing() or n.is_physics_processing()):
			continue
		var s = n.get_script()
		var label : String = (s as Script).resource_path.get_file() if s != null else "<engine:%s>" % n.get_class()
		if not out.has(label):
			out[label] = []
		(out[label] as Array).append(n)
	return out


# ─── sampling ────────────────────────────────────────────────────────────────
func _sample(label: String, n: int) -> Dictionary:
	var vrid := get_viewport().get_viewport_rid()
	var dt : PackedFloat64Array = PackedFloat64Array()
	var cpu : PackedFloat64Array = PackedFloat64Array()
	var gpu : PackedFloat64Array = PackedFloat64Array()
	var calls : PackedFloat64Array = PackedFloat64Array()
	var prims : PackedFloat64Array = PackedFloat64Array()
	var objs : PackedFloat64Array = PackedFloat64Array()
	var proc : PackedFloat64Array = PackedFloat64Array()
	var phys : PackedFloat64Array = PackedFloat64Array()
	await get_tree().process_frame
	var last := Time.get_ticks_usec()
	for _i in n:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		dt.append(float(now - last) / 1000.0)
		last = now
		cpu.append(RenderingServer.viewport_get_measured_render_time_cpu(vrid))
		gpu.append(RenderingServer.viewport_get_measured_render_time_gpu(vrid))
		calls.append(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
		prims.append(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
		objs.append(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
		proc.append(Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)
		phys.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)
	var med := _median_arr(dt)
	var s := _sorted(dt)
	var p95 := s[int(float(s.size() - 1) * 0.95)]
	var p99 := s[int(float(s.size() - 1) * 0.99)]
	# "1% low" fps = fps at the 99th-percentile frame time
	print("  %-38s median %6.2f ms (%5.1f fps) min..max %.1f..%.1f | p95 %.1f p99 %.1f (1%%-low %.1f fps) | mean fps %.1f"
		% [label, med, 1000.0 / med, s[0], s[s.size() - 1], p95, p99, 1000.0 / p99, 1000.0 / _mean(dt)])
	print("        render cpu %.2f ms | gpu %.2f ms | draw calls %.0f | prims %.0f | objects %.0f | TIME_PROCESS %.2f ms (unreliable in absolute terms)"
		% [_median_arr(cpu), _median_arr(gpu), _median_arr(calls), _median_arr(prims), _median_arr(objs), _median_arr(proc)])
	return {"med": med, "gpu": _median_arr(gpu), "cpu": _median_arr(cpu), "calls": _median_arr(calls),
		"mean_fps": 1000.0 / _mean(dt), "p95": p95, "low_fps": 1000.0 / p99}


func _census() -> void:
	var meshes := 0
	var vis_meshes := 0
	var casters := 0
	var ranged := 0
	var multimeshes := 0
	var mm_inst := 0
	var lights := 0
	var shadow_lights := 0
	var particles := 0
	var surfaces := 0
	var stack : Array = [get_tree().root]
	var total := 0
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		total += 1
		for c in n.get_children():
			stack.append(c)
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			meshes += 1
			if mi.is_visible_in_tree():
				vis_meshes += 1
				if mi.cast_shadow != GeometryInstance3D.SHADOW_CASTING_SETTING_OFF:
					casters += 1
				if mi.mesh != null:
					surfaces += mi.mesh.get_surface_count()
			if mi.visibility_range_end > 0.0:
				ranged += 1
		elif n is MultiMeshInstance3D:
			multimeshes += 1
			var mm := (n as MultiMeshInstance3D).multimesh
			if mm != null:
				mm_inst += mm.instance_count
		elif n is Light3D:
			lights += 1
			if (n as Light3D).shadow_enabled:
				shadow_lights += 1
		elif n is GPUParticles3D or n is CPUParticles3D:
			particles += 1
	print("census  : %d nodes | %d MeshInstance3D (%d visible, %d surfaces, %d shadow-casting, %d with visibility range) | %d MultiMesh (%d instances) | %d lights (%d shadowed) | %d particle systems"
		% [total, meshes, vis_meshes, surfaces, casters, ranged, multimeshes, mm_inst, lights, shadow_lights, particles])
	var env := get_viewport().world_3d.environment if get_viewport().world_3d else null
	if env != null:
		print("env     : glow %s | ssao %s | ssr %s | sdfgi %s | volumetric fog %s | tonemap %d"
			% [str(env.glow_enabled), str(env.ssao_enabled), str(env.ssr_enabled), str(env.sdfgi_enabled),
			str(env.volumetric_fog_enabled), int(env.tonemap_mode)])
	else:
		print("env     : no Environment on the root world_3d (may be on a WorldEnvironment node)")


func _shadow_lights() -> Array:
	var out : Array = []
	var stack : Array = [get_tree().root]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Light3D and (n as Light3D).shadow_enabled:
			out.append(n)
	return out


func _teleport_into_plant() -> bool:
	var pl := get_tree().get_first_node_in_group("player")
	if pl == null or not (pl is Node3D):
		print("(no node in group 'player' — skipping the plant view)")
		return false
	var sum := Vector3.ZERO
	var k := 0
	for n in get_tree().get_nodes_in_group("placed_object"):
		if n is Node3D:
			sum += (n as Node3D).global_position
			k += 1
	if k == 0:
		print("(no placed objects — skipping the plant view)")
		return false
	var c := sum / float(k)
	(pl as Node3D).global_position = c + Vector3(0.0, 2.0, 6.0)
	print("player moved to placed-object centroid %s (%d objects)" % [str(c), k])
	return true


# ─── stats ───────────────────────────────────────────────────────────────────
func _ring_max() -> float:
	var m := 0.0
	for v in _ring:
		m = maxf(m, v)
	return m

func _sorted(a: PackedFloat64Array) -> PackedFloat64Array:
	var s := a.duplicate()
	s.sort()
	return s

func _median_arr(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var s := _sorted(a)
	return s[s.size() / 2]

func _mean(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var t := 0.0
	for v in a:
		t += v
	return t / float(a.size())

func _median(a: Array) -> float:
	var p := PackedFloat64Array(a)
	return _median_arr(p)


# ─── scratch slot ────────────────────────────────────────────────────────────
func _prepare_scratch_slot() -> bool:
	var dir := OS.get_environment("PERF_SAVE_DIR")
	var stem := OS.get_environment("PERF_SLOT")
	if stem == "":
		return false
	var src_base := (dir + "/" if dir != "" else "user://")
	print("scratch slot copied from '%s%s'" % [src_base, stem])
	for suffix in ["_factory.json", "_save.json"]:
		DirAccess.copy_absolute("%s%s%s" % [src_base, stem, suffix], "user://%s%s" % [SCRATCH, suffix])
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
