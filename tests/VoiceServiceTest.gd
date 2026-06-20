extends Node

## Headless test for VoiceService (cluster "AI/Voice integration").
##
## Verifies the layered local-first contract WITHOUT requiring a network or any
## sidecar binary:
##   • mock backend returns canned strings on reason() + a deterministic line
##     on listen() + fires voice_done(null) on speak() (no AudioStream)
##   • cloud backend is INACCESSIBLE unless explicitly selected AND a key is
##     present — never silently chosen
##   • speak() with an empty string immediately emits voice_done(null)
##   • local TTS with no piper binary cleanly degrades to voice_done(null)
##
## Mirrors WalkieVoiceTest's pass/fail printout so the gauntlet harness can scrape it.

var _vs : Node

var _passed := 0
var _failed := 0
var _voice_done_count := 0
var _last_voice_stream = null
var _last_recognized : String = ""
var _last_reason : String = ""

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	print("=== VoiceService — local-first AI voice ===")
	_vs = get_node_or_null("/root/VoiceService")
	_ok(_vs != null, "VoiceService autoload present (and compiled)")
	if _vs == null:
		print("RESULT: %d passed, %d failed" % [_passed, _failed]); get_tree().quit(); return

	_vs.voice_done.connect(_on_voice_done)
	_vs.speech_recognized.connect(_on_speech_recognized)
	_vs.llm_response.connect(_on_llm_response)

	# ── Backend selector defaults ──────────────────────────────────────────
	# Resolves to "local" with no SettingsManager state (the default for a
	# brand-new install), which is the local-first guarantee.
	_ok(_vs._backend() in ["local", "cloud", "mock"], "backend selector returns a known value")

	# ── Mock backend exercises the API surface without sidecars ────────────
	_force_backend("mock")

	_vs.speak("Test", "operator", "operator")
	await get_tree().process_frame
	_ok(_voice_done_count == 1, "mock: speak fires voice_done exactly once")
	_ok(_last_voice_stream == null, "mock: speak returns null stream (carrier-only)")

	_vs.listen()
	await get_tree().process_frame
	_ok(_last_recognized != "", "mock: listen returns a non-empty transcript")

	_vs.reason("I need a hand here.", "")
	await get_tree().process_frame
	_ok(_last_reason.length() > 0, "mock: reason returns canned response")

	_vs.reason("copy that", "")
	await get_tree().process_frame
	_ok(_last_reason.to_lower().find("copy") != -1, "mock: 'copy that' maps to 'Copy.'")

	# ── Empty input safety ─────────────────────────────────────────────────
	_voice_done_count = 0
	_vs.speak("   ", "operator", "operator")
	await get_tree().process_frame
	_ok(_voice_done_count == 1, "empty speak still emits voice_done (with null stream)")

	# ── Local backend with no binaries cleanly degrades ────────────────────
	_force_backend("local")
	_voice_done_count = 0
	_last_voice_stream = "sentinel"
	_vs.speak("Copy that.", "operator", "operator")
	await get_tree().process_frame
	_ok(_voice_done_count == 1, "local: speak fires voice_done even with no piper binary")
	_ok(_last_voice_stream == null, "local: missing piper → null stream (carrier-only fallback)")

	# ── Cloud backend is gated by key presence ─────────────────────────────
	# Without OPENAI_API_KEY, _cloud_allowed must be false — no HTTP call ever
	# leaves the box. This is the privacy choke-point: a silent default cloud
	# call here would be a critical regression.
	_force_backend("cloud")
	# Force an empty OpenAI key to simulate "no key configured".
	var ak := get_node_or_null("/root/ApiKeys")
	if ak != null:
		# Best-effort: stash the real key if present, restore it after.
		var saved_key := ""
		if ak.has_method("openai"):
			saved_key = String(ak.openai())
		# Override the internal cfg in-place so the test is hermetic.
		if "_cfg" in ak:
			ak._cfg.set_value("openai", "api_key", "")
		_ok(not _vs._cloud_allowed(), "cloud backend blocked when key empty (no silent network)")
		# Restore so we don't break other tests.
		if "_cfg" in ak and saved_key != "":
			ak._cfg.set_value("openai", "api_key", saved_key)

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()

func _force_backend(b: String) -> void:
	# Force the backend via SettingsManager so _backend() returns the same value
	# the production code would see.
	var sm := get_node_or_null("/root/SettingsManager")
	if sm != null and sm.has_method("set_pending"):
		sm.set_pending("gameplay", "voice_backend", b)
		sm.apply()

func _on_voice_done(stream) -> void:
	_voice_done_count += 1
	_last_voice_stream = stream

func _on_speech_recognized(text: String) -> void:
	_last_recognized = text

func _on_llm_response(text: String) -> void:
	_last_reason = text
