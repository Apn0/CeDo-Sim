extends Node
## MAINWORLD CPU-SIDE PERFORMANCE BENCH — measured, headless-safe.
##
##   godot --headless --path <proj> res://src/tests/bench_mainworld_perf.tscn
##   PERF_SLOT=<stem>  PERF_WARMUP_S=90 (max wait for settle)  PERF_FRAMES=240  PERF_TOP=12   (env, all optional)
##
## WHAT THIS MEASURES — AND WHAT IT CANNOT.
## Headless runs the dummy renderer, so this is the CPU side ONLY: script
## `_process`, `_physics_process`, the physics server step and navigation. It says
## NOTHING about GPU cost, draw calls or fill rate. HotspotProfiler already
## censuses WHAT is in the tree; it cannot time anything, and its header records
## a "7-11 FPS / 60-130 ms proc floor" without ever attributing it.
##
## HOW COST IS ATTRIBUTED (ABLATION, no source instrumentation): for each of the
## most numerous processing scripts, switch off `_process` / `_physics_process` on
## every node running it, measure a window, switch them back on, and take the
## difference against a baseline window measured immediately before AND after
## (bracketing cancels slow drift). The delta is what that script costs per frame.
## It is an ESTIMATE: it also removes second-order work the script triggers, and
## disabling a script briefly changes sim behaviour — the bench discards the run
## afterwards, it never saves.
##
## MEASURED LIMITS OF THIS TOOL (first runs, 2026-09-21 — read before quoting it):
##   * TRUSTWORTHY: the boot trace (the world's `_ready` blocked one frame for
##     4.3-5.0 s in two runs), the frame COUNT / wall-clock fps, and the node census.
##   * NOT TRUSTWORTHY: the ablation attribution. Window-to-window variation of the
##     headless loop was 20-50 % (sim dynamics move), so almost every per-script
##     delta was smaller than its own +/-range; even "ALL scripts off" read
##     8.6 +/- 15 ms. A row is only a finding if its delta exceeds its range.
##   * DO NOT QUOTE the physics column in absolute ms: TIME_PHYSICS_PROCESS read
##     20-31 ms per tick while the loop ticked at ~60 Hz (16.7 ms per tick wall),
##     which is impossible if it were the tick duration. Its semantics are
##     unresolved. Use fps and the boot trace.
##   Getting real attribution needs a quieter signal (pause the sim, fixed-step
##   replay, or many more windows) — not a better estimator on this one.
##
## user:// SAFETY: the operator's real save is never booted. The newest real
## `<stem>_factory.json` / `<stem>_save.json` pair is COPIED into the scratch slot
## `__perfbench__` and that slot is what MainWorld loads; the scratch files are
## removed at the end. MainWorld's 60 s autosave therefore only ever writes there.
## The bench outlives that 60 s autosave, and the autosave ends in
## WorldLayout.save() — the operator's world ground truth — so WorldLayout is
## pointed at a scratch path (layout_path_override) BEFORE the world boots.

const SCRATCH := "__perfbench__"
const WL_SCRATCH := "user://__perfbench___world.json"
const HITCH_MS := 100.0
const REPS := 3
const STEADY_MS := 60.0

var _world : Node3D = null
var _phys_ms : PackedFloat64Array = PackedFloat64Array()
var _proc_ms : PackedFloat64Array = PackedFloat64Array()
var _collecting : bool = false
var _frames : int = 240
var _boot_phase : bool = false
var _t_world : int = 0
var _ring : PackedFloat64Array = PackedFloat64Array()
var _hitches : Array = []


func _ready() -> void:
	print("=== MAINWORLD PERF BENCH (CPU-side, headless-safe) ===")
	var warm_s := float(OS.get_environment("PERF_WARMUP_S")) if OS.get_environment("PERF_WARMUP_S") != "" else 90.0
	_frames = int(OS.get_environment("PERF_FRAMES")) if OS.get_environment("PERF_FRAMES") != "" else 240
	var top_n := int(OS.get_environment("PERF_TOP")) if OS.get_environment("PERF_TOP") != "" else 12

	if not _prepare_scratch_slot():
		print("FATAL: no real save to copy — nothing to measure")
		get_tree().quit(2)
		return

	# Refuse to run unless the redirect is confirmed: without it the 60 s autosave
	# would rewrite the real world_layout.json.
	WorldLayout.layout_path_override = WL_SCRATCH
	if WorldLayout.get_layout_path() != WL_SCRATCH:
		print("FATAL: WorldLayout.layout_path_override not honoured — refusing to run")
		get_tree().quit(2)
		return

	var bus := get_node_or_null("/root/EventBus")
	if bus:
		bus.set_meta("pending_save_name", SCRATCH)
		bus.set_meta("pending_is_new_save", false)
	var scn := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	_world = scn.instantiate() as Node3D
	await get_tree().process_frame
	get_tree().root.add_child(_world)
	get_tree().current_scene = _world
	_t_world = Time.get_ticks_msec()

	# BOOT TRACE. The first version of this bench warmed up for a fixed 8 s and
	# measured a "baseline" window containing ONE frame of 5,557 ms — the boot hitch
	# itself. So: record every frame slower than HITCH_MS from the moment the world
	# is added, wait for the frame time to SETTLE (60 consecutive frames under
	# STEADY_MS), and only then measure, by frame count rather than seconds.
	print("booting; tracing hitches (> %.0f ms) until frame time settles (max %.0f s) ..." % [HITCH_MS, warm_s])
	_boot_phase = true
	var t_boot := Time.get_ticks_msec()
	var settled := false
	while float(Time.get_ticks_msec() - t_boot) / 1000.0 < warm_s:
		await get_tree().process_frame
		if _ring.size() >= 60 and _ring_max() < STEADY_MS:
			settled = true
			break
	_boot_phase = false
	print("  frame time %s after %.1f s; %d frame(s) over %.0f ms during boot" % [
		"SETTLED" if settled else "DID NOT SETTLE", float(Time.get_ticks_msec() - t_boot) / 1000.0,
		_hitches.size(), HITCH_MS])
	_hitches.sort_custom(func(a, b): return a[1] > b[1])
	for i in range(mini(8, _hitches.size())):
		print("    hitch  t+%6.2f s   %8.1f ms" % [_hitches[i][0], _hitches[i][1]])

	var hp := get_node_or_null("/root/HotspotProfiler")
	if hp != null:
		hp.call("_dump_report")

	print("
-- baseline: %d windows of %d frames --" % [REPS, _frames])
	var base_windows : Array = []
	for r in REPS:
		var w := await _sample(_frames)
		base_windows.append(w)
		_print_stats("baseline#%d" % (r + 1), w)
	var base_proc := _median(base_windows.map(func(w): return _mean(w["proc"])))
	var base_phys := _median(base_windows.map(func(w): return _mean(w["phys"])))
	var spread_phys := _range(base_windows.map(func(w): return _mean(w["phys"])))
	print("  baseline median: process %.2f ms, physics %.2f ms per tick (physics window-to-window spread %.2f ms)" % [base_proc, base_phys, spread_phys])

	# Group every node under the world that is actually being processed by script.
	var groups := _processing_nodes_by_script()
	var labels : Array = groups.keys()
	labels.sort_custom(func(a, b): return (groups[a] as Array).size() > (groups[b] as Array).size())
	print("
%d distinct processing scripts under the world; ablating the top %d by node count (+ ALL)" % [labels.size(), top_n])

	# ABLATION. Each target is switched OFF and back ON REPS times, ALTERNATING
	# (off, on, off, on, ...), one window each. The delta is the MEDIAN of the paired
	# on-minus-off means, and the spread of those pairs is reported next to it: the
	# first version of this bench used one bracketed pair and its own noise (up to
	# 48 ms) was larger than every delta, so it attributed nothing.
	var rows : Array = []
	var targets : Array = []
	for i in range(mini(top_n, labels.size())):
		targets.append([labels[i], groups[labels[i]]])
	var all_nodes : Array = []
	for k in labels:
		all_nodes.append_array(groups[k])
	targets.append(["** ALL processing scripts **", all_nodes])

	for t in targets:
		var label : String = t[0]
		var nodes : Array = t[1]
		var d_proc : Array = []
		var d_phys : Array = []
		for r in REPS:
			var saved : Array = []
			for n in nodes:
				if is_instance_valid(n):
					saved.append([n, (n as Node).is_processing(), (n as Node).is_physics_processing()])
					(n as Node).set_process(false)
					(n as Node).set_physics_process(false)
			var off := await _sample(_frames)
			for s in saved:
				if is_instance_valid(s[0]):
					(s[0] as Node).set_process(s[1])
					(s[0] as Node).set_physics_process(s[2])
			var on := await _sample(_frames)
			d_proc.append(_mean(on["proc"]) - _mean(off["proc"]))
			d_phys.append(_mean(on["phys"]) - _mean(off["phys"]))
		rows.append({
			"label": label, "nodes": nodes.size(),
			"d_proc": _median(d_proc), "d_phys": _median(d_phys),
			"s_proc": _range(d_proc), "s_phys": _range(d_phys),
		})

	rows.sort_custom(func(a, b): return (a["d_proc"] + a["d_phys"]) > (b["d_proc"] + b["d_phys"]))
	print("
-- attributed cost per frame/tick (ms): median of %d paired on-minus-off windows --" % REPS)
	print("  %-34s %6s %9s %9s %9s %9s" % ["script", "nodes", "proc_ms", "+/-range", "phys_ms", "+/-range"])
	for r in rows:
		print("  %-34s %6d %9.2f %9.2f %9.2f %9.2f" % [r["label"], r["nodes"], r["d_proc"], r["s_proc"], r["d_phys"], r["s_phys"]])
	print("  (a delta smaller than its +/-range is NOT distinguishable from zero)")

	_cleanup_scratch()
	print("\nResult: PASS (bench completed — informational, no assertions)")
	get_tree().quit(0)


# ─── sampling ────────────────────────────────────────────────────────────────
func _physics_process(_d: float) -> void:
	if _collecting:
		_phys_ms.append(Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0)


func _process(_d: float) -> void:
	var ms := Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	_ring.append(ms)
	if _ring.size() > 60:
		_ring.remove_at(0)
	if _boot_phase and ms > HITCH_MS:
		_hitches.append([float(Time.get_ticks_msec() - _t_world) / 1000.0, ms])
	if _collecting:
		_proc_ms.append(ms)


func _ring_max() -> float:
	var m := 0.0
	for v in _ring:
		m = maxf(m, v)
	return m


func _sample(frames: int) -> Dictionary:
	_phys_ms.clear()
	_proc_ms.clear()
	_collecting = true
	var t0 := Time.get_ticks_msec()
	while _proc_ms.size() < frames:
		await get_tree().process_frame
	_collecting = false
	return {"proc": _proc_ms.duplicate(), "phys": _phys_ms.duplicate(),
		"wall_s": float(Time.get_ticks_msec() - t0) / 1000.0}


func _wait_s(seconds: float) -> void:
	await get_tree().create_timer(seconds, true, false, true).timeout


func _median(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return float(b[b.size() / 2])


func _range(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var lo := float(a[0])
	var hi := float(a[0])
	for v in a:
		lo = minf(lo, float(v))
		hi = maxf(hi, float(v))
	return hi - lo


func _mean(a: PackedFloat64Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for v in a:
		s += v
	return s / float(a.size())


func _pct(a: PackedFloat64Array, p: float) -> float:
	if a.is_empty():
		return 0.0
	var b := a.duplicate()
	b.sort()
	return b[clampi(int(ceil(p * float(b.size()))) - 1, 0, b.size() - 1)]


func _print_stats(tag: String, s: Dictionary) -> void:
	var pr : PackedFloat64Array = s["proc"]
	var ph : PackedFloat64Array = s["phys"]
	print("  %s  process: n=%d in %.2f s (%.0f fps)  mean %.2f ms  p95 %.2f  p99 %.2f  max %.2f" % [
		tag, pr.size(), float(s["wall_s"]), float(pr.size()) / maxf(float(s["wall_s"]), 0.001),
		_mean(pr), _pct(pr, 0.95), _pct(pr, 0.99), _pct(pr, 1.0)])
	print("  %s  physics: n=%d mean %.2f ms  p95 %.2f  p99 %.2f  max %.2f" % [
		tag, ph.size(), _mean(ph), _pct(ph, 0.95), _pct(ph, 0.99), _pct(ph, 1.0)])
	print("  %s  nodes=%d  phys3d active=%d pairs=%d islands=%d  objects=%d  static mem=%.0f MB" % [
		tag, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ACTIVE_OBJECTS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_COLLISION_PAIRS)),
		int(Performance.get_monitor(Performance.PHYSICS_3D_ISLAND_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)),
		Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0])


# ─── tree walk ───────────────────────────────────────────────────────────────
func _processing_nodes_by_script() -> Dictionary:
	var out : Dictionary = {}
	var stack : Array = [_world]
	while not stack.is_empty():
		var n : Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if not (n.is_processing() or n.is_physics_processing()):
			continue
		var s := n.get_script() as Script
		if s == null:
			continue
		var label := String(s.get_global_name()) if s.has_method("get_global_name") else ""
		if label == "":
			label = s.resource_path.get_file().trim_suffix(".gd")
		if not out.has(label):
			out[label] = []
		(out[label] as Array).append(n)
	return out


# ─── scratch slot ────────────────────────────────────────────────────────────
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
	var stem := OS.get_environment("PERF_SLOT")
	if stem == "":
		stem = _newest_real_slot()
	if stem == "":
		return false
	print("scratch slot copied from real save '%s'" % stem)
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
