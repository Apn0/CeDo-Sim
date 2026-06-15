extends StaticBody3D
class_name PushGate

## Self-closing personnel safety push-gate at the top of an industrial ladder.
##
## Asymmetric interaction (the operator's #98 spec):
##   • Approached from the LADDER side (`free_side` = +X / -X / +Z / -Z): the
##     player can simply push it open by walking into it. The pivot tweens out
##     of the way as soon as the player capsule enters the trigger zone on the
##     free side.
##   • Approached from the PLATFORM (deck) side: the gate is BLOCKED. The
##     player must press E to open. This matches Kee Klamp-style fall-protection
##     gates whose hinge is sprung to swing AWAY from the platform — you can
##     climb up and shove through, but you can't accidentally fall through it.
##   • In both cases the gate AUTO-CLOSES after `auto_close_s` seconds (default
##     2.0) once the player has cleared the trigger.
##
## The leaf (its mesh + collision children) is re-parented under a HingePivot
## AnimatableBody3D so the swing geometry is physically present — the player
## can't walk through a closed gate from the platform side, and the open swing
## sweeps the trigger volume cleanly.
##
## Configurable per-instance:
##   open_angle_deg   how far the leaf swings open (default 90°)
##   swing_time       tween duration in seconds (default 0.45)
##   auto_close_s     how long the gate stays open after the player exits the
##                    trigger (default 2.0)
##   hinge_side_idx   which vertical edge the leaf is hinged on
##                    0 → -X edge (gate swings to +X side)
##                    1 → +X edge (gate swings to -X side)
##   free_side_idx    which side the player can push from (0=+X, 1=-X, 2=+Z, 3=-Z)
##                    The opposite side is the platform / requires-E side.
##
## Built inline by PlaceableCatalog._m_extruder_silo() at the top-of-ladder
## position. The mesh children are added BEFORE _ready, same convention as Door.

@export var open_angle_deg : float = 90.0
@export var swing_time     : float = 0.45
@export var auto_close_s   : float = 2.0
@export_enum("Hinge on -X edge", "Hinge on +X edge") var hinge_side_idx : int = 0
@export_enum("Push from +X", "Push from -X", "Push from +Z", "Push from -Z") var free_side_idx : int = 0

const _STATE_CLOSED   : int = 0
const _STATE_OPEN     : int = 1
const _STATE_MOVING   : int = 2

var _state         : int   = _STATE_CLOSED
var _player_near   : bool  = false
var _last_exit_t   : float = -1.0    # game-time of most recent trigger-exit
var _pivot         : AnimatableBody3D = null
var _tween         : Tween

func _ready() -> void:
	add_to_group("push_gate")
	_build_hinge_pivot()
	_build_trigger()
	set_process(true)

## Re-parent the leaf children under a HingePivot AnimatableBody3D at the chosen
## vertical edge. Rotating the pivot then sweeps the leaf like a real swing gate.
func _build_hinge_pivot() -> void:
	# Find the leaf width from the widest BoxMesh child (the swing bars), default
	# to 0.46 m to match the inline build in PlaceableCatalog.
	var width := 0.46
	for ch in get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is BoxMesh:
			width = maxf(width, ((ch as MeshInstance3D).mesh as BoxMesh).size.z)
	var hinge_sign : float = -1.0 if hinge_side_idx == 0 else 1.0
	_pivot = AnimatableBody3D.new()
	_pivot.name = "HingePivot"
	# The gate sits along ±Z (top-of-ladder is at the -X face of the silo, so
	# the gate runs in Z). Hinge edge offset is along Z by half-width.
	_pivot.position = Vector3(0.0, 0.0, hinge_sign * width * 0.5)
	add_child(_pivot)
	var to_move : Array = []
	for ch in get_children():
		if ch == _pivot:
			continue
		if ch is MeshInstance3D or ch is CollisionShape3D:
			to_move.append(ch)
	for ch in to_move:
		var prev_pos: Vector3 = (ch as Node3D).position
		ch.get_parent().remove_child(ch)
		_pivot.add_child(ch)
		(ch as Node3D).position = prev_pos - _pivot.position

func _build_trigger() -> void:
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_mask = 1
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.4, 2.2, 1.4)
	cs.shape = box
	cs.position = Vector3(0.0, 0.5, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

# =============================================================================
func _player_is_on_free_side(body: Node3D) -> bool:
	# Local-space delta from gate origin to the player. The free side is one of
	# ±X / ±Z; sign tells us which half-space the body is in.
	var local := global_transform.affine_inverse() * (body as Node3D).global_position
	match free_side_idx:
		0: return local.x > 0.0   # +X
		1: return local.x < 0.0   # -X
		2: return local.z > 0.0   # +Z
		_: return local.z < 0.0   # -Z

func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	# Auto-push from the free side: open immediately without prompt.
	if _player_is_on_free_side(body) and _state == _STATE_CLOSED:
		_open()

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	_last_exit_t = Time.get_ticks_msec() / 1000.0
	EventBus.interaction_prompt_hide.emit(self)

# =============================================================================
func _process(_dt: float) -> void:
	if _state == _STATE_OPEN and not _player_near and _last_exit_t > 0.0:
		var now := Time.get_ticks_msec() / 1000.0
		if now - _last_exit_t >= auto_close_s:
			_close()

func crosshair_prompt(player: Node3D) -> String:
	if not _player_near:
		return ""
	if _state == _STATE_MOVING:
		return ""
	if _state == _STATE_OPEN:
		return ""
	# Closed + nearby. Free side auto-opened on entry, so if we're here on the
	# free side it means we haven't quite triggered yet — show "push" hint.
	# Platform side requires the E press.
	if _player_is_on_free_side(player):
		return "Push to open"
	return "Open gate"

func crosshair_interact(_player: Node3D) -> void:
	if _state != _STATE_CLOSED:
		return
	# Either side can open via E; the platform side REQUIRES it.
	if _player_near:
		_open()

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or _state != _STATE_CLOSED:
		return
	var is_interact : bool = false
	if InputMap.has_action("interact"):
		is_interact = event.is_action_pressed("interact")
	if (not is_interact) and event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_E:
			is_interact = true
	if is_interact:
		_open()
		get_viewport().set_input_as_handled()

# =============================================================================
func _open() -> void:
	if _state != _STATE_CLOSED or _pivot == null:
		return
	_state = _STATE_MOVING
	var hinge_sign : float = -1.0 if hinge_side_idx == 0 else 1.0
	# Swing AWAY from the platform — toward the free side.
	# Gate runs along Z, hinged at one Z edge; rotation about Y opens it
	# into +X (free=+X) or -X (free=-X).
	var swing_sign : float = 1.0
	match free_side_idx:
		0: swing_sign = -hinge_sign   # +X free → rotate so leaf moves to +X
		1: swing_sign =  hinge_sign
		_: swing_sign = -hinge_sign   # +Z/-Z fall back to hinge_sign convention
	var open_rad : float = deg_to_rad(open_angle_deg) * swing_sign
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_pivot, "rotation:y", open_rad, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_callback(func(): _state = _STATE_OPEN)
	EventBus.interaction_prompt_hide.emit(self)

func _close() -> void:
	if _state != _STATE_OPEN or _pivot == null:
		return
	_state = _STATE_MOVING
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_pivot, "rotation:y", 0.0, swing_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_tween.tween_callback(func(): _state = _STATE_CLOSED)
