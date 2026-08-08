extends CanvasLayer
class_name PerfHud

## Lightweight performance overlay + auto-logger for diagnosing frame-rate.
##
## Shows (top-left) the numbers that actually tell us WHERE the time goes:
##   • FPS + frame time (ms)
##   • CPU: process (script) ms  vs  physics ms  → high = CPU/GDScript-bound
##   • Draw calls / primitives / objects drawn   → high = GPU / draw-call-bound
##   • VRAM, total nodes
## and prints a one-line [PERF] snapshot to the console every few seconds so you
## can diagnose from the log with zero on-screen interaction.
##
## Toggle the overlay with F3 (it stays logging either way). Default: ON.

const LOG_INTERVAL_S : float = 5.0
const AVG_WINDOW_S   : float = 1.0   # rolling window for the stable FPS/frame-ms read

var _label : Label
var _log_accum : float = 0.0
var _peak_draws : int = 0
var _min_fps : float = 9999.0
# Rolling 1-second average (D): accumulate frame times, recompute once per window.
var _win_time   : float = 0.0
var _win_frames : int = 0
var _avg_fps    : float = 0.0
var _avg_ms     : float = 0.0

func _ready() -> void:
	layer = 100
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_color", Color(0.55, 1.0, 0.55))
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_label.add_theme_constant_override("outline_size", 5)
	# Below the HUD crew roster panel (offset_bottom 300, HUD.gd:352). At y=96
	# the perf text sat ON the roster (operator screenshot 2026-08-07).
	_label.position = Vector2(10, 308)
	add_child(_label)
	set_process(true)
	print("[PERF] overlay ready — F3 toggles it; snapshot logged every %.0fs" % LOG_INTERVAL_S)

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo \
			and (event as InputEventKey).keycode == KEY_F3:
		_label.visible = not _label.visible

func _process(delta: float) -> void:
	var fps        : float = Performance.get_monitor(Performance.TIME_FPS)
	var frame_ms   : float = (1000.0 / fps) if fps > 0.0 else 0.0
	var proc_ms    : float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms    : float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws      : int   = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var prims      : int   = int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME))
	var objs       : int   = int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME))
	var vram_mb    : float = Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0
	var nodes      : int   = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))

	_peak_draws = maxi(_peak_draws, draws)
	_min_fps = minf(_min_fps, fps)

	# Rolling 1 s average (D) — instantaneous FPS jitters too much to judge fixes.
	_win_time += delta
	_win_frames += 1
	if _win_time >= AVG_WINDOW_S:
		_avg_fps = float(_win_frames) / _win_time
		_avg_ms = (_win_time / float(_win_frames)) * 1000.0
		_win_time = 0.0
		_win_frames = 0

	# Cheap heuristic for where the bottleneck is:
	#   CPU-bound  → process/physics ms is a big chunk of the frame budget.
	#   GPU-bound  → frame is slow but CPU ms is low (time spent on the GPU),
	#                usually paired with high draw calls / primitives.
	var cpu_ms := proc_ms + phys_ms
	var verdict := "OK"
	if fps < 50.0:
		if cpu_ms > frame_ms * 0.6:
			verdict = "CPU-BOUND (scripts/physics)"
		elif draws > 4000 or prims > 5_000_000:
			verdict = "GPU/DRAW-CALL-BOUND"
		else:
			verdict = "GPU-BOUND (fill/shader)"

	# Pull the layout-conversion summary off MainWorld (our parent) for on-screen
	# display (C) — so the rotation can be diagnosed without the console.
	var layout_line := ""
	var parent := get_parent()
	if parent != null:
		var s = parent.get("layout_conv_summary")
		if s != null and str(s) != "":
			layout_line = "\n" + str(s)

	_label.text = "FPS %d   avg %d  (%.1f ms avg)   min %d\nCPU  process %.1f ms | physics %.1f ms\nDraw calls %d  (peak %d)\nPrimitives %s\nObjects drawn %d\nVRAM %.0f MB   Nodes %d\n→ %s%s" % [
		int(fps), int(_avg_fps), _avg_ms, int(_min_fps),
		proc_ms, phys_ms,
		draws, _peak_draws,
		_commafy(prims),
		objs,
		vram_mb, nodes,
		verdict,
		layout_line,
	]

	_log_accum += delta
	if _log_accum >= LOG_INTERVAL_S:
		_log_accum = 0.0
		print("[PERF] fps=%d frame=%.1fms proc=%.1fms phys=%.1fms draws=%d prims=%d objs=%d vram=%.0fMB nodes=%d -> %s" % [
			int(fps), frame_ms, proc_ms, phys_ms, draws, prims, objs, vram_mb, nodes, verdict])

func _commafy(n: int) -> String:
	var s := str(n)
	var out := ""
	var c := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		c += 1
		if c % 3 == 0 and i > 0:
			out = "," + out
	return out
