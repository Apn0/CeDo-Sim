extends Node

## The player's two-way radio (portagofoon).
##
## Holds ONE battery, which drains only while the shift clock is running. When the
## battery goes flat the player stops hearing crew comms — the whole point of the
## charger gameplay (swap a fresh pack in at the shift-leader office, leave your
## empty to charge for whoever comes next).
##
## Audio routing models the real unit:
##   - HEADSET attached (earpiece on a cable to the right ear): comms play QUIET
##     and private — a small, close sound only the operator hears.
##   - SPEAKER (no headset): comms play LOUD out of the unit's speaker.
## A VOLUME knob (0..1) scales either route, so you can dial it so you neither get
## blasted nor miss a call.
##
## Register as autoload "Walkie". No class_name (autoload-name collision rule).
##
## This node owns only STATE + routing decisions; the actual radio blips are
## synthesised by AudioManager.play_radio_call() on the Voices bus. Keeping the
## two apart means the model is fully testable headless (no audio server needed).

## Battery is a global class (class_name Battery), but under the headless
## `--script` harness the global class registry isn't built, so we preload the
## type explicitly. In-game this resolves to the same class.
const BatteryT := preload("res://src/sim/Battery.gd")

signal battery_changed(percent: int)        # emitted when charge % (rounded) changes
signal battery_went_flat                      # emitted once when the pack dies
signal battery_swapped(old_charge: float)     # player swapped the pack at the station
signal headset_changed(attached: bool)
signal volume_changed(level: float)
signal call_received(from_name: String, text: String, heard: bool)
## Player keyed up — their own TX. `text` is the canned line that went out so
## the HUD can echo it back ("you: 'On my way'"). NPCs are not yet listeners;
## this currently exists for the audio chirp + HUD self-echo, with the canned
## message loop ready for the crew AI to subscribe to.
signal transmit_sent(text: String, heard: bool)
signal mic_ptt_changed(active: bool)
signal mic_level_changed(level: float)
signal task_broadcasted(task_type: String, target_node: Node, from_name: String)

# ── State ─────────────────────────────────────────────────────────────────────
var battery        : BatteryT = null
var headset_on     : bool    = true     # earpiece attached by default
var volume         : float   = 0.6      # 0..1 knob position
const VOLUME_STEP  : float   = 0.1
var is_transmitting_mic : bool = false
var mic_enabled         : bool = true

var _shift_clock   : Node = null
var _last_percent  : int  = -1

# =============================================================================
func _ready() -> void:
	# Start with a fresh pack in the unit.
	battery = BatteryT.new(1.0, "pack_player_start")
	_last_percent = battery.percent()
	# Subscribe to VoiceService TTS results so when a real-voice stream lands we
	# route it through AudioManager at the current effective loudness.
	#
	# INLINE, and deliberately so. FULL_LOGIC_AUDIT_2026-07-08 HIGH #12 records
	# this line as a live defect — "VoiceService is autoload #12 (after Walkie
	# #6) -> node doesn't exist yet -> never retried. All real TTS crew voice is
	# dead every launch" — and prescribes call_deferred. That finding is
	# REFUTED, measured on 4.6.3 on 2026-08-23 by probing from inside this
	# function on a real boot:
	#
	#     [PROBE] Walkie._ready: /root/VoiceService present = true
	#
	# Godot adds every autoload to /root BEFORE readying them, so declaration
	# order does not starve this lookup, and the deferred version was tried and
	# changed nothing (test_project_sweep_guards C2 is green either way — the
	# mutation is in its header). It is written back inline so the next reader of
	# the audit does not "fix" a working line on the strength of a stale doc.
	# The audit is a 2026-07-08 SNAPSHOT: re-measure every finding before acting.
	_connect_voice_service()

## Hook up VoiceService's voice_done signal. Split out of _ready() so the hookup
## has a name a test can call, and written idempotently so calling it twice
## cannot stack two listeners and double every synthesised line. Best-effort —
## silently skipped in stripped builds where the autoload is genuinely absent.
func _connect_voice_service() -> void:
	var vs := get_node_or_null("/root/VoiceService")
	if vs == null or not vs.has_signal("voice_done"):
		return
	if not vs.is_connected("voice_done", Callable(self, "_on_voice_done")):
		vs.connect("voice_done", Callable(self, "_on_voice_done"))

## Resolve the ShiftClock lazily — it lives under MainWorld, which doesn't exist
## yet when this autoload's _ready() runs.
func _shift() -> Node:
	if _shift_clock == null or not is_instance_valid(_shift_clock):
		var scene := get_tree().current_scene
		if scene != null:
			_shift_clock = scene.find_child("ShiftClock", true, false)
	return _shift_clock

func _process(delta: float) -> void:
	# Drain only while the shift is actually running.
	var sc := _shift()
	var running := sc != null and bool(sc.get("shift_active"))
	if running and battery != null and not battery.is_flat():
		if battery.drain(delta):
			emit_signal("battery_went_flat")
		var p := battery.percent()
		if p != _last_percent:
			_last_percent = p
			emit_signal("battery_changed", p)

# =============================================================================
# BATTERY ACCESS (used by the HUD + BatteryStation)
# =============================================================================
func battery_percent() -> int:
	return battery.percent() if battery != null else 0

func battery_alive() -> bool:
	return battery != null and not battery.is_flat()

## Swap the pack currently in the walkie for `new_pack`, returning the one removed
## (which the player then carries / shelves / drops in the charger). Either may be
## null (e.g. taking the pack out to hold it).
func swap_battery(new_pack: BatteryT) -> BatteryT:
	var old := battery
	battery = new_pack
	_last_percent = battery.percent() if battery != null else -1
	emit_signal("battery_swapped", old.charge if old != null else 0.0)
	emit_signal("battery_changed", battery_percent())
	return old

# =============================================================================
# HEADSET + VOLUME (player controls)
# =============================================================================
func toggle_headset() -> void:
	headset_on = not headset_on
	emit_signal("headset_changed", headset_on)

func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	emit_signal("volume_changed", volume)

func volume_up() -> void:
	set_volume(volume + VOLUME_STEP)

func volume_down() -> void:
	set_volume(volume - VOLUME_STEP)

## The effective loudness (0..1) a call will play at, given the current routing.
## Headset is intimate/quiet (caps lower) but always audible; speaker is louder.
## Returns 0 when the battery is dead — nothing comes through.
func effective_loudness() -> float:
	if not battery_alive():
		return 0.0
	var route_cap := 0.55 if headset_on else 1.0
	return volume * route_cap

# =============================================================================
# INCOMING CALLS (driven by crew events — e.g. someone goes on break)
# =============================================================================
## A colleague keys up. If the battery is alive the call is HEARD (routed to
## AudioManager at the effective loudness); if dead, it's missed. Either way we
## emit call_received so the HUD can log it (and show "missed" when not heard).
##
## If VoiceService is available and the active backend supports speech synthesis
## (local piper / cloud TTS), we ask it to produce a real-voice stream for
## `text` IN PARALLEL with arming the squelch carrier. The carrier still plays
## (sidetone is part of the radio feel), and the synthesised voice plays on the
## Voices bus when it's ready. When VoiceService returns null (no backend tools
## installed) the squelch carrier alone carries the message — exactly the
## behaviour pre-VoiceService.
func receive_call(from_name: String, text: String) -> void:
	var loud := effective_loudness()
	var heard := battery_alive()
	if heard:
		var am := get_node_or_null("/root/AudioManager")
		if am != null and am.has_method("play_radio_call"):
			am.play_radio_call(text, loud, headset_on)   # text drives the formant voice (#163)
		_request_voice(text, _voice_id_for(from_name))
	emit_signal("call_received", from_name, text, heard)

# =============================================================================
# OUTGOING PTT — operator keys up to talk back to the crew
# =============================================================================
## Canned response lines. Real walkies don't type — the simulator picks from a
## short repertoire. The operator opens the radio menu (U) and chooses one by
## number (1..9) or arrow keys + Enter. The HUD owns the menu widget; this
## autoload only knows the list and the send/audio routing.
const PTT_LINES : Array[String] = [
	"Copy that.",
	"On my way.",
	"Need a hand here.",
	"Tank swap, give me five.",
	"Standby.",
	# ── Common shift radio phrases ───────────────────────────────────────────
	# Real CeDo shift comms: start/stop a shift, break in/out, line pack-up
	# announcements, silo swap requests, and the short-form acknowledgements
	# you actually hear over the portagofoon. Order matches the menu's number
	# keys, so don't reorder without also rebinding the HUD shortcuts.
	"Start shift",
	"Stop shift",
	"Going on break",
	"Back from break",
	"Line 3A pack-up",
	"Line 3B pack-up",
	"Swap silo full",
	"Tank swap, give me 5",
	"Roger",
	"Copy that",
	"Wait one",
]

## Send the canned line at `index`. Plays the uplink chirp + emits
## transmit_sent so the HUD can show "you: <line>" and any future NPC subscribers
## (crew AI) can react. Returns false if the radio is dead — your colleagues
## won't hear you either, same as in real life. Out-of-range `index` is clamped
## (defensive — the menu always passes a valid index).
func transmit_line(index: int) -> bool:
	if PTT_LINES.is_empty():
		return false
	var clamped : int = clampi(index, 0, PTT_LINES.size() - 1)
	return transmit_freeform(PTT_LINES[clamped])

## Send an arbitrary `text` line over the radio (used by the local STT pipeline
## once it lands, and by tests). Mirrors transmit_line for the canned route, but
## bypasses PTT_LINES entirely. Returns false if the radio is dead.
##
## Routing: the squelch + carrier blip always plays on AudioManager (sidetone
## the operator hears in their own earpiece). If VoiceService is wired, we also
## request a real-voice render of the line in the OPERATOR voice; when it
## comes back the listener side (NPCs) will hear actual words. When VoiceService
## isn't wired, the existing squelch-only carrier path keeps working.
func transmit_freeform(text: String) -> bool:
	var line : String = String(text).strip_edges()
	if line.is_empty():
		return false
	var heard := battery_alive()
	if heard:
		var am := get_node_or_null("/root/AudioManager")
		if am and am.has_method("play_radio_uplink"):
			am.call("play_radio_uplink", line, headset_on)   # the keyed-up line drives the voice (#163)
		_request_voice(line, "operator")
	emit_signal("transmit_sent", line, heard)
	return heard

## Legacy alias — sends the FIRST canned line ("Copy that."). Kept so any
## test harness or future code path that still calls `transmit()` keeps working,
## but the in-game UI now goes through the menu + `transmit_line(index)`.
func transmit() -> bool:
	return transmit_line(0)

## Broadcasts a task over the radio so idle NPCs can pick it up.
func broadcast_task(task_type: String, target_node: Node, from_name: String = "operator") -> void:
	# Convert task to text
	var text := "Task: " + task_type
	if is_instance_valid(target_node) and target_node.has_method("get_name"):
		text += " at " + target_node.name
	transmit_freeform(text)
	emit_signal("task_broadcasted", task_type, target_node, from_name)

# =============================================================================
# LIVE MICROPHONE PUSH-TO-TALK (PTT)
# =============================================================================
func start_mic_ptt() -> bool:
	if not mic_enabled or not battery_alive() or is_transmitting_mic:
		return false
	is_transmitting_mic = true
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("start_mic_transmission"):
		am.call("start_mic_transmission", effective_loudness(), headset_on)
	emit_signal("mic_ptt_changed", true)
	return true

func stop_mic_ptt() -> void:
	if not is_transmitting_mic:
		return
	is_transmitting_mic = false
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("stop_mic_transmission"):
		am.call("stop_mic_transmission")
	emit_signal("mic_ptt_changed", false)

func get_mic_level() -> float:
	var am := get_node_or_null("/root/AudioManager")
	if am and am.has_method("get_mic_level"):
		return float(am.call("get_mic_level"))
	return 0.0

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_T and not event.echo:
		if event.pressed:
			start_mic_ptt()
		else:
			stop_mic_ptt()

# =============================================================================
# VOICE SERVICE INTEGRATION (#179 follow-up — real TTS optional)
# =============================================================================
## Ask VoiceService to synthesise `text` in the given voice. Best-effort: when
## the autoload isn't present (headless tests, stripped builds) or the active
## backend can't produce audio, this is a no-op and the existing AudioManager
## squelch carrier alone carries the message — no regression.
func _request_voice(text: String, voice_id: String) -> void:
	var vs := get_node_or_null("/root/VoiceService")
	if vs == null or not vs.has_method("speak"):
		return
	vs.speak(text, voice_id, voice_id)

## VoiceService finished synthesising a line — route the wav through
## AudioManager at the current loudness / headset routing. Null stream means
## synth failed: do nothing (squelch carrier alone carries the message).
func _on_voice_done(audio_stream) -> void:
	if audio_stream == null:
		return
	var am := get_node_or_null("/root/AudioManager")
	if am == null or not am.has_method("play_radio_voice_stream"):
		return
	am.play_radio_voice_stream(audio_stream, effective_loudness(), headset_on)

## Map an NPC display name onto a VoiceService voice_id. Falls back to the
## "_default" voice if the name isn't in the table. Operator-side keying always
## uses voice_id="operator" — that's hard-wired in transmit_freeform.
func _voice_id_for(from_name: String) -> String:
	var key := String(from_name).strip_edges().to_lower()
	if key.is_empty():
		return "_default"
	# Use the first space-separated token as the lookup key so "Mohammed (feeder)"
	# still resolves to the mohammed voice. Keep this list mirrored with
	# VoiceService.CLOUD_VOICE_MAP for the cloud backend.
	var parts := key.split(" ", false)
	var first : String = parts[0] if parts.size() > 0 else key
	const KNOWN : Array[String] = ["mohammed", "pascal", "kevin", "emrah", "yasin",
									"peter", "abdellilah", "shift_lead", "operator"]
	if KNOWN.has(first):
		return first
	return "_default"
