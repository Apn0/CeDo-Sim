extends Node
## Headless verification of the 11 settings I wired up.
##
## Run via the project boot path so autoloads register as globals:
##   godot --headless --main-scene res://test_settings_wiring.tscn
##
## The test runs in _ready, prints a pass/fail summary, and quits.

var _fail := 0
var _pass := 0

func _ok(cond: bool, msg: String) -> void:
	if cond:
		print("  ok   : %s" % msg)
		_pass += 1
	else:
		print("  FAIL : %s" % msg)
		_fail += 1

func _section(title: String) -> void:
	print("\n[%s]" % title)

func _ready() -> void:
	print("=== Settings wiring verification ===")
	# All autoloads from project.godot are already registered by the engine
	# because we booted via --main-scene.
	var sm = get_node_or_null("/root/SettingsManager")
	if sm == null:
		print("FAIL: SettingsManager autoload not present"); get_tree().quit(1); return

	# ── 1. gamepad_deadzone → InputMap.action_set_deadzone ─────────────────
	_section("gamepad_deadzone")
	sm.set_pending("gameplay", "gamepad_deadzone", 0.42)
	sm.apply()
	var dz := InputMap.action_get_deadzone("move_forward")
	_ok(abs(dz - 0.42) < 0.001, "deadzone 0.42 → InputMap.move_forward = %.3f" % dz)
	sm.set_pending("gameplay", "gamepad_deadzone", 0.15); sm.apply()

	# ── 2. language → TranslationServer.set_locale ─────────────────────────
	_section("language")
	sm.set_pending("gameplay", "language", "nl"); sm.apply()
	_ok(TranslationServer.get_locale() == "nl",
		"language=nl → TranslationServer.get_locale() = %s" % TranslationServer.get_locale())
	sm.set_pending("gameplay", "language", "en"); sm.apply()
	_ok(TranslationServer.get_locale() == "en", "language=en → reverted")

	# ── 3. mute_unfocused → blur/unblur Master bus ─────────────────────────
	_section("mute_unfocused")
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx < 0:
		print("  skip : Master bus not in audio layout")
	else:
		sm.set_pending("audio", "master_db", -7.0)
		sm.set_pending("audio", "mute_unfocused", true)
		sm.apply()
		var baseline := AudioServer.get_bus_volume_db(master_idx)
		_ok(abs(baseline - (-7.0)) < 0.01, "master_db=-7 applied (%.2f dB)" % baseline)
		sm._blur_audio()
		var blurred := AudioServer.get_bus_volume_db(master_idx)
		_ok(blurred <= -70.0, "_blur_audio drops Master to %.1f dB" % blurred)
		sm._unblur_audio()
		var restored := AudioServer.get_bus_volume_db(master_idx)
		_ok(abs(restored - (-7.0)) < 0.01, "_unblur_audio restores to %.2f dB" % restored)

	# ── 4. Settings round-trip for the remaining flags ─────────────────────
	_section("storage round-trip")
	var roundtrip := {
		"head_bob": false, "hud_opacity": 0.55,
		"show_interaction_prompts": false, "tutorial_hints": false,
		"autosave_interval_s": 30, "units": "imperial",
		"subtitles": true, "subtitle_size": "large",
	}
	for k in roundtrip: sm.set_pending("gameplay", k, roundtrip[k])
	sm.apply()
	for k in roundtrip:
		var got = sm.gameplay().get(k, null)
		_ok(got == roundtrip[k], "%s persisted as %s" % [k, str(got)])

	# ── 5. SubtitleHud — gates on `subtitles`, sizes from `subtitle_size` ──
	_section("SubtitleHud (autoload)")
	var sh = get_node_or_null("/root/SubtitleHud")
	_ok(sh != null, "SubtitleHud autoload present")
	if sh:
		# Subtitles ON (from round-trip above). Push and check.
		var before : int = sh._container.get_child_count()
		sh.push_line("hello world")
		_ok(sh._container.get_child_count() == before + 1,
			"subtitles=true → push_line adds 1 label")
		var lbl : Label = sh._container.get_child(sh._container.get_child_count() - 1) as Label
		var fs : int = lbl.get_theme_font_size("font_size")
		_ok(fs == 30, "subtitle_size=large → font_size = %d (expected 30)" % fs)
		# Toggle subtitles OFF
		sm.set_pending("gameplay", "subtitles", false); sm.apply()
		var before_off : int = sh._container.get_child_count()
		sh.push_line("should NOT appear")
		_ok(sh._container.get_child_count() == before_off,
			"subtitles=false → push_line is a no-op")

	# ── 6. settings_applied signal actually fires ──────────────────────────
	_section("settings_applied signal")
	var seen := [false]
	var cb := func(): seen[0] = true
	sm.settings_applied.connect(cb)
	sm.set_pending("gameplay", "head_bob", true); sm.apply()
	_ok(seen[0], "settings_applied emitted on apply()")
	sm.settings_applied.disconnect(cb)

	# ── 7. MainWorld autosave reads from SettingsManager ───────────────────
	_section("MainWorld.autosave")
	var mw_packed := load("res://src/scenes/world/MainWorld.tscn") as PackedScene
	if mw_packed == null:
		print("  skip : MainWorld.tscn could not be loaded")
		return _finish()
	sm.set_pending("gameplay", "autosave_interval_s", 17); sm.apply()
	# Pre-configure WorldLayout so MainWorld skips the in-world "press ENTER"
	# setup overlay and runs _setup_autosave (which is gated by _spawn_world_items).
	var wl = get_node_or_null("/root/WorldLayout")
	if wl:
		wl.player_spawn = Vector3(0, 1, 0)   # any non-zero → is_configured() returns true
	var world := mw_packed.instantiate()
	get_tree().root.add_child.call_deferred(world)
	# Give MainWorld plenty of frames for its full _ready cascade.
	for i in range(20):
		await get_tree().process_frame
	var timer := world.get_node_or_null("AutosaveTimer") as Timer
	if timer == null:
		_ok(false, "AutosaveTimer node not found under MainWorld")
	else:
		_ok(abs(timer.wait_time - 17.0) < 0.01,
			"autosave_interval_s=17 → AutosaveTimer.wait_time = %.1f s" % timer.wait_time)
		sm.set_pending("gameplay", "autosave_interval_s", 0); sm.apply()
		await get_tree().process_frame
		_ok(timer.is_stopped(),
			"autosave_interval_s=0 → AutosaveTimer.is_stopped() == %s" % str(timer.is_stopped()))

	# ── 8. PlayerController head_bob picked up from settings ───────────────
	_section("PlayerController.head_bob")
	var player := world.get_node_or_null("Player") if world else null
	if player == null:
		print("  skip : Player node not present (MainWorld setup mode?)")
	else:
		sm.set_pending("gameplay", "head_bob", false); sm.apply()
		await get_tree().process_frame
		_ok("_head_bob" in player, "PlayerController has _head_bob member")
		if "_head_bob" in player:
			_ok(player._head_bob == false, "head_bob=false → _head_bob = %s" % str(player._head_bob))
			sm.set_pending("gameplay", "head_bob", true); sm.apply()
			await get_tree().process_frame
			_ok(player._head_bob == true, "head_bob=true → _head_bob = %s" % str(player._head_bob))

	# ── 9. HUD opacity / interaction-prompt gate / tutorial hint / units ───
	_section("HUD.hud_opacity / show_interaction_prompts / tutorial_hints / units")
	var hud = get_tree().root.find_child("HUD", true, false)
	if hud == null:
		print("  skip : HUD not in tree")
	else:
		sm.set_pending("gameplay", "hud_opacity", 0.4)
		sm.set_pending("gameplay", "tutorial_hints", true)
		sm.set_pending("gameplay", "units", "imperial"); sm.apply()
		await get_tree().process_frame
		var any_match := false
		for c in hud.get_children():
			if c is Control and abs(c.modulate.a - 0.4) < 0.01:
				any_match = true; break
		_ok(any_match, "hud_opacity=0.4 → at least one HUD Control has modulate.a ≈ 0.4")
		var hint = hud.get_node_or_null("TutorialHint") as Label
		_ok(hint != null and hint.visible, "tutorial_hints=true → TutorialHint visible")
		if hint:
			_ok("ft" in hint.text, "units=imperial → hint text contains 'ft' (got: %s)" % hint.text)
		sm.set_pending("gameplay", "tutorial_hints", false); sm.apply()
		await get_tree().process_frame
		hint = hud.get_node_or_null("TutorialHint") as Label
		_ok(hint == null or not hint.visible, "tutorial_hints=false → TutorialHint hidden")

	# ── 10. set_pending and set_pending_keybind API ────────────────────────
	_section("set_pending API")
	sm.set_pending("graphics", "test_graphics_key", "gfx_val")
	sm.set_pending("audio", "test_audio_key", 42.5)
	sm.set_pending("gameplay", "test_gameplay_key", true)

	var mock_event := InputEventKey.new()
	mock_event.keycode = KEY_Y
	sm.set_pending_keybind("test_action", [mock_event])

	var p_gfx = sm.pending_graphics()
	_ok(p_gfx.get("test_graphics_key") == "gfx_val", "set_pending(graphics) → pending_graphics has key")

	var p_aud = sm.pending_audio()
	_ok(p_aud.get("test_audio_key") == 42.5, "set_pending(audio) → pending_audio has key")

	var p_gp = sm.pending_gameplay()
	_ok(p_gp.get("test_gameplay_key") == true, "set_pending(gameplay) → pending_gameplay has key")

	var p_kb = sm.pending_keybinds()
	var events : Array = p_kb.get("test_action", [])
	_ok(events.size() == 1 and events[0] is InputEventKey and events[0].keycode == KEY_Y, "set_pending_keybind() → pending_keybinds has event")

	_finish()

func _finish() -> void:
	print("\n=========================================")
	print("Result: %d ok, %d fail" % [_pass, _fail])
	print("=========================================")
	get_tree().quit(0 if _fail == 0 else 1)
