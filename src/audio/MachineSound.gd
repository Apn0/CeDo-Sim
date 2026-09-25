extends Node3D
class_name MachineSound
## The sound of ONE placed machine, tool or panel. Built by
## `MachineSoundBank.attach()` from a `MachineSoundSpec` (.tres) and driven by
## whoever owns the machine's state:
##
##   LineFlow._tick_plc_power_downstream  → set_drive(spin × rotor fraction), 10 Hz
##   LeafBlower._physics_process          → set_drive(_spool)
##   HoseReel / WasteContainer (IBC)      → play_event("valve_open" / "valve_close")
##   Hmi (the physical panel)             → set_alarm(unacknowledged faults > 0)
##
## What it enforces (operator 2026-09-25):
##   * not operating → NO sound. The loop players are STOPPED, not merely quiet,
##     once the drive has ramped to 0.
##   * constant operation → the baked loop. `tools/audio/machine_clips.py` cut
##     it at a correlated seam with an equal-power crossfade; nothing here
##     re-cuts it, and the loop starts at a random offset so two machines of one
##     type never phase-lock.
##   * ramp-up / ramp-down sound different from operation → GENERATED from the
##     run loop: pitch follows the drive from spec.pitch_floor to 1.0 and level
##     from spec.ramp_db_floor to 0 dB, over the machine's own spin-up
##     (LineFlow.SPIN_UP_S) or the spec's ramp_up_s / ramp_down_s when longer.
##     A start_clip / stop_clip (leaf blower) plays on top at the transitions.
##   * per-machine level → spec.gain_db, the inspector slider.
##
## Driver watchdog: if nobody calls set_drive() for DRIVER_TIMEOUT_S the target
## drops to 0, so a machine that leaves the flow graph (line disconnected,
## LineFlow freed) winds down instead of humming forever.
##
## Headless-safe: AudioStreamPlayer3D works on the dummy driver, so
## `test_machine_sounds` asserts on `playing`, pitch and volume.

const SILENT_DB        : float = -80.0
const DRIVER_TIMEOUT_S : float = 1.0
const FOLLOW_TAU_S     : float = 0.12   # frame-rate smoothing of the 10 Hz drive steps
const SNAP_EPS         : float = 0.004

var spec : Resource = null                 # MachineSoundSpec

var _run   : AudioStreamPlayer3D = null    # the operation loop
var _idle  : AudioStreamPlayer3D = null    # optional low-speed loop
var _fx    : AudioStreamPlayer3D = null    # start / stop one-shots
var _ev    : AudioStreamPlayer3D = null    # named events (valves, flushes)
var _alarm : AudioStreamPlayer3D = null    # repeated beep

var _target        : float = 0.0
var _drive         : float = 0.0
var _running       : bool  = false
var _since_drive_s : float = 0.0
var _periodic_t    : float = 0.0
var _periodic_next : float = 0.0
var _alarm_on      : bool  = false
var _alarm_t       : float = 0.0
var _events_played : Dictionary = {}       # event name -> count
var _missing_warned: Dictionary = {}
var _rng           : RandomNumberGenerator = RandomNumberGenerator.new()


func setup(s: Resource) -> void:
	spec = s
	_rng.randomize()
	_run   = _make_player("Run",   String(spec.get("run_loop")),   true)
	_idle  = _make_player("Idle",  String(spec.get("idle_loop")),  true)
	_alarm = _make_player("Alarm", String(spec.get("alarm_clip")), false)
	_fx    = _make_player("Fx",    "", false, true)
	_ev    = _make_player("Event", "", false, true)
	_fx.max_polyphony = 2
	_ev.max_polyphony = 4
	_periodic_next = _period()
	set_process(true)


# ── public API ────────────────────────────────────────────────────────────────
## 0..1 fraction of nominal speed the machine is at RIGHT NOW (the caller's
## ramp). Call it every tick while the machine exists; silence follows within
## DRIVER_TIMEOUT_S when the calls stop.
func set_drive(level: float) -> void:
	_target = clampf(level, 0.0, 1.0)
	_since_drive_s = 0.0


## Play a named one-shot from spec.event_clips. False if the spec has no such
## event or its WAV is missing.
func play_event(event: String) -> bool:
	var clips : Dictionary = spec.get("event_clips") if spec != null else {}
	var path := String(clips.get(event, ""))
	var st := _load_clip(path, false)
	if st == null:
		return false
	_ev.stream = st
	_ev.volume_db = float(spec.get("gain_db"))
	_ev.pitch_scale = 1.0
	_ev.play()
	_events_played[event] = int(_events_played.get(event, 0)) + 1
	return true


## Repeat the alarm beep every spec.alarm_period_s while true.
func set_alarm(on: bool) -> void:
	if on == _alarm_on:
		return
	_alarm_on = on
	_alarm_t = 0.0   # first beep on the next frame; a running beep finishes


func drive() -> float:            return _drive
func target() -> float:           return _target
func is_running() -> bool:        return _running
func alarm_active() -> bool:      return _alarm_on
func run_player() -> AudioStreamPlayer3D:   return _run
func idle_player() -> AudioStreamPlayer3D:  return _idle
func fx_player() -> AudioStreamPlayer3D:    return _fx
func event_player() -> AudioStreamPlayer3D: return _ev
func alarm_player() -> AudioStreamPlayer3D: return _alarm
func events_played() -> Dictionary:         return _events_played.duplicate()
func has_run_loop() -> bool:      return _run != null and _run.stream != null


# ── per frame ─────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if spec == null:
		return
	_since_drive_s += delta
	if _since_drive_s > DRIVER_TIMEOUT_S and _target > 0.0:
		_target = 0.0
	_slew(delta)
	var should_run : bool = _target > SNAP_EPS or _drive > SNAP_EPS
	if should_run and not _running:
		_start()
	elif not should_run and _running:
		_stop()
	if _running:
		_apply_levels()
	_tick_periodic(delta)
	_tick_alarm(delta)


func _slew(delta: float) -> void:
	if _target > _drive:
		var up_s : float = float(spec.get("ramp_up_s"))
		if up_s > 0.0:
			_drive = minf(_target, _drive + delta / up_s)
		else:
			_drive = lerpf(_drive, _target, 1.0 - exp(-delta / FOLLOW_TAU_S))
		if _target - _drive < SNAP_EPS:
			_drive = _target
	elif _target < _drive:
		var dn_s : float = float(spec.get("ramp_down_s"))
		if dn_s > 0.0:
			_drive = maxf(_target, _drive - delta / dn_s)
		else:
			_drive = lerpf(_drive, _target, 1.0 - exp(-delta / FOLLOW_TAU_S))
		if _drive - _target < SNAP_EPS:
			_drive = _target


func _start() -> void:
	_running = true
	_periodic_t = 0.0
	_play_oneshot(String(spec.get("start_clip")))
	for p in [_run, _idle]:
		if p != null and p.stream != null:
			p.play(_rng.randf() * _stream_length(p.stream))
	_apply_levels()


func _stop() -> void:
	_running = false
	for p in [_run, _idle]:
		if p != null:
			p.stop()
	_play_oneshot(String(spec.get("stop_clip")))


## Pitch + level of the loop(s) from the live drive. Equal-power idle↔run
## crossfade when an idle loop exists (leaf blower), else the single-loop ramp.
func _apply_levels() -> void:
	var g : float = float(spec.get("gain_db"))
	var d : float = clampf(_drive, 0.0, 1.0)
	if _idle == null:
		if _run != null:
			_run.pitch_scale = lerpf(float(spec.get("pitch_floor")), 1.0, d)
			_run.volume_db = g + lerpf(float(spec.get("ramp_db_floor")), 0.0, smoothstep(0.0, 1.0, d))
		return
	var a : float = float(spec.get("idle_to_run_at"))
	var k : float = clampf((d - a) / maxf(1.0 - a, 0.001), 0.0, 1.0)
	var w_run  : float = sin(k * PI * 0.5)
	var w_idle : float = cos(k * PI * 0.5)
	_idle.pitch_scale = lerpf(1.0, float(spec.get("idle_pitch_top")), d)
	_idle.volume_db = g + linear_to_db(maxf(w_idle, 0.001))
	if _run != null:
		_run.pitch_scale = lerpf(float(spec.get("pitch_floor")), 1.0, k)
		_run.volume_db = g + linear_to_db(maxf(w_run, 0.001))


func _tick_periodic(delta: float) -> void:
	var ev := String(spec.get("periodic_event"))
	if ev == "" or float(spec.get("periodic_event_s")) <= 0.0:
		return
	if not _running or _drive < 0.5:
		_periodic_t = 0.0
		return
	_periodic_t += delta
	if _periodic_t >= _periodic_next:
		_periodic_t = 0.0
		_periodic_next = _period()
		play_event(ev)


func _tick_alarm(delta: float) -> void:
	if not _alarm_on or _alarm == null or _alarm.stream == null:
		return
	_alarm_t -= delta
	if _alarm_t <= 0.0:
		_alarm.volume_db = float(spec.get("gain_db"))
		_alarm.play()
		_alarm_t = maxf(float(spec.get("alarm_period_s")), 0.2)


# ── helpers ───────────────────────────────────────────────────────────────────
func _period() -> float:
	var p : float = float(spec.get("periodic_event_s"))
	var j : float = float(spec.get("periodic_jitter"))
	return p * (1.0 + j * (_rng.randf() * 2.0 - 1.0))


func _play_oneshot(path: String) -> void:
	var st := _load_clip(path, false)
	if st == null:
		return
	_fx.stream = st
	_fx.volume_db = float(spec.get("gain_db"))
	_fx.play()


func _make_player(n: String, path: String, looping: bool, always: bool = false) -> AudioStreamPlayer3D:
	if path == "" and not always:
		return null
	var p := AudioStreamPlayer3D.new()
	p.name = n
	var bus := String(spec.get("bus"))
	p.bus = bus if AudioServer.get_bus_index(bus) >= 0 else "Master"
	p.unit_size = float(spec.get("unit_size_m"))
	p.max_distance = float(spec.get("max_distance_m"))
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	p.volume_db = SILENT_DB if looping else float(spec.get("gain_db"))
	if path != "":
		p.stream = _load_clip(path, looping)
	add_child(p)
	return p


## Load a clip by res:// path. `assets/` is gitignored, so a missing WAV warns
## once and yields null — a silent machine, never a crash. A looping clip is
## forced to LOOP_FORWARD over its full length when the importer did not read a
## loop from the WAV's smpl chunk.
func _load_clip(path: String, looping: bool) -> AudioStream:
	if path == "":
		return null
	if not ResourceLoader.exists(path):
		if not _missing_warned.has(path):
			_missing_warned[path] = true
			push_warning("[MachineSound] %s: clip %s not found — run tools/audio/machine_clips.py (assets/ is gitignored)"
				% [name, path])
		return null
	var st := load(path) as AudioStream
	if st == null:
		return null
	if looping and st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		if w.loop_mode != AudioStreamWAV.LOOP_FORWARD:
			w.loop_mode = AudioStreamWAV.LOOP_FORWARD
			w.loop_begin = 0
			w.loop_end = _frames_of(w)
	return st


static func _frames_of(w: AudioStreamWAV) -> int:
	if w.format != AudioStreamWAV.FORMAT_16_BITS:
		return 0
	var bpf : int = 4 if w.stereo else 2
	@warning_ignore("integer_division")
	return w.data.size() / bpf


static func _stream_length(st: AudioStream) -> float:
	if st is AudioStreamWAV:
		var w := st as AudioStreamWAV
		var n := _frames_of(w)
		if n > 0 and w.mix_rate > 0:
			return float(n) / float(w.mix_rate)
	return maxf(st.get_length(), 0.0)
