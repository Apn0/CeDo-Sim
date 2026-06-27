extends CharacterBody3D

class_name PlayerController

## First-person walking controller.
## Horizontal look rotates the player body (yaw).
## Vertical look rotates the Camera3D under Head (pitch, clamped ±90°).
## Movement is relative to the body's facing direction.
##
## ESC / pause is handled by HUD.gd — not here.
## When the mouse cursor is visible (pause menu open) movement is suppressed.

# Movement
@export var walk_speed         : float = 5.0
@export var acceleration       : float = 20.0
@export var friction           : float = 16.0
@export var jump_speed         : float = 4.5
# Sprint (#side-quest from operator): Shift while moving multiplies the walk
# speed. Only fires while STANDING — crouched / prone keep their stance pace.
@export var sprint_multiplier  : float = 1.7
# Fast-traverse (Alt): 5× speed for cross-yard movement during testing.
# Overrides sprint when both are held.
@export var fast_run_multiplier : float = 5.0

const GRAVITY: float = 9.8
const STEP_HEIGHT: float = 0.4   # max ledge/curb height the player walks over
const INTERACT_RAY_RANGE: float = 3.75

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
const CLIMB_DURATION        : float = 0.5   # seconds to lerp from start pose to top
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

func _physics_process(delta: float) -> void:
	# Vault/climb override (#cluster VAULT_CLIMB): while the mantle tween is
	# active we own the transform directly — gravity, WASD, jump, step-up and
	# wedge-rescue all step aside until we drop the player on top of the ledge.
	if _vault_state == VaultState.CLIMBING:
		_advance_vault(delta)
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
	var speed_mul : float = float(STANCE_SPEED_MUL[_stance])
	if _stance == Stance.STANDING:
		if Input.is_action_pressed("fast_run"):
			speed_mul *= fast_run_multiplier
		elif Input.is_action_pressed("sprint"):
			speed_mul *= sprint_multiplier
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
	_apply_belt_carry(delta)
	_update_crosshair_interaction()
	# Animation Phase 1: feed the body's BlendSpace2D so 3rd-person/orbit shows
	# a real walk cycle. No-op for first-person (the body's head is on a
	# hidden layer + the FP eye sits between the body's shoulders).
	_update_animation_blend()

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
	_ray_player_waist.position = Vector3(0.0, 0.0, 0.0)
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
	# (3) Obstacle profile: waist + chest hit, head clear.
	if not _ray_player_waist.is_colliding():
		return false
	if not _ray_player_chest.is_colliding():
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
	# Register the fast-traverse keybind (Alt) — 5× speed for testing.
	if not InputMap.has_action("fast_run"):
		InputMap.add_action("fast_run")
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

	# Hotbar: 1-4 switch the active inventory slot, Q drops the active item.
	# Tools (scissors / scanner) live under Head and Inventory handles the
	# show/hide so only the active one is in your hand.
	var inv := get_node_or_null("/root/Inventory")
	if inv:
		for i in 4:
			if event.is_action_pressed("hotbar_%d" % (i + 1)):
				inv.call("set_active", i)
				return
		if event.is_action_pressed("hotbar_drop"):
			var t := inv.call("active") as Node3D
			if t and t.has_method("_drop"):
				t.call("_drop")    # tool returns itself to the world; will call Inventory.remove()
			return

	# ESC is owned by HUD.gd — do NOT handle ui_cancel here.

# Register fallback Input actions for the hotbar — same trick as HUD's
# _ensure_map_action, since users without a fresh .godot project may have a
# stale InputMap that doesn't know "hotbar_1" yet.
func _ensure_hotbar_actions() -> void:
	var binds := {
		"hotbar_1":          KEY_1,
		"hotbar_2":          KEY_2,
		"hotbar_3":          KEY_3,
		"hotbar_4":          KEY_4,
		"hotbar_drop":       KEY_Q,
		# LPG dual-cylinder active-tank valve toggle (bale clamp only). Bound
		# here as a fallback so a stale InputMap doesn't silently swallow H.
		"lpg_switch_active": KEY_H,
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
	var target := _interactable_from_hit(hit.get("collider") if not hit.is_empty() else null)
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

func _clear_crosshair_interaction() -> void:
	if _look_interactable != null:
		if is_instance_valid(_look_interactable) and _look_prompt != "":
			EventBus.interaction_prompt_hide.emit(_look_interactable)
		_look_interactable = null
		_look_prompt = ""

func _interactable_from_hit(node: Node) -> Node:
	var n := node
	while n != null:
		if n.has_method("crosshair_interact") and n.has_method("crosshair_prompt"):
			return n
		n = n.get_parent()
	return null

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
	# vault wins over stance
	if _vault_state == VaultState.CLIMBING:
		want_state = "climb"
	# in-vehicle wins over any stance/vault — driver-seat pose
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
	var run_speed : float = walk_speed * sprint_multiplier
	var bx : float
	if horiz <= walk_speed:
		bx = horiz / maxf(walk_speed, 0.1)
	else:
		bx = 1.0 + clampf((horiz - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	_anim_tree.set("parameters/locomotion/blend_position", Vector2(clampf(bx, 0.0, 2.0), 0.0))

## Vehicles call this when the player enters / exits the driver seat so the
## skeleton swaps to the seated pose. Per-vehicle bespoke seated poses (mast
## lift vs car vs forklift) are Phase 3; for now everything routes to the
## single "seated" state.
var _in_vehicle_seated : bool = false
func set_in_vehicle_animation(seated: bool) -> void:
	_in_vehicle_seated = seated
