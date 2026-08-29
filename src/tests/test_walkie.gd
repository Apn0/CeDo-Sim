extends SceneTree

func _initialize() -> void:
	call_deferred("_run_tests")

func _run_tests() -> void:
	print("=== Walkie Autoload Tests ===")

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
	assert(walkie.battery_percent() == 100, "Initial battery should be 100%")
	assert(walkie.battery_alive() == true, "Initial battery should be alive")
	assert(walkie.headset_on == true, "Headset should be on by default")
	assert(abs(walkie.volume - 0.6) < 0.001, "Volume should default to 0.6")

	# 2. Swap Battery
	print("Test: Swap battery")
	var flat = BatteryType.new(0.0)
	var fresh = walkie.swap_battery(flat)
	assert(walkie.battery_alive() == false, "Walkie should be dead with flat battery")
	assert(walkie.battery_percent() == 0, "Flat battery should show 0%")
	walkie.swap_battery(fresh) # put it back
	assert(walkie.battery_alive() == true, "Walkie should be alive again")
	assert(walkie.battery_percent() == 100, "Fresh battery should show 100%")

	# 3. Headset and Volume
	print("Test: Headset and Volume")
	assert(abs(walkie.effective_loudness() - (0.6 * 0.55)) < 0.001, "Headset loudness capped")
	walkie.toggle_headset()
	assert(walkie.headset_on == false, "Headset should be toggled off")
	assert(abs(walkie.effective_loudness() - 0.6) < 0.001, "Speaker loudness is full volume")

	walkie.volume_up()
	assert(abs(walkie.volume - 0.7) < 0.001, "Volume should increment by 0.1")
	walkie.volume_down()
	assert(abs(walkie.volume - 0.6) < 0.001, "Volume should decrement by 0.1")

	# 4. Receive Call
	print("Test: Receive Call")
	am.calls.clear()
	vs.calls.clear()
	walkie.receive_call("Mohammed", "Hello")
	assert(am.calls.size() == 1, "AudioManager should play radio call")
	assert(am.calls[0].method == "play_radio_call", "Wrong am method called")
	if vs.calls.size() > 0:
		assert(vs.calls.size() == 1, "VoiceService should synthesize")
		assert(vs.calls[0].voice_id == "mohammed", "Voice ID lookup failed")

	# 5. Transmit Freeform
	print("Test: Transmit Freeform")
	am.calls.clear()
	vs.calls.clear()
	var tx_res = walkie.transmit_freeform("Copy")
	assert(tx_res == true, "Should transmit successfully")
	assert(am.calls.size() == 1, "AudioManager should play uplink")
	assert(am.calls[0].method == "play_radio_uplink", "Wrong am method called")
	if vs.calls.size() > 0:
		assert(vs.calls.size() == 1, "VoiceService should synthesize operator")
		assert(vs.calls[0].voice_id == "operator", "Transmit must use operator voice")

	# 6. Live Mic PTT
	print("Test: Live Mic")
	am.calls.clear()
	var mic_res = walkie.start_mic_ptt()
	assert(mic_res == true, "Mic should start")
	assert(am.calls.size() == 1, "AudioManager should start mic")
	assert(am.calls[0].method == "start_mic_transmission", "Wrong am method called")

	walkie.stop_mic_ptt()
	assert(am.calls.size() == 2, "AudioManager should stop mic")
	assert(am.calls[1].method == "stop_mic_transmission", "Wrong am method called")

	# 7. Dead Battery Silence
	print("Test: Dead Battery Silence")
	walkie.swap_battery(flat)
	assert(walkie.effective_loudness() == 0.0, "Dead battery loudness should be 0")

	am.calls.clear()
	vs.calls.clear()
	walkie.receive_call("Mohammed", "Hello")
	assert(am.calls.size() == 0, "No audio should play if battery is dead")
	assert(vs.calls.size() == 0, "No TTS should happen if battery is dead")

	tx_res = walkie.transmit_freeform("Copy")
	assert(tx_res == false, "Should not transmit if battery is dead")
	assert(am.calls.size() == 0, "No uplink audio should play")
	assert(vs.calls.size() == 0, "No TTS should happen")

	mic_res = walkie.start_mic_ptt()
	assert(mic_res == false, "Should not start mic if battery is dead")
	assert(am.calls.size() == 0, "No mic transmission should start")

	print("All tests passed.")

	# Cleanup
	root.remove_child(walkie)
	walkie.free()
	root.remove_child(am)
	am.free()
	root.remove_child(vs)
	vs.free()

	quit(0)

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
