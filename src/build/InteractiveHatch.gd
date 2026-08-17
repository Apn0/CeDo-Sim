extends AnimatableBody3D
class_name InteractiveHatch

## Interactive Hinged Machine Door / Inspection Hatch
## Responds to player crosshair look + [E] interact keypress.
## Swings smoothly open and closed on its hinge axis, revealing machine internals.

@export var hatch_name : String = "Inspection Door"
@export var open_angle_deg : float = 105.0
@export var open_time : float = 0.55
@export var hinge_axis : Vector3 = Vector3.UP

var is_open : bool = false
var _moving : bool = false
var _closed_rot : Vector3 = Vector3.ZERO
var _open_rot : Vector3 = Vector3.ZERO
var _tween : Tween = null

func _ready() -> void:
	add_to_group("interactable")
	_closed_rot = rotation
	var target_axis : Vector3 = hinge_axis.normalized()
	_open_rot = _closed_rot + target_axis * deg_to_rad(open_angle_deg)

func crosshair_prompt(_player: Node3D) -> String:
	if _moving:
		return ""
	if is_open:
		return "[E] Close %s" % hatch_name
	return "[E] Open %s" % hatch_name

func crosshair_interact(_player: Node3D) -> void:
	if _moving:
		return
	_moving = true
	is_open = not is_open
	var target_rot : Vector3 = _open_rot if is_open else _closed_rot

	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	_tween.tween_property(self, "rotation", target_rot, open_time)
	_tween.tween_callback(func():
		_moving = false
	)

	# Sound trigger
	if Engine.has_singleton("AudioManager") or get_tree().root.has_node("AudioManager"):
		var am = get_tree().root.get_node_or_null("AudioManager")
		if am and am.has_method("play_spatial"):
			var sfx := "door_creak" if is_open else "door_slam"
			am.call("play_spatial", sfx, global_position)
