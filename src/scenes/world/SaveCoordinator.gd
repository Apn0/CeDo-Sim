extends Node3D

class_name SaveCoordinator

# =============================================================================
# #195 — Save / autosave coordinator extracted from MainWorld.gd.
# =============================================================================
# Owns save_game / save_and_quit / autosave-timer wiring. MainWorld instantiates
# one of these as a child node and calls setup(world, player, game_state,
# shift_clock, crew_manager) exactly once during world setup; the module then
# manages the autosave timer and exposes save_game() / save_and_quit() that
# MainWorld's forwarders delegate to.
#
# Mirrors ExteriorManager.gd's pattern: keeps a _world ref to MainWorld so the
# canonical helpers (_freecam_rig() in particular) stay where they live, and
# spawns the AutosaveTimer under _world.add_child so the scene-tree shape is
# preserved exactly.

# Reference back to MainWorld for _freecam_rig + spawned-node parenting.
var _world : Node = null

# Cached references handed in via setup().
var _player        : CharacterBody3D = null
var _game_state    : Node = null
var _shift_clock   : Node = null
var _crew_manager  : Node = null

func _ready() -> void:
	_world = get_parent()

# ── Public entry point ──────────────────────────────────────────────────────
func setup(world: Node, player: CharacterBody3D, game_state: Node,
		shift_clock: Node, crew_manager: Node) -> void:
	_world        = world
	_player       = player
	_game_state   = game_state
	_shift_clock  = shift_clock
	_crew_manager = crew_manager
	_setup_autosave()

# =============================================================================
# SAVE / QUIT
# =============================================================================
func save_game() -> void:
	if _player and _game_state:
		var ps := {
			"x":     _player.global_position.x,
			"y":     _player.global_position.y,
			"z":     _player.global_position.z,
			"rot_y": _player.rotation.y,
			# X4/#183 — snapshot the world anchor at save time so the loader can
			# tell "save is still in the same world" (trust position) from "world
			# was re-anchored" (must fall back to the spawn marker). The old
			# fixed 100 m guard rejected legit far-from-spawn saves (the
			# residential-vs-industrial-terrain bug).
			"anchor_x": WorldLayout.player_spawn.x,
			"anchor_z": WorldLayout.player_spawn.z,
		}
		# Persist the 3rd-person free-cam pose alongside the player position so the
		# operator's preferred external viewpoint survives a save/load (#freecam).
		var rig : Node = null
		if _world != null and _world.has_method("_freecam_rig"):
			rig = _world.call("_freecam_rig")
		if rig != null and rig.has_method("serialize_freecam"):
			ps["freecam"] = rig.call("serialize_freecam")
		_game_state.save_player_state(ps)
	if _shift_clock:
		_shift_clock.save_shift_state()
	# #124 — flush crew pins (HIER + station/role) so they survive save/load.
	if _crew_manager and _game_state and _crew_manager.has_method("save_pins_dict"):
		_game_state.crew_pins_data = _crew_manager.save_pins_dict()
	if _game_state:
		_game_state.save_game()
	# Defensive flush of the per-save factory layout (placed machines + grating
	# platforms + signs). BuildMode normally writes on every place/edit, but if a
	# K-bake / jog / rotate left dirty state in memory and the user save+quits,
	# those edits would never reach disk. Mirror the save here so the layout
	# round-trips exactly what the player sees.
	var bm = _world.get_node_or_null("BuildMode") if _world else null
	if bm != null and bm.has_method("_save_layout"):
		bm._save_layout()
	print("[SaveCoordinator] Game saved")
	# Surface the save on the HUD ("✓ Saved" toast). Before this the only trace
	# of a save was the console print above — invisible during a shift.
	var bus := get_node_or_null("/root/EventBus")
	if bus and bus.has_signal("autosave_completed"):
		bus.emit_signal("autosave_completed")

func save_and_quit() -> void:
	save_game()
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

# =============================================================================
# Q2 (2026-09-23) — CHECKPOINT: a stamped copy of the live slot the operator
# can reload from the main menu after a risky action (a BuildMode edit, a wire
# cut), without quitting. The 60 s autosave and the pause-card Save both
# OVERWRITE the one slot; before this there was no way to keep a known-good
# point.
# =============================================================================
## Saves the live slot first (so the copy is exactly what the operator sees),
## then copies `<stem>_save.json` and, if present, `<stem>_factory.json` to
## `<stem>_cp_<YYYYMMDD-HHMMSS>_save.json` / `_factory.json`. The main menu
## lists every `*_save.json`, so a checkpoint appears there as its own
## loadable save with its own `saved_at`. Same-second stamps get a `-2`,
## `-3` … suffix instead of overwriting. Returns the checkpoint stem, or "" when
## nothing could be written — the live slot is never touched by a failure.
func save_checkpoint() -> String:
	if _game_state == null or not ("save_file_path" in _game_state):
		push_warning("[SaveCoordinator] checkpoint: no GameState — nothing written")
		return ""
	save_game()
	var live_path : String = String(_game_state.save_file_path)
	var base : String = live_path.get_base_dir()
	var stem : String = live_path.get_file().trim_suffix("_save.json").trim_suffix(".json")
	if stem == "" or not AtomicFile.exists_any(live_path):
		push_warning("[SaveCoordinator] checkpoint: live save '%s' missing — nothing written" % live_path)
		return ""
	var t := Time.get_datetime_dict_from_system()
	var stamp := "%04d%02d%02d-%02d%02d%02d" % [int(t.year), int(t.month), int(t.day),
		int(t.hour), int(t.minute), int(t.second)]
	var cp_stem := "%s_cp_%s" % [stem, stamp]
	var n := 1
	while AtomicFile.exists_any(base.path_join(cp_stem + "_save.json")):
		n += 1
		cp_stem = "%s_cp_%s-%d" % [stem, stamp, n]
	var save_text : String = AtomicFile.read_text(live_path)
	if save_text == "":
		push_warning("[SaveCoordinator] checkpoint: live save read back empty — nothing written")
		return ""
	var cp_save := base.path_join(cp_stem + "_save.json")
	var err := AtomicFile.write_text(cp_save, save_text)
	if err != OK:
		push_error("[SaveCoordinator] checkpoint: could not write %s (error %d)" % [cp_save, err])
		return ""
	var factory_path := base.path_join(stem + "_factory.json")
	if AtomicFile.exists_any(factory_path):
		var factory_text : String = AtomicFile.read_text(factory_path)
		if factory_text != "":
			var ferr := AtomicFile.write_text(base.path_join(cp_stem + "_factory.json"), factory_text)
			if ferr != OK:
				push_error("[SaveCoordinator] checkpoint: save copied but the factory layout was not (error %d) — %s will load with the layout it finds" % [ferr, cp_stem])
	print("[SaveCoordinator] Checkpoint written: %s" % cp_stem)
	return cp_stem

# =============================================================================
# AUTOSAVE (every 60 s of real play time)
# =============================================================================
func _setup_autosave() -> void:
	var timer := Timer.new()
	timer.name       = "AutosaveTimer"
	timer.one_shot   = false
	timer.timeout.connect(_on_autosave)
	# Parent the timer under MainWorld so the existing scene-tree shape (and the
	# /AutosaveTimer lookup in _apply_autosave_interval below) is preserved.
	if _world != null:
		_world.add_child(timer)
	else:
		add_child(timer)
	_apply_autosave_interval()   # set wait_time / start / stop based on setting
	# React to live edits in the Settings menu.
	if has_node("/root/SettingsManager"):
		var sm := get_node("/root/SettingsManager")
		if sm.has_signal("settings_applied"):
			sm.settings_applied.connect(_apply_autosave_interval)

## Reads Settings → Gameplay → "Auto-save interval". 0 disables autosave.
func _apply_autosave_interval() -> void:
	var t : Timer = null
	if _world != null:
		t = _world.get_node_or_null("AutosaveTimer") as Timer
	if t == null:
		t = get_node_or_null("AutosaveTimer") as Timer
	if t == null: return
	var iv : float = 60.0
	if has_node("/root/SettingsManager"):
		iv = float(SettingsManager.gameplay().get("autosave_interval_s", 60))
	if iv <= 0.0:
		t.stop()
		print("[SaveCoordinator] Autosave disabled (interval 0)")
		return
	t.wait_time = iv
	if t.is_stopped(): t.start()
	print("[SaveCoordinator] Autosave interval set to %.0fs" % iv)

func _on_autosave() -> void:
	save_game()
	print("[SaveCoordinator] Autosave")
