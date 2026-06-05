extends Node
## AudioManager — procedural real-time audio synthesis for the CeDo factory.
##
## No audio files are required. Every sound is synthesised from harmonic
## sine oscillators and narrow-band noise.  When real recordings arrive,
## swap the corresponding _fill_*() body; nothing else changes.
##
## Four "voices" (AudioStreamGeneratorPlayback objects):
##   ambient  — always-on Dutch 50 Hz power-line drone  (Ambient bus)
##   engine   — vehicle engine, throttle-driven pitch    (Machines bus)
##   machine  — extruder motor hum, state-driven        (Machines bus)
##   alarm    — vacuum-alarm two-tone / fault pulse      (Machines bus)
##
## Register as autoload "AudioManager" in Project Settings → AutoLoad.
## NOTE: no class_name — autoload singletons must not declare a class_name
## that matches their autoload identifier (Godot 4 parser error).

# ── Audio constants ────────────────────────────────────────────────────────────
const SAMPLE_RATE := 44100.0
const VOL_SILENT  := -80.0          # dB — effectively off

const BUS_MACHINES := &"Machines"
const BUS_AMBIENT  := &"Ambient"
const BUS_VOICES   := &"Voices"

# Fade / glide rates (per second)
const FADE_FAST   := 24.0           # dB/s  engine on, alarm on
const FADE_SLOW   := 8.0            # dB/s  engine off (gives a realistic run-down)
const PITCH_GLIDE := 80.0           # Hz/s  engine pitch transitions
const MACH_GLIDE  := 25.0           # Hz/s  machine pitch transitions

# ── Players ────────────────────────────────────────────────────────────────────
var _ambient_player  : AudioStreamPlayer
var _engine_player   : AudioStreamPlayer
var _machine_player  : AudioStreamPlayer
var _alarm_player    : AudioStreamPlayer
var _radio_player    : AudioStreamPlayer   # walkie-talkie comms (Voices bus)

# ── Generator playback handles (valid only after .play()) ─────────────────────
var _ambient_pb  : AudioStreamGeneratorPlayback
var _engine_pb   : AudioStreamGeneratorPlayback
var _machine_pb  : AudioStreamGeneratorPlayback
var _alarm_pb    : AudioStreamGeneratorPlayback
var _radio_pb    : AudioStreamGeneratorPlayback

# ── Radio (walkie-talkie) voice state ─────────────────────────────────────────
# A call is a short envelope: opening squelch crackle → garbled "voice" blips →
# closing squelch. We don't synthesise speech; the blip texture + squelch read
# unmistakably as two-way radio. _radio_t counts DOWN the active call in seconds.
var _radio_ph    := 0.0      # squelch-beep oscillator phase
var _radio_t     := 0.0      # seconds remaining in the current call (0 = idle)
var _radio_len   := 0.0      # total length of the current call
var _radio_gain  := 0.0      # 0..1 loudness handed in by the Walkie
var _radio_close := false    # headset route → tighter band, quieter

# ── #163 FORMANT VOICE SYNTH ──────────────────────────────────────────────────
# Instead of a flat harmonic buzz (which read as "annoying tone, no voice"), the
# call is synthesised as VOWEL FORMANTS driven by the actual message text: each
# syllable resonates a glottal source through two band-pass formant filters
# (F1/F2) that glide between vowels, with word-gap consonants and smooth
# envelopes. The ear reads the moving formants + word rhythm as muffled radio
# speech. Pure procedural — no audio assets.
const SQUELCH_IN  := 0.10    # opening "kerchunk" key-up, seconds
const SQUELCH_OUT := 0.10    # closing roger beep, seconds
const VOWEL_FORMANTS := {     # F1, F2 (Hz) per vowel — the shape that says "speech"
	"a": Vector2(730.0, 1090.0), "e": Vector2(530.0, 1840.0),
	"i": Vector2(270.0, 2290.0), "o": Vector2(570.0, 840.0),
	"u": Vector2(300.0, 870.0),  "y": Vector2(440.0, 1900.0),
}
var _radio_plan      : Array = []     # [{f1,f2,dur,voiced}] syllable plan from the text
var _radio_seg_idx   : int   = 0
var _radio_seg_start : float = 0.0
var _radio_seg_end   : float = 0.1
var _radio_src_ph    := 0.0           # glottal source phase
var _f1_cur          := 500.0         # gliding formant centres
var _f2_cur          := 1500.0
var _svf1_low := 0.0                  # state-variable bandpass states (F1)
var _svf1_band := 0.0
var _svf2_low := 0.0                  # (F2)
var _svf2_band := 0.0

# ── Phase accumulators  (0–1 = one complete oscillator cycle) ─────────────────
var _amb_ph  := 0.0
var _eng_ph  := 0.0
var _mach_ph := 0.0
var _alm_ph  := 0.0     # alarm tone oscillator phase
var _alm_gt  := 0.0     # alarm gate-LFO phase

# ── Engine voice state ─────────────────────────────────────────────────────────
var _engine_active := false
var _eng_vol_cur   := VOL_SILENT
var _eng_vol_tgt   := VOL_SILENT
var _eng_hz_cur    := 80.0
var _eng_hz_tgt    := 80.0

# ── Machine hum state ──────────────────────────────────────────────────────────
var _mach_vol_cur  := VOL_SILENT
var _mach_vol_tgt  := VOL_SILENT
var _mach_hz_cur   := 150.0
var _mach_hz_tgt   := 150.0

# ── Alarm state ────────────────────────────────────────────────────────────────
var _alarm_active   := false
var _alarm_is_fault := false
var _alarm_urgency  := 0.0          # 0 = just raised, 1 = cascade imminent
var _alm_vol_cur    := VOL_SILENT
var _alm_vol_tgt    := VOL_SILENT

# ── Cached OperatorContext (lazy, survives scene reloads) ─────────────────────
var _op_ctx_cache : OperatorContext = null

# =============================================================================
func _ready() -> void:
	_ambient_player  = _make_gen_player("AmbientVoice",  BUS_AMBIENT,  0.10)
	_engine_player   = _make_gen_player("EngineVoice",   BUS_MACHINES, 0.08)
	_machine_player  = _make_gen_player("MachineVoice",  BUS_MACHINES, 0.08)
	_alarm_player    = _make_gen_player("AlarmVoice",    BUS_MACHINES, 0.05)
	_radio_player    = _make_gen_player("RadioVoice",    BUS_VOICES,   0.06)

	# play() must be called before get_stream_playback()
	for p: AudioStreamPlayer in [_ambient_player, _engine_player,
								  _machine_player, _alarm_player, _radio_player]:
		p.play()

	_ambient_pb  = _ambient_player.get_stream_playback()  as AudioStreamGeneratorPlayback
	_engine_pb   = _engine_player.get_stream_playback()   as AudioStreamGeneratorPlayback
	_machine_pb  = _machine_player.get_stream_playback()  as AudioStreamGeneratorPlayback
	_alarm_pb    = _alarm_player.get_stream_playback()    as AudioStreamGeneratorPlayback
	_radio_pb    = _radio_player.get_stream_playback()    as AudioStreamGeneratorPlayback

	# Ambient is always audible; all others start completely silent.
	_ambient_player.volume_db = -18.0

	_connect_event_bus()


func _make_gen_player(node_name: String, bus: StringName, buf_s: float) -> AudioStreamPlayer:
	var gen           := AudioStreamGenerator.new()
	gen.mix_rate       = SAMPLE_RATE
	gen.buffer_length  = buf_s
	var player         := AudioStreamPlayer.new()
	player.name        = node_name
	player.stream      = gen
	player.bus         = bus
	player.volume_db   = VOL_SILENT
	add_child(player)
	return player


func _connect_event_bus() -> void:
	EventBus.operator_entered_vehicle.connect(_on_entered_vehicle)
	EventBus.operator_exited_vehicle.connect(_on_exited_vehicle)
	EventBus.machine_state_changed.connect(_on_machine_state_changed)
	EventBus.machine_alarm_raised.connect(_on_alarm_raised)
	EventBus.machine_alarm_cleared.connect(_on_alarm_cleared)
	EventBus.machine_vacuum_alarm_tick.connect(_on_vacuum_alarm_tick)


# =============================================================================
# PROCESS — smooth volume/pitch targets, then fill generator buffers
# =============================================================================
func _process(delta: float) -> void:
	_poll_vehicle_throttle()
	_smooth(delta)
	_fill_ambient()
	_fill_engine()
	_fill_machine()
	_fill_alarm()
	_fill_radio(delta)


func _smooth(delta: float) -> void:
	# Engine — slow fade-out when exiting, fast fade-in when entering
	var eng_fade := FADE_SLOW if not _engine_active else FADE_FAST
	_eng_vol_cur  = move_toward(_eng_vol_cur, _eng_vol_tgt, eng_fade    * delta)
	_eng_hz_cur   = move_toward(_eng_hz_cur,  _eng_hz_tgt,  PITCH_GLIDE * delta)
	_engine_player.volume_db = _eng_vol_cur

	# Machine hum
	_mach_vol_cur = move_toward(_mach_vol_cur, _mach_vol_tgt, FADE_FAST  * delta)
	_mach_hz_cur  = move_toward(_mach_hz_cur,  _mach_hz_tgt,  MACH_GLIDE * delta)
	_machine_player.volume_db = _mach_vol_cur

	# Alarm
	_alm_vol_cur  = move_toward(_alm_vol_cur, _alm_vol_tgt, FADE_FAST * delta)
	_alarm_player.volume_db = _alm_vol_cur


# =============================================================================
# SYNTHESIS — push frames into each generator buffer
#
# Phase accumulators: phase advances by (frequency × dt) per sample,
# wraps at 1.0.  sin(phase × TAU) produces one complete sine cycle per wrap.
# Harmonics: sin(phase × 2 × TAU) is the 2nd harmonic, etc.
# =============================================================================

func _fill_ambient() -> void:
	if not _ambient_pb: return
	var n := _ambient_pb.get_frames_available()
	if n == 0: return
	var dt := 1.0 / SAMPLE_RATE
	for _i in n:
		# Dutch 50 Hz mains hum + motor harmonics — the continuous factory drone
		var s  := sin(_amb_ph * TAU)        * 0.50
		s      += sin(_amb_ph * 2.0 * TAU)  * 0.22
		s      += sin(_amb_ph * 3.0 * TAU)  * 0.11
		s      += sin(_amb_ph * 6.0 * TAU)  * 0.05
		s      += sin(_amb_ph * 10.0 * TAU) * 0.02
		# Ventilation / air texture
		s      += (randf() * 2.0 - 1.0)     * 0.04
		s      *= 0.18
		_amb_ph = fmod(_amb_ph + 50.0 * dt, 1.0)
		_ambient_pb.push_frame(Vector2(s, s))


func _fill_engine() -> void:
	if not _engine_pb: return
	var n := _engine_pb.get_frames_available()
	if n == 0: return
	# Skip synthesis when inaudible — saves the oscillator loop
	if _eng_vol_cur < VOL_SILENT + 3.0:
		for _i in n:
			_engine_pb.push_frame(Vector2.ZERO)
		return
	var dt   := 1.0 / SAMPLE_RATE
	var freq := _eng_hz_cur
	for _i in n:
		# LPG engine: strong 2nd harmonic (4-cyl firing interval), mild 3rd / 4th
		var s  := sin(_eng_ph * TAU)        * 0.55
		s      += sin(_eng_ph * 2.0 * TAU)  * 0.30
		s      += sin(_eng_ph * 3.0 * TAU)  * 0.10
		s      += sin(_eng_ph * 4.0 * TAU)  * 0.04
		# tanh soft-saturation gives the LPG "burble" character
		s       = tanh(s * 1.5) * 0.70
		s      *= 0.28
		_eng_ph = fmod(_eng_ph + freq * dt, 1.0)
		_engine_pb.push_frame(Vector2(s, s))


func _fill_machine() -> void:
	if not _machine_pb: return
	var n := _machine_pb.get_frames_available()
	if n == 0: return
	if _mach_vol_cur < VOL_SILENT + 3.0:
		for _i in n:
			_machine_pb.push_frame(Vector2.ZERO)
		return
	var dt   := 1.0 / SAMPLE_RATE
	var freq := _mach_hz_cur
	for _i in n:
		# Electric drive motor powering the extrusion screw — steady industrial hum
		var s    := sin(_mach_ph * TAU)        * 0.60
		s        += sin(_mach_ph * 2.0 * TAU)  * 0.22
		s        += sin(_mach_ph * 3.0 * TAU)  * 0.10
		s        += sin(_mach_ph * 5.3 * TAU)  * 0.04   # inharmonic bearing tone
		s        += (randf() * 2.0 - 1.0)       * 0.02   # bearing-noise texture
		s        *= 0.25
		_mach_ph  = fmod(_mach_ph + freq * dt, 1.0)
		_machine_pb.push_frame(Vector2(s, s))


func _fill_alarm() -> void:
	if not _alarm_pb: return
	var n := _alarm_pb.get_frames_available()
	if n == 0: return
	if not _alarm_active or _alm_vol_cur < VOL_SILENT + 3.0:
		for _i in n:
			_alarm_pb.push_frame(Vector2.ZERO)
		return

	var dt := 1.0 / SAMPLE_RATE
	# Gate-LFO rate: vacuum alarm speeds up as cascade approaches;
	# fault alarm is a fixed rapid pulse.
	var gate_hz := 4.0 if _alarm_is_fault \
				 else lerpf(0.6, 3.0, _alarm_urgency)

	for _i in n:
		var gp := _alm_gt   # gate-LFO phase (0–1)
		var tone_hz := 0.0
		if _alarm_is_fault:
			# Fast 800 Hz pulse — 65 % on, 35 % silence
			tone_hz = 800.0 if gp < 0.65 else 0.0
		else:
			# Two-tone klaxon: 660 Hz → gap → 1320 Hz → gap
			if   gp < 0.44: tone_hz = 660.0
			elif gp < 0.50: tone_hz = 0.0
			elif gp < 0.94: tone_hz = 1320.0
			else:           tone_hz = 0.0

		var s := 0.0
		if tone_hz > 0.0:
			s  = sin(_alm_ph * TAU)        * 0.75
			s += sin(_alm_ph * 2.0 * TAU)  * 0.18   # 2nd harmonic → harsher tone
			s *= 0.55

		# Gate always advances; tone oscillator advances only while sounding
		# (avoids phase discontinuities at tone start)
		_alm_gt = fmod(_alm_gt + gate_hz * dt, 1.0)
		if tone_hz > 0.0:
			_alm_ph = fmod(_alm_ph + tone_hz * dt, 1.0)
		_alarm_pb.push_frame(Vector2(s, s))


# =============================================================================
# RADIO (walkie-talkie comms) — squelch-bracketed garbled-voice blips
# =============================================================================
## Trigger an INCOMING radio call carrying `text` (the spoken line). `loudness`
## 0..1 comes from the Walkie (volume × route cap, already 0 if the battery is
## dead). `headset` tightens the band + drops the level for the earpiece route.
func play_radio_call(text: String, loudness: float, headset: bool) -> void:
	_start_radio(text, clampf(loudness, 0.0, 1.0), headset)

## Player push-to-talk uplink — the operator hears their own keyed-up line as a
## short radio blip (sidetone). Same formant pipeline, fixed local loudness.
func play_radio_uplink(text: String, headset: bool) -> void:
	_start_radio(text, 0.7, headset)

## Begin a radio transmission: build the syllable plan from the text and arm the
## voice synth. Length scales with the message, so "Copy that" is a short blip
## and "Tank swap, give me five" runs longer — the rhythm tracks the words.
func _start_radio(text: String, gain: float, headset: bool) -> void:
	if gain <= 0.001:
		return
	_radio_gain  = gain
	_radio_close = headset
	_radio_plan  = _build_voice_plan(text)
	_radio_len   = SQUELCH_IN + _plan_duration(_radio_plan) + SQUELCH_OUT
	_radio_t     = _radio_len
	_radio_seg_idx   = 0
	_radio_seg_start = 0.0
	_radio_seg_end   = float(_radio_plan[0]["dur"]) if not _radio_plan.is_empty() else 0.1
	_svf1_low = 0.0; _svf1_band = 0.0
	_svf2_low = 0.0; _svf2_band = 0.0
	_f1_cur = 500.0; _f2_cur = 1500.0
	# Wake the player (created at VOL_SILENT); sample-level gain handled below.
	_radio_player.volume_db = 0.0

## Turn a message into a list of voiced syllables (each a vowel with its
## formants) separated by short word-gap consonants. Vowels are read from the
## ACTUAL letters so the formant motion loosely tracks the real word shapes.
func _build_voice_plan(text: String) -> Array:
	var plan : Array = []
	var words := text.to_lower().split(" ", false)
	for wi in words.size():
		var w : String = words[wi]
		var syl_vowels : Array = []
		var prev_v := false
		for ci in w.length():
			var ch := w[ci]
			var is_v : bool = "aeiouy".find(ch) != -1
			if is_v and not prev_v:
				syl_vowels.append(ch)
			prev_v = is_v
		if syl_vowels.is_empty():
			syl_vowels = ["e"]                       # every word is at least one syllable
		for v in syl_vowels:
			var f : Vector2 = VOWEL_FORMANTS.get(v, Vector2(500.0, 1500.0))
			plan.append({"f1": f.x, "f2": f.y, "dur": 0.15, "voiced": true})
		if wi < words.size() - 1:
			plan.append({"f1": 500.0, "f2": 1500.0, "dur": 0.07, "voiced": false})  # word gap
	return plan

func _plan_duration(plan: Array) -> float:
	var d := 0.0
	for seg in plan:
		d += float(seg["dur"])
	return d

func _fill_radio(_delta: float) -> void:
	if not _radio_pb:
		return
	var n := _radio_pb.get_frames_available()
	if n == 0:
		return
	if _radio_t <= 0.0:
		if _radio_player and _radio_player.volume_db > VOL_SILENT + 1.0:
			_radio_player.volume_db = VOL_SILENT
		for _i in n:
			_radio_pb.push_frame(Vector2.ZERO)
		return
	var dt := 1.0 / SAMPLE_RATE
	var fund : float = 135.0 if _radio_close else 115.0
	for _i in n:
		var elapsed : float = _radio_len - _radio_t
		var s := 0.0
		if elapsed < SQUELCH_IN:
			# Opening "kerchunk" — a rising key-up tone with a smooth bump envelope.
			var e := elapsed / SQUELCH_IN
			var bf : float = lerpf(1150.0, 1500.0, e)
			_radio_ph = fmod(_radio_ph + bf * dt, 1.0)
			s = sin(_radio_ph * TAU) * sin(e * PI) * 0.40
		elif elapsed > _radio_len - SQUELCH_OUT:
			# Closing roger beep — a short descending tone.
			var e2 := (elapsed - (_radio_len - SQUELCH_OUT)) / SQUELCH_OUT
			var bf2 : float = lerpf(1400.0, 950.0, e2)
			_radio_ph = fmod(_radio_ph + bf2 * dt, 1.0)
			s = sin(_radio_ph * TAU) * sin((1.0 - e2) * PI * 0.5) * 0.35
		else:
			# ── VOICE: glottal source → two gliding formant band-passes ──────────
			var voice_t := elapsed - SQUELCH_IN
			while _radio_seg_idx < _radio_plan.size() - 1 and voice_t >= _radio_seg_end:
				_radio_seg_idx += 1
				_radio_seg_start = _radio_seg_end
				_radio_seg_end += float(_radio_plan[_radio_seg_idx]["dur"])
			var seg : Dictionary = _radio_plan[_radio_seg_idx] if _radio_seg_idx < _radio_plan.size() \
				else {"f1": 500.0, "f2": 1500.0, "dur": 0.1, "voiced": false}
			# Glide the formant centres toward the syllable's vowel → speech-like motion.
			_f1_cur = move_toward(_f1_cur, float(seg["f1"]), 9000.0 * dt)
			_f2_cur = move_toward(_f2_cur, float(seg["f2"]), 14000.0 * dt)
			# Raised-cosine envelope within the syllable (smooth — no clicky gates).
			var seg_pos : float = (voice_t - _radio_seg_start) / maxf(float(seg["dur"]), 0.001)
			var seg_env := sin(clampf(seg_pos, 0.0, 1.0) * PI)
			var voiced_amp : float = 1.0 if bool(seg["voiced"]) else 0.12
			# Glottal source: a soft sawtooth (rich in harmonics for the formants to shape).
			_radio_src_ph = fmod(_radio_src_ph + fund * dt, 1.0)
			var src := 0.0
			for k in range(1, 5):
				src += sin(_radio_src_ph * float(k) * TAU) / float(k)
			src *= 0.5
			# State-variable band-pass at F1 then F2 (Chamberlin form).
			var f1c : float = 2.0 * sin(PI * clampf(_f1_cur, 80.0, 4000.0) / SAMPLE_RATE)
			_svf1_low += f1c * _svf1_band
			_svf1_band += f1c * (src - _svf1_low - 0.13 * _svf1_band)
			var f2c : float = 2.0 * sin(PI * clampf(_f2_cur, 80.0, 4000.0) / SAMPLE_RATE)
			_svf2_low += f2c * _svf2_band
			_svf2_band += f2c * (src - _svf2_low - 0.17 * _svf2_band)
			var v := _svf1_band * 0.6 + _svf2_band * 0.5 + src * 0.04
			v *= seg_env * voiced_amp
			if not bool(seg["voiced"]):
				v += (randf() * 2.0 - 1.0) * 0.10 * seg_env   # consonant noise burst
			v += (randf() * 2.0 - 1.0) * 0.04                 # radio compression hiss
			s = v
		# Radio band character: soft-clip compression + route level + master gain.
		s = tanh(s * 1.6) * 0.7
		var route := 0.6 if _radio_close else 1.0
		s *= _radio_gain * route * 0.5
		_radio_pb.push_frame(Vector2(s, s))
		_radio_t = maxf(0.0, _radio_t - dt)

# =============================================================================
# VEHICLE THROTTLE POLL (called every _process frame)
# =============================================================================
func _poll_vehicle_throttle() -> void:
	if not _engine_active:
		return
	var op := _get_op_ctx()
	if op == null or op.current_vehicle == null:
		return

	var vehicle  := op.current_vehicle
	var throttle := 0.0
	var t: Variant = vehicle.get("engine_throttle")   # Variant — explicit type avoids warning
	if t != null:
		throttle = clampf(float(t), 0.0, 1.0)
	else:
		# Fallback: derive from speed (no engine_throttle property)
		throttle = clampf(vehicle.linear_velocity.length() / 8.0, 0.0, 1.0)

	# Engine pitch: 80 Hz idle → 180 Hz at full throttle
	_eng_hz_tgt  = lerpf(80.0, 180.0, throttle)
	# Engine volume: -18 dB idle → -8 dB under load
	_eng_vol_tgt = lerpf(-18.0, -8.0, throttle)


func _get_op_ctx() -> OperatorContext:
	if _op_ctx_cache != null and is_instance_valid(_op_ctx_cache):
		return _op_ctx_cache
	# Found via group — get_tree().root.get_child(0) would be an autoload (us, even),
	# never MainWorld, so OperatorContext must be located by group membership.
	_op_ctx_cache = get_tree().get_first_node_in_group("operator_context") as OperatorContext
	return _op_ctx_cache


# =============================================================================
# EVENT BUS HANDLERS
# =============================================================================
func _on_entered_vehicle(_vehicle: Node) -> void:
	_engine_active = true
	_eng_vol_tgt   = -18.0   # starts at idle; throttle poll raises it
	_eng_hz_tgt    = 80.0


func _on_exited_vehicle(_vehicle: Node) -> void:
	_engine_active = false
	_eng_vol_tgt   = VOL_SILENT   # FADE_SLOW gives realistic engine run-down


func _on_machine_state_changed(_id: String, _old: int, new_s: int) -> void:
	# ExtruderModel.State ints: 0=OFF 1=IDLE 2=RUNNING 3=VACUUM_ALARM 4=FAULT 5=E_STOP
	match new_s:
		0:   # OFF
			_mach_vol_tgt = VOL_SILENT
			_mach_hz_tgt  = 150.0
		1:   # IDLE — screw turning slowly, no feed material
			_mach_vol_tgt = -22.0
			_mach_hz_tgt  = 150.0
		2:   # RUNNING — full production throughput
			_mach_vol_tgt = -14.0
			_mach_hz_tgt  = 200.0
		3:   # VACUUM_ALARM — motor still running, alarm added separately
			_mach_vol_tgt = -14.0
			_mach_hz_tgt  = 200.0
		4:   # FAULT — melt runaway, motor over-drives
			_mach_vol_tgt = -10.0
			_mach_hz_tgt  = 225.0
		5:   # EMERGENCY_STOP
			_mach_vol_tgt = VOL_SILENT
	# If machine left alarm territory, silence the alarm automatically
	if new_s != 3 and new_s != 4:
		_alarm_active   = false
		_alarm_urgency  = 0.0
		_alm_vol_tgt    = VOL_SILENT


func _on_alarm_raised(_id: String, alarm_id: String, _sev: int) -> void:
	_alarm_active   = true
	_alarm_is_fault = (alarm_id == "fault")
	# Fault alarm starts at max urgency; vacuum alarm escalates via tick
	_alarm_urgency  = 1.0 if _alarm_is_fault else 0.0
	_alm_vol_tgt    = -6.0 if _alarm_is_fault else -10.0


func _on_alarm_cleared(_id: String, _alarm_id: String) -> void:
	_alarm_active   = false
	_alarm_urgency  = 0.0
	_alm_vol_tgt    = VOL_SILENT


func _on_vacuum_alarm_tick(_id: String, remaining_s: float) -> void:
	# urgency 0.0 = just raised (120 s left), 1.0 = cascade imminent (0 s left)
	_alarm_urgency = 1.0 - clampf(remaining_s / 120.0, 0.0, 1.0)
