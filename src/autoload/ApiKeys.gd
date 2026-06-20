extends Node

## Centralized API-key loader. Reads from `user://api_keys.cfg` so secrets stay
## out of the project source tree and never get committed. The cfg is created
## on first run from the .env on the operator's Desktop if present; otherwise
## it stays empty and consumers gracefully fall back (Walkie keeps using the
## synthesized squelch carrier when google_api_key is empty).
##
## Register as autoload "ApiKeys".
##
## Usage:
##   var key := ApiKeys.google()
##   if key.is_empty():
##       # no cloud TTS/STT — use local fallback
##       ...

const CFG_PATH : String = "user://api_keys.cfg"

var _cfg : ConfigFile = ConfigFile.new()

func _ready() -> void:
	if _cfg.load(CFG_PATH) != OK:
		_bootstrap_from_env()
		_cfg.load(CFG_PATH)

## Operator stores a `.env` on their Desktop with one or more of:
##   GOOGLE_API_KEY=…
##   OPENAI_API_KEY=…
## On first launch we read that file once, copy the keys into
## user://api_keys.cfg, and from then on the cfg is authoritative. We never read
## Desktop again — that keeps the secret in user-only writable space and prevents
## accidental commits.
func _bootstrap_from_env() -> void:
	var env_path : String = "C:/Users/arnod/Desktop/.env"
	if not FileAccess.file_exists(env_path):
		return
	var f := FileAccess.open(env_path, FileAccess.READ)
	if f == null:
		return
	var google_key : String = ""
	var openai_key : String = ""
	while not f.eof_reached():
		var line : String = f.get_line().strip_edges()
		if line.begins_with("GOOGLE_API_KEY="):
			google_key = line.substr("GOOGLE_API_KEY=".length()).strip_edges()
		elif line.begins_with("OPENAI_API_KEY="):
			openai_key = line.substr("OPENAI_API_KEY=".length()).strip_edges()
	f.close()
	var wrote := false
	if not google_key.is_empty():
		_cfg.set_value("google", "api_key", google_key)
		wrote = true
	if not openai_key.is_empty():
		_cfg.set_value("openai", "api_key", openai_key)
		wrote = true
	if wrote:
		_cfg.save(CFG_PATH)
		print("[ApiKeys] Bootstrapped API keys from Desktop .env into ", CFG_PATH)

## Google Cloud API key (used for Speech-to-Text + Text-to-Speech). Empty
## string means the cfg is missing or the key wasn't found — caller MUST
## fall back to a local/non-cloud path.
func google() -> String:
	return String(_cfg.get_value("google", "api_key", ""))

## OpenAI API key (used by VoiceService cloud backend: whisper-1 STT,
## gpt-4o-mini chat, tts-1 voice). Empty string means cloud must NOT be used —
## VoiceService._cloud_allowed() returns false and the call silently degrades
## to the local or mock backend (never silently to the cloud).
func openai() -> String:
	return String(_cfg.get_value("openai", "api_key", ""))
