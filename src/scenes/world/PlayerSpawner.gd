extends Node3D

class_name PlayerSpawner

# =============================================================================
# #195 extraction — Player spawn + footwear swap + freecam state restore.
# =============================================================================
# Owns the player CharacterBody3D construction (saved-position vs. spawn-marker
# resolution, capsule + camera + Humanoid body assembly, render-layer split,
# shift-bell footwear/wardrobe swap, free-cam pose restore).
#
# Mirrors ExteriorManager.gd's pattern: keeps a _world ref to MainWorld so the
# canonical helpers (_shell / _player_spawn_node / _floor_top_y /
# _building_center_and_footprint / _set_body_render_layer_split) stay where
# they live, and spawns the player under _world.add_child so the scene-tree
# shape is preserved exactly.

# Reference back to MainWorld for canonical helpers + spawned-node parenting.
# Set when the manager is added to the tree (its parent IS MainWorld). The
# setup() call below also assigns it explicitly so callers can wire it
# pre-_ready if they choose.
var _world : Node = null

func _ready() -> void:
	# Give ourselves a stable node name so MainWorld can find_child() us when
	# its save_game() needs to resolve the freecam rig forwarder. Without this
	# the auto-name is just "@Node3D@123" and the lookup fails.
	if name == "" or name.begins_with("@"):
		name = "PlayerSpawner"
	if _world == null:
		_world = get_parent()

# ── Public entry point ──────────────────────────────────────────────────────
func setup(world: Node) -> void:
	_world = world
	if name == "" or name.begins_with("@"):
		name = "PlayerSpawner"

func spawn() -> CharacterBody3D:
	return _spawn_player()

# ── Spawn implementation ────────────────────────────────────────────────────
func _spawn_player() -> CharacterBody3D:
	## Tries saved position first; falls back to the PlayerSpawn marker.
	## Saved position is the actual capsule centre (no +1.0 lift needed on load).

	var game_state = _world.game_state
	var shift_clock = _world.shift_clock

	var spawn_pos  : Vector3 = Vector3.ZERO
	var spawn_rot_y: float   = 0.0
	var from_save  : bool    = false

	if game_state:
		var saved = game_state.load_player_state()
		if saved.has("x"):
			var sp := Vector3(saved["x"], saved["y"], saved["z"])
			# X4/#183 — only reject the saved position if the WORLD ANCHOR moved
			# (the operator re-ran WorldSetup and re-placed player_spawn). When
			# the anchor matches, trust the saved coords regardless of distance
			# — the operator may have walked far across the industrial terrain
			# before save. Old guard rejected legitimate 500 m saves and bounced
			# everyone back to spawn.
			var anchor_moved : bool = false
			if saved.has("anchor_x") and saved.has("anchor_z"):
				var ax : float = float(saved["anchor_x"])
				var az : float = float(saved["anchor_z"])
				var d_anchor : float = Vector2(
					ax - WorldLayout.player_spawn.x,
					az - WorldLayout.player_spawn.z).length()
				anchor_moved = d_anchor > 5.0   # 5 m slop for operator nudges
			else:
				# Legacy save with no anchor snapshot — fall back to the old
				# generous-but-not-absurd guard so RD-coord saves still get
				# rejected but routine 500 m walks don't.
				var d_marker : float = Vector2(sp.x - WorldLayout.player_spawn.x,
					sp.z - WorldLayout.player_spawn.z).length()
				anchor_moved = d_marker > 2000.0
			if anchor_moved:
				print("[PlayerSpawner] World re-anchored since save — using spawn marker (was at %.0f,%.0f)"
					% [sp.x, sp.z])
			else:
				spawn_pos   = sp
				spawn_rot_y = saved.get("rot_y", 0.0)
				from_save   = true

	# #200 — Compute the building anchor in BOTH paths (fresh AND resumed).
	# Previously this only ran in the `not from_save` branch and the resumed
	# branch let _player_spawn_pos pick up the player's saved position — so
	# road/fence/yard placement followed the player wherever they walked,
	# and on save+quit+reload the whole plant respawned beside them.
	var floor_top : float = _world.call("_floor_top_y")
	var bldg_info : Dictionary = _world.call("_building_center_and_footprint")
	var bldg_center : Vector3 = bldg_info.get("center", Vector3.ZERO)
	var bldg_fp : PackedVector2Array = bldg_info.get("footprint", PackedVector2Array())
	var anchor_candidate : Vector3
	if WorldLayout.player_spawn != Vector3.ZERO:
		anchor_candidate = Vector3(WorldLayout.player_spawn.x, floor_top + 1.0,
			WorldLayout.player_spawn.z)
	else:
		var marker : Node3D = _world.call("_player_spawn_node")
		if marker:
			anchor_candidate = Vector3(marker.global_position.x, floor_top + 1.0,
				marker.global_position.z)
		else:
			anchor_candidate = Vector3(0.0, floor_top + 1.0, 0.0)
	# X1/#180 building-footprint snap: if the candidate anchor is outside the
	# building footprint AND >50 m from the centre, snap to the centre.
	var plant_anchor : Vector3 = anchor_candidate
	if bldg_fp.size() >= 3:
		var c2 := Vector2(anchor_candidate.x, anchor_candidate.z)
		if not Geometry2D.is_point_in_polygon(c2, bldg_fp):
			var d : float = c2.distance_to(Vector2(bldg_center.x, bldg_center.z))
			if d > 50.0:
				plant_anchor = Vector3(bldg_center.x, floor_top + 1.0, bldg_center.z)
				print("[PlayerSpawner] #200 — plant anchor candidate (%.0f,%.0f) was outside the building footprint (%.0f m from centre); snapped to centre (%.0f,%.0f)"
					% [anchor_candidate.x, anchor_candidate.z,
						anchor_candidate.distance_to(bldg_center),
						bldg_center.x, bldg_center.z])

	if not from_save:
		# Marker XZ is meaningful (where the operator's feet should land);
		# marker Y is NOT — WorldSetup places markers on a y=0 click plane
		# regardless of where the actual floor is. Use the resolved plant
		# anchor with the detected floor Y.
		spawn_pos = plant_anchor

	var script := load("res://src/scenes/player/PlayerController.gd")
	if not script:
		push_error("[PlayerSpawner] PlayerController.gd not found")
		return null

	var player : CharacterBody3D = CharacterBody3D.new()
	# #186 — Node name stays "Player" because dozens of systems (Gate.gd,
	# Door.gd, BatteryStation.gd, vehicle enter-areas, ExtruderMachine etc.)
	# look up the player by that exact string. The DISPLAY name (real operator
	# name like "Arno") lives on a meta key so any UI that wants to show it
	# reads from one place.
	player.name = "Player"
	var _display_name : String = "Arno"
	if game_state and "player_name" in game_state:
		var _pn = game_state.get("player_name")
		if _pn is String and String(_pn) != "":
			_display_name = String(_pn)
	player.set_meta("display_name", _display_name)
	player.set_script(script)

	var head := Node3D.new()
	head.name     = "Head"
	head.position = Vector3(0.0, 0.7, 0.0)   # eye level above capsule centre
	player.add_child(head)

	var camera := Camera3D.new()
	camera.name = "Camera3D"
	camera.current = true   # explicitly own the viewport so vehicle CabCameras
							# added later don't accidentally win the fallback.
	# #200 — Render layers:
	#   layer 1 = world (default for everything)
	#   layer 2 = player body (neck + shoulders + arms + torso + legs)
	#   layer 3 = player head (head, ears, eyes, nose, mouth, hair, cap)
	# The FIRST-PERSON camera keeps layer 2 (so when the operator looks down
	# they see their own torso/legs/arms — they have a visible body) and
	# drops ONLY layer 3, hiding the head that would otherwise poke up into
	# the FOV. The wardrobe mirror (#153) and any third-person camera see
	# both layers and render the whole body + head.
	camera.cull_mask &= ~(1 << 2)   # drop layer 3 (head only)
	head.add_child(camera)

	var col := CollisionShape3D.new()
	col.name = "Collision"          # PlayerController resizes this for crouch/prone
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.8
	col.shape  = cap
	player.add_child(col)

	# #152 / #186 — Visible Humanoid body. The customizer now saves TWO outfits
	# per character (on_duty + off_duty); MainWorld picks the active one based
	# on ShiftClock.shift_active so PPE shows up at the bell and personal
	# clothes show up off-shift. Legacy saves with only the flat
	# `player_appearance` dict still work — used as the off_duty fallback.
	var _on_shift_init : bool = shift_clock != null and bool(shift_clock.get("shift_active"))
	var _wear_state_init : String = "on_duty" if _on_shift_init else "off_duty"
	var appearance : Dictionary = {}
	if game_state:
		var pw = game_state.get("player_wardrobes") if "player_wardrobes" in game_state else null
		if pw is Dictionary:
			var entry = pw.get(_display_name, {})
			if entry is Dictionary:
				appearance = (entry.get(_wear_state_init, entry.get("on_duty", {})) as Dictionary).duplicate(true)
		if appearance.is_empty():
			appearance = (game_state.player_appearance as Dictionary).duplicate(true)
	appearance["wear_state"] = _wear_state_init
	var shirt : Color = Color(0.95, 0.92, 0.10)   # hi-vis YELLOW default (operator spec)
	if appearance.has("shirt_color"):
		var sc = appearance["shirt_color"]
		if sc is Color: shirt = sc
		elif sc is Dictionary and sc.has("r"):
			shirt = Color(float(sc["r"]), float(sc["g"]), float(sc["b"]))
	var humanoid_script = load("res://src/scenes/world/Humanoid.gd")
	if humanoid_script:
		# T8 — auto-switch player footwear by shift state. Same rule survives
		# the wardrobe upgrade: PPE is now wear-state-driven, but footwear stays
		# explicit so an operator who hasn't dialed in their off-duty look still
		# walks in wearing shoes.
		appearance["footwear"] = "work_boots" if _on_shift_init else "shoes"
		var body : Node3D = humanoid_script.build(shirt, 0, appearance)
		body.name = "PlayerBody"
		# #200 — Split-tag: body parts (neck + shoulders + arms + torso + legs)
		# go on layer 2 (visible to the FP camera so the operator can look down
		# and see themselves); head parts (head, ears, eyes, hair, cap) go on
		# layer 3 (hidden from the FP camera only — it would otherwise poke
		# up into the FOV). Wardrobe mirror & third-person cams see both.
		# add_child FIRST so the recursive ancestor-walk in _set_body_render_layer_split
		# can find "PlayerBody" as the root sentinel.
		player.add_child(body)
		# Physical body mass from the build sliders (50-150 kg range). One law
		# for every human — see Humanoid.body_mass_kg. Wardrobe live-edits call
		# the same helper when they re-apply appearance.
		if "mass_kg" in player:
			player.set("mass_kg", humanoid_script.body_mass_kg(appearance))
		# #205 — Humanoid.build() actually authors the rig with the visible face
		# on local -Z (see Humanoid.gd:419 inside the head-build block:
		# "VISUAL FRONT RULE — visible front MUST sit on local -Z to match the
		# canonical convention"). The stale docstring at Humanoid.gd:213-222
		# was telling callers to flip by PI, which made the operator see the
		# BACK of their own head in the wardrobe mirror + any third-party view.
		# No body rotation needed: face-on-(-Z) already aligns with PlayerController's
		# -basis.z forward.
		_world.call("_set_body_render_layer_split", body)
		# Auto-switch when the shift bell rings (or ends). Stored on the player
		# so a later customizer reload reads the freshly-applied value.
		player.set_meta("appearance", appearance)
		if shift_clock != null:
			if shift_clock.has_signal("shift_started"):
				shift_clock.shift_started.connect(_player_apply_footwear.bind(player, true))
			if shift_clock.has_signal("shift_ended"):
				shift_clock.shift_ended.connect(_player_apply_footwear.bind(player, false))

	_world.add_child(player)
	player.global_position = spawn_pos
	if from_save:
		player.rotation.y = spawn_rot_y

	# #200 — _player_spawn_pos is the PLANT ANCHOR, not the player's current
	# position. On a resumed save the player may be a kilometre east of the
	# plant; the road / fences / parking lot / bale yards must still anchor
	# to the BUILDING, not to wherever the player wandered to. The old code
	# set this to player.global_position which dragged the entire plant
	# infrastructure with the player on every save+quit+reload.
	_world._player_spawn_pos = plant_anchor

	print("[PlayerSpawner] Player spawned at %s%s" \
		% [player.global_position, " (resumed)" if from_save else ""])
	# Restore the saved free-cam pose if there is one. Defer one frame so PlayerController._ready
	# has built its CameraRig before we hand it the saved state. (#freecam)
	if from_save and game_state:
		var saved_player = game_state.load_player_state()
		var fc = saved_player.get("freecam", null)
		if fc != null:
			# Cache on the world so the existing serializer / call site stays valid,
			# and defer the restore one frame so PlayerController._ready has built
			# its CameraRig before we hand it the saved state.
			call_deferred("_restore_freecam_state", fc)

	return player

# ── Footwear / wardrobe swap on shift bell ──────────────────────────────────
## T8 — Toggle the player's footwear when the shift starts / ends. Rebuilds the
## visible Humanoid under the player capsule using the cached appearance dict
## with the new footwear value. The customizer's other choices (shirt, hair,
## beard, cap) are preserved because we mutate the same dict.
func _player_apply_footwear(player_node: Node, on_shift: bool) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	# #186 — Swap the WHOLE outfit slot at the shift bell, not just footwear.
	# When the player has a wardrobe with both wear_states defined, this picks
	# up their off_duty clothes when the bell rings off and their on_duty PPE
	# when it rings on. Legacy single-dict saves fall back to the old behaviour
	# (just toggle footwear) so the prior contract still holds.
	var gs = _world.get_node_or_null("/root/GameState")
	var display_name : String = String(player_node.get_meta("display_name", "Arno"))
	var appearance : Dictionary = player_node.get_meta("appearance", {})
	var picked_from_wardrobe : bool = false
	if gs and "player_wardrobes" in gs:
		var pw = gs.get("player_wardrobes")
		if pw is Dictionary and pw.has(display_name):
			var entry = pw[display_name]
			var ws := "on_duty" if on_shift else "off_duty"
			if entry is Dictionary and entry.has(ws):
				appearance = (entry[ws] as Dictionary).duplicate(true)
				picked_from_wardrobe = true
	appearance["wear_state"] = "on_duty" if on_shift else "off_duty"
	appearance["footwear"] = "work_boots" if on_shift else "shoes"
	player_node.set_meta("appearance", appearance)
	# Humanoid.rebuild_appearance swaps the body subtree without re-spawning the
	# capsule, so the player's position / camera / inputs are untouched.
	var humanoid_script = load("res://src/scenes/world/Humanoid.gd")
	if humanoid_script == null or not humanoid_script.has_method("rebuild_appearance"):
		return
	var shirt : Color = Color(0.95, 0.92, 0.10) if on_shift else Color(0.40, 0.45, 0.55)
	if appearance.has("shirt_color"):
		var sc = appearance["shirt_color"]
		if sc is Color: shirt = sc
		elif sc is Dictionary and sc.has("r"):
			shirt = Color(float(sc["r"]), float(sc["g"]), float(sc["b"]))
	humanoid_script.rebuild_appearance(player_node, shirt, 0, appearance)
	if picked_from_wardrobe:
		# Best-effort log so a verification run can confirm the swap landed.
		print("[PlayerSpawner] Player outfit swapped to %s (wardrobe slot)" % ("on_duty" if on_shift else "off_duty"))
	# Re-tag freshly-built MeshInstances onto the body / head render layers
	# (#200 — body visible to FP cam, head hidden from FP only).
	var body : Node = player_node.find_child("PlayerBody", true, false)
	if body != null:
		_world.call("_set_body_render_layer_split", body)

# ── Free-cam rig lookup + restore ───────────────────────────────────────────
## Walk to the player's CameraRig (built lazily by PlayerController._ready).
func _freecam_rig() -> Node:
	var player = _world.player
	if player == null:
		return null
	return player.find_child("CameraRig", true, false)

func _restore_freecam_state(d: Dictionary) -> void:
	var rig := _freecam_rig()
	if rig != null and rig.has_method("load_freecam_state"):
		rig.call("load_freecam_state", d)
