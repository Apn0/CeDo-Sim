extends CharacterBody3D

class_name PlayerController

## First-person walking controller.
## Horizontal look rotates the player body (yaw).
## Vertical look rotates the Camera3D under Head (pitch, clamped ±90°).
## Movement is relative to the body's facing direction.
##
## ESC / pause is handled by HUD.gd — not here.
## When the mouse cursor is visible (pause menu open) movement is suppressed.

# Physical body mass (kg). Set by PlayerSpawner from the wardrobe's build
# sliders via Humanoid.body_mass_kg() — smallest build 50 kg, default ~88 kg,
# largest 150 kg. Consumed wherever the player exchanges momentum with the
# physics world (RigidBody push impulses, belts, vehicle interactions). A
# CharacterBody3D has no engine-side mass, so this is the single source of
# truth for "how heavy is the operator".
var mass_kg : float = 88.1

# Movement
# #223 audit — realistic operator locomotion (work boots, plant floor). Was
# 5.0 m/s (3.5× real walking). These are the top candidates to feel-tune in the
# gauntlet live-update round if a realistic pace reads as too slow to play.
@export var walk_speed         : float = 2.0    # operator-tuned: brisk-but-realistic (was 5.0 → 1.5 → 2.0)
@export var acceleration       : float = 8.0    # reach full walk in ~1-2 steps
@export var friction           : float = 16.0
@export var jump_speed         : float = 3.68   # DOUBLED apex (operator 2026-07-16): height=v²/2g, so 2× height = 2.6·√2 ≈ 3.68 → apex ~0.69 m
# Sprint (#side-quest from operator): Shift while moving multiplies the walk
# speed. Only fires while STANDING — crouched / prone keep their stance pace.
@export var sprint_multiplier  : float = 2.2    # was 1.7 — 3.3 m/s loaded jog
# Fast-traverse (Alt): 5× speed for cross-yard movement during testing.
# Overrides sprint when both are held.
@export var fast_run_multiplier : float = 5.0

# Walk-speed ramps (anti-snap audit). Two layers:
#  1. DIRECTION ramp — handled by the existing `acceleration` + move_toward in
#     _physics_process. With acceleration=20 m/s² and walk_speed=5, going from
#     standstill to full walk takes 5 / 20 = 0.25 s → snappy FPS feel.
#  2. MULTIPLIER ramp — smooths the speed_mul scalar (walk → sprint, walk →
#     fast-traverse, stance multipliers) with a first-order low-pass so tapping
#     Shift doesn't jerk the camera. tau≈0.12 s yields ~0.5 s for a 5× change
#     to settle within 99% — matches the audit's "walk→sprint over ~0.5 s".
const _SPEED_MUL_TAU_S : float = 0.12
var _speed_mul_smooth : SmoothedRate = null

const GRAVITY: float = 9.8
const STEP_HEIGHT: float = 0.4   # max ledge/curb height the player walks over
const INTERACT_RAY_RANGE: float = 3.75
const LADDER_CLIMB_SPEED : float = 0.5  # m/s vertical (#223: was 2.5, ~5× real caged-ladder pace)

# Incremented by each overlapping LadderZone Area3D; 0 = normal movement.
# Using a count (not bool) handles nested/adjacent ladders correctly.
var _on_ladder_count : int = 0

# ── Vault / climb (#cluster VAULT_CLIMB) ──────────────────────────────────────
# When the player presses Space while walking forward (W) into a chest-height
# obstacle that has clear headroom above it, mantle up onto it instead of
# bouncing a useless vertical jump off the wall face. Three forward raycasts
# under Head detect "can I vault this?" each tick:
#   _ray_player_waist (~0.9 m above feet, 0.9 m forward) — must HIT (there is a low obstacle)
#   _ray_player_chest (~1.4 m above feet, 0.9 m forward) — must HIT (obstacle reaches chest)
#   _ray_player_head  (~1.7 m above feet, 0.9 m forward) — must MISS (headroom clear over top)
# Plus the player must be (a) on the floor, (b) standing, (c) pressing W (wish_dir
# aimed along -basis.z), (d) jumping NOW (action just_pressed). All five must
# match — otherwise the jump branch falls through to the normal vertical impulse.
const CLIMB_MAX_HEIGHT      : float = 1.4   # ceiling on ledges we can mantle over (~chest)
const CLIMB_DURATION        : float = 2.0   # #223: was 0.5 — mantling a chest-high ledge is a 2 s effort, not a vault
const CLIMB_FORWARD_DIST    : float = 1.2   # how far forward we land on top of the ledge
const CLIMB_FORWARD_RAY_LEN : float = 0.9
enum VaultState { NONE, CLIMBING }
var _vault_state    : int     = VaultState.NONE
var _vault_timer    : float   = 0.0
var _vault_start    : Vector3 = Vector3.ZERO
var _vault_end      : Vector3 = Vector3.ZERO
var _ray_player_waist : RayCast3D = null
var _ray_player_chest : RayCast3D = null
var _ray_player_head  : RayCast3D = null

var _look_interactable: Node = null
var _look_prompt: String = ""

# ── #210d Pelletizer knife replace — hold-E state ─────────────────────────────
# When the camera ray hits a node with placeable_id == "pelletizer_knife" AND
# the active inventory slot carries a SocketWrench7, we surface a "hold E to
# replace" prompt and integrate progress in _physics_process while the player
# keeps E held on the same knife. Released early → cancel. Reaches 1.0 →
# PelletizerKnifeReplace.complete() flips both the model state and the visual.
# Separate from _look_interactable because the knife body deliberately does
# NOT implement crosshair_prompt/crosshair_interact (it'd require touching
# every catalog-built body and stomp the simpler "tap E with wrench" feel).
var _knife_target : Node3D = null   # node currently under the crosshair (knife body)
var _knife_holding : bool = false   # E currently held + hold-E in flight
var _knife_prompt_text : String = "" # last text we pushed to interaction_prompt_show
const _KNIFE_REPLACE := preload("res://src/scenes/interactions/PelletizerKnifeReplace.gd")

# ── TITECH/TOMRA shaft-wrap cut — hold-E state (sibling to knife replace) ─────
# When the camera ray hits a NIR sorter body (placeable_id in
# {nir_sorter, titech_sort, tomra_sort}) AND the active inventory slot carries
# the WireCutter (tool_id == "scissors"), we surface a "hold E to cut wrap"
# prompt and integrate progress in _physics_process while the player keeps E
# held on the same sorter. Released early → cancel. Reaches 1.0 →
# TitechShaftCut.complete() removes CUT_REMOVE_G of fibrous wrap.
# Separate from _look_interactable for the same reason as the knife block —
# the sorter body deliberately does NOT implement crosshair_prompt/interact.
var _shaft_target : Node3D = null   # node currently under the crosshair (NIR sorter body)
var _shaft_holding : bool = false   # E currently held + hold-E in flight
var _shaft_prompt_text : String = "" # last text we pushed to interaction_prompt_show
const _SHAFT_CUT := preload("res://src/scenes/interactions/TitechShaftCut.gd")

# ── #markers — in-world precise point marker tool (F10) ───────────────────────
# F10 no longer fires a single-shot feedback capture; it toggles a live marker
# mode. A cyan preview orb tracks the crosshair raycast; LMB drops a persistent
# amber orb, G cycles snap (off → grid → edge-vertex), H clears them, RMB/F10
# exits and writes every placed point to user://feedback/<stamp>/markers.json
# (+ screenshot) so the exact coordinates the operator meant are readable — a
# multi-point successor to the old capture. See MarkerTool.gd. The tool is
# hosted under the WORLD (not the player) so placed orbs stay fixed in world
# space instead of riding along under the capsule.
const _MARKER_TOOL := preload("res://src/scenes/player/MarkerTool.gd")
var _marker_tool : Node3D = null

@onready var head     : Node3D   = $Head
@onready var camera_3d: Camera3D = $Head/Camera3D

# ── Stance (crouch = Left Ctrl, prone = Z) ────────────────────────────────────
# Each stance sets the capsule height, the eye (Head) height, and a speed factor.
# Toggling — tap to enter, tap the same key again to stand; you can also go
# straight crouch↔prone. Standing back up is blocked if there's no headroom.
enum Stance { STANDING, CROUCHING, PRONE }
var _stance : int = Stance.STANDING

const STANCE_CAPSULE_H := {Stance.STANDING: 1.8, Stance.CROUCHING: 1.0, Stance.PRONE: 0.5}
const STANCE_EYE_Y     := {Stance.STANDING: 0.7, Stance.CROUCHING: 0.1, Stance.PRONE: -0.55}
const STANCE_SPEED_MUL := {Stance.STANDING: 1.0, Stance.CROUCHING: 0.5,  Stance.PRONE: 0.28}
const STANCE_LERP      := 12.0   # how fast capsule/eye morph between stances
@onready var _collision : CollisionShape3D = get_node_or_null("Collision")

# Multi-mode camera rig (1st person / 3rd-person follow / orbit). F4 cycles
# modes; hold-F4 + arrow keys pan, F4 + scroll zooms — see CameraRig.gd.
var _camera_rig : CameraRig = null

# Live settings (refreshed from SettingsManager on _ready + apply signal)
var _mouse_sens_x : float = 0.003
var _mouse_sens_y : float = 0.003
var _invert_y     : bool  = false
var _mouse_smooth : float = 0.2
# Head bob — Settings → Gameplay → "Head bob while walking". A small sinusoidal
# offset added to the head's Y position when the player is walking on the floor.
# The base eye height (STANCE_EYE_Y) is still owned by _update_stance; we add
# the bob on top so crouch/prone interpolation is unaffected.
var _head_bob   : bool  = true
var _bob_phase  : float = 0.0
const BOB_FREQ_HZ  : float = 1.9     # ~1.9 Hz at default speed feels like a brisk walk
const BOB_AMP_M    : float = 0.035   # 3.5 cm peak — visible without being nauseating

# Smoothing buffer
var _smoothed_motion : Vector2 = Vector2.ZERO

# Auto-unstuck: tracks how long the player has been pressing a direction with
# near-zero actual velocity. After WEDGE_THRESHOLD seconds we start nudging the
# capsule perpendicularly until movement resumes.
var _wedge_timer : float = 0.0
const WEDGE_THRESHOLD   : float = 0.5    # s of "trying but stuck" before nudging
const WEDGE_NUDGE       : float = 0.08   # m of sideways nudge per wedged frame

# Fall fail-safe state — last position where is_on_floor() was true.
var _last_floor_pos : Vector3 = Vector3.ZERO
var _has_floor_pos  : bool = false
const FALL_RESCUE_M : float = 25.0   # drop below last floor spot that triggers rescue

## F12 panic button — try to free a stuck player by lifting them straight up.
## If they're STILL inside geometry after a 2 m lift, teleport them to the
## PlayerSpawn marker (or world origin as a last resort).
func _unstuck_me() -> void:
	velocity = Vector3.ZERO
	# In freefall (off the floor and dropping) a 2 m lift is useless — the test
	# always passes in empty air. Go straight back to solid ground.
	if not is_on_floor() and _has_floor_pos and global_position.y < _last_floor_pos.y - 3.0:
		global_position = _last_floor_pos + Vector3.UP * 1.0
		print("[Player] Unstuck: falling — returned to last floor position (%.1f, %.1f, %.1f)" \
			% [global_position.x, global_position.y, global_position.z])
		return
	# First try just lifting up 2 m — clears the player from low collision
	# slabs (door-cut SAT misses, curb edges, etc.) without losing position.
	var lifted := global_transform.translated(Vector3.UP * 2.0)
	if not test_move(lifted, Vector3.ZERO):
		global_position += Vector3.UP * 2.0
		print("[Player] Unstuck: lifted 2 m up to (%.1f, %.1f, %.1f)" % \
			[global_position.x, global_position.y, global_position.z])
		return
	# Lift didn't help — teleport to PlayerSpawn (or world origin)
	var spawn := get_tree().current_scene.find_child("PlayerSpawn", true, false) as Node3D
	if spawn:
		global_position = spawn.global_position + Vector3.UP * 1.0
		print("[Player] Unstuck: teleported to PlayerSpawn at (%.1f, %.1f, %.1f)" % \
			[global_position.x, global_position.y, global_position.z])
	else:
		global_position = Vector3(0.0, 5.0, 0.0)
		print("[Player] Unstuck: PlayerSpawn missing — fell back to world origin")

## Wrappers OperatorContext uses to hand camera ownership over to / back from
## the vehicle the player is currently in. Centralising these here means the
## OperatorContext doesn't have to know about CameraRig directly.
func deactivate_camera() -> void:
	if _camera_rig:
		_camera_rig.deactivate()

func activate_camera() -> void:
	if _camera_rig:
		# Reset to first-person on dismount — orbit/3rd-person was a temporary
		# inspection mode for the vehicle, not how the player walks around.
		_camera_rig.set_mode(CameraRig.Mode.FIRST_PERSON)
		_camera_rig.activate()

func _ready() -> void:
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	floor_snap_length = 0.3   # stick to the ground when stepping down small ledges
	# Godot 4 CharacterBody3D quicksand fix: with the building shell as a concave
	# trimesh collider, the default safe_margin (1 mm) lets the capsule penetrate
	# triangulated floor edges and oscillate between contacts → slow sink ("quicksand").
	# 5 cm gives the solver enough room to resolve multi-contact cleanly. Standard
	# Godot recommendation for trimesh-heavy levels (0.04 – 0.08 m).
	safe_margin = 0.05
	# Inventory autoload anchors itself to this player so it can re-parent picked-
	# up tools under our Head node, and so it knows where to drop them.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		inv.set("player_ref", self)
		_ensure_hotbar_actions()
	# Camera rig — covers 1st person (hands camera_3d the current flag), 3rd
	# person follow (sits up and behind), and orbit (world-space, F4 + arrows).
	_camera_rig = CameraRig.new()
	_camera_rig.name = "CameraRig"
	add_child(_camera_rig)
	_camera_rig.set_first_person_camera(camera_3d)
	# Player owns the viewport at game start (they're on foot until they enter
	# a vehicle). OperatorContext flips this when they board / dismount.
	_camera_rig.activate()
	_refresh_settings()
	_build_flashlight()
	_build_vault_rays()
	# Speed multiplier smoother (anti-snap audit): walk→sprint over ~0.5 s.
	# Start at 1.0 so a player who spawns standing still doesn't ramp from 0.
	_speed_mul_smooth = SmoothedRate.new(1.0, _SPEED_MUL_TAU_S)
	if Engine.has_singleton("SettingsManager") or has_node("/root/SettingsManager"):
		var sm := get_node("/root/SettingsManager")
		if sm.has_signal("settings_applied"):
			sm.settings_applied.connect(_refresh_settings)

func _refresh_settings() -> void:
	if not has_node("/root/SettingsManager"):
		return
	var g: Dictionary = SettingsManager.gameplay()
	_mouse_sens_x = float(g.get("mouse_sensitivity_x", 0.003))
	_mouse_sens_y = float(g.get("mouse_sensitivity_y", 0.003))
	_invert_y     = bool(g.get("invert_mouse_y", false))
	_mouse_smooth = float(g.get("mouse_smoothing", 0.2))
	_head_bob     = bool(g.get("head_bob", true))
	# FOV
	var fov := float(SettingsManager.graphics().get("fov", 75.0))
	if camera_3d:
		camera_3d.fov = fov
	if _camera_rig and _camera_rig._camera:
		_camera_rig._camera.fov = fov

## Called by LadderZone Area3D when the player's body enters a ladder.
func enter_ladder() -> void:
	_on_ladder_count += 1

## Called by LadderZone Area3D when the player's body exits a ladder.
func exit_ladder() -> void:
	_on_ladder_count = maxi(_on_ladder_count - 1, 0)

func _physics_process(delta: float) -> void:
	# Vault/climb override (#cluster VAULT_CLIMB): while the mantle tween is
	# active we own the transform directly — gravity, WASD, jump, step-up and
	# wedge-rescue all step aside until we drop the player on top of the ledge.
	if _vault_state == VaultState.CLIMBING:
		_advance_vault(delta)
		return

	# Ladder climbing: gravity off, W climbs up, S climbs down.
	# Area3D nodes on every _caged_ladder call enter_ladder/exit_ladder to set the count.
	if _on_ladder_count > 0:
		# Space hops off: reset the zone count so gravity resumes (exit_ladder()
		# clamps at 0 when the body later leaves; walking back in re-arms climb
		# mode). Without this + the A/D side-step below, the zone — its box
		# reaches the plant floor at every ladder foot — captured any passer-by
		# with zero horizontal mobility: a softlock.
		if Input.is_action_just_pressed("jump"):
			_on_ladder_count = 0
			velocity.y = jump_speed * 0.6
		else:
			var climb := 0.0
			if Input.is_action_pressed("move_forward"):
				climb = 1.0
			elif Input.is_action_pressed("move_backward"):
				climb = -1.0
			var lateral := Vector3.ZERO
			if Input.is_action_pressed("move_left"):
				lateral -= global_transform.basis.x
			if Input.is_action_pressed("move_right"):
				lateral += global_transform.basis.x
			var target_xz := lateral.normalized() * walk_speed * 0.5
			velocity.x = move_toward(velocity.x, target_xz.x, acceleration * delta)
			velocity.z = move_toward(velocity.z, target_xz.z, acceleration * delta)
			velocity.y = climb * LADDER_CLIMB_SPEED
		move_and_slide()
		_push_rigid_bodies(delta)   # #223: same mass-based push on the ladder path
		_update_animation_blend()
		return

	# Always apply gravity so the capsule rests on the floor.
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	else:
		# Remember the last spot we genuinely stood on — the fall fail-safe
		# teleports back here if we ever drop through a floor hole.
		_last_floor_pos = global_position
		_has_floor_pos = true
	# Fall fail-safe: dropped >FALL_RESCUE_M below the last stood-on spot means
	# we fell through a hole in the world (e.g. walked out a wall opening past
	# the dynamic floor's edge). Teleport back instead of falling forever —
	# mashing F12 mid-air can't help (its 2 m lift always "succeeds" in the void).
	if _has_floor_pos and global_position.y < _last_floor_pos.y - FALL_RESCUE_M:
		velocity = Vector3.ZERO
		global_position = _last_floor_pos + Vector3.UP * 1.0
		print("[Player] Fall rescue: returned to last floor position (%.1f, %.1f, %.1f)" \
			% [global_position.x, global_position.y, global_position.z])

	# Suppress WASD when cursor is visible (pause menu / any UI overlay).
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_clear_crosshair_interaction()
		velocity.x = move_toward(velocity.x, 0.0, friction * delta)
		velocity.z = move_toward(velocity.z, 0.0, friction * delta)
		move_and_slide()
		_push_rigid_bodies(delta)   # #223: mass-based push on the UI-open glide path too
		# Animation Phase 1: keep the rig in idle while UI is open. Velocity
		# already decays via friction above, but resolve + push 0 explicitly
		# so the legs visibly settle even if velocity is still drifting down.
		_update_animation_blend()
		return

	# WASD — relative to body facing direction. CANONICAL Godot convention:
	# forward = -basis.z. The Humanoid model is authored face-on-+Z (see
	# Humanoid.gd:200 docstring); attach sites (MainWorld._spawn_player,
	# GauntletWorld._build_player) apply rotation.y = PI to align the visible
	# face with -basis.z. Do not "fix" an apparent backward-W by flipping signs
	# here — that would re-break A/D and break vehicle attach sites too.
	var wish_dir := Vector3.ZERO
	if Input.is_action_pressed("move_forward"):
		wish_dir -= global_transform.basis.z
	if Input.is_action_pressed("move_backward"):
		wish_dir += global_transform.basis.z
	if Input.is_action_pressed("move_left"):
		wish_dir -= global_transform.basis.x
	if Input.is_action_pressed("move_right"):
		wish_dir += global_transform.basis.x

	wish_dir = wish_dir.normalized()

	# Speed multipliers (only while STANDING — crouched/prone ignore both):
	#   Alt   → fast-traverse 5× (priority over sprint)
	#   Shift → sprint ×1.7
	# Audit anti-snap: the TARGET multiplier is computed from the current input
	# state, then _speed_mul_smooth low-passes it (tau≈0.12 s) so tapping Shift
	# blends walk→sprint over ~0.5 s instead of teleporting the camera. The
	# move_toward layer below still handles the wish_dir direction-change ramp
	# at acceleration=20 m/s² → 0→walk in 0.25 s for snappy FPS feel.
	var target_speed_mul : float = float(STANCE_SPEED_MUL[_stance])
	if _stance == Stance.STANDING:
		if Input.is_action_pressed("fast_run"):
			target_speed_mul *= fast_run_multiplier
		elif Input.is_action_pressed("sprint"):
			target_speed_mul *= sprint_multiplier
	var speed_mul : float = _speed_mul_smooth.approach(target_speed_mul, delta)
	# #223 audit: carried tool weight slows you. A ~40 kg cap (LPG + blower +
	# hose) knocks off up to 40% of speed; empty-handed = full pace.
	if has_node("/root/Inventory"):
		var carried : float = get_node("/root/Inventory").call("total_carried_kg")
		speed_mul *= clampf(1.0 - carried / 40.0 * 0.4, 0.6, 1.0)
	var target_xz := wish_dir * walk_speed * speed_mul
	var accel     := acceleration if wish_dir.length() > 0.0 else friction
	velocity.x = move_toward(velocity.x, target_xz.x, accel * delta)
	velocity.z = move_toward(velocity.z, target_xz.z, accel * delta)

	# Jump — only from the ground AND only while standing (can't hop when crouched).
	# Combo-aware: W (forward wish_dir) + Space against a chest-height obstacle
	# with clear headroom = vault/mantle onto the ledge instead of a vertical hop.
	# Otherwise, the normal jump impulse fires.
	if Input.is_action_just_pressed("jump") and is_on_floor() and _stance == Stance.STANDING:
		if _try_start_vault(wish_dir):
			pass    # vault tween consumes this tick's velocity
		else:
			velocity.y = jump_speed

	_attempt_step_up()
	_attempt_wedge_rescue(wish_dir, delta)
	_update_stance(delta)
	move_and_slide()
	_push_rigid_bodies(delta)
	_apply_belt_carry(delta)
	_update_crosshair_interaction()
	_update_knife_replace_hold(delta)
	_update_shaft_cut_hold(delta)
	# Animation Phase 1: feed the body's BlendSpace2D so 3rd-person/orbit shows
	# a real walk cycle. No-op for first-person (the body's head is on a
	# hidden layer + the FP eye sits between the body's shoulders).
	_update_animation_blend()

# ── #223 audit (critical): mass-based RigidBody push ─────────────────────────
# A CharacterBody3D is kinematic — Godot's solver displaces RigidBodies it walks
# into with INFINITE effective mass, so a 140 kg loaded cart moved exactly like
# an empty one. This helper restores momentum exchange: for every slide contact
# with a free RigidBody, split momentum by the real mass ratio —
#   * the rigid body receives an impulse toward the contact (F=ma over ~tau),
#   * the PLAYER loses the blocked velocity component scaled by (1-ratio), so
#     walking into a heavy machine actually stops you instead of bulldozing it.
# Grabbed carts are skipped (LumpCart's handle controller owns them) and frozen
# bodies are immovable by definition.
const _PUSH_ACCEL_TAU_S : float = 0.5   # time to accelerate the pushed body to your speed

func _push_rigid_bodies(delta: float) -> void:
	KinematicPush.apply(self, mass_kg, _PUSH_ACCEL_TAU_S, delta)

## Belt-carry: if we're standing on a body in group "belt", drag the player along
## the belt's world-space carry velocity. Reads slide collisions from the last
## move_and_slide(); additive, so WASD can still walk against the belt. Applied
## at most once per frame even if several slide collisions report the same belt.
##
## #172 — Operator reported 2× carry speed + wrong direction. Root cause: every
## belt now ships with BeltSurface (#conveyorphysics), which writes
## constant_linear_velocity. In Godot 4 CharacterBody3D's move_and_slide() ALSO
## inherits a moving platform's constant_linear_velocity, so the carry was being
## applied twice. Fix: skip the manual hack for belts that have BeltSurface — let
## Godot's built-in moving-platform inheritance do the work. The fallback path
## stays for legacy belts that only carry the meta `belt_speed`.
func _apply_belt_carry(delta: float) -> void:
	for i in get_slide_collision_count():
		var collider := get_slide_collision(i).get_collider()
		if collider != null and collider.is_in_group("belt"):
			# BeltSurface-equipped belt → Godot inherits its velocity already.
			if collider.get_script() != null and "belt_speed_mps" in collider:
				return
			# Legacy belt fallback — apply the manual drag.
			var v: Vector3
			if collider.has_method("belt_velocity"):
				v = collider.belt_velocity()
			else:
				# CANONICAL CONVENTION: downstream = body LOCAL +Z (see BeltSurface.gd
				# docstring). BeltBuilder builds the discharge chute at local +Z,
				# ShredderFeedBelt builds the deck along local +Z, the shader scrolls
				# texture toward +Z on positive speed, and BuildMode adds rot_y + PI
				# to each macro-placed body so its local +Z matches the world march
				# (downstream). Carry the operator along +basis.z.
				v = collider.global_transform.basis.z.normalized() * float(collider.get_meta("belt_speed", 0.0))
			global_position += v * delta
			return

# ── Stance morph + toggles ────────────────────────────────────────────────────
## Smoothly lerp the capsule height + eye height toward the current stance's
## targets each frame, keeping the capsule's base on the floor as it shrinks/grows.
func _update_stance(delta: float) -> void:
	if _collision == null:
		_collision = get_node_or_null("Collision") as CollisionShape3D
	var t := clampf(STANCE_LERP * delta, 0.0, 1.0)
	# Eye height: stance target + (optional) walk-bob offset on top.
	if head:
		var base_y := float(STANCE_EYE_Y[_stance])
		var bob_y := 0.0
		# Horizontal speed; bob fades to zero when not moving / not on floor / setting off.
		var horiz := Vector2(velocity.x, velocity.z).length()
		if _head_bob and is_on_floor() and horiz > 0.2:
			_bob_phase = fposmod(_bob_phase + delta * BOB_FREQ_HZ * TAU * (horiz / 4.0), TAU)
			bob_y = sin(_bob_phase) * BOB_AMP_M * clampf(horiz / 4.0, 0.3, 1.0)
		else:
			# Decay phase toward 0 when not bobbing so the offset doesn't snap on stop.
			_bob_phase = lerpf(_bob_phase, 0.0, clampf(delta * 8.0, 0.0, 1.0))
		head.position.y = lerpf(head.position.y, base_y + bob_y, t)
	# Capsule height — shrink from the centre, then re-seat so the base stays put.
	var cap := _collision.shape as CapsuleShape3D if _collision else null
	if cap:
		var target_h := float(STANCE_CAPSULE_H[_stance])
		var new_h := lerpf(cap.height, target_h, t)
		cap.height = new_h
		# The standing capsule is centred on the BODY ORIGIN (position.y == 0),
		# so its bottom sits at -STAND_HALF below the origin. To shrink from the
		# TOP DOWN (crouch lowers your head, not your feet) we must keep that
		# bottom fixed: centre = bottom + h/2 = (h/2 - STAND_HALF). Standing
		# (h=1.8) → 0, identical to the spawn capsule; prone (h=0.5) → -0.65, so
		# the body never sinks and the eye never drops through the floor.
		var stand_half := float(STANCE_CAPSULE_H[Stance.STANDING]) * 0.5
		_collision.position.y = new_h * 0.5 - stand_half

## Can the player stand up to `target` stance? Checks headroom with a test capsule
## sweep so they don't pop through a low ceiling (a belt, a mezzanine, a machine).
func _can_change_to(target: int) -> bool:
	if target <= _stance:
		return true   # crouching down / going prone never needs headroom
	var cap := _collision.shape as CapsuleShape3D if _collision else null
	if cap == null:
		return true
	var grow := float(STANCE_CAPSULE_H[target]) - cap.height
	if grow <= 0.0:
		return true
	# Probe straight up by the height we'd gain; if blocked, stay down.
	return not test_move(global_transform, Vector3.UP * (grow + 0.05))

func _toggle_stance(target: int) -> void:
	# Tapping the same stance key again returns to standing (if there's headroom).
	var dest := Stance.STANDING if _stance == target else target
	if _can_change_to(dest):
		_stance = dest

## Auto-unstuck — when the player is pressing a direction but the actual
## horizontal velocity stays near zero, slowly nudge the capsule perpendicular
## to the input direction. Frees the player from tight inside-corner wedges
## (like the OBJ's non-orthogonal wall meets) without needing the F12 panic key.
func _attempt_wedge_rescue(wish_dir: Vector3, delta: float) -> void:
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if wish_dir.length() < 0.01:
		_wedge_timer = 0.0
		return
	if horiz_speed > 0.3:
		_wedge_timer = 0.0
		return
	# Pressing direction + barely moving = wedged. Accumulate time.
	_wedge_timer += delta
	if _wedge_timer < WEDGE_THRESHOLD:
		return
	# Try a small sideways nudge — pick whichever side has clear space.
	var fwd_xz := Vector3(wish_dir.x, 0.0, wish_dir.z).normalized()
	var perp   := Vector3(-fwd_xz.z, 0.0, fwd_xz.x)   # 90° to the right of wish_dir
	var nudge_right := perp * WEDGE_NUDGE
	var nudge_left  := -perp * WEDGE_NUDGE
	if not test_move(global_transform, nudge_right):
		global_position += nudge_right
	elif not test_move(global_transform, nudge_left):
		global_position += nudge_left
	# else: both sides blocked → wedged deep, wait for F12 panic key

# Lets the player walk over small ledges/curbs (floor seams, wall bottoms) that
# a capsule would otherwise jam against. Lifts the body exactly onto a step that
# is no taller than STEP_HEIGHT; leaves real walls (no clearance above) alone.
func _attempt_step_up() -> void:
	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	if horiz.length() < 0.05 or not is_on_floor():
		return
	var step := horiz.normalized() * 0.3
	if not test_move(global_transform, step):
		return                                   # path clear — nothing to climb
	var raised := global_transform.translated(Vector3.UP * STEP_HEIGHT)
	if test_move(raised, step):
		return                                   # still blocked a step up → real wall
	var probe := raised.translated(step)
	var hit := KinematicCollision3D.new()
	if test_move(probe, Vector3.DOWN * STEP_HEIGHT, hit):
		var lift := STEP_HEIGHT - hit.get_travel().length()
		if lift > 0.01:
			# Only commit if the partially-lifted pose is actually clear —
			# seating the capsule into an overlapping collider (stacked door
			# frame / opening edge) lets depenetration shove us through the floor.
			var seated := global_transform.translated(Vector3.UP * lift)
			if not test_move(seated, Vector3.ZERO):
				global_position.y += lift        # set down exactly on the step top

# =============================================================================
# VAULT / CLIMB  (#cluster VAULT_CLIMB)
# =============================================================================
## Add three forward raycasts under Head so we can detect "is there a chest-
## height obstacle in front of me with clear headroom above?". Mounted in code
## (no scene edit required) so any existing scene picks the capability up at
## runtime — mirrors how _build_flashlight registers nodes on-the-fly.
##
## Geometry (Y is measured from the body origin, which sits at the capsule
## centre; the standing capsule is 1.8 m tall, so the floor is at -0.9 and the
## top is at +0.9):
##   waist ~0.9 m above feet (Y = 0.0)  → -Z forward 0.9 m
##   chest ~1.4 m above feet (Y = 0.5)  → -Z forward 0.9 m
##   head  ~1.7 m above feet (Y = 0.8)  → -Z forward 0.9 m
## All three exclude self.
func _build_vault_rays() -> void:
	if _ray_player_waist != null:
		return
	_ray_player_waist = RayCast3D.new()
	_ray_player_waist.name = "RayVaultWaist"
	_ray_player_waist.position = Vector3(0.0, -0.45, 0.0)   # lower so knee/waist-high crates register (vaulting)
	_ray_player_waist.target_position = Vector3(0.0, 0.0, -CLIMB_FORWARD_RAY_LEN)
	_ray_player_waist.collide_with_areas = false
	_ray_player_waist.collide_with_bodies = true
	_ray_player_waist.add_exception(self)
	add_child(_ray_player_waist)

	_ray_player_chest = RayCast3D.new()
	_ray_player_chest.name = "RayVaultChest"
	_ray_player_chest.position = Vector3(0.0, 0.5, 0.0)
	_ray_player_chest.target_position = Vector3(0.0, 0.0, -CLIMB_FORWARD_RAY_LEN)
	_ray_player_chest.collide_with_areas = false
	_ray_player_chest.collide_with_bodies = true
	_ray_player_chest.add_exception(self)
	add_child(_ray_player_chest)

	_ray_player_head = RayCast3D.new()
	_ray_player_head.name = "RayVaultHead"
	_ray_player_head.position = Vector3(0.0, 0.8, 0.0)
	_ray_player_head.target_position = Vector3(0.0, 0.0, -CLIMB_FORWARD_RAY_LEN)
	_ray_player_head.collide_with_areas = false
	_ray_player_head.collide_with_bodies = true
	_ray_player_head.add_exception(self)
	add_child(_ray_player_head)

## Combo gate: W (forward wish_dir) + Space against a low-but-not-too-low
## obstacle = vault. Returns true if the vault was started this frame (and the
## caller should skip the normal jump impulse). Otherwise the caller falls
## through to the regular vertical hop.
##
## Conditions (all must be true):
##   1. wish_dir is non-trivial and points along -basis.z (the player is
##      walking forward, not strafing or stationary)
##   2. waist ray HITS         — there IS a low obstacle 0.9 m ahead
##   3. chest ray HITS         — the obstacle reaches at least chest height
##   4. head ray MISSES        — headroom above the ledge is clear
##   5. landing pose is clear  — test_move at the target stance succeeds
func _try_start_vault(wish_dir: Vector3) -> bool:
	if _ray_player_waist == null or _ray_player_chest == null or _ray_player_head == null:
		return false
	# (1) Combo check: walking forward, not just standing in front of a wall.
	if wish_dir.length() < 0.1:
		return false
	var forward := -global_transform.basis.z
	if wish_dir.dot(forward) < 0.5:
		return false
	# (2) Force a refresh — we just added these rays in _ready, so on the very
	# first physics tick they may not have a valid is_colliding() snapshot yet.
	_ray_player_waist.force_raycast_update()
	_ray_player_chest.force_raycast_update()
	_ray_player_head.force_raycast_update()
	# (3) Obstacle profile (operator 2026-07-16 "allow vaulting"): waist hit + head
	# clear is enough to MANTLE. The old code also required the CHEST ray to hit,
	# so knee/waist-high crates + railings (which the chest ray sails over) never
	# vaulted and fell through to a useless hop. Chest gate dropped.
	if not _ray_player_waist.is_colliding():
		return false
	if _ray_player_head.is_colliding():
		return false
	# (4) Compute the landing pose — lift by CLIMB_MAX_HEIGHT, push forward
	# CLIMB_FORWARD_DIST along the walk direction. Verify it's clear so we
	# don't drop the player into geometry.
	var land_offset := forward.normalized() * CLIMB_FORWARD_DIST + Vector3.UP * CLIMB_MAX_HEIGHT
	var landing := global_transform.translated(land_offset)
	if test_move(landing, Vector3.ZERO):
		return false
	# All clear — start the climb tween.
	_vault_state = VaultState.CLIMBING
	_vault_timer = 0.0
	_vault_start = global_position
	_vault_end   = global_position + land_offset
	velocity = Vector3.ZERO
	return true

## Advance the vault tween. Lerps the capsule from _vault_start → _vault_end
## over CLIMB_DURATION seconds, then releases control back to normal walking.
## Input is implicitly disabled because _physics_process early-returns while
## _vault_state == CLIMBING (gravity, WASD, jump, step-up all skipped).
func _advance_vault(delta: float) -> void:
	_vault_timer += delta
	var t := clampf(_vault_timer / CLIMB_DURATION, 0.0, 1.0)
	# Ease-out so the player decelerates as they set down on top of the ledge.
	var eased := 1.0 - pow(1.0 - t, 2.0)
	global_position = _vault_start.lerp(_vault_end, eased)
	if t >= 1.0:
		_vault_state = VaultState.NONE
		_vault_timer = 0.0
		# Give the body to gravity again with zero velocity; move_and_slide on
		# the next normal physics tick re-seats it on the ledge top.
		velocity = Vector3.ZERO

## Two-corner opening capture — press F11 looking at the bottom-left corner of
## where a door / gate / window should go, press F11 again looking at the top-
## right corner. The crosshair raycasts onto whatever surface you're aiming at;
## the two hit points define a rectangle on a wall plane. The capture prints a
## `--door cx,cz,W,H,BY` spec already in RD coordinates so you can paste it
## straight into `python tools/solidify_building.py --door ...`.
##
## Sanity checks:
##   * Both hits must be on surfaces with similar normals (same wall).
##   * The second hit must lie within OPENING_PLANE_TOL of the first hit's plane.
## If either check fails the pair is discarded and a warning is printed.
const OPENING_RAY_LEN  : float = 30.0   # crosshair raycast range (m)
const OPENING_PLANE_TOL: float = 0.40   # max distance off the first hit's plane
var _opening_p1        : Vector3 = Vector3.INF
var _opening_p1_normal : Vector3 = Vector3.ZERO

## #106 — Player flashlight. Mounted on the camera so its beam follows the
## player's view. Toggle with F. The Input action "flashlight" is registered
## on-the-fly (binds to KEY_F) so the project doesn't need a custom action set.
var _flashlight : SpotLight3D = null

# ── Animation Phase 1 (cluster: Skeleton3D rig + locomotion BlendSpace) ──
# Cached AnimationTree on the player's visible Humanoid rig ("PlayerBody").
# Updated each physics tick with horizontal velocity so the third-person /
# orbit camera shows a real walk cycle instead of a sliding box rig. Null
# until _resolve_anim_tree finds it (the rig is built by MainWorld /
# GauntletWorld AFTER the controller's _ready, so we resolve lazily).
# TODO Phase 2: feed BlendSpace2D Y axis with strafe (wish_dir decomposed
# into local right vs forward). For Phase 1 we keep Y at 0.
var _anim_tree : AnimationTree = null
const _ANIM_RUN_SPEED_PLAYER : float = 10.0   # m/s mapped to BlendSpace X=2

func _build_flashlight() -> void:
	if _flashlight != null:
		return
	_flashlight = SpotLight3D.new()
	_flashlight.name = "Flashlight"
	_flashlight.spot_range = 22.0
	_flashlight.spot_angle = 32.0
	_flashlight.spot_angle_attenuation = 0.85
	_flashlight.light_energy = 4.0
	_flashlight.light_color = Color(1.0, 0.96, 0.86)   # warm white
	_flashlight.visible = false                          # off by default
	camera_3d.add_child(_flashlight)
	# Register the toggle keybind if it isn't already defined.
	if not InputMap.has_action("flashlight"):
		InputMap.add_action("flashlight")
		var ev := InputEventKey.new()
		ev.physical_keycode = KEY_F
		InputMap.action_add_event("flashlight", ev)
	# Register the opening-capture keybind (F11) the same lazy way.
	if not InputMap.has_action("opening_capture"):
		InputMap.add_action("opening_capture")
		var ev_cap := InputEventKey.new()
		ev_cap.physical_keycode = KEY_F11
		InputMap.action_add_event("opening_capture", ev_cap)
	# Register the sprint keybind (Shift) — same lazy pattern as flashlight.
	if not InputMap.has_action("sprint"):
		InputMap.add_action("sprint")
		var ev_sprint := InputEventKey.new()
		ev_sprint.physical_keycode = KEY_SHIFT
		InputMap.action_add_event("sprint", ev_sprint)
	# Register the fast-traverse keybind (Alt) — 5× speed. #223 audit: this is a
	# DEV traverse aid (25 m/s = 90 km/h on foot), not a real ability. Always
	# register the action so is_action_pressed at line 373 stays valid (an
	# unregistered action spams a per-frame InputMap error), but only bind the
	# Alt key in debug builds — shipping players can't accidentally sprint at
	# 90 km/h across the yard.
	if not InputMap.has_action("fast_run"):
		InputMap.add_action("fast_run")
		if OS.is_debug_build():
			var ev_alt := InputEventKey.new()
			ev_alt.physical_keycode = KEY_ALT
			InputMap.action_add_event("fast_run", ev_alt)
	# Debug fault trigger (0 / Numpad-0) — aim at a machine and press to force
	# the nearest MotorOverload to trip (or call .force_trip() / .force_fault()
	# / .trip() on whatever ancestor of the hit collider exposes it). Lets the
	# operator stress-test crew dispatch + cascade behaviour without waiting for
	# a real overload to accumulate.
	if not InputMap.has_action("debug_force_fault"):
		InputMap.add_action("debug_force_fault")
		var ev0 := InputEventKey.new()
		ev0.physical_keycode = KEY_0
		InputMap.action_add_event("debug_force_fault", ev0)
		var evkp0 := InputEventKey.new()
		evkp0.physical_keycode = KEY_KP_0
		InputMap.action_add_event("debug_force_fault", evkp0)
	# Secret debug — Numpad-9: instantly fill the extruder feed silo you're
	# aiming at to 90 %. Lets the operator force-prime an extruder for a
	# startup-test run without waiting for the wash chain to deliver flake.
	if not InputMap.has_action("debug_fill_silo"):
		InputMap.add_action("debug_fill_silo")
		var ev9 := InputEventKey.new()
		ev9.physical_keycode = KEY_KP_9
		InputMap.action_add_event("debug_fill_silo", ev9)
	# F10 — collaborative feedback capture: snapshots the current view +
	# machine-readable context about whatever is under the crosshair into
	# user://feedback/<timestamp>/ so it can be pasted into a chat and acted on.
	if not InputMap.has_action("feedback_capture"):
		InputMap.add_action("feedback_capture")
		var evf10 := InputEventKey.new()
		evf10.physical_keycode = KEY_F10
		InputMap.action_add_event("feedback_capture", evf10)
	# F8 — Inspect Mode toggle (#inspect): free-fly camera + layout-marker
	# gizmos + satellite / floor-plan ground overlays. F8 is free in MainWorld
	# (the SandboxWorld F8 binding is in a different top-level scene that never
	# coexists with this one). Registered lazily so a stale InputMap from a
	# pre-Inspect save still picks the action up.
	if not InputMap.has_action("inspect_mode"):
		InputMap.add_action("inspect_mode")
		var evf8 := InputEventKey.new()
		evf8.physical_keycode = KEY_F8
		InputMap.action_add_event("inspect_mode", evf8)

func _toggle_flashlight() -> void:
	if _flashlight == null:
		return
	_flashlight.visible = not _flashlight.visible

## F11 — capture one corner of an opening (door / gate / window) by raycasting
## from the camera through the crosshair and recording the hit point on
## whatever surface you're aiming at. First press stores the corner; second
## press computes the W×H rectangle the two points define and prints a
## ready-to-paste `--door` spec (in RD coords, the format solidify_building.py
## expects). Mismatched-wall pairs are rejected with a warning so a stray hit
## on a machine doesn't quietly produce a garbage door.
func _capture_opening_corner() -> void:
	if camera_3d == null:
		print("[OpeningCapture] no camera, aborting")
		return
	var from := camera_3d.global_position
	var to   := from - camera_3d.global_transform.basis.z * OPENING_RAY_LEN
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = false
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	# Also exclude any actively-held tool so we don't capture its hitbox.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		var active_tool := inv.call("active") as CollisionObject3D
		if active_tool:
			q.exclude.append(active_tool.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("[OpeningCapture] aim at a wall — no hit within %.0f m" % OPENING_RAY_LEN)
		return
	var pos : Vector3 = hit.position
	var nrm : Vector3 = hit.normal
	# Convert scene-world position to Dutch RD coords by inverting the
	# BuildingShell parent transform (translated by -RD_origin in MainWorld.tscn).
	# That gives the script numbers in the same frame as its --door input.
	var rd := pos - _building_shell_offset()

	# FIRST CORNER of the pair — store and prompt for the second.
	if _opening_p1 == Vector3.INF:
		_opening_p1 = pos
		_opening_p1_normal = nrm
		print("[OpeningCapture] corner 1: scene (%.2f, %.2f, %.2f)  RD (%.2f, %.2f, %.2f)  — aim at corner 2 + F11"
			% [pos.x, pos.y, pos.z, rd.x, rd.y, rd.z])
		return

	# SECOND CORNER — sanity-check, compute, print, reset.
	var p1 := _opening_p1
	var n1 := _opening_p1_normal
	_opening_p1 = Vector3.INF   # reset whether we accept or reject below
	_opening_p1_normal = Vector3.ZERO
	if n1.dot(nrm) < 0.80:
		print("[OpeningCapture] CANCELLED — second hit faces a different wall (normal·normal=%.2f). Start over." % n1.dot(nrm))
		return
	var off := absf((pos - p1).dot(n1))
	if off > OPENING_PLANE_TOL:
		print("[OpeningCapture] CANCELLED — second hit is %.2fm off the first wall plane (tol %.2fm). Start over." % [off, OPENING_PLANE_TOL])
		return
	# Both hits clean. Compute opening rectangle.
	var p2 := pos
	var off1 := _building_shell_offset()
	var p1_rd := p1 - off1
	var p2_rd := p2 - off1
	var cx       := (p1_rd.x + p2_rd.x) * 0.5
	var cz       := (p1_rd.z + p2_rd.z) * 0.5
	var width    := maxf(absf(p2_rd.x - p1_rd.x), absf(p2_rd.z - p1_rd.z))
	var bottom_y := minf(p1_rd.y, p2_rd.y)
	var height   := absf(p2_rd.y - p1_rd.y)
	if width < 0.3 or height < 0.3:
		print("[OpeningCapture] CANCELLED — rectangle is too small (%.2fw × %.2fh). Start over." % [width, height])
		return
	# #122 auto-classify by W/H/bottom_y. Personnel door (≤1.2 m wide AND
	# bottom ~0 m), roller gate (≥2.0 m wide), bay (≥3.0 m wide, low BY),
	# window (BY ≥ 0.8 m), otherwise generic "door". Thresholds picked from
	# the real CeDo doorways the operator measured.
	var kind := "door"
	if bottom_y >= 0.8:
		kind = "window"
	elif width >= 3.0 and bottom_y < 0.5:
		kind = "bay"
	elif width >= 2.0:
		kind = "gate"
	elif width <= 1.2 and bottom_y < 0.5:
		kind = "door"
	print("[OpeningCapture] %s %.2fw × %.2fh  at RD (cx=%.2f, cz=%.2f, bottom_y=%.2f)"
		% [kind, width, height, cx, cz, bottom_y])
	print("                 paste:  --door %.2f,%.2f,%.2f,%.2f,%.2f" % [cx, cz, width, height, bottom_y])
	# #119 — Append to user://captured_doors.json so the operator doesn't have
	# to scrape the console. tools/solidify_building.py can read this file
	# directly when baking the next building shell.
	_append_captured_door({
		"kind":     kind,
		"cx":       cx,
		"cz":       cz,
		"width":    width,
		"height":   height,
		"bottom_y": bottom_y,
		"captured_at": Time.get_unix_time_from_system(),
	})

## #119 — persist a captured door spec to user://captured_doors.json. Reads
## the existing file (if any), appends the new entry, writes back. Print a
## one-liner with the file path so the operator can find it without digging.
func _append_captured_door(entry: Dictionary) -> void:
	const PATH := "user://captured_doors.json"
	var arr : Array = []
	if FileAccess.file_exists(PATH):
		var rf := FileAccess.open(PATH, FileAccess.READ)
		if rf:
			var parsed : Variant = JSON.parse_string(rf.get_as_text())
			rf.close()
			if parsed is Array:
				arr = parsed
	arr.append(entry)
	var wf := FileAccess.open(PATH, FileAccess.WRITE)
	if wf == null:
		print("[OpeningCapture] WARN — could not open %s for writing (%d)" \
			% [PATH, FileAccess.get_open_error()])
		return
	wf.store_string(JSON.stringify(arr, "\t"))
	wf.close()
	print("[OpeningCapture] saved → %s  (%d total entries)" % [PATH, arr.size()])

## Look up BuildingShell.position so the capture can invert its shift back to
## the original RD coordinates the solidify script speaks. Returns ZERO if no
## shell is present (e.g. a test scene), in which case the scene coords ARE
## the RD coords already.
func _building_shell_offset() -> Vector3:
	var shell := get_tree().current_scene.find_child("BuildingShell", true, false) as Node3D
	if shell == null:
		return Vector3.ZERO
	return shell.global_position

func _input(event: InputEvent) -> void:
	# #markers — while the F10 marker tool is active it owns LMB/RMB/G/H, so it
	# must run before ANY gameplay bind (else H would toggle the LPG tank, etc.).
	if _marker_input(event):
		return
	# #106 — flashlight toggle on F. Check first so other keybinds don't swallow it.
	if event.is_action_pressed("flashlight"):
		_toggle_flashlight()
		return
	# F11 — two-press opening-rectangle capture (door/gate/window dimensions).
	if event.is_action_pressed("opening_capture"):
		_capture_opening_corner()
		return
	# Mouse look — only while captured (not paused).
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var rel: Vector2 = (event as InputEventMouseMotion).relative
		# Smoothing: lerp current relative toward target. 0 = instant, 1 = laggy
		_smoothed_motion = _smoothed_motion.lerp(rel, 1.0 - _mouse_smooth)
		var yaw_delta   :=  -_smoothed_motion.x * _mouse_sens_x
		var pitch_delta :=  -_smoothed_motion.y * _mouse_sens_y
		if _invert_y:
			pitch_delta = -pitch_delta
		rotate_y(yaw_delta)
		head.rotate_object_local(Vector3.RIGHT, pitch_delta)
		head.rotation.x = clamp(head.rotation.x, -PI / 2.0, PI / 2.0)

	# Multi-mode camera (F4 cycle, F4 + arrows / scroll = orbit + zoom)
	if _camera_rig and _camera_rig.handle_input(event):
		return

	# Legacy "P" toggle keeps working for users who learned it before F4 landed —
	# it just cycles modes the same way F4 does.
	if event.is_action_pressed("camera_toggle"):
		_camera_rig.cycle_mode()

	# Stance toggles — Left Ctrl = crouch, Z = prone (lie down). Tapping the same
	# key again stands back up (headroom permitting).
	if event.is_action_pressed("crouch_toggle"):
		_toggle_stance(Stance.CROUCHING)
	if event.is_action_pressed("prone_toggle"):
		_toggle_stance(Stance.PRONE)
	# F5 — snapshot the 3rd-person free-cam relative position into the save file so
	# the operator's preferred external viewpoint survives reload (#freecam).
	if event.is_action_pressed("freecam_save"):
		var world := get_tree().current_scene
		if world and world.has_method("freecam_save_now"):
			world.call("freecam_save_now")

	# F12 → "unstuck" panic button. First lifts the capsule 2 m to clear most
	# wall-carve artefacts; if that doesn't free us, teleports back to
	# PlayerSpawn marker. Saves the player from having to alt-F4 when the
	# WallOpenings SAT carve leaves an invisible slab in a doorway.
	if event.is_action_pressed("debug_unstuck"):
		_unstuck_me()

	# Crosshair interaction: E acts on the thing under the centre of the screen,
	# not merely whichever trigger volume the player happens to be standing in.
	if event.is_action_pressed("interact"):
		_update_crosshair_interaction()
	if event.is_action_pressed("interact") and _look_interactable != null:
		if is_instance_valid(_look_interactable) and _look_interactable.has_method("crosshair_interact"):
			_look_interactable.call("crosshair_interact", self)
			get_viewport().set_input_as_handled()
			return

	# Debug fault trigger (0 / Numpad-0). Aim at any part of a machine and the
	# nearest faultable component (MotorOverload child, or any ancestor with a
	# force_trip / force_fault / trip method) gets tripped. Useful for testing
	# crew dispatch + LineFlow cascade without waiting for an organic overload.
	if event.is_action_pressed("debug_force_fault"):
		_debug_trigger_fault_at_crosshair()
		get_viewport().set_input_as_handled()
		return

	# Secret silo-fill cheat (Numpad-9). Aim at any part of an extruder feed
	# silo and press to instantly fill it to 90 %.
	if event.is_action_pressed("debug_fill_silo"):
		_debug_fill_silo_at_crosshair()
		get_viewport().set_input_as_handled()

	# F10 — enter the marker tool (was: one-shot feedback capture). While the
	# tool is active, F10/RMB exit is handled up in _marker_input(); this branch
	# only fires when the tool is OFF, so it always means "enter".
	if event.is_action_pressed("feedback_capture"):
		_marker_tool_enter()
		get_viewport().set_input_as_handled()
		return

	# F8 — Inspect Mode toggle (#inspect): hand the viewport to a free-fly
	# camera + show gizmos on every WorldLayout marker. Player input is
	# suspended by InspectMode while it's ON; the toggle-OFF path lives on
	# InspectMode itself (its _unhandled_input also listens for F8 / Esc) so
	# the operator can always get back to walking around.
	if event.is_action_pressed("inspect_mode"):
		var world := get_tree().current_scene
		if world and "inspect_mode" in world:
			var im : Node = world.get("inspect_mode")
			if im and im.has_method("toggle"):
				im.call("toggle")
				get_viewport().set_input_as_handled()
				return

	# Hotbar: number keys switch the active inventory slot, Q drops the active item.
	# Tools (scissors / scanner) live under Head and Inventory handles the
	# show/hide so only the active one is in your hand.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		var n_slots : int = int(inv.get("NUM_SLOTS"))
		for i in n_slots:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				inv.call("set_active", i)
				return
		# #punch: mouse wheel cycles the active slot in NORMAL WALKING MODE only.
		# Gated: cursor captured (excludes pause / settings / build-browse / HMI,
		# which all release the cursor), FP camera current, and build mode inactive.
		if event is InputEventMouseButton and event.pressed \
				and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED \
				and camera_3d != null and camera_3d.current \
				and not _build_mode_active():
			var mb := event as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				inv.call("set_active", (int(inv.get("active_idx")) - 1 + n_slots) % n_slots)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				inv.call("set_active", (int(inv.get("active_idx")) + 1) % n_slots)
				get_viewport().set_input_as_handled()
				return
		if event.is_action_pressed("hotbar_drop"):
			var t := inv.call("active") as Node3D
			if t and t.has_method("_drop"):
				t.call("_drop")    # tool returns itself to the world; will call Inventory.remove()
			return

	# ESC is owned by HUD.gd — do NOT handle ui_cancel here.

# =============================================================================
# #markers — F10 in-world point marker tool routing
# =============================================================================
## Lazily build the MarkerTool and host it under the world (current scene) so
## placed orbs stay fixed in world space rather than parented to the moving
## capsule. Rebuilt if the previous instance was freed by a scene change.
func _ensure_marker_tool() -> Node3D:
	if _marker_tool != null and is_instance_valid(_marker_tool):
		return _marker_tool
	_marker_tool = _MARKER_TOOL.new()
	_marker_tool.name = "MarkerTool"
	var host : Node = get_tree().current_scene
	if host == null:
		host = get_tree().root
	host.add_child(_marker_tool)
	return _marker_tool

## F10 (tool OFF) → enter marker mode, casting the crosshair ray from the eye
## and excluding the player capsule so we never tag ourselves.
func _marker_tool_enter() -> void:
	var mt := _ensure_marker_tool()
	mt.begin(camera_3d, [get_rid()])

## Consume LMB/RMB/G/H/F10 while the marker tool is active. Returns true when the
## event was handled (caller returns immediately). No-op when the tool is off.
func _marker_input(event: InputEvent) -> bool:
	if _marker_tool == null or not is_instance_valid(_marker_tool) or not _marker_tool.active:
		return false
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		match (event as InputEventMouseButton).button_index:
			MOUSE_BUTTON_LEFT:
				_marker_tool.place()
				get_viewport().set_input_as_handled()
				return true
			MOUSE_BUTTON_RIGHT:
				_marker_tool.exit_and_save()
				get_viewport().set_input_as_handled()
				return true
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		match (event as InputEventKey).physical_keycode:
			KEY_G:
				_marker_tool.cycle_snap()
				get_viewport().set_input_as_handled()
				return true
			KEY_H:
				_marker_tool.clear()
				get_viewport().set_input_as_handled()
				return true
			KEY_F10:
				_marker_tool.exit_and_save()   # F10 again = exit (toggle)
				get_viewport().set_input_as_handled()
				return true
	return false

# Register fallback Input actions for the hotbar — same trick as HUD's
# _ensure_map_action, since users without a fresh .godot project may have a
# True while BuildMode's placement UI is active — so the walk-mode wheel-scroll
# slot cycling stays OUT of build mode (where the wheel does other things).
func _build_mode_active() -> bool:
	var mw := get_tree().current_scene
	if mw == null or not ("build_mode" in mw):
		return false
	var bm = mw.get("build_mode")
	return bm != null and "_state" in bm and int(bm.get("_state")) != 0

# stale InputMap that doesn't know "hotbar_1" yet.
func _ensure_hotbar_actions() -> void:
	var binds := {
		"hotbar_1":          KEY_1,
		"hotbar_2":          KEY_2,
		"hotbar_3":          KEY_3,
		"hotbar_4":          KEY_4,
		"hotbar_5":          KEY_5,   # #punch: 5th inventory slot
		"hotbar_drop":       KEY_Q,
		# LPG dual-cylinder active-tank valve toggle (bale clamp only). #punch:
		# moved off H (vehicle_handbrake collision), then off J (walkie_headset
		# owns J — HUD._input swallows it before the clamp) to the free I key.
		"lpg_switch_active": KEY_I,
		# Vehicle aux — work lamps, 4-way hazards, horn (mast lift only honks).
		"vehicle_lights":    KEY_L,
		"vehicle_hazards":   KEY_K,
		"vehicle_horn":      KEY_N,
	}
	for action_name in binds:
		if not InputMap.has_action(action_name):
			InputMap.add_action(action_name)
		var key_code: int = binds[action_name]
		var has_event := false
		for ev in InputMap.action_get_events(action_name):
			if ev is InputEventKey and (ev as InputEventKey).keycode == key_code:
				has_event = true
				break
		if not has_event:
			var k := InputEventKey.new()
			k.keycode = key_code as Key
			InputMap.action_add_event(action_name, k)


# =============================================================================
# CROSSHAIR INTERACTION
# =============================================================================
## Interaction prompts now follow the camera ray: being close is only enough to be
## reachable; the player must also aim the centre crosshair at an object exposing
## `crosshair_prompt(player)` and `crosshair_interact(player)`.
func _update_crosshair_interaction() -> void:
	if camera_3d == null or not camera_3d.current or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_clear_crosshair_interaction()
		return
	var from := camera_3d.global_position
	var to := from - camera_3d.global_transform.basis.z * INTERACT_RAY_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		var active_tool := inv.call("active") as CollisionObject3D
		if active_tool:
			q.exclude.append(active_tool.get_rid())
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var hit_collider : Node = hit.get("collider") if not hit.is_empty() else null
	var target := _interactable_from_hit(hit_collider)
	# #210d — also resolve a pelletizer-knife target so the hold-E branch in
	# _update_knife_replace_hold knows what (if anything) is under the crosshair.
	# Walks the same ancestor chain as _interactable_from_hit but matches a
	# different contract (meta-tagged knife body, NO crosshair_* methods).
	_knife_target = _knife_from_hit(hit_collider)
	# TITECH/TOMRA shaft-wrap cut — same shape as the knife branch, different
	# placeable_id set (nir_sorter / titech_sort / tomra_sort). The two contracts
	# don't collide on a single hit because no sorter body carries the knife id.
	_shaft_target = _shaft_from_hit(hit_collider)
	if target != _look_interactable:
		_clear_crosshair_interaction()
		_look_interactable = target
	if _look_interactable != null and is_instance_valid(_look_interactable):
		var prompt := "Interact"
		if _look_interactable.has_method("crosshair_prompt"):
			prompt = String(_look_interactable.call("crosshair_prompt", self))
		if prompt != _look_prompt:
			if _look_prompt != "":
				EventBus.interaction_prompt_hide.emit(_look_interactable)
			_look_prompt = prompt
			if _look_prompt != "":
				EventBus.interaction_prompt_show.emit(_look_interactable, _look_prompt)
	# Knife prompt — driven separately so the wrench-not-held / wrench-held
	# wording and the live "(X/4 vernieuwd)" counter both surface even though
	# the knife body itself implements no crosshair_* methods.
	_refresh_knife_prompt()
	# Shaft-cut prompt — same reason, different contract (NIR sorter body).
	_refresh_shaft_prompt()

func _clear_crosshair_interaction() -> void:
	if _look_interactable != null:
		if is_instance_valid(_look_interactable) and _look_prompt != "":
			EventBus.interaction_prompt_hide.emit(_look_interactable)
		_look_interactable = null
		_look_prompt = ""
	# Knife branch shares the same "look dropped" lifecycle.
	if _knife_target != null:
		_hide_knife_prompt()
		_knife_target = null
	# Cancel any in-flight hold the moment the ray loses its target.
	if _knife_holding:
		_KNIFE_REPLACE.cancel()
		_knife_holding = false
	# Shaft-cut branch — same lifecycle as the knife branch.
	if _shaft_target != null:
		_hide_shaft_prompt()
		_shaft_target = null
	if _shaft_holding:
		_SHAFT_CUT.cancel()
		_shaft_holding = false

func _interactable_from_hit(node: Node) -> Node:
	var n := node
	while n != null:
		if n.has_method("crosshair_interact") and n.has_method("crosshair_prompt"):
			return n
		n = n.get_parent()
	return null

# =============================================================================
# #210d — Pelletizer knife replace (hold-E + wrench gated)
# =============================================================================
## Walk up the ray-hit ancestor chain looking for a node with
## meta("placeable_id") == "pelletizer_knife". Returns that node as a Node3D, or
## null if nothing in the chain qualifies. Cheap (only runs on hits) and keeps
## the knife body free of crosshair_* methods so the contract stays clean.
func _knife_from_hit(node: Node) -> Node3D:
	var n := node
	while n != null:
		if n.has_meta("placeable_id") \
				and String(n.get_meta("placeable_id")) == _KNIFE_REPLACE.KNIFE_PLACEABLE_ID:
			return n as Node3D
		n = n.get_parent()
	return null

## Returns true if the player is currently carrying the Maat-7 socket wrench in
## the active inventory slot. Used to gate prompt text + the hold-begin path.
func _player_has_wrench() -> bool:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("active"):
		return false
	var t = inv.call("active")
	if t == null or not is_instance_valid(t):
		return false
	if "tool_id" in t and String(t.get("tool_id")) == _KNIFE_REPLACE.WRENCH_TOOL_ID:
		return true
	if t is Node and (t as Node).is_in_group(_KNIFE_REPLACE.WRENCH_TOOL_ID):
		return true
	return false

## Number of knives on this pelletizer that have already been refreshed back
## to NEW (state == 0). Reads each sibling knife body under the same cutter
## rotor parent. Falls back to 0 if any meta is missing.
func _knives_renewed_count(knife: Node3D) -> int:
	if knife == null:
		return 0
	var rotor := knife.get_parent()
	if rotor == null:
		return 0
	var n := 0
	for c in rotor.get_children():
		if c == null or not (c is Node):
			continue
		if not c.has_meta("placeable_id"):
			continue
		if String(c.get_meta("placeable_id")) != _KNIFE_REPLACE.KNIFE_PLACEABLE_ID:
			continue
		# Treat MISSING knife_state as NEW (matches the initial build state in
		# PlaceableCatalog._m_heetafslag, where knife_state is only stamped
		# after the first set_knife_state call).
		var s : int = int(c.get_meta("knife_state", 0))
		if s == 0:
			n += 1
	return n

## Build + emit the prompt string for the knife currently under the crosshair.
## Idempotent on the same string — re-emits only when the text changes.
##
## Cases:
##   - No knife under the ray         → hide knife prompt (if any was showing)
##   - Knife under ray, no wrench     → "Maat-7 dopsleutel nodig"
##   - Knife + wrench + rotor spinning → "Stop eerst de rotor"
##   - Knife + wrench, no hold        → "E — vervang mes <i+1> (X/4 vernieuwd)"
##   - Hold in flight                 → "Vervangen... NN %"
func _refresh_knife_prompt() -> void:
	if _knife_target == null or not is_instance_valid(_knife_target):
		_hide_knife_prompt()
		return
	var idx : int = int(_knife_target.get_meta("knife_index", 0))
	var renewed : int = _knives_renewed_count(_knife_target)
	var text : String
	if _knife_holding:
		var pct : int = int(round(_KNIFE_REPLACE.progress() * 100.0))
		text = "Vervangen... %d %%" % pct
	elif not _player_has_wrench():
		text = "Maat-7 dopsleutel nodig"
	elif not _KNIFE_REPLACE.is_rotor_safe(_knife_target):
		# Wrench is in hand but the cut_rm disc is still spinning —
		# try_begin() will refuse, so feed the operator the reason explicitly.
		text = "Stop eerst de rotor"
	else:
		text = "E — vervang mes %d (%d/4 vernieuwd)" % [idx + 1, renewed]
	if text == _knife_prompt_text:
		return
	_knife_prompt_text = text
	EventBus.interaction_prompt_show.emit(_knife_target, text)

func _hide_knife_prompt() -> void:
	if _knife_prompt_text == "":
		return
	if _knife_target != null and is_instance_valid(_knife_target):
		EventBus.interaction_prompt_hide.emit(_knife_target)
	_knife_prompt_text = ""

## Per-tick driver for the hold-E knife replace. Hooked into _physics_process
## just after _update_crosshair_interaction so the per-frame target snapshot is
## already current. State machine:
##   - E pressed + knife in sight + wrench held + no hold yet → try_begin()
##   - E held    + same knife still in sight                  → tick_hold()
##   - E held    + target dropped / ray moved                 → cancel()
##   - E released before progress >= 1                        → cancel()
##   - progress >= 1                                          → complete()
func _update_knife_replace_hold(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if _knife_holding:
			_KNIFE_REPLACE.cancel()
			_knife_holding = false
			_refresh_knife_prompt()
		return
	var e_held := Input.is_action_pressed("interact")
	# Released → cancel any in-flight hold.
	if not e_held:
		if _knife_holding:
			_KNIFE_REPLACE.cancel()
			_knife_holding = false
			_refresh_knife_prompt()
		return
	# E is held. We don't poach the single-tap interact branch (which fires in
	# _unhandled_input on action_just_pressed and consumes its own viewport
	# event); the begin condition below is satisfied on the FIRST physics tick
	# after the press, by which time the tap branch has already returned. That
	# tap branch only triggers when an _look_interactable is present — a bare
	# knife body has none, so the two paths can't collide on the same target.
	if not _knife_holding:
		if _knife_target == null or not is_instance_valid(_knife_target):
			return
		if not _player_has_wrench():
			return
		if not _KNIFE_REPLACE.try_begin(self, _knife_target):
			return
		_knife_holding = true
		_refresh_knife_prompt()
		return
	# Mid-hold guards: the ray must still be on the same knife and we must
	# still be carrying the wrench. Either invalidation cancels.
	if _knife_target == null or not is_instance_valid(_knife_target) \
			or not _KNIFE_REPLACE.is_active_on(_knife_target) \
			or not _player_has_wrench():
		_KNIFE_REPLACE.cancel()
		_knife_holding = false
		_refresh_knife_prompt()
		return
	var p : float = _KNIFE_REPLACE.tick_hold(delta)
	_refresh_knife_prompt()
	if p >= 1.0:
		var ok : bool = _KNIFE_REPLACE.complete(_knife_target)
		_knife_holding = false
		if ok:
			print("[Player] Pelletizer knife %d replaced" \
				% int(_knife_target.get_meta("knife_index", 0)))
		else:
			push_warning("[Player] Knife replace failed (model resolution)")
		# Refresh the prompt — the (X/4 vernieuwd) counter just changed.
		_refresh_knife_prompt()

# =============================================================================
# TITECH/TOMRA shaft-wrap cut (hold-E + wire-cutter gated)
# =============================================================================
## Walk up the ray-hit ancestor chain looking for a node whose placeable_id is
## one of {nir_sorter, titech_sort, tomra_sort}. Returns that node as a Node3D,
## or null if nothing in the chain qualifies. Cheap — only runs on hits — and
## keeps the sorter body free of crosshair_* methods so the contract matches
## the knife branch.
func _shaft_from_hit(node: Node) -> Node3D:
	var n := node
	while n != null:
		if n.has_meta("placeable_id") \
				and _SHAFT_CUT.NIR_PLACEABLE_IDS.has(String(n.get_meta("placeable_id"))):
			return n as Node3D
		n = n.get_parent()
	return null

## True if the player is currently carrying the wire cutter (scissors) in the
## active inventory slot. Used to gate prompt text + the hold-begin path.
## Mirrors _player_has_wrench(): tool_id match wins, group fallback for variants.
func _player_has_wire_cutter() -> bool:
	var inv := get_node_or_null("/root/Inventory")
	if inv == null or not inv.has_method("active"):
		return false
	var t = inv.call("active")
	if t == null or not is_instance_valid(t):
		return false
	if "tool_id" in t and String(t.get("tool_id")) == _SHAFT_CUT.WIRE_CUTTER_TOOL_ID:
		return true
	if t is Node and (t as Node).is_in_group("wire_cutter"):
		return true
	return false

## Peek the current shaft-wrap grams off the cached NirSorter controller without
## starting a hold. Returns -1.0 if the controller isn't wired yet (LineFlow
## hasn't rebuilt since placement) — caller treats that as "unknown / no wrap".
func _shaft_wrap_g_of(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return -1.0
	if not target.has_meta("nir_sorter_ctrl"):
		return -1.0
	var ctrl = target.get_meta("nir_sorter_ctrl")
	if ctrl == null or not is_instance_valid(ctrl):
		return -1.0
	if ctrl.has_method("wrap_g"):
		return float(ctrl.call("wrap_g"))
	# Fallback: read the WrapModel field directly if the public accessor is gone.
	if "shaft_wrap" in ctrl:
		var wm = ctrl.get("shaft_wrap")
		if wm != null and "wrap_g" in wm:
			return float(wm.get("wrap_g"))
	return -1.0

## Build + emit the prompt string for the NIR sorter currently under the
## crosshair. Idempotent on the same string — re-emits only when the text
## changes (matches _refresh_knife_prompt's pattern).
##
## Cases:
##   - No sorter under the ray             → hide shaft prompt
##   - Sorter + wrap visible, no cutter    → "Schaartje nodig — kabel wikkel verwijderen"
##   - Sorter + cutter + wrap > threshold  → "E — snij wikkel (XXg)"
##   - Sorter + cutter + wrap <= threshold → "Geen wikkel zichtbaar"
##   - Hold in flight                      → "Snijden... NN %"
func _refresh_shaft_prompt() -> void:
	if _shaft_target == null or not is_instance_valid(_shaft_target):
		_hide_shaft_prompt()
		return
	var text : String
	if _shaft_holding:
		var pct : int = int(round(_SHAFT_CUT.progress() * 100.0))
		text = "Snijden... %d %%" % pct
	else:
		var wrap_g : float = _shaft_wrap_g_of(_shaft_target)
		var has_cutter : bool = _player_has_wire_cutter()
		if not has_cutter:
			# Only surface the "need a wire cutter" hint when there's actually
			# wrap to cut. Sorters with a clean shaft should be silent.
			if wrap_g > _SHAFT_CUT.MIN_WRAP_FOR_CUT:
				text = "Schaartje nodig — kabel wikkel verwijderen"
			else:
				_hide_shaft_prompt()
				return
		else:
			if wrap_g > _SHAFT_CUT.MIN_WRAP_FOR_CUT:
				text = "E — snij wikkel (%dg)" % int(round(wrap_g))
			else:
				text = "Geen wikkel zichtbaar"
	if text == _shaft_prompt_text:
		return
	_shaft_prompt_text = text
	EventBus.interaction_prompt_show.emit(_shaft_target, text)

func _hide_shaft_prompt() -> void:
	if _shaft_prompt_text == "":
		return
	if _shaft_target != null and is_instance_valid(_shaft_target):
		EventBus.interaction_prompt_hide.emit(_shaft_target)
	_shaft_prompt_text = ""

## Per-tick driver for the hold-E shaft-wrap cut. Same state machine as
## _update_knife_replace_hold:
##   - E pressed + sorter in sight + wire cutter held + wrap > threshold → try_begin()
##   - E held    + same sorter still in sight + cutter still held       → tick_hold()
##   - E held    + target dropped / ray moved / cutter dropped          → cancel()
##   - E released before progress >= 1                                   → cancel()
##   - progress >= 1                                                     → complete()
func _update_shaft_cut_hold(delta: float) -> void:
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		if _shaft_holding:
			_SHAFT_CUT.cancel()
			_shaft_holding = false
			_refresh_shaft_prompt()
		return
	var e_held := Input.is_action_pressed("interact")
	# Released → cancel any in-flight hold.
	if not e_held:
		if _shaft_holding:
			_SHAFT_CUT.cancel()
			_shaft_holding = false
			_refresh_shaft_prompt()
		return
	# E is held. The single-tap interact branch in _input only fires when an
	# _look_interactable is present — the NIR sorter body has none, so the two
	# paths can't collide on the same target (same reasoning as the knife block).
	if not _shaft_holding:
		if _shaft_target == null or not is_instance_valid(_shaft_target):
			return
		if not _player_has_wire_cutter():
			return
		if not _SHAFT_CUT.try_begin(self, _shaft_target):
			return
		_shaft_holding = true
		_refresh_shaft_prompt()
		return
	# Mid-hold guards: ray must still be on the same sorter and we must still
	# be carrying the wire cutter. Either invalidation cancels.
	if _shaft_target == null or not is_instance_valid(_shaft_target) \
			or not _SHAFT_CUT.is_active_on(_shaft_target) \
			or not _player_has_wire_cutter():
		_SHAFT_CUT.cancel()
		_shaft_holding = false
		_refresh_shaft_prompt()
		return
	var p : float = _SHAFT_CUT.tick_hold(delta)
	_refresh_shaft_prompt()
	if p >= 1.0:
		var ok : bool = _SHAFT_CUT.complete(_shaft_target)
		_shaft_holding = false
		if ok:
			print("[Player] TITECH shaft wrap cut (%.0f g removed)" \
				% _SHAFT_CUT.CUT_REMOVE_G)
		else:
			push_warning("[Player] Shaft-wrap cut failed (controller resolution)")
		# Refresh the prompt — wrap_g just dropped, idle text should follow.
		_refresh_shaft_prompt()

# =============================================================================
# Debug — force a fault on the machine under the crosshair (0 / Numpad-0).
# =============================================================================
## Raycast from the crosshair the same way the interact prompt does, walk up the
## hit collider's ancestor chain, and trip the nearest faultable component.
## Resolution order:
##   1. Any ancestor whose direct child is a MotorOverload node (or grandchild)
##   2. Any ancestor with a force_trip() method
##   3. Any ancestor with a force_fault() method
##   4. Any ancestor with a trip() method
## Logs the resolved target's name + reason; prints a clear "no fault target"
## message when nothing matches (so operators know if the hit collider was
## something unfaultable like a wall or the floor).
func _debug_trigger_fault_at_crosshair() -> void:
	if camera_3d == null:
		return
	var from := camera_3d.global_position
	var to := from - camera_3d.global_transform.basis.z * INTERACT_RAY_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("[DEBUG] force-fault: crosshair hit nothing within %d m" % INTERACT_RAY_RANGE)
		return
	var hit_node : Node = hit["collider"]
	# Walk up the ancestor chain looking for a faultable component.
	var n : Node = hit_node
	while n != null:
		# 1) Scan children for a MotorOverload (typical machine wiring).
		for c in n.get_children():
			if c != null and c.has_method("force_trip") \
					and String(c.get_class()) != "":
				# MotorOverload exposes force_trip(); other classes might too,
				# so prefer the explicitly-named one when it's a direct child.
				if "MotorOverload" in String(c.get_script().get_path() if c.get_script() else "") \
						or "motor_overload" in String(c.name).to_lower():
					c.call("force_trip")
					print("[DEBUG] force-fault: tripped MotorOverload on %s" % n.name)
					return
		# 2) Self has a fault method.
		if n.has_method("force_trip"):
			n.call("force_trip")
			print("[DEBUG] force-fault: called force_trip() on %s" % n.name)
			return
		if n.has_method("force_fault"):
			n.call("force_fault")
			print("[DEBUG] force-fault: called force_fault() on %s" % n.name)
			return
		if n.has_method("trip"):
			n.call("trip")
			print("[DEBUG] force-fault: called trip() on %s" % n.name)
			return
		n = n.get_parent()
	print("[DEBUG] force-fault: no faultable component found under %s" % String(hit_node.name))

## SECRET (Numpad-9) — raycast from the camera through the crosshair, walk up
## the ancestor chain until we find an extruder_silo placeable, then drop a
## "DebugFill" mesh inside it sized to 90 % of the inner body volume. Re-runs
## REPLACE the mesh so the fill stays at 90 % regardless of how many times you
## press the key. Sets a `fill_pct` meta on the silo so any future sim
## integration can read it without scanning the visual.
func _debug_fill_silo_at_crosshair() -> void:
	if camera_3d == null:
		return
	var from := camera_3d.global_position
	var to := from - camera_3d.global_transform.basis.z * INTERACT_RAY_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		print("[DEBUG] fill-silo: crosshair hit nothing within %d m" % INTERACT_RAY_RANGE)
		return
	# Find the nearest ancestor that's an extruder_silo placeable.
	var n : Node = hit["collider"]
	var silo : Node3D = null
	while n != null:
		if n is Node3D and n.has_meta("placeable_id") \
				and String(n.get_meta("placeable_id")) == "extruder_silo":
			silo = n as Node3D
			break
		n = n.get_parent()
	if silo == null:
		print("[DEBUG] fill-silo: %s is not part of an extruder_silo" % String(hit["collider"].name))
		return
	# Measure the body AABB by merging every mesh descendant in the silo's
	# local frame. The extruder_silo model spans frame_top..box_top on Y
	# (≈ 0.40..0.92 of size.y); the merged AABB captures that without
	# hard-coding the constants.
	var bb := _silo_local_aabb(silo)
	if bb.size == Vector3.ZERO:
		print("[DEBUG] fill-silo: couldn't measure %s body" % silo.name)
		return
	const FILL_PCT   : float = 0.90
	const WALL_INSET : float = 0.06
	# Clip the lower 42 % of the AABB — that's the support-frame zone below
	# the actual silo box. The flake sits in the upper 50 % only.
	var inner_y_low  : float = bb.position.y + bb.size.y * 0.42
	var inner_y_high : float = bb.position.y + bb.size.y * 0.92
	var inner_x  : float = max(0.05, bb.size.x - WALL_INSET * 2.0)
	var inner_z  : float = max(0.05, bb.size.z - WALL_INSET * 2.0)
	var inner_h  : float = max(0.05, inner_y_high - inner_y_low)
	var fill_h   : float = inner_h * FILL_PCT
	var fill_cy  : float = inner_y_low + fill_h * 0.5
	# Remove any prior DebugFill so re-pressing keeps it at exactly 90 %.
	var existing := silo.get_node_or_null("DebugFill") as Node3D
	if existing != null:
		existing.queue_free()
	var mi := MeshInstance3D.new()
	mi.name = "DebugFill"
	var bm := BoxMesh.new()
	bm.size = Vector3(inner_x, fill_h, inner_z)
	mi.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.82, 0.70, 0.85)    # flake-coloured, slight translucency
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.92
	mat.metallic = 0.0
	mi.material_override = mat
	var bb_cx : float = bb.position.x + bb.size.x * 0.5
	var bb_cz : float = bb.position.z + bb.size.z * 0.5
	mi.position = Vector3(bb_cx, fill_cy, bb_cz)
	silo.add_child(mi)
	silo.set_meta("fill_pct", FILL_PCT)
	print("[DEBUG] fill-silo: filled %s to %.0f %%" % [silo.name, FILL_PCT * 100.0])

## Merge every descendant MeshInstance3D's AABB into the silo's local frame.
## Skips the DebugFill mesh itself so re-runs don't grow the bounding box.
func _silo_local_aabb(silo: Node3D) -> AABB:
	var bb := AABB()
	var started := false
	var inv := silo.global_transform.affine_inverse()
	var stack : Array = [silo]
	while not stack.is_empty():
		var nd : Node = stack.pop_back()
		for c in nd.get_children():
			if c.name == "DebugFill":
				continue
			if c is MeshInstance3D and (c as MeshInstance3D).mesh != null:
				var a : AABB = (c as MeshInstance3D).get_aabb()
				var x : Transform3D = inv * (c as Node3D).global_transform
				for ix in [0.0, 1.0]:
					for iy in [0.0, 1.0]:
						for iz in [0.0, 1.0]:
							var p : Vector3 = x * (a.position + Vector3(a.size.x * ix, a.size.y * iy, a.size.z * iz))
							if not started:
								bb = AABB(p, Vector3.ZERO); started = true
							else:
								bb = bb.expand(p)
			if c is Node3D:
				stack.append(c)
	return bb

# =============================================================================
# F10 — collaborative feedback capture
# =============================================================================
## Snapshot the current view + machine-readable context about whatever the
## crosshair is aimed at to `user://feedback/<timestamp>/`. The folder ends
## up with `screenshot.png` and `context.json`; the operator pastes the path
## into chat and the developer reads context.json to know exactly which
## placeable_id / scene path / world position they meant. Reuses the
## `scanner_banner` HUD toast for the "captured #N" confirmation.
##
## Why JSON over just a screenshot:
##   * A picture of a silo doesn't say WHICH silo (extruder_3a vs 3b vs 1).
##   * The catalog override system writes by `placeable_id`; the JSON makes
##     the id discoverable without the developer having to read the photo.
##   * Future bakes can replay the camera pose to verify the change landed.
func _capture_feedback_at_crosshair() -> void:
	var stamp := _feedback_timestamp()
	var dir_path := "user://feedback/%s" % stamp
	var err := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path)) \
		if not dir_path.begins_with("user://") else DirAccess.make_dir_recursive_absolute(dir_path)
	if err != OK and not DirAccess.dir_exists_absolute(dir_path):
		push_warning("[feedback] could not create %s" % dir_path)
		return
	# Screenshot — grab the active viewport's last frame as a PNG.
	var img : Image = get_viewport().get_texture().get_image()
	if img != null:
		img.save_png("%s/screenshot.png" % dir_path)
	# Build the JSON context dict.
	var ctx : Dictionary = {
		"format":      "cedo-feedback-v1",
		"captured_at": Time.get_datetime_string_from_system(true),
		"world": {
			"scene": String(get_tree().current_scene.scene_file_path) \
				if get_tree().current_scene else "",
		},
		"player": {
			"position": _v3_to_arr(global_position),
			"rotation_y": rotation.y,
		},
		"camera": _camera_pose_dict(),
		"crosshair": _crosshair_context(),
	}
	# Shift clock state (if present) — helps answer "what was happening at the
	# moment of capture" without a screenshot reverse-engineering session.
	var sc := get_tree().root.get_node_or_null("/root/ShiftClock")
	if sc != null and "current_time_label" in sc:
		ctx["shift"] = {"time": String(sc.get("current_time_label"))}
	# Stash any pending size overrides so the developer sees what's already
	# been baked vs what remains to do.
	PlaceableCatalog._ensure_overrides_loaded()
	var overrides : Dictionary = PlaceableCatalog._size_overrides
	if not overrides.is_empty():
		var dump : Dictionary = {}
		for k in overrides.keys():
			var v : Vector3 = overrides[k]
			dump[String(k)] = [v.x, v.y, v.z]
		ctx["active_size_overrides"] = dump
	var jf := FileAccess.open("%s/context.json" % dir_path, FileAccess.WRITE)
	if jf != null:
		jf.store_string(JSON.stringify(ctx, "\t"))
		jf.close()
	# Toast — uses the existing scanner banner channel so the message lands
	# in the same HUD slot as bale scans / F5 saves.
	var banner := "[F10] feedback #%s saved → %s" % [stamp, ProjectSettings.globalize_path(dir_path)]
	var bus := get_tree().root.get_node_or_null("/root/EventBus")
	if bus != null and bus.has_signal("scanner_banner"):
		bus.emit_signal("scanner_banner", banner, false)
	print("[feedback] %s" % banner)

## yyyymmdd_hhmmss timestamp for the feedback folder name. Sortable + safe
## across platforms (no colons, spaces, or path separators).
func _feedback_timestamp() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "%04d%02d%02d_%02d%02d%02d" % [
		int(t["year"]), int(t["month"]), int(t["day"]),
		int(t["hour"]), int(t["minute"]), int(t["second"])]

func _v3_to_arr(v: Vector3) -> Array:
	return [v.x, v.y, v.z]

## Camera pose so the developer can later re-place the view at a key press
## and verify the change.
func _camera_pose_dict() -> Dictionary:
	if camera_3d == null:
		return {}
	var fwd : Vector3 = -camera_3d.global_transform.basis.z
	return {
		"position":  _v3_to_arr(camera_3d.global_position),
		"forward":   _v3_to_arr(fwd),
		"fov_deg":   camera_3d.fov,
	}

## Raycast from camera through the crosshair, walk up to the nearest
## `placed_object` ancestor (the same node K-mode edits), and serialise
## everything that identifies it: id, name, scene path, world transform,
## scale + base size + any active size override. When we don't hit a
## `placed_object`, fall back to the raw collider info so the developer can
## still see what the operator was aiming at.
func _crosshair_context() -> Dictionary:
	var ctx : Dictionary = {"hit": false}
	if camera_3d == null:
		return ctx
	var from := camera_3d.global_position
	# Feedback tagging ray is deliberately LONG (unlike the interact ray):
	# the operator aims at a door / wall / feature from anywhere in the yard,
	# presses F10, and world_point pins it to centimetres.
	const FEEDBACK_RAY_RANGE := 250.0
	var to := from - camera_3d.global_transform.basis.z * FEEDBACK_RAY_RANGE
	var q := PhysicsRayQueryParameters3D.create(from, to)
	q.collision_mask = 0xFFFFFFFF
	q.collide_with_areas = true
	q.collide_with_bodies = true
	q.exclude = [get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		return ctx
	ctx["hit"] = true
	ctx["world_point"] = _v3_to_arr(hit["position"])
	ctx["world_normal"] = _v3_to_arr(hit["normal"])
	# PC coords of the aimed point — same frame as the layout markers, so a
	# tagged door can be placed without any scene-frame conversion.
	if has_node("/root/Plant") and Plant.is_initialized():
		var pcv : Vector2 = Plant.scene_to_pc(hit["position"])
		ctx["world_point_pc"] = [pcv.x, pcv.y]
	var collider : Node = hit["collider"]
	# String() cast is required: collider.name is a StringName, "" is a String, and
	# the mismatch trips INCOMPATIBLE_TERNARY (warnings are errors in this project).
	ctx["collider_name"] = String(collider.name) if collider != null else ""
	# Climb to the nearest placed_object so the developer gets a stable
	# placeable_id rather than e.g. "Model" or "Rib_2".
	var n : Node = collider
	var placed : Node3D = null
	while n != null:
		if n.is_in_group("placed_object"):
			placed = n as Node3D
			break
		n = n.get_parent()
	if placed == null:
		return ctx
	ctx["scene_path"] = String(placed.get_path())
	ctx["node_name"] = placed.name
	ctx["position"] = _v3_to_arr(placed.global_position)
	ctx["rotation_y"] = placed.rotation.y
	ctx["scale"] = _v3_to_arr(placed.scale)
	if placed.has_meta("placeable_id"):
		var pid := String(placed.get_meta("placeable_id"))
		ctx["placeable_id"] = pid
		var item := PlaceableCatalog.get_item(pid)
		if not item.is_empty():
			ctx["catalog_name"] = String(item.get("name", ""))
			ctx["catalog_category"] = String(item.get("category", ""))
			if item.has("size"):
				var sz : Vector3 = item["size"]
				ctx["effective_base_size"] = _v3_to_arr(sz)
			if PlaceableCatalog.has_size_override(pid):
				ctx["override_active"] = true
	if placed.has_meta("macro_id"):
		ctx["macro_id"] = String(placed.get_meta("macro_id"))
	if placed.has_meta("hmi_id"):
		ctx["hmi_id"] = String(placed.get_meta("hmi_id"))
	return ctx

# =============================================================================
# Animation Phase 1 — push horizontal speed into the rig's BlendSpace2D
# =============================================================================
## Locate the AnimationTree node Humanoid._install_skeleton_rig parents under
## "PlayerBody". MainWorld._spawn_player names the rig "PlayerBody" (see
## MainWorld.gd:821); GauntletWorld._build_player uses the same name. Returns
## null until the rig is attached (controller _ready runs BEFORE the world
## attaches the body), so we resolve lazily on first use.
func _resolve_player_anim_tree() -> AnimationTree:
	var body := get_node_or_null("PlayerBody")
	if body == null:
		# Some test scenes attach the rig under the default Humanoid name "Body".
		body = get_node_or_null("Body")
	if body == null:
		return null
	var direct := body.get_node_or_null("AnimationTree")
	if direct is AnimationTree:
		return direct as AnimationTree
	# Recursive fallback in case a future patch nests the rig deeper.
	return _find_anim_tree_recursive(body)

func _find_anim_tree_recursive(n: Node) -> AnimationTree:
	for c in n.get_children():
		if c is AnimationTree:
			return c as AnimationTree
		if c is Node:
			var hit := _find_anim_tree_recursive(c)
			if hit != null:
				return hit
	return null

## Map horizontal speed to BlendSpace X (0 = idle, 1 = walk, 2 = run). The walk
## point matches walk_speed (≈5 m/s); the run point corresponds to
## walk_speed × sprint_multiplier (≈8.5 m/s). Fast-traverse (5×) is clamped to
## the same run pose — no separate "sprint" animation for Phase 1.
## Phase 2: the AnimationTree's tree_root is now an AnimationNodeStateMachine
## wrapping the locomotion BlendSpace2D + crouch / prone / seated pose states.
## Locomotion blend_position is now NESTED inside the state name —
## parameters/locomotion/blend_position. State transitions are driven via
## parameters/playback.travel(name) with a 0.25 s xfade configured on the rig.
var _last_anim_state : String = "locomotion"

func _update_animation_blend() -> void:
	if _anim_tree == null or not is_instance_valid(_anim_tree):
		_anim_tree = _resolve_player_anim_tree()
		if _anim_tree == null:
			return
	# Travel to the state that matches our stance. _stance is the operator's
	# crouch/prone toggle; in-vehicle is owned elsewhere and pushed via
	# set_in_vehicle_animation(...) below.
	var want_state : String
	match _stance:
		Stance.CROUCHING: want_state = "crouch"
		Stance.PRONE:     want_state = "prone"
		_:                want_state = "locomotion"
	# in-vehicle wins over any stance — driver-seat pose
	if _in_vehicle_seated:
		want_state = "seated"
	if want_state != _last_anim_state:
		var pb := _anim_tree.get("parameters/playback") as AnimationNodeStateMachinePlayback
		if pb != null:
			pb.travel(want_state)
		_last_anim_state = want_state
	# Locomotion BlendSpace2D only receives speed when we're in the locomotion
	# state. While crouch / prone / seated are holding a static pose, blend
	# position is irrelevant.
	if want_state != "locomotion":
		return
	var horiz : float = Vector2(velocity.x, velocity.z).length()
	if horiz < 0.05:
		_anim_tree.set("parameters/locomotion/blend_position", Vector2(0.0, 0.0))
		return
	# #224 — decompose world velocity into the body's LOCAL forward/right (the body
	# yaws with look, so basis carries facing). X = gait speed, Y = strafe.
	var lv : Vector3 = global_transform.basis.inverse() * Vector3(velocity.x, 0.0, velocity.z)
	var side : float = lv.x                    # right (+) / left (-)
	var run_speed : float = walk_speed * sprint_multiplier
	var bx : float
	if horiz <= walk_speed:
		bx = horiz / maxf(walk_speed, 0.1)
	else:
		bx = 1.0 + clampf((horiz - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	var by : float = clampf(side / maxf(walk_speed, 0.1), -1.0, 1.0)   # #224 strafe
	_anim_tree.set("parameters/locomotion/blend_position", Vector2(clampf(bx, 0.0, 2.0), by))

## Vehicles call this when the player enters / exits the driver seat so the
## skeleton swaps to the seated pose. Per-vehicle bespoke seated poses (mast
## lift vs car vs forklift) are Phase 3; for now everything routes to the
## single "seated" state.
var _in_vehicle_seated : bool = false
func set_in_vehicle_animation(seated: bool) -> void:
	_in_vehicle_seated = seated
