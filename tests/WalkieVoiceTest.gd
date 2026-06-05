extends Node3D

## #163 — the walkie voice is now a formant synth DRIVEN BY THE MESSAGE TEXT.
## The sound quality is judged in-game (can't hear it headless), but the text→
## syllable-plan logic and the arming of the synth are verifiable here:
##   • a message becomes a list of voiced syllables + word-gap consonants
##   • a longer message produces a longer transmission (rhythm tracks the words)
##   • incoming calls and PTT uplinks both arm the synth; a dead radio does not.

var _am : Node

var _passed := 0
var _failed := 0

func _ok(cond: bool, label: String) -> void:
	if cond:
		_passed += 1
		print("  ok    %s" % label)
	else:
		_failed += 1
		print("  FAIL  %s" % label)

func _ready() -> void:
	print("=== #163 WALKIE FORMANT VOICE ===")
	_am = get_node_or_null("/root/AudioManager")
	_ok(_am != null, "AudioManager autoload present (and compiled)")
	if _am == null:
		print("RESULT: %d passed, %d failed" % [_passed, _failed]); get_tree().quit(); return

	# Text → syllable plan.
	var short_plan : Array = _am._build_voice_plan("Copy that.")
	var long_plan  : Array = _am._build_voice_plan("Tank swap, give me five.")
	_ok(short_plan.size() >= 3, "short line yields multiple syllables (%d segments)" % short_plan.size())
	var voiced := 0
	for seg in short_plan:
		if bool(seg["voiced"]):
			voiced += 1
	_ok(voiced >= 2, "plan has voiced (vowel) syllables (%d)" % voiced)

	var d_short : float = _am._plan_duration(short_plan)
	var d_long  : float = _am._plan_duration(long_plan)
	_ok(d_long > d_short, "longer message → longer voice (%.2fs > %.2fs)" % [d_long, d_short])

	# A single word still speaks (≥1 syllable).
	_ok(_am._build_voice_plan("Standby.").size() >= 1, "single word still produces a syllable")

	# Incoming call arms the synth; length = squelch (~0.20s) + plan.
	_am.play_radio_call("Copy that.", 0.6, false)
	_ok(float(_am._radio_t) > 0.0, "incoming call arms the voice synth")
	_ok(absf(float(_am._radio_len) - (d_short + 0.20)) < 0.01,
		"call length = opening + plan + closing squelch (%.2fs)" % float(_am._radio_len))

	# Dead radio (loudness 0) must NOT arm — nothing comes through.
	_am._radio_t = 0.0
	_am.play_radio_call("Anybody there?", 0.0, false)
	_ok(float(_am._radio_t) == 0.0, "zero loudness (dead battery) does not arm")

	# PTT uplink arms with the keyed-up line too.
	_am.play_radio_uplink("On my way.", true)
	_ok(float(_am._radio_t) > 0.0, "PTT uplink arms the voice synth")

	print("RESULT: %d passed, %d failed" % [_passed, _failed])
	get_tree().quit()
