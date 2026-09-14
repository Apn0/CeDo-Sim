extends Node

## Local-first AI voice service (STT / LLM / TTS) for the walkie + crew comms.
##
## Register as autoload "VoiceService" (no class_name — autoload-name collision rule).
##
## Three backends behind a single API, selected via SettingsManager → "voice_backend":
##   "local" — shell-execs whisper.cpp / llama.cpp / piper using OS.execute. Paths
##             configurable via user://voice_paths.cfg. Default.
##   "cloud" — OpenAI APIs (whisper-1 STT, gpt-4o-mini, tts-1). DISABLED unless
##             explicitly toggled by the operator AND ApiKeys.openai() is set.
##             Never silently used.
##   "mock"  — returns canned strings. For dev / headless tests.
##
## Public API:
##   speak(text, voice_id, npc_name)  -> emits voice_done(stream_or_null)
##   listen()                          -> begins mic capture, emits speech_recognized(text)
##   reason(prompt, system)            -> emits llm_response(text)
##
## Local-first ordering — every call goes Local → (if opted in) Cloud → text-only
## fallback. We NEVER silently use the cloud, and we NEVER block gameplay on a
## network call: every backend hop is best-effort, errors are logged, and the
## walkie keeps working (text-only / squelch carrier) when nothing succeeds.
##
## This intentionally does NOT duplicate Walkie's audio plumbing — when TTS
## produces a stream, Walkie / AudioManager remain the speakers. When TTS fails,
## the squelch carrier in AudioManager.play_radio_call still fires from the
## existing receive_call path, so the walkie always at least "transmits" the text.

# ─────────────────────────────────────────────────────────────────────────────
# SIGNALS
# ─────────────────────────────────────────────────────────────────────────────
## Emitted when speak() finishes. `audio_stream` is the AudioStream the caller
## can hand to an AudioStreamPlayer, or `null` if synthesis failed (caller should
## fall back to text-only / squelch carrier).
signal voice_done(audio_stream)
## Emitted when listen() ends-of-speech and STT produced a transcript. Empty
## string means STT failed — caller falls back to the PTT_LINES menu.
signal speech_recognized(text: String)
## Emitted when reason() returns an LLM response. Empty string = failure.
signal llm_response(text: String)

# ─────────────────────────────────────────────────────────────────────────────
# CONSTANTS
# ─────────────────────────────────────────────────────────────────────────────
const BACKEND_LOCAL : String = "local"
const BACKEND_CLOUD : String = "cloud"
const BACKEND_MOCK  : String = "mock"

const PATHS_CFG : String = "user://voice_paths.cfg"

# Default tool paths (override via voice_paths.cfg).
const DEFAULT_WHISPER_PATH : String = "user://tools/whisper/main.exe"
const DEFAULT_LLAMA_PATH   : String = "user://tools/llama/llama.exe"
const DEFAULT_PIPER_PATH   : String = "user://tools/piper/piper.exe"
const DEFAULT_WHISPER_MODEL: String = "user://tools/whisper/models/ggml-small.en.bin"
const DEFAULT_LLAMA_MODEL  : String = "user://tools/llama/models/llama-3b.gguf"
const DEFAULT_PIPER_VOICE  : String = "user://tools/piper/voices/en_US-amy-medium.onnx"

# Allowlist root for everything handed to OS.execute. The whisper / llama / piper
# binaries all live under user://tools/ by default; _exec_tool refuses to run
# anything that resolves outside this directory, so a tampered or imported
# voice_paths.cfg cannot redirect the exec at an arbitrary binary (local RCE).
const TOOLS_ROOT : String = "user://tools/"

# Cloud (OpenAI) endpoints.
const OPENAI_STT_URL  : String = "https://api.openai.com/v1/audio/transcriptions"
const OPENAI_CHAT_URL : String = "https://api.openai.com/v1/chat/completions"
const OPENAI_TTS_URL  : String = "https://api.openai.com/v1/audio/speech"

# Map our internal voice_id → OpenAI tts-1 voice. Keep keys stable; cloud
# voice names can change without touching the call sites.
const CLOUD_VOICE_MAP : Dictionary = {
	"operator":    "onyx",      # the player
	"mohammed":    "echo",
	"pascal":      "fable",
	"kevin":       "onyx",
	"emrah":       "echo",
	"yasin":       "alloy",
	"peter":       "fable",     # production manager
	"abdellilah":  "echo",
	"shift_lead":  "onyx",
	"_default":    "alloy",
}

# Mock responses keyed loosely by prompt fragment — keeps headless tests honest.
const MOCK_REASONS : Dictionary = {
	"need a hand":       "On my way, boss.",
	"going on break":    "Roger, enjoy the break.",
	"back from break":   "Welcome back.",
	"copy that":         "Copy.",
	"_default":          "Standby.",
}

# ─────────────────────────────────────────────────────────────────────────────
# STATE
# ─────────────────────────────────────────────────────────────────────────────
var _paths_cfg : ConfigFile = ConfigFile.new()
var _http_stt  : HTTPRequest
var _http_chat : HTTPRequest
var _http_tts  : HTTPRequest

## Set true after the first OS.execute attempt against each tool — if the
## binary is missing we record the failure and silently degrade for the rest of
## the session (no spamming the console with "file not found" each PTT).
var _local_whisper_ok : bool = true
var _local_llama_ok   : bool = true
var _local_piper_ok   : bool = true

# In-flight call context for HTTP callbacks (single-flight per channel; new call
# pre-empts the old). Tracks which speak/reason/listen invocation a response
# belongs to so we don't fire stale signals.
var _stt_pending  : bool = false
var _chat_pending : bool = false
var _tts_pending  : bool = false
var _tts_context  : Dictionary = {}     # {"npc_name": ..., "voice_id": ...}

# ─────────────────────────────────────────────────────────────────────────────
# LIFECYCLE
# ─────────────────────────────────────────────────────────────────────────────
func _ready() -> void:
	if _paths_cfg.load(PATHS_CFG) != OK:
		# First run — write defaults so the operator has a config to edit.
		_seed_default_paths()
		_paths_cfg.load(PATHS_CFG)

	# HTTP nodes for cloud calls. We create three so STT, chat and TTS can run
	# concurrently without trampling each other's responses.
	_http_stt  = HTTPRequest.new()
	_http_chat = HTTPRequest.new()
	_http_tts  = HTTPRequest.new()
	add_child(_http_stt)
	add_child(_http_chat)
	add_child(_http_tts)
	_http_stt.request_completed.connect(_on_stt_http_done)
	_http_chat.request_completed.connect(_on_chat_http_done)
	_http_tts.request_completed.connect(_on_tts_http_done)

# ─────────────────────────────────────────────────────────────────────────────
# PUBLIC API
# ─────────────────────────────────────────────────────────────────────────────

## Synthesise `text` in the given voice and fire voice_done(stream_or_null).
## `npc_name` is metadata for the caller (e.g. which AudioStreamPlayer3D to
## attach to) — we pass it through unmodified on the signal context.
func speak(text: String, voice_id: String = "_default", npc_name: String = "") -> void:
	var t := String(text).strip_edges()
	if t.is_empty():
		voice_done.emit(null)
		return
	var backend := _backend()
	if backend == BACKEND_MOCK:
		# Mock: emit null so the existing AudioManager squelch path still plays.
		# Tests just observe the signal firing.
		voice_done.emit(null)
		return
	if backend == BACKEND_LOCAL:
		var stream := _speak_local(t, voice_id)
		voice_done.emit(stream)
		return
	if backend == BACKEND_CLOUD:
		if not _cloud_allowed():
			_log_clear("speak: cloud backend selected but OPENAI_API_KEY missing or cloud not opted-in — degrading to text-only")
			voice_done.emit(null)
			return
		_tts_context = {"voice_id": voice_id, "npc_name": npc_name}
		_speak_cloud(t, voice_id)
		return
	voice_done.emit(null)

## Begin microphone capture, fire speech_recognized(text) on end-of-speech.
## v0.1 — the mic capture stack itself (AudioEffectCapture + PTT hold) isn't
## wired here; this method is the integration seam for it. When the mic layer
## is added, it hands its PackedFloat32Array to _transcribe_*().
##
## For now: in mock backend we synthesise a canned line; in local/cloud we
## emit "" so the walkie code path silently falls back to PTT_LINES menu.
func listen() -> void:
	var backend := _backend()
	if backend == BACKEND_MOCK:
		speech_recognized.emit("Need a hand here.")
		return
	# No actual mic capture wired yet — silently degrade.
	if backend == BACKEND_LOCAL:
		_log_clear("listen: local STT not yet wired (no mic capture layer) — operator should use PTT_LINES menu")
	elif backend == BACKEND_CLOUD:
		_log_clear("listen: cloud STT requires mic capture layer + OPENAI_API_KEY — operator should use PTT_LINES menu")
	speech_recognized.emit("")

## Run an LLM completion on `prompt`. `system` is the system prompt (persona,
## crew context). Fires llm_response(text) — empty on failure.
func reason(prompt: String, system: String = "") -> void:
	var p := String(prompt).strip_edges()
	if p.is_empty():
		llm_response.emit("")
		return
	var backend := _backend()
	if backend == BACKEND_MOCK:
		llm_response.emit(_mock_reason(p))
		return
	if backend == BACKEND_LOCAL:
		var resp := _reason_local(p, system)
		llm_response.emit(resp)
		return
	if backend == BACKEND_CLOUD:
		if not _cloud_allowed():
			_log_clear("reason: cloud backend selected but OPENAI_API_KEY missing or cloud not opted-in — degrading to mock")
			llm_response.emit(_mock_reason(p))
			return
		_reason_cloud(p, system)
		return
	llm_response.emit("")

## Test entry point used by the Settings "Test voice" button. Speaks a short
## sample line in the chosen backend and reports success/failure into the log.
func test_voice() -> void:
	print("[VoiceService] test_voice (backend=", _backend(), ")")
	speak("Walkie test — this is the operator. Copy?", "operator", "operator")

# ─────────────────────────────────────────────────────────────────────────────
# BACKEND SELECTION + PRIVACY GUARDS
# ─────────────────────────────────────────────────────────────────────────────

## The currently selected backend, from SettingsManager. Defaults to "local"
## so a brand-new install never reaches for the cloud.
func _backend() -> String:
	var sm := get_node_or_null("/root/SettingsManager")
	if sm == null:
		return BACKEND_LOCAL
	var gp = sm.gameplay() if sm.has_method("gameplay") else {}
	var b := String(gp.get("voice_backend", BACKEND_LOCAL))
	if not [BACKEND_LOCAL, BACKEND_CLOUD, BACKEND_MOCK].has(b):
		return BACKEND_LOCAL
	return b

## Cloud is only allowed when the user explicitly picked the cloud backend AND
## we actually have a key. ApiKeys.openai() is the canonical accessor (we add
## it below). This is the choke-point: if it returns false, no HTTP request is
## sent — full stop.
func _cloud_allowed() -> bool:
	if _backend() != BACKEND_CLOUD:
		return false
	var ak := get_node_or_null("/root/ApiKeys")
	if ak == null:
		return false
	if not ak.has_method("openai"):
		return false
	return String(ak.openai()).strip_edges() != ""

# ─────────────────────────────────────────────────────────────────────────────
# LOCAL BACKEND — OS.execute sidecars
# ─────────────────────────────────────────────────────────────────────────────

## Run Piper to synthesise `text` and load the resulting wav. Returns null on
## any failure (binary missing, non-zero exit, can't read wav). Never raises —
## the caller falls back to squelch carrier.
func _speak_local(text: String, voice_id: String) -> AudioStream:
	if not _local_piper_ok:
		return null
	var piper := _path("piper", DEFAULT_PIPER_PATH)
	var voice := _voice_model_for(voice_id)
	if not _binary_present(piper, "piper"):
		_local_piper_ok = false
		return null
	# Write the prompt to a tempfile so the shell doesn't have to escape it.
	var prompt_path := "user://tmp_piper_in.txt"
	var wav_path    := "user://tmp_piper_out.wav"
	var f := FileAccess.open(prompt_path, FileAccess.WRITE)
	if f == null:
		return null
	f.store_string(text)
	f.close()
	var output : Array = []
	# piper.exe --model voice.onnx --output_file out.wav --input_file in.txt
	var args := [
		"--model", ProjectSettings.globalize_path(voice),
		"--output_file", ProjectSettings.globalize_path(wav_path),
		"--input_file", ProjectSettings.globalize_path(prompt_path),
	]
	var exit := _exec_tool(piper, args, output)
	if exit != 0:
		_log_clear("Piper exit=%d (text-only fallback). Install piper at %s and a voice model." % [exit, piper])
		return null
	# Load the produced wav. AudioStreamWAV.load_from_buffer would be ideal but
	# isn't available in core — read the bytes and let Godot's resource loader
	# figure it out via ResourceLoader.load.
	if not FileAccess.file_exists(wav_path):
		return null
	var stream := ResourceLoader.load(wav_path, "AudioStream") as AudioStream
	return stream

## Run llama.cpp in single-shot mode. Returns the model's reply, trimmed; or "".
func _reason_local(prompt: String, system: String) -> String:
	if not _local_llama_ok:
		return ""
	var llama := _path("llama", DEFAULT_LLAMA_PATH)
	var model := _path("llama_model", DEFAULT_LLAMA_MODEL)
	if not _binary_present(llama, "llama"):
		_local_llama_ok = false
		return ""
	var joined : String = ""
	if not system.is_empty():
		joined += "<<SYS>>\n%s\n<</SYS>>\n" % system
	joined += prompt

	var prompt_path := "user://tmp_llama_in.txt"
	var f := FileAccess.open(prompt_path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(joined)
	f.close()

	var output : Array = []
	var args := [
		"-m", ProjectSettings.globalize_path(model),
		"-f", ProjectSettings.globalize_path(prompt_path),
		"-n", "120",
		"--no-display-prompt",
	]
	var exit := _exec_tool(llama, args, output)
	if exit != 0:
		_log_clear("llama.cpp exit=%d (mock fallback)." % exit)
		return ""
	# `output` is the OS.execute fill array — always Array, one entry per
	# stdout chunk. Join is the canonical extraction.
	var raw : String = "\n".join(output)
	return raw.strip_edges()

## Run whisper.cpp on a PCM wav at `wav_path`. Returns the transcript (trimmed)
## or "". Currently unused (no mic capture layer yet) but kept here so the
## STT path is one method call away once the mic layer lands.
func _transcribe_local(wav_path: String) -> String:
	if not _local_whisper_ok:
		return ""
	var whisper := _path("whisper", DEFAULT_WHISPER_PATH)
	var model   := _path("whisper_model", DEFAULT_WHISPER_MODEL)
	if not _binary_present(whisper, "whisper"):
		_local_whisper_ok = false
		return ""
	if not FileAccess.file_exists(wav_path):
		return ""
	var output : Array = []
	var args := [
		"-m", ProjectSettings.globalize_path(model),
		"-f", ProjectSettings.globalize_path(wav_path),
		"-otxt", "-of", ProjectSettings.globalize_path(wav_path) + ".out",
		"--no-prints",
	]
	var exit := _exec_tool(whisper, args, output)
	if exit != 0:
		_log_clear("whisper.cpp exit=%d (text-only fallback)." % exit)
		return ""
	# whisper.cpp writes the transcript to <wav>.out.txt
	var txt_path := wav_path + ".out.txt"
	if not FileAccess.file_exists(txt_path):
		return ""
	var f := FileAccess.open(txt_path, FileAccess.READ)
	if f == null:
		return ""
	var s := f.get_as_text()
	f.close()
	return s.strip_edges()

# ─────────────────────────────────────────────────────────────────────────────
# CLOUD BACKEND — OpenAI APIs
# ─────────────────────────────────────────────────────────────────────────────

func _speak_cloud(text: String, voice_id: String) -> void:
	if _tts_pending:
		# Pre-empt the previous request — there is only ever one player voice.
		_http_tts.cancel_request()
	_tts_pending = true
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _openai_key(),
		"Content-Type: application/json",
	])
	var voice_name := String(CLOUD_VOICE_MAP.get(voice_id, CLOUD_VOICE_MAP["_default"]))
	var body := {
		"model":  "tts-1",
		"input":  text,
		"voice":  voice_name,
		"format": "wav",
	}
	var err := _http_tts.request(OPENAI_TTS_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	headers[0] = "Authorization: Bearer [REDACTED]"
	if err != OK:
		_tts_pending = false
		_log_clear("cloud TTS request init failed: %s" % err)
		voice_done.emit(null)

func _reason_cloud(prompt: String, system: String) -> void:
	if _chat_pending:
		_http_chat.cancel_request()
	_chat_pending = true
	var headers := PackedStringArray([
		"Authorization: Bearer %s" % _openai_key(),
		"Content-Type: application/json",
	])
	var messages : Array = []
	if not system.is_empty():
		messages.append({"role": "system", "content": system})
	messages.append({"role": "user", "content": prompt})
	var body := {
		"model":    "gpt-4o-mini",
		"messages": messages,
		"temperature": 0.7,
	}
	var err := _http_chat.request(OPENAI_CHAT_URL, headers, HTTPClient.METHOD_POST, JSON.stringify(body))
	headers[0] = "Authorization: Bearer [REDACTED]"
	if err != OK:
		_chat_pending = false
		_log_clear("cloud chat request init failed: %s" % err)
		llm_response.emit("")

func _on_stt_http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_stt_pending = false
	if code < 200 or code >= 300:
		speech_recognized.emit("")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		speech_recognized.emit("")
		return
	speech_recognized.emit(String(parsed.get("text", "")))

func _on_chat_http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_chat_pending = false
	if code < 200 or code >= 300:
		llm_response.emit("")
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not (parsed is Dictionary):
		llm_response.emit("")
		return
	var choices = parsed.get("choices", [])
	if not (choices is Array) or choices.is_empty():
		llm_response.emit("")
		return
	var msg = (choices[0] as Dictionary).get("message", {})
	llm_response.emit(String(msg.get("content", "")))

func _on_tts_http_done(_result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_tts_pending = false
	if code < 200 or code >= 300 or body.is_empty():
		voice_done.emit(null)
		return
	# Write to user:// so the engine can load it via ResourceLoader (no in-memory
	# AudioStreamWAV.create from bytes API in core Godot 4.6).
	var wav_path := "user://tmp_cloud_tts.wav"
	var f := FileAccess.open(wav_path, FileAccess.WRITE)
	if f == null:
		voice_done.emit(null)
		return
	f.store_buffer(body)
	f.close()
	var stream := ResourceLoader.load(wav_path, "AudioStream") as AudioStream
	voice_done.emit(stream)

# ─────────────────────────────────────────────────────────────────────────────
# MOCK BACKEND
# ─────────────────────────────────────────────────────────────────────────────

func _mock_reason(prompt: String) -> String:
	var lower := prompt.to_lower()
	for k in MOCK_REASONS.keys():
		if k == "_default":
			continue
		if lower.find(k) != -1:
			return String(MOCK_REASONS[k])
	return String(MOCK_REASONS["_default"])

# ─────────────────────────────────────────────────────────────────────────────
# CONFIG / HELPERS
# ─────────────────────────────────────────────────────────────────────────────

func _path(key: String, default_value: String) -> String:
	return String(_paths_cfg.get_value("tools", key, default_value))

func _voice_model_for(voice_id: String) -> String:
	# Per-NPC voice models can be configured under [voices] in voice_paths.cfg
	# (e.g. voices/mohammed = "user://tools/piper/voices/nl_NL-mls_5809-low.onnx").
	# Falls back to the default voice model so the system still produces sound
	# even if the operator hasn't curated per-NPC voices yet.
	return String(_paths_cfg.get_value("voices", voice_id, DEFAULT_PIPER_VOICE))

func _binary_present(path: String, label: String) -> bool:
	var abs_path := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(abs_path):
		return true
	_log_clear("%s binary not found at %s — install the local tool or switch to cloud/mock backend." % [label, path])
	return false

## True when `path` resolves to a location inside TOOLS_ROOT after globalizing
## and collapsing any ./ or ../ segments. Gates OS.execute so a configured tool
## path can't escape the tools dir — e.g. an absolute C:/Windows/System32/cmd.exe
## or a user://tools/../../payload.exe traversal. Fails closed: an empty or
## unresolved path returns false.
func _is_trusted_tool_path(path: String) -> bool:
	if path.strip_edges() == "":
		return false
	var root := ProjectSettings.globalize_path(TOOLS_ROOT).simplify_path()
	if not root.ends_with("/"):
		root += "/"
	var abs_path := ProjectSettings.globalize_path(path).simplify_path()
	return abs_path.begins_with(root)

## OS.execute gated by the TOOLS_ROOT allowlist. Returns the child exit code, or
## -1 when `tool_path` is refused for resolving outside the allowlist. Callers
## already treat any non-zero exit as "degrade to mock / text-only fallback", so
## a refusal is a safe no-op rather than a hard failure.
func _exec_tool(tool_path: String, args: Array, output: Array) -> int:
	if not _is_trusted_tool_path(tool_path):
		_log_clear("refusing to exec '%s' — outside the %s allowlist (check voice_paths.cfg)." % [tool_path, TOOLS_ROOT])
		return -1

	var re := RegEx.new()
	re.compile("[&|;<>`$\n\r%\\^\\\"'\\\\()\\[\\]\\{\\}!\\*\\?\\~]")
	for arg in args:
		var s := String(arg)
		if re.search(s) != null:
			_log_clear("refusing to exec '%s' — unsafe argument detected: %s" % [tool_path, s])
			return -1

	return OS.execute(ProjectSettings.globalize_path(tool_path), args, output, true)

func _openai_key() -> String:
	var ak := get_node_or_null("/root/ApiKeys")
	if ak == null:
		return ""
	if not ak.has_method("openai"):
		return ""
	return String(ak.openai())

# Single-shot console logger that prefixes a category so the operator can spot
# voice-stack errors in godot.log without spamming the console — each tool's
# failure is recorded once (see _local_*_ok flags above).
func _log_clear(msg: String) -> void:
	print("[VoiceService] " + msg)

func _seed_default_paths() -> void:
	_paths_cfg.set_value("tools", "whisper",       DEFAULT_WHISPER_PATH)
	_paths_cfg.set_value("tools", "whisper_model", DEFAULT_WHISPER_MODEL)
	_paths_cfg.set_value("tools", "llama",         DEFAULT_LLAMA_PATH)
	_paths_cfg.set_value("tools", "llama_model",   DEFAULT_LLAMA_MODEL)
	_paths_cfg.set_value("tools", "piper",         DEFAULT_PIPER_PATH)
	# voice_paths.cfg also has a [voices] section for per-NPC piper models —
	# operators can populate it by hand. Defaults to DEFAULT_PIPER_VOICE.
	_paths_cfg.set_value("voices", "_default",     DEFAULT_PIPER_VOICE)
	_paths_cfg.save(PATHS_CFG)
