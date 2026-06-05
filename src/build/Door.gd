extends StaticBody3D
class_name Door

## A placed, interactive HINGED door.
##
## The leaf (mesh + collision children) is re-parented under a HingePivot
## Node3D that sits at one vertical edge of the door. Pressing the interact
## key while standing in front tweens HingePivot.rotation.y between 0 and
## `open_angle_rad` so the door swings open like a real hinged door, not a
## sectional / roller door.
##
## Configurable per-instance:
##   open_angle_deg  swing angle (default 90°)
##   slide_time      tween duration in seconds
##   hinge_side      +1 = hinge on the -X edge (door swings to +X side)
##                   -1 = hinge on the +X edge (door swings to -X side)
##   swing_direction +1 = swing toward +Z, -1 = swing toward -Z
##
## Built by PlaceableCatalog.build_door() / the 4-point surface tool; those
## set `open_angle_deg` + add the Mesh + Col children before _ready runs.

@export var open_angle_deg : float = 90.0    # how far the door swings open
@export var slide_time     : float = 0.9     # seconds per full open / close
@export_enum("Hinge on -X edge", "Hinge on +X edge") var hinge_side_idx : int = 0
@export_enum("Swing toward +Z", "Swing toward -Z") var swing_direction_idx : int = 1

var _is_open    : bool  = false
var _moving     : bool  = false
var _player_near: bool  = false

# The Node3D the leaf rotates about — created in _ready, parented to self.
var _pivot      : Node3D = null
var _tween      : Tween

# =============================================================================
func _ready() -> void:
	add_to_group("door")
	_build_hinge_pivot()
	_build_trigger()

## Re-parent the leaf (Mesh + Col children built by PlaceableCatalog.build_door)
## under a HingePivot Node3D that sits at one vertical edge of the leaf. Once
## reparented, rotating the pivot around its local Y axis swings the leaf like
## a real hinged door.
func _build_hinge_pivot() -> void:
	# Find the leaf's width by inspecting the largest BoxMesh child — fall back
	# to 1.2 m if nothing matches (legacy save data, etc.).
	var width := 1.2
	for ch in get_children():
		if ch is MeshInstance3D and (ch as MeshInstance3D).mesh is BoxMesh:
			width = maxf(width, ((ch as MeshInstance3D).mesh as BoxMesh).size.x)
	# Hinge at the chosen edge — sign matches `hinge_side_idx`.
	var hinge_sign : float = -1.0 if hinge_side_idx == 0 else 1.0
	_pivot = Node3D.new()
	_pivot.name = "HingePivot"
	_pivot.position = Vector3(hinge_sign * width * 0.5, 0.0, 0.0)
	add_child(_pivot)
	# Gather the leaf children, re-parent under pivot, shift each so they keep
	# their world position when the pivot is at the edge.
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
		# Compensate the pivot offset so the visual stays put when closed.
		(ch as Node3D).position = prev_pos - _pivot.position

func _build_trigger() -> void:
	# Proximity zone so the player gets an "Open door" prompt and can interact.
	# Wider than the door itself so you can approach from either side.
	var area := Area3D.new()
	area.name = "Trigger"
	area.collision_mask = 1            # player capsule is on layer 1
	area.monitoring = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2.6, 2.6, 3.0)   # cover both sides of the doorway
	cs.shape = box
	cs.position = Vector3(0.0, 1.2, 0.0)
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)

# =============================================================================
func _on_body_entered(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = true
	EventBus.interaction_prompt_show.emit(self, _prompt_text())

func _on_body_exited(body: Node3D) -> void:
	if body.name != "Player":
		return
	_player_near = false
	EventBus.interaction_prompt_hide.emit(self)

func _prompt_text() -> String:
	return "Close door" if _is_open else "Open door"

func _unhandled_input(event: InputEvent) -> void:
	if not _player_near or _moving:
		return
	if event.is_action_pressed("interact"):
		toggle()
		get_viewport().set_input_as_handled()

# =============================================================================
func toggle() -> void:
	if _moving or _pivot == null:
		return
	_is_open = not _is_open
	_moving = true
	if _tween and _tween.is_valid():
		_tween.kill()
	# +Z swing means positive yaw around the -X hinge edge; flip for the other
	# combinations. See class header for the convention.
	var hinge_sign      : float = -1.0 if hinge_side_idx == 0 else 1.0
	var swing_sign      : float = 1.0 if swing_direction_idx == 0 else -1.0
	var open_angle_rad  : float = deg_to_rad(open_angle_deg) * hinge_sign * swing_sign
	var target_rot      : float = open_angle_rad if _is_open else 0.0
	_tween = create_tween()
	_tween.tween_property(_pivot, "rotation:y", target_rot, slide_time) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_callback(_on_move_done)
	if _player_near:
		EventBus.interaction_prompt_show.emit(self, _prompt_text())

func _on_move_done() -> void:
	_moving = false
