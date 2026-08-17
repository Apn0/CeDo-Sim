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
const FRAME_MS_TAU_S : float = 0.5   # EMA constant for the frame time the VERDICT uses

var _label : Label
var _log_accum : float = 0.0
var _peak_draws : int = 0
var _min_fps : float = 9999.0
# Rolling 1-second average (D): accumulate frame times, recompute once per window.
var _win_time   : float = 0.0
var _win_frames : int = 0
var _avg_fps    : float = 0.0
var _avg_ms     : float = 0.0
# Smoothed TRUE frame time (ms) from the real delta — the denominator the
# bottleneck verdict divides by. See the verdict block in _process().
var _frame_ms_ema : float = 0.0

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

	# ── Bottleneck verdict ───────────────────────────────────────────────────
	# ARITHMETIC FIX 2026-08-17. Two defects, both proved with numbers:
	#
	# 1. WRONG DENOMINATOR. The old code divided the CPU time by
	#        frame_ms = 1000.0 / Performance.TIME_FPS
	#    TIME_FPS is an INTEGER the engine averages over ~1 s, so at low frame
	#    rates it disagrees badly with the frame time the HUD itself displays
	#    (_avg_ms, computed from the real delta).
	#    Operator screenshot: process 73.5 ms + physics 33.4 ms = 106.9 ms CPU
	#    inside a 133.3 ms frame -> the CPU is 80.2 % of the frame: CPU-BOUND.
	#    Old path: TIME_FPS read 4 -> frame_ms 250.0 -> 106.9/250.0 = 42.8 %,
	#    which is not > 60 %; draws < 4000 and prims < 5 M; so it fell through
	#    to the unconditional `else` and printed "GPU-BOUND (fill/shader)".
	#
	# 2. AN `else` THAT ASSERTED THE GPU WITH NO GPU EVIDENCE. Measured proof:
	#    a --headless run (draws = 0, prims = 0 — nothing is rendered at all)
	#    still logged "-> GPU-BOUND (fill/shader)".
	#
	# Now: the denominator is the measured frame time, the CPU is compared
	# against the REST of that same frame, and a GPU verdict requires the CPU
	# to actually be cheap AND some drawing to have happened.
	var dt_ms : float = delta * 1000.0
	if _frame_ms_ema <= 0.0:
		_frame_ms_ema = dt_ms
	else:
		var a : float = clampf(delta / FRAME_MS_TAU_S, 0.0, 1.0)
		_frame_ms_ema += (dt_ms - _frame_ms_ema) * a
	var frame_ms : float = _frame_ms_ema

	var cpu_ms    : float = proc_ms + phys_ms
	var cpu_share : float = (cpu_ms / frame_ms) if frame_ms > 0.0 else 0.0
	var cpu_pct   : float = cpu_share * 100.0
	var cap_ms    : float = (1000.0 / float(Engine.max_fps)) if Engine.max_fps > 0 else 0.0
	var draw_heavy : bool = draws > 4000 or prims > 5_000_000
	var verdict := "OK"
	if frame_ms > 20.0:                                   # slower than 50 FPS
		if cap_ms > 0.0 and frame_ms <= cap_ms * 1.1 and cpu_share < 0.35:
			verdict = "OK — frame limited by max_fps %d" % Engine.max_fps
		elif cpu_share >= 0.55:
			verdict = "CPU-BOUND (scripts/physics) — CPU %.0f%% of frame" % cpu_pct
		elif cpu_share >= 0.35:
			verdict = "MIXED — CPU %.0f%% / rest %.0f%%" % [cpu_pct, 100.0 - cpu_pct]
		elif draw_heavy:
			verdict = "GPU/DRAW-CALL-BOUND — CPU only %.0f%%" % cpu_pct
		elif draws > 0:
			verdict = "GPU-BOUND (fill/shader) — CPU only %.0f%%" % cpu_pct
		else:
			verdict = "UNEXPLAINED — CPU %.0f%%, 0 draws (vsync / stall?)" % cpu_pct

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
		# frame= is the MEASURED frame time (EMA of delta), not 1000/TIME_FPS —
		# it is the same number the verdict divides by, so log and verdict can
		# never disagree again.
		print("[PERF] fps=%d frame=%.1fms cpu=%.1fms(%.0f%%) proc=%.1fms phys=%.1fms draws=%d prims=%d objs=%d vram=%.0fMB nodes=%d -> %s" % [
			int(fps), frame_ms, cpu_ms, cpu_pct, proc_ms, phys_ms, draws, prims, objs, vram_mb, nodes, verdict])

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
