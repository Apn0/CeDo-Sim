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

func save_and_quit() -> void:
	save_game()
	get_tree().change_scene_to_file("res://src/scenes/menus/main_menu/MainMenu.tscn")

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
