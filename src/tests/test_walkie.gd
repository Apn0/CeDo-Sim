extends SceneTree
## Headless test for the Walkie autoload.
##
## Run: godot --headless --path . --script res://src/tests/test_walkie.gd --quit-after 300
##
## Counted checks, not assert(). Two reasons, both measured rather than assumed:
## a failing assert() aborts _run_tests before quit(), so the SceneTree keeps
## iterating and the harness HANGS instead of going red; and assert() is compiled
## out of release builds, while run.sh:17-21 makes $GODOT overridable by design —
## under an export template the assert form would run top to bottom checking
## nothing and still print a pass.

var _pass := 0
var _fail := 0
var _skip := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok    : %s" % msg)
		_pass += 1
	else:
		print("  FAIL  : %s" % msg)
		_fail += 1

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== Walkie Autoload Tests ===")

	# The real autoloads already own the "AudioManager" and "VoiceService" names under /root,
	# so we must free or rename them before inserting our mocks to ensure Walkie's
	# get_node_or_null("/root/AudioManager") finds our mocks.
	# This works because Walkie caches neither: every touch is a fresh
	# get_node_or_null("/root/...") inside the method that needs it, so a rename
	# performed before the first call is enough (Walkie.gd:175, 238, 267, 277, 303).
	if root.has_node("AudioManager"):
		root.get_node("AudioManager").name = "AudioManager_Real"
	if root.has_node("VoiceService"):
		root.get_node("VoiceService").name = "VoiceService_Real"

	var am = MockAudioManager.new()
	am.name = "AudioManager"
	root.add_child(am)

	var vs = MockVoiceService.new()
	vs.name = "VoiceService"
	root.add_child(vs)

	var walkie = load("res://src/autoload/Walkie.gd").new()
	walkie.name = "Walkie"
	root.add_child(walkie)

	# Manually initialize since we skipped normal autoload startup
	walkie._ready()

	var BatteryType = load("res://src/sim/Battery.gd")

	# 1. Initial State
	print("Test: Initial state")
	_ok(walkie.battery_percent() == 100, "Initial battery should be 100%")
	_ok(walkie.battery_alive() == true, "Initial battery should be alive")
	_ok(walkie.headset_on == true, "Headset should be on by default")
	_ok(abs(walkie.volume - 0.6) < 0.001, "Volume should default to 0.6")

	# 2. Swap Battery
	print("Test: Swap battery")
	var flat = BatteryType.new(0.0)
	var fresh = walkie.swap_battery(flat)
	_ok(walkie.battery_alive() == false, "Walkie should be dead with flat battery")
	_ok(walkie.battery_percent() == 0, "Flat battery should show 0%")
	walkie.swap_battery(fresh) # put it back
	_ok(walkie.battery_alive() == true, "Walkie should be alive again")
	_ok(walkie.battery_percent() == 100, "Fresh battery should show 100%")

	# 3. Headset and Volume
	print("Test: Headset and Volume")
	_ok(abs(walkie.effective_loudness() - (0.6 * 0.55)) < 0.001, "Headset loudness capped")
	walkie.toggle_headset()
	_ok(walkie.headset_on == false, "Headset should be toggled off")
	_ok(abs(walkie.effective_loudness() - 0.6) < 0.001, "Speaker loudness is full volume")

	walkie.volume_up()
	_ok(abs(walkie.volume - 0.7) < 0.001, "Volume should increment by 0.1")
	walkie.volume_down()
	_ok(abs(walkie.volume - 0.6) < 0.001, "Volume should decrement by 0.1")

	# 4. Receive Call
	print("Test: Receive Call")
	am.calls.clear()
	vs.calls.clear()
	walkie.receive_call("Mohammed", "Hello")
	# Size claim first, index claim gated on it: a counted check does not abort,
	# so an unguarded calls[0] on an empty array would crash before the verdict
	# print — the hang bug wearing a different hat. The dependent claim still
	# counts as a FAIL (never a skip) when the guard trips.
	var am_call_one: bool = am.calls.size() == 1
	_ok(am_call_one, "AudioManager should play radio call")
	_ok(am_call_one and am.calls[0].method == "play_radio_call", "Wrong am method called")
	# The `if vs.calls.size() > 0:` guard that used to wrap the next two checks is
	# deliberately GONE. It silently deleted them precisely when VoiceService
	# stopped being asked to speak — i.e. it was blind to the one regression this
	# section exists to catch, which is the npc-05 vacuous-green shape this repo
	# has been bitten by before. MEASURED 2026-08-30: the mock IS called, so these
	# hold unconditionally and there is nothing to guard against.
	var vs_call_one: bool = vs.calls.size() == 1
	_ok(vs_call_one, "VoiceService should synthesize")
	_ok(vs_call_one and vs.calls[0].voice_id == "mohammed", "Voice ID lookup failed")

	# 5. Transmit Freeform
	print("Test: Transmit Freeform")
	am.calls.clear()
	vs.calls.clear()
	var tx_res = walkie.transmit_freeform("Copy")
	_ok(tx_res == true, "Should transmit successfully")
	var am_tx_one: bool = am.calls.size() == 1
	_ok(am_tx_one, "AudioManager should play uplink")
	_ok(am_tx_one and am.calls[0].method == "play_radio_uplink", "Wrong am method called")
	# Same de-guarding as section 4, same measurement.
	var vs_tx_one: bool = vs.calls.size() == 1
	_ok(vs_tx_one, "VoiceService should synthesize operator")
	_ok(vs_tx_one and vs.calls[0].voice_id == "operator", "Transmit must use operator voice")

	# 6. Live Mic PTT
	print("Test: Live Mic")
	am.calls.clear()
	var mic_res = walkie.start_mic_ptt()
	_ok(mic_res == true, "Mic should start")
	var am_mic_one: bool = am.calls.size() == 1
	_ok(am_mic_one, "AudioManager should start mic")
	_ok(am_mic_one and am.calls[0].method == "start_mic_transmission", "Wrong am method called")

	walkie.stop_mic_ptt()
	var am_mic_two: bool = am.calls.size() == 2
	_ok(am_mic_two, "AudioManager should stop mic")
	_ok(am_mic_two and am.calls[1].method == "stop_mic_transmission", "Wrong am method called")

	# 7. Dead Battery Silence
	print("Test: Dead Battery Silence")
	walkie.swap_battery(flat)
	_ok(walkie.effective_loudness() == 0.0, "Dead battery loudness should be 0")

	am.calls.clear()
	vs.calls.clear()
	walkie.receive_call("Mohammed", "Hello")
	_ok(am.calls.size() == 0, "No audio should play if battery is dead")
	_ok(vs.calls.size() == 0, "No TTS should happen if battery is dead")

	tx_res = walkie.transmit_freeform("Copy")
	_ok(tx_res == false, "Should not transmit if battery is dead")
	_ok(am.calls.size() == 0, "No uplink audio should play")
	_ok(vs.calls.size() == 0, "No TTS should happen")

	mic_res = walkie.start_mic_ptt()
	_ok(mic_res == false, "Should not start mic if battery is dead")
	_ok(am.calls.size() == 0, "No mic transmission should start")

	# Cleanup
	root.remove_child(walkie)
	walkie.free()
	root.remove_child(am)
	am.free()
	root.remove_child(vs)
	vs.free()

	# Restore real autoloads if they were renamed
	if root.has_node("AudioManager_Real"):
		root.get_node("AudioManager_Real").name = "AudioManager"
	if root.has_node("VoiceService_Real"):
		root.get_node("VoiceService_Real").name = "VoiceService"

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail, %d skip" % [_pass, _fail, _skip])
	print("Result: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("RESULT: %s" % ("PASS" if _fail == 0 else "FAIL"))
	print("=========================================")
	quit(0 if _fail == 0 else 1)

class MockAudioManager extends Node:
	var calls : Array = []

	func play_radio_call(text: String, loud: float, headset: bool) -> void:
		calls.append({"method": "play_radio_call", "text": text, "loud": loud, "headset": headset})

	func play_radio_uplink(line: String, headset: bool) -> void:
		calls.append({"method": "play_radio_uplink", "line": line, "headset": headset})

	func start_mic_transmission(loud: float, headset: bool) -> void:
		calls.append({"method": "start_mic_transmission", "loud": loud, "headset": headset})

	func stop_mic_transmission() -> void:
		calls.append({"method": "stop_mic_transmission"})

class MockVoiceService extends Node:
	signal voice_done(audio_stream)

	var calls : Array = []

	func speak(text: String, voice_id: String = "_default", npc_name: String = "") -> void:
		calls.append({"method": "speak", "text": text, "voice_id": voice_id, "sync_id": npc_name})
