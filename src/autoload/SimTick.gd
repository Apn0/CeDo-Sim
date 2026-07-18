extends Node

## Discrete-event process simulation driver. Register as autoload "SimTick".
##
## Process realism (extruders, washers, vacuum cascades) is fundamentally
## tick-based, not continuous. Mixing it into Godot's _physics_process
## couples it to render rate and to physics simulation — both wrong for our
## purposes. SimTick runs at a fixed rate (10 Hz default) independent of
## either, using an accumulator pattern so it stays deterministic across
## frame-rate variation.
##
## Usage:
##   func _ready():
##       SimTick.sim_tick.connect(_on_sim_tick)
##   func _on_sim_tick(delta: float):
##       # Always called with delta = SimTick.TICK_DT, regardless of FPS.
##       _machine.tick(delta, _gather_inputs())

const TICK_HZ: float = 10.0
const TICK_DT: float = 1.0 / TICK_HZ

signal sim_tick(delta: float)

var _accumulator: float = 0.0
var _paused     : bool  = false
var _tick_count : int   = 0

# ── #221 perf instrumentation ────────────────────────────────────────────────
# Wall-clock cost (µs) of the most recent sim_tick.emit() call, plus a rolling
# EMA so HotspotProfiler can read an averaged figure. Touched by _process only
# when probing is enabled (HotspotProfiler.profile_sim_tick) — zero overhead
# when off, since the timer reads are cheap but the conditional is cheaper.
var last_emit_us : int   = 0
var avg_emit_us  : float = 0.0
var probe_sim_tick : bool = false   # toggled by HotspotProfiler

func _ready() -> void:
	# Process even when the scene tree is paused — we want the option to keep
	# simulating during menu screens for systems that need it. ShiftClock is
	# pausable separately via its own pause_shift() API.
	process_mode = Node.PROCESS_MODE_ALWAYS

func _process(delta: float) -> void:
	if _paused:
		return
	_accumulator += delta
	# Cap the catch-up to avoid death spirals if the game stalls.
	if _accumulator > 1.0:
		_accumulator = 1.0
	while _accumulator >= TICK_DT:
		if probe_sim_tick:
			var t0 : int = Time.get_ticks_usec()
			sim_tick.emit(TICK_DT)
			last_emit_us = Time.get_ticks_usec() - t0
			# First-order EMA, α = 0.1 (≈ last ~10 emits dominate)
			avg_emit_us = avg_emit_us * 0.9 + float(last_emit_us) * 0.1
		else:
			sim_tick.emit(TICK_DT)
		_accumulator -= TICK_DT
		_tick_count += 1

# Number of currently connected subscribers to sim_tick — useful for the
# profiler readout (a tally that creeps up is itself a hotspot signal).
func subscriber_count() -> int:
	return sim_tick.get_connections().size()

# ── Control ───────────────────────────────────────────────────────────────────
func pause() -> void:
	_paused = true

func resume() -> void:
	_paused = false

func is_paused() -> bool:
	return _paused

func get_tick_count() -> int:
	return _tick_count
